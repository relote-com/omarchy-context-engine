#!/bin/bash

# tests/ce.sh — bin/ce and lib/*.sh against stubs, in a throwaway HOME.
#
# No engine and no agents are needed: curl and claude are stubbed, HOSTNAME is
# set, and the other agents only have to be on PATH. Checks the machine stamp on writes
# and in ce brief, that the key never reaches a command line, each agent's
# config format, that a config ce did not write is left alone, and that
# ce uninstall leaves HOME exactly as ce setup found it.
#
# Run: tests/ce.sh

set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CE="$ROOT/bin/ce"
KEY="ce_test_$RANDOM$RANDOM"
MACHINE="test-box"
URL="https://engine.test"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
STUBS="$WORK/stubs"
LOG="$WORK/log"
mkdir -p "$STUBS" "$LOG"

failures=0
pass() { echo "ok   $*"; }
fail() {
  echo "FAIL $*"
  failures=$((failures + 1))
}
check() {
  local name=$1
  shift
  if "$@" >/dev/null; then pass "$name"; else fail "$name"; fi
}

# --- stubs --------------------------------------------------------------------

# curl: logs its arguments and the headers it was handed, answers /tool/<name>
# from the canned replies below, and keeps every write's body.
cat >"$STUBS/curl" <<'EOF'
#!/bin/bash
url="" body="{}"
printf '%s\n' "$*" >>"$CE_TEST_LOG/argv"
while (($#)); do
  case "$1" in
  -H) [[ $2 == @* ]] && cat "${2#@}" >>"$CE_TEST_LOG/headers" || echo "$2" >>"$CE_TEST_LOG/headers"; shift 2 ;;
  --data-binary) body=$2; shift 2 ;;
  http*) url=$1; shift ;;
  *) shift ;;
  esac
done
name=${url##*/tool/}
if [[ $name == write ]]; then
  echo "$body" >>"$CE_TEST_LOG/writes"
  jq -c '{text: "Saved", data: {ref: "\(.type)::saved"}}' <<<"$body"
else
  cat "$CE_TEST_REPLIES/$name.json"
fi
printf '\n200'
EOF

# claude: the subset of `claude mcp` ce uses, kept in $HOME/.claude.json.
cat >"$STUBS/claude" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$CE_TEST_LOG/argv"
file="$HOME/.claude.json"
[[ $1 == mcp ]] || exit 1
case "$2" in
get) jq -e --arg n "$3" '.mcpServers[$n]' "$file" >/dev/null 2>&1 ;;
remove)
  jq -e --arg n "$5" '.mcpServers[$n]' "$file" >/dev/null 2>&1 || exit 1
  jq --arg n "$5" 'del(.mcpServers[$n])' "$file" >"$file.tmp" && mv "$file.tmp" "$file" ;;
add-json)
  [[ -f $file ]] || echo '{}' >"$file"
  jq --arg n "$5" --argjson s "$6" '.mcpServers[$n] = $s' "$file" >"$file.tmp" && mv "$file.tmp" "$file" ;;
*) exit 1 ;;
esac
EOF

# omarchy-shell: logs each IPC call, as the running shell would receive it.
cat >"$STUBS/omarchy-shell" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$CE_TEST_LOG/shell"
EOF

# gum: says which prompts were shown; the key prompt is answered with $CE_TEST_KEY.
cat >"$STUBS/gum" <<'EOF'
#!/bin/bash
printf '%s\n' "$1" >>"$CE_TEST_LOG/gum"
[[ $1 == input ]] && printf '%s\n' "$CE_TEST_KEY"
exit 0
EOF

printf '#!/bin/bash\necho "$*" >>"$CE_TEST_LOG/opened"\n' >"$STUBS/xdg-open"

for agent in codex opencode hermes gemini; do
  printf '#!/bin/bash\nexit 0\n' >"$STUBS/$agent"
done
chmod +x "$STUBS"/*

mkdir -p "$WORK/replies"
cat >"$WORK/replies/brief.json" <<'EOF'
{"text": "# Brief\n\n1 change in Omarchy\n\nNEVER STORE\nSecrets", "data": {
  "engines": [{"slug": "omarchy", "name": "Omarchy", "access": "write"}],
  "since": "2026-10-30T09:00:00Z", "omitted": 2, "unanswered": [{"slug": "work", "name": "Work"}],
  "changed": [{"engine": {"slug": "omarchy", "name": "Omarchy"}, "ref": "note::gaps", "type": "note", "title": "Gaps are 5",
    "updated": "2026-10-31T08:00:00Z", "change": {"act": "edited", "person": "Ada"}}]}}
EOF
cat >"$WORK/replies/find.json" <<'EOF'
{"text": "1 hit", "data": {"hits": [
  {"ref": "note::gaps", "type": "note", "title": "Gaps are 5", "engine": {"slug": "omarchy", "name": "Omarchy"},
   "fields": {"tags": ["omarchy", "machine:air-13"]}},
  {"ref": "note::older", "type": "note", "title": "Older <draft>", "url": "file:///etc/passwd", "engine": {"slug": "omarchy", "name": "Omarchy"},
   "fields": {"tags": ["machine:desk"]}}]}}
EOF

# PATH is the stubs and links to the few tools ce and these tests use, so an
# agent installed on the machine running the tests never counts.
TOOLS="$WORK/tools"
mkdir -p "$TOOLS"
for tool in awk bash cat chmod cmp cp cut date diff dirname find grep head jq ln mkdir mktemp mv \
  readlink rm rmdir script sed sha256sum sort stat tac tail tr wc; do
  ln -s "$(command -v "$tool")" "$TOOLS/$tool" || fail "missing tool: $tool"
done

# A fresh HOME for each scenario.
new_home() {
  export HOME="$WORK/$1"
  mkdir -p "$HOME"
  unset XDG_CONFIG_HOME CODEX_HOME CLAUDE_CONFIG_DIR CE_HOST CE_KEY CE_ENGINE
  export PATH="$STUBS:$TOOLS" CE_TEST_LOG="$LOG" CE_TEST_REPLIES="$WORK/replies" CE_TEST_KEY="$KEY" HOSTNAME="$MACHINE"
}

login() {
  printf '%s' "$KEY" >"$WORK/keyfile"
  "$CE" login --host "$URL" <"$WORK/keyfile" >/dev/null
}

# Every path under HOME with its type, mode, link target and content hash.
# ~/.claude.json is Claude Code's own state, which every claude run rewrites;
# what ce put in it is checked on its own.
tree_of() {
  (
    cd "$HOME" &&
      find . -mindepth 1 ! -path ./.claude.json -printf '%y %m %p -> %l\n' | sort &&
      find . -type f ! -path ./.claude.json -exec sha256sum {} + | sort -k2
  )
}

# --- machine stamp ----------------------------------------------------------

new_home stamp
login
"$CE" remember "Gaps are 5 on the Air" --tag hyprland >/dev/null
check "a write carries the machine as a tag" \
  jq -e --arg m "machine:$MACHINE" '.tags | index($m)' "$LOG/writes"
check "a write keeps its own tags" \
  jq -e '(.tags | index("hyprland")) and (.tags | index("omarchy"))' "$LOG/writes"

brief=$("$CE" brief)
check "ce brief shows which machine saved a change" \
  grep -qF "note::gaps  ←  air-13" <<<"$brief"
check "ce brief lists only what changed" \
  bash -c '! grep -qF "note::older" <<<"$1"' _ "$brief"
styled=$("$CE" find --styled gaps)
check "the overlay's find results show the machine, in italics" grep -qF "· machine:air-13</i>" <<<"$styled"
check "the overlay's find results escape engine text and link only http(s)" \
  bash -c 'grep -qF "<b>Older &lt;draft&gt;</b>" <<<"$1" && ! grep -qF "file:" <<<"$1"' _ "$styled"
check "ce brief is still the engine's brief, as agents read it" grep -qF "NEVER STORE" <<<"$brief"

summary=$("$CE" brief --summary)
check "ce brief --summary lists each change for a person" \
  grep -qxF "  note · Omarchy · 2026-10-31 · edited by Ada · from air-13" <<<"$summary"
check "ce brief --summary says since when, what was left out and who did not answer" \
  bash -c 'grep -qF "since you last looked (2026-10-30)" <<<"$1" && grep -qF "and 2 more" <<<"$1" && grep -qF "Work did not answer" <<<"$1"' _ "$summary"
check "ce brief --summary leaves out the agents' instructions" \
  bash -c '! grep -qE "NEVER STORE|# Brief" <<<"$1"' _ "$summary"

# --- the bar icon hears about sign-in and sign-out -------------------------

check "ce login refreshes the bar icon" grep -qxF -- "-q relote.context-engine refresh" "$LOG/shell"
: >"$LOG/shell"
"$CE" logout >/dev/null
check "ce logout refreshes the bar icon" grep -qxF -- "-q relote.context-engine refresh" "$LOG/shell"
login

# --- the key stays off command lines ---------------------------------------

check "the key reaches curl as a header" grep -qF "authorization: Bearer $KEY" "$LOG/headers"
check "the key is in no command line" bash -c '! grep -qF "$1" "$2"' _ "$KEY" "$LOG/argv"
check "the key file is 0600" test "$(stat -c %a "$HOME/.config/context-engine/config")" = 600

# --- setup with consent: a fresh machine, nothing to keep --------------------

new_home fresh
mkdir -p "$HOME/.cursor" "$HOME/.claude" "$HOME/.config/hypr"
printf 'source = ~/.config/hypr/mine.conf\n' >"$HOME/.config/hypr/hyprland.lua"
before=$(tree_of)
login
"$CE" setup --yes >"$LOG/setup-fresh" 2>&1 || fail "ce setup --yes exited $?"

server='context-engine'
check "claude: http server whose headers come from ce mcp-headers" \
  jq -e --arg n "$server" --arg url "$URL/mcp" \
  '.mcpServers[$n] | .type == "http" and .url == $url and (.headersHelper | endswith("bin/ce mcp-headers")) and (has("headers") | not)' \
  "$HOME/.claude.json"
check "claude: ce mcp-headers prints the bearer header" \
  bash -c '[[ $("$1" mcp-headers | jq -r .Authorization) == "Bearer $2" ]]' _ "$CE" "$KEY"
check "codex: [mcp_servers] table with url and http_headers" \
  grep -qzF "[mcp_servers.$server]"$'\n'"url = \"$URL/mcp\""$'\n'"http_headers = { \"Authorization\" = \"Bearer $KEY\" }" \
  "$HOME/.codex/config.toml"
check "opencode: remote server under mcp" \
  jq -e --arg n "$server" --arg url "$URL/mcp" --arg auth "Bearer $KEY" \
  '.mcp[$n] == {type: "remote", url: $url, headers: {Authorization: $auth}, enabled: true}' \
  "$HOME/.config/opencode/opencode.json"
check "cursor: url and headers under mcpServers" \
  jq -e --arg n "$server" --arg url "$URL/mcp" --arg auth "Bearer $KEY" \
  '.mcpServers[$n] == {url: $url, headers: {Authorization: $auth}}' "$HOME/.cursor/mcp.json"
check "gemini: httpUrl (streamable HTTP) and headers under mcpServers" \
  jq -e --arg n "$server" --arg url "$URL/mcp" --arg auth "Bearer $KEY" \
  '.mcpServers[$n] == {httpUrl: $url, headers: {Authorization: $auth}}' "$HOME/.gemini/settings.json"
check "hermes: mcp_servers entry with url and headers" \
  grep -qzF $'mcp_servers:\n'"  $server:"$'\n'"    url: \"$URL/mcp\""$'\n    headers:\n'"      Authorization: \"Bearer $KEY\"" \
  "$HOME/.hermes/config.yaml"
for file in .codex/config.toml .config/opencode/opencode.json .cursor/mcp.json .gemini/settings.json .hermes/config.yaml; do
  check "$file holding the key is 0600" test "$(stat -c %a "$HOME/$file")" = 600
done
check "skill linked where the agent lives" test -L "$HOME/.claude/skills/context-engine"
check "menu rows added" grep -qF '"context-engine.find"' "$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
check "keys and hook added with --yes" \
  test -f "$HOME/.config/hypr/context_engine.lua" -a -x "$HOME/.config/omarchy/hooks/post-update.d/context-engine"
check "the key is in no command line during setup" bash -c '! grep -qF "$1" "$2"' _ "$KEY" "$LOG/argv"

# An agent removed after setup still has the key in its config: uninstall
# takes it out anyway.
mv "$STUBS/codex" "$WORK/codex.away"
mv "$STUBS/claude" "$WORK/claude.away"
"$CE" uninstall >"$LOG/uninstall-fresh" 2>&1 || fail "ce uninstall exited $?"
mv "$WORK/codex.away" "$STUBS/codex"
mv "$WORK/claude.away" "$STUBS/claude"
after=$(tree_of)
check "claude: the server is gone again" \
  jq -e --arg n "$server" '.mcpServers | has($n) | not' "$HOME/.claude.json"
check "ce uninstall refreshes the bar icon" grep -qxF -- "-q relote.context-engine refresh" "$LOG/shell"
check "ce uninstall leaves HOME exactly as before ce setup" test "$before" = "$after"
[[ $before == "$after" ]] || diff <(echo "$before") <(echo "$after")

# --- setup --yes in a terminal: the key prompt is the only question ---------

new_home terminal
: >"$LOG/gum"
script -qec "$CE setup --yes" /dev/null >"$LOG/setup-terminal" 2>&1 || fail "ce setup --yes in a terminal exited $?"
check "ce setup --yes signs in from the key prompt" grep -qF "CE_KEY=$KEY" "$HOME/.config/context-engine/config"
check "ce setup --yes asks nothing else, not even to open the browser" \
  bash -c '[[ $(cat "$1") == input ]]' _ "$LOG/gum"
"$CE" uninstall >/dev/null 2>&1

# --- setup without consent: configs the person already has -------------------

new_home lived-in
mkdir -p "$HOME/.cursor" "$HOME/.codex" "$HOME/.config/opencode" "$HOME/.local/bin"
mine='{"mcpServers":{"context-engine":{"url":"https://example.org/mcp"},"other":{"url":"https://other.example/mcp"}}}'
jq . <<<"$mine" >"$HOME/.cursor/mcp.json"
jq . <<<'{"theme":"dark","mcp":{"other":{"type":"local","command":["x"]}}}' >"$HOME/.config/opencode/opencode.json"
printf 'model = "gpt"\n\n[mcp_servers.other]\nurl = "https://other.example/mcp"\n' >"$HOME/.codex/config.toml"
chmod 644 "$HOME/.codex/config.toml" "$HOME/.config/opencode/opencode.json"
printf '#!/bin/sh\necho mine\n' >"$HOME/.local/bin/ce"
chmod +x "$HOME/.local/bin/ce"
before=$(tree_of)
login
"$CE" setup </dev/null >"$LOG/setup-lived-in" 2>&1

check "cursor: a context-engine server ce did not add is kept without consent" \
  jq -e '.mcpServers["context-engine"] == {url: "https://example.org/mcp"}' "$HOME/.cursor/mcp.json"
check "another ce on PATH is kept" grep -qF 'echo mine' "$HOME/.local/bin/ce"
check "opencode: merged next to the person's settings" \
  jq -e '.theme == "dark" and .mcp.other and .mcp["context-engine"]' "$HOME/.config/opencode/opencode.json"
check "codex: appended after the person's settings" \
  bash -c 'head -4 "$1" | cmp -s - <(printf "model = \"gpt\"\n\n[mcp_servers.other]\nurl = \"https://other.example/mcp\"\n")' _ "$HOME/.codex/config.toml"
check "the menu runs the plugin's ce, not another ce on PATH" \
  bash -c 'grep -qF "$1/bin/ce setup" "$2" && ! grep -qF "$3 setup" "$2"' _ "$ROOT" \
  "$HOME/.config/omarchy/extensions/omarchy-menu.jsonc" "$HOME/.local/bin/ce"
check "keys and hook are not added without a yes" \
  test ! -e "$HOME/.config/hypr/context_engine.lua" -a ! -e "$HOME/.config/omarchy/hooks/post-update.d/context-engine"

"$CE" uninstall >"$LOG/uninstall-lived-in" 2>&1 || fail "ce uninstall exited $?"
after=$(tree_of)
check "ce uninstall leaves a lived-in HOME exactly as before" test "$before" = "$after"
[[ $before == "$after" ]] || diff <(echo "$before") <(echo "$after")

# --- a config jq cannot change -----------------------------------------------

new_home odd
echo '["not", "an", "object"]' >"$WORK/odd.json"
mkdir -p "$HOME/.config/opencode"
cp "$WORK/odd.json" "$HOME/.config/opencode/opencode.json"
login
"$CE" connect opencode >"$LOG/connect-odd" 2>&1
check "a config jq cannot change is left exactly as it was" \
  cmp -s "$WORK/odd.json" "$HOME/.config/opencode/opencode.json"
check "and ce says the agent needs a hand" grep -qF "opencode: needs a hand" "$LOG/connect-odd"
check "no staging file is left next to it" \
  test -z "$(find "$HOME/.config/opencode" -name 'opencode.json.*')"

# --- a config that stops being plain JSON after connect ----------------------

new_home commented
mkdir -p "$HOME/.cursor"
login
"$CE" connect cursor >/dev/null 2>&1
sed -i '1a // my comment' "$HOME/.cursor/mcp.json"
"$CE" disconnect >"$LOG/disconnect-commented" 2>&1
check "disconnect says it could not remove the server" grep -qF "cursor: still connected" "$LOG/disconnect-commented"
check "and keeps its record, so uninstall can try again" \
  grep -qxF "agent cursor" "$HOME/.config/context-engine/installed"
"$CE" uninstall >"$LOG/uninstall-commented" 2>&1
check "uninstall fails while an agent still holds the key" test $? -ne 0
check "and keeps the record and the key file for the next try" \
  test -f "$HOME/.config/context-engine/installed" -a -f "$HOME/.config/context-engine/config"

# --- a v0.1.0 install: signed in, nothing recorded ---------------------------

new_home v01
mkdir -p "$HOME/.codex" "$HOME/.config/context-engine"
printf 'CE_HOST=%s\nCE_KEY=%s\nCE_ENGINE=omarchy\n' "$URL" "$KEY" >"$HOME/.config/context-engine/config"
printf 'model = "gpt"\n\n[mcp_servers.context-engine]\nurl = "%s/mcp"\n' "$URL" >"$HOME/.codex/config.toml"
"$CE" uninstall >"$LOG/uninstall-v01" 2>&1
check "v0.1.0's codex server is taken as ce's and removed" \
  bash -c '! grep -qF "[mcp_servers.context-engine]" "$1"' _ "$HOME/.codex/config.toml"
check "the person's codex settings stay" grep -qxF 'model = "gpt"' "$HOME/.codex/config.toml"

# --- the plugin folder -------------------------------------------------------

check "no symlinks in the plugin folder" \
  test -z "$(find "$ROOT" -path "$ROOT/.git" -prune -o -type l -print)"
check "manifest and README say the same version" \
  grep -qF "$(jq -r .version "$ROOT/manifest.json")" "$ROOT/README.md"

echo
if ((failures)); then
  echo "$failures failed"
  exit 1
fi
echo "all passed"
