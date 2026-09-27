# Decisiones de Modelado Dimensional

Este documento sustenta las decisiones técnicas de diseño relacionadas al esquema estrella y el modelado analítico en la capa Gold.

## Resolución y Justificación de Snapshots (SCD2)

En nuestro modelo estrella necesitamos mantener la historia real de los datos de negocio. Si un producto cambia de categoría o precio, o si un cliente cambia de región, simplemente sobrescribir el registro arruinaría la trazabilidad de las ventas pasadas (SCD Tipo 1).

Para evitar esto y cumplir con las mejores prácticas, es necesario manejar **Dimensiones Lentamente Cambiantes de Tipo 2 (SCD2)**.

En lugar de escribir complejas lógicas manuales en SQL con sentencias `MERGE` para gestionar la apertura y cierre de las fechas de vigencia, **se implementó la funcionalidad nativa `dbt snapshot`**. 
Esta herramienta actúa como un puente lógico perfecto: toma la "foto actual" desde la capa Silver, detecta los atributos modificados respecto al microlote anterior y automatiza la creación de los rangos `valid_from` y `valid_to`. 

Finalmente, la capa Gold se cruza (JOIN) con estos rangos usando la fecha del hecho (`fecha_venta`). Así, un reporte histórico muestra el precio y la categoría exacta que el producto tenía cuando se vendió, logrando un control histórico robusto y estándar en la industria.

## ¿Estrella o copo de nieve?

Se eligió un **esquema estrella**. 

La jerarquía de categoría tiene dos niveles y decenas de filas, así que aplanarla directamente dentro de `dim_producto` evita la necesidad de hacer JOINs adicionales en cada consulta de BI, lo cual maximiza el rendimiento y no complica el mantenimiento. 

Se justificaría pasar a copo de nieve (creando una `dim_categoria` separada) solo si la jerarquía creciera a cuatro o más niveles con atributos descriptivos propios, o si varias tablas de hechos distintas empezaran a compartirla de forma aislada.

## Pruebas de Integridad y Calidad

Contamos con 106 tests en dbt. Además de los genéricos (`not_null`, `unique`, `relationships`), hay pruebas singulares que protegen los invariantes dimensionales:

| Test | Qué detecta |
|---|---|
| `assert_bronze_silver_sin_perdida` | Eventos de Bronze que el filtro incremental dejó fuera de Silver. |
| `assert_reconciliacion_silver_gold` | Diferencias diarias de conteo o importe entre Silver y Gold. |
| `assert_fact_sin_duplicar_por_scd` | Filas de hechos multiplicadas por un join SCD2 mal resuelto. |
| `assert_scd2_una_version_vigente` | Más de una versión de dimensión vigente para la misma clave. |
| `assert_scd2_sin_solapamiento` | Rangos de fechas de vigencia que se solapan en la misma clave. |

Los tests de integridad referencial en Silver tienen severidad `warn` porque un maestro puede llegar retrasado en el microlote siguiente; en Gold son `error` porque el "miembro desconocido (-1)" garantiza que nunca debería haber huérfanos.
