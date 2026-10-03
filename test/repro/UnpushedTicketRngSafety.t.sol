// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev Only environment setup is synthetic. Admission, packed balance writes,
///      registry allocation, trait generation, cursoring and bucket decoding are production.
contract UnpushedTicketRngHarness is DegenerusGameTicketModule {
    function initialize() external { level = 1; }
    function credit(address player, uint24 lvl, uint32 scaled) external {
        _queueEntriesScaled(player, lvl, scaled, false);
    }
    function creditWhole(address player, uint24 lvl, uint32 entries) external {
        _queueEntries(player, lvl, entries, false);
    }
    function commit(uint256 entropy, bool futurePool) external {
        rngWordCurrent = entropy < 2 ? 2 : entropy;
        _setRngSessionPublished(true);
        rngLockedFlag = true;
        if (futurePool) {
            earlyTicketLevel = 3;
            _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, MID_DAY_FUTURE_POOL);
        } else {
            ticketWriteSlot = !ticketWriteSlot;
        }
    }
    function pending(address player, uint24 lvl, bool future, bool read) external view returns (uint80) {
        return _entriesOwed(future ? _tqFarFutureKey(lvl) : read ? _tqReadKey(lvl) : _tqWriteKey(lvl), player);
    }
    function frozenLength(uint24 lvl, bool future) external view returns (uint256) {
        return _ticketQueueLength(future ? _tqFarFutureKey(lvl) : _tqReadKey(lvl));
    }
    function cursorState() external view returns (uint256) {
        return uint256(ticketCursor) | (uint256(ticketLevel) << 32) | (uint256(ticketRound) << 56);
    }
    function bucketDigest(uint24 lvl) external view returns (bytes32 digest, uint256 count) {
        for (uint256 trait; trait < 256; ++trait) {
            uint256 len = _bucketLength(lvl, uint8(trait));
            count += len;
            digest = keccak256(abi.encode(digest, trait, len));
            for (uint256 i; i < len; ++i) {
                digest = keccak256(abi.encode(digest, _bucketOwnerAtUnchecked(lvl, uint8(trait), i)));
            }
        }
    }
}

contract UnpushedTicketRngSafetyTest is Test {
    UnpushedTicketRngHarness private h;

    function setUp() public {
        vm.warp(10 days);
        h = new UnpushedTicketRngHarness();
        h.initialize();
        vm.etch(ContractAddresses.GAME_FOILPACK_MODULE, address(new DegenerusGameFoilPackModule()).code);
    }

    function _player(uint256 i) private pure returns (address) { return address(uint160(0xA1100 + i)); }

    function _drain(uint24 lvl, uint256 n, bool mutate, uint32 topup)
        private returns (bytes32 digest, uint256 entries, uint256 calls, bytes32 trajectory)
    {
        for (;;) {
            if (mutate) {
                // Exercise whole/remainder carries in the same physical pending word
                // while already-committed balances are consumed in independent lanes.
                for (uint256 i; i < n; ++i) h.credit(_player(i), lvl, topup);
                // New global IDs and another level's queues must not perturb old seeds.
                h.credit(address(uint160(0xCA000 + calls)), 2, 425);
                // This member existed before commitment. Raising its far-future owed
                // is allowed because the jackpot samples membership, not balance.
                h.creditWhole(_player(0), 6, topup);
            }
            (bool done,) = h.processTicketBatch(2);
            ++calls;
            trajectory = keccak256(abi.encode(trajectory, h.cursorState(), done));
            require(calls < 100, "bounded drain progress");
            if (done) break;
        }
        (digest, entries) = h.bucketDigest(lvl);
    }

    function _compare(uint256 entropy, uint256 n, uint32 entries, uint32 topup, bool futurePool) private {
        uint24 target = futurePool ? 3 : 1;
        for (uint256 i; i < n; ++i) h.credit(_player(i), target, entries * 100 + (futurePool ? 0 : uint32(i % 3) * 25));
        h.credit(_player(0), 6, 400);
        h.commit(entropy, futurePool);
        uint256 snapshot = vm.snapshotState();
        (bytes32 baseline, uint256 baselineEntries, uint256 baselineCalls, bytes32 baselineTrajectory) =
            _drain(target, n, false, topup);
        uint256 finalControl = h.cursorState();
        vm.revertToState(snapshot);
        (bytes32 adversarial, uint256 adversarialEntries, uint256 adversarialCalls, bytes32 adversarialTrajectory) =
            _drain(target, n, true, topup);
        assertGe(baselineEntries, n * entries, "non-vacuous original cohort materialization");
        assertEq(adversarialEntries, baselineEntries, "write credits cannot enter frozen cohort");
        assertEq(adversarial, baseline, "every trait occurrence keeps identical owner and order");
        // Access warmth may move a measured-gas checkpoint. The entire frozen
        // inventory and final round/control state must remain identical.
        assertEq(h.cursorState(), finalControl, "same completed control state under permitted write interleaving");
        assertEq(h.frozenLength(target, futurePool), 0);
        for (uint256 i; i < n; ++i) {
            assertEq(h.pending(_player(i), target, futurePool, true), 0, "frozen balance consumed exactly once");
            uint80 pending = h.pending(_player(i), target, false, false);
            assertEq(uint256(uint32(pending >> 8)) * 100 + uint8(pending), uint256(topup) * adversarialCalls,
                "new cohort retains all post-commit credit");
        }
        assertEq(uint32(h.pending(_player(0), 6, true, false) >> 8), 4 + uint32(uint256(topup) * adversarialCalls));
    }

    function test_perEntryPartialDrainsIgnoreKnownWordWriteMutations() public {
        _compare(uint256(keccak256("unpublished-entry-boundary")), 3, 1800, 725, false);
    }

    function test_seatedPartialDrainsIgnoreKnownWordWriteMutations() public {
        _compare(uint256(keccak256("unpublished-round-boundary")), 11, 400, 123, false);
    }

    function test_frozenFuturePoolCannotBeToppedUpAfterPublication() public {
        _compare(uint256(keccak256("unpublished-future-boundary")), 5, 700, 799, true);
    }

    function testFuzz_knownWordAdmissionAndDrainStayFrozen(uint256 entropy, uint32 topup) public {
        topup = uint32(bound(topup, 1, 10_000));
        _compare(entropy, 5, 28, topup, false);
    }

    function test_knownDailyWordRejectsNewFarFutureMemberWithoutAllocating() public {
        h.credit(_player(0), 6, 400);
        h.commit(0xA11CE, false);
        uint256 beforeLength = h.frozenLength(6, true);
        vm.expectRevert(bytes4(keccak256("RngLocked()")));
        h.credit(_player(1), 6, 400);
        assertEq(h.frozenLength(6, true), beforeLength);
        assertEq(h.pending(_player(1), 6, true, false), 0);
    }
}
