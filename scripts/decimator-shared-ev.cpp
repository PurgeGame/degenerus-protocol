// Economic experiment, not production code or byte-for-byte EVM replay.
// Generated include comes from craps-high-water-system-sim.cpp; see Python runner.
#include "decimator-model.inc"
#include <cassert>

namespace {
using Rank = unsigned __int128;
struct Entry {
    Rank peak;
    u64 tie;
    bool actor{};
};
bool better(const Entry& a, const Entry& b) {
    return a.peak > b.peak || (a.peak == b.peak && a.tie > b.tie);
}
struct Stats {
    long double sum{}, squares{}, cash{}, first{};
    void add(long double payout, long double cashChance, long double firstChance) {
        sum += payout; squares += payout * payout;
        cash += cashChance; first += firstChance;
    }
};
long double prize(int rank, int winners, long double baseShare) {
    if (rank >= winners || winners == 0) return 0;
    static constexpr int weights[] = {5, 3, 2};
    int denom = winners == 1 ? 5 : winners == 2 ? 8 : 10;
    return baseShare / winners + (rank < 3 ? (1 - baseShare) * weights[rank] / denom : 0);
}
void emit(const std::string& experiment, const std::string& field, int n, int worlds,
          int boost, bool rotation, long double weight, long double totalWeight,
          const Stats& s, int split = 1, long double burn = 0, long double mult = 1) {
    long double mean = s.sum / worlds;
    long double variance = std::max(0.L, (s.squares - s.sum * mean) / (worlds - 1));
    std::cout << experiment << ',' << field << ',' << n << ',' << worlds << ',' << boost << ','
              << rotation << ',' << weight << ',' << totalWeight << ',' << mean << ','
              << 1.96L * std::sqrt(variance / worlds) << ',' << s.cash / worlds << ','
              << s.first / worlds << ',' << mean / (weight / totalWeight) << ','
              << split << ',' << burn << ',' << mult << '\n';
}
Run normalized(u64 seed, u64 player, ShooterCache& dice, int boost,
               bool rotation, int n, Strategy strategy = Strategy::Blank) {
    Terms t; t.bankroll = 3000; t.round = 600; t.goal = 0;
    BoardMoney board = makeBoard(t, strategy, seed, player);
    return settlePreparedBoard(t, board, dice, seed, player, boost ? 15 : 0, boost,
                              rotation ? rotationTurn(seed, static_cast<int>(player - 1), n) : -1);
}
Entry scored(const Run& r, i64 weight, u64 seed, u64 player, bool actor = false) {
    return {static_cast<Rank>(r.peakMoney) * static_cast<Rank>(weight),
            keyed(seed, player, 0, 0x746965ULL), actor};
}
bool heads(u64 seed, u64 player) { return keyed(seed, player, 0, 0xf1a1ULL) & 1; }
i64 fieldWeight(const std::string& field, int index, int n) {
    if (field == "mixed") {
        constexpr i64 w[] = {2500, 5000, 10000, 20000, 40000};
        return w[index % 5];
    }
    if (field == "other_whale_16" && index == n - 2) return 160000;
    return 10000;
}
void focal(int n, int worlds, const std::string& field, int boost, bool rotation) {
    const std::vector<i64> weights = {1000, 2500, 5000, 7500, 10000, 12500, 15000,
        17049, 17833, 20000, 30000, 40000, 80000, 160000, 320000, 640000,
        1280000, 2560000, 10240000};
    std::vector<std::array<Stats, 3>> stats(weights.size());
    i64 opponentsWeight = 0;
    for (int j = 0; j < n - 1; ++j) opponentsWeight += fieldWeight(field, j, n);
    int k = std::min(100, (n + 9) / 10);
    for (int world = 0; world < worlds; ++world) {
        u64 seed = keyed(20260929, world, n, 0x4556ULL);
        ShooterCache dice(seed);
        Run f = normalized(seed, 1, dice, boost, rotation, n);
        std::vector<Entry> eligible, all;
        eligible.reserve(n); all.reserve(n);
        for (int j = 0; j < n - 1; ++j) {
            u64 player = j + 2;
            Run r = normalized(seed, player, dice, boost, rotation, n);
            Entry e = scored(r, fieldWeight(field, j, n), seed, player);
            all.push_back(e);
            if (heads(seed, player)) eligible.push_back(e);
        }
        std::sort(eligible.begin(), eligible.end(), better);
        std::sort(all.begin(), all.end(), better);
        int winners = std::min(k, static_cast<int>(eligible.size()) + 1);
        for (std::size_t w = 0; w < weights.size(); ++w) {
            Entry e = scored(f, weights[w], seed, 1);
            int rank = std::lower_bound(eligible.begin(), eligible.end(), e, better) - eligible.begin();
            // Integrate the focal entry's independent final coin exactly. Opponent coins are sampled.
            stats[w][0].add(0.5L * prize(rank, winners, 0.4L),
                            rank < winners ? 0.5L : 0, rank == 0 ? 0.5L : 0);
            stats[w][1].add(0.5L * prize(rank, winners, 1.L),
                            rank < winners ? 0.5L : 0, rank == 0 ? 0.5L : 0);
            int rawRank = std::lower_bound(all.begin(), all.end(), e, better) - all.begin();
            stats[w][2].add(prize(rawRank, k, 0.4L), rawRank < k ? 1 : 0, rawRank == 0 ? 1 : 0);
        }
    }
    for (std::size_t w = 0; w < weights.size(); ++w) {
        const char* names[] = {"topheavy_coin", "flat_coin", "topheavy_no_coin"};
        for (int a = 0; a < 3; ++a)
            emit(names[a], field, n, worlds, boost, rotation, weights[w] / 10000.L,
                 (weights[w] + opponentsWeight) / 10000.L, stats[w][a]);
    }
}
void splits(int worlds) {
    constexpr int others = 99;
    const int counts[] = {1, 2, 4, 8, 16};
    const i64 burns[] = {40000, 160000, 640000};
    struct Config { int count; i64 burn; int mult; Stats stats; };
    std::vector<Config> configs;
    for (i64 b : burns) for (int c : counts) for (int m : {10000, 17833})
        configs.push_back({c, b, m, {}});
    for (int world = 0; world < worlds; ++world) {
        u64 seed = keyed(20260929, world, 0, 0x53504c4954ULL);
        ShooterCache dice(seed);
        std::vector<Entry> opponents;
        for (int j = 0; j < others; ++j) {
            u64 player = 100 + j;
            Run r = normalized(seed, player, dice, 3200, false, others + 1);
            if (heads(seed, player)) opponents.push_back(scored(r, 10000, seed, player));
        }
        std::array<Run, 16> actor;
        for (int j = 0; j < 16; ++j) actor[j] = normalized(seed, j + 1, dice, 3200, false, 100);
        for (Config& c : configs) {
            std::vector<Entry> entries;
            // Use a common 10,000x rank scale to represent each split weight exactly.
            for (Entry e : opponents) { e.peak *= 10000; entries.push_back(e); }
            for (int j = 0; j < c.count; ++j) if (heads(seed, j + 1))
                entries.push_back(scored(actor[j], c.burn * c.mult / c.count, seed, j + 1, true));
            std::sort(entries.begin(), entries.end(), better);
            int k = std::min(100, (others + c.count + 9) / 10);
            int winners = std::min(k, static_cast<int>(entries.size()));
            long double payout = 0, total = 0;
            for (int rank = 0; rank < winners; ++rank) {
                long double p = prize(rank, winners, 0.4L); total += p;
                if (entries[rank].actor) payout += p;
            }
            assert(winners == 0 || std::fabs(total - 1.L) < 1e-15L);
            c.stats.add(payout, payout > 0 ? 1 : 0, !entries.empty() && entries[0].actor ? 1 : 0);
        }
    }
    for (const Config& c : configs) {
        long double weight = c.burn / 10000.L * c.mult / 10000.L;
        emit("split_actor", "99_equal_others", others + c.count, worlds, 3200, false,
             weight, others + weight, c.stats, c.count, c.burn / 10000.L, c.mult / 10000.L);
    }
}
void validate() {
    for (int w = 1; w <= 100; ++w) for (long double base : {0.4L, 1.L}) {
        long double total = 0;
        for (int r = 0; r < w; ++r) total += prize(r, w, base);
        assert(std::fabs(total - 1.L) < 1e-15L);
        assert(prize(w, w, base) == 0);
    }
    // A scaling identity check catches regressions in the normalized-run optimization.
    for (u64 seed = 1; seed <= 2000; ++seed) {
        Terms t; t.bankroll = 3000; t.round = 600; t.goal = 0;
        ShooterCache a(seed), b(seed);
        BoardMoney board = makeBoard(t, Strategy::Blank, seed, 1);
        Run x = settlePreparedBoard(t, board, a, seed, 1, 15, 3200, -1);
        t.bankroll *= 4; for (i64& v : board) v *= 4;
        Run y = settlePreparedBoard(t, board, b, seed, 1, 15, 3200, -1);
        assert(x.peakMoney * 4 == y.peakMoney && x.rawMoney * 4 == y.rawMoney);
        assert(x.hands == y.hands && x.rolls == y.rolls && x.stop == Stop::Bust);
        assert(x.rolls <= 1511 && x.hands <= 512);
    }
}
} // namespace

int main(int argc, char** argv) {
    std::cout << std::setprecision(12);
    validate();
    if (argc > 1 && std::string(argv[1]) == "split") { splits(std::stoi(argv[2])); return 0; }
    if (argc != 7) throw std::invalid_argument("N worlds field boostBps rotation seed-placeholder");
    focal(std::stoi(argv[1]), std::stoi(argv[2]), argv[3], std::stoi(argv[4]), std::stoi(argv[5]));
}
