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
        <p>Role: <strong>{user?.role}</strong></p>
        <p>Tenant: {user?.tenantId}</p>
      </div>
    </div>
  );
};

export default DashboardPage;