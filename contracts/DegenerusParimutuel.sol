// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement, and controls over every comment, name,
 * document and statement made about it. It has been audited but is not proven correct:
 * it may contain defects the author did not find, and by interacting with it you accept
 * that risk in full.
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
import {PriceLookupLib} from "./libraries/PriceLookupLib.sol";

/**
 * @title DegenerusParimutuel
 * @author Burnie Degenerus
 * @notice A parimutuel market on the game's own trajectory, denominated in FLIP, one
 *         fixed-size bet per address per round: will the next level's pool-growth rate
 *         beat this level's?
 *
 * @dev Growth round L resolves OVER iff ratchet(L+1) * ratchet(L-1) > ratchet(L)^2 — the
 *      cross-multiplied rate comparison, exact and unsigned; ties are UNDER. Century terms
 *      read the write-once achieved-pool history, so the x01-base overwrite never moves a
 *      settled term; mature-century rounds x99/x00/x01 are lopsided, and knowingly so.
 *
 *      Settlement is PUSHED by the game the instant the round's terms go final — the level
 *      transition that banks the successor ratchet entry — into a write-once two-bit
 *      outcome, 128 rounds per word; claims read the bit and never re-derive.
 *
 *      Stakes burn at placement; winners re-mint through the coinflip rail; dust and an
 *      empty winning side stay burned. Beyond the stakes the rail pays the gas-pegged
 *      settlement bounty (capped at one per winning bet ever). Betting requires having
 *      ever bought anything. FLIP is tombstoned at game over, so an unresolved book needs
 *      no unwind rule.
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
    uint256 public constant STAKE = 1_000 ether;

    /// @dev Participation-quest reward on the first day betting is open, before the
    ///      per-day decay. Parimutuel pays the last mover best, since the final bettor sees
    ///      the book before committing; a decaying reward prices that advantage back out
    ///      without a hard cutoff.
    uint256 public constant QUEST_BASE = 150 ether;

    /// @dev FLIP-per-ETH conversion base, matching the Game's PRICE_COIN_UNIT:
    ///      FLIP per ETH = PRICE_COIN_UNIT / mintPrice. Equal to STAKE by construction —
    ///      the stake is one whole ticket — but priced here, not staked.
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;

    /// @dev Settlement-crank bounty target (ETH wei) per winner actually paid: the ~30k-gas
    ///      marginal cost of one settled winner at the 0.5-gwei reference — the same peg
    ///      and number the foil-claim bounty carries.
    uint256 private constant CRANK_BOUNTY_ETH_TARGET = 15_000_000_000_000;

    uint8 private constant SIDE_OVER = 1;
    uint8 private constant SIDE_UNDER = 2;
    uint8 private constant SIDE_MASK = 3;
    uint8 private constant CLAIMED_BIT = 4;

    // =========================================================================
    // Storage
    // =========================================================================

    /// @dev Per-round side counts: overCount in the low 128 bits, underCount in the high 128.
    ///      One slot, and a placement is a single read-modify-write of it.
    mapping(uint24 => uint256) private growthCounts;

    /// @dev Per-round bets: the low two bits carry the side, bit 2 marks the payout taken.
    ///      Keyed by round then player so a round left unclaimed is never destroyed by the
    ///      next round's placement.
    mapping(uint24 => mapping(address => uint8)) private growthBets;

    /// @dev Settled sides, two bits per round, 128 rounds to a word — keyed by `round >> 7`.
    ///      Values are the SIDE_OVER/SIDE_UNDER encoding; 0 = unsettled.
    mapping(uint24 => uint256) private growthOutcomeWords;

    // =========================================================================
    // Errors
    // =========================================================================

    /// @notice The caller may not act on the player's behalf.
    error NotApproved();

    /// @notice No round is open for betting: outside the jackpot phase — game over
    ///         included, since no phase ever opens again — or on round 0, which can
    ///         never settle.
    error MarketClosed();

    /// @notice The player already holds a bet on the open round.
    error AlreadyBet();

    /// @notice The crank's opening entry settles nothing: the round is unsettled, its
    ///         winning side is empty, the list is empty, or that first address did not
    ///         win the round or was already paid.
    error NothingToSettle();

    /// @notice A settlement push arrived from something other than GAME.
    error OnlyGame();

    /// @notice The player has never bought anything, so may not bet.
    error NotEligible();

    // =========================================================================
    // Events
    // =========================================================================

    /// @notice Emitted when a growth bet is placed.
    /// @param player The player the bet belongs to.
    /// @param round The round's level.
    /// @param over True for the OVER side (growth accelerates), false for UNDER.
    /// @param questReward FLIP credited for the participation quest (0 if not eligible).
    event BetPlaced(
        address indexed player,
        uint24 indexed round,
        bool over,
        uint256 questReward
    );

    /// @notice Emitted when a winning growth bet is claimed.
    /// @param player The bettor being paid.
    /// @param round The round's level.
    /// @param outcome The round's derived outcome (1 = OVER, 2 = UNDER).
    /// @param payout FLIP credited: the stake plus a pro-rata share of the losing side.
    event BetClaimed(
        address indexed player,
        uint24 indexed round,
        uint8 outcome,
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

    /// @notice Place the growth bet for the open round.
    /// @dev Gated, not permissionless: the bet spends the player's FLIP, so only the player
    ///      or an approved operator may place it. One fixed-size bet per address per round —
    ///      there is no amount to choose and no averaging in, which is what makes the choice
    ///      to commit early against a thin book a real decision rather than a mechanical one.
    /// @param player The player the bet belongs to (zero address for msg.sender).
    /// @param over True to bet that growth accelerates, false to bet that it does not.
    function placeBet(address player, bool over) external {
        if (player == address(0)) player = msg.sender;
        if (
            player != msg.sender &&
            !game.isOperatorApproved(player, msg.sender)
        ) revert NotApproved();

        (, , , uint24 round, bool open, uint8 phaseDay) = game.growthState(0);
        // Round 0 is the sole unscoreable round — growthState reports no ratchet terms
        // for it, so it could never settle and a stake left there would strand.
        if (!open || round == 0) revert MarketClosed();
        if (growthBets[round][player] != 0) revert AlreadyBet();

        // A wallet that has never bought anything cannot take a position on how the game
        // grows.
        (bool mayBet, bool earnsReward) = quests.marketBetGates(player, round);
        if (!mayBet) revert NotEligible();

        growthBets[round][player] = over ? SIDE_OVER : SIDE_UNDER;
        // overCount occupies the low half, underCount the high half, so each side increments
        // by its own unit and the two can never carry into one another.
        growthCounts[round] += over ? 1 : (uint256(1) << 128);

        coin.burnCoin(player, STAKE);

        // Only an eligible bettor reaches for the quest: recordGrowthBet applies the same
        // gate internally and pays such a call 0 with no side effects, so skipping it for
        // the ineligible is behavior-identical and one external call cheaper.
        uint256 reward;
        if (earnsReward) {
            reward = quests.recordGrowthBet(
                player,
                round,
                _questReward(phaseDay)
            );
        }
        emit BetPlaced(player, round, over, reward);
    }

    /// @notice Claim payouts for the named settled rounds.
    /// @dev Permissionless: a claim only ever credits the bettor, so any caller may settle
    ///      any player's rounds. Rounds that are unsettled, unbet, already claimed, or lost
    ///      are skipped rather than reverted, so one stale id cannot brick a batch.
    /// @param player The bettor to pay (zero address for msg.sender).
    /// @param rounds The round levels to claim.
    /// @return total FLIP credited across the batch.
    function claim(
        address player,
        uint24[] calldata rounds
    ) external returns (uint256 total) {
        if (player == address(0)) player = msg.sender;

        uint256 len = rounds.length;
        for (uint256 i; i < len; ) {
            total += _claim(player, rounds[i]);
            unchecked {
                ++i;
            }
        }

        if (total != 0) coinflip.creditFlip(player, total);
    }

    /// @notice Pay every winner on one settled round.
    /// @dev The settlement crank. A round's outcome and its per-winner payout are
    ///      properties of the ROUND, not of the claimant, so both are derived once for the
    ///      whole list and the credits land as one creditFlipBatch call: settling a
    ///      hundred bettors costs one growthState call, one growthCounts read and one
    ///      credit call, where a hundred single claims would repeat all three.
    ///
    ///      Permissionless for the same reason as claim — a payout can only ever reach the
    ///      bettor who placed the bet — and paid for its work: the caller earns a gas-pegged
    ///      FLIP credit per winner it actually settles.
    ///
    ///      Past the opening address, entries that did not bet, lost, or already claimed are
    ///      skipped rather than reverted, so a duplicate or junk entry cannot brick the
    ///      batch. The opening address is the exception, and is the probe: a call that would
    ///      settle nothing reverts instead of succeeding silently, so a keeper racing a
    ///      list someone else already swept fails its simulation rather than paying for the
    ///      whole walk. A crank therefore leads with a winner it believes unpaid.
    /// @param round The round to settle.
    /// @param players The bettors to pay, a genuine unpaid winner first.
    /// @custom:reverts NothingToSettle If the round is unsettled, its winning side is empty,
    ///         the list is empty, or the opening address is not an unpaid winner.
    /// @return total FLIP credited to winners across the batch, excluding the caller's bounty.
    function claimRound(
        uint24 round,
        address[] calldata players
    ) external returns (uint256 total) {
        uint256 len = players.length;
        if (len == 0) revert NothingToSettle();

        // Opener first, before the outcome read and the bounty's game call: most cranks
        // are duplicates racing one broadcast list, and a spent opener proves the sweep
        // for one cold slot. (A winner who claimed alone can false-positive this; the
        // cost is one rebuilt broadcast.)
        uint8 opener = growthBets[round][players[0]];
        if (opener == 0 || (opener & CLAIMED_BIT) != 0) revert NothingToSettle();

        // One cold SLOAD, no game call: the side was written by the push at the level
        // transition that banked this round's successor entry.
        uint8 outcome = _readOutcome(round);
        if (outcome == 0 || (opener & SIDE_MASK) != outcome) {
            revert NothingToSettle();
        }

        // The opener is a confirmed winner on this side, so its own placement already
        // incremented the winning count — the divisor below cannot be zero, and needs no
        // guard of its own.
        uint256 packed = growthCounts[round];
        uint256 payout = _payoutFrom(packed, outcome);

        // Credits land through one creditFlipBatch call rather than one credit per
        // winner. The arrays stay list-shaped: a skipped entry leaves its slot zeroed,
        // and the batch ignores zero entries by contract. One slot past the list carries
        // the caller's bounty, so the whole settlement is a single credit call.
        address[] memory winners = new address[](len + 1);
        uint256[] memory payouts = new uint256[](len + 1);
        uint256 settled;
        for (uint256 i; i < len; ) {
            address player = players[i];
            uint8 bet = growthBets[round][player];
            // A repeated address fails this on its second pass: the first already set the
            // claimed bit.
            if ((bet & SIDE_MASK) == outcome && (bet & CLAIMED_BIT) == 0) {
                growthBets[round][player] = bet | CLAIMED_BIT;
                winners[i] = player;
                payouts[i] = payout;
                total += payout;
                unchecked {
                    ++settled;
                }
                emit BetClaimed(player, round, outcome, payout);
            }
            unchecked {
                ++i;
            }
        }

        // Keeper bounty in the batch's tail slot: per winner ACTUALLY settled (padding
        // earns nothing; the claimed bit caps it at one per winning bet ever), priced at
        // the ROUTED level the crank runs at so the FLIP tracks settle gas. A caller who
        // also won takes two slots — payout plus bounty, as two calls would pay.
        // growthState(0) rather than growthState(round): round 0 skips the three ratchet
        // reads, and settlement no longer wants them — the outcome came from the bit. All
        // this call carries now is the routing half the bounty is priced at.
        (, , , uint24 currentLevel, bool bettingOpen, ) = game.growthState(0);
        winners[len] = msg.sender;
        payouts[len] =
            (settled * CRANK_BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) /
            PriceLookupLib.priceForLevel(
                bettingOpen ? currentLevel : currentLevel + 1
            );

        coinflip.creditFlipBatch(winners, payouts);
    }

    /// @dev Settle one round for one player. Returns the payout, or 0 when there is
    ///      nothing to pay.
    function _claim(address player, uint24 round) private returns (uint256) {
        uint8 bet = growthBets[round][player];
        if (bet == 0 || (bet & CLAIMED_BIT) != 0) return 0;

        uint8 outcome = _readOutcome(round);
        if (outcome == 0 || (bet & SIDE_MASK) != outcome) return 0;

        uint256 payout = _payout(round, outcome);
        growthBets[round][player] = bet | CLAIMED_BIT;
        emit BetClaimed(player, round, outcome, payout);
        return payout;
    }

    // =========================================================================
    // Settlement pushes (GAME only)
    // =========================================================================

    /// @inheritdoc IDegenerusParimutuel
    function recordGrowth(uint24 round, bool over) external {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        _writeOutcome(round, over ? SIDE_OVER : SIDE_UNDER);
        emit GrowthRoundSealed(round, over);
    }

    /// @dev Write-once latch: a settled round's answer is permanent by structure.
    function _writeOutcome(uint24 round, uint8 side) private {
        uint24 word = round >> 7;
        uint256 shift = (uint256(round) & 127) << 1;
        uint256 packed = growthOutcomeWords[word];
        if (((packed >> shift) & SIDE_MASK) != 0) return;
        growthOutcomeWords[word] = packed | (uint256(side) << shift);
    }

    /// @dev A round's settled side, or 0 if it has not settled.
    function _readOutcome(uint24 round) private view returns (uint8) {
        return
            uint8(
                (growthOutcomeWords[round >> 7] >>
                    ((uint256(round) & 127) << 1)) & SIDE_MASK
            );
    }

    /// @dev What one winning bet on `round` pays.
    function _payout(
        uint24 round,
        uint8 outcome
    ) private view returns (uint256) {
        return _payoutFrom(growthCounts[round], outcome);
    }

    /// @dev The payout arithmetic over an already-loaded counts word. A winning bet exists
    ///      whenever this is called, so the winning count is at least 1. An empty losing
    ///      side needs no special case — the numerator collapses to the winning count and
    ///      the payout is exactly the stake back.
    function _payoutFrom(
        uint256 packed,
        uint8 outcome
    ) private pure returns (uint256) {
        uint256 overCount = uint128(packed);
        uint256 underCount = packed >> 128;
        uint256 winCount = outcome == SIDE_OVER ? overCount : underCount;
        return (STAKE * (overCount + underCount)) / winCount;
    }

    /// @dev The participation-quest reward for a bet placed on jackpot-phase day
    ///      `phaseDay`: halved per day, floored to a whole FLIP so the ladder reads as
    ///      round numbers rather than trailing halves — 150 / 75 / 37 / 18 across the
    ///      phase's four jackpot days.
    ///
    ///      Days 0 and 1 share the top tier deliberately. The counter reads 0 from the
    ///      transition until the first daily jackpot settles — usually later the same
    ///      day — and 1 from then until day 2's processing. Folding 0 into 1 prices that
    ///      whole first day at 150 rather than dropping a tier minutes in when the
    ///      first settlement lands. It is also what a closed market quotes.
    function _questReward(uint8 phaseDay) private pure returns (uint256) {
        uint256 step = phaseDay == 0 ? 0 : phaseDay - 1;
        return ((QUEST_BASE / 1 ether) >> step) * 1 ether;
    }

    // =========================================================================
    // Views
    // =========================================================================

    /// @notice The open round, plus one player's position on a round of interest.
    /// @param player The player whose position to report (address(0) for none).
    /// @param round The round to report the position for — the open round while betting,
    ///        or any past round when checking what is claimable.
    /// @return openRound The round a bet placed now would join (0 when betting is closed).
    /// @return overCount Bets on the OVER side of `round`.
    /// @return underCount Bets on the UNDER side of `round`.
    /// @return questReward FLIP a bet placed right now would earn from the quest.
    /// @return side The player's side on `round`: 1 = OVER, 2 = UNDER (0 = no bet).
    /// @return claimed True once the player has taken the payout for `round`.
    /// @return outcome `round`'s outcome (0 = unsettled).
    /// @return payout FLIP claimable now (0 if unsettled, lost, or already claimed).
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
        // growthState(0): the ratchet terms are no longer a settlement input — the outcome
        // is a bit this contract holds — so the view asks only for the routing half, and
        // round 0 skips the three ratchet reads.
        (, , , uint24 lvl, bool open, uint8 phaseDay) = game.growthState(0);
        if (open && lvl != 0) openRound = lvl;
        questReward = _questReward(phaseDay);

        uint256 packed = growthCounts[round];
        overCount = uint128(packed);
        underCount = uint128(packed >> 128);

        uint8 bet = growthBets[round][player];
        side = bet & SIDE_MASK;
        claimed = (bet & CLAIMED_BIT) != 0;
        outcome = _readOutcome(round);
        if (side != 0 && !claimed && side == outcome) {
            payout = _payoutFrom(packed, outcome);
        }
    }
}
