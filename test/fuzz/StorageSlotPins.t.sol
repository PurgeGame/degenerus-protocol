// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";
import {WWXRP} from "../../contracts/WWXRP.sol";
import {WalletTableLib} from "../../contracts/libraries/WalletTableLib.sol";
import {CrapsPreferenceLib} from "../../contracts/libraries/CrapsPreferenceLib.sol";
import {GameSlots, CrapsSlots} from "../helpers/GameSlots.sol";

/// @dev Reads `.slot` / `.offset` straight off the audited Game storage declarations.
contract GameSlotHarness is DegenerusGameStorage {
    function s_purchaseStartDay() external pure returns (uint256 s, uint256 o) { assembly { s := purchaseStartDay.slot o := purchaseStartDay.offset } }
    function s_dailyIdx() external pure returns (uint256 s, uint256 o) { assembly { s := dailyIdx.slot o := dailyIdx.offset } }
    function s_rngRequestTime() external pure returns (uint256 s, uint256 o) { assembly { s := rngRequestTime.slot o := rngRequestTime.offset } }
    function s_level() external pure returns (uint256 s, uint256 o) { assembly { s := level.slot o := level.offset } }
    function s_jackpotPhaseFlag() external pure returns (uint256 s, uint256 o) { assembly { s := jackpotPhaseFlag.slot o := jackpotPhaseFlag.offset } }
    function s_jackpotCounter() external pure returns (uint256 s, uint256 o) { assembly { s := jackpotCounter.slot o := jackpotCounter.offset } }
    function s_lastPurchaseDay() external pure returns (uint256 s, uint256 o) { assembly { s := lastPurchaseDay.slot o := lastPurchaseDay.offset } }
    function s_decimatorFlags() external pure returns (uint256 s, uint256 o) { assembly { s := decimatorFlags.slot o := decimatorFlags.offset } }
    function s_rngLockedFlag() external pure returns (uint256 s, uint256 o) { assembly { s := rngLockedFlag.slot o := rngLockedFlag.offset } }
    function s_phaseTransitionActive() external pure returns (uint256 s, uint256 o) { assembly { s := phaseTransitionActive.slot o := phaseTransitionActive.offset } }
    function s_gameOver() external pure returns (uint256 s, uint256 o) { assembly { s := gameOver.slot o := gameOver.offset } }
    function s_dailyJackpotCoinTicketsPending() external pure returns (uint256 s, uint256 o) { assembly { s := dailyJackpotCoinTicketsPending.slot o := dailyJackpotCoinTicketsPending.offset } }
    function s_jackpotFlags() external pure returns (uint256 s, uint256 o) { assembly { s := jackpotFlags.slot o := jackpotFlags.offset } }
    function s_ticketsFullyProcessed() external pure returns (uint256 s, uint256 o) { assembly { s := ticketsFullyProcessed.slot o := ticketsFullyProcessed.offset } }
    function s_ticketWriteSlot() external pure returns (uint256 s, uint256 o) { assembly { s := ticketWriteSlot.slot o := ticketWriteSlot.offset } }
    function s_prizePoolFrozen() external pure returns (uint256 s, uint256 o) { assembly { s := prizePoolFrozen.slot o := prizePoolFrozen.offset } }
    function s_presaleOver() external pure returns (uint256 s, uint256 o) { assembly { s := presaleOver.slot o := presaleOver.offset } }
    function s_subsFullyProcessed() external pure returns (uint256 s, uint256 o) { assembly { s := subsFullyProcessed.slot o := subsFullyProcessed.offset } }
    function s_humanReadComplete() external pure returns (uint256 s, uint256 o) { assembly { s := humanReadComplete.slot o := humanReadComplete.offset } }
    function s_rngFlagsAndNudges() external pure returns (uint256 s, uint256 o) { assembly { s := rngFlagsAndNudges.slot o := rngFlagsAndNudges.offset } }
    function s_currentPrizePool() external pure returns (uint256 s, uint256 o) { assembly { s := currentPrizePool.slot o := currentPrizePool.offset } }
    function s_claimablePool() external pure returns (uint256 s, uint256 o) { assembly { s := claimablePool.slot o := claimablePool.offset } }
    function s_prizePoolsPacked() external pure returns (uint256 s, uint256 o) { assembly { s := prizePoolsPacked.slot o := prizePoolsPacked.offset } }
    function s_rngWordCurrent() external pure returns (uint256 s, uint256 o) { assembly { s := rngWordCurrent.slot o := rngWordCurrent.offset } }
    function s_vrfRequestId() external pure returns (uint256 s, uint256 o) { assembly { s := vrfRequestId.slot o := vrfRequestId.offset } }
    function s_rngRequestDay() external pure returns (uint256 s, uint256 o) { assembly { s := rngRequestDay.slot o := rngRequestDay.offset } }
    function s_rngGapApplied() external pure returns (uint256 s, uint256 o) { assembly { s := rngGapApplied.slot o := rngGapApplied.offset } }
    function s_lastVrfProcessedTimestamp() external pure returns (uint256 s, uint256 o) { assembly { s := lastVrfProcessedTimestamp.slot o := lastVrfProcessedTimestamp.offset } }
    function s_ticketBufferLevels() external pure returns (uint256 s, uint256 o) { assembly { s := ticketBufferLevels.slot o := ticketBufferLevels.offset } }
    function s_dailyTicketBudgetsPacked() external pure returns (uint256 s, uint256 o) { assembly { s := dailyTicketBudgetsPacked.slot o := dailyTicketBudgetsPacked.offset } }
    function s_balancesPacked() external pure returns (uint256 s, uint256 o) { assembly { s := balancesPacked.slot o := balancesPacked.offset } }
    function s_lvlTraitEntry() external pure returns (uint256 s, uint256 o) { assembly { s := lvlTraitEntry.slot o := lvlTraitEntry.offset } }
    function s_afkingFundingApprovals() external pure returns (uint256 s, uint256 o) { assembly { s := afkingFundingApprovals.slot o := afkingFundingApprovals.offset } }
    function s_walletIds() external pure returns (uint256 s) { assembly { s := walletIds.slot } }
    function s_mintPacked() external pure returns (uint256 s, uint256 o) { assembly { s := mintPacked_.slot o := mintPacked_.offset } }
    function s_rngWordByDay() external pure returns (uint256 s, uint256 o) { assembly { s := rngWordByDay.slot o := rngWordByDay.offset } }
    function s_prizePoolPendingPacked() external pure returns (uint256 s, uint256 o) { assembly { s := prizePoolPendingPacked.slot o := prizePoolPendingPacked.offset } }
    function s_ticketQueue() external pure returns (uint256 s, uint256 o) { assembly { s := ticketQueue.slot o := ticketQueue.offset } }
    function s_wallets() external pure returns (uint256 s, uint256 o) { assembly { s := wallets.slot o := wallets.offset } }
    function s_ticketCursor() external pure returns (uint256 s, uint256 o) { assembly { s := ticketCursor.slot o := ticketCursor.offset } }
    function s_ticketLevel() external pure returns (uint256 s, uint256 o) { assembly { s := ticketLevel.slot o := ticketLevel.offset } }
    function s_snapShift() external pure returns (uint256 s, uint256 o) { assembly { s := snapShift.slot o := snapShift.offset } }
    function s_snapLevel() external pure returns (uint256 s, uint256 o) { assembly { s := snapLevel.slot o := snapLevel.offset } }
    function s_snapPendingShift() external pure returns (uint256 s, uint256 o) { assembly { s := snapPendingShift.slot o := snapPendingShift.offset } }
    function s_ticketRound() external pure returns (uint256 s, uint256 o) { assembly { s := ticketRound.slot o := ticketRound.offset } }
    function s_ticketSoloOffset() external pure returns (uint256 s, uint256 o) { assembly { s := ticketSoloOffset.slot o := ticketSoloOffset.offset } }
    function s_degeneretteCursor() external pure returns (uint256 s, uint256 o) { assembly { s := degeneretteCursor.slot o := degeneretteCursor.offset } }
    function s_degeneretteReadCount() external pure returns (uint256 s, uint256 o) { assembly { s := degeneretteReadCount.slot o := degeneretteReadCount.offset } }
    function s_presaleBoxEthSold() external pure returns (uint256 s, uint256 o) { assembly { s := presaleBoxEthSold.slot o := presaleBoxEthSold.offset } }
    function s_presaleBoxCredit() external pure returns (uint256 s, uint256 o) { assembly { s := presaleBoxCredit.slot o := presaleBoxCredit.offset } }
    function s_gameOverStatePacked() external pure returns (uint256 s, uint256 o) { assembly { s := gameOverStatePacked.slot o := gameOverStatePacked.offset } }
    function s_degeneretteQueue() external pure returns (uint256 s, uint256 o) { assembly { s := degeneretteQueue.slot o := degeneretteQueue.offset } }
    function s_operatorApprovals() external pure returns (uint256 s, uint256 o) { assembly { s := operatorApprovals.slot o := operatorApprovals.offset } }
    function s_levelPrizePool() external pure returns (uint256 s, uint256 o) { assembly { s := levelPrizePool.slot o := levelPrizePool.offset } }
    function s_playerClaimWord() external pure returns (uint256 s, uint256 o) { assembly { s := playerClaimWord.slot o := playerClaimWord.offset } }
    function s_levelDgnrsPacked() external pure returns (uint256 s, uint256 o) { assembly { s := levelDgnrsPacked.slot o := levelDgnrsPacked.offset } }
    function s_deityPassPricePaid() external pure returns (uint256 s, uint256 o) { assembly { s := deityPassPricePaid.slot o := deityPassPricePaid.offset } }
    function s_deityPassIds() external pure returns (uint256 s, uint256 o) { assembly { s := deityPassIds.slot o := deityPassIds.offset } }
    function s_deityBySymbol() external pure returns (uint256 s, uint256 o) { assembly { s := deityBySymbol.slot o := deityBySymbol.offset } }
    function s_presaleBoxDgnrsPoolStart() external pure returns (uint256 s, uint256 o) { assembly { s := presaleBoxDgnrsPoolStart.slot o := presaleBoxDgnrsPoolStart.offset } }
    function s_vrfCoordinator() external pure returns (uint256 s, uint256 o) { assembly { s := vrfCoordinator.slot o := vrfCoordinator.offset } }
    function s_vrfKeyHash() external pure returns (uint256 s, uint256 o) { assembly { s := vrfKeyHash.slot o := vrfKeyHash.offset } }
    function s_vrfSubscriptionId() external pure returns (uint256 s, uint256 o) { assembly { s := vrfSubscriptionId.slot o := vrfSubscriptionId.offset } }
    function s_lootboxRngPacked() external pure returns (uint256 s, uint256 o) { assembly { s := lootboxRngPacked.slot o := lootboxRngPacked.offset } }
    function s_rngDayTags() external pure returns (uint256 s, uint256 o) { assembly { s := rngDayTags.slot o := rngDayTags.offset } }
    function s_deityBoonPacked() external pure returns (uint256 s, uint256 o) { assembly { s := deityBoonPacked.slot o := deityBoonPacked.offset } }
    function s_deityBoonRecipientDay() external pure returns (uint256 s, uint256 o) { assembly { s := deityBoonRecipientDay.slot o := deityBoonRecipientDay.offset } }
    function s_degeneretteRecordBounty() external pure returns (uint256 s, uint256 o) { assembly { s := degeneretteRecordBounty.slot o := degeneretteRecordBounty.offset } }
    function s_earlyTicketLevel() external pure returns (uint256 s, uint256 o) { assembly { s := earlyTicketLevel.slot o := earlyTicketLevel.offset } }
    function s_lootboxEvCapPacked() external pure returns (uint256 s, uint256 o) { assembly { s := lootboxEvCapPacked.slot o := lootboxEvCapPacked.offset } }
    function s_decBattleEntries() external pure returns (uint256 s, uint256 o) { assembly { s := decBattleEntries.slot o := decBattleEntries.offset } }
    function s_decBattleRounds() external pure returns (uint256 s, uint256 o) { assembly { s := decBattleRounds.slot o := decBattleRounds.offset } }
    function s_decBattleHeap() external pure returns (uint256 s, uint256 o) { assembly { s := decBattleHeap.slot o := decBattleHeap.offset } }
    function s_decBattlePlayers() external pure returns (uint256 s, uint256 o) { assembly { s := decBattlePlayers.slot o := decBattlePlayers.offset } }
    function s_dailyHeroWagers() external pure returns (uint256 s, uint256 o) { assembly { s := dailyHeroWagers.slot o := dailyHeroWagers.offset } }
    function s_yieldAccumulator() external pure returns (uint256 s, uint256 o) { assembly { s := yieldAccumulator.slot o := yieldAccumulator.offset } }
    function s_centuryBonusUsed() external pure returns (uint256 s, uint256 o) { assembly { s := centuryBonusUsed.slot o := centuryBonusUsed.offset } }
    function s_deityPassSales() external pure returns (uint256 s, uint256 o) { assembly { s := deityPassSales.slot o := deityPassSales.offset } }
    function s_protocolBoonPools() external pure returns (uint256 s, uint256 o) { assembly { s := protocolBoonPools.slot o := protocolBoonPools.offset } }
    function s_protocolBoonEntries() external pure returns (uint256 s, uint256 o) { assembly { s := protocolBoonEntries.slot o := protocolBoonEntries.offset } }
    function s_boonPacked() external pure returns (uint256 s, uint256 o) { assembly { s := boonPacked.slot o := boonPacked.offset } }
    function s_subOf() external pure returns (uint256 s, uint256 o) { assembly { s := _subOf.slot o := _subOf.offset } }
    function s_fundingSourceOf() external pure returns (uint256 s, uint256 o) { assembly { s := _fundingSourceOf.slot o := _fundingSourceOf.offset } }
    function s_subscribers() external pure returns (uint256 s, uint256 o) { assembly { s := _subscribers.slot o := _subscribers.offset } }
    function s_subCursor() external pure returns (uint256 s, uint256 o) { assembly { s := _subCursor.slot o := _subCursor.offset } }
    function s_subOpenCursor() external pure returns (uint256 s, uint256 o) { assembly { s := _subOpenCursor.slot o := _subOpenCursor.offset } }
    function s_afkingResetDay() external pure returns (uint256 s, uint256 o) { assembly { s := _afkingResetDay.slot o := _afkingResetDay.offset } }
    function s_boxCursor() external pure returns (uint256 s, uint256 o) { assembly { s := boxCursor.slot o := boxCursor.offset } }
    function s_boxReadCount() external pure returns (uint256 s, uint256 o) { assembly { s := boxReadCount.slot o := boxReadCount.offset } }
    function s_sdgnrsBonusLevel() external pure returns (uint256 s, uint256 o) { assembly { s := _sdgnrsBonusLevel.slot o := _sdgnrsBonusLevel.offset } }
    function s_pendingBoxCount() external pure returns (uint256 s, uint256 o) { assembly { s := _pendingBoxCount.slot o := _pendingBoxCount.offset } }
    function s_subBoxCount() external pure returns (uint256 s, uint256 o) { assembly { s := _subBoxCount.slot o := _subBoxCount.offset } }
    function s_boxQueue() external pure returns (uint256 s, uint256 o) { assembly { s := boxQueue.slot o := boxQueue.offset } }
    function s_foilRecord() external pure returns (uint256 s, uint256 o) { assembly { s := foilRecord.slot o := foilRecord.offset } }
    function s_foilMatchClaimed() external pure returns (uint256 s, uint256 o) { assembly { s := foilMatchClaimed.slot o := foilMatchClaimed.offset } }
    function s_dailyFoilDraw() external pure returns (uint256 s, uint256 o) { assembly { s := dailyFoilDraw.slot o := dailyFoilDraw.offset } }
    function s_foilQueue() external pure returns (uint256 s, uint256 o) { assembly { s := foilQueue.slot o := foilQueue.offset } }
    function s_foilCursor() external pure returns (uint256 s, uint256 o) { assembly { s := foilCursor.slot o := foilCursor.offset } }
    function s_foilGenerationDay() external pure returns (uint256 s, uint256 o) { assembly { s := foilGenerationDay.slot o := foilGenerationDay.offset } }
    function s_foilFirstDrawDay() external pure returns (uint256 s, uint256 o) { assembly { s := foilFirstDrawDay.slot o := foilFirstDrawDay.offset } }
    function s_foilWriteSlot() external pure returns (uint256 s, uint256 o) { assembly { s := foilWriteSlot.slot o := foilWriteSlot.offset } }
    function s_foilWriteCount() external pure returns (uint256 s, uint256 o) { assembly { s := foilWriteCount.slot o := foilWriteCount.offset } }
    function s_foilReadCount() external pure returns (uint256 s, uint256 o) { assembly { s := foilReadCount.slot o := foilReadCount.offset } }
    function s_deityRecipientBoonCount() external pure returns (uint256 s, uint256 o) { assembly { s := deityRecipientBoonCount.slot o := deityRecipientBoonCount.offset } }
    function s_goldenTicket() external pure returns (uint256 s, uint256 o) { assembly { s := goldenTicket.slot o := goldenTicket.offset } }
    function s_middayRngCredit() external pure returns (uint256 s, uint256 o) { assembly { s := middayRngCredit.slot o := middayRngCredit.offset } }
    function s_centuryPrizePools() external pure returns (uint256 s, uint256 o) { assembly { s := centuryPrizePools.slot o := centuryPrizePools.offset } }
    function s_ticketSeats() external pure returns (uint256 s, uint256 o) { assembly { s := ticketSeats.slot o := ticketSeats.offset } }
    function s_ticketGenerationStartBlock() external pure returns (uint256 s, uint256 o) { assembly { s := ticketGenerationStartBlock.slot o := ticketGenerationStartBlock.offset } }
    function s_deadTallyPos() external pure returns (uint256 s, uint256 o) { assembly { s := deadTallyPos.slot o := deadTallyPos.offset } }
    function s_deadTallyFoilDay() external pure returns (uint256 s, uint256 o) { assembly { s := deadTallyFoilDay.slot o := deadTallyFoilDay.offset } }
    function s_deadTallyFoilIdx() external pure returns (uint256 s, uint256 o) { assembly { s := deadTallyFoilIdx.slot o := deadTallyFoilIdx.offset } }
    function s_deadTallyStage() external pure returns (uint256 s, uint256 o) { assembly { s := deadTallyStage.slot o := deadTallyStage.offset } }
    function s_deadTraitCount() external pure returns (uint256 s, uint256 o) { assembly { s := deadTraitCount.slot o := deadTraitCount.offset } }
    function s_deadUncreated() external pure returns (uint256 s, uint256 o) { assembly { s := deadUncreated.slot o := deadUncreated.offset } }
    function s_deadCreated() external pure returns (uint256 s, uint256 o) { assembly { s := deadCreated.slot o := deadCreated.offset } }
    function s_deadPot() external pure returns (uint256 s, uint256 o) { assembly { s := deadPot.slot o := deadPot.offset } }
    function s_deadTotal() external pure returns (uint256 s, uint256 o) { assembly { s := deadTotal.slot o := deadTotal.offset } }
    function s_deadUncreatedLeft() external pure returns (uint256 s, uint256 o) { assembly { s := deadUncreatedLeft.slot o := deadUncreatedLeft.offset } }
    function s_deadClaimed() external pure returns (uint256 s, uint256 o) { assembly { s := deadClaimed.slot o := deadClaimed.offset } }
    function s_decBattleQueue() external pure returns (uint256 s, uint256 o) { assembly { s := decBattleQueue.slot o := decBattleQueue.offset } }
    function s_traitBucketLive() external pure returns (uint256 s, uint256 o) { assembly { s := traitBucketLive.slot o := traitBucketLive.offset } }
    function s_ticketPending() external pure returns (uint256 s, uint256 o) { assembly { s := ticketPending.slot o := ticketPending.offset } }
    function s_jackpotWork() external pure returns (uint256 s, uint256 o) { assembly { s := jackpotWork.slot o := jackpotWork.offset } }
    function s_farFutureOwed() external pure returns (uint256 s, uint256 o) { assembly { s := farFutureOwed.slot o := farFutureOwed.offset } }
    function s_decPreviousStack() external pure returns (uint256 s, uint256 o) { assembly { s := decPreviousStack.slot o := decPreviousStack.offset } }
    function s_decPreviousCount() external pure returns (uint256 s, uint256 o) { assembly { s := decPreviousCount.slot o := decPreviousCount.offset } }
    function s_decJackpotPlans() external pure returns (uint256 s, uint256 o) { assembly { s := decJackpotPlans.slot o := decJackpotPlans.offset } }
    function s_decGeneratedOwners() external pure returns (uint256 s, uint256 o) { assembly { s := decGeneratedOwners.slot o := decGeneratedOwners.offset } }
}

/// @dev Reads Craps `.slot`s off the audited Craps storage, plus the LootboxCraps Game-slot pins.
contract CrapsSlotHarness is CrapsBattleStorage {
    function dayStaked() external pure returns (uint256 s) { assembly { s := _dayStaked.slot } }
    function highField() external pure returns (uint256 s) { assembly { s := _highField.slot } }
    function passCreditsById() external pure returns (uint256 s) { assembly { s := _passCreditsById.slot } }
    function lootboxCrapsPins() external pure returns (uint256, uint256, uint256, uint256) {
        return (RNG_STATE_SLOT, LOOTBOX_RNG_WORD_SLOT, RNG_WORD_BY_DAY_SLOT, RNG_DAY_TAGS_SLOT);
    }
}

/// @dev Exposes WWXRP's internal Game boon-slot pin.
contract WwxrpSlotHarness is WWXRP {
    function boonPackedSlot() external pure returns (uint256) { return GAME_BOON_PACKED_SLOT; }
}

/// @title StorageSlotPins
/// @notice The single slot-pin gate: every hard-coded storage slot in production contracts and in
///         `test/helpers/GameSlots.sol` equals the compiled `.slot` of the variable it targets.
contract StorageSlotPinsTest is Test {
    GameSlotHarness internal h;

    function setUp() public {
        h = new GameSlotHarness();
    }

    function test_ProductionGameSlotConstants() public {
        CrapsSlotHarness c = new CrapsSlotHarness();
        (uint256 rngState, uint256 lootboxWord, uint256 wordByDay, uint256 dayTags) = c.lootboxCrapsPins();
        uint256 s;
        uint256 o;
        (s, o) = h.s_rngFlagsAndNudges(); assertEq(rngState, s, "LootboxCraps.RNG_STATE_SLOT");
        // LootboxCraps reads the write selector at slot-0 bit 252 (flags bit 12), terminal at 253
        // and publication at 255: the flags word must start at byte 30.
        assertEq(o * 8 + 12, 252, "LootboxCraps slot-0 flag bits");
        (s,) = h.s_rngWordCurrent(); assertEq(lootboxWord, s, "LootboxCraps.LOOTBOX_RNG_WORD_SLOT");
        (s,) = h.s_rngWordByDay(); assertEq(wordByDay, s, "LootboxCraps.RNG_WORD_BY_DAY_SLOT");
        (s,) = h.s_rngDayTags(); assertEq(dayTags, s, "LootboxCraps.RNG_DAY_TAGS_SLOT");

        (s,) = h.s_boonPacked(); assertEq((new WwxrpSlotHarness()).boonPackedSlot(), s, "WWXRP.GAME_BOON_PACKED_SLOT");

        (s,) = h.s_wallets(); assertEq(WalletTableLib.OWNERS_SLOT, s, "WalletTableLib.OWNERS_SLOT");
    }

    function test_CrapsSlotConstants() public {
        CrapsSlotHarness c = new CrapsSlotHarness();
        // JackpotBattleFieldLib reads boards from the ID-keyed pass word in Craps storage.
        assertEq(CrapsPreferenceLib.PASS_SLOT, c.passCreditsById(), "CrapsPreferenceLib.PASS_SLOT");
        assertEq(CrapsSlots.PASS_CREDITS_BY_ID, c.passCreditsById(), "CrapsSlots.PASS_CREDITS_BY_ID");
        assertEq(CrapsSlots.DAY_STAKED, c.dayStaked(), "CrapsSlots.DAY_STAKED");
        assertEq(CrapsSlots.HIGH_FIELD, c.highField(), "CrapsSlots.HIGH_FIELD");
    }

    function test_GameSlotsLibrary() public view {
        uint256 s;
        uint256 o;
        (s, o) = h.s_purchaseStartDay(); assertEq(s, GameSlots.PURCHASE_START_DAY, "purchaseStartDay.slot"); assertEq(o, 0, "purchaseStartDay.offset");
        (s, o) = h.s_dailyIdx(); assertEq(s, GameSlots.DAILY_IDX, "dailyIdx.slot"); assertEq(o, GameSlots.DAILY_IDX_OFFSET, "dailyIdx.offset");
        (s, o) = h.s_rngRequestTime(); assertEq(s, GameSlots.RNG_REQUEST_TIME, "rngRequestTime.slot"); assertEq(o, GameSlots.RNG_REQUEST_TIME_OFFSET, "rngRequestTime.offset");
        (s, o) = h.s_level(); assertEq(s, GameSlots.LEVEL, "level.slot"); assertEq(o, GameSlots.LEVEL_OFFSET, "level.offset");
        (s, o) = h.s_jackpotPhaseFlag(); assertEq(s, GameSlots.JACKPOT_PHASE_FLAG, "jackpotPhaseFlag.slot"); assertEq(o, GameSlots.JACKPOT_PHASE_FLAG_OFFSET, "jackpotPhaseFlag.offset");
        (s, o) = h.s_jackpotCounter(); assertEq(s, GameSlots.JACKPOT_COUNTER, "jackpotCounter.slot"); assertEq(o, GameSlots.JACKPOT_COUNTER_OFFSET, "jackpotCounter.offset");
        (s, o) = h.s_lastPurchaseDay(); assertEq(s, GameSlots.LAST_PURCHASE_DAY, "lastPurchaseDay.slot"); assertEq(o, GameSlots.LAST_PURCHASE_DAY_OFFSET, "lastPurchaseDay.offset");
        (s, o) = h.s_decimatorFlags(); assertEq(s, GameSlots.DECIMATOR_FLAGS, "decimatorFlags.slot"); assertEq(o, GameSlots.DECIMATOR_FLAGS_OFFSET, "decimatorFlags.offset");
        (s, o) = h.s_rngLockedFlag(); assertEq(s, GameSlots.RNG_LOCKED_FLAG, "rngLockedFlag.slot"); assertEq(o, GameSlots.RNG_LOCKED_FLAG_OFFSET, "rngLockedFlag.offset");
        (s, o) = h.s_phaseTransitionActive(); assertEq(s, GameSlots.PHASE_TRANSITION_ACTIVE, "phaseTransitionActive.slot"); assertEq(o, GameSlots.PHASE_TRANSITION_ACTIVE_OFFSET, "phaseTransitionActive.offset");
        (s, o) = h.s_gameOver(); assertEq(s, GameSlots.GAME_OVER, "gameOver.slot"); assertEq(o, GameSlots.GAME_OVER_OFFSET, "gameOver.offset");
        (s, o) = h.s_dailyJackpotCoinTicketsPending(); assertEq(s, GameSlots.DAILY_JACKPOT_COIN_TICKETS_PENDING, "dailyJackpotCoinTicketsPending.slot"); assertEq(o, GameSlots.DAILY_JACKPOT_COIN_TICKETS_PENDING_OFFSET, "dailyJackpotCoinTicketsPending.offset");
        (s, o) = h.s_jackpotFlags(); assertEq(s, GameSlots.JACKPOT_FLAGS, "jackpotFlags.slot"); assertEq(o, GameSlots.JACKPOT_FLAGS_OFFSET, "jackpotFlags.offset");
        (s, o) = h.s_ticketsFullyProcessed(); assertEq(s, GameSlots.TICKETS_FULLY_PROCESSED, "ticketsFullyProcessed.slot"); assertEq(o, GameSlots.TICKETS_FULLY_PROCESSED_OFFSET, "ticketsFullyProcessed.offset");
        (s, o) = h.s_ticketWriteSlot(); assertEq(s, GameSlots.TICKET_WRITE_SLOT, "ticketWriteSlot.slot"); assertEq(o, GameSlots.TICKET_WRITE_SLOT_OFFSET, "ticketWriteSlot.offset");
        (s, o) = h.s_prizePoolFrozen(); assertEq(s, GameSlots.PRIZE_POOL_FROZEN, "prizePoolFrozen.slot"); assertEq(o, GameSlots.PRIZE_POOL_FROZEN_OFFSET, "prizePoolFrozen.offset");
        (s, o) = h.s_presaleOver(); assertEq(s, GameSlots.PRESALE_OVER, "presaleOver.slot"); assertEq(o, GameSlots.PRESALE_OVER_OFFSET, "presaleOver.offset");
        (s, o) = h.s_subsFullyProcessed(); assertEq(s, GameSlots.SUBS_FULLY_PROCESSED, "subsFullyProcessed.slot"); assertEq(o, GameSlots.SUBS_FULLY_PROCESSED_OFFSET, "subsFullyProcessed.offset");
        (s, o) = h.s_humanReadComplete(); assertEq(s, GameSlots.HUMAN_READ_COMPLETE, "humanReadComplete.slot"); assertEq(o, GameSlots.HUMAN_READ_COMPLETE_OFFSET, "humanReadComplete.offset");
        (s, o) = h.s_rngFlagsAndNudges(); assertEq(s, GameSlots.RNG_FLAGS_AND_NUDGES, "rngFlagsAndNudges.slot"); assertEq(o, GameSlots.RNG_FLAGS_AND_NUDGES_OFFSET, "rngFlagsAndNudges.offset");
        (s, o) = h.s_currentPrizePool(); assertEq(s, GameSlots.CURRENT_PRIZE_POOL, "currentPrizePool.slot"); assertEq(o, 0, "currentPrizePool.offset");
        (s, o) = h.s_claimablePool(); assertEq(s, GameSlots.CLAIMABLE_POOL, "claimablePool.slot"); assertEq(o, GameSlots.CLAIMABLE_POOL_OFFSET, "claimablePool.offset");
        (s, o) = h.s_prizePoolsPacked(); assertEq(s, GameSlots.PRIZE_POOLS_PACKED, "prizePoolsPacked.slot"); assertEq(o, 0, "prizePoolsPacked.offset");
        (s, o) = h.s_rngWordCurrent(); assertEq(s, GameSlots.RNG_WORD_CURRENT, "rngWordCurrent.slot"); assertEq(o, 0, "rngWordCurrent.offset");
        (s, o) = h.s_vrfRequestId(); assertEq(s, GameSlots.VRF_REQUEST_ID, "vrfRequestId.slot"); assertEq(o, 0, "vrfRequestId.offset");
        (s, o) = h.s_rngRequestDay(); assertEq(s, GameSlots.RNG_REQUEST_DAY, "rngRequestDay.slot"); assertEq(o, 0, "rngRequestDay.offset");
        (s, o) = h.s_rngGapApplied(); assertEq(s, GameSlots.RNG_GAP_APPLIED, "rngGapApplied.slot"); assertEq(o, GameSlots.RNG_GAP_APPLIED_OFFSET, "rngGapApplied.offset");
        (s, o) = h.s_lastVrfProcessedTimestamp(); assertEq(s, GameSlots.LAST_VRF_PROCESSED_TIMESTAMP, "lastVrfProcessedTimestamp.slot"); assertEq(o, GameSlots.LAST_VRF_PROCESSED_TIMESTAMP_OFFSET, "lastVrfProcessedTimestamp.offset");
        (s, o) = h.s_ticketBufferLevels(); assertEq(s, GameSlots.TICKET_BUFFER_LEVELS, "ticketBufferLevels.slot"); assertEq(o, GameSlots.TICKET_BUFFER_LEVELS_OFFSET, "ticketBufferLevels.offset");
        (s, o) = h.s_dailyTicketBudgetsPacked(); assertEq(s, GameSlots.DAILY_TICKET_BUDGETS_PACKED, "dailyTicketBudgetsPacked.slot"); assertEq(o, 0, "dailyTicketBudgetsPacked.offset");
        (s, o) = h.s_balancesPacked(); assertEq(s, GameSlots.BALANCES_PACKED, "balancesPacked.slot"); assertEq(o, 0, "balancesPacked.offset");
        (s, o) = h.s_lvlTraitEntry(); assertEq(s, GameSlots.LVL_TRAIT_ENTRY, "lvlTraitEntry.slot"); assertEq(o, 0, "lvlTraitEntry.offset");
        assertEq(h.s_walletIds(), GameSlots.WALLET_IDS, "walletIds.slot");
        (s, o) = h.s_afkingFundingApprovals(); assertEq(s, 78, "afkingFundingApprovals.slot"); assertEq(o, 0);
        (s, o) = h.s_mintPacked(); assertEq(s, GameSlots.MINT_PACKED, "mintPacked_.slot"); assertEq(o, 0, "mintPacked_.offset");
        (s, o) = h.s_rngWordByDay(); assertEq(s, GameSlots.RNG_WORD_BY_DAY, "rngWordByDay.slot"); assertEq(o, 0, "rngWordByDay.offset");
        (s, o) = h.s_prizePoolPendingPacked(); assertEq(s, GameSlots.PRIZE_POOL_PENDING_PACKED, "prizePoolPendingPacked.slot"); assertEq(o, 0, "prizePoolPendingPacked.offset");
        (s, o) = h.s_ticketQueue(); assertEq(s, GameSlots.TICKET_QUEUE, "ticketQueue.slot"); assertEq(o, 0, "ticketQueue.offset");
        (s, o) = h.s_wallets(); assertEq(s, GameSlots.WALLETS, "wallets.slot"); assertEq(o, 0, "wallets.offset");
        (s, o) = h.s_ticketCursor(); assertEq(s, GameSlots.TICKET_CURSOR, "ticketCursor.slot"); assertEq(o, 0, "ticketCursor.offset");
        (s, o) = h.s_ticketLevel(); assertEq(s, GameSlots.TICKET_LEVEL, "ticketLevel.slot"); assertEq(o, GameSlots.TICKET_LEVEL_OFFSET, "ticketLevel.offset");
        (s, o) = h.s_snapShift(); assertEq(s, GameSlots.SNAP_SHIFT, "snapShift.slot"); assertEq(o, GameSlots.SNAP_SHIFT_OFFSET, "snapShift.offset");
        (s, o) = h.s_snapLevel(); assertEq(s, GameSlots.SNAP_LEVEL, "snapLevel.slot"); assertEq(o, GameSlots.SNAP_LEVEL_OFFSET, "snapLevel.offset");
        (s, o) = h.s_snapPendingShift(); assertEq(s, GameSlots.SNAP_PENDING_SHIFT, "snapPendingShift.slot"); assertEq(o, GameSlots.SNAP_PENDING_SHIFT_OFFSET, "snapPendingShift.offset");
        (s, o) = h.s_ticketRound(); assertEq(s, GameSlots.TICKET_ROUND, "ticketRound.slot"); assertEq(o, GameSlots.TICKET_ROUND_OFFSET, "ticketRound.offset");
        (s, o) = h.s_ticketSoloOffset(); assertEq(s, GameSlots.TICKET_SOLO_OFFSET, "ticketSoloOffset.slot"); assertEq(o, GameSlots.TICKET_SOLO_OFFSET_OFFSET, "ticketSoloOffset.offset");
        (s, o) = h.s_degeneretteCursor(); assertEq(s, GameSlots.DEGENERETTE_CURSOR, "degeneretteCursor.slot"); assertEq(o, GameSlots.DEGENERETTE_CURSOR_OFFSET, "degeneretteCursor.offset");
        (s, o) = h.s_degeneretteReadCount(); assertEq(s, GameSlots.DEGENERETTE_READ_COUNT, "degeneretteReadCount.slot"); assertEq(o, GameSlots.DEGENERETTE_READ_COUNT_OFFSET, "degeneretteReadCount.offset");
        (s, o) = h.s_presaleBoxEthSold(); assertEq(s, GameSlots.PRESALE_BOX_ETH_SOLD, "presaleBoxEthSold.slot"); assertEq(o, 0, "presaleBoxEthSold.offset");
        (s, o) = h.s_presaleBoxCredit(); assertEq(s, GameSlots.PRESALE_BOX_CREDIT, "presaleBoxCredit.slot"); assertEq(o, 0, "presaleBoxCredit.offset");
        (s, o) = h.s_gameOverStatePacked(); assertEq(s, GameSlots.GAME_OVER_STATE_PACKED, "gameOverStatePacked.slot"); assertEq(o, 0, "gameOverStatePacked.offset");
        (s, o) = h.s_degeneretteQueue(); assertEq(s, GameSlots.DEGENERETTE_QUEUE, "degeneretteQueue.slot"); assertEq(o, 0, "degeneretteQueue.offset");
        (s, o) = h.s_operatorApprovals(); assertEq(s, GameSlots.OPERATOR_APPROVALS, "operatorApprovals.slot"); assertEq(o, 0, "operatorApprovals.offset");
        (s, o) = h.s_levelPrizePool(); assertEq(s, GameSlots.LEVEL_PRIZE_POOL, "levelPrizePool.slot"); assertEq(o, 0, "levelPrizePool.offset");
        (s, o) = h.s_playerClaimWord(); assertEq(s, GameSlots.PLAYER_CLAIM_WORD, "playerClaimWord.slot"); assertEq(o, 0, "playerClaimWord.offset");
        (s, o) = h.s_levelDgnrsPacked(); assertEq(s, GameSlots.LEVEL_DGNRS_PACKED, "levelDgnrsPacked.slot"); assertEq(o, 0, "levelDgnrsPacked.offset");
        (s, o) = h.s_deityPassPricePaid(); assertEq(s, GameSlots.DEITY_PASS_PRICE_PAID, "deityPassPricePaid.slot"); assertEq(o, 0, "deityPassPricePaid.offset");
        (s, o) = h.s_deityPassIds(); assertEq(s, GameSlots.DEITY_PASS_IDS, "deityPassIds.slot"); assertEq(o, 0, "deityPassIds.offset");
        (s, o) = h.s_deityBySymbol(); assertEq(s, GameSlots.DEITY_BY_SYMBOL, "deityBySymbol.slot"); assertEq(o, 0, "deityBySymbol.offset");
        (s, o) = h.s_presaleBoxDgnrsPoolStart(); assertEq(s, GameSlots.PRESALE_BOX_DGNRS_POOL_START, "presaleBoxDgnrsPoolStart.slot"); assertEq(o, 0, "presaleBoxDgnrsPoolStart.offset");
        (s, o) = h.s_vrfCoordinator(); assertEq(s, GameSlots.VRF_COORDINATOR, "vrfCoordinator.slot"); assertEq(o, 0, "vrfCoordinator.offset");
        (s, o) = h.s_vrfKeyHash(); assertEq(s, GameSlots.VRF_KEY_HASH, "vrfKeyHash.slot"); assertEq(o, 0, "vrfKeyHash.offset");
        (s, o) = h.s_vrfSubscriptionId(); assertEq(s, GameSlots.VRF_SUBSCRIPTION_ID, "vrfSubscriptionId.slot"); assertEq(o, 0, "vrfSubscriptionId.offset");
        (s, o) = h.s_lootboxRngPacked(); assertEq(s, GameSlots.LOOTBOX_RNG_PACKED, "lootboxRngPacked.slot"); assertEq(o, 0, "lootboxRngPacked.offset");
        (s, o) = h.s_rngDayTags(); assertEq(s, GameSlots.RNG_DAY_TAGS, "rngDayTags.slot"); assertEq(o, 0, "rngDayTags.offset");
        (s, o) = h.s_deityBoonPacked(); assertEq(s, GameSlots.DEITY_BOON_PACKED, "deityBoonPacked.slot"); assertEq(o, 0, "deityBoonPacked.offset");
        (s, o) = h.s_deityBoonRecipientDay(); assertEq(s, GameSlots.DEITY_BOON_RECIPIENT_DAY, "deityBoonRecipientDay.slot"); assertEq(o, 0, "deityBoonRecipientDay.offset");
        (s, o) = h.s_degeneretteRecordBounty(); assertEq(s, GameSlots.DEGENERETTE_RECORD_BOUNTY, "degeneretteRecordBounty.slot"); assertEq(o, 0, "degeneretteRecordBounty.offset");
        (s, o) = h.s_earlyTicketLevel(); assertEq(s, GameSlots.EARLY_TICKET_LEVEL, "earlyTicketLevel.slot"); assertEq(o, 0, "earlyTicketLevel.offset");
        (s, o) = h.s_lootboxEvCapPacked(); assertEq(s, GameSlots.LOOTBOX_EV_CAP_PACKED, "lootboxEvCapPacked.slot"); assertEq(o, 0, "lootboxEvCapPacked.offset");
        (s, o) = h.s_decBattleEntries(); assertEq(s, GameSlots.DEC_BATTLE_ENTRIES, "decBattleEntries.slot"); assertEq(o, 0, "decBattleEntries.offset");
        (s, o) = h.s_decBattleRounds(); assertEq(s, GameSlots.DEC_BATTLE_ROUNDS, "decBattleRounds.slot"); assertEq(o, 0, "decBattleRounds.offset");
        (s, o) = h.s_decBattleHeap(); assertEq(s, GameSlots.DEC_BATTLE_HEAP, "decBattleHeap.slot"); assertEq(o, 0, "decBattleHeap.offset");
        (s, o) = h.s_decBattlePlayers(); assertEq(s, GameSlots.DEC_BATTLE_PLAYERS, "decBattlePlayers.slot"); assertEq(o, 0, "decBattlePlayers.offset");
        (s, o) = h.s_dailyHeroWagers(); assertEq(s, GameSlots.DAILY_HERO_WAGERS, "dailyHeroWagers.slot"); assertEq(o, 0, "dailyHeroWagers.offset");
        (s, o) = h.s_yieldAccumulator(); assertEq(s, GameSlots.YIELD_ACCUMULATOR, "yieldAccumulator.slot"); assertEq(o, 0, "yieldAccumulator.offset");
        (s, o) = h.s_centuryBonusUsed(); assertEq(s, GameSlots.CENTURY_BONUS_USED, "centuryBonusUsed.slot"); assertEq(o, 0, "centuryBonusUsed.offset");
        (s, o) = h.s_deityPassSales(); assertEq(s, GameSlots.DEITY_PASS_SALES, "deityPassSales.slot"); assertEq(o, 0, "deityPassSales.offset");
        (s, o) = h.s_protocolBoonPools(); assertEq(s, GameSlots.PROTOCOL_BOON_POOLS, "protocolBoonPools.slot"); assertEq(o, 0, "protocolBoonPools.offset");
        (s, o) = h.s_protocolBoonEntries(); assertEq(s, GameSlots.PROTOCOL_BOON_ENTRIES, "protocolBoonEntries.slot"); assertEq(o, 0, "protocolBoonEntries.offset");
        (s, o) = h.s_boonPacked(); assertEq(s, GameSlots.BOON_PACKED, "boonPacked.slot"); assertEq(o, 0, "boonPacked.offset");
        (s, o) = h.s_subOf(); assertEq(s, GameSlots.SUB_OF, "_subOf.slot"); assertEq(o, 0, "_subOf.offset");
        (s, o) = h.s_fundingSourceOf(); assertEq(s, GameSlots.FUNDING_SOURCE_OF, "_fundingSourceOf.slot"); assertEq(o, 0, "_fundingSourceOf.offset");
        (s, o) = h.s_subscribers(); assertEq(s, GameSlots.SUBSCRIBERS, "_subscribers.slot"); assertEq(o, 0, "_subscribers.offset");
        (s, o) = h.s_subCursor(); assertEq(s, GameSlots.SUB_CURSOR, "_subCursor.slot"); assertEq(o, 0, "_subCursor.offset");
        (s, o) = h.s_subOpenCursor(); assertEq(s, GameSlots.SUB_OPEN_CURSOR, "_subOpenCursor.slot"); assertEq(o, GameSlots.SUB_OPEN_CURSOR_OFFSET, "_subOpenCursor.offset");
        (s, o) = h.s_afkingResetDay(); assertEq(s, GameSlots.AFKING_RESET_DAY, "_afkingResetDay.slot"); assertEq(o, GameSlots.AFKING_RESET_DAY_OFFSET, "_afkingResetDay.offset");
        (s, o) = h.s_boxCursor(); assertEq(s, GameSlots.BOX_CURSOR, "boxCursor.slot"); assertEq(o, GameSlots.BOX_CURSOR_OFFSET, "boxCursor.offset");
        (s, o) = h.s_boxReadCount(); assertEq(s, GameSlots.BOX_READ_COUNT, "boxReadCount.slot"); assertEq(o, GameSlots.BOX_READ_COUNT_OFFSET, "boxReadCount.offset");
        (s, o) = h.s_sdgnrsBonusLevel(); assertEq(s, GameSlots.SDGNRS_BONUS_LEVEL, "_sdgnrsBonusLevel.slot"); assertEq(o, GameSlots.SDGNRS_BONUS_LEVEL_OFFSET, "_sdgnrsBonusLevel.offset");
        (s, o) = h.s_pendingBoxCount(); assertEq(s, GameSlots.PENDING_BOX_COUNT, "_pendingBoxCount.slot"); assertEq(o, GameSlots.PENDING_BOX_COUNT_OFFSET, "_pendingBoxCount.offset");
        (s, o) = h.s_subBoxCount(); assertEq(s, GameSlots.SUB_BOX_COUNT, "_subBoxCount.slot"); assertEq(o, GameSlots.SUB_BOX_COUNT_OFFSET, "_subBoxCount.offset");
        (s, o) = h.s_boxQueue(); assertEq(s, GameSlots.BOX_QUEUE, "boxQueue.slot"); assertEq(o, 0, "boxQueue.offset");
        (s, o) = h.s_foilRecord(); assertEq(s, GameSlots.FOIL_RECORD, "foilRecord.slot"); assertEq(o, 0, "foilRecord.offset");
        (s, o) = h.s_foilMatchClaimed(); assertEq(s, GameSlots.FOIL_MATCH_CLAIMED, "foilMatchClaimed.slot"); assertEq(o, 0, "foilMatchClaimed.offset");
        (s, o) = h.s_dailyFoilDraw(); assertEq(s, GameSlots.DAILY_FOIL_DRAW, "dailyFoilDraw.slot"); assertEq(o, 0, "dailyFoilDraw.offset");
        (s, o) = h.s_foilQueue(); assertEq(s, GameSlots.FOIL_QUEUE, "foilQueue.slot"); assertEq(o, 0, "foilQueue.offset");
        (s, o) = h.s_foilCursor(); assertEq(s, GameSlots.FOIL_CURSOR, "foilCursor.slot"); assertEq(o, 0, "foilCursor.offset");
        (s, o) = h.s_foilGenerationDay(); assertEq(s, GameSlots.FOIL_GENERATION_DAY, "foilGenerationDay.slot"); assertEq(o, GameSlots.FOIL_GENERATION_DAY_OFFSET, "foilGenerationDay.offset");
        (s, o) = h.s_foilFirstDrawDay(); assertEq(s, GameSlots.FOIL_FIRST_DRAW_DAY, "foilFirstDrawDay.slot"); assertEq(o, GameSlots.FOIL_FIRST_DRAW_DAY_OFFSET, "foilFirstDrawDay.offset");
        (s, o) = h.s_foilWriteSlot(); assertEq(s, GameSlots.FOIL_WRITE_SLOT, "foilWriteSlot.slot"); assertEq(o, GameSlots.FOIL_WRITE_SLOT_OFFSET, "foilWriteSlot.offset");
        (s, o) = h.s_foilWriteCount(); assertEq(s, GameSlots.FOIL_WRITE_COUNT, "foilWriteCount.slot"); assertEq(o, GameSlots.FOIL_WRITE_COUNT_OFFSET, "foilWriteCount.offset");
        (s, o) = h.s_foilReadCount(); assertEq(s, GameSlots.FOIL_READ_COUNT, "foilReadCount.slot"); assertEq(o, GameSlots.FOIL_READ_COUNT_OFFSET, "foilReadCount.offset");
        (s, o) = h.s_deityRecipientBoonCount(); assertEq(s, GameSlots.DEITY_RECIPIENT_BOON_COUNT, "deityRecipientBoonCount.slot"); assertEq(o, 0, "deityRecipientBoonCount.offset");
        (s, o) = h.s_goldenTicket(); assertEq(s, GameSlots.GOLDEN_TICKET, "goldenTicket.slot"); assertEq(o, 0, "goldenTicket.offset");
        (s, o) = h.s_middayRngCredit(); assertEq(s, GameSlots.MIDDAY_RNG_CREDIT, "middayRngCredit.slot"); assertEq(o, 0, "middayRngCredit.offset");
        (s, o) = h.s_centuryPrizePools(); assertEq(s, GameSlots.CENTURY_PRIZE_POOLS, "centuryPrizePools.slot"); assertEq(o, 0, "centuryPrizePools.offset");
        (s, o) = h.s_ticketSeats(); assertEq(s, GameSlots.TICKET_SEATS, "ticketSeats.slot"); assertEq(o, 0, "ticketSeats.offset");
        (s, o) = h.s_ticketGenerationStartBlock(); assertEq(s, GameSlots.TICKET_GENERATION_START_BLOCK, "ticketGenerationStartBlock.slot"); assertEq(o, 0, "ticketGenerationStartBlock.offset");
        (s, o) = h.s_deadTallyPos(); assertEq(s, GameSlots.DEAD_TALLY_POS, "deadTallyPos.slot"); assertEq(o, 0, "deadTallyPos.offset");
        (s, o) = h.s_deadTallyFoilDay(); assertEq(s, GameSlots.DEAD_TALLY_FOIL_DAY, "deadTallyFoilDay.slot"); assertEq(o, GameSlots.DEAD_TALLY_FOIL_DAY_OFFSET, "deadTallyFoilDay.offset");
        (s, o) = h.s_deadTallyFoilIdx(); assertEq(s, GameSlots.DEAD_TALLY_FOIL_IDX, "deadTallyFoilIdx.slot"); assertEq(o, GameSlots.DEAD_TALLY_FOIL_IDX_OFFSET, "deadTallyFoilIdx.offset");
        (s, o) = h.s_deadTallyStage(); assertEq(s, GameSlots.DEAD_TALLY_STAGE, "deadTallyStage.slot"); assertEq(o, GameSlots.DEAD_TALLY_STAGE_OFFSET, "deadTallyStage.offset");
        (s, o) = h.s_deadTraitCount(); assertEq(s, GameSlots.DEAD_TRAIT_COUNT, "deadTraitCount.slot"); assertEq(o, GameSlots.DEAD_TRAIT_COUNT_OFFSET, "deadTraitCount.offset");
        (s, o) = h.s_deadUncreated(); assertEq(s, GameSlots.DEAD_UNCREATED, "deadUncreated.slot"); assertEq(o, GameSlots.DEAD_UNCREATED_OFFSET, "deadUncreated.offset");
        (s, o) = h.s_deadCreated(); assertEq(s, GameSlots.DEAD_CREATED, "deadCreated.slot"); assertEq(o, GameSlots.DEAD_CREATED_OFFSET, "deadCreated.offset");
        (s, o) = h.s_deadPot(); assertEq(s, GameSlots.DEAD_POT, "deadPot.slot"); assertEq(o, 0, "deadPot.offset");
        (s, o) = h.s_deadTotal(); assertEq(s, GameSlots.DEAD_TOTAL, "deadTotal.slot"); assertEq(o, GameSlots.DEAD_TOTAL_OFFSET, "deadTotal.offset");
        (s, o) = h.s_deadUncreatedLeft(); assertEq(s, GameSlots.DEAD_UNCREATED_LEFT, "deadUncreatedLeft.slot"); assertEq(o, GameSlots.DEAD_UNCREATED_LEFT_OFFSET, "deadUncreatedLeft.offset");
        (s, o) = h.s_deadClaimed(); assertEq(s, GameSlots.DEAD_CLAIMED, "deadClaimed.slot"); assertEq(o, 0, "deadClaimed.offset");
        (s, o) = h.s_decBattleQueue(); assertEq(s, GameSlots.DEC_BATTLE_QUEUE, "decBattleQueue.slot"); assertEq(o, 0, "decBattleQueue.offset");
        (s, o) = h.s_traitBucketLive(); assertEq(s, GameSlots.TRAIT_BUCKET_LIVE, "traitBucketLive.slot"); assertEq(o, 0, "traitBucketLive.offset");
        (s, o) = h.s_ticketPending(); assertEq(s, GameSlots.TICKET_PENDING, "ticketPending.slot"); assertEq(o, 0, "ticketPending.offset");
        (s, o) = h.s_jackpotWork(); assertEq(s, GameSlots.JACKPOT_WORK, "jackpotWork.slot"); assertEq(o, 0, "jackpotWork.offset");
        (s, o) = h.s_farFutureOwed(); assertEq(s, GameSlots.FAR_FUTURE_OWED, "farFutureOwed.slot"); assertEq(o, 0, "farFutureOwed.offset");
        (s, o) = h.s_decPreviousStack(); assertEq(s, GameSlots.DEC_PREVIOUS_STACK, "decPreviousStack.slot"); assertEq(o, 0, "decPreviousStack.offset");
        (s, o) = h.s_decPreviousCount(); assertEq(s, GameSlots.DEC_PREVIOUS_COUNT, "decPreviousCount.slot"); assertEq(o, GameSlots.DEC_PREVIOUS_COUNT_OFFSET, "decPreviousCount.offset");
        (s, o) = h.s_decJackpotPlans(); assertEq(s, GameSlots.DEC_JACKPOT_PLANS, "decJackpotPlans.slot"); assertEq(o, 0, "decJackpotPlans.offset");
        (s, o) = h.s_decGeneratedOwners(); assertEq(s, GameSlots.DEC_GENERATED_OWNERS, "decGeneratedOwners.slot"); assertEq(o, 0, "decGeneratedOwners.offset");
    }
}
