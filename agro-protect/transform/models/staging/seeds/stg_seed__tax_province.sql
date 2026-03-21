{{ config(
    materialized='view',
    tags=['seed', 'economic', 'staging']
) }}

SELECT
    province_name,
    {{ normalize_text('province_name') }} AS province_key,
    SAFE_CAST(rural_property_tax_usd_ha_min AS FLOAT64) AS rural_property_tax_usd_ha_min,
    SAFE_CAST(rural_property_tax_usd_ha_max AS FLOAT64) AS rural_property_tax_usd_ha_max,
    SAFE_CAST(rural_property_tax_usd_ha_avg AS FLOAT64) AS rural_property_tax_usd_ha_avg,
    SAFE_CAST(gross_turnover_tax_pct AS FLOAT64) AS gross_turnover_tax_pct
FROM {{ ref('tax_province') }}
