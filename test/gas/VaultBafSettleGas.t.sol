// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Coinflip} from "../../contracts/Coinflip.sol";
import {CoinflipStakeSetter} from "../helpers/CoinflipStakeSetter.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {VaultBafRig} from "../repro/VaultBafSettlement.t.sol";
import {NativeGasExport} from "../helpers/NativeGasExport.sol";
import {GlamsterdamReprice} from "../helpers/GlamsterdamReprice.sol";
import {VaultBackstopHost} from "../fuzz/VaultFlipBackstop.t.sol";
import {ICoinflip} from "../../contracts/interfaces/ICoinflip.sol";
import {MinerloopGasProbe} from "../helpers/MinerloopGasProbe.sol";
import {VmSafe} from "forge-std/Vm.sol";

/// @title VaultBafSettleGas — cold cost of Vault settlement at the x0 seal.
///
/// @notice The seal settles Vault through a zero-deposit call: one claim walk over
///         the days since its last settlement, at most COIN_CLAIM_DAYS (90), always through the
///         latest resolved day. Its gas is the BAF_VAULT_SETTLE reserve that every seal-capable
///         purchase leg keeps in its tail on an x0 purchase day.
///         - Settle call, cold, every walked day staked and resolved (one loss, so the WWXRP
///           loss mint fires too), auto-rebuy with a carry-keeping stop and auto-rebuy off: a
///           typical 10-level gap (70 days) and the full 90-day window, whose first day opens
///           a fresh result and stake word so the walk crosses the most words a window can.
///           Each stays under BAF_VAULT_SETTLE, and the Glamsterdam re-pricing is logged.
///         - The real sealing chunk, cold: the runDailyPhase_g2582 call that finishes the latch day's
///           purchase legs and seals, in a turbo game (short gap) and in a slow game whose
///           vault walks the full 90-day window, each beside a pre-settled control. Each chunk
///           stays at or under 10M.

/// @dev Writes the vault's coinflip history through Coinflip's own lane helpers.
contract VaultSettleSeeder is CoinflipStakeSetter {
    /// @dev Patterns 0..4: all wins, middle loss, final loss, alternating, all losses.
    ///      Patterns 5..94 place a single loss at each of the 90 possible positions.
    function seedUnlimitedHistory(uint32 id, uint24 latest, uint8 pattern) external {
        PlayerCoinflipState storage s = playerState[id];
        uint24 last = latest - 90;
        s.claimableStored = 0;
        s.lastClaim = last;
        s.autoRebuyStartDay = last;
        s.autoRebuyEnabled = true;
        s.autoRebuyUnlimited = true;
        s.initialized = true;
        s.autoRebuyStop = 1;
        s.autoRebuyCarry = type(uint128).max;
        for (uint24 d = last + 1; d <= latest; ++d) {
            _setFlipStake(d, id, type(uint32).max);
            bool win = pattern == 0 || (pattern == 1 && d != last + 45)
                || (pattern == 2 && d != latest) || (pattern == 3 && d % 2 == 0)
                || (pattern >= 5 && d != uint256(last) + pattern - 4);
            _storeDayResult(d, 156, win);
        }
        flipsClaimableDay = latest;
    }

    function seedVaultHistory(uint24 latest, uint24 gap, bool rebuy) external {
        address v = ContractAddresses.VAULT;
        PlayerCoinflipState storage s = playerState[degenerusGame.walletIdOf_g3120(v)];
        uint24 last = latest - gap;
        s.claimableStored = 0;
        s.lastClaim = last;
        s.autoRebuyStartDay = rebuy ? last : 0;
        s.autoRebuyEnabled = rebuy;
        s.autoRebuyUnlimited = false;
        // A stop that never divides a payout: every win banks a slice and rolls a carry.
        s.autoRebuyStop = rebuy ? 7 ether : 0;
        s.autoRebuyCarry = 0;
        uint24 lossDay = last + gap / 2;
        for (uint24 d = last + 1; d <= latest; ++d) {
            _setFlipStake(d, 1, 5_000 ether);
            _storeDayResult(d, 150, d != lossDay);
        }
        flipsClaimableDay = latest;
    }
}

/// @dev Production facade plus native seams for the daily cycle after the request.
contract VaultSettleHost is DegenerusGame {
    function settleAccounts(uint8 mask) external {
        ICoinflip flips = ICoinflip(ContractAddresses.COINFLIP);
        if (mask & 1 != 0) flips.playCoinflip(1, 0);
        if (mask & 2 != 0) flips.playCoinflip(3, 0);
    }

    function publishOnly() external {
        _native(ContractAddresses.GAME_RNG_MODULE, abi.encodeWithSignature("publishRng_g4514()"));
    }

    function ticketsOnly() external returns (bool done) {
        uint24 anchor = !jackpotPhaseFlag && lastPurchaseDay && rngLockedFlag ? level : level + 1;
        MineFlipGas.Result memory result = abi.decode(_native(ContractAddresses.GAME_TICKET_MODULE,
            abi.encodeWithSignature("runTicketWork_g1150(uint24,uint256)", anchor, uint256(9_000_000))),
            (MineFlipGas.Result));
        done = result.done;
        if (done) {
            // Identical normalization to Miner after a completed native read.
            ticketsFullyProcessed = true;
            _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0);
        }
    }

    function applyOnly() external {
        _native(ContractAddresses.GAME_ADVANCE_MODULE, abi.encodeWithSignature("applyDailyWord_g1652()"));
    }

    function dailyWith(uint256 allowance) external returns (MineFlipGas.Result memory) {
        return abi.decode(_native(ContractAddresses.GAME_ADVANCE_MODULE,
            abi.encodeWithSignature("runDailyPhase_g2582(uint256)", allowance)), (MineFlipGas.Result));
    }

    function _native(address target, bytes memory data) private returns (bytes memory result) {
        (bool ok, bytes memory reason) = target.delegatecall(data);
        if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
        return reason;
    }
}

// -------------------------------------------------------------------------
// The settle call alone
// -------------------------------------------------------------------------

abstract contract VaultSettleCallGas is DeployProtocol, NativeGasExport {
    /// @dev The full window's first day, 1432 - 89 = 1343, is lane 31 of a result word and lane 6
    ///      of a stake word.
    uint24 internal constant LATEST = 1432;

    function _gap() internal pure virtual returns (uint24);
    function _rebuy() internal pure virtual returns (bool);

    function setUp() public {
        _deployProtocol();
        vm.warp((uint256(LATEST) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + 1);
        bytes memory original = address(coinflip).code;
        vm.etch(address(coinflip), type(VaultSettleSeeder).runtimeCode);
        VaultSettleSeeder(address(coinflip)).seedVaultHistory(LATEST, _gap(), _rebuy());
        vm.etch(address(coinflip), original);
    }

    /// @dev The first call of the test: every slot the walk touches is cold.
    function test_SettleCallCold() public {
        uint256 snapshot = vm.snapshotState();
        vm.prank(address(game));
        coinflip.playCoinflip(1, 0);
        uint256 used = vm.lastCallGas().gasTotalUsed;
        emit log_named_uint("vault_settle_call_days", _gap());
        emit log_named_uint("vault_settle_call_gas", used);
        uint256 state = uint256(vm.load(address(coinflip), keccak256(abi.encode(uint32(1), uint256(2)))));
        assertEq(uint24(state >> 128), LATEST, "the walk settles every resolved day");
        assertLe(used, GasBounds.BAF_VAULT_SETTLE, "the settle call fits its declared reserve");
        if (bytes(vm.envOr("STORAGE_REUSE_EXPORT", string(""))).length != 0) {
            assertTrue(vm.revertToState(snapshot));
            string memory label = string.concat("vault-window-", vm.toString(_gap()), "-", vm.toString(_rebuy()));
            vm.serializeUint(label, "fixedCalleeBudget", GasBounds.BAF_VAULT_SETTLE);
            vm.serializeBool(label, "enforceBudget", true);
            this.exportNativeFixture(label, address(game), address(coinflip), abi.encodeCall(coinflip.playCoinflip, (uint32(1), uint256(0))));
            vm.prank(address(game)); coinflip.playCoinflip(1, 0);
        }
        vm.deleteStateSnapshot(snapshot);
    }

    /// @dev The same cold call re-priced under Glamsterdam (EIP-8037 / EIP-8038).
    function test_SettleCallGlamsterdam() public {
        // The cold figure comes from an isolated call; the recorded replay of the same call
        // supplies the accesses (recording does not keep the call's own cold state).
        uint256 snap = vm.snapshotState();
        vm.prank(address(game));
        coinflip.playCoinflip(1, 0);
        uint256 used = vm.lastCallGas().gasTotalUsed;
        vm.revertToState(snap);
        vm.startStateDiffRecording();
        vm.prank(address(game));
        coinflip.playCoinflip(1, 0);
        VmSafe.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        GlamsterdamReprice.Result memory r = GlamsterdamReprice.reprice(used, acc, address(coinflip));
        emit log_named_uint("vault_settle_call_days", _gap());
        emit log_named_uint("osaka_gas", r.osakaExec);
        emit log_named_uint("glamsterdam_exec_gas", r.glamsterdamExec);
        emit log_named_uint("glamsterdam_state_gas", r.stateGas);
        emit log_named_uint("new_slots_0_to_x", r.newSlots);
        emit log_named_uint("cold_accounts", r.coldAccounts);
        assertLe(r.glamsterdamExec + r.stateGas, GasBounds.BAF_VAULT_SETTLE, "the settle unit fits its reserve under Glamsterdam");
    }
}

contract VaultSettleCallGas70Rebuy is VaultSettleCallGas {
    function _gap() internal pure override returns (uint24) { return 70; }
    function _rebuy() internal pure override returns (bool) { return true; }
}

contract VaultSettleCallGas70Plain is VaultSettleCallGas {
    function _gap() internal pure override returns (uint24) { return 70; }
    function _rebuy() internal pure override returns (bool) { return false; }
}

contract VaultSettleCallGas90Rebuy is VaultSettleCallGas {
    function _gap() internal pure override returns (uint24) { return 90; }
    function _rebuy() internal pure override returns (bool) { return true; }
}

contract VaultSettleCallGas90Plain is VaultSettleCallGas {
    function _gap() internal pure override returns (uint24) { return 90; }
    function _rebuy() internal pure override returns (bool) { return false; }
}

// -------------------------------------------------------------------------
// The real sealing chunk
// -------------------------------------------------------------------------

abstract contract VaultSealChunkGas is VaultBafRig, NativeGasExport {
    uint256 internal constant ALLOWANCE = 9_000_000;
    uint256 internal constant CHUNK_CAP = 10_000_000;

    uint24 internal latchDay;
    uint24 internal settledAt;

    /// @dev Slow game: levels 0-18 each hold 27 purchase days, below the 30-day deadline,
    ///      so the level-20 seal falls after day 90 and the vault can carry a full-window
    ///      backlog. Automatic craps funding can settle the vault along the way, so seed its
    ///      worst-case claim backlog immediately before the measured seal to keep the
    ///      full-window gas measurement deterministic.
    function _slow() internal pure virtual returns (bool);
    /// @dev Control: settle the vault's available results before measuring the seal.
    function _presettle() internal pure virtual returns (bool);
    /// @dev Both seeded full-window accounts use unlimited rebuy and maximum starting carry.
    function _rebuy() internal pure virtual returns (bool) {
        return false;
    }

    function _holdFor(uint24 lvl) internal view override returns (uint256) {
        if (!_slow()) return super._holdFor(lvl);
        return lvl < 19 ? 27 : 0;
    }

    function setUp() public override {
        super.setUp();
        vm.pauseGasMetering();
        _settleToday();
        if (_slow()) {
            _runFullDay();
            vm.prank(POKER);
            coinflip.playCoinflip(1, 0);
        }
        if (_rebuy()) {
            vm.prank(VAULT);
            coinflip.setCoinflipAutoRebuy(0, true, 7 ether);
        }
        uint24 pokedAt = _lastClaim(VAULT);
        _driveToEve(_slow() ? 19 : 9);
        latchDay = game.currentDayView_g542950() + 1;
        _stageDay();
        if (!_slow()) {
            require(_lastClaim(VAULT) == pokedAt, "harness: no intermediate vault settlement");
        }
        for (uint256 pokes; !_slow() && _presettle() && _lastClaim(VAULT) + 1 < latchDay; ++pokes) {
            require(pokes < 4, "harness: the control never settled");
            vm.prank(POKER);
            coinflip.playCoinflip(1, 0);
        }
        // The latch day up to its request, then the native daily cycle.
        simTime += 1 days + 1;
        vm.warp(simTime);
        uint256 before = mockVRF.lastRequestId();
        for (uint256 calls; mockVRF.lastRequestId() == before; ++calls) {
            require(calls < 64, "harness: the latch-day request stalled");
            game.mineRun{gas: 12_000_000}(0);
        }
        _fulfillPending();
        vm.etch(address(game), type(VaultSettleHost).runtimeCode);
        VaultSettleHost host = VaultSettleHost(payable(address(game)));
        host.publishOnly();
        for (uint256 reads; !host.ticketsOnly(); ++reads) require(reads < 32, "harness: tickets stalled");
        host.applyOnly();
        for (uint256 phases; ; ++phases) {
            require(phases < 64, "harness: the latch day never sealed");
            uint256 snap = vm.snapshotState();
            host.dailyWith(ALLOWANCE);
            if (_latched()) {
                vm.revertToState(snap);
                break;
            }
            vm.deleteStateSnapshot(snap);
        }
        if (_slow()) {
            require(latchDay > 90, "harness: the slow game reaches a full-window backlog");
            bytes memory original = address(coinflip).code;
            vm.etch(address(coinflip), type(VaultSettleSeeder).runtimeCode);
            VaultSettleSeeder(address(coinflip)).seedVaultHistory(latchDay, 90, _rebuy());
            VaultSettleSeeder(address(coinflip)).seedUnlimitedHistory(3, latchDay, 0);
            if (_rebuy()) VaultSettleSeeder(address(coinflip)).seedUnlimitedHistory(1, latchDay, 0);
            vm.etch(address(coinflip), original);
            if (_presettle()) {
                vm.prank(POKER);
                coinflip.playCoinflip(1, 0);
                vm.prank(POKER);
                coinflip.playCoinflip(3, 0);
            }
        }
        emit log_named_uint("vault_days_unsettled", latchDay - _lastClaim(VAULT));
        // One claim walk always settles through the latest resolved day.
        settledAt = latchDay;
        vm.resumeGasMetering();
    }

    function _latched() internal view returns (bool) {
        (, , bool lastPurchaseDay_, , ) = game.purchaseInfo_g1027();
        return lastPurchaseDay_;
    }

    /// @dev The first call of the test: the latch day's last purchase leg and its seal, cold.
    function test_SealCrankCold() public {
        uint24 gnrusBefore = _lastClaim(ContractAddresses.GNRUS);
        game.mineRun{gas: CHUNK_CAP}(0);
        uint256 used = vm.lastCallGas().gasTotalUsed;
        assertTrue(_latched(), "the full crank seals within 10M supplied gas");
        assertEq(_lastClaim(VAULT), settledAt);
        assertEq(_lastClaim(ContractAddresses.GNRUS), gnrusBefore, "Vault-only seal leaves GNRUS for the request");
        emit log_named_uint("protocol_seal_full_crank_gas", used);
        assertLe(used, CHUNK_CAP);
    }

    function test_SealChunkCold() public {
        uint24 gnrusBefore = _lastClaim(ContractAddresses.GNRUS);
        uint256 snapshot = vm.snapshotState();
        VaultSettleHost(payable(address(game))).dailyWith(ALLOWANCE);
        uint256 used = vm.lastCallGas().gasTotalUsed;
        emit log_named_uint("vault_seal_chunk_gas", used);
        assertTrue(_latched(), "the measured call seals the latch day");
        (uint24 armed, , ) = coinflip.bafDrawInfo();
        assertEq(armed, latchDay + 1, "and arms the BAF draw");
        assertEq(_lastClaim(VAULT), settledAt, "and settles the vault's claim window");
        assertEq(_lastClaim(ContractAddresses.GNRUS), gnrusBefore, "Vault-only seal");
        assertLe(used, CHUNK_CAP, "the sealing chunk stays at or under 10M");
        if (bytes(vm.envOr("STORAGE_REUSE_EXPORT", string(""))).length != 0) {
            assertTrue(vm.revertToState(snapshot));
            string memory label = string.concat("vault-seal-", vm.toString(_slow()), "-", vm.toString(_presettle()), "-", vm.toString(_rebuy()));
            vm.serializeUint(label, "fixedCalleeBudget", CHUNK_CAP);
            vm.serializeBool(label, "enforceBudget", true);
            this.exportNativeFixture(label, address(this), address(game), abi.encodeCall(VaultSettleHost.dailyWith, (ALLOWANCE)));
            VaultSettleHost(payable(address(game))).dailyWith(ALLOWANCE);
        }
        vm.deleteStateSnapshot(snapshot);
    }
}

contract VaultSealChunkGasTurbo is VaultSealChunkGas {
    function _slow() internal pure override returns (bool) { return false; }
    function _presettle() internal pure override returns (bool) { return false; }
}

contract VaultSealChunkGasTurboSettled is VaultSealChunkGas {
    function _slow() internal pure override returns (bool) { return false; }
    function _presettle() internal pure override returns (bool) { return true; }
}

contract VaultSealChunkGasSlow is VaultSealChunkGas {
    function _slow() internal pure override returns (bool) { return true; }
    function _presettle() internal pure override returns (bool) { return false; }
}

contract VaultSealChunkGasSlowSettled is VaultSealChunkGas {
    function _slow() internal pure override returns (bool) { return true; }
    function _presettle() internal pure override returns (bool) { return true; }
}

contract VaultSealChunkGasSlowRebuy is VaultSealChunkGas {
    function test_sealCrankAcrossOutcomePatterns() public {
        require(vm.envOr("FOUNDRY_ISOLATE", false), "cold measurement requires isolation");
        uint256 maximum;
        for (uint8 pattern; pattern < 95; ++pattern) {
            uint256 snap = vm.snapshotState();
            bytes memory original = address(coinflip).code;
            vm.etch(address(coinflip), type(VaultSettleSeeder).runtimeCode);
            VaultSettleSeeder(address(coinflip)).seedUnlimitedHistory(1, latchDay, pattern);
            VaultSettleSeeder(address(coinflip)).seedUnlimitedHistory(3, latchDay, pattern);
            vm.etch(address(coinflip), original);
            uint24 gnrusBefore = _lastClaim(ContractAddresses.GNRUS);
            game.mineRun{gas: CHUNK_CAP}(0);
            uint256 used = vm.lastCallGas().gasTotalUsed;
            assertTrue(_latched());
            assertEq(_lastClaim(VAULT), settledAt);
            assertEq(_lastClaim(ContractAddresses.GNRUS), gnrusBefore, "Vault-only seal leaves GNRUS for the request");
            assertLe(used, CHUNK_CAP);
            emit log_named_uint("seal_pattern", pattern);
            emit log_named_uint("protocol_seal_full_crank_gas", used);
            if (used > maximum) maximum = used;
            assertTrue(vm.revertToState(snap));
            vm.deleteStateSnapshot(snap);
        }
        emit log_named_uint("maximum_protocol_seal_crank_gas", maximum);
    }

    function test_vaultSettlementFailureRollsBackSeal() public {
        uint24 vaultCursor = _lastClaim(VAULT);
        uint24 gnrusCursor = _lastClaim(ContractAddresses.GNRUS);
        bytes32 stampWord = vm.load(address(game), bytes32(uint256(4)));
        (uint24 armedBefore, uint96 weightBefore, uint32 entriesBefore) = coinflip.bafDrawInfo();
        vm.mockCallRevert(ContractAddresses.JACKPOTS,
            abi.encodePacked(bytes4(keccak256("recordBafFlip(uint32,uint24,uint256)")), abi.encode(uint32(1))),
            abi.encodeWithSignature("SecondSettlementFailed()"));
        vm.expectRevert(bytes4(keccak256("SecondSettlementFailed()")));
        VaultSettleHost(payable(address(game))).dailyWith(ALLOWANCE);
        assertFalse(_latched());
        assertEq(_lastClaim(VAULT), vaultCursor);
        assertEq(_lastClaim(ContractAddresses.GNRUS), gnrusCursor);
        assertEq(vm.load(address(game), bytes32(uint256(4))), stampWord);
        (uint24 armedAfter, uint96 weightAfter, uint32 entriesAfter) = coinflip.bafDrawInfo();
        assertEq(armedAfter, armedBefore);
        assertEq(weightAfter, weightBefore);
        assertEq(entriesAfter, entriesBefore);
        vm.clearMockedCalls();
        VaultSettleHost(payable(address(game))).dailyWith(ALLOWANCE);
        assertTrue(_latched());
        assertEq(_lastClaim(VAULT), settledAt);
        assertEq(_lastClaim(ContractAddresses.GNRUS), gnrusCursor, "Vault-only seal leaves GNRUS for the request");
    }

    function _slow() internal pure override returns (bool) { return true; }
    function _presettle() internal pure override returns (bool) { return false; }
    function _rebuy() internal pure override returns (bool) { return true; }
}

contract VaultSealChunkGasSlowRebuySettled is VaultSealChunkGas {
    function _slow() internal pure override returns (bool) { return true; }
    function _presettle() internal pure override returns (bool) { return true; }
    function _rebuy() internal pure override returns (bool) { return true; }
}

/// @dev Each measured call is a separate cold transaction under the gas runner's isolation mode.
contract ProtocolSettleUnlimitedGas is DeployProtocol {
    uint24 private constant LATEST = 1432;

    function setUp() public {
        _deployProtocol();
        vm.warp((uint256(LATEST) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
        vm.etch(address(game), type(VaultSettleHost).runtimeCode);
    }

    function _seed(uint8 pattern) private {
        bytes memory original = address(coinflip).code;
        vm.etch(address(coinflip), type(VaultSettleSeeder).runtimeCode);
        VaultSettleSeeder(address(coinflip)).seedUnlimitedHistory(1, LATEST, pattern);
        VaultSettleSeeder(address(coinflip)).seedUnlimitedHistory(3, LATEST, pattern);
        vm.etch(address(coinflip), original);
    }

    function _measure(uint8 mask) private {
        require(vm.envOr("FOUNDRY_ISOLATE", false), "cold measurement requires isolation");
        uint256 maximum;
        for (uint8 pattern; pattern < 95; ++pattern) {
            uint256 snap = vm.snapshotState();
            _seed(pattern);
            VaultSettleHost(payable(address(game))).settleAccounts(mask);
            uint256 used = vm.lastCallGas().gasTotalUsed;
            emit log_named_uint("pattern", pattern);
            emit log_named_uint("osaka_settle_gas", used);
            assertLt(used, GasBounds.BAF_VAULT_SETTLE / 2, "twofold settlement reserve margin");
            if (used > maximum) maximum = used;
            for (uint32 id = 1; id <= 3; id += 2) {
                if ((mask & (id == 1 ? 1 : 2)) == 0) continue;
                uint256 state = uint256(vm.load(address(coinflip), keccak256(abi.encode(id, uint256(2)))));
                assertEq(uint24(state >> 128), LATEST);
            }
            vm.revertToState(snap);
            _seed(pattern);
            vm.startStateDiffRecording();
            VaultSettleHost(payable(address(game))).settleAccounts(mask);
            VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
            GlamsterdamReprice.Result memory r = this.repriceCall(used, accesses);
            emit log_named_uint("glamsterdam_exec_gas", r.glamsterdamExec);
            emit log_named_uint("glamsterdam_state_gas", r.stateGas);
            assertLt(r.glamsterdamExec + r.stateGas, GasBounds.BAF_VAULT_SETTLE / 2);
            assertTrue(vm.revertToState(snap));
            vm.deleteStateSnapshot(snap);
        }
        emit log_named_uint("maximum_osaka_settle_gas", maximum);
    }

    /// @dev A fresh call frame releases the repricer's large scratch arrays after each case.
    function repriceCall(uint256 used, VmSafe.AccountAccess[] memory accesses)
        external view returns (GlamsterdamReprice.Result memory)
    {
        return GlamsterdamReprice.reprice(used, accesses, address(game));
    }

    function test_vaultAlone90Unlimited() public { _measure(1); }
    function test_gnrusAlone90Unlimited() public { _measure(2); }
    function test_both90Unlimited() public { _measure(3); }

    function test_completeBackstop90UnlimitedBelow10M() public {
        require(vm.envOr("FOUNDRY_ISOLATE", false), "cold measurement requires isolation");
        for (uint8 pattern; pattern < 95; ++pattern) {
            uint256 snap = vm.snapshotState();
            _seed(pattern);
            vm.etch(address(game), type(VaultBackstopHost).runtimeCode);
            VaultBackstopHost host = VaultBackstopHost(payable(address(game)));
            host.seedPhase(LATEST, LATEST - 90, 0);
            MineFlipGas.Result memory result = host.phase(9_000_000);
            uint256 used = vm.lastCallGas().gasTotalUsed;
            assertTrue(result.progressed);
            assertFalse(result.done);
            assertEq(host.stamp(), LATEST);
            assertLt(used, 10_000_000);
            emit log_named_uint("checkpoint_pattern", pattern);
            emit log_named_uint("complete_backstop_gas", used);
            assertTrue(vm.revertToState(snap));
            vm.deleteStateSnapshot(snap);
        }
    }
}

/// @notice The complete Vault-only backstop checkpoint on both schedules.
contract VaultBackstopRepricedGas is DeployProtocol, MinerloopGasProbe {
    uint24 private constant LATEST = 1432;
    function setUp() public {
        _deployProtocol();
        vm.warp((uint256(LATEST) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
        vm.etch(address(game), type(VaultBackstopHost).runtimeCode);
    }
    function seedBackstop(uint8 pattern) external {
        require(msg.sender == address(this));
        bytes memory original = address(coinflip).code;
        vm.etch(address(coinflip), type(VaultSettleSeeder).runtimeCode);
        VaultSettleSeeder(address(coinflip)).seedUnlimitedHistory(1, LATEST, pattern);
        vm.etch(address(coinflip), original);
        VaultBackstopHost(payable(address(game))).seedPhase(LATEST, LATEST - 90, 0);
    }
    function _measure(uint8 pattern) private {
        this.seedBackstop(pattern);
        (GlamsterdamReprice.Result memory r, bytes memory returned) = _probe(address(game), address(this),
            abi.encodeCall(VaultBackstopHost.phase, (uint256(9_000_000))), 9_500_000);
        MineFlipGas.Result memory result = abi.decode(returned, (MineFlipGas.Result));
        assertTrue(result.progressed);
        assertFalse(result.done);
        _report(string.concat("vault_backstop_pattern_", vm.toString(pattern)), r, GasBounds.BAF_VAULT_SETTLE);
        assertLe(r.osakaExec, GasBounds.BAF_VAULT_SETTLE);
        assertLe(r.glamsterdamExec + r.stateGas, GasBounds.BAF_VAULT_SETTLE);
    }
    function test_ColdPattern00() public { _measure(0); }
    function test_ColdPattern01() public { _measure(1); }
    function test_ColdPattern02() public { _measure(2); }
    function test_ColdPattern03() public { _measure(3); }
    function test_ColdPattern04() public { _measure(4); }
    function test_ColdPattern05() public { _measure(5); }
    function test_ColdPattern06() public { _measure(6); }
    function test_ColdPattern07() public { _measure(7); }
    function test_ColdPattern08() public { _measure(8); }
    function test_ColdPattern09() public { _measure(9); }
    function test_ColdPattern10() public { _measure(10); }
    function test_ColdPattern11() public { _measure(11); }
    function test_ColdPattern12() public { _measure(12); }
    function test_ColdPattern13() public { _measure(13); }
    function test_ColdPattern14() public { _measure(14); }
    function test_ColdPattern15() public { _measure(15); }
    function test_ColdPattern16() public { _measure(16); }
    function test_ColdPattern17() public { _measure(17); }
    function test_ColdPattern18() public { _measure(18); }
    function test_ColdPattern19() public { _measure(19); }
    function test_ColdPattern20() public { _measure(20); }
    function test_ColdPattern21() public { _measure(21); }
    function test_ColdPattern22() public { _measure(22); }
    function test_ColdPattern23() public { _measure(23); }
    function test_ColdPattern24() public { _measure(24); }
    function test_ColdPattern25() public { _measure(25); }
    function test_ColdPattern26() public { _measure(26); }
    function test_ColdPattern27() public { _measure(27); }
    function test_ColdPattern28() public { _measure(28); }
    function test_ColdPattern29() public { _measure(29); }
    function test_ColdPattern30() public { _measure(30); }
    function test_ColdPattern31() public { _measure(31); }
    function test_ColdPattern32() public { _measure(32); }
    function test_ColdPattern33() public { _measure(33); }
    function test_ColdPattern34() public { _measure(34); }
    function test_ColdPattern35() public { _measure(35); }
    function test_ColdPattern36() public { _measure(36); }
    function test_ColdPattern37() public { _measure(37); }
    function test_ColdPattern38() public { _measure(38); }
    function test_ColdPattern39() public { _measure(39); }
    function test_ColdPattern40() public { _measure(40); }
    function test_ColdPattern41() public { _measure(41); }
    function test_ColdPattern42() public { _measure(42); }
    function test_ColdPattern43() public { _measure(43); }
    function test_ColdPattern44() public { _measure(44); }
    function test_ColdPattern45() public { _measure(45); }
    function test_ColdPattern46() public { _measure(46); }
    function test_ColdPattern47() public { _measure(47); }
    function test_ColdPattern48() public { _measure(48); }
    function test_ColdPattern49() public { _measure(49); }
    function test_ColdPattern50() public { _measure(50); }
    function test_ColdPattern51() public { _measure(51); }
    function test_ColdPattern52() public { _measure(52); }
    function test_ColdPattern53() public { _measure(53); }
    function test_ColdPattern54() public { _measure(54); }
    function test_ColdPattern55() public { _measure(55); }
    function test_ColdPattern56() public { _measure(56); }
    function test_ColdPattern57() public { _measure(57); }
    function test_ColdPattern58() public { _measure(58); }
    function test_ColdPattern59() public { _measure(59); }
    function test_ColdPattern60() public { _measure(60); }
    function test_ColdPattern61() public { _measure(61); }
    function test_ColdPattern62() public { _measure(62); }
    function test_ColdPattern63() public { _measure(63); }
    function test_ColdPattern64() public { _measure(64); }
    function test_ColdPattern65() public { _measure(65); }
    function test_ColdPattern66() public { _measure(66); }
    function test_ColdPattern67() public { _measure(67); }
    function test_ColdPattern68() public { _measure(68); }
    function test_ColdPattern69() public { _measure(69); }
    function test_ColdPattern70() public { _measure(70); }
    function test_ColdPattern71() public { _measure(71); }
    function test_ColdPattern72() public { _measure(72); }
    function test_ColdPattern73() public { _measure(73); }
    function test_ColdPattern74() public { _measure(74); }
    function test_ColdPattern75() public { _measure(75); }
    function test_ColdPattern76() public { _measure(76); }
    function test_ColdPattern77() public { _measure(77); }
    function test_ColdPattern78() public { _measure(78); }
    function test_ColdPattern79() public { _measure(79); }
    function test_ColdPattern80() public { _measure(80); }
    function test_ColdPattern81() public { _measure(81); }
    function test_ColdPattern82() public { _measure(82); }
    function test_ColdPattern83() public { _measure(83); }
    function test_ColdPattern84() public { _measure(84); }
    function test_ColdPattern85() public { _measure(85); }
    function test_ColdPattern86() public { _measure(86); }
    function test_ColdPattern87() public { _measure(87); }
    function test_ColdPattern88() public { _measure(88); }
    function test_ColdPattern89() public { _measure(89); }
    function test_ColdPattern90() public { _measure(90); }
    function test_ColdPattern91() public { _measure(91); }
    function test_ColdPattern92() public { _measure(92); }
    function test_ColdPattern93() public { _measure(93); }
    function test_ColdPattern94() public { _measure(94); }
}
