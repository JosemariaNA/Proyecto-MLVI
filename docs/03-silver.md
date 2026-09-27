# Capa Silver — Datos limpios y conformados

La capa Silver tiene el propósito de almacenar una versión limpia, unificada y filtrada de los datos transaccionales, dejando una sola fila por clave de negocio con el último estado conocido según el CDC.

## Resolución de Eventos CDC

Cada modelo resuelve los eventos de Bronze utilizando el macro `ultimo_evento_cdc`. Este macro ordena los registros por la marca de tiempo `ingested_at` provista por el recurso CDC de ADF. 

Al recibir cambios netos por microlote:
* Los **borrados** se conservan como borrado lógico (`cdc_operation = 'D'` se mapea a la bandera `es_borrado = 1`).
* Las **actualizaciones e inserciones** llegan listas para procesarse (`cdc_operation = 'U'` o `'I'`).

## Reglas de Negocio Implementadas

| Modelo | Grano | Reglas que resuelve |
|---|---|---|---|
| `slv_clientes` | cliente_id | trim, email en minúsculas, teléfono sin formato, bandera `email_valido` |
| `slv_categorias` | categoria_id | categoría derivada de `products.category` |
| `slv_productos` | producto_id | nombre y categoría normalizados, margen precalculado |
| `slv_canales` | canal_id | canal derivado de `sales_orders.sales_channel` |
| `slv_sucursales` | sucursal_id | geografía derivada de `warehouses` |
| `slv_ventas` | venta_id | fechas reparadas, estado normalizado y regla `es_venta_efectiva` |
| `slv_venta_detalle` | venta_detalle_id | cantidad/descuento reparados e importe recalculado |

## Control Incremental en Silver

| Capa | Checkpoint | Dónde vive |
|---|---|---|
| Silver | `ingested_at` máximo materializado, menos 15 min de margen | `meta.etl_watermark` (post-hook de dbt) |

El watermark se calcula a partir de lo que quedó escrito en la tabla destino, no de la hora del reloj. Esto garantiza que si un modelo falla a medias, el checkpoint no avance y el siguiente microlote repita el trabajo de forma segura y sin pérdida de datos.
