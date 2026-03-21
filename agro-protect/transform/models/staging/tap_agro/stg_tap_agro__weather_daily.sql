{{ config(
    materialized='view',
    tags=['agro', 'tap_agro', 'staging', 'weather']
) }}

WITH source_data AS (
    SELECT *
    FROM {{ source('tap_agro', 'clima_diario_nasa_power') }}
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
    SAFE_CAST(JSON_VALUE(payload, '$.latitude') AS FLOAT64) AS latitude,
    SAFE_CAST(JSON_VALUE(payload, '$.longitude') AS FLOAT64) AS longitude,
    SAFE_CAST(JSON_VALUE(payload, '$.date') AS DATE) AS date,
    JSON_VALUE(payload, '$.x_source') AS source_name,
    JSON_VALUE(payload, '$.x_source_type') AS source_type,
    SAFE_CAST(JSON_VALUE(payload, '$.x_loaded_at') AS TIMESTAMP) AS source_loaded_at,
    SAFE_CAST(JSON_VALUE(payload, '$.T2M_MAX') AS FLOAT64) AS max_air_temp_c,
    SAFE_CAST(JSON_VALUE(payload, '$.T2M_MIN') AS FLOAT64) AS min_air_temp_c,
    SAFE_CAST(JSON_VALUE(payload, '$.T2M') AS FLOAT64) AS avg_air_temp_c,
    SAFE_CAST(JSON_VALUE(payload, '$.T2MDEW') AS FLOAT64) AS dew_point_temp_c,
    SAFE_CAST(JSON_VALUE(payload, '$.T2MWET') AS FLOAT64) AS wet_bulb_temp_c,
    SAFE_CAST(JSON_VALUE(payload, '$.TS') AS FLOAT64) AS soil_surface_temp_c,
    SAFE_CAST(JSON_VALUE(payload, '$.PRECTOTCORR') AS FLOAT64) AS precipitation_mm,
    SAFE_CAST(JSON_VALUE(payload, '$.RH2M') AS FLOAT64) AS relative_humidity_pct,
    SAFE_CAST(JSON_VALUE(payload, '$.QV2M') AS FLOAT64) AS specific_humidity_kg_kg,
    SAFE_CAST(JSON_VALUE(payload, '$.ALLSKY_SFC_SW_DWN') AS FLOAT64) AS solar_radiation_allsky_mj_m2_day,
    SAFE_CAST(JSON_VALUE(payload, '$.CLRSKY_SFC_SW_DWN') AS FLOAT64) AS solar_radiation_clearsky_mj_m2_day,
    SAFE_CAST(JSON_VALUE(payload, '$.WS2M') AS FLOAT64) AS wind_speed_mps,
    SAFE_CAST(JSON_VALUE(payload, '$.WS2M_MAX') AS FLOAT64) AS wind_speed_max_mps,
    SAFE_CAST(JSON_VALUE(payload, '$.WD2M') AS FLOAT64) AS wind_direction_deg,
    SAFE_CAST(JSON_VALUE(payload, '$.PS') AS FLOAT64) AS surface_pressure_kpa,
    SAFE_CAST(JSON_VALUE(payload, '$.CLOUD_AMT') AS FLOAT64) AS cloud_cover_pct,
    SAFE_CAST(_sdc_extracted_at AS TIMESTAMP) AS _sdc_extracted_at,
    SAFE_CAST(_sdc_received_at AS TIMESTAMP) AS _sdc_received_at,
    SAFE_CAST(_sdc_batched_at AS TIMESTAMP) AS _sdc_batched_at,
    SAFE_CAST(_sdc_deleted_at AS TIMESTAMP) AS _sdc_deleted_at,
    SAFE_CAST(_sdc_sequence AS INT64) AS _sdc_sequence,
    SAFE_CAST(_sdc_table_version AS INT64) AS _sdc_table_version
FROM parsed_data
