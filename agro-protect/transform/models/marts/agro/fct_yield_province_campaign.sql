{{ config(tags=['agro', 'mart', 'yield']) }}

SELECT
    province_dim.province_name,
    yield_fact.province_key,
    yield_fact.crop_name,
    yield_fact.crop_key,
    yield_fact.campaign_name,
    yield_fact.campaign_start_year,
    yield_fact.campaign_end_year,
    yield_fact.harvest_year,
    yield_fact.department_count,
    yield_fact.sown_area_ha,
    yield_fact.harvested_area_ha,
    yield_fact.harvested_share_pct,
    yield_fact.production_tonnes,
    yield_fact.yield_kg_ha
FROM {{ ref('int_yield__province_campaign') }} AS yield_fact
INNER JOIN {{ ref('dim_province') }} AS province_dim
    ON yield_fact.province_key = province_dim.province_key
