# CudaSerializationLib

A lightweight CUDA-friendly serialization + object store library designed for GPU-resident objects and direct NVMe↔GPU transfers using NVIDIA GPUDirect Storage (GDS).

 It includes header-only CUDA device serialization primitives, a GPU-side object packing/unpacking pipeline, and a minimal `ObjectStore` that persists GPU buffers to disk using GDS.

---

## Contents & Layout

- `include/`
  - `CudaSerialization.hpp` — Device-side serialization primitives (SizeArchive, OutputArchive, InputArchive).
  - `ObjectStore.hpp` — High-level storage manager that packs GPU objects, writes to disk with GDS, and reads/deserializes back into device memory.
- `src/`
  - `gds_example.cu` — Example end-to-end application showing read-compute-write using GDS (migrated from `main.cu`).
  - `main_toy_example.cu` — Toy example / additional entrypoint.
- `examples/`
  - `basic_test.cpp` — Host-side cereal-based test harness demonstrating CPU serialization (useful for interoperability testing).
- `Makefile` — Build helper for examples (`nvcc` + link flags).
- `cufile.log` — Example run log (kept for reference).

---

## Features

- Device-side (CUDA) serialization primitives suitable for packing arrays and simple structs directly on the GPU.
  - `SizeArchive` — Calculate the packed size on-device
  - `OutputArchive` — Serialize to a device buffer
  - `InputArchive` — Deserialize from a device buffer

- Batch serialization/deserialization kernels to serialize/deserialize many objects in parallel on the GPU.

- `ObjectStore::StorageManager` —
  - Maintains a persistent index of objects (`index.dat`) using `cereal` for CPU-side indexing.
  - Writes GPU-packed buffers to disk using `cuFileWrite` (GDS) with alignment to `GDS_ALIGNMENT`.
  - Reads objects back into device memory using `cuFileRead` and deserializes them with GPU kernels.
  - Handles buffer registration (`cuFileBufRegister`) for GDS transfers and keeps per-file `CUfileHandle_t` handles.

- Convenient host examples and a small test harness.

---

## Implementation Details (Important internals)

### Device Serialization Primitives (`CudaSerialization.hpp`)

- Implemented as device functions and device structs so serialization runs on the GPU with no host involvement.
- `device_strlen` counts characters in device memory.
- `SizeArchive` scans fields and accumulates required bytes (`size`) without actually copying data.
- `OutputArchive` packs values into a contiguous `uint8_t*` buffer using `memcpy` to avoid alignment pitfalls.
- `InputArchive` reads values back from the device buffer into user structures.
- Supports POD types and null-terminated C strings (packed as `uint32_t` length + bytes).
- Variadic `operator()` template enables serializing multiple fields conveniently.

### Object Pack/Unpack Kernels (`ObjectStore.hpp`, `Internal` namespace)

- `get_sizes_kernel` (device): For each object, compute packed size via `SizeArchive`.
- `compute_offsets_kernel` (device): Compute per-object offsets and total data size (simple inclusive loop on device; could be optimized with prefix-sum on host or thrust).
- `serialize_batch_kernel` / `deserialize_batch_kernel` (device): Each thread serializes/deserializes a single object concurrently.
- `deserialize_range_kernel`: Deserialize a contiguous sub-range of objects for partial reads.

Notes:
- Kernels assume objects provide a `serialize(Archive &)` method compatible with the device archives.
- All kernels use `cudaDeviceSynchronize` and check `cudaGetLastError()` for robustness in the POC.

### Storage Manager

- Uses `cuFileDriverOpen()` at construction and `cuFileDriverClose()` at destruction.
- Keeps a map of open `CUfileHandle_t` per data file and returns handles from `getFileHandle()`.
- Stores objects into files named `data/data_<index>.bin` with 64KB alignment (`GDS_ALIGNMENT`).
- Index (`index.dat`) persisted via `cereal` to map object ID → `(fileIndex, offset, size, numElements)`.
- `put(objId, devPtr, n)` packs `n` objects from device memory into a single aligned buffer and writes it atomically via `cuFileWrite()`.
- `get(objId, devPtr)` reads an aligned buffer with `cuFileRead()` and launches deserialization kernels to reconstruct objects into `devPtr`.

Memory management & safety:
- Device allocations for packing are aligned and optionally registered with `cuFileBufRegister`.
- Temporary device allocations are freed after write/read; in production these should be pooled.

---

## Building

This project is a header-first library with examples. The `Makefile` is a thin convenience wrapper; adjust `NVCC`, include paths, and `-L`/`-l` flags to your system.

Quick build (example):

```bash
cd /mnt/gdstest/CudaSerializationLib
make
```

Common compile flags used in examples:
- `nvcc` for `.cu` files
- Link `-lcufile` (GPUDirect Storage), `-lcuda` and system libs for cereal if needed

If `cereal` is not installed system-wide, install it or adjust includes to point to `third_party/cereal`.

---

## Running Examples

1. Generate a test file or use provided generator (if available)
2. Run `gds_example` (requires GDS driver + permissions):

```bash
# from CudaSerializationLib
./gds_example <M> <N>
# example: ./gds_example 1024 1024
```

3. Run `basic_test.cpp` as a host-side check (requires cereal headers and linking with stdc++):

```bash
g++ examples/basic_test.cpp -I/usr/include -o basic_test
./basic_test
```

---

## API Reference (Top-level)

- `ObjectStore::StorageManager::instance()` — Singleton access to the store manager.
- `ObjectStore::put(int objId, T* devPtr, int n=1)` — Serialize `n` objects pointed by `devPtr` and persist to disk.
- `ObjectStore::get(int objId, T* devPtr)` — Load object and deserialize into device memory pointer `devPtr`.
- `ObjectStore::getRange(int objId, T* devPtr, int startIndex, int count)` — Load subset of an object array.

Note: `T` must implement a device `serialize(Archive&)` function compatible with `CudaSerialization`.

---

## Limitations & TODOs

- `compute_offsets_kernel` performs a naive loop; replace with fast prefix-sum (Thrust) for large batches.
- Current implementation allocates temporary device buffers per `put/get`; implement pooling to avoid repeated `cudaMalloc`/`cudaFree` overhead.
- `StorageManager` currently opens files with `O_DIRECT`; ensure filesystem supports it or gracefully fallback.
- Error handling is best-effort; production code should add retries and stronger diagnostics.
- No unit tests yet; add GPU unit test harness and CI integration.

---

## Contact / Maintainer

This code was reorganized from a research prototype. If you want me to:
- add a `CMake` target and CI pipeline,
- implement buffer pooling and a small benchmark harness, or
- add unit tests and example data generators,

say which one and I will implement it next.
