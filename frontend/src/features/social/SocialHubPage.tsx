import { useEffect, useMemo, useState } from 'react';
import { useSelector } from 'react-redux';
import { useSearchParams } from 'react-router-dom';
import { QRCodeSVG } from 'qrcode.react';
import type { RootState } from '../../store/store';
import { useToast } from '../../shared/components/Toast';
import { useConfirmation } from '../../shared/components/ConfirmationProvider';
import { errorMessage } from '../billing/billingApi';
import { useAsync } from '../billing/useAsync';
import { buildBookingLink, AD_URL_TEMPLATES } from '../embed/attribution';
import { socialApi, type Platform, type SocialAccount } from './socialApi';
import { PlatformMark, SoBadge, copyText, relativeTime } from './components';
import '../billing/billing.css';
import './social.css';

const TIKTOK_PRIVACY: Record<string, string> = {
  PUBLIC_TO_EVERYONE: 'Public',
  FOLLOWER_OF_CREATOR: 'Followers',
  MUTUAL_FOLLOW_FRIENDS: 'Friends',
  SELF_ONLY: 'Only me',
};

/* Where a business connects Facebook, Instagram and TikTok, and gets the
 * tracked booking links that make every social booking attributable. */
export default function SocialHubPage() {
  const toast = useToast();
  const confirm = useConfirmation();
  const user = useSelector((s: RootState) => s.auth.user);
  const canManage = user?.role === 'Admin' || user?.role === 'Manager';
  const [params, setParams] = useSearchParams();

  const accounts = useAsync(() => socialApi.accounts(), []);
  const status = useAsync(() => (canManage ? socialApi.status() : Promise.resolve(null)), [canManage]);
  const [busy, setBusy] = useState<string | null>(null);

  /* Back from the provider's consent screen. */
  useEffect(() => {
    const connected = params.get('connected');
    const error = params.get('error');
    if (!connected && !error) return;
    if (connected) {
      const n = Number(params.get('count') ?? '0');
      toast.show(`${connected === 'meta' ? 'Facebook/Instagram' : 'TikTok'} connected${n > 1 ? ` — ${n} accounts added` : ''}.`, 'success');
      void accounts.reload();
    } else if (error) {
      toast.show(error, 'error');
    }
    setParams({}, { replace: true });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const connect = async (provider: 'meta' | 'tiktok') => {
    setBusy(provider);
    try {
      const { url } = await socialApi.connect(provider);
      window.location.assign(url);
    } catch (err) {
      toast.show(errorMessage(err, 'Could not start the connection.'), 'error');
      setBusy(null);
    }
  };

  const addSandbox = async (platform: Platform) => {
    setBusy('sandbox-' + platform);
    try {
      await socialApi.addSandbox(platform);
      toast.show(`Sandbox ${platform} account added. Posts to it are simulated — nothing reaches ${platform}.`, 'success');
      void accounts.reload();
    } catch (err) {
      toast.show(errorMessage(err, 'Could not add the sandbox account.'), 'error');
    } finally {
      setBusy(null);
    }
  };

  const refresh = async (a: SocialAccount) => {
    setBusy(a.id);
    try {
      const updated = await socialApi.refreshAccount(a.id);
      toast.show(updated.status === 'Connected' && !updated.lastError ? 'Account checked — the connection works.' : (updated.lastError ?? 'Account needs attention.'),
        updated.status === 'Connected' && !updated.lastError ? 'success' : 'error');
      void accounts.reload();
    } catch (err) {
      toast.show(errorMessage(err, 'Could not check the account.'), 'error');
    } finally {
      setBusy(null);
    }
  };

  const disconnect = async (a: SocialAccount) => {
    if (!await confirm({
      title: `Disconnect ${a.displayName}?`,
      message: 'Scheduled posts to this account will be cancelled. Already-published posts stay on the platform, and their history stays here.',
      confirmLabel: 'Disconnect',
      tone: 'danger',
    })) return;
    try {
      await socialApi.disconnect(a.id);
      void accounts.reload();
    } catch (err) {
      toast.show(errorMessage(err, 'Could not disconnect.'), 'error');
    }
  };

  const setPrivacy = async (a: SocialAccount, value: string) => {
    try {
      await socialApi.updateAccount(a.id, { defaultPrivacy: value });
      void accounts.reload();
    } catch (err) {
      toast.show(errorMessage(err, 'Could not save.'), 'error');
    }
  };

  const list = accounts.data ?? [];
  const metaConfigured = status.data?.meta.configured ?? false;
  const tiktokConfigured = status.data?.tiktok.configured ?? false;

  return (
    <div className="bl-page">
      <div className="page-header">
        <div>
          <h1 className="page-title">Social accounts</h1>
          <p className="page-subtitle">
            Connect Facebook Pages, Instagram and TikTok to publish from one place, answer DMs in one inbox, and see which posts and ads bring in bookings.
          </p>
        </div>
      </div>

      {accounts.error && <div className="bl-notice bl-notice-critical">{accounts.error}</div>}

      {canManage && (
        <div className="bl-grid-3">
          <div className="so-connect">
            <div className="bl-row"><PlatformMark platform="Facebook" /><PlatformMark platform="Instagram" /><strong>Facebook &amp; Instagram</strong></div>
            <p className="bl-small bl-muted" style={{ margin: 0 }}>
              One sign-in adds every Facebook Page you manage and the Instagram professional account linked to each. It also lets the Ads page read campaign spend.
            </p>
            <button className="btn btn-primary" disabled={busy === 'meta' || !metaConfigured} onClick={() => connect('meta')}>
              {busy === 'meta' ? 'Opening Facebook…' : 'Continue with Facebook'}
            </button>
            {!metaConfigured && status.data && <span className="bl-small bl-muted">Not set up on this server yet — see “Server setup” below.</span>}
          </div>
          <div className="so-connect">
            <div className="bl-row"><PlatformMark platform="TikTok" /><strong>TikTok</strong></div>
            <p className="bl-small bl-muted" style={{ margin: 0 }}>
              Post videos and photo carousels to a TikTok account. Connect each TikTok account separately.
            </p>
            <button className="btn btn-primary" disabled={busy === 'tiktok' || !tiktokConfigured} onClick={() => connect('tiktok')}>
              {busy === 'tiktok' ? 'Opening TikTok…' : 'Continue with TikTok'}
            </button>
            {!tiktokConfigured && status.data && <span className="bl-small bl-muted">Not set up on this server yet — see “Server setup” below.</span>}
          </div>
          <div className="so-connect">
            <strong>Try it in sandbox</strong>
            <p className="bl-small bl-muted" style={{ margin: 0 }}>
              A sandbox account behaves like the real thing — schedule posts, receive and answer test DMs — but nothing is sent to the platform.
            </p>
            <div className="bl-row">
              {(['Facebook', 'Instagram', 'TikTok'] as Platform[]).map((p) => (
                <button key={p} className="btn btn-secondary btn-sm" disabled={busy === 'sandbox-' + p} onClick={() => addSandbox(p)}>
                  + {p}
                </button>
              ))}
            </div>
          </div>
        </div>
      )}

      <section className="bl-stack">
        <h2 style={{ margin: 0, fontSize: '1.05rem' }}>Connected accounts</h2>
        {accounts.loading && !accounts.data && <div className="loading-row"><span className="spinner spinner-dark" /></div>}
        {accounts.data && list.length === 0 && (
          <div className="bl-notice">No accounts yet. Connect one above, or add a sandbox account to try things out first.</div>
        )}
        <div className="bl-grid-2">
          {list.map((a) => (
            <div key={a.id} className="so-account">
              {a.avatarUrl ? <img className="so-avatar" src={a.avatarUrl} alt="" referrerPolicy="no-referrer" /> : <PlatformMark platform={a.platform} />}
              <div className="so-account-body">
                <div className="bl-spread">
                  <div className="so-account-name">{a.displayName}</div>
                  <div className="bl-row">
                    {a.isSandbox && <span className="bl-badge bl-badge-primary">Sandbox</span>}
                    <SoBadge status={a.status} />
                  </div>
                </div>
                <div className="bl-small bl-muted bl-row" style={{ gap: 6 }}>
                  <PlatformMark platform={a.platform} small /> {a.platform}
                  {a.handle && <span>· @{a.handle}</span>}
                  <span>· checked {relativeTime(a.lastSyncedAt)}</span>
                </div>
                {a.lastError && <div className="bl-small" style={{ color: 'var(--color-critical)', marginTop: 6 }}>{a.lastError}</div>}
                {a.platform === 'TikTok' && canManage && (
                  <div className="bl-row" style={{ marginTop: 8 }}>
                    <label className="bl-small bl-muted" htmlFor={`priv-${a.id}`}>Who can see posts</label>
                    <select id={`priv-${a.id}`} className="input" style={{ width: 'auto', padding: '4px 8px' }}
                      value={a.defaultPrivacy ?? 'PUBLIC_TO_EVERYONE'} onChange={(e) => setPrivacy(a, e.target.value)}>
                      {Object.entries(TIKTOK_PRIVACY).map(([v, l]) => <option key={v} value={v}>{l}</option>)}
                    </select>
                  </div>
                )}
                {canManage && (
                  <div className="bl-row" style={{ marginTop: 10 }}>
                    {a.status === 'NeedsReconnect' && !a.isSandbox && (
                      <button className="btn btn-primary btn-sm" onClick={() => connect(a.platform === 'TikTok' ? 'tiktok' : 'meta')}>Reconnect</button>
                    )}
                    <button className="btn btn-secondary btn-sm" disabled={busy === a.id} onClick={() => refresh(a)}>{busy === a.id ? 'Checking…' : 'Check connection'}</button>
                    <button className="btn btn-ghost btn-sm" onClick={() => disconnect(a)}>Disconnect</button>
                  </div>
                )}
              </div>
            </div>
          ))}
        </div>
      </section>

      {user?.tenantId && <BookingLinks tenantId={user.tenantId} />}

      {canManage && status.data && <ServerSetup status={status.data} />}
    </div>
  );
}

const PRESETS: { id: string; label: string; source: string; medium: string; campaign: string; hint: string }[] = [
  { id: 'ig-bio', label: 'Instagram bio', source: 'instagram', medium: 'social', campaign: 'bio', hint: 'Paste into Edit profile → Links.' },
  { id: 'ig-story', label: 'Instagram story', source: 'instagram', medium: 'social', campaign: 'story', hint: 'Use the Link sticker.' },
  { id: 'fb-page', label: 'Facebook Page button', source: 'facebook', medium: 'social', campaign: 'page-button', hint: 'Page → Add action button → Book now → Website.' },
  { id: 'fb-post', label: 'Facebook post', source: 'facebook', medium: 'social', campaign: 'post', hint: 'Add to any post or the composer’s link field.' },
  { id: 'tiktok-bio', label: 'TikTok bio', source: 'tiktok', medium: 'social', campaign: 'bio', hint: 'Edit profile → Website (business accounts).' },
];

function BookingLinks({ tenantId }: { tenantId: string }) {
  const toast = useToast();
  const [preset, setPreset] = useState(PRESETS[0].id);
  const [campaign, setCampaign] = useState('');
  const chosen = PRESETS.find((p) => p.id === preset)!;
  const link = useMemo(() => buildBookingLink({
    origin: window.location.origin, tenantId, source: chosen.source, medium: chosen.medium, campaign: campaign.trim() || chosen.campaign,
  }), [tenantId, chosen, campaign]);

  return (
    <section className="card bl-stack" style={{ padding: 20 }}>
      <div>
        <h2 style={{ margin: 0, fontSize: '1.05rem' }}>Tracked booking links</h2>
        <p className="page-subtitle" style={{ margin: '4px 0 0' }}>
          Every booking made through one of these links shows up with its source (Instagram, Facebook, TikTok) and campaign, so the Ads page can tell you what actually brings customers.
        </p>
      </div>
      <div className="bl-grid-2" style={{ alignItems: 'start' }}>
        <div className="bl-stack">
          <div className="field" style={{ margin: 0 }}>
            <label htmlFor="link-preset">Where will you put it?</label>
            <select id="link-preset" className="input" value={preset} onChange={(e) => setPreset(e.target.value)}>
              {PRESETS.map((p) => <option key={p.id} value={p.id}>{p.label}</option>)}
            </select>
            <span className="bl-small bl-muted">{chosen.hint}</span>
          </div>
          <div className="field" style={{ margin: 0 }}>
            <label htmlFor="link-campaign">Campaign name <span className="bl-muted" style={{ fontWeight: 400 }}>(optional)</span></label>
            <input id="link-campaign" className="input" value={campaign} placeholder={chosen.campaign} onChange={(e) => setCampaign(e.target.value)} />
          </div>
          <code className="so-code">{link}</code>
          <div className="bl-row">
            <button className="btn btn-primary btn-sm" onClick={() => copyText(link, toast.show, 'Link copied.')}>Copy link</button>
            <a className="btn btn-secondary btn-sm" href={link} target="_blank" rel="noreferrer">Open booking page</a>
          </div>
        </div>
        <div className="bl-stack" style={{ alignItems: 'center' }}>
          <div style={{ background: '#fff', padding: 12, borderRadius: 12, border: '1px solid var(--color-border)' }}>
            <QRCodeSVG value={link} size={168} />
          </div>
          <span className="bl-small bl-muted">For flyers, menus and the counter.</span>
        </div>
      </div>
      <details>
        <summary style={{ cursor: 'pointer', fontWeight: 600 }}>For paid ads: URL parameters</summary>
        <p className="bl-small bl-muted">
          Paste these into the ad’s <em>URL parameters</em> field, with the booking page as the website URL. Each click then carries its campaign id, which is how the campaign report matches ad spend to bookings exactly.
        </p>
        <div className="bl-stack" style={{ gap: 8 }}>
          <div><span className="bl-label">Meta (Facebook &amp; Instagram ads)</span><code className="so-code">{AD_URL_TEMPLATES.meta}</code></div>
          <div><span className="bl-label">TikTok ads</span><code className="so-code">{AD_URL_TEMPLATES.tiktok}</code></div>
          <div><span className="bl-label">Website URL for the ad</span><code className="so-code">{`${window.location.origin}/embed/book/${tenantId}`}</code></div>
        </div>
      </details>
    </section>
  );
}

function ServerSetup({ status }: { status: NonNullable<Awaited<ReturnType<typeof socialApi.status>>> }) {
  const toast = useToast();
  const allSet = status.meta.configured && status.tiktok.configured && status.webhook.verifyTokenConfigured;
  return (
    <details className="card" style={{ padding: 20 }} open={!status.meta.configured && !status.tiktok.configured}>
      <summary style={{ cursor: 'pointer', fontWeight: 700 }}>
        Server setup {allSet ? <span className="bl-badge bl-badge-good" style={{ marginLeft: 8 }}>Complete</span> : <span className="bl-badge bl-badge-warning" style={{ marginLeft: 8 }}>Needs attention</span>}
      </summary>
      <div className="bl-grid-2" style={{ marginTop: 14 }}>
        <div className="bl-stack" style={{ gap: 8 }}>
          <div className="bl-row"><PlatformMark platform="Facebook" small /><strong>Meta app</strong> <SoBadge status={status.meta.configured ? 'Connected' : 'Pending'} /></div>
          <ol className="so-steps">
            <li>Create a <strong>Business</strong> app at developers.facebook.com and add <em>Facebook Login for Business</em>, <em>Instagram</em>, <em>Messenger</em> and <em>Marketing API</em>.</li>
            <li>Add this as a valid OAuth redirect URI:</li>
          </ol>
          <code className="so-code" onClick={() => copyText(status.meta.redirectUri, toast.show)}>{status.meta.redirectUri}</code>
          <ol className="so-steps" start={3}>
            <li>Webhooks → Page and Instagram → callback URL below, subscribe to <code>messages</code>:</li>
          </ol>
          <code className="so-code" onClick={() => copyText(status.webhook.url, toast.show)}>{status.webhook.url}</code>
          <ol className="so-steps" start={4}>
            <li>Set on the API server: <code>Social__Meta__AppId</code>, <code>Social__Meta__AppSecret</code>, <code>Social__Meta__WebhookVerifyToken</code>{status.webhook.verifyTokenConfigured ? ' (verify token is set)' : ''}.</li>
            <li>Until App Review approves the permissions, only people with a role on the app can connect.</li>
          </ol>
        </div>
        <div className="bl-stack" style={{ gap: 8 }}>
          <div className="bl-row"><PlatformMark platform="TikTok" small /><strong>TikTok app</strong> <SoBadge status={status.tiktok.configured ? 'Connected' : 'Pending'} /></div>
          <ol className="so-steps">
            <li>Create an app at developers.tiktok.com with <em>Login Kit</em> and <em>Content Posting API</em> (Direct Post).</li>
            <li>Add this redirect URI:</li>
          </ol>
          <code className="so-code" onClick={() => copyText(status.tiktok.redirectUri, toast.show)}>{status.tiktok.redirectUri}</code>
          <ol className="so-steps" start={3}>
            <li>Verify the domain your media is hosted on (TikTok pulls files from it).</li>
            <li>Set on the API server: <code>Social__TikTok__ClientKey</code>, <code>Social__TikTok__ClientSecret</code>.</li>
            <li>Unaudited TikTok apps can only post as <em>Only me</em>; the publisher picks that automatically until your app passes audit.</li>
          </ol>
        </div>
      </div>
    </details>
  );
}
