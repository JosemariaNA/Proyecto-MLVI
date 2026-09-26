/* =====================================================================
   AzureDW — Bateria de validacion manual
   Ejecutar en Synapse MessyOpsDW despues de cada despliegue y tras el
   primer microlote real. Complementa (no sustituye) los tests de dbt.
   Por CLI:  scripts/02_desplegar_sql.sh validar
   ===================================================================== */

-- V0 (Bronze) vive en sql/05_validar_bronze.sql.

-- ---------------------------------------------------------------------
-- V1. Existencia de objetos: 5 esquemas, tablas meta y 16 tablas externas bronze.
-- ---------------------------------------------------------------------
SELECT 'esquemas' AS control, name AS objeto FROM sys.schemas
WHERE name IN ('bronze','silver','gold','meta','stg')
UNION ALL
SELECT 'tablas_meta', s.name + '.' + t.name
FROM sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE s.name = 'meta'
UNION ALL
SELECT 'tablas_externas_bronze', s.name + '.' + t.name
FROM sys.external_tables t JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE s.name = 'bronze';

-- ---------------------------------------------------------------------
-- V2. Salud del pipeline: retraso por entidad y fallos de calidad.
--     Ninguna entidad deberia superar los 30 minutos de retraso.
-- ---------------------------------------------------------------------
SELECT * FROM meta.vw_pipeline_health ORDER BY minutos_de_retraso DESC;

-- ---------------------------------------------------------------------
-- V3. Reconciliacion Bronze -> Silver por entidad.
--     Se comparan claves distintas, no filas: Bronze tiene N eventos
--     por clave y Silver exactamente uno.
-- ---------------------------------------------------------------------
SELECT 'clientes' AS entidad,
    (SELECT COUNT(DISTINCT customer_id) FROM bronze.customers WHERE cdc_operation IN ('I','U')) AS claves_bronze,
       (SELECT COUNT(*) FROM silver.slv_clientes)                                              AS filas_silver
UNION ALL
SELECT 'productos',
    (SELECT COUNT(DISTINCT product_id) FROM bronze.products WHERE cdc_operation IN ('I','U')),
       (SELECT COUNT(*) FROM silver.slv_productos)
UNION ALL
SELECT 'ventas',
    (SELECT COUNT(DISTINCT sales_order_id) FROM bronze.sales_orders WHERE cdc_operation IN ('I','U')),
       (SELECT COUNT(*) FROM silver.slv_ventas)
UNION ALL
SELECT 'detalle',
    (SELECT COUNT(DISTINCT sales_order_line_id) FROM bronze.sales_order_lines WHERE cdc_operation IN ('I','U')),
       (SELECT COUNT(*) FROM silver.slv_venta_detalle);

-- ---------------------------------------------------------------------
-- V4. Reconciliacion Silver -> Gold por mes.
--     Las dos columnas de importe deben coincidir hasta el centavo.
-- ---------------------------------------------------------------------
WITH silver_agg AS (
    SELECT v.fecha_key / 100 AS anio_mes,
           COUNT_BIG(*)      AS filas,
           SUM(d.importe)    AS importe
    FROM   silver.slv_venta_detalle d
    JOIN   silver.slv_ventas        v ON v.venta_id = d.venta_id
    WHERE  d.es_borrado = 0 AND v.es_borrado = 0 AND v.es_venta_efectiva = 1
    GROUP BY v.fecha_key / 100
),
gold_agg AS (
    SELECT fecha_key / 100 AS anio_mes,
           COUNT_BIG(*)    AS filas,
           SUM(importe)    AS importe
    FROM   gold.fact_ventas
    GROUP BY fecha_key / 100
)
SELECT COALESCE(s.anio_mes, g.anio_mes) AS anio_mes,
       s.filas AS filas_silver, g.filas AS filas_gold,
       s.importe AS importe_silver, g.importe AS importe_gold,
       CASE WHEN COALESCE(s.filas,0) = COALESCE(g.filas,0)
             AND ABS(COALESCE(s.importe,0) - COALESCE(g.importe,0)) <= 0.01
            THEN 'OK' ELSE 'DESCUADRE' END AS veredicto
FROM   silver_agg s
FULL OUTER JOIN gold_agg g ON g.anio_mes = s.anio_mes
ORDER BY anio_mes;

-- ---------------------------------------------------------------------
-- V5. Integridad del esquema estrella: ningun hecho debe apuntar a una
--     clave inexistente. Las que caen al -1 se cuentan aparte, porque
--     son toleradas pero no deben crecer sin control.
-- ---------------------------------------------------------------------
SELECT 'fecha'    AS dimension,
       SUM(CASE WHEN d.fecha_key    IS NULL THEN 1 ELSE 0 END) AS huerfanos,
       SUM(CASE WHEN f.fecha_key    = -1    THEN 1 ELSE 0 END) AS desconocidos
FROM gold.fact_ventas f LEFT JOIN gold.dim_fecha d ON d.fecha_key = f.fecha_key
UNION ALL
SELECT 'cliente',
       SUM(CASE WHEN d.cliente_key IS NULL THEN 1 ELSE 0 END),
       SUM(CASE WHEN f.cliente_key = -1    THEN 1 ELSE 0 END)
FROM gold.fact_ventas f LEFT JOIN gold.dim_cliente d ON d.cliente_key = f.cliente_key
UNION ALL
SELECT 'producto',
       SUM(CASE WHEN d.producto_key IS NULL THEN 1 ELSE 0 END),
       SUM(CASE WHEN f.producto_key = -1    THEN 1 ELSE 0 END)
FROM gold.fact_ventas f LEFT JOIN gold.dim_producto d ON d.producto_key = f.producto_key;

-- ---------------------------------------------------------------------
-- V6. Invariante SCD2: exactamente una version vigente por clave.
--     Cualquier fila devuelta aqui es un bug que duplicaria los hechos.
-- ---------------------------------------------------------------------
SELECT 'dim_cliente' AS dimension, cliente_id AS clave, COUNT(*) AS versiones_vigentes
FROM   gold.dim_cliente WHERE es_version_vigente = 1 AND cliente_id <> '-1'
GROUP BY cliente_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'dim_producto', producto_id, COUNT(*)
FROM   gold.dim_producto WHERE es_version_vigente = 1 AND producto_id <> '-1'
GROUP BY producto_id HAVING COUNT(*) > 1;

-- ---------------------------------------------------------------------
-- V7. Calidad acumulada de las ultimas 24 h.
-- ---------------------------------------------------------------------
SELECT entity_name, test_name, severity, SUM(failed_rows) AS filas_fallidas,
       MAX(detected_at) AS ultimo_fallo
FROM   meta.data_quality_log
WHERE  detected_at > DATEADD(DAY, -1, SYSUTCDATETIME())
GROUP BY entity_name, test_name, severity
ORDER BY filas_fallidas DESC;

