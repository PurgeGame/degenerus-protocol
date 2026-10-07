// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {RedemptionFixture} from "./helpers/RedemptionFixture.sol";
import {Vm} from "forge-std/Vm.sol";

/// @notice Public burn/request/fulfill/keeper proof of price and entropy commitment.
/// Exact reward formulas are covered by the shared human-order tests; this suite compares
/// actual award events across gas partitions, later burns, donations and delayed delivery.
contract RedemptionCommitmentBindingTest is RedemptionFixture {
    uint256 private constant OWNERS = 30;
    function _owner(uint256 i) private pure returns (address) { return address(uint160(0xB1AD00 + i)); }
    function _queue() private returns (uint32 id) {
        id = _openBatchId();
        for (uint256 i; i < OWNERS; ++i) {
            // Real creator unwrap funds each owner, without writing token storage.
            dgnrs.unwrapTo(_owner(i), 1_000_000_000e12);
            _burn(_owner(i), 500_000_000e12);
        }
    }
    function _publish(uint256 word, bool delayed) private {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        assertTrue(_runUntilNewRequestOrIdle());
        if (delayed) vm.warp(vm.getBlockTimestamp() + 2 days);
        _fulfillPending(word);
    }
    function _awardDigest(Vm.Log[] memory logs, uint32 id) private view returns (bytes32 digest) {
        // Ignore miner rewards and request lifecycle events; compare every redemption's
        // claimed values and all player reward events emitted during that settlement.
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory e = logs[i];
            if (e.emitter == address(sdgnrs) && e.topics[0] == CLAIMED_TOPIC
                && uint32(uint256(e.topics[2])) == id) digest = keccak256(abi.encode(digest, e.topics, e.data));
        }
        for (uint256 i; i < OWNERS; ++i) {
            address owner = _owner(i);
            digest = keccak256(abi.encode(digest, game.claimableWinningsOf(owner), coinflip.coinflipAmount(owner),
                sdgnrs.balanceOf(owner), wwxrp.balanceOf(owner)));
            for (uint24 lvl = 1; lvl <= 51; ++lvl) digest = keccak256(abi.encode(digest, game.entriesOwedView(lvl, owner)));
        }
    }
    function _settle(uint32 id, uint256 allowance, uint256 word) private returns (bytes32) {
        vm.recordLogs();
        uint32 settling;
        for (uint256 i; i < 200; ++i) {
            (, settling,,) = sdgnrs.redemptionBatchState();
            if (settling != id) break;
            game.mineFlip{gas: allowance}();
        }
        (, settling,,) = sdgnrs.redemptionBatchState();
        assertTrue(settling != id, "the committed batch finished");
        assertEq(_rollOf(id), _roll(word));
        // The same keeper call may close the next batch and request its fresh word.
        // Its unresolved reservation is independent of the batch just consumed.
        uint256 nextReserve;
        if (settling != 0) {
            assertEq(settling, id + 1);
            (,,uint96 nextBase,,uint16 nextRoll,) = sdgnrs.redemptionBatches(settling);
            assertEq(nextRoll, 0, "the next batch cannot consume this word");
            nextReserve = uint256(nextBase) * 175 / 100;
        }
        assertEq(sdgnrs.pendingRedemptionEthValue(), nextReserve);
        for (uint256 i; i < OWNERS; ++i) assertEq(_claimTokens(_owner(i), id), 0);
        return _awardDigest(vm.getRecordedLogs(), id);
    }
    function _compare(uint256 word, bool delayed) private {
        uint32 id = _queue();
        uint256 escrow = _escrow();
        assertGt(escrow, 0);
        _publish(word, delayed);
        (uint128 batchTokens,,uint96 base,,,) = sdgnrs.redemptionBatches(id);
        assertEq(batchTokens, escrow);
        assertGt(base, 0);
        assertEq(_openBatchId(), id + 1);
        assertEq(_escrow(), 0);
        uint256 snap = vm.snapshotState();
        bytes32 full = _settle(id, 15_000_000, word);
        assertTrue(vm.revertToState(snap));
        snap = vm.snapshotState();
        assertEq(_settle(id, 7_000_000, word), full, "gas partition cannot change owner awards");
        assertTrue(vm.revertToState(snap));
        // These mutations happen after the request fixed the price. They cannot change
        // that batch's base, score or word; new burns belong to the next request.
        mockStETH.mint(address(sdgnrs), 100 ether);
        uint256 nextAmount = _minimumLiveBurn();
        _burn(alice, nextAmount);
        assertEq(_claimTokens(alice, id + 1), nextAmount);
        (,,uint96 unchanged,,,) = sdgnrs.redemptionBatches(id);
        assertEq(unchanged, base);
        assertEq(_settle(id, 7_000_000, word), full, "later backing and burns cannot rewrite committed awards");
        assertEq(_claimTokens(alice, id + 1), nextAmount, "next batch was not consumed by the known word");
    }
    function test_NormalOddWordCommitment() public { _compare(7419, false); }
    function test_NormalEvenWordCommitment() public { _compare(7076, false); }
    function test_DelayedOddWordCommitment() public { _compare(7419, true); }
    function test_DelayedEvenWordCommitment() public { _compare(7076, true); }
}
