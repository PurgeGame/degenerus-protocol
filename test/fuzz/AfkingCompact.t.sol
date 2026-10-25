// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {OwnerTargetCall} from "../helpers/OwnerTargetCall.sol";

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";

/// @notice The compact AFKing subscription on the deployed protocol: signup without a purchase,
///         rewards derived from the checkpoint through the last completed subscriber pass,
///         settlement on both sides (the affiliate `claim` drains each sub, whose settlement pays
///         the sub through `creditFlip_g317`), forfeiture on expiry, the protocol-seat pauses, the
///         quest hooks, the EV-allowance bypass and the daily draw (`runSubDraw_g1232`).
contract AfkingCompactTest is DeployProtocol {
    DegenerusGameLens private lens;

    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant CAROL = address(0xCA201);
    address private constant AFFILIATE_OWNER = address(0xAFF1);
    address private constant VAULT_OP = address(0x0FF1CE);

    uint32 private constant VAULT_ID = 1;
    uint32 private constant SDGNRS_ID = 2;

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 1_000_000 ether);
        lens = new DegenerusGameLens();
        vm.deal(address(this), 100 ether);
    }

    // ───────────────────────────── helpers ─────────────────────────────

    function _subscribe(address who, bool tickets, uint8 qty, uint256 deposit) private returns (uint32 id) {
        uint256 seat = _grantSeat(who);
        vm.deal(who, deposit);
        vm.prank(who);
        game.subscribe{value: deposit}(0, tickets, qty, seat);
        id = game.walletIdOf_g3120(who);
    }

    /// @dev Advance one day and run its work through the real crank to the subscription window.
    function _nextDay() private {
        vm.warp(block.timestamp + 1 days);
        _finishSubscriptionWindow();
        _finishReadConsumers();
    }

    function _info(uint32 id) private view returns (DegenerusGameLens.SubFull memory) {
        return lens.subInfoFullById(address(game), id);
    }

    function _flip(uint32 id) private view returns (uint256) {
        return coinflip.coinflipAmountById(id);
    }

    function _claim(uint32 id) private {
        uint32[] memory ids = new uint32[](1);
        ids[0] = id;
        game.claimAfkingFlip(ids);
    }

    function _flags() private view returns (uint8) {
        uint256 word = uint256(vm.load(address(game), bytes32(GameSlots.AFKING_PROTOCOL_FLAGS)));
        return uint8(word >> (8 * GameSlots.AFKING_PROTOCOL_FLAGS_OFFSET));
    }

    function _endpoint() private view returns (uint24) {
        uint256 word = uint256(vm.load(address(game), bytes32(GameSlots.AFKING_ENDPOINT_DAY)));
        return uint24(word >> (8 * GameSlots.AFKING_ENDPOINT_DAY_OFFSET));
    }

    function _price() private view returns (uint256) {
        return PriceLookupLib.priceForLevel(game.level() + 1);
    }

    function _setBalances(uint32 id, uint256 prepaid, uint256 claimable) private {
        vm.store(address(game), GameSlotKeys.balances(id), bytes32((prepaid << 128) | claimable));
    }

    // ───────────────────────────── signup and accrual ─────────────────────────────

    function test_SignupBuysNothingAndCreditsFromTheNextCompletedPass() public {
        uint24 today = game.currentDayView_g542950();
        assertEq(_endpoint(), today, "the deploy day is the first endpoint");
        uint32 id = _subscribe(ALICE, false, 1, 1 ether);

        assertEq(_fixtureAfking(id), 1 ether, "signup buys nothing");
        DegenerusGameLens.SubFull memory s = _info(id);
        assertTrue(s.active);
        assertEq(s.checkpointDay, today, "checkpointed today");
        assertEq(s.runStartDay, today);
        assertEq(s.owedFlip, 0);

        uint256 before = _flip(id);
        _claim(id);
        assertEq(_flip(id), before, "nothing to settle on the signup day");

        uint256 price = _price();
        _nextDay();
        assertEq(_fixtureAfking(id), 1 ether - price, "first purchase the next day");
        s = _info(id);
        assertEq(s.owedFlip, 100, "one box day: the slot-0 reward");
        assertEq(s.owedAffiliateBase, 70);

        uint256 vaultBefore = _flip(VAULT_ID);
        uint256 sdgnrsBefore = _flip(SDGNRS_ID);
        before = _flip(id);
        _claim(id);
        assertEq(_flip(id) - before, 100, "player paid its own reward");
        assertEq(_flip(VAULT_ID) - vaultBefore, 35, "no-referrer base split to the Vault");
        assertEq(_flip(SDGNRS_ID) - sdgnrsBefore, 35, "and to sDGNRS");
        assertEq(_info(id).checkpointDay, _endpoint(), "checkpoint moved to the endpoint");
        assertEq(_info(id).checkpointStreak, s.checkpointStreak + 1, "the day folded into the streak");

        before = _flip(id);
        _claim(id);
        assertEq(_flip(id), before, "a repeat claim credits nothing");
    }

    function test_ClaimBeforeTheDaysPassCreditsNothingForThatDay() public {
        uint32 id = _subscribe(ALICE, true, 3, 2 ether);
        _nextDay();
        // The next day starts; its pass has not run yet, so only the completed day is owed.
        vm.warp(block.timestamp + 1 days);
        assertEq(_info(id).owedFlip, 100 + 300, "one ticket day at quantity 3");
        uint256 before = _flip(id);
        _claim(id);
        assertEq(_flip(id) - before, 400);
        _finishSubscriptionWindow();
        _finishReadConsumers();
        assertEq(_info(id).owedFlip, 400, "the new day is owed only once its pass completed");
        before = _flip(id);
        _claim(id);
        assertEq(_flip(id) - before, 400, "and collected exactly once");
    }

    function test_NewRunNeedsTodaysPassComplete() public {
        vm.warp(block.timestamp + 1 days);
        uint256 seat = _grantSeat(ALICE);
        vm.deal(ALICE, 1 ether);
        vm.prank(ALICE);
        vm.expectRevert(DegenerusGameStorage.RngLocked.selector);
        game.subscribe{value: 1 ether}(0, false, 1, seat);
        _finishSubscriptionWindow();
        vm.prank(ALICE);
        game.subscribe{value: 1 ether}(0, false, 1, seat);
        assertEq(_info(game.walletIdOf_g3120(ALICE)).checkpointDay, game.currentDayView_g542950());
    }

    function test_QuantityAboveEightReverts() public {
        uint256 seat = _grantSeat(ALICE);
        vm.prank(ALICE);
        vm.expectRevert(DegenerusGameStorage.E.selector);
        game.subscribe(0, false, 9, seat);
    }

    // ───────────────────────────── changes, cancel, expiry ─────────────────────────────

    function test_QuantityChangeSettlesAtTheOldRate() public {
        uint32 id = _subscribe(ALICE, true, 2, 3 ether);
        _nextDay();
        uint256 before = _flip(id);
        vm.prank(ALICE);
        game.subscribe(0, true, 5, 0);
        assertEq(_flip(id) - before, 100 + 200, "the old quantity's day settled first");
        assertEq(_info(id).dailyQuantity, 5);
        assertEq(_info(id).owedFlip, 0);
        _nextDay();
        assertEq(_info(id).owedFlip, 100 + 500, "the new quantity earns from the change on");
        assertEq(_info(id).owedAffiliateBase, 350);
    }

    function test_ModeChangeMovesSectionAndKeepsTheRun() public {
        uint32 id = _subscribe(ALICE, false, 2, 3 ether);
        _nextDay();
        DegenerusGameLens.SubFull memory before = _info(id);
        (, uint256 p0) = GameSlotKeys.subLane(address(game), id);
        vm.prank(ALICE);
        game.subscribe(0, true, 2, 0);
        (, uint256 p1) = GameSlotKeys.subLane(address(game), id);
        assertLt(p0, 1000, "was in the box section");
        assertGt(p1, 1000, "now in the ticket section");
        DegenerusGameLens.SubFull memory afterChange = _info(id);
        assertTrue(afterChange.useTickets);
        assertEq(afterChange.runStartDay, before.runStartDay, "the run keeps its start");
        assertEq(afterChange.checkpointStreak, before.checkpointStreak + 1, "settled day folded in");
    }

    function test_CancelSettlesFinalizesAndRemoves() public {
        uint32 id = _subscribe(ALICE, false, 1, 1 ether);
        _nextDay();
        uint256 members = game.subscriberSetLength();
        uint256 before = _flip(id);
        vm.prank(ALICE);
        game.subscribe(0, false, 0, 0);
        assertEq(_flip(id) - before, 100, "cancel settles the player");
        assertEq(game.subscriberSetLength(), members - 1, "and removes the entry");
        assertFalse(_info(id).member);
        (, bool afking) = quests.effectiveBaseStreakAndAfking_g1521(id, _fixtureGameDay());
        assertFalse(afking, "the streak handed back to Quests");

        // A same-day restart burns another seat and credits nothing.
        uint256 seat = _grantSeat(ALICE);
        uint256 seatsBefore = afkingSubToken.totalSupply();
        vm.prank(ALICE);
        game.subscribe(0, false, 1, seat);
        assertEq(afkingSubToken.totalSupply(), seatsBefore - 1, "a restart burns a seat");
        assertEq(_info(id).owedFlip, 0);
    }

    function test_UnfundedExpiryForfeitsUnsettledRewards() public {
        uint256 price = _price();
        uint32 id = _subscribe(ALICE, false, 1, price);
        _nextDay();
        assertEq(_info(id).owedFlip, 100, "the funded day is owed");
        vm.recordLogs();
        _nextDay();
        assertFalse(_info(id).member, "the unfunded member expired");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool expired;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == keccak256("SubscriptionExpired(uint32,uint8)")
                && uint32(uint256(logs[i].topics[1])) == id) {
                assertEq(abi.decode(logs[i].data, (uint8)), 1, "reason: unfunded");
                expired = true;
            }
        }
        assertTrue(expired);
        uint256 before = _flip(id);
        _claim(id);
        assertEq(_flip(id), before, "the unsettled day is forfeited");
    }

    function test_ClaimableFundsBeforePrepaid() public {
        uint32 id = _subscribe(ALICE, false, 1, 1 ether);
        uint256 price = _price();
        // Move the deposit into claimable, keeping the solvency total unchanged.
        _setBalances(id, 0.5 ether, 0.5 ether + 1);
        _nextDay();
        assertEq(_fixtureAfking(id), 0.5 ether, "prepaid untouched");
        assertEq(_fixtureClaimable(id), 0.5 ether + 1 - price, "claimable paid first");
    }

    function test_DailyBoxLeavesTheEvAllowanceUntouched() public {
        uint32 id = _subscribe(ALICE, false, 8, 5 ether);
        _nextDay();
        assertEq(_fixtureAfking(id), 5 ether - 8 * _price(), "the box was bought");
        assertEq(GameSlotKeys.afkingBoxPending(address(game), id), false, "and opened");
        assertEq(
            uint256(vm.load(address(game), GameSlotKeys.byId(id, GameSlots.LOOTBOX_EV_CAP_PACKED))),
            0,
            "no EV allowance read or drawn"
        );
    }

    // ───────────────────────────── protocol seats ─────────────────────────────

    function test_VaultOwnerPauseEarnsNothingAndResumeRestarts() public {
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (
            ContractAddresses.GAME,
            abi.encodeWithSignature("setOperatorApproval(uint32,address,bool)", 0, VAULT_OP, true),
            0
        )), 0), (bytes));
        game.depositAfkingFunding{value: 10 ether}(VAULT_ID);
        // The protocol seats accrue from the bootstrap day, which the day-9 fixture already passed.
        uint256 owedBefore = _info(VAULT_ID).owedFlip;
        _nextDay();
        assertEq(_info(VAULT_ID).owedFlip - owedBefore, 100, "the Vault earns like any box member");

        uint256 before = _flip(VAULT_ID);
        vm.prank(VAULT_OP);
        game.subscribe(VAULT_ID, false, 0, 0);
        assertGe(_flip(VAULT_ID) - before, 100, "the pause settles first");
        assertEq(_flags() & 4, 4, "owner pause set");
        uint256 prepaid = _fixtureAfking(VAULT_ID);
        uint256 streak = _info(VAULT_ID).checkpointStreak;
        uint256 members = game.subscriberSetLength();

        _nextDay();
        _nextDay();
        DegenerusGameLens.SubFull memory s = _info(VAULT_ID);
        assertEq(_fixtureAfking(VAULT_ID), prepaid, "a paused Vault buys nothing");
        assertEq(s.owedFlip, 0, "and earns nothing");
        assertTrue(s.paused && s.member, "it keeps its seat");
        assertEq(game.subscriberSetLength(), members);
        assertEq(s.checkpointStreak, streak, "its streak stands still");

        vm.prank(VAULT_OP);
        game.subscribe(VAULT_ID, false, 1, 0);
        assertEq(_flags() & 4, 0, "resumed");
        assertEq(_info(VAULT_ID).checkpointDay, _endpoint(), "paused days are never credited");
        assertEq(_info(VAULT_ID).runStartDay, _endpoint(), "the draw age restarts");
        _nextDay();
        assertEq(_info(VAULT_ID).owedFlip, 100, "earning again from the resume");
    }

    function test_SdgnrsUnfundedPausesSettlesAndAutoResumes() public {
        game.depositAfkingFunding{value: 10 ether}(SDGNRS_ID);
        // The protocol seats accrue from the bootstrap day, which the day-9 fixture already passed.
        uint256 owedBefore = _info(SDGNRS_ID).owedFlip;
        _nextDay();
        assertEq(_info(SDGNRS_ID).owedFlip - owedBefore, 100, "one day earns one day's FLIP");

        _setBalances(SDGNRS_ID, 0, 1);
        uint256 before = _flip(SDGNRS_ID);
        _nextDay();
        assertEq(_flags() & 16, 16, "unfunded pause");
        assertGe(_flip(SDGNRS_ID) - before, 100, "settled through its last bought day");
        assertEq(_info(SDGNRS_ID).owedFlip, 0);
        _nextDay();
        assertEq(_info(SDGNRS_ID).owedFlip, 0, "nothing earned while paused");

        game.depositAfkingFunding{value: 10 ether}(SDGNRS_ID);
        _nextDay();
        assertEq(_flags() & 16, 0, "back to quantity 1 once it can pay");
        assertEq(_flags() & 2, 2, "and it bought into the cohort");
        assertEq(_info(SDGNRS_ID).owedFlip, 100, "the resume day is its first credited day");
    }

    function test_SdgnrsCannotCancel() public {
        vm.prank(address(sdgnrs));
        vm.expectRevert(DegenerusGameStorage.E.selector);
        game.subscribe(0, false, 0, 0);
    }

    // ───────────────────────────── quest hooks ─────────────────────────────

    function test_QuestHooksMoveTheStreakNotTheCheckpoint() public {
        uint32 id = _subscribe(ALICE, false, 1, 1 ether);
        _nextDay();
        DegenerusGameLens.SubFull memory s = _info(id);
        vm.prank(ContractAddresses.QUESTS);
        game.recordAfkingSecondary_g3316(id, 3);
        DegenerusGameLens.SubFull memory t = _info(id);
        assertEq(t.checkpointStreak, s.checkpointStreak + 3);
        assertEq(t.checkpointDay, s.checkpointDay, "the checkpoint does not move");
        assertEq(t.owedFlip, s.owedFlip, "nothing accrued changes");

        uint256 live = t.checkpointStreak + (t.endpoint - t.checkpointDay);
        vm.prank(ContractAddresses.QUESTS);
        game.floorAfkingStreakBase(id, uint16(live + 9));
        t = _info(id);
        assertEq(t.checkpointStreak + (t.endpoint - t.checkpointDay), live + 9, "floored to exactly the floor");
        vm.prank(ContractAddresses.QUESTS);
        game.floorAfkingStreakBase(id, 1);
        assertEq(_info(id).checkpointStreak, t.checkpointStreak, "a lower floor changes nothing");
    }

    // ───────────────────────────── affiliates and the end of the game ─────────────────────────────

    function test_MixedAffiliateBatchSettlesEachRun() public {
        _giveWalletId(AFFILIATE_OWNER);
        vm.prank(AFFILIATE_OWNER);
        affiliate.createAffiliateCode(bytes32("ALPHA"), 0);
        uint32 a = _subscribe(ALICE, false, 1, 1 ether);
        vm.prank(ALICE);
        affiliate.referPlayer(bytes32("ALPHA"));
        uint32 b = _subscribe(BOB, false, 1, 1 ether);
        uint32 c = _subscribe(CAROL, false, 1, 1 ether);
        vm.prank(CAROL);
        affiliate.referPlayer(bytes32("ALPHA"));
        _nextDay();

        uint32 ownerId = game.walletIdOf_g3120(AFFILIATE_OWNER);
        uint256 ownerBefore = _flip(ownerId);
        uint32[] memory ids = new uint32[](3);
        (ids[0], ids[1], ids[2]) = (a, b, c);
        game.claimAfkingFlip(ids);
        assertGt(_flip(ownerId) - ownerBefore, 0, "both of ALPHA's runs paid its owner");
        assertEq(_info(a).owedFlip + _info(b).owedFlip + _info(c).owedFlip, 0, "every sub settled");
    }

    function test_ClaimsCloseAtTheLivenessTrigger() public {
        uint32 id = _subscribe(ALICE, false, 1, 1 ether);
        _nextDay();
        vm.warp(block.timestamp + 40 days);
        assertTrue(game.livenessTriggered());
        uint32[] memory ids = new uint32[](1);
        ids[0] = id;
        vm.expectRevert(DegenerusGameStorage.GameOver.selector);
        game.claimAfkingFlip(ids);
        uint256 before = _flip(id);
        affiliate.claim(ids);
        assertEq(_flip(id), before, "the affiliate door settles nothing either");
    }

    // ───────────────────────────── daily draw ─────────────────────────────

    function test_DailyDrawPaysRunAgeAndSkipsTheVault() public {
        _subscribe(ALICE, false, 1, 2 ether);
        _subscribe(BOB, true, 1, 2 ether);
        vm.recordLogs();
        for (uint256 d; d < 5; ++d) _nextDay();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("SubDrawWon(uint32,uint24,uint24,uint256)");
        uint256 draws;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics[0] != topic) continue;
            ++draws;
            assertTrue(uint32(uint256(logs[i].topics[1])) != VAULT_ID, "runSubDraw_g1232 never picks the Vault");
            (, uint24 span, uint256 prize) = abi.decode(logs[i].data, (uint24, uint24, uint256));
            assertEq(prize, uint256(span) * 10 > 4000 ? 4000 : uint256(span) * 10);
            assertGt(span, 0);
        }
        assertGt(draws, 0, "the draw ran");
    }
}
