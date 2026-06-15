#!/usr/bin/env python3
"""Fail if any relative markdown link in the repo's docs points to a missing file.

Checks internal `[text](relative/path)` links only; ignores http(s)/mailto/anchor links.
Run from anywhere: `python3 scripts/check-doc-links.py`.
"""
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent
markdown_files = [
    p for p in root.rglob("*.md") if ".build" not in p.parts and ".git" not in p.parts
]
link_re = re.compile(r"\[[^\]]*\]\(([^)]+)\)")

dead: list[str] = []
for md in markdown_files:
    for match in link_re.finditer(md.read_text(encoding="utf-8")):
        target = match.group(1).strip()
        if target.startswith(("http://", "https://", "#", "mailto:")):
            continue
        path = target.split("#", 1)[0]
        if not path:
            continue
        if not (md.parent / path).resolve().exists():
            dead.append(f"{md.relative_to(root)} -> {target}")

if dead:
    print("::error::Dead relative doc links found:")
    print("\n".join(dead))
    sys.exit(1)

print(f"OK: no dead relative links across {len(markdown_files)} markdown files.")
