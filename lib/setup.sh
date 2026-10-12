# ce setup / ce uninstall — everything outside the plugin folder that makes the
# engine part of the desktop. Sourced by bin/ce after lib/agents.sh.
#
# Each step only touches files it can name, marks what it adds, and is undone
# by ce uninstall. Re-running setup is safe.

PLUGIN_ID=$(jq -r '.id' "$CE_DIR/manifest.json")
BIN_LINK="$HOME/.local/bin/ce"
SKILL_SRC="$CE_DIR/skills/context-engine"
# The same skill folders Omarchy links its own skills into, plus OpenCode's.
SKILL_DIRS=(
  "$HOME/.agents/skills"
  "$HOME/.claude/skills"
  "$HOME/.codex/skills"
  "$HOME/.pi/agent/skills"
  "$HOME/.hermes/skills"
  "$HOME/.gemini/config/skills"
  "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills"
)
MENU_FILE="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
MENU_BEGIN="  // >>> context-engine (managed by ce setup)"
MENU_END="  // <<< context-engine"
HYPR_FILE="$HOME/.config/hypr/context_engine.lua"
HYPR_MAIN="$HOME/.config/hypr/hyprland.lua"
HYPR_REQUIRE='require("hypr.context_engine") -- Context Engine (ce setup)'
HOOK_FILE="$HOME/.config/omarchy/hooks/post-update.d/context-engine"

step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

ask() {
  local question=$1
  ((ASSUME_YES)) && return 0
  interactive || return 1
  gum confirm "$question"
}

link_bin() {
  mkdir -p "$(dirname "$BIN_LINK")"
  ln -sfn "$CE_DIR/bin/ce" "$BIN_LINK"
  echo "  ce → $BIN_LINK"
  [[ :$PATH: == *":$HOME/.local/bin:"* ]] || echo "  (add ~/.local/bin to PATH to type ce anywhere)"
}

install_skill() {
  local dir
  for dir in "${SKILL_DIRS[@]}"; do
    # Only where that agent lives; a folder for an agent you do not have is clutter.
    [[ -d $(dirname "$dir") ]] || continue
    mkdir -p "$dir"
    ln -sfn "$SKILL_SRC" "$dir/context-engine"
    echo "  skill → $dir/context-engine"
  done
}

remove_skill() {
  local dir
  for dir in "${SKILL_DIRS[@]}"; do
    [[ -L $dir/context-engine ]] && rm "$dir/context-engine"
  done
  return 0
}

# Menu rows go right after the opening brace: the shell's JSONC reader drops
# whole-line comments and trailing commas, so our block, commas and all, parses
# whatever the person has below it.
install_menu() {
  mkdir -p "$(dirname "$MENU_FILE")"
  [[ -f $MENU_FILE ]] || printf '{\n}\n' >"$MENU_FILE"
  remove_menu
  local block
  block=$(cat <<EOF
$MENU_BEGIN
  "context-engine": {"icon":"󰧑","label":"Context Engine","description":"Memory shared by every agent","aliases":["memory","brain"]},
  "context-engine.find": {"icon":"","label":"Find in memory","action":"omarchy-shell shell summon $PLUGIN_ID '{\"mode\":\"find\"}'"},
  "context-engine.ask": {"icon":"󰚩","label":"Ask your agent","description":"Opens your default agent, which reads the engine","action":"omarchy-shell shell summon $PLUGIN_ID '{\"mode\":\"ask\"}'"},
  "context-engine.remember": {"icon":"󰆓","label":"Remember…","action":"omarchy-shell shell summon $PLUGIN_ID '{\"mode\":\"remember\"}'"},
  "context-engine.brief": {"icon":"󰃭","label":"What changed","action":"omarchy-shell shell summon $PLUGIN_ID '{\"mode\":\"brief\"}'"},
  "context-engine.agents": {"icon":"󰚩","label":"Connect agents","action":"omarchy-launch-floating-terminal-with-presentation '$BIN_LINK connect; $BIN_LINK agents'"},
  "context-engine.setup": {"icon":"","label":"Setup","action":"omarchy-launch-floating-terminal-with-presentation '$BIN_LINK setup'"},
  "context-engine.console": {"icon":"󰖟","label":"Open console","action":"$BIN_LINK open"},
$MENU_END
EOF
)
  # Through the environment, not awk -v, which would eat the JSON's backslashes.
  CE_MENU_BLOCK=$block awk '
    !done && /^[[:space:]]*\{[[:space:]]*$/ { print; print ENVIRON["CE_MENU_BLOCK"]; done = 1; next }
    { print }
  ' "$MENU_FILE" >"$MENU_FILE.tmp" && mv "$MENU_FILE.tmp" "$MENU_FILE"
  echo "  menu → Omarchy menu › Context Engine"
}

remove_menu() {
  [[ -f $MENU_FILE ]] || return 0
  awk -v b="$MENU_BEGIN" -v e="$MENU_END" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip
  ' "$MENU_FILE" >"$MENU_FILE.tmp" && mv "$MENU_FILE.tmp" "$MENU_FILE"
}

install_keys() {
  cat >"$HYPR_FILE" <<EOF
-- Context Engine (written by ce setup; removed by ce uninstall)
o.bind("SUPER + CTRL + M", "Context Engine: find", "omarchy-shell shell toggle $PLUGIN_ID '{\"mode\":\"find\"}'")
o.bind("SUPER + ALT + M", "Context Engine: remember", "omarchy-shell shell toggle $PLUGIN_ID '{\"mode\":\"remember\"}'")
EOF
  if [[ -f $HYPR_MAIN ]] && ! grep -qF 'require("hypr.context_engine")' "$HYPR_MAIN"; then
    cp "$HYPR_MAIN" "$HYPR_MAIN.bak.$(date +%s)"
    printf '\n%s\n' "$HYPR_REQUIRE" >>"$HYPR_MAIN"
  fi
  if command -v hyprctl >/dev/null && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    hyprctl reload >/dev/null 2>&1 || true
    local errors
    errors=$(hyprctl configerrors 2>/dev/null | grep -v '^$' || true)
    [[ -n $errors ]] && echo "  Hyprland reported: $errors" >&2
  fi
  echo "  keys → Super+Ctrl+M find, Super+Alt+M remember"
}

remove_keys() {
  [[ -f $HYPR_MAIN ]] && grep -qF "$HYPR_REQUIRE" "$HYPR_MAIN" &&
    grep -vxF "$HYPR_REQUIRE" "$HYPR_MAIN" >"$HYPR_MAIN.tmp" && mv "$HYPR_MAIN.tmp" "$HYPR_MAIN"
  rm -f "$HYPR_FILE"
}

install_hook() {
  mkdir -p "$(dirname "$HOOK_FILE")"
  cat >"$HOOK_FILE" <<EOF
#!/bin/bash
# Context Engine: note each Omarchy update, so "when did this start?" has an answer.
# Written by ce setup; removed by ce uninstall.
"$BIN_LINK" remember --quiet --tag omarchy-update \\
  "Updated Omarchy to \$(omarchy-version 2>/dev/null || cat "\$OMARCHY_PATH/version") on \$(hostname)" \\
  >/dev/null 2>&1 || true
EOF
  chmod +x "$HOOK_FILE"
  echo "  hook → post-update"
}

enable_plugin() {
  command -v omarchy-plugin-list >/dev/null || return 0
  if omarchy-plugin-list --json 2>/dev/null | jq -e --arg id "$PLUGIN_ID" 'any(.[]; .id == $id and .enabled)' >/dev/null; then
    return 0
  fi
  omarchy-plugin-enable "$PLUGIN_ID" --section right >/dev/null 2>&1 &&
    echo "  bar → $PLUGIN_ID enabled" ||
    echo "  bar → enable it with: omarchy plugin enable $PLUGIN_ID"
}

setup_setup() {
  ASSUME_YES=0
  [[ ${1:-} == --yes || ${1:-} == -y ]] && ASSUME_YES=1

  echo "Context Engine for Omarchy"

  step "1. The ce command"
  link_bin

  step "2. Sign in"
  if [[ -n $CE_KEY ]] && tool brief >/dev/null 2>&1; then
    echo "  already signed in (saving to ${CE_ENGINE:-?})"
  else
    cmd_login
    load_config
  fi

  step "3. Coding agents"
  agents_connect || true

  step "4. Agent skill"
  install_skill

  step "5. Omarchy"
  install_menu
  enable_plugin
  if ask "Add Super+Ctrl+M (find) and Super+Alt+M (remember)?"; then
    install_keys
  fi
  if ask "Note each Omarchy update in your engine?"; then
    install_hook
  fi

  step "Done"
  cat <<EOF
  Every agent Omarchy launches now shares your engine. Try:
    omarchy agent prompt "What do you remember about my setup?"
    ce remember "Gaps are 5 because 10 wasted space on the Air"
    ce find gaps
EOF
}

setup_uninstall() {
  agents_disconnect
  remove_skill
  remove_menu
  remove_keys
  rm -f "$HOOK_FILE"
  [[ -L $BIN_LINK ]] && rm "$BIN_LINK"
  echo "Removed from agents, menu, keys and hooks. Your key stays in $CONFIG_FILE until: ce logout"
  echo "Remove the plugin itself with: omarchy plugin remove $PLUGIN_ID"
}
