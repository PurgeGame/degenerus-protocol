// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

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
    IDegenerusGameLootboxModule,
    IDegenerusGameBoonModule
} from "../interfaces/IDegenerusGameModules.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
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
contract DegenerusGameDegeneretteModule is
    DegenerusGamePayoutUtils,
    DegenerusGameMintStreakUtils
{
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    // error E() — inherited from DegenerusGameStorage

    /// @notice Thrown when the bet index's RNG word is in the wrong state for the call:
    ///         already landed at placement (a bet binds to a still-unrevealed index), or
    ///         still absent at a manual resolution.
    error RngNotReady();

    /// @notice Thrown when bet parameters are invalid (zero amount, below minimum, invalid spec, etc.).
    error InvalidBet();

    /// @notice Thrown when an unsupported currency type is specified.
    error UnsupportedCurrency();

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a Degenerette bet is placed.
    /// @param player The bet owner (the address paid when it resolves).
    /// @param index The lootbox RNG index this bet is tied to.
    /// @param betId The bet's id within `index`: its queue position + 1.
    /// @param packed The queued bet word (layout on DegenerusGameStorage.degeneretteQueue).
    event DegeneretteBetPlaced(
        address indexed player,
        uint32 indexed index,
        uint64 indexed betId,
        uint256 packed
    );

    /// @notice Paid ETH on a protocol deity's hero enters its next-day boon draw.
    event ProtocolBoonDrawEntered(
        address indexed issuer,
        address indexed player,
        uint24 indexed day,
        uint256 amount,
        uint16 scoreSnapshot,
        uint64 weight,
        uint32 entryIndex
    );

    /// @notice Emitted once per resolved Degenerette bet, carrying every spin.
    /// @param player The bet owner (paid).
    /// @param index The lootbox RNG index the bet resolved against.
    /// @param betId The bet's id within `index` (queue position + 1).
    /// @param totalPayout Total payout across all spins. For a FLIP bet the summed spin
    ///        payouts double or zero on the bet's survival flip, then collapse to a whole-FLIP
    ///        floor or, above FLIP_ROUND_THRESHOLD, a 100-FLIP multiple (FlipRoundLib).
    /// @param resultTraits The spin-0 house result traits.
    /// @param spins Five bytes per spin, spin 0 first: the player's traits (4 bytes,
    ///        big-endian), then score S (low 4 bits, 0-9) | matched gold (bits 4-6). Each
    ///        spin's payout follows from these plus the bet's stake and activity score.
    event DegeneretteResolved(
        address indexed player,
        uint32 indexed index,
        uint64 indexed betId,
        uint256 totalPayout,
        uint32 resultTraits,
        bytes spins
    );

    /// @notice Emitted when ETH payout exceeds pool cap and excess is converted to lootbox.
    /// @param player The player address.
    /// @param cappedEthPayout The ETH payout after capping.
    /// @param excessConverted Total ETH routed to the lootbox for this spin — the 3-tier split remainder plus the pool-cap overflow (= payout − cappedEthPayout).
    event PayoutCapped(
        address indexed player,
        uint256 cappedEthPayout,
        uint256 excessConverted
    );

    /// @notice A stake resolved as a Degenerette spin outside the ordinary bet flow — a lootbox
    ///         roll (WWXRP / FLIP×3 / ETH) or a biggest-spin record bounty (FLIP×3) — the single
    ///         self-contained record of that outcome (placed bets report through
    ///         DegeneretteResolved instead). Every reel + every output reward is here or, for
    ///         the ETH recirc, in the fresh box's own (now-emitted) events.
    /// @param player The reward recipient.
    /// @param betId Self-classifying id: bit 63 = synthetic-origin sentinel, bits 62-60 = spin type
    ///        (0=WWXRP, 1=FLIP, 2=ETH, 3=record bounty), bits 59-0 = seed entropy (unique per spin).
    /// @param packedSpins Per-spin reels packed low→high, each spin = [playerTraits:32 |
    ///        resultTraits:32 | score:8] (72 bits, spin 0 lowest); bits 216-223 = spin count;
    ///        bit 224 = FLIP survival flag (1 = the survival flip won; unused for WWXRP/ETH);
    ///        bits 225-230 = 2-bit hero quadrants for spins 0/1/2.
    /// @param payout Total reward: WWXRP requested (before WWXRP's gameMintScale), FLIP (returned to the box caller and credited
    ///        through coinflip at flush; only the record-bounty chain mints here), or the ETH
    ///        gross (= ethShare + the recirc).
    /// @param ethShare ETH credited to the player's claimable winnings (0 for WWXRP/FLIP). The
    ///        recirculated remainder is derivable as `payout - ethShare` (ETH only); that recirc
    ///        box emits its own LootBoxOpened / BoxSpin so its contents are itemized.
    event BoxSpin(
        address indexed player,
        uint64 betId,
        uint256 packedSpins,
        uint256 payout,
        uint256 ethShare
    );

    // -------------------------------------------------------------------------
    // Internal Helpers
    // -------------------------------------------------------------------------

    /// @dev Reverts with the provided reason bytes from a delegatecall failure.
    /// @param reason The revert reason bytes from the failed call.
    function _revertDelegate(bytes memory reason) private pure {
        if (reason.length == 0) revert EmptyRevert();
        assembly ("memory-safe") {
            revert(add(32, reason), mload(reason))
        }
    }

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

    /// @dev Bonus ROI for ETH bets in basis points (+5%), redistributed to high buckets.
    uint16 private constant ETH_ROI_BONUS_BPS = 500;

    /// @dev Maximum ETH payout as percentage of futurePool in basis points (10%).
    uint16 private constant ETH_WIN_CAP_BPS = 1_000;

    /// @dev sDGNRS contract reference for degenerette DGNRS rewards
    IsDGNRS private constant sdgnrs =
        IsDGNRS(ContractAddresses.SDGNRS);

    /// @dev Degenerette DGNRS reward BPS (per ETH wagered, % of remaining Reward pool),
    ///      keyed on the top-3 score tiers S=7/8/9.
    uint16 private constant DEGEN_DGNRS_7_BPS = 400; // S=7: 4% per ETH
    uint16 private constant DEGEN_DGNRS_8_BPS = 800; // S=8: 8% per ETH
    uint16 private constant DEGEN_DGNRS_9_BPS = 1500; // S=9: 15% per ETH

    /// @dev Currency type identifier for ETH.
    uint8 private constant CURRENCY_ETH = 0;

    /// @dev Currency type identifier for FLIP token.
    uint8 private constant CURRENCY_FLIP = 1;

    /// @dev Internal reward-spin currency; unavailable to player-funded bets.
    uint8 private constant CURRENCY_WWXRP = 3;

    /// @dev Minimum bet amount for ETH (0.005 ETH on mainnet).
    uint256 private constant MIN_BET_ETH = 5 ether / 1000;

    /// @dev Minimum bet amount for FLIP (100 tokens with 18 decimals).
    uint256 private constant MIN_BET_FLIP = 100 ether;

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
    // to. Placement already refuses an index whose word is revealed, so the claim
    // is armed against an unknown word by construction — the same freeze the bet's
    // own spins rest on.

    /// @dev Entry floor for the record path, on the bet's total ETH. A bet under this
    ///      never pays the record call at all, which keeps the external arm off the
    ///      overwhelming majority of ETH bets. Sound because the record is only ever
    ///      written by a bet that cleared this floor, so it is always 0 or >= the
    ///      floor: a smaller bet could not have beaten it anyway. The floor is the
    ///      record's bootstrap minimum.
    uint256 private constant BIGGEST_SPIN_MIN_ETH = 1 ether;

    /// @dev Maximum spins per bet, per currency (encoded as ticketCount in the packed bet).
    uint8 private constant MAX_SPINS_ETH = 25;
    uint8 private constant MAX_SPINS_FLIP = 15;

    // -------------------------------------------------------------------------
    // Quick Play Constants
    // -------------------------------------------------------------------------

    /// @dev Salt for quick play ticket generation.
    bytes1 private constant QUICK_PLAY_SALT = 0x51; // 'Q'

    // Shared score table: neutral EV includes the matched-gold multiplier.
    // Derived and checked by scripts/data/degenerette_single_symbol_math.py.
    // Scores 0..7 are packed in 32-bit centi-x lanes; 8/9 are separate.
    uint256 private constant QUICK_PLAY_PAYOUTS_PACKED = 0x0000f424000030d4000009c4000003e80000012c000000320000000000000000;
    uint256 private constant QUICK_PLAY_PAYOUT_S8 = 2_347_036;
    uint256 private constant QUICK_PLAY_PAYOUT_S9 = 10_000_000;
    // ETH's +5 percentage points, 10/30/30/30 EV allocation to scores 6/7/8/9.
    uint256 private constant ETH_BONUS_FACTORS_PACKED = 0x0000000002aaaaaa00000000003c513900000000006cdd2100000000000f7734;
    uint256 private constant BONUS_FACTOR_SCALE = 1_000_000;
    // WWXRP keeps the shared score table. Normalize its rigged/gold base to 70%,
    // then allocate activity's extra 0..60 percentage points to scores 6..9.
    uint256 private constant WWXRP_FLOOR_SCALED = 5_839_907_998;
    uint256 private constant WWXRP_BONUS_FACTORS_PACKED = 0x0000000002aaaaaa00000000001d6c4d000000000046626100000000000bb73b;
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
    // A bet is one word in degeneretteQueue[index] (full layout on the storage declaration):
    // owner [0..159] | symbol [160..164] | spinCount [165..169] | currency [170] |
    // record flag [171] | activity score [172..187] | stake per spin in units [188..251].
    // The bet id is the queue position + 1, so the index and id need no bits.
    //
    /// Every symbol choice has the same distribution. Fresh uniform colors,
    /// independent color scoring, and matched-gold boosts share one payout table.
    /// Internal WWXRP reward spins add a 5% help gate and a 70–130% activity target.
    //
    // -------------------------------------------------------------------------

    uint256 private constant BET_SYMBOL_SHIFT = 160;
    uint256 private constant BET_COUNT_SHIFT = 165;
    uint256 private constant BET_CURRENCY_SHIFT = 170;
    uint256 private constant BET_RECORD_FLAG = uint256(1) << 171;
    uint256 private constant BET_ACTIVITY_SHIFT = 172;
    uint256 private constant BET_STAKE_SHIFT = 188;

    /// @dev Stake units. An ETH stake is whole gwei and a FLIP stake whole FLIP, so 64 bits
    ///      cover any stake (about 1.8e10 ETH or 1.8e19 FLIP per spin). Placement rejects an
    ///      amount that is not a whole unit; a boon bonus floors to the unit.
    uint256 private constant ETH_STAKE_UNIT = 1 gwei;
    uint256 private constant FLIP_STAKE_UNIT = 1 ether;

    /// @dev Sweep BUDGET price of one bet in the shared walk unit (~4.7k gas, see
    ///      OPEN_HUMAN_ENTRY_WEIGHT): an entry floor plus a per-spin weight, read off the bet
    ///      word before it runs, so the crank's work stays a pure function of state. Sized for
    ///      the worst case so a call stays bounded: the ETH floor carries the one win box an ETH
    ///      bet can open, and an armed record adds its three-spin FLIP chain. A zeroed (already
    ///      resolved) word costs one unit to skip. Measured sweep cost per bet (warm): ~6.5k base,
    ///      ~2.5k per spin, ~57k for a win box, and up to ~169k for a cold 1-spin ETH bet whose
    ///      spin scores 7+ (win box plus the sDGNRS award). Outcomes key on
    ///      (word, index, symbol, spin), not the owner, so every bet on one symbol at one index
    ///      hits together; the ETH floor prices that case, never an average.
    uint256 private constant BET_ENTRY_WEIGHT_ETH = 36;
    uint256 private constant BET_ENTRY_WEIGHT_FLIP = 4;
    uint256 private constant BET_SPIN_WEIGHT_ETH = 2;
    uint256 private constant BET_SPIN_WEIGHT_FLIP = 1;
    uint256 private constant BET_RECORD_WEIGHT = 6;

    /// @dev Keeper-bounty CREDIT per resolved bet, in gas: one small flat amount (~0.3 walk unit)
    ///      whatever the bet's spins or win box, and nothing for a zeroed slot, so settled bets add
    ///      only a sliver to the bounty. Placing a bet costs ~100k gas, so placing bets to crank
    ///      them yourself only pays below ~0.05 gwei, and then only dust (house edge ignored;
    ///      pinned by KeeperFaucetResistance GAS-06). Summed per sweep call and floored to walk
    ///      units; the budget still charges each bet its worst-case weight.
    uint256 private constant BET_WORK_CREDIT_GAS = 1_500;
    uint256 private constant BET_WORK_UNIT_GAS = 4_700;

    // Common masks
    uint256 private constant MASK_5 = 0x1F;
    uint256 private constant MASK_16 = 0xFFFF;
    uint256 private constant MASK_64 = 0xFFFFFFFFFFFFFFFF;

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    /// @notice Places a Degenerette bet with one chosen symbol and a generated ticket.
    /// @dev Single chosen-attribute pick.
    ///      spinCount is treated as "spin count": each spin resolves independently but shares
    ///      the same lootbox RNG index/word (derived per spin).
    ///      The bet always belongs to `player` (zero address = caller). Funding source: the
    ///      player or an approved operator spends the player's funds; any other caller funds the
    ///      bet itself — a permissionless gift (the caller pays, the player receives the bet and
    ///      its winnings).
    /// @param player The player the bet belongs to (use zero address for msg.sender).
    /// @param currency Currency type (0=ETH, 1=FLIP; all other values unsupported).
    /// @param amountPerSpin Bet amount per ticket.
    /// @param spinCount Number of spins (per-currency cap: ETH 25 / FLIP 15).
    /// @param symbol Chosen hero symbol (0..31); quadrant = symbol >> 3.
    function placeDegeneretteBet(
        address player,
        uint8 currency,
        uint128 amountPerSpin,
        uint8 spinCount,
        uint8 symbol
    ) external payable {
        // Closed from the liveness trigger on, matching the settlement side: resolution
        // already reverts there, so a bet placed after it can never pay out. The stake is
        // real value — an ETH bet moves fresh ETH into the pools — and it is lost either
        // way: distributed by the terminal drain before game over, swept to the terminal
        // sinks after it, and simply trapped once the one-shot final sweep has run.
        if (_livenessTriggered()) revert GameOver();
        if (player == address(0)) player = msg.sender;
        address funder;
        if (player == msg.sender || operatorApprovals[player][msg.sender]) {
            // The player or an approved operator spends the player's own funds.
            funder = player;
        } else {
            // Permissionless gift: the caller funds, the player receives the bet.
            funder = msg.sender;
        }
        _placeDegeneretteBet(
            player,
            funder,
            currency,
            amountPerSpin,
            spinCount,
            symbol
        );
    }

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
        address owner; // whose payouts ethClaimable / flipMint currently hold
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

    /// @notice Resolves queued bets at one RNG index ahead of the sweep.
    /// @dev Permissionless: payouts always credit each bet's owner, so any caller may settle
    ///      any bet; the mineFlip sweep resolves every bet without being asked. The first id
    ///      fail-fasts on an already-resolved or unknown bet so a racing duplicate settle
    ///      bails cheaply; later ids skip instead. ETH/FLIP payouts accumulate per owner and
    ///      flush once per owner run; the prize-pool running local is written once.
    /// @param index Lootbox RNG index the bets were placed at.
    /// @param betIds Bet ids within `index` (queue position + 1).
    function resolveDegeneretteBets(uint48 index, uint64[] calldata betIds) external {
        // Once game-over liveness has drained the balance into claimable, resolving a
        // pending bet would credit ETH claimable out of the already-distributed
        // futurePrizePool residual, pushing claimablePool above the ETH balance
        // (unbacked obligation). Pending bets are NOT settled by the game-over drain: their
        // stakes stay in the pools the terminal distribution already paid out.
        if (_livenessTriggered()) revert GameOver();
        uint256 rngWord = lootboxRngWordByIndex[index];
        if (rngWord == 0) revert RngNotReady();
        uint256[] storage queue = degeneretteQueue[index];
        uint256 qlen = queue.length;
        ResolveAcc memory acc;
        uint256 len = betIds.length;
        for (uint256 i; i < len; ) {
            uint64 betId = betIds[i];
            uint256 bet = betId == 0 || betId > qlen ? 0 : queue[betId - 1];
            if (bet != 0) {
                queue[betId - 1] = 0;
                _resolveBet(bet, uint32(index), betId, rngWord, acc);
            } else if (i == 0) {
                revert InvalidBet();
            }
            unchecked {
                ++i;
            }
        }
        _flushOwner(acc);
        _flushPool(acc);
    }

    /// @notice Human-box sweep leg for bets: resolves the queue at `index` from `pos`.
    /// @dev Delegatecall target of the lootbox module's openHumanBoxes, which reaches a bet
    ///      queue only after that index's box entries and only once its word has landed.
    ///      Each bet is priced in walk units from its own word (see BET_ENTRY_WEIGHT_*) and
    ///      a zeroed word costs one unit to skip, so the call stays inside `budget`. The first
    ///      bet runs whatever it costs when `mustRunFirst` (nothing opened yet this call), so
    ///      no wide bet can wedge the cursor.
    /// @param index The swept RNG index.
    /// @param pos Queue position to resume from.
    /// @param budget Walk units left in the crank call.
    /// @param mustRunFirst True when the crank has opened nothing yet.
    /// @param rngWord The index's committed word (already loaded by the sweep).
    /// @return resolved Bets resolved.
    /// @return newPos Position to resume from (the queue length once drained).
    /// @return unitsSpent Walk units charged against the budget (worst-case prices).
    /// @return workUnits Walk units credited toward the keeper bounty: BET_WORK_CREDIT_GAS per
    ///         resolved bet, floored; zeroed slots credit nothing.
    function sweepDegeneretteBets(
        uint48 index,
        uint256 pos,
        uint256 budget,
        bool mustRunFirst,
        uint256 rngWord
    ) external returns (uint256 resolved, uint256 newPos, uint256 unitsSpent, uint256 workUnits) {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        // The frozen-pool ETH path reverts Insolvent when the pending buffer runs short, and a
        // revert here would stall the whole box frontier behind this queue. The freeze only
        // runs inside the RNG lock the sweep already waits out; hold the queue while it is up.
        if (prizePoolFrozen) return (0, pos, 0, 0);
        uint256[] storage queue = degeneretteQueue[index];
        uint256 qlen = queue.length;
        ResolveAcc memory acc;
        while (pos < qlen && unitsSpent < budget) {
            uint256 bet = queue[pos];
            if (bet == 0) {
                unchecked {
                    ++pos;
                    ++unitsSpent;
                }
                continue;
            }
            uint256 cost = _betWeight(bet);
            // BREAK, never skip: the cursor is monotonic, so a bet that does not fit stays
            // at the cursor for the next call's fresh budget.
            if ((resolved != 0 || !mustRunFirst) && unitsSpent + cost > budget) break;
            queue[pos] = 0;
            unchecked {
                ++pos;
                unitsSpent += cost;
                ++resolved;
            }
            _resolveBet(bet, uint32(index), uint64(pos), rngWord, acc);
        }
        _flushOwner(acc);
        _flushPool(acc);
        newPos = pos;
        workUnits = (resolved * BET_WORK_CREDIT_GAS) / BET_WORK_UNIT_GAS;
    }

    /// @dev Worst-case walk-unit budget price of one queued bet.
    function _betWeight(uint256 bet) private pure returns (uint256 weight) {
        uint256 spins = (bet >> BET_COUNT_SHIFT) & MASK_5;
        weight = (bet >> BET_CURRENCY_SHIFT) & 1 == CURRENCY_ETH
            ? BET_ENTRY_WEIGHT_ETH + spins * BET_SPIN_WEIGHT_ETH
            : BET_ENTRY_WEIGHT_FLIP + spins * BET_SPIN_WEIGHT_FLIP;
        if (bet & BET_RECORD_FLAG != 0) weight += BET_RECORD_WEIGHT;
    }

    /// @dev Pay the current owner's accumulated FLIP and ETH, then clear them.
    function _flushOwner(ResolveAcc memory acc) private {
        if (acc.flipMint != 0) {
            coin.mintForGame(acc.owner, acc.flipMint);
            acc.flipMint = 0;
        }
        if (acc.ethClaimable != 0) {
            _addClaimableEth(acc.owner, acc.ethClaimable);
            acc.ethClaimable = 0;
        }
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

    /// @dev Internal implementation for placing a Degenerette bet. The bet and its winnings
    ///      belong to `player`; the funds are debited from `funder` (== player for a
    ///      self/approved bet, == the caller for a permissionless gift), and the quest
    ///      progress goes to `funder` — the spender earns the quest.
    function _placeDegeneretteBet(
        address player,
        address funder,
        uint8 currency,
        uint128 amountPerSpin,
        uint8 spinCount,
        uint8 symbol
    ) private {
        uint24 lvl = level;
        uint256 totalBet = _placeDegeneretteBetCore(
            player,
            currency,
            amountPerSpin,
            spinCount,
            symbol,
            lvl,
            funder == player
        );

        _collectBetFunds(funder, currency, totalBet);

        // Quest progress for Degenerette bets (slot 1 only) — credited to the funder (the
        // spender earns the quest, e.g. a gifter advancing their own streak).
        quests.handleDegenerette(
            funder,
            totalBet,
            currency == CURRENCY_ETH,
            currency == CURRENCY_ETH
                ? PriceLookupLib.priceForLevel(lvl + 1)
                : 0
        );
    }

    function _placeDegeneretteBetCore(
        address player,
        uint8 currency,
        uint128 amountPerSpin,
        uint8 spinCount,
        uint8 symbol,
        uint24 lvl,
        bool selfFunded
    ) private returns (uint256 totalBet) {
        // Only ETH and FLIP may fund a player bet. WWXRP remains an internal
        // reward-spin currency and never enters the bet book.
        uint8 maxSpins;
        uint256 minBet;
        uint256 unit;
        if (currency == CURRENCY_ETH) {
            maxSpins = MAX_SPINS_ETH;
            minBet = MIN_BET_ETH;
            unit = ETH_STAKE_UNIT;
        } else if (currency == CURRENCY_FLIP) {
            maxSpins = MAX_SPINS_FLIP;
            minBet = MIN_BET_FLIP;
            unit = FLIP_STAKE_UNIT;
        } else {
            revert UnsupportedCurrency();
        }
        if (spinCount == 0 || spinCount > maxSpins) revert InvalidBet();
        if (uint256(amountPerSpin) < minBet || uint256(amountPerSpin) % unit != 0) revert InvalidBet();
        if (symbol >= 32) revert InvalidBet();
        uint8 heroQuadrant = symbol >> 3;

        uint48 index = uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK));
        if (index == 0) revert NotStarted();
        if (lootboxRngWordByIndex[index] != 0) revert RngNotReady();

        totalBet = uint256(amountPerSpin) * uint256(spinCount);
        // Decay-aware effective quest streak: a streak
        // lapsed past its shields reads 0, so a returning-inactive player can't snapshot a
        // stale-high streak into the bet's activityScore (which scales the ETH ROI and the
        // lootbox-share EV multiplier). This snapshot precedes the new bet's quest credit.
        uint32 questStreak = _effectiveQuestStreak(player);
        uint16 activityScore = uint16(
            _playerActivityScore(player, questStreak, lvl + 1)
        );

        // ETH-only per-bet bookkeeping: the biggest-spin record and the daily hero
        // wager ledger, sharing one currency branch.
        uint256 recordBounty;
        if (currency == CURRENCY_ETH) {
            uint24 day = _simulatedDayIndex();
            // Gate the record behind the entry floor: a bet under it can never hold
            // the record, so skipping the call costs no outcome and keeps the external
            // arm off the bets that make up nearly all ETH volume. The candidate is
            // the bet's TOTAL ETH — the whole transaction's wager, spins included.
            // Gifted bets arm normally: the ETH is real and the record belongs to
            // `player`.
            //
            // The claim does not pay out here. It waits beside the queued bet as whole FLIP
            // and resolves as its own FLIP spin chain off the very word THIS bet is
            // already bound to — an index whose word the gate above proved unrevealed,
            // so a claim can never be armed against a known word. Beating the
            // biggest-spin record therefore buys a spin, not flip credit.
            if (totalBet >= BIGGEST_SPIN_MIN_ETH) {
                uint256 whole = coinflip.armRecord(
                    RECORD_KIND_SPIN,
                    player,
                    totalBet
                ) / LR_FLIP_SCALE;
                recordBounty = whole;
            }

            // Daily hero symbol tracking (heroQuadrant validated to {0..3} above)
            uint8 heroSymbol = symbol & 7;
            uint256 wagerUnit = totalBet / 1e14;
            if (wagerUnit > 0) {
                uint256 wPacked = dailyHeroWagers[day][heroQuadrant];
                uint256 shift = uint256(heroSymbol) * 32;
                uint256 current = (wPacked >> shift) & 0xFFFFFFFF;
                uint256 updated = current + wagerUnit;
                if (updated > 0xFFFFFFFF) updated = 0xFFFFFFFF;
                wPacked =
                    (wPacked & ~(uint256(0xFFFFFFFF) << shift)) |
                    (updated << shift);
                dailyHeroWagers[day][heroQuadrant] = wPacked;
            }
            if (symbol == 0 || symbol == 6) {
                // Canonical boon score uses the routed ticket level. Reuse the
                // effective quest streak already read, before this bet's quest credit.
                uint16 boonScore = _activeTicketLevel() == lvl + 1
                    ? activityScore
                    : uint16(_playerActivityScore(player, questStreak));
                _enterProtocolBoonDraw(
                    player, symbol, day, totalBet, wagerUnit, boonScore
                );
            }
        }

        // Degenerette stake boon: consumed here, AFTER every raw-stake consumer above (the
        // biggest-spin record, the daily hero wager ledger, and the caller's `totalBet` —
        // which funds collection and the pool credit). The bonus rides the PACKED bet only,
        // so the player spins on more than they paid without any unfunded ETH entering the
        // pools. ETH solvency is unaffected: an ETH win is capped at a share of the live pool
        // at distribution time, never at the bet's own size.
        //
        // Self-or-operator-funded bets only, mirroring the coinflip deposit boon's funder
        // gate: a permissionless gift must never spend the recipient's boon (a dust gift
        // could burn it), so a gifted bet skips even the lane read. The bet's own currency
        // lane is read inline first (this module shares the Game's storage), so a player
        // holding no boon in THIS currency — the overwhelmingly common case — pays one
        // SLOAD instead of a nested dispatch; boons in the other currency lanes are
        // untouched by construction.
        uint256 stakeUnits = uint256(amountPerSpin) / unit;
        uint16 boonBps;
        if (
            selfFunded &&
            ((boonPacked[player].slot1 >> _degeneretteLaneShift(currency)) &
                BP_LANE_TIER_MASK) != 0
        ) {
            boonBps = _consumeDegeneretteBoon(player, currency);
        }
        if (boonBps != 0) {
            uint256 boostBase = totalBet;
            if (currency == CURRENCY_ETH) {
                if (boostBase > DEGENERETTE_BOON_ETH_CAP) boostBase = DEGENERETTE_BOON_ETH_CAP;
            } else if (currency == CURRENCY_FLIP) {
                if (boostBase > DEGENERETTE_BOON_FLIP_CAP) boostBase = DEGENERETTE_BOON_FLIP_CAP;
            }
            // Spread across the spins, then floor to the stake unit: integer division drops
            // the sub-unit dust, matching the whole-granule rounding of the other award paths.
            stakeUnits += ((boostBase * boonBps) / 10_000) / spinCount / unit;
        }
        if (stakeUnits > MASK_64) revert InvalidBet();

        // The bet itself is the sweep's queue entry: one word, appended at this index. Its
        // id is the queue position + 1, fixed here while the index word is still unset.
        uint256[] storage queue = degeneretteQueue[index];
        uint64 betId = uint64(queue.length + 1);
        uint256 bet =
            uint256(uint160(player)) |
            (uint256(symbol) << BET_SYMBOL_SHIFT) |
            (uint256(spinCount) << BET_COUNT_SHIFT) |
            (uint256(currency) << BET_CURRENCY_SHIFT) |
            (uint256(activityScore) << BET_ACTIVITY_SHIFT) |
            (stakeUnits << BET_STAKE_SHIFT);
        if (recordBounty != 0) {
            bet |= BET_RECORD_FLAG;
            degeneretteRecordBounty[(uint256(index) << 64) | betId] = recordBounty;
        }
        queue.push(bet);
        emit DegeneretteBetPlaced(player, uint32(index), betId, bet);
    }

    /// @dev Only ordinary ETH placements reach this helper. A gifted bet belongs
    ///      to its recipient; all weight is paid stake, before any boon boost.
    ///      Pool and entry writes revert atomically if later funding fails.
    function _enterProtocolBoonDraw(
        address player, uint8 symbol, uint24 day, uint256 amount, uint256 wagerUnits, uint16 score
    ) private {
        address issuer = symbol == 0 ? ContractAddresses.VAULT : ContractAddresses.SDGNRS;
        if (deityBySymbol[symbol] != issuer) return;
        uint256 weight = wagerUnits * ActivityCurveLib.boonDrawMultUnits(score);
        if (weight > type(uint64).max) revert InvalidBet();
        // The ring slot for `day` (see protocolBoonPools). One still tagged with an older day
        // starts over empty; its entries are overwritten from index 0.
        uint24 ring = day & 1;
        ProtocolBoonPool memory pool = protocolBoonPools[issuer][ring];
        if (pool.day != day) pool = ProtocolBoonPool(0, 0, 0, 0, day);
        uint32 index = pool.entryCount;
        uint64 cumulativeWeight = pool.totalWeight + uint64(weight);
        protocolBoonEntries[issuer][ring][index] = ProtocolBoonEntry(player, cumulativeWeight, score);
        // Weight <= uint64.max and multiplier >= 800 bound amount well below uint112.
        pool.totalWageredWei += uint112(amount);
        pool.totalWeight = cumulativeWeight;
        pool.entryCount = index + 1;
        protocolBoonPools[issuer][ring] = pool;
        emit ProtocolBoonDrawEntered(issuer, player, day, amount, score, uint64(weight), index);
    }

    /// @dev Processes bet funds (burn tokens, handle ETH, check pool).
    function _collectBetFunds(
        address player,
        uint8 currency,
        uint256 totalBet
    ) private {
        if (currency == CURRENCY_ETH) {
            // ETH covers the bet first; any shortfall draws claimable (to the 1-wei
            // sentinel) then afking via the canonical single-sink waterfall.
            if (msg.value > totalBet) revert InvalidBet();
            if (msg.value < totalBet) {
                _settleShortfall(player, totalBet - msg.value, true);
            }

            // Update pool and pending
            if (prizePoolFrozen) {
                (uint128 pNext, uint128 pFuture) = _getPendingPools();
                _setPendingPools(pNext, pFuture + uint128(totalBet));
            } else {
                (uint128 next, uint128 future) = _getPrizePools();
                _setPrizePools(next, future + uint128(totalBet));
            }
            _lrAdd(LR_PENDING_ETH_SHIFT, LR_PENDING_ETH_MASK, _packEthToMilliEth(totalBet));
            // No max payout check needed: ETH payouts are capped at 10% of pool at distribution
            // time, so solvency is guaranteed regardless of jackpot size
        } else if (currency == CURRENCY_FLIP) {
            coin.burnCoin(player, totalBet);
            _lrAdd(LR_PENDING_FLIP_SHIFT, LR_PENDING_FLIP_MASK, _packFlipToWhole(totalBet));
            // A token bet consumes no ETH; any ETH sent alongside it is absorbed to the funder's
            // withdrawable afking balance (solvency-preserving) rather than stranded in the pool.
            // Zero-value is a no-op, so a normal token bet pays no extra gas.
            _creditAfkingValue(player, msg.value);
        }
    }

    /// @dev Resolves one queued bet the caller has already zeroed in the queue: decodes the
    ///      word and materializes its spins against the index word. Per-currency payouts
    ///      accumulate into `acc` per owner (flushed by the caller or at the next owner);
    ///      lootbox-share is summed across this bet's spins and resolved ONCE here (one box
    ///      per bet). Every spin is recorded in the bet's single DegeneretteResolved event.
    function _resolveBet(
        uint256 bet,
        uint32 index,
        uint64 betId,
        uint256 rngWord,
        ResolveAcc memory acc
    ) private {
        address player = address(uint160(bet));
        if (player != acc.owner) {
            _flushOwner(acc);
            acc.owner = player;
        }
        uint8 symbol = uint8((bet >> BET_SYMBOL_SHIFT) & MASK_5);
        uint8 spinCount = uint8((bet >> BET_COUNT_SHIFT) & MASK_5);
        uint8 currency = uint8((bet >> BET_CURRENCY_SHIFT) & 1);
        uint16 activityScore = uint16((bet >> BET_ACTIVITY_SHIFT) & MASK_16);
        uint128 amountPerSpin = uint128(
            ((bet >> BET_STAKE_SHIFT) & MASK_64) *
                (currency == CURRENCY_ETH ? ETH_STAKE_UNIT : FLIP_STAKE_UNIT)
        );

        BetTotals memory totals;
        // Five bytes per spin: player traits (big-endian), then score | gold << 4.
        bytes memory spins = new bytes(uint256(spinCount) * 5);

        for (uint8 spinIdx; spinIdx < spinCount; ) {
            SpinResult memory spin = _rollBetSpin(rngWord, index, symbol, spinIdx, currency);
            if (spinIdx == 0) totals.firstResultTraits = spin.resultTraits;
            uint8 s = spin.score;
            uint256 payout = _degenerettePayout(spin, currency, amountPerSpin, activityScore);
            {
                uint256 traits = spin.playerTraits;
                uint256 tail = uint256(s) | (uint256(spin.goldMatches) << 4);
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
                    player,
                    currency,
                    amountPerSpin,
                    payout,
                    acc
                );
                // Bounded by maxSpins * amountPerSpin(uint128) * max payout factor —
                // ~15.7M below 2^256, so the per-spin accumulation cannot overflow.
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
            if (currency == CURRENCY_ETH && s >= 7) {
                _awardDegeneretteDgnrs(player, amountPerSpin, s);
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
        if (currency == CURRENCY_FLIP && totals.totalPayout != 0) {
            if (EntropyLib.hash4(rngWord, uint160(player), betId, BET_SURVIVAL_TAG) & 1 == 1) {
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
            // The roll is per-bet on a betId-keyed word, and that is load-bearing: settling
            // is permissionless and `betIds[]` is caller-composed, so rounding the summed
            // `acc.flipMint` at the flush instead would let a caller enumerate batch
            // partitions against the already-committed word and take the split with the
            // most round-ups. Keyed per bet, the outcome is fixed at fulfillment however the
            // bets are batched.
            uint256 rounded = totals.totalPayout > FlipRoundLib.FLIP_ROUND_THRESHOLD
                ? FlipRoundLib.roundFlipToHundreds(
                    totals.totalPayout,
                    EntropyLib.hash4(rngWord, uint160(player), betId, FLIP_ROUND_TAG)
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
                player,
                totals.betLootboxShare,
                EntropyLib.hash2(rngWord, betId),
                activityScore
            );
        }

        // Affiliate reward: 7% of the box value from high-match (s>=5) ETH spins, as FLIP
        // to the player's referrer (getReferrer returns VAULT when unreferred).
        if (totals.affiliateBoxShare > 0) {
            uint256 refFlip = (totals.affiliateBoxShare * PRICE_COIN_UNIT) /
                PriceLookupLib.priceForLevel(level + 1);
            coinflip.creditFlip(affiliate.getReferrer(player), (refFlip * 7) / 100);
        }

        emit DegeneretteResolved(
            player,
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
            delete degeneretteRecordBounty[key];
            _flipSpinChain(
                player,
                recordBounty * LR_FLIP_SCALE,
                activityScore,
                EntropyLib.hash4(rngWord, uint160(player), betId, RECORD_SPIN_TAG),
                symbol,
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
    /// @param player The player to receive the payout.
    /// @param currency The currency type (0=ETH, 1=FLIP).
    /// @param betAmount The per-ticket bet amount (uint128) — the tier-threshold reference.
    /// @param payout The total payout amount (uint256).
    /// @param acc Cross-bet accumulator: ETH claimable + the running prize-pool
    ///        local accumulate here (flushed once per resolveDegeneretteBets or
    ///        sweepDegeneretteBets call); FLIP
    ///        mint totals accumulate here too.
    /// @return lootboxShare The ETH lootbox-share for this spin (0 for FLIP),
    ///         summed by the caller into the per-bet box.
    /// @return paid What this spin actually pays out across both legs.
    function _distributePayout(
        address player,
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
            // have held — byte-identical to per-spin. Flushed once by resolveDegeneretteBets.
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
                    emit PayoutCapped(player, ethShare, lootboxShare);
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

    /// @dev Delegates to the boon module to consume the degenerette stake boon in this
    ///      bet's own currency lane. Returns 0 when the lane is empty or expired (an
    ///      expired lane is cleared); the other currencies' lanes are never touched.
    function _consumeDegeneretteBoon(
        address player,
        uint8 currency
    ) private returns (uint16 boonBps) {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_BOON_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameBoonModule.consumeDegeneretteBoon.selector,
                    player,
                    currency
                )
            );
        if (!ok) _revertDelegate(data);
        boonBps = abi.decode(data, (uint16));
    }

    /// @dev Delegates to the lootbox open module to resolve lootbox rewards directly.
    ///      Applies activity-score EV multiplier (90-145%) to match regular lootbox opens.
    ///      The resolved box itemizes its contents via `LootBoxOpened` like every box path.
    function _resolveLootboxDirect(
        address player,
        uint256 amount,
        uint256 rngWord,
        uint16 activityScore
    ) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_LOOTBOX_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameLootboxModule.resolveLootboxDirect.selector,
                    player,
                    amount,
                    rngWord,
                    activityScore
                )
            );
        if (!ok) _revertDelegate(data);
    }

    // -------------------------------------------------------------------------
    // Shared spin generation and scoring
    // -------------------------------------------------------------------------

    struct SpinResult {
        uint32 playerTraits;
        uint32 resultTraits;
        uint8 heroQuadrant;
        uint8 score;
        uint8 goldMatches;
    }

    /// @dev Every manual, box, foil and record spin uses this same reel/scoring path.
    /// The caller supplies its committed house seed; activity never enters the draw.
    function _rollSpin(uint256 seed, uint256 houseSeed, uint8 symbol, uint8 currency)
        internal pure returns (SpinResult memory spin)
    {
        symbol = _spinSymbol(seed, symbol);
        spin.heroQuadrant = symbol >> 3;
        spin.playerTraits = _playerTicket(seed, symbol);
        spin.resultTraits = DegenerusTraitUtils.packedTraitsDegenerette(houseSeed);
        if (currency == CURRENCY_WWXRP) {
            spin.resultTraits = _rigWwxrpResult(
                spin.playerTraits, spin.resultTraits, spin.heroQuadrant,
                EntropyLib.hash2(seed, WWXRP_RIG_SALT)
            );
        }
        (spin.score, spin.goldMatches) = _score(spin.playerTraits, spin.resultTraits, spin.heroQuadrant);
    }

    /// @dev The only fixed ticket component is the selected symbol (0..31).
    ///      Separate domains keep all colors independent of hero selection/results.
    function _playerTicket(uint256 seed, uint8 symbol) internal pure returns (uint32 traits) {
        if (symbol >= 32) revert InvalidBet();
        traits = DegenerusTraitUtils.packedTraitsDegenerette(EntropyLib.hash2(seed, PLAYER_TICKET_TAG));
        uint32 shift = uint32(symbol >> 3) * 8;
        traits = (traits & ~(uint32(7) << shift)) | (uint32(symbol & 7) << shift);
    }

    /// @dev Award spins may request a random hero with the internal sentinel 32.
    function _spinSymbol(uint256 seed, uint8 symbol) internal pure returns (uint8) {
        if (symbol > RANDOM_HERO) revert InvalidBet();
        return symbol == RANDOM_HERO ? uint8(EntropyLib.hash2(seed, HERO_PICK_TAG)) & 31 : symbol;
    }

    /// @dev Score and matched gold in one pass: hero symbol +2, other symbols +1,
    /// each matching color +1. Only gold-to-gold matches add the 25% payout boost.
    /// Branch-free: a lane's symbol (bits 0-2) or color (bits 3-5) matches iff all three bits
    /// of ~(player ^ result) are set there, so the match bits land on bit 0 / bit 3 of each
    /// lane byte, and one multiply sums the four lane bytes into the top byte. Gold is color 7
    /// (all three color bits set). A hero quadrant above 3 lands on no lane and adds nothing.
    function _score(uint32 playerTraits, uint32 resultTraits, uint8 heroQuadrant)
        internal pure returns (uint8 score, uint8 goldMatches)
    {
        assembly ("memory-safe") {
            let nd := not(xor(playerTraits, resultTraits))
            let m := and(nd, and(shr(1, nd), shr(2, nd)))
            let sm := and(m, 0x01010101)
            let cm := and(m, 0x08080808)
            let pg := and(and(playerTraits, and(shr(1, playerTraits), shr(2, playerTraits))), 0x08080808)
            score := add(
                add(shr(24, and(mul(sm, 0x01010101), 0xFF000000)), shr(27, and(mul(cm, 0x01010101), 0xF8000000))),
                and(shr(mul(8, and(heroQuadrant, 0xff)), sm), 1)
            )
            goldMatches := shr(27, and(mul(and(cm, pg), 0x01010101), 0xF8000000))
        }
    }

    /// @dev One table and matched-gold rule, with currency bonuses on scores 6–9.
    ///      WWXRP normalizes its rigged base to 70% and adds the activity surplus;
    ///      ETH adds five percentage points to its ordinary activity return.
    ///      Keep full precision through the final division. At uint128 max stake,
    ///      the bounded score/ROI/gold factors keep the numerator below 2^212.
    function _degenerettePayout(
        SpinResult memory spin,
        uint8 currency,
        uint128 betAmount,
        uint16 activityScore
    ) internal pure returns (uint256) {
        uint8 s = spin.score;
        uint256 base = _basePayoutCentiX(s);
        if (base == 0) return 0;
        uint256 scaledRoi;
        uint256 bonusBps;
        uint256 bonusFactors;
        if (currency == CURRENCY_WWXRP) {
            scaledRoi = WWXRP_FLOOR_SCALED;
            if (s >= 6) {
                bonusBps = _roiBpsFromScore(activityScore, true) - WWXRP_ROI_MIN_BPS;
                bonusFactors = WWXRP_BONUS_FACTORS_PACKED;
            }
        } else {
            scaledRoi = _roiBpsFromScore(activityScore, false) * BONUS_FACTOR_SCALE;
            if (currency == CURRENCY_ETH && s >= 6) {
                bonusBps = ETH_ROI_BONUS_BPS;
                bonusFactors = ETH_BONUS_FACTORS_PACKED;
            }
        }
        if (bonusBps != 0) {
            uint256 factor = (bonusFactors >> (uint256(s - 6) * 64)) & type(uint64).max;
            scaledRoi += bonusBps * factor;
        }
        return uint256(betAmount) * base * (4 + uint256(spin.goldMatches)) * scaledRoi / 4_000_000_000_000;
    }

    function _basePayoutCentiX(uint8 s) internal pure returns (uint256) {
        if (s == 9) return QUICK_PLAY_PAYOUT_S9;
        if (s == 8) return QUICK_PLAY_PAYOUT_S8;
        return (QUICK_PLAY_PAYOUTS_PACKED >> (uint256(s) * 32)) & type(uint32).max;
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

    /// @dev WWXRP has a 5% chance to improve one unmatched non-hero axis when
    ///      2..6 of the eight axes already match. Independent colors are eligible
    ///      even when their symbols miss. Never forces the hero symbol or a jackpot.
    function _rigWwxrpResult(
        uint32 playerTraits,
        uint32 resultTraits,
        uint8 heroQuadrant,
        uint256 rigSeed
    ) internal pure returns (uint32 rigged) {
        rigged = resultTraits;
        if (rigSeed % WWXRP_RIG_DENOMINATOR != 0) return rigged;
        uint32 diff = playerTraits ^ resultTraits;
        uint8 matches;
        uint8 eligible;
        for (uint8 q; q < 4; ++q) {
            uint8 d = uint8(diff >> (q * 8));
            if ((d & 0x38) == 0) ++matches;
            else ++eligible;
            if ((d & 7) == 0) ++matches;
            else if (q != heroQuadrant) ++eligible;
        }
        if (matches < 2 || matches >= 7 || eligible == 0) return rigged;
        uint256 pick = EntropyLib.hash2(rigSeed, 1) % eligible;
        for (uint8 q; q < 4; ++q) {
            uint32 shift = uint32(q) * 8;
            uint8 d = uint8(diff >> shift);
            if ((d & 0x38) != 0) {
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
    function _addClaimableEth(address beneficiary, uint256 weiAmount) private {
        claimablePool += uint128(weiAmount);
        _creditClaimable(beneficiary, weiAmount);
    }

    /// @dev Award sDGNRS from Reward pool on the top-3 score tiers (S>=7) Degenerette ETH bets.
    ///      Reward scales by bet size (capped at 1 ETH) and score tier.
    function _awardDegeneretteDgnrs(
        address player,
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
            player,
            reward
        );
    }

    // -------------------------------------------------------------------------
    // Lootbox-triggered Degenerette spins
    // -------------------------------------------------------------------------
    // Three lootbox value rolls resolve as Degenerette spins instead of flat awards.
    // Each is delegatecalled by the lootbox module in the Game's storage context; the
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
                (uint256(spin.score) << 64)) << (i * 72) |
            (uint256(spin.heroQuadrant) << (225 + i * 2));
    }

    /// @notice One WWXRP Degenerette spin staking a lootbox WWXRP roll (replaces the flat mint).
    /// @dev Uses the 5% reel rig, shared table and 70–130% activity target. The payout is
    ///      WWXRP only, returned for the calling box entry to mint its WWXRP lane once.
    function resolveWwxrpSpinFromBox(
        address player,
        uint256 stake,
        uint16 activityScore,
        uint256 seed,
        uint8 symbol
    ) external payable returns (uint256 wwxrpOut) {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if (stake == 0 || stake > type(uint128).max) return 0;
        uint64 betId = _boxBetId(seed, BOX_SPIN_TYPE_WWXRP);
        seed = EntropyLib.hash2(seed, WWXRP_DRAW_TAG);
        uint128 betAmount = uint128(stake);

        SpinResult memory spin = _rollSpin(seed, EntropyLib.hash2(seed, RESULT_TICKET_TAG), symbol, CURRENCY_WWXRP);
        uint256 payout = _degenerettePayout(spin, CURRENCY_WWXRP, betAmount, activityScore);

        // Returned, not minted: the caller sums every WWXRP lane in the entry and mints once.
        wwxrpOut = payout;

        // One self-contained record: the single reel + WWXRP-minted payout (no ETH split).
        emit BoxSpin(
            player,
            betId,
            _packSpin(0, spin) |
                (uint256(1) << BOX_SPIN_COUNT_SHIFT),
            payout,
            0
        );
    }

    /// @notice Three FLIP Degenerette spins under one survival flip (FLIP-only, safe on any box).
    /// @dev The total stake splits into three equal per-spin stakes (totalStake / 3; the 0-2 wei integer remainder is dropped, un-staked); the summed payout then double-or-
    ///      nothings on one fair flip (EV-neutral) and is returned for the box entry's FLIP
    ///      lane (credited via coinflip.creditFlip at flush; only the record-bounty chain mints
    ///      here). No pool / ETH / recirc touch, so this is solvency-safe on every box path
    ///      including recirc.
    function resolveFlipSpinsFromBox(
        address player,
        uint256 totalStake,
        uint16 activityScore,
        uint256 seed,
        uint8 symbol
    ) external payable returns (uint256 flipOut) {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        // Returned, not minted: the caller sums every FLIP lane in the entry and credits once.
        return
            _flipSpinChain(
                player,
                totalStake,
                activityScore,
                seed,
                symbol,
                BOX_SPIN_TYPE_FLIP
            );
    }

    /// @dev Shared automatic/record FLIP chain. Record and foil awards retain
    ///      a chosen symbol; random box awards pass 32. Every spin rerolls colors.
    function _flipSpinChain(
        address player,
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
        // The BOX caller sums this into the entry's FLIP lane; the record-bounty caller has no
        // accumulator and mints here.
        if (total != 0) {
            if (spinType == BOX_SPIN_TYPE_RECORD) coin.mintForGame(player, total);
            else minted = total;
        }

        // One self-contained record: all three reels + count + survival + the final FLIP mint.
        packedSpins |=
            (uint256(BOX_FLIP_SPINS) << BOX_SPIN_COUNT_SHIFT) |
            (survived ? (uint256(1) << BOX_SPIN_SURVIVED_SHIFT) : 0);
        emit BoxSpin(player, betId, packedSpins, total, 0);
    }

    /// @notice One ETH Degenerette spin staking a lootbox roll's ticket budget.
    /// @dev Reuses the regular 3-tier ETH split (`_distributePayout`): the ETH share credits
    ///      claimable and the lootbox share recircs into a fresh re-hashed box. This spin's
    ///      pool/claimable writes are flushed to storage BEFORE the recirc so the recirc reads
    ///      fresh state, and the recirc box is opened with the ETH-spin path disabled (the box
    ///      module passes allowEthSpin=false on the recirc entry) so no ETH-spin can cascade.
    function resolveEthSpinFromBox(
        address player,
        uint256 stake,
        uint16 activityScore,
        uint256 seed,
        uint8 symbol
    ) external payable {
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
            emit BoxSpin(player, betId, packed, 0, 0);
            return;
        }

        ResolveAcc memory acc;
        // A box spin stakes a lootbox roll's budget rather than a placed bet, so it
        // never touches the biggest-spin record — that arms only on a placed ETH
        // bet's total wager (amountPerSpin x spinCount).
        (uint256 lootboxShare, ) = _distributePayout(
            player,
            CURRENCY_ETH,
            betAmount,
            payout,
            acc
        );
        if (s >= 7) _awardDegeneretteDgnrs(player, betAmount, s);

        // Flush THIS spin's pool/claimable BEFORE recirc so recirc reads fresh storage.
        if (acc.ethClaimable != 0) _addClaimableEth(player, acc.ethClaimable);
        if (acc.poolLoaded) {
            if (acc.poolFrozen) {
                _setPendingPools(acc.pendingNext, acc.pendingFuture);
            } else {
                _setFuturePrizePool(acc.runningFuture);
            }
        }

        // One self-contained record: the reel + ETH gross + the claimable share. The
        // recirculated remainder (payout - ethShare) is itemized by the recirc box's own events.
        emit BoxSpin(player, betId, packed, payout, acc.ethClaimable);

        // Recirc into a fresh re-hashed box; allowEthSpin=false there -> no ETH-spin cascade.
        // The recirculated box's contents are itemized for the UI via its own LootBoxOpened.
        if (lootboxShare != 0) {
            _resolveLootboxDirect(
                player,
                lootboxShare,
                EntropyLib.hash2(seed, BOX_RECIRC_TAG),
                activityScore
            );
        }
    }
}
