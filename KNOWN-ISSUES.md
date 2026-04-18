# Known Issues

Pre-disclosure for audit wardens. If you find something listed here, it's already known.

Pre-audited with Slither v0.11.5 + 4naly3er. 110 detector categories triaged (2 Slither DOCUMENT, 20 4naly3er DOCUMENT, 84 FP + 4 overlapping). DOCUMENT findings below.

---

## Design Decisions

These are architectural decisions, not vulnerabilities.

**All rounding favors solvency.** Every BPS calculation rounds down on payouts and up on burns. stETH transfers retain 1-2 wei per operation. The solvency invariant `balance >= claimablePool` is strengthened by rounding, never weakened. (Detectors: `[L-13]`, `[L-14]`)

**Daily advance assumption.** The protocol assumes `advanceGame` is called to completion every day when available. The advance bounty (escalating from 0.005 to 0.03 ETH-equivalent over 2 hours), and the fact that this function delivers jackpot payments, incentivizes this but does not guarantee it. If `advanceGame` is not called for multiple days, the next call backfills gap days (capped at 120 iterations for gas safety). Gap days beyond 120 are skipped — coinflip payouts for those days are forfeited. In practice, the incentives make daily calling economically rational.

**Non-VRF entropy for affiliate winner roll.** Deterministic seed (gas optimization). Worst case: player times purchases to direct affiliate credit to a different affiliate. No protocol value extraction.

**VRF swap governance.** Emergency VRF coordinator rotation requires a 20h+ stall and sDGNRS community approval with time-decaying threshold. Execution requires approve weight > reject weight and meeting the threshold -- reject voters holding more sDGNRS than approvers block the proposal. This is the intended trust model.

**Price feed swap governance.** LINK/ETH price feed rotation requires feed unhealthy for 2d+ (admin) or 7d+ (community), then sDGNRS governance vote with defence-weighted threshold (50% → 15% floor over 4 days). If 15% approval with approve > reject cannot be reached, the proposal expires. Prevents attacker-controlled feed from enabling BURNIE hyperinflation via fake LINK valuations. If the feed is down, LINK donations still work -- donors just don't receive BURNIE credit.

**Chainlink VRF V2.5 dependency.** Sole randomness source. If VRF goes down, the game stalls but no funds are lost. Upon governance-gated coordinator swap, gap day RNG words are backfilled via keccak256(vrfWord, gapDay) and orphaned lootbox indices receive fallback words. Coinflips and lootboxes resolve naturally after backfill. Independent recovery paths: governance-based coordinator rotation (20h+ stall threshold) and 120-day inactivity timeout.

**Backfill cap at 120 gap days.** `_backfillGapDays` caps iteration at 120 days to stay within block gas limit (~9M gas). If a VRF stall exceeds 120 days, gap days beyond the cap are skipped -- coinflip stakes for those days are frozen (not lost or burned). The `skip-unresolved` handling in BurnieCoinflip (rewardPercent=0 && !win) silently advances past unresolved days. This scenario requires a sustained 4-month Chainlink VRF outage with no coordinator migration -- an unprecedented infrastructure failure affecting the entire ecosystem.

**Lido stETH dependency.** Prize pool growth depends on staking yield. If yield goes to zero, positive-sum margin disappears. Protocol remains solvent -- the solvency invariant does not depend on yield.

**Gameover prevrandao fallback.** `_getHistoricalRngFallback` (`DegenerusGameAdvanceModule.sol:1301`) hashes `block.prevrandao` together with up to 5 historical VRF words as supplementary entropy when VRF is unavailable at game over. A block proposer can bias prevrandao (1-bit manipulation on binary outcomes). Trigger gating: only reachable inside `_gameOverEntropy` (`AdvanceModule:1252`) and only when an in-flight VRF request has been outstanding for at least `GAMEOVER_RNG_FALLBACK_DELAY = 14 days` (`AdvanceModule:109`). The 14-day window is ~17× the 20-hour VRF coordinator-swap governance threshold (see "VRF swap governance" entry above), so this path activates only after both VRF itself AND the governance recovery mechanism have failed to land a fresh coordinator within 14 days. The 5 committed historical VRF words provide bulk entropy; prevrandao only adds unpredictability.

**EntropyLib XOR-shift PRNG for lootbox outcome rolls.** `EntropyLib.entropyStep()` uses a 256-bit XOR-shift PRNG (shifts 7/9/8) for lootbox outcome derivation (target level, ticket counts, BURNIE amounts, boons). XOR-shift has known theoretical weaknesses (cannot produce zero state, fixed cycle, correlated consecutive outputs). Exploitation is infeasible: the PRNG is seeded per-player, per-day, per-amount via `keccak256(rngWord, player, day, amount)` where `rngWord` is VRF-derived. The small number of entropy steps per resolution (5-10) and modular arithmetic over small ranges further mask any non-uniformity.

**Lootbox RNG uses index advance isolation instead of rngLockedFlag.** The rngLockedFlag is set for daily VRF requests but NOT for mid-day lootbox RNG requests. Lootbox RNG isolation relies on a separate mechanism: the lootbox VRF request index advances past the current fulfillment index, preventing any overlap between daily and lootbox VRF words. This asymmetry is intentional -- index advance isolation is proven equivalent to flag-based isolation for the lootbox path.


**Decimator settlement temporarily over-reserves claimablePool.** During decimator settlement, the full decimator pool is reserved in `claimablePool` before individual winner claims are credited to `claimableWinnings`. This temporarily breaks the invariant `claimablePool == SUM(claimableWinnings[*])`, but the inequality is always in the safe direction: `claimablePool >= SUM(claimableWinnings[*])` (over-reserved, never under-reserved). The invariant is restored when all decimator claims are credited. Documented in DegenerusGameStorage NatSpec at L344-L345.

**Gameover RNG substitution for mid-cycle write-buffer tickets.** Degenerus enforces an "RNG-consumer determinism" invariant: every RNG consumer's entropy must be fully committed at input time — the VRF word that a consumer will ultimately read must be unknown-but-bound at the moment that consumer's input parameters are committed to storage. One terminal-state case technically violates it: if a mid-cycle ticket-buffer swap has occurred (daily RNG request via `_swapAndFreeze(purchaseLevel)` at `DegenerusGameAdvanceModule.sol:292`, OR mid-day lootbox RNG request via `_swapTicketSlot(purchaseLevel_)` at `DegenerusGameAdvanceModule.sol:1082`) and the new write buffer is populated with tickets queued at the current level awaiting the expected-next VRF fulfillment, a game-over event intervening before that fulfillment causes those tickets to drain under the final gameover entropy (`_gameOverEntropy` at `DegenerusGameAdvanceModule.sol:1222-1246` — the gameover VRF word under normal conditions, or the VRF-plus-`block.prevrandao` admixture described in the "Gameover prevrandao fallback" entry above when an in-flight VRF request stays unfulfilled for 14+ days) rather than the originally-anticipated mid-day VRF word. The substitution applies in both gameover variants — it is NOT contingent on the prevrandao fallback activating. Acceptance rationale: (a) only reachable at gameover — a terminal state with no further gameplay after the 30-day post-gameover window; (b) no player-reachable exploit — gameover is triggered by a 120-day liveness stall or a pool deficit, neither of which an attacker can time against a specific mid-cycle write-buffer state; (c) at gameover the protocol must drain within bounded transactions and cannot wait for a deferred fulfillment that may never arrive if the VRF coordinator itself is the reason for the liveness stall; (d) all substitute entropy is VRF-derived or VRF-plus-prevrandao.

---

## Automated Tool Findings (Pre-disclosed)

Slither 0.11.5 (1,959 raw findings, 29 detectors after triage) and 4naly3er (4,453 instances, 78 categories after triage).

### ETH Transfer Safety

**Payout functions send ETH to user-supplied addresses.** `_payoutWithStethFallback`, `_payoutWithEthFallback`, `_payEth` (4 instances) send ETH via `.call{value:}`. Destinations are `msg.sender` or player addresses from game state -- all paths have access control. (Detector: `arbitrary-send-eth`)

### Missing Event for claimablePool Decrement

**resolveRedemptionLootbox decrements claimablePool without dedicated event.** Higher-level redemption events capture the full context. The variable is a running tally, not a user-facing balance. (Detector: `events-maths`)

### Centralization Risk

**Admin functions gated by onlyOwner (7 instances).** DegenerusAdmin critical functions (VRF coordinator swap, price feed swap) require sDGNRS governance vote. Remaining onlyOwner functions are operational (staking) and deity pass metadata. Admin cannot drain game funds -- ETH flows are contract-controlled. (Detector: `[M-2]`)

### Chainlink Price Feed

**LINK/ETH feed used for LINK donation valuation only.** Feed swap is governance-gated (2d+ admin / 7d+ community stall + sDGNRS vote). If the feed is stale or down, LINK donations still process but no BURNIE credit is issued. A compromised feed cannot cause damage without passing governance. (Detector: `[M-3]`)

### No SafeERC20 Wrappers

**Protocol uses `.transfer()`/`.transferFrom()` with return value checks instead of SafeERC20.** Only interacts with known tokens (stETH, BURNIE, LINK, wXRP) that return bool per standard. SafeERC20 would add ~2,600 gas/call for no benefit with these specific tokens. (Detectors: `[M-5]`, `[M-6]`, `[L-19]`)

### abi.encodePacked Hash Collision

**abi.encodePacked used for entropy derivation and SVG strings (35 instances).** Entropy inputs are fixed-width (uint256, address) -- no collision possible. SVG string results are not used as keys. No exploitable collision path. (Detector: `[L-4]`)

### Division by Zero

**All divisors have implicit guards (27 instances).** BPS constants are non-zero, supply checks revert on zero, level-derived values guarantee non-zero during active game. (Detector: `[L-7]`)

### External Call Gas Consumption

**`.call{value:}("")` forwards all gas (11 instances).** Recipients are player addresses (self-grief only) or known protocol contracts with minimal receive() logic. CEI pattern followed. Gas-limited calls would risk breaking legitimate receives. (Detector: `[L-9]`)

### Burn/Zero-Address Handling

**Protocol burn functions are intentional operations (67 instances).** BURNIE burn mechanics, sDGNRS gambling burn, GNRUS burn redemption are all by design. Internal functions use msg.sender/contract-to-contract paths ensuring valid addresses. (Detector: `[L-12]`)

### Unchecked Downcasting

**Intentional for storage packing (50 instances).** All downcasts preceded by range validation or mathematically guaranteed to fit (e.g., BPS < 10,000 fits uint16, timestamps < 2^48 fits uint48). SafeCast would add redundant gas overhead. (Detector: `[L-18]`)

### Missing address(0) Checks

**BurnieCoinflip bountyOwedTo from game logic (always valid player), DeityPass renderer setter is admin-only (2 instances).** Neither can result in fund loss if zero. (Detector: `[NC-2]`)

### Magic Numbers

**Bit positions/masks in assembly, small obvious arithmetic, BPS values documented in NatSpec.** Named constants used where readability matters. Remaining literals are documented via NatSpec comments. (Detectors: `[NC-6]`, `[NC-34]`)

### Event Indexed Fields

**Some events omit indexed on fields not useful as filter keys.** Key indexer-critical events (player actions, game state transitions) are properly indexed. Bookkeeping events intentionally omit indexes. (Detectors: `[NC-10]`, `[NC-33]`)

### Event Missing Old+New Values

**Parameter-change events emit new value only (6 instances).** Admin operations are infrequent. Adding old value would increase gas for minimal debugging benefit. (Detector: `[NC-11]`)

### Long Functions

**Complex game logic necessarily exceeds 50 lines (377 instances).** Splitting increases gas via call overhead. Organized with NatSpec section banners for readability. (Detector: `[NC-13]`)

### Setter Validation

**Admin-only setters trust admin (23 instances).** Critical setters (VRF swap, price feed swap) have governance checks. Non-critical setters (renderer) trust the admin. (Detector: `[NC-16]`)

### Missing Parameter Change Events

**27 instances covered by Phase 132 event audit.** 24 INFO findings (all DOCUMENT). (Detector: `[NC-17]`)

### Unchecked Arithmetic

**Protocol uses unchecked blocks strategically (1,054 flagged instances).** Remaining checked arithmetic is intentional safety margin. Gas ceiling analysis (v3.5 Phase 57) confirmed all critical paths within block gas limit. (Detector: `[GAS-7]`)

---

## ERC-20 Deviations

DGNRS and BURNIE are ERC-20 tokens with 4 intentional deviations. sDGNRS and GNRUS are soulbound (not ERC-20) -- filing ERC-20 compliance issues against them is invalid.

**DGNRS blocks transfer to its own contract address.** `_transfer` reverts with `Unauthorized()` when `to == address(this)`. EIP-20 does not restrict recipients. This prevents accidental token lockup since DGNRS held by the contract is indistinguishable from the sDGNRS-backed reserve. Intentional design.

**BURNIE game contract bypasses transferFrom allowance.** The DegenerusGame contract can call `transferFrom` without prior approval. This is the trusted contract pattern -- the game address is a compile-time immutable constant, not upgradeable. Enables seamless gameplay transactions without pre-approval UX. All other callers require standard allowance.

**BURNIE transfer/transferFrom may auto-claim pending coinflip winnings.** Before executing a transfer, `_claimCoinflipShortfall` checks if the sender has insufficient balance and auto-claims pending coinflip BURNIE from the trusted BurnieCoinflip contract (compile-time constant). This mints tokens before the transfer, which is non-standard ERC-20 behavior. Intentional UX design -- players can spend winnings without a separate claim step. The coinflip contract is immutable and trusted.

**BURNIE sent to VAULT is burned, not transferred.** `_transfer` special-cases `to == ContractAddresses.VAULT` -- tokens are burned (totalSupply reduced) and added to vault's virtual mint allowance. The VAULT uses a virtual reserve model where `balanceOf[VAULT]` is always 0 and the actual reserve is tracked in `_supply.vaultAllowance`. Emits `Transfer(from, address(0))` (burn event). Intentional architecture.

