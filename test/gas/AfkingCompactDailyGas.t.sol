// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {console2} from "forge-std/console2.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {AfkingStethHost} from "../fuzz/helpers/AfkingStethFixture.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

contract AfkingDailyGasHost is AfkingStethHost {
    function setCheckpoint(address player, uint24 day) external {
        uint256 position = _subPosition1(_walletIdOf(player)) - 1;
        uint256 lane = _subLaneAt(position);
        _setSubLaneAt(position, _withSubCheckpoint(lane, day, _subCheckpointStreak(lane)));
    }

    /// @dev The prepared cohort's word is published: the opening stage is next.
    function publish(uint256 word) external {
        _setRngComplete(false);
        _setRngSessionPublished(true);
        rngWordCurrent = word;
        ticketsFullyProcessed = true;
    }

    function openWork(uint256 allowance_) external returns (MineFlipGas.Result memory) {
        (bool ok, bytes memory result) = ContractAddresses.GAME_AFKING_MODULE
            .delegatecall(abi.encodeWithSignature("runAfkingWork_g8553(uint256)", allowance_));
        if (!ok) assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
        return abi.decode(result, (MineFlipGas.Result));
    }
}

/// @notice Cold-storage gas of the daily AFKing passes and of settlement: preparation of a box
///         and a ticket cohort, opening of the prepared boxes, and the joint claim of one sub
///         and of twelve subs sharing an affiliate. Each figure is the whole measured call.
contract AfkingCompactDailyGasTest is DeployProtocol {
    AfkingDailyGasHost private host;
    uint256 private constant WORK_GAS = 80_000_000;
    uint256 private constant ELAPSED = 5;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 2 days);
        vm.etch(address(game), type(AfkingDailyGasHost).runtimeCode);
        host = AfkingDailyGasHost(payable(address(game)));
        vm.deal(address(game), 1_000 ether);
        host.prepare();
    }

    function _cool() private {
        vm.cool(address(game));
        vm.cool(address(coinflip));
        vm.cool(address(affiliate));
        vm.cool(address(quests));
        vm.cool(address(mockStETH));
        vm.cool(address(afkingModule));
        vm.cool(address(lootboxModule));
    }

    function _member(uint256 i) private pure returns (address) {
        return address(uint160(0xA000_0000 + i));
    }

    /// @dev `count` funded quantity-8 members, half paying from claimable and half from prepaid,
    ///      checkpointed `ELAPSED` days back.
    function _seed(uint256 count, bool tickets) private {
        uint24 e = host.endpoint();
        for (uint256 i; i < count; ++i) {
            address who = _member(i);
            if (i & 1 == 0) host.add(who, tickets, 8, 5 ether, 0);
            else host.add(who, tickets, 8, 0, 5 ether);
            host.setCheckpoint(who, e - uint24(ELAPSED));
        }
    }

    function _prepare() private returns (uint256 used) {
        _cool();
        uint256 before = gasleft();
        MineFlipGas.Result memory result = host.subWork{gas: WORK_GAS}(WORK_GAS);
        used = before - gasleft();
        assertTrue(result.done, "the cohort drains in one call");
    }

    function _open(uint256 expected) private returns (uint256 used) {
        host.publish(uint256(keccak256("afking-open")));
        _cool();
        uint256 before = gasleft();
        MineFlipGas.Result memory result = host.openWork{gas: WORK_GAS}(WORK_GAS);
        used = before - gasleft();
        assertTrue(result.done, "every box opens in one call");
        assertEq(result.rewardBasis, expected, "every box opened");
    }

    function _boxes(uint256 count) private {
        uint256 snap = vm.snapshotState();
        _seed(count, false);
        console2.log(string.concat("prepare boxes ", vm.toString(count)), _prepare());
        assertEq(host.pendingBoxes(), count);
        console2.log(string.concat("open boxes ", vm.toString(count)), _open(count));
        vm.revertToState(snap);
    }

    function test_PrepareAndOpenBoxes() public {
        _boxes(12);
        _boxes(96);
    }

    function test_PrepareTickets() public {
        _seed(96, true);
        console2.log("prepare tickets 96", _prepare());
    }

    function _claim(uint32[] memory ids) private returns (uint256 used) {
        _cool();
        uint256 before = gasleft();
        game.claimAfkingFlip(ids);
        used = before - gasleft();
    }

    function test_ClaimOne() public {
        _seed(1, false);
        uint32[] memory ids = new uint32[](1);
        ids[0] = game.walletIdOf(_member(0));
        uint256 before = coinflip.coinflipAmountById(ids[0]);
        console2.log("claim one sub", _claim(ids));
        assertGt(coinflip.coinflipAmountById(ids[0]), before, "the sub was paid");
    }

    function test_ClaimTwelveSameAffiliate() public {
        address owner = address(0xAFF1);
        _giveWalletId(owner);
        vm.prank(owner);
        affiliate.createAffiliateCode(bytes32("ALPHA"), 0);
        _seed(12, false);
        uint32[] memory ids = new uint32[](12);
        for (uint256 i; i < 12; ++i) {
            vm.prank(_member(i));
            affiliate.referPlayer(bytes32("ALPHA"));
            ids[i] = game.walletIdOf(_member(i));
        }
        uint32 ownerId = game.walletIdOf(owner);
        uint256 before = coinflip.coinflipAmountById(ownerId);
        console2.log("claim 12 subs, one affiliate", _claim(ids));
        assertGt(coinflip.coinflipAmountById(ownerId), before, "the affiliate was paid");
        for (uint256 i; i < 12; ++i) assertGt(coinflip.coinflipAmountById(ids[i]), 0, "every sub was paid");
    }
}
