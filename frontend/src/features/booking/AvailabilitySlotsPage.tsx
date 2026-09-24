import { useMemo, useState } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../store/store';
import {
  useDeleteAvailabilitySlotsMutation,
  useGenerateAvailabilitySlotsMutation,
  useGetAvailabilitySlotsQuery,
  useGetResourcesQuery,
} from '../../api/bookingApi';
import { apiErrorMessage, useToast } from '../../shared/components/Toast';
import { addDays, formatDayLabel, toISODate } from '../../shared/dateUtils';
import './reservations.css';
import './schedule.css';

/* Availability Slots — the capacity ledger (spec 2.3: AvailabilitySlots).
 *
 * Availability used to be computed on the fly and nowhere else. That is
 * fine until a business wants to *hold* it: publish next month, withdraw a
 * wet Tuesday, see how much of what it opened actually sold. A materialised
 * slot is a row the business owns, and this page is where it owns it.
 *
 * A resource with no generated slots keeps working exactly as before, so
 * this is opt-in per resource — which is why the page leads with the
 * resource picker rather than assuming. */

const SLOT_SIZES = [15, 30, 45, 60, 90, 120];

export default function AvailabilitySlotsPage() {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';
  const { show } = useToast();

  const { data: resourcesData } = useGetResourcesQuery({ tenantId, pageSize: 200 }, { skip: !tenantId });
  const resources = useMemo(() => resourcesData?.items ?? [], [resourcesData]);

  const [resourceId, setResourceId] = useState('');
  const [from, setFrom] = useState(() => toISODate(new Date()));
  const [to, setTo] = useState(() => toISODate(addDays(new Date(), 13)));
  const [slotMinutes, setSlotMinutes] = useState(60);

  const activeResource = resources.find((r) => r.id === resourceId) ?? resources[0];
  const activeId = activeResource?.id ?? '';

  const { data, isLoading, isFetching } = useGetAvailabilitySlotsQuery(
    { id: activeId, from, to },
    { skip: !activeId },
  );
  const [generate, { isLoading: generating }] = useGenerateAvailabilitySlotsMutation();
  const [clear, { isLoading: clearing }] = useDeleteAvailabilitySlotsMutation();

  const handleGenerate = async () => {
    try {
      const result = await generate({ id: activeId, from, to, slotMinutes }).unwrap();
      // Re-running over a generated range is a no-op by design, so say which
      // of the two happened rather than always claiming success.
      show(
        result.created === 0
          ? `Nothing new — all ${result.skipped} slots in that range already exist.`
          : `Published ${result.created} slot${result.created === 1 ? '' : 's'} across ${result.days} day${result.days === 1 ? '' : 's'}.`,
        result.created === 0 ? 'info' : 'success',
      );
    } catch (err) {
      show(apiErrorMessage(err, 'Could not publish these slots.'), 'error');
    }
  };

  const handleClear = async () => {
    if (!window.confirm('Withdraw the unbooked slots in this range? Booked ones are kept.')) return;
    try {
      const result = await clear({ id: activeId, from, to }).unwrap();
      show(
        result.keptBecauseBooked > 0
          ? `Withdrew ${result.removed}; kept ${result.keptBecauseBooked} that are booked.`
          : `Withdrew ${result.removed} slot${result.removed === 1 ? '' : 's'}.`,
        'success',
      );
    } catch (err) {
      show(apiErrorMessage(err, 'Could not withdraw these slots.'), 'error');
    }
  };

  const days = data?.days ?? [];
  const busiest = days.reduce((max, d) => Math.max(max, d.total), 0);

  return (
    <div>
      <div className="page-header">
        <div>
          <h1 className="page-title">Availability Slots</h1>
          <p className="page-subtitle">Publish the capacity you want to sell, and see how much of it went.</p>
        </div>
      </div>

      <div className="rsv">
        <div className="rsv-main">
          <div className="rsv-kpis">
            <div className="rsv-kpi rsv-kpi--blue">
              <div>
                <div className="rsv-kpi-value">{data?.total ?? (isLoading ? '…' : 0)}</div>
                <div className="rsv-kpi-label">Slots published</div>
                <div className="rsv-kpi-sub">{days.length} day{days.length === 1 ? '' : 's'} in range</div>
              </div>
              <div className="rsv-kpi-icon" aria-hidden="true">🗓️</div>
            </div>
            <div className="rsv-kpi rsv-kpi--green">
              <div>
                <div className="rsv-kpi-value">{data?.booked ?? 0}</div>
                <div className="rsv-kpi-label">Sold</div>
                <div className="rsv-kpi-sub">held by a booking</div>
              </div>
              <div className="rsv-kpi-icon" aria-hidden="true">✅</div>
            </div>
            <div className="rsv-kpi rsv-kpi--amber">
              <div>
                <div className="rsv-kpi-value">{data?.free ?? 0}</div>
                <div className="rsv-kpi-label">Still open</div>
                <div className="rsv-kpi-sub">available to book</div>
              </div>
              <div className="rsv-kpi-icon" aria-hidden="true">🕳️</div>
            </div>
            <div className="rsv-kpi rsv-kpi--pink">
              <div>
                <div className="rsv-kpi-value">{data?.utilisationPercent ?? 0}%</div>
                <div className="rsv-kpi-label">Utilisation</div>
                <div className="rsv-kpi-sub">of what you published</div>
              </div>
              <div className="rsv-kpi-icon" aria-hidden="true">📈</div>
            </div>
          </div>

          <section className="rsv-card">
            <div className="rsv-toolbar">
              <select className="input" value={activeId} onChange={(e) => setResourceId(e.target.value)}>
                {resources.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
              </select>
              <input className="input" type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
              <span style={{ color: 'var(--color-text-muted)' }}>to</span>
              <input className="input" type="date" value={to} onChange={(e) => setTo(e.target.value)} />
              <select className="input" value={slotMinutes} onChange={(e) => setSlotMinutes(Number(e.target.value))}>
                {SLOT_SIZES.map((m) => <option key={m} value={m}>{m} min slots</option>)}
              </select>
              <button className="btn btn-primary btn-sm" disabled={!activeId || generating} onClick={handleGenerate}>
                {generating ? 'Publishing…' : 'Publish slots'}
              </button>
              <button className="btn btn-ghost btn-sm" disabled={!activeId || clearing} onClick={handleClear}>
                Withdraw unbooked
              </button>
            </div>

            <div style={{ padding: 18 }}>
              {!activeId ? (
                <div className="rsv-empty"><b>No resources yet</b>Add a room, table or vehicle first.</div>
              ) : isLoading || isFetching ? (
                <div className="loading-row" style={{ padding: 30 }}><span className="spinner spinner-dark" /> Loading the ledger…</div>
              ) : days.length === 0 ? (
                <div className="rsv-empty">
                  <b>Nothing published for this range</b>
                  {activeResource?.name} is still on computed availability. Publish slots above to hold capacity you can
                  withdraw, price and measure.
                </div>
              ) : (
                <div style={{ display: 'grid', gap: 12 }}>
                  {days.map((day) => (
                    <div key={day.date}>
                      <div className="sch-rank-head" style={{ marginBottom: 6 }}>
                        <span className="sch-rank-name">{formatDayLabel(new Date(day.date))}</span>
                        <span className="sch-rank-value">{day.booked}/{day.total} sold</span>
                      </div>
                      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
                        {day.slots.map((slot) => (
                          <span
                            key={slot.id}
                            title={slot.isBooked ? 'Booked' : 'Open'}
                            style={{
                              padding: '5px 10px',
                              borderRadius: 8,
                              fontSize: '.72rem',
                              fontWeight: 700,
                              /* Sold and open must be told apart without
                                 reading the tooltip. */
                              color: slot.isBooked ? '#fff' : 'var(--color-text-secondary)',
                              background: slot.isBooked ? 'var(--color-primary)' : 'var(--color-surface-muted)',
                              border: '1px solid var(--color-border)',
                            }}
                          >
                            {slot.startTime.slice(0, 5)}
                          </span>
                        ))}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </section>
        </div>

        <aside className="rsv-rail">
          <div className="rsv-card">
            <div className="rsv-card-head">
              <div>
                <h3 className="rsv-card-title">Busiest days</h3>
                <p className="rsv-card-sub">Sold against published</p>
              </div>
            </div>
            <div className="sch-rank">
              {days.length === 0 ? (
                <div className="rsv-up-empty">Nothing published yet.</div>
              ) : (
                [...days]
                  .sort((a, b) => b.booked - a.booked)
                  .slice(0, 8)
                  .map((day) => (
                    <div className="sch-rank-row" key={day.date}>
                      <div className="sch-rank-head">
                        <span className="sch-rank-name">{formatDayLabel(new Date(day.date))}</span>
                        <span className="sch-rank-value">{day.total === 0 ? 0 : Math.round((day.booked / day.total) * 100)}%</span>
                      </div>
                      <div className="sch-rank-track">
                        <div className="sch-rank-fill" style={{ width: `${busiest === 0 ? 0 : (day.total / busiest) * 100}%` }} />
                      </div>
                      <div className="sch-rank-sub">{day.booked} sold of {day.total} published</div>
                    </div>
                  ))
              )}
            </div>
          </div>

          <div className="rsv-card">
            <div className="rsv-card-head">
              <div>
                <h3 className="rsv-card-title">How this works</h3>
              </div>
            </div>
            <div className="sch-rank">
              <p style={{ margin: 0, fontSize: '.78rem', color: 'var(--color-text-secondary)', lineHeight: 1.6 }}>
                Slots come from the resource&rsquo;s weekly hours, so publishing never invents time the business is
                closed. Publishing twice over the same range changes nothing. A booking takes its slots and giving the
                booking up hands them straight back, so utilisation is always what actually sold.
              </p>
            </div>
          </div>
        </aside>
      </div>
    </div>
  );
}
