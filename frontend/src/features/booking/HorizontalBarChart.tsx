interface BarDatum {
  label: string;
  value: number;
  color: string;
  displayValue?: string;
}

// A minimal, dependency-free horizontal bar chart: thin rounded-end bars,
// one measure per chart (single axis), direct value labels instead of a
// separate axis scale, sized to its container.
export default function HorizontalBarChart({ data, maxValue }: { data: BarDatum[]; maxValue?: number }) {
  const max = maxValue ?? Math.max(1, ...data.map((d) => d.value));

  if (data.length === 0) {
    return <div className="empty-state">No data for this range.</div>;
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
      {data.map((d) => {
        const pct = Math.max((d.value / max) * 100, d.value > 0 ? 2 : 0);
        return (
          <div key={d.label}>
            <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12.5, marginBottom: 4 }}>
              <span style={{ color: 'var(--color-text-secondary)', fontWeight: 600 }}>{d.label}</span>
              <span style={{ color: 'var(--color-text)', fontWeight: 700 }}>{d.displayValue ?? d.value}</span>
            </div>
            <div style={{ background: 'var(--color-neutral-soft)', borderRadius: 4, height: 8 }}>
              <div
                title={`${d.label}: ${d.displayValue ?? d.value}`}
                style={{
                  width: `${pct}%`,
                  height: '100%',
                  background: d.color,
                  borderRadius: 4,
                  transition: 'width 0.3s ease',
                }}
              />
            </div>
          </div>
        );
      })}
    </div>
  );
}
