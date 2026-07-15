// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";

/// @title WWXRPDailyDraw -- Behavioral tests for the WWXRP daily burn draw
/// @notice Drives the REAL advance/VRF pipeline (no planted words on happy
///         paths): entries burn on day d, the ground VRF word for day d+1 is
///         delivered through MockVRFCoordinator, and claims recompute the
///         outcome from rngWordForDay(d+1).
contract WWXRPDailyDrawTest is DeployProtocol {
    // Mirror of the contract's domain tags (compile-time constants there).
    bytes32 private constant DOM_BIG = "WWXRP_DRAW_BIG";
    bytes32 private constant DOM_SMALL = "WWXRP_DRAW_SMALL";
    bytes32 private constant DOM_WIN_BUCKET = "WWXRP_DRAW_WIN_BUCKET";
    bytes32 private constant DOM_WINNER = "WWXRP_DRAW_WINNER";

    address internal alice;
    address internal bob;

    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
    }

    // ──────────────────────────────────────────────────────────────────────
    // Helpers
    // ──────────────────────────────────────────────────────────────────────

    /// @dev Complete a full day: advanceGame -> VRF fulfill -> drain to unlock.
    function _completeDay(uint256 vrfWord) internal {
        game.advanceGame();
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            mockVRF.fulfillRandomWords(reqId, vrfWord);
            _lastFulfilledReqId = reqId;
        }
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.advanceGame();
        }
    }

    /// @dev Seal the current day (fresh lastVrfProcessed) and fund players.
    function _bootstrap() internal {
        _completeDay(uint256(keccak256("boot")));
        vm.startPrank(address(game));
        wwxrp.mintPrize(alice, 1_000_000 ether);
        wwxrp.mintPrize(bob, 1_000_000 ether);
        vm.stopPrank();
    }

    function _warpNextDay() internal {
        vm.warp(vm.getBlockTimestamp() + 1 days);
    }

    /// @dev Mirror of the contract's outcome hash derivation.
    function _h(
        bytes32 dom,
        uint24 day,
        uint256 word
    ) internal view returns (uint256) {
        return
            uint256(
                keccak256(abi.encodePacked(dom, address(wwxrp), day, word))
            );
    }

    /// @dev Grind a VRF word whose recorded value (nudges are zero in these
    ///      tests) produces the requested gates/bucket for participation day.
    ///      kind: 0 = no prize, 1 = BIG in wantBucket, 2 = SMALL in wantBucket.
    function _grindWord(
        uint24 day,
        uint8 kind,
        uint8 wantBucket
    ) internal view returns (uint256 w) {
        for (w = uint256(keccak256(abi.encode(day, kind, wantBucket))); ; w++) {
            bool big = _h(DOM_BIG, day, w) % 365 == 0;
            bool small = !big && _h(DOM_SMALL, day, w) % 30 == 0;
            if (kind == 0) {
                if (!big && !small) return w;
                continue;
            }
            if ((kind == 1 && !big) || (kind == 2 && !small)) continue;
            if (_h(DOM_WIN_BUCKET, day, w) % 10 == wantBucket) return w;
        }
    }

    /// @dev Grind an address whose (day, player) bucket equals `wantBucket`.
    function _addrInBucket(
        uint24 day,
        uint8 wantBucket,
        string memory tag
    ) internal returns (address a) {
        for (uint256 i = 0; ; i++) {
            a = makeAddr(string(abi.encodePacked(tag, i)));
            if (wwxrp.bucketOf(day, a) == wantBucket) return a;
        }
    }

    /// @dev Enter the draw as `player` for `amount`, minting the WWXRP first.
    function _enterAs(address player, uint256 amount) internal {
        vm.prank(address(game));
        wwxrp.mintPrize(player, amount);
        vm.prank(player);
        wwxrp.enter(amount);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Entry
    // ──────────────────────────────────────────────────────────────────────

    function test_EnterBelowMinBurnReverts() public {
        _bootstrap();
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("BelowMinBurn()"));
        wwxrp.enter(0);
        vm.expectRevert(abi.encodeWithSignature("BelowMinBurn()"));
        wwxrp.enter(25 ether - 1);
        // Exactly the minimum is accepted.
        wwxrp.enter(25 ether);
        vm.stopPrank();
    }

    function test_EnterAtGenesisNoDayCompleted() public {
        // No day sealed yet: entry is open immediately (same model as flip
        // deposits — day-1 entries settle on day 2's fresh VRF word).
        vm.prank(address(game));
        wwxrp.mintPrize(alice, 200 ether);
        vm.prank(alice);
        wwxrp.enter(100 ether);
        uint24 day = game.currentDayView();
        (, , uint32 count) = wwxrp.bucketInfo(day, wwxrp.bucketOf(day, alice));
        assertEq(count, 1, "genesis entry recorded");
    }

    function test_EnterDayMatchesGameDayIndex() public {
        // enter() derives the day locally via GameTimeLib; it must agree with
        // the game's own day view (entry recorded under the same index).
        _bootstrap();
        uint24 day = game.currentDayView();
        uint8 bucket = wwxrp.bucketOf(day, alice);
        vm.prank(alice);
        wwxrp.enter(100 ether);
        (, , uint32 count) = wwxrp.bucketInfo(day, bucket);
        assertEq(count, 1, "entry recorded under the game's day index");
    }

    function test_EnterRecordsEntryAndBurns() public {
        _bootstrap();
        uint24 day = game.currentDayView();
        uint8 bucket = wwxrp.bucketOf(day, alice);
        uint256 balBefore = wwxrp.balanceOf(alice);
        uint256 supplyBefore = wwxrp.totalSupply();

        vm.prank(alice);
        wwxrp.enter(500 ether);

        assertEq(wwxrp.balanceOf(alice), balBefore - 500 ether, "burned");
        assertEq(wwxrp.totalSupply(), supplyBefore - 500 ether, "supply");

        (uint256 raw, uint256 total, uint32 count) = wwxrp.bucketInfo(
            day,
            bucket
        );
        assertEq(raw, 500, "raw (whole WWXRP)");
        // Fresh address: activity 0 -> 1.0x -> effective == whole tokens.
        assertEq(total, 500, "total");
        assertEq(count, 1, "count");

        (address player, uint256 cum) = wwxrp.entryAt(day, bucket, 0);
        assertEq(player, alice, "player");
        assertEq(cum, 500, "cum endpoint");
    }

    function test_EnterMultipleCumulativeIntervals() public {
        _bootstrap();
        uint24 day = game.currentDayView();
        // Force both players into the SAME bucket to test interval stacking.
        uint8 bucket = wwxrp.bucketOf(day, alice);
        address bob2 = _addrInBucket(day, bucket, "bobSameBucket");

        vm.prank(alice);
        wwxrp.enter(200 ether);
        _enterAs(bob2, 300 ether);
        vm.prank(alice);
        wwxrp.enter(100 ether);

        (uint256 raw, uint256 total, uint32 count) = wwxrp.bucketInfo(
            day,
            bucket
        );
        assertEq(raw, 600, "raw (whole WWXRP)");
        assertEq(total, 600, "total");
        assertEq(count, 3, "count");

        (address p0, uint256 c0) = wwxrp.entryAt(day, bucket, 0);
        (address p1, uint256 c1) = wwxrp.entryAt(day, bucket, 1);
        (address p2, uint256 c2) = wwxrp.entryAt(day, bucket, 2);
        assertEq(p0, alice);
        assertEq(c0, 200);
        assertEq(p1, bob2);
        assertEq(c1, 500);
        assertEq(p2, alice);
        assertEq(c2, 600);
    }

    function test_BucketDeterministicAndDayScoped() public {
        _bootstrap();
        uint24 day = game.currentDayView();
        uint8 b1 = wwxrp.bucketOf(day, alice);
        uint8 b2 = wwxrp.bucketOf(day, alice);
        assertEq(b1, b2, "stable within day");
        assertLt(b1, 10, "in range");
        // Matches the documented derivation exactly.
        uint8 expected = uint8(
            uint256(
                keccak256(
                    abi.encodePacked(
                        bytes32("WWXRP_DRAW_BUCKET"),
                        block.chainid,
                        address(wwxrp),
                        day,
                        alice
                    )
                )
            ) % 10
        );
        assertEq(b1, expected, "derivation");
    }

    function test_ScoreOverflowGuard() public {
        _bootstrap();
        // Accumulators are whole-WWXRP units: overflow needs (2^96) tokens.
        uint256 huge = (uint256(type(uint96).max) + 1) * 1 ether;
        vm.prank(address(game));
        wwxrp.mintPrize(alice, huge);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("ScoreOverflow()"));
        wwxrp.enter(huge);
    }

    function test_EnterDustBurnsButAddsNoWeight() public {
        _bootstrap();
        uint24 day = game.currentDayView();
        uint8 bucket = wwxrp.bucketOf(day, alice);
        uint256 supplyBefore = wwxrp.totalSupply();
        vm.prank(alice);
        wwxrp.enter(25.9 ether);
        assertEq(
            wwxrp.totalSupply(),
            supplyBefore - 25.9 ether,
            "full amount burned"
        );
        (uint256 raw, uint256 total, ) = wwxrp.bucketInfo(day, bucket);
        assertEq(raw, 25, "dust excluded from raw");
        assertEq(total, 25, "dust excluded from weight");
    }

    // ──────────────────────────────────────────────────────────────────────
    // Multiplier rescale
    // ──────────────────────────────────────────────────────────────────────

    function test_DrawMultBpsEndpointsAndShape() public view {
        assertEq(wwxrp.drawMultBps(0), 10_000, "1.0x at zero activity");
        assertEq(wwxrp.drawMultBps(30_000), 30_000, "3.0x at cap");
        assertEq(wwxrp.drawMultBps(1_000_000), 30_000, "saturates past cap");
        // Old decimator cap (235 pts): base 17_049 -> 10_000 + 7_049*20_000/7_833.
        assertEq(wwxrp.drawMultBps(235), 27_998, "seg-A knee");
        // Monotonic through the knees.
        uint256 prev = wwxrp.drawMultBps(0);
        uint16[7] memory pts = [100, 235, 400, 500, 5_000, 29_999, 30_000];
        for (uint256 i = 0; i < pts.length; i++) {
            uint256 cur = wwxrp.drawMultBps(pts[i]);
            assertGe(cur, prev, "monotonic");
            prev = cur;
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // Claim
    // ──────────────────────────────────────────────────────────────────────

    function test_ClaimBigHappyPath() public {
        _bootstrap();
        uint24 day = game.currentDayView();
        uint8 bucket = wwxrp.bucketOf(day, alice);

        uint256 gasBefore = gasleft();
        vm.prank(alice);
        wwxrp.enter(500 ether);
        emit log_named_uint("enter gas", gasBefore - gasleft());

        _warpNextDay();
        _completeDay(_grindWord(day, 1, bucket));
        assertTrue(game.rngWordForDay(day + 1) != 0, "word recorded");

        (
            bool wordAvailable,
            bool prize,
            bool big,
            uint8 winningBucket,
            uint256 roll,
            uint256 totalScore,

        ) = wwxrp.previewOutcome(day);
        assertTrue(wordAvailable && prize && big, "BIG preview");
        assertEq(winningBucket, bucket, "bucket");
        assertEq(totalScore, 500, "total (whole WWXRP)");
        assertLt(roll, totalScore, "roll range");

        uint256 flipBalBefore = coin.balanceOf(alice);
        uint256 stakeBefore = coinflip.coinflipAmount(alice);
        gasBefore = gasleft();
        wwxrp.claim(day, 0);
        emit log_named_uint("claim gas", gasBefore - gasleft());
        assertEq(
            coinflip.coinflipAmount(alice) - stakeBefore,
            100_000 ether,
            "BIG prize credited as coinflip stake"
        );
        assertEq(coin.balanceOf(alice), flipBalBefore, "no direct FLIP mint");
        assertTrue(wwxrp.dayClaimed(day), "claimed flag");
    }

    function test_ClaimSmallHappyPath() public {
        _bootstrap();
        uint24 day = game.currentDayView();
        uint8 bucket = wwxrp.bucketOf(day, alice);
        vm.prank(alice);
        wwxrp.enter(500 ether);

        _warpNextDay();
        _completeDay(_grindWord(day, 2, bucket));

        (, bool prize, bool big, , , , ) = wwxrp.previewOutcome(day);
        assertTrue(prize && !big, "SMALL preview");

        uint256 stakeBefore = coinflip.coinflipAmount(alice);
        wwxrp.claim(day, 0);
        assertEq(
            coinflip.coinflipAmount(alice) - stakeBefore,
            10_000 ether,
            "SMALL prize"
        );
    }

    function test_ClaimNoPrizeReverts() public {
        _bootstrap();
        uint24 day = game.currentDayView();
        vm.prank(alice);
        wwxrp.enter(500 ether);

        _warpNextDay();
        _completeDay(_grindWord(day, 0, 0));

        (, bool prize, , , , , ) = wwxrp.previewOutcome(day);
        assertFalse(prize, "no prize preview");
        vm.expectRevert(abi.encodeWithSignature("NoPrize()"));
        wwxrp.claim(day, 0);
    }

    function test_ClaimEmptyBucketDudNoReroll() public {
        _bootstrap();
        uint24 day = game.currentDayView();
        uint8 aliceBucket = wwxrp.bucketOf(day, alice);
        vm.prank(alice);
        wwxrp.enter(500 ether);

        // Gate hits but the winning bucket is a DIFFERENT (empty) one.
        uint8 emptyBucket = aliceBucket == 9 ? 0 : aliceBucket + 1;
        _warpNextDay();
        _completeDay(_grindWord(day, 1, emptyBucket));

        (, bool prize, bool big, uint8 winningBucket, , uint256 total, ) = wwxrp
            .previewOutcome(day);
        assertTrue(big, "gate hit");
        assertFalse(prize, "dud: no prize despite other bucket entries");
        assertEq(winningBucket, emptyBucket, "no reroll to occupied bucket");
        assertEq(total, 0, "empty");

        vm.expectRevert(abi.encodeWithSignature("EmptyWinningBucket()"));
        wwxrp.claim(day, 0);
        assertFalse(wwxrp.dayClaimed(day), "no resolution state");
    }

    function test_ClaimIntervalVerification() public {
        _bootstrap();
        uint24 day = game.currentDayView();
        uint8 bucket = wwxrp.bucketOf(day, alice);
        address bob2 = _addrInBucket(day, bucket, "bobInterval");

        // Alice [0, 200), Bob [200, 500) — whole-WWXRP units.
        vm.prank(alice);
        wwxrp.enter(200 ether);
        _enterAs(bob2, 300 ether);

        _warpNextDay();
        _completeDay(_grindWord(day, 1, bucket));

        (, , , , uint256 roll, , ) = wwxrp.previewOutcome(day);
        uint32 winIdx = roll < 200 ? 0 : 1;
        uint32 loseIdx = 1 - winIdx;
        address winner = winIdx == 0 ? alice : bob2;
        address loser = winIdx == 0 ? bob2 : alice;

        // Wrong index rejected even though that entry exists.
        vm.expectRevert(abi.encodeWithSignature("NotWinningEntry()"));
        wwxrp.claim(day, loseIdx);
        // Nonexistent index rejected.
        vm.expectRevert(abi.encodeWithSignature("EntryMissing()"));
        wwxrp.claim(day, 7);

        uint256 winnerBefore = coinflip.coinflipAmount(winner);
        uint256 loserBefore = coinflip.coinflipAmount(loser);
        wwxrp.claim(day, winIdx);
        assertEq(
            coinflip.coinflipAmount(winner) - winnerBefore,
            100_000 ether,
            "winner paid"
        );
        assertEq(coinflip.coinflipAmount(loser), loserBefore, "loser unpaid");

        // Double claim rejected.
        vm.expectRevert(abi.encodeWithSignature("AlreadyClaimed()"));
        wwxrp.claim(day, winIdx);
    }

    function test_ClaimWordUnavailableReverts() public {
        _bootstrap();
        uint24 day = game.currentDayView();
        vm.prank(alice);
        wwxrp.enter(500 ether);
        // Tomorrow's word does not exist yet.
        vm.expectRevert(abi.encodeWithSignature("WordUnavailable()"));
        wwxrp.claim(day, 0);
    }

    function test_ClaimPermissionlessPaysRecordedWinner() public {
        _bootstrap();
        uint24 day = game.currentDayView();
        uint8 bucket = wwxrp.bucketOf(day, alice);
        vm.prank(alice);
        wwxrp.enter(500 ether);

        _warpNextDay();
        _completeDay(_grindWord(day, 1, bucket));

        uint256 aliceBefore = coinflip.coinflipAmount(alice);
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        wwxrp.claim(day, 0);
        assertEq(
            coinflip.coinflipAmount(alice) - aliceBefore,
            100_000 ether,
            "recorded winner paid"
        );
        assertEq(coinflip.coinflipAmount(stranger), 0, "caller gets nothing");
    }

    function test_FindWinningEntryMatchesLinearScan() public {
        _bootstrap();
        uint24 day = game.currentDayView();
        uint8 bucket = wwxrp.bucketOf(day, alice);

        // 6 entries in one bucket with varied sizes.
        vm.prank(alice);
        wwxrp.enter(50 ether);
        for (uint256 i = 0; i < 4; i++) {
            _enterAs(
                _addrInBucket(day, bucket, string(abi.encodePacked("m", i))),
                (i + 1) * 75 ether
            );
        }
        vm.prank(alice);
        wwxrp.enter(30 ether);

        _warpNextDay();
        _completeDay(_grindWord(day, 2, bucket));

        (, , , , uint256 roll, , ) = wwxrp.previewOutcome(day);
        (bool found, uint32 idx, address player) = wwxrp.findWinningEntry(day);
        assertTrue(found, "found");

        // Linear reference scan.
        uint256 prevCum = 0;
        (, , uint32 count) = wwxrp.bucketInfo(day, bucket);
        for (uint32 i = 0; i < count; i++) {
            (address p, uint256 cum) = wwxrp.entryAt(day, bucket, i);
            if (roll >= prevCum && roll < cum) {
                assertEq(idx, i, "binary == linear index");
                assertEq(player, p, "binary == linear player");
                break;
            }
            prevCum = cum;
        }

        // The located entry claims successfully.
        uint256 before = coinflip.coinflipAmount(player);
        wwxrp.claim(day, idx);
        assertEq(
            coinflip.coinflipAmount(player) - before,
            10_000 ether,
            "paid"
        );
    }

    // ──────────────────────────────────────────────────────────────────────
    // Returns: derivation equivalence, rates, and weight proportionality
    // ──────────────────────────────────────────────────────────────────────

    /// @notice Pin the contract's outcome derivation to the mirrored formula
    ///         across 10 arbitrary words delivered through the REAL pipeline.
    ///         This equivalence is what licenses the pure-mirror statistical
    ///         tests below to speak for the contract.
    function test_PreviewMatchesMirroredDerivationAcrossDays() public {
        _bootstrap();
        for (uint256 i = 0; i < 10; i++) {
            uint24 day = game.currentDayView();
            vm.prank(alice);
            wwxrp.enter(100 ether);
            _warpNextDay();
            _completeDay(uint256(keccak256(abi.encode("mirror", i))));
            uint256 recorded = game.rngWordForDay(day + 1);
            assertTrue(recorded != 0, "word recorded");

            (
                bool wordAvailable,
                bool prize,
                bool big,
                uint8 winningBucket,
                uint256 roll,
                uint256 total,

            ) = wwxrp.previewOutcome(day);
            assertTrue(wordAvailable, "available");

            bool mBig = _h(DOM_BIG, day, recorded) % 365 == 0;
            bool mSmall = !mBig && _h(DOM_SMALL, day, recorded) % 30 == 0;
            assertEq(big, mBig, "BIG gate mirror");
            if (!mBig && !mSmall) {
                assertFalse(prize, "no-gate day pays nothing");
                continue;
            }
            assertEq(
                winningBucket,
                uint8(_h(DOM_WIN_BUCKET, day, recorded) % 10),
                "bucket mirror"
            );
            if (total != 0) {
                assertTrue(prize, "gate + entries = prize");
                assertEq(
                    roll,
                    _h(DOM_WINNER, day, recorded) % total,
                    "roll mirror"
                );
            }
        }
    }

    /// @notice Gate and bucket frequencies over 100k mirrored words (exact
    ///         derivation pinned above). Deterministic sample; bounds are
    ///         ~5 standard deviations around the design rates.
    function test_GateAndBucketRates_100k() public view {
        uint24 day = 7;
        uint256 nBig;
        uint256 nSmall;
        uint256[10] memory bucketHits;
        for (uint256 i = 0; i < 100_000; i++) {
            uint256 w = uint256(keccak256(abi.encode("rate", i)));
            bool big = _h(DOM_BIG, day, w) % 365 == 0;
            if (big) nBig++;
            else if (_h(DOM_SMALL, day, w) % 30 == 0) nSmall++;
            bucketHits[_h(DOM_WIN_BUCKET, day, w) % 10]++;
        }
        // BIG 1/365: expect ~274 (sd ~16.5).
        assertGt(nBig, 190, "BIG rate low");
        assertLt(nBig, 360, "BIG rate high");
        // SMALL (364/365)/30: expect ~3324 (sd ~57).
        assertGt(nSmall, 3040, "SMALL rate low");
        assertLt(nSmall, 3620, "SMALL rate high");
        // Buckets uniform: expect 10_000 each (sd ~95).
        for (uint256 b = 0; b < 10; b++) {
            assertGt(bucketHits[b], 9_500, "bucket cold");
            assertLt(bucketHits[b], 10_500, "bucket hot");
        }
    }

    /// @notice Winner selection lands on each entry in proportion to its
    ///         recorded weight: 100/200/300/400 burns at 1.0x -> intervals
    ///         [0,100) [100,300) [300,600) [600,1000), sampled with 50k
    ///         uniform rolls against the endpoints enter() actually stored.
    function test_WinnerFrequencyProportionalToWeight_50k() public {
        _bootstrap();
        uint24 day = game.currentDayView();
        uint8 bucket = wwxrp.bucketOf(day, alice);

        vm.prank(alice);
        wwxrp.enter(100 ether);
        for (uint256 i = 0; i < 3; i++) {
            _enterAs(
                _addrInBucket(day, bucket, string(abi.encodePacked("w", i))),
                (i + 2) * 100 ether
            );
        }

        (, uint256 total, uint32 count) = wwxrp.bucketInfo(day, bucket);
        assertEq(total, 1000, "total weight");
        uint256[] memory ends = new uint256[](count);
        for (uint32 i = 0; i < count; i++) {
            (, ends[i]) = wwxrp.entryAt(day, bucket, i);
        }

        uint256[] memory hits = new uint256[](count);
        for (uint256 i = 0; i < 50_000; i++) {
            uint256 roll = _h(
                DOM_WINNER,
                day,
                uint256(keccak256(abi.encode("prop", i)))
            ) % total;
            for (uint32 e = 0; e < count; e++) {
                if (roll < ends[e]) {
                    hits[e]++;
                    break;
                }
            }
        }
        // Expected 5k/10k/15k/20k; allow ~10% relative slack (>>5 sd).
        uint256 prevEnd = 0;
        for (uint32 e = 0; e < count; e++) {
            uint256 expected = ((ends[e] - prevEnd) * 50_000) / total;
            assertGt(hits[e], expected - expected / 10, "share low");
            assertLt(hits[e], expected + expected / 10, "share high");
            prevEnd = ends[e];
        }
    }

    /// @notice enter() applies the activity multiplier to recorded weight:
    ///         capped score triples it; a mid-curve score matches drawMultBps
    ///         exactly. (Every other test runs fresh addresses at 1.0x.)
    function test_EnterAppliesActivityMultiplier() public {
        _bootstrap();
        uint24 day = game.currentDayView();
        uint8 bucket = wwxrp.bucketOf(day, alice);

        vm.mockCall(
            address(game),
            abi.encodeWithSignature("playerActivityScore(address)", alice),
            abi.encode(uint256(30_000))
        );
        vm.prank(alice);
        wwxrp.enter(100 ether);
        (, uint256 cum0) = wwxrp.entryAt(day, bucket, 0);
        assertEq(cum0, 300, "capped activity = 3x weight");

        vm.mockCall(
            address(game),
            abi.encodeWithSignature("playerActivityScore(address)", alice),
            abi.encode(uint256(235))
        );
        vm.prank(alice);
        wwxrp.enter(100 ether);
        (, uint256 cum1) = wwxrp.entryAt(day, bucket, 1);
        assertEq(
            cum1 - cum0,
            (100 ether * wwxrp.drawMultBps(235)) / (10_000 * 1 ether),
            "seg-A knee weight matches drawMultBps"
        );
        vm.clearMockedCalls();
    }

    /// @notice Documented expected daily emission stays under ~606 FLIP:
    ///         BIG/365 + SMALL*(364/365)/30, straight from the constants.
    function test_ExpectedDailyEmissionBound() public view {
        uint256 evPerDay = wwxrp.BIG_PRIZE() /
            365 +
            (wwxrp.SMALL_PRIZE() * 364) /
            (365 * 30);
        assertGt(evPerDay, 600 ether, "EV floor");
        assertLt(evPerDay, 610 ether, "EV ceiling");
    }

    // ──────────────────────────────────────────────────────────────────────
    // Access control blast radius
    // ──────────────────────────────────────────────────────────────────────

    function test_MintForGameStillRejectsArbitraryCallers() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OnlyGame()"));
        coin.mintForGame(alice, 1 ether);
        // Prizes flow through creditFlip — WWXRP holds NO FLIP mint authority.
        vm.prank(address(wwxrp));
        vm.expectRevert(abi.encodeWithSignature("OnlyGame()"));
        coin.mintForGame(alice, 1 ether);
    }

    function test_CreditFlipRejectsArbitraryCallers() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OnlyFlipCreditors()"));
        coinflip.creditFlip(alice, 1 ether);
    }

    function test_BurnForGameStillGameOnly() public {
        _bootstrap();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OnlyMinter()"));
        wwxrp.burnForGame(alice, 1 ether);
    }
}
