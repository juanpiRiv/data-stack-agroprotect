{{ config(
    materialized='table',
    tags=['agricultural_data', 'productivity']
) }}

with source as (
    select
        cultivo,
        anio,
        campania,
        provincia,
        safe_cast(provincia_id as int64) as provincia_id,
        departamento,
        safe_cast(departamento_id as int64) as departamento_id,
        safe_cast(superficie_sembrada_ha as float64) as superficie_sembrada_ha,
        safe_cast(superficie_cosechada_ha as float64) as superficie_cosechada_ha,
        safe_cast(produccion_tm as float64) as produccion_tm,
        safe_cast(rendimiento_kgxha as float64) as rendimiento_kgxha
    from {{ seed('rendimiento_agro') }}
)

select
    cultivo,
    anio,
    campania,
    provincia,
    provincia_id,
    departamento,
    departamento_id,
    superficie_sembrada_ha,
    superficie_cosechada_ha,
    produccion_tm,
    rendimiento_kgxha,
    case
        when superficie_sembrada_ha > 0
        then (superficie_cosechada_ha / superficie_sembrada_ha) * 100
    end as harvest_ratio_pct,
    case
        when superficie_sembrada_ha > 0
        then (produccion_tm * 1000) / superficie_sembrada_ha
    end as produccion_kg_ha_sown,
    extract(year from current_date()) as current_year,
    case
        when cultivo is not null
            and anio is not null
            and provincia is not null
            and rendimiento_kgxha is not null
            and rendimiento_kgxha > 0
        then 1
        else 0
    end as is_valid_record
from source
where
    cultivo is not null
    and anio is not null
    and provincia is not null
    and rendimiento_kgxha is not null
    and rendimiento_kgxha > 0
