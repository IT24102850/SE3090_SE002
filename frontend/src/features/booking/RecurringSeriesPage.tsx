import { useSelector } from 'react-redux';
import { RootState } from '../../store/store';
import { useCancelRecurringSeriesMutation, useGetRecurringSeriesQuery } from '../../api/bookingApi';
import { apiErrorMessage, useToast } from '../../shared/components/Toast';
import { formatDayLabel, formatTime } from '../../shared/dateUtils';
import './reservations.css';
import './schedule.css';

/* Recurring Series (spec 2.3: RecurringPatterns).
 *
 * The pattern row has always been written when a series is created, but
 * nothing could read it back — so a weekly class became twelve unrelated
 * bookings the moment it was made, and calling it off meant cancelling
 * twelve things by hand.
 *
 * Cancelling here stops only the *future* occurrences. Past ones keep their
 * history, because a class that ran is a class that ran. */

const DAY_NAMES = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

export default function RecurringSeriesPage() {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';
  const { show } = useToast();

  const { data, isLoading } = useGetRecurringSeriesQuery({ tenantId }, { skip: !tenantId });
  const [cancelSeries, { isLoading: cancelling }] = useCancelRecurringSeriesMutation();

  const items = data?.items ?? [];
  const active = items.filter((s) => s.isActive);
  const upcoming = active.reduce((sum, s) => sum + s.remaining, 0);
  const occurrences = items.reduce((sum, s) => sum + s.total, 0);

  const handleCancel = async (patternId: string, label: string, remaining: number) => {
    if (remaining === 0) {
      show('Nothing left to cancel — every occurrence is in the past.', 'info');
      return;
    }
    if (!window.confirm(`Cancel the ${remaining} future occurrence${remaining === 1 ? '' : 's'} of "${label}"? Past ones are kept.`)) return;
    try {
      const result = await cancelSeries(patternId).unwrap();
      show(`Cancelled ${result.cancelled} future occurrence${result.cancelled === 1 ? '' : 's'}.`, 'success');
    } catch (err) {
      show(apiErrorMessage(err, 'Could not cancel this series.'), 'error');
    }
  };

  return (
    <div>
      <div className="page-header">
        <div>
          <h1 className="page-title">Recurring Series</h1>
          <p className="page-subtitle">Repeating bookings as one thing you can see and call off, not a pile of copies.</p>
        </div>
      </div>

      <div className="rsv">
        <div className="rsv-main">
          <div className="rsv-kpis">
            <div className="rsv-kpi rsv-kpi--blue">
              <div>
                <div className="rsv-kpi-value">{active.length}</div>
                <div className="rsv-kpi-label">Running series</div>
                <div className="rsv-kpi-sub">{items.length - active.length} finished</div>
              </div>
              <div className="rsv-kpi-icon" aria-hidden="true">🔁</div>
            </div>
            <div className="rsv-kpi rsv-kpi--green">
              <div>
                <div className="rsv-kpi-value">{upcoming}</div>
                <div className="rsv-kpi-label">Occurrences ahead</div>
                <div className="rsv-kpi-sub">still to happen</div>
              </div>
              <div className="rsv-kpi-icon" aria-hidden="true">📆</div>
            </div>
            <div className="rsv-kpi rsv-kpi--amber">
              <div>
                <div className="rsv-kpi-value">{occurrences}</div>
                <div className="rsv-kpi-label">Bookings created</div>
                <div className="rsv-kpi-sub">across every series</div>
              </div>
              <div className="rsv-kpi-icon" aria-hidden="true">🧾</div>
            </div>
            <div className="rsv-kpi rsv-kpi--pink">
              <div>
                <div className="rsv-kpi-value">{items.reduce((sum, s) => sum + s.cancelled, 0)}</div>
                <div className="rsv-kpi-label">Cancelled</div>
                <div className="rsv-kpi-sub">dropped occurrences</div>
              </div>
              <div className="rsv-kpi-icon" aria-hidden="true">🚫</div>
            </div>
          </div>

          <section className="rsv-card">
            <div className="rsv-card-head">
              <div>
                <h3 className="rsv-card-title">Every series</h3>
                <p className="rsv-card-sub">Running ones first</p>
              </div>
            </div>

            <div style={{ padding: 18 }}>
              {isLoading ? (
                <div className="loading-row" style={{ padding: 30 }}><span className="spinner spinner-dark" /> Loading series…</div>
              ) : items.length === 0 ? (
                <div className="rsv-empty">
                  <b>No recurring bookings yet</b>
                  Create one from the Booking Manager and it will appear here as a single series.
                </div>
              ) : (
                <div className="svc-grid">
                  {[...items]
                    .sort((a, b) => Number(b.isActive) - Number(a.isActive) || b.remaining - a.remaining)
                    .map((series) => {
                      const label = series.title || series.bookingTypeName || 'Recurring booking';
                      const accent = series.colorHex || '#2563EB';
                      return (
                        <article
                          key={series.patternId}
                          className={`svc${series.isActive ? '' : ' is-retired'}`}
                          style={{ ['--svc' as string]: accent }}
                        >
                          <div className="svc-top">
                            <div className="svc-head">
                              <div className="svc-badge">🔁</div>
                              <div style={{ minWidth: 0 }}>
                                <h3 className="svc-name">{label}</h3>
                                <p className="svc-desc">
                                  {series.resourceName ?? 'Unassigned'} · {formatTime(series.startTime)}
                                </p>
                              </div>
                            </div>
                            <div className="svc-flags">
                              <span className="svc-flag">{series.frequency}</span>
                              {series.daysOfWeek?.length > 0 && (
                                <span className="svc-flag">
                                  {series.daysOfWeek.map((d) => DAY_NAMES[d] ?? d).join(' · ')}
                                </span>
                              )}
                              <span className={`svc-flag ${series.isActive ? 'is-good' : ''}`}>
                                {series.isActive ? 'Running' : 'Finished'}
                              </span>
                            </div>
                          </div>

                          <div className="svc-specs">
                            <div className="svc-spec"><b>{series.total}</b><span>Total</span></div>
                            <div className="svc-spec"><b>{series.remaining}</b><span>Ahead</span></div>
                            <div className="svc-spec"><b>{series.cancelled}</b><span>Cancelled</span></div>
                          </div>

                          <div className="svc-foot">
                            <span className="svc-usage">Until {formatDayLabel(new Date(series.endDate))}</span>
                            <div className="svc-actions">
                              <button
                                className="btn btn-danger btn-sm"
                                disabled={cancelling || series.remaining === 0}
                                onClick={() => handleCancel(series.patternId, label, series.remaining)}
                              >
                                Cancel remaining
                              </button>
                            </div>
                          </div>
                        </article>
                      );
                    })}
                </div>
              )}
            </div>
          </section>
        </div>

        <aside className="rsv-rail">
          <div className="rsv-card">
            <div className="rsv-card-head">
              <div>
                <h3 className="rsv-card-title">Biggest commitments</h3>
                <p className="rsv-card-sub">By occurrences still ahead</p>
              </div>
            </div>
            <div className="sch-rank">
              {active.length === 0 ? (
                <div className="rsv-up-empty">Nothing running.</div>
              ) : (
                [...active]
                  .sort((a, b) => b.remaining - a.remaining)
                  .slice(0, 8)
                  .map((series) => {
                    const max = Math.max(...active.map((s) => s.remaining), 1);
                    return (
                      <div className="sch-rank-row" key={series.patternId}>
                        <div className="sch-rank-head">
                          <span className="sch-rank-name">{series.title || series.bookingTypeName || 'Series'}</span>
                          <span className="sch-rank-value">{series.remaining}</span>
                        </div>
                        <div className="sch-rank-track">
                          <div
                            className="sch-rank-fill"
                            style={{ width: `${(series.remaining / max) * 100}%`, background: series.colorHex ?? undefined }}
                          />
                        </div>
                        <div className="sch-rank-sub">{series.resourceName ?? 'Unassigned'} · {series.frequency}</div>
                      </div>
                    );
                  })
              )}
            </div>
          </div>
        </aside>
      </div>
    </div>
  );
}
