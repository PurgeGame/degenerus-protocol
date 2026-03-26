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

**Chainlink VRF V2.5 dependency.** Sole randomness source. If VRF goes down, the game stalls but no funds are lost. Upon governance-gated coordinator swap, gap day RNG words are backfilled via keccak256(vrfWord, gapDay) and orphaned lootbox indices receive fallback words. Coinflips and lootboxes resolve naturally after backfill. Independent recovery paths: governance-based coordinator rotation (20h+ stall threshold) and 120-day inactivity timeout.

**Lido stETH dependency.** Prize pool growth depends on staking yield. If yield goes to zero, positive-sum margin disappears. Protocol remains solvent -- the solvency invariant does not depend on yield.

**Gameover prevrandao fallback.** `_getHistoricalRngFallback` uses `block.prevrandao` as supplementary entropy when VRF is unavailable at game over. A block proposer can bias prevrandao (1-bit manipulation on binary outcomes). Edge-of-edge case: gameover + VRF dead 3+ days. 5 committed VRF words provide bulk entropy.

---

## v7.0 Delta Audit (GNRUS + v6.0 Changes)

v7.0 delta adversarial audit completed 2026-03-26 covering GNRUS (new contract, 17 functions) and 11 modified contracts (48 entries). Three-agent adversarial methodology (Mad Genius / Skeptic / Taskmaster) with 100% coverage of all changed functions.

**Result: 0 open actionable findings.**

3 findings were identified and fixed:
- **GOV-01** (permissionless resolveLevel desync) -- fixed in commit 1f65cc1c: renamed to `pickCharity` with `onlyGame` modifier.
- **GH-02** (same root cause as GOV-01) -- fixed in same commit.
- **GH-01** (Path A burnAtGameOver omission) -- fixed in commit ba89d160: `burnAtGameOver` calls moved before the Path A early return in `handleGameOverDrain`.

4 findings are informational design intent (GOV-02, GOV-03, GOV-04, AFF-01) with no action required.

**Nice-to-have note (not a vulnerability):** Prior to the GH-01 fix, Path A of `handleGameOverDrain` did not call `burnAtGameOver` on the GNRUS contract. Path A is practically unreachable (requires `available == 0`, meaning the game's entire ETH+stETH balance is consumed by existing claimable winnings) and amounts would be trivial. This was fixed in commit ba89d160 so both terminal paths now invoke `burnAtGameOver`.

Full report: `audit/delta-v7/CONSOLIDATED-FINDINGS.md`

