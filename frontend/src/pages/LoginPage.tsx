import { useState, useEffect } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { Link, useNavigate } from 'react-router-dom';
import { loginUser, clearError } from '../store/authSlice';
import { AppDispatch, RootState } from '../store/store';
import OrbitHero from '../features/marketing/OrbitHero';
import '../features/marketing/landing.css';

/* Sign-in, on the same paper-and-violet surface as the landing page:
 * wordmark, orbit sculpture, then a card carrying the form. The aside drops
 * away under 900px rather than stacking, so the form is the first thing on a
 * phone instead of being pushed below a hero. */

type Mode = 'business' | 'customer';

const MODES: { id: Mode; label: string }[] = [
  { id: 'business', label: 'Business' },
  { id: 'customer', label: 'Customer' },
];

/* What each side of the toggle changes.
 *
 * Only the form - both post to the same place. /api/auth/login is
 * role-agnostic: it looks the account up by email and returns whatever role
 * it has, so the toggle is a label for the person signing in rather than
 * anything the request carries.
 *
 * The two sign-up lines differ because the two routes genuinely do. /register
 * is business onboarding - it posts to /api/tenant/onboard and creates a
 * tenant - so pointing a customer at it would walk them into creating a
 * business. Customer sign-up is /api/auth/register, which only the mobile app
 * calls; there is no web page for it, so this says so rather than linking
 * somewhere that would be wrong.
 */
const COPY: Record<Mode, { blurb: string; placeholder: string; alt: React.ReactNode }> = {
  business: {
    blurb: 'Sign in to your business console.',
    placeholder: 'you@business.com',
    alt: <>New business? <Link to="/register">Register yours</Link></>,
  },
  customer: {
    blurb: 'Sign in to your bookings.',
    placeholder: 'you@email.com',
    alt: <>New customer? Create your account in the Unify app.</>,
  },
};

const LoginPage = () => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [mode, setMode] = useState<Mode>('business');
  const copy = COPY[mode];

  /* Arrow keys move between the two, per the radiogroup pattern. Home and End
   * are included because a two-option group makes them trivial and their
   * absence is the kind of thing that only shows up in an audit. */
  const onToggleKeyDown = (e: React.KeyboardEvent) => {
    const keys = ['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Home', 'End'];
    if (!keys.includes(e.key)) return;
    e.preventDefault();
    const next =
      e.key === 'Home' ? MODES[0].id
      : e.key === 'End' ? MODES[MODES.length - 1].id
      : mode === 'business' ? 'customer'
      : 'business';
    setMode(next);
    /* Focus follows selection in a radiogroup, and the newly selected option
     * is the only one with tabIndex 0 after this render.
     *
     * The group is captured here rather than read inside the callback: React
     * resets currentTarget to null once the handler returns, so reaching for
     * it across the frame boundary finds nothing and focus silently stays
     * put - the selection moves and the focus ring does not follow it. */
    const group = e.currentTarget as HTMLElement;
    requestAnimationFrame(() => {
      group.querySelector<HTMLElement>('[tabindex="0"]')?.focus();
    });
  };
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
              One console that <span className="lp-brandtext">becomes your business</span>
            </h2>
            <p className="lp-body" style={{ fontSize: '0.92rem' }}>
              Bookings, resources, stock and reporting — shaped around what you actually do.
            </p>
          </div>

          <div className="lp-auth-card">
            <div
              className="lp-toggle"
              role="radiogroup"
              aria-label="Account type"
              onKeyDown={onToggleKeyDown}
            >
              <span className="lp-toggle-thumb" data-mode={mode} aria-hidden="true" />
              {MODES.map((m) => (
                <button
                  key={m.id}
                  type="button"
                  role="radio"
                  aria-checked={mode === m.id}
                  /* Roving tabindex: a radiogroup is one tab stop, and the
                     arrow keys move within it. Leaving both focusable makes
                     the pair behave like two unrelated buttons to anyone not
                     using a mouse. */
                  tabIndex={mode === m.id ? 0 : -1}
                  className={`lp-toggle-opt${mode === m.id ? ' is-on' : ''}`}
                  onClick={() => setMode(m.id)}
                >
                  {m.label}
                </button>
              ))}
            </div>

            <h1>Welcome back</h1>
            <p>{copy.blurb}</p>

            {error && <div className="lp-alert">{error}</div>}

            <form onSubmit={handleSubmit}>
              <div className="lp-field">
                <label htmlFor="login-email">Email</label>
                <input
                  id="login-email"
                  className="lp-input"
                  type="email"
                  autoComplete="email"
                  placeholder={copy.placeholder}
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

            <p className="lp-auth-alt">{copy.alt}</p>
          </div>
        </div>
      </div>
    </div>
  );
};

export default LoginPage;
