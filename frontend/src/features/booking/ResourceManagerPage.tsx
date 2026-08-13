import { useState } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../store/store';
import { useDeleteResourceMutation, useGetResourcesQuery } from '../../api/bookingApi';
import { useToast, apiErrorMessage } from '../../shared/components/Toast';
import ResourceFormModal from './ResourceFormModal';
import ResourceDetailPanel from './ResourceDetailPanel';
import { RESOURCE_CATEGORIES, type Resource } from './types';

const STATUS_TONE: Record<string, string> = {
  Available: 'good',
  Reserved: 'primary',
  UnderMaintenance: 'warning',
  Archived: 'neutral',
};

export default function ResourceManagerPage() {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';
  const { show } = useToast();

  const [category, setCategory] = useState('');
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState<Resource | null>(null);
  const [selected, setSelected] = useState<Resource | null>(null);

  const { data, isLoading } = useGetResourcesQuery(
    { tenantId, category: category || undefined, search: search || undefined, page, pageSize: 10 },
    { skip: !tenantId }
  );
  const [deleteResource] = useDeleteResourceMutation();

  const handleDelete = async (r: Resource) => {
    if (!window.confirm(`Archive "${r.name}"? It will no longer be bookable.`)) return;
    try {
      await deleteResource(r.id).unwrap();
      show('Resource archived.', 'success');
      if (selected?.id === r.id) setSelected(null);
    } catch (err) {
      show(apiErrorMessage(err, 'Could not archive resource — it may have upcoming bookings.'), 'error');
    }
  };

  return (
    <div>
      <div className="page-header">
        <div>
          <h1 className="page-title">Resource Manager</h1>
          <p className="page-subtitle">Rooms, tables, vehicles and equipment, with weekly hours and live availability.</p>
        </div>
        <button className="btn btn-primary" onClick={() => { setEditing(null); setShowForm(true); }}>+ New resource</button>
      </div>

      {selected && <ResourceDetailPanel resource={selected} onClose={() => setSelected(null)} />}

      <div className="filter-bar">
        <input className="input" placeholder="Search resources…" value={search} onChange={(e) => { setSearch(e.target.value); setPage(1); }} style={{ minWidth: 220 }} />
        <select className="input" value={category} onChange={(e) => { setCategory(e.target.value); setPage(1); }}>
          <option value="">All categories</option>
          {RESOURCE_CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
        </select>
      </div>

      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Category</th>
              <th>Capacity</th>
              <th>Rate</th>
              <th>Status</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {isLoading && <tr><td colSpan={6} className="loading-row"><span className="spinner spinner-dark" /> Loading…</td></tr>}
            {!isLoading && (data?.items.length ?? 0) === 0 && (
              <tr><td colSpan={6} className="empty-state">No resources yet. Create your first one.</td></tr>
            )}
            {data?.items.map((r) => (
              <tr key={r.id}>
                <td>
                  <div style={{ fontWeight: 600 }}>{r.name}</div>
                  {r.code && <div style={{ fontSize: 12, color: 'var(--color-text-muted)' }}>{r.code}</div>}
                </td>
                <td>{r.category}</td>
                <td>{r.capacity ?? '—'}</td>
                <td>{r.hourlyRate ? `$${r.hourlyRate.toFixed(2)}/hr` : '—'}</td>
                <td><span className={`badge badge-${STATUS_TONE[r.status] ?? 'neutral'}`}>{r.status}</span></td>
                <td>
                  <div style={{ display: 'flex', gap: 6 }}>
                    <button className="btn btn-secondary btn-sm" onClick={() => setSelected(r)}>Manage</button>
                    <button className="btn btn-ghost btn-sm" onClick={() => { setEditing(r); setShowForm(true); }}>Edit</button>
                    <button className="btn btn-danger btn-sm" onClick={() => handleDelete(r)}>Archive</button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {data && data.totalPages > 1 && (
        <div style={{ display: 'flex', justifyContent: 'center', gap: 8, marginTop: 16 }}>
          <button className="btn btn-secondary btn-sm" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>Previous</button>
          <span style={{ alignSelf: 'center', fontSize: 13, color: 'var(--color-text-secondary)' }}>Page {page} of {data.totalPages}</span>
          <button className="btn btn-secondary btn-sm" disabled={page >= data.totalPages} onClick={() => setPage((p) => p + 1)}>Next</button>
        </div>
      )}

      {showForm && (
        <ResourceFormModal tenantId={tenantId} resource={editing} onClose={() => setShowForm(false)} />
      )}
    </div>
  );
}
