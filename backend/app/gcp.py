"""
Google Cloud helpers: Secret Manager, the Cloud SQL private-IP lookup, and
"which identity am I running as?".

Everything here authenticates with Application Default Credentials. On the
VM that means the metadata server hands out short-lived tokens for the VM's
attached service account (gridpulse-vm-sa). There is no key file anywhere:
not in the image, not on the VM, not in git.

Also usable from the command line inside the backend image (the VM scripts
use these so they authenticate exactly the way the app does):

    python -m app.gcp whoami          # identity + how it was obtained
    python -m app.gcp db-host         # Cloud SQL private IP
    python -m app.gcp secret NAME     # prints a secret (for scripts; never echo it)
"""
from __future__ import annotations

import functools
import logging
import os
import sys

from app.config import settings

logger = logging.getLogger("gridpulse.gcp")

CLOUD_PLATFORM_SCOPE = "https://www.googleapis.com/auth/cloud-platform"


@functools.lru_cache(maxsize=1)
def _adc():
    import google.auth

    credentials, adc_project = google.auth.default(scopes=[CLOUD_PLATFORM_SCOPE])
    return credentials, adc_project


def project_id() -> str:
    project = settings.GCP_PROJECT or _adc()[1]
    if not project:
        raise RuntimeError("GCP project unknown: set GCP_PROJECT")
    return project


def access_secret(name: str, version: str = "latest") -> str:
    """Return a secret's value from Secret Manager (kept in memory only)."""
    from google.cloud import secretmanager

    client = secretmanager.SecretManagerServiceClient(credentials=_adc()[0])
    path = f"projects/{project_id()}/secrets/{name}/versions/{version}"
    try:
        response = client.access_secret_version(name=path)
    except Exception as exc:  # noqa: BLE001 - re-raise with a hint students can act on
        raise RuntimeError(
            f"Could not read secret '{name}' from Secret Manager ({exc.__class__.__name__}: {exc}). "
            "Check that the VM runs as gridpulse-vm-sa with the cloud-platform scope and that the "
            "service account has roles/secretmanager.secretAccessor on this secret."
        ) from exc
    return response.payload.data.decode("utf-8").strip()


def cloudsql_private_ip(instance: str) -> str:
    """Look up the PRIVATE IP of a Cloud SQL instance (needs roles/cloudsql.client)."""
    from google.auth.transport.requests import AuthorizedSession

    session = AuthorizedSession(_adc()[0])
    url = (
        "https://sqladmin.googleapis.com/v1/projects/"
        f"{project_id()}/instances/{instance}/connectSettings"
    )
    response = session.get(url, timeout=15)
    if response.status_code != 200:
        raise RuntimeError(
            f"Cloud SQL lookup for '{instance}' failed: HTTP {response.status_code} {response.text[:300]}"
        )
    for address in response.json().get("ipAddresses", []):
        if address.get("type") == "PRIVATE":
            return address["ipAddress"]
    raise RuntimeError(f"Cloud SQL instance '{instance}' has no private IP")


def whoami() -> dict:
    """Describe the identity this process uses - proof that no key file is involved."""
    from google.auth.transport.requests import Request

    credentials, _ = _adc()
    key_file = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
    try:
        credentials.refresh(Request())
    except Exception as exc:  # noqa: BLE001
        return {"identity": None, "source": f"unavailable ({exc.__class__.__name__})"}

    email = getattr(credentials, "service_account_email", None) or getattr(
        credentials, "signer_email", None
    )
    kind = f"{type(credentials).__module__}.{type(credentials).__name__}"
    if key_file:
        source = f"key file {key_file}"
    elif kind.startswith("google.auth.compute_engine"):
        source = "VM metadata server (attached service account, no key file)"
    else:
        source = kind
    return {
        "identity": email,
        "source": source,
        "scopes": list(getattr(credentials, "scopes", None) or []),
    }


def _main(argv: list[str]) -> int:
    if len(argv) < 2 or argv[1] not in {"whoami", "db-host", "secret"}:
        print(__doc__, file=sys.stderr)
        return 2
    command = argv[1]
    if command == "whoami":
        info = whoami()
        print(f"identity: {info['identity']}\nsource:   {info['source']}\nscopes:   {', '.join(info.get('scopes', []))}")
    elif command == "db-host":
        print(settings.DB_HOST or cloudsql_private_ip(settings.CLOUDSQL_INSTANCE))
    elif command == "secret":
        name = argv[2] if len(argv) > 2 else settings.DB_PASSWORD_SECRET
        sys.stdout.write(access_secret(name))
    return 0


if __name__ == "__main__":
    raise SystemExit(_main(sys.argv))
