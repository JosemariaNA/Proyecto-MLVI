#!/usr/bin/env bash
# Verificacion de SOLO LECTURA del grupo de recursos. No crea ni modifica nada.
# Deja la linea base en descubrimiento/*.json (versionable).
#
# Uso:  ./scripts/00_verificar_entorno.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

mkdir -p descubrimiento

log "Cuenta y suscripcion"
az account show --query "{name:name, id:id, tenantId:tenantId}" -o json | tee descubrimiento/00_cuenta.json

log "Recursos en $RG"
az resource list --resource-group "$RG" \
   --query "[].{nombre:name, tipo:type, region:location}" -o json > descubrimiento/01_recursos.json
az resource list --resource-group "$RG" --query "[].{Nombre:name, Tipo:type, Region:location}" -o table

log "Servidor SQL y bases"
az sql db list --server "$SQL_SERVER" --resource-group "$RG" \
   --query "[].{nombre:name, sku:currentServiceObjectiveName, estado:status}" -o json > descubrimiento/02_sql_bases.json
cat descubrimiento/02_sql_bases.json

log "Firewall del servidor SQL (debe existir AllowAllWindowsAzureIps)"
az sql server firewall-rule list --server "$SQL_SERVER" --resource-group "$RG" -o json > descubrimiento/03_sql_firewall.json
az sql server firewall-rule list --server "$SQL_SERVER" --resource-group "$RG" -o table

log "Administrador Microsoft Entra del servidor SQL (necesario para usuarios de identidad administrada)"
az sql server ad-admin list --server "$SQL_SERVER" --resource-group "$RG" -o table || true

log "Cuentas de almacenamiento (ADLS Gen2 = espacio de nombres jerarquico activo)"
az storage account list --resource-group "$RG" \
   --query "[].{Nombre:name, ADLSGen2:to_string(isHnsEnabled), Region:location}" -o table
if ! az storage account show -n "$STORAGE_ACCOUNT" -g "$RG" >/dev/null 2>&1; then
  warn "No existe la cuenta '$STORAGE_ACCOUNT' configurada en scripts/config.sh."
elif [ "$(az storage account show -n "$STORAGE_ACCOUNT" -g "$RG" --query isHnsEnabled -o tsv)" != "true" ]; then
  warn "'$STORAGE_ACCOUNT' NO es ADLS Gen2 (isHnsEnabled vacio/false). 01_aprovisionar.sh puede migrarla."
else
  echo "'$STORAGE_ACCOUNT' es ADLS Gen2."
fi

log "Data Factory"
az datafactory show --name "$ADF_NAME" --resource-group "$RG" \
   --query "{Nombre:name, MI:identity.principalId}" -o table || warn "No existe $ADF_NAME"

log "Synapse"
az synapse workspace show --name "$SYNAPSE_WS" --resource-group "$RG" \
   --query "{Nombre:name, MI:identity.principalId}" -o table || warn "No existe $SYNAPSE_WS"
echo "Pools SQL dedicados del workspace:"
az synapse sql pool list --workspace-name "$SYNAPSE_WS" --resource-group "$RG" \
   --query "[].{Nombre:name, SKU:sku.name, Estado:status}" -o table
echo "Pools de Spark del workspace:"
az synapse spark pool list --workspace-name "$SYNAPSE_WS" --resource-group "$RG" \
   --query "[].{Nombre:name, Nodos:nodeSize, Autopausa:autoPause.enabled}" -o table
echo "Pool SQL serverless (Built-in): siempre disponible en ${SYNAPSE_WS}-ondemand.sql.azuresynapse.net"

log "Azure Container Registry (imagen del ejecutor dbt)"
az acr list --resource-group "$RG" --query "[].{Nombre:name, SKU:sku.name}" -o table

echo
echo "Verificacion completada. Ningun recurso fue creado ni modificado."
