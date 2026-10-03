import { FormEvent, useEffect, useState } from 'react';
import { getStoredToken } from '../features/inventory/authToken';
import { useToast } from '../features/inventory/ui/ToastContext';
import { useConfirmation } from '../shared/components/ConfirmationProvider';
import './ManageUsersPage.css';

type ManagedUser = { id: string; fullName: string; email: string; phone: string; role: 'Admin' | 'Manager' | 'Staff'; branchId: string | null; isApproved: boolean };
type Branch = { id: string; name: string };
const emptyForm = { fullName: '', email: '', phone: '', password: '', role: 'Staff' as ManagedUser['role'], branchId: '' };

export function ManageUsersPage() {
  const token = getStoredToken();
  const { notify } = useToast();
  const confirm = useConfirmation();
  const [users, setUsers] = useState<ManagedUser[]>([]);
  const [pendingUsers, setPendingUsers] = useState<ManagedUser[]>([]);
  const [branches, setBranches] = useState<Branch[]>([]);
  const [form, setForm] = useState(emptyForm);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [updatingId, setUpdatingId] = useState<string | null>(null);
  const [editingUser, setEditingUser] = useState<ManagedUser | null>(null);

  async function loadUsers() {
    const response = await fetch('/api/users', { headers: { Accept: 'application/json', Authorization: `Bearer ${token}` } });
    if (!response.ok) {
      const body = await response.json().catch(() => ({})) as { message?: string };
      throw new Error(body.message ?? `Unable to load users (HTTP ${response.status}).`);
    }
    setUsers(await response.json() as ManagedUser[]);
  }

  async function loadBranches() {
    const response = await fetch('/api/users/branches', { headers: { Accept: 'application/json', Authorization: `Bearer ${token}` } });
    if (!response.ok) {
      if (response.status === 404) {
        throw new Error('User management API is not running. Stop and restart the backend, then refresh this page.');
      }

      const body = await response.json().catch(() => ({})) as { message?: string };
      throw new Error(body.message ?? `Unable to load branches (HTTP ${response.status}).`);
    }
    setBranches(await response.json() as Branch[]);
  }

  async function loadPendingUsers() {
    const response = await fetch('/api/users/pending', { headers: { Accept: 'application/json', Authorization: `Bearer ${token}` } });
    if (!response.ok) throw new Error(`Unable to load signup requests (HTTP ${response.status}).`);
    setPendingUsers(await response.json() as ManagedUser[]);
  }

  useEffect(() => {
    void Promise.allSettled([loadUsers(), loadBranches(), loadPendingUsers()])
      .then((results) => {
        const failed = results.find((result): result is PromiseRejectedResult => result.status === 'rejected');
        if (failed) notify(failed.reason instanceof Error ? failed.reason.message : 'Unable to load user details.', 'error');
      })
      .finally(() => setLoading(false));
  }, [notify, token]);

  async function createUser(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (form.role === 'Admin' && !await confirm({
      title: 'Create an Admin account?',
      message: `This grants ${form.fullName || 'this user'} full access to business settings and user management.`,
      confirmLabel: 'Create Admin',
      tone: 'danger',
    })) return;
    setSaving(true);
    try {
      const response = await fetch('/api/users', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
        body: JSON.stringify({ ...form, branchId: form.branchId || null }),
      });
      const body = await response.json().catch(() => ({})) as { message?: string };
      if (!response.ok) throw new Error(body.message ?? 'Unable to create user.');
      setForm(emptyForm);
      await loadUsers();
      notify('User created successfully.', 'success');
    } catch (error) {
      notify(error instanceof Error ? error.message : 'Unable to create user.', 'error');
    } finally {
      setSaving(false);
    }

  }

  async function saveUser(event: FormEvent<HTMLFormElement>) {
      event.preventDefault();
      if (!editingUser) return;
      if (editingUser.role !== users.find((user) => user.id === editingUser.id)?.role &&
        !await confirm({
          title: 'Change this user’s role?',
          message: `Change ${editingUser.fullName} to ${editingUser.role}? This changes their business permissions.`,
          confirmLabel: 'Change role',
          tone: 'danger',
        })) return;
      setSaving(true);
      try {
        const response = await fetch(`/api/users/${editingUser.id}`, {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
          body: JSON.stringify({ fullName: editingUser.fullName, phone: editingUser.phone, role: editingUser.role, branchId: editingUser.branchId, password: null }),
        });
        const body = await response.json().catch(() => ({})) as { message?: string };
        if (!response.ok) throw new Error(body.message ?? 'Unable to update user.');
        setUsers((current) => current.map((user) => user.id === editingUser.id ? editingUser : user));
        setEditingUser(null);
        notify('User details updated.', 'success');
      } catch (error) {
        notify(error instanceof Error ? error.message : 'Unable to update user.', 'error');
      } finally {
        setSaving(false);
      }
    }

  async function approveUser(user: ManagedUser) {
      if (!await confirm({
        title: 'Approve this signup?',
        message: `Approve ${user.fullName} as ${user.role}? They will be able to sign in with this role.`,
        confirmLabel: 'Approve signup',
        tone: user.role === 'Admin' ? 'danger' : 'primary',
      })) return;
      const branchId = user.branchId ?? branches[0]?.id;
      if (!branchId) {
        notify('Create or select a branch before approving this request.', 'error');
        return;
      }
      try {
        const response = await fetch(`/api/users/${user.id}/approve`, {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
          body: JSON.stringify({ role: user.role, branchId }),
        });
        const body = await response.json().catch(() => ({})) as { message?: string };
        if (!response.ok) throw new Error(body.message ?? 'Unable to approve signup request.');
        setPendingUsers((current) => current.filter((candidate) => candidate.id !== user.id));
        await loadUsers();
        notify('Signup approved. The user can now sign in.', 'success');
      } catch (error) {
        notify(error instanceof Error ? error.message : 'Unable to approve signup request.', 'error');
    }
  }

  async function deleteUser(user: ManagedUser, action: 'delete' | 'reject' = 'delete') {
    if (!await confirm({
      title: action === 'reject' ? 'Reject signup request?' : 'Delete this user?',
      message: action === 'reject'
        ? `Reject and remove ${user.fullName}’s pending signup request?`
        : `Delete ${user.fullName}’s account? This cannot be undone.`,
      confirmLabel: action === 'reject' ? 'Reject signup' : 'Delete user',
      tone: 'danger',
    })) return;
    const response = await fetch(`/api/users/${user.id}`, { method: 'DELETE', headers: { Authorization: `Bearer ${token}` } });
    if (!response.ok) {
      const body = await response.json().catch(() => ({})) as { message?: string };
      notify(body.message ?? 'Unable to delete user.', 'error');
      return;
    }

    setUsers((current) => current.filter((candidate) => candidate.id !== user.id));
    setPendingUsers((current) => current.filter((candidate) => candidate.id !== user.id));
    notify('User deleted.', 'success');
  }

  async function updateRole(user: ManagedUser, role: ManagedUser['role']) {
    if (role === user.role) return;
    if (!await confirm({
      title: 'Change this user’s role?',
      message: `Change ${user.fullName} from ${user.role} to ${role}? This changes their business permissions.`,
      confirmLabel: 'Change role',
      tone: 'danger',
    })) return;
    setUpdatingId(user.id);
    try {
      const response = await fetch(`/api/users/${user.id}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
        body: JSON.stringify({ fullName: user.fullName, phone: user.phone, role, branchId: user.branchId, password: null }),
      });
      if (!response.ok) throw new Error('Unable to update user role.');
      setUsers((current) => current.map((candidate) => candidate.id === user.id ? { ...candidate, role } : candidate));
      notify('User role updated.', 'success');
    } catch (error) {
      notify(error instanceof Error ? error.message : 'Unable to update user role.', 'error');
    } finally {
      setUpdatingId(null);
    }
  }

  return (
    <section className="manage-users-page">
      <div className="manage-users-hero">
        <div>
          <p className="manage-users-kicker">BUSINESS ACCESS</p>
          <h1>People &amp; access</h1>
          <p>Manage business accounts, assign roles, and review registration requests.</p>
        </div>
        <span className="manage-users-admin-tag"><span aria-hidden="true">✦</span> Admin workspace</span>
      </div>
      <div className="manage-users-layout">
        <form className="manage-users-card" onSubmit={editingUser ? saveUser : createUser}>
          <div className="manage-users-card-head">
            <span className="manage-users-card-icon" aria-hidden="true">{editingUser ? '✎' : '+'}</span>
            <div>
              <h2>{editingUser ? 'Edit user' : 'Create user'}</h2>
              <p>{editingUser ? 'Update account details and permissions.' : 'Add a person to your business workspace.'}</p>
            </div>
          </div>
          {editingUser ? (
            <>
              <label className="manage-users-field"><span>Full name</span><input value={editingUser.fullName} onChange={(e) => setEditingUser({ ...editingUser, fullName: e.target.value })} required /></label>
              <label className="manage-users-field"><span>Email</span><input value={editingUser.email} disabled /></label>
              <label className="manage-users-field"><span>Phone</span><input value={editingUser.phone} onChange={(e) => setEditingUser({ ...editingUser, phone: e.target.value })} /></label>
              <label className="manage-users-field"><span>Role</span><select value={editingUser.role} onChange={(e) => setEditingUser({ ...editingUser, role: e.target.value as ManagedUser['role'] })}><option>Staff</option><option>Manager</option><option>Admin</option></select></label>
              <label className="manage-users-field"><span>Branch</span><select value={editingUser.branchId ?? ''} onChange={(e) => setEditingUser({ ...editingUser, branchId: e.target.value || null })}><option value="">No branch</option>{branches.map((branch) => <option key={branch.id} value={branch.id}>{branch.name}</option>)}</select></label>
              <div style={{ display: 'flex', gap: 8 }}><button className="btn btn-primary" type="submit" disabled={saving}>{saving ? 'Saving…' : 'Save changes'}</button><button className="btn btn-secondary" type="button" onClick={() => setEditingUser(null)}>Cancel</button></div>
            </>
          ) : (
            <>
          <label className="manage-users-field"><span>Full name</span><input value={form.fullName} onChange={(e) => setForm({ ...form, fullName: e.target.value })} required /></label>
          <label className="manage-users-field"><span>Email</span><input type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} required /></label>
          <label className="manage-users-field"><span>Phone</span><input type="tel" value={form.phone} onChange={(e) => setForm({ ...form, phone: e.target.value })} /></label>
          <label className="manage-users-field"><span>Temporary password</span><input type="password" minLength={8} value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} required /></label>
          <label className="manage-users-field"><span>Role</span><select value={form.role} onChange={(e) => setForm({ ...form, role: e.target.value as ManagedUser['role'] })}><option>Staff</option><option>Manager</option><option>Admin</option></select></label>
          <label className="manage-users-field"><span>Branch</span><select value={form.branchId} onChange={(e) => setForm({ ...form, branchId: e.target.value })}><option value="">No branch</option>{branches.map((branch) => <option key={branch.id} value={branch.id}>{branch.name}</option>)}</select></label>
          <button className="btn btn-primary" type="submit" disabled={saving}>{saving ? 'Creating…' : 'Create user'}</button>
            </>
          )}
        </form>
        <div className="manage-users-results">
        {pendingUsers.length > 0 && <div className="manage-users-card">
          <div className="manage-users-card-head">
            <span className="manage-users-card-icon manage-users-card-icon-pending" aria-hidden="true">!</span>
            <div>
              <h2>Signup requests</h2>
              <p>Review and assign a role before approving.</p>
            </div>
            <span className="manage-users-count manage-users-count-pending">{pendingUsers.length} pending</span>
          </div>
          <div className="manage-users-table-wrap"><table className="data-table"><thead><tr><th>Name</th><th>Email</th><th>Phone</th><th>Role</th><th>Approval</th></tr></thead><tbody>
            {pendingUsers.map((user) => <tr key={user.id}><td>{user.fullName}</td><td>{user.email}</td><td>{user.phone || '—'}</td><td><select value={user.role} onChange={(event) => setPendingUsers((current) => current.map((candidate) => candidate.id === user.id ? { ...candidate, role: event.target.value as ManagedUser['role'] } : candidate))}><option>Staff</option><option>Manager</option><option>Admin</option></select></td><td><div className="manage-users-actions"><button className="btn btn-primary" type="button" onClick={() => void approveUser(user)}>Approve</button><button className="btn btn-danger" type="button" onClick={() => void deleteUser(user, 'reject')}>Reject</button></div></td></tr>)}
          </tbody></table></div>
        </div>}
        <div className="manage-users-card">
          <div className="manage-users-card-head">
            <span className="manage-users-card-icon manage-users-card-icon-people" aria-hidden="true">♙</span>
            <div>
              <h2>Business users</h2>
              <p>Manage access and branch assignments.</p>
            </div>
            {!loading && <span className="manage-users-count">{users.length} {users.length === 1 ? 'user' : 'users'}</span>}
          </div>
          {loading ? <p>Loading users…</p> : users.length === 0 ? <p>No users found.</p> : (
            <div className="manage-users-table-wrap"><table className="data-table"><thead><tr><th>Name</th><th>Email</th><th>Phone</th><th>Branch</th><th>Role</th><th>Action</th></tr></thead><tbody>
              {users.map((user) => <tr key={user.id}><td>{user.fullName}</td><td>{user.email}</td><td>{user.phone || '—'}</td><td>{branches.find((branch) => branch.id === user.branchId)?.name ?? '—'}</td><td>
                <select value={user.role} disabled={updatingId === user.id} onChange={(event) => void updateRole(user, event.target.value as ManagedUser['role'])}>
                  <option>Staff</option><option>Manager</option><option>Admin</option>
                </select>
              </td><td><div className="manage-users-actions"><button className="btn btn-secondary" type="button" onClick={() => setEditingUser(user)}>Edit</button><button className="btn btn-danger" type="button" onClick={() => void deleteUser(user)}>Delete</button></div></td></tr>)}
            </tbody></table></div>
          )}
        </div>
        </div>
      </div>
    </section>
  );
}
