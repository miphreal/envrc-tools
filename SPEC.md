# SPEC.md — envrc-tools

## Concept

envrc-tools automatically manages per-directory environments by detecting `.envrc` files and loading them in **isolated subshells**. When you `cd` into a directory with `.envrc`, a new shell process is spawned and the `.envrc` is sourced inside it. When you leave, the subshell exits — the parent environment is never modified, so no cleanup is needed.

This differs from direnv, which snapshots the environment before/after sourcing `.envrc` and patches the diff into the current shell. The subshell approach trades a shell process per environment for zero-complexity teardown and natural nesting.

## Setup

In `.zshrc`:
```bash
source ~/path/to/envrc.sh; envrc hook zsh
```

This sources all functions into the current shell and registers zsh hooks (`precmd`, `chpwd`).

## Active implementation

Only **`envrc.sh`** is in use. Experimental files live in `.experiments/` and are not sourced or referenced anywhere.

## How it works

### The `_load_envrc` branching logic

This is the heart of the system. The condition at `envrc.sh:85` determines the behavior:

```
_load_envrc(path) called:

  1. If path == _ENVRC_NESTED_UNLOADED → skip (prevents reload loop)

  2. If ENVRC is set OR _ENVRC_NESTING_LEVEL == 0:
       → spawn subshell (clear ENVRC_*, increment nesting level, exec $SHELL)
       → after subshell exits: set _ENVRC_NESTED_UNLOADED, restore PWD

  3. elif ENVRC is empty (and nesting level > 0):
       → source the .envrc directly, set ENVRC_* state vars
```

The key insight: **branch 2 fires at nesting level 0**, so even the first `.envrc` gets a subshell. Branch 3 (source directly) only runs inside that subshell, at level >= 1. This ensures every `.envrc` environment is isolated — the user's login shell is never polluted.

### Lifecycle: entering a directory

```
cd ~/project  (has .envrc)
    │
    ▼
precmd hook fires → _envrc-run-check()
    │
    ▼
_find_up(".envrc") walks up from $PWD to /
    │
    ▼
Found ~/project/.envrc, differs from current $ENVRC
    │
    ▼
_load_envrc("~/project/.envrc")
    │
    ├─ Level 0, ENVRC empty → branch 2: spawn subshell
    │   │
    │   ▼  (new shell, level=1, ENVRC="")
    │   precmd fires again → _find_up finds same .envrc
    │   │
    │   ▼
    │   _load_envrc → branch 3: source .envrc directly
    │   Set ENVRC, ENVRC_DIR, ENVRC_NAME, ENVRC_HASH, ENVRC_PROMPT
    │
    └─ Level >0, ENVRC set (nested) → branch 2: spawn another subshell
```

### Lifecycle: leaving a directory

```
cd /somewhere/outside
    │
    ▼
precmd hook fires → _envrc-run-check()
    │
    ▼
$PWD is not under $ENVRC_DIR
    │
    ▼
Write $PWD to /tmp/envrc-subshell-last-pwd
exit  (subshell terminates)
    │
    ▼
Parent shell resumes after the `$SHELL` line in branch 2
    │
    ▼
Read temp file, cd to last PWD if changed
_envrc-run-check() runs again (may load a different .envrc)
```

### The `_ENVRC_NESTED_UNLOADED` guard

When a subshell exits, the parent shell's `_find_up` may rediscover the parent's own `.envrc`. Without a guard, this would spawn a subshell endlessly. `_ENVRC_NESTED_UNLOADED` stores the path of the `.envrc` that was just exited. It's checked in branch 1 of `_load_envrc` and cleared on the next `chpwd`.

## Shell hooks

| Hook | Handler | Purpose |
|------|---------|---------|
| `precmd` | `_envrc-run-check()` | Main trigger — runs before every prompt. Detects `.envrc`, exits subshell if outside directory. |
| `chpwd` | `_envrc-on-cd()` | Clears `_ENVRC_NESTED_UNLOADED` so the next `.envrc` can load. |

`zshexit` and `^D` keybinding are present in the code but commented out.

## State variables

| Variable | Purpose |
|----------|---------|
| `ENVRC` | Full path to current `.envrc` file |
| `ENVRC_DIR` | Directory containing `.envrc` |
| `ENVRC_NAME` | Basename of directory (or `~` for home) |
| `ENVRC_HASH` | SHA-512 hash of `.envrc` contents (stored but not used for change detection) |
| `ENVRC_PROMPT` | Prompt indicator, e.g. `📜.envrc[project-name]` |
| `_ENVRC_NESTING_LEVEL` | Subshell depth (0 = login shell) |
| `_ENVRC_NESTED_UNLOADED` | Path of `.envrc` just exited — reload guard (local, not exported) |

IPC between subshell and parent uses `/tmp/envrc-subshell-last-pwd` (single shared file).

## API available inside `.envrc` files

`.envrc` files are sourced as shell scripts. They have access to:

### Functions

- **`use TOOL [VERSION]`** — install and activate a tool version via asdf. Checks `asdf where`, installs if missing, runs `asdf reshim`. VERSION defaults to `latest`.
- **`PATH_add DIR`** — prepend a directory to `$PATH`.
- **`_info MSG`**, **`_debug MSG`**, **`_success MSG`**, **`_error MSG`** — logging (controlled by `ENVRC_VERBOSE`).

### Variables available to `.envrc`

- `$ENVRC_DIR` — the directory containing the `.envrc` being loaded. Useful for building absolute paths:
  ```bash
  PATH_add "${ENVRC_DIR}/node_modules/.bin"
  source $ENVRC_DIR/.venv/bin/activate
  ```

### Common `.envrc` patterns

```bash
# Tool versions (via asdf)
use golang 1.23.2
use python 3.12.2
use nodejs 22.5.1

# Python virtualenv
source .venv/bin/activate

# uv-managed project
if [ ! -d $ENVRC_DIR/.venv/bin ]; then uv venv; fi
source .venv/bin/activate
uv sync

# PATH manipulation
PATH_add "${ENVRC_DIR}/node_modules/.bin"
PATH_add target/release

# Environment variables
export GOPATH=$PWD
export DEV_PROJECT=" configs"
export PYTHONBREAKPOINT=ipdb.set_trace
```

### Verbosity

Set `ENVRC_VERBOSE` before sourcing `envrc.sh`:

| Level | Output |
|-------|--------|
| 0 (default) | Errors only |
| 1 | + success messages |
| 2 | + info messages |
| 3 | + debug messages |

Logging functions are redefined to no-ops at init time — zero overhead for disabled levels.

## Experimental files

Unused explorations live in `.experiments/`:

- **`envrc.zsh`** — zsh-specific variant using `asdf shell` instead of `asdf where`.
- **`envrc-stdlib.sh`** — extracted stdlib with `zshexit` hook and `^D` keybinding enabled.
- **`envrc.py`** — event-driven model outputting shell code for `eval`. JSON cache at `~/.cache/envrc/`. Contains design notes for future features: load modes, modular stdlib, file/directory tracking hooks, aliases system.
- **`envrc.go` + `zsh.go`** — Go CLI (urfave/cli v2) skeleton for a compiled dispatcher.
- **`go.mod` + `go.sum`** — Go module dependencies.
- **`envrc`** — compiled Go binary (arm64 macOS).

## Known limitations

- **Temp file race condition**: `/tmp/envrc-subshell-last-pwd` is shared across all terminal sessions. Concurrent shells can overwrite each other's PWD.
- **No change detection**: `ENVRC_HASH` is computed but never compared — editing `.envrc` requires leaving and re-entering the directory.
- **No security allowlist**: any `.envrc` file is sourced automatically. No `direnv allow`-style trust mechanism.
- **One `.envrc` per scope**: loads the nearest `.envrc` walking upward. Does not merge or cascade multiple `.envrc` files.
- **Subshell cost**: each active `.envrc` is a shell process. Deep nesting means a stack of shell processes.
- **`zshexit` hook disabled**: the subshell exit handler is commented out — PWD is saved inline in `_envrc-run-check` instead.
