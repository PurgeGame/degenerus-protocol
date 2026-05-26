---
phase: 324-terminal-delta-audit-3-skill-adversarial-sweep-closure
plan: 02
milestone: v47.0
audit_subject_frozen_ref: fabe9e94
skills: [contract-auditor, zero-day-hunter, economic-analyst]
degen_skeptic: OUT (D-271-ADVERSARIAL-02)
execution_path: GENUINE PARALLEL_SUBAGENT (3 background Task spawns from the orchestrator)
deliverable: 324-02-ADVERSARIAL-LOG.md
outcome: 2 FINDING_CANDIDATE (both MEDIUM, both USER-adjudicated DEFER→v48, fix designs locked) + skeptic-filtered NEGATIVE/SAFE — v47.0 CLOSES with deferrals
---

# v47.0 SC2 Adversarial Sweep — Disposition Log

## CHARGE

- **Fixed 3-skill set:** `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`.
  `/degen-skeptic` is **OUT** (carried decision D-271-ADVERSARIAL-02, held through v44/v45/v46).
- **Audit subject (FROZEN):** `fabe9e94` (batched IMPL diff `fb29ed51` + the Degenerette `resolveBets`
  post-game-over liveness guard `DegeneretteModule:421`). Working-tree `contracts/` byte-identical
  (`git diff fabe9e94 HEAD -- contracts/` empty). Baseline v46.0 closure HEAD `16e9668a`.
- **Execution path:** **GENUINE PARALLEL_SUBAGENT** — the orchestrator (holding the Task tool) spawned
  all 3 skills as concurrent background subagents, each charged with its probe subset and reading the
  frozen source directly. (The v45 Phase 314 lesson: running the sweep inline in the orchestrator context
  enables true parallelism vs. the v44 HYBRID-fallback.)
- **SC2 charged probe set:** PRESALE (snipe / credit double-spend / box-RNG freeze / close-liveness);
  CLAIMABLE (invariant breakage); LOOTBOX (terminal-paradox closure); REDEMPTION (two-claimant underflow /
  BURNIE-cannot-block-ETH / conservation); TOMBSTONE (griefing — re-trigger H-CANCEL-SWAP-MISS).
- **Skeptic filter (mandatory dual-gate):** (1) structural-protection check; (2) 3-condition EV lens
  (positive-EV/harm-without-attacker · material magnitude · severity survives skeptical re-read). An
  elevation becomes a FINDING_CANDIDATE only if it survives BOTH gates (per-skill self-arm + orchestrator
  integration-time re-application).

---

## §1. Per-Skill Raw Disposition

### /contract-auditor (8 charged probes)
| Probe | Disposition |
|---|---|
| PRESALE SNIPE (closing-box pool sweep) | **FINDING_CANDIDATE (MEDIUM)** → F-47-01 |
| CREDIT DOUBLE-SPEND | NEGATIVE-VERIFIED (checked-before-unchecked consume; credit is a gate not a discount) |
| BOX-RNG FREEZE | NEGATIVE-VERIFIED (uncommitted index at buy; domain-separated draws; `soldBefore` frozen) |
| CLOSE-LIVENESS | NEGATIVE-VERIFIED (`PRESALE_BOX_MIN` on requested pre-clamp; exact-50 clamp; one-way `presaleOver`) |
| CLAIMABLE-INVARIANT | NEGATIVE-VERIFIED (`_settleClaimableShortfall` + `_creditBoxProceeds` net; `pullRedemptionReserve` paired debit) |
| REDEMPTION TWO-CLAIMANT | NEGATIVE-VERIFIED (CHECKED `claimableWinnings[SDGNRS] -= amount`; no 2^256 wrap; fail-closed) |
| BURNIE-CANNOT-BLOCK-ETH | NEGATIVE-VERIFIED (ETH leg before BURNIE leg; `base ≤ held+stake` by construction) |
| CONSERVATION | NEGATIVE-VERIFIED (net BURNIE mint 0; `balance ≥ pendingRedemptionEthValue` maintained) |

### /zero-day-hunter (4 charged probes + 1 beyond-charge)
| Probe | Disposition |
|---|---|
| TOMBSTONE GRIEFING (re-trigger H-CANCEL-SWAP-MISS) | NEGATIVE-VERIFIED (in-place tombstone; no-cursor-advance swap-pop; caller-scoped writes) |
| LOOTBOX TERMINAL-PARADOX CLOSURE | NEGATIVE-VERIFIED (no surviving BURNIE→future-ticket; presale box never `_queueTickets`; BURNIE Degenerette bet pays pure BURNIE) |
| BOX-RNG FREEZE COMPOSITION | SAFE_BY_DESIGN (two domain-separated draws off one committed word; opening order is outcome-neutral) |
| CROSS-SURFACE COMPOSITION (credit×claimable-pay / box×Degenerette-batch / cancel×funding) | NEGATIVE-VERIFIED (no theft/rake/double-spend) |
| **B1 (beyond-charge): redemption submit brick under stETH-dominant backing** | **FINDING_CANDIDATE (MEDIUM, liveness)** → F-47-02 |

### /economic-analyst (4 probes + 2 handoffs + 1 bonus)
| Probe | Disposition |
|---|---|
| PRESALE SNIPE / CREDIT-ACCRUAL EV | NEGATIVE-VERIFIED / SAFE_BY_DESIGN (credit -EV-in-hard-currency; finite pre-minted pool; clamp un-lockable) — **NOTE: examined the closing-box sweep on inflation/over-drain grounds (no mint, pool-bounded) but did NOT address distribution-concentration; see F-47-01 reconciliation** |
| CLAIMABLE-PAY CONSERVATION | NEGATIVE-VERIFIED (strict 1-wei sentinel paired debit at all 5 callers; box nets to `freshUsed`) |
| REDEMPTION CONSERVATION | NEGATIVE-VERIFIED (net BURNIE 0; `balance ≥ pendingRedemptionEthValue` by physical segregation; "sDGNRS is the house" -EV preserved) |
| TOMBSTONE GRIEFING EV | NEGATIVE-VERIFIED (in-place sentinel; self-only cancel; no positive-EV griefing) |
| VRFLifecycle recalibration (handoff) | CONFIRMED INTENDED — test-calibration delta (rake-removal SPEC), NOT a contract defect |
| OBS-1 Decimator under-reservation (handoff) | CONFIRMED PRE-EXISTING — `git diff 16e9668a fabe9e94 -- DecimatorModule.sol` EMPTY; outside v47 surface; carry-forward descriptively |
| Degenerette gas/caps (bonus) | NEGATIVE-VERIFIED (EV-neutral; additive batching; caps are variance limits) |

---

## §2. Per-Probe Disposition Table

| Probe ID | Skill | Surface | Disposition | Skeptic-filter | Tier |
|---|---|---|---|---|---|
| P-PRESALE-SNIPE | auditor | presale closing-box sweep | **FINDING_CANDIDATE** | survives both gates | 1 |
| P-PRESALE-CREDIT | auditor + economist | presale credit accrual/consume | NEGATIVE-VERIFIED | n/a | — |
| P-BOX-RNG | auditor + hunter | presale-box/lootbox shared-index draw | NEGATIVE-VERIFIED / SAFE_BY_DESIGN | n/a | — |
| P-CLOSE-LIVE | auditor | 50-ETH clamp-close | NEGATIVE-VERIFIED | n/a | — |
| P-CLAIMABLE-INV | auditor + economist | `claimablePool == Σ claimableWinnings` | NEGATIVE-VERIFIED | n/a | — |
| P-LOOT-PARADOX | hunter | BURNIE→future-ticket terminal paradox | NEGATIVE-VERIFIED | n/a | — |
| P-REDEEM-2CLAIM | auditor | two-claimant `[SDGNRS]` underflow | NEGATIVE-VERIFIED | n/a | — |
| P-REDEEM-BURNIE-BLOCK | auditor + economist | BURNIE-cannot-block-ETH | NEGATIVE-VERIFIED | n/a | — |
| P-REDEEM-CONSV | auditor + economist | BURNIE-net-0 + balance≥pending | NEGATIVE-VERIFIED | n/a | — |
| P-REDEEM-BRICK (B1) | hunter | stETH-dominant submit brick | **FINDING_CANDIDATE** | survives both gates | 1 |
| P-TOMB-GRIEF | hunter + economist | cancel-tombstone griefing | NEGATIVE-VERIFIED | n/a | — |
| P-XSURFACE | hunter | new-surface compositions | NEGATIVE-VERIFIED | n/a | — |
| P-DGAS-EV | economist | Degenerette batch EV | NEGATIVE-VERIFIED | n/a | — |
| H-VRFLIFE | economist | VRFLifecycle test | INTENDED (handoff; not a finding) | does not elevate | — |
| H-OBS-1 | economist | Decimator under-reservation | PRE-EXISTING (handoff; not a finding) | does not elevate | — |

---

## §3. Outcome Summary

- **15 disposition rows** (deduplicated by probe across skills): **13 NEGATIVE-VERIFIED / SAFE_BY_DESIGN /
  handoff-not-a-finding + 2 FINDING_CANDIDATE (both MEDIUM)**.
- **2 FINDING_CANDIDATE survive the dual-gate skeptic filter** → routed to 324-03/324-04 for USER
  adjudication (NOT auto-fixed; subject FROZEN at `fabe9e94`).
- **Both Tier-1** (single-skill elevation). Neither is a Tier-2 multi-skill consensus elevation. (For
  F-47-01 a second skill — the economist — examined the same mechanism and classified it SAFE on
  *inflation/over-drain* grounds; that does not refute the *distribution-concentration* concern — see §4.1.)
- The 5 primary charged-probe families (presale-snipe-set / claimable / lootbox-paradox / redemption / tombstone)
  each have ≥1 disposition row. The two v46-deferred/expected items are confirmed resolved: H-CANCEL-SWAP-MISS
  cannot be re-triggered (TOMBSTONE NEGATIVE-VERIFIED, 323-05 proof); the §1 Degenerette insolvency is closed
  by the `:421` guard.

---

## §4. FINDING_CANDIDATE Write-ups

### §4.1 F-47-01 — Presale closing-box over-distributes `Pool.PresaleBox` (~60% windfall to the closing buyer)
**Severity:** MEDIUM (tokenomics misallocation / fairness; NOT fund-loss, NOT protocol-ETH drain, NOT inflation —
all DGNRS is pre-minted and pool-bounded). **Skill:** /contract-auditor. **Tier:** 1.

**Location:** `DegenerusGameLootboxModule.sol:678-693` (closing sweep, reads live `poolBalance`),
`:644-676` (50/40/10 branch), `:705-727` `_presaleBoxDgnrsReward` (poolStart-relative draw, formula `:720`).
Pool sizing `StakedDegenerusStonk.sol:294/352/374` (`PRESALE_BOX_POOL_BPS=1000` → 10% of `INITIAL_SUPPLY`
= 100B DGNRS).

**Mechanism (verified against the frozen source + the design doc):** the per-box DGNRS draw is
`(poolStart × tierTenths × amount) / (1000 × 1e18)`, and the USER-locked tier curve `[3.0,2.5,2.0,1.5,1.0]`
over 5×10-ETH tiers sums to `100 × base = poolStart` — i.e. the pool drains exactly over 50 ETH **only if
every box draws DGNRS**. But the resolution branch is **50% BURNIE / 40% DGNRS / 10% WWXRP** (`:644-676`)
and the draw formula does NOT scale up for the 40% hit-rate. So in expectation only ~40% of the 100B pool
drains across box buyers; the remaining **~60B DGNRS (≈6% of total supply)** is swept to the single closing
buyer (`:678-693`, regardless of roll outcome).

**Why it survives the skeptic filter:** (1) Structural-protection — NONE; the draw is calibrated for a 100%
branch rate that never occurs, and nothing scales it to the realized 40%. A buyer can deliberately position
to be the closing buyer (clamp lands exactly at 50) and capture the residual for a small closing-box cost.
(2) EV — (a) positive-EV and manifests even under honest play (whoever closes gets it); (b) material (~60% of
a 10%-of-supply emission pool to one address); (c) survives re-read — it **directly contradicts the USER-locked
design premise** `PLAN-PRESALE-COIN-BOXES-RAKE-FREE.md:85` *"the swept remainder is **dust, not a windfall**"*
and the doc's own *"VERIFY at IMPL that the clamped final tier + sweep zeroes the pool"* gate (which did not hold).

**Economist reconciliation:** /economic-analyst classified the same mechanism SAFE_BY_DESIGN — correctly, on
the grounds that no DGNRS is minted/over-drained (the pool is finite + `transferFromPool` clamps to live balance).
That defeats an *inflation/insolvency* framing but NOT the *concentration/fairness* framing: the bulk of a
fair-launch emission concentrating to one address while the design assumed even front-loaded distribution.

**USER adjudication (2026-05-25): DEFER → v48.0** (the v46→v47 H-CANCEL-SWAP-MISS DEFER precedent).
*"the dgnrs should be mostly paid out at the end, not a big windfall to the closer."* The DGNRS pool must
drain ~fully across box buyers by the close, leaving only dust to sweep. **Fix mechanism LOCKED (USER 2026-05-25)
= (a) scale the per-box draw by the branch rate:** change `_presaleBoxDgnrsReward`'s denominator from
`(1_000 * 1 ether)` to `(400 * 1 ether)` — i.e. `base = poolStart/40` instead of `/100`, so each DGNRS draw is
2.5× larger and the realized ~40% DGNRS branch rate drains the full pool over 50 ETH in expectation; the closing
sweep then mops up only variance dust (`transferFromPool` already clamps to live balance, so a run of early
DGNRS hits can't over-draw). The fix is a v48.0 contract change (subject frozen at `fabe9e94`; v47.0 closes now
with this DEFERRED, carried into v48.0's plans).

### §4.2 F-47-02 — Gambling-burn redemption submit can brick under stETH-dominant sDGNRS backing
**Severity:** MEDIUM (liveness / availability; NO funds at risk — fail-closed protects solvency).
**Skill:** /zero-day-hunter (beyond-charge B1). **Tier:** 1.

**Location:** `StakedDegenerusStonk.sol:844-887` (`_submitGamblingClaimFrom` base + `maxIncrement` + pull),
`DegenerusGame.sol:1888-1899` (`pullRedemptionReserve`, CHECKED debit from `claimableWinnings[SDGNRS]` alone).

**Mechanism (verified against the frozen source):** the proportional ETH base is computed against sDGNRS's
**FULL** backing — `totalMoney = ethBal + stethBal + claimableEth − pendingRedemptionEthValue`,
`ethValueOwed = totalMoney × amount / supplyBefore` (`:846-848`). The MAX-175% reservation `maxIncrement`
(≈ `1.75 × base`) is then pulled by `pullRedemptionReserve`, which does a CHECKED `claimableWinnings[SDGNRS]
-= amount` (reverts on underflow, fail-closed) with **no fallback to sDGNRS's stETH/ETH balance** and no
claimable refill. Because sDGNRS's principal reserve is stETH (yield accrual) while `claimableWinnings[SDGNRS]`
is only the accumulated-unswept yield-surplus share (≈23%, `JackpotModule:720`) + box 20%-shares — and
deterministic burns lazily convert claimable→balance — the claimable bucket is structurally a minority of
backing in steady state. Whenever `1.75 × ethValueOwed > claimableWinnings[SDGNRS]`, the submit reverts,
which can be far below the nominal 50%-supply/day cap.

**Why it survives the per-skill skeptic filter (as reported):** the hunter argued (1) no structural path
moves stETH/balance into `claimableWinnings[SDGNRS]`; (2) harm manifests organically as stETH yield accrues
and the claimable bucket becomes a minority of backing. REDEEM-01 **explicitly** specs "Revert the burn if the
full 175% can't segregate (fail-closed)" — so the fail-closed itself is intended; what the probe surfaced is
the magnitude consequence + a test-coverage gap (`RedemptionAccounting.t.sol:490` funds sDGNRS exclusively
through `claimableWinnings[SDGNRS]`, never exercising the ETH-poor case).

**USER threat-model correction (2026-05-25):** the hunter's "normal steady-state" prevalence is WRONG —
sDGNRS backing **cannot be stETH-dominant before game-over**, and **after game-over gambling burns are blocked**
(the liveness gate), so the stETH-dominant + active-gambling-burn co-occurrence the hunter posited does not arise
in normal operation. The *mechanism* (175% reservation pulled from `claimableWinnings[SDGNRS]` alone, no
stETH/ETH-balance fallback) is real, but the genuine residual case is narrower: **mid-game ETH depletion** — if
the game's ETH runs out while it is still live, the ETH-side reservation/payout has no fallback and the submit
bricks. Net: F-47-02 is re-scoped from "steady-state brick" to "ETH-empty fallback gap" — still a real, bounded
liveness gap worth fixing.

**USER adjudication (2026-05-25): DEFER → v48.0.** *"if the game ran out of eth we need to consider that
situation … we need a fallback case where we are using stETH for all that stuff if eth was empty."* → add a
deterministic ETH→stETH fallback for the redemption reservation/payout when the game's ETH is empty mid-game
(extending the existing game-over ETH→stETH fallback, REDEEM-04, to the mid-game ETH-depletion case). **Fix
shape LOCKED (USER 2026-05-25):** the reservation/payout uses **either pure ETH OR pure stETH** (no mix — keeps
the math simple); **revert if neither alone can cover** the 175% (the "neither covers" case is not realistic,
fail-closed there is fine). The v48 fix is a contract change (subject frozen at `fabe9e94`; v47.0 closes now
with this DEFERRED, carried into v48.0's plans). Add a test that funds sDGNRS ETH-poor / stETH-only.

**Donation-robustness requirement (USER question 2026-05-25):** the redemption base reads raw
`address(this).balance + steth.balanceOf(this) + claimable[SDGNRS] − pending` (sStonk:844-847). ETH `receive()`
is `onlyGame` (`:433`) so casual ETH donations revert (only `selfdestruct` force-feed bypasses it), but **stETH is
freely transferable in** (ERC-20, no hook). A donation inflates the base → inflates the 175% reservation. Verified
this is NOT a profit/inflation/underflow exploit (donation is -EV to the donor; `depositSteth` mints no shares so no
ERC-4626 inflation attack; genesis-minted supply never near 0; checked subtraction), BUT a stETH donation under the
current claimable-ETH-only pull can brick a submit (the F-47-02 mechanism). The fix MUST check coverage against the
**same asset basis it inflates** (so a stETH-inflated base is covered by the pure-stETH leg) — do NOT reintroduce a
claimable-ETH-only chokepoint. Add a test: donate stETH, then submit, assert the stETH leg covers (no brick).

---

## §5. Skeptic-Reviewer Filter Attestation

The dual-gate filter (structural-protection check → 3-condition EV lens) was applied at two layers: per-skill
self-arm (each subagent ran the filter before reporting), and orchestrator integration-time re-application
(every elevation re-verified against the frozen source by the orchestrator). **0 self-discards** at the orchestrator
layer — both surviving candidates were independently code-verified (F-47-01: the `poolStart/100`-vs-40%-branch
drain math + the `:678-693` live-balance sweep; F-47-02: the full-backing base at `:846-848` vs the
claimable-only checked pull at `Game:1888-1899`). The economist's SAFE classification of the closing-box sweep
was NOT taken as a discard of F-47-01 — it addresses a different threat axis (inflation, not concentration).
No "tricked into approving" actor was modeled (per `open-e-operator-approval-trust-boundary`). `/degen-skeptic`
remained OUT per D-271-ADVERSARIAL-02.

---

## §6. Routing

Both FINDING_CANDIDATEs are recorded WITHOUT a contract fix in this phase (subject FROZEN at `fabe9e94`).
**Both are USER-adjudicated DEFER → v48.0 (2026-05-25), with fix designs LOCKED:**
- **F-47-01 (presale closing-box windfall):** DEFER→v48; fix = (a) scale the per-box DGNRS draw by the branch rate (`_presaleBoxDgnrsReward` denominator `1_000`→`400`, i.e. `base=poolStart/40`) so the realized ~40% DGNRS rate drains the pool, dust to the closer.
- **F-47-02 (redemption ETH-empty fallback):** DEFER→v48; fix = pure-ETH-OR-pure-stETH reservation/payout, mid-game ETH→stETH fallback, revert if neither covers, donation-robust (coverage matches inflated asset basis).

Consequence: **v47.0 CLOSES now** with both findings DEFERRED→v48 (the v46→v47 H-CANCEL-SWAP-MISS DEFER precedent;
the §9a "0 NEW_FINDINGS" verdict clause is amended to "2 MEDIUM FINDINGS DEFERRED→v48 [fix designs locked]").
Phase 324 SC1 (delta-audit) + SC2 (this sweep) complete; SC3 findings + SC4 closure proceed. The two fixes are
carried into v48.0's plans (`.planning/PLAN-V48-PRESALE-BOX-DRAIN-FIX.md` + `.planning/PLAN-V48-REDEMPTION-ETH-STETH-FALLBACK.md`).
`git diff fabe9e94 HEAD -- contracts/` is empty (read-only sweep throughout; subject stays frozen at `fabe9e94`).

*SC2 adversarial sweep authored 2026-05-25. GENUINE PARALLEL_SUBAGENT (3 background Task spawns). Read-only; subject frozen at `fabe9e94`.*
