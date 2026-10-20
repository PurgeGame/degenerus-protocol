// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {RedemptionFixture} from "./helpers/RedemptionFixture.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract RedemptionBackingCapTest is RedemptionFixture {
    /// @dev Independent assertion of the protocol limit: a claim's admission bound is base 600k plus
    ///      one 3.2M human entry and 125k per box, capped at twenty boxes (6.3M); with its 1/63
    ///      call retention, 12k call reserve, 100k tail and 2k check reserve it needs ~6.514M.
    uint256 private constant TWENTY_BOX_CLAIM_ALLOWANCE = 7_000_000;

    function test_TwoClaimsShareOneStorageWord() public {
        uint32 id = _openBatchId();
        assertEq(id, 1);
        _burn(alice, 1e18 + 1);
        _burn(bob, 2e18 + 3);
        // Compiler layout: packed-word mappings at roots 9/10; logical counts are in slot 7.
        bytes32 data = keccak256(abi.encode(uint256(0), uint256(10)));
        uint256 packed = uint256(vm.load(address(sdgnrs), data));
        uint128 first = uint128(packed);
        uint128 second = uint128(packed >> 128);
        assertEq(uint80(first), 1e18 + 1);
        assertEq(uint80(second), 2e18 + 3);
        assertEq(uint32(first >> 80), game.walletIdOf(alice));
        assertEq(uint32(second >> 80), game.walletIdOf(bob));
        assertEq(uint256(vm.load(address(sdgnrs), keccak256(abi.encode(uint256(1), uint256(10))))), 0);
        _burn(alice, 3e18 + 5);
        uint256 afterPacked = uint256(vm.load(address(sdgnrs), data));
        assertEq(uint128(afterPacked >> 128), second, "neighbor lane remains intact");
        assertEq(uint80(afterPacked), 4e18 + 6);
    }

    function test_QueueCountsCoexistAndReusedLaneReplacesOldOwner() public {
        _burn(alice, 1e18);
        uint32 first = _resolveLive(100);
        _burn(bob, 2e18);
        uint256 packed = uint256(vm.load(address(sdgnrs), bytes32(uint256(7))));
        assertEq(uint32(packed >> 192), 1, "even count");
        assertEq(uint32(packed >> 224), 1, "odd count");
        assertTrue(_work(9_000_000));
        packed = uint256(vm.load(address(sdgnrs), bytes32(uint256(7))));
        assertEq(uint32(packed >> 192), 1, "finishing odd preserves open even");
        assertEq(uint32(packed >> 224), 0, "finished count retires");
        assertEq(uint128(packed), 2e18 + 1, "encoded open escrow survives");
        uint32 second = _resolveLive(100);
        assertEq(second, first + 1);
        assertTrue(_work(9_000_000));
        _burn(carol, 3e18);
        bytes32 key = keccak256(abi.encode(uint256(0), uint256(10)));
        uint256 entry = uint256(vm.load(address(sdgnrs), key));
        assertEq(uint80(entry), 3e18);
        assertEq(uint32(entry >> 80), game.walletIdOf(carol), "replaces previous beneficiary");
        assertEq(_claimTokens(alice, first), 0, "stale locator cannot read new owner");
        assertEq(_claimTokens(carol, first + 2), 3e18);
        assertEq(uint256(vm.load(address(sdgnrs), bytes32(uint256(9)))), 0, "no array length");
        assertEq(uint256(vm.load(address(sdgnrs), bytes32(uint256(10)))), 0, "no array length");
    }

    function test_LiveVeryLargeCappedClaimSettlesWithinAdmission() public {
        _giveRemainingPools(alice);
        vm.deal(address(sdgnrs), 100_000_000 ether);
        _burn(alice, sdgnrs.totalSupply() * 60 / 100);
        uint32 id = _resolveLive(175);
        uint256 before = gasleft();
        assertTrue(_work(TWENTY_BOX_CLAIM_ALLOWANCE));
        uint256 used = before - gasleft();
        assertEq(_claimTokens(alice, id), 0, "large claim paid, not parked");
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        emit log_named_uint("capped claim settlement gas", used);
        assertLt(used, 2_500_000, "bounded twenty-box work despite uncapped burn");
    }

    function _giveRemainingPools(address to) private {
        for (uint8 i; i < 5; ++i) {
            uint256 amount = sdgnrs.poolBalance(sDGNRS.Pool(i));
            vm.prank(address(game));
            sdgnrs.transferFromPool(sDGNRS.Pool(i), to, amount);
        }
    }

    function test_EveryRawUnitRedeemsAndRepeatedBurnPreservesScore() public {
        uint256 balance = sdgnrs.balanceOf(alice);
        uint256 supply = sdgnrs.totalSupply();
        uint32 id = _openBatchId();
        uint32 walletId = game.walletIdOf(alice);
        vm.mockCall(address(game), abi.encodeWithSelector(game.playerActivityScore.selector, alice),
            abi.encode(uint256(123), walletId));
        _burn(alice, 1e18 + 999_999);
        _burn(bob, 2e18 + 777_777); // adjacent packed entry must remain intact
        vm.mockCall(address(game), abi.encodeWithSelector(game.playerActivityScore.selector, alice),
            abi.encode(uint256(456), walletId));
        _burn(alice, 3e18 + 123_456);
        assertEq(balance - sdgnrs.balanceOf(alice), 4e18 + 1_123_455);
        assertEq(supply - sdgnrs.totalSupply(), 6e18 + 1_901_232);
        (uint104 tokens, uint16 score) = sdgnrs.pendingRedemptions(walletId, id);
        assertEq(tokens, 4e18 + 1_123_455);
        assertEq(score, 124);
        assertEq(_claimTokens(bob, id), 2e18 + 777_777);
        assertEq(_escrow(), 6e18 + 1_901_232);
    }

    function test_EntireSupplyFitsPackedAmountAndPayoutCannotExceedBacking() public {
        _giveRemainingPools(alice);
        uint256 wrapped = sdgnrs.balanceOf(ContractAddresses.DGNRS);
        vm.prank(ContractAddresses.DGNRS);
        sdgnrs.wrapperTransferTo(alice, wrapped);
        uint256 backing = _money();
        uint256 supply = sdgnrs.totalSupply();
        _burn(alice, sdgnrs.balanceOf(alice));
        _burn(bob, sdgnrs.balanceOf(bob));
        _burn(carol, sdgnrs.balanceOf(carol));
        assertEq(_escrow(), supply);
        assertEq(sdgnrs.totalSupply(), 0);
        uint32 id = _resolveLive(175);
        (uint104 tokens, uint96 payout,,,,) = sdgnrs.redemptionBatches(id);
        assertEq(tokens, supply);
        assertEq(payout, backing, "175% roll capped at close backing");
        assertEq(sdgnrs.pendingRedemptionEthValue(), backing);
        _terminalize();
        uint256 paid;
        address[3] memory holders = [alice, bob, carol];
        for (uint256 i; i < holders.length; ++i) {
            uint256 before = _received(holders[i]);
            vm.prank(holders[i]); sdgnrs.claimRedemption(0, id);
            paid += _received(holders[i]) - before;
        }
        assertLe(paid, backing);
        assertLe(backing - paid, 2, "only pro-rata rounding dust remains");
    }

    function test_CappedPayoutIsProRataRegardlessOfClaimOrderOrLaterDeposit() public {
        _giveRemainingPools(alice);
        uint256 supply = sdgnrs.totalSupply();
        uint256 a = supply * 60 / 100;
        uint256 b = supply * 2 / 100;
        uint256 backing = _money();
        _burn(alice, a); _burn(bob, b);
        uint32 id = _openBatchId();
        _closeAsGame();
        (,uint96 maximum,,,,) = sdgnrs.redemptionBatches(id);
        assertEq(maximum, backing);
        // New backing cannot enlarge this already-committed batch's maximum.
        vm.deal(address(sdgnrs), address(sdgnrs).balance + 123 ether);
        settlementWord = _wordForRoll(175);
        vm.mockCall(address(game), abi.encodeWithSignature("rngConsumerStage()"), abi.encode(uint8(1)));
        vm.prank(address(game)); sdgnrs.runRedemptionWork(settlementWord, 200_000);
        (,uint96 payout,,,,) = sdgnrs.redemptionBatches(id);
        assertEq(payout, backing);
        _terminalize();
        uint256 snap = vm.snapshotState();
        uint256 aFirst = _terminalClaim(alice, id);
        uint256 bSecond = _terminalClaim(bob, id);
        assertTrue(vm.revertToState(snap));
        uint256 bFirst = _terminalClaim(bob, id);
        uint256 aSecond = _terminalClaim(alice, id);
        assertEq(aFirst, backing * a / (a + b));
        assertEq(bFirst, backing * b / (a + b));
        assertEq(aFirst, aSecond);
        assertEq(bFirst, bSecond);
        assertGe(address(sdgnrs).balance, 123 ether);
    }

    function _terminalClaim(address player, uint32 id) private returns (uint256 paid) {
        uint256 before = _received(player);
        vm.prank(player); sdgnrs.claimRedemption(0, id);
        paid = _received(player) - before;
    }

    function test_DroppedCappedClaimStaysRetiredAcrossBothBufferReuses() public {
        _giveRemainingPools(alice);
        uint256 amount = sdgnrs.totalSupply() * 60 / 100;
        _burn(alice, amount);
        uint32 first = _resolveLive(175);
        vm.mockCallRevert(address(game), abi.encodeWithSelector(game.resolveRedemptionLootbox.selector), hex"12345678");
        assertTrue(_work(9_000_000));
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertEq(_claimTokens(alice, first), 0);
        vm.clearMockedCalls();
        for (uint256 i; i < 2; ++i) {
            _burn(alice, _minimumLiveBurn());
            uint32 next = _resolveLive(100);
            assertEq(next, first + i + 1);
            assertTrue(_work(9_000_000));
            assertEq(_claimTokens(alice, first), 0);
            assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        }
        (uint80 tokens, uint96 payout, uint96 base, uint96 flip, uint16 roll, uint16 reward) = sdgnrs.redemptionBatches(first);
        assertEq(uint256(tokens) | payout | base | flip | roll | reward, 0);
    }

    function testFuzz_CapAcrossBurnFractionsAndRolls(uint256 amountSeed, uint16 rollSeed) public {
        _giveRemainingPools(alice);
        uint256 supply = sdgnrs.totalSupply();
        uint256 backing = _money();
        uint256 amount = bound(amountSeed, _minimumLiveBurn(), sdgnrs.balanceOf(alice));
        uint16 roll = uint16(bound(rollSeed, 21, 175));
        _burn(alice, amount);
        uint32 id = _resolveLive(roll);
        uint256 base = backing * amount / supply / 1e9 * 1e9;
        uint256 expected = base * roll / 100;
        if (expected > backing) expected = backing;
        (,uint96 payout,,,,) = sdgnrs.redemptionBatches(id);
        assertEq(payout, expected);
        _terminalize();
        uint256 before = _received(alice);
        vm.prank(alice); sdgnrs.claimRedemption(0, id);
        assertEq(_received(alice) - before, expected);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }
}
