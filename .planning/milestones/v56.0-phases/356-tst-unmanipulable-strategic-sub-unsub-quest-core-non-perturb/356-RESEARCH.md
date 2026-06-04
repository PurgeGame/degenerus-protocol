# Phase 356: TST — Unmanipulable + Quest-Core Non-Perturbation + Two-Path-Open + Liveness Valve + Gap-Decouple + Gas Marginals + Non-Widening - Research

**Researched:** 2026-06-02
**Domain:** Solidity security-audit TEST authoring (Foundry forge) against a byte-frozen contract subject — fuzz + named-repro + gas-ceiling proofs + the NON-WIDENING regression ledger
**Confidence:** HIGH (codebase-internal; every claim below is verified against the shipped contract source at HEAD or the existing test corpus — no external/library research applies)

## Summary

Phase 356 is the v56.0 empirical TST gate: prove the afking redesign behaviorally correct and the hard security floor (SEC-01 unmanipulable, esp. strategic sub/unsub; SEC-02 SOLVENCY-01 byte-unchanged + RNG-freeze intact), plus the two USER liveness adds (LIVE-01 `openBoxes` valve, GAS-06 gap/jackpot decouple), and the per-tx 16.7M ceiling — all as forge tests against the v55 frozen baseline `453f8073`. **Test-only: zero `contracts/*.sol` mutation** (`git diff 453f8073 HEAD -- contracts/` shows the v56 IMPL diff is committed and frozen; 356 adds nothing to it).

The single most important grounding fact is confirmed in the source: the afking streak is **compute-on-read** (`GameAfkingModule._afkingStreak`, lines 778-786: `if (currentDay == 0 || covered + 1 < currentDay) return 0;` — decay-on-read; else `base + (covered - afkingStartDay)`). There is **no settle day, no `SETTLE_PERIOD` streak write, no two-batch split** in the shipped code (`SETTLE_PERIOD` survives only as a harness-local warp helper). The reward is a per-day `pendingBurnie` accrual pulled via the permissionless `claimAfkingBurnie(address[])` (CEI: `s.pendingBurnie = 0` precedes `coinflip.creditFlip`, line 1277). The STAGE uses a single weighted budget `SUB_STAGE_WEIGHT_BUDGET = 1000` (lootbox=1 / ticket=8 / evict=2). The "per-settle marginal" wording in ROADMAP/REQUIREMENTS is stale — do not plan tests against a settle-day design.

**Primary recommendation:** Author all new proofs in Foundry forge (per D-11). EXTEND `test/gas/V56AfkingGasMarginal.t.sol` for the per-tx gap-resume / GAS-06 / LIVE-01 / regression-lock cases; ADAPT the three v55 fuzz proofs (`V55FreezeDeterminism`, `V55RevertFreeEvCap`, `V55SetMutationOpenE`) into v56 successors for the SEC-01/02 fuzz+repro; MIGRATE the 10 stale-offset fuzz files (`OFF_LASTBOUGHT 21/uint32 → 11/uint24`) via the exact mechanical transform already applied to the gas suites in `08e59a4a`; build `REGRESSION-BASELINE-v56.md` by empirically checking out `453f8073` and running its full tree for the red union BY NAME. **Two harness bugs found that the planner must fix** — see Common Pitfalls.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01 (method):** Prove SEC-01 with BOTH stateful property-fuzz invariants AND named repro tests. Fuzz drives random `sub`/`unsub`/`buy`/`claim`/`open` sequences asserting global invariants (no churn sequence increases total credited BURNIE/affiliate beyond honest continuous play; effective streak never exceeds the funded-delivered-day span). Named repros anchor each designed-against vector. Matches the v55 fuzz+repro pattern.
- **D-02 (named repro set — ALL FOUR required):**
  1. **Affiliate re-claim churn** — sub → accrue `affiliateBase` → unsub → re-sub repeatedly: prove total credited to uplines EQUALS honest continuous-sub accrual. `affiliateBase` persists across unsub (NOT flushed on mutation) → forfeit-nothing-gain-nothing.
  2. **Streak decay / gap dodge** — miss ONE funded day → effective streak reads 0 (decay-on-read, `afkCovered + 1 < currentDay` → 0); resume after a gap → `afkingStartDay`/`streakAtAfkingStart` reset on the delivered day; per-window streak advances ONLY on debit-DELIVERED days (C3-a non-funded dodge stays closed).
  3. **pendingBurnie double-claim idempotency** — `claimAfkingBurnie` double-call in one block / re-entrancy / claim→unsub→claim pays the accrued balance EXACTLY ONCE, zeroed CEI-before-credit (`s.pendingBurnie = 0` precedes `creditFlip`, `GameAfkingModule.sol:1277`).
  4. **4 finalize hooks before slot-delete** — each sub-ending path (explicit cancel `subscribe(_,0)`; cancel-reclaim that DELETES `_subOf`; pass-eviction crossing; funding-kill) writes the decay-applied final streak to `DegenerusQuests` BEFORE the slot is deleted (`_finalizeAfking`, load-bearing ordering); funding-kill zeroes ONLY if a full prior day was missed with NO valid mint (afking OR manual).
- **D-03 (accepted-by-design):** the first-sub-only `+0..+9` `+daysToNextSettle` head-start (QST-02) is USER-ACCEPTED-BY-DESIGN — treat as accepted; do NOT flag as a missed control.
- **D-04 (QST-04, full empirical coverage in 356):** prove non-perturbation EMPIRICALLY:
  - slot-1 (player's own random/manual quest) stays FULLY ACCESSIBLE every day during afking and is STREAK-NEUTRAL (a slot-1 completion during afking must NOT advance the afking compute-on-read streak — `afkingActive` flag gates it). For a NON-afking player, slot-1 advances the streak normally.
  - manual / bingo / degenerette / boon callers (`awardQuestStreakBonus`, etc.) produce byte-identical results with afking subs present vs absent.
- **D-05 (SEC-02, three legs):** (1) ETH/`claimablePool` debit path byte-unchanged vs `453f8073` (grep/diff anchor in the ledger); (2) solvency invariant fuzz (`balance + steth.balanceOf(this) >= claimablePool` across churn/accrue/claim); (3) RNG-freeze determinism fuzz (subscribe min-buy STAMPS for-later-open and NEVER inline-resolves pre-RNG; single-roll open; `pendingBurnie` credit consume ONLY the frozen day-word).
- **D-06 (per-advance ceiling proof):** forge harness driving a worst-case multi-day VRF-stall resume asserting EACH `advanceGame` tx is `< 16,777,216` INDIVIDUALLY — the gap-backfill advance N AND the jackpot-paying advance N+1. ALSO empirically pin the proof's 4 named residuals.
- **D-07 (decouple regression — full idempotent-resume invariants):** advance N sets `STAGE_GAP_BACKFILLED` + pays NO jackpot; advance N+1 pays the day's jackpot with the SAME frozen word; `rngGate` returns `gapDays == 0` on re-entry; `dailyIdx` NOT advanced so `advanceDue()` stays true; `purchaseStartDay` bumped EXACTLY ONCE; no double jackpot, no skipped day.
- **D-08 (LIVE-01):** prove drain + bound + coexist + byte-unchanged: bounded `openBoxes(maxCount)` chunks each `< 16.7M`; repeated bounded calls fully DRAIN backlog of EITHER box type (both cursors advance); afking-first-then-human ordering; two-path coexistence (no shared-mutable-state hazard, `lastOpenedDay` monotone no-double-open); individual `openLootBox(player,index)` + the rewarded `mintBurnie` open path byte-unchanged; `drainAfkingBoxes` reachable ONLY via the `openBoxes` delegatecall.
- **D-09 (gas regression-lock posture):** re-assert GAS-01..04 wins as regression locks against a recorded LOOSE bound (a ceiling, not a brittle exact number). EXTEND `V56AfkingGasMarginal.t.sol` (+ `KeeperOpenBoxWorstCaseGas.t.sol`), do not author a new suite.
- **D-10 (fuzz-offset migration — MIGRATE ALL):** the 10 `test/fuzz/` files still at stale `OFF_LASTBOUGHT = 21`/uint32 are ALL migrated to `11`/uint24 + the re-packed 13-field Sub layout, the SAME fix already applied to the gas suites in `08e59a4a`. Removes false-green risk; makes the ledger legible (red→green is NARROWING).
- **D-11 (framework + baseline anchoring):** new v56 proofs in Foundry forge. `REGRESSION-BASELINE-v56.md` anchored by empirically checking out `453f8073` and running its FULL tree for the baseline-red union BY NAME (same method v55 used off `20ca1f79`). Binding headline: "by NAME, never a bare count" — at the v56 TST HEAD, live `forge test` failing set − the `453f8073` baseline red union == ∅. Enumerate BOTH forge AND hardhat suites. Offset-migration red→green deltas recorded as NARROWING.

### Claude's Discretion
- D-10 and D-11 above were the two "unselected gray areas" — defaults are now locked (migrate all; forge + empirical-checkout baseline). No further discretion areas remain open.

### Deferred Ideas (OUT OF SCOPE)
- The 3-skill genuine-PARALLEL adversarial sweep + XMODEL Codex/Gemini cross-model close + delta-audit + `audit/FINDINGS-v56.0.md` + the closure flip → **Phase 357 / AUDIT-01**.
- The v50/v51/v52 consolidated cross-model audit debt → the separate v52 track.
- The O1 lootbox-quest double-credit was FIXED in the v56 IMPL — not a 356 open item; its single-credit regression is covered by the quest-core non-perturbation + solvency fuzz.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SEC-01 | The afking system (buy + open) is unmanipulable — no positive-EV from settle-timing, strategic sub/unsub churn (PRIMARY concern), re-rate-on-alteration, pre-credit-EV inflation, double-credit, open-timing, settle-griefing. | The 4 finalize paths + the CEI claim + the persist-on-unsub `affiliateBase`/`pendingBurnie` are all read out below from the shipped source; the v55 fuzz+repro corpus (`V55RevertFreeEvCap`, `V55SetMutationOpenE`) is the closest analog to adapt. |
| SEC-02 | SOLVENCY-01 untouched (ETH/`claimablePool` debit byte-unchanged), RNG-freeze intact under the new accrual/settle. | The debit site is byte-frozen at `GameAfkingModule._deliverAfkingBuy` (the v55 SOLVENCY-01 site); RNG-freeze surface is the subscribe min-buy STAMP-not-resolve + single-roll open + `rngWordByDay[stampDay]` seed. Adapt `V55FreezeDeterminism`. |
| LIVE-01 | `openBoxes(uint256 maxCount)` valve (commit `86a2d6c8`) clears any backlog of EITHER box type in <16.7M chunks, afking-first-then-human, permissionless, both cursors advance; individual `openLootBox` + `mintBurnie` byte-unchanged; `drainAfkingBoxes` only via the `openBoxes` delegatecall. | `DegenerusGame.openBoxes` (line 1800) + `_openHumanBoxes` (1829) + `GameAfkingModule.drainAfkingBoxes` (1234) → `_autoOpen` read out below; distinct selectors confirmed (no autoOpen collision — the dead `autoOpen` was dropped in `86a2d6c8`). |
| GAS-06 | The gap-backfill / daily-jackpot decouple (commit `3d969621`) keeps EACH `advanceGame` tx < 16.7M under a multi-day VRF-stall resume. Verify per-advance (not just the 25M total) + a gap→defer→next-pays regression. | `DegenerusGameAdvanceModule` lines 361-372 (the `if (gapDays != 0) { stage = STAGE_GAP_BACKFILLED; break; }` decouple) + `rngGate` idempotency (1262-1321) read out below. |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Strategic sub/unsub unmanipulability (SEC-01) | Game / `GameAfkingModule` (Sub slot) | `DegenerusQuests` (streak finalize) | The afking economic state (`affiliateBase`, `pendingBurnie`, the compute-on-read streak markers) lives in the Sub slot; the finalize writes the streak back across the contract boundary. |
| SOLVENCY-01 debit + RNG-freeze (SEC-02) | Game / `GameAfkingModule._deliverAfkingBuy` | `DegenerusGameAdvanceModule` (rngGate freeze) | The ETH/`claimablePool` debit is a single in-context site; the freeze invariant is the STAGE-runs-pre-RNG ordering + `rngWordByDay` seed. |
| Two-path box open + valve (LIVE-01) | Game / `openBoxes` dispatch | `GameAfkingModule.drainAfkingBoxes` + `DegenerusGame._openHumanBoxes` | The valve is a Game entrypoint delegatecalling the afking module then walking human boxes in-context. |
| Per-tx gap/jackpot decouple (GAS-06) | `DegenerusGameAdvanceModule.advanceGame`/`rngGate` | — | The advance chain is the only protocol-FORCED multi-loop path; the decouple lives entirely in the advance state machine. |
| The NON-WIDENING ledger | `test/` + `.planning/` (markdown) | — | A doc-only artifact recording the empirical whole-tree run; touches no contract. |

## Standard Stack

No external libraries to install. This is a codebase-internal test phase. The "stack" is the existing test toolchain and the shipped contract surface under test.

### Core (the toolchain)
| Component | Version / Identity | Purpose | Why Standard |
|-----------|--------------------|---------|--------------|
| Foundry `forge` | repo-pinned (see `foundry.toml`) | Authoring + running the v56 fuzz / repro / gas / per-tx-ceiling proofs | D-11: the security/fuzz/freeze/gas properties are forge-native; the V56 harness + fuzz corpus + gas suites are all forge. |
| `forge-std` (`VmSafe`, `Vm`, `StdInvariant`) | repo-vendored under `lib/` | `vm.snapshotState`/`vm.revertToState`, `vm.load`/`vm.store` Sub-slot probing, `vm.warp`, fuzz cheats | Already used verbatim by `V56AfkingGasMarginal` + every v55 proof. |
| `scripts/lib/patchForFoundry.js` | repo script (confirmed present) | Predicts the CREATE addresses (no pretest hook) before a whole-tree `forge test`; restore `ContractAddresses.sol` after | The v55 ledger ran exactly this: patch → `forge test --json` → restore. |
| Hardhat (`npx hardhat compile`) | repo-pinned | The sanity arm of the NON-WIDENING ledger (compile EXIT 0 + byte-identity), NOT the primary BY-NAME ledger | v55 §7a: the redesign is Solidity-internal, blast radius is the forge afking module + shared fixture. |
| `DeployProtocol.sol` (`test/fuzz/helpers/`) | repo fixture | The live deploy fixture every forge proof inherits (`game`, `mockVRF`, the VRF drain helpers) | All v55/v56 forge proofs extend it. |

### Supporting (the v56 contract surface under test — read, do not edit)
| Surface | File:Line | What it is | Used by |
|---------|-----------|-----------|---------|
| `subscribe(player, drainFirst, useTickets, dailyQuantity, reinvestPct, fundingSource)` payable | `GameAfkingModule.sol:255` | Sub create/replace/cancel; `dailyQuantity == 0` is the explicit cancel; FREEZE-01 blocks during rngLock | SEC-01 churn repro, finalize-path repro |
| `_finalizeAfking(player, sub, currentDay)` | `GameAfkingModule.sol:799` | Computes `earned = streakBase + (afkCovered - afkingStartDay)`, calls `quests.finalizeAfking(...)`, then zeroes `afkingStartDay` + streak base | The single finalize hook all 4 ending paths call |
| `processSubscriberStage(processDay, weightBudget)` | `GameAfkingModule.sol:860` | The weighted STAGE chunker — the no-orphan guard, the 4 in-stage ending branches, the buy+debit+accrue | SEC-01 fuzz, GAS-03 chunk |
| `claimAfkingBurnie(address[] subs)` | `GameAfkingModule.sol:1270` | Permissionless pull; CEI zero-before-credit at `:1277` | SEC-01 idempotency repro |
| `drainAfkingBoxes(uint256 count)` returns(opened) | `GameAfkingModule.sol:1234` → `_autoOpen` | The afking-side cursor walk; reached ONLY via the `openBoxes` delegatecall | LIVE-01 |
| `mintBurnie()` | `GameAfkingModule.sol:1193` | The rewarded one-category router (advance → afking-open); `_autoOpen(OPEN_BATCH)` + one CEI-last bounty `creditFlip` | LIVE-01 (byte-unchanged), per-open marginal |
| `openBoxes(uint256 maxCount)` returns(opened) | `DegenerusGame.sol:1800` | The unified valve: `drainAfkingBoxes(maxCount)` first, then `_openHumanBoxes(remaining)` | LIVE-01 |
| `_openHumanBoxes(maxCount)` | `DegenerusGame.sol:1829` | Human-box leg; rngLock+liveness entry-gate, orphan-index skip, uniform O(1) | LIVE-01 |
| `beginAfking(player, currentDay)` returns(streak) | `DegenerusQuests.sol:432` | Sets `afkingActive = true`, returns the snapshot streak | QST-04 non-perturbation |
| `finalizeAfking(player, earnedStreak, afkingCoveredDay, currentDay)` | `DegenerusQuests.sol:463` | Writes `state.streak` (funding-kill guard `lastValid + 1 >= currentDay ? earned : 0`), clears `afkingActive`; idempotent (`if (!afkingActive) return;`) | SEC-01 finalize repro, QST-04 |
| `awardQuestStreakBonus(player, amount, currentDay)` | `DegenerusQuests.sol:378` | The shared-core manual/bingo/degenerette/boon caller | QST-04 byte-identity |
| `_afkingStreak(sub, currentDay)` | `GameAfkingModule.sol:778` | The compute-on-read + decay (`covered + 1 < currentDay → 0`) | SEC-01 decay repro |
| `rngGate(...)` returns(word, gapDays) | `DegenerusGameAdvanceModule.sol:1262` | Idempotent gap backfill (`rngWordByDay[day] != 0 → (word, 0)`); `purchaseStartDay += gapCount` | GAS-06 |
| The decouple break | `DegenerusGameAdvanceModule.sol:369-372` | `if (gapDays != 0) { stage = STAGE_GAP_BACKFILLED; break; }` — returns before the jackpot fall-through | GAS-06 |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Adapting the v55 fuzz proofs in place | Authoring brand-new v56 fuzz files | Adapting carries forward the validated fixture/setUp + the seeded-fuzz determinism; new files re-pay that cost. D-09 mandates EXTEND for gas; the SEC fuzz files are net-new v56 successors but should reuse the v55 driving harness. |
| Strict-equality NON-WIDENING gate | The v55 ⊆ subset gate | The `[invariant]` block is still unseeded (`foundry.toml:35-38`, no `seed`) → `DegeneretteBet.inv` stays flaky → carry the v55 ⊆ relaxation, NOT strict equality. |

**Installation:** None. Verify the toolchain is present:
```bash
forge --version
node scripts/lib/patchForFoundry.js --help 2>/dev/null || ls scripts/lib/patchForFoundry.js
```

## Package Legitimacy Audit

Not applicable — Phase 356 installs **no external packages**. It authors and runs forge tests against an existing, vendored toolchain (`lib/forge-std`) and a frozen contract subject. No npm/PyPI/crates dependency is added. The slopcheck gate is therefore vacuously satisfied (no packages to audit).

## Architecture Patterns

### System Architecture Diagram

```
                         Phase 356 TST proof flow (test-only)
                         ════════════════════════════════════

  453f8073 (v55 frozen subject)                 HEAD (v56 TST head)
        │                                              │
        │ checkout + patchForFoundry                   │ patchForFoundry
        │ + forge test --json (WHOLE tree)             │ + forge test --json (WHOLE tree)
        ▼                                              ▼
  baseline-red UNION (BY NAME) ───── set-diff ────► live failing set
        │                          live − union == ∅ ?  │
        │                                              │
        └──────────────► REGRESSION-BASELINE-v56.md ◄──┘   (the doc-only ledger)

  ┌─────────────────────────────── the new/adapted forge proofs ────────────────────────────────┐
  │                                                                                              │
  │  SEC-01 (unmanipulable, strategic sub/unsub)                                                 │
  │    fuzz: random {sub,unsub,buy,claim,open} seq  ──► invariant: Σcredited ≤ honest-continuous │
  │    repro 1: affiliate re-claim churn       ──► drainAffiliateBase total == honest            │
  │    repro 2: streak decay/gap dodge         ──► _afkingStreak read == 0 after a missed day    │
  │    repro 3: pendingBurnie double-claim      ──► claimAfkingBurnie pays once (CEI :1277)       │
  │    repro 4: 4 finalize hooks before delete ──► quests.finalizeAfking runs pre `delete _subOf`│
  │                                                                                              │
  │  SEC-02   debit byte-diff vs 453f8073 + solvency fuzz + RNG-freeze fuzz                       │
  │  QST-04   slot-1 accessible+streak-neutral during afking; awardQuestStreakBonus byte-ident   │
  │  LIVE-01  openBoxes: afking-first→human, both cursors drain, <16.7M chunks, selectors split  │
  │  GAS-06   advance N (gap backfill, no jackpot) ─break STAGE_GAP_BACKFILLED─► advance N+1 pays │
  │  D-06     multi-day stall resume: EACH advanceGame tx < 16,777,216 (the 4 residuals pinned)  │
  │  D-09     GAS-01..04 marginals re-asserted as LOOSE-bound regression locks                   │
  │                                                                                              │
  │  D-10     migrate 10 fuzz files OFF_LASTBOUGHT 21/uint32 → 11/uint24 (the 08e59a4a transform)│
  └──────────────────────────────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure
```
test/
├── gas/
│   └── V56AfkingGasMarginal.t.sol     # EXTEND: + per-tx gap-resume ceiling, GAS-06, LIVE-01,
│   │                                  #         marginal regression locks (D-06/07/08/09)
│   └── KeeperOpenBoxWorstCaseGas.t.sol# already migrated (=11/uint24); extend if open-leg cases land here
├── fuzz/
│   ├── V56*.t.sol (NEW)               # SEC-01 fuzz+repro, SEC-02 freeze/solvency, QST-04 — v56 successors
│   │                                  #   of V55FreezeDeterminism / V55RevertFreeEvCap / V55SetMutationOpenE
│   └── {10 stale-offset files}        # MIGRATE in place (D-10): 21/uint32 → 11/uint24
└── REGRESSION-BASELINE-v56.md (NEW)   # the BY-NAME NON-WIDENING ledger (copy v55 structure)
```

### Pattern 1: The loop-N-divide MARGINAL (CR-01, load-bearing)
**What:** Every per-item gas number is `(gas for N items − gas for N−1 items)`, NEVER a single-item total. Both runs start from ONE identical clean baseline via `vm.snapshotState()` / `vm.revertToState()` (a linear two-cycle run trips idle-fixture day saturation + `RngNotReady`).
**When to use:** Every gas marginal in `V56AfkingGasMarginal.t.sol`.
**Example:**
```solidity
// Source: test/gas/V56AfkingGasMarginal.t.sol:181-208 (verified shipped)
uint256 snap = vm.snapshotState();
uint256 gasN   = _measureStageAdvanceGas(N_HI, "blMhi_", false, false);
vm.revertToState(snap);
uint256 gasNm1 = _measureStageAdvanceGas(N_LO, "blMlo_", false, false);
uint256 perBuyLootbox = gasN - gasNm1; // the loop-N-divide MARGINAL
```

### Pattern 2: Sub-slot direct-storage probing (the OFF_* offset reads)
**What:** Read the packed Sub slot fields via `vm.load(game, keccak256(abi.encode(who, SUBOF_SLOT))) >> (off*8)` masked to the field width. The v56 re-pack means EVERY offset is uint24 day markers + uint32 accumulators (NOT the old uint32 day markers).
**When to use:** Every fuzz assertion that probes `pendingBurnie`, `affiliateBase`, `afkCoveredThroughDay`, `afkingStartDay`, `lastAutoBoughtDay`, `lastOpenedDay`, the streak latch.
**Example:**
```solidity
// Source: test/gas/V56AfkingGasMarginal.t.sol:80-86, 618-649 (verified shipped — the CANONICAL v56 offsets)
uint256 private constant SUBOF_SLOT = 66;        // _subOf mapping root
uint256 private constant OFF_LASTBOUGHT  = 11;   // uint24 lastAutoBoughtDay   (bytes 11..13)
uint256 private constant OFF_LASTOPENED  = 14;   // uint24 lastOpenedDay       (bytes 14..16)
uint256 private constant OFF_AFKCOVERED  = 17;   // uint24 afkCoveredThroughDay(bytes 17..19)
uint256 private constant OFF_AFKINGSTART = 20;   // uint24 afkingStartDay      (bytes 20..22)
uint256 private constant OFF_AFFBASE     = 23;   // uint32 affiliateBase       (bytes 23..26)
uint256 private constant OFF_PENDINGBURNIE = 27; // uint32 pendingBurnie       (bytes 27..30)
uint256 private constant OFF_STREAKLATCH = 31;   // uint8  subStreakLatch (bit7 ever-sub, bits0-6 streak)
function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
    uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(who, SUBOF_SLOT)))) >> (off * 8);
    return p & ((uint256(1) << widthBits) - 1);
}
```

### Pattern 3: The empirical-checkout NON-WIDENING baseline (D-11)
**What:** Because the v56 contract tree DIFFERS from `453f8073` (the IMPL diff + gas tune + `openBoxes` + decouple are all post-`453f8073`), the baseline red union is NOT carried verbatim — it is re-established by checking out `453f8073`, patching, running the full `forge test --json` tree, and parsing the failing `(suite, test)` set. Then `live − union == ∅` BY NAME.
**When to use:** `REGRESSION-BASELINE-v56.md`.
**Example flow (verified from the v55 ledger §6):**
```bash
node scripts/lib/patchForFoundry.js                    # predict CREATE addrs (no pretest hook)
forge test --json                                      # WHOLE tree, NOT --match-path
git checkout -- contracts/ContractAddresses.sol        # restore frozen (sha256 80fe0dac…)
# then: git stash/worktree to 453f8073, patch, forge test --json, parse union, restore, return
```

### Anti-Patterns to Avoid
- **Testing a settle-day design.** There is no `SETTLE_PERIOD` streak write, no `settleAfkingQuest`, no two-batch split in the shipped code. Any assertion keyed on a settle day tests a superseded design. (`SETTLE_PERIOD` in `V56AfkingGasMarginal` is a harness-local warp helper only — line 124.)
- **Bare-count NON-WIDENING gate.** A `failed == N` count masks a new red coinciding with a narrowing-fix. The gate MUST be a NAME-set membership test (`live − union == ∅`).
- **Linear two-cycle gas measurement.** Re-running a measurement without `vm.revertToState` trips the idle-fixture day saturation + `RngNotReady` on the second cycle (the 351-07 documented failure). Always snapshot/revert.
- **`forge inspect` slot assumptions from training.** The Sub slot is the v56 re-pack — confirm offsets via `forge inspect DegenerusGame storageLayout` against the HEAD tree; copy the canonical block from `V56AfkingGasMarginal:80-86`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Driving a clean VRF-drained advance | A bespoke advance loop | The ported `_settleGame` / `_settleClean` / `_fulfillPending` helpers in `V56AfkingGasMarginal:579-614` | They handle the rngLock + unfulfilled-word interleave; a naive loop reverts `RngNotReady`. |
| Two-near-N marginal isolation | Linear N then N−1 | `vm.snapshotState()` / `vm.revertToState()` (Pattern 1) | Idle-fixture saturation breaks the linear form. |
| The day-boundary warp | `vm.warp(block.timestamp + 1 days)` in a loop | `_warpToBoundary` with an explicit accumulating `t` (line 477) | A Foundry caching quirk freezes `block.timestamp` after the first warp in a loop. |
| Sub-slot field reads | Manual byte math from a guessed layout | The `_subField` + the canonical OFF_* block (Pattern 2) | The v56 re-pack moved every offset; guessed offsets are the `6555125 != 3774873600` garbage-read reds. |
| Deity-pass grant for funded-sub setup | Re-deriving the mintPacked slot | `_grantDeityPass` (line 565: `MINTPACKED_SLOT = 10`, `DEITY_SHIFT = 184`) | Already validated. |
| The baseline red union | Carrying the v55 148-name union verbatim | Empirical checkout of `453f8073` + full run (Pattern 3) | The v56 contract tree differs from `453f8073`; a carried union would be wrong. |

**Key insight:** Almost everything the planner needs already exists in `V56AfkingGasMarginal` (the driving harness, the slot reads, the dual-bound math) or in the three v55 fuzz proofs (the fuzz/repro structure). The 356 work is EXTEND + ADAPT + MIGRATE, not green-field authoring.

## Runtime State Inventory

> This is a test-only phase mutating no contract and no datastore. It is closest to a "refactor" of the test corpus (the D-10 offset migration), so the inventory is included for completeness.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — no datastore is written. The "stored" thing is the v56 Sub-slot layout the tests PROBE; it is frozen in `contracts/`. | None — verified by `git diff 453f8073 HEAD -- contracts/storage/DegenerusGameStorage.sol` is the committed v56 re-pack, not a 356 edit. |
| Live service config | None — no external service. | None. |
| OS-registered state | None. | None. |
| Secrets/env vars | None. | None. |
| Build artifacts | `ContractAddresses.sol` is regenerated by `node scripts/lib/patchForFoundry.js` (and by `hardhat compile --force`) — it MUST be restored byte-identical (sha256 `80fe0dac…`) after every patch round-trip. The forge fixture breaks if it drifts. | The ledger run MUST end with `git checkout -- contracts/ContractAddresses.sol`. The 10 stale-offset test files are the only `test/` artifacts the phase rewrites — the D-10 migration. |

**The canonical question — after every test file is updated, what still carries the old layout?** The answer is: nothing in `contracts/` (frozen), and after D-10, nothing in `test/` (all 14 afking-probing files at `OFF_LASTBOUGHT=11`/uint24). Today, 10 fuzz files still carry `21`/uint32 (the garbage-read reds).

## Common Pitfalls

### Pitfall 1: The harness `SUBSCRIBER_CAP` is STALE (500 vs the shipped 1000) — HARNESS BUG
**What goes wrong:** `V56AfkingGasMarginal.t.sol:127` declares `SUBSCRIBER_CAP = 500` and comments it as "`GameAfkingModule.sol:164`". The shipped contract has `SUBSCRIBER_CAP = 1000` (`GameAfkingModule.sol:165`). A per-tx ceiling proof "at the cap" using 500 under-states the worst-case STAGE/open chunk by 2×.
**Why it happens:** the harness constant was copied from an earlier design and not re-derived against HEAD.
**How to avoid:** the D-06 per-advance ceiling work MUST correct the harness constant to 1000 (and re-derive any "at the cap" assertion against 1000). Flag this to the planner as a required fix, not an optional tidy.
**Warning signs:** any "worst-case at SUBSCRIBER_CAP" assertion that passes comfortably — re-check the cap value.

### Pitfall 2: `processSubscriberStage` has NO per-cycle eviction cap — only the weight budget bounds it
**What goes wrong:** a test assuming an explicit eviction count cap will mis-model the chunk. The per-cycle eviction cap was DROPPED (line 853 comment); the ONLY bound is `SUB_STAGE_WEIGHT_BUDGET = 1000` with an evict weighing `SUB_STAGE_EVICT_WEIGHT = 2`. An all-evicts chunk is `1000/2 = 500` evicts.
**How to avoid:** model the worst-case chunk as the binding weight extreme (all-ticket = `1000/8 = 125` ticket buys, or all-evict = 500 evicts), per the proof's Category-1 row.
**Warning signs:** a chunk-size assertion using a raw count instead of the weight budget.

### Pitfall 3: The decay-read function is `_afkingStreak`, not `_streakOf`
**What goes wrong:** the CONTEXT/REQUIREMENTS name the read `_streakOf` / `_streakBaseOf`; the shipped private functions are `_afkingStreak(sub, currentDay)` (line 778, the decay-read) and `_streakBaseOf(sub)` (the raw base). A test grepping for `_streakOf` finds nothing.
**How to avoid:** assert behavior through public/external paths (the activity-score read, the finalize write) and probe the streak latch byte directly (`OFF_STREAKLATCH`, bits 0-6). The decay condition is `covered + 1 < currentDay → 0` (line 784).
**Warning signs:** a private-function name reference in a test comment that does not match the source.

### Pitfall 4: The funding-kill guard is `lastValid + 1 >= currentDay`, NOT `<= currentDay - 2`
**What goes wrong:** the CONTEXT phrases the funding-kill guard as "zeroes only if `lastValidMintDay <= currentDay - 2`". The shipped `finalizeAfking` (DegenerusQuests.sol:474) keeps the earned streak when `currentDay == 0 || lastValid + 1 >= currentDay`, else zeroes. These are equivalent (`lastValid + 1 >= currentDay` ⟺ NOT `lastValid <= currentDay - 2`), but the test MUST assert the exact `+1` grace boundary: delivered yesterday (`lastValid == currentDay - 1`) → kept; missed a full prior day (`lastValid <= currentDay - 2`) → zeroed. `lastValid = max(afkingCoveredDay, state.lastActiveDay)` — so a sub that lapsed afking funding but kept minting MANUALLY (bumping `lastActiveDay`) is NOT wrongly zeroed (D-02.4).
**How to avoid:** write both the boundary-kept and the boundary-zeroed case explicitly; cover the manual-mint-keeps-alive case.

### Pitfall 5: The `[invariant]` block is unseeded → carry the ⊆ relaxation, not strict equality
**What goes wrong:** `foundry.toml` seeds `[fuzz]` (`seed = "0xdeadbeef"`, line 33) but the default `[invariant]` block (lines 35-38) has NO seed → `DegeneretteBet.inv::invariant_solvencyUnderDegenerette` is flaky run-to-run. A strict-equality NON-WIDENING gate would be non-deterministic.
**How to avoid:** carry the v55 ⊆ subset gate (`live − union == ∅`), NOT strict equality; baseline the flaky cluster member in the union ceiling; document the non-determinism (mirror v55 §4).

### Pitfall 6: `ContractAddresses.sol` drift breaks the whole forge tree
**What goes wrong:** `patchForFoundry.js` rewrites `ContractAddresses.sol` to predict CREATE addresses; if not restored, OR if `hardhat compile --force` regenerates it (a known landmine recorded in project memory), the forge fixture's pinned addresses drift and the whole tree reds at setUp.
**How to avoid:** every patch round-trip ends with `git checkout -- contracts/ContractAddresses.sol`; verify sha256 `80fe0dac…` after restore. Do NOT run `hardhat compile --force` mid-session.

### Pitfall 7: Two-path coexistence shares the Sub slot — assert `lastOpenedDay` monotone + cursor independence
**What goes wrong:** both open paths touch the same Sub record. The afking `_autoOpen` (drainAfkingBoxes) walks `_subOpenCursor` and skips `lastOpenedDay >= lastAutoBoughtDay` (line 1154); the human leg walks `boxCursor` over `boxPlayers[index]`. A test must prove the two cursors are independent and `lastOpenedDay` is monotone (no double-open). The valve calls afking FIRST (`maxCount`), then human with `maxCount - openedAfking` (DegenerusGame:1815).
**How to avoid:** assert (a) afking-first ordering by exhausting the afking backlog and observing the human leg only consumes the remainder; (b) repeated bounded `openBoxes` calls advance BOTH `_subOpenCursor` and `boxCursor` until both backlogs drain; (c) `drainAfkingBoxes` called directly on the module address hits empty storage (selector isolation — it is reached only via the Game delegatecall).

## Code Examples

### The 4 finalize hooks (all call `_finalizeAfking` BEFORE the slot delete)
```solidity
// Source: contracts/modules/GameAfkingModule.sol (verified shipped)
// (A) explicit cancel — subscribe(_, 0), runs on the user's own tx (off the advance chain):
//   :318  _finalizeAfking(subscriber, c, _simulatedDayIndex());  then  c.dailyQuantity = 0;  (tombstone in place)
// (B) cancel-reclaim — in-stage, DELETES _subOf (load-bearing ordering):
//   :912  _finalizeAfking(player, sub, processDay);
//   :915  delete _subOf[player];   :916 _removeFromSet(player);   (finalize PRECEDES delete)
// (C) pass-eviction crossing — currentLevel > validThroughLevel and horizon no longer covers:
//   :952  _finalizeAfking(player, sub, processDay);  :953 sub.dailyQuantity = 0;  :954 _removeFromSet(player);
// (D) funding-kill — NORMAL underfunded sub (VAULT/SDGNRS exempt):
//   :1010 _finalizeAfking(player, sub, processDay); :1011 sub.dailyQuantity = 0; :1012 _removeFromSet(player);
```

### The CEI claim (idempotency anchor for D-02.3)
```solidity
// Source: contracts/modules/GameAfkingModule.sol:1270-1284 (verified shipped)
function claimAfkingBurnie(address[] calldata subs) external {
    uint256 len = subs.length;
    for (uint256 i; i < len; ) {
        Sub storage s = _subOf[subs[i]];
        uint256 owed = uint256(s.pendingBurnie);     // whole BURNIE
        if (owed != 0) {
            s.pendingBurnie = 0;                     // CEI: zero before the external credit
            coinflip.creditFlip(subs[i], owed * 1 ether);
        }
        unchecked { ++i; }
    }
}
```

### The gap/jackpot decouple (GAS-06)
```solidity
// Source: contracts/modules/DegenerusGameAdvanceModule.sol:347-372 (verified shipped)
(uint256 rngWord, uint32 gapDays) = rngGate(ts, day, purchaseLevel, lastPurchase, bonusFlip);
psd += gapDays;
if (rngWord == 1) { _swapAndFreeze(purchaseLevel); stage = STAGE_RNG_REQUESTED; break; }
// Decouple: if rngGate just backfilled a gap, defer the (up-to-305-winner) jackpot to the NEXT advance.
// rngGate is idempotent (rngWordByDay[day] now set -> gapDays == 0 next call); dailyIdx NOT advanced
// (no _unlockRng reached) so advanceDue() stays true; the next advance pays the jackpot with the same word.
if (gapDays != 0) { stage = STAGE_GAP_BACKFILLED; break; }   // STAGE_GAP_BACKFILLED = 12 (:81)
// ... only if NO gap: phase transition / payDailyJackpot fall-through (the deferred work)
// rngGate idempotency: :1271  if (rngWordByDay[day] != 0) return (rngWordByDay[day], 0);
// rngGate gap guard:   :1284  if (day > idx + 1 && rngWordByDay[idx + 1] == 0) { ... purchaseStartDay += gapCount; gapDays = gapCount; }
```

### The openBoxes valve (LIVE-01)
```solidity
// Source: contracts/DegenerusGame.sol:1800-1819 (verified shipped)
function openBoxes(uint256 maxCount) external returns (uint256 opened) {
    if (maxCount == 0) return 0;
    (bool ok, bytes memory data) = ContractAddresses.GAME_AFKING_MODULE.delegatecall(
        abi.encodeWithSelector(IGameAfkingModule.drainAfkingBoxes.selector, maxCount));  // afking FIRST
    if (!ok) _revertDelegate(data);
    uint256 openedAfking = abi.decode(data, (uint256));
    if (openedAfking < maxCount) opened = _openHumanBoxes(maxCount - openedAfking);      // then human, remainder
    opened += openedAfking;
}
```

## The 16.7M per-tx ceiling — the proof's 4 named residuals (D-06)

`audit/PROOF-V56-16P7M-GAS-CEILING.md` is LOCAL/gitignored (confirmed present at research time). It is a 3-model worst-case bound audit. Its honest verdict: the v56 everyday afking subject is PROVEN bounded < 16.7M with 7-10M headroom, and every protocol-FORCED loop has an explicit cap, BUT it is bound analysis, not formal verification, and it left **4 named residuals** as estimates that 356 must empirically pin (the "Residual assumptions" section, lines 58-64):

| # | Residual | What 356 must measure |
|---|----------|------------------------|
| 1 | **STAGE weight-model fidelity** | A *level-crossing pass refresh-or-evict* iteration AND a *gap-resumed streak rebase* iteration are not separately measured against their assigned weights. Add a harness case that forces a level crossing / gap-resume INSIDE a saturated weight chunk and asserts the true per-iter gas ≤ its weight allocation. |
| 2 | **processTicketBatch single-entry worst case** | The per-entry cap (`writesBudget - used`) stops one entry overrunning, but the heaviest single entry (take up to `maxT` at a full budget) chunk is not separately asserted at the cap. Measure the heaviest single `processTicketBatch` entry. |
| 3 | **Mixed-stamp-day OPEN_BATCH (cache-defeating)** | The harness measures a uniform stamp day; the day-cache-defeating mixed-day case (each box re-reads `rngWordByDay`, defeating the `cachedDay`/`cachedWord` short-circuit at `GameAfkingModule:1157-1163`) has a higher per-box marginal. Measure 130 boxes spanning 130 DISTINCT stamp days. |
| 4 | **Per-iter marginals come from fixture states** | The fixture uses 5-ETH subs + a deity pass; the true heaviest per-iter state (max streak hand-back, level crossing) may exceed them. Re-measure at the heaviest reachable per-iter state. |

**Plus the composition breach the proof is the empirical answer to (GAS-06):** Codex found (verified) that `_backfillGapDays` (≤120 days, ~9M) and the `payDailyJackpot` fall-through (≤305 winners, ~6M+) ran in the SAME `advanceGame` tx after a 121+ day stall — ≈15-15.8M, erasing the margin. The decouple (`3d969621`) fixes it. The proof's per-tx gap-resume number is an ESTIMATE (the CONTEXT cites ~15.8M = STAGE ~6.8M + backfill ~9M); **356's D-06 turns it into an empirical per-advance assertion**: drive the worst-case multi-day stall resume and assert EACH `advanceGame` tx < 16,777,216 individually (the backfill advance N AND the jackpot advance N+1). NOTE: the proof's "measured" rows (STAGE 6.82M, open 9.29M) used the OLD `SUBSCRIBER_CAP` model — re-derive against the shipped cap of **1000** (Pitfall 1).

## State of the Art

| Old (stale) framing | Current (shipped) reality | Where it changed | Impact on 356 |
|---------------------|---------------------------|------------------|---------------|
| Settle day / `SETTLE_PERIOD` streak write / two-batch split | Compute-on-read streak + decay; per-day `pendingBurnie` pull; single weighted budget | mid-355 (`355-CONTEXT.md` SUPERSEDING block) | Do NOT test a settle day. |
| `OFF_LASTBOUGHT = 21` / uint32 day markers (old standalone-AfKing 232-bit slot) | `OFF_LASTBOUGHT = 11` / uint24 markers (v56 single 256-bit re-pack) | `08e59a4a` (gas suites) | D-10: migrate the 10 remaining fuzz files. |
| Standalone human `autoOpen(maxCount)` + `MAX_AUTO_OPEN` clamp | Unified `openBoxes(maxCount)` valve; afking `autoOpen`→`drainAfkingBoxes` (distinct selector) | `86a2d6c8` | LIVE-01: test the valve, not the dropped `autoOpen`. |
| `SUBSCRIBER_CAP = 500` (harness) | `SUBSCRIBER_CAP = 1000` (shipped) | — | Pitfall 1: fix the harness constant. |
| v55 baseline `20ca1f79` (148-name union) | v56 baseline `453f8073` | — | Re-establish the union by empirical checkout of `453f8073`. |

**Deprecated/outdated (do not reference in tests):**
- `settleAfkingQuest`, `claimQuest`, `_settleQuest`, `buyerOwedBurnie`, `questProgress` — all removed/folded in the compute-on-read reconciliation. `pendingBurnie` replaced `buyerOwedBurnie`.
- The standalone `autoOpen` selector on the afking module (dropped, replaced by `drainAfkingBoxes`).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `audit/PROOF-V56-16P7M-GAS-CEILING.md` remains the authoritative residual list at plan time (it is LOCAL/gitignored and will not persist in git). | 16.7M ceiling section | LOW — read fully at research time; the 4 residuals + the GAS-06 breach are transcribed above. Re-read if the local file changed. |
| A2 | The v56 baseline-red union off `453f8073` will be of comparable shape to the v55 148-name union (Bucket A VRF/RNG ~41, Bucket B stale-harness ~92, Bucket F flaky ~1). | NON-WIDENING method | MEDIUM — the v56 contract tree differs from `453f8073`, so the union MUST be re-derived empirically; the v55 shape is a prior, not a given. The empirical run is the truth. |
| A3 | `forge` and `node scripts/lib/patchForFoundry.js` run cleanly on the target machine (the fixture is not in the DeployProtocol-vanity-address down-state noted at the end of `355-CONTEXT.md`). | Toolchain | MEDIUM — `355-CONTEXT.md` noted the fixture was down (vanity-address realignment) blocking gas measurement. Verify the fixture builds/runs at plan start; if still down, a Wave-0 fixture repair precedes everything (mirrors v55 351-01). |

## Open Questions

1. **Is the DeployProtocol fixture currently green at setUp?**
   - What we know: `355-CONTEXT.md` ended noting the fixture was down (vanity-address realignment) blocking gas measurement; the V56 gas harness `08e59a4a` is committed (implying it ran at some point post-repair).
   - What's unclear: whether the fixture is green at 356 plan time.
   - Recommendation: the planner should add a Wave-0 fixture-sanity gate (run `V56AfkingGasMarginal` + one v55 fuzz proof) before the SEC/LIVE/GAS waves; if red at setUp, a fixture repair is the first task (the v55 351-01 precedent).

2. **Does the gap-resume worst case need a fixture larger than the current N_HI=24?**
   - What we know: the D-06 per-advance assertion must hit the worst-case STAGE chunk at the cap (1000 subs) AND the multi-day backfill (≤120 days) AND the jackpot (≤305 winners).
   - What's unclear: whether the existing fixture can stand up ~305 jackpot winners + a 120-day stall cheaply enough to measure in one test.
   - Recommendation: the planner should scope the D-06 case as its own harness method with a dedicated heavy-state setup, separate from the cheap marginal cases; budget for `block_gas_limit = 30e9` (already set, `foundry.toml:16`) so the measurement tx itself does not revert.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `forge` (Foundry) | All v56 proofs | ✓ (vendored toolchain; verify `forge --version`) | repo-pinned | none — hard requirement |
| `scripts/lib/patchForFoundry.js` | Whole-tree run + the NON-WIDENING ledger | ✓ (confirmed present) | repo | none |
| `npx hardhat compile` | The ledger sanity arm | ✓ (v55 ran it EXIT 0) | repo-pinned | compile-only sanity is sufficient (v55 §7a precedent) |
| `git` checkout of `453f8073` | The empirical baseline union | ✓ (commit reachable; it is the v55 frozen subject) | — | none |
| `audit/PROOF-V56-16P7M-GAS-CEILING.md` | D-06 residual transcription | ✓ LOCAL/gitignored | — | the 4 residuals + the GAS-06 breach are transcribed in this RESEARCH.md |

**Missing dependencies with no fallback:** none identified, CONTINGENT on the DeployProtocol fixture being green (Open Question 1).
**Missing dependencies with fallback:** the full Hardhat end-to-end run is impractically slow per-case (v55 §7a) — the fallback is the compile-only sanity arm + the forge whole-tree ledger as primary.

## Test Strategy (for the planner)

> The formal `## Validation Architecture` section is OMITTED: `.planning/config.json` sets
> `workflow.nyquist_validation: false`. The test-mapping below is plain planning guidance (this is
> itself a TST phase, so the requirements ARE the tests), not a Nyquist sampling spec.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry `forge` (+ Hardhat sanity arm) |
| Config file | `foundry.toml` ( `[fuzz] seed = 0xdeadbeef runs = 1000` ; `[invariant]` UNSEEDED `runs = 256 depth = 128`) |
| Quick run command | `node scripts/lib/patchForFoundry.js && forge test --match-path 'test/fuzz/V56*.t.sol' && git checkout -- contracts/ContractAddresses.sol` |
| Full suite command | `node scripts/lib/patchForFoundry.js && forge test --json && git checkout -- contracts/ContractAddresses.sol` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SEC-01 | churn/decay/double-claim/finalize-hooks unmanipulable | fuzz + repro | `forge test --match-contract V56SecUnmanipulable -vv` | ❌ Wave 0 (adapt V55RevertFreeEvCap + V55SetMutationOpenE) |
| SEC-02 | debit byte-unchanged + solvency fuzz + RNG-freeze | byte-diff + fuzz | `forge test --match-contract V56FreezeSolvency -vv` | ❌ Wave 0 (adapt V55FreezeDeterminism) + grep/diff anchor in ledger |
| QST-04 | slot-1 accessible+streak-neutral; awardQuestStreakBonus byte-ident | unit + fuzz | `forge test --match-contract V56QuestNonPerturb -vv` | ❌ Wave 0 |
| LIVE-01 | openBoxes drain/bound/coexist; selectors split | unit + gas | `forge test --match-contract V56AfkingGasMarginal -vv` (extend) + `KeeperOpenBoxWorstCaseGas` | ⚠ extend existing |
| GAS-06 | gap→defer→next-pays per-advance <16.7M + idempotent resume | gas + unit | `forge test --match-contract V56AfkingGasMarginal -vv` (extend) | ⚠ extend existing |
| D-06 residuals | level-crossing/gap-rebase, heaviest ticket entry, mixed-day open, heavy-state marginal | gas | `forge test --match-contract V56AfkingGasMarginal -vv` (extend) | ⚠ extend existing |
| NON-WIDENING | live − `453f8073` union == ∅ BY NAME | doc ledger | the full-suite command at BOTH HEADs + set-diff | ❌ Wave-N `REGRESSION-BASELINE-v56.md` |

### Sampling Rate
- **Per task commit:** `forge test --match-contract <the touched contract> -vv` (after patchForFoundry + restore).
- **Per wave merge:** `forge build` EXIT 0 + the touched suites green.
- **Phase gate:** the full whole-tree `forge test --json` run at the v56 TST HEAD, reconciled BY NAME against the empirical `453f8073` union; `live − union == ∅`.

### Wave 0 Gaps
- [ ] `test/fuzz/V56SecUnmanipulable.t.sol` (or similarly named) — SEC-01 fuzz + the 4 named repros (adapt `V55RevertFreeEvCap` + `V55SetMutationOpenE`).
- [ ] `test/fuzz/V56FreezeSolvency.t.sol` — SEC-02 three legs (adapt `V55FreezeDeterminism`).
- [ ] `test/fuzz/V56QuestNonPerturb.t.sol` — QST-04 (D-04) slot-1 + byte-identity.
- [ ] EXTEND `test/gas/V56AfkingGasMarginal.t.sol` — per-tx gap-resume ceiling (D-06, fix `SUBSCRIBER_CAP`→1000), the 4 residuals, GAS-06 decouple, LIVE-01 valve, GAS-01..04 regression locks (D-09).
- [ ] MIGRATE the 10 stale-offset fuzz files (D-10): `AfKingConcurrency`, `AfKingFundingWaterfall`, `AfKingSubscription`, `KeeperRouterOneCategory`, `KeeperFaucetResistance`, `KeeperRewardRoutingSameResults`, `KeeperNonBrick`, `V55SetMutationOpenE`, `V55RevertFreeEvCap`, `V55FreezeDeterminism` — `OFF_LASTBOUGHT 21→11`, `OFF_LASTOPENED 25→14` (+ the other markers to uint24 17/20, accumulators uint32 23/27, latch 31), and every `_subField(..., 32)` day-marker read → `..., 24`.
- [ ] `test/REGRESSION-BASELINE-v56.md` — the BY-NAME ledger (copy `test/REGRESSION-BASELINE-v55.md` structure verbatim).
- [ ] Framework install: none — `forge` is vendored.

## Security Domain

> `security_enforcement` not found false in config — included. This is itself the security-proof phase, so the ASVS framing maps to the SEC requirements.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | n/a — permissionless protocol (the threat model is economic, not auth) |
| V3 Session Management | no | n/a |
| V4 Access Control | partial | `onlyGame`/`onlyCoin`/`AFFILIATE`-only drains (the finalize/claim entrypoints) — assert the gates hold in the finalize/affiliate repros |
| V5 Input Validation | yes | `subscribe` revert paths (`InvalidReinvestPct`, `NotApproved`, `NotSubscribed`, `RngLocked`); the fuzz drives random inputs against these |
| V6 Cryptography | yes (RNG-freeze) | NEVER hand-roll: the freeze invariant is that afking surfaces consume ONLY the frozen `rngWordByDay[stampDay]`; the subscribe min-buy STAMPS (never inline-resolves pre-RNG); single-roll open. Adapt `V55FreezeDeterminism`. |

### Known Threat Patterns for the v56 afking stack

| Pattern | STRIDE | Standard Mitigation (the SHIPPED control to assert) |
|---------|--------|-----------------------------------------------------|
| Strategic sub/unsub churn to re-claim affiliate | Elevation (econ) | `affiliateBase` PERSISTS across unsub (not flushed on mutation, `subscribe:315` comment); `drainAffiliateBase` is read-and-zero at the storage owner (AFFILIATE-only) → churn neither forfeits nor duplicates. |
| Streak gap-dodge / non-funded streak inflation | Tampering | Compute-on-read decay (`_afkingStreak:784` `covered + 1 < currentDay → 0`); streak advances ONLY on debit-DELIVERED days; gap-reset-on-resume. |
| `pendingBurnie` double-claim / re-entrancy harvest | Tampering | CEI zero-before-credit (`claimAfkingBurnie:1277`); `creditFlip` recordAmount makes reentrancy a non-issue. |
| Orphaned paid-for box (mutation between stamp and open) | Denial | The no-orphan guard (`processSubscriberStage:892`): a sub with a pending unopened box is left ENTIRELY untouched (no reclaim/evict/funding-kill/re-stamp). |
| Two-path open double-open / cross-corruption | Tampering | `lastOpenedDay` monotone (skip `lastOpenedDay >= lastAutoBoughtDay`, `:1154`); independent cursors (`_subOpenCursor` vs `boxCursor`); afking-first-then-human budget split. |
| Gap-backfill + jackpot composition DoS (>16.7M) | Denial | The GAS-06 decouple (`AdvanceModule:369-372`): defer the jackpot to advance N+1; `rngGate` idempotent; `dailyIdx` not advanced. |
| SOLVENCY-01 ETH/pool divergence | Tampering | The ETH/`claimablePool` debit is byte-frozen from v55 (`_deliverAfkingBuy`); affiliate/quest rewards are BURNIE flip-credit OFF the ETH path. Assert via byte-diff vs `453f8073` + solvency fuzz. |

## Sources

### Primary (HIGH confidence)
- `contracts/modules/GameAfkingModule.sol` — `subscribe:255`, `_finalizeAfking:799`, `processSubscriberStage:860` (the 4 finalize branches at 912/952/1010 + the cancel at 318), `_afkingStreak:778`, `claimAfkingBurnie:1270` (CEI :1277), `drainAfkingBoxes:1234`, `mintBurnie:1193`/`_autoOpen:1146`, constants (`SUBSCRIBER_CAP=1000:165`, `OPEN_BATCH=130:212`, `SUB_STAGE_EVICT_WEIGHT=2:172`, `SUB_STAGE_TICKET_WEIGHT=8:179`).
- `contracts/modules/DegenerusGameAdvanceModule.sol` — the decouple `:369-372` (`STAGE_GAP_BACKFILLED=12:81`), `rngGate:1262` idempotency (`:1271`, `:1284` `purchaseStartDay += gapCount`), `SUB_STAGE_WEIGHT_BUDGET=1000:166`.
- `contracts/DegenerusGame.sol` — `openBoxes:1800`, `_openHumanBoxes:1829`.
- `contracts/DegenerusQuests.sol` — `beginAfking:432`, `finalizeAfking:463` (funding-kill guard `:474` `lastValid + 1 >= currentDay`), `awardQuestStreakBonus:378`, the O1 region `:880-900`, `afkingActive` flag `:283/441/471/481`.
- `test/gas/V56AfkingGasMarginal.t.sol` — the canonical v56 Sub-slot offsets (`:80-86`), the marginal/dual-bound helpers, the driving harness; the stale `SUBSCRIBER_CAP=500` (`:127`).
- `test/REGRESSION-BASELINE-v55.md` — the EXACT NON-WIDENING pattern (the BY-NAME headline, empirical-checkout method, the buckets, the ⊆ relaxation, the FC1-FC6 guards).
- `audit/PROOF-V56-16P7M-GAS-CEILING.md` — the 3-model bound audit; the 4 residuals (`:58-64`) + the GAS-06 composition breach (`:91-99`).
- `foundry.toml` — `[fuzz] seed=0xdeadbeef runs=1000` (`:30-33`), `[invariant]` UNSEEDED (`:35-38`), `block_gas_limit=30e9` (`:16`).
- `git show 08e59a4a` — the canonical offset-migration transform (21/uint32 → 11/uint24); `git show 86a2d6c8` (openBoxes valve); `git show 3d969621` (decouple).
- `git diff --stat 453f8073 HEAD -- contracts/` — the 14-file v56 IMPL diff (frozen; 356 adds nothing).

### Secondary (MEDIUM confidence)
- `.planning/phases/356-.../356-CONTEXT.md` — the locked decisions D-01..D-11 (authoritative for scope).
- `.planning/phases/355-.../355-CONTEXT.md` — the SUPERSEDING compute-on-read design (the WHAT-shipped description).
- `.planning/REQUIREMENTS.md` — SEC-01/02, LIVE-01, GAS-06 (the stale "per-settle" wording flagged).

### Tertiary (LOW confidence)
- None — all claims verified against source or the test corpus this session.

## Metadata

**Confidence breakdown:**
- Standard stack (toolchain + contract surface): HIGH — every function signature, line, and constant verified against HEAD source this session.
- Architecture (the 4 finalize paths, the decouple, the valve, the compute-on-read decay): HIGH — read out from the shipped source with line anchors.
- Pitfalls: HIGH — the two harness bugs (`SUBSCRIBER_CAP` 500-vs-1000; the `_streakOf`/`_afkingStreak` naming; the `<= currentDay-2` vs `+1 >= currentDay` guard phrasing) were caught by diffing the CONTEXT/REQUIREMENTS framing against the actual source.
- NON-WIDENING method: HIGH — the v55 ledger is a verbatim precedent; the only delta is the baseline commit (`453f8073`) and the empirical-checkout requirement (the v56 tree differs).
- The 4 residuals + GAS-06 ceiling: HIGH on transcription; the per-advance numbers are ESTIMATES the proof itself flags (356's job is to make them empirical).

**Research date:** 2026-06-02
**Valid until:** 7 days (fast-moving — the fixture state and any further USER directives can shift; the contract subject is frozen so the surface facts are stable, but re-verify the fixture is green and re-read `audit/PROOF-V56-...` at plan time as it is gitignored).
