import os
import re

for folder in ['dbt/models/silver', 'dbt/models/gold']:
    if not os.path.exists(folder): continue
    for filename in os.listdir(folder):
        if not filename.endswith('.sql'): continue
        filepath = os.path.join(folder, filename)
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Change delete+insert to merge
        content = content.replace("incremental_strategy = 'delete+insert'", "incremental_strategy = 'merge'")
        content = content.replace("incremental_strategy = 'delete+insert',", "incremental_strategy = 'merge',")
        
        # Find unique_key
        match = re.search(r"unique_key\s*=\s*'([^']+)'", content)
        if match:
            unique_key = match.group(1)
            # Add distribution = 'HASH(...)' if not there
            if 'distribution' not in content:
                content = content.replace(f"unique_key   = '{unique_key}',", f"unique_key   = '{unique_key}',\n    distribution = 'HASH({unique_key})',")
                content = content.replace(f"unique_key = '{unique_key}',", f"unique_key = '{unique_key}',\n    distribution = 'HASH({unique_key})',")
        
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
