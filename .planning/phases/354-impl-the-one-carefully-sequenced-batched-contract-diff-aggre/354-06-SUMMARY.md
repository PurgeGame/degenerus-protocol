---
phase: 354-impl-the-one-carefully-sequenced-batched-contract-diff-aggre
plan: 06
status: complete
contract_commit: e18af451
baseline_sha: 453f8073
---

# 354-06 SUMMARY — Contract-commit boundary

## Self-Check: PASSED

The whole v56 batched contracts diff was verified (`forge build` exit 0), hand-reviewed by the USER,
and committed by them (via the agent at the USER's explicit "approved" authorization) as the single
batched commit `e18af451`. Producer-before-consumer ordering, the 14 per-requirement contract sites,
and the SOLVENCY-01 byte-unchanged invariant were attested in `354-06-DIFF-REVIEW.md` (on disk;
gitignored as a `*REVIEW*` artifact).

## What landed

Single batched contract commit **`e18af451`** — `feat(354): v56 AfKing everyday-gas …` — 7 files,
+701/−326 vs baseline `453f8073`:
- `storage/DegenerusGameStorage.sol` — `Sub` re-packed into one 256-bit slot (in-slot accumulator
  `affiliateBase`/`questProgress`/`buyerOwedBurnie` + `hasEverSubscribed` + `afkCoveredThroughDay`;
  3 settle markers dropped; `amount`→milli-ETH).
- `DegenerusQuests.sol` (+interface) — `onlyGame settleAfkingQuest` entrypoint; O1 double-credit fix;
  dead `handleLootBox` removed.
- `modules/GameAfkingModule.sol` (+`IDegenerusGameModules`) — per-buy storm → one warm in-slot accrue;
  `drainAffiliateBase`; inline `_settleQuest` + `claimQuest` + unsub-settle + first-sub head-start;
  ticket minimal-write primitive (`buyerOwedBurnie`, century parity, boons/boost-off) replacing
  `purchaseWith`; open re-verified (milli-ETH→wei rescale only).
- `DegenerusAffiliate.sol` (+interface) — flat-7% deterministic-split `claim` mints A/U1/U2 directly.

## Gate-time USER changes (folded into the committed diff)

1. **Affiliate two-step → single-step `claim`** — `claim` now mints A/U1/U2 (or VAULT/DGNRS) directly
   via `creditFlip`; `pendingClaim` + `withdraw()` removed. Same recipients/amounts/split (no roll/seed).
   Supersedes 353-SPEC AFF-01's PULL-two-step. See [[affiliate-claim-single-step-direct-mint]].
2. **Comment cleanup across the diff** — comments trimmed to "how the code works"; plan/requirement/
   spec-line/test tags + process narration removed. Code byte-unchanged (SOLVENCY-01 debit statements
   confirmed unchanged). See [[lean-code-comments-no-procedural-meta]].

## Requirements (14 IMPL)

AGG-01..05, TKT-01/02, QST-01..05, OPEN-01/02 — all have their contract site present in `e18af451`
and compile clean. Empirical proofs are deferred to phase 356 (TST); the IMPL acceptance bar
(`forge build` clean) is met.

## Verification

- `forge build` exits 0 across the whole batched diff.
- SOLVENCY-01 ETH/`claimablePool` debit (`GameAfkingModule.sol:744-745`) byte-unchanged vs `453f8073`.
- Affiliate `claim` contains no `keccak256`/`currentDayIndex` (no roll/seed).
- `purchaseWith`/`consumePurchaseBoost` gone from the afking path; `pendingClaim`/`withdraw` removed repo-wide.

## Follow-up seeds captured (post-v56, own reviewed commits)

- `type Day is uint24` repo-wide UDVT (incl. `rngWordByDay` key) — [[type-day-udvt-post-v56-seed]].
- Batch `handlePurchase`'s inline `burnieMintReward` creditFlip + clarify the "ETH mint reward" comments
  — [[handlepurchase-burnie-flip-batching-post-v56-seed]].
