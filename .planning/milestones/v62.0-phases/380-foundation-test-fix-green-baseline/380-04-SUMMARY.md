---
phase: 380-foundation-test-fix-green-baseline
plan: 04
subsystem: testing
tags: [forge, hardhat, green-baseline, regression-baseline-v62, slot-recalibration, event-schema, finding-candidates, c4d48008]

# Dependency graph
requires:
  - phase: 380-foundation-test-fix-green-baseline (plans 01, 02, 03)
    provides: "the slot-recalibrated / event-schema-refreshed / deity-realigned / seeded-invariant test net + deferred-items.md (DEF-380-02-01 gameover-VRF drive, DEF-380-03-01 VRFPath invariants)"
provides:
  - "test/REGRESSION-BASELINE-v62.md — the GREEN full-suite baseline at subject c4d48008 (790 passed / 3 carried bucket-A invariant / 109 skipped), SUPERSEDING the carried-red REGRESSION-BASELINE-v61.md by-name non-widening ledger"
  - "0 deterministic test* failures across the full forge suite (every wave-1 carried red fixed-green or justified-skip-and-recorded)"
  - "6 finding-candidate vm.skip(true) routes (DEF-380-04-FC1..FC6) enumerated for the council (382+ PRIME/ASYMMETRY/VRF-path sweeps)"
affects: [381-invariant-fuzz, 382-prime, 383-asymmetry, 384-compo, 385-loop, 386-periph, 387-terminal, council-sweeps]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "GREEN baseline discipline: 0 deterministic failures is the signal (replaces v61's large-red-count + by-name non-widening diff); comparison still BY NAME, expected failing set empty except the ≤3 carried bucket-A invariants"
    - "Fix-vs-skip triage: re-derive the EXPECTED value/precondition from the FROZEN source where the divergence is stale (slot/event/value/drive); vm.skip + route to council ONLY where the test encodes a real invariant the frozen contract realizes differently and aligning would mask it"
    - "Empirical divergence probing: a throwaway probe replicating the test flow against the frozen subject distinguishes stale-expectation (fix) from genuine-divergence (finding-candidate) before deciding"

key-files:
  created:
    - "test/REGRESSION-BASELINE-v62.md"
  modified:
    - "test/fuzz/AffiliateDgnrsClaim.t.sol"
    - "test/fuzz/CoverageGap222.t.sol"
    - "test/fuzz/AfKingSubscription.t.sol"
    - "test/fuzz/PresaleBoxDrain.t.sol"
    - "test/fuzz/VRFLifecycle.t.sol"
    - "test/fuzz/LootboxBoonCoexistence.t.sol"
    - "test/fuzz/GameOverPathIsolation.t.sol"
    - "test/fuzz/TicketLifecycle.t.sol"
    - "test/fuzz/RngIndexDrainBinding.t.sol"
    - "test/fuzz/RngLockDeterminism.t.sol"
    - "test/fuzz/VRFPathCoverage.t.sol"

key-decisions:
  - "Plan 380-04 was already partially executed by a prior run (12 test(380-04) commits fixing gap-backfill keccak widths, day-width event sigs, slot offsets, churn drain-on-cancel, + FC1-FC4 finding-candidate skips) but never produced REGRESSION-BASELINE-v62.md or a SUMMARY; this run continued from that state — drove the 17 residual full-suite reds to disposition and authored the missing baseline + summary."
  - "Of the 17 residual reds: 12 deterministic test* (11 fixed-green by frozen-source re-derivation + 1 justified-skip FC5), 2 fuzz candidates (1 fixed-green sStonk-seed + 1 justified-skip FC6), 3 are the permitted carried bucket-A VRFPath invariants."
  - "The 25,250-ether-per-1.01-ETH-buy affiliate score magnitude (mint-qty-weighted, not ETH-capped) is a threat-surface OBSERVATION recorded for the council, not asserted by test_revertBelowMinScore (which only proves the 10-ether below-min revert gate via a zero-score affiliate)."
  - "The 3 carried bucket-A VRFPath invariants (allGapDaysBackfilled / rngUnlockedAfterSwap / stallRecoveryValid) are PROVEN carried: DegenerusGameAdvanceModule.sol is byte-identical 2bee6d6f -> b97a7a2e -> c4d48008, so they reproduce at the subject and are not v62 regressions (v61 §7 proved them pre-existing at 2bee6d6f)."
  - "Hardhat deterministic subset (test/unit + test/edge, explicit; NOT the broken npm-test adversarial glob; test:stat excluded) = 1110 passing / 117 failing / 5 pending; the 117 are pre-existing gameover-VRF-drive / RngStall / affiliate-cap harness families (none a solvency-insolvency or RNG-freeze BREACH), corroborating-only — the forge by-name GREEN is PRIMARY."

patterns-established:
  - "Pattern: distinguish a real divergence from a stale slot/event/value by probing the frozen contract's actual behavior, then PREFER a faithful re-derivation; reserve vm.skip+council-route for genuine intended-invariant mismatches and always record them as finding-candidates in the baseline"

requirements-completed: [FOUND-06]

# Metrics
duration: ~85min
completed: 2026-06-07
---

# Phase 380 Plan 04: Green Full-Suite Baseline (FOUND-06) Summary

**Drove the full forge suite to a GREEN baseline at subject c4d48008 (790 passed / 0 deterministic test* failures / 109 skipped; only the 3 carried bucket-A VRFPath invariants remain, proven pre-existing) — every wave-1 carried red fixed-green by re-derivation from the frozen source or justified-skip-and-routed to the council (6 finding-candidates DEF-380-04-FC1..FC6) — and authored REGRESSION-BASELINE-v62.md, SUPERSEDING the carried-red v61 by-name non-widening ledger so regressions are now caught by "0 failures". Contracts byte-frozen at bbffe99e throughout.**

## Performance

- **Duration:** ~85 min
- **Started:** 2026-06-07T20:23:45Z
- **Completed:** 2026-06-07T~21:50Z
- **Tasks:** 2 (full forge green-drive + Hardhat disposition / baseline authoring)
- **Files modified:** 11 test files (this run's 5 commits) + 1 baseline doc created; ZERO contract files

## Accomplishments

- **GREEN forge baseline at c4d48008: 790 passed / 3 failed / 109 skipped (902 total, 105 suites).** The
  ONLY 3 residual reds are the carried bucket-A non-deterministic VRFPath invariants — 0 deterministic
  `test*` failures, exactly the FOUND-06 signal.
- **Dispositioned all 17 residual full-suite reds** the gate inherited (12 deterministic `test*` + 2 fuzz
  candidates + the 3 carried invariants): **12 fixed-green** by re-deriving the expected value /
  precondition / slot / event / drive from the FROZEN source, **2 justified-skip-and-recorded** as
  finding-candidates (FC5 entropy-binding observability, FC6 mid-day-pending gap backfill).
- **Authored `test/REGRESSION-BASELINE-v62.md` (234 lines)** — names the subject c4d48008 + the byte-frozen
  fingerprint (tree `bbffe99e…` + content sha256 `6697ce86…`), the GREEN forge counts, the 3 carried
  bucket-A exceptions (proven carried via the byte-identical AdvanceModule), the 6 finding-candidate skips,
  the Hardhat subset result, and an explicit statement that it SUPERSEDES REGRESSION-BASELINE-v61.md.
- **Confirmed the 3 carried invariants reproduce at c4d48008** — `git diff 2bee6d6f c4d48008 --
  DegenerusGameAdvanceModule.sol` is EMPTY (the VRF/gap-backfill/stall/swap logic is byte-identical to the
  v60 closure where v61 §7 proved them pre-existing) → not v62 regressions.
- **Ran the Hardhat deterministic subset** (test/unit + test/edge, explicit) = 1110/117/5; characterized the
  117 as pre-existing gameover-VRF-drive / RngStall / affiliate-cap harness families (no solvency-insolvency
  or RNG-freeze breach), corroborating-only.
- **Contracts byte-frozen throughout** — tree `bbffe99ede11adadcabcc9b81295566176575d47` held across every
  commit; ContractAddresses.sol restored after the hardhat run; forge build clean on the restored fixture.

## Task Commits

This run continued a partially-executed 380-04 (the prior run had committed FC1-FC4 + the day-width/slot
fixes but never wrote the baseline/summary). This run's atomic commits:

1. **affiliate below-min gate + gnrus governance surface** — `578cf496` (test)
2. **crossing-refresh event sig + presale-box lootbox-rng slots** — `858577d7` (test)
3. **bootstrap buy-count + lootbox-boon storage schema** — `ab1885c6` (test)
4. **TraitsGenerated topic + lootbox-resolution-timing drive + FC5** — `1866f087` (test)
5. **sStonk redemption-fuzz seed + FC6** — `641f8cd7` (test)

_Baseline doc + this SUMMARY committed separately (the final metadata commit)._

Prior-run 380-04 commits folded into this gate's result: `ae71117b` (churn drain-on-cancel), `99899fa9`
(QuestStreakBonusAwarded uint24 + FC4), `89eb327b` (FC3), `0da5a5d6` (KeeperRewardRouting offsets),
`63461fba` (CoinflipStakeUpdated uint24), `64eeefdd` (Degenerette freeze bit + FC2), `f1b6a3b4`/`65bc117a`
(gap-backfill keccak uint24), `e45f807c` (FC1), `4c6be407` (PrizePoolFreeze).

## The 17-red disposition (the heart of FOUND-06)

### Fixed-green (frozen-source re-derivation) — 12

| test (suite) | cause → fix |
|---|---|
| `test_revertBelowMinScore` (AffiliateDgnrsClaim) | 1 buy now scores >> the 10-ether min (mint-qty-weighted); zero-score affiliate = faithful below-min case (BingoModule:226) |
| `test_gap_gnrus_propose_vote_paths`→`…_setCharity_vote_paths` (CoverageGap222) | frozen GNRUS has no propose(address)/vote(uint48,bool); poke the real setCharity + vote(uint8) guards |
| `testCrossingPassHolderRefreshedNotEvicted` (AfKingSubscription) | SubscriptionExtendedFree topic uint32→uint24 (type Day UDVT) |
| `test_PFIX02` / `test_PFIX03_Early` / `test_PFIX03_Tier` (PresaleBoxDrain) | lootboxRngPacked 37→36, lootboxRngWordByIndex 38→37, presaleBoxDgnrsPoolStart 33→32 (_lrIndex read the word-mapping root → empty box record) |
| `test_vrfLifecycle_levelAdvancement` (VRFLifecycle) | each 1.01-ETH buy → ~0.109 ETH nextPrizePool (forgiving-funding split); 200 buys (21.8 ETH) never crossed 50-ETH bootstrap; bumped to 480 |
| `test_lootboxBoonAppliedDespiteExistingCoinflipBoon` / `test_parametricAutoBuy_crossCategoryBoonFromLootbox` (LootboxBoonCoexistence) | boonPacked 61→58, lootbox-rng 37→36/38→37; v55 dropped lootboxDay + added lootboxPurchasePacked (slot 38) — seed scorePlus1=1 so the open rolls the EV multiplier |
| `testGameOverDrainsQueuedTickets` (GameOverPathIsolation) | TraitsGenerated topic 6-arg→slimmed 3-arg (address,uint256,uint32); test only COUNTS emissions |
| `testLootboxNearRollTicketsProcessed` (TicketLifecycle) | a full pre-open drive resolved buyer3's box (permissionless lootbox-resolution-timing) before the explicit open; seed the word directly so the box survives the roll |
| `testFuzz_RngLockDeterminism_StakedStonkRedemption` (RngLockDeterminism) | a buy no longer mints sDGNRS to the buyer → burn reverted → vm.assume(false) exhausted (0 runs); seed holder balance (slot 1)+totalSupply → 1000 runs |

### Justified-skip + routed to council — 6 finding-candidates (DEF-380-04-FC1..FC6)

FC1 mid-day-blocks-next-advance (VRFCore), FC2 Degenerette award match-key vs frozen score-key
(DegeneretteFreezeResolution), FC3 WWXRP +0.0004% `_wwxrpBonusBucket` uplift (DegeneretteResolveRepeg),
FC4 frozen cancel auto-claims+drains affiliateBase (V56SecUnmanipulable), FC5 entropy-binding no longer
observable in the slimmed TraitsGenerated event (RngIndexDrainBinding), FC6 mid-day-pending stall+swap
backfills zero gap days (VRFPathCoverage). FC1+FC4 authored by the prior run for FC2/FC3; FC5+FC6 authored
this run. Full rationale per-test in the `@dev` blocks + REGRESSION-BASELINE-v62.md §4.

### Carried bucket-A non-deterministic invariants (permitted) — 3

`invariant_allGapDaysBackfilled`, `invariant_rngUnlockedAfterSwap`, `invariant_stallRecoveryValid`
(VRFPathInvariants.inv.t.sol) — proven pre-existing (byte-identical AdvanceModule baseline→subject); same
VRF mid-day/stall/swap surface as FC1/FC6.

## Deviations from Plan

### Continuation of a partially-executed plan (process note, not a contract deviation)

Plan 380-04 had already been partially run (12 `test(380-04)` commits + FC1-FC4 skips present, but no
baseline doc and no SUMMARY) — this was NOT flagged in the spawn prompt. This run verified the prior state
(git log + clean working tree), did NOT redo the committed fixes, drove the 17 residual full-suite reds to
disposition, and authored the missing `REGRESSION-BASELINE-v62.md` + this SUMMARY. The plan's 2 tasks were
completed end-to-end against the actual subject state.

### Scope reconciliation: the gate inherited 17 residual reds (not the "0 except bucket-A" the prior run implied)

The prior run's FC1-FC4 + slot/event fixes did not reach "0 deterministic failures" — 17 reds remained at
this gate's start. Driving them down was exactly this gate's charge (the disposition policy). 11 were
deterministic fixes, 1 deterministic skip (FC5), 1 fuzz fix (sStonk), 1 fuzz skip (FC6); the 3 carried
invariants were confirmed pre-existing.

**Total contract changes:** 0 (subject byte-frozen at `bbffe99e…` throughout; no test made to pass by
editing a contract). The 11 test edits + the baseline doc are the gate's intended work.

## Contract-change-needed (NOT applied)

**None.** Every divergence is either a faithful test re-derivation against the frozen `c4d48008` source or a
documented finding-candidate skip routed to the council. The 6 finding-candidates (FC1-FC6) are
CANDIDATES for the council to adjudicate (382+) — they are NOT pre-judged as contract bugs, and no contract
was modified. The frozen subject is read-only here by hard constraint.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: affiliate-score-magnitude | contracts/DegenerusAffiliate.sol | a single 1.01-ETH affiliate buy produces ~25,250-ether `affiliateScore` (mint-quantity-weighted, ~2500× the ETH spent) — affiliate DGNRS allocation is decoupled from ETH spend by a large factor; observed while re-deriving test_revertBelowMinScore. Whether this is an intended scoring unit or an over-allocation/asymmetry is a council question (383 ASYMMETRY). Not asserted by the test; recorded here + in REGRESSION-BASELINE-v62.md for the sweep. |

(The 6 finding-candidates FC1-FC6 are the primary council hand-off — they are documented inline + in
REGRESSION-BASELINE-v62.md §4, not duplicated as threat_flags here.)

## Known Stubs

None. No stub/placeholder data introduced — all changes are test re-derivations to the frozen source,
storage-seed corrections, and documented finding-candidate skips.

## Next Phase Readiness

- **The GREEN full-suite baseline (REGRESSION-BASELINE-v62.md) is the audit oracle** for the council sweeps
  (382+): a future run showing any failing NAME beyond the 3 carried bucket-A invariants is a candidate
  regression. The "0 failures" signal replaces the v61 by-name non-widening diff.
- **6 finding-candidates (FC1-FC6) + the affiliate-score-magnitude threat flag are queued for the council**:
  FC1+FC6+the 3 carried invariants = the VRF mid-day/stall/swap surface (385); FC2/FC3 = Degenerette
  award/RTP (382); FC4 = afking strategic-sub no-farm (382/383); the affiliate-score magnitude = asymmetry
  (383).
- **One corroborating workstream remains (out of this gate's scope):** the Hardhat gameover-VRF-drive /
  RngStall harness recalibration (DEF-380-02-01's JS arm; 117 JS-subset failures, none a hard-floor breach).
- **Contracts byte-frozen** at `bbffe99ede11adadcabcc9b81295566176575d47`; STATE.md / ROADMAP.md left to the
  orchestrator.

## Self-Check: PASSED

- Created files exist: `test/REGRESSION-BASELINE-v62.md` (234 lines, >40 min), `380-04-SUMMARY.md`.
- Commits exist (this run): `578cf496`, `858577d7`, `ab1885c6`, `1866f087`, `641f8cd7` — all in `git log`.
- GREEN forge baseline verified: full `forge test` = 790 passed / 3 failed (only the named bucket-A
  invariants) / 109 skipped on a clean fixture.
- Contracts byte-frozen: tree `bbffe99ede11adadcabcc9b81295566176575d47`; `git status --porcelain
  contracts/` empty; ContractAddresses.sol restored after hardhat; forge build clean.
- STATE.md / ROADMAP.md NOT in any of this plan's commits (orchestrator-owned).

---
*Phase: 380-foundation-test-fix-green-baseline*
*Completed: 2026-06-07*
