# Phase 117: Libraries - Discussion Log

**Phase:** 117-libraries
**Created:** 2026-03-25

---

## Decision Record

### D-01: Category D only (all pure/view)
**Rationale:** All five libraries contain exclusively internal pure/view functions with zero storage writes. No Category B/C functions exist. However, full Mad Genius treatment still applies because library bugs cascade into every caller across the protocol.

### D-02: Five-library single unit
**Rationale:** Libraries are small individually (24-307 lines each, ~500 lines total). Auditing as a single unit avoids overhead while capturing cross-library interactions (e.g., EntropyLib entropy flowing into JackpotBucketLib rotation).

### D-03: Stateless focus shift
**Rationale:** With zero storage writes, BAF-class cache-overwrite bugs cannot originate in libraries. The attack surface shifts to: correctness of pure computation, entropy/randomness bias, boundary conditions, and caller misuse patterns.

### D-04: Caller misuse as first-class finding
**Rationale:** A library function that returns correct values can still cause protocol bugs if callers make wrong assumptions. Example: entropyStep(0) returns 0, creating a fixed point -- any caller passing 0 gets stuck in a degenerate loop.

---

## Execution Notes

(Populated during execution)
