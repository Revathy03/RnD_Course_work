#!/bin/bash

# Output CSV
OUTFILE="read_1M_8thread_results.csv"

# Config
THREADS=8
BLOCK_SIZE="1M"
# Generate SIZES array from 2^20 (1M) to 2^32 (4G)
SIZES=()
for ((p=20; p<=32; p++)); do
    VAL=$((2**p))
    if [ $VAL -lt 1024 ]; then
        SIZES+=("$VAL")
    elif [ $VAL -lt 1048576 ]; then
        SIZES+=("$((VAL/1024))K")
    elif [ $VAL -lt 1073741824 ]; then
        SIZES+=("$((VAL/1048576))M")
    else
        SIZES+=("$((VAL/1073741824))G")
    fi
done
ITER=3
FILEdr="/mnt/gdstest/benchmarking_doc/Read"
GPU_ID=0

# Auto-setup: Ensure data files exist for the requested number of threads
echo "Checking/Creating data files for $THREADS threads in $FILEdr..."
mkdir -p "$FILEdr"
for ((i=0; i<$THREADS; i++)); do
    FILE="$FILEdr/gdsio.$i"
    if [ ! -f "$FILE" ]; then
        echo "  Creating $FILE (4GB)..."
        # Try fallocate first (fast), fallback to truncate if needed
        fallocate -l 4G "$FILE" 2>/dev/null || truncate -s 4G "$FILE"
    fi
done

# CSV header
echo "mode,io_type,total_size,block_size,threads,avg_throughput_MBps,avg_latency_ms,avg_total_time_ms" > $OUTFILE

run_test() {
    MODE=$1   # gds or posix

    for SIZE in "${SIZES[@]}"; do
        SUM_TP=0
        SUM_LAT=0
        SUM_TIME=0
        
        echo "Running $MODE READ total_size=$SIZE, block_size=$BLOCK_SIZE ($ITER iterations averaging)"

        for ((i=1; i<=ITER; i++)); do
            if [ "$MODE" == "gds" ]; then
                EXTRA="-x 0"   # GDS mode
            else
                EXTRA="-x 2"   # POSIX (compat mode)
            fi

            # Capture stdout/stderr and strip ANSI color codes
            # Using -I 0 for SEQUENTIAL READ
            OUTPUT=$(/usr/local/cuda/gds/tools/gdsio -D $FILEdr \
                -d $GPU_ID \
                -w $THREADS \
                -s $SIZE \
                -i $BLOCK_SIZE \
                -I 0 \
                $EXTRA 2>&1 | sed 's/\x1b\[[0-9;]*m//g')

            # Extract metrics
            TP_RAW=$(echo "$OUTPUT" | grep -i "Throughput:" | tail -n 1 | sed -n 's/.*Throughput: \([0-9.]*\) \([^,]*\).*/\1 \2/p')
            TP_VAL=$(echo $TP_RAW | awk '{print $1}')
            TP_UNIT=$(echo $TP_RAW | awk '{print $2}')

            # Normalize Throughput to MB/s
            if [[ "$TP_UNIT" == *"GiB"* ]]; then
                TP_MB=$(echo "$TP_VAL * 1024" | bc -l)
            elif [[ "$TP_UNIT" == *"KiB"* ]]; then
                TP_MB=$(echo "$TP_VAL / 1024" | bc -l)
            else
                TP_MB=$TP_VAL
            fi

            LAT_VAL=$(echo "$OUTPUT" | grep -i "Avg_Latency:" | tail -n 1 | sed -n 's/.*Avg_Latency: \([0-9.]*\).*/\1/p')
            TIME_VAL=$(echo "$OUTPUT" | grep -i "total_time" | tail -n 1 | sed -n 's/.*total_time \([0-9.]*\) secs.*/\1/p')

            if [ -z "$TP_MB" ] || [ -z "$LAT_VAL" ] || [ -z "$TIME_VAL" ]; then
                echo "  [!] Warning: Parsing failed for iteration $i ($MODE $SIZE)."
                echo "$OUTPUT" > .last_gdsio_read_error.log
            else
                # Convert us latency to ms and s total time to ms
                LAT_MS=$(echo "$LAT_VAL / 1000" | bc -l)
                TIME_MS=$(echo "$TIME_VAL * 1000" | bc -l)

                SUM_TP=$(echo "$SUM_TP + $TP_MB" | bc -l)
                SUM_LAT=$(echo "$SUM_LAT + $LAT_MS" | bc -l)
                SUM_TIME=$(echo "$SUM_TIME + $TIME_MS" | bc -l)
            fi
        done

        # Calculate averages
        AVG_TP=$(printf "%.4f" $(echo "$SUM_TP / $ITER" | bc -l | sed 's/^\./0./'))
        AVG_LAT=$(printf "%.4f" $(echo "$SUM_LAT / $ITER" | bc -l | sed 's/^\./0./'))
        AVG_TIME=$(printf "%.4f" $(echo "$SUM_TIME / $ITER" | bc -l | sed 's/^\./0./'))

        echo "$MODE,read,$SIZE,$BLOCK_SIZE,$THREADS,$AVG_TP,$AVG_LAT,$AVG_TIME" >> $OUTFILE
    done
}

# Run both modes
run_test "gds"
run_test "posix"

echo "Done. Results in $OUTFILE"
