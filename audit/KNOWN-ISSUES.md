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

3 INFO findings from Phase 81. No HIGH, MEDIUM, or LOW.

- **DSC-01 (INFO):** v3.9 RNG commitment window proof describes reverted combined pool code (2bf830a2). Proof conclusions still valid -- FF-only is strictly simpler. Proof document needs rewriting before C4A audit.
- **DSC-02 (INFO):** `sampleFarFutureTickets` view function at DG:2681 reads from `_tqWriteKey` instead of `_tqFarFutureKey` for far-future levels. Off-chain consumers receive empty results. No on-chain impact.
- **DSC-03 (INFO):** NatSpec at GS:533 claims uint32 cap but code uses `unchecked` arithmetic. Overflow requires > total ETH supply -- physically infeasible.

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

