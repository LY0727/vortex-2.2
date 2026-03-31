'''
Author: lao liuao0727@foxmail.com
Date: 2026-03-27 22:14:55
LastEditors: lao liuao0727@foxmail.com
LastEditTime: 2026-03-28 12:38:35
FilePath: /vortex-2.2/syn/parse_reports.py
Description: 这是默认设置,请设置`customMade`, 打开koroFileHeader查看配置 进行设置: https://github.com/OBKoro1/koro1FileHeader/wiki/%E9%85%8D%E7%BD%AE
'''
import os
import re
import glob

def parse_area(filepath):
    total_area = "N/A"
    with open(filepath, 'r') as f:
        for line in f:
            if "Total cell area:" in line:
                total_area = line.split(":")[1].strip()
                break
    return total_area

def parse_power(filepath):
    total_power = "N/A"
    leakage_power = "N/A"
    dynamic_power = "N/A"
    with open(filepath, 'r') as f:
        content = f.read()
        # Regex to find the total power row. Usually the last row in the power table.
        # "Total                      x.xxx    y.yyy     z.zzz"
        m = re.search(r'Total\s+[\d\.e+-]+\s+[\d\.e+-]+\s+([\d\.e+-]+)', content)
        if m:
            total_power = m.group(1)
        
        m_leak = re.search(r'Cell Leakage Power\s*=\s*([\d\.e+-]+)\s*(\w+)', content)
        if m_leak:
            leakage_power = m_leak.group(1) + " " + m_leak.group(2)
            
    return total_power, leakage_power

def parse_timing(filepath):
    wns = "N/A"
    endpoint = "N/A"
    with open(filepath, 'r') as f:
        content = f.read()
        m_slack = re.search(r'slack \((MET|VIOLATED)\)\s+([\-\.\d]+)', content)
        if m_slack:
            wns = m_slack.group(2)
        
        m_endpoint = re.search(r'Endpoint:\s+(\S+)', content)
        if m_endpoint:
            endpoint = m_endpoint.group(1)
            
    return wns, endpoint

def analyze_group(group_dir, var_name, sort_func):
    print(f"\n### {group_dir}")
    print(f"| {var_name} | Area (um^2) | Power (uW/mW) | WNS (ns) | Critical Path Endpoint |")
    print(f"|---|---|---|---|---|")
    
    subdirs = glob.glob(os.path.join("syn/dc_experiments", group_dir, "*"))
    
    # Extract var value for sorting
    data = []
    for d in subdirs:
        basename = os.path.basename(d)
        if "W" not in basename: continue
        val = sort_func(basename)
        
        area_file = os.path.join(d, "VX_core_top_area.rpt")
        power_file = os.path.join(d, "VX_core_top_power.rpt")
        timing_file = os.path.join(d, "VX_core_top_timing.rpt")
        
        if os.path.exists(area_file):
            area = parse_area(area_file)
            pwr_total, pwr_leak = parse_power(power_file)
            wns, endpoint = parse_timing(timing_file)
            data.append((val, basename, area, pwr_total, wns, endpoint))
            
    data.sort(key=lambda x: x[0])
    
    for item in data:
        print(f"| {item[1]} | {item[2]} | {item[3]} | {item[4]} | {item[5]} |")

def main():
    def sort_t(name):
        # Format: W4_T16_400M
        m = re.search(r'T(\d+)', name)
        return int(m.group(1)) if m else 0

    def sort_w(name):
        m = re.search(r'W(\d+)', name)
        return int(m.group(1)) if m else 0

    def sort_f(name):
        m = re.search(r'_(\d+)M', name)
        return int(m.group(1)) if m else 0
        
    analyze_group("exp1_scaling_threads", "Config", sort_t)
    analyze_group("exp2_scaling_warps", "Config", sort_w)
    analyze_group("exp3_critical_path", "Config", sort_f)

if __name__ == "__main__":
    main()
