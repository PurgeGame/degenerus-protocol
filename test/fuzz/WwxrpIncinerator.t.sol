// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title WwxrpIncineratorTest -- Century BAF-incinerator draw.
///
/// @notice A daily-draw enter() burn made during a level x99 also arms the
///         upcoming x00 bracket: if that century's BAF skips (daily flip
///         lost), the advance path pays 25% of the would-be BAF pool to one
///         burn-weighted winner drawn over the bracket's cumulative
///         intervals. Incinerator scores are full 18-decimal wei (the daily
///         draw truncates to whole tokens) and saturate at uint192 instead
///         of reverting.
///
/// @dev Two layers:
///      1. Unit tests: force the game level via vm.store (slot 0, confirmed
///         via `forge inspect DegenerusGame storageLayout`), enter via real
///         burns, resolve via a pranked game caller.
///      2. Driven e2e: force level 98, then run the game organically across
///         the 99 -> 100 transition with VRF words parity-forced, covering
///         both the skip (payout) and fire (entries die) branches.
contract WwxrpIncineratorTest is DeployProtocol {
    uint256 private constant SLOT_0 = 0;
    uint256 private constant LEVEL_SHIFT = 96; // slot 0 bytes [12:15): level (uint24)
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2; // [future:128][next:128]

    bytes32 private constant DOM_INCIN_WINNER = "WWXRP_INCIN_WINNER";
    uint256 private constant BPS = 10_000;

    event IncineratorEntered(
        uint24 indexed bracket,
        address indexed player,
        uint32 entryIndex,
        uint256 burnAmount,
        uint256 effectiveScore,
        uint256 cumulativeScore
    );

    event IncineratorResolved(
        uint24 indexed bracket,
        address indexed winner,
        uint256 poolWei,
        uint256 roll,
        uint256 totalScore
    );

    address private alice;
    address private bob;
    address private buyer;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        alice = makeAddr("incin_alice");
        bob = makeAddr("incin_bob");
        buyer = makeAddr("incin_buyer");
        vm.deal(buyer, 100_000 ether);
        vm.deal(address(game), 2_000 ether);
    }

    // ==================== Helpers ====================

    function _setLevel(uint24 lvl) internal {
        uint256 s0 = uint256(vm.load(address(game), bytes32(SLOT_0)));
        s0 &= ~(uint256(0xFFFFFF) << LEVEL_SHIFT);
        s0 |= uint256(lvl) << LEVEL_SHIFT;
        vm.store(address(game), bytes32(SLOT_0), bytes32(s0));
    }

    /// @dev Mint WWXRP to `player` and enter the daily draw (which piggybacks
    ///      the incinerator entry when the level is an x99).
    function _enterAs(address player, uint256 amount) internal {
        vm.prank(address(game));
        wwxrp.mintPrize(player, amount);
        vm.prank(player);
        wwxrp.enter(amount);
    }

    /// @dev Mirror of the contract's winner-roll derivation.
    function _roll(uint24 bracket, uint256 word, uint256 total) internal view returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        DOM_INCIN_WINNER,
                        address(wwxrp),
                        bracket,
                        word
                    )
                )
            ) % total;
    }

    // ==================== Unit: entry recording ====================

    function testEnterOutsideX99RecordsNoIncineratorEntry() public {
        // Default level (not an x99) and an explicit x00.
        _enterAs(alice, 100 ether);
        _setLevel(100);
        _enterAs(alice, 100 ether);

        (uint256 total100, uint32 count100) = wwxrp.incineratorInfo(100);
        (uint256 total101, uint32 count101) = wwxrp.incineratorInfo(101);
        (uint256 total200, uint32 count200) = wwxrp.incineratorInfo(200);
        assertEq(total100 + total101 + total200, 0, "no incinerator score");
        assertEq(uint256(count100) + count101 + count200, 0, "no entries");
    }

    function testEnterAtX99RecordsDualEntryFullPrecision() public {
        _setLevel(99);

        // Fractional amount: the daily draw truncates to whole tokens, the
        // incinerator records full wei.
        uint256 amt = 25 ether + 0.5 ether;
        vm.prank(address(game));
        wwxrp.mintPrize(alice, amt);
        vm.expectEmit(true, true, false, true, address(wwxrp));
        emit IncineratorEntered(100, alice, 0, amt, amt, amt);
        vm.prank(alice);
        wwxrp.enter(amt);

        (uint256 total, uint32 count) = wwxrp.incineratorInfo(100);
        assertEq(total, amt, "full-wei score at 1.0x activity");
        assertEq(count, 1, "one entry");

        (address p0, uint256 cum0) = wwxrp.incineratorEntryAt(100, 0);
        assertEq(p0, alice, "entry player");
        assertEq(cum0, amt, "entry endpoint");

        // Second entrant appends a cumulative interval.
        _enterAs(bob, 100 ether);
        (total, count) = wwxrp.incineratorInfo(100);
        assertEq(total, amt + 100 ether, "cumulative total");
        assertEq(count, 2, "two entries");
        (address p1, uint256 cum1) = wwxrp.incineratorEntryAt(100, 1);
        assertEq(p1, bob, "second player");
        assertEq(cum1, amt + 100 ether, "second endpoint");
    }

    function testEnterAtLaterCenturyUsesItsBracket() public {
        _setLevel(199);
        _enterAs(alice, 50 ether);

        (uint256 total, uint32 count) = wwxrp.incineratorInfo(200);
        assertEq(total, 50 ether, "bracket 200 armed");
        assertEq(count, 1, "one entry");
        (uint256 total100, ) = wwxrp.incineratorInfo(100);
        assertEq(total100, 0, "bracket 100 untouched");
    }

    function testActivityMultiplierWeighsIncineratorScore() public {
        _setLevel(99);

        uint256 score = 500;
        vm.mockCall(
            address(game),
            abi.encodeWithSignature("playerActivityScore(address)", alice),
            abi.encode(score)
        );
        uint256 mult = wwxrp.drawMultBps(score);
        assertGt(mult, BPS, "mocked score maps above 1.0x");

        _enterAs(alice, 100 ether);
        vm.clearMockedCalls();

        (uint256 total, ) = wwxrp.incineratorInfo(100);
        assertEq(total, (100 ether * mult) / BPS, "activity-weighted full-wei score");
    }

    function testScoreSaturatesInsteadOfReverting() public {
        _setLevel(99);

        // First burn saturates the uint192 bracket accumulator (and the daily
        // draw's uint96 bucket accumulator) without reverting.
        uint256 mega = uint256(type(uint192).max);
        _enterAs(alice, mega);
        (uint256 total, uint32 count) = wwxrp.incineratorInfo(100);
        assertEq(total, type(uint192).max, "saturated at uint192.max");
        assertEq(count, 1, "entry recorded");

        // Post-cap entry: accepted, zero-width interval.
        _enterAs(bob, 100 ether);
        (total, count) = wwxrp.incineratorInfo(100);
        assertEq(total, type(uint192).max, "total unchanged");
        assertEq(count, 2, "post-cap entry recorded");
        (address p1, uint256 cum1) = wwxrp.incineratorEntryAt(100, 1);
        assertEq(p1, bob, "post-cap player recorded");
        assertEq(cum1, type(uint192).max, "zero-width endpoint");

        // Any roll lands in alice's interval; bob can never win.
        vm.prank(address(game));
        address winner = wwxrp.resolveIncinerator(100, uint256(keccak256("sat_word")), 1 ether);
        assertEq(winner, alice, "zero-width entry cannot win");
    }

    // ==================== Unit: resolution ====================

    function testResolveOnlyGame() public {
        vm.expectRevert(abi.encodeWithSignature("OnlyMinter()"));
        vm.prank(alice);
        wwxrp.resolveIncinerator(100, 1, 1 ether);
    }

    function testResolveEmptyBracketReturnsZero() public {
        vm.prank(address(game));
        address winner = wwxrp.resolveIncinerator(100, uint256(keccak256("w")), 1 ether);
        assertEq(winner, address(0), "empty bracket resolves to zero");
    }

    function testResolveWinnerMatchesIntervalRoll() public {
        _setLevel(99);
        _enterAs(alice, 100 ether); // interval [0, 100e18)
        _enterAs(bob, 300 ether); // interval [100e18, 400e18)

        uint256 word = uint256(keccak256("incin_resolve_word"));
        uint256 roll = _roll(100, word, 400 ether);
        address expected = roll < 100 ether ? alice : bob;

        vm.expectEmit(true, true, false, true, address(wwxrp));
        emit IncineratorResolved(100, expected, 5 ether, roll, 400 ether);
        vm.prank(address(game));
        address winner = wwxrp.resolveIncinerator(100, word, 5 ether);
        assertEq(winner, expected, "winner matches mirrored interval roll");
    }

    function testResolveBothIntervalsReachable() public {
        _setLevel(99);
        _enterAs(alice, 100 ether);
        _enterAs(bob, 300 ether);

        // Grind one word per side to prove both intervals are hittable.
        uint256 wordAlice;
        uint256 wordBob;
        for (uint256 w = 1; wordAlice == 0 || wordBob == 0; w++) {
            uint256 roll = _roll(100, w, 400 ether);
            if (roll < 100 ether) {
                if (wordAlice == 0) wordAlice = w;
            } else if (wordBob == 0) {
                wordBob = w;
            }
        }

        vm.prank(address(game));
        assertEq(wwxrp.resolveIncinerator(100, wordAlice, 1 ether), alice, "alice side");
        vm.prank(address(game));
        assertEq(wwxrp.resolveIncinerator(100, wordBob, 1 ether), bob, "bob side");
    }

    // ==================== Driven e2e across the century transition ====================

    /// @dev Drive the real game from a forced level 98 across the 99 -> 100
    ///      transition with every VRF word parity-forced. oddWords=false
    ///      forces the BAF fire gate to fail (skip -> incinerator payout);
    ///      oddWords=true forces it to pass (BAF fires, entries die).
    /// @return entered True once the level-99 burns were made.
    function _driveCentury(bool oddWords) internal returns (bool entered) {
        uint256 simTime = block.timestamp;

        // Organic bootstrap to a live daily cadence before forcing the level:
        // a cold-forced level leaves the advance state machine without a
        // running day cursor and the drive stalls.
        for (uint256 day = 0; day < 100; day++) {
            if (game.level() >= 2) break;
            simTime += 1 days + 1;
            vm.warp(simTime);
            _seedNextPrizePool(49.9 ether);
            _seedFuturePrizePool(100 ether);
            _buyTickets(buyer, 4000);
            for (uint256 j = 0; j < 80; j++) {
                _fulfillVrf(oddWords);
                (bool ok, ) = address(game).call(
                    abi.encodeWithSignature("advanceGame()")
                );
                if (!ok) break;
            }
        }
        assertGe(game.level(), 2, "bootstrap reached a live cadence");

        // Charity governance tracks its own sequential level and rejects the
        // forced jump; mock it out for the driven transition.
        vm.mockCall(
            ContractAddresses.GNRUS,
            abi.encodeWithSignature("pickCharity(uint24)"),
            abi.encode()
        );
        _setLevel(98);

        for (uint256 day = 0; day < 600; day++) {
            uint24 currentLevel = game.level();
            if (game.gameOver()) break;
            if (currentLevel > 100) break;

            if (currentLevel == 99 && !entered) {
                _enterAs(alice, 100 ether);
                _enterAs(bob, 300 ether);
                entered = true;
            }

            simTime += 1 days + 1;
            vm.warp(simTime);

            // Growing seed: the forced century records a ~116 ETH pool for
            // level 100, so the next level's target needs an outgrowing seed.
            _seedNextPrizePool(49.9 ether + day * 10 ether);
            _seedFuturePrizePool(100 ether);
            _buyTickets(buyer, 4000);

            for (uint256 j = 0; j < 80; j++) {
                _fulfillVrf(oddWords);
                (bool ok, ) = address(game).call(
                    abi.encodeWithSignature("advanceGame()")
                );
                if (!ok) break;
            }
        }
    }

    function testDrivenCenturySkipPaysIncineratorWinner() public {
        vm.recordLogs();
        bool entered = _driveCentury(false);

        assertTrue(entered, "level-99 burns were made");
        assertGt(game.level(), 100, "game advanced past level 100");

        // Exactly one IncineratorResolved for bracket 100.
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256(
            "IncineratorResolved(uint24,address,uint256,uint256,uint256)"
        );
        uint256 found;
        address winner;
        uint256 poolWei;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != address(wwxrp)) continue;
            if (logs[i].topics[0] != topic) continue;
            assertEq(uint256(logs[i].topics[1]), 100, "bracket 100");
            winner = address(uint160(uint256(logs[i].topics[2])));
            (poolWei, , ) = abi.decode(logs[i].data, (uint256, uint256, uint256));
            found++;
        }
        assertEq(found, 1, "exactly one incinerator resolution");
        assertTrue(winner == alice || winner == bob, "winner is an entrant");
        assertGt(poolWei, 0, "non-zero pool");

        // The winner's ETH landed claimable-side; the loser got nothing
        // (neither address plays any other ETH-earning surface here).
        address loser = winner == alice ? bob : alice;
        assertEq(game.claimableWinningsOf(winner), poolWei, "winner credited poolWei");
        assertEq(game.claimableWinningsOf(loser), 0, "loser uncredited");
    }

    function testDrivenCenturyFireLeavesIncineratorUnresolved() public {
        vm.recordLogs();
        bool entered = _driveCentury(true);

        assertTrue(entered, "level-99 burns were made");
        assertGt(game.level(), 100, "game advanced past level 100");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256(
            "IncineratorResolved(uint24,address,uint256,uint256,uint256)"
        );
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(wwxrp) && logs[i].topics[0] == topic) {
                fail("incinerator must not resolve on a fired BAF");
            }
        }

        // Entries remain recorded (dead), and no ETH was credited.
        (uint256 total, uint32 count) = wwxrp.incineratorInfo(100);
        assertEq(total, 400 ether, "entries persist unresolved");
        assertEq(count, 2, "both entries persist");
        assertEq(game.claimableWinningsOf(alice), 0, "alice uncredited");
        assertEq(game.claimableWinningsOf(bob), 0, "bob uncredited");
    }

    // ==================== Driven-loop internals ====================

    function _seedNextPrizePool(uint256 targetNext) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
        uint128 currentNext = uint128(packed);
        if (uint256(currentNext) >= targetNext) return;
        uint128 currentFuture = uint128(packed >> 128);
        uint256 newPacked = (uint256(currentFuture) << 128) | targetNext;
        vm.store(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)), bytes32(newPacked));
    }

    function _seedFuturePrizePool(uint256 targetFuture) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
        uint128 currentNext = uint128(packed);
        uint128 currentFuture = uint128(packed >> 128);
        if (uint256(currentFuture) >= targetFuture) return;
        uint256 newPacked = (targetFuture << 128) | uint256(currentNext);
        vm.store(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)), bytes32(newPacked));
    }

    function _buyTickets(address who, uint256 qty) internal {
        (, , , bool rngLocked_, uint256 priceWei) = game.purchaseInfo();
        if (rngLocked_) return;
        if (game.gameOver()) return;

        uint256 cost = (priceWei * qty) / 400;
        if (cost == 0) return;
        if (who.balance < cost) vm.deal(who, cost + 10 ether);

        vm.prank(who);
        try game.purchase{value: cost}(who, qty, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
    }

    /// @dev Fulfill any pending VRF request with a parity-forced word: even
    ///      words fail the BAF fire gate (rngWord & 1 == 1), odd words pass
    ///      it. No reverseFlip nudges run here, so parity survives
    ///      _applyDailyRng.
    function _fulfillVrf(bool odd) internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;

        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;

        uint256 randomWord = uint256(
            keccak256(abi.encode("incin_word", block.timestamp, game.level(), reqId))
        );
        randomWord = odd ? (randomWord | 1) : (randomWord & ~uint256(1));
        if (randomWord == 0) randomWord = 2;
        try mockVRF.fulfillRandomWords(reqId, randomWord) {} catch {}
    }
}
