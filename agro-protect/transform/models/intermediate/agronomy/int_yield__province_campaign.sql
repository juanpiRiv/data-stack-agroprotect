{{ config(tags=['agro', 'yield', 'intermediate']) }}

WITH aggregated_yield AS (
    SELECT
        crop_name,
        crop_key,
        campaign_name,
        campaign_start_year,
        campaign_end_year,
        harvest_year,
        province_name,
        province_key,
        SUM(sown_area_ha) AS sown_area_ha,
        SUM(harvested_area_ha) AS harvested_area_ha,
        SUM(production_tonnes) AS production_tonnes,
        COUNT(DISTINCT department_id) AS department_count
    FROM {{ ref('stg_seed__yield_department_campaign') }}
    GROUP BY
        crop_name,
        crop_key,
        campaign_name,
        campaign_start_year,
        campaign_end_year,
        harvest_year,
        province_name,
        province_key
)

SELECT
    crop_name,
    crop_key,
    campaign_name,
    campaign_start_year,
    campaign_end_year,
    harvest_year,
    province_name,
    province_key,
    department_count,
    sown_area_ha,
    harvested_area_ha,
    production_tonnes,
    SAFE_DIVIDE(production_tonnes * 1000.0, harvested_area_ha) AS yield_kg_ha,
    SAFE_DIVIDE(harvested_area_ha, sown_area_ha) AS harvested_share_pct
FROM aggregated_yield
