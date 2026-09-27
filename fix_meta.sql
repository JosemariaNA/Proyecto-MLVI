CREATE TABLE meta.etl_watermark
(
    layer_name        VARCHAR(20)   NOT NULL,   
    entity_name       VARCHAR(128)  NOT NULL,   
    last_lsn          VARBINARY(16) NULL,       
    last_loaded_at    DATETIME2(3)  NULL,       
    last_run_id       VARCHAR(64)   NULL,       
    rows_last_batch   BIGINT        NULL,
    updated_at        DATETIME2(3)  NOT NULL
);
GO
CREATE TABLE meta.pipeline_run_log
(
    run_id          VARCHAR(64)  NOT NULL,
    pipeline_name   VARCHAR(128) NOT NULL,
    layer_name      VARCHAR(20)  NULL,
    entity_name     VARCHAR(128) NULL,
    window_start    DATETIME2(3) NULL,
    window_end      DATETIME2(3) NULL,
    status          VARCHAR(20)  NOT NULL,      
    rows_affected   BIGINT       NULL,
    duration_ms     BIGINT       NULL,
    error_message   NVARCHAR(4000) NULL,
    logged_at       DATETIME2(3) NOT NULL
);
GO
CREATE TABLE meta.data_quality_log
(
    run_id          VARCHAR(64)   NOT NULL,
    layer_name      VARCHAR(20)   NOT NULL,
    entity_name     VARCHAR(128)  NOT NULL,
    test_name       VARCHAR(256)  NOT NULL,
    severity        VARCHAR(10)   NOT NULL,     
    failed_rows     BIGINT        NOT NULL,
    sample_value    NVARCHAR(2000) NULL,
    detected_at     DATETIME2(3)  NOT NULL
);
GO
CREATE TABLE meta.reconciliation_log
(
    run_id            VARCHAR(64)  NOT NULL,
    check_name        VARCHAR(128) NOT NULL,
    period_key        INT          NULL,        
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
