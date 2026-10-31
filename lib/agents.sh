# Wiring the engine into each coding agent as a remote MCP server.
#
# Sourced by bin/ce. Every agent gets the same server name and the same key,
# sent as a Bearer header to the engine's one shared /mcp address — the key,
# not the address, says which engines it reaches. Each agent keeps its copy in
# its own user-only config, in the format that agent documents (checked
# 2026-10-31; the sources are named per agent below).
#
# The key never goes on a command line, where ps would show it: config files
# are written from the environment or a heredoc, and Claude Code asks
# `ce mcp-headers` for it on each connection.
#
# A server called context-engine that ce did not add is the person's own: ce
# replaces it only when asked, and ce uninstall never touches it.

AGENTS=(claude codex opencode hermes cursor gemini)

mcp_url() { echo "$CE_HOST/mcp"; }

# What to show in place of the key when a person has to add the server by hand.
KEY_HINT="<your key: CE_KEY in $CONFIG_FILE>"

agent_installed() {
  case "$1" in
  cursor) [[ -d $HOME/.cursor ]] || command -v cursor >/dev/null ;;
  *) command -v "$1" >/dev/null ;;
  esac
}

# --- claude -----------------------------------------------------------------
# https://code.claude.com/docs/en/mcp: user scope lives in ~/.claude.json,
# {"type": "http", "url", "headersHelper"}; the helper prints the headers as
# JSON on every connection, so Claude Code keeps no copy of the key.

claude_connected() { claude mcp get "$SERVER_NAME" >/dev/null 2>&1; }

claude_connect() {
  claude mcp remove --scope user "$SERVER_NAME" >/dev/null 2>&1 || true
  claude mcp add-json --scope user "$SERVER_NAME" "$(jq -nc --arg url "$(mcp_url)" \
    --arg helper "$(printf '%q mcp-headers' "$CE_DIR/bin/ce")" \
    '{type: "http", url: $url, headersHelper: $helper}')" >/dev/null
}

# Without the CLI (Claude Code removed since), straight from its user config.
claude_disconnect() {
  if agent_installed claude; then
    claude mcp remove --scope user "$SERVER_NAME" >/dev/null 2>&1 || ! claude_connected
  else
    json_del "${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json" mcpServers
  fi
}

# --- codex ------------------------------------------------------------------
# https://learn.chatgpt.com/docs/config-file/config-reference:
# [mcp_servers.<id>] url + http_headers in $CODEX_HOME/config.toml. A static
# header rather than bearer_token_env_var: agents launched from an Omarchy
# keybinding inherit the Hyprland session's environment, not a shell's.

CODEX_CONFIG="${CODEX_HOME:-$HOME/.codex}/config.toml"
CODEX_BEGIN="# >>> context-engine (managed by ce; edit with ce connect/disconnect)"
CODEX_END="# <<< context-engine"

# Our block between its markers, and an unmarked table of that name (v0.1.0
# wrote one), which is only ever stripped once the person agreed to replace it.
codex_strip() {
  strip_block "$CODEX_CONFIG" "$CODEX_BEGIN" "$CODEX_END"
  codex_connected || return 0
  rewrite "$CODEX_CONFIG" awk -v header="[mcp_servers.$SERVER_NAME]" '
    $0 == header { skip = 1; next }
    skip && /^\[/ { skip = 0 }
    !skip
  ' "$CODEX_CONFIG"
}

codex_connected() { grep -qxF "[mcp_servers.$SERVER_NAME]" "$CODEX_CONFIG" 2>/dev/null; }

codex_connect() {
  new_file "$CODEX_CONFIG"
  keep_mode "$CODEX_CONFIG"
  codex_strip || return 1
  end_line "$CODEX_CONFIG"
  cat >>"$CODEX_CONFIG" <<EOF
$CODEX_BEGIN
[mcp_servers.$SERVER_NAME]
url = "$(mcp_url)"
http_headers = { "Authorization" = "Bearer $CE_KEY" }
$CODEX_END
EOF
  chmod 600 "$CODEX_CONFIG"
}

codex_disconnect() { codex_strip; }

# --- JSON configs: opencode, cursor, gemini ----------------------------------

# json_set <file> <jq filter>: the filter sees $name, $url and env.CE_AUTH.
json_set() {
  local file=$1 filter=$2
  if [[ ! -f $file ]]; then
    new_file "$file"
    echo '{}' >"$file"
  fi
  if ! jq -e . "$file" >/dev/null 2>&1; then
    echo "  $file has comments or is not plain JSON; add the server by hand:" >&2
    CE_AUTH="Bearer $KEY_HINT" jq -n --arg name "$SERVER_NAME" --arg url "$(mcp_url)" "{} | $filter" >&2
    return 1
  fi
  keep_mode "$file"
  rewrite "$file" json_with_key "$filter" "$file" || return 1
  chmod 600 "$file"
}

# The key goes to jq through its environment, which ps does not show.
json_with_key() {
  CE_AUTH="Bearer $CE_KEY" jq --arg name "$SERVER_NAME" --arg url "$(mcp_url)" "$1" "$2"
}

# json_has <file> <key>: the file has our server under that key.
json_has() {
  jq -e --arg n "$SERVER_NAME" --arg k "$2" '.[$k][$n]' "$1" >/dev/null 2>&1
}

# json_del <file> <key>: drop our server, and the object holding it if that
# leaves it empty. A file jq cannot read that still names the server (say the
# person added a comment) fails, so the caller keeps its record.
json_del() {
  if [[ -f $1 ]] && ! jq -e . "$1" >/dev/null 2>&1 && grep -qF "\"$SERVER_NAME\"" "$1"; then
    echo "  $1 is not plain JSON any more; remove $SERVER_NAME from it by hand" >&2
    return 1
  fi
  json_has "$1" "$2" || return 0
  rewrite "$1" jq --arg n "$SERVER_NAME" --arg k "$2" \
    'del(.[$k][$n]) | if .[$k] == {} then del(.[$k]) else . end' "$1"
}

# https://opencode.ai/docs/mcp-servers/: mcp.<name> = {type: "remote", url, headers, enabled}.
OPENCODE_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json"

opencode_connected() { json_has "$OPENCODE_CONFIG" mcp; }

opencode_connect() {
  json_set "$OPENCODE_CONFIG" \
    '.mcp[$name] = {type: "remote", url: $url, headers: {Authorization: env.CE_AUTH}, enabled: true}'
}

opencode_disconnect() { json_del "$OPENCODE_CONFIG" mcp; }

# https://cursor.com/docs/context/mcp: ~/.cursor/mcp.json, mcpServers.<name> = {url, headers}.
CURSOR_CONFIG="$HOME/.cursor/mcp.json"

cursor_connected() { json_has "$CURSOR_CONFIG" mcpServers; }

cursor_connect() {
  json_set "$CURSOR_CONFIG" '.mcpServers[$name] = {url: $url, headers: {Authorization: env.CE_AUTH}}'
}

cursor_disconnect() { json_del "$CURSOR_CONFIG" mcpServers; }

# https://github.com/google-gemini/gemini-cli/blob/main/docs/tools/mcp-server.md:
# ~/.gemini/settings.json, mcpServers.<name> = {httpUrl, headers}; httpUrl is
# streamable HTTP (url would mean SSE). Written directly because
# `gemini mcp add -H` would put the key on its command line.
GEMINI_CONFIG="$HOME/.gemini/settings.json"

gemini_connected() { json_has "$GEMINI_CONFIG" mcpServers; }

gemini_connect() {
  json_set "$GEMINI_CONFIG" '.mcpServers[$name] = {httpUrl: $url, headers: {Authorization: env.CE_AUTH}}'
}

gemini_disconnect() { json_del "$GEMINI_CONFIG" mcpServers; }

# --- hermes -----------------------------------------------------------------
# https://hermes-agent.nousresearch.com/docs/user-guide/features/mcp:
# ~/.hermes/config.yaml, mcp_servers.<name> = {url, headers}.
# YAML without a YAML tool: our entry sits between markers at the end of the
# file, under its own mcp_servers key. When the file already has mcp_servers
# we cannot merge safely, so we say what to add instead.

HERMES_CONFIG="$HOME/.hermes/config.yaml"
HERMES_BEGIN="# >>> context-engine (managed by ce; edit with ce connect/disconnect)"
HERMES_END="# <<< context-engine"

hermes_strip() { strip_block "$HERMES_CONFIG" "$HERMES_BEGIN" "$HERMES_END"; }

hermes_connected() { grep -qxF "$HERMES_BEGIN" "$HERMES_CONFIG" 2>/dev/null; }

hermes_connect() {
  hermes_strip || return 1
  if grep -q '^mcp_servers:' "$HERMES_CONFIG" 2>/dev/null; then
    cat >&2 <<EOF
  $HERMES_CONFIG already has mcp_servers; add this under it, then /reload-mcp:
    $SERVER_NAME:
      url: "$(mcp_url)"
      headers:
        Authorization: "Bearer $KEY_HINT"
EOF
    return 1
  fi
  new_file "$HERMES_CONFIG"
  keep_mode "$HERMES_CONFIG"
  end_line "$HERMES_CONFIG"
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

# Connect one agent, unless it already has a context-engine server that ce
# did not add and the person does not want it replaced.
connect_agent() {
  local agent=$1
  if "${agent}_connected" && ! remembered "agent $agent" &&
    ! ask "$agent already has its own $SERVER_NAME server. Replace it with this computer's key?"; then
    echo "  $agent: already has its own $SERVER_NAME server, left as it is"
    return 0
  fi
  "${agent}_connect" </dev/null || return 1
  remember "agent $agent"
  echo "  $agent: connected"
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
    if ! connect_agent "$agent"; then
      echo "  $agent: needs a hand (see above)"
      failed=1
    fi
  done < <(pick_agents "$@")
  return $failed
}

# v0.1.0 kept no record of what it connected; v0.2.0 starts one at sign-in.
# A signed-in computer with no record is a v0.1.0 install: the agents
# connected then are ce's. Runs once: afterwards the record exists.
adopt_v01() {
  [[ -f $CONFIG_FILE && ! -f $STATE_FILE ]] || return 0
  local agent
  for agent in "${AGENTS[@]}"; do
    agent_installed "$agent" && "${agent}_connected" && remember "agent $agent"
  done
  (
    umask 077
    : >>"$STATE_FILE"
  )
}

# With no names: what ce connected, including agents since uninstalled, whose
# config files still hold the key.
# A name given on the command line is disconnected whoever added it.
agents_disconnect() {
  local agent failed=0
  while read -r agent; do
    [[ -n $agent ]] || continue
    valid_agent "$agent" || continue
    (($#)) || remembered "agent $agent" || continue
    if "${agent}_disconnect" </dev/null; then
      forget "agent $agent"
      echo "  $agent: disconnected"
    else
      echo "  $agent: still connected, needs a hand (see above)"
      failed=1
    fi
  done < <((($#)) && printf '%s\n' "$@" || printf '%s\n' "${AGENTS[@]}")
  return $failed
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

adopt_v01
