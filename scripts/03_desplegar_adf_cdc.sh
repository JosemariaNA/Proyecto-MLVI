#!/usr/bin/env bash
# Despliegue por CLI de la captura CDC nativa de ADF (capa Bronze).
#
# Uso (desde la raiz del repo, en Git Bash):
#   bash scripts/03_desplegar_adf_cdc.sh desplegar   # linked services + recurso CDC (queda detenido)
#   bash scripts/03_desplegar_adf_cdc.sh recrear     # borra cdc_oltp_bronze y lo crea de nuevo
#   bash scripts/03_desplegar_adf_cdc.sh iniciar     # arranca la captura (instantanea inicial + cambios)
#   bash scripts/03_desplegar_adf_cdc.sh estado      # Running / Stopped
#   bash scripts/03_desplegar_adf_cdc.sh detener
#   bash scripts/03_desplegar_adf_cdc.sh exportar    # trae la definicion viva al repo (tras editarla en Studio)
#
# El recurso CDC no tiene comando propio en az datafactory, asi que se usa
# la API REST de ARM con "az rest" (misma autenticacion que az login).
# Solo necesita az: no depende de jq ni de python (Git Bash no los trae).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh
fijar_suscripcion >/dev/null

CDC_FILE="adf/adfcdc/${CDC_NAME}.json"
CDC_URL="https://management.azure.com${ADF_ID}/adfcdcs/${CDC_NAME}"
[ -f "$CDC_FILE" ] || fail "No existe $CDC_FILE (generarlo con: python scripts/generar_bronze.py)"

# Carpeta temporal DENTRO del repo y con ruta relativa: en Windows, az (Python
# nativo) no entiende rutas /tmp/... de Git Bash en los argumentos @archivo.
TMP=".tmp_despliegue"; mkdir -p "$TMP"; trap 'rm -rf "$TMP"' EXIT

estado() {
  az rest --method get --url "${CDC_URL}/status?api-version=${ADF_API}" -o tsv 2>/dev/null || echo "NoExiste"
}

# Estados vistos: Stopped, Started, PipelineRunCreated, Running, Stopping...
# Solo se puede actualizar en "Stopped", y el stop es asincrono: se espera.
detener_y_esperar() {
  local e i
  e=$(estado)
  [ "$e" = "Stopped" ] || [ "$e" = "NoExiste" ] && return 0
  echo "  estado actual: $e -> deteniendo..."
  az rest --method post --url "${CDC_URL}/stop?api-version=${ADF_API}" -o none 2>/dev/null || true
  for i in $(seq 1 30); do
    e=$(estado)
    [ "$e" = "Stopped" ] && { echo "  detenido."; return 0; }
    sleep 10
  done
  fail "El recurso sigue en '$e' despues de 5 min. Revisar en ADF Studio > Supervisar."
}

# ---------------------------------------------------------------------------
# Linked services del proyecto: ls_oltp_messyops (origen) y ls_adls_lake
# (destino). Ambos con la identidad administrada del ADF, sin contrasenas.
# Formato: el mismo que usa ADF Studio para las conexiones de CDC
# (connectionString para Azure SQL, url para ADLS Gen2). El formato nuevo
# "version 2.0" de Azure SQL no se usa: el recurso CDC puede no reconocerlo.
# ---------------------------------------------------------------------------
desplegar_linked_services() {
  cat > "$TMP/ls_oltp_messyops.json" <<EOF
{
  "type": "AzureSqlDatabase",
  "description": "Origen MessyOpsOLTP con CDC nativo. Identidad administrada del ADF (usuario creado por sql/02_cdc_setup.sql).",
  "annotations": ["bronze", "origen"],
  "typeProperties": {
    "connectionString": "Integrated Security=False;Encrypt=True;Connection Timeout=30;Data Source=${SQL_SERVER}.database.windows.net;Initial Catalog=${OLTP_DB}"
  }
}
EOF
  cat > "$TMP/ls_adls_lake.json" <<EOF
{
  "type": "AzureBlobFS",
  "description": "Lago ADLS Gen2 de las capas medallion. Identidad administrada del ADF.",
  "annotations": ["bronze", "silver", "gold"],
  "typeProperties": { "url": "https://${STORAGE_ACCOUNT}.dfs.core.windows.net/" }
}
EOF
  local ls
  for ls in ls_oltp_messyops ls_adls_lake; do
    az datafactory linked-service create --factory-name "$ADF_NAME" -g "$RG" \
       --linked-service-name "$ls" --properties @"$TMP/${ls}.json" -o none
    az datafactory linked-service show --factory-name "$ADF_NAME" -g "$RG" --name "$ls" \
       --query "{name: name, properties: properties}" -o json > "adf/linkedService/${ls}.json"
    echo "  $ls (identidad administrada, versionado en adf/linkedService/)"
  done
}

case "${1:-}" in
  desplegar)
    # Regenerar solo si hay python; si no, se usa el JSON versionado en el repo.
    PY=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || command -v py 2>/dev/null || true)
    if [ -n "$PY" ] && "$PY" --version >/dev/null 2>&1; then
      log "Regenerando Bronze desde EstructuraOLTP.sql"
      "$PY" scripts/generar_bronze.py
    fi

    log "Linked services del proyecto"
    desplegar_linked_services

    log "Recurso CDC $CDC_NAME"
    detener_y_esperar
    # El archivo tiene el formato Git de ADF ({name, properties}); ARM acepta el
    # campo name en el cuerpo del PUT, asi que se envia tal cual.
    cp "$CDC_FILE" "$TMP/cdc.json"
    az rest --method put --url "${CDC_URL}?api-version=${ADF_API}" \
       --headers "Content-Type=application/json" --body @"$TMP/cdc.json" -o none
    N=$(grep -c '"enableNativeCdc"' "$CDC_FILE" || true)
    echo "  publicado ($N tablas, estado: $(estado))"
    echo "Siguiente paso: bash scripts/03_desplegar_adf_cdc.sh iniciar"
    ;;
  recrear)
    # Borra SOLO el recurso CDC del proyecto (cdc_oltp_bronze) y lo vuelve a
    # crear desde cero. Azure reutiliza el pipeline interno generado la primera
    # vez (mismo "SystemPipeline_..." en todos los errores), asi que las
    # correcciones publicadas despues pueden no llegar a ejecutarse.
    # No toca datos, conexiones ni el recurso CDCMessyOpsOLTPBronze.
    detener_y_esperar
    if [ "$(estado)" != "NoExiste" ]; then
      az rest --method delete --url "${CDC_URL}?api-version=${ADF_API}" -o none
      echo "  $CDC_NAME eliminado."
    fi
    exec bash "$0" desplegar
    ;;
  iniciar)
    E=$(estado)
    if [ "$E" != "Stopped" ]; then
      echo "Ya esta en marcha (estado: $E). Para reiniciarlo: detener e iniciar."; exit 0
    fi
    az rest --method post --url "${CDC_URL}/start?api-version=${ADF_API}" -o none
    echo "Estado: $(estado). La primera ejecucion hace la instantanea inicial (varios minutos)."
    echo "Revisar con:  bash scripts/03_desplegar_adf_cdc.sh estado"
    echo "y en Synapse: bash scripts/02_desplegar_sql.sh validar"
    ;;
  detener)
    detener_y_esperar
    echo "Estado: $(estado)"
    ;;
  estado)
    estado
    ;;
  exportar)
    az rest --method get --url "${CDC_URL}?api-version=${ADF_API}" \
       --query "{name: name, properties: properties}" -o json > "$CDC_FILE"
    echo "Definicion viva guardada en $CDC_FILE (revisar el diff y versionarla)."
    ;;
  *)
    echo "Uso: $0 {desplegar|recrear|iniciar|estado|detener|exportar}"; exit 2 ;;
esac
