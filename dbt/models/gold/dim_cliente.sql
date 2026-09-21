{{ config(
    materialized = 'table'
) }}

/*  DimCliente — SCD tipo 2.
    Se construye sobre el snapshot, que ya resolvio el versionado. Aqui
    solo se agrega la clave sustituta, las banderas de vigencia y el
    miembro desconocido.

    La clave sustituta es un hash determinista de (cliente_id, valido_desde):
    reconstruir la dimension produce exactamente las mismas claves, asi
    que los hechos ya cargados no se invalidan.                        */

with versiones as (
    select
        cliente_id,
        nombre,
        apellido,
        nombre_completo,
        email,
        telefono,
        pais,
        ciudad,
        email_valido,
        creado_en,
        es_borrado,
        dbt_valid_from                              as valido_desde,
        coalesce(dbt_valid_to, cast('9999-12-31' as datetime2(3))) as valido_hasta
    from {{ ref('snp_clientes') }}
)

select
    {{ clave_sustituta(['cliente_id', 'valido_desde']) }}    as cliente_key,
    cliente_id,
    nombre,
    apellido,
    nombre_completo,
    email,
    telefono,
    pais,
    ciudad,
    email_valido,
    creado_en,
    es_borrado,
    valido_desde,
    valido_hasta,
    cast(case when valido_hasta = cast('9999-12-31' as datetime2(3))
              then 1 else 0 end as bit)                      as es_version_vigente,
    sysutcdatetime()                                         as ingested_at
from versiones

union all

select
    {{ var('unknown_key', -1) }}, cast('-1' as nvarchar(50)),
    'Desconocido', 'Desconocido', 'Desconocido',
    null, null, 'DESCONOCIDO', 'Desconocido',
    cast(0 as bit), null, cast(0 as bit),
    cast('1900-01-01' as datetime2(3)), cast('9999-12-31' as datetime2(3)),
    cast(1 as bit), sysutcdatetime()
