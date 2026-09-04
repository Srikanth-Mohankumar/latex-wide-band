#!/usr/bin/env python3
"""Turn the WBAUDIT records in a LuaLaTeX transcript into an exit status.

Usage:
    scripts/check-audit.py <logfile> [--json <file>]

Exit status
    0  a summary was found and reports fails=0
    1  the summary is missing, or fails is non-zero, or the log is unreadable

The log format is contract section 5.3:

    WBAUDIT: <check> ok|FAIL|skipped <details>
    WBAUDIT SUMMARY: pages=<n> lines=<n> bands=<n> footnotes=<n> fails=<n>

TeX may append its own output to the line that carries a record (the
transcript is a single stream), so records are matched at the start of a line
and trailing text is ignored.  A run that ships a page after \\end{document}
writes a second summary; the last one wins.
"""

import argparse
import json
import re
import sys

RECORD = re.compile(r"^WBAUDIT: (\S+) (ok|FAIL|skipped)\b[ ]?(.*)$")
SUMMARY = re.compile(
    r"^WBAUDIT SUMMARY: pages=(\d+) lines=(\d+) bands=(\d+)"
    r" footnotes=(\d+) fails=(\d+)")
ERROR = re.compile(r"^WBAUDIT ERROR (.*)$")

# every check the package is required to report at least once
EXPECTED = (
    "ledger-unique", "ledger-order", "band-order",
    "footnote-place", "geometry-textarea", "geometry-band-width",
)


def parse(path):
    report = {
        "log": str(path),
        "summary": None,
        "records": [],
        "failures": [],
        "skipped": [],
        "errors": [],
        "missing_checks": [],
    }
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        for lineno, line in enumerate(handle, 1):
            line = line.rstrip("\n")
            match = SUMMARY.match(line)
            if match:
                report["summary"] = {
                    "pages": int(match.group(1)),
                    "lines": int(match.group(2)),
                    "bands": int(match.group(3)),
                    "footnotes": int(match.group(4)),
                    "fails": int(match.group(5)),
                }
                continue
            match = ERROR.match(line)
            if match:
                report["errors"].append({"line": lineno, "text": line})
                continue
            match = RECORD.match(line)
            if not match:
                continue
            record = {
                "line": lineno,
                "check": match.group(1),
                "result": match.group(2),
                "details": match.group(3).strip(),
                "text": line,
            }
            report["records"].append(record)
            if record["result"] == "FAIL":
                report["failures"].append(record)
            elif record["result"] == "skipped":
                report["skipped"].append(record)

    seen = {r["check"] for r in report["records"]}
    report["missing_checks"] = [c for c in EXPECTED if c not in seen]
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="check the wideband-audit records in a LuaLaTeX log")
    parser.add_argument("logfile")
    parser.add_argument("--json", dest="jsonfile",
                        help="write the parsed report to this file")
    args = parser.parse_args(argv)

    try:
        report = parse(args.logfile)
    except OSError as exc:
        print(f"check-audit: cannot read {args.logfile}: {exc}",
              file=sys.stderr)
        return 1

    status = 0
    summary = report["summary"]

    for record in report["errors"]:
        print(record["text"])
    for record in report["failures"]:
        print(record["text"])

    if summary is None:
        print(f"check-audit: no WBAUDIT SUMMARY in {args.logfile}"
              " (the run did not reach the end of the document, or"
              " wideband-audit was not loaded)", file=sys.stderr)
        status = 1
    else:
        if summary["fails"]:
            print("check-audit: {fails} failing check(s) over {pages} page(s),"
                  " {lines} line ids, {bands} band(s), {footnotes} footnote(s)"
                  .format(**summary), file=sys.stderr)
            status = 1
        else:
            print("check-audit: ok, {pages} page(s), {lines} line ids,"
                  " {bands} band(s), {footnotes} footnote(s), 0 fails"
                  .format(**summary))
        # a mismatch means the log was cut or the records were rewritten
        if len(report["failures"]) != summary["fails"]:
            print("check-audit: {} FAIL record(s) found but summary says {}"
                  .format(len(report["failures"]), summary["fails"]),
                  file=sys.stderr)
            status = 1

    if report["errors"]:
        status = 1
    if report["missing_checks"]:
        print("check-audit: checks never reported: "
              + " ".join(report["missing_checks"]), file=sys.stderr)
        status = 1
    for record in report["skipped"]:
        print("check-audit: skipped: " + record["text"], file=sys.stderr)

    report["status"] = status
    if args.jsonfile:
        with open(args.jsonfile, "w", encoding="utf-8") as handle:
            json.dump(report, handle, indent=1, sort_keys=True)
            handle.write("\n")
    return status


if __name__ == "__main__":
    sys.exit(main())
