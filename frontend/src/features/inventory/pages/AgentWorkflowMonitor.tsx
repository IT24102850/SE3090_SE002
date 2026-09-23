import { API_BASE_URL as apiBaseUrl } from '../../../api/apiBaseUrl';
import { useEffect, useState, useRef } from 'react';
import { Link } from 'react-router-dom';
import { LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer } from 'recharts';
import { Badge } from '../ui/Badge';
import { useChartTheme } from '../../../shared/useChartTheme';
import { Icon } from '../ui/Icon';
import { useSelector } from 'react-redux';
import { RootState } from '../../../store/store';
import { getStoredToken } from '../authToken';


type WorkflowItem = {
  id: string;
  created_at: string;
  actionType: string;
  payload: any;
  userRole: string;
  tenantId: string;
  riskLevel: string;
  validation_result: any;
  tool_result: any;
  llm_response: string | null;
  planJson: string | null;
  finalOutcome: string | null;
  errorLog: string | null;
  status: string;
};

function parseWorkflowJson(value: unknown): any {
  if (!value) return null;
  if (typeof value !== 'string') return value;
  try { return JSON.parse(value); } catch { return value; }
}

function readableWorkflowJson(value: unknown, emptyMessage: string) {
  const parsed = parseWorkflowJson(value);
  if (parsed == null || parsed === '' || (typeof parsed === 'object' && Object.keys(parsed).length === 0)) {
    return emptyMessage;
  }

  return typeof parsed === 'string' ? parsed : JSON.stringify(parsed, null, 2);
}

function workflowValidationSummary(workflow: WorkflowItem) {
  if (workflow.validation_result) return workflow.validation_result;
  const plan = parseWorkflowJson(workflow.planJson);
  const steps = plan?.steps ?? plan?.Steps;
  if (Array.isArray(steps)) {
    return {
      valid: workflow.status !== 'rejected' && workflow.status !== 'blocked',
      plannedActions: steps.length,
      status: workflow.status,
      note: 'Validation summary reconstructed from the stored workflow plan.'
    };
  }
  return null;
}

function workflowStatusDetail(workflow: WorkflowItem) {
  const confidence = workflow.validation_result?.confidence ?? workflow.tool_result?.confidence;
  if (confidence != null) return `Confidence ${formatWorkflowConfidence(confidence)}`;

  const plan = parseWorkflowJson(workflow.planJson);
  const steps = plan?.steps ?? plan?.Steps;
  const plannedCount = Array.isArray(steps) ? steps.length : 0;
  const createdCount = workflow.tool_result?.createdBookings;
  const skippedCount = workflow.tool_result?.skippedBookings;

  if (workflow.status === 'completed' && createdCount != null) {
    return `${createdCount} applied${skippedCount ? ` · ${skippedCount} skipped` : ''}`;
  }
  if (plannedCount > 0) return `${plannedCount} planned action${plannedCount === 1 ? '' : 's'}`;
  if (workflow.status === 'approved') return 'Ready to apply';
  if (workflow.status === 'rejected') return 'Decision declined';
  if (workflow.status === 'blocked') return 'Action blocked';
  return 'Awaiting decision';
}

function formatWorkflowConfidence(value: unknown) {
  const n = Number(value);
  if (Number.isNaN(n)) return String(value);
  return n > 0 && n <= 1 ? `${Math.round(n * 100)}%` : `${Math.round(n)}%`;
}

export function AgentWorkflowMonitorPage() {
  // Recharts takes SVG attributes, which cannot resolve var(), so the
  // sparkline reads its stroke from the theme hook rather than a literal.
  const chart = useChartTheme();
  const { user } = useSelector((state: RootState) => state.auth);
  const token = getStoredToken();
  const [items, setItems] = useState<WorkflowItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [loadError, setLoadError] = useState('');
  const [selected, setSelected] = useState<WorkflowItem | null>(null);

  function formatConfidence(c: any) {
    if (c == null) return 'N/A';
    const n = Number(c);
    if (Number.isNaN(n)) return String(c);
    if (n > 0 && n <= 1) return `${Math.round(n * 100)}%`;
    if (n > 1 && n <= 100) return `${Math.round(n)}%`;
    return `${n}`;
  }

  function summarizePayload(payload: any) {
    if (!payload) return '';
    try {
      const p = typeof payload === 'string' ? JSON.parse(payload) : payload;
      const keys = ['inventory_item_id','tenant_id','supplier_id','branchId','branch_id','current_stock','reorder_level','predicted_demand','quantity'];
      const found: string[] = [];
      for (const k of keys) {
        if (k in p) {
          found.push(`${k.replace(/_/g,' ')}:${String(p[k])}`);
        }
        if (found.length >= 3) break;
      }
      if (found.length) return found.join(' · ');
      // fallback: list first 2 keys
      const k2 = Object.keys(p).slice(0,2).map(k=>`${k}:${String(p[k])}`);
      if (k2.length) return k2.join(' · ');
      return '';
    } catch (e) {
      const s = String(payload || '');
      return s.length > 80 ? s.slice(0,80) + '…' : s;
    }
  }

  const [statusFilter, setStatusFilter] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  const prevIdsRef = useRef<string[]>([]);
  const [newIds, setNewIds] = useState<Set<string>>(new Set());

  async function fetchItems() {
    setLoading(true);
    try {
      if (!user?.tenantId) throw new Error('Your tenant could not be identified.');
      const params = new URLSearchParams({ tenantId: user.tenantId });
      if (statusFilter) params.set('status', ({ pending: 'AwaitingApproval', completed: 'Completed', approved: 'Approved', rejected: 'Rejected', blocked: 'Blocked' } as Record<string, string>)[statusFilter] ?? statusFilter);
      const resp = await fetch(`${apiBaseUrl}/agent/workflow?${params.toString()}`, {
        headers: token ? { Authorization: `Bearer ${token}` } : undefined,
      });
      if (!resp.ok) throw new Error(`Workflow request failed (${resp.status})`);
      const raw = await resp.json() as Array<Record<string, any>>;
      const data = raw
        .filter((workflow) => !search || `${workflow.objective} ${workflow.id}`.toLowerCase().includes(search.toLowerCase()))
        .map((workflow): WorkflowItem => ({
          id: String(workflow.id),
          created_at: workflow.createdAt,
          actionType: 'workflow',
          payload: workflow.objective,
          userRole: workflow.requestedByUserId ? 'Requested' : 'System',
          tenantId: workflow.tenantId,
          riskLevel: workflow.approvalStatus,
          validation_result: parseWorkflowJson(workflow.validationResults),
          tool_result: parseWorkflowJson(workflow.toolResultsJson) ?? (workflow.finalOutcome ? { notes: workflow.finalOutcome } : null),
          llm_response: workflow.errorLog || null,
          planJson: workflow.planJson || null,
          finalOutcome: workflow.finalOutcome || null,
          errorLog: workflow.errorLog || null,
          status: workflow.status === 'AwaitingApproval' ? 'pending' : workflow.status.toLowerCase(),
        }));
      setLoadError('');
      setItems(data);
      setLastUpdated(new Date());

      // detect new ids for entry animation
      const prev = prevIdsRef.current || [];
      const nowIds = data.map((i) => i.id);
      const added = nowIds.filter((id) => !prev.includes(id));
      setNewIds(new Set(added));
      prevIdsRef.current = nowIds;
    } catch (err) {
      console.error(err);
      setLoadError('Workflow history could not be loaded. Check your connection and access, then try again.');
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    fetchItems();
    const id = setInterval(fetchItems, 5000);
    return () => clearInterval(id);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [statusFilter, search, token, user?.tenantId]);

  async function approve(id: string) {
    try {
      const resp = await fetch(`${apiBaseUrl}/agent/workflow/${id}/approve`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
        body: JSON.stringify({ approverRole: 'Manager' }),
      });
      if (!resp.ok) throw new Error('approve failed');
      await fetchItems();
    } catch (err) {
      console.error(err);
      alert('Approve failed');
    }
  }

  async function reject(id: string) {
    const reason = prompt('Rejection reason (optional)') || 'rejected';
    try {
      const resp = await fetch(`${apiBaseUrl}/agent/workflow/${id}/reject`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
        body: JSON.stringify({ approverRole: 'Manager', reason }),
      });
      if (!resp.ok) throw new Error('reject failed');
      await fetchItems();
    } catch (err) {
      console.error(err);
      alert('Reject failed');
    }
  }

  const totalCount = items.length;
  const pendingCount = items.filter(i => i.status === 'pending').length;
  const approvedCount = items.filter(i => i.status === 'approved').length;
  const avgConfidence = items.reduce((acc, i) => acc + (Number(i.validation_result?.confidence ?? i.tool_result?.confidence ?? 0) || 0), 0) / Math.max(1, items.length);
  const statusLabel = (status: string) => ({
    pending: 'Awaiting review',
    approved: 'Approved',
    completed: 'Completed',
    rejected: 'Rejected',
    blocked: 'Blocked',
  }[status] ?? status);
  const statusTone = (status: string) => status === 'approved' ? 'green' : status === 'rejected' || status === 'blocked' ? 'red' : status === 'completed' ? 'violet' : 'amber';

  return (
    <div className="page">
      <header className="page-head workflow-page-head workflow-hero">
        <div className="workflow-hero-copy">
          <p className="eyebrow">AUTOMATION / WORKFLOWS</p>
          <h1>Agent Workflow Monitor</h1>
          <p className="page-sub">Review customer booking requests and staff schedule proposals saved by the backend. This page shows workflow history; the Gemini agent service runs separately.</p>
          <div className="workflow-hero-tags">
            <span>✦ AI-assisted</span><span>◉ Live updates</span><span>✓ Human controlled</span>
          </div>
        </div>
        <div className="workflow-hero-orbit" aria-hidden="true"><span>✦</span><i /><b /></div>
        <div className="page-actions workflow-filters">
          <input className="filter-select" placeholder="Search..." value={search} onChange={(e)=>setSearch(e.target.value)} />
          <select className="filter-select" value={statusFilter ?? ''} onChange={(e)=>setStatusFilter(e.target.value || null)}>
            <option value="">All status</option>
            <option value="pending">pending</option>
            <option value="blocked">blocked</option>
            <option value="completed">completed</option>
            <option value="approved">approved</option>
            <option value="rejected">rejected</option>
          </select>
          <button className="btn btn-secondary" onClick={() => fetchItems()}>Refresh</button>
        </div>
      </header>
      {loadError && <p className="page-notice" role="alert">⚠ {loadError}</p>}

      <div className="workflow-live-strip">
        <div className="live-indicator"><span /> Live monitoring{lastUpdated && <small>Updated {lastUpdated.toLocaleTimeString()}</small>}</div>
        <p>Workflow activity refreshes automatically every 5 seconds.</p>
      </div>

      <div className="workflow-kpi-grid">
        <div className="kpi-card workflow-kpi workflow-kpi-total">
          <div className="kpi-top"><div style={{display:'flex', gap:8, alignItems:'center'}}><Icon name="workflow" /><div className="kpi-label">Total Workflows</div></div><div className="kpi-value">{totalCount}</div></div>
        </div>
        <div className="kpi-card workflow-kpi workflow-kpi-review">
          <div className="kpi-top"><div style={{display:'flex', gap:8, alignItems:'center'}}><Icon name="predict" /><div className="kpi-label">Needs review</div></div><div className="kpi-value">{pendingCount}</div></div>
        </div>
        <div className="kpi-card workflow-kpi workflow-kpi-approved">
          <div className="kpi-top"><div style={{display:'flex', gap:8, alignItems:'center'}}><Icon name="approve" /><div className="kpi-label">Approved</div></div><div className="kpi-value">{approvedCount}</div></div>
        </div>
        <div className="kpi-card workflow-kpi workflow-kpi-confidence">
          <div className="kpi-top"><div style={{display:'flex', gap:8, alignItems:'center'}}><Icon name="chart" /><div className="kpi-label">Avg Confidence</div></div><div className="kpi-value">{formatConfidence(avgConfidence)}</div></div>
        </div>
      </div>

      {loading && <div className="workflow-loading" role="status"><span className="spinner spinner-dark" /> Syncing workflow activity…</div>}

      <div className="panel workflow-panel">
        <div className="panel-head">
          <div>
            <h2>Recent AI workflows</h2>
            <p className="hint">A clear audit trail of automated recommendations and human decisions.</p>
          </div>
          <span className="workflow-count">{items.length} {items.length === 1 ? 'workflow' : 'workflows'}</span>
        </div>

        <div className="table-wrap">
          {items.length === 0 ? (
            <div className="empty-state">
              <div className="workflow-empty-content">
                <div className="workflow-empty-icon">✦</div>
                <h3>No workflows match these filters</h3>
                <p className="hint">{search || statusFilter ? 'Try clearing a filter or refreshing the monitor.' : 'Start with the AI Planner to create a schedule proposal for this workspace.'}</p>
                <Link className="btn btn-primary" to="/planner">Open AI Planner</Link>
              </div>
            </div>
          ) : (
            <table className="data-table">
              <thead>
                <tr>
                  <th>Workflow</th>
                  <th>Source</th>
                  <th>Recommendation</th>
                  <th style={{width:160}}>Status</th>
                  <th style={{width:210}}>Review</th>
                </tr>
              </thead>
              <tbody>
                {items.map(it => (
                  <tr key={it.id} className={`hover-row workflow-row ${newIds.has(it.id) ? 'row-new' : ''}`}>
                    <td>
                      <div className="workflow-id"><span className="workflow-id-icon">✦</span><div><div className="cell-title">#{it.id.slice(0, 8)}</div>
                      <div className="cell-sub">{new Date(it.created_at).toLocaleString()}</div>
                      </div></div>
                    </td>
                    <td>
                      <div className="cell-title">{it.actionType}</div>
                      <div className="cell-sub">User: {it.userRole} · Tenant: {it.tenantId}</div>
                    </td>
                    <td>
                      {it.tool_result && it.tool_result.quantity ? (
                        <div>
                          <div className="cell-title">Qty: {it.tool_result.quantity}</div>
                          <div className="cell-sub">Est cost: {it.tool_result.totalCost ?? (it.tool_result.quantity * (it.tool_result.estimatedUnitCost ?? 0)).toFixed(2)}</div>
                        </div>
                      ) : (
                        <div className="cell-sub">{it.tool_result?.notes ?? summarizePayload(it.payload)}</div>
                      )}
                    </td>
                    <td>
                      <div style={{display:'flex', justifyContent:'flex-start', gap:8, alignItems:'center'}}>
                        <Badge tone={statusTone(it.status)} icon={it.status === 'completed' ? <Icon name="approve" /> : it.status === 'rejected' || it.status === 'blocked' ? <Icon name="info" /> : <Icon name="predict" />}>{statusLabel(it.status)}</Badge>
                        <div className="cell-sub status-detail">{workflowStatusDetail(it)}</div>
                      </div>
                    </td>
                    <td>
                      <div className="row-actions">
                        <button className="btn" onClick={() => setSelected(it)}>Details</button>
                        {it.status === 'pending' && (
                          <>
                              <button className="btn btn-primary" onClick={() => { approve(it.id); setNewIds(prev=>{ const copy=new Set(prev); copy.delete(it.id); return copy;}); }}>Approve</button>
                            <button className="btn btn-secondary" onClick={() => reject(it.id)}>Reject</button>
                          </>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {selected && (
        <div className="modal-overlay">
          <div className="modal">
            <div className="modal-head">
              <h3 className="modal-title">Workflow #{selected.id} details</h3>
              <div>
                <button className="modal-close" onClick={() => setSelected(null)}>×</button>
              </div>
            </div>
            <div className="modal-body">
              <div className="workflow-modal-grid">
                <div>
                  <h4 className="font-medium">Execution result</h4>
                  {selected.tool_result?.items && Array.isArray(selected.tool_result.items) ? (
                    <div className="table-wrap">
                      <table className="data-table">
                        <thead>
                          <tr><th>SKU</th><th>Desc</th><th>Qty</th><th>Unit</th><th>Est cost</th></tr>
                        </thead>
                        <tbody>
                          {selected.tool_result.items.map((it:any, idx:number)=>(
                            <tr key={idx}><td>{it.sku ?? it.productId ?? ''}</td><td>{it.description ?? it.name ?? ''}</td><td>{it.quantity ?? it.qty ?? ''}</td><td>{it.unit ?? ''}</td><td>{it.unitCost ?? it.estimatedUnitCost ?? ''}</td></tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  ) : (
                    <div className="workflow-detail-callout">
                      <strong>{selected.finalOutcome || selected.tool_result?.notes || 'No execution result was recorded.'}</strong>
                      {selected.status === 'completed' && <span>The workflow completed and the planned schedule was updated.</span>}
                    </div>
                  )}

                  <h4 className="mt-3 font-medium">Planned actions</h4>
                  <pre className="workflow-json workflow-json-short">{readableWorkflowJson(selected.planJson, 'No plan details were recorded for this workflow.')}</pre>

                  <h4 className="mt-3 font-medium">Validation</h4>
                  <pre className="workflow-json workflow-json-short">{readableWorkflowJson(workflowValidationSummary(selected), 'No validation data was recorded for this workflow.')}</pre>

                  <h4 className="mt-3 font-medium">Decision notes</h4>
                  <pre className="workflow-json workflow-json-short">{readableWorkflowJson(selected.llm_response, selected.errorLog ? `Workflow note: ${selected.errorLog}` : 'This workflow used the deterministic scheduling planner; no LLM reasoning was generated.')}</pre>
                </div>
                <div>
                  <h4 className="font-medium">Decision evidence</h4>
                  {selected.validation_result?.auditLog && (
                    <div className="text-xs text-slate-600 mb-2">Confidence: {formatConfidence(selected.validation_result?.confidence ?? selected.tool_result?.confidence)}</div>
                  )}

                  {selected.tool_result && selected.tool_result.predictedDailyDemand && (
                    <div style={{ height: 220 }}>
                      <ResponsiveContainer>
                        <LineChart data={[0,1,2,3,4,5,6].map((x)=>({x, y: selected.tool_result.predictedDailyDemand*(1 + (x-3)/12)}))}>
                          <XAxis dataKey="x" />
                          <YAxis />
                          <Tooltip />
                          <Line type="monotone" dataKey="y" stroke={chart.series.blue} strokeWidth={3} dot={false} isAnimationActive={true} animationDuration={900} />
                        </LineChart>
                      </ResponsiveContainer>
                    </div>
                  )}

                  {selected.tool_result?.backend_response && (
                    <div className="mt-3">
                      <h5 className="font-medium">Backend PO</h5>
                      <pre className="workflow-json workflow-json-tall">{JSON.stringify(selected.tool_result.backend_response, null, 2)}</pre>
                    </div>
                  )}
                  {!selected.tool_result?.predictedDailyDemand && !selected.tool_result?.backend_response && (
                    <div className="workflow-detail-callout workflow-detail-neutral">
                      <strong>Schedule planning evidence</strong>
                      <span>This workflow was evaluated using resource availability, opening hours, existing bookings, and booking duration. Demand prediction evidence does not apply to this schedule workflow.</span>
                    </div>
                  )}

                  <div className="mt-4 modal-actions">
                    {selected.actionType === 'generate_purchase_order' && selected.status !== 'approved' && (
                      <>
                        <button className="btn btn-primary" onClick={() => { approve(selected.id); setSelected(null); }}>Approve</button>
                        <button className="btn btn-secondary" onClick={() => { reject(selected.id); setSelected(null); }}>Reject</button>
                      </>
                    )}
                    <button className="btn" onClick={() => setSelected(null)}>Close</button>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
