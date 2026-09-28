{#
    Resolucion de eventos CDC -> estado actual de la fila.
    ------------------------------------------------------------------
    El CDC de SQL Server entrega N eventos por clave dentro de un mismo
    microlote. Silver necesita exactamente uno: el ultimo. El orden
    correcto es (__$start_lsn, __$seqval) y NO el timestamp de ingesta,
    porque dos transacciones pueden aterrizar en el lake desordenadas.

    La imagen previa de un update (__$operation = 3) se descarta: solo
    describe como estaba la fila antes y duplicaria la clave.

    Un delete (__$operation = 1) no se descarta: se propaga como
    borrado logico (is_deleted = 1) para que Gold pueda excluirlo sin
    perder la trazabilidad de que existio.
#}

{% macro ultimo_evento_cdc(relacion_origen, clave_negocio, capa, entidad) -%}
    SELECT *
    FROM (
        SELECT *,
               ROW_NUMBER() OVER (PARTITION BY {{ clave_negocio }} ORDER BY (SELECT NULL)) as _rn
        FROM {{ relacion_origen }}
        WHERE 1=1
        {{ filtro_incremental(capa, entidad) }}
    ) src
    WHERE _rn = 1
{%- endmacro %}


{#  Marca de borrado logico a partir del tipo de operacion CDC.  #}
{% macro es_borrado() -%}
    CAST(0 AS BIT)
{%- endmacro %}


{#  Normalizaciones de texto reutilizadas en toda la capa Silver.
    Centralizarlas evita que cada modelo invente su propia limpieza,
    que es el origen clasico de dimensiones que no casan entre si.  #}
{% macro limpiar_texto(columna) -%}
    NULLIF(LTRIM(RTRIM(CAST({{ columna }} AS NVARCHAR(400)))), '')
{%- endmacro %}

{% macro limpiar_email(columna) -%}
    LOWER(NULLIF(LTRIM(RTRIM(CAST({{ columna }} AS NVARCHAR(256)))), ''))
{%- endmacro %}

{% macro limpiar_telefono(columna) -%}
    NULLIF(
        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
            CAST({{ columna }} AS NVARCHAR(50)),
        ' ', ''), '-', ''), '(', ''), ')', ''), '.', ''),
    '')
{%- endmacro %}

{#  Clave de fecha entera YYYYMMDD, el formato que espera DimFecha.  #}
{% macro clave_fecha(columna) -%}
    CAST(CONVERT(CHAR(8), {{ columna }}, 112) AS INT)
{%- endmacro %}
