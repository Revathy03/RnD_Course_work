#include "cuda_runtime.h"
#include <stdio.h>
#include <stdlib.h>
#include <chrono>
#include <iostream>
#include <fstream>
#include <fcntl.h>
#include <unistd.h>
#include <cerrno>
#include <cstring>
#include <cufile.h>
#include <vector>
#include <algorithm>
#include <numeric>

using namespace std;
using namespace chrono;

// ── Config ────────────────────────────────────────────────────────────────
static const int WARMUP_ITERS  = 5;     // discarded
static const int BENCH_ITERS   = 200;   // recorded
static const int TOTAL_ITERS   = WARMUP_ITERS + BENCH_ITERS;
static const int ELEMENTS      = 16384;
static const size_t SIZE       = ELEMENTS * sizeof(float);

// ── Stats helpers ─────────────────────────────────────────────────────────
struct Stats {
    double min, max, mean, median, p95, p99;
};

Stats compute_stats(vector<double>& v) {
    sort(v.begin(), v.end());
    Stats s;
    s.min    = v.front();
    s.max    = v.back();
    s.mean   = accumulate(v.begin(), v.end(), 0.0) / v.size();
    s.median = v[v.size() / 2];
    s.p95    = v[(size_t)(v.size() * 0.95)];
    s.p99    = v[(size_t)(v.size() * 0.99)];
    return s;
}

void print_stats(const char* label, Stats& s) {
    printf("%-26s  min=%8.2f  median=%8.2f  mean=%8.2f  p95=%8.2f  p99=%8.2f  max=%8.2f  [us]\n",
           label, s.min, s.median, s.mean, s.p95, s.p99, s.max);
}

// ── Timer macro ───────────────────────────────────────────────────────────
#define TIME_US(expr) ([&]() -> double {                          \
    auto _t0 = high_resolution_clock::now();                      \
    expr;                                                         \
    auto _t1 = high_resolution_clock::now();                      \
    return duration<double, micro>(_t1 - _t0).count();            \
}())

int main() {
    // Storage for every iteration's latencies
    // driver_open / handle_reg / malloc / buf_reg / read / buf_dereg /
    // handle_dereg / free / driver_close
    vector<double> lat_driver_open(BENCH_ITERS),
                   lat_handle_reg (BENCH_ITERS),
                   lat_malloc     (BENCH_ITERS),
                   lat_buf_reg    (BENCH_ITERS),
                   lat_read       (BENCH_ITERS),
                   lat_buf_dereg  (BENCH_ITERS),
                   lat_handle_dereg(BENCH_ITERS),
                   lat_free       (BENCH_ITERS),
                   lat_driver_close(BENCH_ITERS);

    printf("Running %d warmup + %d benchmark iterations...\n",
           WARMUP_ITERS, BENCH_ITERS);

    for (int iter = 0; iter < TOTAL_ITERS; iter++) {
        bool is_warmup = (iter < WARMUP_ITERS);
        int  idx       = iter - WARMUP_ITERS;   // only valid when !is_warmup

        // Open file fresh each iteration so fd state is clean.
        // Use O_DIRECT to bypass the OS page cache — required for true GDS.
        int fd = open("floats_64kb.bin", O_RDONLY | O_DIRECT);
        if (fd < 0) { cerr << "open failed: " << strerror(errno) << "\n"; return 1; }

        // ── 1. cuFileDriverOpen ───────────────────────────────────────────
        double t_driver_open = TIME_US({
            CUfileError_t st = cuFileDriverOpen();
            if (st.err != CU_FILE_SUCCESS) {
                cerr << "cuFileDriverOpen failed\n"; close(fd); return 1;
            }
        });

        // ── 2. cuFileHandleRegister ───────────────────────────────────────
        CUfileDescr_t  cf_descr  = {};
        CUfileHandle_t cf_handle = {};
        cf_descr.handle.fd = fd;
        cf_descr.type      = CU_FILE_HANDLE_TYPE_OPAQUE_FD;

        double t_handle_reg = TIME_US({
            CUfileError_t st = cuFileHandleRegister(&cf_handle, &cf_descr);
            if (st.err != CU_FILE_SUCCESS) {
                cerr << "cuFileHandleRegister failed: " << st.err << "\n";
                cuFileDriverClose(); close(fd); return 1;
            }
        });

        // ── 3. cudaMalloc ────────────────────────────────────────────────
        float* d_A = nullptr;
        double t_malloc = TIME_US({
            if (cudaMalloc(&d_A, SIZE) != cudaSuccess) {
                cerr << "cudaMalloc failed\n";
                cuFileHandleDeregister(cf_handle); cuFileDriverClose(); close(fd); return 1;
            }
        });

        // ── 4. cuFileBufRegister ──────────────────────────────────────────
        double t_buf_reg = TIME_US({
            CUfileError_t st = cuFileBufRegister(d_A, SIZE, 0);
            if (st.err != CU_FILE_SUCCESS) {
                cerr << "cuFileBufRegister failed: " << st.err << "\n";
                cudaFree(d_A); cuFileHandleDeregister(cf_handle);
                cuFileDriverClose(); close(fd); return 1;
            }
        });

        // ── 5. cuFileRead ─────────────────────────────────────────────────
        ssize_t bytes_read;
        double t_read = TIME_US({
            bytes_read = cuFileRead(cf_handle, d_A, SIZE, 0, 0);
        });
        if (bytes_read < 0) {
            cerr << "cuFileRead error: " << bytes_read << "\n"; return 1;
        }

        // ── 6. cuFileBufDeregister ────────────────────────────────────────
        double t_buf_dereg = TIME_US({
            cuFileBufDeregister(d_A);
        });

        // ── 7. cuFileHandleDeregister ─────────────────────────────────────
        double t_handle_dereg = TIME_US({
            cuFileHandleDeregister(cf_handle);
        });

        // ── 8. cudaFree ───────────────────────────────────────────────────
        double t_free = TIME_US({
            cudaFree(d_A);
        });

        // ── 9. cuFileDriverClose ──────────────────────────────────────────
        double t_driver_close = TIME_US({
            cuFileDriverClose();
        });

        close(fd);

        // Record only after warmup
        if (!is_warmup) {
            lat_driver_open  [idx] = t_driver_open;
            lat_handle_reg   [idx] = t_handle_reg;
            lat_malloc       [idx] = t_malloc;
            lat_buf_reg      [idx] = t_buf_reg;
            lat_read         [idx] = t_read;
            lat_buf_dereg    [idx] = t_buf_dereg;
            lat_handle_dereg [idx] = t_handle_dereg;
            lat_free         [idx] = t_free;
            lat_driver_close [idx] = t_driver_close;
        }

        if ((iter + 1) % 50 == 0)
            printf("  iter %d/%d done\n", iter + 1, TOTAL_ITERS);
    }

    // ── Print summary ─────────────────────────────────────────────────────
    printf("\n%-26s  %8s   %8s   %8s   %8s   %8s   %8s\n",
           "Operation", "min", "median", "mean", "p95", "p99", "max");
    printf("%s\n", string(100, '-').c_str());

    auto print = [&](const char* label, vector<double>& v) {
        Stats s = compute_stats(v);
        print_stats(label, s);
    };

    print("cuFileDriverOpen",    lat_driver_open);
    print("cuFileHandleRegister",lat_handle_reg);
    print("cudaMalloc",          lat_malloc);
    print("cuFileBufRegister",   lat_buf_reg);
    print("cuFileRead",          lat_read);
    print("cuFileBufDeregister", lat_buf_dereg);
    print("cuFileHandleDeregister", lat_handle_dereg);
    print("cudaFree",            lat_free);
    print("cuFileDriverClose",   lat_driver_close);

    // ── Write CSV ─────────────────────────────────────────────────────────
    ofstream csv("gds_latencies.csv");
    csv << "operation,min_us,median_us,mean_us,p95_us,p99_us,max_us\n";

    auto write_row = [&](const char* label, vector<double>& v) {
        Stats s = compute_stats(v);
        csv << label << "," << s.min << "," << s.median << ","
            << s.mean << "," << s.p95 << "," << s.p99 << "," << s.max << "\n";
    };

    write_row("cuFileDriverOpen",    lat_driver_open);
    write_row("cuFileHandleRegister",lat_handle_reg);
    write_row("cudaMalloc",          lat_malloc);
    write_row("cuFileBufRegister",   lat_buf_reg);
    write_row("cuFileRead",          lat_read);
    write_row("cuFileBufDeregister", lat_buf_dereg);
    write_row("cuFileHandleDeregister", lat_handle_dereg);
    write_row("cudaFree",            lat_free);
    write_row("cuFileDriverClose",   lat_driver_close);

    csv.close();
    printf("\nResults saved to gds_latencies.csv\n");
    return 0;
}
// nvcc gdslatency.cu -I/usr/local/cuda-13.1/targets/x86_64-linux/include/  -L/usr/local/cuda-13.1/targets/x86_64-linux/lib/ -lcufile -o gdslat