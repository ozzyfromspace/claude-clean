# claude-clean

A small macOS shell tool to list, protect, and kill stale [Claude Code](https://claude.com/claude-code) CLI processes.

Long-running Claude sessions sit in detached terminal tabs and quietly accumulate — each one holding a few hundred MB of RAM. `claude-clean` finds them, shows which conversation each one is (via the iTerm session title), and kills the stale ones on request.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/ozzyfromspace/claude-clean/main/claude-clean \
  | sudo tee /usr/local/bin/claude-clean >/dev/null \
  && sudo chmod 0755 /usr/local/bin/claude-clean
```

Or clone and install:

```bash
git clone https://github.com/ozzyfromspace/claude-clean.git
cd claude-clean
sudo install -m 0755 claude-clean /usr/local/bin/claude-clean
```

## Usage

```bash
claude-clean                         # list stale (>6h) claude processes for current user
claude-clean --kill                  # kill them
claude-clean --profile=someuser      # target a different user
claude-clean --profile=all --kill    # kill stale across all users (sudo if cross-user)
claude-clean --older-than=2h         # tighten the threshold
claude-clean --protect               # protect THIS session from future --kill
claude-clean --protect=12345         # protect a specific PID
claude-clean --list-protected
claude-clean --help
```

`--older-than` accepts `s` / `m` / `h` / `d` suffixes. For longer windows use days, e.g. `30d`, `90d`.

## How it works

- Identifies candidates via `ps -o comm=claude` — never matches helper processes, bundled apps, or anything else
- Populates a TITLE column from iTerm's AppleScript API so you can tell which conversation is which before killing
- Protected PIDs live in `~/.claude-clean/protected` (600 perms, auto-pruned when PIDs die)
- Never kills the session you're running inside (walks `$PPID` and excludes ancestors)
- Re-verifies `comm=claude` immediately before every `kill` to narrow PID-reuse races

Requires macOS. iTerm integration is a best-effort enrichment — the tool works fine in Terminal.app, just without the TITLE column populated.

## Tests

Zero-dependency bash tests. From the repo root:

```bash
./tests/run.sh
```

Each test runs in an isolated `$HOME` temp dir and covers CLI validation, duration parsing, symlink/permission hardening, and the protect-list lifecycle.

## License

MIT — see [LICENSE](LICENSE).
