// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Craps} from "./Craps.sol";
import {LootboxCraps} from "./LootboxCraps.sol";
import {ContractAddresses} from "./ContractAddresses.sol";
import {FlipRoundLib} from "./libraries/FlipRoundLib.sol";

/// @dev The two FLIP sinks this game uses, both authorized to `ContractAddresses.CRAPS` in the
///      protocol's FLIP.sol — `burnCoin` takes the stake, `mintForGame` pays the win.
interface IFlipCoin {
    function burnCoin(address target, uint256 amount) external;
    function mintForGame(address to, uint256 amount) external;
}

/// @dev The one activity read the odds allowance and the rakeback rate use.
interface IGameActivityScore {
    function playerActivityScore(address player) external view returns (uint256 scorePoints);
}

/// @dev The rakeback's delivery vehicle: the protocol's flip-creditors lane, the same one its own
///      bounties pay through. No minimum, no deposit mechanics — the credit IS next-day coinflip
///      stake, and FLIP only ever materialises if the flip wins.
interface ICoinflipStake {
    function creditFlip(address player, uint256 amount) external;
}

/// @title FlipCraps
/// @notice Craps staked in FLIP, settled the way Degenerette settles FLIP.
///
///         The stake is burned when the bet is placed and the win is minted when it settles. There
///         is no reserve and no pool: FLIP payouts in this protocol have never needed one, because
///         a mint is not paid out of anything. That is the whole reason this is the FLIP-only
///         table — the ETH side of Degenerette debits the prize pool and credits the game's
///         `claimable`, neither of which anything outside `DegenerusGame` can reach.
///
/// @dev THE SURVIVAL FLIP — ONE PER TABLE, PER EXIT ROUND
///
///      Every payout double-or-nothings once, at the end of it all, on a coin keyed to the table
///      and the round the run ended on. Everyone who lasted the same number of shooters at one
///      index shares a coin — so two identical bets still double or bust together — while a run
///      that ended on a different round gets its own. EV-neutral either way: half of all coins pay
///      double, half pay nothing.
///
///      The exit round is in the key so that settling cannot spoil the table. A word is public the
///      moment it lands, so a single shared coin meant the first player to settle a two-shooter run
///      published the answer for everyone still holding a long one.
///
///      What the key must never contain is anything the CALLER composes. Settlement is
///      permissionless and `betIds[]` is caller-chosen, so a flip keyed on a batch total would let
///      a settler enumerate partitions against an already-public word and take whichever split
///      flips best. Nothing here is composable: `(word, index)` were both fixed before any bet
///      could see them, and `handsPlayed` is a pure function of a board, bankroll and goal that
///      were all committed while the word did not yet exist. No arrangement of `betIds[]`, and no
///      decision taken after the dice are public, moves any outcome by a single wei. The per-bet
///      rounding roll stays keyed to `(word, betId)`, both committed at placement, for the same
///      reason.
///
///      The flip lands on everything coming back, stake included, because the stake was burned at
///      placement and never returns on its own. So a table that made money can still pay zero, and
///      one that limped home can pay double.
///
/// @dev MAX ODDS SCALE WITH ACTIVITY
///
///      Odds are the only zero-edge bet on the table, which makes the odds ALLOWANCE the natural
///      loyalty perk: the more a player actually plays the game, the more zero-edge money they may
///      put behind their line bets. Two linear segments: 3x for anyone, climbing to the 100x table
///      at 400 points (the lootbox curve's first knee), then on to 1000x at 2,000 points, which is
///      the ceiling. The ceiling is a product choice, not a solvency one — odds wins mint FLIP
///      like every other payout and are zero-edge at any size, so a degen who wants to gamble big
///      costs the protocol nothing in expectation. The score is read from the game at placement,
///      so the allowance is judged on who the player is when they bet, and a bet once accepted is
///      never re-judged.
///
/// @dev THE BET SLIP — THE ONLY WAY TO PLAY
///
///      The player puts down a bankroll and the wager repeats out of it, shooter after shooter,
///      until the bankroll cannot cover one more round, reaches half of the payout goal they
///      chose, or hits the shooter cap. Stops are judged between shooters, goal before bust. The
///      half-goal is rounded up, so a surviving table's 2x flip reaches at least the requested
///      target before award rounding. A busted slip keeps its sub-stake remainder — nothing is
///      confiscated for stopping. The whole run settles once, so the survival flip lands on the
///      FINAL BANKROLL: a slip that reached its bankroll target can still bust the coin, and one
///      that limped home can double. Slip hand `i` is the table's shooter `i`, the same dice every
///      other slip at the index watches.
///
///      Three table rules shape every slip. The board must total at least `MIN_BOARD_FLIP` whole
///      FLIP; the bankroll may cover at most `MAX_BANKROLL_MULT` rounds of it — a bigger appetite
///      means a bigger board, not a longer grind on a small one; and the engine's escalator
///      (`Craps.ESC_HANDS`) doubles the mandatory wager every five shooters — so a run is a RACE:
///      reach the goal before the rising floor crushes the bankroll. The goal itself is capped at
///      `MAX_GOAL_MULT` times the bankroll, which bounds how long that race can even be asked to
///      run.
///
/// @dev THE RAKEBACK
///
///      Every settlement comps the player a slice of their EXPECTED loss — the theo, computed from
///      the board's exact per-leg edges times the shooters actually played — never their actual
///      result. That is how a casino host comps and it is manipulation-proof: theo depends only on
///      what was wagered, so no one can farm it by winning or tank into it by losing; its EV cost
///      is a fixed fraction of the house's own EV income. The slice scales with activity score,
///      LOCKED AT PLACEMENT: zero at score zero — no play in the game, no comp at its table —
///      then 25% of theo at 100 points, 50% at 400, 75% at 1,000, flat above. With the board and
///      rate both fixed before the word exists, the dice decide only the count of wagers made.
///
///      The comp is COINFLIP STAKE, not liquid FLIP: it ships through `creditFlip`, the same
///      no-minimum crediting lane the protocol's own bounties use, so every settlement pays its
///      comp immediately and in full — no accrual, no deposit threshold, and no mint unless the
///      flip it funds actually wins.
///
/// @dev WHAT BOUNDS A PLAYER'S LOSS
///
///      The bankroll is burned up front and is the exact, entire cost. The engine only ever wagers
///      out of it — the resolver's bounded-loss invariant means no arrangement of dice can reach
///      further — and since settlement only ever mints to the bet's owner, a settler has nothing
///      to gain by choosing which bets to resolve or in what order.
///
/// @dev DEPLOYMENT PINS BOTH WAYS
///
///      This contract reads `ContractAddresses.COIN` (FLIP) and, through `LootboxCraps`,
///      `ContractAddresses.GAME`. The protocol in turn must pin its own `ContractAddresses.CRAPS`
///      to this contract's deployed address, or both FLIP sinks reject it. Neither side works
///      until both are set.
contract FlipCraps is LootboxCraps {
    /// @notice The board's one-round total is under the table minimum.
    error BelowTableMinimum();
    /// @notice No such bet.
    error NoSuchBet();
    /// @notice This bet has already settled.
    error AlreadySettled();
    /// @notice An odds multiplier exceeds the caller's activity-scaled allowance.
    error OddsAboveAllowance();
    /// @notice A slip's bankroll cannot cover even one round of its wager.
    error BankrollBelowStake();
    /// @notice A slip's bankroll exceeds `MAX_BANKROLL_MULT` times its board's one-round stake.
    error BankrollAboveMax();
    /// @notice A slip's post-flip payout goal must be zero (none), above twice its bankroll, and
    ///         at most `MAX_GOAL_MULT` times it.
    error BadGoal();

    /// @notice The table minimum: a board's one-round total, in whole FLIP.
    uint256 public constant MIN_BOARD_FLIP = 600;

    /// @notice Ceiling on a slip's bankroll, as a multiple of its board's one-round stake. A
    ///         bigger appetite means a bigger board, not a longer grind on a small one.
    uint256 public constant MAX_BANKROLL_MULT = 10;

    /// @notice Ceiling on a slip's post-flip payout goal, as a multiple of its bankroll. Generous
    ///         on purpose: the escalator is what actually bounds how long the race can run.
    uint256 public constant MAX_GOAL_MULT = 1000;

    /// @notice Odds multiplier every player may take regardless of score.
    uint256 public constant ODDS_BASE_MULT = 3;
    /// @notice Activity score at which the allowance reaches the 100x table.
    uint256 public constant ODDS_SCORE_100X = 400;
    /// @notice Activity score at which the allowance tops out.
    uint256 public constant ODDS_SCORE_1000X = 2000;
    /// @notice Ceiling on the odds allowance.
    uint256 public constant ODDS_MULT_CAP = 1000;

    /// @notice Rakeback ladder knees: 0% at score zero, 25% at RAKE_SCORE_25, 50% at
    ///         RAKE_SCORE_50, 75% at RAKE_SCORE_75, flat above. Linear between knees.
    uint256 public constant RAKE_SCORE_25 = 100;
    uint256 public constant RAKE_SCORE_50 = 400;
    uint256 public constant RAKE_SCORE_75 = 1000;
    /// @notice The rakeback ceiling, in bps of theo.
    uint256 public constant RAKE_MAX_BPS = 7500;
    /// @dev Domain tag for the table's survival flip. Distinct preimage shape from `_crapsSeed`
    ///      (its first word is a keccak digest, this one is 8 ASCII bytes), so the flip bit and the
    ///      dice can never be the same hash.
    uint256 internal constant SURVIVAL_TAG = 0x537572766976616c; // "Survival"
    /// @notice Shooter cap on a bet slip; bust or goal is the real stop, and the escalator makes
    ///         even approaching this cap need an astronomical bankroll. At ~6.5k gas per full-board
    ///         shooter a cap-length settlement runs under 2M gas — and the engine's `SLIP_ROLL_BUDGET`
    ///         makes the worst case a hard ceiling of the same order, however long the shooters
    ///         run.
    uint256 public constant MAX_SLIP_HANDS = 256;

    /// @dev Separates the per-bet rounding roll from everything else on the same committed word.
    uint256 internal constant FLIP_ROUND_TAG = 0x466c6970526f756e64; // "FlipRound"

    // Bet slot 0 packing. `_resolve` reads this word once and decodes it in stack; keep these in
    // lockstep with `Bet` below if its fields ever move. Slot 1 is staked[0..127] | goal[128..255].
    uint256 private constant _BET_INDEX_SHIFT = 160;
    uint256 private constant _BET_RAKE_SHIFT = 208;
    uint256 private constant _BET_SETTLED_SHIFT = 224;
    uint256 private constant _BET_GOAL_SHIFT = 128;

    /// @notice A placed, unsettled bet slip.
    /// @param player  Who staked it, and the only address settlement can ever pay.
    /// @param index   The lootbox RNG index whose table this slip is seated at.
    /// @param rakeBps The rakeback rate, LOCKED at placement from the player's score then. With the
    ///                board (and so the theo per unit) also fixed at placement, nothing about the
    ///                comp can move after the bet is down: the word only counts the wagers made.
    /// @param settled Whether it has been resolved.
    /// @param staked  The bankroll, burned at placement (wei).
    /// @param goal    Payout target after a surviving 2x flip (wei); zero for none. The slip stops
    ///                once its pre-flip bankroll reaches `ceil(goal / 2)`.
    /// @param bets    The wager itself — one slot (see Craps.Bets).
    struct Bet {
        address player;
        uint48 index;
        uint16 rakeBps;
        bool settled;
        uint128 staked;
        uint128 goal;
        Craps.Bets bets;
    }

    mapping(uint64 => Bet) internal _bets;

    /// @notice Bets placed so far; ids run 1..betCount.
    uint64 public betCount;

    /// @notice A bet slip was staked at a table.
    /// @param config The whole board plus the comp rate locked with it, in one word — everything an
    ///               indexer needs to reconstruct the slip without ever calling `betOf`, and
    ///               everything it needs to recompute `theoFor` and check the comp itself. One
    ///               packed word rather than a struct: the ten fields ABI-encode to ten log words
    ///               on their own, which is 2,560 gas against 256. Layout, low bits first:
    ///
    ///                 bits   0.. 23  passLine       24.. 47  place4     48.. 71  place5
    ///                 bits  72.. 95  place6         96..119  place8    120..143  place9
    ///                 bits 144..167  place10       168..191  hard4     192..215  hard8
    ///                 bits 216..231  passOddsMult  232..247  rakeBps   248..255  unused
    event CrapsSlipPlaced(
        uint64 indexed betId,
        address indexed player,
        uint48 indexed index,
        uint256 bankroll,
        uint256 goal,
        uint256 config
    );

    /// @notice This settlement's theo comp, credited as next-day coinflip stake.
    event CrapsRakeback(address indexed player, uint64 indexed betId, uint256 amount);

    /// @notice A wager settled.
    /// @param betId    The bet.
    /// @param player   Who was paid.
    /// @param staked   FLIP burned at placement.
    /// @param won      What the table returned to this bet, before the survival flip.
    /// @param survived Whether this bet's TABLE survived its flip — shared by every bet at the index.
    /// @param paid     FLIP actually minted, after the flip and the rounding.
    /// @param rolls    Every roll of the session, one byte each — die one in the high nibble, die
    ///                 two in the low — with a 0x00 byte closing each hand. Recorded by the same
    ///                 loop that settled, so a front end can replay the whole shooter run straight
    ///                 off the receipt with no further calls.
    event CrapsBetSettled(
        uint64 indexed betId,
        address indexed player,
        uint256 staked,
        uint256 won,
        bool survived,
        uint256 paid,
        bytes rolls
    );

    // ---------------------------------------------------------------------------------------
    // Placing
    // ---------------------------------------------------------------------------------------

    /// @notice Stake a bet slip at the table now accepting bets: `b` repeats out of `bankroll` —
    ///         doubling every `Craps.ESC_HANDS` shooters — until it cannot cover a round, the
    ///         bankroll reaches half of the post-flip payout `goal` (zero for no goal), or
    ///         `MAX_SLIP_HANDS` shooters have rolled.
    /// @return betId The wager's id, needed to settle it.
    /// @dev Binds to `currentIndex()`, which the protocol's cadence guarantees is a table whose
    ///      word has not been drawn.
    function placeSlip(Craps.Bets calldata b, uint128 bankroll, uint128 goal)
        external
        returns (uint64 betId)
    {
        uint256 stake = stakeFor(b);
        if (stake < MIN_BOARD_FLIP * 1 ether) revert BelowTableMinimum();
        if (bankroll < stake) revert BankrollBelowStake();
        unchecked {
            if (bankroll > stake * MAX_BANKROLL_MULT) revert BankrollAboveMax();
            // A target at or below the bankroll's immediate surviving-flip value would stop before
            // the first shooter; one beyond MAX_GOAL_MULT is a race no bankroll is allowed to ask
            // for. Every accepted slip actually plays, toward a target that can conceivably land.
            if (goal != 0) {
                if (uint256(goal) <= uint256(bankroll) * 2) revert BadGoal();
                if (uint256(goal) > uint256(bankroll) * MAX_GOAL_MULT) revert BadGoal();
            }
        }
        // Both perks read the same activity score. Read it once so an odds-bearing placement
        // does not make two round-trips into the game contract.
        uint256 score = IGameActivityScore(GAME).playerActivityScore(msg.sender);
        if (b.passOddsMult != 0 && b.passOddsMult > _maxOddsForScore(score)) {
            revert OddsAboveAllowance();
        }
        // Bound with no validation, because there is nothing here to validate: the VRF callback
        // writes a word to `currentIndex() - 1` (`DegenerusGame.fulfillRandomWords`) and the index
        // only moves forward, so `wordAt(currentIndex())` is zero by construction. An explicit
        // undrawn-word read would cost a second cross-contract `extsload` per placement to re-ask
        // the SAME contract — `currentIndex()` and `wordAt()` decode adjacent hardcoded slots of
        // it — to vouch for itself. The real gates are the ffi slot-drift test and deploying
        // immutably, all at once, against an already-frozen protocol.
        uint48 index = currentIndex();

        IFlipCoin(ContractAddresses.COIN).burnCoin(msg.sender, bankroll);

        unchecked {
            betId = ++betCount;
        }
        uint256 rakeBps = _rakeBpsForScore(score);
        Bet storage bet = _bets[betId];
        bet.player = msg.sender;
        bet.index = index;
        bet.rakeBps = uint16(rakeBps);
        bet.staked = bankroll;
        bet.goal = goal;
        bet.bets = b;

        emit CrapsSlipPlaced(betId, msg.sender, index, bankroll, goal, _packConfig(b, rakeBps));
    }

    /// @dev The board and its locked comp rate, packed for `CrapsSlipPlaced` (layout documented on
    ///      the event). Written out by field rather than lifted from the `Bets` storage slot on
    ///      purpose: the wire format then cannot silently change meaning if those fields are ever
    ///      reordered, and a renamed one fails to compile instead.
    function _packConfig(Craps.Bets calldata b, uint256 rakeBps) private pure returns (uint256) {
        unchecked {
            return uint256(b.passLine)
                | (uint256(b.place4) << 24)
                | (uint256(b.place5) << 48)
                | (uint256(b.place6) << 72)
                | (uint256(b.place8) << 96)
                | (uint256(b.place9) << 120)
                | (uint256(b.place10) << 144)
                | (uint256(b.hard4) << 168)
                | (uint256(b.hard8) << 192)
                | (uint256(b.passOddsMult) << 216)
                | (rakeBps << 232);
        }
    }

    // ---------------------------------------------------------------------------------------
    // Settling
    // ---------------------------------------------------------------------------------------

    /// @notice Settle wagers whose tables have rolled.
    /// @dev Permissionless: a settlement only ever mints to the bet's own owner, so anyone may
    ///      call it for anyone. Reverts if any named bet is unknown, already settled, or seated at
    ///      a table whose word has not landed.
    function resolveBets(uint64[] calldata betIds) external {
        uint256 length = betIds.length;
        for (uint256 i = 0; i < length;) {
            uint64 betId;
            assembly ("memory-safe") {
                betId := calldataload(add(betIds.offset, shl(5, i)))
            }
            _resolve(betId);
            unchecked {
                ++i;
            }
        }
    }

    function _resolve(uint64 betId) private {
        Bet storage bet = _bets[betId];
        uint256 header;
        uint256 funds;
        assembly ("memory-safe") {
            header := sload(bet.slot)
            funds := sload(add(bet.slot, 1))
        }
        address player = address(uint160(header));
        if (player == address(0)) revert NoSuchBet();
        if (uint8(header >> _BET_SETTLED_SHIFT) != 0) revert AlreadySettled();

        assembly ("memory-safe") {
            sstore(bet.slot, or(header, shl(_BET_SETTLED_SHIFT, 1)))
        }
        Craps.Bets memory board = bet.bets;

        (uint256 won, bool survived, uint256 paid, uint256 unitsPlayed, bytes memory rolls) =
            _settlementOf(betId, header, funds, board, true);
        if (paid != 0) IFlipCoin(ContractAddresses.COIN).mintForGame(player, paid);

        emit CrapsBetSettled(betId, player, uint128(funds), won, survived, paid, rolls);

        // The comp: units actually wagered times the board's theo, at the rate locked when the
        // bet was placed. Everything but the wager count was fixed before the word existed.
        uint256 rakeBps = uint16(header >> _BET_RAKE_SHIFT);
        if (rakeBps != 0) {
            unchecked {
                _accrueRakeback(betId, player, theoFor(board) * unitsPlayed, rakeBps);
            }
        }
    }

    /// @dev Credit `bps` of `theo` straight to the player's next-day coinflip stake. The
    ///      flip-creditors lane has no minimum, so every settlement comps in full.
    function _accrueRakeback(uint64 betId, address player, uint256 theo, uint256 bps) private {
        uint256 rake;
        unchecked {
            rake = (theo * bps) / 10_000;
        }
        ICoinflipStake(ContractAddresses.COINFLIP).creditFlip(player, rake);
        emit CrapsRakeback(player, betId, rake);
    }

    /// @dev The entire settlement of `betId`, decided the moment its table's word landed. Shared by
    ///      the paying path and the preview so the two can never disagree about what a bet is
    ///      worth. Reverts while the table is still unrolled. `withLog` exposes the packed dice to
    ///      the state-changing caller for its receipt; the paying engine records them either way.
    function _settlementOf(
        uint64 betId,
        uint256 header,
        uint256 funds,
        Craps.Bets memory board,
        bool withLog
    )
        private
        view
        returns (uint256 won, bool survived, uint256 paid, uint256 unitsPlayed, bytes memory rolls)
    {
        uint48 index = uint48(header >> _BET_INDEX_SHIFT);
        uint256 word = wordAt(index);
        if (word == 0) revert RngNotReady();

        // Lean mode: settlement pays from the scalars alone, so the per-leg books stay off.
        bytes32 seed = _crapsSeed(word, index);
        SlipResult memory sr = _settleSlip(
            board,
            seed,
            uint128(funds),
            bankrollGoalFor(funds >> _BET_GOAL_SHIFT),
            MAX_SLIP_HANDS,
            SLIP_ROLL_BUDGET
        );
        won = sr.bankrollOut;
        unitsPlayed = sr.unitsPlayed;
        if (withLog) rolls = sr.rollLog;

        // The survival flip, salted by the round the run ended on — see `_survived`.
        survived = _survived(word, index, sr.handsPlayed);
        unchecked {
            paid = survived ? won * 2 : 0;
        }

        // Land the award on a round figure, the same two-band policy the protocol uses: the
        // 100-FLIP granule only once it is a small slice of the award, the whole-FLIP floor below.
        if (paid != 0) {
            paid = paid > FlipRoundLib.FLIP_ROUND_THRESHOLD
                ? FlipRoundLib.roundFlipToHundreds(
                    paid,
                    uint256(keccak256(abi.encode(word, uint256(betId) ^ FLIP_ROUND_TAG)))
                )
                : FlipRoundLib.floorWholeFlip(paid);
        }
    }

    // ---------------------------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------------------------

    /// @notice A placed wager.
    function betOf(uint64 betId) external view returns (Bet memory) {
        return _bets[betId];
    }

    /// @notice What `betId` would settle to, if its table has rolled.
    /// @dev Exactly what `resolveBets` will pay — same computation, not a second copy of it.
    function previewSettlement(uint64 betId)
        external
        view
        returns (uint256 won, bool survived, uint256 paid)
    {
        Bet storage bet = _bets[betId];
        uint256 header;
        uint256 funds;
        assembly ("memory-safe") {
            header := sload(bet.slot)
            funds := sload(add(bet.slot, 1))
        }
        if (address(uint160(header)) == address(0)) revert NoSuchBet();
        Craps.Bets memory board = bet.bets;
        (won, survived, paid,, ) = _settlementOf(betId, header, funds, board, false);
    }

    /// @notice Convert a desired post-survival-flip payout into the bankroll take-profit used by
    ///         the slip engine. Rounds up so doubling the threshold never undershoots an odd goal.
    function bankrollGoalFor(uint256 payoutGoal) internal pure returns (uint256) {
        unchecked {
            return (payoutGoal >> 1) + (payoutGoal & 1);
        }
    }

    /// @notice The largest odds multiplier `player` may take, judged on their activity score now.
    /// @dev Two linear segments, continuous at both knees: 3x at zero to 100x at 400 points, then
    ///      100x to 1000x at 2,000 points, flat above.
    function maxOddsFor(address player) public view returns (uint256) {
        return _maxOddsForScore(IGameActivityScore(GAME).playerActivityScore(player));
    }

    function _maxOddsForScore(uint256 score) private pure returns (uint256) {
        unchecked {
            if (score >= ODDS_SCORE_1000X) return ODDS_MULT_CAP;
            if (score >= ODDS_SCORE_100X) {
                return 100 + ((score - ODDS_SCORE_100X) * 900) / (ODDS_SCORE_1000X - ODDS_SCORE_100X);
            }
            return ODDS_BASE_MULT + (score * 97) / ODDS_SCORE_100X;
        }
    }

    /// @notice The rakeback rate for `player`, in bps of theo — read once at placement and locked
    ///         into the bet. Three linear segments, continuous at every knee: 0% at score zero,
    ///         25% at 100, 50% at 400, 75% at 1,000, flat above.
    function rakeBpsFor(address player) public view returns (uint256) {
        return _rakeBpsForScore(IGameActivityScore(GAME).playerActivityScore(player));
    }

    function _rakeBpsForScore(uint256 score) private pure returns (uint256) {
        unchecked {
            if (score >= RAKE_SCORE_75) return RAKE_MAX_BPS;
            if (score >= RAKE_SCORE_50) {
                return 5000 + ((score - RAKE_SCORE_50) * 2500) / (RAKE_SCORE_75 - RAKE_SCORE_50);
            }
            if (score >= RAKE_SCORE_25) {
                return 2500 + ((score - RAKE_SCORE_25) * 2500) / (RAKE_SCORE_50 - RAKE_SCORE_25);
            }
            return (score * 2500) / RAKE_SCORE_25;
        }
    }

    /// @dev The flip bit itself, off committed data only.
    ///
    ///      SALTED BY THE EXIT ROUND. Keying on `(word, index)` alone gave one coin to the whole
    ///      table, and a table's word is public the moment it lands — so the first player to settle
    ///      a two-shooter run published the result for everyone still holding a long one. Mixing in
    ///      the round the run ended on gives each length its own coin: learning how a short run
    ///      landed says nothing about a long one, and the suspense survives until each player's own
    ///      settlement.
    ///
    ///      It costs the manipulation argument nothing, which is the only reason it is allowed in
    ///      the key. `handsPlayed` is not composed by the settler and cannot be: it is a pure
    ///      function of the board, bankroll and goal — all fixed at placement — against a word that
    ///      did not exist yet. No arrangement of `betIds[]`, and no choice made after the dice are
    ///      public, can move it by one round. Two players who bet identically still run identically,
    ///      so they still share a coin.
    function _survived(uint256 word, uint48 index, uint256 handsPlayed)
        internal
        pure
        returns (bool)
    {
        return uint256(keccak256(abi.encode(SURVIVAL_TAG, word, index, handsPlayed))) & 1 == 1;
    }
}
