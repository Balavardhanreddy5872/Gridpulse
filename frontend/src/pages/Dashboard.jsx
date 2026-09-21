import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { api } from "../services/api";
import RiskBadge from "../components/RiskBadge";
import EmptyState from "../components/EmptyState";
import ErrorBanner from "../components/ErrorBanner";

export default function Dashboard() {
  const [regions, setRegions] = useState(null);
  const [alerts, setAlerts] = useState(null);
  const [jobs, setJobs] = useState(null);
  const [metrics, setMetrics] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    let cancelled = false;
    async function load() {
      try {
        const [r, a, j, m] = await Promise.all([
          api.listRegions(),
          api.listAlerts(),
          api.listJobs(),
          api.modelMetrics(),
        ]);
        if (cancelled) return;
        setRegions(r);
        setAlerts(a);
        setJobs(j);
        setMetrics(m);
      } catch (e) {
        if (!cancelled) setError(e.message);
      }
    }
    load();
    const interval = setInterval(load, 10000);
    return () => {
      cancelled = true;
      clearInterval(interval);
    };
  }, []);

  const loading = regions === null;
  const atRiskCount = regions?.filter((r) => r.current_risk_level !== "normal").length ?? 0;
  const openAlerts = alerts?.filter((a) => a.status === "open").length ?? 0;
  const processingJobs = jobs?.filter((j) => j.status === "queued" || j.status === "processing").length ?? 0;

  return (
    <>
      <div className="page-header">
        <div>
          <h1>Dashboard</h1>
          <div className="subtitle">System status across all monitored regions</div>
        </div>
      </div>

      <ErrorBanner message={error} />

      <div className="stat-grid">
        <div className="stat-cell">
          <div className="label">Monitored regions</div>
          <div className="value">{loading ? "—" : regions.length}</div>
        </div>
        <div className="stat-cell">
          <div className="label">Regions at risk</div>
          <div className={`value ${atRiskCount > 0 ? "status-high" : ""}`}>
            {loading ? "—" : atRiskCount}
          </div>
        </div>
        <div className="stat-cell">
          <div className="label">Open alerts</div>
          <div className={`value ${openAlerts > 0 ? "status-watch" : ""}`}>
            {loading ? "—" : openAlerts}
          </div>
        </div>
        <div className="stat-cell">
          <div className="label">Jobs in flight</div>
          <div className="value">{jobs === null ? "—" : processingJobs}</div>
        </div>
      </div>

      <div className="panel">
        <div className="panel-title">Regions</div>
        {loading ? (
          <EmptyState>Loading regions…</EmptyState>
        ) : regions.length === 0 ? (
          <EmptyState>
            No regions yet. Run <code>python scripts/seed_database.py</code> to load demo data.
          </EmptyState>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Region</th>
                <th>State</th>
                <th>Capacity</th>
                <th>Risk</th>
                <th>Open alerts</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {regions.map((r) => (
                <tr key={r.id}>
                  <td>{r.name}</td>
                  <td>{r.state}</td>
                  <td className="mono">{r.capacity_mw.toFixed(0)} MW</td>
                  <td><RiskBadge level={r.current_risk_level} /></td>
                  <td className="mono">{r.active_alert_count}</td>
                  <td>
                    <Link to={`/forecast?region=${r.id}`} style={{ color: "var(--accent-current)", fontSize: "var(--fs-sm)" }}>
                      View forecast →
                    </Link>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <div className="panel">
        <div className="panel-title">Model status</div>
        {metrics ? (
          <div style={{ fontSize: "var(--fs-sm)", color: "var(--text-secondary)" }}>
            <span className="mono" style={{ color: "var(--text-primary)" }}>{metrics.model_version}</span>
            {" — "}
            {metrics.note}
          </div>
        ) : (
          <EmptyState>Loading…</EmptyState>
        )}
      </div>
    </>
  );
}
