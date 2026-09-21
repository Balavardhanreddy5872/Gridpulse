export default function RiskBadge({ level }) {
  const safe = level || "normal";
  return (
    <span>
      <span className={`risk-dot ${safe}`} />
      <span className="risk-label">{safe}</span>
    </span>
  );
}
