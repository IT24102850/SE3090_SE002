import { API_BASE_URL } from '../../api/apiBaseUrl';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import axios from 'axios';
import { useParams, useSearchParams } from 'react-router-dom';
import './embed.css';

/* The booking widget a business embeds on its own website.
 *
 * Rendered inside an iframe that public/embed.js mounts on the host page, so
 * it has no Unify chrome, no auth, and no dependency on the host's CSS. It
 * talks only to the anonymous /api/public/booking endpoints; everything it
 * shows (prices, sailings, seats left) comes from there, and the server
 * re-prices and re-checks capacity on submission, so nothing the visitor can
 * change in the DOM changes what gets booked.
 *
 * Two shapes of business, decided by what the catalog returns:
 *   - departures  -> pick a date, then a sailing on that date (whale
 *                    watching, safaris, boat trips)
 *   - no departures -> pick a resource and a day, then a free slot
 *
 * Host-page contract (window.postMessage to the parent):
 *   { type: 'unify-booking:height', height }     whenever our height changes
 *   { type: 'unify-booking:booked', reference }  after a successful booking
 */


interface Catalog {
  tenant: { id: string; name: string; logoUrl: string | null; website: string | null; businessType: string; subType: string | null; contactPhone: string | null };
  bookingTypes: BookingType[];
  departures: Departure[];
  resources: { id: string; name: string; category: string; description: string | null }[];
}
interface BookingType {
  id: string; name: string; description: string | null; defaultDurationMinutes: number; requiresApproval: boolean;
  currency: string; pricing: { adult: number | null; child: number | null; infant: number | null };
}
interface Departure {
  id: string; resourceId: string; vesselName: string; bookingTypeId: string | null; bookingTypeName: string | null;
  scheduledDeparture: string; scheduledReturn: string; capacity: number; seatsRemaining: number | null;
}
interface Slot { startTime: string; endTime: string; isAvailable: boolean }
interface Confirmation {
  id: string; reference: string; status: string; startTime: string; endTime: string; resourceName: string;
  tickets: { type: string; qty: number; unitPrice: number; lineTotal: number }[]; total: number; currency: string; seasonLabel: string | null;
}

const dayKey = (iso: string) => {
  const d = new Date(iso);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};
const fmtDay = (key: string) =>
  new Date(`${key}T12:00:00`).toLocaleDateString(undefined, { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' });
const fmtTime = (iso: string) => new Date(iso).toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' });
const fmtMoney = (n: number, currency: string) =>
  `${currency} ${n.toLocaleString(undefined, { minimumFractionDigits: 0, maximumFractionDigits: 2 })}`;
const todayKey = () => dayKey(new Date().toISOString());

const post = (msg: Record<string, unknown>) => {
  if (window.parent !== window) window.parent.postMessage({ source: 'unify-booking', ...msg }, '*');
};

export default function EmbedBookingPage() {
  const { tenantId = '' } = useParams();
  const [params] = useSearchParams();
  const accent = params.get('accent');
  const theme = params.get('theme') === 'dark' ? 'dark' : 'light';
  const whatsappParam = params.get('whatsapp');

  const [catalog, setCatalog] = useState<Catalog | null>(null);
  const [loadError, setLoadError] = useState('');

  const [fullName, setFullName] = useState('');
  const [email, setEmail] = useState('');
  const [phone, setPhone] = useState('');
  const [date, setDate] = useState('');
  const [departureId, setDepartureId] = useState('');
  const [resourceId, setResourceId] = useState('');
  const [slotStart, setSlotStart] = useState('');
  const [slots, setSlots] = useState<Slot[] | null>(null);
  const [adults, setAdults] = useState(2);
  const [children, setChildren] = useState(0);
  const [infants, setInfants] = useState(0);
  const [notes, setNotes] = useState('');
  const [honeypot, setHoneypot] = useState('');

  const [stage, setStage] = useState<'form' | 'review' | 'done'>('form');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');
  const [confirmation, setConfirmation] = useState<Confirmation | null>(null);

  const rootRef = useRef<HTMLDivElement>(null);

  /* Keep the host page's iframe the same height as our content. */
  useEffect(() => {
    const el = rootRef.current;
    if (!el || typeof ResizeObserver === 'undefined') return;
    const ro = new ResizeObserver(() => post({ type: 'unify-booking:height', height: Math.ceil(el.getBoundingClientRect().height) }));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  useEffect(() => {
    if (accent && /^#?[0-9a-f]{3,8}$/i.test(accent)) {
      document.documentElement.style.setProperty('--ub-accent', accent.startsWith('#') ? accent : `#${accent}`);
    }
    document.documentElement.dataset.ubTheme = theme;
  }, [accent, theme]);

  useEffect(() => {
    let cancelled = false;
    axios.get<Catalog>(`${API_BASE_URL}/public/booking/${tenantId}/catalog`)
      .then((r) => { if (!cancelled) setCatalog(r.data); })
      .catch((err) => {
        if (cancelled) return;
        setLoadError(axios.isAxiosError(err) && err.response?.status === 404
          ? 'This booking form is not linked to a business yet.'
          : 'The booking service is unavailable right now. Please try again shortly.');
      });
    return () => { cancelled = true; };
  }, [tenantId]);

  const hasDepartures = (catalog?.departures.length ?? 0) > 0;

  /* Departure mode: the dates that have at least one open sailing. */
  const departureDays = useMemo(() => {
    const map = new Map<string, Departure[]>();
    for (const d of catalog?.departures ?? []) {
      const k = dayKey(d.scheduledDeparture);
      map.set(k, [...(map.get(k) ?? []), d]);
    }
    return map;
  }, [catalog]);
  const departuresOnDay = date ? departureDays.get(date) ?? [] : [];
  const departure = catalog?.departures.find((d) => d.id === departureId) ?? null;

  /* Slot mode: fetch free slots when resource + date are chosen. */
  useEffect(() => {
    if (hasDepartures || !resourceId || !date) { setSlots(null); return; }
    let cancelled = false;
    setSlots(null);
    axios.get(`${API_BASE_URL}/bookings/available-slots`, {
      params: { resourceId, date, bookingTypeId: catalog?.bookingTypes[0]?.id },
    }).then((r) => { if (!cancelled) setSlots(r.data.slots ?? []); })
      .catch(() => { if (!cancelled) setSlots([]); });
    return () => { cancelled = true; };
  }, [hasDepartures, resourceId, date, catalog]);

  const bookingType: BookingType | null = useMemo(() => {
    if (!catalog) return null;
    if (departure?.bookingTypeId) return catalog.bookingTypes.find((bt) => bt.id === departure.bookingTypeId) ?? catalog.bookingTypes[0] ?? null;
    return catalog.bookingTypes[0] ?? null;
  }, [catalog, departure]);

  const currency = bookingType?.currency ?? 'LKR';
  const price = (t: 'adult' | 'child' | 'infant') => bookingType?.pricing[t] ?? 0;
  const infantsPriced = bookingType?.pricing.infant != null;
  const seats = adults + children + infants;
  const seatsLeft = departure?.seatsRemaining ?? null;
  const estimate = adults * price('adult') + children * price('child') + infants * price('infant');

  const when = departure
    ? `${fmtDay(dayKey(departure.scheduledDeparture))} · ${fmtTime(departure.scheduledDeparture)}`
    : slotStart ? `${fmtDay(date)} · ${fmtTime(slotStart)}` : '';
  const where = departure?.vesselName ?? catalog?.resources.find((r) => r.id === resourceId)?.name ?? '';

  /* WhatsApp, alongside Unify - not instead of it.
   *
   * Many small operators ran their bookings off a "send via WhatsApp" form
   * before Unify, and the team on the boat still reads that chat. So when a
   * number is known (the snippet's data-whatsapp, else the business's
   * contact phone in Unify) confirming a booking also opens WhatsApp with
   * the same message such a form would have sent, plus the Unify reference
   * so the two can be matched up. The record lives in Unify either way. */
  const whatsappNumber = (whatsappParam ?? catalog?.tenant.contactPhone ?? '').replace(/[^0-9]/g, '');
  const whatsappUrl = (c: Confirmation | null) => {
    if (!whatsappNumber) return '';
    const lines = [
      `New Booking from ${catalog?.tenant.name ?? 'website'}` + (c ? ` (ref ${c.reference})` : ''),
      '',
      `Name: ${fullName.trim()}`,
      `Email: ${email.trim()}`,
      `Phone: ${phone.trim()}`,
      `Date: ${c ? fmtDay(dayKey(c.startTime)) : departure ? fmtDay(dayKey(departure.scheduledDeparture)) : fmtDay(date)}`,
      `Time: ${c ? fmtTime(c.startTime) : departure ? fmtTime(departure.scheduledDeparture) : fmtTime(slotStart)}`,
      `Where: ${c?.resourceName ?? where}`,
      ...(c
        ? c.tickets.map((t) => `${t.type} Tickets: ${t.qty} × ${fmtMoney(t.unitPrice, c.currency)}`)
        : [
          `Adult Tickets: ${adults} × ${fmtMoney(price('adult'), currency)}`,
          ...(children > 0 ? [`Child Tickets: ${children} × ${fmtMoney(price('child'), currency)}`] : []),
          ...(infantsPriced && infants > 0 ? [`Infant Tickets: ${infants} × ${fmtMoney(price('infant'), currency)}`] : []),
        ]),
      `Total: ${c ? fmtMoney(c.total, c.currency) : fmtMoney(estimate, currency)}`,
      `Special Requests: ${notes.trim() || 'None'}`,
    ];
    return `https://wa.me/${whatsappNumber}?text=${encodeURIComponent(lines.join('\n'))}`;
  };

  const validate = () => {
    if (!fullName.trim()) return 'Please enter your full name.';
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) return 'Please enter a valid email address.';
    if (phone.trim().length < 6) return 'Please enter a phone number we can reach you on.';
    if (hasDepartures ? !departureId : !(resourceId && slotStart)) return hasDepartures ? 'Please choose a departure.' : 'Please choose a time.';
    if (adults < 1) return 'At least one adult is required.';
    if (seatsLeft != null && seats > seatsLeft) return `Only ${seatsLeft} seat${seatsLeft === 1 ? '' : 's'} left on that departure.`;
    return '';
  };

  const review = (e: React.FormEvent) => {
    e.preventDefault();
    const v = validate();
    setError(v);
    if (!v) setStage('review');
  };

  const submit = async (viaWhatsapp: boolean) => {
    setSubmitting(true);
    setError('');
    // Popup blockers only allow a window opened inside the click itself, so
    // open it now and give it the WhatsApp URL once the booking exists.
    const chat = viaWhatsapp && whatsappNumber ? window.open('', '_blank') : null;
    try {
      const { data } = await axios.post<Confirmation>(`${API_BASE_URL}/public/booking/${tenantId}`, {
        fullName: fullName.trim(), email: email.trim(), phone: phone.trim(),
        departureId: hasDepartures ? departureId : null,
        resourceId: hasDepartures ? null : resourceId,
        bookingTypeId: hasDepartures ? null : bookingType?.id ?? null,
        startTime: hasDepartures ? null : slotStart,
        adults, children, infants: infantsPriced ? infants : 0,
        notes: notes.trim() || null,
        pageUrl: document.referrer || null,
        website: honeypot,
      });
      setConfirmation(data);
      setStage('done');
      post({ type: 'unify-booking:booked', reference: data.reference });
      if (chat) chat.location.href = whatsappUrl(data);
    } catch (err) {
      chat?.close();
      const message = axios.isAxiosError(err) ? err.response?.data?.message : undefined;
      setError(message || 'We could not place the booking. Please try again or contact us directly.');
      setStage('form');
    } finally {
      setSubmitting(false);
    }
  };

  const reset = useCallback(() => {
    setStage('form'); setConfirmation(null); setDepartureId(''); setSlotStart(''); setNotes(''); setError('');
  }, []);

  /* ── Render ─────────────────────────────────────────────────────── */

  if (loadError) return <div className="ub" ref={rootRef}><div className="ub-card ub-notice">{loadError}</div></div>;
  if (!catalog) return <div className="ub" ref={rootRef}><div className="ub-card ub-notice"><span className="ub-spinner" /> Loading…</div></div>;

  const brand = (
    <header className="ub-head">
      {catalog.tenant.logoUrl && <img className="ub-logo" src={catalog.tenant.logoUrl} alt="" />}
      <div>
        <div className="ub-kicker">Book with {catalog.tenant.name}</div>
        <h2 className="ub-title">{stage === 'done' ? 'Request received' : stage === 'review' ? 'Review your booking' : 'Reserve your seats'}</h2>
      </div>
    </header>
  );

  if (stage === 'done' && confirmation) {
    return (
      <div className="ub" ref={rootRef}>
        <div className="ub-card">
          {brand}
          <div className="ub-done">
            <div className="ub-done-mark">✓</div>
            <p className="ub-done-lead">Thanks, {fullName.split(' ')[0]}. Your booking request is with the team.</p>
            <p className="ub-done-ref">Reference <b>{confirmation.reference}</b></p>
            <dl className="ub-summary">
              <dt>Where</dt><dd>{confirmation.resourceName}</dd>
              <dt>When</dt><dd>{fmtDay(dayKey(confirmation.startTime))} · {fmtTime(confirmation.startTime)}</dd>
              <dt>Tickets</dt><dd>{confirmation.tickets.map((t) => `${t.qty} × ${t.type}`).join(', ')}</dd>
              <dt>Total</dt><dd><b>{fmtMoney(confirmation.total, confirmation.currency)}</b>{confirmation.seasonLabel ? <small> · {confirmation.seasonLabel}</small> : null}</dd>
            </dl>
            <p className="ub-muted">We'll confirm by email or phone at <b>{email}</b> / <b>{phone}</b>. Nothing is charged until the team confirms.</p>
            <div className="ub-actions ub-actions-center">
              {whatsappNumber && (
                <a className="ub-btn ub-btn-whatsapp" href={whatsappUrl(confirmation)} target="_blank" rel="noreferrer">
                  <WhatsAppIcon /> Send details on WhatsApp
                </a>
              )}
              <button type="button" className="ub-btn ub-btn-ghost" onClick={reset}>Make another booking</button>
            </div>
          </div>
        </div>
        <Footer />
      </div>
    );
  }

  if (stage === 'review') {
    return (
      <div className="ub" ref={rootRef}>
        <div className="ub-card">
          {brand}
          {error && <div className="ub-error" role="alert">{error}</div>}
          <dl className="ub-summary">
            <dt>Name</dt><dd>{fullName}</dd>
            <dt>Contact</dt><dd>{email}<br />{phone}</dd>
            <dt>Where</dt><dd>{where}</dd>
            <dt>When</dt><dd>{when}</dd>
            <dt>Tickets</dt>
            <dd>
              {adults} × Adult ({fmtMoney(price('adult'), currency)})
              {children > 0 && <><br />{children} × Child ({fmtMoney(price('child'), currency)})</>}
              {infantsPriced && infants > 0 && <><br />{infants} × Infant ({fmtMoney(price('infant'), currency)})</>}
            </dd>
            {notes && <><dt>Requests</dt><dd>{notes}</dd></>}
            <dt>Estimated total</dt><dd className="ub-total">{fmtMoney(estimate, currency)}</dd>
          </dl>
          <p className="ub-muted">Seasonal rates may apply for your date; the confirmed total is shown after booking.</p>
          <div className="ub-actions">
            <button type="button" className="ub-btn ub-btn-ghost" onClick={() => setStage('form')} disabled={submitting}>Edit</button>
            {whatsappNumber ? (
              <>
                <button type="button" className="ub-btn ub-btn-ghost" onClick={() => submit(false)} disabled={submitting}>Confirm only</button>
                <button type="button" className="ub-btn ub-btn-primary" onClick={() => submit(true)} disabled={submitting}>
                  {submitting ? <><span className="ub-spinner" /> Booking…</> : <><WhatsAppIcon /> Confirm &amp; send on WhatsApp</>}
                </button>
              </>
            ) : (
              <button type="button" className="ub-btn ub-btn-primary" onClick={() => submit(false)} disabled={submitting}>
                {submitting ? <><span className="ub-spinner" /> Booking…</> : 'Confirm booking'}
              </button>
            )}
          </div>
          {whatsappNumber && <p className="ub-muted ub-center">Both send the booking to the team; WhatsApp also opens a chat with the details pre-filled.</p>}
        </div>
        <Footer />
      </div>
    );
  }

  return (
    <div className="ub" ref={rootRef}>
      <form className="ub-card" onSubmit={review} noValidate>
        {brand}
        {error && <div className="ub-error" role="alert">{error}</div>}

        <div className="ub-grid">
          <label className="ub-field ub-full">
            <span>Full name</span>
            <input value={fullName} onChange={(e) => setFullName(e.target.value)} autoComplete="name" placeholder="Your full name" required />
          </label>
          <label className="ub-field">
            <span>Email address</span>
            <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="email" placeholder="you@example.com" required />
          </label>
          <label className="ub-field">
            <span>Phone / WhatsApp</span>
            <input type="tel" value={phone} onChange={(e) => setPhone(e.target.value)} autoComplete="tel" placeholder="+94 77 000 0000" required />
          </label>

          {hasDepartures ? (
            <>
              <label className="ub-field">
                <span>Tour date</span>
                <select value={date} onChange={(e) => { setDate(e.target.value); setDepartureId(''); }} required>
                  <option value="">Choose a date</option>
                  {[...departureDays.keys()].map((k) => <option key={k} value={k}>{fmtDay(k)}</option>)}
                </select>
              </label>
              <label className="ub-field">
                <span>Departure</span>
                <select value={departureId} onChange={(e) => setDepartureId(e.target.value)} disabled={!date} required>
                  <option value="">{date ? 'Choose a departure' : 'Pick a date first'}</option>
                  {departuresOnDay.map((d) => {
                    const full = d.seatsRemaining != null && d.seatsRemaining <= 0;
                    return (
                      <option key={d.id} value={d.id} disabled={full}>
                        {fmtTime(d.scheduledDeparture)} · {d.vesselName}
                        {d.seatsRemaining != null ? (full ? ' · Full' : ` · ${d.seatsRemaining} seats left`) : ''}
                      </option>
                    );
                  })}
                </select>
              </label>
            </>
          ) : (
            <>
              <label className="ub-field">
                <span>{catalog.resources.length > 1 ? 'Choose' : 'Service'}</span>
                <select value={resourceId} onChange={(e) => { setResourceId(e.target.value); setSlotStart(''); }} required>
                  <option value="">Select…</option>
                  {catalog.resources.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
                </select>
              </label>
              <label className="ub-field">
                <span>Date</span>
                <input type="date" min={todayKey()} value={date} onChange={(e) => { setDate(e.target.value); setSlotStart(''); }} required />
              </label>
              <label className="ub-field ub-full">
                <span>Time</span>
                <select value={slotStart} onChange={(e) => setSlotStart(e.target.value)} disabled={!resourceId || !date || slots === null} required>
                  <option value="">
                    {!resourceId || !date ? 'Choose a service and date first' : slots === null ? 'Checking availability…' : slots.some((s) => s.isAvailable) ? 'Choose a time' : 'No times available that day'}
                  </option>
                  {(slots ?? []).filter((s) => s.isAvailable).map((s) => (
                    <option key={s.startTime} value={s.startTime}>{fmtTime(s.startTime)} – {fmtTime(s.endTime)}</option>
                  ))}
                </select>
              </label>
            </>
          )}

          <Counter label="Adults" hint={price('adult') ? `${fmtMoney(price('adult'), currency)} each` : '12+'} value={adults} min={1} onChange={setAdults} />
          <Counter label="Children" hint={price('child') ? `${fmtMoney(price('child'), currency)} each` : 'under 12'} value={children} min={0} onChange={setChildren} />
          {infantsPriced && (
            <Counter label="Infants" hint={price('infant') ? `${fmtMoney(price('infant'), currency)} each` : 'free'} value={infants} min={0} onChange={setInfants} />
          )}

          <label className="ub-field ub-full">
            <span>Special requests <em>(optional)</em></span>
            <textarea value={notes} onChange={(e) => setNotes(e.target.value)} rows={3} placeholder="Dietary needs, mobility, pick-up, a birthday…" maxLength={2000} />
          </label>

          {/* Honeypot - invisible to people, tempting to bots. */}
          <label className="ub-hp" aria-hidden="true">
            Website <input tabIndex={-1} autoComplete="off" value={honeypot} onChange={(e) => setHoneypot(e.target.value)} />
          </label>
        </div>

        <div className="ub-bar">
          <div>
            <div className="ub-bar-label">Estimated total</div>
            <div className="ub-bar-total">{fmtMoney(estimate, currency)}</div>
            <div className="ub-muted">{seats} seat{seats === 1 ? '' : 's'}{seatsLeft != null ? ` · ${seatsLeft} left` : ''}</div>
          </div>
          <button type="submit" className="ub-btn ub-btn-primary">Preview booking</button>
        </div>
      </form>
      <Footer />
    </div>
  );
}

function Counter({ label, hint, value, min, onChange }: { label: string; hint: string; value: number; min: number; onChange: (n: number) => void }) {
  return (
    <div className="ub-field">
      <span>{label} <em>{hint}</em></span>
      <div className="ub-counter">
        <button type="button" onClick={() => onChange(Math.max(min, value - 1))} aria-label={`Fewer ${label.toLowerCase()}`} disabled={value <= min}>−</button>
        <output>{value}</output>
        <button type="button" onClick={() => onChange(Math.min(20, value + 1))} aria-label={`More ${label.toLowerCase()}`}>+</button>
      </div>
    </div>
  );
}

function WhatsAppIcon() {
  return (
    <svg width="17" height="17" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M12 2a10 10 0 0 0-8.6 15.1L2 22l5-1.3A10 10 0 1 0 12 2Zm0 18.2a8.2 8.2 0 0 1-4.2-1.2l-.3-.2-3 .8.8-2.9-.2-.3A8.2 8.2 0 1 1 12 20.2Zm4.5-6.1c-.2-.1-1.5-.7-1.7-.8s-.4-.1-.6.1-.6.8-.8 1-.3.2-.5.1a6.7 6.7 0 0 1-3.3-2.9c-.3-.4.3-.4.7-1.3.1-.2 0-.3 0-.4l-.8-1.8c-.2-.5-.4-.4-.6-.4h-.5a1 1 0 0 0-.7.3 3 3 0 0 0-.9 2.2 5.2 5.2 0 0 0 1.1 2.7 11.8 11.8 0 0 0 4.5 4c1.7.7 2 .6 2.7.5a2.3 2.3 0 0 0 1.5-1.1 1.9 1.9 0 0 0 .1-1.1c0-.1-.2-.2-.5-.3Z" />
    </svg>
  );
}

function Footer() {
  return <p className="ub-foot">Secure booking powered by <b>Unify</b></p>;
}
