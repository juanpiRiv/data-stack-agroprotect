{{ config(
    materialized='table',
    tags=['agricultural_data', 'productivity']
) }}

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
    SAFE_CAST(rendimiento_kgxha AS FLOAT64) AS rendimiento_kgxha,
    CASE
        WHEN SAFE_CAST(superficie_sembrada_ha AS FLOAT64) > 0
            THEN (
                SAFE_CAST(superficie_cosechada_ha AS FLOAT64)
                / SAFE_CAST(superficie_sembrada_ha AS FLOAT64)
            ) * 100
    END AS harvest_ratio_pct,
    CASE
        WHEN SAFE_CAST(superficie_sembrada_ha AS FLOAT64) > 0
            THEN (SAFE_CAST(produccion_tm AS FLOAT64) * 1000)
                / SAFE_CAST(superficie_sembrada_ha AS FLOAT64)
    END AS produccion_kg_ha_sown,
    EXTRACT(YEAR FROM CURRENT_DATE()) AS current_year
FROM {{ seed('rendimiento_agro') }}
WHERE
    cultivo IS NOT NULL
    AND anio IS NOT NULL
    AND provincia IS NOT NULL
    AND SAFE_CAST(rendimiento_kgxha AS FLOAT64) IS NOT NULL
    AND SAFE_CAST(rendimiento_kgxha AS FLOAT64) > 0
