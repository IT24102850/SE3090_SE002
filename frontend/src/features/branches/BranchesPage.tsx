import { useState } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../store/store';
import { useToast, apiErrorMessage } from '../../shared/components/Toast';
import Modal from '../../shared/components/Modal';
import { useCreateBranchMutation, useDeleteBranchMutation, useGetBranchesQuery, useUpdateBranchMutation } from '../../api/bookingApi';
import type { Branch } from '../booking/types';

// FR-AS4: branch create/edit/deactivate.
export default function BranchesPage() {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';
  const { show } = useToast();

  const { data: branches, isLoading } = useGetBranchesQuery({ tenantId }, { skip: !tenantId });
  const [deleteBranch] = useDeleteBranchMutation();
  const [editing, setEditing] = useState<Branch | 'new' | null>(null);

  const handleDeactivate = async (id: string) => {
    if (!window.confirm('Deactivate this branch?')) return;
    try {
      await deleteBranch(id).unwrap();
      show('Branch deactivated.', 'success');
    } catch (err) {
      show(apiErrorMessage(err, 'Could not deactivate branch.'), 'error');
    }
  };

  return (
    <div>
      <div className="page-header">
        <div>
          <h1 className="page-title">Branches</h1>
          <p className="page-subtitle">Manage your business's physical locations.</p>
        </div>
        <button className="btn btn-primary" onClick={() => setEditing('new')}>+ New branch</button>
      </div>

      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr><th>Name</th><th>Address</th><th>Phone</th><th></th></tr>
          </thead>
          <tbody>
            {isLoading && <tr><td colSpan={4} className="loading-row"><span className="spinner spinner-dark" /> Loading…</td></tr>}
            {!isLoading && (!branches || branches.length === 0) && (
              <tr><td colSpan={4} className="empty-state">No branches yet.</td></tr>
            )}
            {branches?.map((b) => (
              <tr key={b.id}>
                <td style={{ fontWeight: 600 }}>{b.name}</td>
                <td>{b.address || '—'}</td>
                <td>{b.phone || '—'}</td>
                <td>
                  <div style={{ display: 'flex', gap: 6 }}>
                    <button className="btn btn-ghost btn-sm" onClick={() => setEditing(b)}>Edit</button>
                    <button className="btn btn-danger btn-sm" onClick={() => handleDeactivate(b.id)}>Deactivate</button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {editing && <BranchFormModal tenantId={tenantId} branch={editing === 'new' ? null : editing} onClose={() => setEditing(null)} />}
    </div>
  );
}

function BranchFormModal({ tenantId, branch, onClose }: { tenantId: string; branch: Branch | null; onClose: () => void }) {
  const { show } = useToast();
  const [createBranch, { isLoading: creating }] = useCreateBranchMutation();
  const [updateBranch, { isLoading: updating }] = useUpdateBranchMutation();

  const [name, setName] = useState(branch?.name ?? '');
  const [address, setAddress] = useState(branch?.address ?? '');
  const [phone, setPhone] = useState(branch?.phone ?? '');
  const [error, setError] = useState<string | null>(null);
  const isLoading = creating || updating;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    try {
      if (branch) {
        await updateBranch({ id: branch.id, body: { name, address, phone } }).unwrap();
        show('Branch updated.', 'success');
      } else {
        await createBranch({ tenantId, name, address: address || undefined, phone: phone || undefined }).unwrap();
        show('Branch created.', 'success');
      }
      onClose();
    } catch (err) {
      setError(apiErrorMessage(err, 'Could not save branch.'));
    }
  };

  return (
    <Modal
      title={branch ? 'Edit branch' : 'New branch'}
      onClose={onClose}
      footer={
        <>
          <button className="btn btn-secondary" onClick={onClose} type="button">Cancel</button>
          <button className="btn btn-primary" onClick={handleSubmit} disabled={isLoading}>
            {isLoading ? <span className="spinner" /> : branch ? 'Save changes' : 'Create branch'}
          </button>
        </>
      }
    >
      <form onSubmit={handleSubmit}>
        {error && <div className="banner banner-critical">{error}</div>}
        <div className="form-grid">
          <div className="field field-full">
            <label>Name</label>
            <input className="input" value={name} onChange={(e) => setName(e.target.value)} required />
          </div>
          <div className="field field-full">
            <label>Address</label>
            <input className="input" value={address} onChange={(e) => setAddress(e.target.value)} />
          </div>
          <div className="field field-full">
            <label>Phone</label>
            <input className="input" value={phone} onChange={(e) => setPhone(e.target.value)} />
          </div>
        </div>
      </form>
    </Modal>
  );
}
