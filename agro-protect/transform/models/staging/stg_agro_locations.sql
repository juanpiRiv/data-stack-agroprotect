{{ config(
    materialized='view',
    tags=['agro', 'tap_agro']
) }}

-- Aplana el registro Singer (`data` STRUCT) a columnas tipadas.
SELECT
    * EXCEPT (data),
    data.*
FROM {{ source('tap_agro', 'locations') }}
