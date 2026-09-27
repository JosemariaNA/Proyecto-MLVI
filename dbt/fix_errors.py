with open('dbt/macros/cdc.sql', 'r') as f:
    c = f.read()
c = c.replace('-- No hay cdc_operation ni lsn disponibles en modo auto, el snapshot ya viene deduplicado.', 'WHERE 1=1')
with open('dbt/macros/cdc.sql', 'w') as f:
    f.write(c)

with open('dbt/models/silver/slv_categorias.sql', 'r') as f:
    c = f.read()
c = c.replace('order by cast(null as binary(10)) desc, cast(null as binary(10)) desc', 'order by upper(categoria_id)')
with open('dbt/models/silver/slv_categorias.sql', 'w') as f:
    f.write(c)

with open('dbt/models/silver/slv_canales.sql', 'r') as f:
    c = f.read()
c = c.replace('order by cast(null as binary(10)) desc, cast(null as binary(10)) desc', 'order by upper(canal_id)')
with open('dbt/models/silver/slv_canales.sql', 'w') as f:
    f.write(c)
