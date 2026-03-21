# AgroProtect data stack (BigQuery)

## What is this?

This repository implements the **AgroProtect** data stack on BigQuery: **Meltano** for extraction (tap a definir para datos agro) and **dbt** for modeling. This README walks through setup.

**Estado extracción:** `tap-agro` (meteorología) está definido en `extraction/meltano.yml` → [tap-meteorology](https://github.com/juanpiRiv/tap-meteorology). **dbt** aún no modela esas tablas: los YAML/SQL bajo `transform/models` siguen referenciando fuentes legacy `tap_github` hasta que añadas `sources` para `{target}_tap_agro` y nuevos `stg_*` / marts.

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

If you also installed Meltano globally (`uv tool install meltano`), your shell may pick **that** binary instead of `.venv/bin/meltano` and hit Alembic errors (`No such revision 'c0efb3c314eb'`). Use `which meltano` or run `.venv/bin/meltano` explicitly; see `extraction/README.md`.

## What it includes

- Extraction with Meltano (**tap-agro** + `target-bigquery` / `target-jsonl` — ver `extraction/README.md`)
- Transformation with dbt (staging -> marts)
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

3. [DB] Create BigQuery datasets (or grant create permissions)

You will need datasets for raw and modeled data:

- Raw: dataset `{env}_{tap_namespace}` que genere Meltano (ej. `prod_tap_rest_api_msdk`). Los YAML de dbt aún pueden apuntar a `<env>_tap_github` hasta que migres las `sources`.
- Modeled: `stg` and `marts` (prod/ci). For dev, dbt uses `SANDBOX_<DBT_USER>`.

4. [CFG] Configure variables

```bash
cd data-stack-agroprotect/agro-protect
cp .env.example .env
```

Edit `.env` with your credentials. Minimal example:

```bash
BIGQUERY_PROJECT_ID=your-gcp-project
BIGQUERY_DATASET_ID=analytics
BIGQUERY_LOCATION=US
DBT_GOOGLE_APPLICATION_CREDENTIALS=/path/to/dbt-service-account.json
MELTANO_GOOGLE_APPLICATION_CREDENTIALS=/path/to/meltano-service-account.json
GOOGLE_APPLICATION_CREDENTIALS=${MELTANO_GOOGLE_APPLICATION_CREDENTIALS}
# Opcional en local (state en extraction/.meltano/). Si usás GCS: bucket real + facturación activa.
# MELTANO_STATE_BACKEND_URI=gs://your-bucket/meltano/state

TARGET_BIGQUERY_PROJECT=${BIGQUERY_PROJECT_ID}
TARGET_BIGQUERY_LOCATION=${BIGQUERY_LOCATION}
TARGET_BIGQUERY_CREDENTIALS_PATH=${MELTANO_GOOGLE_APPLICATION_CREDENTIALS}

DBT_USER=local
```

> [i] INFO: If you prefer a single service account, set both credential paths to
> the same file.
> [i] INFO: Si definís `MELTANO_STATE_BACKEND_URI`, `GOOGLE_APPLICATION_CREDENTIALS` debe ser la cuenta que pueda escribir en ese bucket. Sin URI de GCS, el state es local (`.meltano`).
> [!] WARNING: Cuando tengas tap, ejecuta Meltano en el **mismo entorno** (`dev` / `ci` / `prod`) que el `--target` de dbt para que el dataset raw coincida con `sources`.

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
meltano --environment=prod run <tu_tap> target-bigquery
```

> [!] WARNING: El nombre del dataset raw depende del tap; debe coincidir con las `sources` en dbt.

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
select * from marts.github_commits limit 10;
select * from marts.github_committers limit 10;
select commit_type, count(*) from marts.github_commits group by commit_type;
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
Fuente agro (API / archivos / …)
  -> Meltano (tu tap + target-bigquery)
  -> BigQuery: dataset <env>_<namespace_tap> (raw)
  -> dbt staging: dataset stg (stg_*)
  -> dbt marts: dataset marts (final models)
```

### Staging vs marts

- Staging cleans and normalizes raw data. It keeps consistent names and correct types.
- Marts are final models ready for analysis or BI.

Real example from this project:

- `stg_github_commits` -> `github_commits`

### Table of models and key columns

All column documentation lives in:

- `transform/models/staging/*.yml`
- `transform/models/production/marts/*.yml`

### Environments (dev, ci, prod)

- dev: default target. Raw en el dataset que defina tu tap (p. ej. `dev_<namespace>`), modelos en `SANDBOX_<DBT_USER>`.
- ci: raw en `ci_<namespace>`, modelos en `stg`/`marts`.
- prod: raw en `prod_<namespace>`, modelos en `stg`/`marts` (deploy/docs).

If you do not pass `--target prod`, dbt uses the default target (dev).

> [!] WARNING: For `dev`, you need `DBT_USER`. If you do not set it, dbt fails in the on-run-start hook.

### Why we use dbt build (and not dbt run)

- `dbt run` only executes models.
- `dbt build` executes models and tests (and snapshots/seeds if they exist).
- In PR and deploy we use `dbt build` to validate everything passes.

### Modeling conventions

- Staging always uses the `stg_` prefix.
- Marts have no prefix (e.g. `github_commits`).
- Each production model has its own `.yml` file with columns and tests.
- Use `ref()` for dependencies between models.

## Local development

### Work in your sandbox (dev)

```bash
export DBT_USER=tu_usuario
cd transform
set -a; source ../.env; set +a
export DBT_PROFILES_DIR=.
dbt build
```

> [i] INFO: Los datos raw quedan en el dataset del tap; en dev los modelos van a `SANDBOX_<DBT_USER>`.
> [i] INFO: If you modify models or YAML, run `dbt build` again.

### Add a new model

1. Create the SQL in `transform/models/staging` or `transform/models/production/marts`.
2. Create the model YAML with descriptions for all columns and basic tests.
3. Run a selective build.

```bash
dbt build --select <nombre_del_modelo>
```

### Change the data source

1. Edit `extraction/meltano.yml` to point to your new extractor.
2. Update `transform/models/staging/source_github.yml` with the new dataset and tables.
3. Rewrite the staging models to map the new columns.

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
They assume `working-directory: agro-protect` for installs and run Meltano/dbt under `agro-protect/extraction` and `agro-protect/transform`. Configure secrets for BigQuery + Meltano. **`data-pipeline.yml`** ejecuta `meltano run tap-agro target-bigquery` en `prod` (ver `extraction/README.md`).

### Required GitHub secrets

- `BIGQUERY_PROJECT_ID`
- `BIGQUERY_DATASET_ID`
- `BIGQUERY_LOCATION`
- `DBT_GOOGLE_APPLICATION_CREDENTIALS` (base64-encoded JSON key)
- `MELTANO_GOOGLE_APPLICATION_CREDENTIALS` (base64-encoded JSON key)
- `DBT_USER` (for sandbox datasets)
- `DBT_MANIFEST_URL` for custom slim CI
- `MELTANO_STATE_BACKEND_URI` (opcional) — `gs://…` con proyecto/bucket con **facturación activa**; si falta, el runner puede usar state en `.meltano` (menos ideal en CI compartido)
- `TARGET_BIGQUERY_PROJECT` if different from `BIGQUERY_PROJECT_ID`
- `TARGET_BIGQUERY_LOCATION` if different from `BIGQUERY_LOCATION`

Encode the JSON key before saving to GitHub Secrets:

```bash
base64 -i /path/to/service-account.json | tr -d '\n'
```

### Workflows

- `data-pipeline.yml`: **`meltano run tap-agro target-bigquery`** (extract y luego load a BigQuery). **Cron diario** = ayer (AR) → `prod`. **Dispatch manual** por defecto igual; o `meltano.yml` / solo validación. Histórico ~10 años: script en `extraction/scripts/`. Cómo correr en local: **`extraction/README.md`**.
- `dbt-pr-ci.yml`: on PR. `dbt build` en sandbox + SQLFluff (fallará si no hay raw alineado con `sources`).
- `dbt-cd-docs.yml`: push a `main`. `dbt build` + docs en Pages.

> [i] INFO: Los workflows de dbt usan `dbt build` cuando corre el job.

### Slim CI (prod manifest)

- The PR workflow tries to download `manifest.json` from prod.
- With `state:modified+` and `--defer`, dbt runs only what changed and uses prod for everything else.
- If there is no manifest, it runs a full build.

### SQLFluff

SQLFluff is a SQL linter. It is used to:

- keep consistent style in models
- catch basic issues before running dbt

In PR, only modified SQL models are linted.

### Enable GitHub Pages

1. Go to Settings -> Pages.
2. In Source, choose GitHub Actions.
3. After a push to `main`, the docs are published.

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
meltano --environment=prod run <tu_tap> target-bigquery
```

Need a full reload (clear Meltano state)

If you want to reimport everything, clear the saved state first:

```bash
meltano --environment=prod state list
meltano --environment=prod state clear "<state_id_del_job>" --force
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
export DBT_USER=tu_usuario
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
