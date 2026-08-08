#!/bin/bash

OUTFILE="read_total_size_sweep_results.csv"
THREADS=4
BLOCK_SIZE="4K"
ITER=3
FILEDR="$(pwd)"
GPU_ID=0

# Total sizes from 4KB to 4GB
SIZES=("4K" "8K" "16K" "32K" "64K" "128K" "256K" "512K" "1M" "2M" "4M" "8M" "16M" "32M" "64M" "128M" "256M" "512M" "1G" "2G" "4G")

mkdir -p "$FILEDR"

echo "mode,io_type,total_size,block_size,threads,avg_throughput_MBps,avg_latency_ms,avg_total_time_ms" > "$OUTFILE"

run_test() {
    MODE="$1"
    for SIZE in "${SIZES[@]}"; do
        SUM_TP=0
        SUM_LAT=0
        SUM_TIME=0

        echo "Running $MODE read: total_size=$SIZE, block_size=$BLOCK_SIZE, threads=$THREADS ($ITER iterations)"

        for ((i=1; i<=ITER; i++)); do
            if [ "$MODE" == "gds" ]; then
                EXTRA="-x 0"
            else
                EXTRA="-x 2"
            fi

            OUTPUT=$(/usr/local/cuda/gds/tools/gdsio -D "$FILEDR" \
                -d "$GPU_ID" \
                -w "$THREADS" \
                -s "$SIZE" \
                -i "$BLOCK_SIZE" \
                -I 0 \
                $EXTRA 2>&1 | sed 's/\x1b\[[0-9;]*m//g')

            TP_LINE=$(echo "$OUTPUT" | grep -i "Throughput:" | tail -n 1)
            TP_VAL=$(echo "$TP_LINE" | awk '{print $2}')
            TP_UNIT=$(echo "$TP_LINE" | awk '{print $3}')
            LAT_VAL=$(echo "$OUTPUT" | grep -i "Avg_Latency:" | tail -n 1 | sed -n 's/.*Avg_Latency: \([0-9.]*\).*/\1/p')
            TIME_VAL=$(echo "$OUTPUT" | grep -i "total_time" | tail -n 1 | sed -n 's/.*total_time \([0-9.]*\) secs.*/\1/p')

            if [ -z "$TP_VAL" ] || [ -z "$LAT_VAL" ] || [ -z "$TIME_VAL" ]; then
                echo "  [!] Warning: Parsing failed for iteration $i ($MODE $SIZE)."
                echo "$OUTPUT" > .last_gdsio_read_error.log
                continue
            fi

            if [[ "$TP_UNIT" == *"GiB"* ]]; then
                TP_MB=$(echo "$TP_VAL * 1024" | bc -l)
            elif [[ "$TP_UNIT" == *"KiB"* ]]; then
                TP_MB=$(echo "$TP_VAL / 1024" | bc -l)
            else
                TP_MB="$TP_VAL"
            fi

            LAT_MS=$(echo "$LAT_VAL / 1000" | bc -l)
            TIME_MS=$(echo "$TIME_VAL * 1000" | bc -l)

            SUM_TP=$(echo "$SUM_TP + $TP_MB" | bc -l)
            SUM_LAT=$(echo "$SUM_LAT + $LAT_MS" | bc -l)
            SUM_TIME=$(echo "$SUM_TIME + $TIME_MS" | bc -l)
        done

        AVG_TP=$(printf "%.4f" $(echo "$SUM_TP / $ITER" | bc -l))
        AVG_LAT=$(printf "%.4f" $(echo "$SUM_LAT / $ITER" | bc -l))
        AVG_TIME=$(printf "%.4f" $(echo "$SUM_TIME / $ITER" | bc -l))

        echo "$MODE,randread,$SIZE,$BLOCK_SIZE,$THREADS,$AVG_TP,$AVG_LAT,$AVG_TIME" >> "$OUTFILE"
    done
}

run_test "gds"
run_test "posix"

echo "Done. Results in $OUTFILE"
