import os
import re
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from pathlib import Path
from collections import defaultdict

def get_k8s_identity(filename):
    """Extracts (base_name, rps) from 'baseline_25_averaged.csv'"""
    match = re.match(r'^([a-zA-Z_-]+?)_?(\d+)_averaged\.csv$', filename)
    if match:
        return match.group(1).rstrip('_'), match.group(2)
    return None, None

def get_k6_identity(filename):
    """Extracts (base_name, rps) from 'k6_baseline_rps25_timeseries.csv'"""
    match = re.match(r'^k6_([a-zA-Z_-]+?)_?(?:rps)?(\d+)_timeseries\.csv$', filename)
    if match:
        return match.group(1).rstrip('_'), match.group(2)
    return None, None

def validate_k6_group(k6_files_dict, rps_group):
    """
    Validates that all k6 throughputs in a group are practically identical.
    k6_files_dict: { 'baseline': DataFrame, 'v1': DataFrame, ... }
    """
    reference_name = list(k6_files_dict.keys())[0]
    reference_df = k6_files_dict[reference_name]
    reference_mean = reference_df['Iterations_per_sec'].mean()
    
    # Tolerance threshold: Maximum allowed difference in average RPS
    TOLERANCE = 2.0 
    
    for version_name, df in k6_files_dict.items():
        if version_name == reference_name:
            continue
            
        current_mean = df['Iterations_per_sec'].mean()
        diff = abs(reference_mean - current_mean)
        
        if diff > TOLERANCE:
            raise ValueError(
                f"\n[Validation Failed] Mismatched Load Profiles in RPS Group '{rps_group}'!\n"
                f"Reference '{reference_name}' average RPS: {reference_mean:.2f}\n"
                f"Offending '{version_name}' average RPS: {current_mean:.2f}\n"
                f"Difference ({diff:.2f}) exceeds tolerance of {TOLERANCE} RPS. Please check your raw data."
            )
            
    print(f"  -> Validated {len(k6_files_dict)} configurations for target {rps_group} RPS.")
    return reference_df # Return the reference to plot as the "Shared" RPS line

def plot_comparative_graphs(k8s_data_dict, shared_k6_df, rps_group, output_dir):
    """Generates the multi-line comparative graphs with extended 0-RPS cooldown."""
    color_rps = '#d62728' 
    colors = plt.rcParams['axes.prop_cycle'].by_key()['color'] 

    # --- THE FIX: Extend the RPS Timeline ---
    # Find the maximum time across all plotted K8s data (e.g., 70 seconds)
    max_k8s_time = int(max(df['Relative_Second'].max() for df in k8s_data_dict.values()))
    
    # Create an array from 0 to the max K8s time
    extended_time = list(range(max_k8s_time + 1))
    
    # Map existing k6 data to a dictionary for quick lookup
    k6_times = shared_k6_df['Elapsed_Time(s)'].astype(int).tolist()
    k6_rps = shared_k6_df['Iterations_per_sec'].tolist()
    rps_map = dict(zip(k6_times, k6_rps))
    
    # Generate the extended RPS array: use mapped value if it exists, otherwise 0.0
    extended_rps = [rps_map.get(t, 0.0) for t in extended_time]

    # ==========================================
    # Graph 1: Comparative CPU
    # ==========================================
    fig1, ax1 = plt.subplots(figsize=(10, 6))
    ax1.set_xlabel('Time (Seconds)', fontsize=11)
    ax1.set_ylabel('Total Service CPU (m)', fontsize=12, fontweight='bold')
    
    for idx, (version, df_k8s) in enumerate(k8s_data_dict.items()):
        c = colors[idx % len(colors)]
        ax1.plot(df_k8s['Relative_Second'], df_k8s['Avg_Total_Service_CPU(m)'], 
                 linewidth=2.5, label=f'{version} CPU', color=c)
        
    ax1.grid(True, linestyle='--', alpha=0.6)

    # Plot the Extended Validated k6 Line on Secondary Axis
    ax1_twin = ax1.twinx()
    ax1_twin.set_ylabel('Requests per Second', color=color_rps, fontsize=12, fontweight='bold')
    ax1_twin.plot(extended_time, extended_rps, 
                  color=color_rps, linestyle='--', linewidth=2, label='Shared Throughput (RPS)')
    ax1_twin.tick_params(axis='y', labelcolor=color_rps)

    # Move legend to upper right to avoid overlapping the initial data
    lines_1, labels_1 = ax1.get_legend_handles_labels()
    lines_2, labels_2 = ax1_twin.get_legend_handles_labels()
    ax1.legend(lines_1 + lines_2, labels_1 + labels_2, loc='upper right')
    ax1.set_title(f'CPU Comparison Across Configurations (Target: {rps_group} RPS)', fontsize=14, fontweight='bold')

    cpu_out = output_dir / f"comparative_cpu_rps{rps_group}.png"
    fig1.tight_layout()
    fig1.savefig(cpu_out, dpi=300, bbox_inches='tight')
    plt.close(fig1)

    # ==========================================
    # Graph 2: Comparative Memory
    # ==========================================
    fig2, ax2 = plt.subplots(figsize=(10, 6))
    ax2.set_xlabel('Time (Seconds)', fontsize=11)
    ax2.set_ylabel('Total Service Memory (Mi)', fontsize=12, fontweight='bold')
    
    for idx, (version, df_k8s) in enumerate(k8s_data_dict.items()):
        c = colors[idx % len(colors)]
        ax2.plot(df_k8s['Relative_Second'], df_k8s['Avg_Total_Service_Memory(Mi)'], 
                 linewidth=2.5, label=f'{version} Memory', color=c)
        
    ax2.grid(True, linestyle='--', alpha=0.6)

    # Plot the Extended Validated k6 Line
    ax2_twin = ax2.twinx()
    ax2_twin.set_ylabel('Requests per Second', color=color_rps, fontsize=12, fontweight='bold')
    ax2_twin.plot(extended_time, extended_rps, 
                  color=color_rps, linestyle='--', linewidth=2, label='Shared Throughput (RPS)')
    ax2_twin.tick_params(axis='y', labelcolor=color_rps)

    lines_1, labels_1 = ax2.get_legend_handles_labels()
    lines_2, labels_2 = ax2_twin.get_legend_handles_labels()
    ax2.legend(lines_1 + lines_2, labels_1 + labels_2, loc='upper right')
    ax2.set_title(f'Memory Comparison Across Configurations (Target: {rps_group} RPS)', fontsize=14, fontweight='bold')

    mem_out = output_dir / f"comparative_memory_rps{rps_group}.png"
    fig2.tight_layout()
    fig2.savefig(mem_out, dpi=300, bbox_inches='tight')
    plt.close(fig2)
    
    print(f"  => Saved comparative graphs for {rps_group} RPS group.")

def process_comparative_graphs(target_folder):
    """Groups data by RPS across ALL folders and plots comparisons."""
    base_path = Path(target_folder)
    if not base_path.exists():
        print(f"Error: The directory '{target_folder}' does not exist.")
        return

    # Data Structure: { '25': { 'baseline': {'k8s': df, 'k6': df}, 'v1': {...} } }
    grouped_data = defaultdict(lambda: defaultdict(dict))
    
    all_k8s = list(base_path.rglob("*_averaged.csv"))
    all_k6 = list(base_path.rglob("k6_*_timeseries.csv"))
    
    # 1. Map K8s files
    for file in all_k8s:
        version, rps = get_k8s_identity(file.name)
        if version and rps:
            grouped_data[rps][version]['k8s'] = pd.read_csv(file)
            
    # 2. Map k6 files
    for file in all_k6:
        version, rps = get_k6_identity(file.name)
        if version and rps:
            grouped_data[rps][version]['k6'] = pd.read_csv(file)

    # 3. Process each RPS group
    for rps_group, versions_dict in grouped_data.items():
        print(f"\n--- Processing Comparative Group: {rps_group} RPS ---")
        
        k8s_data_dict = {}
        k6_data_dict = {}
        
        # Ensure we only graph versions that have BOTH k8s and k6 data
        for version, data in versions_dict.items():
            if 'k8s' in data and 'k6' in data:
                k8s_data_dict[version] = data['k8s']
                k6_data_dict[version] = data['k6']
            else:
                print(f"  [Warning] Skipping '{version}' at {rps_group} RPS: Missing either k8s or k6 data.")
                
        if not k6_data_dict:
            print(f"  [Error] No valid pairs found for {rps_group} RPS. Skipping.")
            continue
            
        # 4. Validate k6 similarity and get the shared reference line
        try:
            shared_k6_df = validate_k6_group(k6_data_dict, rps_group)
        except ValueError as e:
            print(e)
            continue # Skip this RPS group if validation fails
            
        # 5. Plot the graphs (saving them to the root processed folder)
        plot_comparative_graphs(k8s_data_dict, shared_k6_df, rps_group, base_path)

if __name__ == '__main__':
    PROCESSED_CSV_DIR = 'output' 
    print("Starting comparative graph generation...")
    process_comparative_graphs(PROCESSED_CSV_DIR)
    print("\nAll comparative graphing tasks completed successfully!")