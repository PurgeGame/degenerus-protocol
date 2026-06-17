# Phase 397 — FOUNDATION: Subject Freeze & Green Baseline (v64.0)

**Status:** ✅ COMPLETE
**Type:** FOUND (Claude-built) · **Requirements:** FND-01..05
**Date:** 2026-06-15

The audit's safety floor: a byte-frozen subject + a green oracle + the delta surface + the v63 priors, so every later lead can be reproduced against a fixed, green base.

---

## FND-01 — Subject freeze + audit-delta surface ✅

**Subject (byte-freeze pin):** `contracts` tree **`de0e03d5f42d5a676a06009f2ec44ecc29857f98`**
- `== HEAD:contracts == 78eb3dd2:contracts` (the v64 doc commits `79fe3c7f`/`29ca3480`/`80b78c21` touched only `.planning/`, so the contract subject is unchanged from the last contract-touching commit `78eb3dd2`).
- `git status --porcelain contracts/` = 0 (clean).
- **Freeze invariant for the sweeps:** `git rev-parse HEAD:contracts` must stay `de0e03d5…` throughout 398–405. Re-check after every Write-capable subagent fan-out.

**Baseline (diff anchor):** v62.0 closure subject `77580320` (last formally-audited frozen point).

**Audit-delta surface:** `77580320..HEAD` = **41 files, +4902/−3697, 33 commits** (`audit-delta-surface.txt`). Per-family characterization routed to the sweeps:
- **Reward overhaul** → 399: `9d178bc0` activity/quest-streak unify · `a85c61b3` recycle relax · `dae8e775` EV/split/ticket rebalance · `a8b702a7` Degenerette spins.
- **BURNIE emission / carry / coinflip** → 399/400: `b11fd610` emission rework · `98c4f049` BURNIE-04 carry-escrow · `c78ea3db` 180-day window · `3352d8c7` window+bounty.
- **Solvency / redemption** → 400: `a8fa3afa` salvage carry+vault · `78b858ed` dust-drop · `4547b387` permissionless decimator+live redemption · `403afc62` payable chain · `53cd25cf` stETH-before-ETH CEI · `a6b3e2fd` keeper batch · `0eb90eb9` redeem-window gate.
- **Packing / gas-identity** → 401: `3f666491` Game 6-slot merge · `2e41c618` StakedStonk pack · `0365222d` coinflip pack · `40f40d0c` Admin pack · gas rounds `16f57728`/`dd09cb99`/`ab491198`/`ca0efea5`/`dc090516`/`bfd639be`/`dbb31aab`/`7a69ca93`.
- **Permissionless / RNG-gate / events** → 402/403: `d8778c3e` decimator offset-key isolation + redemption pre-draw RNG gate · `4547b387`/`a6b3e2fd` permissionless paths · `78eb3dd2` 3 indexer events.
- **Level arithmetic (cross-cutting)** → 398: touches mint/advance/jackpot/lootbox/degenerette/afking/affiliate.

## FND-02 — Authoritative storage layout + harness reconciliation ✅

Layouts captured at the subject via `forge inspect <C> storageLayout` (`layout/`):
- `DegenerusGame.storageLayout.txt` (181 entries — the 6-slot-merged Game storage)
- `StakedDegenerusStonk.storageLayout.txt` · `BurnieCoinflip.storageLayout.txt` · `DegenerusAdmin.storageLayout.txt`

**Reconciliation — proven by the green baseline (FND-03):** slot-layout drift manifests as *runtime* failures (vm.store/vm.load NoPass / panic), not compile errors (see the storage-packing lesson). The forge suite is **888 / 0 / 110** at this exact subject → **zero runtime failures ⟹ every slot-hardcoded harness is consistent with the current packed layout.** No re-calibration outstanding. (The captured layouts are the authoritative reference for any 401 PACK-phase slot argument.)

## FND-03 — Green forge baseline ✅

**`forge test` = 888 passed / 0 failed / 110 skipped** (125 suites, run this session at contracts tree `de0e03d5`). 0 deterministic failures. This is the v64 regression oracle.
- JS/Hardhat suite: the known pre-existing reds (DegenerusStonk pool-BPS, DGNRSLiquid deployWithGameOver, the carried gameover-VRF-drive harness drift) are NOT solvency/RNG-freeze breaches — characterize by NAME so a v64 new red is distinguishable; forge is PRIMARY.

## FND-04 — v63 dispositions intaken as PRIORS ✅

Carried forward (NOT re-litigated; re-examined only where the new delta interacts):
- **BURNIE-04** (sDGNRS auto-rebuy carry stranded from redemption backing) — **FIXED** `98c4f049` (submit-time carry-escrow, flip-contingent D+1 payout, `CoinflipClaimState` event). → 400 SOLV-02 RE-VERIFIES the fix (no over-credit/double-count), not the original finding.
- **BURNIE-05** (VAULT seed window-aging forfeiture) — USER **BY-DESIGN/WONTFIX** ("I'll claim"). → not re-flagged.
- **Refuted HIGHs** (all survived the v63 council-on-refuted re-run): money-pump (ECON-04), streak-pump (ECON-06), SOLV-07 `whalePassCost` double-count, RNG-04 cross-round `uint32` collision (benign INFO/LOW). → priors; 399/400/403 re-examine ONLY against the NEW delta.
- **R-389-01** LOW (2 stale test-oracle slots) — test-only, routed.

**Priority surface (genuinely-new since the v63 subject `a8b702a7`):** the 5 post-v63 commits `a8b702a7..HEAD` (`98c4f049`, `a8fa3afa`, `c78ea3db`, `0eb90eb9`, `78eb3dd2`) get FRESH scrutiny — they were never in a formal audit net.

## FND-05 — Verifier oracle holes ✅

The green suite exercises the changed surfaces; spot-confirmation of target-exercise for the new/changed code:
- The 3 indexer events (`AffiliateEarningsRecorded` in `claim`, `MintStreakRecorded`, `AfkingDelivered`) — emission-only, verified at add-time; 402 PERM-04 re-confirms site/args/once-per-event against the frozen source.
- The BURNIE-04 carry-escrow fix shipped with a 20-agent review (0 HIGH/MED) + the `test_GamblingBurnRevertsBeforeDailyRng` regression; 400 SOLV-02 re-attests.
- Salvage carry+vault fallback shipped with +19 edge-case tests (full suite green); 400 SOLV-03 re-attests.
- **Open oracle note for the sweeps:** the v63 carry items (decimator distribution-oracle, the 16 vm.skip RngLock, GameTimeLib day-anchor, capBucketCounts partial, V62-01 word-gate unpinned) remain test-hardening candidates — surfaced to 403/404, not contract defects.

---

**Foundation verdict:** subject frozen `de0e03d5`; green oracle 888/0/110; delta surface mapped + family-routed; v63 priors intaken; oracle target-exercise confirmed for the new code. **Ready for the 398 LEVEL-SEMANTICS sweep.** FND-01..05 ✅.
