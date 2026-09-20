export const STATUS = {
  bezi:        { label: "běží",        color: "var(--status-running)",   hex: "#0284c7" },
  ceka:        { label: "čeká",        color: "var(--status-idle)",      hex: "#64748b" },
  proslo:      { label: "prošlo",      color: "var(--status-pass)",      hex: "#059669" },
  selhalo:     { label: "selhalo",     color: "var(--status-fail)",      hex: "#dc2626" },
  zablokovano: { label: "zablokováno", color: "var(--status-blocked)",   hex: "#d97706" },
  eskalace:    { label: "eskalace",    color: "var(--status-escalate)",  hex: "#ea580c" },
  pozor:       { label: "pozor",       color: "var(--status-warn)",      hex: "#ca8a04" },
  necinne:     { label: "nečinné",     color: "var(--status-idle-proj)", hex: "#475569" },
} as const;
export type StatusKey = keyof typeof STATUS;
