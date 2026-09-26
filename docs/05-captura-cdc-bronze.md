# Captura CDC y capa Bronze

## Qué pide el proyecto y cómo se cumple

| Requisito | Implementación |
|---|---|
| Origen SQL Database con CDC nativo | `MessyOpsOLTP` con CDC activo en las 16 tablas de negocio (`sql/02_cdc_setup.sql`). |
| Captura con ADF — CDC (recurso nativo), checkpoint propio | Recurso **Change Data Capture** de ADF `cdc_oltp_bronze` (`adf/adfcdc/`). Lee el CDC de Azure SQL y guarda su propio checkpoint de LSN. No es un pipeline ni una actividad Copy. |
| Carga incremental, sin full load | Tras una única instantánea inicial, el recurso solo lee cambios del log. Nunca se recarga una tabla completa. |
| Medallion en ADLS Gen2 | Bronze = contenedor `bronze/<entidad>/` de `messyopsdl2026`, en Parquet. Contenedores `silver` y `gold` ya creados. |
| Todo por CLI, versionado en Git | `scripts/01…03` (az + sqlcmd). La definición del recurso se genera desde el DDL del OLTP (`scripts/generar_bronze.py`). |

## Flujo

```
MessyOpsOLTP (Azure SQL, CDC nativo en 16 tablas, retención 7 días)
      │  cdc.fn_cdc_get_net_changes_dbo_<tabla>   ← lo invoca el recurso, no código propio
      ▼
ADF · recurso CDC  cdc_oltp_bronze   (microlote de 15 min, checkpoint de LSN interno)
      │  1ª ejecución: instantánea inicial de cada tabla (cdc_operation = 'I')
      │  siguientes:   solo cambios netos
      ▼
ADLS Gen2  bronze/<entidad>/*.parquet
      │  columnas del OLTP + cdc_operation (I/U/D) + ingested_at (UTC)
      ▼
Synapse messyops-synapse · pool serverless Built-in · base MessyOpsDW
                    bronze.<entidad>   (tablas externas nativas, lectura por nombre de columna)
                    meta.vw_bronze_frescura
```

## Decisiones

**Una sola instantánea inicial (`skipInitialLoad = false`).** El CDC de SQL solo contiene cambios posteriores a su activación. Las ~75.000 órdenes que ya existían no están en las tablas de cambios. Sin la instantánea, Bronze arrancaría vacío. Esto no es una carga completa recurrente: ocurre una vez por tabla y el recurso continúa desde el LSN en que terminó. Es el mismo patrón que usan Debezium o Fivetran.

**Cambios netos (`netChanges = true`).** Con microlotes de 15 minutos, a Silver solo le importa el último estado de cada clave dentro del lote. Los cambios netos entregan como máximo una fila por clave y microlote. Con eso el orden entre eventos de una misma clave lo da `ingested_at`, sin necesidad de exponer el LSN.

**Microlote de 15 minutos.** Es la latencia más baja del modo por lotes del recurso. El trigger de dbt (`tr_microlote_5min`) se alineó a 15 minutos: transformar más seguido de lo que llegan datos solo genera ejecuciones vacías con costo.

**Contrato Bronze → Silver.** Columnas del OLTP con sus nombres originales, más:

| Columna | Origen | Uso en Silver |
|---|---|---|
| `cdc_operation` | columna derivada `iif(isDelete(),'D',iif(isUpdate(),'U','I'))` | `D` = borrado lógico |
| `ingested_at` | columna derivada `currentUTC()` | orden entre eventos y watermark incremental |

**Tablas externas nativas en lugar de `TYPE = HADOOP`.** Enlazan las columnas del Parquet por nombre, no por posición. Así el orden en que el recurso escribe las columnas no importa. `tinyint`/`smallint` se ensanchan a `INT` para tolerar cómo se anoten en Parquet. `ticket_text` conserva sus 100 caracteres (antes se declaraba de 50).

**Synapse serverless para Bronze.** El workspace `messyops-synapse` ya existe y su pool SQL serverless (Built-in) está siempre disponible. Solo cobra por datos leídos, y Bronze solo necesita tablas externas sobre el lago, así que no hace falta un pool dedicado. El mismo SQL funciona en un pool dedicado (`DW_MODO=dedicado`). Qué motor usar para Silver y Gold se decide al adaptar Silver: serverless no admite `MERGE` ni tablas materializadas.

**Un solo origen de verdad para el esquema.** `scripts/generar_bronze.py` lee `EstructuraOLTP.sql` y genera a la vez la definición del recurso CDC y las tablas externas. Si cambia el OLTP, se regenera y ambos quedan alineados.

**Checkpoint.** Lo guarda el recurso (requisito "checkpoint propio"). Ya no hacen falta `meta.cdc_control` ni los procedimientos `sp_cerrar_lote_cdc` / `sp_activar_ingesta_cdc`. La observabilidad desde el DW la da `meta.vw_bronze_frescura`.

## Qué verificar en la primera ejecución real

La definición del recurso se validó contra el modelo del SDK oficial de ADF (`ChangeDataCaptureResource`). Hay tres comportamientos que dependen del servicio y conviene confirmarlos con datos:

1. **Que `cdc_operation` llegue con `D` al borrar una fila en el OLTP.** Prueba: borrar una fila de prueba, esperar un microlote y consultar `bronze.<tabla> WHERE cdc_operation = 'D'`. Si el destino Parquet descarta los borrados, Silver no podrá marcar `es_borrado`. En ese caso, cambiar el destino a Delta.
2. **Que la instantánea inicial complete todas las claves:** consulta B2 de `sql/05_validar_bronze.sql`.
3. **Si ADF ajusta algo de la definición al publicarla:** `./scripts/03_desplegar_adf_cdc.sh exportar` y revisar el diff en Git.

## Impacto en Silver (pendiente)

Los modelos Silver todavía esperan el contrato anterior (`__$start_lsn`, `__$seqval`, `__$operation`) y deben adaptarse a este:

- **`ultimo_evento_cdc`:** ordenar por `ingested_at` y no descartar imagen previa, porque el recurso no la entrega.
- **`es_borrado`:** `cdc_operation = 'D'`.
- **`lsn_origen`:** eliminarlo o sustituirlo por `ingested_at`.
