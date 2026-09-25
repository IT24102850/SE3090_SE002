import { useState, useEffect } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { Link, useNavigate } from 'react-router-dom';
import { loginUser, clearError } from '../store/authSlice';
import { AppDispatch, RootState } from '../store/store';
import { useToast } from '../shared/components/Toast';
import '../features/marketing/landing.css';

const LoginPage = () => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [theme, setTheme] = useState<'light' | 'dark'>(() =>
    localStorage.getItem('unify-home-theme') === 'dark' ? 'dark' : 'light',
  );
  const dispatch = useDispatch<AppDispatch>();
  const navigate = useNavigate();
  const { show } = useToast();
  const { isAuthenticated, loading, error } = useSelector((state: RootState) => state.auth);

  useEffect(() => {
    if (isAuthenticated) navigate('/dashboard');
    return () => { dispatch(clearError()); };
  }, [isAuthenticated, navigate, dispatch]);
  useEffect(() => { if (error) show(error, 'error'); }, [error, show]);
  useEffect(() => {
    document.documentElement.dataset.unifyTheme = theme;
    localStorage.setItem('unify-home-theme', theme);
    return () => { delete document.documentElement.dataset.unifyTheme; };
  }, [theme]);

  return <main className="lp lp-auth-page"><div className="lp-auth-backdrop" aria-hidden="true" /><div className="lp-auth"><div className="lp-auth-inner">
    <section className="lp-auth-aside lp-auth-story" aria-label="About Unify">
      <Link className="lp-brand" to="/"><img className="lp-brand-mark" src="/unify-logo.svg" alt="" width={34} height={34} /><span className="lp-brand-name">Unify<span className="lp-brand-tag">Your work, in flow</span></span></Link>
      <div className="lp-auth-photo"><img src="/landing/dive-centre.jpg" alt="A team preparing for a day of work" /></div><p className="lp-kicker"><span /> OPERATIONS, SIMPLIFIED</p><h1>Run the day.<br /><span>See the whole picture.</span></h1><p className="lp-body">Bookings, staff, inventory and customer activity — one calm workspace for the work that matters.</p><div className="lp-proof"><span>✓</span><span>Private, role-based access for every team</span></div>
    </section>
    <section className="lp-auth-card lp-auth-card-rich" aria-labelledby="login-title">
      <div className="lp-auth-theme" aria-label="Choose colour theme"><button type="button" className={theme === 'light' ? 'is-active' : ''} onClick={() => setTheme('light')} aria-pressed={theme === 'light'}>Light</button><button type="button" className={theme === 'dark' ? 'is-active' : ''} onClick={() => setTheme('dark')} aria-pressed={theme === 'dark'}>Dark</button></div>
      <Link className="lp-auth-home" to="/"><span aria-hidden="true">⌂</span> Home</Link>
      <Link className="lp-auth-mobile-brand" to="/"><img src="/unify-logo.svg" alt="Unify" /></Link><div className="lp-auth-eyebrow">WELCOME BACK</div><h1 id="login-title">Sign in to your workspace</h1><p>Use the account details you registered with.</p>
      {error && <div className="lp-alert" role="alert"><span>!</span>{error}</div>}
      <form onSubmit={(e) => { e.preventDefault(); dispatch(loginUser({ email: email.trim(), password })); }}>
        <div className="lp-field"><label htmlFor="login-email">Email address</label><div className="lp-input-wrap"><span aria-hidden="true">✉</span><input id="login-email" className="lp-input" type="email" autoComplete="email" placeholder="you@business.com" value={email} onChange={(e) => setEmail(e.target.value)} required /></div></div>
        <div className="lp-field"><div className="lp-label-row"><label htmlFor="login-password">Password</label><span>Keep your account secure</span></div><div className="lp-input-wrap"><span aria-hidden="true">●</span><input id="login-password" className="lp-input" type={showPassword ? 'text' : 'password'} autoComplete="current-password" placeholder="Enter your password" value={password} onChange={(e) => setPassword(e.target.value)} required /><button className="lp-password-toggle" type="button" onClick={() => setShowPassword((v) => !v)}>{showPassword ? 'Hide' : 'Show'}</button></div></div>
        <button type="submit" disabled={loading} className="lp-btn lp-btn-primary lp-auth-submit">{loading ? <><span className="lp-spinner" /> Signing you in…</> : <>Sign in <span aria-hidden="true">→</span></>}</button>
      </form><div className="lp-auth-divider"><span>New to Unify?</span></div><Link className="lp-btn lp-btn-outline lp-auth-create" to="/register">Create an account</Link>
    </section>
  </div></div></main>;
};
export default LoginPage;
