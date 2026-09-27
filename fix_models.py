import glob, re

for file in glob.glob('dbt/models/silver/*.sql'):
    with open(file, 'r') as f:
        c = f.read()
    
    # Just replace the exact substrings using normal string replace, no regex for the complex ones!
    c = c.replace('[__]', 'cast(null as binary(10))')
    c = c.replace('[__]', 'cast(null as binary(10))')
    
    c = re.sub(r'(?i)order by cast\(null as binary\(10\)\) desc, cast\(null as binary\(10\)\) desc', 'order by (select null)', c)
    c = re.sub(r'(?i)order by\s+cast\(null as binary\(10\)\)\s+desc\s*,\s*cast\(null as binary\(10\)\)\s+desc', 'order by (select null)', c)

    c = re.sub(r'cast\(ingested_at as datetime2\(3\)\)', 'cast(getutcdate() as datetime2(3))', c)
    c = re.sub(r'o\.ingested_at', 'cast(getutcdate() as datetime2(3))', c)
    
    with open(file, 'w') as f:
        f.write(c)

with open('dbt/models/gold/dim_fecha.sql', 'r') as f:
    sql = f.read()

# Replace FROM L5 with FROM L5 WHERE ...
sql = sql.replace('FROM L5', 'FROM L5 WHERE (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL))) <= 30000')

with open('dbt/models/gold/dim_fecha.sql', 'w') as f:
    f.write(sql)
