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
)

SELECT
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
    CASE
        WHEN superficie_sembrada_ha > 0
        THEN (superficie_cosechada_ha / superficie_sembrada_ha) * 100
    END AS harvest_ratio_pct,
    CASE
        WHEN superficie_sembrada_ha > 0
        THEN (produccion_tm * 1000) / superficie_sembrada_ha
    END AS produccion_kg_ha_sown,
    EXTRACT(YEAR FROM CURRENT_DATE()) AS current_year
FROM source
WHERE
    cultivo IS NOT NULL
    AND anio IS NOT NULL
    AND provincia IS NOT NULL
    AND rendimiento_kgxha IS NOT NULL
    AND rendimiento_kgxha > 0
