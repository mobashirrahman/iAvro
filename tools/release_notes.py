#!/usr/bin/env python3
"""
release_notes.py

Prints the change log section for one version, for use as GitHub release notes.

    tools/release_notes.py 2.0.7

Notes are read from CHANGELOG.md rather than from the annotated tag: the tag
object is not reliably available on the runner, and reading it produced the
tagged commit's message instead of the tag's own text. The change log is
already the canonical record of what changed, and is in the working tree.

Exits non-zero when the version has no section, so a release cannot silently
publish with no notes.
"""

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHANGELOG = os.path.join(ROOT, "CHANGELOG.md")


def section_for(version, text):
    """Body of the '## <version>' section, excluding the heading itself."""
    lines = text.split("\n")
    heading = re.compile(r"^##\s+" + re.escape(version) + r"\s*$")
    start = None
    for index, line in enumerate(lines):
        if heading.match(line):
            start = index + 1
            break
    if start is None:
        return None

    end = len(lines)
    for index in range(start, len(lines)):
        if re.match(r"^##\s+\S", lines[index]):
            end = index
            break

    body = "\n".join(lines[start:end]).strip("\n")
    return body if body.strip() else None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("version", help="e.g. 2.0.7")
    parser.add_argument("--changelog", default=CHANGELOG)
    parser.add_argument("--allow-empty", action="store_true",
                        help="exit 0 with no output when the section is missing")
    args = parser.parse_args()

    try:
        with open(args.changelog, encoding="utf-8") as handle:
            text = handle.read()
    except OSError as error:
        print("cannot read %s: %s" % (args.changelog, error), file=sys.stderr)
        return 2

    body = section_for(args.version, text)
    if body is None:
        if args.allow_empty:
            return 0
        print("no changelog section found for version %s" % args.version,
              file=sys.stderr)
        return 1

    print(body)
    return 0


if __name__ == "__main__":
    sys.exit(main())
