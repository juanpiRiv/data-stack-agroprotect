{% docs __overview__ %}
# AgroProtect · data stack en BigQuery
Este proyecto extrae datos de GitHub con Meltano y los modela con dbt para obtener tablas listas para análisis y documentación integrada.

## Cómo orientarte
- Las tablas raw llegan a `<env>_tap_github` vía Meltano.
- Los modelos de staging (`stg_*`) normalizan los datos en el dataset `stg`.
- Los marts publican modelos finales en `marts` (prod/ci) o en `SANDBOX_<DBT_USER>` en dev.
- La documentación de columnas vive junto a cada modelo en archivos YAML.

## Cómo ejecutar en local
1) Cargar variables: `set -a; source ../.env; set +a`.
2) Extracción según el entorno: `meltano --environment=prod run tap-github target-bigquery` (o `dev` / `ci`).
3) Desde `transform/`: `./scripts/setup-local.sh && source venv/bin/activate && dbt deps && dbt build --target prod`.
4) Docs: `dbt docs generate --target prod` y `dbt docs serve`.

## Consejos
- Prefiere `dbt build` a `dbt run` para mantener los tests.
- Define `DBT_USER` para builds de desarrollo en sandbox.
- Añade modelos bajo `models/staging` o `models/production/marts` y su YAML al lado.
{% enddocs %}

{% docs __agroprotect__ %}
# AgroProtect · data stack
Stack listo para operar: Meltano vuelca datos de GitHub en BigQuery y dbt los limpia y publica en marts con tests y documentación.

## Qué leer después
- `README.md` para requisitos y arranque completo.
- `models/staging/*.yml` para fuentes y columnas de staging.
- `models/production/marts/*.yml` para marts, tests y descripciones.

## Flujo de equipo
- Mantén `.env` alineado con tu proyecto GCP y datasets.
- En desarrollo: `dbt build --select <modelo> --target dev`.
- Tras cambios relevantes: `dbt docs generate --target prod` para revisores.
{% enddocs %}
