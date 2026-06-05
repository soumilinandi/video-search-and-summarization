#!/usr/bin/env python3
import json
import os
import sys
import urllib.error
import urllib.request

DEFAULT_URL = "http://host.openshell.internal:9988/mcp"
PROTOCOL_VERSION = "2024-11-05"


def parse_body(content_type, body, allow_empty=False):
    text = body.decode("utf-8", "replace").strip()
    if not text:
        return None if allow_empty else {}

    if "text/event-stream" in content_type or text.startswith(("event:", "data:")):
        messages = []
        current = []
        for line in text.splitlines():
            if line.startswith("data:"):
                current.append(line[5:].lstrip())
            elif not line.strip() and current:
                messages.append("\n".join(current))
                current = []
        if current:
            messages.append("\n".join(current))
        for message in reversed(messages):
            if message and message != "[DONE]":
                text = message
                break

    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return {"raw": text}


def post(url, payload, session_id=None, allow_empty=False):
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
    }
    if session_id:
        headers["Mcp-Session-Id"] = session_id

    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            body = response.read()
            return (
                parse_body(response.headers.get("content-type", ""), body, allow_empty),
                response.headers.get("mcp-session-id"),
            )
    except urllib.error.HTTPError as exc:
        parsed = parse_body(exc.headers.get("content-type", ""), exc.read(), allow_empty=True)
        print(json.dumps({"status": "error", "http_status": exc.code, "response": parsed}, indent=2), file=sys.stderr)
        raise SystemExit(2)
    except urllib.error.URLError as exc:
        print(f"ERROR: cannot reach VSS Orchestrator MCP server: {exc}", file=sys.stderr)
        raise SystemExit(2)


def initialize(url):
    response, session_id = post(
        url,
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {},
                "clientInfo": {"name": "vss-nemohermes-wrapper", "version": "0.1.0"},
            },
        },
    )
    if isinstance(response, dict) and response.get("error"):
        print(json.dumps(response, indent=2), file=sys.stderr)
        raise SystemExit(2)
    if not session_id:
        print("ERROR: MCP server did not return mcp-session-id", file=sys.stderr)
        raise SystemExit(2)

    post(url, {"jsonrpc": "2.0", "method": "notifications/initialized"}, session_id=session_id, allow_empty=True)
    return session_id


def load_arguments(parts):
    if not parts:
        return {}

    raw = " ".join(parts)
    if raw == "-":
        raw = sys.stdin.read()
    elif raw.startswith("@"):
        with open(raw[1:], "r", encoding="utf-8") as handle:
            raw = handle.read()

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"ERROR: arguments must be a JSON object: {exc}", file=sys.stderr)
        raise SystemExit(2)
    if not isinstance(data, dict):
        print("ERROR: arguments must be a JSON object", file=sys.stderr)
        raise SystemExit(2)
    return data


def emit(response):
    print(json.dumps(response, indent=2, sort_keys=True))
    return 2 if isinstance(response, dict) and response.get("error") else 0


def usage():
    print(
        """Usage:
  /sandbox/bin/vss-orchestrator health
  /sandbox/bin/vss-orchestrator list
  /sandbox/bin/vss-orchestrator <tool> [json-arguments]

Examples:
  /sandbox/bin/vss-orchestrator profiles
  /sandbox/bin/vss-orchestrator prereqs
  /sandbox/bin/vss-orchestrator docker_generate '{"profile":"base"}'
"""
    )
    return 0


def main():
    if len(sys.argv) < 2 or sys.argv[1] in {"-h", "--help", "help"}:
        return usage()

    url = os.environ.get("VSS_ORCHESTRATOR_MCP_URL", DEFAULT_URL)
    command = sys.argv[1]
    rest = sys.argv[2:]
    if command == "call":
        if not rest:
            return usage()
        command = rest[0]
        rest = rest[1:]

    session_id = initialize(url)
    if command == "health":
        return emit({"status": "ok", "url": url})
    if command in {"list", "tools", "tools/list"}:
        response, _ = post(url, {"jsonrpc": "2.0", "id": 2, "method": "tools/list"}, session_id=session_id)
        return emit(response)

    tool = command.replace("-", "_")
    if "__" not in tool:
        tool = f"vss_orchestrator__{tool}"
    response, _ = post(
        url,
        {
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {"name": tool, "arguments": load_arguments(rest)},
        },
        session_id=session_id,
    )
    return emit(response)


if __name__ == "__main__":
    raise SystemExit(main())
