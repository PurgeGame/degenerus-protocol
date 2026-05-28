---
phase: 339-spec-design-lock-rng-freeze-safety-proof-tier-precedence-loc
plan: 02
subsystem: bingo
tags: [claimBingo, design-lock, spec, tier-precedence, storage-shape, module-placement, bingo, batch-01]

# Dependency graph
requires:
  - phase: 339-CONTEXT (discuss-phase)
    provides: D-01 (uint32[8] slot-width), D-05 (reward constants), D-06 (tier-precedence rule), D-07 (dedup keys), D-08 (reward paths + events), D-09 (traitId derivation), D-10 (module placement)
  - phase: 339-01 (prior plan, this wave)
    provides: D-13 anchor correction — sole traitBurnTicket writer = DegenerusGameMintModule.sol:603-643 (cited :2701/:2730/:2813/:654 are READ-side); honored throughout
provides:
  - 339-DESIGN-LOCK-BINGO.md — the settled claimBingo signature + uint32 slot-width disposition + three-mapping storage shape (uint24 key) + traitId derivation + module placement/delegatecall wiring + six reward constants verbatim + reward paths/dedup/no-op/cutoff (SC1, BATCH-01)
  - 339-TIER-PRECEDENCE-ACCEPTANCE-CONTRACT.md — the quadrant-first-before-symbol-first ordering + three-branch acceptance table + both-bits-marking + suppression-guarantee invariant, binding for BINGO-03 (SC3, BATCH-01, item 7)
affects: [340-IMPL, 341-TST, 342-TERMINAL, v52-consolidated-audit]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Design-lock that TRANSCRIBES locked economics into a binding IMPL acceptance contract (does NOT re-derive settled numbers)"
    - "Three-branch acceptance table (regular / additive symbol-first / replacement quadrant-first) with per-branch condition / bits-marked / payout / event / suppression"
    - "Written slot-width-cap disposition (uint32 unreachable) — explicit audit disposition, not silence (D-01)"

key-files:
  created:
    - .planning/phases/339-spec-design-lock-rng-freeze-safety-proof-tier-precedence-loc/339-DESIGN-LOCK-BINGO.md
    - .planning/phases/339-spec-design-lock-rng-freeze-safety-proof-tier-precedence-loc/339-TIER-PRECEDENCE-ACCEPTANCE-CONTRACT.md
  modified: []

key-decisions:
  - "Signature LOCKED: claimBingo(uint256 level, uint8 symbol, uint32[8] calldata slots) — slots is uint32[8] not uint256[8] (D-01); uint32 cap ~4.29B/level/traitId unreachable, stated as a written disposition"
  - "Storage LOCKED: bingoClaimed (per-player u8) / firstQuadrant (systemwide u8) / firstSymbol (systemwide u32), all keyed by uint24 level (cites traitBurnTicket :416 precedent), appended to the SHARED DegenerusGameStorage.sol (delegatecall architecture)"
  - "Module placement LOCKED: new contracts/modules/DegenerusGameBingoModule.sol delegatecalled from DegenerusGame.claimBingo via GAME_BINGO_MODULE (cites the :278-288 advanceGame dispatch shape + the :13-31 ContractAddresses module-constant block)"
  - "Tier-precedence LOCKED (D-06): isQuadrantFirst checked BEFORE isSymbolFirst; quadrant-first marks BOTH bits + pays REPLACEMENT (50bps/5_000e18) + SUPPRESSES symbol-first; symbol-first marks firstSymbol + pays ADDITIVE (10bps/2_000e18); regular pays baseline (5bps/1_000e18)"
  - "KEY INVARIANT: a quadrant-first claim marking firstSymbol guarantees no later same-symbol claim can re-collect the symbol-first bonus (forecloses the double-pay trap) — the behavior TST-02 (341) proves"
  - "Honored 339-01 D-13 correction: the sole traitBurnTicket writer = DegenerusGameMintModule.sol:603-643 (keyed by RNG-resolved traitId :586-587); cited :2701/:2730/:2813/:654 are READ-side — NOT re-introduced as writers"

patterns-established:
  - "Producer-before-consumer edit-order map for the 340 diff: storage → new module → ContractAddresses → DegenerusGame entrypoint+interface → REBAL → JACK"
  - "Grep-attest every cited file:line against the live tree (≡ 812abeee for contracts/) before transcribing the design-lock"

requirements-completed: [BATCH-01]

# Metrics
duration: ~18min
completed: 2026-05-28
---

# Phase 339 Plan 02: claimBingo BINGO Design-Lock + Tier-Precedence Acceptance Contract Summary

**Settled the full claimBingo bundle DESIGN in writing — the locked signature + uint32 slot-width disposition + three-mapping storage shape (uint24 key) + module placement/delegatecall wiring + six reward constants verbatim — and wrote the tier-precedence rule (quadrant-first-before-symbol-first, both-bits-marked, suppression) as the binding IMPL acceptance contract for BINGO-03, so IMPL 340 authors a fully-reconciled diff with zero "by construction" assumptions and avoids the double-pay trap.**

## Performance

- **Duration:** ~18 min
- **Started:** 2026-05-28 (Phase 339 Plan 02 execution start)
- **Completed:** 2026-05-28
- **Tasks:** 2 completed
- **Files created:** 2 (both design-lock docs); 0 contract/test files touched

## Accomplishments

- **339-DESIGN-LOCK-BINGO.md** — the settled BINGO design (SC1 / BATCH-01). Records: (1) the LOCKED signature `claimBingo(uint256 level, uint8 symbol, uint32[8] calldata slots)` with the explicit **uint32 slot-width disposition** (~4.29B entries per (level, traitId) unreachable — would need 4 billion RNG-resolved entries of ONE trait byte on ONE level; bounded far below 2^32 by the per-level supply note at `DegenerusGameStorage.sol:415`; written, not silent). (2) the three-mapping **storage shape** — `bingoClaimed` (per-player u8, quadrant mask) / `firstQuadrant` (systemwide u8) / `firstSymbol` (systemwide u32) — all keyed by the existing `uint24` level (cites the `traitBurnTicket` `:416` precedent) and appended to the SHARED `DegenerusGameStorage.sol` layout (delegatecall architecture → storage must be shared; pre-launch redeploy-fresh → appending safe, no migration). (3) the **traitId derivation** `traitId = (quadrant<<6)|(c<<3)|symInQ`, `quadrant = symbol>>3`, `symInQ = symbol&7`, trait byte `[QQ][CCC][SSS]` (cites `DegenerusTraitUtils.sol:17-39`), with duplicate-slot griefing impossible. (4) the **module placement** — new `contracts/modules/DegenerusGameBingoModule.sol` delegatecalled from a new `DegenerusGame.claimBingo` entrypoint via `ContractAddresses.GAME_BINGO_MODULE` (cites the `DegenerusGame.sol:278-288` advanceGame dispatch shape + the `ContractAddresses.sol:13-31` module-constant block) + the interface signatures. (5) the **six reward constants transcribed verbatim** (D-05) with percent equivalents + additive-vs-replacement semantics. (6) the **reward paths** (`transferFromPool(Pool.Reward,…)` clamped-return as `dgnrsPaid`, ref `DegeneretteModule.sol:1135-1159`; `coinflip.creditFlip`, ref `MintModule.sol:1319`), the **empty-pool graceful no-op**, the **gameOver hard cutoff**, the **per-player (level,quadrant) dedup** (max 4/player/level), and the **event-only leaderboard** (`FirstQuadrantBingo` / `FirstSymbolBingo` / `BingoClaimed`). Also includes the producer-before-consumer edit-order map for the 340 diff.
- **339-TIER-PRECEDENCE-ACCEPTANCE-CONTRACT.md** — the binding IMPL acceptance contract for the 3-tier selection (SC3 / BATCH-01 / item 7). States `isQuadrantFirst` is checked **BEFORE** `isSymbolFirst` as an ordered `if/else-if/else` cascade; enumerates the three branches as an acceptance table (per branch: condition / bits marked / sDGNRS bps→% / BURNIE / event / suppression) — quadrant-first marks **BOTH** bits + pays the REPLACEMENT (50 bps = 0.5% + 5 000e18) + SUPPRESSES the symbol-first bonus + emits `FirstQuadrantBingo`; symbol-first marks `firstSymbol` + pays the ADDITIVE (10 bps = 0.1% + 2 000e18) + emits `FirstSymbolBingo`; regular pays the baseline (5 bps = 0.05% + 1 000e18); every branch then emits `BingoClaimed`. States the **KEY INVARIANT** — a quadrant-first claim marking the `firstSymbol` bit guarantees no later same-symbol claim can re-collect the symbol-first bonus (forecloses the double-pay trap, sound because a quadrant-first is necessarily also the chronological symbol-first) — and binds it to **BINGO-03 (340)** and the behavior **TST-02 (341)** proves.

## Task Commits

Each task was committed atomically:

1. **Task 1: BINGO design-lock (signature + storage + slot-width + module placement + constants)** — `1db9fcb3` (docs)
2. **Task 2: tier-precedence acceptance contract (quadrant-first-before-symbol-first + suppression)** — `d5860ef9` (docs)

**Plan metadata:** (this SUMMARY + STATE/ROADMAP/REQUIREMENTS) committed separately as the final docs commit.

## Files Created/Modified

- `.planning/phases/339-.../339-DESIGN-LOCK-BINGO.md` — the BINGO design-lock (SC1 / BATCH-01): signature + uint32 slot-width disposition + three mappings (uint24 key) + traitId derivation + module placement/delegatecall wiring + six constants verbatim + reward paths/dedup/no-op/cutoff + edit-order map.
- `.planning/phases/339-.../339-TIER-PRECEDENCE-ACCEPTANCE-CONTRACT.md` — the tier-precedence acceptance contract (SC3 / BATCH-01 / item 7): ordered precedence + three-branch table + both-bits-marking + suppression-guarantee invariant + BINGO-03/TST-02 binding.

No `contracts/*.sol` or `test/` files touched (paper-only SPEC plan). `git diff 812abeee HEAD -- contracts/` is EMPTY.

## Decisions Made

- Every cited `file:line` was grep-attested against the live tree (≡ `812abeee` for `contracts/`) at execution start before transcribing: `traitBurnTicket` uint24 key `:416`; trait byte `[QQ][CCC][SSS]` at `DegenerusTraitUtils.sol:17-39`; the delegatecall dispatch shape at `DegenerusGame.sol:278-288` (advanceGame) and `:520-532`/`:545-554` (purchase/purchaseCoin); the `GAME_*_MODULE` constant block at `ContractAddresses.sol:13-31`; the sole `traitBurnTicket` writer at `MintModule.sol:603-643` (keyed by the RNG-resolved `traitId` `:586-587`).
- Honored the 339-01 D-13 anchor correction throughout: the design-lock describes `MintModule:603-643` as the authoritative `traitBurnTicket` writer and treats `DegenerusGame.sol:2701/2730/2813` + `JackpotModule:654` as READ-side consumers; the read-side anchors are NOT re-introduced as writers.
- The design-lock TRANSCRIBES the locked economics (D-05) verbatim and does NOT re-litigate settled numbers — per the "Specific Ideas" directive that the SPEC is a faithful design-lock, not a re-derivation. The one piece of selection logic that needed unambiguous prose (the tier-precedence suppression + bit-marking) is written as a directive acceptance table.
- Per `.gitignore:22` (`.planning/` is directory-ignored), both docs were committed via `git add -f`, consistent with the established convention by which the prior 339-01 docs are tracked.

## Deviations from Plan

None — plan executed exactly as written. All anchors verified live; no corrections needed beyond carrying forward the already-recorded 339-01 D-13 read-vs-write classification (honored, not re-discovered).

**Total deviations:** 0
**Impact on plan:** None. Paper-only, zero contract edits, all locked decisions (D-01/D-05/D-06/D-07/D-08/D-09/D-10) honored; the 339-01 D-13 correction propagated into the storage-shape / traitId-derivation prose as instructed in the cross-plan note.

## Issues Encountered

None.

## Known Stubs

None. No placeholder / TODO / FIXME patterns in either design-lock doc. Both are settled, source-attested design-lock documents.

## Threat Flags

None. This plan introduces no new security-relevant surface — it records the design-lock + acceptance contract over the existing claimBingo design surface already enumerated in the plan's `<threat_model>`. T-339-04 (economic over-pay via the tier-precedence double-pay trap) is MITIGATED by the tier-precedence acceptance contract's both-bits-marking + suppression + no-later-re-collect invariant (the binding three-branch table); T-339-05 (storage-shape / level-key tampering) is MITIGATED by fixing all three mappings to the `uint24` level key (cites `:416` precedent) + the written uint32 slot-width disposition; T-339-SC (package installs) is moot — paper-only Markdown authoring, no installs.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- **For IMPL 340 (BINGO-01..05 / REBAL-01 / JACK-01/02 / BATCH-02):** the two design-lock docs are the binding acceptance contract for the BINGO portion. IMPL must (a) implement the tier cascade exactly per `339-TIER-PRECEDENCE-ACCEPTANCE-CONTRACT.md` (quadrant-first-before-symbol-first, BOTH bits on quadrant-first, suppression, the universal `BingoClaimed`) — any IMPL paying the symbol-first bonus on a quadrant-first claim, or failing to set `firstSymbol |= sMask` on a quadrant-first, VIOLATES the contract; (b) append the three mappings to the SHARED `DegenerusGameStorage.sol` (NOT the module), keyed by `uint24`; (c) wire `claimBingo` via `GAME_BINGO_MODULE` mirroring `DegenerusGame.sol:278-288`; (d) treat `MintModule:603-643` as the authoritative `traitBurnTicket` writer and `claimBingo` as a strict read-only consumer (no write to `traitBurnTicket`); (e) follow the producer-before-consumer edit-order map in §8 of the BINGO design-lock.
- **For TST 341 (TST-02):** the tier-precedence acceptance contract names the exact suppression behavior TST-02 will prove — a quadrant-first claim pays the replacement, suppresses the symbol-first bonus, and marks the symbol bit so a later non-quadrant-first same-symbol claim gets only the regular reward.
- No blockers.

## Self-Check: PASSED

- FOUND: 339-DESIGN-LOCK-BINGO.md
- FOUND: 339-TIER-PRECEDENCE-ACCEPTANCE-CONTRACT.md
- FOUND: 339-02-SUMMARY.md
- FOUND commit: `1db9fcb3` (Task 1)
- FOUND commit: `d5860ef9` (Task 2)
- Contract guard: `git diff 812abeee HEAD -- contracts/` EMPTY (zero contract edits)
- Task 1 automated verify: PASS · Task 2 automated verify: PASS

---
*Phase: 339-spec-design-lock-rng-freeze-safety-proof-tier-precedence-loc*
*Completed: 2026-05-28*
