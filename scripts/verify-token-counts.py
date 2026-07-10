#!/usr/bin/env python3
import re, subprocess, sys
from pathlib import Path

if len(sys.argv) < 3:
    raise SystemExit('usage: verify-token-counts.py PDF TOKEN ...')
pdf = Path(sys.argv[1])
text = subprocess.check_output(['pdftotext', str(pdf), '-'], text=True)
failed = False
for token in sys.argv[2:]:
    count = len(re.findall(re.escape(token), text))
    print(f'{token}: {count}')
    if count != 1:
        failed = True
if failed:
    raise SystemExit('token accounting failed: every token must occur exactly once')
