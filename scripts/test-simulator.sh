#!/usr/bin/env bash
# XcodeGen でプロジェクトを作り、iPad シミュレータで単体テストと UI テストを実行する。
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen がありません。brew install xcodegen を実行してください。" >&2
  exit 1
fi

xcodegen generate

DEST_ID="$(python3 scripts/select-ipad-simulator.py)"

# ソフトウェアキーボードを出して、調べるが隠れないことを UI テストで見る。
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false
xcrun simctl shutdown all || true

mkdir -p build
xcodebuild test \
  -project Kininaru.xcodeproj \
  -scheme Kininaru \
  -destination "platform=iOS Simulator,id=${DEST_ID}" \
  -destination-timeout 180 \
  -parallel-testing-enabled NO \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  | tee build/xcodebuild.log
