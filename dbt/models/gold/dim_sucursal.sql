{{ config(
    materialized = 'table'
) }}

/*  DimSucursal — SCD tipo 1, con la geografia aplanada.
    Igual criterio que DimCanal: cardinalidad baja, cambios raros y el
    negocio prefiere la vision actual sobre la historica.               */

select
    {{ clave_sustituta(['sucursal_id']) }}      as sucursal_key,
    sucursal_id,
    sucursal_nombre,
    ciudad,
    region,
    pais,
    es_borrado,
    sysutcdatetime()                            as ingested_at
from {{ ref('slv_sucursales') }}

union all

select {{ var('unknown_key', -1) }}, cast('-1' as nvarchar(50)), 'Desconocido', 'Desconocido',
       'Desconocido', 'DESCONOCIDO', cast(0 as bit), sysutcdatetime()
