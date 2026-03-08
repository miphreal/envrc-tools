#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

docker build -t envrc-tests -f tests/Dockerfile .
docker run --rm envrc-tests sh -c '
  echo "=== shellcheck ==="
  shellcheck envrc.sh
  echo ""
  echo "=== bats ==="
  bats tests/
'
