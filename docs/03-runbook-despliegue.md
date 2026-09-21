# Runbook de despliegue

Cada paso indica dónde se ejecuta y cómo comprobar que salió bien. El CDC está apagado a propósito y se enciende en la fase 5, cuando todo lo demás ya está probado.

## Fase 0 — Requisitos previos

- Azure CLI con sesión iniciada (`az login`) y la suscripción correcta seleccionada.
- Verificar que el workspace `messyops-synapse` y el pool SQL `MessyOpsDW` estén disponibles.

## Fase 1 — Verificación (sin coste)

```bash
./scripts/00_verificar_entorno.sh
```

Debe listar los cinco recursos de la guía. Guardar la salida como línea base.

## Fase 2 — Objetos SQL en Synapse

En Synapse Studio, conectado al pool `MessyOpsDW`, en este orden:

1. `sql/01_meta_control.sql` — esquemas y tablas de control.
2. `sql/03_cdc_control.sql` — control de LSN de Bronze (todas las entidades quedan con `activo = 0`).
3. `sql/00_bronze_external.sql` — tablas externas Bronze sobre el contenedor ADLS.

Comprobación: la primera consulta de `sql/04_validaciones.sql` (V1) debe listar los cinco esquemas, las tablas `meta` y las 16 tablas externas `bronze`.

## Fase 3 — dbt

```bash
cd dbt
cp profiles.example.yml ~/.dbt/profiles.yml
export AZURE_TENANT_ID=...  AZURE_CLIENT_ID=...  AZURE_CLIENT_SECRET=...
dbt deps
dbt debug                       # valida conexión
dbt build --select path:models/silver
dbt snapshot
dbt build --select path:models/gold
dbt docs generate
```

Con Bronze todavía vacío, los modelos se crean sin filas y los tests pasan en vacío: eso confirma que la estructura compila contra el motor real. Para la imagen del ejecutor:

```bash
az acr build --registry <acr> --image azuredw-dbt:latest -f scripts/Dockerfile .
```

## Fase 4 — ADF (trigger detenido)

Conectar messyops-adf al repositorio Git y publicar la carpeta `adf/`. El trigger se publica inicialmente con `runtimeState: Stopped`.

Prueba en seco: lanzar `pl_00_ingesta_cdc_bronze` a mano. Con todas las entidades en `activo = 0`, debe terminar en segundos sin copiar nada.

## Fase 5 — Encender el CDC y la carga (al final)

1. En **MessyOpsOLTP**: ejecutar `sql/02_cdc_setup.sql`. El paso 0 es solo lectura; revisarlo antes de seguir.
2. En **MessyOpsDW**: `EXEC meta.sp_activar_ingesta_cdc;`
3. Lanzar `pl_99_maestro_medallion` a mano una vez y revisar el resultado.
4. Si todo cuadra, arrancar `tr_microlote_5min`.

## Fase 6 — Validación posterior

Ejecutar `sql/04_validaciones.sql` completo. Criterios de aceptación: V3 y V4 sin descuadres, V5 sin huérfanos, V6 sin filas, y ninguna entidad con más de 30 minutos de retraso en V2.

## Reversión

- Detener el trigger `tr_microlote_5min`.
- `UPDATE meta.cdc_control SET activo = 0;`
- Para deshabilitar el CDC en el OLTP: `EXEC sys.sp_cdc_disable_table ...` por tabla, y `EXEC sys.sp_cdc_disable_db;`.
