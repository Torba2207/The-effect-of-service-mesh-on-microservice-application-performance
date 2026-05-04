import csv
import re
from pathlib import Path
from collections import defaultdict

def get_group_info(filename):
    """
    Extracts the base configuration group from filenames:
    'baseline1_25_result' -> 'baseline_25'
    'k6_baseline1_rps25_summary' -> 'k6_baseline_rps25'
    """
    # Matches: (optional k6_) + (letters/hyphens/underscores) + (run number) + _ + (rps string)
    match = re.match(r'^(k6_)?([a-zA-Z_-]+?)\d+_((?:rps)?\d+)', filename)
    if match:
        prefix = match.group(1) or ""
        base = match.group(2)
        rps = match.group(3)
        return f"{prefix}{base}_{rps}"
    return filename

# ==========================================
# 1. Kubernetes Metrics Processing Logic
# ==========================================
def process_k8s_files(k8s_files, output_dir):
    """Parses K8s logs, creates detailed CSVs, and calculates row-by-row group averages."""
    groups = defaultdict(list)
    
    for file_path in k8s_files:
        output_filepath = output_dir / f"{file_path.stem}.csv"
        timestamps = []
        service_totals = defaultdict(lambda: [0, 0]) # sec -> [sum_cpu, sum_mem]
        
        # Process Individual File
        with open(file_path, 'r', encoding='utf-8') as infile, \
             open(output_filepath, 'w', newline='', encoding='utf-8') as outfile:
            
            writer = csv.writer(outfile)
            writer.writerow(['Timestamp', 'Pod_Name', 'CPU_Usage(m)', 'Memory_Usage(Mi)'])
            current_timestamp = None
            
            for line in infile:
                line = line.strip()
                if not line: continue
                    
                timestamp_match = re.match(r'^---\s+([\d:]+)\s+---$', line)
                if timestamp_match:
                    current_timestamp = timestamp_match.group(1)
                    if current_timestamp not in timestamps:
                        timestamps.append(current_timestamp)
                    continue
                    
                if line.startswith('NAME'): continue
                    
                parts = line.split()
                if len(parts) >= 3 and current_timestamp:
                    pod_name = parts[0]
                    cpu = int(parts[1].replace('m', ''))
                    mem = int(parts[2].replace('Mi', ''))
                    
                    writer.writerow([current_timestamp, pod_name, cpu, mem])
                    service_totals[current_timestamp][0] += cpu
                    service_totals[current_timestamp][1] += mem
                    
        print(f"  -> [K8s] Created {output_filepath.name}")
        
        # Map absolute timestamps to a relative timeline (0, 1, 2...)
        rel_data = {}
        for idx, ts in enumerate(timestamps):
            rel_data[idx] = service_totals[ts]
            
        group_key = get_group_info(file_path.stem)
        groups[group_key].append(rel_data)

    # Calculate and output K8s Group Averages
    for group_key, runs_data in groups.items():
        if not runs_data: continue
            
        max_sec = max([max(run.keys()) for run in runs_data if run] + [0])
        avg_filepath = output_dir / f"{group_key}_averaged.csv" # matches 'baseline_25_averaged.csv'
        
        with open(avg_filepath, 'w', newline='', encoding='utf-8') as avgfile:
            writer = csv.writer(avgfile)
            writer.writerow(['Relative_Second', 'Avg_Total_Service_CPU(m)', 'Avg_Total_Service_Memory(Mi)'])
            
            for sec in range(max_sec + 1):
                cpus = [run[sec][0] for run in runs_data if sec in run]
                mems = [run[sec][1] for run in runs_data if sec in run]
                
                if cpus and mems:
                    avg_cpu = sum(cpus) / len(cpus)
                    avg_mem = sum(mems) / len(mems)
                    writer.writerow([sec, round(avg_cpu, 2), round(avg_mem, 2)])
                    
        print(f"  => [K8s Avg] Created {avg_filepath.name}")

# ==========================================
# 2. k6 Load Test Processing Logic
# ==========================================
def process_k6_files(k6_files, output_dir):
    """Parses k6 logs, creating purely time-series CSVs and row-by-row averages."""
    timeseries_pattern = re.compile(r'constant_load.*\[\s*(\d+)%\s*\].*?\s+(\d+)/\d+\s+VUs\s+([\d\.]+)s.*?([\d\.]+)\s+iters/s')
    
    groups = defaultdict(list)

    # Process Individual Files
    for file_path in k6_files:
        parsed_ts = []
        
        with open(file_path, 'r', encoding='utf-8') as infile:
            for line in infile:
                ts_match = timeseries_pattern.search(line.strip())
                if ts_match:
                    elapsed = ts_match.group(3)
                    prog = int(ts_match.group(1))
                    vus = int(ts_match.group(2))
                    iters = float(ts_match.group(4))
                    parsed_ts.append([elapsed, prog, vus, iters])

        # Remove '_summary' from filename if it exists to match desired output formatting
        base_name = file_path.stem.replace('_summary', '')
        output_file_path = output_dir / f"{base_name}_timeseries.csv"
        
        with open(output_file_path, 'w', newline='', encoding='utf-8') as outfile:
            writer = csv.writer(outfile)
            writer.writerow(['Elapsed_Time(s)', 'Progress(%)', 'Active_VUs', 'Iterations_per_sec'])
            writer.writerows(parsed_ts)
            
        group_key = get_group_info(file_path.stem)
        groups[group_key].append(parsed_ts)
        print(f"  -> [k6] Created {output_file_path.name}")

    # Row-by-Row Aggregation Phase (Identical Structure)
    for group_key, runs_ts_data in groups.items():
        group_ts = defaultdict(lambda: [0, 0, 0, 0]) # sec -> [sum_prog, sum_vus, sum_iters, count]
        
        # Tally up the values row by row across all runs in the group
        for run in runs_ts_data:
            for row in run:
                sec = row[0]
                group_ts[sec][0] += row[1] # Progress
                group_ts[sec][1] += row[2] # VUs
                group_ts[sec][2] += row[3] # Iters
                group_ts[sec][3] += 1      # Count

        # matches 'k6_baseline_rps25_timeseries.csv' (no _averaged suffix)
        ts_avg_filepath = output_dir / f"{group_key}_timeseries.csv" 
        
        with open(ts_avg_filepath, 'w', newline='', encoding='utf-8') as ts_avg_file:
            writer = csv.writer(ts_avg_file)
            writer.writerow(['Elapsed_Time(s)', 'Progress(%)', 'Active_VUs', 'Iterations_per_sec'])
            
            # Sort by Elapsed_Time (float) to ensure chronological order
            for sec in sorted(group_ts.keys(), key=float):
                sum_prog, sum_vus, sum_iters, count = group_ts[sec]
                
                avg_prog = int(sum_prog / count)
                avg_vus = int(round(sum_vus / count)) 
                avg_iters = round(sum_iters / count, 2)
                
                writer.writerow([sec, avg_prog, avg_vus, avg_iters])
                
        print(f"  => [k6 TS Avg] Created {ts_avg_filepath.name} (Averaged {len(runs_ts_data)} runs)")

# ==========================================
# 3. Main Orchestrator (Recursive Search)
# ==========================================
def process_all_logs(input_folder, output_folder):
    input_path = Path(input_folder)
    output_path = Path(output_folder)
    
    txt_files = list(input_path.rglob("*.txt"))
    if not txt_files:
        print(f"No .txt files found in '{input_folder}' or its subdirectories.")
        return

    k6_groups = defaultdict(list)
    k8s_groups = defaultdict(list)
    
    for file_path in txt_files:
        relative_dir = file_path.parent.relative_to(input_path)
        target_out_dir = output_path / relative_dir
        target_out_dir.mkdir(parents=True, exist_ok=True)
        
        if file_path.name.startswith("k6_"):
            k6_groups[target_out_dir].append(file_path)
        else:
            k8s_groups[target_out_dir].append(file_path)

    if k8s_groups:
        for target_out_dir, files in k8s_groups.items():
            config_name = target_out_dir.name if target_out_dir.name else "Root Directory"
            print(f"\n--- Processing Kubernetes Logs for: {config_name} ---")
            process_k8s_files(files, target_out_dir)
            
    if k6_groups:
        for target_out_dir, files in k6_groups.items():
            config_name = target_out_dir.name if target_out_dir.name else "Root Directory"
            print(f"\n--- Processing k6 Logs for: {config_name} ---")
            process_k6_files(files, target_out_dir)

if __name__ == '__main__':
    INPUT_DIR = 'thesis/input'
    OUTPUT_DIR = 'thesis/output'
    
    process_all_logs(INPUT_DIR, OUTPUT_DIR)
    print("\nAll tasks completed successfully!")