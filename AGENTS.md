# AGENTS.md

This file provides guidance to AI coding agents when working with code in this repository.

## Project Overview

envrc-tools is a shell integration tool that automatically detects and loads `.envrc` files in isolated subshells. Unlike direnv (which patches env diffs), it spawns a new shell process per `.envrc` — cleanup is automatic when the subshell exits.

Only **`envrc.sh`** is the active implementation (sourced in `.zshrc`). Other files (`envrc.zsh`, `envrc-stdlib.sh`, `envrc.py`, `envrc.go`, `zsh.go`) are unused experiments.

## Setup

```bash
# In .zshrc:
source ~/path/to/envrc.sh; envrc hook zsh
```

No build step, tests, or linting configured.

## Architecture

`envrc.sh` is self-contained (~200 lines). Core functions:

- `_find_up(file)` — walk up from `$PWD` to `/` looking for a file
- `_load_envrc(path)` — spawn subshell or source `.envrc` (see SPEC.md for branching logic)
- `_envrc-run-check()` — main lifecycle hook: detect `.envrc`, exit subshell if outside directory
- `_use(tool, ver)` — install/activate tool version via asdf
- `PATH_add(dir)` — prepend to `$PATH`

### Key state variables

| Variable | Purpose |
|----------|---------|
| `ENVRC` | Full path to current `.envrc` |
| `ENVRC_DIR` | Directory containing `.envrc` |
| `ENVRC_NAME` | Display name (basename or `~`) |
| `ENVRC_HASH` | SHA-512 of `.envrc` contents |
| `ENVRC_PROMPT` | Prompt indicator, e.g. `📜.envrc[project]` |
| `_ENVRC_NESTING_LEVEL` | Subshell depth (0 = login shell) |
| `_ENVRC_NESTED_UNLOADED` | Reload guard after exiting a subshell |

See `SPEC.md` for detailed lifecycle flows, `.envrc` API, and design trade-offs.

## Branches

- `dev` — development branch (base feature branches here)
- `main` — release branch
