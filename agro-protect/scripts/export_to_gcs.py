#!/usr/bin/env python3
"""Export BigQuery tables/views to GCS as NDJSON; optional auto-discovery by dataset + signed export manifest."""

from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from google.api_core import exceptions as gcp_exceptions
from google.cloud import bigquery, storage
from google.oauth2 import service_account

_DEFAULT_GCP_PROJECT = "agro-protect-490822"
# Fallback si no hay metadata ni env; este proyecto usa BQ en southamerica-east1.
_DEFAULT_BIGQUERY_LOCATION = "southamerica-east1"
_DEFAULT_GCS_BUCKET = "agroprotect-exports-prod"
_BQ_SCOPES = ("https://www.googleapis.com/auth/cloud-platform",)
# BigQuery extract no aplica a tablas externas vinculadas.
_EXTRACTABLE_TYPES = frozenset({"TABLE", "VIEW", "MATERIALIZED_VIEW", "SNAPSHOT"})


def _project_id_from_credentials() -> str:
    path = (os.environ.get("GOOGLE_APPLICATION_CREDENTIALS") or "").strip()
    if not path or not os.path.isfile(path):
        return ""
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return (data.get("project_id") or "").strip()
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, TypeError):
        return ""


def _project_id() -> str:
    for key in ("EXPORT_BQ_PROJECT_ID", "BIGQUERY_PROJECT_ID"):
        v = (os.environ.get(key) or "").strip()
        if v:
            return v
    cred_proj = _project_id_from_credentials()
    if cred_proj:
        return cred_proj
    return _DEFAULT_GCP_PROJECT


def _explicit_sources_configured() -> bool:
    mode = (os.environ.get("EXPORT_MODE") or "").strip().lower()
    if mode == "auto":
        return False
    if mode in ("map", "explicit"):
        return True
    if (os.environ.get("EXPORT_TABLE_MAP") or "").strip():
        return True
    if (os.environ.get("EXPORT_BQ_TABLE_REF") or "").strip():
        return True
    return False


def _table_map_explicit() -> dict[str, str]:
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
            "EXPORT_MODE=explicit/map requires EXPORT_TABLE_MAP or EXPORT_BQ_TABLE_REF, "
            "or omit both to use auto export by dataset."
        )
    blob = (os.environ.get("EXPORT_GCS_BLOB_NAME", "").strip() or ref.split(".")[-1]).replace(".json", "")
    return {blob: ref}


def _datasets_for_auto_export() -> list[str]:
    raw = (os.environ.get("EXPORT_BQ_DATASETS") or "").strip()
    if raw:
        return list(dict.fromkeys(x.strip() for x in raw.split(",") if x.strip()))
    analytics = (os.environ.get("BIGQUERY_DATASET_ID") or "analytics").strip() or "analytics"
    # Orden: staging, dataset “principal” de dbt prod, marts (cuando existan).
    return list(dict.fromkeys(["stg", analytics, "marts"]))


def _fully_qualified_table(ref: str, project: str) -> str:
    parts = ref.split(".")
    if len(parts) == 3:
        p, d, t = (x.strip() for x in parts)
        if not p or not d or not t:
            raise SystemExit(
                f"Referencia inválida (cada parte de project.dataset.table debe ser no vacía): {ref!r}"
            )
        return f"{p}.{d}.{t}"
    if len(parts) == 2:
        if not project:
            raise SystemExit("For dataset.table you need BIGQUERY_PROJECT_ID or EXPORT_BQ_PROJECT_ID.")
        d, t = (x.strip() for x in parts)
        if not d or not t:
            raise SystemExit(f"Referencia inválida dataset.table: {ref!r}")
        return f"{project}.{d}.{t}"
    raise SystemExit(f"Invalid table reference (use dataset.table or project.dataset.table): {ref!r}")


def _table_ref_from_fq(fq: str) -> bigquery.TableReference:
    parts = fq.split(".")
    if len(parts) != 3:
        raise SystemExit(f"FQ interno inválido: {fq!r}")
    project_id, dataset_id, table_id = (p.strip() for p in parts)
    if not project_id or not dataset_id or not table_id:
        raise SystemExit(f"FQ con segmento vacío: {fq!r}")
    dr = bigquery.DatasetReference(project_id, dataset_id)
    return bigquery.TableReference(dr, table_id)


def _table_type_for_ref(client: bigquery.Client, bq_ref: bigquery.TableReference) -> str:
    """Tipo TABLE/VIEW/… sin asumir que tables.get funciona (mensajes claros si el proyecto ref está mal)."""
    fq = f"{bq_ref.project}.{bq_ref.dataset_id}.{bq_ref.table_id}"
    ds_ref = bigquery.DatasetReference(bq_ref.project, bq_ref.dataset_id)
    try:
        for item in client.list_tables(ds_ref):
            if item.table_id == bq_ref.table_id:
                return (getattr(item, "table_type", None) or "TABLE").strip()
    except gcp_exceptions.NotFound as e:
        ds = bq_ref.dataset_id
        hint_ds = ""
        if ds.lower() == "analytics":
            hint_ds = (
                "En este repo las vistas dbt en prod suelen estar en el dataset **stg**, no `analytics`. "
                "Cambiá el mapa a `stg.{tbl}` o borrá el secret EXPORT_TABLE_MAP para modo auto. "
            ).format(tbl=bq_ref.table_id)
        raise SystemExit(
            f"BigQuery: no existe el dataset `{ds}` en el proyecto `{bq_ref.project}` (tabla `{bq_ref.table_id}`). {hint_ds}"
            "Revisá EXPORT_TABLE_MAP: valor `dataset.tabla` debe coincidir con BigQuery. "
            "Revisá también BIGQUERY_PROJECT_ID y permisos de la SA de export. "
            "Modo auto (recomendado): quitá EXPORT_TABLE_MAP y EXPORT_BQ_TABLE_REF de los secrets. "
            f"Detalle API: {e}"
        ) from e
    except gcp_exceptions.GoogleAPICallError as e:
        raise SystemExit(
            f"No se pudo listar tablas de {bq_ref.project}.{bq_ref.dataset_id}: {e}. "
            "Revisá IAM de la SA de export (BigQuery Data Viewer / metadata) en ese proyecto."
        ) from e
    try:
        meta = client.get_table(bq_ref)
        return (meta.table_type or "TABLE").strip()
    except gcp_exceptions.NotFound as e:
        raise SystemExit(
            f"Tabla no encontrada: {fq}. Ajustá EXPORT_TABLE_MAP (en prod suele ser stg.stg_agro_*). "
            f"Detalle: {e}"
        ) from e


def _resolve_extract_location(client: bigquery.Client, ref: bigquery.TableReference) -> str:
    """Región del job: primero metadata BQ (dataset/tabla); BIGQUERY_LOCATION solo si no hay metadata."""
    try:
        ds_ref = bigquery.DatasetReference(ref.project, ref.dataset_id)
        ds = client.get_dataset(ds_ref)
        if ds.location:
            return str(ds.location)
    except gcp_exceptions.GoogleAPICallError:
        pass
    try:
        table = client.get_table(ref)
        loc = getattr(table, "location", None) or (getattr(table, "_properties", None) or {}).get(
            "location"
        )
        if loc:
            return str(loc)
    except gcp_exceptions.GoogleAPICallError:
        pass
    for key in ("EXPORT_BIGQUERY_LOCATION", "BIGQUERY_LOCATION"):
        v = (os.environ.get(key) or "").strip()
        if v:
            return v
    return _DEFAULT_BIGQUERY_LOCATION


def _gcs_prefix() -> str:
    raw = (os.environ.get("EXPORT_GCS_PREFIX") or "").strip()
    if raw.lower().startswith("gs://"):
        raw = raw[5:].lstrip("/")
    p = (raw or "prod/exports").strip("/")
    return f"{p}/" if p else ""


def _normalize_bucket(raw: str) -> str:
    b = (raw or "").strip()
    if not b:
        b = _DEFAULT_GCS_BUCKET
    if b.lower().startswith("gs://"):
        b = b[5:].lstrip("/")
    b = b.split("/")[0].strip()
    if not b:
        raise SystemExit(
            "EXPORT_GCS_BUCKET_NAME must be only the bucket id (e.g. my-exports-bucket), "
            "not a full gs:// URI or path."
        )
    return b.lower()


def _signed_url_ttl() -> int:
    raw = (os.environ.get("EXPORT_SIGNED_URL_TTL_SEC") or "43200").strip()
    try:
        n = int(raw)
    except ValueError:
        return 43200
    return max(60, min(n, 604800))


def _run_extract(
    client: bigquery.Client,
    bq_ref: bigquery.TableReference,
    dest_uri: str,
    project: str,
    loc: str,
    job_config: bigquery.ExtractJobConfig,
) -> None:
    extract_job = client.extract_table(
        bq_ref,
        dest_uri,
        job_config=job_config,
        project=project,
        location=loc,
    )
    try:
        extract_job.result()
    except gcp_exceptions.GoogleAPICallError as e:
        detail = getattr(extract_job, "errors", None)
        extra = f" job_errors={detail}" if detail else ""
        raise SystemExit(f"Export falló ({bq_ref} → {dest_uri}): {e}.{extra}") from e


def _run_export_view_query(
    client: bigquery.Client,
    project: str,
    dataset_id: str,
    table_id: str,
    dest_gs_uri: str,
    location: str,
) -> None:
    """BigQuery no permite extract_table sobre VIEW; EXPORT DATA + SELECT sí."""
    from_ref = f"`{project}.{dataset_id}.{table_id}`"
    uri_lit = dest_gs_uri.replace("\\", "\\\\").replace("'", "\\'")
    sql = (
        f"EXPORT DATA OPTIONS(\n"
        f"  uri='{uri_lit}',\n"
        f"  format='JSON',\n"
        f"  overwrite=true\n"
        f") AS\n"
        f"SELECT * FROM {from_ref}"
    )
    job = client.query(sql, location=location)
    try:
        job.result()
    except gcp_exceptions.GoogleAPICallError as e:
        detail = getattr(job, "errors", None)
        extra = f" job_errors={detail}" if detail else ""
        fq = f"{project}.{dataset_id}.{table_id}"
        raise SystemExit(f"Export falló (vista {fq} → {dest_gs_uri}): {e}.{extra}") from e


def _export_relation_ndjson(
    client: bigquery.Client,
    table_type: str,
    bq_ref: bigquery.TableReference,
    dest_uri: str,
    project: str,
    loc: str,
    job_config: bigquery.ExtractJobConfig,
) -> None:
    if table_type == "VIEW":
        _run_export_view_query(
            client,
            bq_ref.project,
            bq_ref.dataset_id,
            bq_ref.table_id,
            dest_uri,
            loc,
        )
    else:
        _run_extract(client, bq_ref, dest_uri, project, loc, job_config)


def _blobs_for_prefix(
    storage_client: storage.Client, bucket_name: str, gcs_prefix: str, table_key: str
) -> list[str]:
    """Lista objetos recién extraídos (patrón table_key_*.json bajo prefix)."""
    bucket = storage_client.bucket(bucket_name)
    prefix = f"{gcs_prefix}{table_key}_"
    names: list[str] = []
    for b in storage_client.list_blobs(bucket_name, prefix=prefix):
        if b.name.endswith(".json"):
            names.append(f"gs://{bucket_name}/{b.name}")
    names.sort()
    return names


def _sign_blobs(
    storage_client: storage.Client,
    bucket_name: str,
    gcs_uris: list[str],
    credentials: service_account.Credentials,
    ttl_sec: int,
) -> list[str]:
    out: list[str] = []
    bucket = storage_client.bucket(bucket_name)
    for uri in gcs_uris:
        if not uri.startswith("gs://"):
            continue
        path = uri.split("/", 3)[3]
        blob = bucket.blob(path)
        out.append(
            blob.generate_signed_url(
                version="v4",
                expiration=timedelta(seconds=ttl_sec),
                method="GET",
                credentials=credentials,
            )
        )
    return out


def _maybe_upload_file_to_gcs(
    storage_client: storage.Client,
    bucket_name: str,
    gcs_prefix: str,
    local_path: Path,
    dest_name: str,
) -> str | None:
    if not local_path.is_file():
        return None
    rel = f"{gcs_prefix}{dest_name}".replace("//", "/")
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(rel)
    blob.upload_from_filename(str(local_path), content_type="application/json")
    return f"gs://{bucket_name}/{rel}"


def export_auto(
    client: bigquery.Client,
    storage_client: storage.Client,
    bucket: str,
    prefix: str,
    project: str,
    job_config: bigquery.ExtractJobConfig,
    credentials: service_account.Credentials,
) -> tuple[list[dict[str, Any]], dict[str, Any] | None]:
    ttl = _signed_url_ttl()
    records: list[dict[str, Any]] = []
    dbt_extra: dict[str, Any] | None = None

    for ds_id in _datasets_for_auto_export():
        ds_ref = bigquery.DatasetReference(project, ds_id)
        try:
            ds_full = client.get_dataset(ds_ref)
        except gcp_exceptions.GoogleAPICallError:
            print(f"skip dataset (missing or no access): {project}.{ds_id}", file=sys.stderr)
            continue

        # La región del job debe coincidir con la del dataset; BIGQUERY_LOCATION=US con stg en
        # southamerica-east1 provoca "Dataset not found in location US".
        ds_location = (getattr(ds_full, "location", None) or "").strip() or None

        for item in client.list_tables(ds_ref):
            ttype = (getattr(item, "table_type", None) or "TABLE").strip()
            if ttype not in _EXTRACTABLE_TYPES:
                print(f"skip {ds_id}.{item.table_id} (type={ttype})", file=sys.stderr)
                continue

            fq = f"{project}.{ds_id}.{item.table_id}"
            bq_ref = _table_ref_from_fq(fq)
            loc = ds_location or _resolve_extract_location(client, bq_ref)
            table_key = f"{ds_id}/{item.table_id}"
            dest_uri = f"gs://{bucket}/{prefix}{table_key}_*.json"

            _export_relation_ndjson(client, ttype, bq_ref, dest_uri, project, loc, job_config)
            gcs_objects = _blobs_for_prefix(storage_client, bucket, prefix, table_key)
            signed = _sign_blobs(storage_client, bucket, gcs_objects, credentials, ttl)

            rec: dict[str, Any] = {
                "dataset": ds_id,
                "table": item.table_id,
                "table_type": ttype,
                "export_method": "export_data_sql" if ttype == "VIEW" else "extract_table",
                "fully_qualified": fq,
                "bq_job_location": loc,
                "gcs_objects": gcs_objects,
                "signed_urls": signed,
                "signed_url_expires_in_seconds": ttl,
            }
            records.append(rec)
            print(f"OK {fq} -> {dest_uri}", file=sys.stderr)

    manifest_path = (os.environ.get("DBT_MANIFEST_PATH") or "").strip()
    if manifest_path:
        p = Path(manifest_path)
        uploaded = _maybe_upload_file_to_gcs(
            storage_client, bucket, prefix, p, "dbt/manifest.json"
        )
        if uploaded:
            b = storage_client.bucket(bucket)
            blob_path = uploaded.split("/", 3)[3]
            su = b.blob(blob_path).generate_signed_url(
                version="v4",
                expiration=timedelta(seconds=ttl),
                method="GET",
                credentials=credentials,
            )
            dbt_extra = {"gcs_uri": uploaded, "signed_url": su, "signed_url_expires_in_seconds": ttl}
            print(f"OK dbt manifest -> {uploaded}", file=sys.stderr)

    return records, dbt_extra


def export_explicit(
    client: bigquery.Client,
    storage_client: storage.Client,
    bucket: str,
    prefix: str,
    project: str,
    job_config: bigquery.ExtractJobConfig,
    credentials: service_account.Credentials,
) -> list[dict[str, Any]]:
    ttl = _signed_url_ttl()
    records: list[dict[str, Any]] = []
    for blob_key, src_table_ref in _table_map_explicit().items():
        fq = _fully_qualified_table(src_table_ref, project)
        base = blob_key[:-5] if blob_key.endswith(".json") else blob_key
        dest_uri = f"gs://{bucket}/{prefix}{base}_*.json"

        bq_ref = _table_ref_from_fq(fq)
        ds_ref = bigquery.DatasetReference(bq_ref.project, bq_ref.dataset_id)
        try:
            ds_meta = client.get_dataset(ds_ref)
            ds_location = (getattr(ds_meta, "location", None) or "").strip() or None
        except gcp_exceptions.GoogleAPICallError:
            ds_location = None
        loc = ds_location or _resolve_extract_location(client, bq_ref)
        ttype = _table_type_for_ref(client, bq_ref)

        _export_relation_ndjson(client, ttype, bq_ref, dest_uri, project, loc, job_config)
        gcs_objects = _blobs_for_prefix(storage_client, bucket, prefix, base)
        signed = _sign_blobs(storage_client, bucket, gcs_objects, credentials, ttl)

        records.append(
            {
                "dataset": bq_ref.dataset_id,
                "table": bq_ref.table_id,
                "table_type": ttype,
                "export_method": "export_data_sql" if ttype == "VIEW" else "extract_table",
                "fully_qualified": fq,
                "bq_job_location": loc,
                "gcs_objects": gcs_objects,
                "signed_urls": signed,
                "signed_url_expires_in_seconds": ttl,
            }
        )
        print(f"OK {fq} -> {dest_uri}", file=sys.stderr)
    return records


def main() -> None:
    bucket = _normalize_bucket(os.environ.get("EXPORT_GCS_BUCKET_NAME", ""))

    creds_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", "").strip()
    if not creds_path or not os.path.isfile(creds_path):
        raise SystemExit("GOOGLE_APPLICATION_CREDENTIALS must point to a service account JSON file.")

    try:
        raw = open(creds_path, encoding="utf-8").read().strip()
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

    project = _project_id().strip()
    if not project:
        raise SystemExit(
            "No se pudo determinar el proyecto GCP para BigQuery. "
            "Definí BIGQUERY_PROJECT_ID o EXPORT_BQ_PROJECT_ID (sin espacios), o usá una key JSON con project_id."
        )
    for env_key in (
        "GOOGLE_CLOUD_PROJECT",
        "GCLOUD_PROJECT",
        "GOOGLE_CLOUD_QUOTA_PROJECT",
        "CLOUDSDK_CORE_PROJECT",
    ):
        if not (os.environ.get(env_key) or "").strip():
            os.environ.pop(env_key, None)
    os.environ["GOOGLE_CLOUD_PROJECT"] = project
    os.environ["GOOGLE_CLOUD_QUOTA_PROJECT"] = project

    credentials = service_account.Credentials.from_service_account_file(
        creds_path,
        scopes=_BQ_SCOPES,
    )
    client = bigquery.Client(project=project, credentials=credentials)
    storage_client = storage.Client(project=project, credentials=credentials)

    prefix = _gcs_prefix()
    job_config = bigquery.ExtractJobConfig(
        destination_format=bigquery.DestinationFormat.NEWLINE_DELIMITED_JSON,
    )

    explicit = _explicit_sources_configured()
    if explicit:
        records = export_explicit(
            client, storage_client, bucket, prefix, project, job_config, credentials
        )
        dbt_extra = None
        manifest_path = (os.environ.get("DBT_MANIFEST_PATH") or "").strip()
        if manifest_path:
            p = Path(manifest_path)
            ttl = _signed_url_ttl()
            uploaded = _maybe_upload_file_to_gcs(
                storage_client, bucket, prefix, p, "dbt/manifest.json"
            )
            if uploaded:
                bkt = storage_client.bucket(bucket)
                blob_path = uploaded.split("/", 3)[3]
                su = bkt.blob(blob_path).generate_signed_url(
                    version="v4",
                    expiration=timedelta(seconds=ttl),
                    method="GET",
                    credentials=credentials,
                )
                dbt_extra = {
                    "gcs_uri": uploaded,
                    "signed_url": su,
                    "signed_url_expires_in_seconds": ttl,
                }
                print(f"OK dbt manifest -> {uploaded}", file=sys.stderr)
    else:
        records, dbt_extra = export_auto(
            client, storage_client, bucket, prefix, project, job_config, credentials
        )

    manifest_doc: dict[str, Any] = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "project": project,
        "gcs_bucket": bucket,
        "gcs_prefix": prefix,
        "mode": "explicit" if explicit else "auto",
        "exports": records,
        "dbt_manifest": dbt_extra,
    }

    manifest_name = (os.environ.get("EXPORT_MANIFEST_OBJECT") or "export_manifest.json").strip()
    if "/" in manifest_name or manifest_name.startswith(".."):
        raise SystemExit("EXPORT_MANIFEST_OBJECT must be a single file name (no path).")
    manifest_blob_path = f"{prefix}{manifest_name}".replace("//", "/")
    mb = storage_client.bucket(bucket).blob(manifest_blob_path)
    mb.upload_from_string(
        json.dumps(manifest_doc, indent=2),
        content_type="application/json",
    )
    manifest_gs = f"gs://{bucket}/{manifest_blob_path}"
    manifest_signed = mb.generate_signed_url(
        version="v4",
        expiration=timedelta(seconds=_signed_url_ttl()),
        method="GET",
        credentials=credentials,
    )
    print(f"OK export manifest -> {manifest_gs}", file=sys.stderr)
    print(f"MANIFEST_SIGNED_URL={manifest_signed}", file=sys.stderr)


if __name__ == "__main__":
    main()

