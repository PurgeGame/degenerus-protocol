# Pitfalls Research

**Domain:** Smart contract security audit — VRF-based on-chain game with delegatecall modules, prize pools, and complex token economics (v2.0 Adversarial Audit)
**Researched:** 2026-03-04
**Confidence:** HIGH (contract code directly inspected; external findings corroborated across multiple sources)

---

## How to Read This File

This document extends the v1.0 pitfalls (pitfalls 1-17) with adversarial audit-specific pitfalls discovered through research into Code4rena warden patterns, post-audit exploits, and integration-specific bugs in delegatecall+VRF+pull-withdrawal architectures. Pitfalls are grouped into:

1. **Critical Pitfalls (v1.0)** — Carried forward from the systematic audit pass.
2. **Critical Pitfalls (v2.0 Adversarial)** — New categories the adversarial pass must address.
3. **What Adversarial Passes Find That First Passes Miss** — Meta-audit methodology.
4. **Integration Gotchas (updated)**, **Security Mistakes (updated)**, **Phase Mapping (updated)**.

---

## Critical Pitfalls (v1.0 — Carry-Forward)

### Pitfall 1: VRF Callback Gas Limit Overflow Causes Silent DOS

**What goes wrong:**
`rawFulfillRandomWords` is called by the Chainlink VRF coordinator with a fixed gas limit (300,000 gas as set in `VRF_CALLBACK_GAS_LIMIT`). The callback is routed via `delegatecall` to `DegenerusGameAdvanceModule`. If the callback logic consumes more gas than the limit, the coordinator call reverts internally but the coordinator does **not** retry — the randomness request is permanently dropped. The game's `rngRequestTime` stays set, the `rngLockedFlag` stays true, and the game is stalled until the 18-hour timeout expires. This is a silent failure mode: no event is emitted, no revert propagates.

Real-world precedent: Sherlock's audit of LooksRare Infiltration (2023) found a HIGH/MEDIUM gas overflow in `fulfillRandomWords` where the callback called an internal function that looped over agents and made external ERC20 transfers. The Chainlink coordinator's max gas limit is 2,500,000 for the VRF coordinator — but consumer contracts set their own lower limit, which is the actual ceiling. Chainlink's official security docs state: "If `fulfillRandomWords()` reverts, the VRF service will not attempt to call it a second time."

**Why it happens:**
Auditors focus on whether the callback validates correctly, not whether it fits within the gas envelope. The callback routes through a delegatecall, adding overhead. As lootbox state grows (pending eth, pending burnie, index mappings), the callback may creep toward the limit over the life of the game.

**How to avoid:**
- Measure the gas cost of `rawFulfillRandomWords` with worst-case state (maximum lootbox pending, maximum nudge count) using `forge test --gas-report` or gas snapshots.
- Ensure the callback stays under 200,000 gas with comfortable headroom so growth over the game's lifetime doesn't push it past 300,000.
- The callback should store the word and return; all complex logic should be deferred to the next `advanceGame()` call.
- Grep for `grep -n "rawFulfillRandomWords\|fulfillRandomWords" contracts/` and audit every line in the callback path.

**Warning signs:**
- Callback cost climbing above 150,000 gas in tests with large lootbox state.
- Any additional logic added to the callback path without a gas re-measurement.

**Phase to address:** VRF/RNG security phase (adversarial audit).

---

### Pitfall 2: Stale VRF Request ID Allows Late Fulfillment to Corrupt State

**What goes wrong:**
The Chainlink VRF coordinator can fulfill a request at any time — including after a timeout retry has issued a new request. The current guard `if (requestId != vrfRequestId || rngWordCurrent != 0) return;` drops old fulfillments correctly. But the dropped lootbox index reservation (`lootboxRngRequestIndexById[oldRequestId]`) may not be cleaned up if the retry logic didn't handle the transition atomically. An orphaned entry could mislead off-chain indexers or be exploited by `openLootBox` with a stale index.

**Why it happens:**
Retry logic in `_finalizeRngRequest` remaps the reserved lootbox index from the old request ID to the new one only on the retry path. Late-arrival fulfillments for the old ID after a retry is fulfilled leave orphaned entries.

**How to avoid:**
- Verify by code review that all paths through the VRF request lifecycle (fresh, retry, late-arrive) leave `lootboxRngRequestIndexById` in a consistent state.
- Check whether orphaned entries can be exploited by a player calling `openLootBox` with a stale index.
- Test: trigger a retry, fulfill the new request, then send a fulfillment for the old request ID — verify the game is in correct state with no exploitable residue.

**Warning signs:**
- Test coverage does not include late-arrival of an old fulfillment after a retry has been fulfilled.
- `lootboxRngRequestIndexById` entries growing monotonically without cleanup.

**Phase to address:** VRF/RNG security phase.

---

### Pitfall 3: Nudge Mechanism Lets Coordinated BURNIE Holders Bias RNG Outcomes

**What goes wrong:**
The `reverseFlip()` function allows any BURNIE holder to add +1 to the upcoming VRF word by burning BURNIE. A coordinated group that accumulates BURNIE and purchases nudges shifts the random word by a known integer, changing jackpot bucket or trait selection. After VRF fulfillment, the word is visible in mempool before `advanceGame()` is called. A block proposer can see the fulfilled word and the desired offset, then sequence nudge transactions and `advanceGame()` in the same block.

Chainlink's official security guidance: "Lock the contract to further user inputs immediately after submitting the randomness request and before fulfillment." The critical question is whether this lock is maintained after the word arrives but before it is processed.

**How to avoid:**
- Verify `rngLockedFlag` remains set from VRF request through the `advanceGame()` call that consumes the word.
- Trace every code path where `rngLockedFlag` is cleared and confirm no window exists between word arrival and word consumption.
- Grep: `grep -n "rngLockedFlag" contracts/` — audit every write.

**Warning signs:**
- Any code path where `rngLockedFlag` is cleared before `rngWordCurrent` is consumed.
- Test coverage that does not validate nudges cannot be added after VRF fulfillment but before word processing.

**Phase to address:** VRF/RNG security phase.

---

### Pitfall 4: Delegatecall Return Value Propagation Masks Reverts

**What goes wrong:**
Every delegatecall in `DegenerusGame` follows the pattern:
```solidity
(bool ok, bytes memory data) = MODULE.delegatecall(...);
if (!ok) _revertDelegate(data);
```
If `_revertDelegate` doesn't correctly propagate the revert reason, callers receive an opaque failure. More critically: if any delegatecall path returns `true` with malformed return data, `_revertDelegate` is never called and the caller sees "success" with garbage return data silently decoded. V1.0 audit confirmed all 30 call sites use a uniform checked pattern — the adversarial pass must verify `_revertDelegate` itself is correct.

**How to avoid:**
- Review `_revertDelegate` to confirm it propagates the full error selector and data without truncation.
- Review every delegatecall return value decoding: does each decoded return value match the expected type?
- Add fuzz tests that send malformed return data from modules (forge fuzzing can do this).

**Warning signs:**
- Any module function with multiple return paths where some return values are uninitialized.
- Delegatecall results decoded with `abi.decode` without length validation.

**Phase to address:** Reentrancy and cross-contract attack phase.

---

### Pitfall 5: Storage Slot Layout Drift in Delegatecall Modules

**What goes wrong:**
`DegenerusGameStorage` defines the canonical storage layout used by `DegenerusGame` and all 10 modules. If any module inherits a contract that adds a storage variable **before** importing `DegenerusGameStorage`, the module's storage view is shifted. This is the storage collision attack — documented in Audius ($6M hack, 2022) and AllianceBlock upgrade (2024). V1.0 audit confirmed zero collisions — the adversarial pass must re-verify this claim with automated tooling, not just visual review.

**How to avoid:**
- Generate storage layout reports with `forge inspect DegenerusGameAdvanceModule storage-layout` and compare against `forge inspect DegenerusGame storage-layout` for every slot from 0 onward.
- Run this check for all 10 modules.
- Any mismatch at any slot is critical and blocks deployment.

**Warning signs:**
- Any module that inherits from more than one parent.
- New imports added to module files without a storage layout re-check.
- A module that declares its own storage variables.

**Phase to address:** Reentrancy and cross-contract attack phase (standalone verification step).

---

### Pitfall 6: Prize Pool Invariant Break Via stETH Rebasing

**What goes wrong:**
The critical invariant is `address(this).balance + steth.balanceOf(this) >= claimablePool`. Lido stETH rebases daily — balances change without transfer events. Contracts that store a `steth.balanceOf(this)` snapshot then use it later for payout calculations can undercount if rebase happened between calculation and execution.

Lido's integration guide states: "stETH balances change upon transfers, mints/burns, and rebases — do not cache balances over extended periods." Code4rena's 2023 Kelp DAO audit found a stETH rebasing bug where the deposit limit invariant became inaccurate due to balance fluctuation.

**How to avoid:**
- Verify that no function stores `steth.balanceOf(this)` in a state variable and uses that stored value for payout calculations.
- Verify that `claimWinnings` uses the live balance at payout time.
- Grep: `grep -n "steth\|stETH" contracts/` — audit every read/write.

**Warning signs:**
- Any mapping or state variable holding a previously-read stETH balance.
- Payout logic using two separate `steth.balanceOf` calls assuming they are equal.

**Phase to address:** ETH accounting invariant phase (remaining v1.0 gap).

---

### Pitfall 7: Rounding Direction Errors Accumulate to Protocol Drain

**What goes wrong:**
The Balancer $128M exploit (Nov 2025) demonstrated that rounding errors in integer division, when compound across many operations, can be exploited to drain funds. This protocol has numerous BPS calculations (`PURCHASE_TO_FUTURE_BPS`, jackpot slices, affiliate shares, EV multipliers). If any consistently round in the player's favor, a coordinated attacker making many small operations can extract more than expected.

**How to avoid:**
- For every fee/split formula, verify which direction rounding favors (protocol or player).
- Fuzz with `amount` values of 1 wei, 2 wei, and tiny amounts to see if splits sum to more or less than input.
- Verify sum of all split components equals input for every split formula (no dust accumulation).
- Grep: `grep -n "bps\|BPS\|10000" contracts/` — audit every division involving basis points.

**Warning signs:**
- Any formula `a * bps / 10000` followed by `remainder = total - computed` — check both sum to `total`.
- Lootbox EV multiplier with activity score — small scores could yield 0 bonus.

**Phase to address:** ETH accounting invariant phase.

---

### Pitfall 8-17 (v1.0)

Pitfalls 8-17 from v1.0 are carried forward as-is:
- **P8:** Operator approval enables cross-player manipulation
- **P9:** ERC20 return value ignored on BURNIE/DGNRS transfers
- **P10:** Game-over payout underpays if stETH fluctuates during settlement
- **P11:** Block proposer can reorder `advanceGame` and player purchases
- **P12:** Sybil groups extract proportional prize pool by owning majority tickets
- **P13:** Unchecked arithmetic in module hot paths bypasses overflow protection
- **P14:** `receive()` routes all ETH to `futurePrizePool` — accidental funding miscounts
- **P15:** Generic `E()` error hides root cause in complex audit paths
- **P16:** VRF subscription balance griefing
- **P17:** Deity pass triangular pricing formula overflow for high pass count

Full detail for each is in the v1.0 PITFALLS document (archived). See Phase Mapping at the bottom of this document for where each maps in v2.0 phases.

---

## Critical Pitfalls (v2.0 Adversarial — New)

These are the pitfalls that adversarial audit passes (Code4rena wardens, second-pass analysts) commonly find after a systematic first pass. Sources: Code4rena/Sherlock report patterns, post-audit exploit post-mortems, and integration-specific research.

---

### Pitfall 18: Admin Power Vectors the v1.0 Audit Accepted as "Trusted"

**What goes wrong:**
V1.0 completed the access control matrix and confirmed privilege assignments. However, a Code4rena context requires a different framing: **every admin capability that can halt, drain, or grief the game must be enumerated as a potential finding.** In competitive audit contests, wardens frequently escalate "trusted admin" issues to HIGH/MEDIUM when the admin can:
- Halt the game indefinitely (e.g., never calling `advanceGame`, or triggering the 3-day emergency stall and never recovering it)
- Drain the prize pool via a privileged withdrawal function
- Permanently block all winner withdrawals by manipulating the payout state
- Grief individual players through ticket invalidation or affiliate nullification

The Code4rena Tigris audit (2022) found HIGH: "owner can freeze withdraws and use timelock to steal all funds." The reNFT audit (2024) found admin functions that bypassed user protections.

**Why it happens:**
V1.0 audits typically confirm that admin functions are gated correctly (only admin can call them). Adversarial audits ask whether those functions should exist at all from a player trust perspective, and whether their combination enables stealth rug vectors.

**How to avoid:**
- List every admin-only function that touches: (a) payout state, (b) VRF subscription, (c) contract addresses, (d) prize pool balances.
- For each: model the worst case if the admin key is compromised or malicious.
- Assess whether the 3-day emergency stall, combined with `adminSweepResidual`, combined with `adminSwapEthForStEth`, creates a rug path that bypasses the 30-day BURNIE timeout.
- Check if `wireVrf` or `setSubscriptionId` can be called post-deployment to redirect VRF callbacks to a malicious coordinator.

**Warning signs:**
- Any admin function callable at any game state that modifies payout addresses or VRF coordinator address.
- Admin functions with no time delay or multi-sig requirement on fund movements.
- A sequence of 2-3 admin calls that collectively extract the prize pool without triggering visible on-chain alarms.

**Phase to address:** Admin power map phase (first task in v2.0).

---

### Pitfall 19: `advanceGame()` Gas Ceiling Fails Under Adversarial State

**What goes wrong:**
`advanceGame()` is the critical state-advancing function with a 16M gas hard limit. V1.0 confirmed all loops are bounded. However, adversarial analysis requires measuring the worst-case call graph through a combination of:
- Maximum number of jackpot bucket updates per day
- Maximum Sybil-bloated lootbox state (if an attacker created maximum pending lootbox indices)
- Maximum degenerette resolution path
- BAF multi-level scatter jackpot (commit 9442375: multi-level scatter targeting)

If any adversarially-constructed state pushes `advanceGame()` past 16M gas, the function becomes permanently uncallable, stalling the game. The Infiltration audit demonstrated that game loop DoS via gas exhaustion is a recognized vulnerability class in on-chain games using VRF.

**Why it happens:**
V1.0 loop analysis verified individual bounds but did not measure worst-case composition. A single function call can traverse multiple modules in sequence; the aggregate gas cost with adversarial state may exceed individual module bounds.

**How to avoid:**
- Instrument `advanceGame()` with gas measurement via `forge test --gas-report` under worst-case state construction.
- Write a test that: (1) maximizes lootbox pending indices, (2) maximizes jackpot scatter targets, (3) triggers BAF scatter, (4) measures gas.
- Identify any input-controlled growth vector (Sybil can buy N tickets, does each ticket add O(1) state to `advanceGame()`?).
- Grep: `grep -rn "for\|while" contracts/game/` — enumerate every loop in the `advanceGame()` call graph.

**Warning signs:**
- Any loop whose iteration count is proportional to total player count or total ticket count (unbounded with Sybil).
- `advanceGame()` gas in tests exceeding 8M (over 50% of the limit under non-adversarial state is a warning).

**Phase to address:** `advanceGame()` gas analysis phase (first task after admin map).

---

### Pitfall 20: Cross-Function Reentrancy via ERC721 `onERC721Received` Callback

**What goes wrong:**
`DegenerusNFT.safeMint()` triggers `onERC721Received` on the recipient if it is a contract. If any game function calls `safeMint` before finalizing all state updates (CEI violation), an attacking contract can reenter via the callback:

1. Attacker calls `claimWinnings(attacker_contract)` or any function ending in `safeMint`.
2. During `onERC721Received`, attacker's contract calls back into `claimWinnings` or `purchaseWhaleBundle`.
3. Second call sees stale pre-update state (winner not yet cleared, ticket not consumed).

Real-world precedent: Code4rena's AI Arena audit (2024) found HIGH H-08: `claimRewards()` contained reentrancy enabling excessive NFT minting. The attack vector was precisely this pattern — `claimRewards` called `_safeMint` before zeroing the claimable balance.

This is the hardest category for first-pass auditors to catch because the reentrancy path goes through an ERC721 callback, not an ETH transfer, and `nonReentrant` guards are often applied only to ETH withdrawal functions.

**How to avoid:**
- Identify every function in the protocol that calls any `safeMint` or `safeTransferFrom` on a user-controlled address.
- For each: verify state is finalized before the external call (CEI pattern).
- Verify `nonReentrant` guards are present on all entry points that could be reentered via this callback chain, including delegatecall paths.
- Grep: `grep -rn "safeMint\|safeTransferFrom\|_safeMint" contracts/` — enumerate every site.

**Warning signs:**
- Any `safeMint` call that occurs before the calling function zeroes claimable balances or updates a lock flag.
- `nonReentrant` present on ETH withdrawal functions but absent on NFT minting functions.
- Any function where the user can receive an ERC721 token AND simultaneously trigger a callback into the same contract.

**Phase to address:** Reentrancy and cross-contract attack phase.

---

### Pitfall 21: VRF Subscription Owner Attack Vector (Malicious Admin)

**What goes wrong:**
Chainlink's $300K Immunefi bounty (2022) revealed: the VRF subscription owner can block randomness fulfillment and reroll requests until receiving a favorable outcome. The Degenerus Admin contract owns the VRF subscription. If the admin key is compromised, the attacker becomes the subscription owner and can:
1. Block all `fulfillRandomWords` callbacks until a favorable VRF word arrives for a jackpot outcome.
2. Fund the subscription with minimal LINK to cause fulfillment delays.
3. Remove the game contract as a consumer, permanently stalling all VRF requests.

This attack requires the admin key to be compromised, making it a MEDIUM or HIGH severity finding depending on the admin's key management setup. In Code4rena contexts, this is often rated MEDIUM ("trusted admin" with a critical power vector).

**How to avoid:**
- Confirm the admin key uses a hardware wallet or multi-sig in production.
- Assess whether the VRF subscription should be owned by a time-locked multi-sig rather than a single EOA.
- Verify that no player-controlled action can remove the game as a VRF consumer.
- Document this as a known centralization risk in the protocol's threat model documentation.

**Warning signs:**
- Admin contract owns the VRF subscription with a single private key.
- No time delay on VRF consumer management functions.
- VRF subscription LINK balance can be set to zero by admin, enabling selective fulfillment blocking.

**Phase to address:** VRF/RNG security phase and admin power map phase (overlapping concern).

---

### Pitfall 22: Business Logic Invariant: ETH Accounting Completeness (Unfinished v1.0 Gap)

**What goes wrong:**
V1.0 explicitly identified: "Phase 4 (ETH accounting invariant) — 8 of 9 plans unexecuted." This is the largest remaining gap. The accounting invariant is:

```
sum(claimableAmounts[all players]) + futurePrizePool + currentPrizePool
  <= address(this).balance + steth.balanceOf(this)
```

If this invariant can be violated — through rounding, through a reentrancy on `claimWinnings`, through a fee split error, through an unchecked return value from BURNIE burn — players cannot collect their winnings. This is the class of bug that is hardest to catch on first pass because it requires modeling the entire ETH lifecycle, not just individual functions.

Real-world precedent: Euler Finance was exploited via interactions between donation functions, liquidation mechanisms, and collateral accounting that line-by-line code review could not detect. The Balancer $128M exploit was a rounding error that broke the pool invariant.

**How to avoid:**
- Write an invariant test (foundry invariant testing) that runs all game actions in random order and asserts the accounting invariant holds after each.
- Manually trace every ETH entry point to its accounting destination.
- Manually trace every ETH exit point and verify it subtracts from the correct accounting variable.
- Test the invariant at game-over after all players claim winnings: `address(this).balance` should be 0 or near-0 with no unclaimed pools.

**Warning signs:**
- Any function that modifies `claimableAmounts[player]` without a corresponding modification to the global accounting pool.
- Any ETH transfer that is not preceded by a corresponding decrement of `currentPrizePool` or `futurePrizePool`.
- The `claimWinnings` function updating state after the ETH transfer (CEI violation enabling reentrancy that bypasses the invariant).

**Phase to address:** ETH accounting invariant phase (must complete before adversarial audit closes).

---

### Pitfall 23: Multicall / Operator Proxy Reentrancy via Delegatecall

**What goes wrong:**
If the protocol has any multicall-like mechanism, or if `setOperatorApproval` + operator-proxied calls can be composed in a single transaction, a delegatecall-based reentrancy attack becomes possible. Real-world precedent: MakerDAO (Sherlock, 2024, HIGH): "Multicall Reentrancy Exploit via Delegatecall" — the Multicall contract's use of `delegatecall` to execute multiple function calls within the calling contract's context allowed reentrancy if any called function was not guarded.

In this protocol, the concern is: can an operator-proxied call sequence that includes a delegatecall to a module trigger reentry into a different module via a callback?

**How to avoid:**
- Map all operator-proxied functions and verify that the delegatecall chain they invoke is fully guarded.
- Check whether `setOperatorApproval` + batch operator calls can be combined to call the same function twice in one tx while the first call's state updates are pending.
- Verify the `nonReentrant` guard, if present, covers the full delegatecall chain (a guard at the `DegenerusGame` entry point but not inside the module is insufficient if the module makes external calls).

**Warning signs:**
- Operator-proxied functions that invoke delegatecall and then make external calls (ERC20 transfers, ETH sends) in the same transaction.
- Missing `nonReentrant` at the `DegenerusGame` level on all state-modifying entry points.

**Phase to address:** Reentrancy and cross-contract attack phase.

---

### Pitfall 24: Last-Mover / Last-Purchaser Economic Advantage at Phase Boundary

**What goes wrong:**
On-chain games with discrete phase transitions (purchase phase → VRF → resolution) have a structural vulnerability: the last purchaser before phase close, or the first purchaser after phase open, may have a provable economic advantage. Block proposers who are players can capture this advantage reliably. In Code4rena game audits, this class of finding (classified under MEV/validator attacks) has been rated MEDIUM when the advantage is quantifiable and the proposer can capture it deterministically.

Specific risks for this protocol:
- Lootbox index reservation at the start of a new round (earlier index may have better timing relative to VRF word).
- The VRF word is determined by the block in which the VRF request is sent — a block proposer can control when `advanceGame()` is called to influence which block generates the entropy seed.
- Price escalation last-ticket purchase: the ticket that pushes the price to the next tier benefits from being the last at the lower price.

**How to avoid:**
- Model the value of being the last purchaser at each price tier.
- Model the value of controlling the block number in which the VRF request lands.
- If advantages are quantifiable and exceed ~0.1 ETH for a 1000-ETH adversary, flag as MEDIUM.
- For VRF block selection: verify whether the VRF request block hash can be influenced by a validator who delays or reorders blocks.

**Warning signs:**
- Any game variable computed from `block.number` at request time that influences jackpot outcomes.
- Price tier boundaries where the last ticket at tier N and first at tier N+1 create measurable EV difference.
- `advanceGame()` bounty payable to the caller creates incentive to be the phase transition executor.

**Phase to address:** Economic attacks phase.

---

### Pitfall 25: Integer Underflow in `unchecked` Blocks Under Adversarial Wallet State

**What goes wrong:**
225 `unchecked` blocks exist across the codebase. V1.0 confirmed individual blocks have documented invariants. The adversarial audit must check that those invariants cannot be violated by an attacker who manipulates the state through a sequence of legitimate calls. Example pattern: a decrement in an unchecked block relies on the invariant "variable X is always >= amount" — but if a separate function can set X to 0 through a different code path before the decrement runs, the invariant breaks and the underflow wraps around to `type(uint256).max`.

The JackpotModule has 40 unchecked blocks — the highest density — and should receive the most scrutiny. The `capBucketCounts` underflow guard fix (commit 9539c6d) indicates this class of bug has already been found in this codebase.

**How to avoid:**
- For every unchecked block that decrements, find every code path that could set the decremented variable to 0 or below the expected floor.
- Grep: `grep -n -A 3 "unchecked" contracts/game/DegenerusGameJackpotModule.sol` — audit all 40 blocks in JackpotModule.
- Write fuzz tests that explore state sequences (not just individual function calls) targeting each unchecked decrement.

**Warning signs:**
- Unchecked decrements in JackpotModule whose invariant depends on a carryover value computed in a previous `advanceGame()` call.
- The `capBucketCounts` guard was recently added — check if similar guards are needed elsewhere.
- Any unchecked block whose invariant comment says "always >= 0" without proof.

**Phase to address:** Integer math and edge cases phase.

---

### Pitfall 26: BURNIE 30-Day Liveness Guard Bypass via BURNIE Ticket Purchase Window

**What goes wrong:**
The v1.0 audit added F01 HIGH: whale bundle lacks level eligibility guard. Commit 4592d8c adds: "block BURNIE ticket purchases within 30 days of liveness-guard timeout." This guard was added to prevent a specific class of exploit. The adversarial pass must verify:
1. The guard cannot be bypassed through operator-proxied purchases.
2. The guard correctly uses the same timestamp comparison as the liveness guard itself.
3. The guard does not have an off-by-one on the 30-day window (block.timestamp vs block.number, timezone effects, etc.).
4. The guard applies to ALL ticket purchase paths, not just the one tested.

**Why it matters:**
Guards added in response to audit findings are a common location for residual bugs in adversarial review. The mitigation review (second pass) is exactly where Code4rena wardens look: "did the fix introduce a new bug or leave a bypass?"

**How to avoid:**
- Read commit 4592d8c diff in full.
- Identify all ticket purchase entry points (direct purchase, operator-proxied, whale bundle, lazy pass, deity pass, BURNIE purchase variant).
- Verify the 30-day guard is applied consistently across all paths with the same timestamp comparison.
- Fuzz the boundary: call a purchase at exactly `timeout - 30 days` (allowed), `timeout - 30 days + 1` (should be blocked), and `timeout - 30 days - 1` (should be allowed).

**Warning signs:**
- Any purchase path that does not call the same internal validation function containing the 30-day guard.
- The guard using `block.timestamp >= livenessTimeout - 30 days` vs `livenessTimeout - 2592000` (integer constant) — one is susceptible to timestamp manipulation, the other is not.

**Phase to address:** Access control gaps phase.

---

### Pitfall 27: Degenerette Bet Resolution: CEI Order and Pull-Withdrawal Race

**What goes wrong:**
Pull-withdrawal pattern combined with delegatecall creates a specific reentrancy risk: if `resolveDegenerette()` (or equivalent) sends ETH to the winning player before updating the bet record to "resolved," a reentrancy via ETH fallback allows the player to call `resolveDegenerette` again for the same bet. The bet appears unresolved to the second call because state was not updated before the transfer.

This is a textbook CEI violation that is easy to miss because the transfer goes to a user-controlled address AND the calling contract uses delegatecall, meaning the `nonReentrant` guard (if placed on the module) does not protect the game contract's storage during the reentrant call.

**How to avoid:**
- Read `DegeneretteModule` and `resolveDegenerette` (or equivalent) fully.
- Confirm the bet resolution state is set to "resolved" before any ETH transfer or `claimable` balance update.
- Verify `nonReentrant` is at the `DegenerusGame` entry point level, not just inside the module delegatecall.
- Write a test: a contract that calls `resolveDegenerette`, then in its `receive()` calls `resolveDegenerette` again for the same bet ID — verify the second call reverts.

**Warning signs:**
- Any delegatecall module that sends ETH (directly or via `claimableAmounts` update) before zeroing the triggering state (bet ID, lock flag).
- `nonReentrant` applied to the module function but not to the `DegenerusGame` entry point.

**Phase to address:** Reentrancy and cross-contract attack phase.

---

### Pitfall 28: Token Security — `vaultMintAllowance` Abuse Vector

**What goes wrong:**
`VAULT` (deploy order N+19) calls `COIN.vaultMintAllowance()` to establish how much BURNIE the vault can mint. This allowance mechanism creates a potential abuse vector if:
1. The vault address can be changed after deployment (to a malicious contract that drains the allowance).
2. The allowance can be repeatedly reset by admin to allow unlimited minting.
3. The allowance is not decremented per-mint, only set as a cap.

BURNIE inflation beyond intended limits destroys the tokenomics: nudge cost becomes trivial if BURNIE supply is infinitely diluted.

**How to avoid:**
- Read `BurnieCoin.vaultMintAllowance()` implementation.
- Verify the vault address is immutable or set only once.
- Verify the allowance is consumed (decremented) on every mint.
- Verify only the vault (not admin) can mint via the allowance mechanism.

**Warning signs:**
- `vaultMintAllowance` can be called by admin to reset the allowance to an arbitrary value.
- Vault address is settable by admin post-deployment with no time delay.

**Phase to address:** Token security phase.

---

## What Adversarial Passes Find That First Passes Miss

This section synthesizes Code4rena/Sherlock patterns into a checklist for the adversarial audit team. These are meta-observations about audit methodology, not specific pitfalls.

### Meta-Pattern 1: Interaction Between Correct-But-Composable Functions

First-pass audits verify functions are correct in isolation. Adversarial wardens ask: "what happens when a player calls A, then B, then C in the same block?" Euler Finance was exploited this way — three individually correct functions composed in a way auditors never tested. For Degenerus: what happens if a player purchases a ticket, immediately calls `reverseFlip`, triggers a lootbox open, and then operator-proxies a degenerette resolution in the same transaction?

**Implication:** Write adversarial scenario tests that chain 3-5 operations in a single transaction and verify game state invariants hold after each step.

### Meta-Pattern 2: Mitigation Bypasses

Code4rena mitigation reviews (second pass) are where wardens look hardest. Commit 4592d8c (BURNIE 30-day guard), 36084a1 (subscriptionId widening), cbbafa0 (1 wei sentinel), 9539c6d (capBucketCounts underflow) — every recent fix is a candidate for a bypass or incomplete fix. Specifically:
- Was the fix applied to ALL relevant code paths or just the one tested?
- Did the fix introduce a new edge case (e.g., the 1 wei sentinel in degenerette — does it create a new underflow path elsewhere?)?
- Did the fix change the gas profile of `advanceGame()` in a way that pushes it closer to the 16M limit?

**Implication:** For each of the last 5 commits, write a targeted test that probes the fix boundary.

### Meta-Pattern 3: Trust Boundary Misconfiguration

First-pass audits confirm that A can call B and B cannot be called by C. Adversarial wardens ask: "can C cause A to call B in a way A didn't intend?" In this protocol: can a player cause the admin to call a function (via griefing the admin into an emergency state) that benefits the player? Can a player's crafted transaction sequence cause the VRF callback to arrive in a state the protocol didn't expect?

**Implication:** Model the protocol from the perspective of a player who controls the timing of their own calls and can observe (but not control) admin and VRF actions.

### Meta-Pattern 4: Gas Griefing on Admin Functions

If an admin function iterates over player state (e.g., `handleGameOverDrain` from FSM-F02), a Sybil attacker who creates many small accounts can push the admin function above the block gas limit, making it permanently uncallable. V1.0 confirmed all loops are bounded — the adversarial pass must verify the bounds are tight enough to prevent griefing.

**Implication:** For every admin function with a loop, measure worst-case gas with maximum state.

### Meta-Pattern 5: Stale Assumption Drift

V1.0 assumptions that may have drifted since audit began:
- Chainlink VRF V2.5 confirmation times (may have changed on mainnet).
- Lido stETH behavior under edge conditions (slashing parameters).
- The deploy order N+X assumptions embedded in test fixtures — are they still correct after recent contract additions?

**Implication:** Re-verify all external dependency assumptions with current documentation before the final report.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Generic `E()` error for all guards | Saves bytecode, stays under 24KB | Audit + debugging cost, unclear failure reasons | Acceptable for size-constrained contracts; must be mapped in tests |
| 225 unchecked blocks for gas | Gas reduction in hot paths | Each block must be individually audited; adversarial sequences may violate invariants | Only where invariant is documented and proved unreachable by adversarial state |
| Compile-time constant contract addresses | No governance attack surface | Any address mistake requires full redeploy | Acceptable for non-upgradeable protocol |
| `receive()` routes all ETH to `futurePrizePool` | Simple funding mechanism | Silent miscounting if ETH arrives unexpectedly | Never in high-value multi-pool accounting without explicit enumeration of all ETH sources |
| `delegatecall` pattern without upgrade mechanism | No proxy attack surface | Storage layout must be manually verified on every module change | Acceptable if verified by `forge inspect` on every PR |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Chainlink VRF V2.5 | `rawFulfillRandomWords` gas limit exceeded causes permanent stall | Measure worst-case gas; keep callback under 200K; defer work to next `advanceGame()` call |
| Chainlink VRF V2.5 | Subscription owner can block/reroll fulfillments | Admin key must be secured; document as centralization risk; consider time-locked multi-sig ownership |
| Chainlink VRF V2.5 | Assuming failed fulfillment will be retried | It will not; the game's 18h timeout is the only recovery — verify it is reachable from all failure states |
| Chainlink VRF V2.5 | VRF request from wrong block influenced by validator | Verify VRF request is sent in a deterministic block relative to game state; validator reorder window |
| Lido stETH | Caching `balanceOf` for payout calculations | Always call `balanceOf` live at payout time; never cache rebasing token balances |
| Lido stETH | `steth.transfer(amount)` sends exactly `amount` | May send 1-2 wei less due to share rounding; use `transferShares()` for exact amounts |
| BURNIE ERC20 | Assuming `burnCoin` reverts on failure | Must verify — if it returns false, nudge purchases are potentially free |
| ERC721 `safeMint` | Calling before state update enables `onERC721Received` reentrancy | Always finalize state before `safeMint`; add `nonReentrant` to the game entry point, not just the module |

---

## Security Mistakes (Domain-Specific)

| Mistake | Risk | Prevention |
|---------|------|------------|
| Not locking user inputs between VRF request and `advanceGame` | Nudges after fulfillment change a known word — predictable outcome | Verify `rngLockedFlag` covers the full window from request to word consumption |
| Auditing modules in isolation rather than in-context | Storage layout bugs only appear when both game and module are considered together | Always check storage layout side-by-side for each module with `forge inspect` |
| Testing only "happy path" for game-over | Multi-step game-over has many timing-dependent edge cases | Test every intermediate state: what if VRF fulfillment never arrives during game-over? |
| Treating delegatecall success as proof of correct execution | A module can return `true` with zero-valued return data on an invalid path | Validate return data length and non-zero values where expected |
| Ignoring affiliate credit flows in operator-proxied calls | Affiliate credit may go to operator, not player | Trace `msg.sender` vs `player` in every proxied call that touches affiliate state |
| Accepting admin functions as "trusted" without modeling compromise | Compromised admin = subscription owner attack, prize pool drain | Map every admin power and its consequence if key is compromised |
| Verifying loop bounds without testing adversarial state composition | Sybil bloat creates state that passes individual bounds but fails composite | Measure `advanceGame()` gas with maximum concurrent adversarial state |
| Applying `nonReentrant` only to ETH-sending functions | ERC721 `safeTransferFrom` and `safeMint` also trigger callbacks | Add `nonReentrant` to all external entry points that eventually call `safeMint` or `safeTransferFrom` |
| Treating recent fix commits as closed issues | Mitigation bypasses are the most common Code4rena mitigation-review finding | For each of commits 4592d8c, cbbafa0, 9539c6d: write a targeted bypass attempt test |

---

## "Looks Done But Isn't" Checklist

Carried from v1.0, extended for v2.0 adversarial scope:

- [ ] **VRF gas budget:** The callback stays under 200,000 gas with worst-case lootbox state — not just average state.
- [ ] **Storage layout verification:** `forge inspect` run on all 10 modules and compared slot-by-slot against the game contract, not just visually reviewed.
- [ ] **Nudge window:** `reverseFlip` is provably blocked from the moment VRF word arrives until `advanceGame` consumes and clears it.
- [ ] **stETH accounting:** No path caches `steth.balanceOf(this)` in a state variable between transactions.
- [ ] **Fee splits sum to input:** Every BPS split verified that the two halves equal the original amount (no dust gains or losses).
- [ ] **Operator abuse:** Every `_resolvePlayer()` call site verified that value flows to `player`, not `msg.sender`.
- [ ] **BURNIE burn return value:** `burnCoin` implementation verified to revert (not return false) on insufficient balance.
- [ ] **Game-over with zero stETH:** Settlement path tested when `steth.balanceOf(this)` is 0 (ETH-only treasury).
- [ ] **Late VRF fulfillment:** Test that a fulfillment for an old request ID after a retry is fulfilled is safely ignored with no state corruption.
- [ ] **VRF subscription consumers:** Only admin-controlled; no public function to add consumers.
- [ ] **Admin rug sequence:** No combination of 2-3 admin calls extracts prize pool without 30-day BURNIE timeout.
- [ ] **`advanceGame()` gas ceiling:** Worst-case state (max lootbox + BAF scatter + max degenerette resolution) stays under 12M gas (75% of 16M limit).
- [ ] **ERC721 reentrancy:** Every `safeMint` call site verified: state is finalized before mint; `nonReentrant` at game entry point.
- [ ] **ETH accounting invariant:** Foundry invariant test confirms `sum(claimable) <= balance + stethBalance` holds across all action sequences.
- [ ] **BURNIE 30-day guard:** Applied identically to ALL ticket purchase paths (direct, operator-proxied, all pass types).
- [ ] **Mitigation fix verification:** Commits 4592d8c, cbbafa0, 9539c6d each have a dedicated adversarial test probing the fix boundary.
- [ ] **`vaultMintAllowance` consumed per-mint:** Not just a cap that can be reset arbitrarily.
- [ ] **Degenerette resolution CEI:** Bet marked resolved before ETH/claimable update; reentrancy test written.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| VRF callback gas limit exceeded (DOS) | LOW | Wait 18h for timeout; retry fires automatically on next `advanceGame` call |
| Storage slot collision found | HIGH | Full redeployment required; no in-place fix possible for non-upgradeable contracts |
| Prize pool invariant broken (funds stuck) | HIGH | Admin ETH injection via `receive()` is possible but requires trust in admin key security |
| stETH slashing drains payout buffer | MEDIUM | Admin can inject ETH via `receive()`; communicate pro-rata reduction to players |
| Sybil group extracts excess prize pool | HIGH | No on-chain remedy; economics must be correct from day one |
| Admin key compromised (subscription attack) | HIGH | Subscription consumer removal possible if new key can be recovered; fund loss if prize pool drained |
| ERC721 reentrancy exploit active | HIGH | No on-chain pause mechanism; requires emergency ETH injection to restore invariant |
| `advanceGame()` gas DoS from adversarial state | MEDIUM | Emergency stall (3-day) buys time; recovery requires game-over or state cleanup |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| VRF callback gas limit DOS (P1) | VRF/RNG security phase | `forge test --gas-report` on `rawFulfillRandomWords` with max state |
| Stale VRF request ID (P2) | VRF/RNG security phase | Test: old fulfillment arrives after retry is fulfilled |
| Nudge window exploitable (P3) | VRF/RNG security phase | Trace `rngLockedFlag` state transitions through full VRF lifecycle |
| Delegatecall return propagation masks reverts (P4) | Reentrancy phase | Unit test every delegatecall with deliberately malformed module |
| Storage slot layout drift (P5) | Reentrancy phase | `forge inspect` all 10 modules; automated slot comparison script |
| stETH rebasing breaks invariant (P6) | ETH accounting invariant phase | Test with live balance snapshot; test slashing scenario |
| Rounding accumulation drains protocol (P7) | ETH accounting invariant phase | Fuzz all split formulas with values 1 wei to 1000 ETH |
| Operator approval manipulation (P8) | Access control gaps phase | Trace value flows in operator-proxied calls for every entry point |
| BURNIE return value ignored (P9) | Token security phase | Read `burnCoin` implementation; verify revert vs return false |
| Game-over stETH settlement (P10) | ETH accounting invariant phase | Simulate multi-block settlement with rebase occurring between steps |
| Block proposer reorders phase boundary (P11) | Economic attacks phase | Model value of being last/first; quantify block proposer advantage |
| Sybil majority ticket extraction (P12) | Economic attacks phase | EV model for N% ticket ownership across levels |
| Unchecked arithmetic in hot paths (P13) | Integer math phase | JackpotModule: verify all 40 unchecked blocks have documented invariants |
| `receive()` ETH routing (P14) | ETH accounting invariant phase | Enumerate all ETH entry points; verify correct accounting destination |
| Admin power rug vectors (P18) | Admin power map phase | Map every admin function; model worst-case if key is compromised |
| `advanceGame()` gas ceiling (P19) | `advanceGame()` gas analysis phase | `forge test --gas-report` with adversarial max state; BAF scatter |
| ERC721 `onERC721Received` reentrancy (P20) | Reentrancy phase | Test: contract re-enters via `onERC721Received`; verify `nonReentrant` at entry point |
| VRF subscription owner attack (P21) | VRF/RNG security phase and admin map | Document centralization risk; verify no player-controlled consumer removal |
| ETH accounting invariant (P22) | ETH accounting invariant phase | Foundry invariant test: `sum(claimable) <= balance + stethBalance` holds |
| Multicall/operator delegatecall reentrancy (P23) | Reentrancy phase | Map operator-proxied delegatecall chains; verify `nonReentrant` coverage |
| Last-mover economic advantage (P24) | Economic attacks phase | Model EV of controlling phase transition block |
| Unchecked underflow via adversarial state (P25) | Integer math phase | Fuzz JackpotModule with state sequences targeting unchecked decrements |
| BURNIE 30-day guard bypass (P26) | Access control gaps phase | Test all purchase paths; probe fix boundary for commit 4592d8c |
| Degenerette CEI violation (P27) | Reentrancy phase | Write reentrancy test via ETH fallback on bet resolution |
| `vaultMintAllowance` abuse (P28) | Token security phase | Read `vaultMintAllowance` implementation; verify per-mint decrement |

---

## Sources

**HIGH Confidence (official docs, verified code):**
- Chainlink VRF V2.5 Security Considerations (official): https://docs.chain.link/vrf/v2-5/security
- Lido stETH Integration Guide (official): https://docs.lido.fi/guides/lido-tokens-integration-guide/
- DegenerusGameStorage.sol, DegenerusGame.sol, commit history — direct inspection (this codebase)
- Balancer $128M rounding exploit post-mortem (Check Point Research, Nov 2025): https://research.checkpoint.com/2025/how-an-attacker-drained-128m-from-balancer-through-rounding-error-exploitation/

**MEDIUM Confidence (multiple corroborating sources):**
- Sherlock LooksRare Infiltration audit — VRF gas overflow finding (2023): https://github.com/sherlock-audit/2023-10-looksrare-judging/issues/136
- Chainlink VRF white hat $300K bounty (subscription owner attack, 2022): https://cryptoslate.com/chainlink-vrf-vulnerability-thwarted-by-white-hat-hackers-with-300k-reward/
- Code4rena AI Arena audit — ERC721 reentrancy in `claimRewards` H-08 (2024): https://code4rena.com/reports/2024-02-ai-arena
- Code4rena Tigris audit — admin freeze/drain finding (2022): https://github.com/code-423n4/2022-12-tigris-findings/issues/377
- MakerDAO Sherlock audit — Multicall delegatecall reentrancy (2024): https://github.com/sherlock-audit/2024-06-makerdao-endgame-judging/issues/47
- OWASP Smart Contract Top 10 (2025) — unchecked returns, reentrancy patterns: https://owasp.org/www-project-smart-contract-top-10/2025/en/src/SC06-unchecked-external-calls.html
- Delegatecall storage collision survey (Finxter Academy, AllianceBlock case): https://academy.finxter.com/delegatecall-or-storage-collision-attack-on-smart-contracts/
- Olympix: Why smart contract audits fail — business logic gap analysis: https://olympix.security/blog/why-smart-contract-audits-fail

**LOW Confidence (single source, not independently verified):**
- Code4rena reNFT mitigation review admin bypass pattern (2024) — corroborated by pattern but not specific finding

---
*Pitfalls research for: VRF-based on-chain game with delegatecall modules, prize pools, and complex token economics — v2.0 Adversarial Audit*
*Researched: 2026-03-04*
