/**
 * Notification hook for the AID Dashboard.
 *
 * Provides audio notifications (Web Audio API) and browser notifications
 * (Notification API) for alerting users to new pending decisions.
 *
 * Audio notifications use a short 440Hz sine wave tone (150ms) with a
 * quick gain fade-out. They are debounced to fire at most once every
 * 3 seconds.
 *
 * Browser notifications are only shown when the tab is in the background
 * (document.hidden === true). Clicking the notification focuses the window
 * and navigates to the Decision Hub.
 *
 * @example
 * ```tsx
 * function DecisionHub() {
 *   const { playNotificationSound, showBrowserNotification } = useNotifications();
 *
 *   useEffect(() => {
 *     if (newDecisionArrived) {
 *       playNotificationSound();
 *       showBrowserNotification('Plan Review required for E-042');
 *     }
 *   }, [newDecisionArrived]);
 * }
 * ```
 */

import { useRef, useCallback, useState } from 'react';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/** Minimum interval between notification sounds in milliseconds. */
const SOUND_DEBOUNCE_MS = 3_000;

/** Frequency of the notification tone in Hz. */
const TONE_FREQUENCY = 440;

/** Duration of the notification tone in seconds. */
const TONE_DURATION = 0.15;

/** Duration of the gain fade-out at the end of the tone in seconds. */
const FADE_OUT_DURATION = 0.05;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface UseNotificationsReturn {
  /** Play a short audio notification tone. Debounced to max once per 3s. */
  playNotificationSound: () => void;

  /**
   * Show a browser notification if the tab is in the background.
   * @param body - Notification body text (e.g., decision title or description).
   */
  showBrowserNotification: (body: string) => void;

  /**
   * Request browser notification permission explicitly.
   * Called automatically on first showBrowserNotification trigger,
   * but can be called proactively (e.g., from a settings toggle).
   */
  requestPermission: () => Promise<NotificationPermission>;

  /** Current Notification API permission state. */
  permissionState: NotificationPermission | 'unsupported';
}

// ---------------------------------------------------------------------------
// Hook
// ---------------------------------------------------------------------------

export function useNotifications(): UseNotificationsReturn {
  // AudioContext is created lazily on first sound play (browser requires user gesture)
  const audioCtxRef = useRef<AudioContext | null>(null);
  const lastPlayedAtRef = useRef<number>(0);

  // Track notification permission state
  const [permissionState, setPermissionState] = useState<
    NotificationPermission | 'unsupported'
  >(() => {
    if (typeof window === 'undefined' || !('Notification' in window)) {
      return 'unsupported';
    }
    return Notification.permission;
  });

  /**
   * Get or create the AudioContext lazily.
   * Must be called from a user gesture context on first invocation.
   */
  const getAudioContext = useCallback((): AudioContext | null => {
    if (audioCtxRef.current) {
      // Resume if suspended (happens after browser auto-suspends)
      if (audioCtxRef.current.state === 'suspended') {
        audioCtxRef.current.resume().catch(() => {
          // Non-fatal: audio just won't play
        });
      }
      return audioCtxRef.current;
    }

    try {
      const ctx = new AudioContext();
      audioCtxRef.current = ctx;
      return ctx;
    } catch {
      // AudioContext not available (e.g., very old browser)
      return null;
    }
  }, []);

  /**
   * Play a short notification tone via Web Audio API.
   *
   * Uses a 440Hz sine wave oscillator connected through a GainNode for
   * a smooth fade-out. Debounced to prevent rapid-fire sounds.
   */
  const playNotificationSound = useCallback((): void => {
    const now = Date.now();
    if (now - lastPlayedAtRef.current < SOUND_DEBOUNCE_MS) {
      return; // Still within debounce window
    }
    lastPlayedAtRef.current = now;

    const ctx = getAudioContext();
    if (!ctx) return;

    const currentTime = ctx.currentTime;

    // Create oscillator: 440Hz sine wave
    const oscillator = ctx.createOscillator();
    oscillator.type = 'sine';
    oscillator.frequency.setValueAtTime(TONE_FREQUENCY, currentTime);

    // Create gain node for fade-out
    const gainNode = ctx.createGain();
    gainNode.gain.setValueAtTime(0.3, currentTime);
    // Fade out over the last 50ms of the tone
    gainNode.gain.linearRampToValueAtTime(
      0,
      currentTime + TONE_DURATION + FADE_OUT_DURATION,
    );

    // Connect: oscillator -> gain -> speakers
    oscillator.connect(gainNode);
    gainNode.connect(ctx.destination);

    // Play and auto-stop
    oscillator.start(currentTime);
    oscillator.stop(currentTime + TONE_DURATION + FADE_OUT_DURATION);
  }, [getAudioContext]);

  /**
   * Request browser notification permission.
   * Returns the resulting permission state. Handles denial gracefully
   * (no error thrown, just returns 'denied').
   */
  const requestPermission =
    useCallback(async (): Promise<NotificationPermission> => {
      if (typeof window === 'undefined' || !('Notification' in window)) {
        return 'denied';
      }

      if (Notification.permission === 'granted') {
        setPermissionState('granted');
        return 'granted';
      }

      if (Notification.permission === 'denied') {
        setPermissionState('denied');
        return 'denied';
      }

      try {
        const result = await Notification.requestPermission();
        setPermissionState(result);
        return result;
      } catch {
        // Some browsers throw on requestPermission failure
        setPermissionState('denied');
        return 'denied';
      }
    }, []);

  /**
   * Show a browser notification when the tab is in the background.
   *
   * If notification permission has not been requested yet, it will be
   * requested on first call. Denial is handled gracefully (notification
   * is simply skipped).
   */
  const showBrowserNotification = useCallback(
    (body: string): void => {
      // Only show when tab is in background
      if (!document.hidden) return;

      // Check if Notification API is available
      if (typeof window === 'undefined' || !('Notification' in window)) return;

      const show = () => {
        if (Notification.permission !== 'granted') return;

        const notification = new Notification('AID \u2014 New Decision Required', {
          body,
          icon: '/favicon.ico',
          tag: 'aid-decision', // Prevents duplicate notifications
        });

        notification.onclick = () => {
          window.focus();
          // Navigate to Decision Hub using location.href for reliable
          // cross-router compatibility (pushState + PopStateEvent is unreliable
          // with BrowserRouter in React Router v6+)
          if (window.location.pathname !== '/decisions') {
            window.location.href = '/decisions';
          }
          notification.close();
        };
      };

      if (Notification.permission === 'granted') {
        show();
      } else if (Notification.permission !== 'denied') {
        // Request permission on first trigger
        requestPermission().then(() => {
          show();
        });
      }
      // If denied, silently skip — no error
    },
    [requestPermission],
  );

  return {
    playNotificationSound,
    showBrowserNotification,
    requestPermission,
    permissionState,
  };
}
