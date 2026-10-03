import { useState } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../store/store';
import { useToast, apiErrorMessage } from '../../shared/components/Toast';
import Modal from '../../shared/components/Modal';
import { useConfirmation } from '../../shared/components/ConfirmationProvider';
import {
  useCreateStaffMutation,
  useGetBranchesQuery,
  useGetStaffUsersQuery,
  useUpdateStaffMemberMutation,
} from '../../api/bookingApi';
import type { StaffUser } from '../booking/types';

// FR-AS2: Admin/Manager creates, edits, and deactivates Staff accounts and
// assigns them to a branch. (Specialty stays on the Resource side — see
// ResourceFormModal's "Linked staff login" — so it isn't duplicated here.)
export default function StaffManagementPage() {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';
  const isAdmin = user?.role === 'Admin';
  const { show } = useToast();
  const confirm = useConfirmation();

  const { data: staff, isLoading } = useGetStaffUsersQuery({ tenantId, includeInactive: true }, { skip: !tenantId });
  const { data: branches } = useGetBranchesQuery({ tenantId }, { skip: !tenantId });
  const [updateStaff] = useUpdateStaffMemberMutation();
  const [showCreate, setShowCreate] = useState(false);
  const [editingStaff, setEditingStaff] = useState<StaffUser | null>(null);

  const handleBranchChange = async (id: string, currentBranchId: string | null | undefined, branchId: string) => {
    if (branchId === (currentBranchId ?? '')) return;
    const branchName = branches?.find((branch) => branch.id === branchId)?.name;
    if (!await confirm({
      title: 'Change staff branch assignment?',
      message: `This changes which branch this staff account is assigned to${branchName ? ` (${branchName})` : ''}.`,
      confirmLabel: 'Change assignment',
    })) return;
    try {
      await updateStaff({ id, branchId: branchId || undefined, clearBranch: !branchId }).unwrap();
      show('Branch updated.', 'success');
    } catch (err) {
      show(apiErrorMessage(err, 'Could not update branch.'), 'error');
    }
  };

  const handleToggleActive = async (id: string, isActive: boolean) => {
    if (isActive && !await confirm({
      title: 'Deactivate this staff account?',
      message: 'This person will no longer be able to sign in. You can reactivate the account later.',
      confirmLabel: 'Deactivate account',
      tone: 'danger',
    })) return;
    try {
      await updateStaff({ id, isActive: !isActive }).unwrap();
      show(!isActive ? 'Account reactivated.' : 'Staff account deactivated.', 'success');
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
                      onChange={(e) => handleBranchChange(s.id, s.branchId, e.target.value)}
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
                      <div style={{ display: 'flex', gap: 6 }}>
                        <button className="btn btn-ghost btn-sm" onClick={() => setEditingStaff(s)}>Edit</button>
                        <button
                          className={s.isActive ? 'btn btn-danger btn-sm' : 'btn btn-ghost btn-sm'}
                          onClick={() => handleToggleActive(s.id, !!s.isActive)}
                        >
                          {s.isActive ? 'Delete' : 'Reactivate'}
                        </button>
                      </div>
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
      {editingStaff && (
        <EditStaffModal
          staff={editingStaff}
          tenantId={tenantId}
          isAdmin={isAdmin}
          onClose={() => setEditingStaff(null)}
        />
      )}
    </div>
  );
}

function EditStaffModal({ staff, tenantId, isAdmin, onClose }: { staff: StaffUser; tenantId: string; isAdmin: boolean; onClose: () => void }) {
  const { show } = useToast();
  const confirm = useConfirmation();
  const { data: branches } = useGetBranchesQuery({ tenantId }, { skip: !tenantId });
  const [updateStaff, { isLoading }] = useUpdateStaffMemberMutation();
  const [fullName, setFullName] = useState(staff.fullName);
  const [phone, setPhone] = useState(staff.phone ?? '');
  const [branchId, setBranchId] = useState(staff.branchId ?? '');
  const [role, setRole] = useState<StaffUser['role']>(staff.role);
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    const roleChanged = isAdmin && role !== staff.role;
    const branchChanged = branchId !== (staff.branchId ?? '');
    if ((roleChanged || branchChanged) && !await confirm({
      title: roleChanged ? 'Change staff account access?' : 'Change staff branch assignment?',
      message: [
        roleChanged ? `This changes this account's role from ${staff.role} to ${role}.` : '',
        branchChanged ? 'This changes which branch the staff account is assigned to.' : '',
      ].filter(Boolean).join(' '),
      confirmLabel: 'Save access changes',
    })) return;
    try {
      await updateStaff({
        id: staff.id,
        fullName: fullName.trim(),
        phone,
        branchId: branchId || undefined,
        clearBranch: !branchId,
        ...(isAdmin ? { role } : {}),
      }).unwrap();
      show('Staff account updated.', 'success');
      onClose();
    } catch (err) {
      setError(apiErrorMessage(err, 'Could not update staff account.'));
    }
  };

  return (
    <Modal
      title="Edit staff account"
      onClose={onClose}
      footer={
        <>
          <button className="btn btn-secondary" onClick={onClose} type="button">Cancel</button>
          <button className="btn btn-primary" onClick={handleSubmit} disabled={isLoading}>
            {isLoading ? <span className="spinner" /> : 'Save changes'}
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
          <div className="field field-full">
            <label>Email</label>
            <input className="input" type="email" value={staff.email} disabled />
          </div>
          <div className="field">
            <label>Phone</label>
            <input className="input" value={phone} onChange={(e) => setPhone(e.target.value)} />
          </div>
          <div className="field">
            <label>Branch</label>
            <select className="input" value={branchId} onChange={(e) => setBranchId(e.target.value)}>
              <option value="">Unassigned</option>
              {branches?.map((branch) => <option key={branch.id} value={branch.id}>{branch.name}</option>)}
            </select>
          </div>
          {isAdmin && (
            <div className="field">
              <label>Role</label>
              <select className="input" value={role} onChange={(e) => setRole(e.target.value as StaffUser['role'])}>
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

function CreateStaffModal({ tenantId, isAdmin, onClose }: { tenantId: string; isAdmin: boolean; onClose: () => void }) {
  const { show } = useToast();
  const confirm = useConfirmation();
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
    if (role === 'Manager' && !await confirm({
      title: 'Create a Manager account?',
      message: 'Managers can access staff and operational features for this business.',
      confirmLabel: 'Create Manager account',
    })) return;
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
