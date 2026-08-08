import pandas as pd
import matplotlib.pyplot as plt
import os

def parse_size(size_str):
    size_str = str(size_str).strip().upper()
    if size_str.endswith('K'):
        return float(size_str[:-1]) * 1024
    elif size_str.endswith('M'):
        return float(size_str[:-1]) * 1024**2
    elif size_str.endswith('G'):
        return float(size_str[:-1]) * 1024**3
    else:
        return float(size_str)

def format_size(size_bytes):
    if size_bytes >= 1024**3:
        return f"{int(size_bytes/1024**3)}G"
    elif size_bytes >= 1024**2:
        return f"{int(size_bytes/1024**2)}M"
    elif size_bytes >= 1024:
        return f"{int(size_bytes/1024)}K"
    else:
        return f"{int(size_bytes)}"

def plot_size_sweep():
    csv_file = "read_1M_8thread_results.csv"
    if not os.path.exists(csv_file):
        print(f"Error: {csv_file} not found")
        return

    df = pd.read_csv(csv_file)
    df['bytes'] = df['total_size'].apply(parse_size)
    df = df.sort_values('bytes')

    # Filter out points below 128MB for better linear scale visibility
    df = df[df['bytes'] >= 128 * 1024 * 1024]
    
    # Create the figure with 2 subplots (1 row, 2 columns)
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 6))
    x_ticks = sorted(df['bytes'].unique())
    x_tick_labels = [format_size(b) for b in x_ticks]

    # --- Plot 1: Throughput ---
    for mode, color in [('gds', 'blue'), ('posix', 'red')]:
        data = df[df['mode'] == mode]
        ax1.plot(data['bytes'], data['avg_throughput_MBps'], marker='o', label=mode.upper(), color=color)
    
    ax1.set_title("Read Throughput vs. Total Size", fontsize=14)
    ax1.set_xlabel("Total Size per Thread", fontsize=12)
    ax1.set_ylabel("Throughput (MB/s)", fontsize=12)
    ax1.set_xticks(x_ticks)
    ax1.set_xticklabels(x_tick_labels, rotation=45)
    ax1.grid(True, linestyle='--', alpha=0.7)
    ax1.legend()

    # --- Plot 2: Average Total Time ---
    for mode, color in [('gds', 'blue'), ('posix', 'red')]:
        data = df[df['mode'] == mode]
        ax2.plot(data['bytes'], data['avg_total_time_ms'], marker='^', label=mode.upper(), color=color)
    
    ax2.set_title("Total Completion Time vs. Total Size", fontsize=14)
    ax2.set_xlabel("Total Size per Thread", fontsize=12)
    ax2.set_ylabel("Total Time (ms)", fontsize=12)
    ax2.set_xticks(x_ticks)
    ax2.set_xticklabels(x_tick_labels, rotation=45)
    ax2.grid(True, linestyle='--', alpha=0.7)
    ax2.legend()

    plt.tight_layout()
    plt.savefig("read_1M_8thread_plots.png", dpi=300)
    print("Plot saved as read_1M_8thread_plots.png")

if __name__ == "__main__":
    plot_size_sweep()
