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

/// @title SdgnrsReserveUnderpullDoS — repro for finding B (post-gameOver reserve under-pull).
/// @notice A resolved-but-unclaimed gambling-burn claim leaves a segregated reserve
///         `_pendingRedemptionEthValue` (P) owed to that claimant. Post-gameOver, a deterministic
///         burn by another holder computes its payout net of P but pays the ETH leg out of raw
///         balance (which includes P), pulling game-side claimable only when the ETH leg alone is
///         short. When stETH + claimable <= P the burn draws down the reserve, leaving in-contract
///         ETH+stETH below P, so the earlier claimant's `_payEth` reverts (TransferFailed).
///         Pre-fix this test's reserve-identity assertion and the claim both fail; post-fix both hold.
/// @dev TEST-ONLY. No contracts/*.sol are mutated here.
///      Run: forge test --match-path test/repro/SdgnrsReserveUnderpullDoS.t.sol -vv
contract SdgnrsReserveUnderpullDoS is DeployProtocol {
    /// @dev balancesPacked (DegenerusGame) at slot 7; low 128 bits = claimable.
    uint256 internal constant GAME_CLAIMABLE_SLOT = 7;
    /// @dev claimablePool in the upper 128 bits of slot 1.
    uint256 internal constant GAME_SLOT1 = 1;

    address internal playerX = address(0xBEEF01); // gambling-burn claimant, owed the reserve P
    address internal playerY = address(0xBEEF02); // post-gameOver deterministic burner (the drain)

    uint256 internal constant FUND = 80_000_000_000 ether;
    uint256 internal constant BURN = 10_000_000_000 ether;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        // Fund the game with ETH backing + claimable[SDGNRS] so the submit-time pullRedemptionReserve
        // ETH leg segregates the reserve into sDGNRS's balance.
        vm.deal(address(game), 1000 ether);
        _setGameClaimableSdgnrs(1000 ether);
        _setGameClaimablePool(uint128(1000 ether));

        vm.startPrank(address(game));
        sdgnrs.transferFromPool(sDGNRS.Pool.Reward, playerX, FUND);
        sdgnrs.transferFromPool(sDGNRS.Pool.Reward, playerY, FUND);
        vm.stopPrank();

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

    function _reserveIdentityHolds() internal view returns (bool) {
        return address(sdgnrs).balance + mockStETH.balanceOf(address(sdgnrs)) >= sdgnrs.pendingRedemptionEthValue();
    }

    function test_reserveSurvivesGameOverDrainAndClaimantIsPaid() public {
        // 1. X's gambling burn on day D records a positive-base pending redemption.
        uint24 dayD = uint24(game.currentDayView());
        _primeCurrentDayRng();
        vm.prank(playerX);
        sdgnrs.burn(BURN);
        (uint96 owedBase, , ) = sdgnrs.pendingRedemptions(playerX, dayD);
        assertGt(uint256(owedBase), 0, "precondition: X's gambling burn recorded a positive base");

        // 2. Advance and resolve at MAX (175%) so the reserve P is large; X leaves it unclaimed.
        vm.warp(block.timestamp + 1 days);
        vm.prank(address(game));
        sdgnrs.resolveRedemptionPeriod(175, dayD);
        uint256 P = sdgnrs.pendingRedemptionEthValue();
        assertGt(P, 0, "precondition: reserve P > 0 after resolve, unclaimed");

        // 3. gameOver latches AFTER the resolve → the deterministic burn path is now open.
        vm.mockCall(address(game), abi.encodeWithSelector(game.gameOver.selector), abi.encode(true));

        // 4. Shape Case-B: in-contract ETH = P, stETH = S (~0), game-side claimable C with S + C <= P.
        uint256 S = mockStETH.balanceOf(address(sdgnrs));
        vm.deal(address(sdgnrs), P); // E = P
        assertLt(S, P, "precondition: stETH below reserve");
        uint256 C = (P - S) / 2; // C <= P - S so S + C <= P, and C > 0
        assertGt(C, 0, "precondition: claimable C > 0");
        _setGameClaimableSdgnrs(C);
        _setGameClaimablePool(uint128(C + 1 ether));
        vm.deal(address(game), C + 1 ether); // game can fund a claimWinnings pull (post-fix path)
        assertTrue(_reserveIdentityHolds(), "precondition: reserve identity holds before the drain burn");

        // 5. Y's post-gameOver deterministic burn — the drain. totalValueOwed <= E, so pre-fix the
        //    ETH-leg-short pull does NOT fire and the payout is taken from the reserved ETH.
        vm.prank(playerY);
        sdgnrs.burn(BURN);

        // 6a. The reserve must still be covered by in-contract ETH+stETH (pre-fix: violated).
        assertTrue(_reserveIdentityHolds(), "FIX B: in-contract ETH+stETH must still cover the reserve after the drain burn");

        // 6b. X's resolved claim must be payable (pre-fix: reverts TransferFailed inside _payEth).
        uint256 xBefore = playerX.balance;
        vm.prank(playerX);
        sdgnrs.claimRedemption(playerX, dayD);
        assertGt(playerX.balance, xBefore, "FIX B: the resolved claimant must receive their redemption");
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0, "reserve fully released after the only claimant is paid");
    }
}
