# CORPUS workstream status

Branch `worktree-agent-a6f87344366c50f36`, worktree
`/data/personal-projects/latex-wide-band/.claude/worktrees/agent-a6f87344366c50f36`.
Never pushed; `master` untouched.

## Done

Commits (on top of `67756d5`):

- `60b7da7` CORPUS: scenario matrix, synthetic generator and runners
- `4a89cd5` CORPUS: recalibrate generated band heights, add the stratum dry-run
- this commit: header-failure gating, committed measurement probes, doc fixes

Everything contract section 6 asks of CORPUS exists and runs:

| File | State |
|---|---|
| `scripts/check-decisions.py` | complete; 28 self-tests (`--selftest`), exit 0/1/2/3, `--print-meta`, `--package-mode`, `--strict-format`, log un-wrapping |
| `scripts/run-matrix.sh` | complete; `--only`, `--keep-going`, `--strict`, `--source-dir`, `--package-mode`, positional/`WB_BUILD_DIR` build dir, summary table, baseline/stratum detection |
| `scripts/gen-corpus.py` | complete; `--seed`, `--count`, `--out`, `--load-style`, `--list`; deterministic |
| `scripts/run-corpus.sh` | complete; generates then delegates to `run-matrix.sh` |
| `tests/matrix/*.tex` | 35 scenarios, m01..m35 |
| `tests/matrix/matrix-content.tex` | shared prose and layout helpers |
| `tests/matrix/stratum-dryrun.py` | 34 scenario headers checked against synthesised spec-conforming logs |
| `tests/matrix/probes/measure.py` | reproduces every measurement the derivations rest on |
| `tests/matrix/probes/verify-h.py` | predicted `h` vs the marker position the package reports |
| `docs/CORPUS.md` | parameters, derivations, how to add a scenario, how to run |

Verified in this worktree, against the **baseline** package:

```
make test                                        -> green (unchanged)
./scripts/run-matrix.sh --keep-going             -> exit 0; pass=14 fail=0 xfail=10 xpass=11
./scripts/run-corpus.sh --seed 1 --count 30 ...  -> exit 0; pass=11 fail=0 xfail=15 xpass=4
./scripts/check-decisions.py --selftest          -> 28 cases pass
python3 tests/matrix/stratum-dryrun.py           -> 34/34 headers satisfiable
./tests/matrix/probes/verify-h.py                -> worst deviation 5.06pt (< half a line)
```

## In progress

Nothing. The last edit (`docs/CORPUS.md`, the "Two checks that the derivations are right"
section) is finished and the full verification above was re-run after it.

## Next steps (ordered)

1. When CORE lands, run `./scripts/run-matrix.sh --keep-going` (it will auto-detect
   stratum mode) and triage. `tests/matrix/stratum-dryrun.py` already proves a conforming
   log passes every header, so a failure there is CORE's behaviour, not the checker.
2. When AUDIT lands, the `AUDIT` column stops saying `skip` on its own; no change needed.
3. Regenerate the corpus with `--load-style option` once CORE parses `\usepackage[audit]{wideband}`,
   to exercise the documented contract form.
4. Larger corpus sweeps: `./scripts/run-corpus.sh --seed 1 --count 200 --keep-going`
   (contract section 8, integration). Seed 2 count 60 already found one baseline defect
   (see Known issues).
5. Optionally wire `run-matrix.sh` into the `Makefile` — deliberately not done, the
   `Makefile` is in nobody's ownership table.

## Known issues

Baseline defects the corpus found (spec-vs-baseline, **not** tooling failures):

- the reservation kern is discarded when the marker lands at the top of a column
  (`wideband.lua` writes a plain kern, which TeX discards on an empty page) - m02, m08;
- a deferred band is dropped when no page follows it - m14;
- the band is dropped with `\enlargethispage` (m28) and inside a `minipage` (m27);
- a footnote inside the band box is trapped there (m31);
- `--seed 2 --count 60`, document 52: `Overfull \vbox (29.28pt too high) ... while
  \output is active` with `figure*[t]` + `[t]`/`[h]` floats + a 510pt band under
  `\flushbottom`. Reported as a hard FAIL, correctly: it is a real layout defect.

Contract points not honoured, with reasons:

- generated documents use `\usepackage{wideband}` +
  `\IfFileExists{wideband-audit.sty}{\usepackage{wideband-audit}}{}` (the other form
  contract 6.2 allows) instead of `\usepackage[audit]{wideband}`, because the baseline
  package declares no options and aborts with `Unknown option`. `--load-style option`
  emits the literal form.
- `check-audit.py` is skipped with a message (AUDIT not merged).
- no self-tests added to `verify-token-counts.py` / `check-pdf-bounds.py`: shared, read-only.
- `m06` (report 2.8 row 6) is a genuine boundary case: a stricter reading of the two-line
  minimum piece rule gives D1 instead of "placed at y_max". The expectation follows the
  report.

## How to run / verify

```bash
cd /data/personal-projects/latex-wide-band/.claude/worktrees/agent-a6f87344366c50f36
make test
./scripts/check-decisions.py --selftest
python3 tests/matrix/stratum-dryrun.py
./scripts/run-matrix.sh --keep-going
./scripts/run-corpus.sh --seed 1 --count 30 --keep-going
./tests/matrix/probes/measure.py            # reproduce the derivation inputs
./tests/matrix/probes/verify-h.py           # after a matrix run
```

Requires LuaLaTeX (TeX Live 2025), Poppler (`pdftotext`), Python 3. Builds land in
`build/matrix`, `build/corpus`, `build/probe-measure`; all gitignored.
`docs/CORPUS.md` is the full reference.
