# Phase 474 — MANIFEST-REPOINT

**Milestone:** v74.0 — As-Built Milestone Audit + C4A Package
**Executed:** 2026-06-27 · **Commits:** `3827c570` (manifest+doc), `ddc99874` (agent count fixes)
**Gate:** none

Re-points the single machine-readable MAN-01 invariant manifest from the stale v73 tree to the
frozen v74 HEAD and augments it with the batch's new conservation/freeze surfaces.

## MAN-01 — re-pin + re-validate ✓
- `agent/manifest/invariants.json` `subject`: frozenTree `d6615306→280bdb19`, impl `64ec993e→3986926c`,
  closure `MILESTONE_V73_AT_HEAD_15650b6a → MILESTONE_V74_AT_HEAD_PENDING_478` (concrete sha at 478),
  verdict provisional ("0 findings (8-cluster as-built audit + cross-model pending)").
- All 28 existing entries re-validated: every cited getter exists by the same name (no renames); all raw
  slot reads confirmed against the 466 golden — **no top-level slot moved** (balancesPacked=7,
  prizePoolPendingPacked=11, _subOf=54, _sdgnrsBonusLevel=58/25, boxPlayers=59).
- Drifted file:line citations corrected across SOLV/REDEEM/FSM/TICKET/RNG/VRF/CURSE/DEG entries (the
  +1861/−1030 diff shifted line numbers; test-file `source:` citations did not drift).
- **Substantive:** REDEEM-05 — the sDGNRS per-period 50%-cap fields are no longer top-level slots 13/15;
  sDGNRS storage was restructured so `supplySnapshot`/`burned` pack into the per-day `DayPending` struct
  (`pendingByDay` slot 7, bits 64-127/128-191; cap at sDGNRS.sol:1064). onchainRead rewritten.

## MAN-02 — 6 new-surface invariants added (total 28→34) ✓
`SOLV-06-FOLD-CONSERVATION`, `SOLV-07-SDGNRS-BOX-ROUTING`, `SOLV-08-AFFILIATE-WINNERCREDIT-FLIP-ONLY`
(ledger); `VRF-03-DEADMAN-MONOTONIC-LATCH` (state); `ACCESS-01-GIFT-FUNDER-SOURCING`,
`RNG-03-QUEUE-WINDOW-NO-TERMINAL-JACKPOT` (behavioral/statistical). Each grounded in the 468/469/470/471
findings with HEAD-accurate file:line evidence; all entries well-formed.

## MAN-03 — doc regen + oracle parity ✓
- `agent/manifest/MAIN-INVARIANTS.md` regenerated in the identical style, all 34 entries + a new
  "Access control & gift sourcing" section.
- **Oracle parity (flagged):** `agent/src/oracle.js` runtime-asserts only a SUBSET (SOLV-01/02/05,
  REDEEM-01/03, COIN-01, VAULT-01, FSM-01/02/03, TICKET-01, RNG-01-window, DEG-01/03). **All 6 MAN-02
  entries are manifest/doc-only, NOT runtime-asserted** — wiring them into the runtime is a Phase 476
  soak decision (oracle.js runtime logic intentionally left untouched here).
- Follow-up: bumped the agent unit-test count assertion 28→34 (`agent/test/unit.test.js`) + the
  agent README pointer; `npm run agent:test` 8/8 green (`ddc99874`).

**Verdict:** MAN-01 re-pointed to the frozen subject, re-validated, and augmented; the manifest stays the
single source shared by the oracle + README. Carry to 476: decide whether to runtime-assert the 6 new
invariants in the soak.
