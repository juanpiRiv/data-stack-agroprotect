{{ config(
    materialized='view',
    tags=['agro', 'tap_agro']
) }}

-- target-bigquery puede cargar `data` como JSON; `data.*` solo sirve para STRUCT/RECORD.
-- Normalizamos a JSON y extraemos campos (también válido si `data` ya es RECORD).
WITH src AS (
    SELECT * FROM {{ source('tap_agro', 'locations') }}
),

j AS (
    SELECT
        * EXCEPT (data),
        PARSE_JSON(TO_JSON_STRING(data)) AS _j
    FROM src
)

SELECT
    * EXCEPT (_j),
    JSON_VALUE(_j, '$.location_id') AS location_id,
    JSON_VALUE(_j, '$.location_name') AS location_name,
    JSON_VALUE(_j, '$.province_name') AS province_name,
    SAFE_CAST(JSON_VALUE(_j, '$.latitude') AS FLOAT64) AS latitude,
    SAFE_CAST(JSON_VALUE(_j, '$.longitude') AS FLOAT64) AS longitude,
    JSON_VALUE(_j, '$.country_code') AS country_code,
    SAFE_CAST(JSON_VALUE(_j, '$.is_active') AS BOOL) AS is_active
FROM j
