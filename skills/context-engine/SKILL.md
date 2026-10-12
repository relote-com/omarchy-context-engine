---
name: context-engine
description: Shared long-term memory for this Omarchy computer, held in Context Engine and reached through the `context-engine` MCP server (tools brief, find, get, write, edit) or the `ce` command. Use at the start of every session to load what changed, before answering anything about past decisions, people, projects or why this machine is set up the way it is, and after making a decision or changing the system so the next agent — whichever one it is — knows. Triggers: remember, recall, "what did we decide", "why is X like this", "last time", notes, decisions, tasks, my setup, my config history.
---

# Context Engine — the memory every agent on this machine shares

This computer runs Omarchy. The person can launch any of several coding
agents (`omarchy agent`), and all of them are connected to the same Context
Engine. What you save, the next agent reads. What the last agent saved, you
can read now. Treat the engine as the machine's memory, not your own notes.

## How to reach it

Prefer the MCP tools on the `context-engine` server:

| Tool | Use it to |
| --- | --- |
| `brief` | Start a session: which engines you reach, what each is for, whether you may save there, what changed since the last session, and what never to store. |
| `find` | Search (`q`) or list recent memories, filtered by `type`, `tags`, `since`. Bodies come back inline. |
| `get` | Open one memory by ref, e.g. `decision::hyprland-gaps`. |
| `write` | Save a new memory in one `engine` (required): `note`, `decision` (needs `fields.rationale`), `task`, `person`, `company`, `meeting`. |
| `edit` | Change a memory that already exists instead of writing a second one. |

If the MCP tools are not available in this session, the `ce` command does
the same over HTTP:

```bash
ce brief                     # what changed
ce find "hyprland gaps"      # search
ce get decision::hyprland-gaps
ce remember "Title" --decision --why "because…" --tag hyprland
echo "longer note…" | ce remember --title "Title"
ce engine                    # which engine new memories go to
```

## What to do

1. **Session start.** Call `brief` once, before your first reply. Mention
   anything in it that bears on the request; don't recite it.
2. **Before answering from assumption,** `find` first when the question
   touches the person's past: "why is…", "what did we…", "last time",
   a named person or project, or a config choice you did not make. Cite the
   memory you used by its ref.
3. **Save when something is decided or learned,** not at the end of every
   turn:
   - A choice with a reason → `decision` with `fields.rationale`.
   - A fact worth knowing later → `note`.
   - Work someone still has to do → `task`.
   `find` first; if a memory about the same thing exists, `edit` it.
4. **Changing this Omarchy system** (anything under `~/.config/hypr`,
   `~/.config/omarchy`, terminal configs, themes, keybindings, installed
   packages): after the change works, save a `decision` titled after what
   changed, with the old value, the new value, the file, and the person's
   reason in `rationale`. Tag it `omarchy` plus the area (`hyprland`,
   `bar`, `theme`, `keybinding`, `package`). This is how the next agent
   answers "why is my gap 5?" months later, and how the person's other
   machines learn the same preference.
5. **Use the default engine** (`ce engine` prints it) unless the brief or
   the person says another one fits better: a client's engine for that
   client's work, a team engine for team decisions.

## What never to store

Secrets — API keys, tokens, passwords, private keys — never; store *where*
one lives, not what it is. Anyone's private data (health, finances, home
address, contact details) only when the person asks you to keep that exact
thing. The `brief` repeats this rule; follow the engine's wording if it
differs.

## Style of a good memory

- Title says the thing: "Hyprland gaps set to 5 on the Air", not "Config update".
- Body is a few lines of Markdown a stranger could act on. Link related
  memories with `[[type::slug]]`.
- One fact per memory. A long session yields a few memories, not a transcript.
