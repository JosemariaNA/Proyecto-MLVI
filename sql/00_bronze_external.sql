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
    [is_active] BIT,
    [cdc_operation] VARCHAR(1),
    [ingested_at] DATETIME2(3)
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
    [inventory_value] FLOAT,
    [cdc_operation] VARCHAR(1),
    [ingested_at] DATETIME2(3)
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
    [late_payment] BIT,
    [cdc_operation] VARCHAR(1),
    [ingested_at] DATETIME2(3)
) WITH (LOCATION = '/dbo.invoices/**', DATA_SOURCE = ds_bronze, FILE_FORMAT = ff_parquet);
GO

CREATE EXTERNAL TABLE bronze.payments (
    [payment_id] NVARCHAR(50),
    [invoice_id] NVARCHAR(50),
    [payment_date] DATE,
    [payment_amount] FLOAT,
    [payment_method] NVARCHAR(50),
    [is_partial_payment] BIT,
    [cdc_operation] VARCHAR(1),
    [ingested_at] DATETIME2(3)
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
    [reorder_quantity] INT,
    [cdc_operation] VARCHAR(1),
    [ingested_at] DATETIME2(3)
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
    [quantity_received] FLOAT,
    [cdc_operation] VARCHAR(1),
    [ingested_at] DATETIME2(3)
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
    [total_amount] FLOAT,
    [cdc_operation] VARCHAR(1),
    [ingested_at] DATETIME2(3)
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
    [refund_amount] FLOAT,
    [cdc_operation] VARCHAR(1),
    [ingested_at] DATETIME2(3)
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
    [line_total] FLOAT,
    [cdc_operation] VARCHAR(1),
    [ingested_at] DATETIME2(3)
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
    [total_amount] FLOAT,
    [cdc_operation] VARCHAR(1),
    [ingested_at] DATETIME2(3)
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
    [shipping_status] NVARCHAR(50),
    [cdc_operation] VARCHAR(1),
    [ingested_at] DATETIME2(3)
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
    [invoice_status] NVARCHAR(50),
    [cdc_operation] VARCHAR(1),
    [ingested_at] DATETIME2(3)
) WITH (LOCATION = '/dbo.supplier_invoices/**', DATA_SOURCE = ds_bronze, FILE_FORMAT = ff_parquet);
GO

CREATE EXTERNAL TABLE bronze.supplier_payments (
    [supplier_payment_id] NVARCHAR(50),
    [supplier_invoice_id] NVARCHAR(50),
    [payment_date] DATE,
    [payment_amount] FLOAT,
    [payment_method] NVARCHAR(50),
    [cdc_operation] VARCHAR(1),
    [ingested_at] DATETIME2(3)
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
    [supplier_since] DATE,
    [cdc_operation] VARCHAR(1),
    [ingested_at] DATETIME2(3)
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
    [status] NVARCHAR(50),
    [cdc_operation] VARCHAR(1),
    [ingested_at] DATETIME2(3)
) WITH (LOCATION = '/dbo.support_tickets/**', DATA_SOURCE = ds_bronze, FILE_FORMAT = ff_parquet);
GO

CREATE EXTERNAL TABLE bronze.warehouses (
    [warehouse_id] NVARCHAR(50),
    [warehouse_name] NVARCHAR(50),
    [country] NVARCHAR(50),
    [city] NVARCHAR(50),
    [capacity_units] INT,
    [cdc_operation] VARCHAR(1),
    [ingested_at] DATETIME2(3)
) WITH (LOCATION = '/dbo.warehouses/**', DATA_SOURCE = ds_bronze, FILE_FORMAT = ff_parquet);
GO
