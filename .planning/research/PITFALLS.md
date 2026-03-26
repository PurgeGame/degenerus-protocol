# Pitfalls Research

**Domain:** Solidity protocol extension -- adding DegenerusCharity contract, removing shared delegatecall storage variable, changing BPS splits, modifying freeze behavior, adding try/catch hooks, pruning dual test suites
**Researched:** 2026-03-25
**Confidence:** HIGH (based on direct codebase analysis + established Solidity security patterns)

---

## Critical Pitfalls

### Pitfall 1: Storage Slot Shift When Removing `lastLootboxRngWord` From Shared DelegateCall Layout

**What goes wrong:**
Removing `lastLootboxRngWord` (currently at slot 55 in `DegenerusGameStorage.sol`) shifts every subsequent variable down by one slot. Since `DegenerusGame`, `JackpotModule`, `MintModule`, and `EndgameModule` all inherit this layout and execute via delegatecall, any slot mismatch causes catastrophic storage corruption. `midDayTicketRngPending` (currently slot 56) would be read from slot 55, every `deityBoonDay` mapping would hash from a different base slot, and so on through all 78+ storage entries.

However, since this system is NOT upgradeable (no proxy -- fresh deploy every time), the actual slot-shift risk only materializes if some contracts are redeployed and others are not. Given the all-or-nothing deploy model, the real risks are:
1. Failing to update every reference to `lastLootboxRngWord` across all modules.
2. Introducing an off-by-one in the STORAGE-WRITE-MAP.md and other audit deliverables.
3. Breaking the `processTicketBatch` consumer in JackpotModule (line 1838), which reads `lastLootboxRngWord` for trait-assignment entropy.

**Why it happens:**
Solidity assigns storage slots sequentially. Removing a variable from the middle of a layout causes all later variables to shift down by one slot. This is invisible at the Solidity level -- the compiler silently reassigns slots. The STORAGE-WRITE-MAP.md (which documents slot numbers explicitly) falls out of sync, and any inline assembly referencing slot offsets would break.

**How to avoid:**
1. Option A (safest): Replace with `uint256 internal __deprecated_lastLootboxRngWord;` to preserve slot positions. Then remove all 3 write sites and refactor the 1 read site. This preserves layout stability but wastes 1 slot.
2. Option B (true removal): Delete the variable entirely. Then: (a) run a full slot audit post-change, (b) compare every slot number in the pre-change STORAGE-WRITE-MAP.md against the post-change layout, (c) verify every inline assembly block that references slot offsets, (d) update all audit deliverables.
3. Regardless of option: the JackpotModule consumer at line 1838 (`uint256 entropy = lastLootboxRngWord;`) must be refactored to use `lootboxRngWordByIndex[lootboxRngIndex - 1]` directly.
4. All 3 write sites in AdvanceModule (lines 162, 862, 1526) must be removed.
5. Run the DeployCanary test and full integration test suite after the change.

**Warning signs:**
- Any test that reads trait data or lootbox entropy will fail silently (wrong entropy, not a revert).
- STORAGE-WRITE-MAP.md slot numbers becoming inconsistent with actual layout.
- The 3 SSTORE savings per RNG cycle vanish if you use a placeholder instead of true removal (the writes still need to be removed either way).

**Phase to address:**
Storage/gas fixes phase. This is the highest-risk change in the milestone and should be done first, with a delta audit immediately after.

---

### Pitfall 2: Adding DegenerusCharity to a 23-Contract System With Compile-Time Immutable Addresses

**What goes wrong:**
All 23 contracts use `ContractAddresses.sol` -- a library of compile-time constant addresses derived from CREATE nonce prediction. Adding DegenerusCharity as contract #24 means:
1. It needs a `CHARITY` entry in ContractAddresses.sol.
2. The deploy script (`predictAddresses.js`) must predict its nonce-derived address correctly.
3. `DeployProtocol.sol` (the Foundry test harness) must deploy it at the exact right nonce position (after DegenerusAdmin at nonce 28, so nonce 29).
4. The `patchForFoundry.js` script must include it in its address prediction.
5. Any existing contract that needs to call DegenerusCharity (e.g., the yield surplus distribution in JackpotModule, the `resolveLevel` hook in AdvanceModule) must import and use the new constant address.

If the nonce prediction is wrong, the charity contract deploys at a different address than what was baked into other contracts at compile time, and all cross-contract calls to it revert or send ETH/tokens into the void.

**Why it happens:**
The system uses no proxy, no registry, no admin-settable addresses. Every cross-contract reference is a compile-time constant. This is excellent for gas and security (no admin re-pointing risk) but makes adding a new contract error-prone because the nonce prediction chain is fragile.

**How to avoid:**
1. Add `address internal constant CHARITY = address(...)` to ContractAddresses.sol with a placeholder address.
2. Update `predictAddresses.js` to include DegenerusCharity at the correct deploy order position.
3. Update `patchForFoundry.js` to include the new contract.
4. Update `DeployProtocol.sol` to deploy `DegenerusCharity` at the correct nonce position.
5. Run `DeployCanary.t.sol` -- this test exists specifically to verify address predictions match actual deploys. If it passes, the nonce chain is correct.
6. Determine deploy ordering carefully: if DegenerusCharity's constructor calls other contracts (e.g., reads sDGNRS data), it must deploy AFTER those contracts. If other contracts' constructors need the charity address, they already have it as a compile-time constant (no ordering constraint for callers).

**Warning signs:**
- DeployCanary test fails.
- Any test calling the charity contract gets `EvmError: Revert` with no meaningful error (call to empty/wrong address).
- Nonce count in deploy script doesn't match the total in ContractAddresses.sol.

**Phase to address:**
DegenerusCharity implementation phase. Must be done with the ContractAddresses + deploy pipeline update as the very first sub-step.

---

### Pitfall 3: Burn-For-Proportional-ETH/stETH Rounding and Dust in DegenerusCharity

**What goes wrong:**
The burn-for-proportional-ETH pattern (`ethOut = (ethBal * amount) / totalSupply`) has three well-known failure modes:
1. **Rounding to zero:** Small burns with large totalSupply yield `ethOut = 0`, burning tokens for nothing. The existing `_deterministicBurnFrom` in StakedDegenerusStonk handles this by operating on `totalMoney * amount / supplyBefore` (combined ETH+stETH), but a new charity contract could introduce a variant that rounds differently.
2. **stETH 1-2 wei rounding:** Lido's stETH uses shares-based accounting. `steth.balanceOf(address)` can be 1-2 wei less than expected due to integer division in their shares-to-balance conversion. `steth.transfer(recipient, amount)` may transfer 1 wei less than requested. This is a documented Lido behavior (lidofinance/core issue #442). If the charity contract reads `steth.balanceOf(this)` and then transfers exactly `(stethBal * amount) / totalSupply`, the transfer may revert or leave dust.
3. **Last-burner dust trap:** When the last charity token holder burns, rounding across all prior burns means 1-N wei of ETH/stETH is permanently trapped in the contract. The existing sDGNRS has game-over cleanup to handle remnants, but a standalone charity contract has no such fallback.

**Why it happens:**
Integer division in Solidity always rounds toward zero. stETH adds a second layer of rounding via its shares-to-balance conversion. These compound across many small operations.

**How to avoid:**
1. Enforce a minimum burn amount (e.g., `require(amount >= MIN_BURN)`) to prevent rounding-to-zero burns.
2. For stETH, use shares-based accounting: store and compute using `getSharesByPooledEth()` / `getPooledEthByShares()` rather than raw balances. Or, compute proportional shares and call `transferShares()` instead of `transfer()`.
3. For the last-holder case, use: `if (totalSupply == amount) { ethOut = address(this).balance; stethOut = steth.balanceOf(address(this)); }` to sweep everything.
4. Add a dust-sweep function callable when totalSupply reaches zero, sending any remaining dust to a designated recipient.
5. Mirror the existing sDGNRS pattern: compute `totalValueOwed = (totalMoney * amount) / supplyBefore` as a combined value, then split between ETH and stETH using the ratio, rather than computing them independently (which doubles the rounding loss).

**Warning signs:**
- Fuzz tests where `sum(ethOut for all burns) < initial ETH balance - acceptable_dust`.
- stETH transfer reverts with `BALANCE_EXCEEDED`.
- Users reporting `ethOut = 0` despite holding tokens.

**Phase to address:**
DegenerusCharity implementation phase, specifically during the burn mechanism design.

---

### Pitfall 4: Soulbound CHARITY Token Governance -- Mint-Vote-Burn and Weight Manipulation

**What goes wrong:**
If DegenerusCharity uses a soulbound token for governance (non-transferable, like sDGNRS), the standard flash-loan governance attack is mitigated. However, charity-specific attack vectors remain:
1. **Mint-vote-burn within same block:** If minting is permissionless and governance uses current balance for voting weight, an attacker can mint, vote, and burn without capital lock-up. The existing sDGNRS governance mitigates this with snapshot-based voting, but a new governance system might skip snapshots.
2. **Supply inflation dilution:** If new CHARITY tokens are minted over time (e.g., each `resolveLevel` hook mints tokens), existing holders' vote weight decreases. An attacker controlling level resolution timing could strategically dilute other voters before a critical vote.
3. **Cross-protocol governance interaction:** If CHARITY governance controls meaningful parameters (e.g., yield split percentages, allowlist) and the same whales hold both sDGNRS and CHARITY tokens, governance attacks could be coordinated across both systems.

**Why it happens:**
Soulbound tokens prevent transfer-based attacks but not mint/burn-based attacks. Governance systems that use current balances rather than historical snapshots are vulnerable to same-block manipulation.

**How to avoid:**
1. Best option: do NOT create a separate governance system. Gate charity parameter changes through the existing sDGNRS governance mechanism in DegenerusAdmin.sol. One governance system, one attack surface.
2. If separate governance is required: use snapshot-based voting where balance snapshot is taken at proposal creation block.
3. Add a time delay between minting and vote eligibility (e.g., tokens minted in the current period cannot vote on proposals created before the mint).
4. Cap the rate of CHARITY token minting per period to prevent rapid supply inflation attacks.

**Warning signs:**
- Governance proposal passing with votes from addresses that received tokens in the same block as the vote.
- Total vote weight on a proposal exceeding the snapshot-time supply.
- Single address accumulating >50% of charity tokens via strategic deposit timing.

**Phase to address:**
DegenerusCharity implementation phase, governance design sub-step.

---

### Pitfall 5: Changing `prizePoolFrozen` Behavior Reintroduces BAF Cache-Overwrite Bug

**What goes wrong:**
Currently, `_distributePayout` in `DegenerusGameDegeneretteModule.sol` (line 685) reverts when `prizePoolFrozen` is true. The I-12 finding requests allowing degenerette ETH payouts during the freeze. The freeze exists because `advanceGame`/`runRewardJackpots` reads `futurePrizePool` into a local variable, operates on it, and writes it back. If a degenerette payout modifies `futurePrizePool` between the read and write-back, the write-back clobbers the payout -- this is exactly the BAF (Buy-And-Forget) cache-overwrite bug pattern discovered and fixed in v4.4 Phases 100-102.

Simply removing `if (prizePoolFrozen) revert E()` would silently reintroduce the exact class of bug that took 3 phases to find and fix.

**Why it happens:**
The "obvious" fix looks trivially correct -- remove one line. But it is only safe if the payout is routed through the pending-pools side-channel that already exists for bet PLACEMENT during freeze (lines 558-561).

**How to avoid:**
1. Route frozen-context degenerette ETH payouts through `_setPendingPools` -- the same mechanism used for bet placement during freeze. The pending pools are reconciled after the freeze is lifted.
2. After any change, re-run the BAF cache-overwrite scan from Phase 100: for every function that reads `futurePrizePool` into a local, check if any called function (including via delegatecall) can modify the underlying storage.
3. Add a Foundry test that: (a) places a degenerette bet, (b) triggers advanceGame (which sets freeze), (c) resolves the bet during freeze, (d) completes advanceGame, and (e) verifies `futurePrizePool` conservation.

**Warning signs:**
- `futurePrizePool` value decreasing when it should only increase during jackpot phase.
- ETH conservation invariant failing in fuzz tests.
- Degenerette payouts "vanishing" -- paid from pool, but pool write-back overwrites the deduction.

**Phase to address:**
Storage/gas/event fixes phase (I-12 fix). Must include a delta audit against the BAF fix from v4.4.

---

### Pitfall 6: Try/Catch Hooks in Gas-Sensitive `advanceGame` Path

**What goes wrong:**
Adding a `resolveLevel` hook (external call to DegenerusCharity) in the `advanceGame` path introduces gas overhead. The `advanceGame` path has been profiled extensively (v4.2 Phases 95-98, v3.5 Phase 57) with the tightest paths having headroom of 34.9-42.3%. A new external call costs:
- 2,600 gas minimum (CALL opcode to cold address)
- Any gas consumed by the callee (including state reads, SSTOREs)
- Even if the callee reverts, the gas forwarded to the call IS consumed (try/catch catches the revert but not the gas)

The 63/64 gas forwarding rule (EIP-150) means the try block forwards nearly all remaining gas to the callee. Without an explicit gas limit, a misbehaving charity contract could consume most of the transaction's gas budget.

**Why it happens:**
Existing try/catch patterns in the codebase (stETH staking at line 1850, VRF shutdown at GameOverModule line 179, `_tryRequestRng` at line 1303) are all in non-gas-critical paths or have proven SAFE headroom. A new hook in the daily `advanceGame` hot path needs fresh verification.

**How to avoid:**
1. Set an explicit gas limit on the external call: `try ICharity(CHARITY).resolveLevel{gas: 50_000}(...) {} catch {}`. This caps the gas regardless of callee behavior.
2. Make the callee as gas-cheap as possible. Avoid SSTOREs in the happy path -- read state and emit an event only.
3. Profile the gas ceiling BEFORE and AFTER adding the hook, using the same methodology as v3.5 Phase 57.
4. Emit a distinguishable event on try/catch failure so silent failures are detectable off-chain.

**Warning signs:**
- `advanceGame` gas approaching 80% of block gas limit in profiling.
- The charity hook reverting silently (caught by try/catch) with no observable off-chain signal.

**Phase to address:**
DegenerusCharity integration phase (resolveLevel hook). Requires a gas ceiling delta analysis.

---

### Pitfall 7: Pruning Test Suites Removes Unique Coverage Without Detection

**What goes wrong:**
The project has 59 Foundry `.sol` test files and 50 Hardhat `.js/.ts` test files (109 total). With 13 known broken Foundry tests, the temptation is to remove tests that "look redundant." The danger is that two tests can assert similar-looking things while covering different code paths:
- A unit test for `purchaseMint` at level 0 covers the BOOTSTRAP_PRIZE_POOL fallback (50 ETH).
- A unit test for `purchaseMint` at level 10 covers the `price = 0.04 ether` tier transition.
- Pruning either one loses coverage of a distinct branch.

Worse, Foundry and Hardhat tests may cover the same feature but from different angles (Foundry via fuzz, Hardhat via exact scenario). Pruning the Hardhat test because "Foundry covers it" may lose the specific edge case the Hardhat test was written for.

**Why it happens:**
Test names and descriptions are often vague. Without running coverage analysis, it is impossible to know if two tests exercise different branches. Additionally, tests written during different audit phases may have been targeting specific findings -- removing a test written for CP-06 loses the precise regression guard for that fix.

**How to avoid:**
1. Run coverage BEFORE pruning: `forge coverage --report lcov` for Foundry, `npx hardhat coverage` for Hardhat. Save the baseline.
2. For each test being considered for removal: check which lines/branches it uniquely covers (the coverage report shows per-test coverage in detailed mode).
3. If a test is the ONLY test covering a specific line: do not remove it unless another test is added that covers the same line.
4. Cross-reference test file names against audit finding IDs (e.g., `BafRebuyReconciliation.t.sol` was written for the v4.4 BAF fix -- do not remove).
5. Run coverage AFTER pruning: diff the before/after reports. Zero lines lost is the success criterion.
6. Fix the 13 broken Foundry tests BEFORE pruning. A broken test that covers unique code should be fixed, not pruned.

**Warning signs:**
- Coverage percentage decreasing after pruning.
- A test file name containing an audit finding ID (CP-06, BAF, TQ-01, etc.) being pruned.
- Post-pruning: a bug that existed in test history was caught by a now-removed test.

**Phase to address:**
Test suite cleanup phase (first phase of milestone). Fix broken tests first, then prune with coverage-guided approach.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| `__deprecated_*` placeholder for `lastLootboxRngWord` instead of true removal | Zero risk of slot shift, simpler diff | Wastes 1 storage slot (32 bytes) permanently; but the 3 SSTORE writes must still be removed either way | Acceptable if slot stability is valued more than the 32-byte waste. The 3 SSTORE savings come from removing the WRITES, not the slot. |
| Duplicating sDGNRS governance logic in DegenerusCharity | Self-contained contract, no cross-contract dependency | Two governance systems to maintain, doubled attack surface, potential inconsistency in voting mechanics | Never -- delegate to existing sDGNRS governance. |
| Hardcoding charity yield split BPS as constants | Simpler code, gas savings vs. storage reads | Requires contract redeploy to change splits | Acceptable -- the entire protocol uses immutable constants for BPS splits. Consistency matters more than flexibility. |
| Skipping gas ceiling re-profiling after adding resolveLevel hook | Faster delivery | Gas regression on mainnet undiscoverable in tests | Never -- the advanceGame path has 3 previously AT_RISK gas ceilings. |
| Testing only happy-path burns in DegenerusCharity | Faster test writing | Rounding edge cases at small amounts and last-holder burns uncaught | Never -- fuzz the burn path with parameterized amounts. |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| ContractAddresses.sol (adding CHARITY) | Adding the address constant but forgetting to update `predictAddresses.js` AND `patchForFoundry.js` | Update all three files. Run DeployCanary.t.sol to verify. |
| Yield surplus split (JackpotModule `_distributeYieldSurplus`) | Changing the 23%/23%/46% split without adjusting the ~8% buffer (800 BPS unextracted) | If adding a charity split (e.g., 5%), subtract from the accumulator share, NOT the buffer. Verify `sum(all_shares_BPS) + buffer <= 10000`. |
| stETH in DegenerusCharity | Assuming `steth.balanceOf(this)` is stable between reads within the same tx | stETH can rebase between blocks but IS stable within a single transaction. The real issue is transfer imprecision: `transfer(X)` may move `X-1` wei. Read once, cache, and tolerate 1-2 wei imprecision. |
| `resolveLevel` hook placement in AdvanceModule | Calling the hook BEFORE critical state updates (violating CEI) | Call AFTER all state mutations for the level transition are complete. The hook is informational. |
| Degenerette freeze change (I-12) | Removing `if (prizePoolFrozen) revert E()` without rerouting payouts | Route frozen-context payouts through `_setPendingPools` (same pattern as lines 558-561). |
| sDGNRS BPS constants in constructor | Changing a BPS constant without verifying the constructor dust-rounding logic (lines 269-275) | After changing any BPS value, verify that the dust-to-lootbox fallback at lines 270-275 correctly absorbs the rounding difference. Sum of all pool amounts must equal INITIAL_SUPPLY. |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Cold address access to DegenerusCharity in advanceGame | +2,600 gas on first call per transaction | Use explicit `{gas: N}` limit on try/catch call; profile with `forge test --gas-report` | Every `advanceGame` transaction |
| stETH `balanceOf` imprecision in burn calculations | 1-2 wei discrepancy between computed and actual transfer amount | Cache balance once; use shares-based accounting; tolerate small imprecision | Every burn transaction |
| Double `_getFuturePrizePool()` SLOAD in earlybird path (F-04) | 200 gas wasted per earlybird payout | Cache the first read into a local variable | Not a scale issue -- fixed 200 gas. Low priority. |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Reentrancy in charity burn (ETH send before state update) | Attacker re-enters burn() to drain contract | Strict CEI: update `balanceOf` and `totalSupply` BEFORE any ETH/stETH transfer. Copy the sDGNRS `_deterministicBurnFrom` pattern (lines 492-496 update, then lines 498+ transfer). |
| Not deducting reserved amounts from charity burn calculation | Burns claim assets reserved for other purposes | If charity holds segregated reserves (like sDGNRS's `pendingRedemptionEthValue`), exclude them from proportional calculations. |
| Governance proposal front-running | Attacker sees proposal in mempool, mints tokens, votes | Use snapshot-based voting or delegate all governance to existing sDGNRS system. |
| Force-feeding ETH to charity via selfdestruct | Inflated proportional burn payouts | Track deposited ETH explicitly rather than relying on `address(this).balance`. Or document as INFO-level (force-feed inflates ALL holders proportionally, no selective advantage). |
| stETH transfer returning less than requested | Accounting inconsistency; trapped dust | Use `transferShares()` for exact-share transfers or document the 1-2 wei imprecision as known behavior. |

## "Looks Done But Isn't" Checklist

- [ ] **lastLootboxRngWord removal:** All 3 write sites removed (AdvanceModule L162, L862, L1526) AND the 1 read site updated (JackpotModule L1838) AND STORAGE-WRITE-MAP.md updated AND slot numbers re-verified
- [ ] **ContractAddresses update for CHARITY:** Constant added AND predictAddresses.js updated AND patchForFoundry.js updated AND DeployProtocol.sol updated AND DeployCanary.t.sol passes
- [ ] **RewardJackpotsSettled event fix (I-09):** Emits post-reconciliation value AND no other event in same function reads stale pre-reconciliation local
- [ ] **Degenerette freeze change (I-12):** Payouts during freeze route through `_setPendingPools` AND BAF cache-overwrite scan re-run AND Foundry test verifies ETH conservation across resolution-during-freeze
- [ ] **BPS split changes:** All BPS constants sum to <= 10000 AND constructor dust logic still works AND yield surplus buffer is sufficient AND no test hardcodes old BPS values
- [ ] **DegenerusCharity burn:** Minimum burn enforced AND stETH rounding handled AND last-holder sweep exists AND CEI verified AND fuzz test covers parametric amounts
- [ ] **Charity governance:** Uses snapshot voting OR delegates to sDGNRS governance AND mint-vote-burn tested and prevented
- [ ] **resolveLevel hook:** Placed AFTER all state mutations AND wrapped in try/catch with explicit gas limit AND gas ceiling profiled AND silent-failure emits event
- [ ] **Test pruning:** Every pruned test's unique assertions preserved elsewhere AND coverage report shows no lines lost AND both Foundry and Hardhat suites green
- [ ] **BitPackingLib NatSpec fix (I-26):** "bits 152-154" changed to "bits 152-153" AND no other NatSpec in same file inadvertently changed

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Storage slot shift from variable removal | MEDIUM | Pre-deploy only (non-upgradeable). Fix layout, recompile all contracts, re-run full test suite. |
| Nonce prediction wrong for DegenerusCharity | LOW | Re-run predictAddresses.js, update ContractAddresses.sol, recompile. No state to migrate. |
| BAF cache-overwrite from I-12 freeze fix | HIGH | If caught in testing: reroute through pending pools. If missed to deploy: ETH silently lost on every degenerette resolution during freeze. Requires full redeploy. |
| Burn rounding drains more than expected | LOW | 1-2 wei per burn is economically insignificant. Fix in next deploy cycle with shares-based accounting. |
| resolveLevel hook gas regression | LOW | The try/catch ensures hook failure does not block advanceGame. Reduce gas limit or remove hook in next deploy. |
| Test pruning removes unique coverage | LOW | Re-add pruned tests from git history. Coverage regression detectable before deploy. |
| Charity governance manipulation | HIGH | If exploited: governance decision may need social consensus to reverse. Prevent by delegating to sDGNRS governance. |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Storage slot shift (#1) | Storage/gas fixes (first change) | Full slot audit pre/post. All delegatecall modules compile. DeployCanary + integration tests pass. |
| ContractAddresses nonce (#2) | DegenerusCharity impl (first sub-step) | DeployCanary.t.sol passes. Cross-contract calls to CHARITY succeed in integration tests. |
| Burn rounding/dust (#3) | DegenerusCharity impl (burn design) | Fuzz test: parametric amounts [1 wei .. full supply]. `sum(ethOut) <= initial_balance` invariant. stETH transfer no revert. |
| Governance attacks (#4) | DegenerusCharity impl (governance design) | Snapshot voting test or delegation to sDGNRS governance verified. Mint-vote-burn attack test fails as expected. |
| BAF reintroduction (#5) | Storage/gas fixes (I-12) | BAF scan re-run. ETH conservation invariant fuzz test covering resolution-during-freeze. |
| Gas-sensitive hook (#6) | DegenerusCharity integration | Gas ceiling delta analysis. advanceGame headroom > 20% of block limit after hook. |
| Test pruning coverage loss (#7) | Test cleanup (first phase) | Coverage diff: before minus after = zero lost lines. Both suites green. |

## Sources

- Direct codebase analysis: `contracts/storage/DegenerusGameStorage.sol` (storage layout, slots 0-78+), `contracts/ContractAddresses.sol` (compile-time addresses), `contracts/StakedDegenerusStonk.sol` (burn mechanism, BPS constants, constructor), `contracts/modules/DegenerusGameAdvanceModule.sol` (RNG finalization, try/catch patterns), `contracts/modules/DegenerusGameJackpotModule.sol` (yield surplus distribution, `lastLootboxRngWord` consumer), `contracts/modules/DegenerusGameDegeneretteModule.sol` (prizePoolFrozen guard), `test/fuzz/helpers/DeployProtocol.sol` (nonce-ordered deploy)
- Audit deliverables: `audit/FINDINGS.md` (I-02, I-09, I-12, I-26, F-04), `audit/STORAGE-WRITE-MAP.md` (78+ slot mappings), `audit/ETH-FLOW-MAP.md`
- v4.4 BAF cache-overwrite fix: Phases 100-102
- [Lido stETH rounding issue #442](https://github.com/lidofinance/core/issues/442)
- [Lido token integration guide](https://docs.lido.fi/guides/lido-tokens-integration-guide/)
- [Solidity storage layout docs](https://docs.soliditylang.org/en/latest/internals/layout_in_storage.html)
- [OWASP Smart Contract Top 10 2025](https://owasp.org/www-project-smart-contract-top-10/)

---
*Pitfalls research for: Degenerus Protocol v6.0 -- test cleanup, storage/gas fixes, DegenerusCharity*
*Researched: 2026-03-25*
