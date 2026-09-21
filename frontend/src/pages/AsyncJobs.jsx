import { useEffect, useState } from "react";
import { api } from "../services/api";
import EmptyState from "../components/EmptyState";
import ErrorBanner from "../components/ErrorBanner";

export default function AsyncJobs() {
  const [jobs, setJobs] = useState(null);
  const [regionsById, setRegionsById] = useState({});
  const [error, setError] = useState(null);
  const [simulating, setSimulating] = useState(false);
  const [notice, setNotice] = useState(null);

  useEffect(() => {
    let cancelled = false;
    async function load() {
      try {
        const [j, regions] = await Promise.all([api.listJobs(), api.listRegions()]);
        if (cancelled) return;
        setJobs(j);
        setRegionsById(Object.fromEntries(regions.map((r) => [r.id, r.name])));
      } catch (e) {
        if (!cancelled) setError(e.message);
      }
    }
    load();
    // Poll fairly often here - this is the page meant to show a queue
    // filling up live during the "simulate spike" demo moment.
    const interval = setInterval(load, 3000);
    return () => { cancelled = true; clearInterval(interval); };
  }, []);

  async function handleSimulate() {
    setSimulating(true);
    setError(null);
    setNotice(null);
    try {
      const res = await api.simulateSpike(10);
      setNotice(res.message);
      const j = await api.listJobs();
      setJobs(j);
    } catch (e) {
      setError(e.message);
    } finally {
      setSimulating(false);
    }
  }

  const counts = (jobs || []).reduce((acc, j) => {
    acc[j.status] = (acc[j.status] || 0) + 1;
    return acc;
  }, {});

  return (
    <>
      <div className="page-header">
        <div>
          <h1>Async jobs</h1>
          <div className="subtitle">Forecast-recompute jobs, queued for asynchronous processing</div>
        </div>
        <button className="btn" onClick={handleSimulate} disabled={simulating}>
          {simulating ? "Queuing…" : "Simulate multi-region spike"}
        </button>
      </div>

      <ErrorBanner message={error} />
      {notice && (
        <div className="panel" style={{ borderColor: "var(--accent-current)", marginBottom: "1.25rem" }}>
          {notice}
        </div>
      )}

      <div className="stat-grid">
        <div className="stat-cell">
          <div className="label">Queued</div>
          <div className="value">{counts.queued || 0}</div>
        </div>
        <div className="stat-cell">
          <div className="label">Processing</div>
          <div className="value status-watch">{counts.processing || 0}</div>
        </div>
        <div className="stat-cell">
          <div className="label">Completed</div>
          <div className="value">{counts.completed || 0}</div>
        </div>
        <div className="stat-cell">
          <div className="label">Failed</div>
          <div className={`value ${counts.failed ? "status-critical" : ""}`}>{counts.failed || 0}</div>
        </div>
      </div>

      <div className="panel">
        <div className="panel-title">Job queue</div>
        {jobs === null ? (
          <EmptyState>Loading…</EmptyState>
        ) : jobs.length === 0 ? (
          <EmptyState>
            No jobs yet. Click "Simulate multi-region spike" to queue forecast-recompute jobs
            for 10 regions at once.
          </EmptyState>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Job</th>
                <th>Type</th>
                <th>Region</th>
                <th>Status</th>
                <th>Created</th>
                <th>Completed</th>
              </tr>
            </thead>
            <tbody>
              {jobs.map((j) => (
                <tr key={j.id}>
                  <td className="mono">#{j.id}</td>
                  <td>{j.job_type}</td>
                  <td>{regionsById[j.region_id] || "—"}</td>
                  <td><span className={`badge ${j.status}`}>{j.status}</span></td>
                  <td className="mono" style={{ color: "var(--text-tertiary)" }}>
                    {new Date(j.created_at).toLocaleTimeString()}
                  </td>
                  <td className="mono" style={{ color: "var(--text-tertiary)" }}>
                    {j.completed_at ? new Date(j.completed_at).toLocaleTimeString() : "—"}
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
