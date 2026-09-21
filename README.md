# AzureDW — Data Warehouse Medallion (Bronze → Silver → Gold)

Implementación de las capas **Silver** y **Gold** del Data Warehouse de MessyOps sobre el grupo de recursos `AzureDW`, siguiendo la guía técnica del proyecto. Silver se construyó con el mismo rigor que Gold: modelado explícito, control incremental, pruebas, versionado y documentación.

## Arquitectura

```
MessyOpsOLTP (Azure SQL, CDC nativo)
        │  cdc.fn_cdc_get_all_changes_*  (rango de LSN)
        ▼
ADF  pl_00_ingesta_cdc_bronze  ──►  ADLS Gen2 /bronze/<entidad>/date=YYYY-MM-DD/*.parquet
        │
        ▼
ADF  pl_10_ejecutar_dbt (ACI efímero) ──►  Azure Synapse Analytics MessyOpsDW
                                              ├─ silver.*   (7 modelos incrementales)
                                              ├─ gold.snp_* (snapshots SCD2)
                                              ├─ gold.*     (esquema estrella)
                                              └─ meta.*     (watermark, calidad, auditoría)
                                                    │
                                                    ▼
                                             Power BI Service
```

Todo el flujo se dispara cada 5 minutos con una **ventana de volteo** (`tr_microlote_5min`), con concurrencia 1 para que dos microlotes nunca escriban Silver a la vez.

## Contenido del repositorio

| Carpeta | Qué contiene |
|---|---|
| `sql/` | Scripts que dbt no gestiona: esquema `meta`, habilitación y control del CDC, batería de validación. |
| `dbt/` | Proyecto dbt: 7 modelos Silver, 6 modelos Gold, 2 snapshots SCD2, macros de control incremental y 106 tests. |
| `adf/` | Linked services, datasets, 3 pipelines y el trigger, en el formato JSON del modo Git de ADF. |
| `scripts/` | Verificación de entorno (solo lectura), preparación del lake y permisos, y el Dockerfile del ejecutor dbt. |
| `docs/` | Arquitectura, modelo dimensional, catálogo de datos, runbook de despliegue y costes. |

## Orden de despliegue

El CDC está apagado a propósito y se enciende **al final**. El orden completo está en [`docs/03-runbook-despliegue.md`](docs/03-runbook-despliegue.md); en resumen:

1. `scripts/00_verificar_entorno.sh` — confirmar recursos (no crea nada).
2. `sql/01_meta_control.sql` → `sql/03_cdc_control.sql` → `sql/00_bronze_external.sql` en Synapse `MessyOpsDW`.
3. `dbt deps && dbt build` — crea Silver, snapshots y Gold.
4. Publicar `adf/` en messyops-adf (trigger queda detenido).
5. **Al final:** `sql/02_cdc_setup.sql` en el OLTP, `EXEC meta.sp_activar_ingesta_cdc`, y arrancar el trigger.
6. `sql/04_validaciones.sql` tras el primer microlote real.

## Decisiones clave

- **Estrella, no copo de nieve.** La jerarquía de producto tiene dos niveles y baja cardinalidad: aplanarla en `dim_producto` es más rápido y no añade mantenimiento. El criterio para cambiar está documentado en el propio modelo.
- **SCD2 con snapshots de dbt** para cliente y producto; **SCD1** para canal y sucursal.
- **Claves sustitutas por hash determinista**, no `IDENTITY`: reprocesar produce las mismas claves y el MERGE sigue siendo idempotente.
- **Miembro desconocido (-1)** en todas las dimensiones: un maestro que llega tarde degrada el reporte en vez de borrar la venta.
- **Azure Synapse Analytics**, con Bronze expuesto sobre ADLS y Silver/Gold materializados por dbt.
- **dbt en Azure Container Instance efímero**: solo se factura el tiempo de ejecución de cada microlote.

## Credenciales

Ningún archivo del repositorio contiene contraseñas. dbt las lee de variables de entorno y ADF usa identidades administradas. `profiles.example.yml` muestra la plantilla.
