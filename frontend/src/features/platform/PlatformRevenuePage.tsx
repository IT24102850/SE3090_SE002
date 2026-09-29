import { useState, type ReactNode } from 'react';
import PlatformLayout from './PlatformLayout';
import OtpPrompt from './OtpPrompt';
import {
  errorMessage,
  useCompSubscriptionMutation,
  useExtendSubscriptionMutation,
  useRevenueInvoicesQuery,
  useRevenueQuery,
  useRevenueSubscriptionsQuery,
  type RevenueSubscriptionRow,
} from './platformApi';

/* The money half of the owner's console: what the platform earns, who is on
 * what, and how the free-to-paid funnel is doing.
 *
 * Every rate here is null rather than zero when there is nothing to divide
 * by. A platform in its first week showing "0% trial conversion" and "0%
 * churn" reads as a business that is failing, when in truth nothing has
 * happened yet - so those render as a dash, the same rule the clinic and
 * gym dashboards already follow. */

const n = (v: number) => v.toLocaleString();
const day = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString([], { dateStyle: 'medium' }) : '—');
const when = (iso: string) => new Date(iso).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' });
const rate = (v: number | null) => (v === null || v === undefined ? '—' : `${v}%`);
const money = (amount: number, currency: string) =>
  `${currency} ${amount.toLocaleString(undefined, { maximumFractionDigits: 0 })}`;

type Pending = { kind: 'comp' | 'extend'; row: RevenueSubscriptionRow };

function Kpi({ label, value, sub, icon }: { label: string; value: string; sub?: ReactNode; icon: string }) {
  return (
    <div className="pf-card pf-kpi">
      <span className="pf-kpi-icon" aria-hidden="true">{icon}</span>
      <div className="pf-kpi-label">{label}</div>
      <div className="pf-kpi-value">{value}</div>
      {sub && <div className="pf-kpi-sub">{sub}</div>}
    </div>
  );
}

function Bars({ rows }: { rows: { label: string; value: number; hint: string }[] }) {
  if (rows.length === 0) return <div className="pf-empty">Nothing yet.</div>;
  const max = Math.max(1, ...rows.map((r) => r.value));
  return (
    <div className="pf-bars">
      {rows.map((r) => (
        <div className="pf-bar" key={r.label}>
          <span>{r.label}</span>
          <div className="pf-bar-track">
            <i style={{ width: `${Math.max(2, (r.value / max) * 100)}%` }} />
          </div>
          <b>{r.hint}</b>
        </div>
      ))}
    </div>
  );
}

function statusPill(status: string) {
  const tone =
    status === 'Active' ? 'pf-pill-good'
    : status === 'PastDue' || status === 'Cancelling' ? 'pf-pill-warn'
    : status === 'Expired' ? 'pf-pill-bad'
    : 'pf-pill-neutral';
  return <span className={`pf-pill ${tone}`}>{status}</span>;
}

export default function PlatformRevenuePage() {
  const { data, isLoading, isError, refetch } = useRevenueQuery();
  const [status, setStatus] = useState('');
  const [page, setPage] = useState(1);
  const subscriptions = useRevenueSubscriptionsQuery({ status: status || undefined, page, pageSize: 25 });
  const invoices = useRevenueInvoicesQuery({ page: 1, pageSize: 12 });

  const [comp, { isLoading: comping }] = useCompSubscriptionMutation();
  const [extend, { isLoading: extending }] = useExtendSubscriptionMutation();
  const [pending, setPending] = useState<Pending | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const confirm = async (code: string, reason: string) => {
    if (!pending) return;
    setError(null);
    try {
      const result =
        pending.kind === 'comp'
          ? await comp({
              tenantId: pending.row.tenantId,
              // Comping the plan they are already on is a no-op; a free
              // tenant is comped onto Pro, the rung the trial is on.
              planCode: pending.row.tier > 0 ? pending.row.planCode : 'pro',
              months: 12,
              // The backend requires a reason for the audit trail; the prompt
              // leaves it optional, so give it an honest default.
              reason: reason || 'Complimentary plan granted from the owner console',
              otp: code,
            }).unwrap()
          : await extend({
              tenantId: pending.row.tenantId,
              days: 30,
              reason: reason || 'Term extended from the owner console',
              otp: code,
            }).unwrap();
      setNotice(`${pending.row.tenantName}: ${result.message}`);
      setPending(null);
    } catch (err) {
      setError(errorMessage(err, 'The change was refused.'));
    }
  };

  return (
    <PlatformLayout title="Revenue">
      <div className="pf-head">
        <div>
          <div className="pf-eyebrow">What the platform earns</div>
          <h1>Subscriptions and revenue</h1>
          <p>
            What tenants pay Unify for the platform - not what they charge their own customers. Comped accounts are left
            out of MRR.
          </p>
        </div>
        <button type="button" className="pf-btn" onClick={() => refetch()}>
          ↻ Refresh
        </button>
      </div>

      {notice && (
        <div className="pf-ok" role="status">
          {notice}
        </div>
      )}
      {isError && (
        <div className="pf-alert pf-alert-bad">
          <div>
            <b>Could not load the revenue figures.</b>Your session may have ended; try refreshing.
          </div>
        </div>
      )}
      {isLoading && !data && <div className="pf-empty">Loading revenue figures…</div>}

      {data && (
        <>
          <div className="pf-grid pf-grid-4">
            <Kpi
              icon="💰"
              label="MRR"
              value={money(data.mrr, data.currency)}
              sub={<><b>{n(data.tenants.paying)}</b> paying · every term normalised to a month</>}
            />
            <Kpi icon="📈" label="ARR" value={money(data.arr, data.currency)} sub={<>MRR × 12</>} />
            <Kpi
              icon="🧮"
              label="Average per account"
              value={money(data.arpa, data.currency)}
              sub={<>Across paying businesses only</>}
            />
            <Kpi
              icon="🏦"
              label="Collected · 30 days"
              value={money(data.collected30d, data.currency)}
              sub={<><b>{money(data.addOnRevenue30d, data.currency)}</b> of it from add-ons</>}
            />
          </div>

          <div className="pf-grid pf-grid-4">
            <Kpi
              icon="🎯"
              label="Free → paid"
              value={rate(data.tenants.paidConversionRate)}
              sub={<><b>{n(data.tenants.free)}</b> still on Starter · <b>{n(data.tenants.trialing)}</b> trialling</>}
            />
            <Kpi
              icon="🔁"
              label="Trial conversion · 30 days"
              value={rate(data.funnel.trialConversionRate)}
              sub={<><b>{n(data.funnel.trialsStarted30d)}</b> started · <b>{n(data.funnel.trialsConverted30d)}</b> converted · <b>{n(data.funnel.trialsExpired30d)}</b> lapsed</>}
            />
            <Kpi
              icon="📉"
              label="Churn · 30 days"
              value={rate(data.funnel.churnRate)}
              sub={<><b>{n(data.funnel.churned30d)}</b> lapsed · <b>+{n(data.funnel.newPaid30d)}</b> new</>}
            />
            <Kpi
              icon="⚠"
              label="Needs attention"
              value={n(data.tenants.pastDue + data.tenants.cancelling)}
              sub={<><b>{n(data.tenants.pastDue)}</b> past due · <b>{n(data.tenants.cancelling)}</b> ending this term</>}
            />
          </div>

          <div className="pf-grid pf-grid-21">
            <div className="pf-card">
              <div className="pf-card-head">
                <h2>Plan mix</h2>
                <span>Businesses on each rung, and what each rung earns</span>
              </div>
              <Bars
                rows={data.planMix.map((p) => ({
                  label: p.planCode,
                  value: p.count,
                  hint: `${n(p.count)} · ${money(p.mrr, data.currency)}`,
                }))}
              />
            </div>

            <div className="pf-card">
              <div className="pf-card-head">
                <h2>Term mix</h2>
                <span>Where the discount goes</span>
              </div>
              <Bars rows={data.termMix.map((t) => ({ label: t.label, value: t.count, hint: n(t.count) }))} />
            </div>
          </div>

          <div className="pf-card">
            <div className="pf-card-head">
              <h2>Subscriptions</h2>
              <span>{subscriptions.data ? `${n(subscriptions.data.total)} in total` : ''}</span>
            </div>
            <div className="pf-filters">
              <select
                className="pf-select"
                value={status}
                onChange={(e) => {
                  setStatus(e.target.value);
                  setPage(1);
                }}
                aria-label="Subscription status"
              >
                <option value="">All statuses</option>
                <option value="Active">Active</option>
                <option value="Trialing">Trialing</option>
                <option value="PastDue">Past due</option>
                <option value="Cancelling">Cancelling</option>
                <option value="Expired">Expired</option>
              </select>
              <span className="pf-filters-spacer" />
              <span className="pf-count">{subscriptions.isFetching ? 'updating…' : ''}</span>
            </div>

            <div className="pf-table-wrap">
              <table className="pf-table">
                <thead>
                  <tr>
                    <th>Business</th>
                    <th>Plan</th>
                    <th>Term</th>
                    <th>Amount</th>
                    <th>Status</th>
                    <th>Renews</th>
                    <th>Open bills</th>
                    <th>Owner actions</th>
                  </tr>
                </thead>
                <tbody>
                  {subscriptions.isLoading && (
                    <tr>
                      <td colSpan={8} className="pf-empty">
                        Loading subscriptions…
                      </td>
                    </tr>
                  )}
                  {!subscriptions.isLoading && subscriptions.data?.items.length === 0 && (
                    <tr>
                      <td colSpan={8} className="pf-empty">
                        No subscriptions match that filter.
                      </td>
                    </tr>
                  )}
                  {subscriptions.data?.items.map((row) => (
                    <tr key={row.id}>
                      <td>
                        <b>{row.tenantName}</b>
                        <br />
                        <span className="pf-count">{row.businessType}</span>
                      </td>
                      <td style={{ textTransform: 'capitalize' }}>
                        {row.planCode}
                        {row.isComplimentary && <> · <span className="pf-pill pf-pill-neutral">comped</span></>}
                      </td>
                      <td>{row.period}</td>
                      <td>{row.amount > 0 ? money(row.amount, row.currency) : '—'}</td>
                      <td>{statusPill(row.status)}</td>
                      <td>{day(row.currentPeriodEnd)}</td>
                      <td>{row.openInvoices > 0 ? n(row.openInvoices) : '—'}</td>
                      <td>
                        <button
                          type="button"
                          className="pf-btn pf-btn-sm"
                          onClick={() => setPending({ kind: 'extend', row })}
                        >
                          Extend 30d
                        </button>{' '}
                        <button
                          type="button"
                          className="pf-btn pf-btn-sm"
                          onClick={() => setPending({ kind: 'comp', row })}
                        >
                          Comp
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {subscriptions.data && subscriptions.data.totalPages > 1 && (
              <div className="pf-pager">
                <button type="button" className="pf-btn pf-btn-sm" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>
                  ← Prev
                </button>
                <span className="pf-count">
                  Page {subscriptions.data.page} of {subscriptions.data.totalPages}
                </span>
                <button
                  type="button"
                  className="pf-btn pf-btn-sm"
                  disabled={page >= subscriptions.data.totalPages}
                  onClick={() => setPage((p) => p + 1)}
                >
                  Next →
                </button>
              </div>
            )}
          </div>

          <div className="pf-grid pf-grid-21">
            <div className="pf-card">
              <div className="pf-card-head">
                <h2>Latest invoices</h2>
                <span>Raised by Unify against its tenants</span>
              </div>
              <div className="pf-table-wrap">
                <table className="pf-table">
                  <thead>
                    <tr>
                      <th>Invoice</th>
                      <th>Business</th>
                      <th>Total</th>
                      <th>Status</th>
                      <th>Paid</th>
                    </tr>
                  </thead>
                  <tbody>
                    {invoices.data?.items.length === 0 && (
                      <tr>
                        <td colSpan={5} className="pf-empty">
                          No invoices yet.
                        </td>
                      </tr>
                    )}
                    {invoices.data?.items.map((i) => (
                      <tr key={i.id}>
                        <td className="pf-mono">{i.number}</td>
                        <td>{i.tenantName}</td>
                        <td>{money(i.total, i.currency)}</td>
                        <td>
                          <span
                            className={`pf-pill ${
                              i.status === 'Paid' ? 'pf-pill-good' : i.status === 'Failed' ? 'pf-pill-bad' : 'pf-pill-warn'
                            }`}
                          >
                            {i.status}
                          </span>
                        </td>
                        <td>{day(i.paidAt)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>

            <div className="pf-card">
              <div className="pf-card-head">
                <h2>Recent activity</h2>
                <span>Every change of standing</span>
              </div>
              {data.recentEvents.length === 0 ? (
                <div className="pf-empty">Nothing yet.</div>
              ) : (
                <ul className="pf-list">
                  {data.recentEvents.map((e) => (
                    <li key={e.id} className="pf-audit-row">
                      <i aria-hidden="true" />
                      <span>
                        <span className="pf-mono">{e.eventType}</span>
                        <small>
                          {e.tenantName}
                          {e.fromPlanCode && e.toPlanCode && e.fromPlanCode !== e.toPlanCode && (
                            <> · {e.fromPlanCode} → {e.toPlanCode}</>
                          )}
                          {e.amount ? <> · {money(e.amount, e.currency ?? data.currency)}</> : null}
                        </small>
                      </span>
                      <time>{when(e.createdAt)}</time>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          </div>
        </>
      )}

      {pending && (
        <OtpPrompt
          title={pending.kind === 'comp' ? `Comp ${pending.row.tenantName}` : `Extend ${pending.row.tenantName}`}
          description={
            pending.kind === 'comp'
              ? 'Puts this business on a paid plan free for 12 months. It renews itself, is excluded from MRR, and the reason is kept in the audit log.'
              : 'Pushes this term out by 30 days at no charge and clears a past-due state. The reason is kept in the audit log.'
          }
          confirmLabel={pending.kind === 'comp' ? 'Comp the plan' : 'Extend the term'}
          busy={comping || extending}
          error={error}
          onConfirm={confirm}
          onCancel={() => {
            setPending(null);
            setError(null);
          }}
        />
      )}
    </PlatformLayout>
  );
}
