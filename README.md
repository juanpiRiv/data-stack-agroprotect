# AgroProtect Platform

AgroProtect is an agricultural intelligence platform focused on Argentina.

This repository contains the data platform for AgroProtect: extraction, transformation, testing, and export workflows that turn raw weather and reference data into analytics-ready models on BigQuery.

The user-facing frontend currently lives in a separate companion repository:

- Frontend: `https://github.com/Ingbakk16/front-agroprotect`

## What lives in this repository

All implementation code in this monorepo lives under `agro-protect/`.

It includes:

- Meltano-based extraction pipelines
- dbt transformation layers on BigQuery
- SQLFluff linting for SQL model quality
- seed-based economic and yield enrichment
- BigQuery to GCS export utilities for downstream apps
- GitHub Actions for CI, data pipeline runs, exports, and docs workflows

## Current platform scope

The data platform currently covers:

- raw ingestion of weather and location data through `tap-agro`
- canonical dbt modeling with `staging`, `intermediate`, and `marts`
- province-level tax enrichment
- historical crop yield enrichment
- weather quality checks and derived agronomic indicators
- curated analytical marts for downstream applications

The main analytical output introduced in this phase is a province-level mart at:

- `province + campaign + crop`

That mart combines:

- campaign-level weather summaries
- province-level crop yield
- province-level tax variables
- climate quality and coverage indicators

## High-level architecture

```text
Source APIs / raw inputs
  -> Meltano extraction
  -> BigQuery raw datasets
  -> dbt staging
  -> dbt intermediate
  -> dbt marts
  -> exports / app consumption
```

### Canonical modeling path

```text
tap_agro raw
  -> stg_tap_agro__locations
  -> stg_tap_agro__weather_daily

seed tax_province
  -> stg_seed__tax_province

seed yield_department_campaign
  -> stg_seed__yield_department_campaign

staging
  -> int_location__current
  -> int_weather__daily_base
  -> int_weather__daily_metrics
  -> int_weather__daily_quality
  -> int_tax__province
  -> int_yield__province_campaign

intermediate
  -> dim_location
  -> dim_province
  -> fct_weather_daily
  -> fct_tax_province
  -> fct_yield_province_campaign
  -> mart_agro_province_campaign
```

## What was implemented in this phase

This work moved the project from a mostly staging-oriented dbt setup to a more complete analytical stack.

### Canonical weather path

We added a canonical weather pipeline built on `tap_agro` raw data:

- parsed and typed weather staging models
- robust deduplication by `location_id + date`
- derived weather and agronomic metrics
- quality and anomaly flags
- final weather fact table for analytics

### Economic and yield enrichment

We added two seed-driven business domains:

- provincial tax reference data
- historical crop yield data

The yield dataset was cleaned and consolidated before modeling, including:

- text normalization
- province normalization
- duplicate consolidation
- province-level campaign aggregation

### Final marts

The current curated outputs include:

- `dim_location`
- `dim_province`
- `fct_weather_daily`
- `fct_tax_province`
- `fct_yield_province_campaign`
- `mart_agro_province_campaign`

### Data quality and standards

The new dbt layer was built with:

- dbt tests for uniqueness, nullability, relationships, and business rules
- SQLFluff formatting and linting for the new SQL models
- sandbox validation with `dbt build`
- normalized join keys for province and crop domains

## Example analytical metrics now available

The current models expose metrics such as:

- daily precipitation
- minimum, maximum, and average air temperature
- vapor pressure deficit
- growing degree days
- frost days
- heat stress days
- heavy rain days
- dry days
- fungal risk days
- campaign precipitation totals
- campaign average temperature
- campaign usable weather ratio
- crop yield per hectare
- province-level tax indicators

## Technology stack

### Data stack

- Python 3.11
- Meltano
- `tap-agro`
- dbt Core
- dbt BigQuery
- BigQuery
- Google Cloud Storage
- SQLFluff
- GitHub Actions

## Frontend companion

AgroProtect also has a separate frontend repository:

- `https://github.com/Ingbakk16/front-agroprotect`

Based on the current repository structure, the frontend stack is:

- Next.js 16
- React 19
- TypeScript
- Tailwind CSS 4
- Radix UI / shadcn-style components
- Recharts
- Leaflet and `leaflet.heat`
- AI SDK with an OpenAI-powered chat route
- Vercel Analytics

### Current frontend scope

The frontend already covers a strong presentation layer for AgroProtect, including:

- a landing page
- an interactive Argentina map
- KPI cards and dashboard views
- zone detail panels
- analytics modal flows
- an AI assistant/chat experience

Right now, it looks like the frontend is primarily a UI and product shell with generated or mock risk data for interaction. The natural next step is to connect it to the curated outputs from this data platform, especially:

- `fct_weather_daily`
- `fct_tax_province`
- `fct_yield_province_campaign`
- `mart_agro_province_campaign`

That can be done through:

- exported NDJSON or JSON artifacts from BigQuery/GCS
- a thin API layer on top of BigQuery
- precomputed app-facing datasets for maps and dashboard views

## Repository structure

```text
data-stack-agroprotect/
├── README.md
├── .github/
└── agro-protect/
    ├── extraction/
    │   -> Meltano extraction layer
    ├── transform/
    │   ├── models/
    │   │   ├── staging/
    │   │   ├── intermediate/
    │   │   └── marts/
    │   ├── seeds/
    │   ├── macros/
    │   └── dbt config
    ├── scripts/
    │   -> BigQuery to GCS export utilities
    └── pyproject.toml
```

## Where to start

- Platform setup and local execution: `agro-protect/README.md`
- Model-level documentation: `agro-protect/transform/models/README.md`
- GitHub Actions: `.github/workflows/`

## Summary

AgroProtect is evolving into a full-stack agricultural intelligence product:

- this repository provides the trusted analytical data foundation
- the separate frontend repository provides the user experience layer

Together, they define the current platform direction: climate-aware, agriculture-focused monitoring and decision support for Argentina.
