# AGENTS.md - VSS NemoHermes Workspace

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
Prefer the Hermes MCP tools from `vss_orchestrator` when they are available.
If those tools are not listed, use the installed command bridge instead:

```bash
/sandbox/bin/vss-orchestrator <tool> '<json arguments>'
```

When the user asks for the VSS orchestrator, deployment profiles,
prerequisites, compose generation, deploy, status, logs, or teardown, use the
Hermes MCP tools or `/sandbox/bin/vss-orchestrator`. Do not satisfy these
requests by only reading a skill and running local shell checks in the sandbox.
Skills are reference material; the orchestrator is the execution path.

For prerequisite checks, the first command must be:

```bash
/sandbox/bin/vss-orchestrator prereqs
```

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

## Progress

Deployments can take several minutes. When polling `docker_status`, give the
user a short plain-language update after every poll and continue until the
operation reaches `success`, `error`, or `cancelled`.

## Safety

Ask before destructive actions unless the user explicitly requested teardown.
Never print API keys or tokens.
