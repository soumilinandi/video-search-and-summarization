# TOOLS.md - NemoClaw Hermes VSS Tools

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

The NemoClaw Hermes setup registers this endpoint in `/sandbox/.hermes/config.yaml`:

```yaml
mcp_servers:
  vss_orchestrator:
    url: "http://host.openshell.internal:9988/mcp"
```

Start the host MCP server before connecting to Hermes. If Hermes was already
connected, reconnect the session.

Use the orchestrator for host Docker work. Do not run `docker compose`,
`deploy/docker/scripts/dev-profile.sh`, `nvidia-smi`, Docker prerequisite
shell probes, or raw host deployment commands from inside this sandbox.
If a prerequisite check would require `sudo`, skip that path and call the
orchestrator instead.

Use the Hermes MCP tools from the `vss_orchestrator` server. The exact
displayed tool names may be prefixed by Hermes. Match by the underlying VSS
Orchestrator operation: `profiles`, `prereqs`, `docker_generate`,
`docker_read`, `docker_up`, `docker_status`, `docker_list`, `docker_logs`, and
`docker_down`.

Do not replace orchestrator calls with skill-only reasoning. The VSS skills
describe how deployment works, but the host checks and deploy operations must
go through `vss_orchestrator` MCP tools.

## MCP Reachability

Check whether the sandbox can reach the host orchestrator:

```bash
curl -i --max-time 5 -H 'Accept: application/json, text/event-stream' http://host.openshell.internal:9988/mcp
```

A non-2xx MCP protocol response still proves the endpoint is reachable. Use the
native `vss_orchestrator` MCP tools for actual operations.

Do not replace this with `sudo`, `docker ps`, `nvidia-smi`, `ngc --version`,
`sysctl`, or package-manager probes from inside the sandbox.

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
