#!/usr/bin/env bash
#===----------------------------------------------------------------------===#
#
# Copyright (c) 2026 Apple Inc. Licensed under MIT License.
#
# See LICENSE for license information
#
#===----------------------------------------------------------------------===#

# Verify that tracked Swift sources start with the project's license header.
# Paths listed in .licenseignore are skipped.
# Exits non-zero if any file is missing the header.
# Usage: ./scripts/check-license-headers.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

EXPECTED='// Copyright (c) YEARS Apple Inc. Licensed under MIT License.'

# Turn each .licenseignore line into a git ":(exclude)" pathspec.
excludes=()
while IFS= read -r pattern; do
    [[ -n "$pattern" ]] && excludes+=(":(exclude)$pattern")
done < .licenseignore

missing=()
while IFS= read -r file; do
    # Normalize a year ("2026") or range ("2024-2026") to YEARS.
    first_line=$(head -n 1 "$file" | sed -E -e 's/20[0-9]{2} ?[-–] ?20[0-9]{2}/YEARS/' -e 's/20[0-9]{2}/YEARS/')
    if [[ "$first_line" != "$EXPECTED" ]]; then
        missing+=("$file")
    fi
done < <(git ls-files -- '*.swift' ${excludes[@]+"${excludes[@]}"})

if (( ${#missing[@]} > 0 )); then
    echo "ERROR: missing or incorrect license header in:" >&2
    printf '  %s\n' "${missing[@]}" >&2
    echo "Expected first line: ${EXPECTED/YEARS/<year>}" >&2
    exit 1
fi

echo "All Swift files have the expected license header."
