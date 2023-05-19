#!/usr/bin/env python
import os
import sys
import pathlib


ENVRC_CMD = "envrcx"

INIT_ZSH = """
# Add entry point
$(ENVRC_CMD)s() {
    eval "$("%(ENVRC_BIN)s" $@)"
}

# Add ZSH hooks

# - run envrc check every time we show prompt
__envrc-run-check() { %(ENVRC_CMD)s lifecycle check; }
add-zsh-hook precmd __envrc-run-check

# - handle exiting from the subshell
__envrc-handle-subshell-exit() { %(ENVRC_CMD)s lifecycle subshell-exit; }
add-zsh-hook zshexit __envrc-handle-subshell-exit

# - handle changing working directory
__envrc-handle-cd() { %(ENVRC_CMD)s lifecycle cd; }
add-zsh-hook chpwd __envrc-handle-cd

    
# Override hotkeys
# zle -N _envrc-exit-shell
# bindkey "^D" _envrc-exit-shell
""" % dict(
    ENVRC_CMD=ENVRC_CMD,
    ENVRC_BIN=__file__,
)

UNLOAD_SESSION = """
# closing current subshell
exit
"""


def handle_check():
    cwd = os.getcwd()
    envrc_dir = os.getenv('ENVRC_DIR', '')

    if envrc_dir and not cwd.startswith(envrc_dir):
        # we moved outside envrc dir
        print(UNLOAD_SESSION)
        exit()

def handle_cd():
    print("""
        unset _ENVRC_NESTED_UNLOADED
    """)

def handle_subshell_exit():
    print("""
        echo "$PWD" > /tmp/envrc-subshell-last-pwd
    """)



def main():
    args = sys.argv[1:]

    match args:
        case ['lifecycle', lifecycle_event]:

            match lifecycle_event:
                case 'cd':
                    handle_cd()
                case 'check':
                    handle_check()
                case 'subshell-exit':
                    handle_subshell_exit()
        
        case ['init', 'zsh']:
            print(INIT_ZSH)



if __name__ == '__main__':
    main()
