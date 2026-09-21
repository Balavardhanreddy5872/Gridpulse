import { useEffect, useState } from "react";
import { api } from "../services/api";
import EmptyState from "../components/EmptyState";
import ErrorBanner from "../components/ErrorBanner";

export default function Documents() {
  const [regions, setRegions] = useState(null);
  const [documents, setDocuments] = useState(null);
  const [error, setError] = useState(null);
  const [uploading, setUploading] = useState(false);

  const [form, setForm] = useState({
    region_id: "",
    file: null,
    capacity_impact_mw: "",
    start_date: "",
    end_date: "",
    description: "",
  });

  useEffect(() => { refresh(); }, []);

  async function refresh() {
    try {
      const [r, d] = await Promise.all([api.listRegions(), api.listDocuments()]);
      setRegions(r);
      setDocuments(d);
      setForm((f) => ({ ...f, region_id: f.region_id || String(r[0]?.id || "") }));
    } catch (e) {
      setError(e.message);
    }
  }

  async function handleUpload(e) {
    e.preventDefault();
    if (!form.file || !form.region_id) return;
    setUploading(true);
    setError(null);
    try {
      const fd = new FormData();
      fd.append("region_id", form.region_id);
      fd.append("file", form.file);
      if (form.capacity_impact_mw) fd.append("capacity_impact_mw", form.capacity_impact_mw);
      if (form.start_date) fd.append("start_date", form.start_date);
      if (form.end_date) fd.append("end_date", form.end_date);
      if (form.description) fd.append("description", form.description);

      await api.uploadDocument(fd);
      setForm((f) => ({ ...f, file: null, capacity_impact_mw: "", start_date: "", end_date: "", description: "" }));
      e.target.reset();
      await refresh();
    } catch (err) {
      setError(err.message);
    } finally {
      setUploading(false);
    }
  }

  const regionsById = Object.fromEntries((regions || []).map((r) => [r.id, r.name]));

  return (
    <>
      <div className="page-header">
        <div>
          <h1>Infrastructure documents</h1>
          <div className="subtitle">Upload inspection/outage PDFs — capacity impact links directly to the forecast</div>
        </div>
      </div>

      <ErrorBanner message={error} />

      <div className="panel">
        <div className="panel-title">Upload a report</div>
        <form onSubmit={handleUpload} style={{ display: "flex", flexWrap: "wrap", gap: "0.75rem", alignItems: "flex-end" }}>
          <div>
            <div style={{ fontSize: "var(--fs-xs)", color: "var(--text-secondary)", marginBottom: 4 }}>Region</div>
            <select value={form.region_id} onChange={(e) => setForm({ ...form, region_id: e.target.value })}>
              {(regions || []).map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
            </select>
          </div>
          <div>
            <div style={{ fontSize: "var(--fs-xs)", color: "var(--text-secondary)", marginBottom: 4 }}>PDF file</div>
            <input type="file" accept="application/pdf" onChange={(e) => setForm({ ...form, file: e.target.files[0] })} />
          </div>
          <div>
            <div style={{ fontSize: "var(--fs-xs)", color: "var(--text-secondary)", marginBottom: 4 }}>
              Capacity impact MW (optional override)
            </div>
            <input type="number" placeholder="auto-detect" value={form.capacity_impact_mw}
              onChange={(e) => setForm({ ...form, capacity_impact_mw: e.target.value })} style={{ width: 150 }} />
          </div>
          <div>
            <div style={{ fontSize: "var(--fs-xs)", color: "var(--text-secondary)", marginBottom: 4 }}>Start date</div>
            <input type="date" value={form.start_date} onChange={(e) => setForm({ ...form, start_date: e.target.value })} />
          </div>
          <div>
            <div style={{ fontSize: "var(--fs-xs)", color: "var(--text-secondary)", marginBottom: 4 }}>End date</div>
            <input type="date" value={form.end_date} onChange={(e) => setForm({ ...form, end_date: e.target.value })} />
          </div>
          <button className="btn" type="submit" disabled={uploading || !form.file}>
            {uploading ? "Uploading…" : "Upload & extract"}
          </button>
        </form>
        <div style={{ fontSize: "var(--fs-xs)", color: "var(--text-tertiary)", marginTop: "0.6rem" }}>
          Fields left blank are auto-extracted from the PDF text where possible. Anything the extractor
          can't find confidently stays empty rather than being guessed.
        </div>
      </div>

      <div className="panel">
        <div className="panel-title">Uploaded documents</div>
        {documents === null ? (
          <EmptyState>Loading…</EmptyState>
        ) : documents.length === 0 ? (
          <EmptyState>No documents uploaded yet.</EmptyState>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Region</th>
                <th>File</th>
                <th>Capacity impact</th>
                <th>Window</th>
                <th>Description</th>
                <th>Uploaded</th>
              </tr>
            </thead>
            <tbody>
              {documents.map((d) => (
                <tr key={d.id}>
                  <td>{regionsById[d.region_id] || `Region ${d.region_id}`}</td>
                  <td>{d.filename}</td>
                  <td className="mono">{d.capacity_impact_mw != null ? `${d.capacity_impact_mw} MW` : "—"}</td>
                  <td className="mono" style={{ color: "var(--text-secondary)" }}>
                    {d.start_date ? new Date(d.start_date).toLocaleDateString() : "—"}
                    {" → "}
                    {d.end_date ? new Date(d.end_date).toLocaleDateString() : "—"}
                  </td>
                  <td style={{ color: "var(--text-secondary)", maxWidth: 280 }}>{d.description || "—"}</td>
                  <td className="mono" style={{ color: "var(--text-tertiary)" }}>
                    {new Date(d.uploaded_at).toLocaleString()}
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
