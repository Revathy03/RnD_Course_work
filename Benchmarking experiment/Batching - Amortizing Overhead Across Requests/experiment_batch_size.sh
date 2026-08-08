#!/bin/bash

# GDS Batch Size Scaling Experiment Script (Optimized & Fast)
# Investigates throughput and latency as a function of batch size
# Mode: 0 (Baseline GDS), 6 (GPU_BATCH)

GDSIO_PATH="/usr/local/cuda/gds/tools/gdsio"
TEST_FILE="/mnt/gdstest/batch_size_test_file"
RESULTS_CSV="/mnt/gdstest/batch_size_experiment/batch_size_results_$(date +%Y%m%d_%H%M%S).csv"

# Configurations
BATCH_SIZES=(1 2 4 8 16 32 64 128)
IO_SIZES=("4K" "1M")
WARMUP_RUNS=1
MEASURE_RUNS=3

# Ensure results directory exists
mkdir -p /mnt/gdstest/batch_size_experiment

# Header for CSV
echo "XferType,IOSize,BatchSize,Run,Throughput_GiBps,AvgLatency_usec,TotalTime_sec" > "$RESULTS_CSV"

# Function to run gdsio and parse results
run_benchmark() {
    local x_type=$1
    local i_size=$2
    local b_size=$3
    local run_num=$4
    local is_warmup=$5
    local f_size=$6

    echo "Running Read: Mode=$x_type, IOSize=$i_size, BatchSize=$b_size, Run=$run_num (Warmup=$is_warmup, FileSize=$f_size)"

    if [ "$x_type" = "6" ]; then
        B_OPT="-B $b_size -b"
    else
        B_OPT=""
    fi

    OUTPUT=$($GDSIO_PATH -f "$TEST_FILE" -s "$f_size" -i "$i_size" -x "$x_type" $B_OPT -I 2 -T 0 -d 0 2>&1)
    
    if [ $? -ne 0 ]; then
        echo "Error running gdsio: $OUTPUT"
        return 1
    fi

    THROUGHPUT=$(echo "$OUTPUT" | grep -oP 'Throughput: \K[0-9.]+')
    LATENCY=$(echo "$OUTPUT" | grep -oP 'Avg_Latency: \K[0-9.]+')
    TOTAL_TIME=$(echo "$OUTPUT" | grep -oP 'total_time \K[0-9.]+')

    if [ "$is_warmup" = "false" ]; then
        echo "$x_type,$i_size,$b_size,$run_num,$THROUGHPUT,$LATENCY,$TOTAL_TIME" >> "$RESULTS_CSV"
    fi
}

# Function to prepare test file
prepare_file() {
    local s=$1
    echo "Preparing test file of size $s..."
    $GDSIO_PATH -f "$TEST_FILE" -s "$s" -i "1M" -x 0 -I 1 -T 0 -d 0 > /dev/null
}

# Run Experiment
for i in "${IO_SIZES[@]}"; do
    if [ "$i" = "4K" ]; then
        FILE_SIZE="512M"
    else
        FILE_SIZE="4G"
    fi
    
    prepare_file "$FILE_SIZE"
    
    # Baseline
    for ((r=1; r<=WARMUP_RUNS; r++)); do run_benchmark 0 "$i" 1 "$r" "true" "$FILE_SIZE"; done
    for ((r=1; r<=MEASURE_RUNS; r++)); do run_benchmark 0 "$i" 1 "$r" "false" "$FILE_SIZE"; done
    
    # Batch Scaling
    for b in "${BATCH_SIZES[@]}"; do
        for ((r=1; r<=WARMUP_RUNS; r++)); do run_benchmark 6 "$i" "$b" "$r" "true" "$FILE_SIZE"; done
        for ((r=1; r<=MEASURE_RUNS; r++)); do run_benchmark 6 "$i" "$b" "$r" "false" "$FILE_SIZE"; done
    done
    
    rm -f "$TEST_FILE"
done

echo "----------------------------------------------------"
echo "Experiment complete. Results saved to $RESULTS_CSV"

if command -v python3 &>/dev/null; then
    echo "Generating visualization..."
    python3 /mnt/gdstest/batch_size_experiment/plot_batch_size.py "$RESULTS_CSV"
fi
