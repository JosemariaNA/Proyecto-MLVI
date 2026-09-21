/*  Reconciliacion Silver -> Gold por dia.
    Compara conteo de lineas e importe entre el detalle de Silver
    (filtrado por la misma regla de venta efectiva) y FactVentas.
    Tolerancia de 0.01 por redondeo decimal. Devuelve filas = falla.   */

with esperado as (
    select
        v.fecha_key,
        count_big(*)                    as filas_silver,
        sum(d.importe)                  as importe_silver
    from {{ ref('slv_venta_detalle') }} as d
    join {{ ref('slv_ventas') }}        as v on v.venta_id = d.venta_id
    where d.es_borrado = 0
      and v.es_borrado = 0
      and v.es_venta_efectiva = 1
    group by v.fecha_key
),

obtenido as (
    select
        fecha_key,
        count_big(*)                    as filas_gold,
        sum(importe)                    as importe_gold
    from {{ ref('fact_ventas') }}
    group by fecha_key
)

select
    coalesce(e.fecha_key, o.fecha_key)  as fecha_key,
    e.filas_silver,
    o.filas_gold,
    e.importe_silver,
    o.importe_gold
from esperado as e
full outer join obtenido as o
  on o.fecha_key = e.fecha_key
where coalesce(e.filas_silver, 0) <> coalesce(o.filas_gold, 0)
   or abs(coalesce(e.importe_silver, 0) - coalesce(o.importe_gold, 0)) > 0.01
