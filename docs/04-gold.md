# Capa Gold — Esquema Estrella

La capa Gold está diseñada puramente para el consumo de analítica y BI, organizada bajo un modelo dimensional en esquema estrella clásico.

## Arquitectura del Esquema

```
                 dim_fecha
                        │
dim_cliente ──┐         │         ┌── dim_producto
 (SCD2)       ├──── fact_ventas ──┤    (SCD2)
dim_canal ────┘       fact_ventas └── dim_sucursal
 (SCD1)                                 (SCD1)
```

## Detalles de Hechos y Medidas

**Grano de `fact_ventas`:** Una línea de detalle de pedido. Es el grano más fino disponible; cualquier agregado (por día, por cliente, por sucursal) se deriva agrupando esta tabla.

**Medidas principales:** 
- `cantidad`
- `precio_unitario`
- `descuento`
- `importe`
- `costo`: Calculado como (cantidad × costo de la versión del producto vigente en la fecha de la venta).
- `margen`

## Control Incremental en Gold

Al igual que en Silver, la ingesta hacia Gold está optimizada para procesar únicamente las ventas nuevas o modificadas.

| Capa | Checkpoint | Dónde vive |
|---|---|---|
| Gold | `ingested_at` del detalle **o** de su cabecera | `meta.etl_watermark` |

Gold solo lee desde Silver las filas cuyo `ingested_at` sea mayor al último watermark registrado en `meta.etl_watermark`, procesando los Upserts necesarios en las tablas de dimensiones y hechos.
