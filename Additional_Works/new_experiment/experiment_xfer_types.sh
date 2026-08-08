#!/bin/bash

# GDS Transfer Type Comparison Experiment Script
# Compares performance across all transfer types (-x 0-7)
# Variables: File Size, IO Size
# Measurements: Throughput, Avg Latency, Total Time
# Method: 1 warm-up iteration + 3 timed iterations

GDSIO_PATH="/usr/local/cuda/gds/tools/gdsio"
TEST_FILE="/mnt/gdstest/test_data_xfer"
RESULTS_CSV="/mnt/gdstest/xfer_results_$(date +%Y%m%d_%H%M%S).csv"

# Configurations
XFER_TYPES=(0 1 2 3 4 5 6 7)
FILE_SIZES=("512M" "1G" "4G" "8G")
IO_SIZES=("4K" "1M")
WARMUP_RUNS=1
MEASURE_RUNS=3

# Header for CSV
echo "XferType,FileSize,IOSize,Run,Throughput_GiBps,AvgLatency_usec,TotalTime_sec" > "$RESULTS_CSV"

# Function to run gdsio and parse results
run_benchmark() {
    local x_type=$1
    local f_size=$2
    local i_size=$3
    local run_num=$4
    local is_warmup=$5

    echo "Running: XferType=$x_type, FileSize=$f_size, IOSize=$i_size, Run=$run_num (Warmup=$is_warmup)"

    # We use -I 1 (Write) for simplicity in this comparison, 
    # as it ensures data transfer costs are measured.
    # -T 0 means run until dataset size is completed.
    # -d 0 assumes GPU 0
    OUTPUT=$($GDSIO_PATH -f "$TEST_FILE" -s "$f_size" -i "$i_size" -x "$x_type" -I 1 -T 0 -d 0 2>&1)
    
    if [ $? -ne 0 ]; then
        echo "Error running gdsio: $OUTPUT"
        return 1
    fi

    # Parse throughput, latency, and total time
    # IoType: WRITE XferType: GPUD Threads: 1 DataSetSize: ... Throughput: 1.199890 GiB/sec, Avg_Latency: 812.088748 usecs ops: 631 total_time 0.513556 secs
    THROUGHPUT=$(echo "$OUTPUT" | grep -oP 'Throughput: \K[0-9.]+')
    LATENCY=$(echo "$OUTPUT" | grep -oP 'Avg_Latency: \K[0-9.]+')
    TOTAL_TIME=$(echo "$OUTPUT" | grep -oP 'total_time \K[0-9.]+')

    if [ "$is_warmup" = "false" ]; then
        echo "$x_type,$f_size,$i_size,$run_num,$THROUGHPUT,$LATENCY,$TOTAL_TIME" >> "$RESULTS_CSV"
    fi
}

# Iterate through configurations
for x in "${XFER_TYPES[@]}"; do
    for s in "${FILE_SIZES[@]}"; do
        for i in "${IO_SIZES[@]}"; do
            
            # 1. Warm-up
            for ((r=1; r<=WARMUP_RUNS; r++)); do
                run_benchmark "$x" "$s" "$i" "$r" "true"
            done
            
            # 2. Measurement runs
            for ((r=1; r<=MEASURE_RUNS; r++)); do
                run_benchmark "$x" "$s" "$i" "$r" "false"
            done
            
            # Clean up test file between configs if needed, or reuse.
            # Reusing same file for writes is generally fine as it gets overwritten.
            rm -f "$TEST_FILE"
        done
    done
done

echo "Experiment complete. Results saved to $RESULTS_CSV"
