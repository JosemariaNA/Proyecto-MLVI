{{ config(
    materialized = 'incremental',
    unique_key   = 'canal_id',
    incremental_strategy = 'merge'
) }}

/*  Silver: canales de venta. Tabla pequena y estable -> REPLICATE.     */

with eventos as (
    {{ ultimo_evento_cdc(source('bronze', 'sales_orders'), 'sales_order_id',
                         'silver', 'slv_canales') }}
),
ordenados as (
    select upper({{ limpiar_texto('sales_channel') }}) as canal_id,
           upper({{ limpiar_texto('sales_channel') }}) as canal_nombre,
           cast(null as nvarchar(64)) as canal_tipo,
           cast(0 as bit) as es_borrado,
           [__$start_lsn] as lsn_origen,
           cast(ingested_at as datetime2(3)) as ingested_at,
           row_number() over (partition by upper({{ limpiar_texto('sales_channel') }})
                              order by [__$start_lsn] desc, [__$seqval] desc) as rn
    from eventos
    where {{ limpiar_texto('sales_channel') }} is not null
)

select
    canal_id, canal_nombre, canal_tipo,
    ingested_at as actualizado_en, es_borrado, lsn_origen, ingested_at
from ordenados
where rn = 1
