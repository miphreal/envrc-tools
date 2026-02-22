package main

const ZSHShellIntegration = `
##
# Enable evnrc zsh shell integration
# Usage:
#  eval "$(envrc shell-integration init)"
function _envrc-hook() {
  if output=$(%s shell-integration hook $@); then
    eval "$output"
  fi
}

##
# envrc hooks
autoload -Uz add-zsh-hook

# - before propmt is shown
function _envrc-before-prompt() { _envrc-hook before-prompt; }
add-zsh-hook precmd _envrc-before-prompt

# - before command is executed
function _envrc-before-exec() { _envrc-hook before-exec "$1"; }
add-zsh-hook preexec _envrc-before-exec

# - on working directory change
function _envrc-on-cd() { _envrc-hook on-cd; }
add-zsh-hook chpwd _envrc-on-cd

# - on subshell exit
function _envrc-on-subshell-exit() { _envrc-hook on-subshell-exit; }
add-zsh-hook zshexit _envrc-on-subshell-exit

# zle -N _envrc-exit-shell
# bindkey '^D' _envrc-exit-shell
`
