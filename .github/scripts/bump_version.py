#!/usr/bin/env python3
"""Bump the app, Watch, and Live Activity marketing versions.

Usage: python3 .github/scripts/bump_version.py [patch|minor|major]
"""

import re
import os
import sys

PBXPROJ = os.path.join(
    os.path.dirname(__file__),
    "../../JumpRec.xcodeproj/project.pbxproj",
)

TARGETS = [
    # iOS app (exact match — no suffix)
    r"com\.kinn\.JumpRec;",
    # Watch app
    r"com\.kinn\.JumpRec\.watchkitapp;",
    # Live Activity Extension (quoted in the file)
    r'"com\.kinn\.JumpRec\.Jump-Rec-Live-Activity-Extension";',
]


def bump(action: str) -> str:
    with open(PBXPROJ, "r") as f:
        content = f.read()

    # Read current version from the first MARKETING_VERSION occurrence
    m = re.search(r"MARKETING_VERSION = (\d+\.\d+\.\d+);", content)
    if not m:
        sys.exit("ERROR: Could not find MARKETING_VERSION in project.pbxproj")

    current = m.group(1)
    major, minor, patch = map(int, current.split("."))

    if action == "major":
        major += 1
        minor = 0
        patch = 0
    elif action == "minor":
        minor += 1
        patch = 0
    elif action == "patch":
        patch += 1
    else:
        sys.exit(f"ERROR: Unknown action '{action}'. Use patch, minor, or major.")

    new_version = f"{major}.{minor}.{patch}"
    print(f"Version: {current} -> {new_version}")

    for bundle_pattern in TARGETS:
        content, n = re.subn(
            rf"(MARKETING_VERSION = )\d+\.\d+\.\d+(;\s*\n\s*PRODUCT_BUNDLE_IDENTIFIER = {bundle_pattern})",
            rf"\g<1>{new_version}\2",
            content,
        )
        if n == 0:
            print(f"WARNING: no match for bundle pattern: {bundle_pattern}", flush=True)

    with open(PBXPROJ, "w") as f:
        f.write(content)

    print(f"Done. New version: {new_version}")
    return new_version


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(f"Usage: {sys.argv[0]} [patch|minor|major]")
    bump(sys.argv[1])
