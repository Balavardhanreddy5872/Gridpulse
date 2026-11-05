#!/usr/bin/env bash
# VIDEO / EVIDENCE: a CONTROLLED HTTP 5xx, end to end.
#
#  1. the 5xx counter (log-based metric gridpulse_http_5xx) for the last hour - BEFORE
#  2. N requests to https://<domain>/api/system/simulate-error -> HTTP 500
#     (touches no data; each request carries its own X-Request-ID so we can find it)
#  3. the JSON log entry Cloud Logging stored for one of those requests
#  4. the counter again - AFTER (waits until the new errors are counted, ~1-3 min)
#
# Five errors in a row are more than the alert threshold (more than 2 within 5
# minutes), so the "GridPulse - HTTP 5xx errors" alert fires and e-mails the team.
#
#   ./deploy/m6/demo_5xx.sh          # 5 errors
#   ./deploy/m6/demo_5xx.sh 1        # one error (stays below the alert threshold)
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh
need jq "brew install jq"
N="${1:-5}"
RUN="m6demo-$(date +%s)"
mkdir -p "$EVIDENCE_DIR"
OUT="$EVIDENCE_DIR/controlled_5xx.txt"

# Sum of the log-based metric over the last 60 minutes (Cloud Monitoring API).
metric_total() {
  local token start end
  token="$(gcloud auth print-access-token)"
  start="$(jq -rn 'now - 3600 | todate')"; end="$(jq -rn 'now | todate')"
  curl -sS --get "https://monitoring.googleapis.com/v3/projects/${PROJECT_ID}/timeSeries" \
    -H "Authorization: Bearer $token" \
    --data-urlencode "filter=metric.type=\"logging.googleapis.com/user/${LOG_METRIC}\"" \
    --data-urlencode "interval.startTime=$start" --data-urlencode "interval.endTime=$end" \
    --data-urlencode "aggregation.alignmentPeriod=3600s" \
    --data-urlencode "aggregation.perSeriesAligner=ALIGN_DELTA" \
    --data-urlencode "aggregation.crossSeriesReducer=REDUCE_SUM" \
  | jq '[.timeSeries[]?.points[]?.value.int64Value // "0" | tonumber] | add // 0'
}

{
echo "GridPulse controlled HTTP 5xx - $(date '+%Y-%m-%d %H:%M:%S %Z') - $APP_URL"

step "1. Log-based metric $LOG_METRIC, last 60 minutes - BEFORE"
BEFORE="$(metric_total)"
echo "    5xx counted: $BEFORE"

step "2. $N controlled errors:  GET $APP_URL/api/system/simulate-error"
for i in $(seq 1 "$N"); do
  printf '    %s  ' "$(now)"
  curl -sS --max-time 15 -H "X-Request-ID: ${RUN}-${i}" -w '  -> HTTP %{http_code}\n' \
    "$APP_URL/api/system/simulate-error"
done

step "3. The JSON log entry in Cloud Logging (request ${RUN}-1)"
FILTER="resource.type=\"k8s_container\" AND resource.labels.namespace_name=\"$NAMESPACE\" AND resource.labels.container_name=\"backend\" AND jsonPayload.event=\"http_request\" AND jsonPayload.request_id=\"${RUN}-1\""
echo "    query: $FILTER"
ENTRY=""
for _ in $(seq 1 12); do
  ENTRY="$(gcloud logging read "$FILTER" --project "$PROJECT_ID" --freshness=15m --limit=1 --format=json)"
  [ "$(echo "$ENTRY" | jq length)" -gt 0 ] && break
  sleep 5
done
echo "$ENTRY" | jq '.[0] | {severity, timestamp, logName, resource: .resource.labels | {cluster_name, namespace_name, pod_name, container_name},
  httpRequest, jsonPayload: (.jsonPayload | {message, event, method, path, route, status_code, status_class, probe, duration_ms, request_id, version, pod})}'

step "4. Log-based metric $LOG_METRIC - AFTER (log-based metrics lag 1-3 minutes)"
AFTER="$BEFORE"
for _ in $(seq 1 24); do
  AFTER="$(metric_total)"
  [ "$AFTER" -ge $((BEFORE + N)) ] && break
  printf '    %s  counted so far: %s (was %s) - checking again in 10 s\n' "$(now)" "$AFTER" "$BEFORE"
  sleep 10
done
echo "    5xx counted: $BEFORE -> $AFTER  (+$((AFTER - BEFORE)))"
echo
echo "Metric definition: gcloud logging metrics describe $LOG_METRIC"
echo "Dashboard:         $(tf output -raw dashboard_url 2>/dev/null || echo 'Monitoring > Dashboards > GridPulse - production (Milestone 6)')"
if [ "$N" -gt 2 ]; then
  echo "Alert:             more than 2 in 5 min -> 'GridPulse - HTTP 5xx errors' fires; e-mail arrives in ~2-4 min"
fi
} 2>&1 | tee "$OUT"
echo "saved: ${OUT#"$REPO_ROOT"/}"
