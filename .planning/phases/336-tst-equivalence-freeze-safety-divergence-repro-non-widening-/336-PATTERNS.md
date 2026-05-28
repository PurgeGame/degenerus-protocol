# Phase 336: TST — Equivalence + Freeze-Safety + Divergence-Repro + Non-Widening Regression — Pattern Map

**Mapped:** 2026-05-28
**Files analyzed:** 6 (3 EXTENDED test files + 1 NEW test file + 1 NEW markdown ledger + 1 optional EXTENDED file for D-TST01-03)
**Analogs found:** 6 / 6 — every new/extended file maps 1:1 to an existing in-tree analog (no "no analog found" rows). The `vm.expectCall` cheatcode is brand-new to the test tree (zero existing usages) so the planner gets an explicit "first-introduction" pattern with no prior precedent to follow but a forge-std-stable surface.

---

## Hard Constraints Re-Surfaced From `336-CONTEXT.md` (apply to every plan)

| ID | Constraint | Where Enforced |
|----|-----------|----------------|
| D-TST04-04 | **ZERO `contracts/*.sol` mutation** — Phase 336 touches ONLY `test/` + `.planning/`. A 336 plan that proposes a contract edit triggers STOP + re-spec. | Every plan; `feedback_no_contract_commits` honored |
| D-TST01-01 | `test/fuzz/RngLockDeterminism.t.sol` is the **ROADMAP-LOCKED** TST-01 freeze-fuzz home. Do NOT author a parallel harness (e.g. `RngLockFreezeSafetyV50.t.sol`). | TST-01 freeze-leg plan |
| D-CC-02 | **Sequential-on-main, no-worktrees** — submodule + node_modules friction makes worktrees unusable. | Plan wave shape (all plans on `main`) |
| D-CC-01 | **Per-plan atomic commits.** NO single batched commit (only IMPL phases batch). | Every plan |
| D-CC-03 | Test-only commits: `autonomous: true`. **The final ledger commit** (TST-04 binding NAME-set-equality headline) = `autonomous: false` — USER gate. | TST-04 plan only |
| D-TST01-02 | Deep-fuzz proof gates under `FOUNDRY_PROFILE=deep`. Routine = default profile. | TST-01 freeze-leg plan |

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `test/fuzz/RngLockDeterminism.t.sol` *(EXTEND in place; ROADMAP-LOCKED)* | test (fuzz) | snapshot/perturb/revert byte-identity oracle | the SAME file `test/fuzz/RngLockDeterminism.t.sol:1839-1928` (`testFuzz_RngLockDeterminism_AutoBuyDuringLockSafe`) | exact (intra-file template) |
| `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` *(EXTEND in place)* | test (gas) | gas-measurement equivalence one-liner | the SAME file `test/gas/KeeperOpenBoxWorstCaseGas.t.sol:163-217` (`testPerBoxMarginalAmortizesFixedOverhead`) | exact (intra-file template) |
| `test/fuzz/AfKingSubscription.t.sol` *(EXTEND in place — TST-02 oracle home, planner's pick)* | test (fuzz) | `vm.expectCall(count: 0)` no-SLOAD oracle (request-response/log-capture) | the SAME file `test/fuzz/AfKingSubscription.t.sol:182-199` (`testNonCrossingPassHolderBuysWithoutRefresh` — the non-crossing scaffold to wrap with `vm.expectCall`) | exact (intra-file scaffold) |
| `test/fuzz/RngFreezeAndRemovalProofs.t.sol` *(POSSIBLE EXTEND for TST-01 D-TST01-03 dedicated equivalence/grant oracle — planner's pick)* | test (fuzz) | unit equivalence + view-purity assertion | the SAME file `test/fuzz/RngFreezeAndRemovalProofs.t.sol:442-476` (the two trivial `whalePassClaims +=` + `lazyPassHorizon` view tests that EXPLICITLY DEFER the deeper roundtrip to 336 per header lines 38-44) | role-match (existing trivial-side; planner extends with the deferred substance) |
| **NEW** `test/fuzz/MintModuleDivergenceAcrossSplit.t.sol` *(TST-03 file home; planner's pick per D-TST03-04)* | test (fuzz) | cross-path equality (snapshot/revertTo two-env OR before/after) on same-seed `processTicketBatch` | `test/fuzz/RngLockDeterminism.t.sol` snapshot/revert helpers + `test/fuzz/GameOverPathIsolation.t.sol:64-86` (the `vm.recordLogs` + `TraitsGenerated` event-capture + advance-to-game-over driver for exercising MintModule traits) | role-match (no MINTDIV-shaped analog exists — composes snapshot/revert from one file + Mint-driver from another) |
| **NEW** `test/REGRESSION-BASELINE-v50.md` *(TST-04 ledger; new markdown file)* | doc (ledger) | name-set-equality regression gate | `test/REGRESSION-BASELINE-v49.md` (§1 arithmetic + §2 42-by-NAME + §6 false-confidence guards FC1-FC4 — mirror verbatim per D-TST04-01) | exact (format model) |

> **Why `test/fuzz/AfKingSubscription.t.sol` is the preferred TST-02 home (over the 3 sibling AfKing test files):** the `testNonCrossingPassHolderBuysWithoutRefresh:182-199` test in that file is the EXACT non-crossing scaffold (deity-pass + `_subscribeTicketMode` + `_approveKeeper` + `_fundPool` + `vm.recordLogs` + `afKing.autoBuy(50)`) the D-TST02-02 `vm.expectCall(..., count: 0)` oracle wraps. The 3 alternatives (`AfKingFundingWaterfall.t.sol`, `AfKingConcurrency.t.sol`, `KeeperNonBrick.t.sol`) all carry crossing-tests but `AfKingSubscription` is the only one with the dedicated non-crossing setup helpers ready to call.

---

## Pattern Assignments

### `test/fuzz/RngLockDeterminism.t.sol` (test/fuzz, EXTEND; TST-01 freeze leg)

**Analog:** the SAME file, `testFuzz_RngLockDeterminism_AutoBuyDuringLockSafe` at lines 1839-1928. Add a parallel `testFuzz_RngLockDeterminism_ClaimWhalePassDuringLockSafe` mirroring this template's snapshot → perturb-in-window → deliver word → revert → baseline → assert byte-identity flow.

**Imports pattern** (lines 29-34):
```solidity
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {VRFHandler} from "./helpers/VRFHandler.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Vm} from "forge-std/Vm.sol";
```

**Setup pattern** (lines 62-67):
```solidity
function setUp() public {
    _deployProtocol();
    vm.warp(block.timestamp + 1 days);
    vrfHandler = new VRFHandler(mockVRF, game);
    mockVRF.fundSubscription(1, 100e18);
}
```

**Snapshot/revert helpers to REUSE VERBATIM** (lines 94-144) — do NOT re-author:
```solidity
function _readLootboxRngIndex() internal view returns (uint48) {
    return uint48(uint256(vm.load(address(game), bytes32(uint256(SLOT_LOOTBOX_RNG_INDEX)))));
}
function _lootboxRngWord(uint48 index) internal view returns (uint256) {
    bytes32 slot = keccak256(abi.encode(uint256(index), uint256(SLOT_LOOTBOX_RNG_WORD_BY_INDEX)));
    return uint256(vm.load(address(game), slot));
}
function _advanceToVrfRequestBoundary() internal returns (uint256 reqId) { ... }
function _deliverMockVrf(uint256 reqId, uint256 word) internal { ... }
function _snapshotPreLock() internal returns (uint256 snapshotId) { return vm.snapshot(); }
function _revertToPreLock(uint256 snapshotId) internal { vm.revertTo(snapshotId); }
function _assertVrfOutputByteIdentity(bytes32 perturbed, bytes32 baseline, string memory label) internal pure {
    assertEq(perturbed, baseline, label);
}
```

**Core template — snapshot/perturb/revert byte-identity** (lines 1839-1928 — the EXACT shape to mirror for the new claimWhalePass perturbation; key spine):
```solidity
function testFuzz_RngLockDeterminism_AutoBuyDuringLockSafe(uint256 seed) public {
    uint256 vrfWord = uint256(keccak256(abi.encode("tst01-autobuy-word", seed)));
    address buyer = makeAddr("tst01-autobuy-lootbox-buyer");
    vm.deal(buyer, 100 ether);

    _completeDay(0xDEAD0901);
    vm.warp(block.timestamp + 1 days);

    uint48 purchaseIndex = _readLootboxRngIndex();
    vm.prank(buyer);
    game.purchase{value: 1.01 ether}(
        buyer, 400, 1 ether, bytes32(0), MintPaymentKind.DirectEth
    );

    // ... (pre-lock state nudges; see line 1858-1867)

    uint256 preLockSnap = _snapshotPreLock();

    // ---- perturbed: keeper action fires inside the locked window ----
    game.advanceGame();
    uint256 reqId = mockVRF.lastRequestId();
    assertTrue(game.rngLocked(), "TST-01: rngLock must engage at the VRF boundary");
    assertTrue(reqId != 0, "TST-01: VRF request must be pending");
    assertEq(_lootboxRngWord(purchaseIndex), 0, "TST-01: per-index word must be 0 pre-VRF");

    _perturb(perturbSeed); // ← for the new test, add a cls (e.g. 11) for claimWhalePass

    _deliverMockVrf(reqId, vrfWord);
    uint256 perturbedWord = _lootboxRngWord(purchaseIndex);

    // ---- baseline: SAME word, NO perturbation ----
    _revertToPreLock(preLockSnap);
    game.advanceGame();
    uint256 baselineReqId = mockVRF.lastRequestId();
    _deliverMockVrf(baselineReqId, vrfWord);
    uint256 baselineWord = _lootboxRngWord(purchaseIndex);

    _assertVrfOutputByteIdentity(
        bytes32(perturbedWord), bytes32(baselineWord),
        "TST-01: claim perturbation must NOT alter the consumed per-index word (ADV-04 freeze)"
    );
}
```

**Perturbation library extension pattern** (lines 150-232) — add a new class for `claimWhalePass`. The 11-class library (`N_PERTURB_ACTIONS = 11`) is the precedent: classes 9 (doWork) and 10 (autoBuy(0)) were added for v49. For 336, add a NEW class (e.g. `cls == 11`) for `claimWhalePass`:
```solidity
// Existing pattern at lines 216-231 (cls 9 doWork / cls 10 autoBuy):
} else if (cls == 9) {
    vm.prank(actor);
    try afKing.doWork() {} catch { return; }
} else if (cls == 10) {
    vm.prank(actor);
    try afKing.autoBuy(0) {} catch { return; }
}
// NEW (336 D-TST01-02; bump N_PERTURB_ACTIONS to 12 if added):
// } else if (cls == 11) {
//     vm.prank(actor);
//     try game.claimWhalePass(claimantAddr) {} catch { return; }
// }
```

**Deep-fuzz gating mechanism** (D-TST01-02): NO test-side annotation needed. The `foundry.toml` `[profile.deep.fuzz]` / `[profile.deep.invariant]` blocks (lines 45-58) auto-engage when the user runs `FOUNDRY_PROFILE=deep forge test`. The new function inherits the same fuzz config from the contract, so a single `function testFuzz_*(uint256 seed)` signature suffices — the profile env var is the gate, not a Solidity annotation.

**Non-vacuity guard pattern** (lines 1914-1927) — the AutoBuy test has a CONTROL run that zeroes the perturbation source and proves the captured word would have DIFFERED if the perturbation weren't real. The new claim-test should mirror this defensively (assumption A3 in RESEARCH may need empirical validation):
```solidity
// ---- NON-VACUITY (B): a control run with the perturbation source zeroed MUST yield a DIFFERENT consumed word ----
_revertToPreLock(preLockSnap);
vm.store(address(game), bytes32(uint256(SLOT_TOTAL_FLIP_REVERSALS)), bytes32(uint256(0)));
// ... run baseline path again ...
assertTrue(
    controlWord != baselineWord,
    "TST-01 non-vacuity: the freeze proof must not pass vacuously"
);
```

---

### `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` (test/gas, EXTEND; TST-01 uniform-O(1) one-liner)

**Analog:** the SAME file, `testPerBoxMarginalAmortizesFixedOverhead` at lines 163-217. Add a parallel `testWhaleOpenerEqualsNonWhaleOpenerGas` mirroring the gas-bracketing idiom, but with TWO distinct openers (one whale-pass holder, one non-whale) and an `|Δ| ≤ tolerance` equivalence assertion.

**Imports pattern** (lines 4-6):
```solidity
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
```

**Setup pattern** (lines 68-77):
```solidity
function setUp() public {
    _deployProtocol();
    vm.warp(block.timestamp + 1 days);
    boxOwner = makeAddr("open_box_owner");
    cranker = makeAddr("open_box_cranker");
    vm.deal(boxOwner, 100_000 ether);
    vm.deal(cranker, 100_000 ether);
    vm.deal(address(game), 1_000_000 ether);
}
```

**Core gas-bracketing pattern** (lines 187-191 — the `gasleft()` measurement spine; mirror this twice for whale and non-whale):
```solidity
vm.prank(cranker);
uint256 gasBefore = gasleft();
game.autoOpen(nBoxes * 64);
uint256 totalGas = gasBefore - gasleft();
uint256 perBoxMarginal = totalGas / nBoxes;
```

**Box-enqueue + RNG-word inject helpers to REUSE** (lines 226-249):
```solidity
function _buyBox(address buyer, uint256 lootboxAmount) internal {
    vm.prank(buyer);
    game.purchase{value: lootboxAmount + 0.01 ether}(
        buyer, 400, lootboxAmount, bytes32(0), MintPaymentKind.DirectEth
    );
}
function _activeLootboxIndex() internal view returns (uint48) {
    uint256 packed = uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT))));
    return uint48(packed & 0xFFFFFFFFFFFF);
}
function _injectLootboxRngWord(uint48 index, uint256 rngWord) internal {
    bytes32 slot = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_RNG_WORD_SLOT)));
    vm.store(address(game), slot, bytes32(rngWord));
}
```

**TOLERANCE — empirical resolution pattern** (the RESEARCH §A1 + Pitfall): the D-TST01-04 SPEC suggests `|Δ| ≤ 500 gas`, but a cold-SSTORE `whalePassClaims[opener] += 1` write can cost ~22_100 gas (cold) vs ~5_000 (warm) — well above 500. Two valid resolutions; planner picks at execution:
1. **Widen tolerance** to ~25_000 gas (the worst-case cold SSTORE penalty).
2. **Pre-warm** the whale opener's `whalePassClaims` slot in setup so both openers face a warm SSTORE:
   ```solidity
   // Pre-warm to neutralize the cold-SSTORE asymmetry — both openers face a warm SSTORE.
   bytes32 whaleSlot = keccak256(abi.encode(whaleOpener, /* whalePassClaims root slot */));
   vm.store(address(game), whaleSlot, bytes32(uint256(0))); // touch slot to warm it
   ```
The planner picks one approach at first execution; A1 acknowledges this is LOW risk (caught at first run).

**Whale-pass boon-trigger helper** (NEW helper the planner needs to write — no in-tree analog beyond the `_grantDeityPass` shape at `AfKingSubscription.t.sol:398-403`):
```solidity
// Pre-seed the per-index RNG word to a value whose BOON_WHALE_PASS bit is set so the whale's
// box-open deterministically triggers the whalePassClaims[opener] += accumulator write.
// Mirror the existing _injectLootboxRngWord pattern (line 240-243) but with a word whose
// boon-bits include the whale-pass slot.
function _grantWhalePassBoonOnNextOpen(address opener) internal {
    // ... (planner picks the exact mechanism — vm.store on the per-index word with a known whale-bit) ...
}
```

**Logging pattern** (lines 213-216 — emit gas values via `log_named_uint` so the planner has the empirical numbers in the test log):
```solidity
emit log_named_uint("per_box_marginal_gas", perBoxMarginal);
emit log_named_uint("per_box_batch_total_gas", totalGas);
emit log_named_uint("single_box_total_ref_gas", SINGLE_BOX_TOTAL_REF_GAS);
```

---

### `test/fuzz/AfKingSubscription.t.sol` (test/fuzz, EXTEND; TST-02 D-TST02-02 no-pass-SLOAD oracle)

**Analog:** the SAME file, `testNonCrossingPassHolderBuysWithoutRefresh` at lines 182-199 — the exact non-crossing scaffold (deity-pass grant + ticket-mode subscribe + operator approval + pool funding) to wrap with `vm.expectCall(..., count: 0)`.

**Imports pattern** (lines 4-6):
```solidity
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
```

**Helpers to REUSE VERBATIM** — already in the file (lines 362-460):
```solidity
function _currentLevel() internal view returns (uint24) { return game.level(); }
function _subscribeTicketMode(address who, uint8 q) internal {
    vm.prank(who);
    afKing.subscribe(address(0), false, true, q, 0, address(0));
}
function _approveKeeper(address who) internal {
    vm.prank(who);
    game.setOperatorApproval(address(afKing), true);
}
function _fundPool(address who, uint256 amount) internal {
    vm.deal(address(this), amount);
    afKing.depositFor{value: amount}(who);
}
function _grantDeityPass(address who) internal {
    bytes32 slot = keccak256(abi.encode(who, uint256(9)));
    uint256 packed = uint256(vm.load(address(game), slot));
    packed |= (uint256(1) << 184);
    vm.store(address(game), slot, bytes32(packed));
}
```

**The closest analog scaffold** (lines 182-199 — copy the staging spine VERBATIM, replace the assertions with the `vm.expectCall(count: 0)` oracle):
```solidity
function testNonCrossingPassHolderBuysWithoutRefresh() public {
    address pass = makeAddr("nx_pass_holder");
    _grantDeityPass(pass); // horizon = uint24.max
    _subscribeTicketMode(pass, 1); // validThroughLevel = uint24.max (deity sentinel)
    _approveKeeper(pass);
    _fundPool(pass, 1 ether);
    // DO NOT force crossing — leave validThroughLevel at the sentinel so currentLevel <= horizon.

    vm.recordLogs();
    vm.prank(makeAddr("autoBuyer_nx"));
    afKing.autoBuy(50);

    // Non-crossing path: NO refresh event, NO eviction event for this sub.
    assertEq(_countEventFor(address(afKing), EXTENDED_FREE_SIG, pass), 0, "non-crossing: no refresh");
    assertEq(_countEventFor(address(afKing), SUB_EXPIRED_SIG, pass), 0, "non-crossing: no eviction");
    assertGt(_subscriberIndexOf(pass), 0, "non-crossing sub stays in set");
}
```

**The D-TST02-02 addition pattern** (the NEW test — first `vm.expectCall` in the test tree; precedent-setting):
```solidity
import {IGame} from "../../contracts/AfKing.sol"; // ← NEW import for the selector

function testNonCrossingPathPerformsZeroLazyPassHorizonSloads() public {
    address pass = makeAddr("nx_no_sload_holder");
    _grantDeityPass(pass);                 // horizon = uint24.max
    _subscribeTicketMode(pass, 1);         // validThroughLevel = uint24.max → non-crossing
    _approveKeeper(pass);
    _fundPool(pass, 1 ether);

    // ORDER STRICTLY MATTERS (RESEARCH Pitfall 1):
    //   (1) STAGE FIRST (above): no expectCall in scope while staging fires
    //   (2) vm.expectCall on the NEXT line
    //   (3) prank + autoBuy
    //   (4) test teardown auto-verifies the count
    vm.expectCall(
        address(game),                                          // IGame facade target
        abi.encodeWithSelector(IGame.lazyPassHorizon.selector), // selector — matches ANY (address) arg
        0                                                       // EXACTLY ZERO calls expected on non-crossing path
    );
    vm.prank(makeAddr("autoBuyer_no_sload_check"));
    afKing.autoBuy(50);
    // Cheatcode auto-verifies on test teardown — NO explicit assertEq required.
}
```

**`IGame` selector source** (`contracts/AfKing.sol:27-48` — the interface AfKing uses to call into the game facade; `lazyPassHorizon` is at line 40):
```solidity
interface IGame {
    // ... other selectors ...
    function lazyPassHorizon(address player) external view returns (uint24);
}
```

**Pitfall 1 (Cheatcode consumption-before-stage)** — ENFORCED ORDER:
```
1. Stage (grantDeity → subscribe → approve → fund)  ← all external calls happen here
2. vm.expectCall(..., 0)                            ← starts counting from THIS line
3. vm.prank(caller)
4. afKing.autoBuy(50)                                ← only call counted is the autoBuy + its internals
```

**Subject under test** — `contracts/AfKing.sol:627-647` (the ONLY external `lazyPassHorizon` call site, inside the `currentLevel > sub.validThroughLevel` crossing branch — non-crossing path takes the cheap stored-field compare on line 627 and never enters the block at line 628):
```solidity
if (currentLevel > sub.validThroughLevel) {
    uint24 h = GAME.lazyPassHorizon(player);  // ← the only external SLOAD on the hot path
    if (currentLevel <= h) {
        // REFRESH
        sub.validThroughLevel = uint32(h);
        emit SubscriptionExtendedFree(player, today);
        didWork = true;
    } else {
        // EVICT via tombstone-then-reclaim
        sub.dailyQuantity = 0;
        _removeFromSet(player);
        emit SubscriptionExpired(player, 1);
        ...
    }
}
```

---

### `test/fuzz/RngFreezeAndRemovalProofs.t.sol` (test/fuzz, POSSIBLE EXTEND; TST-01 D-TST01-03 equivalence/grant oracle home)

**Analog:** the SAME file's two trivial assertions at lines 442-476 (`testWhalePassClaimsWriteIsNonFrozenSlot` + `testLazyPassHorizonReadDoesNotPerturbFrozenSlots`). The file header at lines 32-46 EXPLICITLY DEFERS the deeper roundtrip equivalence to Phase 336 — this file is the natural home for the D-TST01-03 dedicated grant-correctness test (planner's pick).

**The deferral marker the planner should READ FIRST** (lines 38-46):
```solidity
// The DEEPER RNG-freeze fuzz of the deferred-claim path (the WhaleModule:1018
// `claimWhalePass` invariant under rngLock + the fuzzed roundtrip equivalence) is DEFERRED
// TO Phase 336 / TST-01 freeze leg per 335-CONTEXT.md D-IMPL-02. THIS file ships only the
// trivial assertions; the deeper proof is 336's job, not 335's.
```

**Existing trivial-side assertions to BUILD UPON** (lines 442-476):
```solidity
function testWhalePassClaimsWriteIsNonFrozenSlot() public view {
    string memory src = vm.readFile("contracts/modules/DegenerusGameLootboxModule.sol");
    assertGt(
        _countOccurrences(src, "whalePassClaims[player] +="),
        0,
        "WHALE-01: box-open O(1) `whalePassClaims[player] +=` write byte-present"
    );
}

function testLazyPassHorizonReadDoesNotPerturbFrozenSlots() public {
    address probe = makeAddr("freeze_probe");
    _grantDeityPass(probe);

    bytes32 mintPackedSlot = keccak256(abi.encode(probe, uint256(9)));
    bytes32 before_ = vm.load(address(game), mintPackedSlot);

    uint24 horizon = game.lazyPassHorizon(probe);

    bytes32 after_ = vm.load(address(game), mintPackedSlot);

    assertEq(horizon, type(uint24).max, "deity-bit holder: horizon == sentinel");
    assertEq(after_, before_, "lazyPassHorizon is a pure view: mintPacked_ slot UNCHANGED across the call");
}
```

**D-TST01-03 NEW oracle to add** (the deferred substance — the claim materializes `[currentLevel+1 .. currentLevel+100]` with `_applyWhalePassStats` applied at claim-time):

The new test stages a box-open that fires the O(1) `whalePassClaims[player] += 1` accumulator, then calls `game.claimWhalePass(player)`, then asserts:
1. **Grant window correctness**: the claim materialized future-window levels exactly `[currentLevel+1 .. currentLevel+100]` (per WHALE D-03 claim-time anchoring).
2. **Stats applied at claim** (D-04): `_applyWhalePassStats` fired at the same anchor.
3. **Pre-claim box-open writes ONLY the O(1) accumulator** (D-IMPL-01): no `mintPacked_` perturbation pre-claim.

The exact storage probes (which slots `claimWhalePass` mutates) are derived from `contracts/modules/DegenerusGameWhaleModule.sol:1018` (the materialization entrypoint) and `contracts/storage/DegenerusGameStorage.sol:1111` (`_applyWhalePassStats`). The planner picks the storage probes empirically at execution.

**Source-grep `_countOccurrences` helper pattern** — reuse this idiom for any source-level attestation (the helper already exists in the file):
```solidity
string memory src = vm.readFile("contracts/modules/DegenerusGameWhaleModule.sol");
assertGt(_countOccurrences(src, "_applyWhalePassStats"), 0, "stats-at-claim helper byte-present");
```

**Alternative home (planner's call per D-TST01-03):** if extending `RngFreezeAndRemovalProofs.t.sol` co-mingles the equivalence test with the freeze-proof file, the planner MAY instead author a NEW dedicated `test/fuzz/WhalePassClaimEquivalence.t.sol` (the closer-to-pure-equivalence home). RESEARCH §A4 leans toward in-file extension because the file already has the `_grantDeityPass` helper + the deferral marker; a NEW file means re-deriving helpers. Recommendation: **EXTEND in place** unless the new function count exceeds ~3.

---

### NEW `test/fuzz/MintModuleDivergenceAcrossSplit.t.sol` (TST-03 file home; planner's pick per D-TST03-04)

**Closest analogs (composes two — no MINTDIV-shaped analog exists in-tree):**
- `test/fuzz/RngLockDeterminism.t.sol:130-144` — `_snapshotPreLock` / `_revertToPreLock` / `vm.snapshot()` / `vm.revertTo()` two-env isolation pattern.
- `test/fuzz/GameOverPathIsolation.t.sol:30-86` — `vm.recordLogs()` + `TraitsGenerated` event-capture + the `_driveToGameOver`-style advance loop for exercising `processTicketBatch` via the daily/game-over path.

**Imports pattern** (mirror `test/fuzz/GameOverPathIsolation.t.sol:1-7` + the level-storage helper from `AfKingSubscription.t.sol:419-438` for any direct slot writes):
```solidity
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
```

**Setup pattern** (mirror `GameOverPathIsolation.t.sol:40-46`):
```solidity
function setUp() public {
    _deployProtocol();
    vm.warp(block.timestamp + 1 days);
    // ... player + funding ...
    mockVRF.fundSubscription(1, 100e18);
}
```

**LIVE TraitsGenerated event signature** (`contracts/storage/DegenerusGameStorage.sol:485-489`) — the 3-ARG form, NOT the v48-era 6-arg form:
```solidity
event TraitsGenerated(
    address indexed player,
    uint256 baseKey,
    uint32 take
);
// → topic-0 = keccak256("TraitsGenerated(address,uint256,uint32)")
```

**Pitfall 3 (v48-era 6-arg topic hash)** — the carried-forward red `GameOverPathIsolation.t.sol:31-32` still hardcodes the OLD signature:
```solidity
// WRONG (v48 carried-forward red):
bytes32 internal constant TOPIC_TRAITS_GENERATED =
    keccak256("TraitsGenerated(address,uint24,uint32,uint32,uint32,uint256)");
// CORRECT (live, v50):
bytes32 internal constant TOPIC_TRAITS_GENERATED =
    keccak256("TraitsGenerated(address,uint256,uint32)");
```

**Cross-path equality two-env pattern** (compose `vm.snapshot`/`revertTo` from `RngLockDeterminism.t.sol`):
```solidity
// Deterministic anchor per D-TST03-03: owed=300 at level L, warm budget 550, maxT=292.
// Cite the verdict by PATH (per D-TST03-03):
//   .planning/phases/334-spec-design-lock-mintdiv-reachability-proof-rngaudit-structu/334-MINTDIV01-REACHABILITY-VERDICT.md
function testMintDivCrossPathEquality_OwedSplitsAcrossSlices() public {
    uint24 lvl = 1;
    address player = makeAddr("mintdiv-300-player");

    _seedPlayerWithOwed(player, lvl, 300); // owed=300 at level L (test-side helper)

    uint256 snapId = vm.snapshot();

    // === Env A: drive processTicketBatch under natural budget slicing (split mid-player) ===
    _driveProcessTicketBatchUntilDone(lvl); // multiple narrow-slice calls
    bytes32 envADigest = _digestTraitBurnTicketForPlayer(player, lvl);

    vm.revertTo(snapId);

    // === Env B: differently-split processTicketBatch (same total owed, different slice shape) ===
    _seedPlayerWithOwed(player, lvl, 300);
    _driveProcessTicketBatchFractured(lvl, 3); // 3 slices
    bytes32 envBDigest = _digestTraitBurnTicketForPlayer(player, lvl);

    assertEq(envADigest, envBDigest,
        "TST-03 D-TST03-02: byte-identical trait derivation across budget-slice splits");
}
```

**Pitfall 5 (snapshot state pollution)** — between two envs, ALWAYS `vm.revertTo(snapId)` BEFORE re-staging Env B. The `RngLockDeterminism` helpers `_snapshotPreLock` / `_revertToPreLock` already model this; do NOT re-snapshot without reverting first.

**Boundary-fuzz overlay pattern** (D-TST03-01 — `owed ∈ [maxT+1, maxT+200]`, i.e. `[293, 492]`):
```solidity
function testFuzz_MintDiv_BoundaryOwedCrossPath(uint32 owed) public {
    vm.assume(owed >= 293 && owed <= 492); // forces split mid-player; maxT=292 warm
    // ... mirror the deterministic anchor flow with this fuzzed owed ...
}
```

**MintModule surfaces under test** (`contracts/modules/DegenerusGameMintModule.sol:671-733`):
```solidity
function processTicketBatch(uint24 lvl) external returns (bool finished) {
    // ... cursor + budget setup ...
    uint32 writesBudget = WRITES_BUDGET_SAFE;  // line 690 — 550 warm; 358 cold (65% scaling)
    // ... main loop ...
    while (idx < total && used < writesBudget) {
        (uint32 writesUsed, uint32 take, bool advance) = _processOneTicketEntry(
            queue[idx], lvl, owedMap, writesBudget - used, processed, entropy, idx
        );
        if (writesUsed == 0 && !advance) break;
        unchecked {
            used += writesUsed;
            if (advance) {
                ++idx;
                processed = 0;
            } else {
                // MINTDIV-02: align with processFutureTicketBatch:502 — advance
                // the within-player startIndex by the per-iter ticket count, not
                // by the gas-budget-derived writesUsed>>1 heuristic (which diverged
                // for take > 256 per 334-MINTDIV01-REACHABILITY-VERDICT).
                processed += take;            // ← line 720: THE INVARIANT TST-03 EMPIRICALLY VALIDATES
            }
        }
    }
}
```

**Test-side helper sketches** (planner authors; no exact analog — the closest existing storage-direct pattern is `AfKingSubscription._forceCrossingDue` at lines 420-438 which writes packed Sub slots):
```solidity
// (1) _seedPlayerWithOwed — write owedMap[player] = packed(owed, 0) via vm.store on the
//     ticketsOwedPacked[rk] mapping. ticketsOwedPacked maps uint24 → mapping(address => uint40).
// (2) _driveProcessTicketBatchUntilDone(lvl) — loop on game.processTicketBatch(lvl) until it
//     returns true (finished); each call uses one natural WRITES_BUDGET_SAFE slice.
// (3) _digestTraitBurnTicketForPlayer — vm.load over traitBurnTicket[level][traitId] for
//     traitId ∈ 0..255 and keccak256 the concatenation (the cross-env equality digest).
```

**Alternative TST-03 mechanic** (RESEARCH §A2 — simpler before/after on the same state if the snapshot/revert pollution gets tricky): the MINTDIV-02 alignment makes a multi-call advance equal the contiguous endpoint on the SAME state — so the test can be a before/after digest comparison with NO `vm.revertTo`. Planner picks at execution.

---

### NEW `test/REGRESSION-BASELINE-v50.md` (TST-04 v50 ledger; markdown file)

**Analog:** `test/REGRESSION-BASELINE-v49.md` — **mirror the §1 / §2 / §6 structure VERBATIM** with version + commit substituted. Per D-TST04-01, §2 FULLY RE-ENUMERATES all 42 names (NOT a v49-delta partial — set-equality requires the full enumeration).

**Headline form to MIRROR VERBATIM** (`test/REGRESSION-BASELINE-v49.md:17-24`; substitute the version + commit only):
```markdown
> **THE BINDING HEADLINE (by NAME, never a bare count):**
> at the v50 TST HEAD, the `forge test` failing set **==** the 42 v50.0 §2 enumerated union
> **BY NAME** — net-zero new regression. The gate is a strict NAME-set equality
> (`live failing set == the §2 enumerated 42-name union`), NOT a count match. A count-only
> gate would mask a real new regression that coincidentally offsets a 335 D-IMPL-02
> fixture-migration artifact. Both directions hold: zero failing name is OUTSIDE the 42
> union (no new red), and zero name in the 42 union is MISSING from the live set (no
> dropped baseline red).
```

**§1 arithmetic table starting point** (335-LOCAL-VERIFICATION confirms IMPL HEAD `e756a6f3` = 666/42/17):
```markdown
| Quantity | v50 IMPL HEAD `e756a6f3` | TST-HEAD delta (336-XX) | v50 TST HEAD |
|----------|--------------------------|-------------------------|--------------|
| `forge test` passed | 666 | + N new TST-01/02/03 proofs | **666 + N** |
| `forge test` failed | 42 | (per-plan churn — see §3) | **42** |
| `forge test` skipped | 17 | + 0 | **17** |
```

**§2 v50 42-name union — PRE-DERIVED IN RESEARCH §"Pre-derived v50 baseline set"** (the planner does NOT re-derive; copy from RESEARCH lines 597-643):
- Bucket A: 8 carried verbatim from v49 §2 (`A1..A8`).
- Bucket B: 34 = v49 B1..B8 + v49 B11..B13 (12 carried) + 2 NEW invariants (`invariant_noEthCreation` + `invariant_ghostAccountingNetPositive` on `test/fuzz/invariant/DegeneretteBet.inv.t.sol`); B9 OUT (deleted at 335-05), B10 OUT (flipped green at v50 IMPL).
- Bucket C: 0.
- **Total: 42 ✓**

**Pitfall 4 (B9/B10 disposition trap)** — DO NOT verbatim-copy v49 §2; apply the v50 deltas:
```
v50 §2 = {v49 §2 42-name union}
        − {B9 testRenewalExactlyAtCostFullBurn}              [DELETED at 335-05]
        − {B10 testFundingSourceVaultDoesNotInheritExemption} [GREEN at v50 IMPL]
        + {invariant_noEthCreation}                            [NEW B14]
        + {invariant_ghostAccountingNetPositive}               [NEW B15]
= 42 − 2 + 2 = 42 ✓
```

**§6 set-equality proof pattern to MIRROR** (`test/REGRESSION-BASELINE-v49.md:263-302` — the false-confidence guards FC1-FC4):
```markdown
A `forge test --json` parse built the live failing `(suite-basename, testName)` set and compared it to
the §2 enumerated 42-name v50 union by strict SET EQUALITY:
- `live failing set − v50 §2 union` (NEW regression OUTSIDE baseline) = ∅
- `v50 §2 union − live failing set` (dropped baseline red) = ∅
- `live failing set == v50 §2 union BY NAME` → TRUE.

### The false-confidence guards (mirrors v49 §6 FC1-FC4)
- **FC1 (loose count match masks a new regression):** mitigated — strict NAME-set EQUALITY.
- **FC2 (deletions/renames are unattributable churn):** mitigated — §3 enumerates v50 deltas BY NAME.
- **FC3 (passing ledger over a real regression):** mitigated — §1 STOPS with `## STOP — NEW REGRESSION
  OUTSIDE BASELINE` if any failing name is outside the 42 union.
- **FC4 (full tree never actually run, only --match-path):** mitigated — full `forge test` run, reconciled.
```

**§7 scope attestation pattern** (`test/REGRESSION-BASELINE-v49.md:346-358`):
```markdown
## 7. Scope attestation
- FULL `forge test` tree run (NOT `--match-path`) at the v50 TST HEAD → 666 + N passed / 42 failed / 17 skipped.
- **Zero `contracts/*.sol` modifications** this phase (D-TST04-04); audit subject FROZEN at v50 IMPL `e756a6f3`.
- The v50 deltas vs v49 §2 (B9 deleted, B10 green, invariant_noEthCreation + invariant_ghostAccountingNetPositive
  added) are fully attributable to 335 D-IMPL-02 / IMPL HEAD `e756a6f3`.
- TST-04 gate is NAME-set EQUALITY, not bare count.
```

**`autonomous: false` on this plan's commit** — per D-CC-03. The TST-04 ledger commit is the only USER-gated commit in 336.

---

## Shared Patterns

### Pattern S1 — `DeployProtocol` test fixture (every test contract inherits)

**Source:** `test/fuzz/helpers/DeployProtocol.sol`
**Apply to:** every NEW test contract in 336 (RngLockDeterminism extension, KeeperOpenBoxWorstCaseGas extension, AfKingSubscription extension, RngFreezeAndRemovalProofs extension, MintModuleDivergenceAcrossSplit NEW)

```solidity
import {DeployProtocol} from "./helpers/DeployProtocol.sol";

contract MyTest is DeployProtocol {
    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }
}
```

The fixture stands up `game` / `coin` / `dgnrs` / `mockVRF` / `vault` / `affiliate` / `admin` / `afKing` as contract members. All test files use this without exception.

### Pattern S2 — `vm.recordLogs` + topic-filter + `_drain` cache

**Source:** `test/fuzz/AfKingSubscription.t.sol:468-526`
**Apply to:** any test asserting event emission counts (TST-02 + TST-03 + TST-01 freeze leg if event-capture is used for trait digest)

```solidity
Vm.Log[] private _logsCache;
bool private _logsCacheReady;

function _drain() internal {
    if (!_logsCacheReady) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        delete _logsCache;
        for (uint256 i; i < logs.length; i++) _logsCache.push(logs[i]);
        _logsCacheReady = true;
    }
}

function _countEvent(address emitter, bytes32 sig) internal returns (uint256 count) {
    _drain();
    for (uint256 i; i < _logsCache.length; i++) {
        if (_logsCache[i].emitter == emitter
            && _logsCache[i].topics.length > 0
            && _logsCache[i].topics[0] == sig) count++;
    }
}
```

**Why drain-once cache:** `vm.getRecordedLogs()` is CONSUMING (empties the buffer). Multiple per-test assertions need this cache to avoid silently zero-ing after the first call.

### Pattern S3 — `vm.snapshot()` / `vm.revertTo()` two-env isolation

**Source:** `test/fuzz/RngLockDeterminism.t.sol:130-136`
**Apply to:** TST-03 cross-path equality test (the load-bearing primitive for two-env equality)

```solidity
uint256 snapId = vm.snapshot();
// Env A: run path A
vm.revertTo(snapId);
// Env B: run path B against the SAME pre-snapshot state
// Diff Env A vs Env B outputs
```

### Pattern S4 — Direct slot writes for state forging (mintPacked_ / Sub.validThroughLevel / level)

**Source:** `test/fuzz/AfKingSubscription.t.sol:398-438`
**Apply to:** TST-01 (whale-pass deity bit + per-index RNG word) + TST-03 (owed seeding) + TST-02 (deity bit for non-crossing horizon)

```solidity
// Pattern: keccak256(abi.encode(key, mappingRootSlot)) is the inner storage slot;
//          packed bit-fields use byte-offset masks (see _forceCrossingDue lines 419-438).
function _grantDeityPass(address who) internal {
    bytes32 slot = keccak256(abi.encode(who, uint256(9))); // mintPacked_ root slot
    uint256 packed = uint256(vm.load(address(game), slot));
    packed |= (uint256(1) << 184);  // HAS_DEITY_PASS_SHIFT
    vm.store(address(game), slot, bytes32(packed));
}
```

### Pattern S5 — `vm.readFile` source-grep attestations (only path `./contracts`)

**Source:** `test/fuzz/RngFreezeAndRemovalProofs.t.sol:443-450` + `foundry.toml:21`
**Apply to:** any structural source-byte-presence attestation (TST-01 D-TST01-03 may use this for `_applyWhalePassStats` presence)

```solidity
// foundry.toml grants read on ./contracts ONLY (no repo-root access).
string memory src = vm.readFile("contracts/modules/DegenerusGameLootboxModule.sol");
assertGt(_countOccurrences(src, "whalePassClaims[player] +="), 0, "byte-present");
```

### Pattern S6 — Per-plan atomic commit (D-CC-01 + v49 332 D-precedent)

**Source:** v49 332 precedent — see `MEMORY.md "v49-keeper-router-redesign" / 332 entry`
**Apply to:** every plan in 336 (no batched commits)

| Plan | Commits | `autonomous` flag |
|------|---------|-------------------|
| 336-01 TST-01 freeze leg (RngLockDeterminism extension) | 1 | `true` |
| 336-02 TST-01 uniform-O(1) gas equiv (KeeperOpenBoxWorstCaseGas extension) | 1 | `true` |
| 336-03 TST-01 equivalence/grant oracle (RngFreezeAndRemovalProofs extension OR new file) | 1 | `true` |
| 336-04 TST-02 no-pass-SLOAD oracle (AfKingSubscription extension) | 1 | `true` |
| 336-05 TST-03 cross-path equality (NEW file MintModuleDivergenceAcrossSplit.t.sol) | 1 | `true` |
| 336-06 TST-04 ledger + binding NAME-set-equality headline (NEW REGRESSION-BASELINE-v50.md) | 1 | **`false`** (USER gate) |

Plans 336-01 / 02 / 03 / 04 / 05 are commutative — order is flexible. 336-06 is the terminal gate.

---

## Pitfall → Plan Surface Map

| Pitfall (per RESEARCH §5) | Plan(s) Where It Fires | Mitigation Excerpt |
|---------------------------|------------------------|--------------------|
| **P1** `vm.expectCall` consumption-before-stage | 336-04 TST-02 oracle | Order STRICTLY: (1) stage → (2) `vm.expectCall` → (3) `vm.prank` → (4) `autoBuy`. Nothing between (2) and (4). |
| **P2** Fixture-migration artifact masquerading as v50 regression | 336-04 (touches `AfKingSubscription.t.sol`) + 336-06 TST-04 | D-IMPL-03 row 1 — fixture artifacts close IN-PLAN; D-TST04-04 — STOP-and-re-spec on a genuine v50 contract regression. |
| **P3** `TraitsGenerated` 6-arg signature drift (v48-era) | 336-05 TST-03 | Use `keccak256("TraitsGenerated(address,uint256,uint32)")` — the LIVE 3-arg form at `DegenerusGameStorage.sol:485-489`. |
| **P4** v49 B9/B10 carried-forward trap | 336-06 TST-04 ledger | RESEARCH pre-derives the 42-name v50 set: B9 OUT (deleted 335-05), B10 OUT (green v50 IMPL), 2 NEW invariants IN. Do NOT verbatim-copy v49 §2. |
| **P5** Snapshot state pollution across two envs | 336-05 TST-03 + 336-01 TST-01 freeze leg | Always `vm.revertTo(snapId)` BEFORE re-staging the second env. Mirror `_snapshotPreLock`/`_revertToPreLock` helpers. |

---

## No Analog Found

**None.** Every new/extended file has a concrete in-tree analog (often the same file). The only "new" primitive (`vm.expectCall`) is forge-std-stable; no project-local precedent exists but the cheatcode is documented and well-understood — RESEARCH §"Pattern 2" provides the verified usage shape.

---

## Metadata

**Analog search scope:**
- `test/fuzz/` (54 `.t.sol` files inventoried)
- `test/gas/` (KeeperOpenBoxWorstCaseGas + sibling Keeper gas files)
- `test/REGRESSION-BASELINE-v49.md` (ledger format model)
- `contracts/AfKing.sol` + `contracts/DegenerusGame.sol` + `contracts/modules/DegenerusGameMintModule.sol` + `contracts/storage/DegenerusGameStorage.sol` (source for selector / event signature / line-cited surfaces under test)
- `foundry.toml` (deep-profile gate)

**Files scanned:** ~60 (53 fuzz test files + 4 gas test files + 4 contracts + 1 foundry config + 1 v49 ledger)

**Pattern extraction date:** 2026-05-28

**Verification posture:** every cited `file:line` re-attested against the live working tree at FROZEN audit subject `e756a6f3` via Read/Grep this session. The `vm.expectCall` zero-existing-usages claim (RESEARCH §"Summary" finding 1) re-verified by `grep -rn "vm.expectCall" test/` returning empty.

---

*Phase 336 pattern map artifact. Every new/extended file → closest existing analog with verbatim code excerpts the executor copy-adapts.*
