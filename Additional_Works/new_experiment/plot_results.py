import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import sys
import os

# Mapping of transfer types to human readable names as requested
XFER_NAMES = {
    0: "0 - Storage->GPU (GDS)",
    1: "1 - Storage->CPU",
    2: "2 - Storage->CPU->GPU",
    3: "3 - Storage->CPU->GPU_ASYNC",
    4: "4 - Storage->PAGE_CACHE->CPU->GPU",
    5: "5 - Storage->GPU_ASYNC_STREAM",
    6: "6 - Storage->GPU_BATCH",
    7: "7 - Storage->GPU_BATCH_STREAM"
}

def plot_metric(df, io_size, metric, ylabel, output_file):
    plt.figure(figsize=(12, 7))
    sns.set_style("whitegrid")
    
    # Filter for specific IO size
    subset = df[df['IOSize'] == io_size].copy()
    
    # Map XferType to names
    subset['Transfer Path'] = subset['XferType'].map(XFER_NAMES)
    
    # Group by FileSize and Transfer Path to get the mean of runs
    size_order = ["512M", "1G", "4G", "8G"]
    subset['FileSize'] = pd.Categorical(subset['FileSize'], categories=size_order, ordered=True)
    
    avg_df = subset.groupby(['FileSize', 'Transfer Path'])[metric].mean().reset_index()
    
    # Create the line plot
    ax = sns.lineplot(data=avg_df, x='FileSize', y=metric, hue='Transfer Path', marker='o', linewidth=2.5)
    
    title = f"GDS {ylabel} Comparison (IO Size: {io_size})"
    plt.title(title, fontsize=15, pad=20)
    plt.xlabel("File Size", fontsize=12)
    plt.ylabel(ylabel, fontsize=12)
    plt.legend(title="Transfer Path", bbox_to_anchor=(1.05, 1), loc='upper left')
    plt.tight_layout()
    
    plt.savefig(output_file, dpi=300)
    print(f"Saved plot to {output_file}")
    plt.close()

def main(csv_file):
    if not os.path.exists(csv_file):
        print(f"Error: File {csv_file} not found.")
        return

    df = pd.read_csv(csv_file)
    
    # Throughput Plots
    plot_metric(df, "4K", "Throughput_GiBps", "Throughput (GiB/s)", "throughput_4k.png")
    plot_metric(df, "1M", "Throughput_GiBps", "Throughput (GiB/s)", "throughput_1m.png")
    
    # Latency Plots
    plot_metric(df, "4K", "AvgLatency_usec", "Normalized Latency (usec)", "latency_4k.png")
    plot_metric(df, "1M", "AvgLatency_usec", "Normalized Latency (usec)", "latency_1m.png")

if __name__ == "__main__":
    target_csv = "/mnt/gdstest/new_experiment/xfer_results_20260419_161035.csv"
    if len(sys.argv) > 1:
        target_csv = sys.argv[1]
    main(target_csv)
