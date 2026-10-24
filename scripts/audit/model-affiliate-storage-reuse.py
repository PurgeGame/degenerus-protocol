#!/usr/bin/env python3
"""One-word affiliate history: reference checks and Glamsterdam storage costs.

NOT Solidity, an EVM trace, or a protocol-security proof. Only the per-affiliate
earnings/cache word is priced; shared level totals, routing, events, external
calls and arithmetic are excluded. Uses the plan's dated EIP-8037/8038 schedule.

Run: python3 -I scripts/audit/model-affiliate-storage-reuse.py
"""

import hashlib
import importlib.util
import json
from pathlib import Path
import random

ROOT = Path(__file__).resolve().parents[2]
PRICING_PATH = Path(__file__).with_name("model-coinflip-reuse-lifetime.py")
SPEC = importlib.util.spec_from_file_location("pricing", PRICING_PATH)
P = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(P)

LIVE_BITS, HISTORY_BITS = 35, 19
LIVE_CAP = (1 << LIVE_BITS) - 1
HISTORY_CAP = 500_000
HISTORY_MASK = (1 << (HISTORY_BITS * 5)) - 1
LEVEL_MASK = (1 << 24) - 1
CACHE_MASK = (1 << 66) - 1
HISTORY_SHIFT, LEVEL_SHIFT, CACHE_SHIFT = 70, 165, 189
BONUS_CAP_PRODUCT = 5_000 * 10**18
MAX_UINT256 = (1 << 256) - 1


def meter():
    return dict(exec=0, state=0, refund=0, net=0, creations=0, peak_tx=0)


def price(level):
    if level < 5:
        return 10**16
    if level < 10:
        return 2 * 10**16
    offset = level % 100
    if offset == 0:
        return 24 * 10**16
    return 4 * 10**16 * ((0x4333222111 >> ((offset // 10) * 4)) & 15)


def points(scores, current):
    product = sum(scores.get(lvl, 0) * price(lvl)
                  for lvl in range(max(1, current - 5), current))
    volume = product * 10_000 // (2_000 * 1_000)
    result = volume * 4 // 10**18 if volume <= 5 * 10**18 else (
        20 + (volume - 5 * 10**18) * 3 // (2 * 10**18))
    return min(50, result)


def latest(word):
    return (word >> LEVEL_SHIFT) & LEVEL_MASK


def retained_score(word, level):
    """Internal activity input, not a promise of exact historical score views."""
    top = latest(word)
    if not top or level > top or level < 1:
        return 0
    age = top - level
    if age < 2:
        return (word >> (age * LIVE_BITS)) & LIVE_CAP
    if age < 7:
        return (word >> (HISTORY_SHIFT + (age - 2) * HISTORY_BITS)) & ((1 << HISTORY_BITS) - 1)
    return 0


def roll(word, level):
    """Bounded memory-only rollover; no history-sized loop or storage clearing."""
    old_level = latest(word)
    assert 1 <= level <= LEVEL_MASK
    assert not old_level or level >= old_level, "writers must target monotonically increasing next levels"
    distance = level - old_level
    if distance == 0:
        return word
    newest = word & LIVE_CAP
    previous = (word >> LIVE_BITS) & LIVE_CAP
    history = (word >> HISTORY_SHIFT) & HISTORY_MASK
    if not old_level or distance >= 7:
        previous = history = 0
    elif distance == 1:
        history = ((history << HISTORY_BITS) | min(previous, HISTORY_CAP)) & HISTORY_MASK
        previous = newest
    else:
        history = (history << (distance * HISTORY_BITS)) & HISTORY_MASK
        history |= min(newest, HISTORY_CAP) << ((distance - 2) * HISTORY_BITS)
        if distance <= 5:
            history |= min(previous, HISTORY_CAP) << ((distance - 1) * HISTORY_BITS)
        previous = 0
    return ((word & (CACHE_MASK << CACHE_SHIFT)) | (level << LEVEL_SHIFT)
            | (history << HISTORY_SHIFT) | (previous << LIVE_BITS))


class Packed:
    def __init__(self):
        self.store, self.gas = {}, meter()
        # Logical shared accounting is checked but not included in the gas meter.
        self.totals, self.leaders = {}, {}

    def book(self, account, level, amount, stable_cache=None):
        assert 0 <= amount <= MAX_UINT256
        if amount == 0:
            return 0
        tx = P.Tx(self.store, self.gas)
        key = ("affiliate", account)
        original = tx.sload(key)
        if level == 0 or level < latest(original):
            tx.close()
            return 0
        word = roll(original, level)
        before = word & LIVE_CAP
        # Subtraction-before-addition avoids uint256 overflow on oversized input.
        delta = min(amount, LIVE_CAP - before)
        word += delta
        if stable_cache is not None:
            assert 0 <= stable_cache <= CACHE_MASK
            word = (word & ~(CACHE_MASK << CACHE_SHIFT)) | (stable_cache << CACHE_SHIFT)
        assert 0 < word < (1 << 255)
        if word != original:
            tx.sstore(key, word)
        tx.close()
        self.totals[level] = self.totals.get(level, 0) + delta
        total = before + delta
        if total > self.leaders.get(level, (0, 0))[1]:
            self.leaders[level] = (account, total)
        return delta

    def exact_score(self, account, level):
        word = self.store.get(("affiliate", account), 0)
        top = latest(word)
        return retained_score(word, level) if top and top - 1 <= level <= top else 0

    def bonus(self, account, current):
        word = self.store.get(("affiliate", account), 0)
        scores = {lvl: retained_score(word, lvl) for lvl in range(max(1, current - 5), current)}
        return points(scores, current)


class CurrentStorage:
    """Only today's per-level uint128 earnings + cache word, below its cap."""
    def __init__(self):
        self.store, self.gas = {}, meter()

    def book(self, account, level, amount, stable_cache):
        tx = P.Tx(self.store, self.gas)
        key = (level, account)
        word = tx.sload(key)
        total = (word & ((1 << 128) - 1)) + amount
        assert total < 1 << 128
        tx.sstore(key, total | (stable_cache << 128))
        tx.close()


def regressions():
    cases = []
    # Both cache IDs, both valid bits and adjacent lanes must survive every roll.
    cache = ((1 << 32) - 1) | (123 << 32) | (3 << 64)
    for distance in (0, 1, 2, 3, 4, 5, 6, 7, 8, 10_000):
        p = Packed()
        ref = {}
        for lvl in range(10, 17):
            amount = 400_000 + 50_000 * (lvl - 10)
            ref[lvl] = amount
            p.book(1, lvl, amount, cache)
        target = 16 + distance
        p.book(1, target, 100)
        ref[target] = ref.get(target, 0) + 100
        word = p.store[("affiliate", 1)]
        assert word >> CACHE_SHIFT == cache
        for age in range(7):
            expected = ref.get(target - age, 0)
            if age >= 2:
                expected = min(expected, HISTORY_CAP)
            assert retained_score(word, target - age) == expected, (distance, age)
        assert retained_score(word, target - 7) == 0
        assert p.exact_score(1, target - 2) == 0, "do not expose clipped history as an exact score"
        cases.append(f"roll_gap_{distance}")

    p = Packed()
    p.book(1, 1, 5, cache)
    snapshot, gas = dict(p.store), dict(p.gas)
    assert p.book(1, 1000, 0) == 0
    assert p.store == snapshot and p.gas == gas
    cases.append("zero_does_not_roll_or_allocate")
    assert p.book(1, 1, LIVE_CAP - 5) == LIVE_CAP - 5
    snapshot = dict(p.store)
    assert p.book(1, 1, MAX_UINT256) == 0
    assert p.store == snapshot and p.totals[1] == LIVE_CAP
    p.book(2, 1, LIVE_CAP)
    assert p.leaders[1] == (1, LIVE_CAP), "cap ties preserve the earlier leader"
    assert p.totals[1] == 2 * LIVE_CAP
    cases.append("cap_huge_input_exact_denominator_and_tie")
    for lvl in (LEVEL_MASK - 6, LEVEL_MASK - 1, LEVEL_MASK):
        p.book(1, lvl, 1)
    assert latest(p.store[("affiliate", 1)]) == LEVEL_MASK
    assert p.exact_score(1, LEVEL_MASK - 1) == 1
    assert p.store[("affiliate", 1)] >> CACHE_SHIFT == cache
    cases.append("uint24_last_level_preserves_cache")
    snapshot = (dict(p.store), dict(p.totals), dict(p.leaders))
    for lvl in (0, 1, LEVEL_MASK - 2, LEVEL_MASK - 1):
        assert p.book(1, lvl, MAX_UINT256) == 0
        assert (p.store, p.totals, p.leaders) == snapshot
    assert p.book(3, 0, MAX_UINT256) == 0
    assert ("affiliate", 3) not in p.store
    cases.append("zero_and_backward_targets_are_noops")

    # Source-equivalent prices over the intro and a complete repeating cycle.
    assert min(price(lvl) for lvl in range(201)) == 10**16
    assert HISTORY_CAP * 10**16 == BONUS_CAP_PRODUCT
    bonus_cases = 0
    for current in range(0, 207):
        for amount in (0, 1, 99_999, 100_000, 499_999, 500_000, 500_001, LIVE_CAP, (1 << 128) - 1):
            for offset in range(1, 6):
                lvl = current - offset
                raw = {lvl: amount} if lvl > 0 else {}
                clipped = {k: min(v, HISTORY_CAP) for k, v in raw.items()}
                assert points(raw, current) == points(clipped, current)
                bonus_cases += 1
    return {"cases": cases, "cases_passed": len(cases), "bonus_clipping_boundary_cases": bonus_cases}


def differential():
    writes = queries = 0
    for seed in range(24):
        rng = random.Random(seed + 42)
        p = Packed()
        raw = {i: {} for i in range(1, 7)}
        capped = {i: {} for i in range(1, 7)}
        totals, leaders = {}, {}
        caches = {i: 0 for i in range(1, 7)}
        game_level = 0
        for step in range(600):
            game_level += rng.choice((0, 0, 0, 1, 1, 2, 5, 6, 7, 31, 1000))
            target = game_level + 1
            account = rng.randint(1, 6)
            amount = rng.choice((0, 1, 499_999, 500_000, LIVE_CAP - 1, LIVE_CAP,
                                 LIVE_CAP + 1, rng.randrange(1 << 50)))
            # Cache contents are immutable once valid. Referral resolution itself
            # remains a Solidity integration obligation.
            update = None
            if amount and rng.random() < 0.1:
                caches[account] = account + 100 | ((account + 200) << 32) | (3 << 64)
                update = caches[account]
            before = capped[account].get(target, 0)
            after = min(LIVE_CAP, before + amount)
            accepted = after - before
            assert p.book(account, target, amount, update) == accepted
            if amount:
                raw[account][target] = raw[account].get(target, 0) + amount
                capped[account][target] = after
                totals[target] = totals.get(target, 0) + accepted
                if after > leaders.get(target, (0, 0))[1]:
                    leaders[target] = (account, after)
                assert p.totals[target] == totals[target]
                assert p.leaders[target] == leaders[target]
            writes += 1
            for who in range(1, 7):
                word = p.store.get(("affiliate", who), 0)
                assert word >> CACHE_SHIFT == caches[who]
                assert p.exact_score(who, game_level) == capped[who].get(game_level, 0)
                assert p.exact_score(who, target) == capped[who].get(target, 0)
                assert p.bonus(who, game_level) == points(capped[who], game_level)
                assert p.bonus(who, game_level) == points(raw[who], game_level)
                queries += 4
            assert len(p.store) <= 6
    return {"credit_operations": writes, "score_and_bonus_comparisons": queries,
            "accounts_per_seed": 6, "seeds": 24}


def gas_study():
    rows = []
    cache = 100 | (200 << 32) | (3 << 64)
    for levels in (1, 7, 100, 1000, 10_000):
        for per_level in (1, 10):
            current, packed = CurrentStorage(), Packed()
            for lvl in range(1, levels + 1):
                for _ in range(per_level):
                    current.book(1, lvl, 100, cache)
                    packed.book(1, lvl, 100, cache)
            rows.append({"credited_levels": levels, "credits_per_level": per_level,
                         "current_storage_gas": current.gas["net"],
                         "packed_storage_gas": packed.gas["net"],
                         "savings": current.gas["net"] - packed.gas["net"],
                         "current_creations": current.gas["creations"],
                         "packed_creations": packed.gas["creations"]})
    return rows


def main():
    sources = ["contracts/DegenerusAffiliate.sol", "contracts/libraries/AffiliateEarningsLib.sol", "contracts/libraries/PriceLookupLib.sol",
               "contracts/modules/GameBingo.sol",
               "contracts/modules/DegenerusGameMintStreakUtils.sol"]
    out = {"scope": "Python codec/accounting model and storage-only Glamsterdam estimates; no EVM/security proof",
           "score_cap": LIVE_CAP, "history_cap": HISTORY_CAP,
           "packed_bits": 2 * LIVE_BITS + 5 * HISTORY_BITS + 24 + 66,
           "model_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
           "pricing_model_sha256": hashlib.sha256(PRICING_PATH.read_bytes()).hexdigest(),
           "source_sha256": {f: hashlib.sha256((ROOT / f).read_bytes()).hexdigest() for f in sources},
           "regressions": regressions(), "differential": differential(), "gas_workloads": gas_study()}
    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()
