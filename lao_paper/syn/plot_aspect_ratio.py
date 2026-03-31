import matplotlib.pyplot as plt
import os

# Total thread count constraints
total_threads = [4, 8, 16, 32, 64, 128]

# Area data (in k um^2)
# "Wide & Shallow": Keep W=4, scale T
area_wide_shallow = [78.804, 123.259, 207.771, 381.055, 744.361, 1483.816]

# "Narrow & Deep": Keep T=4, scale W
area_narrow_deep = [113.091, 147.036, 207.771, 329.039, 639.207, 1259.035]

fig, ax = plt.subplots(figsize=(8, 6))

ax.plot(total_threads, area_wide_shallow, marker='o', linestyle='-', color='#1f77b4', linewidth=2, markersize=8, label='Scale NUM_THREADS (Fixed NUM_WARPS=4)')
ax.plot(total_threads, area_narrow_deep, marker='s', linestyle='-', color='#d62728', linewidth=2, markersize=8, label='Scale NUM_WARPS (Fixed NUM_THREADS=4)')

ax.set_title('Area Trade-off under Equal Total Threads\n(Total Threads = NUM_WARPS × NUM_THREADS)', fontsize=13, fontweight='bold')
ax.set_xlabel('Total Hardware Threads Count', fontsize=11)
ax.set_ylabel('Total Cell Area (x1000 $\mu m^2$)', fontsize=11)
ax.set_xticks(total_threads)
ax.grid(True, linestyle='--', alpha=0.7)
ax.legend(fontsize=11)

# Annotate the intersection point
ax.annotate('Intersection Point\n(W=4, T=4)', 
            xy=(16, 207.771), xytext=(20, 100),
            arrowprops=dict(facecolor='black', shrink=0.05, width=1.5, headwidth=6),
            fontsize=10)

plt.tight_layout()

output_path = '/mnt/ssd2/lao/vortex-2.2/笔记/image/aspect_ratio_tradeoff.png'
os.makedirs(os.path.dirname(output_path), exist_ok=True)
plt.savefig(output_path, dpi=300)
print(f"Trade-off plot saved to {output_path}")
