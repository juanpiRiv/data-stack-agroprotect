# AgroProtect data stack (BigQuery)

## What is this?

This repository implements the **AgroProtect** data stack on BigQuery: **Meltano** extracts **agro weather** with **`tap-agro`** ([tap-meteorology](https://github.com/juanpiRiv/tap-meteorology)) into **`{target}_tap_agro`**, and **dbt** modela capa **staging** (NASA / agro); los marts son opcionales cuando los agregues. Este README recorre el setup.

**Extraction → transform:** raw in BigQuery (`prod_tap_agro` from Meltano, `raw_nasa` for the NASA POWER view) and dbt staging (`stg_agro_*`, `stg_clima_diario_nasa`, `source_tap_agro.yml`, `source_nasa.yml` under `transform/models/staging/`).

### Production extraction checklist (GitHub Actions + GCP)

| # | What to set |
|---|-------------|
| 1 | **Meltano service account** JSON as base64 (single line): `MELTANO_GOOGLE_APPLICATION_CREDENTIALS`. |
| 2 | **BigQuery:** `BIGQUERY_PROJECT_ID`, `BIGQUERY_LOCATION`; optional `TARGET_BIGQUERY_*` overrides. SA needs at least **BigQuery Job User** + rights to load into `{env}_tap_agro`. |
| 3 | **GCS state:** `MELTANO_STATE_BACKEND_URI=gs://bucket/prefix` on a bucket with billing; SA needs object read/write on that prefix. |
| 4 | **Workflow:** [`.github/workflows/data-pipeline.yml`](../.github/workflows/data-pipeline.yml) — daily cron **06:00** `America/Argentina/Buenos_Aires` (09:00 UTC) + `workflow_dispatch`. |
| 5 | **Local:** run [`extraction/scripts/setup-local.sh`](extraction/scripts/setup-local.sh) once; it prints a **step-by-step** (venv + `meltano run …`). Optional: [`run_prod_elt.sh`](extraction/scripts/run_prod_elt.sh) as a shortcut. |

Long backfill is **not** in Actions — run [`extraction/scripts/run_tap_agro_bq_yearly.sh`](extraction/scripts/run_tap_agro_bq_yearly.sh) locally; see [`extraction/README.md`](extraction/README.md).

**Export BQ → GCS:** [`export-bigquery-gcs.yml`](../.github/workflows/export-bigquery-gcs.yml) — schedule, manual, push on export changes, and after a successful **`data-pipeline`** run on **`main`**. Details and `EXPORT_TABLE_MAP` in [`scripts/README.md`](scripts/README.md).

## 🎯 Prerequisites (read first)

**Software required (install if missing)**

- Python 3.11+: https://www.python.org/downloads/
- Git: https://git-scm.com/downloads
- Google Cloud account (billing-enabled project or rights to create one): https://console.cloud.google.com/
- Optional but recommended: gcloud CLI https://cloud.google.com/sdk/docs/install

**If you use [uv](https://github.com/astral-sh/uv)** at the `agro-protect/` root: `uv` installs into a virtualenv by default. Create it once, then install the editable package (do not use `python -m uv` inside the fresh venv):

```bash
cd agro-protect
uv venv
uv pip install -e ".[extraction,transform]"
source .venv/bin/activate
```

Alternatively: `uv pip install --system -e ".[extraction,transform]"` (installs into the active Python, like CI).

If you also installed Meltano globally (`uv tool install meltano`), your shell may pick **that** binary instead of `.venv/bin/meltano` and hit Alembic errors (`No such revision 'c0efb3c314eb'`) or **fail to persist state to GCS** (`ModuleNotFoundError: No module named 'google'`). Prefer **`./extraction/scripts/run_prod_elt.sh`** or **`./extraction/scripts/run_elt.sh`**, or **`.venv/bin/meltano`**, or `uv tool uninstall meltano`; see `extraction/README.md`.

## What it includes

- Extraction with Meltano (**tap-agro** + `target-bigquery` / `target-jsonl` — see [`extraction/README.md`](extraction/README.md))
- **Export BQ → GCS** (NDJSON for a frontend): [`scripts/README.md`](scripts/README.md)
- Transformation with dbt (staging; marts cuando los agregues)
- Models and columns documented in YAML
- CI/CD workflows and dbt docs on GitHub Pages

## Quick start (Happy Path)

If you do not have a Google Cloud account, create one. If you already have GCP, create a new project for this stack.

In IAM & Admin:

- Go to Service Accounts and create one account for dbt and one for Meltano
  (or reuse a single account for both).
- For each service account, create a JSON key and download it.
- Rename the files (for example): `dbt-service-account.json` and `meltano-service-account.json`.
- Go back to IAM and grant access to each service account email
  (example: `meltano@data.iam.gserviceaccount.com`).
- Assign the role `BigQuery Data Owner` (or the minimum you need for datasets/jobs).

2. [GCS] Create a GCS bucket for Meltano state

In Cloud Storage -> Buckets:

- Create a private bucket (example: `agroprotect-meltano-state` or your org naming).
- Recommended settings:
  - Public access prevention: Enabled
  - Access control: Uniform
  - Storage class: Standard
  - Encryption: Google-managed

Then in bucket permissions:

- Add the Meltano service account (for example: `meltano@<project-id>.iam.gserviceaccount.com`).
- Grant the role `Storage Object Admin`.

This allows Meltano to create and manage state files.

2b. [GCS] Bucket for dbt **`manifest.json`** (slim CI)

- Same bucket as Meltano or a dedicated one (e.g. `gs://your-project-dbt-artifacts/dbt/manifest.json`).
- The **dbt** service account (`DBT_GOOGLE_APPLICATION_CREDENTIALS`) needs **`Storage Object Admin`** (or `objectCreator` + `objectViewer`) on that bucket/object.
- In GitHub → Secrets set **`DBT_MANIFEST_GCS_URI`** to the full object URI, e.g. `gs://your-bucket/dbt/manifest.json`.
- After a successful **`dbt-cd-docs`** deploy the workflow **uploads** `target/manifest.json` there; **`dbt-pr-ci`** PRs **download** it for `state:modified+`.

3. [DB] Create BigQuery datasets (or grant create permissions)

You will need datasets for raw and modeled data:

- Raw: **`{env}_tap_agro`** for `tap-agro` (e.g. `prod_tap_agro`) and **`raw_nasa`** for `source_nasa` / `stg_clima_diario_nasa` (dbt creates both on `on-run-start` when the hook runs).
- Modeled: `stg` and `marts` (prod/ci). For dev, dbt uses `SANDBOX_<DBT_USER>`.

4. [CFG] Configure variables

```bash
cd data-stack-agroprotect/agro-protect
cp .env.example .env
```

Edit `.env` with your credentials. Minimal example:

```bash
BIGQUERY_PROJECT_ID=agro-protect-490822
BIGQUERY_DATASET_ID=analytics
BIGQUERY_LOCATION=US
DBT_GOOGLE_APPLICATION_CREDENTIALS=/path/to/dbt-service-account.json
MELTANO_GOOGLE_APPLICATION_CREDENTIALS=/path/to/meltano-service-account.json
GOOGLE_APPLICATION_CREDENTIALS=${MELTANO_GOOGLE_APPLICATION_CREDENTIALS}
# Optional locally (state under extraction/.meltano/). For GCS: real bucket + billing enabled.
# MELTANO_STATE_BACKEND_URI=gs://your-bucket/meltano/state

TARGET_BIGQUERY_PROJECT=${BIGQUERY_PROJECT_ID}
TARGET_BIGQUERY_LOCATION=${BIGQUERY_LOCATION}
TARGET_BIGQUERY_CREDENTIALS_PATH=${MELTANO_GOOGLE_APPLICATION_CREDENTIALS}

DBT_USER=local
```

> [i] INFO: If you prefer a single service account, set both credential paths to
> the same file.
> [i] INFO: If you set `MELTANO_STATE_BACKEND_URI`, `GOOGLE_APPLICATION_CREDENTIALS` must be an account that can write to that bucket. Without a GCS URI, state stays local (`.meltano`).
> [!] WARNING: Run Meltano in the **same environment** (`dev` / `ci` / `prod`) as dbt’s `--target` so the raw dataset matches `sources`.

5. [LOCAL] Set up the extraction environment

```bash
cd extraction
./scripts/setup-local.sh
source venv/bin/activate
set -a; source ../.env; set +a
```

This creates the venv, installs Meltano dependencies, and initializes the project.

6. [TEST] Verify the state backend

From `extraction/` with the venv active:

```bash
set -a; source ../.env; set +a
meltano state list
```

Expected: no errors, and either an empty list or existing states.

7. [EXT] Run extraction once (Meltano)

```bash
set -a; source ../.env; set +a
meltano --environment=prod run tap-agro target-bigquery
```

> [!] WARNING: The raw dataset name depends on the tap; it must match dbt `sources`.

8. [DBT] Run transform and build models

```bash
cd ../transform
./scripts/setup-local.sh
source venv/bin/activate
cp profiles.yml.example profiles.yml
set -a; source ../.env; set +a
export DBT_PROFILES_DIR=.
dbt deps
dbt build --target prod
```

> [i] INFO: `dbt build` runs models and tests, so it is used in PR/deploy.
> [i] INFO: Every time you change a model, run `dbt build` again (or a selective build).

9. [SQL] See results in the DB

```sql
select * from stg.stg_clima_diario_nasa limit 10;
select * from stg.stg_agro_clima_diario_nasa_power limit 10;
select count(*) from stg.stg_agro_locations;
```

10. [DOCS] Generate dbt docs (optional)

```bash
cd ../transform
set -a; source ../.env; set +a
export DBT_PROFILES_DIR=.
dbt docs generate --target prod
dbt docs serve --target prod
```

Opens at: http://localhost:8080

## Next steps

1. View dbt docs to explore the DAG and columns.
2. Add a new model and document it.
3. Change the data source and adapt staging.

## Understanding the project

### Data flow

```
Agro / NASA POWER (API)
  -> Meltano (tap-agro + target-bigquery)
  -> BigQuery: dataset <env>_tap_agro (raw) y raw_nasa (vista NASA)
  -> dbt staging: dataset stg (stg_*)
  -> (opcional) dbt marts: dataset marts
```

### Staging vs marts

- Staging cleans and normalizes raw data. It keeps consistent names and correct types.
- Marts are final models ready for analysis or BI.

Real example from this project:

- `stg_agro_clima_diario_nasa_power` limpia la tabla cruda de clima de `tap-agro`; `stg_clima_diario_nasa` modela la vista en `raw_nasa`.

### Table of models and key columns

La documentación de columnas está en `transform/models/staging/*.yml` (y en YAML junto a cada mart cuando existan).

### Environments (dev, ci, prod)

- dev: default target. Raw in `dev_<namespace>`; models in `SANDBOX_<DBT_USER>`.
- ci: raw in `ci_<namespace>`; models in `stg` / `marts`.
- prod: raw in `prod_<namespace>`; models in `stg` / `marts` (deploy/docs).

If you do not pass `--target prod`, dbt uses the default target (dev).

> [!] WARNING: For `dev`, you need `DBT_USER`. If you do not set it, dbt fails in the on-run-start hook.

### Why we use dbt build (and not dbt run)

- `dbt run` only executes models.
- `dbt build` executes models and tests (and snapshots/seeds if they exist).
- In PR and deploy we use `dbt build` to validate everything passes.

### Modeling conventions

- Staging always uses the `stg_` prefix.
- Los marts (cuando existan) no llevan prefijo `stg_`; hoy el proyecto se centra en staging NASA / agro.
- Each production model has its own `.yml` file with columns and tests.
- Use `ref()` for dependencies between models.

## Local development

### Work in your sandbox (dev)

```bash
export DBT_USER=your_username
cd transform
set -a; source ../.env; set +a
export DBT_PROFILES_DIR=.
dbt build
```

> [i] INFO: Raw data stays in the tap’s dataset; in dev models go to `SANDBOX_<DBT_USER>`.
> [i] INFO: Creá ese dataset (y `stg` si usás `--defer`) en BigQuery en la **misma región** que `BIGQUERY_LOCATION`, p. ej. `bq mk --dataset --location=US ${BIGQUERY_PROJECT_ID}:SANDBOX_tu_usuario`. En PRs, GitHub Actions lo hace por región alineada a `prod_tap_agro`.
> [i] INFO: If you modify models or YAML, run `dbt build` again.

### Add a new model

1. Create the SQL in `transform/models/staging` or `transform/models/production/marts`.
2. Create the model YAML with descriptions for all columns and basic tests.
3. Run a selective build.

```bash
dbt build --select <model_name>
```

### Change the data source

1. Edit `extraction/meltano.yml` to point to your new extractor.
2. Update `transform/models/staging/source_tap_agro.yml` and/or `source_nasa.yml` con el dataset y tablas correctos.
3. Reescribe los modelos `stg_*` para mapear las nuevas columnas.

## Quick repo layout

Monorepo root (`data-stack-agroprotect/`):

- `.github/workflows/`: CI/CD (GitHub only loads workflows from the **repository root**)

Inside `agro-protect/`:

- `extraction/`: Meltano project
- `transform/`: dbt project
- `.env.example`: variables template

<details>
<summary>CI/CD Setup</summary>

Workflows live at the **repository root** (`.github/workflows/` next to `agro-protect/`).
They assume `working-directory: agro-protect` for installs and run Meltano/dbt under `agro-protect/extraction` and `agro-protect/transform`. Configure secrets for BigQuery + Meltano. **`data-pipeline.yml`** runs `meltano run tap-agro target-bigquery` for `prod` — see [`extraction/README.md`](extraction/README.md).

### Required GitHub secrets

- `BIGQUERY_PROJECT_ID`
- `BIGQUERY_DATASET_ID`
- `BIGQUERY_LOCATION`
- `DBT_GOOGLE_APPLICATION_CREDENTIALS` (base64-encoded JSON key)
- `MELTANO_GOOGLE_APPLICATION_CREDENTIALS` (base64-encoded JSON key)
- `DBT_USER` (for sandbox datasets)
- **`DBT_MANIFEST_GCS_URI`** (recommended): `gs://bucket/path/manifest.json` — prod manifest for slim CI; CD uploads it and PR jobs download it
- `DBT_MANIFEST_URL` (optional): **https** or `gs://…` if you do not use the secret above; if neither is set, the workflow tries `manifest.json` from GitHub Pages
- `MELTANO_STATE_BACKEND_URI` (optional) — `gs://…` on a project/bucket with **billing enabled**; if missing, the runner may use state under `.meltano` (less ideal on shared CI)
- `TARGET_BIGQUERY_PROJECT` if different from `BIGQUERY_PROJECT_ID`
- `TARGET_BIGQUERY_LOCATION` if different from `BIGQUERY_LOCATION`

**Export a GCS (workflow `export-bigquery-gcs`):**

- `EXPORT_GOOGLE_APPLICATION_CREDENTIALS` (base64) — SA dedicated to export (BQ read + bucket write)
- `EXPORT_GCS_BUCKET_NAME`
- `EXPORT_TABLE_MAP` (single-line JSON) **or** `EXPORT_BQ_TABLE_REF` (+ optional `EXPORT_GCS_BLOB_NAME`)
- Optional: `EXPORT_GCS_PREFIX` (if unset, the script defaults to `prod/exports`)

Encode the JSON key before saving to GitHub Secrets:

```bash
base64 -i /path/to/service-account.json | tr -d '\n'
```

### Workflows

- `data-pipeline.yml`: **`meltano run tap-agro target-bigquery`** (extract then load to BigQuery). **Daily cron** = yesterday (ART) → `prod`. **Manual dispatch** defaults the same; or fixed window from `meltano.yml` / validate-only. ~10y history: script under `extraction/scripts/`. Local run: **`extraction/README.md`**.
- `export-bigquery-gcs.yml`: **export BQ → GCS** (NDJSON) via `agro-protect/scripts/export_to_gcs.py`. **Every 6 h** cron + manual + push to `main` when the script changes. Secrets: `EXPORT_GOOGLE_APPLICATION_CREDENTIALS` (base64), `EXPORT_GCS_BUCKET_NAME`, `EXPORT_TABLE_MAP` or `EXPORT_BQ_TABLE_REF`; details in **`scripts/README.md`**.
- `dbt-pr-ci.yml`: on PR. Alinea proyecto (secret vs key JSON) y región con `prod_tap_agro`; crea/recrea datasets `SANDBOX_*` si la región no coincide; `dbt build` en sandbox + SQLFluff.
- `dbt-cd-docs.yml`: al **merge/push a `main`** o **workflow_dispatch** corre el job **deploy**: `dbt build` (prod) → **`dbt docs generate`** → sube `target/` a **GitHub Pages** (no se usa `dbt docs serve` en CI; eso es solo en tu máquina). En PR solo valida `dbt parse`. Opcional: sube `target/manifest.json` a GCS si definís `DBT_MANIFEST_GCS_URI`.

> [i] INFO: dbt workflows use `dbt build` when the job runs.

### Slim CI (prod manifest)

- PR manifest lookup order: **`DBT_MANIFEST_GCS_URI`** → `DBT_MANIFEST_URL` (https or `gs://`) → GitHub Pages (`…/manifest.json`).
- With `state:modified+` and `--defer`, dbt compiles/runs only what changed and defers the rest to prod.
- Without a valid manifest, the job does a **full build** (slower but safe).
- El `manifest.json` para slim CI sale del mismo `dbt docs generate` en **`dbt-cd-docs`**: o lo copiás a GCS (secret) o queda publicado en Pages en la raíz del sitio (`manifest.json`). Hasta que **Pages esté habilitado** y haya un deploy exitoso en `main`, el fallback por URL suele fallar y es normal.

### SQLFluff

SQLFluff is a SQL linter. It is used to:

- keep consistent style in models
- catch basic issues before running dbt

In PR, only modified SQL models are linted.

### Enable GitHub Pages

1. Repo → **Settings** → **Pages**.
2. **Build and deployment** → **Source**: **GitHub Actions** (no “Deploy from a branch”).
3. Hacé push a **`main`** (o **Actions** → **dbt-cd-docs** → **Run workflow**) para que el job **deploy** publique `target/` (incluye `index.html`, `manifest.json`, etc.).
4. Si el workflow falla por secretos GCP, el deploy a Pages no llega a ejecutarse; los PR seguirán sin manifest hasta que `dbt-cd-docs` complete bien.

</details>

<details>
<summary>Common troubleshooting</summary>

Error: Env var required but not provided: BIGQUERY_PROJECT_ID

```bash
set -a; source .env; set +a
```

If you are inside `transform` or `extraction`:

```bash
set -a; source ../.env; set +a
```

Error: source: no such file or directory: .env

```bash
set -a; source ../.env; set +a
```

Error: Source dataset not found

Run extraction in the same environment as your dbt target (prod example):

```bash
meltano --environment=prod run tap-agro target-bigquery
```

Need a full reload (clear Meltano state)

If you want to reimport everything, clear the saved state first:

```bash
meltano --environment=prod state list
meltano --environment=prod state clear "<state_id>" --force
```

To clear all state IDs:

```bash
meltano --environment=prod state clear --all --force
```

Error: Required key is missing from config (Meltano)

Make sure `BIGQUERY_*`, `TARGET_BIGQUERY_*`, and Meltano credential paths are set in `.env` and reload:

```bash
set -a; source .env; set +a
```

Error: DBT_USER environment variable not set

```bash
export DBT_USER=your_username
```

</details>

<details>
<summary>Project customization</summary>

- For another API: replace the tap in `extraction/meltano.yml` and align `transform/models/staging` sources + macro `ensure_source_datasets`.
- For another warehouse: update `transform/profiles.yml.example` and `BIGQUERY_*`/`TARGET_BIGQUERY_*` in `.env`.
- For new models: add SQL in `transform/models/production/marts` and its YAML next to it.

</details>

## License

MIT
