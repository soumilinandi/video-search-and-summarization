#!/usr/bin/env bash
# Bootstraps a NemoClaw/OpenShell sandbox with the Hermes agent and VSS skills.
# This is the managed/sandboxed Hermes path. Standalone Hermes users should use
# Hermes `skills.external_dirs`; OpenClaw migration is optional for old user data.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
VSS_REPO_DIR="${VSS_REPO_DIR:-$(cd "${SCRIPT_DIR}/../../../.." && pwd)}"
NEMOCLAW_REPO_DIR="${NEMOCLAW_REPO_DIR:-${HOME}/NemoClaw}"
NEMOCLAW_SANDBOX_NAME="${NEMOCLAW_SANDBOX_NAME:-vss-hermes}"
NEMOCLAW_AGENT="${NEMOCLAW_AGENT:-hermes}"
NEMOCLAW_PROVIDER="${NEMOCLAW_PROVIDER:-}"
NEMOCLAW_ENDPOINT_URL="${NEMOCLAW_ENDPOINT_URL:-}"
COMPATIBLE_API_KEY="${COMPATIBLE_API_KEY:-}"
OPENSHELL_PROVIDER_NAME="${OPENSHELL_PROVIDER_NAME:-nvidia}"
NEMOCLAW_MODEL="${NEMOCLAW_MODEL:-nvidia/nemotron-3-super-120b-a12b}"
NEMOCLAW_NON_INTERACTIVE=1
NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1
NVIDIA_API_KEY="${NVIDIA_API_KEY:-}"
NVIDIA_BASE_URL="${NVIDIA_BASE_URL:-https://integrate.api.nvidia.com/v1}"
NEMOCLAW_SHIM_DIR="${HOME}/.local/bin"
NEMOCLAW_POLICY_FILE="${NEMOCLAW_POLICY_FILE:-${VSS_REPO_DIR}/assets/vss_nemoclaw_policy.yaml}"
NEMOHERMES_WORKSPACE_DIR="${NEMOHERMES_WORKSPACE_DIR:-${VSS_REPO_DIR}/.hermes/workspace}"
NEMOHERMES_REMOTE_WORKSPACE="${NEMOHERMES_REMOTE_WORKSPACE:-/sandbox/.hermes-data/workspace}"
NEMOHERMES_API_PORT="${NEMOHERMES_API_PORT:-8642}"
NEMOHERMES_MCP_SERVER_NAME="${NEMOHERMES_MCP_SERVER_NAME:-vss_orchestrator}"
NEMOHERMES_MCP_URL="${NEMOHERMES_MCP_URL:-http://host.openshell.internal:9988/mcp}"
NEMOCLAW_HERMES_DASHBOARD="${NEMOCLAW_HERMES_DASHBOARD:-0}"
NEMOCLAW_HERMES_DASHBOARD_PORT="${NEMOCLAW_HERMES_DASHBOARD_PORT:-9119}"

log() {
  printf '[init_nemohermes] %s\n' "$*"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

is_truthy() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

node_major_version() {
  node -e 'process.stdout.write(String(parseInt(process.versions.node, 10)))' 2>/dev/null || printf '0'
}

usage() {
  cat <<'EOF'
Usage:
  bash init_nemohermes.sh [--nvidia-api-key <KEY>] [options]
  NVIDIA_API_KEY=<key> NEMOCLAW_PROVIDER=build bash init_nemohermes.sh [options]

Options:
  --nvidia-api-key KEY        NVIDIA API key (required when NEMOCLAW_PROVIDER=build)
  --sandbox-name NAME         Sandbox name (default: vss-hermes)
  --model NAME                NemoClaw/Hermes inference model
  --nvidia-base-url URL       NVIDIA API base URL (default: https://integrate.api.nvidia.com/v1)
  --endpoint-url URL          OpenAI-compatible endpoint URL (required when NEMOCLAW_PROVIDER=custom)
  --compatible-api-key KEY    API key for the OpenAI-compatible endpoint
  --nemoclaw-repo-dir PATH    Path to NemoClaw source checkout (default: $HOME/NemoClaw)
  --policy-file PATH          Path to the VSS sandbox policy file
  --workspace-dir PATH        Local Hermes workspace template directory
  --help                      Show this help

Environment:
  NEMOCLAW_PROVIDER           Required: build or custom
  NEMOCLAW_AGENT              Defaults to hermes
  NEMOCLAW_ENDPOINT_URL       Required when NEMOCLAW_PROVIDER=custom
  COMPATIBLE_API_KEY          Required when NEMOCLAW_PROVIDER=custom
  OPENSHELL_PROVIDER_NAME     Inference provider name in OpenShell (default: nvidia)
  NEMOCLAW_MODEL              Model ID for Hermes inference
  NEMOHERMES_API_PORT         Hermes API port exposed by NemoHermes (default: 8642)
  NEMOHERMES_MCP_URL          VSS Orchestrator MCP URL from the sandbox
                              (default: http://host.openshell.internal:9988/mcp)
  NEMOCLAW_HERMES_DASHBOARD   Set to 1 to enable the optional Hermes web dashboard
  NEMOCLAW_HERMES_DASHBOARD_PORT
                              Hermes dashboard port when enabled (default: 9119)
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
      --policy-file)
        NEMOCLAW_POLICY_FILE="$2"
        shift 2
        ;;
      --workspace-dir)
        NEMOHERMES_WORKSPACE_DIR="$2"
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

  if [ "${NEMOCLAW_PROVIDER}" = "build" ] && [ -z "${NVIDIA_API_KEY:-}" ]; then
    read -rsp "Enter your NVIDIA API key: " NVIDIA_API_KEY
    printf '\n'
    if [ -z "${NVIDIA_API_KEY:-}" ]; then
      log "ERROR: NVIDIA API key is required when NEMOCLAW_PROVIDER=build."
      exit 1
    fi
  fi
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

  if [ -d "$NEMOCLAW_SHIM_DIR" ] && [[ ":$PATH:" != *":$NEMOCLAW_SHIM_DIR:"* ]]; then
    export PATH="$NEMOCLAW_SHIM_DIR:$PATH"
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
    "$NEMOCLAW_SHIM_DIR/nemoclaw" \
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
    "$NEMOCLAW_SHIM_DIR/nemohermes" \
    "${npm_bin:-}/nemohermes"
  do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

validate_settings() {
  case "${NEMOCLAW_AGENT}" in
    hermes) ;;
    *)
      log "ERROR: init_nemohermes.sh supports NEMOCLAW_AGENT=hermes only."
      exit 1
      ;;
  esac

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

  if [ ! -d "${VSS_REPO_DIR}/skills" ]; then
    log "ERROR: ${VSS_REPO_DIR}/skills is missing."
    exit 1
  fi
}

export_provider_env() {
  export NEMOCLAW_AGENT
  export NEMOCLAW_PROVIDER
  export NEMOCLAW_MODEL
  export NEMOCLAW_NON_INTERACTIVE
  export NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE
  export NEMOCLAW_HERMES_DASHBOARD
  export NEMOCLAW_HERMES_DASHBOARD_PORT
  export NVIDIA_API_KEY
  if [ "${NEMOCLAW_PROVIDER}" = "custom" ]; then
    export NEMOCLAW_ENDPOINT_URL
    export COMPATIBLE_API_KEY
  fi
}

sandbox_exists() {
  have openshell && openshell sandbox get "$NEMOCLAW_SANDBOX_NAME" >/dev/null 2>&1
}

run_onboard() {
  local nemohermes_cmd nemoclaw_cmd

  export_provider_env
  if nemohermes_cmd="$(resolve_nemohermes)"; then
    log "Running nemohermes onboard (NEMOCLAW_PROVIDER=${NEMOCLAW_PROVIDER})"
    "$nemohermes_cmd" onboard --non-interactive
    return
  fi

  nemoclaw_cmd="$(resolve_nemoclaw)" || {
    log "neither nemohermes nor nemoclaw is currently resolvable"
    exit 1
  }

  log "Running nemoclaw onboard --agent hermes (NEMOCLAW_PROVIDER=${NEMOCLAW_PROVIDER})"
  "$nemoclaw_cmd" onboard --agent hermes --non-interactive
}

run_install() {
  local install_script="${NEMOCLAW_REPO_DIR}/install.sh"

  if [ ! -x "$install_script" ]; then
    log "${install_script} is not available"
    exit 1
  fi

  log "Running NemoClaw installer for Hermes (NEMOCLAW_PROVIDER=${NEMOCLAW_PROVIDER})"
  (
    export_provider_env
    export NEMOCLAW_SANDBOX_NAME
    cd "$NEMOCLAW_REPO_DIR" && ./install.sh --non-interactive
  )
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
  esac

  log "Configuring OpenShell provider ${OPENSHELL_PROVIDER_NAME} (base=${openai_base_url})"
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

  openshell inference set --provider "$OPENSHELL_PROVIDER_NAME" --model "$NEMOCLAW_MODEL" --timeout 300
  openshell inference get || true
}

# Inject NGC_CLI_API_KEY into the sandbox env so VSS skills can authenticate
# if they need sandbox-side NGC access. The orchestrator MCP server also
# inherits NGC_CLI_API_KEY on the host for deploy-time downloads.
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

# Install the NGC CLI inside the running sandbox so sandbox-side `ngc`
# commands work when a skill needs them. Best-effort: the main VSS deploy path
# still uses the host-side orchestrator MCP server for Docker/NGC operations.
configure_ngc_cli_in_sandbox() {
  if ! have nemoclaw; then
    log "nemoclaw not available; skipping in-sandbox NGC CLI install"
    return
  fi
  log "Installing NGC CLI inside sandbox ${NEMOCLAW_SANDBOX_NAME} (pip3 install --user ngcsdk)"
  if ! nemoclaw sandbox exec -n "$NEMOCLAW_SANDBOX_NAME" --no-tty -- bash -c '
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
  '; then
    log "In-sandbox NGC CLI install failed; ngc registry calls inside the sandbox will not work"
  fi
}

strip_ansi() {
  sed -E 's/\x1B\[[0-9;]*[[:alpha:]]//g'
}

sandbox_ready() {
  have openshell || return 1
  openshell sandbox list 2>/dev/null \
    | strip_ansi \
    | awk -v name="$NEMOCLAW_SANDBOX_NAME" '$1 == name && $NF == "Ready" { found = 1 } END { exit found ? 0 : 1 }' \
    || return 1
  openshell sandbox exec -n "$NEMOCLAW_SANDBOX_NAME" -- sh -lc 'command -v hermes >/dev/null' </dev/null >/dev/null 2>&1
}

wait_for_sandbox_ready() {
  local timeout deadline
  timeout="${1:-${NEMOHERMES_SANDBOX_READY_TIMEOUT:-300}}"
  deadline=$((SECONDS + timeout))

  if have nemoclaw; then
    log "NemoClaw status before sandbox readiness check"
    nemoclaw status || true
  fi

  log "Waiting for Hermes sandbox ${NEMOCLAW_SANDBOX_NAME} to be Ready"
  while [ "$SECONDS" -lt "$deadline" ]; do
    if sandbox_ready; then
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

install_vss_skills() {
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

upload_workspace_templates() {
  local local_file remote_file shell_cmd

  if [ ! -d "$NEMOHERMES_WORKSPACE_DIR" ]; then
    log "Workspace template directory ${NEMOHERMES_WORKSPACE_DIR} is missing; skipping"
    return
  fi

  if ! have openshell; then
    log "OpenShell is not available; cannot upload Hermes workspace templates"
    return 1
  fi

  log "Uploading Hermes workspace templates from ${NEMOHERMES_WORKSPACE_DIR}"
  openshell sandbox exec -n "$NEMOCLAW_SANDBOX_NAME" -- sh -lc \
    "mkdir -p '$NEMOHERMES_REMOTE_WORKSPACE/memory'" </dev/null

  for local_file in "$NEMOHERMES_WORKSPACE_DIR"/*.md; do
    [ -f "$local_file" ] || continue
    remote_file="${NEMOHERMES_REMOTE_WORKSPACE}/$(basename "$local_file")"
    printf -v shell_cmd 'cat > %q' "$remote_file"
    if ! openshell sandbox exec -n "$NEMOCLAW_SANDBOX_NAME" -- sh -c "$shell_cmd" < "$local_file"; then
      log "ERROR: failed to upload $(basename "$local_file")"
      return 1
    fi
  done
}

configure_hermes_mcp_server() {
  if ! have openshell; then
    log "OpenShell is not available; cannot configure Hermes MCP server"
    return 1
  fi

  log "Configuring Hermes MCP server ${NEMOHERMES_MCP_SERVER_NAME} -> ${NEMOHERMES_MCP_URL}"
  openshell sandbox exec -n "$NEMOCLAW_SANDBOX_NAME" -- \
    env "VSS_ORCHESTRATOR_MCP_NAME=${NEMOHERMES_MCP_SERVER_NAME}" \
      "VSS_ORCHESTRATOR_MCP_URL=${NEMOHERMES_MCP_URL}" \
      sh -s <<'SH'
set -e
if ! command -v hermes >/dev/null 2>&1; then
  echo "hermes CLI is required to configure MCP servers" >&2
  exit 1
fi

PYTHON_BIN=""
for candidate in \
  /sandbox/.hermes/hermes-agent/.venv/bin/python \
  "$(command -v python3 || true)" \
  "$(command -v python || true)"
do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then
    PYTHON_BIN="$candidate"
    break
  fi
done

if [ -z "$PYTHON_BIN" ]; then
  echo "python is required to verify Hermes MCP support" >&2
  exit 1
fi

if ! "$PYTHON_BIN" - <<'PY' >/dev/null 2>&1
import importlib.util
raise SystemExit(0 if importlib.util.find_spec("mcp") else 1)
PY
then
  if command -v uv >/dev/null 2>&1 && [ -d /sandbox/.hermes/hermes-agent ]; then
    echo "Hermes MCP Python package is missing; installing Hermes MCP extra"
    cd /sandbox/.hermes/hermes-agent
    uv pip install -e ".[mcp]"
  else
    echo "Hermes MCP Python package is missing and could not be installed automatically." >&2
    echo "Install it inside the sandbox with: cd /sandbox/.hermes/hermes-agent && uv pip install -e '.[mcp]'" >&2
    exit 1
  fi
fi

hermes mcp remove "$VSS_ORCHESTRATOR_MCP_NAME" >/dev/null 2>&1 || true
hermes mcp add "$VSS_ORCHESTRATOR_MCP_NAME" --url "$VSS_ORCHESTRATOR_MCP_URL"
SH
}

hermes_api_healthy() {
  have curl && curl -fsS "http://127.0.0.1:${NEMOHERMES_API_PORT}/health" >/dev/null 2>&1
}

wait_for_hermes_api() {
  local timeout deadline
  timeout="${1:-${NEMOHERMES_API_READY_TIMEOUT:-120}}"
  deadline=$((SECONDS + timeout))

  log "Waiting for Hermes API on http://127.0.0.1:${NEMOHERMES_API_PORT}/health"
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

main() {
  refresh_path

  if sandbox_exists; then
    log "Sandbox ${NEMOCLAW_SANDBOX_NAME} already exists; skipping NemoClaw onboard/install"
    configure_openshell_provider
  else
    log "Start installing/onboarding NemoHermes"
    if have nemoclaw; then
      run_onboard
    else
      run_install
    fi
    log "Finished installing/onboarding NemoHermes"
  fi

  wait_for_sandbox_ready
  refresh_path
  configure_ngc_credential_provider
  apply_vss_policy
  install_vss_skills
  upload_workspace_templates
  configure_hermes_mcp_server
  configure_ngc_cli_in_sandbox
  wait_for_hermes_api

  log "NemoHermes VSS setup complete."
  log "To connect, run: nemohermes ${NEMOCLAW_SANDBOX_NAME} connect"
  log "Hermes API: http://127.0.0.1:${NEMOHERMES_API_PORT}/v1"
  log "VSS Orchestrator MCP: ${NEMOHERMES_MCP_URL}"
  log "After starting or restarting the host MCP server, run /reload-mcp in Hermes or reconnect."
  if is_truthy "${NEMOCLAW_HERMES_DASHBOARD}"; then
    log "Hermes dashboard: http://127.0.0.1:${NEMOCLAW_HERMES_DASHBOARD_PORT}/"
  fi
}

parse_args "$@"
validate_settings
export NEMOCLAW_SANDBOX_NAME NEMOCLAW_AGENT NEMOCLAW_PROVIDER OPENSHELL_PROVIDER_NAME NEMOCLAW_MODEL
export NEMOCLAW_NON_INTERACTIVE NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE
export NEMOCLAW_ENDPOINT_URL COMPATIBLE_API_KEY NEMOCLAW_REPO_DIR NEMOCLAW_POLICY_FILE
export NEMOHERMES_WORKSPACE_DIR NEMOHERMES_REMOTE_WORKSPACE NEMOHERMES_API_PORT
export NEMOHERMES_MCP_SERVER_NAME NEMOHERMES_MCP_URL
export NEMOCLAW_HERMES_DASHBOARD NEMOCLAW_HERMES_DASHBOARD_PORT

main
