import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '../auth/AuthContext';

export function ForbiddenPage() {
  const { logout } = useAuth();
  const navigate = useNavigate();
  const signInAgain = () => {
    logout();
    navigate('/login', { replace: true });
  };

  return <section>
    <h1>Access denied</h1>
    <p>Your account does not have access to this area.</p>
    <p><Link to="/inventory">Return to Inventory Manager</Link></p>
    <button type="button" onClick={signInAgain}>Clear session and sign in again</button>
  </section>;
}
