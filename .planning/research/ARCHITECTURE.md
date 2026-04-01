# Architecture Attack Surface Analysis for C4A Contest Dry Run

**Domain:** Delegatecall-based game protocol with shared storage, VRF randomness, stETH yield, soulbound governance
**Researched:** 2026-03-28
**Overall confidence:** HIGH (based on code review + prior audit history + external references)

---

## 1. Delegatecall Storage Collision / Corruption

### Attack Pattern

**How wardens attack this:** Verify that every module inheriting `DegenerusGameStorage` has zero additional state variables. Any module-declared storage variable occupies the same slot as a game variable, causing silent corruption. The classic attack (Pike Finance 2024, Fractional C4A 2022-07) involves re-initialization after slot corruption -- an attacker overwrites a nonce/initializer slot via delegatecall, then calls `initialize()` again to become owner.

**Attack Sequence:**
1. Identify any module contract that declares its own storage variable (even `private`)
2. Map that variable's slot to the corresponding `DegenerusGameStorage` slot
3. Find a module function that writes to that variable
4. Trigger delegatecall from `DegenerusGame` to that function
5. Observe corruption of the corresponding game state variable

**Prerequisites:** Module declares its own storage variable AND game dispatches to it via delegatecall.

**Expected Severity:** CRITICAL if found (direct state corruption). Most likely Medium-High in C4A terms.

**Degenerus-Specific Assessment:**

All 10 modules inherit `DegenerusGameStorage` as the sole storage source. The architecture uses a single-inheritance chain: `DegenerusGameStorage` -> `DegenerusGamePayoutUtils` -> `DegenerusGameMintStreakUtils` -> module. This is the correct pattern.

**Contracts at risk:**
- `DegenerusGameAdvanceModule.sol` -- largest module, most complex logic
- `DegenerusGameEndgameModule.sol` -- BAF scatter, reward jackpots
- `DegenerusGameMintModule.sol` -- ticket purchasing, ETH splitting
- All 10 modules in `contracts/modules/`

**Warden approach for this codebase:**
1. Run `forge inspect <Module> storage-layout` for every module and compare slot-by-slot against `DegenerusGame`
2. Grep for any `uint`, `mapping`, `bool`, `address` declarations in module files outside of function scope and outside of inherited contracts
3. Check utility contracts in the inheritance chain (`DegenerusGamePayoutUtils`, `DegenerusGameMintStreakUtils`) for accidental state variables
4. Verify constants are truly `constant` or `immutable` (not consuming storage slots)

**Existing mitigation (from prior audits):** v7.0 verified all 11 changed contract storage layouts via `forge inspect`. v5.0 ultimate adversarial audit covered all 29 contracts. This surface has been verified SAFE multiple times, but wardens will re-check because it is a mandatory first-pass check for any delegatecall architecture.

**Residual risk:** LOW. The codebase has been verified via `forge inspect` at multiple milestones. A warden would need to find a variable that all prior audits missed. Worth verifying one final time with automated slot comparison.

---

## 2. VRF Request/Fulfillment Manipulation

### Attack Pattern

**How wardens attack this:** The canonical VRF attack is manipulating state between `requestRandomWords` (commitment point) and `rawFulfillRandomWords` (fulfillment point). Any player-controllable variable that is (a) read during RNG-dependent calculations and (b) writable between request and fulfillment creates a manipulation window.

The Immunefi $300K VRF vulnerability (Obront/Trust, 2022) showed that a malicious VRF subscription owner could block and reroll randomness until receiving a desired value. The Sherlock LooksRare finding (2023-10) showed that `fulfillRandomWords` must not revert, as VRF will not retry.

**Attack Sequences:**

**2a. Commitment Window Exploitation:**
1. Observe VRF request (on-chain `requestRandomWords` call)
2. Before fulfillment arrives (1-3 blocks typically), modify state that affects outcome
3. VRF fulfills with randomness, but outcome is influenced by post-commitment state change

**2b. Fulfillment Revert (DoS):**
1. Create on-chain state that causes `rawFulfillRandomWords` to revert
2. VRF coordinator will not retry -- game permanently stalls
3. Governance swap is required to recover (20h+ stall threshold)

**2c. Fulfillment Gas Exhaustion:**
1. Create state requiring more gas than VRF callback gas limit (300k in this protocol)
2. Callback silently fails or reverts

**Prerequisites:** For 2a: writable state consumed by RNG logic. For 2b/2c: ability to force revert/gas-exceed in callback path.

**Expected Severity:** CRITICAL for 2a if exploitable. HIGH for 2b if achievable. MEDIUM for 2c.

**Degenerus-Specific Assessment:**

The `rawFulfillRandomWords` in `DegenerusGameAdvanceModule.sol` (line 1467) is deliberately minimal:
- Validates `msg.sender == vrfCoordinator` and `requestId == vrfRequestId`
- Silently returns (no revert) on mismatch: `if (requestId != vrfRequestId || rngWordCurrent != 0) return;`
- Stores the word (`rngWordCurrent = word`) or directly finalizes lootbox RNG
- No loops, no external calls, no complex logic -- cannot revert or gas-exhaust

**Contracts at risk:**
- `DegenerusGameAdvanceModule.sol` -- VRF callback and daily RNG processing
- `DegenerusGame.sol` -- dispatches `rawFulfillRandomWords` via delegatecall
- `StakedDegenerusStonk.sol` -- gambling burns blocked during `rngLockedFlag`
- `BurnieCoinflip.sol` -- coinflip resolution uses daily RNG words

**Warden approach for this codebase:**
1. Trace every variable consumed by RNG-dependent calculations (jackpot selection, coinflip, lootbox, decimator, ticket sampling)
2. For each variable, determine if it can be written by any external/public function between VRF request and fulfillment
3. Check the `rngLockedFlag` gate: does it block ALL relevant state changes?
4. Verify `rawFulfillRandomWords` cannot revert under any on-chain state
5. Check VRF gas budget (300k) against worst-case callback execution cost

**Existing mitigation:** v3.8 VRF commitment window audit verified 55 variables and 87 permissionless paths (51/51 SAFE). v3.7 proved `rawFulfillRandomWords` revert-safety and 300k gas budget is 6-10x sufficient. `rngLockedFlag` mutual exclusion verified airtight.

**Residual risk:** LOW. This is the most thoroughly audited surface in the protocol. A warden would need to find a variable or path missed across v3.7, v3.8, v4.0, and v4.1 audits. However, variables introduced in v3.9+ (far-future ticket changes) and v6.0+ (charity, boon packing, degenerette freeze fix) should be checked against commitment window proofs as delta additions.

---

## 3. Cross-Module State Inconsistencies in Shared Storage

### Attack Pattern

**How wardens attack this:** When multiple modules read/write the same storage variables via delegatecall, ordering and atomicity assumptions can break. The attack targets state transitions that span multiple delegatecall dispatches within a single transaction.

**Attack Sequences:**

**3a. Split-Transaction State Tearing:**
1. Module A writes partial state (e.g., updates a pool balance but not the accounting flag)
2. Execution returns to `DegenerusGame`
3. Module B is called and reads the partially-updated state
4. Inconsistency between balance and flag creates exploitable condition

**3b. Re-entrancy Through Module Boundaries:**
1. Module A makes an external call (e.g., ETH transfer via `.call{value:}`)
2. Re-entrant callback reaches `DegenerusGame` and dispatches to Module B
3. Module B reads storage that Module A hasn't finished updating (CEI violation across module boundary)

**3c. Flag Race Between Daily and Mid-Day RNG:**
1. Daily RNG sets `rngLockedFlag = true`
2. Mid-day lootbox RNG uses a different path but shares `vrfRequestId` and `rngRequestTime`
3. Interleaving could cause one path to consume the other's fulfillment

**Prerequisites:** Multiple delegatecalls within a single logical operation, or external calls between delegatecalls.

**Expected Severity:** HIGH if state tearing leads to fund extraction. MEDIUM for state inconsistency without direct loss.

**Degenerus-Specific Assessment:**

The architecture uses `advanceGame()` as the primary orchestrator, which makes sequential delegatecalls to advance, jackpot, endgame, and gameover modules. State consistency depends on the ordering of these calls within `advanceGame`.

Key shared state variables across modules:
- `currentPrizePool`, `prizePoolsPacked` (read/written by Mint, Jackpot, Endgame, GameOver)
- `claimablePool`, `claimableWinnings` (written by Jackpot, Endgame, GameOver; read by payout)
- `rngLockedFlag`, `rngWordCurrent`, `vrfRequestId` (Advance module primary, but read by guards everywhere)
- `jackpotPhaseFlag`, `jackpotCounter` (FSM state, drives module dispatch decisions)
- `prizePoolFrozen` (set during RNG request, cleared by `_unfreezePool`)

**Contracts at risk:**
- `DegenerusGame.sol` -- orchestrates module dispatch ordering
- `DegenerusGameJackpotModule.sol` -- daily ETH/coin/ticket distribution reads pool state
- `DegenerusGameEndgameModule.sol` -- BAF scatter, reward jackpots modify pools
- `DegenerusGameMintModule.sol` -- purchase ETH splitting writes to pools

**Warden approach for this codebase:**
1. Map all storage writes per module function (the existing STORAGE-WRITE-MAP.md from v5.0 covers this)
2. For each `advanceGame` code path, verify write ordering: does Module A's write complete before Module B reads?
3. Check for external calls between delegatecalls (CEI across module boundaries)
4. Verify `prizePoolFrozen` semantics: purchases during jackpot phase route correctly
5. Check the daily/mid-day RNG path separation: can fulfillments cross-contaminate?

**Existing mitigation:** v5.0 produced a complete STORAGE-WRITE-MAP.md. v4.4 found and fixed the BAF cache-overwrite bug (EndgameModule `runRewardJackpots`), which was exactly this class of vulnerability. CEI compliance verified post-v2.1.

**Residual risk:** LOW-MEDIUM. The BAF cache-overwrite bug (v4.4) proves this class is real for this codebase. While it was found and fixed, wardens will aggressively hunt for similar patterns. The split daily jackpot execution (`dailyJackpotCoinTicketsPending` flag) across multiple `advanceGame` calls is a particularly interesting attack surface because state consistency must hold across separate transactions.

---

## 4. stETH / Yield Integration Vulnerabilities

### Attack Pattern

**How wardens attack this:** stETH is a rebasing token -- balances change daily as staking yield accrues. The canonical vulnerability (Morpheus C4A 2025-08) is recording `transferFrom` amount instead of actual balance change. stETH transfers can deliver 1-2 wei less than requested due to share-based rounding.

**Attack Sequences:**

**4a. Rounding Drain (Wei Accumulation):**
1. Repeatedly transfer stETH in/out, accumulating 1-2 wei per operation
2. Over many operations, the protocol's accounting diverges from actual balance
3. Eventually, the last claimant cannot withdraw their full entitlement

**4b. Rebase Timing Exploitation:**
1. Deposit just before daily rebase (Lido rebase occurs ~12:00 UTC)
2. Claim yield share including the rebase
3. Withdraw immediately after

**4c. Share/Amount Mismatch:**
1. Protocol records amounts in wei but stETH internally tracks shares
2. Between recording and redemption, share value changes
3. Withdrawal sends different value than recorded

**Prerequisites:** Protocol stores stETH amounts (not shares) AND allows deposits/withdrawals.

**Expected Severity:** MEDIUM for rounding issues (small per-operation, but systemic). LOW for rebase timing (would need significant capital).

**Degenerus-Specific Assessment:**

`DegenerusVault.sol` integrates stETH through `deposit()` and `burnEth()`:
- Deposits pull stETH via `transferFrom` and accrue to DGVE share token
- Burns redeem proportional ETH + stETH (ETH preferred, then stETH for remainder)
- The vault uses a share-based model (DGVE) which naturally handles rebasing
- stETH is also received by `StakedDegenerusStonk.sol` for sDGNRS backing

The KNOWN-ISSUES.md already documents: "All rounding favors solvency. stETH transfers retain 1-2 wei per operation."

**Contracts at risk:**
- `DegenerusVault.sol` -- primary stETH integration point
- `StakedDegenerusStonk.sol` -- receives stETH deposits, sends stETH on burn
- `DegenerusGame.sol` -- `claimWinningsStethFirst()` path, yield surplus calculation

**Warden approach for this codebase:**
1. Check every `steth.transferFrom()` call: is the return value checked? Is actual balance change recorded vs requested amount?
2. Verify DGVE share math: can rounding allow a depositor to get more shares than fair value?
3. Check `burnEth()` ordering: ETH first then stETH -- can a front-runner drain ETH leaving only stETH (which has rounding)?
4. Look for stETH balance reads that don't account for pending rebases
5. Check yield surplus calculation in JackpotModule: does it use balance-of vs stored-amount?

**Existing mitigation:** KNOWN-ISSUES.md documents rounding behavior. The DGVE share model inherently handles rebasing (shares represent proportional ownership, not fixed amounts). Solvency invariant proven in v3.3 economic analysis. Rounding always favors solvency (rounds down on payouts, up on burns).

**Residual risk:** LOW. The share-based vault model is the correct integration pattern for rebasing tokens. Rounding is documented and favors solvency. A warden might file an INFO about the 1-2 wei retention, but it is pre-disclosed in KNOWN-ISSUES.md.

---

## 5. Soulbound Token Bypass Patterns

### Attack Pattern

**How wardens attack this:** Soulbound tokens (SBTs) lack `transfer()`, but bypass patterns exist:
1. **Wrapper arbitrage:** If a wrapper exists that mints transferable tokens backed by SBTs, the wrapper IS the transfer mechanism
2. **Burn-and-remint:** Burn SBT to extract underlying value, then re-acquire via different mechanism
3. **Approval/operator abuse:** If any approval mechanism exists, operator could act on behalf of holder
4. **Flash-loan voting:** Borrow transferable wrapper, unwrap to SBT, vote, re-wrap, return

**Attack Sequences:**

**5a. DGNRS Wrapper as Transfer Bypass:**
1. Acquire sDGNRS through gameplay rewards
2. This is soulbound -- cannot transfer
3. BUT: DGNRS (the wrapper) IS transferable
4. Admin/creator allocation flows: mint sDGNRS to DGNRS wrapper contract -> DGNRS is transferable ERC-20
5. Only the DGVE majority holder can `unwrapTo()` (convert DGNRS back to sDGNRS for specific recipients)

**5b. Governance Weight via Wrapper Cycling:**
1. Hold DGNRS (transferable)
2. `unwrapTo()` converts DGNRS to sDGNRS for a recipient
3. Recipient now has governance voting weight
4. After vote, burn sDGNRS to extract ETH/stETH/BURNIE
5. Repeat with different addresses

**5c. Burn-Redeem Value Extraction:**
1. Accumulate sDGNRS via gameplay
2. Burn for proportional ETH + stETH + BURNIE backing
3. The "soulbound" property only prevents transfers, not value extraction via burn
4. Economic attack: if burn value exceeds acquisition cost, rational actors drain reserves

**Prerequisites:** For 5a: access to DGNRS wrapper. For 5b: DGVE majority (admin). For 5c: sDGNRS balance.

**Expected Severity:** MEDIUM at most (5b is documented as WAR-01 in KNOWN-ISSUES). LOW for 5c (designed behavior).

**Degenerus-Specific Assessment:**

The sDGNRS/DGNRS split is intentionally designed:
- sDGNRS: soulbound, no `transfer()` function exists, holds all reserves, used for governance voting
- DGNRS: transferable ERC-20 wrapper, creator allocation only
- `unwrapTo()` restricted to DGVE majority holder AND blocked during VRF stalls
- `unwrapTo` block during VRF stalls prevents vote-stacking during governance

**Contracts at risk:**
- `StakedDegenerusStonk.sol` -- soulbound token with burn redemption
- `DegenerusStonk.sol` -- transferable wrapper, `unwrapTo()` entry point
- `DegenerusAdmin.sol` -- governance voting reads sDGNRS balances

**Warden approach for this codebase:**
1. Verify sDGNRS truly has no `transfer`/`transferFrom`/`approve` functions
2. Check if any contract can move sDGNRS between addresses (internal `_transfer` or equivalent)
3. Verify `unwrapTo` guard: is the VRF stall check correct? Can it be bypassed?
4. Check if `transferFromPool` (game-only) can be triggered by a player indirectly
5. Look for flash-loan attack on DGNRS: borrow DGNRS, unwrapTo sDGNRS, vote, burn sDGNRS for value, repay

**Existing mitigation:** `unwrapTo` blocked during VRF stalls (v2.1). `transferFromPool` is `onlyGame`. sDGNRS has no public transfer function. WAR-01 documents the admin bootstrap assumption.

**Residual risk:** LOW. The soulbound property is enforced at the contract level (no transfer function exists). The DGNRS wrapper is limited to creator allocation. The `unwrapTo` guard prevents governance manipulation. Wardens will verify these properties but are unlikely to find a bypass that prior audits missed.

---

## 6. Governance Vote Manipulation

### Attack Pattern

**How wardens attack this:** Token-weighted governance is vulnerable to vote concentration, flash loans, and timing attacks. The PartyDAO C4A finding showed a 51% majority could hijack governance by minting NFTs with astronomical voting power.

**Attack Sequences:**

**6a. Vote-Stacking Before Proposal:**
1. Accumulate DGNRS (transferable, can buy on market)
2. `unwrapTo()` to convert to sDGNRS voting weight
3. Propose VRF coordinator swap with malicious coordinator
4. Vote with accumulated weight
5. Execute swap -- now control all RNG

**6b. Snapshot Timing Attack:**
1. Governance snapshots circulating supply at proposal creation time
2. Acquire sDGNRS AFTER snapshot (lower denominator in threshold calculation)
3. Vote with weight not reflected in the snapshot denominator
4. Effective threshold is lower than intended

**6c. Cartel Attack at Low Participation:**
1. At day 6, VRF governance threshold drops to 5% (time-decay)
2. Colluding minority (5% of circulating sDGNRS) approves malicious swap
3. Community is inattentive or fragmented

**6d. Price Feed Governance with Live Supply:**
1. Price feed governance uses live circulating supply (not frozen snapshot)
2. During a feed stall, acquire sDGNRS via gameplay
3. Circulating supply grows, but your proportional weight is measured against the new larger supply
4. Alternatively: if sDGNRS burns are happening (reducing supply), your fixed weight gains more power

**Prerequisites:** For 6a: `unwrapTo` access (DGVE majority). For 6b: ability to acquire sDGNRS post-snapshot. For 6c: 5%+ sDGNRS. For 6d: active sDGNRS burns during feed governance.

**Expected Severity:** MEDIUM (WAR-01 and WAR-02 are already documented). Could be HIGH if a novel bypass is found.

**Degenerus-Specific Assessment:**

VRF governance in `DegenerusAdmin.sol`:
- Requires 20h+ VRF stall (admin) or 7d+ stall (community) before proposal
- Threshold decays from 50% to 5% over time
- `unwrapTo` blocked during VRF stalls (prevents vote-stacking during governance window)
- Changeable votes, approval voting across proposals
- Auto-invalidation on VRF recovery (stall re-check in every vote)

Price feed governance:
- Uses LIVE circulating supply (not frozen snapshot) -- intentional difference from VRF governance
- Requires 2d+ (admin) or 7d+ (community) feed-unhealthy period
- Defence-weighted threshold: 50% -> 15% floor over 4 days

**Contracts at risk:**
- `DegenerusAdmin.sol` -- all governance logic (VRF swap + price feed swap)
- `DegenerusStonk.sol` -- `unwrapTo()` entry point for vote-stacking
- `StakedDegenerusStonk.sol` -- provides `balanceOf` for vote weight

**Warden approach for this codebase:**
1. Verify snapshot timing: when is circulating supply captured? Can it be manipulated?
2. Check vote weight recording: is it balance-at-vote-time or balance-at-snapshot?
3. Verify `unwrapTo` VRF stall guard: exact conditions, edge cases (does the check trigger on the right stall state?)
4. Check price feed governance: live supply vs snapshot -- is this exploitable via burn-during-vote?
5. Look for proposal state transitions: can a proposal be executed after VRF recovery invalidates it?
6. Check `_executeSwap`: CEI compliance, can it be called twice?
7. Verify that votes are invalidated when VRF recovers during voting

**Existing mitigation:** WAR-01 (compromised admin + 7d inattention) and WAR-02 (5% cartel at day 6) are documented in KNOWN-ISSUES.md. `unwrapTo` stall guard verified in v2.1. `_executeSwap` CEI fixed post-v2.1. Auto-invalidation on VRF recovery verified. WAR-06 (admin spam-propose gas griefing) documented as Low.

**Residual risk:** LOW-MEDIUM. The governance design has documented known limitations (WAR-01, WAR-02, WAR-06) that are accepted risks. The price feed governance's live supply model is documented in KNOWN-ISSUES.md (DELTA-F-001). A warden filing any of these would be marked as a known issue. The risk is that a warden finds a novel governance manipulation path not covered by existing WAR findings.

---

## Cross-Cutting Attack: Multi-Contract Composition

Beyond the 6 individual surfaces, wardens will attempt composite attacks spanning multiple contracts:

### Composite Attack 1: VRF Stall + Governance + Fund Extraction
1. Trigger VRF stall (external -- Chainlink dependency)
2. Propose malicious coordinator swap during stall
3. If swap passes, new coordinator feeds biased randomness
4. Biased RNG manipulates jackpot outcomes for attacker

**Assessment:** Requires VRF stall (external dependency) + governance takeover (WAR-01/02). Double-gated. Documented.

### Composite Attack 2: Module State + Pool Manipulation
1. During `advanceGame`, delegatecall to JackpotModule reads `currentPrizePool`
2. Before jackpot resolution, MintModule purchase writes to pools
3. Cross-module pool state could be inconsistent during split jackpot execution

**Assessment:** `advanceGame` is the sole entry point for both paths, and purchases are blocked during jackpot phase (`jackpotPhaseFlag` guard). Purchases during split-jackpot pending state route through `prizePoolFrozen` accumulator. Verified safe.

### Composite Attack 3: sDGNRS Burn + VRF Timing
1. Submit sDGNRS gambling burn (enters pending queue)
2. Burns are resolved by RNG roll during `advanceGame`
3. If burn amount affects pool balances read during jackpot resolution in same tx, ordering matters

**Assessment:** Burns block during `rngLockedFlag`. Gambling burn resolution happens in `advanceGame` after RNG fulfillment. Ordering verified in v3.3 (CP-06, CP-07, CP-08 fixes).

### Composite Attack 4: stETH Rebase + Yield Surplus Calculation
1. Yield surplus calculation reads stETH balance
2. If called in same block as a rebase, surplus amount may differ from expected
3. Could over- or under-allocate to CHARITY / VAULT / SDGNRS

**Assessment:** Yield surplus is calculated during `consolidatePrizePools()` at level transition. stETH rebase is oracle-driven and occurs once per day. Surplus calculation uses `address(this).balance + steth.balanceOf(address(this)) - obligations`. Even if called in same block as rebase, the balance is still accurate (just includes/excludes the rebase). Rounding favors solvency.

---

## Summary: Priority Ranking for C4A Wardens

| Rank | Surface | Likely Warden Time Spent | Risk of Payable Finding | Key Contracts |
|------|---------|--------------------------|------------------------|---------------|
| 1 | Cross-module state (split-transaction) | HIGH | LOW-MEDIUM | Game, JackpotModule, EndgameModule |
| 2 | VRF commitment window | HIGH | LOW | AdvanceModule, Game |
| 3 | Governance manipulation | MEDIUM | LOW (known issues block most) | DegenerusAdmin, DegenerusStonk |
| 4 | Delegatecall storage collision | LOW (automated check) | LOW | All 10 modules |
| 5 | stETH rounding/integration | LOW | LOW | DegenerusVault, StakedDegenerusStonk |
| 6 | Soulbound bypass | LOW | LOW | StakedDegenerusStonk, DegenerusStonk |

**Most dangerous unknown:** A cross-module state inconsistency during the split daily jackpot execution path (`dailyJackpotCoinTicketsPending`), or a variable missed in the VRF commitment window audit that was introduced in later milestones (v3.9+, v4.x, v6.0). Delta additions after the v3.8 commitment window audit include:
- v3.9: `TICKET_FAR_FUTURE_BIT`, `_tqFarFutureKey` routing, combined pool jackpot selection, `rngLocked` guard with `phaseTransitionActive` exemption
- v6.0: DegenerusCharity integration (resolveLevel hook, yield split), degenerette freeze fix routing
- v3.8: boon storage packing (29 per-player mappings -> 2-slot struct)

All of these were delta-audited at their respective milestones, but a fresh-eyes warden may find something the delta approach missed.

---

## Past C4A Contests with Similar Architecture

| Contest | Architecture | Key Finding | Relevance |
|---------|-------------|-------------|-----------|
| Fractional 2022-07 | delegatecall vault | Storage collision via nonce overwrite enabling re-initialization | Direct -- same delegatecall pattern |
| Forgeries 2022-12 | VRF integration | Underfunded VRF subscription timing attack | VRF lifecycle management |
| Superposition 2024-08 | Diamond proxy shared storage | Cross-facet state inconsistency | Shared storage module pattern |
| PartyDAO 2023-10 | Token governance | 51% majority minted governance NFT with astronomical voting power | Governance manipulation class |
| Morpheus 2025-08 | stETH integration | Balance difference vs transfer amount rounding on stETH | stETH integration pattern |
| Pike Finance 2024 (real exploit, not C4A) | Upgradeable proxy | Storage collision from added pause functions, re-initialization | delegatecall storage corruption in production |

---

## References

- [Fractional C4A Storage Collision Finding](https://github.com/code-423n4/2022-07-fractional-findings/issues/418)
- [Chainlink VRF V2 Best Practices](https://docs.chain.link/vrf/v2/best-practices)
- [Chainlink VRF $300K Vulnerability (Immunefi)](https://blog.chain.link/smart-contract-research-case-study/)
- [LooksRare fulfillRandomWords Revert (Sherlock 2023-10)](https://github.com/sherlock-audit/2023-10-looksrare-judging/issues/40)
- [Lido stETH Integration Guide](https://docs.lido.fi/guides/lido-tokens-integration-guide/)
- [Pike Finance Storage Collision (CertiK)](https://www.certik.com/resources/blog/pike-finance-incident-analysis)
- [PartyDAO Governance Finding (C4A 2023-10)](https://code4rena.com/reports/2023-10-party)
- [Diamond Proxy Storage Pattern](https://medium.com/1milliondevs/new-storage-layout-for-proxy-contracts-and-diamonds-98d01d0eadb)
- [Halborn Delegatecall Vulnerabilities](https://www.halborn.com/blog/post/delegatecall-vulnerabilities-in-solidity)
- [NDSS 2024 Storage Collision Detection Paper](https://www.ndss-symposium.org/wp-content/uploads/2024-713-paper.pdf)
- [Cyfrin Chainlink Oracle DeFi Attacks](https://medium.com/cyfrin/chainlink-oracle-defi-attacks-93b6cb6541bf)
