{{ config(
    materialized='view',
    tags=['seed', 'agronomy', 'staging']
) }}

SELECT
    LOWER(TRIM(crop_name)) AS crop_name,
    {{ normalize_text('crop_name') }} AS crop_key,
    SAFE_CAST(harvest_year AS INT64) AS harvest_year,
    campaign_name,
    SAFE_CAST(SPLIT(campaign_name, '/')[SAFE_OFFSET(0)] AS INT64) AS campaign_start_year,
    SAFE_CAST(SPLIT(campaign_name, '/')[SAFE_OFFSET(1)] AS INT64) AS campaign_end_year,
    province_name,
    {{ normalize_text('province_name') }} AS province_key,
    province_id,
    department_name,
    {{ normalize_text('department_name') }} AS department_key,
    department_id,
    SAFE_CAST(sown_area_ha AS FLOAT64) AS sown_area_ha,
    SAFE_CAST(harvested_area_ha AS FLOAT64) AS harvested_area_ha,
    SAFE_CAST(production_tonnes AS FLOAT64) AS production_tonnes,
    SAFE_CAST(yield_kg_ha AS FLOAT64) AS yield_kg_ha
FROM {{ ref('yield_department_campaign') }}
