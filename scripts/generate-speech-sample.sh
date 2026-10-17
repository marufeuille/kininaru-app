#!/usr/bin/env bash
# 計測用の短い日本語 WAV を作り直す。実行時には使わない。
# 必要: espeak-ng（日本語音声）、python3
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v espeak-ng >/dev/null 2>&1; then
  echo "espeak-ng がありません。" >&2
  exit 1
fi

python3 - <<'PY'
import array
import struct
import subprocess
import sys
import wave
from pathlib import Path

script = "そらわなぜあおいの。たいようのひかりがくうきのなかでちらばるからです。"
raw = Path("/tmp/kininaru-speech-sample-espeak.wav")
subprocess.check_call(["espeak-ng", "-v", "ja", "-s", "120", "-w", str(raw), script])

with wave.open(str(raw)) as src:
    if src.getnchannels() != 1 or src.getsampwidth() != 2:
        raise SystemExit("espeak-ng の WAV が mono 16-bit ではありません")
    rate = src.getframerate()
    frames = src.readframes(src.getnframes())

samples = list(struct.unpack("<" + "h" * (len(frames) // 2), frames))
dst_rate = 16000
dst_len = int(len(samples) * dst_rate / rate)
resampled = []
for index in range(dst_len):
    pos = index * rate / dst_rate
    left = int(pos)
    frac = pos - left
    a = samples[min(left, len(samples) - 1)]
    b = samples[min(left + 1, len(samples) - 1)]
    resampled.append(int(a + (b - a) * frac))

pad = int(0.15 * dst_rate)
resampled = [0] * pad + resampled + [0] * pad
out = Path("Kininaru/Spike/Resources/speech-sample.wav")
pcm = array.array("h", resampled)
if sys.byteorder != "little":
    pcm.byteswap()
with wave.open(str(out), "w") as dst:
    dst.setnchannels(1)
    dst.setsampwidth(2)
    dst.setframerate(dst_rate)
    dst.writeframes(pcm.tobytes())
print(f"{out} {len(resampled) / dst_rate:.3f}s")
PY
