{{ config(
    materialized = 'incremental',
    unique_key   = 'categoria_id',
    distribution = 'HASH(categoria_id)',
    incremental_strategy = 'merge'
) }}

/*  Silver: catalogo de categorias con su padre resuelto en un nivel.
    Se replica en todas las distribuciones porque es una tabla pequena
    que participa en joins frecuentes: REPLICATE elimina el movimiento
    de datos que provocaria un HASH sobre una tabla de decenas de filas. */

with eventos as (
    {{ ultimo_evento_cdc(source('bronze', 'products'), 'product_id',
                         'silver', 'slv_categorias') }}
),
categorias as (
    select
        upper({{ limpiar_texto('category') }}) as categoria_id,
        upper({{ limpiar_texto('category') }}) as categoria_nombre,
        cast(null as nvarchar(100)) as categoria_padre_id,
        cast(null as nvarchar(100)) as categoria_padre_nombre,
        cast(0 as bit) as es_borrado,
        cast(null as binary(10)) as lsn_origen,
        cast(getutcdate() as datetime2(3)) as ingested_at,
        row_number() over (
            partition by upper({{ limpiar_texto('category') }})
            order by upper({{ limpiar_texto('category') }}) desc
        ) as rn
    from eventos
    where {{ limpiar_texto('category') }} is not null
)
select categoria_id, categoria_nombre, categoria_padre_id,
       categoria_padre_nombre, es_borrado, lsn_origen, ingested_at
from categorias
where rn = 1
