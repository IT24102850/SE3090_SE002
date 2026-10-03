import { createContext, useCallback, useContext, useRef, useState, type ReactNode } from 'react';
import ConfirmDialog from './ConfirmDialog';

type ConfirmationOptions = {
  title: string;
  message: string;
  confirmLabel?: string;
  tone?: 'primary' | 'danger';
};

type ConfirmationRequest = ConfirmationOptions & { resolve: (confirmed: boolean) => void };
type ConfirmationContextValue = (options: ConfirmationOptions) => Promise<boolean>;

const ConfirmationContext = createContext<ConfirmationContextValue | null>(null);

export function ConfirmationProvider({ children }: { children: ReactNode }) {
  const [request, setRequest] = useState<ConfirmationRequest | null>(null);
  const resolver = useRef<((confirmed: boolean) => void) | null>(null);

  const confirm = useCallback((options: ConfirmationOptions) => new Promise<boolean>((resolve) => {
    resolver.current?.(false);
    resolver.current = resolve;
    setRequest({ ...options, resolve });
  }), []);

  const finish = useCallback((confirmed: boolean) => {
    resolver.current?.(confirmed);
    resolver.current = null;
    setRequest(null);
  }, []);

  return (
    <ConfirmationContext.Provider value={confirm}>
      {children}
      {request && (
        <ConfirmDialog
          title={request.title}
          message={request.message}
          confirmLabel={request.confirmLabel}
          tone={request.tone}
          onConfirm={() => finish(true)}
          onCancel={() => finish(false)}
        />
      )}
    </ConfirmationContext.Provider>
  );
}

export function useConfirmation() {
  const confirm = useContext(ConfirmationContext);
  if (!confirm) throw new Error('useConfirmation must be used within ConfirmationProvider');
  return confirm;
}
