{{ config(
    materialized = 'incremental',
    unique_key   = 'sucursal_id',
    distribution = 'HASH(sucursal_id)',
    incremental_strategy = 'merge'
) }}

/*  Silver: sucursales con geografia normalizada en mayusculas para que
    los joins y los filtros de Power BI no dependan de como se capturo.  */

with eventos as (
    {{ ultimo_evento_cdc(source('bronze', 'warehouses'), 'warehouse_id',
                         'silver', 'slv_sucursales') }}
)

select
    cast(warehouse_id as nvarchar(50))      as sucursal_id,
    {{ limpiar_texto('warehouse_name') }}   as sucursal_nombre,
    {{ limpiar_texto('city') }}             as ciudad,
    cast(null as nvarchar(100))             as region,
    upper({{ limpiar_texto('country') }})   as pais,
    cast(getutcdate() as datetime2(3)) as actualizado_en,
    {{ es_borrado() }}                      as es_borrado,
    cast(null as binary(10))                          as lsn_origen,
    cast(getutcdate() as datetime2(3)) as ingested_at
from eventos
