{% macro ensure_source_datasets() -%}
    {%- set tap_agro_ds = env_var('DBT_TAP_AGRO_DATASET', target.name ~ '_tap_agro') -%}
    {%- set nasa_on = env_var('DBT_ENABLE_RAW_NASA', 'true') | lower in ['true', '1', 'yes'] -%}
    {%- set source_datasets = [tap_agro_ds] -%}
    {%- if nasa_on -%}
        {%- set source_datasets = source_datasets + ['raw_nasa'] -%}
    {%- endif -%}
    {%- set project = target.project -%}
    {%- set location = target.location if target.location is defined and target.location else 'US' -%}

    {%- for dataset in source_datasets -%}
        {%- set ddl -%}
            CREATE SCHEMA IF NOT EXISTS `{{ project }}.{{ dataset }}`
            OPTIONS(location="{{ location }}")
        {%- endset -%}
        {% if execute %}
            {% do run_query(ddl) %}
        {% endif %}
    {%- endfor -%}
{%- endmacro %}
