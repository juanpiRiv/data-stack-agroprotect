# Extraction (Meltano)

**tap-agro** ([tap-meteorology](https://github.com/juanpiRiv/tap-meteorology)) → **target-bigquery** into `{environment}_tap_agro`. Config: **`meltano.yml`**.

## Step-by-step (local)

After **`./extraction/scripts/setup-local.sh`** finishes, it prints the same checklist. Summary:

1. **`cp .env.example .env`** at `agro-protect/` and fill GCP + Meltano variables (see root **`README.md`**).
2. **Activate the project venv** and confirm **`which meltano`** → **`…/agro-protect/.venv/bin/meltano`** (not `uv tool` meltano, or GCS state can break).
3. **Load env**, **`cd extraction`**, run:
   - Daily (yesterday, `prod`): **`meltano --environment=prod run tap-agro target-bigquery`**
   - Short window (`dev`): **`meltano --environment=dev run tap-agro target-bigquery`**

**Optional shortcuts** (same commands; they **`source .env`** and force the venv **`meltano`**):

- **`./extraction/scripts/run_prod_elt.sh`** / **`run_dev_elt.sh`** (from `agro-protect/`)
- **`./scripts/run_elt.sh …`** (from `extraction/` for any Meltano subcommand)

## Behaviour (short)

- **`prod`**: `days_back: 1`. **CI**: `data-pipeline.yml`.
- **`dev` / `ci`**: short `days_back` in **`meltano.yml`**.
- **NASA only**: `use_open_meteo: false`; optional **`TAP_AGRO_USE_OPEN_METEO=false`** in `.env`.
- **Catalog**: **`data/locations.csv`** — run from **`extraction/`**.
- **Long history**: **`./scripts/run_tap_agro_bq_yearly.sh`** (local; see script).

## Reinstall plugins

```bash
cd agro-protect/extraction && ./scripts/meltano_install.sh
```

## Streams

`locations`, `clima_diario_nasa_power`

## Troubleshooting

Missing BQ config → **`source .env`**. Wrong **`.meltano`** → remove and **`meltano_install.sh`**. Loader **`pkg_resources`** → **`patch_meltano_loader_venvs.sh`**. GCS **403** → billing/IAM or unset **`MELTANO_STATE_BACKEND_URI`** locally. Wrong **Meltano** → venv binary or **`uv tool uninstall meltano`**. **429** → raise **`request_delay_seconds`**; use yearly script for backfill. **Bookmarks** → **`meltano state list` / `state clear`**.

## dbt

Raw: **`{target}_tap_agro`**. Staging: **`stg_agro_*`**, **`source_tap_agro.yml`** under **`transform/models/staging/`**.

## Env

**`agro-protect/.env`** or **`extraction/.env.example`** as template.
