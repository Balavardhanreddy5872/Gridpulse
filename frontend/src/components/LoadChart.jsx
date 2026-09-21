import {
  ComposedChart, Line, Area, XAxis, YAxis, CartesianGrid,
  Tooltip, Legend, ReferenceLine, ResponsiveContainer,
} from "recharts";

/**
 * historical: [{ timestamp, load_mw }]
 * forecast:   [{ forecast_timestamp, predicted_load_mw }]
 * capacityMw: effective capacity line
 */
export default function LoadChart({ historical, forecast, capacityMw }) {
  const histPoints = historical.map((r) => ({
    ts: r.timestamp,
    historical_mw: r.load_mw,
  }));
  const forecastPoints = forecast.map((f) => ({
    ts: f.forecast_timestamp,
    forecast_mw: f.predicted_load_mw,
    risk_level: f.risk_level,
  }));

  const merged = [...histPoints, ...forecastPoints].sort(
    (a, b) => new Date(a.ts) - new Date(b.ts)
  );

  const formatTick = (ts) => {
    const d = new Date(ts);
    return `${d.getMonth() + 1}/${d.getDate()} ${String(d.getHours()).padStart(2, "0")}:00`;
  };

  return (
    <ResponsiveContainer width="100%" height={340}>
      <ComposedChart data={merged} margin={{ top: 10, right: 16, left: 0, bottom: 0 }}>
        <CartesianGrid stroke="var(--line-soft)" strokeDasharray="0" vertical={false} />
        <XAxis
          dataKey="ts"
          tickFormatter={formatTick}
          stroke="var(--text-tertiary)"
          fontSize={11}
          fontFamily="var(--font-data)"
          minTickGap={40}
        />
        <YAxis
          stroke="var(--text-tertiary)"
          fontSize={11}
          fontFamily="var(--font-data)"
          width={56}
          tickFormatter={(v) => `${v}`}
        />
        <Tooltip
          labelFormatter={formatTick}
          contentStyle={{
            background: "var(--bg-panel-raised)",
            border: "1px solid var(--line)",
            borderRadius: 6,
            fontSize: 12,
            fontFamily: "var(--font-data)",
          }}
        />
        <Legend wrapperStyle={{ fontSize: 12 }} />
        <ReferenceLine
          y={capacityMw}
          stroke="var(--status-critical)"
          strokeDasharray="4 4"
          label={{
            value: `Effective capacity ${capacityMw.toFixed(0)} MW`,
            fill: "var(--status-critical)",
            fontSize: 11,
            position: "insideTopRight",
          }}
        />
        <Line
          type="monotone"
          dataKey="historical_mw"
          name="Historical load"
          stroke="var(--accent-current)"
          dot={false}
          strokeWidth={2}
          connectNulls
        />
        <Line
          type="monotone"
          dataKey="forecast_mw"
          name="Forecasted load"
          stroke="var(--accent-signal)"
          strokeDasharray="5 3"
          dot={false}
          strokeWidth={2}
          connectNulls
        />
      </ComposedChart>
    </ResponsiveContainer>
  );
}
