# AGENTS.md - VSS NemoHermes Workspace

## Every Session

Before starting user work:

1. Read `ENV.md` and export the variables shown there.
2. Read `SOUL.md`.
3. Read `TOOLS.md`.
4. If `memory/YYYY-MM-DD.md` exists, read today's and yesterday's notes.

## VSS Rules

This is a NemoClaw/OpenShell sandbox running Hermes. Host Docker and VSS
deployment operations go through the VSS Orchestrator MCP server on the host.
Prefer the Hermes MCP tools from `vss_orchestrator` when they are available.
If those tools are not listed, use the installed command bridge instead:

```bash
/sandbox/bin/vss-orchestrator <tool> '<json arguments>'
```

Do not run raw host deployment commands from the sandbox. Use MCP tools for:

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
