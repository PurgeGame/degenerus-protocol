# Deferred Items — Phase 301

## Out-of-scope discoveries during plan 301-03 execution

### D-301-03-DEFER-01 — pre-existing untracked sandbox file in `test/fuzz/`

- **File:** `test/fuzz/_SandboxRngLockDeterminism.t.sol`
- **Mtime:** 2026-05-18 15:22:05 (pre-dates this contribution at 15:23:59)
- **Status:** untracked, not part of plan 301-03 scope; appears to be an in-flight sandbox/experiment from another session.
- **Action deferred to:** Phase 301 plan 06 (Wave 2 aggregator) — the aggregator should decide whether to fold this sandbox into the canonical `test/fuzz/RngLockDeterminism.t.sol` or delete it.
- **Verifier:** plan 301-03 produced ZERO contracts/ and ZERO test/ mutations from its own writes; the sandbox file is an upstream artifact.
