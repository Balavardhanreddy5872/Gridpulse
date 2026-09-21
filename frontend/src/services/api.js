const BASE_URL = import.meta.env.VITE_API_BASE_URL || "http://localhost:8000";

async function request(path, options = {}) {
  const res = await fetch(`${BASE_URL}${path}`, {
    headers: options.body instanceof FormData ? {} : { "Content-Type": "application/json" },
    ...options,
  });
  if (!res.ok) {
    let detail = res.statusText;
    try {
      const data = await res.json();
      detail = data.detail || detail;
    } catch {
      // response wasn't JSON - keep statusText
    }
    throw new Error(detail);
  }
  if (res.status === 204) return null;
  return res.json();
}

export const api = {
  health: () => request("/api/health"),

  listRegions: () => request("/api/regions"),
  getRegion: (id) => request(`/api/regions/${id}`),
  getRegionReadings: (id, hours = 168) => request(`/api/regions/${id}/readings?hours=${hours}`),

  getForecast: (regionId) => request(`/api/regions/${regionId}/forecast`),
  recomputeForecast: (regionId) =>
    request(`/api/forecast/${regionId}`, { method: "POST" }),

  listAlerts: () => request("/api/alerts"),
  listRegionAlerts: (regionId) => request(`/api/regions/${regionId}/alerts`),

  listDocuments: (regionId) =>
    request(regionId ? `/api/documents?region_id=${regionId}` : "/api/documents"),
  uploadDocument: (formData) =>
    request("/api/documents/upload", { method: "POST", body: formData }),

  listJobs: () => request("/api/jobs"),
  simulateSpike: (regionCount) =>
    request("/api/jobs/simulate-spike", {
      method: "POST",
      body: JSON.stringify({ region_count: regionCount }),
    }),

  modelMetrics: () => request("/api/model/metrics"),
};
