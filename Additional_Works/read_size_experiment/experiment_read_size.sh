#!/bin/bash

# GDS Read Performance Experiment Script
# Compares performance for modes 0 and 6 with increasing file sizes
# Variables: File Size, IO Size (4K, 1M)
# Mode: 0 (GPU_DIRECT), 6 (GPU_BATCH)

GDSIO_PATH="/usr/local/cuda/gds/tools/gdsio"
TEST_FILE="/mnt/gdstest/read_test_file"
RESULTS_CSV="/mnt/gdstest/read_size_experiment/read_results_$(date +%Y%m%d_%H%M%S).csv"

# Configurations
XFER_TYPES=(0 6)
FILE_SIZES=("1G" "2G" "4G" "8G")
IO_SIZES=("4K" "1M")
WARMUP_RUNS=1
MEASURE_RUNS=3

# Ensure results directory exists
mkdir -p /mnt/gdstest/read_size_experiment

# Header for CSV
echo "XferType,FileSize,IOSize,Run,Throughput_GiBps,AvgLatency_usec,TotalTime_sec" > "$RESULTS_CSV"

# Function to run gdsio and parse results
run_benchmark() {
    local x_type=$1
    local f_size=$2
    local i_size=$3
    local run_num=$4
    local is_warmup=$5

    # Flush cache before read operations to ensure data is read from disk
    echo "Flushing OS page cache..."
    sync
    # Attempting to flush caches. Requires sudo or appropriate permissions.
    sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches' 2>/dev/null || echo "Warning: Could not flush cache (sudo required)"

    echo "Running Read: XferType=$x_type, FileSize=$f_size, IOSize=$i_size, Run=$run_num (Warmup=$is_warmup)"

    # -I 2 for randread
    # -T 0 means run until dataset size is completed.
    # -d 0 assumes GPU 0
    OUTPUT=$($GDSIO_PATH -f "$TEST_FILE" -s "$f_size" -i "$i_size" -x "$x_type" -I 2 -T 0 -d 0 2>&1)
    
    if [ $? -ne 0 ]; then
        echo "Error running gdsio: $OUTPUT"
        return 1
    fi

    # Parse throughput, latency, and total time
    THROUGHPUT=$(echo "$OUTPUT" | grep -oP 'Throughput: \K[0-9.]+')
    LATENCY=$(echo "$OUTPUT" | grep -oP 'Avg_Latency: \K[0-9.]+')
    TOTAL_TIME=$(echo "$OUTPUT" | grep -oP 'total_time \K[0-9.]+')

    if [ "$is_warmup" = "false" ]; then
        echo "$x_type,$f_size,$i_size,$run_num,$THROUGHPUT,$LATENCY,$TOTAL_TIME" >> "$RESULTS_CSV"
    fi
}

# Iterate through configurations
for s in "${FILE_SIZES[@]}"; do
    echo "----------------------------------------------------"
    echo "Preparing test file of size $s..."
    # Create the file once for this size using Mode 0 Write (-I 1)
    # We use a large IO size (1M) for fast writing.
    $GDSIO_PATH -f "$TEST_FILE" -s "$s" -i "1M" -x 0 -I 1 -T 0 -d 0 > /dev/null
    
    if [ $? -ne 0 ]; then
        echo "Failed to create test file. Skipping size $s."
        continue
    fi

    for x in "${XFER_TYPES[@]}"; do
        for i in "${IO_SIZES[@]}"; do
            
            # 1. Warm-up
            for ((r=1; r<=WARMUP_RUNS; r++)); do
                run_benchmark "$x" "$s" "$i" "$r" "true"
            done
            
            # 2. Measurement runs
            for ((r=1; r<=MEASURE_RUNS; r++)); do
                run_benchmark "$x" "$s" "$i" "$r" "false"
            done
        done
    done
    
    # Cleanup file after all tests for this size are done
    rm -f "$TEST_FILE"
done

echo "----------------------------------------------------"
echo "Experiment complete. Results saved to $RESULTS_CSV"

# Automatically generate plot
if command -v python3 &>/dev/null; then
    echo "Generating visualization..."
    python3 /mnt/gdstest/read_size_experiment/plot_results.py
fi
