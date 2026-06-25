# NemoClaw VSS Installer

`init_nemoclaw.sh` bootstraps a NemoClaw-managed sandbox on a Brev instance for
either OpenClaw or Hermes, configures its model provider, applies the VSS
sandbox policy, and installs the VSS agent skills.

Select the managed agent runtime with `NEMOCLAW_AGENT_RUNTIME`:

- `openclaw` — OpenClaw UI/plugin path. This is the default.
- `hermes` — Hermes agent path through NemoClaw.

It supports two onboard providers, selected via the **required** `NEMOCLAW_PROVIDER` env var:

- `build` — NVIDIA Endpoints (`integrate.api.nvidia.com`), authenticated with `NVIDIA_API_KEY`.
- `custom` — any OpenAI-compatible endpoint (e.g. a local vLLM), configured with `NEMOCLAW_ENDPOINT_URL` and `COMPATIBLE_API_KEY`.

## What It Does

When you run `init_nemoclaw.sh`, it:

1. Runs NemoClaw onboarding if `nemoclaw` is already available, or falls back to `/home/ubuntu/NemoClaw/install.sh`.
2. Configures the OpenShell inference provider.
3. Applies the VSS sandbox policy from `assets/vss_nemoclaw_policy.yaml`.
4. Runs the selected runtime setup.

For `NEMOCLAW_AGENT_RUNTIME=openclaw`, it:

- packages and installs the `.openclaw` plugin,
- updates OpenClaw allowed origins,
- registers the VSS Orchestrator as a native OpenClaw MCP server,
- refreshes the OpenClaw dashboard forward.

For `NEMOCLAW_AGENT_RUNTIME=hermes`, it:

- creates the Hermes sandbox with a generated `--from` Dockerfile that installs
  Python `mcp` into `/opt/hermes/.venv`,
- installs each repository skill with `nemohermes <sandbox> skill install`,
- uploads `.hermes/workspace` context files into the sandbox,
- registers the host VSS Orchestrator MCP server in `/sandbox/.hermes/config.yaml`.

## Expected Environment

This script is meant to run on a NemoClaw-ready Ubuntu machine, typically a Brev instance, with this repository already checked out.

The following repo content is expected to exist:

- `skills/`
- `assets/vss_nemoclaw_policy.yaml`
- `deploy/docker/scripts/nemoclaw/update_openclaw_config.py`
- `.openclaw/` when using `NEMOCLAW_AGENT_RUNTIME=openclaw`
- `.hermes/workspace/` when using `NEMOCLAW_AGENT_RUNTIME=hermes`

The following host tools or resources are also expected:

- `python3`
- `docker`
- `sudo`
- a working NemoClaw install source at `/home/ubuntu/NemoClaw/install.sh`, unless `nemoclaw` is already in `PATH`

## Usage

`NEMOCLAW_PROVIDER` is required. The script exits immediately if it is unset.

### `build` provider (NVIDIA Endpoints)

```bash
NEMOCLAW_AGENT_RUNTIME=openclaw \
NEMOCLAW_PROVIDER=build \
NVIDIA_API_KEY="$NVIDIA_API_KEY" \
  bash deploy/docker/scripts/nemoclaw/init_nemoclaw.sh demo
```

Or use explicit flags:

```bash
NEMOCLAW_PROVIDER=build \
  bash deploy/docker/scripts/nemoclaw/init_nemoclaw.sh \
    --agent-runtime openclaw \
    --sandbox-name demo \
    --model nvidia/nemotron-3-super-120b-a12b \
    --nvidia-api-key "$NVIDIA_API_KEY"
```

### `custom` provider (OpenAI-compatible endpoint)

`NEMOCLAW_ENDPOINT_URL` and `COMPATIBLE_API_KEY` are required when `NEMOCLAW_PROVIDER=custom`:

```bash
NEMOCLAW_PROVIDER=custom \
NEMOCLAW_ENDPOINT_URL=http://host.docker.internal:8000/v1 \
NEMOCLAW_MODEL=Qwen/Qwen3.6-35B-A3B-FP8 \
COMPATIBLE_API_KEY=nemoclaw-local-qwen \
NVIDIA_API_KEY="$NVIDIA_API_KEY" \
  bash deploy/docker/scripts/nemoclaw/init_nemoclaw.sh demo
```

### Hermes runtime

Use the same script and switch only the runtime:

```bash
NEMOCLAW_AGENT_RUNTIME=hermes \
NEMOCLAW_PROVIDER=build \
NVIDIA_API_KEY="$NVIDIA_API_KEY" \
  bash deploy/docker/scripts/nemoclaw/init_nemoclaw.sh demo
```

Hermes native MCP support requires the Python `mcp` package in the Hermes
runtime environment. By default, this script generates a Dockerfile from
`$HOME/NemoClaw/agents/hermes/Dockerfile`, adds the `mcp` install layer, and
uses it for fresh Hermes onboarding. Override with `HERMES_FROM_DOCKERFILE` or
`--from-dockerfile`.

Equivalent with CLI flags:

```bash
NEMOCLAW_PROVIDER=custom \
  bash deploy/docker/scripts/nemoclaw/init_nemoclaw.sh \
    --sandbox-name demo \
    --model Qwen/Qwen3.6-35B-A3B-FP8 \
    --endpoint-url http://host.docker.internal:8000/v1 \
    --compatible-api-key nemoclaw-local-qwen \
    --nvidia-api-key "$NVIDIA_API_KEY"
```

### Background run on a Brev instance

```bash
nohup env NEMOCLAW_PROVIDER=build NVIDIA_API_KEY="$NVIDIA_API_KEY" \
  bash /home/ubuntu/video-search-and-summarization/deploy/docker/scripts/nemoclaw/init_nemoclaw.sh \
  > /tmp/nemoclaw_install.log 2>&1 &
```

## Options

| Option | Description | Default |
|---|---|---|
| `--agent-runtime RUNTIME` | `openclaw` or `hermes` | `openclaw` |
| `--sandbox-name NAME` | Target sandbox name | `demo` |
| `--model NAME` | NemoClaw inference model | `nvidia/nemotron-3-super-120b-a12b` |
| `--nvidia-base-url URL` | NVIDIA API base URL for the `build` provider | `https://integrate.api.nvidia.com/v1` |
| `--nvidia-api-key KEY` | API key for the `build` provider | `NVIDIA_API_KEY` env fallback |
| `--endpoint-url URL` | OpenAI-compatible endpoint URL (required when `NEMOCLAW_PROVIDER=custom`) | — |
| `--compatible-api-key KEY` | API key for the OpenAI-compatible endpoint (required when `NEMOCLAW_PROVIDER=custom`) | — |
| `--openclaw-config-script PATH` | Path to `update_openclaw_config.py` | `deploy/docker/scripts/nemoclaw/update_openclaw_config.py` |
| `--policy-file PATH` | Custom sandbox policy file | `assets/vss_nemoclaw_policy.yaml` |
| `--workspace-dir PATH` | Hermes workspace/context directory | `.hermes/workspace` |
| `--from-dockerfile PATH` | Custom Hermes Dockerfile | generated from `$HOME/NemoClaw/agents/hermes/Dockerfile` |
| `--help` | Show usage help | n/a |

## Environment Variables

The script also honors these environment variables:

- `VSS_REPO_DIR`: repo root used to resolve plugin assets and the default policy file
- `NEMOCLAW_AGENT_RUNTIME`: `openclaw` or `hermes`, default `openclaw`
- `NEMOCLAW_SANDBOX_NAME`
- `NEMOCLAW_PROVIDER` (**required**) — `build` or `custom`
- `NEMOCLAW_ENDPOINT_URL` — OpenAI-compatible endpoint URL; required when `NEMOCLAW_PROVIDER=custom`
- `COMPATIBLE_API_KEY` — API key for the OpenAI-compatible endpoint; required when `NEMOCLAW_PROVIDER=custom`
- `OPENSHELL_PROVIDER_NAME`
- `NEMOCLAW_MODEL`
- `NVIDIA_BASE_URL`
- `NVIDIA_API_KEY`
- `OPENCLAW_CONFIG_UPDATE_SCRIPT`
- `OPENCLAW_PLUGIN_VARIANT`: plugin workspace overlay, default `nemoclaw`
- `NEMOCLAW_POLICY_FILE`
- `VSS_CONTAINER_NAME`: explicit OpenShell gateway container name, if autodetection is not sufficient
- `VSS_NAMESPACE`: Kubernetes namespace for the sandbox pod, default `openshell`
- `HERMES_WORKSPACE_DIR`: Hermes workspace/context directory, default `.hermes/workspace`
- `HERMES_MCP_URL`: VSS Orchestrator MCP URL from the sandbox, default `http://host.openshell.internal:9988/mcp`
- `HERMES_BAKE_MCP`: set to `0` to skip generated Dockerfile creation
- `HERMES_FROM_DOCKERFILE`: custom Hermes Dockerfile path
- `HERMES_BUILD_DIR`: generated Dockerfile directory

## Expected Output

Successful runs usually include log lines like:

```text
[init_nemoclaw] Start installing/onboarding NemoClaw
[init_nemoclaw] Finished installing/onboarding NemoClaw
[init_nemoclaw] Applying custom policy file /home/ubuntu/video-search-and-summarization/assets/vss_nemoclaw_policy.yaml to sandbox demo
[init_nemoclaw] VSS skills installed
[init_nemoclaw] Updating OpenClaw config for sandbox demo using script /home/ubuntu/video-search-and-summarization/deploy/docker/scripts/nemoclaw/update_openclaw_config.py
OpenClaw UI at https://18789-<brev-id>.brevlab.com/#token=<token>
```

If the config update succeeds, the helper also prints:

- `Updated /sandbox/.openclaw/openclaw.json` or `No JSON change needed ...`
- `Brev instance ID: ...`
- `Origin allowed in OpenClaw: https://18789-<brev-id>.brevlab.com`
- `MCP server registered: vss_orchestrator -> http://host.openshell.internal:9988/mcp`
- `Dashboard token: ...`

## Troubleshooting

- Verify `NEMOCLAW_PROVIDER` is set (`build` or `custom`) — the script exits immediately if it is unset.
- For `NEMOCLAW_PROVIDER=custom`, verify both `NEMOCLAW_ENDPOINT_URL` and `COMPATIBLE_API_KEY` are set (or pass `--endpoint-url` / `--compatible-api-key`).
- If `openshell inference set` cannot verify an otherwise reachable endpoint,
  the script retries automatically with `--no-verify`.
- Verify `NVIDIA_API_KEY` is set before running the installer.
- If NemoClaw onboarding fails, verify `nemoclaw` is resolvable or that `/home/ubuntu/NemoClaw/install.sh` exists and is executable.
- If the custom policy is skipped, confirm `assets/vss_nemoclaw_policy.yaml` exists or pass `--policy-file`.
- If the skills upload is skipped, verify the repo checkout includes `skills/`.
- If the skills upload cannot determine a gateway container, set `VSS_CONTAINER_NAME` explicitly.
- If the OpenClaw origin update fails, run `python3 deploy/docker/scripts/nemoclaw/update_openclaw_config.py demo` directly to inspect the underlying error.
- For Hermes, if MCP tools are not listed after connecting, confirm the host MCP
  server is running, reconnect Hermes, and verify `/opt/hermes/.venv` can import
  Python `mcp`. Existing sandboxes created before the MCP layer may need to be
  rebuilt or recreated.
