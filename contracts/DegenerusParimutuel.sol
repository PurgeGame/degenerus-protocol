// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended, not a
 * malfunction and not a defect. Do not commit funds you are not prepared to lose
 * entirely.
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
import {GameTimeLib} from "./libraries/GameTimeLib.sol";

/**
 * @title DegenerusParimutuel
 * @author Burnie Degenerus
 * @notice Two parimutuel markets on the game's own trajectory, denominated in FLIP, one
 *         fixed-size bet per address per round: GROWTH — will the next level's pool-growth
 *         rate beat this level's — and VOLUME — will today's manual ETH ticket volume beat
 *         yesterday's.
 *
 * @dev Growth round L resolves OVER iff ratchet(L+1) * ratchet(L-1) > ratchet(L)^2 — the
 *      cross-multiplied rate comparison, exact and unsigned; ties are UNDER. Century terms
 *      read the write-once achieved-pool history, so the x01-base overwrite never moves a
 *      settled term; mature-century rounds x99/x00/x01 are lopsided, and knowingly so.
 *
 *      Volume round D resolves OVER iff volume(D) > volume(D-1), counted in raw purchase
 *      units (400 = one ticket) of MANUAL ETH ticket buys only — FLIP-paid, afking, pass,
 *      box, foil and award tickets are all outside the count, both ends. A round runs RNG
 *      request to RNG request; betting is open 22:57–00:00 UTC, computed off the clock.
 *      OVER can force its win by buying tickets: that is the design — the book leans OVER
 *      and every bettor is an incentivized buyer, each win ratcheting the next benchmark.
 *
 *      Settlement is PUSHED by the game the instant a round's terms go final (growth: the
 *      level transition; volume: the daily RNG request) into write-once two-bit outcomes,
 *      128 rounds per word; claims read the bit and never re-derive. A volume round sealed
 *      without a scoreable benchmark — the first seal ever, or a VRF-stall gap breaking
 *      seal adjacency — never settles, and once a later round seals, its bets refund the
 *      stake, both sides, once.
 *
 *      Stakes burn at placement; winners re-mint through the coinflip rail; dust and an
 *      empty winning side stay burned. Beyond the stakes the rail pays the gas-pegged
 *      settlement bounty (capped at one per winning bet ever) and the volume market's
 *      gated placement credit. Both markets require having ever bought anything. FLIP is
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

    /// @dev FLIP credited for placing a ticket-volume bet at the top of the window — the
    ///      daily market's participation incentive, in place of the growth market's
    ///      decaying quest. At most 2.5% of the stake it accompanies, so a placement is
    ///      deflationary on its own terms whatever the round pays.
    uint256 public constant VOLUME_BET_CREDIT = 25 ether;

    /// @dev The credit's decay clock: anchored at 23:15 UTC, -5 FLIP per full 10 minutes
    ///      elapsed — 25 through 23:24:59, then 20/15/10, and 5 from 23:55 to close. Late
    ///      bettors have watched more of the round; the decay prices that back out.
    uint256 private constant CREDIT_DECAY_START = 83_700; // 23:15:00 UTC
    uint256 private constant CREDIT_DECAY_STEP = 10 minutes;

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
    ///      Values are the SIDE_OVER/SIDE_UNDER encoding; 0 = unsettled. Separate mappings:
    ///      the markets number rounds independently (levels vs days) and would collide.
    mapping(uint24 => uint256) private growthOutcomeWords;
    mapping(uint24 => uint256) private volumeOutcomeWords;

    /// @dev The ticket-volume book, mirroring growthCounts / bets for the other market.
    mapping(uint24 => uint256) private volumeCounts;
    mapping(uint24 => mapping(address => uint8)) private volumeBets;

    /// @dev The ticket-volume benchmark, one slot: the last round the game sealed and that
    ///      round's total. A round is scoreable only against its immediate predecessor, so
    ///      both fields are needed — see recordVolume. lastVolumeRound doubles as the
    ///      closed-round marker the void rule reads.
    uint24 private lastVolumeRound;
    uint48 private prevVolume;

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

    /// @notice Emitted when a ticket-volume bet is placed.
    /// @param player The player the bet belongs to.
    /// @param round The round (game day) the bet joins.
    /// @param over True for the OVER side (volume rises), false for UNDER.
    /// @param credit FLIP credited for placing (0 when the player fails the gate).
    event VolumeBetPlaced(
        address indexed player,
        uint24 indexed round,
        bool over,
        uint256 credit
    );

    /// @notice Emitted when a ticket-volume bet is settled.
    /// @param player The bettor being paid.
    /// @param round The round (game day).
    /// @param outcome The round's side (1 = OVER, 2 = UNDER, 0 = voided).
    /// @param payout FLIP credited: a winner's share, or the stake back on a void.
    event VolumeBetClaimed(
        address indexed player,
        uint24 indexed round,
        uint8 outcome,
        uint256 payout
    );

    /// @notice Emitted when the game closes a ticket-volume round at its RNG request.
    /// @dev Carries the volume series the game no longer stores, so the history stays
    ///      reconstructible from logs. A round whose bits stay 0 after this event was not
    ///      scoreable against its predecessor — first seal, or a VRF-stall gap.
    /// @param round The round that closed.
    /// @param total The round's ticket volume, in raw purchase units (400 = 1 ticket).
    /// @param previous The benchmark it was scored against.
    event VolumeRoundSealed(
        uint24 indexed round,
        uint48 total,
        uint48 previous
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
        uint8 outcome = _readOutcome(growthOutcomeWords, round);
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

        uint8 outcome = _readOutcome(growthOutcomeWords, round);
        if (outcome == 0 || (bet & SIDE_MASK) != outcome) return 0;

        uint256 payout = _payout(round, outcome);
        growthBets[round][player] = bet | CLAIMED_BIT;
        emit BetClaimed(player, round, outcome, payout);
        return payout;
    }

    // =========================================================================
    // Ticket-volume market
    // =========================================================================

    /// @notice Place the ticket-volume bet for the open round.
    /// @dev Same shape and stake as the growth bet; the window and round come off the
    ///      clock (_openVolumeRound). Placement pays the decaying volumeBetCredit() off
    ///      the coinflip rail instead of a quest — a daily market on the quest ladder
    ///      would out-earn the growth bet several times over for the same act.
    /// @param player The player the bet belongs to (zero address for msg.sender).
    /// @param over True to bet volume rises against the previous round, false for UNDER.
    function placeVolumeBet(address player, bool over) external {
        if (player == address(0)) player = msg.sender;
        if (
            player != msg.sender &&
            !game.isOperatorApproved(player, msg.sender)
        ) revert NotApproved();

        (uint24 round, bool open) = _openVolumeRound();
        // Nothing has sealed yet, so the open round has no benchmark to be scored against
        // and could only ever void. Closed rather than open-and-worthless.
        if (!open || lastVolumeRound == 0) revert MarketClosed();
        if (volumeBets[round][player] != 0) revert AlreadyBet();

        (bool mayBet, bool earnsReward) = quests.marketBetGates(
            player,
            game.level()
        );
        if (!mayBet) revert NotEligible();

        volumeBets[round][player] = over ? SIDE_OVER : SIDE_UNDER;
        volumeCounts[round] += over ? 1 : (uint256(1) << 128);

        coin.burnCoin(player, STAKE);

        // Gate-cleared bettors earn the decaying credit; past the lifetime bar but short
        // of the level quest still bets, just without the bonus.
        uint256 credit;
        if (earnsReward) {
            credit = volumeBetCredit();
            coinflip.creditFlip(player, credit);
        }
        emit VolumeBetPlaced(player, round, over, credit);
    }

    /// @dev The open round and window, off the clock alone: 22:57–00:00 UTC, round =
    ///      day index + 1 (the break's RNG request closes one round and opens the next,
    ///      so an in-window bet joins the round that request opened).
    function _openVolumeRound() private view returns (uint24 round, bool open) {
        open = block.timestamp % 1 days >= GameTimeLib.JACKPOT_RESET_TIME;
        round = GameTimeLib.currentDayIndex() + 1;
    }

    /// @notice FLIP the placement credit pays a gate-clearing bettor right now.
    /// @dev Pure clock schedule (CREDIT_DECAY_START); in-window steps never exceed four,
    ///      so the quote never falls below 5 FLIP.
    function volumeBetCredit() public view returns (uint256) {
        uint256 tod = block.timestamp % 1 days;
        if (tod < CREDIT_DECAY_START) return VOLUME_BET_CREDIT;
        return
            VOLUME_BET_CREDIT -
            ((tod - CREDIT_DECAY_START) / CREDIT_DECAY_STEP) * 5 ether;
    }

    /// @notice Claim ticket-volume payouts for the named rounds.
    /// @dev Permissionless on the same grounds as the growth claim: a payout only ever
    ///      reaches the bettor who placed it.
    /// @param player The bettor to pay (zero address for msg.sender).
    /// @param rounds The rounds to claim.
    /// @return total FLIP credited across the batch.
    function claimVolume(
        address player,
        uint24[] calldata rounds
    ) external returns (uint256 total) {
        if (player == address(0)) player = msg.sender;

        uint256 len = rounds.length;
        for (uint256 i; i < len; ) {
            total += _claimVolume(player, rounds[i]);
            unchecked {
                ++i;
            }
        }

        if (total != 0) coinflip.creditFlip(player, total);
    }

    /// @dev Settle one ticket-volume round for one player: a winner's share, or on a
    ///      voided round the stake back. `round <= lastVolumeRound` is the closed test —
    ///      a later seal proves this round's crossover passed; above it, an unset bit
    ///      means "not yet" rather than "never".
    function _claimVolume(
        address player,
        uint24 round
    ) private returns (uint256) {
        uint8 bet = volumeBets[round][player];
        if (bet == 0 || (bet & CLAIMED_BIT) != 0) return 0;

        uint8 outcome = _readOutcome(volumeOutcomeWords, round);
        uint256 payout;
        if (outcome == 0) {
            if (round > lastVolumeRound) return 0;
            payout = STAKE;
        } else {
            if ((bet & SIDE_MASK) != outcome) return 0;
            payout = _payoutFrom(volumeCounts[round], outcome);
        }

        volumeBets[round][player] = bet | CLAIMED_BIT;
        emit VolumeBetClaimed(player, round, outcome, payout);
        return payout;
    }

    /// @notice Pay every winner on one settled ticket-volume round.
    /// @dev Mirror of claimRound. A voided round is not crankable — every position pays
    ///      the same stake back, so there is no shared divisor to amortize.
    /// @param round The round to settle.
    /// @param players The bettors to pay, a genuine unpaid winner first.
    /// @custom:reverts NothingToSettle If the round is unsettled or voided, the list is
    ///         empty, or the opening address is not an unpaid winner.
    /// @return total FLIP credited to winners, excluding the caller's bounty.
    function claimVolumeRound(
        uint24 round,
        address[] calldata players
    ) external returns (uint256 total) {
        uint256 len = players.length;
        if (len == 0) revert NothingToSettle();

        uint8 opener = volumeBets[round][players[0]];
        if (opener == 0 || (opener & CLAIMED_BIT) != 0) revert NothingToSettle();

        uint8 outcome = _readOutcome(volumeOutcomeWords, round);
        if (outcome == 0 || (opener & SIDE_MASK) != outcome) {
            revert NothingToSettle();
        }

        uint256 packed = volumeCounts[round];
        uint256 payout = _payoutFrom(packed, outcome);

        address[] memory winners = new address[](len + 1);
        uint256[] memory payouts = new uint256[](len + 1);
        uint256 settled;
        for (uint256 i; i < len; ) {
            address player = players[i];
            uint8 bet = volumeBets[round][player];
            if ((bet & SIDE_MASK) == outcome && (bet & CLAIMED_BIT) == 0) {
                volumeBets[round][player] = bet | CLAIMED_BIT;
                winners[i] = player;
                payouts[i] = payout;
                total += payout;
                unchecked {
                    ++settled;
                }
                emit VolumeBetClaimed(player, round, outcome, payout);
            }
            unchecked {
                ++i;
            }
        }

        (, , , uint24 currentLevel, bool bettingOpen, ) = game.growthState(0);
        winners[len] = msg.sender;
        payouts[len] =
            (settled * CRANK_BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) /
            PriceLookupLib.priceForLevel(
                bettingOpen ? currentLevel : currentLevel + 1
            );

        coinflip.creditFlipBatch(winners, payouts);
    }

    /// @notice The open ticket-volume round, plus one player's position on a round.
    /// @param player The player whose position to report (address(0) for none).
    /// @param round The round to report the position for.
    /// @return openRound The round a bet placed now would join (0 when betting is closed).
    /// @return overCount Bets on the OVER side of `round`.
    /// @return underCount Bets on the UNDER side of `round`.
    /// @return side The player's side on `round`: 1 = OVER, 2 = UNDER (0 = no bet).
    /// @return claimed True once the player has taken the payout for `round`.
    /// @return outcome `round`'s side (0 = unsettled, or voided once it has closed).
    /// @return voided True when `round` closed with no comparable benchmark.
    /// @return payout FLIP claimable now — a winner's share, or the stake back on a void.
    function volumeMarketState(
        address player,
        uint24 round
    )
        external
        view
        returns (
            uint24 openRound,
            uint128 overCount,
            uint128 underCount,
            uint8 side,
            bool claimed,
            uint8 outcome,
            bool voided,
            uint256 payout
        )
    {
        (uint24 open, bool bettingOpen) = _openVolumeRound();
        if (bettingOpen && lastVolumeRound != 0) openRound = open;

        uint256 packed = volumeCounts[round];
        overCount = uint128(packed);
        underCount = uint128(packed >> 128);

        uint8 bet = volumeBets[round][player];
        side = bet & SIDE_MASK;
        claimed = (bet & CLAIMED_BIT) != 0;
        outcome = _readOutcome(volumeOutcomeWords, round);
        voided = outcome == 0 && round <= lastVolumeRound && lastVolumeRound != 0;

        if (side != 0 && !claimed) {
            if (voided) payout = STAKE;
            else if (side == outcome) payout = _payoutFrom(packed, outcome);
        }
    }

    // =========================================================================
    // Settlement pushes (GAME only)
    // =========================================================================

    /// @inheritdoc IDegenerusParimutuel
    /// @dev Scored only against the immediately preceding round: the first-ever seal and
    ///      any VRF-stall gap have no honest benchmark, get no bit, and void rather than
    ///      hand the outcome to whoever watched the stall.
    function recordVolume(uint24 round, uint48 total) external {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        uint24 last = lastVolumeRound;
        uint48 prev = prevVolume;
        lastVolumeRound = round;
        prevVolume = total;
        if (last != 0 && round == last + 1) {
            _writeOutcome(
                volumeOutcomeWords,
                round,
                total > prev ? SIDE_OVER : SIDE_UNDER
            );
        }
        emit VolumeRoundSealed(round, total, prev);
    }

    /// @inheritdoc IDegenerusParimutuel
    function recordGrowth(uint24 round, bool over) external {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        _writeOutcome(
            growthOutcomeWords,
            round,
            over ? SIDE_OVER : SIDE_UNDER
        );
        emit GrowthRoundSealed(round, over);
    }

    /// @dev Write-once latch: a settled round's answer is permanent by structure.
    function _writeOutcome(
        mapping(uint24 => uint256) storage words,
        uint24 round,
        uint8 side
    ) private {
        uint24 word = round >> 7;
        uint256 shift = (uint256(round) & 127) << 1;
        uint256 packed = words[word];
        if (((packed >> shift) & SIDE_MASK) != 0) return;
        words[word] = packed | (uint256(side) << shift);
    }

    /// @dev A round's settled side, or 0 if it has not settled.
    function _readOutcome(
        mapping(uint24 => uint256) storage words,
        uint24 round
    ) private view returns (uint8) {
        return
            uint8(
                (words[round >> 7] >> ((uint256(round) & 127) << 1)) & SIDE_MASK
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
        outcome = _readOutcome(growthOutcomeWords, round);
        if (side != 0 && !claimed && side == outcome) {
            payout = _payoutFrom(packed, outcome);
        }
    }
}
