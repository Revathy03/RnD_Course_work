#!/bin/bash
# =============================================================================
# Experiment 3: GDS vs Phoenix Batch I/O Benchmark
# Compares batch I/O performance across varying io_depth (batch sizes)
# Uses Phoenix's microbenchmark binary
# =============================================================================

set -e

MICRO_BIN="/mnt/gdstest/Experiment 3/phoenix/build/bin/microbenchmark"
TEST_FILE="/mnt/gdstest/test_data_xfer"   # 8GB file
RESULT_DIR="/mnt/gdstest/Experiment 3/batch_comparison"
IO_SIZE="4k"
LENGTH="1G"
THREADS=1
GPU_ID=0

mkdir -p "$RESULT_DIR"

# Batch sizes (io_depth) to sweep
BATCH_SIZES=(1 2 4 8 16 32 64 128)

# =============================================================================
# GDS Batch I/O (xfer_mode=1, async=2)
# =============================================================================
echo "============================================"
echo "  GDS Batch I/O Experiment (cuFileBatchIO)"
echo "============================================"

GDS_CSV="$RESULT_DIR/gds_batch_results.csv"
echo "batch_size,bandwidth_MBps,avg_latency_us,p95_latency_us,p99_latency_us,p999_latency_us" > "$GDS_CSV"

for BATCH in "${BATCH_SIZES[@]}"; do
    echo ""
    echo ">>> GDS Batch Size = $BATCH"
    echo "---"

    # Drop caches before each run
    echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null 2>&1 || true

    OUTPUT=$("$MICRO_BIN" \
        -f "$TEST_FILE" \
        -l "$LENGTH" \
        -s "$IO_SIZE" \
        -t "$THREADS" \
        -i "$BATCH" \
        -m read \
        -a 2 \
        -d "$GPU_ID" \
        -x 1 \
        2>&1) || {
        echo "  [ERROR] GDS batch=$BATCH failed"
        echo "$OUTPUT"
        continue
    }

    echo "$OUTPUT"

    # Parse output
    BW=$(echo "$OUTPUT" | grep -oP 'Average IO bandwidth:\s*\K[\d.]+')
    LAT=$(echo "$OUTPUT" | grep -oP 'Average IO latency:\s*\K[\d.]+')
    P95=$(echo "$OUTPUT" | grep -oP '95th percentile latency:\s*\K[\d.]+')
    P99=$(echo "$OUTPUT" | grep -oP '99th percentile latency:\s*\K[\d.]+')
    P999=$(echo "$OUTPUT" | grep -oP '99\.9th percentile latency:\s*\K[\d.]+')

    echo "$BATCH,$BW,$LAT,$P95,$P99,$P999" >> "$GDS_CSV"
    echo "  => BW=${BW} MB/s, Lat=${LAT} us, P95=${P95} us"
done

echo ""
echo "GDS results saved to: $GDS_CSV"
cat "$GDS_CSV"

# =============================================================================
# Phoenix Batch I/O (xfer_mode=0, async=2) — requires kernel module
# =============================================================================
echo ""
echo "============================================"
echo "  Phoenix Batch I/O Experiment (io_uring)"
echo "============================================"

# Check if Phoenix kernel module is loaded
if lsmod | grep -qi "phxfs\|phoenix"; then
    echo "Phoenix kernel module detected. Running Phoenix batch benchmark..."

    PHX_CSV="$RESULT_DIR/phoenix_batch_results.csv"
    echo "batch_size,bandwidth_MBps,avg_latency_us,p95_latency_us,p99_latency_us,p999_latency_us" > "$PHX_CSV"

    for BATCH in "${BATCH_SIZES[@]}"; do
        echo ""
        echo ">>> Phoenix Batch Size = $BATCH"
        echo "---"

        echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null 2>&1 || true

        OUTPUT=$("$MICRO_BIN" \
            -f "$TEST_FILE" \
            -l "$LENGTH" \
            -s "$IO_SIZE" \
            -t "$THREADS" \
            -i "$BATCH" \
            -m read \
            -a 2 \
            -d "$GPU_ID" \
            -x 0 \
            2>&1) || {
            echo "  [ERROR] Phoenix batch=$BATCH failed"
            echo "$OUTPUT"
            continue
        }

        echo "$OUTPUT"

        BW=$(echo "$OUTPUT" | grep -oP 'Average IO bandwidth:\s*\K[\d.]+')
        LAT=$(echo "$OUTPUT" | grep -oP 'Average IO latency:\s*\K[\d.]+')
        P95=$(echo "$OUTPUT" | grep -oP '95th percentile latency:\s*\K[\d.]+')
        P99=$(echo "$OUTPUT" | grep -oP '99th percentile latency:\s*\K[\d.]+')
        P999=$(echo "$OUTPUT" | grep -oP '99\.9th percentile latency:\s*\K[\d.]+')

        echo "$BATCH,$BW,$LAT,$P95,$P99,$P999" >> "$PHX_CSV"
        echo "  => BW=${BW} MB/s, Lat=${LAT} us, P95=${P95} us"
    done

    echo ""
    echo "Phoenix results saved to: $PHX_CSV"
    cat "$PHX_CSV"
else
    echo ""
    echo "[WARNING] Phoenix kernel module is NOT loaded."
    echo "  Phoenix batch I/O (xfer_mode=0) requires the phxfs kernel module."
    echo "  To install it:"
    echo "    cd /mnt/gdstest/Experiment\\ 3/phoenix/build && sudo make insmod"
    echo ""
    echo "  Skipping Phoenix benchmark. Only GDS results are available."
fi

echo ""
echo "============================================"
echo "  Experiment Complete!"
echo "============================================"
