// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {RedemptionFixture} from "./helpers/RedemptionFixture.sol";
import {RedemptionCloseHarness} from "./helpers/RedemptionCloseTools.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";

/// @notice Exercises _closeRedemptionBatch funding and real ETH/stETH claim forwarding.
contract RedemptionStethFallbackTest is RedemptionFixture {
    function _fundGameBacking(uint256 liquid) internal {
        vm.deal(address(sdgnrs), 0);
        vm.deal(address(game), liquid);
        mockStETH.mint(address(game), 1000 ether - liquid);
        bytes32 slot = keccak256(abi.encode(address(sdgnrs), uint256(7)));
        uint256 packed = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32((packed & (type(uint256).max << 128)) | uint128(1000 ether + 1)));
        uint256 pools = uint256(vm.load(address(game), bytes32(uint256(1))));
        vm.store(address(game), bytes32(uint256(1)), bytes32((pools & type(uint128).max) | (uint256(1000 ether + 1) << 128)));
    }
    function _fundedClose() internal {
        bytes memory code = address(game).code;
        vm.etch(address(game), type(RedemptionCloseHarness).runtimeCode);
        RedemptionCloseHarness(address(game)).close();
        vm.etch(address(game), code);
    }
    function _solvent() internal view {
        assertGe(address(sdgnrs).balance + mockStETH.balanceOf(address(sdgnrs)), sdgnrs.pendingRedemptionEthValue());
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
        assertEq(game.claimablePoolView(), pool - reserved);
        assertEq(address(sdgnrs).balance, liquid < reserved ? liquid : reserved);
        assertEq(mockStETH.balanceOf(address(sdgnrs)), reserved - address(sdgnrs).balance);
        _solvent();
        settlementWord = _wordForRoll(175);
        vm.mockCall(address(game), abi.encodeWithSignature("rngConsumerStage()"), abi.encode(uint8(1)));
        uint256 gameBefore = address(game).balance + mockStETH.balanceOf(address(game));
        uint256 future = game.futurePrizePoolView();
        assertTrue(_work(9_000_000));
        assertEq(_claimTokens(alice, id), 0, "real claim settled, not parked");
        assertEq(address(game).balance + mockStETH.balanceOf(address(game)) - gameBefore, reserved);
        assertApproxEqAbs(game.claimableWinningsOf(alice), reserved / 2, 1);
        assertEq(game.futurePrizePoolView() - future, reserved / 2);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        _solvent();
    }
    function test_EthReserveFundingAndClaim() public { _case(1000 ether); }
    function test_StethReserveFundingAndClaim() public { _case(0); }
    function test_MixedReserveFundingAndClaim() public { _case(3 ether); }
    function testFuzz_CloseAndClaimFundingMix(uint256 seed) public { _case(bound(seed, 0, 1000 ether)); }
    function test_FailedReserveTransferRollsBackEntireClose() public {
        _fundGameBacking(0);
        uint32 id = _openBatchId();
        _burn(alice, sdgnrs.totalSupply() / 100);
        bytes memory code = address(game).code;
        vm.etch(address(game), type(RedemptionCloseHarness).runtimeCode);
        vm.mockCall(address(mockStETH), abi.encodeWithSelector(mockStETH.transfer.selector), abi.encode(false));
        vm.expectRevert(); RedemptionCloseHarness(address(game)).close();
        vm.etch(address(game), code);
        assertEq(_openBatchId(), id);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertEq(game.claimableWinningsOf(address(sdgnrs)), 1000 ether + 1);
        assertGt(_escrow(), 0);
    }
    function test_DonationPricedOnceAndCustodyAvoidsUnneededPull() public {
        _fundGameBacking(1000 ether);
        mockStETH.mint(address(sdgnrs), 100 ether);
        uint256 n = sdgnrs.totalSupply() / 100;
        _burn(alice, n);
        uint256 credit = game.claimableWinningsOf(address(sdgnrs));
        _fundedClose();
        assertEq(_claimBase(alice, 1), 11 ether);
        assertEq(game.claimableWinningsOf(address(sdgnrs)), credit);
        _solvent();
    }
    function test_NonGameReceiveReverts() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(sdgnrs).call{value: 1 ether}("");
        assertFalse(ok);
    }
    function test_ForcedEthIsIncludedInClosePrice() public {
        uint256 n = sdgnrs.totalSupply() / 1000;
        _burn(alice, n);
        vm.deal(address(sdgnrs), 11_000 ether);
        _closeAsGame();
        assertEq(_claimBase(alice, 1), 11 ether);
        _solvent();
    }
}
