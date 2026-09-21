import { useEffect, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { api } from "../services/api";
import LoadChart from "../components/LoadChart";
import RiskBadge from "../components/RiskBadge";
import EmptyState from "../components/EmptyState";
import ErrorBanner from "../components/ErrorBanner";

export default function RegionalForecast() {
  const [searchParams, setSearchParams] = useSearchParams();
  const [regions, setRegions] = useState(null);
  const [selectedId, setSelectedId] = useState(searchParams.get("region") || null);
  const [readings, setReadings] = useState(null);
  const [forecast, setForecast] = useState(null);
  const [recomputing, setRecomputing] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    api.listRegions().then((r) => {
      setRegions(r);
      if (!selectedId && r.length > 0) {
        setSelectedId(String(r[0].id));
      }
    }).catch((e) => setError(e.message));
  }, []);

  useEffect(() => {
    if (!selectedId) return;
    setSearchParams({ region: selectedId });
    loadRegionData(selectedId);
  }, [selectedId]);

  async function loadRegionData(regionId) {
    setError(null);
    try {
      const [r, f] = await Promise.all([
        api.getRegionReadings(regionId, 96),
        api.getForecast(regionId),
      ]);
      setReadings(r);
      setForecast(f);
    } catch (e) {
      setError(e.message);
    }
  }

  async function handleRecompute() {
    setRecomputing(true);
    setError(null);
    try {
      const f = await api.recomputeForecast(selectedId);
      setForecast(f);
    } catch (e) {
      setError(e.message);
    } finally {
      setRecomputing(false);
    }
  }

  const selectedRegion = regions?.find((r) => String(r.id) === String(selectedId));
  const nextRisk = forecast?.points?.[0]?.risk_level;
  const worstRisk = forecast?.points?.reduce((worst, p) => {
    const order = { normal: 0, watch: 1, high: 2, critical: 3 };
    return order[p.risk_level] > order[worst] ? p.risk_level : worst;
  }, "normal");

  return (
    <>
      <div className="page-header">
        <div>
          <h1>Regional forecast</h1>
          <div className="subtitle">Historical demand, 24-hour forecast, and effective capacity</div>
        </div>
        <div style={{ display: "flex", gap: "0.6rem", alignItems: "center" }}>
          {regions && (
            <select value={selectedId || ""} onChange={(e) => setSelectedId(e.target.value)}>
              {regions.map((r) => (
                <option key={r.id} value={r.id}>{r.name}</option>
              ))}
            </select>
          )}
          <button className="btn" onClick={handleRecompute} disabled={recomputing || !selectedId}>
            {recomputing ? "Recomputing…" : "Recompute forecast"}
          </button>
        </div>
      </div>

      <ErrorBanner message={error} />

      {!readings || !forecast ? (
        <div className="panel"><EmptyState>Loading region data…</EmptyState></div>
      ) : (
        <>
          <div className="stat-grid">
            <div className="stat-cell">
              <div className="label">Region capacity</div>
              <div className="value">{selectedRegion?.capacity_mw.toFixed(0)}<span style={{fontSize: "0.9rem", color: "var(--text-tertiary)"}}> MW</span></div>
            </div>
            <div className="stat-cell">
              <div className="label">Effective capacity</div>
              <div className="value">{forecast.effective_capacity_mw.toFixed(0)}<span style={{fontSize: "0.9rem", color: "var(--text-tertiary)"}}> MW</span></div>
            </div>
            <div className="stat-cell">
              <div className="label">Next-hour risk</div>
              <div className="value" style={{ fontSize: "var(--fs-md)" }}><RiskBadge level={nextRisk} /></div>
            </div>
            <div className="stat-cell">
              <div className="label">Peak risk (24h)</div>
              <div className="value" style={{ fontSize: "var(--fs-md)" }}><RiskBadge level={worstRisk} /></div>
            </div>
          </div>

          <div className="panel">
            <div className="panel-title">
              Load curve — last 96 hours actual, next {forecast.points.length}h forecast
            </div>
            {readings.length === 0 ? (
              <EmptyState>No historical readings yet for this region.</EmptyState>
            ) : (
              <LoadChart
                historical={readings}
                forecast={forecast.points}
                capacityMw={forecast.effective_capacity_mw}
              />
            )}
          </div>
        </>
      )}
    </>
  );
}
