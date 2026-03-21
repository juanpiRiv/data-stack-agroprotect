# Export BigQuery → GCS (data for a frontend)

Minimal flow: **GCS bucket + service account in GCP** (step 1) and a **local script** that writes newline-delimited JSON (NDJSON) into the bucket (step 2).

Output is **NDJSON**: one BigQuery row = one JSON object per line. In Next.js you can use `response.text()` and `.split("\n").filter(Boolean).map(JSON.parse)` or fetch a small file and treat it line by line.

---

## Step 1 — GCP: bucket, service account, permissions

### 1.1 Bucket

1. In [Cloud Storage](https://console.cloud.google.com/storage) → **Create bucket**.
2. Globally unique name (e.g. `agroprotect-exports-prod`).
3. **Location**: same region as BigQuery (`BIGQUERY_LOCATION`).
4. **Public access prevention**: on (recommended).
5. **Uniform bucket-level access**: on.

### 1.2 Service account

1. **IAM & Admin** → **Service accounts** → **Create**.
2. Descriptive name, e.g. `bq-export-to-gcs`.
3. **Keys** → **Add key** → JSON → download and store securely (`chmod 600` locally).

It does not need to be the same SA as Meltano/dbt: a dedicated export SA is better.

### 1.3 Permissions (reasonable minimum)

On the **export** service account:

| Scope | Suggested role | Purpose |
|--------|----------------|---------|
| **Project** (where the extract job runs) | `BigQuery Job User` | Run `extract` |
| **Dataset(s)** you read | `BigQuery Data Viewer` | Read tables/views |
| **Export bucket** | `Storage Object Admin` (or `Object Creator` + `Object Viewer` on a prefix with IAM conditions) | Write `gs://…/*.json` |

If the dataset lives in another project, grant **Data Viewer** there and **Job User** where the client runs (usually the same project as `BIGQUERY_PROJECT_ID`).

### 1.4 Optional check with gcloud

Replace placeholders:

```bash
export PROJECT=your-project
export SA=bq-export-to-gcs@${PROJECT}.iam.gserviceaccount.com
export BUCKET=your-exports-bucket

gcloud config set project "${PROJECT}"

gsutil mb -l US "gs://${BUCKET}"   # adjust region to yours

gcloud projects add-iam-policy-binding "${PROJECT}" \
  --member="serviceAccount:${SA}" \
  --role="roles/bigquery.jobUser"

gcloud projects add-iam-policy-binding "${PROJECT}" \
  --member="serviceAccount:${SA}" \
  --role="roles/bigquery.dataViewer"
# For a specific dataset, prefer roles/bigquery.dataViewer at dataset scope in the console.

gsutil iam ch serviceAccount:${SA}:roles/storage.objectAdmin "gs://${BUCKET}"
```

---

## Step 2 — Test export locally

### 2.1 Dependencies

From `agro-protect/` root (venv active):

```bash
uv pip install -r scripts/requirements-export.txt
# or, with the editable package:
uv pip install -e ".[export]"
```

### 2.2 Environment variables

Add to `.env` (see `.env.example`) or export in the shell:

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/secure/path/bq-export-to-gcs.json
export BIGQUERY_PROJECT_ID=your-project
export EXPORT_GCS_BUCKET_NAME=your-exports-bucket
export EXPORT_GCS_PREFIX=prod/exports

# Option A — multiple tables/views (values = dataset.table in your project)
export EXPORT_TABLE_MAP='{"locations":"analytics.stg_agro_locations","weather":"analytics.stg_agro_clima_diario_nasa_power"}'

# Option B — single table
# export EXPORT_BQ_TABLE_REF=analytics.stg_agro_locations
# export EXPORT_GCS_BLOB_NAME=locations   # → prod/exports/locations.json
```

**Note:** tables must exist in BigQuery. You can export **raw** (`prod_tap_agro.*`) or **dbt views** (`stg_agro_*` in `analytics` / `BIGQUERY_DATASET_ID`). Example `EXPORT_TABLE_MAP` (single-line JSON):

```text
{"clima":"your-project.prod_tap_agro.clima_diario_nasa_power","locations":"your-project.prod_tap_agro.locations"}
```

After `dbt run` on agro staging:

```text
{"clima":"your-project.analytics.stg_agro_clima_diario_nasa_power","locations":"your-project.analytics.stg_agro_locations"}
```

Replace `your-project` with `BIGQUERY_PROJECT_ID` if the client does not already default the project.

### 2.3 Run

```bash
cd agro-protect
set -a && source .env && set +a   # if using .env
python scripts/export_to_gcs.py
```

Expected output: lines like `OK project.dataset.table -> gs://bucket/prefix/file.json`. Confirm objects in the GCS console.

### Limits

BigQuery may require a **wildcard** in the URI if an extract exceeds ~1 GiB per file. This script uses **one file per table** without wildcards; for very large tables you would extend the script (e.g. `name-*.json` and multiple shards).

---

## Relation to `data-pipeline` (Meltano extraction)

- **`data-pipeline`** ([`.github/workflows/data-pipeline.yml`](../../.github/workflows/data-pipeline.yml)) loads raw into **`{env}_tap_agro`**.
- **`export-bigquery-gcs`** is **independent**: it does not wait for dbt. You can export **raw** or already deployed **views**.
- After a successful ELT on `main`, export can also run via **`workflow_run`** (same successful conclusion from `data-pipeline`). **Cron** and **manual** runs still apply; watch for duplicate runs if cron aligns with the end of the pipeline.

## GitHub Actions workflow

Workflow: **`.github/workflows/export-bigquery-gcs.yml`** (`export-bigquery-gcs`).

- **When it runs:** every **6 hours** (UTC), **manual**, **push to `main`** when the script / `requirements-export.txt` / workflow changes, and when **`data-pipeline`** completes **successfully** on `main` (optional chained export).
- **Secrets** (Settings → Secrets and variables → Actions):

| Secret | Required | Description |
|--------|----------|-------------|
| `EXPORT_GOOGLE_APPLICATION_CREDENTIALS` | Yes | Export SA JSON, **base64 single line** (`base64 -i key.json \| tr -d '\n'`) |
| `BIGQUERY_PROJECT_ID` | Yes | Same as elsewhere in the repo |
| `EXPORT_GCS_BUCKET_NAME` | Yes | e.g. `agroprotect-exports-prod` |
| `EXPORT_TABLE_MAP` | One or the other | **One-line** JSON, e.g. `{"locations":"analytics.stg_agro_locations"}` |
| `EXPORT_BQ_TABLE_REF` | One or the other | `dataset.table` for a single table |
| `EXPORT_GCS_BLOB_NAME` | No | File name without `.json` (only with `EXPORT_BQ_TABLE_REF`) |
| `EXPORT_GCS_PREFIX` | No | If the secret is unset, the script defaults to `prod/exports` |

### Quick test secret (`EXPORT_TABLE_MAP`)

Paste this **exact single line** as the secret value (no line breaks):

```text
{"locations":"analytics.stg_agro_locations","weather":"analytics.stg_agro_clima_diario_nasa_power"}
```

Object keys (`locations`, `weather`) become file names: `locations.json`, `weather.json` under your prefix (default `prod/exports/`).

**Dataset name:** Values must match **BigQuery** (`dataset.table`). In this repo, dbt **prod** staging often lives in the **`stg`** dataset (`stg.stg_agro_locations`, …), not `analytics`. If the job fails with “not found”, use:

```text
{"locations":"stg.stg_agro_locations","weather":"stg.stg_agro_clima_diario_nasa_power"}
```

If you create **`EXPORT_GCS_PREFIX`** as an **empty** secret, GitHub may omit it; to force an empty prefix you can skip the secret and rely on the script default. For a custom prefix, set the secret to e.g. `prod/exports` (no trailing slash).

## Optional next steps

- Manifest with signed URLs for the frontend.
- Bucket CORS if the browser calls signed URLs directly.
