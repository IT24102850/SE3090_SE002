import { useEffect, useRef, useState } from 'react';
import { useSelector } from 'react-redux';
import { Link } from 'react-router-dom';
import type { RootState } from '../../store/store';
import { useToast } from '../../shared/components/Toast';
import { errorMessage } from '../billing/billingApi';
import { useAsync } from '../billing/useAsync';
import { buildBookingLink } from '../embed/attribution';
import { socialApi, type Conversation, type InboxMessage } from './socialApi';
import { PlatformMark, relativeTime } from './components';
import '../billing/billing.css';
import './social.css';

const QUICK_REPLIES = [
  'Thanks for your message! Yes, we have availability — you can pick a time and book here:',
  'Our opening hours are listed on our page. Would you like me to send you the booking link?',
  'Thank you! Your booking is received and we will confirm it shortly.',
];

/* Messenger + Instagram DMs from every connected account in one place,
 * with a one-click tracked booking link so a chat becomes a booking. */
export default function SocialInboxPage() {
  const toast = useToast();
  const user = useSelector((s: RootState) => s.auth.user);
  const canManage = user?.role === 'Admin' || user?.role === 'Manager';
  const [archived, setArchived] = useState(false);
  const [search, setSearch] = useState('');
  const [query, setQuery] = useState('');
  const threads = useAsync(() => socialApi.conversations({ archived, search: query || undefined }), [archived, query]);
  const accounts = useAsync(() => socialApi.accounts(), []);
  const [selected, setSelected] = useState<string | null>(null);
  const [thread, setThread] = useState<{ conversation: Conversation; messages: InboxMessage[] } | null>(null);
  const [text, setText] = useState('');
  const [sending, setSending] = useState(false);
  const bottomRef = useRef<HTMLDivElement>(null);

  /* Debounced search. */
  useEffect(() => {
    const t = window.setTimeout(() => setQuery(search.trim()), 300);
    return () => window.clearTimeout(t);
  }, [search]);

  /* New messages arrive by webhook; poll the list and the open thread. */
  useEffect(() => {
    const t = window.setInterval(() => { void threads.reload(); }, 15_000);
    return () => window.clearInterval(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [archived, query]);

  const loadThread = async (id: string, quiet = false) => {
    try {
      const data = await socialApi.messages(id);
      setThread((prev) => {
        if (quiet && prev && prev.conversation.id === id && prev.messages.length === data.messages.length) return prev;
        return data;
      });
    } catch (err) {
      if (!quiet) toast.show(errorMessage(err, 'Could not open the conversation.'), 'error');
    }
  };

  useEffect(() => {
    if (!selected) return;
    void loadThread(selected).then(() => threads.reload());
    const t = window.setInterval(() => { void loadThread(selected, true); }, 10_000);
    return () => window.clearInterval(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selected]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView?.({ block: 'end' });
  }, [thread?.messages.length]);

  const send = async (body = text) => {
    if (!selected || !body.trim()) return;
    setSending(true);
    try {
      const msg = await socialApi.reply(selected, body.trim());
      setThread((t) => (t ? { ...t, messages: [...t.messages, msg] } : t));
      setText('');
      void threads.reload();
    } catch (err) {
      toast.show(errorMessage(err, 'The message was not sent.'), 'error');
    } finally {
      setSending(false);
    }
  };

  const bookingLink = (c: Conversation) => user?.tenantId
    ? buildBookingLink({ origin: window.location.origin, tenantId: user.tenantId, source: c.platform.toLowerCase(), medium: 'dm', campaign: 'inbox', conversationId: c.id })
    : '';

  const insertBookingLink = () => {
    if (!thread) return;
    const link = bookingLink(thread.conversation);
    setText((t) => (t.trim() ? `${t.trimEnd()}\n${link}` : `${QUICK_REPLIES[0]}\n${link}`));
  };

  const archive = async (c: Conversation) => {
    try {
      await socialApi.archive(c.id, !c.isArchived);
      setSelected(null);
      setThread(null);
      void threads.reload();
    } catch (err) {
      toast.show(errorMessage(err, 'Could not update the conversation.'), 'error');
    }
  };

  const messageable = (accounts.data ?? []).filter((a) => a.canMessage && a.status !== 'Disconnected');
  const sandboxes = messageable.filter((a) => a.isSandbox);
  const c = thread?.conversation;

  return (
    <div className="bl-page">
      <div className="page-header">
        <div>
          <h1 className="page-title">Inbox</h1>
          <p className="page-subtitle">Facebook Messenger and Instagram DMs from every connected account. Send a booking link and the booking that follows is tied back to the chat.</p>
        </div>
      </div>

      {accounts.data && messageable.length === 0 && (
        <div className="bl-notice">
          No Facebook Page or Instagram account is connected. <Link to="/social">Connect one</Link> to receive messages here. (TikTok does not offer a messaging API for businesses.)
        </div>
      )}

      {canManage && sandboxes.length > 0 && <SandboxMessage accounts={sandboxes} onSent={(id) => { void threads.reload(); setSelected(id); }} />}

      <div className="so-inbox">
        <div className="so-threads">
          <div style={{ padding: 10, borderBottom: '1px solid var(--color-border)' }} className="bl-stack">
            <input className="input" placeholder="Search name or message" value={search} onChange={(e) => setSearch(e.target.value)} aria-label="Search conversations" />
            <div className="bl-row">
              <button className={`btn btn-sm ${!archived ? 'btn-primary' : 'btn-ghost'}`} onClick={() => setArchived(false)}>Open</button>
              <button className={`btn btn-sm ${archived ? 'btn-primary' : 'btn-ghost'}`} onClick={() => setArchived(true)}>Archived</button>
            </div>
          </div>
          {threads.error && <div className="bl-notice bl-notice-critical" style={{ margin: 10 }}>{threads.error}</div>}
          {threads.data && threads.data.length === 0 && <div className="bl-small bl-muted" style={{ padding: 16 }}>No conversations{archived ? ' in the archive' : ' yet'}.</div>}
          {threads.data?.map((t) => (
            <button key={t.id} className={`so-thread${t.unreadCount > 0 ? ' so-thread-unread' : ''}`} aria-current={selected === t.id} onClick={() => setSelected(t.id)}>
              <PlatformMark platform={t.platform} small />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div className="bl-spread" style={{ gap: 6, flexWrap: 'nowrap' }}>
                  <span className="so-thread-name" style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{t.participantName ?? 'Customer'}</span>
                  <span className="bl-small bl-muted" style={{ flex: 'none' }}>{relativeTime(t.lastMessageAt)}</span>
                </div>
                <div className="bl-small bl-muted" style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{t.lastMessagePreview}</div>
                <div className="bl-row" style={{ gap: 6, marginTop: 2 }}>
                  <span className="bl-small bl-muted">{t.accountName}</span>
                  {t.linkedBookingId && <span className="bl-badge bl-badge-good">Booked</span>}
                </div>
              </div>
              {t.unreadCount > 0 && <span className="so-unread">{t.unreadCount}</span>}
            </button>
          ))}
        </div>

        <div className="so-chat">
          {!c && <div className="bl-muted" style={{ margin: 'auto', padding: 24 }}>Choose a conversation.</div>}
          {c && thread && (
            <>
              <div className="so-chat-head">
                <PlatformMark platform={c.platform} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontWeight: 700 }}>{c.participantName ?? 'Customer'}</div>
                  <div className="bl-small bl-muted">
                    via {c.accountName}{c.isSandbox ? ' (sandbox)' : ''}
                    {!c.isSandbox && c.replyWindowEndsAt && (c.canReply ? ` · reply window closes ${relativeTime(c.replyWindowEndsAt)}` : ' · reply window closed')}
                  </div>
                </div>
                {c.linkedBookingId && <Link className="btn btn-secondary btn-sm" to="/bookings">View booking</Link>}
                <button className="btn btn-ghost btn-sm" onClick={() => archive(c)}>{c.isArchived ? 'Unarchive' : 'Archive'}</button>
              </div>
              <div className="so-messages">
                {thread.messages.map((m) => (
                  <div key={m.id} className={`so-bubble ${m.direction === 'Inbound' ? 'so-bubble-in' : 'so-bubble-out'}`}>
                    {m.text}
                    {m.attachmentUrl && <div><a href={m.attachmentUrl} target="_blank" rel="noreferrer" style={{ color: 'inherit' }}>Attachment</a></div>}
                    <div className="so-bubble-time">{new Date(m.sentAt).toLocaleString(undefined, { hour: '2-digit', minute: '2-digit', day: 'numeric', month: 'short' })}</div>
                  </div>
                ))}
                <div ref={bottomRef} />
              </div>
              <div className="so-reply">
                {!c.canReply && (
                  <div className="bl-notice">
                    {c.platform} only lets businesses reply within 24 hours of the customer’s last message. Reply from the {c.platform} app, or wait for them to write again.
                  </div>
                )}
                <div className="bl-row">
                  {QUICK_REPLIES.slice(1).map((q) => (
                    <button key={q} className="btn btn-ghost btn-sm" disabled={!c.canReply} onClick={() => setText(q)}>{q.slice(0, 28)}…</button>
                  ))}
                </div>
                <textarea className="input" value={text} disabled={!c.canReply || sending} placeholder="Write a reply…"
                  onChange={(e) => setText(e.target.value)}
                  onKeyDown={(e) => { if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) { e.preventDefault(); void send(); } }} />
                <div className="bl-spread">
                  <button className="btn btn-secondary btn-sm" disabled={!c.canReply} onClick={insertBookingLink}>Send booking link</button>
                  <div className="bl-row">
                    <span className="bl-small bl-muted">Ctrl+Enter to send</span>
                    <button className="btn btn-primary btn-sm" disabled={!c.canReply || sending || !text.trim()} onClick={() => send()}>{sending ? 'Sending…' : 'Send'}</button>
                  </div>
                </div>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

function SandboxMessage({ accounts, onSent }: { accounts: { id: string; displayName: string; platform: string }[]; onSent: (conversationId: string) => void }) {
  const toast = useToast();
  const [accountId, setAccountId] = useState(accounts[0].id);
  const [name, setName] = useState('Amaya Perera');
  const [body, setBody] = useState('Hi! Do you have space for 2 adults on Saturday morning?');
  const [busy, setBusy] = useState(false);

  const send = async () => {
    setBusy(true);
    try {
      const { conversationId } = await socialApi.simulateIncoming(accountId, name, body);
      onSent(conversationId);
    } catch (err) {
      toast.show(errorMessage(err, 'Could not simulate the message.'), 'error');
    } finally {
      setBusy(false);
    }
  };

  return (
    <details className="card" style={{ padding: 14 }}>
      <summary style={{ cursor: 'pointer', fontWeight: 600 }}>Sandbox: simulate an incoming message</summary>
      <div className="bl-row" style={{ marginTop: 10, alignItems: 'flex-end' }}>
        <select className="input" style={{ width: 'auto' }} value={accountId} onChange={(e) => setAccountId(e.target.value)} aria-label="Sandbox account">
          {accounts.map((a) => <option key={a.id} value={a.id}>{a.platform} · {a.displayName}</option>)}
        </select>
        <input className="input" style={{ width: 180 }} value={name} onChange={(e) => setName(e.target.value)} aria-label="Customer name" />
        <input className="input" style={{ flex: 1, minWidth: 220 }} value={body} onChange={(e) => setBody(e.target.value)} aria-label="Message" />
        <button className="btn btn-secondary btn-sm" disabled={busy || !body.trim()} onClick={send}>Deliver</button>
      </div>
    </details>
  );
}
