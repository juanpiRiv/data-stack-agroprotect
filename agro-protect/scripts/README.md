# Export BigQuery → GCS (datos para frontend)

Flujo mínimo: **bucket + cuenta de servicio en GCP** (paso 1) y **script local** que escribe JSON por línea (NDJSON) en el bucket (paso 2).

El formato de salida es **NDJSON** (newline-delimited JSON): una fila de BigQuery = una línea con un objeto JSON. En Next.js podés leerlo con `response.text()` y `.split("\n").filter(Boolean).map(JSON.parse)` o pedir un solo archivo pequeño y tratarlo como líneas.

---

## Paso 1 — GCP: bucket, cuenta de servicio y permisos

### 1.1 Bucket

1. En [Cloud Storage](https://console.cloud.google.com/storage) → **Crear bucket**.
2. Nombre único global (ej. `agroprotect-exports-prod`).
3. **Ubicación**: misma región que BigQuery (la que usás en `BIGQUERY_LOCATION`).
4. **Prevención de acceso público**: activada (recomendado).
5. **Control de acceso uniforme**: activado.

### 1.2 Cuenta de servicio

1. **IAM y administración** → **Cuentas de servicio** → **Crear**.
2. Nombre descriptivo, ej. `bq-export-to-gcs`.
3. **Claves** → **Agregar clave** → JSON → descargá el archivo para uso local (`chmod 600`).

No hace falta que sea la misma que Meltano/dbt: es mejor una SA solo para export.

### 1.3 Permisos (mínimo razonable)

Sobre la **cuenta de servicio** del export:

| Ámbito | Rol sugerido | Para qué |
|--------|----------------|----------|
| **Proyecto** (donde corre el job de extracción) | `BigQuery Job User` | Ejecutar `extract` |
| **Dataset(s)** de BigQuery que vas a leer | `BigQuery Data Viewer` | Leer tablas/vistas |
| **Bucket** de export | `Storage Object Admin` (o `Object Creator` + `Object Viewer` en el prefijo si usás condiciones IAM) | Escribir `gs://…/*.json` |

Si el dataset está en otro proyecto, concedé **Data Viewer** allí y **Job User** donde ejecutás el cliente (normalmente el mismo proyecto que en `BIGQUERY_PROJECT_ID`).

### 1.4 Comprobar con gcloud (opcional)

Reemplazá placeholders:

```bash
export PROJECT=tu-proyecto
export SA=bq-export-to-gcs@${PROJECT}.iam.gserviceaccount.com
export BUCKET=tu-bucket-exports

gcloud config set project "${PROJECT}"

gsutil mb -l US "gs://${BUCKET}"   # ajustá región a la tuya

gcloud projects add-iam-policy-binding "${PROJECT}" \
  --member="serviceAccount:${SA}" \
  --role="roles/bigquery.jobUser"

gcloud projects add-iam-policy-binding "${PROJECT}" \
  --member="serviceAccount:${SA}" \
  --role="roles/bigquery.dataViewer"
# Si los datos están en un dataset concreto, preferí roles/bigquery.dataViewer a nivel dataset en la consola.

gsutil iam ch serviceAccount:${SA}:roles/storage.objectAdmin "gs://${BUCKET}"
```

---

## Paso 2 — Probar el export en local

### 2.1 Dependencias

Desde la raíz `agro-protect/` (con venv activado):

```bash
uv pip install -r scripts/requirements-export.txt
# o, si usás el paquete editable:
uv pip install -e ".[export]"
```

### 2.2 Variables de entorno

Podés añadir al `.env` (ver comentarios en `.env.example`) o exportar en la shell:

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/ruta/segura/bq-export-to-gcs.json
export BIGQUERY_PROJECT_ID=tu-proyecto
export EXPORT_GCS_BUCKET_NAME=tu-bucket-exports
export EXPORT_GCS_PREFIX=prod/exports

# Opción A — varias tablas/vistas (valores = dataset.tabla en tu proyecto)
export EXPORT_TABLE_MAP='{"locations":"analytics.stg_agro_locations","clima":"analytics.stg_agro_clima_diario_nasa_power"}'

# Opción B — una sola tabla
# export EXPORT_BQ_TABLE_REF=analytics.stg_agro_locations
# export EXPORT_GCS_BLOB_NAME=locations   # → prod/exports/locations.json
```

**Nota:** las tablas deben existir en BigQuery. Podés exportar **raw** (`prod_tap_agro.*`) o **vistas dbt** (`stg_agro_*` en tu dataset `analytics` / `BIGQUERY_DATASET_ID`). Ejemplos de `EXPORT_TABLE_MAP` (una sola línea JSON):

```text
{"clima":"tu-proyecto.prod_tap_agro.clima_diario_nasa_power","locations":"tu-proyecto.prod_tap_agro.locations"}
```

Tras `dbt run` sobre los staging agro:

```text
{"clima":"tu-proyecto.analytics.stg_agro_clima_diario_nasa_power","locations":"tu-proyecto.analytics.stg_agro_locations"}
```

Reemplazá `tu-proyecto` por tu `BIGQUERY_PROJECT_ID` si el script no usa ya el proyecto por defecto del cliente.

### 2.3 Ejecutar

```bash
cd agro-protect
set -a && source .env && set +a   # si usás .env
python scripts/export_to_gcs.py
```

Salida esperada: líneas `OK proyecto.dataset.tabla -> gs://bucket/prefijo/archivo.json`. Verificá en la consola de GCS que aparezcan los objetos.

### Límites

BigQuery puede exigir **comodín** en la URI si el extract supera ~1 GiB por archivo. Este script usa **un archivo por tabla** sin comodín; para tablas enormes habría que ampliar el script (URI `nombre-*.json` y varios shards).

---

## Relación con `data-pipeline` (extracción Meltano)

- **`data-pipeline`** ([`.github/workflows/data-pipeline.yml`](../../.github/workflows/data-pipeline.yml)) carga raw en **`{env}_tap_agro`**.
- **`export-bigquery-gcs`** es **independiente**: no espera a dbt. Podés exportar tablas **raw** o **vistas** ya desplegadas.
- Tras un ELT exitoso en `main`, el workflow de export también puede dispararse vía **`workflow_run`** (misma conclusión exitosa de `data-pipeline`). Sigue habiendo **cron** y **manual**; revisá duplicados si el cron cae cerca del fin del pipeline.

## Pipeline en GitHub Actions

Workflow: **`.github/workflows/export-bigquery-gcs.yml`** (`export-bigquery-gcs`).

- **Cuándo corre:** cada **6 horas** (UTC), **manual**, al **push a `main`** si cambian el script / `requirements-export.txt` / el workflow, y cuando **`data-pipeline`** termina **con éxito** en `main` (export opcional encadenado).
- **Secrets** (Settings → Secrets and variables → Actions):

| Secret | Obligatorio | Descripción |
|--------|-------------|-------------|
| `EXPORT_GOOGLE_APPLICATION_CREDENTIALS` | Sí | JSON de la SA de export, **base64 en una sola línea** (`base64 -i key.json \| tr -d '\n'`) |
| `BIGQUERY_PROJECT_ID` | Sí | Mismo que usás en el resto del repo |
| `EXPORT_GCS_BUCKET_NAME` | Sí | Ej. `agroprotect-exports-prod` |
| `EXPORT_TABLE_MAP` | Uno u otro | JSON en **una línea**, ej. `{"locations":"analytics.stg_agro_locations"}` |
| `EXPORT_BQ_TABLE_REF` | Uno u otro | `dataset.tabla` si exportás una sola tabla |
| `EXPORT_GCS_BLOB_NAME` | No | Nombre del archivo sin `.json` (solo con `EXPORT_BQ_TABLE_REF`) |
| `EXPORT_GCS_PREFIX` | No | Si no definís el secret, el script usa `prod/exports` por defecto |

Si definís **`EXPORT_GCS_PREFIX`** como secret vacío, GitHub puede omitirlo; para forzar prefijo vacío no hace falta secret (dejá sin crear y usá el default del script). Para un prefijo custom, creá el secret con valor `prod/exports` (sin barra final).

## Siguientes pasos (opcional)

- Manifiesto con URLs firmadas para el front.
- CORS del bucket si el navegador llama directo a URLs firmadas.
