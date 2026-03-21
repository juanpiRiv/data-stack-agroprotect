# Extracción (Meltano) — AgroProtect

## tap-agro (meteorología)

Extractor custom instalado desde GitHub: [juanpiRiv/tap-meteorology](https://github.com/juanpiRiv/tap-meteorology) (`pip_url` en `meltano.yml` apunta a `@main`; para fijar versión usá `@v0.1.0`).

### Configuración

- **`data/locations.csv`**: catálogo de sitios (~110 localidades con peso agronómico o logístico, todas las regiones productivas). Columnas: `location_id`, `location_name`, `province_name`, `latitude`, `longitude`, `country_code`, `is_active`. Las coordenadas son aproximadas (centro urbano); afiná por lote/campo si necesitás microclima.
- **`location_catalog_path`**: en `meltano.yml` está como `data/locations.csv` (relativo; ejecutá Meltano **desde `extraction/`**). Para ruta absoluta:

  ```bash
  meltano --environment=prod config set tap-agro location_catalog_path /ruta/absoluta/locations.csv
  ```

- **`start_date` / `end_date`**: por defecto el YAML lleva **fase 1** del backfill (**2025-01-01** hasta una **`end_date`** reciente). Cuando termine esa corrida, pasá a **2024** con `config set` (ej. `2024-01-01` … `2024-12-31`) y repetí hacia atrás; o usá **`run_tap_agro_bq_yearly.sh`** para años completos. Para **“hoy”** sin editar el archivo:  
  `meltano --environment=prod config set tap-agro end_date "$(TZ=America/Argentina/Buenos_Aires date +%Y-%m-%d)"`  
  Reducí el rango en pruebas. Por defecto el repo usa **NASA POWER** (mejor para históricos largos; cuotas distintas a Open-Meteo). Para **Open-Meteo** (más fresco, límites duros en plan gratis): `use_open_meteo: true`, `use_nasa_power: false`, `select` → `clima_diario_open_meteo.*`, y subí `request_delay_seconds` (p. ej. 8–12).

### Carga diaria (CI)

En GitHub Actions, **`data-pipeline.yml`** hace **un solo comando** `meltano run tap-agro target-bigquery`: primero **extract** (APIs → Singer) y al terminar el stream, **load** a **GCP BigQuery** (dataset `{env}_tap_agro`).

- **Cron diario:** ventana = **ayer** en `America/Argentina/Buenos_Aires`, entorno **prod**.
- **Run workflow (manual):** por defecto **mismo ELT que el diario** (`elt_daily_yesterday`). Opciones: `elt_meltano_yml` (fechas cortas del repo) o `validate_only` (solo install + discover).

## Extract + load manual (tu máquina)

Mismo flujo que en CI: **un** `meltano run` en cadena tap → target.

```bash
cd agro-protect
source .venv/bin/activate
set -a && source .env && set +a
cd extraction
meltano install   # si hace falta
```

**Opción A — Igual que el pipeline diario (ayer, Argentina):**

```bash
export TZ=America/Argentina/Buenos_Aires
# Linux (GitHub/ubuntu): date -d yesterday
# macOS: DAY=$(date -v-1d +%Y-%m-%d)
DAY=$(date -d yesterday +%Y-%m-%d)
meltano --environment=prod config set tap-agro start_date "$DAY"
meltano --environment=prod config set tap-agro end_date "$DAY"
meltano --environment=prod run tap-agro target-bigquery
```

**Opción B — Fechas del `meltano.yml` (ventana corta de prueba):**

```bash
meltano --environment=prod run tap-agro target-bigquery
```

**Opción C — Histórico ~10 años (varias corridas):**

```bash
./scripts/run_tap_agro_bq_yearly.sh
```

**Estado incremental:** en **local** podés no definir `MELTANO_STATE_BACKEND_URI` y Meltano guarda el estado en **`extraction/.meltano/`** (suficiente para desarrollo). En **CI/equipo** conviene un **`gs://bucket-real/meltano/state`** con facturación activa en el proyecto del bucket.

## Carga histórica (~10 años) — **solo manual**

No está automatizada en GitHub Actions. Usá en tu máquina (o runner propio) con `.env` cargado:

```bash
cd extraction
./scripts/run_tap_agro_bq_yearly.sh
```

Sin argumentos recorre **2016 hasta hoy** (orden **forward**): años calendario completos hasta el año anterior, y al final la “cola” del año en curso hasta hoy.

**Orden inverso** (primero lo reciente: 2026→hoy, luego 2025 entero, 2024… hasta 2016):

```bash
YEAR_ORDER=reverse PAUSE_BETWEEN_YEARS_SEC=300 ./scripts/run_tap_agro_bq_yearly.sh
```

Las fechas del script usan **`TZ`** si ya lo exportaste; si no, **`America/Argentina/Buenos_Aires`**. El `meltano.yml` sigue llevando **fechas cortas** solo para pruebas / CI.

## Variables de entorno

- Plantilla solo extracción: **`.env.example`** en esta carpeta (o seguí usando **`../.env`** en la raíz del paquete).

## Comandos

Desde `agro-protect/`:

```bash
set -a && source .env && set +a
cd extraction
meltano install
meltano invoke tap-agro --discover
```

Prueba local sin BigQuery:

```bash
meltano run tap-agro target-jsonl
```

Carga a BigQuery **en una sola ventana** (fechas en `meltano.yml`):

```bash
meltano --environment=prod run tap-agro target-bigquery
```

Carga **por años** (recomendado con muchas localidades / ventana larga): script que ajusta `start_date`/`end_date` y ejecuta varias corridas:

```bash
./scripts/run_tap_agro_bq_yearly.sh
# o fechas fijas: ./scripts/run_tap_agro_bq_yearly.sh 2016 2025 2026-03-20
# entorno Meltano (default prod): MELTANO_ENV=dev ./scripts/run_tap_agro_bq_yearly.sh
```

Tras el script, las fechas quedan en **overrides** de Meltano (`.meltano/`), no en `meltano.yml`. **Meltano 4+:** `meltano --environment=prod config list tap-agro` y `meltano --environment=prod config reset tap-agro` (no uses `config tap-agro set`; eso era la CLI vieja).

`target-bigquery` en `meltano.yml` usa **`method: batch_job`** (Load Job en BigQuery) y **`batch_size: 100000`** (raw JSON + vista).

Dataset raw: **`{entorno}_tap_agro`** (por ejemplo `prod_tap_agro`).

### Streams esperados

- `locations`
- `clima_diario_nasa_power` (default actual)

(Open-Meteo: `clima_diario_open_meteo.*` en `select` si activás `use_open_meteo`.)

## Error: `project` is a required property / KeyError project

`meltano.yml` toma **`BIGQUERY_PROJECT_ID`**, **`BIGQUERY_LOCATION`** y **`MELTANO_GOOGLE_APPLICATION_CREDENTIALS`** del entorno. Sin `source ../.env`, quedan vacías.

Si en los logs el `target-bigquery` apunta a **otro repo** (rutas con `lite-data-stack-bigquery` u otro path), el `.meltano` está mezclado: desde `extraction/` ejecutá `rm -rf .meltano` y `meltano install` de nuevo **en este proyecto**.

## `Unable to persist state` / 403 en `storage.googleapis.com` / facturación cerrada

Meltano intentó escribir el **state** en **`MELTANO_STATE_BACKEND_URI`** (p. ej. `gs://tu-bucket/...` copiado del ejemplo). Google devuelve **403** con *“The billing account for the owning project is disabled in state closed”* cuando el bucket no existe, es de otro proyecto sin permisos, o el **proyecto de GCP del bucket tiene la cuenta de facturación cerrada**.

**Qué hacer:**

1. **Solo local:** comentá o borrá **`MELTANO_STATE_BACKEND_URI`** del `.env` y volvé a correr; el estado queda en `.meltano` (la próxima corrida incremental puede repetir ventana si no había state válido guardado antes).
2. **GCS de verdad:** creá un bucket en un proyecto con **facturación activa**, asigná permisos al service account de Meltano (`storage.objects.create` / `get` / `delete` en ese bucket) y poné `MELTANO_STATE_BACKEND_URI=gs://ese-bucket/meltano/state`.

El warning *incremental state has not been updated* significa que **esta corrida no actualizó bookmarks en el backend**; la carga a BigQuery puede haber terminado igual.

## Open-Meteo `429` (minuto u hora)

La API pública tiene **tope por minuto** y **por hora**. Con ~110 localidades y muchas llamadas seguidas, podés ver:

- *Minutely API request limit exceeded* → subí `request_delay_seconds` o esperá ~1 minuto.
- *Hourly API request limit exceeded. Please try again in the next hour* → el **Singer SDK solo reintenta unas 5 veces** (unos segundos en total) y **no espera una hora**, así que el tap **corta** aunque la API diga “volvé en una hora”.

**No hace falta borrar `meltano.db`** por esto: el problema es cuota de Open-Meteo, no la base local. El **state** (GCS o `.meltano`) puede quedar a medias tras un fallo; al reintentar, el tap suele seguir por los bookmarks.

**Qué hacer (histórico / muchas localidades):**

1. Usá **`./scripts/run_tap_agro_bq_yearly.sh`** (un año por corrida). Con **NASA**, el default suele ser **`request_delay_seconds: 3`**. Con **Open-Meteo**, usá **8–12**; si ves **429** diario/minuto, pausá hasta el día siguiente o pasá temporalmente a NASA.
2. Entre años, enfriá la cuota horaria:  
   `PAUSE_BETWEEN_YEARS_SEC=300 ./scripts/run_tap_agro_bq_yearly.sh`  
   o dejá pasar **~1 h** y volvé a correr el mismo año si falló al final.
3. Más delay:  
   `meltano --environment=prod config set tap-agro request_delay_seconds 10`
4. Si Open-Meteo te pegó **429 diario**, alterná a **NASA** en `meltano.yml` (`use_open_meteo: false`, `use_nasa_power: true`, `clima_diario_nasa_power.*`) o acortá fechas / localidades.
5. Tier de pago / API key en [tap-meteorology](https://github.com/juanpiRiv/tap-meteorology) si necesitás throughput serio.

Mejora durable: en el repo del **tap**, ante 429 “hourly”, backoff largo (p. ej. 3600 s) o más reintentos — hoy el límite de 5 intentos es corto para ese mensaje.

## Qué binario de Meltano usar

Si tenés **otro** `meltano` en el PATH (p. ej. `uv tool install meltano` → 4.0.x), puede chocar con la base `.meltano/meltano.db` creada por el del **venv del proyecto** (4.1.x) y verás `ResolutionError: No such revision or branch 'c0efb3c314eb'`.

**Usá siempre el del proyecto:**

```bash
cd agro-protect
source .venv/bin/activate
hash -r
which meltano   # debe ser .../agro-protect/.venv/bin/meltano
cd extraction
meltano install
```

Si el PATH sigue ganando el de `uv tools`, llamá explícito:

```bash
agro-protect/.venv/bin/meltano --version
agro-protect/.venv/bin/meltano run tap-agro target-jsonl
```

**Si la base quedó inconsistente:** borrá `extraction/.meltano/meltano.db` y volvé a `meltano install` (se pierde solo el estado interno del proyecto Meltano local, no BigQuery).

## Variables `.env` (raíz `agro-protect/`)

- `TARGET_BIGQUERY_*`, `MELTANO_GOOGLE_APPLICATION_CREDENTIALS`, etc. (ver `../.env.example`).
- `MELTANO_STATE_BACKEND_URI` opcional en local; en producción/CI, `gs://…` con bucket y facturación activos.

## Alinear dbt

Cuando el raw exista en BigQuery:

1. Declarar `sources` con schema = `{target}_tap_agro`.
2. Actualizar `transform/macros/ensure_source_datasets.sql`.
3. Añadir modelos `stg_*` / marts (los actuales siguen apuntando a `tap_github` legacy).
