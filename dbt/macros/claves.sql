{#
    Claves sustitutas deterministas.
    Se usa un hash en vez de IDENTITY para que reprocesar una particion
    produzca las mismas claves y el MERGE siga siendo idempotente.
#}

{% macro clave_sustituta(campos) -%}
    CONVERT(BIGINT, CONVERT(VARBINARY(8),
        HASHBYTES('SHA2_256',
            {%- for campo in campos %}
            CONCAT(COALESCE(CAST({{ campo }} AS NVARCHAR(200)), '<null>'), '||')
            {%- if not loop.last %} + {% endif -%}
            {%- endfor %}
        )
    ))
{%- endmacro %}


{#  Hash de atributos para detectar cambios en SCD tipo 2 sin comparar
    columna por columna en el MERGE.  #}
{% macro hash_atributos(campos) -%}
    CONVERT(CHAR(64), HASHBYTES('SHA2_256',
        {%- for campo in campos %}
        CONCAT(COALESCE(CAST({{ campo }} AS NVARCHAR(400)), '<null>'), '||')
        {%- if not loop.last %} + {% endif -%}
        {%- endfor %}
    ), 2)
{%- endmacro %}


{#  Resuelve una clave foranea contra una dimension, devolviendo el
    centinela -1 cuando el negocio todavia no envio el maestro.
    Esto evita perder hechos por integridad referencial.  #}
{% macro resolver_dimension(clave_negocio, alias_dim, columna_dim) -%}
    COALESCE({{ alias_dim }}.{{ columna_dim }}, {{ var('unknown_key', -1) }})
{%- endmacro %}
