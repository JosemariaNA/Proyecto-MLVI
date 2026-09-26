#!/usr/bin/env bash
# Aprovisionamiento por CLI de todo lo necesario hasta la capa Bronze.
# Idempotente: si un recurso ya existe, lo deja como esta y sigue.
#
#   - ADLS Gen2 (HNS) con contenedores bronze / silver / gold
#   - Data Factory con identidad administrada
#   - Synapse workspace (si no existe); pool dedicado solo con CREAR_POOL_DEDICADO=si
#   - Reglas de firewall "Allow Azure services" en SQL y Synapse
#   - Administrador Microsoft Entra en SQL y Synapse (necesario para crear
#     usuarios de identidades administradas; se usa el usuario de az login)
#   - Permisos RBAC sobre el lago para ADF y Synapse
#
# Uso:
#   az login && az account set -s <suscripcion>
#   SYNAPSE_SQL_ADMIN_PWD='...' ./scripts/01_aprovisionar.sh
#   (la contrasena solo se usa si hay que CREAR el workspace de Synapse)
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

az extension add --name datafactory --upgrade --only-show-errors >/dev/null 2>&1 || true

log "0. Suscripcion"
fijar_suscripcion
az group show -n "$RG" --subscription "$SUBSCRIPTION_ID" >/dev/null \
  || fail "El grupo de recursos $RG no existe en la suscripcion $SUBSCRIPTION_ID"

YO_ID=$(az ad signed-in-user show --query id -o tsv)
YO_UPN=$(az ad signed-in-user show --query userPrincipalName -o tsv)

# --------------------------------------------------------------------------
log "1. Lago ADLS Gen2: $STORAGE_ACCOUNT"
if ! az storage account show -n "$STORAGE_ACCOUNT" -g "$RG" >/dev/null 2>&1; then
  az storage account create -n "$STORAGE_ACCOUNT" -g "$RG" -l "$LOCATION" \
     --sku Standard_LRS --kind StorageV2 --hns true \
     --min-tls-version TLS1_2 --allow-blob-public-access false -o none
  echo "Creada."
elif es_adls_gen2; then
  echo "Ya existe (ADLS Gen2)."
else
  # La cuenta existe pero es Blob Storage plano. Se migra en sitio a ADLS Gen2:
  # conserva nombre y datos, pero es IRREVERSIBLE, por eso pide confirmacion.
  warn "$STORAGE_ACCOUNT existe pero NO es ADLS Gen2 (isHnsEnabled = '${HNS_VALOR:-vacio}')."
  [ "${MIGRAR_HNS:-}" = "si" ] || fail "Para migrarla en sitio ejecutar:  MIGRAR_HNS=si ./scripts/01_aprovisionar.sh"
  echo "Validando la migracion (revisa compatibilidad: soft delete, versionado, etc.)..."
  az storage account hns-migration start --type validation -n "$STORAGE_ACCOUNT" -g "$RG"
  echo "Migrando a ADLS Gen2 (puede tardar varios minutos)..."
  az storage account hns-migration start --type upgrade -n "$STORAGE_ACCOUNT" -g "$RG"
  es_adls_gen2 \
    || fail "La migracion no termino; revisar con: az storage account show -n $STORAGE_ACCOUNT --query isHnsEnabled"
  echo "Migrada a ADLS Gen2."
fi
STORAGE_ID=$(az storage account show -n "$STORAGE_ACCOUNT" -g "$RG" --query id -o tsv)
# Clave de cuenta solo para crear contenedores sin esperar la propagacion de RBAC.
STORAGE_KEY=$(az storage account keys list -n "$STORAGE_ACCOUNT" -g "$RG" --query "[0].value" -o tsv)
for c in $CONTENEDORES; do
  az storage fs create -n "$c" --account-name "$STORAGE_ACCOUNT" --account-key "$STORAGE_KEY" -o none 2>/dev/null \
    && echo "Contenedor $c creado." || echo "Contenedor $c ya existe."
done

# --------------------------------------------------------------------------
log "2. Data Factory: $ADF_NAME"
if ! az datafactory show -n "$ADF_NAME" -g "$RG" >/dev/null 2>&1; then
  az datafactory create -n "$ADF_NAME" -g "$RG" -l "$LOCATION" -o none
  echo "Creado."
else
  echo "Ya existe."
fi
ADF_MI=$(az datafactory show -n "$ADF_NAME" -g "$RG" --query identity.principalId -o tsv)
[ -n "$ADF_MI" ] || fail "El Data Factory no tiene identidad administrada asignada por el sistema."

# --------------------------------------------------------------------------
log "3. Synapse: $SYNAPSE_WS / $SYNAPSE_POOL"
if ! az synapse workspace show -n "$SYNAPSE_WS" -g "$RG" >/dev/null 2>&1; then
  [ -n "${SYNAPSE_SQL_ADMIN_PWD:-}" ] || fail "Hay que crear el workspace: exportar SYNAPSE_SQL_ADMIN_PWD."
  az synapse workspace create -n "$SYNAPSE_WS" -g "$RG" -l "$LOCATION" \
     --storage-account "$STORAGE_ACCOUNT" --file-system gold \
     --sql-admin-login-user sqladminuser --sql-admin-login-password "$SYNAPSE_SQL_ADMIN_PWD" -o none
  echo "Workspace creado."
else
  echo "Workspace ya existe."
fi
if az synapse sql pool show -n "$SYNAPSE_POOL" --workspace-name "$SYNAPSE_WS" -g "$RG" >/dev/null 2>&1; then
  echo "Pool dedicado $SYNAPSE_POOL ya existe (estado: $(az synapse sql pool show -n "$SYNAPSE_POOL" \
       --workspace-name "$SYNAPSE_WS" -g "$RG" --query status -o tsv))."
elif [ "${CREAR_POOL_DEDICADO:-}" = "si" ]; then
  # Se crea y se pausa de inmediato: se cobra por hora mientras este en linea.
  az synapse sql pool create -n "$SYNAPSE_POOL" --workspace-name "$SYNAPSE_WS" -g "$RG" \
     --performance-level "$SYNAPSE_SKU" -o none
  az synapse sql pool pause -n "$SYNAPSE_POOL" --workspace-name "$SYNAPSE_WS" -g "$RG" -o none
  echo "Pool dedicado creado ($SYNAPSE_SKU) y pausado. Usar DW_MODO=dedicado para desplegar en el."
else
  echo "Sin pool dedicado: se usa el pool serverless Built-in (DW_MODO=$DW_MODO)."
  echo "Para crear el dedicado:  CREAR_POOL_DEDICADO=si ./scripts/01_aprovisionar.sh"
fi
SYN_MI=$(az synapse workspace show -n "$SYNAPSE_WS" -g "$RG" --query identity.principalId -o tsv)

# --------------------------------------------------------------------------
log "4. Firewall: acceso desde servicios de Azure (ADF y Synapse)"
az sql server firewall-rule create -s "$SQL_SERVER" -g "$RG" -n AllowAllWindowsAzureIps \
   --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0 -o none
az synapse workspace firewall-rule create --workspace-name "$SYNAPSE_WS" -g "$RG" \
   -n AllowAllWindowsAzureIps --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0 -o none 2>/dev/null \
   || echo "Synapse: la regla AllowAllWindowsAzureIps ya existe."
MI_IP=$(curl -s https://api.ipify.org || true)
if [ -n "$MI_IP" ]; then
  echo "Permitiendo tambien la IP de esta consola ($MI_IP) para sqlcmd."
  az sql server firewall-rule create -s "$SQL_SERVER" -g "$RG" -n consola-cli \
     --start-ip-address "$MI_IP" --end-ip-address "$MI_IP" -o none
  az synapse workspace firewall-rule create --workspace-name "$SYNAPSE_WS" -g "$RG" \
     -n consola-cli --start-ip-address "$MI_IP" --end-ip-address "$MI_IP" -o none 2>/dev/null \
     || az synapse workspace firewall-rule update --workspace-name "$SYNAPSE_WS" -g "$RG" \
          -n consola-cli --start-ip-address "$MI_IP" --end-ip-address "$MI_IP" -o none
fi

# --------------------------------------------------------------------------
log "5. Administrador Microsoft Entra (para CREATE USER ... FROM EXTERNAL PROVIDER)"
if [ -z "$(az sql server ad-admin list -s "$SQL_SERVER" -g "$RG" --query '[0].login' -o tsv)" ]; then
  az sql server ad-admin create -s "$SQL_SERVER" -g "$RG" --display-name "$YO_UPN" --object-id "$YO_ID" -o none
  echo "SQL: administrador Entra = $YO_UPN"
else
  echo "SQL: ya tiene administrador Entra ($(az sql server ad-admin list -s "$SQL_SERVER" -g "$RG" --query '[0].login' -o tsv))."
fi
if [ -z "$(az synapse sql ad-admin show --workspace-name "$SYNAPSE_WS" -g "$RG" --query login -o tsv 2>/dev/null)" ]; then
  az synapse sql ad-admin create --workspace-name "$SYNAPSE_WS" -g "$RG" \
     --display-name "$YO_UPN" --object-id "$YO_ID" -o none
  echo "Synapse: administrador Entra = $YO_UPN"
else
  echo "Synapse: ya tiene administrador Entra."
fi

# --------------------------------------------------------------------------
log "6. RBAC sobre el lago"
GUID_RE='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
SCOPE_ESPERADO="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}"
echo "  STORAGE_ID = ${STORAGE_ID:-<vacio>}"
echo "  ADF_MI     = ${ADF_MI:-<vacio>}"
echo "  SYN_MI     = ${SYN_MI:-<vacio>}"
[ -n "$STORAGE_ID" ] || fail "STORAGE_ID vacio: no se pudo leer la cuenta $STORAGE_ACCOUNT."
# Comparacion sin distinguir mayusculas: ARM puede devolver resourcegroups/resourceGroups.
[ "${STORAGE_ID,,}" = "${SCOPE_ESPERADO,,}" ] \
  || fail "STORAGE_ID con formato inesperado. Esperado: $SCOPE_ESPERADO"
[[ "$ADF_MI" =~ $GUID_RE ]] || fail "ADF_MI no es un principalId valido: '$ADF_MI' (identidad administrada de $ADF_NAME)."
[[ "$SYN_MI" =~ $GUID_RE ]] || fail "SYN_MI no es un principalId valido: '$SYN_MI' (identidad administrada de $SYNAPSE_WS)."
[ "$(az provider show -n Microsoft.Authorization --subscription "$SUBSCRIPTION_ID" --query registrationState -o tsv)" = "Registered" ] \
  || fail "El provider Microsoft.Authorization no esta registrado en $SUBSCRIPTION_ID."

asignar() {  # principal, rol  (idempotente: no duplica una asignacion existente)
  local existe
  # Se filtra por principalId en vez de --assignee: --assignee consulta Microsoft
  # Graph, que un usuario invitado (#EXT#) de la cuenta de estudiante no puede leer.
  existe=$(az role assignment list --role "$2" --scope "$STORAGE_ID" --subscription "$SUBSCRIPTION_ID" \
             --query "length([?principalId=='$1'])" -o tsv)
  if [ "${existe:-0}" -gt 0 ]; then
    echo "  $2 -> $1 (ya existia)"; return 0
  fi
  az role assignment create --assignee-object-id "$1" --assignee-principal-type ServicePrincipal \
     --role "$2" --scope "$STORAGE_ID" --subscription "$SUBSCRIPTION_ID" -o none \
    || fail "No se pudo asignar $2. Tu usuario necesita Owner o User Access Administrator sobre $RG (ver scripts/diag_rbac.sh)."
  echo "  $2 -> $1"
}
# ADF escribe Bronze (recurso CDC).
asignar "$ADF_MI" "Storage Blob Data Contributor"
# Synapse lee Bronze con tablas externas; Contributor porque Silver/Gold
# tambien escribiran en el lago (CETAS).
asignar "$SYN_MI" "Storage Blob Data Contributor"

# --------------------------------------------------------------------------
log "7. Requisito del CDC: nivel de servicio del OLTP"
SLO=$(az sql db show -n "$OLTP_DB" -s "$SQL_SERVER" -g "$RG" --query currentServiceObjectiveName -o tsv)
case "$SLO" in
  Basic|S0|S1|S2) warn "El OLTP esta en $SLO: el CDC de Azure SQL requiere S3 o superior (o vCore)." ;;
  *) echo "OLTP en $SLO: compatible con CDC." ;;
esac

echo
echo "Aprovisionamiento completo. Siguiente paso: ./scripts/02_desplegar_sql.sh oltp"
