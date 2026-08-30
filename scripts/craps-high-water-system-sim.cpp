// Reproducible economic Monte Carlo for the proposed high-water CrapsBattle system.
//
// Build:
//   g++ -O3 -std=c++20 -pthread scripts/craps-high-water-system-sim.cpp -o /tmp/craps-high-water-system-sim
// Run:
//   /tmp/craps-system-sim --days 10000 --calibration 250000 --seed 20260826
//
// This is an economic replica, not a byte-for-byte EVM replay. It implements the proposed
// scheduled rules and existing surrounding distributions, while using a fast counter-based
// 64-bit mixer in place of keccak256.
// Shared shooter dice are preserved within each battle; board scatter, survival flips, payout
// rounding, boost rungs, and final exact-score ties use separate deterministic streams.
//
// This file models PROTOCOL-SCHEDULED Dice Run only. Custom battles are deliberately excluded:
// they retain legacy immediate-Goal/speed semantics and contribute to none of the scheduled
// boost, action, progressive, or record paths represented here.

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <deque>
#include <iomanip>
#include <iostream>
#include <limits>
#include <map>
#include <numeric>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

using i64 = std::int64_t;
using u64 = std::uint64_t;

namespace {

constexpr int kWindows = 7;
constexpr int kBurnDays = 7;
// THE SCHEDULED-BONUS FUNDING RULE, exactly as the contract states it:
//     a day's budget = kDefaultMainBase + kActionBps / kBpsDenominator of the trailing action.
// The base is ADDITIVE and is never a floor: a busy week is paid for its action ON TOP of it.
constexpr i64 kActionBps = 1'200;
constexpr i64 kBpsDenominator = 10'000;
constexpr i64 kDefaultMainBase = 50'000;
// THE SPLIT. Half the day's raw main allocation is the ladder its seven windows share; the other
// half — the odd unit with it — is banked in one global progressive. Floored on the ladder side,
// exactly as `_splitMainBudget` floors it, so the two always sum back to the raw figure.
inline i64 ladderHalf(i64 rawMain) { return rawMain / 2; }
inline i64 progressiveHalf(i64 rawMain) { return rawMain - rawMain / 2; }
// THE PROTOCOL-AWARD PASS SPLIT. Half of each eligible protocol award — the admitted main boost,
// a contested lane's boost, the sole rider's protocol ride, the progressive award — converts to
// whole day-pass credits at the lootbox's own denominations; everything the flooring, the
// thirty-high cap or the (unmodeled) lane ceiling refuses pays out liquid. Deterministic: no
// entropy, no Bernoulli rounding.
constexpr i64 kNormalPassValue = 22'800;
constexpr i64 kHighPassValue = 19 * kNormalPassValue;
constexpr i64 kPassHighSwitch = 20 * kNormalPassValue;
constexpr i64 kMaxHighPassesPerAward = 30;
// THE PROGRESSIVE'S RUNGS, in BASIS POINTS of the LIVE pool. Two rungs and two window classes:
// the day's EVENT (period 6) is its headline and pays four times what a routine window does, and
// doubles again where its winner already took a routine field as Goal earlier the same day. A
// ROUTINE window never doubles. Rare overrides common.
constexpr i64 kProgRoutineCommonBps = 500;
constexpr i64 kProgRoutineRareBps = 1'000;
constexpr i64 kProgEventCommonBps = 2'000;
constexpr i64 kProgEventRareBps = 4'000;
// The same four rungs as DOUBLINGS of the routine common share, which is how the award applies
// them and how the contract computes them: rare is worth one, the event two more, and a repeat
// victory at the event one further.
constexpr int kProgRareDoublings = 1;
constexpr int kProgEventDoublings = 2;
// `floor(pool * bps / 10_000)` the way the contract's `_poolShare` computes it: split at the
// denominator first, so the multiplication is bounded by the result rather than by pool * bps.
inline i64 poolShare(i64 pool, i64 bps) {
    return (pool / kBpsDenominator) * bps + ((pool % kBpsDenominator) * bps) / kBpsDenominator;
}
// THE ROLL CUTOFFS, indexed `depthIndex * 3 + goalIndex` with depth in (2, 5, 10) and target in
// (5x, 10x, 50x). Cumulative dice rolls, inclusive, and the WINNING ticket's own.
constexpr int kProgCommon[9] = {150, 205, 340, 215, 275, 405, 265, 325, 455};
constexpr int kProgRare[9] = {185, 245, 395, 260, 320, 455, 315, 375, 500};
// Final peak/start thresholds. 10,000 bps = 1x starting bankroll. Scheduled formats only.
constexpr i64 kGoal5CommonPeakBps = 250'000;   // 25x
constexpr i64 kGoal5RarePeakBps = 1'200'000;   // 120x
constexpr i64 kGoal20CommonPeakBps = 500'000;  // 50x
constexpr i64 kGoal20RarePeakBps = 2'250'000;  // 225x

inline i64 peakCommonBps(int goalMult) {
    return goalMult == 5 ? kGoal5CommonPeakBps : kGoal20CommonPeakBps;
}

inline i64 peakRareBps(int goalMult) {
    return goalMult == 5 ? kGoal5RarePeakBps : kGoal20RarePeakBps;
}

inline int progFormatIndex(int depth, int goalMult) {
    int d = depth == 2 ? 0 : (depth == 5 ? 1 : 2);
    int g = goalMult == 5 ? 0 : ((goalMult == 10 || goalMult == 20) ? 1 : 2);
    return d * 3 + g;
}
// The two parts the HIGH lane's component splits into: two fifths to the main lane, three to
// the lane that earned it.
constexpr i64 kHighToMainNum = 2;
constexpr i64 kHighToMainDen = 5;
constexpr int kScoreFloor = 12;
constexpr int kMaxHands = 512;
int gEscHands = 3;
// Scheduled settlement widens the packed multiplier from 16 to 32 bits. This keeps the
// every-three-shooters escalator live through shooter 95; 0xFFFFFFFF is first used at hand 96.
i64 gEscCap = 0xFFFFFFFFLL;
int gDrawGoalFilter = 0;
constexpr int kRollBudget = 8192;
constexpr int kMaxRolls = 512;
// 1,200ths keep every current payout denominator exact and also keep an integer percentage
// uplift on any combination of current profit payments exact. In particular, 25% of a 3:4
// Don't-Pass profit and 25% of a 7:6 Place profit both remain integral.
constexpr i64 kMoneyUnits = 1'200;
int gDontProfitNum = 3;
int gDontProfitDen = 4;
i64 gMainBase = kDefaultMainBase;
// Analysis-only switch for the proposed rules: reaching Goal latches qualification, after which
// only surplus above Goal may fund another full shooter. Goal fields rank by their completed-
// shooter bankroll high-water mark, then by ending bankroll; Bust fields retain the shipped rank.
bool gHighWaterGoal = true;
// THE PROPOSED SHOOTER PROFIT SCHEDULE, as the defaults. A blank/random ticket carries the boost
// on 15 shooters in a hundred and a picked one on 5; the amount is FIXED per target — there is no
// jitter and no fractional rung, so the bps figures below are always whole hundreds.
//
//     ticket   eligible   goal 5x   goal 20x
//     blank        15%       +33%        +45%
//     picked        5%       +20%        +50%
//
// Every knob here stays overridable so a sweep can still explore off-schedule settings; nothing
// but an explicit flag moves them off production.
int gBoostedShootersPct = 0;
int gWinningsBoostPct = 0;
enum class WinningsBoostMode { All, RandomTickets };
WinningsBoostMode gWinningsBoostMode = WinningsBoostMode::All;
int gRandomBoostedShootersPct = 15;
int gPickedBoostedShootersPct = 5;
int gRandomGoal5ShooterPct = -1;
int gRandomGoal10ShooterPct = -1;
int gRandomGoal50ShooterPct = -1;
int gPickedGoal5ShooterPct = -1;
int gPickedGoal10ShooterPct = -1;
int gPickedGoal50ShooterPct = -1;
int gRandomWinningsBoostPct = -1;
int gPickedWinningsBoostPct = -1;
int gRandomWinningsBoostJitterPct = 0;
int gPickedWinningsBoostJitterPct = 0;
int gRandomGoal5WinningsBoostBps = 3'300;
int gRandomGoal10WinningsBoostBps = 4'500;
int gRandomGoal50WinningsBoostBps = 4'500;
int gPickedGoal5WinningsBoostBps = 2'000;
int gPickedGoal10WinningsBoostBps = 5'000;
int gPickedGoal50WinningsBoostBps = 5'000;

int winningsBoostFrequency(bool randomTicket) {
    int overridePct = randomTicket ? gRandomBoostedShootersPct : gPickedBoostedShootersPct;
    if (overridePct >= 0) return overridePct;
    if (!randomTicket && gWinningsBoostMode == WinningsBoostMode::RandomTickets) return 0;
    return gBoostedShootersPct;
}

int winningsBoostFrequency(bool randomTicket, int goalMult) {
    int goalPct = -1;
    if (goalMult == 5) {
        goalPct = randomTicket ? gRandomGoal5ShooterPct : gPickedGoal5ShooterPct;
    } else if (goalMult == 10 || goalMult == 20) {
        goalPct = randomTicket ? gRandomGoal10ShooterPct : gPickedGoal10ShooterPct;
    } else if (goalMult == 50) {
        goalPct = randomTicket ? gRandomGoal50ShooterPct : gPickedGoal50ShooterPct;
    }
    return goalPct >= 0 ? goalPct : winningsBoostFrequency(randomTicket);
}

int winningsBoostAmount(bool randomTicket) {
    int overridePct = randomTicket ? gRandomWinningsBoostPct : gPickedWinningsBoostPct;
    return overridePct >= 0 ? overridePct : gWinningsBoostPct;
}

int winningsBoostJitter(bool randomTicket) {
    return randomTicket ? gRandomWinningsBoostJitterPct : gPickedWinningsBoostJitterPct;
}

int winningsBoostTargetBps(bool randomTicket, int goalMult) {
    int goalBps = -1;
    if (goalMult == 5) {
        goalBps = randomTicket ? gRandomGoal5WinningsBoostBps : gPickedGoal5WinningsBoostBps;
    } else if (goalMult == 10 || goalMult == 20) {
        goalBps = randomTicket ? gRandomGoal10WinningsBoostBps : gPickedGoal10WinningsBoostBps;
    } else if (goalMult == 50) {
        goalBps = randomTicket ? gRandomGoal50WinningsBoostBps : gPickedGoal50WinningsBoostBps;
    }
    if (goalBps >= 0) return goalBps;
    return winningsBoostAmount(randomTicket) * 100;
}

u64 mix64(u64 x) {
    x += 0x9e3779b97f4a7c15ULL;
    x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9ULL;
    x = (x ^ (x >> 27)) * 0x94d049bb133111ebULL;
    return x ^ (x >> 31);
}

u64 keyed(u64 a, u64 b = 0, u64 c = 0, u64 d = 0) {
    return mix64(a ^ mix64(b + 0x243f6a8885a308d3ULL)
                 ^ mix64(c + 0x13198a2e03707344ULL)
                 ^ mix64(d + 0xa4093822299f31d0ULL));
}

struct Rng {
    u64 state;
    explicit Rng(u64 seed) : state(seed) {}
    u64 next() { return state = mix64(state); }
    u64 below(u64 n) { return next() % n; }
};

using ChipCounts = std::array<i64, 10>;

enum class Strategy { Sharp4, FairSpread, Mixed, Pass, Blank, Hardways, Dark, Bounty, FairControl };

std::string_view strategyName(Strategy s) {
    switch (s) {
        case Strategy::Sharp4: return "sharp_place4_4_place10_3";
        case Strategy::FairSpread: return "fair_spread";
        case Strategy::Mixed: return "mixed";
        case Strategy::Pass: return "pass4_place4_3";
        case Strategy::Blank: return "blank";
        case Strategy::Hardways: return "hardways";
        case Strategy::Dark: return "dontpass4_place4_3";
        case Strategy::Bounty: return "bounty_dontpass4_place5_3";
        case Strategy::FairControl: return "control_10_fair_no_scatter";
    }
    return "unknown";
}

Strategy strategyFromName(std::string_view name) {
    if (name == "sharp" || name == "sharp_place4_4_place10_3") return Strategy::Sharp4;
    if (name == "fair" || name == "fair_spread") return Strategy::FairSpread;
    if (name == "mixed") return Strategy::Mixed;
    if (name == "pass" || name == "pass4_place4_3") return Strategy::Pass;
    if (name == "blank") return Strategy::Blank;
    if (name == "hardways") return Strategy::Hardways;
    if (name == "dark" || name == "dontpass4_place4_3") return Strategy::Dark;
    if (name == "bounty" || name == "bounty_dontpass4_place5_3") return Strategy::Bounty;
    throw std::invalid_argument("unknown strategy name");
}

// Canonical production order: pass, place4, place5, place6, place8, place9, place10,
// hard4, hard8, don't pass. Values are chip counts before scaling by the window chip.
ChipCounts pickedCounts(Strategy s) {
    ChipCounts c{};
    switch (s) {
        case Strategy::Sharp4:
            c[1] = 4;
            c[6] = 3;
            break;
        case Strategy::FairSpread:
            c[1] = 2;
            c[2] = 2;
            c[5] = 1;
            c[6] = 2;
            break;
        case Strategy::Mixed:
            c[0] = 2;
            c[1] = c[2] = c[3] = c[4] = c[5] = 1;
            break;
        case Strategy::Pass:
            c[0] = 4;
            c[1] = 3;
            break;
        case Strategy::Blank:
            break;
        case Strategy::Hardways:
            c[7] = 4;
            c[8] = 3;
            break;
        case Strategy::Dark:
            c[1] = 3;
            c[9] = 4;
            break;
        case Strategy::Bounty:
            c[2] = 3;
            c[9] = 4;
            break;
        case Strategy::FairControl:
            // Mathematical control, not a player-submitted board: ten chips entirely on true-odds
            // Place legs and no random scatter. It isolates bust-forfeiture drag from wager drag.
            c[1] = 4;
            c[2] = 3;
            c[6] = 3;
            break;
    }
    return c;
}

struct Terms {
    i64 bankroll{};
    i64 goal{};
    i64 round{};
    i64 bounty{};
    int depth{};
    int goalMult{};
    int tier{}; // routine: 1/2/3; event: 0
};

Terms drawTerms(Rng& rng, int period) {
    Terms t;
    t.depth = 5;
    // Scheduled play now has only two targets. A goal filter is useful for format-specific
    // board searches; otherwise draw the two formats evenly.
    t.goalMult = gDrawGoalFilter != 0 ? gDrawGoalFilter : (rng.below(2) == 0 ? 5 : 20);

    if (period == kWindows - 1) {
        int tail = static_cast<int>(rng.below(100));
        t.bankroll = tail < 5 ? 30'000 : (tail < 7 ? 60'000 : 1'500 * (1 + static_cast<int>(rng.below(10))));
        int pct = 25 + 5 * static_cast<int>(rng.below(6));
        t.bounty = ((t.bankroll * pct) / 100 / 100) * 100;
        t.tier = 0;
    } else {
        int tierPick;
        if (period == 0) {
            tierPick = static_cast<int>(rng.below(3));
        } else {
            int x = static_cast<int>(rng.below(10));
            tierPick = x < 7 ? 0 : (x < 9 ? 1 : 2);
        }
        int b = static_cast<int>(rng.below(3));
        if (tierPick == 0) {
            t.tier = 1;
            t.bankroll = 300;
            t.bounty = std::array<i64, 3>{100, 200, 300}[b];
        } else if (tierPick == 1) {
            t.tier = 2;
            t.bankroll = 1'200;
            t.bounty = std::array<i64, 3>{300, 800, 1'200}[b];
        } else {
            t.tier = 3;
            t.bankroll = 3'000;
            t.bounty = std::array<i64, 3>{1'000, 1'500, 3'000}[b];
        }
    }
    t.round = (t.bankroll / t.depth / 10) * 10;
    if (t.round < 10) t.round = 10;
    t.goal = t.bankroll * t.goalMult;
    return t;
}

struct Roll { int d1; int d2; };

struct Shooter {
    std::vector<Roll> rolls;
    bool sevenOut{};
};

class ShooterCache {
  public:
    explicit ShooterCache(u64 seed) : seed_(seed) {}

    const Shooter& get(int hand) {
        while (static_cast<int>(shooters_.size()) <= hand) shooters_.push_back(make(static_cast<int>(shooters_.size())));
        return shooters_[hand];
    }

  private:
    Shooter make(int hand) const {
        Shooter s;
        int point = 0;
        for (int i = 0; i < kMaxRolls; ++i) {
            u64 w = keyed(seed_, static_cast<u64>(hand), static_cast<u64>(i), 0xd1ceULL);
            Roll r{static_cast<int>(w % 6) + 1, static_cast<int>((w >> 32) % 6) + 1};
            s.rolls.push_back(r);
            int total = r.d1 + r.d2;
            if (point != 0 && total == 7) {
                s.sevenOut = true;
                break;
            }
            if (point == 0) {
                if (total == 4 || total == 5 || total == 6 || total == 8 || total == 9 || total == 10) point = total;
            } else if (total == point) {
                point = 0;
            }
        }
        return s;
    }

    u64 seed_;
    std::vector<Shooter> shooters_;
};

// Board stakes and raw settlement values use 1,200ths of one FLIP. That keeps every current
// payout denominator and integer-percentage profit uplift exact without floating point.
using BoardMoney = std::array<i64, 10>;

BoardMoney makeBoard(const Terms& t, Strategy strategy, u64 scatterSeed, u64 playerKey) {
    auto counts = pickedCounts(strategy);
    int thrown = strategy == Strategy::Blank ? 10 : (strategy == Strategy::FairControl ? 0 : 3);
    for (int i = 0; i < thrown; ++i) {
        int leg = static_cast<int>(keyed(scatterSeed, playerKey, static_cast<u64>(i), 0x5ca77eULL) % 10);
        ++counts[leg];
    }
    i64 chipMoney = (t.round / 10) * kMoneyUnits;
    BoardMoney b{};
    for (int i = 0; i < 10; ++i) b[i] = counts[i] * chipMoney;
    return b;
}

BoardMoney makeBoardChoice(
    const Terms& t, const ChipCounts& selected, u64 scatterSeed, u64 playerKey
) {
    ChipCounts counts = selected;
    // Zero is the contract's other legal board mode: scatter all ten chips. Every nonzero board
    // enumerated by the search is a legal seven-chip selection and therefore scatters three.
    int thrown = std::accumulate(selected.begin(), selected.end(), i64{0}) == 0 ? 10 : 3;
    for (int i = 0; i < thrown; ++i) {
        int leg = static_cast<int>(keyed(scatterSeed, playerKey, static_cast<u64>(i), 0x5ca77eULL) % 10);
        ++counts[leg];
    }
    i64 chipMoney = (t.round / 10) * kMoneyUnits;
    BoardMoney b{};
    for (int i = 0; i < 10; ++i) b[i] = counts[i] * chipMoney;
    return b;
}

i64 runHandMoney(const BoardMoney& b, const Shooter& shooter, bool boosted, int winningsBoostPct) {
    bool pass = b[0] != 0;
    std::array<bool, 6> place{};
    for (int i = 0; i < 6; ++i) place[i] = b[i + 1] != 0;
    bool hard4 = b[7] != 0;
    bool hard8 = b[8] != 0;
    bool dark = b[9] != 0;
    int point = 0;
    i64 returned = 0;
    i64 eligibleProfit = 0;

    auto payProfit = [&](i64 amount) {
        returned += amount;
        eligibleProfit += amount;
    };

    auto payDont = [&]() {
        i64 profit = b[9] * gDontProfitNum / gDontProfitDen;
        returned += b[9] + profit;
        eligibleProfit += profit;
    };

    auto payPlace = [&](int total) {
        if (total == 4 && place[0]) payProfit(b[1] * 2);
        else if (total == 5 && place[1]) payProfit(b[2] * 3 / 2);
        else if (total == 6 && place[2]) payProfit(b[3] * 7 / 6);
        else if (total == 8 && place[3]) payProfit(b[4] * 7 / 6);
        else if (total == 9 && place[4]) payProfit(b[5] * 3 / 2);
        else if (total == 10 && place[5]) payProfit(b[6] * 2);
    };

    bool sevenOut = false;
    for (const Roll& r : shooter.rolls) {
        int total = r.d1 + r.d2;
        bool comeOut = point == 0;
        if (!comeOut && total == 7) {
            if (dark) payDont();
            sevenOut = true;
            break;
        }

        if (!comeOut) {
            payPlace(total);
            if (total == 4 && hard4) {
                if (r.d1 == r.d2) payProfit(b[7] * 7);
                else hard4 = false;
            } else if (total == 8 && hard8) {
                if (r.d1 == r.d2) payProfit(b[8] * 9);
                else hard8 = false;
            }
        }

        if (comeOut) {
            if (total == 7 || total == 11) {
                if (pass) payProfit(b[0]);
                dark = false;
            } else if (total == 12) {
                pass = false;
            } else if (total == 2 || total == 3) {
                pass = false;
                if (dark) {
                    payDont();
                    dark = false;
                }
            } else {
                point = total;
            }
        } else if (total == point) {
            if (pass) payProfit(b[0]);
            dark = false;
            point = 0;
        }
    }

    if (!sevenOut) {
        if (pass) returned += b[0];
        for (int i = 0; i < 6; ++i) if (place[i]) returned += b[i + 1];
        if (hard4) returned += b[7];
        if (hard8) returned += b[8];
        if (dark) returned += b[9];
    }
    if (boosted) returned += eligibleProfit * winningsBoostPct / 100;
    return returned;
}

enum class Stop { Bust, Goal };

struct Run {
    i64 rawMoney{};
    i64 paid{};
    i64 peakMoney{};
    int hands{};
    int rolls{};
    int goalHands{-1};
    int goalRolls{-1};
    i64 goalMoney{};
    int peakHands{};
    int peakRolls{};
    Stop stop{Stop::Bust};
    i64 units{};
    bool capped{};
    i64 ceilingEntryMoney{-1};
    int ceilingEntryHand{-1};
    i64 maxHandGainMoney{};
    int maxHandGainHand{-1};
    int positiveHands{};
    int negativeHands{};
    int flatHands{};
    int boostedHands{};
};

i64 highWaterBps(const Run& r, const Terms& t);

i64 roundedPaid(i64 rawMoney, u64 seed, u64 playerKey) {
    if (rawMoney <= 0) return 0;
    i64 whole = rawMoney / kMoneyUnits;
    if (rawMoney <= 1'000 * kMoneyUnits) return whole;
    i64 hundreds = whole / 100;
    i64 rem = whole % 100;
    if (rem != 0 && static_cast<i64>(keyed(seed, playerKey, 0xf11f00dULL) % 100) < rem) ++hundreds;
    return hundreds * 100;
}

Run settlePreparedBoard(
    const Terms& t,
    const BoardMoney& board,
    ShooterCache& dice,
    u64 seed,
    u64 playerKey,
    int boostedShootersPct,
    int winningsBoostTargetBps,
    int winningsBoostJitterPct
) {
    i64 stakeMoney = std::accumulate(board.begin(), board.end(), i64{0});
    i64 bankrollMoney = t.bankroll * kMoneyUnits;
    i64 goalMoney = t.goal * kMoneyUnits;
    Run r;
    r.peakMoney = bankrollMoney;
    bool qualified = false;

    while (true) {
        if (!qualified && bankrollMoney >= goalMoney) {
            qualified = true;
            r.stop = Stop::Goal;
            r.goalHands = r.hands;
            r.goalRolls = r.rolls;
            r.goalMoney = bankrollMoney;
            if (!gHighWaterGoal) break;
        }
        if (r.hands == kMaxHands || r.rolls >= kRollBudget) {
            r.stop = qualified ? Stop::Goal : Stop::Bust;
            r.capped = true;
            break;
        }
        int escShift = r.hands / gEscHands;
        i64 q = escShift >= 62 ? gEscCap : std::min(i64{1} << escShift, gEscCap);
        if (q == gEscCap && r.ceilingEntryHand == -1) {
            r.ceilingEntryMoney = bankrollMoney;
            r.ceilingEntryHand = r.hands;
        }
        i64 needMoney = stakeMoney * q;
        if (qualified) {
            // Goal is a protected reserve. Equality is playable: only a round that would leave
            // LESS than Goal behind retires the run.
            if (bankrollMoney - goalMoney < needMoney) {
                r.stop = Stop::Goal;
                break;
            }
        } else {
            if (bankrollMoney * 2 < needMoney) {
                r.stop = Stop::Bust;
                break;
            }
            if (bankrollMoney < needMoney) {
                bool survived = (keyed(seed, playerKey, static_cast<u64>(r.hands), 0x5a7ULL) & 1) != 0;
                if (survived) bankrollMoney *= 2;
                else {
                    bankrollMoney = 0;
                    r.stop = Stop::Bust;
                    break;
                }
            }
        }

        i64 beforeHandMoney = bankrollMoney;
        bankrollMoney -= needMoney;
        const Shooter& shooter = dice.get(r.hands);
        bool boosted = boostedShootersPct != 0 && winningsBoostTargetBps != 0
            && static_cast<int>(keyed(seed, playerKey, static_cast<u64>(r.hands), 0xb0057ULL) % 100)
                < boostedShootersPct;
        int shooterBoostPct = winningsBoostTargetBps / 100;
        int fractionalPct = winningsBoostTargetBps % 100;
        if (boosted && fractionalPct != 0
            && static_cast<int>(keyed(seed, playerKey, static_cast<u64>(r.hands), 0xb0058ULL) % 100)
                < fractionalPct) {
            ++shooterBoostPct;
        }
        if (boosted && winningsBoostJitterPct != 0) {
            int width = winningsBoostJitterPct * 2 + 1;
            int offset = static_cast<int>(
                keyed(seed, playerKey, static_cast<u64>(r.hands), 0xb0059ULL) % width
            ) - winningsBoostJitterPct;
            shooterBoostPct = std::max(0, shooterBoostPct + offset);
        }
        if (boosted) ++r.boostedHands;
        bankrollMoney += runHandMoney(board, shooter, boosted, shooterBoostPct) * q;
        i64 handGainMoney = bankrollMoney - beforeHandMoney;
        if (handGainMoney > 0) ++r.positiveHands;
        else if (handGainMoney < 0) ++r.negativeHands;
        else ++r.flatHands;
        if (handGainMoney > r.maxHandGainMoney) {
            r.maxHandGainMoney = handGainMoney;
            r.maxHandGainHand = r.hands;
        }
        r.units += q;
        r.rolls += static_cast<int>(shooter.rolls.size());
        ++r.hands;
        if (bankrollMoney > r.peakMoney) {
            r.peakMoney = bankrollMoney;
            r.peakHands = r.hands;
            r.peakRolls = r.rolls;
        }
    }

    r.rawMoney = bankrollMoney;
    r.paid = r.stop == Stop::Bust ? 0 : roundedPaid(bankrollMoney, seed, playerKey);
    return r;
}

Run settleRun(const Terms& t, Strategy strategy, ShooterCache& dice, u64 seed, u64 playerKey) {
    BoardMoney board = makeBoard(t, strategy, seed, playerKey);
    bool randomTicket = strategy == Strategy::Blank;
    return settlePreparedBoard(
        t, board, dice, seed, playerKey,
        winningsBoostFrequency(randomTicket, t.goalMult), winningsBoostTargetBps(randomTicket, t.goalMult),
        winningsBoostJitter(randomTicket)
    );
}

Run settleBoardChoice(
    const Terms& t,
    const ChipCounts& selected,
    ShooterCache& dice,
    u64 seed,
    u64 playerKey
) {
    BoardMoney board = makeBoardChoice(t, selected, seed, playerKey);
    bool randomTicket = std::accumulate(selected.begin(), selected.end(), i64{0}) == 0;
    return settlePreparedBoard(
        t, board, dice, seed, playerKey,
        winningsBoostFrequency(randomTicket, t.goalMult), winningsBoostTargetBps(randomTicket, t.goalMult),
        winningsBoostJitter(randomTicket)
    );
}

struct ScoredRun {
    Run run;
    int standing{};
    u64 tie{};
};

bool better(const ScoredRun& a, const ScoredRun& b) {
    if (a.run.stop != b.run.stop) return a.run.stop == Stop::Goal;
    if (gHighWaterGoal && a.run.stop == Stop::Goal) {
        i64 ap = a.run.peakMoney / kMoneyUnits;
        i64 bp = b.run.peakMoney / kMoneyUnits;
        if (ap != bp) return ap > bp;
        i64 aw = a.run.rawMoney / kMoneyUnits;
        i64 bw = b.run.rawMoney / kMoneyUnits;
        if (aw != bw) return aw > bw;
        if (a.standing != b.standing) return a.standing > b.standing;
        return a.tie > b.tie;
    }
    if (a.run.hands != b.run.hands) {
        return a.run.stop == Stop::Goal ? a.run.hands < b.run.hands : a.run.hands > b.run.hands;
    }
    i64 aw = a.run.rawMoney / kMoneyUnits;
    i64 bw = b.run.rawMoney / kMoneyUnits;
    if (aw != bw) return aw > bw;
    if (a.standing != b.standing) return a.standing > b.standing;
    return a.tie > b.tie;
}

i64 integerPercentile(std::vector<i64> xs, long double q);

void printBountyMatchup(int fields, u64 seed) {
    constexpr std::array<int, 2> goals{5, 20};
    std::cout << "BOUNTY_MATCHUP_HEADER\tgoal_multiple\tfields\tfield_random_win_pct"
                 "\tfield_picked_win_pct\tpair_random_win_pct\tpair_picked_win_pct"
                 "\tqualified_winner_pct\tall_bust_pct"
                 "\tall_winner_peak_p90_bps\tall_winner_peak_p99_bps"
                 "\tqualified_peak_p90_bps\tqualified_peak_p99_bps\n";
    for (int goalMult : goals) {
        ChipCounts bountyBoard{};
        // Best common tournament board in the 8,917-board search against random incumbents:
        // one Place 5, two Place 9, four Don't Pass.
        bountyBoard[2] = 1;
        bountyBoard[5] = 2;
        bountyBoard[9] = 4;
        Rng rng(keyed(seed, static_cast<u64>(goalMult), 0xb0177ULL));
        std::size_t fieldRandomWins = 0;
        std::size_t pairRandomWins = 0;
        std::size_t qualifiedWinners = 0;
        std::vector<i64> allWinnerPeaks;
        std::vector<i64> qualifiedWinnerPeaks;
        allWinnerPeaks.reserve(static_cast<std::size_t>(fields));
        qualifiedWinnerPeaks.reserve(static_cast<std::size_t>(fields));
        for (int f = 0; f < fields; ++f) {
            Terms t;
            t.bankroll = 3'000;
            t.depth = 5;
            t.goalMult = goalMult;
            t.round = t.bankroll / t.depth;
            t.goal = t.bankroll * t.goalMult;
            u64 runSeed = rng.next();
            ShooterCache dice(runSeed);
            std::array<ScoredRun, 40> runs;
            for (std::size_t n = 0; n < runs.size(); ++n) {
                u64 playerKey = keyed(seed, static_cast<u64>(goalMult), static_cast<u64>(f), n + 1);
                Run run = n < 20
                    ? settleRun(t, Strategy::Blank, dice, runSeed, playerKey)
                    : settleBoardChoice(t, bountyBoard, dice, runSeed, playerKey);
                runs[n] = ScoredRun{
                    run,
                    kScoreFloor,
                    keyed(runSeed, n, 0x71eULL)
                };
            }
            std::size_t winner = 0;
            for (std::size_t n = 1; n < runs.size(); ++n) {
                if (better(runs[n], runs[winner])) winner = n;
            }
            if (winner < 20) ++fieldRandomWins;
            i64 winnerPeak = highWaterBps(runs[winner].run, t);
            allWinnerPeaks.push_back(winnerPeak);
            if (runs[winner].run.stop == Stop::Goal) {
                ++qualifiedWinners;
                qualifiedWinnerPeaks.push_back(winnerPeak);
            }
            if (better(runs[0], runs[20])) ++pairRandomWins;
        }
        auto pct = [&](std::size_t n) {
            return 100.0L * static_cast<long double>(n) / fields;
        };
        std::cout << "BOUNTY_MATCHUP\t" << goalMult << '\t' << fields
                  << '\t' << static_cast<double>(pct(fieldRandomWins))
                  << '\t' << static_cast<double>(100.0L - pct(fieldRandomWins))
                  << '\t' << static_cast<double>(pct(pairRandomWins))
                  << '\t' << static_cast<double>(100.0L - pct(pairRandomWins))
                  << '\t' << static_cast<double>(pct(qualifiedWinners))
                  << '\t' << static_cast<double>(100.0L - pct(qualifiedWinners))
                  << '\t' << integerPercentile(allWinnerPeaks, 0.90L)
                  << '\t' << integerPercentile(allWinnerPeaks, 0.99L)
                  << '\t' << integerPercentile(qualifiedWinnerPeaks, 0.90L)
                  << '\t' << integerPercentile(qualifiedWinnerPeaks, 0.99L) << "\n";
    }
}

bool betterShippedFromHighWater(const ScoredRun& a, const ScoredRun& b) {
    if (a.run.stop != b.run.stop) return a.run.stop == Stop::Goal;
    int ah = a.run.stop == Stop::Goal ? a.run.goalHands : a.run.hands;
    int bh = b.run.stop == Stop::Goal ? b.run.goalHands : b.run.hands;
    if (ah != bh) return a.run.stop == Stop::Goal ? ah < bh : ah > bh;
    i64 aw = (a.run.stop == Stop::Goal ? a.run.goalMoney : a.run.rawMoney) / kMoneyUnits;
    i64 bw = (b.run.stop == Stop::Goal ? b.run.goalMoney : b.run.rawMoney) / kMoneyUnits;
    if (aw != bw) return aw > bw;
    if (a.standing != b.standing) return a.standing > b.standing;
    return a.tie > b.tie;
}

enum class Funding { Cash, FreePass, Prepaid };

struct Cohort {
    std::string name;
    int ordinary{};
    int high{};
    Strategy strategy{Strategy::Blank};
    int standing{kScoreFloor};
    Funding funding{Funding::Cash};
};

struct Scenario {
    std::string name;
    std::vector<Cohort> cohorts;
    int forcedHigh{}; // zero = production 90% 10x / 10% 100x draw
};

struct Seat {
    int group{};
    bool high{};
    Strategy strategy{};
    int standing{};
    Funding funding{};
    u64 playerKey{};
};

struct GroupTotals {
    long double faceCost{};
    long double cashBurn{};
    long double engineCredit{};
    long double potCredit{};
    long double totalCredit{};
    long double mainWins{};
    long double highWins{};
};

struct Totals {
    long double days{};
    long double windows{};
    long double ordinarySeats{};
    long double highSeats{};
    long double actionRegular{};
    long double actionHigh{};
    long double riskBankroll{};
    long double engineCredit{};
    long double rawBankroll{};
    long double deletedOnBust{};
    long double faceCost{};
    long double cashBurn{};
    long double totalCredit{};
    long double bountyPosted{};
    long double bountyReturned{};
    long double mainBudget{};
    long double highBudget{};
    long double mainBoostPaid{};
    long double highBoostPaid{};
    /// THE PROGRESSIVE'S BOOK. `progressiveFunded` is the half of each day's main allocation that
    /// is banked rather than laddered — EMISSION, counted the day it lands. `progressiveRolled` is
    /// protocol money a standing curve denied, which is emission already counted as part of the
    /// budget it came out of. `progressivePaid` is a RELEASE of that stored liability and must
    /// never be counted as issuance a second time.
    long double progressiveFunded{};
    long double progressiveRolled{};
    long double progressivePaid{};
    long double progressiveCommonAwards{};
    long double progressiveRareAwards{};
    /// THE PASS SPLIT'S BOOK, by source: 0 main ladder, 1 contested high, 2 sole rider,
    /// 3 progressive — the same numbering the contract's split event freezes. Pass value is
    /// award value delivered in a different shape, so every credit ledger above still carries
    /// the full gross and the split moves none of them; these count what changed shape.
    std::array<long double, 4> passNormal{};
    std::array<long double, 4> passHigh{};
    std::array<long double, 4> passValue{};
    long double passCapHits{};
    /// What ONE seat of each kind puts through the table per day, summed over counted days —
    /// the redemption-side figure a banked pass-day later adds to action when it is used.
    long double ordinarySeatDayAction{};
    long double highSeatDayAction{};
    /// The pool's balance at the end of the counted run, and its trajectory.
    long double progressiveEnd{};
    std::vector<long double> progressiveDaily;
    // The LINEAR TERM the schedule's rate implies on the day's action. Not an estimate of burn
    // and never was: the rate is a policy choice about the handle.
    long double linearTerm{};
    std::vector<long double> dailyBoostPaid;
    std::vector<GroupTotals> groups;
};

i64 boostUnits(i64 base, int quarterMult) {
    return base * quarterMult / 400; // base FLIP -> 100-FLIP granules, then quarter multiplier
}

i64 boostShare(i64 units, int standing) {
    if (standing >= kScoreFloor) return units;
    if (standing == 0) return 0;
    return units / (kScoreFloor - standing);
}

// The contract's deterministic award split, applied to one gross figure: half of it is the pass
// target, floored to whole passes — HIGH above twenty normal units, at most thirty of them — and
// the return is the pass VALUE that changed shape. The caller's credit figures are left whole.
i64 splitAward(i64 gross, int source, Totals& out) {
    i64 budget = gross / 2;
    bool high = budget > kPassHighSwitch;
    i64 unit = high ? kHighPassValue : kNormalPassValue;
    i64 wanted = budget / unit;
    if (high && wanted > kMaxHighPassesPerAward) {
        wanted = kMaxHighPassesPerAward;
        out.passCapHits += 1;
    }
    if (wanted == 0) return 0;
    if (high) out.passHigh[source] += static_cast<long double>(wanted);
    else out.passNormal[source] += static_cast<long double>(wanted);
    i64 value = wanted * unit;
    out.passValue[source] += static_cast<long double>(value);
    return value;
}

i64 roundBoostUnits(i64 units) {
    if (units <= 40) return units;
    return ((units + 5) / 10) * 10;
}

i64 paidBoost(i64 base, int quarterMult, int standing) {
    return roundBoostUnits(boostShare(boostUnits(base, quarterMult), standing)) * 100;
}

long double expectedPaidBoost(i64 base, int standing) {
    return (
        768.0L * paidBoost(base, 1, standing)
        + 208.0L * paidBoost(base, 4, standing)
        + 20.0L * paidBoost(base, 40, standing)
        + 4.0L * paidBoost(base, 400, standing)
    ) / 1000.0L;
}

int drawBoostQuarterMult(Rng& rng) {
    int x = static_cast<int>(rng.below(1000));
    if (x < 768) return 1;
    if (x < 976) return 4;
    if (x < 996) return 40;
    return 400;
}

std::pair<i64, i64> drawBudgets(const std::deque<std::pair<i64, i64>>& action) {
    i64 er = 0;
    i64 eh = 0;
    for (const auto& [regular, high] : action) {
        er += regular * kActionBps / kBpsDenominator;
        eh += high * kActionBps / kBpsDenominator;
    }
    er /= kBurnDays;
    eh /= kBurnDays;
    i64 fromHigh = eh * kHighToMainNum / kHighToMainDen;
    i64 highBudget = eh - fromHigh;
    // ADDITIVE, NOT A FLOOR: `gMainBase + linear`, never `max(gMainBase, linear)`.
    i64 mainBudget = gMainBase + er + fromHigh;
    return {mainBudget, highBudget};
}

std::vector<Seat> makeSeats(const Scenario& scenario, u64 scenarioKey) {
    std::vector<Seat> seats;
    for (int g = 0; g < static_cast<int>(scenario.cohorts.size()); ++g) {
        const Cohort& c = scenario.cohorts[g];
        for (int i = 0; i < c.ordinary; ++i) {
            seats.push_back(Seat{g, false, c.strategy, c.standing, c.funding,
                                 keyed(scenarioKey, static_cast<u64>(g), static_cast<u64>(i), 1)});
        }
        for (int i = 0; i < c.high; ++i) {
            seats.push_back(Seat{g, true, c.strategy, c.standing, c.funding,
                                 keyed(scenarioKey, static_cast<u64>(g), static_cast<u64>(i), 2)});
        }
    }
    return seats;
}

long double percentile(std::vector<long double> xs, long double q) {
    if (xs.empty()) return 0;
    std::sort(xs.begin(), xs.end());
    long double pos = q * static_cast<long double>(xs.size() - 1);
    std::size_t lo = static_cast<std::size_t>(pos);
    std::size_t hi = std::min(lo + 1, xs.size() - 1);
    long double f = pos - static_cast<long double>(lo);
    return xs[lo] * (1 - f) + xs[hi] * f;
}

Totals simulateScenario(const Scenario& scenario, int days, int warmup, u64 seed) {
    Rng rng(seed);
    std::vector<Seat> seats = makeSeats(scenario, seed);
    int highHeads = static_cast<int>(std::count_if(seats.begin(), seats.end(), [](const Seat& s) { return s.high; }));
    int ordinaryHeads = static_cast<int>(seats.size()) - highHeads;
    std::deque<std::pair<i64, i64>> history(kBurnDays, {0, 0});
    Totals out;
    out.groups.resize(scenario.cohorts.size());
    // ONE POOL, carried across every day and every window of the run. It is warmed through the
    // burn-in exactly as the contract's would be through its own first days, so the counted run
    // opens on a realistic balance rather than an empty table.
    i64 pool = 0;

    for (int day = 0; day < days + warmup; ++day) {
        auto [rawMain, highBudget] = drawBudgets(history);
        i64 mainBudget = ladderHalf(rawMain);
        i64 contribution = progressiveHalf(rawMain);
        pool += contribution;
        int highMult = scenario.forcedHigh != 0 ? scenario.forcedHigh : (rng.below(10) == 0 ? 100 : 10);
        std::array<Terms, kWindows> terms;
        int routineWeight = 0;
        for (int p = 0; p < kWindows; ++p) {
            terms[p] = drawTerms(rng, p);
            if (p + 1 < kWindows) routineWeight += 1 << (terms[p].tier - 1);
        }

        bool count = day >= warmup;
        i64 dayRegular = 0;
        i64 dayHigh = 0;
        long double dayBoostPaid = 0;
        // THE DAY'S ROUTINE GOAL VICTORS, cleared with the day exactly as the contract's
        // day-stamped map goes stale with it. Only a routine field writes here, so the event can
        // never qualify itself, and the flag is read at the moment the event resolves.
        std::vector<char> routineGoalWinner(seats.size(), 0);

        if (count) {
            out.days += 1;
            out.windows += kWindows;
            out.ordinarySeats += static_cast<long double>(ordinaryHeads) * kWindows;
            out.highSeats += static_cast<long double>(highHeads) * kWindows;
            // THE RAW ALLOCATION is what the emission accounting is against: the ladder half is
            // paid out immediately and the other half becomes a liability the moment it is banked.
            out.mainBudget += rawMain;
            out.highBudget += highBudget;
            out.progressiveFunded += contribution;
            for (int p = 0; p < kWindows; ++p) {
                out.ordinarySeatDayAction += static_cast<long double>(terms[p].bankroll);
                out.highSeatDayAction += static_cast<long double>(terms[p].bankroll) * highMult;
            }
            for (int g = 0; g < static_cast<int>(scenario.cohorts.size()); ++g) {
                const Cohort& c = scenario.cohorts[g];
                if (c.funding == Funding::Prepaid) {
                    i64 burn = static_cast<i64>(c.ordinary) * 25'000 + static_cast<i64>(c.high) * 450'000;
                    out.cashBurn += burn;
                    out.groups[g].cashBurn += burn;
                }
            }
        }

        for (int p = 0; p < kWindows; ++p) {
            const Terms& t = terms[p];
            i64 halfMain = mainBudget / 2;
            i64 halfHigh = highBudget / 2;
            i64 mainBase = p + 1 == kWindows ? halfMain : halfMain * (1 << (t.tier - 1)) / routineWeight;
            i64 highBase = p + 1 == kWindows ? halfHigh : halfHigh * (1 << (t.tier - 1)) / routineWeight;
            int rung = drawBoostQuarterMult(rng);
            u64 windowSeed = rng.next();
            ShooterCache dice(windowSeed);

            std::vector<ScoredRun> runs;
            runs.reserve(seats.size());
            for (std::size_t n = 0; n < seats.size(); ++n) {
                const Seat& seat = seats[n];
                u64 pk = keyed(seat.playerKey, static_cast<u64>(day), static_cast<u64>(p));
                Run run = settleRun(t, seat.strategy, dice, windowSeed, pk);
                runs.push_back(ScoredRun{run, seat.standing, keyed(windowSeed, static_cast<u64>(n), 0x71eULL)});

                i64 scale = seat.high ? highMult : 1;
                i64 bankrollRisk = t.bankroll * scale;
                i64 face = (t.bankroll + t.bounty) * scale;
                i64 engine = run.paid * scale;
                if (seat.high) {
                    dayHigh += bankrollRisk;
                    if (highHeads == 1) dayHigh += (highMult - 1) * t.bounty;
                } else {
                    dayRegular += bankrollRisk;
                }

                if (count) {
                    out.riskBankroll += bankrollRisk;
                    out.rawBankroll += static_cast<long double>(run.rawMoney) / kMoneyUnits * scale;
                    out.engineCredit += engine;
                    out.faceCost += face;
                    out.totalCredit += engine;
                    out.bountyPosted += t.bounty * scale;
                    if (run.stop == Stop::Bust) {
                        out.deletedOnBust += static_cast<long double>(run.rawMoney) / kMoneyUnits * scale;
                    }
                    GroupTotals& gt = out.groups[seat.group];
                    gt.faceCost += face;
                    gt.engineCredit += engine;
                    gt.totalCredit += engine;
                    if (seat.funding == Funding::Cash) {
                        out.cashBurn += face;
                        gt.cashBurn += face;
                    }
                }
            }

            if (seats.empty()) continue;

            std::size_t mainWinner = 0;
            for (std::size_t i = 1; i < runs.size(); ++i) if (better(runs[i], runs[mainWinner])) mainWinner = i;
            i64 mainBoost = paidBoost(mainBase, rung, seats[mainWinner].standing);
            // WHAT THE STANDING DENIED IS NOT UNMINTED. It is protocol money already allocated to
            // this window, so it goes into the pool — compared at the same rounding stage the
            // payment lands on, which is what makes credit plus rollover the full-standing award.
            i64 mainDenied = paidBoost(mainBase, rung, kScoreFloor) - mainBoost;
            pool += mainDenied;
            i64 mainBounties = t.bounty * static_cast<i64>(seats.size());
            i64 mainPot = mainBounties + mainBoost;
            if (count) {
                out.totalCredit += mainPot;
                out.bountyReturned += mainBounties;
                out.mainBoostPaid += mainBoost;
                splitAward(mainBoost, 0, out);
                out.progressiveRolled += mainDenied;
                dayBoostPaid += mainBoost;
                GroupTotals& gt = out.groups[seats[mainWinner].group];
                gt.potCredit += mainPot;
                gt.totalCredit += mainPot;
                gt.mainWins += 1;
            }

            // THE PROGRESSIVE. No draw of its own: the recipient is the winner the comparator
            // already named, the qualification is that winner's cumulative roll prefix against
            // this window's format, and a bust never qualifies however far it ran.
            // A ROUTINE GOAL VICTORY qualifies this day's event, whether or not it clears a
            // cutoff of its own — so it is recorded on the VICTORY, ahead of the award below.
            if (p + 1 != kWindows && runs[mainWinner].run.stop == Stop::Goal) {
                routineGoalWinner[mainWinner] = 1;
            }
            if (runs[mainWinner].run.stop == Stop::Goal) {
                int fi = progFormatIndex(t.depth, t.goalMult);
                int rolls = runs[mainWinner].run.rolls;
                i64 candidate = 0;
                bool rare;
                bool common;
                if (gHighWaterGoal) {
                    i64 scoreBps = highWaterBps(runs[mainWinner].run, t);
                    i64 commonBps = peakCommonBps(t.goalMult);
                    i64 rareBps = peakRareBps(t.goalMult);
                    rare = scoreBps >= rareBps;
                    common = scoreBps >= commonBps;
                } else {
                    rare = rolls >= kProgRare[fi];
                    common = rolls >= kProgCommon[fi];
                }
                // THE RUNG, COUNTED IN DOUBLINGS of the routine common share, exactly as the
                // contract counts it: rare is one doubling, the day's event two more, and a
                // repeat victory at the event one further.
                if (rare || common) {
                    int shift = rare ? kProgRareDoublings : 0;
                    if (p + 1 == kWindows) {
                        shift += kProgEventDoublings;
                        // THE REPEAT DOUBLE, on the event alone and never stacking past 2x.
                        if (routineGoalWinner[mainWinner]) ++shift;
                    }
                    candidate = poolShare(pool, kProgRoutineCommonBps << shift);
                }
                if (candidate > 0) {
                    // The candidate is ALREADY in the pool, so the curve applies to it directly
                    // and only the credit is deducted. What is denied never left.
                    i64 award = boostShare(candidate, seats[mainWinner].standing);
                    pool -= award;
                    if (count) {
                        out.totalCredit += award;
                        out.progressivePaid += award;
                        splitAward(award, 3, out);
                        if (rare) out.progressiveRareAwards += 1;
                        else out.progressiveCommonAwards += 1;
                        GroupTotals& gt = out.groups[seats[mainWinner].group];
                        gt.potCredit += award;
                        gt.totalCredit += award;
                    }
                }
            }

            if (highHeads == 1) {
                std::size_t h = 0;
                while (!seats[h].high) ++h;
                i64 laneBoost = paidBoost(highBase, rung, seats[h].standing);
                // The denied CAPITAL never gets on the table: it is banked before the dice are
                // consulted, so nothing here manufactures a return on money the curve refused.
                i64 laneDenied = paidBoost(highBase, rung, kScoreFloor) - laneBoost;
                pool += laneDenied;
                i64 extra = (highMult - 1) * t.bounty;
                i64 rider = runs[h].run.paid == 0 ? 0 : runs[h].run.paid * (extra + laneBoost) / t.bankroll;
                i64 boostPart = runs[h].run.paid == 0 ? 0 : runs[h].run.paid * laneBoost / t.bankroll;
                if (count) {
                    out.progressiveRolled += laneDenied;
                    out.totalCredit += rider;
                    out.bountyReturned += rider - boostPart;
                    out.highBoostPaid += boostPart;
                    splitAward(boostPart, 2, out);
                    dayBoostPaid += boostPart;
                    GroupTotals& gt = out.groups[seats[h].group];
                    gt.potCredit += rider;
                    gt.totalCredit += rider;
                    gt.highWins += 1;
                }
            } else if (highHeads >= 2) {
                std::size_t highWinner = std::numeric_limits<std::size_t>::max();
                for (std::size_t i = 0; i < seats.size(); ++i) {
                    if (!seats[i].high) continue;
                    if (highWinner == std::numeric_limits<std::size_t>::max() || better(runs[i], runs[highWinner])) highWinner = i;
                }
                i64 laneBoost = paidBoost(highBase, rung, seats[highWinner].standing);
                i64 laneDenied = paidBoost(highBase, rung, kScoreFloor) - laneBoost;
                pool += laneDenied;
                i64 laneBounties = static_cast<i64>(highHeads) * (highMult - 1) * t.bounty;
                i64 lanePot = laneBounties + laneBoost;
                if (count) {
                    out.progressiveRolled += laneDenied;
                    out.totalCredit += lanePot;
                    out.bountyReturned += laneBounties;
                    out.highBoostPaid += laneBoost;
                    splitAward(laneBoost, 1, out);
                    dayBoostPaid += laneBoost;
                    GroupTotals& gt = out.groups[seats[highWinner].group];
                    gt.potCredit += lanePot;
                    gt.totalCredit += lanePot;
                    gt.highWins += 1;
                }
            }
        }

        if (count) {
            out.actionRegular += dayRegular;
            out.actionHigh += dayHigh;
            out.linearTerm +=
                static_cast<long double>(dayRegular + dayHigh) * kActionBps / kBpsDenominator;
            out.dailyBoostPaid.push_back(dayBoostPaid);
            out.progressiveDaily.push_back(static_cast<long double>(pool));
        }
        history.pop_front();
        history.push_back({dayRegular, dayHigh});
    }
    out.progressiveEnd = static_cast<long double>(pool);
    return out;
}

struct Calibration {
    long double bankroll{};
    long double raw{};
    long double paid{};
    long double deleted{};
    long double busts{};
    long double goals{};
    long double hands{};
};

Calibration calibrate(Strategy strategy, int samples, u64 seed) {
    Rng rng(seed);
    Calibration c;
    for (int i = 0; i < samples; ++i) {
        Terms t;
        t.bankroll = 3'000;
        t.depth = 5;
        t.goalMult = rng.below(2) == 0 ? 5 : 20;
        t.round = t.bankroll / t.depth;
        t.goal = t.bankroll * t.goalMult;
        u64 runSeed = rng.next();
        ShooterCache dice(runSeed);
        Run r = settleRun(t, strategy, dice, runSeed, keyed(seed, static_cast<u64>(i), 0xca1ULL));
        c.bankroll += t.bankroll;
        c.raw += static_cast<long double>(r.rawMoney) / kMoneyUnits;
        c.paid += r.paid;
        if (r.stop == Stop::Bust) {
            c.deleted += static_cast<long double>(r.rawMoney) / kMoneyUnits;
            c.busts += 1;
        } else {
            c.goals += 1;
        }
        c.hands += r.hands;
    }
    return c;
}

Calibration calibrateFixed(Strategy strategy, int samples, u64 seed, int depth, int goalMult) {
    Rng rng(seed);
    Calibration c;
    for (int i = 0; i < samples; ++i) {
        Terms t;
        t.bankroll = 3'000;
        t.depth = depth;
        t.goalMult = goalMult;
        t.round = t.bankroll / t.depth;
        t.goal = t.bankroll * t.goalMult;
        u64 runSeed = rng.next();
        ShooterCache dice(runSeed);
        Run r = settleRun(t, strategy, dice, runSeed, keyed(seed, static_cast<u64>(i), 0xf1cedULL));
        c.bankroll += t.bankroll;
        c.raw += static_cast<long double>(r.rawMoney) / kMoneyUnits;
        c.paid += r.paid;
        if (r.stop == Stop::Bust) {
            c.deleted += static_cast<long double>(r.rawMoney) / kMoneyUnits;
            c.busts += 1;
        } else {
            c.goals += 1;
        }
        c.hands += r.hands;
    }
    return c;
}

i64 highWaterBps(const Run& r, const Terms& t) {
    __int128 numerator = static_cast<__int128>(r.peakMoney) * 10'000;
    __int128 denominator = static_cast<__int128>(t.bankroll) * kMoneyUnits;
    __int128 value = denominator == 0 ? 0 : numerator / denominator;
    if (value > std::numeric_limits<i64>::max()) return std::numeric_limits<i64>::max();
    return static_cast<i64>(value);
}

std::size_t inclusiveTailCount(const std::vector<i64>& xs, i64 threshold) {
    return static_cast<std::size_t>(std::count_if(xs.begin(), xs.end(), [&](int x) { return x >= threshold; }));
}

i64 rawTailThreshold(std::vector<i64> xs, std::size_t targetCount) {
    if (xs.empty()) return 0;
    std::sort(xs.begin(), xs.end());
    if (targetCount == 0) return xs.back() + 1;
    if (targetCount >= xs.size()) return xs.front();
    return xs[xs.size() - targetCount];
}

i64 bestSteppedThreshold(const std::vector<i64>& xs, std::size_t targetCount, i64 step) {
    if (xs.empty()) return 0;
    i64 raw = rawTailThreshold(xs, targetCount);
    i64 base = (raw / step) * step;
    i64 best = std::max<i64>(10'000, base);
    std::size_t bestError = std::numeric_limits<std::size_t>::max();
    i64 bestDistance = std::numeric_limits<i64>::max();
    // The tail count is monotone in the threshold, so the best stepped value must be adjacent to
    // the unrounded empirical quantile. Checking two steps on either side also handles ties.
    for (int offset = -2; offset <= 2; ++offset) {
        i64 threshold = std::max<i64>(10'000, base + offset * step);
        std::size_t got = inclusiveTailCount(xs, threshold);
        std::size_t error = got > targetCount ? got - targetCount : targetCount - got;
        i64 distance = std::abs(threshold - raw);
        if (error < bestError || (error == bestError && distance < bestDistance)) {
            best = threshold;
            bestError = error;
            bestDistance = distance;
        }
    }
    return best;
}

i64 integerPercentile(std::vector<i64> xs, long double q) {
    if (xs.empty()) return 0;
    std::sort(xs.begin(), xs.end());
    long double pos = q * static_cast<long double>(xs.size() - 1);
    return xs[static_cast<std::size_t>(std::llround(pos))];
}

template <std::size_t N>
int histogramPercentile(const std::array<u64, N>& counts, long double q) {
    u64 total = std::accumulate(counts.begin(), counts.end(), u64{0});
    if (total == 0) return 0;
    u64 target = static_cast<u64>(std::ceil(q * static_cast<long double>(total))) - 1;
    u64 seen = 0;
    for (std::size_t i = 0; i < counts.size(); ++i) {
        seen += counts[i];
        if (seen > target) return static_cast<int>(i);
    }
    return static_cast<int>(counts.size() - 1);
}

enum class MatrixComposition {
    AllRandom,
    AllSharp,
    HalfRandomSharp,
    StandardMixed,
    OneBounty
};

std::string_view matrixCompositionName(MatrixComposition c) {
    switch (c) {
        case MatrixComposition::AllRandom: return "all_random";
        case MatrixComposition::AllSharp: return "all_bankroll_pick";
        case MatrixComposition::HalfRandomSharp: return "half_random_half_bankroll_pick";
        case MatrixComposition::StandardMixed: return "standard_mixed";
        case MatrixComposition::OneBounty: return "one_bounty_vs_random";
    }
    return "unknown";
}

Strategy matrixStrategy(MatrixComposition c, int seat, int heads) {
    switch (c) {
        case MatrixComposition::AllRandom:
            return Strategy::Blank;
        case MatrixComposition::AllSharp:
            return Strategy::Sharp4;
        case MatrixComposition::HalfRandomSharp:
            return seat < (heads + 1) / 2 ? Strategy::Blank : Strategy::Sharp4;
        case MatrixComposition::StandardMixed: {
            if (seat < (heads + 1) / 2) return Strategy::Blank;
            constexpr std::array<Strategy, 4> picked{
                Strategy::Sharp4, Strategy::Mixed, Strategy::Pass, Strategy::Dark
            };
            return picked[static_cast<std::size_t>(seat - (heads + 1) / 2) % picked.size()];
        }
        case MatrixComposition::OneBounty:
            return seat == 0 ? Strategy::Bounty : Strategy::Blank;
    }
    return Strategy::Blank;
}

Scenario matrixScenario(MatrixComposition c, int heads) {
    Scenario s;
    s.name = std::string(matrixCompositionName(c)) + "_" + std::to_string(heads);
    if (c == MatrixComposition::AllRandom) {
        s.cohorts.push_back({"random", heads, 0, Strategy::Blank, 12, Funding::Cash});
    } else if (c == MatrixComposition::AllSharp) {
        s.cohorts.push_back({"bankroll_pick", heads, 0, Strategy::Sharp4, 12, Funding::Cash});
    } else if (c == MatrixComposition::HalfRandomSharp) {
        int random = (heads + 1) / 2;
        s.cohorts.push_back({"random", random, 0, Strategy::Blank, 12, Funding::Cash});
        s.cohorts.push_back({"bankroll_pick", heads - random, 0, Strategy::Sharp4, 12, Funding::Cash});
    } else if (c == MatrixComposition::OneBounty) {
        s.cohorts.push_back({"bounty_pick", 1, 0, Strategy::Bounty, 12, Funding::Cash});
        if (heads > 1) s.cohorts.push_back({"random", heads - 1, 0, Strategy::Blank, 12, Funding::Cash});
    } else {
        int random = (heads + 1) / 2;
        int left = heads - random;
        s.cohorts.push_back({"random", random, 0, Strategy::Blank, 12, Funding::Cash});
        constexpr std::array<Strategy, 4> picked{
            Strategy::Sharp4, Strategy::Mixed, Strategy::Pass, Strategy::Dark
        };
        constexpr std::array<const char*, 4> names{"sharp", "mixed", "pass", "dark"};
        for (int i = 0; i < 4; ++i) {
            int n = left / 4 + (i < left % 4 ? 1 : 0);
            if (n != 0) s.cohorts.push_back({names[i], n, 0, picked[i], 12, Funding::Cash});
        }
    }
    return s;
}

void printPopulationMatrix(int targetSeatsPerCell, u64 seed) {
    constexpr std::array<int, 8> heads{1, 2, 5, 10, 20, 40, 80, 160};
    constexpr std::array<int, 2> goals{5, 20};
    constexpr std::array<MatrixComposition, 5> compositions{
        MatrixComposition::AllRandom,
        MatrixComposition::AllSharp,
        MatrixComposition::HalfRandomSharp,
        MatrixComposition::StandardMixed,
        MatrixComposition::OneBounty
    };
    constexpr i64 recordFloorBps = 1'000'000; // Analysis baseline: 100x, pending product lock.
    constexpr int fieldsPerDay = 7;
    std::cout << "POPULATION_HEADER\tcomposition\theads\tgoal\tfields\tseats"
                 "\tengine_edge_pct\tgoal_seat_pct\tall_bust_field_pct"
                 "\trandom_winner_pct\tpicked_winner_pct\tbounty_winner_pct"
                 "\tcommon_field_pct\trare_field_pct\tcommon_per_entry_pct\trare_per_entry_pct"
                 "\twinner_peak_p95_x\twinner_peak_p995_x\tqualified_peak_p95_x\tqualified_peak_p995_x"
                 "\tending_p50_x\tending_p99_x\tmax_peak_x\tmax_ending_x"
                 "\tmean_hands\thands_p99\tmax_hands\tmean_rolls\trolls_p99\tmax_rolls"
                 "\tmean_work_units\twork_p99\tmax_work_units\tcap_seat_pct"
                 "\trecord_floor_x\trecord_hits\tfirst_year_record_hits\tfinal_record_x"
                 "\tdice_only_record_paid\tdice_only_record_pool_end\n";

    for (std::size_t ci = 0; ci < compositions.size(); ++ci) {
        MatrixComposition composition = compositions[ci];
        for (int n : heads) {
            int fields = std::clamp(targetSeatsPerCell / n, 3'000, 200'000);
            for (int goalMult : goals) {
                Terms t;
                t.bankroll = 3'000;
                t.depth = 5;
                t.goalMult = goalMult;
                t.round = t.bankroll / t.depth;
                t.goal = t.bankroll * t.goalMult;
                long double risk = 0;
                long double paid = 0;
                long double handsSum = 0;
                long double rollsSum = 0;
                long double workSum = 0;
                std::size_t goalSeats = 0;
                std::size_t cappedSeats = 0;
                std::size_t allBust = 0;
                std::size_t common = 0;
                std::size_t rare = 0;
                std::size_t randomWins = 0;
                std::size_t pickedWins = 0;
                std::size_t bountyWins = 0;
                std::size_t recordHits = 0;
                std::size_t firstYearRecordHits = 0;
                i64 record = 0;
                i64 maxPeak = 0;
                i64 maxEnding = 0;
                i64 maxHands = 0;
                i64 maxRolls = 0;
                i64 maxWork = 0;
                i64 recordPool = 10'000;
                i64 recordPaid = 0;
                int lastFundedDay = -1;
                int lastClaimDay = 0;
                std::vector<i64> winnerPeaks;
                std::vector<i64> qualifiedPeaks;
                std::vector<i64> endings;
                std::vector<i64> handCounts;
                std::vector<i64> rollCounts;
                std::vector<i64> workUnits;
                winnerPeaks.reserve(fields);
                qualifiedPeaks.reserve(fields);
                endings.reserve(static_cast<std::size_t>(fields) * n);
                handCounts.reserve(static_cast<std::size_t>(fields) * n);
                rollCounts.reserve(static_cast<std::size_t>(fields) * n);
                workUnits.reserve(static_cast<std::size_t>(fields) * n);
                Rng rng(keyed(seed, ci, static_cast<u64>(n), static_cast<u64>(goalMult)));

                for (int f = 0; f < fields; ++f) {
                    int day = f / fieldsPerDay;
                    while (lastFundedDay < day) {
                        ++lastFundedDay;
                        recordPool += 2'000;
                    }
                    u64 runSeed = rng.next();
                    ShooterCache dice(runSeed);
                    std::vector<ScoredRun> runs;
                    runs.reserve(n);
                    for (int p = 0; p < n; ++p) {
                        Strategy strategy = matrixStrategy(composition, p, n);
                        u64 playerKey = keyed(seed, static_cast<u64>(f), static_cast<u64>(p + 1),
                                              keyed(ci, n, goalMult));
                        Run run = settleRun(t, strategy, dice, runSeed, playerKey);
                        runs.push_back({run, kScoreFloor, keyed(runSeed, static_cast<u64>(p), 0x71eULL)});
                        risk += t.bankroll;
                        paid += run.paid;
                        handsSum += run.hands;
                        rollsSum += run.rolls;
                        i64 work = 7 + run.rolls / 6 + (run.paid != 0 ? 6 : 0);
                        workSum += work;
                        maxWork = std::max(maxWork, work);
                        maxHands = std::max<i64>(maxHands, run.hands);
                        maxRolls = std::max<i64>(maxRolls, run.rolls);
                        handCounts.push_back(run.hands);
                        rollCounts.push_back(run.rolls);
                        workUnits.push_back(work);
                        endings.push_back(run.paid * 10'000 / t.bankroll);
                        maxEnding = std::max(maxEnding, run.paid * 10'000 / t.bankroll);
                        maxPeak = std::max(maxPeak, highWaterBps(run, t));
                        if (run.stop == Stop::Goal) ++goalSeats;
                        if (run.capped) ++cappedSeats;
                    }
                    std::size_t winner = 0;
                    for (std::size_t p = 1; p < runs.size(); ++p) {
                        if (better(runs[p], runs[winner])) winner = p;
                    }
                    Strategy ws = matrixStrategy(composition, static_cast<int>(winner), n);
                    if (ws == Strategy::Blank) ++randomWins;
                    else if (ws == Strategy::Bounty) ++bountyWins;
                    else ++pickedWins;
                    i64 peak = highWaterBps(runs[winner].run, t);
                    winnerPeaks.push_back(peak);
                    if (runs[winner].run.stop != Stop::Goal) {
                        ++allBust;
                        continue;
                    }
                    qualifiedPeaks.push_back(peak);
                    if (peak >= peakRareBps(goalMult)) ++rare;
                    else if (peak >= peakCommonBps(goalMult)) ++common;
                    if (peak >= recordFloorBps && peak > record) {
                        record = peak;
                        ++recordHits;
                        if (f < fieldsPerDay * 365) ++firstYearRecordHits;
                        i64 elapsed = day > lastClaimDay ? day - lastClaimDay : 0;
                        i64 shareBps = std::min<i64>(7'500, 500 + elapsed * 50);
                        i64 claim = recordPool * shareBps / 10'000;
                        recordPool -= claim;
                        recordPaid += claim;
                        lastClaimDay = day;
                    }
                }

                long double seats = static_cast<long double>(fields) * n;
                auto pctFields = [&](std::size_t x) { return 100.0L * x / fields; };
                auto pctSeats = [&](std::size_t x) { return 100.0L * x / seats; };
                std::cout << "POPULATION\t" << matrixCompositionName(composition) << '\t' << n << '\t'
                          << goalMult << '\t' << fields << '\t' << static_cast<std::uint64_t>(seats) << '\t'
                          << static_cast<double>(100 * (risk - paid) / risk) << '\t'
                          << static_cast<double>(pctSeats(goalSeats)) << '\t'
                          << static_cast<double>(pctFields(allBust)) << '\t'
                          << static_cast<double>(pctFields(randomWins)) << '\t'
                          << static_cast<double>(pctFields(pickedWins)) << '\t'
                          << static_cast<double>(pctFields(bountyWins)) << '\t'
                          << static_cast<double>(pctFields(common)) << '\t'
                          << static_cast<double>(pctFields(rare)) << '\t'
                          << static_cast<double>(pctSeats(common)) << '\t'
                          << static_cast<double>(pctSeats(rare)) << '\t'
                          << static_cast<double>(integerPercentile(winnerPeaks, 0.95L) / 10'000.0L) << '\t'
                          << static_cast<double>(integerPercentile(winnerPeaks, 0.995L) / 10'000.0L) << '\t'
                          << static_cast<double>(integerPercentile(qualifiedPeaks, 0.95L) / 10'000.0L) << '\t'
                          << static_cast<double>(integerPercentile(qualifiedPeaks, 0.995L) / 10'000.0L) << '\t'
                          << static_cast<double>(integerPercentile(endings, 0.50L) / 10'000.0L) << '\t'
                          << static_cast<double>(integerPercentile(endings, 0.99L) / 10'000.0L) << '\t'
                          << static_cast<double>(maxPeak / 10'000.0L) << '\t'
                          << static_cast<double>(maxEnding / 10'000.0L) << '\t'
                          << static_cast<double>(handsSum / seats) << '\t'
                          << integerPercentile(handCounts, 0.99L) << '\t' << maxHands << '\t'
                          << static_cast<double>(rollsSum / seats) << '\t'
                          << integerPercentile(rollCounts, 0.99L) << '\t' << maxRolls << '\t'
                          << static_cast<double>(workSum / seats) << '\t'
                          << integerPercentile(workUnits, 0.99L) << '\t' << maxWork << '\t'
                          << static_cast<double>(pctSeats(cappedSeats)) << "\t100\t" << recordHits << '\t'
                          << firstYearRecordHits << '\t'
                          << static_cast<double>(record / 10'000.0L) << '\t'
                          << recordPaid << '\t' << recordPool << "\n";
            }
        }
    }
}

void printSystemMatrix(int days, u64 seed) {
    constexpr std::array<int, 8> heads{1, 2, 5, 10, 20, 40, 80, 160};
    constexpr std::array<MatrixComposition, 5> compositions{
        MatrixComposition::AllRandom,
        MatrixComposition::AllSharp,
        MatrixComposition::HalfRandomSharp,
        MatrixComposition::StandardMixed,
        MatrixComposition::OneBounty
    };
    std::cout << "SYSTEM_HEADER\tcomposition\theads\tdays\taction_per_day\trisk_bankroll_per_day"
                 "\tengine_credit_per_day\tengine_retention_per_day\tengine_edge_pct"
                 "\traw_main_allocation_per_day\tallocation_pct_action\tprogressive_funded_per_day"
                 "\tprogressive_paid_per_day\tladder_paid_per_day\tnet_accrual_after_allocation_per_day"
                 "\tnet_cash_per_day\tprogressive_pool_end\tcommon_per_year\trare_per_year\n";
    // THE PASS SPLIT'S REPORT rides the same matrix walk. Sources use the contract's frozen
    // numbering: 1 main ladder, 2 contested high, 3 sole rider, 4 progressive. Outstanding
    // pass-days assume ZERO redemption over the horizon — the upper bound on the float — and the
    // feedback column prices FULL redemption instead: every issued pass-day replayed at this
    // run's mean per-seat day action, times the schedule's 12% action rate, is what the split
    // hands back to future budgets.
    std::cout << "PASS_SPLIT_HEADER\tcomposition\theads"
                 "\tnormal_by_source_1_2_3_4\thigh_by_source_1_2_3_4"
                 "\tpasses_per_day\tpass_value_per_day\tliquid_change_per_day"
                 "\tthirty_high_caps_per_year\toutstanding_pass_days_end"
                 "\tredeemed_action_per_day\tbudget_feedback_per_day\n";
    for (std::size_t ci = 0; ci < compositions.size(); ++ci) {
        for (int n : heads) {
            Scenario s = matrixScenario(compositions[ci], n);
            Totals t = simulateScenario(s, days, 21, keyed(seed, 0x535953ULL, ci, n));
            long double d = t.days;
            long double action = t.actionRegular + t.actionHigh;
            long double retained = t.riskBankroll - t.engineCredit;
            long double allocation = t.mainBudget + t.highBudget;
            long double netAccrual = retained - allocation;
            long double ladderPaid = t.mainBoostPaid + t.highBoostPaid;
            std::cout << "SYSTEM\t" << matrixCompositionName(compositions[ci]) << '\t' << n << '\t' << days << '\t'
                      << static_cast<double>(action / d) << '\t'
                      << static_cast<double>(t.riskBankroll / d) << '\t'
                      << static_cast<double>(t.engineCredit / d) << '\t'
                      << static_cast<double>(retained / d) << '\t'
                      << static_cast<double>(100 * retained / t.riskBankroll) << '\t'
                      << static_cast<double>(allocation / d) << '\t'
                      << static_cast<double>(100 * allocation / action) << '\t'
                      << static_cast<double>(t.progressiveFunded / d) << '\t'
                      << static_cast<double>(t.progressivePaid / d) << '\t'
                      << static_cast<double>(ladderPaid / d) << '\t'
                      << static_cast<double>(netAccrual / d) << '\t'
                      << static_cast<double>((t.cashBurn - t.totalCredit) / d) << '\t'
                      << static_cast<double>(t.progressiveEnd) << '\t'
                      << static_cast<double>(365 * t.progressiveCommonAwards / d) << '\t'
                      << static_cast<double>(365 * t.progressiveRareAwards / d) << "\n";
            long double normals = 0;
            long double highs = 0;
            long double value = 0;
            for (int src = 0; src < 4; ++src) {
                normals += t.passNormal[src];
                highs += t.passHigh[src];
                value += t.passValue[src];
            }
            long double gross = t.mainBoostPaid + t.highBoostPaid + t.progressivePaid;
            long double meanOrdinaryDay = t.ordinarySeatDayAction / d;
            long double meanHighDay = t.highSeatDayAction / d;
            long double redeemedAction = (normals * meanOrdinaryDay + highs * meanHighDay) / d;
            std::cout << "PASS_SPLIT\t" << matrixCompositionName(compositions[ci]) << '\t' << n << '\t'
                      << static_cast<double>(t.passNormal[0]) << '/'
                      << static_cast<double>(t.passNormal[1]) << '/'
                      << static_cast<double>(t.passNormal[2]) << '/'
                      << static_cast<double>(t.passNormal[3]) << '\t'
                      << static_cast<double>(t.passHigh[0]) << '/'
                      << static_cast<double>(t.passHigh[1]) << '/'
                      << static_cast<double>(t.passHigh[2]) << '/'
                      << static_cast<double>(t.passHigh[3]) << '\t'
                      << static_cast<double>((normals + highs) / d) << '\t'
                      << static_cast<double>(value / d) << '\t'
                      << static_cast<double>((gross - value) / d) << '\t'
                      << static_cast<double>(365 * t.passCapHits / d) << '\t'
                      << static_cast<double>(normals + highs) << '\t'
                      << static_cast<double>(redeemedAction) << '\t'
                      << static_cast<double>(redeemedAction * kActionBps / kBpsDenominator) << "\n";
        }
    }
}

void printPeakJackpotCalibration(int samples, u64 seed, int depthFilter, int goalFilter) {
    constexpr std::array<int, 1> depths{5};
    constexpr std::array<int, 2> goals{5, 20};
    bool savedMode = gHighWaterGoal;
    std::cout << "PEAK_JACKPOT_HEADER\tdepth\tgoal_multiple\tsamples\tgoals"
                 "\told_common_roll_cutoff\told_common_tail_pct\told_rare_roll_cutoff\told_rare_tail_pct"
                 "\traw_common_start_bps\traw_rare_start_bps"
                 "\tbest_0p1pct_common_bps\tbest_0p1pct_common_tail_pct"
                 "\tbest_0p1pct_rare_bps\tbest_0p1pct_rare_tail_pct"
                 "\tbest_0p1x_common_bps\tbest_0p1x_common_tail_pct"
                 "\tbest_0p1x_rare_bps\tbest_0p1x_rare_tail_pct"
                 "\tpeak_p50_bps\tpeak_p90_bps\tpeak_p99_bps\tpeak_p999_bps"
                 "\tmean_peak_x_start\tmean_final_x_start\tmean_post_goal_hands"
                 "\tmean_post_goal_rolls\tmax_post_goal_hands\tmax_total_rolls\tcap_stops\n";
    for (int depth : depths) {
        for (int goalMult : goals) {
            if ((depthFilter != 0 && depth != depthFilter) || (goalFilter != 0 && goalMult != goalFilter)) {
                continue;
            }
            int fi = progFormatIndex(depth, goalMult);
            std::vector<i64> peaks;
            peaks.reserve(static_cast<std::size_t>(samples));
            std::size_t oldCommon = 0;
            std::size_t oldRare = 0;
            std::size_t goalsSeen = 0;
            long double peakSum = 0;
            long double finalSum = 0;
            long double postHands = 0;
            long double postRolls = 0;
            int maxPostHands = 0;
            int maxTotalRolls = 0;
            std::size_t capStops = 0;
            Rng rng(keyed(seed, static_cast<u64>(fi), 0x4a43414cULL));
            for (int i = 0; i < samples; ++i) {
                Terms t;
                t.bankroll = 3'000;
                t.depth = depth;
                t.goalMult = goalMult;
                t.round = t.bankroll / t.depth;
                t.goal = t.bankroll * t.goalMult;
                u64 runSeed = rng.next();
                u64 playerKey = keyed(seed, static_cast<u64>(fi), static_cast<u64>(i), 0x5045414bULL);
                ShooterCache dice(runSeed);
                gHighWaterGoal = false;
                Run oldRun = settleRun(t, Strategy::Blank, dice, runSeed, playerKey);
                gHighWaterGoal = true;
                Run newRun = settleRun(t, Strategy::Blank, dice, runSeed, playerKey);
                if (oldRun.stop != newRun.stop) {
                    throw std::runtime_error("high-water proposal changed pre-Goal qualification");
                }
                if (oldRun.stop != Stop::Goal) continue;
                ++goalsSeen;
                if (oldRun.rolls >= kProgCommon[fi]) ++oldCommon;
                if (oldRun.rolls >= kProgRare[fi]) ++oldRare;
                i64 bps = highWaterBps(newRun, t);
                peaks.push_back(bps);
                peakSum += static_cast<long double>(newRun.peakMoney)
                    / (static_cast<long double>(t.bankroll) * kMoneyUnits);
                finalSum += static_cast<long double>(newRun.rawMoney)
                    / (static_cast<long double>(t.bankroll) * kMoneyUnits);
                int extraHands = newRun.hands - newRun.goalHands;
                int extraRolls = newRun.rolls - newRun.goalRolls;
                postHands += extraHands;
                postRolls += extraRolls;
                maxPostHands = std::max(maxPostHands, extraHands);
                maxTotalRolls = std::max(maxTotalRolls, newRun.rolls);
                if (newRun.capped) ++capStops;
            }
            i64 rawCommon = rawTailThreshold(peaks, oldCommon);
            i64 rawRare = rawTailThreshold(peaks, oldRare);
            i64 fineCommon = bestSteppedThreshold(peaks, oldCommon, 10);
            i64 fineRare = bestSteppedThreshold(peaks, oldRare, 10);
            i64 wholeCommon = bestSteppedThreshold(peaks, oldCommon, 1'000);
            i64 wholeRare = bestSteppedThreshold(peaks, oldRare, 1'000);
            auto pct = [&](std::size_t n) {
                return goalsSeen == 0 ? 0.0L : 100.0L * static_cast<long double>(n) / goalsSeen;
            };
            std::cout << "PEAK_JACKPOT\t" << depth << '\t' << goalMult << '\t' << samples << '\t'
                      << goalsSeen << '\t' << kProgCommon[fi] << '\t' << static_cast<double>(pct(oldCommon))
                      << '\t' << kProgRare[fi] << '\t' << static_cast<double>(pct(oldRare))
                      << '\t' << rawCommon << '\t' << rawRare
                      << '\t' << fineCommon << '\t' << static_cast<double>(pct(inclusiveTailCount(peaks, fineCommon)))
                      << '\t' << fineRare << '\t' << static_cast<double>(pct(inclusiveTailCount(peaks, fineRare)))
                      << '\t' << wholeCommon << '\t' << static_cast<double>(pct(inclusiveTailCount(peaks, wholeCommon)))
                      << '\t' << wholeRare << '\t' << static_cast<double>(pct(inclusiveTailCount(peaks, wholeRare)))
                      << '\t' << integerPercentile(peaks, 0.50L) << '\t' << integerPercentile(peaks, 0.90L)
                      << '\t' << integerPercentile(peaks, 0.99L) << '\t' << integerPercentile(peaks, 0.999L)
                      << '\t' << static_cast<double>(goalsSeen == 0 ? 0 : peakSum / goalsSeen)
                      << '\t' << static_cast<double>(goalsSeen == 0 ? 0 : finalSum / goalsSeen)
                      << '\t' << static_cast<double>(goalsSeen == 0 ? 0 : postHands / goalsSeen)
                      << '\t' << static_cast<double>(goalsSeen == 0 ? 0 : postRolls / goalsSeen)
                      << '\t' << maxPostHands << '\t' << maxTotalRolls << '\t' << capStops << "\n";
        }
    }
    gHighWaterGoal = savedMode;
}

void printWinnerPeakCalibration(int fields, u64 seed, int depthFilter, int goalFilter) {
    constexpr std::array<int, 1> depths{5};
    constexpr std::array<int, 2> goals{5, 20};
    std::array<Strategy, 40> field{};
    int cursor = 0;
    for (int i = 0; i < 20; ++i) field[cursor++] = Strategy::Blank;
    for (int i = 0; i < 5; ++i) field[cursor++] = Strategy::Sharp4;
    for (int i = 0; i < 5; ++i) field[cursor++] = Strategy::Mixed;
    for (int i = 0; i < 5; ++i) field[cursor++] = Strategy::Pass;
    for (int i = 0; i < 5; ++i) field[cursor++] = Strategy::Dark;

    bool savedMode = gHighWaterGoal;
    gHighWaterGoal = true;
    std::vector<i64> aggregateWinnerPeaks;
    std::array<std::vector<i64>, 2> aggregatePeaksByGoal;
    std::size_t aggregateOldCommon = 0;
    std::size_t aggregateOldRare = 0;
    std::size_t aggregateFields = 0;
    i64 observedMaxPeakMoney = 0;
    i64 observedMaxPaid = 0;
    int observedMaxPeakGoal = 0;
    int observedMaxPeakStrategy = 0;
    int observedMaxPeakHands = 0;
    int observedMaxPeakRolls = 0;
    int observedMaxPaidGoal = 0;
    int observedMaxPaidStrategy = 0;
    int observedMaxPaidHands = 0;
    int observedMaxPaidRolls = 0;
    int observedMaxHands = 0;
    int observedMaxRolls = 0;
    i64 observedMaxWork = 0;
    std::cout << "WINNER_PEAK_HEADER\tdepth\tgoal_multiple\tfields\tgoal_fields"
                 "\told_common_fields\told_common_pct_all\told_rare_fields\told_rare_pct_all"
                 "\traw_common_start_bps\traw_rare_start_bps"
                 "\tbest_0p1x_common_bps\tbest_0p1x_common_pct_all"
                 "\tbest_0p1x_rare_bps\tbest_0p1x_rare_pct_all"
                 "\tsimple_2p5goal_common_bps\tsimple_2p5goal_common_pct_all"
                 "\tsimple_15goal_rare_bps\tsimple_15goal_rare_pct_all"
                 "\twinner_peak_p50_bps\twinner_peak_p90_bps\twinner_peak_p99_bps"
                 "\twinner_peak_p999_bps\twinner_changed_pct_goal_fields\tcap_stops"
                 "\tfloor_500x_pct_all\tfloor_1000x_pct_all\tfloor_2000x_pct_all"
                 "\tfloor_5000x_pct_all\tfloor_10000x_pct_all"
                 "\tfloor_20000x_pct_all\tfloor_50000x_pct_all\tfloor_100000x_pct_all\n";
    std::cout << "BOUNTY_COHORT_HEADER\tdepth\tgoal_multiple\tfields"
                 "\trandom_win_pct\tpicked_win_pct\tqualified_winner_pct"
                 "\tall_winner_peak_p90_bps\tall_winner_peak_p95_bps"
                 "\tall_winner_peak_p99_bps\tall_winner_peak_p995_bps"
                 "\tqualified_peak_p90_bps\tqualified_peak_p99_bps\n";
    std::cout << "CAP_STOP_HEADER\tdepth\tgoal_multiple\tfield\tseat\tstrategy\tfield_winner"
                 "\treason\thands\trolls\tgoal_hand\tgoal_roll\tpost_goal_hands"
                 "\tgoal_start_x\tceiling_entry_hand\tceiling_entry_start_x"
                 "\tpeak_hand\tpeak_start_x\tend_start_x\tpaid_start_x"
                 "\tnext_wager_start_x\tend_surplus_next_wagers\tmax_hand_gain_hand"
                 "\tmax_hand_gain_start_x\tpositive_hands\tnegative_hands\tflat_hands"
                 "\tboosted_hands\ttotal_handle_start_x\n";
    for (int depth : depths) {
        for (int goalMult : goals) {
            if ((depthFilter != 0 && depth != depthFilter) || (goalFilter != 0 && goalMult != goalFilter)) {
                continue;
            }
            int fi = progFormatIndex(depth, goalMult);
            std::vector<i64> winnerPeaks;
            winnerPeaks.reserve(static_cast<std::size_t>(fields));
            std::vector<i64> allWinnerPeaks;
            allWinnerPeaks.reserve(static_cast<std::size_t>(fields));
            std::size_t randomWinners = 0;
            std::size_t commonHits = 0;
            std::size_t rareHits = 0;
            std::size_t commonRandomHits = 0;
            std::size_t rareRandomHits = 0;
            std::size_t goalFields = 0;
            std::size_t oldCommon = 0;
            std::size_t oldRare = 0;
            std::size_t changedWinner = 0;
            std::size_t capStops = 0;
            std::array<u64, kMaxHands + 1> handHistogram{};
            std::array<u64, kRollBudget + kMaxRolls + 1> rollHistogram{};
            Rng rng(keyed(seed, static_cast<u64>(fi), 0x57494eULL));
            for (int f = 0; f < fields; ++f) {
                Terms t;
                t.bankroll = 3'000;
                t.depth = depth;
                t.goalMult = goalMult;
                t.round = t.bankroll / t.depth;
                t.goal = t.bankroll * t.goalMult;
                u64 runSeed = rng.next();
                ShooterCache dice(runSeed);
                std::array<ScoredRun, 40> runs;
                std::vector<std::size_t> cappedSeats;
                for (std::size_t n = 0; n < runs.size(); ++n) {
                    u64 playerKey = keyed(
                        seed, static_cast<u64>(fi), static_cast<u64>(f), static_cast<u64>(n + 1)
                    );
                    Run run = settleRun(t, field[n], dice, runSeed, playerKey);
                    observedMaxHands = std::max(observedMaxHands, run.hands);
                    observedMaxRolls = std::max(observedMaxRolls, run.rolls);
                    ++handHistogram[static_cast<std::size_t>(run.hands)];
                    ++rollHistogram[static_cast<std::size_t>(run.rolls)];
                    observedMaxWork = std::max(
                        observedMaxWork, i64{7} + run.rolls / 6 + (run.paid != 0 ? 6 : 0)
                    );
                    if (run.capped) {
                        ++capStops;
                        cappedSeats.push_back(n);
                    }
                    if (run.stop == Stop::Goal && run.peakMoney > observedMaxPeakMoney) {
                        observedMaxPeakMoney = run.peakMoney;
                        observedMaxPeakGoal = goalMult;
                        observedMaxPeakStrategy = static_cast<int>(field[n]);
                        observedMaxPeakHands = run.peakHands;
                        observedMaxPeakRolls = run.peakRolls;
                    }
                    if (run.stop == Stop::Goal && run.paid > observedMaxPaid) {
                        observedMaxPaid = run.paid;
                        observedMaxPaidGoal = goalMult;
                        observedMaxPaidStrategy = static_cast<int>(field[n]);
                        observedMaxPaidHands = run.hands;
                        observedMaxPaidRolls = run.rolls;
                    }
                    runs[n] = ScoredRun{
                        run, kScoreFloor, keyed(runSeed, static_cast<u64>(n), 0x71eULL)
                    };
                }
                std::size_t oldWinner = 0;
                std::size_t newWinner = 0;
                for (std::size_t n = 1; n < runs.size(); ++n) {
                    if (betterShippedFromHighWater(runs[n], runs[oldWinner])) oldWinner = n;
                    if (better(runs[n], runs[newWinner])) newWinner = n;
                }
                for (std::size_t n : cappedSeats) {
                    const Run& run = runs[n].run;
                    long double startMoney = static_cast<long double>(t.bankroll) * kMoneyUnits;
                    i64 nextQ = run.hands / gEscHands >= 62
                        ? gEscCap
                        : std::min(i64{1} << (run.hands / gEscHands), gEscCap);
                    i64 nextNeed = t.round * kMoneyUnits * nextQ;
                    long double surplusWagers = nextNeed == 0
                        ? 0
                        : static_cast<long double>(std::max(i64{0}, run.rawMoney - t.goal * kMoneyUnits))
                            / nextNeed;
                    std::cout << "CAP_STOP\t" << depth << '\t' << goalMult << '\t' << f << '\t' << n
                              << '\t' << strategyName(field[n]) << '\t' << (n == newWinner ? 1 : 0)
                              << '\t' << (run.hands == kMaxHands ? "hands" : "rolls")
                              << '\t' << run.hands << '\t' << run.rolls
                              << '\t' << run.goalHands << '\t' << run.goalRolls
                              << '\t' << run.hands - run.goalHands
                              << '\t' << static_cast<double>(run.goalMoney / startMoney)
                              << '\t' << run.ceilingEntryHand
                              << '\t' << static_cast<double>(run.ceilingEntryMoney / startMoney)
                              << '\t' << run.peakHands
                              << '\t' << static_cast<double>(run.peakMoney / startMoney)
                              << '\t' << static_cast<double>(run.rawMoney / startMoney)
                              << '\t' << static_cast<double>(run.paid / static_cast<long double>(t.bankroll))
                              << '\t' << static_cast<double>(nextNeed / startMoney)
                              << '\t' << static_cast<double>(surplusWagers)
                              << '\t' << run.maxHandGainHand
                              << '\t' << static_cast<double>(run.maxHandGainMoney / startMoney)
                              << '\t' << run.positiveHands << '\t' << run.negativeHands
                              << '\t' << run.flatHands << '\t' << run.boostedHands
                              << '\t' << static_cast<double>(run.units * t.round / static_cast<long double>(t.bankroll))
                              << "\n";
                }
                if (newWinner < 20) ++randomWinners;
                i64 winnerPeakBps = highWaterBps(runs[newWinner].run, t);
                allWinnerPeaks.push_back(winnerPeakBps);
                int matchedCommonBps = goalMult == 5 ? 250'000 : 500'000;
                int matchedRareBps = goalMult == 5 ? 1'200'000 : 2'250'000;
                if (runs[newWinner].run.stop == Stop::Goal && winnerPeakBps >= matchedCommonBps) {
                    ++commonHits;
                    if (newWinner < 20) ++commonRandomHits;
                }
                if (runs[newWinner].run.stop == Stop::Goal && winnerPeakBps >= matchedRareBps) {
                    ++rareHits;
                    if (newWinner < 20) ++rareRandomHits;
                }
                if (runs[oldWinner].run.stop != Stop::Goal) continue;
                ++goalFields;
                if (oldWinner != newWinner) ++changedWinner;
                int oldRolls = runs[oldWinner].run.goalRolls;
                if (oldRolls >= kProgCommon[fi]) ++oldCommon;
                if (oldRolls >= kProgRare[fi]) ++oldRare;
                winnerPeaks.push_back(highWaterBps(runs[newWinner].run, t));
            }
            i64 rawCommon = rawTailThreshold(winnerPeaks, oldCommon);
            i64 rawRare = rawTailThreshold(winnerPeaks, oldRare);
            i64 roundedCommon = bestSteppedThreshold(winnerPeaks, oldCommon, 1'000);
            i64 roundedRare = bestSteppedThreshold(winnerPeaks, oldRare, 1'000);
            i64 simpleCommon = peakCommonBps(goalMult);
            i64 simpleRare = peakRareBps(goalMult);
            aggregateWinnerPeaks.insert(
                aggregateWinnerPeaks.end(), winnerPeaks.begin(), winnerPeaks.end()
            );
            int aggregateGoalIndex = goalMult == 5 ? 0 : 1;
            aggregatePeaksByGoal[aggregateGoalIndex].insert(
                aggregatePeaksByGoal[aggregateGoalIndex].end(), winnerPeaks.begin(), winnerPeaks.end()
            );
            aggregateOldCommon += oldCommon;
            aggregateOldRare += oldRare;
            aggregateFields += static_cast<std::size_t>(fields);
            auto fieldPct = [&](std::size_t n) {
                return fields == 0 ? 0.0L : 100.0L * static_cast<long double>(n) / fields;
            };
            std::cout << "WINNER_PEAK\t" << depth << '\t' << goalMult << '\t' << fields << '\t'
                      << goalFields << '\t' << oldCommon << '\t' << static_cast<double>(fieldPct(oldCommon))
                      << '\t' << oldRare << '\t' << static_cast<double>(fieldPct(oldRare))
                      << '\t' << rawCommon << '\t' << rawRare
                      << '\t' << roundedCommon << '\t'
                      << static_cast<double>(fieldPct(inclusiveTailCount(winnerPeaks, roundedCommon)))
                      << '\t' << roundedRare << '\t'
                      << static_cast<double>(fieldPct(inclusiveTailCount(winnerPeaks, roundedRare)))
                      << '\t' << simpleCommon << '\t'
                      << static_cast<double>(fieldPct(inclusiveTailCount(winnerPeaks, simpleCommon)))
                      << '\t' << simpleRare << '\t'
                      << static_cast<double>(fieldPct(inclusiveTailCount(winnerPeaks, simpleRare)))
                      << '\t' << integerPercentile(winnerPeaks, 0.50L)
                      << '\t' << integerPercentile(winnerPeaks, 0.90L)
                      << '\t' << integerPercentile(winnerPeaks, 0.99L)
                      << '\t' << integerPercentile(winnerPeaks, 0.999L)
                      << '\t' << static_cast<double>(goalFields == 0 ? 0 : 100.0L * changedWinner / goalFields)
                      << '\t' << capStops
                      << '\t' << static_cast<double>(fieldPct(inclusiveTailCount(winnerPeaks, 5'000'000)))
                      << '\t' << static_cast<double>(fieldPct(inclusiveTailCount(winnerPeaks, 10'000'000)))
                      << '\t' << static_cast<double>(fieldPct(inclusiveTailCount(winnerPeaks, 20'000'000)))
                      << '\t' << static_cast<double>(fieldPct(inclusiveTailCount(winnerPeaks, 50'000'000)))
                      << '\t' << static_cast<double>(fieldPct(inclusiveTailCount(winnerPeaks, 100'000'000)))
                      << '\t' << static_cast<double>(fieldPct(inclusiveTailCount(winnerPeaks, 200'000'000)))
                      << '\t' << static_cast<double>(fieldPct(inclusiveTailCount(winnerPeaks, 500'000'000)))
                      << '\t' << static_cast<double>(fieldPct(inclusiveTailCount(winnerPeaks, 1'000'000'000)))
                      << "\n";
            std::cout << "BOUNTY_COHORT\t" << depth << '\t' << goalMult << '\t' << fields
                      << '\t' << static_cast<double>(100.0L * randomWinners / fields)
                      << '\t' << static_cast<double>(100.0L * (fields - randomWinners) / fields)
                      << '\t' << static_cast<double>(100.0L * goalFields / fields)
                      << '\t' << integerPercentile(allWinnerPeaks, 0.90L)
                      << '\t' << integerPercentile(allWinnerPeaks, 0.95L)
                      << '\t' << integerPercentile(allWinnerPeaks, 0.99L)
                      << '\t' << integerPercentile(allWinnerPeaks, 0.995L)
                      << '\t' << integerPercentile(winnerPeaks, 0.90L)
                      << '\t' << integerPercentile(winnerPeaks, 0.99L) << "\n";
            std::cout << "JACKPOT_MATCH\t" << depth << '\t' << goalMult << '\t' << fields
                      << '\t' << (goalMult == 5 ? 250'000 : 500'000)
                      << '\t' << (goalMult == 5 ? 1'200'000 : 2'250'000)
                      << '\t' << static_cast<double>(100.0L * commonHits / fields)
                      << '\t' << static_cast<double>(100.0L * rareHits / fields)
                      << '\t' << static_cast<double>(100.0L * commonRandomHits / (fields * 20.0L))
                      << '\t' << static_cast<double>(100.0L * (commonHits - commonRandomHits) / (fields * 20.0L))
                      << '\t' << static_cast<double>(100.0L * rareRandomHits / (fields * 20.0L))
                      << '\t' << static_cast<double>(100.0L * (rareHits - rareRandomHits) / (fields * 20.0L))
                      << "\n";
            std::cout << "RUN_LENGTH\t" << depth << '\t' << goalMult
                      << '\t' << static_cast<u64>(fields) * field.size()
                      << "\thands_p95\t" << histogramPercentile(handHistogram, 0.95L)
                      << "\thands_p99\t" << histogramPercentile(handHistogram, 0.99L)
                      << "\thands_p999\t" << histogramPercentile(handHistogram, 0.999L)
                      << "\thands_max\t" << histogramPercentile(handHistogram, 1.0L)
                      << "\trolls_p95\t" << histogramPercentile(rollHistogram, 0.95L)
                      << "\trolls_p99\t" << histogramPercentile(rollHistogram, 0.99L)
                      << "\trolls_p999\t" << histogramPercentile(rollHistogram, 0.999L)
                      << "\trolls_max\t" << histogramPercentile(rollHistogram, 1.0L) << "\n";
        }
    }
    if (!aggregateWinnerPeaks.empty()) {
        i64 common = bestSteppedThreshold(aggregateWinnerPeaks, aggregateOldCommon, 1'000);
        i64 rare = bestSteppedThreshold(aggregateWinnerPeaks, aggregateOldRare, 1'000);
        auto aggregatePct = [&](std::size_t n) {
            return aggregateFields == 0
                ? 0.0L
                : 100.0L * static_cast<long double>(n) / aggregateFields;
        };
        std::cout << "WINNER_PEAK_AGGREGATE\t" << aggregateFields
                  << '\t' << aggregateOldCommon
                  << '\t' << static_cast<double>(aggregatePct(aggregateOldCommon))
                  << '\t' << common
                  << '\t' << static_cast<double>(
                         aggregatePct(inclusiveTailCount(aggregateWinnerPeaks, common))
                     )
                  << '\t' << aggregateOldRare
                  << '\t' << static_cast<double>(aggregatePct(aggregateOldRare))
                  << '\t' << rare
                  << '\t' << static_cast<double>(
                         aggregatePct(inclusiveTailCount(aggregateWinnerPeaks, rare))
                     )
                  << "\n";
        for (int i = 0; i < 2; ++i) {
            int goal = i == 0 ? 5 : 20;
            std::cout << "WINNER_PEAK_UNIVERSAL_RATE\t" << goal
                      << '\t' << static_cast<double>(
                             100.0L * inclusiveTailCount(aggregatePeaksByGoal[i], common) / fields
                         )
                      << '\t' << static_cast<double>(
                             100.0L * inclusiveTailCount(aggregatePeaksByGoal[i], rare) / fields
                         )
                      << "\n";
        }
        long double startMoney = 3'000.0L * kMoneyUnits;
        std::cout << "WINNER_PEAK_OBSERVED_MAX\tpeak_start_x\t"
                  << static_cast<double>(observedMaxPeakMoney / startMoney)
                  << "\tpeak_flip\t" << static_cast<double>(observedMaxPeakMoney / kMoneyUnits)
                  << "\tgoal\t" << observedMaxPeakGoal
                  << "\tstrategy\t" << strategyName(static_cast<Strategy>(observedMaxPeakStrategy))
                  << "\thands_at_peak\t" << observedMaxPeakHands
                  << "\trolls_at_peak\t" << observedMaxPeakRolls
                  << "\tpaid_start_x\t" << static_cast<double>(observedMaxPaid / 3'000.0L)
                  << "\tpaid_flip\t" << observedMaxPaid
                  << "\tpaid_goal\t" << observedMaxPaidGoal
                  << "\tpaid_strategy\t" << strategyName(static_cast<Strategy>(observedMaxPaidStrategy))
                  << "\tpaid_hands\t" << observedMaxPaidHands
                  << "\tpaid_rolls\t" << observedMaxPaidRolls
                  << "\tmax_hands_any\t" << observedMaxHands
                  << "\tmax_rolls_any\t" << observedMaxRolls
                  << "\tmax_work_any\t" << observedMaxWork
                  << "\n";
    }
    gHighWaterGoal = savedMode;
}

void printSchedule(int samples, u64 seed) {
    Rng rng(seed);
    long double bank = 0;
    long double bounty = 0;
    long double cost = 0;
    long double highCost = 0;
    long double eventBank = 0;
    long double eventBounty = 0;
    for (int i = 0; i < samples; ++i) {
        i64 b = 0;
        i64 s = 0;
        for (int p = 0; p < kWindows; ++p) {
            Terms t = drawTerms(rng, p);
            b += t.bankroll;
            s += t.bounty;
            if (p + 1 == kWindows) {
                eventBank += t.bankroll;
                eventBounty += t.bounty;
            }
        }
        int h = rng.below(10) == 0 ? 100 : 10;
        bank += b;
        bounty += s;
        cost += b + s;
        highCost += static_cast<long double>(b + s) * h;
    }
    std::cout << "SCHEDULE\tmean_day_bankroll\tmean_day_bounty\tmean_day_face_cost\tmean_high_face_cost"
                 "\tmean_event_bankroll\tmean_event_bounty\n";
    std::cout << "SCHEDULE\t" << static_cast<double>(bank / samples) << '\t'
              << static_cast<double>(bounty / samples) << '\t' << static_cast<double>(cost / samples) << '\t'
              << static_cast<double>(highCost / samples) << '\t' << static_cast<double>(eventBank / samples) << '\t'
              << static_cast<double>(eventBounty / samples) << "\n";
}

std::vector<Scenario> scenarios() {
    using F = Funding;
    using S = Strategy;
    return {
        // Current fail-soft behavior: if neither its FLIP burn nor pass fallback works, the house
        // still receives one ordinary blank seat; the Vault does not.
        {"empty_unfunded", {{"house_comp", 1, 0, S::Blank, 12, F::FreePass}}, 0},
        {"cold_2_bodies_cash", {{"protocol", 2, 0, S::Blank, 12, F::Cash}}, 0},
        {"cold_2_bodies_pass", {{"protocol", 2, 0, S::Blank, 12, F::FreePass}}, 0},
        {"cold_vault_off", {{"house_comp", 1, 0, S::Blank, 12, F::FreePass}}, 0},
        {"cold_vault_sharp", {{"house", 1, 0, S::Blank, 12, F::Cash}, {"vault", 1, 0, S::Sharp4, 12, F::Cash}}, 0},
        {"cold_vault_dark", {{"house", 1, 0, S::Blank, 12, F::Cash}, {"vault", 1, 0, S::Dark, 12, F::Cash}}, 0},
        {"thin_3_sharp", {{"protocol", 2, 0, S::Blank, 12, F::Cash}, {"sharp", 3, 0, S::Sharp4, 12, F::Cash}}, 0},
        {"healthy_30_sharp", {{"protocol", 2, 0, S::Blank, 12, F::Cash}, {"sharp", 30, 0, S::Sharp4, 12, F::Cash}}, 0},
        {"healthy_vault_dark", {{"house", 1, 0, S::Blank, 12, F::Cash}, {"vault", 1, 0, S::Dark, 12, F::Cash}, {"sharp", 30, 0, S::Sharp4, 12, F::Cash}}, 0},
        {"healthy_30_blank", {{"protocol", 2, 0, S::Blank, 12, F::Cash}, {"casual", 30, 0, S::Blank, 12, F::Cash}}, 0},
        {"solo_high", {{"protocol", 2, 0, S::Blank, 12, F::Cash}, {"sharp", 20, 0, S::Sharp4, 12, F::Cash}, {"whale", 0, 1, S::Sharp4, 12, F::Cash}}, 0},
        {"contested_high", {{"protocol", 2, 0, S::Blank, 12, F::Cash}, {"sharp", 20, 0, S::Sharp4, 12, F::Cash}, {"whale", 0, 2, S::Sharp4, 12, F::Cash}}, 0},
        {"fresh_sybil_30", {{"protocol", 2, 0, S::Blank, 12, F::Cash}, {"fresh", 30, 0, S::Sharp4, 0, F::Cash}}, 0},
        {"fresh_sharp_into_31_blank", {{"incumbent", 31, 0, S::Blank, 12, F::Cash}, {"fresh", 1, 0, S::Sharp4, 0, F::Cash}}, 0},
        {"fresh_dark_into_31_blank", {{"incumbent", 31, 0, S::Blank, 12, F::Cash}, {"fresh", 1, 0, S::Dark, 0, F::Cash}}, 0},
        {"fresh_solo_no_bodies", {{"fresh", 1, 0, S::Sharp4, 0, F::Cash}}, 0},
        {"loyal_solo_no_bodies", {{"loyal", 1, 0, S::Sharp4, 12, F::Cash}}, 0},
        {"comped_20_passes", {{"protocol", 2, 0, S::Blank, 12, F::FreePass}, {"pass", 20, 0, S::Sharp4, 12, F::FreePass}}, 0},
        {"prepaid_20_days", {{"protocol", 2, 0, S::Blank, 12, F::Cash}, {"prepaid", 20, 0, S::Sharp4, 12, F::Prepaid}}, 0},
        {"one_body_high_pass", {{"body_normal", 1, 0, S::Blank, 12, F::Cash}, {"body_high", 0, 1, S::Blank, 12, F::FreePass}}, 0},
        {"vault_high_pass_dark", {{"house", 1, 0, S::Blank, 12, F::Cash}, {"vault", 0, 1, S::Dark, 12, F::FreePass}}, 0},
        {"two_body_high_passes", {{"body_high", 0, 2, S::Blank, 12, F::FreePass}}, 0},
        {"tail_100x_contested", {{"protocol", 2, 0, S::Blank, 12, F::Cash}, {"sharp", 10, 0, S::Sharp4, 12, F::Cash}, {"whale", 0, 2, S::Sharp4, 12, F::Cash}}, 100},
        // THE PROGRESSIVE'S CALIBRATION COHORT. Forty daily tickets, deliberately heterogeneous
        // and deliberately not efficient: twenty blank/random and five each of fixed place 4/10,
        // mixed, pass-heavy and 3:4 don't-pass-heavy. The weighted post-shooter edge this field
        // hands the table is well above the 16% an efficient one would, which is exactly why its
        // break-even head count is far below the policy figure — the participation equilibrium is
        // edge-dependent, not a universal number of players.
        {"mixed_40_cohort",
         {{"blank", 20, 0, S::Blank, 12, F::Cash},
          {"place410", 5, 0, S::Sharp4, 12, F::Cash},
          {"mixed", 5, 0, S::Mixed, 12, F::Cash},
          {"pass_heavy", 5, 0, S::Pass, 12, F::Cash},
          {"dont_pass_heavy", 5, 0, S::Dark, 12, F::Cash}},
         0},
    };
}

struct BoardSearchStats {
    std::size_t boardIndex{};
    long double wins{};
    long double bankroll{};
    long double paid{};
    long double faceCost{};
    long double potCredit{};
    long double trials{};
};

std::vector<ChipCounts> legalBoardChoices() {
    // Blank is a first-class legal choice in addition to every seven-chip selection.
    std::vector<ChipCounts> boards{ChipCounts{}};
    ChipCounts board{};
    auto walk = [&](auto&& self, int leg, int left) -> void {
        if (leg == 10) {
            if (left == 0 && !(board[0] != 0 && board[9] != 0)) boards.push_back(board);
            return;
        }
        int cap = std::min(4, left);
        for (int n = 0; n <= cap; ++n) {
            board[leg] = n;
            self(self, leg + 1, left - n);
        }
        board[leg] = 0;
    };
    walk(walk, 0, 7);
    return boards;
}

std::vector<ChipCounts> strategicField(std::string_view name) {
    std::vector<ChipCounts> field;
    auto fill = [&](Strategy s, int n) {
        ChipCounts c = pickedCounts(s);
        for (int i = 0; i < n; ++i) field.push_back(c);
    };
    if (name.starts_with("duel")) {
        int darkSeats = std::stoi(std::string(name.substr(4)));
        if (darkSeats < 0 || darkSeats > 31) {
            throw std::invalid_argument("duel field dark-seat count must be in 0..31");
        }
        ChipCounts light{};
        light[0] = 4;
        light[2] = 3;
        ChipCounts dark{};
        dark[2] = 3;
        dark[9] = 4;
        for (int i = 0; i < darkSeats; ++i) field.push_back(dark);
        for (int i = darkSeats; i < 31; ++i) field.push_back(light);
    } else if (name == "strategic_mix" || name == "adaptive_mix") {
        // A deliberately heterogeneous field, not random boards: every seat picks one of the
        // six hand-built responses used elsewhere in this model. Counts sum to 31.
        fill(Strategy::Sharp4, 6);
        fill(Strategy::FairSpread, 5);
        fill(Strategy::Mixed, 5);
        fill(Strategy::Pass, 5);
        fill(Strategy::Hardways, 5);
        fill(Strategy::Dark, 5);
    } else {
        Strategy s = strategyFromName(name);
        if (s == Strategy::FairControl) {
            throw std::invalid_argument("the no-scatter mathematical control is not a legal incumbent board");
        }
        fill(s, 31);
    }
    return field;
}

std::string boardText(const ChipCounts& board) {
    std::string out;
    for (int i = 0; i < 10; ++i) {
        if (i != 0) out += ',';
        out += std::to_string(board[i]);
    }
    return out;
}

long double boardSearchRoi(const BoardSearchStats& s) {
    return 100 * (s.paid + s.potCredit - s.faceCost) / s.faceCost;
}

long double boardSearchWinPct(const BoardSearchStats& s) {
    return 100 * s.wins / s.trials;
}

long double boardSearchEdge(const BoardSearchStats& s) {
    return 100 * (s.bankroll - s.paid) / s.bankroll;
}

std::vector<BoardSearchStats> evaluateBoardChoices(
    const std::vector<ChipCounts>& allBoards,
    const std::vector<std::size_t>& candidateIds,
    const std::vector<ChipCounts>& field,
    int samples,
    u64 seed
) {
    if (field.size() != 31) throw std::invalid_argument("board-search field must contain 31 incumbents");
    Rng rng(seed);
    std::deque<std::pair<i64, i64>> history(kBurnDays, {0, 0});
    std::vector<BoardSearchStats> stats(candidateIds.size());
    for (std::size_t i = 0; i < candidateIds.size(); ++i) stats[i].boardIndex = candidateIds[i];

    constexpr int warmupDays = 21;
    int counted = 0;
    int day = 0;
    u64 candidateOwner = keyed(seed, 0xcad1da7eULL);
    std::array<u64, 31> incumbentOwners{};
    for (std::size_t i = 0; i < incumbentOwners.size(); ++i) {
        incumbentOwners[i] = keyed(seed, 0x1ac0b3a7ULL, i);
    }

    while (counted < samples) {
        auto [rawMain, ignoredHighBudget] = drawBudgets(history);
        (void)ignoredHighBudget;
        // The LADDER half is what a board can actually race for. The progressive half is not on
        // any one window's table, and no board choice moves the roll prefix a winner qualifies on.
        i64 mainBudget = ladderHalf(rawMain);
        std::array<Terms, kWindows> terms;
        int routineWeight = 0;
        i64 dayBankroll = 0;
        for (int p = 0; p < kWindows; ++p) {
            terms[p] = drawTerms(rng, p);
            dayBankroll += terms[p].bankroll;
            if (p + 1 < kWindows) routineWeight += 1 << (terms[p].tier - 1);
        }

        if (day >= warmupDays) {
            for (int p = 0; p < kWindows && counted < samples; ++p, ++counted) {
                const Terms& t = terms[p];
                i64 halfMain = mainBudget / 2;
                i64 mainBase = p + 1 == kWindows
                    ? halfMain
                    : halfMain * (1 << (t.tier - 1)) / routineWeight;
                // The rung is independent of board choice and of the race score. Integrating its
                // exact four-point distribution here eliminates needless 100x-rung Monte Carlo
                // noise when comparing thousands of boards.
                long double pot = 32 * t.bounty + expectedPaidBoost(mainBase, kScoreFloor);
                u64 windowSeed = rng.next();
                ShooterCache dice(windowSeed);

                ScoredRun fieldBest;
                bool haveFieldBest = false;
                for (std::size_t i = 0; i < field.size(); ++i) {
                    u64 pk = keyed(incumbentOwners[i], static_cast<u64>(day), static_cast<u64>(p));
                    Run run = settleBoardChoice(t, field[i], dice, windowSeed, pk);
                    ScoredRun scored{run, kScoreFloor, keyed(windowSeed, i, 0x71eULL)};
                    if (!haveFieldBest || better(scored, fieldBest)) {
                        fieldBest = scored;
                        haveFieldBest = true;
                    }
                }

                u64 candidateKey = keyed(candidateOwner, static_cast<u64>(day), static_cast<u64>(p));
                u64 candidateTie = keyed(windowSeed, 31, 0x71eULL);
                for (std::size_t i = 0; i < candidateIds.size(); ++i) {
                    Run run = settleBoardChoice(
                        t, allBoards[candidateIds[i]], dice, windowSeed, candidateKey
                    );
                    ScoredRun scored{run, kScoreFloor, candidateTie};
                    BoardSearchStats& s = stats[i];
                    s.trials += 1;
                    s.bankroll += t.bankroll;
                    s.paid += run.paid;
                    s.faceCost += t.bankroll + t.bounty;
                    if (better(scored, fieldBest)) {
                        s.wins += 1;
                        s.potCredit += pot;
                    }
                }
            }
        }

        history.pop_front();
        history.push_back({dayBankroll * 32, 0});
        ++day;
    }
    return stats;
}

void printBoardSearch(
    std::string_view fieldName,
    int screenSamples,
    int refineSamples,
    int rows,
    u64 seed
) {
    std::vector<ChipCounts> boards = legalBoardChoices();
    std::vector<ChipCounts> field = strategicField(fieldName);
    std::vector<std::size_t> allIds(boards.size());
    std::iota(allIds.begin(), allIds.end(), std::size_t{0});
    std::vector<BoardSearchStats> screened = evaluateBoardChoices(
        boards, allIds, field, screenSamples, keyed(seed, 0x5c433aULL)
    );

    std::vector<bool> keep(boards.size(), false);
    auto retain = [&](auto metric, int n, bool descending) {
        std::vector<std::size_t> order(screened.size());
        std::iota(order.begin(), order.end(), std::size_t{0});
        std::sort(order.begin(), order.end(), [&](std::size_t a, std::size_t b) {
            long double av = metric(screened[a]);
            long double bv = metric(screened[b]);
            return descending ? av > bv : av < bv;
        });
        n = std::min(n, static_cast<int>(order.size()));
        for (int i = 0; i < n; ++i) keep[screened[order[i]].boardIndex] = true;
    };
    // Preserve candidates that screen well on tournament value, race frequency, or engine return.
    // This makes the refinement robust to the rare 100x boost rung in the first pass.
    retain(boardSearchRoi, 512, true);
    retain(boardSearchWinPct, 256, true);
    retain(boardSearchEdge, 256, false);

    std::vector<std::pair<std::string_view, ChipCounts>> probes;
    probes.push_back({"blank", ChipCounts{}});
    ChipCounts light5{};
    light5[0] = 4;
    light5[2] = 3;
    probes.push_back({"pass4_place5_3", light5});
    ChipCounts dark5{};
    dark5[2] = 3;
    dark5[9] = 4;
    probes.push_back({"dont4_place5_3", dark5});
    ChipCounts fair59{};
    fair59[2] = 4;
    fair59[5] = 3;
    probes.push_back({"place5_4_place9_3", fair59});
    for (const auto& [label, probe] : probes) {
        (void)label;
        auto it = std::find(boards.begin(), boards.end(), probe);
        if (it != boards.end()) keep[static_cast<std::size_t>(it - boards.begin())] = true;
    }
    std::vector<std::size_t> refineIds;
    for (std::size_t i = 0; i < keep.size(); ++i) if (keep[i]) refineIds.push_back(i);

    std::vector<BoardSearchStats> refined = evaluateBoardChoices(
        boards, refineIds, field, refineSamples, keyed(seed, 0x7ef1aeULL)
    );
    std::sort(refined.begin(), refined.end(), [](const BoardSearchStats& a, const BoardSearchStats& b) {
        return boardSearchRoi(a) > boardSearchRoi(b);
    });

    std::cout << "BOARD_SEARCH_HEADER\tfield\tlegal_boards\tscreen_samples\trefined_boards"
                 "\trefine_samples\tdont_profit_ratio\taction_divisor\n";
    std::cout << "BOARD_SEARCH\t" << fieldName << '\t' << boards.size() << '\t' << screenSamples << '\t'
              << refineIds.size() << '\t' << refineSamples << '\t' << gDontProfitNum << '/' << gDontProfitDen
              << '\t' << kActionBps << "\n";
    std::cout << "BOARD_RESULT_HEADER\trank\tboard_pass_p4_p5_p6_p8_p9_p10_h4_h8_dp"
                 "\tmain_win_pct\tengine_edge_pct\tplayer_roi_pct\n";
    rows = std::min(rows, static_cast<int>(refined.size()));
    for (int i = 0; i < rows; ++i) {
        const BoardSearchStats& s = refined[i];
        std::cout << "BOARD_RESULT\t" << (i + 1) << '\t' << boardText(boards[s.boardIndex]) << '\t'
                  << static_cast<double>(boardSearchWinPct(s)) << '\t'
                  << static_cast<double>(boardSearchEdge(s)) << '\t'
                  << static_cast<double>(boardSearchRoi(s)) << "\n";
    }
    std::cout << "BOARD_PROBE_HEADER\tlabel\tboard_pass_p4_p5_p6_p8_p9_p10_h4_h8_dp"
                 "\tmain_win_pct\tengine_edge_pct\tplayer_roi_pct\n";
    for (const auto& [label, probe] : probes) {
        auto boardIt = std::find(boards.begin(), boards.end(), probe);
        std::size_t boardIndex = static_cast<std::size_t>(boardIt - boards.begin());
        auto resultIt = std::find_if(refined.begin(), refined.end(), [&](const BoardSearchStats& s) {
            return s.boardIndex == boardIndex;
        });
        if (resultIt == refined.end()) continue;
        std::cout << "BOARD_PROBE\t" << label << '\t' << boardText(probe) << '\t'
                  << static_cast<double>(boardSearchWinPct(*resultIt)) << '\t'
                  << static_cast<double>(boardSearchEdge(*resultIt)) << '\t'
                  << static_cast<double>(boardSearchRoi(*resultIt)) << "\n";
    }
}

// THE FUNDING RULE, END TO END, as arithmetic rather than as a sample. Everything here is a
// division: it fixes the curve the contract tests and the documentation are held to, so a change
// to the rate or the base shows up in one place before any simulated day is run.
void printEquilibriumTable() {
    // The 100-million-run-per-cell equal random/picked, equal-Goal calibration, and the exact
    // expected bankroll action of seven scheduled windows. Bounties are excluded from action.
    constexpr long double kTakePct = 17.27590775L;
    constexpr long double kTicketAction = 15'622.5L;
    const long double residual = kTicketAction * (kTakePct - 12.0L) / 100.0L;

    // THE SPLIT DOES NOT MOVE THIS CURVE. A wei banked in the progressive is a wei allocated: it
    // becomes a liability the moment it lands there, and its later payout releases that liability
    // rather than issuing again. So the emission below is the WHOLE main allocation.
    std::cout << "EQUILIBRIUM_HEADER\ttickets\taction\tengine_take_at_equal_mix_17p2759pct\tallocation_base_plus_rate"
                 "\tladder_half\tprogressive_half\tnet_issuance\n";
    for (int tickets : {0, 2, 16, 40, 50, 60, 61, 77, 98}) {
        long double action = static_cast<long double>(tickets) * kTicketAction;
        long double take = action * kTakePct / 100.0L;
        long double bonus = gMainBase + action * kActionBps / kBpsDenominator;
        std::cout << "EQUILIBRIUM\t" << tickets << '\t' << action << '\t' << take << '\t' << bonus << '\t'
                  << bonus / 2.0L << '\t' << bonus / 2.0L << '\t' << (bonus - take) << "\n";
    }
    std::cout << "EQUILIBRIUM_NOTE\tresidual_burn_per_ticket\t" << residual
              << "\tbreak_even_tickets\t" << (static_cast<long double>(gMainBase) / residual)
              << "\tbase\t" << gMainBase
              << "\trate_bps\t" << kActionBps << "\n";

    // THE TWO LANES, RATED THE SAME AND NEVER SHARING A WEI. Regular action pays 12% into the
    // main lane; high action pays 4.8% there and 7.2% into its own. A mixed day is booked once.
    std::cout << "LANES_HEADER\tregular_action\thigh_action\traw_main_allocation\tladder_half"
                 "\tprogressive_half\thigh_budget\tlinear_total\trate_bps_of_action\n";
    for (auto [reg, high] : std::vector<std::pair<i64, i64>>{
             {1'000'000, 0}, {0, 1'000'000}, {500'000, 500'000}, {200'000, 100'000}}) {
        std::deque<std::pair<i64, i64>> h(kBurnDays, {reg, high});
        auto [m, hi] = drawBudgets(h);
        i64 linear = m - gMainBase + hi;
        i64 total = reg + high;
        std::cout << "LANES\t" << reg << '\t' << high << '\t' << m << '\t' << ladderHalf(m) << '\t'
                  << progressiveHalf(m) << '\t' << hi << '\t' << linear << '\t'
                  << (total == 0 ? 0 : linear * 10'000 / total) << "\n";
    }
}

void printShockTable() {
    std::deque<std::pair<i64, i64>> h(kBurnDays, {1'000'000, 0});
    // A SHUTDOWN IS A SEVEN-DAY LAG, NOT A LEAK. The window is the seven days BEHIND the day it
    // opens, so a table that empties overnight keeps paying its old rate down a ramp for a week
    // and then sits on the base. Every row below is the rule applied to a shrinking window.
    std::cout << "SHOCK_HEADER\tday\tregular_action\thigh_action\tmain_budget\thigh_budget\n";
    for (int day = 0; day < 10; ++day) {
        auto [m, hi] = drawBudgets(h);
        i64 reg = 0;
        i64 high = 0;
        std::cout << "SHOCK_shutdown\t" << day << '\t' << reg << '\t' << high << '\t' << m << '\t' << hi << "\n";
        h.pop_front();
        h.push_back({reg, high});
    }

    h.assign(kBurnDays, {0, 0});
    h.back() = {0, 10'000'000};
    for (int day = 0; day < 9; ++day) {
        auto [m, hi] = drawBudgets(h);
        std::cout << "SHOCK_high_10m\t" << day << "\t0\t0\t" << m << '\t' << hi << "\n";
        h.pop_front();
        h.push_back({0, 0});
    }
}

void usage(const char* argv0) {
    std::cerr << "Usage: " << argv0
              << " [--days N] [--worlds N] [--calibration N] [--schedule N] [--settings N]"
                 " [--setting-depths a,b,c] [--setting-goals x,y]"
                 " [--high-water-goal 0|1] [--jackpot-calibration N]"
                 " [--winner-calibration N]"
                 " [--bounty-matchup N]"
                 " [--population-matrix-seats N] [--system-matrix-days N]"
                 " [--jackpot-depth 5] [--jackpot-goal 5|20]"
                 " [--settings-strategy STRATEGY] [--dont-profit-num N] [--dont-profit-den N]"
                 " [--main-base FLIP]"
                 " [--esc-hands N] [--esc-cap N]"
                 " [--boosted-shooters-pct N] [--winnings-boost-pct N]"
                 " [--winnings-boost-mode all|random]"
                 " [--random-boosted-shooters-pct N] [--picked-boosted-shooters-pct N]"
                 " [--random-goal5-shooters-pct N] [--random-goal20-shooters-pct N]"
                 " [--picked-goal5-shooters-pct N] [--picked-goal20-shooters-pct N]"
                 " [--random-winnings-boost-pct N] [--picked-winnings-boost-pct N]"
                 " [--random-winnings-boost-jitter-pct N] [--picked-winnings-boost-jitter-pct N]"
                 " [--random-goal5-boost-bps N] [--random-goal20-boost-bps N]"
                 " [--picked-goal5-boost-bps N] [--picked-goal20-boost-bps N]"
                 " [--board-search N] [--search-refine N]"
                 " [--search-field STRATEGY|strategic_mix|duelN]"
                 " [--search-top N]"
                 " [--seed N] [--scenario NAME]"
                 " [--matchup-incumbent STRATEGY] [--matchup-candidate STRATEGY]\n";
}

} // namespace

int main(int argc, char** argv) {
    int days = 10'000;
    int worlds = 0;
    int calibrationSamples = 250'000;
    int scheduleSamples = 500'000;
    int settingSamples = 0;
    std::string settingDepthsArg;
    std::string settingGoalsArg;
    int boardSearchSamples = 0;
    int searchRefineSamples = 0;
    int searchTop = 20;
    int jackpotCalibrationSamples = 0;
    int winnerCalibrationFields = 0;
    int bountyMatchupFields = 0;
    int populationMatrixSeats = 0;
    int systemMatrixDays = 0;
    int jackpotDepthFilter = 0;
    int jackpotGoalFilter = 0;
    u64 seed = 20'260'826ULL;
    std::string scenarioFilter;
    std::string settingStrategyFilter;
    std::string matchupIncumbentFilter;
    std::string matchupCandidateFilter;
    std::string searchField = "sharp";
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--help" || arg == "-h") {
            usage(argv[0]);
            return 0;
        }
        if (i + 1 >= argc) {
            usage(argv[0]);
            return 2;
        }
        if (arg == "--days") days = std::stoi(argv[++i]);
        else if (arg == "--worlds") worlds = std::stoi(argv[++i]);
        else if (arg == "--calibration") calibrationSamples = std::stoi(argv[++i]);
        else if (arg == "--schedule") scheduleSamples = std::stoi(argv[++i]);
        else if (arg == "--settings") settingSamples = std::stoi(argv[++i]);
        else if (arg == "--setting-depths") settingDepthsArg = argv[++i];
        else if (arg == "--setting-goals") settingGoalsArg = argv[++i];
        else if (arg == "--high-water-goal") gHighWaterGoal = std::stoi(argv[++i]) != 0;
        else if (arg == "--jackpot-calibration") jackpotCalibrationSamples = std::stoi(argv[++i]);
        else if (arg == "--winner-calibration") winnerCalibrationFields = std::stoi(argv[++i]);
        else if (arg == "--bounty-matchup") bountyMatchupFields = std::stoi(argv[++i]);
        else if (arg == "--population-matrix-seats") populationMatrixSeats = std::stoi(argv[++i]);
        else if (arg == "--system-matrix-days") systemMatrixDays = std::stoi(argv[++i]);
        else if (arg == "--jackpot-depth") jackpotDepthFilter = std::stoi(argv[++i]);
        else if (arg == "--jackpot-goal") {
            jackpotGoalFilter = std::stoi(argv[++i]);
            gDrawGoalFilter = jackpotGoalFilter;
        }
        else if (arg == "--settings-strategy") settingStrategyFilter = argv[++i];
        else if (arg == "--board-search") boardSearchSamples = std::stoi(argv[++i]);
        else if (arg == "--search-refine") searchRefineSamples = std::stoi(argv[++i]);
        else if (arg == "--search-field") searchField = argv[++i];
        else if (arg == "--search-top") searchTop = std::stoi(argv[++i]);
        else if (arg == "--dont-profit-num") gDontProfitNum = std::stoi(argv[++i]);
        else if (arg == "--dont-profit-den") gDontProfitDen = std::stoi(argv[++i]);
        else if (arg == "--main-base") gMainBase = std::stoll(argv[++i]);
        else if (arg == "--esc-hands") gEscHands = std::stoi(argv[++i]);
        else if (arg == "--esc-cap") gEscCap = std::stoll(argv[++i]);
        else if (arg == "--boosted-shooters-pct") gBoostedShootersPct = std::stoi(argv[++i]);
        else if (arg == "--winnings-boost-pct") gWinningsBoostPct = std::stoi(argv[++i]);
        else if (arg == "--random-boosted-shooters-pct") {
            gRandomBoostedShootersPct = std::stoi(argv[++i]);
        }
        else if (arg == "--picked-boosted-shooters-pct") {
            gPickedBoostedShootersPct = std::stoi(argv[++i]);
        }
        else if (arg == "--random-goal5-shooters-pct") {
            gRandomGoal5ShooterPct = std::stoi(argv[++i]);
        }
        else if (arg == "--random-goal20-shooters-pct" || arg == "--random-goal10-shooters-pct") {
            gRandomGoal10ShooterPct = std::stoi(argv[++i]);
        }
        else if (arg == "--random-goal50-shooters-pct") {
            gRandomGoal50ShooterPct = std::stoi(argv[++i]);
        }
        else if (arg == "--picked-goal5-shooters-pct") {
            gPickedGoal5ShooterPct = std::stoi(argv[++i]);
        }
        else if (arg == "--picked-goal20-shooters-pct" || arg == "--picked-goal10-shooters-pct") {
            gPickedGoal10ShooterPct = std::stoi(argv[++i]);
        }
        else if (arg == "--picked-goal50-shooters-pct") {
            gPickedGoal50ShooterPct = std::stoi(argv[++i]);
        }
        else if (arg == "--random-winnings-boost-pct") {
            gRandomWinningsBoostPct = std::stoi(argv[++i]);
        }
        else if (arg == "--picked-winnings-boost-pct") {
            gPickedWinningsBoostPct = std::stoi(argv[++i]);
        }
        else if (arg == "--random-winnings-boost-jitter-pct") {
            gRandomWinningsBoostJitterPct = std::stoi(argv[++i]);
        }
        else if (arg == "--picked-winnings-boost-jitter-pct") {
            gPickedWinningsBoostJitterPct = std::stoi(argv[++i]);
        }
        else if (arg == "--random-goal5-boost-bps") {
            gRandomGoal5WinningsBoostBps = std::stoi(argv[++i]);
        }
        else if (arg == "--random-goal20-boost-bps" || arg == "--random-goal10-boost-bps") {
            gRandomGoal10WinningsBoostBps = std::stoi(argv[++i]);
        }
        else if (arg == "--random-goal50-boost-bps") {
            gRandomGoal50WinningsBoostBps = std::stoi(argv[++i]);
        }
        else if (arg == "--picked-goal5-boost-bps") {
            gPickedGoal5WinningsBoostBps = std::stoi(argv[++i]);
        }
        else if (arg == "--picked-goal20-boost-bps" || arg == "--picked-goal10-boost-bps") {
            gPickedGoal10WinningsBoostBps = std::stoi(argv[++i]);
        }
        else if (arg == "--picked-goal50-boost-bps") {
            gPickedGoal50WinningsBoostBps = std::stoi(argv[++i]);
        }
        else if (arg == "--winnings-boost-mode") {
            std::string mode = argv[++i];
            if (mode == "all") gWinningsBoostMode = WinningsBoostMode::All;
            else if (mode == "random" || mode == "blank") {
                gWinningsBoostMode = WinningsBoostMode::RandomTickets;
            } else {
                throw std::invalid_argument("winnings boost mode must be all or random");
            }
        }
        else if (arg == "--dont-profit-sixths") {
            // Backward-compatible shorthand retained for reproducing earlier sweeps.
            gDontProfitNum = std::stoi(argv[++i]);
            gDontProfitDen = 6;
        }
        else if (arg == "--seed") seed = static_cast<u64>(std::stoull(argv[++i]));
        else if (arg == "--scenario") scenarioFilter = argv[++i];
        else if (arg == "--matchup-incumbent") matchupIncumbentFilter = argv[++i];
        else if (arg == "--matchup-candidate") matchupCandidateFilter = argv[++i];
        else {
            usage(argv[0]);
            return 2;
        }
    }
    if (days <= 0 || calibrationSamples <= 0 || scheduleSamples <= 0 || settingSamples < 0
        || jackpotCalibrationSamples < 0
        || winnerCalibrationFields < 0
        || bountyMatchupFields < 0
        || populationMatrixSeats < 0
        || systemMatrixDays < 0
        || boardSearchSamples < 0 || searchRefineSamples < 0 || searchTop <= 0) {
        throw std::invalid_argument("sample counts must be positive (settings may be zero)");
    }
    if (gDontProfitNum < 0 || gDontProfitDen <= 0 || gDontProfitNum > gDontProfitDen
        || kMoneyUnits % gDontProfitDen != 0) {
        throw std::invalid_argument("Don't Pass ratio must satisfy 0 <= numerator <= denominator and divide 1200");
    }
    if (gMainBase < 0) throw std::invalid_argument("main base cannot be negative");
    if (gEscHands <= 0 || gEscHands > 16) throw std::invalid_argument("esc-hands must be in 1..16");
    if (gEscCap <= 0 || gEscCap > 0xFFFFFFFFLL) {
        throw std::invalid_argument("esc-cap must be in 1..4294967295");
    }
    if (jackpotDepthFilter != 0 && jackpotDepthFilter != 2 && jackpotDepthFilter != 5
        && jackpotDepthFilter != 10) {
        throw std::invalid_argument("jackpot depth must be 2, 5, or 10");
    }
    if (jackpotGoalFilter != 0 && jackpotGoalFilter != 5 && jackpotGoalFilter != 20) {
        throw std::invalid_argument("jackpot goal must be 5 or 20");
    }
    if (gBoostedShootersPct < 0 || gBoostedShootersPct > 100
        || gWinningsBoostPct < 0 || gWinningsBoostPct > 100
        || gRandomBoostedShootersPct < -1 || gRandomBoostedShootersPct > 100
        || gPickedBoostedShootersPct < -1 || gPickedBoostedShootersPct > 100
        || gRandomWinningsBoostPct < -1 || gRandomWinningsBoostPct > 100
        || gPickedWinningsBoostPct < -1 || gPickedWinningsBoostPct > 100
        || gRandomWinningsBoostJitterPct < 0 || gRandomWinningsBoostJitterPct > 100
        || gPickedWinningsBoostJitterPct < 0 || gPickedWinningsBoostJitterPct > 100
        || gRandomGoal5ShooterPct < -1 || gRandomGoal5ShooterPct > 100
        || gRandomGoal10ShooterPct < -1 || gRandomGoal10ShooterPct > 100
        || gRandomGoal50ShooterPct < -1 || gRandomGoal50ShooterPct > 100
        || gPickedGoal5ShooterPct < -1 || gPickedGoal5ShooterPct > 100
        || gPickedGoal10ShooterPct < -1 || gPickedGoal10ShooterPct > 100
        || gPickedGoal50ShooterPct < -1 || gPickedGoal50ShooterPct > 100
        || gRandomGoal5WinningsBoostBps < -1 || gRandomGoal5WinningsBoostBps > 10'000
        || gRandomGoal10WinningsBoostBps < -1 || gRandomGoal10WinningsBoostBps > 10'000
        || gRandomGoal50WinningsBoostBps < -1 || gRandomGoal50WinningsBoostBps > 10'000
        || gPickedGoal5WinningsBoostBps < -1 || gPickedGoal5WinningsBoostBps > 10'000
        || gPickedGoal10WinningsBoostBps < -1 || gPickedGoal10WinningsBoostBps > 10'000
        || gPickedGoal50WinningsBoostBps < -1 || gPickedGoal50WinningsBoostBps > 10'000) {
        throw std::invalid_argument("shooter frequency and winnings boost must each be between 0 and 100 percent");
    }
    bool matchupOnly = !matchupIncumbentFilter.empty() || !matchupCandidateFilter.empty();
    if (matchupOnly && !scenarioFilter.empty()) {
        throw std::invalid_argument("scenario and matchup filters cannot be combined");
    }

    std::cout << std::fixed << std::setprecision(6);
    std::cout << "CONFIG\tdays\t" << days << "\tcalibration\t" << calibrationSamples
              << "\tschedule\t" << scheduleSamples << "\tseed\t" << seed << "\taction_bps\t"
              << kActionBps << "\tmain_base\t" << gMainBase
              << "\tesc_hands\t" << gEscHands << "\tesc_cap\t" << gEscCap << "\tdont_profit_ratio\t"
              << gDontProfitNum << '/' << gDontProfitDen << "\tboosted_shooters_pct\t"
              << gBoostedShootersPct << "\twinnings_boost_pct\t" << gWinningsBoostPct
              << "\twinnings_boost_mode\t"
              << (gWinningsBoostMode == WinningsBoostMode::All ? "all" : "random")
              << "\trandom_shooters_pct\t" << winningsBoostFrequency(true)
              << "\tpicked_shooters_pct\t" << winningsBoostFrequency(false)
              << "\trandom_goal_shooters_pct_5_20\t"
              << winningsBoostFrequency(true, 5) << ',' << winningsBoostFrequency(true, 20)
              << "\tpicked_goal_shooters_pct_5_20\t"
              << winningsBoostFrequency(false, 5) << ',' << winningsBoostFrequency(false, 20)
              << "\trandom_winnings_pct\t" << winningsBoostAmount(true)
              << "\tpicked_winnings_pct\t" << winningsBoostAmount(false)
              << "\trandom_winnings_jitter_pct\t" << winningsBoostJitter(true)
              << "\tpicked_winnings_jitter_pct\t" << winningsBoostJitter(false)
              << "\trandom_goal_bps_5_20\t" << winningsBoostTargetBps(true, 5) << ','
              << winningsBoostTargetBps(true, 20)
              << "\tpicked_goal_bps_5_20\t" << winningsBoostTargetBps(false, 5) << ','
              << winningsBoostTargetBps(false, 20) << "\n";
    std::cout << "PROPOSED_RULES\thigh_water_goal\t" << (gHighWaterGoal ? 1 : 0)
              << "\tpeak_jackpot_table\t25x_120x__50x_225x"
              << "\tcustoms\texcluded_legacy_product\n";
    long double darkWinProbability = 949.0L / 1925.0L;
    auto scheduledProfitRatio = [&](int frequencyPct, int boostBps) {
        return static_cast<long double>(gDontProfitNum) / gDontProfitDen
            * (1 + static_cast<long double>(frequencyPct) * boostBps / 1'000'000);
    };
    auto darkPerShooterEdge = [&](bool randomTicket, int goalMult) {
        return 100 * (1 - darkWinProbability * (
            1 + scheduledProfitRatio(
                winningsBoostFrequency(randomTicket, goalMult), winningsBoostTargetBps(randomTicket, goalMult)
            )
        ));
    };
    std::cout << "DONT_PASS\tprofit_ratio\t" << gDontProfitNum << '/' << gDontProfitDen
              << "\trandom_ticket_edge_pct_5_20\t"
              << static_cast<double>(darkPerShooterEdge(true, 5)) << ','
              << static_cast<double>(darkPerShooterEdge(true, 20))
              << "\tpicked_ticket_edge_pct_5_20\t"
              << static_cast<double>(darkPerShooterEdge(false, 5)) << ','
              << static_cast<double>(darkPerShooterEdge(false, 20)) << "\n";

    // An exhaustive board sweep is a self-contained mode. Avoid spending time on, and printing,
    // unrelated schedule/calibration/scenario tables before returning its result.
    if (boardSearchSamples != 0) {
        if (searchRefineSamples == 0) searchRefineSamples = boardSearchSamples * 20;
        printBoardSearch(searchField, boardSearchSamples, searchRefineSamples, searchTop, seed);
        return 0;
    }

    if (jackpotCalibrationSamples != 0) {
        printPeakJackpotCalibration(
            jackpotCalibrationSamples, seed, jackpotDepthFilter, jackpotGoalFilter
        );
        return 0;
    }
    if (winnerCalibrationFields != 0) {
        printWinnerPeakCalibration(
            winnerCalibrationFields, seed, jackpotDepthFilter, jackpotGoalFilter
        );
        return 0;
    }

    if (bountyMatchupFields != 0) {
        printBountyMatchup(bountyMatchupFields, seed);
        return 0;
    }

    if (populationMatrixSeats != 0 || systemMatrixDays != 0) {
        if (populationMatrixSeats != 0) printPopulationMatrix(populationMatrixSeats, seed);
        if (systemMatrixDays != 0) printSystemMatrix(systemMatrixDays, keyed(seed, 0x4d4154524958ULL));
        return 0;
    }

    printSchedule(scheduleSamples, keyed(seed, 0x5cedULL));

    std::cout << "CALIBRATION_HEADER\tstrategy\teffective_edge_pct\tpre_forfeit_engine_drag_pct\tbust_deletion_pct"
                 "\tbust_rate_pct\tgoal_rate_pct\tmean_hands\n";
    std::array<Strategy, 7> strategies{Strategy::Sharp4, Strategy::FairSpread, Strategy::Mixed,
                                       Strategy::Pass, Strategy::Blank, Strategy::Hardways, Strategy::Dark};
    auto printCalibration = [&](std::string_view kind, Strategy strategy, u64 calibrationSeed) {
        Calibration c = calibrate(strategy, calibrationSamples, calibrationSeed);
        long double effective = 100 * (c.bankroll - c.paid) / c.bankroll;
        long double rawEdge = 100 * (c.bankroll - c.raw) / c.bankroll;
        long double deletion = 100 * c.deleted / c.bankroll;
        std::cout << kind << '\t' << strategyName(strategy) << '\t' << static_cast<double>(effective) << '\t'
                  << static_cast<double>(rawEdge) << '\t' << static_cast<double>(deletion) << '\t'
                  << static_cast<double>(100 * c.busts / calibrationSamples) << '\t'
                  << static_cast<double>(100 * c.goals / calibrationSamples) << '\t'
                  << static_cast<double>(c.hands / calibrationSamples) << "\n";
    };
    for (std::size_t i = 0; i < strategies.size(); ++i) {
        printCalibration("CALIBRATION", strategies[i], keyed(seed, i, 0xca1bULL));
    }
    printCalibration("CALIBRATION_CONTROL", Strategy::FairControl, keyed(seed, 0xfa17ULL, 0xca1bULL));

    if (settingSamples != 0) {
        std::cout << "SETTING_HEADER\tstrategy\tdepth\tgoal_multiple\teffective_edge_pct"
                     "\tpre_forfeit_engine_drag_pct\tbust_deletion_pct\tbust_rate_pct\tgoal_rate_pct\tmean_hands\n";
        auto parseIntList = [](const std::string& text) {
            std::vector<int> out;
            std::size_t pos = 0;
            while (pos < text.size()) {
                std::size_t comma = text.find(',', pos);
                if (comma == std::string::npos) comma = text.size();
                out.push_back(std::stoi(text.substr(pos, comma - pos)));
                pos = comma + 1;
            }
            return out;
        };
        std::vector<int> depths{5};
        std::vector<int> goals{5, 20};
        if (!settingDepthsArg.empty()) depths = parseIntList(settingDepthsArg);
        if (!settingGoalsArg.empty()) goals = parseIntList(settingGoalsArg);
        for (std::size_t si = 0; si < strategies.size(); ++si) {
            if (!settingStrategyFilter.empty() && strategies[si] != strategyFromName(settingStrategyFilter)) continue;
            for (int depth : depths) {
                for (int goalMult : goals) {
                    if ((jackpotDepthFilter != 0 && depth != jackpotDepthFilter)
                        || (jackpotGoalFilter != 0 && goalMult != jackpotGoalFilter)) {
                        continue;
                    }
                    Calibration c = calibrateFixed(
                        strategies[si], settingSamples,
                        keyed(seed, si, static_cast<u64>(depth), static_cast<u64>(goalMult)), depth, goalMult
                    );
                    long double effective = 100 * (c.bankroll - c.paid) / c.bankroll;
                    long double rawEdge = 100 * (c.bankroll - c.raw) / c.bankroll;
                    long double deletion = 100 * c.deleted / c.bankroll;
                    std::cout << "SETTING\t" << strategyName(strategies[si]) << '\t' << depth << '\t' << goalMult
                              << '\t' << static_cast<double>(effective) << '\t' << static_cast<double>(rawEdge)
                              << '\t' << static_cast<double>(deletion) << '\t'
                              << static_cast<double>(100 * c.busts / settingSamples) << '\t'
                              << static_cast<double>(100 * c.goals / settingSamples) << '\t'
                              << static_cast<double>(c.hands / settingSamples) << "\n";
                }
            }
        }
    }

    // THE PROGRESSIVE'S TRAJECTORY, across independent worlds. One world's pool is a single path
    // of a heavy-tailed process — the rare rung takes half of it — so a mean over many worlds is
    // the only honest statement of where it settles. Each world gets its own seed and therefore
    // its own terms, dice, boost rungs and tie coins.
    if (worlds > 0) {
        if (scenarioFilter.empty()) throw std::invalid_argument("--worlds needs --scenario NAME");
        auto all = scenarios();
        const Scenario* chosen = nullptr;
        for (const Scenario& sc : all) {
            if (sc.name == scenarioFilter) chosen = &sc;
        }
        if (chosen == nullptr) throw std::invalid_argument("unknown scenario for --worlds");

        std::vector<long double> ends;
        ends.reserve(static_cast<std::size_t>(worlds));
        long double funded = 0;
        long double rolled = 0;
        long double paid = 0;
        long double common = 0;
        long double rare = 0;
        long double allocation = 0;
        long double ladderPaid = 0;
        long double credit = 0;
        long double burn = 0;
        long double action = 0;
        long double risk = 0;
        long double engine = 0;
        long double dayCount = 0;
        for (int w = 0; w < worlds; ++w) {
            Totals t = simulateScenario(*chosen, days, 21, keyed(seed, 0x301dULL, static_cast<u64>(w)));
            ends.push_back(t.progressiveEnd);
            funded += t.progressiveFunded;
            rolled += t.progressiveRolled;
            paid += t.progressivePaid;
            common += t.progressiveCommonAwards;
            rare += t.progressiveRareAwards;
            allocation += t.mainBudget;
            ladderPaid += t.mainBoostPaid + t.highBoostPaid;
            credit += t.totalCredit;
            burn += t.cashBurn;
            action += t.actionRegular + t.actionHigh;
            risk += t.riskBankroll;
            engine += t.engineCredit;
            dayCount += t.days;
        }
        long double d = dayCount;
        std::cout << "WORLDS_HEADER\tscenario\tworlds\tdays\taction_per_day\tengine_retention_per_day"
                     "\tengine_edge_pct\traw_allocation_per_day\tladder_paid_per_day"
                     "\tprog_funded_per_day\tprog_rolled_per_day\tprog_paid_per_day"
                     "\temission_counting_stored_per_day\tnet_burn_accrual_per_day"
                     "\tnet_burn_cash_per_day\tpool_growth_per_day\tpool_mean\tpool_p10"
                     "\tpool_p50\tpool_p90\tcommon_per_year\trare_per_year\n";
        // EMISSION IS COUNTED WHERE IT LANDS. The ladder half is paid out; the progressive half is
        // a liability the day it is banked. A later award RELEASES that liability and is therefore
        // not added here — counting it again would double-count the same wei.
        long double emission = (ladderPaid + funded) / d;
        // THE ACCRUAL FIGURE is the one the policy is set on: what the engine kept, less what the
        // schedule allocated. The CASH figure counts an award when it is credited instead, so the
        // two differ by exactly the pool's growth while it is still filling — which is the
        // identity printed beside them.
        long double netAccrual = (risk - engine) / d - emission;
        long double netCash = (burn - credit) / d;
        long double poolGrowth = (funded + rolled - paid) / d;
        std::cout << "WORLDS\t" << chosen->name << '\t' << worlds << '\t' << days << '\t'
                  << static_cast<double>(action / d) << '\t' << static_cast<double>((risk - engine) / d) << '\t'
                  << static_cast<double>(risk == 0 ? 0 : 100 * (risk - engine) / risk) << '\t'
                  << static_cast<double>(allocation / d) << '\t' << static_cast<double>(ladderPaid / d) << '\t'
                  << static_cast<double>(funded / d) << '\t' << static_cast<double>(rolled / d) << '\t'
                  << static_cast<double>(paid / d) << '\t' << static_cast<double>(emission) << '\t'
                  << static_cast<double>(netAccrual) << '\t' << static_cast<double>(netCash) << '\t'
                  << static_cast<double>(poolGrowth) << '\t'
                  << static_cast<double>(std::accumulate(ends.begin(), ends.end(), 0.0L) / worlds) << '\t'
                  << static_cast<double>(percentile(ends, 0.10L)) << '\t'
                  << static_cast<double>(percentile(ends, 0.50L)) << '\t'
                  << static_cast<double>(percentile(ends, 0.90L)) << '\t'
                  << static_cast<double>(365 * common / d) << '\t' << static_cast<double>(365 * rare / d) << "\n";
        // THE IDENTITY, printed rather than asserted so a drift is visible in the output itself:
        // the cash basis exceeds the accrual basis by exactly what the pool grew.
        std::cout << "WORLDS_IDENTITY\tcash_minus_accrual\t" << static_cast<double>(netCash - netAccrual)
                  << "\tpool_growth\t" << static_cast<double>(poolGrowth) << "\tresidual\t"
                  << static_cast<double>(netCash - netAccrual - poolGrowth) << "\n";
        return 0;
    }

    std::cout << "SCENARIO_HEADER\tname\tordinary_seats_per_window\thigh_seats_per_window"
                 "\tregular_action_per_day\thigh_action_per_day\tactual_engine_edge_pct\tlinear_term_per_day"
                 "\traw_main_allocation_per_day\thigh_budget_per_day\tmain_boost_paid_per_day"
                 "\thigh_boost_paid_per_day"
                 "\tface_cost_per_day\tcash_burn_per_day\ttotal_credit_per_day\tnet_cash_burn_per_day"
                 "\tboost_paid_p50\tboost_paid_p90\tboost_paid_p99"
                 "\tprog_funded_per_day\tprog_rolled_per_day\tprog_paid_per_day\tprog_pool_end"
                 "\tprog_common_per_year\tprog_rare_per_year\n";

    auto all = scenarios();
    for (std::size_t si = 0; si < all.size(); ++si) {
        if (matchupOnly) break;
        const Scenario& scenario = all[si];
        if (!scenarioFilter.empty() && scenario.name != scenarioFilter) continue;
        Totals t = simulateScenario(scenario, days, 21, keyed(seed, si, 0x5ceULL));
        long double d = t.days;
        long double edge = t.riskBankroll == 0 ? 0 : 100 * (t.riskBankroll - t.engineCredit) / t.riskBankroll;
        std::cout << "SCENARIO\t" << scenario.name << '\t' << static_cast<double>(t.ordinarySeats / t.windows) << '\t'
                  << static_cast<double>(t.highSeats / t.windows) << '\t' << static_cast<double>(t.actionRegular / d) << '\t'
                  << static_cast<double>(t.actionHigh / d) << '\t' << static_cast<double>(edge) << '\t'
                  << static_cast<double>(t.linearTerm / d) << '\t' << static_cast<double>(t.mainBudget / d) << '\t'
                  << static_cast<double>(t.highBudget / d) << '\t' << static_cast<double>(t.mainBoostPaid / d) << '\t'
                  << static_cast<double>(t.highBoostPaid / d) << '\t' << static_cast<double>(t.faceCost / d) << '\t'
                  << static_cast<double>(t.cashBurn / d) << '\t' << static_cast<double>(t.totalCredit / d) << '\t'
                  << static_cast<double>((t.cashBurn - t.totalCredit) / d) << '\t'
                  << static_cast<double>(percentile(t.dailyBoostPaid, 0.50L)) << '\t'
                  << static_cast<double>(percentile(t.dailyBoostPaid, 0.90L)) << '\t'
                  << static_cast<double>(percentile(t.dailyBoostPaid, 0.99L)) << '\t'
                  << static_cast<double>(t.progressiveFunded / d) << '\t'
                  << static_cast<double>(t.progressiveRolled / d) << '\t'
                  << static_cast<double>(t.progressivePaid / d) << '\t'
                  << static_cast<double>(t.progressiveEnd) << '\t'
                  << static_cast<double>(365 * t.progressiveCommonAwards / d) << '\t'
                  << static_cast<double>(365 * t.progressiveRareAwards / d) << "\n";

        for (std::size_t g = 0; g < scenario.cohorts.size(); ++g) {
            const Cohort& c = scenario.cohorts[g];
            const GroupTotals& gt = t.groups[g];
            long double roi = gt.cashBurn == 0 ? std::numeric_limits<long double>::quiet_NaN()
                                               : 100 * (gt.totalCredit - gt.cashBurn) / gt.cashBurn;
            std::cout << "GROUP\t" << scenario.name << '\t' << c.name << '\t' << c.ordinary << '\t' << c.high << '\t'
                      << strategyName(c.strategy) << '\t' << c.standing << '\t'
                      << static_cast<double>(gt.cashBurn / d) << '\t' << static_cast<double>(gt.totalCredit / d) << '\t'
                      << static_cast<double>(roi) << '\t' << static_cast<double>(gt.mainWins / (d * kWindows)) << '\t'
                      << static_cast<double>(gt.highWins / (d * kWindows)) << "\n";
        }
    }

    // Best-response probes use common random numbers: every candidate sees the same terms,
    // boost draws, incumbent addresses, and shooter streams. Only its board changes.
    if (scenarioFilter.empty()) {
        std::cout << "MATCHUP_HEADER\tcandidate\tincumbent\tfield_size\tcandidate_main_win_pct"
                     "\tcandidate_roi_pct\tincumbent_roi_pct\n";
        for (std::size_t ii = 0; ii < strategies.size(); ++ii) {
            Strategy incumbent = strategies[ii];
            if (!matchupIncumbentFilter.empty()
                && incumbent != strategyFromName(matchupIncumbentFilter)) continue;
            u64 matchupSeed = keyed(seed, 0xbe57ULL, ii);
            for (Strategy candidate : strategies) {
                if (!matchupCandidateFilter.empty()
                    && candidate != strategyFromName(matchupCandidateFilter)) continue;
                Scenario m{"matchup", {{"incumbent", 31, 0, incumbent, 12, Funding::Cash},
                                        {"candidate", 1, 0, candidate, 12, Funding::Cash}}, 0};
                Totals t = simulateScenario(m, days, 21, matchupSeed);
                const GroupTotals& inc = t.groups[0];
                const GroupTotals& cand = t.groups[1];
                long double candRoi = 100 * (cand.totalCredit - cand.cashBurn) / cand.cashBurn;
                long double incRoi = 100 * (inc.totalCredit - inc.cashBurn) / inc.cashBurn;
                std::cout << "MATCHUP\t" << strategyName(candidate) << '\t' << strategyName(incumbent) << "\t32\t"
                          << static_cast<double>(100 * cand.mainWins / (t.days * kWindows)) << '\t'
                          << static_cast<double>(candRoi) << '\t' << static_cast<double>(incRoi) << "\n";
            }
        }

        if (!matchupOnly) {
            std::cout << "HIGH_MATCHUP_HEADER\tcandidate\tincumbent\tcandidate_main_win_pct"
                         "\tcandidate_high_win_pct\tcandidate_roi_pct\tincumbent_roi_pct\n";
            u64 highMatchupSeed = keyed(seed, 0xbe57ULL, 0xa11ceULL);
            for (Strategy candidate : strategies) {
                Scenario m{"high_matchup", {{"incumbent", 0, 1, Strategy::Blank, 12, Funding::Cash},
                                             {"candidate", 0, 1, candidate, 12, Funding::Cash}}, 0};
                Totals t = simulateScenario(m, days, 21, highMatchupSeed);
                const GroupTotals& inc = t.groups[0];
                const GroupTotals& cand = t.groups[1];
                long double candRoi = 100 * (cand.totalCredit - cand.cashBurn) / cand.cashBurn;
                long double incRoi = 100 * (inc.totalCredit - inc.cashBurn) / inc.cashBurn;
                std::cout << "HIGH_MATCHUP\t" << strategyName(candidate) << "\tblank\t"
                          << static_cast<double>(100 * cand.mainWins / (t.days * kWindows)) << '\t'
                          << static_cast<double>(100 * cand.highWins / (t.days * kWindows)) << '\t'
                          << static_cast<double>(candRoi) << '\t' << static_cast<double>(incRoi) << "\n";
            }
        }
    }

    printEquilibriumTable();
    printShockTable();
    return 0;
}
