/*  Invariante central de SCD tipo 2: cada clave natural debe tener
    exactamente una version vigente. Si aparecen dos, el snapshot se
    corrompio y los hechos se duplicarian al hacer el join por rango.
    Devuelve filas = falla.                                            */

select cliente_id, count(*) as versiones_vigentes
from {{ ref('dim_cliente') }}
where es_version_vigente = 1
  and cliente_id <> {{ var('unknown_key', -1) }}
group by cliente_id
having count(*) > 1

union all

select producto_id, count(*)
from {{ ref('dim_producto') }}
where es_version_vigente = 1
  and producto_id <> {{ var('unknown_key', -1) }}
group by producto_id
having count(*) > 1
