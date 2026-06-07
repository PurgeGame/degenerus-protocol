---
phase: 377-gas-neutrality-gate
type: GAS (gas-neutrality measurement gate — owns NO REQ-ID)
milestone: v61.0
subject: b97a7a2e (the v61.0 batched diff committed at 376)
baseline: 2bee6d6f (v60.0 closure HEAD)
completed: 2026-06-06
verdict: OUTCOME-A (gas-neutral on the advanceGame DoS-ceiling chain — NO contract gas-tune)
---

# Phase 377 GAS — Gas-Neutrality Gate (v61.0)

**OUTCOME-A: the v61 diff does NOT regress the advanceGame gas-DoS ceiling chain. No contract tune.** The only metered-ceiling deltas are PACK accessor impls (1-slot-vs-1, neutral) and the curse APPLY (zero-new-SLOAD). All v61 feature gas (AFPAY afking tier, curse SET, decurse/smite) lands OFF the advanceGame chain (user txs), which is the only gas-DoS surface per the threat model (16.7M = gg).

## 1. Worst-case derivation (per "derive first, then test")

The dominant/only gas-DoS surface is the **advanceGame chain** (threat-model: HIGH = gas-DoS only here; 16.7M = forced game-over). What v61 changed on it:

- **advanceGame orchestrator + jackpot/decimator/boon/bingo modules: byte-UNCHANGED by v61** (verified `git show b97a7a2e --stat`). The 12 changed contracts do NOT include AdvanceModule or JackpotModule.
- **PACK (balancesPacked fold) — the only accessor-impl change reachable from advanceGame:**
  - Jackpot 305-winner ETH leg credit (`JackpotModule._addClaimableEth` → `_creditClaimable`): old `claimableWinnings[x] += amt` (1 SLOAD+SSTORE) → new `balancesPacked[x] += amt` (1 SLOAD+SSTORE). **NEUTRAL.**
  - Afking auto-buy/evict debit (`GameAfkingModule._deliverAfkingBuy:791` → `_debitAfking`): old `afkingFunding[x] -= v` (1 SLOAD+SSTORE) → new `balancesPacked[x] -= v<<128` (1 SLOAD+SSTORE, +3 gas shift). **NEUTRAL.** No claimable read added on this path (funding check reads only `_afkingOf`).
  - Game-over final sweep (VAULT/SDGNRS/GNRUS via `_debitClaimable`, preserving the afking half): 3 fixed-address reads+writes, one-time, NOT a loop. Negligible.
  - Folding 2 mappings → 1 can only REDUCE cold-slot count where both halves co-access; otherwise 1-slot-vs-1. So PACK is **gas-neutral-or-better** on every metered path.
- **CURSE-02 APPLY** (`MintStreakUtils:322`): rides the existing `mintPacked_` SLOAD at `:248` → **zero new SLOAD**; adds shift+mask+compare+subtract (~20-30 gas arithmetic). The subscriber EVICT path (the binding stage) is teardown and does not compute the activity score, so even the +30 doesn't apply there.
- **AFPAY afking tier, curse SET (maybeCurse), decurse/smite: OFF the advanceGame chain.** The afking AUTO-buy (advanceGame stage 2) does NOT call `_processMintPayment` (SPEC anchor: ref count 0). The AFPAY waterfall + maybeCurse fire on MANUAL buy / claimWinnings (user txs), which cannot brick the game.

## 2. Empirical measurement (clean harnesses, v61 tree b97a7a2e)

`forge test --match-contract "AdvanceStageWorstCaseGas|GameOverCompositionAdvanceGas"` → **7/7 passed.** These two harnesses use ZERO hardcoded storage slots, so the PACK fold did not break them.

| advanceGame stage | v61 worst-case gas | source | headroom to 16.7M |
|---|---|---|---|
| STAGE 8/11/12 — daily ETH jackpot, 305 winners (PACK'd credit) | **7,279,713** | MEASURED | 9.50M |
| STAGE 0/1/5/6/7 — ticket batch chunk (cold) | 6,515,529 | MEASURED | 10.26M |
| STAGE 0/1/5/6/7 — ticket batch chunk (warm full budget) | 9,738,286 | MEASURED | 7.04M |
| STAGE 4 — gap backfill | 7,308,134 | referenced | — |
| **STAGE 2 — subscriber all-evict (BINDING)** | **13,603,709** | referenced* | **3,173,507** |
| per-ETH-winner marginal (305) | 22,949 | MEASURED | — |
| per-trait marginal (ticket batch) | 28,367 | MEASURED | — |

Game-over composition (the v60 critical, now carrying the +~1k/refund `PlayerCredited` LOG on deity-refund): harness PASSED — composition stays under the ceiling on v61.

*STAGE_2 is *referenced* from the v56/v60 measurement (the `AdvanceStageWorstCaseGas` harness references it from `V56AfkingGasMarginal` by design — re-measuring it needs the heavy 270-subscriber setup). On v61 it is **structurally neutral**: the evict path's afking op is 1-slot (PACK-neutral) and the curse counter is not on the evict path. So the 13.60M / 3.17M-headroom binding figure holds on v61.

## 3. Stale slot-hardcoded harnesses — 378 recalibration (NOT a gas regression)

The v61 PACK fold removed the `afkingFunding` mapping from Storage, shifting subsequent storage slots. Six gas harnesses set up state via **hardcoded `vm.store`/`vm.load` slot constants** calibrated to the old (`453f8073`) layout, so their seeders now write the WRONG slot → setup fails (e.g. `V56AfkingGasMarginal`: all 16 tests revert `NoPass()` because the deity-pass grant writes a stale slot, so the D-11 pass-gate then rejects subscribe). This is a **test-harness staleness**, NOT a production gas regression — the production afking debit is provably 1-slot-neutral (§1).

| Harness | hardcoded-slot refs | covers | status |
|---|---|---|---|
| V56AfkingGasMarginal | 31 | afking subscriber stage / per-buy marginals (binding STAGE_2) | broken → recalibrate at 378 |
| SweepPerPlayerWorstCaseGas | 18 | per-player sweep | broken → 378 |
| RouterWorstCaseGas | 16 | keeper router | broken → 378 |
| KeeperResolveBetWorstCaseGas | 12 | degenerette resolve | broken → 378 |
| KeeperOpenBoxWorstCaseGas | 9 | box open | broken → 378 |
| KeeperLeversAndPacking | 5 | levers/packing | broken → 378 |

**378 TST handoff:** recalibrate these harnesses' slot constants to the v61 layout (`forge inspect DegenerusGame storageLayout`), then re-measure STAGE_2 live to confirm the 13.60M binding figure on v61. Same slot shift also breaks the vm.load redemption tests (already flagged in 376-EXEC-HANDOFF). The raw `claimableWinnings`/`afkingFunding` mappings are fully gone (0 raw accesses in Storage).

## 4. Per-tx feature costs (off the ceiling chain — accepted, not tuned)

- AFPAY afking tier on a shortfall-funded manual buy: +`_afkingOf` read + `_debitAfking` + an `AfkingSpent` LOG (~1.1–1.9k). User's own buy tx, far under block limit.
- `maybeCurse` delegatecall from `claimWinnings`: +~2.6k (delegatecall) + cheapest-first bails (+ one SSTORE only on a stale ghost-cashout). User's own claim tx.
- `decurse`/`smite`: standalone external fns, not on any hot path.

None is on the advanceGame chain → none is a gas-DoS / tune concern. These are the feature's intended costs.

## 5. Verdict

**OUTCOME-A — gas-neutral on the metered DoS-ceiling chain; no contract gas-tune.** Matches the v55-350 / v57-360 Outcome-A precedent and the roadmap's expected outcome. The binding advanceGame stage stays at 13.60M (3.17M headroom under 16.7M, < EIP-7825 16,777,216 tx cap) on v61. No `contracts/*.sol` change → no contract-commit gate at 377.

**Caveat carried to 378:** the binding STAGE_2 figure is structurally-neutral + referenced, not freshly measured on v61 (its harness is slot-stale). 378 recalibrates the 6 slot-hardcoded harnesses and re-measures it live, alongside SEC-01/02 + TST-01..06.
