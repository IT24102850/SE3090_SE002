import { useSelector } from 'react-redux';
import { RootState } from '../store/store';

const DashboardPage = () => {
  const { user } = useSelector((state: RootState) => state.auth);

  return (
    <div style={{ padding: '2rem' }}>
      <h1>Welcome, {user?.fullName}</h1>
      <p>Role: <strong>{user?.role}</strong></p>
      <p>Tenant: {user?.tenantId}</p>
    </div>
  );
};

export default DashboardPage;
