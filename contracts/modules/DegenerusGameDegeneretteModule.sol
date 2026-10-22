// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {GameDegeneretteBet} from "./GameDegeneretteBet.sol";
import {GameBoxInternals} from "./GameBoxInternals.sol";

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

import {IsDGNRS} from "../interfaces/IsDGNRS.sol";
import {RECORD_KIND_SPIN} from "../interfaces/ICoinflip.sol";
import {
    IDegenerusGameLootboxModule
} from "../interfaces/IDegenerusGameModules.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {MineFlipGas} from "../libraries/MineFlipGas.sol";
import {DegenerusTraitUtils} from "../DegenerusTraitUtils.sol";
import {EntropyLib} from "../libraries/EntropyLib.sol";
import {FlipRoundLib} from "../libraries/FlipRoundLib.sol";
import {ActivityCurveLib} from "../libraries/ActivityCurveLib.sol";
import {DegenerusGamePayoutUtils} from "./DegenerusGamePayoutUtils.sol";
import {DegenerusGameMintStreakUtils} from "./DegenerusGameMintStreakUtils.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";

/**
 * @title DegenerusGameDegeneretteModule
 * @author Burnie Degenerus
 * @notice Delegate-called module handling Degenerette symbol-roll bets.
 * @dev Uses lootbox RNG index/word for randomness. All storage reads/writes operate
 *      on the inherited DegenerusGameStorage. Player-funded bets support ETH and FLIP;
 *      internal box and foil reward spins also support WWXRP.
 *      FLIP payouts face a per-bet survival flip (double-or-nothing) at resolution,
 *      so all FLIP entering existence survives at least one coinflip.
 */
abstract contract DegenerusGameDegeneretteModule is GameBoxInternals,
    DegenerusGamePayoutUtils,
    DegenerusGameMintStreakUtils, GameDegeneretteBet
{
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    // error E() — inherited from DegenerusGameStorage

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted once per resolved Degenerette bet, carrying every spin.
    /// @param playerId The reward account's wallet ID.
    /// @param index The lootbox RNG index the bet resolved against.
    /// @param betId The bet's id within `index` (queue position + 1).
    /// @param totalPayout Total payout across all spins. For a FLIP bet the summed spin
    ///        payouts double or zero on the bet's survival flip, then collapse to a whole-FLIP
    ///        floor or, above FLIP_ROUND_THRESHOLD, a 100-FLIP multiple (FlipRoundLib).
    /// @param resultTraits The spin-0 house result traits.
    /// @param spins Five bytes per spin, spin 0 first: the player's traits (4 bytes,
    ///        big-endian), then score S (low 4 bits, 1-9) | house wild count W (bits 4-6).
    ///        Each spin's payout follows from these plus the bet's stake and activity score.
    event DegeneretteResolved(
        uint32 indexed playerId,
        uint32 indexed index,
        uint64 indexed betId,
        uint256 totalPayout,
        uint32 resultTraits,
        bytes spins
    );

    /// @notice Emitted when ETH payout exceeds pool cap and excess is converted to lootbox.
    /// @param playerId The reward account's wallet ID.
    /// @param cappedEthPayout The ETH payout after capping.
    /// @param excessConverted Total ETH routed to the lootbox for this spin — the 3-tier split remainder plus the pool-cap overflow (= payout − cappedEthPayout).
    event PayoutCapped(
        uint32 indexed playerId,
        uint256 cappedEthPayout,
        uint256 excessConverted
    );

    /// @notice A stake resolved as a Degenerette spin outside the ordinary bet flow — a lootbox
    ///         roll (WWXRP / FLIP×3 / ETH) or a biggest-spin record bounty (FLIP×3) — the single
    ///         self-contained record of that outcome (placed bets report through
    ///         DegeneretteResolved instead). Every reel + every output reward is here or, for
    ///         the ETH recirc, in the fresh box's own (now-emitted) events.
    /// @param playerId The reward account's wallet ID.
    /// @param betId Self-classifying id: bit 63 = synthetic-origin sentinel, bits 62-60 = spin type
    ///        (0=WWXRP, 1=FLIP, 2=ETH, 3=record bounty), bits 59-0 = seed entropy (unique per spin).
    /// @param packedSpins Per-spin reels packed low→high, each spin = [playerTraits:32 |
    ///        resultTraits:32 | score:8] (72 bits, spin 0 lowest); bits 216-223 = spin count;
    ///        bit 224 = FLIP survival flag (1 = the survival flip won; unused for WWXRP/ETH).
    ///        The hero lane is the player lane with its wild bit (0x40) set.
    /// @param payout Total reward: WWXRP requested (before WWXRP's gameMintScale), FLIP (returned to the box caller and credited
    ///        through coinflip at flush; a record-bounty chain joins its bettor's batched mint), or the ETH
    ///        gross (= ethShare + the recirc).
    /// @param ethShare ETH credited to the player's claimable winnings (0 for WWXRP/FLIP). The
    ///        recirculated remainder is derivable as `payout - ethShare` (ETH only); that recirc
    ///        box emits its own LootBoxOpened / BoxSpin so its contents are itemized.
    event BoxSpin(
        uint32 indexed playerId,
        uint64 betId,
        uint256 packedSpins,
        uint256 payout,
        uint256 ethShare
    );

    // -------------------------------------------------------------------------
    // Internal Helpers
    // -------------------------------------------------------------------------

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @dev Activity score at the curve knee K (seg-A end; deity pass theoretical max).
    uint16 private constant ACTIVITY_SCORE_MAX_POINTS = 305;

    /// @dev Minimum ROI in basis points (90%, score 0).
    uint16 private constant ROI_MIN_BPS = 9_000;

    /// @dev ROI at the knee K (90% of the gain delivered).
    uint16 private constant ROI_VA_BPS = 9_891;

    /// @dev ROI at the seg-B knee (98% of the gain).
    uint16 private constant ROI_VB_BPS = 9_970;

    /// @dev Maximum ROI in basis points (99.9%, reached at the effective cap).
    uint16 private constant ROI_MAX_BPS = 9_990;

    /// @dev Maximum ETH payout as percentage of futurePool in basis points (10%).
    uint16 private constant ETH_WIN_CAP_BPS = 1_000;

    /// @dev Referrer's FLIP credit on the box value of S>=5 ETH spins (4.26%).
    uint16 private constant AFFILIATE_BOX_BPS = 426;

    /// @dev sDGNRS contract reference for degenerette DGNRS rewards
    IsDGNRS private constant sdgnrs =
        IsDGNRS(ContractAddresses.SDGNRS);

    /// @dev Degenerette DGNRS reward BPS (per ETH wagered, % of remaining Reward pool),
    ///      keyed on the top-3 score tiers S=7/8/9.
    uint16 private constant DEGEN_DGNRS_7_BPS = 204; // S=7: 2.04% per ETH
    uint16 private constant DEGEN_DGNRS_8_BPS = 466; // S=8: 4.66% per ETH
    uint16 private constant DEGEN_DGNRS_9_BPS = 1010; // S=9: 10.1% per ETH

    /// @dev Internal reward-spin currency; unavailable to player-funded bets.
    uint8 private constant CURRENCY_WWXRP = 3;

    // -------------------------------------------------------------------------
    // Biggest-Spin Record Bonus (ETH only)
    // -------------------------------------------------------------------------
    //
    // An ETH bet above the entry floor is offered against the all-time
    // biggest-bet record, which Coinflip owns alongside the other three
    // all-time records and the shared FLIP pool they pay from. The unit is the
    // bet's TOTAL ETH (the whole transaction's wager). Beating the mark by a
    // fifth claims the category's accrued pool share; any larger bet ratchets the
    // mark for free.
    //
    // The claim is drawn from the pool at placement but paid as a FLIP spin chain,
    // not as flip credit: it waits in whole FLIP beside the queued bet
    // (degeneretteRecordBounty, flagged on the bet word) and spins when the bet resolves, off the same word the bet itself is bound
    // to. Placement always binds to the unrevealed write buffer, so the claim
    // is armed against an unknown word by construction — the same freeze the bet's
    // own spins rest on.

    // -------------------------------------------------------------------------
    // Quick Play Constants
    // -------------------------------------------------------------------------

    /// @dev Salt for quick play ticket generation.
    bytes1 private constant QUICK_PLAY_SALT = 0x51; // 'Q'

    // Shared ETH/FLIP score table in centi-x, gross of stake; neutral EV includes the
    // result-wild multiplier (1 + W/4). Derived and checked by
    // scripts/data/degenerette_single_symbol_math.py. Scores 0..2 pay nothing; S3..S9
    // are packed in 32-bit lanes from S3 up.
    uint256 private constant BASE_CENTIX_PACKED = 0x00000000015ef3c0001bbaf00000f42400002710000003e80000012c00000032;
    // ETH's flat additions in centi-x for S6..S9 (32-bit lanes from S6): +5 percentage
    // points of return, not scaled by activity, scaled by wilds and the stake boon.
    uint256 private constant ETH_ADD_CENTIX_PACKED = 0x000000000000000000000000000000000155ecd000019a28000011f8000000f0;
    // WWXRP shares S0..7 and keeps its own S8/S9 prizes. Normalize its rigged/wild base
    // to 70%, then allocate activity's extra 0..60 percentage points to scores 6..9.
    uint256 private constant WWXRP_FLOOR_SCALED = 5_762_468_903;
    uint256 private constant WWXRP_PAYOUT_S8 = 480_677;
    uint256 private constant WWXRP_PAYOUT_S9 = 100_000_000;
    uint256 private constant WWXRP_BONUS_FACTORS_PACKED = 0x000000000022398b000000000050091100000000001bd97b000000000005711c;
    uint16 private constant WWXRP_ROI_MIN_BPS = 7_000;
    uint16 private constant WWXRP_ROI_VA_BPS = 12_400;
    uint16 private constant WWXRP_ROI_VB_BPS = 12_760;
    uint16 private constant WWXRP_ROI_MAX_BPS = 13_000;
    uint256 private constant WWXRP_RIG_DENOMINATOR = 20;

    uint256 private constant PLAYER_TICKET_TAG = 0x446567656e506c61796572; // DegenPlayer
    uint256 private constant HERO_PICK_TAG = 0x446567656e4865726f; // DegenHero
    uint256 private constant RESULT_TICKET_TAG = 0x446567656e526573756c74; // DegenResult
    uint256 private constant WWXRP_DRAW_TAG = 0x575758525044726177; // WWXRPDraw
    uint256 private constant WWXRP_RIG_SALT = 0x52494721; // RIG!
    uint8 private constant RANDOM_HERO = 32; // internal award spins only

    // -------------------------------------------------------------------------
    // Queued Bet Layout
    // -------------------------------------------------------------------------
    //
    // A bet is a paired lane in degeneretteQueue[index & 1] (full layout on the storage declaration):
    // owner wallet ID [0..31] | symbol [32..36] | spinCount [37..41] | currency [42] |
    // record flag [43] | activity score [44..59] | boosted stake units [60..123].
    // The bet id is the queue position + 1, so the index and id need no bits.
    //

    // Whole bets remain atomic; only admission bounds depend on spin count.
    uint256 private constant BET_ETH_BASE_GAS = GasBounds.DEGENERETTE_ETH_BASE_GAS;
    uint256 private constant BET_ETH_SPIN_GAS = GasBounds.DEGENERETTE_ETH_SPIN_GAS;
    uint256 private constant BET_FLIP_BASE_GAS = GasBounds.DEGENERETTE_FLIP_BASE_GAS;
    uint256 private constant BET_FLIP_SPIN_GAS = GasBounds.DEGENERETTE_FLIP_SPIN_GAS;
    uint256 private constant BET_RECORD_GAS = GasBounds.DEGENERETTE_RECORD_GAS;
    uint256 private constant BET_TAIL_GAS = GasBounds.DEGENERETTE_TAIL_GAS;

    // Common masks
    uint256 private constant MASK_5 = 0x1F;
    uint256 private constant MASK_16 = 0xFFFF;

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    /// @dev Cross-bet payout accumulator threaded through the resolve paths → _resolveBet
    ///      → _distributePayout. Per-currency payouts are summed per owner and flushed when
    ///      the next bet belongs to someone else or the call ends (additive, so byte-identical
    ///      to the per-spin writes). The prize-pool decrement runs
    ///      against a running local that mirrors the live storage value spin-by-spin:
    ///      read once at first ETH win, decremented in memory per spin (so each
    ///      spin's ETH_WIN_CAP_BPS cap sees the same shrinking pool it would have
    ///      read from storage today), written back once at flush. Lootbox-share is
    ///      NOT accumulated here — it is summed PER betId and resolved once per bet
    ///      inside _resolveBet (resolution-batch-invariant).
    struct ResolveAcc {
        uint32 ownerId; // whose payouts ethClaimable / flipMint currently hold
        uint256 ownerElement; // loaded only by a referral lookup or token payout
        address payee; // shared by the current owner's token payouts
        uint256 ethClaimable; // summed ETH claimable across all bets
        uint256 flipMint; // summed FLIP mint across all bets
        bool poolFrozen; // prizePoolFrozen snapshot (loaded with the pool locals)
        bool poolLoaded; // running pool locals initialized?
        uint256 runningFuture; // unfrozen: running futurePrizePool
        uint128 pendingNext; // frozen: running pending next pool
        uint128 pendingFuture; // frozen: running pending future pool
    }

    /// @dev Per-bet results kept together to bound stack use across the payout calls.
    struct BetTotals {
        uint256 totalPayout;
        uint256 betLootboxShare;
        uint256 affiliateBoxShare;
        uint32 firstResultTraits;
    }

    /// @notice Consume the active session's FIFO bet queue after human boxes finish.
    function runDegeneretteWork(uint256 gasAllowance) external returns (MineFlipGas.Result memory) {
        return _runDegeneretteWork(gasAllowance);
    }

    struct BetWork {
        uint48 index;
        uint256 pos;
        uint256 qlen;
        uint256 rngWord;
        uint256 startPos;
    }

    function _runDegeneretteWork(uint256 gasAllowance) private returns (MineFlipGas.Result memory result) {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if (_activeDegeneretteCursor() != 0) return result;
        BetWork memory c;
        MineFlipGas.Meter memory meter = MineFlipGas.start(gasAllowance);
        c.index = _rngReadBuffer();
        c.pos = degeneretteCursor;
        c.qlen = degeneretteReadCount;
        if (c.pos == c.qlen) { result.done = true; return result; }
        if (_rngConsumerStage() != 4) return result;
        c.rngWord = _lootboxWord(c.index);
        ResolveAcc memory acc;
        c.startPos = c.pos;
        _setActiveDegeneretteCursor(c.pos + 1);
        while (c.pos < c.qlen) {
            uint256 bet = _loadDegeneretteBet(c.index, c.pos);
            if (!MineFlipGas.canRun(meter, _betGasMaximum(bet), BET_TAIL_GAS)) break;
            ++c.pos;
            _setActiveDegeneretteCursor(c.pos + 1);
            ++result.rewardBasis;
            _resolveBet(bet, uint32(c.index), uint64(c.pos), c.rngWord, acc);
            MineFlipGas.markProgress(meter);
        }
        _flushOwner(acc);
        _flushPool(acc);
        result.progressed = c.pos != c.startPos;
        if (result.progressed) degeneretteCursor = uint48(c.pos);
        _setActiveDegeneretteCursor(0);
        result.done = c.pos == c.qlen;
        if (result.done) _tryCompleteRng();
        MineFlipGas.finish(meter);
    }

    function _betGasMaximum(uint256 bet) private pure returns (uint256 maximum) {
        uint256 spins = (bet >> BET_COUNT_SHIFT) & MASK_5;
        maximum = (bet >> BET_CURRENCY_SHIFT) & 1 == CURRENCY_ETH
            ? BET_ETH_BASE_GAS + spins * BET_ETH_SPIN_GAS
            : BET_FLIP_BASE_GAS + spins * BET_FLIP_SPIN_GAS;
        if (bet & BET_RECORD_FLAG != 0) maximum += BET_RECORD_GAS;
    }

    /// @dev Pay the current owner's accumulated FLIP and ETH, then clear them.
    function _flushOwner(ResolveAcc memory acc) private {
        if (acc.flipMint != 0) {
            coin.mintForGame(_resolvePayee(acc), acc.flipMint);
            acc.flipMint = 0;
        }
        if (acc.ethClaimable != 0) {
            _addClaimableEth(acc.ownerId, acc.ethClaimable);
            acc.ethClaimable = 0;
        }
    }

    function _ownerElement(ResolveAcc memory acc) private view returns (uint256) {
        if (acc.ownerElement == 0) acc.ownerElement = _walletElement(acc.ownerId);
        return acc.ownerElement;
    }

    function _resolvePayee(ResolveAcc memory acc) private view returns (address) {
        if (acc.payee == address(0)) acc.payee = _payee(_ownerElement(acc));
        return acc.payee;
    }

    /// @dev Write the running prize-pool local back once, only if an ETH win loaded it.
    function _flushPool(ResolveAcc memory acc) private {
        if (acc.poolLoaded) {
            if (acc.poolFrozen) {
                _setPendingPools(acc.pendingNext, acc.pendingFuture);
            } else {
                _setFuturePrizePool(acc.runningFuture);
            }
        }
    }

    // -------------------------------------------------------------------------
    // Internal Bet Logic
    // -------------------------------------------------------------------------

    /// @dev Resolves one queued bet covered by the caller's active cursor: decodes the
    ///      word and materializes its spins against the index word. Per-currency payouts
    ///      accumulate into `acc` per owner (flushed by the caller or at the next owner);
    ///      lootbox-share is summed across this bet's spins and resolved ONCE here (one box
    ///      per bet). Every spin is recorded in the bet's single DegeneretteResolved event.
    struct ResolvedBet {
        uint32 playerId;
        uint8 symbol;
        uint8 spinCount;
        uint8 currency;
        uint16 activityScore;
        uint128 amountPerSpin;
    }

    function _resolveBet(
        uint256 bet,
        uint32 index,
        uint64 betId,
        uint256 rngWord,
        ResolveAcc memory acc
    ) private {
        ResolvedBet memory c;
        c.playerId = uint32(bet);
        if (c.playerId != acc.ownerId) {
            _flushOwner(acc);
            acc.ownerId = c.playerId;
            acc.ownerElement = 0;
            acc.payee = address(0);
        }
        c.symbol = uint8((bet >> BET_SYMBOL_SHIFT) & MASK_5);
        c.spinCount = uint8((bet >> BET_COUNT_SHIFT) & MASK_5);
        c.currency = uint8((bet >> BET_CURRENCY_SHIFT) & 1);
        c.activityScore = uint16((bet >> BET_ACTIVITY_SHIFT) & MASK_16);
        c.amountPerSpin = uint128(
            ((bet >> BET_STAKE_SHIFT) & MASK_64) *
                (c.currency == CURRENCY_ETH ? ETH_STAKE_UNIT : FLIP_STAKE_UNIT)
        );

        BetTotals memory totals;
        // Five bytes per spin: player traits (big-endian), then score | house wilds << 4.
        bytes memory spins = new bytes(uint256(c.spinCount) * 5);

        for (uint8 spinIdx; spinIdx < c.spinCount; ) {
            SpinResult memory spin = _rollBetSpin(rngWord, index, c.symbol, spinIdx, c.currency);
            if (spinIdx == 0) totals.firstResultTraits = spin.resultTraits;
            uint8 s = spin.score;
            uint256 payout = _degenerettePayout(spin, c.currency, c.amountPerSpin, c.activityScore);
            {
                uint256 traits = spin.playerTraits;
                uint256 tail = uint256(s) | (uint256(spin.resultWilds) << 4);
                assembly ("memory-safe") {
                    let p := add(add(spins, 0x20), mul(spinIdx, 5))
                    mstore8(p, shr(24, traits))
                    mstore8(add(p, 1), shr(16, traits))
                    mstore8(add(p, 2), shr(8, traits))
                    mstore8(add(p, 3), traits)
                    mstore8(add(p, 4), tail)
                }
            }

            if (payout != 0) {
                // Accumulate this spin's payout. ETH credits + the running-pool
                // decrement / cap land in `acc` (flushed cross-bet); the spin's
                // lootbox-share is returned and summed into this bet's box. `paid` is
                // what the spin actually pays across both legs.
                (uint256 spinLootboxShare, uint256 paid) = _distributePayout(
                    c.playerId,
                    c.currency,
                    c.amountPerSpin,
                    payout,
                    acc
                );
                // maxSpins * max payout factor < 2^26, even after FLIP survival;
                // with a uint128 stake the bet total stays below 2^154.
                unchecked {
                    totals.totalPayout += paid;
                }
                totals.betLootboxShare += spinLootboxShare;
                // Only a high-match (s>=5) spin's box value earns the affiliate reward;
                // the share is 0 for FLIP, so this stays ETH-only implicitly.
                if (s >= 5) totals.affiliateBoxShare += spinLootboxShare;
            }

            // Award sDGNRS from Reward pool on S>=7 ETH bets. Stays per-spin:
            // _awardDegeneretteDgnrs reads poolBalance fresh per call, so summing
            // off a stale balance would change the payout.
            if (c.currency == CURRENCY_ETH && s >= 7) {
                _awardDegeneretteDgnrs(acc, c.amountPerSpin, s);
            }

            unchecked {
                ++spinIdx;
            }
        }

        // FLIP survival flip: every FLIP payout must survive one fair coinflip before
        // it mints — the bet's whole payout double-or-nothings on a single bet-keyed flip
        // (EV-neutral: x2 at 50/50). A dedicated domain binds owner and bet id.
        // Both identities are committed before the VRF word lands, so the outcome
        // is fixed at fulfillment;
        // a losing bet pays zero whether resolved or abandoned, so selective resolution
        // earns nothing. The accumulator holds exactly this bet's payout once (added per
        // spin), so doubling adds it again and zeroing subtracts it back out. The outcome
        // reads off DegeneretteResolved: totalPayout vs the payouts its packed spins imply.
        if (c.currency == CURRENCY_FLIP && totals.totalPayout != 0) {
            if (EntropyLib.hash4(rngWord, c.playerId, betId, BET_SURVIVAL_TAG) & 1 == 1) {
                acc.flipMint += totals.totalPayout;
                totals.totalPayout *= 2;
            } else {
                acc.flipMint -= totals.totalPayout;
                totals.totalPayout = 0;
            }

            // Collapse what the player actually receives onto a whole 100-FLIP multiple,
            // EV-preserving, above the threshold where the granule is a small slice of the
            // award; below it the payout keeps the whole-FLIP floor. A bet that loses its
            // survival flip is zero and both forms leave it there. The delta rides into the
            // accumulator so the single flush mints exactly this bet's payout — the
            // subtraction cannot underflow because the accumulator already holds at least it.
            //
            // The roll is per-bet on a betId-keyed word, and that is load-bearing: the sweep
            // resolves the queue in order but each call stops where its budget runs out, so
            // rounding the summed `acc.flipMint` at the flush instead would make the payout
            // depend on where the crank's call boundaries fall. Keyed per bet, the outcome is
            // fixed at fulfillment however the queue is chunked.
            uint256 rounded = totals.totalPayout > FlipRoundLib.FLIP_ROUND_THRESHOLD
                ? FlipRoundLib.roundFlipToHundreds(
                    totals.totalPayout,
                    EntropyLib.hash4(rngWord, c.playerId, betId, FLIP_ROUND_TAG)
                )
                : FlipRoundLib.floorWholeFlip(totals.totalPayout);
            if (rounded > totals.totalPayout) {
                acc.flipMint += rounded - totals.totalPayout;
            } else if (rounded < totals.totalPayout) {
                acc.flipMint -= totals.totalPayout - rounded;
            }
            totals.totalPayout = rounded;
        }

        // One lootbox per betId, on the summed lootbox-share. The box seed binds the immutable
        // betId (keccak'd with the index word) so each of a player's bets at the same index rolls
        // independently; the live lootbox-share is NOT a seed input. Never summed across betIds.
        if (totals.betLootboxShare > 0) {
            // The bet-win recirc box itemizes its contents via LootBoxOpened (like every box path)
            // so the per-box FLIP datum is recoverable.
            _resolveLootboxDirect(
                c.playerId,
                totals.betLootboxShare,
                EntropyLib.hash2(rngWord, betId),
                c.activityScore
            );
        }

        // Affiliate reward: 4.26% of the box value from high-match (s>=5) ETH spins, as FLIP
        // to the player's referrer by wallet ID (VAULT when unreferred; 0, a no-op credit, for a
        // referrer not yet registered).
        if (totals.affiliateBoxShare > 0) {
            uint256 refFlip = (totals.affiliateBoxShare * PRICE_COIN_UNIT) /
                PriceLookupLib.priceForLevel(level + 1);
            coinflip.creditFlip(
                affiliate.getReferrerIdById(c.playerId), (refFlip * AFFILIATE_BOX_BPS) / 10_000
            );
        }

        emit DegeneretteResolved(
            c.playerId,
            index,
            betId,
            totals.totalPayout,
            totals.firstResultTraits,
            spins
        );

        // Biggest-spin record bounty: the claim this bet armed at placement, staked as
        // its own FLIP spin chain rather than paid as flip credit — beating the spin
        // record buys a spin. Mint-only (no pool / ETH / claimable touch), so it is
        // solvency-neutral and independent of everything settled above. The seed binds
        // the bet's committed word and its immutable betId, so the outcome was fixed at
        // fulfillment and no batch composition can steer it. The chosen hero symbol
        // carries over; the remaining ticket is freshly generated per bounty spin.
        if (bet & BET_RECORD_FLAG != 0) {
            uint256 key = (uint256(index) << 64) | betId;
            uint256 recordBounty = degeneretteRecordBounty[key];
            // The cursor retires this claim. A later flagged bet overwrites the
            // side slot; an unflagged bet never reads it when the buffer is reused.
            // The chain's FLIP joins the owner's batched mint, which pays the owner's payee.
            acc.flipMint += _flipSpinChain(
                c.playerId,
                recordBounty * TOKEN_MATH_SCALE,
                c.activityScore,
                EntropyLib.hash4(rngWord, c.playerId, betId, RECORD_SPIN_TAG),
                c.symbol,
                BOX_SPIN_TYPE_RECORD
            );
        }
    }

    /// @dev Distributes payout to player. ETH-currency 3-tier split rule:
    ///        - payout ≤ 3 × betAmount        → 100% ETH (no lootbox conversion).
    ///        - 3×bet < payout ≤ 10 × bet     → 2.5 × betAmount ETH (flat floor) + remainder lootbox.
    ///        - payout > 10 × betAmount       → payout / 4 ETH (25% standard) + remainder lootbox.
    ///      Implementation expresses the upper two tiers as
    ///      `ethShare = max(2.5 × betAmount, payout / 4)`; the two bands meet exactly at
    ///      payout = 10 × bet where `payout / 4 == 2.5 × bet`. Boundary at exactly
    ///      3 × bet is inclusive (3 × bet pays full ETH); the discontinuity at
    ///      3.0× → 3.01× drops ETH from 3.0×bet to 2.5×bet (smaller than the
    ///      naive 25% alternative which would drop to 0.7525×bet).
    ///
    ///      Pool cap (ETH_WIN_CAP_BPS = 10% of futurePool) takes PRECEDENCE over
    ///      all three tiers in the unfrozen branch: if computed ethShare exceeds
    ///      10% of pool, excess flips to lootbox and the PayoutCapped event is
    ///      emitted. Frozen-pool branch retains its solvency-check posture
    ///      (pending future debit with revert-on-insufficient).
    ///
    ///      CURRENCY_FLIP accumulates toward the coin mint (the per-bet survival
    ///      flip in _resolveBet then doubles or zeroes the bet's total
    ///      before the flush). FLIP does not use the 3-tier split (which applies only to the
    ///      lootbox-convertible ETH path).
    /// @param playerId The reward account's wallet ID.
    /// @param currency The currency type (0=ETH, 1=FLIP).
    /// @param betAmount The per-ticket bet amount (uint128) — the tier-threshold reference.
    /// @param payout The total payout amount (uint256).
    /// @param acc Cross-bet accumulator: ETH claimable + the running prize-pool
    ///        local accumulate here (flushed once per runDegeneretteWork call); FLIP
    ///        mint totals accumulate here too.
    /// @return lootboxShare The ETH lootbox-share for this spin (0 for FLIP),
    ///         summed by the caller into the per-bet box.
    /// @return paid What this spin actually pays out across both legs.
    function _distributePayout(
        uint32 playerId,
        uint8 currency,
        uint128 betAmount,
        uint256 payout,
        ResolveAcc memory acc
    ) private returns (uint256 lootboxShare, uint256 paid) {
        paid = payout;
        if (currency == CURRENCY_ETH) {
            // 3-tier split rule
            uint256 ethShare;
            uint256 threeBet = uint256(betAmount) * 3;
            if (payout <= threeBet) {
                // Tier 1: payout ≤ 3 × bet → 100% ETH.
                ethShare = payout;
                lootboxShare = 0;
            } else {
                // Tier 2 (3 × bet < payout ≤ 10 × bet) → 2.5 × bet floor.
                // Tier 3 (payout > 10 × bet) → payout / 4 standard.
                // The max() resolves cleanly between the two bands.
                uint256 minEth = (uint256(betAmount) * 5) / 2; // 2.5 × bet
                uint256 stdEth = payout / 4;                    // 25% of payout
                ethShare = stdEth > minEth ? stdEth : minEth;
                lootboxShare = payout - ethShare;
            }

            // Load the running prize-pool local on the first ETH win. The first
            // read mirrors the live storage value the per-spin path would have
            // read; subsequent spins decrement the running local in memory, so
            // each spin's cap/solvency sees the same shrinking pool storage would
            // have held — byte-identical to per-spin. Flushed once by runDegeneretteWork.
            if (!acc.poolLoaded) {
                acc.poolLoaded = true;
                acc.poolFrozen = prizePoolFrozen;
                if (acc.poolFrozen) {
                    (acc.pendingNext, acc.pendingFuture) = _getPendingPools();
                } else {
                    acc.runningFuture = _getFuturePrizePool();
                }
            }

            if (acc.poolFrozen) {
                // Frozen path: route ETH share through the pending pool side-channel
                // (matching the bet-placement pattern). The live futurePrizePool
                // snapshot that advanceGame / runRewardJackpots operates on stays
                // intact; the pending future accumulator (credited by purchases
                // during freeze) is debited here with a revert-on-insufficient
                // solvency check, against the running local.
                if (uint256(acc.pendingFuture) < ethShare) revert Insolvent();
                acc.pendingFuture -= uint128(ethShare);
            } else {
                // Unfrozen path: pool cap (ETH_WIN_CAP_BPS) takes PRECEDENCE over
                // the 3-tier split. After capping,
                // ethShare ≤ pool × 10% < pool, so no further solvency check.
                uint256 pool = acc.runningFuture;
                uint256 maxEth = (pool * ETH_WIN_CAP_BPS) / 10_000;
                if (ethShare > maxEth) {
                    lootboxShare += ethShare - maxEth;
                    ethShare = maxEth;
                    emit PayoutCapped(playerId, ethShare, lootboxShare);
                }
                unchecked {
                    pool -= ethShare;
                }
                acc.runningFuture = pool;
            }

            // Accumulate ETH claimable cross-bet (flushed once). The lootbox-share
            // is returned to the caller, summed per betId, and resolved once per bet.
            // Bounded far below 2^256 (see totalPayout note), so the accumulation is safe.
            unchecked {
                acc.ethClaimable += ethShare;
            }
        } else if (currency == CURRENCY_FLIP) {
            unchecked {
                acc.flipMint += payout;
            }
        }
    }

    /// @dev Manual ETH/FLIP reel and player ticket, with the same shared round seeds.
    function _rollBetSpin(uint256 rngWord, uint32 index, uint8 symbol, uint8 spinIdx, uint8 currency)
        private
        pure
        returns (SpinResult memory)
    {
        // Spin results are derived deterministically from the lootbox RNG word + index.
        // Spin 0 uses a shorter preimage (no spinIdx mixed in) to produce a distinct seed.
        // Scratch-space keccak of the packed preimage — byte-identical layout to the
        // abi.encodePacked form: rngWord[32] | index[4] | (spinIdx[1], spin>0 only) | salt[1].
        // index is uint32 (shl 224 lands its 4 bytes at 0x20..0x23); QUICK_PLAY_SALT is bytes1
        // (left-aligned) so byte(0,·) lifts its single byte into the low lane for mstore8.
        // Writes only scratch (0x00..0x25); the free-memory pointer at 0x40 is untouched.
        uint256 resultSeed;
        if (spinIdx == 0) {
            assembly ("memory-safe") {
                mstore(0x00, rngWord)
                mstore(0x20, shl(224, index))
                mstore8(0x24, byte(0, QUICK_PLAY_SALT))
                resultSeed := keccak256(0x00, 37)
            }
        } else {
            assembly ("memory-safe") {
                mstore(0x00, rngWord)
                mstore(0x20, shl(224, index))
                mstore8(0x24, spinIdx)
                mstore8(0x25, byte(0, QUICK_PLAY_SALT))
                resultSeed := keccak256(0x00, 38)
            }
        }
        // All bettors choosing this symbol share the same prefix of player tickets.
        // The house sequence above is shared across symbols.
        uint256 spinSeed = EntropyLib.hash4(rngWord, index, symbol, spinIdx);
        return _rollSpin(spinSeed, resultSeed, symbol, currency);
    }

    /// @dev Resolve a purchased bet's combined win box against the shared per-level EV allowance.
    function _resolveLootboxDirect(
        uint32 id,
        uint256 amount,
        uint256 rngWord,
        uint16 activityScore
    ) private {
        _boxResolveLootboxDirect(id, amount, rngWord, activityScore);
    }

    // -------------------------------------------------------------------------
    // Shared spin generation and scoring
    // -------------------------------------------------------------------------

    struct SpinResult {
        uint32 playerTraits;
        uint32 resultTraits;
        uint8 score;
        uint8 resultWilds;
    }

    /// @dev Every manual, box, foil and record spin uses this same reel/scoring path.
    /// The caller supplies its committed house seed; activity never enters the draw.
    function _rollSpin(uint256 seed, uint256 houseSeed, uint8 symbol, uint8 currency)
        internal pure returns (SpinResult memory spin)
    {
        symbol = _spinSymbol(seed, symbol);
        spin.playerTraits = _playerTicket(seed, symbol);
        spin.resultTraits = DegenerusTraitUtils.packedTraitsDegenerette(houseSeed);
        if (currency == CURRENCY_WWXRP) {
            spin.resultTraits = _rigWwxrpResult(
                spin.playerTraits, spin.resultTraits, symbol >> 3,
                EntropyLib.hash2(seed, WWXRP_RIG_SALT)
            );
        }
        (spin.score, spin.resultWilds) = _score(spin.playerTraits, spin.resultTraits);
    }

    /// @dev The only fixed ticket component is the selected symbol (0..23; no Dice heroes),
    ///      whose lane's color is wild. The other three lanes are ordinary, so the player
    ///      holds exactly one wild. Separate domains keep colors independent of the results.
    function _playerTicket(uint256 seed, uint8 symbol) internal pure returns (uint32 traits) {
        if (symbol >= DEGENERETTE_HERO_COUNT) revert InvalidBet();
        traits = DegenerusTraitUtils.packedTraitsDegeneretteOrdinary(EntropyLib.hash2(seed, PLAYER_TICKET_TAG));
        uint32 shift = uint32(symbol >> 3) * 8;
        traits = (traits & ~(uint32(0xFF) << shift)) | (uint32(0x40 | (symbol & 7)) << shift);
    }

    /// @dev Award spins may request a random hero with the internal sentinel 32.
    ///      All 24 Crypto, Zodiac and Cards symbols are equally eligible.
    function _spinSymbol(uint256 seed, uint8 symbol) internal pure returns (uint8) {
        if (symbol == RANDOM_HERO) return uint8(EntropyLib.hash2(seed, HERO_PICK_TAG) % DEGENERETTE_HERO_COUNT);
        if (symbol >= DEGENERETTE_HERO_COUNT) revert InvalidBet();
        return symbol;
    }

    /// @dev Score and house wild count in one pass. Per lane: a symbol match scores 1; the
    /// color scores 1 for equal ordinary colors or one wild, 2 for two wilds. Only the hero
    /// lane holds a player wild, so the scorer needs no hero quadrant.
    /// Branch-free: a lane's symbol (bits 0-2) or color (bits 3-5) is equal iff all three bits
    /// of ~(player ^ result) are set there. Any-wild lands on bit 3 and both-wild on bit 0, so
    /// each lane byte holds its points (at most 3) and one multiply sums the four bytes into
    /// the top byte. A wild's zero color bits never matter: any wild already scores the color.
    function _score(uint32 playerTraits, uint32 resultTraits)
        internal pure returns (uint8 score, uint8 resultWilds)
    {
        assembly ("memory-safe") {
            let nd := not(xor(playerTraits, resultTraits))
            let m := and(nd, and(shr(1, nd), shr(2, nd)))
            let anyWild := and(shr(3, or(playerTraits, resultTraits)), 0x08080808)
            let bothWild := and(shr(6, and(playerTraits, resultTraits)), 0x01010101)
            let lanes := add(
                add(and(m, 0x01010101), shr(3, or(and(m, 0x08080808), anyWild))),
                bothWild
            )
            score := shr(24, and(mul(lanes, 0x01010101), 0xFF000000))
            resultWilds := shr(24, and(mul(and(shr(6, resultTraits), 0x01010101), 0x01010101), 0xFF000000))
        }
    }

    /// @dev ETH/FLIP share the base table; ETH adds its flat S6–S9 additions, scaled by the
    ///      result-wild multiplier but not by activity. WWXRP keeps separate S8/S9 entries,
    ///      normalizes its rigged base to 70% and adds the activity surplus on scores 6–9.
    ///      Keep full precision through the final division. At uint128 max stake the
    ///      numerator stays below 2^200.
    function _degenerettePayout(
        SpinResult memory spin,
        uint8 currency,
        uint128 betAmount,
        uint16 activityScore
    ) internal pure returns (uint256) {
        uint8 s = spin.score;
        if (s < 3) return 0;
        uint256 base = _basePayoutCentiX(s);
        uint256 wildFactor = 4 + uint256(spin.resultWilds);
        if (currency == CURRENCY_WWXRP) {
            if (s == 8) base = WWXRP_PAYOUT_S8;
            else if (s == 9) base = WWXRP_PAYOUT_S9;
            uint256 scaledRoi = WWXRP_FLOOR_SCALED;
            if (s >= 6) {
                scaledRoi += (_roiBpsFromScore(activityScore, true) - WWXRP_ROI_MIN_BPS) *
                    ((WWXRP_BONUS_FACTORS_PACKED >> (uint256(s - 6) * 64)) & type(uint64).max);
            }
            return uint256(betAmount) * base * wildFactor * scaledRoi / 4_000_000_000_000;
        }
        uint256 rate = base * _roiBpsFromScore(activityScore, false);
        if (currency == CURRENCY_ETH) rate += _ethAddCentiX(s) * 10_000;
        return uint256(betAmount) * rate * wildFactor / 4_000_000;
    }

    function _basePayoutCentiX(uint8 s) internal pure returns (uint256) {
        if (s < 3) return 0;
        return (BASE_CENTIX_PACKED >> (uint256(s - 3) * 32)) & type(uint32).max;
    }

    function _ethAddCentiX(uint8 s) internal pure returns (uint256) {
        if (s < 6) return 0;
        return (ETH_ADD_CENTIX_PACKED >> (uint256(s - 6) * 32)) & type(uint32).max;
    }

    // -------------------------------------------------------------------------
    // Payout Math
    // -------------------------------------------------------------------------

    /// @dev Scheduled return target at the shared activity knees (305, 500, 30,000).
    /// Ordinary: 90 / 98.91 / 99.7 / 99.9%. WWXRP: 70 / 124 / 127.6 / 130%.
    /// WWXRP distributes the gain above 70% only to winning scores 6..9.
    function _roiBpsFromScore(uint256 score, bool isWwxrp) internal pure returns (uint256) {
        uint256 minBps = isWwxrp ? WWXRP_ROI_MIN_BPS : ROI_MIN_BPS;
        uint256 kneeABps = isWwxrp ? WWXRP_ROI_VA_BPS : ROI_VA_BPS;
        uint256 kneeBBps = isWwxrp ? WWXRP_ROI_VB_BPS : ROI_VB_BPS;
        uint256 maxBps = isWwxrp ? WWXRP_ROI_MAX_BPS : ROI_MAX_BPS;
        if (score >= ActivityCurveLib.ACTIVITY_EFFECTIVE_CAP_POINTS) return maxBps;
        if (score <= ACTIVITY_SCORE_MAX_POINTS) {
            return minBps + score * (kneeABps - minBps) / ACTIVITY_SCORE_MAX_POINTS;
        }
        if (score <= ActivityCurveLib.ACTIVITY_SEG_B_KNEE_POINTS) {
            return kneeABps + (score - ACTIVITY_SCORE_MAX_POINTS) * (kneeBBps - kneeABps) /
                (ActivityCurveLib.ACTIVITY_SEG_B_KNEE_POINTS - ACTIVITY_SCORE_MAX_POINTS);
        }
        return kneeBBps + (score - ActivityCurveLib.ACTIVITY_SEG_B_KNEE_POINTS) * (maxBps - kneeBBps) /
            (ActivityCurveLib.ACTIVITY_EFFECTIVE_CAP_POINTS - ActivityCurveLib.ACTIVITY_SEG_B_KNEE_POINTS);
    }

    /// @dev WWXRP has a 5% chance to improve one missed axis of an already-paying spin
    ///      (S >= 3) with at most six matched axes, counting the always-matched hero color
    ///      once. Eligible: missed non-hero symbols and missed colors where neither side is
    ///      wild. The pick copies the player's bits into that house lane: +1 point, the
    ///      house wild count unchanged, never the hero symbol, never a jackpot. With at most
    ///      six matched axes at least two of eight are missed and at most one of them is the
    ///      hero symbol, so an eligible axis always exists.
    function _rigWwxrpResult(
        uint32 playerTraits,
        uint32 resultTraits,
        uint8 heroQuadrant,
        uint256 rigSeed
    ) internal pure returns (uint32 rigged) {
        rigged = resultTraits;
        if (rigSeed % WWXRP_RIG_DENOMINATOR != 0) return rigged;
        uint32 diff = playerTraits ^ resultTraits;
        uint32 wilds = (playerTraits | resultTraits) & 0x40404040;
        uint8 matches;
        uint8 eligible;
        for (uint8 q; q < 4; ++q) {
            uint32 shift = uint32(q) * 8;
            uint8 d = uint8(diff >> shift);
            if ((wilds >> shift) & 0x40 != 0 || (d & 0x38) == 0) ++matches;
            else ++eligible;
            if ((d & 7) == 0) ++matches;
            else if (q != heroQuadrant) ++eligible;
        }
        // Score adds the hero lane's second color point when the house lane is wild too.
        uint8 points = matches + uint8((resultTraits >> (uint32(heroQuadrant) * 8 + 6)) & 1);
        if (points < 3 || matches > 6) return rigged;
        uint256 pick = EntropyLib.hash2(rigSeed, 1) % eligible;
        for (uint8 q; q < 4; ++q) {
            uint32 shift = uint32(q) * 8;
            uint8 d = uint8(diff >> shift);
            if ((wilds >> shift) & 0x40 == 0 && (d & 0x38) != 0) {
                if (pick == 0) {
                    uint32 mask = uint32(0x38) << shift;
                    return (rigged & ~mask) | (playerTraits & mask);
                }
                --pick;
            }
            if (q != heroQuadrant && (d & 7) != 0) {
                if (pick == 0) {
                    uint32 mask = uint32(7) << shift;
                    return (rigged & ~mask) | (playerTraits & mask);
                }
                --pick;
            }
        }
    }

    /// @dev Credit a nonzero ETH payout through the shared accounting helper.
    function _addClaimableEth(uint32 beneficiary, uint256 weiAmount) private {
        claimablePool += uint128(weiAmount);
        _creditClaimableLogged(beneficiary, weiAmount);
    }

    /// @dev Award sDGNRS from Reward pool on the top-3 score tiers (S>=7) Degenerette ETH bets.
    ///      Reward scales by bet size (capped at 1 ETH) and score tier. Resolve the account's
    ///      payee only when a nonzero reward is ready to transfer.
    function _awardDegeneretteDgnrs(
        ResolveAcc memory acc,
        uint256 betWei,
        uint8 s
    ) private {
        uint256 bps;
        if (s == 7) bps = DEGEN_DGNRS_7_BPS;
        else if (s == 8) bps = DEGEN_DGNRS_8_BPS;
        else bps = DEGEN_DGNRS_9_BPS;

        uint256 poolBalance = sdgnrs.poolBalance(
            IsDGNRS.Pool.Reward
        );
        if (poolBalance == 0) return;

        uint256 cappedBet = betWei > 1 ether ? 1 ether : betWei;
        uint256 reward = (poolBalance * bps * cappedBet) / (10_000 * 1 ether);
        if (reward == 0) return;

        sdgnrs.transferFromPool(
            IsDGNRS.Pool.Reward,
            _resolvePayee(acc),
            reward
        );
    }

    // -------------------------------------------------------------------------
    // Lootbox-triggered Degenerette spins
    // -------------------------------------------------------------------------
    // Three lootbox value rolls resolve as Degenerette spins instead of flat awards.
    // Lootbox settlement calls these bodies in the Game's storage context; the
    // `address(this) != GAME` guard rejects any direct call on the deployed module
    // instance. Spin draws derive purely from the passed (hash2-tagged, freeze-safe)
    // seed — no live state enters the seed, so the outcome is fixed at fulfillment.
    // Each spin emits ONE self-contained BoxSpin event (DegeneretteResolved is
    // intentionally NOT emitted for box rolls — BoxSpin carries every reel plus the resolved
    // reward). The synthetic betId self-classifies: bit 63 =
    // box-origin sentinel, bits 62-60 = spin type, bits 59-0 = seed entropy.

    uint256 private constant BOX_FLIP_SPINS = 3;
    uint256 private constant BOX_SURVIVAL_TAG = 0x537572766976616c; // "Survival"
    uint256 private constant BOX_RECIRC_TAG = 0x5265636972; // "Recir"
    /// @dev Domain-separation tag for the 100-FLIP award collapse. Mixed with the immutable
    ///      per-award key (the betId, the box seed) so the roll is fixed at VRF fulfillment
    ///      and cannot be steered by how a settle batch is composed.
    uint256 private constant FLIP_ROUND_TAG = 0x466c6970526f756e64; // "FlipRound"
    uint256 private constant BET_SURVIVAL_TAG = 0x446567656e537572766976616c; // "DegenSurvival"

    // Box-spin BoxSpin.betId header. Bit 63 is a box-origin sentinel (real bet ids are queue
    // positions + 1, so they never reach it); bits 62-60 carry the spin type; bits 59-0 are seed entropy
    // (a unique per-box-spin id). The off-chain UI reads `betId >> 63` (is-box-spin) and
    // `(betId >> 60) & 7` (type) off the event's data field (only `player` is indexed).
    uint256 private constant BOX_BETID_SENTINEL = uint256(1) << 63;
    uint8 private constant BOX_SPIN_TYPE_WWXRP = 0;
    uint8 private constant BOX_SPIN_TYPE_FLIP = 1;
    uint8 private constant BOX_SPIN_TYPE_ETH = 2;
    /// @dev Not a box roll: a biggest-spin record bounty spun as FLIP off the bet that
    ///      won it. Shares the BoxSpin record so the reels stay itemized one way.
    uint8 private constant BOX_SPIN_TYPE_RECORD = 3;
    /// @dev Domain-separation tag for the record bounty's spin seed, keyed under the
    ///      resolving bet's own word so the outcome is fixed at VRF fulfillment.
    uint256 private constant RECORD_SPIN_TAG = 0x5265636f7264; // "Record"
    // BoxSpin.packedSpins layout: spin i occupies bits [i*72 .. i*72+71] as
    // [playerTraits:32 | resultTraits:32 | score:8]; bits 216-223 = spin count; bit 224 = survived.
    uint256 private constant BOX_SPIN_COUNT_SHIFT = 216;
    uint256 private constant BOX_SPIN_SURVIVED_SHIFT = 224;

    function _boxBetId(uint256 seed, uint8 spinType) private pure returns (uint64) {
        return uint64(
            BOX_BETID_SENTINEL |
            (uint256(spinType) << 60) |
            (seed & ((uint256(1) << 60) - 1))
        );
    }

    /// @dev Pack one spin's reel into `packedSpins` at slot `i` (72 bits): player ticket,
    ///      result ticket, score. OR the returned word into the accumulator.
    function _packSpin(uint256 i, SpinResult memory spin) private pure returns (uint256) {
        return
            (uint256(spin.playerTraits) |
                (uint256(spin.resultTraits) << 32) |
                (uint256(spin.score) << 64)) << (i * 72);
    }

    /// @notice One WWXRP Degenerette spin staking a lootbox WWXRP roll (replaces the flat mint).
    /// @dev Uses the 5% reel rig, shared table and 70–130% activity target before token rounding.
    ///      Stake is in 10^18 sub-units per WWXRP. The final payout converts to whole
    ///      WWXRP with a minimum of one for a positive sub-token win; a loss stays zero.
    ///      Returned for the calling box or foil entry to mint its WWXRP lane once.
    function resolveWwxrpSpinFromBox(
        uint32 playerId,
        uint256 stake,
        uint16 activityScore,
        uint256 seed,
        uint8 symbol
    ) external payable returns (uint256 wwxrpOut) {
        return _boxResolveWwxrpSpinFromBox(playerId, stake, activityScore, seed, symbol);
    }

    function _boxResolveWwxrpSpinFromBox(
        uint32 playerId,
        uint256 stake,
        uint16 activityScore,
        uint256 seed,
        uint8 symbol
    ) internal override returns (uint256 wwxrpOut) {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if (stake == 0 || stake > type(uint128).max) return 0;
        uint64 betId = _boxBetId(seed, BOX_SPIN_TYPE_WWXRP);
        seed = EntropyLib.hash2(seed, WWXRP_DRAW_TAG);
        uint128 betAmount = uint128(stake);

        SpinResult memory spin = _rollSpin(seed, EntropyLib.hash2(seed, RESULT_TICKET_TAG), symbol, CURRENCY_WWXRP);
        uint256 rawPayout = _degenerettePayout(spin, CURRENCY_WWXRP, betAmount, activityScore);
        uint256 payout = rawPayout / TOKEN_MATH_SCALE;
        if (payout == 0 && rawPayout != 0) payout = 1;

        // Returned, not minted: the caller sums every WWXRP lane in the entry and mints once.
        wwxrpOut = payout;

        // One self-contained record: the single reel + WWXRP-minted payout (no ETH split).
        emit BoxSpin(
            playerId,
            betId,
            _packSpin(0, spin) |
                (uint256(1) << BOX_SPIN_COUNT_SHIFT),
            payout,
            0
        );
    }

    /// @notice Three FLIP Degenerette spins under one survival flip (FLIP-only, safe on any box).
    /// @dev Stake uses 10^18 sub-units per FLIP. The split drops at most two sub-units;
    ///      spin payouts retain this precision until their sum completes the double-or-
    ///      nothings on one fair flip (EV-neutral) and is returned for the box entry's FLIP
    ///      lane (credited via coinflip.creditFlip at flush). No pool / ETH / recirc touch, so
    ///      this is solvency-safe on every box path including recirc.
    function resolveFlipSpinsFromBox(
        uint32 playerId,
        uint256 totalStake,
        uint16 activityScore,
        uint256 seed,
        uint8 symbol
    ) external payable returns (uint256 flipOut) {
        return _boxResolveFlipSpinsFromBox(playerId, totalStake, activityScore, seed, symbol);
    }

    function _boxResolveFlipSpinsFromBox(
        uint32 playerId,
        uint256 totalStake,
        uint16 activityScore,
        uint256 seed,
        uint8 symbol
    ) internal override returns (uint256 flipOut) {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        // Returned, not minted: the caller sums every FLIP lane in the entry and credits once.
        return
            _flipSpinChain(
                playerId,
                totalStake,
                activityScore,
                seed,
                symbol,
                BOX_SPIN_TYPE_FLIP
            );
    }

    /// @dev Shared automatic/record FLIP chain. Record and foil awards retain
    ///      a chosen symbol; random box awards pass 32. Every spin rerolls colors. Returns the
    ///      whole-FLIP result; every caller credits or mints it.
    function _flipSpinChain(
        uint32 playerId,
        uint256 totalStake,
        uint16 activityScore,
        uint256 seed,
        uint8 symbol,
        uint8 spinType
    ) private returns (uint256 minted) {
        if (totalStake == 0) return 0;
        uint256 perSpinAmount = totalStake / BOX_FLIP_SPINS;
        if (perSpinAmount == 0 || perSpinAmount > type(uint128).max) return 0;
        uint128 perSpin = uint128(perSpinAmount);
        uint64 betId = _boxBetId(seed, spinType);

        uint256 total;
        uint256 packedSpins;
        for (uint256 i; i < BOX_FLIP_SPINS; ) {
            uint256 ss = EntropyLib.hash2(seed, i);
            SpinResult memory spin = _rollSpin(ss, EntropyLib.hash2(ss, RESULT_TICKET_TAG), symbol, CURRENCY_FLIP);
            total += _degenerettePayout(spin, CURRENCY_FLIP, perSpin, activityScore);
            packedSpins |= _packSpin(i, spin);
            unchecked {
                ++i;
            }
        }

        // Survival flip on the summed payout (the seed bit never otherwise consumed by the spins).
        bool survived = total != 0 &&
            (EntropyLib.hash2(seed, BOX_SURVIVAL_TAG) & 1 == 1);
        total = survived ? total * 2 : 0;
        total /= TOKEN_MATH_SCALE;
        // Collapse the surviving mint onto a whole 100-FLIP multiple, EV-preserving, above
        // the threshold; a minimum box stakes about 13 FLIP at the milestone price, so
        // smaller spins keep the whole-FLIP floor rather than round to nothing. The box seed
        // is immutable per box and keyed here under its own tag, distinct from the survival
        // draw.
        total = total > FlipRoundLib.FLIP_ROUND_THRESHOLD
            ? FlipRoundLib.roundFlipToHundreds(
                total,
                EntropyLib.hash2(seed, FLIP_ROUND_TAG)
            )
            : FlipRoundLib.floorWholeFlip(total);
        // The box caller sums this into the entry's FLIP lane; the record-bounty caller adds it
        // to the owner's batched FLIP mint.
        minted = total;

        // One self-contained record: all three reels + count + survival + the final FLIP mint.
        packedSpins |=
            (uint256(BOX_FLIP_SPINS) << BOX_SPIN_COUNT_SHIFT) |
            (survived ? (uint256(1) << BOX_SPIN_SURVIVED_SHIFT) : 0);
        emit BoxSpin(playerId, betId, packedSpins, total, 0);
    }

    /// @notice One ETH Degenerette spin staking a lootbox roll's ticket budget.
    /// @dev Reuses the regular 3-tier ETH split (`_distributePayout`): the ETH share credits
    ///      claimable and the lootbox share recircs into a fresh re-hashed box. This spin's
    ///      pool/claimable writes are flushed to storage BEFORE the recirc so the recirc reads
    ///      fresh state, and the recirc box is opened with the ETH-spin path disabled (the box
    ///      module passes allowEthSpin=false on the recirc entry) so no ETH-spin can cascade.
    function resolveEthSpinFromBox(
        uint32 playerId,
        uint256 stake,
        uint16 activityScore,
        uint256 seed,
        uint8 symbol
    ) external payable {
        _boxResolveEthSpinFromBox(playerId, stake, activityScore, seed, symbol);
    }

    function _boxResolveEthSpinFromBox(
        uint32 playerId,
        uint256 stake,
        uint16 activityScore,
        uint256 seed,
        uint8 symbol
    ) internal override {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if (stake == 0 || stake > type(uint128).max) return;
        uint64 betId = _boxBetId(seed, BOX_SPIN_TYPE_ETH);
        uint128 betAmount = uint128(stake);

        SpinResult memory spin = _rollSpin(seed, EntropyLib.hash2(seed, RESULT_TICKET_TAG), symbol, CURRENCY_ETH);
        uint8 s = spin.score;
        uint256 payout = _degenerettePayout(spin, CURRENCY_ETH, betAmount, activityScore);

        uint256 packed = _packSpin(0, spin) |
            (uint256(1) << BOX_SPIN_COUNT_SHIFT);
        if (payout == 0) {
            emit BoxSpin(playerId, betId, packed, 0, 0);
            return;
        }

        ResolveAcc memory acc;
        acc.ownerId = playerId;
        // A box spin stakes a lootbox roll's budget rather than a placed bet, so it
        // never touches the biggest-spin record — that arms only on a placed ETH
        // bet's total wager (amountPerSpin x spinCount).
        (uint256 lootboxShare, ) = _distributePayout(
            playerId,
            CURRENCY_ETH,
            betAmount,
            payout,
            acc
        );
        if (s >= 7) _awardDegeneretteDgnrs(acc, betAmount, s);

        // Flush THIS spin's pool/claimable BEFORE recirc so recirc reads fresh storage.
        if (acc.ethClaimable != 0) _addClaimableEth(playerId, acc.ethClaimable);
        if (acc.poolLoaded) {
            if (acc.poolFrozen) {
                _setPendingPools(acc.pendingNext, acc.pendingFuture);
            } else {
                _setFuturePrizePool(acc.runningFuture);
            }
        }

        // One self-contained record: the reel + ETH gross + the claimable share. The
        // recirculated remainder (payout - ethShare) is itemized by the recirc box's own events.
        emit BoxSpin(playerId, betId, packed, payout, acc.ethClaimable);

        // Recirc into a fresh re-hashed box; allowEthSpin=false there -> no ETH-spin cascade.
        // The recirculated box's contents are itemized for the UI via its own LootBoxOpened.
        if (lootboxShare != 0) {
            // Keep this frame so the box resolver has no static recursion path.
            (bool ok, bytes memory data) = ContractAddresses.GAME_LOOTBOX_MODULE.delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameLootboxModule.resolveLootboxDirect.selector,
                    playerId,
                    lootboxShare,
                    EntropyLib.hash2(seed, BOX_RECIRC_TAG),
                    activityScore
                )
            );
            if (!ok) {
                if (data.length == 0) revert EmptyRevert();
                assembly ("memory-safe") {
                    revert(add(32, data), mload(data))
                }
            }
        }
    }
}
