/*  Reconciliacion Bronze -> Silver.
    Toda clave natural que llego a Bronze con un insert o update debe
    existir en Silver. Si falta, el filtro incremental esta perdiendo
    eventos: es el fallo silencioso mas peligroso de un pipeline CDC.  */

select b.sales_order_line_id as clave_faltante, 'slv_venta_detalle' as modelo
from {{ source('bronze', 'sales_order_lines') }} as b
left join {{ ref('slv_venta_detalle') }}   as s
  on s.venta_detalle_id = b.sales_order_line_id
where b.[__$operation] in (2, 4)
  and s.venta_detalle_id is null

union all

select b.customer_id, 'slv_clientes'
from {{ source('bronze', 'customers') }} as b
left join {{ ref('slv_clientes') }}      as s on s.cliente_id = b.customer_id
where b.[__$operation] in (2, 4)
  and s.cliente_id is null
