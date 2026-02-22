#!/usr/bin/env bash

readonly envrc_name=".envrc"
envrc_last_subshell_pwd="/tmp/envrc-subshell-last-pwd-$$"
trap 'rm -f "$envrc_last_subshell_pwd"' EXIT


function _debug() {
  echo "🐛 envrc: $1" >&2
}

function _info() {
  echo "ℹ️ envrc: $1" >&2
}

function _success() {
  echo "✅ envrc: $1" >&2
}

function _error() {
  echo "⁉️ envrc: $1" >&2
}

if [ "${ENVRC_VERBOSE:-0}" -ge 3 ]; then
  : # all enabled
elif [ "${ENVRC_VERBOSE:-0}" -ge 2 ]; then
  _debug() { :; }
elif [ "${ENVRC_VERBOSE:-0}" -ge 1 ]; then
  _debug() { :; }
  _info() { :; }
else
  _debug() { :; }
  _info() { :; }
  _success() { :; }
fi

function _use() {
  local tool=$1;
  local ver=${2:-latest};

  if ! command -v asdf >/dev/null 2>&1; then
    _error "asdf not found on PATH"
    return 1
  fi

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
  local abs_path="$1"

  if [[ -z $abs_path ]]; then return; fi

  if [[ -n $HOME ]]; then
    local rel_path=${abs_path#$HOME}
    if [[ $rel_path != "$abs_path" ]]; then
      abs_path="~$rel_path"
    fi
  fi

  printf '%s\n' "$abs_path"
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

function _envrc_hashsum() {
  if command -v sha512sum >/dev/null 2>&1; then
    sha512sum "$1" | cut -d" " -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 512 "$1" | cut -d" " -f1
  else
    _error "No sha512sum or shasum found"
    return 1
  fi
}

function _envrc_spawn_subshell() {
  local path_="$1"
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

  _info "Unloaded $(_user_rel_path "$path_")"

  # After exiting from subshell, ensure we stay in the same working directory
  local last_pwd_in_subshell=$(cat "$envrc_last_subshell_pwd")
  if [ -n "$last_pwd_in_subshell" ] && [[ "${PWD}" != "${last_pwd_in_subshell}" ]] && [ -d "$last_pwd_in_subshell" ]; then
    _debug "Setting last PWD: $last_pwd_in_subshell"
    cd "$last_pwd_in_subshell"
    _envrc_run_check
  fi
}

function _envrc_source() {
  local path_="$1"
  _debug "Loading ${path_}"
  export ENVRC="${path_}"
  export ENVRC_DIR="$(dirname "$ENVRC")"
  export ENVRC_NAME="$(basename "$ENVRC_DIR")"
  export ENVRC_HASH="$(_envrc_hashsum "$ENVRC")"
  if [[ "${ENVRC_DIR}" == "$HOME" ]]; then
    export ENVRC_NAME="~"
  fi

  source "${path_}"

  export ENVRC_PROMPT="${ENVRC_PROMPT:-📜${envrc_name}[${ENVRC_NAME}]}"
  _success "Loaded $(_user_rel_path "$path_")"
}

function _load_envrc() {
  local path_="$1"

  if [[ "${_ENVRC_NESTED_UNLOADED:-}" == "${path_}" ]]; then
    _debug "Skipping loading $path_: was unloaded."
    return
  fi

  if [ -n "${ENVRC}" ] || [[ "${_ENVRC_NESTING_LEVEL:-0}" == "0" ]]; then
    _envrc_spawn_subshell "$path_"
  elif [ -z "${ENVRC}" ]; then
    _envrc_source "$path_"
  fi
}

function _envrc_on_cd() {
  unset _ENVRC_NESTED_UNLOADED
}

function _envrc_run_check() {
  # Leave current shell if we outside .envrc's directory
  if [[ -n "${ENVRC:-}" ]]; then
    local env_dir=$(dirname "${ENVRC:-}")
    if [[ "$PWD" != "$env_dir" && "$PWD" != "$env_dir/"* ]]; then
      _debug "Unloading ${ENVRC}"
      echo "$PWD" > "$envrc_last_subshell_pwd"
      exit
    fi
  fi

  local path_="$(_find_up "$envrc_name")"
  # If it's the same envrc file, do nothing
  if [[ "${ENVRC-}" == "${path_}" ]]; then
    return
  fi

  if [ -f "$path_" ]; then
    _load_envrc "$path_"
  fi
}

function _envrc_hook() {
  local hook=$1

  case $hook in
    zsh)
      add-zsh-hook precmd _envrc_run_check
      add-zsh-hook chpwd _envrc_on_cd
      ;;
  esac
}

function envrc() {
  local cmd=$1
  shift 1

  case $cmd in
    hook)
      _envrc_hook "$@"
      ;;
    use)
      _use "$@"
      ;;
  esac
}

alias use="envrc use"
PATH_add() {
  export PATH="$1:$PATH"
}
