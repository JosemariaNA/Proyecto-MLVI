{{ config(
    materialized = 'incremental',
    unique_key   = 'venta_id',
    distribution = 'HASH(venta_id)',
    incremental_strategy = 'merge'
) }}

/*  Silver: cabecera de venta.
    Se conserva el grano del OLTP (una fila por pedido) y se normaliza
    el estado, que en el origen llega con mayusculas y espacios mezclados.
    El estado se conforma aqui porque es el filtro que decide que entra
    a la tabla de hechos: si cada consumidor lo interpretara por su
    cuenta, dos dashboards darian cifras distintas.                     */

with eventos as (
    {{ ultimo_evento_cdc(source('bronze', 'sales_orders'), 'sales_order_id',
                         'silver', 'slv_ventas') }}
),
facturas as (
    {{ ultimo_evento_cdc(source('bronze', 'invoices'), 'invoice_id',
                         'silver', 'slv_facturas_para_ventas') }}
),
envios as (
    {{ ultimo_evento_cdc(source('bronze', 'shipments'), 'shipment_id',
                         'silver', 'slv_envios_para_ventas') }}
),
fechas as (
    select sales_order_id,
           max(coalesce(invoice_date, dateadd(day, -payment_term_days, due_date))) as fecha_factura
    from facturas
    group by sales_order_id
),
primer_envio as (
    select sales_order_id, min(ship_date) as fecha_envio
    from envios
    group by sales_order_id
)

select
    cast(o.sales_order_id as nvarchar(50))       as venta_id,
    cast(o.customer_id as nvarchar(50))          as cliente_id,
    upper({{ limpiar_texto('o.sales_channel') }}) as canal_id,
    cast(o.warehouse_id as nvarchar(50))         as sucursal_id,
    cast(coalesce(
        case when o.order_date > e.fecha_envio then f.fecha_factura else o.order_date end,
        f.fecha_factura, e.fecha_envio
    ) as datetime2(3))                           as fecha_venta,
    {{ clave_fecha('coalesce(o.order_date, f.fecha_factura, e.fecha_envio)') }} as fecha_key,
    upper({{ limpiar_texto('o.order_status') }}) as estado,
    cast(case when upper(ltrim(rtrim(o.order_status))) = 'COMPLETED'
              then 1 else 0 end as bit)         as es_venta_efectiva,
    cast(null as char(3))                        as moneda,
    cast(getutcdate() as datetime2(3)) as actualizado_en,
    {{ es_borrado() }}                          as es_borrado,
    cast(null as binary(10))                             as lsn_origen,
    cast(getutcdate() as datetime2(3)) as ingested_at
from eventos as o
left join fechas as f on f.sales_order_id = o.sales_order_id
left join primer_envio as e on e.sales_order_id = o.sales_order_id
