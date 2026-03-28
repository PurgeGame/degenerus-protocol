# Phase 140: Consolidated Adjudicated Findings Report

**Date:** 2026-03-28
**Adjudicator:** Synthesis agent applying official C4A severity rules
**Inputs:** 5 warden reports from Phase 139 (fresh-eyes specialist wardens)

---

## 1. Executive Summary

Five specialist wardens audited 152 attack surfaces across the Degenerus protocol:

- **RNG/VRF Warden:** 24 surfaces, 9 SAFE proofs, 3 INFO findings
- **Gas Ceiling Warden:** 31 surfaces, 8 SAFE proofs, 0 findings (3 INFO observations in SAFE proofs)
- **Money Correctness Warden:** 42 surfaces, 10 SAFE proofs, 0 findings (2 INFO observations)
- **Admin Resistance Warden:** 30 surfaces, 6 SAFE proofs, 3 INFO findings
- **Composition Warden:** 25 surfaces, 7 SAFE proofs, 0 findings

**Result:** 0 High, 0 Medium, 0 Low. All findings classified as QA or Rejected per C4A severity rules. **Zero payable severity-based findings in a C4A contest.**

---

## 2. C4A Severity Classification

Per D-01, each finding is classified using official C4A severity rules:

- **High:** Direct loss of funds or permanent freezing without user error
- **Medium:** Loss of funds under specific conditions, griefing with material impact, broken core functionality
- **QA (Quality Assurance):** Gas optimizations, code style, informational observations
- **Rejected:** Already documented in KNOWN-ISSUES, explicitly out of scope, invalid assumptions

### Findings Table

| ID | Source Warden | Original ID | Finding | C4A Severity | Rationale |
|----|--------------|-------------|---------|-------------|-----------|
| ADJ-01 | RNG/VRF | INFO-01 | Nudge mechanism allows marginal RNG influence via `reverseFlip` | **Rejected** | Documented in KNOWN-ISSUES.md under "Design Decisions" as an accepted design with correct economic gating. The nudge is purchased before VRF request (rngLockedFlag blocks post-request nudges), and the 1.5x compounding cost makes large nudge counts economically impractical. A C4A warden filing this would be rejected as a pre-disclosed known issue. |
| ADJ-02 | RNG/VRF | INFO-02 | Gameover prevrandao fallback has 1-bit validator bias | **Rejected** | Documented in KNOWN-ISSUES.md under "Design Decisions" as "Gameover prevrandao fallback." Triple edge case: gameover + VRF dead 3+ days + validator manipulation. Five committed VRF words provide bulk entropy. Impact is negligible and pre-disclosed. |
| ADJ-03 | RNG/VRF | INFO-03 | EntropyLib XOR-shift PRNG is not cryptographically uniform | **QA** | Not documented in KNOWN-ISSUES.md. However, the VRF seed makes exploitation infeasible: the PRNG is seeded from `keccak256(rngWord, player, day, amount)` -- a per-player, per-day, per-amount unique seed derived from VRF. The number of entropyStep calls per resolution is small (5-10). Statistical non-uniformity is astronomically small and not exploitable. This is an informational observation with no material impact -- classic QA finding. |
| ADJ-04 | Gas Ceiling | GAS-INFO-01 | `_backfillGapDays` loop bounded by VRF stall economics, not constant | **QA** | The gas warden noted that `_backfillGapDays` has no explicit iteration cap, relying on economic bounds (120-day liveness guard) rather than a constant. Worst-case practical is 120 gap days at ~9M gas, well within 30M block limit. This is a code quality observation -- the bound exists but is implicit rather than explicit. No exploit path. |
| ADJ-05 | Gas Ceiling | GAS-INFO-02 | `deityPassOwners` loop in `handleGameOverDrain` bounded by economics | **QA** | The deity pass refund loop iterates over `deityPassOwners.length`. Triangular pricing (21 ETH for 6 passes) makes 1000+ unique purchasers economically infeasible. At 500 purchasers: 13.15M gas (safe). This is an informational observation about implicit vs explicit loop bounds. |
| ADJ-06 | Gas Ceiling | GAS-INFO-03 | BAF scatter 50 rounds with external calls | **QA** | BAF scatter uses `BAF_SCATTER_ROUNDS = 50` with external view calls to `sampleTraitTicketsAtLevel`. Total ~5M gas. Bounded by constant. The warden flagged this as an INFO observation about gas consumption in the endgame module, not a vulnerability. |
| ADJ-07 | Gas Ceiling | CROSS-01 | `coinflip.processCoinflipPayouts` gas in advanceGame | **QA** | The gas warden noted that coinflip payout processing gas depends on pending flip count. The BurnieCoinflip contract uses a cursor pattern that processes 1 day's flips per call. Under VRF stall, gap days are backfilled individually. Bounded in practice. Informational. |
| ADJ-08 | Admin | INFO-01 | GNRUS vault owner gets +5% snapshot vote weight bonus | **QA** | Not separately documented in KNOWN-ISSUES.md (though GNRUS governance is described). The vault owner receives a bounded +5% bonus when voting in GNRUS charity governance. Impact is limited: GNRUS governance controls 2% of remaining unallocated GNRUS per level. No fund extraction path. Community can outvote at scale. This is a QA-level design observation. |
| ADJ-09 | Admin | INFO-02 | Lootbox RNG threshold has no upper bound check | **QA** | `setLootboxRngThreshold` only validates `newThreshold != 0`. Admin could set astronomically high threshold, delaying mid-day lootbox VRF requests. No fund impact -- lootboxes still resolve via daily VRF. Daily RNG and game advancement are unaffected. Classic admin trust assumption, QA severity. |
| ADJ-10 | Admin | INFO-03 | `wireVrf` is not one-shot (no re-invocation guard) | **QA** | `wireVrf` has no guard preventing re-call, but it is access-controlled to ADMIN only, and the ADMIN contract only calls it in the constructor. The governance path uses `updateVrfCoordinatorAndSub` instead. No separate exploit path exists. Informational code quality observation. |
| ADJ-11 | RNG/VRF | CROSS-01 | Lootbox EV multiplier snapshot timing inconsistency | **QA** | Players who purchase lootboxes before their activity score improves get the lower multiplier. The fallback to live score for legacy entries creates a minor inconsistency. No exploit path -- multiplier is capped (80%-135%, 10 ETH per account per level). Informational design observation. |
| ADJ-12 | RNG/VRF | CROSS-02 | Charity governance resolution during level increment | **QA** | `charityResolve.pickCharity(lvl-1)` external call during `_finalizeRngRequest` could stall game if GNRUS reverts. GNRUS is a known immutable compile-time constant address. Acceptable trust boundary. Informational. |
| ADJ-13 | Money | INFO-CD01 | stETH 1-2 wei rounding on Lido rebasing transfers | **Rejected** | Documented in KNOWN-ISSUES.md: "All rounding favors solvency." The 1-2 wei discrepancy per stETH transfer is economically negligible and structurally favorable to the protocol. Pre-disclosed. |
| ADJ-14 | Money | INFO-CD02 | Degenerette bet funds collection from claimable winnings | **QA** | The `_collectBetFunds` function correctly decrements `claimablePool` when claimable is used for bets. No money correctness issue. Pure informational observation about an existing code pattern. |

### Classification Summary

| C4A Severity | Count | Findings |
|-------------|-------|----------|
| High | 0 | -- |
| Medium | 0 | -- |
| Low | 0 | -- |
| QA | 11 | ADJ-03 through ADJ-12, ADJ-14 |
| Rejected | 3 | ADJ-01, ADJ-02, ADJ-13 |
| **Total** | **14** | All findings classified (per D-03) |

---

## 3. Duplicate Analysis

Per D-02, findings are grouped by root cause across wardens. C4A duplicate decay applies: first unique = 100% reward, duplicates split with decay.

### Root Cause Grouping

| Root Cause | Findings | Wardens | Duplicate? |
|-----------|----------|---------|-----------|
| Implicit loop bounds (economic rather than constant) | ADJ-04, ADJ-05 | Gas | No -- same warden, different loops |
| RNG design tradeoffs (accepted non-cryptographic properties) | ADJ-01, ADJ-02, ADJ-03 | RNG | No -- three distinct root causes (nudge design, prevrandao fallback, XOR-shift PRNG) |
| Admin parameter validation gaps | ADJ-09, ADJ-10 | Admin | No -- different functions, different missing validations |
| GNRUS governance weight asymmetry | ADJ-08 | Admin | Unique finding |
| External call gas/revert risk in advanceGame | ADJ-06, ADJ-07, ADJ-12 | Gas, RNG | Partial overlap -- ADJ-07 and ADJ-12 both concern external calls during advanceGame, but different contracts (BurnieCoinflip vs GNRUS). ADJ-06 is endgame-only. **Not duplicates** under C4A rules because the root causes are distinct external contracts. |
| Lootbox EV snapshot timing | ADJ-11 | RNG | Unique finding |
| stETH rounding | ADJ-13 | Money | Unique (and Rejected -- pre-disclosed) |
| Degenerette claimable usage | ADJ-14 | Money | Unique finding |

### Cross-Domain Duplicate Check (per D-07)

The composition warden produced 0 unique findings. The RNG warden's CROSS-01 (lootbox EV snapshot) and CROSS-02 (charity resolution) are classified the same as if filed by a primary-domain warden. No cross-domain finding duplicates a primary-domain finding.

**Result:** Zero duplicate pairs across wardens. All 14 findings have distinct root causes.

---

## 4. PoC Validation

Per D-04, PoC validation is conceptual since all wardens produced SAFE proofs rather than exploit PoCs. No Foundry PoCs were submitted because no exploitable vulnerability was found.

### SAFE Proof Catalogue (40 Total)

**RNG/VRF Warden (9 SAFE proofs):**

| # | SAFE Proof | Conclusion |
|---|-----------|------------|
| 1 | SAFE-01: Daily RNG commitment window | All player inputs committed before VRF request. Prize pools frozen. Ticket buffers swapped. |
| 2 | SAFE-02: Mid-day lootbox RNG commitment window | Lootbox inputs committed at purchase time. Index increment isolates future purchases. |
| 3 | SAFE-03: Coinflip resolution path | All coinflip inputs committed on prior days. VRF word committed via Chainlink. |
| 4 | SAFE-04: Gambling burn redemption resolution | Burns committed before VRF request (rngLocked gate). Roll derived from VRF word. |
| 5 | SAFE-05: VRF request ID validation and fulfillment routing | Strict coordinator validation. Request ID matching prevents replay. |
| 6 | SAFE-06: Lootbox RNG consumer chain | 1:1 index-to-word mapping. Per-player entropy via keccak mixing. |
| 7 | SAFE-07: rngLockedFlag mutual exclusion | Strict mutual exclusion between daily and mid-day VRF paths. |
| 8 | SAFE-08: Ticket queue double-buffer integrity | Double-buffer ensures temporal isolation of ticket purchases. |
| 9 | SAFE-09: Gap day backfill entropy independence | Gap day entropy derived from VRF word + day index. No player influence. |

**Gas Ceiling Warden (8 SAFE proofs):**

| # | SAFE Proof | Conclusion |
|---|-----------|------------|
| 1 | SAFE-01: advanceGame stage-return pattern | Single-stage execution via do-while(false). Max 14.5M gas, 52% headroom. |
| 2 | SAFE-02: Ticket processing write budget | WRITES_BUDGET_SAFE=550 bounds batch at ~14.5M gas. |
| 3 | SAFE-03: Daily jackpot winner caps | DAILY_ETH_MAX_WINNERS=321 at ~8.5M gas, 72% headroom. |
| 4 | SAFE-04: External call gas consumption | All external calls to known protocol contracts with bounded execution. |
| 5 | SAFE-05: Delegatecall gas forwarding | Module reverts propagate up. No gas-starvation scenario. |
| 6 | SAFE-06: Orphaned lootbox backfill bounded | Max ~240 indices at 25K/iter = 6M gas. Combined with gap backfill: 15M. |
| 7 | SAFE-07: Nudge cost loop economically bounded | 1.5^n cost makes >50 nudges practically impossible. Even 1000 iterations = 100K gas. |
| 8 | SAFE-08: Storage access patterns in hot paths | ~8 cold SLOADs per call = ~16.8K gas. Bounded. |

**Money Correctness Warden (10 SAFE proofs):**

| # | SAFE Proof | Conclusion |
|---|-----------|------------|
| 1 | SAFE-M01: Reentrancy on claimWinnings | Sentinel pattern blocks re-entry. CEI enforced. |
| 2 | SAFE-M02: Admin ETH extraction via swap | Value-neutral: ETH in = stETH out. |
| 3 | SAFE-M03: Admin ETH extraction via staking | Reserve guard protects player claims. |
| 4 | SAFE-M04: sDGNRS gambling burn solvency | 50% supply cap + segregation + supply reduction. Roll=175 covered. |
| 5 | SAFE-M05: Double-claim on gambling redemption | Claim deleted/zeroed before payment. |
| 6 | SAFE-M06: claimablePool accounting integrity | Symmetric increment/decrement across all paths. |
| 7 | SAFE-M07: Affiliate self-referral extraction | Self-referral routed to VAULT. Per-referrer cap enforced. |
| 8 | SAFE-M08: Vault owner fund extraction | Only pro-rata redemption or game purchases. |
| 9 | SAFE-M09: uint96 truncation in gambling claims | 160 ETH daily cap ensures well within uint96 range. |
| 10 | SAFE-M10: Prize pool frozen/pending accounting | Pending pools merged at level transition. No ETH lost. |

**Admin Resistance Warden (6 SAFE proofs):**

| # | SAFE Proof | Conclusion |
|---|-----------|------------|
| 1 | SAFE-1: Admin cannot extract ETH | Swap is value-neutral. Staking is reserve-protected. |
| 2 | SAFE-2: Admin cannot manipulate RNG | wireVrf is constructor-only. updateVrfCoordinator is governance-gated. |
| 3 | SAFE-3: Admin cannot grief active players | No admin function modifies game parameters or prizes. |
| 4 | SAFE-4: No ownership transfer / privilege escalation | No transferOwnership, no proxy, no selfdestruct. Immutable addresses. |
| 5 | SAFE-5: unwrapTo guard prevents vote-stacking | rngLocked blocks just-in-time sDGNRS minting. Supply frozen during VRF stall. |
| 6 | SAFE-6: yearSweep cannot be exploited | Time-locked post-gameover cleanup. Not admin-specific. |

**Composition Warden (7 SAFE proofs):**

| # | SAFE Proof | Conclusion |
|---|-----------|------------|
| 1 | RNG+Money: Jackpot manipulation | rngLockedFlag blocks all state changes during VRF window. |
| 2 | Admin+Gas: Parameter manipulation | No admin-modifiable parameter affects gas-sensitive loops. |
| 3 | RNG+Admin: VRF coordinator swap | 20h stall + governance vote + rngLocked guard on unwrapTo. |
| 4 | Money+Gas: Ticket queue DoS | Batched processing (550/call). Gas bounded. Economic cost to grow queue. |
| 5 | Money+Admin: Fund extraction | All admin ETH operations are value-neutral or value-preserving. |
| 6 | Flash loan governance | sDGNRS soulbound. No transfer. Flash loans impossible by construction. |
| 7 | Cross-contract reentrancy | CEI universal. Sentinel pattern on claims. Proportional calc on re-entry. |

---

## 5. Medium+ Disposition

Per D-01, Medium+ findings require FIX/DOCUMENT/DISPUTE disposition.

**Zero findings classified Medium or higher.** No FIX/DOCUMENT/DISPUTE dispositions are needed.

This section exists to satisfy SYNTH-04 explicitly: the 152-surface audit across 5 specialist wardens produced no findings meeting the C4A threshold for Medium (loss of funds under specific conditions, griefing with material impact, or broken core functionality) or High (direct loss of funds or permanent freezing).

---

## 6. KNOWN-ISSUES.md Gap Analysis

For each finding NOT already documented in KNOWN-ISSUES.md, assessment of whether it should be added to pre-empt C4A filings:

| Finding | In KNOWN-ISSUES? | Should Add? | Rationale |
|---------|-----------------|-------------|-----------|
| ADJ-01 (nudge RNG influence) | Yes (Design Decisions, reverseFlip/VRF swap governance) | No | Already covered |
| ADJ-02 (prevrandao fallback) | Yes (Design Decisions, "Gameover prevrandao fallback") | No | Already covered |
| ADJ-03 (EntropyLib XOR-shift) | **No** | **Yes** | A QA warden could file this as an informational finding about PRNG quality. Adding it pre-empts the filing and removes it from payable QA pool. |
| ADJ-04 (backfillGapDays bound) | No | No | Implicit gas bound is standard Solidity pattern. Filing this would be rejected as gas optimization, and the 9M worst case is well within limits. Not worth a KNOWN-ISSUES entry. |
| ADJ-05 (deityPassOwners bound) | No | No | Same reasoning as ADJ-04. Economic bound is sufficient. |
| ADJ-06 (BAF scatter gas) | No | No | Constant-bounded (50 rounds). Standard gas observation. |
| ADJ-07 (coinflip gas in advanceGame) | No | No | Cursor-bounded processing. Standard gas observation. |
| ADJ-08 (GNRUS vote bonus) | No | **Consider** | The +5% vault owner bonus is a design choice. However, it is implicitly covered by the broader GNRUS governance description in KNOWN-ISSUES (which discusses charity governance as non-extractive). Not strictly needed but adds defense-in-depth. |
| ADJ-09 (lootbox threshold no upper bound) | No | No | Admin trust assumption. `setLootboxRngThreshold` is operational. No fund impact even at extreme values. Standard admin-can-grief-themselves pattern. |
| ADJ-10 (wireVrf not one-shot) | No | No | Admin-only, constructor-only in practice. No separate exploit path. |
| ADJ-11 (lootbox EV snapshot) | No | No | Minor UX inconsistency, not a vulnerability. No fund impact. |
| ADJ-12 (charity resolution revert risk) | No | No | Known immutable contract. Acceptable trust boundary. |
| ADJ-13 (stETH rounding) | Yes ("All rounding favors solvency") | No | Already covered |
| ADJ-14 (degenerette claimable) | No | No | Correct behavior. Not a finding. |

### Recommended KNOWN-ISSUES.md Additions

**1. EntropyLib XOR-shift PRNG (ADJ-03)**

Recommended entry under "Design Decisions":

> **EntropyLib XOR-shift PRNG for lootbox outcome rolls.** `EntropyLib.entropyStep()` uses a 256-bit XOR-shift PRNG (shifts 7/9/8) for lootbox outcome derivation (target level, ticket counts, BURNIE amounts, boons). XOR-shift has known theoretical weaknesses (cannot produce zero state, fixed cycle, correlated consecutive outputs). Exploitation is infeasible: the PRNG is seeded per-player, per-day, per-amount via `keccak256(rngWord, player, day, amount)` where `rngWord` is VRF-derived. The small number of entropy steps per resolution (5-10) and modular arithmetic over small ranges further mask any non-uniformity.

**2. GNRUS vault owner +5% vote bonus (ADJ-08) -- optional**

Could be added under "Design Decisions" but is arguably already covered by the existing GNRUS governance context. The bonus is bounded, non-extractive, and community-outweighable. Left to project discretion.

---

## 7. Warden Coverage Summary

| Warden | Surfaces | SAFE Proofs | Findings | Cross-Domain |
|--------|----------|-------------|----------|-------------|
| RNG/VRF | 24 | 9 | 3 INFO | 2 (CROSS-01, CROSS-02) |
| Gas Ceiling | 31 | 8 | 3 INFO (in SAFE proofs) | 1 (CROSS-01) |
| Money | 42 | 10 | 2 INFO (cross-domain) | 0 |
| Admin | 30 | 6 | 3 INFO | 0 |
| Composition | 25 | 7 | 0 | N/A (cross-domain by definition) |
| **Total** | **152** | **40** | **14 observations** | **3** |

Note: The gas warden's 3 INFO findings are embedded within SAFE proofs (GAS-INFO-01/02/03) and the gas CROSS-01 observation. The money warden's 2 INFO findings are cross-domain observations (INFO-CD01/CD02). Total unique observations across all wardens: 14.

---

## 8. Contest Payout Projection

Based on 0 High, 0 Medium, 14 QA/Rejected observations:

- **Severity-based payouts:** $0. No findings meet the C4A Medium or High threshold.
- **QA report payouts:** QA reports may earn small fixed awards depending on contest structure (typically $50-200 per qualifying QA report). With 11 QA-grade observations (3 Rejected), a warden could consolidate these into a single QA submission. Maximum QA payout is capped at a small percentage of the contest pool.
- **Rejected findings:** The 3 Rejected findings (pre-disclosed in KNOWN-ISSUES.md) earn $0.

**Estimated total contest payout for valid findings: $0 for severity-based payouts.** QA-grade observations may earn minimal fixed awards but represent no material cost to the protocol.

---

## Source Warden Reports

All findings traced to their source reports:

1. `.planning/phases/139-fresh-eyes-wardens/139-01-warden-rng-report.md` -- RNG/VRF warden (ADJ-01, ADJ-02, ADJ-03, ADJ-11, ADJ-12)
2. `.planning/phases/139-fresh-eyes-wardens/139-02-warden-gas-report.md` -- Gas ceiling warden (ADJ-04, ADJ-05, ADJ-06, ADJ-07)
3. `.planning/phases/139-fresh-eyes-wardens/139-03-warden-money-report.md` -- Money correctness warden (ADJ-13, ADJ-14)
4. `.planning/phases/139-fresh-eyes-wardens/139-04-warden-admin-report.md` -- Admin resistance warden (ADJ-08, ADJ-09, ADJ-10)
5. `.planning/phases/139-fresh-eyes-wardens/139-05-warden-composition-report.md` -- Composition warden (0 unique findings; all composition surfaces SAFE)
