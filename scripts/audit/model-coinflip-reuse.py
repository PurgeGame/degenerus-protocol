#!/usr/bin/env python3
"""Executable design study: resettable, tagged stake pages with a 730-day window.

This is a Python reference model, NOT Solidity implementation, gas measurement,
or a proof of protocol security. It compares day-keyed stakes with seven uint32
amounts plus one shared absolute block tag per reusable word. Metadata/init,
external calls, events, RNG gaps, seeds, and BAF are outside the model.

Run: python3 scripts/audit/model-coinflip-reuse.py
"""

import json
import random

WINDOW = 730
LANES = 7
# Include both partial edge pages and tomorrow's unresolved stake.
PAGES = (WINDOW + LANES - 1) // LANES + 1
CAP = (1 << 32) - 1
CARRY_CAP = (1 << 128) - 1
# Glamsterdam EIP-8037/8038 parameters, checked 2026-10-19. These support
# storage-component calculations only, not a replacement for transaction traces.
STATE_GAS_PER_CREATION = 64 * 1530
COLD_STORAGE_ACCESS = 2100
WARM_ACCESS = 100
STORAGE_WRITE = 10_000
COLD_READ_MODIFY_WRITE = COLD_STORAGE_ACCESS + WARM_ACCESS + STORAGE_WRITE


class Reference:
    def __init__(self):
        self.stakes = {}
        self.cursor = 0
        self.carry = 0
        self.created = 0

    def get(self, day):
        return self.stakes.get(day, 0)

    def credit(self, day, amount, latest):
        del latest
        self.stakes[day] = min(CAP, self.get(day) + amount)

    def consume(self, day):
        self.stakes.pop(day, None)

    def reset(self, latest, wall):
        pass


class LiveCollision(Exception):
    """Reject reuse rather than overwrite a still-live stake."""


class Reused(Reference):
    def __init__(self):
        super().__init__()
        self.words = {}
        self.base = None
        self.moves = 0

    def index(self, block):
        return (block - self.base) % PAGES

    def get(self, day):
        if self.base is None:
            return 0
        block, lane = divmod(day, LANES)
        word = self.words.get(self.index(block), 0)
        if word >> 224 != block + 1:
            return 0
        return (word >> (lane * 32)) & CAP

    def put(self, index, word):
        assert word != 0, "retained word must never return to zero"
        if index not in self.words:
            self.created += 1
        self.words[index] = word

    def credit(self, day, amount, latest):
        if amount == 0:
            return
        block, lane = divmod(day, LANES)
        if self.base is None:
            self.base = block
        index = self.index(block)
        word = self.words.get(index, 0)
        if word >> 224 != block + 1:
            if word:
                old_block = (word >> 224) - 1
                cutoff = max(self.cursor, max(0, latest - WINDOW))
                for old_lane in range(LANES):
                    # A rebase can leave an unreachable old copy. It is not a
                    # second liability: its tag no longer maps to this index.
                    if self.index(old_block) == index and (word >> (old_lane * 32)) & CAP:
                        if old_block * LANES + old_lane > cutoff:
                            raise LiveCollision("must not overwrite an unexpired stake")
            word = (block + 1) << 224
        shift = lane * 32
        previous = (word >> shift) & CAP
        total = min(CAP, previous + amount)
        self.put(index, (word & ~(CAP << shift)) | (total << shift))

    def consume(self, day):
        # The absolute claim cursor, not clearing, consumes settled amounts.
        pass

    def reset(self, latest, wall):
        # Rebase only once caught up: all accepted future credits target tomorrow.
        # A lagging resolution clock leaves the mapping unchanged.
        if latest != wall or self.base is None:
            return
        future = wall + 1
        block = future // LANES
        if self.base == block:
            return
        amount = self.get(future)
        old_index = self.index(block)
        if amount and old_index != 0:
            # Read before changing the base. Retaining the whole page is safe:
            # old lanes remain behind the absolute claim cursor.
            self.put(0, self.words[old_index])
            self.moves += 1
        self.base = block


def claim(ledger, latest, wall, results, rebuy=False, take_profit=0):
    start = ledger.cursor
    bank = 0
    carry = ledger.carry
    losses = 0
    if not rebuy:
        bank, carry = carry, 0
    cutoff = max(0, latest - WINDOW)
    if start < cutoff:
        start = cutoff
        carry = 0
    for day in range(start + 1, latest + 1):
        amount = ledger.get(day) + (carry if rebuy else 0)
        ledger.consume(day)
        reward = results[day]
        if amount:
            if reward >= 50:
                payout = amount + amount * reward // 100
                if rebuy:
                    reserved = payout // take_profit * take_profit if take_profit else 0
                    bank += reserved
                    carry = payout - reserved
                    carry = min(CARRY_CAP, carry + carry * 75 // 10_000)
                else:
                    bank += payout
            else:
                losses += 1
                if rebuy:
                    carry = 0
    ledger.cursor = latest
    ledger.carry = carry
    ledger.reset(latest, wall)
    return bank, carry, losses, latest


def differential():
    operations = 0
    # Each run crosses many wraps; random sparse credits, same-day merges,
    # saturated lanes, future stakes written before claims, and long expiry.
    for seed in range(40):
        rng = random.Random(seed)
        ref, ring = Reference(), Reused()
        rebuy = bool(seed % 2)
        stop = [0, 1, 10_000, 10**12][(seed // 2) % 4]
        results = {}
        for wall in range(1, 5001):
            results[wall] = rng.choice([1, 50, 100, 156])
            if rng.randrange(3):
                for _ in range(rng.randrange(1, 4)):
                    amount = rng.choice([1, 100, 50_000, CAP, CAP + 1])
                    ref.credit(wall + 1, amount, wall)
                    ring.credit(wall + 1, amount, wall)
                    assert ref.get(wall + 1) == ring.get(wall + 1)
                    operations += 1
            cadence = [1, 7, 29, 730, 1001][seed % 5]
            if wall % cadence == 0:
                a = claim(ref, wall, wall, results, rebuy, stop)
                b = claim(ring, wall, wall, results, rebuy, stop)
                assert a == b, (seed, wall, a, b)
                assert ref.get(wall + 1) == ring.get(wall + 1)
                assert claim(ring, wall, wall, results, rebuy, stop)[0] == 0
                operations += 1
            assert ring.created <= PAGES
        assert claim(ref, wall, wall, results, rebuy, stop) == claim(
            ring, wall, wall, results, rebuy, stop
        )
    return operations


def boundary_checks():
    # Every alignment, oldest still-valid claim, and an already funded tomorrow.
    for offset in range(LANES):
        latest = 1500 + offset
        oldest = latest - WINDOW + 1
        ref, ring = Reference(), Reused()
        results = {d: 100 for d in range(1, latest + 1)}
        for day in range(oldest - 1, latest + 2):
            ref.credit(day, 100, day - 1)
            ring.credit(day, 100, day - 1)
        assert claim(ref, latest, latest, results) == claim(ring, latest, latest, results)
        assert ring.get(latest + 1) == 100
        assert claim(ring, latest, latest, results)[0] == 0

    # A catastrophic unresolved gap must be detected, never quietly aliased.
    ring = Reused()
    ring.credit(1, 100, 0)
    try:
        ring.credit(1 + PAGES * LANES, 100, 0)
    except LiveCollision:
        pass
    else:
        raise AssertionError("unresolved stake was overwritten")


def review_regressions():
    # The superseded plan grows forever on this reachable schedule, although
    # only eight days can remain unsettled. Its uint8 n eventually cannot fit.
    base, n, last_claim = 2, 1, 0
    ref, ring = Reference(), Reused()
    results = {d: 100 for d in range(1, 5001)}
    old_failure = None
    for wall in range(1, 5001):
        day = wall + 1
        if old_failure is None:
            i = day - base
            k = 0 if i < 7 else 1 + ((i - 7) >> 3)
            if k >= n:
                if day - (last_claim + 1) < 7:
                    base, n = last_claim + 1, 1
                else:
                    n = k + 1
            if n > 255:
                old_failure = {"wall_day": wall, "target_day": day, "required_n": n}
        ref.credit(day, 100, wall)
        ring.credit(day, 100, wall)
        if wall % 8 == 1:
            last_claim = wall
            assert claim(ref, wall, wall, results) == claim(ring, wall, wall, results)
        assert ring.get(day) == ref.get(day)
    assert old_failure == {"wall_day": 2040, "target_day": 2041, "required_n": 256}
    assert ring.created <= 3, "small backlog must not consume lifetime calendar capacity"

    # The superseded gap-clearing rule re-creates a previously allocated word.
    base, n, last_claim = 0, 0, 0
    old_slots = {}
    creations = 0
    actions = [("credit", 2), ("credit", 9), ("credit", 17), ("claim", 24),
               ("credit", 25), ("credit", 40), ("claim", 47),
               ("credit", 48), ("credit", 55)]
    ref, sparse = Reference(), Reused()
    for action, day in actions:
        if action == "claim":
            last_claim = day
            assert claim(ref, day, day, results) == claim(sparse, day, day, results)
            continue
        if n == 0:
            base, n, k = day, 1, 0
        else:
            i = day - base
            k = 0 if i < 7 else 1 + ((i - 7) >> 3)
            if k >= n:
                first = last_claim + 1
                if day - first < 7:
                    base, n, k = first, 1, 0
                else:
                    for j in range(n, k):
                        old_slots[j] = 0
                    n = k + 1
        creations += not old_slots.get(k, 0)
        old_slots[k] = day
        ref.credit(day, 100, day - 1)
        sparse.credit(day, 100, day - 1)
    assert creations == 4 and len(old_slots) == 3
    assert claim(ref, 55, 55, results) == claim(sparse, 55, 55, results)
    assert all(word != 0 for word in sparse.words.values())

    # The production walk can start before the first external stake's base.
    ref, late = Reference(), Reused()
    assert late.get(1) == 0
    ref.credit(100, 100, 99)
    late.credit(100, 100, 99)
    assert late.get(1) == 0
    assert claim(ref, 100, 100, results) == claim(late, 100, 100, results)
    return {
        "superseded_plan_uint8_failure": old_failure,
        "candidate_words_after_5000_days_claiming_every_eight_days": ring.created,
        "superseded_gap_clear_creations_for_three_addresses": creations,
        "pre_base_reads": "pass",
    }


def lifetime_counts():
    rows = []
    for cadence in [1, 7, 30, 730, 1001]:
        ring = Reused()
        # Count actual 0->nonzero events in current eight-lane words, including
        # re-creation after clearing a partially used calendar word.
        old_words = {}
        old_creations = 0
        cursor = 0
        results = {d: 100 for d in range(1, 3651)}
        for wall in range(1, 3651):
            day = wall + 1
            block, lane = divmod(day, 8)
            if not old_words.get(block, 0):
                old_creations += 1
            old_words[block] = old_words.get(block, 0) | (100 << (lane * 32))
            ring.credit(day, 100, wall)
            if wall % cadence == 0:
                for settled in range(max(cursor, wall - WINDOW) + 1, wall + 1):
                    key, shift_lane = divmod(settled, 8)
                    old_words[key] = old_words.get(key, 0) & ~(CAP << (shift_lane * 32))
                cursor = wall
                claim(ring, wall, wall, results)
        rows.append({
            "claim_every_days": cadence,
            "current_stake_word_creations": old_creations,
            "candidate_stake_word_creations": ring.created,
            "candidate_future_page_copies": ring.moves,
            "glamsterdam_state_gas_avoided": (old_creations - ring.created) * STATE_GAS_PER_CREATION,
            "glamsterdam_copy_destination_write_allowance": ring.moves * COLD_READ_MODIFY_WRITE,
        })
    return rows


if __name__ == "__main__":
    boundary_checks()
    regressions = review_regressions()
    operations = differential()
    print(json.dumps({
        "scope": "reference model only; no EVM gas or protocol-security claim",
        "window_days": WINDOW,
        "lazy_maximum_stake_words_per_player": PAGES,
        "randomized_operations_checked": operations,
        "review_regressions": regressions,
        "glamsterdam_parameters": {
            "state_gas_per_creation": STATE_GAS_PER_CREATION,
            "cold_storage_access": COLD_STORAGE_ACCESS,
            "warm_access": WARM_ACCESS,
            "storage_write": STORAGE_WRITE,
            "cold_read_modify_write": COLD_READ_MODIFY_WRITE,
            "calculation_scope": "state premium and copy destination writes only; not net transaction savings",
        },
        "ten_year_daily_credit_storage_counts": lifetime_counts(),
    }, indent=2))
