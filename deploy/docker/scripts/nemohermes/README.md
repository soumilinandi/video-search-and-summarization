# NemoHermes VSS Installer

`init_nemohermes.sh` bootstraps a NemoClaw/OpenShell sandbox with the Hermes
agent, applies the VSS sandbox policy, installs the repository `skills/`, and
uploads Hermes workspace instructions.

This is the managed/sandboxed Hermes path. The standalone Hermes path is
documented below.

## What It Does

When you run `init_nemohermes.sh`, it:

1. Runs NemoClaw onboarding with `--agent hermes`, or falls back to
   `$HOME/NemoClaw/install.sh`.
2. Configures the OpenShell inference provider.
3. Applies the VSS sandbox policy from `assets/vss_nemoclaw_policy.yaml`.
4. Configures `NGC_CLI_API_KEY` as a sandbox credential provider when present.
5. Installs each VSS skill from the repository `skills/` directory using
   `nemohermes <sandbox> skill install`.
6. Uploads Hermes workspace files to `/sandbox/.hermes-data/workspace`.
7. Installs `/sandbox/bin/vss-orchestrator`, a small command bridge for the
   host-side HTTP MCP endpoint.
8. Registers the host-side VSS Orchestrator MCP server in
   `/sandbox/.hermes/config.yaml`.
9. Installs the NGC CLI inside the sandbox on a best-effort basis.
10. Checks the Hermes API health endpoint on port `8642`.
11. Optionally enables the Hermes web dashboard when `NEMOCLAW_HERMES_DASHBOARD=1`.

It intentionally does not update `openclaw.json`, install the `.openclaw`
plugin, restart `openclaw-gateway`, or print an OpenClaw dashboard URL.

## VSS Skills vs Hermes Plugins

VSS uses repository `SKILL.md` agent skills. In a NemoHermes sandbox, those are
installed with `nemohermes <sandbox> skill install <path>`.

Hermes runtime plugins are different: they add Python code, hooks, or runtime
dependencies under `/sandbox/.hermes/plugins/<plugin-name>` and should be baked
into a custom Hermes sandbox image with `nemohermes onboard --from`. VSS does
not require a custom Hermes runtime plugin for the current skill workflow.

## Usage

`NEMOCLAW_PROVIDER` is required.

### NVIDIA Endpoints

```bash
NEMOCLAW_PROVIDER=build \
NVIDIA_API_KEY="$NVIDIA_API_KEY" \
  bash deploy/docker/scripts/nemohermes/init_nemohermes.sh vss-hermes
```

### OpenAI-Compatible Endpoint

```bash
NEMOCLAW_PROVIDER=custom \
NEMOCLAW_ENDPOINT_URL=http://host.docker.internal:8000/v1 \
NEMOCLAW_MODEL=Qwen/Qwen3.6-35B-A3B-FP8 \
COMPATIBLE_API_KEY=nemoclaw-local-qwen \
  bash deploy/docker/scripts/nemohermes/init_nemohermes.sh vss-hermes
```

## Options

| Option | Description | Default |
|---|---|---|
| `--sandbox-name NAME` | Target sandbox name | `vss-hermes` |
| `--model NAME` | Hermes inference model | `nvidia/nemotron-3-super-120b-a12b` |
| `--nvidia-base-url URL` | NVIDIA API base URL | `https://integrate.api.nvidia.com/v1` |
| `--nvidia-api-key KEY` | API key for the `build` provider | `NVIDIA_API_KEY` |
| `--endpoint-url URL` | OpenAI-compatible endpoint URL | `NEMOCLAW_ENDPOINT_URL` |
| `--compatible-api-key KEY` | OpenAI-compatible endpoint key | `COMPATIBLE_API_KEY` |
| `--policy-file PATH` | VSS sandbox policy file | `assets/vss_nemoclaw_policy.yaml` |
| `--workspace-dir PATH` | Hermes workspace template directory | `.hermes/workspace` |

## Environment Variables

- `VSS_REPO_DIR`: repo root used to resolve skills and policy file
- `NEMOCLAW_SANDBOX_NAME`: target sandbox name, default `vss-hermes`
- `NEMOCLAW_PROVIDER`: required, `build` or `custom`
- `NEMOCLAW_ENDPOINT_URL`: required when `NEMOCLAW_PROVIDER=custom`
- `COMPATIBLE_API_KEY`: required when `NEMOCLAW_PROVIDER=custom`
- `OPENSHELL_PROVIDER_NAME`: OpenShell inference provider name, default `nvidia`
- `NEMOCLAW_MODEL`: Hermes inference model
- `NVIDIA_API_KEY`: required when `NEMOCLAW_PROVIDER=build`
- `NGC_CLI_API_KEY`: optional sandbox credential and host orchestrator credential
- `NEMOCLAW_POLICY_FILE`: VSS sandbox policy file
- `NEMOHERMES_API_PORT`: Hermes API port, default `8642`
- `NEMOHERMES_MCP_URL`: VSS Orchestrator MCP URL from the sandbox, default `http://host.openshell.internal:9988/mcp`
- `NEMOCLAW_HERMES_DASHBOARD`: set to `1`/`true` to enable the optional Hermes web dashboard
- `NEMOCLAW_HERMES_DASHBOARD_PORT`: Hermes dashboard port, default `9119`

## Managed Deployment Flow

For sandboxed NemoHermes, host Docker work still happens through the
host-side VSS Orchestrator MCP server. Start it from the notebook, then ask
Hermes to deploy or inspect VSS using the VSS Orchestrator MCP tools. Hermes
may display client-specific tool prefixes; match the underlying operation names
such as `profiles`, `prereqs`, `docker_generate`, `docker_up`, and
`docker_status`.

The sandbox reaches the host through:

```text
http://host.openshell.internal:9988/mcp
```

The installer registers that URL in `/sandbox/.hermes/config.yaml` as:

```yaml
mcp_servers:
  vss_orchestrator:
    url: "http://host.openshell.internal:9988/mcp"
```

Start the host-side MCP server before connecting to NemoHermes so the agent can
discover the server when the session starts. If a session was already open,
reconnect it.

If Hermes MCP tools are not listed, use the installed command bridge:

```bash
/sandbox/bin/vss-orchestrator profiles
/sandbox/bin/vss-orchestrator prereqs
/sandbox/bin/vss-orchestrator docker_generate '{"profile":"base"}'
```

The command bridge talks to the same HTTP MCP endpoint and keeps host Docker
operations outside the sandbox.

## Connect

After setup:

```bash
nemohermes vss-hermes connect
```

The Hermes API is expected at:

```text
http://127.0.0.1:8642/v1
```

The Hermes web dashboard is disabled by default. To enable it during setup:

```bash
NEMOCLAW_HERMES_DASHBOARD=1 \
NEMOCLAW_PROVIDER=build \
NVIDIA_API_KEY="$NVIDIA_API_KEY" \
  bash deploy/docker/scripts/nemohermes/init_nemohermes.sh vss-hermes
```

When enabled, the dashboard is expected at:

```text
http://127.0.0.1:9119/
```

## Standalone Hermes

For users who want Hermes directly on the VSS host, do not use this
NemoHermes installer. Use one of these simpler paths.

Primary setup: register this repository's skills directory:

```bash
hermes config edit
```

```yaml
skills:
  external_dirs:
    - /path/to/video-search-and-summarization/skills
```

OpenClaw migration is optional and is only needed when the user wants to bring
compatible existing OpenClaw user data into Hermes:

```bash
hermes claw migrate --dry-run
hermes claw migrate --preset user-data --skill-conflict rename
```

Full migration, including compatible provider secrets:

```bash
hermes claw migrate --preset full --migrate-secrets --yes
```

Standalone Hermes runs on the host and can use shell, Docker, compose, and
VSS APIs directly. The VSS Orchestrator MCP server is optional in that path.
