# envrc-tools

A shell integration tool that automatically detects and loads `.envrc` files in **isolated subshells**. Unlike [direnv](https://direnv.net/) (which patches env diffs into your current shell), envrc-tools spawns a new shell process per `.envrc` — cleanup is automatic when the subshell exits.

## Setup

```bash
# In .zshrc:
source ~/path/to/envrc.sh; envrc hook zsh
```

## `.envrc` API

### Functions

- **`use TOOL [VERSION]`** — install and activate a tool version via [asdf](https://asdf-vm.com/). VERSION defaults to `latest`.
- **`PATH_add DIR`** — prepend a directory to `$PATH`.

### Variables

- `$ENVRC_DIR` — the directory containing the `.envrc` being loaded.

### Example `.envrc`

```bash
use golang 1.23.2
use python 3.12.2
use nodejs 22.5.1

source .venv/bin/activate
PATH_add "${ENVRC_DIR}/node_modules/.bin"

export GOPATH=$PWD
```

### Verbosity

Set `ENVRC_VERBOSE` before sourcing `envrc.sh`:

| Level | Output |
|-------|--------|
| 0 (default) | Errors only |
| 1 | + success messages |
| 2 | + info messages |
| 3 | + debug messages |

## Architecture

`envrc.sh` is a self-contained ~200-line script. The key design choice: every `.envrc` environment runs in its own shell process, so exiting the subshell is a clean teardown with no env patching needed.

### Component Diagram

```mermaid
graph TD
    subgraph "User Shell (.zshrc)"
        INIT["source envrc.sh<br>envrc hook zsh"]
    end

    subgraph "envrc.sh — Core"
        HOOK["_envrc_hook(zsh)"]
        CHECK["_envrc_run_check()"]
        FIND["_find_up(.envrc)"]
        LOAD["_load_envrc(path)"]
        SPAWN["_envrc_spawn_subshell(path)"]
        SOURCE["_envrc_source(path)"]
        ONCD["_envrc_on_cd()"]
    end

    subgraph "envrc.sh — Utilities"
        HASH["_envrc_hashsum()"]
        REL["_user_rel_path()"]
        LOG["_debug / _info / _success / _error"]
    end

    subgraph ".envrc API"
        USE["use TOOL [VER]"]
        PATHADD["PATH_add DIR"]
    end

    subgraph "External"
        ASDF["asdf (version manager)"]
        TMPFILE["/tmp/envrc-subshell-last-pwd-$$"]
    end

    INIT --> HOOK
    HOOK -->|"add-zsh-hook precmd"| CHECK
    HOOK -->|"add-zsh-hook chpwd"| ONCD
    CHECK --> FIND
    FIND -->|"found .envrc"| LOAD
    LOAD -->|"level 0 or ENVRC set"| SPAWN
    LOAD -->|"level >0 and ENVRC empty"| SOURCE
    SPAWN -->|"exec $SHELL"| CHECK
    SOURCE -->|"source .envrc"| USE
    SOURCE -->|"source .envrc"| PATHADD
    SOURCE --> HASH
    USE --> ASDF
    CHECK -->|"outside ENVRC_DIR"| TMPFILE
    SPAWN -->|"read last PWD"| TMPFILE
```

### Lifecycle: Enter & Exit Flow

```mermaid
sequenceDiagram
    participant User
    participant Login as Login Shell (level 0)
    participant Sub as Subshell (level 1)
    participant Envrc as .envrc file
    participant Tmp as /tmp/last-pwd

    Note over User,Login: — Entering a directory —
    User->>Login: cd ~/project
    Login->>Login: precmd → _envrc_run_check()
    Login->>Login: _find_up(".envrc") → ~/project/.envrc
    Login->>Login: _load_envrc() → level 0 → spawn subshell
    Login->>Sub: exec $SHELL (level=1, ENVRC="")
    Sub->>Sub: precmd → _envrc_run_check()
    Sub->>Sub: _find_up(".envrc") → same file
    Sub->>Sub: _load_envrc() → level 1, ENVRC="" → source
    Sub->>Envrc: source .envrc
    Envrc-->>Sub: sets env vars, PATH, tools
    Note over Sub: ENVRC_PROMPT = 📜.envrc[project]

    Note over User,Login: — Leaving the directory —
    User->>Sub: cd /other
    Sub->>Sub: precmd → _envrc_run_check()
    Sub->>Sub: PWD not under ENVRC_DIR
    Sub->>Tmp: write PWD
    Sub->>Sub: exit
    Sub-->>Login: subshell terminates
    Login->>Tmp: read last PWD
    Login->>Login: cd to last PWD
    Login->>Login: set _ENVRC_NESTED_UNLOADED (guard)
    Login->>Login: _envrc_run_check() → skip (guard match)
```

### `_load_envrc` Decision Tree

```mermaid
flowchart TD
    A["_load_envrc(path)"] --> B{"path == _ENVRC_NESTED_UNLOADED?"}
    B -->|Yes| C["Skip — prevents reload loop"]
    B -->|No| D{"ENVRC set OR<br>nesting level == 0?"}
    D -->|Yes| E["Spawn subshell<br>Clear ENVRC_*, level++, exec $SHELL"]
    D -->|No| F{"ENVRC empty AND<br>nesting level > 0?"}
    F -->|Yes| G["Source .envrc directly<br>Set ENVRC, ENVRC_DIR,<br>ENVRC_NAME, ENVRC_HASH,<br>ENVRC_PROMPT"]
    F -->|No| H["No action"]

    E --> I["On subshell exit:<br>set _ENVRC_NESTED_UNLOADED<br>restore PWD"]

    style C fill:#f9f,stroke:#333
    style E fill:#bbf,stroke:#333
    style G fill:#bfb,stroke:#333
```

### Nesting State Machine

```mermaid
stateDiagram-v2
    [*] --> LoginShell: source envrc.sh

    LoginShell --> Subshell_L1: cd into dir with .envrc\n(spawn subshell, level++)

    state Subshell_L1 {
        [*] --> Loaded: source .envrc
        Loaded --> Loaded: stay in dir
        Loaded --> [*]: cd outside → exit
    }

    Subshell_L1 --> LoginShell: subshell exits\n(_ENVRC_NESTED_UNLOADED = path)

    Subshell_L1 --> Subshell_L2: cd into nested dir\nwith different .envrc

    state Subshell_L2 {
        [*] --> Loaded2: source .envrc
        Loaded2 --> [*]: cd outside → exit
    }

    Subshell_L2 --> Subshell_L1: subshell exits
```

### Key Design Notes

- **Isolation via process stack**: each `.envrc` is a shell process; nesting creates a stack of shells. Clean by design, but deep nesting = many processes.
- **IPC is a temp file**: `/tmp/envrc-subshell-last-pwd-$$` (PID-scoped) passes PWD from exiting subshell to parent.
- **No trust model**: unlike direnv's `allow`/`deny`, any `.envrc` is auto-sourced.
- **Hash unused**: `ENVRC_HASH` is computed but never compared — no hot-reload on `.envrc` edits.
- **Reload guard** (`_ENVRC_NESTED_UNLOADED`): prevents infinite re-spawn when parent rediscovers its own `.envrc` after subshell exit; cleared on next `chpwd`.

## Known Limitations

- No security allowlist — any `.envrc` is sourced automatically
- No change detection — editing `.envrc` requires leaving and re-entering the directory
- Each active `.envrc` is a shell process — deep nesting means a stack of processes
- Loads the nearest `.envrc` walking upward — does not merge or cascade multiple files
