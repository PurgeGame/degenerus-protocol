// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {GnrusFlipTicketsTest} from "./GnrusFlipTickets.t.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {OwnerTargetCall} from "../helpers/OwnerTargetCall.sol";
import {PeripheralSlots} from "../helpers/PeripheralSlots.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";

contract GnrusWwxrpTest is GnrusFlipTicketsTest {
    function _fund(uint256 credit, uint256 held) private {
        vm.prank(address(game)); wwxrp.creditPrize(3, credit);
        vm.prank(ContractAddresses.VAULT); wwxrp.vaultMintTo(ContractAddresses.GNRUS, held);
    }
    function test_centuryRequestEntersOldDayAndUpcomingBracket() public {
        uint24 day = _seed(100, 0, 3000, 5000, 7000);
        _fund(30, 40);
        host.wwxrpBoon();
        host.request();
        assertEq(game.currentLvl(), 100);
        assertEq(wwxrp.claimable(3), 0);
        assertEq(wwxrp.balanceOf(ContractAddresses.GNRUS), 0);
        (uint256 raw, uint256 total, uint32 count) = wwxrp.bucketInfo(day - 1, wwxrp.bucketOf(day - 1, 3));
        assertEq(raw, 70); assertGt(total, 70); assertEq(count, 1);
        (uint32 id,) = wwxrp.entryAt(day - 1, wwxrp.bucketOf(day - 1, 3), 0);
        assertEq(id, 3);
        (uint256 incinTotal, uint32 incinCount) = wwxrp.incineratorInfo(100);
        assertEq(incinTotal, total); assertEq(incinCount, 1);
        (id,) = wwxrp.incineratorEntryAt(100, 0); assertEq(id, 3);
        (,,count) = wwxrp.bucketInfo(day, wwxrp.bucketOf(day, 3)); assertEq(count, 0);
        (,uint256 boon) = game.boonPacked(3); assertEq(boon >> 232, 0);
    }
    function test_belowMinimumIsNoOp() public {
        _seed(100, 0, 3000, 5000, 7000); _fund(12, 12); host.request();
        assertEq(wwxrp.claimable(3), 12); assertEq(wwxrp.balanceOf(ContractAddresses.GNRUS), 12);
        (,uint32 count) = wwxrp.incineratorInfo(100); assertEq(count, 0);
    }
    function test_nonCenturyDoesNotEnter() public {
        _seed(99, 0, 3000, 5000, 7000); _fund(30, 40);
        vm.expectCall(address(wwxrp), abi.encodeCall(wwxrp.enterDrawForGnrus, ()), 0);
        host.request(); assertEq(wwxrp.claimable(3), 30); assertEq(wwxrp.balanceOf(ContractAddresses.GNRUS), 40);
    }
    function test_entryIsGameOnly() public {
        vm.expectRevert(bytes4(keccak256("OnlyMinter()"))); wwxrp.enterDrawForGnrus();
    }
    /// Saturated authorized awards enter without overflowing when held gifts coexist.
    /// Neither WWXRP reward storage nor its token supply is modified with cheatcode writes.
    function test_authorizedPrizeScaleAndWalletGiftOverflowCompletesRequest() public {
        _seed(100, 0, 3000, 5000, 7000);
        OwnerTargetCall.call(address(wwxrp), abi.encodeCall(wwxrp.setGameMintScale, (type(uint256).max)), 0);
        _fund(1, 2);
        assertEq(wwxrp.claimable(3), type(uint256).max - 1);
        host.request();
        assertEq(game.currentLvl(), 100);
        assertEq(wwxrp.claimable(3), 0);
        (, uint32 count) = wwxrp.incineratorInfo(100);
        assertEq(count, 1);
        assertEq(wwxrp.balanceOf(ContractAddresses.GNRUS), 2);
    }
    function testFuzz_claimableHeldSumNeverStalls(uint256 credit, uint256 held) public {
        _seed(100, 0, 3000, 5000, 7000);
        // Independent production award and held-supply domains, including their overflow boundary.
        _fund(credit, held);
        uint256 bank = wwxrp.claimable(3);
        uint256 wallet = wwxrp.balanceOf(ContractAddresses.GNRUS);
        bool fits = wallet <= type(uint256).max - bank;
        uint256 amount = fits ? bank + wallet : bank;
        host.request();
        assertEq(game.currentLvl(), 100);
        assertEq(wwxrp.claimable(3), amount >= 25 ? 0 : bank);
        assertEq(wwxrp.balanceOf(ContractAddresses.GNRUS), amount >= 25 && fits ? 0 : wallet);
        (, uint32 count) = wwxrp.incineratorInfo(100);
        assertEq(count, amount >= 25 ? 1 : 0);
    }

    /// A full day-bucket or century counter skips GNRUS's burn and the request still completes;
    /// players are still refused by the shared century counter.
    function test_fullEntryCounterSkipsGnrusAndRequestCompletes() public {
        for (uint8 which; which < 2; ++which) {
            uint256 snap = vm.snapshotState();
            uint24 day = _seed(100, 0, 3000, 5000, 7000) - 1;
            uint256 header;
            uint256 slot;
            if (which == 0) {
                slot = PeripheralSlots.WW_DRAW_HEADER + uint256(day % 3) * 10 + wwxrp.bucketOf(day, 3);
                header = (uint256(day + 1) << 224) | (uint256(type(uint32).max - 1) << 192);
            } else {
                slot = PeripheralSlots.WW_INCIN_HEADER;
                header = (uint256(100) << 224) | (uint256(type(uint32).max - 1) << 192);
            }
            vm.store(address(wwxrp), bytes32(slot), bytes32(header));
            _fund(25, 0);
            vm.prank(address(game)); wwxrp.enterDrawForGnrus(); // Final legal append commits max count.
            assertEq(wwxrp.claimable(3), 0);
            if (which == 1) {
                address player = address(0xBEEF01);
                vm.prank(ContractAddresses.VAULT); wwxrp.vaultMintTo(player, 25);
                vm.expectRevert(bytes4(keccak256("ScoreOverflow()")));
                vm.prank(player); wwxrp.enterDraw(0, 25);
                assertEq(wwxrp.balanceOf(player), 25);
            }
            _fund(25, 0);
            host.request();
            assertEq(game.currentLvl(), 100);
            assertEq(wwxrp.claimable(3), 25);
            assertEq(uint32(uint256(vm.load(address(wwxrp), bytes32(slot))) >> 192), type(uint32).max);
            assertTrue(vm.revertToState(snap));
        }
    }

    function test_gnrusNativeTokensDoNotIncreaseVotingSupply() public {
        uint256 beforeSupply = sdgnrs.votingSupply();
        _unwrapFromVault(ContractAddresses.GNRUS, 1000 ether);
        assertEq(sdgnrs.votingSupply(), beforeSupply);
        vm.prank(address(game)); sdgnrs.transferFromPool_g106128(sDGNRS.Pool.Reward, ContractAddresses.GNRUS, 1000 ether);
        assertEq(sdgnrs.votingSupply(), beforeSupply);
        _unwrapFromVault(address(0xA111), 1000 ether);
        assertEq(sdgnrs.votingSupply(), beforeSupply + 1000 ether);
    }
}
