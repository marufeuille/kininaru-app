#!/usr/bin/env bash
# XcodeGen でプロジェクトを作り、iPad シミュレータで単体テストと UI テストを実行する。
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen がありません。brew install xcodegen を実行してください。" >&2
  exit 1
fi

xcodegen generate

DEST_13="$(python3 scripts/select-ipad-simulator.py --inches 13)"
DEST_11="$(python3 scripts/select-ipad-simulator.py --inches 11)"

# ソフトウェアキーボードを出して、調べるが隠れないことを UI テストで見る。
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false
xcrun simctl shutdown all || true

mkdir -p build
rm -rf /tmp/kininaru-ui-screenshots
: > build/xcodebuild.log

# 単体テストは 13 インチで 1 回。UI テストは 13 インチと、実機に近い 11 インチの両方。
run_xcodebuild() {
  local dest_id="$1"
  shift
  xcodebuild test \
    -project Kininaru.xcodeproj \
    -scheme Kininaru \
    -destination "platform=iOS Simulator,id=${dest_id}" \
    -destination-timeout 180 \
    -parallel-testing-enabled NO \
    "$@" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    | tee -a build/xcodebuild.log
  return "${PIPESTATUS[0]}"
}

set +e
run_xcodebuild "$DEST_13"
status=$?
if [[ "$status" -eq 0 ]]; then
  run_xcodebuild "$DEST_11" -only-testing:KininaruUITests
  status=$?
fi
set -e

mkdir -p build/ui-screenshots
if [ -d /tmp/kininaru-ui-screenshots ]; then
  cp -R /tmp/kininaru-ui-screenshots/. build/ui-screenshots/ || true
fi
exit "$status"
