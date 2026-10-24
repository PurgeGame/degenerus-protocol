// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {NativeGasExport} from "../helpers/NativeGasExport.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {GlamsterdamReprice} from "../helpers/GlamsterdamReprice.sol";

/// @title SdgnrsWhaleBuyStageGas -- calibration of the sDGNRS whale purchase checkpoint.
/// @notice Measures the COLD incremental gas of sDGNRS's automatic whale purchase inside the
///         afking process STAGE (the first mineFlip call of a new day), for 0 / 5 / 10 / 100 /
///         1,000 paid passes (1,000 = the 200-group cap), with the Degenesis AFKing top-up that
///         precedes the purchase forced to write, in the state the buy really fires in: the stored level just promoted
///         (here set directly), genesis deity coverage on levels 1..100 (so the span's first 99
///         levels are nonzero-to-nonzero owed updates) and the far-end level unregistered for
///         sDGNRS (the ONE fresh owner registration + lane append). `vm.cool` re-colds every
///         contract the purchase touches right before the measured call.
///
///         The bound this pins: the purchase is its own checkpoint, admitted only when the
///         allowance covers its declared bound `MineFlipGasBounds.SUBSCRIBER_WHALE_GAS` (the
///         engine's gas bounds replaced the subscriber stage's weight units), so its incremental
///         gas through the real keeper call must stay inside that bound, itself inside the 10M
///         realistic chunk limit. Whole keeper calls are budgeted by their allowance and only
///         reported. Test-only: ZERO contracts/*.sol mutation.
contract SdgnrsWhaleBuyStageGas is DeployProtocol, NativeGasExport {
    uint256 private constant GAME_CLAIMABLE_SLOT = GameSlots.BALANCES_PACKED;
    uint256 private constant CLAIMABLE_POOL_SLOT = GameSlots.CLAIMABLE_POOL;
    uint256 private constant CURSOR_SLOT = GameSlots.SUB_CURSOR;
    uint256 private constant SDGNRS_BONUS_OFFBYTES = 17;
    uint256 private constant LEVEL_OFFBYTES = 12;

    uint256 private constant TICKET_QUEUE_SLOT = GameSlots.TICKET_QUEUE;
    uint256 private constant TICKET_PENDING_SLOT = GameSlots.TICKET_PENDING;
    /// @dev A realistic keeper allowance for the measured call.
    uint256 private constant KEEPER_ALLOWANCE = 10_000_000;

    uint256 private _t;
    /// @dev State-inclusive Glamsterdam total of the last measured call.
    uint256 internal _lastRepriced;

    function setUp() public {
        _deployProtocol();
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
    }

    function test_WhalePurchaseIncrement_FitsChargedWeight() public {
        uint256 snap = vm.snapshotState();
        uint256 g0 = _measureFirstAdvanceOfDay(10 ether, TOP_UP_TARGET, 0);
        vm.revertToState(snap);
        uint256 g5 = _measureFirstAdvanceOfDay(80 ether + TOP_UP_TARGET, 0, 5);
        vm.revertToState(snap);
        uint256 g10 = _measureFirstAdvanceOfDay(160 ether + TOP_UP_TARGET, 0, 10);
        vm.revertToState(snap);
        uint256 g100 = _measureFirstAdvanceOfDay(1_600 ether + TOP_UP_TARGET, 0, 100);
        vm.revertToState(snap);
        uint256 g1000 = _measureFirstAdvanceOfDay(16_000 ether + TOP_UP_TARGET, 0, 1000);
        vm.revertToState(snap);
        uint256 r0;
        uint256 r100;
        uint256 r1000;
        uint256 gCap;
        {
            vm.revertToState(snap);
            _measureFirstAdvanceOfDay(10 ether, TOP_UP_TARGET, 0);
            r0 = _lastRepriced;
            vm.revertToState(snap);
            _measureFirstAdvanceOfDay(1_600 ether + TOP_UP_TARGET, 0, 100);
            r100 = _lastRepriced;
            vm.revertToState(snap);
            _measureFirstAdvanceOfDay(16_000 ether + TOP_UP_TARGET, 0, 1000);
            r1000 = _lastRepriced;
            vm.revertToState(snap);
            gCap = _measureFirstAdvanceOfDay(1_000_000 ether, 0, 1000);
        }
        emit log_named_uint("repriced increment incl. state gas, 100 passes", r100 - r0);
        emit log_named_uint("repriced increment incl. state gas, 1,000 passes", r1000 - r0);
        assertLe(r1000 - r0, GasBounds.SUBSCRIBER_WHALE_GAS, "state-inclusive 1,000-pass increment <= bound");

        emit log_named_uint("stage call, no purchase (cold)", g0);
        emit log_named_uint("stage call, 5 passes (cold)", g5);
        emit log_named_uint("stage call, 10 passes (cold)", g10);
        emit log_named_uint("stage call, 100 passes (cold)", g100);
        emit log_named_uint("stage call, 1,000 passes (cold)", g1000);
        emit log_named_uint("increment, 5 passes", g5 - g0);
        emit log_named_uint("increment, 10 passes", g10 - g0);
        emit log_named_uint("increment, 100 passes", g100 - g0);
        emit log_named_uint("increment, 1,000 passes", g1000 - g0);
        emit log_named_uint("increment, 1,000,000 ETH claimable (capped at 1,000)", gCap - g0);
        emit log_named_uint("declared whale checkpoint bound", GasBounds.SUBSCRIBER_WHALE_GAS);

        assertGt(g1000, g0, "the purchase did real work");
        assertLe(g100 - g0, GasBounds.SUBSCRIBER_WHALE_GAS, "100-pass increment <= declared whale checkpoint bound");
        assertLe(g1000 - g0, GasBounds.SUBSCRIBER_WHALE_GAS, "1,000-pass increment <= declared whale checkpoint bound");
        assertLe(gCap - g0, GasBounds.SUBSCRIBER_WHALE_GAS, "capped increment <= declared whale checkpoint bound");
        assertLe(GasBounds.SUBSCRIBER_WHALE_GAS + GasBounds.SUBSCRIBER_TAIL_GAS, uint256(10_000_000),
            "whale checkpoint inside the realistic chunk limit");
    }

    uint256 private constant TOP_UP_TARGET = 10 ether;
    bytes32 private constant AFKING_DELIVERED_SIG = keccak256("AfkingDelivered(uint32,uint256)");

    /// @dev Level 4 (standard price), sDGNRS funded, a new day: cool everything and bracket the
    ///      first mineFlip call, which runs the day's reset + STAGE (+ the RNG request). An AFKing
    ///      balance below the target forces the top-up write. Non-vacuity: the latch flips inside
    ///      that call and the claimable debit equals the top-up plus exactly `passes` passes.
    function _measureFirstAdvanceOfDay(uint256 claimable, uint256 afking, uint256 passes)
        internal
        returns (uint256 used)
    {
        bool expectBuy = passes != 0;
        _setLevel(4);
        _retireSkippedLevels();
        _setClaimable(ContractAddresses.SDGNRS, claimable);
        _setAfking(ContractAddresses.SDGNRS, afking);
        _t += 1 days;
        vm.warp(_t);
        require(game.advanceDue(), "fixture: advance due");
        require(_sdgnrsBonusLevel() == 0, "fixture: level 4's attempt not yet spent");
        uint256 claimable0 = _claimableOf(ContractAddresses.SDGNRS);

        uint256 snapshot = vm.snapshotState();
        vm.cool(address(game));
        vm.cool(address(sdgnrs));
        vm.cool(address(affiliate));
        vm.cool(address(coinflip));
        vm.cool(address(crapsBattle));
        vm.cool(address(afkingSubToken));
        // A realistic allowance succeeds; the engine keeps admitting chunks while it lasts.
        vm.recordLogs();
        vm.startStateDiffRecording();
        uint256 before = gasleft();
        game.mineFlip{gas: KEEPER_ALLOWANCE}(0);
        used = before - gasleft();
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        GlamsterdamReprice.Result memory r = GlamsterdamReprice.reprice(used, accesses, address(game));
        _lastRepriced = r.glamsterdamExec + r.stateGas;

        // The attempt latches the level either way; the claimable debit tells buy from no-buy.
        require(_sdgnrsBonusLevel() == 4, "fixture: the attempt ran in the measured call");
        // sDGNRS's own daily delivery in the same call spends claimable first; take it out.
        uint256 debit = claimable0 - _claimableOf(ContractAddresses.SDGNRS) - _sdgnrsDelivered(vm.getRecordedLogs());
        if (expectBuy) {
            uint256 topUp = afking >= TOP_UP_TARGET ? 0 : TOP_UP_TARGET - afking;
            require(debit == topUp + passes * 4 ether, "fixture: the exact purchase fired in the measured call");
        } else {
            require(debit < 1 ether, "fixture: no purchase in the baseline (daily box only)");
        }
        if (bytes(vm.envOr("STORAGE_REUSE_EXPORT", string(""))).length != 0) {
            uint256 repriced = _lastRepriced;
            assertTrue(vm.revertToState(snapshot));
            this.exportNativeFixture(string.concat("subscriber_whale_", vm.toString(passes)), address(this),
                address(game), abi.encodeCall(game.mineFlip, (uint32(0))));
            game.mineFlip{gas: KEEPER_ALLOWANCE}(0);
            _lastRepriced = repriced;
        }
    }

    function _sdgnrsDelivered(VmSafe.Log[] memory logs) internal view returns (uint256 weiIn) {
        bytes32 id = bytes32(uint256(game.walletIdOf_g3120(ContractAddresses.SDGNRS)));
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length == 2
                && logs[i].topics[0] == AFKING_DELIVERED_SIG && logs[i].topics[1] == id) {
                weiIn += uint128(abi.decode(logs[i].data, (uint256)));
            }
        }
    }

    function _setLevel(uint24 lvl) internal {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        s0 &= ~(uint256(0xFFFFFF) << (LEVEL_OFFBYTES * 8));
        s0 |= (uint256(lvl) & 0xFFFFFF) << (LEVEL_OFFBYTES * 8);
        vm.store(address(game), bytes32(uint256(0)), bytes32(s0));
    }

    /// @dev Setting the level directly skips the drains of levels 1..4: release their near queue
    ///      roots (both slot sides) and bootstrap far-future roots, whose recycled physical roots the
    ///      purchase binds for levels 5..104, and retire the genesis holders' near cohorts (a parity
    ///      lane still holding a skipped level refuses a new level's write with E()).
    function _retireSkippedLevels() internal {
        for (uint24 lvl = 1; lvl <= 4; ++lvl) {
            uint24 nearRoot = ((lvl - 1) & 1) + 1;
            uint24[3] memory roots = [nearRoot, nearRoot | 0x800000, lvl | 0x400000];
            for (uint256 k; k < 3; ++k) {
                vm.store(address(game), keccak256(abi.encode(uint256(roots[k]), TICKET_QUEUE_SLOT)), bytes32(0));
            }
        }
        address[2] memory holders = [ContractAddresses.SDGNRS, ContractAddresses.VAULT];
        for (uint256 i; i < 2; ++i) {
            uint32 id = game.walletIdOf_g3120(holders[i]);
            if (id != 0) vm.store(address(game), keccak256(abi.encode(uint256(id), TICKET_PENDING_SLOT)), bytes32(0));
        }
    }

    function _setClaimable(address who, uint256 amount) internal {
        uint256 mask128 = (uint256(1) << 128) - 1;
        bytes32 cwSlot = keccak256(abi.encode(uint256(game.walletIdOf_g3120(who)), uint256(GAME_CLAIMABLE_SLOT)));
        uint256 packed = uint256(vm.load(address(game), cwSlot));
        uint256 prev = packed & mask128;
        uint256 high = packed & ~mask128;
        vm.store(address(game), cwSlot, bytes32(high | (amount & mask128)));
        bytes32 s1 = bytes32(uint256(CLAIMABLE_POOL_SLOT));
        uint256 p1 = uint256(vm.load(address(game), s1));
        uint128 pool = uint128(p1 >> 128);
        if (amount >= prev) pool += uint128(amount - prev);
        else {
            uint128 dec = uint128(prev - amount);
            pool = pool >= dec ? pool - dec : 0;
        }
        vm.store(address(game), s1, bytes32((p1 & mask128) | (uint256(pool) << 128)));
    }

    /// @dev Set `who`'s AFKing half of its balance word, moving claimablePool with it.
    function _setAfking(address who, uint256 amount) internal {
        uint256 mask128 = (uint256(1) << 128) - 1;
        bytes32 cwSlot = keccak256(abi.encode(uint256(game.walletIdOf_g3120(who)), uint256(GAME_CLAIMABLE_SLOT)));
        uint256 packed = uint256(vm.load(address(game), cwSlot));
        uint256 prev = packed >> 128;
        vm.store(address(game), cwSlot, bytes32((packed & mask128) | (amount << 128)));
        bytes32 s1 = bytes32(uint256(CLAIMABLE_POOL_SLOT));
        uint256 p1 = uint256(vm.load(address(game), s1));
        uint256 pool = (p1 >> 128) + amount - prev;
        vm.store(address(game), s1, bytes32((p1 & mask128) | (pool << 128)));
    }

    function _claimableOf(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(game.walletIdOf_g3120(who)), uint256(GAME_CLAIMABLE_SLOT))))) & ((uint256(1) << 128) - 1);
    }

    function _sdgnrsBonusLevel() internal view returns (uint24) {
        return uint24(uint256(vm.load(address(game), bytes32(uint256(CURSOR_SLOT)))) >> (SDGNRS_BONUS_OFFBYTES * 8));
    }
}
