{% docs __overview__ %}
# AgroProtect · data stack en BigQuery
Extracción con Meltano (tap **por definir** para datos agro) y modelado con dbt.

## Cómo orientarte
- Las tablas raw las crea Meltano en `<env>_<namespace_del_tap>` cuando configures el extractor.
- Los modelos `stg_*` / marts actuales siguen ligados a fuentes legacy `tap_github` hasta la migración.
- Staging en dataset `stg`; marts en `marts` (prod/ci) o `SANDBOX_<DBT_USER>` en dev.

## Cómo ejecutar en local
1) `set -a; source ../.env; set +a`
2) Con tap configurado: `meltano --environment=prod run <tap> target-bigquery` desde `extraction/`
3) Desde `transform/`: `./scripts/setup-local.sh`, `dbt deps`, `dbt build --target prod` (requiere raw alineado con `sources`)

## Consejos
- `dbt build` sobre `run`; define `DBT_USER` en dev.
- Tras cambiar el tap, actualiza `sources`, macro `ensure_source_datasets` y modelos staging.
{% enddocs %}

{% docs __agroprotect__ %}
# AgroProtect · data stack
Stack BigQuery: Meltano para ingesta y dbt para capas limpias y marts documentados.

## Qué leer después
- `README.md` y `extraction/README.md` para el extractor.
- `models/staging/*.yml` para fuentes (hoy legacy GitHub hasta migración agro).
- `models/production/marts/*.yml` para marts y tests.

## Flujo de equipo
- `.env` alineado con GCP y el tap elegido.
- `dbt build --select <modelo> --target dev` en desarrollo.
- `dbt docs generate --target prod` para revisión cuando toque.
{% enddocs %}
