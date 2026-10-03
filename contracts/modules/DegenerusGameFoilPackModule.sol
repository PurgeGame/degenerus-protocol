// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {GoldSixLib} from "../libraries/GoldSixLib.sol";

import {MineFlipGasBounds as GasBounds} from "../libraries/MineFlipGasBounds.sol";

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement and the exclusive source of truth; any
 * comment, name, document or statement that disagrees with it is in error. It has been
 * audited but is not proven correct: it may contain defects the author did not find, and
 * by interacting with it you accept that risk in full.
 *
 * Any state transition the code permits is authorised — including one that exploits a
 * defect, and including sequences the author did not intend or foresee. A bug is not a
 * breach of these terms. There is no unwritten rule behind the code for a permitted
 * transaction to violate, and no unauthorised access to this contract.
 *
 * You bear all resulting loss, whether it follows from chance or from a defect. There is
 * no refund, no rollback and no privileged party able to restore a position.
 *
 * Provided AS IS, without warranty of any kind. Full text: TERMS.md
 */

import {MineFlipGas} from "../libraries/MineFlipGas.sol";
import {TicketEntropy} from "../libraries/TicketEntropy.sol";
import {MintPaymentKind} from "../interfaces/IDegenerusGame.sol";
import {
    IDegenerusGameTicketModule,
    IDegenerusGameDegeneretteModule,
    IDegenerusGameJackpotModule
} from "../interfaces/IDegenerusGameModules.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {DegenerusTraitUtils} from "../DegenerusTraitUtils.sol";
import {DegenerusGamePayoutUtils} from "./DegenerusGamePayoutUtils.sol";
import {DegenerusGameMintStreakUtils} from "./DegenerusGameMintStreakUtils.sol";
import {ActivityCurveLib} from "../libraries/ActivityCurveLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";

/**
 * @title DegenerusGameFoilPackModule
 * @author Burnie Degenerus
 * @notice Delegate-called module for the foil pack: a 10x-priced four-ticket SKU
 *         whose boost multiplier and activity score freeze at buy (the match lines resolve later), a
 *         per-(day, ticket) match claim that reads the day's sealed winning set
 *         and pays an isolated 40/40/20 spin, and a per-pack gold route
 *         on how much gold the pack's own sixteen quadrants came out holding — pulled
 *         as a claim, except the grand, which the drain pushes where it is decided.
 * @dev All storage reads/writes operate on the inherited DegenerusGameStorage.
 *      The buy keys on the active ticket level (the cycle the pack bets into), so
 *      a pack and the draws it bets against share one cycle key. The claim never
 *      re-derives the winning set — it reads the tagged dailyFoilDraw slot, which the
 *      jackpot sealed, so the foil numbers equal the jackpot's.
 */
interface IFoilWwxrp {
    /// @notice Mint WWXRP to a recipient (WWXRP, authorized minters only).
    function mintPrize(address to, uint256 amount) external;
}

contract DegenerusGameFoilPackModule is
    DegenerusGamePayoutUtils,
    DegenerusGameMintStreakUtils
{
    /// @notice One deity perpetual ticket per owner was queued at `targetLevel`.
    /// @dev The owner set is the deity registry at that transition (genesis plus every
    ///      DeityPassPurchased so far); fresh registrations emit EntryOwnerRegistered.
    event DeityPerpetualQueued(uint24 indexed targetLevel, uint32 entriesPerOwner);

    /// @notice Extend every deity's perpetual coverage by one level, at most 32 owners.
    /// @dev The advance runs this exactly once per transition (the transition branch runs
    ///      once per boundary), so every owner is extended unconditionally. Existing
    ///      queued purchases and affiliate rewards share an owed record; append only newly
    ///      enrolled owners. One event covers the batch.
    function queuePerpetualTickets(uint24 targetLevel) external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if (targetLevel != level + 100) return;
        uint24 key = _tqFarFutureKey(targetLevel);
        uint256 lanes;
        uint256 count;
        uint256 total = deityPassOwners.length;
        for (uint256 i; i < total; ++i) {
            address owner = deityPassOwners[i];
            uint80 packed = _entriesOwed(key, owner);
            if (packed == 0) {
                packed = _registerEntryOwner(owner, targetLevel);
                if (packed == 0) continue;
                lanes |= uint256(uint32(packed >> OWNER_IDX_SHIFT)) << (count * 32);
                if (++count == 8) {
                    _tqAppendLanes(key, lanes, count);
                    lanes = 0;
                    count = 0;
                }
            }
            uint32 owed = _saturateFarFutureOwed(uint256(uint32(packed >> 8)) + DEITY_PERPETUAL_ENTRIES);
            _setEntryOwed(key, uint32(packed >> OWNER_IDX_SHIFT),
                (packed & OWNER_IDX_MASK) | (uint80(owed) << 8) | uint80(uint8(packed)));
        }
        if (count != 0) _tqAppendLanes(key, lanes, count);
        if (total != 0) emit DeityPerpetualQueued(targetLevel, DEITY_PERPETUAL_ENTRIES);
    }

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    // error E() — inherited from DegenerusGameStorage
    /// @notice Thrown when the buyer already holds a foil pack for this cycle level.
    error FoilAlreadyBought();
    /// @notice The reusable slot still holds a pending pack or unexpired claim rights.
    error FoilRecordBusy();
    /// @notice Thrown when the given (player, day, ticketIndex) tuple does not resolve to
    ///         a claimable foil match.
    error NoClaimableMatch();
    /// @notice Thrown when the batch's opening tuple is not claimable because the list has
    ///         already been swept.
    error StaleBatch();
    /// @notice Thrown when there is no pack at that cycle, its lines have not resolved yet,
    ///         it holds under three golds, it is already claimed, or it holds two or more
    ///         all-gold tickets (the grand route, paid by the drain, never the pull).
    error NoGoldenTicket();

    // -------------------------------------------------------------------------
    // External Contract References (compile-time constants)
    // -------------------------------------------------------------------------

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @dev FLIP face value: one face stakes 1,000 FLIP into the spin.
    uint256 private constant FLIP_FACE_AMOUNT = 1000e18;

    /// @dev WWXRP face value: one face stakes 1 WWXRP into the spin. WWXRP is a worthless
    ///      currency by design — the spin/score is revealed first and the currency only
    ///      after, so a WWXRP outcome is a deliberate dud. The 1-coin stake is cosmetic
    ///      (the lane carries no value); only the ETH and FLIP lanes pay.
    uint256 private constant WWXRP_FACE_AMOUNT = 1e18;

    // Per-score face counts for the graded match (see _tryClaimFoilMatch).
    // One face stakes 1,000 FLIP or priceForLevel(L) ETH — one ticket of value either
    // way (WWXRP, the third currency, is worthless). The schedule was calibrated to
    // E[faces/comparison] = 0.087774 on an independent, uniform winning board. That is
    // a reference baseline: hero selection and gold-six survival/redistribution mean
    // actual match probabilities depend on the stored line and the day's board policy.
    // A pack compares its four lines against the day's one board every day, purchase and
    // jackpot days alike, so its match value grows with how long its level runs: FOIL IS A
    // BET ON THE LEVEL SLOWING DOWN. The ETH and FLIP lanes each occur 40% of the time;
    // their faces fund reward spins rather than guaranteed face-value payouts.
    // Score T (0..8) pays from T=4; T=8 (all four full doubles) also grants a half whale pass.
    uint256 private constant FOIL_FACES_T4 = 16;
    uint256 private constant FOIL_FACES_T5 = 48;
    uint256 private constant FOIL_FACES_T6 = 280;
    uint256 private constant FOIL_FACES_T7 = 3_200;
    uint256 private constant FOIL_FACES_T8 = 80_000;

    // The gold ladder: FLIP on the pack's TOTAL gold count, its sixteen quadrants read
    // as one pool. This is the rung players actually meet — the boost sets a per-quadrant
    // gold cut of 1.5625% at the floor to 4.6875% at the cap, so three or more golds
    // lands 1 pack in 545 at score 0, 1 in 114 at 150, 1 in 44 at 300 and 1 in 27 at the
    // cap. Calibrated so a score-300 pack averages ~689 FLIP (0.69 tickets of coin at the
    // reference rate); the same table pays ~43 at score 0 and ~1,209 at the cap, so the
    // ladder's value tracks activity the way the boost that produced it does.
    // Rungs accelerate ~3x against a ~10x rarity step, so the low rung carries the EV
    // (3 golds = 58% of it, 4 golds = 31%) and the tail is a lottery, not a subsidy.
    uint256 private constant GOLD_LADDER_3 = 20_000e18;
    uint256 private constant GOLD_LADDER_4 = 80_000e18;
    uint256 private constant GOLD_LADDER_5 = 250_000e18;
    uint256 private constant GOLD_LADDER_6 = 750_000e18;
    uint256 private constant GOLD_LADDER_7 = 2_500_000e18;
    uint256 private constant GOLD_LADDER_8 = 7_500_000e18;

    /// @dev Kicker on top of the ladder when the pack holds exactly ONE all-gold ticket
    ///      — four golds landing in the SAME ticket rather than scattered, which is
    ///      ~1 pack in 107,000 at score 300 against 1 in 381 for four golds anywhere.
    ///      It pays for the shape, not the count. Two all-gold tickets skip both the
    ///      ladder and this and take the grand.
    uint256 private constant GOLDEN_TICKET_FLIP = 25_000e18;

    /// @dev Budget units the grand's own writes cost when a pack pushes it from the
    ///      drain: the futurePrizePool debit, the winner's claimable credit, the
    ///      claimable-pool total, the whale-pass credit, and the coinflip module's own
    ///      write behind an external call, plus the claim marker that closes the pull
    ///      behind it — roughly 110k gas against this budget's ~10k-per-unit
    ///      calibration, rounded up for headroom. Charged only on the pack that fires
    ///      it, never folded into the fixed per-pack charge, so the ~7.1 billion packs
    ///      that do not reach it pay nothing toward it.
    uint32 private constant GRAND_DRAIN_UNITS = 14;

    /// @dev Per-settled-claim keeper bounty target (ETH-equivalent wei) for the
    ///      permissionless batch claimer, converted to FLIP at the reference price.
    ///      Mirrors the decimator box-claim bounty so a sweeper is reimbursed roughly
    ///      its per-claim settle gas.
    uint256 private constant FOIL_CLAIM_BOUNTY_ETH_TARGET = 15_000_000_000_000;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a foil pack is bought and its boost freezes.
    /// @param buyer The player who bought the pack.
    /// @param level The cycle level the pack bets into.
    /// @param multBps The frozen activity-boost multiplier (20000..60000).
    /// @dev weiIn = the foil-premium ETH-in (any funding source); the off-chain ETH-in ledger
    ///      reads it here instead of a separate event.
    event FoilPackBought(
        address indexed buyer,
        uint24 indexed level,
        uint16 multBps,
        uint256 weiIn
    );

    /// @notice Emitted when a foil match claim resolves to a paid tier.
    /// @param player The claimant.
    /// @param day The draw day claimed against.
    /// @param ticketIndex Which of the pack's four tickets matched the board (0-3).
    /// @param tier The matched score T (4..8): the graded symbol/color axis match; T=8
    ///        is the moonshot (all four full doubles). Field name retained for the indexer.
    /// @param faces The face count paid for the score.
    event FoilMatchClaimed(
        address indexed player,
        uint24 indexed day,
        uint256 ticketIndex,
        uint8 tier,
        uint256 faces
    );

    /// @notice Emitted when a pack's gold is claimed.
    /// @param player The pack's buyer.
    /// @param level The pack's cycle level.
    /// @param golds The pack's total gold quadrants (3-16); the ladder rung.
    /// @param allGoldTickets How many of the pack's four tickets came out all gold.
    /// @param flipCredit FLIP credited (ladder + any single-all-gold-ticket kicker);
    ///        0 on the grand, whose payout is stamped by GoldenTicketWin instead.
    event GoldenTicketFoil(
        address indexed player,
        uint24 indexed level,
        uint8 golds,
        uint8 allGoldTickets,
        uint256 flipCredit
    );

    // =========================================================================
    // Buy
    // =========================================================================

    /// @notice Deliver one foil pack (four tickets) for the active cycle as the foil leg
    ///         of an additive ticket/lootbox/foil purchase.
    /// @dev Delegatecall-only from the Game facade's combined purchase path (_purchaseWithFoil), a
    ///      sibling leg to the mint ticket/lootbox leg: address(this) == GAME. A direct call on the deployed module would trap the
    ///      in-flight msg.value against empty local state. Liveness is gated by the purchase
    ///      path. This handles the ENTIRE foil leg so a foil pack counts exactly like a
    ///      ticket purchase: its own payment (75/25 pool), the 25|20/5 affiliate, the ten
    ///      price-equivalent mint units, the daily MINT_ETH primary + level quest, the mint
    ///      streak, the recycle bonus, the boost freeze, the queue push, and the foil
    ///      secondary quest. Kept a separate leg (not folded into the ticket path) so the
    ///      near-full mint module's purchase body stays within the via-IR stack budget.
    /// @param buyer Player receiving the pack (already operator-resolved).
    /// @param ethSent Fresh ETH the purchase path carved for the foil leg.
    /// @param affiliateCode Affiliate/referral code for the foil leg.
    /// @param payKind Payment method (DirectEth forbids drawing claimable; prepaid afking
    ///        still covers the shortfall on every kind).
    function buyFoilPack(
        address buyer,
        uint256 ethSent,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) external payable {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();

        // Block once the liveness-timeout game-over trigger is active, or the game has
        // ended: a foil pack must not be added to a terminal jackpot whose resolving word
        // is becoming known (mirrors the ticket queue's guard), and a post-gameover buy
        // could never resolve a match.
        if (gameOver) revert GameOver();
        if (_livenessTriggered()) revert GameOver();

        // Use the same active level and frozen read/write cohort as normal tickets.
        // Purchases after a request enter the next cohort and require fresh entropy.
        uint24 lvl = _activeTicketLevel();
        if (_foilBoughtThisLevel(buyer, lvl)) revert FoilAlreadyBought();
        if (!_foilRecordReusable(foilRecord[lvl & 3][buyer])) revert FoilRecordBusy();


        // Price: ten ticket prices for the level. The fresh ETH the purchase path carved
        // for the foil leg covers it first (overpay ignored); any shortfall runs the
        // canonical spend waterfall, so the pack is funded by the same mix as every other
        // purchase. cost - claimableUsed (fresh ETH plus the afking draw, the buyer's own
        // principal) is the fresh-rate affiliate basis; claimableUsed is the recycle-rate basis.
        uint256 priceWei = PriceLookupLib.priceForLevel(lvl);
        // Snap valve: the pack keeps its full four lines and match game on a thanos
        // level — the price carries the exponent instead (2^s times ten ticket
        // prices), the same effective cost-per-entry scaling the ticket path gets
        // from quantity division.
        uint8 snapS = _snapShiftFor(lvl);
        uint256 cost = (FOIL_PACK_TICKETS * priceWei) << snapS;
        uint256 ethUsed = ethSent < cost ? ethSent : cost;
        uint256 claimableUsed;
        if (ethUsed != cost) {
            // Canonical waterfall (the ticket leg's _processMintPayment tiers): claimable
            // down to the 1-wei sentinel — skipped on DirectEth — then the buyer's prepaid
            // afking, reverting when the tiers together fall short. The sink emits
            // ClaimableSpent / AfkingSpent and pairs the claimablePool debit.
            (claimableUsed, ) = _settleShortfall(
                buyer,
                cost - ethUsed,
                payKind != MintPaymentKind.DirectEth
            );
        }

        // Pool fork: 25% future / 75% next (inverse of the 90/10 ticket split), applied to
        // the foil cost specifically (the ticket/lootbox legs keep their own splits). The
        // frozen/unfrozen routing branch is reused verbatim; only the bps differ.
        uint256 futureShare = (cost * FOIL_TO_FUTURE_BPS) / 10_000;
        uint256 nextShare = cost - futureShare;
        if (prizePoolFrozen) {
            (uint128 pNext, uint128 pFuture) = _getPendingPools();
            _setPendingPools(
                pNext + uint128(nextShare),
                pFuture + uint128(futureShare)
            );
        } else {
            (uint128 next, uint128 future) = _getPrizePools();
            _setPrizePools(
                next + uint128(nextShare),
                future + uint128(futureShare)
            );
        }

        // Price-equivalent mint units — the pack costs 2^s times ten ticket prices,
        // so it records the units the same ETH spent on tickets would, in the ticket
        // leg's quantity scale (one whole ticket = 4 * QTY_SCALE units). Via the
        // shared _recordMintData. Runs before the quest + boost so the units feed
        // the activity score exactly like the equivalent ticket purchase.
        _recordMintData(
            buyer,
            lvl,
            uint32((FOIL_PACK_TICKETS * 4 * QTY_SCALE) << snapS)
        );

        // Affiliate, fresh 25% at affiliate levels 1-3 / 20% at 4+ (paid at level + 1) and 5% recycle exactly like a
        // normal ticket mint: the fresh portion (cost - claimableUsed, fresh ETH plus the
        // afking-drawn principal) at the fresh rate, the claimable portion at the recycle
        // rate, both frozen at level + 1 like the ticket affiliate (score 0, same as
        // tickets). FLIP kickbacks accumulate and are credited once below.
        uint24 affLevel = level + 1;
        uint256 kickback;
        uint256 freshBasis = cost - claimableUsed;
        if (freshBasis != 0) {
            kickback += affiliate.payAffiliate(
                (freshBasis * PRICE_COIN_UNIT) / priceWei,
                affiliateCode,
                buyer,
                affLevel,
                true,
                0
            );
        }
        if (claimableUsed != 0) {
            kickback += affiliate.payAffiliate(
                (claimableUsed * PRICE_COIN_UNIT) / priceWei,
                affiliateCode,
                buyer,
                affLevel,
                false,
                0
            );
        }

        // Daily MINT_ETH primary + level quest, on the foil cost, together with the foil
        // secondary quest and streak floor in one GAME call. The combined ticket leg (run
        // first by the purchase path) may already have completed the primary today, in which
        // case the primary leg is idempotent (completed = false, no double reward/streak) but
        // still credits level-quest progress. When the foil is the buy that completes the
        // primary, it credits the reward, advances the mint streak (the recorder is per-level
        // idempotent), and unlocks the foil secondary. streakSnapshot is the reward streak
        // captured post-primary, pre-floor — the foil-EV score basis frozen into the record.
        // levelQuestPrice keys the level quest at the routed-next level: the level quest a jackpot-
        // phase foil feeds is level + 1's, so its MINT_ETH target must price at level + 1 — pricing it
        // at the current level under-targets and over-grants the reward. Mirrors the mint path; in the
        // purchase phase priceWei already equals priceForLevel(level + 1) so it stays the basis.
        uint256 levelQuestPrice = jackpotPhaseFlag
            ? PriceLookupLib.priceForLevel(level + 1)
            : priceWei;
        (uint256 reward, uint8 qType, bool questCompleted, uint32 streakSnapshot) = quests
            .handleFoilPurchase(buyer, cost, 0, 0, priceWei, levelQuestPrice);
        if (questCompleted) {
            kickback += reward;
            // questType 1 == MINT_ETH (the daily primary), matching the ticket leg's gate.
            if (qType == 1) {
                _recordMintStreakForLevel(buyer, lvl);
            }
        }

        // Coin-presale-box credit accrual: while the box presale is open, the foil premium
        // earns 25% spendable box credit on its gross cost, exactly as the ticket/lootbox
        // spend and the pass buys do, independent of the funding mix.
        if (!presaleOver) {
            presaleBoxCredit[buyer] += cost / 4;
        }

        // Recycle bonus: spending at least three whole tickets' worth of claimable on the
        // foil leg earns 10% of that claimable spend back as FLIP, exactly as a recycled
        // ticket buy does. The afking-drawn portion is own principal, not recycled winnings,
        // so it stays out of the basis.
        if (claimableUsed >= priceWei * 3) {
            kickback += (claimableUsed * PRICE_COIN_UNIT * 10) / (priceWei * 100);
        }

        if (kickback != 0) coinflip.creditFlip(buyer, kickback);

        // Boost freeze off the buyer's post-action activity score (units + the streak the
        // primary just advanced are reflected via streakSnapshot). Mirror the mint path's
        // unified-streak swap: a live afking sub's reward streak lives on the Sub side (funded
        // days + in-run secondaries), not the decayed manual snapshot, so use the afking-live
        // value when a run is active — the same basis the mint path's cachedScore uses for the
        // lootbox EV. The raw score is also frozen into the record and reused as the claim
        // spin's RTP input, so the spin's RTP is fixed at buy (the match resolves later, against the future resolveDay word).
        (bool afkLive, uint32 afkStreak) = _liveAfkingStreak(buyer);
        uint256 score = _playerActivityScore(buyer, afkLive ? afkStreak : streakSnapshot);
        uint16 multBps = uint16(ActivityCurveLib.foilBoostBps(score));

        // The normal ticket swap freezes this pack before the cohort's request.
        // Lines and eligibility are stamped later, when that cohort materializes.
        foilRecord[lvl & 3][buyer] =
            (uint256(lvl) << _FOIL_LEVEL_SHIFT) |
            (uint256(multBps) << _FOIL_MULT_SHIFT) |
            (uint256(uint16(score)) << _FOIL_SCORE_SHIFT);

        uint80 ownerBits = _registerEntryOwner(buyer, lvl);
        if (ownerBits == 0) revert E();
        foilQueue[_foilWriteKey()].push(
            (uint256(ownerBits >> OWNER_IDX_SHIFT) << 192) | (uint256(lvl) << 160) | uint256(uint160(buyer))
        );

        emit FoilPackBought(buyer, lvl, multBps, cost);
    }

    // =========================================================================
    // Claim
    // =========================================================================

    /// @notice Claim a foil ticket's match against a day's draw (permissionless).
    /// @dev Delegatecall-only (see buyFoilPack). Anyone may resolve any player's
    ///      claim — all value credits to `player` (the pack owner), never the caller,
    ///      and the double-claim marker is set before any payout, so a tuple pays at
    ///      most once regardless of who triggers it. The eligible cycle level is read
    ///      from the day's sealed draw, not passed in. Reverts if the tuple is not a
    ///      claimable win (the batch variant skips instead). Matches expire after the
    ///      draw day and following day; terminal settlement also closes this entrance.
    /// @param player Pack owner the win credits to.
    /// @param day The draw day to claim against.
    /// @param ticketIndex Which of the pack's four tickets to claim (0-3).
    function claimFoilMatch(
        address player,
        uint256 day,
        uint256 ticketIndex
    ) external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        // Closed from the liveness trigger on. The ETH lane recirculates its over-cap
        // remainder into a lootbox, which queues ticket entries; during the terminal
        // drain both the drain entropy that assigns those entries' traits and the
        // terminal word that picks the winning traits are already public, so a holder
        // of several unclaimed tuples could settle only the one that lands winners.
        // The pack's own entries are unaffected — the foil drain still materializes
        // them into the terminal cohort. The batch variant self-calls this entrypoint
        // under try/catch, so it inherits the gate and skips instead of reverting.
        if (_livenessTriggered()) revert GameOver();
        if (!_tryClaimFoilMatch(player, day, ticketIndex)) revert NoClaimableMatch();
    }

    /// @notice Claim a foil pack's gold: the ladder on its total gold count, plus a
    ///         kicker when one whole ticket came out all gold.
    /// @dev Delegatecall-only (see buyFoilPack). The pack's four lines are the ones the
    ///      drain filed into the jackpot buckets and stored in the pack record. Gold
    ///      claims use those lines without any daily RNG lookup. They remain available
    ///      on the generation day and the following day; the grand still pays in the drain.
    ///
    ///      Claimable from three golds up to one all-gold ticket (see _settleGoldenTicket
    ///      for the rungs). TWO all-gold tickets are not claimable here at all: that pack
    ///      took the grand at the drain, which pushed it without waiting to be claimed
    ///      (see _pushFoilGrand). Only the FLIP legs are left to pull, and neither of
    ///      them reads a pool — which is why this claim needs no RNG-lock guard either.
    ///
    ///      Anyone may settle any player's pack — every rung credits `player`, never the
    ///      caller, and the marker is set before the payout (CEI), so a pack pays at
    ///      most once regardless of who triggers it.
    ///
    ///      Closed from the liveness trigger on, matching the match claim and the drain's
    ///      own grand push: past that point the terminal path is drawing down the pools,
    ///      and a claim held back to straddle it would settle against a pool the terminal
    ///      jackpot has already committed.
    /// @param player Pack owner the win credits to.
    /// @param lvl The pack's cycle level.
    function claimGoldenTicket(address player, uint24 lvl) external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if (_livenessTriggered()) revert GameOver();

        (bool present, , , ) = _foilRecordFor(
            player,
            lvl
        );
        if (!present) revert NoGoldenTicket();

        uint256 record = _foilRecordWord(player, lvl);
        if (record & _FOIL_READY == 0 || !_foilGoldClaimOpen(uint24(record >> _FOIL_GENERATED_DAY_SHIFT))) {
            revert NoGoldenTicket();
        }

        // Already settled — including by the drain, which burns this exact marker when
        // it pushes a pack's grand.
        if (record & _FOIL_GOLD_CLAIMED != 0) revert NoGoldenTicket();

        (uint8 golds, uint8 allGold) = _packGold(
            _foilStoredLines(player, lvl)
        );
        // Three golds anywhere in the sixteen is the floor, and it subsumes every
        // richer shape: an all-gold ticket is four golds by construction.
        if (golds < 3) revert NoGoldenTicket();
        // Belt to the marker's braces: two all-gold tickets took the grand at the
        // drain, and the grand supersedes the FLIP legs rather than stacking. The
        // marker above already closes the settled case; this closes the shape itself,
        // so a pack that somehow reached here unmarked still cannot mint the ladder's
        // top rung on top of a pool-sized grand.
        if (allGold >= 2) revert NoGoldenTicket();

        // Mark before any payout (CEI).
        foilRecord[lvl & 3][player] = record | _FOIL_GOLD_CLAIMED;
        _settleGoldenTicket(player, lvl, golds, allGold);
    }

    /// @notice Permissionlessly resolve a batch of foil match claims.
    /// @dev Each claim runs as an external self-call wrapped in try/catch, so ANY single
    ///      claim revert — a non-claimable tuple (out of range, no draw, no record,
    ///      ineligible day, already claimed, no match) OR a payout spin that reverts (e.g. an
    ///      ETH tier too large for the frozen pool's pending buffer) — rolls back ONLY
    ///      that claim (its marker, whale pass, and spin together) and the sweep moves
    ///      on. One stale or unpayable tuple past the opener can never poison the batch.
    ///      The tuple at index 0 is the exception: a revert there reverts the whole call
    ///      with StaleBatch(), because an already-swept list fails there first and the
    ///      cheap revert is what a wallet's pre-flight simulation shows a second sender.
    ///      Put a tuple expected to settle first. Each settled win credits its own
    ///      `player`. The arrays are parallel: claim i is (players[i], drawDays[i],
    ///      ticketIndexes[i]).
    /// @param players Pack owners the wins credit to.
    /// @param drawDays Draw days to claim against.
    /// @param ticketIndexes Which pack ticket (0-3) per claim.
    function claimFoilMatchMany(
        address[] calldata players,
        uint24[] calldata drawDays,
        uint8[] calldata ticketIndexes
    ) external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        uint256 n = players.length;
        if (drawDays.length != n || ticketIndexes.length != n) revert LengthMismatch();

        uint256 settled;
        for (uint256 i; i < n; ) {
            // External self-call: address(this) is GAME under delegatecall, so this
            // dispatches through the facade stub back into this module in the Game's
            // storage context. try/catch isolates each claim — a revert (non-claimable
            // OR an unpayable payout spin, e.g. an ETH tier the frozen pool can't cover)
            // rolls back ONLY that tuple's effects and the sweep continues.
            try
                this.claimFoilMatch(
                    players[i],
                    drawDays[i],
                    ticketIndexes[i]
                )
            {
                unchecked {
                    ++settled;
                }
            } catch {
                // The opening tuple doubles as the spent-list probe. One tuple list is
                // handed to many senders and the first to land settles every tuple in
                // it, so a dead opener means the list is already swept. Reverting lets a
                // wallet's pre-flight simulation warn every later sender: a sweep that
                // settles nothing would otherwise SUCCEED, drawing no warning and
                // charging the full walk. Costs one tuple of gas instead of n.
                if (i == 0) revert StaleBatch();
                // Non-claimable or payout-reverting tuple past the opener: skip.
            }
            unchecked {
                ++i;
            }
        }

        // Keeper bounty: a small FLIP credit per claim actually settled, paid to the
        // caller during a live game (the flip credit is worthless post-gameover).
        // Skipped and non-winning tuples settle nothing and earn nothing, so a padded
        // batch cannot farm the bounty. The ETH-value tracks the per-claim settle gas
        // at the reference price (FLIP per ETH = PRICE_COIN_UNIT / mintPrice), so the
        // credit holds its gas-reimbursement value across the price curve.
        if (!gameOver && settled != 0) {
            coinflip.creditFlip(
                msg.sender,
                (settled * FOIL_CLAIM_BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) /
                    PriceLookupLib.priceForLevel(
                        jackpotPhaseFlag ? level : level + 1
                    )
            );
        }
    }

    /// @dev Resolve one foil match claim. Returns false (no state change) on any
    ///      non-claimable condition so the batch can skip it; the single entry point
    ///      turns false into a revert. A real win sets the double-claim marker before
    ///      the payout (CEI) and pays the isolated 40/40/20 spin.
    function _tryClaimFoilMatch(
        address player,
        uint256 day,
        uint256 ticketIndex
    ) private returns (bool) {
        if (ticketIndex >= 4) return false;
        // Expire before reading reusable slots or replacing any claim bitmap lane.
        uint256 today = _simulatedDayIndex();
        if (day == 0 || day > today || today - day > 1) return false;

        // One retained record supplies the exact board, level and payout entropy.
        // The full day tag rejects stale parity aliases.
        uint256 draw = _foilDrawWord(day);
        if (draw & _FOIL_DRAW_SEEDED == 0) return false;
        uint32 winSet = uint32(draw);
        uint24 L = uint24(draw >> 64);

        // The pack's first eligible draw and buy-time activity score (spin RTP).
        // Pending packs have no generated lines and cannot claim.
        uint256 record = _foilRecordWord(player, L);
        if (record & _FOIL_READY == 0) return false;
        uint24 resolveDay = uint24(record);
        uint16 activityScore = uint16(record >> _FOIL_SCORE_SHIFT);

        // The first eligible draw is pinned when the cohort materializes.
        // A draw already sealed that day cannot be claimed retroactively.
        if (day < resolveDay) return false;

        // A sealed day has one level. Exact-day bitmap lanes separate all four tickets.
        if (_foilMatchAlreadyClaimed(player, uint24(day), ticketIndex)) return false;

        uint32 sel = uint32(record >> (_FOIL_LINES_SHIFT + ticketIndex * 32));

        // Graded score vs the day's winning set: per quadrant a symbol
        // match scores +1, and if the color of that same quadrant also matches it
        // scores +2; a symbol miss scores 0 (color only counts once the symbol is hit).
        // Score T in {0..8}. The foil's boosted colors, daily hero and gold-six
        // survival/redistribution affect match probabilities; the face schedule is
        // fixed and does not compensate for those differences.
        uint256 score;
        for (uint256 q; q < 4; ++q) {
            uint8 selByte = uint8(sel >> (8 * q));
            uint8 winByte = uint8(winSet >> (8 * q));
            // Symbol = bits 2-0; color = bits 5-3 (quadrant bits 7-6 ignored).
            if ((selByte & 7) == (winByte & 7)) {
                score += ((selByte >> 3) & 7) == ((winByte >> 3) & 7) ? 2 : 1;
            }
        }
        if (score < 4) return false;

        // Mark before any payout (CEI).
        _markFoilMatchClaimed(player, uint24(day), ticketIndex);

        uint8 tier = uint8(score); // 4..8
        uint256 faces;
        if (score == 4) {
            faces = FOIL_FACES_T4;
        } else if (score == 5) {
            faces = FOIL_FACES_T5;
        } else if (score == 6) {
            faces = FOIL_FACES_T6;
        } else if (score == 7) {
            faces = FOIL_FACES_T7;
        } else {
            faces = FOIL_FACES_T8; // score == 8 (all four full doubles)
        }

        emit FoilMatchClaimed(player, uint24(day), ticketIndex, tier, faces);

        _payFoilTier(player, day, ticketIndex, L, sel, tier, faces, activityScore, uint128(draw >> _FOIL_DRAW_SEED_SHIFT));
        return true;
    }

    /// @dev Generate four lines from the committed normal pack cohort's entropy.
    ///      The drain stores these same sixteen traits in the pack record and buckets;
    ///      later claims read the stored lines. Each uint32 holds four quadrant bytes.
    function _deriveFoilLines(
        address buyer,
        uint24 lvl,
        uint256 entropy,
        uint16 multBps,
        bool goldSixTaken
    ) private view returns (uint32[4] memory lines) {
        uint256[7] memory cut = DegenerusTraitUtils.foilCuts(multBps);
        for (uint256 i; i < 4; ++i) {
            uint256 seed = uint256(
                keccak256(abi.encode(entropy, buyer, lvl, FOIL_SEED_TAG, i))
            );
            uint8 tA = DegenerusTraitUtils.foilTrait(uint64(seed), cut);
            uint8 tB = DegenerusTraitUtils.foilTrait(uint64(seed >> 64), cut) | 64;
            uint8 tC = DegenerusTraitUtils.foilTrait(uint64(seed >> 128), cut) | 128;
            uint8 tD = DegenerusTraitUtils.foilTrait(uint64(seed >> 192), cut) | 192;
            if (tD == GoldSixLib.TRAIT) {
                // Read live cap state at most once, and only when this pack needs it.
                // Retired levels enter with goldSixTaken=true and never read a stale bucket.
                if (goldSixTaken || _goldSixTaken(lvl)) tD = GoldSixLib.replacement(seed);
                goldSixTaken = true;
            }
            lines[i] =
                uint32(tA) |
                (uint32(tB) << 8) |
                (uint32(tC) << 16) |
                (uint32(tD) << 24);
        }
    }

    // =========================================================================
    // Isolated payout
    // =========================================================================

    /// @dev Pay one matched tier as a single Degenerette box-spin. The tier's
    ///      magnitude (faces) is the stake; the currency is rolled 40/40/20
    ///      (ETH/FLIP/WWXRP) and the spin is seeded — both off the historical draw's
    ///      packed payout seed. Spins use the buyer's activity score frozen at buy, and regenerate
    ///      all colors, so the foil's boosted gold mix does not tilt spin EV. FLIP stakes split into
    ///      thirds across three spins under one survival flip; ETH and WWXRP are single
    ///      spins. The T=8 tier (all four full doubles) also grants a half whale pass. All
    ///      effects run after the double-claim marker is set (CEI). The matched signature `sel` is the
    ///      source of one seed-selected hero symbol; the remaining ticket is generated.
    ///
    ///      Snap valve: foil payouts never carry the exponent. The buy pays 2^s
    ///      with the normal ticket price, but every award uses the unshifted face.
    ///      Claims can follow purchases by many draws; no live snap read changes them.
    function _payFoilTier(
        address player,
        uint256 day,
        uint256 ticketIndex,
        uint24 L,
        uint32 sel,
        uint8 tier,
        uint256 faces,
        uint16 activityScore,
        uint256 entropy
    ) private {
        if (tier == 8) {
            whalePassClaims[player] += 1;
        }

        // Currency and spin use disjoint lanes of the seed saved with this draw.
        // Zero is a valid seed; the caller authenticated the record's presence flag.
        uint256 c = uint256(
            keccak256(abi.encode(entropy, day, ticketIndex, FOIL_CCY_TAG))
        ) % 100;
        uint256 seed = uint256(
            keccak256(abi.encode(entropy, day, ticketIndex, FOIL_SPIN_TAG))
        );

        // activityScore is the buyer's score frozen at buy (passed in), not a live read:
        // the spin RNG and activity-based RTP are fixed. Realized ETH/recirculation
        // still depends on the live pool; an unclaimed match is not reserved ETH.
        // Only a symbol carries into the award spin; all colors are rerolled,
        // so the foil's boosted color mix cannot change the spin EV.

        uint8 quadrant = uint8(seed % (DEGENERETTE_HERO_COUNT / 8));
        uint8 symbol = uint8((sel >> (quadrant * 8)) & 7) | (quadrant << 3);
        if (c < 40) {
            // ETH (40%): one pool-capped spin; over-cap recircs to the lootbox.
            _foilSpin(
                IDegenerusGameDegeneretteModule.resolveEthSpinFromBox.selector,
                player,
                faces * PriceLookupLib.priceForLevel(L),
                activityScore,
                seed,
                symbol
            );
        } else if (c < 80) {
            // FLIP (40%): the magnitude splits into thirds across three spins under
            // one survival flip; free mint, no solvency impact.
            _foilSpin(
                IDegenerusGameDegeneretteModule.resolveFlipSpinsFromBox.selector,
                player,
                faces * FLIP_FACE_AMOUNT,
                activityScore,
                seed,
                symbol
            );
        } else {
            // WWXRP (20%): one spin; free mint, no solvency impact.
            _foilSpin(
                IDegenerusGameDegeneretteModule.resolveWwxrpSpinFromBox.selector,
                player,
                faces * WWXRP_FACE_AMOUNT,
                activityScore,
                seed,
                symbol
            );
        }
    }

    /// @dev Delegatecall one of the Degenerette box-spin resolvers in the Game's
    ///      storage context. The three resolvers share a single (player, stake,
    ///      activityScore, seed, symbol) shape, so one helper covers every
    ///      currency. Only the chosen hero symbol reaches the spin resolver.
    function _foilSpin(
        bytes4 selector,
        address player,
        uint256 stake,
        uint16 activityScore,
        uint256 seed,
        uint8 symbol
    ) private {
        (bool ok, bytes memory data) = ContractAddresses.GAME_DEGENERETTE_MODULE.delegatecall(
            abi.encodeWithSelector(
                selector,
                player,
                stake,
                activityScore,
                seed,
                symbol
            )
        );
        if (!ok) revert EmptyRevert();
        // The FLIP and WWXRP box-spin resolvers RETURN their payout for the caller to credit
        // (the box sweep pools them into its entry accumulator); a foil tier is a single spin,
        // so it credits inline. The ETH resolver still settles its own payout and returns
        // nothing — crediting its (empty) return here would be a decode revert, so it is
        // routed by selector.
        if (selector == IDegenerusGameDegeneretteModule.resolveFlipSpinsFromBox.selector) {
            uint256 flipOut = abi.decode(data, (uint256));
            if (flipOut != 0) coinflip.creditFlip(player, flipOut);
        } else if (
            selector == IDegenerusGameDegeneretteModule.resolveWwxrpSpinFromBox.selector
        ) {
            uint256 wwxrpOut = abi.decode(data, (uint256));
            if (wwxrpOut != 0) IFoilWwxrp(ContractAddresses.WWXRP).mintPrize(player, wwxrpOut);
        }
    }

    // =========================================================================
    // Queue drain (lives here so the mint module keeps only the normal-ticket path
    // under the EIP-170 limit)
    // =========================================================================

    // -------------------------------------------------------------------------
    // Seated Round Drain (hosted here for the mint module)
    // -------------------------------------------------------------------------



    /// @dev Compatibility selectors; all ordinary ticket generation lives in Ticket.
    function generateTraitRun(uint256 identity, uint32 startIndex, uint32 count, uint256 entropy, uint256 ownerIdx)
        external returns (uint256 writes)
    {
        return abi.decode(_ticketWorkerCall(abi.encodeWithSelector(
            IDegenerusGameTicketModule.generateTraitRun.selector, identity, startIndex, count, entropy, ownerIdx
        )), (uint256));
    }

    function drainRounds(uint24 rk, uint24 lvl, uint32 room, uint256 idx, uint256 total, uint256 entropy, uint8 shift)
        external returns (uint256 nextIdx, uint32 used)
    {
        return abi.decode(_ticketWorkerCall(abi.encodeWithSelector(
            IDegenerusGameTicketModule.drainRounds.selector, rk, lvl, room, idx, total, entropy, shift
        )), (uint256, uint32));
    }

    function _ticketWorkerCall(bytes memory callData) private returns (bytes memory data) {
        bool ok;
        (ok, data) = ContractAddresses.GAME_TICKET_MODULE.delegatecall(callData);
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
    }

    /// @dev Payable delegate worker: records the presale leg in the reusable cohort.
    function recordPresaleBox(address buyer, uint48 index, uint256 word) external payable {
        if (presaleBoxEth[index & 1][buyer] != 0) revert E();
        presaleBoxEth[index & 1][buyer] = word;
        boxPlayers[index & 1].push(buyer);
    }

    /// @notice Prepare a ticket level with constant work, deferring unsafe buffer takeover.
    function prepareTicketLevel(uint24 lvl) external payable returns (bool) {
        return _prepareTicketLevel(lvl);
    }

    /// @notice Drain the frozen foil read cohort on the leftover write budget.
    /// @dev Delegatecall-only entry, invoked by the mint module's processTicketBatch
    ///      once the normal queue is drained (and only when _foilDrainPending). Runs in
    ///      the Game's storage context, so it reads/writes the same
    ///      foilQueue/foilGenerationDay/foilCursor/foilRecord and the lvlTraitEntry
    ///      buckets the jackpot samples.
    /// @return done True iff the committed foil read cohort is exhausted.
    /// @return drained True if this call resolved at least one foil buyer.
    function processFoilDrain(uint32) external returns (bool done, bool drained) {
        MineFlipGas.Result memory result = _runFoilWork(MineFlipGas.available());
        return (result.done, result.progressed);
    }

    function runFoilWork(uint256 allowance) external returns (MineFlipGas.Result memory) {
        return _runFoilWork(allowance);
    }

    function _runFoilWork(uint256 allowance) private returns (MineFlipGas.Result memory result) {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        MineFlipGas.Meter memory meter = MineFlipGas.start(allowance);
        uint256[] storage packs = foilQueue[_foilReadKey()];
        uint256 cursor = foilCursor;
        uint256 total = packs.length;
        uint256 entropy = _lootboxWord(_rngReadBuffer());
        bool terminal = gameOver || _lrRead(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK) != 0
            || _lrRead(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK) != 0;
        uint32[256] memory counts;
        // Four lines contribute at most sixteen distinct trait bytes per pack.
        uint8[16] memory touchedTraits;
        // Includes a cold pack, all bucket flushes, and the possible grand push.
        while (entropy != 0 && cursor < total && MineFlipGas.canRun(meter, GasBounds.FOIL_PACK, 100_000)) {
            uint24 packLevel = uint24(packs[cursor] >> 160);
            if (!_ticketLevelRetired(packLevel) && !(terminal && packLevel != _gameOverTicketLevel(level))
                && !_prepareTicketLevelAfterFoil(packLevel)) break;
            if (foilGenerationDay == 0) {
                uint24 day = _simulatedDayIndex();
                foilGenerationDay = day;
                (bool drawn,,) = _foilDrawFor(day);
                foilFirstDrawDay = drawn ? day + 1 : day;
            }
            _resolveFoilBuyer(packs[cursor], entropy, terminal, counts, touchedTraits);
            result.progressed = true;
            result.rewardBasis += FOIL_PACK_ENTRIES;
            ++cursor;
        }
        result.done = cursor >= total;
        if (result.done) {
            assembly ("memory-safe") { sstore(packs.slot, 0) }
            foilCursor = 0;
        } else if (cursor != foilCursor) foilCursor = uint32(cursor);
        MineFlipGas.finish(meter);
    }

    /// @dev Generate and store the four boosted lines from the committed read word,
    ///      then file their sixteen traits into the pack's eligible level. The first
    ///      eligible draw is pinned for the cohort; each pack's gold deadline starts
    ///      on its actual materialization day. Terminal work only files the payout level.
    ///
    ///      Counts the pack's gold on the way past. The lines are already in memory and
    ///      already unpacked below, so reading how much gold they hold is opcode work on
    ///      data this function has in hand — a fraction of a percent of the sixteen
    ///      entry writes it is here to do. Only the grand acts on it: the ladder and its
    ///      kicker stay a pull, off this budgeted path.
    /// @param packedLvlBuyer Packed queue entry: buyer address, cycle level, and registry position.
    /// @param entropy Committed normal cohort word driving the four boosted lines.
    /// @param terminal Whether liveness has triggered; suppresses the grand push, so the
    ///        terminal drain never carves a pool the terminal jackpot is settling from.
    /// @param counts Shared scratch: per-trait occurrence counter for this level, re-zeroed
    ///        before return.
    /// @param touchedTraits Shared scratch: trait IDs touched this call, for the batch write.
    /// @return grandPaid True when this pack pushed the grand, so the caller can charge
    ///         its writes against the batch budget.
    /// @return units Four fixed bookkeeping units plus three per zero-valued slot write
    ///         and one per nonzero slot write. Includes bitmap initialization, the header
    ///         and completed data words; stale headers are priced before resetting their value.
    function _resolveFoilBuyer(
        uint256 packedLvlBuyer,
        uint256 entropy,
        bool terminal,
        uint32[256] memory counts,
        uint8[16] memory touchedTraits
    ) private returns (bool grandPaid, uint32 units) {
        address buyer = address(uint160(packedLvlBuyer));
        uint24 lvl = uint24(packedLvlBuyer >> 160);
        // Only the terminal payout level needs generated traits after the ending latches.
        // Consuming unrelated packs must not reassign the frozen terminal payout buffer.
        if (terminal && lvl != _gameOverTicketLevel(level)) return (false, 3);
        // Retired levels have no live inventory to authenticate an unclaimed slot.
        // Their delayed claim records redirect every gold six, preserving uniqueness.
        bool retired = _ticketLevelRetired(lvl);
        uint32[4] memory lines = _deriveFoilLines(
            buyer,
            lvl,
            entropy,
            _foilMultFor(buyer, lvl),
            retired
        );

        uint256 record = _foilRecordWord(buyer, lvl);
        record |= uint256(foilFirstDrawDay) | (uint256(_simulatedDayIndex()) << _FOIL_GENERATED_DAY_SHIFT) | _FOIL_READY;
        for (uint256 i; i < 4; ++i) record |= uint256(lines[i]) << (_FOIL_LINES_SHIFT + i * 32);
        foilRecord[lvl & 3][buyer] = record;
        units = 4; // record, cursor and stored lines
        // Tomorrow's word can land after a turbo transition retired this pack's
        // inventory. Claims still use its retained record and daily word; never
        // reassign a newer buffer or let this old generation queue block progress.
        if (!retired) {
            uint16 touchedLen;
            for (uint256 i; i < 4; ++i) {
                uint32 line = lines[i];
                uint8 tA = uint8(line);
                uint8 tB = uint8(line >> 8);
                uint8 tC = uint8(line >> 16);
                uint8 tD = uint8(line >> 24);
                if (counts[tA]++ == 0) touchedTraits[touchedLen++] = tA;
                if (counts[tB]++ == 0) touchedTraits[touchedLen++] = tB;
                if (counts[tC]++ == 0) touchedTraits[touchedLen++] = tC;
                if (counts[tD]++ == 0) touchedTraits[touchedLen++] = tD;
            }

            // Batch-write the sixteen entries into lvlTraitEntry[lvl][traitId] as packed
            // lanes naming the buyer's registry position, one length update per distinct
            // trait. Mirrors the mint module's batch writer; re-zeroes the shared scratch so
            // the next buyer starts clean.
            uint256 levelSlot = _traitBufferBase(lvl);
            // Every queue writer registers a checked nonzero stable ID.
            uint256 ownerIdx;
            unchecked { ownerIdx = (packedLvlBuyer >> 192) - 1; }
            for (uint16 u; u < touchedLen; ) {
                uint8 traitId = touchedTraits[u];
                uint32 occurrences = counts[traitId];
                counts[traitId] = 0;
                (uint256 f, uint256 d) = _bucketAppendRun(levelSlot, traitId, ownerIdx, occurrences, lvl);
                unchecked {
                    units += uint32(f * 3 + d);
                    ++u;
                }
            }

            uint256 baseKey = (uint256(TicketEntropy.FOIL) << 248) | (uint256(lvl) << 224) |
                (uint256(uint160(buyer)) << 32);
            emit TraitsGenerated(buyer, baseKey, FOIL_PACK_ENTRIES);

        }

        // Two or more all-gold tickets: push the grand now rather than wait to be
        // claimed. Runs AFTER the pack's own entries are filed, so the sixteen it just
        // bought are in the buckets the draw this drain gates will read — the pack wins
        // the grand and still plays the board it paid for.
        if (!terminal) {
            (uint8 golds, uint8 allGold) = _packGold(lines);
            if (allGold >= 2) {
                _pushFoilGrand(buyer, lvl, golds, allGold);
                grandPaid = true;
            }
        }
    }

    /// @dev Read a pack's gold two ways in one pass over the four lines the drain
    ///      filed: the total gold quadrants (the ladder's rung) and how many whole
    ///      tickets came out all gold (the kicker and the grand). Each quadrant byte is
    ///      [QQ][CCC][SSS], so the color is bits 5-3 and gold is color 7. Pure and
    ///      re-derivable — the claim recomputes the same lines the drain filed, so
    ///      nothing about the pack's gold has to be stored.
    /// @param lines The pack's four four-quadrant lines.
    /// @return golds Total gold quadrants across the pack (0..16).
    /// @return allGoldTickets How many of the four lines are all gold (0..4).
    function _packGold(
        uint32[4] memory lines
    ) internal pure returns (uint8 golds, uint8 allGoldTickets) {
        for (uint256 i; i < 4; ++i) {
            uint32 line = lines[i];
            uint8 inLine;
            for (uint256 q; q < 4; ++q) {
                if (((uint8(line >> (8 * q)) >> 3) & 7) == 7) {
                    unchecked {
                        ++inLine;
                    }
                }
            }
            unchecked {
                golds += inLine;
                if (inLine == 4) ++allGoldTickets;
            }
        }
    }

    /// @dev The gold ladder's FLIP for a pack's total gold count. Only reached with
    ///      `golds >= 3` (the claim's floor), so the fallthrough is the 3 rung; 8 caps
    ///      it, since past there the rarity outruns any table worth writing.
    function _goldLadderFlip(uint8 golds) internal pure returns (uint256) {
        if (golds >= 8) return GOLD_LADDER_8;
        if (golds == 7) return GOLD_LADDER_7;
        if (golds == 6) return GOLD_LADDER_6;
        if (golds == 5) return GOLD_LADDER_5;
        if (golds == 4) return GOLD_LADDER_4;
        return GOLD_LADDER_3;
    }

    /// @dev Pay the pull's half of the foil gold route: the ladder rung for the pack's
    ///      total gold count, plus GOLDEN_TICKET_FLIP when exactly ONE whole ticket came
    ///      out all gold (which pays for the shape, not the count).
    ///
    ///      Two or more all-gold tickets never arrive here — the drain pushed their
    ///      grand and burned the pack's claim marker on the way. The grand supersedes
    ///      rather than stacks, the same way the board route pays one rung: a pack that
    ///      reached it has already been paid the top of the whole structure, so adding
    ///      the ladder's own top rung would only blur the headline.
    ///
    ///      Neither leg carries the snap exponent (see _payFoilTier: no foil payout
    ///      does), and neither reads a pool — so nothing here is sized off state a
    ///      pending draw is about to move, and the claim needs no RNG-lock guard.
    ///
    ///      Internal, not private, so a test exposer can drive one rung at a time:
    ///      every (golds, allGold) shape is reachable in production, but each needs its
    ///      own brute-forced (buyer, entropy) vector to reach through the live claim.
    ///      No production contract derives from this module, so the reachable surface is
    ///      unchanged.
    /// @param player The pack's buyer, who every rung credits.
    /// @param lvl The pack's cycle level.
    /// @param golds The pack's total gold quadrants (3..7, or 8+ scattered across at
    ///        most one whole ticket).
    /// @param allGold How many of the pack's four tickets came out all gold (0 or 1).
    function _settleGoldenTicket(
        address player,
        uint24 lvl,
        uint8 golds,
        uint8 allGold
    ) internal {
        uint256 flipCredit = _goldLadderFlip(golds);
        if (allGold == 1) flipCredit += GOLDEN_TICKET_FLIP;
        coinflip.creditFlip(player, flipCredit);
        emit GoldenTicketFoil(player, lvl, golds, allGold, flipCredit);
    }

    /// @dev Push the golden-ticket grand for a pack that drained holding two or more
    ///      all-gold tickets. Delegatecalls the jackpot module's single grand definition
    ///      in the Game's storage context, so the foil route and the armed board route
    ///      pay the identical rung off one body of code — the amounts cannot drift. It
    ///      neither arms nor consumes the armed board slot: a pending arm still resolves
    ///      on its own next draw.
    ///
    ///      NO RNG-lock guard, deliberately. This runs inside advanceGame, which is a
    ///      deterministic protocol function with no player discretion, and the drain
    ///      strictly precedes the draw it feeds — the readiness gate holds rngGate until
    ///      _foilDrainPending clears, so the futurePrizePool debit always lands before
    ///      any pool math that reads it. That is exactly how the armed board route's own
    ///      grand already settles from payDailyJackpot. Nothing is double-committed: the
    ///      later draw simply reads the pool this call left behind.
    ///
    ///      Internal, not private, only so a test exposer can drive it: a pack reaches
    ///      two all-gold tickets once in 7.1 billion, far past what a search over
    ///      buyer/entropy can construct. Same precedent as the jackpot module's
    ///      _pickSoloQuadrant, and no production contract derives from this module, so
    ///      the reachable surface is unchanged.
    /// @param player The pack's buyer, who the grand credits.
    /// @param lvl The pack's cycle level.
    /// @param golds The pack's total gold quadrants — 8 to 16 (at least two all-gold tickets,
    ///        the other tickets holding 0-3 golds each).
    /// @param allGold How many of the pack's four tickets came out all gold (2..4).
    function _pushFoilGrand(
        address player,
        uint24 lvl,
        uint8 golds,
        uint8 allGold
    ) internal {
        // Burn the pack's claim marker before paying (CEI), the SAME one the pull
        // checks. The grand supersedes the FLIP legs rather than stacking, so a pack
        // paid here must not go on to pull the ladder's top rung as well — eight golds
        // is exactly what two all-gold tickets are, so an unmarked pack would qualify
        // for 7.5M FLIP on top of a pool-sized grand. The marker closes that outright
        // rather than leaving it to the pull's re-derivation.
        foilRecord[lvl & 3][player] |= _FOIL_GOLD_CLAIMED;
        (bool ok, bytes memory reason) = ContractAddresses.GAME_JACKPOT_MODULE.delegatecall(
            abi.encodeWithSelector(
                IDegenerusGameJackpotModule.payGoldenTicketGrand.selector,
                player,
                lvl,
                golds
            )
        );
        if (!ok) {
            assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
        }
        // flipCredit 0: the grand's own legs are stamped by GoldenTicketWin.
        emit GoldenTicketFoil(player, lvl, golds, allGold, 0);
    }

}
