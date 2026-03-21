{{ config(
    materialized='table',
    tags=['agricultural_data', 'taxes']
) }}

with source as (
    select
        provincia,
        inmobiliario_rural_usd_ha,
        safe_cast(
            regexp_replace(iibb_agro_percent, '%', '') as float64
        ) as iibb_agro_pct
    from {{ seed('impuestos_agro_argentina') }}
)

select
    provincia,
    case
        when string_length(inmobiliario_rural_usd_ha) > 0
        then cast(
            (
                cast(
                    regexp_extract(inmobiliario_rural_usd_ha, r'^(\d+)')
                    as float64
                ) + cast(
                    regexp_extract(inmobiliario_rural_usd_ha, r'(\d+)$')
                    as float64
                )
            ) / 2 as float64
        )
    end as inmobiliario_rural_usd_ha,
    iibb_agro_pct
from source
where provincia is not null
order by provincia asc
