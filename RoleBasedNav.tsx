import { useSelector, useDispatch } from 'react-redux';
import { RootState } from '../store/store';
import { logout } from '../store/authSlice';

const RoleBasedNav = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const dispatch = useDispatch();

  if (!user) return null;

  return (
    <nav style={{ padding: '1rem 2rem', background: '#1a1a2e', color: 'white', display: 'flex', alignItems: 'center', gap: '1.5rem' }}>
      <span style={{ fontWeight: 'bold', fontSize: '1.2rem' }}>SME Platform</span>
      <a href="/dashboard" style={{ color: 'white', textDecoration: 'none' }}>Dashboard</a>
      {(user.role === 'Admin' || user.role === 'Manager') && (
        <a href="/bookings" style={{ color: 'white', textDecoration: 'none' }}>Bookings</a>
      )}
      {(user.role === 'Admin' || user.role === 'Manager' || user.role === 'Staff') && (
        <a href="/schedule" style={{ color: 'white', textDecoration: 'none' }}>Schedule</a>
      )}
      {user.role === 'Admin' && (
        <a href="/admin" style={{ color: '#ffd700', textDecoration: 'none', fontWeight: 'bold' }}>Admin Panel</a>
      )}
      {user.role === 'Customer' && (
        <a href="/my-bookings" style={{ color: 'white', textDecoration: 'none' }}>My Bookings</a>
      )}
      <div style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: '1rem' }}>
        <span>{user.fullName} ({user.role})</span>
        <button onClick={() => dispatch(logout())}
          style={{ background: '#dc2626', color: 'white', border: 'none', padding: '0.4rem 1rem', borderRadius: '4px', cursor: 'pointer', fontWeight: 'bold' }}>
          Logout
        </button>
      </div>
    </nav>
  );
};

export default RoleBasedNav;