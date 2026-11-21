// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {TicketGasHarness} from "../repro/JackpotTicketAwardChunks.t.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as Bounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Coinflip} from "../../contracts/Coinflip.sol";
import {IDegenerusGameJackpotModule, IDegenerusGameWhaleModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {GlamsterdamReprice} from "../helpers/GlamsterdamReprice.sol";
import {MinerloopGasProbe} from "../helpers/MinerloopGasProbe.sol";
import {ProfileModules} from "../helpers/ProfileModules.sol";
import {Vm, VmSafe} from "forge-std/Vm.sol";

/// @dev TicketGasHarness only seeds storage here. The measured entry delegatecalls the deployed jackpot
///      shell at GAME_JACKPOT_MODULE (etched by ProfileModules.installGame) in the harness storage, the way
///      the Game dispatches runDailyJackpot, so the bytecode measured is the deployed one rather than the
///      raw module compiled into the harness.
contract DeployedJackpotHost is TicketGasHarness {
    function runDeployedDailyJackpot(bool inJackpot, uint24 lvl, uint256 word, uint256 allowance)
        external returns (MineFlipGas.Result memory)
    {
        (bool ok, bytes memory data) = ContractAddresses.GAME_JACKPOT_MODULE.delegatecall(
            abi.encodeWithSelector(IDegenerusGameJackpotModule.runDailyJackpot.selector, inJackpot, lvl, word, allowance)
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        return abi.decode(data, (MineFlipGas.Result));
    }

    function runDeployedEarlyBird(uint256 word, uint256 allowance) external returns (MineFlipGas.Result memory) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_JACKPOT_MODULE.delegatecall(
            abi.encodeWithSelector(IDegenerusGameJackpotModule.runEarlyBirdTickets.selector, word, allowance)
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        return abi.decode(data, (MineFlipGas.Result));
    }

    /// @dev One ticket-leg pass recipient, delegated to the deployed whale shell as `_awardWhalePass` does.
    function awardDeployedPass(uint24 lvl, uint8 trait, uint256 halfPasses, uint256 word) external {
        (bool ok, bytes memory data) = ContractAddresses.GAME_WHALE_MODULE.delegatecall(
            abi.encodeWithSelector(IDegenerusGameWhaleModule.awardWhalePass_g201599.selector, lvl, trait, halfPasses, word)
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
    }

    /// @dev A day with no leg record, budget field, yield accumulator or board word written yet.
    function primeFreshDay(uint24 lvl, bool jackpotPhase) external {
        level = lvl;
        dailyIdx = 101;
        rngRequestDay = 101;
        rngLockedFlag = true;
        if (jackpotPhase) {
            jackpotPhaseFlag = true;
            _setCurrentPrizePool(10_000 ether);
        }
        _setPrizePools(0, 5_000 ether);
    }

    /// @dev Fields a live game has already written: the budget field's retained bit, an earlier
    ///      day's board in this day's slot, and outstanding winnings in the claimable pool.
    function primeLiveFields(uint256 word) external {
        dailyTicketBudgetsPacked = DAILY_TICKET_BUDGET_RETAINED;
        dailyFoilDraw[rngRequestDay & 1] = _packFoilDraw(0, level, rngRequestDay - 2, word);
        if (claimablePool == 0) claimablePool = 1 ether;
    }

    /// @dev Armed on day 100 for `winner`'s quadrant and symbol; today's draw resolves it.
    function armGoldenTicket(address winner, uint8 quadrant, uint8 symbol) external {
        goldenTicket = uint256(_seedWallet(winner)) | (uint256(quadrant) << 160) | (uint256(symbol) << 162)
            | (uint256(100) << 165) | (uint256(1) << 189);
    }

    function setEarlyBirdEntries(uint256 entries) external {
        dailyTicketBudgetsPacked = entries << 144;
    }

    /// @dev Every ticket group awarded: the next call plans and runs only the final step.
    function finishTicketGroups() external {
        jackpotWork.quadrant = 4;
        jackpotWork.winner = 0;
    }

    function ticketKind() external view returns (uint8) {
        return jackpotWork.kind;
    }

    function halfPassesOf(address player) external view returns (uint256) {
        return _halfPassesOf(player);
    }
}

/// @dev Repriced Glamsterdam figures of cold host calls (no reservoir). State-diff recording warms
///      every later access in a test, so a test with several measured calls takes every cold figure
///      (`_cold`) before its first recorded replay (`_replayed`), which supplies only the accesses.
abstract contract JackpotGlamsterdamUnits is MinerloopGasProbe {
    uint256 internal constant CAP = 30_000_000;

    function _cold(address host, bytes memory data) internal returns (uint256 used, bytes memory returned) {
        uint256 snap = vm.snapshotState();
        (used, returned) = this.minerloopMeasured(host, address(this), data, CAP);
        assertTrue(vm.revertToState(snap));
    }

    function _replayed(address host, bytes memory data, uint256 used, bytes memory returned)
        internal returns (GlamsterdamReprice.Result memory)
    {
        uint256 snap = vm.snapshotState();
        vm.startStateDiffRecording();
        (, bytes memory replay) = this.minerloopMeasured(host, address(this), data, CAP);
        VmSafe.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        vm.stopMappingRecording();
        assertTrue(vm.revertToState(snap));
        assertEq(replay, returned, "recorded replay reproduces the cold call");
        uint256 n;
        for (uint256 i; i < acc.length; ++i) {
            if (acc[i].account == address(vm)) continue;
            if (acc[i].account == address(this) && acc[i].kind != VmSafe.AccountAccessKind.Resume) continue;
            assertFalse(acc[i].reverted, "repricing assumes successful frames");
            acc[n++] = acc[i];
        }
        assembly ("memory-safe") { mstore(acc, n) }
        return GlamsterdamReprice.reprice(used, acc, host);
    }

    function _glam(address host, bytes memory data) internal returns (GlamsterdamReprice.Result memory r) {
        (r,) = _glamResult(host, data);
    }

    function _glamResult(address host, bytes memory data)
        internal returns (GlamsterdamReprice.Result memory r, MineFlipGas.Result memory result)
    {
        bytes memory returned;
        (r, returned) = _probe(host, address(this), data, CAP);
        vm.stopMappingRecording();
        if (returned.length != 0) result = abi.decode(returned, (MineFlipGas.Result));
    }

    function _total(GlamsterdamReprice.Result memory r) internal pure returns (uint256) {
        return r.glamsterdamExec + r.stateGas;
    }

    function _check(string memory label, GlamsterdamReprice.Result memory r, uint256 bound) internal {
        _report(label, r, bound);
        emit log_named_uint("new_slots", r.newSlots);
        assertLe(_total(r), bound, label);
    }

    /// @dev Unit = measured call minus the identical call refused before the unit.
    function _checkUnit(string memory label, GlamsterdamReprice.Result memory run,
        GlamsterdamReprice.Result memory refused, uint256 bound) internal
    {
        uint256 unit = _total(run) - _total(refused);
        emit log_named_string("unit", label);
        emit log_named_uint("osaka", run.osakaExec - refused.osakaExec);
        emit log_named_uint("glamsterdam_exec", run.glamsterdamExec - refused.glamsterdamExec);
        emit log_named_uint("glamsterdam_state", run.stateGas - refused.stateGas);
        emit log_named_uint("glamsterdam_total", unit);
        emit log_named_uint("new_slots", run.newSlots - refused.newSlots);
        emit log_named_uint("call_total", _total(run));
        emit log_named_uint("refused_call_total", _total(refused));
        emit log_named_uint("bound", bound);
        assertLe(unit, bound, label);
    }
}

/// @dev The original heavy 512-holder quadrants, isolated into individual units
/// with the production first-progress context. A zero allowance commits exactly
/// one mandatory unit, leaving no budget for an optional following unit.
contract JackpotEthNativeUnitsTest is JackpotGlamsterdamUnits {
    DeployedJackpotHost private h;
    uint24 private constant LVL = 110;
    uint256 private constant WORD = 0xAC4DE45EDBEEF;
    bytes32 private constant ETH_WIN = keccak256("JackpotEthWin(uint32,uint24,uint16,uint256,uint256)");
    // Admits the plan (120,000 + 180,000 tail + 2,000), never a group.
    uint256 private constant PLAN_ONLY = 320_000;

    function setUp() public {
        // Deployed EIP-170 shells at every module address (jackpot, ticket, foil, whale, ...), not the raw modules.
        ProfileModules.installGame(vm);
        h = new DeployedJackpotHost();
        h.seed(LVL, WORD, false);
        h.seedDaily(LVL);
    }

    function _one() private returns (MineFlipGas.Result memory) {
        return h.runDeployedDailyJackpot(true, LVL, WORD, MineFlipGas.budget(0, 10_000, true));
    }

    function _daily(uint256 allowance) private view returns (bytes memory) {
        return abi.encodeCall(h.runDeployedDailyJackpot, (true, LVL, WORD, allowance));
    }

    function _measure(uint256 allowance, uint256 expectedWins, bool expectDone) private {
        vm.cool(address(h));
        vm.cool(ContractAddresses.GAME_JACKPOT_MODULE);
        vm.cool(ContractAddresses.GAME_WHALE_MODULE);
        vm.recordLogs();
        MineFlipGas.Result memory result = h.runDeployedDailyJackpot(true, LVL, WORD, allowance);
        uint256 used = vm.lastCallGas().gasTotalUsed;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 wins;
        for (uint256 i; i < logs.length; ++i) if (logs[i].topics[0] == ETH_WIN) ++wins;
        assertEq(wins, expectedWins, "exact original sampler group");
        assertEq(result.done, expectDone, "expected phase completion");
        assertEq(result.progressed, allowance != PLAN_ONLY, "only the plan-only call refuses progress");
        assertLt(used, 10_000_000, "one checkpoint fits");
        emit log_named_uint("cold_native_eth_unit", used);
    }

    /// @dev Glamsterdam figures of the next mandatory unit and of the plan-only call refused before it.
    function _groupUnit() private returns (GlamsterdamReprice.Result memory run, GlamsterdamReprice.Result memory refused) {
        bytes memory refusedCall = _daily(PLAN_ONLY);
        bytes memory runCall = _daily(MineFlipGas.budget(0, 10_000, true));
        (uint256 refusedGas, bytes memory refusedOut) = _cold(address(h), refusedCall);
        (uint256 runGas, bytes memory runOut) = _cold(address(h), runCall);
        assertFalse(abi.decode(refusedOut, (MineFlipGas.Result)).progressed, "the plan-only call refuses the group");
        refused = _replayed(address(h), refusedCall, refusedGas, refusedOut);
        run = _replayed(address(h), runCall, runGas, runOut);
    }

    function test_NativeEthSetupOnly() public {
        uint256 snap = vm.snapshotState();
        _measure(MineFlipGas.budget(0, 10_000, true), 0, false);
        assertTrue(vm.revertToState(snap));
        // The whole setup-only call, prelude and return included, against the setup unit alone.
        _check("jackpot-day setup, fresh leg record (JACKPOT_SETUP_GAS)",
            _glam(address(h), _daily(MineFlipGas.budget(0, 10_000, true))), Bounds.JACKPOT_SETUP_GAS);
    }
    function test_NativeEthFirstGroup() public {
        assertTrue(_one().progressed);
        uint256 snap = vm.snapshotState();
        _measure(MineFlipGas.budget(0, 10_000, true), Bounds.JACKPOT_ETH_AWARD_CHUNK, false);
        assertTrue(vm.revertToState(snap));
        (GlamsterdamReprice.Result memory run, GlamsterdamReprice.Result memory refused) = _groupUnit();
        // First group with its pass conversion and checkpoint writes, against bound + tail at its canRun.
        _checkUnit("first ETH group with pass conversion (8 * WINNER + FIRST_GROUP + TAIL)", run, refused,
            Bounds.JACKPOT_ETH_AWARD_CHUNK * Bounds.JACKPOT_ETH_WINNER_GAS_MAX + Bounds.JACKPOT_ETH_FIRST_GROUP_GAS
                + Bounds.JACKPOT_TAIL_GAS);
    }
    function test_NativeEthContinuationGroup() public {
        assertTrue(_one().progressed);
        assertTrue(_one().progressed);
        uint256 snap = vm.snapshotState();
        _measure(MineFlipGas.budget(0, 10_000, true), Bounds.JACKPOT_ETH_AWARD_CHUNK, false);
        assertTrue(vm.revertToState(snap));
        (GlamsterdamReprice.Result memory run, GlamsterdamReprice.Result memory refused) = _groupUnit();
        _checkUnit("continuation ETH group (8 * WINNER + TAIL)", run, refused,
            Bounds.JACKPOT_ETH_AWARD_CHUNK * Bounds.JACKPOT_ETH_WINNER_GAS_MAX + Bounds.JACKPOT_TAIL_GAS);
    }
    function test_NativeEthPlanOnly() public {
        assertTrue(_one().progressed);
        uint256 snap = vm.snapshotState();
        _measure(PLAN_ONLY, 0, false);
        assertTrue(vm.revertToState(snap));
        // The whole plan-only call (prelude, plan, refused group, return) at its canRun admission.
        _check("ETH plan-only call (JACKPOT_PLAN_GAS + TAIL)", _glam(address(h), _daily(PLAN_ONLY)),
            Bounds.JACKPOT_PLAN_GAS + Bounds.JACKPOT_TAIL_GAS);
    }
    function test_NativeEthFinalGroup() public {
        for (uint256 i; i < 256; ++i) {
            uint256 snapshot = vm.snapshotState();
            bool done = _one().done;
            if (!done) { vm.deleteStateSnapshot(snapshot); continue; }
            assertTrue(vm.revertToStateAndDelete(snapshot));
            uint256 snap = vm.snapshotState();
            _measure(MineFlipGas.budget(0, 10_000, true), 1, true);
            assertTrue(vm.revertToState(snap));
            (GlamsterdamReprice.Result memory run, GlamsterdamReprice.Result memory refused) = _groupUnit();
            // The solo group with leg completion (final-day sweep, board record, retire).
            _checkUnit("final solo ETH group with completion (WINNER + FIRST_GROUP + TAIL)", run, refused,
                Bounds.JACKPOT_ETH_WINNER_GAS_MAX + Bounds.JACKPOT_ETH_FIRST_GROUP_GAS + Bounds.JACKPOT_TAIL_GAS);
            return;
        }
        revert("canonical groups must complete");
    }
}

/// @dev Glamsterdam setup and ticket-leg units with the deployed shells. Setup fixtures hold the most
///      new slots one setup can write: a fresh leg record, and a golden-ticket grand that credits a
///      fresh Coinflip stake page through the real Coinflip.
contract JackpotSetupAndTicketGlamsterdamTest is JackpotGlamsterdamUnits {
    uint24 private constant LVL = 110;
    uint256 private constant WORD = 0xAC4DE45EDBEEF;
    address private constant GOLD_HOLDER = address(0xA11CE);
    // Admits the plan and the worker call, never a ticket group (3.0156M).
    uint256 private constant TICKET_PLAN_ONLY = 3_000_000;
    // Admits the plan, never the final step with passes (450,000 + tail + 2,000).
    uint256 private constant FINAL_REFUSED = 400_000;
    uint256 private constant FINAL_ADMITTED = 2_000_000;
    // Admits the plan, never a one-award group (354,200 + tail + 2,000 inside the worker).
    uint256 private constant ONE_AWARD_REFUSED = 400_000;

    function setUp() public {
        ProfileModules.installGame(vm);
    }

    /// @dev Host at the Game address (the Coinflip creditor gate), real Coinflip with empty pages.
    function _gameHost() private returns (DeployedJackpotHost host) {
        vm.etch(ContractAddresses.GAME, address(new DeployedJackpotHost()).code);
        vm.etch(ContractAddresses.COINFLIP, vm.getDeployedCode("Coinflip.sol:Coinflip"));
        host = DeployedJackpotHost(ContractAddresses.GAME);
    }

    /// @dev First word whose board holds `golds` gold quadrants (GoldSix keeps a die gold).
    function _goldWord(uint256 golds) private pure returns (uint256 word, uint8[4] memory traits) {
        for (word = 1;; ++word) {
            traits = JackpotBucketLib.getRandomTraits(word);
            uint256 n;
            for (uint256 q; q < 4; ++q) if (((traits[q] >> 3) & 7) == 7) ++n;
            if (n == golds) return (word, traits);
        }
    }

    function _setup(DeployedJackpotHost host, bool jackpotPhase, uint256 word) private returns (GlamsterdamReprice.Result memory) {
        return _glam(address(host), abi.encodeCall(host.runDeployedDailyJackpot,
            (jackpotPhase, LVL, word, MineFlipGas.budget(0, 10_000, true))));
    }

    /// @dev The game's first purchase day: leg record, board slot, yield accumulator and budget field all new.
    function test_GlamsterdamPurchaseSetupFreshFields() public {
        DeployedJackpotHost host = _gameHost();
        host.primeFreshDay(LVL, false);
        GlamsterdamReprice.Result memory r = _setup(host, false, WORD);
        assertEq(host.ticketKind(), 1, "the setup checkpoint only");
        _check("purchase-day setup, five new slots (JACKPOT_SETUP_GAS)", r, Bounds.JACKPOT_SETUP_GAS);
    }

    /// @dev Jackpot day one (early-bird pricing) resolving an armed grand: ETH, passes and a fresh FLIP page.
    function test_GlamsterdamJackpotSetupGrandResolve() public {
        DeployedJackpotHost host = _gameHost();
        (uint256 word, uint8[4] memory traits) = _goldWord(4);
        host.primeFreshDay(LVL, true);
        host.primeLiveFields(word);
        host.armGoldenTicket(GOLD_HOLDER, 0, traits[0] & 7);
        GlamsterdamReprice.Result memory r = _setup(host, true, word);
        assertEq(host.ticketKind(), 2, "the setup checkpoint only");
        assertGt(host.halfPassesOf(GOLD_HOLDER), 0, "the grand paid its passes");
        _check("jackpot-day setup with golden grand (JACKPOT_SETUP_GAS)", r, Bounds.JACKPOT_SETUP_GAS);
    }

    /// @dev Purchase day resolving an armed grand with an empty yield accumulator.
    function test_GlamsterdamPurchaseSetupGrandResolve() public {
        DeployedJackpotHost host = _gameHost();
        (uint256 word, uint8[4] memory traits) = _goldWord(4);
        host.primeFreshDay(LVL, false);
        host.primeLiveFields(word);
        host.armGoldenTicket(GOLD_HOLDER, 0, traits[0] & 7);
        GlamsterdamReprice.Result memory r = _setup(host, false, word);
        assertEq(host.ticketKind(), 1, "the setup checkpoint only");
        assertGt(host.halfPassesOf(GOLD_HOLDER), 0, "the grand paid its passes");
        _check("purchase-day setup with golden grand (JACKPOT_SETUP_GAS)", r, Bounds.JACKPOT_SETUP_GAS);
    }

    /// @dev Early-bird leg over four 512-holder buckets whose surplus converts to whole passes.
    function _ticketHost() private returns (DeployedJackpotHost host) {
        host = new DeployedJackpotHost();
        host.seed(LVL, WORD, false);
        host.setEarlyBirdEntries(4_000_000);
        assertTrue(host.runDeployedEarlyBird(WORD, MineFlipGas.budget(0, 10_000, true)).progressed);
        assertEq(host.ticketKind(), 5);
    }

    function test_GlamsterdamTicketPlanOnly() public {
        DeployedJackpotHost host = _ticketHost();
        (GlamsterdamReprice.Result memory r, MineFlipGas.Result memory result) = _glamResult(address(host),
            abi.encodeCall(host.runDeployedEarlyBird, (WORD, TICKET_PLAN_ONLY)));
        assertEq(result.rewardBasis, 0, "the plan-only call awards no group");
        assertFalse(result.done);
        // The whole plan-only call, including the worker frame that refuses the group.
        _check("ticket plan-only call with worker frame (JACKPOT_PLAN_GAS + TAIL)", r,
            Bounds.JACKPOT_PLAN_GAS + Bounds.JACKPOT_TAIL_GAS);
    }

    function test_GlamsterdamTicketFinalWithPasses() public {
        DeployedJackpotHost host = _ticketHost();
        host.finishTicketGroups();
        uint256 snap = vm.snapshotState();
        vm.recordLogs();
        assertTrue(host.runDeployedEarlyBird(WORD, FINAL_ADMITTED).done, "the final step retires the leg");
        uint256 recipients;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == keccak256("JackpotWhalePassWin(uint32,uint256,uint8)")) ++recipients;
        }
        emit log_named_uint("pass recipients in the final step", recipients);
        assertGt(recipients, 0, "the final step awards passes");
        assertLe(recipients, 3, "at most the three non-solo quadrants draw a pass recipient");
        assertTrue(vm.revertToState(snap));
        bytes memory refusedCall = abi.encodeCall(host.runDeployedEarlyBird, (WORD, FINAL_REFUSED));
        bytes memory runCall = abi.encodeCall(host.runDeployedEarlyBird, (WORD, FINAL_ADMITTED));
        (uint256 refusedGas, bytes memory refusedOut) = _cold(address(host), refusedCall);
        (uint256 runGas, bytes memory runOut) = _cold(address(host), runCall);
        assertFalse(abi.decode(refusedOut, (MineFlipGas.Result)).done, "below the final admission the leg stays open");
        assertTrue(abi.decode(runOut, (MineFlipGas.Result)).done);
        GlamsterdamReprice.Result memory refused = _replayed(address(host), refusedCall, refusedGas, refusedOut);
        GlamsterdamReprice.Result memory run = _replayed(address(host), runCall, runGas, runOut);
        _checkUnit("ticket final step with three pass recipients (FINAL + 3 * PASS_AWARD)", run, refused,
            Bounds.JACKPOT_FINAL_GAS + 3 * Bounds.JACKPOT_PASS_AWARD_GAS);
    }

    /// @dev A one-ticket leg over one seeded quadrant: its single winner's award writes the most new
    ///      slots one award can, its pending word and the never-used queue's first word and header.
    function test_GlamsterdamTicketSingleFreshAward() public {
        DeployedJackpotHost host = new DeployedJackpotHost();
        host.seed(LVL, WORD, true);
        host.setEarlyBirdEntries(4);
        assertTrue(host.runDeployedEarlyBird(WORD, MineFlipGas.budget(0, 10_000, true)).progressed);
        bytes memory refusedCall = abi.encodeCall(host.runDeployedEarlyBird, (WORD, ONE_AWARD_REFUSED));
        bytes memory runCall = abi.encodeCall(host.runDeployedEarlyBird, (WORD, MineFlipGas.budget(0, 10_000, true)));
        (uint256 refusedGas, bytes memory refusedOut) = _cold(address(host), refusedCall);
        (uint256 runGas, bytes memory runOut) = _cold(address(host), runCall);
        assertEq(abi.decode(refusedOut, (MineFlipGas.Result)).rewardBasis, 0, "below its admission the award waits");
        assertEq(abi.decode(runOut, (MineFlipGas.Result)).rewardBasis, 1, "the mandatory unit is the single award");
        GlamsterdamReprice.Result memory refused = _replayed(address(host), refusedCall, refusedGas, refusedOut);
        GlamsterdamReprice.Result memory run = _replayed(address(host), runCall, runGas, runOut);
        assertEq(run.newSlots - refused.newSlots, 3, "pending word, queue word and queue header are new");
        uint256 bound = Bounds.JACKPOT_TICKET_DRAW_GAS_MAX + Bounds.JACKPOT_TICKET_AWARD_GAS_MAX;
        emit log_named_uint("one-award admission without its tail (DRAW + AWARD)", bound);
        // The unit holds the draw, the award and the checkpoint write the tail reserves.
        _checkUnit("single fresh ticket award with its checkpoint (DRAW + AWARD + TAIL)", run, refused,
            bound + Bounds.JACKPOT_TAIL_GAS);
    }

    function test_GlamsterdamTicketPassRecipient() public {
        DeployedJackpotHost host = new DeployedJackpotHost();
        host.seed(LVL, WORD, false);
        uint8 trait = JackpotBucketLib.getRandomTraits(WORD)[0];
        GlamsterdamReprice.Result memory r = _glam(address(host),
            abi.encodeCall(host.awardDeployedPass, (LVL, trait, 200, uint256(keccak256("pass")))));
        assertEq(r.sstores, 1, "one claim write");
        _check("one ticket-leg pass recipient (JACKPOT_PASS_AWARD_GAS)", r, Bounds.JACKPOT_PASS_AWARD_GAS);
    }

}
