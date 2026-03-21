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
            raise SystemExit(f"EXPORT_TABLE_MAP is not valid JSON: {e}") from e
        if not isinstance(parsed, dict) or not parsed:
            raise SystemExit("EXPORT_TABLE_MAP must be a non-empty JSON object {blob_key: dataset.table}.")
        return {str(k): str(v) for k, v in parsed.items()}

    ref = os.environ.get("EXPORT_BQ_TABLE_REF", "").strip()
    if not ref:
        raise SystemExit(
            "Set EXPORT_TABLE_MAP (JSON) or EXPORT_BQ_TABLE_REF (dataset.table or project.dataset.table)."
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
            raise SystemExit("For dataset.table you need BIGQUERY_PROJECT_ID or EXPORT_BQ_PROJECT_ID.")
        return f"{proj}.{parts[0]}.{parts[1]}"
    raise SystemExit(f"Invalid table reference (use dataset.table or project.dataset.table): {ref!r}")


def _gcs_prefix() -> str:
    # Empty or missing → default (GitHub Actions may inject the secret even when empty).
    raw = (os.environ.get("EXPORT_GCS_PREFIX") or "").strip()
    if raw.lower().startswith("gs://"):
        raw = raw[5:].lstrip("/")
    p = (raw or "prod/exports").strip("/")
    return f"{p}/" if p else ""


def _normalize_bucket(raw: str) -> str:
    """Bucket name only — BigQuery rejects URIs like gs://gs://bucket/... if the secret includes gs://."""
    b = (raw or "").strip()
    if not b:
        raise SystemExit("EXPORT_GCS_BUCKET_NAME is required.")
    if b.lower().startswith("gs://"):
        b = b[5:].lstrip("/")
    b = b.split("/")[0].strip()
    if not b:
        raise SystemExit(
            "EXPORT_GCS_BUCKET_NAME must be only the bucket id (e.g. my-exports-bucket), "
            "not a full gs:// URI or path."
        )
    return b.lower()


def main() -> None:
    bucket = _normalize_bucket(os.environ.get("EXPORT_GCS_BUCKET_NAME", ""))

    creds = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", "").strip()
    if not creds or not os.path.isfile(creds):
        raise SystemExit("GOOGLE_APPLICATION_CREDENTIALS must point to a service account JSON file.")

    try:
        raw = open(creds, encoding="utf-8").read().strip()
        if not raw:
            raise ValueError("empty file")
        json.loads(raw)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, ValueError) as e:
        raise SystemExit(
            "GOOGLE_APPLICATION_CREDENTIALS file must contain valid service account JSON. "
            "In GitHub Actions, set EXPORT_GOOGLE_APPLICATION_CREDENTIALS to base64(single line): "
            "base64 -i key.json | tr -d '\\n'. "
            f"({e})"
        ) from e

    project = _project_id()
    client = bigquery.Client(project=project) if project else bigquery.Client()

    prefix = _gcs_prefix()
    job_config = bigquery.ExtractJobConfig(
        destination_format=bigquery.DestinationFormat.NEWLINE_DELIMITED_JSON,
    )

    for blob_key, table_ref in _table_map().items():
        fq = _fully_qualified_table(table_ref)
        # BigQuery expects a GCS *pattern* for extract; a bare single filename often 400s.
        # Output shards: {base}_000000000000.json (one shard for small tables).
        base = blob_key[:-5] if blob_key.endswith(".json") else blob_key
        dest_uri = f"gs://{bucket}/{prefix}{base}_*.json"

        extract_job = client.extract_table(fq, dest_uri, job_config=job_config)
        extract_job.result()

        print(f"OK {fq} -> {dest_uri}", file=sys.stderr)


if __name__ == "__main__":
    main()
