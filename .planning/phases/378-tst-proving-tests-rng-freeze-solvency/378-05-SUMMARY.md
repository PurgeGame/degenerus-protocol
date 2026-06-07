---
phase: 378-tst-proving-tests-rng-freeze-solvency
plan: 05
subsystem: testing
tags: [foundry, forge, cashout-curse, cure, decurse, deity-smite, bounty-stamp, non-widening, by-name, proving-tests, expectemit]

# Dependency graph
requires:
  - phase: 376-impl-the-one-batched-contract-diff
    provides: "the shipped v61 impl (b97a7a2e) — _clearCurse cure-before-score in _purchaseForWith, _recordLootboxMintDay lootbox bounty stamp, decurse (100 BURNIE), smite (200 BURNIE + ownerOf gate + active-afker immunity + 5-stack ceiling), the shared CURSE_COUNT_SHIFT=215 counter"
  - phase: 378-01-tst-foundation
    provides: "the 2bee6d6f baseline red union BY NAME (172 names) + the non-widening rule + the authoritative v61 slot layout"
  - phase: 378-03-triage
    provides: "the accepted-staleness/accepted-behavior sets + the 3 documented class-(c) candidates (C-1/C-2)"
  - phase: 378-04-proving-tests
    provides: "the funded-sub + STAGE harness + canonical-layout seeders (curse/claimable/deity/affiliate/dailyIdx) reused by TST-04/05"
provides:
  - "V61CureBountyDecurse.t.sol — TST-04: cure on every purchase() host path (direct/batch/affiliate/lootbox>=ticket/ticket+lootbox bundle, fresh ETH AND claimable), cure-before-score by contrast (deity base), whale-bundle-no-cure by contrast, sub-ticket DAY_SHIFT bounty stamp (no cure), manual-lootbox bounty eligibility, decurse (100 BURNIE + Decursed emit + revert-if-0 + permissionless)"
  - "V61Smite.t.sol — TST-05: ownerOf gate (no burn), active-afker immunity (pre-burn), 5-stack ceiling (pre-burn), success (200 BURNIE + 2 stack + Smited), shared counter (cashout+smite on one counter), single-cure-clears-both (buy AND decurse), self-smite harmless"
  - "378-05-NONWIDENING-LEDGER.md — TST-06: live HEAD forge red set BY NAME, the union definition, the name-keyed set-diff (live - union == empty), the verdict, Hardhat documented limitation"
affects: [378-06-sec-rng-freeze-solvency, 379-terminal-delta-audit]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Cure-by-contrast on a deity base (8000 bps, read-only in the buy path so it survives a ticket buy): the curing buy ends un-penalized, an equal-curse sub-ticket buy ends penalized by curse*100 — isolates the cure-before-score ordering without the affiliate-cache clobber a single buy causes"
    - "Day-basis alignment for the bounty stamp: the ticket leg stamps lastEthDay = _currentMintDay() (dailyIdx) while the lootbox leg stamps _simulatedDayIndex() (wall clock) — the bounty test seeds dailyIdx to match the relevant basis (seed 100 for the ticket-leg test; align to currentDayView() for the lootbox-leg test)"
    - "Real soulbound deity-pass via the GAME-gated DegenerusDeityPass.mint(holder, tokenId) for the smite ownerOf gate (distinct from the mintPacked_ HAS_DEITY_PASS score-bonus bit)"
    - "Pre-burn validation proof: every smite revert leg reads the caller's coin.balanceOf before/after and asserts it UNCHANGED, proving the validation fires before burnCoin"
    - "TST-06 out-of-union triage: a non-destructive 2bee6d6f checkout (HEAD-only V61 files + WIP drafts moved aside, cache cleared) to REPRODUCE an out-of-union red at baseline — proving carried, not regression — then HARD-restore to HEAD"

key-files:
  created:
    - "test/fuzz/V61CureBountyDecurse.t.sol"
    - "test/fuzz/V61Smite.t.sol"
    - ".planning/phases/378-tst-proving-tests-rng-freeze-solvency/378-05-NONWIDENING-LEDGER.md"
  modified:
    - "test/REGRESSION-BASELINE-v61.md (folded the TST-06 final verdict into section 7)"

key-decisions:
  - "NON-WIDENING HOLDS: live HEAD 66 unique red names = 60 carried baseline-§3 + 3 documented class-(c) candidates + 3 carried VRFPath bucket-A invariants; live - union == empty BY NAME"
  - "The 3 VRFPath invariants (allGapDaysBackfilled/rngUnlockedAfterSwap/stallRecoveryValid) were surfaced out-of-union by the gate, then PROVEN PRE-EXISTING at 2bee6d6f via a non-destructive baseline checkout (byte-identical failure messages) — carried, NOT a v61 regression; the §3 union omitted them only because it enumerated test* names not invariant_*"
  - "A VRFPathHandler slot-stale hypothesis (lootboxRngIndex slot 37, dailyIdx read >>32, word-map slot 38) was investigated: recalibrating to the v61 layout (36/>>24/37) did NOT change the outcome and the baseline reproduces with its own handler, so the reds are a genuine pre-existing ghost-counter property — the recalibration probe was REVERTED (handler byte-identical to HEAD)"
  - "The cure (CURSE-04) lives ONLY in _purchaseForWith (the purchase() ticket/lootbox host); the separate purchaseWhaleBundle() pass-host does NOT cure (writes mintPacked_ field-isolated, never calls _clearCurse) — proven truthfully by contrast (a curse survives a whale-bundle pass-purchase)"
  - "No CONTRACT-CHANGE-NEEDED: TST-04 (13) + TST-05 (10) all green vs the shipped v61 impl; TST-06 non-widening holds"

patterns-established:
  - "Falsifiability spot-check per surface: invert one expected value (decurse exact-burn, whale-bundle no-cure, smite pre-burn no-burn, exact 200-burn, shared-counter sum), confirm FAIL, restore — per the T-378-05-01 mitigation"

requirements-completed: [TST-04, TST-05, TST-06]

# Metrics
duration: 66min
completed: 2026-06-07
---

# Phase 378 Plan 05: TST-04/05/06 (Cure+Bounty+Decurse · Smite · Final NON-WIDENING) Summary

**Two new forge proving tests (23 tests, all green against the shipped v61 impl) certify the cashout-curse CURE + bounty-stamp + permissionless decurse and deity-smite (ownerOf gate, active-afker immunity, 5-stack ceiling, 200-BURNIE burn, shared counter), and the binding TST-06 by-name non-widening gate HOLDS — live HEAD 66 red names == (172 baseline union + 3 documented candidates + 3 carried VRFPath invariants), `live − union == ∅`, ZERO new v61 contract regression, contracts byte-frozen (tree-hash `87e3b45b…`).**

## Performance

- **Duration:** ~66 min
- **Started:** 2026-06-07T09:36:57Z
- **Completed:** 2026-06-07T10:42:21Z
- **Tasks:** 3
- **Files created:** 2 test-only + 1 ledger; 1 baseline-doc modified

## Accomplishments

- **TST-04 (V61CureBountyDecurse.t.sol, 13 tests):** Proves the cure clears `curseCount` to 0 on every `purchase()` host path — direct ticket, batched buy, affiliate-coded buy, lootbox >= ticket, and a ticket+lootbox bundle — each twice (fresh ETH via DirectEth AND claimable via Claimable), asserting the cure is funding-agnostic (`totalCost >= priceWei`). Proves cure-BEFORE-score by contrast: a curing buy on a deity base (8000 bps, survives the buy) ends un-penalized while an equal-curse sub-ticket buy ends penalized by exactly `curse*100`. Proves the separate `purchaseWhaleBundle()` pass-host does NOT cure (a curse survives). Proves a sub-ticket buy stamps DAY_SHIFT (`bountyEligible` true) but does NOT cure, and a manual lootbox buyer becomes bounty-eligible. Proves decurse: clears + burns EXACTLY 100 BURNIE (`PRICE_COIN_UNIT/10`) + `Decursed(curer,target)` emit + revert-if-already-0 (no burn) + permissionless third-party clear.
- **TST-05 (V61Smite.t.sol, 10 tests):** Proves the `ownerOf(deityId)` gate rejects a non-deity caller with NO burn; an active-afker smitee (`dailyQuantity != 0`) reverts pre-burn (the sole immunity — no burn, no curse change); a smitee at the 5-stack ceiling (`curse >= 10`) reverts pre-burn (plus an 8→10 boundary + then-blocked proof); a successful smite burns EXACTLY 200 BURNIE (`PRICE_COIN_UNIT/5`) + adds one stack (+2) + emits `Smited(deityId,smitee)`; smite saturates at its own 10-point ceiling (can never reach the 20 counter cap — that cap is proven on the cashout path in V61CurseSet); cashout-curse and smite share ONE counter (4+2==6); a single >=1-ticket buy AND decurse each clear the combined total; self-smite is allowed/harmless. Every revert leg asserts the caller's BURNIE balance is unchanged (pre-burn validation).
- **TST-06 (378-05-NONWIDENING-LEDGER.md):** Ran the FULL forge suite at the v61 HEAD (711 passed / 66 unique failing NAMES / 103 skipped, clean cache). Computed the name-keyed set-diff `live − (172 baseline §3 ∪ 3 documented class-(c) ∪ 3 carried VRFPath invariants) == ∅` → **NON-WIDENING HOLDS**. 60 carried baseline + 3 documented C-1/C-2 + 3 carried VRFPath bucket-A invariants. 112 baseline names narrowed to green; 54 new proving tests (TST-01..05) additive green; the 2 untracked WIP gas drafts additive green. Verdict folded into `test/REGRESSION-BASELINE-v61.md` §7.
- **All 23 new tests pass against the shipped v61 impl** — the v61 contract behavior matches the design-lock spec; no contract change required.

## Task Commits

Each task committed atomically (test/docs-only, hooks run, not pushed):

1. **Task 1: TST-04 cure + bounty-stamp + decurse** — `01b827aa` (test)
2. **Task 2: TST-05 deity-smite** — `38e63ef4` (test)
3. **Task 3: TST-06 final NON-WIDENING ledger + baseline fold** — `097c9064` (docs)

**Plan metadata:** (this commit) `docs(378-05): complete TST-04/05/06 plan`

## Files Created/Modified

- `test/fuzz/V61CureBountyDecurse.t.sol` (481 lines, 13 tests) — TST-04 cure + bounty + decurse proof
- `test/fuzz/V61Smite.t.sol` (366 lines, 10 tests) — TST-05 deity-smite proof
- `.planning/phases/378-tst-proving-tests-rng-freeze-solvency/378-05-NONWIDENING-LEDGER.md` — TST-06 by-name ledger
- `test/REGRESSION-BASELINE-v61.md` (modified) — §7 TST-06 final verdict folded in

No `contracts/*.sol` modified (test-only phase; contract tree-hash `87e3b45b46879ec80c4fe6a689b4c17ccae482f1` / fingerprint `fcdd999ce2ddb0cac9e04b49242522b896cf56c67c18e213cd0f6dd5b6aa8aaf` preserved throughout; `git status --porcelain contracts/` empty at every commit).

## Decisions Made

- **No CONTRACT-CHANGE-NEEDED.** All 23 TST-04/05 assertions pass against the shipped v61 impl, and TST-06 non-widening holds (`live − union == ∅` by name). The PROVING_TEST escalation (a provably-correct failing test contradicting the spec) was NOT triggered.
- **The cure lives only in `_purchaseForWith`.** The CURSE-04 cure (`totalCost >= priceWei → _clearCurse`) is in the `purchase()` ticket/lootbox host. The separate `purchaseWhaleBundle()` pass-host writes `mintPacked_` field-isolated and never calls `_clearCurse`, so it preserves a curse. The plan prose's "whale bundle" cure path is the `purchase()`-host bundle (ticket+lootbox), proven; the pass-host non-cure is proven by contrast (truthful, falsifiable both ways).
- **The 3 out-of-union VRFPath invariants are carried, not a regression.** The gate surfaced `invariant_allGapDaysBackfilled` / `invariant_rngUnlockedAfterSwap` / `invariant_stallRecoveryValid` out-of-union. A decisive non-destructive `2bee6d6f` baseline checkout reproduced the SAME 3 failures with byte-identical messages → pre-existing. The §3 union omitted them only because it enumerated `test*` names, not `invariant_*`. Added as carried with the evidence; the union was NOT widened to hide a regression.
- **The VRFPathHandler slot-stale hypothesis was investigated and dismissed.** Recalibrating the handler's `lootboxRngIndex` (37→36), `dailyIdx` (>>32 → >>24), and word-map (38→37) reads to the v61 layout did NOT change the invariant outcome, and the baseline reproduces with its own handler — so the reds are a genuine pre-existing ghost-counter property, not a slot-read artifact. The recalibration probe was REVERTED (handler byte-identical to its HEAD-committed form — no spurious test edit).
- **Day-basis discipline for the bounty stamp.** The ticket leg stamps `lastEthDay = _currentMintDay()` (== dailyIdx) while the lootbox leg stamps `_simulatedDayIndex()` (wall clock); `_bountyEligible` gates on `gateIdx == dailyIdx`. The sub-ticket-stamp test keeps `dailyIdx = 100` (ticket-leg basis); the manual-lootbox test aligns `dailyIdx` to `currentDayView()` (lootbox-leg basis). This mirrors the 378-04 `dailyIdx`-vs-wall-clock lesson.

## Deviations from Plan

None affecting scope — the plan was executed as written (2 proving-test tasks + the TST-06 gate, each committed atomically). Test-side corrections applied during authoring (not contract deviations):

### Test-side corrections (within Task 1 / Task 2 authoring)

**1. [Test-setup] TST-04 sub-ticket buys must be in [100, 400) units (the 0.0025-ETH TICKET_MIN_BUYIN floor)**
- **Found during:** Task 1 (the sub-ticket bounty-stamp + the cure-before-score contrast)
- **Issue:** A 40-unit (0.1-ticket) buy reverts `E()` — `_callTicketPurchase` enforces `costWei >= TICKET_MIN_BUYIN_WEI (0.0025 ether)`; and a sub-`LOOTBOX_MIN` (0.005 ETH) lootbox reverts too. Also a 4000-unit batch was funded for 40 units (a test arithmetic slip).
- **Fix:** Use 200 ticket-units (0.005 ETH ∈ [0.0025, priceWei 0.01) — a valid sub-ticket below the cure threshold) for the no-cure legs; fund the batch with `_ticketCost(4000)`.
- **Verification:** 13/13 green.

**2. [Test-setup] TST-04 cure-before-score uses a deity base, not a seeded affiliate cache**
- **Found during:** Task 1 (the cure-before-score proof)
- **Issue:** A real ticket buy re-caches the affiliate points to the live (zero) value, clobbering a seeded `_seedAffiliateBase`, and a single buy builds no positive streak base — so both buyers read score 0 (the penalty floors a 0 base at 0). The contrast was vacuous.
- **Fix:** Use the deity-pass activity bonus (8000 bps, read from the HAS_DEITY_PASS bit which the buy path never rewrites) as the base; the deity exemption blocks the cashout SET but NOT the cure or the penalty APPLY, so a curing-vs-sub-ticket contrast isolates the cure's +`curse*100` effect.
- **Verification:** the cured buyer scores exactly `curse*100` higher than the equal-curse sub-ticket buyer.

**3. [Test-setup] TST-04 whale-bundle uses exactly the bundle price (no overpay)**
- **Found during:** Task 1 (the whale-bundle no-cure contrast)
- **Issue:** `purchaseWhaleBundle` reverts on OVER-payment (`msg.value > totalPrice`); sending 100 ETH for a 2.4-ETH bundle reverts.
- **Fix:** Send exactly 2.4 ETH (the early-price 1-bundle).

**4. [Unicode] Replaced `⇒`/`→` in string literals with ASCII** (Solidity rejects non-ASCII outside `unicode"..."`). Two strings in TST-04, one in TST-05. (Comments may keep Unicode; only string literals broke compilation.)

---

**Total deviations:** 0 contract deviations; 4 test-setup/authoring corrections (no scope change).
**Impact on plan:** None — all three surfaces proved exactly as specified; the TST-06 gate holds.

## Falsifiability Verification (T-378-05-01/02/03 mitigations)

Each surface had assertions confirmed falsifiable by temporary inversion (then restored; contracts re-verified clean):

- **TST-04:** Inverting the decurse exact-burn to `DECURSE_BURN/2` FAILED (`100e18 != 50e18` — the burn is genuinely exactly 100 BURNIE); inverting the whale-bundle no-cure to assert 0 FAILED (`6 != 0` — the curse genuinely survives the whale-bundle pass-purchase).
- **TST-05:** Inverting the active-afker pre-burn no-burn to assert a burn happened FAILED (`200e18 != 0` — the deity's BURNIE is genuinely untouched on the revert ⇒ validation is pre-burn); inverting the exact 200-burn to 100 FAILED; inverting the shared-counter sum to 2 FAILED (`6 != 2` — cashout 4 + smite 2 genuinely stack on one counter).
- **TST-06 (T-378-05-02/03):** The set-diff is name-keyed (a swapped red would appear in `live − union` by name); the union was NOT widened to force green — the 3 out-of-union VRFPath invariants were added as carried ONLY after a decisive baseline reproduction.

## Issues Encountered

- **`TICKET_MIN_BUYIN_WEI` (0.0025 ETH) + `LOOTBOX_MIN` (0.01 ETH) floors (TST-04):** resolved by using 200-unit sub-ticket buys (see Deviations).
- **Affiliate-cache clobber on a ticket buy (TST-04):** resolved by the deity-base contrast (see Deviations).
- **3 out-of-union VRFPath invariants (TST-06):** resolved by a decisive non-destructive baseline reproduction proving them pre-existing (see Decisions). The forge cache replay-failure corpus was cleared so the final run re-explored fresh.
- **Hardhat `npm test` cannot complete:** the `test/adversarial/*.test.js` glob is absent at both baseline and HEAD (documented env limitation per 378-01 §6). The runnable `test/unit` subset ran (930 pass / 67 fail / 3 pending — pre-existing families, corroborating); the forge by-name verdict is PRIMARY.

## User Setup Required

None — test-only phase, no external service configuration.

## Next Phase Readiness

- TST-04/05/06 are the last three of the six TST proofs (TST-01..06 now ALL complete). Ready for **378-06** (SEC-01 RNG-freeze + SEC-02 SOLVENCY-01 re-attestation). The reusable harness (curse/claimable/deity/affiliate seeders + the STAGE driver + the real-deity-pass mint + the BURNIE mint pattern + the pre-burn-balance assertion pattern) is established across V61CurseSet/V61CureBountyDecurse/V61Smite.
- The TST-06 non-widening ledger is the canonical certification (folded into `test/REGRESSION-BASELINE-v61.md` §7) — 379 TERMINAL's delta-audit re-attests against it.
- The contract subject remains byte-frozen (tree-hash `87e3b45b…`); these tests add green and characterize the v61 CURE/DECURSE/SMITE surfaces positively.
- No blockers.

## Self-Check: PASSED

- Files: V61CureBountyDecurse.t.sol, V61Smite.t.sol, 378-05-NONWIDENING-LEDGER.md, 378-05-SUMMARY.md — all FOUND.
- Commits: `01b827aa`, `38e63ef4`, `097c9064` — all FOUND in git history.
- Contract tree-hash `87e3b45b46879ec80c4fe6a689b4c17ccae482f1` (fingerprint `fcdd999c…`) — preserved; `git status --porcelain contracts/` empty.
- TST-04 13/13 green; TST-05 10/10 green; TST-06 `live − union == ∅` by name (NON-WIDENING HOLDS). Falsifiability spot-checked per surface.

---
*Phase: 378-tst-proving-tests-rng-freeze-solvency*
*Completed: 2026-06-07*
