{{ config(tags=['agro', 'mart', 'combined']) }}

WITH weather_by_campaign AS (
    SELECT
        province_key,
        campaign_name,
        campaign_start_year,
        ANY_VALUE(province_name) AS province_name,
        COUNT(*) AS weather_day_count,
        COUNTIF(is_quality_approved) AS usable_weather_day_count,
        COUNT(DISTINCT location_id) AS weather_location_count,
        SUM(precipitation_mm) AS campaign_precipitation_mm,
        AVG(avg_air_temp_c) AS avg_campaign_temp_c,
        MAX(max_air_temp_c) AS max_campaign_temp_c,
        MIN(min_air_temp_c) AS min_campaign_temp_c,
        AVG(relative_humidity_pct) AS avg_relative_humidity_pct,
        AVG(vpd_kpa) AS avg_vpd_kpa,
        SUM(gdd_base_10_c_days) AS total_gdd_base_10,
        SUM(CASE WHEN frost_day THEN 1 ELSE 0 END) AS frost_days,
        SUM(CASE WHEN heat_stress_day THEN 1 ELSE 0 END) AS heat_days,
        SUM(CASE WHEN heavy_rain_day THEN 1 ELSE 0 END) AS heavy_rain_days,
        SUM(CASE WHEN dry_day THEN 1 ELSE 0 END) AS dry_days,
        SUM(CASE WHEN fungal_risk_day THEN 1 ELSE 0 END) AS fungal_risk_days
    FROM {{ ref('fct_weather_daily') }}
    GROUP BY
        province_key,
        campaign_name,
        campaign_start_year
)

SELECT
    yield_fact.province_name,
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
    yield_fact.yield_kg_ha,
    weather_by_campaign.weather_day_count,
    weather_by_campaign.usable_weather_day_count,
    weather_by_campaign.weather_location_count,
    weather_by_campaign.campaign_precipitation_mm,
    weather_by_campaign.avg_campaign_temp_c,
    weather_by_campaign.max_campaign_temp_c,
    weather_by_campaign.min_campaign_temp_c,
    weather_by_campaign.avg_relative_humidity_pct,
    weather_by_campaign.avg_vpd_kpa,
    weather_by_campaign.total_gdd_base_10,
    weather_by_campaign.frost_days,
    weather_by_campaign.heat_days,
    weather_by_campaign.heavy_rain_days,
    weather_by_campaign.dry_days,
    weather_by_campaign.fungal_risk_days,
    tax_fact.rural_property_tax_usd_ha_min,
    tax_fact.rural_property_tax_usd_ha_max,
    tax_fact.rural_property_tax_usd_ha_avg,
    tax_fact.rural_property_tax_usd_ha_spread,
    tax_fact.gross_turnover_tax_pct,
    SAFE_DIVIDE(
        weather_by_campaign.usable_weather_day_count,
        weather_by_campaign.weather_day_count
    ) AS usable_weather_day_ratio,
    weather_by_campaign.province_key IS NOT NULL AS has_weather_campaign_data,
    tax_fact.province_key IS NOT NULL AS has_tax_data
FROM {{ ref('fct_yield_province_campaign') }} AS yield_fact
LEFT JOIN weather_by_campaign
    ON
        yield_fact.province_key = weather_by_campaign.province_key
        AND yield_fact.campaign_name = weather_by_campaign.campaign_name
LEFT JOIN {{ ref('fct_tax_province') }} AS tax_fact
    ON yield_fact.province_key = tax_fact.province_key
