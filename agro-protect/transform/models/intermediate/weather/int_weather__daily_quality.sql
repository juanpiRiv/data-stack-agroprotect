{{ config(tags=['agro', 'weather', 'intermediate']) }}

WITH latest_weather_date AS (
    SELECT MAX(date) AS latest_date
    FROM {{ ref('int_weather__daily_metrics') }}
),

quality_flags AS (
    SELECT
        metrics.*,
        (
            CASE WHEN metrics.avg_air_temp_c IS NULL THEN 1 ELSE 0 END
            + CASE WHEN metrics.min_air_temp_c IS NULL THEN 1 ELSE 0 END
            + CASE WHEN metrics.max_air_temp_c IS NULL THEN 1 ELSE 0 END
            + CASE WHEN metrics.precipitation_mm IS NULL THEN 1 ELSE 0 END
        ) AS critical_null_count,
        COALESCE(metrics.weather_variable_non_null_count < 8, FALSE) AS has_high_missing_data,
        COALESCE(
            metrics.min_air_temp_c IS NOT NULL
            AND metrics.max_air_temp_c IS NOT NULL
            AND metrics.min_air_temp_c > metrics.max_air_temp_c,
            FALSE
        ) AS temperature_inconsistent,
        COALESCE(
            metrics.avg_air_temp_c IS NOT NULL
            AND (metrics.avg_air_temp_c > 50 OR metrics.avg_air_temp_c < -50),
            FALSE
        ) AS temperature_outlier,
        COALESCE(
            metrics.precipitation_mm IS NOT NULL AND metrics.precipitation_mm > 400,
            FALSE
        ) AS precipitation_outlier,
        COALESCE(
            metrics.wind_speed_mps IS NOT NULL AND metrics.wind_speed_mps > 50,
            FALSE
        ) AS wind_outlier,
        COALESCE(
            metrics.solar_radiation_allsky_mj_m2_day IS NOT NULL
            AND metrics.solar_radiation_clearsky_mj_m2_day IS NOT NULL
            AND metrics.solar_radiation_allsky_mj_m2_day > metrics.solar_radiation_clearsky_mj_m2_day,
            FALSE
        ) AS radiation_inconsistent,
        CASE
            WHEN metrics.min_air_temp_c IS NULL THEN NULL
            WHEN metrics.min_air_temp_c < 0 THEN TRUE
            ELSE FALSE
        END AS frost_day,
        CASE
            WHEN metrics.max_air_temp_c IS NULL THEN NULL
            WHEN metrics.max_air_temp_c > 35 THEN TRUE
            ELSE FALSE
        END AS heat_stress_day,
        CASE
            WHEN metrics.precipitation_mm IS NULL THEN NULL
            WHEN metrics.precipitation_mm > 25 THEN TRUE
            ELSE FALSE
        END AS heavy_rain_day,
        CASE
            WHEN metrics.precipitation_mm IS NULL OR metrics.relative_humidity_pct IS NULL THEN NULL
            WHEN metrics.precipitation_mm < 1 AND metrics.relative_humidity_pct < 35 THEN TRUE
            ELSE FALSE
        END AS dry_day,
        CASE
            WHEN metrics.relative_humidity_pct IS NULL OR metrics.avg_air_temp_c IS NULL THEN NULL
            WHEN
                metrics.relative_humidity_pct >= 80
                AND metrics.avg_air_temp_c BETWEEN 15 AND 30
                AND COALESCE(metrics.precipitation_mm, 0) > 0 THEN TRUE
            ELSE FALSE
        END AS fungal_risk_day
    FROM {{ ref('int_weather__daily_metrics') }} AS metrics
)

SELECT
    quality_flags.*,
    COALESCE(
        quality_flags.date = latest_weather_date.latest_date
        AND quality_flags.critical_null_count > 0,
        FALSE
    ) AS is_partial_latest_day,
    NOT COALESCE(
        quality_flags.has_high_missing_data
        OR quality_flags.temperature_inconsistent
        OR quality_flags.temperature_outlier
        OR quality_flags.precipitation_outlier
        OR quality_flags.wind_outlier
        OR quality_flags.radiation_inconsistent,
        FALSE
    ) AS is_quality_approved
FROM quality_flags
CROSS JOIN latest_weather_date
