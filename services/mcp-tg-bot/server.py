"""svc-mcp-tg-bot — Telegram Alert MCP Server for AID v3+ (P032 Step 6).

Two transports:
  • stdio  — used by Claude Code main + sub-agents via ~/.claude/.mcp.json
  • HTTP   — used by FSM bash scripts via curl localhost:8817/send_message

Tools:
  • send_message(text, parse_mode="HTML", chat_id=None)

Endpoints:
  • POST /send_message  — same shape as the tool, for FSM bash callers
  • GET  /health        — Docker healthcheck

Configuration via env (loaded from container env_file: /opt/eco/services/.env):
  TELEGRAM_ALERT_BOT_TOKEN          required for actual delivery
  TELEGRAM_ALERT_DEFAULT_CHAT_ID    used when send_message chat_id is None
  MCP_HTTP_PORT                     default 8817
  MCP_HTTP_HOST                     default 127.0.0.1 (localhost-only — see plan §S.2)
"""
from __future__ import annotations

import argparse
import os
from typing import Any

import httpx
from dotenv import load_dotenv
from fastmcp import FastMCP

load_dotenv()

mcp = FastMCP(name="svc-mcp-tg-bot", version="1.0.0")

BOT_TOKEN = os.environ.get("TELEGRAM_ALERT_BOT_TOKEN", "")
DEFAULT_CHAT_ID = os.environ.get("TELEGRAM_ALERT_DEFAULT_CHAT_ID", "")
HTTP_PORT = int(os.environ.get("MCP_HTTP_PORT", "8817"))
# Bind to 127.0.0.1 by default to prevent LAN exposure even when the
# container runs with `network_mode: host` (plan §S.2 — Risks row LAN exposure).
# Override only when explicit external access is needed.
HTTP_HOST = os.environ.get("MCP_HTTP_HOST", "127.0.0.1")


@mcp.tool()
async def send_message(
    text: str,
    parse_mode: str = "HTML",
    chat_id: str | None = None,
) -> dict[str, Any]:
    """Send a Telegram message via the alert bot.

    Args:
        text: Message body. HTML parse_mode supports <b>, <i>, <code>, <pre>, <a>.
        parse_mode: "HTML" (default), "Markdown", or "MarkdownV2".
        chat_id: Target chat ID. None → uses TELEGRAM_ALERT_DEFAULT_CHAT_ID.

    Returns:
        {"ok": bool, "message_id": int | None, "error": str | None}
    """
    if not BOT_TOKEN:
        return {"ok": False, "message_id": None, "error": "TELEGRAM_ALERT_BOT_TOKEN not set"}

    target_chat = chat_id or DEFAULT_CHAT_ID
    if not target_chat:
        return {
            "ok": False,
            "message_id": None,
            "error": "No chat_id provided and TELEGRAM_ALERT_DEFAULT_CHAT_ID not set",
        }

    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    payload = {"chat_id": target_chat, "text": text, "parse_mode": parse_mode}

    async with httpx.AsyncClient(timeout=5.0) as client:
        try:
            resp = await client.post(url, json=payload)
            data = resp.json()
            if data.get("ok"):
                return {"ok": True, "message_id": data["result"]["message_id"], "error": None}
            return {
                "ok": False,
                "message_id": None,
                "error": data.get("description", "Unknown Telegram API error"),
            }
        except httpx.HTTPError as e:
            return {"ok": False, "message_id": None, "error": str(e)}


@mcp.custom_route("/health", methods=["GET"])
async def health_check(request):
    """Docker healthcheck endpoint. Always 200 OK regardless of token state —
    distinguishes container-up from token-misconfigured (latter shows up as
    {ok: false} on the tool/endpoint, not as health failure)."""
    from starlette.responses import JSONResponse

    return JSONResponse(
        {
            "status": "ok",
            "service": "svc-mcp-tg-bot",
            "version": "1.0.0",
            "token_configured": bool(BOT_TOKEN),
            "default_chat_configured": bool(DEFAULT_CHAT_ID),
        }
    )


@mcp.custom_route("/send_message", methods=["POST"])
async def send_message_http(request):
    """HTTP wrapper for the send_message tool — used by FSM bash callers
    (curl POST localhost:8817/send_message). Body shape:
        {"text": "...", "parse_mode": "HTML", "chat_id": null}
    """
    from starlette.responses import JSONResponse

    body = await request.json()
    result = await send_message(
        text=body.get("text", ""),
        parse_mode=body.get("parse_mode", "HTML"),
        chat_id=body.get("chat_id"),
    )
    return JSONResponse(result)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--transport", choices=["stdio", "http"], default="stdio")
    parser.add_argument("--port", type=int, default=HTTP_PORT)
    parser.add_argument("--host", default=HTTP_HOST)
    args = parser.parse_args()

    if args.transport == "stdio":
        mcp.run(transport="stdio")
    else:
        mcp.run(transport="http", host=args.host, port=args.port)


if __name__ == "__main__":
    main()
