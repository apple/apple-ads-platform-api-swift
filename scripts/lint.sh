#!/usr/bin/env bash
#===----------------------------------------------------------------------===#
#
# Copyright (c) 2026 Apple Inc. Licensed under MIT License.
#
# See LICENSE for license information
#
#===----------------------------------------------------------------------===#

# Lint all hand-written Swift sources against .swift-format.
# Exits non-zero if any file doesn't conform.
# Usage: ./scripts/lint.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

find "$REPO_ROOT/Sources/AppleAdsClient" "$REPO_ROOT/Tests/AppleAdsClientTests" \
    "$REPO_ROOT/Tools/Postprocessor/Sources" "$REPO_ROOT/Tools/Postprocessor/Tests" \
    -name "*.swift" -not -path "*/Generated/*" -print0 \
    | xargs -0 swift-format lint --configuration "$REPO_ROOT/.swift-format" --strict --ignore-unparsable-files
