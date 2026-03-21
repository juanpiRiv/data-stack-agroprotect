# Models README

Este directorio contiene la capa de modelado dbt de AgroProtect.

La ruta canonica actual es:

```text
tap_agro raw
  -> staging
  -> intermediate
  -> marts
```

La idea es separar responsabilidades:

- `staging`: parseo, casteo, renombre, normalizacion de llaves.
- `intermediate`: dedupe, reglas de negocio reutilizables, metricas y calidad.
- `marts`: tablas finales para analisis, export y consumo aguas abajo.

## Mapa rapido

```text
source tap_agro.locations
  -> stg_tap_agro__locations
  -> int_location__current
  -> dim_location

source tap_agro.clima_diario_nasa_power
  -> stg_tap_agro__weather_daily
  -> int_weather__daily_base
  -> int_weather__daily_metrics
  -> int_weather__daily_quality
  -> fct_weather_daily

seed tax_province
  -> stg_seed__tax_province
  -> int_tax__province
  -> fct_tax_province

seed yield_department_campaign
  -> stg_seed__yield_department_campaign
  -> int_yield__province_campaign
  -> fct_yield_province_campaign

int_location__current + int_tax__province + int_yield__province_campaign
  -> dim_province

fct_weather_daily + fct_tax_province + fct_yield_province_campaign
  -> mart_agro_province_campaign
```

## Llaves y convenciones

- `location_id`: llave de ubicacion meteorologica.
- `province_key`: provincia normalizada en mayusculas, sin tildes, para joins estables.
- `crop_key`: cultivo normalizado.
- `campaign_name`: campania agricola en formato `YYYY/YYYY`.
- `campaign_start_year`: si el mes es julio o mayor, la campania empieza ese anio; si no, empieza el anio anterior.

## Fuentes de entrada

### Raw sources

- `source_tap_agro.yml`
  - `locations`
  - `clima_diario_nasa_power`

### Seeds

- `seeds/economic/tax_province.csv`
  - impuestos provinciales agropecuarios.
  - incluye min, max y promedio de inmobiliario rural en USD/ha.
  - incluye alicuota de ingresos brutos agro.
- `seeds/agronomy/yield_department_campaign.csv`
  - rendimiento historico por departamento.
  - se limpio encoding, se normalizaron provincias y se consolidaron duplicados aparentes.
  - alcance actual: `soja`, `maiz`, `trigo`.

## Staging models

### `stg_tap_agro__locations`

- Grano: una fila por snapshot raw de `location_id`.
- Input: `source('tap_agro', 'locations')`.
- Que trae:
  - identificadores y nombres de ubicacion.
  - provincia, departamento, municipio.
  - latitud, longitud, elevacion, pais, activo/inactivo.
  - metadata de carga y metadata `_sdc_*`.
- Como se calcula:
  - parsea el campo raw `data` como JSON.
  - extrae columnas tipadas.
  - genera `province_key` y `department_key` con la macro `normalize_text`.

### `stg_tap_agro__weather_daily`

- Grano: una fila por snapshot raw de `location_id + date`.
- Input: `source('tap_agro', 'clima_diario_nasa_power')`.
- Que trae:
  - clima diario ya renombrado a nombres tecnicos consistentes.
  - `max_air_temp_c`, `min_air_temp_c`, `avg_air_temp_c`.
  - `precipitation_mm`, `relative_humidity_pct`, `wind_speed_mps`, etc.
  - contexto geografico embebido que venia en el raw.
  - metadata `_sdc_*`.
- Como se calcula:
  - parsea `data` como JSON.
  - castea todos los numericos y fechas.
  - renombra variables NASA a nombres mas claros.

### `stg_seed__tax_province`

- Grano: una fila por provincia.
- Input: `ref('tax_province')`.
- Que trae:
  - `province_name`, `province_key`.
  - `rural_property_tax_usd_ha_min`.
  - `rural_property_tax_usd_ha_max`.
  - `rural_property_tax_usd_ha_avg`.
  - `gross_turnover_tax_pct`.
- Como se calcula:
  - tipa el seed y crea `province_key` para joins.

### `stg_seed__yield_department_campaign`

- Grano: una fila por `crop_name + campaign_name + province_name + department_name` del seed limpio.
- Input: `ref('yield_department_campaign')`.
- Que trae:
  - cultivo, provincia, departamento, anio de cosecha.
  - superficie sembrada, cosechada, produccion y rendimiento.
  - `campaign_start_year` y `campaign_end_year`.
  - `crop_key`, `province_key`, `department_key`.
- Como se calcula:
  - tipa campos numericos.
  - deriva inicio y fin de campania desde `campaign_name`.
  - crea llaves normalizadas para joins.

## Intermediate models

### `int_location__current`

- Grano: una fila vigente por `location_id`.
- Input: `ref('stg_tap_agro__locations')`.
- Que trae:
  - la version actual del catalogo de ubicaciones.
- Como se calcula:
  - descarta registros borrados (`_sdc_deleted_at`).
  - rankea por carga mas reciente.
  - usa `source_loaded_at`, `_sdc_extracted_at`, `_sdc_received_at` y `_sdc_sequence` como orden de desempate.

### `int_weather__daily_base`

- Grano: una fila deduplicada por `location_id + date`.
- Input: `ref('stg_tap_agro__weather_daily')` + `ref('int_location__current')`.
- Que trae:
  - la mejor fila diaria disponible por ubicacion y fecha.
  - enriquecimiento de nombre/provincia desde la dimension de ubicacion cuando existe.
  - bandera `has_location_dimension`.
- Como se calcula:
  - descarta nulos de llave y borrados logicos.
  - cuenta cuantas variables meteorologicas no nulas tiene cada fila.
  - deduplica usando este orden:
    1. mas variables no nulas
    2. carga mas reciente
    3. `_sdc_received_at`
    4. `_sdc_extracted_at`
    5. `_sdc_sequence`

### `int_weather__daily_metrics`

- Grano: una fila por `location_id + date`.
- Input: `ref('int_weather__daily_base')`.
- Que trae:
  - calendario: anio, mes, trimestre, semana, mes y campania agricola.
  - metricas derivadas de clima.
- Como se calcula:
  - `temp_range_c = max_air_temp_c - min_air_temp_c`
  - `clear_sky_radiation_gap_mj_m2_day = clearsky - allsky`
  - `heat_index_c`: formula de heat index en Fahrenheit convertida de nuevo a Celsius.
  - `wind_chill_c`: formula clasica usando velocidad convertida a km/h.
  - `vpd_kpa`: `max(saturation_vapor_pressure - actual_vapor_pressure, 0)`.
  - `gdd_base_10_c_days = max(((tmax + tmin) / 2) - 10, 0)`.

### `int_weather__daily_quality`

- Grano: una fila por `location_id + date`.
- Input: `ref('int_weather__daily_metrics')`.
- Que trae:
  - flags de calidad de dato.
  - flags de riesgo agroclimatico diario.
  - bandera final `is_quality_approved`.
- Como se calcula:
  - `critical_null_count`: faltantes en temperatura media, minima, maxima y precipitacion.
  - `has_high_missing_data`: menos de 8 variables climaticas presentes.
  - `temperature_inconsistent`: `min_air_temp_c > max_air_temp_c`.
  - `temperature_outlier`: temperatura media fuera de `[-50, 50]`.
  - `precipitation_outlier`: precipitacion mayor a 400 mm.
  - `wind_outlier`: viento mayor a 50 m/s.
  - `radiation_inconsistent`: radiacion all-sky mayor a clear-sky.
  - `frost_day`: minima menor a 0 C.
  - `heat_stress_day`: maxima mayor a 35 C.
  - `heavy_rain_day`: precipitacion mayor a 25 mm.
  - `dry_day`: precipitacion menor a 1 mm y humedad relativa menor a 35%.
  - `fungal_risk_day`: humedad relativa >= 80, temperatura media entre 15 y 30 C y lluvia positiva.
  - `is_partial_latest_day`: detecta si el ultimo dia cargado vino incompleto.
  - `is_quality_approved`: falso si alguna bandera fuerte de calidad esta activa.

### `int_tax__province`

- Grano: una fila por provincia.
- Input: `ref('stg_seed__tax_province')`.
- Que trae:
  - impuestos provinciales listos para marts.
- Como se calcula:
  - agrega `rural_property_tax_usd_ha_spread = max - min`.

### `int_yield__province_campaign`

- Grano: una fila por `province_key + campaign_name + crop_key`.
- Input: `ref('stg_seed__yield_department_campaign')`.
- Que trae:
  - rendimiento agregado a nivel provincia-campania-cultivo.
  - cantidad de departamentos aportando datos.
- Como se calcula:
  - suma `sown_area_ha`, `harvested_area_ha`, `production_tonnes`.
  - cuenta `department_count`.
  - `yield_kg_ha = production_tonnes * 1000 / harvested_area_ha`.
  - `harvested_share_pct = harvested_area_ha / sown_area_ha`.

## Mart models

### `dim_location`

- Grano: una fila por `location_id`.
- Input: `ref('int_location__current')` + `ref('int_weather__daily_base')`.
- Que trae:
  - catalogo actual de ubicaciones.
  - fallback para ubicaciones presentes en clima pero ausentes en catalogo.
  - bandera `is_catalog_location`.
- Como se calcula:
  - toma todas las ubicaciones actuales del catalogo.
  - agrega ubicaciones solo vistas en clima con el registro mas reciente por `location_id`.

### `dim_province`

- Grano: una fila por `province_key`.
- Input: `ref('int_location__current')`, `ref('int_tax__province')`, `ref('int_yield__province_campaign')`.
- Que trae:
  - nombre canonico de provincia.
  - cobertura por dominio: `has_weather_data`, `has_tax_data`, `has_yield_data`.
- Como se calcula:
  - une provincias de clima, impuestos y rendimiento.
  - prioriza el nombre de provincia observado en clima, luego tax, luego yield.

### `fct_weather_daily`

- Grano: una fila por `location_id + date`.
- Input: `ref('int_weather__daily_quality')` + `ref('dim_location')`.
- Que trae:
  - la tabla diaria final de clima.
  - metricas derivadas y flags de calidad/riesgo.
  - nombre y provincia finales listos para consumo.
- Como se calcula:
  - toma todo lo curado en `int_weather__daily_quality`.
  - vuelve a resolver nombre y provincia desde `dim_location` cuando existe.
  - esta particionada por mes de `date` y clusterizada por `province_key`, `location_id`.

### `fct_tax_province`

- Grano: una fila por provincia.
- Input: `ref('int_tax__province')` + `ref('dim_province')`.
- Que trae:
  - hechos economicos provinciales finales.
- Como se calcula:
  - cruza con `dim_province` para garantizar provincia canonica y consistencia de joins.

### `fct_yield_province_campaign`

- Grano: una fila por `province_key + campaign_name + crop_key`.
- Input: `ref('int_yield__province_campaign')` + `ref('dim_province')`.
- Que trae:
  - hechos finales de rendimiento provincial por campania y cultivo.
- Como se calcula:
  - cruza con `dim_province` para usar la provincia canonica.

### `mart_agro_province_campaign`

- Grano: una fila por `province_key + campaign_name + crop_key`.
- Input: `ref('fct_weather_daily')`, `ref('fct_tax_province')`, `ref('fct_yield_province_campaign')`.
- Que trae:
  - clima agregado por campania.
  - rendimiento provincial por cultivo.
  - variables economicas provinciales.
  - indicadores de cobertura y calidad del clima disponible.
- Como se calcula:
  - primero resume clima por `province_key + campaign_name`:
    - `weather_day_count`
    - `usable_weather_day_count`
    - `weather_location_count`
    - `campaign_precipitation_mm`
    - `avg_campaign_temp_c`
    - `max_campaign_temp_c`
    - `min_campaign_temp_c`
    - `avg_relative_humidity_pct`
    - `avg_vpd_kpa`
    - `total_gdd_base_10`
    - `frost_days`, `heat_days`, `heavy_rain_days`, `dry_days`, `fungal_risk_days`
  - luego hace left join contra yield y tax.
  - deriva `usable_weather_day_ratio` para medir cobertura climatica util.

## Modelos legacy

Todavia existen modelos previos que no forman parte de la ruta principal nueva:

- `stg_agro_locations`
- `stg_agro_clima_diario_nasa_power`
- `stg_clima_diario_nasa`
- `source_nasa.yml`

Se mantienen como referencia o camino opcional, pero el desarrollo nuevo debe apoyarse sobre:

- `stg_tap_agro__*`
- `int_*`
- `marts/*`

## Donde mirar primero

- Si queres entender el raw y el renombre: `staging/`.
- Si queres entender dedupe y formulas: `intermediate/weather/`.
- Si queres la salida final para analisis: `marts/`.
- Si queres el modelo mas importante del proyecto hoy: `marts/agro/mart_agro_province_campaign.sql`.
