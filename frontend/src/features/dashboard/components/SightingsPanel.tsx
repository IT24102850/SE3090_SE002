import { useState } from 'react';
import {
  useGetSightingAnalyticsQuery,
  useGetSightingVocabularyQuery,
  useLogSightingMutation,
} from '../../../api/bookingApi';
import Modal from '../../../shared/components/Modal';
import { apiErrorMessage, useToast } from '../../../shared/components/Toast';
import HorizontalBarChart from '../../booking/HorizontalBarChart';
import type { DepartureSummary } from '../../booking/types';

/* Sighting analytics and the log-a-sighting form.
 *
 * Not whale-specific: the species vocabulary comes from the backend enum,
 * which spans marine and land wildlife, so the identical panel serves a
 * safari operator logging leopards. */

/** Turns "BottlenoseDolphin" into "Bottlenose dolphin". */
function humanise(species: string): string {
  const spaced = species.replace(/([a-z])([A-Z])/g, '$1 $2');
  return spaced.charAt(0).toUpperCase() + spaced.slice(1).toLowerCase();
}

export function LogSightingModal({
  departure,
  onClose,
}: {
  departure: DepartureSummary;
  onClose: () => void;
}) {
  const { data: vocabulary } = useGetSightingVocabularyQuery();
  const [logSighting, { isLoading }] = useLogSightingMutation();
  const [form, setForm] = useState({ species: '', count: '', behaviour: '', notes: '' });
  const toast = useToast();

  const submit = async () => {
    if (!form.species) {
      toast.show('Pick a species.', 'error');
      return;
    }
    try {
      await logSighting({
        departureId: departure.id,
        species: form.species,
        // Blank stays null: an unknown pod size is not a pod of zero.
        count: form.count.trim() === '' ? undefined : Number(form.count),
        behaviour: form.behaviour || undefined,
        notes: form.notes.trim() || undefined,
      }).unwrap();
      toast.show('Sighting logged.', 'success');
      onClose();
    } catch (error) {
      toast.show(apiErrorMessage(error, 'Could not log the sighting.'), 'error');
    }
  };

  return (
    <Modal
      title={`Log a sighting — ${departure.vesselName}`}
      onClose={onClose}
      footer={
        <>
          <button className="btn btn-ghost" onClick={onClose}>Cancel</button>
          <button className="btn btn-primary" onClick={submit} disabled={isLoading}>
            {isLoading ? 'Saving…' : 'Log sighting'}
          </button>
        </>
      }
    >
      <div style={{ display: 'grid', gap: 10 }}>
        <div className="field">
          <label>Species</label>
          <select className="input" value={form.species}
            onChange={(e) => setForm({ ...form, species: e.target.value })}>
            <option value="">Select…</option>
            {(vocabulary?.species ?? []).map((s) => (
              <option key={s} value={s}>{humanise(s)}</option>
            ))}
          </select>
        </div>
        <div className="field">
          <label>How many (leave blank if unknown)</label>
          <input className="input" type="number" min={1} value={form.count}
            onChange={(e) => setForm({ ...form, count: e.target.value })} />
        </div>
        <div className="field">
          <label>Behaviour</label>
          <select className="input" value={form.behaviour}
            onChange={(e) => setForm({ ...form, behaviour: e.target.value })}>
            <option value="">Not recorded</option>
            {(vocabulary?.behaviours ?? []).map((b) => (
              <option key={b} value={b}>{humanise(b)}</option>
            ))}
          </select>
        </div>
        <div className="field">
          <label>Notes</label>
          <textarea className="input" rows={3} value={form.notes}
            onChange={(e) => setForm({ ...form, notes: e.target.value })} />
        </div>
      </div>
    </Modal>
  );
}

export default function SightingsPanel({ from, to }: { from?: string; to?: string }) {
  const [species, setSpecies] = useState('');
  const { data: vocabulary } = useGetSightingVocabularyQuery();
  const { data, isLoading } = useGetSightingAnalyticsQuery({ from, to, species: species || undefined });

  const frequency = (data?.speciesFrequency ?? []).slice(0, 8).map((row) => ({
    label: humanise(row.species),
    value: row.sightings,
    displayValue: `${row.sightings} (${row.individuals} seen)`,
    color: 'var(--color-primary)',
  }));

  // Only months where something actually sailed are drawn; a month with no
  // departures has no success rate to report, and plotting it at 0% would
  // read as a month of failed searches.
  const monthly = (data?.monthly ?? []).filter((m) => m.departures > 0);

  return (
    <div className="card chart-card" style={{ padding: 16 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 12, flexWrap: 'wrap' }}>
        <div>
          <p className="chart-title" style={{ margin: 0 }}>Sightings</p>
          <p className="chart-subtitle" style={{ margin: 0 }}>
            {isLoading
              ? 'Loading…'
              : `${data?.departuresWithSighting ?? 0} of ${data?.departuresSailed ?? 0} departures that sailed had a sighting`}
          </p>
        </div>
        <select className="input" style={{ maxWidth: 220 }} value={species}
          onChange={(e) => setSpecies(e.target.value)}>
          <option value="">All species</option>
          {(vocabulary?.species ?? []).map((s) => (
            <option key={s} value={s}>{humanise(s)}</option>
          ))}
        </select>
      </div>

      <div className="stat-grid" style={{ marginTop: 12 }}>
        <div className="stat-tile">
          <div className="stat-tile-label">Success rate</div>
          <div className="stat-tile-value" style={{ color: 'var(--color-good)' }}>
            {isLoading ? '…' : `${(data?.successRate ?? 0).toFixed(1)}%`}
          </div>
          <div className="stat-tile-sub">
            {species ? `${humanise(species)} only` : 'any species'}
          </div>
        </div>
        <div className="stat-tile">
          <div className="stat-tile-label">Total sightings</div>
          <div className="stat-tile-value">{data?.totalSightings ?? 0}</div>
        </div>
        <div className="stat-tile">
          <div className="stat-tile-label">Animals seen</div>
          <div className="stat-tile-value">{data?.totalIndividuals ?? 0}</div>
          <div className="stat-tile-sub">where the count was recorded</div>
        </div>
      </div>

      <div style={{ marginTop: 16 }}>
        <p className="chart-subtitle">Species frequency</p>
        {frequency.length === 0 ? (
          <p style={{ color: 'var(--color-text-muted)', fontSize: '0.85rem' }}>
            No sightings logged in this range yet.
          </p>
        ) : (
          <HorizontalBarChart data={frequency} />
        )}
      </div>

      {monthly.length > 0 && (
        <div style={{ marginTop: 16 }}>
          <p className="chart-subtitle">Monthly success rate</p>
          <div style={{ display: 'flex', gap: 6, alignItems: 'flex-end', overflowX: 'auto', paddingBottom: 4 }}>
            {monthly.map((m) => (
              <div key={m.month} style={{ minWidth: 54, textAlign: 'center' }}>
                <div
                  title={`${m.label}: ${m.departuresWithSighting} of ${m.departures} departures`}
                  style={{
                    height: 80,
                    display: 'flex',
                    alignItems: 'flex-end',
                    background: 'var(--color-neutral-soft)',
                    borderRadius: 4,
                    overflow: 'hidden',
                  }}
                >
                  <div
                    style={{
                      width: '100%',
                      height: `${Math.max(m.successRate, 2)}%`,
                      // Heat rather than one flat colour: a poor month should
                      // be visibly different, not just shorter.
                      background: m.successRate >= 75
                        ? 'var(--color-good)'
                        : m.successRate >= 40
                          ? 'var(--color-warning)'
                          : 'var(--color-critical)',
                    }}
                  />
                </div>
                <div style={{ fontSize: '0.68rem', color: 'var(--color-text-muted)', marginTop: 4 }}>
                  {m.label.split(' ')[0]}
                </div>
                <div style={{ fontSize: '0.68rem', color: 'var(--color-text-secondary)' }}>
                  {m.successRate.toFixed(0)}%
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
