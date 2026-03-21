#!/usr/bin/env bash
# Crea dataset + tablas crudas mínimas (0 filas) para que dbt pueda compilar vistas
# sobre source('tap_agro', ...) cuando Meltano aún no cargó a ese dataset.
# Idempotente: no toca tablas que ya existen (p. ej. carga real de Meltano).
#
# Importante: OPTIONS(location=…) debe coincidir con BIGQUERY_LOCATION del perfil dbt.
# Si el dataset ya existía en otra región, el workflow de PR alinea BIGQUERY_LOCATION leyendo bq show.
set -euo pipefail

PROJECT="${BIGQUERY_PROJECT_ID:?missing BIGQUERY_PROJECT_ID}"
LOC="${BIGQUERY_LOCATION:?missing BIGQUERY_LOCATION}"
DS="${DBT_TAP_AGRO_DATASET:?missing DBT_TAP_AGRO_DATASET}"

echo "Ensuring BigQuery dataset ${PROJECT}.${DS} (location=${LOC}) for dbt sources…"

bq query --use_legacy_sql=false --project_id="${PROJECT}" \
  "CREATE SCHEMA IF NOT EXISTS \`${PROJECT}.${DS}\` OPTIONS(location='${LOC}')"

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
