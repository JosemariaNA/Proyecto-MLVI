# Runbook de despliegue

Todo se ejecuta por consola (Azure CLI, go-sqlcmd, dbt), desde la raíz del repositorio. Cada fase indica cómo comprobar que salió bien. Los nombres de recursos viven en `scripts/config.sh`.

> **Estado:** Todas las fases del proyecto se encuentran completadas. Las capas Bronze, Silver y Gold están totalmente alineadas con el recurso CDC nativo de ADF, y la orquestación de dbt ocurre exitosamente en Azure Batch.

## Fase 0 — Requisitos

- Azure CLI con sesión iniciada: `az login` y `az account set -s <suscripcion>`.
- `jq`, `python3` y go-sqlcmd (`winget install sqlcmd` o `brew install sqlcmd`).
- En Windows, ejecutar los `.sh` desde Git Bash o WSL.

## Fase 1 — Verificación (solo lectura, sin costo)

```bash
./scripts/00_verificar_entorno.sh
```

Deja la línea base en `descubrimiento/*.json`. Si algún nombre real difiere de `scripts/config.sh`, cambiarlo ahí (y la cuenta ADLS también en `adf/linkedService/ls_adls_lake.json`). La línea base del 2026-09-21 confirmó: suscripción *Azure for Students*, región `westus`, cuenta `messyopsdl2026`.

## Fase 2 — Aprovisionamiento (idempotente)

```bash
./scripts/01_aprovisionar.sh
# si el workspace de Synapse no existe todavía:
SYNAPSE_SQL_ADMIN_PWD='...' ./scripts/01_aprovisionar.sh
```

El script crea lo que falte y no toca lo que ya existe:

- ADLS Gen2 con los contenedores `bronze`, `silver` y `gold`.
- ADF con identidad administrada.
- Synapse: usa el workspace `messyops-synapse`, que ya existe. **No crea el pool dedicado**, salvo con `CREAR_POOL_DEDICADO=si`; en ese caso lo deja pausado.
- Reglas de firewall para servicios de Azure y para la IP de la consola.
- Administrador Microsoft Entra en SQL y en Synapse.
- Permisos RBAC de ADF y Synapse sobre el lago.

Comprobación: el paso 7 del script debe decir que el OLTP es compatible con CDC. `GP_S_Gen5_2` (vCore serverless) lo es.

Si `00_verificar_entorno.sh` indica que la cuenta no es ADLS Gen2, el script la migra en sitio solo si se confirma con `MIGRAR_HNS=si ./scripts/01_aprovisionar.sh`. La migración es irreversible.

**Motor de Synapse.** Bronze se despliega por defecto en el pool **serverless Built-in** de `messyops-synapse` (`DW_MODO=serverless` en `scripts/config.sh`), en una base `MessyOpsDW` que el script crea allí. No se cobra por hora, solo por datos leídos. Con `DW_MODO=dedicado` el mismo SQL se despliega en un pool dedicado.

> Ojo: en `messyops-server` también existe una Azure SQL Database llamada `MessyOpsDW`. No es Synapse y ningún script la usa.

## Fase 3 — CDC en el OLTP y Bronze en Synapse

```bash
./scripts/02_desplegar_sql.sh oltp
MASTER_KEY_PWD='...' ./scripts/02_desplegar_sql.sh bronze
```

- `oltp` ejecuta `sql/02_cdc_setup.sql`: CDC en las 16 tablas, retención de 7 días y el usuario de la identidad de ADF con `db_datareader`. La última consulta debe devolver 16 instancias de captura.
- `bronze` crea la base `MessyOpsDW` en Synapse serverless si hace falta, y ejecuta `sql/00_bronze_external.sql` (16 tablas externas nativas) y `sql/03_bronze_monitoreo.sql` (`meta.vw_bronze_frescura`). Con el lago todavía vacío, las consultas sobre `bronze.*` devuelven 0 filas o un error de "no se encontraron archivos": es lo esperado.

## Fase 4 — Captura CDC nativa de ADF

```bash
./scripts/03_desplegar_adf_cdc.sh desplegar   # linked services + recurso cdc_oltp_bronze (detenido)
./scripts/03_desplegar_adf_cdc.sh iniciar     # instantánea inicial + cambios cada 15 min
./scripts/03_desplegar_adf_cdc.sh estado      # debe responder Running
```

Tras el primer microlote (la instantánea inicial puede tardar varios minutos):

```bash
./scripts/02_desplegar_sql.sh validar
```

Criterios de aceptación de Bronze:

- **B1** (`sql/05_validar_bronze.sql`): 16 tablas externas y la vista de frescura.
- **B2:** todas las entidades en `OK`, es decir, las claves de Bronze son iguales o más que las filas del OLTP.
- **`meta.vw_bronze_frescura`:** ninguna entidad en `REVISAR` mientras haya actividad en el OLTP.
- **Prueba de cambios:** insertar, actualizar y borrar una fila de prueba en `dbo.warehouses`. En el siguiente microlote deben aparecer en `bronze.warehouses` con `cdc_operation` = `I`, `U` y `D`.

Si se edita el recurso desde ADF Studio, traer la versión viva al repositorio con `./scripts/03_desplegar_adf_cdc.sh exportar`.

## Fase 5 — dbt (Silver adaptado a CDC nativo)

```bash
cd dbt
cp profiles.example.yml ~/.dbt/profiles.yml
export AZURE_TENANT_ID=...  AZURE_CLIENT_ID=...  AZURE_CLIENT_SECRET=...
dbt deps && dbt debug
dbt source freshness            # Bronze: ya funciona con el nuevo contrato
```

El `dbt build` de Silver y Gold ya está completamente adaptado. La ejecución de dbt se realiza mediante **Azure Batch**, clonando el código fuente de este repositorio directamente desde GitHub en cada ejecución, por lo que ya no es necesario compilar imágenes Docker en ACR.

## Fase 6 — Orquestación dbt

Publicar `adf/pipeline/pl_10_ejecutar_dbt.json`, `pl_99_maestro_medallion.json` y el trigger `tr_microlote_15min`, que ahora corre cada 15 minutos y arranca detenido. El maestro ya no incluye Bronze.

## Reversión

```bash
./scripts/03_desplegar_adf_cdc.sh detener
```

Con *Azure for Students* conviene detener el recurso CDC al terminar cada sesión de trabajo. Mientras corre, consume cómputo de flujo de datos y además mantiene despierto el OLTP serverless, que no se autopausa.

Mientras el recurso esté detenido menos de 7 días (la retención), al reiniciarlo continúa desde su checkpoint sin perder cambios. Para deshabilitar el CDC en el OLTP: `EXEC sys.sp_cdc_disable_table ...` por tabla y luego `EXEC sys.sp_cdc_disable_db;`.
