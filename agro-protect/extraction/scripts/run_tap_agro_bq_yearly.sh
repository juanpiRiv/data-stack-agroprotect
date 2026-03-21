#!/usr/bin/env bash
# tap-agro → target-bigquery: one full calendar year per run, plus tail through END_TAIL_DATE.
#
# Usage (from extraction/, with .env loaded):
#   set -a && source ../.env && set +a
#   ./scripts/run_tap_agro_bq_yearly.sh
#
# No args: from 2016 through TODAY (Argentina calendar, same TZ as tap-agro in meltano.yml).
#   TZ=America/Argentina/Buenos_Aires (script default for year/date math).
#
# Optional args:
#   $1 START_YEAR (default 2016)
#   $2 LAST_FULL_YEAR (forward order only; ignored in reverse)
#   $3 END_TAIL_DATE YYYY-MM-DD (default: today) → tail: (LAST+1)-01-01 .. this date
#
# Optional: PAUSE_BETWEEN_YEARS_SEC=300 — pause between years (API rate limits).
#
# Full years only (no tail to today): SKIP_TAIL=1 — useful if recent data is already loaded
# and only old years remain, e.g. SKIP_TAIL=1 ./scripts/run_tap_agro_bq_yearly.sh 2016 2022
#
# Reverse order (prioritize recent data): YEAR_ORDER=reverse
#   1) current year: (today’s year)-01-01 .. today
#   2) full years: (year-1) .. START_YEAR backward (2025, 2024, …)
#   e.g. YEAR_ORDER=reverse PAUSE_BETWEEN_YEARS_SEC=300 ./scripts/run_tap_agro_bq_yearly.sh
#
# Note: `meltano config set` stores overrides in the Meltano project (.meltano/), not meltano.yml.
# If the tap has `days_back` active (daily run), this script runs `config unset days_back` before setting dates.

set -euo pipefail

# “Today” and calendar year (aligned with tap; export TZ before the script for another zone).
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
  echo "error: YEAR_ORDER must be forward or reverse (got: ${YEAR_ORDER})"
  exit 1
fi

if [[ "${YEAR_ORDER}" == "reverse" ]]; then
  _yc="$(year_now)"
  echo "Order: REVERSE — first ${_yc}-01-01 .. ${END_TAIL_DATE}, then full years $((_yc - 1))..${START_YEAR} (TZ: ${TZ_SCRIPT})"
else
  echo "Window: full years ${START_YEAR}..${LAST_FULL_YEAR}, tail through ${END_TAIL_DATE} (TZ: ${TZ_SCRIPT})"
fi

if ! [[ "${START_YEAR}" =~ ^[0-9]{4}$ ]] || ! [[ "${LAST_FULL_YEAR}" =~ ^[0-9]{4}$ ]]; then
  echo "error: START_YEAR and LAST_FULL_YEAR must be 4-digit years (got: ${START_YEAR}, ${LAST_FULL_YEAR})"
  exit 1
fi

if ! [[ "${END_TAIL_DATE}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "error: END_TAIL_DATE must be YYYY-MM-DD (got: ${END_TAIL_DATE})"
  exit 1
fi

if ! command -v meltano >/dev/null 2>&1; then
  echo "meltano not on PATH (activate agro-protect/.venv or extraction/venv)."
  exit 1
fi

# Meltano 4+: `meltano config set <plugin> <key> <value>` (not `config tap-agro set`).
# --environment aligns overrides with the same env as `run` (e.g. prod → prod_tap_agro).
# Clear `days_back` if left from a daily run; otherwise the tap ignores start_date/end_date.
cfg_clear_days_back() {
  meltano --environment="${MELTANO_ENV}" config unset tap-agro days_back 2>/dev/null || true
}

cfg_set() {
  meltano --environment="${MELTANO_ENV}" config set tap-agro "$1" "$2"
}

run_full_year() {
  local y="$1"
  echo "======== Full year ${y} (env ${MELTANO_ENV}) ========"
  cfg_clear_days_back
  cfg_set start_date "${y}-01-01"
  cfg_set end_date "${y}-12-31"
  meltano --environment="${MELTANO_ENV}" run tap-agro target-bigquery
}

run_range() {
  local d0="$1" d1="$2" label="$3"
  echo "======== ${label}: ${d0} .. ${d1} (env ${MELTANO_ENV}) ========"
  cfg_clear_days_back
  cfg_set start_date "${d0}"
  cfg_set end_date "${d1}"
  meltano --environment="${MELTANO_ENV}" run tap-agro target-bigquery
}

maybe_pause() {
  _pause="${PAUSE_BETWEEN_YEARS_SEC:-0}"
  if [[ "${_pause}" =~ ^[0-9]+$ ]] && [ "${_pause}" -gt 0 ]; then
    echo "Pausing ${_pause}s between runs..."
    sleep "${_pause}"
  fi
}

if [[ "${YEAR_ORDER}" == "reverse" ]]; then
  Y_CUR="$(year_now)"
  TAIL_START="${Y_CUR}-01-01"
  if [[ "${END_TAIL_DATE}" < "${TAIL_START}" ]]; then
    echo "error: END_TAIL_DATE (${END_TAIL_DATE}) must be >= ${TAIL_START}"
    exit 1
  fi
  run_range "${TAIL_START}" "${END_TAIL_DATE}" "Current year ${Y_CUR}"
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
        echo "Pausing ${_pause}s before next year..."
        sleep "${_pause}"
      fi
    done
  fi

  if [[ "${SKIP_TAIL:-0}" == "1" ]]; then
    echo "SKIP_TAIL=1 — skipping tail after ${LAST_FULL_YEAR}-12-31."
  else
    TAIL_YEAR=$((LAST_FULL_YEAR + 1))
    TAIL_START="${TAIL_YEAR}-01-01"
    if [[ "${END_TAIL_DATE}" < "${TAIL_START}" ]]; then
      echo "error: END_TAIL_DATE (${END_TAIL_DATE}) must be >= ${TAIL_START}"
      exit 1
    fi

    echo "======== Tail ${TAIL_YEAR}: ${TAIL_START} .. ${END_TAIL_DATE} (env ${MELTANO_ENV}) ========"
    cfg_clear_days_back
    cfg_set start_date "${TAIL_START}"
    cfg_set end_date "${END_TAIL_DATE}"
    meltano --environment="${MELTANO_ENV}" run tap-agro target-bigquery
  fi
fi

echo "Done. tap-agro dates remain as Meltano overrides (see: meltano --environment=${MELTANO_ENV} config list tap-agro)."
echo "To revert to meltano.yml defaults: meltano --environment=${MELTANO_ENV} config reset tap-agro"
