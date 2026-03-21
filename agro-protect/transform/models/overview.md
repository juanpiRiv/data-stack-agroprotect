{% docs __overview__ %}
# AgroProtect · BigQuery data stack
Extraction with Meltano (**tap-agro** for agro weather) and modeling with dbt.

## How to navigate
- Meltano creates raw tables in `<env>_<tap_namespace>`.
- Raw NASA POWER: **`{env}_tap_agro`** (Meltano) and **`raw_nasa`** (source `tap_nasa` in `source_nasa.yml`).
- Staging dataset `stg`; marts in `marts` (prod/ci) or `SANDBOX_<DBT_USER>` in dev.

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
- `models/staging/source_tap_agro.yml`, `source_nasa.yml`, and `stg_*.yml` for sources.
- Cuando agregues marts en `models/production/marts/`, configura `+schema: marts` en `dbt_project.yml` bajo `models.agroprotect.production.marts`.

## Team flow
- `.env` aligned with GCP and the chosen tap.
- `dbt build --select <model> --target dev` in development.
- `dbt docs generate --target prod` for review when needed.

## Mapeo NASA POWER (`tap_nasa.clima_diario_nasa_power_view`) → `stg_clima_diario_nasa`
La vista vive en el dataset **`raw_nasa`** (ver `models/staging/source_nasa.yml`). El modelo `models/staging/stg_clima_diario_nasa.sql` deduplica por `(location_id, date)`, castea tipos y añade métricas derivadas y flags de calidad.

### Renombrado directo (columna fuente → columna staging)
| Fuente (NASA / ELT) | Staging |
| --- | --- |
| `location_id` | `location_id` |
| `location_name` | `location_name` |
| `province_name` | `province_name` |
| `latitude` | `latitude` (`FLOAT64`) |
| `longitude` | `longitude` (`FLOAT64`) |
| `date` | `date` (`DATE`) |
| `T2M_MAX` | `t2m_max` |
| `T2M_MIN` | `t2m_min` |
| `T2M` | `t2m` |
| `T2MDEW` | `t2m_dew` |
| `T2MWET` | `t2m_wet` |
| `TS` | `soil_temperature` |
| `PRECTOTCORR` | `precipitation_corrected` |
| `RH2M` | `relative_humidity_2m` |
| `QV2M` | `specific_humidity_2m` |
| `ALLSKY_SFC_SW_DWN` | `solar_radiation_allsky` |
| `CLRSKY_SFC_SW_DWN` | `solar_radiation_clearsky` |
| `WS2M` | `wind_speed_2m` |
| `WS2M_MAX` | `wind_speed_2m_max` |
| `WD2M` | `wind_direction_2m` |
| `PS` | `surface_pressure` |
| `CLOUD_AMT` | `cloud_amount` |
| `x_source` | `x_source` |
| `x_source_type` | `x_source_type` |
| `x_loaded_at` | `loaded_at` (`TIMESTAMP`) |
| `_sdc_extracted_at` … `_sdc_table_version` | mismos nombres (metadatos de replicación) |

### Solo en staging (derivadas o de tiempo)
- **Calendario:** `year`, `month`, `quarter`, `week_start`, `month_start` desde `date`.
- **Agronomía / confort:** `heat_index`, `wind_chill`, `vapor_pressure_deficit`, `growing_degree_days_10c`.
- **Riesgos (0/1/NULL):** `frost_risk`, `frost_severity_degrees`, `heat_stress_risk`, `drought_stress_risk`, `fungal_disease_risk`, `excessive_moisture_risk`.
- **Calidad:** `critical_null_count`, `has_high_missing_data`, `temperature_inconsistent`, `temperature_outlier`, `precipitation_outlier`.

Detalle de fórmulas y tests: `models/staging/stg_clima_diario_nasa.yml`.
{% enddocs %}
