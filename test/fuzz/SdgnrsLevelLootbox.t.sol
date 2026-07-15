// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title SdgnrsLevelLootbox -- the sDGNRS level-start lootbox top-up.
/// @notice Verifies the once-per-level sDGNRS bonus stamped at the START of the afking process
///         STAGE (GameAfkingModule.processSubscriberStage, before the per-sub loop). On the first
///         STAGE pass of each new level, sDGNRS's daily box is resized to
///         max(mp, min(5% of claimable, 6 ETH)), funded purely from claimable; the latch
///         `_sdgnrsBonusLevel` makes it fire once per level. The non-vacuity proof is the box
///         AMOUNT itself: a 5%-of-100-ETH box is 5000 milli-ETH, hugely larger than the flat daily
///         box (mp ~ a few milli-ETH), so a passing equality proves the bonus actually fired.
///         Test-only: ZERO contracts/*.sol mutation.
contract SdgnrsLevelLootbox is DeployProtocol {
    uint256 private constant GAME_CLAIMABLE_SLOT = 7; // balancesPacked root (low-128 = claimableWinnings)
    uint256 private constant CLAIMABLE_POOL_SLOT = 1; // claimablePool uint128 @ slot 1, high-128
    uint256 private constant SUBOF_SLOT = 54; // _subOf mapping root (address => Sub, one packed slot)
    uint256 private constant CURSOR_SLOT = 58; // cursor slot; _sdgnrsBonusLevel uint24 @ byte 25
    uint256 private constant SDGNRS_BONUS_OFFBYTES = 25;
    uint256 private constant MINTPACKED_SLOT = 9; // mintPacked_ root (deity bit @ 184)
    uint256 private constant DEITY_SHIFT = 184;
    uint256 private constant OFF_AMOUNT = 7; // Sub.amount (milli-ETH) byte offset
    uint256 private constant LR_ETH_SCALE = 1e15; // milli-ETH (the Sub.amount unit)
    uint256 private constant LEVEL_OFFBYTES = 12; // `level` uint24 @ slot 0, byte 12

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;
    uint256 private _t;

    function setUp() public {
        _deployProtocol();
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
    }

    // =====================================================================================
    // The bonus sizing (the core non-vacuity proof)
    // =====================================================================================

    /// @notice 5% of claimable (below the 6-ETH cap, above the mp floor): claimable 100 ETH -> a
    ///         5-ETH box == 5000 milli-ETH. A flat daily box would be a few milli-ETH, so this
    ///         equality is the proof the level-start bonus fired.
    function test_SizingFivePercentOfClaimable() public {
        uint256 cl = 100 ether;
        _setClaimable(ContractAddresses.SDGNRS, cl);
        _fireBonus(0x5D60001);
        assertGe(_currentLevel(), 1, "fixture: the STAGE ran at a real level (>=1)");

        uint256 amountMilli = _subField(ContractAddresses.SDGNRS, OFF_AMOUNT, 24);
        assertEq(
            amountMilli,
            (cl / 20) / LR_ETH_SCALE,
            "sDGNRS level box == 5% of claimable (milli-ETH)"
        );
    }

    /// @notice 5% of claimable above the 6-ETH cap clamps to 6 ETH == 6000 milli-ETH.
    function test_CapAtSixEth() public {
        uint256 cl = 200 ether; // 5% == 10 ETH > 6 ETH cap
        _setClaimable(ContractAddresses.SDGNRS, cl);
        _fireBonus(0x5D60002);
        assertGe(_currentLevel(), 1, "fixture: the STAGE ran at a real level (>=1)");

        uint256 amountMilli = _subField(ContractAddresses.SDGNRS, OFF_AMOUNT, 24);
        assertEq(
            amountMilli,
            (6 ether) / LR_ETH_SCALE,
            "sDGNRS level box clamps to the 6-ETH cap"
        );
    }

    // =====================================================================================
    // Once-per-level latch + funded-from-claimable
    // =====================================================================================

    /// @notice After the bonus fires the latch equals the current level, so the level-gate
    ///         (`currentLevel > _sdgnrsBonusLevel`) is false for the rest of the level: no re-fire.
    function test_OncePerLevel_LatchEqualsLevel() public {
        _setClaimable(ContractAddresses.SDGNRS, 100 ether);
        _fireBonus(0x5D60003);
        uint24 lvl = _currentLevel();
        assertGe(lvl, 1, "fixture: the STAGE ran at a real level (>=1)");
        assertEq(
            _sdgnrsBonusLevel(),
            lvl,
            "latch stamped to the current level (the once-per-level gate is now closed)"
        );
    }

    /// @notice The box is funded purely from claimable. sDGNRS holds ZERO afkingFunding, so a
    ///         5-ETH box (ethValue would have to come from afkingFunding) could only be funded by
    ///         the claimable leg - the buy delivers, proving claimable-only funding (ethValue == 0,
    ///         claimableUse == box). A non-claimable-funded box would have skipped on the funding
    ///         gate and left the small daily box instead.
    function test_FundedFromClaimable() public {
        uint256 cl = 100 ether;
        _setClaimable(ContractAddresses.SDGNRS, cl);
        assertEq(
            game.afkingFundingOf(ContractAddresses.SDGNRS),
            0,
            "fixture: sDGNRS has no afkingFunding - any delivered box is claimable-funded"
        );
        _fireBonus(0x5D60004);
        assertGe(_currentLevel(), 1, "fixture: the STAGE ran at a real level (>=1)");

        assertEq(
            _subField(ContractAddresses.SDGNRS, OFF_AMOUNT, 24),
            (cl / 20) / LR_ETH_SCALE,
            "the 5-ETH box delivered with zero afkingFunding => funded from claimable"
        );
    }

    // =====================================================================================
    // Harness (ported from V56FreezeSolvency + AfKingFundingWaterfall; test-only)
    // =====================================================================================

    /// @dev Set the level to 1 (a real level, so the bonus gate fires) and run ONE new-day STAGE.
    ///      A single settle is deliberate: a second day at the same level would re-stamp sDGNRS's
    ///      box with its NORMAL daily box, masking the level-start bonus we are asserting.
    function _fireBonus(uint256 vrfWord) internal {
        _setLevel(1);
        _t += 1 days;
        vm.warp(_t);
        _settleGame(vrfWord);
    }

    /// @dev Field-surgical write of `level` (slot 0, byte 12, uint24), preserving every other
    ///      slot-0 flag/field. Mirrors V56AfkingGasMarginal._setLevel.
    function _setLevel(uint24 lvl) internal {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        s0 &= ~(uint256(0xFFFFFF) << (LEVEL_OFFBYTES * 8));
        s0 |= (uint256(lvl) & 0xFFFFFF) << (LEVEL_OFFBYTES * 8);
        vm.store(address(game), bytes32(uint256(0)), bytes32(s0));
    }

    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.advanceGame();
            _fulfillPending(vrfWord);
        }
    }

    function _fulfillPending(uint256 vrfWord) internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
            if (!fulfilled) {
                mockVRF.fulfillRandomWords(reqId, vrfWord);
                _lastFulfilledReqId = reqId;
            }
        }
    }

    /// @dev Force `who`'s claimableWinnings (slot 7 low-128) to `amount`, preserving the high-128
    ///      half, AND credit `claimablePool` (slot 1, high-128) in tandem so the SOLVENCY-01
    ///      invariant holds (otherwise a claimable-funded buy underflows the pool `-=`).
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
        if (amount >= prev) {
            pool += uint128(amount - prev);
        } else {
            uint128 dec = uint128(prev - amount);
            pool = pool >= dec ? pool - dec : 0;
        }
        p1 = (p1 & mask128) | (uint256(pool) << 128);
        vm.store(address(game), s1, bytes32(p1));
    }

    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBOF_SLOT))))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    function _claimableOf(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(GAME_CLAIMABLE_SLOT))))) & ((uint256(1) << 128) - 1);
    }

    function _sdgnrsBonusLevel() internal view returns (uint24) {
        return uint24(uint256(vm.load(address(game), bytes32(uint256(CURSOR_SLOT)))) >> (SDGNRS_BONUS_OFFBYTES * 8));
    }

    function _currentLevel() internal view returns (uint24) {
        return uint24(uint256(vm.load(address(game), bytes32(uint256(0)))) >> (LEVEL_OFFBYTES * 8));
    }
}
