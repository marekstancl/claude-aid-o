# svc-mcp-tg-bot — Telegram Alert MCP Server

FastMCP server providing a `send_message` tool plus an HTTP `/send_message`
endpoint, used by AID v3 for `fsm_precondition_repeated_fail` alerts and by
Claude Code (main + sub-agents) for ad-hoc Telegram notifications.

## What it offers

- **stdio transport** — for Claude Code via `~/.claude/.mcp.json`.
  Tools: `send_message(text, parse_mode="HTML", chat_id=None)`.
- **HTTP transport** — for bash callers (FSM scripts) on `localhost:8818`.
  Endpoints:
  - `GET  /health` — Docker healthcheck. Returns
    `{status, service, version, token_configured, default_chat_configured}`.
  - `POST /send_message` — JSON body `{text, parse_mode, chat_id}`,
    returns `{ok, message_id, error}`.

## Configuration

Bot token + default chat live in `/opt/eco/services/.env` (NOT committed,
per ekosystem secret-handling convention):

```bash
TELEGRAM_ALERT_BOT_TOKEN=<from BotFather>
TELEGRAM_ALERT_DEFAULT_CHAT_ID=<-100... for groups, @channel, or numeric DM>
```

See `.env.example` for the full template (including optional `MCP_HTTP_PORT`
and `MCP_HTTP_HOST` overrides).

## Deploy (PM steps, post-merge)

```bash
# 1. Token + chat ID into shared env (out-of-band, not in git)
sudo cp -n /opt/eco/projects/aid-orchestrator/services/mcp-tg-bot/.env.example /opt/eco/services/.env
$EDITOR /opt/eco/services/.env   # fill TELEGRAM_ALERT_BOT_TOKEN + DEFAULT_CHAT_ID
sudo chmod 600 /opt/eco/services/.env

# 2. Append the service block from docker-compose.snippet.yml into
#    /opt/eco/services/docker-compose.yml (separate git tree).
$EDITOR /opt/eco/services/docker-compose.yml

# 3. Build + start
cd /opt/eco/services && sudo docker compose up -d --build svc-mcp-tg-bot

# 4. Verify
docker ps --filter name=svc-mcp-tg-bot --format '{{.Names}} {{.Status}}'
curl -fsS http://127.0.0.1:8818/health
```

> **Port conflict caveat:** as of 2026-05-05 port 8818 is held by
> `svc-mcp-postgres-ops`. Resolve before step 3 (either migrate
> svc-mcp-postgres-ops or renumber svc-mcp-tg-bot to e.g. 8819 — see the
> root PR description deploy guide for the renumbering checklist).

## Claude Code MCP integration

Add to `~/.claude/.mcp.json` (per-machine, per-user — NOT in any git repo):

```json
{
  "mcpServers": {
    "svc-mcp-tg-bot": {
      "command": "docker",
      "args": ["exec", "-i", "svc-mcp-tg-bot", "python", "-m", "server", "--transport", "stdio"],
      "env": {}
    }
  }
}
```

Restart Claude Code, then verify via the `/mcp` slash command.

## FSM bash callers

The Step 3 helper `try_telegram_alert()` already POSTs to
`http://localhost:8818/send_message`. Best-effort: if the service is
down, it logs `[INFO] Telegram alert skipped (svc-mcp-tg-bot not
available — non-fatal)` and the FSM transition continues.

## Local development

```bash
cd services/mcp-tg-bot
docker build -t svc-mcp-tg-bot:dev .
docker run --rm -e MCP_HTTP_HOST=0.0.0.0 -p 127.0.0.1:8829:8818 svc-mcp-tg-bot:dev
curl -fsS http://127.0.0.1:8829/health
```

`MCP_HTTP_HOST=0.0.0.0` is needed for port-mapped (non-host-network)
runs because the container's 127.0.0.1 isn't reachable from outside via
`-p`. Production uses `network_mode: host` and keeps the safer 127.0.0.1
default per plan §S.2 LAN-exposure mitigation.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Container restart loop, `unhealthy` | Port 8818 already in use | `docker ps --filter expose=8818` to find conflict; renumber via `MCP_HTTP_PORT` env or stop the other service. |
| `/send_message` returns `{ok:false, error:"...not set"}` | Token/chat ID missing in `/opt/eco/services/.env` | Edit `.env`, `docker compose restart svc-mcp-tg-bot`. |
| `/send_message` returns `{ok:false, error:"Unauthorized"}` | Bot token revoked or wrong | Re-issue via BotFather; update `.env`; restart. |
| `/send_message` returns `{ok:false, error:"chat not found"}` | Wrong chat ID format (missing `-100` for groups) | Fix `.env`, restart. |
| `curl /health` hangs / connection refused | Container not running, or HTTP_HOST=127.0.0.1 in non-host-network mode | Check `docker logs svc-mcp-tg-bot`; ensure `network_mode: host` in compose, or set `MCP_HTTP_HOST=0.0.0.0` for `-p` runs. |
