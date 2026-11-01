# Context Engine for Omarchy

One memory for every agent on your Omarchy machines. Version 0.2.2.

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

Both ask before they change anything. From a script, with no terminal to
ask in, add `--yes` to each: `omarchy plugin add … --enable --yes`, then
`ce setup --yes <keyfile` with the key in a file.

It needs `curl`, `jq` and `gum`, which Omarchy already ships, and uses
`notify-send` and `xdg-open` when they are there. The agents it connects
(Claude Code, Codex, OpenCode, Hermes, Cursor, Gemini CLI) are optional: it
wires up the ones you have.

`ce setup` walks you through it:

1. Links `ce` into `~/.local/bin`.
2. Signs in. Make a key at [app.contextengine.com](https://app.contextengine.com):
   **AI tools → Connect an AI tool → Your own code → Create my key**, with
   *Can read and save* on the engines Omarchy should use. The free plan is
   enough (3 engines).
3. Connects every installed coding agent to the engine over MCP. An agent that
   already has a `context-engine` server of its own keeps it unless you say
   to replace it.
4. Installs the `context-engine` skill into each agent's skill folder, next to
   Omarchy's own, so agents know when to read and save.
5. Adds **Context Engine** to the Omarchy menu and, if you agree, two keys and
   a post-update hook.

Not set up yet? Click the dimmed brain icon in the bar and it opens setup.

## Remove

```bash
ce uninstall
omarchy plugin remove relote.context-engine
```

`ce uninstall` takes out everything `ce setup` and `ce connect` added, the
key included, and nothing else: an agent server, skill, key binding or `ce`
command that was there before is left as it was, and settings you added to
those files since stay. `omarchy plugin remove` then deletes the plugin
folder.

## Many machines, one brain

Point every Omarchy machine at the same engine. Each write from `ce` and from
the agent skill carries a `machine:<hostname>` tag, so `ce brief` says which
machine saved what:

```
From which machine:
  decision::hyprland-gaps  ←  air
  note::dock-firmware      ←  desk
```

`ce find --json` shows the same tag under `fields.tags`.

## Use it

| Where | What |
| --- | --- |
| Bar icon | Click to find, right-click to remember, middle-click for what changed |
| `Super+Ctrl+M` | Find in memory (Tab switches to Remember, Ask, What changed) |
| Ask (in the box or the menu) | Opens your default Omarchy agent with the question. The agent answers from the engine over MCP |
| `Super+Alt+M` | Remember something. The first line is the title, Shift+Enter starts the next line, Enter saves |
| Omarchy menu › Context Engine | Find, remember, what changed, connect agents, setup |
| Any agent | Just ask: "what did we decide about the gaps?" The skill has it check the engine first |

From a terminal:

```bash
ce brief --summary                         # what changed since you last looked
ce find "hyprland gaps"                    # search across your engines
ce remember "Gaps are 5 on the Air" --decision --why "10 wasted space on a 13in screen"
git log -1 --format=%B | ce remember --tag release
echo "private note" | ce remember -        # stdin: the text stays out of ps
ce engine acme                             # save to another engine by default
ce agents                                  # which agents are connected
```

## What it changes on your machine

Everything outside the plugin folder is written by `ce setup` (or
`ce connect`) and removed by `ce uninstall`. What it created is listed in
`~/.config/context-engine/installed`, so uninstall removes exactly that.

| File | What |
| --- | --- |
| `~/.config/context-engine/config` | Your key and default engine (mode 600) |
| `~/.local/bin/ce` | Symlink to the plugin's `bin/ce`, unless another `ce` is there |
| `~/.claude.json` (via `claude mcp add-json --scope user`) | `context-engine`: `type: http`, `url`, `headersHelper: …/bin/ce mcp-headers` |
| `~/.codex/config.toml` | `[mcp_servers.context-engine]` `url`, `http_headers`, between marker comments |
| `~/.config/opencode/opencode.json` | `mcp.context-engine`: `type: remote`, `url`, `headers` |
| `~/.cursor/mcp.json` | `mcpServers.context-engine`: `url`, `headers` |
| `~/.gemini/settings.json` | `mcpServers.context-engine`: `httpUrl`, `headers` |
| `~/.hermes/config.yaml` | `mcp_servers.context-engine`: `url`, `headers`, between marker comments |
| `~/.agents/skills`, `~/.claude/skills`, … | `context-engine` skill symlink |
| `~/.config/omarchy/extensions/omarchy-menu.jsonc` | Menu rows between marker comments |
| `~/.config/hypr/context_engine.lua` + one `require` line | The two keys (asks first) |
| `~/.config/omarchy/hooks/post-update.d/context-engine` | Records Omarchy updates (asks first) |

Every agent reaches `https://app.contextengine.com/mcp` with the same key as
a Bearer header, and the key decides which engines they reach. Claude Code
asks `ce mcp-headers` for it on each connection, so its config holds no copy;
the other agents keep a copy in their own config, which `ce` sets to mode
600. The key never goes on a command line. Writes are credited to you. To
give agents read-only access, make a key with *Can read* and run `ce login`
again.

What you write, search and ask is kept off command lines too, since every
account on the computer can read those (`ps`). The box hands Remember and
Find text to `ce` on stdin, and `ce` passes it to `jq` and `curl` the same
way. A note or query you type as an argument in a terminal is in `ps` while
`ce` runs; pipe it instead (`echo … | ce remember -`, `echo … | ce find -`).
One exception: Ask hands the question to `omarchy agent prompt`, which only
takes it as an argument and passes it to your agent as one, so a question is
visible in `ps` while the agent runs.

## How it works

- **Questions go to your agent, not to `ce`.** Ask hands the question to
  `omarchy agent prompt`, so the answer comes from whichever agent you chose
  in Omarchy, reading the engine through its MCP server. If that agent has no
  engine yet (say you changed the default after setup), Ask connects it first.
- **`bin/ce`** is a small bash client for the desktop's quick paths, over the
  engine's plain HTTP door `POST /tool/<name>` (`brief`, `find`, `get`,
  `write`, `edit`). It needs only `curl`, `jq` and `gum`, which Omarchy
  already ships.
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
git clone https://github.com/relote-com/omarchy-context-engine.git \
  ~/.config/omarchy/plugins/relote.context-engine
omarchy-shell shell rescanPlugins && omarchy plugin enable relote.context-engine
omarchy plugin validate ~/.config/omarchy/plugins/relote.context-engine
tests/ce.sh
```

`tests/ce.sh` runs `bin/ce` against stubs in a throwaway `HOME`: the machine
tag, each agent's config format, and that `ce uninstall` leaves `HOME` as
`ce setup` found it.

QML edits hot-reload. Summon the box with
`omarchy-shell shell summon relote.context-engine '{"mode":"find"}'`.

## License

MIT
