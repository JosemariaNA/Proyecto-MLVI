#!/usr/bin/env python3
"""
Genera los dos artefactos de la capa Bronze a partir de un unico contrato:
el DDL real del OLTP (EstructuraOLTP.sql).

  1. adf/adfcdc/cdc_oltp_bronze.json  -> recurso Change Data Capture nativo de ADF
  2. sql/00_bronze_external.sql       -> tablas externas Bronze en Synapse

Generar ambos desde la misma fuente evita que el esquema que escribe ADF y el
que lee Synapse se desalineen (el origen del error de ticket_text 100 vs 50).

Uso:  python3 scripts/generar_bronze.py
"""
import json
import pathlib
import re

RAIZ = pathlib.Path(__file__).resolve().parent.parent
DDL = RAIZ / "EstructuraOLTP.sql"
SALIDA_CDC = RAIZ / "adf" / "adfcdc" / "cdc_oltp_bronze_v2.json"
SALIDA_SQL = RAIZ / "sql" / "00_bronze_external.sql"

# Linked services propios del proyecto. 03_desplegar_adf_cdc.sh los crea con
# el MISMO formato que usan los de ADF Studio (el recurso CDC no entiende los
# escritos a mano y deja el origen vacio: "DF-ARG-007 format is not defined").
import os
LS_ORIGEN = os.environ.get("LS_ORIGEN", "ls_oltp_messyops")
LS_DESTINO = os.environ.get("LS_DESTINO", "ls_adls_lake")
CONTENEDOR = "bronze"
# Carpeta por tabla con la convencion de Studio: bronze/dbo.<tabla>/.
# Con mapeo automatico el servicio exige que el destino se llame
# "<contenedor>/<esquema>.<tabla>"; con otro nombre responde
# "Invalid mapping information".
def carpeta(tabla):
    return f"dbo.{tabla}"

# data_quality_log es una tabla de auditoria del generador de datos, no de negocio.
EXCLUIR = {"data_quality_log"}

# Columnas que agrega la captura. Son el contrato Bronze -> Silver.
COL_OPERACION = "cdc_operation"   # I = insert, U = update, D = delete
COL_INGESTA = "ingested_at"       # hora UTC del microlote que escribio la fila


def leer_ddl():
    for cod in ("utf-16", "utf-8-sig", "utf-8"):
        try:
            return DDL.read_text(encoding=cod)
        except UnicodeError:
            continue
    raise SystemExit(f"No se pudo leer {DDL}")


def parsear_tablas(texto):
    tablas = {}
    patron_tabla = re.compile(r"CREATE TABLE \[dbo\]\.\[(\w+)\]\((.*?)(?:CONSTRAINT|\)\s*ON \[PRIMARY\])", re.S)
    patron_col = re.compile(r"^\s*\[(\w+)\] \[(\w+)\](\((\w+)(,\s*\d+)?\))?\s+(NOT NULL|NULL)", re.M)
    for m in patron_tabla.finditer(texto):
        nombre = m.group(1)
        if nombre in EXCLUIR:
            continue
        cols = []
        for c in patron_col.finditer(m.group(2)):
            cols.append({"nombre": c.group(1), "tipo": c.group(2).lower(), "largo": c.group(4)})
        tablas[nombre] = cols
    return tablas


def tipo_sql(col):
    t, n = col["tipo"], col["largo"]
    if t in ("nvarchar", "varchar", "nchar", "char"):
        return f"{t.upper()}({n})"
    if t in ("tinyint", "smallint"):
        # Se ensancha a INT: el Parquet que escribe el flujo de datos puede
        # anotar estos enteros de forma distinta y INT los acepta a todos.
        return "INT"
    if t == "datetime2":
        return f"DATETIME2({n or 7})"
    return t.upper()


def tipo_df(col):
    """Tipo en el vocabulario de Datasets de ADF."""
    return {
        "nvarchar": "String", "varchar": "String", "nchar": "String", "char": "String",
        "tinyint": "Int16", "smallint": "Int16", "int": "Int32", "bigint": "Int64",
        "float": "Double", "real": "Single", "bit": "Boolean", "date": "Date",
        "datetime2": "DateTime", "datetime": "DateTime", "decimal": "Decimal",
    }.get(col["tipo"], "String")


def generar_cdc(tablas):
    """
    Estructura copiada del recurso CDC que crea ADF Studio (exportado en
    descubrimiento/adfcdc_existentes.json). Detalles que importan:
      - Claves de primer nivel en PascalCase: SourceConnectionsInfo, Connection,
        SourceEntities, TargetEntities, DataMapperMappings, Relationships, Policy.
        Con camelCase el servicio no lee las propiedades de conexion y falla con
        "DF-ARG-007 format is not defined".
      - skipInitialLoad va en la conexion de origen, no en cada tabla.
      - schema vacio: el servicio lo toma de la tabla y del mapeo.
    """
    ref_origen = {"connectionName": LS_ORIGEN, "type": "linkedservicetype"}

    fuentes, destinos, mapeos = [], [], []
    for tabla, cols in tablas.items():
        origen = f"dbo.{tabla}"
        destino = f"{CONTENEDOR}/{carpeta(tabla)}"

        esquema_fuente = [{"name": c["nombre"], "type": tipo_df(c)} for c in cols]
        esquema_destino = [{"name": c["nombre"], "type": tipo_df(c)} for c in cols] + [
            {"name": COL_OPERACION, "type": "String"},
            {"name": COL_INGESTA, "type": "DateTime"}
        ]

        fuentes.append({
            "name": origen,
            "properties": {
                "dslConnectorProperties": [
                    {"name": "schemaName", "value": "dbo"},
                    {"name": "tableName", "value": tabla},
                    # CDC nativo de SQL: el recurso lee las tablas de cambios y
                    # guarda su propio checkpoint de LSN.
                    {"name": "enableNativeCdc", "value": True},
                    # Cambios netos: como maximo una fila por clave y microlote.
                    {"name": "netChanges", "value": True},
                ],
                "schema": [],
            },
        })

        destinos.append({
            "name": destino,
            "properties": {
                "dslConnectorProperties": [
                    {"name": "container", "value": CONTENEDOR},
                    {"name": "fileSystem", "value": CONTENEDOR},
                    {"name": "folderPath", "value": carpeta(tabla)},
                ],
                "schema": [],
            },
        })

        # Mapeo explicito: columnas del OLTP tal cual + 2 columnas derivadas
        # que forman el contrato Bronze -> Silver.
        atributos = [{
            "name": c["nombre"],
            "type": "Direct",
            "functionName": "",
            "attributeReference": {
                "name": c["nombre"],
                "entity": origen,
                "entityConnectionReference": ref_origen,
            },
        } for c in cols]
        atributos += [
            {
                "name": COL_OPERACION,
                "type": "Derived",
                "functionName": "",
                "expression": "iif(isDelete(), 'D', iif(isUpdate(), 'U', 'I'))",
                "attributeReferences": [],
            },
            {
                "name": COL_INGESTA,
                "type": "Derived",
                "functionName": "",
                "expression": "currentUTC()",
                "attributeReferences": [],
            },
        ]

        # MAPEO=auto (defecto): igual que el recurso que creo ADF Studio, sin
        # lista de columnas; el servicio copia todas las columnas del origen.
        # MAPEO=explicito: lista de columnas + cdc_operation/ingested_at. Con
        # esquema vacio el servicio no ve las columnas y falla con
        # "Column ... unavailable" y "format is not defined".
        if os.environ.get("MAPEO", "auto") != "explicito":
            atributos = []
        mapeos.append({
            "attributeMappingInfo": {"attributeMappings": atributos},
            "sourceConnectionReference": ref_origen,
            "sourceEntityName": origen,
            "targetEntityName": destino,
        })

    return {
        "name": "cdc_oltp_bronze_v2",
        "properties": {
            "Policy": {"mode": "Microbatch", "recurrence": {"frequency": "Minute", "interval": 15}},
            "SourceConnectionsInfo": [{
                "Connection": {
                    "commonDslConnectorProperties": [
                        {"name": "allowSchemaDrift", "value": True},
                        {"name": "inferDriftedColumnTypes", "value": True},
                        {"name": "format", "value": "table"},
                        {"name": "store", "value": "sqlserver"},
                        # Instantanea inicial UNA sola vez; despues solo cambios.
                        # El CDC no contiene las filas previas a su activacion.
                        {"name": "skipInitialLoad", "value": False},
                    ],
                    "isInlineDataset": True,
                    "linkedService": {"referenceName": LS_ORIGEN, "type": "LinkedServiceReference"},
                    "linkedServiceType": "AzureSqlDatabase",
                    "type": "linkedservicetype",
                },
                "SourceEntities": fuentes,
            }],
            "TargetConnectionsInfo": [{
                "Connection": {
                    "commonDslConnectorProperties": [
                        {"name": "allowSchemaDrift", "value": True},
                        {"name": "inferDriftedColumnTypes", "value": True},
                        {"name": "format", "value": "parquet"},
                    ],
                    "isInlineDataset": True,
                    "linkedService": {"referenceName": LS_DESTINO, "type": "LinkedServiceReference"},
                    "linkedServiceType": "AzureBlobFS",
                    "type": "linkedservicetype",
                },
                "DataMapperMappings": mapeos,
                "Relationships": [],
                "TargetEntities": destinos,
            }],
            "allowVNetOverride": False,
            # Se publica detenido; se arranca con scripts/03_desplegar_adf_cdc.sh iniciar.
            "status": "Stopped",
        },
    }


def generar_sql(tablas):
    lineas = [
        "/* =====================================================================",
        "   AzureDW - Capa Bronze en Synapse (base MessyOpsDW)",
        "   Compatible con el pool serverless Built-in y con un pool dedicado.",
        "   GENERADO por scripts/generar_bronze.py a partir de EstructuraOLTP.sql.",
        "   No editar a mano: cambiar el generador y volver a ejecutarlo.",
        "",
        "   Tablas externas NATIVAS (sin TYPE = HADOOP) sobre el Parquet que escribe",
        "   el recurso CDC de ADF en el contenedor bronze/<entidad>/.",
        "   - Las columnas se enlazan por NOMBRE, no por posicion.",
        "   - El comodin doble asterisco al final de LOCATION recorre subcarpetas",
        "     por si el recurso particiona la salida. (No se escribe aqui porque",
        "     barra + asterisco abriria un comentario anidado en T-SQL.)",
        "   Contrato Bronze: columnas del OLTP + cdc_operation (I/U/D) + ingested_at.",
        "",
        "   Variables sqlcmd (las pasa scripts/02_desplegar_sql.sh):",
        "     LAKE_URL         raiz del contenedor bronze:",
        "                      serverless: https://<cuenta>.dfs.core.windows.net/bronze",
        "                      dedicado:   abfss://bronze@<cuenta>.dfs.core.windows.net",
        "     MASTER_KEY_PWD   contrasena de la master key (nunca en el repositorio)",
        "   ===================================================================== */",
        "",
        "IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'bronze') EXEC('CREATE SCHEMA bronze');",
        "GO",
        "IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')",
        "    CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$(MASTER_KEY_PWD)';",
        "GO",
        "IF NOT EXISTS (SELECT 1 FROM sys.database_scoped_credentials WHERE name = 'cred_adls_mi')",
        "    CREATE DATABASE SCOPED CREDENTIAL cred_adls_mi WITH IDENTITY = 'Managed Identity';",
        "GO",
        "",
        "-- Se eliminan primero las tablas: el origen de datos no se puede recrear",
        "-- mientras alguna tabla lo use (la version anterior era TYPE = HADOOP).",
    ]
    for t in tablas:
        lineas.append(f"IF OBJECT_ID('bronze.{t}') IS NOT NULL DROP EXTERNAL TABLE bronze.{t};")
    lineas += [
        "GO",
        "IF EXISTS (SELECT 1 FROM sys.external_data_sources WHERE name = 'ds_bronze')",
        "    DROP EXTERNAL DATA SOURCE ds_bronze;",
        "GO",
        "CREATE EXTERNAL DATA SOURCE ds_bronze WITH (",
        "    LOCATION   = '$(LAKE_URL)',",
        "    CREDENTIAL = cred_adls_mi",
        ");",
        "GO",
        "IF NOT EXISTS (SELECT 1 FROM sys.external_file_formats WHERE name = 'ff_parquet')",
        "    CREATE EXTERNAL FILE FORMAT ff_parquet WITH (FORMAT_TYPE = PARQUET);",
        "GO",
        "",
    ]
    for t, cols in tablas.items():
        defs = [f"    [{c['nombre']}] {tipo_sql(c)}" for c in cols]
        lineas.append(f"CREATE EXTERNAL TABLE bronze.{t} (")
        lineas.append(",\n".join(defs))
        lineas.append(f") WITH (LOCATION = '/{carpeta(t)}/**', DATA_SOURCE = ds_bronze, FILE_FORMAT = ff_parquet);")
        lineas.append("GO")
        lineas.append("")
    return "\n".join(lineas)


def main():
    tablas = parsear_tablas(leer_ddl())
    if len(tablas) != 16:
        raise SystemExit(f"Se esperaban 16 tablas de negocio y se encontraron {len(tablas)}: {list(tablas)}")
    SALIDA_CDC.parent.mkdir(parents=True, exist_ok=True)
    SALIDA_CDC.write_text(json.dumps(generar_cdc(tablas), indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    SALIDA_SQL.write_text(generar_sql(tablas), encoding="utf-8")
    print(f"{len(tablas)} tablas -> {SALIDA_CDC.relative_to(RAIZ)} y {SALIDA_SQL.relative_to(RAIZ)}")


if __name__ == "__main__":
    main()
