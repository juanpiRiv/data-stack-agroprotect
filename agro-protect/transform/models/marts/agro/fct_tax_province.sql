{{ config(tags=['agro', 'mart', 'economic']) }}

SELECT
    province_dim.province_name,
    tax_fact.province_key,
    tax_fact.rural_property_tax_usd_ha_min,
    tax_fact.rural_property_tax_usd_ha_max,
    tax_fact.rural_property_tax_usd_ha_avg,
    tax_fact.rural_property_tax_usd_ha_spread,
    tax_fact.gross_turnover_tax_pct
FROM {{ ref('int_tax__province') }} AS tax_fact
INNER JOIN {{ ref('dim_province') }} AS province_dim
    ON tax_fact.province_key = province_dim.province_key
