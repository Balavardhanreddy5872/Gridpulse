"""Initial GridPulse schema: the 7 tables, their keys and indexes.

Revision ID: 0001_initial_schema
Revises: (none - first migration)
Create Date: 2026-10-14

Milestone 4: this migration, not the application, creates the tables.
It reproduces exactly the schema the Milestone 1-3 app built implicitly with
SQLAlchemy's create_all(), so the data dumped from the Milestone 3 Postgres
container loads into Cloud SQL unchanged (same columns, types, nullability,
constraint names and SERIAL sequences).

    alembic upgrade head      # create everything (run on Cloud SQL by the VM)
    alembic downgrade base    # drop everything again
    alembic upgrade head --sql  # print the SQL without touching a database

Future schema changes go in NEW files (0002_..., 0003_...), never by editing
this one after it has run.
"""
from alembic import op

revision = "0001_initial_schema"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1. regions - every other table points at a region
    op.execute(
        """
        CREATE TABLE regions (
            id          SERIAL                   NOT NULL,
            name        VARCHAR(100)             NOT NULL,
            state       VARCHAR(50)              NOT NULL,
            capacity_mw DOUBLE PRECISION         NOT NULL,
            created_at  TIMESTAMP WITH TIME ZONE NOT NULL,
            CONSTRAINT regions_pkey     PRIMARY KEY (id),
            CONSTRAINT regions_name_key UNIQUE (name)
        )
        """
    )

    # 2. hourly_readings - historical load per region per hour
    op.execute(
        """
        CREATE TABLE hourly_readings (
            id        SERIAL                   NOT NULL,
            region_id INTEGER                  NOT NULL,
            timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
            load_mw   DOUBLE PRECISION         NOT NULL,
            CONSTRAINT hourly_readings_pkey PRIMARY KEY (id),
            CONSTRAINT hourly_readings_region_id_fkey
                FOREIGN KEY (region_id) REFERENCES regions (id)
        )
        """
    )
    op.execute(
        "CREATE INDEX ix_hourly_readings_region_timestamp "
        "ON hourly_readings (region_id, timestamp)"
    )

    # 3. weather_observations - weather features used by the forecaster
    op.execute(
        """
        CREATE TABLE weather_observations (
            id                SERIAL                   NOT NULL,
            region_id         INTEGER                  NOT NULL,
            timestamp         TIMESTAMP WITH TIME ZONE NOT NULL,
            temperature       DOUBLE PRECISION         NOT NULL,
            humidity          DOUBLE PRECISION         NOT NULL,
            wind_speed        DOUBLE PRECISION         NOT NULL,
            weather_condition VARCHAR(50)              NOT NULL,
            CONSTRAINT weather_observations_pkey PRIMARY KEY (id),
            CONSTRAINT weather_observations_region_id_fkey
                FOREIGN KEY (region_id) REFERENCES regions (id)
        )
        """
    )
    op.execute(
        "CREATE INDEX ix_weather_observations_region_timestamp "
        "ON weather_observations (region_id, timestamp)"
    )

    # 4. forecast_results - latest 24h forecast per region
    op.execute(
        """
        CREATE TABLE forecast_results (
            id                    SERIAL                   NOT NULL,
            region_id             INTEGER                  NOT NULL,
            forecast_timestamp    TIMESTAMP WITH TIME ZONE NOT NULL,
            predicted_load_mw     DOUBLE PRECISION         NOT NULL,
            effective_capacity_mw DOUBLE PRECISION         NOT NULL,
            risk_level            VARCHAR(20)              NOT NULL,
            model_version         VARCHAR(50)              NOT NULL,
            created_at            TIMESTAMP WITH TIME ZONE NOT NULL,
            CONSTRAINT forecast_results_pkey PRIMARY KEY (id),
            CONSTRAINT forecast_results_region_id_fkey
                FOREIGN KEY (region_id) REFERENCES regions (id)
        )
        """
    )
    op.execute(
        "CREATE INDEX ix_forecast_results_region_ts "
        "ON forecast_results (region_id, forecast_timestamp)"
    )

    # 5. peak_alerts - raised when a forecast crosses a risk threshold
    op.execute(
        """
        CREATE TABLE peak_alerts (
            id                 SERIAL                   NOT NULL,
            region_id          INTEGER                  NOT NULL,
            forecast_result_id INTEGER                  NOT NULL,
            risk_level         VARCHAR(20)              NOT NULL,
            predicted_load_mw  DOUBLE PRECISION         NOT NULL,
            capacity_mw        DOUBLE PRECISION         NOT NULL,
            message            VARCHAR(300)             NOT NULL,
            status             VARCHAR(20)              NOT NULL,
            created_at         TIMESTAMP WITH TIME ZONE NOT NULL,
            CONSTRAINT peak_alerts_pkey PRIMARY KEY (id),
            CONSTRAINT peak_alerts_region_id_fkey
                FOREIGN KEY (region_id) REFERENCES regions (id),
            CONSTRAINT peak_alerts_forecast_result_id_fkey
                FOREIGN KEY (forecast_result_id) REFERENCES forecast_results (id)
        )
        """
    )

    # 6. infrastructure_documents - uploaded PDF metadata. `filepath` holds
    #    the object's gs:// URI in the cloud bucket (the PDF itself is NOT
    #    stored in the database).
    op.execute(
        """
        CREATE TABLE infrastructure_documents (
            id                 SERIAL                   NOT NULL,
            region_id          INTEGER                  NOT NULL,
            filename           VARCHAR(255)             NOT NULL,
            filepath           VARCHAR(500)             NOT NULL,
            extracted_text     TEXT,
            capacity_impact_mw DOUBLE PRECISION,
            start_date         TIMESTAMP WITH TIME ZONE,
            end_date           TIMESTAMP WITH TIME ZONE,
            description        VARCHAR(500),
            uploaded_at        TIMESTAMP WITH TIME ZONE NOT NULL,
            CONSTRAINT infrastructure_documents_pkey PRIMARY KEY (id),
            CONSTRAINT infrastructure_documents_region_id_fkey
                FOREIGN KEY (region_id) REFERENCES regions (id)
        )
        """
    )

    # 7. async_jobs - the background worker's queue (queued -> processing ->
    #    completed/failed). Lives in the database, so it survives the VM.
    op.execute(
        """
        CREATE TABLE async_jobs (
            id            SERIAL                   NOT NULL,
            job_type      VARCHAR(50)              NOT NULL,
            region_id     INTEGER,
            status        VARCHAR(20)              NOT NULL,
            created_at    TIMESTAMP WITH TIME ZONE NOT NULL,
            started_at    TIMESTAMP WITH TIME ZONE,
            completed_at  TIMESTAMP WITH TIME ZONE,
            error_message VARCHAR(500),
            CONSTRAINT async_jobs_pkey PRIMARY KEY (id),
            CONSTRAINT async_jobs_region_id_fkey
                FOREIGN KEY (region_id) REFERENCES regions (id)
        )
        """
    )


def downgrade() -> None:
    # Reverse dependency order: children before the tables they reference.
    for table in (
        "async_jobs",
        "infrastructure_documents",
        "peak_alerts",
        "forecast_results",
        "weather_observations",
        "hourly_readings",
        "regions",
    ):
        op.execute(f"DROP TABLE {table}")
