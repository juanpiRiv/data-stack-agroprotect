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
| **Export bucket** | `Storage Object Admin` (or `Object Creator` + `Object Viewer` on a prefix with IAM conditions) | Write `gs://…/*.json`, list objects (manifiesto), firmar URLs con la clave de la SA |

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
export BIGQUERY_DATASET_ID=analytics   # usado en modo auto (dataset “principal” de dbt prod)
export EXPORT_GCS_BUCKET_NAME=your-exports-bucket
export EXPORT_GCS_PREFIX=prod/exports
```

**Modo por defecto (auto):** si **no** definís `EXPORT_TABLE_MAP` ni `EXPORT_BQ_TABLE_REF`, el script recorre los datasets `stg`, `BIGQUERY_DATASET_ID` (default `analytics`) y `marts` (si existen), exporta cada tabla/vista extraíble a `gs://…/{prefix}{dataset}/{table}_*.json` (NDJSON) y sube **`export_manifest.json`** al bucket con **URLs firmadas (V4)** por cada archivo. En stderr verás `MANIFEST_SIGNED_URL=…` para descargar el JSON del manifiesto.

- `EXPORT_BQ_DATASETS` — lista separada por comas para reemplazar la lista por defecto (ej. `stg,analytics,marts,prod_tap_agro`).
- `EXPORT_MODE=auto` — fuerza auto aunque existan otras variables (raro).
- `EXPORT_MODE=explicit` o `map` — exige `EXPORT_TABLE_MAP` o `EXPORT_BQ_TABLE_REF`.
- `EXPORT_SIGNED_URL_TTL_SEC` — vigencia de las URLs firmadas (default **43200** s = 12 h, máx. 604800).
- `EXPORT_MANIFEST_OBJECT` — nombre del objeto del manifieste (default `export_manifest.json`).
- `DBT_MANIFEST_PATH` — ruta local a `target/manifest.json` tras `dbt docs generate`; si existe, se sube a `…/dbt/manifest.json` y se incluye en el manifieste con URL firmada.

**Modo lista manual** (`EXPORT_TABLE_MAP` o `EXPORT_BQ_TABLE_REF`):

```bash
export EXPORT_TABLE_MAP='{"locations":"stg.stg_agro_locations","weather":"stg.stg_agro_clima_diario_nasa_power"}'
# o una sola tabla:
# export EXPORT_BQ_TABLE_REF=stg.stg_agro_locations
```

Ejemplos con proyecto explícito en el mapa:

```text
{"clima":"your-project.prod_tap_agro.clima_diario_nasa_power","locations":"your-project.prod_tap_agro.locations"}
```

### 2.3 Run

```bash
cd agro-protect
set -a && source .env && set +a   # if using .env
python scripts/export_to_gcs.py
```

Expected output: líneas `OK … -> gs://…` y al final `OK export manifest -> gs://…` + `MANIFEST_SIGNED_URL=…`.

### Limits

BigQuery usa un **patrón con `*`** en el destino; tablas grandes generan varios shards (`_000000000000.json`, …). El manifieste lista todos los objetos y firma cada uno.

Las **vistas** (`VIEW`) no admiten `extract_table`; el script usa **`EXPORT DATA … AS SELECT *`** (mismo NDJSON en GCS).

---

## Relation to `data-pipeline` (Meltano extraction)

- **`data-pipeline`** ([`.github/workflows/data-pipeline.yml`](../../.github/workflows/data-pipeline.yml)) loads raw into **`{env}_tap_agro`**.
- **`export-bigquery-gcs`** is **independent**: it does not wait for dbt. You can export **raw** or already deployed **views**.
- After a successful ELT on `main`, export can also run via **`workflow_run`** (same successful conclusion from `data-pipeline`). **Cron** and **manual** runs still apply; watch for duplicate runs if cron aligns with the end of the pipeline.

## GitHub Actions workflow

Workflow: **`.github/workflows/export-bigquery-gcs.yml`** (`export-bigquery-gcs`).

- **When it runs:** every **6 hours** (UTC), **manual**, **pull request** a `main` (cambios bajo `agro-protect/**` o este workflow), **push a `main`** (mismos paths + `transform/**` / `pyproject.toml`), y cuando **`data-pipeline`** termina **OK** en `main`.
- **CI:** `dbt deps` + `dbt parse --target prod` → `transform/target/manifest.json`; luego el script sube NDJSON + ese manifest a GCS (y `export_manifest.json` con URLs firmadas). **No hace falta** GitHub Pages.
- **PRs:** prefijo GCS automático `pr/<número>/exports/` para no pisar `prod/exports`. Los PRs desde **forks** no ejecutan el job (sin secrets).
- **Secrets** (Settings → Secrets and variables → Actions):

| Secret | Required | Description |
|--------|----------|-------------|
| `EXPORT_GOOGLE_APPLICATION_CREDENTIALS` | Yes | Export SA JSON, **base64 single line** (`base64 -i key.json \| tr -d '\n'`) |
| `DBT_GOOGLE_APPLICATION_CREDENTIALS` | No | Si existe, **dbt parse** usa esta key; si no, reutiliza la key de export (misma SA posible). |
| `BIGQUERY_PROJECT_ID` | Yes | Same as elsewhere in the repo |
| `BIGQUERY_LOCATION` | No | Default **`US`** (workflow y script, alineado a `.env.example`). Si tus datasets están en otra región (`southamerica-east1`, …), definí el secret o `EXPORT_BIGQUERY_LOCATION`. |
| `EXPORT_GCS_BUCKET_NAME` | No | Default **`agroprotect-exports-prod`**. **Bucket id only** (no `gs://`). Sobreescribí con secret/variable si usás otro bucket. |
| `BIGQUERY_DATASET_ID` | No | Default **`analytics`** (workflow y modo auto). Debe coincidir con el `schema` de dbt **prod**. |
| `EXPORT_TABLE_MAP` | No* | *Solo modo explícito. Si **omitís** este secret y `EXPORT_BQ_TABLE_REF`, corre **modo auto** (todos los datasets listados arriba). |
| `EXPORT_BQ_TABLE_REF` | No* | Una tabla `dataset.table` si no usás mapa JSON. |
| `EXPORT_GCS_BLOB_NAME` | No | File name without `.json` (only with `EXPORT_BQ_TABLE_REF`) |
| `EXPORT_GCS_PREFIX` | No | If the secret is unset, the script defaults to `prod/exports` |
| `EXPORT_BQ_DATASETS` | No | Lista `stg,analytics,marts` por defecto; sobreescribe con secret o variable de repo. |

### Sin `EXPORT_TABLE_MAP` (recomendado)

Dejá vacíos (o no crees) los secrets `EXPORT_TABLE_MAP` y `EXPORT_BQ_TABLE_REF`. El workflow pasa `BIGQUERY_DATASET_ID` desde secrets (default `analytics`) y el script exporta **todo lo extraíble** en `stg`, ese dataset y `marts`.

### Lista manual opcional

Si preferís solo algunas tablas, definí **una** de:

```text
{"locations":"stg.stg_agro_locations","weather":"stg.stg_agro_clima_diario_nasa_power"}
```

If you create **`EXPORT_GCS_PREFIX`** as an **empty** secret, GitHub may omit it; to force an empty prefix you can skip the secret and rely on the script default. For a custom prefix, set the secret to e.g. `prod/exports` (no trailing slash).

## Optional next steps

- Bucket CORS if the browser calls signed URLs directly.
- **dbt-cd-docs** sigue publicando docs/manifest en Pages; el export en CI ya genera su propio `manifest.json` con `dbt parse` y lo sube a GCS.
