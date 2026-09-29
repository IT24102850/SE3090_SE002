import { useLazyGetDepartureForecastQuery } from '../../../api/bookingApi';
import type { DepartureSummary } from '../../booking/types';

const TONE: Record<string, { bg: string; label: string; icon: string }> = {
  ok: { bg: 'var(--color-good)', label: 'Safe to sail', icon: '🟢' },
  caution: { bg: 'var(--color-warning)', label: 'Marginal', icon: '🟡' },
  unsafe: { bg: 'var(--color-critical)', label: 'Unsafe to sail', icon: '🔴' },
  unknown: { bg: 'var(--color-neutral)', label: 'No reading', icon: '⚪' },
};

/* Marine forecast for one departure, from Open-Meteo.
 *
 * Fetched on demand rather than with the board: it is a third-party call, and
 * a board showing a dozen sailings should not fire a dozen of them on load.
 *
 * It only ever *suggests* a cancellation. Cancelling strands every guest
 * aboard, so the button below hands over to the existing cancel-weather flow
 * and a human decision - the forecast never triggers it. */
export function DepartureForecastPanel({
  departure,
  onCancelWeather,
}: {
  departure: DepartureSummary;
  onCancelWeather: (departure: DepartureSummary) => void;
}) {
  const [fetchForecast, { data, isFetching, isUninitialized }] = useLazyGetDepartureForecastQuery();

  if (isUninitialized) {
    return (
      <button className="btn btn-ghost btn-sm" onClick={() => fetchForecast(departure.id)}>
        🌊 Check forecast
      </button>
    );
  }

  if (isFetching) {
    return <div style={{ fontSize: '.78rem', color: 'var(--color-text-muted)' }}><span className="spinner spinner-dark" /> Reading the forecast…</div>;
  }

  if (!data?.available) {
    return (
      <div style={{ fontSize: '.76rem', color: 'var(--color-text-muted)' }}>
        {data?.message ?? 'No forecast available.'}{' '}
        <button className="btn btn-ghost btn-sm" onClick={() => fetchForecast(departure.id)}>Retry</button>
      </div>
    );
  }

  const risk = data.risk!;
  const f = data.forecast!;
  const tone = TONE[risk.level] ?? TONE.unknown;

  return (
    <div style={{
      marginTop: 8, padding: '10px 12px', borderRadius: 12,
      border: `1px solid ${tone.bg}`, background: 'var(--color-surface-muted)',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
        <span style={{
          padding: '2px 9px', borderRadius: 999, fontSize: '.7rem', fontWeight: 800,
          color: '#fff', background: tone.bg,
        }}>
          {tone.icon} {tone.label}
        </span>
        <span style={{ fontSize: '.72rem', color: 'var(--color-text-muted)' }}>
          {f.source} · {new Date(f.forecastedFor).toLocaleString(undefined, { weekday: 'short', hour: '2-digit', minute: '2-digit' })}
        </span>
      </div>

      <div style={{ display: 'flex', gap: 14, flexWrap: 'wrap', marginTop: 8, fontSize: '.78rem' }}>
        <span><b>{f.windSpeedKnots ?? '—'}</b> kn wind{f.windGustKnots ? ` (gust ${f.windGustKnots})` : ''}</span>
        <span><b>{f.waveHeightMetres ?? '—'}</b> m waves</span>
        <span><b>{f.visibilityKm ?? '—'}</b> km visibility</span>
      </div>

      <ul style={{ margin: '8px 0 0', paddingLeft: 18, fontSize: '.75rem', color: 'var(--color-text-secondary)' }}>
        {risk.reasons.map((reason, i) => <li key={i}>{reason}</li>)}
      </ul>

      {risk.suggestCancellation && (
        <div style={{ marginTop: 10 }}>
          <p style={{ margin: '0 0 6px', fontSize: '.76rem', color: 'var(--color-critical)' }}>
            Conditions are outside safe limits
            {data.guestsAffected ? ` and ${data.guestsAffected} guest(s) are booked` : ''}.
            The forecast cannot cancel a sailing — that is your call.
          </p>
          <button className="btn btn-danger btn-sm" onClick={() => onCancelWeather(departure)}>
            Cancel for weather…
          </button>
        </div>
      )}

      {f.coordinates.from !== 'resource' && (
        <p style={{ margin: '8px 0 0', fontSize: '.7rem', color: 'var(--color-text-muted)' }}>
          Using {f.coordinates.from}. Add latitude/longitude to this vessel for a forecast at its own position.
        </p>
      )}
    </div>
  );
}
