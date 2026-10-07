// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {RedemptionFixture} from "./helpers/RedemptionFixture.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {Vm} from "forge-std/Vm.sol";

/// @dev Both endings reach resolveTerminalRedemptions through the real Game ending worker.
contract RedemptionForwardBatchesTest is RedemptionFixture {
    // ---------------------------------------------------------------------
    // Burn at burn time
    // ---------------------------------------------------------------------

    /// @dev (a) Supply drops at the burn; the escrow keeps the tokens in the holder base, so
    ///      the live per-token price does not move; the close emits no Transfer.
    function test_BurnLeavesSupplyAtOnceAndCloseEmitsNoTransfer() public {
        uint256 amount = sdgnrs.totalSupply() / 1000;
        uint256 supply = sdgnrs.totalSupply();
        uint256 voting = sdgnrs.votingSupply();
        (uint256 priceBefore,) = sdgnrs.previewBurnValue(1e24);

        vm.expectEmit(true, true, false, true, address(sdgnrs));
        emit sDGNRS.Transfer(alice, address(0), amount);
        _burn(alice, amount);

        assertEq(sdgnrs.totalSupply(), supply - amount, "supply drops at the burn");
        assertEq(sdgnrs.votingSupply(), voting - amount, "burned tokens stop voting at the burn");
        assertEq(_escrow(), amount, "the open batch counts the burned tokens");
        (uint256 priceAfter,) = sdgnrs.previewBurnValue(1e24);
        assertEq(priceAfter, priceBefore, "the holder base still counts the escrow");

        vm.recordLogs();
        _closeAsGame();
        assertEq(_sdgnrsTransfers(vm.getRecordedLogs()), 0, "the close emits no Transfer");
        assertEq(sdgnrs.totalSupply(), supply - amount, "the close leaves supply alone");
        assertEq(_escrow(), 0, "the close clears the batch's escrow share");
    }

    // ---------------------------------------------------------------------
    // One price per batch
    // ---------------------------------------------------------------------

    function _orderRun(bool aliceFirst, uint256 amount)
        internal returns (uint256 aliceDirect, uint256 bobDirect, uint256 aliceBox, uint256 bobBox, uint256 ethBase)
    {
        (uint32 id,) = _state();
        _burn(aliceFirst ? alice : bob, amount);
        // Backing that moves between the burns reaches both burners pro rata at the close.
        vm.deal(address(sdgnrs), address(sdgnrs).balance + 37 ether);
        _burn(aliceFirst ? bob : alice, amount);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0, "a burn reserves nothing; the close does");
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.recordLogs();
        _complete(0xB47C4);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        (found, aliceDirect, aliceBox) = _claimedLegs(logs, alice, id);
        assertTrue(found, "alice settled");
        (found, bobDirect, bobBox) = _claimedLegs(logs, bob, id);
        assertTrue(found, "bob settled");
        (, ethBase,,,) = _batch(id);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0, "a settled batch releases its whole reserve");
        assertFalse(sdgnrs.redemptionSettlementPending());
    }

    function test_BurnersInOneBatchGetOneClosePriceRegardlessOfOrder() public {
        uint256 amount = sdgnrs.totalSupply() / 1000;
        uint256 snap = vm.snapshotState();
        (uint256 aDirect, uint256 bDirect, uint256 aBox, uint256 bBox, uint256 baseA) = _orderRun(true, amount);
        assertTrue(vm.revertToState(snap));
        (uint256 aDirect2, uint256 bDirect2, uint256 aBox2, uint256 bBox2, uint256 baseB) = _orderRun(false, amount);

        assertGt(baseA, 0);
        assertEq(baseA, baseB, "the close price ignores burn order");
        assertEq(aDirect, bDirect, "equal tokens, equal direct leg in one batch");
        assertEq(aBox, bBox, "equal tokens, equal lootbox leg in one batch");
        assertEq(aDirect, aDirect2, "alice's leg does not depend on her position");
        assertEq(bDirect, bDirect2, "bob's leg does not depend on his position");
        assertEq(aBox, aBox2);
        assertEq(bBox, bBox2);
    }

    /// @dev (b) The close prices the whole batch over the holder base (supply plus the escrow):
    ///      the batch base is the batch's share of the live money, and each claim's base is pro
    ///      rata by tokens, so per-token bases match across burners of different sizes.
    function test_ClosePricesOverTheHolderBaseWithEqualPerTokenBases() public {
        uint256 unit = sdgnrs.totalSupply() / 1000;
        (uint32 id,) = _state();
        _burn(alice, unit);
        vm.deal(address(sdgnrs), address(sdgnrs).balance + 11 ether);
        _burn(bob, 2 * unit);

        uint256 holderBase = sdgnrs.totalSupply() + _escrow();
        uint256 expected = ((_money() * 3 * unit) / holderBase / 1e9) * 1e9;
        _closeAsGame();
        (uint256 tokens, uint256 ethBase,,,) = _batch(id);
        assertEq(tokens, 3 * unit);
        assertEq(ethBase, expected, "batch base is its share of the money over the holder base");
        uint256 aliceBase = ethBase * unit / tokens;
        uint256 bobBase = ethBase * (2 * unit) / tokens;
        assertApproxEqAbs(bobBase, 2 * aliceBase, 1, "equal per-token base for every burner");
    }

    // ---------------------------------------------------------------------
    // Daily lock and mid-day flight
    // ---------------------------------------------------------------------

    /// @dev A burn during the daily lock (word possibly public) is accepted, joins the next batch,
    ///      and leaves the century refill computed from that word unchanged: the recycle reads the
    ///      holder base, which a burn does not move.
    function test_InLockBurnJoinsNextBatchAndLeavesCenturyRefillUnchanged() public {
        uint256 amount = sdgnrs.totalSupply() / 1000;
        (uint32 first,) = _state();
        _burn(alice, amount);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        assertTrue(_runUntilNewRequestOrIdle(), "daily request sent");
        assertTrue(game.rngLocked());
        uint256 word = uint256(keccak256("x00 transition word"));

        uint256 snap = vm.snapshotState();
        uint256 supply = sdgnrs.totalSupply();
        vm.prank(address(game));
        sdgnrs.recycleCentury(100, word);
        uint256 mintedWithout = sdgnrs.totalSupply() - supply;
        uint256 checkpointWithout = sdgnrs.centurySupplyCheckpoint();
        assertTrue(vm.revertToState(snap));

        _burn(bob, amount); // inside the lock: accepted
        assertEq(_claimTokens(bob, first + 1), amount, "the in-lock burn joins the next batch");
        supply = sdgnrs.totalSupply();
        vm.prank(address(game));
        sdgnrs.recycleCentury(100, word);
        assertGt(mintedWithout, 0, "harness: the closed batch counts as burned");
        assertEq(sdgnrs.totalSupply() - supply, mintedWithout, "the in-lock burn does not move the refill");
        assertEq(sdgnrs.centurySupplyCheckpoint(), checkpointWithout, "nor the next checkpoint");
    }

    function test_LockedAndInFlightBurnsJoinTheNextBatchAndMiddayWordSettles() public {
        uint256 amount = sdgnrs.totalSupply() / 1000;
        (uint32 first,) = _state();
        _burn(alice, amount);

        // The daily request closes the open batch and opens the next one.
        vm.warp(vm.getBlockTimestamp() + 1 days);
        assertTrue(_runUntilNewRequestOrIdle(), "daily request sent");
        assertTrue(game.rngLocked(), "the daily request holds the lock");
        (uint32 open, uint32 settling) = _state();
        assertEq(settling, first, "the request closed alice's batch");
        assertEq(open, first + 1);
        (uint256 closedTokens,,,,) = _batch(first);
        assertEq(closedTokens, amount);

        // A burn during the daily lock is admitted and joins the next batch.
        _burn(bob, amount);
        assertEq(_claimTokens(bob, first + 1), amount, "locked burn joins the open batch");
        assertEq(_claimTokens(bob, first), 0);

        uint256 dailyWord = uint256(keccak256("daily word"));
        assertTrue(_fulfillPending(dailyWord));
        bool middayAlready = _runUntilNewRequestOrIdle();
        (,,, uint16 roll1, uint16 flip1) = _batch(first);
        assertEq(roll1, _roll(dailyWord), "first batch rolled from the daily word that answered its close");
        assertEq(flip1, _synthReward(dailyWord, first));
        assertEq(_claimTokens(alice, first), 0, "alice settled");

        // The next fresh request is a mid-day one: it closes bob's batch.
        if (!middayAlready) _sendMiddayRequest();
        assertFalse(game.rngLocked(), "a mid-day request takes no daily lock");
        (open, settling) = _state();
        assertEq(settling, first + 1, "the mid-day request closed bob's batch");
        assertEq(open, first + 2);

        // A burn while the mid-day word is in flight joins the batch after it.
        uint256 carolAmount = amount / 3;
        _burn(carol, carolAmount);
        assertEq(_claimTokens(carol, first + 2), carolAmount, "in-flight burn joins the open batch");
        assertEq(_claimTokens(carol, first + 1), 0);

        uint256 bobCredit = game.claimableWinningsOf(bob);
        uint256 middayWord = uint256(keccak256("midday word"));
        assertTrue(_fulfillPending(middayWord));
        vm.recordLogs();
        // Stop once bob's batch is settled: the same call may already send the next request,
        // which closes carol's batch (left unanswered here).
        for (uint256 i; i < 300; ++i) {
            (, settling) = _state();
            if (settling != first + 1) break;
            require(game.nextMinerAction() != 2, "harness: only the mid-day word is answered");
            game.mineFlip();
        }
        (, settling) = _state();
        assertTrue(settling != first + 1, "bob's batch settled on the mid-day session");
        (, uint256 base2,, uint16 roll2, uint16 flip2) = _batch(first + 1);
        assertEq(roll2, _roll(middayWord), "settled on the word that answered its closing request");
        assertEq(flip2, _synthReward(middayWord, first + 1));
        (bool found, uint256 direct,) = _claimedLegs(vm.getRecordedLogs(), bob, first + 1);
        assertTrue(found, "bob settled");
        assertEq(direct, (base2 * roll2 / 100) / 2, "a sole member takes the whole batch base");
        // The lootbox leg may add its own ETH prizes on top.
        assertGe(game.claimableWinningsOf(bob) - bobCredit, direct, "the direct half lands in game claimable");
        assertEq(_claimTokens(bob, first + 1), 0);
        assertEq(_claimTokens(carol, first + 2), carolAmount, "carol waits for her own batch");
    }

    // ---------------------------------------------------------------------
    // The close is total
    // ---------------------------------------------------------------------

    function testFuzz_CloseNeverRevertsAcrossBackingMix(
        uint96 ethHeld, uint96 stethHeld, uint256 gameClaimable, uint256 amountSeed
    ) public {
        ethHeld = uint96(bound(ethHeld, 0, 1_000_000 ether));
        stethHeld = uint96(bound(stethHeld, 0, 1_000_000 ether));
        gameClaimable = bound(gameClaimable, 0, 1_000_000 ether);
        vm.deal(address(sdgnrs), ethHeld);
        _giveSteth(stethHeld);

        // Burn as much as the per-wallet day cap and the holding allow (at least the minimum).
        uint256 supply = sdgnrs.totalSupply();
        (uint256 live,) = sdgnrs.previewBurnValue(supply);
        uint256 maxAmount = sdgnrs.balanceOf(alice);
        if (live > 160 ether) {
            uint256 capped = 160 ether * supply / live;
            if (capped < maxAmount) maxAmount = capped;
        }
        vm.assume(maxAmount >= 1e18);
        uint256 amount = bound(amountSeed, 1e18, maxAmount);
        _burn(alice, amount);
        assertEq(sdgnrs.totalSupply(), supply - amount, "the burn leaves supply at once");

        (uint32 id,) = _state();
        uint256 custody = address(sdgnrs).balance + mockStETH.balanceOf(address(sdgnrs));
        vm.recordLogs();
        vm.prank(address(game));
        uint256 pull = sdgnrs.closeRedemptionBatch(gameClaimable);
        assertEq(_sdgnrsTransfers(vm.getRecordedLogs()), 0, "the close emits no Transfer");

        (uint32 open,) = _state();
        assertEq(open, id + 1, "the batch closed");
        (, uint256 ethBase,,,) = _batch(id);
        uint256 reserve = sdgnrs.pendingRedemptionEthValue();
        assertEq(reserve, ethBase * 175 / 100, "the close reserves the batch MAX");
        assertLe(pull, gameClaimable > 1 ? gameClaimable - 1 : 0, "pull never exceeds the claimable");
        assertGe(custody + pull, reserve, "custody plus the pull backs the reserve");
        assertEq(sdgnrs.totalSupply(), supply - amount, "the close leaves supply alone");
        assertEq(_escrow(), 0);
    }

    function test_StethHeavyBackingClosesAndSettlesEndToEnd() public {
        // Nearly all of sDGNRS custody as stETH.
        vm.deal(address(sdgnrs), 1 ether);
        _giveSteth(9_999 ether);
        uint256 amount = sdgnrs.totalSupply() / 1000;
        (uint32 id,) = _state();
        _burn(alice, amount);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.recordLogs();
        _complete(0x57E7);
        (, uint256 ethBase,, uint16 roll,) = _batch(id);
        assertGt(ethBase, 0);
        assertGt(roll, 0, "resolved");
        (bool found, uint256 direct,) = _claimedLegs(vm.getRecordedLogs(), alice, id);
        assertTrue(found, "settled from stETH-heavy custody");
        assertEq(direct, (ethBase * roll / 100) / 2);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }

    function _giveSteth(uint256 amount) internal {
        if (amount == 0) return;
        address minter = makeAddr("stethMinter");
        vm.deal(minter, amount);
        vm.startPrank(minter);
        mockStETH.submit{value: amount}(address(0));
        mockStETH.transfer(address(sdgnrs), amount);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------------
    // Game over
    // ---------------------------------------------------------------------

    /// @dev (c) A claim in the batch still open at game over unwinds at exactly what a regular
    ///      holder's game-over burn of the same token count pays, and the escrow does not move a
    ///      regular holder's game-over price.
    function test_OpenBatchUnwindsAtTheGameOverBurnPrice() public {
        uint256 amount = sdgnrs.totalSupply() / 1000;

        // Counterfactual: alice never burned live.
        uint256 snap = vm.snapshotState();
        _latchGameOver();
        uint256 before = _received(bob);
        vm.prank(bob);
        sdgnrs.burn(amount);
        uint256 bobNoEscrow = _received(bob) - before;
        assertTrue(vm.revertToState(snap));

        // Alice's live burn sits in the open batch when the game ends.
        (uint32 id,) = _state();
        _burn(alice, amount);
        _latchGameOver();
        uint256 snap2 = vm.snapshotState();

        before = _received(bob);
        vm.prank(bob);
        sdgnrs.burn(amount);
        uint256 bobWithEscrow = _received(bob) - before;
        assertEq(bobWithEscrow, bobNoEscrow, "the escrow leaves a regular holder's price unchanged");
        assertTrue(vm.revertToState(snap2));

        (uint256 preview,) = sdgnrs.previewBurnValue(amount);
        before = _received(alice);
        vm.prank(alice);
        sdgnrs.claimRedemption(0, id);
        assertEq(_received(alice) - before, bobWithEscrow, "the open claim unwinds at the game-over burn price");
        assertEq(preview, bobWithEscrow, "the preview shows the game-over price");
        assertEq(_claimTokens(alice, id), 0);
        assertEq(_escrow(), 0, "the unwind leaves the escrow");
        vm.expectRevert(sDGNRS.NoClaim.selector);
        vm.prank(alice);
        sdgnrs.claimRedemption(0, id);
    }

    /// @dev (d) Liveness fires while a closed batch waits for settlement: its pre-freeze word is
    ///      never consumed, the ending resolves it at a flat 100 (never from the terminal word),
    ///      and the post-game-over claim pays it 100% direct. The open batch never closes and
    ///      unwinds as in (c).
    function test_TerminalWordResolvesTheSettlingBatchAndOpenBatchUnwinds() public {
        uint256 amount = sdgnrs.totalSupply() / 1000;
        (uint32 first,) = _state();
        _burn(alice, amount);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        assertTrue(_runUntilNewRequestOrIdle(), "daily request sent");
        (, uint32 settling) = _state();
        assertEq(settling, first);
        _burn(bob, amount); // joins the open batch during the lock
        assertTrue(_fulfillPending(uint256(keccak256("pre-freeze word"))));

        // The deadman fires before anyone settles the delivered word; VRF stays alive.
        vm.warp(vm.getBlockTimestamp() + 31 days);
        assertTrue(game.livenessTriggered());
        uint256 terminalWord = uint256(keccak256("terminal word"));
        _endGame(terminalWord);

        (, uint256 ethBase,, uint16 roll, uint16 flip) = _batch(first);
        assertEq(roll, 100, "the ending resolves the settling batch at a flat 100");
        assertEq(flip, 0, "FLIP is forfeited at the ending");
        (uint32 open,) = _state();
        assertEq(open, first + 1, "the ending closed nothing");
        assertEq(_claimTokens(bob, first + 1), amount);

        uint256 before = _received(alice);
        vm.prank(alice);
        sdgnrs.claimRedemption(0, first);
        assertEq(_received(alice) - before, ethBase, "100% direct at roll 100");

        (uint256 preview,) = sdgnrs.previewBurnValue(amount);
        before = _received(bob);
        vm.prank(bob);
        sdgnrs.claimRedemption(0, first + 1);
        assertEq(_received(bob) - before, preview, "the open batch unwinds at the game-over price");
    }

    /// @dev (e) The deterministic ending: a closed batch whose word never arrives resolves at 100.
    function test_DeadEndingResolvesTheSettlingBatchAtExpectedValue() public {
        uint256 amount = sdgnrs.totalSupply() / 1000;
        (uint32 first,) = _state();
        _burn(alice, amount);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        assertTrue(_runUntilNewRequestOrIdle(), "daily request sent");
        (, uint32 settling) = _state();
        assertEq(settling, first);
        fulfilled = mockVRF.lastRequestId(); // never answered

        vm.warp(vm.getBlockTimestamp() + 14 days);
        assertTrue(game.livenessTriggered(), "unanswered for the dead window");
        for (uint256 i; i < 200 && !game.gameOver(); ++i) game.mineFlip();
        assertTrue(game.gameOver(), "deterministic ending reached game over");

        (, uint256 ethBase,, uint16 roll, uint16 flip) = _batch(first);
        assertEq(roll, 100, "the expected roll");
        assertEq(flip, 0);
        uint256 before = _received(alice);
        vm.prank(alice);
        sdgnrs.claimRedemption(0, first);
        assertEq(_received(alice) - before, ethBase, "100% direct at roll 100");
    }

    // ---------------------------------------------------------------------
    // Redemption lootbox leg: one box order
    // ---------------------------------------------------------------------

    bytes32 internal constant OPENED_TOPIC =
        keccak256("LootBoxOpened(address,uint48,uint256,uint24,uint32,uint256,bool)");

    /// @dev Resolve one lootbox leg as sDGNRS would; return gas, opened-box events and the
    ///      expected order shape.
    function _resolveLeg(uint256 amount, uint32 batchId)
        internal
        returns (uint256 gasUsed, uint256 opened, uint256 boxes, uint256 boxSize)
    {
        boxes = (amount - 1) / 1 ether + 1;
        if (boxes > 20) boxes = 20;
        boxSize = (amount / boxes / 1e12) * 1e12;
        vm.deal(address(sdgnrs), address(sdgnrs).balance + amount);
        uint256 sdgnrsBefore = address(sdgnrs).balance;
        uint256 gameBefore = address(game).balance;
        uint256 futureBefore = game.futurePrizePoolView();
        uint32 aliceId = game.walletIdOf(alice);
        vm.recordLogs();
        vm.prank(address(sdgnrs));
        uint256 g0 = gasleft();
        game.resolveRedemptionLootbox{value: amount}(
            alice, aliceId, amount, uint256(keccak256(abi.encode("leg", amount))), 300, batchId
        );
        gasUsed = g0 - gasleft();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 tagged = (uint256(1) << 47) | batchId;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == OPENED_TOPIC
                && uint256(logs[i].topics[2]) == tagged) ++opened;
        }
        assertEq(sdgnrsBefore - address(sdgnrs).balance, amount, "the whole leg leaves sDGNRS");
        assertEq(address(game).balance - gameBefore, amount, "and lands in the Game");
        // Box prizes are drawn against the pool after the credit, so the pool moved by at most
        // the amount; with no prize paid out of it the credit is exactly the amount.
        assertLe(game.futurePrizePoolView(), futureBefore + amount, "pool credit is the amount");
        assertLt(amount - boxes * boxSize, boxes * 1e12 + 1, "only sub-1e12 rounding stays in the pool");
    }

    function test_RedemptionLootboxLegResolvesAsOneBoundedOrder() public {
        uint256[5] memory legs = [uint256(0.5 ether), 7 ether, 20 ether, 140 ether, 400 ether];
        uint256[5] memory expectBoxes = [uint256(1), 7, 20, 20, 20];
        for (uint256 i; i < legs.length; ++i) {
            uint256 snap = vm.snapshotState();
            (uint256 gasUsed, uint256 opened, uint256 boxes, uint256 boxSize) = _resolveLeg(legs[i], uint32(i + 1));
            assertEq(boxes, expectBoxes[i], "box count rule");
            // Not every box outcome emits LootBoxOpened (a WWXRP spin outcome emits BoxSpin), so
            // the open events only bound the count from above (one recirculated box per ETH spin).
            assertLe(opened, 2 * boxes);
            uint256 bound = 1_300_000 + boxes * 27_500;
            emit log_named_uint(string.concat("redemption_leg_wei_", vm.toString(legs[i])), legs[i]);
            emit log_named_uint("  boxes", boxes);
            emit log_named_uint("  box_size_wei", boxSize);
            emit log_named_uint("  opened_events", opened);
            emit log_named_uint("  gas_used", gasUsed);
            emit log_named_uint("  admission_bound", bound);
            assertLe(gasUsed, bound, "fits the order admission bound");
            assertTrue(vm.revertToState(snap));
        }
    }

    /// @dev The live roll spans exactly [21, 175] (155 values, mean 98): both ends are reached
    ///      and the range wraps back to 21.
    function test_LiveRollSpansExactly21To175() public {
        _burn(alice, sdgnrs.totalSupply() / 1000);
        (uint32 id,) = _state();
        _closeAsGame();
        vm.mockCall(address(game), abi.encodeWithSignature("rngConsumerStage()"), abi.encode(uint8(1)));
        uint256[4] memory steps = [uint256(0), 154, 155, 77];
        uint16[4] memory expected = [uint16(21), 175, 21, 98];
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            uint256 snap = vm.snapshotState();
            vm.prank(address(game));
            sdgnrs.runRedemptionWork((steps[i] << 8) | 2, 200_000);
            (,,, uint16 roll,) = _batch(id);
            assertEq(roll, expected[i], "roll at the range edges");
            assertTrue(vm.revertToState(snap));
        }
        for (uint256 v; v < 155; ++v) sum += _roll(v << 8);
        assertEq(sum, 98 * 155, "mean roll is exactly 98");
    }

    // ---------------------------------------------------------------------
    // Synthetic flip
    // ---------------------------------------------------------------------

    /// @dev The batch's synthetic flip is tagged: over many words its win bit both agrees and
    ///      disagrees with the word's raw bit 0 (the daily coinflip's win bit on a daily word).
    function test_SyntheticFlipBitIsIndependentOfDailyCoinflipBit() public {
        _burn(alice, sdgnrs.totalSupply() / 1000);
        (uint32 id,) = _state();
        _closeAsGame();
        vm.mockCall(address(game), abi.encodeWithSignature("rngConsumerStage()"), abi.encode(uint8(1)));

        uint256 agree;
        uint256 differ;
        for (uint256 i; i < 96; ++i) {
            uint256 word = uint256(keccak256(abi.encode("synthetic flip", i))) | 2;
            uint256 snap = vm.snapshotState();
            // Enough for the resolution, not for a claim: the batch resolves and stops.
            vm.prank(address(game));
            sdgnrs.runRedemptionWork(word, 200_000);
            (,,, uint16 roll, uint16 reward) = _batch(id);
            assertEq(roll, _roll(word));
            assertTrue(roll >= 21 && roll <= 175, "live roll in [21, 175]");
            assertEq(reward, _synthReward(word, id));
            if (reward != 0) {
                assertTrue(reward == 50 || reward == 150 || (reward >= 78 && reward <= 115), "coinflip odds, no bonus");
            }
            if ((reward != 0) == ((word & 1) == 1)) ++agree;
            else ++differ;
            assertTrue(vm.revertToState(snap));
        }
        emit log_named_uint("synthetic_flip_agrees_with_bit0", agree);
        emit log_named_uint("synthetic_flip_differs_from_bit0", differ);
        assertGt(agree, 0);
        assertGt(differ, 0, "the synthetic flip is not the word's bit 0");
    }
}
