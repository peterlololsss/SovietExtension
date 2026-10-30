#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sovext-regression.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

FILTER="${1:-}"
WECHAT_BINARY="${WECHAT_BINARY:-$REPO_ROOT/analysis/sidebar-wechat-4.1.11/wechat-arm64.dylib}"
passed=0
skipped=0
matched=0

for source in "$REPO_ROOT"/RegressionTests/*Tests.mm; do
    name="$(basename "$source" .mm)"
    if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then continue; fi
    matched=$((matched + 1))
    args=()
    if [ "$name" = DebuggerCheckMaskTests ]; then
        if [ ! -r "$WECHAT_BINARY" ]; then
            echo "SKIP $name (set WECHAT_BINARY to a supported WeChat arm64 image)"
            skipped=$((skipped + 1))
            continue
        fi
        args=("$WECHAT_BINARY")
    fi
    clang++ -std=c++20 -fobjc-arc -Wall -Wextra "$source" \
        -framework AppKit -framework Foundation -framework ApplicationServices \
        -o "$BUILD_DIR/$name"
    "$BUILD_DIR/$name" ${args+"${args[@]}"}
    passed=$((passed + 1))
done

if [ "$matched" -eq 0 ]; then
    echo "No regression tests match: $FILTER" >&2
    exit 2
fi
echo "passed $passed, skipped $skipped"
