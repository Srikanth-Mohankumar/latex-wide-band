#!/usr/bin/env python3
"""Conservative PDF text-bound check for regression documents.

Checks that non-footer words remain inside a safe article type-area envelope.
This catches the original failure mode where an exact-height vbox concealed
content protruding toward or beyond the physical page bottom.
"""
from __future__ import annotations
import re
import subprocess
import sys
import tempfile
from pathlib import Path

NS = {"x": "http://www.w3.org/1999/xhtml"}


def check(pdf: Path) -> list[str]:
    with tempfile.TemporaryDirectory() as td:
        html = Path(td) / "bbox.html"
        subprocess.run(
            ["pdftotext", "-bbox-layout", str(pdf), str(html)],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        data = html.read_text(errors="replace")

    errors: list[str] = []
    page_re = re.compile(
        r'<page\s+width="(?P<w>[0-9.]+)"\s+height="(?P<h>[0-9.]+)">(?P<body>.*?)</page>',
        re.S,
    )
    word_re = re.compile(
        r'<word\s+xMin="(?P<x0>[0-9.]+)"\s+yMin="[0-9.]+"\s+'
        r'xMax="(?P<x1>[0-9.]+)"\s+yMax="(?P<y1>[0-9.]+)">(?P<t>.*?)</word>',
        re.S,
    )
    for page_no, pm in enumerate(page_re.finditer(data), 1):
        width = float(pm.group("w"))
        height = float(pm.group("h"))
        safe_left, safe_right = 55.0, width - 55.0
        safe_bottom = height - 95.0
        for wm in word_re.finditer(pm.group("body")):
            text = re.sub(r"<[^>]+>", "", wm.group("t")).strip()
            x0 = float(wm.group("x0"))
            x1 = float(wm.group("x1"))
            y1 = float(wm.group("y1"))
            is_folio = bool(re.fullmatch(r"\d+", text)) and abs((x0 + x1) / 2 - width / 2) < 20 and y1 > safe_bottom
            if is_folio:
                continue
            if x0 < safe_left - 1 or x1 > safe_right + 1 or y1 > safe_bottom:
                errors.append(
                    f"{pdf.name}: page {page_no}: word {text!r} outside safe bounds "
                    f"(x={x0:.1f}..{x1:.1f}, yMax={y1:.1f}; page={width:.1f}x{height:.1f})"
                )
    return errors


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: check-pdf-bounds.py FILE.pdf [...]", file=sys.stderr)
        return 2
    errors: list[str] = []
    for arg in sys.argv[1:]:
        errors.extend(check(Path(arg)))
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"PDF bounds check passed for {len(sys.argv)-1} file(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
