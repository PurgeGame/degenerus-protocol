// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title CoinflipClaimSaturation — the uint128 claim fields saturate instead of truncating
/// @notice 1. CARRY — a rolled carry above uint128 is clamped to uint128 max in the settle walk,
///                    and the preview reports the same clamped carry.
///         2. BANK  — claimableStored + newly settled winnings saturate at uint128 max on every
///                    writer: the claim, the settle-only deposit and the carry claim.
/// @dev STATE SHORTCUT: the near-maximum carry and bank are installed with vm.store into
///      playerState (slot 2: word0 = claimableStored | lastClaim << 128 | startDay << 152 |
///      enabled << 176; word1 = autoRebuyStop | autoRebuyCarry << 128). No ordinary path
///      reaches these magnitudes in a test-sized run; the stake and day result come from the
///      real credit and the GAME's processCoinflipPayouts.
contract CoinflipClaimSaturation is DeployProtocol {
    address internal constant GAME = ContractAddresses.GAME;
    uint256 internal constant STAKE = 100_000;
    uint256 internal constant MAX = type(uint128).max;

    address internal player;
    uint32 internal id;

    function setUp() public {
        _deployProtocol();
        player = makeAddr("saturation_player");
        id = _giveWalletId(player);
        _resolveDay(2, false);
    }

    function _warpToDay(uint24 d) internal {
        _setRequestedFixtureDay(d);
        vm.warp((uint256(d - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + 1);
    }

    function _resolveDay(uint24 epoch, bool win) internal {
        _warpToDay(epoch);
        uint256 w = uint256(keccak256(abi.encodePacked("saturation_word", epoch)));
        w = win ? (w | 1) : (w & ~uint256(1));
        vm.prank(GAME);
        coinflip.processCoinflipPayouts(0, w, epoch);
    }

    function _stateSlot() internal view returns (bytes32) {
        return keccak256(abi.encode(uint256(id), uint256(2)));
    }

    function _stored() internal view returns (uint256) {
        return uint128(uint256(vm.load(address(coinflip), _stateSlot())));
    }

    /// @dev Replace claimableStored, keeping the rest of word0.
    function _setStored(uint256 amount) internal {
        uint256 w0 = uint256(vm.load(address(coinflip), _stateSlot()));
        vm.store(address(coinflip), _stateSlot(), bytes32((w0 & ~MAX) | amount));
    }

    /// @dev Replace autoRebuyCarry, keeping the stop.
    function _setCarry(uint256 carry) internal {
        bytes32 slot = bytes32(uint256(_stateSlot()) + 1);
        uint256 w1 = uint256(vm.load(address(coinflip), slot));
        vm.store(address(coinflip), slot, bytes32((w1 & MAX) | (carry << 128)));
    }

    function _creditAndWin() internal {
        vm.prank(GAME);
        coinflip.creditFlip_g317(id, STAKE);
        _resolveDay(3, true);
    }

    function test_CarryClampsAtUint128() public {
        vm.prank(player);
        coinflip.setCoinflipAutoRebuy(0, true, 0);
        _setCarry(MAX - 1000);
        _creditAndWin();
        assertEq(coinflip.previewFlipBackingById(id), MAX, "preview reports the clamped carry");
        vm.prank(player);
        coinflip.claimCoinflips(0, 0);
        (, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfoById(id);
        assertEq(carry, MAX, "settled carry clamps to uint128 max");
        assertEq(_stored(), 0, "nothing banked at take-profit 0");
    }

    function test_ClaimSaturatesBank() public {
        _setStored(MAX - 5);
        _creditAndWin();
        vm.prank(player);
        coinflip.claimCoinflips(0, 0);
        assertEq(_stored(), MAX, "claim: bank saturates");
    }

    function test_SettleOnlyDepositSaturatesBank() public {
        _setStored(MAX - 5);
        _creditAndWin();
        vm.prank(player);
        coinflip.depositCoinflip(0, 0);
        assertEq(_stored(), MAX, "deposit settle: bank saturates");
    }

    function test_CarryClaimSaturatesBank() public {
        vm.prank(player);
        coinflip.setCoinflipAutoRebuy(0, true, 1);
        _setStored(MAX - 5);
        _creditAndWin();
        vm.prank(player);
        coinflip.claimCoinflipCarry(0, 0);
        assertEq(_stored(), MAX, "carry claim: take-profit bank saturates");
    }
}
