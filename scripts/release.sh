#!/usr/bin/env bash
# App Store 제출용 아카이브·업로드.
#
# 사전 조건 (둘 중 하나):
#   A) Xcode → Settings → Accounts 에 Apple ID 추가 (자동 서명)
#   B) App Store Connect API 키를 ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8 에 두고
#      ASC_KEY_ID / ASC_ISSUER_ID 환경변수 설정
#
# 사용법:
#   ./scripts/release.sh archive        # 아카이브만
#   ./scripts/release.sh upload         # 아카이브 + App Store Connect 업로드
#
# 업로드 후 심사 제출은 App Store Connect 웹에서 진행한다.
# "이번 버전의 새로운 기능" 문구는 docs/release-notes/<버전>.md 에 있다.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

WORKSPACE="HyroxSim.xcworkspace"
SCHEME="HyroxSim"
VERSION="$(grep -m1 'let appVersion' Projects/HyroxSim/Project.swift | sed -E 's/.*"([^"]+)".*/\1/')"
BUILD="$(grep -m1 'let appBuildNumber' Projects/HyroxSim/Project.swift | sed -E 's/.*"([^"]+)".*/\1/')"
ARCHIVE="build/HyroxSim-${VERSION}-${BUILD}.xcarchive"
EXPORT_DIR="build/export-${VERSION}-${BUILD}"
MODE="${1:-archive}"

echo "▸ HyroxSim ${VERSION} (${BUILD}) — ${MODE}"

if [[ ! -d "$WORKSPACE" ]]; then
    echo "  워크스페이스가 없다. 먼저: tuist install && tuist generate"
    exit 1
fi

AUTH_ARGS=()
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
    echo "  인증: App Store Connect API 키 (${ASC_KEY_ID})"
    AUTH_ARGS=(
        -authenticationKeyID "$ASC_KEY_ID"
        -authenticationKeyIssuerID "$ASC_ISSUER_ID"
        -authenticationKeyPath "$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
    )
else
    echo "  인증: Xcode 에 등록된 Apple ID (자동 서명)"
fi

# 프로젝트는 릴리스에서 수동 서명(이름이 정해진 배포 프로필)을 쓴다. 그 프로필이 계정에
# 없으면 아카이브가 막히므로, 아카이브할 때만 자동 서명으로 덮어쓴다.
# 수동 프로필을 그대로 쓰고 싶으면 MANUAL_SIGNING=1 로 실행한다.
SIGN_ARGS=()
if [[ "${MANUAL_SIGNING:-0}" != "1" ]]; then
    SIGN_ARGS=(
        CODE_SIGN_STYLE=Automatic
        DEVELOPMENT_TEAM=M79H9K226Y
        PROVISIONING_PROFILE_SPECIFIER=
        CODE_SIGN_IDENTITY=
    )
fi

echo "▸ 아카이브"
xcodebuild archive \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"} \
    ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"}

echo "▸ 아카이브 완료: $ARCHIVE"

# 계정이 없으면 xcodebuild 는 조용히 *서명 없는* 아카이브를 만든다. 업로드 단계에서야
# 실패하므로 여기서 먼저 잡는다.
APP="$ARCHIVE/Products/Applications/HyroxSim.app"
if ! codesign -dv "$APP" 2>&1 | grep -q "Authority"; then
    echo
    echo "  ✗ 서명되지 않은 아카이브다. App Store 에 업로드할 수 없다."
    echo "    Xcode → Settings → Accounts 에 Apple ID 를 추가하거나,"
    echo "    ASC_KEY_ID / ASC_ISSUER_ID 를 설정한 뒤 다시 실행할 것."
    exit 2
fi
echo "  서명: $(codesign -dv "$APP" 2>&1 | grep Authority | head -1 | sed 's/^Authority=//')"

if [[ "$MODE" != "upload" ]]; then
    echo "  업로드까지 하려면: $0 upload"
    exit 0
fi

echo "▸ 내보내기 · 업로드"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist scripts/ExportOptions.plist \
    -exportPath "$EXPORT_DIR" \
    -allowProvisioningUpdates \
    ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"}

echo "▸ 업로드 완료. App Store Connect 에서 빌드 처리(보통 10~30분)를 기다린 뒤 심사 제출."
