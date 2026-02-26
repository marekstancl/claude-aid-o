import React, { createContext, useCallback, useContext, useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, CheckCircle, Info, AlertCircle, AlertTriangle } from 'lucide-react';
import { cn } from '../lib/utils';

type ToastType = 'success' | 'error' | 'info' | 'warning';

interface Toast {
  id: string;
  type: ToastType;
  message: string;
  duration?: number;
}

interface ToastContextValue {
  toast: (type: ToastType, message: string, duration?: number) => void;
  dismiss: (id: string) => void;
}

const ToastContext = createContext<ToastContextValue | null>(null);

let toastCounter = 0;

const TOAST_ICONS: Record<ToastType, React.FC<{ className?: string }>> = {
  success: CheckCircle,
  error: AlertCircle,
  info: Info,
  warning: AlertTriangle,
};

const TOAST_STYLES: Record<ToastType, { icon: string; border: string }> = {
  success: {
    icon: 'text-emerald-400',
    border: 'border-emerald-500/20',
  },
  error: {
    icon: 'text-red-400',
    border: 'border-red-500/20',
  },
  info: {
    icon: 'text-blue-400',
    border: 'border-blue-500/20',
  },
  warning: {
    icon: 'text-amber-400',
    border: 'border-amber-500/20',
  },
};

export function ToastProvider({ children }: { children: React.ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([]);

  const dismiss = useCallback((id: string) => {
    setToasts((prev) => prev.filter((t) => t.id !== id));
  }, []);

  const toast = useCallback(
    (type: ToastType, message: string, duration: number = 5000) => {
      const id = `toast-${++toastCounter}`;
      const newToast: Toast = { id, type, message, duration };

      setToasts((prev) => [...prev, newToast]);

      if (duration > 0) {
        setTimeout(() => {
          dismiss(id);
        }, duration);
      }
    },
    [dismiss]
  );

  return (
    <ToastContext.Provider value={{ toast, dismiss }}>
      {children}
      <div className="fixed bottom-4 right-4 z-[100] flex flex-col gap-2 pointer-events-none">
        <AnimatePresence mode="popLayout">
          {toasts.map((t) => {
            const Icon = TOAST_ICONS[t.type];
            const styles = TOAST_STYLES[t.type];

            return (
              <motion.div
                key={t.id}
                layout
                initial={{ opacity: 0, y: 20, scale: 0.95 }}
                animate={{ opacity: 1, y: 0, scale: 1 }}
                exit={{ opacity: 0, x: 80, scale: 0.95 }}
                transition={{ duration: 0.2, ease: 'easeOut' }}
                className={cn(
                  'pointer-events-auto flex items-start gap-3 px-4 py-3 rounded-xl',
                  'bg-surface-2 backdrop-blur-xl border',
                  'shadow-lg shadow-black/20 max-w-sm w-80',
                  styles.border
                )}
              >
                <Icon className={cn('w-5 h-5 mt-0.5 shrink-0', styles.icon)} />
                <p className="flex-1 text-sm text-white/80 leading-snug">{t.message}</p>
                <button
                  onClick={() => dismiss(t.id)}
                  className="shrink-0 p-0.5 rounded-lg hover:bg-white/5 text-white/40 hover:text-white/70 transition-colors"
                  aria-label="Dismiss notification"
                >
                  <X className="w-4 h-4" />
                </button>
              </motion.div>
            );
          })}
        </AnimatePresence>
      </div>
    </ToastContext.Provider>
  );
}

export function useToast(): ToastContextValue {
  const ctx = useContext(ToastContext);
  if (!ctx) {
    throw new Error('useToast must be used within a <ToastProvider>');
  }
  return ctx;
}
