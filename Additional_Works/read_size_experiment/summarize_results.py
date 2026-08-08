import pandas as pd

def summarize_results():
    input_file = '/mnt/gdstest/read_size_experiment/read_results_20260428_080133.csv'
    output_file = '/mnt/gdstest/read_size_experiment/read_results_summary.csv'
    
    # Read the data
    df = pd.read_csv(input_file)
    
    # Map XferType to descriptive names
    mapping = {0: 'batch off', 6: 'batch on'}
    df['XferType'] = df['XferType'].map(mapping)
    
    # Calculate average throughput
    summary = df.groupby(['XferType', 'FileSize', 'IOSize'])['Throughput_GiBps'].mean().reset_index()
    
    # Rename the column to indicate it is an average
    summary = summary.rename(columns={'Throughput_GiBps': 'Avg_Throughput_GiBps'})
    
    # Optional: Sort for better readability
    # Define a helper for numeric sorting of FileSize
    def parse_size(size_str):
        import re
        match = re.match(r"(\d+)([KMG])", str(size_str))
        if not match: return 0
        val, unit = match.groups()
        mult = {'K': 1024, 'M': 1024**2, 'G': 1024**3}
        return int(val) * mult.get(unit, 1)
    
    summary['SizeVal'] = summary['FileSize'].apply(parse_size)
    summary = summary.sort_values(['IOSize', 'SizeVal', 'XferType'])
    summary = summary.drop(columns=['SizeVal'])
    
    # Save to CSV
    summary.to_csv(output_file, index=False)
    print(f"Summary CSV created at: {output_file}")
    print("\nSummary Content:")
    print(summary.to_string(index=False))

if __name__ == "__main__":
    summarize_results()
