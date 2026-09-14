import { useState } from 'react';
import {
  useSetDepartureStatusMutation,
  useSetSafetyChecklistMutation,
} from '../../../api/bookingApi';
import { useToast } from '../../../shared/components/Toast';
import { formatTime } from '../../../shared/dateUtils';
import {
  DEPARTURE_STATUS_COLORS,
  parseCrew,
  parseSafetyChecklist,
  type DepartureStatus,
  type DepartureSummary,
} from '../../booking/types';

/* The departure operations board: one card per sailing, with the one-click
 * actions an operator needs between the office and the jetty.
 *
 * Status transitions and the safety checklist live here rather than behind
 * a modal because both are things a manager does while looking at the
 * board, often on a phone at the harbour. */

/** The next status a card can move to, and what to call the button.
 *  CancelledWeather is deliberately absent: it has its own action, because
 *  it also has to move every booking and notify every guest. */
const NEXT_ACTIONS: Partial<Record<DepartureStatus, { status: DepartureStatus; label: string }[]>> = {
  Scheduled: [{ status: 'Boarding', label: 'Start boarding' }],
  Boarding: [
    { status: 'AtSea', label: 'Mark at sea' },
    { status: 'Scheduled', label: 'Back to scheduled' },
  ],
  AtSea: [{ status: 'Returned', label: 'Mark returned' }],
};

function OccupancyBar({ departure }: { departure: DepartureSummary }) {
  const pct = Math.min(departure.occupancyPercent, 100);
  const color = departure.nearCapacity ? 'var(--color-warning)' : 'var(--color-good)';
  return (
    <div>
      <div
        style={{
          height: 6,
          borderRadius: 3,
          background: 'var(--color-neutral-soft)',
          overflow: 'hidden',
        }}
      >
        <div style={{ width: `${pct}%`, height: '100%', background: color }} />
      </div>
      <div style={{ fontSize: '0.78rem', color: 'var(--color-text-muted)', marginTop: 4 }}>
        {departure.paxBooked} / {departure.capacity || '—'} pax
        {departure.capacity > 0 && ` · ${departure.seatsRemaining} seats left`}
        {departure.nearCapacity && ' · nearly full'}
      </div>
    </div>
  );
}

function SafetyChecklistEditor({ departure }: { departure: DepartureSummary }) {
  const checklist = parseSafetyChecklist(departure.safetyChecklist);
  const [save, { isLoading }] = useSetSafetyChecklistMutation();
  const toast = useToast();

  const items: { key: keyof typeof checklist; label: string }[] = [
    { key: 'jacketsCounted', label: 'Life jackets counted' },
    { key: 'briefingDone', label: 'Safety briefing done' },
    { key: 'manifestClosed', label: 'Manifest closed' },
    { key: 'weatherChecked', label: 'Weather checked' },
  ];

  const toggle = async (key: keyof typeof checklist) => {
    const next = {
      jacketsCounted: !!checklist.jacketsCounted,
      briefingDone: !!checklist.briefingDone,
      manifestClosed: !!checklist.manifestClosed,
      weatherChecked: !!checklist.weatherChecked,
      [key]: !checklist[key],
    };
    try {
      await save({ id: departure.id, ...next }).unwrap();
    } catch {
      toast.show('Could not save the safety checklist.', 'error');
    }
  };

  return (
    <div style={{ display: 'grid', gap: 4 }}>
      {items.map((item) => (
        <label key={item.key} style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: '0.8rem' }}>
          <input
            type="checkbox"
            checked={!!checklist[item.key]}
            disabled={isLoading}
            onChange={() => toggle(item.key)}
          />
          {item.label}
        </label>
      ))}
    </div>
  );
}

export default function DepartureBoard({
  departures,
  loading,
  isAdmin,
  onOpenManifest,
  onLogSighting,
  onCancelWeather,
  emptyMessage,
}: {
  departures: DepartureSummary[];
  loading: boolean;
  isAdmin: boolean;
  onOpenManifest: (departure: DepartureSummary) => void;
  onLogSighting: (departure: DepartureSummary) => void;
  onCancelWeather: (departure: DepartureSummary) => void;
  emptyMessage: string;
}) {
  const [setStatus] = useSetDepartureStatusMutation();
  const [expanded, setExpanded] = useState<string | null>(null);
  const toast = useToast();

  const move = async (departure: DepartureSummary, status: DepartureStatus) => {
    try {
      await setStatus({ id: departure.id, status }).unwrap();
      toast.show(`${departure.vesselName} marked ${DEPARTURE_STATUS_COLORS[status].label.toLowerCase()}.`, 'success');
    } catch (error) {
      // The safety-checklist gate comes back as a 400 with requiresOverride.
      // An Admin gets offered the override; anyone else is told to finish
      // the checklist, because the gate exists for a reason.
      const data = (error as { data?: { message?: string; requiresOverride?: boolean } })?.data;
      if (data?.requiresOverride && isAdmin) {
        if (window.confirm(`${data.message}\n\nOverride and mark this departure at sea anyway?`)) {
          try {
            await setStatus({ id: departure.id, status, overrideSafetyChecklist: true }).unwrap();
            toast.show('Departure marked at sea with a safety-checklist override.', 'success');
            return;
          } catch {
            toast.show('Could not update the departure.', 'error');
            return;
          }
        }
        return;
      }
      toast.show(data?.message ?? 'Could not update the departure.', 'error');
    }
  };

  if (loading) {
    return (
      <div className="card">
        <div className="loading-row"><span className="spinner spinner-dark" /> Loading departures…</div>
      </div>
    );
  }

  if (departures.length === 0) {
    return (
      <div className="card" style={{ padding: 24, color: 'var(--color-text-muted)' }}>{emptyMessage}</div>
    );
  }

  return (
    <div style={{ display: 'grid', gap: 12 }}>
      {departures.map((departure) => {
        const statusVisual = DEPARTURE_STATUS_COLORS[departure.status];
        const crew = parseCrew(departure.crew);
        const cancelled = departure.status === 'CancelledWeather' || departure.status === 'CancelledOther';
        const isOpen = expanded === departure.id;

        return (
          <div className="card" key={departure.id} style={{ padding: 16 }}>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 16, alignItems: 'flex-start' }}>
              <div style={{ minWidth: 190, flex: '1 1 190px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                  <strong style={{ fontSize: '1rem' }}>{formatTime(departure.scheduledDeparture)}</strong>
                  <span
                    className="badge"
                    style={{ background: statusVisual.bg, color: '#0A0A0B', fontWeight: 700 }}
                  >
                    {statusVisual.label}
                  </span>
                </div>
                <div style={{ color: 'var(--color-text-secondary)', fontSize: '0.85rem' }}>
                  {departure.vesselName}
                  {departure.bookingTypeName && ` · ${departure.bookingTypeName}`}
                </div>
                <div style={{ color: 'var(--color-text-muted)', fontSize: '0.78rem' }}>
                  {departure.durationMinutes} min · returns {formatTime(departure.scheduledReturn)}
                </div>
                {crew.length > 0 && (
                  <div style={{ color: 'var(--color-text-muted)', fontSize: '0.78rem', marginTop: 4 }}>
                    Crew: {crew.map((c) => (c.role ? `${c.name} (${c.role})` : c.name)).join(', ')}
                  </div>
                )}
                {cancelled && departure.cancellationReason && (
                  <div style={{ color: 'var(--color-warning)', fontSize: '0.78rem', marginTop: 4 }}>
                    {departure.cancellationReason}
                  </div>
                )}
              </div>

              <div style={{ minWidth: 180, flex: '1 1 180px' }}>
                <OccupancyBar departure={departure} />
                <div style={{ fontSize: '0.78rem', color: 'var(--color-text-muted)', marginTop: 6 }}>
                  {Object.entries(departure.ticketMix).length > 0
                    ? Object.entries(departure.ticketMix).map(([type, qty]) => `${qty} ${type.toLowerCase()}`).join(' · ')
                    : 'No ticket breakdown recorded'}
                </div>
              </div>

              <div style={{ minWidth: 150, flex: '1 1 150px', fontSize: '0.8rem' }}>
                <div>
                  Waivers:{' '}
                  <strong style={{ color: departure.waiverCompletionPercent >= 100 ? 'var(--color-good)' : 'var(--color-warning)' }}>
                    {departure.waiverCompletionPercent.toFixed(0)}%
                  </strong>
                </div>
                <div>Checked in: <strong>{departure.checkedInCount}</strong> / {departure.bookingCount}</div>
                <div>Sightings: <strong>{departure.sightingCount}</strong></div>
                {departure.latestWeather && (
                  <div style={{ color: 'var(--color-text-muted)', marginTop: 4 }}>
                    {departure.latestWeather.windSpeedKnots ?? '—'} kt ·{' '}
                    {departure.latestWeather.waveHeightMetres ?? '—'} m
                  </div>
                )}
              </div>

              <div style={{ display: 'flex', flexDirection: 'column', gap: 6, minWidth: 170 }}>
                <button className="btn btn-secondary btn-sm" onClick={() => onOpenManifest(departure)}>
                  Open manifest
                </button>
                {!cancelled && (NEXT_ACTIONS[departure.status] ?? []).map((action) => (
                  <button
                    key={action.status}
                    className="btn btn-primary btn-sm"
                    onClick={() => move(departure, action.status)}
                  >
                    {action.label}
                  </button>
                ))}
                {!cancelled && (
                  <>
                    <button className="btn btn-secondary btn-sm" onClick={() => onLogSighting(departure)}>
                      Log sighting
                    </button>
                    <button className="btn btn-danger btn-sm" onClick={() => onCancelWeather(departure)}>
                      Cancel — weather
                    </button>
                  </>
                )}
                <button
                  className="btn btn-ghost btn-sm"
                  onClick={() => setExpanded(isOpen ? null : departure.id)}
                >
                  {`${isOpen ? 'Hide' : 'Safety'} checklist${!departure.safetyChecklistComplete && !cancelled ? ' ⚠' : ''}`}
                </button>
              </div>
            </div>

            {isOpen && (
              <div style={{ marginTop: 12, paddingTop: 12, borderTop: '1px solid var(--color-border)' }}>
                <p style={{ fontSize: '0.8rem', color: 'var(--color-text-secondary)', margin: '0 0 8px' }}>
                  Pre-departure safety checklist — must be complete before this departure can be marked at sea.
                </p>
                <SafetyChecklistEditor departure={departure} />
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}
