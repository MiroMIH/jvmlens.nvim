# Working in this codebase

This doc is for anyone (including future sessions with Claude) picking
this codebase back up. It explains where things go and why, so new code
doesn't drift back into the tangled state that caused the first rewrite.

## The one question to ask before writing anything

**"Is this a decision, or is this drawing?"**

- A *decision* is anything like: which line is a breakpoint, what layer a
  method belongs to, what a variable's value is. Decisions go in `core/`.
- *Drawing* is anything that touches the screen: opening a window, sizing
  a popup, moving the cursor, setting buffer lines. Drawing goes in `ui/`.

`core/` code must never call `vim.api.nvim_win_*`, `vim.api.nvim_buf_set_lines`,
or touch `nui`. If a `core/` file needs to do any of that, the logic in it
is in the wrong place.

`ui/` code must never contain business rules (e.g. "is this annotation a
Controller"). If a `ui/` file needs to decide something like that, call
into `core/` and just render whatever it returns.

## Folder map

```
lua/jvmlens/
├── init.lua        -- setup(), keymaps/commands. Wiring only, no logic.
├── config.lua       -- every option + its default, in one place.
├── core/            -- pure logic. No vim.api screen calls. Easy to reason
│                        about without running Neovim at all.
├── ui/              -- all screen code. Reuses shared building blocks
│                        instead of each feature writing its own popup code.
└── source/          -- where live debugging data comes from (nvim-dap for
                          now; later phases add other backends here without
                          touching core/ or ui/).
```

## Why this split exists

The first version of this plugin mixed "which line is a stop" logic
together with "how big should the popup be" rendering code, in the same
functions. That's how a scanner bug (a bad line number) turned directly
into a crash in `nvim_win_set_cursor` — nothing forced a safety check to
happen in one predictable place. Keeping `core/` free of screen calls
means a `core/` bug is a wrong *value*, not a crash; keeping `ui/` free of
business logic means the same popup/cursor code gets reused and hardened
once instead of reinvented per feature.

## Adding a new feature — the checklist

1. Does it need new state or a new decision (e.g. "what counts as a
   stop")? Add/extend a file in `core/`. Write it as plain functions on
   plain Lua tables — no `vim.api` calls.
2. Does it need to show something? Add to `ui/`, and prefer extending an
   existing building block (`panel.lua`, `list.lua`) over writing new
   window-management code from scratch.
3. Wire the two together in `init.lua` (a keymap/command that calls into
   `core/` and/or `ui/`).
4. Test it — headless Neovim first if possible (see below), then live.
   Don't add a second feature in the same pass until the first one has
   actually been tried.

## Current status

Step 1: the debugger view toggle (`ui/workspace.lua`) — a dedicated tab,
separate from your normal editing, that you switch into and back out of
with one keybind. No breakpoints, panels, or variables yet — this step is
just proving the switch-in/switch-out mechanic works cleanly on its own.
