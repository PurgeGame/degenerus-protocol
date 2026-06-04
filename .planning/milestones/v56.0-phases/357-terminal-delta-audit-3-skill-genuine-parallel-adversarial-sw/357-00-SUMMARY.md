---
phase: 357-terminal-delta-audit-3-skill-genuine-parallel-adversarial-sw
plan: 00
subsystem: contracts
tags: [solidity, afking, affiliate, delegatecall, subscribe-gate, foundry]

requires:
  - phase: 356
    provides: "the v56.0 batching subject + the F-356-01 missing-stub finding this plan fixes"
provides:
  - "HEAD' = ac5f1e033a785d18a9f0b89b7de5d05268431dbd — the sole .sol commit of phase 357; the actually-shippable hardened v56.0 audit subject (audited == shipped)"
  - "F-356-01 fix: drainAffiliateBase(address) dispatch stub in DegenerusGame.sol (DegenerusAffiliate.claim() no longer reverts)"
  - "D-11 pass-required subscribe gate (NoPass)"
  - "D-12 purchase-grounded subscribe gate (MustPurchaseToBeginAfking)"
  - "D-13 VAULT/SDGNRS bootstrap exemption on the un-spoofable resolved subscriber identity"
affects: [357-00b, 357-01, 357-02, 357-03, 357-04]

tech-stack:
  added: []
  patterns:
    - "guard-less Game dispatch stub → module delegatecall → _revertDelegate → data.length==0 guard → abi.decode return tail (mirror claimAfkingBurnie + runDecimatorJackpot)"
    - "subscribe UPSERT gate wrapped by an un-spoofable pinned-address exempt short-circuit (mirror the :996-997 VAULT/SDGNRS idiom)"

key-files:
  created: []
  modified:
    - contracts/DegenerusGame.sol
    - contracts/modules/GameAfkingModule.sol

key-decisions:
  - "FIX-FIRST (D-01): the closure HEAD = the hardened subject; this breaks the prior 'zero contract mutation' TERMINAL mold (the v56-specific footprint)."
  - "Stub tail reuses the file's existing zero-length error `revert E();`, matching the runDecimatorJackpot return tail exactly; no level() stub (auto-getter collision avoided)."
  - "D-12 keyed on the existing NEW-run control flow: the sole unfunded leg (done[0]==false AND cover-buy unfunded) flips to revert; done[0]-grounded + funded-cover-buy + wasActive re-sub paths untouched — no new 'purchased today' predicate added."
  - "D-13 exemptSub computed once on the resolved subscriber identity (:270); D-11 via `!exemptSub &&`, D-12 via an `else if (exemptSub)` base-0 bootstrap branch so VAULT/sDGNRS still self-subscribe at construction without reverting."

patterns-established:
  - "Contract-commit gate: pre-commit hook moved aside + CONTRACTS_COMMIT_APPROVED=1 + stage ONLY the .sol files + restore hook (trap EXIT)."

requirements-completed: [AUDIT-01]

duration: ~18min
completed: 2026-06-03
---

# Phase 357 / Plan 00: Contract Gate Summary

**The three bundled v56.0 hardening changes are committed as HEAD' `ac5f1e03` after explicit USER hand-review — the F-356-01 affiliate-claim revert is fixed and the subscribe UPSERT branch is pass-required + purchase-grounded with a load-bearing VAULT/sDGNRS bootstrap exemption.**

## Performance

- **Tasks:** 4/4 (Tasks 1–3 authored by gsd-executor; Task 4 contract-commit gate owned by the orchestrator after USER approval)
- **Files modified:** 2 (`contracts/DegenerusGame.sol`, `contracts/modules/GameAfkingModule.sol`)
- **Completed:** 2026-06-03

## HEAD' (the downstream re-freeze anchor)

```
ac5f1e033a785d18a9f0b89b7de5d05268431dbd
```

This is the SOLE `contracts/*.sol` commit of phase 357. Pre-fix HEAD was `c5715297`. Everything downstream (357-00b D-14, 357-01 delta-audit, 357-02 sweep, 357-03 FINDINGS, 357-04 closure) re-freezes against HEAD' and is READ-ONLY against `contracts/`.

## Accomplishments

1. **F-356-01 fixed** — `DegenerusGame.sol` gains `function drainAffiliateBase(address sub) external returns (uint256)`: guard-less delegatecall to `GAME_AFKING_MODULE` (mirrors `claimAfkingBurnie`), `_revertDelegate` on failure, `data.length==0` guard, `abi.decode(data,(uint256))` return tail (mirrors `runDecimatorJackpot`). No `level()` stub. `DegenerusAffiliate.claim()` no longer reverts at the `drainAffiliateBase` drain loop → afking-affiliate rewards reachable.
2. **D-11 pass-required** — `subscribe()` UPSERT reverts `NoPass()` unless `_passHorizonOf(subscriber) >= level` (reuses the existing `validThroughLevel` write; deity sentinel `type(uint24).max` always covers; the `:942` crossing eviction unchanged).
3. **D-12 purchase-grounded** — the sole unfunded NEW-run leg flips from `_setStreakBase(s, 0)` → `revert MustPurchaseToBeginAfking()`. Funded, `done[0]`-grounded, and `wasActive` re-sub (already-bought / pending-box) paths unchanged.
4. **D-13 exemption** — both gates short-circuit for `subscriber == ContractAddresses.VAULT || subscriber == ContractAddresses.SDGNRS`, keyed on the un-spoofable resolved identity; VAULT/sDGNRS construction-time self-subscribes (no-pass + unfunded) still succeed.

## Task Commits

Tasks 1–3 produced UNCOMMITTED working-tree edits (the .sol commit is deferred to the gate). Task 4 committed both files atomically after USER approval:

1. **Tasks 1+2+3 (author + build):** bundled — `ac5f1e03`
2. **Task 4 (USER-approved .sol commit, HEAD'):** `ac5f1e03` (fix)

## Verification

- `forge build` exit 0 (only a pre-existing `unsafe-typecast` lint advisory in the untouched `DegenerusGameMintModule.sol`).
- Both plan automated grep-gates PASS (stub shape + guard-less + no level(); both errors declared+reverted + ≥2 VAULT refs).
- Commit contains ONLY the two `.sol` files; pre-commit hook restored; nothing pushed (40 ahead of origin/main).
- SOLVENCY-01 byte-unchanged (revert-only / BURNIE-only; no ETH/claimablePool debit change).

## Self-Check: PASSED

The contract gate is satisfied. The D-14 test reconciliation + new positive proofs + re-freeze are 357-00b.
