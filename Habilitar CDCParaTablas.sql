EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'customers',
    @role_name = NULL;

EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'products',
    @role_name = NULL;

EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'sales_orders',
    @role_name = NULL;

EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'sales_order_lines',
    @role_name = NULL;

EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'inventory_snapshots',
    @role_name = NULL;

EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'invoices',
    @role_name = NULL;

EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'payments',
    @role_name = NULL;

EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'purchase_orders',
    @role_name = NULL;

EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'purchase_order_lines',
    @role_name = NULL;

EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'suppliers',
    @role_name = NULL;

EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'supplier_invoices',
    @role_name = NULL;

EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'supplier_payments',
    @role_name = NULL;

EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'shipments',
    @role_name = NULL;

EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'returns',
    @role_name = NULL;

EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'support_tickets',
    @role_name = NULL;

EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'warehouses',
    @role_name = NULL;