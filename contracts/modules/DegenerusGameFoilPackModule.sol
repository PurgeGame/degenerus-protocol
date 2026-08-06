// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {MintPaymentKind} from "../interfaces/IDegenerusGame.sol";
import {
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
 *         per-(day, ticket, drawKind) match claim that reads the day's sealed
 *         winning sets and pays an isolated 40/40/20 spin, and a per-pack gold route
 *         on how much gold the pack's own sixteen quadrants came out holding — pulled
 *         as a claim, except the grand, which the drain pushes where it is decided.
 * @dev All storage reads/writes operate on the inherited DegenerusGameStorage.
 *      The buy keys on the active ticket level (the cycle the pack bets into), so
 *      a pack and the draws it bets against share one cycle key. The claim never
 *      re-derives the winning sets — it reads dailyFoilDraw[day], which the
 *      jackpot sealed, so the foil numbers equal the coin jackpot's.
 */
contract DegenerusGameFoilPackModule is
    DegenerusGamePayoutUtils,
    DegenerusGameMintStreakUtils
{
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    // error E() — inherited from DegenerusGameStorage
    error FoilAlreadyBought(); // Buyer already holds a foil pack for this cycle level.
    error StaleAdvance(); // Simulated day is more than one day ahead of the processed daily index; multi-day stall detected.
    error NoClaimableMatch(); // The given (player, day, ticketIndex, drawKind) tuple does not resolve to a claimable foil match.
    error StaleBatch(); // The batch's opening tuple is not claimable: the list has already been swept.
    error NoGoldenTicket(); // No pack at that cycle, its lines have not resolved yet, it holds under three golds, or it is already claimed.

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
    // way (WWXRP, the third currency, is worthless). Calibrated to
    // E[faces/comparison] = 0.010972 (E[faces/pack/30d] = 2.633) — byte-identical EV to
    // the prior liveCount {2->7, 3->65, 4->1000} table, so the value-bearing ETH and
    // FLIP lanes (40% each) still each deliver ~1 ticket of value per pack over a
    // 30-day, 60-draw window. Score T (0..8) pays from T=4; T=8 (all four full doubles,
    // the old 4-of-4 moonshot) also grants a half whale pass.
    uint256 private constant FOIL_FACES_T4 = 2;
    uint256 private constant FOIL_FACES_T5 = 6;
    uint256 private constant FOIL_FACES_T6 = 35;
    uint256 private constant FOIL_FACES_T7 = 400;
    uint256 private constant FOIL_FACES_T8 = 10_000;

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

    /// @dev Domain tag for the golden-ticket claim's double-claim marker, which shares
    ///      the foilMatchClaimed map with the per-draw match markers. Those fold five
    ///      fields (player, level, day, drawKind, ticketIndex) against this key's three,
    ///      so the preimages differ in length as well as in this tag — the two claim
    ///      families can never mint the same marker.
    bytes32 private constant GOLDEN_TICKET_TAG = keccak256("foil-golden-ticket");

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
    /// @param drawKind 0 = main set, 1 = bonus set.
    /// @param tier The matched score T (4..8): the graded symbol/color axis match; T=8
    ///        is the moonshot (all four full doubles). Field name retained for the indexer.
    /// @param faces The face count paid for the score.
    event FoilMatchClaimed(
        address indexed player,
        uint24 indexed day,
        uint256 ticketIndex,
        uint8 drawKind,
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
    ///      ticket purchase: its own payment (75/25 pool), the 20/5 affiliate, the ten
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

        // The pack bets on its resolveDay daily draw, so it keys on the level that draw seals
        // at — the same level a ticket bought now resolves into, which the claim reads back
        // from dailyFoilDraw[day].level. _activeTicketLevel() is that level: the active ticket
        // level, except on the final jackpot day once the daily RNG is requested (where
        // _endPhase breaks before _unlockRng, so no further draw seals here and resolveDay =
        // day + 1 is the next cycle's first day, level + 1). Shared with the ticket queue and
        // the purchase quote so the cap, the record, the queue, and the charge all key alike.
        uint24 lvl = _activeTicketLevel();
        if (_foilBoughtThisLevel(buyer, lvl)) revert FoilAlreadyBought();

        // Forward-commit guard (multi-day stall only): the resolving daily word must be
        // unknowable at buy. In normal operation — caught up, or the brief pre-request
        // slice one day ahead — the resolving day's VRF is a fresh future request, so the
        // lines cannot be known. The one exception is a MULTI-day stall (the advance >= 2
        // days behind the wall): there the pending VRF word gap-backfills the unprocessed
        // days from an already-public word, so a buyer could grind addresses offline for
        // one whose derived lines win and buy it. Block foil until the advance catches up
        // (anyone can call it; it is keeper-incentivized). _simulatedDayIndex() is
        // timestamp-only, so this `day` is reused for resolveDay below.
        uint24 day = _simulatedDayIndex();
        if (day > dailyIdx + 1) revert StaleAdvance();

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

        // Affiliate, fresh 25% at levels 0-3 / 20% at 4+ and 5% recycle exactly like a
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

        // Resolve day = the next day whose daily word is genuinely future at buy.
        // Default tomorrow (day + 1): its word can't be requested until then. The lone
        // exception is the brief slice after the wall day rolls but before that day's RNG
        // was requested (!rngLockedFlag && dailyIdx < day) — today's word is still
        // unrequested, so resolve against today. The multi-day-stall guard above bounds
        // `day` to at most dailyIdx + 1 here, so neither choice can land on a day the
        // gap-backfill would fill from an already-public word.
        uint24 resolveDay = (!rngLockedFlag && dailyIdx < day) ? day : day + 1;

        // Freeze the record: resolveDay (>= 1), multBps (>= 20000), and the buy-time
        // activity score. The slot is non-zero, so its presence IS the one-per-cycle cap.
        // No signatures are stored — the drain and the claim re-derive the four match
        // lines from rngWordByDay[resolveDay] + multBps. The snap exponent is NOT
        // recorded: no foil payout scales with it (see _payFoilTier).
        foilRecord[lvl][buyer] =
            uint256(resolveDay) |
            (uint256(multBps) << _FOIL_MULT_SHIFT) |
            (uint256(uint16(score)) << _FOIL_SCORE_SHIFT);

        // Bucket the buyer by resolveDay (the coinflip-by-day analog), carrying the
        // cycle level so the day-keyed drain can file into the right trait buckets and
        // re-derive with the right key. resolveDay is provably future at buy (the
        // engine only requests RNG up to the current wall day), so the lines are
        // unsteerable. Raise the high-water mark, and skip the low-water cursor to this
        // bucket when the drain has caught up (or on the first ever buy) so a sparse
        // buy never makes the drain walk a long empty day range.
        foilBuyers[resolveDay].push(
            (uint256(lvl) << 160) | uint256(uint160(buyer))
        );
        uint24 prevLast = foilLastResolveDay;
        if (resolveDay > prevLast) foilLastResolveDay = resolveDay;
        if (foilDrainDay == 0 || foilDrainDay > prevLast) {
            foilDrainDay = resolveDay;
        }

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
    ///      claimable win (the batch variant skips instead).
    /// @param player Pack owner the win credits to.
    /// @param day The draw day to claim against.
    /// @param ticketIndex Which of the pack's four tickets to claim (0-3).
    /// @param drawKind 0 = main set, 1 = bonus set.
    function claimFoilMatch(
        address player,
        uint256 day,
        uint256 ticketIndex,
        uint8 drawKind
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
        if (!_tryClaimFoilMatch(player, day, ticketIndex, drawKind)) revert NoClaimableMatch();
    }

    /// @notice Claim a foil pack's gold: the ladder on its total gold count, plus a
    ///         kicker when one whole ticket came out all gold.
    /// @dev Delegatecall-only (see buyFoilPack). The pack's four lines are the ones the
    ///      drain filed into the jackpot buckets, re-derived here from the same
    ///      (buyer, level, resolveDay word, frozen boost) — so how much gold a pack
    ///      holds is a fact about a sealed word, decided before the pack drained and
    ///      unchanged by anything the buyer does afterwards. Nothing about the gold is
    ///      stored: this is a PULL, deliberately kept out of the drain, which is a
    ///      gas-budgeted hot path that gates every jackpot. A revert here costs the
    ///      claimant their own tx and nothing else.
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

        (bool present, uint16 multBps, uint24 resolveDay, ) = _foilRecordFor(
            player,
            lvl
        );
        if (!present) revert NoGoldenTicket();

        // The pack's lines exist only once its resolveDay word has sealed.
        uint256 entropy = rngWordByDay[resolveDay];
        if (entropy == 0) revert NoGoldenTicket();

        // Already settled — including by the drain, which burns this exact marker when
        // it pushes a pack's grand.
        bytes32 mk = _goldenTicketKey(player, lvl);
        if (foilMatchClaimed[mk]) revert NoGoldenTicket();

        (uint8 golds, uint8 allGold) = _packGold(
            _deriveFoilLines(player, lvl, entropy, multBps)
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
        foilMatchClaimed[mk] = true;
        _settleGoldenTicket(player, lvl, golds, allGold);
    }

    /// @notice Permissionlessly resolve a batch of foil match claims.
    /// @dev Each claim runs as an external self-call wrapped in try/catch, so ANY single
    ///      claim revert — a non-claimable tuple (out of range, no draw, no record,
    ///      look-back, already claimed, no match) OR a payout spin that reverts (e.g. an
    ///      ETH tier too large for the frozen pool's pending buffer) — rolls back ONLY
    ///      that claim (its marker, whale pass, and spin together) and the sweep moves
    ///      on. One stale or unpayable tuple past the opener can never poison the batch.
    ///      The tuple at index 0 is the exception: a revert there reverts the whole call
    ///      with StaleBatch(), because an already-swept list fails there first and the
    ///      cheap revert is what a wallet's pre-flight simulation shows a second sender.
    ///      Put a tuple expected to settle first. Each settled win credits its own
    ///      `player`. The arrays are parallel: claim i is (players[i], drawDays[i],
    ///      ticketIndexes[i], drawKinds[i]).
    /// @param players Pack owners the wins credit to.
    /// @param drawDays Draw days to claim against.
    /// @param ticketIndexes Which pack ticket (0-3) per claim.
    /// @param drawKinds 0 = main, 1 = bonus, per claim.
    function claimFoilMatchMany(
        address[] calldata players,
        uint24[] calldata drawDays,
        uint8[] calldata ticketIndexes,
        uint8[] calldata drawKinds
    ) external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        uint256 n = players.length;
        if (
            drawDays.length != n ||
            ticketIndexes.length != n ||
            drawKinds.length != n
        ) revert LengthMismatch();

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
                    ticketIndexes[i],
                    drawKinds[i]
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
        uint256 ticketIndex,
        uint8 drawKind
    ) private returns (bool) {
        if (ticketIndex >= 4) return false;
        if (drawKind >= 2) return false;
        // Bind `day` to the uint24 domain every lookup truncates to (dailyFoilDraw,
        // rngWordByDay). Without this the double-claim marker — which folds the full
        // uint256 `day` — would alias: day, day + 2^24, ... resolve to the SAME
        // draw/level/line/tier but mint DISTINCT markers, re-paying the win.
        if (day > type(uint24).max) return false;

        // The day's sealed winning sets + the cycle level active that day.
        (bool drawPresent, uint32 mainSet, uint32 bonusSet, uint24 L) =
            _foilDrawFor(day);
        if (!drawPresent) return false;

        // The player's frozen record for that cycle: the boost, the resolveDay the lines
        // derive from, and the activity score frozen at buy (the spin's RTP). present is
        // the cap/ownership check.
        (bool present, uint16 multBps, uint24 resolveDay, uint16 activityScore) =
            _foilRecordFor(player, L);
        if (!present) return false;

        // No look-back: the first claimable draw is resolveDay (the day whose word the
        // lines derive from). A domain-separated keccak makes the line and that day's
        // winning-set draw independent, so claiming from resolveDay on is safe.
        if (day < resolveDay) return false;

        // Double-claim marker. The level binding keeps a player's wins at different
        // cycles separable.
        bytes32 mk = keccak256(
            abi.encode(player, uint256(L), day, uint256(drawKind), ticketIndex)
        );
        if (foilMatchClaimed[mk]) return false;

        // Re-derive the selected ticket's four-quadrant line from the SAME word +
        // boost the drain filed the jackpot entries with, so the foil match equals a
        // real jackpot entry (the load-bearing mint == claim invariant).
        uint32 sel = _deriveFoilLines(
            player,
            L,
            rngWordByDay[resolveDay],
            multBps
        )[ticketIndex];

        // Graded score vs the day's winning set: per quadrant a symbol
        // match scores +1, and if the color of that same quadrant also matches it
        // scores +2; a symbol miss scores 0 (color only counts once the symbol is hit).
        // Score T in {0..8}. Color (bits 5-3) is boosted on the foil line but the
        // winning set is uniform, so P(symbol) = P(color) = 1/8 — both boost-invariant,
        // so the faces calibration holds at any multBps.
        uint32 winSet = drawKind == 1 ? bonusSet : mainSet;
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
        foilMatchClaimed[mk] = true;

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

        emit FoilMatchClaimed(player, uint24(day), ticketIndex, drawKind, tier, faces);

        _payFoilTier(player, day, ticketIndex, drawKind, L, sel, tier, faces, activityScore);
        return true;
    }

    /// @dev Re-derive a pack's four four-quadrant match lines — the single shared
    ///      producer called by BOTH the drain (to file the sixteen boosted entries
    ///      into the jackpot trait buckets) and the claim (to compare against the
    ///      day's winning sets). Identical inputs (buyer, cycle level, the resolveDay
    ///      word, the frozen boost) give identical lines, so the jackpot samples
    ///      exactly what is claimable. Each line packs four 8-bit [QQ][CCC][SSS]
    ///      quadrant traits (A|B|C|D in bytes 0..3); the boost color ladder depends
    ///      only on multBps, so the cut table is built once and shared.
    function _deriveFoilLines(
        address buyer,
        uint24 lvl,
        uint256 entropy,
        uint16 multBps
    ) private pure returns (uint32[4] memory lines) {
        uint256[7] memory cut = DegenerusTraitUtils.foilCuts(multBps);
        for (uint256 i; i < 4; ++i) {
            uint256 seed = uint256(
                keccak256(abi.encode(entropy, buyer, lvl, FOIL_SEED_TAG, i))
            );
            uint8 tA = DegenerusTraitUtils.foilTrait(uint64(seed), cut);
            uint8 tB = DegenerusTraitUtils.foilTrait(uint64(seed >> 64), cut) | 64;
            uint8 tC = DegenerusTraitUtils.foilTrait(uint64(seed >> 128), cut) | 128;
            uint8 tD = DegenerusTraitUtils.foilTrait(uint64(seed >> 192), cut) | 192;
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
    ///      (ETH/FLIP/WWXRP) and the spin is seeded — both off the retained daily
    ///      word. The per-N-calibrated box-spins are EV-neutral (RTP scales with the
    ///      buyer's activity score frozen at buy), so the foil's boosted traits cannot
    ///      tilt EV and the ~2.633-faces/pack/30d calibration holds. FLIP stakes split into
    ///      thirds across three spins under one survival flip; ETH and WWXRP are single
    ///      spins. The T=8 tier (all four full doubles) also grants a half whale pass. All effects run after
    ///      the double-claim marker is set (CEI). The matched signature `sel` is the
    ///      spin's player ticket, so the win plays the exact four-quadrant line that
    ///      matched (its boosted gold count is EV-neutral under the per-N tables).
    ///
    ///      Snap valve: NO foil payout carries the exponent. The buy still pays 2^s
    ///      (the price tracks the ticket path), so on a thanos level the pack is simply
    ///      bad value — a deliberate ruling, not an oversight. Scaling the payout
    ///      instead would mean reading an exponent at claim time, and the claim can
    ///      land arbitrarily later than the buy: a declaration always targets
    ///      `level + 6` or beyond, so once one commits a live `_snapShiftFor` hands
    ///      every PAST level the new exponent, and a claim parked across the commit
    ///      would pay 2^(new - old) times its face. Freezing the exponent into the
    ///      record would close that, but the valve is an emergency lever nobody should
    ///      be farming around, so the foil legs just do not scale.
    function _payFoilTier(
        address player,
        uint256 day,
        uint256 ticketIndex,
        uint8 drawKind,
        uint24 L,
        uint32 sel,
        uint8 tier,
        uint256 faces,
        uint16 activityScore
    ) private {
        if (tier == 8) {
            whalePassClaims[player] += 1;
        }

        // Two disjoint keccak lanes off the retained daily word: the currency split
        // and the spin entropy. A sealed draw always retained a non-zero word; the
        // guard fails closed if that invariant is ever violated.
        uint256 rw = rngWordByDay[uint24(day)];
        if (rw == 0) revert Invariant();
        uint256 c = uint256(
            keccak256(abi.encode(rw, day, drawKind, ticketIndex, FOIL_CCY_TAG))
        ) % 100;
        uint256 seed = uint256(
            keccak256(abi.encode(rw, day, drawKind, ticketIndex, FOIL_SPIN_TAG))
        );

        // activityScore is the buyer's score frozen at buy (passed in), not a live read:
        // the spin RTP is fixed at buy, so neither the claim timing nor who triggers it
        // can move the payout. The per-N tables hold EV flat across the foil's boosted
        // trait mix.

        if (c < 40) {
            // ETH (40%): one pool-capped spin; over-cap recircs to the lootbox.
            _foilSpin(
                IDegenerusGameDegeneretteModule.resolveEthSpinFromBox.selector,
                player,
                faces * PriceLookupLib.priceForLevel(L),
                activityScore,
                seed,
                sel
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
                sel
            );
        } else {
            // WWXRP (20%): one spin; free mint, no solvency impact.
            _foilSpin(
                IDegenerusGameDegeneretteModule.resolveWwxrpSpinFromBox.selector,
                player,
                faces * WWXRP_FACE_AMOUNT,
                activityScore,
                seed,
                sel
            );
        }
    }

    /// @dev Delegatecall one of the Degenerette box-spin resolvers in the Game's
    ///      storage context. The three resolvers share a single (player, stake,
    ///      activityScore, seed, customTraits) shape, so one helper covers every
    ///      currency. `customTraits` is the matched foil line, so the spin plays the
    ///      exact ticket that won (a non-zero value bypasses seed-derived generation).
    function _foilSpin(
        bytes4 selector,
        address player,
        uint256 stake,
        uint16 activityScore,
        uint256 seed,
        uint32 customTraits
    ) private {
        (bool ok, ) = ContractAddresses.GAME_DEGENERETTE_MODULE.delegatecall(
            abi.encodeWithSelector(
                selector,
                player,
                stake,
                activityScore,
                seed,
                customTraits
            )
        );
        if (!ok) revert EmptyRevert();
    }

    // =========================================================================
    // Queue drain (relocated here from the mint module so the near-full mint
    // module keeps only the normal-ticket path under the EIP-170 limit)
    // =========================================================================

    /// @notice Drain the per-buy-day foil buckets on the leftover write budget.
    /// @dev Delegatecall-only entry, invoked by the mint module's processTicketBatch
    ///      once the normal queue is drained (and only when _foilDrainPending). Runs in
    ///      the Game's storage context, so it reads/writes the same
    ///      foilBuyers/foilDrainDay/foilCursor/foilRecord and the lvlTraitEntry
    ///      buckets the jackpot samples.
    /// @param room The leftover write budget for this batch.
    /// @return done True iff the foil drain has caught up (no sealed bucket remains).
    /// @return drained True if this call resolved at least one foil buyer.
    function processFoilDrain(uint32 room)
        external
        returns (bool done, bool drained)
    {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        return _processFoilDrain(room);
    }

    /// @dev Walk the per-buy-day buckets forward from the low-water mark (foilDrainDay)
    ///      up to the high-water mark (foilLastResolveDay), draining each whose daily
    ///      word has sealed. Each buyer resolves a fixed FOIL_PACK_ENTRIES (16) boosted
    ///      entries — four tickets x four quadrants — derived from rngWordByDay[bucket]
    ///      + the buyer's frozen multBps, filed into the jackpot trait buckets (no
    ///      stamp; the claim re-derives the same lines). foilCursor makes a
    ///      budget-short deferral resumable; a whole buyer defers (never a partial pack)
    ///      when the leftover budget can't cover the fixed 35-unit charge. A bucket
    ///      whose word is not yet sealed (a future day) stops the walk — it does not
    ///      gate the current jackpot.
    ///
    ///      The one payout this path makes is the golden-ticket grand, on a pack whose
    ///      four lines came out holding two or more all-gold tickets. Everything else
    ///      the gold is worth stays a pull. See _pushFoilGrand for why the debit needs
    ///      no RNG-lock guard here, and GRAND_DRAIN_UNITS for how it is metered.
    function _processFoilDrain(uint32 room)
        private
        returns (bool done, bool drained)
    {
        uint24 dd = foilDrainDay;
        uint24 last = foilLastResolveDay;
        uint256 cursor = foilCursor;

        // The grand push is closed from the liveness trigger on, matching the pull
        // claim: past that point the terminal path is drawing down the same pools the
        // grand debits. Read once for the whole walk — it cannot change mid-call.
        bool terminal = _livenessTriggered();

        // Trait-batch scratch shared across every buyer this call (re-zeroed per buyer
        // inside _resolveFoilBuyer), so memory does not grow per queue entry.
        uint32[256] memory counts;
        uint8[256] memory touchedTraits;

        while (dd <= last) {
            uint256 entropy = rngWordByDay[dd];
            if (entropy == 0) {
                // A bucket whose own day never sealed. In normal play that is simply a
                // future-dated bucket and the drain stops here. Under the terminal
                // fallback regime it is instead a day the dead VRF never worded, and no
                // later advance will ever seal it — so settle it against the committed
                // fallback word rather than reporting the drain complete and dropping
                // paid packs whose level is the one the terminal jackpot pays from.
                // rngWordCurrent holds that word for the whole drain; _unlockRng clears
                // it only after handleGameOverDrain has run.
                if (_lrRead(LR_GO_FALLBACK_SHIFT, LR_GO_FALLBACK_MASK) == 0) break;
                entropy = rngWordCurrent;
                if (entropy == 0) break;
            }

            // Meter the day-walk itself. A drained-past (empty) bucket between the low- and
            // high-water marks advances dd without entering the per-buyer loop, so a long run
            // of them — a whale/Sybil buy day keeps the drain behind while later calendar days
            // seal with no foil buys — would otherwise burn unbounded gas in one finishing call.
            // Charge one unit per day stepped and defer when the leftover budget is spent, the
            // same resumable shape as the per-buyer guard below.
            if (room == 0) {
                foilDrainDay = dd;
                foilCursor = uint32(cursor);
                return (false, drained);
            }
            unchecked {
                --room;
            }

            uint256[] storage bucket = foilBuyers[dd];
            uint256 total = bucket.length;
            while (cursor < total) {
                // A foil pack resolves a fixed FOIL_PACK_ENTRIES (16) boosted entries at
                // a fixed cost of 16*2 trait-writes + baseOv(2) + 1 = 35 budget units.
                // Defer the whole buyer when the leftover budget can't cover a full
                // pack; it resumes next tx (no partial-within-buyer, no brick). The
                // guard MUST equal the charge below: a smaller guard lets `room` just
                // above it underflow the unchecked charge and drain everything in one tx.
                if (room < (FOIL_PACK_ENTRIES * 2) + 3) {
                    foilDrainDay = dd;
                    foilCursor = uint32(cursor);
                    return (false, drained);
                }
                bool grand = _resolveFoilBuyer(
                    bucket[cursor],
                    entropy,
                    terminal,
                    counts,
                    touchedTraits
                );
                drained = true;
                unchecked {
                    room -= (FOIL_PACK_ENTRIES * 2) + 3; // 16*2 + baseOv(2) + 1 = 35
                    ++cursor;
                }
                // The grand's own writes, charged only to the pack that fired it. This
                // subtraction SATURATES where the fixed charge above wraps: the entry
                // guard is sized for a plain pack, so a grand landing on the last pack
                // a batch can afford would underflow an unchecked charge and hand the
                // rest of the walk a budget of ~4 billion units — draining every
                // remaining bucket in one transaction, which is the exact failure the
                // guard-equals-charge rule above exists to prevent. Saturating instead
                // overshoots this one batch's gas target by GRAND_DRAIN_UNITS (~140k
                // against a sub-10M target) on a pack that arrives once in 7.1 billion.
                if (grand) {
                    room = room < GRAND_DRAIN_UNITS
                        ? 0
                        : room - GRAND_DRAIN_UNITS;
                }
            }

            // Bucket fully drained: advance to the next day. The bucket is left in
            // place — days are monotonic and both the walk and the pending gate read
            // only foilDrainDay/foilLastResolveDay, so a passed bucket is unreachable.
            // (`delete foilBuyers[dd]` would compile into a loop zeroing every
            // element slot: unbounded gas on a big buy day, bricking the drain.)
            unchecked {
                ++dd;
            }
            cursor = 0;
        }

        // Caught up: dd is past the high-water mark or at a not-yet-sealed bucket.
        foilDrainDay = dd;
        foilCursor = 0;
        return (true, drained);
    }

    /// @dev Resolve one queued buyer (the packed level<<160|buyer entry): re-derive
    ///      the four boosted four-quadrant lines via the shared _deriveFoilLines, then
    ///      file all sixteen traits into the cycle level's trait buckets. No stamp —
    ///      the claim re-derives the SAME lines from rngWordByDay[resolveDay] + the
    ///      frozen multBps, so the stored record stays just (multBps, resolveDay).
    ///
    ///      Counts the pack's gold on the way past. The lines are already in memory and
    ///      already unpacked below, so reading how much gold they hold is opcode work on
    ///      data this function has in hand — a fraction of a percent of the sixteen
    ///      entry writes it is here to do. Only the grand acts on it: the ladder and its
    ///      kicker stay a pull, off this budgeted path.
    /// @param terminal Whether liveness has triggered; suppresses the grand push, so the
    ///        terminal drain never carves a pool the terminal jackpot is settling from.
    /// @return grandPaid True when this pack pushed the grand, so the caller can charge
    ///         its writes against the batch budget.
    function _resolveFoilBuyer(
        uint256 packedLvlBuyer,
        uint256 entropy,
        bool terminal,
        uint32[256] memory counts,
        uint8[256] memory touchedTraits
    ) private returns (bool grandPaid) {
        address buyer = address(uint160(packedLvlBuyer));
        uint24 lvl = uint24(packedLvlBuyer >> 160);
        uint32[4] memory lines = _deriveFoilLines(
            buyer,
            lvl,
            entropy,
            _foilMultFor(buyer, lvl)
        );

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

        // Batch-write the sixteen entries into lvlTraitEntry[lvl][traitId], one
        // length update per distinct trait. Mirrors the mint module's batch writer;
        // re-zeroes the shared scratch so the next buyer starts clean.
        uint256 levelSlot;
        assembly ("memory-safe") {
            mstore(0x00, lvl)
            mstore(0x20, lvlTraitEntry.slot)
            levelSlot := keccak256(0x00, 0x40)
        }
        for (uint16 u; u < touchedLen; ) {
            uint8 traitId = touchedTraits[u];
            uint32 occurrences = counts[traitId];
            counts[traitId] = 0;
            assembly ("memory-safe") {
                let elem := add(levelSlot, traitId)
                let len := sload(elem)
                sstore(elem, add(len, occurrences))
                mstore(0x00, elem)
                let dst := add(keccak256(0x00, 0x20), len)
                for {
                    let k := 0
                } lt(k, occurrences) {
                    k := add(k, 1)
                } {
                    sstore(dst, buyer)
                    dst := add(dst, 1)
                }
            }
            unchecked {
                ++u;
            }
        }

        uint256 baseKey = (uint256(lvl) << 224) |
            (uint256(uint160(buyer)) << 32);
        emit TraitsGenerated(buyer, baseKey, FOIL_PACK_ENTRIES);

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
    /// @param golds The pack's total gold quadrants — 8, 12 or 16.
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
        foilMatchClaimed[_goldenTicketKey(player, lvl)] = true;
        (bool ok, ) = ContractAddresses.GAME_JACKPOT_MODULE.delegatecall(
            abi.encodeWithSelector(
                IDegenerusGameJackpotModule.payGoldenTicketGrand.selector,
                player,
                lvl,
                golds
            )
        );
        if (!ok) revert EmptyRevert();
        // flipCredit 0: the grand's own legs are stamped by GoldenTicketWin.
        emit GoldenTicketFoil(player, lvl, golds, allGold, 0);
    }

    /// @dev The pack's golden-ticket claim marker key. Shares the foilMatchClaimed map
    ///      with the per-draw match markers: those fold five fields (player, level, day,
    ///      drawKind, ticketIndex) against this key's three, so the preimages differ in
    ///      length as well as in the tag — the two claim families can never mint the
    ///      same marker.
    function _goldenTicketKey(
        address player,
        uint24 lvl
    ) private pure returns (bytes32) {
        return keccak256(abi.encode(player, uint256(lvl), GOLDEN_TICKET_TAG));
    }
}