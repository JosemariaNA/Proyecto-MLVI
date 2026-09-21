/*  Guarda contra el fallo mas caro del modelo estrella: que el join por
    rango de una dimension SCD2 multiplique las filas de hechos.
    El conteo de FactVentas no puede superar al de lineas elegibles en
    Silver.                                                            */

with gold as (
    select count_big(*) as filas from {{ ref('fact_ventas') }}
),
silver as (
    select count_big(*) as filas
    from {{ ref('slv_venta_detalle') }} as d
    join {{ ref('slv_ventas') }}        as v on v.venta_id = d.venta_id
    where d.es_borrado = 0 and v.es_borrado = 0 and v.es_venta_efectiva = 1
)
select g.filas as filas_gold, s.filas as filas_silver
from gold as g cross join silver as s
where g.filas > s.filas
