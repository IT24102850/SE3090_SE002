import { useEffect, useState, useRef } from 'react';
import { LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer } from 'recharts';
import { Badge } from '../ui/Badge';
import { Icon } from '../ui/Icon';

type WorkflowItem = {
  id: number;
  created_at: string;
  actionType: string;
  payload: any;
  userRole: string;
  tenantId: string;
  riskLevel: string;
  validation_result: any;
  tool_result: any;
  llm_response: string | null;
  status: string;
};

export function AgentWorkflowMonitorPage() {
  const [items, setItems] = useState<WorkflowItem[]>([]);
  const [loading, setLoading] = useState(false);
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

  const [page, setPage] = useState(1);
  const [pageSize] = useState(10);
  const [, setTotal] = useState<number | null>(null);
  const [statusFilter, setStatusFilter] = useState<string | null>(null);
  const [actionFilter, setActionFilter] = useState<string | null>(null);
  const [tenantFilter, setTenantFilter] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const prevIdsRef = useRef<number[]>([]);
  const [newIds, setNewIds] = useState<Set<number>>(new Set());

  async function fetchItems() {
    setLoading(true);
    try {
      const params = new URLSearchParams();
      params.set('page', String(page));
      params.set('pageSize', String(pageSize));
      if (statusFilter) params.set('status', statusFilter);
      if (actionFilter) params.set('actionType', actionFilter);
      if (tenantFilter) params.set('tenantId', tenantFilter);
      if (search) params.set('search', search);
      const url = `http://localhost:8000/workflows?${params.toString()}`;
      const resp = await fetch(url);
      if (!resp.ok) throw new Error('fetch failed');
      const data = await resp.json();
      setItems(data.items || []);
      setTotal(data.total ?? null);

      // detect new ids for entry animation
      const prev = prevIdsRef.current || [];
      const nowIds = (data.items || []).map((i: any) => i.id);
      const added = nowIds.filter((id: number) => !prev.includes(id));
      setNewIds(new Set(added));
      prevIdsRef.current = nowIds;
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    fetchItems();
    const id = setInterval(fetchItems, 5000);
    return () => clearInterval(id);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page, pageSize, statusFilter, actionFilter, tenantFilter, search]);

  async function approve(id: number) {
    try {
      const resp = await fetch(`http://localhost:8000/workflows/${id}/approve`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ approverRole: 'Manager' }),
      });
      if (!resp.ok) throw new Error('approve failed');
      await fetchItems();
    } catch (err) {
      console.error(err);
      alert('Approve failed');
    }
  }

  async function reject(id: number) {
    const reason = prompt('Rejection reason (optional)') || 'rejected';
    try {
      const resp = await fetch(`http://localhost:8000/workflows/${id}/reject`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
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

  return (
    <div className="p-4 page page-head">
      <div className="page-head">
        <div>
          <h2 className="text-2xl font-semibold mb-1">Agent Workflow Monitor</h2>
          <p className="page-sub">View AI-generated purchase orders, approve/reject auto-reorders, and inspect prediction evidence.</p>
        </div>
        <div className="page-actions">
          <input className="filter-select" placeholder="Search..." value={search} onChange={(e)=>{ setSearch(e.target.value); setPage(1); }} />
          <select className="filter-select" value={statusFilter ?? ''} onChange={(e)=>{ setStatusFilter(e.target.value || null); setPage(1); }}>
            <option value="">All status</option>
            <option value="pending">pending</option>
            <option value="blocked">blocked</option>
            <option value="completed">completed</option>
            <option value="approved">approved</option>
            <option value="rejected">rejected</option>
          </select>
          <select className="filter-select" value={actionFilter ?? ''} onChange={(e)=>{ setActionFilter(e.target.value || null); setPage(1); }}>
            <option value="">All actions</option>
            <option value="generate_purchase_order">generate_purchase_order</option>
            <option value="predict_demand">predict_demand</option>
            <option value="send_notification">send_notification</option>
          </select>
          <input className="filter-select" placeholder="Tenant ID" value={tenantFilter ?? ''} onChange={(e)=>{ setTenantFilter(e.target.value || null); setPage(1); }} />
          <button className="btn btn-secondary" onClick={() => fetchItems()}>Refresh</button>
        </div>
      </div>

      <div style={{display:'grid', gridTemplateColumns:'repeat(4,1fr)', gap:12, marginTop:12, marginBottom:12}}>
        <div className="kpi-card">
          <div className="kpi-top"><div style={{display:'flex', gap:8, alignItems:'center'}}><Icon name="workflow" /><div className="kpi-label">Total Workflows</div></div><div className="kpi-value">{totalCount}</div></div>
        </div>
        <div className="kpi-card">
          <div className="kpi-top"><div style={{display:'flex', gap:8, alignItems:'center'}}><Icon name="predict" /><div className="kpi-label">Pending</div></div><div className="kpi-value">{pendingCount}</div></div>
        </div>
        <div className="kpi-card">
          <div className="kpi-top"><div style={{display:'flex', gap:8, alignItems:'center'}}><Icon name="approve" /><div className="kpi-label">Approved</div></div><div className="kpi-value">{approvedCount}</div></div>
        </div>
        <div className="kpi-card">
          <div className="kpi-top"><div style={{display:'flex', gap:8, alignItems:'center'}}><Icon name="chart" /><div className="kpi-label">Avg Confidence</div></div><div className="kpi-value">{formatConfidence(avgConfidence)}</div></div>
        </div>
      </div>

      {loading && <div className="panel p-6">Loading workflows…</div>}

      <div className="panel">
        <div className="panel-head">
          <h2>Recent AI Workflows</h2>
          <p className="hint">Automatically generated suggestions from the demand prediction agent.</p>
        </div>

        <div className="table-wrap">
          {items.length === 0 ? (
            <div className="empty-state">
              <div style={{maxWidth:420, margin: '0 auto'}}>
                <h3>No AI workflows yet</h3>
                <p className="hint">Generate a workflow by posting to <code>/workflows/execute</code> or wait for the agent to produce suggestions.</p>
                <div style={{marginTop:12}}>
                  <button className="btn btn-primary" onClick={() => {
                    // create a lightweight demo workflow
                    const demo = {
                      actionType: 'generate_purchase_order',
                      payload: { current_stock: 3, reorder_level: 20, historicUsageDays: [2,3,4,2,1,5,3], estimatedUnitCost: 9.5, branchId: '11111111-1111-1111-1111-111111111111', supplierId: '22222222-2222-2222-2222-222222222222', budget_limit: 1000 },
                      userRole: 'Manager', tenantId: 'tenant-demo'
                    };
                    fetch('http://localhost:8000/workflows/execute', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(demo) }).then(()=>fetchItems());
                  }}>Create demo workflow</button>
                </div>
              </div>
            </div>
          ) : (
            <table className="data-table">
              <thead>
                <tr>
                  <th>When</th>
                  <th>Action</th>
                  <th>Suggestion</th>
                  <th style={{width:140}}>Status</th>
                  <th style={{width:210}}>Actions</th>
                </tr>
              </thead>
              <tbody>
                {items.map(it => (
                  <tr key={it.id} className={`hover-row ${newIds.has(it.id) ? 'row-new' : ''}`}>
                    <td>
                      <div className="cell-title">#{it.id}</div>
                      <div className="cell-sub">{new Date(it.created_at).toLocaleString()}</div>
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
                        <Badge tone={it.status === 'approved' ? 'green' : it.status === 'rejected' ? 'red' : it.status === 'completed' ? 'violet' : 'amber'} icon={it.actionType === 'generate_purchase_order' ? <Icon name="po" /> : it.actionType === 'predict_demand' ? <Icon name="predict" /> : <Icon name="info" />}>{it.status}</Badge>
                        <div className="cell-sub">{formatConfidence(it.validation_result?.confidence ?? it.tool_result?.confidence)}</div>
                      </div>
                    </td>
                    <td>
                      <div className="row-actions">
                        <button className="btn" onClick={() => setSelected(it)}>Details</button>
                        {it.actionType === 'generate_purchase_order' && it.status !== 'approved' && (
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
              <div style={{display:'grid', gridTemplateColumns:'1fr 360px', gap:16}}>
                <div>
                  <h4 className="font-medium">Tool result</h4>
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
                    <pre className="text-xs p-2 bg-slate-50 rounded max-h-60 overflow-auto">{JSON.stringify(selected.tool_result, null, 2)}</pre>
                  )}

                  <h4 className="mt-3 font-medium">Validation</h4>
                  <pre className="text-xs p-2 bg-slate-50 rounded max-h-40 overflow-auto">{JSON.stringify(selected.validation_result, null, 2)}</pre>

                  <h4 className="mt-3 font-medium">LLM reasoning</h4>
                  <pre className="text-xs p-2 bg-slate-50 rounded max-h-40 overflow-auto">{selected.llm_response}</pre>
                </div>
                <div>
                  <h4 className="font-medium">Prediction evidence</h4>
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
                          <Line type="monotone" dataKey="y" stroke="#7c3aed" strokeWidth={3} dot={false} isAnimationActive={true} animationDuration={900} />
                        </LineChart>
                      </ResponsiveContainer>
                    </div>
                  )}

                  {selected.tool_result?.backend_response && (
                    <div className="mt-3">
                      <h5 className="font-medium">Backend PO</h5>
                      <pre className="text-xs p-2 bg-slate-50 rounded max-h-36 overflow-auto">{JSON.stringify(selected.tool_result.backend_response, null, 2)}</pre>
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
