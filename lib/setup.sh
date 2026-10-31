# ce setup / ce uninstall — everything outside the plugin folder that makes the
# engine part of the desktop. Sourced by bin/ce after lib/agents.sh.
#
# Each step only touches files it can name, marks what it adds, remembers in
# $STATE_FILE what it created, and is undone by ce uninstall. A file that is
# not ce's (another `ce` on PATH, a skill of the same name) is left alone.
# Re-running setup is safe.

BIN_LINK="$HOME/.local/bin/ce"
# What the menu and the hook run: the plugin's own ce, whatever else is on PATH.
CE_BIN="$CE_DIR/bin/ce"
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

# ce_wrote <file>: the file says ce setup wrote it (the keys and the hook do).
ce_wrote() {
  grep -qi 'written by ce setup' "$1" 2>/dev/null
}

# ours <link> <target>: the link exists and points where ce points it.
ours() {
  [[ -L $1 && $(readlink "$1") == "$2" ]]
}

link_bin() {
  if [[ -e $BIN_LINK || -L $BIN_LINK ]] && ! ours "$BIN_LINK" "$CE_DIR/bin/ce"; then
    echo "  $BIN_LINK is something else; left as it is (run $CE_DIR/bin/ce directly)"
    return 0
  fi
  mkdirs "$(dirname "$BIN_LINK")"
  ln -sfn "$CE_DIR/bin/ce" "$BIN_LINK"
  echo "  ce → $BIN_LINK"
  [[ :$PATH: == *":$HOME/.local/bin:"* ]] || echo "  (add ~/.local/bin to PATH to type ce anywhere)"
}

install_skill() {
  local dir
  for dir in "${SKILL_DIRS[@]}"; do
    # Only where that agent lives; a folder for an agent you do not have is clutter.
    [[ -d $(dirname "$dir") ]] || continue
    if [[ -e $dir/context-engine || -L $dir/context-engine ]] && ! ours "$dir/context-engine" "$SKILL_SRC"; then
      echo "  $dir/context-engine is another skill; left as it is"
      continue
    fi
    mkdirs "$dir"
    ln -sfn "$SKILL_SRC" "$dir/context-engine"
    echo "  skill → $dir/context-engine"
  done
}

remove_skill() {
  local dir
  for dir in "${SKILL_DIRS[@]}"; do
    ours "$dir/context-engine" "$SKILL_SRC" && rm "$dir/context-engine"
  done
  return 0
}

# Menu rows go right after the opening brace: the shell's JSONC reader drops
# whole-line comments and trailing commas, so our block, commas and all, parses
# whatever the person has below it.
install_menu() {
  if [[ ! -f $MENU_FILE ]]; then
    new_file "$MENU_FILE"
    printf '{\n}\n' >"$MENU_FILE"
  fi
  remove_menu
  local block
  block=$(cat <<EOF
$MENU_BEGIN
  "context-engine": {"icon":"󰧑","label":"Context Engine","description":"Memory shared by every agent","aliases":["memory","brain"]},
  "context-engine.find": {"icon":"","label":"Find in memory","action":"omarchy-shell shell summon $PLUGIN_ID '{\"mode\":\"find\"}'"},
  "context-engine.ask": {"icon":"󰚩","label":"Ask your agent","description":"Opens your default agent, which reads the engine","action":"omarchy-shell shell summon $PLUGIN_ID '{\"mode\":\"ask\"}'"},
  "context-engine.remember": {"icon":"󰆓","label":"Remember…","action":"omarchy-shell shell summon $PLUGIN_ID '{\"mode\":\"remember\"}'"},
  "context-engine.brief": {"icon":"󰃭","label":"What changed","action":"omarchy-shell shell summon $PLUGIN_ID '{\"mode\":\"brief\"}'"},
  "context-engine.agents": {"icon":"󰚩","label":"Connect agents","action":"omarchy-launch-floating-terminal-with-presentation '$CE_BIN connect; $CE_BIN agents'"},
  "context-engine.setup": {"icon":"","label":"Setup","action":"omarchy-launch-floating-terminal-with-presentation '$CE_BIN setup'"},
  "context-engine.console": {"icon":"󰖟","label":"Open console","action":"$CE_BIN open"},
$MENU_END
EOF
)
  # Through the environment, not awk -v, which would eat the JSON's backslashes.
  CE_MENU_BLOCK=$block rewrite "$MENU_FILE" awk '
    !done && /^[[:space:]]*\{[[:space:]]*$/ { print; print ENVIRON["CE_MENU_BLOCK"]; done = 1; next }
    { print }
  ' "$MENU_FILE"
  echo "  menu → Omarchy menu › Context Engine"
}

remove_menu() { strip_block "$MENU_FILE" "$MENU_BEGIN" "$MENU_END"; }

install_keys() {
  if [[ -e $HYPR_FILE ]] && ! ce_wrote "$HYPR_FILE"; then
    echo "  $HYPR_FILE is not ce's; keys left as they are"
    return 0
  fi
  new_file "$HYPR_FILE"
  cat >"$HYPR_FILE" <<EOF
-- Context Engine (written by ce setup; removed by ce uninstall)
o.bind("SUPER + CTRL + M", "Context Engine: find", "omarchy-shell shell toggle $PLUGIN_ID '{\"mode\":\"find\"}'")
o.bind("SUPER + ALT + M", "Context Engine: remember", "omarchy-shell shell toggle $PLUGIN_ID '{\"mode\":\"remember\"}'")
EOF
  # One line at the end, removed again by ce uninstall.
  if [[ -f $HYPR_MAIN ]] && ! grep -qF 'require("hypr.context_engine")' "$HYPR_MAIN"; then
    end_line "$HYPR_MAIN"
    printf '%s\n' "$HYPR_REQUIRE" >>"$HYPR_MAIN"
  fi
  if command -v hyprctl >/dev/null && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    hyprctl reload >/dev/null 2>&1 || true
    local errors
    errors=$(hyprctl configerrors 2>/dev/null | grep -v '^$' || true)
    [[ -n $errors ]] && echo "  Hyprland reported: $errors" >&2
  fi
  echo "  keys → Super+Ctrl+M find, Super+Alt+M remember"
}

# The require line carries ce's own comment, so an exact match is ce's line
# (v0.1.0's included), and it goes together with the file it loads.
remove_keys() {
  if [[ -f $HYPR_MAIN ]] && grep -qxF "$HYPR_REQUIRE" "$HYPR_MAIN"; then
    rewrite "$HYPR_MAIN" without_line "$HYPR_REQUIRE" "$HYPR_MAIN"
  fi
  ce_wrote "$HYPR_FILE" && rm "$HYPR_FILE"
  return 0
}

install_hook() {
  if [[ -e $HOOK_FILE ]] && ! ce_wrote "$HOOK_FILE"; then
    echo "  $HOOK_FILE is not ce's; hook left as it is"
    return 0
  fi
  new_file "$HOOK_FILE"
  cat >"$HOOK_FILE" <<EOF
#!/bin/bash
# Context Engine: note each Omarchy update, so "when did this start?" has an answer.
# Written by ce setup; removed by ce uninstall.
"$CE_BIN" remember --quiet --tag omarchy-update \\
  "Updated Omarchy to \$(omarchy-version 2>/dev/null || cat "\$OMARCHY_PATH/version") on \$(uname -n)" \\
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
  if omarchy-plugin-enable "$PLUGIN_ID" --section right >/dev/null 2>&1; then
    remember "plugin enabled"
    echo "  bar → $PLUGIN_ID enabled"
  else
    echo "  bar → enable it with: omarchy plugin enable $PLUGIN_ID"
  fi
}

setup_setup() {
  # shellcheck disable=SC2034 # read by ask() in bin/ce
  [[ ${1:-} == --yes || ${1:-} == -y ]] && ASSUME_YES=1

  echo "Context Engine for Omarchy"

  step "1. The ce command"
  link_bin

  step "2. Sign in"
  if [[ -n $CE_KEY ]] && tool brief >/dev/null 2>&1; then
    echo "  already signed in (saving to ${CE_ENGINE:-?})"
  else
    # A key can be piped in; a terminal that cannot show a prompt cannot ask.
    [[ -t 0 ]] && ! interactive && die "sign in first: ce login <keyfile"
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

# remove_made <state>: a file ce made goes only once nothing but ce's own
# skeleton is left in it; a directory ce made goes only once it is empty.
# Newest first, so a directory is emptied before it is tried.
remove_made() {
  local path
  while read -r path; do
    if [[ -d $path ]]; then
      rmdir "$path" 2>/dev/null || true
    elif [[ -f $path ]] && [[ ! -s $path || $(tr -d '[:space:]' <"$path") == "{}" ]]; then
      rm "$path"
    fi
  done < <(sed -n 's/^made //p' <<<"$1" | tac)
}

restore_modes() {
  local path mode
  while read -r path mode; do
    [[ -f $path ]] && chmod "$mode" "$path"
  done < <(sed -n 's/^mode \(.*\) \([0-7]*\)$/\1 \2/p' "$STATE_FILE")
}

setup_uninstall() {
  local stuck=0
  agents_disconnect || stuck=1
  remove_skill
  remove_menu
  remove_keys
  ce_wrote "$HOOK_FILE" && rm "$HOOK_FILE"
  ours "$BIN_LINK" "$CE_DIR/bin/ce" && rm "$BIN_LINK"
  if remembered "plugin enabled" && command -v omarchy-plugin-disable >/dev/null; then
    omarchy-plugin-disable "$PLUGIN_ID" >/dev/null 2>&1 || true
  fi
  # An agent still holding the key keeps the record and the key file, so the
  # next ce uninstall can finish the job once it is fixed by hand.
  if ((stuck)); then
    echo "Some agents still have the key (see above). Fix those, then run ce uninstall again."
    return 1
  fi
  if [[ -f $STATE_FILE ]]; then
    restore_modes
    rm -f "$CONFIG_FILE"
    local state
    state=$(cat "$STATE_FILE")
    rm "$STATE_FILE"
    remove_made "$state"
  fi
  refresh_bar
  echo "Removed from agents, skills, menu, keys and hooks."
  [[ -f $CONFIG_FILE ]] && echo "Your key stays in $CONFIG_FILE until: ce logout"
  echo "Remove the plugin itself with: omarchy plugin remove $PLUGIN_ID"
}
