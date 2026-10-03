import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { useFindAndBookMutation, useGetBookingTypesQuery, useGetMyWorkflowsQuery } from '../../api/bookingApi';
import type { RootState } from '../../store/store';
import { apiErrorMessage, useToast } from '../../shared/components/Toast';
import { addDays, formatDateTime, toISODate } from '../../shared/dateUtils';
import './customer.css';

/* The customer's AI planner - the web twin of the Flutter AiPlannerScreen
 * and MyAiRequestsScreen: state what you want in plain words, pick how
 * far ahead to look, and POST /agent/find-and-book plans and books it
 * (or parks it for the business's approval). Every request the customer
 * has made is listed below with its status. */

const WINDOWS = [3, 7, 14, 30];

export default function CustomerAiPlannerPage() {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';
  const toast = useToast();
  const { data: types } = useGetBookingTypesQuery({ tenantId, status: 'Active' }, { skip: !tenantId });
  const { data: requests, isLoading: requestsLoading } = useGetMyWorkflowsQuery();
  const [findAndBook, { isLoading }] = useFindAndBookMutation();
  const [objective, setObjective] = useState('');
  const [bookingTypeId, setBookingTypeId] = useState('');
  const [days, setDays] = useState(7);
  const [result, setResult] = useState<{ status: string; bookingId?: string | null; message?: string | null; workflowId: string } | null>(null);

  const examples = (types ?? []).slice(0, 3).map((t) => `Find me the earliest ${t.name.toLowerCase()} this week`);

  async function submit() {
    if (objective.trim().length < 6) { toast.show('Say a little more about what you want.', 'error'); return; }
    setResult(null);
    try {
      const from = new Date();
      if (!bookingTypeId) { toast.show('Choose a service first.', 'error'); return; }
      const r = await findAndBook({ objective: objective.trim(), dateFrom: toISODate(from), dateTo: toISODate(addDays(from, days)), extraConstraints: { booking_type_id: bookingTypeId } }).unwrap();
      setResult(r);
      toast.show(r.bookingId ? 'Booked!' : r.message ?? 'Request sent.', r.bookingId ? 'success' : 'info');
    } catch (error) {
      toast.show(apiErrorMessage(error, 'The planner could not complete this request.'), 'error');
    }
  }

  return (
    <div className="cust-page">
      <div className="page-header">
        <div>
          <h1 className="page-title">AI planner</h1>
          <p className="page-subtitle">Choose a service and describe what you need. AI searches available slots; it may book immediately or send the request to the business for approval.</p>
        </div>
      </div>

      <section className="card chart-card">
        <div className="cust-ai">
          <label className="cust-note" htmlFor="ai-booking-type">Service</label>
          <select id="ai-booking-type" className="input" value={bookingTypeId} onChange={(e) => setBookingTypeId(e.target.value)} disabled={!types?.length}>
            <option value="">Choose a service</option>
            {(types ?? []).map((type) => <option key={type.id} value={type.id}>{type.name}</option>)}
          </select>
          <textarea className="input" placeholder='e.g. "Find me the earliest beginner-friendly slot this week, afternoons only"' value={objective} onChange={(e) => setObjective(e.target.value)} aria-label="What would you like?" />
          {examples.length > 0 && (
            <div className="cust-ai-examples">
              {examples.map((ex) => <button key={ex} type="button" onClick={() => setObjective(ex)}>{ex}</button>)}
            </div>
          )}
          <div className="cust-ai-row">
            <span className="cust-note" style={{ margin: 0 }}>Within</span>
            <div className="cust-tabs" role="tablist" aria-label="Search window">
              {WINDOWS.map((d) => <button key={d} type="button" role="tab" aria-selected={days === d} className={days === d ? 'active' : ''} onClick={() => setDays(d)}>{d} days</button>)}
            </div>
            <span style={{ flex: 1 }} />
            <button type="button" className="btn btn-primary" disabled={isLoading || !bookingTypeId} onClick={submit}>{isLoading ? 'Planning…' : '✨ Find & book'}</button>
          </div>
          {(types?.length ?? 0) === 0 && <p className="cust-note">No bookable services yet.</p>}
          {result && (
            <div className="cust-ai-result" role="status">
              <h4>{result.bookingId ? 'Booked' : result.status === 'AwaitingApproval' ? 'Waiting for approval' : result.status}</h4>
              <p className="cust-note" style={{ margin: 0 }}>{result.message ?? (result.bookingId ? 'Your booking is confirmed - the check-in code is under My bookings.' : '')}</p>
              <div className="cust-hero-actions" style={{ marginTop: 10 }}>
                <Link className="btn btn-primary btn-sm" to="/my-bookings">My bookings</Link>
              </div>
            </div>
          )}
        </div>
      </section>

      <section className="card chart-card">
        <p className="chart-title">My requests</p>
        <p className="chart-subtitle">Everything you have asked the planner, newest first</p>
        {requestsLoading ? (
          <div className="loading-row"><span className="spinner spinner-dark" /></div>
        ) : (requests?.length ?? 0) === 0 ? (
          <div className="cust-empty">No requests yet.</div>
        ) : (
          <div className="cust-requests">
            {requests!.map((w) => (
              <div key={w.id} className="cust-request">
                <div>
                  <strong>{w.objective}</strong>
                  <span>{formatDateTime(w.createdAt)}{w.finalOutcome ? ` · ${w.finalOutcome}` : ''}{w.errorLog ? ` · ${w.errorLog}` : ''}</span>
                </div>
                <span className={`badge badge-${w.status === 'Completed' ? 'good' : w.status === 'Failed' || w.status === 'Rejected' ? 'critical' : w.status === 'AwaitingApproval' ? 'warning' : 'neutral'}`}>
                  <span className="badge-dot" />{w.status === 'AwaitingApproval' ? 'Awaiting approval' : w.status}
                </span>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
