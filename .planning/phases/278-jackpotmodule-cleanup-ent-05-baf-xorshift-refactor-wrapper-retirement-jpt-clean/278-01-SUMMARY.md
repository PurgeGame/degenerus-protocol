---
phase: 278-jackpotmodule-cleanup-ent-05-baf-xorshift-refactor-wrapper-retirement-jpt-clean
plan: 01
subsystem: jackpot
tags: [solidity, entropy, keccak, xorshift, jackpot, events, dead-code-cleanup, storage-layout]

# Dependency graph
requires:
  - phase: 276-jackpotmodule-2216-baf-bernoulli-jpt-br
    provides: "_jackpotTicketRoll Bernoulli whole-ticket round-up + :2216 swap to direct _queueTickets(whole, true), which left _queueLootboxTickets with zero callers"
  - phase: 277-event-surface-unification-sentinel-retirement-evt-uni
    provides: "JackpotTicketWin gains the bool roundedUp 7th field — the event surface this plan's whole-ticket value unification emits into"
provides:
  - "_jackpotTicketRoll evolves entropy via EntropyLib.hash2(entropy, entropy) (keccak self-mix) instead of EntropyLib.entropyStep (xorshift) — low-bit path/level consumers + bits[200..215] Bernoulli slice now read a full-diffusion keccak word"
  - "2-roll per-roll-uniqueness invariant in _awardJackpotTickets structurally preserved with zero body edit (return-and-rethread)"
  - "All 3 JackpotTicketWin emit sites emit the whole ticket count (no * TICKET_SCALE scaling); event signature/topic-hash unchanged"
  - "EntropyLib.entropyStep deleted — library keeps only hash2"
  - "Zero-caller _queueLootboxTickets wrapper deleted from DegenerusGameStorage.sol"
  - "Storage-layout byte-identity proof + gas worst-case derivation artifacts for Phase 280 terminal audit §3.A consumption"
affects: [278-02 test wave, 280 terminal audit, EXC-04 KI envelope demotion]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "hash2(entropy, entropy) self-mix: full-diffusion keccak entropy evolution with zero new constants introduced"
    - "Whole-ticket event-value unification: emit value matches the adjacent _queueTickets storage-write argument at all 3 sites"

key-files:
  created:
    - .planning/phases/278-jackpotmodule-cleanup-ent-05-baf-xorshift-refactor-wrapper-retirement-jpt-clean/278-01-STORAGE-LAYOUT-DIFF.md
    - .planning/phases/278-jackpotmodule-cleanup-ent-05-baf-xorshift-refactor-wrapper-retirement-jpt-clean/278-01-GAS-WORSTCASE.md
  modified:
    - contracts/modules/DegenerusGameJackpotModule.sol
    - contracts/libraries/EntropyLib.sol
    - contracts/storage/DegenerusGameStorage.sol
    - contracts/modules/DegenerusGameMintModule.sol

key-decisions:
  - "D-278-ENT05-CHAIN-01: hash2(entropy, entropy) self-mix chosen over a fixed-salt constant — zero new constants, smaller audit surface; per-roll uniqueness depends on the FIRST arg differing between rolls (guaranteed by the rethread), not the second"
  - "Bernoulli slice offset stays at bits[200..215] — any slice of a full keccak word is full-entropy; keeping 200 preserves the Phase-276 NatSpec"
  - "ENT-05 keccak swap intentionally CHANGES BAF roll output semantics for a given seed (not byte-equivalent to v39); Roadmap SC2 permits this. JackpotTicketWin topic-hash unchanged — only emitted values shift"

patterns-established:
  - "hash2(entropy, entropy) self-mix: the canonical full-diffusion entropy-evolution primitive for JackpotModule, mirroring the call shape of _rollRemainder's EntropyLib.hash2(entropy, rollSalt) at MintModule.sol"
  - "Whole-ticket event-value unification: JackpotTicketWin.ticketCount is a whole count on all 3 paths, self-consistent with the adjacent _queueTickets storage write"

requirements-completed: [JPT-CLEAN-01, JPT-CLEAN-02, JPT-CLEAN-03, JPT-CLEAN-04, JPT-CLEAN-05, JPT-CLEAN-06]

# Metrics
duration: ~50min
completed: 2026-05-14
---

# Phase 278 Plan 01: JackpotModule Cleanup + ENT-05 Keccak Refactor + Wrapper Retirement Summary

**`_jackpotTicketRoll` swaps its xorshift entropy evolution for a full-diffusion `EntropyLib.hash2(entropy, entropy)` keccak self-mix, all 3 `JackpotTicketWin` emits unify onto whole-ticket counts, and the dead `EntropyLib.entropyStep` + `_queueLootboxTickets` functions are deleted — −689 bytes deployed bytecode, storage layout byte-identical to v39 baseline `6a7455d1`.**

## Performance

- **Duration:** ~50 min (including the blocking human-verify checkpoint review pause)
- **Started:** 2026-05-14T11:05Z (approx; prior executor agent)
- **Completed:** 2026-05-14T11:55:10Z
- **Tasks:** 3 (Tasks 1-2 by prior executor agent; Task 3 commit + this summary by continuation agent post-approval)
- **Files modified:** 4 contract files

## Accomplishments
- **ENT-05 keccak refactor (JPT-CLEAN-04):** `_jackpotTicketRoll` evolves `entropy` via `EntropyLib.hash2(entropy, entropy)` on entry instead of `EntropyLib.entropyStep`. The low-bit path/level consumers (`entropy / 100`, `% 4`, `% 46`) and the bits[200..215] Bernoulli slice now read a full-diffusion keccak word — converting EXC-04 (BAF-jackpot xorshift KI envelope) from a documented `NARROWS` known-issue toward a fixed non-issue at near-zero gas cost.
- **2-roll chaining preserved:** the return-and-rethread pattern in `_awardJackpotTickets` is structurally intact with zero body edit — roll 2's input equals roll 1's keccak output, so per-roll words remain distinct (keccak collision-resistance guarantees distinct roll-1 inputs → distinct roll-2 inputs).
- **JackpotTicketWin whole-ticket unification (JPT-CLEAN-01/02/03):** all 3 emit sites emit the whole ticket count (trait-burn `ticketCount`, coin-path `uint32(units)`, BAF `whole`) — each now self-consistent with its adjacent `_queueTickets` storage-write argument. Event signature and topic-hash unchanged; only emitted values + NatSpec shift.
- **Dead-code retirement (JPT-CLEAN-05):** `EntropyLib.entropyStep` deleted (library keeps only `hash2`); zero-caller `_queueLootboxTickets` wrapper deleted from `DegenerusGameStorage.sol`. Sibling helpers `_queueTickets`, `_queueTicketsScaled`, `_queueTicketRange` untouched.
- **Proof artifacts (JPT-CLEAN-06):** storage layout proven byte-identical to v39 baseline `6a7455d1` (`forge inspect storage-layout` diff empty, sha256 cross-check identical); gas worst-case derived analytically first, then `−689 bytes` deployed bytecode delta measured (NET-NEGATIVE).

## Task Commits

1. **Task 1: ENT-05 keccak swap + entropyStep deletion + MintModule comment touch** — part of `8a81a87c` (feat) — applied in working tree by prior executor agent
2. **Task 2: 3× JackpotTicketWin whole-ticket unification + _queueLootboxTickets deletion** — part of `8a81a87c` (feat) — applied in working tree by prior executor agent
3. **Task 3: storage-layout/gas proof + batched-diff approval + commit** — `8a81a87c` (feat) — the single batched USER-APPROVED contract commit carrying all of Tasks 1-3

**Plan metadata:** committed alongside this SUMMARY + the 2 proof artifacts as a separate docs commit.

_Note: Phase 278 follows the project's batched-contract-approval discipline — all contract edits from Tasks 1-2 land in ONE user-approved commit (`8a81a87c`), not per-task commits._

## Files Created/Modified
- `contracts/modules/DegenerusGameJackpotModule.sol` — `_jackpotTicketRoll` `:2210` `entropyStep`→`hash2(entropy, entropy)` swap; 3 `JackpotTicketWin` emit-value unifications onto whole counts; bit-allocation NatSpec + event-doc + module NatSpec rewrites to describe the keccak derivation
- `contracts/libraries/EntropyLib.sol` — `entropyStep` function + NatSpec deleted; library-level NatSpec rewritten to describe `hash2` as the sole remaining function
- `contracts/storage/DegenerusGameStorage.sol` — zero-caller `_queueLootboxTickets` wrapper + NatSpec deleted; sibling queue helpers untouched
- `contracts/modules/DegenerusGameMintModule.sol` — `_rollRemainder` design-rationale comment at `:649` rewritten to drop the dead `entropyStep` name while keeping the keccak-over-XOR rationale (comment-only touch)
- `.planning/phases/278-.../278-01-STORAGE-LAYOUT-DIFF.md` — storage-layout byte-identity proof vs `6a7455d1` (PASS)
- `.planning/phases/278-.../278-01-GAS-WORSTCASE.md` — worst-case gas derivation + `−689 bytes` deployed bytecode delta

## Decisions Made
- **D-278-ENT05-CHAIN-01** — `hash2(entropy, entropy)` self-mix chosen over a fixed-salt constant. Rationale: keccaks the full 256-bit `entropy` word into a new full-diffusion word with zero new constants introduced (smaller audit surface, no magic number to justify). Per-roll uniqueness does not depend on the second arg differing — it depends on the FIRST arg differing between rolls, which the `_awardJackpotTickets` rethread guarantees.
- **Bernoulli slice offset stays at bits[200..215]** — any slice of a full keccak word is full-entropy; keeping 200 preserves the Phase-276 NatSpec.
- **ENT-05 semantics change accepted** — the keccak swap intentionally CHANGES BAF roll output for a given seed (not byte-equivalent to v39); Roadmap SC2 permits this. `JackpotTicketWin` topic-hash unchanged — only emitted values shift.

## Deviations from Plan

None - plan executed exactly as written. Tasks 1-2 applied the contract edits per the plan's `<action>` blocks; Task 3 produced the two proof artifacts, the user reviewed and approved the batched 4-file diff, and the continuation agent committed exactly the 4 contract files with the required commit-body content.

## Issues Encountered
- **Contract-commit guard hook:** the repo's pre-commit guard blocks `git add` of `contracts/` files unless `CONTRACTS_COMMIT_APPROVED=1` is set. The user had explicitly reviewed the batched diff and responded "approved" (the plan's Task 3 resume-signal), so the env var was set to satisfy the guard — consistent with the project's `feedback_no_contract_commits.md` / `feedback_batch_contract_approval.md` discipline (the guard enforces exactly that gate; explicit user approval was obtained first).
- **`entropyStep` still present in `contracts/test/JackpotBernoulliTester.sol`** (2 NatSpec hits) — this is a Wave 2 / plan 278-02 file, correctly out of this plan's scope per CONTEXT.md D-278-ENTROPYSTEP-DELETE-01. Not touched.
- **Pre-existing compiler shadow warning** at `DegenerusGameJackpotModule.sol:535` (`effectiveEntropy` shadows an outer declaration) — pre-existing, unrelated to this plan's edits, out of scope. `npx hardhat compile` succeeds (warning only, no error).

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- **278-02 (test wave)** is ready: TST-CLEAN-01 ENT-05 post-refactor statistical invariant, TST-CROSS-01 cross-surface `rem`-byte regression, TST-CLEAN-02/03 wrapper-removal & whole-ticket-event regression, plus the `entropyStep`-replica/drift-gate updates in `JackpotBernoulliTester.sol` (the 2 remaining NatSpec hits live there and are 278-02's to resolve).
- **EXC-04 KI envelope** is now a candidate for demotion from `NARROWS` to `NEGATIVE` at v40 close (Phase 280 terminal audit) — the ENT-05 BAF xorshift refactor has landed.
- The `8a81a87c` contract commit is local-only; **not pushed** — future push is a separate user gate per `feedback_manual_review_before_push.md`.

## Self-Check: PASSED

- `contracts/modules/DegenerusGameJackpotModule.sol`, `contracts/libraries/EntropyLib.sol`, `contracts/storage/DegenerusGameStorage.sol`, `contracts/modules/DegenerusGameMintModule.sol` — all present in commit `8a81a87c`
- `278-01-SUMMARY.md`, `278-01-STORAGE-LAYOUT-DIFF.md`, `278-01-GAS-WORSTCASE.md` — all present on disk
- Commit `8a81a87c` — present in git history

---
*Phase: 278-jackpotmodule-cleanup-ent-05-baf-xorshift-refactor-wrapper-retirement-jpt-clean*
*Completed: 2026-05-14*
