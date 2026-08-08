#!/bin/bash

GDS_OUT="gds_results1.csv"
TRAD_OUT="trad_results1.csv"

# CSV headers
echo "N,DataSize_Power,Read_Total_ms,Compute_ms,Write_Total_ms,Total_ms" > $GDS_OUT
echo "N,DataSize_Power,Read_NVMe_CPU_ms,Read_CPU_GPU_ms,Read_Total_ms,Compute_ms,Write_GPU_CPU_ms,Write_CPU_NVMe_ms,Write_Total_ms,Total_ms" > $TRAD_OUT


for ((i=1;i<=15;i++))
do
    N=$((2**i))

    POW=$((2*i+2))
    SIZE_LABEL="2^${POW}"

    echo "Running N=$N  Size=$SIZE_LABEL"

    ############################
    # Run GDS
    ############################
    GDS_LOG=$(./gds $N $N)

    GDS_READ=$(echo "$GDS_LOG" | grep 'Read time' | awk -F':' '{print $2}' | awk '{print $1}')
    GDS_COMP=$(echo "$GDS_LOG" | grep 'Compute time' | awk -F':' '{print $2}' | awk '{print $1}')
    GDS_WRITE=$(echo "$GDS_LOG" | grep 'Write time' | awk -F':' '{print $2}' | awk '{print $1}')
    GDS_TOTAL=$(echo "$GDS_LOG" | grep 'Total time' | awk -F':' '{print $2}' | awk '{print $1}')

    echo "$N,$SIZE_LABEL,$GDS_READ,$GDS_COMP,$GDS_WRITE,$GDS_TOTAL" >> $GDS_OUT


    ############################
    # Run Traditional
    ############################
    TRAD_LOG=$(./trad $N $N)

    TRAD_READ_NVME=$(echo "$TRAD_LOG"     | grep 'Read time NVMe-CPU'  | awk -F':' '{print $2}' | awk '{print $1}')
    TRAD_READ_CPU_GPU=$(echo "$TRAD_LOG"  | grep 'Read time CPU-GPU'   | awk -F':' '{print $2}' | awk '{print $1}')
    TRAD_READ_TOTAL=$(echo "$TRAD_LOG"    | grep 'Read time :'         | awk -F':' '{print $2}' | awk '{print $1}')

    TRAD_COMP=$(echo "$TRAD_LOG"          | grep 'Compute time'        | awk -F':' '{print $2}' | awk '{print $1}')

    TRAD_WRITE_GPU_CPU=$(echo "$TRAD_LOG" | grep 'Write time GPU-CPU'  | awk -F':' '{print $2}' | awk '{print $1}')
    TRAD_WRITE_CPU_NVME=$(echo "$TRAD_LOG"| grep 'Write time CPU-NVMe' | awk -F':' '{print $2}' | awk '{print $1}')
    TRAD_WRITE_TOTAL=$(echo "$TRAD_LOG"   | grep 'Write time :'         | awk -F':' '{print $2}' | awk '{print $1}')

    TRAD_TOTAL=$(echo "$TRAD_LOG"         | grep 'Total time'          | awk -F':' '{print $2}' | awk '{print $1}')

    echo "$N,$SIZE_LABEL,$TRAD_READ_NVME,$TRAD_READ_CPU_GPU,$TRAD_READ_TOTAL,$TRAD_COMP,$TRAD_WRITE_GPU_CPU,$TRAD_WRITE_CPU_NVME,$TRAD_WRITE_TOTAL,$TRAD_TOTAL" >> $TRAD_OUT

done

echo "Done."
echo "Results saved to:"
echo "$GDS_OUT"
echo "$TRAD_OUT"