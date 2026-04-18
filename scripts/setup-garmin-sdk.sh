#!/usr/bin/env bash
# Pulls the public Connect IQ Mobile SDK for iOS and drops its XCFramework
# into Frameworks/. Intended for fresh clones where the gitignored
# ConnectIQ.xcframework is missing.
#
# Usage:
#     ./scripts/setup-garmin-sdk.sh [tag]
#     tag defaults to 1.8.0

set -euo pipefail

TAG="${1:-1.8.0}"
REPO="https://github.com/garmin/connectiq-companion-app-sdk-ios.git"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Frameworks/ConnectIQ.xcframework"
TMP="$(mktemp -d)"

trap 'rm -rf "$TMP"' EXIT

echo "📦 Fetching ConnectIQ SDK $TAG"
git clone --depth 1 --branch "$TAG" "$REPO" "$TMP/sdk" 2>&1 | tail -2

if [[ -d "$DEST" ]]; then
    echo "🗑  Removing existing $DEST"
    rm -rf "$DEST"
fi

mkdir -p "$ROOT/Frameworks"
cp -R "$TMP/sdk/ConnectIQ.xcframework" "$DEST"

echo "✅ Installed: $DEST"
echo "   Next: tuist install && tuist generate"
