/** Server configuration from environment variables. */

export interface ServerConfig {
  port: number;
  host: string;
  /** Root directory of the project (where .aid-o/ lives). */
  projectRoot: string;
  /**
   * Allowed CORS origins.
   * - `'*'` (string) enables wildcard CORS (any origin).
   * - `string[]` enables a whitelist of specific origins.
   */
  corsOrigins: string | string[];
  /** WebSocket heartbeat interval in ms. */
  wsHeartbeatInterval: number;
  /** WebSocket idle timeout in ms. */
  wsIdleTimeout: number;
}

/** Parse the AID_CORS_ORIGINS env var into a wildcard string or origin array. */
function parseCorsOrigins(raw: string | undefined): string | string[] {
  const DEFAULT_ORIGINS = 'http://localhost:5173,http://localhost:3000,http://localhost:3910';
  const value = (raw ?? DEFAULT_ORIGINS).trim();

  // Wildcard: return the string '*' so the cors package enables any-origin.
  if (value === '*') {
    return '*';
  }

  // Comma-separated whitelist: split, trim, and filter empty entries.
  return value.split(',').map((o) => o.trim()).filter(Boolean);
}

export function loadConfig(): ServerConfig {
  return {
    port: parseInt(process.env.AID_PORT ?? '3910', 10),
    host: process.env.AID_HOST ?? '127.0.0.1',
    projectRoot: process.env.AID_PROJECT_ROOT ?? process.cwd(),
    corsOrigins: parseCorsOrigins(process.env.AID_CORS_ORIGINS),
    wsHeartbeatInterval: 30_000,
    wsIdleTimeout: 90_000,
  };
}
