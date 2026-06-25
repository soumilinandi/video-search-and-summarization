# AGENTS.md - VSS NemoClaw Hermes Workspace

## Every Session

Before starting user work:

1. Read `ENV.md` and export the variables shown there.
2. Read `TOOLS.md`.
3. If `memory/YYYY-MM-DD.md` exists, read today's and yesterday's notes.

Hermes loads its persona from `/sandbox/.hermes/SOUL.md`; do not look for a
project-local `SOUL.md`.

## VSS Rules

This is a NemoClaw/OpenShell sandbox running Hermes. Host Docker and VSS
deployment operations go through the VSS Orchestrator MCP server on the host.
Use the Hermes MCP tools from `vss_orchestrator`.

When the user asks for the VSS orchestrator, deployment profiles,
prerequisites, compose generation, deploy, status, logs, or teardown, use the
Hermes MCP tools. Do not satisfy these requests by only reading a skill and
running local shell checks in the sandbox. Skills are reference material; the
orchestrator is the execution path.

For prerequisite checks, call the `prereqs` operation from the
`vss_orchestrator` MCP server.

Do not ask for sudo and do not run sandbox-local prerequisite probes such as
`sudo -n true`, `docker ps`, `nvidia-smi`, `ngc --version`, `sysctl`, or
package-manager checks. Those checks belong to the host-side orchestrator.

Do not run raw host deployment commands from the sandbox. Use orchestrator tools
for:

- prerequisites
- compose artifact generation
- deploy
- status
- logs
- teardown

For read-only VSS service calls, use `${HOST_IP}` from `ENV.md`.

If the `vss_orchestrator` MCP tools are not available, tell the user to start
the host MCP server and reconnect Hermes. If they are still unavailable, the
Hermes sandbox likely was not built with the Python `mcp` package; ask the user
to rerun setup on a fresh/rebuilt sandbox with MCP baked into the Hermes image.

## Progress

Deployments can take several minutes. When polling `docker_status`, give the
user a short plain-language update after every poll and continue until the
operation reaches `success`, `error`, or `cancelled`.

## Safety

Ask before destructive actions unless the user explicitly requested teardown.
Never print API keys or tokens.
