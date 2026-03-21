{{ config(
    materialized='table',
    tags=['marts', 'risk_analysis']
) }}

with climate_data as (
    select
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
    from {{ ref('stg_clima_diario_nasa') }}
    where date >= current_date() - 90
),

climate_aggregated as (
    select
        cd.location_id,
        cd.location_name,
        cd.province_name,
        cd.latitude,
        cd.longitude,
        max(cd.t2m_max) as max_temperature,
        min(cd.t2m_min) as min_temperature,
        avg(cd.t2m) as avg_temperature,
        sum(cd.precipitation_corrected) as total_precipitation_90d,
        avg(cd.relative_humidity_2m) as avg_humidity,
        sum(case when cd.frost_risk = 1 then 1 else 0 end)
            / count(*) * 100 as frost_risk_pct,
        sum(case when cd.heat_stress_risk = 1 then 1 else 0 end)
            / count(*) * 100 as heat_stress_risk_pct,
        sum(case when cd.drought_stress_risk = 1 then 1 else 0 end)
            / count(*) * 100 as drought_stress_risk_pct,
        sum(case when cd.fungal_disease_risk = 1 then 1 else 0 end)
            / count(*) * 100 as fungal_disease_risk_pct,
        sum(case when cd.excessive_moisture_risk = 1 then 1 else 0 end)
            / count(*) * 100 as excess_moisture_risk_pct
    from climate_data as cd
    where cd.critical_null_count < 2
    group by
        cd.location_id,
        cd.location_name,
        cd.province_name,
        cd.latitude,
        cd.longitude
),

productivity_data as (
    select
        r.provincia,
        avg(r.rendimiento_kgxha) as avg_yield,
        min(r.rendimiento_kgxha) as min_yield,
        max(r.rendimiento_kgxha) as max_yield,
        stddev(r.rendimiento_kgxha) as yield_stddev,
        sum(r.superficie_sembrada_ha) as total_sown_area,
        sum(r.superficie_cosechada_ha) as total_harvested_area,
        sum(r.produccion_tm) as total_production,
        avg(r.harvest_ratio_pct) as avg_harvest_ratio,
        max(r.anio) as latest_year
    from {{ ref('stg_rendimiento_agro') }} as r
    group by r.provincia
),

productivity_risk as (
    select
        p.provincia,
        p.avg_yield,
        p.latest_year,
        case
            when p.avg_yield is not null
            then 100
                - (
                    (p.avg_yield - min(p.avg_yield) over ())
                    / (
                        max(p.avg_yield) over ()
                        - min(p.avg_yield) over () + 1
                    ) * 100
                )
        end as yield_risk_score,
        case
            when p.avg_harvest_ratio is not null
            then (1 - (p.avg_harvest_ratio / 100)) * 100
        end as harvest_efficiency_risk_score
    from productivity_data as p
),

tax_data as (
    select
        provincia,
        inmobiliario_rural_usd_ha,
        iibb_agro_pct
    from {{ ref('stg_impuestos_agro_argentina') }}
),

tax_risk as (
    select
        t.provincia,
        t.inmobiliario_rural_usd_ha,
        t.iibb_agro_pct,
        case
            when t.inmobiliario_rural_usd_ha is not null
            then (
                (t.inmobiliario_rural_usd_ha - min(t.inmobiliario_rural_usd_ha) over ())
                / (
                    max(t.inmobiliario_rural_usd_ha) over ()
                    - min(t.inmobiliario_rural_usd_ha) over () + 1
                ) * 100
            )
        end as property_tax_risk_score,
        coalesce(t.iibb_agro_pct * 100, 0) as income_tax_risk_score
    from tax_data as t
),

joined_data as (
    select
        ca.location_id,
        ca.location_name,
        ca.province_name,
        ca.latitude,
        ca.longitude,
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
        (
            ca.frost_risk_pct * 0.25
            + ca.heat_stress_risk_pct * 0.25
            + ca.drought_stress_risk_pct * 0.20
            + ca.fungal_disease_risk_pct * 0.15
            + ca.excess_moisture_risk_pct * 0.15
        ) as climate_risk_score,
        pr.avg_yield,
        pr.yield_risk_score,
        pr.harvest_efficiency_risk_score,
        coalesce(
            (
                pr.yield_risk_score * 0.6
                + coalesce(pr.harvest_efficiency_risk_score, 0) * 0.4
            ),
            0
        ) as productivity_risk_score,
        tr.inmobiliario_rural_usd_ha,
        tr.iibb_agro_pct,
        tr.property_tax_risk_score,
        tr.income_tax_risk_score,
        coalesce(
            (
                coalesce(tr.property_tax_risk_score, 0) * 0.5
                + tr.income_tax_risk_score * 0.5
            ),
            0
        ) as tax_risk_score
    from climate_aggregated as ca
    left join productivity_risk as pr
        on ca.province_name = pr.provincia
    left join tax_risk as tr
        on ca.province_name = tr.provincia
),

final as (
    select
        jd.location_id,
        jd.location_name,
        jd.province_name,
        jd.latitude,
        jd.longitude,
        jd.max_temperature,
        jd.min_temperature,
        jd.avg_temperature,
        jd.total_precipitation_90d,
        jd.avg_humidity,
        jd.frost_risk_pct,
        jd.heat_stress_risk_pct,
        jd.drought_stress_risk_pct,
        jd.fungal_disease_risk_pct,
        jd.excess_moisture_risk_pct,
        round(jd.climate_risk_score, 2) as climate_risk_score,
        jd.avg_yield,
        round(jd.productivity_risk_score, 2) as productivity_risk_score,
        jd.inmobiliario_rural_usd_ha,
        jd.iibb_agro_pct,
        round(jd.tax_risk_score, 2) as tax_risk_score,
        round(
            (
                jd.climate_risk_score * 0.40
                + jd.productivity_risk_score * 0.35
                + jd.tax_risk_score * 0.25
            ),
            2
        ) as overall_risk_index,
        current_timestamp() as calculated_at
    from joined_data as jd
)

select *
from final
order by overall_risk_index desc, location_name asc
