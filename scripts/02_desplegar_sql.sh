#!/usr/bin/env bash
# Ejecuta los scripts SQL por consola con go-sqlcmd y autenticacion Microsoft Entra
# (la sesion de az login). Sin portal ni Query Editor.
#
# Uso:
#   ./scripts/02_desplegar_sql.sh oltp      # CDC nativo + usuario de ADF en MessyOpsOLTP
#   MASTER_KEY_PWD='...' ./scripts/02_desplegar_sql.sh bronze
#                                           # tablas externas Bronze + monitoreo en Synapse
#   ./scripts/02_desplegar_sql.sh validar   # validacion de Bronze (sql/05_validar_bronze.sql)
#
# Destino en Synapse segun DW_MODO (config.sh): serverless (por defecto) o dedicado.
#
# Requisito: go-sqlcmd  (winget install sqlcmd | brew install sqlcmd |
#            https://github.com/microsoft/go-sqlcmd/releases)
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

# ---------------------------------------------------------------------------
# sqlcmd: se necesita go-sqlcmd (el moderno). En Windows suele haber tambien
# el sqlcmd ODBC antiguo que instala SQL Server / SSMS, que NO entiende
# --authentication-method y falla siempre. Se busca go-sqlcmd explicitamente.
# Se puede forzar con:  SQLCMD="/c/ruta/a/sqlcmd.exe" bash scripts/02_desplegar_sql.sh ...
# ---------------------------------------------------------------------------
# go-sqlcmd responde a --version con "Version: v1.x" (o "sqlcmd: v1.x" en
# versiones viejas); el sqlcmd ODBC antiguo da error ("'-' or '/' does not have...").
# Se captura la salida primero: con "set -o pipefail", un "grep -q" en tuberia
# corta la lectura, el productor recibe SIGPIPE y la tuberia entera "falla".
es_go_sqlcmd() {
  local v; v=$("$1" --version 2>/dev/null | tr -d '\r' || true)
  grep -qiE '(^version:|^sqlcmd:) *v[0-9]' <<< "$v"
}
if [ -z "${SQLCMD:-}" ]; then
  for c in "/c/Program Files/SqlCmd/sqlcmd.exe" "/c/Program Files (x86)/SqlCmd/sqlcmd.exe" \
           "$LOCALAPPDATA/Microsoft/WinGet/Links/sqlcmd.exe" "$(command -v sqlcmd 2>/dev/null)"; do
    [ -n "$c" ] && [ -x "$c" ] && es_go_sqlcmd "$c" && { SQLCMD="$c"; break; }
  done
fi
[ -n "${SQLCMD:-}" ] || fail "No se encontro go-sqlcmd. Instalar con:  winget install sqlcmd  y abrir una Git Bash nueva.
   (Si 'sqlcmd -?' muestra 'Version 15/16/17', es el sqlcmd ODBC antiguo de SQL Server y no sirve.)"
echo "sqlcmd: $SQLCMD ($("$SQLCMD" --version 2>/dev/null | tr -d '\r' | grep -iE ' *v[0-9]' | head -1))"

# Autenticacion Microsoft Entra. ActiveDirectoryDefault usa la sesion de "az login".
SQLCMD_AUTH="${SQLCMD_AUTH:-ActiveDirectoryDefault}"
sq() { "$SQLCMD" --authentication-method "$SQLCMD_AUTH" "$@"; }

OLTP_HOST="tcp:${SQL_SERVER}.database.windows.net,1433"
# DW_HOST lo define config.sh segun DW_MODO (serverless | dedicado).

ejecutar() {  # host, base, archivo, [-v VAR=valor ...]
  local host="$1" db="$2" file="$3"; shift 3
  echo "-> $file  @ $db"
  # -W quita el relleno de espacios y -s "|" separa columnas: sin esto las
  # columnas sql_variant/nvarchar(max) salen de miles de caracteres de ancho.
  sq -S "$host" -d "$db" -b -I -W -s "|" -i "$file" "$@"
}

oltp_despierto() {
  # MessyOpsOLTP es Azure SQL serverless con autopausa: la primera conexion
  # lo despierta y suele fallar con 40613 mientras arranca. Solo ese error se
  # reintenta; cualquier otro (login, firewall, driver) se muestra y se corta.
  local i salida
  for i in 1 2 3 4 5 6 7 8 9; do
    if salida=$(sq -S "$OLTP_HOST" -d "$OLTP_DB" -b -Q "SELECT 1" 2>&1); then
      echo "  OLTP en linea."; return 0
    fi
    if grep -qE '40613|40197|not currently available|no est. disponible' <<< "$salida"; then
      echo "  OLTP reanudandose (intento $i)..."; sleep 20
    else
      echo "$salida" | tr -d '\r' | sed 's/^/    /' >&2
      fail "sqlcmd no pudo conectar a $OLTP_HOST (el error de arriba no es de base pausada)."
    fi
  done
  echo "$salida" | tr -d '\r' | sed 's/^/    /' >&2
  fail "El OLTP sigue sin responder tras 3 min."
}

pool_en_linea() {
  if [ "$DW_MODO" = "serverless" ]; then
    # El pool Built-in siempre esta disponible; solo hay que crear la base.
    log "Synapse serverless: base de datos $SYNAPSE_POOL"
    sq -S "$DW_HOST" -d master -b -Q \
      "IF DB_ID('$SYNAPSE_POOL') IS NULL CREATE DATABASE [$SYNAPSE_POOL] COLLATE Latin1_General_100_CI_AS_SC_UTF8;"
    return 0
  fi
  local estado
  estado=$(az synapse sql pool show -n "$SYNAPSE_POOL" --workspace-name "$SYNAPSE_WS" -g "$RG" --query status -o tsv)
  if [ "$estado" = "Paused" ]; then
    log "El pool $SYNAPSE_POOL esta pausado: reanudando (tarda 1-3 min)"
    az synapse sql pool resume -n "$SYNAPSE_POOL" --workspace-name "$SYNAPSE_WS" -g "$RG" -o none
  fi
  warn "Pool dedicado en linea: se cobra por hora. Pausarlo al terminar:"
  warn "  az synapse sql pool pause -n $SYNAPSE_POOL --workspace-name $SYNAPSE_WS -g $RG"
}

case "${1:-}" in
  oltp)
    log "OLTP: CDC nativo y usuario de la identidad administrada de ADF"
    oltp_despierto
    ejecutar "$OLTP_HOST" "$OLTP_DB" sql/02_cdc_setup.sql -v ADF_NAME="$ADF_NAME"
    ;;
  bronze)
    [ -n "${MASTER_KEY_PWD:-}" ] || fail "Exportar MASTER_KEY_PWD (contrasena de la master key de MessyOpsDW)."
    pool_en_linea
    if [ "$DW_MODO" = "dedicado" ]; then
      LAKE_URL="abfss://bronze@${STORAGE_ACCOUNT}.dfs.core.windows.net"
    else
      LAKE_URL="https://${STORAGE_ACCOUNT}.dfs.core.windows.net/bronze"
    fi
    log "Synapse ($DW_MODO): tablas externas Bronze sobre $LAKE_URL"
    ejecutar "$DW_HOST" "$SYNAPSE_POOL" sql/00_bronze_external.sql \
             -v LAKE_URL="$LAKE_URL" MASTER_KEY_PWD="$MASTER_KEY_PWD"
    log "Synapse: monitoreo de Bronze"
    ejecutar "$DW_HOST" "$SYNAPSE_POOL" sql/03_bronze_monitoreo.sql
    ;;
  validar)
    # Antes de consultar Synapse se mira el lago: si una carpeta de Bronze aun
    # no existe, Synapse responde con el error poco claro 16561 ("content of
    # directory cannot be listed"). Aqui se dice exactamente que falta.
    log "Lago: archivos Parquet por entidad en bronze/"
    ENTIDADES="customers products suppliers warehouses sales_orders sales_order_lines invoices payments
               shipments returns purchase_orders purchase_order_lines supplier_invoices supplier_payments
               inventory_snapshots support_tickets"
    ARCHIVOS=$(az storage fs file list -f bronze --account-name "$STORAGE_ACCOUNT" --auth-mode login \
                 --query "[?!isDirectory].name" -o tsv 2>&1) \
      || fail "No se pudo listar el contenedor bronze con tu usuario:
$ARCHIVOS"
    FALTAN=0
    for e in $ENTIDADES; do
      n=$(grep "^dbo\.$e/" <<< "$ARCHIVOS" | grep -vc '/_' || true)
      if [ "$n" -gt 0 ]; then printf '  %-22s %4s archivo(s)\n' "$e" "$n"
      else printf '  %-22s  --  sin archivos todavia\n' "$e"; FALTAN=$((FALTAN+1)); fi
    done
    if [ "$FALTAN" -gt 0 ]; then
      warn "$FALTAN entidad(es) sin datos en Bronze. Si el recurso CDC acaba de arrancar, la"
      warn "instantanea inicial aun no termino: esperar y repetir. Estado del recurso:"
      warn "  $(bash scripts/03_desplegar_adf_cdc.sh estado 2>/dev/null | tail -1)"
      fail "Validacion en Synapse omitida hasta que las 16 entidades tengan archivos."
    fi

    pool_en_linea
    # Solo Bronze: V1..V7 de sql/04_validaciones.sql necesitan Silver/Gold.
    ejecutar "$DW_HOST" "$SYNAPSE_POOL" sql/05_validar_bronze.sql
    ;;
  *)
    echo "Uso: $0 {oltp|bronze|validar}"; exit 2 ;;
esac
