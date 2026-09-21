import { useEffect, useState } from "react";
import { api } from "../services/api";
import RiskBadge from "../components/RiskBadge";
import EmptyState from "../components/EmptyState";
import ErrorBanner from "../components/ErrorBanner";

export default function Alerts() {
  const [alerts, setAlerts] = useState(null);
  const [regionsById, setRegionsById] = useState({});
  const [error, setError] = useState(null);

  useEffect(() => {
    let cancelled = false;
    async function load() {
      try {
        const [a, regions] = await Promise.all([api.listAlerts(), api.listRegions()]);
        if (cancelled) return;
        setAlerts(a);
        setRegionsById(Object.fromEntries(regions.map((r) => [r.id, r.name])));
      } catch (e) {
        if (!cancelled) setError(e.message);
      }
    }
    load();
    const interval = setInterval(load, 10000);
    return () => { cancelled = true; clearInterval(interval); };
  }, []);

  return (
    <>
      <div className="page-header">
        <div>
          <h1>Alerts</h1>
          <div className="subtitle">Peak-risk alerts generated from the latest forecasts</div>
        </div>
      </div>

      <ErrorBanner message={error} />

      <div className="panel">
        {alerts === null ? (
          <EmptyState>Loading…</EmptyState>
        ) : alerts.length === 0 ? (
          <EmptyState>No alerts yet. Alerts appear once a forecast crosses the watch threshold.</EmptyState>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Region</th>
                <th>Risk</th>
                <th>Predicted load</th>
                <th>Capacity</th>
                <th>Message</th>
                <th>Status</th>
                <th>Created</th>
              </tr>
            </thead>
            <tbody>
              {alerts.map((a) => (
                <tr key={a.id}>
                  <td>{regionsById[a.region_id] || `Region ${a.region_id}`}</td>
                  <td><RiskBadge level={a.risk_level} /></td>
                  <td className="mono">{a.predicted_load_mw.toFixed(0)} MW</td>
                  <td className="mono">{a.capacity_mw.toFixed(0)} MW</td>
                  <td style={{ color: "var(--text-secondary)" }}>{a.message}</td>
                  <td><span className={`badge ${a.status === "open" ? "processing" : "completed"}`}>{a.status}</span></td>
                  <td className="mono" style={{ color: "var(--text-tertiary)" }}>
                    {new Date(a.created_at).toLocaleString()}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </>
  );
}
