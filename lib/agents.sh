# Wiring the engine into each coding agent as a remote MCP server.
#
# Sourced by bin/ce. Every agent gets the same server name and the same key,
# sent as a Bearer header to the engine's one shared /mcp address — the key,
# not the address, says which engines it reaches. Each agent keeps its copy in
# its own user-only config, the way that agent documents.

AGENTS=(claude codex opencode hermes cursor gemini)

mcp_url() { echo "$CE_HOST/mcp"; }

agent_installed() {
  case "$1" in
  cursor) [[ -d $HOME/.cursor ]] || command -v cursor >/dev/null ;;
  *) command -v "$1" >/dev/null ;;
  esac
}

# --- claude -----------------------------------------------------------------

claude_connected() { claude mcp get "$SERVER_NAME" >/dev/null 2>&1; }

claude_connect() {
  claude mcp remove --scope user "$SERVER_NAME" >/dev/null 2>&1 || true
  claude mcp add --scope user --transport http "$SERVER_NAME" "$(mcp_url)" \
    --header "Authorization: Bearer $CE_KEY" >/dev/null
}

claude_disconnect() { claude mcp remove --scope user "$SERVER_NAME" >/dev/null 2>&1; }

# --- codex ------------------------------------------------------------------
# A static header rather than --bearer-token-env-var: agents launched from an
# Omarchy keybinding inherit the Hyprland session's environment, not a shell's.

CODEX_CONFIG="${CODEX_HOME:-$HOME/.codex}/config.toml"

codex_strip() {
  [[ -f $CODEX_CONFIG ]] || return 0
  awk -v header="[mcp_servers.$SERVER_NAME]" '
    $0 == header { skip = 1; next }
    skip && /^\[/ { skip = 0 }
    !skip
  ' "$CODEX_CONFIG" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' >"$CODEX_CONFIG.tmp" &&
    mv "$CODEX_CONFIG.tmp" "$CODEX_CONFIG"
}

codex_connected() { grep -qxF "[mcp_servers.$SERVER_NAME]" "$CODEX_CONFIG" 2>/dev/null; }

codex_connect() {
  mkdir -p "$(dirname "$CODEX_CONFIG")"
  codex_strip
  [[ -s $CODEX_CONFIG ]] && echo >>"$CODEX_CONFIG"
  cat >>"$CODEX_CONFIG" <<EOF
[mcp_servers.$SERVER_NAME]
url = "$(mcp_url)"
http_headers = { "Authorization" = "Bearer $CE_KEY" }
EOF
  chmod 600 "$CODEX_CONFIG"
}

codex_disconnect() { codex_strip; }

# --- JSON configs: opencode, cursor ------------------------------------------

json_set() {
  local file=$1 filter=$2
  mkdir -p "$(dirname "$file")"
  [[ -f $file ]] || echo '{}' >"$file"
  if ! jq -e . "$file" >/dev/null 2>&1; then
    echo "  $file has comments or is not plain JSON; add the server by hand:" >&2
    jq -n --arg url "$(mcp_url)" --arg auth "Bearer $CE_KEY" "{} | $filter" >&2
    return 1
  fi
  jq --arg name "$SERVER_NAME" --arg url "$(mcp_url)" --arg auth "Bearer $CE_KEY" \
    "$filter" "$file" >"$file.tmp" && cat "$file.tmp" >"$file" && rm "$file.tmp"
  [[ $filter == *'$auth'* ]] && chmod 600 "$file"
  return 0
}

OPENCODE_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json"

opencode_connected() { jq -e --arg n "$SERVER_NAME" '.mcp[$n]' "$OPENCODE_CONFIG" >/dev/null 2>&1; }

opencode_connect() {
  json_set "$OPENCODE_CONFIG" \
    '.mcp[$name] = {type: "remote", url: $url, headers: {Authorization: $auth}, enabled: true}'
}

opencode_disconnect() {
  opencode_connected || return 0
  json_set "$OPENCODE_CONFIG" 'del(.mcp[$name]) | if .mcp == {} then del(.mcp) else . end'
}

CURSOR_CONFIG="$HOME/.cursor/mcp.json"

cursor_connected() { jq -e --arg n "$SERVER_NAME" '.mcpServers[$n]' "$CURSOR_CONFIG" >/dev/null 2>&1; }

cursor_connect() {
  json_set "$CURSOR_CONFIG" '.mcpServers[$name] = {url: $url, headers: {Authorization: $auth}}'
}

cursor_disconnect() {
  cursor_connected || return 0
  json_set "$CURSOR_CONFIG" 'del(.mcpServers[$name])'
}

# --- hermes -----------------------------------------------------------------
# YAML without a YAML tool: our entry sits between markers at the end of the
# file, under its own mcp_servers key. When the file already has mcp_servers
# we cannot merge safely, so we say what to add instead.

HERMES_CONFIG="$HOME/.hermes/config.yaml"
HERMES_BEGIN="# >>> context-engine (managed by ce; edit with ce connect/disconnect)"
HERMES_END="# <<< context-engine"

hermes_strip() {
  [[ -f $HERMES_CONFIG ]] || return 0
  awk -v b="$HERMES_BEGIN" -v e="$HERMES_END" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip
  ' "$HERMES_CONFIG" >"$HERMES_CONFIG.tmp" && mv "$HERMES_CONFIG.tmp" "$HERMES_CONFIG"
}

hermes_connected() { grep -qxF "$HERMES_BEGIN" "$HERMES_CONFIG" 2>/dev/null; }

hermes_connect() {
  mkdir -p "$(dirname "$HERMES_CONFIG")"
  hermes_strip
  if grep -q '^mcp_servers:' "$HERMES_CONFIG" 2>/dev/null; then
    cat >&2 <<EOF
  $HERMES_CONFIG already has mcp_servers; add this under it, then /reload-mcp:
    $SERVER_NAME:
      url: "$(mcp_url)"
      headers:
        Authorization: "Bearer $CE_KEY"
EOF
    return 1
  fi
  cat >>"$HERMES_CONFIG" <<EOF
$HERMES_BEGIN
mcp_servers:
  $SERVER_NAME:
    url: "$(mcp_url)"
    headers:
      Authorization: "Bearer $CE_KEY"
$HERMES_END
EOF
  chmod 600 "$HERMES_CONFIG"
}

hermes_disconnect() { hermes_strip; }

# --- gemini -----------------------------------------------------------------

gemini_connected() { gemini mcp list 2>/dev/null | grep -q "$SERVER_NAME"; }

gemini_connect() {
  gemini mcp remove --scope user "$SERVER_NAME" >/dev/null 2>&1 || true
  gemini mcp add --scope user --transport http "$SERVER_NAME" "$(mcp_url)" \
    -H "Authorization: Bearer $CE_KEY" >/dev/null
}

gemini_disconnect() { gemini mcp remove --scope user "$SERVER_NAME" >/dev/null 2>&1; }

# --- commands ---------------------------------------------------------------

pick_agents() {
  if (($#)); then
    printf '%s\n' "$@"
  else
    local agent
    for agent in "${AGENTS[@]}"; do
      agent_installed "$agent" && echo "$agent"
    done
  fi
}

valid_agent() {
  local agent
  for agent in "${AGENTS[@]}"; do [[ $agent == "$1" ]] && return 0; done
  return 1
}

agents_connect() {
  require_key
  local agent failed=0
  while read -r agent; do
    [[ -n $agent ]] || continue
    valid_agent "$agent" || { echo "  $agent: not an agent ce knows (${AGENTS[*]})" >&2; failed=1; continue; }
    if ! agent_installed "$agent"; then
      echo "  $agent: not installed, skipped"
      continue
    fi
    if "${agent}_connect" </dev/null; then
      echo "  $agent: connected"
    else
      echo "  $agent: needs a hand (see above)"
      failed=1
    fi
  done < <(pick_agents "$@")
  return $failed
}

agents_disconnect() {
  local agent
  while read -r agent; do
    [[ -n $agent ]] || continue
    valid_agent "$agent" || continue
    agent_installed "$agent" || continue
    "${agent}_disconnect" </dev/null || true
    echo "  $agent: disconnected"
  done < <(pick_agents "$@")
}

agents_agents() {
  local agent default state
  default=$(omarchy-default-agent 2>/dev/null || true)
  for agent in "${AGENTS[@]}"; do
    if ! agent_installed "$agent"; then
      state="not installed"
    elif "${agent}_connected"; then
      state="connected"
    else
      state="not connected"
    fi
    printf '  %-9s %s%s\n' "$agent" "$state" "$([[ $agent == "$default" ]] && echo "  (Omarchy default)")"
  done
}
