/* =====================================================================
   AzureDW - CDC nativo en MessyOpsOLTP (origen de la capa Bronze)
   Ejecutar contra: messyops-server / MessyOpsOLTP
   Por CLI:  scripts/02_desplegar_sql.sh oltp
   Requiere: conectarse como administrador Microsoft Entra del servidor
             (para crear el usuario de la identidad administrada de ADF).

   Idempotente: se puede ejecutar N veces. Reemplaza a los scripts sueltos
   de la raiz (Habilitar CDC*.sql, Verificar*.sql).

   Variable sqlcmd:
     ADF_NAME  nombre del Data Factory (su identidad administrada lee el CDC)
   ===================================================================== */
-- En SSMS (modo SQLCMD) definir antes:  :setvar ADF_NAME "messyops-adf"

SET NOCOUNT ON;

-- ---------------------------------------------------------------------
-- PASO 0 (solo lectura). Linea base: nivel de servicio y estado actual.
--   El CDC de Azure SQL necesita S3 o superior en DTU, o cualquier vCore.
-- ---------------------------------------------------------------------
SELECT  DB_NAME()                                          AS base_de_datos,
        DATABASEPROPERTYEX(DB_NAME(), 'Edition')           AS edicion,
        DATABASEPROPERTYEX(DB_NAME(), 'ServiceObjective')  AS nivel_servicio,
        is_cdc_enabled                                     AS cdc_habilitado_en_bd
FROM    sys.databases
WHERE   name = DB_NAME();
GO

-- ---------------------------------------------------------------------
-- PASO 1. CDC a nivel de base de datos.
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
-- PASO 2. CDC en las 16 tablas de negocio.
--   data_quality_log queda fuera: es la bitacora del generador de datos,
--   no un proceso de negocio.
--   La instancia de captura se fija explicitamente (dbo_<tabla>) porque
--   el recurso CDC de ADF la usa para leer los cambios.
--   supports_net_changes = 1: el recurso lee cambios netos.
-- ---------------------------------------------------------------------
DECLARE @tablas TABLE (tabla SYSNAME);
INSERT INTO @tablas VALUES
    ('customers'), ('products'), ('suppliers'), ('warehouses'),
    ('sales_orders'), ('sales_order_lines'), ('invoices'), ('payments'),
    ('shipments'), ('returns'), ('purchase_orders'), ('purchase_order_lines'),
    ('supplier_invoices'), ('supplier_payments'), ('inventory_snapshots'),
    ('support_tickets');

DECLARE @tabla SYSNAME, @captura SYSNAME;
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT tabla FROM @tablas;
OPEN cur;
FETCH NEXT FROM cur INTO @tabla;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @captura = N'dbo_' + @tabla;

    IF OBJECT_ID(N'dbo.' + @tabla, 'U') IS NULL
        PRINT 'ERROR: no existe la tabla dbo.' + @tabla;
    ELSE IF NOT EXISTS (SELECT 1 FROM cdc.change_tables WHERE capture_instance = @captura)
    BEGIN
        EXEC sys.sp_cdc_enable_table
             @source_schema        = N'dbo',
             @source_name          = @tabla,
             @role_name            = NULL,   -- el acceso lo controla el usuario de ADF (paso 4)
             @capture_instance     = @captura,
             @supports_net_changes = 1;
        PRINT 'CDC habilitado: dbo.' + @tabla;
    END
    ELSE
        PRINT 'Sin cambios (CDC ya activo): dbo.' + @tabla;

    FETCH NEXT FROM cur INTO @tabla;
END
CLOSE cur; DEALLOCATE cur;
GO

-- ---------------------------------------------------------------------
-- PASO 3. Retencion del log de cambios: 7 dias (por defecto son 3).
--   Si el recurso CDC de ADF queda detenido mas tiempo que la retencion,
--   pierde eventos. 7 dias cubren un fin de semana largo con margen.
-- ---------------------------------------------------------------------
EXEC sys.sp_cdc_change_job @job_type = 'cleanup', @retention = 10080;
GO

-- ---------------------------------------------------------------------
-- PASO 4. Usuario de la identidad administrada de ADF.
--   Lectura de tablas y del esquema cdc; sin contrasenas.
-- ---------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'$(ADF_NAME)')
BEGIN
    CREATE USER [$(ADF_NAME)] FROM EXTERNAL PROVIDER;
    PRINT 'Usuario creado: $(ADF_NAME)';
END
ALTER ROLE db_datareader ADD MEMBER [$(ADF_NAME)];
GRANT VIEW DATABASE STATE TO [$(ADF_NAME)];
GO

-- ---------------------------------------------------------------------
-- PASO 5. Verificacion.
--   Debe devolver 16 filas. inicio_captura indica desde cuando existe
--   historia en el CDC: las filas cargadas ANTES de esa hora no estan en
--   las tablas de cambios, por eso el recurso CDC de ADF hace una unica
--   instantanea inicial (skipInitialLoad = false) y despues solo lee cambios.
-- ---------------------------------------------------------------------
SELECT  ct.capture_instance,
        OBJECT_NAME(ct.source_object_id)                          AS tabla_origen,
        ct.supports_net_changes,
        sys.fn_cdc_map_lsn_to_time(ct.start_lsn)                  AS inicio_captura,
        sys.fn_cdc_get_min_lsn(ct.capture_instance)               AS lsn_minimo_disponible,
        sys.fn_cdc_get_max_lsn()                                  AS lsn_maximo_actual
FROM    cdc.change_tables AS ct
ORDER BY ct.capture_instance;

SELECT  dp.name AS usuario, r.name AS rol
FROM    sys.database_role_members rm
JOIN    sys.database_principals dp ON dp.principal_id = rm.member_principal_id
JOIN    sys.database_principals r  ON r.principal_id  = rm.role_principal_id
WHERE   dp.name = N'$(ADF_NAME)';
GO
