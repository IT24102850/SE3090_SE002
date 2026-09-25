import { useState } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../store/store';
import { useToast, apiErrorMessage } from '../../shared/components/Toast';
import Modal from '../../shared/components/Modal';
import {
  useCreateStaffMutation,
  useGetBranchesQuery,
  useGetStaffUsersQuery,
  useUpdateStaffMemberMutation,
} from '../../api/bookingApi';

// FR-AS2: Admin/Manager creates, edits, and deactivates Staff accounts and
// assigns them to a branch. (Specialty stays on the Resource side — see
// ResourceFormModal's "Linked staff login" — so it isn't duplicated here.)
export default function StaffManagementPage() {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';
  const isAdmin = user?.role === 'Admin';
  const { show } = useToast();

  const { data: staff, isLoading } = useGetStaffUsersQuery({ tenantId, includeInactive: true }, { skip: !tenantId });
  const { data: branches } = useGetBranchesQuery({ tenantId }, { skip: !tenantId });
  const [updateStaff] = useUpdateStaffMemberMutation();
  const [showCreate, setShowCreate] = useState(false);

  const handleBranchChange = async (id: string, branchId: string) => {
    try {
      await updateStaff({ id, branchId: branchId || null }).unwrap();
      show('Branch updated.', 'success');
    } catch (err) {
      show(apiErrorMessage(err, 'Could not update branch.'), 'error');
    }
  };

  const handleToggleActive = async (id: string, isActive: boolean) => {
    try {
      await updateStaff({ id, isActive: !isActive }).unwrap();
      show(!isActive ? 'Account reactivated.' : 'Account deactivated.', 'success');
    } catch (err) {
      show(apiErrorMessage(err, 'Could not update account.'), 'error');
    }
  };

  return (
    <div>
      <div className="page-header">
        <div>
          <h1 className="page-title">Staff</h1>
          <p className="page-subtitle">Create staff/manager logins and assign them to a branch.</p>
        </div>
        <button className="btn btn-primary" onClick={() => setShowCreate(true)}>+ New staff account</button>
      </div>

      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Email</th>
              <th>Role</th>
              <th>Branch</th>
              <th>Status</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {isLoading && (
              <tr><td colSpan={6} className="loading-row"><span className="spinner spinner-dark" /> Loading…</td></tr>
            )}
            {!isLoading && (!staff || staff.length === 0) && (
              <tr><td colSpan={6} className="empty-state">No staff accounts yet.</td></tr>
            )}
            {staff?.map((s) => {
              const canEdit = isAdmin || s.role === 'Staff';
              return (
                <tr key={s.id}>
                  <td style={{ fontWeight: 600 }}>{s.fullName}</td>
                  <td>{s.email}</td>
                  <td><span className="badge">{s.role}</span></td>
                  <td>
                    <select
                      className="input"
                      style={{ padding: '4px 8px', fontSize: 12, width: 'auto' }}
                      value={s.branchId ?? ''}
                      disabled={!canEdit}
                      onChange={(e) => handleBranchChange(s.id, e.target.value)}
                    >
                      <option value="">Unassigned</option>
                      {branches?.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
                    </select>
                  </td>
                  <td>
                    <span className={`badge badge-${s.isActive ? 'good' : 'neutral'}`}>{s.isActive ? 'Active' : 'Inactive'}</span>
                  </td>
                  <td>
                    {canEdit && (
                      <button className="btn btn-ghost btn-sm" onClick={() => handleToggleActive(s.id, !!s.isActive)}>
                        {s.isActive ? 'Deactivate' : 'Reactivate'}
                      </button>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {showCreate && (
        <CreateStaffModal tenantId={tenantId} isAdmin={isAdmin} onClose={() => setShowCreate(false)} />
      )}
    </div>
  );
}

function CreateStaffModal({ tenantId, isAdmin, onClose }: { tenantId: string; isAdmin: boolean; onClose: () => void }) {
  const { show } = useToast();
  const { data: branches } = useGetBranchesQuery({ tenantId }, { skip: !tenantId });
  const [createStaff, { isLoading }] = useCreateStaffMutation();

  const [fullName, setFullName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [phone, setPhone] = useState('');
  const [branchId, setBranchId] = useState('');
  const [role, setRole] = useState<'Staff' | 'Manager'>('Staff');
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    try {
      await createStaff({
        email, password, fullName, phone: phone || undefined, branchId: branchId || undefined, role,
      }).unwrap();
      show('Staff account created.', 'success');
      onClose();
    } catch (err) {
      setError(apiErrorMessage(err, 'Could not create account.'));
    }
  };

  return (
    <Modal
      title="New staff account"
      onClose={onClose}
      footer={
        <>
          <button className="btn btn-secondary" onClick={onClose} type="button">Cancel</button>
          <button className="btn btn-primary" onClick={handleSubmit} disabled={isLoading}>
            {isLoading ? <span className="spinner" /> : 'Create account'}
          </button>
        </>
      }
    >
      <form onSubmit={handleSubmit}>
        {error && <div className="banner banner-critical">{error}</div>}
        <div className="form-grid">
          <div className="field field-full">
            <label>Full name</label>
            <input className="input" value={fullName} onChange={(e) => setFullName(e.target.value)} required />
          </div>
          <div className="field">
            <label>Email</label>
            <input className="input" type="email" value={email} onChange={(e) => setEmail(e.target.value)} required />
          </div>
          <div className="field">
            <label>Temporary password</label>
            <input className="input" type="password" minLength={6} value={password} onChange={(e) => setPassword(e.target.value)} required />
          </div>
          <div className="field">
            <label>Phone</label>
            <input className="input" value={phone} onChange={(e) => setPhone(e.target.value)} />
          </div>
          <div className="field">
            <label>Branch</label>
            <select className="input" value={branchId} onChange={(e) => setBranchId(e.target.value)}>
              <option value="">Unassigned</option>
              {branches?.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
            </select>
          </div>
          {isAdmin && (
            <div className="field">
              <label>Role</label>
              <select className="input" value={role} onChange={(e) => setRole(e.target.value as 'Staff' | 'Manager')}>
                <option value="Staff">Staff</option>
                <option value="Manager">Manager</option>
              </select>
            </div>
          )}
        </div>
      </form>
    </Modal>
  );
}
