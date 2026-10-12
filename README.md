# Codex counter

Permanently show token usage in the Codex CLI TUI status line: **tokens
currently in context**, **model context window size**, and **conversation
totals** - plus a **cached vs. non-cached** split of the conversation's input
tokens, available on demand through an installed skill and standalone scripts.

## Components

| File | Purpose |
| --- | --- |
| `install.ps1` | Merges token items into `[tui] status_line` in `config.toml` (existing items kept, timestamped backup made) and installs the skill. |
| `uninstall.ps1` | Removes the added status line items and the skill (backup made). |
| `src/codex-context-stats.ps1` | One-shot report: context tokens, window size, conversation totals split cached vs non-cached. Formats: `line` (default), `table`, `json`. |
| `src/codex-context-watch.ps1` | Live dashboard in a separate terminal (refreshes every 5 s by default). |
| `skill/SKILL.md` | The `codex-context-stats` skill: ask Codex "what's my token usage?" and it runs the script for you. |

## Install

From this folder, in Windows PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Then restart Codex. The status line now shows (defaults, values hidden until
the first model response of a session):

```
52.3k used · 124.5k window · 1.2M in · 18.4k out
```

- `-Items <a>,<b>` - choose which items to ensure in the status line.
  Default: `used-tokens`, `context-window-size`, `total-input-tokens`,
  `total-output-tokens`. Other built-in items you can add: `context-used`
  ("Context N% used"), `context-remaining`, `git-branch`, `hostname`,
  `codex-version`, `session-id`, `model-with-reasoning`, `thread-credits`,
  `estimated-thread-cost`.
- `-NoSkill` - status line only, skip the skill.
- `-CodexHome <path>` - install into a different Codex home.

## Cached vs non-cached tokens

Codex has no built-in status line item for cached tokens, so the status line
cannot show that split. The skill and scripts cover it: they read the session
rollout JSONL in your Codex home and report the provider prompt-cache numbers.

Ask Codex: "token usage?", "how much context is used?", "cached vs non-cached
tokens" - the `codex-context-stats` skill handles it. Or run directly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\codex-context-stats.ps1
```

Example output:

```
ctx 99.6k/124.5k (80%) | in 3.1M [cached 3.0M | fresh 65.4k] | out 48.4k
```

- `-Format table` - human readable multi-line report.
- `-Format json` - machine readable.
- `-SessionId <id>` - a specific session (default: most recently updated).
- `-CodexHome <path>` - override the Codex home.

Live dashboard in a separate terminal:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\codex-context-watch.ps1 -IntervalSeconds 5
```

Ctrl+C stops it.

### What the numbers mean

- **ctx** - input tokens of the most recent API request, i.e. what occupies
  the context window right now.
- **window** - the model context window size.
- **in** - total input tokens sent over the whole conversation. The context is
  re-sent on every request, so this grows fast (a few million over a ~100k
  context session is normal).
- **cached** - input tokens served from the provider's prompt cache.
- **fresh** (non-cached) - input minus cached minus cache-write.
- **out** - model output tokens, including reasoning tokens.

## Optional: mirror in the terminal title

The same items can be used for the terminal window title in `config.toml`:

```toml
[tui]
terminal_title = ["used-tokens", "context-used"]
```

## Uninstall

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

Removes the four added items from `status_line` (items you had before are
kept), deletes the skill folder, and backs up `config.toml` first.
`-RemoveAllStatusLine` removes the whole setting instead.

## Notes & troubleshooting

- Status line items with a zero/unknown value are hidden until after the
  first model response of the session.
- Changes to `config.toml` take effect when the TUI (re)starts.
- The running session's rollout file is file-locked by Codex; the scripts open
  it with a shared read handle, so the current session can be read live.
- Every install/uninstall run writes a `config.toml.bak-<timestamp>` next to
  the config you can restore if needed.
