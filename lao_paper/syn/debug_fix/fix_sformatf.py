import os
import glob

def fix_sformatf_in_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    if '$sformatf' in content:
        # replace $sformatf(...) with "" when not in trace mode or to avoid DC errors
        # a safer way is to just replace the whole .INSTANCE_ID ($sformatf(...)) with .INSTANCE_ID ("")
        import re
        content = re.sub(r'\.INSTANCE_ID\s*\(\s*\$sformatf\s*\([^)]*\)\s*\)', '.INSTANCE_ID ("")', content)
        content = re.sub(r'\.INSTANCE_ID\s*\(\$sformatf\s*\([^)]*\)\)', '.INSTANCE_ID ("")', content)

        with open(filepath, 'w') as f:
            f.write(content)
        print("Fixed $sformatf in", filepath)

for root, _, files in os.walk('.'):
    for f in files:
        if f.endswith('.sv') or f.endswith('.vh'):
            fix_sformatf_in_file(os.path.join(root, f))
