# claude-clean

A small macOS shell tool to list, protect, and kill stale [Claude Code](https://claude.com/claude-code) CLI processes.

Long-running Claude sessions sit in detached terminal tabs and quietly accumulate — each one holding a few hundred MB of RAM. `claude-clean` finds them, shows which conversation each one is (via the iTerm session title), and kills the stale ones on request.

## Install

**Pick one of the two options below — you don't need both.** Option A is the default; pick Option B only if you want a single install shared by multiple macOS user accounts on the same machine.

### Option A — User-local (recommended, no sudo)

```bash
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/ozzyfromspace/claude-clean/main/claude-clean \
  -o ~/.local/bin/claude-clean
chmod +x ~/.local/bin/claude-clean
```

If `~/.local/bin` isn't on your `PATH` yet (check with `echo $PATH`):

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
# then open a new terminal, or run: hash -r
```

### Option B — System-wide (needs sudo, shared across macOS accounts)

Use this *instead of* Option A if multiple macOS user accounts on this machine should share one install:

```bash
sudo curl -fsSL https://raw.githubusercontent.com/ozzyfromspace/claude-clean/main/claude-clean \
  -o /usr/local/bin/claude-clean
sudo chmod 0755 /usr/local/bin/claude-clean
```

### Uninstall

Run `claude-clean --where` first to see the paths on your system. It prints three lines like:

```
binary:       /Users/<you>/.local/bin/claude-clean
protect-list: /Users/<you>/.claude-clean/protected
protect-dir:  /Users/<you>/.claude-clean
```

(The block above is **example output**, not commands — don't paste it.)

Then remove them in one of these ways:

**Scripted (parses `--where` output):**

Capture the paths first — once the binary is deleted, a second `claude-clean --where` call won't work:

```bash
info=$(claude-clean --where)
bin=$(echo "$info" | awk '/^binary:/ {print $2}')
dir=$(echo "$info" | awk '/^protect-dir:/ {print $2}')
```

Then remove. For a **user-local (Option A)** install:

```bash
rm "$bin" && rm -rf "$dir"
```

For a **system-wide (Option B)** install the binary is root-owned, so:

```bash
sudo rm "$bin" && rm -rf "$dir"
```

**By hand:**

```bash
rm ~/.local/bin/claude-clean          # user-local install
sudo rm /usr/local/bin/claude-clean   # system-wide install
rm -rf ~/.claude-clean                # protect list
```

## Privileges

`claude-clean` needs **no elevated privileges** for the common case (listing, protecting, killing your own stale claude processes). The only exception:

- **Cross-user kills** (`--profile=otheruser --kill` or `--profile=all --kill`) invoke `sudo kill` internally — killing another user's process is a Unix-level restriction that can't be worked around. Same-user ops never prompt.
- **iTerm session titles** need one-time Automation permission (macOS asks the first time). If denied, the TITLE column just stays blank.

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

---

_Vibe coded with love, lol_ ❤️
