#!/usr/bin/env python3
"""Export BigQuery tables/views to GCS as newline-delimited JSON (NDJSON)."""

from __future__ import annotations

import json
import os
import sys

from google.cloud import bigquery


def _project_id() -> str:
    return (os.environ.get("EXPORT_BQ_PROJECT_ID") or os.environ.get("BIGQUERY_PROJECT_ID") or "").strip()


def _table_map() -> dict[str, str]:
    raw = os.environ.get("EXPORT_TABLE_MAP", "").strip()
    if raw:
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError as e:
            raise SystemExit(f"EXPORT_TABLE_MAP no es JSON válido: {e}") from e
        if not isinstance(parsed, dict) or not parsed:
            raise SystemExit("EXPORT_TABLE_MAP debe ser un objeto JSON no vacío {blob_key: dataset.table}.")
        return {str(k): str(v) for k, v in parsed.items()}

    ref = os.environ.get("EXPORT_BQ_TABLE_REF", "").strip()
    if not ref:
        raise SystemExit(
            "Definí EXPORT_TABLE_MAP (JSON) o EXPORT_BQ_TABLE_REF (dataset.tabla o proyecto.dataset.tabla)."
        )
    blob = (os.environ.get("EXPORT_GCS_BLOB_NAME", "").strip() or ref.split(".")[-1]).replace(".json", "")
    return {blob: ref}


def _fully_qualified_table(ref: str) -> str:
    parts = ref.split(".")
    if len(parts) == 3:
        return ref
    if len(parts) == 2:
        proj = _project_id()
        if not proj:
            raise SystemExit("Con dataset.tabla hace falta BIGQUERY_PROJECT_ID o EXPORT_BQ_PROJECT_ID.")
        return f"{proj}.{parts[0]}.{parts[1]}"
    raise SystemExit(f"Referencia de tabla inválida (usa dataset.tabla o proyecto.dataset.tabla): {ref!r}")


def _gcs_prefix() -> str:
    # Vacío o ausente → default (GitHub Actions suele inyectar el secret aunque esté vacío).
    raw = (os.environ.get("EXPORT_GCS_PREFIX") or "").strip()
    p = (raw or "prod/exports").strip("/")
    return f"{p}/" if p else ""


def main() -> None:
    bucket = os.environ.get("EXPORT_GCS_BUCKET_NAME", "").strip()
    if not bucket:
        raise SystemExit("EXPORT_GCS_BUCKET_NAME es obligatorio.")

    creds = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", "").strip()
    if not creds or not os.path.isfile(creds):
        raise SystemExit("GOOGLE_APPLICATION_CREDENTIALS debe apuntar a un archivo JSON de cuenta de servicio.")

    project = _project_id()
    client = bigquery.Client(project=project) if project else bigquery.Client()

    prefix = _gcs_prefix()
    job_config = bigquery.ExtractJobConfig(
        destination_format=bigquery.DestinationFormat.NEWLINE_DELIMITED_JSON,
    )

    for blob_key, table_ref in _table_map().items():
        fq = _fully_qualified_table(table_ref)
        filename = blob_key if blob_key.endswith(".json") else f"{blob_key}.json"
        dest_uri = f"gs://{bucket}/{prefix}{filename}"

        extract_job = client.extract_table(fq, dest_uri, job_config=job_config)
        extract_job.result()

        print(f"OK {fq} -> {dest_uri}", file=sys.stderr)


if __name__ == "__main__":
    main()
