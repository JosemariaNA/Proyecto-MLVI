/* Bronze ADLS -> Synapse Analytics.
   Las 16 tablas externas leen Parquet CDC desde el contenedor bronze.
   Silver y Gold son materializados por dbt en Synapse.
*/

IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'ChangeThisBronzeMasterKey_2026!';
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_scoped_credentials WHERE name = 'cred_adls_mi')
    CREATE DATABASE SCOPED CREDENTIAL cred_adls_mi WITH IDENTITY = 'Managed Identity';
GO
IF NOT EXISTS (SELECT 1 FROM sys.external_data_sources WHERE name = 'ds_bronze')
    CREATE EXTERNAL DATA SOURCE ds_bronze WITH (
        LOCATION = 'abfss://bronze@messydopsdl2026.dfs.core.windows.net',
        CREDENTIAL = cred_adls_mi,
        TYPE = HADOOP
    );
GO
IF NOT EXISTS (SELECT 1 FROM sys.external_file_formats WHERE name = 'ff_parquet_snappy')
    CREATE EXTERNAL FILE FORMAT ff_parquet_snappy WITH (
        FORMAT_TYPE = PARQUET,
        DATA_COMPRESSION = 'org.apache.hadoop.io.compress.SnappyCodec'
    );
GO

-- El contrato de cada entidad conserva los campos CDC y ingested_at.
IF OBJECT_ID('bronze.customers') IS NOT NULL DROP EXTERNAL TABLE bronze.customers;
CREATE EXTERNAL TABLE bronze.customers (
 customer_id NVARCHAR(50), company_name NVARCHAR(50), customer_segment NVARCHAR(50), country NVARCHAR(50), city NVARCHAR(50), region_type NVARCHAR(50), contact_email NVARCHAR(50), contact_phone NVARCHAR(50), payment_term_days INT, credit_limit FLOAT, customer_since DATE, is_active BIT, [__$start_lsn] VARBINARY(16), [__$seqval] VARBINARY(16), [__$operation] INT, [__$update_mask] VARBINARY(128), ingested_at DATETIME2(3)
) WITH (LOCATION='/customers/', DATA_SOURCE=ds_bronze, FILE_FORMAT=ff_parquet_snappy, REJECT_TYPE=VALUE, REJECT_VALUE=0);
GO
IF OBJECT_ID('bronze.products') IS NOT NULL DROP EXTERNAL TABLE bronze.products;
CREATE EXTERNAL TABLE bronze.products (
 product_id NVARCHAR(50), product_name NVARCHAR(50), category NVARCHAR(50), subcategory NVARCHAR(50), primary_supplier_id NVARCHAR(50), unit_cost FLOAT, list_price FLOAT, gross_margin_pct FLOAT, unit_of_measure NVARCHAR(50), weight_kg FLOAT, is_seasonal BIT, product_launch_date DATE, is_discontinued BIT, discontinued_date DATE, reorder_point INT, reorder_quantity INT, [__$start_lsn] VARBINARY(16), [__$seqval] VARBINARY(16), [__$operation] INT, [__$update_mask] VARBINARY(128), ingested_at DATETIME2(3)
) WITH (LOCATION='/products/', DATA_SOURCE=ds_bronze, FILE_FORMAT=ff_parquet_snappy, REJECT_TYPE=VALUE, REJECT_VALUE=0);
GO
IF OBJECT_ID('bronze.suppliers') IS NOT NULL DROP EXTERNAL TABLE bronze.suppliers;
CREATE EXTERNAL TABLE bronze.suppliers (supplier_id NVARCHAR(50), supplier_name NVARCHAR(50), supplier_reliability_tier NVARCHAR(50), country NVARCHAR(50), lead_time_days_mean INT, avg_defect_rate FLOAT, default_payment_term_days INT, supplier_since DATE, [__$start_lsn] VARBINARY(16), [__$seqval] VARBINARY(16), [__$operation] INT, [__$update_mask] VARBINARY(128), ingested_at DATETIME2(3)) WITH (LOCATION='/suppliers/', DATA_SOURCE=ds_bronze, FILE_FORMAT=ff_parquet_snappy, REJECT_TYPE=VALUE, REJECT_VALUE=0);
GO
IF OBJECT_ID('bronze.warehouses') IS NOT NULL DROP EXTERNAL TABLE bronze.warehouses;
CREATE EXTERNAL TABLE bronze.warehouses (warehouse_id NVARCHAR(50), warehouse_name NVARCHAR(50), country NVARCHAR(50), city NVARCHAR(50), capacity_units INT, [__$start_lsn] VARBINARY(16), [__$seqval] VARBINARY(16), [__$operation] INT, [__$update_mask] VARBINARY(128), ingested_at DATETIME2(3)) WITH (LOCATION='/warehouses/', DATA_SOURCE=ds_bronze, FILE_FORMAT=ff_parquet_snappy, REJECT_TYPE=VALUE, REJECT_VALUE=0);
GO
IF OBJECT_ID('bronze.sales_orders') IS NOT NULL DROP EXTERNAL TABLE bronze.sales_orders;
CREATE EXTERNAL TABLE bronze.sales_orders (sales_order_id NVARCHAR(50), customer_id NVARCHAR(50), warehouse_id NVARCHAR(50), order_date DATE, order_status NVARCHAR(50), sales_channel NVARCHAR(50), subtotal FLOAT, discount_total FLOAT, tax_rate FLOAT, tax_amount FLOAT, shipping_cost FLOAT, total_amount FLOAT, [__$start_lsn] VARBINARY(16), [__$seqval] VARBINARY(16), [__$operation] INT, [__$update_mask] VARBINARY(128), ingested_at DATETIME2(3)) WITH (LOCATION='/sales_orders/', DATA_SOURCE=ds_bronze, FILE_FORMAT=ff_parquet_snappy, REJECT_TYPE=VALUE, REJECT_VALUE=0);
GO
IF OBJECT_ID('bronze.sales_order_lines') IS NOT NULL DROP EXTERNAL TABLE bronze.sales_order_lines;
CREATE EXTERNAL TABLE bronze.sales_order_lines (sales_order_line_id NVARCHAR(50), sales_order_id NVARCHAR(50), line_number INT, product_id NVARCHAR(50), quantity INT, unit_price FLOAT, discount_rate FLOAT, line_subtotal FLOAT, discount_amount FLOAT, line_total FLOAT, [__$start_lsn] VARBINARY(16), [__$seqval] VARBINARY(16), [__$operation] INT, [__$update_mask] VARBINARY(128), ingested_at DATETIME2(3)) WITH (LOCATION='/sales_order_lines/', DATA_SOURCE=ds_bronze, FILE_FORMAT=ff_parquet_snappy, REJECT_TYPE=VALUE, REJECT_VALUE=0);
GO
IF OBJECT_ID('bronze.invoices') IS NOT NULL DROP EXTERNAL TABLE bronze.invoices;
CREATE EXTERNAL TABLE bronze.invoices (invoice_id NVARCHAR(50), sales_order_id NVARCHAR(50), customer_id NVARCHAR(50), invoice_date DATE, due_date DATE, payment_term_days INT, invoice_amount FLOAT, amount_paid FLOAT, balance_due FLOAT, invoice_status NVARCHAR(50), days_to_full_payment FLOAT, late_payment BIT, [__$start_lsn] VARBINARY(16), [__$seqval] VARBINARY(16), [__$operation] INT, [__$update_mask] VARBINARY(128), ingested_at DATETIME2(3)) WITH (LOCATION='/invoices/', DATA_SOURCE=ds_bronze, FILE_FORMAT=ff_parquet_snappy, REJECT_TYPE=VALUE, REJECT_VALUE=0);
GO
IF OBJECT_ID('bronze.payments') IS NOT NULL DROP EXTERNAL TABLE bronze.payments;
CREATE EXTERNAL TABLE bronze.payments (payment_id NVARCHAR(50), invoice_id NVARCHAR(50), payment_date DATE, payment_amount FLOAT, payment_method NVARCHAR(50), is_partial_payment BIT, [__$start_lsn] VARBINARY(16), [__$seqval] VARBINARY(16), [__$operation] INT, [__$update_mask] VARBINARY(128), ingested_at DATETIME2(3)) WITH (LOCATION='/payments/', DATA_SOURCE=ds_bronze, FILE_FORMAT=ff_parquet_snappy, REJECT_TYPE=VALUE, REJECT_VALUE=0);
GO
IF OBJECT_ID('bronze.shipments') IS NOT NULL DROP EXTERNAL TABLE bronze.shipments;
CREATE EXTERNAL TABLE bronze.shipments (shipment_id NVARCHAR(50), sales_order_id NVARCHAR(50), warehouse_id NVARCHAR(50), ship_date DATE, expected_delivery_date DATE, actual_delivery_date DATE, carrier NVARCHAR(50), shipping_status NVARCHAR(50), [__$start_lsn] VARBINARY(16), [__$seqval] VARBINARY(16), [__$operation] INT, [__$update_mask] VARBINARY(128), ingested_at DATETIME2(3)) WITH (LOCATION='/shipments/', DATA_SOURCE=ds_bronze, FILE_FORMAT=ff_parquet_snappy, REJECT_TYPE=VALUE, REJECT_VALUE=0);
GO
IF OBJECT_ID('bronze.returns') IS NOT NULL DROP EXTERNAL TABLE bronze.returns;
CREATE EXTERNAL TABLE bronze.returns (return_id NVARCHAR(50), shipment_id NVARCHAR(50), sales_order_line_id NVARCHAR(50), return_date DATE, returned_quantity INT, return_reason NVARCHAR(50), return_condition NVARCHAR(50), restocking_fee_rate FLOAT, refund_amount FLOAT, [__$start_lsn] VARBINARY(16), [__$seqval] VARBINARY(16), [__$operation] INT, [__$update_mask] VARBINARY(128), ingested_at DATETIME2(3)) WITH (LOCATION='/returns/', DATA_SOURCE=ds_bronze, FILE_FORMAT=ff_parquet_snappy, REJECT_TYPE=VALUE, REJECT_VALUE=0);
GO
IF OBJECT_ID('bronze.purchase_orders') IS NOT NULL DROP EXTERNAL TABLE bronze.purchase_orders;
CREATE EXTERNAL TABLE bronze.purchase_orders (purchase_order_id NVARCHAR(50), supplier_id NVARCHAR(50), warehouse_id NVARCHAR(50), order_date DATE, expected_delivery_date DATE, actual_delivery_date DATE, po_status NVARCHAR(50), subtotal FLOAT, freight_cost FLOAT, total_amount FLOAT, [__$start_lsn] VARBINARY(16), [__$seqval] VARBINARY(16), [__$operation] INT, [__$update_mask] VARBINARY(128), ingested_at DATETIME2(3)) WITH (LOCATION='/purchase_orders/', DATA_SOURCE=ds_bronze, FILE_FORMAT=ff_parquet_snappy, REJECT_TYPE=VALUE, REJECT_VALUE=0);
GO
IF OBJECT_ID('bronze.purchase_order_lines') IS NOT NULL DROP EXTERNAL TABLE bronze.purchase_order_lines;
CREATE EXTERNAL TABLE bronze.purchase_order_lines (purchase_order_line_id NVARCHAR(50), purchase_order_id NVARCHAR(50), line_number INT, product_id NVARCHAR(50), quantity_ordered INT, unit_cost FLOAT, line_total FLOAT, quantity_received FLOAT, [__$start_lsn] VARBINARY(16), [__$seqval] VARBINARY(16), [__$operation] INT, [__$update_mask] VARBINARY(128), ingested_at DATETIME2(3)) WITH (LOCATION='/purchase_order_lines/', DATA_SOURCE=ds_bronze, FILE_FORMAT=ff_parquet_snappy, REJECT_TYPE=VALUE, REJECT_VALUE=0);
GO
IF OBJECT_ID('bronze.supplier_invoices') IS NOT NULL DROP EXTERNAL TABLE bronze.supplier_invoices;
CREATE EXTERNAL TABLE bronze.supplier_invoices (supplier_invoice_id NVARCHAR(50), purchase_order_id NVARCHAR(50), supplier_id NVARCHAR(50), invoice_date DATE, due_date DATE, invoice_amount FLOAT, amount_paid FLOAT, balance_due FLOAT, invoice_status NVARCHAR(50), [__$start_lsn] VARBINARY(16), [__$seqval] VARBINARY(16), [__$operation] INT, [__$update_mask] VARBINARY(128), ingested_at DATETIME2(3)) WITH (LOCATION='/supplier_invoices/', DATA_SOURCE=ds_bronze, FILE_FORMAT=ff_parquet_snappy, REJECT_TYPE=VALUE, REJECT_VALUE=0);
GO
IF OBJECT_ID('bronze.supplier_payments') IS NOT NULL DROP EXTERNAL TABLE bronze.supplier_payments;
CREATE EXTERNAL TABLE bronze.supplier_payments (supplier_payment_id NVARCHAR(50), supplier_invoice_id NVARCHAR(50), payment_date DATE, payment_amount FLOAT, payment_method NVARCHAR(50), [__$start_lsn] VARBINARY(16), [__$seqval] VARBINARY(16), [__$operation] INT, [__$update_mask] VARBINARY(128), ingested_at DATETIME2(3)) WITH (LOCATION='/supplier_payments/', DATA_SOURCE=ds_bronze, FILE_FORMAT=ff_parquet_snappy, REJECT_TYPE=VALUE, REJECT_VALUE=0);
GO
IF OBJECT_ID('bronze.inventory_snapshots') IS NOT NULL DROP EXTERNAL TABLE bronze.inventory_snapshots;
CREATE EXTERNAL TABLE bronze.inventory_snapshots (inventory_snapshot_id NVARCHAR(50), snapshot_date DATETIME2, product_id NVARCHAR(50), warehouse_id NVARCHAR(50), quantity_on_hand INT, quantity_on_order NVARCHAR(50), reorder_point INT, is_stockout BIT, inventory_value FLOAT, [__$start_lsn] VARBINARY(16), [__$seqval] VARBINARY(16), [__$operation] INT, [__$update_mask] VARBINARY(128), ingested_at DATETIME2(3)) WITH (LOCATION='/inventory_snapshots/', DATA_SOURCE=ds_bronze, FILE_FORMAT=ff_parquet_snappy, REJECT_TYPE=VALUE, REJECT_VALUE=0);
GO
IF OBJECT_ID('bronze.support_tickets') IS NOT NULL DROP EXTERNAL TABLE bronze.support_tickets;
CREATE EXTERNAL TABLE bronze.support_tickets (support_ticket_id NVARCHAR(50), customer_id NVARCHAR(50), related_sales_order_id NVARCHAR(50), related_shipment_id NVARCHAR(50), related_invoice_id NVARCHAR(50), created_at DATE, category NVARCHAR(50), priority NVARCHAR(50), ticket_text NVARCHAR(50), sentiment NVARCHAR(50), resolution_time_hours FLOAT, status NVARCHAR(50), [__$start_lsn] VARBINARY(16), [__$seqval] VARBINARY(16), [__$operation] INT, [__$update_mask] VARBINARY(128), ingested_at DATETIME2(3)) WITH (LOCATION='/support_tickets/', DATA_SOURCE=ds_bronze, FILE_FORMAT=ff_parquet_snappy, REJECT_TYPE=VALUE, REJECT_VALUE=0);
GO
