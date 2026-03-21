{{ config(tags=['agro', 'locations', 'intermediate']) }}

WITH ranked_locations AS (
    SELECT
        locations.*,
        COALESCE(
            locations.source_loaded_at,
            locations._sdc_extracted_at,
            locations._sdc_received_at
        ) AS record_loaded_at,
        ROW_NUMBER() OVER (
            PARTITION BY locations.location_id
            ORDER BY
                CASE WHEN locations._sdc_deleted_at IS NULL THEN 0 ELSE 1 END,
                COALESCE(
                    locations.source_loaded_at,
                    locations._sdc_extracted_at,
                    locations._sdc_received_at
                ) DESC,
                locations._sdc_received_at DESC,
                locations._sdc_extracted_at DESC,
                locations._sdc_sequence DESC
        ) AS row_number
    FROM {{ ref('stg_tap_agro__locations') }} AS locations
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
    _sdc_extracted_at,
    _sdc_received_at,
    _sdc_batched_at,
    _sdc_deleted_at,
    _sdc_sequence,
    _sdc_table_version
FROM ranked_locations
WHERE
    row_number = 1
    AND _sdc_deleted_at IS NULL
