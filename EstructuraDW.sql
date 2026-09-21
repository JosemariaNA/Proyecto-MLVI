Agrega este tambien:
USE MessyOpsDW;
GO

-- Crear tabla data_quality_log en el DW (si no existe)
IF OBJECT_ID('dbo.data_quality_log','U') IS NULL
BEGIN
    CREATE TABLE dbo.data_quality_log
    (
        DataQualityLogKey      BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY, -- clave surrogate para el DW
        issue_id               nvarchar(50)    NULL,
        table_name             nvarchar(50)    NOT NULL,
        row_primary_key        nvarchar(50)    NULL,
        column_name            nvarchar(50)    NULL,
        issue_type             nvarchar(50)    NULL,
        severity               nvarchar(50)    NULL,
        original_clean_value   nvarchar(50)    NULL,
        corrupted_value        nvarchar(50)    NULL,
        is_auto_detectable     bit             NULL,
        is_repair_suggested    nvarchar(50)    NULL,
        description            nvarchar(100)   NULL,

        -- Columnas de auditoría (opcionales pero recomendadas en DW)
        source_system          nvarchar(50)    NULL,   -- ejemplo: 'OLTP', 'SSIS_ETL'
        etl_run_id             int             NULL,   -- referencia al id de ejecución del ETL
        package_name           nvarchar(100)   NULL,
        created_at             datetime2       NOT NULL DEFAULT SYSUTCDATETIME()
    );

    -- Índices sugeridos para consultas comunes y rendimiento de búsquedas
    CREATE NONCLUSTERED INDEX IX_dqlog_table_issue_created
    ON dbo.data_quality_log(table_name, issue_type, severity, created_at);
END
GO