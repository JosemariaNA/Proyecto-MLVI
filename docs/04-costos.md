# Costos y optimización

## Dónde está el gasto

| Componente | Modelo de cobro | Cómo se contiene |
|---|---|---|
| Recurso CDC de ADF (`cdc_oltp_bronze`) | Cómputo de flujo de datos mientras el recurso está en ejecución | Microlote de 15 min. Detenerlo con `./scripts/03_desplegar_adf_cdc.sh detener` cuando no se use, por ejemplo fuera del periodo de evaluación. Mientras la parada dure menos que la retención del CDC (7 días), al reiniciar no se pierden cambios. |
| ADLS Gen2 (Bronze) | Almacenamiento y transacciones | Parquet con compresión Snappy. Con cambios netos se escribe como máximo una fila por clave y microlote. |
| Synapse serverless (Built-in) | Por TB leído | Es lo que usa Bronze hoy. El volumen de MessyOps es de cientos de MB, así que las consultas cuestan centavos. |
| Pool dedicado de Synapse (opcional) | Por DWU mientras está encendido | Solo existe si se crea con `CREAR_POOL_DEDICADO=si`, y se crea pausado. Pausarlo siempre al terminar (`az synapse sql pool pause`). |
| OLTP Azure SQL serverless (`GP_S_Gen5_2`) | Por vCore-segundo mientras está activo | El recurso CDC lo consulta cada 15 min, así que no se autopausa mientras la captura corre. |
| ADF (pipelines de dbt) | Por ejecución de actividad | Trigger cada 15 min, alineado con Bronze: no se transforma más seguido de lo que llegan datos. |
| ACI (dbt) | Por segundo de CPU y memoria | Se crea y se destruye en cada ejecución. |
| CDC en el OLTP | Almacenamiento de las tablas de cambios | Retención de 7 días. |

## Recomendaciones

1. **El mayor costo fijo es el recurso CDC en ejecución (más el OLTP que mantiene despierto).** Para un proyecto académico, conviene encender los dos solo durante las pruebas y la demostración.
2. **Ajustar la frecuencia al SLA real del negocio.** Si alcanza con 30 o 60 minutos, el recurso CDC acepta esos intervalos y el costo de cómputo baja en la misma proporción.
3. **Revisar el tamaño y la distribución de `gold.fact_ventas`** cuando pase de algunos millones de filas: `DBCC PDW_SHOWSPACEUSED('gold.fact_ventas')` en Synapse.
