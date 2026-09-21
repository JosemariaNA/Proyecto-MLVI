{{ config(
    materialized = 'table'
) }}

/*  DimProducto — SCD tipo 2.
    Conserva la jerarquia de categoria aplanada (categoria y categoria
    padre). Esa es la decision estrella-vs-copo-de-nieve de este modelo:
    con solo dos niveles y baja cardinalidad, aplanar gana en velocidad
    de consulta y no cuesta mantenimiento. Si la jerarquia creciera a
    cuatro o cinco niveles con atributos propios, tocaria normalizar
    DimCategoria aparte y pasar a copo de nieve.                       */

with versiones as (
    select
        producto_id,
        sku,
        nombre_producto,
        categoria_id,
        categoria_nombre,
        categoria_padre_id,
        categoria_padre_nombre,
        marca,
        costo_unitario,
        precio_unitario,
        margen_unitario,
        activo,
        es_borrado,
        dbt_valid_from                              as valido_desde,
        coalesce(dbt_valid_to, cast('9999-12-31' as datetime2(3))) as valido_hasta
    from {{ ref('snp_productos') }}
)

select
    {{ clave_sustituta(['producto_id', 'valido_desde']) }}   as producto_key,
    producto_id,
    sku,
    nombre_producto,
    categoria_id,
    categoria_nombre,
    categoria_padre_id,
    categoria_padre_nombre,
    marca,
    costo_unitario,
    precio_unitario,
    margen_unitario,
    activo,
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
    'DESCONOCIDO', 'Desconocido', cast('-1' as nvarchar(100)), 'Desconocido', null, null, 'Desconocido',
    cast(0 as decimal(19,4)), cast(0 as decimal(19,4)), null,
    cast(0 as bit), cast(0 as bit),
    cast('1900-01-01' as datetime2(3)), cast('9999-12-31' as datetime2(3)),
    cast(1 as bit), sysutcdatetime()
