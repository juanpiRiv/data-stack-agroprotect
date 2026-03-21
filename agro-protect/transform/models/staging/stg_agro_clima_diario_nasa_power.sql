{{ config(
    materialized='view',
    tags=['agro', 'tap_agro']
) }}

-- Aplana el registro Singer (`data` STRUCT). Primary key lógica del tap: location_id + date.
SELECT
    * EXCEPT (data),
    data.*
FROM {{ source('tap_agro', 'clima_diario_nasa_power') }}
