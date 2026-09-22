import { useState } from 'react';
import { useToast } from '../../shared/components/Toast';

/* The snippet a business pastes into its own website to take bookings there.
 *
 * Everything the snippet needs is the tenant id and this deployment's origin;
 * the loader (public/embed.js) does the rest. Shown here rather than in docs
 * because the person who needs it is the business admin, not a developer,
 * and they are already on this page setting up their business.
 */
export default function WebsiteWidgetCard({ tenantId }: { tenantId: string }) {
  const { show } = useToast();
  const [accent, setAccent] = useState('#2563eb');
  const [theme, setTheme] = useState<'light' | 'dark'>('light');
  const [whatsapp, setWhatsapp] = useState('');
  const whatsappDigits = whatsapp.replace(/[^0-9]/g, '');

  const origin = window.location.origin;
  const previewUrl = `${origin}/embed/book/${tenantId}?accent=${encodeURIComponent(accent.replace('#', ''))}&theme=${theme}${whatsappDigits ? `&whatsapp=${whatsappDigits}` : ''}`;
  const snippet = [
    `<div data-unify-booking="${tenantId}" data-accent="${accent}"${theme === 'dark' ? ' data-theme="dark"' : ''}${whatsappDigits ? ` data-whatsapp="${whatsappDigits}"` : ''}></div>`,
    `<script src="${origin}/embed.js" async></script>`,
  ].join('\n');

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(snippet);
      show('Snippet copied. Paste it where the booking form should appear.', 'success');
    } catch {
      show('Could not copy automatically — select the text and copy it.', 'error');
    }
  };

  return (
    <div className="card" style={{ padding: 20, maxWidth: 640, marginTop: 20 }}>
      <h2 style={{ margin: '0 0 4px', fontSize: '1.05rem' }}>Website booking widget</h2>
      <p className="page-subtitle" style={{ margin: '0 0 16px' }}>
        Take bookings on your own website. Paste this snippet into the page where you want the form;
        every booking arrives here as a <b>Pending</b> booking with source <b>Website</b>, for you to confirm.
      </p>

      <div className="form-grid">
        <div className="field">
          <label htmlFor="widget-accent">Button colour</label>
          <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
            <input id="widget-accent" type="color" value={accent} onChange={(e) => setAccent(e.target.value)}
              style={{ width: 44, height: 38, padding: 2, border: '1px solid var(--color-border-strong)', borderRadius: 8, background: 'transparent' }} />
            <input className="input" value={accent} onChange={(e) => setAccent(e.target.value)} style={{ fontFamily: 'monospace' }} />
          </div>
        </div>
        <div className="field">
          <label htmlFor="widget-theme">Theme</label>
          <select id="widget-theme" className="input" value={theme} onChange={(e) => setTheme(e.target.value as 'light' | 'dark')}>
            <option value="light">Light (for light pages)</option>
            <option value="dark">Dark (for dark pages)</option>
          </select>
        </div>
        <div className="field field-full">
          <label htmlFor="widget-whatsapp">WhatsApp number <span style={{ fontWeight: 400, color: 'var(--color-text-secondary)' }}>(optional)</span></label>
          <input id="widget-whatsapp" className="input" value={whatsapp} onChange={(e) => setWhatsapp(e.target.value)}
            placeholder="94 77 000 0000 — with country code" inputMode="tel" />
          <small style={{ color: 'var(--color-text-secondary)' }}>
            If set, confirming a booking also opens WhatsApp with the details pre-filled, so your team still gets the
            message they're used to. The booking is recorded here either way.
          </small>
        </div>
        <div className="field field-full">
          <label htmlFor="widget-snippet">Snippet</label>
          <textarea id="widget-snippet" className="input" readOnly rows={3} value={snippet} onFocus={(e) => e.currentTarget.select()}
            style={{ fontFamily: 'monospace', fontSize: '.82rem', resize: 'vertical' }} />
        </div>
        <div className="field field-full" style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
          <button type="button" className="btn btn-primary" onClick={copy}>Copy snippet</button>
          <a className="btn btn-secondary" href={previewUrl} target="_blank" rel="noreferrer">Preview the form</a>
        </div>
      </div>

      <p className="page-subtitle" style={{ margin: '14px 0 0', fontSize: '.82rem' }}>
        Works on any site — plain HTML, WordPress, Wix or Squarespace custom-code blocks. The form shows your
        upcoming departures and ticket prices automatically; nothing else to configure.
      </p>
    </div>
  );
}
