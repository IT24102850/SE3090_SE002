import { FormEvent, useEffect, useRef, useState } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { createDemoToken, useAuth } from '../auth/AuthContext';

type LoginResponse = { accessToken?: string; token?: string };

type OwlMood = 'idle' | 'email' | 'covered' | 'peeking' | 'error';

function LoginOwl({ mood }: { mood: OwlMood }) {
  const ref = useRef<SVGSVGElement>(null);
  const gaze = useRef({ x: 0, y: 0 });
  const [look, setLook] = useState({ x: 0, y: 0 });
  const [blink, setBlink] = useState(0);

  const covered = mood === 'covered';
  const peeking = mood === 'peeking';
  const error = mood === 'error';
  const focusGaze = mood === 'email' ? { x: 7, y: 6 } : error ? { x: 4, y: 0 } : null;

  // Smooth gaze easing toward the pointer/caret target.
  useEffect(() => {
    let frame = 0;
    const tick = () => {
      const target = focusGaze ?? gaze.current;
      setLook((current) => {
        const x = current.x + (target.x - current.x) * 0.12;
        const y = current.y + (target.y - current.y) * 0.12;
        return Math.abs(x - target.x) < 0.05 && Math.abs(y - target.y) < 0.05 ? { ...target } : { x, y };
      });
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [focusGaze?.x, focusGaze?.y]);

  // Random natural blinks (140ms close + optional double wink).
  useEffect(() => {
    let timer = 0;
    const schedule = () => {
      timer = window.setTimeout(() => {
        setBlink(1);
        window.setTimeout(() => {
          if (Math.random() > 0.5) {
            window.setTimeout(() => setBlink(1), 90);
          }
          window.setTimeout(() => setBlink(0), 140);
        }, 140);
        schedule();
      }, 2200 + Math.random() * 3400);
    };
    schedule();
    return () => window.clearTimeout(timer);
  }, []);

  const lidY = 98 - blink * 16;
  const browDrop = error ? 14 : mood === 'idle' ? 4 : 0;
  const squint = mood === 'idle' || mood === 'email' ? 4 : 0;
  const sway = 1 + Math.sin(Date.now() / 900) * 0.006;

  return (
    <svg
      ref={ref}
      className={`login-owl ${covered ? 'is-covered' : ''} ${peeking ? 'is-peeking' : ''} ${error ? 'is-error' : ''}`}
      viewBox="0 0 300 320"
      aria-hidden="true"
      onMouseMove={(event) => {
        const box = ref.current?.getBoundingClientRect();
        if (!box) return;
        gaze.current = {
          x: ((event.clientX - box.left) / box.width - 0.5) * 16,
          y: ((event.clientY - box.top) / box.height - 0.5) * 10,
        };
      }}
    >
      <defs>
        <radialGradient id="owl-iris" cx="50%" cy="42%" r="60%">
          <stop stopColor="#fef3c7" />
          <stop offset=".4" stopColor="#fbbf24" />
          <stop offset=".8" stopColor="#d97706" />
          <stop offset="1" stopColor="#78350f" />
        </radialGradient>
        <radialGradient id="owl-body" cx="50%" cy="34%" r="75%">
          <stop stopColor="#64748b" />
          <stop offset=".65" stopColor="#475569" />
          <stop offset="1" stopColor="#334155" />
        </radialGradient>
        <linearGradient id="owl-face" x1="0" y1="0" x2="0" y2="1">
          <stop stopColor="#f8fafc" />
          <stop offset="1" stopColor="#cbd5e1" />
        </linearGradient>
        <linearGradient id="owl-beak" x1="0" y1="0" x2="0" y2="1">
          <stop stopColor={error ? '#f87171' : '#fbbf24'} />
          <stop offset="1" stopColor={error ? '#b91c1c' : '#b45309'} />
        </linearGradient>
        <filter id="owl-shadow" x="-30%" y="-30%" width="160%" height="160%">
          <feDropShadow dx="0" dy="10" stdDeviation="8" floodOpacity=".45" />
        </filter>
      </defs>

      <g className="owl-breathe" style={{ transform: `scale(${sway})`, transformOrigin: '50% 88%' }}>
        <g filter="url(#owl-shadow)">
          {/* Tail */}
          <ellipse cx="150" cy="268" rx="34" ry="16" fill="#1e293b" opacity=".55" />
          {/* Body */}
          <path d="M75 168C75 104 225 104 225 168c0 104-150 104-150 0Z" fill="url(#owl-body)" stroke="#1e293b" strokeWidth="2" />
          <path d="M96 181c0-49 108-49 108 0 0 60-108 60-108 0Z" fill="#cbd5e1" opacity=".5" />
          {/* Belly feather arcs */}
          <g fill="none" stroke="#0f172a" strokeOpacity=".28" strokeWidth="2" strokeLinecap="round">
            <path d="M96 241c10 8 26 8 36 0" />
            <path d="M120 227c10 8 26 8 36 0" />
            <path d="M150 219c12 8 30 8 42 0" />
            <path d="M164 235c10 8 26 8 36 0" />
          </g>
          {/* Feet */}
          <path d="M132 286c-8 14-16 24-28 26M168 286c8 14 16 24 28 26" fill="none" stroke="#94a3b8" strokeWidth="4" strokeLinecap="round" />
        </g>

        {/* Wings */}
        <g className="owl-wing owl-wing-left" filter="url(#owl-shadow)" stroke="#1e293b" strokeWidth="2">
          <path d="M30 252C15 178 66 128 108 142c-18 54-52 100-78 110Z" fill="#1e293b" />
          <path d="M40 244c6-48 22-86 52-104" fill="none" stroke="#475569" strokeWidth="2" />
        </g>
        <g className="owl-wing owl-wing-right" filter="url(#owl-shadow)" stroke="#1e293b" strokeWidth="2">
          <path d="M270 252c15-74-36-124-78-110 18 54 52 100 78 110Z" fill="#1e293b" />
          <path d="M260 244c-6-48-22-86-52-104" fill="none" stroke="#475569" strokeWidth="2" />
        </g>

        {/* Head group */}
        <g>
          <path d="M65 122C65 42 235 42 235 122c0 52-170 52-170 0Z" fill="url(#owl-body)" stroke="#1e293b" strokeWidth="2.5" />
          {/* Ear tufts */}
          <path d="m78 74-30-52 50 34M222 74l30-52-50 34" fill="url(#owl-body)" stroke="#1e293b" strokeWidth="2.5" strokeLinejoin="round" />
          {/* Facial disc */}
          <g filter="url(#owl-shadow)">
            <path d="M150 134c-46 4-78-28-90-64 18 24 56 34 90 34 34 0 72-10 90-34-12 36-44 68-90 64Z" fill="url(#owl-face)" />
            <circle cx="150" cy="122" r="84" fill="none" stroke="#64748b" strokeWidth="1.5" opacity=".5" />
          </g>
          {/* Eyes */}
          {[108, 192].map((cx) => (
            <g key={cx}>
              <circle cx={cx} cy="118" r="38" fill="#0f172a" />
              <circle cx={cx} cy="118" r="30" fill="url(#owl-iris)" />
              {/* Iris spokes */}
              <g stroke="#78350f" strokeOpacity=".35" strokeWidth="1.2">
                {[0, 45, 90, 135, 180, 225, 270, 315].map((deg) => (
                  <line key={deg} x1={cx + 10 * Math.cos((deg * Math.PI) / 180)} y1={118 + 10 * Math.sin((deg * Math.PI) / 180)} x2={cx + 26 * Math.cos((deg * Math.PI) / 180)} y2={118 + 26 * Math.sin((deg * Math.PI) / 180)} />
                ))}
              </g>
              {/* Pupils track the smoothed gaze */}
              <g transform={`translate(${look.x} ${look.y})`}>
                <circle cx={cx} cy="118" r="13" fill="#020617" />
                <circle cx={cx - 4} cy="113" r="4.5" fill="white" opacity=".95" />
                <circle cx={cx + 3.5} cy="124" r="2" fill="white" opacity=".5" />
              </g>
              {/* Eyelid (blink + content squint) */}
              <path d={`M${cx - 38} 120 Q${cx} ${lidY - squint} ${cx + 38} 120 L${cx + 38} 90 Q${cx} ${92 - squint} ${cx - 38} 90 Z`} fill="#334155" opacity={blink ? 1 : 0.001} />
              <path d={`M${cx - 38} ${118 - squint} Q${cx} ${112 - squint} ${cx + 38} ${118 - squint}`} fill="none" stroke="#1e293b" strokeWidth="3" strokeLinecap="round" opacity={squint ? 0.9 : 0.4} transform="translate(0 4)" />
            </g>
          ))}
          {/* Angry/curious brows */}
          {(error || mood === 'covered' || peeking) && (
            <g stroke="#1e293b" strokeWidth="5" strokeLinecap="round">
              <line x1="78" y1={78 + browDrop} x2="126" y2={66 + browDrop} />
              <line x1="222" y1={78 + browDrop} x2="174" y2={66 + browDrop} />
            </g>
          )}
          {/* Beak */}
          <path d="M150 130c10 8 8 22 0 30-8-8-10-22 0-30Z" fill="url(#owl-beak)" stroke="#451a03" strokeWidth="1.5" />
          <path d="M150 142v14" stroke="#451a03" strokeWidth="1.2" opacity=".6" />
          {/* Mouth line */}
          <path d={error ? 'M138 166c8 8 16 8 24 0' : 'M138 166c8 5 16 5 24 0'} fill="none" stroke="#1e293b" strokeWidth="3" strokeLinecap="round" />
        </g>
      </g>
    </svg>
  );
}

export function LoginPage() {
  const { setToken } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [focused, setFocused] = useState<'email' | 'password' | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const mood: OwlMood = error ? 'error' : focused === 'password' ? (showPassword ? 'peeking' : 'covered') : focused === 'email' ? 'email' : 'idle';
  function reset() { setEmail(''); setPassword(''); setShowPassword(false); setError(null); }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);
    try {
      const response = await fetch('/api/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password })
      });
      const body = (await response.json().catch(() => ({}))) as LoginResponse;
      const token = body.accessToken ?? body.token;
      if (!response.ok || !token) throw new Error('Login failed. Check your credentials and try again.');
      setToken(token);
      const from = (location.state as { from?: { pathname?: string } } | null)?.from?.pathname;
      navigate(from ?? '/inventory', { replace: true });
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Login failed.');
    } finally {
      setSubmitting(false);
    }
  }

  function demoSignIn() {
    setToken(createDemoToken('Admin'));
    navigate('/analytics', { replace: true });
  }

  return (
    <main className="login-page">
      <div className="login-scene" aria-label="SME Inventory sign in">
        <div className="owl-wrapper"><LoginOwl mood={mood} /></div>
        <form className={`login-card ${error ? 'has-error' : ''}`} onSubmit={submit}>
          <div className="login-heading"><span className="login-brand-mark">▦</span><div><p>SME INVENTORY</p><h1>Welcome back</h1></div></div>
          <p className="login-intro">Sign in to keep your inventory moving.</p>
          <label>Email address <input type="email" autoComplete="username" placeholder="you@company.com" value={email} onFocus={() => setFocused('email')} onBlur={() => setFocused(null)} onChange={(e) => setEmail(e.target.value)} required /></label>
          <label className="password-field">Password <input type={showPassword ? 'text' : 'password'} autoComplete="current-password" placeholder="••••••••" value={password} onFocus={() => setFocused('password')} onBlur={() => setFocused(null)} onChange={(e) => setPassword(e.target.value)} required /><button className="password-toggle" type="button" aria-label={showPassword ? 'Hide password' : 'Show password'} aria-pressed={showPassword} onMouseDown={(e) => e.preventDefault()} onClick={() => setShowPassword((value) => !value)}>{showPassword ? 'Hide' : 'Show'}</button></label>
          {error && <p className="error" role="alert">{error}</p>}
          <label className="remember"><input type="checkbox" />Remember me</label>
          <button disabled={submitting}>{submitting ? 'Signing in…' : 'Sign in'}</button>
          <button className="secondary reset-button" type="button" onClick={reset}>Reset</button>
          {import.meta.env.DEV && (
            <button className="demo-button" type="button" onClick={demoSignIn}>
              Demo sign in as Admin
            </button>
          )}
          <p className="security-note">⌁ Your session is secured and encrypted.</p>
        </form>
      </div>
    </main>
  );
}
