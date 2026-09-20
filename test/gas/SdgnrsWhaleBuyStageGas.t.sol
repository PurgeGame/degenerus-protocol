// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title SdgnrsWhaleBuyStageGas -- calibration of `SUB_STAGE_SDGNRS_WHALE_WEIGHT`.
/// @notice Measures the COLD incremental gas of sDGNRS's automatic whale purchase inside the
///         afking process STAGE (the first advanceGame call of a new day), for 0 / 5 / 10 / 100
///         paid passes, in the state the buy really fires in: the stored level just promoted
///         (here set directly), genesis deity coverage on levels 1..100 (so the span's first 99
///         levels are nonzero-to-nonzero owed updates) and the far-end level unregistered for
///         sDGNRS (the ONE fresh owner registration + lane append). `vm.cool` re-colds every
///         contract the purchase touches right before the measured call.
///
///         The bound this pins: the purchase's incremental gas must not exceed its charged weight
///         times the STAGE's ~3.4k-gas weight unit. The STAGE charges the weight against the same
///         2,500-unit budget the subscriber loop draws from, so a purchase under `weight x unit`
///         keeps every chunk composition inside the existing <10M proof (V56AfkingGasMarginal,
///         AdvanceStageWorstCaseGas): the purchase displaces at least as many subscriber units as
///         it costs. Test-only: ZERO contracts/*.sol mutation.
contract SdgnrsWhaleBuyStageGas is DeployProtocol {
    uint256 private constant GAME_CLAIMABLE_SLOT = 7;
    uint256 private constant CLAIMABLE_POOL_SLOT = 1;
    uint256 private constant CURSOR_SLOT = 56;
    uint256 private constant SDGNRS_BONUS_OFFBYTES = 25;
    uint256 private constant LEVEL_OFFBYTES = 12;

    /// @dev Mirrors GameAfkingModule.SUB_STAGE_SDGNRS_WHALE_WEIGHT (private there).
    uint256 private constant WHALE_WEIGHT = 700;
    /// @dev The STAGE's weight unit (GameAfkingModule.SUB_STAGE_LOOTBOX_WEIGHT = 10 ~= 34k gas).
    uint256 private constant GAS_PER_WEIGHT_UNIT = 3_400;
    /// @dev Repository hard ceiling for any single advance transaction.
    uint256 private constant HARD_CEILING = 16_700_000;

    uint256 private _t;

    function setUp() public {
        _deployProtocol();
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
    }

    function test_WhalePurchaseIncrement_FitsChargedWeight() public {
        uint256 snap = vm.snapshotState();
        uint256 g0 = _measureFirstAdvanceOfDay(10 ether, false);
        vm.revertToState(snap);
        uint256 g5 = _measureFirstAdvanceOfDay(80 ether, true);
        vm.revertToState(snap);
        uint256 g10 = _measureFirstAdvanceOfDay(160 ether, true);
        vm.revertToState(snap);
        uint256 g100 = _measureFirstAdvanceOfDay(2_000 ether, true);

        emit log_named_uint("stage call, no purchase (cold)", g0);
        emit log_named_uint("stage call, 5 passes (cold)", g5);
        emit log_named_uint("stage call, 10 passes (cold)", g10);
        emit log_named_uint("stage call, 100 passes (cold)", g100);
        emit log_named_uint("increment, 5 passes", g5 - g0);
        emit log_named_uint("increment, 10 passes", g10 - g0);
        emit log_named_uint("increment, 100 passes", g100 - g0);
        emit log_named_uint("charged weight x unit", WHALE_WEIGHT * GAS_PER_WEIGHT_UNIT);

        assertGt(g100, g0, "the purchase did real work");
        assertLe(g100 - g0, WHALE_WEIGHT * GAS_PER_WEIGHT_UNIT, "100-pass increment <= charged weight x 3.4k");
        assertLt(g100, HARD_CEILING, "the whole stage call stays under the hard ceiling");
    }

    /// @dev Level 4 (standard price), sDGNRS funded, a new day: cool everything and bracket the
    ///      first advanceGame call, which runs the day's reset + STAGE (+ the RNG request).
    ///      Non-vacuity: with `expectBuy` the latch must flip inside that call.
    function _measureFirstAdvanceOfDay(uint256 claimable, bool expectBuy) internal returns (uint256 used) {
        _setLevel(4);
        _setClaimable(ContractAddresses.SDGNRS, claimable);
        _t += 1 days;
        vm.warp(_t);
        require(game.advanceDue(), "fixture: advance due");
        require(_sdgnrsBonusLevel() == 0, "fixture: level 4's attempt not yet spent");
        uint256 claimable0 = _claimableOf(ContractAddresses.SDGNRS);

        vm.cool(address(game));
        vm.cool(address(sdgnrs));
        vm.cool(address(affiliate));
        vm.cool(address(coinflip));
        vm.cool(address(crapsBattle));
        vm.cool(address(afkingSubToken));
        uint256 before = gasleft();
        game.advanceGame();
        used = before - gasleft();

        // The attempt latches the level either way; the claimable debit tells buy from no-buy.
        require(_sdgnrsBonusLevel() == 4, "fixture: the attempt ran in the measured call");
        uint256 debit = claimable0 - _claimableOf(ContractAddresses.SDGNRS);
        if (expectBuy) {
            require(debit >= 5 * 4 ether, "fixture: the purchase fired in the measured call");
        } else {
            require(debit < 1 ether, "fixture: no purchase in the baseline (daily box only)");
        }
    }

    function _setLevel(uint24 lvl) internal {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        s0 &= ~(uint256(0xFFFFFF) << (LEVEL_OFFBYTES * 8));
        s0 |= (uint256(lvl) & 0xFFFFFF) << (LEVEL_OFFBYTES * 8);
        vm.store(address(game), bytes32(uint256(0)), bytes32(s0));
    }

    function _setClaimable(address who, uint256 amount) internal {
        uint256 mask128 = (uint256(1) << 128) - 1;
        bytes32 cwSlot = keccak256(abi.encode(who, uint256(GAME_CLAIMABLE_SLOT)));
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

    function _claimableOf(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(GAME_CLAIMABLE_SLOT))))) & ((uint256(1) << 128) - 1);
    }

    function _sdgnrsBonusLevel() internal view returns (uint24) {
        return uint24(uint256(vm.load(address(game), bytes32(uint256(CURSOR_SLOT)))) >> (SDGNRS_BONUS_OFFBYTES * 8));
    }
}
