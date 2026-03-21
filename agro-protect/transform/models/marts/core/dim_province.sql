{{ config(tags=['agro', 'mart', 'dimension']) }}

WITH province_sources AS (
    SELECT
        province_key,
        province_name,
        'weather' AS source_name
    FROM {{ ref('int_location__current') }}

    UNION ALL

    SELECT
        province_key,
        province_name,
        'tax' AS source_name
    FROM {{ ref('int_tax__province') }}

    UNION ALL

    SELECT
        province_key,
        province_name,
        'yield' AS source_name
    FROM {{ ref('int_yield__province_campaign') }}
),

ranked_sources AS (
    SELECT
        province_sources.*,
        ROW_NUMBER() OVER (
            PARTITION BY province_sources.province_key
            ORDER BY
                CASE province_sources.source_name
                    WHEN 'weather' THEN 1
                    WHEN 'tax' THEN 2
                    ELSE 3
                END,
                province_sources.province_name
        ) AS row_number
    FROM province_sources
    WHERE
        province_sources.province_key IS NOT NULL
        AND province_sources.province_key != ''
),

coverage AS (
    SELECT
        province_key,
        LOGICAL_OR(source_name = 'weather') AS has_weather_data,
        LOGICAL_OR(source_name = 'tax') AS has_tax_data,
        LOGICAL_OR(source_name = 'yield') AS has_yield_data
    FROM province_sources
    GROUP BY province_key
)

SELECT
    ranked_sources.province_key,
    ranked_sources.province_name,
    coverage.has_weather_data,
    coverage.has_tax_data,
    coverage.has_yield_data
FROM ranked_sources
INNER JOIN coverage
    ON ranked_sources.province_key = coverage.province_key
WHERE ranked_sources.row_number = 1
