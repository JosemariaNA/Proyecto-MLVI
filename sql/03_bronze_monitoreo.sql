/* =====================================================================
   AzureDW - Monitoreo de la capa Bronze (MessyOpsDW, Synapse)
   Ejecutar DESPUES de sql/00_bronze_external.sql.
   Por CLI:  scripts/02_desplegar_sql.sh bronze

   Reemplaza a sql/03_cdc_control.sql: con el recurso CDC nativo de ADF
   el checkpoint de LSN lo guarda el propio recurso, asi que ya no hace
   falta meta.cdc_control ni los procedimientos que lo actualizaban.
   Lo que si hace falta es ver desde el DW si Bronze esta recibiendo datos.
   ===================================================================== */

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'meta') EXEC('CREATE SCHEMA meta');
GO

IF OBJECT_ID('meta.vw_bronze_frescura', 'V') IS NOT NULL DROP VIEW meta.vw_bronze_frescura;
GO

/*  Una fila por entidad: ultimo microlote recibido, minutos de retraso y
    volumen por tipo de operacion. Con microlotes de 15 min, mas de 30 min
    sin datos nuevos significa que el recurso CDC esta detenido o fallando
    (o que el OLTP no tuvo actividad: revisar el estado del recurso).      */
CREATE VIEW meta.vw_bronze_frescura AS
WITH eventos AS (
    SELECT 'customers'            AS entidad, ingested_at, cdc_operation FROM bronze.customers
    UNION ALL SELECT 'products',             ingested_at, cdc_operation FROM bronze.products
    UNION ALL SELECT 'suppliers',            ingested_at, cdc_operation FROM bronze.suppliers
    UNION ALL SELECT 'warehouses',           ingested_at, cdc_operation FROM bronze.warehouses
    UNION ALL SELECT 'sales_orders',         ingested_at, cdc_operation FROM bronze.sales_orders
    UNION ALL SELECT 'sales_order_lines',    ingested_at, cdc_operation FROM bronze.sales_order_lines
    UNION ALL SELECT 'invoices',             ingested_at, cdc_operation FROM bronze.invoices
    UNION ALL SELECT 'payments',             ingested_at, cdc_operation FROM bronze.payments
    UNION ALL SELECT 'shipments',            ingested_at, cdc_operation FROM bronze.shipments
    UNION ALL SELECT 'returns',              ingested_at, cdc_operation FROM bronze.returns
    UNION ALL SELECT 'purchase_orders',      ingested_at, cdc_operation FROM bronze.purchase_orders
    UNION ALL SELECT 'purchase_order_lines', ingested_at, cdc_operation FROM bronze.purchase_order_lines
    UNION ALL SELECT 'supplier_invoices',    ingested_at, cdc_operation FROM bronze.supplier_invoices
    UNION ALL SELECT 'supplier_payments',    ingested_at, cdc_operation FROM bronze.supplier_payments
    UNION ALL SELECT 'inventory_snapshots',  ingested_at, cdc_operation FROM bronze.inventory_snapshots
    UNION ALL SELECT 'support_tickets',      ingested_at, cdc_operation FROM bronze.support_tickets
)
SELECT  entidad,
        COUNT_BIG(*)                                              AS eventos_totales,
        SUM(CASE WHEN cdc_operation = 'I' THEN 1 ELSE 0 END)      AS inserts,
        SUM(CASE WHEN cdc_operation = 'U' THEN 1 ELSE 0 END)      AS updates,
        SUM(CASE WHEN cdc_operation = 'D' THEN 1 ELSE 0 END)      AS deletes,
        MIN(ingested_at)                                          AS primer_microlote,
        MAX(ingested_at)                                          AS ultimo_microlote,
        DATEDIFF(MINUTE, MAX(ingested_at), SYSUTCDATETIME())      AS minutos_sin_datos,
        CASE WHEN DATEDIFF(MINUTE, MAX(ingested_at), SYSUTCDATETIME()) > 30
             THEN 'REVISAR' ELSE 'OK' END                         AS estado
FROM    eventos
GROUP BY entidad;
GO
