{% docs __overview__ %}
# AgroProtect · BigQuery data stack
Extraction with Meltano (**tap-agro** for agro weather) and modeling with dbt.

## How to navigate
- Meltano creates raw tables in `<env>_<tap_namespace>`.
- Raw NASA POWER: **`{env}_tap_agro`** (Meltano) and **`raw_nasa`** (source `tap_nasa` in `source_nasa.yml`).
- The project now follows **staging -> intermediate -> marts**.
- Staging dataset `stg`; intermediate dataset `int`; marts in `marts` (prod/ci) or `SANDBOX_<DBT_USER>` in dev (crear el sandbox en BQ a mano en local; en PR CI lo asegura `.github/workflows/dbt-pr-ci.yml`).

## Running locally
1) `set -a; source ../.env; set +a`
2) With tap configured: `meltano --environment=prod run tap-agro target-bigquery` from `extraction/`
3) From `transform/`: `./scripts/setup-local.sh`, `dbt deps`, `dbt build --target prod` (requires raw aligned with `sources`)

## Tips
- Prefer `dbt build` over `dbt run`; set `DBT_USER` in dev.
- After changing the tap, update `sources`, macro `ensure_source_datasets`, and staging models.
{% enddocs %}

{% docs __agroprotect__ %}
# AgroProtect · data stack
BigQuery stack: Meltano for ingest, dbt for clean layers and documented marts.

## Read next
- `README.md` and `extraction/README.md` for the extractor.
- `models/staging/tap_agro/` for canonical weather and location staging.
- `models/staging/seeds/` and `seeds/seeds.yml` for tax and yield seed inputs.
- `models/intermediate/` for deduplication, campaign metrics, and province-level aggregations.
- `models/marts/` for `dim_location`, `dim_province`, `fct_weather_daily`, `fct_yield_province_campaign`, `fct_tax_province`, and `mart_agro_province_campaign`.

## Team flow
- `.env` aligned with GCP and the chosen tap.
- `dbt build --select <model> --target dev` in development.
- `dbt docs generate --target prod` for review when needed.

## Canonical path (`tap_agro`) -> marts
La ruta principal del proyecto es ahora `tap_agro` raw -> `stg_tap_agro__*` -> `int_*` -> marts. El modelo legacy `stg_clima_diario_nasa` sigue disponible para la ruta opcional `tap_nasa`, pero la modelización nueva vive sobre `tap_agro`.

### Renombrado directo (columna fuente -> staging canónico)
| Fuente (tap-agro raw) | Staging |
| --- | --- |
| `location_id` | `location_id` |
| `location_name` | `location_name` |
| `province_name` | `province_name` |
| `province_name` | `province_key` (normalizado para joins) |
| `latitude` | `latitude` (`FLOAT64`) |
| `longitude` | `longitude` (`FLOAT64`) |
| `date` | `date` (`DATE`) |
| `T2M_MAX` | `max_air_temp_c` |
| `T2M_MIN` | `min_air_temp_c` |
| `T2M` | `avg_air_temp_c` |
| `T2MDEW` | `dew_point_temp_c` |
| `T2MWET` | `wet_bulb_temp_c` |
| `TS` | `soil_surface_temp_c` |
| `PRECTOTCORR` | `precipitation_mm` |
| `RH2M` | `relative_humidity_pct` |
| `QV2M` | `specific_humidity_kg_kg` |
| `ALLSKY_SFC_SW_DWN` | `solar_radiation_allsky_mj_m2_day` |
| `CLRSKY_SFC_SW_DWN` | `solar_radiation_clearsky_mj_m2_day` |
| `WS2M` | `wind_speed_mps` |
| `WS2M_MAX` | `wind_speed_max_mps` |
| `WD2M` | `wind_direction_deg` |
| `PS` | `surface_pressure_kpa` |
| `CLOUD_AMT` | `cloud_cover_pct` |
| `x_source` | `source_name` |
| `x_source_type` | `source_type` |
| `x_loaded_at` | `source_loaded_at` (`TIMESTAMP`) |
| `_sdc_extracted_at` … `_sdc_table_version` | mismos nombres (metadatos de replicación) |

### Derivadas nuevas
- **Calendario:** `calendar_year`, `calendar_month`, `calendar_quarter`, `week_start`, `month_start`, `campaign_name`, `campaign_start_year`.
- **Agronomía / confort:** `heat_index_c`, `wind_chill_c`, `vpd_kpa`, `gdd_base_10_c_days`, `temp_range_c`.
- **Riesgos diarios:** `frost_day`, `heat_stress_day`, `heavy_rain_day`, `dry_day`, `fungal_risk_day`.
- **Calidad:** `critical_null_count`, `has_high_missing_data`, `temperature_inconsistent`, `temperature_outlier`, `precipitation_outlier`, `wind_outlier`, `radiation_inconsistent`, `is_partial_latest_day`, `is_quality_approved`.

### Seeds de negocio
- `tax_province` agrega variables económicas provinciales.
- `yield_department_campaign` agrega rendimiento histórico por cultivo, campaña, provincia y departamento.
- El mart final `mart_agro_province_campaign` combina clima por campaña, rendimiento provincial y carga tributaria provincial.

Detalle de fórmulas y tests: YAMLs en `models/staging/`, `models/intermediate/`, `models/marts/` y `seeds/seeds.yml`.
{% enddocs %}
