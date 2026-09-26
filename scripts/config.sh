#!/usr/bin/env bash
# Configuracion comun de los scripts de aprovisionamiento y despliegue.
# Sin secretos: cualquier valor se puede sobrescribir con una variable de
# entorno antes de ejecutar (p. ej.  STORAGE_ACCOUNT=otro ./scripts/01_aprovisionar.sh).
#
# Valores confirmados con ./scripts/00_verificar_entorno.sh (2026-09-21):
# suscripcion "Azure for Students" 4ddbce0d-..., todo en westus.

export RG="${RG:-AzureDW}"
export LOCATION="${LOCATION:-westus}"

export SQL_SERVER="${SQL_SERVER:-messyops-server}"
export OLTP_DB="${OLTP_DB:-MessyOpsOLTP}"

export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-messyopsdl2026}"
export CONTENEDORES="${CONTENEDORES:-bronze silver gold}"

export ADF_NAME="${ADF_NAME:-messyops-adf}"
export CDC_NAME="${CDC_NAME:-cdc_oltp_bronze}"

export SYNAPSE_WS="${SYNAPSE_WS:-messyops-synapse}"
# Motor SQL de Synapse para el DW:
#   serverless -> pool Built-in del workspace (ya existe, pago por TB leido).
#                 Es el valor por defecto: Bronze solo necesita tablas externas.
#   dedicado   -> pool dedicado SYNAPSE_POOL (hay que crearlo con
#                 CREAR_POOL_DEDICADO=si ./scripts/01_aprovisionar.sh; se cobra
#                 por hora mientras este encendido).
export DW_MODO="${DW_MODO:-serverless}"
export SYNAPSE_POOL="${SYNAPSE_POOL:-MessyOpsDW}"   # base de datos del DW en ambos modos
export SYNAPSE_SKU="${SYNAPSE_SKU:-DW100c}"
if [ "$DW_MODO" = "dedicado" ]; then
  export DW_HOST="tcp:${SYNAPSE_WS}.sql.azuresynapse.net,1433"
else
  export DW_HOST="tcp:${SYNAPSE_WS}-ondemand.sql.azuresynapse.net,1433"
fi

# Git Bash convierte los argumentos que empiezan con "/" en rutas de Windows
# ("/subscriptions/..." -> "C:/Program Files/Git/subscriptions/..."), lo que
# rompe los --scope de "az role assignment" (error MissingSubscription).
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

# En Windows (Git Bash) az devuelve fin de linea CRLF: "true\r" no es igual a
# "true" y todas las comparaciones fallan (p. ej. isHnsEnabled). Este envoltorio
# quita el \r de toda salida de az. Con pipefail se conserva su codigo de salida.
set -o pipefail
az() { command az "$@" | tr -d '\r'; }
jq() { command jq "$@" | tr -d '\r'; }

# Instalar extensiones de az (datafactory) sin preguntar: en modo no
# interactivo la pregunta (Y/n) se responde sola con "no" y el comando falla.
export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=yes_without_prompt
az extension show --name datafactory >/dev/null 2>&1 \
  || az extension add --name datafactory --only-show-errors >/dev/null

# Suscripcion y tenant del proyecto: explicitos, no "la que este por defecto"
# en az. fijar_suscripcion() la activa y verifica antes de tocar nada.
export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-4ddbce0d-5c26-4d5c-88ec-f8c439b0caf5}"   # Azure for Students
export TENANT_ID="${TENANT_ID:-29b04522-efb6-422d-8d80-d86a2967b572}"

fijar_suscripcion() {
  az account set --subscription "$SUBSCRIPTION_ID" \
    || fail "No se pudo activar la suscripcion $SUBSCRIPTION_ID. Ejecutar: az login --tenant $TENANT_ID"
  local sub ten
  sub=$(az account show --query id -o tsv)
  ten=$(az account show --query tenantId -o tsv)
  [ "$sub" = "$SUBSCRIPTION_ID" ] || fail "Suscripcion activa '$sub' distinta de $SUBSCRIPTION_ID"
  [ "$ten" = "$TENANT_ID" ]       || fail "Tenant activo '$ten' distinto de $TENANT_ID. Ejecutar: az login --tenant $TENANT_ID"
  echo "Suscripcion: $(az account show --query name -o tsv) ($sub) | tenant $ten"
}

export ADF_API="2018-06-01"
export ADF_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG}/providers/Microsoft.DataFactory/factories/${ADF_NAME}"

# ADLS Gen2 = espacio de nombres jerarquico (isHnsEnabled). Ojo: "az -o tsv"
# imprime los booleanos como "True"/"False" (con mayuscula), por eso se usa
# -o json y se normaliza. Deja el valor leido en HNS_VALOR para los mensajes.
es_adls_gen2() {
  HNS_VALOR=$(az storage account show -n "$STORAGE_ACCOUNT" -g "$RG" --query isHnsEnabled -o json 2>/dev/null \
              | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
  [ "$HNS_VALOR" = "true" ]
}

log()  { printf '\n\033[1;32m== %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$*" >&2; }
fail() { printf '\033[1;31mXX %s\033[0m\n' "$*" >&2; exit 1; }
