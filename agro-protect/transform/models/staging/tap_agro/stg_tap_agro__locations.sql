{{ config(
    materialized='view',
    tags=['agro', 'tap_agro', 'staging']
) }}

WITH source_data AS (
    SELECT *
    FROM {{ source('tap_agro', 'locations') }}
),

parsed_data AS (
    SELECT
        * EXCEPT (data),
        PARSE_JSON(TO_JSON_STRING(data)) AS payload
    FROM source_data
)

SELECT
    JSON_VALUE(payload, '$.location_id') AS location_id,
    JSON_VALUE(payload, '$.location_name') AS location_name,
    JSON_VALUE(payload, '$.province_name') AS province_name,
    {{ normalize_text("JSON_VALUE(payload, '$.province_name')") }} AS province_key,
    JSON_VALUE(payload, '$.department_name') AS department_name,
    {{ normalize_text("JSON_VALUE(payload, '$.department_name')") }} AS department_key,
    JSON_VALUE(payload, '$.municipality_name') AS municipality_name,
    SAFE_CAST(JSON_VALUE(payload, '$.latitude') AS FLOAT64) AS latitude,
    SAFE_CAST(JSON_VALUE(payload, '$.longitude') AS FLOAT64) AS longitude,
    SAFE_CAST(JSON_VALUE(payload, '$.elevation') AS FLOAT64) AS elevation_m,
    JSON_VALUE(payload, '$.country_code') AS country_code,
    SAFE_CAST(JSON_VALUE(payload, '$.is_active') AS BOOL) AS is_active,
    JSON_VALUE(payload, '$.source_catalog') AS source_catalog,
    JSON_VALUE(payload, '$.x_source_type') AS source_type,
    SAFE_CAST(JSON_VALUE(payload, '$.x_loaded_at') AS TIMESTAMP) AS source_loaded_at,
    SAFE_CAST(_sdc_extracted_at AS TIMESTAMP) AS _sdc_extracted_at,
    SAFE_CAST(_sdc_received_at AS TIMESTAMP) AS _sdc_received_at,
    SAFE_CAST(_sdc_batched_at AS TIMESTAMP) AS _sdc_batched_at,
    SAFE_CAST(_sdc_deleted_at AS TIMESTAMP) AS _sdc_deleted_at,
    SAFE_CAST(_sdc_sequence AS INT64) AS _sdc_sequence,
    SAFE_CAST(_sdc_table_version AS INT64) AS _sdc_table_version
FROM parsed_data
