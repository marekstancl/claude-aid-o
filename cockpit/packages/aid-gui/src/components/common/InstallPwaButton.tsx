import { useEffect, useRef, useState } from 'react';
import { Download } from 'lucide-react';
import { cn } from '../../lib/utils';

/**
 * The non-standard `beforeinstallprompt` event (Chromium PWA install flow).
 * Not in lib.dom, so it is typed locally.
 */
export interface BeforeInstallPromptEvent extends Event {
  readonly platforms: string[];
  readonly userChoice: Promise<{ outcome: 'accepted' | 'dismissed'; platform: string }>;
  prompt(): Promise<void>;
}

interface InstallPwaButtonProps {
  /** Button label (Czech). */
  label?: string;
  className?: string;
}

/**
 * §8 PWA install affordance. Captures the `beforeinstallprompt` event
 * (preventDefault + store in a ref), and renders a button ONLY while a prompt
 * is available; clicking fires the native install prompt. Returns `null` when
 * the browser has not offered an install (already installed, unsupported, or
 * not yet eligible).
 */
export function InstallPwaButton({ label = 'Instalovat aplikaci', className }: InstallPwaButtonProps) {
  const promptRef = useRef<BeforeInstallPromptEvent | null>(null);
  const [available, setAvailable] = useState(false);

  useEffect(() => {
    const onBeforeInstallPrompt = (event: Event) => {
      event.preventDefault();
      promptRef.current = event as BeforeInstallPromptEvent;
      setAvailable(true);
    };
    const onInstalled = () => {
      promptRef.current = null;
      setAvailable(false);
    };
    window.addEventListener('beforeinstallprompt', onBeforeInstallPrompt);
    window.addEventListener('appinstalled', onInstalled);
    return () => {
      window.removeEventListener('beforeinstallprompt', onBeforeInstallPrompt);
      window.removeEventListener('appinstalled', onInstalled);
    };
  }, []);

  if (!available) return null;

  const handleClick = async () => {
    const evt = promptRef.current;
    if (!evt) return;
    await evt.prompt();
    // The prompt can only be used once; consume it regardless of outcome.
    promptRef.current = null;
    setAvailable(false);
  };

  return (
    <button
      type="button"
      onClick={handleClick}
      className={cn(
        'inline-flex min-h-[44px] items-center gap-3 rounded-lg px-3 text-sm text-slate-700 hover:bg-slate-100',
        className,
      )}
    >
      <Download className="h-5 w-5 text-slate-400" />
      {label}
    </button>
  );
}
