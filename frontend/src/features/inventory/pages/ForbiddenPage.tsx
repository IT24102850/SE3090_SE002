import { Link, useNavigate } from 'react-router-dom';
import { useDispatch } from 'react-redux';
import { logout } from '../../../store/authSlice';

export function ForbiddenPage() {
  const dispatch = useDispatch();
  const navigate = useNavigate();
  const signInAgain = () => {
    dispatch(logout());
    navigate('/login', { replace: true });
  };

  return <section>
    <h1>Access denied</h1>
    <p>Your account does not have access to this area.</p>
    <p><Link to="/dashboard">Return to Dashboard</Link></p>
    <button type="button" onClick={signInAgain}>Clear session and sign in again</button>
  </section>;
}
