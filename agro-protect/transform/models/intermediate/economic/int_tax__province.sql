{{ config(tags=['agro', 'economic', 'intermediate']) }}

SELECT
    province_name,
    province_key,
    rural_property_tax_usd_ha_min,
    rural_property_tax_usd_ha_max,
    rural_property_tax_usd_ha_avg,
    gross_turnover_tax_pct,
    rural_property_tax_usd_ha_max - rural_property_tax_usd_ha_min AS rural_property_tax_usd_ha_spread
FROM {{ ref('stg_seed__tax_province') }}
