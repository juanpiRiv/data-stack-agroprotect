{{ config(tags=['agro', 'weather', 'intermediate']) }}

WITH weather_source AS (
    SELECT
        weather.*,
        (
            CASE WHEN weather.max_air_temp_c IS NOT NULL THEN 1 ELSE 0 END
            + CASE WHEN weather.min_air_temp_c IS NOT NULL THEN 1 ELSE 0 END
            + CASE WHEN weather.avg_air_temp_c IS NOT NULL THEN 1 ELSE 0 END
            + CASE WHEN weather.dew_point_temp_c IS NOT NULL THEN 1 ELSE 0 END
            + CASE WHEN weather.wet_bulb_temp_c IS NOT NULL THEN 1 ELSE 0 END
            + CASE WHEN weather.soil_surface_temp_c IS NOT NULL THEN 1 ELSE 0 END
            + CASE WHEN weather.precipitation_mm IS NOT NULL THEN 1 ELSE 0 END
            + CASE WHEN weather.relative_humidity_pct IS NOT NULL THEN 1 ELSE 0 END
            + CASE WHEN weather.specific_humidity_kg_kg IS NOT NULL THEN 1 ELSE 0 END
            + CASE WHEN weather.solar_radiation_allsky_mj_m2_day IS NOT NULL THEN 1 ELSE 0 END
            + CASE WHEN weather.solar_radiation_clearsky_mj_m2_day IS NOT NULL THEN 1 ELSE 0 END
            + CASE WHEN weather.wind_speed_mps IS NOT NULL THEN 1 ELSE 0 END
            + CASE WHEN weather.wind_speed_max_mps IS NOT NULL THEN 1 ELSE 0 END
            + CASE WHEN weather.wind_direction_deg IS NOT NULL THEN 1 ELSE 0 END
            + CASE WHEN weather.surface_pressure_kpa IS NOT NULL THEN 1 ELSE 0 END
            + CASE WHEN weather.cloud_cover_pct IS NOT NULL THEN 1 ELSE 0 END
        ) AS weather_variable_non_null_count,
        COALESCE(
            weather.source_loaded_at,
            weather._sdc_extracted_at,
            weather._sdc_received_at
        ) AS record_loaded_at
    FROM {{ ref('stg_tap_agro__weather_daily') }} AS weather
    WHERE
        weather.location_id IS NOT NULL
        AND weather.date IS NOT NULL
        AND weather._sdc_deleted_at IS NULL
),

deduplicated_weather AS (
    SELECT *
    FROM (
        SELECT
            weather_source.*,
            ROW_NUMBER() OVER (
                PARTITION BY weather_source.location_id, weather_source.date
                ORDER BY
                    weather_source.weather_variable_non_null_count DESC,
                    weather_source.record_loaded_at DESC,
                    weather_source._sdc_received_at DESC,
                    weather_source._sdc_extracted_at DESC,
                    weather_source._sdc_sequence DESC
            ) AS row_number
        FROM weather_source
    )
    WHERE row_number = 1
),

joined_weather AS (
    SELECT
        deduplicated_weather.location_id,
        location_dim.is_active AS is_active_location,
        deduplicated_weather.date,
        deduplicated_weather.source_name,
        deduplicated_weather.source_type,
        deduplicated_weather.source_loaded_at,
        deduplicated_weather.record_loaded_at,
        deduplicated_weather.max_air_temp_c,
        deduplicated_weather.min_air_temp_c,
        deduplicated_weather.avg_air_temp_c,
        deduplicated_weather.dew_point_temp_c,
        deduplicated_weather.wet_bulb_temp_c,
        deduplicated_weather.soil_surface_temp_c,
        deduplicated_weather.precipitation_mm,
        deduplicated_weather.relative_humidity_pct,
        deduplicated_weather.specific_humidity_kg_kg,
        deduplicated_weather.solar_radiation_allsky_mj_m2_day,
        deduplicated_weather.solar_radiation_clearsky_mj_m2_day,
        deduplicated_weather.wind_speed_mps,
        deduplicated_weather.wind_speed_max_mps,
        deduplicated_weather.wind_direction_deg,
        deduplicated_weather.surface_pressure_kpa,
        deduplicated_weather.cloud_cover_pct,
        deduplicated_weather.weather_variable_non_null_count,
        deduplicated_weather._sdc_extracted_at,
        deduplicated_weather._sdc_received_at,
        deduplicated_weather._sdc_batched_at,
        deduplicated_weather._sdc_deleted_at,
        deduplicated_weather._sdc_sequence,
        deduplicated_weather._sdc_table_version,
        COALESCE(location_dim.location_name, deduplicated_weather.location_name) AS location_name,
        COALESCE(location_dim.province_name, deduplicated_weather.province_name) AS province_name,
        COALESCE(location_dim.province_key, deduplicated_weather.province_key) AS province_key,
        COALESCE(location_dim.latitude, deduplicated_weather.latitude) AS latitude,
        COALESCE(location_dim.longitude, deduplicated_weather.longitude) AS longitude,
        COALESCE(location_dim.country_code, 'AR') AS country_code,
        location_dim.location_id IS NOT NULL AS has_location_dimension
    FROM deduplicated_weather
    LEFT JOIN {{ ref('int_location__current') }} AS location_dim
        ON deduplicated_weather.location_id = location_dim.location_id
)

SELECT *
FROM joined_weather
