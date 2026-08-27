// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Craps} from "../../contracts/Craps.sol";

/// @title CrapsOracle
/// @notice TEST-ONLY reference resolver. This is the full-fidelity engine that used to ship
///         inside `Craps`: scripted dice, per-leg books, per-hand ledgers, and the many-hand
///         aggregate. It was cut from production because `CrapsBattle` inherited its whole public
///         surface and blew EIP-170; nothing on the paying path ever called it.
///
///         It is kept here because it is the SUITE'S ORACLE, and the validation chain only works
///         with both halves present:
///
///           1. `Craps.t.sol` grades THIS contract against hand-written dice scripts, which is the
///              only way to assert a rule exactly ("the hard eight pays 9:1", "a come-out craps
///              kills the line"). Scripted dice are what make that possible, and the shipped lean
///              engine takes a seed, not a script.
///           2. `CrapsBattle.t.sol` and `CrapsEconomics.t.sol` then grade the SHIPPED lean engine
///              against this one, off the same seed. That step is what makes these assertions
///              about production rather than about a test fixture.
///
///         So this is deliberately an INDEPENDENT implementation, not a subclass sharing helpers
///         with `Craps`. It carries its own payout tables and its own state machine on purpose: if
///         it shared them, a bug in a shared helper would cancel out on both sides of step 2 and
///         the differential test would pass through it. Keep it that way — when a production
///         payout rule changes, this file must be updated by hand, and step 2 failing loudly is
///         the intended behaviour, not drift to be papered over.
///
///         Bets are `Craps.Bets` so one struct feeds both engines.
contract CrapsOracle {
    /// @notice A session must cover at least one hand and at most `MAX_SESSION_HANDS`.
    error BadHandCount();
    /// @notice A scripted dice array must hold whole (d1, d2) pairs.
    error OddDiceScript();
    /// @notice A scripted die must be in 1..6.
    error BadDie();

    // ---------------------------------------------------------------------------------------
    // Bet legs
    // ---------------------------------------------------------------------------------------

    /// @dev Number of independently-settled bets in a hand. Indexes `Bets`, `Outcome.legStaked`,
    ///      `Outcome.legReturned`, and the `Sim` aggregates. The struct members below hardcode 10
    ///      because Solidity wants a literal there; keep them in step.
    uint256 internal constant _LEGS = 10;

    uint256 public constant LEG_PASS = 0;
    /// @dev Place legs occupy LEG_PLACE + PLACE_* (1..6).
    uint256 public constant LEG_PLACE = 1;
    uint256 public constant LEG_HARD4 = 7;
    uint256 public constant LEG_HARD8 = 8;
    /// @dev The dark side, the tenth and last leg — canonical order matches `Craps.Bets`.
    uint256 public constant LEG_DONT_PASS = 9;

    /// @dev Place indexes, ordered by dice total: 4, 5, 6, 8, 9, 10.
    uint256 public constant PLACE_4 = 0;
    uint256 public constant PLACE_5 = 1;
    uint256 public constant PLACE_6 = 2;
    uint256 public constant PLACE_8 = 3;
    uint256 public constant PLACE_9 = 4;
    uint256 public constant PLACE_10 = 5;

    /// @dev 1 FLIP in wei. Stakes are stored in whole FLIP; every payout computation scales here
    ///      first, so the math is identical to wei-denominated stakes.
    uint256 internal constant FLIP = 1 ether;

    // ---------------------------------------------------------------------------------------
    // Limits and tables
    // ---------------------------------------------------------------------------------------

    /// @notice Hard bound on the length of one hand.
    /// @dev A hand ends on a seven-out; its length is geometric with mean ~8.53 rolls. The per-roll
    ///      hazard is ~1/8.53, so the chance of reaching 512 rolls is on the order of 1e-28 — far
    ///      below any threshold worth pricing. The cap exists so the loop provably terminates.
    ///      A hand that hits it is flagged `Outcome.truncated` and every still-live stake is
    ///      refunded rather than being silently confiscated.
    uint256 public constant MAX_ROLLS = 512;

    /// @notice Hands one `resolveHands` session may cover.
    /// @dev Bounds the returned ledger, nothing else. `simulate` is uncapped because it returns no
    ///      per-hand data.
    uint256 public constant MAX_SESSION_HANDS = 1024;

    /// @notice Total dice rolls a bet slip may consume, judged between shooters.
    /// @dev This is what makes a slip settlement's gas a GUARANTEE instead of a probability. The
    ///      shooter cap alone leaves a bounded-but-huge worst case (cap x MAX_ROLLS rolls); with
    ///      this budget the hard ceiling is `SLIP_ROLL_BUDGET - 1 + MAX_ROLLS` rolls — under two
    ///      million gas in the measured settlement engine — however the dice fall. Even a
    ///      hypothetical 256-shooter slip averages ~2,200 rolls; legal terms stop much earlier,
    ///      making 4,096 effectively unreachable. Hitting it is an ordinary bust between shooters;
    ///      every shooter still settles whole, and the budget never cuts a hand mid-roll.
    uint256 public constant SLIP_ROLL_BUDGET = 4096;

    /// @notice Shooters between each mandatory doubling of a slip's base wager.
    /// @dev The escalator: rounds 0..4 wager 1x the board, 5..9 wager 2x, 10..14 wager 4x, and so
    ///      on, capped at the 65,535-unit table limit. A slip that cannot cover the doubled wager
    ///      busts between shooters with its remainder intact. Deterministic in the hand ordinal, so
    ///      the whole run is still recomputable from the base-board ledger alone.
    uint256 public constant ESC_HANDS = 5;

    /// @notice Domain tag for the table's survival coin (see `_slip`). Held independently from the
    ///         production engine, at the same value, so the differential proves the two agree.
    uint256 internal constant SURVIVAL_TAG = 0x537572766976616c; // "Survival"

    /// @dev The six totals that can be a point, for grading `Outcome.pointsMade`.
    uint256 internal constant _POINT_TOTALS_MASK = (1 << 4) | (1 << 5) | (1 << 6) | (1 << 8) | (1 << 9) | (1 << 10);

    /// @dev The roll loop's entire state machine, packed into one stack word so it never leaves
    ///      the stack (see _run). Field layout, indexed by dice total `t` where a total is the key:
    ///        bits  0..15  live place-bet totals (bit t; only 4, 5, 6, 8, 9, 10 are ever set)
    ///        bits 16..31  distinct points made (bit t, offset 16 — `pointsMade` telemetry)
    ///        bits 32..35  the point (0 = come-out)
    ///        bit  40      pass line live          bit 43  seven-out happened
    ///        bit  41      don't pass unresolved   bit 44  hard four live
    ///        bit  42      hard eight live
    uint256 private constant ST_FIRE = 16;
    uint256 private constant ST_POINT = 32;
    uint256 private constant ST_PLACE_ANY = 0xFFFF;
    uint256 private constant ST_POINT_MASK = 0xF << 32;
    uint256 private constant ST_PASS_LIVE = 1 << 40;
    /// @dev Independently held at the production engine's value: the dark wager is UNRESOLVED,
    ///      which is what bounds it to one decision per shooter and what tells a roll-cap
    ///      truncation whether the stake is still owed back.
    uint256 private constant ST_DONT_LIVE = 1 << 41;
    uint256 private constant ST_HARD8_LIVE = 1 << 42;
    uint256 private constant ST_SEVEN_OUT = 1 << 43;
    uint256 private constant ST_HARD4_LIVE = 1 << 44;

    // ---------------------------------------------------------------------------------------
    // Types
    // ---------------------------------------------------------------------------------------

    /// @notice The full settlement of one hand.
    /// @param staked       Sum of every stake. The player's exact maximum loss.
    /// @param returned     Sum of everything credited back: returned stakes plus winnings.
    /// @param net          `returned - staked`. Negative means the house won the hand.
    /// @param rolls        Dice rolls in the hand, including the seven-out roll.
    /// @param pointsMade   Distinct points made — the number the Fire bet is graded on.
    /// @param truncated    True if MAX_ROLLS was reached without a seven-out. Live stakes refunded.
    /// @param legStaked    Per-leg stake, indexed by LEG_*.
    /// @param legReturned  Per-leg credit, indexed by LEG_*.
    struct Outcome {
        uint256 staked;
        uint256 returned;
        int256 net;
        uint32 rolls;
        uint8 pointsMade;
        bool truncated;
        uint256[10] legStaked;
        uint256[10] legReturned;
    }

    /// @notice One hand's line in a session ledger.
    /// @param net         That hand's `Outcome.net`.
    /// @param rolls       That hand's length.
    /// @param pointsMade  Distinct points made in that hand.
    /// @param truncated   That hand hit MAX_ROLLS.
    struct HandRecord {
        int256 net;
        uint32 rolls;
        uint8 pointsMade;
        bool truncated;
    }

    /// @notice The settlement of one bet set played over several consecutive hands off one seed.
    /// @param hands        Hands played.
    /// @param staked       Total charged upfront: one hand's stake sum times `hands`.
    /// @param returned     Total credited back across every hand.
    /// @param net          `returned - staked`.
    /// @param totalRolls   Dice rolls across the whole session.
    /// @param legStaked    Per-leg stake totals, indexed by LEG_*.
    /// @param legReturned  Per-leg credit totals, indexed by LEG_*.
    /// @param ledger       Hand-by-hand record, in play order.
    /// @param rollLog      The session's dice, one byte per roll — die one in the high nibble, die
    ///                     two in the low — with a 0x00 byte closing each hand. Recorded during the
    ///                     same roll loop that settles, so it can never disagree with the money;
    ///                     empty unless the caller asked for it.
    struct Session {
        uint256 hands;
        uint256 staked;
        uint256 returned;
        int256 net;
        uint256 totalRolls;
        uint256[10] legStaked;
        uint256[10] legReturned;
        HandRecord[] ledger;
        bytes rollLog;
    }

    /// @notice Why a bet slip stopped playing.
    enum SlipStop {
        Bust, // fell below half a round, or lost the mid-run second-chance flip
        Goal // the bankroll reached the chosen target
    }

    /// @notice The full account of one bet-slip run: the same wager repeated shooter after shooter
    ///         out of a bankroll, until it cannot cover another round, reaches the goal, or hits a
    ///         hard execution bound. Either failure is a bust.
    /// @param bankrollIn   What the slip started with.
    /// @param bankrollOut  What was left when it stopped — the settlement figure. Includes any
    ///                     sub-stake remainder; stopping never confiscates it.
    /// @param handsPlayed  Shooters actually played.
    /// @param unitsPlayed  Base-board units wagered across the run — the sum of each round's
    ///                     escalating mandatory multiplier, which is the true handle and what theo
    ///                     comps from. Only equals `handsPlayed` for a run short enough that the
    ///                     escalator never doubled.
    /// @param totalRolls   Dice rolls across the run.
    /// @param stop         Why it ended.
    /// @param ledger       Hand-by-hand record of the BASE board, in play order (when requested).
    ///                     Round `i`'s money is `q x net` for `q = _escOf(i)`; the whole money path
    ///                     is recomputable from the ledger alone, since q depends only on the hand
    ///                     ordinal.
    /// @param rollLog      The run's dice, encoded as in `Session.rollLog` (when requested).
    struct SlipResult {
        uint256 bankrollIn;
        uint256 bankrollOut;
        uint256 handsPlayed;
        uint256 unitsPlayed;
        uint256 totalRolls;
        SlipStop stop;
        HandRecord[] ledger;
        bytes rollLog;
    }

    /// @notice Aggregate of many hands, for measuring the realised house edge on a bet set.
    /// @param hands           Hands simulated.
    /// @param totalRolls      Dice rolls across all hands; `totalRolls / hands` is the mean length.
    /// @param longestHand     Rolls in the longest hand seen.
    /// @param truncatedHands  Hands that hit MAX_ROLLS. Expected to be zero.
    /// @param staked          Sum of `Outcome.staked`.
    /// @param returned        Sum of `Outcome.returned`.
    /// @param legStaked       Per-leg stake totals, indexed by LEG_*.
    /// @param legReturned     Per-leg credit totals, indexed by LEG_*.
    /// @param pointsMadeHist  Count of hands by distinct points made, index 0..6.
    struct Sim {
        uint256 hands;
        uint256 totalRolls;
        uint256 longestHand;
        uint256 truncatedHands;
        uint256 staked;
        uint256 returned;
        uint256[10] legStaked;
        uint256[10] legReturned;
        uint256[7] pointsMadeHist;
    }

    // ---------------------------------------------------------------------------------------
    // Entry points
    // ---------------------------------------------------------------------------------------

    /// @notice Resolve one shooter's hand against `seed`.
    /// @dev The production entry point. `seed` must not be knowable when the bets are locked —
    ///      the entire hand is a deterministic function of it, so anyone who learns the seed early
    ///      knows every roll. A VRF word is the intended source.
    /// @param b     The bets, all placed before the come-out.
    /// @param seed  Randomness. Expanded into an unbounded roll stream; see `diceAt`.
    /// @return o    The settlement.
    function resolveHand(Craps.Bets calldata b, bytes32 seed) external pure returns (Outcome memory o) {
        o.staked = stakeFor(b);
        uint8[] memory noScript;
        _run(b, seed, noScript, true, new bytes(0), 0, o);
    }

    /// @notice Resolve a hand from an explicit dice script instead of a seed.
    /// @dev SIMULATION AND REPLAY ONLY — never wire this to an escrow, because the caller chooses
    ///      the dice. It exists so a hand can be replayed for a UI, so strategies can be tested
    ///      against hand-built sequences, and so the rules can be unit-tested deterministically.
    ///      If `dice` runs out before the hand ends, `seed` supplies the remaining rolls.
    /// @param b     The bets.
    /// @param dice  Flat pairs: `[d1, d2, d1, d2, ...]`, each value in 1..6.
    /// @param seed  Fallback randomness once the script is exhausted.
    function resolveHandWithScriptedDice(Craps.Bets calldata b, uint8[] calldata dice, bytes32 seed)
        external
        pure
        returns (Outcome memory o)
    {
        if (dice.length % 2 != 0) revert OddDiceScript();
        for (uint256 i = 0; i < dice.length; ++i) {
            if (dice[i] < 1 || dice[i] > 6) revert BadDie();
        }
        o.staked = stakeFor(b);
        _run(b, seed, dice, true, new bytes(0), 0, o);
    }

    /// @notice Play one bet set over `hands` consecutive shooter hands, all off a single seed.
    /// @dev The multi-hand production entry point. The player commits the whole session upfront and
    ///      it settles once, at the end: nothing is decided between hands any more than between
    ///      rolls. The bounded-loss invariant carries straight over — the exact charge is
    ///      `Session.staked`, which is one hand's stake sum times `hands`, and the player can still
    ///      never lose more than that.
    ///
    ///      Every hand comes off the same `seed`, so one VRF word settles the session. Hand `i` is
    ///      `resolveHand(b, handSeed(seed, i))`, which makes any single hand independently
    ///      replayable and the whole session verifiable off-chain from the one word.
    ///
    ///      Measured at ~10k gas per marginal hand on a full board (~16k for a single-hand
    ///      session, which carries the per-call overhead), so a session settled on-chain should
    ///      stay well under the cap; the cap itself only exists to bound the returned ledger.
    ///      `CrapsGas.t.sol` re-measures this rather than trusting the comment.
    function resolveHands(Craps.Bets calldata b, bytes32 seed, uint256 hands) external pure returns (Session memory s) {
        return _session(b, seed, hands, true, false);
    }

    /// @dev Body of `resolveHands`, exposed to subclasses that source their seed from somewhere
    ///      other than a caller argument. `withLegs` as in `_run`; a settlement passes false and
    ///      reads only the scalars. `withLog` records the dice into `s.rollLog` as the same loop
    ///      rolls them.
    function _session(Craps.Bets memory b, bytes32 seed, uint256 hands, bool withLegs, bool withLog)
        internal
        pure
        returns (Session memory s)
    {
        if (hands == 0 || hands > MAX_SESSION_HANDS) revert BadHandCount();

        s.hands = hands;
        // The ledger is a per-hand view concern: a settlement pays from the scalars alone, so in
        // lean mode neither the records nor their allocation exist.
        if (withLegs) s.ledger = new HandRecord[](hands);

        // See the note in `simulate`: everything that must outlive the rewind is allocated first.
        // The log is sized for the impossible worst case and trimmed after; its zero-init also
        // pre-writes every hand's 0x00 terminator, so only real rolls are ever written into it.
        bytes memory log;
        if (withLog) log = new bytes(hands * (MAX_ROLLS + 1));
        uint8[] memory noScript;
        Outcome memory o;
        o.staked = stakeFor(b);
        uint256 mark;
        assembly ("memory-safe") {
            mark := mload(0x40)
        }

        // Bounded by the same note as _run; the accumulators cannot approach 2^256. As in _slip,
        // `cur` packs the hand counter (low 16 bits) with the roll-log cursor (above) — the
        // production compiler profile inlines _run here and runs out of stack with them separate.
        unchecked {
            uint256 cur;
            while (cur & 0xFFFF < hands) {
                uint256 end = _run(b, handSeed(seed, cur & 0xFFFF), noScript, withLegs, log, cur >> 16, o);

                if (withLegs) _record(s.ledger, cur & 0xFFFF, o);
                s.staked += o.staked;
                s.returned += o.returned;
                if (withLegs) {
                    for (uint256 k = 0; k < _LEGS; ++k) {
                        s.legStaked[k] += o.legStaked[k];
                        s.legReturned[k] += o.legReturned[k];
                    }
                }

                // +1 past the hand's 0x00 terminator, already there from the buffer's zero-init.
                cur = ((end + 1) << 16) | ((cur & 0xFFFF) + 1);
                assembly ("memory-safe") {
                    mstore(0x40, mark)
                }
            }

            if (withLog) {
                // Trim the worst-case buffer down to the bytes actually written. Everything past the
                // new length was only ever zero-init scratch, so nothing dirty is exposed.
                uint256 pos = cur >> 16;
                assembly ("memory-safe") {
                    mstore(log, pos)
                }
                s.rollLog = log;
            }
            // `_run` advances its logical cursor for every roll even when no byte log is being
            // kept; the outer loop adds one hand terminator. Subtract those terminators here.
            s.totalRolls = (cur >> 16) - hands;
            s.net = int256(s.returned) - int256(s.staked);
        }
    }

    /// @notice Play `b` as a bet slip: repeat the wager out of `bankroll` — doubling it every
    ///         `ESC_HANDS` shooters — until it cannot cover a round, `goal` is reached, or `cap`
    ///         shooters have rolled.
    /// @dev Pure view with full ledger and dice log. Hand `i` of a slip is the table's shooter `i`
    ///      — identical to hand `i` of any session on the same seed — so every wager at one table
    ///      watches the same dice, differing only in where it stops.
    function resolveSlip(Craps.Bets calldata b, bytes32 seed, uint256 bankroll, uint256 goal, uint256 cap)
        external
        pure
        returns (SlipResult memory)
    {
        return _slip(b, seed, bankroll, goal, cap, SLIP_ROLL_BUDGET, true, true, address(0));
    }

    /// @dev The same run for a NAMED owner. The dice are the table's either way; only the survival
    ///      coin moves, which is what a caller comparing two players at one seat order needs.
    function resolveSlipFor(
        Craps.Bets calldata b,
        bytes32 seed,
        uint256 bankroll,
        uint256 goal,
        uint256 cap,
        address player
    ) external pure returns (SlipResult memory) {
        return _slip(b, seed, bankroll, goal, cap, SLIP_ROLL_BUDGET, true, true, player);
    }

    /// @dev The slip engine. Stop conditions are judged BETWEEN shooters, in this order: goal first
    ///      (so a run that is simultaneously at goal and out of the next stake counts as a win), then
    ///      the hard bounds, then affordability. A round short of even half its wager busts; one it can cover
    ///      between half and all of takes its OWNER's survival coin (survive doubles the bankroll and
    ///      plays on, lose zeroes it) — the dice are the table's, the second chance is the player's. Each played round escrows its wager — the base board times the
    ///      escalating mandatory multiplier (see `ESC_HANDS`) — out of the bankroll, plays one lean
    ///      hand, and credits back whatever it returned; the resolver's bounded-loss invariant is
    ///      exactly what makes the escrow subtraction safe unchecked after the affordability check.
    ///      The remainder of a hard-busted bankroll is kept, never confiscated.
    ///
    ///      Because every payout is linear in the stakes, a q-unit round is EXACTLY q times the
    ///      base hand: the engine rolls the base board once and scales, which is what keeps the
    ///      dice log and the ledger those of the base board however far the escalator has climbed.
    ///
    ///      Loop state note: `cur` packs the hand counter (bits 0..15), the round's mandatory
    ///      multiplier (16..31), and the roll-log cursor (32+) into one stack slot — via-IR runs
    ///      out of stack here with them separate.
    function _slip(
        Craps.Bets memory b,
        bytes32 seed,
        uint256 bankroll,
        uint256 goal,
        uint256 cap,
        uint256 rollBudget,
        bool withLedger,
        bool withLog,
        address player
    ) internal pure returns (SlipResult memory r) {
        if (cap == 0 || cap > MAX_SESSION_HANDS) revert BadHandCount();
        uint256 stake = stakeFor(b);

        r.bankrollIn = bankroll;
        if (withLedger) r.ledger = new HandRecord[](cap);

        // Allocation order matters — see `simulate`: everything outliving the rewind comes first.
        // The log is sized by the roll budget's hard ceiling plus one terminator per hand — far
        // tighter than cap x MAX_ROLLS ever was.
        bytes memory log;
        if (withLog) log = new bytes(rollBudget + MAX_ROLLS + cap);
        uint8[] memory noScript;
        Outcome memory o;
        o.staked = stake;
        uint256 mark;
        assembly ("memory-safe") {
            mark := mload(0x40)
        }

        // Bounded as in _run; the bust check above each round is what keeps the escrow safe. The
        // escalating minimum is scoped to the check and packed into `cur`, rather than kept live
        // across `_run`, because the via-IR frame has no spare stack slot there.
        unchecked {
            uint256 cur;
            while (true) {
                if (goal != 0 && bankroll >= goal) {
                    r.stop = SlipStop.Goal;
                    break;
                }
                // A hard bound is an ordinary bust. Bust is enum zero, so a bare break mirrors the
                // lean engine's cheapest path. The packed cursor is total rolls plus one terminator
                // per completed hand.
                if (cur & 0xFFFF == cap || (cur >> 32) - (cur & 0xFFFF) >= rollBudget) {
                    break;
                }

                {
                    uint256 q = _escOf(cur & 0xFFFF);
                    uint256 need = stake * q;
                    if (bankroll * 2 < need) {
                        // Short of even half the round: no second chance, the slip busts.
                        r.stop = SlipStop.Bust;
                        break;
                    }
                    if (bankroll < need) {
                        // Between half and a full round: the table's survival coin for this round —
                        // the same one that decides a run of this length at the end — rides the
                        // whole bankroll. Survive doubles it and plays on, lose zeroes it.
                        if (_survived(seed, cur & 0xFFFF, player)) {
                            bankroll += bankroll;
                        } else {
                            bankroll = 0;
                            r.stop = SlipStop.Bust;
                            break;
                        }
                    }
                    cur = (cur & ~uint256(0xFFFF0000)) | (q << 16);
                }

                // This round's wager, in base-board units: the escalating mandatory multiple the
                // affordability check above already proved covered.
                bankroll -= ((cur >> 16) & 0xFFFF) * stake;

                uint256 end = _run(b, handSeed(seed, cur & 0xFFFF), noScript, false, log, cur >> 32, o);
                bankroll += ((cur >> 16) & 0xFFFF) * o.returned;
                r.unitsPlayed += (cur >> 16) & 0xFFFF;

                if (withLedger) _record(r.ledger, cur & 0xFFFF, o);
                cur = ((end + 1) << 32) | (cur & 0xFFFF0000) | ((cur & 0xFFFF) + 1);
                assembly ("memory-safe") {
                    mstore(0x40, mark)
                }
            }

            r.handsPlayed = cur & 0xFFFF;
            r.bankrollOut = bankroll;
            r.totalRolls = (cur >> 32) - (cur & 0xFFFF);
            if (withLedger) {
                // Trim the cap-sized ledger down to the hands actually played.
                HandRecord[] memory led = r.ledger;
                uint256 played = cur & 0xFFFF;
                assembly ("memory-safe") {
                    mstore(led, played)
                }
            }
            if (withLog) {
                uint256 pos = cur >> 32;
                assembly ("memory-safe") {
                    mstore(log, pos)
                }
                r.rollLog = log;
            }
        }
    }

    /// @notice Play the same bet set over `hands` consecutive hands and return only the aggregate.
    /// @dev Same hands as `resolveHands` off the same seed, with no per-hand ledger and no cap, so
    ///      it scales to the hundreds of thousands of hands needed to measure a realised edge:
    ///      `-(legReturned - legStaked) / legStaked`. Pure, so it costs nothing over `eth_call`.
    function simulate(Craps.Bets calldata b, bytes32 baseSeed, uint256 hands) external pure returns (Sim memory s) {
        s.hands = hands;

        // Reuse one Outcome across every hand and rewind its scratch region so very large eth_call
        // simulations do not pay quadratic memory expansion. Aggregate stake is known up front;
        // aggregate return is summed from the canonical leg book below, so neither depends on a
        // scalar spill surviving this deliberately reclaimed scratch region.
        uint8[] memory noScript;
        bytes memory noLog = new bytes(0);
        Outcome memory o;
        uint256 handStake = stakeFor(b);
        o.staked = handStake;
        s.staked = handStake * hands;

        uint256 mark;
        assembly ("memory-safe") {
            mark := mload(0x40)
        }

        // Bounded as in _run.
        unchecked {
            for (uint256 i = 0; i < hands; ++i) {
                _run(b, handSeed(baseSeed, i), noScript, true, noLog, 0, o);

                s.totalRolls += o.rolls;
                if (o.rolls > s.longestHand) s.longestHand = o.rolls;
                if (o.truncated) ++s.truncatedHands;
                ++s.pointsMadeHist[o.pointsMade];
                for (uint256 k = 0; k < _LEGS; ++k) {
                    s.legStaked[k] += o.legStaked[k];
                    s.legReturned[k] += o.legReturned[k];
                }

                assembly ("memory-safe") {
                    mstore(0x40, mark)
                }
            }
            for (uint256 k = 0; k < _LEGS; ++k) {
                s.returned += s.legReturned[k];
            }
        }
    }

    /// @notice Total staked across every leg of `b` — one hand's charge.
    /// @dev What an escrow must collect up front, and the exact ceiling on what the player can
    ///      lose. Multiply by the hand count for a session.
    function stakeFor(Craps.Bets memory b) public pure returns (uint256 total) {
        // Stakes are whole FLIP; the charge is wei. Bounded far below 2^256: ten uint24 legs.
        unchecked {
            total = (
                uint256(b.passLine) + uint256(b.place4) + uint256(b.place5) + uint256(b.place6)
                    + uint256(b.place8) + uint256(b.place9) + uint256(b.place10) + uint256(b.hard4)
                    + uint256(b.hard8) + uint256(b.dontPass)
            ) * FLIP;
        }
    }

    /// @notice The expected loss of one hand of `b`, in wei — the theo a casino comps from.
    /// @dev Exact per-leg rationals for the ride-to-the-seven-out model this table plays:
    ///      pass 7/251, place 4/10 and 5/9 EXACTLY ZERO (they pay true odds — 2:1 and 3:2 against
    ///      the 1/2 and 2/3 hits a stake expects before the seven), place 6/8 1/36, the hard four
    ///      1/8, the hard eight 1/10, and the dark side 101/1050.
    ///
    ///      The dark rational is per SHOOTER, which is also per decision: a barred twelve leaves
    ///      the wager up, so it always resolves. Excluding pushes the wager wins 949/1925 and
    ///      loses 976/1925, and at 3:4 that is `(976 - 949 * 3/4) / 1925 = 151/1100` = 13.727%.
    ///      The MC oracle pins every one of these numbers against the resolver; flooring loses at
    ///      most a few wei.
    function theoFor(Craps.Bets memory b) public pure returns (uint256) {
        unchecked {
            return (uint256(b.passLine) * FLIP * 7) / 251 + (uint256(b.place6) * FLIP) / 36
                + (uint256(b.place8) * FLIP) / 36 + (uint256(b.hard4) * FLIP) / 8
                + (uint256(b.hard8) * FLIP) / 10 + (uint256(b.dontPass) * FLIP * 151) / 1100;
        }
    }

    /// @notice The dice of the hand seeded by `seed`, as flat `(d1, d2)` pairs, ending on the
    ///         seven-out that closed it.
    /// @dev Lets a caller see the shooter itself rather than only what it paid — which is what
    ///      makes a shared table checkable, since every player settling against a seed can pull the
    ///      same rolls and verify their own result against them.
    ///
    ///      This re-walks the point machine rather than threading a recorder through `_run`, to
    ///      keep the settlement path free of display concerns. That duplication is the risk here:
    ///      if the two ever disagree, the dice shown would not be the dice paid. `Craps.t.sol`
    ///      fuzzes `handDice(seed).length / 2 == resolveHand(b, seed).rolls`, pinning them together.
    function handDice(bytes32 seed) public pure returns (uint8[] memory dice) {
        uint8[] memory buf = new uint8[](MAX_ROLLS * 2);
        uint256 point;
        uint256 n;

        // Bounded: dice are 1..6 and the buffer is cap-sized.
        unchecked {
            for (uint256 i = 0; i < MAX_ROLLS; ++i) {
                (uint256 d1, uint256 d2) = diceAt(seed, i);
                buf[n++] = uint8(d1);
                buf[n++] = uint8(d2);

                uint256 t = d1 + d2;
                if (point == 0) {
                    // Naturals and craps leave the come-out open; anything else sets the point.
                    if (t != 7 && t != 11 && t != 2 && t != 3 && t != 12) point = t;
                } else if (t == point) {
                    point = 0;
                } else if (t == 7) {
                    break;
                }
            }

            dice = new uint8[](n);
            for (uint256 k = 0; k < n; ++k) {
                dice[k] = buf[k];
            }
        }
    }

    /// @notice The seed for hand `i` of a session seeded by `seed`.
    /// @dev Exposed so a single hand of a session can be pulled out and replayed on its own through
    ///      `resolveHand`, and so a session can be checked off-chain from the one word.
    function handSeed(bytes32 seed, uint256 i) public pure returns (bytes32 h) {
        // keccak256(abi.encodePacked(seed, i)) computed over the EVM scratch space: the 64-byte
        // preimage fits in 0x00..0x3F exactly, so the digest is identical and nothing is allocated.
        assembly ("memory-safe") {
            mstore(0x00, seed)
            mstore(0x20, i)
            h := keccak256(0x00, 0x40)
        }
    }

    /// @notice The dice for roll `i` of the hand seeded by `seed`.
    /// @dev Two independent 32-bit lanes of one keccak. Reducing a 32-bit draw mod 6 leaves a bias
    ///      of ~1.4e-9 per face — negligible. Reducing an 8-bit draw instead (the obvious shortcut)
    ///      would skew three faces by ~2.4%, which is larger than the entire pass-line edge it is
    ///      supposed to be riding on. Bits 64..255 are unused; a caller that wants fewer hashes can
    ///      amortise four rolls per word, at the cost of a less trivial off-chain replay.
    /// @return d1 First die, 1..6.
    /// @return d2 Second die, 1..6.
    function diceAt(bytes32 seed, uint256 i) public pure returns (uint256 d1, uint256 d2) {
        // Same scratch-space keccak as `handSeed` — this is the hottest line in the resolver, run
        // once per roll, and the digest is unchanged from the abi.encodePacked form.
        uint256 w;
        assembly ("memory-safe") {
            mstore(0x00, seed)
            mstore(0x20, i)
            w := keccak256(0x00, 0x40)
        }
        d1 = (uint256(uint32(w)) % 6) + 1;
        d2 = (uint256(uint32(w >> 32)) % 6) + 1;
    }

    // ---------------------------------------------------------------------------------------
    // Core
    // ---------------------------------------------------------------------------------------

    /// @dev `withLegs` selects full fidelity (per-leg staked/returned arrays, for views and the
    ///      edge oracle) or the lean mode a settlement uses, which keeps only the scalars it will
    ///      actually pay from. One roll loop serves both — the mode changes bookkeeping, never a
    ///      rule — and `o.returned` is accumulated at every credit site in both modes, so neither
    ///      ever needs a closing sweep over the leg array.
    ///
    ///      A non-empty `rollLog` records each roll as one byte (d1 high nibble, d2 low) starting
    ///      at `logPos`; `logEnd` is one past the last byte written. Recording rides the very rolls
    ///      being settled, so the log cannot drift from the money the way a re-walk could.
    function _run(
        Craps.Bets memory b,
        bytes32 seed,
        uint8[] memory script,
        bool withLegs,
        bytes memory rollLog,
        uint256 logPos,
        Outcome memory o
    ) internal pure returns (uint256 logEnd) {
        // `o` is caller-owned so the session loops can carry ONE struct across a rewind mark
        // instead of zero-filling a fresh 22-word allocation every hand. The caller must have set
        // `o.staked` to `stakeFor(b)` — it is constant across a session, so it is set once out
        // there rather than recomputed per hand. Only `returned` and the full-mode `legReturned`
        // accumulate — every other field is assigned below — so this reset is all reuse requires.
        o.returned = 0;
        if (withLegs) {
            _stakeBooks(b, o);
            for (uint256 k = 0; k < _LEGS; ++k) {
                o.legReturned[k] = 0;
            }
        }

        // Zero means logging is disabled; otherwise this points at the first data byte. Keeping
        // the data pointer on the stack avoids loading the bytes header on every dice roll.
        uint256 logPtr;
        if (rollLog.length != 0) {
            assembly ("memory-safe") {
                logPtr := add(rollLog, 0x20)
            }
        }

        // Dice sums, sub-2^146 payouts, sub-512 counters: every figure below is bounded far
        // inside uint256 (see the overflow note on Outcome), so the resolver runs unchecked —
        // 0.8's checked arithmetic costs more than the whole point machine at every roll.
        unchecked {
            // The whole machine lives in `st` (layout above). Keeping the loop's persistent state in
            // one word is what lets every local stay on the stack; no STAKE ever rides along — each
            // is a pure function of `b`, recomputed at its resolution event — only liveness does.
            uint256 st;
            if (b.place4 != 0) st |= 1 << 4;
            if (b.place5 != 0) st |= 1 << 5;
            if (b.place6 != 0) st |= 1 << 6;
            if (b.place8 != 0) st |= 1 << 8;
            if (b.place9 != 0) st |= 1 << 9;
            if (b.place10 != 0) st |= 1 << 10;
            if (b.hard4 != 0) st |= ST_HARD4_LIVE;
            if (b.hard8 != 0) st |= ST_HARD8_LIVE;
            if (b.passLine != 0) st |= ST_PASS_LIVE;
            if (b.dontPass != 0) st |= ST_DONT_LIVE;

            uint256 scripted;
            // Production callers pass a zero memory pointer instead of allocating an empty
            // array. Scripted replay passes a normal array and takes this one guarded load.
            assembly ("memory-safe") {
                if script { scripted := shr(1, mload(script)) }
            }
            uint256 i;
            for (; i < MAX_ROLLS; ++i) {
                uint256 d1;
                uint256 d2;
                if (i < scripted) {
                    d1 = script[2 * i];
                    d2 = script[2 * i + 1];
                } else {
                    // diceAt, inlined: one scratch-space keccak per roll is the loop's hottest line.
                    uint256 w;
                    assembly ("memory-safe") {
                        mstore(0x00, seed)
                        mstore(0x20, i)
                        w := keccak256(0x00, 0x40)
                    }
                    d1 = (uint256(uint32(w)) % 6) + 1;
                    d2 = (uint256(uint32(w >> 32)) % 6) + 1;
                }
                uint256 t = d1 + d2;
                bool comeOut = (st & ST_POINT_MASK) == 0;
                if (logPtr != 0) {
                    // Every caller sizes the buffer for its hard roll ceiling. Skip Solidity's
                    // per-roll bounds check and bytes1 alignment machinery in this hot path.
                    assembly ("memory-safe") {
                        mstore8(add(logPtr, logPos), or(shl(4, d1), d2))
                    }
                }
                // Advance the logical cursor whether or not bytes are being retained. Session
                // loops derive totalRolls from this cursor and avoid a memory update per hand.
                ++logPos;

                // --- Place bets: pay and stay, die on the 7 ---
                if (st & ST_PLACE_ANY != 0 && !comeOut) {
                    if (t == 7) {
                        st &= ~ST_PLACE_ANY;
                    } else if (st & (1 << t) != 0) {
                        uint256 idx = _placeIndex(t);
                        _pay(o, withLegs, LEG_PLACE + idx, _placeWin(b, idx));
                    }
                }

                // --- The hardways: the pair pays and stays; an easy way or the 7 kills it ---
                if (st & (ST_HARD4_LIVE | ST_HARD8_LIVE) != 0 && !comeOut) {
                    if (t == 7) {
                        st &= ~(ST_HARD4_LIVE | ST_HARD8_LIVE);
                    } else if (t == 4 && st & ST_HARD4_LIVE != 0) {
                        if (d1 == d2) {
                            _pay(o, withLegs, LEG_HARD4, uint256(b.hard4) * (7 * FLIP));
                        } else {
                            st &= ~ST_HARD4_LIVE;
                        }
                    } else if (t == 8 && st & ST_HARD8_LIVE != 0) {
                        if (d1 == d2) {
                            _pay(o, withLegs, LEG_HARD8, uint256(b.hard8) * (9 * FLIP));
                        } else {
                            st &= ~ST_HARD8_LIVE;
                        }
                    }
                }

                // --- The dark side: ONE decision per shooter, bar the twelve ---
                // Ahead of the point machine below, which is what moves the point out from under
                // it: `comeOut` and the point read here are the ones this roll was judged against.
                if (st & ST_DONT_LIVE != 0) {
                    if (comeOut) {
                        if (t == 2 || t == 3) {
                            _pay(o, withLegs, LEG_DONT_PASS, _dontWin(b));
                            st &= ~ST_DONT_LIVE;
                        } else if (t == 7 || t == 11) {
                            // A come-out natural kills it, and is NOT a seven-out: the shooter
                            // rolls on with the wager retired.
                            st &= ~ST_DONT_LIVE;
                        }
                        // 12 is barred: no profit, no loss, and the same wager stays up. A point
                        // leaves it up too, to be decided by the seven or the point.
                    } else if (t == 7) {
                        // The seven-out is the wager's win, and it collects before the hand ends.
                        _pay(o, withLegs, LEG_DONT_PASS, _dontWin(b));
                        st &= ~ST_DONT_LIVE;
                    } else if (t == (st >> ST_POINT) & 0xF) {
                        st &= ~ST_DONT_LIVE;
                    }
                }

                // --- Line bets and the point state machine ---
                if (comeOut) {
                    if (t == 7 || t == 11) {
                        // A 7 on the come-out is NOT a seven-out. The line wins 1:1 and, like every
                        // other bet on this board, pays and stays.
                        if (st & ST_PASS_LIVE != 0) {
                            _pay(o, withLegs, LEG_PASS, uint256(b.passLine) * FLIP);
                        }
                    } else if (t == 2 || t == 3 || t == 12) {
                        // Craps out: the line's one death. With no dark side on the board there is
                        // no barred 12 either.
                        st &= ~ST_PASS_LIVE;
                    } else {
                        st |= t << ST_POINT;
                    }
                } else if (t == (st >> ST_POINT) & 0xF) {
                    // Distinct points made, kept as telemetry (`pointsMade`).
                    st |= 1 << (ST_FIRE + t);
                    if (st & ST_PASS_LIVE != 0) {
                        _pay(o, withLegs, LEG_PASS, uint256(b.passLine) * FLIP);
                    }
                    st &= ~ST_POINT_MASK;
                } else if (t == 7) {
                    st &= ~ST_PASS_LIVE;
                    st |= ST_SEVEN_OUT;
                    break;
                }
            }

            // --- End of hand ---

            o.rolls = uint32(st & ST_SEVEN_OUT != 0 ? i + 1 : i);
            o.pointsMade = uint8(_countPoints((st >> ST_FIRE) & 0xFFFF));

            o.truncated = st & ST_SEVEN_OUT == 0;
            if (o.truncated) {
                // Refund whatever is still in action rather than confiscating it on a technicality.
                // Every condition reads the state word or the wager, never the leg array, so this
                // block works identically with the per-leg books switched off.
                if (st & ST_PASS_LIVE != 0) _pay(o, withLegs, LEG_PASS, uint256(b.passLine) * FLIP);
                for (uint256 k = 0; k < 6; ++k) {
                    if (st & (1 << _placeTotal(k)) != 0) _pay(o, withLegs, LEG_PLACE + k, _placeWei(b, k));
                }
                if (st & ST_HARD4_LIVE != 0) _pay(o, withLegs, LEG_HARD4, uint256(b.hard4) * FLIP);
                if (st & ST_HARD8_LIVE != 0) _pay(o, withLegs, LEG_HARD8, uint256(b.hard8) * FLIP);
                // An UNDECIDED dark wager gets its stake back; a decided one gets nothing, having
                // already been paid or lost. The liveness bit is exactly that distinction.
                if (st & ST_DONT_LIVE != 0) _pay(o, withLegs, LEG_DONT_PASS, uint256(b.dontPass) * FLIP);
            }

            o.net = int256(o.returned) - int256(o.staked);
            logEnd = logPos;
        }
    }

    function _stakeBooks(Craps.Bets memory b, Outcome memory o) private pure {
        // The caller-set `o.staked` scalar is the settlement-grade figure; the fuzz suite pins it
        // equal to this leg vector's sum, so the two derivations cannot drift apart unnoticed.
        unchecked {
            o.legStaked[LEG_PASS] = uint256(b.passLine) * FLIP;
            for (uint256 k = 0; k < 6; ++k) {
                o.legStaked[LEG_PLACE + k] = _placeWei(b, k);
            }
            o.legStaked[LEG_HARD4] = uint256(b.hard4) * FLIP;
            o.legStaked[LEG_HARD8] = uint256(b.hard8) * FLIP;
            o.legStaked[LEG_DONT_PASS] = uint256(b.dontPass) * FLIP;
        }
    }

    /// @dev THE ESCALATOR: the mandatory wager for shooter `hand`, in base-board units — doubling
    ///      every `ESC_HANDS` shooters, capped at the 65,535-unit table limit. Surviving the table
    ///      means outracing this: a slip cannot flat-grind forever, because the floor under its
    ///      wager keeps rising.
    function _escOf(uint256 hand) private pure returns (uint256 esc) {
        unchecked {
            esc = 1 << (hand / ESC_HANDS);
            if (esc > 0xFFFF) esc = 0xFFFF;
        }
    }

    /// @dev Independent twin of the production survival coin: a fair, committed double-or-nothing
    ///      keyed on the table seed, the run-length `n` and the slip's OWNER. The owner is what
    ///      keeps one player's second chance off the rest of the field.
    function _survived(bytes32 seed, uint256 n, address player) private pure returns (bool) {
        return uint256(keccak256(abi.encode(SURVIVAL_TAG, seed, n, player))) & 1 == 1;
    }

    /// @dev Copy one hand's summary into a ledger slot. Split out of the session loops so their
    ///      frames hold fewer live memory pointers — inlined, the extra pointers push the
    ///      production compiler profile (via-IR at higher optimizer runs) past stack depth.
    function _record(HandRecord[] memory led, uint256 i, Outcome memory o) private pure {
        HandRecord memory h = led[i];
        h.net = o.net;
        h.rolls = o.rolls;
        h.pointsMade = o.pointsMade;
        h.truncated = o.truncated;
    }

    /// @dev Credit `amount` to the hand's return, and to the per-leg breakdown only when the
    ///      caller is keeping one. Bounded far below 2^256 (see the overflow note on Outcome), so
    ///      the scalar add is safe unchecked.
    function _pay(Outcome memory o, bool withLegs, uint256 leg, uint256 amount) private pure {
        unchecked {
            o.returned += amount;
            if (withLegs) o.legReturned[leg] += amount;
        }
    }

    // ---------------------------------------------------------------------------------------
    // Tables
    // ---------------------------------------------------------------------------------------

    /// @dev Place index (0..3) -> dice total: 0,1 -> 5,6 and 2,3 -> 8,9.
    function _placeTotal(uint256 idx) private pure returns (uint256) {
        return idx < 3 ? idx + 4 : idx + 5;
    }

    /// @dev Dice total -> place index. Inverse of `_placeTotal`; only called for 4, 5, 6, 8, 9, 10.
    function _placeIndex(uint256 t) private pure returns (uint256) {
        return t < 7 ? t - 4 : t - 5;
    }

    /// @dev The stake on place index `idx`, in wei. The struct's named fields are what buy the
    ///      one-slot packing; this is the array view the resolver's index math wants.
    function _placeWei(Craps.Bets memory b, uint256 idx) private pure returns (uint256) {
        unchecked {
            if (idx == PLACE_4) return uint256(b.place4) * FLIP;
            if (idx == PLACE_5) return uint256(b.place5) * FLIP;
            if (idx == PLACE_6) return uint256(b.place6) * FLIP;
            if (idx == PLACE_8) return uint256(b.place8) * FLIP;
            if (idx == PLACE_9) return uint256(b.place9) * FLIP;
            return uint256(b.place10) * FLIP;
        }
    }

    /// @dev Place winnings. 4/10 and 5/9 pay TRUE ODDS — 2:1 and 3:2 — so those legs are exactly
    ///      fair; only 6/8 at 7:6 still carries an edge. Keeping each denominator literal lets the
    ///      compiler prove it nonzero and removes the generic checked-division guard from every
    ///      place hit.
    function _placeWin(Craps.Bets memory b, uint256 idx) private pure returns (uint256 stake) {
        stake = _placeWei(b, idx);
        if (idx == PLACE_4 || idx == PLACE_10) return stake * 2;
        if (idx == PLACE_5 || idx == PLACE_9) return (stake * 3) / 2;
        return (stake * 7) / 6;
    }

    /// @dev What a WINNING dark wager returns in full: its own stake back plus 3:4 of it, the
    ///      profit floored once at wei precision. Unlike everything else on this board the stake
    ///      comes home with the winnings, because the wager retires the moment it wins.
    function _dontWin(Craps.Bets memory b) private pure returns (uint256) {
        unchecked {
            return uint256(b.dontPass) * FLIP + (uint256(b.dontPass) * (3 * FLIP)) / 4;
        }
    }


    /// @dev Distinct points made, from the bitmask set at each point-made roll. Counts all six
    ///      point totals — 4 and 10 can still be points even though they take no place bets.
    function _countPoints(uint256 mask) private pure returns (uint256 n) {
        unchecked {
            mask &= _POINT_TOTALS_MASK;
            while (mask != 0) {
                mask &= mask - 1;
                ++n;
            }
        }
    }
}
