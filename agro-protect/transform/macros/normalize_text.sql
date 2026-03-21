{% macro normalize_text(column_name) -%}
    REGEXP_REPLACE(
        TRANSLATE(
            UPPER(TRIM(CAST({{ column_name }} AS STRING))),
            'ÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇ',
            'AAAAAEEEEIIIIOOOOOUUUUNC'
        ),
        r'\s+',
        ' '
    )
{%- endmacro %}
