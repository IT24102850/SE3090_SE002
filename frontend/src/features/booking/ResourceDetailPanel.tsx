import { useEffect, useState } from 'react';
import { useGetAvailabilityGridQuery, useGetResourceScheduleQuery, useSetResourceScheduleMutation } from '../../api/bookingApi';
import { useToast, apiErrorMessage } from '../../shared/components/Toast';
import { addDays, toISODate } from '../../shared/dateUtils';
import type { DaySchedule, Resource } from './types';

const DAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

function defaultWeek(): DaySchedule[] {
  return Array.from({ length: 7 }, (_, dayOfWeek) => ({
    dayOfWeek,
    startTime: '09:00:00',
    endTime: '17:00:00',
    isAvailable: dayOfWeek !== 0 && dayOfWeek !== 6,
  }));
}

function utilizationTone(pct: number, isOpen: boolean): string {
  if (!isOpen) return 'var(--color-border-strong)';
  if (pct < 40) return 'var(--color-good)';
  if (pct < 80) return 'var(--color-warning)';
  return 'var(--color-critical)';
}

export default function ResourceDetailPanel({ resource, onClose }: { resource: Resource; onClose: () => void }) {
  const { show } = useToast();
  const { data: scheduleData, isLoading: scheduleLoading } = useGetResourceScheduleQuery(resource.id);
  const [setSchedule, { isLoading: saving }] = useSetResourceScheduleMutation();

  const [days, setDays] = useState<DaySchedule[]>(defaultWeek());

  useEffect(() => {
    if (scheduleData && scheduleData.length > 0) {
      const byDay = new Map(scheduleData.map((d) => [d.dayOfWeek, d]));
      setDays(defaultWeek().map((d) => byDay.get(d.dayOfWeek) ?? d));
    }
  }, [scheduleData]);

  const from = toISODate(new Date());
  const to = toISODate(addDays(new Date(), 13));
  const { data: grid, isLoading: gridLoading } = useGetAvailabilityGridQuery({ id: resource.id, from, to });

  const updateDay = (idx: number, patch: Partial<DaySchedule>) => {
    setDays((prev) => prev.map((d, i) => (i === idx ? { ...d, ...patch } : d)));
  };

  const handleSave = async () => {
    try {
      await setSchedule({ id: resource.id, days }).unwrap();
      show('Schedule updated.', 'success');
    } catch (err) {
      show(apiErrorMessage(err, 'Could not save schedule.'), 'error');
    }
  };

  return (
    <div className="card card-pad" style={{ marginBottom: 24 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 16 }}>
        <div>
          <h3 style={{ margin: 0 }}>{resource.name}</h3>
          <p style={{ margin: '2px 0 0', color: 'var(--color-text-secondary)', fontSize: 13 }}>Weekly hours & 14-day availability</p>
        </div>
        <button className="btn btn-ghost btn-sm" onClick={onClose}>Close</button>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 24 }}>
        <div>
          <h4 style={{ fontSize: 13, textTransform: 'uppercase', letterSpacing: '0.03em', color: 'var(--color-text-secondary)', marginBottom: 10 }}>
            Weekly schedule
          </h4>
          {scheduleLoading ? (
            <div className="loading-row"><span className="spinner spinner-dark" /></div>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
              {days.map((d, idx) => (
                <div key={d.dayOfWeek} style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 13 }}>
                  <label style={{ display: 'flex', alignItems: 'center', gap: 6, width: 100 }}>
                    <input type="checkbox" checked={d.isAvailable} onChange={(e) => updateDay(idx, { isAvailable: e.target.checked })} />
                    {DAY_NAMES[d.dayOfWeek].slice(0, 3)}
                  </label>
                  <input
                    className="input" type="time" style={{ padding: '4px 8px' }}
                    value={d.startTime.slice(0, 5)}
                    disabled={!d.isAvailable}
                    onChange={(e) => updateDay(idx, { startTime: `${e.target.value}:00` })}
                  />
                  <span>–</span>
                  <input
                    className="input" type="time" style={{ padding: '4px 8px' }}
                    value={d.endTime.slice(0, 5)}
                    disabled={!d.isAvailable}
                    onChange={(e) => updateDay(idx, { endTime: `${e.target.value}:00` })}
                  />
                </div>
              ))}
              <button className="btn btn-primary btn-sm" style={{ marginTop: 8, alignSelf: 'flex-start' }} onClick={handleSave} disabled={saving}>
                {saving ? <span className="spinner" /> : 'Save schedule'}
              </button>
            </div>
          )}
        </div>

        <div>
          <h4 style={{ fontSize: 13, textTransform: 'uppercase', letterSpacing: '0.03em', color: 'var(--color-text-secondary)', marginBottom: 10 }}>
            Availability — next 14 days
          </h4>
          {gridLoading ? (
            <div className="loading-row"><span className="spinner spinner-dark" /></div>
          ) : (
            <>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 4 }}>
                {grid?.map((d) => (
                  <div
                    key={d.date}
                    title={d.isOpen ? `${d.date.slice(0, 10)}: ${d.utilizationPercent}% booked (${d.bookedHours}h of ${d.openHours}h)` : `${d.date.slice(0, 10)}: closed`}
                    style={{
                      aspectRatio: '1',
                      borderRadius: 6,
                      background: utilizationTone(d.utilizationPercent, d.isOpen),
                      opacity: d.isOpen ? 0.85 : 0.35,
                      display: 'flex', alignItems: 'center', justifyContent: 'center',
                      color: '#fff', fontSize: 11, fontWeight: 700,
                    }}
                  >
                    {new Date(d.date).getDate()}
                  </div>
                ))}
              </div>
              <div className="chart-legend" style={{ marginTop: 12 }}>
                <div className="chart-legend-item"><span className="chart-legend-swatch" style={{ background: 'var(--color-good)' }} /> Low use</div>
                <div className="chart-legend-item"><span className="chart-legend-swatch" style={{ background: 'var(--color-warning)' }} /> Busy</div>
                <div className="chart-legend-item"><span className="chart-legend-swatch" style={{ background: 'var(--color-critical)' }} /> Nearly full</div>
                <div className="chart-legend-item"><span className="chart-legend-swatch" style={{ background: 'var(--color-border-strong)', opacity: 0.35 }} /> Closed</div>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
