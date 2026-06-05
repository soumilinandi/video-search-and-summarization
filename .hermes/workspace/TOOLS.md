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

The NemoHermes installer registers this endpoint in `/sandbox/.hermes/config.yaml`:

```yaml
mcp_servers:
  vss_orchestrator:
    url: "http://host.openshell.internal:9988/mcp"
```

Start the host MCP server before connecting to Hermes. If Hermes was already
connected, reconnect the session.

Use the orchestrator for host Docker work. Do not run `docker compose`,
`deploy/docker/scripts/dev-profile.sh`, or raw host deployment commands from
inside this sandbox.

Use the Hermes MCP tools from the `vss_orchestrator` server when available.
The exact displayed tool names may be prefixed by Hermes. Match by the
underlying VSS Orchestrator operation: `profiles`, `prereqs`,
`docker_generate`, `docker_read`, `docker_up`, `docker_status`, `docker_list`,
`docker_logs`, and `docker_down`.

If MCP tools are not registered, verify the HTTP endpoint below and reconnect
or use the installed command bridge before deploying from the sandbox.

## Orchestrator Command Bridge

The NemoHermes installer uploads:

```bash
/sandbox/bin/vss-orchestrator
```

Use it when Hermes MCP tools are not listed. It calls the same HTTP MCP endpoint
and maps the first argument to `vss_orchestrator__<tool>`.

```bash
/sandbox/bin/vss-orchestrator health
/sandbox/bin/vss-orchestrator list
/sandbox/bin/vss-orchestrator profiles
/sandbox/bin/vss-orchestrator prereqs
/sandbox/bin/vss-orchestrator docker_generate '{"profile":"base"}'
/sandbox/bin/vss-orchestrator docker_up '{"docker_compose_id":"..."}'
/sandbox/bin/vss-orchestrator docker_status '{"docker_compose_id":"..."}'
```

Pass tool arguments as one JSON object, or use `-` to read the JSON object from
stdin.

## MCP Reachability

Check whether the sandbox can reach the host orchestrator:

```bash
/sandbox/bin/vss-orchestrator health
```

## Deployment Tool Chains

Map user intent to the smallest safe chain:

| User asks | Tool chain |
|---|---|
| list profiles | `profiles` |
| check prerequisites | `prereqs` |
| generate artifacts | `docker_generate` |
| deploy a profile | `prereqs` -> `docker_generate` -> `docker_up` -> poll `docker_status` |
| inspect running services | `docker_list` |
| read logs | `docker_logs` |
| tear down | `docker_down` -> poll `docker_status` |

For long deploys, report one short progress update after each poll. Poll at the
cadence returned by the orchestrator.
