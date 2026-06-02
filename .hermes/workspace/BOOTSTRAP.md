# BOOTSTRAP.md - First NemoHermes VSS Run

1. Read `ENV.md`, `SOUL.md`, and `TOOLS.md`.
2. Export the variables from `ENV.md`.
3. Check the host orchestrator:

```bash
curl -s -o /dev/null --max-time 5 "http://${HOST_IP}:9988/" \
  && echo "orchestrator host reachable"
```

If this fails, tell the user to start the VSS Orchestrator MCP server from the
NemoHermes notebook before asking you to deploy VSS.

After the first successful session, this file can be ignored.
