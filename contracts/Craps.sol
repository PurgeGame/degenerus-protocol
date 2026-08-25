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
///         This contract holds no funds and has no state. An escrow wrapper supplies a seed that
///         was unknown when the bets were locked (a VRF word) and pays out the net.
///
/// @dev THE BOUNDED-LOSS INVARIANT
///
///      Every bet in this resolver loses at most its own stake, and the sum of stakes is known at
///      bet time. That is not an accident of the payout tables — it is why this exact bet set was
///      chosen:
///
///        * Everything "pays and stays": a win credits winnings only, the stake remains at risk,
///          and the stake is lost when the bet dies. The pass line pays every natural and every
///          point made until its first loss — a come-out craps or the seven-out. The odds behind
///          it ride each point established while the line lives, at true odds every cycle, and die
///          with the shooter. Place bets and hardways can pay many times but die once, on the 7.
///
///      So `stakeFor(b)` is the player's exact maximum loss for one hand and no upfront liability
///      formula is needed. Winnings are unbounded above (a long hand can hit a place number many
///      times), which is the house's problem, not the escrow's.
///
///      What is missing and why:
///
///        * Come and Don't Come are structurally impossible here, not merely inconvenient. A Come
///          bet IS a bet made during a point phase; there is no such thing as placing one before
///          the come-out. Supporting them means accepting a pre-declared betting policy, which
///          turns this resolver into a strategy interpreter.
///        * Field and the one-roll propositions resolve on a single roll, so riding them to the end
///          of a hand means re-arming them every roll. That is what actually breaks bounded loss,
///          and it is why they are out while odds are in.
///
/// @dev HOUSE RULES PINNED HERE (there is no canonical craps; these are the choices)
///
///        * The board is the basics and nothing else: the pass line with true odds, all six place
///          numbers, and the two iconic hardways — the hard four and the hard eight. Everything
///          else that only bled (Big 6/8, the other hardways), every side lottery (Fire,
///          All/Tall/Small), and the whole dark side (Don't Pass, lay odds — the grinder's lane,
///          not this table's crowd) has been cut. In this ride-to-the-seven-out model the pass
///          line runs 2.79% (still the textbook 1.41% per decision), the good places 2.78-6.67%,
///          place 4/10 at 9:5 run 10%, and the hardways are the indulgences: 10% on the eight,
///          12.5% on the four.
///        * Stakes are WHOLE FLIP, uint24 per leg: the type itself is the table maximum of
///          16,777,215 FLIP a leg. All payout math still runs in wei internally, so fractions pay
///          exactly as they always did. One consequence worth loving: the entire bet slip packs
///          into a single storage slot.
///        * Place bets and the hardways are OFF on the come-out, the table default, and there is no
///          toggle. Working them changes no house edge whatsoever — every roll is i.i.d. — so the
///          switch bought a player nothing but a decision to get wrong.
///        * Payouts are floored. Stakes in multiples of 30 FLIP make every payout exact.
contract Craps {
    // ---------------------------------------------------------------------------------------
    // Bet legs
    // ---------------------------------------------------------------------------------------

    /// @dev Place indexes, ordered by dice total: 4, 5, 6, 8, 9, 10.
    uint256 internal constant PLACE_4 = 0;
    uint256 internal constant PLACE_5 = 1;
    uint256 internal constant PLACE_6 = 2;
    uint256 internal constant PLACE_8 = 3;
    uint256 internal constant PLACE_9 = 4;
    uint256 internal constant PLACE_10 = 5;

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
    uint256 public constant MAX_ROLLS = 512;

    /// @notice Total dice rolls a bet slip may consume, judged between shooters.
    /// @dev This is what makes a slip settlement's gas a GUARANTEE instead of a probability. The
    ///      shooter cap alone leaves a bounded-but-huge worst case (cap x MAX_ROLLS rolls); with
    ///      this budget the hard ceiling is `SLIP_ROLL_BUDGET - 1 + MAX_ROLLS` rolls — under two
    ///      million gas in the measured settlement engine — however the dice fall. A 256-shooter
    ///      slip averages ~2,200 rolls, so
    ///      reaching 4,096 needs the average hand nearly doubled across the whole run: organically
    ///      unreachable, and hitting it anyway is harmless — the slip stops as `Cap` between
    ///      shooters with the bankroll intact. Every shooter still settles whole; the budget never
    ///      cuts a hand mid-roll.
    uint256 public constant SLIP_ROLL_BUDGET = 4096;

    /// @notice Shooters between each mandatory doubling of a slip's base wager.
    /// @dev The escalator: rounds 0..4 wager 1x the board, 5..9 wager 2x, 10..14 wager 4x, and so
    ///      on, capped at the 65,535-unit table limit. A slip that cannot cover the doubled wager
    ///      busts between shooters with its remainder intact. Deterministic in the hand ordinal, so
    ///      the whole run is still recomputable from the base board and the seed alone.
    uint256 public constant ESC_HANDS = 5;

    /// @notice Domain tag for the table's survival coin — the double-or-nothing consulted both
    ///         mid-run as a second chance and once at the end of a run. Tagged so its preimage can
    ///         never collide with the dice stream (`keccak(seed, i)`, untagged).
    uint256 internal constant SURVIVAL_TAG = 0x537572766976616c; // "Survival"

    /// @dev The six totals that can be a point.
    uint256 internal constant _POINT_TOTALS_MASK = (1 << 4) | (1 << 5) | (1 << 6) | (1 << 8) | (1 << 9) | (1 << 10);

    /// @dev The roll loop's entire state machine, packed into one stack word so it never leaves
    ///      the stack. Field layout, indexed by dice total `t` where a total is the key:
    ///        bits  0..15  live place-bet totals (bit t; only 4, 5, 6, 8, 9, 10 are ever set)
    ///        bits 32..35  the point (0 = come-out)
    ///        bits 36..39  the point the pass odds are riding (0 = never armed)
    ///        bit  40      pass line live          bit 41  pass odds unresolved
    ///        bit  42      hard eight live         bit 43  seven-out happened
    ///        bit  44      hard four live
    uint256 private constant ST_POINT = 32;
    uint256 private constant ST_PASS_PT = 36;
    uint256 private constant ST_PLACE_ANY = 0xFFFF;
    uint256 private constant ST_POINT_MASK = 0xF << 32;
    uint256 private constant ST_PASS_PT_MASK = 0xF << 36;
    uint256 private constant ST_PASS_LIVE = 1 << 40;
    uint256 private constant ST_PASS_ODDS_LIVE = 1 << 41;
    uint256 private constant ST_HARD8_LIVE = 1 << 42;
    uint256 private constant ST_SEVEN_OUT = 1 << 43;
    uint256 private constant ST_HARD4_LIVE = 1 << 44;

    // ---------------------------------------------------------------------------------------
    // Types
    // ---------------------------------------------------------------------------------------

    /// @notice Everything the player puts down before the come-out roll. Any leg may be zero.
    ///         All stakes are WHOLE FLIP; the uint24 fields make 16,777,215 FLIP the table max per
    ///         leg, and the whole slip fits one storage slot.
    /// @param passLine   Pass Line: every natural and every point made pays 1:1 and the line stays
    ///                   up; dies on its first come-out craps or the seven-out.
    /// @param place4     Place 4: pays 9:5 on every 4 and stays up; the stake is lost on the 7.
    /// @param place5     Place 5: 7:5, same shape.
    /// @param place6     Place 6: 7:6, same shape.
    /// @param place8     Place 8: 7:6, same shape.
    /// @param place9     Place 9: 7:5, same shape.
    /// @param place10    Place 10: 9:5, same shape.
    /// @param hard4      The hard four: 2-2 pays 7:1 and stays up; dies on an easy 4 or the 7.
    /// @param hard8      The hard eight: 4-4 pays 9:1 and stays up; dies on an easy 8 or the 7.
    /// @param passOddsMult   Odds behind the pass line, as a multiple of `passLine`. True odds,
    ///                       zero edge — 2:1 on 4/10, 3:2 on 5/9, 6:5 on 6/8 — riding each point
    ///                       established while the line lives, winnings credited per point made;
    ///                       the stake dies on a seven-out mid-point and is refunded in full if
    ///                       the hand ends with the odds not riding.
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
        uint16 passOddsMult;
    }

    /// @notice Why a bet slip stopped playing.
    enum SlipStop {
        Bust, // fell below half a round, or lost the mid-run second-chance flip
        Goal, // the bankroll reached the chosen target
        Cap // the shooter cap arrived before either
    }

    /// @notice The full account of one bet-slip run: the same wager repeated shooter after shooter
    ///         out of a bankroll, until it cannot cover another round, reaches the goal, or hits
    ///         the cap.
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
    /// @param rollLog      The run's dice, one byte per roll — die one in the high nibble, die two
    ///                     in the low — with a 0x00 byte closing each hand. Recorded during the
    ///                     same roll loop that settles, so it can never disagree with the money.
    struct SlipResult {
        uint256 bankrollIn;
        uint256 bankrollOut;
        uint256 handsPlayed;
        uint256 unitsPlayed;
        uint256 totalRolls;
        SlipStop stop;
        bytes rollLog;
    }

    // ---------------------------------------------------------------------------------------
    // Entry points
    // ---------------------------------------------------------------------------------------

    /// @dev The slip engine: the same wager repeated shooter after shooter out of a bankroll. It
    ///      returns only what a settlement can observe — the bankroll, the wager units, and the
    ///      packed dice receipt — because that is all the paying path needs. Per-leg books and
    ///      per-hand ledgers have no consumer here and are not computed.
    ///
    ///      Stop conditions are judged BETWEEN shooters, in this order: goal first (so a run that
    ///      is simultaneously at goal and out of the next stake counts as a win), then the cap, then
    ///      affordability. A round short of even half its escalating wager busts outright; one that
    ///      can cover between half and all of it takes a single committed double-or-nothing on the
    ///      whole bankroll — surviving doubles it (enough to cover the round) and plays on, losing
    ///      ends the slip with nothing. Each played round escrows its wager — the base board times
    ///      the escalating mandatory multiplier (see `ESC_HANDS`) — out of the bankroll, plays one
    ///      hand, and credits back whatever it returned; the bounded-loss invariant is exactly what
    ///      makes the escrow subtraction safe unchecked after the affordability check. A busted
    ///      bankroll keeps its remainder.
    ///
    ///      Because every payout is linear in the stakes, a q-unit round is EXACTLY q times the
    ///      base hand: the engine rolls the base board once and scales, which is what keeps the
    ///      dice log that of the base board however far the escalator has climbed.
    ///
    ///      Loop state note: `cur` packs the hand counter (bits 0..15), the round's mandatory
    ///      multiplier (16..31), and the roll-log cursor (32+) into one stack slot — via-IR runs
    ///      out of stack here with them separate.
    function _settleSlip(Bets memory b, bytes32 seed, uint256 bankroll, uint256 goal, uint256 cap, uint256 rollBudget)
        internal
        pure
        returns (SlipResult memory r)
    {
        uint256 stake = stakeFor(b);

        r.bankrollIn = bankroll;
        bytes memory log;
        unchecked {
            log = new bytes(rollBudget + MAX_ROLLS + cap);
        }
        uint256 initialState = _settlementState(b);
        uint256 unitsPlayed;
        uint256[6] memory placeWins;
        unchecked {
            if (initialState & ST_PLACE_ANY != 0) {
                placeWins[0] = (uint256(b.place4) * (9 * FLIP)) / 5;
                placeWins[1] = (uint256(b.place5) * (7 * FLIP)) / 5;
                placeWins[2] = (uint256(b.place6) * (7 * FLIP)) / 6;
                placeWins[3] = (uint256(b.place8) * (7 * FLIP)) / 6;
                placeWins[4] = (uint256(b.place9) * (7 * FLIP)) / 5;
                placeWins[5] = (uint256(b.place10) * (9 * FLIP)) / 5;
            } else if (initialState & (ST_HARD4_LIVE | ST_HARD8_LIVE) == 0) {
                placeWins[0] = uint256(b.passLine) * FLIP;
                placeWins[1] = placeWins[0] * b.passOddsMult;
            }
        }

        unchecked {
            uint256 cur;
            while (true) {
                if (goal != 0 && bankroll >= goal) {
                    r.stop = SlipStop.Goal;
                    break;
                }
                // Goal and the hard caps stop cleanly; only a run that is going to continue can be
                // asked to take a second chance, so both are settled before affordability.
                if (cur & 0xFFFF == cap || (cur >> 32) - (cur & 0xFFFF) >= rollBudget) {
                    r.stop = SlipStop.Cap;
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
                        // the same double-or-nothing that would decide a run of this length at the
                        // end — rides the whole bankroll. Surviving doubles it, enough to cover
                        // exactly this round, and play continues; losing ends the slip with nothing.
                        if (_survived(seed, cur & 0xFFFF)) {
                            bankroll += bankroll;
                        } else {
                            bankroll = 0;
                            r.stop = SlipStop.Bust;
                            break;
                        }
                    }
                    cur = (cur & ~uint256(0xFFFF0000)) | (q << 16);
                }

                bankroll -= ((cur >> 16) & 0xFFFF) * stake;

                uint256 handOut =
                    _runSettlement(b, handSeed(seed, cur & 0xFFFF), log, cur >> 32, initialState, placeWins);
                bankroll += ((cur >> 16) & 0xFFFF) * uint128(handOut);
                unitsPlayed += (cur >> 16) & 0xFFFF;
                cur = (((handOut >> 128) + 1) << 32) | (cur & 0xFFFF0000) | ((cur & 0xFFFF) + 1);
            }

            r.handsPlayed = cur & 0xFFFF;
            r.bankrollOut = bankroll;
            r.unitsPlayed = unitsPlayed;
            r.totalRolls = (cur >> 32) - (cur & 0xFFFF);
            uint256 pos = cur >> 32;
            assembly ("memory-safe") {
                mstore(log, pos)
            }
            r.rollLog = log;
        }
    }

    /// @notice Total staked across every leg of `b` — one hand's charge.
    /// @dev What an escrow must collect up front, and the exact ceiling on what the player can
    ///      lose. Multiply by the hand count for a session.
    function stakeFor(Bets memory b) public pure returns (uint256 total) {
        // Stakes are whole FLIP; the charge is wei. Bounded far below 2^256: nine uint24 legs
        // plus the odds leg at uint24 x uint16 sum under 2^42 FLIP.
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
                        + uint256(b.passLine)
                        * b.passOddsMult) * FLIP;
        }
    }

    /// @notice The expected loss of one hand of `b`, in wei — the theo a casino comps from.
    /// @dev Exact per-leg rationals for the ride-to-the-seven-out model this table plays:
    ///      pass 7/251, place 4/10 1/10, place 5/9 1/15, place 6/8 1/36, the hard four 1/8, the
    ///      hard eight 1/10, and odds exactly zero. The MC oracle pins every one of these numbers
    ///      against the resolver; flooring loses at most a few wei.
    function theoFor(Bets memory b) public pure returns (uint256) {
        unchecked {
            return (uint256(b.passLine) * FLIP * 7) / 251 + (uint256(b.place4) * FLIP) / 10 + (uint256(b.place5) * FLIP)
                / 15 + (uint256(b.place6) * FLIP) / 36 + (uint256(b.place8) * FLIP) / 36 + (uint256(b.place9) * FLIP)
                / 15 + (uint256(b.place10) * FLIP) / 10 + (uint256(b.hard4) * FLIP) / 8 + (uint256(b.hard8) * FLIP) / 10;
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
    function _runSettlement(
        Bets memory b,
        bytes32 seed,
        bytes memory rollLog,
        uint256 logPos,
        uint256 st,
        uint256[6] memory placeWins
    ) private pure returns (uint256 packed) {
        uint256 returned;
        uint256 logPtr;
        assembly ("memory-safe") {
            logPtr := add(rollLog, 0x20)
        }

        unchecked {
            // A line-only board should not pay two dead class checks on every point roll. Select
            // its smaller machine once per shooter; dice and line/odds semantics remain identical.
            if (st & (ST_PLACE_ANY | ST_HARD4_LIVE | ST_HARD8_LIVE) == 0) {
                return _runLineSettlement(seed, rollLog, logPos, st, placeWins);
            }
            if (st & ST_PASS_LIVE == 0) {
                return _runSideSettlement(b, seed, rollLog, logPos, st, placeWins);
            }

            uint256 i;
            for (; i < MAX_ROLLS; ++i) {
                uint256 w;
                assembly ("memory-safe") {
                    mstore(0x00, seed)
                    mstore(0x20, i)
                    w := keccak256(0x00, 0x40)
                }
                uint256 d1 = (uint256(uint32(w)) % 6) + 1;
                uint256 d2 = (uint256(uint32(w >> 32)) % 6) + 1;
                uint256 t = d1 + d2;
                bool comeOut = (st & ST_POINT_MASK) == 0;
                assembly ("memory-safe") {
                    mstore8(add(logPtr, logPos), or(shl(4, d1), d2))
                }
                ++logPos;

                // A point-phase seven ends the hand before any bet can pay. Only the odds-refund
                // bit matters after the break; every other live stake is swept by the seven-out.
                if (t == 7 && !comeOut) {
                    if (st & ST_PASS_LIVE != 0) st &= ~ST_PASS_ODDS_LIVE;
                    st |= ST_SEVEN_OUT;
                    break;
                }

                if (!comeOut) {
                    if (st & ST_PLACE_ANY != 0 && st & (1 << t) != 0) {
                        returned += _cachedPlaceWin(placeWins, t);
                    }

                    if (st & (ST_HARD4_LIVE | ST_HARD8_LIVE) != 0) {
                        if (t == 4 && st & ST_HARD4_LIVE != 0) {
                            if (d1 == d2) {
                                returned += uint256(b.hard4) * (7 * FLIP);
                            } else {
                                st &= ~ST_HARD4_LIVE;
                            }
                        } else if (t == 8 && st & ST_HARD8_LIVE != 0) {
                            if (d1 == d2) {
                                returned += uint256(b.hard8) * (9 * FLIP);
                            } else {
                                st &= ~ST_HARD8_LIVE;
                            }
                        }
                    }
                }

                if (comeOut) {
                    if (t == 7 || t == 11) {
                        if (st & ST_PASS_LIVE != 0) returned += uint256(b.passLine) * FLIP;
                    } else if (t == 2 || t == 3 || t == 12) {
                        st &= ~ST_PASS_LIVE;
                    } else {
                        st |= t << ST_POINT;
                        if (st & ST_PASS_LIVE != 0) st |= t << ST_PASS_PT;
                    }
                } else if (t == (st >> ST_POINT) & 0xF) {
                    if (st & ST_PASS_LIVE != 0) returned += uint256(b.passLine) * FLIP;
                    if (st & ST_PASS_ODDS_LIVE != 0 && (st >> ST_PASS_PT) & 0xF == t) {
                        uint256 po = uint256(b.passLine) * b.passOddsMult * FLIP;
                        returned += _oddsWin(po, t);
                    }
                    st &= ~(ST_POINT_MASK | ST_PASS_PT_MASK);
                }
            }

            if (st & ST_PASS_ODDS_LIVE != 0) {
                returned += uint256(b.passLine) * b.passOddsMult * FLIP;
            }

            if (st & ST_SEVEN_OUT == 0) {
                if (st & ST_PASS_LIVE != 0) returned += uint256(b.passLine) * FLIP;
                for (uint256 k = 0; k < 6; ++k) {
                    if (st & (1 << _placeTotal(k)) != 0) returned += _placeWei(b, k);
                }
                if (st & ST_HARD4_LIVE != 0) returned += uint256(b.hard4) * FLIP;
                if (st & ST_HARD8_LIVE != 0) returned += uint256(b.hard8) * FLIP;
            }

            // Even 512 consecutive maximum-odds wins stay below 2^112. Pack the log cursor above
            // bit 127 so the hot caller carries one return word.
            packed = returned | (logPos << 128);
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
        if (b.passLine != 0) {
            st |= ST_PASS_LIVE;
            if (b.passOddsMult != 0) st |= ST_PASS_ODDS_LIVE;
        }
    }

    /// @dev Pass-line/odds specialization selected by `_runSettlement` when no side bet is live.
    function _runLineSettlement(bytes32 seed, bytes memory rollLog, uint256 logPos, uint256 st, uint256[6] memory wins)
        private
        pure
        returns (uint256 packed)
    {
        uint256 returned;
        uint256 logPtr;
        assembly ("memory-safe") {
            logPtr := add(rollLog, 0x20)
        }

        unchecked {
            uint256 i;
            for (; i < MAX_ROLLS; ++i) {
                uint256 w;
                assembly ("memory-safe") {
                    mstore(0x00, seed)
                    mstore(0x20, i)
                    w := keccak256(0x00, 0x40)
                }
                uint256 d1 = (uint256(uint32(w)) % 6) + 1;
                uint256 d2 = (uint256(uint32(w >> 32)) % 6) + 1;
                uint256 t = d1 + d2;
                assembly ("memory-safe") {
                    mstore8(add(logPtr, logPos), or(shl(4, d1), d2))
                }
                ++logPos;

                uint256 point = (st >> ST_POINT) & 0xF;
                if (point == 0) {
                    if (t == 7 || t == 11) {
                        if (st & ST_PASS_LIVE != 0) returned += wins[0];
                    } else if (t == 2 || t == 3 || t == 12) {
                        st &= ~ST_PASS_LIVE;
                    } else {
                        st |= t << ST_POINT;
                        if (st & ST_PASS_LIVE != 0) st |= t << ST_PASS_PT;
                    }
                } else if (t == 7) {
                    if (st & ST_PASS_LIVE != 0) st &= ~ST_PASS_ODDS_LIVE;
                    st |= ST_SEVEN_OUT;
                    break;
                } else if (t == point) {
                    if (st & ST_PASS_LIVE != 0) returned += wins[0];
                    if (st & ST_PASS_ODDS_LIVE != 0 && (st >> ST_PASS_PT) & 0xF == t) {
                        returned += _oddsWin(wins[1], t);
                    }
                    st &= ~(ST_POINT_MASK | ST_PASS_PT_MASK);
                }
            }

            if (st & ST_PASS_ODDS_LIVE != 0) {
                returned += wins[1];
            }
            if (st & ST_SEVEN_OUT == 0 && st & ST_PASS_LIVE != 0) {
                returned += wins[0];
            }
            packed = returned | (logPos << 128);
        }
    }

    /// @dev Place/hardway specialization selected when the board has no pass line or odds.
    function _runSideSettlement(
        Bets memory b,
        bytes32 seed,
        bytes memory rollLog,
        uint256 logPos,
        uint256 st,
        uint256[6] memory placeWins
    ) private pure returns (uint256 packed) {
        uint256 returned;
        uint256 logPtr;
        assembly ("memory-safe") {
            logPtr := add(rollLog, 0x20)
        }

        unchecked {
            uint256 i;
            for (; i < MAX_ROLLS; ++i) {
                uint256 w;
                assembly ("memory-safe") {
                    mstore(0x00, seed)
                    mstore(0x20, i)
                    w := keccak256(0x00, 0x40)
                }
                uint256 d1 = (uint256(uint32(w)) % 6) + 1;
                uint256 d2 = (uint256(uint32(w >> 32)) % 6) + 1;
                uint256 t = d1 + d2;
                assembly ("memory-safe") {
                    mstore8(add(logPtr, logPos), or(shl(4, d1), d2))
                }
                ++logPos;

                uint256 point = (st >> ST_POINT) & 0xF;
                if (t == 7 && point != 0) {
                    st |= ST_SEVEN_OUT;
                    break;
                }

                if (point != 0) {
                    if (st & ST_PLACE_ANY != 0 && st & (1 << t) != 0) {
                        returned += _cachedPlaceWin(placeWins, t);
                    }
                    if (st & (ST_HARD4_LIVE | ST_HARD8_LIVE) != 0) {
                        if (t == 4 && st & ST_HARD4_LIVE != 0) {
                            if (d1 == d2) {
                                returned += uint256(b.hard4) * (7 * FLIP);
                            } else {
                                st &= ~ST_HARD4_LIVE;
                            }
                        } else if (t == 8 && st & ST_HARD8_LIVE != 0) {
                            if (d1 == d2) {
                                returned += uint256(b.hard8) * (9 * FLIP);
                            } else {
                                st &= ~ST_HARD8_LIVE;
                            }
                        }
                    }
                }

                if (point == 0) {
                    if (_POINT_TOTALS_MASK & (1 << t) != 0) st |= t << ST_POINT;
                } else if (t == point) {
                    st &= ~ST_POINT_MASK;
                }
            }

            if (st & ST_SEVEN_OUT == 0) {
                for (uint256 k = 0; k < 6; ++k) {
                    if (st & (1 << _placeTotal(k)) != 0) returned += _placeWei(b, k);
                }
                if (st & ST_HARD4_LIVE != 0) returned += uint256(b.hard4) * FLIP;
                if (st & ST_HARD8_LIVE != 0) returned += uint256(b.hard8) * FLIP;
            }
            packed = returned | (logPos << 128);
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

    /// @dev The table's survival coin at run-length `n`: a fair, committed double-or-nothing keyed
    ///      on the table seed. It is consulted in two places and is the SAME coin in both — as the
    ///      mid-run second chance for the round at ordinal `n` (see `_settleSlip`), and as the
    ///      end-of-run flip for a run that stopped after `n` shooters (see `FlipCraps`).
    ///
    ///      SALTED BY THE RUN LENGTH `n`. One coin per table (n dropped) would let the first player
    ///      to settle a short run publish the deciding flip for everyone still holding a long one,
    ///      since a table's word is public the moment it lands. Keying on `n` gives each length its
    ///      own coin, so a run's DECIDING flip — the one at its own exit round — is never published
    ///      by settling a run of a different length. (A shorter run can reveal a coin a longer one
    ///      later rides as a mid-hand second chance, but that is informational only: everything is
    ///      committed before the word exists, so no foreknowledge moves a payout.) It costs the
    ///      manipulation argument nothing — `n` is a pure function of the committed board, bankroll
    ///      and goal against a word that did not exist yet, so no arrangement of `betIds[]` and no
    ///      choice made after the dice are public can move it. Two identical slips flip identically
    ///      and share it.
    function _survived(bytes32 seed, uint256 n) internal pure returns (bool) {
        return uint256(keccak256(abi.encode(SURVIVAL_TAG, seed, n))) & 1 == 1;
    }

    // ---------------------------------------------------------------------------------------
    // Tables
    // ---------------------------------------------------------------------------------------

    /// @dev Place index (0..5) -> dice total: 0,1,2 -> 4,5,6 and 3,4,5 -> 8,9,10.
    function _placeTotal(uint256 idx) private pure returns (uint256) {
        return idx < 3 ? idx + 4 : idx + 5;
    }

    /// @dev The stake on place index `idx`, in wei. The struct's named fields are what buy the
    ///      one-slot packing; this is the array view the resolver's index math wants.
    function _placeWei(Bets memory b, uint256 idx) private pure returns (uint256) {
        unchecked {
            if (idx == PLACE_4) return uint256(b.place4) * FLIP;
            if (idx == PLACE_5) return uint256(b.place5) * FLIP;
            if (idx == PLACE_6) return uint256(b.place6) * FLIP;
            if (idx == PLACE_8) return uint256(b.place8) * FLIP;
            if (idx == PLACE_9) return uint256(b.place9) * FLIP;
            return uint256(b.place10) * FLIP;
        }
    }

    function _cachedPlaceWin(uint256[6] memory wins, uint256 t) private pure returns (uint256 amount) {
        unchecked {
            uint256 idx = t < 7 ? t - 4 : t - 5;
            assembly ("memory-safe") {
                amount := mload(add(wins, shl(5, idx)))
            }
        }
    }

    /// @dev True-odds winnings on a point. These are the real
    ///      probabilities: 4 and 10 come 3 ways against the seven's 6, so 2:1; 5 and 9 come 4 ways,
    ///      so 3:2; 6 and 8 come 5 ways, so 6:5. Nothing is shaded, which is what makes odds the
    ///      only zero-edge bet on the table and a sharp test oracle.
    function _oddsWin(uint256 stake, uint256 pt) private pure returns (uint256) {
        unchecked {
            if (pt == 4 || pt == 10) return stake * 2;
            if (pt == 5 || pt == 9) return (stake * 3) / 2;
            return (stake * 6) / 5;
        }
    }
}
