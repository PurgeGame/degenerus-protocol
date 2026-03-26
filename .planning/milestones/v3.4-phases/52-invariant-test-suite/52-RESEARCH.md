# Phase 52: Invariant Test Suite - Research

**Researched:** 2026-03-21
**Domain:** Foundry stateful fuzz / invariant testing for Solidity 0.8.34
**Confidence:** HIGH

## Summary

Phase 52 requires writing three Foundry fuzz invariant tests proving safety properties identified in Phases 50 and 51: (1) skim conservation -- nextPool + futurePool + yieldAccumulator is constant, (2) take cap -- skim take never exceeds 80% of nextPool, and (3) redemption lootbox split -- direct ETH + lootbox ETH sums to total rolled ETH for every resolution.

The project already has comprehensive test infrastructure. The skim harness (`SkimHarness` in `test/fuzz/FuturepoolSkim.t.sol`) exposes `_applyTimeBasedFutureTake` and all pool state, with two existing fuzz tests that already assert conservation and take cap (`testFuzz_conservation` and `testFuzz_G2_takeCapped`). INV-01 and INV-02 can extend this suite with minimal new code. For INV-03, the existing `RedemptionInvariants.inv.t.sol` with its `RedemptionHandler` and `DeployProtocol` base provides the full-protocol deployment needed for the redemption lootbox split invariant.

**Primary recommendation:** INV-01 and INV-02 should extend the existing `FuturepoolSkimTest` using property-based fuzz tests (same pattern as `testFuzz_conservation` and `testFuzz_G2_takeCapped`). INV-03 requires either extending the existing `RedemptionHandler` with ghost tracking of the 50/50 split or adding a dedicated unit-level fuzz test that exercises `claimRedemption` through the handler lifecycle.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| INV-01 | Fuzz invariant: skim conservation holds across random inputs | Existing `testFuzz_conservation` already proves this with 1000 fuzz runs. Extend to invariant-style or confirm existing test satisfies requirement. The algebraic proof in 50-02-SUMMARY already establishes conservation holds for ALL inputs via T+I cancellation. |
| INV-02 | Fuzz invariant: take never exceeds 80% of nextPool | Existing `testFuzz_G2_takeCapped` already proves this with 1000 fuzz runs. The take cap is enforced by explicit `if (take > maxTake) take = maxTake` at line 1049. Extend to invariant-style or confirm existing test satisfies requirement. |
| INV-03 | Fuzz invariant: redemption lootbox split sums to total rolled ETH | The algebraic proof `floor(x/2) + (x - floor(x/2)) = x` was proven in 51-01. Needs a fuzz test that exercises the full claim path and verifies `ethDirect + lootboxEth == totalRolledEth` for randomized inputs. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Foundry (forge) | 1.5.1-stable | Fuzz + invariant testing framework | Already installed and configured in project |
| forge-std | (bundled) | Test base contract, assertions, vm cheats | Standard Foundry test library, already in lib/ |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| DeployProtocol.sol | (project) | Full 23-contract protocol deployment for invariant tests | INV-03 (needs full protocol for cross-contract claim path) |
| RedemptionHandler.sol | (project) | Multi-actor burn-resolve-claim lifecycle handler | INV-03 (extend with split tracking ghosts) |
| VRFHandler.sol | (project) | VRF fulfillment handler for driving state transitions | INV-03 (needed to resolve periods for claims) |
| SkimHarness | (project) | Exposer contract for `_applyTimeBasedFutureTake` internal | INV-01, INV-02 (direct function-level fuzz testing) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Extending FuturepoolSkimTest with new fuzz tests | Stateful invariant via handler contract | The existing fuzz test pattern is simpler and sufficient for INV-01/INV-02 since the skim function is pure (no cross-contract state). Handler-based invariant testing adds complexity with no benefit for a single function. |
| Extending RedemptionHandler | New standalone handler | Existing handler already drives the full lifecycle. Extending it with ghost variables for split tracking is less work and reuses battle-tested infrastructure. |

## Architecture Patterns

### Existing Test Organization
```
test/fuzz/
  FuturepoolSkim.t.sol        # 22 tests (unit + fuzz) for skim pipeline
  invariant/
    RedemptionInvariants.inv.t.sol  # 7+1 invariants for redemption lifecycle
    EthSolvency.inv.t.sol           # ETH solvency invariants
    ...
  handlers/
    RedemptionHandler.sol      # Multi-actor handler for redemption
  helpers/
    DeployProtocol.sol         # Full protocol deployment base
    VRFHandler.sol             # VRF fulfillment helper
```

### Pattern 1: Property-Based Fuzz Tests (INV-01, INV-02)
**What:** Single-function fuzz tests with `testFuzz_` prefix that take randomized inputs and assert a property.
**When to use:** Testing properties of a single function (or isolated subsystem) that can be called directly via a harness.
**Example (existing, from FuturepoolSkim.t.sol):**
```solidity
function testFuzz_conservation(
    uint128 nextPool,
    uint128 futurePool,
    uint24 lvl,
    uint128 lastPoolRaw,
    uint48 elapsedRaw,
    uint256 rngWord
) public {
    nextPool = uint128(bound(nextPool, 1 ether, 10_000 ether));
    futurePool = uint128(bound(futurePool, 0, 50_000 ether));
    lvl = uint24(bound(lvl, 1, 200));
    uint256 lastPool = bound(lastPoolRaw, 0.01 ether, 10_000 ether);
    uint48 elapsed = uint48(bound(elapsedRaw, 0, 120 days));

    (uint128 nextAfter, uint128 futureAfter, uint256 yieldAfter) =
        _runSkim(nextPool, futurePool, lvl, lastPool, elapsed, rngWord);

    _assertConservation(nextPool, futurePool, nextAfter, futureAfter, yieldAfter);
}
```

### Pattern 2: Stateful Invariant Tests (INV-03)
**What:** Handler-based invariant tests where the fuzzer calls random handler actions and invariants are checked after each call sequence.
**When to use:** Testing multi-step lifecycle properties across multiple contracts (burn -> resolve -> claim).
**Example (existing, from RedemptionInvariants.inv.t.sol):**
```solidity
contract RedemptionInvariants is DeployProtocol {
    RedemptionHandler public handler;
    VRFHandler public vrfHandler;

    function setUp() public {
        _deployProtocol();
        handler = new RedemptionHandler(sdgnrs, game, mockVRF, coin, 5);
        vrfHandler = new VRFHandler(mockVRF, game);
        targetContract(address(handler));
        targetContract(address(vrfHandler));
    }

    function invariant_someProperty() public view {
        // Check property using handler ghost variables
        assertEq(handler.ghost_someCounter(), 0, "invariant violated");
    }
}
```

### Pattern 3: Ghost Variable Tracking
**What:** Handler contracts maintain shadow state (`ghost_` prefixed variables) that track cumulative values the fuzzer cannot observe from on-chain state alone.
**When to use:** Verifying aggregate properties (total ETH claimed, total burned) that require tracking across multiple calls.
**Key insight:** The existing RedemptionHandler already tracks `ghost_totalEthClaimed`, `ghost_totalBurnieClaimed`, etc. INV-03 needs new ghost variables for tracking the ethDirect vs lootboxEth split.

### Anti-Patterns to Avoid
- **Testing already-proven algebraic identities:** `floor(x/2) + (x - floor(x/2)) = x` is proven for ALL integers. A fuzz test cannot add confidence beyond the proof. The value of INV-03 is in testing the full lifecycle (burn -> resolve -> claim) where the split is embedded, not the arithmetic identity itself.
- **Overly complex harnesses:** The skim pipeline is a pure function -- no need for stateful invariant testing with handlers. Property-based fuzz tests are simpler and run faster.
- **Unbounded inputs without `bound()`:** Always constrain fuzz inputs to realistic ranges to avoid reverts that waste fuzzer budget.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Full protocol deployment | Manual contract-by-contract deployment | `DeployProtocol._deployProtocol()` | CREATE nonce ordering must match patched ContractAddresses; `DeployProtocol` handles this correctly |
| VRF fulfillment orchestration | Manual reqId tracking and fulfillment | `VRFHandler.fulfillVrf()` | Already handles pending request detection, duplicate fulfillment prevention |
| Actor management | Manual address generation and setup | `RedemptionHandler` actor framework with `useActor` modifier | Handles seeding actors with sDGNRS and ETH, bounded actor selection |
| sDGNRS burn lifecycle | Direct burn calls | `RedemptionHandler.action_burn()` | Handles 50% supply cap pre-check, RNG lock detection, gameOver guard, balance bounding |

## Common Pitfalls

### Pitfall 1: INV-01/INV-02 Already Exist in Substance
**What goes wrong:** Writing new invariant tests that duplicate the existing `testFuzz_conservation` and `testFuzz_G2_takeCapped` without adding value.
**Why it happens:** The requirement says "fuzz invariant" which suggests stateful invariant testing, but the existing fuzz tests already cover the properties with 1000 runs across randomized inputs.
**How to avoid:** Either (a) acknowledge the existing fuzz tests satisfy the requirement and add minimal wrapper tests with explicit INV-01/INV-02 naming, or (b) extend with additional edge cases from Phase 50 findings (level 1 with lastPool=0, extreme stall escalation, etc.).
**Warning signs:** Creating a complex handler for the skim pipeline when `SkimHarness` already exposes everything needed.

### Pitfall 2: RedemptionHandler Ghost Variables for Split Tracking
**What goes wrong:** The existing `RedemptionHandler.action_claim()` does not track `ethDirect` and `lootboxEth` separately -- it only tracks total ETH claimed.
**Why it happens:** The original v3.3 invariants (INV-01 through INV-07) focused on solvency, double-claim, and period mechanics, not the 50/50 split.
**How to avoid:** Extend `RedemptionHandler` or create a `RedemptionSplitHandler` that adds ghost variables tracking `ghost_totalEthDirect` and `ghost_totalLootboxEth`, then verify `ghost_totalEthDirect + ghost_totalLootboxEth == ghost_totalRolledEth` in an invariant.
**Warning signs:** Trying to read `ethDirect` and `lootboxEth` from on-chain state after the claim -- these are local variables that exist only during the transaction.

### Pitfall 3: INV-03 Split Is Not Observable On-Chain Post-Claim
**What goes wrong:** The 50/50 split (lines 592-594 of StakedDegenerusStonk.sol) creates two local variables `ethDirect` and `lootboxEth`. After the transaction completes, these are gone. You cannot assert the split by reading contract state.
**Why it happens:** The split is an intermediate computation, not stored state.
**How to avoid:** Two approaches: (a) Add event-based tracking -- the `RedemptionClaimed` event (line 632) already emits `ethDirect` and `lootboxEth` as parameters. Parse the event log in the handler. (b) Use a fuzz test that calls a harness contract exposing the split computation as a pure function.
**Warning signs:** Trying to read storage after `claimRedemption()` to verify the split.

### Pitfall 4: REDM-06-A Underflow in resolveRedemptionLootbox
**What goes wrong:** The unchecked `claimableWinnings[SDGNRS] -= amount` at DegenerusGame.sol:1811 can underflow if prior claims drain sDGNRS's claimable balance.
**Why it happens:** The lootbox resolution debits from sDGNRS's claimable via unchecked subtraction -- a MEDIUM finding from Phase 51.
**How to avoid:** The invariant test for INV-03 should be designed to survive this edge case (e.g., using `fail_on_revert = false` in the invariant config, which is already the default). The split invariant itself is about `ethDirect + lootboxEth == totalRolledEth`, which is an arithmetic identity that holds regardless of the downstream lootbox resolution.
**Warning signs:** INV-03 tests reverting due to the unchecked subtraction in `resolveRedemptionLootbox`, which is a known MEDIUM finding but not what INV-03 is testing.

### Pitfall 5: FuturepoolSkim.t.sol Uses SkimHarness, Not Full Protocol
**What goes wrong:** Trying to add full-protocol invariant tests to FuturepoolSkim.t.sol.
**Why it happens:** Confusion between the two test patterns -- `FuturepoolSkim.t.sol` uses a lightweight `SkimHarness` that only instantiates `DegenerusGameAdvanceModule`, while full-protocol tests use `DeployProtocol`.
**How to avoid:** Keep INV-01 and INV-02 in `FuturepoolSkim.t.sol` using the `SkimHarness` pattern. Only INV-03 needs full-protocol deployment.
**Warning signs:** Attempting to call `game.claimRedemption()` from a `SkimHarness`-based test.

### Pitfall 6: Foundry Invariant Test Config
**What goes wrong:** Invariant tests timing out or not providing meaningful coverage.
**Why it happens:** Default invariant config is `runs=256, depth=128`. For INV-01/INV-02 using property-based fuzz tests, the fuzz config (`runs=1000`) applies instead.
**How to avoid:** The existing `foundry.toml` already has appropriate settings. Property-based fuzz tests (`testFuzz_*`) use `[fuzz]` settings (1000 runs). Stateful invariant tests (`invariant_*`) use `[invariant]` settings (256 runs, depth 128). For deeper testing, use `FOUNDRY_PROFILE=deep forge test`.
**Warning signs:** INV-03 timing out because the full protocol deployment is expensive. Monitor gas costs.

## Code Examples

### INV-01: Skim Conservation Fuzz Test (extends existing)

The existing `testFuzz_conservation` in `FuturepoolSkim.t.sol` already asserts:
```solidity
// Source: test/fuzz/FuturepoolSkim.t.sol:404-422
function testFuzz_conservation(
    uint128 nextPool, uint128 futurePool, uint24 lvl,
    uint128 lastPoolRaw, uint48 elapsedRaw, uint256 rngWord
) public {
    // ... bounds ...
    (uint128 nextAfter, uint128 futureAfter, uint256 yieldAfter) =
        _runSkim(nextPool, futurePool, lvl, lastPool, elapsed, rngWord);
    _assertConservation(nextPool, futurePool, nextAfter, futureAfter, yieldAfter);
}
```

Where `_assertConservation` checks:
```solidity
// Source: test/fuzz/FuturepoolSkim.t.sol:87-99
assertEq(
    uint256(nextAfter) + uint256(futureAfter) + yieldAfter,
    uint256(nextBefore) + uint256(futureBefore),
    "conservation: total ETH must be preserved"
);
```

This exactly matches the INV-01 requirement. The test runs 1000 fuzz iterations.

### INV-02: Take Cap Fuzz Test (extends existing)

The existing `testFuzz_G2_takeCapped` already asserts:
```solidity
// Source: test/fuzz/FuturepoolSkim.t.sol:262-285
function testFuzz_G2_takeCapped(
    uint128 nextPool, uint128 futurePool, uint24 lvl,
    uint128 lastPoolRaw, uint48 elapsedRaw, uint256 rngWord
) public {
    // ... bounds ...
    uint256 take = uint256(futureAfter) - uint256(futurePool);
    uint256 maxTake = uint256(nextPool) * NEXT_TO_FUTURE_BPS_MAX / 10_000;
    assertTrue(take <= maxTake, "take must respect 80% cap");
    assertTrue(uint256(nextAfter) + yieldAfter <= uint256(nextPool), "next can only decrease");
}
```

This exactly matches the INV-02 requirement.

### INV-03: Redemption Lootbox Split Invariant (new)

The split logic from StakedDegenerusStonk.sol:
```solidity
// Source: contracts/StakedDegenerusStonk.sol:584-595
uint256 totalRolledEth = (claim.ethValueOwed * roll) / 100;
bool isGameOver = game.gameOver();
uint256 ethDirect;
uint256 lootboxEth;
if (isGameOver) {
    ethDirect = totalRolledEth;
} else {
    ethDirect = totalRolledEth / 2;
    lootboxEth = totalRolledEth - ethDirect;
}
```

The `RedemptionClaimed` event emits these values:
```solidity
// Source: contracts/StakedDegenerusStonk.sol:632
emit RedemptionClaimed(player, roll, flipResolved, ethDirect, burniePayout, lootboxEth);
```

The handler can capture this event to track the split. Alternatively, since the split is a pure arithmetic identity, a simpler approach is a property-based fuzz test that replicates the split computation:
```solidity
function testFuzz_INV03_splitConservation(
    uint96 ethValueOwed,
    uint16 rollRaw,
    bool isGameOver
) public pure {
    ethValueOwed = uint96(bound(ethValueOwed, 1, MAX_DAILY_REDEMPTION_EV));
    uint16 roll = uint16(bound(rollRaw, 25, 175));

    uint256 totalRolledEth = (uint256(ethValueOwed) * roll) / 100;

    uint256 ethDirect;
    uint256 lootboxEth;
    if (isGameOver) {
        ethDirect = totalRolledEth;
    } else {
        ethDirect = totalRolledEth / 2;
        lootboxEth = totalRolledEth - ethDirect;
    }

    assertEq(ethDirect + lootboxEth, totalRolledEth, "INV-03: split must sum to total");
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `testFuzz_*` only (stateless) | `invariant_*` with handlers (stateful) | Foundry v0.2+ | Multi-step lifecycle testing possible |
| Manual VRF fulfillment | VRFHandler abstraction | v3.3 (Phase 45) | Reusable VRF handling across all invariant tests |
| Direct protocol calls | Handler-mediated bounded calls | v3.3 (Phase 45) | Better fuzzer coverage with `fail_on_revert=false` |

## Open Questions

1. **Should INV-01 and INV-02 be new tests or should existing tests satisfy the requirement?**
   - What we know: `testFuzz_conservation` and `testFuzz_G2_takeCapped` already test exactly these properties with 1000 fuzz runs. They are in `FuturepoolSkim.t.sol` and pass.
   - What's unclear: Whether the requirement mandates NEW tests or whether existing coverage satisfies INV-01/INV-02.
   - Recommendation: Add explicitly-named `testFuzz_INV01_conservation` and `testFuzz_INV02_takeCap` tests that either wrap or extend the existing tests, ensuring traceability. This adds minimal code while clearly mapping to requirements. Optionally add edge cases from Phase 50 findings (level 1 with 50 ether bootstrap, extreme R=50 ratio).

2. **INV-03: Pure arithmetic test vs full lifecycle test?**
   - What we know: The split `floor(x/2) + (x - floor(x/2)) = x` is an algebraic identity proven for ALL integers. A fuzz test of the arithmetic alone adds no confidence.
   - What's unclear: Whether INV-03 requires testing just the split computation or the full claim lifecycle (burn -> resolve period -> claim -> verify split).
   - Recommendation: Do both -- a simple arithmetic fuzz test for the split identity (cheap, fast, high confidence), PLUS verify in the existing `RedemptionInvariants` suite that `ethDirect + lootboxEth == totalRolledEth` for every claim via ghost variable tracking.

3. **REDM-06-A interaction with INV-03**
   - What we know: The unchecked subtraction at DegenerusGame.sol:1811 can underflow. This is a MEDIUM finding from Phase 51.
   - What's unclear: Whether the underflow can cause `resolveRedemptionLootbox` to revert (preventing claim) or corrupt state in a way that affects the split invariant.
   - Recommendation: The split invariant is about `ethDirect + lootboxEth == totalRolledEth`, which is computed BEFORE the lootbox resolution call. The REDM-06-A underflow occurs INSIDE `resolveRedemptionLootbox` which is called AFTER the split. So the split invariant is independent of REDM-06-A. Document this explicitly.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry forge 1.5.1-stable |
| Config file | `foundry.toml` |
| Quick run command | `forge test --match-contract FuturepoolSkimTest -vv` |
| Full suite command | `forge test --match-path "test/fuzz/*" -vv` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INV-01 | Skim conservation: N+F+Y constant | fuzz (property) | `forge test --match-test "testFuzz_INV01" -vv` | Existing `testFuzz_conservation` covers this; new named test extends |
| INV-02 | Take cap: take <= 80% nextPool | fuzz (property) | `forge test --match-test "testFuzz_INV02" -vv` | Existing `testFuzz_G2_takeCapped` covers this; new named test extends |
| INV-03 | Split: ethDirect + lootboxEth == totalRolledEth | fuzz (property) + invariant (lifecycle) | `forge test --match-test "testFuzz_INV03" -vv` | New test needed |

### Sampling Rate
- **Per task commit:** `forge test --match-contract FuturepoolSkimTest -vv && forge test --match-contract RedemptionInvariants -vv`
- **Per wave merge:** `forge test --match-path "test/fuzz/*" -vv`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/fuzz/FuturepoolSkim.t.sol` -- add `testFuzz_INV01_conservation` and `testFuzz_INV02_takeCap` (named tests mapping to requirements)
- [ ] `test/fuzz/FuturepoolSkim.t.sol` or new file -- add `testFuzz_INV03_splitConservation` (arithmetic fuzz test for 50/50 split)
- [ ] Optionally extend `RedemptionHandler` with `ghost_totalEthDirect` and `ghost_totalLootboxEth` for lifecycle-level split verification

*No framework install needed -- Foundry already configured.*

## Sources

### Primary (HIGH confidence)
- `test/fuzz/FuturepoolSkim.t.sol` -- existing 22-test fuzz suite with SkimHarness, conservation and take cap fuzz tests
- `test/fuzz/invariant/RedemptionInvariants.inv.t.sol` -- existing 7+1 invariant tests with RedemptionHandler
- `test/fuzz/handlers/RedemptionHandler.sol` -- multi-actor handler with ghost variable tracking
- `test/fuzz/helpers/DeployProtocol.sol` -- full 23-contract protocol deployment
- `contracts/modules/DegenerusGameAdvanceModule.sol:985-1055` -- `_applyTimeBasedFutureTake` function
- `contracts/StakedDegenerusStonk.sol:571-636` -- `claimRedemption` function with 50/50 split
- `.planning/phases/50-skim-redesign-audit/50-02-conservation-insurance.md` -- algebraic ETH conservation proof
- `.planning/phases/51-redemption-lootbox-audit/51-01-split-routing-findings.md` -- algebraic 50/50 split proof
- `foundry.toml` -- fuzz config (1000 runs) and invariant config (256 runs, depth 128)

### Secondary (MEDIUM confidence)
- [Foundry invariant testing docs](https://getfoundry.sh/forge/invariant-testing) -- handler patterns, targetContract usage, ghost variables
- [RareSkills invariant testing guide](https://rareskills.io/post/invariant-testing-solidity) -- practical patterns for Foundry invariant tests

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Foundry already installed, configured, and has 22+ existing tests. No new dependencies needed.
- Architecture: HIGH - Existing test infrastructure (SkimHarness, RedemptionHandler, DeployProtocol) covers all three invariant requirements. Patterns are proven by existing passing tests.
- Pitfalls: HIGH - All pitfalls identified from direct code reading and Phase 50/51 findings. REDM-06-A interaction with INV-03 analyzed and confirmed independent.

**Research date:** 2026-03-21
**Valid until:** 2026-04-21 (stable -- no external dependencies, project-internal tests only)
