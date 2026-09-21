# Costes y optimización

## Dónde está el gasto

| Componente | Modelo de cobro | Cómo se contiene |
|---|---|---|
| Dedicated SQL pool de Synapse | Por DWU mientras está encendido | Pausarlo fuera de las ventanas de micro-lotes. |
| ADF | Por actividad y por hora de integración | Microlote de 5 min con concurrencia 1. Si el SLA lo permite, 15 min reduce las ejecuciones a un tercio. |
| ACI (dbt) | Por segundo de CPU/memoria | Se crea y destruye en cada ejecución; nunca queda encendido. |
| CDC en el OLTP | Almacenamiento del log de cambios | Retención de 7 días; subirla más solo si hace falta. |

## Recomendaciones

1. Frecuencia del trigger según el SLA real del negocio, no la más alta posible.
2. Mantener la auto-pausa de Azure SQL cuando no haya microlotes.
3. Revisar el tamaño y los índices de `gold.fact_ventas` cuando pase de algunos millones de filas; en Azure SQL el control equivalente se realiza con las vistas de espacio de `sys.dm_db_partition_stats`.
