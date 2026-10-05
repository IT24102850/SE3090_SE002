import { useState } from 'react';
import { useToast } from '../../shared/components/Toast';

const PIN_KEY = 'unify.customer.pin';

/** Device-local equivalent of Flutter's Security & PIN screen. */
export default function CustomerSecurityPage() {
  const toast = useToast();
  const [hasPin, setHasPin] = useState(() => Boolean(localStorage.getItem(PIN_KEY)));
  const [pin, setPin] = useState('');
  const [confirm, setConfirm] = useState('');

  function save() {
    if (!/^\d{4,6}$/.test(pin)) {
      toast.show('Use a 4–6 digit PIN.', 'warning');
      return;
    }
    if (pin !== confirm) {
      toast.show('The PINs do not match.', 'warning');
      return;
    }
    localStorage.setItem(PIN_KEY, pin);
    setHasPin(true);
    setPin('');
    setConfirm('');
    toast.show('Device PIN saved.', 'success');
  }

  function remove() {
    localStorage.removeItem(PIN_KEY);
    setHasPin(false);
    toast.show('Device PIN removed.', 'success');
  }

  return (
    <div className="cust-page">
      <div className="page-header">
        <div>
          <p className="cust-eyebrow">ACCOUNT PROTECTION</p>
          <h1 className="page-title">Security &amp; PIN</h1>
          <p className="page-subtitle">Protect this device without changing your account password.</p>
        </div>
      </div>
      <section className="card card-pad" style={{ maxWidth: 520 }}>
        <h2>{hasPin ? 'Device lock is enabled' : 'Enable device lock'}</h2>
        <p className="page-subtitle">The PIN stays in this browser and is never uploaded.</p>
        {!hasPin ? (
          <>
            <label className="field"><span>New PIN</span><input className="input" inputMode="numeric" type="password" maxLength={6} value={pin} onChange={(e) => setPin(e.target.value.replace(/\D/g, ''))} /></label>
            <label className="field"><span>Confirm PIN</span><input className="input" inputMode="numeric" type="password" maxLength={6} value={confirm} onChange={(e) => setConfirm(e.target.value.replace(/\D/g, ''))} /></label>
            <button className="btn btn-primary" onClick={save}>Save PIN</button>
          </>
        ) : (
          <button className="btn btn-danger" onClick={remove}>Remove device PIN</button>
        )}
      </section>
    </div>
  );
}
