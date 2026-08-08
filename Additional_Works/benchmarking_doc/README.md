# Benchmarking GPUDirect Storage (GDS) vs. POSIX I/O

This project documents a benchmarking journey to compare the performance of NVIDIA GPUDirect Storage (GDS) against traditional POSIX I/O paths. 

## The Story: From Contradiction to Discovery

### 1. The Initial Experiment (The 4KB Paradox)
**Experiment:** Measuring Throughput and Latency for random read operations.
- **Configuration:** 4KB block size, 4 threads.
- **Hypothesis:** GDS will take less time than POSIX because it bypasses the CPU and system DRAM.
- **Result:** **Contradiction.** POSIX was faster than GDS.

![The 4KB Paradox](Read/read_total_size_sweep_plots.png)

### 2. The Investigation: Why was POSIX faster?
We analyzed the results and identified two primary reasons for this behavior:
- **Management Overhead:** GDS has a fixed per-request setup time. At 4KB, this overhead is a large percentage of the total transfer time.
- **Bandwidth Under-utilization:** 4KB chunks are too small to saturate the high-bandwidth path.

### 3. The Turning Point: Thread Sweep
To test if bandwidth utilization was the problem, we performed a **Thread Sweep**:
- **Action:** Varied thread count from 1 to 16.
- **Finding:** GDS throughput scaled linearly with threads, while POSIX performance remained flat. This confirmed that GDS needs higher concurrency to hide its management overhead.

### 4. Discovery: The Impact of Block Size
We conducted a targeted sweep of block sizes (**2K to 16M**) with **8 threads** to find the exact point where GDS becomes superior:
- **Small Blocks (2K-8K):** GDS is highly inefficient, starting at only **~391 MB/s**. POSIX matches GDS at these sizes.
- **The Sweet Spot (1M-4M):** GDS efficiency peaks, reaching **~51.6 GB/s**.
- **The POSIX Ceiling:** Regardless of block size, POSIX cannot break past **~11.3 GB/s** in this system.

![Impact of Block Size](Read/targeted_block_sweep_plots.png)

### 5. The Verification: The Optimal Configuration
Based on these discoveries, we combined **large blocks** and **high concurrency**:
- **New Configuration:** 1MB block size, 8 threads.
- **Total Transfer:** 4GB per thread (32GB total).

### 6. The Final Result: Breaking the "POSIX Ceiling"
The results confirmed our theory. While POSIX reached a hard physical/software ceiling, GDS scaled almost linearly.

![The GDS Breakthrough](Read/read_1M_8thread_plots.png)

| Metric | POSIX (Standard) | GDS (Direct) | Improvement |
| :--- | :--- | :--- | :--- |
| **Peak Throughput** | ~11.3 GB/s | **~92.7 GB/s** | **8.1x Faster** |
| **Total Completion Time** | ~2,779 ms | **~342 ms** | **8.1x Less Time** |

### 7. The Stress Test: IOPS and Latency Scaling
To push GDS to its absolute limits, we shifted focus from throughput (GB/s) to **IOPS (Operations per Second)** and **Latency**.

**Experiment:** Random 1MB I/O across a thread sweep (4 to 128 threads).

#### The Read vs. Write Disparity
We discovered a significant performance gap between read and write operations:
- **Read Peak (1MB):** Reached **~7,617 IOPS** at 128 threads (**~7.6 GB/s**).
- **Write Peak (1MB):** Reached **~711 IOPS** at 4 threads (**~711 MB/s**).
- **Result:** Reads are approximately **10.7x faster** than writes in peak IOPS.

![Read IOPS Scaling](iops/read/read_iops_plot.png)

#### Why the gap?
- **Write Amplification:** SSD garbage collection and metadata updates add significant overhead to write operations.
- **Controller Buffering:** Reads benefit from prefetching, while writes eventually saturate the NVMe controller's SLC cache.

#### Latency Scaling: The Hardware Limit
As thread count increases, average latency grows monotonically. This is a classic demonstration of **Little's Law**: once the hardware queue depth is saturated, additional requests simply increase wait time without improving throughput.

![Write IOPS Scaling](iops/write/write_iops_plot.png)

## Conclusion
GDS is significantly more efficient than POSIX for high-throughput workloads. While POSIX is "snappy" for tiny random files due to OS-level caching, GDS is the superior choice for large-scale data (AI training, big data analytics) where throughput is critical and CPU cycles must be preserved.


---

## Directory Structure
- `/Read`: Main benchmarking scripts and total size sweep results.
- `/optimal_experiment`: Results for the optimized 1MB/8-thread configuration.
- `/varying_thread`: Data on how GDS scales with increased concurrency.
- `/iops`: IOPS and Latency scaling experiments for Read and Write.
