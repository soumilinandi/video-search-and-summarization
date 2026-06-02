# ENV.md - NemoHermes VSS Sandbox Environment

Set these at the start of each shell session inside the NemoHermes sandbox.

```bash
export HOST_IP=host.openshell.internal
export VSS_ORCHESTRATOR_MCP_URL=http://host.openshell.internal:9988/mcp
```

`HOST_IP` is the sandbox host alias allowed by the VSS NemoClaw policy. Use
`${HOST_IP}` for VSS backend calls from inside the sandbox. Do not replace it
with `localhost` or a literal host IP.
