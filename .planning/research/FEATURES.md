# C4A Warden Exploit Pattern Catalog

**Domain:** DeFi / On-chain Game Protocol (Degenerus) -- Contest Dry Run
**Researched:** 2026-03-28
**Purpose:** Ranked exploit patterns that top C4A wardens hunt, mapped to Degenerus-specific attack surfaces
**Overall Confidence:** MEDIUM-HIGH (patterns based on documented C4A/Sherlock findings and OWASP SC Top 10 2025-2026)

## How This File Works

Each pattern is ranked by **C4A hit rate** -- how frequently this class of finding produces valid HIGH/MEDIUM payouts in competitive audits. Patterns are ordered from highest to lowest probability of a real finding existing in Degenerus specifically, given its architecture (delegatecall modules, VRF, multi-pool ETH accounting, soulbound token wrapping, BPS-based splits).

For each pattern:
- **What it is** -- the exploit class
- **Why automated tools miss it** -- why Slither/4naly3er cannot catch it
- **What a warden checks** -- concrete audit steps
- **Degenerus-specific surfaces** -- where in this protocol to look
- **What a finding looks like** -- example submission format

---

## Pattern 1: Cross-Function State Inconsistency via Delegatecall Modules

**C4A Hit Rate:** VERY HIGH -- the #1 pattern in multi-module delegatecall architectures. Access control was the #1 loss category in 2024 ($953.2M per OWASP/Hacken data), but in module architectures, state inconsistency across delegatecall boundaries is the most exploitable form.
**Typical Severity:** HIGH

**What it is:** When Module A reads a storage variable that Module B modifies in the same transaction (via the Game router), the ordering of delegatecall dispatches can create windows where state is inconsistent. A warden looks for any path where a permissionless function in the Game router can be called mid-transaction (via a callback or reentrancy) while storage written by one module has not yet been read/consumed by another.

**Why automated tools miss it:** Slither analyzes contracts individually. Delegatecall modules share DegenerusGameStorage but tools cannot reason about cross-module state dependencies through the router's dispatch mechanism. The "reentrancy" detector fires on external calls but cannot trace the semantic dependency between packed storage slots written by AdvanceModule and read by JackpotModule. The SlowMist delegatecall vulnerability guide confirms that storage collision analysis requires manual verification of slot alignment.

**What a warden checks:**
1. Map every storage slot written by each module during `advanceGame()`
2. Identify slots written by module A and read by module B in the same flow
3. Check if any external call (ETH transfer, VRF request, stETH operation) occurs between the write and the read
4. Check if any permissionless function reads the same slot and could be called during that external call window
5. Verify the delegatecall modules cannot be called directly at their deployed address (bypassing the router)

**Degenerus-specific surfaces:**
- `advanceGame()` dispatches to AdvanceModule which calls into JackpotModule, EndgameModule, GameOverModule in sequence -- storage written early (e.g., `prizePoolsPacked`) could be read stale by later modules if an external call intervenes
- `_payoutWithStethFallback` / `_payEth` make external `.call{value:}` -- any callback from a recipient contract hits the Game's `receive()` which writes to `prizePoolsPacked`
- BAF cache-overwrite class (already fixed once in v4.4 for `runRewardJackpots`) -- the pattern of reading a packed slot, doing work, then writing back can lose writes from intervening operations

**What a finding looks like:**
> "During advanceGame(), EndgameModule reads `prizePoolsPacked.futurePrizePool` after AdvanceModule has already sent ETH via `_payEth`. If the recipient is a contract with a `receive()` that calls `purchaseFor()`, the `receive()` handler adds ETH to `prizePoolsPacked.futurePrizePool`. When EndgameModule then writes back its cached copy of `prizePoolsPacked`, the purchase contribution is silently erased. Impact: permanent ETH loss equal to the purchase amount."

**Prior audit coverage:** v4.4 BAF cache-overwrite scan found 1 VULNERABLE / 11 SAFE. v5.0 adversarial audit covered all 693 functions. STORAGE-WRITE-MAP.md exists. But a fresh-eyes warden will re-derive the cross-module write map independently and may find paths the adversarial system missed due to its systematic (vs. creative) approach.

---

## Pattern 2: Rounding / Precision Loss in BPS Splits and Pool Arithmetic

**C4A Hit Rate:** VERY HIGH -- rounding bugs are the most common HIGH/MEDIUM in DeFi protocols with pool accounting. The 2024 Balancer exploit ($128M) exploited `mulDown` vs. `mulUp` rounding in 65 micro-swaps. OWASP SC Top 10 ranks logic errors (including precision) at #3 ($63.8M losses in 2024).
**Typical Severity:** MEDIUM (dust accumulation) to HIGH (exploitable drain)

**What it is:** When ETH is split across multiple pools using BPS (basis points), integer division truncation creates remainders. If remainders are not explicitly captured, they accumulate as "phantom ETH" -- tracked in contract balance but not in any pool variable. Over thousands of transactions, this can break the solvency invariant. Worse: if a warden finds a path where rounding consistently favors the user (not the protocol), it becomes extractable.

**Why automated tools miss it:** Tools flag division operations but cannot determine whether the remainder is captured or lost. The semantic question "does the sum of all BPS splits equal msg.value?" requires understanding the full split logic, not just individual operations. 4naly3er detects `L-13`/`L-14` (rounding) but cannot determine directionality.

**What a warden checks:**
1. Sum all BPS splits for each entry point -- does `sum(splits) == msg.value` or is there a remainder?
2. Where does the remainder go? Explicitly to a pool, or silently to contract balance?
3. Can a user craft `msg.value` to maximize remainder per transaction?
4. Are there any paths where division rounds in the user's favor (e.g., `amount * userBps / 10000` where the numerator is large)?
5. Does `claimablePool` ever exceed `address(this).balance + stethBalance`?
6. In multi-winner jackpot distributions, does rounding across N winners leak or create ETH?

**Degenerus-specific surfaces:**
- `purchaseFor()` in MintModule splits ETH across nextPrizePool, futurePrizePool, claimablePool, vault share, affiliate commission -- 5+ destinations with BPS arithmetic
- Whale bundle / lazy pass / deity pass have different split ratios
- `_processDailyEth` distributes prize pools to winners -- rounding across N winners
- BAF scatter splits 20% current level + 80% random near-future across variable recipient counts
- sDGNRS gambling burn redemption: roll [25,175] applied to pending ETH reservation
- Recycling bonus calculation: 0.75% of total claimableStored (base changed from fresh mintable)

**What a finding looks like:**
> "In `purchaseFor()`, the sum of `nextPoolBps + futurePoolBps + vaultBps + affiliateBps` is 9,850 BPS, leaving 150 BPS (1.5%) unaccounted. For a 1 ETH purchase, 0.015 ETH is added to `address(this).balance` but not to any pool variable. After 10,000 purchases, 150 ETH sits in the contract but is not claimable by anyone, breaking the conservation invariant."

**Prior audit coverage:** v3.3 economic analysis proved EV and solvency. v5.0 proved ETH conservation. KNOWN-ISSUES.md states "all rounding favors solvency." But a warden will independently verify the BPS arithmetic for every entry point, especially for edge-case msg.value amounts (1 wei, type(uint256).max / 10000, etc.).

---

## Pattern 3: Stale / Cached State Reads Across VRF Request-Fulfillment Gap

**C4A Hit Rate:** HIGH -- VRF protocols are a favorite target because the 2-tx pattern creates natural state inconsistency windows. Chainlink's own documentation warns that "the order in which VRF fulfillments arrive cannot be used to manipulate user-significant behavior."
**Typical Severity:** HIGH (if RNG outcome can be influenced)

**What it is:** Between a VRF request (tx1) and fulfillment (tx2), there is a multi-block window. Any state that affects the outcome of RNG-dependent operations but can be changed by a user during this window is a commitment violation. Wardens look for variables that are read during fulfillment but writable during the gap.

**Why automated tools miss it:** This requires understanding the 2-transaction lifecycle. No static analyzer can reason about "what state existed at request time vs. fulfillment time." It requires manual tracing of every variable read in `rawFulfillRandomWords` and checking if each one is writable via any permissionless path between request and fulfillment.

**What a warden checks:**
1. List every variable read in `rawFulfillRandomWords` and all functions it calls
2. For each variable: can any permissionless function modify it between request and fulfillment?
3. Check `rngLockedFlag` guard coverage -- does it block ALL relevant write paths?
4. Check for indirect writes -- can a user modify a variable that feeds into an intermediate calculation?
5. Look for "commitmentless" inputs to jackpot selection: player count, ticket count, pool balances
6. Check mid-day ticket RNG: separate VRF request cycle with its own gap window

**Degenerus-specific surfaces:**
- `rngLockedFlag` blocks purchases during VRF window, but does it block ALL state modifications?
- Ticket queues: can tickets be added/removed between request and fulfillment?
- `prizePoolsPacked` values at fulfillment vs. request time
- Player boon state: can a boon be applied during VRF window that changes lootbox odds?
- Degenerette bets: can bets be placed/resolved during VRF window?
- `setAutoRebuy(bool)` / `setTakeProfit(uint8)` -- are these blocked during VRF window?

**What a finding looks like:**
> "When advanceGame requests VRF, rngLockedFlag prevents new ticket purchases. However, `setAutoRebuy(true)` is still callable. During fulfillment, the auto-rebuy flag is read to determine ticket generation for the next level. A user can enable auto-rebuy after seeing the VRF request to guarantee their participation in a favorable jackpot distribution, violating the commitment window."

**Prior audit coverage:** v3.8 performed comprehensive commitment window audit (55 variables, 87 permissionless paths, 51/51 SAFE). v3.9 added rngLocked guard to far-future ticket writes. v4.0 re-verified all 55 variables after slot shifts. This is the best-covered area. A fresh warden may challenge the "SAFE" conclusions differently or find paths the methodology overlooked, but probability of a new finding is LOW.

---

## Pattern 4: Token Accounting Asymmetry (Mint/Burn/Wrap Imbalance)

**C4A Hit Rate:** HIGH -- token accounting bugs are consistently the highest-paying findings. The ERC4626 first-depositor/inflation attack pattern alone has appeared in dozens of C4A/Sherlock contests. Multi-token systems with wrap/unwrap are especially vulnerable.
**Typical Severity:** HIGH (unauthorized minting or extraction)

**What it is:** In multi-token protocols, wardens look for any path where tokens can be minted without a corresponding value lock, or burned without releasing the correct value. The sDGNRS/DGNRS wrapping relationship, BURNIE coinflip auto-claim, and GNRUS burn redemption create multiple asymmetry surfaces. The key warden technique is tracing a full round-trip and checking if value is conserved.

**Why automated tools miss it:** Tools check individual transfer/mint/burn calls but cannot reason about cross-contract value conservation. The semantic question "does wrapping 100 sDGNRS into DGNRS and unwrapping back yield exactly 100 sDGNRS?" requires tracing the full round-trip across two contracts.

**What a warden checks:**
1. sDGNRS wrap/unwrap round-trip: deposit X sDGNRS, get Y DGNRS, unwrap Y DGNRS, receive Z sDGNRS. Is X == Z always?
2. BURNIE auto-claim in transfer: does the auto-claim mint affect balanceOf consistency? Can a user trigger auto-claim to inflate their balance before a check?
3. BURNIE vault burn: when tokens sent to VAULT are burned, does vaultAllowance increase by exactly the burned amount?
4. sDGNRS gambling burn: does the pending reservation system correctly track ETH obligations? Can a user claim more ETH than reserved?
5. GNRUS burn redemption: does burning GNRUS release the correct sDGNRS amount? Is there a precision loss in proportional calculation?
6. Can wrap+unwrap+wrap cycling extract value through rounding?

**Degenerus-specific surfaces:**
- `DegenerusStonk.wrapFor()` / `unwrapTo()` -- the soulbound-to-transferable conversion; `unwrapTo` blocked during VRF stalls but what about edge cases?
- `BurnieCoin._claimCoinflipShortfall()` called during `_transfer` -- mints tokens mid-transfer, potentially changing sender's balance between check and transfer
- `BurnieCoin._transfer` to VAULT -- burns tokens and increases virtual allowance atomically; is the accounting exact?
- `StakedDegenerusStonk` gambling burn reservation system -- pending vs. resolved vs. claimable lifecycle; CP-08 was a real double-spend bug
- `GNRUS.burn()` -- burns GNRUS, releases sDGNRS from DegenerusCharity

**What a finding looks like:**
> "When a user calls DGNRS.unwrapTo(), the function burns DGNRS and transfers sDGNRS. However, if the user has pending gambling burn claims on the sDGNRS, the sDGNRS transfer triggers _claimGamblingBurn which mints additional sDGNRS. The user receives more sDGNRS than they originally wrapped, creating inflation."

**Prior audit coverage:** v3.3 gambling burn audit (CP-08, CP-06, Seam-1 all fixed). v5.0 adversarial audit. But the interaction between DGNRS unwrapping and sDGNRS gambling claims is a cross-contract path that systematic per-contract audits may not have traced end-to-end.

---

## Pattern 5: Cross-Function Reentrancy via ETH Recipient Callbacks

**C4A Hit Rate:** HIGH -- even with CEI, cross-function reentrancy through callbacks is commonly missed. OWASP SC Top 10 notes cross-contract reentrancy (A calls B calls back A through C) as the live variant in 2025, not single-function reentrancy.
**Typical Severity:** HIGH

**What it is:** Classic single-function reentrancy is well-understood. The warden meta is **cross-function reentrancy**: Contract sends ETH to user, user's `receive()` calls a DIFFERENT function on the same contract (or a related contract), exploiting the fact that state updates for function A have not completed when function B executes. In delegatecall architectures, this is amplified because all modules share state -- a reentrancy guard on one module does not protect state read by another.

**Why automated tools miss it:** Slither's reentrancy detectors check single-function patterns and known modifiers (nonReentrant). They cannot reason about cross-function reentrancy through delegatecall dispatch where the guard is a state flag rather than a modifier, or where different modules have different reentrancy assumptions.

**What a warden checks:**
1. Find every external call (ETH send, token transfer) in the protocol
2. At the point of each external call, what state has been partially updated?
3. Can the callback enter a different function that reads that partially-updated state?
4. Is there a global reentrancy guard on the Game router, or only per-function guards?
5. Does the delegatecall router have reentrancy protection?
6. Can `operatorClaimWinnings` be called during a `claimWinnings` callback?

**Degenerus-specific surfaces:**
- Game router dispatches to modules via delegatecall -- is there a global reentrancy guard on the router?
- `_payoutWithStethFallback` sends ETH mid-function -- can recipient call `purchaseFor()` or `claimWinnings()` during callback?
- `advanceGame()` sends ETH for jackpot payouts -- can recipient call `advanceGame()` again during payout?
- stETH transfers (Lido's stETH has non-trivial transfer logic) -- do they create callback opportunities?
- `claimWinnings` decrements claimablePool then sends ETH -- what if the recipient re-enters via a different claim function?

**What a finding looks like:**
> "During `advanceGame()`, JackpotModule pays the daily ETH jackpot winner via `_payEth`. The winner's receive() calls `claimWinnings()` on the Game contract. At this point, the winner's claimable balance has not yet been zeroed by JackpotModule (CEI violation across modules). The winner claims their full balance AND receives the jackpot, double-claiming."

**Prior audit coverage:** Post-v2.1 CEI fix applied to `_executeSwap`. v5.0 verified CEI. But cross-module reentrancy through the router is architecturally different from single-contract CEI -- a warden specifically targeting the delegatecall dispatch boundary may find paths the per-contract analysis missed.

---

## Pattern 6: Unchecked Return Values on ETH Transfers (Silent Fund Loss)

**C4A Hit Rate:** HIGH -- this is a "meta" pattern wardens check on every protocol with ETH payouts. SWC-104 (unchecked call return value) has been a consistent source of findings since the DAO hack.
**Typical Severity:** HIGH (permanent fund loss)

**What it is:** When ETH is sent via `.call{value:}("")`, the return value `(bool success, )` must be checked. If not checked, a failed transfer (recipient reverts, gas limit exceeded) silently proceeds, and the protocol's accounting marks the ETH as sent when it was not. The ETH remains in the contract but claimablePool is decremented. The deeper warden check is the fallback chain: when ETH fails, does stETH fallback also have correct error handling?

**Why automated tools miss it:** Slither has a `low-level-calls` detector that flags unchecked returns, but it produces many false positives. KNOWN-ISSUES.md triages these as "won't fix" with rationale. A warden independently verifies every `.call{value:}` site and specifically tests the fallback-of-fallback path.

**What a warden checks:**
1. Find every `.call{value:}` in the codebase (11 instances per KNOWN-ISSUES.md)
2. Verify the return value is checked and the function reverts on failure
3. Check fallback paths: does `_payoutWithStethFallback` correctly handle both ETH AND stETH failure?
4. Verify that accounting updates (claimablePool decrement) happen AFTER the success check, not before (CEI ordering)
5. Can a recipient contract deliberately fail to receive ETH to manipulate protocol state?

**Degenerus-specific surfaces:**
- `_payoutWithStethFallback` -- the double-fallback: try ETH, fail, try stETH, fail. What happens?
- `_payEth` -- 4 instances; each needs independent verification
- sDGNRS/DGNRS ETH transfers during burn flows -- smaller codebase, less reviewed
- Game `receive()` accepts ETH from anyone -- what happens with unexpected senders?
- Can a recipient contract grief jackpot payouts by reverting, causing advanceGame to fail?

**What a finding looks like:**
> "In `_payEth`, the return value of `.call{value: amount}("")` is checked, but the error handling sends ETH via stETH as fallback. If stETH.transfer also fails (e.g., stETH paused), the function silently continues. claimablePool was already decremented before the send attempt, so the ETH is permanently lost from the user's perspective while remaining in the contract."

**Prior audit coverage:** KNOWN-ISSUES.md documents `.call{value:}` patterns and CEI compliance. v5.0 verified CEI. The fallback-of-fallback (what happens when BOTH ETH and stETH sends fail?) is the specific edge that wardens will target.

---

## Pattern 7: Denial of Service via Gas Griefing on advanceGame

**C4A Hit Rate:** MEDIUM-HIGH -- gas DoS is a reliable MEDIUM finding category. The Solodit checklist has an entire section on DoS patterns (dust transactions, queue processing, unsafe external calls).
**Typical Severity:** MEDIUM (game stall) to HIGH (permanent freeze)

**What it is:** If an attacker can force `advanceGame()` to exceed the block gas limit, the game permanently stalls. Wardens look for unbounded loops, arrays that grow with user count, and storage reads that scale with participation. The specific warden technique is to construct an adversarial on-chain state (buying maximum tickets, lootboxes, etc.) and then gas-profile `advanceGame()` at that state.

**Why automated tools miss it:** Slither flags loops but cannot estimate gas under worst-case conditions. The question "can an attacker force this loop to iterate 10,000 times?" requires understanding game mechanics, entry point costs, and attacker economic incentives.

**What a warden checks:**
1. What is the maximum iteration count for every loop in `advanceGame()`?
2. Can an attacker inflate any loop bound (e.g., by purchasing many tickets for the same level)?
3. Are there any storage arrays that grow without bound?
4. Can ticket queue processing exceed gas limits? What is the maximum queue depth?
5. What happens if `advanceGame()` always reverts? Is there a recovery path?
6. Can the attacker make the griefing attack profitable (e.g., by preventing jackpot distributions)?

**Degenerus-specific surfaces:**
- `advanceGame()` processes ticket queues, jackpots, lootboxes in sequence -- total gas must fit in one block (30M limit)
- v3.5 profiled 18 paths (15 SAFE, 1 TIGHT, 2 AT_RISK) -- wardens will specifically target the AT_RISK paths
- Ticket cursor-based processing -- what is the worst case if all tickets are for the current level?
- BAF scatter distributes across variable recipient counts -- maximum recipient count?
- Far-future ticket drain -- what is the worst-case iteration count?
- Daily jackpot processes across all players with tickets at a level -- maximum player count per level?
- v4.2 removed daily jackpot chunks -- did this improve or worsen worst-case gas?

**What a finding looks like:**
> "An attacker purchases 1,000 lootboxes across 200 levels, each creating pending lootbox indices. During advanceGame(), _processLootboxes iterates over all pending indices for the current level. With 1,000 pending lootboxes, gas consumption reaches 28M, exceeding practical limits and permanently stalling the game."

**Prior audit coverage:** v3.5 gas ceiling analysis. v4.2 daily jackpot chunk removal. Gas baselines captured. But wardens will try to construct states not considered in profiling -- especially combinations of maximum ticket count + maximum lootbox count + maximum player count at the same level.

---

## Pattern 8: Front-Running / MEV Extraction on Permissionless Functions

**C4A Hit Rate:** MEDIUM-HIGH -- wardens check every permissionless function for ordering sensitivity. MEV analysis is a distinct skill from code auditing and is often missed by auditors focused on correctness.
**Typical Severity:** MEDIUM

**What it is:** Any permissionless function where the caller benefits from seeing pending transactions (mempool observation) creates MEV opportunities. In game protocols, this includes: seeing someone else's purchase and front-running to claim a position, seeing VRF fulfillment and sandwiching to manipulate pool sizes, or seeing jackpot results and extracting value. The Degenerus protocol has 30+ permissionless state-changing functions per the ACCESS-CONTROL-MATRIX.

**Why automated tools miss it:** MEV analysis requires reasoning about transaction ordering in the mempool, which is outside any static analyzer's scope. It requires understanding game theory, block builder incentives, and the specific ordering sensitivity of each function.

**What a warden checks:**
1. Can a user profit by front-running another user's `purchaseFor()`?
2. Can a user see the VRF fulfillment transaction in the mempool and sandwich it?
3. Can `advanceGame()` be sandwiched to extract value?
4. Are jackpot selections deterministic given on-chain state? Can a user compute the outcome before calling?
5. Can affiliate assignment be front-run to redirect commission?
6. Does ticket pricing escalation create front-running incentive?

**Degenerus-specific surfaces:**
- `purchaseFor()` is permissionless -- front-running affects price if escalation is per-purchase
- `advanceGame()` is permissionless -- if VRF fulfillment is pending, can someone position themselves?
- 30+ permissionless functions in ACCESS-CONTROL-MATRIX.md
- Decimator mechanics -- can seeing decimator state advantage a front-runner?
- Degenerette bets -- ordering-sensitive?

**What a finding looks like:**
> "A block proposer observing a VRF fulfillment in the mempool can extract the VRF word, compute the daily jackpot winner, and front-run advanceGame() with a claimWinnings() call if the winner has pending claims. The claim reduces claimablePool, causing advanceGame to distribute from a smaller pool."

**Prior audit coverage:** KNOWN-ISSUES.md documents non-VRF entropy for affiliate winner roll as acceptable. VRF commitment window audit covered most surfaces. But MEV-specific attack sequences through the mempool are a distinct analysis from commitment window integrity.

---

## Pattern 9: Storage Packing / Bit Manipulation Errors

**C4A Hit Rate:** MEDIUM -- found frequently in protocols that use custom packing for gas optimization. This is a high-value target for fresh eyes because it requires meticulous manual verification of every bit boundary and no automated tool can help.
**Typical Severity:** MEDIUM to HIGH (data corruption, fund loss)

**What it is:** When multiple values are packed into a single storage slot (e.g., `prizePoolsPacked`, `BoonPacked`), bit mask errors can cause one field's write to corrupt an adjacent field. Off-by-one in shift amounts, wrong mask widths, or missing mask application can silently corrupt critical state. The Degenerus protocol has extensive custom packing for gas optimization.

**Why automated tools miss it:** No static analyzer understands custom bit packing semantics. Slither sees assembly blocks as opaque. 4naly3er does not analyze bit operations. The correctness of `(slot & ~mask) | (value << offset)` requires knowing the intended field boundaries.

**What a warden checks:**
1. Map every packed storage slot: field name, bit offset, bit width, mask
2. Verify masks: does `~mask` correctly clear the target field without touching adjacent fields?
3. Verify shifts: does `value << offset` place the value in the correct bit range?
4. Check overflow: can a value exceed its allocated bit width? (e.g., a BPS value > 10000 stored in 14 bits)
5. Check read/write consistency: is the same offset/mask used for both read and write?
6. Look for assembly blocks that manipulate packed slots directly

**Degenerus-specific surfaces:**
- `prizePoolsPacked` (slot 3) -- contains nextPrizePool and futurePrizePool; central to ETH accounting
- `BoonPacked` -- 2-slot struct with 9 categories of boon data in isolated bit fields; redesigned in v3.8 Phase 73
- `ticketQueuePacked` -- ticket keys packed with bit 22 for far-future space (added v3.9)
- `BitPackingLib` library -- central packing logic used across all modules
- Player data structs with packed fields (204 variables analyzed in v3.5)
- Slot 0 assembly in VRF fulfillment path

**What a finding looks like:**
> "In BoonPacked, the lootbox boon occupies bits [32:47] and the purchase boon occupies bits [48:63]. The write mask for lootbox boon is `0xFFFF << 32` but the clear mask uses `~(0xFFFF << 31)` (off-by-one). Writing a lootbox boon value corrupts bit 31 of the coinflip boon field, potentially disabling an active coinflip boon."

**Prior audit coverage:** v3.8 Phase 73 redesigned BoonPacked. v4.0 verified slot shifts. v3.5 analyzed 204 variables. But packed storage is one of the highest-value targets for fresh eyes because a single off-by-one creates a real finding and prior auditors may have developed blind spots on frequently-revisited code.

---

## Pattern 10: Access Control Gaps on Module / Helper Functions

**C4A Hit Rate:** MEDIUM -- access control is the #1 loss category overall ($953.2M in 2024) but Degenerus uses compile-time constant addresses which eliminates most vectors. The remaining surface is: can modules be called directly, bypassing the router?
**Typical Severity:** MEDIUM to HIGH

**What it is:** In delegatecall architectures, modules are deployed as separate contracts. If a module's external functions can be called directly (not through the router's delegatecall), they operate on the module's own storage -- which is empty/uninitialized. This can produce unexpected behavior. Additionally, functions intended as `internal` that are accidentally `public` create unauthorized access paths.

**Why automated tools miss it:** Slither checks visibility modifiers but cannot determine intent. A function marked `public` might be intentionally public or accidentally so. The semantic distinction requires understanding the delegatecall architecture.

**What a warden checks:**
1. Can any of the 10 delegatecall modules be called directly at their deployed address?
2. If called directly, do module functions operate on the module's empty storage? Do they revert or produce unexpected effects?
3. Are there any `public` functions in modules that should be `internal`?
4. Do module functions validate that they are being delegatecalled (e.g., checking `address(this) == GAME`)?
5. `resolveRedemptionLootbox` is guarded by `msg.sender == ContractAddresses.SDGNRS` -- in delegatecall context, msg.sender is preserved. Is this correct?
6. Can `operatorApprovals` be manipulated by calling approve functions on the module directly?

**Degenerus-specific surfaces:**
- 10 delegatecall modules with external functions -- each must be verified as safe to call directly
- All access control uses compile-time constant addresses (ContractAddresses.*) -- no re-pointing, but can the modules themselves be called outside the router?
- sDGNRS governance voting functions -- are vote thresholds enforced correctly?
- Admin functions in DegenerusAdmin -- all have `onlyOwner` but are there any that should also require governance?

**What a finding looks like:**
> "AdvanceModule's `advanceGame()` is an external function. Calling it directly on the AdvanceModule contract (not via delegatecall through DegenerusGame) operates on the module's own storage. The function reads uninitialized state, executes unexpected paths, and leaves the module's storage in a state that allows subsequent calls to extract value."

**Prior audit coverage:** ACCESS-CONTROL-MATRIX.md covers all 693+ functions. Compile-time constant addresses eliminate re-pointing attacks. v5.0 adversarial audit. But direct module invocation (bypassing the router) as a specific attack class may not have been systematically tested.

---

## Pattern 11: Game-Over / Terminal State Transition Exploits

**C4A Hit Rate:** MEDIUM -- lifecycle boundaries are high-value targets because invariants change at the transition point and auditors often focus on steady-state behavior.
**Typical Severity:** MEDIUM to HIGH

**What it is:** The transition from active game to game-over state creates a boundary where invariants change. Functions that are safe during normal gameplay may be exploitable at game-over. Wardens look for: functions callable after game-over that should be blocked, state that is not correctly frozen at game-over, and distribution logic that can be manipulated.

**Why automated tools miss it:** State machine transitions require understanding the protocol's lifecycle. No tool can determine "should this function be callable after game over?"

**What a warden checks:**
1. Which functions are blocked after game-over? Which should be but are not?
2. Can a user front-run the game-over transaction to position themselves?
3. Does the game-over distribution correctly handle all pending states (lootboxes, coinflips, degenerette bets)?
4. Can the 120-day inactivity timeout be triggered prematurely or manipulated?
5. Are deity pass refunds correctly calculated with quadratic pricing?
6. Post-game-over deterministic burns: different codepath from during-game gambling burns. Are both paths correct?
7. What happens to pending VRF requests at game-over?

**Degenerus-specific surfaces:**
- GameOverModule distributes remaining pools -- is the distribution formula exploitable?
- Seam-1 fix (burn() guard after game-over) -- are there other functions with similar seam issues?
- Post-game-over deterministic burns in sDGNRS -- different path from during-game gambling burns
- Deity pass refunds with quadratic pricing -- rounding in refund calculation
- Pending lootbox resolution at game-over (orphaned lootbox recovery in v3.6)
- 120-day death clock -- can VRF stalls interact with the death clock?
- `burnRemainingPools` -- who can call this, and what does it do to pending claims?

**What a finding looks like:**
> "After game-over, `claimDecimatorJackpot()` is still callable. The decimator pool was not included in the game-over distribution because it was expected to be claimed individually. However, if no one claims within the 120-day period, the ETH becomes permanently locked in the contract with no recovery mechanism."

**Prior audit coverage:** v5.0 adversarial audit covered GameOverModule. Seam-1 fixed. But the interaction between game-over, pending claims, the 120-day timeout, and post-game-over burns creates a combinatorial space that benefits from fresh analysis.

---

## Pattern 12: Read-Only Reentrancy / Stale View Function State

**C4A Hit Rate:** MEDIUM -- emerging pattern that gained prominence after the Curve/Vyper exploit. Specifically relevant when view functions are consumed by other contracts or used internally during state-modifying operations.
**Typical Severity:** MEDIUM

**What it is:** View functions that return state can be called mid-transaction while state is partially updated. If any external protocol (or the protocol itself) reads balances, prices, or pool sizes via view functions during an external call, the stale values can cause incorrect behavior. The "read-only" nature makes these invisible to standard reentrancy checks.

**Why automated tools miss it:** View functions are not flagged by reentrancy detectors. The `nonReentrant` modifier does not protect `view` functions. No tool checks whether a view function returns consistent state during a reentrant call.

**What a warden checks:**
1. List all `view`/`pure` functions that return financial data (balances, prices, pool sizes)
2. Are any of these called internally during state-modifying operations?
3. Could an external protocol call these view functions during a callback?
4. Is `balanceOf` consistent during a transfer? (BURNIE auto-claim makes this non-trivial)
5. Does `_reentrancyGuardEntered()` or equivalent protect critical view functions?

**Degenerus-specific surfaces:**
- BURNIE `balanceOf` -- if auto-claim (`_claimCoinflipShortfall`) has not yet resolved, balanceOf may return a stale value
- sDGNRS `balanceOf` during gambling burn resolution -- pending vs. claimed state
- `DegenerusVault` stETH balance calculations during yield distribution
- Deity pass triangular pricing reads current supply -- is supply consistent during mint?
- Any view function used by external protocols (DEX, aggregator) to price tokens

**What a finding looks like:**
> "BURNIE's balanceOf returns the raw storage balance without accounting for pending coinflip winnings. An external DEX protocol calls balanceOf during a swap to check the user's balance. The user's actual balance (including unclaimed coinflip winnings) is higher than reported, causing the DEX to under-price the swap."

**Prior audit coverage:** stETH 1-2 wei retention documented. BURNIE auto-claim documented in KNOWN-ISSUES.md. But read-only reentrancy as a pattern class was not explicitly audited as a category across the protocol.

---

## Pattern 13: Governance Manipulation via Vote Timing / Flash Wrapping

**C4A Hit Rate:** MEDIUM -- common in protocols with token-weighted governance. The Degenerus governance has specific defenses (unwrapTo blocked during stalls, time-decay thresholds) but wardens will test every edge.
**Typical Severity:** MEDIUM

**What it is:** If governance votes use current token balance (not snapshot), an attacker can borrow/buy tokens, vote, then return them. The sDGNRS governance uses real-time balances with defenses, but edge cases in threshold decay, proposal timing, and supply manipulation create potential attack surfaces.

**Why automated tools miss it:** Governance logic is too complex for pattern matching. The interaction between vote timing, threshold decay, and token transfer restrictions requires manual analysis of the state machine.

**What a warden checks:**
1. Can sDGNRS be acquired quickly? `unwrapTo` blocked during VRF stalls but what about during normal governance?
2. Can DGNRS be flash-loaned and wrapped to sDGNRS for voting, then unwrapped and returned?
3. Can votes be cast and revoked in the same block?
4. Does threshold decay from 50% to 15% floor over 4 days create a window where a small holder can pass a proposal?
5. Can an attacker manipulate circulating supply to affect threshold calculations?
6. Price feed governance uses LIVE circulating supply -- can this be manipulated mid-vote?

**Degenerus-specific surfaces:**
- VRF governance: `unwrapTo` blocked during VRF stalls (20h+), but DGNRS could be acquired on secondary market
- Price feed governance: uses live circulating supply (documented design decision) -- but is this manipulable?
- sDGNRS is soulbound -- but DGNRS is transferable, and wrap/unwrap creates a path to sDGNRS accumulation
- WAR-01/WAR-02 documented: compromised admin + 7-day inattention, colluding cartel at day 6 with 5% threshold
- Bootstrap assumption: admin holds majority sDGNRS at launch and can self-approve

**What a finding looks like:**
> "An attacker acquires 14.9% of DGNRS on secondary market, wraps to sDGNRS (not blocked during normal operation), then waits for threshold decay to reach 15% floor. They approve a malicious price feed swap proposal. The proposal passes with minority approval because reject voters did not participate. The malicious feed enables BURNIE hyperinflation via fake LINK valuations."

**Prior audit coverage:** v2.1 governance audit (26 verdicts), WAR-01/WAR-02/WAR-06 documented. Bootstrap assumption documented. But the interaction between DGNRS secondary market liquidity and sDGNRS governance remains a theoretical vector that fresh eyes may formalize.

---

## Pattern 14: ERC-20 Integration Edge Cases (Weird Token Behaviors)

**C4A Hit Rate:** MEDIUM -- reliable source of MEDIUM findings when protocol interacts with external tokens. The stETH rebasing behavior is the primary surface here.
**Typical Severity:** MEDIUM

**What it is:** Tokens with non-standard behaviors (fee-on-transfer, rebasing, blocklist, permit, callbacks) can break protocols that assume standard ERC-20 semantics. Degenerus interacts with stETH (rebasing, 1-2 wei per-transfer loss), LINK (transferAndCall), and its own non-standard tokens (BURNIE auto-claim, DGNRS transfer restriction, BURNIE vault burn).

**Why automated tools miss it:** Tools check for SafeERC20 usage but cannot reason about token-specific behaviors. 4naly3er flags missing SafeERC20 (`[M-5]`, `[M-6]`) but KNOWN-ISSUES.md documents this as intentional. The actual risk is in stETH compound failure scenarios and LINK callback paths.

**What a warden checks:**
1. stETH rebasing: does the protocol correctly handle negative rebases? What is the maximum rebase size the 8% buffer can absorb?
2. stETH 1-2 wei transfer losses: do they accumulate to material amounts over thousands of transfers?
3. LINK transferAndCall: can it create callbacks into the protocol via DegenerusCharity?
4. BURNIE auto-claim during transferFrom: what happens with zero balance + large pending coinflip?
5. What if stETH is paused by Lido? Does the protocol have a fallback for all paths?

**Degenerus-specific surfaces:**
- DegenerusVault holds stETH -- negative rebase handling with 8% buffer
- stETH transfer precision (1-2 wei per operation) -- documented but accumulation analysis needed over protocol lifetime
- BURNIE `_claimCoinflipShortfall` during transfer -- race conditions with BurnieCoinflip state
- wXRP utility token -- standard ERC-20 but verify behavior
- Compound scenario: stETH negative rebase + mass claims with stETH fallback

**What a finding looks like:**
> "stETH negative rebase reduces DegenerusVault balance by 5%. The 8% buffer absorbs this, but if followed immediately by a mass claimWinnings with stETH fallback, the stETH transfers lose 1-2 wei each. With 10,000 claims, approximately 20,000 wei is lost. Combined with the rebase, claimablePool exceeds available stETH balance, and the final claimant cannot receive payment."

**Prior audit coverage:** KNOWN-ISSUES.md documents stETH dependency, 1-2 wei retention, and the 8% buffer. The compound failure scenario (rebase + mass claims) deserves analysis but the 8% buffer is large enough that practical impact is likely INFO-level.

---

## Pattern 15: Deterministic Outcome Gaming / Commit-Reveal Bypass

**C4A Hit Rate:** MEDIUM -- relevant for any protocol where outcomes are derivable from on-chain state before execution. Lower hit rate in Degenerus because VRF covers most randomness.
**Typical Severity:** MEDIUM

**What it is:** If a function's outcome is deterministic given current on-chain state (no VRF), a user can simulate the call off-chain, decide whether the outcome is favorable, and only execute if it benefits them. For Degenerus, any non-VRF randomness or deterministic selection mechanism is vulnerable.

**Why automated tools miss it:** Determinism analysis requires understanding the full input space of a function and whether all inputs are known to the caller before execution. No tool can determine "is this outcome predictable before execution?"

**What a warden checks:**
1. Which outcomes use VRF vs. deterministic logic?
2. Affiliate winner roll: documented as deterministic -- can it be gamed for more than "affiliate credit redirection"?
3. Are there any pseudo-random operations using block.timestamp, block.number, or block.prevrandao?
4. Can a user simulate `advanceGame()` off-chain to know if they win before calling?
5. Are decimator selections predictable given on-chain state?
6. Can deity pass pricing be gamed by timing purchases?

**Degenerus-specific surfaces:**
- Affiliate winner roll: uses deterministic seed (documented as acceptable, worst case = affiliate credit redirection, no protocol value extraction)
- `prevrandao` fallback at game-over: 1-bit manipulable by block proposer (documented as edge-of-edge case)
- Quest streak system: any deterministic component?
- Ticket pricing: deterministic from level state -- front-runnable but self-limiting (price goes up)

**What a finding looks like:**
> "Affiliate winner selection uses keccak256(abi.encodePacked(level, playerCount)). A player can compute the winning affiliate index before purchasing, choosing their affiliate referral to match the predicted winner. Combined with self-referral through a proxy contract, this allows systematic extraction of affiliate commissions on every purchase."

**Prior audit coverage:** KNOWN-ISSUES.md documents the affiliate determinism as acceptable (no protocol value extraction). A warden would need to prove actual value extraction beyond affiliate credit redirection to upgrade this to MEDIUM.

---

## Ranking Summary (Degenerus-Specific Probability of NEW Finding)

| Rank | Pattern | C4A Hit Rate | P(New Finding) | Why |
|------|---------|-------------|----------------|-----|
| 1 | Cross-Function State via Delegatecall (P1) | VERY HIGH | MEDIUM | Combinatorial cross-module paths; hardest to audit exhaustively |
| 2 | Token Accounting Asymmetry (P4) | HIGH | MEDIUM | Cross-contract wrap/unwrap/claim interactions across 5 tokens |
| 3 | Storage Packing Errors (P9) | MEDIUM | MEDIUM | Manual bit boundary verification; fresh eyes catch what familiarity blinds |
| 4 | BPS Rounding / Precision Loss (P2) | VERY HIGH | LOW-MEDIUM | v3.3 + v5.0 conservation proof, but edge-case msg.value not exhausted |
| 5 | Cross-Function Reentrancy (P5) | HIGH | LOW-MEDIUM | CEI verified but cross-module re-entry through router less certain |
| 6 | Game-Over Transition Exploits (P11) | MEDIUM | LOW-MEDIUM | Combinatorial lifecycle boundary; pending state interactions |
| 7 | Unchecked ETH Transfer Returns (P6) | HIGH | LOW | CEI verified; fallback-of-fallback is the remaining edge |
| 8 | Gas DoS on advanceGame (P7) | MEDIUM-HIGH | LOW | Gas profiled; cursor approach; but adversarial state construction needed |
| 9 | VRF Commitment Window (P3) | HIGH | LOW | Best-covered area (55 vars, 87 paths, 51/51 SAFE) |
| 10 | Access Control Gaps (P10) | MEDIUM | LOW | 693 functions mapped; compile-time addresses |
| 11 | MEV / Front-Running (P8) | MEDIUM-HIGH | LOW | Permissionless functions documented; limited value extraction |
| 12 | Read-Only Reentrancy (P12) | MEDIUM | LOW | Not explicitly audited as class but limited external integration |
| 13 | Governance Manipulation (P13) | MEDIUM | LOW | Documented known issues; defense-weighted thresholds |
| 14 | ERC-20 Edge Cases (P14) | MEDIUM | LOW | stETH documented; 8% buffer is generous |
| 15 | Deterministic Outcome Gaming (P15) | MEDIUM | LOW | VRF covers most randomness; affiliate roll is accepted risk |

---

## Recommended Warden Specializations

Based on probability ranking, the four contest dry-run wardens should be assigned:

**1. Cross-Contract Composition Warden (Patterns 1, 4, 5, 12)**
Focus on delegatecall state sharing, token round-trip integrity, and cross-module reentrancy. Highest probability area for a new finding because it requires tracing state flows across module boundaries -- the one analytical lens that per-contract and per-function audits are structurally weakest at. Must independently derive the storage-write map and test callback paths through the Game router.

**2. Money Correctness Warden (Patterns 2, 6, 4, 11)**
Focus on BPS arithmetic verification for every entry point, ETH transfer fallback chains, and game-over distribution math. Must independently re-derive the conservation proof with adversarial msg.value inputs (1 wei, max/10000, etc.). Test the double-fallback path (ETH fail + stETH fail).

**3. RNG / VRF Warden (Patterns 3, 8, 15)**
Focus on commitment window re-verification with fresh eyes, plus MEV analysis of VRF fulfillment ordering. Lowest probability of a new finding due to comprehensive prior coverage (v3.8 commitment window, v3.7 VRF path audit), but highest severity if a gap exists. Must independently verify the 51/51 SAFE proof, not merely review it.

**4. Gas / Storage Warden (Patterns 7, 9, 10)**
Focus on constructing adversarial on-chain states that maximize gas consumption in advanceGame, verifying every bit boundary in packed storage slots, and testing direct module invocation (bypassing the router). The storage packing verification is the most likely source of a finding in this bucket.

---

## Sources

- [OWASP Smart Contract Top 10 2025-2026](https://owasp.org/www-project-smart-contract-top-10/) -- vulnerability category rankings and financial impact data
- [Hacken: Top 10 Smart Contract Vulnerabilities 2025](https://hacken.io/discover/smart-contract-vulnerabilities/) -- $953.2M access control, $63.8M logic errors, $35.7M reentrancy data
- [Solodit Audit Checklist (Cyfrin)](https://github.com/Cyfrin/audit-checklist) -- community-curated vulnerability checklist from competitive audit findings
- [Cyfrin: Solodit Checklist - Reentrancy](https://www.cyfrin.io/blog/solodit-checklist-explained-8-reentrancy-attack) -- cross-function, cross-contract, read-only reentrancy patterns
- [Cyfrin: Solodit Checklist - Miner Attacks](https://www.cyfrin.io/blog/solodit-checklist-explained-6-miner-attacks) -- block proposer bias, frontrunning patterns
- [Halborn: Top 100 DeFi Hacks 2025](https://www.halborn.com/reports/top-100-defi-hacks-2025) -- real exploit data
- [OpenZeppelin: ERC4626 Inflation Attack Defense](https://blog.openzeppelin.com/a-novel-defense-against-erc4626-inflation-attacks) -- first depositor/share inflation
- [Olympix: Why Smart Contract Audits Fail](https://olympix.security/blog/why-smart-contract-audits-fail) -- cross-protocol composability gaps
- [Code4rena First $1M Stats](https://cmichel.io/code4rena-first-1m-stats/) -- competitive audit finding patterns
- [Vibranium Audits: Unchecked Return Values](https://www.vibraniumaudits.com/post/understanding-unchecked-return-values-in-solidity-low-level-calls) -- SWC-104 silent loss
- [SlowMist: Delegatecall Vulnerabilities](https://www.slowmist.com/articles/solidity-security/Common-Vulnerabilities-in-Solidity-Delegatecall.html) -- storage collision in module architectures
- [Chainlink VRF Security Considerations](https://docs.chain.link/vrf/v1/security) -- fulfillment ordering, request-fulfillment gap
- [QuillAudits: Why Contracts Pass Audits But Still Get Hacked](https://www.quillaudits.com/blog/smart-contract/smart-contract-pass-audits-but-still-gets-hacked) -- composability and multi-step vulnerabilities
- [OWASP SC Top 10 2026 Update](https://dev.to/ohmygod/owasp-smart-contract-top-10-2026-reentrancy-falls-to-8-proxy-bugs-enter-and-your-new-audit-57l) -- reentrancy drop to #8, proxy bugs rise
