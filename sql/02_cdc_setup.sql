/* =====================================================================
   AzureDW — Habilitacion y control del CDC en MessyOpsOLTP
   IMPORTANTE: el CDC esta apagado a proposito. Este script se ejecuta
   AL FINAL, cuando Silver y Gold ya estan desplegados y probados.
   Ejecutar contra: MessyOpsOLTP (messyops-server)
   ===================================================================== */

-- ---------------------------------------------------------------------
-- PASO 0 (solo lectura). Diagnostico: que hay habilitado hoy.
--        Correr esto primero y guardar la salida como linea base.
-- ---------------------------------------------------------------------
SELECT  DB_NAME()                AS base_de_datos,
        is_cdc_enabled           AS cdc_habilitado_en_bd
FROM    sys.databases
WHERE   name = DB_NAME();

SELECT  s.name    AS esquema,
        t.name    AS tabla,
        t.is_tracked_by_cdc
FROM    sys.tables t
JOIN    sys.schemas s ON s.schema_id = t.schema_id
ORDER BY t.is_tracked_by_cdc DESC, s.name, t.name;

-- Sesiones de captura disponibles en Azure SQL.
SELECT * FROM sys.dm_cdc_log_scan_sessions;

-- ---------------------------------------------------------------------
-- PASO 1. Habilitar CDC a nivel de base de datos.
--         Idempotente: no falla si ya estaba activo.
-- ---------------------------------------------------------------------
IF (SELECT is_cdc_enabled FROM sys.databases WHERE name = DB_NAME()) = 0
BEGIN
    EXEC sys.sp_cdc_enable_db;
    PRINT 'CDC habilitado a nivel de base de datos.';
END
ELSE
    PRINT 'CDC ya estaba habilitado a nivel de base de datos.';
GO

-- ---------------------------------------------------------------------
-- PASO 2. Habilitar CDC por tabla.
--         El nombre de la instancia de captura se fija explicitamente:
--         es el que usan los pipelines de ADF y no debe cambiar nunca,
--         porque es parte del contrato de ingesta.
-- ---------------------------------------------------------------------
DECLARE @tablas TABLE (esquema SYSNAME, tabla SYSNAME, captura SYSNAME);
INSERT INTO @tablas VALUES
    ('dbo','customers',         'dbo_customers'),
    ('dbo','products',          'dbo_products'),
    ('dbo','suppliers',         'dbo_suppliers'),
    ('dbo','warehouses',        'dbo_warehouses'),
    ('dbo','sales_orders',      'dbo_sales_orders'),
    ('dbo','sales_order_lines', 'dbo_sales_order_lines'),
    ('dbo','invoices',          'dbo_invoices'),
    ('dbo','payments',          'dbo_payments'),
    ('dbo','shipments',         'dbo_shipments'),
    ('dbo','returns',           'dbo_returns'),
    ('dbo','purchase_orders',   'dbo_purchase_orders'),
    ('dbo','purchase_order_lines', 'dbo_purchase_order_lines'),
    ('dbo','supplier_invoices', 'dbo_supplier_invoices'),
    ('dbo','supplier_payments', 'dbo_supplier_payments'),
    ('dbo','inventory_snapshots', 'dbo_inventory_snapshots'),
    ('dbo','support_tickets',   'dbo_support_tickets');

DECLARE @esquema SYSNAME, @tabla SYSNAME, @captura SYSNAME;
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT esquema, tabla, captura FROM @tablas;
OPEN cur;
FETCH NEXT FROM cur INTO @esquema, @tabla, @captura;

WHILE @@FETCH_STATUS = 0
BEGIN
    IF EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id
               WHERE s.name = @esquema AND t.name = @tabla AND t.is_tracked_by_cdc = 0)
    BEGIN
        EXEC sys.sp_cdc_enable_table
             @source_schema        = @esquema,
             @source_name          = @tabla,
             @role_name            = NULL,          -- sin rol: el acceso se controla por IAM
             @capture_instance     = @captura,
             @supports_net_changes = 1;             -- permite net changes ademas de all changes
        PRINT 'CDC habilitado: ' + @esquema + '.' + @tabla;
    END
    ELSE
        PRINT 'Sin cambios (ya activo o tabla inexistente): ' + @esquema + '.' + @tabla;

    FETCH NEXT FROM cur INTO @esquema, @tabla, @captura;
END
CLOSE cur; DEALLOCATE cur;
GO

-- ---------------------------------------------------------------------
-- PASO 3. Retencion del log de cambios.
--         Por defecto son 3 dias (4320 min). Se sube a 7 dias para
--         tolerar un fin de semana con el pipeline caido sin perder
--         eventos. Subirlo tiene coste de almacenamiento: es el
--         intercambio consciente entre resiliencia y factura.
-- ---------------------------------------------------------------------
EXEC sys.sp_cdc_change_job
     @job_type   = 'cleanup',
     @retention  = 10080;   -- minutos = 7 dias
GO

-- ---------------------------------------------------------------------
-- PASO 4. Verificacion posterior. Debe devolver una fila por tabla
--         con su instancia de captura y su LSN minimo disponible.
-- ---------------------------------------------------------------------
SELECT  ct.capture_instance,
    OBJECT_SCHEMA_NAME(ct.source_object_id) AS source_schema,
    OBJECT_NAME(ct.source_object_id) AS source_table,
        sys.fn_cdc_get_min_lsn(ct.capture_instance) AS lsn_minimo_disponible,
        sys.fn_cdc_get_max_lsn()                    AS lsn_maximo_actual
FROM    cdc.change_tables AS ct
;
