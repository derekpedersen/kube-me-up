#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Compatibility wrapper: keep app-local entrypoint while delegating implementation
# to the canonical installer under k8s-tools.
exec "$ROOT_DIR/k8s-tools/johnny-5-alive.install.sh" "$@"
