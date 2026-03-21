WITH coverage AS (
    SELECT
        SAFE_DIVIDE(
            (SELECT COUNT(*) FROM {{ ref('app_location_snapshot') }}),
            NULLIF((SELECT COUNT(*) FROM {{ ref('dim_location') }}), 0)
        ) AS coverage_ratio
)

SELECT coverage_ratio
FROM coverage
WHERE coverage_ratio < 0.95
