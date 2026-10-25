// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {VRFRandomWordsRequest} from "../../contracts/interfaces/IVRFCoordinator.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusAdmin} from "../../contracts/DegenerusAdmin.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

contract VrfNativeDonationTest is DeployProtocol {
    address donor;
    function setUp() public {
        _deployProtocol();
        donor = makeAddr("native donor"); vm.deal(donor, 100 ether);
    }
    function _balance() private view returns (uint256 amount) {
        (, uint96 bal,,,) = mockVRF.getSubscription(admin.subscriptionId()); return bal;
    }
    function testFuzzFullDonationAndQuarterCredit(uint96 value) public {
        uint256 amount = bound(value, 1, 10 ether);
        uint256 beforeBalance = _balance();
        vm.prank(donor); admin.donateVrf{value: amount}();
        assertEq(_balance() - beforeBalance, amount);
        assertEq(game.middayRngCredits(donor), amount / 4);
        assertEq(address(admin).balance, 0);
        assertGt(game.walletIdOf_g3120(donor), 0);
    }
    function testFuzzSplittingCannotIncreaseCredit(uint96 total, uint96 first) public {
        uint256 value = bound(total, 2, 10 ether);
        uint256 part = bound(first, 1, value - 1);
        vm.startPrank(donor);
        admin.donateVrf{value: part}(); admin.donateVrf{value: value - part}();
        vm.stopPrank();
        assertLe(game.middayRngCredits(donor), value / 4);
    }
    function testForwardFailureRollsBackDonation() public {
        uint256 beforeBalance = donor.balance;
        vm.mockCallRevert(address(mockVRF), abi.encodeWithSelector(mockVRF.fundSubscriptionWithNative.selector), "fund failed");
        vm.prank(donor); vm.expectRevert(bytes("fund failed")); admin.donateVrf{value: 1 ether}();
        assertEq(donor.balance, beforeBalance); assertEq(game.middayRngCredits(donor), 0);
        assertEq(_balance(), 0); assertEq(address(admin).balance, 0);
    }
    function testCreditFailureRollsBackSuccessfulForward() public {
        vm.mockCallRevert(address(game), abi.encodeWithSelector(game.creditMiddayRng.selector), "credit failed");
        vm.prank(donor); vm.expectRevert(bytes("credit failed")); admin.donateVrf{value: 1 ether}();
        assertEq(_balance(), 0); assertEq(donor.balance, 100 ether);
    }
    function testPlainEthGoesToVaultWithoutCredit() public {
        uint256 beforeBalance = address(vault).balance;
        vm.prank(donor); (bool ok,) = address(admin).call{value: 1 ether}("");
        assertTrue(ok); assertEq(address(vault).balance - beforeBalance, 1 ether);
        assertEq(game.middayRngCredits(donor), 0); assertEq(_balance(), 0);
    }
    function testZeroDonationAndGameOverRefused() public {
        vm.expectRevert(DegenerusAdmin.InvalidAmount.selector); admin.donateVrf();
        vm.mockCall(address(game), abi.encodeWithSelector(game.gameOver.selector), abi.encode(true));
        vm.prank(donor); vm.expectRevert(DegenerusAdmin.GameOver.selector); admin.donateVrf{value: 1 ether}();
    }
    function testNoSubscriptionRefused() public {
        vm.prank(address(game)); admin.shutdownVrf();
        vm.prank(donor); vm.expectRevert(DegenerusAdmin.NoSubscription.selector); admin.donateVrf{value: 1 ether}();
    }
    function testStakingKeepsNativeTargetBeyondPlayerClaims() public {
        address owner = makeAddr("staking owner");
        vm.mockCall(address(vault), abi.encodeWithSignature("isVaultOwner(address)", owner), abi.encode(true));
        // No user claims in the genesis fixture: keep the full target even here.
        vm.deal(address(game), 1 ether);
        vm.prank(owner); vm.expectRevert(bytes4(keccak256("Insolvent()")));
        game.adminStakeEthForStEth(1 ether - 0.49352 ether + 1);
        vm.prank(owner); game.adminStakeEthForStEth(1 ether - 0.49352 ether);
        assertEq(address(game).balance, 0.49352 ether);
        assertEq(mockStETH.balanceOf(address(game)), 1 ether - 0.49352 ether);
    }
    function testTerminalRefundAndZeroRefundReachVault() public {
        vm.prank(donor); admin.donateVrf{value: 1 ether}();
        uint256 beforeBalance = address(vault).balance;
        vm.prank(address(game)); admin.shutdownVrf();
        assertEq(address(vault).balance, beforeBalance + 1 ether);
        assertEq(admin.subscriptionId(), 0);
        vm.prank(address(game)); admin.shutdownVrf();
        assertEq(address(vault).balance, beforeBalance + 1 ether);
    }
    function testAdminCannotMintCoinflipCredit() public {
        vm.prank(address(admin)); vm.expectRevert(); coinflip.creditFlip_g317(1, 1000);
    }
}

contract NativeSwapAdminHarness is DegenerusAdmin {
    function swapForTest(address replacement, bytes32 keyHash) external {
        Proposal storage p = proposals[++proposalCount];
        p.coordinator = replacement; p.keyHash = keyHash; p.callbackGasLimit = 150_000;
        _executeSwap(proposalCount);
    }
}

contract NativeSwapGameProbe {
    bool public gameOver;
    mapping(address => uint256) public credits;
    function wireVrf(address, uint256, bytes32) external {}
    function creditMiddayRng(address donor, uint256 amount) external returns (uint32) { credits[donor] += amount; return 1; }
    function updateVrfCoordinatorAndSub(address replacement, uint256 sub, bytes32 keyHash, uint32 gasLimit) external {
        (, uint96 balance,,,) = MockVRFCoordinator(payable(replacement)).getSubscription(sub);
        require(balance == 1 ether, "refund must be funded before update/reissue");
        MockVRFCoordinator(payable(replacement)).requestRandomWords(VRFRandomWordsRequest({keyHash:keyHash,subId:sub,
            requestConfirmations:6,callbackGasLimit:gasLimit,numWords:1,
            extraArgs:hex"92fd13380000000000000000000000000000000000000000000000000000000000000001"}));
    }
}

contract NativeSwapOrderingTest is Test {
    function testLiveSwapRetainsRefundAndFundsBeforeReissue() public {
        deployCodeTo("MockVRFCoordinator.sol:MockVRFCoordinator", ContractAddresses.VRF_COORDINATOR);
        vm.etch(ContractAddresses.GAME, type(NativeSwapGameProbe).runtimeCode);
        vm.setNonce(address(this), 10);
        NativeSwapAdminHarness a = new NativeSwapAdminHarness();
        a.donateVrf{value: 1 ether}();
        NativeSwapGameProbe g = NativeSwapGameProbe(ContractAddresses.GAME);
        assertEq(g.credits(address(this)), 0.25 ether);
        MockVRFCoordinator replacement = new MockVRFCoordinator();
        replacement.requireFundedRequests(true);
        uint256 vaultBefore = ContractAddresses.VAULT.balance;
        a.swapForTest(address(replacement), bytes32(uint256(9)));
        assertGt(replacement.lastRequestId(), 0);
        assertTrue(replacement.lastNativePayment());
        assertEq(ContractAddresses.VAULT.balance, vaultBefore);
        assertEq(address(a).balance, 0); assertEq(g.credits(address(this)), 0.25 ether);
    }
}
