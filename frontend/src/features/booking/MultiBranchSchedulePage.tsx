import { useMemo, useRef, useState } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../store/store';
import { useGetBookingsQuery, useGetBranchesQuery, useGetResourcesQuery } from '../../api/bookingApi';
import { addDays, buildMonthGrid, formatDayLabel, formatMonthYear, formatTime, isSameDay, startOfMonth, toISODate, WEEKDAY_LABELS } from '../../shared/dateUtils';
import { STATUS_COLORS } from './types';
import BookingDetailsModal from './BookingDetailsModal';
import type { Booking } from './types';
import './reservations.css';
import './schedule.css';

/* Multi-Branch Schedule — the manager's oversight board (spec 2.5).
 *
 * Rebuilt to the Reservations page's language: the same two-column frame, the
 * same gradient KPI strip, the same card shells, so the Scheduling section
 * reads as one product. The old page had a raw <input type="date">, unstyled
 * chevrons and a bare gantt with no summary; the question a multi-site
 * manager actually asks — where is the load, and where is the slack — was
 * left for them to work out by eye.
 *
 * Now the KPI strip answers it in a glance, each branch board carries its own
 * utilisation bar, the gantt has an hour grid and a live now-line, and
 * clashes are outlined in red on the board itself rather than hidden behind
 * whichever bar happened to paint last. */

const START_HOUR = 7;
const END_HOUR = 19;
const WINDOW_MINUTES = (END_HOUR - START_HOUR) * 60;
const HOURS = Array.from({ length: END_HOUR - START_HOUR }, (_, i) => START_HOUR + i);

const DROPPED = new Set(['Cancelled', 'Rejected', 'NoShow', 'WeatherCancelled']);
const DONE = new Set(['Completed']);

const hourLabel = (h: number) => `${h % 12 === 0 ? 12 : h % 12}${h < 12 ? 'am' : 'pm'}`;

export default function MultiBranchSchedulePage() {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';

  const [day, setDay] = useState(() => new Date());
  const [monthAnchor, setMonthAnchor] = useState(() => startOfMonth(new Date()));
  const [selectedBooking, setSelectedBooking] = useState<Booking | null>(null);
  const dateInput = useRef<HTMLInputElement>(null);

  const { data: branches } = useGetBranchesQuery({ tenantId }, { skip: !tenantId });
  const { data: resourcesData } = useGetResourcesQuery({ tenantId, pageSize: 200 }, { skip: !tenantId });
  const { data: dayData, isLoading } = useGetBookingsQuery(
    { tenantId, dateFrom: toISODate(day), dateTo: toISODate(addDays(day, 1)), pageSize: 500 },
    { skip: !tenantId },
  );
  /* A second, wider window purely for the calendar's density dots — the day
     board must not have to load a month to draw one day. */
  const { data: monthData } = useGetBookingsQuery(
    { tenantId, dateFrom: toISODate(addDays(monthAnchor, -7)), dateTo: toISODate(addDays(monthAnchor, 44)), pageSize: 1000 },
    { skip: !tenantId },
  );

  const resources = useMemo(() => resourcesData?.items ?? [], [resourcesData]);
  const bookings = useMemo(() => dayData?.items ?? [], [dayData]);
  const live = useMemo(() => bookings.filter((b) => !DROPPED.has(b.status)), [bookings]);

  const bookingsByResource = useMemo(() => {
    const map = new Map<string, Booking[]>();
    for (const b of live) {
      if (!map.has(b.resourceId)) map.set(b.resourceId, []);
      map.get(b.resourceId)!.push(b);
    }
    for (const list of map.values()) list.sort((a, b) => a.startTime.localeCompare(b.startTime));
    return map;
  }, [live]);

  /* Bookings that genuinely overlap on one resource. Flagged here rather
     than in the renderer so the count can also feed the KPI strip. */
  const clashing = useMemo(() => {
    const ids = new Set<string>();
    for (const list of bookingsByResource.values()) {
      for (let i = 0; i < list.length; i += 1) {
        for (let j = i + 1; j < list.length; j += 1) {
          if (list[j].startTime < list[i].endTime && list[i].startTime < list[j].endTime) {
            ids.add(list[i].id);
            ids.add(list[j].id);
          }
        }
      }
    }
    return ids;
  }, [bookingsByResource]);

  const branchName = (id?: string | null) => branches?.find((b) => b.id === id)?.name ?? 'Unassigned';

  const groups = useMemo(() => {
    const map = new Map<string, { key: string; name: string; resources: typeof resources }>();
    for (const r of resources) {
      const key = r.branchId ?? 'unassigned';
      if (!map.has(key)) map.set(key, { key, name: branchName(r.branchId), resources: [] });
      map.get(key)!.resources.push(r);
    }
    /* Busiest branch first: the comparison is the reason this page exists. */
    return Array.from(map.values()).sort((a, b) => countFor(b.resources) - countFor(a.resources));
    function countFor(rs: typeof resources) {
      return rs.reduce((sum, r) => sum + (bookingsByResource.get(r.id)?.length ?? 0), 0);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [resources, branches, bookingsByResource]);

  /* Minutes of the 07:00–19:00 window each branch has sold, against what its
     resources could sell — the one honest way to compare a two-room branch
     with a ten-room one. */
  const utilisationOf = (branchResources: typeof resources) => {
    const capacity = branchResources.length * WINDOW_MINUTES;
    if (capacity === 0) return 0;
    const booked = branchResources.reduce((sum, r) => {
      const list = bookingsByResource.get(r.id) ?? [];
      return sum + list.reduce((m, b) => m + minutesInWindow(b, day), 0);
    }, 0);
    return Math.min(100, Math.round((booked / capacity) * 100));
  };

  const totalHeads = live.reduce((sum, b) => sum + (b.attendeeCount ?? 1), 0);
  const busyBranches = groups.filter((g) => g.resources.some((r) => (bookingsByResource.get(r.id)?.length ?? 0) > 0));
  const overallUtilisation = resources.length === 0
    ? 0
    : Math.min(100, Math.round((live.reduce((m, b) => m + minutesInWindow(b, day), 0) / (resources.length * WINDOW_MINUTES)) * 100));

  const monthCounts = useMemo(() => {
    const counts = new Map<string, number>();
    for (const b of monthData?.items ?? []) {
      if (DROPPED.has(b.status)) continue;
      const key = toISODate(new Date(b.startTime));
      counts.set(key, (counts.get(key) ?? 0) + 1);
    }
    return counts;
  }, [monthData]);

  const monthDays = useMemo(() => buildMonthGrid(monthAnchor), [monthAnchor]);
  const today = new Date();

  const upcoming = useMemo(
    () => live.filter((b) => new Date(b.startTime) >= new Date()).sort((a, b) => a.startTime.localeCompare(b.startTime)).slice(0, 4),
    [live],
  );

  const pickDay = (next: Date) => {
    setDay(next);
    setMonthAnchor(startOfMonth(next));
  };

  return (
    <div>
      <div className="page-header">
        <div>
          <h1 className="page-title">Multi-Branch Schedule</h1>
          <p className="page-subtitle">Every resource across every branch, one day at a time.</p>
        </div>
        <div className="sch-daynav">
          <button className="sch-step" title="Previous day" onClick={() => pickDay(addDays(day, -1))}>‹</button>
          <button
            type="button"
            className="sch-daynav-date"
            style={{ position: 'relative' }}
            onClick={() => dateInput.current?.showPicker?.() ?? dateInput.current?.click()}
          >
            <strong>{formatDayLabel(day)}</strong>
            <span>{isSameDay(day, today) ? 'Today' : formatMonthYear(day)}</span>
            <input
              ref={dateInput}
              type="date"
              value={toISODate(day)}
              onChange={(e) => e.target.value && pickDay(new Date(`${e.target.value}T00:00:00`))}
            />
          </button>
          <button className="sch-step" title="Next day" onClick={() => pickDay(addDays(day, 1))}>›</button>
          <button className="btn btn-ghost btn-sm" onClick={() => pickDay(new Date())}>Today</button>
        </div>
      </div>

      <div className="rsv">
        <div className="rsv-main">
          <div className="rsv-kpis">
            <div className="rsv-kpi rsv-kpi--blue">
              <div>
                <div className="rsv-kpi-value">{live.length}</div>
                <div className="rsv-kpi-label">Booked on this day</div>
                <div className="rsv-kpi-sub">{totalHeads} {totalHeads === 1 ? 'person' : 'people'} expected</div>
              </div>
              <div className="rsv-kpi-icon" aria-hidden="true">📋</div>
            </div>
            <div className="rsv-kpi rsv-kpi--green">
              <div>
                <div className="rsv-kpi-value">{busyBranches.length}<small style={{ fontSize: '.9rem', fontWeight: 700, opacity: .8 }}>/{groups.length}</small></div>
                <div className="rsv-kpi-label">Branches trading</div>
                <div className="rsv-kpi-sub">{groups.length - busyBranches.length} idle today</div>
              </div>
              <div className="rsv-kpi-icon" aria-hidden="true">🏬</div>
            </div>
            <div className="rsv-kpi rsv-kpi--amber">
              <div>
                <div className="rsv-kpi-value">{overallUtilisation}%</div>
                <div className="rsv-kpi-label">Resource utilisation</div>
                <div className="rsv-kpi-sub">of {hourLabel(START_HOUR)}–{hourLabel(END_HOUR)} across {resources.length} resources</div>
              </div>
              <div className="rsv-kpi-icon" aria-hidden="true">📈</div>
            </div>
            <div className="rsv-kpi rsv-kpi--pink">
              <div>
                <div className="rsv-kpi-value">{clashing.size / 2 || 0}</div>
                <div className="rsv-kpi-label">Double bookings</div>
                <div className="rsv-kpi-sub">{clashing.size === 0 ? 'Nothing clashing' : 'Outlined in red below'}</div>
              </div>
              <div className="rsv-kpi-icon" aria-hidden="true">⚠️</div>
            </div>
          </div>

          {isLoading ? (
            <div className="rsv-card"><div className="loading-row" style={{ padding: 40 }}><span className="spinner spinner-dark" /> Loading the board…</div></div>
          ) : groups.length === 0 ? (
            <div className="rsv-card">
              <div className="rsv-empty">
                <b>No resources yet</b>
                A branch needs rooms, tables or vehicles before anything can be scheduled against it.
              </div>
            </div>
          ) : (
            groups.map((group) => {
              const utilisation = utilisationOf(group.resources);
              const count = group.resources.reduce((sum, r) => sum + (bookingsByResource.get(r.id)?.length ?? 0), 0);
              return (
                <section className="rsv-card sch-board" key={group.key}>
                  <header className="sch-board-head">
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <h3 className="sch-board-title">{group.name}</h3>
                      <p className="sch-board-sub">
                        {count} booking{count === 1 ? '' : 's'} · {group.resources.length} resource{group.resources.length === 1 ? '' : 's'}
                      </p>
                    </div>
                    <div className="sch-load">
                      <div className="sch-load-track">
                        <div className="sch-load-fill" style={{ width: `${utilisation}%` }} />
                      </div>
                      <div className="sch-load-label">{utilisation}% used</div>
                    </div>
                  </header>

                  <div className="sch-grid">
                    <div className="sch-hours">
                      <div />
                      <div className="sch-hours-track" style={{ gridTemplateColumns: `repeat(${HOURS.length}, 1fr)` }}>
                        {HOURS.map((h) => <div className="sch-hours-col" key={h}>{hourLabel(h)}</div>)}
                      </div>
                    </div>

                    {group.resources.map((resource) => {
                      const list = bookingsByResource.get(resource.id) ?? [];
                      return (
                        <div className="sch-row" key={resource.id}>
                          <div className="sch-row-label">
                            <span className="sch-row-name">{resource.name}</span>
                            <span className="sch-row-meta">
                              {resource.category}{resource.capacity ? ` · seats ${resource.capacity}` : ''}
                            </span>
                          </div>
                          <div className="sch-track" style={{ ['--sch-hour' as string]: `${100 / HOURS.length}%` }}>
                            {list.length === 0 && <div className="sch-rowempty">Free all day</div>}
                            {list.map((b) => {
                              const pos = barPosition(b, day);
                              if (!pos) return null;
                              const classes = ['sch-bar'];
                              if (DONE.has(b.status)) classes.push('is-done');
                              if (DROPPED.has(b.status)) classes.push('is-dropped');
                              if (clashing.has(b.id)) classes.push('is-clash');
                              return (
                                <button
                                  key={b.id}
                                  type="button"
                                  className={classes.join(' ')}
                                  style={{ left: pos.left, width: pos.width, background: STATUS_COLORS[b.status].bg }}
                                  title={`${b.title ?? b.bookingTypeName} — ${formatTime(b.startTime)}–${formatTime(b.endTime)} · ${b.status}`}
                                  onClick={() => setSelectedBooking(b)}
                                >
                                  <i />
                                  {b.title ?? b.bookingTypeName}
                                </button>
                              );
                            })}
                            {isSameDay(day, today) && nowOffset() !== null && (
                              <div className="sch-now" style={{ left: `${nowOffset()}%` }} title="Now" />
                            )}
                          </div>
                        </div>
                      );
                    })}
                  </div>

                  <div className="sch-legend">
                    {(['Pending', 'Confirmed', 'CheckedIn', 'InProgress', 'Completed'] as const).map((s) => (
                      <span key={s}><i style={{ background: STATUS_COLORS[s].bg }} />{s === 'CheckedIn' ? 'Checked in' : s === 'InProgress' ? 'In progress' : s}</span>
                    ))}
                    {clashing.size > 0 && <span><i style={{ background: 'transparent', boxShadow: '0 0 0 2px var(--color-critical)' }} />Clash</span>}
                  </div>
                </section>
              );
            })
          )}
        </div>

        <aside className="rsv-rail">
          <div className="rsv-card rsv-cal">
            <div className="rsv-cal-head">
              <strong>{formatMonthYear(monthAnchor)}</strong>
              <div className="rsv-cal-nav">
                <button className="rsv-icon-btn" onClick={() => setMonthAnchor(addDays(monthAnchor, -1))} title="Previous month">‹</button>
                <button className="rsv-icon-btn" onClick={() => setMonthAnchor(startOfMonth(new Date()))} title="This month">•</button>
                <button className="rsv-icon-btn" onClick={() => setMonthAnchor(startOfMonth(addDays(monthAnchor, 32)))} title="Next month">›</button>
              </div>
            </div>
            <div className="rsv-cal-grid">
              {WEEKDAY_LABELS.map((d) => <div className="rsv-cal-dow" key={d}>{d.slice(0, 2)}</div>)}
              {monthDays.map((d) => {
                const n = monthCounts.get(toISODate(d)) ?? 0;
                const cls = ['rsv-cal-day',
                  d.getMonth() !== monthAnchor.getMonth() ? 'is-other' : '',
                  isSameDay(d, today) ? 'is-today' : '',
                  isSameDay(d, day) ? 'is-selected' : '',
                  n > 0 ? 'has-bookings' : ''].filter(Boolean).join(' ');
                return (
                  <button type="button" key={toISODate(d)} className={cls} onClick={() => pickDay(d)} title={n ? `${n} booking${n === 1 ? '' : 's'}` : undefined}>
                    {d.getDate()}
                  </button>
                );
              })}
            </div>
            <div className="rsv-cal-foot">
              <span>• a day with bookings</span>
              <span>Tap a day to load it</span>
            </div>
          </div>

          <div className="rsv-card">
            <div className="rsv-card-head">
              <div>
                <h3 className="rsv-card-title">Where the load is</h3>
                <p className="rsv-card-sub">Utilisation by branch, this day</p>
              </div>
            </div>
            <div className="sch-rank">
              {groups.length === 0 ? (
                <div className="rsv-up-empty">No branches to compare.</div>
              ) : (
                groups.map((group) => {
                  const utilisation = utilisationOf(group.resources);
                  const count = group.resources.reduce((sum, r) => sum + (bookingsByResource.get(r.id)?.length ?? 0), 0);
                  return (
                    <div className="sch-rank-row" key={group.key}>
                      <div className="sch-rank-head">
                        <span className="sch-rank-name">{group.name}</span>
                        <span className="sch-rank-value">{utilisation}%</span>
                      </div>
                      <div className="sch-rank-track"><div className="sch-rank-fill" style={{ width: `${utilisation}%` }} /></div>
                      <div className="sch-rank-sub">{count} booking{count === 1 ? '' : 's'} · {group.resources.length} resource{group.resources.length === 1 ? '' : 's'}</div>
                    </div>
                  );
                })
              )}
            </div>
          </div>

          <div className="rsv-card">
            <div className="rsv-card-head">
              <div>
                <h3 className="rsv-card-title">Next up</h3>
                <p className="rsv-card-sub">Across every branch</p>
              </div>
            </div>
            <div className="rsv-up">
              {upcoming.length === 0 ? (
                <div className="rsv-up-empty">Nothing else on this day.</div>
              ) : (
                upcoming.map((b) => (
                  <button
                    type="button"
                    key={b.id}
                    className="rsv-up-item"
                    style={{ width: '100%', border: 0, background: 'transparent', textAlign: 'left', cursor: 'pointer' }}
                    onClick={() => setSelectedBooking(b)}
                  >
                    <div className="rsv-up-time" style={{ background: STATUS_COLORS[b.status].bg }}>
                      {formatTime(b.startTime)}
                      <small>{branchName(resources.find((r) => r.id === b.resourceId)?.branchId)}</small>
                    </div>
                    <div style={{ minWidth: 0 }}>
                      <div className="rsv-up-title">{b.title ?? b.bookingTypeName}</div>
                      <div className="rsv-up-meta">{b.resourceName} · {b.status}</div>
                    </div>
                  </button>
                ))
              )}
            </div>
          </div>
        </aside>
      </div>

      {selectedBooking && <BookingDetailsModal booking={selectedBooking} onClose={() => setSelectedBooking(null)} />}
    </div>
  );
}

/** Minutes of this booking that fall inside the board's own window. */
function minutesInWindow(b: Booking, day: Date): number {
  const windowStart = new Date(day);
  windowStart.setHours(START_HOUR, 0, 0, 0);
  const startMin = Math.max(0, (new Date(b.startTime).getTime() - windowStart.getTime()) / 60000);
  const endMin = Math.min(WINDOW_MINUTES, (new Date(b.endTime).getTime() - windowStart.getTime()) / 60000);
  return Math.max(0, endMin - startMin);
}

function barPosition(b: Booking, day: Date): { left: string; width: string } | null {
  const windowStart = new Date(day);
  windowStart.setHours(START_HOUR, 0, 0, 0);
  const startMin = Math.max(0, (new Date(b.startTime).getTime() - windowStart.getTime()) / 60000);
  const endMin = Math.min(WINDOW_MINUTES, (new Date(b.endTime).getTime() - windowStart.getTime()) / 60000);
  if (endMin <= 0 || startMin >= WINDOW_MINUTES) return null;
  return {
    left: `${(startMin / WINDOW_MINUTES) * 100}%`,
    // A 15-minute booking still needs to be wide enough to hit.
    width: `${Math.max(((endMin - startMin) / WINDOW_MINUTES) * 100, 2.5)}%`,
  };
}

/** Where "now" falls in the window, or null when it is outside it. */
function nowOffset(): number | null {
  const now = new Date();
  const minutes = (now.getHours() - START_HOUR) * 60 + now.getMinutes();
  if (minutes < 0 || minutes > WINDOW_MINUTES) return null;
  return (minutes / WINDOW_MINUTES) * 100;
}
