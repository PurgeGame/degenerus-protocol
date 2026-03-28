# Known Issues

Pre-disclosure for audit wardens. If you find something listed here, it's already known.

Pre-audited with Slither v0.11.5 + 4naly3er. 110 detector categories triaged (2 Slither DOCUMENT, 20 4naly3er DOCUMENT, 84 FP + 4 overlapping). DOCUMENT findings below.

---

## Design Decisions

These are architectural decisions, not vulnerabilities.

**All rounding favors solvency.** Every BPS calculation rounds down on payouts and up on burns. stETH transfers retain 1-2 wei per operation. The solvency invariant `balance >= claimablePool` is strengthened by rounding, never weakened. (Detectors: `[L-13]`, `[L-14]`)

**Non-VRF entropy for affiliate winner roll.** Deterministic seed (gas optimization). Worst case: player times purchases to direct affiliate credit to a different affiliate. No protocol value extraction.

**VRF swap governance.** Emergency VRF coordinator rotation requires a 20h+ stall and sDGNRS community approval with time-decaying threshold. Execution requires approve weight > reject weight and meeting the threshold -- reject voters holding more sDGNRS than approvers block the proposal. This is the intended trust model.

**Price feed swap governance.** LINK/ETH price feed rotation requires feed unhealthy for 2d+ (admin) or 7d+ (community), then sDGNRS governance vote with defence-weighted threshold (50% → 15% floor over 4 days). If 15% approval with approve > reject cannot be reached, the proposal expires. Prevents attacker-controlled feed from enabling BURNIE hyperinflation via fake LINK valuations. If the feed is down, LINK donations still work -- donors just don't receive BURNIE credit.

**Chainlink VRF V2.5 dependency.** Sole randomness source. If VRF goes down, the game stalls but no funds are lost. Upon governance-gated coordinator swap, gap day RNG words are backfilled via keccak256(vrfWord, gapDay) and orphaned lootbox indices receive fallback words. Coinflips and lootboxes resolve naturally after backfill. Independent recovery paths: governance-based coordinator rotation (20h+ stall threshold) and 120-day inactivity timeout.

**Lido stETH dependency.** Prize pool growth depends on staking yield. If yield goes to zero, positive-sum margin disappears. Protocol remains solvent -- the solvency invariant does not depend on yield.

**Gameover prevrandao fallback.** `_getHistoricalRngFallback` uses `block.prevrandao` as supplementary entropy when VRF is unavailable at game over. A block proposer can bias prevrandao (1-bit manipulation on binary outcomes). Edge-of-edge case: gameover + VRF dead 3+ days. 5 committed VRF words provide bulk entropy.

**EntropyLib XOR-shift PRNG for lootbox outcome rolls.** `EntropyLib.entropyStep()` uses a 256-bit XOR-shift PRNG (shifts 7/9/8) for lootbox outcome derivation (target level, ticket counts, BURNIE amounts, boons). XOR-shift has known theoretical weaknesses (cannot produce zero state, fixed cycle, correlated consecutive outputs). Exploitation is infeasible: the PRNG is seeded per-player, per-day, per-amount via `keccak256(rngWord, player, day, amount)` where `rngWord` is VRF-derived. The small number of entropy steps per resolution (5-10) and modular arithmetic over small ranges further mask any non-uniformity.

---

## Automated Tool Findings (Pre-disclosed)

Slither 0.11.5 (1,959 raw findings, 29 detectors after triage) and 4naly3er (4,453 instances, 78 categories after triage). Full triage: `audit/bot-race/slither-triage.md`, `audit/bot-race/4naly3er-triage.md`.

### ETH Transfer Safety

**Payout functions send ETH to user-supplied addresses.** `_payoutWithStethFallback`, `_payoutWithEthFallback`, `_payEth` (4 instances) send ETH via `.call{value:}`. Destinations are `msg.sender` or player addresses from game state -- all paths have access control. ETH conservation proven in v5.0 adversarial audit. (Detector: `arbitrary-send-eth`)

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

**All divisors have implicit guards (27 instances).** BPS constants are non-zero, supply checks revert on zero, level-derived values guarantee non-zero during active game. Exhaustively audited in v3.3 economic analysis + v5.0 adversarial audit. (Detector: `[L-7]`)

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

**27 instances covered by Phase 132 event audit.** 24 INFO findings (all DOCUMENT). Full details: `audit/event-correctness.md`. (Detector: `[NC-17]`)

### Unchecked Arithmetic

**Protocol uses unchecked blocks strategically (1,054 flagged instances).** Remaining checked arithmetic is intentional safety margin. Gas ceiling analysis (v3.5 Phase 57) confirmed all critical paths within block gas limit. (Detector: `[GAS-7]`)

---

## ERC-20 Deviations

DGNRS and BURNIE are ERC-20 tokens with 4 intentional deviations. sDGNRS and GNRUS are soulbound (not ERC-20) -- filing ERC-20 compliance issues against them is invalid. Full analysis: `audit/erc-20-compliance.md`.

**DGNRS blocks transfer to its own contract address.** `_transfer` reverts with `Unauthorized()` when `to == address(this)`. EIP-20 does not restrict recipients. This prevents accidental token lockup since DGNRS held by the contract is indistinguishable from the sDGNRS-backed reserve. Intentional design.

**BURNIE game contract bypasses transferFrom allowance.** The DegenerusGame contract can call `transferFrom` without prior approval. This is the trusted contract pattern -- the game address is a compile-time immutable constant, not upgradeable. Enables seamless gameplay transactions without pre-approval UX. All other callers require standard allowance.

**BURNIE transfer/transferFrom may auto-claim pending coinflip winnings.** Before executing a transfer, `_claimCoinflipShortfall` checks if the sender has insufficient balance and auto-claims pending coinflip BURNIE from the trusted BurnieCoinflip contract (compile-time constant). This mints tokens before the transfer, which is non-standard ERC-20 behavior. Intentional UX design -- players can spend winnings without a separate claim step. The coinflip contract is immutable and trusted.

**BURNIE sent to VAULT is burned, not transferred.** `_transfer` special-cases `to == ContractAddresses.VAULT` -- tokens are burned (totalSupply reduced) and added to vault's virtual mint allowance. The VAULT uses a virtual reserve model where `balanceOf[VAULT]` is always 0 and the actual reserve is tracked in `_supply.vaultAllowance`. Emits `Transfer(from, address(0))` (burn event). Intentional architecture.

---

## Event Design Decisions

Phase 132 systematic event audit covered all 26 production contracts. 24 INFO-level DOCUMENT findings remain. Key categories: 19 missing events for non-critical state changes (admin setters, internal bookkeeping), 2 stale parameter values (cosmetic), 2 missing indexed fields, 1 unused event declaration. Full details: `audit/event-correctness.md`.
