/* =====================================================================
   AzureDW - Capa Bronze en Synapse (base MessyOpsDW)
   Compatible con el pool serverless Built-in y con un pool dedicado.
   GENERADO por scripts/generar_bronze.py a partir de EstructuraOLTP.sql.
   No editar a mano: cambiar el generador y volver a ejecutarlo.

   Tablas externas NATIVAS (sin TYPE = HADOOP) sobre el Parquet que escribe
   el recurso CDC de ADF en el contenedor bronze/<entidad>/.
   - Las columnas se enlazan por NOMBRE, no por posicion.
   - El comodin doble asterisco al final de LOCATION recorre subcarpetas
     por si el recurso particiona la salida. (No se escribe aqui porque
     barra + asterisco abriria un comentario anidado en T-SQL.)
   Contrato Bronze: columnas del OLTP + cdc_operation (I/U/D) + ingested_at.

   Variables sqlcmd (las pasa scripts/02_desplegar_sql.sh):
     LAKE_URL         raiz del contenedor bronze:
                      serverless: https://<cuenta>.dfs.core.windows.net/bronze
                      dedicado:   abfss://bronze@<cuenta>.dfs.core.windows.net
     MASTER_KEY_PWD   contrasena de la master key (nunca en el repositorio)
   ===================================================================== */

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'bronze') EXEC('CREATE SCHEMA bronze');
GO
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$(MASTER_KEY_PWD)';
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_scoped_credentials WHERE name = 'cred_adls_mi')
    CREATE DATABASE SCOPED CREDENTIAL cred_adls_mi WITH IDENTITY = 'Managed Identity';
GO

-- Se eliminan primero las tablas: el origen de datos no se puede recrear
-- mientras alguna tabla lo use (la version anterior era TYPE = HADOOP).
IF OBJECT_ID('bronze.customers') IS NOT NULL DROP EXTERNAL TABLE bronze.customers;
IF OBJECT_ID('bronze.inventory_snapshots') IS NOT NULL DROP EXTERNAL TABLE bronze.inventory_snapshots;
IF OBJECT_ID('bronze.invoices') IS NOT NULL DROP EXTERNAL TABLE bronze.invoices;
IF OBJECT_ID('bronze.payments') IS NOT NULL DROP EXTERNAL TABLE bronze.payments;
IF OBJECT_ID('bronze.products') IS NOT NULL DROP EXTERNAL TABLE bronze.products;
IF OBJECT_ID('bronze.purchase_order_lines') IS NOT NULL DROP EXTERNAL TABLE bronze.purchase_order_lines;
IF OBJECT_ID('bronze.purchase_orders') IS NOT NULL DROP EXTERNAL TABLE bronze.purchase_orders;
IF OBJECT_ID('bronze.returns') IS NOT NULL DROP EXTERNAL TABLE bronze.returns;
IF OBJECT_ID('bronze.sales_order_lines') IS NOT NULL DROP EXTERNAL TABLE bronze.sales_order_lines;
IF OBJECT_ID('bronze.sales_orders') IS NOT NULL DROP EXTERNAL TABLE bronze.sales_orders;
IF OBJECT_ID('bronze.shipments') IS NOT NULL DROP EXTERNAL TABLE bronze.shipments;
IF OBJECT_ID('bronze.supplier_invoices') IS NOT NULL DROP EXTERNAL TABLE bronze.supplier_invoices;
IF OBJECT_ID('bronze.supplier_payments') IS NOT NULL DROP EXTERNAL TABLE bronze.supplier_payments;
IF OBJECT_ID('bronze.suppliers') IS NOT NULL DROP EXTERNAL TABLE bronze.suppliers;
IF OBJECT_ID('bronze.support_tickets') IS NOT NULL DROP EXTERNAL TABLE bronze.support_tickets;
IF OBJECT_ID('bronze.warehouses') IS NOT NULL DROP EXTERNAL TABLE bronze.warehouses;
GO
IF EXISTS (SELECT 1 FROM sys.external_data_sources WHERE name = 'ds_bronze')
    DROP EXTERNAL DATA SOURCE ds_bronze;
GO
CREATE EXTERNAL DATA SOURCE ds_bronze WITH (
    LOCATION   = '$(LAKE_URL)',
    CREDENTIAL = cred_adls_mi
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.external_file_formats WHERE name = 'ff_parquet')
    CREATE EXTERNAL FILE FORMAT ff_parquet WITH (FORMAT_TYPE = PARQUET);
GO

CREATE EXTERNAL TABLE bronze.customers (
    [customer_id] NVARCHAR(50),
    [company_name] NVARCHAR(50),
    [customer_segment] NVARCHAR(50),
    [country] NVARCHAR(50),
    [city] NVARCHAR(50),
    [region_type] NVARCHAR(50),
    [contact_email] NVARCHAR(50),
    [contact_phone] NVARCHAR(50),
    [payment_term_days] INT,
    [credit_limit] FLOAT,
    [customer_since] DATE,
    [is_active] BIT
) WITH (LOCATION = '/dbo.customers/**', DATA_SOURCE = ds_bronze, FILE_FORMAT = ff_parquet);
GO

CREATE EXTERNAL TABLE bronze.inventory_snapshots (
    [inventory_snapshot_id] NVARCHAR(50),
    [snapshot_date] DATETIME2(7),
    [product_id] NVARCHAR(50),
    [warehouse_id] NVARCHAR(50),
    [quantity_on_hand] INT,
    [quantity_on_order] NVARCHAR(50),
    [reorder_point] INT,
    [is_stockout] BIT,
    [inventory_value] FLOAT
) WITH (LOCATION = '/dbo.inventory_snapshots/**', DATA_SOURCE = ds_bronze, FILE_FORMAT = ff_parquet);
GO

CREATE EXTERNAL TABLE bronze.invoices (
    [invoice_id] NVARCHAR(50),
    [sales_order_id] NVARCHAR(50),
    [customer_id] NVARCHAR(50),
    [invoice_date] DATE,
    [due_date] DATE,
    [payment_term_days] INT,
    [invoice_amount] FLOAT,
    [amount_paid] FLOAT,
    [balance_due] FLOAT,
    [invoice_status] NVARCHAR(50),
    [days_to_full_payment] FLOAT,
    [late_payment] BIT
) WITH (LOCATION = '/dbo.invoices/**', DATA_SOURCE = ds_bronze, FILE_FORMAT = ff_parquet);
GO

CREATE EXTERNAL TABLE bronze.payments (
    [payment_id] NVARCHAR(50),
    [invoice_id] NVARCHAR(50),
    [payment_date] DATE,
    [payment_amount] FLOAT,
    [payment_method] NVARCHAR(50),
    [is_partial_payment] BIT
) WITH (LOCATION = '/dbo.payments/**', DATA_SOURCE = ds_bronze, FILE_FORMAT = ff_parquet);
GO

CREATE EXTERNAL TABLE bronze.products (
    [product_id] NVARCHAR(50),
    [product_name] NVARCHAR(50),
    [category] NVARCHAR(50),
    [subcategory] NVARCHAR(50),
    [primary_supplier_id] NVARCHAR(50),
    [unit_cost] FLOAT,
    [list_price] FLOAT,
    [gross_margin_pct] FLOAT,
    [unit_of_measure] NVARCHAR(50),
    [weight_kg] FLOAT,
    [is_seasonal] BIT,
    [product_launch_date] DATE,
    [is_discontinued] BIT,
    [discontinued_date] DATE,
    [reorder_point] INT,
    [reorder_quantity] INT
) WITH (LOCATION = '/dbo.products/**', DATA_SOURCE = ds_bronze, FILE_FORMAT = ff_parquet);
GO

CREATE EXTERNAL TABLE bronze.purchase_order_lines (
    [purchase_order_line_id] NVARCHAR(50),
    [purchase_order_id] NVARCHAR(50),
    [line_number] INT,
    [product_id] NVARCHAR(50),
    [quantity_ordered] INT,
    [unit_cost] FLOAT,
    [line_total] FLOAT,
    [quantity_received] FLOAT
) WITH (LOCATION = '/dbo.purchase_order_lines/**', DATA_SOURCE = ds_bronze, FILE_FORMAT = ff_parquet);
GO

CREATE EXTERNAL TABLE bronze.purchase_orders (
    [purchase_order_id] NVARCHAR(50),
    [supplier_id] NVARCHAR(50),
    [warehouse_id] NVARCHAR(50),
    [order_date] DATE,
    [expected_delivery_date] DATE,
    [actual_delivery_date] DATE,
    [po_status] NVARCHAR(50),
    [subtotal] FLOAT,
    [freight_cost] FLOAT,
    [total_amount] FLOAT
) WITH (LOCATION = '/dbo.purchase_orders/**', DATA_SOURCE = ds_bronze, FILE_FORMAT = ff_parquet);
GO

CREATE EXTERNAL TABLE bronze.returns (
    [return_id] NVARCHAR(50),
    [shipment_id] NVARCHAR(50),
    [sales_order_line_id] NVARCHAR(50),
    [return_date] DATE,
    [returned_quantity] INT,
    [return_reason] NVARCHAR(50),
    [return_condition] NVARCHAR(50),
    [restocking_fee_rate] FLOAT,
    [refund_amount] FLOAT
) WITH (LOCATION = '/dbo.returns/**', DATA_SOURCE = ds_bronze, FILE_FORMAT = ff_parquet);
GO

CREATE EXTERNAL TABLE bronze.sales_order_lines (
    [sales_order_line_id] NVARCHAR(50),
    [sales_order_id] NVARCHAR(50),
    [line_number] INT,
    [product_id] NVARCHAR(50),
    [quantity] INT,
    [unit_price] FLOAT,
    [discount_rate] FLOAT,
    [line_subtotal] FLOAT,
    [discount_amount] FLOAT,
    [line_total] FLOAT
) WITH (LOCATION = '/dbo.sales_order_lines/**', DATA_SOURCE = ds_bronze, FILE_FORMAT = ff_parquet);
GO

CREATE EXTERNAL TABLE bronze.sales_orders (
    [sales_order_id] NVARCHAR(50),
    [customer_id] NVARCHAR(50),
    [warehouse_id] NVARCHAR(50),
    [order_date] DATE,
    [order_status] NVARCHAR(50),
    [sales_channel] NVARCHAR(50),
    [subtotal] FLOAT,
    [discount_total] FLOAT,
    [tax_rate] FLOAT,
    [tax_amount] FLOAT,
    [shipping_cost] FLOAT,
    [total_amount] FLOAT
) WITH (LOCATION = '/dbo.sales_orders/**', DATA_SOURCE = ds_bronze, FILE_FORMAT = ff_parquet);
GO

CREATE EXTERNAL TABLE bronze.shipments (
    [shipment_id] NVARCHAR(50),
    [sales_order_id] NVARCHAR(50),
    [warehouse_id] NVARCHAR(50),
    [ship_date] DATE,
    [expected_delivery_date] DATE,
    [actual_delivery_date] DATE,
    [carrier] NVARCHAR(50),
    [shipping_status] NVARCHAR(50)
) WITH (LOCATION = '/dbo.shipments/**', DATA_SOURCE = ds_bronze, FILE_FORMAT = ff_parquet);
GO

CREATE EXTERNAL TABLE bronze.supplier_invoices (
    [supplier_invoice_id] NVARCHAR(50),
    [purchase_order_id] NVARCHAR(50),
    [supplier_id] NVARCHAR(50),
    [invoice_date] DATE,
    [due_date] DATE,
    [invoice_amount] FLOAT,
    [amount_paid] FLOAT,
    [balance_due] FLOAT,
    [invoice_status] NVARCHAR(50)
) WITH (LOCATION = '/dbo.supplier_invoices/**', DATA_SOURCE = ds_bronze, FILE_FORMAT = ff_parquet);
GO

CREATE EXTERNAL TABLE bronze.supplier_payments (
    [supplier_payment_id] NVARCHAR(50),
    [supplier_invoice_id] NVARCHAR(50),
    [payment_date] DATE,
    [payment_amount] FLOAT,
    [payment_method] NVARCHAR(50)
) WITH (LOCATION = '/dbo.supplier_payments/**', DATA_SOURCE = ds_bronze, FILE_FORMAT = ff_parquet);
GO

CREATE EXTERNAL TABLE bronze.suppliers (
    [supplier_id] NVARCHAR(50),
    [supplier_name] NVARCHAR(50),
    [supplier_reliability_tier] NVARCHAR(50),
    [country] NVARCHAR(50),
    [lead_time_days_mean] INT,
    [avg_defect_rate] FLOAT,
    [default_payment_term_days] INT,
    [supplier_since] DATE
) WITH (LOCATION = '/dbo.suppliers/**', DATA_SOURCE = ds_bronze, FILE_FORMAT = ff_parquet);
GO

CREATE EXTERNAL TABLE bronze.support_tickets (
    [support_ticket_id] NVARCHAR(50),
    [customer_id] NVARCHAR(50),
    [related_sales_order_id] NVARCHAR(50),
    [related_shipment_id] NVARCHAR(50),
    [related_invoice_id] NVARCHAR(50),
    [created_at] DATE,
    [category] NVARCHAR(50),
    [priority] NVARCHAR(50),
    [ticket_text] NVARCHAR(100),
    [sentiment] NVARCHAR(50),
    [resolution_time_hours] FLOAT,
    [status] NVARCHAR(50)
) WITH (LOCATION = '/dbo.support_tickets/**', DATA_SOURCE = ds_bronze, FILE_FORMAT = ff_parquet);
GO

CREATE EXTERNAL TABLE bronze.warehouses (
    [warehouse_id] NVARCHAR(50),
    [warehouse_name] NVARCHAR(50),
    [country] NVARCHAR(50),
    [city] NVARCHAR(50),
    [capacity_units] INT
) WITH (LOCATION = '/dbo.warehouses/**', DATA_SOURCE = ds_bronze, FILE_FORMAT = ff_parquet);
GO
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
