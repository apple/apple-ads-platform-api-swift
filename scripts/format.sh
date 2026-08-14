#!/usr/bin/env bash
#===----------------------------------------------------------------------===#
#
# Copyright (c) 2026 Apple Inc. Licensed under MIT License.
#
# See LICENSE for license information
#
#===----------------------------------------------------------------------===#

# Format all hand-written Swift sources using .swift-format.
# Usage: ./scripts/format.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

find "$REPO_ROOT/Sources/AppleAdsClient" "$REPO_ROOT/Tests/AppleAdsClientTests" \
    "$REPO_ROOT/Tools/Postprocessor/Sources" "$REPO_ROOT/Tools/Postprocessor/Tests" \
    -name "*.swift" -not -path "*/Generated/*" \
    | xargs swift-format format -i --configuration "$REPO_ROOT/.swift-format"
