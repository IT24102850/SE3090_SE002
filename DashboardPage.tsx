import { useSelector } from 'react-redux';
import { RootState } from '../store/store';
import RoleBasedNav from '../components/RoleBasedNav';

const DashboardPage = () => {
  const { user } = useSelector((state: RootState) => state.auth);

  return (
    <div>
      <RoleBasedNav />
      <div style={{ padding: '2rem', maxWidth: '1200px', margin: '0 auto' }}>
        <h1>Welcome, {user?.fullName}</h1>
        <div style={{ display: 'flex', gap: '1rem', marginTop: '1rem' }}>
          <div style={{ padding: '1rem', background: '#f3f4f6', borderRadius: '8px', flex: 1 }}>
            <p><strong>Role:</strong> {user?.role}</p>
            <p><strong>Tenant ID:</strong> {user?.tenantId}</p>
          </div>
        </div>

        {user?.role === 'Admin' && (
          <div style={{ marginTop: '1.5rem', padding: '1.5rem', background: '#fef3c7', borderRadius: '8px', border: '1px solid #f59e0b' }}>
            <h3>Admin Controls</h3>
            <ul style={{ marginTop: '0.5rem' }}>
              <li>Manage all branches</li>
              <li>View system analytics</li>
              <li>Assign managers & staff</li>
            </ul>
          </div>
        )}

        {user?.role === 'Manager' && (
          <div style={{ marginTop: '1.5rem', padding: '1.5rem', background: '#dbeafe', borderRadius: '8px', border: '1px solid #3b82f6' }}>
            <h3>Branch Manager</h3>
            <ul style={{ marginTop: '0.5rem' }}>
              <li>Manage branch bookings</li>
              <li>Approve schedules</li>
            </ul>
          </div>
        )}

        {user?.role === 'Staff' && (
          <div style={{ marginTop: '1.5rem', padding: '1.5rem', background: '#d1fae5', borderRadius: '8px', border: '1px solid #10b981' }}>
            <h3>Staff Panel</h3>
            <ul style={{ marginTop: '0.5rem' }}>
              <li>Create/view bookings</li>
              <li>Process walk-ins</li>
            </ul>
          </div>
        )}

        {user?.role === 'Customer' && (
          <div style={{ marginTop: '1.5rem', padding: '1.5rem', background: '#f3e8ff', borderRadius: '8px', border: '1px solid #8b5cf6' }}>
            <h3>My Account</h3>
            <ul style={{ marginTop: '0.5rem' }}>
              <li>Book appointments</li>
              <li>View my bills</li>
            </ul>
          </div>
        )}
      </div>
    </div>
  );
};

export default DashboardPage;