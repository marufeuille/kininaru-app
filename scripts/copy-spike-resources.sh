#!/usr/bin/env bash
# 計測の同梱ファイルは Debug だけアプリに入れる。Release には置かない。
set -euo pipefail

if [[ "${CONFIGURATION:-}" != "Debug" ]]; then
  exit 0
fi

dest="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
src="${SRCROOT}/Kininaru/Spike/Resources"
mkdir -p "${dest}"
cp "${src}/speech-sample.wav" "${dest}/speech-sample.wav"
cp "${src}/source-excerpt.txt" "${dest}/source-excerpt.txt"
