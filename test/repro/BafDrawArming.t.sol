// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title BafDrawArming — the game arms exactly one draw day per BAF bracket.
///
/// @notice Drives the real advance path (turbo-chained levels from genesis, the same
///         rig as TurboBafTicketFloor) to the level-10 evening latch and pins:
///         - No arm exists before the x0 latch: levels 1-9 latch lastPurchaseDay
///           without arming (their purchase levels are not x0).
///         - The x0 latch arms day+1 — the flip day the sealed window's deposits
///           stake and the day the transition word resolves.
///         - A 100-FLIP deposit inside the sealed window enters the draw, survives
///           the turbo collapse, and is the winner the transition word selects.
///         - The x0 evening latch keeps a real last-purchase window even under a
///           one-day turbo collapse (flag 2), so the armed day is depositable.
contract BafDrawArming is DeployProtocol {
    address private buyer = address(0xB4A1);
    address private minnow = address(0x314A);

    uint256 private simTime;

    /// @dev Clock offset folded into every fulfillment word (word = keccak(simTime, reqId)).
    ///      Chosen so the level-10 BAF's daily-flip bit lands 1 (a skipped BAF would leave
    ///      the draw unexercised; the epoch reachability assert guards against that).
    uint256 private constant WORD_NUDGE = 1;

    function setUp() public {
        _deployProtocol();
        simTime = block.timestamp + 1 days + WORD_NUDGE;
        vm.warp(simTime);
        vm.deal(address(game), 10_000 ether);
        vm.deal(buyer, 500_000 ether);
        mockVRF.fundSubscription(1, 1_000 ether);
        deal(address(coin), buyer, 5_000_000 ether, true);
        deal(address(coin), minnow, 1_000 ether, true);
    }

    function testLevelTenLatchArmsTheDrawAndTheMinnowCanWin() public {
        vm.pauseGasMetering();
        _driveToLevelTenLatchDay();

        // The latch armed tomorrow's flip day; nothing was armed before it
        // (asserted every pre-latch day inside the driver).
        uint24 today = game.currentDayView();
        (uint24 armedDay, uint96 totalBefore, uint32 countBefore) = coinflip.bafDrawInfo();
        assertEq(armedDay, today + 1, "the x0 latch arms day + 1");
        assertEq(totalBefore, 0, "the armed day's book opens empty");
        assertEq(countBefore, 0, "no entries precede the sealed window");

        // A minimum-size deposit inside the sealed last-purchase window enters.
        vm.prank(minnow);
        coinflip.depositCoinflip(address(0), 100 ether);

        (, uint96 total, uint32 count) = coinflip.bafDrawInfo();
        assertEq(count, 1, "the sealed-window deposit entered the draw");
        assertEq(total, 100, "weight is the raw 100-FLIP principal");

        // Run the turbo collapse out: the transition resolves the level-10 BAF.
        _runFullDay();
        assertGe(_compressedFlag(), 2, "harness: level 10 must have collapsed under turbo");
        assertEq(_bafEpoch(10), 1, "harness: the level-10 BAF must have resolved, not skipped");

        // The deciding word selects the minnow — the book's only interval.
        uint256 word = game.rngWordForDay(armedDay);
        assertTrue(word != 0, "harness: the transition word must be recorded");
        assertEq(
            coinflip.bafDrawWinner(word),
            minnow,
            "the sole sealed-window entrant wins Slice A2's draw"
        );
    }

    // ---------------------------------------------------------------------
    // Driver (shared shape with TurboBafTicketFloor)
    // ---------------------------------------------------------------------

    /// @dev Turbo-chain levels 1-9, stopping ON the day the level-10 evening latch
    ///      fires (lastPurchaseDay with the tier-2 flag; purchaseInfo's lvl reads 9).
    ///      Every pre-latch day asserts the draw is still un-armed: the levels
    ///      1-9 latches must never arm it.
    function _driveToLevelTenLatchDay() internal {
        _settleToday();
        for (uint256 i = 0; i < 120; i++) {
            require(!game.gameOver(), "harness: gameOver before the level-10 latch");
            (uint24 lvl, , bool lastPurchaseDay_, , ) = game.purchaseInfo();
            if (lastPurchaseDay_ && lvl == 9) {
                require(_compressedFlag() == 2, "harness: the x0 latch must be tier 2");
                return;
            }
            (uint24 armedDay, , ) = coinflip.bafDrawInfo();
            assertEq(armedDay, 0, "no non-x0 latch may arm the draw");
            if (!game.jackpotPhase()) {
                _seedNextPrizePool(_levelPrizePool(_level()) + 25 ether);
                _buyTickets();
                _tryCoinflipDeposit();
            }
            _runFullDay();
        }
        revert("harness: never reached the level-10 latch day");
    }

    /// @dev Run the advance chain to exhaustion on the current (already-warped) day.
    function _settleToday() internal {
        for (uint256 i = 0; i < 300; i++) {
            _fulfillPending();
            (bool ok, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
            if (!ok) break;
        }
    }

    /// @dev levelPrizePool[lvl] — the mapping sits at slot 23. levelPrizePool[L] is the
    ///      target the NEXT level's pool must exceed; 0 until first recorded.
    function _levelPrizePool(uint24 lvl) internal view returns (uint256) {
        uint256 v = uint256(
            vm.load(address(game), keccak256(abi.encode(uint256(lvl), uint256(23))))
        );
        return v < 50 ether ? 50 ether : v;
    }

    function _tryCoinflipDeposit() internal {
        vm.prank(buyer);
        try coinflip.depositCoinflip(buyer, 500 ether) {} catch {}
    }

    function _fulfillPending() internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;
        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;
        uint256 word = uint256(keccak256(abi.encode(simTime, reqId)));
        try mockVRF.fulfillRandomWords(reqId, word) {} catch {}
    }

    function _buyTickets() internal {
        (, , , bool rngLocked_, uint256 priceWei) = game.purchaseInfo();
        if (rngLocked_) return;
        vm.prank(buyer);
        game.purchase{value: (priceWei * 4000) / 400}(
            buyer,
            4000,
            0,
            bytes32(0),
            MintPaymentKind.DirectEth,
            false
        );
    }

    /// @dev Cross the day boundary and run the whole advance chain to the day seal.
    function _runFullDay() internal {
        simTime += 1 days + 1;
        vm.warp(simTime);
        for (uint256 i = 0; i < 300; i++) {
            _fulfillPending();
            (bool ok, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
            if (!ok) break;
        }
    }

    /// @dev Seed the live next-pool half (slot 2, low 104 bits) up to targetNext.
    function _seedNextPrizePool(uint256 targetNext) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(2))));
        uint256 currentNext = packed & ((uint256(1) << 104) - 1);
        if (currentNext >= targetNext) return;
        vm.store(
            address(game),
            bytes32(uint256(2)),
            bytes32((packed & ~((uint256(1) << 104) - 1)) | targetNext)
        );
    }

    // ---- storage probes (shared shape with TurboBafTicketFloor) ----

    function _level() internal view returns (uint24) {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        return uint24(s0 >> 96);
    }

    /// @dev compressedJackpotFlag — slot 0, byte 23.
    function _compressedFlag() internal view returns (uint8) {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        return uint8(s0 >> 184);
    }

    /// @dev jackpots.bafLevel[lvl].epoch — the mapping sits at Jackpots slot 2; epoch is
    ///      the low uint64 of the packed struct slot.
    function _bafEpoch(uint24 lvl) internal view returns (uint64) {
        return
            uint64(
                uint256(
                    vm.load(
                        address(jackpots),
                        keccak256(abi.encode(uint256(lvl), uint256(2)))
                    )
                )
            );
    }
}
