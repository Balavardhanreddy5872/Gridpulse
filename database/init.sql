-- GridPulse relational schema (matches backend/app/models exactly).
-- This is provided for reference/manual setup; the FastAPI app also
-- creates these tables automatically on startup via SQLAlchemy metadata.

CREATE TABLE IF NOT EXISTS regions (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    state VARCHAR(50) NOT NULL,
    capacity_mw FLOAT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS hourly_readings (
    id SERIAL PRIMARY KEY,
    region_id INTEGER NOT NULL REFERENCES regions(id),
    timestamp TIMESTAMPTZ NOT NULL,
    load_mw FLOAT NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_hourly_readings_region_timestamp
    ON hourly_readings (region_id, timestamp);

CREATE TABLE IF NOT EXISTS weather_observations (
    id SERIAL PRIMARY KEY,
    region_id INTEGER NOT NULL REFERENCES regions(id),
    timestamp TIMESTAMPTZ NOT NULL,
    temperature FLOAT NOT NULL,
    humidity FLOAT NOT NULL,
    wind_speed FLOAT NOT NULL,
    weather_condition VARCHAR(50) NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_weather_observations_region_timestamp
    ON weather_observations (region_id, timestamp);

CREATE TABLE IF NOT EXISTS forecast_results (
    id SERIAL PRIMARY KEY,
    region_id INTEGER NOT NULL REFERENCES regions(id),
    forecast_timestamp TIMESTAMPTZ NOT NULL,
    predicted_load_mw FLOAT NOT NULL,
    effective_capacity_mw FLOAT NOT NULL,
    risk_level VARCHAR(20) NOT NULL,
    model_version VARCHAR(50) NOT NULL DEFAULT 'naive-v1',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_forecast_results_region_ts
    ON forecast_results (region_id, forecast_timestamp);

CREATE TABLE IF NOT EXISTS peak_alerts (
    id SERIAL PRIMARY KEY,
    region_id INTEGER NOT NULL REFERENCES regions(id),
    forecast_result_id INTEGER NOT NULL REFERENCES forecast_results(id),
    risk_level VARCHAR(20) NOT NULL,
    predicted_load_mw FLOAT NOT NULL,
    capacity_mw FLOAT NOT NULL,
    message VARCHAR(300) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'open',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS infrastructure_documents (
    id SERIAL PRIMARY KEY,
    region_id INTEGER NOT NULL REFERENCES regions(id),
    filename VARCHAR(255) NOT NULL,
    filepath VARCHAR(500) NOT NULL,
    extracted_text TEXT,
    capacity_impact_mw FLOAT,
    start_date TIMESTAMPTZ,
    end_date TIMESTAMPTZ,
    description VARCHAR(500),
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS async_jobs (
    id SERIAL PRIMARY KEY,
    job_type VARCHAR(50) NOT NULL,
    region_id INTEGER REFERENCES regions(id),
    status VARCHAR(20) NOT NULL DEFAULT 'queued',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    error_message VARCHAR(500)
);
