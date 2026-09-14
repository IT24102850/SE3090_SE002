import { useSelector, useDispatch } from 'react-redux';
import { RootState } from '../store/store';
import { logout } from '../store/authSlice';

const RoleBasedNav = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const dispatch = useDispatch();

  if (!user) return null;

  return (
    <nav style={{ padding: '1rem', background: '#1a1a2e', color: 'white' }}>
      <h3>Unify</h3>
      <div style={{ display: 'flex', gap: '1rem', marginTop: '0.5rem', alignItems: 'center' }}>
        <a href="/dashboard" style={{ color: 'white', textDecoration: 'none' }}>Dashboard</a>
        
        {(user.role === 'Admin' || user.role === 'Manager') && (
          <a href="/bookings" style={{ color: 'white', textDecoration: 'none' }}>Bookings</a>
        )}
        
        {(user.role === 'Admin' || user.role === 'Manager' || user.role === 'Staff') && (
          <a href="/schedule" style={{ color: 'white', textDecoration: 'none' }}>Schedule</a>
        )}
        
        {user.role === 'Admin' && (
          <a href="/admin" style={{ color: '#ffd700', textDecoration: 'none' }}>Admin Panel</a>
        )}
        
        {user.role === 'Customer' && (
          <a href="/my-bookings" style={{ color: 'white', textDecoration: 'none' }}>My Bookings</a>
        )}
        
        <span style={{ marginLeft: 'auto' }}>
          {user.fullName} ({user.role})
        </span>
        
        <button 
          onClick={() => dispatch(logout())}
          style={{
            background: '#dc2626',
            color: 'white',
            border: 'none',
            padding: '0.5rem 1rem',
            borderRadius: '4px',
            cursor: 'pointer'
          }}
        >
          Logout
        </button>
      </div>
    </nav>
  );
};

export default RoleBasedNav;
