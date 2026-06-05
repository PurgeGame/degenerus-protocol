// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title RngRetryLootboxStall — PoC for the phase-blind `isRetry` RNG bug (v60 R2, RNGRETRY).
/// @notice A mid-day lootbox VRF request and the daily VRF request share one
///         (vrfRequestId, rngRequestTime, rngWordCurrent) slot-set, distinguished only by
///         rngLockedFlag. `_finalizeRngRequest` computes
///             isRetry = vrfRequestId != 0 && rngRequestTime != 0 && rngWordCurrent == 0
///         which is PHASE-BLIND. If a mid-day lootbox request is still in flight (stalled ≥12h)
///         when a last-purchase-day → jackpot transition fires its daily RNG request via the
///         12h timeout branch (rngGate:1263), the daily request is misclassified as a retry,
///         so the `isTicketJackpotDay && !isRetry` block (AdvanceModule:1693-1716) is SKIPPED:
///         the sole `level = lvl` increment (:1697), `_rewardTopAffiliate`, the dec-window
///         update, and `pickCharity` never run.
///
/// @dev Two tests:
///   - testControl_NormalTransition_LevelIncrements: same drive, NO stalled lootbox →
///     the transition increments the level (proves the harness + transition work).
///   - testBug_StalledLootbox_SkipsLevelIncrement: inject a stalled mid-day lootbox request
///     before the transition → assert the level still increments. FAILS on the buggy code
///     (level stuck), PASSES once `isRetry` is made phase-aware (`&& rngLockedFlag`).
contract RngRetryLootboxStallTest is DeployProtocol {
    /// @dev prizePoolsPacked slot (confirmed via the BAF tests): [hi128 future][lo128 next].
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2;

    address private buyer;
    address private attacker;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        buyer = makeAddr("rngretry_buyer");
        attacker = makeAddr("rngretry_attacker");
        vm.deal(buyer, 1_000_000 ether);
        vm.deal(attacker, 1_000 ether);
        vm.deal(address(game), 5_000 ether);

        // Fund the VRF subscription LINK so requestLootboxRng() passes its >= 40 LINK gate.
        // Admin's constructor created subscription id 1 on the mock.
        mockVRF.fundSubscription(1, 1_000 ether);
    }

    function testControl_NormalTransition_LevelIncrements() public {
        uint24 L = _driveToLastPurchaseDay();
        emit log_named_uint("[control] level at last-purchase-day window", L);

        // No stalled lootbox: drive the transition fulfilling every VRF request.
        uint24 after_ = _driveThroughTransition(0, L);
        emit log_named_uint("[control] level after transition", after_);

        assertEq(after_, L + 1, "control: a normal last-purchase-day transition must increment the level");
    }

    function testBug_StalledLootbox_SkipsLevelIncrement() public {
        uint24 L = _driveToLastPurchaseDay();
        emit log_named_uint("[bug] level at last-purchase-day window", L);

        // --- Inject a stalled mid-day lootbox VRF request ---
        // 1) create lootbox pending (>= 1 ETH threshold) via a real purchase.
        vm.prank(attacker);
        game.purchase{value: 3 ether}(attacker, 0, 3 ether, bytes32(0), MintPaymentKind.DirectEth);

        // 2) fire the mid-day lootbox RNG request (leaves rngLockedFlag = false).
        vm.prank(attacker);
        game.requestLootboxRng();
        uint256 lootboxReqId = mockVRF.lastRequestId();

        // 3) confirm it is genuinely in flight (we will NEVER fulfill it).
        (, , bool fulfilled) = mockVRF.pendingRequests(lootboxReqId);
        assertTrue(!fulfilled, "lootbox VRF request should be pending (stalled)");

        // Drive the transition, fulfilling every NEW (daily) request but leaving the
        // lootbox request stalled. The transition fires via the 12h timeout branch.
        uint24 after_ = _driveThroughTransition(lootboxReqId, L);
        emit log_named_uint("[bug] level after transition (lootbox stalled)", after_);

        // The lootbox request must still be unfulfilled (we never fed it).
        (, , bool fulfilled2) = mockVRF.pendingRequests(lootboxReqId);
        assertTrue(!fulfilled2, "lootbox request must remain stalled for the PoC");

        // CORRECT behavior: the transition still increments the level. On the buggy code the
        // stalled lootbox makes isRetry=true and the increment is skipped (after_ == L).
        assertEq(
            after_,
            L + 1,
            "BUG: stalled mid-day lootbox made the daily transition misclassify as a retry -> level increment skipped"
        );
    }

    // ==================== Helpers ====================

    /// @notice Drive the game (level >= 1) until it sits in a last-purchase-day window with
    ///         the daily RNG already consumed and unlocked (lastPurchaseDay && !rngLocked) —
    ///         exactly the state in which requestLootboxRng() is callable.
    function _driveToLastPurchaseDay() internal returns (uint24) {
        uint256 simTime = block.timestamp;
        for (uint256 day = 0; day < 800; day++) {
            require(!game.gameOver(), "gameOver before reaching last-purchase-day");

            (, , bool lpd, bool rngL, ) = game.purchaseInfo();
            if (game.level() >= 1 && lpd && !rngL) return game.level();

            simTime += 1 days + 1;
            vm.warp(simTime);
            _seedNextPrizePool(49.9 ether);
            _buyTickets(buyer, 4000);

            for (uint256 j = 0; j < 80; j++) {
                _fulfillVrfIfPending();
                (, , bool lpd2, bool rngL2, ) = game.purchaseInfo();
                if (game.level() >= 1 && lpd2 && !rngL2) return game.level();
                (bool ok, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
                if (!ok) break;
            }
        }
        revert("did not reach a last-purchase-day window");
    }

    /// @notice Advance through the pending transition, fulfilling every VRF request except
    ///         `skipReqId` (use 0 to fulfill all). Returns the level once it changes (or after
    ///         the loop budget). Warps forward so any stalled request crosses the 12h timeout.
    function _driveThroughTransition(uint256 skipReqId, uint24 L0) internal returns (uint24) {
        uint256 simTime = block.timestamp + 1 days + 1; // new day; stalled req now > 12h old
        vm.warp(simTime);

        for (uint256 j = 0; j < 200; j++) {
            uint256 rid = mockVRF.lastRequestId();
            if (rid != 0 && rid != skipReqId) {
                (, , bool fl) = mockVRF.pendingRequests(rid);
                if (!fl) {
                    uint256 w = uint256(keccak256(abi.encode(block.timestamp, game.level(), rid)));
                    try mockVRF.fulfillRandomWords(rid, w) {} catch {}
                }
            }

            if (game.level() != L0) return game.level();

            (bool ok, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
            if (!ok) {
                // Need a fresh wall-clock day (e.g. NotTimeYet / death-clock pacing).
                simTime += 1 days + 1;
                vm.warp(simTime);
            }
        }
        return game.level();
    }

    function _buyTickets(address who, uint256 qty) internal {
        (, , , bool rngLocked_, uint256 priceWei) = game.purchaseInfo();
        if (rngLocked_ || game.gameOver()) return;
        uint256 cost = (priceWei * qty) / 400;
        if (cost == 0) return;
        if (who.balance < cost) vm.deal(who, cost + 10 ether);
        vm.prank(who);
        try game.purchase{value: cost}(who, qty, 0, bytes32(0), MintPaymentKind.DirectEth) {} catch {}
    }

    function _fulfillVrfIfPending() internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;
        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;
        uint256 randomWord = uint256(keccak256(abi.encode(block.timestamp, game.level(), reqId)));
        try mockVRF.fulfillRandomWords(reqId, randomWord) {} catch {}
    }

    function _seedNextPrizePool(uint256 targetNext) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
        uint128 currentNext = uint128(packed);
        if (uint256(currentNext) >= targetNext) return;
        uint128 currentFuture = uint128(packed >> 128);
        vm.store(
            address(game),
            bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)),
            bytes32((uint256(currentFuture) << 128) | targetNext)
        );
    }
}
