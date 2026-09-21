# Modelo dimensional

## Capa Silver — datos limpios y conformados

Silver tiene una fila por clave de negocio con el último estado conocido según el CDC. Cada modelo resuelve los eventos de Bronze con el mismo macro (`ultimo_evento_cdc`), que ordena por `(__$start_lsn, __$seqval)` y no por hora de ingesta, porque dos transacciones pueden llegar al lake desordenadas. La imagen previa de los updates (`__$operation = 3`) se descarta y los deletes se conservan como borrado lógico (`es_borrado = 1`).

| Modelo | Grano | Reglas que resuelve |
|---|---|---|---|
| `slv_clientes` | cliente_id | trim, email en minúsculas, teléfono sin formato, bandera `email_valido` |
| `slv_categorias` | categoria_id | categoría derivada de `products.category` |
| `slv_productos` | producto_id | nombre y categoría normalizados, margen precalculado |
| `slv_canales` | canal_id | canal derivado de `sales_orders.sales_channel` |
| `slv_sucursales` | sucursal_id | geografía derivada de `warehouses` |
| `slv_ventas` | venta_id | fechas reparadas, estado normalizado y regla `es_venta_efectiva` |
| `slv_venta_detalle` | venta_detalle_id | cantidad/descuento reparados e importe recalculado |

## Capa Gold — esquema estrella

```
                 dim_fecha
                        │
dim_cliente ──┐         │         ┌── dim_producto
 (SCD2)       ├──── fact_ventas ──┤    (SCD2)
dim_canal ────┘       fact_ventas └── dim_sucursal
 (SCD1)                                 (SCD1)
```

**Grano de `fact_ventas`:** una línea de detalle de pedido. Es el grano más fino disponible; cualquier agregado se deriva de aquí.

**Medidas:** `cantidad`, `precio_unitario`, `descuento`, `importe`, `costo` (cantidad × costo de la versión del producto vigente en la fecha de la venta) y `margen`.

**Resolución SCD2:** el hecho se une a la versión de la dimensión vigente en `fecha_venta`, no a la vigente hoy. Así un reporte histórico muestra el precio y la categoría que el producto tenía cuando se vendió.

### ¿Estrella o copo de nieve?

Se eligió **estrella**. La jerarquía de categoría tiene dos niveles y decenas de filas, así que aplanarla en `dim_producto` evita un join en cada consulta y no complica el mantenimiento. Se justificaría pasar a copo de nieve (una `dim_categoria` separada) si la jerarquía creciera a cuatro o más niveles con atributos propios, o si varias dimensiones empezaran a compartirla.

## Control incremental

| Capa | Checkpoint | Dónde vive |
|---|---|---|
| Bronze | LSN del CDC | `meta.cdc_control` (lo escribe ADF) |
| Silver | `ingested_at` máximo materializado, menos 15 min de margen | `meta.etl_watermark` (post-hook de dbt) |
| Gold | `ingested_at` del detalle **o** de su cabecera | `meta.etl_watermark` |

El watermark se calcula a partir de lo que quedó escrito en la tabla destino, no de la hora del reloj: si un modelo falla a medias, el checkpoint no avanza y el siguiente microlote repite el trabajo.

## Pruebas

106 tests en total. Además de los genéricos (`not_null`, `unique`, `relationships`, `accepted_values`, `accepted_range`), hay cinco singulares que protegen los invariantes que no se ven a simple vista:

| Test | Qué detecta |
|---|---|
| `assert_bronze_silver_sin_perdida` | eventos de Bronze que el filtro incremental dejó fuera de Silver |
| `assert_reconciliacion_silver_gold` | diferencias diarias de conteo o importe entre Silver y Gold |
| `assert_fact_sin_duplicar_por_scd` | filas de hechos multiplicadas por un join SCD2 mal resuelto |
| `assert_scd2_una_version_vigente` | más de una versión vigente por clave |
| `assert_scd2_sin_solapamiento` | rangos de vigencia que se pisan |

Los tests de integridad referencial en Silver tienen severidad `warn` porque un maestro puede llegar en el microlote siguiente; en Gold son `error` porque el miembro desconocido garantiza que nunca debería haber huérfanos.
