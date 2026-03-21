{{ config(
    tags=['agro', 'mart', 'dimension'],
    cluster_by=['province_key']
) }}

WITH catalog_locations AS (
    SELECT
        location_id,
        location_name,
        province_name,
        province_key,
        department_name,
        department_key,
        municipality_name,
        latitude,
        longitude,
        elevation_m,
        country_code,
        is_active,
        source_catalog,
        source_type,
        source_loaded_at,
        record_loaded_at,
        TRUE AS is_catalog_location
    FROM {{ ref('int_location__current') }}
),

weather_only_locations AS (
    SELECT *
    FROM (
        SELECT
            weather.location_id,
            weather.location_name,
            weather.province_name,
            weather.province_key,
            weather.latitude,
            weather.longitude,
            weather.country_code,
            weather.is_active_location AS is_active,
            weather.source_type,
            weather.source_loaded_at,
            weather.record_loaded_at,
            FALSE AS is_catalog_location,
            CAST(NULL AS STRING) AS department_name,
            CAST(NULL AS STRING) AS department_key,
            CAST(NULL AS STRING) AS municipality_name,
            CAST(NULL AS FLOAT64) AS elevation_m,
            CAST('weather_fallback' AS STRING) AS source_catalog,
            ROW_NUMBER() OVER (
                PARTITION BY weather.location_id
                ORDER BY weather.record_loaded_at DESC, weather.date DESC
            ) AS row_number
        FROM {{ ref('int_weather__daily_base') }} AS weather
        LEFT JOIN {{ ref('int_location__current') }} AS catalog
            ON weather.location_id = catalog.location_id
        WHERE catalog.location_id IS NULL
    )
    WHERE row_number = 1
)

SELECT
    location_id,
    location_name,
    province_name,
    province_key,
    department_name,
    department_key,
    municipality_name,
    latitude,
    longitude,
    elevation_m,
    country_code,
    is_active,
    source_catalog,
    source_type,
    source_loaded_at,
    record_loaded_at,
    is_catalog_location
FROM catalog_locations

UNION ALL

SELECT
    location_id,
    location_name,
    province_name,
    province_key,
    department_name,
    department_key,
    municipality_name,
    latitude,
    longitude,
    elevation_m,
    country_code,
    is_active,
    source_catalog,
    source_type,
    source_loaded_at,
    record_loaded_at,
    is_catalog_location
FROM weather_only_locations
