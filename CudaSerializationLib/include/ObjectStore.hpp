#ifndef OBJECT_STORE_HPP
#define OBJECT_STORE_HPP

#include <iostream>
#include <fstream>
#include <string>
#include <filesystem>
#include <unordered_map>
#include <vector>
#include <fcntl.h>
#include <unistd.h>
#include <cstring>
#include <stdexcept>
#include <cuda_runtime.h>

// GPUDirect Storage and CUDA headers
#include <cuda_runtime_api.h>
#include <cufile.h>

// Indexing headers
#include "cereal/archives/binary.hpp"
#include "cereal/types/unordered_map.hpp"

// Serialization header
#include "CudaSerialization.hpp"

namespace ObjectStore
{
    using namespace CudaSerialization;

    const size_t MAX_FILE_SIZE = 1024 * 1024 * 1024; // 1GB 
    const size_t GDS_ALIGNMENT = 65536;              // 64KB alignment for maximum compatibility 
    const std::string DATA_DIR = "data/";
    const std::string INDEX_FILE = DATA_DIR + "index.dat";

    struct ObjectMetadata
    {
        int fileIndex;
        size_t offset;
        size_t size;
        int numElements;

        template <class Archive>
        void serialize(Archive &ar)
        {
            ar(fileIndex, offset, size, numElements);
        }
    };

    namespace Internal {
        template <typename T>
        __global__ void get_sizes_kernel(T *objs, int n, size_t *sizes)
        {
            int i = blockIdx.x * blockDim.x + threadIdx.x;
            if (i < n)
            {
                SizeArchive ar;
                objs[i].serialize(ar);
                sizes[i] = ar.size;
            }
        }

        __global__ void compute_offsets_kernel(size_t *sizes, size_t *offsets, int n, size_t *total_size)
        {
            size_t current = 0;
            for (int i = 0; i < n; ++i)
            {
                offsets[i] = current;
                current += sizes[i];
            }
            *total_size = current;
        }

        template <typename T>
        __global__ void serialize_batch_kernel(T *objs, int n, size_t *offsets, void *buffer, size_t dataOffset)
        {
            int i = blockIdx.x * blockDim.x + threadIdx.x;
            if (i < n)
            {
                OutputArchive ar((uint8_t *)buffer + dataOffset + offsets[i]);
                objs[i].serialize(ar);
            }
        }

        template <typename T>
        __global__ void deserialize_batch_kernel(T *objs, int n, const size_t *offsets, const void *buffer, size_t dataOffset)
        {
            int i = blockIdx.x * blockDim.x + threadIdx.x;
            if (i < n)
            {
                InputArchive ar((const uint8_t *)buffer + dataOffset + offsets[i]);
                objs[i].serialize(ar);
            }
        }
    }

    class StorageManager
    {
    public:
        static StorageManager &instance()
        {
            static StorageManager inst;
            return inst;
        }

        ~StorageManager()
        {
            for (auto &pair : fileHandles) cuFileHandleDeregister(pair.second);
            for (auto &pair : fds) close(pair.second);
            cuFileDriverClose();
        }

        void saveIndex()
        {
            std::filesystem::create_directories(DATA_DIR);
            std::ofstream os(INDEX_FILE, std::ios::binary);
            if (os.is_open())
            {
                cereal::BinaryOutputArchive archive(os);
                archive(index, currentFileIndex);
            }
        }

        void loadIndex()
        {
            try {
                if (std::filesystem::exists(INDEX_FILE) && std::filesystem::file_size(INDEX_FILE) > 0)
                {
                    std::ifstream is(INDEX_FILE, std::ios::binary);
                    if (is.is_open())
                    {
                        cereal::BinaryInputArchive archive(is);
                        archive(index, currentFileIndex);
                    }
                }
            } catch (const std::exception& e) {
                std::cerr << "[ObjectStore] Warning: Failed to load index: " << e.what() << "\n";
                index.clear();
                currentFileIndex = 0;
            }
        }

        CUfileHandle_t getFileHandle(int fileIdx)
        {
            if (fileHandles.find(fileIdx) != fileHandles.end()) return fileHandles[fileIdx];
            std::string filename = DATA_DIR + "data_" + std::to_string(fileIdx) + ".bin";
            int fd = open(filename.c_str(), O_CREAT | O_RDWR | O_DIRECT, 0644);
            if (fd < 0) {
                std::cerr << "[ObjectStore] Error: Failed to open file " << filename 
                          << " (errno=" << errno << ": " << std::strerror(errno) << "). "
                          << "Check if filesystem supports O_DIRECT.\n";
                return nullptr;
            }
            CUfileDescr_t cf_descr;
            std::memset(&cf_descr, 0, sizeof(CUfileDescr_t));
            cf_descr.type = CU_FILE_HANDLE_TYPE_OPAQUE_FD;
            cf_descr.handle.fd = fd;
            CUfileHandle_t cf_handle;
            CUfileError_t err = cuFileHandleRegister(&cf_handle, &cf_descr);
            if (err.err != CU_FILE_SUCCESS) { 
                std::cerr << "[ObjectStore] Error: cuFileHandleRegister failed for " << filename << " (err=" << err.err << ")\n";
                close(fd); 
                return nullptr; 
            }
            fileHandles[fileIdx] = cf_handle;
            fds[fileIdx] = fd;
            return cf_handle;
        }

        std::unordered_map<int, ObjectMetadata> index;
        int currentFileIndex = 0;

    private:
        StorageManager() { 
            if (cuFileDriverOpen().err != CU_FILE_SUCCESS) {
                std::cerr << "[ObjectStore] GDS Driver failed to open.\n";
            }
            std::filesystem::create_directories(DATA_DIR);
            loadIndex(); 
        }
        std::unordered_map<int, CUfileHandle_t> fileHandles;
        std::unordered_map<int, int> fds;
    };

    template <typename T>
    inline void put(int objId, T *devPtr, int n = 1)
    {
        auto &mgr = StorageManager::instance();
        int devId = 0;
        cudaGetDevice(&devId);
        cudaSetDevice(devId); // Ensure context is active

        int threadsPerBlock = 256;
        int blocks = (n + threadsPerBlock - 1) / threadsPerBlock;

        size_t *d_sizes, *d_offsets, *d_total_size;
        cudaMalloc(&d_sizes, n * sizeof(size_t));
        cudaMalloc(&d_offsets, n * sizeof(size_t));
        cudaMalloc(&d_total_size, sizeof(size_t));

        Internal::get_sizes_kernel<<<blocks, threadsPerBlock>>>(devPtr, n, d_sizes);
        Internal::compute_offsets_kernel<<<1, 1>>>(d_sizes, d_offsets, n, d_total_size);
        cudaError_t kernel_err = cudaGetLastError();
        if (kernel_err != cudaSuccess) {
            std::cerr << "[ObjectStore] Error: Size calculation kernel failed for ID " << objId 
                      << " (err=" << cudaGetErrorString(kernel_err) << ")\n";
            cudaFree(d_sizes); cudaFree(d_offsets); cudaFree(d_total_size);
            return;
        }

        size_t total_data_size = 0;
        if (cudaMemcpy(&total_data_size, d_total_size, sizeof(size_t), cudaMemcpyDeviceToHost) != cudaSuccess) {
             std::cerr << "[ObjectStore] Error: cudaMemcpy failed for ID " << objId << "\n";
             cudaFree(d_sizes); cudaFree(d_offsets); cudaFree(d_total_size);
             return;
        }

        if (total_data_size == 0) {
            std::cerr << "[ObjectStore] Warning: Serialized size is 0 for ID " << objId << ". Check if objects are initialized.\n";
        }

        // Header size: numElements + offsets
        size_t headerSize = sizeof(size_t) + (n * sizeof(size_t));
        size_t total_buf_size = headerSize + total_data_size;
        size_t alignedBufSize = (total_buf_size + GDS_ALIGNMENT - 1) & ~(GDS_ALIGNMENT - 1);

        void *d_base_ptr = nullptr;
        cudaError_t err = cudaMalloc(&d_base_ptr, alignedBufSize + GDS_ALIGNMENT);
        if (err != cudaSuccess) {
            std::cerr << "[ObjectStore] Error: cudaMalloc failed for ID " << objId 
                      << " (size=" << (alignedBufSize + GDS_ALIGNMENT) 
                      << ", data=" << total_data_size 
                      << ", err=" << cudaGetErrorString(err) << ")\n";
            cudaFree(d_sizes); cudaFree(d_offsets); cudaFree(d_total_size);
            return;
        }
        void *devBuffer = (void*)(((uintptr_t)d_base_ptr + GDS_ALIGNMENT - 1) & ~(GDS_ALIGNMENT - 1));

        bool is_registered = false;
        if (cuFileBufRegister(devBuffer, alignedBufSize, 0).err == CU_FILE_SUCCESS) {
            is_registered = true;
        }

        // Pack header
        size_t n_size_t = (size_t)n;
        cudaMemcpy(devBuffer, &n_size_t, sizeof(size_t), cudaMemcpyHostToDevice);
        cudaMemcpy((uint8_t*)devBuffer + sizeof(size_t), d_offsets, n * sizeof(size_t), cudaMemcpyDeviceToDevice);

        // Pack data
        Internal::serialize_batch_kernel<<<blocks, threadsPerBlock>>>(devPtr, n, d_offsets, devBuffer, headerSize);
        cudaDeviceSynchronize();
        kernel_err = cudaGetLastError();
        if (kernel_err != cudaSuccess) {
            std::cerr << "[ObjectStore] Error: Serialization kernel failed for ID " << objId 
                      << " (err=" << cudaGetErrorString(kernel_err) << ")\n";
            if (is_registered) cuFileBufDeregister(devBuffer);
            cudaFree(d_base_ptr); cudaFree(d_sizes); cudaFree(d_offsets); cudaFree(d_total_size);
            return;
        }

        size_t fileSize = 0;
        std::string filename = DATA_DIR + "data_" + std::to_string(mgr.currentFileIndex) + ".bin";
        if (std::filesystem::exists(filename)) fileSize = std::filesystem::file_size(filename);
        size_t offset = (fileSize + GDS_ALIGNMENT - 1) & ~(GDS_ALIGNMENT - 1);
        if (offset + alignedBufSize > MAX_FILE_SIZE) { mgr.currentFileIndex++; offset = 0; }

        CUfileHandle_t handle = mgr.getFileHandle(mgr.currentFileIndex);
        if (handle)
        {
            if (cuFileWrite(handle, devBuffer, alignedBufSize, offset, 0) >= 0)
            {
                mgr.index[objId] = {mgr.currentFileIndex, offset, total_buf_size, n};
                mgr.saveIndex();
                std::cout << "[ObjectStore] GDS Success: Saved ID " << objId << " (" << n << " objects).\n";
            } else {
                std::cerr << "[ObjectStore] GDS Error: cuFileWrite failed.\n";
            }
        } else {
            std::cerr << "[ObjectStore] Error: Could not get file handle for ID " << objId << ".\n";
        }

        // Cleanup
        if (is_registered) cuFileBufDeregister(devBuffer);
        cudaFree(d_base_ptr);
        cudaFree(d_sizes);
        cudaFree(d_offsets);
        cudaFree(d_total_size);
    }

    template <typename T>
    inline void get(int objId, T *devPtr)
    {
        auto &mgr = StorageManager::instance();
        int devId = 0;
        cudaGetDevice(&devId);
        cudaSetDevice(devId);

        if (mgr.index.find(objId) == mgr.index.end()) return;
        ObjectMetadata meta = mgr.index[objId];

        size_t alignedBufSize = (meta.size + GDS_ALIGNMENT - 1) & ~(GDS_ALIGNMENT - 1);
        void *d_base_ptr = nullptr;
        cudaError_t err = cudaMalloc(&d_base_ptr, alignedBufSize + GDS_ALIGNMENT);
        if (err != cudaSuccess) {
            std::cerr << "[ObjectStore] Error: cudaMalloc failed during retrieval for ID " << objId 
                      << " (size=" << (alignedBufSize + GDS_ALIGNMENT) 
                      << ", err=" << cudaGetErrorString(err) << ")\n";
            return;
        }
        void *devBuffer = (void*)(((uintptr_t)d_base_ptr + GDS_ALIGNMENT - 1) & ~(GDS_ALIGNMENT - 1));

        bool is_registered = false;
        if (cuFileBufRegister(devBuffer, alignedBufSize, 0).err == CU_FILE_SUCCESS) {
            is_registered = true;
        }

        CUfileHandle_t handle = mgr.getFileHandle(meta.fileIndex);
        if (handle && cuFileRead(handle, devBuffer, alignedBufSize, meta.offset, 0) >= 0)
        {
            size_t n_size_t;
            cudaMemcpy(&n_size_t, devBuffer, sizeof(size_t), cudaMemcpyDeviceToHost);
            int n = (int)n_size_t;
            
            size_t headerSize = sizeof(size_t) + (n * sizeof(size_t));
            size_t *d_offsets = (size_t*)((uint8_t*)devBuffer + sizeof(size_t));

            int threadsPerBlock = 256;
            int blocks = (n + threadsPerBlock - 1) / threadsPerBlock;
            Internal::deserialize_batch_kernel<<<blocks, threadsPerBlock>>>(devPtr, n, d_offsets, devBuffer, headerSize);
            cudaDeviceSynchronize();
            cudaError_t kernel_err = cudaGetLastError();
            if (kernel_err != cudaSuccess) {
                std::cerr << "[ObjectStore] Error: Deserialization kernel failed for ID " << objId 
                          << " (err=" << cudaGetErrorString(kernel_err) << ")\n";
            } else {
                std::cout << "[ObjectStore] GDS Success: Loaded ID " << objId << ".\n";
            }
        } else {
            std::cerr << "[ObjectStore] GDS Error: cuFileRead failed.\n";
        }

        if (is_registered) cuFileBufDeregister(devBuffer);
        cudaFree(d_base_ptr);
    }
}

#endif // OBJECT_STORE_HPP
