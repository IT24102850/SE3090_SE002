import { useState, useEffect } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { Link, useNavigate } from 'react-router-dom';
import { loginUser, clearError } from '../store/authSlice';
import { AppDispatch, RootState } from '../store/store';
import OrbitHero from '../features/marketing/OrbitHero';
import '../features/marketing/landing.css';

/* Sign-in, on the same neon-dark backdrop as the landing page and the Flutter
 * app's auth screens: wordmark, orbit sculpture, then a glass card carrying
 * the form. The aside drops away under 900px rather than stacking, so the
 * form is the first thing on a phone instead of being pushed below a hero. */

const LoginPage = () => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const dispatch = useDispatch<AppDispatch>();
  const navigate = useNavigate();
  const { isAuthenticated, loading, error } = useSelector((state: RootState) => state.auth);

  useEffect(() => {
    if (isAuthenticated) {
      navigate('/dashboard');
    }
    return () => {
      dispatch(clearError());
    };
  }, [isAuthenticated, navigate, dispatch]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    dispatch(loginUser({ email, password }));
  };

  return (
    <div className="lp">
      <div className="lp-auth">
        <div className="lp-auth-inner">
          <div className="lp-auth-aside">
            <Link className="lp-brand" to="/" style={{ marginBottom: 28 }}>
              <span className="lp-brand-mark">U</span>
              Unify
            </Link>
            <OrbitHero />
            <h2 className="lp-h2" style={{ fontSize: '1.5rem', marginTop: 24 }}>
              One console that <span className="lp-gradient-text">becomes your business</span>
            </h2>
            <p className="lp-sub" style={{ fontSize: '0.92rem' }}>
              Bookings, resources, stock and reporting — shaped around what you actually do.
            </p>
          </div>

          <div className="lp-auth-card">
            <h1>Welcome back</h1>
            <p>Sign in to your business console.</p>

            {error && <div className="lp-alert">{error}</div>}

            <form onSubmit={handleSubmit}>
              <div className="lp-field">
                <label htmlFor="login-email">Email</label>
                <input
                  id="login-email"
                  className="lp-input"
                  type="email"
                  autoComplete="email"
                  placeholder="you@business.com"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  required
                />
              </div>

              <div className="lp-field">
                <label htmlFor="login-password">Password</label>
                <input
                  id="login-password"
                  className="lp-input"
                  type="password"
                  autoComplete="current-password"
                  placeholder="••••••••"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  required
                />
              </div>

              <button type="submit" disabled={loading} className="lp-btn lp-btn-primary lp-auth-submit">
                {loading ? <><span className="lp-spinner" /> Signing in…</> : 'Sign in'}
              </button>
            </form>

            <p className="lp-auth-alt">
              New business? <Link to="/register">Register yours</Link>
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};

export default LoginPage;
