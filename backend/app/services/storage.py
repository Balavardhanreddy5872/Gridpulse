"""
Where uploaded infrastructure PDFs are kept.

Milestone 4: in the cloud the PDFs go to a Google Cloud Storage bucket, never
to the VM's disk. The storage client authenticates with Application Default
Credentials, which on the VM is the attached service account served by the
metadata server - there is no key file. The database row keeps only the
object's URI (gs://bucket/documents/...).

STORAGE_BACKEND=local keeps the old behaviour (a folder on disk) for laptop
development and the test suite.
"""
from __future__ import annotations

import functools
import os
import re
import uuid
from pathlib import Path

from app.config import settings


class StorageError(RuntimeError):
    pass


def object_name_for(region_id: int, original_filename: str) -> str:
    """documents/region-3/1f2e..._Substation_report.pdf (unique, URL-safe)."""
    base = os.path.basename(original_filename or "upload.pdf")
    safe = re.sub(r"[^A-Za-z0-9._-]+", "_", base).strip("._") or "upload.pdf"
    return f"region-{region_id}/{uuid.uuid4().hex}_{safe[:150]}"


class LocalStorage:
    kind = "local"

    def __init__(self, directory: str):
        self.directory = Path(directory)

    def describe(self) -> str:
        return f"local folder {self.directory.resolve()}"

    def save(self, name: str, data: bytes, content_type: str) -> str:
        path = self.directory / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return str(path)

    def read(self, uri: str) -> bytes:
        return Path(uri).read_bytes()


class GCSStorage:
    kind = "gcs"

    def __init__(self, bucket: str, prefix: str):
        if not bucket:
            raise StorageError("STORAGE_BACKEND=gcs needs GCS_BUCKET")
        self.bucket_name = bucket
        self.prefix = prefix.strip("/")

    def describe(self) -> str:
        return f"gs://{self.bucket_name}/{self.prefix}/"

    @functools.cached_property
    def _bucket(self):
        from google.cloud import storage

        from app import gcp

        # bucket() builds a reference without an API call, so the service
        # account only needs object permissions, not bucket-admin rights.
        return storage.Client(project=gcp.project_id()).bucket(self.bucket_name)

    def save(self, name: str, data: bytes, content_type: str) -> str:
        object_name = f"{self.prefix}/{name}" if self.prefix else name
        blob = self._bucket.blob(object_name)
        try:
            # if_generation_match=0: create only, never overwrite an existing object
            blob.upload_from_string(data, content_type=content_type, if_generation_match=0)
        except Exception as exc:  # noqa: BLE001
            raise StorageError(
                f"Upload to gs://{self.bucket_name}/{object_name} failed "
                f"({exc.__class__.__name__}: {exc})"
            ) from exc
        return f"gs://{self.bucket_name}/{object_name}"

    def read(self, uri: str) -> bytes:
        bucket, _, object_name = uri.removeprefix("gs://").partition("/")
        if bucket != self.bucket_name:
            raise StorageError(f"{uri} is not in bucket {self.bucket_name}")
        return self._bucket.blob(object_name).download_as_bytes()


@functools.lru_cache(maxsize=1)
def get_storage() -> LocalStorage | GCSStorage:
    if settings.STORAGE_BACKEND == "gcs":
        return GCSStorage(settings.GCS_BUCKET, settings.GCS_PREFIX)
    return LocalStorage(settings.UPLOAD_DIRECTORY)
