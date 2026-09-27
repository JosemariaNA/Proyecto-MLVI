# Catálogo de datos

Propietario de todas las entidades: **Equipo de Datos**. El catálogo navegable completo se genera con `dbt docs generate && dbt docs serve`, que publica las descripciones de columnas y el grafo de linaje a partir de los `.yml` del proyecto.

| Capa | Entidad | Descripción | SLA de frescura | Consumidor |
|---|---|---|---|---|
| Bronze | `bronze.customers` … `bronze.warehouses` | Cambios CDC netos, crudos e inmutables (recurso CDC nativo de ADF) | 15 min (microlote) | dbt Silver |
| Silver | `slv_clientes` | Cliente limpio, una fila por clave | 15 min | Snapshot SCD2 |
| Silver | `slv_categorias` | Categorías con padre resuelto | 60 min | `slv_productos` |
| Silver | `slv_productos` | Producto con categoría y margen | 15 min | Snapshot SCD2 |
| Silver | `slv_canales` | Canal de venta | 60 min | `dim_canal` |
| Silver | `slv_sucursales` | Sucursal y geografía | 60 min | `dim_sucursal` |
| Silver | `slv_ventas` | Cabecera con estado conformado | 15 min | `fact_ventas` |
| Silver | `slv_venta_detalle` | Línea de venta con importe recalculado | 15 min | `fact_ventas` |
| Gold | `dim_fecha` | Calendario 2020–2030 | Estática | Power BI |
| Gold | `dim_cliente` | Cliente historizado (SCD2) | 15 min | Power BI |
| Gold | `dim_producto` | Producto historizado (SCD2) | 15 min | Power BI |
| Gold | `dim_canal` | Canal (SCD1) | 60 min | Power BI |
| Gold | `dim_sucursal` | Sucursal (SCD1) | 60 min | Power BI |
| Gold | `fact_ventas` | Ventas efectivas por línea | 15 min | Power BI |
| Meta | `etl_watermark` | Checkpoint de Silver y Gold | — | dbt |
| Meta | `vw_bronze_frescura` | Último microlote y retraso por entidad de Bronze (el checkpoint de LSN lo guarda el recurso CDC de ADF) | — | Operación |
| Meta | `data_quality_log` | Histórico de fallos de calidad | — | Operación / Power BI |
| Meta | `reconciliation_log` | Conteos entre capas | — | Operación |
| Meta | `vw_pipeline_health` | Retraso y fallos por entidad | — | Operación |

## Definiciones de negocio conformadas

- **Venta efectiva:** pedido con estado `COMPLETED`. Se define una sola vez en `slv_ventas.es_venta_efectiva`; ningún dashboard debe reinterpretarla.
- **Importe:** `cantidad × precio_unitario − descuento`, recalculado en Silver. El importe que trae el OLTP se conserva solo para detectar descuadres.
- **Margen:** `importe − cantidad × costo_unitario`, con el costo vigente en la fecha de la venta.
