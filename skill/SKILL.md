---
name: "codex-context-stats"
description: "Report Codex session token usage: tokens currently in context, the model context window size, and conversation totals split into cached vs non-cached input tokens. Use when the user asks about token usage, context size, remaining context, prompt-cache hits, or how many cached/non-cached tokens the current conversation has used."
metadata:
  short-description: "Codex token usage: context tokens, window size, cached vs non-cached conversation totals."
---

# Codex Context Stats

Report token statistics for a Codex CLI session. The data is read from the
session rollout JSONL in the Codex home (default `%USERPROFILE%\.codex`, or
`$env:CODEX_HOME` when set), so it works without network access and without
touching the running session.

## Run the bundled script

The scripts ship with this skill in `scripts/` (relative to this skill folder).
Use Windows PowerShell 5.1+ (or pwsh):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\codex-context-stats.ps1" -Format table
```

Resolve `<skill-dir>` to the absolute directory that contains this SKILL.md.

Options:
- `-Format line|table|json` — `line` is a compact one-liner (default), `table`
  is a human readable report, `json` is machine readable.
- `-SessionId <id>` — report a specific session/thread id (the id embedded in
  the rollout file name, e.g. `01a12ef0-...`). Default: the most recently
  updated session.
- `-CodexHome <path>` — override the Codex home directory.

## What the numbers mean

- **Context now** — input size of the most recent API request, i.e. the tokens
  currently occupying the context window.
- **Window** — the model context window size (e.g. 124.5k).
- **Context cached** — how much of the current context was served from the
  provider's prompt cache on the last request.
- **Conversation totals** — cumulative over the whole conversation:
  - `input total` = every token sent to the model (the context is re-sent on
    each sampling request, so this grows quickly).
  - `cached` = input tokens served from the prompt cache.
  - `non-cached` = input - cached - cache-write (prompt, tools, and
    first-time cache misses).
  - `output` = model output tokens (with the reasoning subset).

## Live dashboard

For a continuously updated display in a separate terminal:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\codex-context-watch.ps1"
```

It follows the most recently updated session by default and refreshes every 5
seconds (override with `-IntervalSeconds`). Ctrl+C stops it.

## Notes

- Data updates after each model response; right after starting a conversation
  the rollout may not contain token usage yet.
- The Codex TUI status line already shows built-in items
  (`context-used`, `context-window-size`, `used-tokens`, `total-input-tokens`,
  `total-output-tokens` via `/statusline`), but Codex has no built-in
  cached/non-cached item — that breakdown is what this skill adds.
