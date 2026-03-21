{{ config(
    materialized='table',
    tags=['agricultural_data', 'taxes']
) }}

WITH source AS (
    SELECT
        provincia,
        inmobiliario_rural_usd_ha,
        SAFE_CAST(
            REGEXP_REPLACE(iibb_agro_percent, '%', '') AS FLOAT64
        ) AS iibb_agro_pct
    FROM {{ seed('impuestos_agro_argentina') }}
)

SELECT
    provincia,
    CASE
        WHEN STRING_LENGTH(inmobiliario_rural_usd_ha) > 0
        THEN CAST(
            (
                CAST(
                    REGEXP_EXTRACT(inmobiliario_rural_usd_ha, r'^(\d+)')
                    AS FLOAT64
                ) + CAST(
                    REGEXP_EXTRACT(inmobiliario_rural_usd_ha, r'(\d+)$')
                    AS FLOAT64
                )
            ) / 2 AS FLOAT64
        )
    END AS inmobiliario_rural_usd_ha,
    iibb_agro_pct
FROM source
WHERE provincia IS NOT NULL
ORDER BY provincia ASC
