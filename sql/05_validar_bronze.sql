/* =====================================================================
   AzureDW - Validacion de la capa Bronze (Synapse, serverless o dedicado)
   Por CLI:  scripts/02_desplegar_sql.sh validar
   Ejecutar tras el primer microlote del recurso CDC (instantanea inicial).
   ===================================================================== */

-- ---------------------------------------------------------------------
-- B1. Objetos: 16 tablas externas bronze y la vista de frescura.
-- ---------------------------------------------------------------------
SELECT 'tabla_externa' AS tipo, s.name + '.' + t.name AS objeto
FROM   sys.external_tables t JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE  s.name = 'bronze'
UNION ALL
SELECT 'vista', s.name + '.' + v.name
FROM   sys.views v JOIN sys.schemas s ON s.schema_id = v.schema_id
WHERE  s.name = 'meta' AND v.name = 'vw_bronze_frescura'
ORDER BY tipo, objeto;

-- ---------------------------------------------------------------------
-- B2. Bronze: la instantanea inicial del recurso CDC debe contener todas
--     las claves del OLTP. Se compara contra el perfilado del 2026-09-20
--     (00-perfilado-oltp.md); si el OLTP cambio desde entonces, comparar
--     contra SELECT COUNT(*) en MessyOpsOLTP.
--     Ademas: frescura por entidad (ver sql/03_bronze_monitoreo.sql).
-- ---------------------------------------------------------------------
WITH esperado AS (
    SELECT * FROM (VALUES
        ('customers', 4081), ('products', 1200), ('suppliers', 250), ('warehouses', 6),
        ('sales_orders', 75081), ('sales_order_lines', 142502), ('invoices', 72800),
        ('payments', 76343), ('shipments', 72784), ('returns', 5275),
        ('purchase_orders', 5296), ('purchase_order_lines', 5420),
        ('supplier_invoices', 4959), ('supplier_payments', 4873),
        ('inventory_snapshots', 161408), ('support_tickets', 7323)
    ) AS v(entidad, filas_oltp)
),
obtenido AS (
    SELECT 'customers' AS entidad, COUNT(DISTINCT customer_id) AS claves_bronze FROM bronze.customers
    UNION ALL SELECT 'products', COUNT(DISTINCT product_id) FROM bronze.products
    UNION ALL SELECT 'suppliers', COUNT(DISTINCT supplier_id) FROM bronze.suppliers
    UNION ALL SELECT 'warehouses', COUNT(DISTINCT warehouse_id) FROM bronze.warehouses
    UNION ALL SELECT 'sales_orders', COUNT(DISTINCT sales_order_id) FROM bronze.sales_orders
    UNION ALL SELECT 'sales_order_lines', COUNT(DISTINCT sales_order_line_id) FROM bronze.sales_order_lines
    UNION ALL SELECT 'invoices', COUNT(DISTINCT invoice_id) FROM bronze.invoices
    UNION ALL SELECT 'payments', COUNT(DISTINCT payment_id) FROM bronze.payments
    UNION ALL SELECT 'shipments', COUNT(DISTINCT shipment_id) FROM bronze.shipments
    UNION ALL SELECT 'returns', COUNT(DISTINCT return_id) FROM bronze.returns
    UNION ALL SELECT 'purchase_orders', COUNT(DISTINCT purchase_order_id) FROM bronze.purchase_orders
    UNION ALL SELECT 'purchase_order_lines', COUNT(DISTINCT purchase_order_line_id) FROM bronze.purchase_order_lines
    UNION ALL SELECT 'supplier_invoices', COUNT(DISTINCT supplier_invoice_id) FROM bronze.supplier_invoices
    UNION ALL SELECT 'supplier_payments', COUNT(DISTINCT supplier_payment_id) FROM bronze.supplier_payments
    UNION ALL SELECT 'inventory_snapshots', COUNT(DISTINCT inventory_snapshot_id) FROM bronze.inventory_snapshots
    UNION ALL SELECT 'support_tickets', COUNT(DISTINCT support_ticket_id) FROM bronze.support_tickets
)
SELECT e.entidad, e.filas_oltp, o.claves_bronze,
       CASE WHEN o.claves_bronze >= e.filas_oltp THEN 'OK' ELSE 'FALTAN CLAVES' END AS veredicto
FROM   esperado e LEFT JOIN obtenido o ON o.entidad = e.entidad
ORDER BY e.entidad;

SELECT * FROM meta.vw_bronze_frescura ORDER BY minutos_sin_datos DESC;

