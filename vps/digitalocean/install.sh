#!/usr/bin/env bash
# OpenClaw VPS Installer — DigitalOcean / Ubuntu
# https://github.com/no-name-labs/openclaw-install-scripts
# MIT License
#
# Usage (one-liner):
#   bash <(curl -fsSL https://raw.githubusercontent.com/no-name-labs/openclaw-install-scripts/main/vps/digitalocean/install.sh)
#
# Non-interactive (pre-set env vars to skip prompts):
#   RUNTIME_PROVIDER=openai OPENAI_API_KEY=sk-... TELEGRAM_BOT_TOKEN=... \
#   BIND_MODE=topic BIND_TELEGRAM_LINK=https://t.me/c/.../... \
#   AUTO_CONFIRM=true NON_INTERACTIVE=true bash install.sh

set -euo pipefail

# ── Configuration (override via env) ─────────────────────────────────────────

OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"
AUTO_CONFIRM="${AUTO_CONFIRM:-false}"
NODE_MAJOR="${NODE_MAJOR:-22}"

# LLM provider — set these to skip the interactive menus
RUNTIME_PROVIDER="${RUNTIME_PROVIDER:-}"         # openai | anthropic
RUNTIME_AUTH_METHOD="${RUNTIME_AUTH_METHOD:-}"   # api_key | codex (openai) | oauth (anthropic)
OPENAI_API_KEY="${OPENAI_API_KEY:-}"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"

# Telegram
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
PAIRING_TELEGRAM_USER_ID="${PAIRING_TELEGRAM_USER_ID:-}"
TELEGRAM_PAIRING_TIMEOUT_SECONDS="${TELEGRAM_PAIRING_TIMEOUT_SECONDS:-120}"

# Binding
BIND_MODE="${BIND_MODE:-}"                       # topic | direct
BIND_TELEGRAM_LINK="${BIND_TELEGRAM_LINK:-}"
BIND_GROUP_ID="${BIND_GROUP_ID:-}"
BIND_TOPIC_ID="${BIND_TOPIC_ID:-}"
BIND_DIRECT_USER_ID="${BIND_DIRECT_USER_ID:-}"

# ── Terminal colours ──────────────────────────────────────────────────────────

if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
else
  C_RESET=""; C_BOLD=""; C_CYAN=""; C_GREEN=""; C_YELLOW=""; C_RED=""
fi

# ── Logging helpers ───────────────────────────────────────────────────────────

ts()           { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log_info()     { printf "[%s] [INFO]  %s\n"    "$(ts)" "$*"; }
log_warn()     { printf "[%s] [WARN]  %s\n"    "$(ts)" "$*" >&2; }
log_error()    { printf "[%s] [ERROR] %s\n"    "$(ts)" "$*" >&2; }
section()      { printf "\n%s%s%s\n"           "${C_BOLD}${C_CYAN}" "$*" "${C_RESET}"; }
step()         { printf "%s  %s%s\n"           "${C_GREEN}" "$*" "${C_RESET}"; }
cmd_hint()     { printf "  %s%s%s\n"           "${C_YELLOW}" "$*" "${C_RESET}"; }
die()          { log_error "$*"; exit 1; }
require_cmd()  { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

run_as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then "$@"
  else require_cmd sudo; sudo "$@"; fi
}

# ── apt helpers ───────────────────────────────────────────────────────────────

apt_retry() {
  local attempt=1
  while (( attempt <= 5 )); do
    if run_as_root apt-get -o DPkg::Lock::Timeout=300 -o Acquire::Retries=5 "$@"; then
      return 0
    fi
    (( attempt == 5 )) && break
    log_warn "apt-get failed (attempt ${attempt}/5), retrying in 5s"
    sleep 5; attempt=$((attempt + 1))
  done
  die "apt-get failed after 5 attempts: apt-get $*"
}

cleanup_stale_nodesource() {
  local stale
  stale="$(run_as_root bash -c \
    "grep -RIl 'deb\\.nodesource\\.com' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null || true")"
  if [[ -n "${stale}" ]]; then
    log_warn "Removing stale NodeSource apt entries."
    while IFS= read -r f; do
      [[ -n "${f}" ]] || continue
      if [[ "${f}" == /etc/apt/sources.list.d/* ]]; then
        run_as_root rm -f "${f}" || true
      else
        run_as_root sed -i '/deb\.nodesource\.com/d' "${f}" || true
        run_as_root sed -i '/nodesource\.com/d'     "${f}" || true
      fi
    done <<< "${stale}"
  fi
  run_as_root rm -f \
    /etc/apt/sources.list.d/nodesource.list \
    /etc/apt/sources.list.d/nodesource.sources \
    /etc/apt/keyrings/nodesource.gpg \
    /usr/share/keyrings/nodesource.gpg || true
}

# ── Interactive helpers ───────────────────────────────────────────────────────

prompt_secret() {
  local var_name="$1" prompt_text="$2" optional="${3:-false}"
  local current="${!var_name:-}"
  [[ -n "${current}" ]] && return 0
  if [[ "${NON_INTERACTIVE}" == "true" ]]; then
    [[ "${optional}" == "true" ]] && return 0
    die "Missing required env var: ${var_name} (NON_INTERACTIVE=true)"
  fi
  local entered=""
  if [[ "${optional}" == "true" ]]; then
    read -r -s -p "${prompt_text} (optional, press Enter to skip): " entered; echo
  else
    while [[ -z "${entered}" ]]; do
      read -r -s -p "${prompt_text}: " entered; echo
    done
  fi
  printf -v "${var_name}" "%s" "${entered}"
}

prompt_input() {
  local var_name="$1" prompt_text="$2" default="${3:-}"
  local current="${!var_name:-}"
  [[ -n "${current}" ]] && return 0
  if [[ "${NON_INTERACTIVE}" == "true" ]]; then
    [[ -n "${default}" ]] && { printf -v "${var_name}" "%s" "${default}"; return 0; }
    die "Missing required env var: ${var_name} (NON_INTERACTIVE=true)"
  fi
  local entered=""
  if [[ -n "${default}" ]]; then
    read -r -p "${prompt_text} [${default}]: " entered
    entered="${entered:-${default}}"
  else
    while [[ -z "${entered}" ]]; do
      read -r -p "${prompt_text}: " entered
    done
  fi
  printf -v "${var_name}" "%s" "${entered}"
}

# Inline ↑/↓ selection menu (falls back to numbered list when no TTY)
menu_select() {
  local var_name="$1" prompt_text="$2"; shift 2
  local -a entries=("$@")
  local -a values=() labels=()
  for e in "${entries[@]}"; do values+=("${e%%|*}"); labels+=("${e#*|}"); done

  local current="${!var_name:-}"
  if [[ -n "${current}" ]]; then return 0; fi

  if [[ "${NON_INTERACTIVE}" == "true" ]]; then
    die "Missing required env var: ${var_name} (NON_INTERACTIVE=true)"
  fi

  if [[ -t 0 && -t 1 ]] && command -v tput >/dev/null 2>&1; then
    local selected=0
    local line_count=$(( ${#labels[@]} + 2 ))
    tput civis >&2 || true
    trap 'tput cnorm >/dev/null 2>&1 || true' RETURN
    while true; do
      printf "\r%s\n" "${prompt_text}" >&2
      local i
      for i in "${!labels[@]}"; do
        if [[ "${i}" -eq "${selected}" ]]; then printf "  > %s\n" "${labels[$i]}" >&2
        else printf "    %s\n" "${labels[$i]}" >&2; fi
      done
      printf "  (↑/↓ + Enter)\n" >&2
      local key="" c1="" c2=""
      IFS= read -rsn1 key
      if [[ "${key}" == "" ]]; then break; fi
      if [[ "${key}" == $'\x1b' ]]; then
        IFS= read -rsn1 -t 0.1 c1 || true
        IFS= read -rsn1 -t 0.1 c2 || true
        case "${c1}${c2}" in
          "[A") (( selected > 0 )) && selected=$((selected - 1)) ;;
          "[B") (( selected < ${#labels[@]} - 1 )) && selected=$((selected + 1)) ;;
        esac
      fi
      printf "\033[%dA" "${line_count}" >&2
    done
    printf "\033[%dA" "${line_count}" >&2
    printf "\033[J" >&2
    printf "%s %s\n" "${prompt_text}" "${labels[$selected]}" >&2
    printf -v "${var_name}" "%s" "${values[$selected]}"
  else
    printf "%s\n" "${prompt_text}" >&2
    local i
    for i in "${!labels[@]}"; do printf "  %d) %s\n" "$((i+1))" "${labels[$i]}" >&2; done
    local choice=""
    while true; do
      read -r -p "Choice [1-${#labels[@]}]: " choice
      if [[ "${choice}" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#labels[@]} )); then
        printf -v "${var_name}" "%s" "${values[$((choice-1))]}"; break
      fi
    done
  fi
}

# ── env file helper ───────────────────────────────────────────────────────────

upsert_env_var() {
  local env_file="$1" key="$2" value="$3"
  mkdir -p "$(dirname "${env_file}")"
  touch "${env_file}"; chmod 600 "${env_file}" || true
  python3 - "${env_file}" "${key}" "${value}" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1]); key = sys.argv[2]; value = sys.argv[3]
lines = p.read_text(encoding="utf-8").splitlines() if p.exists() else []
pat = re.compile(rf"^{re.escape(key)}=")
updated = False
for i, l in enumerate(lines):
    if pat.match(l): lines[i] = f"{key}={value}"; updated = True; break
if not updated: lines.append(f"{key}={value}")
p.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
}

with_openclaw_env() {
  local env_file="${OPENCLAW_HOME}/.env"
  export OPENCLAW_STATE_DIR="${OPENCLAW_HOME}"
  export OPENCLAW_CONFIG_PATH="${OPENCLAW_HOME}/openclaw.json"
  if [[ -f "${env_file}" ]]; then set -a; source "${env_file}"; set +a; fi
  "$@"
}

# ── Gateway helpers ───────────────────────────────────────────────────────────

stop_gateway() {
  with_openclaw_env openclaw gateway stop >/dev/null 2>&1 || true
  sleep 1
  if command -v pgrep >/dev/null 2>&1; then
    local pid
    while read -r pid; do
      [[ -z "${pid}" || "${pid}" == "$$" || "${pid}" == "${PPID:-}" ]] && continue
      kill "${pid}" 2>/dev/null || true
    done < <(pgrep -f "openclaw.*gateway" 2>/dev/null | sort -u || true)
  fi
}

start_gateway() {
  local extra_args="${1:-}"
  mkdir -p "${OPENCLAW_HOME}/logs"
  stop_gateway || true
  (
    cd "${OPENCLAW_HOME}"
    export OPENCLAW_STATE_DIR="${OPENCLAW_HOME}"
    export OPENCLAW_CONFIG_PATH="${OPENCLAW_HOME}/openclaw.json"
    [[ -f "${OPENCLAW_HOME}/.env" ]] && { set -a; source "${OPENCLAW_HOME}/.env"; set +a; }
    # shellcheck disable=SC2086
    nohup openclaw gateway run --port "${OPENCLAW_PORT}" ${extra_args} \
      >"${OPENCLAW_HOME}/logs/gateway-run.log" 2>&1 &
    echo $! > "${OPENCLAW_HOME}/.gateway.pid"
  )
}

wait_for_gateway() {
  local timeout="${1:-60}" start; start="$(date +%s)"
  while true; do
    if with_openclaw_env openclaw health --json >/dev/null 2>&1; then return 0; fi
    (( "$(date +%s)" - start >= timeout )) && return 1
    sleep 2
  done
}

restart_gateway() {
  stop_gateway || true; start_gateway
  wait_for_gateway 60 || die "Gateway did not become healthy after restart."
}

# ── LLM provider helpers ──────────────────────────────────────────────────────

is_valid_claude_oauth_token() {
  [[ "${1:-}" =~ ^sk-ant-oat[0-9]+-[A-Za-z0-9_-]{20,}$ ]]
}

ensure_claude_cli() {
  if command -v claude >/dev/null 2>&1; then return 0; fi
  log_info "Anthropic setup-token requires Claude CLI — installing @anthropic-ai/claude-code."
  run_as_root npm install -g @anthropic-ai/claude-code
  require_cmd claude
}

write_auth_profile() {
  local profile_id="$1" provider="$2" auth_type="$3" credential="$4"
  local store="${OPENCLAW_HOME}/agents/main/agent/auth-profiles.json"
  python3 - "${store}" "${profile_id}" "${provider}" "${auth_type}" "${credential}" <<'PY'
import json, pathlib, sys, time
store = pathlib.Path(sys.argv[1])
profile_id, provider, auth_type, credential = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
store.parent.mkdir(parents=True, exist_ok=True)
try:
    data = json.loads(store.read_text(encoding="utf-8")) if store.exists() else {}
except Exception:
    data = {}
if not isinstance(data, dict):
    data = {}
data["version"] = 1
profiles = data.setdefault("profiles", {})
if auth_type == "api_key":
    profiles[profile_id] = {"type": "api_key", "provider": provider, "key": credential}
elif auth_type == "token":
    profiles[profile_id] = {
        "type": "token", "provider": provider, "token": credential,
        "expires": int(time.time() * 1000) + 365 * 24 * 60 * 60 * 1000,
    }
store.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"Auth profile written: {profile_id}")
PY
}

run_anthropic_setup_token() {
  local token=""

  # Try auto-capture via script(1) so the user only does one action
  if command -v script >/dev/null 2>&1; then
    local tmplog; tmplog="$(mktemp)"
    if script -q -e -c "claude setup-token" "${tmplog}" 2>/dev/null; then
      token="$(grep -oP 'sk-ant-oat[0-9]+-[A-Za-z0-9_-]+' "${tmplog}" 2>/dev/null | tail -1 || true)"
    fi
    rm -f "${tmplog}"
  else
    claude setup-token || true
  fi

  local attempts=0
  while ! is_valid_claude_oauth_token "${token}" && (( attempts < 3 )); do
    attempts=$(( attempts + 1 ))
    [[ "${attempts}" -gt 1 ]] && step "Run:  claude setup-token  — then paste the token below."
    step "Paste the setup-token (starts with sk-ant-oat...):"
    read -r -s -p "Token: " token; echo
    token="${token// /}"
  done

  is_valid_claude_oauth_token "${token}" || die "Invalid setup-token after 3 attempts."
  write_auth_profile "anthropic:oauth" "anthropic" "token" "${token}"
  log_info "Anthropic setup-token applied."
}

authenticate_runtime_provider() {
  case "${RUNTIME_PROVIDER}:${RUNTIME_AUTH_METHOD}" in
    *:api_key) return 0 ;;  # Already done during configure_llm_provider
    openai:codex)
      section "OpenAI — Codex OAuth"
      step "A browser window will open for OpenAI authentication."
      step "Complete the login, then return here."
      with_openclaw_env openclaw models auth login --provider openai-codex \
        || die "OpenAI Codex OAuth login failed."
      log_info "OpenAI Codex OAuth login complete."
      ;;
    anthropic:oauth)
      section "Anthropic — setup-token"
      step "You need a Claude Pro/Max subscription for this method."
      ensure_claude_cli
      run_anthropic_setup_token
      ;;
  esac
}

# ── LLM provider setup ────────────────────────────────────────────────────────

configure_llm_provider() {
  section "LLM Provider Setup"

  # ── 1. Provider ─────────────────────────────────────────────────────────────
  menu_select RUNTIME_PROVIDER "Select your LLM provider:" \
    "openai|OpenAI" \
    "anthropic|Anthropic (Claude)"

  # ── 2. Auth method ──────────────────────────────────────────────────────────
  local auth_opt_a="" auth_opt_b=""
  case "${RUNTIME_PROVIDER}" in
    openai)
      auth_opt_a="api_key|API key  (sk-proj-...)"
      auth_opt_b="codex|ChatGPT subscription — Codex OAuth"
      ;;
    anthropic)
      auth_opt_a="api_key|API key  (sk-ant-api...)"
      auth_opt_b="oauth|Claude subscription — setup-token  (sk-ant-oat...)"
      ;;
  esac
  menu_select RUNTIME_AUTH_METHOD "Authentication method:" "${auth_opt_a}" "${auth_opt_b}"

  # ── 3. Resolve profile / model / mode ───────────────────────────────────────
  local profile_id="" default_model="" auth_mode_json="" provider_in_profile=""
  case "${RUNTIME_PROVIDER}:${RUNTIME_AUTH_METHOD}" in
    openai:api_key)
      profile_id="openai:api-key"; default_model="openai/gpt-4o"
      auth_mode_json="api_key";    provider_in_profile="openai" ;;
    openai:codex)
      profile_id="openai-codex:oauth"; default_model="openai-codex/gpt-5.4"
      auth_mode_json="oauth";          provider_in_profile="openai-codex" ;;
    anthropic:api_key)
      profile_id="anthropic:api-key"; default_model="anthropic/claude-opus-4-6"
      auth_mode_json="api_key";        provider_in_profile="anthropic" ;;
    anthropic:oauth)
      profile_id="anthropic:oauth"; default_model="anthropic/claude-opus-4-6"
      auth_mode_json="token";        provider_in_profile="anthropic" ;;
    *) die "Unsupported provider/auth combination: ${RUNTIME_PROVIDER}:${RUNTIME_AUTH_METHOD}" ;;
  esac

  # ── 4. Collect API key (api_key mode only) ───────────────────────────────────
  local api_key=""
  case "${RUNTIME_PROVIDER}:${RUNTIME_AUTH_METHOD}" in
    openai:api_key)
      prompt_secret OPENAI_API_KEY "Enter your OpenAI API key"
      api_key="${OPENAI_API_KEY}"
      upsert_env_var "${OPENCLAW_HOME}/.env" "OPENAI_API_KEY" "${api_key}"
      ;;
    anthropic:api_key)
      prompt_secret ANTHROPIC_API_KEY "Enter your Anthropic API key"
      api_key="${ANTHROPIC_API_KEY}"
      upsert_env_var "${OPENCLAW_HOME}/.env" "ANTHROPIC_API_KEY" "${api_key}"
      ;;
  esac
  upsert_env_var "${OPENCLAW_HOME}/.env" "RUNTIME_PROVIDER"    "${RUNTIME_PROVIDER}"
  upsert_env_var "${OPENCLAW_HOME}/.env" "RUNTIME_AUTH_METHOD" "${RUNTIME_AUTH_METHOD}"

  # ── 5. Write openclaw.json (profile definition + model defaults) ─────────────
  python3 - "${OPENCLAW_HOME}/openclaw.json" \
    "${provider_in_profile}" "${profile_id}" "${default_model}" "${auth_mode_json}" "${api_key:-}" <<'PY'
import json, pathlib, sys
cfg_path          = pathlib.Path(sys.argv[1])
provider_profile  = sys.argv[2]
profile_id        = sys.argv[3]
model             = sys.argv[4]
auth_mode         = sys.argv[5]
api_key           = sys.argv[6] if len(sys.argv) > 6 else ""

data = json.loads(cfg_path.read_text(encoding="utf-8")) if cfg_path.exists() else {}

auth = data.setdefault("auth", {})
profiles = auth.setdefault("profiles", {})
profiles[profile_id] = {"provider": provider_profile, "mode": auth_mode}

# For api_key mode also store inline in auth.keys (gateway fallback)
if api_key and auth_mode == "api_key":
    auth.setdefault("keys", {})[profile_id] = api_key

agents = data.setdefault("agents", {})
if isinstance(agents, list):
    agents = {"list": agents}
    data["agents"] = agents
defaults = agents.setdefault("defaults", {})
defaults["profile"] = profile_id
defaults.setdefault("model", {})["primary"] = model

cfg_path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"Configured provider={provider_profile} profile={profile_id} model={model}")
PY

  # ── 6. Write auth-profiles.json for api_key ──────────────────────────────────
  if [[ "${RUNTIME_AUTH_METHOD}" == "api_key" ]]; then
    write_auth_profile "${profile_id}" "${provider_in_profile}" "api_key" "${api_key}"
  fi

  log_info "LLM provider configured: ${RUNTIME_PROVIDER}/${RUNTIME_AUTH_METHOD} (${profile_id})"
}

# ── Telegram setup ────────────────────────────────────────────────────────────

ensure_telegram_plugin() {
  local plugins_json
  plugins_json="$(with_openclaw_env openclaw plugins list --json 2>/dev/null || true)"

  if printf "%s" "${plugins_json}" | python3 -c \
      "import json,sys; d=json.load(sys.stdin); \
       exit(0 if any(p.get('id')=='telegram' and p.get('enabled') for p in d.get('plugins',[])) else 1)" \
      2>/dev/null; then
    log_info "Telegram plugin already enabled."
    return 0
  fi

  log_info "Enabling Telegram plugin."
  with_openclaw_env openclaw plugins enable telegram >/dev/null
}

configure_telegram_in_json() {
  python3 - "${OPENCLAW_HOME}/openclaw.json" "${TELEGRAM_BOT_TOKEN}" <<'PY'
import json, pathlib, sys
cfg = pathlib.Path(sys.argv[1]); token = sys.argv[2]
data = json.loads(cfg.read_text(encoding="utf-8")) if cfg.exists() else {}
ch = data.setdefault("channels", {})
tg = ch.setdefault("telegram", {})
tg["enabled"] = True
tg.setdefault("commands", {})["native"] = True
accounts = tg.setdefault("accounts", {})
accounts.setdefault("default", {})["botToken"] = token
cfg.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
}

wait_for_pairing_code() {
  local timeout="${TELEGRAM_PAIRING_TIMEOUT_SECONDS}" start; start="$(date +%s)"
  while (( "$(date +%s)" - start < timeout )); do
    local raw code uid
    raw="$(with_openclaw_env openclaw pairing list --channel telegram --json 2>/dev/null \
           || with_openclaw_env openclaw pairing list telegram --json 2>/dev/null || true)"
    [[ -z "${raw}" ]] && { sleep 2; continue; }
    code="$(printf "%s" "${raw}" | python3 -c \
      "import json,sys; d=json.load(sys.stdin); \
       reqs=d.get('requests', d) if isinstance(d,dict) else d; \
       reqs=reqs if isinstance(reqs,list) else []; \
       r=reqs[0] if reqs else {}; print(r.get('code',''))" 2>/dev/null || true)"
    uid="$(printf "%s" "${raw}" | python3 -c \
      "import json,sys; d=json.load(sys.stdin); \
       reqs=d.get('requests', d) if isinstance(d,dict) else d; \
       reqs=reqs if isinstance(reqs,list) else []; \
       r=reqs[0] if reqs else {}; print(r.get('id',''))" 2>/dev/null || true)"
    if [[ -n "${code}" ]]; then
      PAIRING_CODE="${code}"
      PAIRING_TELEGRAM_USER_ID="${uid:-${PAIRING_TELEGRAM_USER_ID}}"
      return 0
    fi
    sleep 2
  done
  return 1
}

add_to_allowlist() {
  local uid="${1:-}"; [[ -n "${uid}" ]] || return 0
  python3 - "${OPENCLAW_HOME}/openclaw.json" "${uid}" <<'PY'
import json, pathlib, sys
cfg = pathlib.Path(sys.argv[1]); uid = str(sys.argv[2]).strip()
if not uid: raise SystemExit(0)
data = json.loads(cfg.read_text(encoding="utf-8")) if cfg.exists() else {}
tg = data.setdefault("channels", {}).setdefault("telegram", {})
tg.setdefault("groupPolicy", "allowlist")
allow = {str(x).strip() for x in tg.get("groupAllowFrom", []) if str(x).strip()}
allow.add(uid); tg["groupAllowFrom"] = sorted(allow)
acct = tg.setdefault("accounts", {}).setdefault("default", {})
acct.setdefault("groupPolicy", "allowlist")
a2 = {str(x).strip() for x in acct.get("groupAllowFrom", []) if str(x).strip()}
a2.add(uid); acct["groupAllowFrom"] = sorted(a2)
cfg.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
}

parse_telegram_topic_link() {
  local link="$1"
  local parsed
  parsed="$(python3 - "${link}" "${TELEGRAM_BOT_TOKEN}" <<'PY'
import json, re, sys
from urllib.parse import urlparse
from urllib.request import Request, urlopen

raw = (sys.argv[1] or "").strip()
bot_token = (sys.argv[2] or "").strip()

if not re.match(r"^https?://", raw, re.I):
    raw = "https://" + raw

parsed = urlparse(raw)
if parsed.netloc.lower() not in {"t.me","www.t.me","telegram.me","www.telegram.me"}:
    raise SystemExit("Unsupported Telegram host in link.")

parts = [p for p in parsed.path.split("/") if p]
group_id = ""; topic_id = ""; username = ""

if parts[0] == "c":
    if len(parts) < 3: raise SystemExit("Invalid t.me/c link: missing topic ID.")
    group_id = f"-100{parts[1]}" if parts[1].isdigit() else ""
    username = "" if parts[1].isdigit() else parts[1]
    topic_id = parts[2]
else:
    if len(parts) < 2: raise SystemExit("Invalid Telegram topic link.")
    username = parts[0]; topic_id = parts[1]

if not topic_id.isdigit(): raise SystemExit("Topic ID must be numeric.")
if not group_id:
    if not username: raise SystemExit("Could not resolve group identifier.")
    if not bot_token: raise SystemExit("Bot token required to resolve group username.")
    url = f"https://api.telegram.org/bot{bot_token}/getChat?chat_id=@{username}"
    req = Request(url, headers={"Accept": "application/json"})
    with urlopen(req, timeout=15) as r:
        payload = json.loads(r.read())
    if not payload.get("ok"): raise SystemExit(payload.get("description","getChat failed"))
    group_id = str(payload["result"]["id"])

print(json.dumps({"group_id": group_id, "topic_id": topic_id}))
PY
)" || return 1
  BIND_GROUP_ID="$(printf "%s" "${parsed}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['group_id'])")"
  BIND_TOPIC_ID="$(printf "%s" "${parsed}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['topic_id'])")"
}

collect_bind_target() {
  menu_select BIND_MODE "Where should the bot reply?" \
    "topic|Group topic (recommended — create a group and enable Topics)" \
    "direct|Direct chat with the bot"

  if [[ "${BIND_MODE}" == "topic" ]]; then
    section "Group Topic Binding"
    step "Quick setup:"
    step "  1) Create a Telegram group (or use existing)."
    step "  2) Open Group Settings → enable Topics."
    step "  3) Add your bot to the group and make it admin (send messages)."
    step "  4) Open the target topic, copy its link."
    step "     Example: https://t.me/c/1234567890/2"

    if [[ -z "${BIND_TELEGRAM_LINK}" && ( -z "${BIND_GROUP_ID}" || -z "${BIND_TOPIC_ID}" ) ]]; then
      [[ "${NON_INTERACTIVE}" == "true" ]] && \
        die "Set BIND_TELEGRAM_LINK or BIND_GROUP_ID + BIND_TOPIC_ID (NON_INTERACTIVE=true)"
      read -r -p "Paste topic link: " BIND_TELEGRAM_LINK
    fi

    if [[ -n "${BIND_TELEGRAM_LINK}" ]]; then
      parse_telegram_topic_link "${BIND_TELEGRAM_LINK}" \
        || die "Could not parse Telegram link: ${BIND_TELEGRAM_LINK}"
      log_info "Resolved → group=${BIND_GROUP_ID} topic=${BIND_TOPIC_ID}"
    fi

    [[ -n "${BIND_GROUP_ID}" && -n "${BIND_TOPIC_ID}" ]] \
      || die "Group ID and Topic ID are required for topic binding."
  else
    [[ -n "${BIND_DIRECT_USER_ID}" ]] \
      || BIND_DIRECT_USER_ID="${PAIRING_TELEGRAM_USER_ID}"
    if [[ -z "${BIND_DIRECT_USER_ID}" ]]; then
      prompt_input BIND_DIRECT_USER_ID "Telegram user ID for direct binding"
    fi
    [[ -n "${BIND_DIRECT_USER_ID}" ]] || die "Telegram user ID required for direct binding."
  fi
}

bind_agent() {
  local agent_id="main"
  local peer_id=""
  if [[ "${BIND_MODE}" == "topic" ]]; then
    peer_id="${BIND_GROUP_ID}:topic:${BIND_TOPIC_ID}"
  else
    peer_id="${BIND_DIRECT_USER_ID}"
  fi

  with_openclaw_env openclaw agent bind \
    --agent "${agent_id}" \
    --channel telegram \
    --peer "${peer_id}" >/dev/null 2>&1 || true
  log_info "Agent '${agent_id}' bound to telegram peer: ${peer_id}"
}

# ── Startup cron ──────────────────────────────────────────────────────────────

install_startup_cron() {
  local cron_cmd="@reboot OPENCLAW_STATE_DIR=\"${OPENCLAW_HOME}\" OPENCLAW_CONFIG_PATH=\"${OPENCLAW_HOME}/openclaw.json\" openclaw gateway run --port ${OPENCLAW_PORT} >> \"${OPENCLAW_HOME}/logs/gateway-run.log\" 2>&1"
  local existing
  existing="$(crontab -l 2>/dev/null || true)"
  if printf "%s" "${existing}" | grep -q "openclaw gateway run"; then
    log_info "Startup cron already present."
    return 0
  fi
  printf "%s\n%s\n" "${existing}" "${cron_cmd}" | crontab - 2>/dev/null \
    || log_warn "Could not install startup cron. You may need to add it manually."
  log_info "Startup cron installed (openclaw will auto-start on reboot)."
}

# ── Summary ───────────────────────────────────────────────────────────────────

print_summary() {
  local gateway_token=""
  gateway_token="$(with_openclaw_env openclaw gateway token --json 2>/dev/null \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('token',''))" 2>/dev/null || true)"

  local health_ok="no"
  with_openclaw_env openclaw health --json >/dev/null 2>&1 && health_ok="yes"

  section "✅  OpenClaw installed successfully"
  step "Gateway:   http://127.0.0.1:${OPENCLAW_PORT}  (health: ${health_ok})"
  step "Home:      ${OPENCLAW_HOME}"
  step "Logs:      ${OPENCLAW_HOME}/logs/gateway-run.log"
  step "Provider:  ${RUNTIME_PROVIDER}"

  if [[ "${BIND_MODE}" == "topic" ]]; then
    step "Telegram:  group ${BIND_GROUP_ID}, topic ${BIND_TOPIC_ID}"
  else
    step "Telegram:  direct → user ${BIND_DIRECT_USER_ID}"
  fi

  if [[ -n "${gateway_token}" ]]; then
    printf "\n%sGateway token (keep this secret):%s\n" "${C_BOLD}" "${C_RESET}"
    printf "  %s%s%s\n\n" "${C_YELLOW}" "${gateway_token}" "${C_RESET}"
  fi

  step "Send a message to your Telegram bot to verify it's working."
  printf "\n%sUseful commands:%s\n" "${C_BOLD}" "${C_RESET}"
  cmd_hint "openclaw gateway status"
  cmd_hint "openclaw gateway restart"
  cmd_hint "openclaw health --json"
}

# ── OS check ──────────────────────────────────────────────────────────────────

assert_ubuntu_or_debian() {
  if [[ ! -f /etc/os-release ]]; then
    log_warn "Cannot detect OS. Proceeding anyway."
    return 0
  fi
  local os_id=""
  os_id="$(. /etc/os-release; echo "${ID:-}")"
  case "${os_id}" in
    ubuntu|debian) ;;
    *) die "Unsupported OS '${os_id}'. This script supports Ubuntu/Debian." ;;
  esac
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
  printf "\n%sOpenClaw VPS Installer%s\n" "${C_BOLD}${C_CYAN}" "${C_RESET}"
  printf "Logs: %s/logs/install.log\n\n" "${OPENCLAW_HOME}"

  mkdir -p "${OPENCLAW_HOME}/logs"

  # ── Stage 1/5: System dependencies ────────────────────────────────────────
  section "Stage 1/5: System dependencies"
  assert_ubuntu_or_debian
  log_info "Updating package lists."
  cleanup_stale_nodesource
  apt_retry update -qq
  apt_retry install -y -qq ca-certificates curl git jq python3 gnupg lsb-release

  log_info "Installing Node.js ${NODE_MAJOR}.x via NodeSource."
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | run_as_root bash - >/dev/null 2>&1
  apt_retry install -y -qq nodejs
  log_info "Node.js $(node --version), npm $(npm --version)"

  # ── Stage 2/5: Install OpenClaw ────────────────────────────────────────────
  section "Stage 2/5: Installing OpenClaw"
  run_as_root npm install -g openclaw
  require_cmd openclaw
  log_info "OpenClaw $(openclaw --version 2>/dev/null || echo '(version unknown)')"

  mkdir -p "${OPENCLAW_HOME}/logs"

  # Start gateway once to bootstrap the config directory and openclaw.json.
  # --allow-unconfigured is required because openclaw.json does not exist yet.
  log_info "Starting gateway to initialise config."
  start_gateway "--allow-unconfigured"
  wait_for_gateway 60 || die "Gateway failed to start on first boot."

  # ── Stage 3/5: LLM provider ────────────────────────────────────────────────
  section "Stage 3/5: LLM provider"
  configure_llm_provider
  restart_gateway
  # OAuth flows run after restart (gateway must be up for codex login callback)
  authenticate_runtime_provider
  # If OAuth tokens were just written, restart once more to load them
  case "${RUNTIME_AUTH_METHOD:-api_key}" in
    codex|oauth) restart_gateway ;;
  esac

  # ── Stage 4/5: Telegram ────────────────────────────────────────────────────
  section "Stage 4/5: Telegram"

  log_info "Step 4a: Bot token."
  prompt_secret TELEGRAM_BOT_TOKEN "Enter your Telegram bot token"
  [[ -n "${TELEGRAM_BOT_TOKEN}" ]] || die "Bot token is required."
  upsert_env_var "${OPENCLAW_HOME}/.env" "TELEGRAM_BOT_TOKEN" "${TELEGRAM_BOT_TOKEN}"

  log_info "Step 4b: Enabling Telegram plugin."
  ensure_telegram_plugin

  log_info "Step 4c: Writing Telegram config."
  configure_telegram_in_json
  with_openclaw_env openclaw channels add \
    --channel telegram --account default --token "${TELEGRAM_BOT_TOKEN}" >/dev/null
  restart_gateway

  log_info "Step 4d: Pairing."
  section "Action required — Telegram pairing"
  step "1) Open a direct chat with your bot in Telegram."
  step "2) Press Start (if first time) and send any message."
  step "3) Wait for the 'pairing required' reply from the bot."
  step "4) Come back here and press Enter."

  PAIRING_CODE=""
  if [[ "${AUTO_CONFIRM}" != "true" ]]; then
    [[ "${NON_INTERACTIVE}" == "true" ]] \
      && die "AUTO_CONFIRM=true required when NON_INTERACTIVE=true."
    read -r -p "Press Enter once you have messaged the bot..."
  fi

  if ! wait_for_pairing_code; then
    log_warn "No pairing code found within ${TELEGRAM_PAIRING_TIMEOUT_SECONDS}s."
    section "Manual pairing fallback"
    step "Run this command manually after the pairing code appears in Telegram:"
    cmd_hint "openclaw pairing approve telegram <PAIRING_CODE>"
    exit 0
  fi

  with_openclaw_env openclaw pairing approve telegram "${PAIRING_CODE}" --notify >/dev/null
  add_to_allowlist "${PAIRING_TELEGRAM_USER_ID}"
  log_info "Pairing approved for user ${PAIRING_TELEGRAM_USER_ID:-unknown}."

  log_info "Step 4e: Binding."
  collect_bind_target
  bind_agent
  upsert_env_var "${OPENCLAW_HOME}/.env" "BIND_MODE" "${BIND_MODE}"
  if [[ "${BIND_MODE}" == "topic" ]]; then
    upsert_env_var "${OPENCLAW_HOME}/.env" "BIND_GROUP_ID"   "${BIND_GROUP_ID}"
    upsert_env_var "${OPENCLAW_HOME}/.env" "BIND_TOPIC_ID"   "${BIND_TOPIC_ID}"
    [[ -n "${BIND_TELEGRAM_LINK}" ]] && \
      upsert_env_var "${OPENCLAW_HOME}/.env" "BIND_TELEGRAM_LINK" "${BIND_TELEGRAM_LINK}"
  else
    upsert_env_var "${OPENCLAW_HOME}/.env" "BIND_DIRECT_USER_ID" "${BIND_DIRECT_USER_ID}"
  fi

  restart_gateway

  # ── Stage 5/5: Finalise ────────────────────────────────────────────────────
  section "Stage 5/5: Finalising"
  install_startup_cron
  print_summary
}

main "$@"
