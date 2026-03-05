# Architecture Patterns: Zero-Day Attack Surface Audit Integration

**Domain:** Smart contract security audit -- novel zero-day hunting on 22-contract delegatecall architecture
**Researched:** 2026-03-05

## Recommended Architecture

The zero-day audit is an **analysis overlay** on the existing protocol architecture, not new contract code. It produces Foundry test harnesses, Slither custom detectors, and Halmos verification properties that target five attack surface categories. Each category maps to specific contract interfaces and data flows.

### Existing Architecture (Attack Surface Map)

```
                        +------------------+
                        |  DegenerusAdmin  |  wireVrf, subscription mgmt
                        +--------+---------+
                                 |
                        +--------v---------+
                        |  DegenerusGame   |  FSM orchestrator, 30 delegatecall sites
                        |  (19KB, largest)  |  receive() payable, ETH custody
                        +--+--+--+--+--+---+
                           |  |  |  |  |
              delegatecall |  |  |  |  | delegatecall
          +----------------+  |  |  |  +----------------+
          v                   v  |  v                    v
    MintModule          AdvanceModule  JackpotModule   WhaleModule
    (15 unchecked)      (4 assembly)   (40 unchecked)  (6 unchecked)
          |                   |             |               |
          |    +--------------+             |               |
          v    v              v             v               v
    EndgameModule    DecimatorModule   LootboxModule   DegeneretteModule
    GameOverModule   BoonModule        MintStreakUtils  PayoutUtils
          |                                |
          +---------- Shared Storage ------+
          |     DegenerusGameStorage       |
          |  (single source of truth)      |
          +--------------------------------+
                        |
         +--------------+------------------+
         |              |                  |
    BurnieCoin    BurnieCoinflip     DegenerusVault
    (ERC20)       (14 unchecked)    (share classes)
         |              |                  |
    DegenerusStonk  DegenerusJackpots  DegenerusDeityPass
    (AMM-like)     (36 unchecked)     (ERC721)
         |              |
    DegenerusAffiliate  DegenerusQuests
    (referral tree)     (streak system)
```

### Component Boundaries for Zero-Day Analysis

| Component | Responsibility | Zero-Day Attack Surface | Priority |
|-----------|---------------|------------------------|----------|
| DegenerusGame | FSM, 30 delegatecall dispatch, ETH custody | Composition: module return values, state assumptions across delegatecall boundaries | CRITICAL |
| DegenerusGameStorage | 1 file, all 10 modules share it | BitPackingLib corruption: gap bits 155-227 writable? Cross-module state race via shared packed slots | CRITICAL |
| JackpotModule | 40 unchecked blocks, bucket math, winner selection | Precision: division chains in bucketShares(), rounding to zero in small pools | HIGH |
| MintModule | 15 unchecked blocks, 4 assembly SSTOREs, ticket pricing | Precision: cost formula `(priceWei * qty) / 400`, dust-free minting | HIGH |
| JackpotBucketLib | Pure math: scaling, capping, share distribution | Precision: `(pool * shareBps) / 10000`, `(share / unitBucket) * unitBucket` double-division | HIGH |
| GameTimeLib | Day index from timestamps, 22:57 UTC boundary | Temporal: underflow at DEPLOY_DAY_BOUNDARY, +-900s manipulation on day boundary | MEDIUM |
| EntropyLib | xorshift64 PRNG derivation from VRF | EVM: weak period analysis, state=0 absorbing state, bias in modular reduction | MEDIUM |
| DegenerusVault | Dual share classes (ETH + stETH) | Economic: donation attack on share price, stETH rebasing interaction | MEDIUM |
| DegenerusStonk | AMM-like token exchange | Economic: sandwich attacks, price manipulation via vault share value | MEDIUM |
| ContractAddresses | Compile-time constants, all address(0) in source | EVM: what happens if deploy script bug leaves an address as 0? delegatecall to address(0) | LOW |
| BurnieCoinflip | 14 unchecked blocks, coin mechanics | Precision: payout rounding, EV calculation edge cases | LOW |

### Data Flow: How Zero-Day Categories Map to Contract Interactions

#### 1. Composition Bugs (Cross-Contract State)

Primary target: the 30 delegatecall sites in DegenerusGame.

```
DegenerusGame.purchase()
  -> delegatecall MintModule.purchase()
     -> MintModule reads/writes shared storage (BitPackingLib fields)
     -> MintModule calls COIN.gameMint() (cross-contract)
     -> MintModule calls VAULT.call{value}() (ETH transfer)
     -> Returns to DegenerusGame context
  -> DegenerusGame reads storage that MintModule modified
```

**Analysis approach:**
- Map every storage slot written by each module during delegatecall
- Identify slots read by DegenerusGame AFTER delegatecall returns
- Find state assumptions: does Game assume a slot is unchanged when a module actually writes it?
- Trace cross-module state flows: Module A writes X, later Module B reads X -- what if B assumes A's invariant?

**Specific composition risks:**
1. **Module A + Module B shared state race**: MintModule writes `mintData[player]` via BitPackingLib, then JackpotModule reads the same packed word -- does JackpotModule's read handle partially-written state?
2. **Return value trust**: 30 delegatecall sites all check `(bool ok, bytes memory data)` but what if module returns unexpected data layout? All use uniform checked pattern (verified v1.0), but verify ABI decode assumptions.
3. **Cross-contract call chains**: MintModule delegatecall writes storage, then calls external COIN contract which calls back to Game -- reentrancy through delegation path.

#### 2. Precision and Rounding Exploitation

222 division operations across 21 files. Key chains:

```
Ticket pricing:    costWei = (priceWei * ticketQuantity) / 400
Jackpot shares:    share = (pool * shareBps) / 10_000
Bucket rounding:   perWinner = (share / unitBucket) * unitBucket  // double-division!
Bucket scaling:    scaled = (baseCount * scaleBps) / 10_000
```

**Analysis approach:**
- For each division, determine: can numerator be attacker-controlled? Can it be small enough to round to zero?
- Trace division chains: output of one division feeds input of another -- precision loss compounds
- Identify "free action" paths: if cost rounds to zero, attacker gets something for nothing
- Check `bucketShares()` remainder calculation: `shares[remainderIdx] = pool - distributed` -- if distributed > pool due to rounding up, underflow

**Highest-risk precision targets:**
1. `costWei = (priceWei * qty) / 400`: minimum priceWei is 0.01 ETH, minimum qty is 100 (1/4 ticket). `(0.01e18 * 100) / 400 = 2.5e15 wei` -- no zero-rounding. But verify edge: qty=1 gives `(0.01e18 * 1) / 400 = 25e12 wei` -- still nonzero. Need to verify minimum qty enforcement.
2. `(pool * shareBps[i]) / 10_000` in JackpotBucketLib: if pool < 10_000 wei, share rounds to zero. Attacker could drain pool to dust, then all shares round to zero but `remainder = pool - 0 = pool` -- solo bucket gets everything. Is this exploitable?
3. Lootbox EV calculations: 39 division operations in LootboxModule -- heavy rounding surface.

#### 3. Temporal Edge Cases

14 `block.timestamp` uses across 6 files. Key temporal boundaries:

```
GameTimeLib.currentDayIndexAt():
  dayBoundary = (ts - 82620) / 86400     // Day resets at 22:57 UTC
  dayIndex = dayBoundary - DEPLOY_DAY + 1

Advance module: levelStartTime checks, VRF timeout (18h), stall (3d), inactivity (365d)
GameOver module: 30-day sweep, 912-day pre-game timeout
```

**Analysis approach:**
- Test at exact boundary: ts = N * 86400 + 82620 (day boundary moment)
- Test with +-900s (Ethereum timestamp tolerance): can block proposer manipulate which "day" a transaction lands in?
- Multi-tx race: tx1 in day N, tx2 in day N+1 within same block (impossible on-chain but verify assumptions)
- Level transition timing: can a purchase land in the gap between jackpot phase end and next purchase phase start?
- GameTimeLib underflow: if `ts < JACKPOT_RESET_TIME`, the subtraction `ts - 82620` underflows (uint48 arithmetic) -- but Solidity 0.8+ catches this. However, `currentDayIndexAt` is called with `uint48(block.timestamp)` -- block.timestamp cast to uint48 will not underflow until year 8.9M.

#### 4. EVM-Level Weirdness

```
Assembly:     15 assembly blocks across 7 files (sstore/sload in MintModule, JackpotModule)
Unchecked:    231 unchecked blocks across 27 files
Bit packing:  BitPackingLib with gap at bits 155-227 (73 unused bits in mintData)
ETH forcing:  No selfdestruct in protocol, but external selfdestruct can force ETH
receive():    3 contracts accept ETH (Game=open, Vault=open, Stonk=onlyGame)
```

**Analysis approach:**
- **Assembly SSTORE**: Verify slot calculations match Solidity-computed storage layout. 6 assembly sstore/sload ops in MintModule and JackpotModule push to `traitBurnTicket` arrays -- slot = `keccak256(traitId . keccak256(level . baseSlot))` + index. Verify these match `forge inspect` output.
- **BitPackingLib gap**: Bits 155-227 are "reserved" but `setPacked` with arbitrary shift/mask could write into them. If any call site passes attacker-controlled shift/mask, the gap becomes writable and could corrupt adjacent fields when read with wrong mask.
- **ETH forcing**: `selfdestruct` (deprecated but still functional pre-Cancun, and still forces ETH post-Cancun via coinbase) can push ETH into Game contract. Game uses `address(this).balance` for solvency check -- forced ETH makes balance > obligations, which is safe (it inflates, not deflates). But verify no path uses `address(this).balance - obligations` as a "free ETH" source.
- **ABI encoding**: All 30 delegatecall sites use `abi.encodeWithSelector` -- verify no selector collision between module interfaces. Selector = first 4 bytes of keccak256(signature). With 30+ selectors, collision probability is negligible but worth automated check.

#### 5. Cross-System Economic Composition

```
ETH flow: Player -> Game -> {Vault, Stonk, Jackpots, Affiliate}
Token flow: Game.gameMint -> COIN.mint -> Coinflip.deposit -> COIN.burn
Share flow: Vault.deposit -> shares -> Vault.withdraw -> ETH/stETH
Affiliate: circular referrals, self-referral, affiliate bonus points
```

**Analysis approach:**
- **Vault share manipulation**: Donation attack -- deposit large ETH to inflate share price, then small depositors get 0 shares. Verified safe in v2.0 but re-examine with exact Vault math.
- **Stonk sandwich**: Stonk has AMM-like exchange. Can attacker front-run a large trade to extract value? Verify slippage protection.
- **Circular affiliates**: If A refers B, B refers C, C refers A -- does bonus accumulation create unbounded reward?
- **Cross-contract EV exploitation**: Lootbox EV depends on activity score. Activity score comes from mints. If minting is nearly free (precision exploit), attacker farms activity score for high-EV lootboxes.
- **stETH rebasing during game-over**: GameOverModule sends stETH to Vault. If rebase occurs between balance check and transfer, amount mismatch. Verified safe in v1.0 (no cached balance) but verify GameOverModule specifically.

## Patterns to Follow

### Pattern 1: Composition Invariant Testing

**What:** For each delegatecall site, write a Foundry invariant test that captures storage state before and after the call, verifying no unintended slot mutations.

**When:** Every delegatecall site that writes storage.

**Example:**
```solidity
// In a handler, wrap each delegatecall-triggering function
function purchase_withStorageCheck(address buyer, uint256 qty) external {
    // Snapshot slots we expect NOT to change
    bytes32 slot0Before = vm.load(address(game), bytes32(uint256(0)));

    // Execute
    game.purchase{value: cost}(buyer, qty, 0, bytes32(0), MintPaymentKind.DirectEth);

    // Verify: slot 0 timing fields should NOT change during purchase
    bytes32 slot0After = vm.load(address(game), bytes32(uint256(0)));
    // level, jackpotPhaseFlag should be unchanged
    assert(uint24(uint256(slot0Before) >> 208) == uint24(uint256(slot0After) >> 208));
}
```

### Pattern 2: Precision Boundary Fuzzing

**What:** Fuzz division operations with inputs that produce minimum nonzero and zero results.

**When:** Every division that feeds into ETH distribution or cost calculation.

**Example:**
```solidity
function testFuzz_bucketSharesNoUnderflow(uint256 pool, uint16[4] memory bps) public {
    // Constrain to realistic ranges
    pool = bound(pool, 1, 10_000 ether);
    // Ensure BPS sum to 10000
    // ...
    uint256[4] memory shares = JackpotBucketLib.bucketShares(pool, bps, counts, 0, unit);

    // Invariant: sum of shares == pool (no dust lost or created)
    uint256 sum = shares[0] + shares[1] + shares[2] + shares[3];
    assertEq(sum, pool, "Shares must sum to pool");
}
```

### Pattern 3: Temporal Boundary Testing

**What:** Test protocol behavior at exact day boundaries with timestamp manipulation.

**When:** Every function that uses GameTimeLib or block.timestamp comparisons.

**Example:**
```solidity
function testFuzz_dayBoundaryNoDoubleJackpot(uint256 offset) public {
    offset = bound(offset, 0, 1800); // +-900s proposer range
    uint256 boundary = deployTime + 86400 + 82620; // exact day 2 start

    vm.warp(boundary - offset);
    // ... trigger jackpot

    vm.warp(boundary + offset);
    // ... verify no double-trigger
}
```

## Anti-Patterns to Avoid

### Anti-Pattern 1: Testing Only Happy Paths

**What:** Writing fuzz tests that only exercise valid inputs within normal operating ranges.
**Why bad:** Zero-day bugs live at boundaries -- empty pools, maximum values, zero-quantity operations, level 0 vs level 16M.
**Instead:** Explicitly test at extremes: pool=1 wei, qty=1, level=0, level=uint24.max, timestamp at day boundary.

### Anti-Pattern 2: Trusting Prior Audit Conclusions Without Re-verification

**What:** Assuming "verified safe in v1.0" means no need to re-examine.
**Why bad:** Prior audits may have missed composition effects or tested in isolation. 10 agents unanimously found zero Medium+ -- which means either the protocol is genuinely hardened, or all 10 had the same blind spots.
**Instead:** Re-examine with different methodology. Prior audits tested "does X break?" -- zero-day hunting tests "what if X and Y interact in sequence Z that nobody considered?"

### Anti-Pattern 3: Assembly Verification by Reading Alone

**What:** Manually reviewing assembly SSTORE slot calculations and declaring them correct.
**Why bad:** Slot arithmetic depends on storage layout which depends on compiler version, viaIR, and variable ordering. Manual calculation is error-prone.
**Instead:** Use `forge inspect DegenerusGame storage-layout` to get compiler-verified slot numbers, then write tests that assert `vm.load(address(game), slot)` matches expected values after operations.

## Integration with Existing Infrastructure

### New Components (to create)

| Component | Type | Location | Purpose |
|-----------|------|----------|---------|
| CompositionHandler.sol | Foundry handler | test/fuzz/handlers/ | Ghost-tracks storage mutations across delegatecall boundaries |
| PrecisionBoundary.inv.t.sol | Invariant test | test/fuzz/invariant/ | Fuzz division chains for rounding exploits |
| TemporalBoundary.inv.t.sol | Invariant test | test/fuzz/invariant/ | Day boundary, VRF timeout, and phase transition timing |
| StorageSlotVerifier.t.sol | Unit test | test/fuzz/ | Asserts assembly SSTORE targets match forge inspect layout |
| SelectorCollision.t.sol | Unit test | test/fuzz/ | Checks all module interface selectors for collision |
| Slither custom detectors | Python | slither-detectors/ (new) | Division-before-multiplication chains, unchecked block analysis |
| Halmos properties | Solidity | test/halmos/ (new or existing) | Symbolic verification of BitPackingLib, EntropyLib |

### Modified Components (existing, extended)

| Component | Modification | Reason |
|-----------|-------------|--------|
| foundry.toml | Increase fuzz runs to 10000, invariant runs to 1000 | Higher coverage for edge cases |
| DeployProtocol.sol | No changes needed | Existing deployment works for new harnesses |
| GameHandler.sol | Add ghost variables for storage slot tracking | Composition analysis needs before/after snapshots |
| VRFHandler.sol | Add temporal boundary manipulation (vm.warp) | Temporal edge case testing |

### Build Order (respects dependencies)

```
Phase 1: Tooling Setup + Static Analysis
  1.1  Configure Slither for full triage (existing config, increase coverage)
  1.2  Run `forge inspect` on all 22 contracts, capture storage layouts
  1.3  Build selector collision checker (SelectorCollision.t.sol)
  1.4  Fix Halmos config for 0.3.3 compatibility
  Depends on: nothing (can start immediately)

Phase 2: Composition Analysis
  2.1  Map all 30 delegatecall storage write sets (which slots each module writes)
  2.2  Build CompositionHandler with storage snapshots
  2.3  Write composition invariant tests
  2.4  Test cross-module state assumptions (MintModule writes -> JackpotModule reads)
  Depends on: Phase 1.2 (storage layouts needed for slot mapping)

Phase 3: Precision Analysis (PARALLEL with Phase 2)
  3.1  Catalog all 222 division operations, classify by risk
  3.2  Write PrecisionBoundary invariant harness
  3.3  Fuzz JackpotBucketLib.bucketShares() specifically (highest-risk double-division)
  3.4  Verify ticket cost formula cannot round to zero
  Depends on: nothing (can run parallel with Phase 2)

Phase 4: Temporal + EVM Analysis
  4.1  Build TemporalBoundary invariant harness
  4.2  Test GameTimeLib at exact boundaries with proposer manipulation
  4.3  Build StorageSlotVerifier for assembly SSTORE operations
  4.4  Verify BitPackingLib gap bits (155-227) cannot be corrupted
  4.5  Test ETH forcing via selfdestruct on all 3 receive() contracts
  Depends on: Phase 1.2 (storage layouts)

Phase 5: Economic Composition Analysis
  5.1  Re-examine Vault share math with donation attack vectors
  5.2  Analyze Stonk sandwich potential
  5.3  Test circular affiliate reward accumulation
  5.4  Cross-contract EV exploitation (lootbox farming via cheap mints)
  Depends on: Phase 3 (precision results inform whether cheap mints are possible)

Phase 6: Synthesis + Halmos Verification
  6.1  Halmos: BitPackingLib setPacked preserves non-target fields
  6.2  Halmos: EntropyLib has no absorbing states (state=0 check)
  6.3  Halmos: JackpotBucketLib shares sum to pool
  6.4  Final synthesis of all findings
  Depends on: Phases 2-5 complete, Phase 1.4 (Halmos config)
```

### Phase Ordering Rationale

1. **Tooling first** because storage layout data is a prerequisite for composition and temporal analysis. Selector collision check is fast and eliminates/confirms a whole attack class immediately.
2. **Composition before precision** because composition bugs are the highest-severity zero-day class (can cause state corruption, fund loss). Precision bugs are typically Medium severity.
3. **Precision parallel with composition** because they are independent analysis streams with no data dependencies.
4. **Temporal after tooling** because temporal analysis requires storage layout knowledge and is moderate severity.
5. **Economic last** because it depends on precision analysis results (if minting can be free, economic exploitation is amplified).
6. **Halmos last** because symbolic verification is most valuable for confirming specific properties discovered in earlier phases.

## Scalability Considerations

| Concern | Current (1K fuzz runs) | Target (10K fuzz runs) | At 100K runs |
|---------|----------------------|----------------------|-------------|
| Test runtime | ~19s (Hardhat), ~30s (Forge) | ~5 min (Forge) | ~50 min, need CI split |
| False positive rate | Low | Low (same methodology) | Higher (more edge triggers) |
| Storage snapshots | Not tracked | 30 delegatecall sites tracked | Same, ghost overhead grows |
| Halmos timeout | 5 min per property | 5 min per property | Need loop bounds |

## Sources

- Contract source code analysis: all files in `contracts/` directory -- HIGH confidence
- Existing Foundry infrastructure: `test/fuzz/` directory -- HIGH confidence
- Storage layout: `DegenerusGameStorage.sol` -- packed slots 0-2, sequential slots 3+ -- HIGH confidence
- BitPackingLib: 8 named fields in bits 0-243, gap at 155-227 (73 bits) -- HIGH confidence
- Assembly operations: 6 sstore/sload in MintModule + JackpotModule (traitBurnTicket array pushes) -- HIGH confidence
- Unchecked blocks: 231 total across 27 files (JackpotModule: 40, MintModule: 15, BurnieCoinflip: 14 are heaviest) -- HIGH confidence
- Division operations: 222 across 21 files (LootboxModule: 39, JackpotModule: 27, DegeneretteModule: 24 are heaviest) -- HIGH confidence
- Timestamp usage: 14 block.timestamp references across 6 files -- HIGH confidence
- ETH transfer sites: 21 call/transfer operations across 8 files -- HIGH confidence
- Delegatecall sites: 30 in DegenerusGame.sol -- HIGH confidence
- Prior audit findings: 0 Critical, 0 High, 0 Medium across v1.0-v4.0 (10 independent blind agents) -- HIGH confidence
