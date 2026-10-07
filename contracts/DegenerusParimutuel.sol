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

import {ContractAddresses} from "./ContractAddresses.sol";
import {IDegenerusGame} from "./interfaces/IDegenerusGame.sol";
import {IDegenerusCoin} from "./interfaces/IDegenerusCoin.sol";
import {ICoinflip} from "./interfaces/ICoinflip.sol";
import {IDegenerusQuests} from "./interfaces/IDegenerusQuests.sol";
import {IDegenerusParimutuel} from "./interfaces/IDegenerusParimutuel.sol";

/**
 * @title DegenerusParimutuel
 * @author Burnie Degenerus
 * @notice A parimutuel market on the game's own trajectory, denominated in FLIP, one
 *         fixed-size bet per wallet per round: will the next level's pool-growth rate
 *         beat this level's?
 *
 * @dev Growth round L resolves OVER iff ratchet(L+1) * ratchet(L-1) > ratchet(L)^2 — the
 *      cross-multiplied rate comparison, exact and unsigned; ties are UNDER. Century terms
 *      read the write-once achieved-pool history, so the x01-base overwrite never moves a
 *      settled term; mature-century rounds x99/x00/x01 are lopsided, and knowingly so.
 *
 *      Settlement is PUSHED by the game the instant the round's terms go final — the level
 *      transition that banks the successor ratchet entry — into a write-once two-bit
 *      outcome, 128 rounds per word.
 *
 *      Each bet appends the bettor's wallet ID to its side's array for the round; the side
 *      counts are the array lengths. Stakes burn at placement. Winners are paid by the game's
 *      in-order settlement stage, which walks only the winning array from a cursor and credits
 *      each winner the round's uniform payout through the coinflip rail; nobody claims. Dust and
 *      an empty winning side stay burned. Betting requires having ever bought anything. FLIP is
 *      tombstoned at game over, so an unresolved book needs no unwind rule.
 */
contract DegenerusParimutuel is IDegenerusParimutuel {
    // =========================================================================
    // Wiring
    // =========================================================================

    IDegenerusGame private constant game =
        IDegenerusGame(ContractAddresses.GAME);
    IDegenerusCoin private constant coin =
        IDegenerusCoin(ContractAddresses.COIN);
    ICoinflip private constant coinflip =
        ICoinflip(ContractAddresses.COINFLIP);
    IDegenerusQuests private constant quests =
        IDegenerusQuests(ContractAddresses.QUESTS);

    // =========================================================================
    // Constants
    // =========================================================================

    /// @dev The single growth-bet stake: one whole ticket at PRICE_COIN_UNIT. Fixed rather
    ///      than chosen, so the two pools are counts and every winner is paid the same.
    uint256 public constant STAKE = 1_000;

    /// @dev Participation-quest reward on the first day betting is open, before the
    ///      per-day decay. Parimutuel pays the last mover best, since the final bettor sees
    ///      the book before committing; a decaying reward prices that advantage back out
    ///      without a hard cutoff.
    uint256 public constant QUEST_BASE = 150;

    uint8 private constant SIDE_OVER = 1;
    uint8 private constant SIDE_UNDER = 2;
    uint8 private constant SIDE_MASK = 3;

    /// @dev Width of one wallet-ID lane; eight lanes fill a word.
    uint256 private constant LANE_MASK = type(uint32).max;

    // =========================================================================
    // Storage
    // =========================================================================

    /// @dev Per-round side counts: overCount in the low 128 bits, underCount in the high 128.
    ///      Each count is also the length of that side's wallet-ID array.
    mapping(uint24 => uint256) private growthCounts;

    /// @dev Settled sides, two bits per round, 128 rounds to a word — keyed by `round >> 7`.
    ///      Values are the SIDE_OVER/SIDE_UNDER encoding; 0 = unsettled.
    mapping(uint24 => uint256) private growthOutcomeWords;

    /// @dev Each round's two side arrays of bettor wallet IDs, eight 32-bit lanes per word:
    ///      position i of `side` on `round` is lane i & 7 of the word keyed
    ///      (round << 40) | (side << 32) | (i >> 3). Append-only: a lane is written once.
    mapping(uint256 => uint256) private growthSideLanes;

    /// @dev The last round each wallet bet on, eight 32-bit lanes per word keyed by id >> 3.
    ///      Bets only join the open round, which only moves forward, so one lane per wallet
    ///      blocks a second bet on the round, on either side.
    mapping(uint32 => uint256) private lastBetRounds;

    /// @dev Settlement cursor: bits 0-23 the oldest round not yet fully paid (every earlier
    ///      round is), bits 24-87 how many of that round's winners are paid. Starts at round 1,
    ///      the first round the game seals.
    uint256 private growthSettlement = 1;

    // =========================================================================
    // Errors
    // =========================================================================

    /// @notice The caller may not act for the account: it is neither the account's key, a
    ///         smurf's owner, nor an approved operator.
    error NotApproved();

    /// @notice No round is open for betting: outside the jackpot phase — game over
    ///         included, since no phase ever opens again — or on round 0, which can
    ///         never settle.
    error MarketClosed();

    /// @notice The player's wallet already holds a bet on the open round.
    error AlreadyBet();

    /// @notice A settlement push or settlement stage arrived from something other than GAME.
    error OnlyGame();

    /// @notice The player has never bought anything, so may not bet.
    error NotEligible();

    // =========================================================================
    // Events
    // =========================================================================

    /// @notice Emitted when a growth bet is placed. Per round and side, these events in log
    ///         order are that side's wallet-ID array.
    /// @param id The bettor's wallet ID.
    /// @param round The round's level.
    /// @param over True for the OVER side (growth accelerates), false for UNDER.
    /// @param questReward FLIP credited for the participation quest (0 if not eligible).
    event BetPlaced(
        uint32 indexed id,
        uint24 indexed round,
        bool over,
        uint256 questReward
    );

    /// @notice Emitted for each run of winners the settlement stage pays on one round.
    /// @param round The round's level.
    /// @param outcome The round's outcome (1 = OVER, 2 = UNDER): the side array paid.
    /// @param firstIndex Position of the first winner paid in that side's array.
    /// @param count Winners paid, at positions [firstIndex, firstIndex + count).
    /// @param payout FLIP credited to each of them: the stake plus a pro-rata share of the
    ///        losing side.
    event GrowthWinnersPaid(
        uint24 indexed round,
        uint8 outcome,
        uint256 firstIndex,
        uint256 count,
        uint256 payout
    );

    /// @notice Emitted when the game settles a growth round at the level transition that
    ///         banks its successor ratchet entry.
    /// @param round The growth round that settled.
    /// @param over True if the round resolved OVER.
    event GrowthRoundSealed(uint24 indexed round, bool over);

    // =========================================================================
    // Construction
    // =========================================================================

    /// @notice Registers this contract's ENS reverse name; takes no arguments.
    constructor() {
        // Register this contract's ENS reverse name (best-effort; skipped when the
        // registrar is unset — local/test/testnet builds). The setName(string)
        // selector is shared by the L1 ReverseRegistrar and Base's L2ReverseRegistrar.
        address ensReg = ContractAddresses.ENS_REVERSE_REGISTRAR;
        if (ensReg != address(0)) {
            (bool ok, ) = ensReg.call(
                // raw-selectors: justified — best-effort ENS reverse-name; setName(string) has no deploy-wide bound interface and must not revert deployment
                abi.encodeWithSignature("setName(string)", "parimutuel.degenerus.eth")
            );
            ok;
        }
    }

    // =========================================================================
    // Betting
    // =========================================================================

    /// @notice Place account `id`'s growth bet for the open round.
    /// @dev Gated, not permissionless: the bet spends the account payee's FLIP, so only the
    ///      account's key, a smurf's owner or an approved operator may place it (`id == 0` is the
    ///      caller, with no Game resolution call). One fixed-size bet per wallet per round —
    ///      there is no amount to choose and no averaging in, which is what makes the choice
    ///      to commit early against a thin book a real decision rather than a mechanical one.
    /// @param id The account the bet belongs to (0 = caller).
    /// @param over True to bet that growth accelerates, false to bet that it does not.
    function placeBet(uint32 id, bool over) external {
        address key = msg.sender;
        address payee = msg.sender;
        if (id != 0) {
            bool authorized;
            (key, payee, authorized) = game.resolveAccount(id, msg.sender);
            if (!authorized) revert NotApproved();
        }

        (, , , uint24 round, bool open, uint8 phaseDay) = game.growthState(0);
        // Round 0 is the sole unscoreable round — growthState reports no ratchet terms
        // for it, so it could never settle and a stake left there would strand.
        if (!open || round == 0) revert MarketClosed();

        // A wallet that has never bought anything cannot take a position on how the game
        // grows. The gate reads the mint word that also carries the wallet ID; every Game
        // door that writes a field passing it registers the wallet first, so `mayBet`
        // implies a nonzero ID (for a resolved account, `id` itself).
        bool mayBet;
        bool earnsReward;
        (mayBet, earnsReward, id) = quests.marketBetGates(key, round);
        if (!mayBet) revert NotEligible();
        _recordBet(id, round, over);

        coin.burnCoin(payee, STAKE);

        // Only an eligible bettor reaches for the quest: recordGrowthBet applies the same
        // gate internally and pays such a call 0 with no side effects, so skipping it for
        // the ineligible is behavior-identical and one external call cheaper.
        uint256 reward;
        if (earnsReward) {
            reward = quests.recordGrowthBet(
                id,
                key,
                round,
                _questReward(phaseDay)
            );
        }
        emit BetPlaced(id, round, over, reward);
    }

    /// @dev Mark wallet `id`'s bet on `round` (one per wallet per round, on either side) and
    ///      append the ID to its side's array.
    function _recordBet(uint32 id, uint24 round, bool over) private {
        uint32 lastKey = id >> 3;
        uint256 lastShift = (uint256(id) & 7) << 5;
        uint256 lastWord = lastBetRounds[lastKey];
        if (uint32(lastWord >> lastShift) == round) revert AlreadyBet();
        lastBetRounds[lastKey] = (lastWord & ~(LANE_MASK << lastShift)) | (uint256(round) << lastShift);

        // overCount occupies the low half, underCount the high half, so each side increments
        // by its own unit and the two can never carry into one another. The side's count
        // before the increment is this bet's position in the side's array.
        uint256 counts = growthCounts[round];
        uint256 index = over ? uint128(counts) : counts >> 128;
        growthCounts[round] = counts + (over ? 1 : uint256(1) << 128);
        growthSideLanes[_laneKey(round, over ? SIDE_OVER : SIDE_UNDER, index)] |=
            uint256(id) << ((index & 7) << 5);
    }

    // =========================================================================
    // Settlement (GAME only)
    // =========================================================================

    /// @inheritdoc IDegenerusParimutuel
    function recordGrowth(uint24 round, bool over) external returns (bool settlementPending) {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        uint8 outcome = _writeOutcome(round, over ? SIDE_OVER : SIDE_UNDER);
        emit GrowthRoundSealed(round, over);

        // Settlement caught up with this round and its winning side is empty: step the
        // cursor past it here, so the stage never runs for a round with nobody to pay.
        uint24 next = uint24(growthSettlement);
        if (next == round && _winCount(growthCounts[round], outcome) == 0) {
            unchecked {
                next = round + 1;
            }
            growthSettlement = next;
        }
        // The cursor rests on a sealed round only while it, or a round after it, still owes
        // winners.
        settlementPending = _readOutcome(next) != 0;
    }

    /// @inheritdoc IDegenerusParimutuel
    /// @dev Each winner paid and each round stepped past spends one unit of `maxWinners`, so a
    ///      call's work is bounded by the argument alone. A call that ends exactly on a round
    ///      boundary reports not done; the next call steps the cursor and reports done.
    function settleGrowth(uint256 maxWinners) external returns (bool done) {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        uint256 cursor = growthSettlement;
        uint24 round = uint24(cursor);
        uint256 pos = uint64(cursor >> 24);

        uint32[] memory ids = new uint32[](maxWinners);
        uint256[] memory amounts = new uint256[](maxWinners);
        uint256 n;
        uint256 budget = maxWinners;
        while (budget != 0) {
            uint8 outcome = _readOutcome(round);
            if (outcome == 0) {
                // The cursor reached a round the game has not sealed: every sealed round is paid.
                done = true;
                break;
            }
            uint256 counts = growthCounts[round];
            uint256 winCount = _winCount(counts, outcome);
            if (pos == winCount) {
                unchecked {
                    ++round;
                    --budget;
                }
                pos = 0;
                continue;
            }

            uint256 take = winCount - pos;
            if (take > budget) take = budget;
            _payRun(ids, amounts, n, round, outcome, counts, pos, take);
            unchecked {
                n += take;
                pos += take;
                budget -= take;
            }
        }
        growthSettlement = uint256(round) | (pos << 24);

        if (n != 0) {
            assembly ("memory-safe") {
                mstore(ids, n)
                mstore(amounts, n)
            }
            coinflip.creditFlipBatch(ids, amounts);
        }
    }

    /// @dev Load `take` winners of `round` from array position `pos` into the batch arrays at
    ///      slot `n`, each at the round's uniform payout.
    function _payRun(
        uint32[] memory ids,
        uint256[] memory amounts,
        uint256 n,
        uint24 round,
        uint8 outcome,
        uint256 counts,
        uint256 pos,
        uint256 take
    ) private {
        uint256 payout = _payoutFrom(counts, outcome);
        emit GrowthWinnersPaid(round, outcome, pos, take, payout);
        uint256 end = pos + take;
        uint256 word = growthSideLanes[_laneKey(round, outcome, pos)];
        while (true) {
            ids[n] = uint32(word >> ((pos & 7) << 5));
            amounts[n] = payout;
            unchecked {
                ++n;
                ++pos;
            }
            if (pos == end) break;
            if (pos & 7 == 0) word = growthSideLanes[_laneKey(round, outcome, pos)];
        }
    }

    /// @dev Write-once latch: a settled round's answer is permanent by structure. Returns the
    ///      round's stored side.
    function _writeOutcome(uint24 round, uint8 side) private returns (uint8) {
        uint24 word = round >> 7;
        uint256 shift = (uint256(round) & 127) << 1;
        uint256 packed = growthOutcomeWords[word];
        uint8 stored = uint8((packed >> shift) & SIDE_MASK);
        if (stored != 0) return stored;
        growthOutcomeWords[word] = packed | (uint256(side) << shift);
        return side;
    }

    /// @dev A round's settled side, or 0 if it has not settled.
    function _readOutcome(uint24 round) private view returns (uint8) {
        return
            uint8(
                (growthOutcomeWords[round >> 7] >>
                    ((uint256(round) & 127) << 1)) & SIDE_MASK
            );
    }

    /// @dev The winning side's count (its array length) from a counts word.
    function _winCount(uint256 counts, uint8 outcome) private pure returns (uint256) {
        return outcome == SIDE_OVER ? uint128(counts) : counts >> 128;
    }

    /// @dev Key of the side-array word holding position `index` of `side` on `round`.
    function _laneKey(uint24 round, uint8 side, uint256 index) private pure returns (uint256) {
        return (uint256(round) << 40) | (uint256(side) << 32) | (index >> 3);
    }

    /// @dev The payout arithmetic over an already-loaded counts word. A winning bet exists
    ///      whenever this is called, so the winning count is at least 1. An empty losing
    ///      side needs no special case — the numerator collapses to the winning count and
    ///      the payout is exactly the stake back.
    function _payoutFrom(
        uint256 packed,
        uint8 outcome
    ) private pure returns (uint256) {
        return (STAKE * (uint128(packed) + (packed >> 128))) / _winCount(packed, outcome);
    }

    /// @dev The participation-quest reward for a bet placed on jackpot-phase day
    ///      `phaseDay`: 150 FLIP across the first day (counter 0 or 1), then 37 FLIP
    ///      after the second draw (counter 2). This preserves the three-day schedule's
    ///      reward amounts while counting actual draws. The final draw closes betting.
    function _questReward(uint8 phaseDay) private pure returns (uint256) {
        uint256 step = phaseDay <= 1 ? 0 : 2;
        return QUEST_BASE >> step;
    }

    // =========================================================================
    // Views
    // =========================================================================

    /// @notice The open round, plus one player's position on a round of interest.
    /// @dev Off-chain view. The player's side and array position are found by scanning the
    ///      round's side arrays.
    /// @param player The player whose position to report (address(0) for none).
    /// @param round The round to report the position for — the open round while betting,
    ///        or any past round.
    /// @return openRound The round a bet placed now would join (0 when betting is closed).
    /// @return overCount Bets on the OVER side of `round`.
    /// @return underCount Bets on the UNDER side of `round`.
    /// @return questReward The quest's nominal reward at the current phase counter, before the
    ///         eligibility gates `placeBet` applies; quoted even while the market is closed.
    /// @return side The player's side on `round`: 1 = OVER, 2 = UNDER (0 = no bet).
    /// @return claimed True once the settlement stage has paid the player's win on `round`.
    /// @return outcome `round`'s outcome (0 = unsettled).
    /// @return payout FLIP the player's win on `round` pays that the settlement stage has not
    ///         paid yet (0 if unsettled, lost, or already paid).
    function marketState(
        address player,
        uint24 round
    )
        external
        view
        returns (
            uint24 openRound,
            uint128 overCount,
            uint128 underCount,
            uint256 questReward,
            uint8 side,
            bool claimed,
            uint8 outcome,
            uint256 payout
        )
    {
        // growthState(0): the ratchet terms are not a settlement input — the outcome is a
        // bit this contract holds — so the view asks only for the routing half, and round 0
        // skips the three ratchet reads.
        {
            (, , , uint24 lvl, bool open, uint8 phaseDay) = game.growthState(0);
            if (open && lvl != 0) openRound = lvl;
            questReward = _questReward(phaseDay);
        }

        uint256 packed = growthCounts[round];
        overCount = uint128(packed);
        underCount = uint128(packed >> 128);
        outcome = _readOutcome(round);
        (side, claimed, payout) = _position(game.walletIdOf(player), round, packed, outcome);
    }

    /// @dev Wallet `id`'s side on `round`, whether settlement has paid its win, and the payout
    ///      still owed to it. A wallet whose last bet is older than `round` placed none on it
    ///      (ID 0 never bets); otherwise the round's side arrays are scanned for its position.
    function _position(uint32 id, uint24 round, uint256 packed, uint8 outcome)
        private
        view
        returns (uint8 side, bool paid, uint256 owed)
    {
        if (id == 0 || uint32(lastBetRounds[id >> 3] >> ((uint256(id) & 7) << 5)) < round) {
            return (0, false, 0);
        }
        uint256 index;
        (side, index) = _findBet(id, round, packed);
        if (side != 0 && side == outcome) {
            uint256 cursor = growthSettlement;
            uint24 next = uint24(cursor);
            paid = round < next || (round == next && index < uint64(cursor >> 24));
            if (!paid) owed = _payoutFrom(packed, outcome);
        }
    }

    /// @dev Scan `round`'s OVER then UNDER array for wallet `id`: its side and position, or
    ///      (0, 0) when it holds no bet on the round.
    function _findBet(uint32 id, uint24 round, uint256 packed)
        private
        view
        returns (uint8 side, uint256 index)
    {
        for (uint8 s = SIDE_OVER; s <= SIDE_UNDER; ++s) {
            uint256 len = _winCount(packed, s);
            uint256 word;
            for (uint256 i; i < len; ++i) {
                if (i & 7 == 0) word = growthSideLanes[_laneKey(round, s, i)];
                if (uint32(word >> ((i & 7) << 5)) == id) return (s, i);
            }
        }
    }
}
