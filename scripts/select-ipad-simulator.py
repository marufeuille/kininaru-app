#!/usr/bin/env python3
"""Pick an available iPad simulator for the selected Xcode SDK."""

import json
import re
import subprocess
import sys


def sdk_version():
    raw = subprocess.check_output(
        ["xcodebuild", "-version", "-sdk", "iphonesimulator", "SDKVersion"],
        text=True,
    ).strip()
    parts = tuple(int(piece) for piece in raw.split("."))
    return parts


def runtime_version(runtime_id):
    match = re.search(r"iOS-(\d+)-(\d+)(?:-(\d+))?", runtime_id)
    if not match:
        return None
    return tuple(int(piece) for piece in match.groups() if piece is not None)


def name_rank(name):
    if "iPad Pro" in name:
        return 3
    if "iPad Air" in name:
        return 2
    if name.startswith("iPad"):
        return 1
    return 0


def main():
    sdk = sdk_version()
    print(f"iOS Simulator SDK {'.'.join(str(part) for part in sdk)}", file=sys.stderr)
    payload = json.loads(
        subprocess.check_output(
            ["xcrun", "simctl", "list", "devices", "available", "-j"],
            text=True,
        )
    )
    candidates = []
    for runtime_id, devices in payload.get("devices", {}).items():
        version = runtime_version(runtime_id)
        if version is None or version[0] != sdk[0]:
            continue
        for device in devices:
            name = device.get("name", "")
            if not device.get("isAvailable") or "iPad" not in name:
                continue
            candidates.append(
                {
                    "version": version,
                    "exact": version[: len(sdk)] == sdk or version[:2] == sdk[:2],
                    "rank": name_rank(name),
                    "name": name,
                    "udid": device["udid"],
                }
            )

    if not candidates:
        print("選択中の Xcode で使える iPad シミュレータがありません。", file=sys.stderr)
        return 1

    candidates.sort(
        key=lambda item: (
            item["exact"],
            item["version"],
            item["rank"],
            item["name"],
        )
    )
    chosen = candidates[-1]
    version = ".".join(str(part) for part in chosen["version"])
    print(
        f"{chosen['name']} / iOS {version} / {chosen['udid']}",
        file=sys.stderr,
    )
    print(chosen["udid"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
