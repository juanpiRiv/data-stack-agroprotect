WITH usable_locations AS (
    SELECT location_id
    FROM {{ ref('fct_weather_daily') }}
    WHERE
        is_quality_approved
        AND NOT is_partial_latest_day
    GROUP BY location_id
)

SELECT
    app_snapshot.location_id,
    app_snapshot.selection_strategy,
    app_snapshot.snapshot_date
FROM {{ ref('app_location_snapshot') }} AS app_snapshot
INNER JOIN usable_locations
    ON app_snapshot.location_id = usable_locations.location_id
WHERE app_snapshot.selection_strategy != 'usable'
