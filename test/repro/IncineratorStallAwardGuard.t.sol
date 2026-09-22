// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title IncineratorStallAwardGuard -- does the incinerator pay against a WINNING armed day?
///
/// @notice The x00 incinerator pays 10% of the FLIP that the armed BAF day's direct depositors
///         burned and LOST. The armed day and the BAF skip decision are only coupled when the
///         same word resolves both. This drives the one path where they can come apart: a VRF
///         stall whose retry re-fires on the wall day, so the RNGREUSE buffered clamp does not
///         engage and rngGate backfills the armed day with a DERIVED word while the transition
///         keeps the fresh one. The fulfilled word is ground so the armed day WINS (derived low
///         bit 1) and the transition LOSES (word low bit 0).
///
/// @dev Original title retained below for the lifted helpers.
/// @title WwxrpIncineratorTest -- Century BAF-incinerator draw.
///
/// @notice A daily-draw enter() burn made during a level x99 also arms the
///         upcoming x00 bracket: if that century's BAF skips (daily flip
///         lost), WWXRP credits one burn-weighted winner, drawn over the
///         bracket's cumulative intervals, with 10% of the FLIP that day's
///         direct depositors burned and lost (flip credit, never ETH). Incinerator scores are full 18-decimal wei (the daily
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
contract IncineratorStallAwardGuard is DeployProtocol {
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
        uint256 flipAward,
        uint256 roll,
        uint256 totalScore
    );

    address private alice;
    address private bob;
    address private buyer;
    address private depositor;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        alice = makeAddr("incin_alice");
        bob = makeAddr("incin_bob");
        buyer = makeAddr("incin_buyer");
        depositor = makeAddr("incin_depositor");
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

    // ==================== The stall ====================

    uint256 private constant STALL_DAYS = 3;

    /// @dev Grind a fulfilment word whose low bit loses the transition flip (BAF skips) while
    ///      the gap-day word it derives for `armedDay` wins that day's flip.
    function _grindWord(uint24 armedDay) internal pure returns (uint256 word) {
        for (uint256 i = 1; i < 4096; ++i) {
            uint256 w = uint256(keccak256(abi.encode("incin_stall", i))) & ~uint256(1);
            if (w == 0) continue;
            if (uint256(keccak256(abi.encodePacked(w, armedDay))) & 1 == 1) return w;
        }
        revert("no word found");
    }

    function _advance() internal returns (bool ok) {
        (ok, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
    }

    function testStalledCenturyIncineratorPaysAgainstTheArmedDaysResult() public {
        uint256 simTime = block.timestamp;

        for (uint256 d = 0; d < 100; d++) {
            if (game.level() >= 2) break;
            simTime += 1 days + 1;
            vm.warp(simTime);
            _seedNextPrizePool(49.9 ether);
            _seedFuturePrizePool(100 ether);
            _buyTickets(buyer, 4000);
            for (uint256 j = 0; j < 80; j++) { _fulfillVrf(false); if (!_advance()) break; }
        }
        assertGe(game.level(), 2, "bootstrap reached a live cadence");

        vm.mockCall(ContractAddresses.GNRUS, abi.encodeWithSignature("pickCharity(uint24)"), abi.encode());
        _setLevel(98);

        bool entered;
        uint24 armedDay;
        uint24 prevArmed;
        (prevArmed, , ) = coinflip.bafDrawInfo();
        for (uint256 d = 0; d < 600 && armedDay == 0; d++) {
            uint24 currentLevel = game.level();
            if (game.gameOver()) break;
            if (currentLevel > 100) break;

            if (currentLevel == 99 && !entered) {
                _enterAs(alice, 100 ether);
                _enterAs(bob, 300 ether);
                entered = true;
            }
            if (currentLevel >= 99) _selfDeposit(depositor, 1_000 ether);

            simTime += 1 days + 1;
            vm.warp(simTime);
            _seedNextPrizePool(49.9 ether + d * 10 ether);
            _seedFuturePrizePool(100 ether);
            _buyTickets(buyer, 4000);
            for (uint256 j = 0; j < 80; j++) { _fulfillVrf(false); if (!_advance()) break; }

            // The x00 last-purchase seal arms TOMORROW's flip day: take it only on the
            // advance that changes it, at level 100, and only while it is still unresolved.
            // `level` storage sits one below the purchase level, so the x00 seal happens
            // while it reads 99. Take the arm on the advance that changes it, entries made.
            {
                (uint24 nowArmed, , ) = coinflip.bafDrawInfo();
                if (entered && nowArmed != prevArmed) {
                    (uint16 rp, bool w) = coinflip.getCoinflipDayResult(nowArmed);
                    if (rp == 0 && !w) armedDay = nowArmed;
                }
                prevArmed = nowArmed;
            }
        }
        assertTrue(entered, "level-99 burns were made");
        assertGt(armedDay, 0, "the x00 last-purchase day armed the draw");

        // Deposits made after the seal, still on the sealed day, stake the armed day.
        _selfDeposit(depositor, 5_000 ether);
        (, uint96 bookTotal, uint32 bookCount) = coinflip.bafDrawInfo();
        assertGt(bookCount, 0, "the armed day's book has entries");
        assertGt(bookTotal, 0, "the armed day's book has weight");

        // The armed day opens and fires its daily request; VRF then stalls.
        simTime += 1 days + 1;
        vm.warp(simTime);
        _advance();
        assertTrue(game.rngLocked(), "the armed day's request is outstanding");

        // Wall clock runs past the armed day. The 12h retry re-fires ON the wall day, so the
        // buffered RNGREUSE clamp (request day < processed day) cannot engage.
        simTime += STALL_DAYS * (1 days + 1);
        vm.warp(simTime);
        _advance();

        uint256 word = _grindWord(armedDay);
        uint256 reqId = mockVRF.lastRequestId();
        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        assertFalse(fulfilled, "a fresh request is outstanding after the retry");
        mockVRF.fulfillRandomWords(reqId, word);

        emit log_named_uint("level at fulfilment", game.level());
        vm.recordLogs();
        // One advance backfills the gap (and defers the transition), the next transitions.
        // Keep the level fed so the transition can complete rather than stalling on a target.
        for (uint256 k = 0; k < 6; k++) {
            _seedNextPrizePool(400 ether);
            _seedFuturePrizePool(300 ether);
            for (uint256 j = 0; j < 40; j++) { if (!_advance()) break; }
            if (game.level() > 100) break;
            simTime += 1 days + 1;
            vm.warp(simTime);
            _buyTickets(buyer, 4000);
            for (uint256 j = 0; j < 40; j++) { _fulfillVrf(false); if (!_advance()) break; }
        }
        emit log_named_uint("level after the stall", game.level());

        (uint16 rewardPercent, bool armedWin) = coinflip.getCoinflipDayResult(armedDay);
        assertTrue(rewardPercent != 0 || armedWin, "the armed day resolved");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("IncineratorResolved(uint24,address,uint256,uint256,uint256)");
        uint256 found;
        uint256 flipAward;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != address(wwxrp) || logs[i].topics[0] != topic) continue;
            assertEq(uint256(logs[i].topics[1]), 100, "bracket 100");
            (flipAward, , ) = abi.decode(logs[i].data, (uint256, uint256, uint256));
            found++;
        }

        emit log_named_uint("armed day", armedDay);
        emit log_named_uint("recorded armed-day word low bit", uint256(game.extsload(bytes32(uint256(keccak256(abi.encode(uint256(armedDay), uint256(10))))))) & 1);
        emit log_named_uint("armed day won (1) or lost (0)", armedWin ? 1 : 0);
        emit log_named_uint("incinerator resolutions", found);
        emit log_named_uint("flip award", flipAward);
        emit log_named_uint("armed book total (whole FLIP)", bookTotal);

        // The invariant the award claims: it is 10% of what the armed day's direct depositors
        // LOST. This path decouples the armed day from the skip gate — the stall resolves the
        // armed day from a backfilled derived word while the transition keeps a later day's —
        // so the armed day WINS here while the BAF still skips. Before the guard in
        // resolveIncinerator the winner was credited 10% of that winning book; now the draw
        // still resolves and logs, with a zero award.
        assertEq(found, 1, "the incinerator resolved");
        assertTrue(armedWin, "fixture: this path really does leave the armed day a winner");
        assertEq(flipAward, 0, "no award may be paid against a book whose flip won");
        assertGt(bookTotal, 0, "fixture: the winning book was non-empty, so a payout was possible");
    }

    /// @notice Control: the identical fixture with no stall. The transition word is the one
    ///         that resolves the armed day, so a paying incinerator always follows a LOSS.
    function testControlNoStallPaysOnlyAgainstALosingArmedDay() public {
        uint256 simTime = block.timestamp;
        for (uint256 d = 0; d < 100; d++) {
            if (game.level() >= 2) break;
            simTime += 1 days + 1;
            vm.warp(simTime);
            _seedNextPrizePool(49.9 ether);
            _seedFuturePrizePool(100 ether);
            _buyTickets(buyer, 4000);
            for (uint256 j = 0; j < 80; j++) { _fulfillVrf(false); if (!_advance()) break; }
        }
        vm.mockCall(ContractAddresses.GNRUS, abi.encodeWithSignature("pickCharity(uint24)"), abi.encode());
        _setLevel(98);

        vm.recordLogs();
        bool entered;
        uint24 armedDay;
        uint24 prevArmed;
        (prevArmed, , ) = coinflip.bafDrawInfo();
        for (uint256 d = 0; d < 600; d++) {
            uint24 currentLevel = game.level();
            if (game.gameOver() || currentLevel > 100) break;
            if (currentLevel == 99 && !entered) {
                _enterAs(alice, 100 ether);
                _enterAs(bob, 300 ether);
                entered = true;
            }
            if (currentLevel >= 99) _selfDeposit(depositor, 1_000 ether);
            simTime += 1 days + 1;
            vm.warp(simTime);
            _seedNextPrizePool(49.9 ether + d * 10 ether);
            _seedFuturePrizePool(100 ether);
            _buyTickets(buyer, 4000);
            for (uint256 j = 0; j < 80; j++) { _fulfillVrf(false); if (!_advance()) break; }
            {
                (uint24 nowArmed, , ) = coinflip.bafDrawInfo();
                if (entered && nowArmed != prevArmed) {
                    (uint16 rp, bool w) = coinflip.getCoinflipDayResult(nowArmed);
                    if (rp == 0 && !w) armedDay = nowArmed;
                }
                prevArmed = nowArmed;
            }
        }
        assertGt(armedDay, 0, "the x00 last-purchase day armed the draw");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("IncineratorResolved(uint24,address,uint256,uint256,uint256)");
        uint256 found;
        for (uint256 i2 = 0; i2 < logs.length; i2++) {
            if (logs[i2].emitter == address(wwxrp) && logs[i2].topics[0] == topic) found++;
        }
        (, bool armedWin) = coinflip.getCoinflipDayResult(armedDay);
        emit log_named_uint("control: armed day", armedDay);
        emit log_named_uint("control: armed day won (1) or lost (0)", armedWin ? 1 : 0);
        emit log_named_uint("control: incinerator resolutions", found);
        if (found != 0) {
            assertFalse(armedWin, "control: an unstalled payout always follows a losing armed day");
            (, uint96 bookTotal, ) = coinflip.bafDrawInfo();
            assertGt(bookTotal, 0, "control: the losing book was non-empty");
        }
    }

    // ==================== Driven-loop internals ====================

    /// @dev Mint wallet FLIP and self-deposit it (direct: burns from the wallet and
    ///      carries BAF draw weight on an armed day).
    function _selfDeposit(address who, uint256 amount) internal {
        vm.prank(address(game));
        coin.mintForGame(who, amount);
        vm.prank(who);
        coinflip.depositCoinflip(address(0), amount);
    }

    function _seedNextPrizePool(uint256 targetNext) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
        uint256 currentNext = packed & ((uint256(1) << 128) - 1);
        if (currentNext >= targetNext) return;
        uint256 newPacked = (packed & ~((uint256(1) << 128) - 1)) | targetNext;
        vm.store(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)), bytes32(newPacked));
    }

    function _seedFuturePrizePool(uint256 targetFuture) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
        uint256 currentFuture = (packed >> 128) & ((uint256(1) << 128) - 1);
        if (currentFuture >= targetFuture) return;
        uint256 newPacked = (packed & ~(((uint256(1) << 128) - 1) << 128)) | (targetFuture << 128);
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
