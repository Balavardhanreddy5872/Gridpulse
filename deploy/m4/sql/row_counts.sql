-- Row count + content checksum for every GridPulse table.
-- Run against BOTH databases; identical output = nothing lost or altered.
-- checksum = first 12 hex chars of md5(all rows as text, ordered by id), with
-- time zone and float formatting pinned so both servers render rows the same.
SET TimeZone = 'UTC';
SET extra_float_digits = 1;
SET DateStyle = 'ISO, MDY';
SELECT table_name, row_count, checksum FROM (
  SELECT 1 AS ord, 'regions' AS table_name, count(*) AS row_count,
         coalesce(left(md5(string_agg(t::text, '|' ORDER BY t.id)), 12), '-') AS checksum FROM regions t
  UNION ALL SELECT 2, 'hourly_readings', count(*), coalesce(left(md5(string_agg(t::text, '|' ORDER BY t.id)), 12), '-') FROM hourly_readings t
  UNION ALL SELECT 3, 'weather_observations', count(*), coalesce(left(md5(string_agg(t::text, '|' ORDER BY t.id)), 12), '-') FROM weather_observations t
  UNION ALL SELECT 4, 'forecast_results', count(*), coalesce(left(md5(string_agg(t::text, '|' ORDER BY t.id)), 12), '-') FROM forecast_results t
  UNION ALL SELECT 5, 'peak_alerts', count(*), coalesce(left(md5(string_agg(t::text, '|' ORDER BY t.id)), 12), '-') FROM peak_alerts t
  UNION ALL SELECT 6, 'infrastructure_documents', count(*), coalesce(left(md5(string_agg(t::text, '|' ORDER BY t.id)), 12), '-') FROM infrastructure_documents t
  UNION ALL SELECT 7, 'async_jobs', count(*), coalesce(left(md5(string_agg(t::text, '|' ORDER BY t.id)), 12), '-') FROM async_jobs t
) counts ORDER BY ord;
