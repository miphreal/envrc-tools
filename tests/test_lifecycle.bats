#!/usr/bin/env bats

setup() {
  TEST_TMPDIR=$(mktemp -d)
  export HOME="$TEST_TMPDIR/home"
  mkdir -p "$HOME"
  ENVRC_SH="$BATS_TEST_DIRNAME/../envrc.sh"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

# --- Hook registration ---

@test "envrc hook zsh registers hooks without error" {
  run zsh -c 'autoload -Uz add-zsh-hook; source "'"$ENVRC_SH"'"; envrc hook zsh'
  [ "$status" -eq 0 ]
}

# --- _envrc_source ---

@test "_envrc_source sets all state variables" {
  local dir="$TEST_TMPDIR/myproject"
  mkdir -p "$dir"
  echo 'export SOURCED_VAR=hello' > "$dir/.envrc"

  run bash -c '
    export _ENVRC_NESTING_LEVEL=1
    source "'"$ENVRC_SH"'"
    _envrc_source "'"$dir"'/.envrc"
    echo "ENVRC=$ENVRC"
    echo "ENVRC_DIR=$ENVRC_DIR"
    echo "ENVRC_NAME=$ENVRC_NAME"
    echo "ENVRC_HASH_SET=$( [ -n "$ENVRC_HASH" ] && echo yes || echo no )"
    echo "ENVRC_PROMPT=$ENVRC_PROMPT"
    echo "SOURCED_VAR=$SOURCED_VAR"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"ENVRC=$dir/.envrc"* ]]
  [[ "$output" == *"ENVRC_DIR=$dir"* ]]
  [[ "$output" == *"ENVRC_NAME=myproject"* ]]
  [[ "$output" == *"ENVRC_HASH_SET=yes"* ]]
  [[ "$output" == *"SOURCED_VAR=hello"* ]]
}

@test "_envrc_source sets ENVRC_NAME to ~ for home directory" {
  echo "" > "$HOME/.envrc"

  run bash -c '
    export HOME="'"$HOME"'"
    export _ENVRC_NESTING_LEVEL=1
    source "'"$ENVRC_SH"'"
    _envrc_source "'"$HOME"'/.envrc"
    echo "ENVRC_NAME=$ENVRC_NAME"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"ENVRC_NAME=~"* ]]
}

# --- _envrc_run_check ---

@test "_envrc_run_check sources .envrc in subshell context" {
  local dir="$TEST_TMPDIR/project"
  mkdir -p "$dir"
  echo 'export LIFECYCLE_TEST=loaded' > "$dir/.envrc"

  run bash -c '
    export _ENVRC_NESTING_LEVEL=1
    source "'"$ENVRC_SH"'"
    cd "'"$dir"'"
    _envrc_run_check
    echo "ENVRC=$ENVRC"
    echo "LIFECYCLE_TEST=$LIFECYCLE_TEST"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"ENVRC=$dir/.envrc"* ]]
  [[ "$output" == *"LIFECYCLE_TEST=loaded"* ]]
}

@test "_envrc_run_check exits when outside ENVRC_DIR" {
  local dir="$TEST_TMPDIR/project"
  local other="$TEST_TMPDIR/other"
  mkdir -p "$dir" "$other"
  touch "$dir/.envrc"

  run bash -c '
    source "'"$ENVRC_SH"'"
    export ENVRC="'"$dir"'/.envrc"
    export ENVRC_DIR="'"$dir"'"
    cd "'"$other"'"
    _envrc_run_check
    echo "SHOULD_NOT_REACH"
  '
  [[ "$output" != *"SHOULD_NOT_REACH"* ]]
}

@test "_envrc_run_check exits for sibling directory with common prefix" {
  local dir="$TEST_TMPDIR/proj"
  local sibling="$TEST_TMPDIR/proj-other"
  mkdir -p "$dir" "$sibling"
  touch "$dir/.envrc"

  run bash -c '
    source "'"$ENVRC_SH"'"
    export ENVRC="'"$dir"'/.envrc"
    export ENVRC_DIR="'"$dir"'"
    cd "'"$sibling"'"
    _envrc_run_check
    echo "SHOULD_NOT_REACH"
  '
  [[ "$output" != *"SHOULD_NOT_REACH"* ]]
}

@test "_envrc_run_check records PWD in temp file on exit" {
  local dir="$TEST_TMPDIR/project"
  local other="$TEST_TMPDIR/other"
  local tmpfile="$TEST_TMPDIR/last-pwd"
  mkdir -p "$dir" "$other"
  touch "$dir/.envrc"

  bash -c '
    source "'"$ENVRC_SH"'"
    envrc_last_subshell_pwd="'"$tmpfile"'"
    trap "" EXIT
    export ENVRC="'"$dir"'/.envrc"
    export ENVRC_DIR="'"$dir"'"
    cd "'"$other"'"
    _envrc_run_check
  ' || true

  [ -f "$tmpfile" ]
  [ "$(cat "$tmpfile")" = "$other" ]
}

@test "_envrc_run_check does nothing if same .envrc already loaded" {
  local dir="$TEST_TMPDIR/project"
  mkdir -p "$dir"
  echo 'export RELOAD_COUNT=$((${RELOAD_COUNT:-0}+1))' > "$dir/.envrc"

  run bash -c '
    export _ENVRC_NESTING_LEVEL=1
    source "'"$ENVRC_SH"'"
    cd "'"$dir"'"
    _envrc_run_check
    _envrc_run_check
    echo "RELOAD_COUNT=$RELOAD_COUNT"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"RELOAD_COUNT=1"* ]]
}

# --- _ENVRC_NESTED_UNLOADED guard ---

@test "_load_envrc skips when _ENVRC_NESTED_UNLOADED matches" {
  local dir="$TEST_TMPDIR/project"
  mkdir -p "$dir"
  echo 'export GUARD_TEST=loaded' > "$dir/.envrc"

  run bash -c '
    export _ENVRC_NESTING_LEVEL=1
    source "'"$ENVRC_SH"'"
    _ENVRC_NESTED_UNLOADED="'"$dir"'/.envrc"
    _load_envrc "'"$dir"'/.envrc"
    echo "ENVRC=${ENVRC:-empty}"
    echo "GUARD_TEST=${GUARD_TEST:-empty}"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"ENVRC=empty"* ]]
  [[ "$output" == *"GUARD_TEST=empty"* ]]
}

@test "_envrc_on_cd clears _ENVRC_NESTED_UNLOADED" {
  run bash -c '
    source "'"$ENVRC_SH"'"
    _ENVRC_NESTED_UNLOADED="/some/path/.envrc"
    _envrc_on_cd
    echo "GUARD=${_ENVRC_NESTED_UNLOADED:-cleared}"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"GUARD=cleared"* ]]
}
