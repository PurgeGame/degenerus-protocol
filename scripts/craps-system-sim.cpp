// Reproducible economic Monte Carlo for the current CrapsBattle system.
//
// Build:
//   g++ -O3 -std=c++20 -pthread scripts/craps-system-sim.cpp -o /tmp/craps-system-sim
// Run:
//   /tmp/craps-system-sim --days 10000 --calibration 250000 --seed 20260826
//
// This is an economic replica, not a byte-for-byte EVM replay. It implements the production
// rules and distributions, while using a fast counter-based 64-bit mixer in place of keccak256.
// Shared shooter dice are preserved within each battle; board scatter, survival flips, payout
// rounding, boost rungs, and final exact-score ties use separate deterministic streams.

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
// The progressive's two rungs, as divisors of the LIVE pool.
constexpr i64 kProgCommonDiv = 10;
constexpr i64 kProgRareDiv = 2;
// THE ROLL CUTOFFS, indexed `depthIndex * 3 + goalIndex` with depth in (2, 5, 10) and target in
// (5x, 10x, 50x). Cumulative dice rolls, inclusive, and the WINNING ticket's own.
constexpr int kProgCommon[9] = {150, 205, 340, 215, 275, 405, 265, 325, 455};
constexpr int kProgRare[9] = {185, 245, 395, 260, 320, 455, 315, 375, 500};

inline int progFormatIndex(int depth, int goalMult) {
    int d = depth == 2 ? 0 : (depth == 5 ? 1 : 2);
    int g = goalMult == 5 ? 0 : (goalMult == 10 ? 1 : 2);
    return d * 3 + g;
}
// The two parts the HIGH lane's component splits into: two fifths to the main lane, three to
// the lane that earned it.
constexpr i64 kHighToMainNum = 2;
constexpr i64 kHighToMainDen = 5;
constexpr int kScoreFloor = 12;
constexpr int kMaxHands = 256;
constexpr int kEscHands = 5;
constexpr int kRollBudget = 4096;
constexpr int kMaxRolls = 512;
// 1,200ths keep every current payout denominator exact and also keep an integer percentage
// uplift on any combination of current profit payments exact. In particular, 25% of a 3:4
// Don't-Pass profit and 25% of a 7:6 Place profit both remain integral.
constexpr i64 kMoneyUnits = 1'200;
int gDontProfitNum = 3;
int gDontProfitDen = 4;
i64 gMainBase = kDefaultMainBase;
// THE SHIPPED SHOOTER PROFIT SCHEDULE, as the defaults. A blank/random ticket carries the boost
// on 15 shooters in a hundred and a picked one on 5; the amount is FIXED per target — there is no
// jitter and no fractional rung, so the bps figures below are always whole hundreds.
//
//     ticket   eligible   goal 5x   goal 10x   goal 50x
//     blank        15%       +25%       +30%       +40%
//     picked        5%        +6%       +20%       +35%
//
// Every knob here stays overridable so a sweep can still explore off-schedule settings; nothing
// but an explicit flag moves them off production.
int gBoostedShootersPct = 0;
int gWinningsBoostPct = 0;
enum class WinningsBoostMode { All, RandomTickets };
WinningsBoostMode gWinningsBoostMode = WinningsBoostMode::All;
int gRandomBoostedShootersPct = 15;
int gPickedBoostedShootersPct = 5;
int gRandomWinningsBoostPct = -1;
int gPickedWinningsBoostPct = -1;
int gRandomWinningsBoostJitterPct = 0;
int gPickedWinningsBoostJitterPct = 0;
int gRandomGoal5WinningsBoostBps = 2'500;
int gRandomGoal10WinningsBoostBps = 3'000;
int gRandomGoal50WinningsBoostBps = 4'000;
int gPickedGoal5WinningsBoostBps = 600;
int gPickedGoal10WinningsBoostBps = 2'000;
int gPickedGoal50WinningsBoostBps = 3'500;

int winningsBoostFrequency(bool randomTicket) {
    int overridePct = randomTicket ? gRandomBoostedShootersPct : gPickedBoostedShootersPct;
    if (overridePct >= 0) return overridePct;
    if (!randomTicket && gWinningsBoostMode == WinningsBoostMode::RandomTickets) return 0;
    return gBoostedShootersPct;
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
    } else if (goalMult == 10) {
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

enum class Strategy { Sharp4, FairSpread, Mixed, Pass, Blank, Hardways, Dark, FairControl };

std::string_view strategyName(Strategy s) {
    switch (s) {
        case Strategy::Sharp4: return "sharp_place4_4_place10_3";
        case Strategy::FairSpread: return "fair_spread";
        case Strategy::Mixed: return "mixed";
        case Strategy::Pass: return "pass4_place4_3";
        case Strategy::Blank: return "blank";
        case Strategy::Hardways: return "hardways";
        case Strategy::Dark: return "dontpass4_place4_3";
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
    int d = static_cast<int>(rng.below(3));
    t.depth = d == 0 ? 2 : (d == 1 ? 5 : 10);
    // Three rungs, drawn evenly. The shooter schedule is what separates the targets now, so
    // weighting the draw as well would subsidise one of them twice.
    int g = static_cast<int>(rng.below(3));
    t.goalMult = g == 0 ? 5 : (g == 1 ? 10 : 50);

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
    int hands{};
    int rolls{};
    Stop stop{Stop::Bust};
    i64 units{};
};

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

    while (true) {
        if (bankrollMoney >= goalMoney) {
            r.stop = Stop::Goal;
            break;
        }
        if (r.hands == kMaxHands || r.rolls >= kRollBudget) {
            r.stop = Stop::Bust;
            break;
        }
        i64 q = i64{1} << (r.hands / kEscHands);
        if (q > 65'535) q = 65'535;
        i64 needMoney = stakeMoney * q;
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
        bankrollMoney += runHandMoney(board, shooter, boosted, shooterBoostPct) * q;
        r.units += q;
        r.rolls += static_cast<int>(shooter.rolls.size());
        ++r.hands;
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
        winningsBoostFrequency(randomTicket), winningsBoostTargetBps(randomTicket, t.goalMult),
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
        winningsBoostFrequency(randomTicket), winningsBoostTargetBps(randomTicket, t.goalMult),
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
    if (a.run.hands != b.run.hands) {
        return a.run.stop == Stop::Goal ? a.run.hands < b.run.hands : a.run.hands > b.run.hands;
    }
    i64 aw = a.run.rawMoney / kMoneyUnits;
    i64 bw = b.run.rawMoney / kMoneyUnits;
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
            if (runs[mainWinner].run.stop == Stop::Goal) {
                int fi = progFormatIndex(t.depth, t.goalMult);
                int rolls = runs[mainWinner].run.rolls;
                i64 candidate = 0;
                bool rare = rolls >= kProgRare[fi];
                if (rare) candidate = pool / kProgRareDiv;
                else if (rolls >= kProgCommon[fi]) candidate = pool / kProgCommonDiv;
                if (candidate > 0) {
                    // The candidate is ALREADY in the pool, so the curve applies to it directly
                    // and only the credit is deducted. What is denied never left.
                    i64 award = boostShare(candidate, seats[mainWinner].standing);
                    pool -= award;
                    if (count) {
                        out.totalCredit += award;
                        out.progressivePaid += award;
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
        int d = static_cast<int>(rng.below(3));
        t.depth = d == 0 ? 2 : (d == 1 ? 5 : 10);
        int g = static_cast<int>(rng.below(4));
        t.goalMult = g == 0 ? 5 : (g == 1 ? 10 : 50);
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
    // The policy calibration. A conservative whole-run engine take, and the bankroll action an
    // ordinary daily ticket puts through — SEVEN windows of it, not one, and bounties excluded.
    constexpr i64 kTakeBps = 1'600;
    constexpr i64 kTicketAction = 15'600;
    const i64 residual = kTicketAction * (kTakeBps - kActionBps) / 10'000;

    // THE SPLIT DOES NOT MOVE THIS CURVE. A wei banked in the progressive is a wei allocated: it
    // becomes a liability the moment it lands there, and its later payout releases that liability
    // rather than issuing again. So the emission below is the WHOLE main allocation.
    std::cout << "EQUILIBRIUM_HEADER\ttickets\taction\tengine_take_at_16pct\tallocation_base_plus_rate"
                 "\tladder_half\tprogressive_half\tnet_issuance\n";
    for (int tickets : {0, 2, 16, 40, 41, 80, 81}) {
        i64 action = static_cast<i64>(tickets) * kTicketAction;
        i64 take = action * kTakeBps / 10'000;
        i64 bonus = gMainBase + action * kActionBps / 10'000;
        std::cout << "EQUILIBRIUM\t" << tickets << '\t' << action << '\t' << take << '\t' << bonus << '\t'
                  << ladderHalf(bonus) << '\t' << progressiveHalf(bonus) << '\t' << (bonus - take) << "\n";
    }
    std::cout << "EQUILIBRIUM_NOTE\tresidual_burn_per_ticket\t" << residual
              << "\tbreak_even_tickets\t" << (gMainBase / residual) << "\tbase\t" << gMainBase
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
                 " [--settings-strategy STRATEGY] [--dont-profit-num N] [--dont-profit-den N]"
                 " [--main-base FLIP]"
                 " [--boosted-shooters-pct N] [--winnings-boost-pct N]"
                 " [--winnings-boost-mode all|random]"
                 " [--random-boosted-shooters-pct N] [--picked-boosted-shooters-pct N]"
                 " [--random-winnings-boost-pct N] [--picked-winnings-boost-pct N]"
                 " [--random-winnings-boost-jitter-pct N] [--picked-winnings-boost-jitter-pct N]"
                 " [--random-goal5-boost-bps N] [--random-goal10-boost-bps N]"
                 " [--random-goal50-boost-bps N]"
                 " [--picked-goal5-boost-bps N] [--picked-goal10-boost-bps N]"
                 " [--picked-goal50-boost-bps N]"
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
    int boardSearchSamples = 0;
    int searchRefineSamples = 0;
    int searchTop = 20;
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
        else if (arg == "--settings-strategy") settingStrategyFilter = argv[++i];
        else if (arg == "--board-search") boardSearchSamples = std::stoi(argv[++i]);
        else if (arg == "--search-refine") searchRefineSamples = std::stoi(argv[++i]);
        else if (arg == "--search-field") searchField = argv[++i];
        else if (arg == "--search-top") searchTop = std::stoi(argv[++i]);
        else if (arg == "--dont-profit-num") gDontProfitNum = std::stoi(argv[++i]);
        else if (arg == "--dont-profit-den") gDontProfitDen = std::stoi(argv[++i]);
        else if (arg == "--main-base") gMainBase = std::stoll(argv[++i]);
        else if (arg == "--boosted-shooters-pct") gBoostedShootersPct = std::stoi(argv[++i]);
        else if (arg == "--winnings-boost-pct") gWinningsBoostPct = std::stoi(argv[++i]);
        else if (arg == "--random-boosted-shooters-pct") {
            gRandomBoostedShootersPct = std::stoi(argv[++i]);
        }
        else if (arg == "--picked-boosted-shooters-pct") {
            gPickedBoostedShootersPct = std::stoi(argv[++i]);
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
        else if (arg == "--random-goal10-boost-bps") {
            gRandomGoal10WinningsBoostBps = std::stoi(argv[++i]);
        }
        else if (arg == "--random-goal50-boost-bps") {
            gRandomGoal50WinningsBoostBps = std::stoi(argv[++i]);
        }
        else if (arg == "--picked-goal5-boost-bps") {
            gPickedGoal5WinningsBoostBps = std::stoi(argv[++i]);
        }
        else if (arg == "--picked-goal10-boost-bps") {
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
        || boardSearchSamples < 0 || searchRefineSamples < 0 || searchTop <= 0) {
        throw std::invalid_argument("sample counts must be positive (settings may be zero)");
    }
    if (gDontProfitNum < 0 || gDontProfitDen <= 0 || gDontProfitNum > gDontProfitDen
        || kMoneyUnits % gDontProfitDen != 0) {
        throw std::invalid_argument("Don't Pass ratio must satisfy 0 <= numerator <= denominator and divide 1200");
    }
    if (gMainBase < 0) throw std::invalid_argument("main base cannot be negative");
    if (gBoostedShootersPct < 0 || gBoostedShootersPct > 100
        || gWinningsBoostPct < 0 || gWinningsBoostPct > 100
        || gRandomBoostedShootersPct < -1 || gRandomBoostedShootersPct > 100
        || gPickedBoostedShootersPct < -1 || gPickedBoostedShootersPct > 100
        || gRandomWinningsBoostPct < -1 || gRandomWinningsBoostPct > 100
        || gPickedWinningsBoostPct < -1 || gPickedWinningsBoostPct > 100
        || gRandomWinningsBoostJitterPct < 0 || gRandomWinningsBoostJitterPct > 100
        || gPickedWinningsBoostJitterPct < 0 || gPickedWinningsBoostJitterPct > 100
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
              << kActionBps << "\tmain_base\t" << gMainBase << "\tdont_profit_ratio\t"
              << gDontProfitNum << '/' << gDontProfitDen << "\tboosted_shooters_pct\t"
              << gBoostedShootersPct << "\twinnings_boost_pct\t" << gWinningsBoostPct
              << "\twinnings_boost_mode\t"
              << (gWinningsBoostMode == WinningsBoostMode::All ? "all" : "random")
              << "\trandom_shooters_pct\t" << winningsBoostFrequency(true)
              << "\tpicked_shooters_pct\t" << winningsBoostFrequency(false)
              << "\trandom_winnings_pct\t" << winningsBoostAmount(true)
              << "\tpicked_winnings_pct\t" << winningsBoostAmount(false)
              << "\trandom_winnings_jitter_pct\t" << winningsBoostJitter(true)
              << "\tpicked_winnings_jitter_pct\t" << winningsBoostJitter(false)
              << "\trandom_goal_bps_5_10_50\t" << winningsBoostTargetBps(true, 5) << ','
              << winningsBoostTargetBps(true, 10) << ',' << winningsBoostTargetBps(true, 50)
              << "\tpicked_goal_bps_5_10_50\t" << winningsBoostTargetBps(false, 5) << ','
              << winningsBoostTargetBps(false, 10) << ',' << winningsBoostTargetBps(false, 50) << "\n";
    long double darkWinProbability = 949.0L / 1925.0L;
    auto scheduledProfitRatio = [&](int frequencyPct, int boostBps) {
        return static_cast<long double>(gDontProfitNum) / gDontProfitDen
            * (1 + static_cast<long double>(frequencyPct) * boostBps / 1'000'000);
    };
    auto darkPerShooterEdge = [&](bool randomTicket, int goalMult) {
        return 100 * (1 - darkWinProbability * (
            1 + scheduledProfitRatio(
                winningsBoostFrequency(randomTicket), winningsBoostTargetBps(randomTicket, goalMult)
            )
        ));
    };
    std::cout << "DONT_PASS\tprofit_ratio\t" << gDontProfitNum << '/' << gDontProfitDen
              << "\trandom_ticket_edge_pct_5_10_50\t"
              << static_cast<double>(darkPerShooterEdge(true, 5)) << ','
              << static_cast<double>(darkPerShooterEdge(true, 10)) << ','
              << static_cast<double>(darkPerShooterEdge(true, 50))
              << "\tpicked_ticket_edge_pct_5_10_50\t"
              << static_cast<double>(darkPerShooterEdge(false, 5)) << ','
              << static_cast<double>(darkPerShooterEdge(false, 10)) << ','
              << static_cast<double>(darkPerShooterEdge(false, 50)) << "\n";

    // An exhaustive board sweep is a self-contained mode. Avoid spending time on, and printing,
    // unrelated schedule/calibration/scenario tables before returning its result.
    if (boardSearchSamples != 0) {
        if (searchRefineSamples == 0) searchRefineSamples = boardSearchSamples * 20;
        printBoardSearch(searchField, boardSearchSamples, searchRefineSamples, searchTop, seed);
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
        constexpr std::array<int, 3> depths{2, 5, 10};
        constexpr std::array<int, 3> goals{5, 10, 50};
        for (std::size_t si = 0; si < strategies.size(); ++si) {
            if (!settingStrategyFilter.empty() && strategies[si] != strategyFromName(settingStrategyFilter)) continue;
            for (int depth : depths) {
                for (int goalMult : goals) {
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
