#!/usr/bin/env bash
# Release に計測コードと FoundationModels が無いこと、または Debug で
# FoundationModels をコンパイルしていることを、ビルド成果物で確認する。
set -eu

cd "$(dirname "$0")/.."

mode="${1:-release}"
case "$mode" in
  release|debug) ;;
  *)
    echo "使い方: $0 release|debug" >&2
    exit 2
    ;;
esac

try_ios17_launch() {
  local runtime udid device_type ios17_derived ios17_app
  runtime="$(python3 - <<'PY'
import json
import subprocess

raw = subprocess.check_output(
    ["xcrun", "simctl", "list", "runtimes", "available", "-j"],
    text=True,
)
data = json.loads(raw)
best = None
for runtime in data.get("runtimes", []):
    version = str(runtime.get("version", ""))
    name = str(runtime.get("name", ""))
    if not runtime.get("isAvailable"):
        continue
    if not version.startswith("17."):
        continue
    if "iOS" not in name and "iPad" not in name:
        continue
    ident = runtime.get("identifier")
    if best is None or version > best[0]:
        best = (version, ident)
if best:
    print(best[1])
PY
)"
  if [[ -z "$runtime" ]]; then
    echo "iPadOS 17 のシミュレータランタイムは入っていません。起動確認は飛ばします。"
    return 0
  fi

  udid="$(python3 - "$runtime" <<'PY'
import json
import subprocess
import sys

wanted = sys.argv[1]
raw = subprocess.check_output(
    ["xcrun", "simctl", "list", "devices", "available", "-j"],
    text=True,
)
devices = json.loads(raw).get("devices", {})
for runtime_id, entries in devices.items():
    if wanted not in runtime_id and "iOS-17" not in runtime_id:
        continue
    for device in entries:
        name = device.get("name", "")
        if device.get("isAvailable") and "iPad" in name:
            print(device["udid"])
            raise SystemExit
PY
)"
  if [[ -z "$udid" ]]; then
    device_type="$(python3 - <<'PY'
import json
import subprocess

raw = subprocess.check_output(["xcrun", "simctl", "list", "devicetypes", "-j"], text=True)
for item in json.loads(raw).get("devicetypes", []):
    name = item.get("name", "")
    if name.startswith("iPad"):
        print(item["identifier"])
        break
PY
)"
    if [[ -z "$device_type" ]]; then
      echo "iPadOS 17 のランタイムはありますが、iPad のデバイス型がありません。起動確認は飛ばします。"
      return 0
    fi
    if ! udid="$(xcrun simctl create "Kininaru Release iPadOS 17" "$device_type" "$runtime")"; then
      echo "iPadOS 17 の iPad を作れませんでした。起動確認は飛ばします。"
      return 0
    fi
  fi

  echo "iPadOS 17 シミュレータで Release を起動します: ${udid}"
  ios17_derived="build/spike-packaging/Release-iOS17"
  rm -rf "$ios17_derived"
  xcodebuild build \
    -project Kininaru.xcodeproj \
    -scheme Kininaru \
    -configuration Release \
    -destination "platform=iOS Simulator,id=${udid}" \
    -destination-timeout 180 \
    -derivedDataPath "$ios17_derived" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO
  ios17_app="$(find "$ios17_derived/Build/Products" -type d -name 'Kininaru.app' | head -1 || true)"
  if [[ -z "$ios17_app" ]]; then
    echo "iPadOS 17 向けの Kininaru.app が見つかりません" >&2
    exit 1
  fi
  xcrun simctl boot "$udid" || true
  xcrun simctl bootstatus "$udid" -b
  xcrun simctl install "$udid" "$ios17_app"
  xcrun simctl launch "$udid" com.marufeuille.kininaru
  echo "iPadOS 17 シミュレータで Release が起動しました"
}

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen がありません。brew install xcodegen を実行してください。" >&2
  exit 1
fi

xcodegen generate

if [[ "$mode" == "release" ]]; then
  config="Release"
else
  config="Debug"
fi

dest_id="$(python3 scripts/select-ipad-simulator.py)"
derived="build/spike-packaging/${config}"
rm -rf "$derived"

xcodebuild build \
  -project Kininaru.xcodeproj \
  -scheme Kininaru \
  -configuration "$config" \
  -destination "platform=iOS Simulator,id=${dest_id}" \
  -destination-timeout 180 \
  -derivedDataPath "$derived" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

app="$(find "$derived/Build/Products" -type d -name 'Kininaru.app' | head -1 || true)"
if [[ -z "$app" ]]; then
  echo "Kininaru.app が見つかりません (${derived})" >&2
  exit 1
fi
echo "確認するアプリ: $app"

machos=()
while IFS= read -r -d '' candidate; do
  if file "$candidate" | grep -q 'Mach-O'; then
    machos+=("$candidate")
  fi
done < <(find "$app" -type f -print0)

if [[ "${#machos[@]}" -eq 0 ]]; then
  echo "Mach-O がありません" >&2
  exit 1
fi

linked=0
has_spike_string=0
for bin in "${machos[@]}"; do
  echo "== otool -L ${bin#"$app"/}"
  otool -L "$bin"
  if otool -L "$bin" | grep -q 'FoundationModels'; then
    linked=1
  fi
  if strings "$bin" | grep -F -q 'deviceNotEligible'; then
    has_spike_string=1
  fi
  if ! otool -l "$bin" | grep -q 'minos 17.0'; then
    echo "${bin} の最低 OS が 17.0 ではありません" >&2
    otool -l "$bin" | grep -n 'minos' || true
    exit 1
  fi
done

resources="$(find "$app" \( -name 'speech-sample.wav' -o -name 'source-excerpt.txt' \) || true)"
plist="$(plutil -p "$app/Info.plist")"
has_privacy=0
if grep -E -q 'NSSpeechRecognitionUsageDescription|NSMicrophoneUsageDescription' <<<"$plist"; then
  has_privacy=1
fi

if [[ "$mode" == "release" ]]; then
  if [[ "$linked" -ne 0 ]]; then
    echo "Release が FoundationModels をリンクしています" >&2
    exit 1
  fi
  if [[ "$has_spike_string" -ne 0 ]]; then
    echo "Release のバイナリに計測の文字列 deviceNotEligible があります" >&2
    exit 1
  fi
  if [[ -n "$resources" ]]; then
    echo "Release に計測の同梱ファイルがあります" >&2
    echo "$resources" >&2
    exit 1
  fi
  if [[ "$has_privacy" -ne 0 ]]; then
    echo "Release の Info.plist に音声認識かマイクの利用目的があります" >&2
    exit 1
  fi
  echo "Release のパッケージ確認: FoundationModels なし、計測リソースなし、利用目的なし"
  try_ios17_launch
else
  if [[ "$linked" -eq 0 ]]; then
    echo "Debug が FoundationModels をリンクしていません。計測の生成コードがコンパイルされていません。" >&2
    exit 1
  fi
  if [[ "$has_spike_string" -eq 0 ]]; then
    echo "Debug のバイナリに deviceNotEligible がありません" >&2
    exit 1
  fi
  if [[ "$resources" != *"speech-sample.wav"* || "$resources" != *"source-excerpt.txt"* ]]; then
    echo "Debug に計測の同梱ファイルがありません" >&2
    echo "見つかったもの: ${resources:-なし}" >&2
    exit 1
  fi
  if [[ "$has_privacy" -eq 0 ]]; then
    echo "Debug の Info.plist に音声認識とマイクの利用目的がありません" >&2
    exit 1
  fi
  echo "Debug のパッケージ確認: FoundationModels をリンク、計測リソースあり"
fi
