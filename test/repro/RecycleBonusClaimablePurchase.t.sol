// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {VmSafe} from "forge-std/Vm.sol";

/// @title RecycleBonusClaimablePurchase — the 10% claimable-recycle FLIP bonus, by payment kind
/// @notice The purchase path pays a recycle bonus (10% of the recycled claimable value, in FLIP)
///         when a buy spends >= 3 whole tickets' worth of claimable winnings — and pays NOTHING
///         on DirectEth, which cannot draw claimable on either leg (its balance reads are
///         skipped entirely). Two otherwise-identical buys — one DirectEth-funded, one
///         claimable-funded — must therefore differ in their buyer flip credit by EXACTLY
///         recycled × PRICE_COIN_UNIT / (price × 10).
/// @dev The claimable balance is fixtured directly: balancesPacked[buyer] low-128 (slot 7 map)
///      plus the matching claimablePool (slot 1, high half) and contract ETH, preserving the
///      solvency identity the purchase's pool decrement relies on.
contract RecycleBonusClaimablePurchase is DeployProtocol {
    uint256 private constant BALANCES_PACKED_SLOT = 7;
    uint256 private constant POOL_SLOT = 1; // claimablePool = bits [128,256)
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;
    uint256 private constant QTY_SCALE = 100;

    bytes32 private constant STAKE_UPDATED_SIG =
        keccak256("CoinflipStakeUpdated(address,uint24,uint256,uint256)");

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 10_000_000 ether);
    }

    function testRecycleBonusPaidOnClaimableAndNotOnDirectEth() public {
        uint256 price = game.mintPrice();
        uint256 qty = 3 * 4 * QTY_SCALE; // exactly 3 whole tickets — the bonus threshold
        uint256 cost = (price * qty) / (4 * QTY_SCALE);
        require(cost == price * 3, "fixture: cost is exactly 3 whole tickets");

        address ethBuyer = makeAddr("recycle_eth");
        address claimBuyer = makeAddr("recycle_claim");
        vm.deal(ethBuyer, cost + 1 ether);

        // Arm the claimable buyer: per-player low-128 balance + the pool total (the purchase
        // folds its per-player draw into one claimablePool decrement, which must not underflow).
        _pokeClaimable(claimBuyer, cost + 1 ether);
        _bumpClaimablePool(cost + 1 ether);

        // DirectEth buy — no claimable draw is possible, so no recycle bonus.
        vm.recordLogs();
        vm.prank(ethBuyer);
        game.purchase{value: cost}(ethBuyer, qty, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        uint256 ethCredit = _buyerStakeCredit(ethBuyer);

        // Claimable buy — the full ticket cost is recycled (balance >= cost + sentinel).
        vm.recordLogs();
        vm.prank(claimBuyer);
        game.purchase(claimBuyer, qty, 0, bytes32(0), MintPaymentKind.Claimable, false);
        uint256 claimCredit = _buyerStakeCredit(claimBuyer);

        // Identical buys, identical bulk/quest components — the only difference is the
        // recycle bonus: recycled × PRICE_COIN_UNIT / (price × 10), recycled == cost.
        uint256 expectedBonus = (cost * PRICE_COIN_UNIT) / (price * 10);
        assertGt(expectedBonus, 0, "non-vacuous bonus");
        assertEq(
            claimCredit - ethCredit,
            expectedBonus,
            "claimable-funded buy credits exactly the 10% recycle bonus over the DirectEth twin"
        );
    }

    // ---- helpers ----

    /// @dev Sum this buyer's CoinflipStakeUpdated credits from the recorded logs (the purchase
    ///      routes the buyer's flip credit through one creditFlipPair call).
    function _buyerStakeCredit(address buyer) internal returns (uint256 total) {
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].topics.length > 1 &&
                logs[i].topics[0] == STAKE_UPDATED_SIG &&
                address(uint160(uint256(logs[i].topics[1]))) == buyer
            ) {
                (uint256 amount, ) = abi.decode(logs[i].data, (uint256, uint256));
                total += amount;
            }
        }
    }

    function _pokeClaimable(address who, uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(BALANCES_PACKED_SLOT)));
        uint256 w = uint256(vm.load(address(game), slot));
        w = (w & ~uint256(type(uint128).max)) | amount;
        vm.store(address(game), slot, bytes32(w));
    }

    function _bumpClaimablePool(uint256 amount) internal {
        uint256 w = uint256(vm.load(address(game), bytes32(POOL_SLOT)));
        uint256 pool = (w >> 128) + amount;
        w = (w & type(uint128).max) | (pool << 128);
        vm.store(address(game), bytes32(POOL_SLOT), bytes32(w));
    }
}
