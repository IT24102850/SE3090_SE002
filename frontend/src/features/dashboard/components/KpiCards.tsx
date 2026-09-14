import type { KpiDefinition } from '../subtypes/SubtypeDashboardConfig';

/* The KPI strip every sub-type dashboard renders. Which cards appear and
 * what they read is entirely the registry's business - this component only
 * knows how to format a number and pick a colour. */

export interface KpiValues {
  /** Keyed by KpiDefinition.field. A missing key renders an em dash rather
   *  than 0, because "we have no number for this" and "the number is zero"
   *  are different things to an operator looking at a dashboard. */
  [field: string]: number | string | null | undefined;
}

function formatValue(
  value: number | string | null | undefined,
  format: KpiDefinition['format'],
  currency: string,
): string {
  if (value === null || value === undefined || value === '') return '—';
  if (typeof value === 'string') return value;
  if (!Number.isFinite(value)) return '—';

  switch (format) {
    case 'percent':
      return `${value.toFixed(1)}%`;
    case 'currency':
      return `${currency} ${Math.round(value).toLocaleString()}`;
    default:
      return value.toLocaleString();
  }
}

const TONE_COLOR: Record<NonNullable<KpiDefinition['tone']>, string> = {
  default: 'var(--color-text)',
  good: 'var(--color-good)',
  warning: 'var(--color-warning)',
  critical: 'var(--color-critical)',
};

export default function KpiCards({
  kpis,
  values,
  currency = 'LKR',
  loading = false,
}: {
  kpis: KpiDefinition[];
  values: KpiValues;
  currency?: string;
  loading?: boolean;
}) {
  return (
    <div className="stat-grid">
      {kpis.map((kpi) => {
        const raw = values[kpi.field];
        // A zero-tone card still gets the neutral colour; only cards the
        // registry marked as good/warning/critical are tinted.
        const color = TONE_COLOR[kpi.tone ?? 'default'];
        return (
          <div className="stat-tile" key={kpi.id}>
            <div className="stat-tile-label">{kpi.label}</div>
            <div className="stat-tile-value" style={{ color }}>
              {loading ? '…' : formatValue(raw, kpi.format, currency)}
            </div>
            {kpi.sub && <div className="stat-tile-sub">{kpi.sub}</div>}
          </div>
        );
      })}
    </div>
  );
}
