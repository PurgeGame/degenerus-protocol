---
phase: 324-terminal-delta-audit-3-skill-adversarial-sweep-closure
plan: 04
milestone: v47.0
milestone_name: Rake-Free Presale + Lootbox-Boon Unification + Redemption/Degenerette/Cancel-Tombstone Bundle
audit_baseline: 16e9668a6de35cc0c809d81ce960aee137950687
audit_baseline_signal: MILESTONE_V46_AT_HEAD_16e9668a6de35cc0c809d81ce960aee137950687
v45_baseline_signal: MILESTONE_V45_AT_HEAD_62fb514bfcc8ad042a45cef960e5ff0ff6fbb801
source_tree_frozen_ref: fabe9e94
audit_subject_head: "MILESTONE_V47_AT_HEAD_da5c9d50989707c8964a9411e68c51ca1b1a25f2"
closure_signal: MILESTONE_V47_AT_HEAD_da5c9d50989707c8964a9411e68c51ca1b1a25f2
deliverable: audit/FINDINGS-v47.0.md
new_findings: 2
new_findings_disposition: F-47-01 (presale closing-box DGNRS windfall, MEDIUM) + F-47-02 (redemption ETH-empty stETH-fallback gap, MEDIUM) — BOTH DEFERRED→v48.0 [fix designs locked; SOURCE-TREE FROZEN held at fabe9e94]
---

# v47.0 Findings — Rake-Free Presale + Lootbox-Boon Unification + Redemption/Degenerette/Cancel-Tombstone Bundle (Terminal)

## 1. Audit Subject + Baseline

**Audit Baseline.** v46.0 closure HEAD `16e9668a6de35cc0c809d81ce960aee137950687` (signal
`MILESTONE_V46_AT_HEAD_16e9668a6de35cc0c809d81ce960aee137950687`). v45 chain reference:
`MILESTONE_V45_AT_HEAD_62fb514bfcc8ad042a45cef960e5ff0ff6fbb801`. v47.0 closure HEAD is
`MILESTONE_V47_AT_HEAD_da5c9d50989707c8964a9411e68c51ca1b1a25f2` (resolved at the Phase 324 closure commit per the 2-commit sequential-SHA
orchestration; see §9c). SOURCE-TREE FROZEN reference for the terminal: `fabe9e94` (contracts/ byte-frozen;
`git diff fabe9e94 HEAD -- contracts/` empty throughout Phase 324).

**Subject.** Every v46→v47 `contracts/` commit (`git log 16e9668a..fabe9e94 -- contracts/`):
- `fb29ed51` — the batched Phase 322 IMPL diff (USER-APPROVED): rake-free presale + coin-presale boxes,
  lootbox-boon unification (BURNIE-lootbox removal), Degenerette resolution gas + per-currency spin caps,
  universal claimable-pay, sDGNRS redemption accounting (ETH segregation + BURNIE flip-credit-at-submit),
  and the AfKing cancel-tombstone restore. Reconciled per manifest §2 (the single most critical point:
  `resolveRedemptionLootbox`'s final signature settles LOOT-03 boon flag + REDEEM-03 payable + no-claimable-debit).
- `269ce788` — Phase 323-03 test commit; the only `contracts/` touch is the `contracts/test/SettleClaimableShortfallTester.sol` helper (non-mainnet).
- `fabe9e94` — the USER-APPROVED Degenerette `resolveBets` post-game-over insolvency guard
  `if (_livenessTriggered()) revert E();` (`DegenerusGameDegeneretteModule.sol:421`); the frozen subject HEAD.

v47.0 is a contract-accounting/behavior bundle. It ships the full 9-section deliverable, `chmod 444` at close.

---

## 2. Executive Summary

### Closure Verdict Summary
v47.0 makes the game truly rake-free (removes the 20% presale vault skim + the 62% presale BURNIE bonus), replaces
the earlybird subsystem with credit-gated coin-presale boxes, removes the BURNIE-lootbox terminal-paradox, unifies
the 3 ETH lootbox callers to full boons+passes (10% haircut fixed), write-batches Degenerette `resolveBets`
(same-results) at per-currency spin caps (ETH 25 / BURNIE 15 / WWXRP 5), generalizes claimable-pay across ETH-input
paths, hard-segregates sDGNRS-redemption ETH + settles the BURNIE leg at submit (net mint 0), and restores the
AfKing in-place cancel-tombstone. The SC1 delta-audit + the SC2 3-skill adversarial sweep + the LEAN regression find
the change set sound **with TWO exceptions**: two Tier-1 MEDIUM findings (**F-47-01** presale closing-box DGNRS
windfall; **F-47-02** redemption submit ETH-empty fallback gap) — **both USER-adjudicated DEFER→v48.0** with fix
designs locked, keeping v47.0 SOURCE-TREE FROZEN at `fabe9e94`.

### Verdict Math
- **Adversarial sweep (Phase 324 SC2):** 15 deduplicated disposition rows — 13 NEGATIVE-VERIFIED / SAFE_BY_DESIGN /
  handoff-not-a-finding + **2 FINDING_CANDIDATE (both MEDIUM)**. 0 skeptic-filter discards. Two-tier consensus:
  2 Tier-1, 0 Tier-2 (for F-47-01 a second skill examined the mechanism and classed it SAFE on an inflation axis
  that does not refute the concentration concern — see §4.2).
- **Delta-audit (Phase 324 SC1):** every one of the 7 v47 work-item surfaces attests NON-WIDENING vs `16e9668a`
  with grep/diff anchors; the BURNIE-lootbox + earlybird kill-sets are grep-ZERO in mainnet code.
- **Regression:** NON-WIDENING; suite 598 pass / 38 fail / 16 skip (32 pre-existing-v46 byte-identical at `16e9668a`
  + 5 combined-run noise + 1 v47-PRESALE test-calibration delta); 0 v47 contract regressions vs the v46 565/45/16.

### Severity Counts
- CATASTROPHE 0 · HIGH 0 · **MEDIUM 2** (F-47-01 + F-47-02, both DEFERRED→v48) · LOW 0 · informational SAFE_BY_DESIGN 1.

### KI Gating Rubric Reference
KNOWN-ISSUES.md byte-unmodified vs v46 (§6). No KI promotion/demotion this milestone.

### Forward-Cite Closure Summary
Three forward items: (1) **H-CANCEL-SWAP-MISS** (the v46.0-deferred MEDIUM) is **RESOLVED-AT-V47** (§8); (2) **F-47-01**
presale closing-box windfall → v48 (`.planning/PLAN-V48-PRESALE-BOX-DRAIN-FIX.md`); (3) **F-47-02** redemption ETH-empty
stETH fallback → v48 (`.planning/PLAN-V48-REDEMPTION-ETH-STETH-FALLBACK.md`).

### Attestation Anchor
All `contracts/` file:line anchors herein are sourced from the Phase 324 workstream logs (324-01-DELTA-AUDIT,
324-02-ADVERSARIAL-LOG), each re-grep-verified by the orchestrator against the frozen subject `fabe9e94`
(`git diff fabe9e94 HEAD -- contracts/` empty).

---

## 3. Per-Phase Sections

- **§3a Phase 321 — SPEC (design-lock).** `779eacc3` — the locked v47.0 design across the 7 work items + the
  call-graph attestation (BATCH-01/02): shared-surface reconciliation per manifest §2, most critically the single
  `resolveRedemptionLootbox` final signature.
- **§3b Phase 322 — IMPL (the ONE batched contract diff).** `fb29ed51` (USER-APPROVED; VERIFICATION 6/6) + 4
  USER-directed refinements (burnForRedemption removal, AfKing didWork revert-fix, `_settleClaimableShortfall`
  helper, flipDay param removal). PRESALE-01..13 · LOOT-01..06 · DGAS-01..04 · CPAY-01..03 · REDEEM-01..07 ·
  DSPIN-01 · TOMB-01..03.
- **§3c Phase 323 — TST.** Repro-first (REDEEM-08 `269ce788`), same-results gas (DGAS-05/DSPIN-02 `39807240`/`b74ff527`),
  cancel-tombstone proofs (TOMB-04 `b47fc3e7`/`9b46403e`), solvency re-green + the §1 insolvency repro
  (`82520b4c`/`b9451eb0`). The phase surfaced a real MEDIUM insolvency (pre-existing `resolveBets` lacked a liveness
  guard) → USER-APPROVED one-line fix advanced the subject `fb29ed51`→`fabe9e94`; proven closed + bug-class swept
  (0 siblings). Baseline 598/38/16 NON-WIDENING.
- **§3d Phase 324 — TERMINAL.** This deliverable; SOURCE-TREE FROZEN at `fabe9e94`; the SC1 delta-audit + the SC2
  3-skill GENUINE PARALLEL_SUBAGENT sweep + the regression + the gated closure flip.

### §3.A Delta-Surface Table (folded from 324-01-DELTA-AUDIT.md §2)

| Surface | Requirements | Re-grepped anchors @ `fabe9e94` | Disposition |
| --- | --- | --- | --- |
| Rake-removal + presale-box | PRESALE-01..13 | 90/10 split (`MintModule:1030-1045`); `LOOTBOX_PRESALE_BURNIE_BONUS_BPS` grep 0; `presaleOver` latch (15); `PresaleBox` rename (43); presale box boon-less own-path (`LootboxModule:574`) | NON-WIDENING |
| Lootbox-boon unification | LOOT-01..06 | BURNIE-lootbox kill-set grep 0 mainnet (sole survivor = `contracts/test/` doc comment); `allowBoons`/`allowPasses` grep 0; `_resolveLootboxCommon` 3 callers | NON-WIDENING |
| Degenerette gas + liveness guard | DGAS-01..05 | DGAS-05 byte-identical (323-04); guard `:421`; per-betId lootbox / per-spin DGNRS | NON-WIDENING |
| Per-currency spin caps | DSPIN-01..02 | `MAX_SPINS_ETH=25`/`BURNIE=15`/`WWXRP=5` (`:226-228`); worst-case 485k/619k gas ≪ 30M | NON-WIDENING |
| Universal claimable-pay | CPAY-01..03 | 3 WhaleModule purchases + payable-entry sweep; `claimablePool == Σ claimableWinnings` (323-09 SolvencyObligations, 5 invariants GREEN) | NON-WIDENING |
| sDGNRS redemption | REDEEM-01..08 | `pullRedemptionReserve` (8); `redeemBurnieShare` (7); `pendingRedemptionBurnie`/`_payBurnie`/`RedemptionPeriod.flipDay` grep 0; `resolveRedemptionLootbox` Game-entry `payable` + unchecked debit removed | NON-WIDENING |
| AfKing cancel-tombstone | TOMB-01..05 | `setDailyQuantity(0)` in-place (`:463-467`), no `_removeFromSet`; 3 reclaim sites all in-sweep no-cursor-advance | NON-WIDENING |

### §3.B Composition Attestation Matrix (folded from 324-01 §3)
- **ADD×REMOVE:** earlybird emission subsystem grep-0; 1:1 swap to `presaleBoxCredit += 0.25·eth`; `Pool.Earlybird`→`Pool.PresaleBox` same 10%-of-supply allocation. NON-WIDENING.
- **claimable-balance:** `claimablePool == Σ claimableWinnings` across PRESALE-06 / CPAY / REDEEM (323-09 canonical obligation set, 5 invariants GREEN @256 runs). NON-WIDENING.
- **BURNIE-net-0:** `redeemBurnieShare` burns held + consumes stake → `creditFlip` = net new BURNIE 0; BURNIE→box path removed; BURNIE→tickets kept (ENF-01). NON-WIDENING.
- **RNG-freeze-intact:** presale box reuses committed word + `keccak256(rngWord,"PRESALE_BOX")` salt; Degenerette batch is bookkeeping-only post-outcome (DGAS-05). NON-WIDENING.

### §3.C Requirement Re-Attestation
All 45 v47.0 requirements (PRESALE 13 · LOOT 6 · DGAS 5 · CPAY 3 · REDEEM 8 · DSPIN 2 · TOMB 5 · BATCH 3) are
re-attested at closure. 43 NEGATIVE-VERIFIED/Complete. The two NEW findings attach to: **PRESALE-05/09** (the DGNRS
draw-rate vs the closing sweep — F-47-01) and **REDEEM-01/03** (the reservation's missing ETH→stETH fallback —
F-47-02); both are IMPL-as-specced but carry a v48 fix (the SPEC's calibration/edge-case assumptions did not fully
hold). The 5 TST requirements (DGAS-05, DSPIN-02, TOMB-04 Complete; REDEEM-08, TOMB-05 attested here at closure).

---

## 4. Adversarial-Pass Disposition (folded from 324-02-ADVERSARIAL-LOG.md)

### §4.1 Outcome
3-skill GENUINE PARALLEL_SUBAGENT sweep (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`; `/degen-skeptic`
OUT per D-271-ADVERSARIAL-02), run as 3 concurrent background Task spawns from the orchestrator. **15 deduplicated
disposition rows: 13 NEGATIVE-VERIFIED / SAFE_BY_DESIGN / handoff + 2 FINDING_CANDIDATE.** 0 skeptic-filter
self-discards; 0 orchestrator integration-time discards. The five primary charged-probe families (presale-snipe-set /
claimable / lootbox-paradox / redemption / tombstone) each have ≥1 row; the two v46-deferred/expected items confirm
resolved (H-CANCEL-SWAP-MISS cannot be re-triggered; the §1 Degenerette insolvency is closed by the `:421` guard).

### §4.2 The FINDING_CANDIDATEs (both MEDIUM, both DEFERRED→v48.0)

**F-47-01 — Presale closing-box over-distributes `Pool.PresaleBox` (~60% windfall to the closing buyer).**
The per-box DGNRS draw `(poolStart × tierTenths × amount)/(1000 × 1e18)` (`LootboxModule:720`) with the locked tier
curve `[3.0,2.5,2.0,1.5,1.0]` over 5×10-ETH tiers drains the 100B-DGNRS pool (`PRESALE_BOX_POOL_BPS=1000` = 10% of
supply) over 50 ETH **only if every box draws DGNRS** — but the resolution branch is 50% BURNIE / **40% DGNRS** /
10% WWXRP (`:644-676`) and the draw does not scale for the 40% hit-rate, so ~60% (~60B DGNRS ≈ 6% of supply) is swept
to the single closing buyer (`:678-693`). This contradicts the USER-locked design premise "the swept remainder is
dust, not a windfall" (`PLAN-PRESALE-COIN-BOXES-RAKE-FREE.md:85`). Severity MEDIUM (tokenomics misallocation — NOT
fund-loss/drain/inflation; the DGNRS is pre-minted + pool-bounded). `/economic-analyst` examined the same mechanism
and classified it SAFE on inflation/over-drain grounds (no mint; `transferFromPool` clamps to live balance) — correct
on that axis but does not refute the concentration concern; the elevation survives the dual-gate filter on the
distribution axis. **USER-adjudicated DEFER→v48.0; fix LOCKED = (a) scale the draw by the branch rate
(`_presaleBoxDgnrsReward` denominator `1_000`→`400`, `base=poolStart/40`).** `.planning/PLAN-V48-PRESALE-BOX-DRAIN-FIX.md`.

**F-47-02 — Gambling-burn redemption submit can brick under ETH-empty / stETH-inflated backing.**
`_submitGamblingClaimFrom` computes the ETH base against sDGNRS's FULL backing
(`ethBal + stethBal + claimable − pending`, `StakedDegenerusStonk.sol:844-848`), but `pullRedemptionReserve`
(`DegenerusGame.sol:1888-1899`) segregates the MAX-175% reservation from `claimableWinnings[SDGNRS]` ALONE, fail-closed,
with no fallback to sDGNRS's stETH/ETH balance. REDEEM-01 explicitly specs the fail-closed; what the probe surfaces is
the residual case where it bites. The original "stETH-dominant steady-state" framing was USER-corrected (stETH cannot
dominate pre-game-over and gambling burns are blocked post-game-over) — the genuine residual case is **mid-game ETH
depletion** (and a freely-transferable stETH donation that inflates the base; verified NOT a profit/inflation/underflow
exploit). Severity MEDIUM (liveness/availability; no funds at risk). **USER-adjudicated DEFER→v48.0; fix LOCKED =
reservation/payout uses pure-ETH OR pure-stETH (no mix), mid-game ETH→stETH fallback, revert if neither alone covers
the 175%, donation-robust (coverage matches the inflated asset basis).** `.planning/PLAN-V48-REDEMPTION-ETH-STETH-FALLBACK.md`.

### §4.3 SAFE_BY_DESIGN rows (informational)
- **Presale-box / lootbox shared-index RNG freeze** (hunter) — two domain-separated keccak draws off one committed word;
  opening order is outcome-neutral; `soldBefore` frozen into the record. Freeze invariant holds across request→unlock.

### §4.4 Skeptic-Reviewer Filter Attestation
Dual-gate filter (structural-protection check → 3-condition EV lens) applied per-skill self-arm + orchestrator
integration-time re-application. Both surviving candidates were independently code-verified by the orchestrator
(F-47-01: the `poolStart/100`-vs-40%-branch drain math + the `:678-693` live-balance sweep; F-47-02: the full-backing
base at `:846-848` vs the claimable-only checked pull at `Game:1888-1899`). The economist's SAFE classification of
F-47-01 was NOT taken as a discard (different threat axis — inflation, not concentration). No "tricked into approving"
actor modeled (per `open-e-operator-approval-trust-boundary`).

---

## 5. LEAN Regression Appendix (folded from 324-01 §4)

### §5a Suite Baseline — 598 / 38 / 16 NON-WIDENING vs v46 565 / 45 / 16
Every one of the 38 combined-run failures is classified — zero unexplained v47-delta: **32 PRE-EXISTING v46**
(byte-identical at `16e9668a`; the 0x11 ticket-queue + pending-pool cluster = a harness `block.timestamp` underflow +
an unmodeled 1% `_swapAndFreeze` pre-seed, NOT a v47 slot-shift) + **5 combined-run fuzz/cache noise** (pass isolated)
+ **1 v47-behavioral PRESALE delta** (§5b). The 5 solvency invariants 323-01/04 had listed as new-vs-v46 were proven
STALE-HARNESS and re-greened by 323-09's principled obligation-formula correction (`SolvencyObligations` helper).
ZERO v47 contract regressions.

### §5b REG-01-equivalent + handoff dispositions
`git diff 16e9668a..fabe9e94 -- contracts/ test/`: every hunk attributable to a known v47-scope change
(`fb29ed51` + `fabe9e94` + the AGENT-committed test repairs). `git diff fabe9e94 HEAD -- contracts/` empty. NON-WIDENING.
- **VRFLifecycle::test_vrfLifecycle_levelAdvancement** — a v47-PRESALE test-calibration delta (the v46-calibrated
  purchase volume no longer bootstraps to 50 ETH under the rake-free 90/10 split). Intended SPEC behavior, NOT a defect;
  recommended recalibration is a test-only note. Passes the economic skeptic-filter (does not elevate).
- **OBS-1** — pre-existing `DecimatorModule:394 vs :592` whale-remainder under-reservation (pre-game-over only;
  byte-identical at v46; outside the v47 surface). Carried forward descriptively; passes the skeptic-filter (does not elevate).

---

## 6. KI Gating Walk + KNOWN-ISSUES.md Re-Verification
- **KNOWN-ISSUES.md byte-unmodified** vs v46 (`git diff 16e9668a..fabe9e94 -- KNOWN-ISSUES.md` empty). No KI promotion/demotion.
- **RNG-freeze intact** — the presale-box draw is domain-separated off the committed word; the Degenerette write-batching
  touches only bookkeeping after outcomes are determined (DGAS-05 byte-identical); no new in-window VRF consumer.
- **Obligations conserved** — `claimablePool == Σ claimableWinnings` proven (323-09); BURNIE net mint 0 (REDEEM-05);
  `address(this).balance ≥ pendingRedemptionEthValue` maintained (REDEEM-08). Note: F-47-02's fail-closed pull is the
  intended solvency guard; the v48 fix preserves solvency while restoring liveness via the stETH fallback.

---

## 7. Prior-Artifact Cross-Cites
- **v47.0 phase artifacts:** Phase 321 SPEC (`779eacc3`); Phase 322 IMPL (`fb29ed51`, USER-APPROVED, 6/6 + 4 refinements);
  Phase 323 TST SUMMARYs (323-01/03/04/05/09 + the `fabe9e94` liveness guard + 323-SOLVENCY-FINDING + 323-BUGCLASS-SWEEP);
  Phase 324 logs (324-01-DELTA-AUDIT, 324-02-ADVERSARIAL-LOG + the 3 per-skill sweep outputs).
- **Prior milestone FINDINGS:** `audit/FINDINGS-v46.0.md` (9-section template + the H-CANCEL-SWAP-MISS forward-cite this
  milestone resolves); `audit/FINDINGS-v44.0.md` (9-section template).
- **Carry-forward anchors:** v46 closure signal `MILESTONE_V46_AT_HEAD_16e9668a…`; the v44 §9d maximalist handoff
  register (135 anchors — NOT live vectors).

---

## 8. Forward-Cite Closure
- **H-CANCEL-SWAP-MISS (v46.0-deferred MEDIUM) → RESOLVED-AT-V47.** v47 restored the SUB-07 in-place tombstone +
  added the in-sweep `dailyQuantity==0` reclaim branch (TOMB-01/02/03; `AfKing.sol:463-467` in-place, no `_removeFromSet`;
  3 reclaim sites all in-sweep no-cursor-advance). Empirically proven by 323-05 `testCancelBehindCursorDoesNotStrandPendingTail`
  + the Phase 324 tombstone-griefing probe (NEGATIVE-VERIFIED — the in-place tombstone relocates no one; cancel is self-only).
- **F-47-01 (presale closing-box DGNRS windfall, MEDIUM) → v48.0.** `.planning/PLAN-V48-PRESALE-BOX-DRAIN-FIX.md` (fix LOCKED = denominator 1000→400).
- **F-47-02 (redemption ETH-empty stETH-fallback gap, MEDIUM) → v48.0.** `.planning/PLAN-V48-REDEMPTION-ETH-STETH-FALLBACK.md` (fix LOCKED = pure-ETH/stETH fallback).
- **v48.0 descriptive seeds** (NOT live vectors): keeper-rename + VAULT-code (`PLAN-V48-KEEPER-RENAME-AND-VAULT-CODE.md`),
  gameover-burnie-tombstone (`PLAN-V48-GAMEOVER-BURNIE-TOMBSTONE.md`), sDGNRS far-future salvage swap
  (`PLAN-SDGNRS-FAR-FUTURE-SALVAGE-SWAP.md`).

---

## 9. Milestone Closure Attestation

### 9a. Closure Verdict

**Locked target (STATE.md "Closure verdict (target, Phase 324)", verbatim — for the record):**
`RAKE_FREE (20%_VAULT_SKIM + 62%_BURNIE_BONUS REMOVED); PRESALE_BOXES REPLACE EARLYBIRD (credit-gated, boon-less, 80/20, 50-ETH clamp-close + sweep + presaleOver latch); BURNIE_LOOTBOX REMOVED (terminal-paradox closed) + BURNIE→TICKETS KEPT; 3_ETH_LOOTBOX_CALLERS UNIFIED (full boons+passes, 10%-haircut fixed); DEGENERETTE_RESOLUTION WRITE-BATCHED SAME-RESULTS @ PER-CURRENCY_CAPS (ETH 25 / BURNIE 15 / WWXRP 5); UNIVERSAL_CLAIMABLE-PAY (claimablePool == Σ claimableWinnings BALANCED); SDGNRS_REDEMPTION_ETH HARD-SEGREGATED (underflow fixed) + BURNIE FLIP-CREDIT-AT-SUBMIT (BURNIE-cant-block-ETH; net mint 0); AFKING_CANCEL_TOMBSTONE RESTORED (H-CANCEL-SWAP-MISS RESOLVED_AT_V47); RNG_FREEZE_INTACT; 0 NEW_FINDINGS; KNOWN_ISSUES_UNMODIFIED`

**Amended actual verdict (the sweep surfaced 2 findings; both USER-adjudicated DEFER→v48.0 — the `0 NEW_FINDINGS` clause is amended accordingly, per the v46 §9a amended-verdict precedent):**
`RAKE_FREE (20%_VAULT_SKIM + 62%_BURNIE_BONUS REMOVED); PRESALE_BOXES REPLACE EARLYBIRD (credit-gated, boon-less, 80/20, 50-ETH clamp-close + sweep + presaleOver latch) [presale closing-box DGNRS over-distribution F-47-01 → v48.0]; BURNIE_LOOTBOX REMOVED (terminal-paradox closed) + BURNIE→TICKETS KEPT; 3_ETH_LOOTBOX_CALLERS UNIFIED (full boons+passes, 10%-haircut fixed); DEGENERETTE_RESOLUTION WRITE-BATCHED SAME-RESULTS @ PER-CURRENCY_CAPS (ETH 25 / BURNIE 15 / WWXRP 5); UNIVERSAL_CLAIMABLE-PAY (claimablePool == Σ claimableWinnings BALANCED); SDGNRS_REDEMPTION_ETH HARD-SEGREGATED (underflow fixed) + BURNIE FLIP-CREDIT-AT-SUBMIT (BURNIE-cant-block-ETH; net mint 0) [redemption submit ETH-empty stETH-fallback gap F-47-02 → v48.0]; AFKING_CANCEL_TOMBSTONE RESTORED (H-CANCEL-SWAP-MISS RESOLVED_AT_V47); RNG_FREEZE_INTACT; 2 MEDIUM FINDINGS (F-47-01 + F-47-02) DEFERRED→v48.0 [fix designs locked; SOURCE-TREE FROZEN held at fabe9e94]; KNOWN_ISSUES_UNMODIFIED`

The deviation from the locked target is the single `0 NEW_FINDINGS` → `2 MEDIUM FINDINGS … DEFERRED→v48.0` clause
(+ the two inline bracket annotations), a direct consequence of the USER adjudication. All other clauses hold verbatim.

### 9b. 4-Phase Wave Summary
Phase 321 (SPEC design-lock `779eacc3`) + 322 (IMPL `fb29ed51`, USER-APPROVED batched diff + 4 refinements) +
323 (TST — 5 plans + the `fabe9e94` liveness-guard mid-phase fix) + 324 (TERMINAL — this deliverable; SOURCE-TREE
FROZEN; SC1 delta-audit + SC2 3-skill sweep + regression + gated closure flip). Closure signal:
`MILESTONE_V47_AT_HEAD_da5c9d50989707c8964a9411e68c51ca1b1a25f2`.

### 9c. Closure Signal
**`MILESTONE_V47_AT_HEAD_da5c9d50989707c8964a9411e68c51ca1b1a25f2`** (resolved to the Phase 324 audit-deliverable
commit `da5c9d50` — the closure HEAD; contracts byte-identical to the frozen subject `fabe9e94`). Verbatim propagation targets (resolved at closure):
1. Frontmatter `closure_signal:` + `audit_subject_head:`.
2. §1 Audit Subject prose.
3. §9b / §9c references.
4. ROADMAP.md (v47.0 milestone flip).
5. STATE.md (Last Shipped Milestone) + MILESTONES.md (archive entry).

### 9d. Deferred to v48.0+ — Handoff Register
- **F-47-01** (MEDIUM) — presale closing-box DGNRS over-distribution → `.planning/PLAN-V48-PRESALE-BOX-DRAIN-FIX.md` (fix LOCKED: denominator 1000→400).
- **F-47-02** (MEDIUM) — redemption submit ETH-empty stETH-fallback gap → `.planning/PLAN-V48-REDEMPTION-ETH-STETH-FALLBACK.md` (fix LOCKED: pure-ETH/stETH, revert if neither, donation-robust).
- **v48.0 descriptive seeds** (carry, NOT live vectors): keeper-rename + VAULT-code; gameover-burnie-tombstone; sDGNRS far-future salvage swap.
- The v44 §9d maximalist handoff register (135 anchors) carries forward unchanged (NOT live vectors).

---

*v47.0 TERMINAL findings authored 2026-05-25. Source-tree frozen throughout (`git diff fabe9e94 HEAD -- contracts/` empty).
2 MEDIUM findings (F-47-01 + F-47-02) DEFERRED→v48.0 with fix designs locked; H-CANCEL-SWAP-MISS RESOLVED-AT-V47.
Closure signal resolves at the Phase 324 closure commit.*
