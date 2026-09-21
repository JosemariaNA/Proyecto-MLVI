/* =====================================================================
   AzureDW — Capa META (control, auditoría y calidad)
   Destino : Azure Synapse Analytics MessyOpsDW
   Objetivo: dar a Silver y Gold el mismo andamiaje de control.
            - meta.etl_watermark      -> checkpoint incremental (LSN / timestamp)
            - meta.pipeline_run_log   -> auditoría de cada microlote
            - meta.data_quality_log   -> fallos de tests dbt y validaciones
            - meta.reconciliation_log -> conteos Bronze -> Silver -> Gold
   Idempotente: se puede ejecutar N veces sin efectos secundarios.
   ===================================================================== */

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'meta')   EXEC('CREATE SCHEMA meta');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'bronze') EXEC('CREATE SCHEMA bronze');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'silver') EXEC('CREATE SCHEMA silver');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'gold')   EXEC('CREATE SCHEMA gold');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'stg')    EXEC('CREATE SCHEMA stg');
GO

/* ---------------------------------------------------------------------
   1. Watermark: un renglón por (capa, entidad). Es la única fuente de
      verdad del punto hasta donde se procesó. dbt lo lee en
      is_incremental() y lo actualiza en el post-hook del modelo.
   --------------------------------------------------------------------- */
IF OBJECT_ID('meta.etl_watermark') IS NULL
CREATE TABLE meta.etl_watermark
(
    layer_name        VARCHAR(20)   NOT NULL,   -- 'silver' | 'gold'
    entity_name       VARCHAR(128)  NOT NULL,   -- nombre del modelo dbt
    last_lsn          VARBINARY(16) NULL,       -- checkpoint CDC (preferente)
    last_loaded_at    DATETIME2(3)  NULL,       -- checkpoint por timestamp (fallback)
    last_run_id       VARCHAR(64)   NULL,       -- invocation_id de dbt
    rows_last_batch   BIGINT        NULL,
    updated_at        DATETIME2(3)  NOT NULL
);
GO

/* ---------------------------------------------------------------------
   2. Auditoría de ejecuciones: la escribe ADF al abrir/cerrar el microlote
      y dbt al terminar cada modelo.
   --------------------------------------------------------------------- */
IF OBJECT_ID('meta.pipeline_run_log') IS NULL
CREATE TABLE meta.pipeline_run_log
(
    run_id          VARCHAR(64)  NOT NULL,
    pipeline_name   VARCHAR(128) NOT NULL,
    layer_name      VARCHAR(20)  NULL,
    entity_name     VARCHAR(128) NULL,
    window_start    DATETIME2(3) NULL,
    window_end      DATETIME2(3) NULL,
    status          VARCHAR(20)  NOT NULL,      -- STARTED|SUCCEEDED|FAILED
    rows_affected   BIGINT       NULL,
    duration_ms     BIGINT       NULL,
    error_message   NVARCHAR(4000) NULL,
    logged_at       DATETIME2(3) NOT NULL
);
GO

/* ---------------------------------------------------------------------
   3. Calidad de datos: destino de los store_failures de dbt y de los
      tests custom. Nada se borra: es la serie histórica de calidad.
   --------------------------------------------------------------------- */
IF OBJECT_ID('meta.data_quality_log') IS NULL
CREATE TABLE meta.data_quality_log
(
    run_id          VARCHAR(64)   NOT NULL,
    layer_name      VARCHAR(20)   NOT NULL,
    entity_name     VARCHAR(128)  NOT NULL,
    test_name       VARCHAR(256)  NOT NULL,
    severity        VARCHAR(10)   NOT NULL,     -- warn | error
    failed_rows     BIGINT        NOT NULL,
    sample_value    NVARCHAR(2000) NULL,
    detected_at     DATETIME2(3)  NOT NULL
);
GO

/* ---------------------------------------------------------------------
   4. Reconciliación entre capas: conteos y sumas por periodo, lo que
      permite demostrar que Gold no perdió ni inventó registros.
   --------------------------------------------------------------------- */
IF OBJECT_ID('meta.reconciliation_log') IS NULL
CREATE TABLE meta.reconciliation_log
(
    run_id            VARCHAR(64)  NOT NULL,
    check_name        VARCHAR(128) NOT NULL,
    period_key        INT          NULL,        -- YYYYMMDD
    source_layer      VARCHAR(20)  NOT NULL,
    target_layer      VARCHAR(20)  NOT NULL,
    source_row_count  BIGINT       NULL,
    target_row_count  BIGINT       NULL,
    source_measure    DECIMAL(38,6) NULL,
    target_measure    DECIMAL(38,6) NULL,
    is_match          BIT          NOT NULL,
    checked_at        DATETIME2(3) NOT NULL
);
GO

/* ---------------------------------------------------------------------
   5. Vista de salud: lo que mira el operador cada mañana.
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW meta.vw_pipeline_health AS
SELECT  w.layer_name,
        w.entity_name,
        w.last_loaded_at,
        w.rows_last_batch,
        DATEDIFF(MINUTE, w.last_loaded_at, SYSUTCDATETIME()) AS minutos_de_retraso,
        CASE WHEN DATEDIFF(MINUTE, w.last_loaded_at, SYSUTCDATETIME()) > 30
             THEN 'RETRASADO' ELSE 'OK' END                  AS estado_sla,
        (SELECT COUNT(*) FROM meta.data_quality_log d
          WHERE d.entity_name = w.entity_name
            AND d.severity = 'error'
            AND d.detected_at > DATEADD(DAY, -1, SYSUTCDATETIME()))  AS fallos_calidad_24h
FROM    meta.etl_watermark w;
GO
