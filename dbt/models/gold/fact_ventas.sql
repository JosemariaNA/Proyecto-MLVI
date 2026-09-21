{{ config(
    materialized = 'incremental',
    unique_key   = 'venta_detalle_id',
    incremental_strategy = 'merge'
) }}

/*  FactVentas — tabla de hechos transaccional.

    Grano: una fila por linea de detalle de pedido (venta_detalle_id).
    Es el grano mas fino disponible; cualquier agregacion posterior
    (por dia, cliente, producto) se deriva de aqui sin perder detalle.

    Distribucion HASH sobre venta_detalle_id: reparte uniforme y evita
    sesgo. Todas las dimensiones son REPLICATE, de modo que los joins
    del modelo estrella se resuelven sin movimiento de datos.

    Resolucion de claves SCD2: se busca la version de la dimension
    vigente en la fecha de la venta, no la vigente hoy. Es lo que hace
    que un reporte historico muestre el precio y la categoria que el
    producto tenia cuando se vendio.

    Integridad referencial: los joins son LEFT y caen al miembro
    desconocido (-1). Un maestro que llega tarde degrada el reporte,
    no borra la venta.                                                  */

with detalle as (
    select *
    from {{ ref('slv_venta_detalle') }}
    where es_borrado = 0

    {% if is_incremental() %}
      -- Se reprocesa la linea si cambio el detalle O si cambio su
      -- cabecera: un cambio de estado del pedido altera el hecho aunque
      -- la linea no se haya tocado.
      and (
            ingested_at > {{ obtener_watermark('gold', 'fact_ventas') }}
         or venta_id in (
                select venta_id
                from {{ ref('slv_ventas') }}
                where ingested_at > {{ obtener_watermark('gold', 'fact_ventas') }}
            )
      )
    {% endif %}
),

cabecera as (
    select *
    from {{ ref('slv_ventas') }}
    where es_borrado = 0
      and es_venta_efectiva = 1     -- definicion conformada en Silver
),

hechos as (
    select
        d.venta_detalle_id,
        d.venta_id,
        c.fecha_venta,
        coalesce(c.fecha_key, -1)                       as fecha_key,
        c.cliente_id,
        c.canal_id,
        c.sucursal_id,
        d.producto_id,
        d.cantidad,
        d.precio_unitario,
        d.descuento,
        d.importe,
        d.tiene_descuadre,
        d.ingested_at
    from detalle   as d
    inner join cabecera as c
            on c.venta_id = d.venta_id
)

select
    h.venta_detalle_id,
    h.venta_id,

    -- Claves foraneas del modelo estrella
    h.fecha_key,
    {{ resolver_dimension('h.cliente_id',  'dc', 'cliente_key')  }}  as cliente_key,
    {{ resolver_dimension('h.producto_id', 'dp', 'producto_key') }}  as producto_key,
    {{ resolver_dimension('h.canal_id',    'dn', 'canal_key')    }}  as canal_key,
    {{ resolver_dimension('h.sucursal_id', 'ds', 'sucursal_key') }}  as sucursal_key,

    -- Claves naturales: se conservan para auditoria y trazabilidad
    h.cliente_id,
    h.producto_id,
    h.canal_id,
    h.sucursal_id,
    h.fecha_venta,

    -- Medidas aditivas
    h.cantidad,
    h.precio_unitario,
    h.descuento,
    h.importe,
    cast(h.cantidad * coalesce(dp.costo_unitario, 0) as decimal(19,4)) as costo,
    cast(h.importe - (h.cantidad * coalesce(dp.costo_unitario, 0))
         as decimal(19,4))                                            as margen,

    h.tiene_descuadre,
    h.ingested_at

from hechos as h

-- SCD2: version vigente en la fecha de la venta
left join {{ ref('dim_cliente') }} as dc
       on dc.cliente_id = h.cliente_id
      and h.fecha_venta >= dc.valido_desde
      and h.fecha_venta <  dc.valido_hasta

left join {{ ref('dim_producto') }} as dp
       on dp.producto_id = h.producto_id
      and h.fecha_venta >= dp.valido_desde
      and h.fecha_venta <  dp.valido_hasta

-- SCD1: una sola version
left join {{ ref('dim_canal') }} as dn
       on dn.canal_id = h.canal_id

left join {{ ref('dim_sucursal') }} as ds
       on ds.sucursal_id = h.sucursal_id
