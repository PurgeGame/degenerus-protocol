# Known Issues

Pre-disclosure for audit wardens. If you find something listed here, it's already known.

---

## Intentional Design (Not Bugs)

**stETH rounding strengthens invariant.** 1-2 wei per transfer retained by contract, pushing `balance >= claimablePool` further into safety. Not a leak.

**Non-VRF entropy for affiliate winner roll.** Deterministic seed (gas optimization). Worst case: player times purchases to direct affiliate credit to a different affiliate. No protocol value extraction.

---

## Design Mechanics

These are architectural decisions, not vulnerabilities.

**VRF swap governance.** Emergency VRF coordinator rotation requires a 20h+ stall and sDGNRS community approval with time-decaying threshold. Execution requires approve weight > reject weight and meeting the threshold -- reject voters holding more sDGNRS than approvers block the proposal. This is the intended trust model.

**Chainlink VRF V2.5 dependency.** Sole randomness source. If VRF goes down, the game stalls but no funds are lost. v3.6 adds automatic recovery: upon governance-gated coordinator swap, gap day RNG words are backfilled via keccak256(vrfWord, gapDay) and orphaned lootbox indices receive fallback words. Coinflips and lootboxes resolve naturally after backfill. Independent recovery paths: governance-based coordinator rotation (20h+ stall threshold) and 120-day inactivity timeout.

**Lido stETH dependency.** Prize pool growth depends on staking yield. If yield goes to zero, positive-sum margin disappears. Protocol remains solvent — the solvency invariant does not depend on yield.

**_sendToVault uses hard reverts (GO-05-F01).** `_sendToVault` reverts on any ETH or stETH transfer failure. Vault and sDGNRS are immutable protocol-owned contracts with unconditional `receive()` functions. Lido stETH has never paused transfers. Recipients can't reject funds.

---

## Audit History

### v3.7 Phase 63: VRF Request/Fulfillment Core (2026-03-22)

0 HIGH, 0 MEDIUM, 0 LOW, 2 INFO. All 4 VRF core requirements (VRFC-01 through VRFC-04) VERIFIED with 22 Foundry fuzz tests (1000 runs each, 0 failures). Slot 0 assembly audit: SAFE (0 of 8 assembly blocks touch packed VRF state). Gas budget: SAFE (~28k-47k vs 300k limit).

- **V37-001 (INFO):** `_tryRequestRng` gameover entry point not covered by VRFCore.t.sol. Low risk: shares `_finalizeRngRequest` with proven daily path. Deferred to Phase 65.
- **V37-002 (INFO):** Research documentation listed wrong storage slot numbers for `rngWordCurrent` and `vrfRequestId`. Corrected via `forge inspect` during test development. No contract code impact.

See `audit/v3.7-vrf-core-findings.md` for full findings document.

### v3.7 Phase 64: Lootbox RNG Lifecycle (2026-03-22)

0 HIGH, 0 MEDIUM, 0 LOW, 2 INFO. All 5 lootbox RNG lifecycle requirements (LBOX-01 through LBOX-05) VERIFIED with 21 Foundry fuzz tests (1000 runs each, 0 failures). Index mutation audit: 4 mutation sites verified (increment on fresh daily + mid-day, no increment on retry + swap). Word write audit: 5 write sites verified (daily, mid-day, stale, backfill, gameover). Zero-state guards: 4/5 sites guarded. Entropy derivation: unique per (player, day, amount) tuple via keccak256 preimage. Full lifecycle: purchase -> VRF -> open traced end-to-end.

- **V37-003 (INFO):** `_getHistoricalRngFallback` (AdvanceModule line 962) returns keccak256 output without explicit `if (word == 0) word = 1` guard. All other VRF word injection points have this guard. Probability of keccak256 returning 0 is 2^-256 (negligible). If triggered with zero nudges, would cause permanent RngNotReady for that lootbox index.
- **V37-004 (INFO):** `rawFulfillRandomWords` mid-day branch does not update `lastLootboxRngWord`. Correct by design: variable is only consumed by ticket processing in `advanceGame`, which reads the word via mid-day drain path when needed.

See `audit/v3.7-lootbox-rng-findings.md` for full findings document.

### v3.7 Phase 65: VRF Stall Edge Cases (2026-03-22)

0 HIGH, 0 MEDIUM, 0 LOW, 3 INFO. All 7 VRF stall edge case requirements (STALL-01 through STALL-07) VERIFIED with 17 Foundry fuzz/unit tests (1000 runs each, 0 failures). Gap backfill entropy: keccak256(vrfWord, gapDay) uniqueness verified. Gas ceiling: 120-day gap uses ~15M gas (2x margin under 30M block limit). Coordinator swap: 8/8 state variables correctly reset, 7 preserved variables audited with rationale. Zero-seed edge case: unreachable in any practical code path. Gameover fallback: prevrandao 1-bit bias documented as INFO (edge-of-edge trigger). DailyIdx timing: all block.timestamp usages consistent with context. V37-001 deferred coverage from Phase 63 resolved.

- **V37-005 (INFO):** Gap backfill manipulation window is identical to standard daily VRF callback-to-consumption window. Coinflip positions pre-committed before stall, lootbox purchases impossible during stall. No additional attack surface.
- **V37-006 (INFO):** Gameover fallback `_getHistoricalRngFallback` uses `block.prevrandao` supplementary entropy. On Base L2, sequencer controls prevrandao (1-bit manipulation on binary outcomes). Edge-of-edge case: gameover + VRF dead 3+ days. 5 committed VRF words provide bulk entropy.
- **V37-007 (INFO):** Level-0 `_getHistoricalRngFallback` returns prevrandao-only entropy (no historical VRF words exist). At level 0, no player positions exist to manipulate.

See `audit/v3.7-vrf-stall-findings.md` for full findings document.

### v3.6: VRF Stall Resilience (2026-03-22)

0 HIGH, 0 MEDIUM, 0 LOW, 2 INFO. Delta audit: all 8 attack surfaces SAFE. See `audit/v3.6-findings-consolidated.md`.

### v3.5: Final Polish (2026-03-22)

43 findings (10 LOW, 33 INFO) from comment correctness, gas optimization, and gas ceiling analysis. See `audit/v3.5-findings-consolidated.md`.

### v3.4: Lootbox + Skim Audit

5 findings (5 INFO). See `audit/v3.4-findings-consolidated.md`.

### v3.2: RNG Delta + Comment Re-scan

30 findings (6 LOW, 24 INFO). See `audit/v3.2-findings-consolidated.md`.

