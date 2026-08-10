import { useSelector } from 'react-redux';
import { RootState } from '../store/store';

const RoleBasedNav = () => {
  const { user } = useSelector((state: RootState) => state.auth);

  if (!user) return null;

  return (
    <nav style={{ padding: '1rem', background: '#1a1a2e', color: 'white' }}>
      <h3>SME Platform</h3>
      <div style={{ display: 'flex', gap: '1rem', marginTop: '0.5rem' }}>
        <a href="/dashboard" style={{ color: 'white' }}>Dashboard</a>
        
        {(user.role === 'Admin' || user.role === 'Manager') && (
          <a href="/bookings" style={{ color: 'white' }}>Bookings</a>
        )}
        
        {(user.role === 'Admin' || user.role === 'Manager' || user.role === 'Staff') && (
          <a href="/schedule" style={{ color: 'white' }}>Schedule</a>
        )}
        
        {user.role === 'Admin' && (
          <a href="/admin" style={{ color: '#ffd700' }}>Admin Panel</a>
        )}
        
        {user.role === 'Customer' && (
          <a href="/my-bookings" style={{ color: 'white' }}>My Bookings</a>
        )}
        
        <span style={{ marginLeft: 'auto' }}>
          {user.fullName} ({user.role})
        </span>
      </div>
    </nav>
  );
};

export default RoleBasedNav;