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

**Gameover prevrandao fallback.** `_getHistoricalRngFallback` uses `block.prevrandao` as supplementary entropy when VRF is unavailable at game over. A block proposer can bias prevrandao (1-bit manipulation on binary outcomes). Edge-of-edge case: gameover + VRF dead 3+ days. 5 committed VRF words provide bulk entropy. (See F-25-08 in `audit/FINDINGS-v25.0.md`; re-verified v29.0 Phase 235 RNG-01 at HEAD 1646d5af — see `audit/FINDINGS-v29.0.md` regression appendix)

**EntropyLib XOR-shift PRNG for lootbox outcome rolls.** `EntropyLib.entropyStep()` uses a 256-bit XOR-shift PRNG (shifts 7/9/8) for lootbox outcome derivation (target level, ticket counts, BURNIE amounts, boons). XOR-shift has known theoretical weaknesses (cannot produce zero state, fixed cycle, correlated consecutive outputs). Exploitation is infeasible: the PRNG is seeded per-player, per-day, per-amount via `keccak256(rngWord, player, day, amount)` where `rngWord` is VRF-derived. The small number of entropy steps per resolution (5-10) and modular arithmetic over small ranges further mask any non-uniformity.

**Lootbox RNG uses index advance isolation instead of rngLockedFlag.** The rngLockedFlag is set for daily VRF requests but NOT for mid-day lootbox RNG requests. Lootbox RNG isolation relies on a separate mechanism: the lootbox VRF request index advances past the current fulfillment index, preventing any overlap between daily and lootbox VRF words. This asymmetry is intentional -- index advance isolation is proven equivalent to flag-based isolation for the lootbox path. (See F-25-07 in `audit/FINDINGS-v25.0.md`; re-verified v29.0 Phase 235 RNG-01 + RNG-02 at HEAD 1646d5af)


**Decimator settlement temporarily over-reserves claimablePool.** During decimator settlement, the full decimator pool is reserved in `claimablePool` before individual winner claims are credited to `claimableWinnings`. This temporarily breaks the invariant `claimablePool == SUM(claimableWinnings[*])`, but the inequality is always in the safe direction: `claimablePool >= SUM(claimableWinnings[*])` (over-reserved, never under-reserved). The invariant is restored when all decimator claims are credited. Documented in DegenerusGameStorage NatSpec at L344-L345. (See F-25-12 in `audit/FINDINGS-v25.0.md`; re-verified v29.0 Phase 235 CONS-01 at HEAD 1646d5af)

**BAF event-widening and `BAF_TRAIT_SENTINEL=420` pattern.** BAF (Big-Ass-Friday) jackpot payouts use a `uint16 private constant BAF_TRAIT_SENTINEL = 420;` (declared at `DegenerusGameJackpotModule.sol:136`) as a sentinel value in event emissions at the four `runBafJackpot` emit sites (`JackpotEthWin` at lines 2002 and 2034; `JackpotTicketWin` at lines 2014 and 2038). 420 is out-of-domain for real trait IDs (`uint8` max = 255) by construction. The `JackpotEthWin` and `JackpotTicketWin` event declarations are declared with `uint16 indexed traitId` to carry the sentinel (at `DegenerusGameJackpotModule.sol:69-77` field at line 72 and `:80-87` field at line 83 respectively). On-chain EVM topic encoding is 32-byte left-padded regardless of declared width; the wider declaration does not affect on-chain log behavior. The canonical event signatures differ from a `uint8 traitId` encoding, which changes the keccak-derived `topic0` hash — off-chain ABI consumers (indexers, UI subgraphs, The Graph) must regenerate their ABIs to consume the declared types. The sentinel approach avoids introducing a separate event type per BAF path while preserving structural domain-separation guarantees (wider declared type, out-of-domain value, `private` visibility keeps the symbol module-local). Intentional design. `JackpotBurnieWin` at line 90-96 retains `uint8 traitId` at line 93 (non-BAF emitters continue passing real `uint8` values). (See F-29-01 and F-29-02 in `audit/FINDINGS-v29.0.md`)

**Gameover RNG substitution for mid-cycle write-buffer tickets.** Degenerus enforces an "RNG-consumer determinism" invariant: every RNG consumer's entropy should be fully committed at input time — the VRF word that a consumer will ultimately read must be unknown-but-bound at the moment that consumer's input parameters are committed to storage. Phase 235 RNG-01 and RNG-02 prove this invariant holds for every new RNG consumer in the v29.0 delta under normal and skip-split paths. One terminal-state case technically violates it: if a mid-cycle ticket-buffer swap has occurred (daily RNG request via `_swapAndFreeze(purchaseLevel)` at `DegenerusGameAdvanceModule.sol:292`, OR mid-day lootbox RNG request via `_swapTicketSlot(purchaseLevel_)` at `DegenerusGameAdvanceModule.sol:1082`) and the new write buffer is populated with tickets queued at the current level awaiting the expected-next VRF fulfillment, a game-over event intervening before that fulfillment causes those tickets to drain under `_gameOverEntropy` (at `DegenerusGameAdvanceModule.sol:1222-1246`, VRF-derived with `block.prevrandao` admixture per the "Gameover prevrandao fallback" entry above / F-25-08 when VRF is dead 3+ days) rather than the originally-anticipated VRF word. Acceptance rationale: (a) only reachable at gameover — a terminal state with no further gameplay after the 30-day post-gameover window; (b) no player-reachable exploit — gameover is triggered by a 120-day liveness stall or a pool deficit, neither of which an attacker can time against a specific mid-cycle write-buffer state; (c) at gameover the protocol must drain within bounded transactions and cannot wait for a deferred fulfillment that may never arrive if the VRF coordinator itself is the reason for the liveness stall; (d) all substitute entropy is VRF-derived or VRF-plus-prevrandao. Phase 235 TRNX-01's 4-Path Walk Gameover row verdict (SAFE / Finding Candidate: N) is unchanged — this is a disclosure supplement, not a re-classification. Documented retroactively during Phase 236 consolidation review. (See F-29-04 in `audit/FINDINGS-v29.0.md`)

**Deploy-pipeline VRF_KEY_HASH regex is single-line only.** `scripts/lib/patchContractAddresses.js` replaces the `VRF_KEY_HASH` bytes32 constant in `ContractAddresses.sol` via a regex that requires the declaration, hex literal, and terminating semicolon on the same line. If the constant is ever reformatted to the multi-line style already used by `ContractAddresses.sol:8-9` (with the `0xabab...` literal wrapped to its own line), `src.replace()` silently returns the input unchanged and the deploy-time constant retains its dummy value. The accepted mitigation is operator review of `ContractAddresses.sol` before every mainnet deploy — compiled bytecode surfaces the post-patch value in a diff — rather than hardening the regex in the pipeline. A future cycle may escalate if an automated deploy path removes that review gate. (See F-27-12 in `audit/FINDINGS-v27.0.md`)

**Parallel `make -j test` mutates `ContractAddresses.sol` concurrently.** `Makefile:44` declares `test: test-foundry test-hardhat` and the `test-foundry` recipe patches `ContractAddresses.sol` in-place before compilation and restores it after the suite exits. Running `make -j2 test` schedules both sub-targets concurrently, so `test-hardhat` can compile against the Foundry-patched addresses or catch the restore mid-write. Default serial invocation (`make test`) is unaffected and is the supported workflow. Recommended mitigations for operators who want parallel builds are `.NOTPARALLEL: test` or a file-lock around the patch/restore pair; the pre-existing footgun is accepted rather than adding Makefile complexity. (See F-27-05 in `audit/FINDINGS-v27.0.md`)

**v27.0 Phase 222 VERIFICATION gap closures (in-cycle).** During Plan 222-02 code review, two quality gaps were filed against the external-function-coverage deliverables: (1) 62 of 76 tests in `test/fuzz/CoverageGap222.t.sol` asserted only reachability (`(bool ok,) = addr.call(...); ok; assertTrue(true)`) rather than guard-rejection or observable state change, and (2) `scripts/coverage-check.sh` drift mode ran a global function-name grep against the matrix rather than a contract-scoped membership test, so a same-name function added to a new contract would be masked by an existing row under another contract (e.g., `BurnieCoin.transfer(`). Both gaps were closed in-cycle by Plan 222-03: commit `ef83c5cd` rewrote the 62 reachability-only tests (plus the tautological `uint32 >= 0` check in `test_gap_lifecycle_purchase_then_advanceGame`) to assert guard-rejection or pre/post snapshot state changes, and commit `e0a1aa3e` introduced a preflight matrix parser that populates per-section function sets so drift enforcement is now scoped to `(contract, function)` pairs. The fix also surfaced a real drift it was previously masking — `DegenerusGame.sol`'s `emitDailyWinningTraits` self-call wrapper (added in commit `e4064d67`) was missing a row under the `DegenerusGame.sol` section; the row was added in the same commit. 222-VERIFICATION.md re-verified at 4/4 must-haves. (See F-27-13 and F-27-14 in `audit/FINDINGS-v27.0.md`)

---

## Automated Tool Findings (Pre-disclosed)

Slither 0.11.5 (1,959 raw findings, 29 detectors after triage) and 4naly3er (4,453 instances, 78 categories after triage). Full triage: `audit/bot-race/slither-triage.md`, `audit/bot-race/4naly3er-triage.md`.

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
