{{ config(
    materialized = 'table'
) }}

/*  DimFecha: dimension conformada y generada, no derivada de datos.
    Se materializa completa (no incremental) porque es pequena, barata
    de reconstruir y debe existir antes que cualquier hecho.
    Se replica en todas las distribuciones: participa en practicamente
    todas las consultas y su tamano lo hace gratuito.                   */

with
L0 AS (SELECT c FROM (SELECT 1 AS c UNION ALL SELECT 1) AS v),
L1 AS (SELECT 1 AS c FROM L0 A CROSS JOIN L0 B),
L2 AS (SELECT 1 AS c FROM L1 A CROSS JOIN L1 B),
L3 AS (SELECT 1 AS c FROM L2 A CROSS JOIN L2 B),
L4 AS (SELECT 1 AS c FROM L3 A CROSS JOIN L3 B),
Nums AS (SELECT n FROM (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n FROM L4) x WHERE n <= 30000),
dias AS (
    SELECT cast(dateadd(day, n, cast('{{ var("dim_fecha_inicio") }}' as date)) as date) as date_day
    FROM Nums
    WHERE cast(dateadd(day, n, cast('{{ var("dim_fecha_inicio") }}' as date)) as date) <= cast('{{ var("dim_fecha_fin") }}' as date)
),

calendario as (
    select cast(date_day as date) as fecha
    from dias
)

select
    cast(convert(char(8), fecha, 112) as int)                as fecha_key,
    fecha,
    datepart(year,    fecha)                                 as anio,
    datepart(quarter, fecha)                                 as trimestre,
    datepart(month,   fecha)                                 as mes,
    datepart(day,     fecha)                                 as dia,
    datepart(dayofyear, fecha)                               as dia_del_anio,
    datepart(week,    fecha)                                 as semana_anio,
    datepart(weekday, fecha)                                 as dia_semana,
    datename(month,   fecha)                                 as mes_nombre,
    datename(weekday, fecha)                                 as dia_semana_nombre,
    cast(convert(char(6), fecha, 112) as int)                as anio_mes,
    cast(datepart(year, fecha) * 10 + datepart(quarter, fecha) as int) as anio_trimestre,
    -- Primer y ultimo dia del mes: evitan que cada medida DAX repita la formula.
    datefromparts(datepart(year, fecha), datepart(month, fecha), 1) as primer_dia_mes,
    eomonth(fecha)                                           as ultimo_dia_mes,
    cast(case when datepart(weekday, fecha) in (1, 7) then 1 else 0 end as bit) as es_fin_semana,
    cast(case when fecha = eomonth(fecha) then 1 else 0 end as bit)             as es_fin_de_mes,
    cast(case when fecha <= cast(sysutcdatetime() as date) then 1 else 0 end as bit) as es_pasado,
    sysutcdatetime()                                         as ingested_at
from calendario

union all

/*  Miembro desconocido: permite que un hecho sin fecha valida siga
    entrando al modelo en vez de desaparecer del reporte.              */
select
    -1, cast('1900-01-01' as date), 1900, 0, 0, 0, 0, 0, 0,
    'Desconocido', 'Desconocido', 190001, 19000,
    cast('1900-01-01' as date), cast('1900-01-31' as date),
    cast(0 as bit), cast(0 as bit), cast(0 as bit),
    sysutcdatetime()
