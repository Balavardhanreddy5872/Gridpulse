"""Milestone 4: the cloud DB URL is built from Secret Manager + the Cloud SQL
private IP, and the password never appears when the URL is printed."""
from app import database, gcp
from app.config import settings


def test_cloud_url_uses_secret_and_private_ip(monkeypatch):
    monkeypatch.setattr(settings, "DATABASE_URL", None)
    monkeypatch.setattr(settings, "DB_PASSWORD_SECRET", "gridpulse-db-password")
    monkeypatch.setattr(settings, "CLOUDSQL_INSTANCE", "gridpulse-db")
    monkeypatch.setattr(settings, "DB_HOST", None)
    calls = {}

    def fake_secret(name, version="latest"):
        calls["secret"] = name
        return "s3cretValue123"

    def fake_ip(instance):
        calls["instance"] = instance
        return "10.60.0.3"

    monkeypatch.setattr(gcp, "access_secret", fake_secret)
    monkeypatch.setattr(gcp, "cloudsql_private_ip", fake_ip)

    url = database.build_database_url()
    assert calls == {"secret": "gridpulse-db-password", "instance": "gridpulse-db"}
    assert url.host == "10.60.0.3"
    assert url.password == "s3cretValue123"
    assert url.query["sslmode"] == "require"
    assert "s3cretValue123" not in str(url)
    assert "s3cretValue123" not in url.render_as_string(hide_password=True)


def test_explicit_db_host_skips_lookup(monkeypatch):
    monkeypatch.setattr(settings, "DATABASE_URL", None)
    monkeypatch.setattr(settings, "DB_PASSWORD_SECRET", "gridpulse-db-password")
    monkeypatch.setattr(settings, "DB_HOST", "10.60.0.9")
    monkeypatch.setattr(gcp, "access_secret", lambda name, version="latest": "pw")

    def no_lookup(instance):
        raise AssertionError("must not look up the IP when DB_HOST is set")

    monkeypatch.setattr(gcp, "cloudsql_private_ip", no_lookup)
    assert database.build_database_url().host == "10.60.0.9"


def test_settings_never_read_a_dotenv_file():
    assert settings.model_config.get("env_file") is None
