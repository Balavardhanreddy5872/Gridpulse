-- After a data-only load, point every id sequence just past the highest id
-- so the next INSERT from the app does not collide with a copied row.
SELECT 'regions' AS seq, setval(pg_get_serial_sequence('regions', 'id'), coalesce(max(id), 1), max(id) IS NOT NULL) FROM regions
UNION ALL SELECT 'hourly_readings', setval(pg_get_serial_sequence('hourly_readings', 'id'), coalesce(max(id), 1), max(id) IS NOT NULL) FROM hourly_readings
UNION ALL SELECT 'weather_observations', setval(pg_get_serial_sequence('weather_observations', 'id'), coalesce(max(id), 1), max(id) IS NOT NULL) FROM weather_observations
UNION ALL SELECT 'forecast_results', setval(pg_get_serial_sequence('forecast_results', 'id'), coalesce(max(id), 1), max(id) IS NOT NULL) FROM forecast_results
UNION ALL SELECT 'peak_alerts', setval(pg_get_serial_sequence('peak_alerts', 'id'), coalesce(max(id), 1), max(id) IS NOT NULL) FROM peak_alerts
UNION ALL SELECT 'infrastructure_documents', setval(pg_get_serial_sequence('infrastructure_documents', 'id'), coalesce(max(id), 1), max(id) IS NOT NULL) FROM infrastructure_documents
UNION ALL SELECT 'async_jobs', setval(pg_get_serial_sequence('async_jobs', 'id'), coalesce(max(id), 1), max(id) IS NOT NULL) FROM async_jobs;
