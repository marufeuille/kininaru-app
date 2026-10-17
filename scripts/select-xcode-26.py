#!/usr/bin/env python3
"""Print the path of the newest installed Xcode 26, or nothing."""

import os
import re
import sys

apps = []
for name in os.listdir("/Applications"):
    match = re.fullmatch(r"Xcode_26(?:\.(\d+))?(?:\.(\d+))?\.app", name)
    if not match:
        continue
    minor = int(match.group(1) or 0)
    patch = int(match.group(2) or 0)
    apps.append((minor, patch, os.path.join("/Applications", name)))

if not apps:
    print("Xcode 26 がありません", file=sys.stderr)
    sys.exit(1)

apps.sort()
print(apps[-1][2])
