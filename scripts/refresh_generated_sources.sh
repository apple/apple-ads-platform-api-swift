#!/usr/bin/env bash
set -euo pipefail

if ! command -v swift &>/dev/null; then
  echo "Error: swift toolchain not found in PATH"
  exit 1
fi

if ! command -v swift-openapi-generator &>/dev/null; then
  echo "Error: swift-openapi-generator not found in PATH"
  echo "Install via: brew install swift-openapi-generator"
  exit 1
fi

if [ $# -ne 2 ]; then
  echo "Usage: $0 <spec-tag> <path-to-openapi-spec>"
  exit 1
fi

SPEC_TAG="$1"
SPEC_FILE="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -f "$SPEC_FILE" ]; then
  echo "Error: Spec file not found at $SPEC_FILE"
  exit 1
fi

# Generate to a temp directory, then copy output into the source tree
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

swift-openapi-generator generate \
  "$SPEC_FILE" \
  --config "$ROOT_DIR/Sources/AppleAdsClient/openapi-generator-config.yaml" \
  --output-directory "$WORK_DIR"

GENERATED_DIR="$ROOT_DIR/Sources/AppleAdsClient/Generated"
rm -rf "$GENERATED_DIR"
mkdir -p "$GENERATED_DIR"
cp -R "$WORK_DIR"/. "$GENERATED_DIR"

# Rewrite closed enums to open structs (resilient to unknown server values)
echo "Post-processing generated code..."
swift run --package-path "$ROOT_DIR/Tools/Postprocessor" postprocessor "$GENERATED_DIR/Types.swift" --in-place

echo "Generated code in Sources/AppleAdsClient/Generated/"
ls -la "$GENERATED_DIR"

# Update spec version and patch version
PREV_SPEC_TAG=$(cat "$ROOT_DIR/spec.version" 2>/dev/null || true)
printf '%s\n' "$SPEC_TAG" > "$ROOT_DIR/spec.version"
if [ "$SPEC_TAG" != "$PREV_SPEC_TAG" ]; then
  printf '%s\n' "0" > "$ROOT_DIR/patch.version"
fi

echo "Done. Run 'swift build' to verify."
