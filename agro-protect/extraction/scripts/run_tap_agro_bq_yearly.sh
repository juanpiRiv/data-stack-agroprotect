#!/usr/bin/env bash
# tap-agro → target-bigquery: un año calendario completo por corrida, más cola hasta END_TAIL_DATE.
#
# Uso (desde extraction/, con .env cargado):
#   set -a && source ../.env && set +a
#   ./scripts/run_tap_agro_bq_yearly.sh
#
# Sin args: desde 2016 hasta HOY (calendario Argentina, mismo huso que tap-agro en meltano.yml).
#   TZ=America/Argentina/Buenos_Aires (default interno del script para calcular año/fecha).
#
# Args opcionales:
#   $1 START_YEAR (default 2016)
#   $2 LAST_FULL_YEAR (solo orden forward; en reverse se ignora)
#   $3 END_TAIL_DATE YYYY-MM-DD (default: hoy) → cola: (LAST+1)-01-01 .. esta fecha
#
# Opcional: PAUSE_BETWEEN_YEARS_SEC=300 — espera entre año y año (enfriar cuotas de API).
#
# Solo años completos (sin cola hasta hoy): SKIP_TAIL=1 — útil si ya cargaste el tramo reciente
# y solo faltan años viejos, p. ej. SKIP_TAIL=1 ./scripts/run_tap_agro_bq_yearly.sh 2016 2022
#
# Orden inverso (priorizá datos recientes): YEAR_ORDER=reverse
#   1) año en curso: (hoy año)-01-01 .. hoy
#   2) años completos: (año-1) .. START_YEAR hacia atrás (2025, 2024, …)
#   Ej: YEAR_ORDER=reverse PAUSE_BETWEEN_YEARS_SEC=300 ./scripts/run_tap_agro_bq_yearly.sh
#
# Nota: `meltano config set` guarda overrides en el proyecto Meltano (.meltano/), no en meltano.yml.
# Si el tap tiene `days_back` activo (run diario), este script hace `config unset days_back` antes de fijar fechas.

set -euo pipefail

# “Hoy” y año calendario (alineado al tap; exportá TZ antes del script si querés otro huso).
TZ_SCRIPT="${TZ:-America/Argentina/Buenos_Aires}"
today_iso() { TZ="$TZ_SCRIPT" date +%Y-%m-%d; }
year_now() { TZ="$TZ_SCRIPT" date +%Y; }

START_YEAR="${1:-2016}"
if [[ -n "${2-}" ]]; then
  LAST_FULL_YEAR="$2"
else
  LAST_FULL_YEAR=$(( $(year_now) - 1 ))
fi
if [[ -n "${3-}" ]]; then
  END_TAIL_DATE="$3"
else
  END_TAIL_DATE="$(today_iso)"
fi
MELTANO_ENV="${MELTANO_ENV:-prod}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

YEAR_ORDER="${YEAR_ORDER:-forward}"
if [[ "${YEAR_ORDER}" != "forward" && "${YEAR_ORDER}" != "reverse" ]]; then
  echo "error: YEAR_ORDER debe ser forward o reverse (recibido: ${YEAR_ORDER})"
  exit 1
fi

if [[ "${YEAR_ORDER}" == "reverse" ]]; then
  _yc="$(year_now)"
  echo "Orden: INVERSO — primero ${_yc}-01-01 .. ${END_TAIL_DATE}, luego años completos $((_yc - 1))..${START_YEAR} (TZ: ${TZ_SCRIPT})"
else
  echo "Ventana: años completos ${START_YEAR}..${LAST_FULL_YEAR}, cola hasta ${END_TAIL_DATE} (TZ: ${TZ_SCRIPT})"
fi

if ! [[ "${START_YEAR}" =~ ^[0-9]{4}$ ]] || ! [[ "${LAST_FULL_YEAR}" =~ ^[0-9]{4}$ ]]; then
  echo "error: START_YEAR y LAST_FULL_YEAR deben ser años de 4 dígitos (recibido: ${START_YEAR}, ${LAST_FULL_YEAR})"
  exit 1
fi

if ! [[ "${END_TAIL_DATE}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "error: END_TAIL_DATE debe ser YYYY-MM-DD (recibido: ${END_TAIL_DATE})"
  exit 1
fi

if ! command -v meltano >/dev/null 2>&1; then
  echo "meltano no está en PATH (activá agro-protect/.venv o extraction/venv)."
  exit 1
fi

# Meltano 4+: `meltano config set <plugin> <key> <value>` (no `config tap-agro set`).
# --environment alinea overrides con el mismo entorno que el `run` (p. ej. prod → prod_tap_agro).
# Quitar `days_back` si quedó de un run diario; si no, el tap ignora start_date/end_date.
cfg_clear_days_back() {
  meltano --environment="${MELTANO_ENV}" config unset tap-agro days_back 2>/dev/null || true
}

cfg_set() {
  meltano --environment="${MELTANO_ENV}" config set tap-agro "$1" "$2"
}

run_full_year() {
  local y="$1"
  echo "======== Año completo ${y} (entorno ${MELTANO_ENV}) ========"
  cfg_clear_days_back
  cfg_set start_date "${y}-01-01"
  cfg_set end_date "${y}-12-31"
  meltano --environment="${MELTANO_ENV}" run tap-agro target-bigquery
}

run_range() {
  local d0="$1" d1="$2" label="$3"
  echo "======== ${label}: ${d0} .. ${d1} (entorno ${MELTANO_ENV}) ========"
  cfg_clear_days_back
  cfg_set start_date "${d0}"
  cfg_set end_date "${d1}"
  meltano --environment="${MELTANO_ENV}" run tap-agro target-bigquery
}

maybe_pause() {
  _pause="${PAUSE_BETWEEN_YEARS_SEC:-0}"
  if [[ "${_pause}" =~ ^[0-9]+$ ]] && [ "${_pause}" -gt 0 ]; then
    echo "Pausa ${_pause}s entre corridas..."
    sleep "${_pause}"
  fi
}

if [[ "${YEAR_ORDER}" == "reverse" ]]; then
  Y_CUR="$(year_now)"
  TAIL_START="${Y_CUR}-01-01"
  if [[ "${END_TAIL_DATE}" < "${TAIL_START}" ]]; then
    echo "error: END_TAIL_DATE (${END_TAIL_DATE}) debe ser >= ${TAIL_START}"
    exit 1
  fi
  run_range "${TAIL_START}" "${END_TAIL_DATE}" "Año en curso ${Y_CUR}"
  LAST_REV=$((Y_CUR - 1))
  if [ "${LAST_REV}" -ge "${START_YEAR}" ]; then
    maybe_pause
    for ((y = LAST_REV; y >= START_YEAR; y--)); do
      run_full_year "$y"
      if [ "${y}" -gt "${START_YEAR}" ]; then
        maybe_pause
      fi
    done
  fi
else
  if [ "${START_YEAR}" -le "${LAST_FULL_YEAR}" ]; then
    for ((y = START_YEAR; y <= LAST_FULL_YEAR; y++)); do
      run_full_year "$y"
      _pause="${PAUSE_BETWEEN_YEARS_SEC:-0}"
      if [ "${y}" -lt "${LAST_FULL_YEAR}" ] && [[ "${_pause}" =~ ^[0-9]+$ ]] && [ "${_pause}" -gt 0 ]; then
        echo "Pausa ${_pause}s antes del siguiente año..."
        sleep "${_pause}"
      fi
    done
  fi

  if [[ "${SKIP_TAIL:-0}" == "1" ]]; then
    echo "SKIP_TAIL=1 — no se ejecuta la cola tras ${LAST_FULL_YEAR}-12-31."
  else
    TAIL_YEAR=$((LAST_FULL_YEAR + 1))
    TAIL_START="${TAIL_YEAR}-01-01"
    if [[ "${END_TAIL_DATE}" < "${TAIL_START}" ]]; then
      echo "error: END_TAIL_DATE (${END_TAIL_DATE}) debe ser >= ${TAIL_START}"
      exit 1
    fi

    echo "======== Cola ${TAIL_YEAR}: ${TAIL_START} .. ${END_TAIL_DATE} (entorno ${MELTANO_ENV}) ========"
    cfg_clear_days_back
    cfg_set start_date "${TAIL_START}"
    cfg_set end_date "${END_TAIL_DATE}"
    meltano --environment="${MELTANO_ENV}" run tap-agro target-bigquery
  fi
fi

echo "Hecho. Fechas de tap-agro quedaron en overrides de Meltano (ver: meltano --environment=${MELTANO_ENV} config list tap-agro)."
echo "Para volver a lo declarado en meltano.yml: meltano --environment=${MELTANO_ENV} config reset tap-agro"
