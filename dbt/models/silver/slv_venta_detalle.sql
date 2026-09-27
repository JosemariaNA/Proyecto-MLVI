{{ config(
    materialized = 'incremental',
    unique_key   = 'venta_detalle_id',
    distribution = 'HASH(venta_detalle_id)',
    incremental_strategy = 'merge'
) }}

/*  Silver: detalle de venta. Este es el grano del negocio y el grano
    futuro de FactVentas: una linea por producto dentro de un pedido.

    Se distribuye por venta_id, no por venta_detalle_id, para que el
    join contra la cabecera ocurra dentro de cada distribucion y no
    genere movimiento innecesario de datos.

    LineAmount llega calculado del OLTP pero no se confia en el: se
    recalcula y se guarda la diferencia, de modo que una inconsistencia
    del origen se detecta en vez de propagarse a los reportes.          */

with eventos as (
    {{ ultimo_evento_cdc(source('bronze', 'sales_order_lines'), 'sales_order_line_id',
                         'silver', 'slv_venta_detalle') }}
),

calculado as (
    select
           cast(sales_order_line_id as nvarchar(50))     as venta_detalle_id,
           cast(sales_order_id as nvarchar(50))          as venta_id,
           cast(product_id as nvarchar(50))              as producto_id,
           cast(coalesce(quantity, round(line_subtotal / nullif(unit_price, 0), 0)) as int) as cantidad,
           cast(unit_price as decimal(19,4))              as precio_unitario,
           cast(coalesce(discount_amount, line_subtotal * coalesce(discount_rate, 0)) as decimal(19,4)) as descuento,
           cast(line_total as decimal(19,4))              as importe_origen,
           cast(coalesce(line_subtotal, 0) - coalesce(discount_amount, line_subtotal * coalesce(discount_rate, 0))
             as decimal(19,4))                      as importe_calculado,
           cast(getutcdate() as datetime2(3)) as actualizado_en,
        {{ es_borrado() }}                          as es_borrado,
        cast(null as binary(10))                              as lsn_origen,
        cast(getutcdate() as datetime2(3)) as ingested_at
    from eventos
)

select
    venta_detalle_id,
    venta_id,
    producto_id,
    cantidad,
    precio_unitario,
    descuento,
    importe_origen,
    importe_calculado,
    -- El importe que consume Gold es el recalculado: una sola definicion.
    importe_calculado                               as importe,
    abs(importe_origen - importe_calculado)         as diferencia_importe,
    cast(case when abs(importe_origen - importe_calculado) > 0.01
              then 1 else 0 end as bit)             as tiene_descuadre,
    actualizado_en,
    es_borrado,
    lsn_origen,
    ingested_at
from calculado
