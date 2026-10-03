import { useEffect, useRef, useState } from 'react';
import { useAskWorkspaceAssistantMutation } from '../../api/bookingApi';

type Message = { id: number; role: 'user' | 'assistant'; text: string };

const suggestions = [
  'Which items need reordering?',
  'How many open purchase orders do we have?',
  'What can you help me with?',
];

function relatedQuestions(message: string) {
  const normalized = message.toLowerCase();
  if (normalized.includes('inventory') || normalized.includes('reorder') || normalized.includes('stock')) {
    return ['Show me the low-stock page', 'How do I create a purchase order?', 'What is the branch stock value?'];
  }
  if (normalized.includes('purchase') || normalized.includes('po')) {
    return ['Which items need reordering?', 'How do I receive a purchase order?', 'Show me branch inventory'];
  }
  if (normalized.includes('booking') || normalized.includes('appointment') || normalized.includes('schedule')) {
    return ['How do I find available slots?', 'What can the AI Planner do?', 'Show me today’s bookings'];
  }
  if (normalized.includes('branch') || normalized.includes('location')) {
    return ['Which branches have low stock?', 'How many active branches are there?', 'Show me inventory by branch'];
  }
  return ['Which items need reordering?', 'How many open purchase orders do we have?', 'What can you help me with?'];
}

export default function WorkspaceAssistant() {
  const [open, setOpen] = useState(false);
  const [draft, setDraft] = useState('');
  const [messages, setMessages] = useState<Message[]>([]);
  const [related, setRelated] = useState<string[]>(suggestions);
  const [ask, { isLoading }] = useAskWorkspaceAssistantMutation();
  const nextId = useRef(1);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (open) inputRef.current?.focus();
  }, [open]);

  const send = async (value = draft) => {
    const text = value.trim();
    if (!text || isLoading) return;
    setDraft('');
    setMessages((current) => [...current, { id: nextId.current++, role: 'user', text }]);
    try {
      const response = await ask({ message: text }).unwrap();
      setMessages((current) => [...current, { id: nextId.current++, role: 'assistant', text: response.answer }]);
      setRelated(relatedQuestions(text));
    } catch {
      setMessages((current) => [...current, {
        id: nextId.current++,
        role: 'assistant',
        text: 'I could not reach the workspace assistant. Please try again in a moment.',
      }]);
    }
  };

  return (
    <>
      {open && (
        <section className="workspace-assistant" role="dialog" aria-label="Workspace AI assistant">
          <header className="workspace-assistant-header">
            <div>
              {messages.length > 0 && (
                <button
                  type="button"
                  className="workspace-assistant-back"
                  onClick={() => { setMessages([]); setRelated(suggestions); }}
                  aria-label="Back to assistant questions"
                >
                  ← Questions
                </button>
              )}
              <span className="workspace-assistant-kicker">UNIFY AI</span>
              <strong>Workspace assistant</strong>
              <small>Answers from your live workspace data</small>
            </div>
            <button type="button" className="workspace-assistant-close" onClick={() => setOpen(false)} aria-label="Close assistant">×</button>
          </header>
          <div className="workspace-assistant-messages" aria-live="polite">
            {messages.length === 0 && (
              <div className="workspace-assistant-welcome">
                <div className="workspace-assistant-orb">✦</div>
                <strong>How can I help?</strong>
                <p>Ask about inventory, purchase orders, branches, bookings, schedules, or AI workflows.</p>
                <div className="workspace-assistant-suggestions">
                  {suggestions.map((suggestion) => (
                    <button key={suggestion} type="button" onClick={() => void send(suggestion)}>{suggestion}</button>
                  ))}
                </div>
              </div>
            )}
            {messages.map((message) => (
              <div key={message.id} className={`workspace-assistant-message ${message.role}`}>
                {message.text}
              </div>
            ))}
            {isLoading && <div className="workspace-assistant-message assistant is-thinking">Checking your workspace<span>•••</span></div>}
            {!isLoading && messages.length > 0 && (
              <div className="workspace-assistant-related">
                <span>Related questions</span>
                {related.map((question) => (
                  <button key={question} type="button" onClick={() => void send(question)}>{question}</button>
                ))}
              </div>
            )}
          </div>
          <form className="workspace-assistant-input" onSubmit={(event) => { event.preventDefault(); void send(); }}>
            <input ref={inputRef} value={draft} onChange={(event) => setDraft(event.target.value)} placeholder="Ask about your workspace…" aria-label="Ask the workspace assistant" />
            <button type="submit" disabled={isLoading || !draft.trim()} aria-label="Send message">↑</button>
          </form>
        </section>
      )}
      <button type="button" className={`workspace-assistant-launcher${open ? ' is-open' : ''}`} onClick={() => setOpen((value) => !value)} aria-label={open ? 'Close workspace assistant' : 'Open workspace assistant'}>
        <span aria-hidden="true">{open ? '×' : '✦'}</span>
        {!open && <small>Ask AI</small>}
      </button>
    </>
  );
}
