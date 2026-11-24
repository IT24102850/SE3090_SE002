import { useEffect, useMemo, useRef, useState } from 'react';
import { useSelector } from 'react-redux';
import { Link } from 'react-router-dom';
import type { RootState } from '../../store/store';
import { useToast } from '../../shared/components/Toast';
import { useConfirmation } from '../../shared/components/ConfirmationProvider';
import { errorMessage } from '../billing/billingApi';
import { useAsync } from '../billing/useAsync';
import { buildBookingLink } from '../embed/attribution';
import { socialApi, type MediaType, type Platform, type SocialAccount, type SocialPost, type UpsertPost } from './socialApi';
import { PlatformMark, SoBadge, dateTime, relativeTime } from './components';
import { CAPTION_LIMIT, captionWithLink, fromLocalInput, postProblem, toLocalInput } from './postRules';
import '../billing/billing.css';
import './social.css';

const FILTERS: { id: string; label: string }[] = [
  { id: '', label: 'All' },
  { id: 'Scheduled', label: 'Scheduled' },
  { id: 'Published', label: 'Published' },
  { id: 'Failed', label: 'Failed' },
  { id: 'Draft', label: 'Drafts' },
];

const EMPTY: UpsertPost = { caption: '', mediaType: 'None', mediaUrl: null, linkUrl: null, scheduledAt: null, accountIds: [], asDraft: false };

export default function SocialPublisherPage() {
  const toast = useToast();
  const confirm = useConfirmation();
  const tenantId = useSelector((s: RootState) => s.auth.user?.tenantId) ?? '';
  const accounts = useAsync(() => socialApi.accounts(), []);
  const [filter, setFilter] = useState('');
  const posts = useAsync(() => socialApi.posts({ status: filter || undefined, pageSize: 50 }), [filter]);
  const [editing, setEditing] = useState<string | null>(null);
  const [form, setForm] = useState<UpsertPost>(EMPTY);
  const [when, setWhen] = useState<'now' | 'later'>('now');
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);

  const usable = (accounts.data ?? []).filter((a) => a.status !== 'Disconnected');
  const chosen = usable.filter((a) => form.accountIds.includes(a.id));

  /* Keep the list fresh while anything is in flight. */
  const inFlight = posts.data?.items.some((p) => p.status === 'Publishing' || (p.status === 'Scheduled' && (!p.scheduledAt || new Date(p.scheduledAt).getTime() - Date.now() < 5 * 60_000)));
  useEffect(() => {
    if (!inFlight) return;
    const t = window.setInterval(() => { void posts.reload(); }, 10_000);
    return () => window.clearInterval(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [inFlight]);

  const problems = useMemo(() => chosen
    .map((a) => ({ a, problem: postProblem(a.platform, form.caption, form.mediaType, form.mediaUrl) }))
    .filter((x) => x.problem), [chosen, form.caption, form.mediaType, form.mediaUrl]);

  const toggle = (a: SocialAccount) => setForm((f) => ({
    ...f,
    accountIds: f.accountIds.includes(a.id) ? f.accountIds.filter((id) => id !== a.id) : [...f.accountIds, a.id],
  }));

  const insertBookingLink = () => {
    const platforms = new Set(chosen.map((a) => a.platform.toLowerCase()));
    const source = platforms.size === 1 ? [...platforms][0] : 'social';
    setForm((f) => ({ ...f, linkUrl: buildBookingLink({ origin: window.location.origin, tenantId, source, medium: 'social', campaign: 'post' }) }));
  };

  const upload = async (file: File) => {
    if (!/^image\/(jpe?g|png|webp)$/.test(file.type)) {
      toast.show('Upload a JPG, PNG or WebP image. For video, paste a public https link to the file.', 'error');
      return;
    }
    if (file.size > 5 * 1024 * 1024) {
      toast.show('Images must be 5 MB or smaller.', 'error');
      return;
    }
    setUploading(true);
    try {
      const { url } = await socialApi.uploadImage(file);
      setForm((f) => ({ ...f, mediaType: 'Image', mediaUrl: url }));
    } catch (err) {
      toast.show(errorMessage(err, 'The image could not be uploaded.'), 'error');
    } finally {
      setUploading(false);
      if (fileRef.current) fileRef.current.value = '';
    }
  };

  const reset = () => {
    setEditing(null);
    setForm(EMPTY);
    setWhen('now');
  };

  const edit = (p: SocialPost, duplicate = false) => {
    setEditing(duplicate ? null : p.id);
    setForm({
      caption: p.caption,
      mediaType: p.mediaType,
      mediaUrl: p.mediaUrl,
      linkUrl: p.linkUrl,
      scheduledAt: duplicate ? null : p.scheduledAt,
      accountIds: p.targets.map((t) => t.accountId).filter((id) => usable.some((a) => a.id === id)),
      asDraft: false,
    });
    setWhen(!duplicate && p.scheduledAt && new Date(p.scheduledAt) > new Date() ? 'later' : 'now');
    window.scrollTo({ top: 0, behavior: 'smooth' });
  };

  const save = async (asDraft: boolean) => {
    if (form.accountIds.length === 0) {
      toast.show('Choose at least one account.', 'error');
      return;
    }
    if (!asDraft && when === 'later' && !form.scheduledAt) {
      toast.show('Pick a date and time, or choose “Publish now”.', 'error');
      return;
    }
    const body: UpsertPost = { ...form, asDraft, scheduledAt: when === 'later' ? form.scheduledAt : null };
    setSaving(true);
    try {
      if (editing) await socialApi.updatePost(editing, body);
      else await socialApi.createPost(body);
      toast.show(asDraft ? 'Draft saved.' : when === 'later' ? `Scheduled for ${dateTime(body.scheduledAt)}.` : 'Publishing now — status updates below.', 'success');
      reset();
      void posts.reload();
    } catch (err) {
      toast.show(errorMessage(err, 'The post could not be saved.'), 'error');
    } finally {
      setSaving(false);
    }
  };

  const act = async (label: string, fn: () => Promise<unknown>) => {
    try {
      await fn();
      void posts.reload();
    } catch (err) {
      toast.show(errorMessage(err, `Could not ${label}.`), 'error');
    }
  };

  const remove = async (p: SocialPost) => {
    if (!await confirm({
      title: 'Delete this post from Unify?',
      message: p.targets.some((t) => t.status === 'Published')
        ? 'It stays live on the platforms — delete it there if you want it gone. Only the record here is removed.'
        : 'Anything not yet sent will not be sent.',
      confirmLabel: 'Delete',
      tone: 'danger',
    })) return;
    await act('delete the post', () => socialApi.deletePost(p.id));
  };

  const minLocal = toLocalInput(new Date(Date.now() + 2 * 60_000).toISOString());
  const previewAccount = chosen[0];
  const previewCaption = previewAccount && previewAccount.platform !== 'Facebook' ? captionWithLink(form.caption, form.linkUrl) : form.caption;

  return (
    <div className="bl-page">
      <div className="page-header">
        <div>
          <h1 className="page-title">Publisher</h1>
          <p className="page-subtitle">Write once, publish to Facebook, Instagram and TikTok — now or on a schedule. Failed posts retry automatically.</p>
        </div>
      </div>

      {accounts.data && usable.length === 0 && (
        <div className="bl-notice">No social accounts are connected. <Link to="/social">Connect one</Link> (or add a sandbox account) to start publishing.</div>
      )}

      <div className="card" style={{ padding: 20 }}>
        <div className="bl-spread" style={{ marginBottom: 12 }}>
          <h2 style={{ margin: 0, fontSize: '1.05rem' }}>{editing ? 'Edit post' : 'New post'}</h2>
          {editing && <button className="btn btn-ghost btn-sm" onClick={reset}>Cancel editing</button>}
        </div>
        <div className="so-composer">
          <div className="bl-stack">
            <div className="field" style={{ margin: 0 }}>
              <label>Publish to</label>
              <div className="bl-row">
                {usable.map((a) => (
                  <button key={a.id} type="button" className="so-pick" aria-pressed={form.accountIds.includes(a.id)}
                    disabled={a.status !== 'Connected'} title={a.status !== 'Connected' ? 'Reconnect this account first' : undefined}
                    onClick={() => toggle(a)}>
                    <PlatformMark platform={a.platform} small />
                    {a.displayName}{a.isSandbox ? ' (sandbox)' : ''}
                  </button>
                ))}
              </div>
            </div>

            <div className="field" style={{ margin: 0 }}>
              <label htmlFor="post-caption">Caption</label>
              <textarea id="post-caption" className="input" rows={6} value={form.caption}
                placeholder="What's new? Add hashtags at the end — #whalewatching #mirissa"
                onChange={(e) => setForm((f) => ({ ...f, caption: e.target.value }))} />
              <div className="bl-row" style={{ justifyContent: 'flex-end', gap: 12 }}>
                {[...new Set(chosen.map((a) => a.platform))].map((p) => (
                  <span key={p} className={`so-counter${form.caption.length > CAPTION_LIMIT[p] ? ' so-counter-over' : ''}`}>
                    {p}: {form.caption.length.toLocaleString()} / {CAPTION_LIMIT[p].toLocaleString()}
                  </span>
                ))}
              </div>
            </div>

            <div className="bl-grid-2">
              <div className="field" style={{ margin: 0 }}>
                <label htmlFor="post-media-type">Media</label>
                <select id="post-media-type" className="input" value={form.mediaType}
                  onChange={(e) => setForm((f) => ({ ...f, mediaType: e.target.value as MediaType, mediaUrl: e.target.value === 'None' ? null : f.mediaUrl }))}>
                  <option value="None">No media (Facebook only)</option>
                  <option value="Image">Image</option>
                  <option value="Video">Video</option>
                </select>
              </div>
              {form.mediaType !== 'None' && (
                <div className="field" style={{ margin: 0 }}>
                  <label htmlFor="post-media-url">{form.mediaType} URL</label>
                  <div className="bl-row" style={{ flexWrap: 'nowrap' }}>
                    <input id="post-media-url" className="input" value={form.mediaUrl ?? ''} placeholder="https://…"
                      onChange={(e) => setForm((f) => ({ ...f, mediaUrl: e.target.value || null }))} />
                    {form.mediaType === 'Image' && (
                      <>
                        <input ref={fileRef} type="file" accept="image/jpeg,image/png,image/webp" hidden onChange={(e) => e.target.files?.[0] && upload(e.target.files[0])} />
                        <button type="button" className="btn btn-secondary btn-sm" disabled={uploading} onClick={() => fileRef.current?.click()}>
                          {uploading ? 'Uploading…' : 'Upload'}
                        </button>
                      </>
                    )}
                  </div>
                  {form.mediaType === 'Video' && <span className="bl-small bl-muted">MP4, public https link. Instagram Reels: 3–90 s. TikTok fetches it from your verified domain.</span>}
                </div>
              )}
            </div>

            <div className="field" style={{ margin: 0 }}>
              <label htmlFor="post-link">Link</label>
              <div className="bl-row" style={{ flexWrap: 'nowrap' }}>
                <input id="post-link" className="input" value={form.linkUrl ?? ''} placeholder="https://…"
                  onChange={(e) => setForm((f) => ({ ...f, linkUrl: e.target.value || null }))} />
                <button type="button" className="btn btn-secondary btn-sm" onClick={insertBookingLink} disabled={!tenantId}>Use booking link</button>
              </div>
              <span className="bl-small bl-muted">Facebook shows a link card. Instagram and TikTok captions aren’t clickable, so the link is added to the end of the caption there.</span>
            </div>

            <div className="field" style={{ margin: 0 }}>
              <label>When</label>
              <div className="bl-row">
                <label className="bl-row" style={{ gap: 6, fontWeight: 400 }}>
                  <input type="radio" name="when" checked={when === 'now'} onChange={() => setWhen('now')} /> Publish now
                </label>
                <label className="bl-row" style={{ gap: 6, fontWeight: 400 }}>
                  <input type="radio" name="when" checked={when === 'later'} onChange={() => setWhen('later')} /> Schedule
                </label>
                {when === 'later' && (
                  <input type="datetime-local" className="input" style={{ width: 'auto' }} min={minLocal}
                    value={toLocalInput(form.scheduledAt)} onChange={(e) => setForm((f) => ({ ...f, scheduledAt: fromLocalInput(e.target.value) }))} />
                )}
              </div>
            </div>

            {problems.length > 0 && (
              <div className="bl-notice bl-notice-critical">
                {problems.map(({ a, problem }) => <div key={a.id}><strong>{a.displayName}:</strong> {problem}</div>)}
              </div>
            )}

            <div className="bl-row">
              <button className="btn btn-primary" disabled={saving || form.accountIds.length === 0 || problems.length > 0} onClick={() => save(false)}>
                {saving ? 'Saving…' : when === 'later' ? 'Schedule' : 'Publish now'}
              </button>
              <button className="btn btn-secondary" disabled={saving || form.accountIds.length === 0} onClick={() => save(true)}>Save draft</button>
            </div>
          </div>

          <div className="bl-stack">
            <span className="bl-label">Preview{previewAccount ? ` · ${previewAccount.platform}` : ''}</span>
            <div className="so-preview">
              <div className="so-preview-head">
                {previewAccount ? <PlatformMark platform={previewAccount.platform} small /> : null}
                {previewAccount?.displayName ?? 'Choose an account'}
              </div>
              {form.mediaType === 'Image' && form.mediaUrl && <img className="so-preview-media" src={form.mediaUrl} alt="" />}
              {form.mediaType === 'Video' && form.mediaUrl && <video className="so-preview-media" src={form.mediaUrl} controls muted />}
              <div className="so-preview-text">{previewCaption || <span className="bl-muted">Your caption appears here.</span>}</div>
              {previewAccount?.platform === 'Facebook' && form.linkUrl && (
                <div className="so-preview-text bl-small bl-muted" style={{ borderTop: '1px solid var(--color-border)' }}>🔗 {form.linkUrl}</div>
              )}
            </div>
          </div>
        </div>
      </div>

      <section className="bl-stack">
        <div className="bl-tabs" role="tablist">
          {FILTERS.map((f) => (
            <button key={f.id} role="tab" aria-selected={filter === f.id} className={`bl-tab${filter === f.id ? ' bl-tab-active' : ''}`} onClick={() => setFilter(f.id)}>{f.label}</button>
          ))}
        </div>
        {posts.error && <div className="bl-notice bl-notice-critical">{posts.error}</div>}
        {posts.loading && !posts.data && <div className="loading-row"><span className="spinner spinner-dark" /></div>}
        {posts.data && posts.data.items.length === 0 && <div className="bl-notice">Nothing here yet.</div>}
        {posts.data && posts.data.items.length > 0 && (
          <div className="bl-table-wrap">
            {posts.data.items.map((p) => (
              <div key={p.id} className="so-post">
                {p.mediaType === 'Image' && p.mediaUrl
                  ? <img className="so-thumb" src={p.mediaUrl} alt="" />
                  : <div className="so-thumb" aria-hidden>{p.mediaType === 'Video' ? '🎬' : '📝'}</div>}
                <div style={{ minWidth: 0 }}>
                  <div className="bl-row" style={{ gap: 8 }}>
                    <SoBadge status={p.status} />
                    <span className="bl-small bl-muted">
                      {p.status === 'Scheduled' && p.scheduledAt ? `Goes out ${dateTime(p.scheduledAt)} (${relativeTime(p.scheduledAt)})` : `Updated ${relativeTime(p.updatedAt)}`}
                    </span>
                  </div>
                  <div className="so-caption" style={{ marginTop: 4 }}>{p.caption || <span className="bl-muted">(no caption)</span>}</div>
                  <div className="so-targets">
                    {p.targets.map((t) => (
                      <span key={t.id} className="so-target" title={t.error ?? undefined}>
                        <PlatformMark platform={t.platform as Platform} small />
                        {t.permalinkUrl ? <a href={t.permalinkUrl} target="_blank" rel="noreferrer">{t.accountName}</a> : t.accountName}
                        <SoBadge status={t.status} />
                      </span>
                    ))}
                  </div>
                  {p.targets.filter((t) => t.error && t.status !== 'Published').map((t) => (
                    <div key={t.id} className="bl-small" style={{ color: t.status === 'Failed' ? 'var(--color-critical)' : 'var(--color-text-secondary)', marginTop: 4 }}>
                      {t.accountName}: {t.error}{t.status === 'Pending' && t.nextAttemptAt ? ` — retrying ${relativeTime(t.nextAttemptAt)}` : ''}
                    </div>
                  ))}
                </div>
                <div className="bl-stack" style={{ gap: 6, alignItems: 'flex-end' }}>
                  {p.editable && <button className="btn btn-secondary btn-sm" onClick={() => edit(p)}>Edit</button>}
                  {(p.status === 'Failed' || p.status === 'PartiallyPublished') && (
                    <button className="btn btn-secondary btn-sm" onClick={() => act('retry', () => socialApi.retryPost(p.id))}>Retry failed</button>
                  )}
                  {(p.status === 'Scheduled' || p.status === 'Draft' || p.status === 'Publishing') && (
                    <button className="btn btn-ghost btn-sm" onClick={() => act('cancel', () => socialApi.cancelPost(p.id))}>Cancel</button>
                  )}
                  <button className="btn btn-ghost btn-sm" onClick={() => edit(p, true)}>Duplicate</button>
                  <button className="btn btn-ghost btn-sm" onClick={() => remove(p)}>Delete</button>
                </div>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
