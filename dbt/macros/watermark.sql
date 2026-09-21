{#
    Control incremental centralizado.
    ------------------------------------------------------------------
    obtener_watermark(capa, entidad)
        Devuelve el ultimo timestamp procesado, menos un buffer de
        seguridad para tolerar eventos que llegaron tarde al lake.
        Si no hay checkpoint (primera corrida) devuelve una fecha zocalo
        para que el modelo cargue todo el historico.

    obtener_watermark_lsn(capa, entidad)
        Igual, pero por LSN de CDC. Es el modo preferente cuando ADF
        entrega el campo __$start_lsn en Bronze.

    actualizar_watermark(this, capa)
        Post-hook. Escribe el nuevo checkpoint a partir de lo que quedo
        realmente materializado en la tabla destino, no de la hora del
        reloj: si el modelo fallo a medias, el watermark no avanza.
#}

{% macro obtener_watermark(capa, entidad) -%}
    {%- set buffer = var('late_arriving_buffer_minutes', 15) -%}
    {%- set consulta -%}
        SELECT COALESCE(
                 DATEADD(MINUTE, -{{ buffer }}, MAX(last_loaded_at)),
                 CAST('1900-01-01' AS DATETIME2(3))
               ) AS wm
        FROM   meta.etl_watermark
        WHERE  layer_name  = '{{ capa }}'
          AND  entity_name = '{{ entidad }}'
    {%- endset -%}

    {%- if execute -%}
        {%- set resultado = run_query(consulta) -%}
        {%- set wm = resultado.columns[0].values()[0] -%}
        {{ return("CAST('" ~ wm ~ "' AS DATETIME2(3))") }}
    {%- else -%}
        {{ return("CAST('1900-01-01' AS DATETIME2(3))") }}
    {%- endif -%}
{%- endmacro %}


{% macro obtener_watermark_lsn(capa, entidad) -%}
    {%- set consulta -%}
        SELECT COALESCE(
                 CONVERT(VARCHAR(34), MAX(last_lsn), 1),
                 '0x00000000000000000000'
               ) AS lsn
        FROM   meta.etl_watermark
        WHERE  layer_name  = '{{ capa }}'
          AND  entity_name = '{{ entidad }}'
    {%- endset -%}

    {%- if execute -%}
        {%- set resultado = run_query(consulta) -%}
        {{ return(resultado.columns[0].values()[0]) }}
    {%- else -%}
        {{ return('0x00000000000000000000') }}
    {%- endif -%}
{%- endmacro %}


{% macro actualizar_watermark(relacion, capa, columna_ts='ingested_at', columna_lsn=None) -%}
    {%- set entidad = relacion.identifier -%}
    {%- set expr_lsn = 'MAX(' ~ columna_lsn ~ ')' if columna_lsn else 'CAST(NULL AS VARBINARY(16))' -%}

    DELETE FROM meta.etl_watermark
    WHERE  layer_name = '{{ capa }}' AND entity_name = '{{ entidad }}';

    INSERT INTO meta.etl_watermark
        (layer_name, entity_name, last_lsn, last_loaded_at,
         last_run_id, rows_last_batch, updated_at)
    SELECT '{{ capa }}',
           '{{ entidad }}',
           {{ expr_lsn }},
           MAX({{ columna_ts }}),
           '{{ invocation_id }}',
           COUNT_BIG(*),
           SYSUTCDATETIME()
    FROM   {{ relacion }};
{%- endmacro %}


{#  Filtro incremental reutilizable: se escribe una sola vez y todos los
    modelos Silver lo invocan, de modo que cambiar la estrategia
    (LSN vs timestamp) es un cambio en un unico lugar.  #}
{% macro filtro_incremental(capa, entidad, columna='ingested_at') -%}
    {%- if is_incremental() %}
        AND {{ columna }} > {{ obtener_watermark(capa, entidad) }}
    {%- endif %}
{%- endmacro %}
