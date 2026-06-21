import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

/** Short Czech relative phrase for an ISO timestamp (e.g. "před 3 h"). */
export function relativeCzech(iso: string, now: number = Date.now()): string {
  const then = Date.parse(iso);
  if (Number.isNaN(then)) return iso;
  const diffS = Math.max(0, Math.round((now - then) / 1000));
  if (diffS < 60) return 'právě teď';
  const diffMin = Math.round(diffS / 60);
  if (diffMin < 60) return `před ${diffMin} min`;
  const diffH = Math.round(diffMin / 60);
  if (diffH < 24) return `před ${diffH} h`;
  const diffD = Math.round(diffH / 24);
  return `před ${diffD} d`;
}
