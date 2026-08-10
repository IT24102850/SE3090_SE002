import { useSelector } from 'react-redux';
import { RootState } from '../store/store';
import RoleBasedNav from '../components/RoleBasedNav';

const DashboardPage = () => {
  const { user } = useSelector((state: RootState) => state.auth);

  return (
    <div>
      <RoleBasedNav />
      <div style={{ padding: '2rem' }}>
        <h1>Welcome, {user?.fullName}</h1>
        <p>Tenant ID: {user?.tenantId}</p>
        <p>Role: <strong>{user?.role}</strong></p>

        {user?.role === 'Admin' && (
          <div style={{ marginTop: '1rem', padding: '1rem', background: '#fef3c7', borderRadius: '8px' }}>
            <h3>🔧 Admin Controls</h3>
            <ul>
              <li>Manage all branches</li>
              <li>View system analytics</li>
              <li>Assign managers & staff</li>
              <li>Approve high-impact actions</li>
            </ul>
          </div>
        )}

        {user?.role === 'Manager' && (
          <div style={{ marginTop: '1rem', padding: '1rem', background: '#dbeafe', borderRadius: '8px' }}>
            <h3>📊 Branch Manager</h3>
            <ul>
              <li>Manage branch bookings</li>
              <li>Approve schedules</li>
              <li>View branch reports</li>
            </ul>
          </div>
        )}

        {user?.role === 'Staff' && (
          <div style={{ marginTop: '1rem', padding: '1rem', background: '#d1fae5', borderRadius: '8px' }}>
            <h3>👨‍💼 Staff Panel</h3>
            <ul>
              <li>Create/view bookings</li>
              <li>Mark attendance</li>
              <li>Process walk-ins</li>
            </ul>
          </div>
        )}

        {user?.role === 'Customer' && (
          <div style={{ marginTop: '1rem', padding: '1rem', background: '#f3e8ff', borderRadius: '8px' }}>
            <h3>👤 My Account</h3>
            <ul>
              <li>Book appointments</li>
              <li>View my bills</li>
              <li>Cancel/reschedule</li>
            </ul>
          </div>
        )}
      </div>
    </div>
  );
};

export default DashboardPage;