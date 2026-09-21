{#
    Registro de calidad de datos.
    dbt escribe los fallos en tablas meta.<nombre_test> gracias a
    store_failures; este macro los consolida en meta.data_quality_log
    para tener una sola serie historica consultable desde Power BI.
    Se invoca con:  dbt run-operation consolidar_calidad
#}

{% macro consolidar_calidad() %}
    {% set buscar_tests %}
        SELECT s.name AS esquema, t.name AS tabla
        FROM   sys.tables t
        JOIN   sys.schemas s ON s.schema_id = t.schema_id
        WHERE  s.name = 'meta'
          AND  t.name NOT IN ('etl_watermark','pipeline_run_log',
                              'data_quality_log','reconciliation_log')
    {% endset %}

    {% if execute %}
        {% set tablas = run_query(buscar_tests) %}
        {% for fila in tablas.rows %}
            {% set nombre_test = fila[1] %}
            {% set insertar %}
                INSERT INTO meta.data_quality_log
                    (run_id, layer_name, entity_name, test_name,
                     severity, failed_rows, sample_value, detected_at)
                SELECT '{{ invocation_id }}',
                       CASE WHEN '{{ nombre_test }}' LIKE '%gold%' THEN 'gold' ELSE 'silver' END,
                       '{{ nombre_test }}',
                       '{{ nombre_test }}',
                       'error',
                       COUNT_BIG(*),
                       NULL,
                       SYSUTCDATETIME()
                FROM   meta.[{{ nombre_test }}]
                HAVING COUNT_BIG(*) > 0;
            {% endset %}
            {% do run_query(insertar) %}
        {% endfor %}
        {% do log("Calidad consolidada: " ~ tablas.rows | length ~ " tests revisados.", info=True) %}
    {% endif %}
{% endmacro %}


{#  Registro de una ejecucion en la bitacora de pipeline.  #}
{% macro registrar_ejecucion(pipeline, capa, entidad, estado, filas=0, error='') %}
    INSERT INTO meta.pipeline_run_log
        (run_id, pipeline_name, layer_name, entity_name,
         status, rows_affected, error_message, logged_at)
    VALUES ('{{ invocation_id }}', '{{ pipeline }}', '{{ capa }}', '{{ entidad }}',
            '{{ estado }}', {{ filas }}, '{{ error }}', SYSUTCDATETIME());
{% endmacro %}
