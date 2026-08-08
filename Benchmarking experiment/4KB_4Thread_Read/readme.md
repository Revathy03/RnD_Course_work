# Experiment: Random Read Performance vs. Total File Size

## Overview
This experiment evaluates the performance of GPUDirect Storage (GDS) compared to traditional POSIX I/O for random read operations. The benchmark measures throughput and latency as the total amount of data transferred increases, while keeping the block size and thread count fixed.

## Parameters
- **Thread Count:** 4
- **Block Size (Request Size):** 4K
- **I/O Type:** Random Read (`randread`)
- **Transfer Modes:**
    - **GDS (Mode 0):** GPUDirect Storage (Direct DMA to GPU memory)
    - **POSIX (Mode 2):** Standard CPU-buffered I/O (Storage -> CPU -> GPU)
- **Data Range:** 4KB to 4GB (total transfer size per thread)

## Methodology
The `gdsio` utility was used to perform the benchmarks. Each test point is an average of 3 iterations.
The total transfer size was swept from 4KB to 4GB (per thread) in powers of 2.

## Results

### Throughput and Latency Plots
![Random Read Results](read_total_size_sweep_plots.png)

### Summary Table (Selected Points)
| Total Size (per thread) | Mode | Throughput (MB/s) | Avg Latency (ms) |
| :--- | :--- | :--- | :--- |
| 1M | GDS | 487.68 | 0.0313 |
| 1M | POSIX | 393.72 | 0.0388 |
| 128M | GDS | 1009.88 | 0.0155 |
| 128M | POSIX | 1334.01 | 0.0117 |
| 1G | GDS | 1049.39 | 0.0149 |
| 1G | POSIX | 1320.07 | 0.0118 |
| 4G | GDS | 1048.28 | 0.0149 |
| 4G | POSIX | 1340.78 | 0.0117 |

## Analysis
- **Small Data Sizes:** For total transfer sizes below 1MB, GDS remains competitive in throughput, but POSIX still holds an edge for some points.
- **Large Data Sizes:** As total transfer size increases beyond 16MB, POSIX (Mode 2) consistently outperforms GDS in this 4K random read test with 4 threads, directly contradicting our original hypothesis that GDS would be superior in this regime.
- **Saturation:** POSIX reaches a higher throughput plateau (~1340 MB/s) than GDS (~1050 MB/s) under these conditions.
- **Latency:** Average latency decreases as total transfer size increases, stabilizing around 0.015ms for GDS and 0.012ms for POSIX.

### Why does POSIX outperform GDS here?
The result contradicts our hypothesis. In this low-concurrency, small-block regime, GDS setup and synchronization overhead appear to outweigh its direct DMA benefit. POSIX Mode 2 instead delivers more consistent performance and lower average latency for the given hardware and workload.
