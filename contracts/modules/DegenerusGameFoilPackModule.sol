// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {MintPaymentKind} from "../interfaces/IDegenerusGame.sol";
import {
    IDegenerusGameDegeneretteModule
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
 *         whose four match signatures and boost multiplier freeze at buy, and a
 *         per-(day, ticket, drawKind) match claim that reads the day's sealed
 *         winning sets and pays an isolated 40/40/20 spin.
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
    error DirectEthInsufficient(); // DirectEth payment kind cannot cover the foil cost shortfall from claimable balance.
    error NoClaimableMatch(); // The given (player, day, ticketIndex, drawKind) tuple does not resolve to a claimable foil match.

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

    // Per-score face counts for the graded "Variant-2" match (see _tryClaimFoilMatch).
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

    /// @dev Per-settled-claim keeper bounty target (ETH-equivalent wei) for the
    ///      permissionless batch claimer, converted to FLIP at the reference price.
    ///      Mirrors the decimator box-claim bounty so a sweeper is reimbursed roughly
    ///      its per-claim settle gas.
    uint256 private constant FOIL_CLAIM_BOUNTY_ETH_TARGET = 15_000_000_000_000;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a foil pack is bought and its signatures freeze.
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

    // =========================================================================
    // Buy
    // =========================================================================

    /// @notice Deliver one foil pack (four tickets) for the active cycle as the foil leg
    ///         of an additive ticket/lootbox/foil purchase.
    /// @dev Delegatecall-only from the mint module's purchase path: address(this) == GAME
    ///      under the nested dispatch. A direct call on the deployed module would trap the
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
    /// @param payKind Payment method (DirectEth forbids drawing claimable).
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
        // for the foil leg covers it first (overpay ignored); any shortfall is taken from
        // claimable down to the 1-wei sentinel. The afking principal is NEVER tapped, and
        // DirectEth forbids claimable: either way an uncovered remainder reverts. ethUsed
        // is the fresh-rate affiliate basis; remaining is the recycle-rate basis.
        uint256 priceWei = PriceLookupLib.priceForLevel(lvl);
        uint256 cost = FOIL_PACK_TICKETS * priceWei;
        uint256 ethUsed = ethSent < cost ? ethSent : cost;
        uint256 remaining = cost - ethUsed;
        if (remaining != 0) {
            if (payKind == MintPaymentKind.DirectEth) revert DirectEthInsufficient();
            // One slot read covers the check and the debit. remaining must stay at or
            // below claimable - 1 (the 1-wei sentinel), so remaining < claimable and
            // the low-half subtraction cannot borrow into the afking principal above.
            uint256 bal = balancesPacked[buyer];
            if (remaining + 1 > uint128(bal)) revert Insolvent();
            balancesPacked[buyer] = bal - remaining;
            claimablePool -= uint128(remaining);
            emit ClaimableSpent(buyer, remaining, uint128(bal - remaining), MintPaymentKind.Internal, remaining);
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

        // Ten whole tickets' worth of mint units — the pack costs ten ticket prices, so it
        // records the same units a ten-whole-ticket purchase would, in the ticket leg's
        // quantity scale (one whole ticket = 4 * QTY_SCALE units). Via the shared
        // _recordMintData. Runs before the quest + boost so the units feed the activity
        // score exactly like a ten-ticket purchase.
        _recordMintData(buyer, lvl, uint32(FOIL_PACK_TICKETS * 4 * QTY_SCALE));

        // Affiliate, 20% fresh / 5% recycle exactly like a normal ticket mint: the fresh
        // portion (ethUsed) at the fresh rate, the claimable portion (remaining) at the
        // recycle rate, both frozen at level + 1 like the ticket affiliate (score 0, same
        // as tickets). FLIP kickbacks accumulate and are credited once below.
        uint24 affLevel = level + 1;
        uint256 kickback;
        if (ethUsed != 0) {
            kickback += affiliate.payAffiliate(
                (ethUsed * PRICE_COIN_UNIT) / priceWei,
                affiliateCode,
                buyer,
                affLevel,
                true,
                0
            );
        }
        if (remaining != 0) {
            kickback += affiliate.payAffiliate(
                (remaining * PRICE_COIN_UNIT) / priceWei,
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

        // Recycle bonus: spending at least three whole tickets' worth of claimable on the
        // foil leg (remaining is that claimable spend) earns 10% back as FLIP, exactly as a
        // recycled ticket buy does.
        if (remaining >= priceWei * 3) {
            kickback += (remaining * PRICE_COIN_UNIT * 10) / (priceWei * 100);
        }

        if (kickback != 0) coinflip.creditFlip(buyer, kickback);

        // Boost freeze off the buyer's post-action activity score (units + the streak the
        // primary just advanced are reflected via streakSnapshot). Mirror the mint path's
        // unified-streak swap: a live afking sub's reward streak lives on the Sub side (funded
        // days + in-run secondaries), not the decayed manual snapshot, so use the afking-live
        // value when a run is active — the same basis the mint path's cachedScore uses for the
        // lootbox EV. The raw score is also frozen into the record and reused as the claim
        // spin's RTP input, so the payout is fully determined at buy.
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
        // lines from rngWordByDay[resolveDay] + multBps.
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
        if (!_tryClaimFoilMatch(player, day, ticketIndex, drawKind)) revert NoClaimableMatch();
    }

    /// @notice Permissionlessly resolve a batch of foil match claims.
    /// @dev Each claim runs as an external self-call wrapped in try/catch, so ANY single
    ///      claim revert — a non-claimable tuple (out of range, no draw, no record,
    ///      look-back, already claimed, no match) OR a payout spin that reverts (e.g. an
    ///      ETH tier too large for the frozen pool's pending buffer) — rolls back ONLY
    ///      that claim (its marker, whale pass, and spin together) and the sweep moves
    ///      on. One stale or unpayable tuple can never poison the batch, so a keeper can
    ///      submit an off-chain-computed superset. Each settled win credits its own
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
                // Non-claimable or payout-reverting tuple: skip.
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

        // Graded "Variant-2" score vs the day's winning set: per quadrant a symbol
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
    ///      tilt EV and the ~2-faces/pack/30d calibration holds. FLIP stakes split into
    ///      thirds across three spins under one survival flip; ETH and WWXRP are single
    ///      spins. The T=8 tier (all four full doubles) also grants a half whale pass. All effects run after
    ///      the double-claim marker is set (CEI). The matched signature `sel` is the
    ///      spin's player ticket, so the win plays the exact four-quadrant line that
    ///      matched (its boosted gold count is EV-neutral under the per-N tables).
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
    function _processFoilDrain(uint32 room)
        private
        returns (bool done, bool drained)
    {
        uint24 dd = foilDrainDay;
        uint24 last = foilLastResolveDay;
        uint256 cursor = foilCursor;

        // Trait-batch scratch shared across every buyer this call (re-zeroed per buyer
        // inside _resolveFoilBuyer), so memory does not grow per queue entry.
        uint32[256] memory counts;
        uint8[256] memory touchedTraits;

        while (dd <= last) {
            uint256 entropy = rngWordByDay[dd];
            if (entropy == 0) break; // future-dated bucket: its word has not sealed yet

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
                _resolveFoilBuyer(bucket[cursor], entropy, counts, touchedTraits);
                drained = true;
                unchecked {
                    room -= (FOIL_PACK_ENTRIES * 2) + 3; // 16*2 + baseOv(2) + 1 = 35
                    ++cursor;
                }
            }

            // Bucket fully drained: free it and advance to the next day.
            if (total != 0) delete foilBuyers[dd];
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
    function _resolveFoilBuyer(
        uint256 packedLvlBuyer,
        uint256 entropy,
        uint32[256] memory counts,
        uint8[256] memory touchedTraits
    ) private {
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
    }
}