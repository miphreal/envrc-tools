#!/usr/bin/env bats

setup() {
  TEST_TMPDIR=$(mktemp -d)
  export HOME="$TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$BATS_TEST_DIRNAME/../envrc.sh"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

# --- _user_rel_path ---

@test "_user_rel_path replaces HOME prefix with ~" {
  run _user_rel_path "$HOME/project/foo"
  [ "$status" -eq 0 ]
  [ "$output" = "~/project/foo" ]
}

@test "_user_rel_path leaves non-home path unchanged" {
  run _user_rel_path "/usr/local/bin"
  [ "$status" -eq 0 ]
  [ "$output" = "/usr/local/bin" ]
}

@test "_user_rel_path returns empty for empty input" {
  run _user_rel_path ""
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "_user_rel_path returns ~ for HOME itself" {
  run _user_rel_path "$HOME"
  [ "$status" -eq 0 ]
  [ "$output" = "~" ]
}

# --- _find_up ---

@test "_find_up finds .envrc in current directory" {
  mkdir -p "$TEST_TMPDIR/project"
  touch "$TEST_TMPDIR/project/.envrc"
  cd "$TEST_TMPDIR/project"

  run _find_up ".envrc"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TMPDIR/project/.envrc" ]
}

@test "_find_up finds .envrc in parent directory" {
  mkdir -p "$TEST_TMPDIR/project/subdir"
  touch "$TEST_TMPDIR/project/.envrc"
  cd "$TEST_TMPDIR/project/subdir"

  run _find_up ".envrc"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TMPDIR/project/.envrc" ]
}

@test "_find_up returns empty when .envrc is absent" {
  mkdir -p "$TEST_TMPDIR/empty"
  cd "$TEST_TMPDIR/empty"

  run _find_up ".envrc"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

# --- _envrc_hashsum ---

@test "_envrc_hashsum returns non-empty hash" {
  echo "hello" > "$TEST_TMPDIR/hashfile"

  run _envrc_hashsum "$TEST_TMPDIR/hashfile"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "_envrc_hashsum is consistent for same file" {
  echo "consistent" > "$TEST_TMPDIR/hashfile"

  local hash1 hash2
  hash1=$(_envrc_hashsum "$TEST_TMPDIR/hashfile")
  hash2=$(_envrc_hashsum "$TEST_TMPDIR/hashfile")
  [ "$hash1" = "$hash2" ]
}

@test "_envrc_hashsum differs for different content" {
  echo "content A" > "$TEST_TMPDIR/file_a"
  echo "content B" > "$TEST_TMPDIR/file_b"

  local hash1 hash2
  hash1=$(_envrc_hashsum "$TEST_TMPDIR/file_a")
  hash2=$(_envrc_hashsum "$TEST_TMPDIR/file_b")
  [ "$hash1" != "$hash2" ]
}

# --- PATH_add ---

@test "PATH_add prepends directory to PATH" {
  local orig_path="$PATH"
  PATH_add "/tmp/test-bin"
  [[ "$PATH" == "/tmp/test-bin:"* ]]
  export PATH="$orig_path"
}

# --- Logging ---

@test "_error outputs at verbosity 0" {
  run bash -c 'ENVRC_VERBOSE=0; source "'"$BATS_TEST_DIRNAME"'/../envrc.sh"; _error "test error" 2>&1'
  [[ "$output" == *"test error"* ]]
}

@test "_success is silent at verbosity 0" {
  run bash -c 'ENVRC_VERBOSE=0; source "'"$BATS_TEST_DIRNAME"'/../envrc.sh"; _success "test success" 2>&1'
  [ "$output" = "" ]
}

@test "_success outputs at verbosity 1" {
  run bash -c 'export ENVRC_VERBOSE=1; source "'"$BATS_TEST_DIRNAME"'/../envrc.sh"; _success "test success" 2>&1'
  [[ "$output" == *"test success"* ]]
}

@test "_info is silent at verbosity 1" {
  run bash -c 'export ENVRC_VERBOSE=1; source "'"$BATS_TEST_DIRNAME"'/../envrc.sh"; _info "test info" 2>&1'
  [ "$output" = "" ]
}

@test "_info outputs at verbosity 2" {
  run bash -c 'export ENVRC_VERBOSE=2; source "'"$BATS_TEST_DIRNAME"'/../envrc.sh"; _info "test info" 2>&1'
  [[ "$output" == *"test info"* ]]
}

@test "_debug outputs at verbosity 3" {
  run bash -c 'export ENVRC_VERBOSE=3; source "'"$BATS_TEST_DIRNAME"'/../envrc.sh"; _debug "test debug" 2>&1'
  [[ "$output" == *"test debug"* ]]
}
