/*  Los rangos de vigencia de una misma clave natural no pueden
    solaparse: si lo hicieran, un hecho casaria con dos versiones y la
    tabla de hechos se duplicaria silenciosamente en el join.          */

with rangos as (
    select cliente_id as clave_natural, valido_desde, valido_hasta, 'cliente' as dimension
    from {{ ref('dim_cliente') }}
    where cliente_id <> {{ var('unknown_key', -1) }}
    union all
    select producto_id, valido_desde, valido_hasta, 'producto'
    from {{ ref('dim_producto') }}
    where producto_id <> {{ var('unknown_key', -1) }}
)

select a.dimension, a.clave_natural, a.valido_desde, a.valido_hasta
from rangos as a
join rangos as b
  on  a.dimension     = b.dimension
  and a.clave_natural = b.clave_natural
  and a.valido_desde <> b.valido_desde
  and a.valido_desde <  b.valido_hasta
  and b.valido_desde <  a.valido_hasta
