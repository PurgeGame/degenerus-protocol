// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @title Craps
/// @notice A self-contained, stateless resolver for one craps shooter's hand.
///
///         Every bet is placed once, before the come-out roll, and stays in action until the
///         shooter sevens out. There is no betting between rolls: no Come / Don't Come, no
///         take-downs, no press. The whole hand is a pure function of (bets, seed), which makes it
///         replayable off-chain, fuzzable, and free to call via `eth_call`.
///
///         `_settleSlip` extends the same idea across several hands: one bet set, paid for
///         upfront, played over N consecutive shooters off a single seed and settled once at the
///         end. Nothing is decided between hands any more than between rolls.
///
///         This contract holds no funds and has no state. A wrapper supplies a seed that was
///         unknown when the board was locked and pays the returned bankroll.
///
/// @dev THE BOUNDED-LOSS INVARIANT
///
///      Every bet in this resolver loses at most its own stake, and the sum of stakes is known at
///      bet time. That is not an accident of the payout tables — it is why this exact bet set was
///      chosen:
///
///        * The light side "pays and stays": a win credits winnings only, the stake remains at risk,
///          and the stake is lost when the bet dies. The pass line pays every natural and every
///          point made until its first loss — a come-out craps or the seven-out. Place bets and
///          hardways can pay many times but die once, on the 7.
///        * Don't Pass is the one wager that does NOT stay: it is a single decision per shooter,
///          settled the first time the dice answer it, and it returns its own stake with the
///          winnings when it wins. A barred twelve is the only push, and it leaves the same wager
///          up for the come-out that follows. So it too loses at most its stake, exactly once.
///
///      So `_stakeFor(b)` is the player's exact maximum loss for one hand and no upfront liability
///      formula is needed. Winnings are unbounded above (a long hand can hit a place number many
///      times), which is the house's problem, not the escrow's.
///
///      What is missing and why:
///
///        * Come and Don't Come are structurally impossible here, not merely inconvenient. A Come
///          bet IS a bet made during a point phase; there is no such thing as placing one before
///          the come-out. Supporting them means accepting a pre-declared betting policy, which
///          turns this resolver into a strategy interpreter. Don't PASS is not in that family — it
///          is placed before the come-out like everything else here.
///        * Field and the one-roll propositions resolve on a single roll, so riding them to the end
///          of a hand means re-arming them every roll. That is what actually breaks bounded loss,
///          and it is why they are out.
///
/// @dev HOUSE RULES PINNED HERE (there is no canonical craps; these are the choices)
///
///        * The board is the basics and nothing else: the pass line, all six place
///          numbers, the two iconic hardways — the hard four and the hard eight — and one dark
///          lane, Don't Pass. Everything else that only bled (Big 6/8, the other hardways), every
///          side lottery (Fire, All/Tall/Small) and pass odds has been cut. In this
///          ride-to-the-seven-out model the pass line runs 2.79% (still the textbook 1.41% per
///          decision), place 4/10 and 5/9 pay TRUE ODDS and run exactly 0%, place 6/8 at 7:6 run
///          2.78%, and the indulgences are the hardways (10% on the eight, 12.5% on the four) and
///          the dark lane, deliberately the dearest seat on the table: Don't Pass pays 3:4 and
///          runs 13.73% per decision.
///        * Stakes are WHOLE FLIP, uint24 per leg: the type itself is the table maximum of
///          16,777,215 FLIP a leg. All payout math still runs in wei internally, so fractions pay
///          exactly as they always did. One consequence worth loving: the entire bet slip packs
///          into a single storage slot.
///        * Place bets and the hardways are OFF on the come-out, the table default, and there is no
///          toggle. Working them changes no house edge whatsoever — every roll is i.i.d. — so the
///          switch bought a player nothing but a decision to get wrong.
///        * Payouts are floored. Stakes in multiples of 30 FLIP make every payout exact.
contract Craps {
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
    ///      A hand that hits it has every still-live stake refunded rather than being silently
    ///      confiscated.
    uint256 internal constant _MAX_ROLLS = 512;

    /// @notice Total dice rolls a bet slip may consume, judged between shooters.
    /// @dev This is what makes a slip settlement's gas a GUARANTEE instead of a probability. The
    ///      shooter cap alone leaves a bounded-but-huge worst case (cap x _MAX_ROLLS rolls); with
    ///      this budget the hard ceiling is `_SLIP_ROLL_CEILING` rolls however the dice fall.
    ///      Hitting it is an ordinary stop between shooters; every shooter still settles whole,
    ///      and the budget never cuts a hand mid-roll.
    uint256 internal constant _SLIP_ROLL_BUDGET = 8192;

    /// @notice Shooter cap on a bet slip. A run does not stop when it wins — it latches the goal
    ///         and plays on — so it needs room to: the escalator reaches its ceiling at shooter
    ///         96, and twice that is where the cap belongs.
    uint256 internal constant _MAX_SLIP_HANDS = 512;

    /// @notice THE ABSOLUTE TOTAL-ROLL CEILING, and the figure the gas and work-unit bounds are
    ///         sized on. NOT the budget: the budget is judged BETWEEN shooters, so the last
    ///         shooter it admits may still run a full `_MAX_ROLLS` hand of its own.
    uint256 internal constant _SLIP_ROLL_CEILING = _SLIP_ROLL_BUDGET - 1 + _MAX_ROLLS;

    /// @notice Shooters between each mandatory doubling of a slip's base wager.
    /// @dev The escalator: shooters 0-2 wager 1x the board, 3-5 wager 2x, 6-8 wager 4x, and so on,
    ///      capped at `_ESC_CAP`. A slip that cannot cover the doubled wager stops between
    ///      shooters with its remainder intact. Deterministic in the hand ordinal, so the whole
    ///      run is still recomputable from the base board and the seed alone.
    uint256 internal constant _ESC_HANDS = 3;

    /// @notice The escalator ceiling, in base-board units. A 16-bit lane would flatten the
    ///         mandatory wager from the 48th shooter on, which would cap the RUN rather than the
    ///         dice; at `uint32.max` the escalator is the binding term for as long as a slip can
    ///         survive it — shooters 93-95 wager 2,147,483,648x and 96 onward wagers the ceiling.
    uint256 internal constant _ESC_CAP = type(uint32).max;

    /// @dev The slip loop's own cursor, one stack word (see the note in `_settleSlip`):
    ///        bits  0..14  hands played
    ///        bit  15      GOAL QUALIFIED, latched
    ///        bits 16..47  this round's mandatory multiplier
    ///        bits 48..79  the roll-log cursor
    ///      The latch sits UNDER the log rather than over it so the log stays the top of the word
    ///      and every read of it is a bare shift. Fifteen bits is sixty-four times the widest
    ///      hand cap either product uses.
    uint256 private constant _CUR_HANDS_MASK = 0x7FFF;
    uint256 private constant _CUR_QUALIFIED = 1 << 15;
    uint256 private constant _CUR_MULT_SHIFT = 16;
    uint256 private constant _CUR_MULT_MASK = 0xFFFFFFFF;
    uint256 private constant _CUR_LOG_SHIFT = 48;
    /// @dev The two slices the next round inherits from this one: the latch and the multiplier.
    uint256 private constant _CUR_CARRY_MASK = (_CUR_MULT_MASK << _CUR_MULT_SHIFT) | _CUR_QUALIFIED;

    /// @notice Domain tag for the mid-run second-chance coin, separated from the dice stream.
    uint256 internal constant SURVIVAL_TAG = 0x537572766976616c; // "Survival"

    /// @notice Domain tag for the scheduled shooter profit boost, separated from the dice stream,
    ///         from the survival coin and from every draw the wrapper takes off the same word.
    uint256 internal constant SHOOTER_BOOST_TAG = 0x53686f6f746572426f6f7374; // "ShooterBoost"

    /// @dev The six totals that can be a point.
    uint256 internal constant _POINT_TOTALS_MASK = (1 << 4) | (1 << 5) | (1 << 6) | (1 << 8) | (1 << 9) | (1 << 10);

    /// @dev The roll loop's entire state machine, packed into one stack word so it never leaves
    ///      the stack. Field layout, indexed by dice total `t` where a total is the key:
    ///        bits  0..15  live place-bet totals (bit t; only 4, 5, 6, 8, 9, 10 are ever set)
    ///        bits 32..35  the point (0 = come-out)
    ///        bit  40      pass line live          bit 43  seven-out happened
    ///        bit  41      don't pass live         bit 44  hard four live
    ///        bit  42      hard eight live
    uint256 private constant ST_POINT = 32;
    uint256 private constant ST_PLACE_ANY = 0xFFFF;
    uint256 private constant ST_POINT_MASK = 0xF << 32;
    uint256 private constant ST_PASS_LIVE = 1 << 40;
    /// @dev Don't Pass is UNRESOLVED, not merely staked: it is cleared the moment the wager wins
    ///      or loses, which is what makes it at most one decision per shooter and what tells a
    ///      roll-cap truncation whether the stake is still owed back.
    uint256 private constant ST_DONT_LIVE = 1 << 41;
    uint256 private constant ST_HARD8_LIVE = 1 << 42;
    uint256 private constant ST_SEVEN_OUT = 1 << 43;
    uint256 private constant ST_HARD4_LIVE = 1 << 44;
    /// @dev The dark wager COLLECTED this hand. Its win hands back its own stake alongside the
    ///      3:4, and that stake is principal — so the profit boost needs to know, and the state
    ///      word already rides the whole roll loop where a second local would not.
    uint256 private constant ST_DONT_WON = 1 << 45;

    /// @dev One hand's return word, as the resolvers pack it and `_settleSlip` reads it back:
    ///        bits   0..111  the amount the hand returned
    ///        bits 112..143  the roll-log cursor
    ///        bits 144..255  the ELIGIBLE PROFIT inside that amount — winnings only, never a
    ///                       stake refund and never the principal a winning dark wager hands back
    ///      Both money fields are bounded by the same argument: 512 rolls of the whole board at
    ///      the uint24 leg maximum comes to under 2^98, and the profit is a part of that amount.
    ///      `_settleSlip` adds the boost straight onto the packed word, which is safe on the same
    ///      figure — a boost is at most a fraction of the profit, so the sum stays fourteen orders
    ///      of magnitude clear of the cursor. The cursor itself is the roll budget plus one
    ///      terminator per shooter, far inside its 32 bits.
    uint256 private constant _HR_LOG_SHIFT = 112;
    uint256 private constant _HR_PROFIT_SHIFT = 144;
    uint256 private constant _HR_AMOUNT_MASK = (1 << 112) - 1;
    uint256 private constant _HR_LOG_MASK = 0xFFFFFFFF;

    // ---------------------------------------------------------------------------------------
    // Types
    // ---------------------------------------------------------------------------------------

    /// @notice Everything the player puts down before the come-out roll. Any leg may be zero.
    ///         All stakes are WHOLE FLIP; the uint24 fields make 16,777,215 FLIP the table max per
    ///         leg, and the whole slip fits one storage slot.
    /// @param passLine   Pass Line: every natural and every point made pays 1:1 and the line stays
    ///                   up; dies on its first come-out craps or the seven-out.
    /// @param place4     Place 4: pays TRUE ODDS, 2:1 on every 4, and stays up; the stake is lost
    ///                   on the 7. A fair leg — the table takes nothing from it.
    /// @param place5     Place 5: 3:2, also true odds, same shape.
    /// @param place6     Place 6: 7:6, same shape. The one place leg that still carries an edge.
    /// @param place8     Place 8: 7:6, same shape.
    /// @param place9     Place 9: 3:2, same shape.
    /// @param place10    Place 10: 2:1, same shape.
    /// @param hard4      The hard four: 2-2 pays 7:1 and stays up; dies on an easy 4 or the 7.
    /// @param hard8      The hard eight: 4-4 pays 9:1 and stays up; dies on an easy 8 or the 7.
    /// @param dontPass   Don't Pass: ONE decision per shooter, and the only wager here that does
    ///                   not stay. It wins on a come-out 2 or 3 and on the seven-out, loses on a
    ///                   come-out 7 or 11 and on the point made, and pushes on a barred 12 — which
    ///                   leaves it up for the next come-out. A win returns the stake plus 3:4; a
    ///                   loss returns nothing. Deliberately the dearest leg on the table.
    struct Bets {
        uint24 passLine;
        uint24 place4;
        uint24 place5;
        uint24 place6;
        uint24 place8;
        uint24 place9;
        uint24 place10;
        uint24 hard4;
        uint24 hard8;
        uint24 dontPass;
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
    /// @param peakBankroll THE HIGH POINT: the largest bankroll the run ever held at a COMPLETED
    ///                     shooter boundary, starting at `bankrollIn`. Sampled once per shooter,
    ///                     after that shooter's return and boost have landed — never before a
    ///                     stake, never after one, never mid-hand. It is a RANKING figure and a
    ///                     record candidate; it is never what a slip is paid.
    /// @param handsPlayed  Shooters actually played.
    /// @param unitsPlayed  Base-board units wagered across the run — the sum of each round's
    ///                     escalating mandatory multiplier. Only equals `handsPlayed` before the
    ///                     escalator first doubles.
    /// @param totalRolls   Dice rolls across the run.
    /// @param stop         Why it ended.
    struct SlipResult {
        uint256 bankrollIn;
        uint256 bankrollOut;
        uint256 peakBankroll;
        uint256 handsPlayed;
        uint256 unitsPlayed;
        uint256 totalRolls;
        SlipStop stop;
    }

    // ---------------------------------------------------------------------------------------
    // Entry points
    // ---------------------------------------------------------------------------------------

    /// @dev The slip engine: the same wager repeated shooter after shooter out of a bankroll. It
    ///      returns a scalar run receipt; per-leg books and per-hand ledgers are not retained.
    ///
    ///      Stop conditions are judged BETWEEN shooters, in this order: goal first (so a run that
    ///      is simultaneously at goal and out of the next stake counts as a win), then the hard
    ///      bounds, then affordability. A round short of even half its escalating wager busts outright; one that
    ///      can cover between half and all of it takes a single committed double-or-nothing on the
    ///      whole bankroll — surviving doubles it (enough to cover the round) and plays on, losing
    ///      ends the slip with nothing. Each played round escrows its wager — the base board times
    ///      the escalating mandatory multiplier (see `_ESC_HANDS`) — out of the bankroll, plays one
    ///      hand, and credits back whatever it returned; the bounded-loss invariant is exactly what
    ///      makes the escrow subtraction safe unchecked after the affordability check. A busted
    ///      bankroll keeps its remainder.
    ///
    ///      THE HIGH WATER. The goal is not a finish line: the first time the bankroll reaches it
    ///      between shooters, the win LATCHES and the run plays ON. Every slip this engine settles
    ///      works this way — a custom table and a protocol-scheduled Dice Run play by the same
    ///      rules, and differ only in what the WRAPPER does with the result:
    ///
    ///        * the goal becomes a PROTECTED RESERVE. A later shooter is posted only when
    ///          `bankroll - need >= goal`, equality included, so a losing shooter can lower the
    ///          payout and can never lower it through the goal;
    ///        * the survival coin is never taken again — the reserve rule, not a coin, decides
    ///          affordability from the latch on;
    ///        * a hard bound reached AFTER the latch stops as Goal, and one reached before it is
    ///          the ordinary bust it always was;
    ///        * `bankrollOut` is the bankroll at the ACTUAL stop. The high point ranks the run and
    ///          feeds the records; it is never paid.
    ///
    ///      Because every payout is linear in the stakes, a q-unit round is EXACTLY q times the
    ///      base hand: the engine rolls the base board once and scales, which is what keeps the
    ///      dice log that of the base board however far the escalator has climbed.
    ///
    ///      THE SHOOTER PROFIT BOOST rides here and nowhere else. `boost` names a schedule the
    ///      wrapper fixed before the seed existed — how often a shooter is eligible, and what the
    ///      house adds to that shooter's PROFIT when one is — and zero turns the whole thing off,
    ///      which is what a custom table passes. Eligibility is drawn per SHOOTER and per PLAYER
    ///      off the same committed seed the dice come from, so one field shares its shooters and
    ///      no two seats share a schedule. The boost lands in the base hand, so it is inside the
    ///      bankroll before the next goal, bound and affordability check — it may cross a goal a
    ///      shooter early, or buy a round the run could not otherwise afford, on purpose.
    ///
    ///      Loop state note: `cur` packs the hand counter, the round's mandatory multiplier, the
    ///      roll cursor and the goal latch into one stack slot (see `_CUR_HANDS_MASK`) — via-IR
    ///      runs out of stack here with them separate.
    /// @param boost Packed schedule: the eligible-shooter percentage in bits 0..7 and the percent
    ///              added to an eligible shooter's profit in bits 8..15. Zero is no schedule.
    function _settleSlip(
        Bets memory b,
        bytes32 seed,
        uint256 bankroll,
        uint256 goal,
        uint256 cap,
        uint256 rollBudget,
        address player,
        uint256 boost
    ) internal pure returns (SlipResult memory r) {
        uint256 stake = _stakeFor(b);

        r.bankrollIn = bankroll;
        r.peakBankroll = bankroll;
        uint256 initialState = _settlementState(b);
        // Cache place winnings by dice total, plus the whole figure a winning Don't Pass returns
        // at index zero. Sized to the highest total the dice can throw, so the resolvers' indexed
        // read is in bounds for every roll rather than only for the totals a live place bit can
        // name. Keeping the board pointer in the resolver is deliberate: via-IR otherwise inlines
        // the whole hand machine through the battle wrapper and exhausts its stack.
        uint256[13] memory wins;
        unchecked {
            if (initialState & ST_PLACE_ANY != 0) {
                wins[4] = uint256(b.place4) * (2 * FLIP);
                wins[5] = (uint256(b.place5) * (3 * FLIP)) / 2;
                wins[6] = (uint256(b.place6) * (7 * FLIP)) / 6;
                wins[8] = (uint256(b.place8) * (7 * FLIP)) / 6;
                wins[9] = (uint256(b.place9) * (3 * FLIP)) / 2;
                wins[10] = uint256(b.place10) * (2 * FLIP);
            }
            if (initialState & ST_DONT_LIVE != 0) {
                wins[0] = uint256(b.dontPass) * FLIP + (uint256(b.dontPass) * (3 * FLIP)) / 4;
            }
        }

        unchecked {
            uint256 cur;
            while (true) {
                // THE GOAL, judged once. The slip does not stop on it — it LATCHES and plays
                // on, and the latch is what every branch below then reads.
                if (cur & _CUR_QUALIFIED == 0 && goal != 0 && bankroll >= goal) {
                    r.stop = SlipStop.Goal;
                    cur |= _CUR_QUALIFIED;
                }
                // A hard bound is an ordinary bust BEFORE the goal and an ordinary stop after it.
                // Bust is enum zero and a latched goal has already written its verdict, so a bare
                // break says both; the battle wrapper forfeits a busted run's remainder.
                if (
                    cur & _CUR_HANDS_MASK == cap
                        || (cur >> _CUR_LOG_SHIFT) - (cur & _CUR_HANDS_MASK) >= rollBudget
                ) {
                    break;
                }

                {
                    uint256 q = _escOf(cur & _CUR_HANDS_MASK);
                    uint256 need = stake * q;
                    if (cur & _CUR_QUALIFIED != 0) {
                        // THE PROTECTED RESERVE. Past the goal the run wagers only what it holds
                        // ABOVE it, so the bounded-loss invariant makes the win unlosable: the
                        // worst this shooter can do is give back `need`, which lands exactly on
                        // the goal. Equality is playable; anything short of it retires the run.
                        if (bankroll - goal < need) break;
                    } else if (bankroll * 2 < need) {
                        // Short of even half the round: no second chance, the slip busts.
                        r.stop = SlipStop.Bust;
                        break;
                    } else if (bankroll < need) {
                        // Between half and a full round: the table's survival coin for this round —
                        // the same double-or-nothing that would decide a run of this length at the
                        // end — rides the whole bankroll. Surviving doubles it, enough to cover
                        // exactly this round, and play continues; losing ends the slip with nothing.
                        // It is a PRE-GOAL instrument only: past the latch the reserve decides.
                        if (_survived(seed, cur & _CUR_HANDS_MASK, player)) {
                            bankroll += bankroll;
                        } else {
                            bankroll = 0;
                            r.stop = SlipStop.Bust;
                            break;
                        }
                    }
                    cur = (cur & ~(_CUR_MULT_MASK << _CUR_MULT_SHIFT)) | (q << _CUR_MULT_SHIFT);
                }

                bankroll -= ((cur >> _CUR_MULT_SHIFT) & _CUR_MULT_MASK) * stake;

                uint256 handOut = _runSettlement(
                    b,
                    handSeed(seed, cur & _CUR_HANDS_MASK), cur >> _CUR_LOG_SHIFT, initialState, wins
                );
                // THE SHOOTER PROFIT BOOST. House money on the base hand's ELIGIBLE PROFIT and on
                // nothing else, floored ONCE here so the round's escalating multiple below scales
                // one boosted base figure rather than drawing a schedule per copy.
                if (boost != 0 && _boostedShooter(seed, cur & _CUR_HANDS_MASK, player, boost & 0xFF)) {
                    handOut += ((handOut >> _HR_PROFIT_SHIFT) * (boost >> 8)) / 100;
                }
                bankroll += ((cur >> _CUR_MULT_SHIFT) & _CUR_MULT_MASK) * (handOut & _HR_AMOUNT_MASK);
                // ACCUMULATED IN MEMORY, not on the stack. The loop's live set is what decides
                // whether via-IR can allocate this frame at all, and the running handle is the one
                // figure in it that nothing inside the loop reads back.
                r.unitsPlayed += (cur >> _CUR_MULT_SHIFT) & _CUR_MULT_MASK;
                // THE HIGH POINT, sampled here and nowhere else: one completed shooter, its return
                // and its boost already banked, before the next round's stake leaves again.
                if (bankroll > r.peakBankroll) r.peakBankroll = bankroll;
                cur = ((((handOut >> _HR_LOG_SHIFT) & _HR_LOG_MASK) + 1) << _CUR_LOG_SHIFT)
                    | (cur & _CUR_CARRY_MASK) | ((cur & _CUR_HANDS_MASK) + 1);
            }

            r.handsPlayed = cur & _CUR_HANDS_MASK;
            r.bankrollOut = bankroll;
            r.totalRolls = (cur >> _CUR_LOG_SHIFT) - (cur & _CUR_HANDS_MASK);
        }
    }

    /// @notice Total staked across every leg of `b` — one hand's charge.
    /// @dev What an escrow must collect up front, and the exact ceiling on what the player can
    ///      lose. Multiply by the hand count for a session.
    function _stakeFor(Bets memory b) internal pure returns (uint256 total) {
        // Stakes are whole FLIP; the charge is wei. Bounded far below 2^256: ten uint24 legs.
        unchecked {
            total =
                (uint256(b.passLine)
                        + uint256(b.place4)
                        + uint256(b.place5)
                        + uint256(b.place6)
                        + uint256(b.place8)
                        + uint256(b.place9)
                        + uint256(b.place10)
                        + uint256(b.hard4)
                        + uint256(b.hard8)
                        + uint256(b.dontPass)) * FLIP;
        }
    }

    /// @notice The seed for hand `i` of a session seeded by `seed`.
    /// @dev Exposed so a single hand of a run can be pulled out and replayed on its own, and so a
    ///      whole run can be checked off-chain from the one word.
    function handSeed(bytes32 seed, uint256 i) internal pure returns (bytes32 h) {
        // keccak256(abi.encodePacked(seed, i)) computed over the EVM scratch space: the 64-byte
        // preimage fits in 0x00..0x3F exactly, so the digest is identical and nothing is allocated.
        assembly ("memory-safe") {
            mstore(0x00, seed)
            mstore(0x20, i)
            h := keccak256(0x00, 0x40)
        }
    }

    /// @dev Exact `keccak256(abi.encode(a, b))` over the EVM scratch space. Kept here because
    ///      table seeding, mapping-slot reads and several settlement draws all share this shape.
    function _hash2(uint256 a, uint256 b) internal pure returns (uint256 h) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            h := keccak256(0x00, 0x40)
        }
    }

    /// @dev Exact `keccak256(abi.encode(a, b, c))`, using temporary free memory without moving
    ///      its pointer. Three words do not fit in the EVM's 64-byte scratch region.
    function _hash3(uint256 a, uint256 b, uint256 c) internal pure returns (uint256 h) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, a)
            mstore(add(ptr, 0x20), b)
            mstore(add(ptr, 0x40), c)
            h := keccak256(ptr, 0x60)
        }
    }

    // ---------------------------------------------------------------------------------------
    // Core
    // ---------------------------------------------------------------------------------------

    /// @dev One shooter's hand, money only. It consumes the random stream and applies the state
    ///      transitions of the full rules, but computes only what a settlement can observe — the
    ///      amount returned — omitting leg books and net/roll/point telemetry entirely.
    ///
    ///      `test/craps` grades this against an independent implementation of the same rules off
    ///      the identical seed; that differential is what stands in for the per-leg assertions the
    ///      scalar return cannot make on its own.
    function _runSettlement(Bets memory b, bytes32 seed, uint256 logPos, uint256 st, uint256[13] memory wins)
        private
        pure
        returns (uint256 packed)
    {
        uint256 returned;

        unchecked {
            // A board with no line bet skips the point machine entirely; every other shape runs
            // the general one. A line-ONLY board is not worth a third machine: the dice place
            // three of the ten chips uniformly over ten legs, so one board in 1,000 stays
            // line-only even when all seven picked chips are on the line.
            if (st & ST_PASS_LIVE == 0) {
                return _runSideSettlement(b, seed, logPos, st, wins);
            }

            uint256 i;
            for (; i < _MAX_ROLLS; ++i) {
                uint256 w;
                assembly ("memory-safe") {
                    mstore(0x00, seed)
                    mstore(0x20, i)
                    w := keccak256(0x00, 0x40)
                }
                uint256 t = (uint256(uint32(w)) % 6) + (uint256(uint32(w >> 32)) % 6) + 2;

                uint256 point = st & ST_POINT_MASK;
                if (point == 0) {
                    if (t == 7 || t == 11) {
                        if (st & ST_PASS_LIVE != 0) returned += uint256(b.passLine) * FLIP;
                        st &= ~ST_DONT_LIVE;
                    } else if (t == 12) {
                        st &= ~ST_PASS_LIVE;
                    } else if (t == 2 || t == 3) {
                        st &= ~ST_PASS_LIVE;
                        if (st & ST_DONT_LIVE != 0) {
                            returned += wins[0];
                            st = (st | ST_DONT_WON) & ~ST_DONT_LIVE;
                        }
                    } else {
                        st |= t << ST_POINT;
                    }
                } else {
                    // A point-phase seven ends the hand before any light bet can pay. Don't Pass
                    // is the exception: this is the decision it was waiting for.
                    if (t == 7) {
                        if (st & ST_DONT_LIVE != 0) {
                            returned += wins[0];
                            st |= ST_DONT_WON;
                        }
                        st |= ST_SEVEN_OUT;
                        break;
                    }
                    // Place winnings are indexed directly by dice total. Totals without a live
                    // place bit never touch memory.
                    if (st & (1 << t) != 0) {
                        assembly ("memory-safe") {
                            returned := add(returned, mload(add(wins, shl(5, t))))
                        }
                    }
                    if (st & (ST_HARD4_LIVE | ST_HARD8_LIVE) != 0) {
                        if (t == 4 && st & ST_HARD4_LIVE != 0) {
                            if (uint32(w) % 6 == uint32(w >> 32) % 6) {
                                returned += uint256(b.hard4) * (7 * FLIP);
                            }
                            else st &= ~ST_HARD4_LIVE;
                        } else if (t == 8 && st & ST_HARD8_LIVE != 0) {
                            if (uint32(w) % 6 == uint32(w >> 32) % 6) {
                                returned += uint256(b.hard8) * (9 * FLIP);
                            }
                            else st &= ~ST_HARD8_LIVE;
                        }
                    }
                    if (t << ST_POINT == point) {
                        if (st & ST_PASS_LIVE != 0) returned += uint256(b.passLine) * FLIP;
                        st &= ~(ST_DONT_LIVE | ST_POINT_MASK);
                    }
                }
            }
            // Seven-out is the loop's only early exit. Accumulate the cursor once per hand rather
            // than once per roll.
            logPos += st & ST_SEVEN_OUT == 0 ? _MAX_ROLLS : i + 1;

            // ELIGIBLE PROFIT, banked before the refunds below can dilute it. What is in
            // `returned` at this point is everything the dice PAID: the light side's winnings,
            // which never include their own stake, and a winning dark wager's 3:4 once its own
            // stake is taken back out. The roll-cap refunds are principal to the last wei and are
            // added after, so a truncated hand can never have its stake boosted.
            uint256 elig = returned - (st & ST_DONT_WON == 0 ? 0 : uint256(b.dontPass) * FLIP);

            if (st & ST_SEVEN_OUT == 0) {
                if (st & ST_PASS_LIVE != 0) returned += uint256(b.passLine) * FLIP;
                if (st & (1 << 4) != 0) returned += uint256(b.place4) * FLIP;
                if (st & (1 << 5) != 0) returned += uint256(b.place5) * FLIP;
                if (st & (1 << 6) != 0) returned += uint256(b.place6) * FLIP;
                if (st & (1 << 8) != 0) returned += uint256(b.place8) * FLIP;
                if (st & (1 << 9) != 0) returned += uint256(b.place9) * FLIP;
                if (st & (1 << 10) != 0) returned += uint256(b.place10) * FLIP;
                if (st & ST_HARD4_LIVE != 0) returned += uint256(b.hard4) * FLIP;
                if (st & ST_HARD8_LIVE != 0) returned += uint256(b.hard8) * FLIP;
                // A hand cut off by the roll cap owes an UNDECIDED dark wager its stake back, and
                // owes a decided one nothing: the liveness bit is exactly that distinction.
                if (st & ST_DONT_LIVE != 0) returned += uint256(b.dontPass) * FLIP;
            }

            // ONE RETURN WORD, three fields (see the layout note by `_HR_LOG_SHIFT`): the amount
            // in bits 0..111, the log cursor in 112..143, the eligible profit in 144..255.
            packed = returned | (logPos << _HR_LOG_SHIFT) | (elig << _HR_PROFIT_SHIFT);
        }
    }

    function _settlementState(Bets memory b) private pure returns (uint256 st) {
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
    }

    /// @dev Place/hardway specialization selected when the board has no pass line.
    function _runSideSettlement(Bets memory b, bytes32 seed, uint256 logPos, uint256 st, uint256[13] memory wins)
        private
        pure
        returns (uint256 packed)
    {
        uint256 returned;

        unchecked {
            uint256 i;
            for (; i < _MAX_ROLLS; ++i) {
                uint256 w;
                assembly ("memory-safe") {
                    mstore(0x00, seed)
                    mstore(0x20, i)
                    w := keccak256(0x00, 0x40)
                }
                uint256 t = (uint256(uint32(w)) % 6) + (uint256(uint32(w >> 32)) % 6) + 2;

                uint256 point = st & ST_POINT_MASK;
                if (point == 0) {
                    if (_POINT_TOTALS_MASK & (1 << t) != 0) {
                        st |= t << ST_POINT;
                    } else if (st & ST_DONT_LIVE != 0) {
                        // A come-out that is not a point is the dark side's whole decision: 2 or 3
                        // wins, 7 or 11 loses, and the barred 12 leaves the wager up.
                        if (t == 2 || t == 3) {
                            returned += wins[0];
                            st = (st | ST_DONT_WON) & ~ST_DONT_LIVE;
                        } else if (t != 12) {
                            st &= ~ST_DONT_LIVE;
                        }
                    }
                } else {
                    if (t == 7) {
                        if (st & ST_DONT_LIVE != 0) {
                            returned += wins[0];
                            st |= ST_DONT_WON;
                        }
                        st |= ST_SEVEN_OUT;
                        break;
                    }
                    if (st & (1 << t) != 0) {
                        assembly ("memory-safe") {
                            returned := add(returned, mload(add(wins, shl(5, t))))
                        }
                    }
                    if (st & (ST_HARD4_LIVE | ST_HARD8_LIVE) != 0) {
                        if (t == 4 && st & ST_HARD4_LIVE != 0) {
                            if (uint32(w) % 6 == uint32(w >> 32) % 6) {
                                returned += uint256(b.hard4) * (7 * FLIP);
                            }
                            else st &= ~ST_HARD4_LIVE;
                        } else if (t == 8 && st & ST_HARD8_LIVE != 0) {
                            if (uint32(w) % 6 == uint32(w >> 32) % 6) {
                                returned += uint256(b.hard8) * (9 * FLIP);
                            }
                            else st &= ~ST_HARD8_LIVE;
                        }
                    }
                    if (t << ST_POINT == point) st &= ~(ST_DONT_LIVE | ST_POINT_MASK);
                }
            }
            logPos += st & ST_SEVEN_OUT == 0 ? _MAX_ROLLS : i + 1;

            uint256 elig = returned - (st & ST_DONT_WON == 0 ? 0 : uint256(b.dontPass) * FLIP);

            if (st & ST_SEVEN_OUT == 0) {
                if (st & (1 << 4) != 0) returned += uint256(b.place4) * FLIP;
                if (st & (1 << 5) != 0) returned += uint256(b.place5) * FLIP;
                if (st & (1 << 6) != 0) returned += uint256(b.place6) * FLIP;
                if (st & (1 << 8) != 0) returned += uint256(b.place8) * FLIP;
                if (st & (1 << 9) != 0) returned += uint256(b.place9) * FLIP;
                if (st & (1 << 10) != 0) returned += uint256(b.place10) * FLIP;
                if (st & ST_HARD4_LIVE != 0) returned += uint256(b.hard4) * FLIP;
                if (st & ST_HARD8_LIVE != 0) returned += uint256(b.hard8) * FLIP;
                if (st & ST_DONT_LIVE != 0) returned += uint256(b.dontPass) * FLIP;
            }
            packed = returned | (logPos << _HR_LOG_SHIFT) | (elig << _HR_PROFIT_SHIFT);
        }
    }

    /// @dev THE ESCALATOR: the mandatory wager for shooter `hand`, in base-board units — doubling
    ///      every `_ESC_HANDS` shooters, capped at `_ESC_CAP`. Surviving the table means
    ///      outracing this: a slip cannot flat-grind forever, because the floor under its wager
    ///      keeps rising.
    ///
    ///      The shift is never taken past 31. The ceiling fits a uint32, so a 32nd doubling has
    ///      already passed it — which makes the branch exact rather than defensive, and keeps a
    ///      wide hand cap from shifting a literal off the end of the word.
    function _escOf(uint256 hand) internal pure returns (uint256 esc) {
        unchecked {
            uint256 shift = hand / _ESC_HANDS;
            esc = shift < 32 ? 1 << shift : _ESC_CAP;
        }
    }

    /// @dev The fair, committed second-chance coin for round `n`. Salting by the round keeps each
    ///      affordability decision on its own coin, and salting by the OWNER keeps one player's
    ///      coin off every other player's: the shooter is the table's, but a bust is not, so two
    ///      seats reaching the same round no longer live or die together. Both inputs were fixed
    ///      before the word existed — the seed is the table's and the owner is who placed the slip
    ///      — so settlement order cannot change the result. It is the same salt the board scatter
    ///      already uses, so a player's whole run is decorrelated from the field by one key.
    function _survived(bytes32 seed, uint256 n, address player) internal pure returns (bool) {
        return _playerDraw(SURVIVAL_TAG, seed, n, player) & 1 == 1;
    }

    /// @dev Whether shooter `n` carries THIS player's profit boost — `chance` shooters in a
    ///      hundred do. Its
    ///      own domain, so it moves neither the dice nor the survival coin and cannot be read off
    ///      either: the tag separates it from every other draw the same seed answers, and the
    ///      player separates one seat's schedule from the next's over the shared shooters. Both
    ///      inputs were fixed before the seed existed — the word is the table's and the player is
    ///      who placed the slip — so nobody could know the schedule while entry was still open,
    ///      and settlement order cannot change it afterwards.
    function _boostedShooter(bytes32 seed, uint256 n, address player, uint256 chance) internal pure returns (bool) {
        return _playerDraw(SHOOTER_BOOST_TAG, seed, n, player) % 100 < chance;
    }

    /// @dev Exact `abi.encode(tag, seed, n, player)` digest without allocating or advancing the
    ///      free-memory pointer. Both caller domains use the same four-word preimage layout.
    function _playerDraw(uint256 tag, bytes32 seed, uint256 n, address player) private pure returns (uint256 draw) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, tag)
            mstore(add(ptr, 0x20), seed)
            mstore(add(ptr, 0x40), n)
            mstore(add(ptr, 0x60), player)
            draw := keccak256(ptr, 0x80)
        }
    }
}
