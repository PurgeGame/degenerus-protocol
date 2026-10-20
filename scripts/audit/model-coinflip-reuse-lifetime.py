#!/usr/bin/env python3
"""Lifetime Glamsterdam storage-gas model for coinflip stake layouts.

Reference model, NOT Solidity, NOT a protocol-security proof. It prices only the
stake-storage and slot-A accesses that differ between layouts, using the EIP-8037
/ EIP-8038 schedule (checked 2026-10-19):

  cold access 2,100 | warm access 100 | first change of a slot 10,000
  zero->nonzero adds 97,920 state gas | clearing a slot nonzero at tx start
  refunds 11,616 (cap 20% of gas used; no state-gas refill)

Day-result words, hashing, events and external calls are excluded. Slot-A reads,
cursor changes and layout metadata changes are included, including same-transaction
write sharing between a claim and credit. Other player-state fields are omitted.
Every layout is differentially checked against a logical ledger,
including a resolution clock that lags the wall day (stalls up to the deadman).

Layouts:
  current         key day>>3, 8 x uint32 lanes, walk clears consumed lanes
  cur_noclear     current keys; the cursor alone consumes (no clearing writes)
  ring            7 lanes + absolute page tag, physical page q % 128, no metadata
  rebaseA         plan candidate B: anchor in slot A, rebase+copy on caught-up claim
  rebase0         candidate B with the anchor recovered from physical page 0's tag
  queue           plan candidate C: chronological page list, head/tail in slot A
  nearfar[M]      page q lives in near[q % M] or far[q % 128]; never moves, no metadata
  nearfar[M]_hint nearfar plus a credit-only spill marker in the near word (plan D)

Run: python3 -I scripts/audit/model-coinflip-reuse-lifetime.py
"""

import json
import random

WINDOW = 730
LANES = 7
CAP = (1 << 32) - 1
COLD, WARM, WRITE, STATE, CLEAR_REFUND = 2100, 100, 10_000, 97_920, 11_616
TX_OVERHEAD = 60_000  # only used to apply the 20% refund cap
TAG_SHIFT = 224
TAG_MASK = (1 << 24) - 1
CURSOR_SHIFT = 128
CURSOR_MASK = TAG_MASK << CURSOR_SHIFT
META_SHIFT = 184
META_MASK = TAG_MASK << META_SHIFT


class LiveCollision(Exception):
    pass


class Tx:
    """One transaction's storage pricing (EIP-2929 warmth + EIP-2200 states)."""

    def __init__(self, store, meter):
        self.store, self.meter = store, meter
        self.warm, self.orig = set(), {}
        self.exec = self.state = self.refund = 0

    def _access(self, k):
        if k in self.warm:
            self.exec += WARM
        else:
            self.exec += COLD
            self.warm.add(k)
            self.orig[k] = self.store.get(k, 0)

    def sload(self, k):
        self._access(k)
        return self.store.get(k, 0)

    def sstore(self, k, v):
        self._access(k)
        cur, orig = self.store.get(k, 0), self.orig[k]
        if v != cur:
            if cur == orig:
                self.exec += WRITE
                if orig == 0:
                    self.state += STATE
                    self.meter["creations"] += 1
                elif v == 0:
                    self.refund += CLEAR_REFUND
            else:
                if orig != 0 and cur == 0:
                    self.refund -= CLEAR_REFUND
                if orig != 0 and v == 0:
                    self.refund += CLEAR_REFUND
                if v == orig:
                    if orig == 0:
                        self.state -= STATE
                        self.meter["creations"] -= 1
                    self.refund += WRITE
        if v:
            self.store[k] = v
        else:
            self.store.pop(k, None)

    def close(self):
        gross = self.exec + self.state
        refund = max(0, min(self.refund, (gross + TX_OVERHEAD) // 5))
        m = self.meter
        m["exec"] += self.exec
        m["state"] += self.state
        m["refund"] += refund
        m["net"] += gross - refund
        m["peak_tx"] = max(m["peak_tx"], gross)


def tag(w):
    return (w >> TAG_SHIFT) & TAG_MASK


def lane(w, i):
    return (w >> (i * 32)) & CAP


def set_lane(w, i, v):
    return (w & ~(CAP << (i * 32))) | (v << (i * 32))


def page_word(q, keep_hi=0):
    return ((q + 1) << TAG_SHIFT) | keep_hi


def dead(tx, env, w, fcd_first=False):
    """Priced liveness: the page is dead iff its last nonzero lane is at or below
    max(lastClaim, fcd - 730). Reads slot A (lastClaim) and the global resolution
    clock lazily, in the given order, stopping at the first proof."""
    q = tag(w) - 1
    last = None
    for i in range(LANES):
        if lane(w, i):
            last = q * LANES + i
    if last is None:
        return True
    order = [("G",), ("A",)] if fcd_first else [("A",), ("G",)]
    for k in order:
        tx.sload(k)
        if k == ("G",) and last <= env.fcd - WINDOW:
            return True
        if k == ("A",) and last <= env.last_claim:
            return True
    return False


class Env:
    """Shared clocks plus the player's logical claim cursor (lives in slot A)."""

    def __init__(self):
        self.wall = 0
        self.fcd = 0
        self.last_claim = 0

    def cutoff(self):
        return max(self.last_claim, max(0, self.fcd - WINDOW))


def page_dead(w, cutoff):
    q = tag(w) - 1
    for i in range(LANES):
        if lane(w, i) and q * LANES + i > cutoff:
            return False
    return True


class Layout:
    name = "?"

    def __init__(self):
        self.store = {}
        self.meter = dict(exec=0, state=0, refund=0, net=0, creations=0, peak_tx=0, copies=0)

    # credit(tx, env, day, amount) ; walk(tx, env, start, end) -> {day: amount}
    # after_claim(tx, env) runs once the cursor has moved (rebase hooks).
    def after_claim(self, tx, env):
        pass

    def claim_state_word(self, w):
        """Combine any changed layout metadata with the claim's slot-A write."""
        return w


class Current(Layout):
    name = "current"

    def credit(self, tx, env, day, amount):
        k = ("S", day >> 3)
        w = tx.sload(k)
        prev = lane(w, day & 7)
        new = min(CAP, prev + amount)
        if new != prev:
            tx.sstore(k, set_lane(w, day & 7, new))

    def walk(self, tx, env, start, end):
        out, cache, dirty = {}, {}, set()
        for d in range(start + 1, end + 1):
            k = ("S", d >> 3)
            if k not in cache:
                cache[k] = tx.sload(k)
            v = lane(cache[k], d & 7)
            if v:
                out[d] = v
                cache[k] = set_lane(cache[k], d & 7, 0)
                dirty.add(k)
        for k in dirty:
            tx.sstore(k, cache[k])
        return out


class CurrentNoClear(Current):
    """Current keys, but the cursor alone consumes: no clearing writes, no churn."""

    name = "cur_noclear"

    def walk(self, tx, env, start, end):
        out, cache = {}, {}
        for d in range(start + 1, end + 1):
            k = ("S", d >> 3)
            if k not in cache:
                cache[k] = tx.sload(k)
            v = lane(cache[k], d & 7)
            if v:
                out[d] = v
        return out


class Ring(Layout):
    """Absolute direct-mapped ring: page q at q % P. No metadata, no moves."""

    name = "ring"
    P = 128

    def key(self, q):
        return ("R", q % self.P)

    def _place(self, tx, env, k, w, q):
        if w and tag(w) != q + 1:
            # Expiry alone proves the old page dead while fcd lags < ~159 days.
            if not dead(tx, env, w, fcd_first=True):
                raise LiveCollision(self.name)
            w = 0
        return w if w else page_word(q)

    def credit(self, tx, env, day, amount):
        q, i = divmod(day, LANES)
        k = self.key(q)
        w = tx.sload(k)
        if tag(w) != q + 1:
            w = self._place(tx, env, k, w, q)
        new = min(CAP, lane(w, i) + amount)
        tx.sstore(k, set_lane(w, i, new))

    def walk(self, tx, env, start, end):
        out, cache = {}, {}
        for d in range(start + 1, end + 1):
            q, i = divmod(d, LANES)
            if q not in cache:
                w = tx.sload(self.key(q))
                cache[q] = w if tag(w) == q + 1 else 0
            v = lane(cache[q], i)
            if v:
                out[d] = v
        return out


class RebaseA(Layout):
    """Plan candidate B: slot index (q - anchor) % P, anchor kept in slot A."""

    name = "rebaseA"
    P = 128

    def __init__(self):
        super().__init__()
        self.anchor = None

    def key(self, q):
        return ("B", (q - self.anchor) % self.P)

    def _anchor(self, tx, env, q):
        tx.sload(("A",))
        if self.anchor is None:
            self.anchor = q
            tx.sstore(("A",), self.claim_state_word(tx.store.get(("A",), 0)))

    def claim_state_word(self, w):
        if self.anchor is None:
            return w
        return (w & ~META_MASK) | ((self.anchor + 1) << META_SHIFT)

    def credit(self, tx, env, day, amount):
        q, i = divmod(day, LANES)
        self._anchor(tx, env, q)
        k = self.key(q)
        w = tx.sload(k)
        if tag(w) != q + 1:
            if w and (tag(w) - 1 - self.anchor) % self.P == k[1] and not dead(tx, env, w):
                raise LiveCollision(self.name)
            w = page_word(q)
        tx.sstore(k, set_lane(w, i, min(CAP, lane(w, i) + amount)))

    def get_page(self, tx, q):
        if self.anchor is None:
            return 0
        w = tx.sload(self.key(q))
        return w if tag(w) == q + 1 else 0

    def walk(self, tx, env, start, end):
        out, cache = {}, {}
        for d in range(start + 1, end + 1):
            q, i = divmod(d, LANES)
            if q not in cache:
                cache[q] = self.get_page(tx, q)
            v = lane(cache[q], i)
            if v:
                out[d] = v
        return out

    def after_claim(self, tx, env):
        if self.anchor is None or env.last_claim != env.wall:
            return
        qt = (env.wall + 1) // LANES
        if qt == self.anchor:
            return
        w = self.get_page(tx, qt)
        if w and self.key(qt)[1] != 0:
            tx.sstore(("B", 0), w)
            self.meter["copies"] += 1
        self.anchor = qt  # slot A is written by the claim anyway


class Rebase0(RebaseA):
    """Candidate B with no slot-A metadata: physical page 0's tag carries anchor % P."""

    name = "rebase0"

    def claim_state_word(self, w):
        # This variant stores the anchor in page 0, not slot A.
        return w

    def _anchor(self, tx, env, q):
        w0 = tx.sload(("B", 0))
        if w0 == 0:
            self.anchor = q
        # else anchor = (tag(w0) - 1) % P, tracked in self.anchor

    def credit(self, tx, env, day, amount):
        q, i = divmod(day, LANES)
        self._anchor(tx, env, q)
        k = self.key(q)
        w = tx.sload(k)
        if tag(w) != q + 1:
            if w and (tag(w) - 1 - self.anchor) % self.P == k[1]:
                if not dead(tx, env, w):
                    raise LiveCollision(self.name)
            w = page_word(q)
        tx.sstore(k, set_lane(w, i, min(CAP, lane(w, i) + amount)))

    def get_page(self, tx, q):
        if self.anchor is None:
            return 0
        tx.sload(("B", 0))
        return super().get_page(tx, q)

    def after_claim(self, tx, env):
        if self.anchor is None or env.last_claim != env.wall:
            return
        qt = (env.wall + 1) // LANES
        if qt == self.anchor:
            return
        w = self.get_page(tx, qt)
        if self.key(qt)[1] != 0:
            # Page 0 must carry a tag congruent to the new anchor: copy, or retag empty.
            tx.sstore(("B", 0), w if w else page_word(qt))
            self.meter["copies"] += 1
        self.anchor = qt


class Queue(Layout):
    """Plan candidate C: allocated pages form a cycle; head..tail is chronological."""

    name = "queue"
    LIMIT = 128

    def __init__(self):
        super().__init__()
        self.cycle = []  # physical ids in link order
        self.head = self.tail = 0

    def k(self, pid):
        return ("Q", pid)

    def _meta(self, tx):
        old = tx.store.get(("A",), 0)
        new = self.claim_state_word(old)
        if new != old:
            tx.sstore(("A",), new)

    def claim_state_word(self, w):
        if not self.cycle:
            return w
        # Physical IDs, not list positions: insertion does not relabel pages.
        metadata = (self.cycle[self.head] | (self.cycle[self.tail] << 8)
                    | (len(self.cycle) << 16))
        return (w & ~META_MASK) | (metadata << META_SHIFT)

    def credit(self, tx, env, day, amount):
        q, i = divmod(day, LANES)
        tx.sload(("A",))
        if not self.cycle:
            self.cycle = [1]
            self.head = self.tail = 0
            w = page_word(q)
            tx.sstore(self.k(1), set_lane(w, i, min(CAP, amount)))
            self._meta(tx)
            return
        tpid = self.cycle[self.tail]
        w = tx.sload(self.k(tpid))
        if tag(w) == q + 1:
            tx.sstore(self.k(tpid), set_lane(w, i, min(CAP, lane(w, i) + amount)))
            return
        n = len(self.cycle)
        if dead(tx, env, w):
            # Every older page is older than the dead tail: collapse onto it.
            self.head = self.tail
            target = tpid
        else:
            succ = (self.tail + 1) % n
            if succ != self.head:
                target = self.cycle[succ]
                tx.sload(self.k(target))
                self.tail = succ
            else:
                hw = tx.sload(self.k(self.cycle[self.head]))
                if dead(tx, env, hw):
                    target = self.cycle[self.head]
                    self.tail = self.head
                    self.head = (self.head + 1) % n
                else:
                    if n >= self.LIMIT:
                        raise LiveCollision(self.name)
                    target = max(self.cycle) + 1
                    self.cycle.insert(self.tail + 1, target)
                    if self.head > self.tail:
                        self.head += 1
                    self.tail += 1
                    # Splice: the old tail's link field changes.
                    tx.sstore(self.k(tpid), w ^ (1 << 248) or w)
        tx.sstore(self.k(target), set_lane(page_word(q), i, min(CAP, amount)))
        self._meta(tx)

    def walk(self, tx, env, start, end):
        out = {}
        if not self.cycle:
            return out
        n = len(self.cycle)
        pos = self.head
        while True:
            w = tx.sload(self.k(self.cycle[pos]))
            q = tag(w) - 1
            for i in range(LANES):
                d = q * LANES + i
                if start < d <= end and lane(w, i):
                    out[d] = lane(w, i)
            if pos == self.tail or q * LANES > end:
                break
            pos = (pos + 1) % n
        # Retire consumed head pages through metadata (slot A is written anyway).
        while self.head != self.tail:
            w = self.store.get(self.k(self.cycle[self.head]), 0)
            if not page_dead(w, max(end, env.cutoff())):
                break
            self.head = (self.head + 1) % n
        return out


class NearFar(Layout):
    """Page q lives in exactly one of near[q % M] or far[q % F]; pages never move."""

    name = "nearfar"
    M = 8
    F = 128

    def near(self, q):
        return ("N", q % self.M)

    def far(self, q):
        return ("F", q % self.F)

    def credit(self, tx, env, day, amount):
        q, i = divmod(day, LANES)
        kn = self.near(q)
        w = tx.sload(kn)
        k = kn
        if tag(w) != q + 1:
            kf = self.far(q)
            wf = tx.sload(kf)
            if tag(wf) == q + 1:
                k, w = kf, wf
            else:
                # New page: near if its occupant is gone, else far.
                if not w or dead(tx, env, w):
                    w = page_word(q)
                else:
                    k = kf
                    if wf and not dead(tx, env, wf, fcd_first=True):
                        raise LiveCollision(self.name)
                    w = page_word(q)
        tx.sstore(k, set_lane(w, i, min(CAP, lane(w, i) + amount)))

    def walk(self, tx, env, start, end):
        out, cache = {}, {}
        for d in range(start + 1, end + 1):
            q, i = divmod(d, LANES)
            if q not in cache:
                w = tx.sload(self.near(q))
                if tag(w) != q + 1:
                    w = tx.sload(self.far(q))
                    if tag(w) != q + 1:
                        w = 0
                cache[q] = w
            v = lane(cache[q], i)
            if v:
                out[d] = v
        return out


class NearFarHint(NearFar):
    """NearFar plus a credit-only spill marker in the near word's spare top byte.

    When page q spills, near[q % M] (still holding a live older page) records
    0x80 | (q & 0x7F). While q is tomorrow's page, near[q % M] can only be
    rewritten by a page >= q + M, so a credit never misses its own spilled page;
    a stale match is only a wasted far read. Walks do not trust the marker.
    """

    name = "nearfar_hint"

    def credit(self, tx, env, day, amount):
        q, i = divmod(day, LANES)
        kn, kf = self.near(q), self.far(q)
        w = tx.sload(kn)
        if tag(w) == q + 1:
            tx.sstore(kn, set_lane(w, i, min(CAP, lane(w, i) + amount)))
            return
        marker = 0x80 | (q & 0x7F)
        wf = None
        if w and (w >> 248) == marker:
            wf = tx.sload(kf)
            if tag(wf) == q + 1:
                tx.sstore(kf, set_lane(wf, i, min(CAP, lane(wf, i) + amount)))
                return
        if not w or dead(tx, env, w):
            tx.sstore(kn, set_lane(page_word(q), i, min(CAP, amount)))
            return
        if wf is None:
            wf = tx.sload(kf)
        if wf and not dead(tx, env, wf, fcd_first=True):
            raise LiveCollision(self.name)
        tx.sstore(kf, set_lane(page_word(q), i, min(CAP, amount)))
        tx.sstore(kn, (w & ~(0xFF << 248)) | (marker << 248))


def _variant(base, m, label):
    return type(label, (base,), {"name": label, "M": m})


LAYOUTS = [Current, CurrentNoClear, Ring, RebaseA, Rebase0, Queue, NearFar,
           _variant(NearFar, 4, "nearfar4"), _variant(NearFar, 16, "nearfar16"),
           NearFarHint, _variant(NearFarHint, 1, "nearfar1_hint"),
           _variant(NearFarHint, 4, "nearfar4_hint"),
           _variant(NearFarHint, 16, "nearfar16_hint"),
           _variant(NearFarHint, 32, "nearfar32_hint")]


class Player:
    """Drives one layout and a logical ledger through identical operations."""

    def __init__(self, layout_cls):
        self.lay = layout_cls()
        self.env = Env()
        self.ledger = {}

    def credit(self, amount, tx=None):
        day = self.env.wall + 1
        own = tx is None
        tx = tx or Tx(self.lay.store, self.lay.meter)
        self.lay.credit(tx, self.env, day, amount)
        if own:
            tx.close()
        self.ledger[day] = min(CAP, self.ledger.get(day, 0) + amount)

    def claim(self, tx=None, check=True):
        env = self.env
        own = tx is None
        tx = tx or Tx(self.lay.store, self.lay.meter)
        tx.sload(("A",))
        tx.sload(("G",))
        start = max(env.last_claim, max(0, env.fcd - WINDOW))
        got = {}
        if start < env.fcd:
            got = self.lay.walk(tx, env, start, env.fcd)
            env.last_claim = env.fcd
        self.lay.after_claim(tx, env)
        old = tx.store.get(("A",), 0)
        new = (old & ~CURSOR_MASK) | (env.last_claim << CURSOR_SHIFT)
        new = self.lay.claim_state_word(new)
        if new != old:
            tx.sstore(("A",), new)
        if own:
            tx.close()
        if check:
            want = {d: v for d, v in self.ledger.items() if start < d <= env.fcd and v}
            assert got == want, (self.lay.name, env.wall, env.fcd, got, want)
        for d in [d for d in self.ledger if d <= env.fcd]:
            del self.ledger[d]

    def deposit(self, amount):
        tx = Tx(self.lay.store, self.lay.meter)
        self.claim(tx)
        self.credit(amount, tx)
        tx.close()


def differential(layout_cls, seeds=24, days=2600):
    """Random credits/claims/deposits with lagging resolution and long stalls."""
    ops = 0
    for seed in range(seeds):
        rng = random.Random(seed * 7919 + 1)
        p = Player(layout_cls)
        cadence = [1, 3, 7, 8, 29, 120, 731, 10_000][seed % 8]
        stall_at = rng.randrange(200, days - 100) if seed % 3 == 0 else None
        stall_len = 30 if stall_at else 0
        for wall in range(1, days):
            p.env.wall = wall
            stalled = stall_at is not None and stall_at <= wall < stall_at + stall_len
            if not stalled:
                p.env.fcd = wall if rng.random() < 0.8 else wall - 1
            for _ in range(rng.choice([0, 1, 1, 2, 3])):
                p.credit(rng.choice([1, 100, 50_000, CAP]))
                ops += 1
            if wall % cadence == 0 and rng.random() < 0.9:
                if rng.random() < 0.3:
                    p.deposit(100)
                else:
                    p.claim()
                ops += 1
        p.claim()
    return ops


def stall_collision(layout_cls, stall=30, offset=0):
    """Never-claiming daily-credit player holding a full 730-day window, then a stall."""
    p = Player(layout_cls)
    last = 1500 + offset
    try:
        for wall in range(1, last + stall):
            p.env.wall = wall
            if wall < last:
                p.env.fcd = wall
            p.credit(100)
        return None
    except LiveCollision:
        return p.env.wall - p.env.fcd


def min_colliding_stall(layout_cls, limit=60):
    """Shortest resolution lag (over all page alignments) at which a credit must revert."""
    worst = None
    for offset in range(LANES):
        lag = stall_collision(layout_cls, limit, offset)
        if lag is not None and (worst is None or lag < worst):
            worst = lag
    return worst if worst is not None else f"none within {limit} days"


SCENARIOS = {
    # name: (credits per day, claim cadence days or None, order)
    "daily credit, daily claim, credit lands first": (1, 1, "credit_first"),
    "daily credit, daily claim, claim first": (1, 1, "claim_first"),
    "daily deposit (claim+credit, one tx)": (1, 1, "deposit"),
    "3 credits/day, claim weekly": (3, 7, "credit_first"),
    "daily credit, claim every 13d": (1, 13, "credit_first"),
    "daily credit, claim every 14d": (1, 14, "credit_first"),
    "daily credit, claim monthly": (1, 30, "credit_first"),
    "daily credit, claim every 90d": (1, 90, "credit_first"),
    "daily credit, claim every 120d": (1, 120, "credit_first"),
    "daily credit, claim every 730d": (1, 730, "credit_first"),
    "daily credit, never claims": (1, None, "credit_first"),
    "weekly credit, claim monthly": ("weekly", 30, "credit_first"),
}
HORIZONS = [30, 90, 365, 730, 1825, 3650, 10950]


def run_scenario(layout_cls, spec, horizons):
    per_day, cadence, order = spec
    p = Player(layout_cls)
    snaps = {}
    for wall in range(1, max(horizons) + 1):
        p.env.wall = wall
        p.env.fcd = wall
        n = (1 if wall % 7 == 0 else 0) if per_day == "weekly" else per_day
        claim_today = cadence is not None and wall % cadence == 0
        if order == "deposit":
            p.deposit(100)
        else:
            if claim_today and order == "claim_first":
                p.claim(check=False)
            for _ in range(n):
                p.credit(100)
            if claim_today and order == "credit_first":
                p.claim(check=False)
        if wall in horizons:
            snaps[wall] = dict(p.lay.meter)
    return snaps


def accounting_regressions():
    # Advancing lastClaim must change the stored value on every claim, not only
    # the first. Otherwise later claims are incorrectly priced as no-op SSTOREs.
    p = Player(Ring)
    claim_exec = []
    for day in (1, 2, 3):
        p.env.wall = p.env.fcd = day
        p.credit(100)
        tx = Tx(p.lay.store, p.lay.meter)
        p.claim(tx)
        assert (p.lay.store[("A",)] & CURSOR_MASK) >> CURSOR_SHIFT == day
        claim_exec.append(tx.exec)
        tx.close()
    assert claim_exec[0] == claim_exec[1] == claim_exec[2]

    class RecordingTx(Tx):
        def __init__(self, store, meter):
            super().__init__(store, meter)
            self.a_writes = 0

        def sstore(self, k, v):
            if k == ("A",):
                self.a_writes += 1
            super().sstore(k, v)

    # Claim then deposit daily: one queue page is enough and its head/tail/count
    # remain unchanged across page transitions. Do not invent pointer writes.
    p = Player(Queue)
    metadata = None
    for day in range(1, 43):
        p.env.wall = p.env.fcd = day
        tx = RecordingTx(p.lay.store, p.lay.meter)
        p.claim(tx)
        p.credit(100, tx)
        current = p.lay.store[("A",)] & META_MASK
        if metadata is not None:
            assert current == metadata
            assert tx.a_writes == 1, "only the advancing cursor needs a slot-A write"
        metadata = current
        tx.close()

    # User workload: under-two-week claims. Sweep page alignment and both
    # operation orders; four near pages must suffice without any far creation.
    d4 = _variant(NearFarHint, 4, "nearfar4_hint")
    cases = 0
    for cadence in range(1, 15):
        for offset in range(LANES):
            for credit_first in (False, True):
                p = Player(d4)
                for step in range(1, 451):
                    p.env.wall = p.env.fcd = step + offset
                    if step % cadence == 0 and not credit_first:
                        p.claim()
                    p.credit(100)
                    if step % cadence == 0 and credit_first:
                        p.claim()
                p.claim()
                assert not any(k[0] == "F" for k in p.lay.store)
                cases += 1
    return {"advancing_cursor_writes": "pass", "unchanged_queue_metadata": "pass",
            "four_near_pages_no_spill_cases": cases}


def main():
    out = {"scope": "storage-only Glamsterdam model; not EVM traces, not a security proof"}
    out["accounting_regressions"] = accounting_regressions()
    out["differential_ops"] = {c.name: differential(c) for c in LAYOUTS}

    class Rebase106(RebaseA):
        name = "rebaseA_P106"
        P = 106

    out["min_resolution_lag_forcing_credit_revert"] = {
        c.name: min_colliding_stall(c) for c in LAYOUTS + [Rebase106]
    }
    table = {}
    for sname, spec in SCENARIOS.items():
        rows = {}
        for c in LAYOUTS:
            snaps = run_scenario(c, spec, set(HORIZONS))
            row = {f"{h}d": snaps[h]["net"] for h in HORIZONS}
            row["per_year_after_10y"] = (snaps[10950]["net"] - snaps[3650]["net"]) // 20
            row["creations_30y"] = snaps[10950]["creations"]
            row["copies_30y"] = snaps[10950]["copies"]
            row["peak_tx"] = snaps[10950]["peak_tx"]
            rows[c.name] = row
        table[sname] = rows
    out["net_storage_gas"] = table
    print(json.dumps(out, indent=1))


if __name__ == "__main__":
    main()
