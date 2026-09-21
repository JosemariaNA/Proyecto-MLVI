SELECT
    capture_instance,
    start_lsn,
    supports_net_changes
FROM cdc.change_tables
ORDER BY capture_instance;