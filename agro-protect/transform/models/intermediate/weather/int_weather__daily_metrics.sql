{{ config(tags=['agro', 'weather', 'intermediate']) }}

WITH weather_base AS (
    SELECT
        weather.*,
        ((weather.avg_air_temp_c * 9.0 / 5.0) + 32.0) AS avg_air_temp_f,
        (weather.wind_speed_mps * 3.6) AS wind_speed_kph,
        0.6108 * EXP(
            (17.27 * weather.avg_air_temp_c) / (weather.avg_air_temp_c + 237.3)
        ) AS saturation_vapor_pressure_kpa,
        0.6108 * EXP(
            (17.27 * weather.dew_point_temp_c) / (weather.dew_point_temp_c + 237.3)
        ) AS actual_vapor_pressure_kpa
    FROM {{ ref('int_weather__daily_base') }} AS weather
)

SELECT
    weather_base.location_id,
    weather_base.location_name,
    weather_base.province_name,
    weather_base.province_key,
    weather_base.latitude,
    weather_base.longitude,
    weather_base.country_code,
    weather_base.is_active_location,
    weather_base.date,
    weather_base.source_name,
    weather_base.source_type,
    weather_base.source_loaded_at,
    weather_base.record_loaded_at,
    weather_base.max_air_temp_c,
    weather_base.min_air_temp_c,
    weather_base.avg_air_temp_c,
    weather_base.dew_point_temp_c,
    weather_base.wet_bulb_temp_c,
    weather_base.soil_surface_temp_c,
    weather_base.precipitation_mm,
    weather_base.relative_humidity_pct,
    weather_base.specific_humidity_kg_kg,
    weather_base.solar_radiation_allsky_mj_m2_day,
    weather_base.solar_radiation_clearsky_mj_m2_day,
    weather_base.wind_speed_mps,
    weather_base.wind_speed_max_mps,
    weather_base.wind_direction_deg,
    weather_base.surface_pressure_kpa,
    weather_base.cloud_cover_pct,
    weather_base.weather_variable_non_null_count,
    weather_base.has_location_dimension,
    weather_base._sdc_extracted_at,
    weather_base._sdc_received_at,
    weather_base._sdc_batched_at,
    weather_base._sdc_deleted_at,
    weather_base._sdc_sequence,
    weather_base._sdc_table_version,
    EXTRACT(YEAR FROM weather_base.date) AS calendar_year,
    EXTRACT(MONTH FROM weather_base.date) AS calendar_month,
    EXTRACT(QUARTER FROM weather_base.date) AS calendar_quarter,
    DATE_TRUNC(weather_base.date, WEEK (MONDAY)) AS week_start,
    DATE_TRUNC(weather_base.date, MONTH) AS month_start,
    CASE
        WHEN EXTRACT(MONTH FROM weather_base.date) >= 7 THEN EXTRACT(YEAR FROM weather_base.date)
        ELSE EXTRACT(YEAR FROM weather_base.date) - 1
    END AS campaign_start_year,
    CONCAT(
        CAST(
            CASE
                WHEN EXTRACT(MONTH FROM weather_base.date) >= 7 THEN EXTRACT(YEAR FROM weather_base.date)
                ELSE EXTRACT(YEAR FROM weather_base.date) - 1
            END AS STRING
        ),
        '/',
        CAST(
            CASE
                WHEN EXTRACT(MONTH FROM weather_base.date) >= 7 THEN EXTRACT(YEAR FROM weather_base.date) + 1
                ELSE EXTRACT(YEAR FROM weather_base.date)
            END AS STRING
        )
    ) AS campaign_name,
    weather_base.max_air_temp_c - weather_base.min_air_temp_c AS temp_range_c,
    weather_base.solar_radiation_clearsky_mj_m2_day
    - weather_base.solar_radiation_allsky_mj_m2_day AS clear_sky_radiation_gap_mj_m2_day,
    CASE
        WHEN weather_base.avg_air_temp_c IS NULL THEN NULL
        WHEN weather_base.relative_humidity_pct IS NULL THEN weather_base.avg_air_temp_c
        WHEN weather_base.avg_air_temp_f < 80 OR weather_base.relative_humidity_pct < 40
            THEN
                weather_base.avg_air_temp_c
        ELSE (
            (
                -42.379
                + (2.04901523 * weather_base.avg_air_temp_f)
                + (10.14333127 * weather_base.relative_humidity_pct)
                - (0.22475541 * weather_base.avg_air_temp_f * weather_base.relative_humidity_pct)
                - (0.00683783 * POW(weather_base.avg_air_temp_f, 2))
                - (0.05481717 * POW(weather_base.relative_humidity_pct, 2))
                + (0.00122874 * POW(weather_base.avg_air_temp_f, 2) * weather_base.relative_humidity_pct)
                + (0.00085282 * weather_base.avg_air_temp_f * POW(weather_base.relative_humidity_pct, 2))
                - (
                    0.00000199 * POW(weather_base.avg_air_temp_f, 2)
                    * POW(weather_base.relative_humidity_pct, 2)
                )
            ) - 32.0
        ) * 5.0 / 9.0
    END AS heat_index_c,
    CASE
        WHEN weather_base.avg_air_temp_c IS NULL THEN NULL
        WHEN weather_base.wind_speed_mps IS NULL THEN weather_base.avg_air_temp_c
        WHEN weather_base.avg_air_temp_c > 10 OR weather_base.wind_speed_kph < 4.8
            THEN
                weather_base.avg_air_temp_c
        ELSE
            13.12
            + (0.6215 * weather_base.avg_air_temp_c)
            - (11.37 * POW(weather_base.wind_speed_kph, 0.16))
            + (0.3965 * weather_base.avg_air_temp_c * POW(weather_base.wind_speed_kph, 0.16))
    END AS wind_chill_c,
    CASE
        WHEN weather_base.avg_air_temp_c IS NOT NULL AND weather_base.dew_point_temp_c IS NOT NULL
            THEN
                GREATEST(
                    weather_base.saturation_vapor_pressure_kpa - weather_base.actual_vapor_pressure_kpa,
                    0.0
                )
    END AS vpd_kpa,
    CASE
        WHEN weather_base.max_air_temp_c IS NOT NULL AND weather_base.min_air_temp_c IS NOT NULL
            THEN
                GREATEST(((weather_base.max_air_temp_c + weather_base.min_air_temp_c) / 2.0) - 10.0, 0.0)
    END AS gdd_base_10_c_days
FROM weather_base
