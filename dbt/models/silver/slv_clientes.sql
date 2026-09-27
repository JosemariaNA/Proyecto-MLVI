{{ config(
    materialized = 'incremental',
    unique_key   = 'cliente_id',
    distribution = 'HASH(cliente_id)',
    incremental_strategy = 'merge'
) }}

/*  Silver: clientes limpios y desduplicados.
    Una fila por customer_id, con el ultimo estado conocido segun CDC.
    Aqui se resuelve la calidad (trim, email en minuscula, telefono sin
    formato) para que Gold nunca tenga que limpiar nada.                */

with eventos as (
    {{ ultimo_evento_cdc(source('bronze', 'customers'), 'customer_id',
                         'silver', 'slv_clientes') }}
),

limpio as (
    select
        cast(customer_id as nvarchar(50))                   as cliente_id,
        {{ limpiar_texto('company_name') }}                 as nombre,
        cast(null as nvarchar(100))                         as apellido,
        {{ limpiar_texto('company_name') }}                 as nombre_completo,
        {{ limpiar_email('contact_email') }}                as email,
        {{ limpiar_telefono('contact_phone') }}             as telefono,
        case upper({{ limpiar_texto('country') }})
            when 'US' then 'UNITED STATES'
            when 'USA' then 'UNITED STATES'
            when 'U.S.A.' then 'UNITED STATES'
            when 'UK' then 'UNITED KINGDOM'
            when 'U.K.' then 'UNITED KINGDOM'
            when 'ENGLAND' then 'UNITED KINGDOM'
            else upper({{ limpiar_texto('country') }})
        end                                                 as pais,
        {{ limpiar_texto('city') }}                         as ciudad,
        cast(customer_since as datetime2(3))                as creado_en,
        cast(customer_since as datetime2(3))                as actualizado_en,
        {{ es_borrado() }}                                  as es_borrado,
        cast(null as binary(10))                                      as lsn_origen,
        cast(getutcdate() as datetime2(3)) as ingested_at
    from eventos
)

select
    cliente_id,
    nombre,
    apellido,
    nombre_completo,
    email,
    telefono,
    pais,
    ciudad,
    -- Indicador de calidad, no un filtro: el registro entra igual, pero
    -- queda marcado para que el test lo reporte en data_quality_log.
    cast(case when email like '%_@_%.__%' then 1 else 0 end as bit) as email_valido,
    creado_en,
    actualizado_en,
    es_borrado,
    lsn_origen,
    ingested_at
from limpio
