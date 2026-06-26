import { useMemo } from 'react';
import {
  ResponsiveContainer,
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
} from 'recharts';
import type { AuditTrend, AuditTrendPoint } from '@aid/contract';
import { cn } from '../../lib/utils';
import { chartTheme } from './chartTheme';

interface AuditTrendChartProps {
  trend: AuditTrend;
  /**
   * Compact sparkline variant for mobile / dense tiles: no axes/grid/tooltip,
   * shorter height. Desktop default renders the full chart.
   */
  compact?: boolean;
  /** Click handler for a data point's dot → navigate to that run's audit. */
  onPointClick?: (point: AuditTrendPoint) => void;
  className?: string;
}

/** One row fed to recharts — `score` stays `null` for gaps (NEVER 0/NaN). */
interface ChartRow {
  runId: string;
  epicId: string;
  /** X-axis label: EPIC id is the most useful human anchor per point. */
  label: string;
  /** Real score or `null`. recharts breaks the line at null when connectNulls={false}. */
  score: number | null;
  point: AuditTrendPoint;
}

/**
 * Map `AuditTrend.points` (already chronological by startedAt) to chart rows.
 * Score-less runs are kept as `score:null` — a real gap — and are NEVER coerced
 * to 0 or NaN (recharts throws on NaN/undefined, and 0 would be a lie).
 */
function toRows(points: AuditTrendPoint[]): ChartRow[] {
  return points.map((p) => ({
    runId: p.runId,
    epicId: p.epicId,
    label: p.epicId || p.runId,
    score: p.score == null ? null : p.score,
    point: p,
  }));
}

/**
 * §13.5 audit-score trend as a recharts `LineChart`.
 *
 * Honesty contract:
 *  - `connectNulls={false}` is MANDATORY — a `score:null` point produces a
 *    visible line BREAK (two segments), never an interpolated straight line.
 *  - a trend with zero scored points renders an honest "žádné audity" empty
 *    state, NOT a flat zero line.
 *  - a missing score is `null` (a gap), NEVER 0 or NaN.
 *
 * Dots are tappable: clicking one calls `onPointClick(point)` so the caller can
 * deep-link to that run's audit.
 */
export function AuditTrendChart({ trend, compact = false, onPointClick, className }: AuditTrendChartProps) {
  const points = trend.points;
  const data = useMemo(() => toRows(points), [points]);

  // Empty state: no point carries a real number → don't draw a fake zero line.
  if (trend.scoredPointCount === 0) {
    return (
      <div
        data-audit-trend
        data-empty
        className={cn(
          'flex items-center justify-center rounded-lg border border-dashed border-slate-200 text-sm text-slate-400',
          compact ? 'h-16' : 'h-[180px]',
          className,
        )}
      >
        žádné audity
      </div>
    );
  }

  // recharts passes the dot's own props (which carry `payload`) as the first arg.
  const handleDotClick = (dotProps: unknown) => {
    const row = (dotProps as { payload?: ChartRow } | undefined)?.payload;
    if (row && onPointClick) onPointClick(row.point);
  };

  if (compact) {
    // Mobile sparkline: just the broken line, no chrome.
    return (
      <div data-audit-trend data-compact className={cn(className)} aria-label="Vývoj skóre auditu">
        <ResponsiveContainer width="100%" height={64}>
          <LineChart data={data} margin={{ top: 4, right: 4, bottom: 4, left: 4 }}>
            <YAxis domain={[0, 100]} hide />
            <Line
              type="monotone"
              dataKey="score"
              connectNulls={false}
              stroke={chartTheme.colors.running}
              strokeWidth={2}
              dot={{ r: 2 }}
              activeDot={{ r: 4, onClick: handleDotClick }}
              isAnimationActive={false}
            />
          </LineChart>
        </ResponsiveContainer>
      </div>
    );
  }

  return (
    <div data-audit-trend className={cn(className)} aria-label="Vývoj skóre auditu">
      <ResponsiveContainer width="100%" height={180}>
        <LineChart data={data} margin={{ top: 8, right: 12, bottom: 4, left: 0 }}>
          <CartesianGrid {...chartTheme.grid} />
          <XAxis dataKey="label" {...chartTheme.axis} />
          <YAxis domain={[0, 100]} {...chartTheme.axis} />
          <Tooltip {...chartTheme.tooltip} />
          <Line
            type="monotone"
            dataKey="score"
            connectNulls={false}
            stroke={chartTheme.colors.running}
            strokeWidth={2}
            dot={{ r: 3 }}
            activeDot={{ r: 5, onClick: handleDotClick }}
            isAnimationActive={false}
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
