#ifndef CUDA_SERIALIZATION_HPP
#define CUDA_SERIALIZATION_HPP

#include <cuda_runtime.h>
#include <stdint.h>
#include <string.h>

namespace CudaSerialization {

    __device__ inline size_t device_strlen(const char* s) {
        if (!s) return 0;
        size_t len = 0;
        while (s[len] != '\0') len++;
        return len;
    }

    struct Archive {};

    // --- SizeArchive ---
    struct SizeArchive {
        size_t size = 0;

        template<typename T>
        __device__ void serialize(const T& val) {
            size += sizeof(T);
        }

        __device__ void serialize(const char* s) {
            size_t len = device_strlen(s);
            size += sizeof(uint32_t); 
            size += len;             
        }

        template<typename T>
        __device__ void serialize(const T* ptr) {
            size += sizeof(T);
        }

        template<typename T, typename... Args>
        __device__ void operator()(const T& first, const Args&... args) {
            this->serialize(first);
            if constexpr (sizeof...(args) > 0) {
                (*this)(args...);
            }
        }
    };

    // --- OutputArchive ---
    struct OutputArchive {
        uint8_t* buffer;
        size_t offset = 0;

        __device__ OutputArchive(void* ptr) : buffer((uint8_t*)ptr) {}

        template<typename T>
        __device__ void serialize(const T& val) {
            // Use memcpy to avoid alignment issues in tight packing
            memcpy(buffer + offset, &val, sizeof(T));
            offset += sizeof(T);
        }

        __device__ void serialize(const char* s) {
            uint32_t len = (uint32_t)device_strlen(s);
            memcpy(buffer + offset, &len, sizeof(uint32_t));
            offset += sizeof(uint32_t);
            if (len > 0) {
                memcpy(buffer + offset, s, len);
            }
            offset += len;
        }

        template<typename T>
        __device__ void serialize(const T* ptr) {
            memcpy(buffer + offset, ptr, sizeof(T));
            offset += sizeof(T);
        }

        template<typename T, typename... Args>
        __device__ void operator()(const T& first, const Args&... args) {
            this->serialize(first);
            if constexpr (sizeof...(args) > 0) {
                (*this)(args...);
            }
        }
    };

    // --- InputArchive ---
    struct InputArchive {
        const uint8_t* buffer;
        size_t offset = 0;

        __device__ InputArchive(const void* ptr) : buffer((const uint8_t*)ptr) {}

        template<typename T>
        __device__ void serialize(T& val) {
            // Use memcpy to avoid alignment issues in tight packing
            memcpy(&val, buffer + offset, sizeof(T));
            offset += sizeof(T);
        }

        __device__ void serialize(char* s) {
            uint32_t len;
            memcpy(&len, buffer + offset, sizeof(uint32_t));
            offset += sizeof(uint32_t);
            if (len > 0) {
                memcpy(s, buffer + offset, len);
            }
            s[len] = '\0';
            offset += len;
        }

        template<typename T>
        __device__ void serialize(T* ptr) {
            memcpy(ptr, buffer + offset, sizeof(T));
            offset += sizeof(T);
        }

        template<typename T, typename... Args>
        __device__ void operator()(T& first, Args&... args) {
            this->serialize(first);
            if constexpr (sizeof...(args) > 0) {
                (*this)(args...);
            }
        }
    };

} // namespace CudaSerialization

#endif // CUDA_SERIALIZATION_HPP
