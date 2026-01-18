#!/bin/bash
# DEPRECATED: Use 'make deploy' or the new workflow instead:
#   ./scripts/setup-env.sh   # Generate k8s/.env
#   make deploy              # Deploy with envsubst
#
# This script is kept for backward compatibility.

set -euo pipefail

echo "NOTE: This script is deprecated. Use 'make deploy' instead."
echo ""
echo "New workflow:"
echo "  1. ./scripts/setup-env.sh  # Generate k8s/.env from terraform"
echo "  2. make deploy             # Deploy with kustomize + envsubst"
echo ""
read -p "Continue with old script? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

# Fall back to setup-env.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/setup-env.sh"

echo ""
echo "Now run: make deploy"
