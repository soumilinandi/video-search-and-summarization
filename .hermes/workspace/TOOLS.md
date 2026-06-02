# TOOLS.md - NemoHermes VSS Tools

## Sandbox Host Alias

Inside the NemoClaw/OpenShell sandbox, VSS services on the host are reachable
through:

```bash
export HOST_IP=host.openshell.internal
```

The VSS policy allows this alias on the VSS backend ports. `localhost` means
the sandbox itself, not the VSS host.

## VSS Deployment

Deployment and teardown are delegated to the host-side VSS Orchestrator MCP
server:

```text
http://host.openshell.internal:9988/mcp
```

Use the orchestrator for host Docker work. Do not run `docker compose`,
`deploy/docker/scripts/dev-profile.sh`, or raw host deployment commands from
inside this sandbox.

If Hermes exposes `vss_orchestrator__*` tools natively, use those tools. If
they are not registered, call the MCP server with JSON-RPC over HTTP.

## MCP Reachability

Check whether the sandbox can reach the host orchestrator:

```bash
curl -s -o /dev/null --max-time 5 "http://${HOST_IP}:9988/" \
  && echo "orchestrator host reachable"
```

Do not use `curl -f` for this generic check. Some MCP routes return 404 from
`GET /` even when the server is reachable.

## Manual MCP Handshake

Use this fallback when native Hermes MCP tooling is unavailable.

```bash
SID=$(curl -sN -D /tmp/vss-mcp-headers.txt -X POST "${VSS_ORCHESTRATOR_MCP_URL}" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  --data @- <<'EOF' >/dev/null
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"vss-nemohermes","version":"0.1.0"}}}
EOF
  grep -i '^mcp-session-id:' /tmp/vss-mcp-headers.txt | awk '{print $2}' | tr -d '\r')

curl -s -X POST "${VSS_ORCHESTRATOR_MCP_URL}" \
  -H "Mcp-Session-Id: $SID" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  --data '{"jsonrpc":"2.0","method":"notifications/initialized"}'
```

Call a tool:

```bash
curl -s -X POST "${VSS_ORCHESTRATOR_MCP_URL}" \
  -H "Mcp-Session-Id: $SID" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  --data @- <<'EOF'
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"vss_orchestrator__profiles","arguments":{}}}
EOF
```

## Deployment Tool Chains

Map user intent to the smallest safe chain:

| User asks | Tool chain |
|---|---|
| list profiles | `vss_orchestrator__profiles` |
| check prerequisites | `vss_orchestrator__prereqs` |
| generate artifacts | `vss_orchestrator__docker_generate` |
| deploy a profile | `prereqs` -> `docker_generate` -> `docker_up` -> poll `docker_status` |
| inspect running services | `vss_orchestrator__docker_list` |
| read logs | `vss_orchestrator__docker_logs` |
| tear down | `vss_orchestrator__docker_down` -> poll `docker_status` |

For long deploys, report one short progress update after each poll. Poll at the
cadence returned by the orchestrator.
