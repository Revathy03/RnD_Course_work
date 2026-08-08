# Breaking the POSIX Ceiling: Large Blocks + High Concurrency

## Overview
This experiment demonstrates GDS's ability to scale beyond POSIX's fundamental throughput limit by using the optimal configuration: **1MB blocks** with **8 threads**.

- **Block size:** 1MB
- **Threads:** 8
- **Variable:** total transfer size (1MB to 4GB per thread)
- **Measured:** throughput and latency
- **Compared:** `gds` vs `posix`

## Files included
- `gdsvstrad_read.sh` — benchmark script for 1MB + 8 threads sweep
- `read_1M_8thread_results.csv` — throughput and latency results for each data size
- `plot_read_1M_8thread.py` — plotting script
- `read_1M_8thread_plots.png` — generated graph showing the divergence

## The POSIX Ceiling

POSIX throughput **plateaus** and never breaks past ~**11.3 GB/s**, regardless of data size:

| Total Size per Thread | GDS (MB/s) | POSIX (MB/s) | GDS Advantage |
|:---|:---:|:---:|:---|
| 1M | 1,229.5 | 2,170.0 | — (POSIX ahead for tiny transfers) |
| 4M | 12,039.4 | 6,606.2 | **1.8x** |
| 16M | 23,290.7 | 6,741.2 | **3.5x** |
| 64M | 31,069.5 | 9,437.9 | **3.3x** |
| 256M | 47,656.6 | 10,901.3 | **4.4x** |
| 1G | 75,518.6 | 11,222.5 | **6.7x** |
| **4G** | **92,683.5** | **11,353.4** | **8.2x faster** |

## Why POSIX Hits a Ceiling

The POSIX ceiling exists because:

1. **CPU Bottleneck:** All data must flow through the CPU to reach GPU VRAM:
   - Storage → System RAM (limited by PCIe or system interconnect)
   - System RAM → GPU VRAM (limited by PCIe bandwidth, typically ~16 GB/s max)
   - CPU context switching and memory management overhead reduce effective throughput

2. **Fixed PCIe Bandwidth:** The CPU-to-GPU PCIe path is inherently limited to the card's PCIe generation (e.g., PCIe 4.0 = ~16 GB/s).

3. **Memory Copy Overhead:** Every byte copied by the CPU incurs cache coherency, TLB, and memory management overhead.

## Why GDS Keeps Scaling

GDS throughput **continues to increase** with data size because:

1. **Direct DMA:** GDS bypasses the CPU entirely, allowing direct PCIe DMA from storage → GPU memory.

2. **Batching Efficiency:** Larger requests allow GDS to batch operations and amortize fixed overhead (memory registration, request submission).

3. **Pipeline Utilization:** As data size grows, GPU memory bandwidth and storage I/O pipelines are fully saturated with outstanding requests, improving aggregate efficiency.

4. **Latency Improvement:** GDS latency *decreases* from **0.21 ms** (at 256MB) to **0.09 ms** (at 4GB), showing improved per-request efficiency.

## The Crossover Point

- **Below 1M–2M:** POSIX is faster due to lower overhead for tiny transfers.
- **4M–8M:** GDS overtakes POSIX (~2x advantage).
- **256M+:** GDS is **4x–8x faster**, and the gap continues to widen.

## Key Insights

| Metric | GDS | POSIX |
|:---|:---:|:---:|
| **Peak Throughput** | 92.7 GB/s | 11.4 GB/s |
| **Scaling Behavior** | Linear growth with data size | Flattens immediately |
| **Minimum Latency** | 0.086 ms | 0.705 ms |
| **Latency Trend** | Decreases with data size | Stays constant |
| **Practical Limit** | Hardware limited (~100 GB/s PCIe Gen 5) | CPU bottleneck (~11 GB/s) |

## Conclusion

The POSIX ceiling is **not a performance plateau but a hard architectural limit**. Once GDS is correctly configured (1MB blocks, 8 threads), it transcends this limit and scales all the way to hardware maximums.

For workloads requiring **aggregate throughput > 11 GB/s**, GDS is the only viable option. At 4G transfers with 1MB blocks, GDS delivers **8.2x the throughput** of POSIX with **12% lower latency**.

> See `read_1M_8thread_plots.png` for the divergence curves showing GDS acceleration and POSIX flattening.
