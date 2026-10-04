// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Coinflip} from "../../contracts/Coinflip.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {VaultBafRig} from "../repro/VaultBafSettlement.t.sol";

/// @title VaultBafSettleGas — cold cost of the vault settlement the x0 seal runs.
///
/// @notice The seal settles the vault through `depositCoinflip(VAULT, 0)`: one claim walk over
///         the days since its last settlement, at most COIN_CLAIM_DAYS (365) per call. Its gas is
///         the BAF_VAULT_SETTLE reserve that every seal-capable purchase leg keeps in its tail on
///         an x0 purchase day.
///         - Settle call, cold, every walked day staked and resolved (one loss, so the WWXRP
///           loss mint fires too), auto-rebuy with a carry-keeping stop and auto-rebuy off: a
///           typical 10-level gap (70 days) and the full 365-day window (a stall-length gap).
///           Each stays under BAF_VAULT_SETTLE.
///         - The real sealing chunk, cold: the runDailyPhase call that finishes the latch day's
///           purchase legs and seals, in a turbo game (short gap) and in a slow game whose
///           vault walks the full 365-day window, each beside a pre-settled control. Each chunk
///           stays at or under 10M.

/// @dev Writes the vault's coinflip history through Coinflip's own lane helpers.
contract VaultSettleSeeder is Coinflip {
    function seedVaultHistory(uint24 latest, uint24 gap, bool rebuy) external {
        address v = ContractAddresses.VAULT;
        PlayerCoinflipState storage s = playerState[v];
        uint24 last = latest - gap;
        s.claimableStored = 0;
        s.lastClaim = last;
        s.autoRebuyStartDay = rebuy ? last : 0;
        s.autoRebuyEnabled = rebuy;
        // A stop that never divides a payout: every win banks a slice and rolls a carry.
        s.autoRebuyStop = rebuy ? 7 ether : 0;
        s.autoRebuyCarry = 0;
        uint24 lossDay = last + gap / 2;
        for (uint24 d = last + 1; d <= latest; ++d) {
            _setFlipStake(d, v, 5_000 ether);
            _storeDayResult(d, 150, d != lossDay);
        }
        flipsClaimableDay = latest;
    }
}

/// @dev Production facade plus native seams for the daily cycle after the request.
contract VaultSettleHost is DegenerusGame {
    function publishOnly() external {
        _native(ContractAddresses.GAME_RNG_MODULE, abi.encodeWithSignature("publishRng()"));
    }

    function ticketsOnly() external returns (bool done) {
        uint24 anchor = !jackpotPhaseFlag && lastPurchaseDay && rngLockedFlag ? level : level + 1;
        MineFlipGas.Result memory result = abi.decode(_native(ContractAddresses.GAME_TICKET_MODULE,
            abi.encodeWithSignature("runTicketWork(uint24,uint256)", anchor, uint256(9_000_000))),
            (MineFlipGas.Result));
        done = result.done;
        if (done) {
            // Identical normalization to Miner after a completed native read.
            ticketsFullyProcessed = true;
            _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0);
        }
    }

    function applyOnly() external {
        _native(ContractAddresses.GAME_ADVANCE_MODULE, abi.encodeWithSignature("applyDailyWord()"));
    }

    function dailyWith(uint256 allowance) external returns (MineFlipGas.Result memory) {
        return abi.decode(_native(ContractAddresses.GAME_ADVANCE_MODULE,
            abi.encodeWithSignature("runDailyPhase(uint256)", allowance)), (MineFlipGas.Result));
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

abstract contract VaultSettleCallGas is DeployProtocol {
    uint24 internal constant LATEST = 400;

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
        vm.prank(address(game));
        coinflip.depositCoinflip(ContractAddresses.VAULT, 0);
        uint256 used = vm.lastCallGas().gasTotalUsed;
        emit log_named_uint("vault_settle_call_days", _gap());
        emit log_named_uint("vault_settle_call_gas", used);
        uint256 state = uint256(vm.load(address(coinflip), keccak256(abi.encode(ContractAddresses.VAULT, uint256(2)))));
        assertEq(uint24(state >> 128), LATEST, "the walk settles every resolved day");
        assertLe(used, GasBounds.BAF_VAULT_SETTLE, "the settle call fits its declared reserve");
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

contract VaultSettleCallGas365Rebuy is VaultSettleCallGas {
    function _gap() internal pure override returns (uint24) { return 365; }
    function _rebuy() internal pure override returns (bool) { return true; }
}

contract VaultSettleCallGas365Plain is VaultSettleCallGas {
    function _gap() internal pure override returns (uint24) { return 365; }
    function _rebuy() internal pure override returns (bool) { return false; }
}

// -------------------------------------------------------------------------
// The real sealing chunk
// -------------------------------------------------------------------------

abstract contract VaultSealChunkGas is VaultBafRig {
    uint256 internal constant ALLOWANCE = 9_000_000;
    uint256 internal constant CHUNK_CAP = 10_000_000;

    uint24 internal latchDay;
    uint24 internal settledAt;

    /// @dev Slow game: level 0 idles 240 days and each of levels 1-9 holds 14 purchase days.
    ///      Automatic craps funding can settle the vault along the way, so seed its worst-case
    ///      claim backlog immediately before the measured seal to keep the full-window gas
    ///      measurement deterministic.
    function _slow() internal pure virtual returns (bool);
    /// @dev Control: settle the vault's available results before measuring the seal.
    function _presettle() internal pure virtual returns (bool);
    /// @dev The vault rides auto-rebuy with a stop that keeps a carry on every win.
    function _rebuy() internal pure virtual returns (bool) {
        return false;
    }

    function _holdFor(uint24 lvl) internal view override returns (uint256) {
        if (!_slow()) return super._holdFor(lvl);
        return lvl == 0 ? 240 : (lvl < 9 ? 14 : 0);
    }

    function setUp() public override {
        super.setUp();
        vm.pauseGasMetering();
        _settleToday();
        if (_slow()) {
            _runFullDay();
            vm.prank(POKER);
            coinflip.depositCoinflip(VAULT, 0);
        }
        if (_rebuy()) {
            vm.prank(VAULT);
            coinflip.setCoinflipAutoRebuy(address(0), true, 7 ether);
        }
        uint24 pokedAt = _lastClaim(VAULT);
        _driveToEve(9);
        latchDay = game.currentDayView() + 1;
        _stageDay();
        if (!_slow()) {
            require(_lastClaim(VAULT) == pokedAt, "harness: no intermediate vault settlement");
        }
        for (uint256 pokes; !_slow() && _presettle() && _lastClaim(VAULT) + 1 < latchDay; ++pokes) {
            require(pokes < 4, "harness: the control never settled");
            vm.prank(POKER);
            coinflip.depositCoinflip(VAULT, 0);
        }
        // The latch day up to its request, then the native daily cycle.
        simTime += 1 days + 1;
        vm.warp(simTime);
        uint256 before = mockVRF.lastRequestId();
        for (uint256 calls; mockVRF.lastRequestId() == before; ++calls) {
            require(calls < 64, "harness: the latch-day request stalled");
            game.mineFlip{gas: 12_000_000}();
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
            bytes memory original = address(coinflip).code;
            vm.etch(address(coinflip), type(VaultSettleSeeder).runtimeCode);
            VaultSettleSeeder(address(coinflip)).seedVaultHistory(latchDay, 365, _rebuy());
            vm.etch(address(coinflip), original);
            if (_presettle()) {
                vm.prank(POKER);
                coinflip.depositCoinflip(VAULT, 0);
            }
        }
        emit log_named_uint("vault_days_unsettled", latchDay - _lastClaim(VAULT));
        // One claim walks at most 365 days; compute the endpoint from the actual pre-seal state.
        settledAt = _rebuy() && latchDay - _lastClaim(VAULT) > 365 ? _lastClaim(VAULT) + 365 : latchDay;
        vm.resumeGasMetering();
    }

    function _latched() internal view returns (bool) {
        (, , bool lastPurchaseDay_, , ) = game.purchaseInfo();
        return lastPurchaseDay_;
    }

    /// @dev The first call of the test: the latch day's last purchase leg and its seal, cold.
    function test_SealChunkCold() public {
        VaultSettleHost(payable(address(game))).dailyWith(ALLOWANCE);
        uint256 used = vm.lastCallGas().gasTotalUsed;
        emit log_named_uint("vault_seal_chunk_gas", used);
        assertTrue(_latched(), "the measured call seals the latch day");
        (uint24 armed, , ) = coinflip.bafDrawInfo();
        assertEq(armed, latchDay + 1, "and arms the BAF draw");
        assertEq(_lastClaim(VAULT), settledAt, "and settles the vault's claim window");
        assertLe(used, CHUNK_CAP, "the sealing chunk stays at or under 10M");
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
    function _slow() internal pure override returns (bool) { return true; }
    function _presettle() internal pure override returns (bool) { return false; }
    function _rebuy() internal pure override returns (bool) { return true; }
}

contract VaultSealChunkGasSlowRebuySettled is VaultSealChunkGas {
    function _slow() internal pure override returns (bool) { return true; }
    function _presettle() internal pure override returns (bool) { return true; }
    function _rebuy() internal pure override returns (bool) { return true; }
}
