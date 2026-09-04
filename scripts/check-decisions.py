#!/usr/bin/env python3
"""Check a wideband test document's declared expectations against its .log.

Expectation comments live in the first 40 lines of the .tex file
(implementation contract section 6.1):

    %% WB-EXPECT: requests=<n> placed=<n> deferred=<n> [errors=<n>]
    %% WB-EXPECT-DECISION: id=<n> result=<placed|deferred|error> [col=<c>] [code=<Dx>] [page=<p>]
    %% WB-EXPECT-LOG: <Python regex that must match at least one log line>
    %% WB-EXPECT-NOLOG: <Python regex that must match no log line>
    %% WB-EXPECT-TOKENS: TOKEN-A TOKEN-B ...
    %% WB-EXPECT-COMPILE: pass|fail
    %% WB-ALLOW-OVERFULL
    %% WB-BASELINE-DIFFERS

Decision lines in the log have the exact format of contract section 4.2:

    WIDEBAND DECISION: id=<n> page=<p> col=<0|1|2> stratum=<k> h=<dim> S=<dim> R=<dim>
      B=<dim> P=<dim> ymin=<dim> ymax=<dim> y=<dim|-> result=<...> code=<...> note=<token>

Exit codes
    0  every checked expectation holds
    1  at least one expectation or spec invariant failed
    2  usage / unreadable input
    3  the document declares decision expectations but the log has no
       decision lines at all (the baseline package writes none)

The spec invariants checked on every decision line come from report sections
1, 2.2 and 2.3 and are independent of the document: ymax = S - R - B,
ymin >= P/2, ymin <= y <= ymax for a same-page placement, P = h in column 1,
y = "-" unless the band was placed, and at most one placement per band id.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

EXPECT_SCAN_LINES = 40
DIM_TOL = 0.05  # pt; absorbs grid rounding of y and B (report 2.6)

DECISION_KEYS = [
    "id", "page", "col", "stratum", "h", "S", "R", "B", "P",
    "ymin", "ymax", "y", "result", "code", "note",
]
INT_KEYS = {"id", "page", "col", "stratum"}
DIM_KEYS = {"h", "S", "R", "B", "P", "ymin", "ymax", "y"}
RESULTS = {"placed", "deferred", "error"}
CODES = {"OK", "D1", "D2", "D3", "D4", "D5"}
NOTES = {
    "col1-at-h", "col1-recut", "col2-recut", "stacked", "top-of-page",
    "no-room", "unbreakable-range", "footnotes-in-moved-material",
    "marginpar-in-moved-material", "holdover-footnote", "enlargethispage",
    "nested", "recut-disabled", "oversized", "kernel-mismatch",
    # phase-1 extensions to the contract 4.2 vocabulary, documented in
    # README.md (decision-log): re-cut refusals and the output-cycle guard
    "float-in-moved-material", "no-raw-column", "cycle-limit",
}
NOTE_PREFIXES = ("pkg-conflict-",)

DIM_RE = re.compile(r"^-?\d+(?:\.\d+)?pt$")
KV_RE = re.compile(r"(\w+)=(\S*)")
DECISION_RE = re.compile(r"WIDEBAND DECISION:\s*(.*)$")
PAGE_RE = re.compile(r"WIDEBAND PAGE:\s*(.*)$")
GATE_RE = re.compile(r"WIDEBAND GATE:\s*(.*)$")

# A LOG/NOLOG pattern that talks about the decision log cannot hold for the
# baseline package, which writes no decision lines at all.
DECISION_DERIVED_RE = re.compile(r"WIDEBAND|code=|stratum=|ymin=|ymax=")


# ---------------------------------------------------------------- expectations
class Expectations:
    def __init__(self) -> None:
        self.counts: dict[str, int] = {}
        self.decisions: list[dict[str, str]] = []
        self.log: list[str] = []
        self.nolog: list[str] = []
        self.tokens: list[str] = []
        self.compile: str = "pass"
        self.allow_overfull = False
        self.baseline_differs = False
        self.raw: list[str] = []

    @property
    def has_decision_expectations(self) -> bool:
        return bool(self.counts) or bool(self.decisions)


def parse_expectations(path: Path) -> tuple[Expectations, list[str]]:
    """Return (expectations, list of parse errors)."""
    exp = Expectations()
    errors: list[str] = []
    try:
        text = path.read_text(errors="replace")
    except OSError as exc:  # pragma: no cover - reported by caller
        raise SystemExit(f"check-decisions: cannot read {path}: {exc}")

    for lineno, line in enumerate(text.splitlines()[:EXPECT_SCAN_LINES], 1):
        stripped = line.strip()
        if not stripped.startswith("%"):
            continue
        body = stripped.lstrip("%").strip()
        if not body.startswith("WB-"):
            continue
        exp.raw.append(body)
        tag, _, rest = body.partition(":")
        tag = tag.strip()
        rest = rest.strip()
        if tag == "WB-EXPECT":
            for key, value in KV_RE.findall(rest):
                if key not in ("requests", "placed", "deferred", "errors"):
                    errors.append(f"line {lineno}: unknown WB-EXPECT key {key!r}")
                    continue
                try:
                    exp.counts[key] = int(value)
                except ValueError:
                    errors.append(f"line {lineno}: WB-EXPECT {key}={value!r} is not an integer")
        elif tag == "WB-EXPECT-DECISION":
            want = dict(KV_RE.findall(rest))
            bad = set(want) - {"id", "result", "col", "code", "page", "note"}
            if bad:
                errors.append(f"line {lineno}: unknown WB-EXPECT-DECISION key(s) {sorted(bad)}")
            if "id" not in want:
                errors.append(f"line {lineno}: WB-EXPECT-DECISION needs id=<n>")
            if "result" not in want:
                errors.append(f"line {lineno}: WB-EXPECT-DECISION needs result=<...>")
            elif want["result"] not in RESULTS:
                errors.append(f"line {lineno}: WB-EXPECT-DECISION result={want['result']!r} unknown")
            exp.decisions.append(want)
        elif tag == "WB-EXPECT-LOG":
            exp.log.append(rest)
        elif tag == "WB-EXPECT-NOLOG":
            exp.nolog.append(rest)
        elif tag == "WB-EXPECT-TOKENS":
            exp.tokens.extend(rest.split())
        elif tag == "WB-EXPECT-COMPILE":
            if rest not in ("pass", "fail"):
                errors.append(f"line {lineno}: WB-EXPECT-COMPILE must be pass or fail, got {rest!r}")
            else:
                exp.compile = rest
        elif tag in ("WB-ALLOW-OVERFULL", "WB-ALLOW-OVERFULL:"):
            exp.allow_overfull = True
        elif tag in ("WB-BASELINE-DIFFERS", "WB-BASELINE-DIFFERS:"):
            exp.baseline_differs = True
        elif tag == "WB-KNOWN-XFAIL":
            # A note read by run-matrix.sh to record a documented out-of-scope
            # limitation as XFAIL; carries a free-text reason, nothing to check.
            pass
        else:
            errors.append(f"line {lineno}: unknown expectation tag {tag!r}")

    for pattern in exp.log + exp.nolog:
        try:
            re.compile(pattern)
        except re.error as exc:
            errors.append(f"bad regex {pattern!r}: {exc}")

    dup = [t for t in set(exp.tokens) if exp.tokens.count(t) > 1]
    if dup:
        errors.append(f"WB-EXPECT-TOKENS lists {sorted(dup)} more than once")
    # verify-token-counts.py counts substrings, so one token must never be a
    # substring of another or both counts are wrong.
    for a in exp.tokens:
        for b in exp.tokens:
            if a != b and a in b:
                errors.append(f"token {a!r} is a substring of token {b!r}")
    return exp, errors


# ------------------------------------------------------------------- log input
def unwrap(lines: list[str], width: int) -> list[str]:
    """Undo TeX's max_print_line wrapping.

    TeX breaks log output at max_print_line characters with no continuation
    marker, so a wrap fragment is a line sitting exactly on the boundary
    (LuaTeX emits width or width+1 characters).  A longer line was never
    wrapped and is left alone.  The runners pass --wrap-width 1000 together
    with max_print_line=1000, so this is a safety net for logs produced
    elsewhere.
    """
    def is_fragment(line: str) -> bool:
        return width <= len(line) <= width + 1

    out: list[str] = []
    buf: str | None = None
    for line in lines:
        buf = line if buf is None else buf + line
        if not is_fragment(line):
            out.append(buf)
            buf = None
    if buf is not None:
        out.append(buf)
    return out


class Log:
    def __init__(self, path: Path, wrap_width: int) -> None:
        self.path = path
        self.raw = path.read_text(errors="replace").splitlines()
        self.lines = unwrap(self.raw, wrap_width)
        self.decisions: list[dict[str, str]] = []
        self.decision_lines: list[str] = []
        self.pages: list[dict[str, str]] = []
        self.gates: list[dict[str, str]] = []
        self.format_errors: list[str] = []
        self.format_warnings: list[str] = []
        self._scan()

    def _scan(self) -> None:
        for line in self.lines:
            m = DECISION_RE.search(line)
            if m:
                self.decision_lines.append(line)
                self.decisions.append(self._parse_decision(m.group(1)))
                continue
            m = PAGE_RE.search(line)
            if m:
                self.pages.append(dict(KV_RE.findall(m.group(1))))
                continue
            m = GATE_RE.search(line)
            if m:
                self.gates.append(dict(KV_RE.findall(m.group(1))))

    def _parse_decision(self, body: str) -> dict[str, str]:
        pairs = KV_RE.findall(body)
        rec = dict(pairs)
        order = [k for k, _ in pairs]
        missing = [k for k in DECISION_KEYS if k not in rec]
        if missing:
            self.format_errors.append(
                f"decision line misses key(s) {missing}: {body!r}")
        extra = [k for k in rec if k not in DECISION_KEYS]
        if extra:
            self.format_errors.append(
                f"decision line has unexpected key(s) {sorted(extra)}: {body!r}")
        if not missing and not extra and order != DECISION_KEYS:
            self.format_warnings.append(
                f"decision line key order is {order}, contract 4.2 order is {DECISION_KEYS}")
        for key in INT_KEYS:
            if key in rec and not re.fullmatch(r"\d+", rec[key]):
                self.format_errors.append(f"{key}={rec[key]!r} is not a non-negative integer")
        for key in DIM_KEYS:
            if key not in rec:
                continue
            value = rec[key]
            if value == "-":
                continue
            if not DIM_RE.match(value):
                self.format_errors.append(
                    f"{key}={value!r} is not a TeX dimension such as 123.4567pt")
        if "result" in rec and rec["result"] not in RESULTS:
            self.format_errors.append(f"result={rec['result']!r} is not one of {sorted(RESULTS)}")
        if "code" in rec and rec["code"] not in CODES:
            self.format_errors.append(f"code={rec['code']!r} is not one of {sorted(CODES)}")
        if "note" in rec:
            note = rec["note"]
            known = note in NOTES or any(note.startswith(p) for p in NOTE_PREFIXES)
            if not known:
                self.format_warnings.append(
                    f"note={note!r} is outside the contract 4.2 vocabulary "
                    "(extensions must be documented in README.md)")
        return rec


def dim(rec: dict[str, str], key: str) -> float | None:
    value = rec.get(key)
    if value is None or value == "-" or not DIM_RE.match(value):
        return None
    return float(value[:-2])


# ------------------------------------------------------------------ the checks
class Report:
    def __init__(self) -> None:
        self.failures: list[str] = []
        self.warnings: list[str] = []
        self.skips: list[str] = []
        self.notes: list[str] = []
        self.no_decisions = False

    def fail(self, label: str, message: str) -> None:
        self.failures.append(f"[{label}] {message}")

    def warn(self, message: str) -> None:
        self.warnings.append(message)

    def skip(self, message: str) -> None:
        self.skips.append(message)


def check_invariants(log: Log, rep: Report) -> None:
    placed_per_id: dict[str, int] = {}
    seen_order: dict[str, list[str]] = {}
    for rec in log.decisions:
        bid = rec.get("id", "?")
        result = rec.get("result")
        seen_order.setdefault(bid, []).append(result or "?")
        if result == "placed":
            placed_per_id[bid] = placed_per_id.get(bid, 0) + 1
        col = rec.get("col")
        S, R, B, P = (dim(rec, k) for k in ("S", "R", "B", "P"))
        h, ymin, ymax, y = (dim(rec, k) for k in ("h", "ymin", "ymax", "y"))

        if result == "placed" and rec.get("y") == "-":
            rep.fail("invariant", f"id={bid}: result=placed but y=- (contract 4.2)")
        if result in ("deferred", "error") and rec.get("y") != "-":
            rep.fail("invariant",
                     f"id={bid}: result={result} but y={rec.get('y')} (must be - when not placed)")
        if None not in (S, R, B, ymax) and abs(ymax - (S - R - B)) > DIM_TOL:  # type: ignore[operator]
            rep.fail("invariant",
                     f"id={bid}: ymax={ymax} but S-R-B={S - R - B:.4f} (report 2.3)")  # type: ignore[operator]
        if col in ("1", "2") and None not in (P, ymin) and ymin < P / 2 - DIM_TOL:  # type: ignore[operator]
            rep.fail("invariant",
                     f"id={bid}: ymin={ymin} < P/2={P / 2:.4f} (report 2.1/2.2 reading order)")  # type: ignore[operator]
        if col == "1" and None not in (P, h) and abs(P - h) > DIM_TOL:  # type: ignore[operator]
            rep.fail("invariant", f"id={bid}: col=1 requires P=h, got P={P} h={h} (report 1)")
        if col == "2" and None not in (P, S, h) and abs(P - (S + h)) > DIM_TOL:  # type: ignore[operator]
            rep.warn(f"id={bid}: col=2 has P={P}, expected S+h={S + h:.4f} "  # type: ignore[operator]
                     "(only exact when the column-1 piece was set to full height)")
        if result == "placed" and col in ("1", "2") and None not in (ymin, ymax, y):
            if y < ymin - DIM_TOL or y > ymax + DIM_TOL:  # type: ignore[operator]
                rep.fail("invariant",
                         f"id={bid}: y={y} outside the feasible interval [{ymin}, {ymax}] (report 2.3)")
        if col == "0" and y is not None and abs(y) > DIM_TOL:
            rep.fail("invariant", f"id={bid}: col=0 must place at y=0, got y={y} (contract 4.2)")
        if result == "placed" and rec.get("code") not in (None, "OK"):
            rep.warn(f"id={bid}: result=placed with code={rec.get('code')}")
        if result == "deferred" and rec.get("code") == "OK":
            rep.warn(f"id={bid}: result=deferred with code=OK")

    for bid, count in sorted(placed_per_id.items()):
        if count > 1:
            rep.fail("invariant",
                     f"id={bid}: {count} lines with result=placed; a band ships at most once")
    for bid, results in sorted(seen_order.items()):
        if len(results) > 2:
            rep.warn(f"id={bid}: {len(results)} decision lines ({results}); "
                     "contract 4.2 expects at most one deferral plus one placement")
        if len(results) == 2 and results != ["deferred", "placed"]:
            rep.warn(f"id={bid}: decision lines are {results}; "
                     "contract 4.2 expects deferred then placed")

    for rec in log.pages:
        ids = [i for i in rec.get("bands", "").split(",") if i]
        for bid in ids:
            if bid not in seen_order:
                rep.fail("invariant",
                         f"WIDEBAND PAGE page={rec.get('page')} lists band {bid} "
                         "but no decision line mentions it")
    for rec in log.gates:
        status = rec.get("status")
        if status not in ("active", "disabled"):
            rep.fail("format", f"WIDEBAND GATE status={status!r} is not active or disabled")
    if len(log.gates) > 1:
        rep.warn(f"{len(log.gates)} WIDEBAND GATE lines; contract 4.2 expects one")


def check_counts(exp: Expectations, log: Log, rep: Report) -> None:
    actual = {
        "requests": len({r.get("id") for r in log.decisions}),
        "placed": sum(1 for r in log.decisions if r.get("result") == "placed"),
        "deferred": sum(1 for r in log.decisions if r.get("result") == "deferred"),
        "errors": sum(1 for r in log.decisions if r.get("result") == "error"),
    }
    for key, want in sorted(exp.counts.items()):
        if actual[key] != want:
            rep.fail("counts", f"expected {key}={want}, log has {key}={actual[key]}")


def check_decision_expectations(exp: Expectations, log: Log, rep: Report) -> None:
    for want in exp.decisions:
        bid = want.get("id")
        candidates = [r for r in log.decisions if r.get("id") == bid]
        if not candidates:
            rep.fail("decision", f"no decision line for id={bid}")
            continue
        fields = {k: v for k, v in want.items() if k != "id"}
        for rec in candidates:
            if all(rec.get(k) == v for k, v in fields.items()):
                break
        else:
            shown = " ".join(f"{k}={v}" for k, v in sorted(fields.items()))
            got = "; ".join(
                " ".join(f"{k}={r.get(k)}" for k in ("result", "col", "code", "page", "note"))
                for r in candidates)
            rep.fail("decision", f"id={bid}: no line matching [{shown}]; log has [{got}]")


def check_patterns(exp: Expectations, log: Log, rep: Report, baseline: bool) -> None:
    haystack = log.lines
    for pattern in exp.log:
        if baseline and DECISION_DERIVED_RE.search(pattern):
            rep.skip(f"WB-EXPECT-LOG {pattern!r} (decision log; baseline package writes none)")
            continue
        rx = re.compile(pattern)
        if any(rx.search(line) for line in haystack) or any(rx.search(line) for line in log.raw):
            continue
        rep.fail("log", f"WB-EXPECT-LOG {pattern!r} matched no line of {log.path.name}")
    for pattern in exp.nolog:
        if baseline and DECISION_DERIVED_RE.search(pattern):
            rep.skip(f"WB-EXPECT-NOLOG {pattern!r} (decision log; baseline package writes none)")
            continue
        rx = re.compile(pattern)
        hits = [l for l in haystack if rx.search(l)]
        if hits:
            rep.fail("log", f"WB-EXPECT-NOLOG {pattern!r} matched: {hits[0][:160]!r}")


def run_checks(tex: Path, logfile: Path, package_mode: str, strict_format: bool,
               compile_status: str | None, wrap_width: int) -> tuple[Report, Expectations]:
    rep = Report()
    exp, parse_errors = parse_expectations(tex)
    for message in parse_errors:
        rep.fail("expect-syntax", message)

    log = Log(logfile, wrap_width)
    for message in log.format_errors:
        rep.fail("format", message)
    for message in log.format_warnings:
        if strict_format:
            rep.fail("format", message)
        else:
            rep.warn(message)

    baseline = package_mode == "baseline"
    check_invariants(log, rep)
    check_patterns(exp, log, rep, baseline)

    if compile_status == "fail":
        rep.skip("decision counts and per-band expectations "
                 "(WB-EXPECT-COMPILE: fail, no complete run)")
    elif baseline and exp.has_decision_expectations:
        rep.skip("decision counts and per-band expectations "
                 "(--package-mode baseline: the baseline package writes no decision log)")
    elif exp.has_decision_expectations and not log.decisions:
        rep.no_decisions = True
    else:
        check_counts(exp, log, rep)
        check_decision_expectations(exp, log, rep)

    rep.notes.append(
        f"{len(log.decisions)} decision line(s), {len(log.pages)} page line(s), "
        f"{len(log.gates)} gate line(s)")
    return rep, exp


# ------------------------------------------------------------------------ meta
def print_meta(exp: Expectations) -> None:
    print(f"compile={exp.compile}")
    print(f"allow_overfull={1 if exp.allow_overfull else 0}")
    print(f"baseline_differs={1 if exp.baseline_differs else 0}")
    print(f"has_decision_expectations={1 if exp.has_decision_expectations else 0}")
    print(f"n_tokens={len(exp.tokens)}")
    print(f"tokens={' '.join(exp.tokens)}")


# -------------------------------------------------------------------- selftest
SELFTEST_DECISION = (
    "WIDEBAND DECISION: id=1 page=2 col=2 stratum=1 h=200.0pt S=600.0pt R=0.0pt "
    "B=90.0pt P=800.0pt ymin=400.0pt ymax=510.0pt y=400.0pt result=placed code=OK "
    "note=col2-recut")


def selftest() -> int:
    import tempfile

    failures: list[str] = []
    ran = [0]

    def case(name: str, tex_body: str, log_body: str, want_exit: int,
             package_mode: str = "stratum", compile_status: str | None = None,
             want_in: str | None = None) -> None:
        ran[0] += 1
        with tempfile.TemporaryDirectory() as td:
            tex = Path(td) / "t.tex"
            logf = Path(td) / "t.log"
            tex.write_text(tex_body)
            logf.write_text(log_body)
            rep, _ = run_checks(tex, logf, package_mode, False, compile_status, 79)
            got = 3 if rep.no_decisions and not rep.failures else (1 if rep.failures else 0)
            text = "\n".join(rep.failures + rep.warnings + rep.skips)
            if got != want_exit:
                failures.append(f"{name}: exit {got}, wanted {want_exit}\n    {text}")
            elif want_in is not None and want_in not in text:
                failures.append(f"{name}: {want_in!r} not in\n    {text}")

    case("clean", "%% WB-EXPECT: requests=1 placed=1 deferred=0\n",
         SELFTEST_DECISION + "\n", 0)

    case("count-mismatch", "%% WB-EXPECT: requests=1 placed=0 deferred=1\n",
         SELFTEST_DECISION + "\n", 1, want_in="expected placed=0")

    case("no-decision-lines", "%% WB-EXPECT: requests=1 placed=1 deferred=0\n",
         "This is a plain log.\n", 3)

    case("no-expectations-no-lines", "% nothing declared here\n",
         "This is a plain log.\n", 0)

    case("baseline-mode-skips",
         "%% WB-EXPECT: requests=1 placed=1 deferred=0\n"
         "%% WB-EXPECT-LOG: WIDEBAND DECISION: id=1 .*code=D1\n",
         "This is a plain log.\n", 0, package_mode="baseline",
         want_in="baseline package writes none")

    case("per-band-expectation",
         "%% WB-EXPECT-DECISION: id=1 result=placed col=2 code=OK\n",
         SELFTEST_DECISION + "\n", 0)

    case("per-band-mismatch",
         "%% WB-EXPECT-DECISION: id=1 result=deferred code=D1\n",
         SELFTEST_DECISION + "\n", 1, want_in="no line matching")

    case("per-band-missing",
         "%% WB-EXPECT-DECISION: id=2 result=placed\n",
         SELFTEST_DECISION + "\n", 1, want_in="no decision line for id=2")

    case("invariant-ymax",
         "%% WB-EXPECT: requests=1\n",
         SELFTEST_DECISION.replace("ymax=510.0pt", "ymax=520.0pt") + "\n", 1,
         want_in="S-R-B")

    case("invariant-ymin-reading-order",
         "%% WB-EXPECT: requests=1\n",
         SELFTEST_DECISION.replace("ymin=400.0pt", "ymin=300.0pt")
         .replace("y=400.0pt", "y=310.0pt") + "\n", 1, want_in="P/2")

    case("invariant-y-outside-interval",
         "%% WB-EXPECT: requests=1\n",
         SELFTEST_DECISION.replace("y=400.0pt", "y=560.0pt") + "\n", 1,
         want_in="outside the feasible interval")

    case("invariant-placed-without-y",
         "%% WB-EXPECT: requests=1\n",
         SELFTEST_DECISION.replace("y=400.0pt", "y=-") + "\n", 1,
         want_in="result=placed but y=-")

    case("invariant-deferred-with-y",
         "%% WB-EXPECT: requests=1\n",
         SELFTEST_DECISION.replace("result=placed", "result=deferred")
         .replace("code=OK", "code=D1") + "\n", 1, want_in="must be - when not placed")

    case("invariant-double-placement",
         "%% WB-EXPECT: requests=1\n",
         SELFTEST_DECISION + "\n" + SELFTEST_DECISION.replace("page=2", "page=3") + "\n", 1,
         want_in="ships at most once")

    case("invariant-col1-P-equals-h",
         "%% WB-EXPECT: requests=1\n",
         SELFTEST_DECISION.replace("col=2", "col=1") + "\n", 1,
         want_in="col=1 requires P=h")

    case("format-missing-key",
         "%% WB-EXPECT: requests=1\n",
         "WIDEBAND DECISION: id=1 page=2 result=placed\n", 1, want_in="misses key")

    case("format-bad-dim",
         "%% WB-EXPECT: requests=1\n",
         SELFTEST_DECISION.replace("B=90.0pt", "B=90") + "\n", 1,
         want_in="not a TeX dimension")

    case("format-bad-code",
         "%% WB-EXPECT: requests=1\n",
         SELFTEST_DECISION.replace("code=OK", "code=D9") + "\n", 1, want_in="code='D9'")

    case("expect-log-hit",
         "%% WB-EXPECT-LOG: note=col2-recut\n", SELFTEST_DECISION + "\n", 0)

    case("expect-log-miss",
         "%% WB-EXPECT-LOG: Overfull .hbox\n", SELFTEST_DECISION + "\n", 1,
         want_in="matched no line")

    case("expect-nolog-hit",
         "%% WB-EXPECT-NOLOG: nesting level\n",
         "! pdfTeX warning: ended up in different nesting level\n", 1, want_in="matched")

    case("bad-token-substring",
         "%% WB-EXPECT-TOKENS: MX01A0 MX01A01\n", SELFTEST_DECISION + "\n", 1,
         want_in="substring")

    case("bad-compile-value",
         "%% WB-EXPECT-COMPILE: maybe\n", SELFTEST_DECISION + "\n", 1,
         want_in="must be pass or fail")

    case("compile-fail-skips-counts",
         "%% WB-EXPECT-COMPILE: fail\n%% WB-EXPECT: requests=1 placed=1\n",
         "! Package wideband Error: too tall\n", 0, compile_status="fail")

    case("gate-line-bad-status",
         "%% WB-EXPECT: requests=0\n",
         "WIDEBAND GATE: status=broken reason=ok\n", 1, want_in="not active or disabled")

    case("page-line-unknown-band",
         "%% WB-EXPECT: requests=1\n",
         SELFTEST_DECISION + "\nWIDEBAND PAGE: page=2 strata=2 bands=1,7 "
         "heights=400.0pt,90.0pt,110.0pt\n", 1, want_in="band 7")

    # unwrapping: a decision line split by max_print_line=79 must still parse
    wrapped = SELFTEST_DECISION
    chunks = [wrapped[i:i + 79] for i in range(0, len(wrapped), 79)]
    case("unwraps-tex-log-wrapping",
         "%% WB-EXPECT: requests=1 placed=1\n", "\n".join(chunks) + "\n", 0)

    # expectation comments must be found only in the first 40 lines
    case("expectations-only-in-header",
         "\n" * 45 + "%% WB-EXPECT: requests=9\n", SELFTEST_DECISION + "\n", 0)

    if failures:
        print("check-decisions selftest FAILED:")
        for f in failures:
            print("  - " + f)
        return 1
    print(f"check-decisions selftest passed ({ran[0]} cases).")
    return 0


# ------------------------------------------------------------------------ main
def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("texfile", nargs="?")
    ap.add_argument("logfile", nargs="?")
    ap.add_argument("--package-mode", choices=("baseline", "stratum"), default="stratum",
                    help="baseline: skip every decision-log derived expectation")
    ap.add_argument("--compile-status", choices=("pass", "fail"), default=None,
                    help="outcome of the compile the log came from")
    ap.add_argument("--strict-format", action="store_true",
                    help="treat decision-line key order and unknown notes as failures")
    ap.add_argument("--wrap-width", type=int, default=79,
                    help="TeX max_print_line used for the log (default 79)")
    ap.add_argument("--print-meta", action="store_true",
                    help="print the parsed expectation metadata as key=value lines and exit")
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args(argv)

    if args.selftest:
        return selftest()
    if not args.texfile:
        ap.error("texfile is required")
    tex = Path(args.texfile)
    if not tex.is_file():
        print(f"check-decisions: no such file: {tex}", file=sys.stderr)
        return 2
    if args.print_meta:
        exp, errors = parse_expectations(tex)
        print_meta(exp)
        for message in errors:
            print(f"# expect-syntax: {message}", file=sys.stderr)
        return 1 if errors else 0
    if not args.logfile:
        ap.error("logfile is required")
    logfile = Path(args.logfile)
    if not logfile.is_file():
        print(f"check-decisions: no such file: {logfile}", file=sys.stderr)
        return 2

    rep, _ = run_checks(tex, logfile, args.package_mode, args.strict_format,
                        args.compile_status, args.wrap_width)

    name = tex.name
    if not args.quiet:
        for message in rep.notes:
            print(f"  {name}: {message}")
        for message in rep.skips:
            print(f"  {name}: SKIP {message}")
        for message in rep.warnings:
            print(f"  {name}: WARN {message}")
    if rep.no_decisions and not rep.failures:
        print(f"{name}: no decision lines: baseline package? "
              f"(the document declares WB-EXPECT but {logfile.name} has no "
              f"'WIDEBAND DECISION:' line)", file=sys.stderr)
        return 3
    if rep.failures:
        print(f"{name}: {len(rep.failures)} expectation failure(s)", file=sys.stderr)
        for message in rep.failures:
            print(f"  {message}", file=sys.stderr)
        return 1
    if not args.quiet:
        print(f"  {name}: expectations satisfied")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
