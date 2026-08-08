import pandas as pd
import matplotlib.pyplot as plt
import sys
import os

def plot_results(csv_path):
    if not os.path.exists(csv_path):
        print(f"CSV file not found: {csv_path}")
        return

    df = pd.read_csv(csv_path)
    
    # Calculate averages across runs
    summary = df.groupby(['XferType', 'IOSize', 'BatchSize']).agg({
        'Throughput_GiBps': 'mean',
        'AvgLatency_usec': 'mean'
    }).reset_index()

    io_sizes = summary['IOSize'].unique()
    
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(15, 6))

    # Plot Throughput
    for io in io_sizes:
        # Mode 6 scaling
        subset_6 = summary[(summary['XferType'] == 6) & (summary['IOSize'] == io)]
        ax1.plot(subset_6['BatchSize'], subset_6['Throughput_GiBps'], marker='o', label=f'Mode 6 ({io})')
        
        # Mode 0 baseline (it only has BatchSize 1)
        subset_0 = summary[(summary['XferType'] == 0) & (summary['IOSize'] == io)]
        if not subset_0.empty:
            baseline = subset_0['Throughput_GiBps'].iloc[0]
            ax1.axhline(y=baseline, linestyle='--', alpha=0.7, label=f'Mode 0 ({io}) Baseline')

    ax1.set_xlabel('Batch Size')
    ax1.set_ylabel('Throughput (GiB/s)')
    ax1.set_title('Throughput vs Batch Size')
    ax1.legend()
    ax1.grid(True, which="both", ls="-", alpha=0.2)
    ax1.set_xscale('log', base=2)

    # Plot Latency
    for io in io_sizes:
        subset_6 = summary[(summary['XferType'] == 6) & (summary['IOSize'] == io)]
        ax2.plot(subset_6['BatchSize'], subset_6['AvgLatency_usec'], marker='s', label=f'Mode 6 ({io})')
        
        subset_0 = summary[(summary['XferType'] == 0) & (summary['IOSize'] == io)]
        if not subset_0.empty:
            baseline = subset_0['AvgLatency_usec'].iloc[0]
            ax2.axhline(y=baseline, linestyle='--', alpha=0.7, label=f'Mode 0 ({io}) Baseline')

    ax2.set_xlabel('Batch Size')
    ax2.set_ylabel('Avg Latency (usec)')
    ax2.set_title('Latency vs Batch Size')
    ax2.legend()
    ax2.grid(True, which="both", ls="-", alpha=0.2)
    ax2.set_xscale('log', base=2)

    plt.tight_layout()
    plot_path = csv_path.replace('.csv', '.png')
    plt.savefig(plot_path)
    print(f"Plot saved to {plot_path}")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        plot_results(sys.argv[1])
    else:
        # Try to find the latest CSV
        import glob
        csvs = glob.glob("/mnt/gdstest/batch_size_experiment/batch_size_results_*.csv")
        if csvs:
            latest_csv = max(csvs, key=os.path.getctime)
            plot_results(latest_csv)
        else:
            print("No CSV files found in /mnt/gdstest/batch_size_experiment/")
