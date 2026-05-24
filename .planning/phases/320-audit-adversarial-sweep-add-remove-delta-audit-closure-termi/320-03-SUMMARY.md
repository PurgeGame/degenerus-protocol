---
phase: 320-audit-adversarial-sweep-add-remove-delta-audit-closure-termi
plan: 03
status: complete
verdict: NON-WIDENING (0 contract regressions; 1 stale-test deferred v47)
suite: 565-pass-45-fail-16-skip
source_tree_frozen: true
---

# 320-03 SUMMARY — Regression + SOURCE-TREE FROZEN

## REG-01 NON-WIDENING
`git diff 62fb514b..HEAD -- contracts/ test/`: 14 contracts files + 36 test files, EVERY hunk attributable to a v46-scope commit (df4ef365 317 batch · e4014f91/795e679d GAS · 42140ceb/e1baa978 OPEN-E · 745cd63d fixture · 318-TST additions). v44 sStonk redemption core + v45 VRF-rotation logic byte-unchanged (v46 edits to those files confined to SUB-09 wiring + JGAS single-call). Zero unattributable hunks.

## Suite baseline — 565 pass / 45 fail / 16 skip (626 total)
The documented named baseline was 44 fail (held at 44 through Phase 319; 319-03: 549/44). At HEAD: 45 fail, suite grew 601→626 (+25 tests from 319/319.1). **44 of 45 failures are BYTE-IDENTICAL to the named 318-01 baseline** (TicketRouting ×12, QueueDoubleBuffer ×9, TicketEdgeCases ×2, PrizePoolFreeze ×2, DegeneretteFreezeResolution ×3, VRF fuzz ×2, lootbox/boon/drain ×5, GNRUS ×1, solvency/VRF invariants ×8). **The 45th = `CrankLeversAndPacking::testGas04PackingAndNoNewHotPathStorageSourcePresence` (panic 0x11) — a STALE v46-internal TEST**, NOT a contract regression: it asserts the pre-OPEN-E `Sub` 7-field/13-byte layout, but OPENE-01 (319.1, USER-APPROVED) collapsed the two standalone bools into `flags` + added `address fundingSource` (HEAD Sub = 6 fields, AfKing.sol:79-86). Contract correct (320-01 SWP-OPENE NEGATIVE-VERIFIED + 319.1 13/13); the gas source-presence assertion just wasn't updated for the repack. **ZERO v46 CONTRACT regressions.** Test-only fix deferred to v47.0.

## RNG-freeze + obligation retirement + faucet
- **§3 RNG-freeze intact** — RngNotReady guards re-grepped (DegeneretteModule:578/:452, LootboxModule:485/:567); crank relaxes WHO not WHEN; re-attests 318-05 13/13.
- **§4 freeze-obligation RETIREMENT** — RM-02 ETH-auto-rebuy removal deletes 1 VRF consumer + 3 player-mutable in-window inputs (confirmed: BurnieCoinflip.sol auto-rebuy/afKing-mode/deity machinery all deleted). Re-attests SAFE-04.
- **§5 faucet bounded** — SAFE-01 (CrankFaucetResistance) re-attested; round-trip ≤ 0, WWXRP zero, CR-01 box-peg 71_203 + WR-01 guard.

## Byte-unmodified attestations
- **§7 KNOWN-ISSUES.md** — `git diff 62fb514b..HEAD -- KNOWN-ISSUES.md` empty; sha256 `75b3b4bc…`.
- **§8 BURNIE win/loss RNG path** — `processCoinflipPayouts` (BurnieCoinflip.sol:756) + `bool win = (rngWord & 1) == 1;` (:788) byte-UNMODIFIED; the 106-line BurnieCoinflip delta is entirely RM-scope auto-rebuy removal, ZERO win/loss-resolution lines touched.

## §9 SOURCE-TREE FROZEN
`git diff 30b5c89c -- contracts/ test/` → empty. Zero in-phase contracts/+test/ mutation. No RE-PASS (H-CANCEL-SWAP-MISS + testGas04 both deferred to v47.0). FROZEN HELD.

## Self-Check: PASSED
Doc exists + verify PASS; NON-WIDENING (0 contract regressions); the +1 fail diagnosed as stale-test (testGas04, test-only); KNOWN-ISSUES + BURNIE-RNG byte-unmodified; SOURCE-TREE FROZEN confirmed empty.
