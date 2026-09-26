#!/usr/bin/env bash
# Diagnostico SOLO LECTURA del paso 6 (RBAC) de 01_aprovisionar.sh.
# No crea, modifica ni elimina nada. Cada comprobacion imprime OK / FALLA.
#
# Uso (desde la raiz del repo, en Git Bash):  bash scripts/diag_rbac.sh
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh
set +e

ok()    { printf '  \033[32mOK\033[0m    %s\n' "$*"; }
falla() { printf '  \033[31mFALLA\033[0m %s\n' "$*"; FALLAS=$((FALLAS+1)); }
FALLAS=0
GUID_RE='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'

log "Entorno de la consola"
echo "  MSYS_NO_PATHCONV=${MSYS_NO_PATHCONV:-<no definido>}  (debe ser 1 en Git Bash)"
echo "  az: $(command az version --query '\"azure-cli\"' -o tsv 2>/dev/null | tr -d '\r')"

log "1-3. Suscripcion y tenant activos (az account show)"
SUB=$(az account show --query id -o tsv); TEN=$(az account show --query tenantId -o tsv)
NOM=$(az account show --query name -o tsv); USR=$(az account show --query user.name -o tsv)
echo "  $NOM | $SUB | tenant $TEN | usuario $USR"
[ "$SUB" = "$SUBSCRIPTION_ID" ] && ok "suscripcion = $SUBSCRIPTION_ID" || falla "suscripcion activa $SUB (esperada $SUBSCRIPTION_ID)"
[ "$TEN" = "$TENANT_ID" ]       && ok "tenant = $TENANT_ID"             || falla "tenant activo $TEN (esperado $TENANT_ID)"

log "10. Suscripciones visibles para az (la marcada con True es la predeterminada)"
az account list --query "[].{nombre:name, id:id, tenant:tenantId, predeterminada:isDefault}" -o table

log "4. El grupo de recursos pertenece a la suscripcion"
RG_ID=$(az group show -n "$RG" --subscription "$SUBSCRIPTION_ID" --query id -o tsv 2>/dev/null)
[ "$RG_ID" = "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG" ] && ok "$RG_ID" || falla "no se encontro $RG en $SUBSCRIPTION_ID (leido: '${RG_ID}')"

log "5. STORAGE_ID"
STORAGE_ID=$(az storage account show -n "$STORAGE_ACCOUNT" -g "$RG" --subscription "$SUBSCRIPTION_ID" --query id -o tsv 2>/dev/null)
ESPERADO="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT"
echo "  $STORAGE_ID"
[ -n "$STORAGE_ID" ] && [ "${STORAGE_ID,,}" = "${ESPERADO,,}" ] && ok "formato correcto" || falla "esperado $ESPERADO"
printf '  bytes finales: '; printf '%s' "$STORAGE_ID" | tail -c 3 | od -c | head -1   # detecta \r residual

log "6-7. principalId de las identidades administradas"
ADF_MI=$(az datafactory show -n "$ADF_NAME" -g "$RG" --subscription "$SUBSCRIPTION_ID" --query identity.principalId -o tsv 2>/dev/null)
SYN_MI=$(az synapse workspace show -n "$SYNAPSE_WS" -g "$RG" --subscription "$SUBSCRIPTION_ID" --query identity.principalId -o tsv 2>/dev/null)
[[ "$ADF_MI" =~ $GUID_RE ]] && ok "ADF_MI = $ADF_MI" || falla "ADF_MI invalido: '$ADF_MI'"
[[ "$SYN_MI" =~ $GUID_RE ]] && ok "SYN_MI = $SYN_MI" || falla "SYN_MI invalido: '$SYN_MI'"
# Consultar Entra ID (Graph) requiere permisos de directorio que un usuario
# invitado (#EXT#) del tenant de estudiante no tiene: es solo informativo.
for P in "$ADF_MI" "$SYN_MI"; do
  if az ad sp show --id "$P" --query displayName -o tsv >/dev/null 2>&1; then
    ok "$P existe en Entra ID"
  else
    echo "  INFO  $P: Graph no consultable con tu usuario invitado (no afecta al RBAC)"
  fi
done

log "8. Permiso de tu usuario para crear asignaciones de rol"
YO=$(az ad signed-in-user show --query id -o tsv 2>/dev/null)
ROLES=$(az role assignment list --assignee "$YO" --all --include-inherited --subscription "$SUBSCRIPTION_ID" \
          --query "[?contains(scope, '$SUBSCRIPTION_ID')].roleDefinitionName" -o tsv 2>/dev/null | sort -u | tr '\n' ',')
echo "  roles: ${ROLES:-<ninguno visible>}"
case ",$ROLES" in
  *,Owner,*|*,"User Access Administrator",*|*,"Role Based Access Control Administrator",*) ok "puede crear asignaciones de rol" ;;
  *) falla "sin Owner / User Access Administrator: az role assignment create fallara con AuthorizationFailed" ;;
esac

log "9. Provider Microsoft.Authorization"
EST=$(az provider show -n Microsoft.Authorization --subscription "$SUBSCRIPTION_ID" --query registrationState -o tsv 2>/dev/null)
[ "$EST" = "Registered" ] && ok "Registered" || falla "estado: '$EST'"

log "Asignaciones actuales sobre el lago"
az role assignment list --scope "$STORAGE_ID" --subscription "$SUBSCRIPTION_ID" \
   --query "[].{principal:principalId, rol:roleDefinitionName, ambito:scope}" -o table 2>/dev/null
for P in "$ADF_MI" "$SYN_MI"; do
  N=$(az role assignment list --role "Storage Blob Data Contributor" --scope "$STORAGE_ID" --subscription "$SUBSCRIPTION_ID" \
        --query "length([?principalId=='$P'])" -o tsv 2>/dev/null)
  [ "${N:-0}" -gt 0 ] && ok "$P tiene Storage Blob Data Contributor sobre el lago" \
                      || falla "$P sin Storage Blob Data Contributor sobre el lago"
done

echo
[ "$FALLAS" -eq 0 ] && echo "Diagnostico sin fallas: 01_aprovisionar.sh deberia pasar el paso 6." \
                    || echo "$FALLAS comprobacion(es) fallaron: revisar arriba."
