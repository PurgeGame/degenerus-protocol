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
///      So `stakeFor(b)` is the player's exact maximum loss for one hand and no upfront liability
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
    // ---------------------------------------------------------------------------------------
    // Bet legs
    // ---------------------------------------------------------------------------------------

    /// @dev Place indexes, ordered by dice total: 4, 5, 6, 8, 9, 10.
    uint256 internal constant PLACE_4 = 0;
    uint256 internal constant PLACE_5 = 1;
    uint256 internal constant PLACE_6 = 2;
    uint256 internal constant PLACE_8 = 3;
    uint256 internal constant PLACE_9 = 4;

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
    ///      this budget the hard ceiling is `_SLIP_ROLL_BUDGET - 1 + _MAX_ROLLS` rolls — under two
    ///      million gas in the measured settlement engine — however the dice fall. Even a
    ///      hypothetical 256-shooter slip averages ~2,200 rolls; legal terms stop much earlier,
    ///      making 4,096 effectively unreachable. Hitting it is an ordinary bust between shooters;
    ///      every shooter still settles whole, and the budget never cuts a hand mid-roll.
    uint256 internal constant _SLIP_ROLL_BUDGET = 4096;

    /// @notice Shooters between each mandatory doubling of a slip's base wager.
    /// @dev The escalator: rounds 0..4 wager 1x the board, 5..9 wager 2x, 10..14 wager 4x, and so
    ///      on, capped at the 65,535-unit table limit. A slip that cannot cover the doubled wager
    ///      busts between shooters with its remainder intact. Deterministic in the hand ordinal, so
    ///      the whole run is still recomputable from the base board and the seed alone.
    uint256 internal constant _ESC_HANDS = 5;

    /// @notice Domain tag for the mid-run second-chance coin, separated from the dice stream.
    uint256 internal constant SURVIVAL_TAG = 0x537572766976616c; // "Survival"

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
    /// @param handsPlayed  Shooters actually played.
    /// @param unitsPlayed  Base-board units wagered across the run — the sum of each round's
    ///                     escalating mandatory multiplier. Only equals `handsPlayed` before the
    ///                     escalator first doubles.
    /// @param totalRolls   Dice rolls across the run.
    /// @param stop         Why it ended.
    struct SlipResult {
        uint256 bankrollIn;
        uint256 bankrollOut;
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
    ///      Because every payout is linear in the stakes, a q-unit round is EXACTLY q times the
    ///      base hand: the engine rolls the base board once and scales, which is what keeps the
    ///      dice log that of the base board however far the escalator has climbed.
    ///
    ///      Loop state note: `cur` packs the hand counter (bits 0..15), the round's mandatory
    ///      multiplier (16..31), and the ROLL counter (32+) into one stack slot — via-IR runs
    ///      out of stack here with them separate.
    function _settleSlip(
        Bets memory b,
        bytes32 seed,
        uint256 bankroll,
        uint256 goal,
        uint256 cap,
        uint256 rollBudget,
        address player
    ) internal pure returns (SlipResult memory r) {
        uint256 stake = stakeFor(b);

        r.bankrollIn = bankroll;
        uint256 initialState = _settlementState(b);
        uint256 unitsPlayed;
        // Indexes 0..5 are the place legs' WINNINGS, by place index; index 6 is the whole figure a
        // winning Don't Pass returns — its own stake plus the 3:4, floored once. Computed here so
        // the roll loop pays out of memory rather than redoing a division per hit.
        uint256[7] memory wins;
        unchecked {
            if (initialState & ST_PLACE_ANY != 0) {
                wins[0] = uint256(b.place4) * (2 * FLIP);
                wins[1] = (uint256(b.place5) * (3 * FLIP)) / 2;
                wins[2] = (uint256(b.place6) * (7 * FLIP)) / 6;
                wins[3] = (uint256(b.place8) * (7 * FLIP)) / 6;
                wins[4] = (uint256(b.place9) * (3 * FLIP)) / 2;
                wins[5] = uint256(b.place10) * (2 * FLIP);
            }
            if (initialState & ST_DONT_LIVE != 0) {
                wins[6] = uint256(b.dontPass) * FLIP + (uint256(b.dontPass) * (3 * FLIP)) / 4;
            }
        }

        unchecked {
            uint256 cur;
            while (true) {
                if (goal != 0 && bankroll >= goal) {
                    r.stop = SlipStop.Goal;
                    break;
                }
                // A hard bound is an ordinary bust. Bust is enum zero, so a bare break is the
                // cheapest path; the battle wrapper forfeits a busted run's remainder.
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
                        // the same double-or-nothing that would decide a run of this length at the
                        // end — rides the whole bankroll. Surviving doubles it, enough to cover
                        // exactly this round, and play continues; losing ends the slip with nothing.
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

                bankroll -= ((cur >> 16) & 0xFFFF) * stake;

                uint256 handOut = _runSettlement(b, handSeed(seed, cur & 0xFFFF), cur >> 32, initialState, wins);
                bankroll += ((cur >> 16) & 0xFFFF) * uint128(handOut);
                unitsPlayed += (cur >> 16) & 0xFFFF;
                cur = (((handOut >> 128) + 1) << 32) | (cur & 0xFFFF0000) | ((cur & 0xFFFF) + 1);
            }

            r.handsPlayed = cur & 0xFFFF;
            r.bankrollOut = bankroll;
            r.unitsPlayed = unitsPlayed;
            r.totalRolls = (cur >> 32) - (cur & 0xFFFF);
        }
    }

    /// @notice Total staked across every leg of `b` — one hand's charge.
    /// @dev What an escrow must collect up front, and the exact ceiling on what the player can
    ///      lose. Multiply by the hand count for a session.
    function stakeFor(Bets memory b) public pure returns (uint256 total) {
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
    function _runSettlement(Bets memory b, bytes32 seed, uint256 logPos, uint256 st, uint256[7] memory wins)
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
                uint256 d1 = (uint256(uint32(w)) % 6) + 1;
                uint256 d2 = (uint256(uint32(w >> 32)) % 6) + 1;
                uint256 t = d1 + d2;
                bool comeOut = (st & ST_POINT_MASK) == 0;
                ++logPos;

                // A point-phase seven ends the hand before any LIGHT bet can pay: every live
                // stake there is swept by the seven-out, so nothing after the break needs the
                // roll. The dark side is the exception — the seven that kills the table is the
                // seven it was waiting for — so it collects here, before the break.
                if (t == 7 && !comeOut) {
                    if (st & ST_DONT_LIVE != 0) returned += wins[6];
                    st |= ST_SEVEN_OUT;
                    break;
                }

                if (!comeOut) {
                    if (st & ST_PLACE_ANY != 0 && st & (1 << t) != 0) {
                        returned += _cachedPlaceWin(wins, t);
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
                        // A come-out natural is the dark side's loss and NOT a seven-out: the
                        // shooter rolls on, with that wager retired for the rest of the hand.
                        st &= ~ST_DONT_LIVE;
                    } else if (t == 12) {
                        // Bar the twelve. The line dies; the dark side neither wins nor loses and
                        // the same wager stays up for the come-out that follows.
                        st &= ~ST_PASS_LIVE;
                    } else if (t == 2 || t == 3) {
                        st &= ~ST_PASS_LIVE;
                        if (st & ST_DONT_LIVE != 0) {
                            returned += wins[6];
                            st &= ~ST_DONT_LIVE;
                        }
                    } else {
                        st |= t << ST_POINT;
                    }
                } else if (t == (st >> ST_POINT) & 0xF) {
                    if (st & ST_PASS_LIVE != 0) returned += uint256(b.passLine) * FLIP;
                    // The point made is the dark side's other death, and the table returns to a
                    // come-out with it already retired.
                    st &= ~(ST_DONT_LIVE | ST_POINT_MASK);
                }
            }

            if (st & ST_SEVEN_OUT == 0) {
                if (st & ST_PASS_LIVE != 0) returned += uint256(b.passLine) * FLIP;
                for (uint256 k = 0; k < 6; ++k) {
                    if (st & (1 << _placeTotal(k)) != 0) returned += _placeWei(b, k);
                }
                if (st & ST_HARD4_LIVE != 0) returned += uint256(b.hard4) * FLIP;
                if (st & ST_HARD8_LIVE != 0) returned += uint256(b.hard8) * FLIP;
                // A hand cut off by the roll cap owes an UNDECIDED dark wager its stake back, and
                // owes a decided one nothing: the liveness bit is exactly that distinction.
                if (st & ST_DONT_LIVE != 0) returned += uint256(b.dontPass) * FLIP;
            }

            // Even 512 consecutive maximum place wins stay below 2^112. Pack the log cursor above
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
        if (b.passLine != 0) st |= ST_PASS_LIVE;
        if (b.dontPass != 0) st |= ST_DONT_LIVE;
    }

    /// @dev Place/hardway specialization selected when the board has no pass line.
    function _runSideSettlement(Bets memory b, bytes32 seed, uint256 logPos, uint256 st, uint256[7] memory wins)
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
                uint256 d1 = (uint256(uint32(w)) % 6) + 1;
                uint256 d2 = (uint256(uint32(w >> 32)) % 6) + 1;
                uint256 t = d1 + d2;
                ++logPos;

                uint256 point = (st >> ST_POINT) & 0xF;
                if (t == 7 && point != 0) {
                    if (st & ST_DONT_LIVE != 0) returned += wins[6];
                    st |= ST_SEVEN_OUT;
                    break;
                }

                if (point != 0) {
                    if (st & ST_PLACE_ANY != 0 && st & (1 << t) != 0) {
                        returned += _cachedPlaceWin(wins, t);
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
                    if (_POINT_TOTALS_MASK & (1 << t) != 0) {
                        st |= t << ST_POINT;
                    } else if (st & ST_DONT_LIVE != 0) {
                        // A come-out that is not a point is the dark side's whole decision: 2 or 3
                        // wins, 7 or 11 loses, and the barred 12 leaves the wager up.
                        if (t == 2 || t == 3) {
                            returned += wins[6];
                            st &= ~ST_DONT_LIVE;
                        } else if (t != 12) {
                            st &= ~ST_DONT_LIVE;
                        }
                    }
                } else if (t == point) {
                    st &= ~(ST_DONT_LIVE | ST_POINT_MASK);
                }
            }

            if (st & ST_SEVEN_OUT == 0) {
                for (uint256 k = 0; k < 6; ++k) {
                    if (st & (1 << _placeTotal(k)) != 0) returned += _placeWei(b, k);
                }
                if (st & ST_HARD4_LIVE != 0) returned += uint256(b.hard4) * FLIP;
                if (st & ST_HARD8_LIVE != 0) returned += uint256(b.hard8) * FLIP;
                if (st & ST_DONT_LIVE != 0) returned += uint256(b.dontPass) * FLIP;
            }
            packed = returned | (logPos << 128);
        }
    }

    /// @dev THE ESCALATOR: the mandatory wager for shooter `hand`, in base-board units — doubling
    ///      every `_ESC_HANDS` shooters, capped at the 65,535-unit table limit. Surviving the table
    ///      means outracing this: a slip cannot flat-grind forever, because the floor under its
    ///      wager keeps rising.
    function _escOf(uint256 hand) private pure returns (uint256 esc) {
        unchecked {
            esc = 1 << (hand / _ESC_HANDS);
            if (esc > 0xFFFF) esc = 0xFFFF;
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
        return uint256(keccak256(abi.encode(SURVIVAL_TAG, seed, n, player))) & 1 == 1;
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

    function _cachedPlaceWin(uint256[7] memory wins, uint256 t) private pure returns (uint256 amount) {
        unchecked {
            uint256 idx = t < 7 ? t - 4 : t - 5;
            assembly ("memory-safe") {
                amount := mload(add(wins, shl(5, idx)))
            }
        }
    }
}
