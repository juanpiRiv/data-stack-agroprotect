{{ config(
    materialized='view',
    tags=['agro', 'tap_agro']
) }}

-- Flattens the Singer record (`data` STRUCT). Tap logical primary key: location_id + date.
SELECT
    * EXCEPT (data),
    data.*
FROM {{ source('tap_agro', 'clima_diario_nasa_power') }}
