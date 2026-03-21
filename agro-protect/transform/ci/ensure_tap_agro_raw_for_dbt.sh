#!/usr/bin/env bash
# Crea dataset + tablas crudas mínimas (0 filas) para que dbt pueda compilar vistas
# sobre source('tap_agro', ...) cuando Meltano aún no cargó a ese dataset.
# Idempotente: no toca tablas que ya existen (p. ej. carga real de Meltano).
#
# Importante: OPTIONS(location=…) debe coincidir con BIGQUERY_LOCATION del perfil dbt.
# Si el dataset ya existía en otra región, el workflow de PR alinea BIGQUERY_LOCATION leyendo bq show.
set -euo pipefail

# Proyecto GCP por defecto del repo (sobreescribible con BIGQUERY_PROJECT_ID / secrets).
DEFAULT_BQ_PROJECT_ID="agro-protect-490822"

# GitHub secrets a veces traen \\n o espacios al final → bq falla con "ProjectId must be non-empty".
trim() { printf '%s' "$1" | xargs; }

# Misma resolución que source_tap_agro.yml y dbt-pr-ci (DBT_TAP_RESOLVED_PROJECT lo escribe CI).
PROJECT="$(trim "${DBT_TAP_RESOLVED_PROJECT:-}")"
if [ -z "${PROJECT}" ]; then
  PROJECT="$(trim "${DBT_TAP_AGRO_PROJECT:-}")"
fi
if [ -z "${PROJECT}" ]; then
  PROJECT="$(trim "${BIGQUERY_PROJECT_ID:-}")"
fi
if [ -z "${PROJECT}" ]; then
  PROJECT="${DEFAULT_BQ_PROJECT_ID}"
fi

LOC="$(trim "${BIGQUERY_LOCATION:-}")"
DS="$(trim "${DBT_TAP_AGRO_DATASET:-}")"

if [ -z "${PROJECT}" ]; then
  echo "::error::Proyecto BigQuery vacío: definí BIGQUERY_PROJECT_ID o DBT_TAP_AGRO_PROJECT (o DBT_TAP_RESOLVED_PROJECT en CI)."
  exit 1
fi
if [ -z "${LOC}" ]; then
  echo "::error::BIGQUERY_LOCATION vacío o solo espacios."
  exit 1
fi
if [ -z "${DS}" ]; then
  echo "::error::DBT_TAP_AGRO_DATASET vacío o solo espacios."
  exit 1
fi

export CLOUDSDK_CORE_PROJECT="${PROJECT}"
export GOOGLE_CLOUD_PROJECT="${PROJECT}"
# Evita "ProjectId must be non-empty" en clientes que toman quota project del entorno.
export GOOGLE_CLOUD_QUOTA_PROJECT="${PROJECT}"

echo "Ensuring BigQuery dataset ${PROJECT}.${DS} (location=${LOC}) for dbt sources…"

bq_can_list_project() {
  local p="$1"
  [ -n "${p}" ] && bq ls --project_id="${p}" "${p}:" >/dev/null 2>&1
}

# Preflight: si el ID configurado no es accesible pero el project_id del JSON de la SA sí, alineamos (CI suele tener secret ≠ proyecto de la key).
if ! bq_can_list_project "${PROJECT}"; then
  KEY_PID=""
  KEY_EMAIL=""
  if [ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ] && [ -f "${GOOGLE_APPLICATION_CREDENTIALS}" ] && command -v jq >/dev/null 2>&1; then
    KEY_PID="$(trim "$(jq -r '.project_id // empty' "${GOOGLE_APPLICATION_CREDENTIALS}")")"
    KEY_EMAIL="$(trim "$(jq -r '.client_email // empty' "${GOOGLE_APPLICATION_CREDENTIALS}")")"
  fi

  if [ -n "${KEY_PID}" ] && [ "${KEY_PID}" != "${PROJECT}" ] && bq_can_list_project "${KEY_PID}"; then
    echo "::warning::El proyecto '${PROJECT}' no es accesible con esta SA; usando el project_id de la clave JSON ('${KEY_PID}'). Corregí el secret BIGQUERY_PROJECT_ID o concedé a ${KEY_EMAIL} roles BigQuery en '${PROJECT}' si los datos deben vivir ahí."
    PROJECT="${KEY_PID}"
    export CLOUDSDK_CORE_PROJECT="${PROJECT}"
    export GOOGLE_CLOUD_PROJECT="${PROJECT}"
    export GOOGLE_CLOUD_QUOTA_PROJECT="${PROJECT}"
    # Pasos siguientes del job (dbt) leen el mismo proyecto.
    if [ -n "${GITHUB_ENV:-}" ]; then
      {
        echo "BIGQUERY_PROJECT_ID=${PROJECT}"
        echo "DBT_TAP_RESOLVED_PROJECT=${PROJECT}"
      } >> "${GITHUB_ENV}"
    fi
    echo "Ensuring BigQuery dataset ${PROJECT}.${DS} (location=${LOC}) for dbt sources… (proyecto = clave JSON)"
  elif [ -n "${KEY_PID}" ] && [ "${KEY_PID}" = "${PROJECT}" ]; then
    echo "::error::BigQuery no accede al proyecto '${PROJECT}' pero la SA pertenece a ese mismo proyecto: en GCP → IAM del proyecto '${PROJECT}' añadí a ${KEY_EMAIL} los roles **BigQuery Data Editor** (o Admin) y **BigQuery Job User**."
    exit 2
  else
    KEY_HINT=""
    [ -n "${KEY_EMAIL}" ] && KEY_HINT=" SA: ${KEY_EMAIL}; project_id en JSON=${KEY_PID:-vacío}."
    echo "::error::BigQuery no accede a '${PROJECT}'.${KEY_HINT} Ajustá BIGQUERY_PROJECT_ID al ID real (Console → Configuración del proyecto) o concedé a la SA permisos BigQuery en ese proyecto."
    exit 2
  fi
fi

if ! bq show --format=none --project_id="${PROJECT}" "${PROJECT}:${DS}" >/dev/null 2>&1; then
  bq --project_id="${PROJECT}" mk --dataset --location="${LOC}" "${PROJECT}:${DS}"
else
  echo "  dataset ${DS} already exists — skip create"
fi

ensure_table() {
  local table="$1"
  local ddl="$2"
  if bq show --format=none --project_id="${PROJECT}" "${PROJECT}:${DS}.${table}" >/dev/null 2>&1; then
    echo "  table ${DS}.${table} already exists — skip"
    return 0
  fi
  echo "  creating empty ${DS}.${table}…"
  bq query --use_legacy_sql=false --project_id="${PROJECT}" "${ddl}"
}

LOCATIONS_DDL="
CREATE TABLE IF NOT EXISTS \`${PROJECT}.${DS}.locations\` (
  _sdc_extracted_at TIMESTAMP,
  _sdc_received_at TIMESTAMP,
  _sdc_batched_at TIMESTAMP,
  _sdc_deleted_at TIMESTAMP,
  _sdc_sequence INT64,
  _sdc_table_version INT64,
  data STRUCT<
    location_id STRING,
    location_name STRING,
    province_name STRING,
    latitude STRING,
    longitude STRING
  >
);
"

CLIMA_DDL="
CREATE TABLE IF NOT EXISTS \`${PROJECT}.${DS}.clima_diario_nasa_power\` (
  _sdc_extracted_at TIMESTAMP,
  _sdc_received_at TIMESTAMP,
  _sdc_batched_at TIMESTAMP,
  _sdc_deleted_at TIMESTAMP,
  _sdc_sequence INT64,
  _sdc_table_version INT64,
  data STRUCT<
    location_id STRING,
    \`date\` STRING,
    x_source STRING,
    x_source_type STRING,
    x_loaded_at STRING,
    T2M_MAX STRING,
    T2M_MIN STRING,
    T2M STRING,
    T2MDEW STRING,
    T2MWET STRING,
    TS STRING,
    PRECTOTCORR STRING,
    RH2M STRING,
    QV2M STRING,
    ALLSKY_SFC_SW_DWN STRING,
    CLRSKY_SFC_SW_DWN STRING,
    WS2M STRING,
    WS2M_MAX STRING,
    WD2M STRING,
    PS STRING,
    CLOUD_AMT STRING
  >
);
"

ensure_table "locations" "${LOCATIONS_DDL}"
ensure_table "clima_diario_nasa_power" "${CLIMA_DDL}"

echo "Done."
