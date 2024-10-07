#!/usr/bin/env python
import base64
import hashlib
import json
import os
import re
import shlex
import sys
from pathlib import Path


class Env:
    path: Path
    data: dict

    def __init__(self, path: Path, data: dict):
        self.path = path
        self.data = data

    @classmethod
    def load(cls, env_meta_path: Path):
        if env_meta_path.exists():
            meta = json.loads(env_meta_path.read_text())
            return cls(env_meta_path, meta)
        raise ValueError("Unknown env data file")

    @classmethod
    def new(cls, envrc_path: Path):
        envrc_id = hashfunc(str(envrc_path))
        envrc_hash = (hashfunc(envrc_path.read_text()),)

        cache_dir = Path.home() / ".cache/envrc" / envrc_id
        cache_dir.mkdir(parents=True, exist_ok=True)

        data_path = cache_dir / "data.json"

        return cls(
            data_path,
            {
                "envrc": str(envrc_path),
                "envrc_hash": envrc_hash,
                "envrc_id": envrc_id,
                "envrc_dir": str(envrc_path.parent),
                "cache_dir": str(cache_dir),
            },
        )

    def update(self, **data):
        self.data.update(data)

    def dump(self):
        # TODO: dump only if changes
        self.path.write_text(json.dumps(self.data))


ENVRC_FILE = ".envrc"
ENVRC_CMD = "envrcx"

INIT_ZSH = """
# Add entry point
$ENVRC_CMD () {
    eval "$($ENVRC_BIN $@)"
}

# Add ZSH hooks

# - run envrc check every time we show prompt
__envrc-pre-prompt() { $ENVRC_CMD lifecycle pre-prompt; }
add-zsh-hook precmd __envrc-pre-prompt

# - handle exiting from the subshell
__envrc-handle-subshell-exit() { $ENVRC_CMD lifecycle subshell-exit; }
add-zsh-hook zshexit __envrc-handle-subshell-exit

# - handle changing working directory
__envrc-handle-cd() { $ENVRC_CMD lifecycle cd; }
add-zsh-hook chpwd __envrc-handle-cd


# Override hotkeys
# zle -N _envrc-exit-shell
# bindkey "^D" _envrc-exit-shell
"""


def format_script(script: str, **params: str) -> str:
    values = {}
    patterns = []
    for var, val in sorted(params.items(), reverse=True):
        val = shlex.quote(str(val))
        patterns.append(rf"\$({var})\b")
        values[f"${var}"] = val
        patterns.append(rf"\$\{{({var})\}}")
        values[f"${{{var}}}"] = val

    pattern = "|".join(patterns)

    def replace_fn(m: re.Match) -> str:
        var = m.group(0)
        return values.get(var, var)

    script, _ = re.subn(pattern, replace_fn, script)

    return script


def out(script: str, **params):
    default = {
        "ENVRC_CMD": ENVRC_CMD,
        "ENVRC_BIN": __file__,
    }
    print(format_script(script, **params, **default))


def find_envrc():
    pwd = Path.cwd()

    for d in pwd.parents:
        envrc_path = d / ENVRC_FILE
        if envrc_path.exists():
            yield envrc_path


def hashfunc(text: str):
    hash_algo = "sha3_256"
    h = hashlib.new(hash_algo)
    h.update(text.encode("utf8"))
    hash_data = base64.urlsafe_b64encode(h.digest()).decode("utf8")

    return f"{hash_data}.{hash_algo}.b64u"


def handle_pre_prompt(curr_env: Env | None):
    cwd = os.getcwd()

    if curr_env:
        # curr_envrc = curr_env.data.get("envrc")
        envrc_dir = curr_env.data.get("envrc_dir")

        curr_env.update(cwd=cwd)

        if envrc_dir and not cwd.startswith(envrc_dir):
            # we moved outside envrc dir
            # unloading current environment
            return out(
                """
                # closing current subshell
                exit
                """
            )

    nearest_envrc_file = next(find_envrc(), None)

    if (
        nearest_envrc_file
        and curr_env
        and nearest_envrc_file == curr_env.data.get("envrc")
    ):
        # already loaded, do nothing
        return out("")

    # load the nearest .envrc in a subshell
    envrc_file = nearest_envrc_file
    if envrc_file:
        new_env = Env.new(envrc_file)
        new_env.update(cwd=os.getcwd())

        return out(
            """
            ENVRC=${ENVRC} \
            __ENVRC__=${ENVRC_META} \
            $SHELL

            $ENVRC_CMD lifecycle post-subshell-exit "${ENVRC_META}"
            """,
            ENVRC=envrc_file,
            ENVRC_DATA=new_env.path,
        )


def handle_cd(curr_env: Env):
    curr_env.update(cwd=os.getcwd())

    return out(
        """
        unset _ENVRC_NESTED_UNLOADED
    """
    )


def handle_subshell_exit(curr_env: Env):
    curr_env.update(cwd=os.getcwd())

    return out(
        """
        # TODO
        """
    )


def handle_post_subshell_exit(curr_env: Env | None, prev_env: Env):
    if curr_env:
        pass
    prev_pwd = prev_env.data.get("cwd")
    cwd = os.getcwd()
    if prev_pwd and prev_pwd != cwd:
        return out(
            """
            cd $prev_pwd
            """,
            prev_pwd=prev_pwd,
        )


def main():
    args = sys.argv[1:]

    match args:
        case ["lifecycle", lifecycle_event, *opts]:
            curr_envrc_file = os.getenv("__ENVRC__", "")
            if not curr_envrc_file:
                curr_env = None
            else:
                curr_env = Env.load(Path(curr_envrc_file))

            match lifecycle_event:
                case "cd":
                    if curr_env:
                        handle_cd(curr_env)
                case "pre-prompt":
                    if curr_env:
                        handle_pre_prompt(curr_env)
                case "subshell-exit":
                    if curr_env:
                        handle_subshell_exit(curr_env)
                case "post-subshell-exit" if len(opts) == 1:
                    prev_env = Env.load(Path(opts[0]))
                    handle_post_subshell_exit(curr_env, prev_env)

            if curr_env:
                curr_env.dump()

        case ["init", "zsh"]:
            out(INIT_ZSH)


"""
Env events:
    - cd
    - exit
    - pre-prompt
    - pre-cmd
    - post-cmd

    -
    - changed .envrc
"""
"""
possible hooks

- envrc-loaded
- envrc-unloaded
- envrc-changed
- shell-exit


actions
- deactivate-env -- basicaly `exit` for the current env (if it exists/loaded)
- term-exit -- unloads all nested envrc until nesting level = 0 and execute `exit`


eval "$(
  envrc init zsh \
  # "cascade" | "current"
  --load-mode "cascade" \
  --stdlib "core,use,dotenv,path,log,tui" \
  --stdlib "~/Develop/playground/envrc-tools/envrc.sh" \
  --aliases "
    use:__envrc-stdlib-use
    load:__envrc-stdlib-load
    track:__envrc-hook track-file
    PATH_add:__envrc-stdlib-path-add
    dotenv:__envrc-stdlib-dotenv
    log:__envrc-stdlib-log
  "
)"

envrc track-file --allow path-to-file
envrc track-file --deny path-to-file
envrc hook track-file ".nvmrc" \
  --on-tracked "load-nvmrc" \
  --on-chnaged "reload-nvmrc" \
  --on-untracked "nvm use default"

envrc hook track-workdir "web/" \
  --on-enter "Entering dir" \
  --on-leave "Leaving dir"

envrc hook [env-enter | env-leave | env-reloaded | cd]


"""


if __name__ == "__main__":
    main()
