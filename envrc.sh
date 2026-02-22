#!/usr/bin/env bash

envrc_name=".envrc"
envrc_last_subshell_pwd="/tmp/envrc-subshell-last-pwd"


function _debug() {
  echo "🐛 envrc: $1"
}

function _info() {
  echo "ℹ️ envrc: $1"
}

function _success() {
  echo "✅ envrc: $1"
}

function _error() {
  echo "⁉️ envrc: $1"
}

if [ ${ENVRC_VERBOSE:-0} -eq 1 ]; then
  _debug() { }
  _info() { }
elif [ ${ENVRC_VERBOSE:-0} -eq 2 ]; then
  _debug() { }
elif [ ${ENVRC_VERBOSE:-0} -eq 3 ]; then
  ;
else
  _debug() { }
  _info() { }
  _success() { }
fi

function _use() {
  local tool=$1;
  local ver=${2:-latest};

  if ! asdf where "$tool" "$ver" >/dev/null 2>&1; then
    if asdf install "$tool" "$ver"; then
      _info "Installed $tool@$ver"
      asdf reshim "$tool" "$ver"
    else
      _error "Failed to install $tool@$ver"
    fi
  fi
}


function _user_rel_path() {
  local abs_path=${1#-}

  if [[ -z $abs_path ]]; then return; fi

  if [[ -n $HOME ]]; then
    local rel_path=${abs_path#$HOME}
    if [[ $rel_path != "$abs_path" ]]; then
      abs_path="~$rel_path"
    fi
  fi

  echo "$abs_path"
}

function _find_up() {
  local path_="${PWD}"
  local file_="$1"
  while [ "${path_}" != "" ] && [ "${path_}" != '.' ] && [ ! -f "${path_}/${file_}" ]; do
    path_=${path_%/*}
  done
  if [ -f "${path_}/${file_}" ]; then
    echo "${path_}/${file_}"
  fi
}

function _load_envrc() {
  local path_="$1"

  if [[ "${_ENVRC_NESTED_UNLOADED:-}" == "${path_}" ]]; then
    _debug "Skipping loading $path_: was unloaded."
    return
  fi

  if [ -n "${ENVRC}" ] || [[ "${_ENVRC_NESTING_LEVEL:-0}" == "0" ]]; then
    unset _ENVRC_NESTED_UNLOADED
    _debug "Loading subshell..."
    ENVRC="" \
    ENVRC_NAME="" \
    ENVRC_HASH="" \
    ENVRC_DIR="" \
    ENVRC_PROMPT="" \
    _ENVRC_NESTING_LEVEL=$((${_ENVRC_NESTING_LEVEL:-0}+1)) \
    $SHELL

    _ENVRC_NESTED_UNLOADED="${path_}"

    _info "Unloaded $(_user_rel_path $path_)"

    # After exiting from subshell, ensure we stay in the same working directory
    local last_pwd_in_subshell=$(cat $envrc_last_subshell_pwd)
    if [ -n "$last_pwd_in_subshell" ] && [[ "${PWD}" != "${last_pwd_in_subshell}" ]]; then
      _debug "Setting last PWD: $last_pwd_in_subshell"
      cd "$last_pwd_in_subshell"
      _envrc-run-check
    fi
  elif [ -z "${ENVRC}" ]; then
    _debug "Loading ${path_}"
    export ENVRC="${path_}"
    export ENVRC_DIR="$(dirname $ENVRC)"
    export ENVRC_NAME="$(basename $ENVRC_DIR)"
    export ENVRC_HASH="$(_envrc-hashsum $ENVRC)"
    if [[ "${ENVRC_DIR}" == "$HOME" ]]; then
      export ENVRC_NAME="~"
    fi

    source "${path_}"

    export ENVRC_PROMPT="${ENVRC_PROMPT:-📜${envrc_name}[${ENVRC_NAME}]}"
    _success "Loaded $(_user_rel_path $path_)"
  fi
}

function _envrc-hashsum() {
  sha512sum $1 | cut -d" " -f1
}

function _envrc-on-subshell-exit() {
  echo "$PWD" > $envrc_last_subshell_pwd
}

function _envrc-on-cd() {
  unset _ENVRC_NESTED_UNLOADED
}

function _envrc-run-check() {
  # Leave current shell if we outside .envrc's directory
  if [[ -n "${ENVRC:-}" ]]; then
    local env_dir=$(dirname "${ENVRC:-}")
    if [[ "$PWD" != "$env_dir"* ]]; then
      _debug "Unloading ${ENVRC}"
      echo "$PWD" > $envrc_last_subshell_pwd
      exit
    fi
  fi

  local path_="$(_find_up $envrc_name)"
  # If it's the same envrc file, do nothing
  if [[ "${ENVRC-}" == "${path_}" ]]; then
    return
  fi

  if [ -f "$path_" ]; then
    _load_envrc "$path_"
  fi
}

function _envrc-exit-shell() {
  _debug "Exiting shell..."
  exit
}

function _envrc-hook() {
  hook=$1

  case $hook in
    zsh)
      add-zsh-hook precmd _envrc-run-check
      # add-zsh-hook zshexit _envrc-on-subshell-exit
      add-zsh-hook chpwd _envrc-on-cd
      # zle -N _envrc-exit-shell
      # bindkey '^D' _envrc-exit-shell
      ;;
  esac

}

function envrc() {
  cmd=$1
  shift 1

  case $cmd in
    hook)
      _envrc-hook $@
      ;;
    use)
      _use $@
      ;;
  esac
}

alias use="envrc use"
PATH_add() {
  export PATH="$1:$PATH"
}

