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

    {# Dev (p. ej. PR CI): generate_schema_name usa SANDBOX_<DBT_USER> sin --defer, y `stg` con --defer + +schema:stg. BigQuery exige que el dataset exista. #}
    {%- if target.name == 'dev' -%}
        {%- set raw_user = env_var('DBT_USER', 'default_user') -%}
        {%- set user = raw_user.split('@')[0] | replace('.', '_') | replace('-', '_') -%}
        {%- set sandbox_ds = 'SANDBOX_' ~ (user | upper) -%}
        {%- if execute -%}
            {%- set ddl_sb -%}
                CREATE SCHEMA IF NOT EXISTS `{{ project }}.{{ sandbox_ds }}`
                OPTIONS(location="{{ location }}")
            {%- endset -%}
            {% do run_query(ddl_sb) %}
            {%- set ddl_stg -%}
                CREATE SCHEMA IF NOT EXISTS `{{ project }}.stg`
                OPTIONS(location="{{ location }}")
            {%- endset -%}
            {% do run_query(ddl_stg) %}
        {%- endif -%}
    {%- endif -%}
{%- endmacro %}
