{{ config(
    materialized = 'table'
) }}

/*  DimCanal — SCD tipo 1.
    El canal no se historiza: si un canal se renombra, el negocio quiere
    ver todo el historico con el nombre nuevo. Sobrescribir es la
    decision correcta aqui, y ademas mantiene la dimension trivial.     */

select
    {{ clave_sustituta(['canal_id']) }}         as canal_key,
    canal_id,
    canal_nombre,
    canal_tipo,
    es_borrado,
    sysutcdatetime()                            as ingested_at
from {{ ref('slv_canales') }}

union all

select {{ var('unknown_key', -1) }}, cast('-1' as nvarchar(100)), 'Desconocido', 'DESCONOCIDO',
       cast(0 as bit), sysutcdatetime()
