{{ config(
    materialized = 'table',
    distribution = 'HASH(cliente_id)'
) }}
select 1 as cliente_id
