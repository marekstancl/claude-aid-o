import { STATUS } from '@aid/contract';

/**
 * Shared recharts theme (§6.2 status palette, light surface, tabular figures).
 *
 * One source of truth for axis/grid/tooltip styling so every chart in the
 * cockpit reads the same. Spread these onto the matching recharts primitives:
 *
 *   <XAxis dataKey="label" {...chartTheme.axis} />
 *   <Tooltip {...chartTheme.tooltip} />
 */
export const chartTheme = {
  /** §6.2 colours reused as chart series colours. */
  colors: {
    pass: STATUS.proslo.hex,
    fail: STATUS.selhalo.hex,
    warn: STATUS.pozor.hex,
    running: STATUS.bezi.hex,
    idle: STATUS.ceka.hex,
    grid: '#e2e8f0', // slate-200
    axis: '#94a3b8', // slate-400
    text: '#475569', // slate-600
  },

  /** Spread onto <XAxis>/<YAxis>: thin slate ticks, tabular figures. */
  axis: {
    stroke: '#94a3b8',
    tick: { fill: '#64748b', fontSize: 11, fontVariantNumeric: 'tabular-nums' as const },
    tickLine: false,
    axisLine: { stroke: '#e2e8f0' },
  },

  /** Spread onto <CartesianGrid>. */
  grid: {
    stroke: '#e2e8f0',
    strokeDasharray: '3 3',
    vertical: false,
  },

  /** Spread onto <Tooltip>: light card, slate border, tabular figures. */
  tooltip: {
    cursor: { stroke: '#cbd5e1', strokeWidth: 1 },
    contentStyle: {
      background: '#ffffff',
      border: '1px solid #e2e8f0',
      borderRadius: 8,
      fontSize: 12,
      color: '#475569',
      fontVariantNumeric: 'tabular-nums' as const,
    },
    labelStyle: { color: '#94a3b8', fontSize: 11 },
  },
} as const;
