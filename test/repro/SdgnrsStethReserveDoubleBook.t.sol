// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";

/// @notice Local mirror of the coinflip player surface so the submit-time FLIP leg is mocked to a
///         no-op, keeping the focus on the ETH/stETH redemption reserve identity.
interface IFlipCoinflipPlayerMock {
    function previewClaimCoinflips(address player) external view returns (uint256 mintable);
    function redeemableFlipBacking() external returns (uint256 backing);
    function withdrawRedeemedFlip(uint256 base) external;
}

/// @title SdgnrsStethReserveDoubleBook — repro for the per-increment custody-leg admission in
///        pullRedemptionReserve.
/// @notice In the ETH-short regime the reserve pull falls to the custody-backed leg, which admits
///         each reservation against sDGNRS's stETH balance alone with no state change — so the same
///         custody can be counted for two burns. The reservation base, however, is sized against
///         ethBal + stethBal + claimableEth. Two same-day burns each individually covered can
///         together reserve more than sDGNRS holds (pendingRedemptionEthValue > in-contract
///         ETH + stETH), stranding a later claimant, and — once game-side claimable is drained by
///         the protocol self-sub — underflowing every totalMoney computation (burn, preview,
///         submit) in checked arithmetic.
///         Pre-fix: the second over-committing submit is admitted (the expectRevert here fails).
///         Post-fix: the custody leg admits cumulatively (custody >= pending + amount), the second
///         submit reverts Insolvent, and custody >= pendingRedemptionEthValue holds throughout.
/// @dev TEST-ONLY. No contracts/*.sol are mutated here.
///      Run: forge test --match-path test/repro/SdgnrsStethReserveDoubleBook.t.sol -vv
contract SdgnrsStethReserveDoubleBook is DeployProtocol {
    /// @dev Mirror of DegenerusGameStorage.Insolvent for expectRevert.
    error Insolvent();

    /// @dev balancesPacked (DegenerusGame) at slot 7; low 128 bits = claimable.
    uint256 internal constant GAME_CLAIMABLE_SLOT = 7;
    /// @dev claimablePool in the upper 128 bits of slot 1.
    uint256 internal constant GAME_SLOT1 = 1;

    address internal playerX = address(0xCAFE01); // first same-day gambling burner
    address internal playerY = address(0xCAFE02); // second same-day gambling burner

    uint256 internal constant FUND = 80_000_000_000 ether; // 8% of the 1e12-token supply each

    /// @dev sDGNRS custody: pure stETH, the shape the ETH-short regime produces.
    uint256 internal constant CUSTODY_STETH = 100 ether;
    /// @dev Game-side claimable[SDGNRS]: inflates the submit base well beyond custody.
    uint256 internal constant GAME_CLAIMABLE = 1000 ether;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        // ETH-short regime: claimable[SDGNRS] is large (the base the reservation is sized against)
        // but the game's liquid ETH cannot cover a MAX pull, so the ETH leg's balance conjunct
        // fails and every reservation lands on the custody-backed leg.
        _setGameClaimableSdgnrs(GAME_CLAIMABLE);
        _setGameClaimablePool(uint128(GAME_CLAIMABLE));
        vm.deal(address(game), 1 ether);

        // sDGNRS custody is pure stETH (what the ETH-first claim path leaves it in the ETH-short
        // regime); no ETH so _payEth pays stETH only.
        mockStETH.mint(address(sdgnrs), CUSTODY_STETH);
        vm.deal(address(sdgnrs), 0);

        // Two pools: Reward (10% of supply) cannot cover both 8% grants alone.
        vm.startPrank(address(game));
        sdgnrs.transferFromPool(sDGNRS.Pool.Reward, playerX, FUND);
        sdgnrs.transferFromPool(sDGNRS.Pool.Affiliate, playerY, FUND);
        vm.stopPrank();
        assertEq(sdgnrs.balanceOf(playerX), FUND, "setup: X fully funded");
        assertEq(sdgnrs.balanceOf(playerY), FUND, "setup: Y fully funded");

        // FLIP legs no-op → escrow slice is 0, claim-time FLIP leg skipped; focus stays on ETH/stETH.
        vm.mockCall(address(coinflip), abi.encodeWithSelector(IFlipCoinflipPlayerMock.previewClaimCoinflips.selector), abi.encode(uint256(0)));
        vm.mockCall(address(coinflip), abi.encodeWithSelector(IFlipCoinflipPlayerMock.redeemableFlipBacking.selector), abi.encode(uint256(0)));
        vm.mockCall(address(coinflip), abi.encodeWithSelector(IFlipCoinflipPlayerMock.withdrawRedeemedFlip.selector), abi.encode());
    }

    function _setGameClaimableSdgnrs(uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(address(sdgnrs), GAME_CLAIMABLE_SLOT));
        uint256 word = uint256(vm.load(address(game), slot));
        word = (word & (type(uint256).max << 128)) | uint128(amount);
        vm.store(address(game), slot, bytes32(word));
    }

    function _setGameClaimablePool(uint128 amount) internal {
        uint256 slot1Val = uint256(vm.load(address(game), bytes32(uint256(GAME_SLOT1))));
        slot1Val = (slot1Val & type(uint128).max) | (uint256(amount) << 128);
        vm.store(address(game), bytes32(uint256(GAME_SLOT1)), bytes32(slot1Val));
    }

    /// @dev The invariant the fix enforces: in-contract ETH + stETH custody covers every
    ///      outstanding reservation.
    function _custodyCoversReserve() internal view returns (bool) {
        return address(sdgnrs).balance + mockStETH.balanceOf(address(sdgnrs)) >= sdgnrs.pendingRedemptionEthValue();
    }

    /// @dev Burn `permille`/1000 of the LIVE supply as `player` on the current day.
    function _burnPermilleOfSupply(address player, uint256 permille) internal {
        uint256 amount = (sdgnrs.totalSupply() * permille) / 1000;
        vm.prank(player);
        sdgnrs.burn(amount);
    }

    /// @notice Two same-day burns, each individually under custody, together over custody.
    ///         Post-fix the second submit fails closed (Insolvent) and no wedge state is reachable.
    function test_overCommittingSecondSubmitFailsClosed() public {
        _primeCurrentDayRng();

        // X burns 5% of supply: base ≈ 1100 ETH → MAX increment ≈ 96.25, custody 100 covers it.
        _burnPermilleOfSupply(playerX, 50);
        uint256 pendingAfterX = sdgnrs.pendingRedemptionEthValue();
        assertGt(pendingAfterX, 0, "precondition: X's reservation recorded");
        assertTrue(_custodyCoversReserve(), "precondition: custody covers X's reservation alone");

        // Y burns 5% of the live supply: individually the increment (~87.8) fits under the 100
        // custody, but cumulatively 96.25 + 87.8 > 100 — the same stETH would back both.
        // FIX: the custody leg must test cumulatively and fail closed.
        uint256 amountY = (sdgnrs.totalSupply() * 50) / 1000;
        vm.prank(playerY);
        vm.expectRevert(Insolvent.selector);
        sdgnrs.burn(amountY);

        assertEq(sdgnrs.pendingRedemptionEthValue(), pendingAfterX, "FIX: no reservation admitted beyond custody");
        assertTrue(_custodyCoversReserve(), "FIX: custody still covers the reserve after the rejected submit");

        // Wedge probe: the protocol self-sub drains claimable[SDGNRS] after reservations were
        // sized against it. With cumulative admission, pending <= custody, so totalMoney
        // (custody + claimable - pending) cannot underflow: previews and right-sized burns
        // keep working.
        _setGameClaimableSdgnrs(0);
        _setGameClaimablePool(0);
        sdgnrs.previewBurnValue(1_000_000_000 ether);
        _burnPermilleOfSupply(playerY, 10); // base is now custody - pending; a small burn is admitted
        assertTrue(_custodyCoversReserve(), "FIX: identity holds through the post-drain burn");
    }

    /// @notice Two same-day custody-leg burns that DO fit cumulatively, resolved at MAX (175),
    ///         claimed X-then-Y: both claimants are paid in full and the reserve releases exactly.
    function test_bothClaimantsPaid_claimOrderXY() public {
        _runBothClaimants(true);
    }

    /// @notice Same as above with the claim order reversed (Y then X).
    function test_bothClaimantsPaid_claimOrderYX() public {
        _runBothClaimants(false);
    }

    function _runBothClaimants(bool xFirst) internal {
        uint24 dayD = uint24(game.currentDayView());
        _primeCurrentDayRng();

        // 2.5% + 2.5%: MAX increments ≈ 48.1 + 46.0 = 94.1 <= 100 custody — both admitted.
        _burnPermilleOfSupply(playerX, 25);
        assertTrue(_custodyCoversReserve(), "identity after X's submit");
        _burnPermilleOfSupply(playerY, 25);
        assertTrue(_custodyCoversReserve(), "identity after Y's submit");

        uint256 pending = sdgnrs.pendingRedemptionEthValue();
        (uint96 owedX, , ) = sdgnrs.pendingRedemptions(playerX, dayD);
        (uint96 owedY, , ) = sdgnrs.pendingRedemptions(playerY, dayD);
        assertGt(uint256(owedX), 0, "X's base recorded");
        assertGt(uint256(owedY), 0, "Y's base recorded");

        // Resolve at MAX (175) so the rolled amounts equal the segregated MAX — the reserve must
        // cover both claims with nothing to spare from the over-pull.
        vm.warp(block.timestamp + 1 days);
        vm.prank(address(game));
        sdgnrs.resolveRedemptionPeriod(175, dayD);
        assertEq(sdgnrs.pendingRedemptionEthValue(), pending, "175 resolve keeps the MAX reservation");

        // Terminal mode (self-claims pay direct via _payEth): gameOver implies livenessTriggered.
        vm.mockCall(address(game), abi.encodeWithSelector(game.gameOver.selector), abi.encode(true));
        vm.mockCall(address(game), abi.encodeWithSelector(game.livenessTriggered.selector), abi.encode(true));

        (address first, address second) = xFirst ? (playerX, playerY) : (playerY, playerX);
        (uint96 owedFirst, uint96 owedSecond) = xFirst ? (owedX, owedY) : (owedY, owedX);

        _claimAndAssertPaid(first, dayD, owedFirst);
        assertTrue(_custodyCoversReserve(), "identity after the first claim");
        _claimAndAssertPaid(second, dayD, owedSecond);

        assertEq(sdgnrs.pendingRedemptionEthValue(), 0, "reserve fully released after both claims");
        assertTrue(_custodyCoversReserve(), "identity after both claims");
    }

    function _claimAndAssertPaid(address player, uint24 dayD, uint96 owedBase) internal {
        uint256 expected = (uint256(owedBase) * 175) / 100;
        uint256 before = player.balance + mockStETH.balanceOf(player);
        vm.prank(player);
        sdgnrs.claimRedemption(player, dayD);
        assertEq(
            player.balance + mockStETH.balanceOf(player) - before,
            expected,
            "claimant received the full rolled redemption"
        );
    }
}
