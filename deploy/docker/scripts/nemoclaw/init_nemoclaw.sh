#!/usr/bin/env bash
# Configures a NemoClaw-managed VSS agent runtime. Set
# NEMOCLAW_AGENT_RUNTIME=openclaw or hermes.
#
# The provider can be NVIDIA's hosted Nemotron model (NEMOCLAW_PROVIDER=build)
# or an OpenAI-compatible endpoint (NEMOCLAW_PROVIDER=custom).
# For "build": requires NVIDIA_API_KEY (via --nvidia-api-key, env var, or interactive prompt).
# For "custom": requires NEMOCLAW_ENDPOINT_URL and COMPATIBLE_API_KEY; NVIDIA_API_KEY is unused.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
VSS_REPO_DIR="${VSS_REPO_DIR:-$(cd "${SCRIPT_DIR}/../../../.." && pwd)}"
NEMOCLAW_REPO_DIR="${NEMOCLAW_REPO_DIR:-${HOME}/NemoClaw}"
NEMOCLAW_SANDBOX_NAME="${NEMOCLAW_SANDBOX_NAME:-demo}"
NEMOCLAW_AGENT_RUNTIME="${NEMOCLAW_AGENT_RUNTIME:-openclaw}"
NEMOCLAW_AGENT="${NEMOCLAW_AGENT:-}"
# NEMOCLAW_PROVIDER selects the Nemoclaw onboard/install provider. Required — no default.
# Accepted values: "build" (NVIDIA Endpoints / integrate.api.nvidia.com) or "custom" (OpenAI-compatible endpoint).
NEMOCLAW_PROVIDER="${NEMOCLAW_PROVIDER:?NEMOCLAW_PROVIDER is required}"
# Custom-provider settings — required when NEMOCLAW_PROVIDER=custom (OpenAI-compatible endpoint).
NEMOCLAW_ENDPOINT_URL="${NEMOCLAW_ENDPOINT_URL:-}"
COMPATIBLE_API_KEY="${COMPATIBLE_API_KEY:-}"
# OpenShell provider display name (separate from Nemoclaw's NEMOCLAW_PROVIDER for onboard).
OPENCLAW_PLUGIN_VARIANT="${OPENCLAW_PLUGIN_VARIANT:-nemoclaw}"
OPENSHELL_PROVIDER_NAME="${OPENSHELL_PROVIDER_NAME:-nvidia}"
NEMOCLAW_MODEL="${NEMOCLAW_MODEL:-nvidia/nemotron-3-super-120b-a12b}"
NEMOCLAW_NON_INTERACTIVE=1
NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1
NVIDIA_API_KEY="${NVIDIA_API_KEY:-}"
NVIDIA_BASE_URL="${NVIDIA_BASE_URL:-https://integrate.api.nvidia.com/v1}"
NEMOCLAW_SHIM_DIR="${HOME}/.local/bin"
OPENCLAW_CONFIG_UPDATE_SCRIPT="${OPENCLAW_CONFIG_UPDATE_SCRIPT:-${SCRIPT_DIR}/update_openclaw_config.py}"
NEMOCLAW_POLICY_FILE="${NEMOCLAW_POLICY_FILE:-${VSS_REPO_DIR}/assets/vss_nemoclaw_policy.yaml}"
OPENCLAW_PLUGIN_DIR="${OPENCLAW_PLUGIN_DIR:-${VSS_REPO_DIR}/.openclaw}"
VSS_NAMESPACE="${VSS_NAMESPACE:-openshell}"
VSS_REMOTE_CONFIG_PATH="/sandbox/.openclaw/openclaw.json"
NEMOCLAW_DASHBOARD_PORT="${NEMOCLAW_DASHBOARD_PORT:-18789}"
NEMOCLAW_DASHBOARD_BIND_ADDRESS="${NEMOCLAW_DASHBOARD_BIND_ADDRESS:-0.0.0.0}"
HERMES_WORKSPACE_DIR="${HERMES_WORKSPACE_DIR:-${VSS_REPO_DIR}/.hermes/workspace}"
HERMES_REMOTE_CONTEXT_DIR="${HERMES_REMOTE_CONTEXT_DIR:-/sandbox}"
HERMES_REMOTE_HOME="${HERMES_REMOTE_HOME:-/sandbox/.hermes}"
HERMES_API_PORT="${HERMES_API_PORT:-8642}"
HERMES_MCP_SERVER_NAME="${HERMES_MCP_SERVER_NAME:-vss_orchestrator}"
HERMES_MCP_URL="${HERMES_MCP_URL:-http://host.openshell.internal:9988/mcp}"
HERMES_BAKE_MCP="${HERMES_BAKE_MCP:-1}"
HERMES_FROM_DOCKERFILE="${HERMES_FROM_DOCKERFILE:-${NEMOCLAW_FROM_DOCKERFILE:-}}"
HERMES_BUILD_DIR="${HERMES_BUILD_DIR:-${VSS_REPO_DIR}/.orchestrator-artifacts/nemoclaw-hermes-mcp-build}"
NEMOCLAW_HERMES_DASHBOARD="${NEMOCLAW_HERMES_DASHBOARD:-0}"
NEMOCLAW_HERMES_DASHBOARD_PORT="${NEMOCLAW_HERMES_DASHBOARD_PORT:-9119}"
NEMOCLAW_LOG_PREFIX="${NEMOCLAW_LOG_PREFIX:-init_nemoclaw}"

log() {
  printf '[%s] %s\n' "${NEMOCLAW_LOG_PREFIX:-nemoclaw}" "$*"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

node_major_version() {
  node -e 'process.stdout.write(String(parseInt(process.versions.node, 10)))' 2>/dev/null || printf '0'
}

ensure_nvm_loaded() {
  if have node && [ "$(node_major_version)" -ge 22 ]; then
    return 0
  fi
  if [ -z "${NVM_DIR:-}" ]; then
    export NVM_DIR="$HOME/.nvm"
  fi
  if [ -s "$NVM_DIR/nvm.sh" ]; then
    # shellcheck disable=SC1090
    . "$NVM_DIR/nvm.sh"
    if ! have node || [ "$(node_major_version)" -lt 22 ]; then
      nvm use 22 >/dev/null 2>&1 || nvm use default >/dev/null 2>&1 || nvm use node >/dev/null 2>&1 || true
    fi
    if [ -n "${NVM_BIN:-}" ] && [ -d "${NVM_BIN}" ]; then
      export PATH="${NVM_BIN}:${PATH}"
      hash -r 2>/dev/null || true
    fi
  fi
}

refresh_path() {
  ensure_nvm_loaded

  local npm_bin
  npm_bin="$(npm config get prefix 2>/dev/null)/bin" || true
  if [ -n "${npm_bin:-}" ] && [ -d "$npm_bin" ] && [[ ":$PATH:" != *":$npm_bin:"* ]]; then
    export PATH="$npm_bin:$PATH"
  fi

  if [ -d "${NEMOCLAW_SHIM_DIR}" ] && [[ ":$PATH:" != *":${NEMOCLAW_SHIM_DIR}:"* ]]; then
    export PATH="${NEMOCLAW_SHIM_DIR}:$PATH"
  fi
}

resolve_nemoclaw() {
  refresh_path

  if have nemoclaw; then
    command -v nemoclaw
    return 0
  fi

  local npm_bin candidate
  npm_bin="$(npm config get prefix 2>/dev/null)/bin" || true

  for candidate in \
    "${NEMOCLAW_SHIM_DIR}/nemoclaw" \
    "${npm_bin:-}/nemoclaw"
  do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

resolve_nemohermes() {
  refresh_path

  if have nemohermes; then
    command -v nemohermes
    return 0
  fi

  local npm_bin candidate
  npm_bin="$(npm config get prefix 2>/dev/null)/bin" || true

  for candidate in \
    "${NEMOCLAW_SHIM_DIR}/nemohermes" \
    "${npm_bin:-}/nemohermes"
  do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

validate_nemoclaw_provider_settings() {
  case "${NEMOCLAW_PROVIDER}" in
    build|custom) ;;
    *)
      log "ERROR: NEMOCLAW_PROVIDER must be build or custom."
      exit 1
      ;;
  esac

  if [ "${NEMOCLAW_PROVIDER}" = "custom" ]; then
    if [ -z "${NEMOCLAW_ENDPOINT_URL}" ]; then
      log "ERROR: NEMOCLAW_PROVIDER=custom requires NEMOCLAW_ENDPOINT_URL (or --endpoint-url)."
      exit 1
    fi
    if [ -z "${COMPATIBLE_API_KEY}" ]; then
      log "ERROR: NEMOCLAW_PROVIDER=custom requires COMPATIBLE_API_KEY (or --compatible-api-key)."
      exit 1
    fi
  fi
}

export_nemoclaw_provider_env() {
  export NEMOCLAW_PROVIDER
  export NEMOCLAW_MODEL
  export NEMOCLAW_NON_INTERACTIVE
  export NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE
  export NVIDIA_API_KEY
  if [ -n "${NEMOCLAW_AGENT:-}" ]; then
    export NEMOCLAW_AGENT
  fi
  if [ "${NEMOCLAW_PROVIDER}" = "custom" ]; then
    export NEMOCLAW_ENDPOINT_URL
    export COMPATIBLE_API_KEY
    export OPENAI_API_KEY="${OPENAI_API_KEY:-$COMPATIBLE_API_KEY}"
  fi
}

configure_openshell_provider() {
  if ! have openshell; then
    log "OpenShell not available yet; skipping provider setup for now"
    return
  fi

  local openai_base_url openai_api_key
  case "${NEMOCLAW_PROVIDER}" in
    build)
      openai_base_url="${NVIDIA_BASE_URL}"
      openai_api_key="${NVIDIA_API_KEY}"
      ;;
    custom)
      openai_base_url="${NEMOCLAW_ENDPOINT_URL}"
      openai_api_key="${COMPATIBLE_API_KEY}"
      ;;
    *)
      log "ERROR: NEMOCLAW_PROVIDER=${NEMOCLAW_PROVIDER} is not supported by configure_openshell_provider."
      return 1
      ;;
  esac

  log "Configuring OpenShell provider ${OPENSHELL_PROVIDER_NAME} (NEMOCLAW_PROVIDER=${NEMOCLAW_PROVIDER}, base=${openai_base_url})"
  local action provider_args
  if openshell provider get "$OPENSHELL_PROVIDER_NAME" >/dev/null 2>&1; then
    action="update"
    provider_args=(provider update --credential OPENAI_API_KEY --config "OPENAI_BASE_URL=$openai_base_url" "$OPENSHELL_PROVIDER_NAME")
  else
    action="create"
    provider_args=(provider create --name "$OPENSHELL_PROVIDER_NAME" --type openai --credential OPENAI_API_KEY --config "OPENAI_BASE_URL=$openai_base_url")
  fi
  if ! OPENAI_API_KEY="$openai_api_key" openshell "${provider_args[@]}"; then
    log "Provider ${action} failed; continuing with existing provider config"
  fi

  local inference_args
  inference_args=(inference set --provider "$OPENSHELL_PROVIDER_NAME" --model "$NEMOCLAW_MODEL" --timeout 300)
  if ! openshell "${inference_args[@]}"; then
    log "OpenShell inference endpoint verification failed; retrying with --no-verify"
    openshell "${inference_args[@]}" --no-verify
  fi
  openshell inference get || true
}

run_nemoclaw_install() {
  local label="${1:-NemoClaw installer}"
  local install_script="${NEMOCLAW_REPO_DIR}/install.sh"

  if [ ! -x "$install_script" ]; then
    log "${install_script} is not available"
    exit 1
  fi

  log "Running ${label} (NEMOCLAW_PROVIDER=${NEMOCLAW_PROVIDER})"
  (
    export_nemoclaw_provider_env
    export NEMOCLAW_SANDBOX_NAME
    cd "$NEMOCLAW_REPO_DIR" && ./install.sh --non-interactive
  )
}

sandbox_exists() {
  have openshell && openshell sandbox get "$NEMOCLAW_SANDBOX_NAME" >/dev/null 2>&1
}

strip_ansi() {
  sed -E 's/\x1B\[[0-9;]*[[:alpha:]]//g'
}

sandbox_ready_for_command() {
  local command_name="$1"
  have openshell || return 1
  openshell sandbox list 2>/dev/null \
    | strip_ansi \
    | awk -v name="$NEMOCLAW_SANDBOX_NAME" '$1 == name && $NF == "Ready" { found = 1 } END { exit found ? 0 : 1 }' \
    || return 1
  openshell sandbox exec -n "$NEMOCLAW_SANDBOX_NAME" -- sh -lc "command -v ${command_name} >/dev/null" </dev/null >/dev/null 2>&1
}

wait_for_sandbox_ready_for_command() {
  local command_name="$1"
  local timeout="${2:-300}"
  local deadline=$((SECONDS + timeout))

  if have nemoclaw; then
    log "NemoClaw status before sandbox readiness check"
    nemoclaw status || true
  fi

  log "Waiting for sandbox ${NEMOCLAW_SANDBOX_NAME} to be Ready with ${command_name}"
  while [ "$SECONDS" -lt "$deadline" ]; do
    if sandbox_ready_for_command "$command_name"; then
      log "Sandbox ${NEMOCLAW_SANDBOX_NAME} is Ready"
      return 0
    fi
    sleep 5
  done

  log "ERROR: sandbox ${NEMOCLAW_SANDBOX_NAME} did not become Ready within ${timeout}s"
  openshell sandbox get "$NEMOCLAW_SANDBOX_NAME" || true
  return 1
}

apply_vss_policy() {
  local policy_file="${NEMOCLAW_POLICY_FILE}"

  if ! have nemoclaw; then
    log "ERROR: nemoclaw CLI is not available; cannot apply preset from ${policy_file}"
    return 1
  fi

  if [ ! -f "$policy_file" ]; then
    log "ERROR: Policy file ${policy_file} is not available"
    return 1
  fi

  log "Applying VSS preset ${policy_file} to sandbox ${NEMOCLAW_SANDBOX_NAME}"
  nemoclaw "$NEMOCLAW_SANDBOX_NAME" policy-add --from-file "$policy_file" --yes
}

is_truthy() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

usage() {
  cat <<'EOF'
Usage:
  bash init_nemoclaw.sh [--nvidia-api-key <KEY>] [options]
  NVIDIA_API_KEY=<key> NEMOCLAW_AGENT_RUNTIME=openclaw bash init_nemoclaw.sh [options]
  NVIDIA_API_KEY=<key> NEMOCLAW_AGENT_RUNTIME=hermes bash init_nemoclaw.sh [options]

  When NEMOCLAW_PROVIDER=build, the NVIDIA API key is resolved in this order:
    1. --nvidia-api-key flag (overrides env)
    2. NVIDIA_API_KEY environment variable
    3. Interactive prompt (if neither is set)
  When NEMOCLAW_PROVIDER=custom, NVIDIA_API_KEY is ignored — use --endpoint-url and --compatible-api-key.

Options:
  --nvidia-api-key KEY        NVIDIA API key (required when NEMOCLAW_PROVIDER=build; ignored for "custom")
  --agent-runtime RUNTIME     openclaw or hermes (default: openclaw)
  --sandbox-name NAME         Sandbox name (default: demo)
  --model NAME                NVIDIA model ID (default: nvidia/nemotron-3-super-120b-a12b)
  --nvidia-base-url URL       NVIDIA API base URL (default: https://integrate.api.nvidia.com/v1)
  --endpoint-url URL          OpenAI-compatible endpoint URL (REQUIRED when --provider=custom)
  --compatible-api-key KEY    API key for the OpenAI-compatible endpoint (REQUIRED when --provider=custom)
  --nemoclaw-repo-dir PATH    Path to NemoClaw source checkout (default: $HOME/NemoClaw)
  --openclaw-config-script PATH
                              Path to the OpenClaw config update helper
  --policy-file PATH          Path to the custom sandbox policy file
  --workspace-dir PATH        Hermes workspace/context directory (Hermes runtime only)
  --from-dockerfile PATH      Custom NemoClaw Hermes Dockerfile. If omitted, Hermes
                              setup generates one from $HOME/NemoClaw/agents/hermes/Dockerfile
                              that installs the Python MCP package.
  --help                      Show this help

Environment (non-interactive Nemoclaw / OpenShell):
  NEMOCLAW_AGENT_RUNTIME      openclaw or hermes (default: openclaw)
  NEMOCLAW_PROVIDER           Nemoclaw onboard/install provider (REQUIRED; must be "build" = NVIDIA Endpoints / integrate.api.nvidia.com, or "custom" = OpenAI-compatible)
  NEMOCLAW_ENDPOINT_URL       OpenAI-compatible endpoint URL (REQUIRED when NEMOCLAW_PROVIDER=custom)
  COMPATIBLE_API_KEY          API key for the OpenAI-compatible endpoint (REQUIRED when NEMOCLAW_PROVIDER=custom)
  OPENSHELL_PROVIDER_NAME     Name for openshell OpenAI-compatible provider (default: nvidia)
  OPENCLAW_PLUGIN_DIR         Path to the OpenClaw plugin source to pack and install
                              (default: <VSS_REPO_DIR>/.openclaw)
  NEMOCLAW_DASHBOARD_PORT     OpenClaw dashboard forward port (default: 18789)
  NEMOCLAW_DASHBOARD_BIND_ADDRESS
                              OpenClaw dashboard forward bind address (default: 0.0.0.0)
  HERMES_WORKSPACE_DIR        Path to Hermes workspace/context files (default: <VSS_REPO_DIR>/.hermes/workspace)
  HERMES_MCP_URL              VSS Orchestrator MCP URL from the sandbox
                              (default: http://host.openshell.internal:9988/mcp)
  HERMES_BAKE_MCP             Set to 0 to skip generated --from Dockerfile creation.
EOF
}

parse_args() {
  local positional=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --nvidia-api-key)
        NVIDIA_API_KEY="$2"
        shift 2
        ;;
      --agent-runtime)
        NEMOCLAW_AGENT_RUNTIME="$2"
        shift 2
        ;;
      --sandbox-name)
        NEMOCLAW_SANDBOX_NAME="$2"
        shift 2
        ;;
      --model)
        NEMOCLAW_MODEL="$2"
        shift 2
        ;;
      --nvidia-base-url)
        NVIDIA_BASE_URL="$2"
        shift 2
        ;;
      --endpoint-url)
        NEMOCLAW_ENDPOINT_URL="$2"
        shift 2
        ;;
      --compatible-api-key)
        COMPATIBLE_API_KEY="$2"
        shift 2
        ;;
      --nemoclaw-repo-dir)
        NEMOCLAW_REPO_DIR="$2"
        shift 2
        ;;
      --openclaw-config-script)
        OPENCLAW_CONFIG_UPDATE_SCRIPT="$2"
        shift 2
        ;;
      --policy-file)
        NEMOCLAW_POLICY_FILE="$2"
        shift 2
        ;;
      --workspace-dir)
        HERMES_WORKSPACE_DIR="$2"
        shift 2
        ;;
      --from-dockerfile)
        HERMES_FROM_DOCKERFILE="$2"
        shift 2
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      --*)
        log "Unknown option: $1"
        usage
        exit 1
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  if [ "${#positional[@]}" -ge 1 ]; then
    NEMOCLAW_SANDBOX_NAME="${positional[0]}"
  fi
  if [ "${#positional[@]}" -gt 1 ]; then
    log "Too many positional arguments"
    usage
    exit 1
  fi

  # NVIDIA_API_KEY is only required for the "build" provider (NVIDIA Endpoints).
  # In "custom" mode the OpenAI-compatible endpoint uses COMPATIBLE_API_KEY instead,
  # which is validated separately in validate_custom_provider_settings().
  if [ "${NEMOCLAW_PROVIDER}" = "build" ] && [ -z "${NVIDIA_API_KEY:-}" ]; then
    read -rsp "Enter your NVIDIA API key: " NVIDIA_API_KEY
    printf '\n'
    if [ -z "${NVIDIA_API_KEY:-}" ]; then
      log "ERROR: NVIDIA API key is required when NEMOCLAW_PROVIDER=build."
      exit 1
    fi
  fi
}

normalize_agent_runtime() {
  NEMOCLAW_AGENT_RUNTIME="$(printf '%s' "${NEMOCLAW_AGENT_RUNTIME}" | tr '[:upper:]' '[:lower:]')"
  case "$NEMOCLAW_AGENT_RUNTIME" in
    nemoclaw|openclaw)
      NEMOCLAW_AGENT_RUNTIME="openclaw"
      NEMOCLAW_AGENT="${NEMOCLAW_AGENT:-}"
      ;;
    nemohermes|hermes)
      NEMOCLAW_AGENT_RUNTIME="hermes"
      NEMOCLAW_AGENT="hermes"
      ;;
    *)
      log "ERROR: NEMOCLAW_AGENT_RUNTIME must be openclaw or hermes."
      exit 1
      ;;
  esac
}

validate_runtime_settings() {
  normalize_agent_runtime
  validate_nemoclaw_provider_settings

  if [ ! -d "${VSS_REPO_DIR}/skills" ]; then
    log "ERROR: ${VSS_REPO_DIR}/skills is missing."
    exit 1
  fi

  if [ "$NEMOCLAW_AGENT_RUNTIME" = "openclaw" ] && [ ! -f "$OPENCLAW_CONFIG_UPDATE_SCRIPT" ]; then
    log "ERROR: OpenClaw config update script ${OPENCLAW_CONFIG_UPDATE_SCRIPT} is not available"
    exit 1
  fi
}

# `nemoclaw onboard` creates the dashboard port-forward (default 18789) that exposes the in-pod
# openclaw-gateway (and its /hooks endpoint) to the host. When the sandbox already exists we skip
# onboard, and the forward can also die independently between runs — so refresh it unconditionally.
forward_running_for_sandbox() {
  local port="$1"
  local sandbox_name="$2"
  local bind_address="${NEMOCLAW_DASHBOARD_BIND_ADDRESS:-0.0.0.0}"
  openshell forward list 2>/dev/null \
    | strip_ansi \
    | awk -v name="$sandbox_name" -v bind="$bind_address" -v port="$port" \
        '$1 == name && $2 == bind && $3 == port && tolower($NF) == "running" { found = 1 } END { exit found ? 0 : 1 }'
}

forward_running_for_sandbox_any_bind() {
  local port="$1"
  local sandbox_name="$2"
  openshell forward list 2>/dev/null \
    | strip_ansi \
    | awk -v name="$sandbox_name" -v port="$port" \
        '$1 == name && $3 == port && tolower($NF) == "running" { found = 1 } END { exit found ? 0 : 1 }'
}

forward_process_running_for_sandbox() {
  local port="$1"
  local sandbox_name="$2"
  local bind_address="${NEMOCLAW_DASHBOARD_BIND_ADDRESS:-0.0.0.0}"
  local args
  while IFS= read -r args; do
    case "$args" in
      *"openshell forward start ${bind_address}:${port} ${sandbox_name}"*|*"openshell forward start --background ${bind_address}:${port} ${sandbox_name}"*)
        return 0
        ;;
    esac
  done < <(ps -eo args= 2>/dev/null || true)
  return 1
}

forward_owned_by_sandbox() {
  local port="$1"
  local sandbox_name="$2"
  forward_running_for_sandbox "$port" "$sandbox_name" || forward_process_running_for_sandbox "$port" "$sandbox_name"
}

dashboard_forward_healthy() {
  local port="$1"
  have curl && curl -fsS "http://127.0.0.1:${port}/health" 2>/dev/null \
    | grep -q '"ok"[[:space:]]*:[[:space:]]*true'
}

ensure_dashboard_forward() {
  local port="${NEMOCLAW_DASHBOARD_PORT}"
  local bind_address="${NEMOCLAW_DASHBOARD_BIND_ADDRESS}"
  local forward_port="${bind_address}:${port}"
  local forward_log="/tmp/nemoclaw-forward-${port}.log"
  if ! have openshell; then
    log "ERROR: OpenShell not available; cannot refresh dashboard port-forward"
    return 1
  fi
  log "Refreshing dashboard port-forward on ${forward_port} for sandbox ${NEMOCLAW_SANDBOX_NAME}"
  if dashboard_forward_healthy "$port"; then
    sleep 2
    if dashboard_forward_healthy "$port" && forward_owned_by_sandbox "$port" "$NEMOCLAW_SANDBOX_NAME"; then
      log "Dashboard port-forward on ${forward_port} is already healthy; keeping existing listener"
      return
    fi
    if forward_running_for_sandbox_any_bind "$port" "$NEMOCLAW_SANDBOX_NAME"; then
      log "Dashboard forward is healthy but not bound to ${bind_address}; restarting scoped OpenShell forward"
    fi
    log "Existing listener on ${port} is not the expected forward for sandbox ${NEMOCLAW_SANDBOX_NAME}; restarting scoped OpenShell forward"
  fi

  openshell forward stop "$port" "$NEMOCLAW_SANDBOX_NAME" >/dev/null 2>&1 || true
  pkill -TERM -f "[o]penshell forward start .*${port} ${NEMOCLAW_SANDBOX_NAME}" >/dev/null 2>&1 || true

  if have setsid; then
    setsid -f openshell forward start "$forward_port" "$NEMOCLAW_SANDBOX_NAME" </dev/null >"$forward_log" 2>&1 || true
  else
    openshell forward start --background "$forward_port" "$NEMOCLAW_SANDBOX_NAME" </dev/null >"$forward_log" 2>&1 || true
  fi

  for _attempt in $(seq 1 30); do
    if forward_owned_by_sandbox "$port" "$NEMOCLAW_SANDBOX_NAME" && dashboard_forward_healthy "$port"; then
      log "Dashboard port-forward on ${forward_port} is healthy for sandbox ${NEMOCLAW_SANDBOX_NAME}"
      return
    fi
    sleep 1
  done

  log "ERROR: could not (re)start dashboard forward on ${forward_port}; the OpenClaw UI and /hooks endpoint are unreachable at http://127.0.0.1:${port}"
  if [ -f "$forward_log" ]; then
    tail -n 20 "$forward_log" | sed 's/^/[init_nemoclaw] forward log: /' >&2 || true
  fi
  return 1
}

update_openclaw_allowed_origin() {
  local script="${OPENCLAW_CONFIG_UPDATE_SCRIPT}"

  if [ ! -f "$script" ]; then
    log "ERROR: OpenClaw config update script ${script} is not available"
    return 1
  fi

  if ! have python3; then
    log "ERROR: python3 is not available; cannot run OpenClaw config update script ${script}"
    return 1
  fi

  log "Updating OpenClaw config for sandbox ${NEMOCLAW_SANDBOX_NAME} using script ${script}"
  if ! python3 "$script" "$NEMOCLAW_SANDBOX_NAME" --config-path "$VSS_REMOTE_CONFIG_PATH"; then
    log "ERROR: OpenClaw config update failed for sandbox ${NEMOCLAW_SANDBOX_NAME}"
    return 1
  fi
}

resolve_vss_gateway_container() {
  if [ -n "${VSS_CONTAINER_NAME:-}" ]; then
    printf '%s\n' "${VSS_CONTAINER_NAME}"
    return 0
  fi

  # Match either the legacy kubectl-driver gateway (openshell-cluster-*) or the
  # newer Docker-driver gateway (nemoclaw-openshell-*) emitted by NemoClaw >= v0.0.40.
  docker ps --format '{{.Names}}' | awk '/^(openshell-cluster-|nemoclaw-openshell-)/{print; exit}'
}

restart_vss_openclaw_gateway() {
  local port attempt
  port="${NEMOCLAW_DASHBOARD_PORT:-18789}"

  if ! have openshell; then
    log "OpenShell is not available; cannot restart OpenClaw gateway"
    return 1
  fi

  log "Restarting OpenClaw gateway in sandbox ${NEMOCLAW_SANDBOX_NAME}"
  openshell sandbox exec -n "${NEMOCLAW_SANDBOX_NAME}" -- sh -lc \
    "pkill -TERM -f '[o]penclaw-gateway' || true" </dev/null || true

  for attempt in $(seq 1 30); do
    if openshell sandbox exec -n "${NEMOCLAW_SANDBOX_NAME}" -- sh -lc \
        "curl -fsS http://127.0.0.1:${port}/health >/dev/null" </dev/null; then
      log "OpenClaw gateway is healthy after restart"
      return 0
    fi
    sleep 1
  done

  log "WARN: OpenClaw gateway did not become healthy within 30 seconds after restart"
  return 1
}

install_vss_openclaw_plugin() {
  local plugin_dir tgz_name tgz_path container_name remote_tgz install_cmd shell_cmd
  plugin_dir="${OPENCLAW_PLUGIN_DIR}"

  if [ ! -f "${plugin_dir}/package.json" ]; then
    log "${plugin_dir} is not a packable OpenClaw plugin; skipping plugin install"
    return
  fi

  if ! have npm; then
    log "npm is not available; cannot pack VSS OpenClaw plugin"
    return 1
  fi

  if ! have openshell; then
    log "OpenShell is not available; skipping VSS plugin install"
    return
  fi

  if ! openshell sandbox list >/dev/null 2>&1; then
    log "OpenShell sandbox access is not ready; skipping VSS plugin install"
    return
  fi

  container_name="$(resolve_vss_gateway_container)"
  if [ -z "${container_name}" ]; then
    log "Could not determine the OpenShell gateway container; skipping VSS plugin install"
    return
  fi

  if [ ! -d "${VSS_REPO_DIR}/skills" ]; then
    log "ERROR: ${VSS_REPO_DIR}/skills is missing; prepack (cp -r ../skills skills) will fail. Cannot pack VSS OpenClaw plugin."
    return 1
  fi

  log "Packing VSS OpenClaw plugin in ${plugin_dir}"
  tgz_name="$(cd "${plugin_dir}" && npm pack | tail -n1)"
  if [ -z "${tgz_name}" ] || [ ! -f "${plugin_dir}/${tgz_name}" ]; then
    log "ERROR: npm pack did not produce a tarball in ${plugin_dir}"
    return 1
  fi
  tgz_path="${plugin_dir}/${tgz_name}"
  remote_tgz="/tmp/${tgz_name}"
  # Clean up the local tarball on every return path (success, upload failure, install failure).
  trap 'rm -f "${tgz_path}"; trap - RETURN' RETURN

  # --dangerously-force-unsafe-install: the plugin extension uses child_process (npx skills add agent-browser,
  # systemctl daemon-reload), which OpenClaw's install-time scanner flags. We trust this first-party plugin.
  # printf %q shell-escapes both interpolated values so a quote in tgz_name or
  # OPENCLAW_PLUGIN_VARIANT can't break out of the remote shell command.
  printf -v install_cmd 'OPENCLAW_PLUGIN_VARIANT=%q openclaw plugins install %q --force --dangerously-force-unsafe-install' \
    "${OPENCLAW_PLUGIN_VARIANT}" "${remote_tgz}"
  log "Installing VSS OpenClaw plugin ${tgz_name} into sandbox ${NEMOCLAW_SANDBOX_NAME} (variant=${OPENCLAW_PLUGIN_VARIANT})"
  log "Plugin install command: ${install_cmd}"

  if [[ "${container_name}" == nemoclaw-openshell-* ]]; then
    log "Streaming ${tgz_name} into sandbox ${NEMOCLAW_SANDBOX_NAME}:${remote_tgz}"
    printf -v shell_cmd 'cat > %q' "${remote_tgz}"
    if ! openshell sandbox exec -n "${NEMOCLAW_SANDBOX_NAME}" -- sh -c "${shell_cmd}" < "${tgz_path}"; then
      log "ERROR: failed to stream ${tgz_name} into sandbox ${NEMOCLAW_SANDBOX_NAME}"
      return 1
    fi

    printf -v shell_cmd '%s && rm -f %q' "${install_cmd}" "${remote_tgz}"
    if ! openshell sandbox exec -n "${NEMOCLAW_SANDBOX_NAME}" -- sh -lc "${shell_cmd}" </dev/null; then
      log "ERROR: openclaw plugins install failed for ${tgz_name}"
      return 1
    fi
  else
    log "Streaming ${tgz_name} into sandbox ${NEMOCLAW_SANDBOX_NAME}:${remote_tgz}"
    if ! sudo docker exec -i "${container_name}" kubectl exec -i -n "${VSS_NAMESPACE}" "${NEMOCLAW_SANDBOX_NAME}" -- \
        sh -c "cat > '${remote_tgz}'" < "${tgz_path}"; then
      log "ERROR: failed to stream ${tgz_name} into sandbox ${NEMOCLAW_SANDBOX_NAME}"
      return 1
    fi

    if ! sudo docker exec "${container_name}" kubectl exec -n "${VSS_NAMESPACE}" "${NEMOCLAW_SANDBOX_NAME}" -- \
        sh -lc "$(printf 'su - sandbox -c %q && rm -f %q' "${install_cmd}" "${remote_tgz}")"; then
      log "ERROR: openclaw plugins install failed for ${tgz_name}"
      return 1
    fi
  fi

  log "VSS OpenClaw plugin installed"
  restart_vss_openclaw_gateway || return 1
  ensure_dashboard_forward || return 1
}

prepare_hermes_mcp_dockerfile() {
  if ! is_truthy "$HERMES_BAKE_MCP"; then
    log "HERMES_BAKE_MCP is disabled; using the stock Hermes sandbox image"
    return
  fi

  if [ -n "${HERMES_FROM_DOCKERFILE}" ]; then
    if [ ! -f "$HERMES_FROM_DOCKERFILE" ]; then
      log "ERROR: HERMES_FROM_DOCKERFILE does not exist: ${HERMES_FROM_DOCKERFILE}"
      exit 1
    fi
    export NEMOCLAW_FROM_DOCKERFILE="$HERMES_FROM_DOCKERFILE"
    log "Using custom Hermes Dockerfile: ${NEMOCLAW_FROM_DOCKERFILE}"
    return
  fi

  local source_dockerfile="${NEMOCLAW_REPO_DIR}/agents/hermes/Dockerfile"
  local generated_dockerfile="${HERMES_BUILD_DIR}/Dockerfile"

  if [ ! -f "$source_dockerfile" ]; then
    log "ERROR: Cannot generate a Hermes MCP Dockerfile because ${source_dockerfile} is missing."
    log "Set HERMES_FROM_DOCKERFILE to a custom NemoClaw Hermes Dockerfile, or set HERMES_BAKE_MCP=0 only if the base image already includes the Python mcp package."
    exit 1
  fi

  mkdir -p "$HERMES_BUILD_DIR"
  cp "$source_dockerfile" "$generated_dockerfile"
  cat >> "$generated_dockerfile" <<'EOF'

# VSS Hermes: native MCP client support.
# This follows the documented Hermes custom-image path for runtime dependencies.
USER root
RUN /opt/hermes/.venv/bin/python -m pip install --no-cache-dir mcp
USER sandbox
WORKDIR /sandbox
EOF

  HERMES_FROM_DOCKERFILE="$generated_dockerfile"
  export NEMOCLAW_FROM_DOCKERFILE="$generated_dockerfile"
  log "Generated Hermes MCP Dockerfile: ${generated_dockerfile}"
}

configure_ngc_credential_provider() {
  if ! have openshell; then
    log "OpenShell not available yet; skipping NGC credential provider setup"
    return
  fi

  local ngc_api_key="${NGC_CLI_API_KEY:-}"
  if [ -z "$ngc_api_key" ]; then
    log "NGC_CLI_API_KEY not set in operator env; skipping NGC credential provider setup. Sandbox-side ngc calls will fail until this is exported and init re-run."
    return
  fi

  local action provider_args
  if openshell provider get ngc >/dev/null 2>&1; then
    action="update"
    provider_args=(provider update --credential NGC_CLI_API_KEY ngc)
  else
    action="create"
    provider_args=(provider create --name ngc --type generic --credential NGC_CLI_API_KEY)
  fi
  log "Configuring NGC credential provider (action=${action})"
  if ! NGC_CLI_API_KEY="$ngc_api_key" openshell "${provider_args[@]}"; then
    log "NGC provider ${action} failed; sandbox-side ngc calls will be missing NGC_CLI_API_KEY"
  fi
}

configure_ngc_cli_in_hermes_sandbox() {
  if ! have nemoclaw; then
    log "nemoclaw not available; skipping in-sandbox NGC CLI install"
    return
  fi

  log "Installing NGC CLI inside sandbox ${NEMOCLAW_SANDBOX_NAME} (pip3 install --user ngcsdk)"
  if ! nemoclaw sandbox exec "$NEMOCLAW_SANDBOX_NAME" --no-tty -- bash -s <<'SH'
set -e
if command -v ngc >/dev/null 2>&1 && ngc --version >/dev/null 2>&1; then
  echo "ngc already installed: $(ngc --version 2>&1 | head -1)"
  exit 0
fi
python3 -m pip install --user --quiet --break-system-packages ngcsdk 2>/dev/null \
  || python3 -m pip install --user --quiet ngcsdk
if [ ! -e /usr/local/bin/ngc ] && [ -e "$HOME/.local/bin/ngc" ]; then
  sudo install -m 0755 "$HOME/.local/bin/ngc" /usr/local/bin/ngc 2>/dev/null \
    || cp "$HOME/.local/bin/ngc" /usr/local/bin/ngc 2>/dev/null \
    || true
fi
/usr/local/bin/ngc --version 2>/dev/null \
  || "$HOME/.local/bin/ngc" --version
SH
  then
    log "In-sandbox NGC CLI install failed; ngc registry calls inside the sandbox will not work"
  fi
}

verify_hermes_mcp_support() {
  if ! have openshell; then
    log "OpenShell is not available; cannot verify Hermes MCP Python support"
    return 1
  fi

  log "Verifying Hermes Python MCP support in sandbox ${NEMOCLAW_SANDBOX_NAME}"
  if ! openshell sandbox exec -n "$NEMOCLAW_SANDBOX_NAME" -- \
    /opt/hermes/.venv/bin/python -c 'import importlib.util; raise SystemExit(0 if importlib.util.find_spec("mcp") else 1)' \
    </dev/null; then
    log "ERROR: Hermes Python package 'mcp' is not installed in /opt/hermes/.venv."
    log "Recreate or rebuild the Hermes sandbox with HERMES_BAKE_MCP=1, or provide HERMES_FROM_DOCKERFILE that installs mcp."
    return 1
  fi
}

install_vss_hermes_skills() {
  local skill_cli skill_dir skill_name

  if skill_cli="$(resolve_nemohermes)"; then
    :
  elif skill_cli="$(resolve_nemoclaw)"; then
    :
  else
    log "ERROR: neither nemohermes nor nemoclaw is available; cannot install VSS skills"
    return 1
  fi

  log "Installing VSS skills into Hermes sandbox ${NEMOCLAW_SANDBOX_NAME}"
  for skill_dir in "${VSS_REPO_DIR}"/skills/*; do
    [ -d "$skill_dir" ] || continue
    [ -f "${skill_dir}/SKILL.md" ] || continue
    skill_name="$(basename "$skill_dir")"
    log "Installing skill ${skill_name}"
    "$skill_cli" "$NEMOCLAW_SANDBOX_NAME" skill install "$skill_dir"
  done
}

upload_hermes_context_files() {
  local local_file remote_file file_name shell_cmd

  if [ ! -d "$HERMES_WORKSPACE_DIR" ]; then
    log "Hermes context directory ${HERMES_WORKSPACE_DIR} is missing; skipping"
    return
  fi

  if ! have openshell; then
    log "OpenShell is not available; cannot upload Hermes workspace templates"
    return 1
  fi

  log "Uploading Hermes context files from ${HERMES_WORKSPACE_DIR}"
  openshell sandbox exec -n "$NEMOCLAW_SANDBOX_NAME" -- sh -lc \
    "mkdir -p '$HERMES_REMOTE_CONTEXT_DIR/memory' '$HERMES_REMOTE_HOME'" </dev/null

  for local_file in "$HERMES_WORKSPACE_DIR"/*.md; do
    [ -f "$local_file" ] || continue

    file_name="$(basename "$local_file")"
    if [ "$file_name" = "SOUL.md" ]; then
      remote_file="${HERMES_REMOTE_HOME}/SOUL.md"
    else
      remote_file="${HERMES_REMOTE_CONTEXT_DIR}/${file_name}"
    fi

    printf -v shell_cmd 'cat > %q' "$remote_file"
    if ! openshell sandbox exec -n "$NEMOCLAW_SANDBOX_NAME" -- sh -c "$shell_cmd" < "$local_file"; then
      log "ERROR: failed to upload ${file_name} to ${remote_file}"
      return 1
    fi
  done
}

configure_hermes_mcp_server() {
  if ! have openshell; then
    log "OpenShell is not available; cannot configure Hermes MCP server"
    return 1
  fi

  log "Configuring Hermes MCP server ${HERMES_MCP_SERVER_NAME} -> ${HERMES_MCP_URL}"
  openshell sandbox exec -n "$NEMOCLAW_SANDBOX_NAME" -- \
    env "VSS_ORCHESTRATOR_MCP_NAME=${HERMES_MCP_SERVER_NAME}" \
      "VSS_ORCHESTRATOR_MCP_URL=${HERMES_MCP_URL}" \
      sh -s <<'SH'
set -e
if ! command -v hermes >/dev/null 2>&1; then
  echo "hermes CLI is required to configure MCP servers" >&2
  exit 1
fi

CONFIG_FILE="${HERMES_CONFIG_FILE:-/sandbox/.hermes/config.yaml}"
mkdir -p "$(dirname "$CONFIG_FILE")"
touch "$CONFIG_FILE"

python3 - "$CONFIG_FILE" "$VSS_ORCHESTRATOR_MCP_NAME" "$VSS_ORCHESTRATOR_MCP_URL" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
name = sys.argv[2]
url = sys.argv[3]
text = path.read_text()

lines = text.splitlines()
out = []
i = 0
while i < len(lines):
    line = lines[i]
    if line.strip() == "mcp_servers:" and not line.startswith((" ", "\t")):
        out.append(line)
        i += 1
        while i < len(lines):
            current = lines[i]
            if current and not current.startswith((" ", "\t")):
                break
            if current.startswith(f"  {name}:"):
                i += 1
                while i < len(lines):
                    nested = lines[i]
                    if nested.startswith("  ") and not nested.startswith("    "):
                        break
                    if nested and not nested.startswith((" ", "\t")):
                        break
                    i += 1
                continue
            out.append(current)
            i += 1
        out.extend([f"  {name}:", f'    url: "{url}"'])
        continue
    out.append(line)
    i += 1

if not any(line.strip() == "mcp_servers:" and not line.startswith((" ", "\t")) for line in out):
    if out and out[-1].strip():
        out.append("")
    out.extend(["mcp_servers:", f"  {name}:", f'    url: "{url}"'])

path.write_text("\n".join(out).rstrip() + "\n")
print(f"Registered MCP server {name} -> {url} in {path}")
PY
SH
}

hermes_api_healthy() {
  have curl && curl -fsS "http://127.0.0.1:${HERMES_API_PORT}/health" >/dev/null 2>&1
}

wait_for_hermes_api() {
  local timeout deadline
  timeout="${1:-${HERMES_API_READY_TIMEOUT:-120}}"
  deadline=$((SECONDS + timeout))

  log "Waiting for Hermes API on http://127.0.0.1:${HERMES_API_PORT}/health"
  while [ "$SECONDS" -lt "$deadline" ]; do
    if hermes_api_healthy; then
      log "Hermes API is healthy"
      return 0
    fi
    sleep 3
  done

  log "WARN: Hermes API did not become healthy within ${timeout}s"
  return 0
}

run_openclaw_onboard() {
  local nemoclaw_cmd
  nemoclaw_cmd="$(resolve_nemoclaw)" || {
    log "nemoclaw is not currently resolvable"
    exit 1
  }

  log "Running nemoclaw onboard (NEMOCLAW_PROVIDER=${NEMOCLAW_PROVIDER})"
  export_nemoclaw_provider_env
  "$nemoclaw_cmd" onboard --non-interactive
}

run_openclaw_install() {
  run_nemoclaw_install "NemoClaw installer"
}

wait_for_openclaw_sandbox_ready() {
  wait_for_sandbox_ready_for_command openclaw "${1:-${NEMOCLAW_SANDBOX_READY_TIMEOUT:-300}}"
}

run_hermes_onboard() {
  local nemohermes_cmd nemoclaw_cmd

  export_nemoclaw_provider_env
  export NEMOCLAW_HERMES_DASHBOARD
  export NEMOCLAW_HERMES_DASHBOARD_PORT
  prepare_hermes_mcp_dockerfile

  if nemohermes_cmd="$(resolve_nemohermes)"; then
    log "Running nemohermes onboard (NEMOCLAW_PROVIDER=${NEMOCLAW_PROVIDER})"
    if [ -n "${NEMOCLAW_FROM_DOCKERFILE:-}" ]; then
      "$nemohermes_cmd" onboard --name "$NEMOCLAW_SANDBOX_NAME" --from "$NEMOCLAW_FROM_DOCKERFILE" --non-interactive
    else
      "$nemohermes_cmd" onboard --non-interactive
    fi
    return
  fi

  if [ -n "${NEMOCLAW_FROM_DOCKERFILE:-}" ]; then
    log "ERROR: nemohermes CLI is required for custom --from Dockerfile onboarding."
    exit 1
  fi

  nemoclaw_cmd="$(resolve_nemoclaw)" || {
    log "neither nemohermes nor nemoclaw is currently resolvable"
    exit 1
  }

  log "Running nemoclaw onboard --agent hermes (NEMOCLAW_PROVIDER=${NEMOCLAW_PROVIDER})"
  "$nemoclaw_cmd" onboard --agent hermes --non-interactive
}

run_hermes_install() {
  export NEMOCLAW_HERMES_DASHBOARD
  export NEMOCLAW_HERMES_DASHBOARD_PORT
  prepare_hermes_mcp_dockerfile
  run_nemoclaw_install "NemoClaw installer for Hermes"
}

wait_for_hermes_sandbox_ready() {
  wait_for_sandbox_ready_for_command hermes "${1:-${HERMES_SANDBOX_READY_TIMEOUT:-300}}"
}

main_openclaw() {
  # Non-interactive shells often skip .bashrc; load nvm/node before nemoclaw (env node shebang).
  refresh_path

  if sandbox_exists; then
    log "Sandbox ${NEMOCLAW_SANDBOX_NAME} already exists; skipping NemoClaw onboard/install"
    configure_openshell_provider
  else
    log "Start installing/onboarding NemoClaw"
    if have nemoclaw; then
      run_openclaw_onboard
    else
      run_openclaw_install
    fi
    log "Finished installing/onboarding NemoClaw"
  fi

  # Onboard can return before OpenClaw is executable inside the sandbox.
  wait_for_openclaw_sandbox_ready
  refresh_path
  ensure_dashboard_forward
  apply_vss_policy
  update_openclaw_allowed_origin
  # Policy/config updates can briefly flap gateway readiness before plugin install.
  wait_for_openclaw_sandbox_ready "${NEMOCLAW_POST_CONFIG_READY_TIMEOUT:-60}"
  install_vss_openclaw_plugin

  log "To use nemoclaw in your current shell, run:"
  printf '\n  . "%s/nvm.sh"\n\n' "${NVM_DIR:-$HOME/.nvm}"
}

main_hermes() {
  refresh_path

  if sandbox_exists; then
    log "Sandbox ${NEMOCLAW_SANDBOX_NAME} already exists; skipping NemoClaw onboard/install"
    configure_openshell_provider
  else
    log "Start installing/onboarding NemoClaw Hermes"
    if have nemoclaw; then
      run_hermes_onboard
    else
      run_hermes_install
    fi
    log "Finished installing/onboarding NemoClaw Hermes"
  fi

  wait_for_hermes_sandbox_ready
  refresh_path
  configure_ngc_credential_provider
  apply_vss_policy
  verify_hermes_mcp_support
  install_vss_hermes_skills
  upload_hermes_context_files
  configure_hermes_mcp_server
  configure_ngc_cli_in_hermes_sandbox
  wait_for_hermes_api

  log "NemoClaw Hermes VSS setup complete."
  log "To connect, run: nemohermes ${NEMOCLAW_SANDBOX_NAME} connect"
  log "Hermes API: http://127.0.0.1:${HERMES_API_PORT}/v1"
  log "VSS Orchestrator MCP: ${HERMES_MCP_URL}"
  log "Start the host MCP server before connecting to Hermes; reconnect for native MCP discovery."
  if is_truthy "${NEMOCLAW_HERMES_DASHBOARD}"; then
    log "Hermes dashboard: http://127.0.0.1:${NEMOCLAW_HERMES_DASHBOARD_PORT}/"
  fi
}

main() {
  if [ "$NEMOCLAW_AGENT_RUNTIME" = "hermes" ]; then
    main_hermes
  else
    main_openclaw
  fi
}

parse_args "$@"
validate_runtime_settings
export NEMOCLAW_SANDBOX_NAME NEMOCLAW_AGENT_RUNTIME NEMOCLAW_AGENT NEMOCLAW_PROVIDER OPENSHELL_PROVIDER_NAME NEMOCLAW_MODEL
export NEMOCLAW_NON_INTERACTIVE NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE
export NEMOCLAW_ENDPOINT_URL COMPATIBLE_API_KEY
export NEMOCLAW_REPO_DIR OPENCLAW_CONFIG_UPDATE_SCRIPT NEMOCLAW_POLICY_FILE
export NEMOCLAW_DASHBOARD_PORT NEMOCLAW_DASHBOARD_BIND_ADDRESS
export HERMES_WORKSPACE_DIR HERMES_REMOTE_CONTEXT_DIR HERMES_REMOTE_HOME HERMES_API_PORT
export HERMES_MCP_SERVER_NAME HERMES_MCP_URL HERMES_BAKE_MCP HERMES_FROM_DOCKERFILE HERMES_BUILD_DIR
export NEMOCLAW_HERMES_DASHBOARD NEMOCLAW_HERMES_DASHBOARD_PORT

main
