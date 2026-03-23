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

### v4.0 Ticket Lifecycle & RNG-Dependent Variable Re-Audit (2026-03-23)

51 INFO findings across 8 phases (81-88). No HIGH, MEDIUM, or LOW.

Two findings initially reported above INFO were withdrawn as false positives during Phase 87 audit:
- ~~DEC-01 (MEDIUM)~~: `decBucketOffsetPacked` collision between regular and terminal decimator -- withdrawn because regular decimator never resolves at a stalled level and `poolWei == 0` guard prevents access.
- ~~DGN-01 (LOW)~~: `_collectBetFunds` uses `<=` instead of `<` for claimable balance -- withdrawn because `<=` is intentional due to 1-wei sentinel in `claimableWinnings`.

Key findings by phase:
- **Phase 81 (Ticket Creation):** DSC-01 (stale v3.9 proof), DSC-02 (wrong key in sampleFarFutureTickets view), DSC-03 (NatSpec/unchecked mismatch)
- **Phase 82 (Ticket Processing):** P82-01 through P82-06 (byte offset, setter attribution, missing writer, line drifts)
- **Phase 83 (Winner Selection):** 0 new findings; DSC-01/DSC-02 independently re-confirmed
- **Phase 84 (Prize Pool):** DSC-84-01 through DSC-84-06 (slot shifts from boon packing, line drift, NatSpec gaps, freeze redirect caveat)
- **Phase 85 (Daily ETH Jackpot):** 9 new INFO (v3.8 slot/access discrepancies, line drifts, scope omission)
- **Phase 86 (Daily Coin+Ticket):** 6 new INFO (stale FF key claim, line drifts, duplicate winners by design, level arithmetic asymmetry)
- **Phase 87 (Other Jackpots):** 22 INFO + 2 withdrawn (earlybird dust/truncation/PRNG, BAF zero-score/dead code, decimator design patterns, degenerette auto-rebuy/decorative state/frozen guard)
- **Phase 88 (RNG Re-verification):** 0 new findings; 55/55 v3.8 rows confirmed SAFE, 27 slot shifts documented

See `audit/v4.0-findings-consolidated.md`.

### v3.7 VRF Path Audit (2026-03-22)

3 INFO findings across Phases 63-67. No HIGH, MEDIUM, or LOW.

- **V37-004 (INFO):** `rawFulfillRandomWords` mid-day branch does not update `lastLootboxRngWord`. Correct by design: variable is only consumed by ticket processing in `advanceGame`, which reads the word via mid-day drain path when needed.
- **V37-006 (INFO):** Gameover fallback `_getHistoricalRngFallback` uses `block.prevrandao` supplementary entropy. On Base L2, sequencer controls prevrandao (1-bit manipulation on binary outcomes). Edge-of-edge case: gameover + VRF dead 3+ days. 5 committed VRF words provide bulk entropy. **Intended emergency fallback — prevrandao is an acceptable trade-off when VRF is unavailable at gameover.**
- **V37-007 (INFO):** Level-0 `_getHistoricalRngFallback` returns prevrandao-only entropy (no historical VRF words exist). At level 0, no player positions exist to manipulate. **If this triggers, the game never actually started — no economic impact possible.**

See `audit/v3.7-vrf-core-findings.md`, `audit/v3.7-lootbox-rng-findings.md`, `audit/v3.7-vrf-stall-findings.md`.

### v3.6: VRF Stall Resilience (2026-03-22)

0 HIGH, 0 MEDIUM, 0 LOW, 2 INFO. Delta audit: all 8 attack surfaces SAFE. See `audit/v3.6-findings-consolidated.md`.

### v3.5: Final Polish (2026-03-22)

43 findings (10 LOW, 33 INFO) from comment correctness, gas optimization, and gas ceiling analysis. See `audit/v3.5-findings-consolidated.md`.

### v3.4: Lootbox + Skim Audit

5 findings (5 INFO). See `audit/v3.4-findings-consolidated.md`.

### v3.2: RNG Delta + Comment Re-scan

30 findings (6 LOW, 24 INFO). See `audit/v3.2-findings-consolidated.md`.

