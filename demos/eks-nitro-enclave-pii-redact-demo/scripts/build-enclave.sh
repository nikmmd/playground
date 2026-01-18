#!/bin/bash
set -euo pipefail

# Build Nitro Enclave Image (EIF) and Parent App Binary
#
# Usage:
#   ./build-enclave.sh              # Build using local nitro-cli (if available)
#   ./build-enclave.sh --docker     # Build using dockerized nitro-cli

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENCLAVE_DIR="$PROJECT_DIR/enclave"
PARENT_DIR="$PROJECT_DIR/parent-app"
OUTPUT_DIR="$PROJECT_DIR/build"

IMAGE_TAG="${IMAGE_TAG:-latest}"
USE_DOCKER_BUILDER=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
  --docker)
    USE_DOCKER_BUILDER=true
    shift
    ;;
  *)
    echo "Unknown option: $1"
    echo "Usage: $0 [--docker]"
    exit 1
    ;;
  esac
done

echo "============================================================"
echo "Building PII Redaction Artifacts"
echo "============================================================"
echo "  Enclave Source: $ENCLAVE_DIR"
echo "  Parent App Source: $PARENT_DIR"
echo "  Output: $OUTPUT_DIR"
echo "  Use Docker Builder: $USE_DOCKER_BUILDER"
echo ""

mkdir -p "$OUTPUT_DIR"

# Build EIF using dockerized nitro-cli
build_eif_docker() {
  local BUILDER_IMAGE="nitro-cli-builder:latest"
  local ENCLAVE_IMAGE="pii-detection-enclave:$IMAGE_TAG"

  echo "Step 1: Building nitro-cli builder image..."
  docker build -t "$BUILDER_IMAGE" -f "docker/Dockerfile.nitro-cli" "$PROJECT_DIR"

  echo ""
  echo "Step 2: Building enclave Docker image..."
  docker build -t "$ENCLAVE_IMAGE" "$ENCLAVE_DIR"

  echo ""
  echo "Step 3: Building EIF using dockerized nitro-cli..."
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$OUTPUT_DIR":/output \
    "$BUILDER_IMAGE" \
    nitro-cli build-enclave \
    --docker-uri "$ENCLAVE_IMAGE" \
    --output-file /output/pii-detection.eif

  echo ""
  echo "Step 4: Extracting PCR0..."
  docker run --rm \
    -v "$OUTPUT_DIR":/output \
    "$BUILDER_IMAGE" \
    sh -c "nitro-cli describe-eif --eif-path /output/pii-detection.eif | jq -r '.Measurements.PCR0'" \
    >"$OUTPUT_DIR/pcr0.txt"

  echo ""
  echo "EIF Information:"
  docker run --rm \
    -v "$OUTPUT_DIR":/output \
    "$BUILDER_IMAGE" \
    nitro-cli describe-eif --eif-path /output/pii-detection.eif
}

# Build EIF using local nitro-cli
build_eif_local() {
  local ENCLAVE_IMAGE="pii-detection-enclave:$IMAGE_TAG"

  echo "Step 1: Building enclave Docker image..."
  docker build -t "$ENCLAVE_IMAGE" "$ENCLAVE_DIR"

  echo ""
  echo "Step 2: Building EIF..."
  nitro-cli build-enclave \
    --docker-uri "$ENCLAVE_IMAGE" \
    --output-file "$OUTPUT_DIR/pii-detection.eif"

  echo ""
  echo "Step 3: Extracting PCR0..."
  nitro-cli describe-eif --eif-path "$OUTPUT_DIR/pii-detection.eif" |
    jq -r '.Measurements.PCR0' >"$OUTPUT_DIR/pcr0.txt"

  echo ""
  echo "EIF Information:"
  nitro-cli describe-eif --eif-path "$OUTPUT_DIR/pii-detection.eif"
}

# Build EIF
EIF_BUILT=false
if [ "$USE_DOCKER_BUILDER" = true ]; then
  if ! command -v docker &>/dev/null; then
    echo "ERROR: Docker is required for --docker mode"
    exit 1
  fi
  build_eif_docker
  EIF_BUILT=true
else
  if ! command -v nitro-cli &>/dev/null; then
    echo "WARNING: nitro-cli not found locally."
    echo ""
    echo "Options:"
    echo "  1. Run with --docker flag to use dockerized nitro-cli"
    echo "  2. Install nitro-cli on Amazon Linux 2023:"
    echo "     sudo dnf install -y aws-nitro-enclaves-cli aws-nitro-enclaves-cli-devel"
    echo ""
  elif ! command -v docker &>/dev/null; then
    echo "WARNING: Docker not found. Cannot build EIF."
  else
    build_eif_local
    EIF_BUILT=true
  fi
fi

# Build Go parent app
echo ""
echo "Building Go parent app..."

if ! command -v go &>/dev/null; then
  echo "WARNING: Go not found locally. Trying Docker..."
  docker run --rm \
    -v "$PARENT_DIR":/app \
    -v "$OUTPUT_DIR":/output \
    -w /app \
    golang:1.25-alpine \
    go build -o /output/pii-detection-parent .
  echo "Parent app built via Docker: $OUTPUT_DIR/pii-detection-parent"
else
  cd "$PARENT_DIR"
  GOOS=linux GOARCH=amd64 GOAMD64=v3 go build -o "$OUTPUT_DIR/pii-detection-parent" .
  echo "Parent app built: $OUTPUT_DIR/pii-detection-parent"
fi

echo ""
echo "============================================================"
echo "Build complete!"
echo "============================================================"
echo ""
echo "Artifacts:"
ls -la "$OUTPUT_DIR/" 2>/dev/null | grep -E '\.eif|pii-detection-parent|pcr0' || echo "  (no artifacts found)"

if [ "$EIF_BUILT" = true ] && [ -f "$OUTPUT_DIR/pcr0.txt" ]; then
  echo ""
  echo "PCR0: $(cat "$OUTPUT_DIR/pcr0.txt")"
  echo "Saved to: $OUTPUT_DIR/pcr0.txt"
fi
