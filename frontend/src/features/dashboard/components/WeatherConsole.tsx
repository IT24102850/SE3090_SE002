import { useState } from 'react';
import { useGetWeatherQuery, useRecordWeatherMutation } from '../../../api/bookingApi';
import { apiErrorMessage, useToast } from '../../../shared/components/Toast';
import { formatDateTime } from '../../../shared/dateUtils';

/* The weather & sea-state console.
 *
 * Readings are entered by hand: there is no external weather provider wired
 * up, deliberately. The backing table carries a `source` column so a future
 * provider can write rows alongside these without a schema change - what is
 * shown here is whatever the harbour actually reported, not a forecast this
 * app invented. */

/** Douglas sea state, 0 (glassy) to 9 (phenomenal). Labelled rather than
 *  numeric-only because a skipper reads "rough", not "5". */
const SEA_STATES = [
  '0 — Calm (glassy)',
  '1 — Calm (rippled)',
  '2 — Smooth',
  '3 — Slight',
  '4 — Moderate',
  '5 — Rough',
  '6 — Very rough',
  '7 — High',
  '8 — Very high',
  '9 — Phenomenal',
];

function Reading({ label, value, unit }: { label: string; value?: number | null; unit: string }) {
  return (
    <div>
      <div style={{ fontSize: '0.72rem', textTransform: 'uppercase', letterSpacing: '0.07em', color: 'var(--color-text-muted)' }}>
        {label}
      </div>
      <div style={{ fontSize: '1.1rem', fontWeight: 700 }}>
        {value === null || value === undefined ? '—' : `${value} ${unit}`}
      </div>
    </div>
  );
}

export default function WeatherConsole() {
  const { data, isLoading } = useGetWeatherQuery({ limit: 8 });
  const [record, { isLoading: saving }] = useRecordWeatherMutation();
  const [open, setOpen] = useState(false);
  const [form, setForm] = useState({ wind: '', wave: '', visibility: '', seaState: '', note: '' });
  const toast = useToast();

  const latest = data?.latest;

  const submit = async () => {
    // Every field is optional: an operator who only measured wind should be
    // able to log wind. Blank means "not measured", stored as null, not 0.
    const num = (v: string) => (v.trim() === '' ? undefined : Number(v));
    try {
      await record({
        windSpeedKnots: num(form.wind),
        waveHeightMetres: num(form.wave),
        visibilityKm: num(form.visibility),
        seaStateCode: num(form.seaState),
        note: form.note.trim() || undefined,
      }).unwrap();
      toast.show('Weather reading recorded.', 'success');
      setForm({ wind: '', wave: '', visibility: '', seaState: '', note: '' });
      setOpen(false);
    } catch (error) {
      toast.show(apiErrorMessage(error, 'Could not record the reading.'), 'error');
    }
  };

  return (
    <div className="card" style={{ padding: 16 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
        <div>
          <p className="chart-title" style={{ margin: 0 }}>Weather & sea state</p>
          <p className="chart-subtitle" style={{ margin: 0 }}>
            {isLoading
              ? 'Loading…'
              : latest
                ? `Last logged ${formatDateTime(latest.observedAt)}`
                : 'No readings logged yet.'}
          </p>
        </div>
        <button className="btn btn-secondary btn-sm" onClick={() => setOpen((v) => !v)}>
          {open ? 'Cancel' : 'Log reading'}
        </button>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(110px, 1fr))', gap: 12 }}>
        <Reading label="Wind" value={latest?.windSpeedKnots} unit="kt" />
        <Reading label="Wave height" value={latest?.waveHeightMetres} unit="m" />
        <Reading label="Visibility" value={latest?.visibilityKm} unit="km" />
        <div>
          <div style={{ fontSize: '0.72rem', textTransform: 'uppercase', letterSpacing: '0.07em', color: 'var(--color-text-muted)' }}>
            Sea state
          </div>
          <div style={{ fontSize: '1.1rem', fontWeight: 700 }}>
            {latest?.seaStateCode === null || latest?.seaStateCode === undefined
              ? '—'
              : (SEA_STATES[latest.seaStateCode] ?? String(latest.seaStateCode))}
          </div>
        </div>
      </div>

      {latest?.note && (
        <p style={{ marginTop: 10, fontSize: '0.85rem', color: 'var(--color-text-secondary)' }}>{latest.note}</p>
      )}

      {open && (
        <div style={{ marginTop: 14, paddingTop: 14, borderTop: '1px solid var(--color-border)', display: 'grid', gap: 8 }}>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))', gap: 8 }}>
            <div className="field">
              <label>Wind (knots)</label>
              <input className="input" type="number" value={form.wind}
                onChange={(e) => setForm({ ...form, wind: e.target.value })} />
            </div>
            <div className="field">
              <label>Wave height (m)</label>
              <input className="input" type="number" step="0.1" value={form.wave}
                onChange={(e) => setForm({ ...form, wave: e.target.value })} />
            </div>
            <div className="field">
              <label>Visibility (km)</label>
              <input className="input" type="number" step="0.1" value={form.visibility}
                onChange={(e) => setForm({ ...form, visibility: e.target.value })} />
            </div>
            <div className="field">
              <label>Sea state</label>
              <select className="input" value={form.seaState}
                onChange={(e) => setForm({ ...form, seaState: e.target.value })}>
                <option value="">Not recorded</option>
                {SEA_STATES.map((label, code) => (
                  <option key={code} value={code}>{label}</option>
                ))}
              </select>
            </div>
          </div>
          <div className="field">
            <label>Note</label>
            <input className="input" placeholder="e.g. swell building from the south-west"
              value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} />
          </div>
          <div>
            <button className="btn btn-primary btn-sm" onClick={submit} disabled={saving}>
              {saving ? 'Saving…' : 'Save reading'}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
