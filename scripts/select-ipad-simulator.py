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


def screen_inches(name):
    if re.search(r"11-inch|11インチ", name):
        return 11
    if re.search(r"13-inch|13インチ", name):
        return 13
    return None


def requested_inches(argv):
    if len(argv) == 1:
        return None
    if len(argv) == 3 and argv[1] == "--inches" and argv[2] in {"11", "13"}:
        return int(argv[2])
    print("使い方: select-ipad-simulator.py [--inches 11|13]", file=sys.stderr)
    return "invalid"


def main():
    inches = requested_inches(sys.argv)
    if inches == "invalid":
        return 2

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
            size = screen_inches(name)
            if inches is not None and size != inches:
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
        label = f"{inches} インチの " if inches is not None else ""
        print(f"選択中の Xcode で使える {label}iPad シミュレータがありません。", file=sys.stderr)
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
