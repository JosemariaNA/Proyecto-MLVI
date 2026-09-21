{#
    Historizacion SCD tipo 2 del cliente.
    Se usa el mecanismo nativo de snapshots de dbt en vez de un MERGE
    artesanal: dbt garantiza la apertura y cierre de versiones, y deja
    la tabla auditada con dbt_valid_from / dbt_valid_to.

    Estrategia 'check' sobre los atributos que el negocio quiere
    historizar. Un cambio de telefono no abre version nueva; un cambio
    de pais si, porque reasigna la venta a otra geografia.
#}
{% snapshot snp_clientes %}

    {{ config(
        target_schema = 'gold',
        unique_key    = 'cliente_id',
        strategy      = 'check',
        check_cols    = ['nombre_completo', 'email', 'pais', 'ciudad', 'es_borrado'],
        invalidate_hard_deletes = true
    ) }}

    select
        cliente_id,
        nombre,
        apellido,
        nombre_completo,
        email,
        telefono,
        pais,
        ciudad,
        email_valido,
        creado_en,
        es_borrado,
        ingested_at
    from {{ ref('slv_clientes') }}

{% endsnapshot %}
