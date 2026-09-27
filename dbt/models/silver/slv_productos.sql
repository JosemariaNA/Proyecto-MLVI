{{ config(
    materialized = 'incremental',
    unique_key   = 'producto_id',
    distribution = 'HASH(producto_id)',
    incremental_strategy = 'merge'
) }}

/*  Silver: productos conformados, con la categoria ya resuelta.
    La jerarquia de categorias se aplana aqui (categoria + categoria
    padre) para que Gold pueda elegir entre estrella y copo de nieve
    sin volver a tocar Bronze.                                         */

with eventos as (
    {{ ultimo_evento_cdc(source('bronze', 'products'), 'product_id',
                         'silver', 'slv_productos') }}
),

categorias as (
    select * from {{ ref('slv_categorias') }}
),

limpio as (
    select
        cast(p.product_id as nvarchar(50))          as producto_id,
        cast(p.product_id as nvarchar(64))          as sku,
        {{ limpiar_texto('p.product_name') }}       as nombre_producto,
        upper({{ limpiar_texto('p.category') }})    as categoria_id,
        {{ limpiar_texto('p.primary_supplier_id') }} as marca,
        cast(p.unit_cost as decimal(19,4))           as costo_unitario,
        cast(p.list_price as decimal(19,4))          as precio_unitario,
        cast(case when p.is_discontinued = 1 then 0 else 1 end as bit) as activo,
        cast(coalesce(p.discontinued_date, p.product_launch_date) as datetime2(3)) as actualizado_en,
        {{ es_borrado() }}                          as es_borrado,
        cast(null as binary(10))                            as lsn_origen,
        cast(getutcdate() as datetime2(3)) as ingested_at
    from eventos as p
)

select
    l.producto_id,
    l.sku,
    l.nombre_producto,
    l.categoria_id,
    c.categoria_nombre,
    c.categoria_padre_id,
    c.categoria_padre_nombre,
    l.marca,
    l.costo_unitario,
    l.precio_unitario,
    -- Margen precalculado en Silver: es una regla de negocio estable y
    -- evita repetir la formula en cada modelo Gold y en cada dashboard.
    case when l.precio_unitario > 0
         then cast((l.precio_unitario - l.costo_unitario) / l.precio_unitario
                   as decimal(9,6))
    end                                             as margen_unitario,
    l.activo,
    l.actualizado_en,
    l.es_borrado,
    l.lsn_origen,
    l.ingested_at
from limpio as l
left join categorias as c
       on c.categoria_id = l.categoria_id
