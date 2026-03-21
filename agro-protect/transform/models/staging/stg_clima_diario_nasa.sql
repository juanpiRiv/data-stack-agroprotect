-- noqa: disable=all
-- Modelo con muchas métricas derivadas; relajar lint global (columnas NASA en mayúsculas, CASE largos).
WITH source_data AS (
    SELECT
        s.*
    FROM {{ source('tap_nasa', 'clima_diario_nasa_power_view') }} AS s
    {% if is_incremental() %}
        WHERE s._sdc_extracted_at > (
            SELECT MAX(t._sdc_extracted_at)
            FROM {{ this }} AS t
        )
    {% endif %}
),

deduped_data AS (
    SELECT *
    FROM (
        SELECT
            sd.*,
            ROW_NUMBER() OVER (
                PARTITION BY sd.location_id, sd.date
                ORDER BY sd._sdc_extracted_at DESC
            ) AS row_num
        FROM source_data AS sd
    )
    WHERE row_num = 1
),

cleaned_data AS (
    SELECT
        -- Location identifiers
        dd.location_id,
        dd.location_name,
        dd.province_name,
        SAFE_CAST(dd.latitude AS FLOAT64) AS latitude,
        SAFE_CAST(dd.longitude AS FLOAT64) AS longitude,

        -- Date
        SAFE_CAST(dd.date AS DATE) AS date,

        -- Temperature variables (Celsius)
        SAFE_CAST(dd.T2M_MAX AS FLOAT64) AS t2m_max,
        SAFE_CAST(dd.T2M_MIN AS FLOAT64) AS t2m_min,
        SAFE_CAST(dd.T2M AS FLOAT64) AS t2m,
        SAFE_CAST(dd.T2MDEW AS FLOAT64) AS t2m_dew,
        SAFE_CAST(dd.T2MWET AS FLOAT64) AS t2m_wet,

        -- Soil and surface temperature
        SAFE_CAST(dd.TS AS FLOAT64) AS soil_temperature,

        -- Precipitation (mm/day)
        SAFE_CAST(dd.PRECTOTCORR AS FLOAT64) AS precipitation_corrected,

        -- Humidity variables
        SAFE_CAST(dd.RH2M AS FLOAT64) AS relative_humidity_2m,
        SAFE_CAST(dd.QV2M AS FLOAT64) AS specific_humidity_2m,

        -- Solar radiation (MJ/m²/day)
        SAFE_CAST(dd.ALLSKY_SFC_SW_DWN AS FLOAT64) AS solar_radiation_allsky,
        SAFE_CAST(dd.CLRSKY_SFC_SW_DWN AS FLOAT64) AS solar_radiation_clearsky,

        -- Wind variables
        SAFE_CAST(dd.WS2M AS FLOAT64) AS wind_speed_2m,
        SAFE_CAST(dd.WS2M_MAX AS FLOAT64) AS wind_speed_2m_max,
        SAFE_CAST(dd.WD2M AS FLOAT64) AS wind_direction_2m,

        -- Pressure
        SAFE_CAST(dd.PS AS FLOAT64) AS surface_pressure,

        -- Cloud cover (%)
        SAFE_CAST(dd.CLOUD_AMT AS FLOAT64) AS cloud_amount,

        -- Metadata
        dd.x_source,
        dd.x_source_type,
        SAFE_CAST(dd.x_loaded_at AS TIMESTAMP) AS loaded_at,

        -- Stitch metadata
        dd._sdc_extracted_at,
        dd._sdc_received_at,
        dd._sdc_batched_at,
        dd._sdc_deleted_at,
        dd._sdc_sequence,
        dd._sdc_table_version
    FROM deduped_data AS dd
),

climate_metrics AS (
    SELECT
        cd.*,

        -- Heat Index (approximate formula for temperatures > 26.7°C)
        CASE
            WHEN cd.t2m > 26.7 AND cd.relative_humidity_2m IS NOT NULL THEN
                -42.379 +
                (2.04901523 * cd.t2m) +
                (10.14333127 * cd.relative_humidity_2m) -
                (0.22475541 * cd.t2m * cd.relative_humidity_2m) -
                (0.00683783 * POWER(cd.t2m, 2)) -
                (0.05481717 * POWER(cd.relative_humidity_2m, 2)) +
                (0.00122874 * POWER(cd.t2m, 2) * cd.relative_humidity_2m) +
                (0.00085282 * cd.t2m * POWER(cd.relative_humidity_2m, 2)) -
                (0.00000199 * POWER(cd.t2m, 2) * POWER(cd.relative_humidity_2m, 2))
            ELSE cd.t2m
        END AS heat_index,

        -- Wind Chill (for temperatures < 10°C)
        CASE
            WHEN cd.t2m < 10 AND cd.wind_speed_2m IS NOT NULL THEN
                13.12 +
                (0.6215 * cd.t2m) -
                (11.37 * POWER(cd.wind_speed_2m, 0.16)) +
                (0.3965 * cd.t2m * POWER(cd.wind_speed_2m, 0.16))
            ELSE cd.t2m
        END AS wind_chill,

        -- Vapor pressure deficit (approximate, kPa)
        CASE
            WHEN cd.t2m_dew IS NOT NULL AND cd.t2m IS NOT NULL THEN
                6.1094 * EXP((17.625 * cd.t2m_dew) / (cd.t2m_dew + 243.04)) -
                6.1094 * EXP((17.625 * cd.t2m) / (cd.t2m + 243.04))
            ELSE NULL
        END AS vapor_pressure_deficit,

        -- Growing degree days (base 10°C, common for crops)
        CASE
            WHEN cd.t2m IS NOT NULL AND cd.t2m_min IS NOT NULL THEN
                GREATEST(0, ((cd.t2m_max + cd.t2m_min) / 2) - 10)
            ELSE NULL
        END AS growing_degree_days_10c,

        -- Frost risk indicator (T_min < 0)
        CASE
            WHEN cd.t2m_min < 0 THEN 1
            WHEN cd.t2m_min IS NULL THEN NULL
            ELSE 0
        END AS frost_risk,

        -- Frost severity (if applicable)
        CASE
            WHEN cd.t2m_min < 0 THEN ABS(cd.t2m_min)
            WHEN cd.t2m_min IS NULL THEN NULL
            ELSE 0
        END AS frost_severity_degrees,

        -- Heat stress indicator (T_max > 35°C)
        CASE
            WHEN cd.t2m_max > 35 THEN 1
            WHEN cd.t2m_max IS NULL THEN NULL
            ELSE 0
        END AS heat_stress_risk,

        -- Drought stress indicator (low relative humidity)
        CASE
            WHEN cd.relative_humidity_2m < 30 THEN 1
            WHEN cd.relative_humidity_2m IS NULL THEN NULL
            ELSE 0
        END AS drought_stress_risk,

        -- Wet/fungal disease risk (high humidity + warm)
        CASE
            WHEN cd.relative_humidity_2m > 80 AND cd.t2m > 15 THEN 1
            WHEN cd.relative_humidity_2m IS NULL OR cd.t2m IS NULL THEN NULL
            ELSE 0
        END AS fungal_disease_risk,

        -- Excessive moisture indicator
        CASE
            WHEN cd.precipitation_corrected > 25 THEN 1
            WHEN cd.precipitation_corrected IS NULL THEN NULL
            ELSE 0
        END AS excessive_moisture_risk
    FROM cleaned_data AS cd
),

data_quality_flags AS (
    SELECT
        cm.*,

        -- Count missing critical variables
        (CASE WHEN cm.t2m IS NULL THEN 1 ELSE 0 END +
         CASE WHEN cm.t2m_min IS NULL THEN 1 ELSE 0 END +
         CASE WHEN cm.t2m_max IS NULL THEN 1 ELSE 0 END +
         CASE WHEN cm.precipitation_corrected IS NULL THEN 1 ELSE 0 END) AS critical_null_count,

        -- Flag records with > 50% variables missing
        CASE
            WHEN (
                CASE WHEN cm.t2m IS NULL THEN 1 ELSE 0 END +
                CASE WHEN cm.t2m_min IS NULL THEN 1 ELSE 0 END +
                CASE WHEN cm.t2m_max IS NULL THEN 1 ELSE 0 END +
                CASE WHEN cm.t2m_dew IS NULL THEN 1 ELSE 0 END +
                CASE WHEN cm.soil_temperature IS NULL THEN 1 ELSE 0 END +
                CASE WHEN cm.precipitation_corrected IS NULL THEN 1 ELSE 0 END +
                CASE WHEN cm.relative_humidity_2m IS NULL THEN 1 ELSE 0 END +
                CASE WHEN cm.wind_speed_2m IS NULL THEN 1 ELSE 0 END
            ) > 4 THEN 1
            ELSE 0
        END AS has_high_missing_data,

        -- Flag temperature inconsistencies
        CASE
            WHEN cm.t2m_max IS NOT NULL AND cm.t2m_min IS NOT NULL
                AND cm.t2m_max < cm.t2m_min THEN 1
            ELSE 0
        END AS temperature_inconsistent,

        -- Flag extreme outliers (simple z-score approach)
        CASE
            WHEN cm.t2m > 50 OR cm.t2m < -50 THEN 1
            ELSE 0
        END AS temperature_outlier,

        CASE
            WHEN cm.precipitation_corrected > 400 THEN 1
            ELSE 0
        END AS precipitation_outlier
    FROM climate_metrics AS cm
),

final AS (
    SELECT
        -- Location and time
        dqf.location_id,
        dqf.location_name,
        dqf.province_name,
        dqf.latitude,
        dqf.longitude,
        dqf.date,

        -- Year, month, week for aggregation
        EXTRACT(YEAR FROM dqf.date) AS year,
        EXTRACT(MONTH FROM dqf.date) AS month,
        EXTRACT(QUARTER FROM dqf.date) AS quarter,
        DATE_TRUNC(dqf.date, WEEK(MONDAY)) AS week_start,
        DATE_TRUNC(dqf.date, MONTH) AS month_start,

        -- Core weather variables
        dqf.t2m_max,
        dqf.t2m_min,
        dqf.t2m,
        dqf.t2m_dew,
        dqf.t2m_wet,
        dqf.soil_temperature,
        dqf.precipitation_corrected,
        dqf.relative_humidity_2m,
        dqf.specific_humidity_2m,
        dqf.solar_radiation_allsky,
        dqf.solar_radiation_clearsky,
        dqf.wind_speed_2m,
        dqf.wind_speed_2m_max,
        dqf.wind_direction_2m,
        dqf.surface_pressure,
        dqf.cloud_amount,

        -- Derived agronomic metrics
        dqf.heat_index,
        dqf.wind_chill,
        dqf.vapor_pressure_deficit,
        dqf.growing_degree_days_10c,

        -- Risk indicators
        dqf.frost_risk,
        dqf.frost_severity_degrees,
        dqf.heat_stress_risk,
        dqf.drought_stress_risk,
        dqf.fungal_disease_risk,
        dqf.excessive_moisture_risk,

        -- Data quality flags
        dqf.critical_null_count,
        dqf.has_high_missing_data,
        dqf.temperature_inconsistent,
        dqf.temperature_outlier,
        dqf.precipitation_outlier,

        -- Metadata (most important for incremental processing)
        dqf.x_source,
        dqf.x_source_type,
        dqf.loaded_at,
        dqf._sdc_extracted_at,
        dqf._sdc_received_at,
        dqf._sdc_batched_at,
        dqf._sdc_deleted_at,
        dqf._sdc_sequence,
        dqf._sdc_table_version
    FROM data_quality_flags AS dqf
)

SELECT *
FROM final
WHERE location_id IS NOT NULL AND date IS NOT NULL
