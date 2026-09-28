import { useState, useEffect, useRef } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import axios from 'axios';
import { API_BASE_URL } from '../api/apiBaseUrl';
import { useToast } from '../shared/components/Toast';
import '../features/marketing/landing.css';
import './signup.css';

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

export default function ForgotPasswordPage() {
  const [searchParams] = useSearchParams();
  const initialEmail = searchParams.get('email') || '';
  const initialCode = searchParams.get('code') || '';

  const [step, setStep] = useState<'request' | 'verify' | 'success'>(initialCode ? 'verify' : 'request');
  const [email, setEmail] = useState(initialEmail);
  const [code, setCode] = useState(initialCode);
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [resendCooldown, setResendCooldown] = useState(0);

  const [theme, setTheme] = useState<'light' | 'dark'>(() => {
    const saved = localStorage.getItem('unify-home-theme');
    if (saved === 'dark' || saved === 'light') return saved;
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  });

  const { show } = useToast();
  const navigate = useNavigate();

  useEffect(() => {
    document.documentElement.dataset.unifyTheme = theme;
    localStorage.setItem('unify-home-theme', theme);
    return () => {
      delete document.documentElement.dataset.unifyTheme;
    };
  }, [theme]);

  // Resend cooldown timer
  useEffect(() => {
    if (resendCooldown <= 0) return;
    const timer = setInterval(() => {
      setResendCooldown((prev) => prev - 1);
    }, 1000);
    return () => clearInterval(timer);
  }, [resendCooldown]);

  const handleRequestReset = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email.trim()) {
      show('Please enter your email address.', 'error');
      return;
    }
    setLoading(true);
    try {
      const res = await axios.post(`${API_BASE_URL}/auth/forgot-password`, {
        email: email.trim(),
      });
      show(res.data.message || 'If the address is registered and email delivery is configured, a code will arrive shortly.', 'success');
      setCode('');
      setResendCooldown(60);
      setStep('verify');
    } catch (err: unknown) {
      if (axios.isAxiosError(err) && err.response?.data?.message) {
        show(err.response.data.message, 'error');
      } else {
        show('Unable to process password reset. Please try again.', 'error');
      }
    } finally {
      setLoading(false);
    }
  };

  const handleResetPassword = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!code.trim()) {
      show('Please enter the 6-digit verification code.', 'error');
      return;
    }
    if (newPassword.length < 6) {
      show('Password must be at least 6 characters long.', 'error');
      return;
    }
    if (newPassword !== confirmPassword) {
      show('Passwords do not match.', 'error');
      return;
    }

    setLoading(true);
    try {
      const res = await axios.post(`${API_BASE_URL}/auth/reset-password`, {
        email: email.trim(),
        code: code.trim(),
        newPassword,
      });
      show(res.data.message || 'Password successfully reset!', 'success');
      setStep('success');
    } catch (err: unknown) {
      if (axios.isAxiosError(err) && err.response?.data?.message) {
        show(err.response.data.message, 'error');
      } else {
        show('Reset failed. Please verify your code and try again.', 'error');
      }
    } finally {
      setLoading(false);
    }
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
            <span className="lp-auth-brand-badge">RECOVERY</span>
          </Link>

          <div className="lp-auth-top-actions">
            <Link className="lp-auth-home-btn" to="/login">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <polyline points="15 18 9 12 15 6" />
              </svg>
              <span>Back to Sign In</span>
            </Link>

            {/* Interactive Theme Switcher */}
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

        {/* 2-Column Card Shell */}
        <div className="lp-auth-shell">
          {/* Left Side: Graphic & Photography Context */}
          <section className="lp-auth-showcase" aria-label="Account Recovery Support">
            <div className="lp-auth-photo-frame lp-float-card">
              <img
                src="/landing/operations-hub.jpg"
                alt="Secure account authentication and workspace operations"
              />
              <div className="lp-auth-photo-overlay">
                <span className="lp-auth-live-chip">
                  <i /> SECURE VERIFICATION
                </span>
                <strong className="lp-auth-photo-caption">
                  Encrypted credentials & multi-factor protection.
                </strong>
              </div>
            </div>

            <div className="lp-auth-showcase-copy">
              <span className="lp-auth-eyebrow">FAST &amp; SAFE RECOVERY</span>
              <h2>
                Regain access.<br />
                <em>Keep moving forward.</em>
              </h2>
              <p>
                We'll email a confidential 6-digit confirmation code. Once verified, your workspace credentials are updated instantly across all your branches and devices.
              </p>

              <ul className="lp-auth-proof-list">
                <li>
                  <span>✓</span>
                  <span>15-minute time-limited verification codes</span>
                </li>
                <li>
                  <span>✓</span>
                  <span>Direct sync with all branch and mobile sessions</span>
                </li>
                <li>
                  <span>✓</span>
                  <span>Zero password exposure or plain-text handling</span>
                </li>
              </ul>
            </div>

            <div className="lp-auth-trust-bar">
              <p>Need extra help? Email our security team at <b>support@unify.work</b></p>
            </div>
          </section>

          {/* Right Side: Step Form Card */}
          <section className="lp-auth-form-card" aria-labelledby="recovery-title">
            <span className="lp-auth-eyebrow">CREDENTIAL RECOVERY</span>

            {step === 'request' && (
              <div className="lp-auth-step-anim">
                <h1 id="recovery-title">Reset your password</h1>
                <p className="lp-auth-subtext">
                  Enter the email associated with your Unify workspace account to receive a 6-digit verification code.
                </p>

                <form onSubmit={handleRequestReset} noValidate>
                  <div className="lp-auth-field">
                    <label htmlFor="recovery-email">Account email address</label>
                    <div className="lp-auth-input-wrap">
                      <span className="lp-auth-input-icon">
                        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                          <rect x="3" y="5" width="18" height="14" rx="2" />
                          <polyline points="3 7 12 13 21 7" />
                        </svg>
                      </span>
                      <input
                        id="recovery-email"
                        className="lp-auth-input"
                        type="email"
                        autoComplete="email"
                        placeholder="you@business.com"
                        value={email}
                        onChange={(e) => setEmail(e.target.value)}
                        required
                        autoFocus
                      />
                    </div>
                  </div>

                  <button
                    type="submit"
                    disabled={loading}
                    className="lp-auth-submit-btn lp-btn-shine"
                  >
                    {loading ? (
                      <>
                        <span className="lp-spinner" />
                        <span>Sending recovery code…</span>
                      </>
                    ) : (
                      <>
                        <span>Send Recovery Code</span>
                        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                          <line x1="5" y1="12" x2="19" y2="12" />
                          <polyline points="12 5 19 12 12 19" />
                        </svg>
                      </>
                    )}
                  </button>
                </form>

                <div className="lp-auth-divider">
                  <span>Remembered your password?</span>
                </div>

                <Link className="lp-auth-secondary-btn" to="/login">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                    <line x1="19" y1="12" x2="5" y2="12" />
                    <polyline points="12 19 5 12 12 5" />
                  </svg>
                  <span>Return to Sign In</span>
                </Link>
              </div>
            )}

            {step === 'verify' && (
              <div className="lp-auth-step-anim">
                <h1 id="recovery-title">Enter verification code</h1>
                <p className="lp-auth-subtext">
                  If this address is registered and email delivery is configured, a 6-digit code will arrive at <strong>{email}</strong>. Check your inbox and enter it below with your new password.
                </p>

                <form onSubmit={handleResetPassword} noValidate>
                  <div className="lp-auth-field">
                    <label htmlFor="recovery-code">6-digit verification code</label>
                    <div className="lp-auth-input-wrap">
                      <span className="lp-auth-input-icon">
                        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                          <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
                          <path d="M7 11V7a5 5 0 0 1 10 0v4" />
                        </svg>
                      </span>
                      <input
                        id="recovery-code"
                        className="lp-auth-input lp-code-input"
                        type="text"
                        maxLength={6}
                        placeholder="123456"
                        value={code}
                        onChange={(e) => setCode(e.target.value.replace(/\D/g, ''))}
                        required
                        autoFocus
                      />
                    </div>
                  </div>

                  <div className="lp-auth-field">
                    <label htmlFor="new-password">New password</label>
                    <div className="lp-auth-input-wrap">
                      <span className="lp-auth-input-icon">
                        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                          <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
                          <path d="M7 11V7a5 5 0 0 1 10 0v4" />
                        </svg>
                      </span>
                      <input
                        id="new-password"
                        className="lp-auth-input"
                        type={showPassword ? 'text' : 'password'}
                        placeholder="At least 6 characters"
                        value={newPassword}
                        onChange={(e) => setNewPassword(e.target.value)}
                        required
                      />
                      <button
                        type="button"
                        className="lp-auth-eye-btn"
                        onClick={() => setShowPassword((prev) => !prev)}
                        title={showPassword ? 'Hide password' : 'Show password'}
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

                  <div className="lp-auth-field">
                    <label htmlFor="confirm-password">Confirm new password</label>
                    <div className="lp-auth-input-wrap">
                      <span className="lp-auth-input-icon">
                        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                          <polyline points="20 6 9 17 4 12" />
                        </svg>
                      </span>
                      <input
                        id="confirm-password"
                        className="lp-auth-input"
                        type={showPassword ? 'text' : 'password'}
                        placeholder="Re-enter new password"
                        value={confirmPassword}
                        onChange={(e) => setConfirmPassword(e.target.value)}
                        required
                      />
                    </div>
                  </div>

                  <div className="lp-auth-options-row">
                    <button
                      type="button"
                      disabled={resendCooldown > 0 || loading}
                      className="lp-resend-btn"
                      onClick={handleRequestReset}
                    >
                      {resendCooldown > 0 ? `Resend code in ${resendCooldown}s` : 'Resend code'}
                    </button>
                    <button
                      type="button"
                      className="lp-auth-hint-link"
                      onClick={() => setStep('request')}
                    >
                      Change email
                    </button>
                  </div>

                  <button
                    type="submit"
                    disabled={loading}
                    className="lp-auth-submit-btn lp-btn-shine"
                  >
                    {loading ? (
                      <>
                        <span className="lp-spinner" />
                        <span>Updating credentials…</span>
                      </>
                    ) : (
                      <>
                        <span>Reset Password &amp; Sign In</span>
                        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                          <line x1="5" y1="12" x2="19" y2="12" />
                          <polyline points="12 5 19 12 12 19" />
                        </svg>
                      </>
                    )}
                  </button>
                </form>
              </div>
            )}

            {step === 'success' && (
              <div className="lp-auth-step-anim lp-success-card">
                <div className="lp-success-icon-wrap">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                    <polyline points="20 6 9 17 4 12" />
                  </svg>
                </div>
                <h2>Password Reset Successful!</h2>
                <p>
                  Your credentials have been securely updated. You can now access your workspace using your new password.
                </p>

                <button
                  type="button"
                  className="lp-auth-submit-btn lp-btn-shine"
                  onClick={() => navigate('/login')}
                >
                  <span>Proceed to Sign In</span>
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                    <line x1="5" y1="12" x2="19" y2="12" />
                    <polyline points="12 5 19 12 12 19" />
                  </svg>
                </button>
              </div>
            )}

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
