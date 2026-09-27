# Runbook de Despliegue en la Nube (Portal/Cloud Shell)

Este runbook describe cómo desplegar el Data Warehouse si no tienes acceso a una terminal local con Azure CLI o dependencias instaladas, usando **Azure Cloud Shell** directamente desde el portal.

## Fase 1 — Preparar Azure Cloud Shell

1. Ingresa a [portal.azure.com](https://portal.azure.com) y abre **Cloud Shell** (el ícono `>_` en la barra superior).
2. Selecciona **Bash**.
3. Clona tu repositorio directamente en el entorno de la nube:
   ```bash
   git clone https://github.com/JosemariaNA/Proyecto-MLVI.git
   cd Proyecto-MLVI
   ```

## Fase 2 — Aprovisionamiento e Infraestructura
Cloud Shell ya viene con `az cli`, `jq` y `sqlcmd` preinstalados. Ejecuta los scripts de configuración:

```bash
# Dar permisos de ejecución
chmod +x scripts/*.sh

# Verificación de entorno y cuenta
./scripts/00_verificar_entorno.sh

# Aprovisionar recursos básicos (ADLS, ADF, Synapse)
# Te pedirá que asignes una clave para el Admin de SQL:
SYNAPSE_SQL_ADMIN_PWD='TuPasswordFuerte123' ./scripts/01_aprovisionar.sh
```

## Fase 3 — Configurar CDC y Tablas Externas
Las utilidades de base de datos se conectarán directamente dentro de la red de Azure.

```bash
# Activar CDC en el origen
./scripts/02_desplegar_sql.sh oltp

# Desplegar tablas de Bronze en Synapse
MASTER_KEY_PWD='TuPasswordFuerte123' ./scripts/02_desplegar_sql.sh bronze
```

## Fase 4 — Publicar Componentes en Data Factory

Si tu ADF está vinculado a GitHub:
1. Abre **Azure Data Factory Studio**.
2. Asegúrate de estar en tu rama principal (`main`).
3. El recurso CDC (`cdc_oltp_bronze`) y los pipelines (`pl_99_maestro_medallion`, `pl_10_ejecutar_dbt`) aparecerán automáticamente.
4. Presiona **Publish** (Publicar) en la barra superior para guardar los cambios en vivo en el servicio.

Para arrancar la captura:
```bash
./scripts/03_desplegar_adf_cdc.sh iniciar
```

## Fase 5 — Despliegue de dbt (Azure Batch)

Dado que la orquestación llama a **Azure Batch** y el script allí clona automáticamente el repositorio de GitHub al vuelo, no tienes que hacer un despliegue de dbt manual, a menos que quieras configurar la base de datos de Batch por primera vez:

1. Asegúrate de que el pool de Azure Batch esté creado y activo.
2. Comprueba que el Linked Service `MessyBatch` en ADF tiene las credenciales correctas hacia tu cuenta de Batch.

## Fase 6 — Activación del Maestro

En **Azure Data Factory Studio**:
1. Ve a **Manage** -> **Triggers**.
2. Selecciona el trigger `tr_microlote_15min` y dale a **Start** (Activar).
3. Publica los cambios. Tu Data Warehouse ahora está operando en tiempo real.
