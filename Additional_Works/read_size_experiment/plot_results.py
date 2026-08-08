import pandas as pd
import matplotlib.pyplot as plt
import glob
import os
import re

# Premium styling
plt.style.use('seaborn-v0_8-darkgrid')
plt.rcParams['font.family'] = 'sans-serif'
plt.rcParams['font.sans-serif'] = ['Inter', 'Roboto', 'Arial']

def get_latest_csv(pattern):
    list_of_files = glob.glob(pattern)
    if not list_of_files:
        return None
    # Return the one with the latest timestamp in the filename or most recently created
    return max(list_of_files, key=os.path.getctime)

def parse_size(size_str):
    """Convert size strings like 1G, 512M to numeric bytes for sorting."""
    match = re.match(r"(\d+)([KMG])", size_str)
    if not match:
        return 0
    val, unit = match.groups()
    val = int(val)
    multiplier = {'K': 1024, 'M': 1024**2, 'G': 1024**3}
    return val * multiplier.get(unit, 1)

def plot_experiment_results():
    # Find the latest results file
    csv_pattern = '/mnt/gdstest/read_size_experiment/read_results_*.csv'
    csv_file = get_latest_csv(csv_pattern)

    if not csv_file:
        print(f"No results CSV found matching pattern: {csv_pattern}")
        return

    print(f"Analyzing and plotting results from: {csv_file}")

    try:
        df = pd.read_csv(csv_file)
    except Exception as e:
        print(f"Error reading CSV: {e}")
        return

    if df.empty:
        print("CSV is empty. The experiment might still be preparing its first run.")
        return

    # Average the runs for each configuration (XferType, FileSize, IOSize)
    df_avg = df.groupby(['XferType', 'FileSize', 'IOSize'])['Throughput_GiBps'].mean().reset_index()

    # Sort FileSize numerically to ensure lines are plotted correctly
    df_avg['SizeNumeric'] = df_avg['FileSize'].apply(parse_size)
    df_avg = df_avg.sort_values('SizeNumeric')

    # Create the plot
    fig, ax = plt.subplots(figsize=(12, 7), dpi=120)

    # Configuration mapping for styles and labels
    # Format: (XferType, IOSize, LineStyle, LabelSuffix, Color)
    configs = [
        (0, '4K', '-',  'Batch Off (4K) [Solid]', '#3498DB'), 
        (6, '4K', '--', 'Batch On (4K) [Dashed]',  '#3498DB'), 
        (0, '1M', '-',  'Batch Off (1M) [Solid]', '#E67E22'), 
        (6, '1M', '--', 'Batch On (1M) [Dashed]',  '#E67E22'), 
    ]

    has_data = False
    for xfer_type, io_size, linestyle, label, color in configs:
        subset = df_avg[(df_avg['XferType'] == xfer_type) & (df_avg['IOSize'] == io_size)]
        
        if not subset.empty:
            has_data = True
            ax.plot(subset['FileSize'], subset['Throughput_GiBps'], 
                    label=label, 
                    linestyle=linestyle, 
                    marker='o',
                    color=color,
                    linewidth=2.5,
                    markersize=8,
                    alpha=0.9)

    if not has_data:
        print("No data points found to plot yet.")
        return

    # Formatting
    ax.set_xlabel('File Size', fontsize=13, fontweight='bold', labelpad=10)
    ax.set_ylabel('Throughput (GiB/s)', fontsize=13, fontweight='bold', labelpad=10)
    ax.set_title('GDS Read Performance Analysis\nBatch Off (Mode 0) vs Batch On (Mode 6)', 
                 fontsize=16, fontweight='bold', pad=20)
    
    ax.legend(frameon=True, facecolor='white', framealpha=0.8, fontsize=11, loc='best')
    ax.grid(True, which='both', linestyle='--', alpha=0.4)
    
    # Add subtle background gradient or just keep it clean
    ax.set_facecolor('#f8f9fa')
    fig.patch.set_facecolor('white')

    plt.tight_layout()

    # Save the plot
    plot_path = csv_file.replace('.csv', '.png')
    plt.savefig(plot_path)
    plt.savefig('/mnt/gdstest/read_size_experiment/latest_results.png') # Constant name for easy access
    
    print(f"Successfully generated plot:")
    print(f" - Timestamped: {plot_path}")
    print(f" - Latest: /mnt/gdstest/read_size_experiment/latest_results.png")

if __name__ == "__main__":
    plot_experiment_results()
