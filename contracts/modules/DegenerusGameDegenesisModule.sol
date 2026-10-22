// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {MineFlipGasBounds as GasBounds} from "../libraries/MineFlipGasBounds.sol";
import {MineFlipGas} from "../libraries/MineFlipGas.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {IsDGNRS} from "../interfaces/IsDGNRS.sol";
import {CrapsPriceLib} from "../libraries/CrapsPriceLib.sol";
import {EntropyLib} from "../libraries/EntropyLib.sol";
import {FlipRoundLib} from "../libraries/FlipRoundLib.sol";
import {GameTimeLib} from "../libraries/GameTimeLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";
import {MintPaymentKind} from "../interfaces/IDegenerusGame.sol";
import {IDegenerusGameWhaleModule, IDegenerusGameMintModule} from "../interfaces/IDegenerusGameModules.sol";

interface IDegenesisWwxrp {
    function creditPrize(uint32 to, uint256 amount) external;
}

interface IDegenesisPasses {
    function creditPasses(uint32 id, uint32 normal, uint32 high) external;
}

/**
 * @title DegenerusGameDegenesisModule
 * @author Burnie Degenerus
 * @notice Delegatecall module for the seven-day Degenesis sale: purchases, the per-cohort split
 *         and pricing at the daily request, and the miner's settlement stage.
 * @dev Runs in the Game's storage. Outside this module the sale costs the rest of the game only
 *      the credit window's timestamp compare and slot-0 reads of degenesisClosed.
 */
contract DegenerusGameDegenesisModule is DegenerusGameStorage {
    event DegenesisAfkingExcessClaimable(uint256 amount);

    /// @notice Emitted when a Degenesis order joins its day's cohort.
    /// @param buyer The account the order is for.
    /// @param degenesisDay The cohort, Degenesis day 1..7.
    /// @param orderIndex The order's zero-based position in that cohort.
    /// @param amount The order's ETH.
    /// @param secondsIntoDay Seconds since the day began, capped at six hours (the early bonus input).
    event DegenesisBuy(
        uint32 indexed buyer,
        uint8 degenesisDay,
        uint32 orderIndex,
        uint256 amount,
        uint256 secondsIntoDay
    );

    /// @notice Emitted when a Degenesis order is resolved.
    /// @param id The reward account's wallet ID.
    /// @param degenesisDay The order's cohort, Degenesis day 1..7.
    /// @param orderIndex The order's position in that cohort.
    /// @param amount The order's ETH.
    /// @param flip FLIP credited: the whole collapsed roll when the FLIP-valued category keeps
    ///        coin, or only the overflow above the 12-high-pass cap when it denominated into
    ///        passes; 0 otherwise.
    /// @param dgnrs sDGNRS paid.
    /// @param wwxrp WWXRP requested (before WWXRP's gameMintScale): the 10% consolation, or the
    ///        fallback for a FLIP result below one whole FLIP, a lost sub-pass fraction, or a
    ///        zero sDGNRS award.
    /// @param normalPasses Normal Craps day passes credited by the pass side (0 otherwise).
    /// @param highPasses High-roller Craps day passes credited by the pass side (0 otherwise).
    event DegenesisOrderResolved(
        uint32 indexed id,
        uint8 degenesisDay,
        uint32 orderIndex,
        uint256 amount,
        uint256 flip,
        uint256 dgnrs,
        uint256 wwxrp,
        uint32 normalPasses,
        uint32 highPasses
    );

    /// @notice A sealed cohort funds equal shares of future prizes, insurance, the Vault budget
    ///         and sDGNRS AFKing.
    event DegenesisCohortSplit(uint8 indexed degenesisDay, uint256 volume);
    /// @notice A sealed cohort was priced and bound to `boundDay`'s daily word.
    event DegenesisCohortPriced(uint8 indexed degenesisDay, uint256 volume, uint256 payoutBudget, uint24 boundDay);
    /// @notice A cohort closed, settled or empty; its unused sDGNRS reservation is released.
    event DegenesisCohortClosed(uint8 indexed degenesisDay, uint256 dgnrsPaid);
    /// @notice Leftover Degenesis inventory burned once the seventh cohort closed.
    event DegenesisInventoryBurned(uint256 dgnrs);
    /// @notice The Vault's Degenesis budget paid `cost` for `recipientId`.
    ///         The budget, not the Vault's claimable, pays it; the purchase's ClaimableSpent in the
    ///         same transaction reports a post-state that still includes the budget moved in.
    event DegenesisVaultSpent(uint32 indexed recipientId, uint256 cost);

    // ---- Degenesis FLIP ladder (lootbox band recentered on a 400% branch mean) ----
    // E[flipBps] = 0.8*lowMean + 0.2*highMean = 40000 (400% of order ETH on the FLIP-valued
    // category, which rolls 50%); the day schedule, early bonus and volume factor scale it.
    /// @dev Base BPS for the low Degenesis FLIP path (rolls 0-15, p=80%).
    uint32 private constant DEGENESIS_FLIP_LOW_BASE_BPS = 14_098;
    /// @dev Step BPS per roll for the low Degenesis FLIP path.
    uint32 private constant DEGENESIS_FLIP_LOW_STEP_BPS = 1158;
    /// @dev Base BPS for the high Degenesis FLIP path (rolls 16-19, p=20%).
    uint32 private constant DEGENESIS_FLIP_HIGH_BASE_BPS = 74_534;
    /// @dev Step BPS per roll for the high Degenesis FLIP path.
    uint32 private constant DEGENESIS_FLIP_HIGH_STEP_BPS = 22_890;

    /// @dev Ceiling on high-roller passes one Degenesis order can denominate; the budget above it
    ///      stays coinflip credit.
    uint256 private constant DEGENESIS_HIGH_PASS_CAP = 12;

    /// @dev Volume factor constant K_day = 46 ETH in DEGENESIS_UNIT: r = K / (K + V).
    uint256 private constant DEGENESIS_K_UNITS = 460_000;
    /// @dev FLIP scale = ladder bps x base(n) / 2 x earlyBonus x r with base(n) / 2 = (21 - n) / 16
    ///      and earlyBonus = (453_600 - s) / 432_000 for s seconds, capped at 21,600.
    uint256 private constant DEGENESIS_BONUS_NUMERATOR = 453_600;
    uint256 private constant DEGENESIS_FLIP_DENOMINATOR = 10_000 * 16 * 432_000;
    /// @dev sDGNRS AFKing funding target restored before each bulk whale attempt.
    uint256 private constant SDGNRS_AFKING_TARGET = 10 ether;
    /// @dev Orders one settlement call may resolve; sizes the chunk's coin-credit batch.
    uint256 private constant DEGENESIS_ORDER_CHUNK = 128;

    /// @dev Degenesis seed domain and its draw extractors: category, size, denomination.
    uint256 private constant DEGENESIS_ORDER_DOMAIN = 0x446567656e657369734f72646572; // "DegenesisOrder"
    uint256 private constant DEGENESIS_CATEGORY_TAG = 0x44656743617465676f7279; // "DegCategory"
    uint256 private constant DEGENESIS_SIZE_TAG = 0x44656753697a65; // "DegSize"
    uint256 private constant DEGENESIS_PASS_TAG = 0x5061737353696465; // "PassSide"

    /// @dev Nominal sDGNRS targets in raw units: 20B tokens on Degenesis days 1-3, 10B on 4-7.
    uint256 private constant DEGENESIS_TARGET_EARLY = 20_000_000_000 * 1e12;
    uint256 private constant DEGENESIS_TARGET_LATE = 10_000_000_000 * 1e12;

    /// @dev One whole WWXRP token, the consolation.
    uint256 private constant DEGENESIS_WWXRP_PRIZE = 1;
    /// @dev Extractors shared in form with the ordinary box: the 100-FLIP collapse and the
    ///      fractional pass round, read off the order's own seed.
    uint256 private constant FLIP_ROUND_TAG = 0x466c6970526f756e64; // "FlipRound"
    uint256 private constant BOX_PASS_ROUND_TAG = 0x50617373526f756e64; // "PassRound"

    /// @notice Buy a credit-gated Degenesis box, funded by msg.value, then the buyer's claimable,
    ///         then prepaid AFKing balance; overpay credits the payer's AFKing.
    /// @dev Sale-day, size and Vault gates, 1:1 credit consume, payment, then the whole amount is
    ///      held in claimablePool until the cohort split and the order joins today's cohort. No
    ///      affiliate, quest, streak or activity work. Raw msg.data target of Game.buyDegenesisBox.
    /// @param id Account receiving the order (0 = caller; account rule).
    /// @param amount Degenesis ETH: at least 0.01 ETH in whole 0.0001-ETH units, within the
    ///        per-order bound.
    function buyDegenesisBox(uint32 id, uint256 amount) external payable {
        // Delegatecall-only: a direct call on the deployed module would trap msg.value.
        if (address(this) != ContractAddresses.GAME) revert E();
        uint32 buyerId = _registerCallerAccount(_resolveAccountId(id), amount);
        uint256 value = msg.value;
        uint24 today = _simulatedDayIndex();
        uint256 units = amount / DEGENESIS_UNIT;
        if (
            !_degenesisSaleDay(today) || _livenessTriggered() || amount < DEGENESIS_MIN
                || amount % DEGENESIS_UNIT != 0 || units > DEGENESIS_AMOUNT_MASK
        ) revert E();
        // Covers a direct Vault call and an operator acting for wallet 1.
        if (buyerId == VAULT_WALLET_ID) revert E();

        uint256 credit = degenesisCredit[buyerId];
        if (amount > credit) revert E();
        unchecked {
            degenesisCredit[buyerId] = credit - amount;
        }

        // Overpay is credited to the payer's afking, not reverted.
        if (value > amount) {
            _creditAfkingValue(_requireWalletId(msg.sender), value - amount);
            value = amount;
        }
        _settleShortfall(buyerId, amount - value, true);
        // The whole amount is a reserved obligation until its cohort splits.
        claimablePool += uint128(amount);

        uint256 degenesisDay = today - GameTimeLib.DEGENESIS_START_DAY + 1;
        uint256 header = degenesisDays[degenesisDay];
        uint256 index = uint32(header >> GD_COUNT_SHIFT);
        uint256 secondsIntoDay = (block.timestamp - GameTimeLib.JACKPOT_RESET_TIME) % 1 days;
        if (secondsIntoDay > DEGENESIS_BONUS_WINDOW) secondsIntoDay = DEGENESIS_BONUS_WINDOW;
        uint256 lane = buyerId | (units << DEGENESIS_AMOUNT_SHIFT) | (secondsIntoDay << DEGENESIS_SECONDS_SHIFT);
        uint256 key = (degenesisDay << 32) | (index / 3);
        uint256 lanePos = index % 3;
        if (lanePos == 0) degenesisOrders[key] = lane;
        else degenesisOrders[key] |= lane << (lanePos * DEGENESIS_LANE_BITS);
        degenesisDays[degenesisDay] = header + units + (uint256(1) << GD_COUNT_SHIFT);

        emit DegenesisBuy(buyerId, uint8(degenesisDay), uint32(index), amount, secondsIntoDay);
    }

    /// @dev Degenesis days 1-7.
    function _degenesisSaleDay(uint24 day) private pure returns (bool) {
        return day >= GameTimeLib.DEGENESIS_START_DAY && day < GameTimeLib.MAIN_LAUNCH_DAY;
    }

    /// @notice Daily-request step: split every sealed cohort, then close sealed empty cohorts and
    ///         price the next sealed one once the previous cohort has settled, binding it to this
    ///         request's word.
    /// @dev Delegatecalled by the Advance module's request boundary only while degenesisClosed < 7.
    ///      Every input (V, the pool balance, the orders) is fixed before the request.
    /// @param day The request day.
    function prepareDegenesis(uint24 day) external {
        if (address(this) != ContractAddresses.GAME) revert E();
        _splitDegenesisCohorts(day);
        if (degenesisActive != 0) return;
        for (uint256 c = uint256(degenesisClosed) + 1; c <= DEGENESIS_DAYS; ++c) {
            if (GameTimeLib.DEGENESIS_START_DAY + c - 1 >= day) return;
            uint256 volume = uint48(degenesisDays[c]);
            if (volume == 0) {
                _closeDegenesisCohort();
                continue;
            }
            uint256 q = (c <= 3 ? DEGENESIS_TARGET_EARLY : DEGENESIS_TARGET_LATE) * 5 / 2;
            uint256 cap = dgnrs.poolBalance(IsDGNRS.Pool.Degenesis) * 2 / 3;
            if (cap < q) q = cap;
            degenesisActive = q | (uint256(day) << GA_DAY_SHIFT);
            emit DegenesisCohortPriced(uint8(c), volume * DEGENESIS_UNIT, q, day);
            return;
        }
    }

    /// @notice Top sDGNRS AFKing funding up to SDGNRS_AFKING_TARGET from its claimable above the
    ///         1-wei sentinel, before each once-per-level bulk whale attempt.
    /// @dev Delegatecalled by the AFKing STAGE ahead of the whale purchase, which then sizes its
    ///      budget on the remaining claimable. A reclassification inside claimablePool, kept
    ///      whether or not a group is bought.
    function topUpSdgnrsAfking() external {
        uint256 packed = balancesPacked[SDGNRS_WALLET_ID];
        uint256 afking = packed >> 128;
        uint256 claimable = uint128(packed);
        if (afking >= SDGNRS_AFKING_TARGET || claimable <= 1) return;
        uint256 topUp = SDGNRS_AFKING_TARGET - afking;
        if (topUp >= claimable) topUp = claimable - 1;
        balancesPacked[SDGNRS_WALLET_ID] = packed - topUp + (topUp << 128);
        emit ClaimableSpent(SDGNRS_WALLET_ID, topUp, claimable - topUp, MintPaymentKind.Internal, topUp);
        emit AfkingFunded(SDGNRS_WALLET_ID, topUp);
    }

    /// @notice Split every unsplit cohort, sealed or not. Idempotent.
    /// @dev Delegatecalled by terminal setup, after which no order can join a cohort.
    function splitDegenesis() external {
        if (address(this) != ContractAddresses.GAME) revert E();
        _splitDegenesisCohorts(type(uint24).max);
    }

    /// @notice Spend the Vault's Degenesis budget on a recipient's tickets
    ///         and lootboxes, or whale passes, at their normal price.
    /// @dev Vault-only, reached through the facade's delegatecall so msg.sender stays the Vault.
    ///      Moves `maxCost` from the budget into Vault claimable (a reclassification inside
    ///      claimablePool), runs the existing claimable-funded purchase in this frame, then moves
    ///      back what the purchase did not take. The purchase may lower the Vault's balance word
    ///      by at most `maxCost`, from claimable alone, so the net move is exactly the cost and
    ///      none of the budget stays withdrawable. No affiliate code: the Vault default applies.
    /// @param recipientId Allocated recipient account; 0 selects the Vault.
    /// @param whalePass True for whale passes, false for tickets and lootboxes.
    /// @param quantity Whale passes, or ticket purchase units (400 = one whole ticket).
    /// @param boxOrder Packed lootbox order (ignored with whale passes).
    /// @param maxCost Budget moved in for the purchase.
    function spendDegenesis(uint32 recipientId, bool whalePass, uint256 quantity, uint256 boxOrder, uint256 maxCost) external {
        uint256 budget = degenesisVaultBudget;
        if (address(this) != ContractAddresses.GAME || msg.sender != ContractAddresses.VAULT || maxCost > budget) {
            revert E();
        }
        if (recipientId == 0) recipientId = VAULT_WALLET_ID;
        _requireAllocated(recipientId);
        uint256 funded = balancesPacked[VAULT_WALLET_ID] + maxCost;
        balancesPacked[VAULT_WALLET_ID] = funded;
        (bool ok, bytes memory data) = whalePass
            ? ContractAddresses.GAME_WHALE_MODULE.delegatecall(abi.encodeWithSelector(
                IDegenerusGameWhaleModule.purchaseWhalePassForDegenesis.selector, recipientId, quantity
            ))
            : ContractAddresses.GAME_MINT_MODULE.delegatecall(abi.encodeWithSelector(
                IDegenerusGameMintModule.purchaseWith.selector, recipientId, quantity, boxOrder, bytes32(0),
                MintPaymentKind.Claimable, uint256(0), VAULT_WALLET_ID
            ));
        if (!ok) _revertDelegate(data);
        uint256 after_ = balancesPacked[VAULT_WALLET_ID];
        // Checked: a word that grew, an AFKing draw or a draw above maxCost reverts.
        uint256 cost = funded - after_;
        uint256 unspent = maxCost - cost;
        balancesPacked[VAULT_WALLET_ID] = after_ - unspent;
        degenesisVaultBudget = uint128(budget - cost);
        emit DegenesisVaultSpent(recipientId, cost);
    }

    function _revertDelegate(bytes memory reason) private pure {
        if (reason.length == 0) revert EmptyRevert();
        assembly ("memory-safe") {
            revert(add(32, reason), mload(reason))
        }
    }

    /// @dev Split every sealed, unsplit cohort before `day`. Half of V leaves claimablePool for
    ///      future prizes and insurance equally; the Vault budget and sDGNRS AFKing quarters stay inside it. V is a
    ///      whole number of DEGENESIS_UNIT, so the quarters are exact.
    function _splitDegenesisCohorts(uint24 day) private {
        uint256 quarters;
        for (uint256 c = uint256(degenesisClosed) + 1; c <= DEGENESIS_DAYS; ++c) {
            if (GameTimeLib.DEGENESIS_START_DAY + c - 1 >= day) break;
            uint256 header = degenesisDays[c];
            uint256 volume = uint48(header) * DEGENESIS_UNIT;
            if (volume == 0 || header & GD_SPLIT != 0) continue;
            degenesisDays[c] = header | GD_SPLIT;
            quarters += volume / 4;
            emit DegenesisCohortSplit(uint8(c), volume);
        }
        if (quarters == 0) return;
        claimablePool -= uint128(quarters * 2);
        _addPrizeContribution(0, uint128(quarters));
        yieldAccumulator += quarters;
        degenesisVaultBudget += uint128(quarters);
        balancesPacked[SDGNRS_WALLET_ID] += quarters << 128;
        emit AfkingFunded(SDGNRS_WALLET_ID, quarters);
    }

    /// @dev Close cohort degenesisClosed + 1, settled or empty, releasing its reservation. The
    ///      seventh close burns the leftover Degenesis inventory; degenesisClosed reaches 7 once.
    function _closeDegenesisCohort() private {
        uint8 closed = degenesisClosed + 1;
        degenesisClosed = closed;
        uint256 active = degenesisActive;
        if (active != 0) {
            degenesisActive = 0;
            degenesisWord = 0;
        }
        emit DegenesisCohortClosed(closed, (active >> GA_PAID_SHIFT) & GA_FIELD_MASK);
        if (closed == DEGENESIS_DAYS) {
            uint256 packed = balancesPacked[SDGNRS_WALLET_ID];
            uint256 afking = packed >> 128;
            if (afking > SDGNRS_AFKING_TARGET) {
                uint256 excess = afking - SDGNRS_AFKING_TARGET;
                balancesPacked[SDGNRS_WALLET_ID] =
                    (SDGNRS_AFKING_TARGET << 128) | (uint128(packed) + excess);
                emit AfkingSpent(SDGNRS_WALLET_ID, excess);
                emit PlayerCredited(SDGNRS_WALLET_ID, excess);
                emit DegenesisAfkingExcessClaimable(excess);
            }
            emit DegenesisInventoryBurned(
                dgnrs.transferFromPool(IsDGNRS.Pool.Degenesis, ContractAddresses.SDGNRS, type(uint256).max)
            );
        }
    }

    /// @dev The active cohort's frozen inputs.
    struct DegenesisCohort {
        uint256 word; // the bound daily word
        uint256 day; // Degenesis day 1..7
        uint256 volume; // V in DEGENESIS_UNIT
        uint256 q; // sDGNRS payout budget
    }

    /// @dev One order's outcome, fixed by state before any of it is paid.
    struct DegenesisOutcome {
        uint32 id;
        uint256 units;
        uint256 flip; // coin credit, joins the chunk's batch
        uint256 dgnrs; // sDGNRS award
        uint32 normalPasses;
        uint32 highPasses;
        bool wwxrp; // the consolation
    }

    /// @notice Settle the active Degenesis cohort's orders in order, then close the cohort.
    /// @dev Miner stage, not an RNG consumer. Each order's outcome is a pure function of the bound
    ///      word and the frozen cohort, derived before admission, so each admits against its own
    ///      branch bound plus the coin-credit flush still owed. The cursor advances before each
    ///      order pays. Coin credits pay in one batch per chunk: nothing acts between orders of
    ///      one call. Revert-free except gas: every callee is a revert-free credit or the
    ///      clamping pool transfer.
    function runDegenesisWork(uint256 gasAllowance) external returns (MineFlipGas.Result memory result) {
        MineFlipGas.Meter memory meter = MineFlipGas.start(gasAllowance);
        if (!_degenesisSettlePending()) {
            result.done = true;
            return result;
        }
        DegenesisCohort memory g;
        g.day = uint256(degenesisClosed) + 1;
        g.word = degenesisWord;
        uint256 active = degenesisActive;
        g.q = active & GA_FIELD_MASK;
        uint256 header = degenesisDays[g.day];
        g.volume = uint48(header);
        uint256 count = uint32(header >> GD_COUNT_SHIFT);
        uint256 cursor = uint32(active >> GA_CURSOR_SHIFT);
        uint256 end = count - cursor > DEGENESIS_ORDER_CHUNK ? cursor + DEGENESIS_ORDER_CHUNK : count;
        uint32[] memory ids = new uint32[](end - cursor);
        uint256[] memory amounts = new uint256[](end - cursor);
        uint256 queued;
        uint256 orders;
        while (cursor < end) {
            if (cursor % 3 == 0 || orders == 0) orders = degenesisOrders[(g.day << 32) | (cursor / 3)];
            DegenesisOutcome memory o = _degenesisOutcome(
                g, (orders >> ((cursor % 3) * DEGENESIS_LANE_BITS)) & DEGENESIS_LANE_MASK, cursor
            );
            uint256 credits = o.flip != 0 ? queued + 1 : queued;
            uint256 branchGas = o.dgnrs != 0 ? GasBounds.DEGENESIS_DGNRS_GAS
                : (o.normalPasses | o.highPasses) != 0 ? GasBounds.DEGENESIS_FLIP_PASS_GAS
                : o.wwxrp ? GasBounds.DEGENESIS_WWXRP_GAS : GasBounds.DEGENESIS_FLIP_CREDIT_GAS;
            if (!MineFlipGas.canRun(
                meter, branchGas, GasBounds.DEGENESIS_TAIL_GAS + credits * GasBounds.DEGENESIS_FLUSH_PER_CREDIT
            )) break;
            active += uint256(1) << GA_CURSOR_SHIFT;
            degenesisActive = active;
            uint256 paid = _resolveDegenesisOrder(g, o, cursor);
            if (paid != 0) {
                active += paid << GA_PAID_SHIFT;
                degenesisActive = active;
            }
            if (o.flip != 0) {
                ids[queued] = o.id;
                amounts[queued] = o.flip;
                queued = credits;
            }
            ++cursor;
            ++result.rewardBasis;
            result.progressed = true;
            MineFlipGas.markProgress(meter);
        }
        if (queued != 0) {
            assembly ("memory-safe") {
                mstore(ids, queued)
                mstore(amounts, queued)
            }
            coinflip.creditFlipBatch(ids, amounts);
        }
        if (cursor == count) {
            _closeDegenesisCohort();
            result.progressed = true;
            result.done = true;
        }
        MineFlipGas.finish(meter);
    }

    /// @dev Outcome of order `index` with lane `lane`: 50% FLIP-valued, 40% sDGNRS, 10% WWXRP,
    ///      each from its own extractor of hash4(DEGENESIS_ORDER_DOMAIN, word, day << 32 | index, id).
    ///      FLIP: the ladder scaled by the day schedule, the early bonus and the cohort's volume
    ///      factor in one multiply-then-divide, converted at the level-1 price, then collapsed and
    ///      denominated as an ordinary box's; below one whole FLIP pays WWXRP. sDGNRS:
    ///      x * Q * [5000, 15000] bps / V, never above 1.5Q over the cohort; zero pays WWXRP.
    function _degenesisOutcome(DegenesisCohort memory g, uint256 lane, uint256 index)
        private
        pure
        returns (DegenesisOutcome memory o)
    {
        o.id = uint32(lane);
        o.units = (lane >> DEGENESIS_AMOUNT_SHIFT) & DEGENESIS_AMOUNT_MASK;
        uint256 seed = EntropyLib.hash4(DEGENESIS_ORDER_DOMAIN, g.word, (g.day << 32) | index, o.id);
        uint256 category = EntropyLib.hash2(seed, DEGENESIS_CATEGORY_TAG) % 100;
        uint256 size = EntropyLib.hash2(seed, DEGENESIS_SIZE_TAG);
        if (category < 50) {
            uint256 roll = size % 20;
            uint256 flipBps = roll < 16
                ? DEGENESIS_FLIP_LOW_BASE_BPS + roll * DEGENESIS_FLIP_LOW_STEP_BPS
                : DEGENESIS_FLIP_HIGH_BASE_BPS + (roll - 16) * DEGENESIS_FLIP_HIGH_STEP_BPS;
            uint256 flipOut = (o.units * DEGENESIS_UNIT * PRICE_COIN_UNIT * flipBps * (21 - g.day)
                * (DEGENESIS_BONUS_NUMERATOR - (lane >> DEGENESIS_SECONDS_SHIFT)) * DEGENESIS_K_UNITS)
                / (DEGENESIS_FLIP_DENOMINATOR * (DEGENESIS_K_UNITS + g.volume) * PriceLookupLib.priceForLevel(1));
            // Collapse onto a whole 100-FLIP multiple above the threshold, EV-preserving;
            // smaller awards keep the whole-FLIP floor.
            flipOut = flipOut > FlipRoundLib.FLIP_ROUND_THRESHOLD
                ? FlipRoundLib.roundFlipToHundreds(flipOut, EntropyLib.hash2(seed, FLIP_ROUND_TAG))
                : FlipRoundLib.floorWholeFlip(flipOut);
            if (flipOut == 0) {
                o.wwxrp = true;
            } else if (EntropyLib.hash2(seed, DEGENESIS_PASS_TAG) & 1 == 1) {
                // Half the results denominate the whole roll into Craps day passes at the box
                // pass units, switching wholly to high-roller passes above HIGH_SWITCH. The
                // fractional pass is Bernoulli-rounded; from the twelve-high cap up the count pins
                // there and the rest stays coinflip credit. A lost sub-pass fraction pays WWXRP.
                bool highPass = flipOut > CrapsPriceLib.HIGH_SWITCH;
                uint256 passUnit = highPass ? HIGH_ROLLER_DAY_PASS_VALUE : NORMAL_DAY_PASS_VALUE;
                uint256 passCount = flipOut / passUnit;
                uint256 flipRest;
                if (highPass && passCount >= DEGENESIS_HIGH_PASS_CAP) {
                    passCount = DEGENESIS_HIGH_PASS_CAP;
                    flipRest = flipOut - DEGENESIS_HIGH_PASS_CAP * HIGH_ROLLER_DAY_PASS_VALUE;
                } else {
                    uint256 rem = flipOut % passUnit;
                    if (rem != 0 && EntropyLib.hash2(seed, BOX_PASS_ROUND_TAG) % passUnit < rem) ++passCount;
                }
                flipOut = flipRest;
                if (passCount == 0) o.wwxrp = true;
                else if (highPass) o.highPasses = uint32(passCount);
                else o.normalPasses = uint32(passCount);
            }
            o.flip = flipOut;
        } else if (category < 90) {
            o.dgnrs = (o.units * g.q * (5000 + size % 10_001)) / (g.volume * 10_000);
            if (o.dgnrs == 0) o.wwxrp = true;
        } else {
            o.wwxrp = true;
        }
    }

    /// @dev Pay an order's non-batched legs and announce it. Returns the sDGNRS paid; a transfer
    ///      that finds the pool empty pays the WWXRP consolation instead.
    function _resolveDegenesisOrder(DegenesisCohort memory g, DegenesisOutcome memory o, uint256 index)
        private
        returns (uint256 paid)
    {
        if (o.dgnrs != 0) {
            paid = dgnrs.transferFromPool(IsDGNRS.Pool.Degenesis, _payee(_walletElement(o.id)), o.dgnrs);
            if (paid == 0) o.wwxrp = true;
        } else if ((o.normalPasses | o.highPasses) != 0) {
            IDegenesisPasses(ContractAddresses.CRAPS).creditPasses(o.id, o.normalPasses, o.highPasses);
        }
        if (o.wwxrp) IDegenesisWwxrp(ContractAddresses.WWXRP).creditPrize(o.id, DEGENESIS_WWXRP_PRIZE);
        emit DegenesisOrderResolved(
            o.id,
            uint8(g.day),
            uint32(index),
            o.units * DEGENESIS_UNIT,
            o.flip,
            paid,
            o.wwxrp ? DEGENESIS_WWXRP_PRIZE : 0,
            o.normalPasses,
            o.highPasses
        );
    }
}
