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

/*+==============================================================================+
  |                        DEGENERUS JACKPOTS CONTRACT                           |
  |                                                                              |
  |  Standalone contract managing the BAF (Big Ass Flip) jackpot system.         |
  |  Decimator logic is handled in the game decimator module.                    |
  +==============================================================================+*/

import {IDegenerusGame} from "./interfaces/IDegenerusGame.sol";
import {IDegenerusJackpots} from "./interfaces/IDegenerusJackpots.sol";
import {ContractAddresses} from "./ContractAddresses.sol";
import {EntropyLib} from "./libraries/EntropyLib.sol";
import {GameTimeLib} from "./libraries/GameTimeLib.sol";

// ===========================================================================
// External Interfaces
// ===========================================================================

/// @notice View interface for coin contract jackpot-related queries.
/// @dev Used to draw the weighted final-day depositor slice.
interface IDegenerusCoinJackpotView {
    /// @notice One amount-weighted random winner among the armed final-day direct
    ///         coinflip deposits, as a wallet ID (0 when the day recorded none).
    /// @param rngWord The BAF transition VRF word (domain-separated inside Coinflip).
    /// @return winnerId The drawn depositor's wallet ID, or 0 (no winner).
    function bafDrawWinner(uint256 rngWord) external view returns (uint32 winnerId);
}

// ===========================================================================
// Contract
// ===========================================================================

/// @notice WWXRP mint surface for skipped-bracket consolation prizes.
interface IWwxrpMintPrize {
    /// @notice Mint WWXRP to a recipient.
    function mintPrize(address to, uint256 amount) external;
}

/// @title DegenerusJackpots
/// @author Burnie Degenerus
/// @notice Standalone contract managing the BAF jackpot system.
/// @dev Coinflip forwards flips into this contract; game calls to resolve jackpots.
///      - BAF: Leaderboard-based distribution to top BAF bettors, plus one
///        amount-weighted random final-day coinflip depositor
///      - Decimator: handled in the game decimator module
///      - Skipped brackets (daily flip lost): players claim a WWXRP consolation
///        proportional to their frozen bracket score via claimBafConsolation
/// @custom:security-contact burnie@degener.us
contract DegenerusJackpots is IDegenerusJackpots {
    /*+======================================================================+
      |                              ERRORS                                  |
      +======================================================================+
      |  Custom errors for gas-efficient reverts. Each error maps to a       |
      |  specific failure condition in jackpot operations.                   |
      +======================================================================+*/

    /// @notice Thrown when a function restricted to the coinflip contract is called by another address.
    error OnlyCoin();

    /// @notice Thrown when a function restricted to the game contract is called by another address.
    error OnlyGame();

    /// @notice Thrown when a consolation claim covers no claimable score.
    error NothingToClaim();

    /*+======================================================================+
      |                              EVENTS                                  |
      +======================================================================+
      |  Events for tracking BAF state changes for indexers.                 |
      +======================================================================+*/

    /// @notice Emitted when a player's winning-flip payout is credited to their BAF score.
    /// @param id The player's wallet ID.
    /// @param lvl BAF bracket (level rounded up to the next multiple of 10).
    /// @param amount Amount added this flip.
    /// @param newTotal Player's new accumulated BAF credit for this bracket.
    event BafFlipRecorded(
        uint32 indexed id,
        uint24 indexed lvl,
        uint256 amount,
        uint256 newTotal
    );

    /// @notice Emitted when a BAF bracket is skipped because the daily flip lost.
    /// @param lvl Level whose BAF was skipped.
    /// @param day Day index on which the skip occurred.
    event BafSkipped(uint24 indexed lvl, uint24 day);

    /// @notice Emitted when the WWXRP consolation for a skipped bracket is claimed.
    /// @param player Key of the score owner account; its payee receives the mint (claims are
    ///        permissionless).
    /// @param lvl Skipped BAF bracket level.
    /// @param score Frozen bracket score consumed by the claim (FLIP-denominated).
    /// @param wwxrpAmount WWXRP requested (score / 1000, minimum 1 for a positive score), before gameMintScale.
    event BafConsolationClaimed(
        address indexed player,
        uint24 indexed lvl,
        uint256 score,
        uint256 wwxrpAmount
    );

    /*+======================================================================+
      |                              STRUCTS                                 |
      +======================================================================+
      |  Data structures for BAF leaderboard tracking.                       |
      +======================================================================+*/

    /// @notice Per-player BAF state for a bracket level.
    /// @dev Packed into single slot: total (192) + epoch (64) = 256 bits.
    ///      A total whose epoch is stale (bracket already resolved) reads as zero.
    struct BafPlayer {
        /// @notice Accumulated winning-flip payout credit (saturates at uint192.max).
        uint192 total;
        /// @notice Bracket epoch the total belongs to.
        uint64 epoch;
    }

    /// @notice Per-level BAF bracket state.
    /// @dev Packed into single slot: epoch (64) + topLen (8) + skipped (8). Epoch and
    ///      topLen are touched by every flip credit, so sharing a slot makes the second
    ///      read warm; skipped rides along for free.
    struct BafLevel {
        /// @notice Epoch counter, incremented on jackpot resolution (lazy-resets player totals).
        uint64 epoch;
        /// @notice Current length of the bafTop board (0-4).
        uint8 topLen;
        /// @notice True once the bracket's BAF was skipped (daily flip lost). Terminal:
        ///         a skipped bracket can never resolve, so this is the exact gate for
        ///         WWXRP consolation claims against the bracket's frozen scores.
        bool skipped;
    }

    /*+======================================================================+
      |                            CONSTANT STATE                            |
      +======================================================================+
      |  Trusted contract addresses fixed at deployment.                     |
      +======================================================================+*/

    /// @notice Coinflip contract for coinflip stats queries (constant).
    IDegenerusCoinJackpotView internal constant coin = IDegenerusCoinJackpotView(ContractAddresses.COINFLIP);

    /// @notice Core game contract for jackpot resolution and player queries (constant).
    IDegenerusGame internal constant degenerusGame = IDegenerusGame(ContractAddresses.GAME);

    /// @notice WWXRP token minted as skipped-bracket consolation (constant).
    IWwxrpMintPrize internal constant wwxrp = IWwxrpMintPrize(ContractAddresses.WWXRP);


    /*+======================================================================+
      |                            CONSTANTS                                 |
      +======================================================================+
      |  Fixed values for prize calculations and BAF configuration.          |
      +======================================================================+*/

    /// @dev Entropy key of the far-future pair draws, above every scatter round index.
    uint256 private constant BAF_FAR_PAIR_KEY = 1 << 16;
    /// @dev Entropy key of head slot 2's third-or-fourth pick.
    uint256 private constant BAF_HEAD_PICK_KEY = 1 << 17;
    bytes32 private constant BAF_WINNERS_TAG = keccak256("degenerus.baf.winners");

    /// @dev Skipped-bracket consolation rate: 1 WWXRP per 1000 FLIP of frozen
    ///      bracket score (both whole tokens), with a minimum of 1 for a positive score.
    ///      WWXRP emission is economically
    ///      inert — daily-draw prizes are fixed FLIP amounts at fixed odds —
    ///      so the mint carries no protocol liability.
    uint256 private constant CONSOLATION_DIVISOR = 1000;

    /// @dev The Game's constant wallet ID for the vault.
    uint32 private constant VAULT_WALLET_ID = 1;

    /// @dev One leaderboard entry's 128-bit lane: score in the low 96 bits, wallet ID above.
    uint256 private constant TOP_ENTRY_MASK = type(uint128).max;


    /*+======================================================================+
      |                         BAF STATE STORAGE                            |
      +======================================================================+
      |  Per-player BAF totals and top-4 leaderboard per level.              |
      +======================================================================+*/

    /// @notice Accumulated winning-flip payout credit + owning epoch per wallet ID per BAF bracket.
    mapping(uint24 => mapping(uint32 => BafPlayer)) internal bafPlayer;

    /// @notice Top-4 coinflip bettors for BAF per level, sorted by score descending. Two 128-bit
    ///         entries per word: entry i lives in word i >> 1 at bit (i & 1) * 128, laid out as
    ///         score (bits 0-95, whole tokens capped at uint96.max) | wallet ID (bits 96-127).
    mapping(uint24 => uint256[2]) internal bafTop;

    /// @notice Epoch counter + bafTop board length per BAF bracket level.
    mapping(uint24 => BafLevel) internal bafLevel;

    /// @notice Day index of the most recent BAF resolution or skip (any bracket).
    uint24 internal lastBafResolvedDay;

    constructor() {
        // Register this contract's ENS reverse name (best-effort; skipped when the
        // registrar is unset — local/test/testnet builds). The setName(string)
        // selector is shared by the L1 ReverseRegistrar and Base's L2ReverseRegistrar.
        address ensReg = ContractAddresses.ENS_REVERSE_REGISTRAR;
        if (ensReg != address(0)) {
            (bool ok, ) = ensReg.call(
                // raw-selectors: justified — best-effort ENS reverse-name; setName(string) has no deploy-wide bound interface and must not revert deployment
                abi.encodeWithSignature("setName(string)", "jackpots.degenerus.eth")
            );
            ok;
        }
    }

    /*+======================================================================+
      |                      MODIFIERS & ACCESS CONTROL                      |
      +======================================================================+
      |  Access control for trusted callers only.                            |
      +======================================================================+*/

    /// @dev Restricts function to the coinflip contract.
    /// @custom:reverts OnlyCoin When caller is not the coinflip contract.
    modifier onlyCoin() {
        if (msg.sender != ContractAddresses.COINFLIP) revert OnlyCoin();
        _;
    }

    /// @dev Restricts function to game contract only.
    /// @custom:reverts OnlyGame When caller is not the game contract.
    modifier onlyGame() {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        _;
    }

    /*+======================================================================+
      |                      COINFLIP CONTRACT HOOKS                         |
      +======================================================================+
      |  Called by Coinflip to record coinflip activity.                     |
      |  These hooks build state used by jackpot resolution.                 |
      +======================================================================+*/

    /// @notice Record a coinflip win for BAF score tracking.
    /// @dev Called by COINFLIP when a player's winnings settle. VAULT accrues a BAF score like any
    ///      player — so it can rank in the score-ranked ticket slices whose tickets it holds — but
    ///      is kept OFF the top-4 leaderboard (no _updateBafTop), so it can never take the
    ///      top-bettor slices. sDGNRS gets no BAF score at all: it is skipped upstream at the
    ///      recordBafFlip call site (its free per-level flips would otherwise dominate the slices).
    ///      Coinflip reports only a nonzero wallet ID (its claim walk runs only under one).
    /// @param id The player's wallet ID.
    /// @param lvl BAF bracket (level rounded up to the next multiple of 10).
    /// @param amount Winning coinflip payout credited to the player's BAF score.
    /// @custom:access Restricted to COINFLIP via onlyCoin modifier.
    function recordBafFlip(uint32 id, uint24 lvl, uint256 amount) external override onlyCoin {
        uint64 currentEpoch = bafLevel[lvl].epoch;
        BafPlayer memory ps = bafPlayer[lvl][id];
        // A stale epoch means the bracket already resolved: restart the total from zero.
        uint256 total = ps.epoch == currentEpoch ? ps.total : 0;
        unchecked { total += amount; }
        if (total > type(uint192).max) total = type(uint192).max;
        bafPlayer[lvl][id] = BafPlayer({total: uint192(total), epoch: currentEpoch});

        // VAULT accrues a score (above) but stays off the leaderboard: it can never win the
        // top-bettor slices, while still ranking in the score-ranked ticket slices it holds.
        if (id != VAULT_WALLET_ID) {
            _updateBafTop(lvl, id, total);
        }
        emit BafFlipRecorded(id, lvl, amount, total);
    }

    /*+========================================================================+
      |                      BAF JACKPOT RESOLUTION                            |
      +========================================================================+
      |  Distributes ETH prize pool to various winner categories.              |
      |                                                                        |
      |  PRIZE DISTRIBUTION:                                                   |
      |  +-------------------------------------------------------------------+ |
      |  | 10% | Top BAF bettor for this level                               | |
      |  |  5% | Weighted-random final-day coinflip depositor                | |
      |  |  5% | Random pick: 3rd or 4th BAF slot                            | |
      |  | 50% | Scatter 1st place (R rounds x 4 sampled candidates)         | |
      |  | 30% | Scatter 2nd place (R rounds x 4 sampled candidates)         | |
      |  +-------------------------------------------------------------------+ |
      |  R: 48 below a 500 ETH pool, doubled per fourfold step, max 1,536.     |
      |                                                                        |
      |  ELIGIBILITY:                                                          |
      |  * Top-BAF/pick: any wallet on the board (no streak req)               |
      |  * Weighted depositor slice: drawn in Coinflip over the armed final    |
      |    day's direct deposits, weight = raw FLIP principal                  |
      |  * Far-future & scatter: additionally require a positive BAF score;    |
      |    zero-score candidates are skipped and their share refunds           |
      |                                                                        |
      |  SECURITY:                                                             |
      |  • VRF-derived randomness for all random selections                    |
      |  • Draws hashed per round pair from the single VRF seed                |
      |  • Unfilled awards leave their reserve to the game's future pool       |
      +========================================================================+*/

    /// @notice Opens a bracket's resolution: winning-flip credit claimed from today on belongs
    ///         to the next bracket.
    /// @custom:access Restricted to game contract via onlyGame modifier.
    function beginBaf() external onlyGame {
        lastBafResolvedDay = GameTimeLib.currentDayIndex();
    }

    /// @notice Closes a resolved bracket once every award is paid: clears the board and bumps
    ///         the epoch so every stored score reads zero.
    /// @param lvl Level whose bracket resolved.
    /// @custom:access Restricted to game contract via onlyGame modifier.
    function finalizeBaf(uint24 lvl) external onlyGame {
        BafLevel memory current = bafLevel[lvl];
        if (current.topLen != 0) delete bafTop[lvl][0];
        if (current.topLen > 2) delete bafTop[lvl][1];
        unchecked {
            bafLevel[lvl] = BafLevel({epoch: current.epoch + 1, topLen: 0, skipped: false});
        }
    }

    /// @notice One of the bracket's three head awards: slot 0 the top BAF bettor, slot 1 the
    ///         armed final purchase day's amount-weighted direct depositor (drawn inside
    ///         Coinflip from the same word), slot 2 a word-picked third or fourth place.
    /// @dev Pure in the frozen board, the word and the slot; 0 (no winner) when the slot is empty.
    function bafHeadWinner(uint24 lvl, uint256 rngWord, uint8 slot) external view returns (uint32 winnerId) {
        if (slot == 0) (winnerId, ) = _bafTop(lvl, 0);
        else if (slot == 1) winnerId = coin.bafDrawWinner(rngWord);
        else (winnerId, ) = _bafTop(lvl, 2 + uint8(EntropyLib.hash2(_bafEntropyBase(rngWord), BAF_HEAD_PICK_KEY) & 1));
    }

    /// @notice Scatter rounds 2 * pair and 2 * pair + 1 of the bracket: each round's best and
    ///         second-best BAF score among its four sampled candidates, as [best, second] of the
    ///         even round then of the odd round, as wallet IDs (0 where none qualifies).
    /// @dev Pure in the bracket, the word, the pair, the round count and the bucket and queue
    ///      entries it samples. Four bands of `rounds / 4` rounds (`rounds` a multiple of 8, so a
    ///      pair never straddles two bands): trait buckets at lvl and lvl + 1 (each round four
    ///      entries of one packed word), then one queue lane per wallet over lvl + 2..lvl + 5 and
    ///      lvl + 6..lvl + 99, where one sample of eight lanes serves the pair (the even round
    ///      ranks the first four).
    function bafPairWinners(uint24 lvl, uint256 rngWord, uint256 pair, uint256 rounds)
        external view returns (uint32[4] memory winners)
    {
        uint256 base = _bafEntropyBase(rngWord);
        uint256 band = (pair * 8) / rounds;
        uint64 currentEpoch = bafLevel[lvl].epoch;
        uint32[] memory tickets;
        if (band < 2) {
            (, tickets) = degenerusGame.sampleTraitEntries(band == 1, EntropyLib.hash2(base, 2 * pair));
            (winners[0], winners[1]) = _bafRank(tickets, 0, lvl, currentEpoch);
            (, tickets) = degenerusGame.sampleTraitEntries(band == 1, EntropyLib.hash2(base, 2 * pair + 1));
            (winners[2], winners[3]) = _bafRank(tickets, 0, lvl, currentEpoch);
        } else {
            uint256 pairEntropy = EntropyLib.hash2(base, BAF_FAR_PAIR_KEY | pair);
            tickets = band == 2
                ? degenerusGame.sampleFarFutureTickets(pairEntropy, lvl + 2, lvl + 5)
                : degenerusGame.sampleFarFutureTickets(pairEntropy, lvl + 6, lvl + 99);
            (winners[0], winners[1]) = _bafRank(tickets, 0, lvl, currentEpoch);
            (winners[2], winners[3]) = _bafRank(tickets, 4, lvl, currentEpoch);
        }
    }

    /// @dev Best and second-best BAF score among the four candidate wallet IDs from `off` (fewer
    ///      when the sample is shorter); 0 where none qualifies. An unfilled sample slot is ID 0,
    ///      which never holds a score.
    function _bafRank(uint32[] memory tickets, uint256 off, uint24 lvl, uint64 currentEpoch)
        private
        view
        returns (uint32 best, uint32 second)
    {
        uint256 end = off + 4;
        if (end > tickets.length) end = tickets.length;
        uint256 bestScore;
        uint256 secondScore;
        for (uint256 i = off; i < end; ) {
            uint32 cand = tickets[i];
            uint256 score = _bafScore(cand, lvl, currentEpoch);
            if (score > bestScore) {
                second = best;
                secondScore = bestScore;
                best = cand;
                bestScore = score;
            } else if (score > secondScore && cand != best) {
                second = cand;
                secondScore = score;
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @dev The bracket's winner stream, separate from the craps schedule's (word, ordinal) stream.
    function _bafEntropyBase(uint256 rngWord) private pure returns (uint256) {
        return EntropyLib.hash2(rngWord, uint256(BAF_WINNERS_TAG));
    }

    /// @notice Mark a BAF bracket as skipped because the daily flip lost.
    /// @dev Bumps lastBafResolvedDay so pre-skip winning-flip credit is filtered
    ///      out of future claims (Coinflip gates winningBafCredit on
    ///      cursor >= lastBafResolvedDay). Leaderboard state for lvl is left
    ///      as-is — no new writes ever target a past bracket, so clearing
    ///      would only burn gas. Sets the bracket's skipped flag: the frozen
    ///      player scores become claimable as WWXRP consolation.
    /// @param lvl Level whose BAF was skipped.
    /// @custom:access Restricted to game contract via onlyGame modifier.
    function markBafSkipped(uint24 lvl) external onlyGame {
        bafLevel[lvl].skipped = true;
        // Day computed locally: identical to game.currentDayView() (pure GameTimeLib
        // wall-clock) without the external call.
        uint24 today = GameTimeLib.currentDayIndex();
        lastBafResolvedDay = today;
        emit BafSkipped(lvl, today);
    }

    /*+======================================================================+
      |                  SKIPPED-BRACKET WWXRP CONSOLATION                   |
      +======================================================================+
      |  When a bracket's BAF skips (daily flip lost), the ETH pool rolls    |
      |  forward but the players' accumulated scores are wasted. Those       |
      |  scores are frozen in storage (the epoch only bumps on resolution,   |
      |  and no new credit can target a past bracket), so each score can be  |
      |  redeemed once at score / 1000, minimum 1 for a positive score.      |
      +======================================================================+*/

    /// @notice Claim the WWXRP consolation of account `id` for a skipped BAF bracket.
    /// @dev Permissionless: anyone may execute, but the mint always goes to
    ///      the score owner's payee — no value can move from a non-consenting
    ///      party. The score is keyed by the owner's Game wallet ID; a wallet without
    ///      one holds no score. `id == 0` is the caller (ID from Game `walletIdOf`, paid
    ///      to the caller); any other ID resolves its payee through Game
    ///      `resolveAccount` (authorization is not required). Pays only when the bracket
    ///      is marked skipped and the score
    ///      belongs to the bracket's live epoch (a resolved bracket bumped its
    ///      epoch, so its scores read stale and pay nothing). Deleting the
    ///      score slot is the claim flag — no separate mapping. The delete can
    ///      never affect a jackpot resolution: skipped is terminal, so a
    ///      claimable bracket can never resolve later. VAULT's consolation
    ///      (it accrues bracket score from its daily flips) escrows into its
    ///      WWXRP mint allowance via the token's vault routing.
    /// @param id Score owner account (0 = caller).
    /// @param lvl Skipped bracket level to claim.
    /// @custom:reverts E (Game) When `id` is unallocated.
    /// @custom:reverts NothingToClaim When the bracket is not skipped, the
    ///         score is stale/absent/already claimed.
    function claimBafConsolation(uint32 id, uint24 lvl) external {
        BafLevel memory lv = bafLevel[lvl];
        if (!lv.skipped) revert NothingToClaim();
        address key = msg.sender;
        address payee = msg.sender;
        if (id == 0) {
            // A caller with no ID reads the never-written key 0: no score, nothing to claim.
            id = degenerusGame.walletIdOf(msg.sender);
        } else {
            (key, payee, ) = degenerusGame.resolveAccount(id, msg.sender);
        }
        BafPlayer memory ps = bafPlayer[lvl][id];
        if (ps.epoch != lv.epoch) revert NothingToClaim();
        uint256 amount = _bafConsolationAmount(ps.total);
        if (amount == 0) revert NothingToClaim();
        delete bafPlayer[lvl][id];
        emit BafConsolationClaimed(key, lvl, ps.total, amount);
        wwxrp.mintPrize(payee, amount);
    }

    /// @notice Claimable WWXRP consolation for a player at a bracket level, before WWXRP's
    ///         gameMintScale (the mint at claim is scaled).
    /// @return Zero unless the bracket is skipped and the player holds an
    ///         unclaimed live-epoch score.
    function bafConsolationOf(address player, uint24 lvl) external view returns (uint256) {
        BafLevel memory lv = bafLevel[lvl];
        if (!lv.skipped) return 0;
        BafPlayer memory ps = bafPlayer[lvl][degenerusGame.walletIdOf(player)];
        if (ps.epoch != lv.epoch) return 0;
        return _bafConsolationAmount(ps.total);
    }

    /// @dev Round positive sub-token consolation up to one; an absent score stays zero.
    function _bafConsolationAmount(uint256 score) private pure returns (uint256) {
        if (score == 0) return 0;
        uint256 amount = score / CONSOLATION_DIVISOR;
        return amount == 0 ? 1 : amount;
    }

    /*+======================================================================+
      |                      BAF LEADERBOARD HELPERS                         |
      +======================================================================+
      |  Maintain sorted top-4 leaderboard per level.                        |
      +======================================================================+*/

    /// @dev Get a wallet's BAF score for a level.
    /// @param id Wallet ID to query.
    /// @param lvl Level number.
    /// @param currentEpoch The bracket's current epoch (read once per resolution by callers).
    /// @return Accumulated winning-flip payout credit (0 if the stored epoch is stale).
    function _bafScore(uint32 id, uint24 lvl, uint64 currentEpoch) private view returns (uint256) {
        BafPlayer memory ps = bafPlayer[lvl][id];
        if (ps.epoch != currentEpoch) return 0;
        return ps.total;
    }

    /// @dev Convert raw score to capped uint96 (whole tokens only).
    /// @param s Raw score in base units.
    /// @return Capped score in whole tokens.
    function _score96(uint256 s) private pure returns (uint96) {
        uint256 wholeTokens = s;
        if (wholeTokens > type(uint96).max) {
            wholeTokens = type(uint96).max;
        }
        return uint96(wholeTokens);
    }

    /// @dev Update top-4 BAF leaderboard with new stake.
    ///      Maintains sorted order (highest score first).
    ///      Handles existing player update, new player insertion, and capacity management.
    ///      Entries shift down through the two packed words in place.
    /// @param lvl Level number.
    /// @param id Wallet ID.
    /// @param stake New total stake for the wallet.
    function _updateBafTop(uint24 lvl, uint32 id, uint256 stake) private {
        uint96 score = _score96(stake);
        uint256[2] storage board = bafTop[lvl];
        uint8 len = bafLevel[lvl].topLen;
        uint256 entry = uint256(score) | (uint256(id) << 96);

        // Check if the wallet is already on the leaderboard
        uint8 existing = 4; // sentinel: not found
        for (uint8 i; i < len; ) {
            if (uint32(_topEntry(board, i) >> 96) == id) {
                existing = i;
                break;
            }
            unchecked {
                ++i;
            }
        }

        // Case 1: Already on board - shift down and re-place if improved
        // (same shift-then-place idiom as Cases 2/3; strict > keeps tie order).
        if (existing < 4) {
            if (score <= uint96(_topEntry(board, existing))) return; // No improvement
            uint8 idx = existing;
            while (idx > 0) {
                uint256 above = _topEntry(board, idx - 1);
                if (score <= uint96(above)) break;
                _setTopEntry(board, idx, above);
                unchecked {
                    --idx;
                }
            }
            _setTopEntry(board, idx, entry);
            return;
        }

        // Case 2: Board not full - insert in sorted position
        if (len < 4) {
            uint8 insert = len;
            while (insert > 0) {
                uint256 above = _topEntry(board, insert - 1);
                if (score <= uint96(above)) break;
                _setTopEntry(board, insert, above);
                unchecked {
                    --insert;
                }
            }
            _setTopEntry(board, insert, entry);
            bafLevel[lvl].topLen = len + 1;
            return;
        }

        // Case 3: Board full - replace bottom if score is higher
        if (score <= uint96(_topEntry(board, 3))) return; // Not good enough
        uint8 idx2 = 3;
        while (idx2 > 0) {
            uint256 above = _topEntry(board, idx2 - 1);
            if (score <= uint96(above)) break;
            _setTopEntry(board, idx2, above);
            unchecked {
                --idx2;
            }
        }
        _setTopEntry(board, idx2, entry);
    }

    /// @dev Leaderboard entry `i` (score | wallet ID << 96) from its packed word.
    function _topEntry(uint256[2] storage board, uint256 i) private view returns (uint256) {
        return (board[i >> 1] >> ((i & 1) << 7)) & TOP_ENTRY_MASK;
    }

    /// @dev Write leaderboard entry `i`, keeping the other entry of its word.
    function _setTopEntry(uint256[2] storage board, uint256 i, uint256 entry) private {
        uint256 shift = (i & 1) << 7;
        uint256 w = board[i >> 1];
        board[i >> 1] = (w & ~(TOP_ENTRY_MASK << shift)) | (entry << shift);
    }

    /// @dev Get the wallet at a leaderboard position.
    /// @param lvl Level number.
    /// @param idx Position (0 = top).
    /// @return id Wallet ID at the position (0 if empty).
    /// @return score The wallet's score.
    function _bafTop(uint24 lvl, uint8 idx) private view returns (uint32 id, uint96 score) {
        uint8 len = bafLevel[lvl].topLen;
        if (idx >= len) return (0, 0);
        uint256 entry = _topEntry(bafTop[lvl], idx);
        return (uint32(entry >> 96), uint96(entry));
    }

    /*+======================================================================+
      |                         VIEW FUNCTIONS                               |
      +======================================================================+*/

    /// @notice Day index of the most recent BAF resolution or skip.
    function getLastBafResolvedDay() external view returns (uint24) {
        return lastBafResolvedDay;
    }
}
