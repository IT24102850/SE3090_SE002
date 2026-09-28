import { useState, useEffect, useRef } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { Link, useNavigate } from 'react-router-dom';
import { loginUser, clearError } from '../store/authSlice';
import { AppDispatch, RootState } from '../store/store';
import { useToast } from '../shared/components/Toast';
import '../features/marketing/landing.css';

/* ── Interactive Particle Canvas ─────────────────────────────── */
function ParticleCanvas() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const animRef = useRef<number>(0);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const particles: { x: number; y: number; r: number; dx: number; dy: number; alpha: number }[] = [];
    const resize = () => {
      canvas.width = window.innerWidth;
      canvas.height = window.innerHeight;
    };
    resize();
    window.addEventListener('resize', resize);

    for (let i = 0; i < 40; i++) {
      particles.push({
        x: Math.random() * window.innerWidth,
        y: Math.random() * window.innerHeight,
        r: Math.random() * 2.2 + 0.6,
        dx: (Math.random() - 0.5) * 0.35,
        dy: (Math.random() - 0.5) * 0.35,
        alpha: Math.random() * 0.45 + 0.15,
      });
    }

    const draw = () => {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      for (const p of particles) {
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
        ctx.fillStyle = `rgba(37,99,235,${p.alpha})`;
        ctx.fill();
        p.x += p.dx;
        p.y += p.dy;
        if (p.x < 0 || p.x > canvas.width) p.dx *= -1;
        if (p.y < 0 || p.y > canvas.height) p.dy *= -1;
      }
      animRef.current = requestAnimationFrame(draw);
    };
    draw();
    return () => {
      window.removeEventListener('resize', resize);
      cancelAnimationFrame(animRef.current);
    };
  }, []);

  return <canvas ref={canvasRef} className="lp-particle-canvas" aria-hidden="true" />;
}

export default function LoginPage() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [rememberMe, setRememberMe] = useState(true);
  const [theme, setTheme] = useState<'light' | 'dark'>(() => {
    const saved = localStorage.getItem('unify-home-theme');
    if (saved === 'dark' || saved === 'light') return saved;
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  });

  const dispatch = useDispatch<AppDispatch>();
  const navigate = useNavigate();
  const { show } = useToast();
  const { isAuthenticated, loading, error } = useSelector((state: RootState) => state.auth);

  useEffect(() => {
    if (isAuthenticated) {
      navigate('/dashboard');
    }
    return () => {
      dispatch(clearError());
    };
  }, [isAuthenticated, navigate, dispatch]);

  useEffect(() => {
    if (error) {
      show(error, 'error');
    }
  }, [error, show]);

  useEffect(() => {
    document.documentElement.dataset.unifyTheme = theme;
    localStorage.setItem('unify-home-theme', theme);
    return () => {
      delete document.documentElement.dataset.unifyTheme;
    };
  }, [theme]);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!email.trim() || !password) {
      show('Please enter both your email address and password.', 'error');
      return;
    }
    dispatch(loginUser({ email: email.trim(), password }));
  };

  const handleForgotPassword = () => {
    navigate(`/forgot-password${email.trim() ? `?email=${encodeURIComponent(email.trim())}` : ''}`);
  };

  return (
    <main className="lp lp-home lp-auth-page">
      <ParticleCanvas />
      {/* Dynamic Background Glow Orbs */}
      <div className="lp-auth-mesh" aria-hidden="true">
        <div className="lp-auth-orb-1" />
        <div className="lp-auth-orb-2" />
      </div>

      <div className="lp-auth-content-wrap">
        {/* Top Header Navigation */}
        <header className="lp-auth-topbar">
        <Link className="lp-auth-brand" to="/" title="Back to Unify Home">
          <img src="/unify-logo.svg" alt="Unify" width={32} height={32} />
          <span className="lp-auth-brand-name">unify</span>
          <span className="lp-auth-brand-badge">WORKSPACE</span>
        </Link>

        <div className="lp-auth-top-actions">
          <Link className="lp-auth-home-btn" to="/">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
              <polyline points="9 22 9 12 15 12 15 22" />
            </svg>
            <span>Home</span>
          </Link>

          {/* Interactive Sun / Moon Theme Switcher */}
          <div className="lp-home-theme-toggle" role="radiogroup" aria-label="Theme mode selector">
            <button
              type="button"
              className={`lp-theme-btn ${theme === 'light' ? 'is-active' : ''}`}
              onClick={() => setTheme('light')}
              aria-checked={theme === 'light'}
              role="radio"
              title="Light theme"
            >
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <circle cx="12" cy="12" r="5" />
                <line x1="12" y1="1" x2="12" y2="3" />
                <line x1="12" y1="21" x2="12" y2="23" />
                <line x1="4.22" y1="4.22" x2="5.64" y2="5.64" />
                <line x1="18.36" y1="18.36" x2="19.78" y2="19.78" />
                <line x1="1" y1="12" x2="3" y2="12" />
                <line x1="21" y1="12" x2="23" y2="12" />
                <line x1="4.22" y1="19.78" x2="5.64" y2="18.36" />
                <line x1="18.36" y1="5.64" x2="19.78" y2="4.22" />
              </svg>
              <span>Light</span>
            </button>
            <button
              type="button"
              className={`lp-theme-btn ${theme === 'dark' ? 'is-active' : ''}`}
              onClick={() => setTheme('dark')}
              aria-checked={theme === 'dark'}
              role="radio"
              title="Dark theme"
            >
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z" />
              </svg>
              <span>Dark</span>
            </button>
          </div>
        </div>
      </header>

      {/* Main 2-Column Auth Card */}
      <div className="lp-auth-shell">
        {/* Left Side: Editorial & Real Project Photography Showcase */}
        <section className="lp-auth-showcase" aria-label="Why Unify">
          <div className="lp-auth-photo-frame lp-float-card">
            <img
              src="/landing/operations-hub.jpg"
              alt="Operations team coordinating bookings, shift handovers and stock in real time"
            />
            <div className="lp-auth-photo-overlay">
              <span className="lp-auth-live-chip">
                <i /> LIVE WORKSPACE HUB
              </span>
              <strong className="lp-auth-photo-caption">
                Clear context. Confident decisions. Every day.
              </strong>
            </div>
          </div>

          <div className="lp-auth-showcase-copy">
            <span className="lp-auth-eyebrow">ONE CALM WORKSPACE</span>
            <h2>
              Run the day.<br />
              <em>See the whole picture.</em>
            </h2>
            <p>
              Bookings, team rosters, live inventory tracking, and client handovers — brought together into one synchronized operating system.
            </p>

            <ul className="lp-auth-proof-list">
              <li>
                <span>✓</span>
                <span>Real-time multi-branch calendar &amp; dispatch</span>
              </li>
              <li>
                <span>✓</span>
                <span>Role-based permissions tailored for staff &amp; managers</span>
              </li>
              <li>
                <span>✓</span>
                <span>Automated inventory reorder triggers &amp; PO workflows</span>
              </li>
            </ul>
          </div>

          <div className="lp-auth-trust-bar">
            <div className="lp-auth-avatars">
              <span title="Colombo Diving Center">C</span>
              <span title="Villa Ceylon">V</span>
              <span title="Kandy Wellness Studio">K</span>
              <span title="Artisan Store Colombo">A</span>
            </div>
            <p>Trusted by 450+ modern businesses across 6 industries.</p>
          </div>
        </section>

        {/* Right Side: High Polish Form Card */}
        <section className="lp-auth-form-card" aria-labelledby="login-title">
          <span className="lp-auth-eyebrow">SECURE WORKSPACE ACCESS</span>
          <h1 id="login-title">Sign in to your workspace</h1>
          <p className="lp-auth-subtext">
            Enter your credentials to access your dashboard and active branches.
          </p>

          {error && (
            <div className="lp-auth-alert" role="alert">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
                <circle cx="12" cy="12" r="10" />
                <line x1="12" y1="8" x2="12" y2="12" />
                <line x1="12" y1="16" x2="12.01" y2="16" />
              </svg>
              <div>{error}</div>
            </div>
          )}

          <form onSubmit={handleSubmit} noValidate>
            <div className="lp-auth-field">
              <label htmlFor="login-email">Email address</label>
              <div className="lp-auth-input-wrap">
                <span className="lp-auth-input-icon">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                    <rect x="3" y="5" width="18" height="14" rx="2" />
                    <polyline points="3 7 12 13 21 7" />
                  </svg>
                </span>
                <input
                  id="login-email"
                  className="lp-auth-input"
                  type="email"
                  autoComplete="email"
                  placeholder="name@business.com"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  required
                />
              </div>
            </div>

            <div className="lp-auth-field">
              <div className="lp-auth-label-row">
                <label htmlFor="login-password">Password</label>
                <button
                  type="button"
                  className="lp-auth-hint-link"
                  onClick={handleForgotPassword}
                >
                  Forgot password?
                </button>
              </div>
              <div className="lp-auth-input-wrap">
                <span className="lp-auth-input-icon">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                    <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
                    <path d="M7 11V7a5 5 0 0 1 10 0v4" />
                  </svg>
                </span>
                <input
                  id="login-password"
                  className="lp-auth-input"
                  type={showPassword ? 'text' : 'password'}
                  autoComplete="current-password"
                  placeholder="Enter your password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  required
                />
                <button
                  type="button"
                  className="lp-auth-eye-btn"
                  onClick={() => setShowPassword((prev) => !prev)}
                  title={showPassword ? 'Hide password' : 'Show password'}
                  aria-label={showPassword ? 'Hide password' : 'Show password'}
                >
                  {showPassword ? (
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                      <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24" />
                      <line x1="1" y1="1" x2="23" y2="23" />
                    </svg>
                  ) : (
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                      <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z" />
                      <circle cx="12" cy="12" r="3" />
                    </svg>
                  )}
                </button>
              </div>
            </div>

            <div className="lp-auth-options-row">
              <label className="lp-auth-remember">
                <input
                  type="checkbox"
                  checked={rememberMe}
                  onChange={(e) => setRememberMe(e.target.checked)}
                />
                <span>Remember this device</span>
              </label>
            </div>

            <button
              type="submit"
              disabled={loading}
              className="lp-auth-submit-btn lp-btn-shine"
            >
              {loading ? (
                <>
                  <span className="lp-spinner" />
                  <span>Signing you in…</span>
                </>
              ) : (
                <>
                  <span>Sign In to Workspace</span>
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                    <line x1="5" y1="12" x2="19" y2="12" />
                    <polyline points="12 5 19 12 12 19" />
                  </svg>
                </>
              )}
            </button>
          </form>

          <div className="lp-auth-divider">
            <span>New to Unify?</span>
          </div>

          <Link className="lp-auth-secondary-btn" to="/register">
            <span>Create your workspace for free</span>
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
              <line x1="5" y1="12" x2="19" y2="12" />
              <polyline points="12 5 19 12 12 19" />
            </svg>
          </Link>

          <div className="lp-auth-security-footer">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
              <path d="M7 11V7a5 5 0 0 1 10 0v4" />
            </svg>
            <span>Bank-grade 256-bit encryption · Multi-branch ready</span>
          </div>
        </section>
      </div>
      </div>
    </main>
  );
}
