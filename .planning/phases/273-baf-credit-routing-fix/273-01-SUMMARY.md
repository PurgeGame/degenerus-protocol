---
phase: 273-baf-credit-routing-fix
phase_number: 273
plan: 273-01
status: complete
completed: 2026-05-12
baseline: "06623edb"
baseline_signal: "MILESTONE_V38_AT_HEAD_06623edb"
commits:
  - ff929948  # fix(273): contracts + tests batched USER-APPROVED
  - 1cae7682  # chore(273): ROADMAP + STATE scaffold (AGENT-COMMITTED)
  - <pending> # test(273): BAF-ROUTE-06/07/08 expansion (USER-APPROVED, this commit)
  - <pending> # chore(273): phase SUMMARY (AGENT-COMMITTED)
---

# Phase 273 Summary — BAF Credit Routing Fix

## What shipped

**Contract patch** (`contracts/BurnieCoinflip.sol`, committed `ff929948`):

- **`:525`** `cursor > bafResolvedDay` → `cursor >= bafResolvedDay`. Day-of-resolution winning flips now flow into the next bracket instead of being orphaned.
- **`:585-598`** RngLocked guard predicate switched from `purchaseLevel_` to `cachedLevel` (storage `level`). The pre-fix predicate could never fire at x10 boundaries because `_finalizeRngRequest` atomically bumps `level` and sets `rngLockedFlag`, leaving `purchaseLevel_ = _activeTicketLevel() = level + 1` — which never satisfies `% 10 == 0`. Added bafLevel override: when `inJackpotPhase && cachedLevel != 0 && cachedLevel % 10 == 0`, route credit to `cachedLevel + 1` so day-D wins claimed during the jackpot phase land in bracket N+10, not in the just-resolved bracket.
- **`:1035-1045`** `_coinflipLockedDuringTransition` (deposit lock) — same predicate fix.

**Test suite** (`test/edge/BafCreditRouting.test.js`, 14 tests across 8 `describe` blocks):

| Block | # | What it proves |
|---|---|---|
| BAF-ROUTE-01 | 1 | Normal era-0 claim emits `BafFlipRecorded(alice, lvl=10, …)`. |
| BAF-ROUTE-02 | 2 | `cursor >= bafResolvedDay`: day-of-resolution INCLUDED; pre-resolution wins still EXCLUDED (no forward leak). |
| BAF-ROUTE-03 | 3 | RngLocked guard fires at `level=10 + rngLocked + lastPurchaseDay`: claim reverts `RngLocked`, deposit reverts `CoinflipLocked`; requires the full conjunction. |
| BAF-ROUTE-04 | 3 | Guard does NOT fire at `level=5` or with `rngLocked=false`. |
| BAF-ROUTE-05 | 2 | Jackpot-phase override at `level=10` routes credit to bracket 20; no override at `level=15`. |
| BAF-ROUTE-06 | 1 | Post-jackpot era-11 purchase claim routes via `purchaseLevel_=11` → bracket 20 (parity with the override path). |
| BAF-ROUTE-07 | 1 | Era-7 jackpot phase credits bracket 10 (override does NOT fire; still-open bracket). |
| BAF-ROUTE-08 | 1 | `markBafSkipped` bumps `lastBafResolvedDay` and post-skip day-D claims route to bracket 20 identically to the `runBafJackpot` path. |

All 14 pass under `npx hardhat test test/edge/BafCreditRouting.test.js`.

**Approach:** drive one organic VRF cycle to produce a real winning flip for alice, then use `hardhat_setStorageAt` to seed slot-0 of the game's packed state (`level` + `jackpotPhaseFlag` + `lastPurchaseDay` + `rngLockedFlag`) and slot-5 of DegenerusJackpots (`lastBafResolvedDay`). BAF-ROUTE-08 additionally impersonates the game address via `hardhat_impersonateAccount` to invoke `onlyGame`-gated `markBafSkipped`. Same pattern as `test/fuzz/BafRebuyReconciliation.t.sol`.

## Security property verified

`bafTotals[N]` cannot be mutated after `_requestRng` for the era-N boundary. Composes:

1. **Level-bump atomicity** in `_finalizeRngRequest` (`AdvanceModule.sol:1601, 1610`): `rngLockedFlag = true` and `level = N` in the same call.
2. **Lock predicate** (`BurnieCoinflip.sol:585-598` + `:1035-1045`): blocks claims and deposits during the RNG-wait window at x10 boundaries (BAF-ROUTE-03a/b verifies the positive case; BAF-ROUTE-04 verifies it doesn't over-fire).
3. **Cursor filter** (`BurnieCoinflip.sol:525`): excludes pre-resolution wins on later claims (BAF-ROUTE-02b verifies no forward leak).
4. **bafLevel override** (`BurnieCoinflip.sol:594-598`): redirects post-BAF writes from the dead bracket to N+10 (BAF-ROUTE-05a + BAF-ROUTE-08 verify both runBafJackpot and markBafSkipped paths converge).

## Out of scope

- Gas analysis of the new override branch + the added `level()` SLOAD in `_coinflipLockedDuringTransition`. Separate task per `feedback_gas_worst_case.md`.
- Cross-era leak proof via a multi-era driven sequence. The matrix-by-condition coverage above is sufficient; the multi-era proof would just compose those cases.
- Adversarial pass / FINDINGS doc / closure signal. Per the minimal-scaffold disposition, this phase folds into the next full milestone's delta audit naturally.

## Process notes

Approval discipline followed `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` + `feedback_manual_review_before_push.md`. Two USER-APPROVED commits (initial contracts+tests, then BAF-ROUTE-06/07/08 expansion); two AGENT-COMMITTED planning updates (ROADMAP+STATE, then SUMMARY).
