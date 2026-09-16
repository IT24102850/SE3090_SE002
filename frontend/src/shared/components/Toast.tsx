import { createContext, useCallback, useContext, useRef, useState, type ReactNode } from 'react';

type ToastKind = 'success' | 'error' | 'warning' | 'info';
interface ToastItem { id: number; kind: ToastKind; message: string }

const ToastContext = createContext<{ show: (message: string, kind?: ToastKind) => void } | null>(null);

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<ToastItem[]>([]);
  const idRef = useRef(0);

  const show = useCallback((message: string, kind: ToastKind = 'info') => {
    const id = ++idRef.current;
    setToasts((prev) => [...prev, { id, kind, message }]);
    setTimeout(() => {
      setToasts((prev) => prev.filter((t) => t.id !== id));
    }, kind === 'error' || kind === 'warning' ? 6000 : 4500);
  }, []);

  const dismiss = useCallback((id: number) => {
    setToasts((prev) => prev.filter((toast) => toast.id !== id));
  }, []);

  return (
    <ToastContext.Provider value={{ show }}>
      {children}
      <div className="toast-stack">
        {toasts.map((t) => (
          <div key={t.id} className={`toast toast-${t.kind}`} role={t.kind === 'error' ? 'alert' : 'status'}>
            <span className="toast-icon" aria-hidden="true">{t.kind === 'success' ? '✓' : t.kind === 'error' ? '×' : t.kind === 'warning' ? '!' : 'i'}</span>
            <span className="toast-content">
              <strong>{t.kind === 'success' ? 'Success' : t.kind === 'error' ? 'Failed' : t.kind === 'warning' ? 'Warning' : 'Information'}</strong>
              <span>{t.message}</span>
            </span>
            <button className="toast-dismiss" type="button" aria-label="Dismiss message" onClick={() => dismiss(t.id)}>×</button>
            <span className="toast-progress" aria-hidden="true" />
          </div>
        ))}
      </div>
    </ToastContext.Provider>
  );
}

export function useToast() {
  const ctx = useContext(ToastContext);
  if (!ctx) throw new Error('useToast must be used within a ToastProvider');
  return ctx;
}

export function apiErrorMessage(err: unknown, fallback = 'Something went wrong.'): string {
  const e = err as { data?: { message?: string }; error?: string } | undefined;
  return e?.data?.message ?? e?.error ?? fallback;
}
