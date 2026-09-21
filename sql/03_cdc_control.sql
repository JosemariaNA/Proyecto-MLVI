/* =====================================================================
   AzureDW — Tabla de control de ingesta CDC (capa Bronze)
    Destino: MessyOpsDW (Synapse) — la lee y la escribe ADF.
   Es el checkpoint de Bronze: hasta que LSN se copio cada entidad.
   Separada de meta.etl_watermark, que gobierna Silver y Gold.
   ===================================================================== */

IF OBJECT_ID('meta.cdc_control') IS NULL
CREATE TABLE meta.cdc_control
(
    entidad             VARCHAR(64)   NOT NULL,   -- carpeta destino en Bronze
    capture_instance    VARCHAR(128)  NOT NULL,   -- instancia CDC en el OLTP
    last_lsn            VARCHAR(34)   NULL,       -- 0x... ultimo LSN copiado
    last_extracted_at   DATETIME2(3)  NULL,
    rows_last_batch     BIGINT        NULL,
    activo              BIT           NOT NULL,
    updated_at          DATETIME2(3)  NOT NULL
);
GO

/*  Semilla: LSN nulo = "desde el minimo disponible en el CDC".
    activo = 0 en todas las entidades a proposito: el CDC esta apagado
    y la ingesta no debe arrancar hasta el final del despliegue.        */
IF NOT EXISTS (SELECT 1 FROM meta.cdc_control)
INSERT INTO meta.cdc_control
    (entidad, capture_instance, last_lsn, last_extracted_at, rows_last_batch, activo, updated_at)
VALUES
    ('customers',         'dbo_customers',         NULL, NULL, NULL, 0, SYSUTCDATETIME()),
    ('products',          'dbo_products',          NULL, NULL, NULL, 0, SYSUTCDATETIME()),
    ('suppliers',         'dbo_suppliers',         NULL, NULL, NULL, 0, SYSUTCDATETIME()),
    ('warehouses',        'dbo_warehouses',        NULL, NULL, NULL, 0, SYSUTCDATETIME()),
    ('sales_orders',      'dbo_sales_orders',      NULL, NULL, NULL, 0, SYSUTCDATETIME()),
    ('sales_order_lines', 'dbo_sales_order_lines', NULL, NULL, NULL, 0, SYSUTCDATETIME()),
    ('invoices',          'dbo_invoices',          NULL, NULL, NULL, 0, SYSUTCDATETIME()),
    ('payments',          'dbo_payments',          NULL, NULL, NULL, 0, SYSUTCDATETIME()),
    ('shipments',         'dbo_shipments',         NULL, NULL, NULL, 0, SYSUTCDATETIME()),
    ('returns',           'dbo_returns',           NULL, NULL, NULL, 0, SYSUTCDATETIME()),
    ('purchase_orders',   'dbo_purchase_orders',   NULL, NULL, NULL, 0, SYSUTCDATETIME()),
    ('purchase_order_lines', 'dbo_purchase_order_lines', NULL, NULL, NULL, 0, SYSUTCDATETIME()),
    ('supplier_invoices', 'dbo_supplier_invoices', NULL, NULL, NULL, 0, SYSUTCDATETIME()),
    ('supplier_payments', 'dbo_supplier_payments', NULL, NULL, NULL, 0, SYSUTCDATETIME()),
    ('inventory_snapshots', 'dbo_inventory_snapshots', NULL, NULL, NULL, 0, SYSUTCDATETIME()),
    ('support_tickets',   'dbo_support_tickets',   NULL, NULL, NULL, 0, SYSUTCDATETIME());
GO

/*  Procedimiento que usa ADF para cerrar cada microlote de una entidad.
    Un unico punto de escritura del checkpoint evita checkpoints
    inconsistentes escritos desde varias actividades.                   */
CREATE OR ALTER PROCEDURE meta.sp_cerrar_lote_cdc
    @entidad    VARCHAR(64),
    @nuevo_lsn  VARCHAR(34),
    @filas      BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE meta.cdc_control
    SET    last_lsn          = @nuevo_lsn,
           last_extracted_at = SYSUTCDATETIME(),
           rows_last_batch   = @filas,
           updated_at        = SYSUTCDATETIME()
    WHERE  entidad = @entidad;

    INSERT INTO meta.pipeline_run_log
        (run_id, pipeline_name, layer_name, entity_name,
         status, rows_affected, logged_at)
    VALUES (CAST(NEWID() AS VARCHAR(64)), 'pl_00_ingesta_cdc_bronze', 'bronze',
            @entidad, 'SUCCEEDED', @filas, SYSUTCDATETIME());
END
GO

/*  Activar la ingesta. Se ejecuta deliberadamente al final.            */
CREATE OR ALTER PROCEDURE meta.sp_activar_ingesta_cdc
AS
BEGIN
    UPDATE meta.cdc_control SET activo = 1, updated_at = SYSUTCDATETIME();
END
GO
