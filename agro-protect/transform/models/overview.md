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
{% enddocs %}
