# AzureDW — Data Warehouse Medallion (Bronze → Silver → Gold)

Implementación de las capas **Silver** y **Gold** del Data Warehouse de MessyOps sobre el grupo de recursos `AzureDW`, siguiendo la guía técnica del proyecto. Silver se construyó con el mismo rigor que Gold: modelado explícito, control incremental, pruebas, versionado y documentación.

## Arquitectura

```
MessyOpsOLTP (Azure SQL, CDC nativo en 16 tablas)
        │  cambios netos por LSN
        ▼
ADF · recurso CDC nativo  cdc_oltp_bronze
        │  microlote 15 min, checkpoint propio, instantánea inicial única
        ▼
ADLS Gen2 /bronze/<entidad>/*.parquet   (columnas OLTP + cdc_operation + ingested_at)
        │  tablas externas bronze.* en Synapse
        ▼
ADF  pl_10_ejecutar_dbt (Azure Batch) ──►  Azure Synapse Analytics MessyOpsDW
                                              ├─ silver.*   (7 modelos incrementales)
                                              ├─ gold.snp_* (snapshots SCD2)
                                              ├─ gold.*     (esquema estrella)
                                              └─ meta.*     (watermark, calidad, auditoría)
                                                    │
                                                    ▼
                                             Power BI Service
```

Bronze se alimenta de forma continua con el recurso CDC nativo de ADF. Silver y Gold se disparan cada 15 minutos con una **ventana de volteo** (`tr_microlote_15min`), alineada con los microlotes de Bronze y con concurrencia 1 para que dos microlotes nunca escriban Silver a la vez. El detalle de la captura está en [`docs/02-captura-cdc-bronze.md`](docs/02-captura-cdc-bronze.md).

## Contenido del repositorio

| Carpeta | Qué contiene |
|---|---|
| `sql/` | Scripts que dbt no gestiona: CDC en el OLTP (`02`), tablas externas Bronze (`00`, generado), monitoreo de Bronze (`03`), esquema `meta` y batería de validación. |
| `dbt/` | Proyecto dbt: 7 modelos Silver, 6 modelos Gold, 2 snapshots SCD2, macros de control incremental y 106 tests. |
| `adf/` | Recurso CDC nativo (`adfcdc/`), linked services, pipelines de dbt y el trigger, en el formato JSON del modo Git de ADF. |
| `scripts/` | Todo por CLI: verificación (`00`), aprovisionamiento (`01`), despliegue SQL con sqlcmd (`02`), despliegue del recurso CDC (`03`), generador de Bronze y el Dockerfile del ejecutor dbt. |
| `docs/` | Flujo completo, CDC Bronze, Silver, Gold, modelo dimensional, catálogo, costos y runbooks de despliegue. |

## Orden de despliegue

Todo por consola. El detalle está en [`docs/08-runbook-despliegue-local.md`](docs/08-runbook-despliegue-local.md); en resumen:

1. `./scripts/00_verificar_entorno.sh`: línea base, solo lectura.
2. `./scripts/01_aprovisionar.sh`: lago, ADF, Synapse, firewall, administradores Entra y RBAC. Es idempotente.
3. `./scripts/02_desplegar_sql.sh oltp`, y luego `bronze`: CDC en el OLTP y tablas externas Bronze.
4. `./scripts/03_desplegar_adf_cdc.sh desplegar`, y luego `iniciar`: captura CDC nativa.
5. `./scripts/02_desplegar_sql.sh validar`: V0 y frescura de Bronze.
6. dbt (Silver y Gold) y los pipelines de orquestación, completamente adaptados al nuevo contrato de Bronze y orquestados vía Azure Batch.

## Decisiones clave

- **Estrella, no copo de nieve.** La jerarquía de producto tiene dos niveles y baja cardinalidad: aplanarla en `dim_producto` es más rápido y no añade mantenimiento. El criterio para cambiar está documentado en el propio modelo.
- **SCD2 con snapshots de dbt** para cliente y producto: Se emplea la funcionalidad nativa de dbt para historizar los cambios dimensionales, garantizando que el análisis histórico del esquema estrella no se vea alterado por actualizaciones recientes, evitando así la necesidad de escribir lógicas MERGE manuales propensas a errores. Para canal y sucursal se usa **SCD1**.
- **Claves sustitutas por hash determinista**, no `IDENTITY`: reprocesar produce las mismas claves y el MERGE sigue siendo idempotente.
- **Miembro desconocido (-1)** en todas las dimensiones: un maestro que llega tarde degrada el reporte en vez de borrar la venta.
- **Captura con el recurso CDC nativo de ADF**, no con pipelines de copia: el recurso lee el CDC de Azure SQL y guarda su propio checkpoint. Hace una única instantánea inicial y después solo lee cambios netos.
- **Esquema de Bronze generado desde el DDL del OLTP** (`scripts/generar_bronze.py`): el recurso CDC y las tablas externas no pueden desalinearse.
- **Azure Synapse Analytics** (`messyops-synapse`): Bronze se expone sobre ADLS con tablas externas nativas en el pool serverless Built-in, sin costo por hora. Silver y Gold se materializan con dbt; el motor se define al adaptar Silver (pool dedicado o serverless).
- **dbt en Azure Batch**: Se utiliza una Custom Activity en ADF conectada a Azure Batch. El nodo de procesamiento descarga el repositorio de GitHub y ejecuta dbt al vuelo, dándonos mayor control sobre el poder de cómputo y evitando la necesidad de compilar y mantener imágenes de Docker.

## Credenciales

Ningún archivo del repositorio contiene contraseñas. ADF y Synapse usan identidades administradas; los scripts usan la sesión de `az login`. La master key de Synapse se pasa por la variable `MASTER_KEY_PWD` y dbt lee sus credenciales de variables de entorno (`profiles.example.yml`).
