{{ config(
    materialized='table',
    tags=['agricultural_data', 'taxes']
) }}

WITH source AS (
    SELECT
        provincia,
        inmobiliario_rural_usd_ha,
        SAFE_CAST(REPLACE(iibb_agro_%, '%', '') AS FLOAT64) AS iibb_agro_pct
    FROM {{ seed('impuestos_agro_argentina') }}
),

parsed_taxes AS (
    SELECT
        s.provincia,
        
        -- Parse property tax range (extract midpoint)
        CASE
            WHEN STRING_LENGTH(s.inmobiliario_rural_usd_ha) > 0
            THEN CAST(
                (CAST(
                    REGEXP_EXTRACT(s.inmobiliario_rural_usd_ha, r'^(\d+)') AS FLOAT64
                ) + CAST(
                    REGEXP_EXTRACT(s.inmobiliario_rural_usd_ha, r'(\d+)$') AS FLOAT64
                )) / 2 AS FLOAT64
            )
            ELSE NULL
        END AS inmobiliario_rural_usd_ha,
        
        -- Gross income tax percentage
        s.iibb_agro_pct,
        
        -- Data quality flag
        CASE
            WHEN s.provincia IS NOT NULL
            THEN 1
            ELSE 0
        END AS is_valid_record
    FROM source AS s
)

SELECT
    provincia,
    inmobiliario_rural_usd_ha,
    iibb_agro_pct,
    is_valid_record
FROM parsed_taxes
WHERE is_valid_record = 1
ORDER BY provincia
