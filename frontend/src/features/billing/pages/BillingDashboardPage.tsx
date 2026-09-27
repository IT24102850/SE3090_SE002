import { useState } from 'react';
import { Link } from 'react-router-dom';
import { Area, AreaChart, Bar, BarChart, CartesianGrid, Cell, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { useChartTheme } from '../../../shared/useChartTheme';
import { billingApi } from '../billingApi';
import { addDays, compactMoney, date, isoDay, money, statusTone, humanize } from '../format';
import { useAsync } from '../useAsync';
import StatusBadge from '../components/StatusBadge';
import '../billing.css';

const RANGES = [
  { label: '7 days', days: 7 },
  { label: '30 days', days: 30 },
  { label: '90 days', days: 90 },
  { label: '12 months', days: 365 },
];

export default function BillingDashboardPage() {
  const theme = useChartTheme();
  const [days, setDays] = useState(30);
  const to = isoDay();
  const from = isoDay(addDays(new Date(), -(days - 1)));

  const { data: d, loading, error, reload } = useAsync(() => billingApi.dashboard(from, to), [from, to]);
  const { data: aging } = useAsync(() => billingApi.outstanding(0), []);
  const { data: today } = useAsync(() => billingApi.dailyRevenue(to), [to]);

  const toneColor = (tone: string) =>
    tone === 'good' ? theme.series.green : tone === 'warning' ? theme.series.amber : tone === 'critical' ? theme.series.red : tone === 'primary' ? theme.series.blue : theme.series.slate;
  const currency = d?.currency ?? 'LKR';
  const collectionRate = d && d.totalInvoiced > 0 ? Math.round((d.totalCollected / d.totalInvoiced) * 100) : null;

  return (
    <div className="bl-page">
      <div className="page-header">
        <div>
          <h1 className="page-title">Billing dashboard</h1>
          <p className="page-subtitle">Revenue, payment status and what is still owed, across every way this business charges.</p>
        </div>
        <div className="bl-tabs" role="tablist" aria-label="Date range">
          {RANGES.map((r) => (
            <button key={r.days} role="tab" className="bl-tab" aria-selected={days === r.days} onClick={() => setDays(r.days)}>{r.label}</button>
          ))}
        </div>
      </div>

      {error && (
        <div className="bl-notice bl-notice-critical" role="alert">
          {error} <button className="btn btn-ghost btn-sm" onClick={reload}>Retry</button>
        </div>
      )}

      <div className="bl-kpis">
        <div className="bl-kpi">
          <div className="bl-kpi-label">Invoiced</div>
          <div className="bl-kpi-value">{d ? compactMoney(d.totalInvoiced, currency) : '…'}</div>
          <div className="bl-kpi-sub">{date(d?.from)} – {date(d?.to)}</div>
        </div>
        <div className="bl-kpi">
          <div className="bl-kpi-label">Collected</div>
          <div className="bl-kpi-value" style={{ color: 'var(--color-good)' }}>{d ? compactMoney(d.totalCollected, currency) : '…'}</div>
          <div className="bl-kpi-sub">{collectionRate === null ? 'No invoices in range' : `${collectionRate}% of invoiced`}</div>
        </div>
        <div className="bl-kpi">
          <div className="bl-kpi-label">Outstanding</div>
          <div className="bl-kpi-value">{d ? compactMoney(d.totalOutstanding, currency) : '…'}</div>
          <div className="bl-kpi-sub">all open invoices</div>
        </div>
        <div className="bl-kpi">
          <div className="bl-kpi-label">Overdue</div>
          <div className="bl-kpi-value" style={{ color: d && d.overdueCount > 0 ? 'var(--color-critical)' : undefined }}>
            {d ? compactMoney(d.overdueAmount, currency) : '…'}
          </div>
          <div className="bl-kpi-sub">{d?.overdueCount ?? 0} invoices</div>
        </div>
        <div className="bl-kpi">
          <div className="bl-kpi-label">Recurring (MRR)</div>
          <div className="bl-kpi-value">{d ? compactMoney(d.monthlyRecurringRevenue, currency) : '…'}</div>
          <div className="bl-kpi-sub">{d?.activeSubscriptions ?? 0} active subscriptions</div>
        </div>
        <div className="bl-kpi">
          <div className="bl-kpi-label">Needs attention</div>
          <div className="bl-kpi-value">{d ? d.pendingApprovals + d.pendingClaims : '…'}</div>
          <div className="bl-kpi-sub">
            <Link to="/billing-agent">{d?.pendingApprovals ?? 0} approvals</Link> · <Link to="/insurance-claims">{d?.pendingClaims ?? 0} claims</Link>
          </div>
        </div>
      </div>

      <div className="card chart-card">
        <p className="chart-title">Invoiced vs collected</p>
        <p className="chart-subtitle">{days > 92 ? 'Weekly' : 'Daily'} totals · refunds are subtracted from collections</p>
        {loading && !d ? (
          <div className="loading-row"><span className="spinner spinner-dark" /></div>
        ) : (
          <div style={{ height: 280 }}>
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={d?.revenueSeries ?? []} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
                <CartesianGrid stroke={theme.grid} vertical={false} />
                <XAxis dataKey="date" tick={{ fill: theme.tick, fontSize: 11 }} tickLine={false} axisLine={false} minTickGap={24} />
                <YAxis tick={{ fill: theme.tick, fontSize: 11 }} tickLine={false} axisLine={false} width={64}
                  tickFormatter={(v: number) => compactMoney(v, '').trim()} />
                <Tooltip contentStyle={theme.tooltip} itemStyle={theme.tooltipItem} formatter={(v) => money(Number(v), currency)} />
                <Area type="monotone" dataKey="invoiced" name="Invoiced" stroke={theme.series.blue} fill={theme.series.blue} fillOpacity={0.12} strokeWidth={2} />
                <Area type="monotone" dataKey="collected" name="Collected" stroke={theme.series.green} fill={theme.series.green} fillOpacity={0.18} strokeWidth={2} />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        )}
      </div>

      <div className="bl-grid-2">
        <div className="card chart-card">
          <p className="chart-title">Payment status</p>
          <p className="chart-subtitle">Invoices raised in the range, by status</p>
          {d && d.statusBreakdown.length === 0 && <div className="bl-empty">No invoices in this range.</div>}
          <div style={{ height: 220 }}>
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={d?.statusBreakdown ?? []} layout="vertical" margin={{ left: 12, right: 16 }}>
                <XAxis type="number" hide />
                <YAxis type="category" dataKey="label" width={110} tick={{ fill: theme.tick, fontSize: 12 }} tickFormatter={humanize} axisLine={false} tickLine={false} />
                <Tooltip contentStyle={theme.tooltip} itemStyle={theme.tooltipItem}
                  formatter={(v, _n, p) => [`${money(Number(v), currency)} · ${(p?.payload as { count?: number } | undefined)?.count ?? 0} invoices`, 'Amount']} />
                <Bar dataKey="amount" radius={[0, 6, 6, 0]}>
                  {(d?.statusBreakdown ?? []).map((s) => <Cell key={s.label} fill={toneColor(statusTone(s.label))} />)}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </div>
        </div>

        <div className="card chart-card">
          <p className="chart-title">Collected by method</p>
          <p className="chart-subtitle">Card, cash, QR, bank transfer…</p>
          {d && d.methodBreakdown.length === 0 && <div className="bl-empty">No payments in this range.</div>}
          <ul className="bl-list">
            {(d?.methodBreakdown ?? []).map((m) => {
              const pct = d && d.totalCollected > 0 ? Math.round((m.amount / d.totalCollected) * 100) : 0;
              return (
                <li key={m.label} className="bl-list-item">
                  <div className="bl-spread"><strong>{m.label}</strong><span className="bl-num">{money(m.amount, currency)} · {m.count}</span></div>
                  <div className="bl-meter" aria-label={`${pct}% of collections`}><span style={{ width: `${pct}%` }} /></div>
                </li>
              );
            })}
          </ul>
        </div>
      </div>

      <div className="bl-grid-2">
        <div className="card chart-card">
          <div className="bl-spread">
            <div>
              <p className="chart-title">Outstanding by age</p>
              <p className="chart-subtitle">{aging ? `${aging.count} unpaid invoices · ${money(aging.totalOutstanding, currency)}` : '…'}</p>
            </div>
            <Link className="btn btn-secondary btn-sm" to="/invoices?status=Overdue">Chase overdue</Link>
          </div>
          <div className="bl-table-wrap">
            <table className="bl-table">
              <thead><tr><th>Age</th><th className="bl-num">Invoices</th><th className="bl-num">Amount</th></tr></thead>
              <tbody>
                {(aging?.buckets ?? []).map((b) => (
                  <tr key={b.label}><td>{b.label}</td><td className="bl-num">{b.count}</td><td className="bl-num">{money(b.amount, currency)}</td></tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        <div className="card chart-card">
          <p className="chart-title">Today</p>
          <p className="chart-subtitle">Daily revenue report · {date(today?.date)}</p>
          <div className="bl-kpis">
            <div className="bl-kpi"><div className="bl-kpi-label">Collected</div><div className="bl-kpi-value">{today ? money(today.totalCollected, currency) : '…'}</div></div>
            <div className="bl-kpi"><div className="bl-kpi-label">Payments</div><div className="bl-kpi-value">{today?.paymentCount ?? '…'}</div></div>
            <div className="bl-kpi"><div className="bl-kpi-label">Average</div><div className="bl-kpi-value">{today ? money(today.averagePayment, currency) : '…'}</div></div>
          </div>
          {aging && aging.items.length > 0 && (
            <>
              <p className="chart-subtitle" style={{ marginTop: 12 }}>Most overdue</p>
              <ul className="bl-list">
                {aging.items.slice(0, 4).map((r) => (
                  <li key={r.invoiceId} className="bl-list-item">
                    <div className="bl-spread">
                      <span>{r.invoiceNumber} · {r.customerName ?? 'Customer'}</span>
                      <span className="bl-row"><StatusBadge status={r.status} label={r.daysOverdue > 0 ? `${r.daysOverdue}d overdue` : 'Due'} /><strong>{money(r.balanceDue, r.currency)}</strong></span>
                    </div>
                  </li>
                ))}
              </ul>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
