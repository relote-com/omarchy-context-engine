# Context Engine for Omarchy

One memory for every agent on your Omarchy machine.

Omarchy can launch Claude Code, Codex, OpenCode, Hermes and more from one
keybinding, and each of them normally starts from nothing. This plugin
connects all of them to the same [Context Engine](https://contextengine.com),
so a decision one agent saves on Monday is something another agent already
knows on Friday. It also puts that memory on the desktop: a bar icon, a
find/remember box on a hotkey, and entries in the Omarchy menu.

```
 ┌──────────── Omarchy ────────────┐
 │  bar icon · Super+Ctrl+M · menu │──┐
 │  claude  codex  opencode  hermes│──┼──▶  Context Engine  ◀── ChatGPT, Claude,
 │  (one skill, one MCP server)    │──┘     (your engines)      Cursor, your team
 └─────────────────────────────────┘
```

## Install

```bash
omarchy plugin add https://github.com/relote-com/omarchy-context-engine.git --enable
~/.config/omarchy/plugins/relote.context-engine/bin/ce setup
```

`ce setup` walks you through it:

1. Links `ce` into `~/.local/bin`.
2. Signs in. Make a key at [app.contextengine.com](https://app.contextengine.com):
   **AI tools → Connect an AI tool → Your own code → Create my key**, with
   *Can read and save* on the engines Omarchy should use. The free plan is
   enough (3 engines).
3. Connects every installed coding agent to the engine over MCP.
4. Installs the `context-engine` skill into each agent's skill folder, next to
   Omarchy's own, so agents know when to read and save.
5. Adds **Context Engine** to the Omarchy menu and, if you agree, two keys and
   a post-update hook.

Not set up yet? Click the dimmed brain icon in the bar and it opens setup.

## Use it

| Where | What |
| --- | --- |
| Bar icon | Click to find, right-click to remember, middle-click for what changed |
| `Super+Ctrl+M` | Find in memory (Tab switches to Remember, Ask, What changed) |
| `Super+Alt+M` | Remember something. The first line is the title |
| Omarchy menu › Context Engine | Find, remember, what changed, connect agents, setup |
| Any agent | Just ask: "what did we decide about the gaps?" The skill has it check the engine first |

From a terminal:

```bash
ce brief                                   # what changed since you last looked
ce find "hyprland gaps"                    # search across your engines
ce remember "Gaps are 5 on the Air" --decision --why "10 wasted space on a 13in screen"
git log -1 --format=%B | ce remember --tag release
ce ask "what's still open on the Acme install?"   # the engine's own agent (metered)
ce engine acme                             # save to another engine by default
ce agents                                  # which agents are connected
```

## What it changes on your machine

Everything outside the plugin folder is written by `ce setup` and removed by
`ce uninstall`:

| File | What |
| --- | --- |
| `~/.config/context-engine/config` | Your key and default engine (mode 600) |
| `~/.local/bin/ce` | Symlink to the plugin's `bin/ce` |
| Claude Code (`claude mcp add --scope user`) | `context-engine` MCP server |
| `~/.codex/config.toml` | `[mcp_servers.context-engine]` |
| `~/.config/opencode/opencode.json` | `mcp.context-engine` |
| `~/.hermes/config.yaml` | `mcp_servers.context-engine` between marker comments |
| `~/.cursor/mcp.json`, Gemini CLI | the same server, if installed |
| `~/.agents/skills`, `~/.claude/skills`, … | `context-engine` skill symlink |
| `~/.config/omarchy/extensions/omarchy-menu.jsonc` | Menu rows between marker comments |
| `~/.config/hypr/context_engine.lua` + one `require` line | The two keys (opt-in) |
| `~/.config/omarchy/hooks/post-update.d/context-engine` | Records Omarchy updates (opt-in) |

Every agent gets the same key as a Bearer header to
`https://app.contextengine.com/mcp`, and the key decides which engines they
reach. Writes are credited to you. To give agents read-only access, make a
key with *Can read* and run `ce login` again.

## How it works

- **`bin/ce`** is a small bash client for the engine's plain HTTP door,
  `POST /tool/<name>` (`brief`, `find`, `get`, `write`, `edit`), plus the
  OpenAI-compatible `/v1/chat/completions` for `ce ask`. It needs only
  `curl`, `jq` and `gum`, which Omarchy already ships.
- **`Overlay.qml`** and **`BarWidget.qml`** are an Omarchy shell plugin
  (`overlay` + `bar-widget`). They hold no key and make no HTTP calls
  themselves. They run `bin/ce`.
- **`skills/context-engine/SKILL.md`** tells any agent to call `brief` at the
  start of a session, `find` before answering about the past, and to save a
  `decision` whenever it changes the system, with the old value, the new
  value and the reason. That is what turns "why is my gap 5?" into a question
  with an answer, on this machine and on your others.

## Develop

```bash
git clone https://github.com/relote-com/omarchy-context-engine.git
ln -s "$PWD/omarchy-context-engine" ~/.config/omarchy/plugins/relote.context-engine
omarchy-shell shell rescanPlugins && omarchy plugin enable relote.context-engine
omarchy plugin validate omarchy-context-engine
```

QML edits hot-reload. Summon the box with
`omarchy-shell shell summon relote.context-engine '{"mode":"find"}'`.

## License

MIT
