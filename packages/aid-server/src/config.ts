/** Server configuration from environment variables. */

export interface ServerConfig {
  port: number;
  host: string;
  /** Root directory of the project (where .aid-o/ lives). */
  projectRoot: string;
  /** Allowed CORS origins. */
  corsOrigins: string[];
  /** WebSocket heartbeat interval in ms. */
  wsHeartbeatInterval: number;
  /** WebSocket idle timeout in ms. */
  wsIdleTimeout: number;
}

export function loadConfig(): ServerConfig {
  return {
    port: parseInt(process.env.AID_PORT ?? '3001', 10),
    host: process.env.AID_HOST ?? '0.0.0.0',
    projectRoot: process.env.AID_PROJECT_ROOT ?? process.cwd(),
    corsOrigins: (process.env.AID_CORS_ORIGINS ?? 'http://localhost:5173,http://localhost:3000').split(','),
    wsHeartbeatInterval: 30_000,
    wsIdleTimeout: 90_000,
  };
}
