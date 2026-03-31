import matplotlib.pyplot as plt
import os

# Data from parsed synthesis reports (divided by 1000 for k um^2)
threads = [1, 2, 4, 8, 16, 32]
area_threads = [78.804, 123.259, 207.771, 381.055, 744.361, 1483.816]

warps = [1, 2, 4, 8, 16, 32]
area_warps = [113.091, 147.036, 207.771, 329.039, 639.207, 1259.035]

fig, ax = plt.subplots(1, 2, figsize=(12, 5))

# Plot 1: Scaling Threads
ax[0].plot(threads, area_threads, marker='o', linestyle='-', color='#1f77b4', linewidth=2, markersize=8)
ax[0].set_title('Area Scaling vs. NUM_THREADS\n(Fixed NUM_WARPS=4)', fontsize=12, fontweight='bold')
ax[0].set_xlabel('Number of Threads per Warp (NUM_THREADS)', fontsize=11)
ax[0].set_ylabel('Total Cell Area (x1000 $\mu m^2$)', fontsize=11)
ax[0].set_xticks(threads)
ax[0].grid(True, linestyle='--', alpha=0.7)

# Plot 2: Scaling Warps
ax[1].plot(warps, area_warps, marker='s', linestyle='-', color='#d62728', linewidth=2, markersize=8)
ax[1].set_title('Area Scaling vs. NUM_WARPS\n(Fixed NUM_THREADS=4)', fontsize=12, fontweight='bold')
ax[1].set_xlabel('Number of Resident Warps (NUM_WARPS)', fontsize=11)
ax[1].set_ylabel('Total Cell Area (x1000 $\mu m^2$)', fontsize=11)
ax[1].set_xticks(warps)
ax[1].grid(True, linestyle='--', alpha=0.7)

plt.tight_layout()

output_path = '/mnt/ssd2/lao/vortex-2.2/笔记/image/area_scaling_charts.png'
os.makedirs(os.path.dirname(output_path), exist_ok=True)
plt.savefig(output_path, dpi=300)
print(f"Plot saved to {output_path}")
