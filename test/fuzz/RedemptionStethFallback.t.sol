// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {RedemptionFixture} from "./helpers/RedemptionFixture.sol";
import {RedemptionCloseHarness} from "./helpers/RedemptionCloseTools.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @notice Game-held ETH and stETH back the protected reserve; live closes and claims move no ETH.
contract RedemptionStethFallbackTest is RedemptionFixture {
    function _fundGameBacking(uint256 liquid) internal { _fundGameBacking(liquid, 1000 ether); }
    function _fundGameBacking(uint256 liquid, uint256 credit) internal {
        vm.deal(address(game), liquid);
        mockStETH.mint(address(game), credit - liquid);
        bytes32 slot = keccak256(abi.encode(uint256(game.walletIdOf(address(sdgnrs))), GameSlots.BALANCES_PACKED));
        uint256 packed = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32((packed & (type(uint256).max << 128)) | uint128(credit + 1)));
        uint256 pools = uint256(vm.load(address(game), bytes32(uint256(1))));
        vm.store(address(game), bytes32(uint256(1)), bytes32((pools & type(uint128).max) | (uint256(credit + 1) << 128)));
    }
    function _fundedClose() internal {
        bytes memory code = address(game).code;
        vm.etch(address(game), type(RedemptionCloseHarness).runtimeCode);
        RedemptionCloseHarness(address(game)).close();
        vm.etch(address(game), code);
    }
    function _solvent() internal view {
        assertGe(address(sdgnrs).balance + mockStETH.balanceOf(address(sdgnrs)) + game.redemptionReserve(),
            sdgnrs.pendingRedemptionEthValue());
    }
    function _case(uint256 liquid) internal {
        _fundGameBacking(liquid);
        uint32 id = _openBatchId();
        _burn(alice, sdgnrs.totalSupply() / 100);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0, "burn does not pull game backing");
        uint256 claimable = game.claimableWinningsOf(address(sdgnrs));
        uint256 pool = game.claimablePoolView();
        _fundedClose();
        uint256 reserved = sdgnrs.pendingRedemptionEthValue();
        assertEq(reserved, 17.5 ether);
        assertEq(game.claimableWinningsOf(address(sdgnrs)), claimable - reserved);
        assertEq(game.claimablePoolView(), pool, "the reserve stays inside claimablePool");
        assertEq(address(sdgnrs).balance, 0, "the close sends sDGNRS no ETH");
        assertEq(mockStETH.balanceOf(address(sdgnrs)), 0);
        assertEq(game.redemptionReserve(), reserved, "the whole pull is the reserve");
        _solvent();
        settlementWord = _wordForRoll(175);
        vm.mockCall(address(game), abi.encodeWithSignature("rngConsumerStage_g379()"), abi.encode(uint8(1)));
        uint256 gameBefore = address(game).balance + mockStETH.balanceOf(address(game));
        uint256 future = game.futurePrizePoolView();
        assertTrue(_work(9_000_000));
        assertEq(_claimTokens(alice, id), 0, "real claim settled, not parked");
        assertEq(address(game).balance + mockStETH.balanceOf(address(game)), gameBefore, "no ETH moves");
        assertEq(address(sdgnrs).balance, 0, "sDGNRS holds no ETH");
        assertApproxEqAbs(game.claimableWinningsOf(alice), reserved / 2, 1);
        assertEq(game.futurePrizePoolView() - future, reserved / 2);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertEq(game.redemptionReserve(), 0);
        _solvent();
    }
    function test_EthReserveFundingAndClaim() public { _case(1000 ether); }
    function test_StethReserveFundingAndClaim() public { _case(0); }
    function test_MixedReserveFundingAndClaim() public { _case(3 ether); }
    function testFuzz_CloseAndClaimFundingMix(uint256 seed) public { _case(bound(seed, 0, 1000 ether)); }
    function test_StethTransferFailureCannotBlockReserveCloseOrSettlement() public {
        vm.mockCall(address(mockStETH), abi.encodeWithSelector(mockStETH.transfer.selector), abi.encode(false));
        _case(0);
    }
    /// @dev Live legs pay only ETH and the Game reserve, so a token donation waits for the ending.
    function test_TokenDonationWaitsForTheEndingAndGameReserveFundsClaim() public {
        _fundGameBacking(1000 ether);
        mockStETH.mint(address(sdgnrs), 100 ether);
        uint256 n = sdgnrs.totalSupply() / 100;
        (uint256 preview,) = sdgnrs.previewBurnValue(n);
        assertEq(preview, 10 ether, "live preview ignores token custody");
        _burn(alice, n);
        uint256 credit = game.claimableWinningsOf(address(sdgnrs));
        _fundedClose();
        assertEq(_claimBase(alice, 1), 10 ether);
        uint256 beneficiaryBefore = game.claimableWinningsOf(alice);
        settlementWord = _wordForRoll(175);
        vm.mockCall(address(game), abi.encodeWithSignature("rngConsumerStage_g379()"), abi.encode(uint8(1)));
        assertTrue(_work(9_000_000));
        assertGe(game.claimableWinningsOf(alice), beneficiaryBefore + 17.5 ether / 2,
            "token donation cannot make a funded live claim drop");
        assertEq(game.claimableWinningsOf(address(sdgnrs)), credit - 17.5 ether);
        assertEq(mockStETH.balanceOf(address(sdgnrs)), 100 ether, "token donation remains backing");
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        _solvent();
    }
    /// @dev Thin Game backing and a large token donation: every live claim is still paid at the
    ///      top roll, because pricing counts only what the legs can spend.
    function test_LargeTokenDonationCannotDropALiveClaim() public {
        // Under stETH-inclusive pricing this 1% burn would carry a 1.776 ETH maximum against
        // 1.5 ETH of payable backing, so a top roll could not be paid.
        _fundGameBacking(0, 1.5 ether);
        mockStETH.mint(address(sdgnrs), 100 ether);
        uint32 id = _openBatchId();
        _burn(alice, sdgnrs.totalSupply() / 100);
        _fundedClose();
        uint256 base = _claimBase(alice, id);
        assertApproxEqAbs(base, 0.015 ether, 1e9, "priced from Game backing only");
        uint256 max = base * 175 / 100;
        assertEq(game.redemptionReserve(), max, "the whole maximum is isolated");
        uint256 future = game.futurePrizePoolView();
        settlementWord = _wordForRoll(175);
        vm.mockCall(address(game), abi.encodeWithSignature("rngConsumerStage_g379()"), abi.encode(uint8(1)));
        assertTrue(_work(9_000_000));
        assertEq(_claimTokens(alice, id), 0, "claim settled");
        assertApproxEqAbs(game.claimableWinningsOf(alice), max / 2, 1, "direct half paid");
        assertApproxEqAbs(game.futurePrizePoolView() - future, max - max / 2, 1, "lootbox half paid");
        assertEq(game.redemptionReserve(), 0);
        assertEq(mockStETH.balanceOf(address(sdgnrs)), 100 ether, "token donation remains backing");
        _solvent();
    }
    function test_NonGameReceiveReverts() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(sdgnrs).call{value: 1 ether}("");
        assertFalse(ok);
    }
    function test_ForcedEthIsIgnoredByTheLiveClosePrice() public {
        uint256 n = sdgnrs.totalSupply() / 1000;
        _burn(alice, n);
        vm.deal(address(sdgnrs), 11_000 ether);
        _closeAsGame();
        assertEq(_claimBase(alice, 1), 10 ether, "priced from Game backing only");
        assertEq(address(sdgnrs).balance, 11_000 ether, "forced ETH stays in custody");
        _solvent();
    }
}
