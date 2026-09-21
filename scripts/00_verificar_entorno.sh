#!/usr/bin/env bash
# Verificacion de solo lectura del grupo de recursos AzureDW.
# No crea nada: ningun comando de este script genera coste.
set -euo pipefail

RG="${RG:-AzureDW}"
echo "== Recursos en $RG =="
az resource list --resource-group "$RG" \
   --query "[].{Nombre:name, Tipo:type, Region:location}" -o table

echo
echo "== Servidor SQL y base OLTP =="
az sql server show --name messyops-server --resource-group "$RG" \
   --query "{Nombre:name, FQDN:fullyQualifiedDomainName, Admin:administratorLogin}" -o table
az sql db show --name MessyOpsOLTP --server messyops-server --resource-group "$RG" \
   --query "{Nombre:name, SKU:sku.name, Estado:status, MaxGB:maxSizeBytes}" -o table

echo
echo "== Reglas de firewall (debe existir 'Allow Azure services') =="
az sql server firewall-rule list --server messyops-server --resource-group "$RG" -o table

echo
echo "== Data Factory y pipelines existentes =="
az datafactory show --name messyops-adf --resource-group "$RG" \
   --query "{Nombre:name, MI:identity.principalId}" -o table
az datafactory pipeline list --factory-name messyops-adf --resource-group "$RG" -o table || true

echo
echo "Verificacion completada. Ningun recurso fue creado ni modificado."
