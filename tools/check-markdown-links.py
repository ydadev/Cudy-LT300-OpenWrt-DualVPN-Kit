#!/usr/bin/env python3
"""Check relative Markdown links without downloading external URLs."""

from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote


LINK_RE = re.compile(r"(?<!!)\[[^\]]*\]\(([^)]+)\)")


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    errors: list[str] = []

    for document in sorted(root.rglob("*.md")):
        if ".git" in document.parts or "dist" in document.parts:
            continue
        text = document.read_text(encoding="utf-8")
        for match in LINK_RE.finditer(text):
            raw = match.group(1).strip().strip("<>")
            if not raw or raw.startswith(("http://", "https://", "mailto:", "#")):
                continue
            target = unquote(raw.split("#", 1)[0])
            if not target:
                continue
            resolved = (document.parent / target).resolve()
            try:
                resolved.relative_to(root)
            except ValueError:
                errors.append(f"{document.relative_to(root)}: link leaves repository: {raw}")
                continue
            if not resolved.exists():
                errors.append(f"{document.relative_to(root)}: missing link target: {raw}")

    if errors:
        print("Markdown link check failed:", file=sys.stderr)
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("Markdown links: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
