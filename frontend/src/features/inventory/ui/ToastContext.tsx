import { createContext, useContext, type ReactNode } from 'react';
import { useToast as useSharedToast } from '../../../shared/components/Toast';

export type ToastTone = 'success' | 'error' | 'warning' | 'info';
type ToastContextValue = { notify: (message: string, tone?: ToastTone) => void };

const ToastContext = createContext<ToastContextValue | undefined>(undefined);

export function ToastProvider({ children }: { children: ReactNode }) {
  const { show } = useSharedToast();
  const value = { notify: show };

  return (
    <ToastContext.Provider value={value}>
      {children}
    </ToastContext.Provider>
  );
}

export function useToast() {
  const context = useContext(ToastContext);
  if (!context) throw new Error('useToast must be used within ToastProvider');
  return context;
}
