{#
    Historizacion SCD tipo 2 del producto.
    Se historiza precio, costo y categoria: son los atributos que
    cambian el analisis de margen a lo largo del tiempo. El nombre
    comercial tambien, porque los reportes historicos deben mostrar
    como se llamaba el producto cuando se vendio.
#}
{% snapshot snp_productos %}

    {{ config(
        target_schema = 'gold',
        unique_key    = 'producto_id',
        strategy      = 'check',
        check_cols    = ['nombre_producto', 'categoria_id', 'marca',
                         'costo_unitario', 'precio_unitario', 'activo', 'es_borrado'],
        invalidate_hard_deletes = true
    ) }}

    select
        producto_id,
        sku,
        nombre_producto,
        categoria_id,
        categoria_nombre,
        categoria_padre_id,
        categoria_padre_nombre,
        marca,
        costo_unitario,
        precio_unitario,
        margen_unitario,
        activo,
        es_borrado,
        ingested_at
    from {{ ref('slv_productos') }}

{% endsnapshot %}
