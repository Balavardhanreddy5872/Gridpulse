import { NavLink } from "react-router-dom";

const LINKS = [
  { to: "/", label: "Dashboard", end: true },
  { to: "/forecast", label: "Regional forecast" },
  { to: "/alerts", label: "Alerts" },
  { to: "/documents", label: "Infrastructure documents" },
  { to: "/jobs", label: "Async jobs" },
];

export default function Sidebar() {
  return (
    <aside
      style={{
        width: "var(--sidebar-w)",
        flexShrink: 0,
        borderRight: "1px solid var(--line-soft)",
        padding: "1.75rem 1.25rem",
        display: "flex",
        flexDirection: "column",
      }}
    >
      <div style={{ marginBottom: "2.25rem", paddingLeft: "0.5rem" }}>
        <div style={{ fontWeight: 600, fontSize: "1.05rem", letterSpacing: "-0.01em" }}>
          GridPulse
        </div>
        <div style={{ fontSize: "var(--fs-xs)", color: "var(--text-tertiary)", marginTop: "0.15rem" }}>
          Grid Operations Console
        </div>
      </div>

      <nav style={{ display: "flex", flexDirection: "column", gap: "0.15rem" }}>
        {LINKS.map((link) => (
          <NavLink
            key={link.to}
            to={link.to}
            end={link.end}
            style={({ isActive }) => ({
              padding: "0.55rem 0.6rem",
              borderRadius: "var(--radius-sm)",
              fontSize: "var(--fs-sm)",
              textDecoration: "none",
              color: isActive ? "var(--text-primary)" : "var(--text-secondary)",
              background: isActive ? "var(--bg-panel-raised)" : "transparent",
              borderLeft: isActive ? "2px solid var(--accent-current)" : "2px solid transparent",
            })}
          >
            {link.label}
          </NavLink>
        ))}
      </nav>

      <div style={{ marginTop: "auto", fontSize: "var(--fs-xs)", color: "var(--text-tertiary)" }}>
        Live dashboard — forecasts run on a trained model, jobs process asynchronously.
      </div>
    </aside>
  );
}
