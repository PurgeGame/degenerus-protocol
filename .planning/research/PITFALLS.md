# Pitfalls Research

**Domain:** Smart contract security audit — VRF-based on-chain game with delegatecall modules, prize pools, and complex token economics
**Researched:** 2026-02-28
**Confidence:** HIGH (contract code directly inspected; external findings corroborated across multiple sources)

---

## Critical Pitfalls

### Pitfall 1: VRF Callback Gas Limit Overflow Causes Silent DOS

**What goes wrong:**
`rawFulfillRandomWords` is called by the Chainlink VRF coordinator with a fixed gas limit (300,000 gas as set in `VRF_CALLBACK_GAS_LIMIT`). The callback is routed via `delegatecall` to `DegenerusGameAdvanceModule`. If the callback logic consumes more gas than the limit, the coordinator call reverts internally but the coordinator does **not** retry — the randomness request is permanently dropped. The game's `rngRequestTime` stays set, the `rngLockedFlag` stays true, and the game is stalled until the 18-hour timeout expires. This is a silent failure mode: no event is emitted, no revert propagates.

**Why it happens:**
Auditors focus on whether the callback validates correctly, not whether it fits within the gas envelope. The Chainlink documentation warns explicitly: "If `fulfillRandomWords()` reverts, the VRF service won't retry." The callback routes through a delegatecall, adding overhead. As lootbox state grows (pending eth, pending burnie, index mappings), the callback may creep toward the limit over the life of the game.

**How to avoid:**
- Measure the gas cost of `rawFulfillRandomWords` with worst-case state (maximum lootbox pending, maximum nudge count) using forge gas snapshots.
- Ensure the callback stays under 200,000 gas with comfortable headroom so growth over the game's lifetime doesn't push it past 300,000.
- The callback should store the word and return; all complex logic should be deferred to the next `advanceGame()` call. Inspect whether the mid-day lootbox finalization path in the callback adds significant work.

**Warning signs:**
- Callback cost climbing above 150,000 gas in tests with large lootbox state.
- Any additional logic added to the callback path in a future PR without a gas re-measurement.

**Phase to address:** RNG state machine integrity phase (early audit).

---

### Pitfall 2: Stale VRF Request ID Allows Late Fulfillment to Corrupt State

**What goes wrong:**
The Chainlink VRF coordinator can fulfill a request at any time — including after a timeout retry has issued a new request. The current guard is `if (requestId != vrfRequestId || rngWordCurrent != 0) return;`. This means: if a retry fires a new request (new `vrfRequestId`), and then the **old** coordinator fulfillment arrives, it is correctly silently dropped. But the dropped lootbox index reservation (`lootboxRngRequestIndexById[oldRequestId]`) may not be cleaned up if the retry logic didn't handle the transition atomically.

**Why it happens:**
Retry logic in `_finalizeRngRequest` does remap the reserved lootbox index from the old request ID to the new one — but this only happens on the retry path. If a late fulfillment arrives for the old request ID after a retry has already been fulfilled (i.e., `rngWordCurrent != 0`), the guard returns early. The lootbox index entry for the old ID is orphaned in `lootboxRngRequestIndexById`. This is storage bloat, not an exploit, but could mislead off-chain indexers or a future contract reading the mapping.

**How to avoid:**
- Verify by code review that all paths through VRF request lifecycle (fresh, retry, late-arrive) leave `lootboxRngRequestIndexById` in a consistent state.
- Check whether orphaned entries can be exploited by a player calling `openLootBox` with a stale index.

**Warning signs:**
- Test coverage does not include the late-arrival of an old fulfillment after a retry has been fulfilled.
- `lootboxRngRequestIndexById` entries growing monotonically without cleanup.

**Phase to address:** RNG state machine integrity phase.

---

### Pitfall 3: Nudge Mechanism Lets Coordinated BURNIE Holders Bias RNG Outcomes

**What goes wrong:**
The `reverseFlip()` function allows any BURNIE holder to add +1 to the upcoming VRF word by burning BURNIE (starting at 100 BURNIE, scaling +50% per queued nudge). The `_applyDailyRng` function applies all queued nudges as an additive offset to the VRF word before it is stored. A coordinated group that accumulates BURNIE and purchases nudges in the same window effectively shifts the random word by a known integer, changing which jackpot bucket or trait is selected.

**Why it happens:**
The design intends for nudge cost to become prohibitively expensive. However: (1) the mapping from word value to jackpot outcome is deterministic and observable on-chain, (2) the VRF word is available in mempool before `advanceGame()` is called in the next step, and (3) if a block proposer sees both the fulfilled word and the desired offset, they can sequence nudge transactions and `advanceGame()` in the same block. Chainlink's security documentation specifically warns: "Lock the contract to further user inputs immediately after submitting the randomness request and before fulfillment."

**How to avoid:**
- Determine the exact window during which nudges can be applied relative to VRF fulfillment. Nudges are blocked while `rngLockedFlag = true` (during VRF in-flight), but are they blocked **after** fulfillment arrives but **before** `advanceGame()` processes them? If `rngLockedFlag` is still set when the word arrives, no nudges can be queued at that moment. But if a fulfilled word sits in `rngWordCurrent` while `rngLockedFlag` is cleared between steps, a block proposer can see the word, calculate the desired nudge count, and front-run `advanceGame()`.
- Verify that `rngLockedFlag` remains set from VRF request through the `advanceGame()` call that consumes the word.

**Warning signs:**
- Any code path where `rngLockedFlag` is cleared before `rngWordCurrent` is consumed.
- Test coverage that validates nudges cannot be added after VRF fulfillment but before word processing.

**Phase to address:** RNG manipulation analysis phase (highest priority).

---

### Pitfall 4: Delegatecall Return Value Propagation Masks Reverts in Module Calls

**What goes wrong:**
Every delegatecall in `DegenerusGame` follows the pattern:
```solidity
(bool ok, bytes memory data) = ContractAddresses.SOME_MODULE.delegatecall(...);
if (!ok) _revertDelegate(data);
```
If `_revertDelegate` doesn't correctly propagate the revert reason (e.g., if it truncates the error data or the error selector is lost), callers receive an opaque failure that doesn't match the original custom error. More critically: if any delegatecall path returns `true` with malformed return data, `_revertDelegate` is never called and the caller sees a "success" with garbage return data silently decoded.

**Why it happens:**
Custom error propagation through delegatecall is tricky. ABI decoding of return values from a delegatecall that succeeded with incorrect return data can silently produce wrong values. Auditors commonly verify that reverts propagate but miss the case where a module accidentally returns `true` on a path that should have failed.

**How to avoid:**
- Review `_revertDelegate` to confirm it propagates the full error selector and data without truncation.
- Review every delegatecall return value decoding: does each decoded return value match the expected type? What happens if the module returns 32 bytes of zeros on a path that should have returned a non-zero value?
- Add fuzz tests that send malformed return data from modules.

**Warning signs:**
- Any module function that has multiple return paths where some return values are uninitialized.
- Delegatecall results decoded with `abi.decode` without length validation.

**Phase to address:** Delegatecall storage safety phase.

---

### Pitfall 5: Storage Slot Layout Drift in Delegatecall Modules

**What goes wrong:**
`DegenerusGameStorage` defines the canonical storage layout used by `DegenerusGame` and all 10 modules. If any module inherits a contract that adds a storage variable **before** importing `DegenerusGameStorage`, the module's storage view is shifted by one or more slots relative to the game's actual storage. This is the storage collision attack — the module writes to what it believes is slot N, but that slot holds a completely different variable in the game's actual layout.

**Why it happens:**
This is the most well-documented delegatecall vulnerability class (Audius hack, AllianceBlock upgrade). The risk is highest when: (a) new imports are added to modules, (b) inheritance chains change, or (c) constants are added that happen to be the wrong type. Even a `bool` added to an inherited contract can consume a full slot if it doesn't pack with adjacent variables.

**How to avoid:**
- Generate storage layout reports with `forge inspect DegenerusGameAdvanceModule storage-layout` and compare against `forge inspect DegenerusGame storage-layout` for every slot from 0 onward.
- This check must be run for all 10 modules.
- Any mismatch at any slot is critical.

**Warning signs:**
- Any module that inherits from more than one parent (diamond inheritance risk).
- New imports added to module files without a storage layout re-check.
- A module that declares its own variables (explicitly prohibited in the architecture comments but must be verified).

**Phase to address:** Delegatecall storage safety phase (standalone verification step).

---

### Pitfall 6: Prize Pool Invariant Break Via stETH Rebasing

**What goes wrong:**
The critical invariant is `address(this).balance + steth.balanceOf(this) >= claimablePool`. Lido stETH rebases daily — the balance of `steth.balanceOf(address(this))` increases each day without any transfer event. This means the invariant is passively maintained (stETH accrual adds to the buffer), but code that reads `steth.balanceOf(this)` at two different points in the same transaction can see different values. More dangerously: code that converts stETH amounts to ETH using a snapshot balance may undercount if rebase happened between calculation and execution.

**Why it happens:**
Lido's integration guide warns: "stETH balances change upon transfers, mints/burns, and rebases — do not cache balances over extended periods." Contracts that store the stETH balance in a variable for accounting purposes then read it back later can have a growing discrepancy. The `adminSwapEthForStEth` function swaps ETH for stETH at 1:1 — this ratio is only valid if no rebase has occurred between the swap setup and execution.

**How to avoid:**
- Verify that no function stores `steth.balanceOf(this)` in a state variable and uses that stored value for payout calculations.
- Verify that `claimWinnings` uses the live balance (not a cached value) when deciding how much stETH to send.
- Verify `adminSwapEthForStEth` cannot be sandwiched around a rebase event to extract value.

**Warning signs:**
- Any mapping or state variable holding a previously-read stETH balance.
- Payout logic that uses two separate `steth.balanceOf` calls and assumes they are equal.

**Phase to address:** ETH flow accounting phase.

---

### Pitfall 7: Rounding Direction Errors Accumulate to Protocol Drain

**What goes wrong:**
The Balancer $128M exploit (Nov 2025) demonstrated that rounding errors in integer division, when compound across many operations, can be exploited to drain funds. This protocol has numerous percentage calculations (PURCHASE_TO_FUTURE_BPS, jackpot slices, affiliate shares, EV multipliers). If any of these consistently round in the player's favor rather than the protocol's favor, a coordinated attacker making many small operations can extract more than expected.

**Why it happens:**
Solidity integer division always truncates (rounds toward zero). When the protocol computes `amount * bps / 10000`, a small `amount` may yield 0 after truncation even though the player contributed ETH. The complement — `amount - (amount * bps / 10000)` — then gets the full amount. This favors whichever side receives the complement. Auditors often verify formulas are mathematically correct for large values but miss that small-value edge cases consistently favor one party.

**How to avoid:**
- For every fee/split formula, verify which direction rounding favors (protocol or player).
- Run fuzz tests with `amount` values of 1 wei, 2 wei, and other tiny amounts to see if splits sum to more or less than the input.
- Verify that the sum of all split components equals the input for every split formula (no dust accumulation).

**Warning signs:**
- Any formula of the form `a * bps / 10000` followed by `remainder = total - computed` — check that these two paths together equal `total`.
- Lootbox EV multiplier calculations with activity scores — small scores could yield 0 bonus while large scores yield exact computation.

**Phase to address:** Token/pass math verification phase and fee split integrity phase.

---

## Moderate Pitfalls

### Pitfall 8: Operator Approval Enables Cross-Player Manipulation

**What goes wrong:**
`setOperatorApproval` allows any address to be approved as an operator for any player. Operators can then call functions like `purchaseWhaleBundle(victim, quantity)`, `openLootBox(victim, index)`, and `claimWinnings(victim)` on behalf of the victim. If any of these functions have side effects that benefit the operator rather than the victim (e.g., affiliate credit being awarded to msg.sender instead of buyer), operators can weaponize player approvals.

**Why it happens:**
Operator approval systems are designed for legitimate bot/helper use, but auditors must verify that every proxied action truly benefits only the named player. The Degenerette and boon modules accept operators acting on behalf of players — if affiliate credit flows to `msg.sender` instead of `buyer` in any code path, a malicious operator drains affiliate value from players they are "helping."

**How to avoid:**
- Trace every function that accepts a `player` argument and uses `_resolvePlayer()`: verify that all value flows (DGNRS rewards, lootbox credits, coinflip credits, affiliate bonuses) use `player` (not `msg.sender`) as the beneficiary.
- Verify that operator approval cannot be used to grief players by opening their lootboxes at an unfavorable time (before they can add lootbox boosts, for example).

**Warning signs:**
- Any function that awards value to `msg.sender` inside a branch where `msg.sender != player`.
- Missing test coverage for the "operator calls on behalf of player" path in each module.

**Phase to address:** Access control audit phase.

---

### Pitfall 9: ERC20 Return Value Ignored on BURNIE/DGNRS Transfers

**What goes wrong:**
`BurnieCoin.burnCoin` and `IDegenerusStonk.transferFromPool` are called in multiple places without checking return values. If either token contract returns `false` instead of reverting on failure (common in non-standard ERC20 implementations), the calling contract continues execution as if the burn/transfer succeeded.

**Why it happens:**
The protocol uses custom ERC20 implementations. Auditors must verify whether these tokens revert on failure or return false. Lido's documentation notes that LDO "returns false instead of reverting on transfer failures." If `BurnieCoin` has similar behavior, `coin.burnCoin` calls that check nothing would silently no-op, allowing free nudges or coinflips without BURNIE spending.

**How to avoid:**
- Read `BurnieCoin.burnCoin` implementation: does it revert on insufficient balance, or return false?
- Read `DegenerusStonk.transferFromPool`: does it revert, or silently return?
- If either can return false, add return value checks at every call site.

**Warning signs:**
- Any call to `coin.burnCoin` or `dgnrs.transferFromPool` that is not followed by a success check or a revert.

**Phase to address:** Cross-contract interaction safety phase.

---

### Pitfall 10: Game-Over Payout Underpays If stETH Balance Fluctuates During Settlement

**What goes wrong:**
Game over is a multi-step process (advanceGame → VRF request → fulfill → advanceGame → gameOver=true). During this multi-block window, stETH rebasing can occur. If the game-over settlement calculates payout shares based on `steth.balanceOf(this)` at step 1 and then sends that stETH at step 5, the balance may have grown (rebase accrual) or — in a Lido slashing event — shrunk. Accrual is benign (players get slightly more). Slashing is catastrophic: the settlement logic may try to send more stETH than exists, causing all endgame withdrawals to fail.

**Why it happens:**
Lido stETH slashing is rare but non-zero. The protocol's settlement assumes stETH is stable during the multi-step game-over sequence. Under normal conditions this is fine, but auditors must consider the slashing scenario as part of the game-over edge case.

**How to avoid:**
- Verify that the game-over settlement uses current live balances at payout time, not cached values from a previous step.
- Verify that the payout logic handles the case where `steth.balanceOf(this) < expectedAmount` without reverting (instead paying whatever is available).

**Warning signs:**
- Any state variable storing a stETH amount that is set during step 1 of game-over and read during step 5.

**Phase to address:** Edge case accounting phase (game-over settlement).

---

### Pitfall 11: Block Proposer Can Reorder `advanceGame` and Player Purchases

**What goes wrong:**
On Ethereum PoS, the block proposer has full control over transaction ordering within a block. For this game, the `advanceGame` call that ends the purchase phase and the last few player purchases can be reordered. A block proposer who is also a player (or colluding with one) can: (1) place their purchase transaction, (2) let other players' transactions occur, then (3) call `advanceGame` to close the phase — or vice versa, squeezing in a purchase at the last block after all other players have committed.

**Why it happens:**
Solodit SOL-AM-MA-3 explicitly covers transaction ordering sensitivity. Games with defined phase transitions are particularly vulnerable because the value of being "last" or "first" in a phase can be significant (final day jackpot timing, price escalation position, lootbox index assignment).

**How to avoid:**
- Analyze what game advantage accrues to the "last purchaser before phase end" — is there a meaningful edge?
- Analyze what game advantage accrues to being first after `advanceGame` starts the new phase (e.g., lootbox index reservation).
- If the advantage is material, consider adding a commit-delay (block-based) between phase close and jackpot calculation.

**Warning signs:**
- Phase transitions that grant a bonus to the triggering caller (`advanceGame` pays a bounty — verify this doesn't create perverse incentives).
- Lootbox index reservation that makes "being first in a new round" significantly advantageous.

**Phase to address:** Validator/MEV attack surface phase.

---

### Pitfall 12: Sybil Groups Extract Proportional Prize Pool by Owning Majority Tickets

**What goes wrong:**
If a coordinated Sybil group buys a majority of tickets across multiple wallets at level prices below the jackpot payout, they can guarantee a positive expected value for the group even if individual wallets lose. The group collectively "owns the house" for that level. This is especially relevant for levels with low ticket prices and a predictable prize pool fill rate.

**Why it happens:**
This is a game-theoretic attack, not a code bug — it is not detectable by static analysis. Auditors typically focus on code correctness, not economic equilibria. The threat model explicitly names "coordinated Sybil groups" as adversaries.

**How to avoid:**
- Model the expected value for a Sybil group buying X% of tickets at each level.
- Verify that the prize pool mechanics (90/10 current/future split, daily jackpot variance) prevent guaranteed-positive EV for even a 90% ticket holder.
- Specifically check: can a Sybil group profitably run the game end-to-end from level 1 through game-over by owning 51%+ of tickets?

**Warning signs:**
- Prize pool payout rate significantly exceeds ticket purchase cost at early levels.
- Earlybird DGNRS multiplier creates a window where early concentrated purchases have higher EV than intended.

**Phase to address:** Sybil/collusion analysis phase.

---

### Pitfall 13: Unchecked Arithmetic in Module Hot Paths Bypasses Overflow Protection

**What goes wrong:**
225 `unchecked` blocks are present across the codebase (grep count). Solidity 0.8+ provides automatic overflow protection, but `unchecked {}` disables it for gas savings. If any unchecked block contains arithmetic that can actually overflow under adversarial input (e.g., a very large `quantity` in whale bundle purchase, a very large `nudges` count in `_currentNudgeCost`), the overflow could corrupt critical state variables.

**Why it happens:**
The `_currentNudgeCost` function uses an O(n) loop with `unchecked { --reversals; }` — this is safe (decrement of a counter toward zero). But the outer cost calculation `(cost * 15) / 10` is **not** in an unchecked block, so it reverts on overflow. Auditors must verify every unchecked block individually. The JackpotModule has 40 unchecked blocks — the highest density — and should receive the most scrutiny.

**How to avoid:**
- For each unchecked block: establish the invariant that prevents overflow (e.g., "this variable is bounded by X and Y, so overflow cannot occur").
- Document the invariant in an inline comment (many blocks already do this — verify they are correct).
- Pay special attention to JackpotBucketLib and DegenerusGameJackpotModule.

**Warning signs:**
- Unchecked blocks without an accompanying comment explaining why overflow is safe.
- Any unchecked block that performs multiplication before division (can overflow before the division reduces the value).

**Phase to address:** Token/pass math verification phase.

---

### Pitfall 14: `receive()` Routes All ETH to `futurePrizePool` — Accidental Funding Miscounts

**What goes wrong:**
The contract's `receive()` function routes all plain ETH transfers to `futurePrizePool`:
```solidity
receive() external payable {
    futurePrizePool += msg.value;
}
```
If any internal call path accidentally sends ETH to the game contract (e.g., a module call that returns excess ETH, or a failed external call that ETH bounces back from), that ETH silently enters `futurePrizePool` rather than being accounted to the correct pool. This could inflate future pools while under-crediting current players.

**Why it happens:**
`receive()` is a catch-all that makes the contract easy to fund. But in a multi-contract system with complex ETH flows, any ETH that doesn't hit a named function goes here silently. Auditors commonly overlook `receive()` as an accounting vector.

**How to avoid:**
- Enumerate all paths where ETH can enter the game contract: purchase functions, admin swaps, and plain transfers.
- Verify that each path lands in the correct accounting variable.
- Consider whether `futurePrizePool` should be the default destination, or whether a dedicated admin-only funding function is safer.

**Warning signs:**
- Any call to an external contract from the game contract where a refund could arrive as a plain ETH transfer.

**Phase to address:** ETH flow accounting phase.

---

## Minor Pitfalls

### Pitfall 15: Generic `E()` Error Hides Root Cause in Complex Audit Paths

**What goes wrong:**
Most validation guards use `revert E()` — a single generic error with no context. When an audit finds a revert, tracing back which guard triggered it requires careful state reconstruction. This slows audit work and can cause auditors to overlook a code path that incorrectly triggers `E()` (false positive revert) or fails to trigger it when it should (false negative).

**Prevention:**
During audit, map each `revert E()` to its enclosing condition. Create a test for each one that verifies the exact guard (not just "the function reverts"). This is an audit methodology concern, not a security vulnerability — but it adds audit time.

**Phase to address:** Access control audit phase (adds time, not risk).

---

### Pitfall 16: VRF Subscription Balance Griefing

**What goes wrong:**
A malicious contract added to the Chainlink subscription (if subscription management is not tightly controlled) can spam cheap VRF requests, draining the LINK balance and starving the game's legitimate requests. Chainlink's own documentation notes: "a malicious contract added to a subscription can drain funds with spam requests."

**Prevention:**
Verify that only `DegenerusAdmin` can manage the VRF subscription (add/remove consumers, fund it). Verify the admin does not expose a permissive consumer management function that any caller could invoke. Check whether the Chainlink subscription has a consumer whitelist in place.

**Phase to address:** RNG state machine integrity phase.

---

### Pitfall 17: Deity Pass Triangular Pricing Formula Overflow for High Pass Count

**What goes wrong:**
Deity pass price is `24 + T(n)` ETH where `T(n) = n*(n+1)/2` and `n` is the number of passes already sold. For very high `n`, `n*(n+1)` could overflow uint256. At `n = 2^128`, the multiplication wraps around zero.

**Why it matters (likely benign, but verify):**
The game would need to sell approximately 2^127 deity passes before overflow. At 24 ETH each, this is cosmically impossible economically. However, auditors should verify the storage type of the pass counter and confirm it cannot be artificially incremented by any exploit.

**Prevention:**
Verify the storage type of the deity pass counter. Verify that `purchaseDeityPass` cannot be called with a forged or replayed ERC721 state that artificially increments the counter.

**Phase to address:** Token/pass math verification phase (low priority, likely safe).

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Generic `E()` error for all guards | Saves bytecode, stays under 24KB | Audit + debugging cost, unclear failure reasons | Acceptable for size-constrained contracts only if mapped in tests |
| 225 unchecked blocks for gas | Gas reduction in hot paths | Each block must be individually audited | Only where invariant is documented and provable |
| Compile-time constant contract addresses | No governance attack surface | Any address mistake requires full redeploy | Acceptable for non-upgradeable protocol |
| `receive()` routes all ETH to futurePrizePool | Simple funding mechanism | Silent miscounting if ETH arrives unexpectedly | Never in high-value multi-pool accounting |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Chainlink VRF V2.5 | Inheriting `VRFConsumerBaseV2Plus` for safety checks; custom `rawFulfillRandomWords` bypasses coordinator verification | Verify coordinator address explicitly in callback (done); also verify key hash matches expected |
| Chainlink VRF V2.5 | Assuming failed fulfillment will be retried | It will not be retried; the game must have a timeout/recovery path (18h timeout exists — verify it works) |
| Lido stETH | Storing stETH balance in a variable for later use | Always call `balanceOf` live at payout time; never cache rebasing token balances |
| Lido stETH | Assuming `steth.transfer(amount)` sends exactly `amount` | May send 1-2 wei less due to share rounding; use `transferShares()` for exact control |
| BURNIE ERC20 | Assuming `burnCoin` reverts on failure | Must verify the implementation — if it returns false, all nudge purchases are potentially free |

---

## Security Mistakes (Domain-Specific)

| Mistake | Risk | Prevention |
|---------|------|------------|
| Not locking user inputs between VRF request and advanceGame | Nudges after fulfillment change a known word — predictable outcome | Verify rngLockedFlag covers the full window from request to word consumption |
| Auditing modules in isolation rather than in-context | Storage layout bugs only appear when both game and module are considered together | Always check storage layout side-by-side for each module |
| Testing only "happy path" for game-over | Multi-step game-over has many timing-dependent edge cases | Test every intermediate state: what if VRF fulfillment never arrives during game-over? |
| Treating delegatecall success as proof of correct execution | A module can return `true` with zero-valued return data on an invalid path | Validate return data length and non-zero values where expected |
| Ignoring affiliate credit flows in operator-proxied calls | Affiliate credit may go to operator, not player | Trace msg.sender vs player in every proxied call that touches affiliate state |

---

## "Looks Done But Isn't" Checklist

- [ ] **VRF gas budget:** The callback stays under 200,000 gas with worst-case lootbox state — not just average state.
- [ ] **Storage layout verification:** `forge inspect` run on all 10 modules and compared slot-by-slot against the game contract, not just "visually reviewed."
- [ ] **Nudge window:** `reverseFlip` is provably blocked from the moment VRF word arrives until `advanceGame` consumes and clears it.
- [ ] **stETH accounting:** No path caches `steth.balanceOf(this)` in a state variable between transactions.
- [ ] **Fee splits sum to input:** Every BPS split verified that the two halves equal the original amount (no dust gains or losses).
- [ ] **Operator abuse:** Every `_resolvePlayer()` call site verified that value flows to `player`, not `msg.sender`.
- [ ] **BURNIE burn return value:** `burnCoin` implementation verified to revert (not return false) on insufficient balance.
- [ ] **Game-over with zero stETH:** Settlement path tested when `steth.balanceOf(this)` is 0 (ETH-only treasury).
- [ ] **Late VRF fulfillment:** Test that a fulfillment arriving for an old request ID after a retry has been fulfilled is safely ignored and causes no state corruption.
- [ ] **VRF subscription consumers:** Only admin-controlled; no public function to add consumers.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| VRF callback gas limit exceeded (DOS) | LOW | Wait 18h for timeout; retry fires automatically on next advanceGame call |
| Storage slot collision found | HIGH | Full redeployment required; no in-place fix possible for non-upgradeable contracts |
| Prize pool invariant broken (funds stuck) | HIGH | Admin ETH injection via receive() is possible but requires trust in admin key security |
| stETH slashing drains payout buffer | MEDIUM | Admin can inject ETH via receive(); communicate pro-rata reduction to players |
| Sybil group extracts excess prize pool | HIGH | No on-chain remedy; economics must be correct from day one |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| VRF callback gas limit DOS | RNG state machine integrity | forge gas snapshot of rawFulfillRandomWords with max state |
| Stale VRF request ID corruption | RNG state machine integrity | Test: old fulfillment arrives after retry is fulfilled |
| Nudge window exploitable by block proposer | RNG manipulation analysis | Trace rngLockedFlag state transitions through full VRF lifecycle |
| Delegatecall return propagation masks reverts | Delegatecall storage safety | Unit test every delegatecall with deliberately malformed module |
| Storage slot layout drift | Delegatecall storage safety | forge inspect all 10 modules; automated slot comparison script |
| stETH rebasing breaks invariant | ETH flow accounting | Test with live stETH balance snapshot; test slashing scenario |
| Rounding accumulation drains protocol | Token/pass math verification and fee split integrity | Fuzz all split formulas with values 1 wei to 1000 ETH |
| Operator approval manipulation | Access control audit | Trace value flows in operator-proxied calls for every entry point |
| BURNIE return value ignored | Cross-contract interaction safety | Read burnCoin implementation; verify revert vs return false |
| Game-over settlement with stETH fluctuation | Edge case accounting | Simulate multi-block settlement with rebase occurring between steps |
| Block proposer reorders phase boundary | Validator/MEV attack surface | Model value of being last/first; quantify block proposer advantage |
| Sybil majority ticket extraction | Sybil/collusion analysis | EV model for N% ticket ownership across levels |
| Unchecked arithmetic in hot paths | Token/pass math verification | JackpotModule and JackpotBucketLib: verify all 40 unchecked blocks have documented invariants |
| receive() ETH routing to wrong pool | ETH flow accounting | Enumerate all ETH entry points; verify correct accounting destination |

---

## Sources

- Chainlink VRF V2.5 Security Considerations (official): https://docs.chain.link/vrf/v2-5/security — HIGH confidence
- Solodit Checklist SOL-AM-MA-1/2/3 Miner Attacks (Cyfrin): https://www.cyfrin.io/blog/solodit-checklist-explained-6-miner-attacks — HIGH confidence
- Lido stETH Integration Guide (official): https://docs.lido.fi/guides/lido-tokens-integration-guide/ — HIGH confidence
- Balancer $128M rounding exploit post-mortem (Check Point Research, Nov 2025): https://research.checkpoint.com/2025/how-an-attacker-drained-128m-from-balancer-through-rounding-error-exploitation/ — HIGH confidence
- Chainlink VRF white hat $300K bounty report (subscription owner attack): https://cryptoslate.com/chainlink-vrf-vulnerability-thwarted-by-white-hat-hackers-with-300k-reward/ — MEDIUM confidence
- Delegatecall storage collision survey (Finxter Academy, AllianceBlock case): https://academy.finxter.com/delegatecall-or-storage-collision-attack-on-smart-contracts/ — MEDIUM confidence
- DegenerusGameStorage.sol and DegenerusGame.sol — direct inspection (this codebase) — HIGH confidence
- DegenerusGameAdvanceModule.sol reverseFlip/nudge mechanism — direct inspection — HIGH confidence
- Unchecked arithmetic pitfalls in Solidity 0.8 (VibraniumAudits): https://www.vibraniumaudits.com/post/unchecked-math-operations-in-solidity — MEDIUM confidence

---
*Pitfalls research for: VRF-based on-chain game with delegatecall modules, prize pools, and complex token economics*
*Researched: 2026-02-28*
