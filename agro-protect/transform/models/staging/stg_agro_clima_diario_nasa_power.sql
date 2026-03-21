{{ config(
    materialized='view',
    tags=['agro', 'tap_agro']
) }}

-- Misma lógica que stg_agro_locations: `data` como JSON (no soporta data.*).
WITH src AS (
    SELECT * FROM {{ source('tap_agro', 'clima_diario_nasa_power') }}
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
    SAFE_CAST(JSON_VALUE(_j, '$.date') AS DATE) AS date,
    JSON_VALUE(_j, '$.x_source') AS x_source,
    JSON_VALUE(_j, '$.x_source_type') AS x_source_type,
    SAFE_CAST(JSON_VALUE(_j, '$.x_loaded_at') AS TIMESTAMP) AS x_loaded_at,
    SAFE_CAST(JSON_VALUE(_j, '$.T2M_MAX') AS FLOAT64) AS t2m_max,
    SAFE_CAST(JSON_VALUE(_j, '$.T2M_MIN') AS FLOAT64) AS t2m_min,
    SAFE_CAST(JSON_VALUE(_j, '$.T2M') AS FLOAT64) AS t2m,
    SAFE_CAST(JSON_VALUE(_j, '$.T2MDEW') AS FLOAT64) AS t2m_dew,
    SAFE_CAST(JSON_VALUE(_j, '$.T2MWET') AS FLOAT64) AS t2m_wet,
    SAFE_CAST(JSON_VALUE(_j, '$.TS') AS FLOAT64) AS soil_temperature,
    SAFE_CAST(JSON_VALUE(_j, '$.PRECTOTCORR') AS FLOAT64) AS precipitation_corrected,
    SAFE_CAST(JSON_VALUE(_j, '$.RH2M') AS FLOAT64) AS relative_humidity_2m,
    SAFE_CAST(JSON_VALUE(_j, '$.QV2M') AS FLOAT64) AS specific_humidity_2m,
    SAFE_CAST(JSON_VALUE(_j, '$.ALLSKY_SFC_SW_DWN') AS FLOAT64) AS solar_radiation_allsky,
    SAFE_CAST(JSON_VALUE(_j, '$.CLRSKY_SFC_SW_DWN') AS FLOAT64) AS solar_radiation_clearsky,
    SAFE_CAST(JSON_VALUE(_j, '$.WS2M') AS FLOAT64) AS wind_speed_2m,
    SAFE_CAST(JSON_VALUE(_j, '$.WS2M_MAX') AS FLOAT64) AS wind_speed_2m_max,
    SAFE_CAST(JSON_VALUE(_j, '$.WD2M') AS FLOAT64) AS wind_direction_2m,
    SAFE_CAST(JSON_VALUE(_j, '$.PS') AS FLOAT64) AS surface_pressure,
    SAFE_CAST(JSON_VALUE(_j, '$.CLOUD_AMT') AS FLOAT64) AS cloud_amount
FROM j
