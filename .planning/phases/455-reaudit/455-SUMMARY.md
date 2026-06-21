---
phase: 455-reaudit
subsystem: audit
tags: [degenerette, variant-2, solvency, rng-integrity, liveness, cross-model]
requires:
  - phase: 453-impl-the-sole-approval-gate
    provides: "v73 byte-frozen subject (commit 64ec993e; contracts/ tree d6615306)"
  - phase: 454-tst
    provides: "byte-reproduce + EV/EVEQ + rig-parity + held-fixed-invariant proofs (943/0/108 forge)"
provides:
  - "v73 3-pillar re-audit (Solvency / RNG-integrity / Liveness-no-brick) on the new scoring"
  - "cross-model (Codex) corroboration of the 3 load-bearing claims"
affects: [456-terminal]
requirements-completed: [AUD-01]
completed: 2026-06-21
---

# Phase 455 — REAUDIT Summary

**The v73 Variant-2 scoring change was re-audited across all three pillars by isolated top-model
subagents (neutral prompts) plus a cross-model Codex corroboration. VERDICT: 0 CATASTROPHE / 0 HIGH
/ 0 MED / 0 LOW. Only by-design INFO confirmations. No contract change required.**

## Method (per the standing isolated-subagent + cross-model architecture)

The audit subject is the single-file v73 diff (`git show 64ec993e`), consumed in `_resolveFullTicketBet`
and the three box/claim spin paths. Three isolated `general-purpose` subagents (neutral,
defensive-engineering prompts; read-only — tree verified clean after) each took one pillar; a Codex
`exec` pass independently re-checked the three load-bearing claims. The 454 stat/Foundry proofs
(byte-reproduce, EV exactness, EVEQ, P(S=9) invariance, rig distribution-parity, curves byte-unchanged)
are the quantitative backbone; this phase verifies CODE-LEVEL wiring, freeze, and safety.

## Pillar 1 — SOLVENCY (no path pays unbacked value): PASS, 0 findings

- Re-ran `derive_5_tables.py` and diffed all **44** v73 constants vs the contract → 44/44 byte-match
  (no swapped HEROGOLD/HEROCOMMON, no mis-pasted packed slot). Every honest sub-case basePayoutEV ∈
  [99.99968, 100.0] centi-x; every rigged-lane EV ∈ [99.99857, 99.99955] — all ≤ 100 (house edge ≥ 0).
- `heroIsGold = ((playerTicket >> (heroQuadrant*8+3)) & 7) == 7` is the correct gold-color (==7)
  extraction for the hero quadrant, consistent with `_countGoldQuadrants` and the trait packing.
- At ALL four call sites the SAME `heroQuadrant` local feeds both `_score(...)` and the `heroIsGold`
  derivation — the scored hero quadrant can never diverge from the table-selection quadrant. N0/N4
  collapse is sound (N=0 ⇒ hero common; N=4 ⇒ hero gold). Rigged lane only reachable under
  `currency==WWXRP`; FLIP/ETH never read a rigged table and vice-versa.
- Bonus-bucket indexing in-range (0 or 6..9; factor lookup gated on `bucket!=0`), ETH bonus EV exactly
  5.0000% so redistribution cannot overpay. The rig (m≥7 cap) can never route an S=9 payout; the S=9
  pin is by-N only and reachable only by an organic all-8-axes match.

## Pillar 2 — RNG INTEGRITY / MANIPULABILITY (freeze-at-commitment): PASS, 0 findings

- Result seed (`keccak256(rngWord, index[, spinIdx], QUICK_PLAY_SALT)`) and rig seed
  (`EntropyLib.hash2(resultSeed, WWXRP_RIG_SALT)`) are byte-identical in shape to pre-v73 and derive
  only from the committed `lootboxRngWordByIndex[index]`. The rig seed is reel-independent; gate
  (`rigSeed%5>=3`) and pick (`(rigSeed>>8)%u`) consume disjoint bits of a frozen hash.
- All table selectors — heroQuadrant, customTicket, N (goldCount), heroIsGold, activityScore — are
  fixed at bet PLACEMENT (placement requires the frontier index word == 0; the word lands later via
  VRF; `delete degeneretteBets` + frontier-zero block any re-commit against a revealed word). No path
  mutates a placed bet, so a player who could foresee the word still could not re-pick to bias the
  table or the rig pool. Box-spin resolvers are delegatecall-gated (`address(this)!=GAME → revert`)
  with `customTicket=0` and a committed seed — no caller-chosen input.
- The m≥7 cap holds IN CODE: each fired roll forces exactly one axis and returns, so post-force M≤7 ⇒
  S≤8; the +2 unlock raises S by 2 but M by only 1, so S=9 (⟺ M=8) is unreachable by the rig.
- Resolution is caller- and order-independent: `_score` is a pure function of committed inputs; the
  `ResolveAcc`/`betLootboxShare` accumulators are additive-only and never feed back into scoring; the
  FLIP survival-flip and recirc box are keyed by the immutable `betId`.

## Pillar 3 — LIVENESS / NO-BRICK / STATE-INTEGRITY: PASS, 0 findings

- `% u` is guarded by an explicit `if (u==0) return` placed after the m≥7 cap and the gate and before
  the modulo (this is the one hardening v73 itself shipped — the prior code relied on an unstated
  `u≥1` invariant that Variant-2's narrowed eligible pool could break). The `5` divisor is constant.
- Pass-1 and pass-2 of the rig walk quadrants 0→3 recomputing the same predicates from the
  never-mutated `playerTicket`/`resultTicket`, enumerating the same `u` cells in the same order, so
  `pick∈{0..u-1}` always reaches `pick==0` at an eligible cell and returns; `--pick` only runs when
  `pick>0` — no underflow, no fall-through.
- All packed-slot shifts in range: `s≤7` for the packed path (s=8/9 separate), `(bucket-6)*64` only
  when bucket∈6..9, N dispatch total over 0..4, heroQuadrant validated `<4` at placement.
- advanceGame / keeper path: the state-write surface (betLootboxShare, the cross-bet ResolveAcc flush,
  claimablePool/_creditClaimable, the FLIP flip, the s==9 whale-pass bracket write) is byte-identical
  to pre-v73 — entirely outside the diff hunks. v73 changes only WHICH table/bucket is read.
- Pull-claim preserved: no new push-transfer; ETH accrues to claimable (pull), FLIP/WWXRP mint once
  per currency. EIP-170: `forge build --sizes` = 15,873 B runtime (8,703 B margin). Rig is WWXRP-only
  (cap 5 spins), pure, storage-free → negligible bounded gas; the 25/45-spin worst case (ETH/FLIP,
  no rig) stays < 30M (per the Variant-2-updated worst-case gas test, 454).

## Cross-model corroboration (Codex)

A Codex `exec` pass independently re-checked the three load-bearing claims (solvency, RNG freeze,
no-brick) against the diff. Result: see 455-CODEX-CROSSCHECK.md (folded into the verdict below).

## VERDICT

**0 CATASTROPHE / 0 HIGH / 0 MED / 0 LOW.** All findings INFO/by-design. The v73 change is a bounded,
correctly-wired payout recalibration that preserves solvency, RNG-freeze, and liveness. No contract
change required. Carries (non-blocking, pre-existing, NOT v73): the 6 stale `test:stat` surface
anchors (SurfaceRegression / PerPullEmptyBucketSkip — files v73 never touched) and the harness-wide
`_deployProtocol` real-clock setUp flake (no `block_timestamp` pin in foundry.toml).
