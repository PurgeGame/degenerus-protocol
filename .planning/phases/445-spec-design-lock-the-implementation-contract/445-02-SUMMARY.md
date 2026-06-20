---
phase: 445-spec-design-lock-the-implementation-contract
plan: 02
subsystem: v71.0-foilpack-spec
tags: [spec, design-lock, storage-layout, packed-slot, century-stamp, double-claim-marker]
requires:
  - 445-RESEARCH.md §D (storage layout, V3 PASS — the reconciled E.6 168-bit superset)
  - 445-CONTEXT.md (canonical refs + integration points)
  - DegenerusGameStorage.sol:1857-1876 (centuryBonusUsed level-stamp idiom — the template)
provides:
  - 445-SPEC-D-storage.md (locked foilRecord packed layout + folded cap flag + foilMatchClaimed marker + the two pinned layout decisions + the USER-sign-off flag)
affects:
  - 445-04 (SPEC consolidation consumes this section + must surface PIN 1's USER-sign-off flag)
  - 446 IMPL (declares foilRecord/foilMatchClaimed/masks/accessors from this section, no further layout decision)
  - 448 (SEC-04 layout-golden re-pass attests the no-slot-move claim)
tech-stack:
  added: []
  patterns:
    - century level-stamp idiom reused for foilRecord (embedded 24-bit raw-level stamp = per-level auto-reset + folded cap)
    - single packed uint256 slot per player (4x32-bit sigs + 16-bit multBps + 24-bit stamp = 168 bits)
    - sparse keccak(player,level,day,drawKind,ticketIndex) double-claim marker, CEI mark-before-payout
key-files:
  created:
    - .planning/phases/445-spec-design-lock-the-implementation-contract/445-SPEC-D-storage.md
  modified: []
decisions:
  - "E.6 168-bit superset adopted OVER the D.1 24-bit/no-multBps variant — frozen multBps REQUIRED in the record by RARE-03/MATCH-09"
  - "PIN 1 (LOCKED): single-slot mapping(address=>uint256) foilRecord; level=>player variant documented as the not-chosen alternative; USER-sign-off flag raised for the L+1-overwrite player-loss edge"
  - "PIN 2 (LOCKED): stamp at bits [144-167], payload at [0-143] (sig0..3 [0-127], multBps [128-143]); bit-224 centuryBonusUsed-mirror documented as the not-chosen alternative"
  - "Per-raw-level cap folded into the stamp (FOIL-01) — no separate slot; keyed on raw uint24 level (:236), never _activeTicketLevel()"
  - "foilMatchClaimed is the unified marker name (NOT foilClaimed); whalePassClaims already exists at :1122 (do not re-declare)"
metrics:
  duration: ~9m
  completed: 2026-06-20
  tasks: 2
  files: 1
  commits: 1
---

# Phase 445 Plan 02: SPEC Storage Layout (foilRecord + cap flag + foilMatchClaimed) Summary

Locked the storage half of the v71.0 Foil Pack design-lock SPEC — the single packed `foilRecord`
slot per player (4×32-bit sigs + 16-bit frozen `multBps` + 24-bit raw-level stamp = 168 bits), the
folded per-raw-level cap flag (no separate slot), and the sparse `foilMatchClaimed` double-claim
marker — all tail-appended after `DegenerusGameStorage.sol:2393` with no slot move, plus the two
pinned layout decisions and the USER-sign-off flag for the single-slot player-loss edge.

## Performance

- **Duration:** ~9 min
- **Started:** 2026-06-20T00:00:00Z (approx)
- **Completed:** 2026-06-20T00:09:31Z
- **Tasks:** 2
- **Files modified:** 1 (created)

## What was built

`.planning/phases/445-spec-design-lock-the-implementation-contract/445-SPEC-D-storage.md` (268 lines),
authored from the RESEARCH §D reconciled E.6 superset, grounded against the live contract anchors
(append point `:2393`, century idiom `:1857-1876`, `whalePassClaims` `:1122`, `uint24 level` `:236`).

### Task 1 — lock the layout (FOIL-01, MATCH-01/02/05, SEC-03/04)
- **`foilRecord` as ONE packed `mapping(address => uint256)`** appended after `:2393`, holding the
  reconciled **E.6 168-bit superset**: 4 × 32-bit packed `uint32` ticket signatures + a 16-bit frozen
  `multBps` + a 24-bit raw-level stamp = 168 bits ≤ 256, one SSTORE on buy / one SLOAD on claim. The
  E.6 form is adopted OVER the D.1 24-bit/no-`multBps` variant (the frozen `multBps` is REQUIRED in
  the record by RARE-03/MATCH-09).
- The five `_FOIL_*` private-constant masks/shifts (`_FOIL_SIG_MASK`, `_FOIL_MULT_SHIFT=128`,
  `_FOIL_MULT_MASK`, `_FOIL_STAMP_SHIFT=144`, `_FOIL_STAMP_MASK`) and the `_foilRecordFor(player, lvl)`
  accessor semantics (returns `(false, 0, [0,0,0,0])` when the stamp ≠ the queried raw level — the
  century auto-reset).
- The **folded per-raw-level cap** (FOIL-01) via the stamp:
  `_foilBoughtThisLevel(player, lvl) == ((foilRecord[player] >> _FOIL_STAMP_SHIFT) & _FOIL_STAMP_MASK) == lvl`
  — no separate cap slot; keyed on raw `uint24 level` (`:236`), never `_activeTicketLevel()`.
- The sparse **`mapping(bytes32 => bool) foilMatchClaimed`** double-claim marker with key
  `keccak256(abi.encode(player, uint256(level), uint256(day), uint256(drawKind), uint256(ticketIndex)))`
  — five distinct positional `abi.encode` fields (`drawKind ∈ {0=main,1=bonus}`,
  `ticketIndex ∈ {0..3}`), each tuple claimable at most once, mark-before-payout (CEI).
- MATCH-02 whole-level window (eligibility read from the stamp, not a live `level` compare), the
  MATCH-05 persist-per-level griefing-resistance (a record at L is overwritten ONLY by the SAME
  player's next buy, never by `advanceGame` or another player; a fast `level++` does not strand an
  unclaimed match), and the SEC-04 no-slot-move attestation (append-only at the tail, constants
  consume no slots, two new base mapping slots, all prior slot indices unchanged, storage only in
  `DegenerusGameStorage` — SEC-03). Noted `whalePassClaims` already exists at `:1122` (do NOT
  re-declare); used the unified `foilMatchClaimed` name (NOT `foilClaimed`).

### Task 2 — PIN the two genuine layout decisions + surface the player-loss edge
Appended a dedicated "Pinned Layout Decisions (LOCKED)" section in the SPEC-V61 "Locked Knobs" form
(LOCKED value + rationale + documented alternative + affected REQ-IDs):
- **PIN 1 — `foilRecord` level-keying.** LOCKED the single-slot `mapping(address => uint256)` form
  (the §5-compliant minimum). Stated the precise edge: a player's OWN re-buy at L+1 overwrites their
  unclaimed L signatures; a level advance ALONE never strands a match. Documented the
  `mapping(uint24 level => mapping(address => uint256))` alternative (additive widening, no reorder,
  +1 slot per level per buyer) that survives an L+1 re-buy. Added a **USER-SIGN-OFF FLAG** ("USER
  REVIEW BEFORE THE 446 IMPL GATE — … confirm acceptable, or switch to the level=>player variant").
  Cited FOIL-01/MATCH-01/MATCH-05.
- **PIN 2 — exact packed bit-offset.** LOCKED the **stamp at bits `[144-167]`, payload at `[0-143]`**
  (sig0..3 `[0-127]`, multBps `[128-143]`), with the exact bit ranges asserted as a string so IMPL has
  zero ambiguity, and the self-stamp read `(packed >> _FOIL_STAMP_SHIFT) & _FOIL_STAMP_MASK == lvl`.
  Noted the `centuryBonusUsed`-mirroring stamp-at-bit-224 form as the documented-but-not-chosen
  alternative. Cited SEC-03/SEC-04.
- The PIN 1 USER-sign-off flag is marked clearly enough for Plan 04's consolidation to surface it in
  the SPEC's "USER decisions to confirm" callout.

## Task Commits

Both `type="auto"` tasks write to the **same single artifact** (`445-SPEC-D-storage.md`), which was
authored in one atomic pass (Task 1 = the layout body §D.0–D.5; Task 2 = the pinned-decisions section
§D.6), then committed once:

1. **Task 1 + Task 2: SPEC-D storage layout + the two pinned layout decisions** — `eb7010dd` (docs)

_No separate metadata commit is made for STATE/ROADMAP — the orchestrator owns those writes by hand
for this repo. This SUMMARY commit is the plan's only metadata commit._

## Files Created/Modified

- `.planning/phases/445-spec-design-lock-the-implementation-contract/445-SPEC-D-storage.md` — the
  locked storage-layout SPEC section (foilRecord packed slot + folded cap flag + foilMatchClaimed
  marker + the two pinned decisions + the USER-sign-off flag).

## Decisions Made

- **E.6 168-bit superset over the D.1 24-bit variant** — the frozen `multBps` must live in the slot
  (RARE-03/MATCH-09 read it at resolve), and storing the full packed `uint32` per ticket makes the
  match predicate a direct byte compare.
- **PIN 1 single-slot lock** — one cold slot per player, per-level auto-reset for free, no
  cap/record desync; the `level=>player` alternative is documented (additive widening) but the
  single-slot form is the §5-compliant minimum.
- **PIN 2 `[144-167]`-stamp / `[0-143]`-payload** — keeps the four 32-bit sigs + the 16-bit `multBps`
  contiguous in the low 144 bits; the bit-224 `centuryBonusUsed` mirror is documented but not chosen.

## Deviations from Plan

None — plan executed exactly as written. Both `type="auto"` tasks transcribed the RESEARCH §D
reconciled E.6 superset verbatim into directive prose + bit-range tables (no fenced Solidity
declaration bodies, per the plan's instruction); no bugs, missing functionality, or blocking issues
arose (paper-only SPEC authoring). The two tasks share one artifact and were committed in a single
atomic commit (the file is one continuous document — Task 2's pins are an appended section of the
same file Task 1 created); both tasks' automated verify gates passed independently before the commit.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration. **One USER decision is flagged in the SPEC for sign-off
before the 446 IMPL gate** (PIN 1's USER-SIGN-OFF FLAG: the single-slot lock means a player who
re-buys at L+1 before claiming L's matches loses L's unclaimed signatures — confirm acceptable, or
switch to the `level=>player` variant). Plan 04's consolidation surfaces this in the SPEC's "USER
decisions to confirm" callout.

## Verification

- Task 1 automated verify: PASS — `foilMatchClaimed`, the keccak `player…level…day…drawKind…ticketIndex`
  key, `168`/`4×32`/`32-bit sig`, `2393`, and `1122`/`whalePassClaims` all string-present.
- Task 2 automated verify: PASS — `pin 1`/`level-keying`/`single-slot`, `pin 2`/`bit-offset`/`144-167`,
  `USER-SIGN-OFF`/`USER REVIEW`/`sign-off`, and `level => mapping`/`mapping(level`/`level=>` all present.
- Plan-level verify: PASS — `445-SPEC-D-storage.md` exists; the layout, the cap flag, the claimed
  marker, and BOTH pins are string-present.
- `git diff --quiet -- contracts/` → CLEAN (no `contracts/*.sol` touched; paper-only plan, read-only
  on contracts honored).
- No `.planning/STATE.md` or `.planning/ROADMAP.md` write (orchestrator owns those; the pre-existing
  `STATE.md` modification remains unstaged and untouched).
- Stub scan: NONE (no TODO/FIXME/placeholder/coming-soon — the USER-SIGN-OFF FLAG is a deliberate
  decision callout, not a stub).

## Known Stubs

None.

## Threat Flags

None — this plan authors a `.planning/` design-lock SPEC section only; it introduces no code, no
network endpoint, no auth path, and no file access. The storage surface it specifies (the two new
mappings appended at the tail) is exactly the plan's `<threat_model>` register (T-445-D1 slot
collision → append-only/no-slot-move; T-445-D2 double-claim → CEI sparse marker; T-445-D3 fast
`level++` grief → accept-by-design §5 + the PIN 1 single-slot loss edge surfaced for USER sign-off).
No new trust-boundary surface beyond that register is introduced. SEC-04 (no-slot-move) is attested
downstream at 448 by the layout-golden re-pass.

## Next Phase Readiness

- The storage-layout SPEC section is byte-budget-exact; an IMPL-446 author can declare `foilRecord`,
  `foilMatchClaimed`, the five masks/shifts, and the two accessors with ZERO further layout decision
  beyond the two pins.
- PIN 2 is locked outright; **PIN 1 carries the one open USER sign-off** (the single-slot L+1-overwrite
  player-loss edge) — Plan 04's consolidation must surface it, and USER must confirm before the 446
  IMPL gate.
- Ready for Plan 04 (SPEC consolidation) to consume §D and carry the USER-sign-off flag forward.

## Self-Check: PASSED

- `445-SPEC-D-storage.md` — FOUND.
- `445-02-SUMMARY.md` — FOUND (this file).
- Commit `eb7010dd` (Task 1 + Task 2 SPEC-D) — FOUND in `git log`.
- `git diff --quiet -- contracts/` → CLEAN.
- `.planning/STATE.md` / `.planning/ROADMAP.md` ABSENT from my commit (orchestrator-owned; the
  pre-existing `STATE.md` modification remains unstaged and untouched).

---
*Phase: 445-spec-design-lock-the-implementation-contract*
*Completed: 2026-06-20*
