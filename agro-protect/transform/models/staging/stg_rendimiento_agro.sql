{{ config(
    materialized='table',
    tags=['agricultural_data', 'productivity']
) }}

WITH source AS (
    SELECT
        cultivo,
        anio,
        campania,
        provincia,
        SAFE_CAST(provincia_id AS INT64) AS provincia_id,
        departamento,
        SAFE_CAST(departamento_id AS INT64) AS departamento_id,
        SAFE_CAST(superficie_sembrada_ha AS FLOAT64) AS superficie_sembrada_ha,
        SAFE_CAST(superficie_cosechada_ha AS FLOAT64) AS superficie_cosechada_ha,
        SAFE_CAST(produccion_tm AS FLOAT64) AS produccion_tm,
        SAFE_CAST(rendimiento_kgxha AS FLOAT64) AS rendimiento_kgxha
    FROM {{ seed('rendimiento_agro') }}
),

with_derived_metrics AS (
    SELECT
        s.*,
        -- Calculate harvest ratio (%) - efficiency of harvesting
        CASE
            WHEN s.superficie_sembrada_ha > 0
                THEN (s.superficie_cosechada_ha / s.superficie_sembrada_ha) * 100
            ELSE NULL
        END AS harvest_ratio_pct,
        
        -- Calculate production efficiency (kg per ha sown)
        CASE
            WHEN s.superficie_sembrada_ha > 0
                THEN (s.produccion_tm * 1000) / s.superficie_sembrada_ha
            ELSE NULL
        END AS produccion_kg_ha_sown,
        
        -- Year dimension
        EXTRACT(YEAR FROM CURRENT_DATE()) AS current_year,
        
        -- Flag high-quality records (non-null key fields)
        CASE
            WHEN s.cultivo IS NOT NULL
                AND s.anio IS NOT NULL
                AND s.provincia IS NOT NULL
                AND s.rendimiento_kgxha IS NOT NULL
                AND s.rendimiento_kgxha > 0
            THEN 1
            ELSE 0
        END AS is_valid_record
    FROM source AS s
)

SELECT *
FROM with_derived_metrics
WHERE is_valid_record = 1
