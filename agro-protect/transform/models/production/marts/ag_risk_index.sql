{{ config(
    materialized='table',
    tags=['marts', 'risk_analysis']
) }}

WITH climate_data AS (
    SELECT
        location_id,
        location_name,
        province_name,
        latitude,
        longitude,
        date,
        year,
        month,
        quarter,
        t2m_max,
        t2m_min,
        t2m,
        precipitation_corrected,
        relative_humidity_2m,
        frost_risk,
        heat_stress_risk,
        drought_stress_risk,
        fungal_disease_risk,
        excessive_moisture_risk,
        critical_null_count
    FROM {{ ref('stg_clima_diario_nasa') }}
    WHERE date >= CURRENT_DATE() - 90  -- Last 90 days of climate data
),

-- Aggregate climate data by location (90-day period)
climate_aggregated AS (
    SELECT
        cd.location_id,
        cd.location_name,
        cd.province_name,
        cd.latitude,
        cd.longitude,
        
        -- Climate metrics
        MAX(cd.t2m_max) AS max_temperature,
        MIN(cd.t2m_min) AS min_temperature,
        AVG(cd.t2m) AS avg_temperature,
        SUM(cd.precipitation_corrected) AS total_precipitation_90d,
        AVG(cd.relative_humidity_2m) AS avg_humidity,
        
        -- Climate risk percentages (days with risk / total days)
        (SUM(CASE WHEN cd.frost_risk = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100) AS frost_risk_pct,
        (SUM(CASE WHEN cd.heat_stress_risk = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100) AS heat_stress_risk_pct,
        (SUM(CASE WHEN cd.drought_stress_risk = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100) AS drought_stress_risk_pct,
        (SUM(CASE WHEN cd.fungal_disease_risk = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100) AS fungal_disease_risk_pct,
        (SUM(CASE WHEN cd.excessive_moisture_risk = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100) AS excess_moisture_risk_pct
    FROM climate_data AS cd
    WHERE cd.critical_null_count < 2  -- Only good quality records
    GROUP BY
        cd.location_id,
        cd.location_name,
        cd.province_name,
        cd.latitude,
        cd.longitude
),

-- Productivity data (latest year)
productivity_data AS (
    SELECT
        r.provincia,
        AVG(r.rendimiento_kgxha) AS avg_yield,
        MIN(r.rendimiento_kgxha) AS min_yield,
        MAX(r.rendimiento_kgxha) AS max_yield,
        STDDEV(r.rendimiento_kgxha) AS yield_stddev,
        SUM(r.superficie_sembrada_ha) AS total_sown_area,
        SUM(r.superficie_cosechada_ha) AS total_harvested_area,
        SUM(r.produccion_tm) AS total_production,
        AVG(r.harvest_ratio_pct) AS avg_harvest_ratio,
        MAX(r.anio) AS latest_year
    FROM {{ ref('stg_rendimiento_agro') }} AS r
    GROUP BY r.provincia
),

-- Normalize productivity metrics to risk scores (0-100)
productivity_risk AS (
    SELECT
        p.provincia,
        p.avg_yield,
        p.latest_year,
        -- Low yield = high risk (0-100 scale)
        CASE
            WHEN p.avg_yield IS NOT NULL
            THEN 100 - (
                (p.avg_yield - MIN(p.avg_yield) OVER ()) /
                (MAX(p.avg_yield) OVER () - MIN(p.avg_yield) OVER () + 1) * 100
            )
            ELSE NULL
        END AS yield_risk_score,
        -- Low harvest ratio = high risk
        CASE
            WHEN p.avg_harvest_ratio IS NOT NULL
            THEN (1 - (p.avg_harvest_ratio / 100)) * 100
            ELSE NULL
        END AS harvest_efficiency_risk_score
    FROM productivity_data AS p
),

-- Tax data
tax_data AS (
    SELECT
        provincia,
        inmobiliario_rural_usd_ha,
        iibb_agro_pct
    FROM {{ ref('stg_impuestos_agro_argentina') }}
),

-- Normalize tax metrics to risk scores (0-100)
tax_risk AS (
    SELECT
        t.provincia,
        t.inmobiliario_rural_usd_ha,
        t.iibb_agro_pct,
        -- High property tax = high risk
        CASE
            WHEN t.inmobiliario_rural_usd_ha IS NOT NULL
            THEN (
                (t.inmobiliario_rural_usd_ha - MIN(t.inmobiliario_rural_usd_ha) OVER ()) /
                (MAX(t.inmobiliario_rural_usd_ha) OVER () - MIN(t.inmobiliario_rural_usd_ha) OVER () + 1) * 100
            )
            ELSE NULL
        END AS property_tax_risk_score,
        -- High income tax = high risk
        COALESCE(t.iibb_agro_pct * 100, 0) AS income_tax_risk_score
    FROM tax_data AS t
),

-- Join all data
joined_data AS (
    SELECT
        ca.location_id,
        ca.location_name,
        ca.province_name,
        ca.latitude,
        ca.longitude,
        
        -- Climate components
        ca.max_temperature,
        ca.min_temperature,
        ca.avg_temperature,
        ca.total_precipitation_90d,
        ca.avg_humidity,
        ca.frost_risk_pct,
        ca.heat_stress_risk_pct,
        ca.drought_stress_risk_pct,
        ca.fungal_disease_risk_pct,
        ca.excess_moisture_risk_pct,
        
        -- Climate risk score (weighted components)
        (
            ca.frost_risk_pct * 0.25 +
            ca.heat_stress_risk_pct * 0.25 +
            ca.drought_stress_risk_pct * 0.20 +
            ca.fungal_disease_risk_pct * 0.15 +
            ca.excess_moisture_risk_pct * 0.15
        ) AS climate_risk_score,
        
        -- Productivity components
        pr.avg_yield,
        pr.yield_risk_score,
        pr.harvest_efficiency_risk_score,
        
        -- Productivity risk score (weighted)
        COALESCE(
            (pr.yield_risk_score * 0.6 + COALESCE(pr.harvest_efficiency_risk_score, 0) * 0.4),
            0
        ) AS productivity_risk_score,
        
        -- Tax components
        tr.inmobiliario_rural_usd_ha,
        tr.iibb_agro_pct,
        tr.property_tax_risk_score,
        tr.income_tax_risk_score,
        
        -- Tax risk score (weighted)
        COALESCE(
            (COALESCE(tr.property_tax_risk_score, 0) * 0.5 + tr.income_tax_risk_score * 0.5),
            0
        ) AS tax_risk_score
    FROM climate_aggregated AS ca
    LEFT JOIN productivity_risk AS pr
        ON ca.province_name = pr.provincia
    LEFT JOIN tax_risk AS tr
        ON ca.province_name = tr.provincia
),

final AS (
    SELECT
        jd.location_id,
        jd.location_name,
        jd.province_name,
        jd.latitude,
        jd.longitude,
        
        -- Climate metrics
        jd.max_temperature,
        jd.min_temperature,
        jd.avg_temperature,
        jd.total_precipitation_90d,
        jd.avg_humidity,
        
        -- Climate risk breakdown
        jd.frost_risk_pct,
        jd.heat_stress_risk_pct,
        jd.drought_stress_risk_pct,
        jd.fungal_disease_risk_pct,
        jd.excess_moisture_risk_pct,
        ROUND(jd.climate_risk_score, 2) AS climate_risk_score,
        
        -- Productivity metrics & risk
        jd.avg_yield,
        ROUND(jd.productivity_risk_score, 2) AS productivity_risk_score,
        
        -- Tax metrics & risk
        jd.inmobiliario_rural_usd_ha,
        jd.iibb_agro_pct,
        ROUND(jd.tax_risk_score, 2) AS tax_risk_score,
        
        -- OVERALL RISK INDEX (0-100)
        -- Weighted combination: Climate (40%) + Productivity (35%) + Tax (25%)
        ROUND(
            (jd.climate_risk_score * 0.40 +
             jd.productivity_risk_score * 0.35 +
             jd.tax_risk_score * 0.25),
            2
        ) AS overall_risk_index,
        
        -- Metadata
        CURRENT_TIMESTAMP() AS calculated_at
    FROM joined_data AS jd
)

SELECT * FROM final
ORDER BY overall_risk_index DESC, location_name
