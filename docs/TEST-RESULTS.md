# Test results — v0.4 Option A

Run `make test` (or `./scripts/run-tests.sh`) to reproduce the checks.

The suite verifies:

1. Normal column-1 insertion.
2. Deterministic column-2 deferral.
3. Exactly-once PDF-text occurrence of unique tokens around a deferred band.
4. Hyperref/equation reference compilation.
5. Explicit errors for a second pending band and an oversized band.
6. Pixel-identical output when the package is loaded but unused.
7. PDF page-bound checks and absence of overfull vertical boxes in core tests.
8. No synthetic `lipsum` content in regression sources.

Unsupported combinations such as arbitrary floats and tagged PDF remain warnings rather than compatibility claims.
