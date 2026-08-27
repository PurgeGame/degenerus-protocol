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
constexpr i64 kActionDivisor = 3;
constexpr i64 kBurnShareDivisor = 2;
constexpr i64 kMainFloor = 15'000;
constexpr int kScoreFloor = 12;
constexpr int kMaxHands = 256;
constexpr int kEscHands = 5;
constexpr int kRollBudget = 4096;
constexpr int kMaxRolls = 512;
constexpr i64 kMoneyUnits = 60;
int gDontProfitNum = 3;
int gDontProfitDen = 4;

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
    int g = static_cast<int>(rng.below(4));
    t.goalMult = g == 0 ? 5 : (g == 1 ? 10 : (g == 2 ? 20 : 50));

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

// Board stakes and raw settlement values use sixtieths of one FLIP. That keeps every current
// payout denominator exact and also lets counterfactual quarter-denominated payouts (for
// example 3:4 Don't Pass profit) be simulated without floating point.
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

BoardMoney makeSelectedBoard(
    const Terms& t, const ChipCounts& selected, u64 scatterSeed, u64 playerKey
) {
    ChipCounts counts = selected;
    for (int i = 0; i < 3; ++i) {
        int leg = static_cast<int>(keyed(scatterSeed, playerKey, static_cast<u64>(i), 0x5ca77eULL) % 10);
        ++counts[leg];
    }
    i64 chipMoney = (t.round / 10) * kMoneyUnits;
    BoardMoney b{};
    for (int i = 0; i < 10; ++i) b[i] = counts[i] * chipMoney;
    return b;
}

i64 runHandMoney(const BoardMoney& b, const Shooter& shooter) {
    bool pass = b[0] != 0;
    std::array<bool, 6> place{};
    for (int i = 0; i < 6; ++i) place[i] = b[i + 1] != 0;
    bool hard4 = b[7] != 0;
    bool hard8 = b[8] != 0;
    bool dark = b[9] != 0;
    int point = 0;
    i64 returned = 0;

    auto payPlace = [&](int total) {
        if (total == 4 && place[0]) returned += b[1] * 2;
        else if (total == 5 && place[1]) returned += b[2] * 3 / 2;
        else if (total == 6 && place[2]) returned += b[3] * 7 / 6;
        else if (total == 8 && place[3]) returned += b[4] * 7 / 6;
        else if (total == 9 && place[4]) returned += b[5] * 3 / 2;
        else if (total == 10 && place[5]) returned += b[6] * 2;
    };

    bool sevenOut = false;
    for (const Roll& r : shooter.rolls) {
        int total = r.d1 + r.d2;
        bool comeOut = point == 0;
        if (!comeOut && total == 7) {
            if (dark) returned += b[9] + b[9] * gDontProfitNum / gDontProfitDen;
            sevenOut = true;
            break;
        }

        if (!comeOut) {
            payPlace(total);
            if (total == 4 && hard4) {
                if (r.d1 == r.d2) returned += b[7] * 7;
                else hard4 = false;
            } else if (total == 8 && hard8) {
                if (r.d1 == r.d2) returned += b[8] * 9;
                else hard8 = false;
            }
        }

        if (comeOut) {
            if (total == 7 || total == 11) {
                if (pass) returned += b[0];
                dark = false;
            } else if (total == 12) {
                pass = false;
            } else if (total == 2 || total == 3) {
                pass = false;
                if (dark) {
                    returned += b[9] + b[9] * gDontProfitNum / gDontProfitDen;
                    dark = false;
                }
            } else {
                point = total;
            }
        } else if (total == point) {
            if (pass) returned += b[0];
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
    const Terms& t, const BoardMoney& board, ShooterCache& dice, u64 seed, u64 playerKey
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
        bankrollMoney += runHandMoney(board, shooter) * q;
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
    return settlePreparedBoard(t, board, dice, seed, playerKey);
}

Run settleSelected(
    const Terms& t,
    const ChipCounts& selected,
    ShooterCache& dice,
    u64 seed,
    u64 playerKey
) {
    BoardMoney board = makeSelectedBoard(t, selected, seed, playerKey);
    return settlePreparedBoard(t, board, dice, seed, playerKey);
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
    long double modeledBurn{};
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
        er += regular / kActionDivisor;
        eh += high / kActionDivisor;
    }
    er /= kBurnDays;
    eh /= kBurnDays;
    i64 recycle = eh / kBurnShareDivisor;
    i64 fromHigh = recycle * 2 / 5;
    i64 highBudget = recycle - fromHigh;
    i64 mainBudget = er / kBurnShareDivisor + fromHigh;
    if (mainBudget < kMainFloor) mainBudget = kMainFloor;
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

    for (int day = 0; day < days + warmup; ++day) {
        auto [mainBudget, highBudget] = drawBudgets(history);
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
            out.mainBudget += mainBudget;
            out.highBudget += highBudget;
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
            i64 mainBounties = t.bounty * static_cast<i64>(seats.size());
            i64 mainPot = mainBounties + mainBoost;
            if (count) {
                out.totalCredit += mainPot;
                out.bountyReturned += mainBounties;
                out.mainBoostPaid += mainBoost;
                dayBoostPaid += mainBoost;
                GroupTotals& gt = out.groups[seats[mainWinner].group];
                gt.potCredit += mainPot;
                gt.totalCredit += mainPot;
                gt.mainWins += 1;
            }

            if (highHeads == 1) {
                std::size_t h = 0;
                while (!seats[h].high) ++h;
                i64 laneBoost = paidBoost(highBase, rung, seats[h].standing);
                i64 extra = (highMult - 1) * t.bounty;
                i64 rider = runs[h].run.paid == 0 ? 0 : runs[h].run.paid * (extra + laneBoost) / t.bankroll;
                i64 boostPart = runs[h].run.paid == 0 ? 0 : runs[h].run.paid * laneBoost / t.bankroll;
                if (count) {
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
                i64 laneBounties = static_cast<i64>(highHeads) * (highMult - 1) * t.bounty;
                i64 lanePot = laneBounties + laneBoost;
                if (count) {
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
            out.modeledBurn += static_cast<long double>(dayRegular + dayHigh) / kActionDivisor;
            out.dailyBoostPaid.push_back(dayBoostPaid);
        }
        history.pop_front();
        history.push_back({dayRegular, dayHigh});
    }
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
        t.goalMult = g == 0 ? 5 : (g == 1 ? 10 : (g == 2 ? 20 : 50));
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

std::vector<ChipCounts> legalSelectedBoards() {
    std::vector<ChipCounts> boards;
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
        if (s == Strategy::Blank || s == Strategy::FairControl) {
            throw std::invalid_argument("board search requires a seven-chip selected incumbent field");
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

std::vector<BoardSearchStats> evaluateSelectedBoards(
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
        auto [mainBudget, ignoredHighBudget] = drawBudgets(history);
        (void)ignoredHighBudget;
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
                    Run run = settleSelected(t, field[i], dice, windowSeed, pk);
                    ScoredRun scored{run, kScoreFloor, keyed(windowSeed, i, 0x71eULL)};
                    if (!haveFieldBest || better(scored, fieldBest)) {
                        fieldBest = scored;
                        haveFieldBest = true;
                    }
                }

                u64 candidateKey = keyed(candidateOwner, static_cast<u64>(day), static_cast<u64>(p));
                u64 candidateTie = keyed(windowSeed, 31, 0x71eULL);
                for (std::size_t i = 0; i < candidateIds.size(); ++i) {
                    Run run = settleSelected(
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
    std::vector<ChipCounts> boards = legalSelectedBoards();
    std::vector<ChipCounts> field = strategicField(fieldName);
    std::vector<std::size_t> allIds(boards.size());
    std::iota(allIds.begin(), allIds.end(), std::size_t{0});
    std::vector<BoardSearchStats> screened = evaluateSelectedBoards(
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

    std::vector<BoardSearchStats> refined = evaluateSelectedBoards(
        boards, refineIds, field, refineSamples, keyed(seed, 0x7ef1aeULL)
    );
    std::sort(refined.begin(), refined.end(), [](const BoardSearchStats& a, const BoardSearchStats& b) {
        return boardSearchRoi(a) > boardSearchRoi(b);
    });

    std::cout << "BOARD_SEARCH_HEADER\tfield\tlegal_boards\tscreen_samples\trefined_boards"
                 "\trefine_samples\tdont_profit_ratio\taction_divisor\n";
    std::cout << "BOARD_SEARCH\t" << fieldName << '\t' << boards.size() << '\t' << screenSamples << '\t'
              << refineIds.size() << '\t' << refineSamples << '\t' << gDontProfitNum << '/' << gDontProfitDen
              << '\t' << kActionDivisor << "\n";
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

void printShockTable() {
    std::deque<std::pair<i64, i64>> h(kBurnDays, {1'000'000, 0});
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
              << " [--days N] [--calibration N] [--schedule N] [--settings N]"
                 " [--settings-strategy STRATEGY] [--dont-profit-num N] [--dont-profit-den N]"
                 " [--board-search N] [--search-refine N] [--search-field STRATEGY|strategic_mix]"
                 " [--search-top N]"
                 " [--seed N] [--scenario NAME]"
                 " [--matchup-incumbent STRATEGY] [--matchup-candidate STRATEGY]\n";
}

} // namespace

int main(int argc, char** argv) {
    int days = 10'000;
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
        if (i + 1 >= argc) {
            usage(argv[0]);
            return 2;
        }
        if (arg == "--days") days = std::stoi(argv[++i]);
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
        throw std::invalid_argument("Don't Pass ratio must satisfy 0 <= numerator <= denominator and divide 60");
    }
    bool matchupOnly = !matchupIncumbentFilter.empty() || !matchupCandidateFilter.empty();
    if (matchupOnly && !scenarioFilter.empty()) {
        throw std::invalid_argument("scenario and matchup filters cannot be combined");
    }

    std::cout << std::fixed << std::setprecision(6);
    std::cout << "CONFIG\tdays\t" << days << "\tcalibration\t" << calibrationSamples
              << "\tschedule\t" << scheduleSamples << "\tseed\t" << seed << "\taction_divisor\t"
              << kActionDivisor << "\tdont_profit_ratio\t" << gDontProfitNum << '/' << gDontProfitDen << "\n";
    long double darkWinProbability = 949.0L / 1925.0L;
    long double darkPerShooterEdge =
        100 * (1 - darkWinProbability * (1 + static_cast<long double>(gDontProfitNum) / gDontProfitDen));
    std::cout << "DONT_PASS\tprofit_ratio\t" << gDontProfitNum << '/' << gDontProfitDen
              << "\tper_shooter_edge_pct\t"
              << static_cast<double>(darkPerShooterEdge) << "\n";
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

    if (boardSearchSamples != 0) {
        if (searchRefineSamples == 0) searchRefineSamples = boardSearchSamples * 20;
        printBoardSearch(searchField, boardSearchSamples, searchRefineSamples, searchTop, seed);
        return 0;
    }

    if (settingSamples != 0) {
        std::cout << "SETTING_HEADER\tstrategy\tdepth\tgoal_multiple\teffective_edge_pct"
                     "\tpre_forfeit_engine_drag_pct\tbust_deletion_pct\tbust_rate_pct\tgoal_rate_pct\tmean_hands\n";
        constexpr std::array<int, 3> depths{2, 5, 10};
        constexpr std::array<int, 4> goals{5, 10, 20, 50};
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

    std::cout << "SCENARIO_HEADER\tname\tordinary_seats_per_window\thigh_seats_per_window"
                 "\tregular_action_per_day\thigh_action_per_day\tactual_engine_edge_pct\tmodeled_burn_per_day"
                 "\tmain_budget_per_day\thigh_budget_per_day\tmain_boost_paid_per_day\thigh_boost_paid_per_day"
                 "\tface_cost_per_day\tcash_burn_per_day\ttotal_credit_per_day\tnet_cash_burn_per_day"
                 "\tboost_paid_p50\tboost_paid_p90\tboost_paid_p99\n";

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
                  << static_cast<double>(t.modeledBurn / d) << '\t' << static_cast<double>(t.mainBudget / d) << '\t'
                  << static_cast<double>(t.highBudget / d) << '\t' << static_cast<double>(t.mainBoostPaid / d) << '\t'
                  << static_cast<double>(t.highBoostPaid / d) << '\t' << static_cast<double>(t.faceCost / d) << '\t'
                  << static_cast<double>(t.cashBurn / d) << '\t' << static_cast<double>(t.totalCredit / d) << '\t'
                  << static_cast<double>((t.cashBurn - t.totalCredit) / d) << '\t'
                  << static_cast<double>(percentile(t.dailyBoostPaid, 0.50L)) << '\t'
                  << static_cast<double>(percentile(t.dailyBoostPaid, 0.90L)) << '\t'
                  << static_cast<double>(percentile(t.dailyBoostPaid, 0.99L)) << "\n";

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

    printShockTable();
    return 0;
}
