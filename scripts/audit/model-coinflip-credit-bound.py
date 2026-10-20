#!/usr/bin/env python3
"""Credit hot-path bound and payer split for the coinflip stake layouts.

Extends scripts/audit/model-coinflip-reuse-lifetime.py (imported by path, unmodified).
Storage-only Glamsterdam pricing; NOT an EVM trace and NOT a security proof.

Questions answered:
  1. Can a credit revert, or cost more than a constant, in ANY state, including a
     never-claiming account, a 30-day stall, and years of credits after resolution
     has stopped for good (game over)?
  2. What does the protocol pay (credit transactions) versus players (claims),
     for accounts that claim at least every two weeks?

Layout D' = plan D plus an absolute overflow tier: page q lives in near[q % M],
else far[q % 128], else overflow[q]. Overflow is keyed by the absolute page, so
it can never hold another page: every branch places, none reverts.

Run: python3 -I scripts/audit/model-coinflip-credit-bound.py --readiness
Other modes retain the historical comparison and window sensitivity studies.
"""

import importlib.util
import hashlib
import json
import pathlib
import random

_path = pathlib.Path(__file__).with_name("model-coinflip-reuse-lifetime.py")
_spec = importlib.util.spec_from_file_location("lifetime", _path)
L = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(L)

LANES, CAP, tag, lane, set_lane, page_word, dead = (
    L.LANES, L.CAP, L.tag, L.lane, L.set_lane, L.page_word, L.dead)


class NearFarOverflow(L.NearFarHint):
    """Plan D with a third, absolute home. Credits never revert."""

    name = "Dprime4"
    M = 4

    def ovf(self, q):
        return ("O", q)

    def _merge(self, tx, k, w, i, amount):
        tx.sstore(k, set_lane(w, i, min(CAP, lane(w, i) + amount)))

    def credit(self, tx, env, day, amount):
        if amount == 0:
            return
        q, i = divmod(day, LANES)
        kn, kf, ko = self.near(q), self.far(q), self.ovf(q)
        w = tx.sload(kn)
        if tag(w) == q + 1:
            return self._merge(tx, kn, w, i, amount)
        marker = 0x80 | (q & 0x7F)
        wf = wo = None
        if w and (w >> 248) == marker:
            # Page q left near during its own window: it is in far or overflow.
            wf = tx.sload(kf)
            if tag(wf) == q + 1:
                return self._merge(tx, kf, wf, i, amount)
            wo = tx.sload(ko)
            if wo:
                assert tag(wo) == q + 1
                return self._merge(tx, ko, wo, i, amount)
        fresh = set_lane(page_word(q), i, min(CAP, amount))
        if not w or dead(tx, env, w):
            tx.sstore(kn, fresh)
            return
        if wf is None:
            wf = tx.sload(kf)
        flagged = (w & ~(0xFF << 248)) | (marker << 248)
        if not wf or dead(tx, env, wf, fcd_first=True):
            tx.sstore(kf, fresh)
            tx.sstore(kn, flagged)
            return
        if wo is None:
            wo = tx.sload(ko)
        assert wo == 0, "a placed page always leaves its marker in near"
        tx.sstore(ko, fresh)
        tx.sstore(kn, flagged)

    def walk(self, tx, env, start, end):
        out, cache = {}, {}
        for d in range(start + 1, end + 1):
            q, i = divmod(d, LANES)
            if q not in cache:
                w = tx.sload(self.near(q))
                if tag(w) != q + 1:
                    w = tx.sload(self.far(q))
                    if tag(w) != q + 1:
                        w = tx.sload(self.ovf(q))
                        assert w == 0 or tag(w) == q + 1
                cache[q] = w
            v = lane(cache[q], i)
            if v:
                out[d] = v
        return out


def variant(base, m, label):
    return type(label, (base,), {"name": label, "M": m})


D4 = NearFarOverflow
D8 = variant(NearFarOverflow, 8, "Dprime8")
D16 = variant(NearFarOverflow, 16, "Dprime16")
LAYOUTS = [L.Current, L.Ring, variant(L.NearFarHint, 4, "D4_twotier"),
           variant(L.NearFarHint, 16, "D16_twotier"), D4, D8, D16]


def new_meter():
    return dict(exec=0, state=0, refund=0, net=0, creations=0, peak_tx=0, copies=0)


class SplitPlayer(L.Player):
    """Automatic credits bill the protocol meter; claims bill the player meter."""

    def __init__(self, layout_cls):
        super().__init__(layout_cls)
        self.proto, self.player = new_meter(), new_meter()

    def credit(self, amount, tx=None):
        own = tx is None
        tx = tx or L.Tx(self.lay.store, self.proto)
        super().credit(amount, tx)
        if own:
            tx.close()

    def claim(self, tx=None, check=True):
        own = tx is None
        tx = tx or L.Tx(self.lay.store, self.player)
        super().claim(tx, check)
        if own:
            tx.close()

    def tomorrow(self):
        """The tomorrow view must equal the ledger (free view; scratch meter)."""
        if isinstance(self.lay, L.Current):
            return  # its walk clears lanes; reading through it would mutate state
        d = self.env.wall + 1
        got = self.lay.walk(L.Tx(self.lay.store, new_meter()), self.env, d - 1, d).get(d, 0)
        assert got == self.ledger.get(d, 0), (self.lay.name, d, got, self.ledger.get(d, 0))


def drive(layout_cls, days, claim_gap, freeze_at=None, seed=0, check=True, snaps=()):
    """Daily credits; claims after `claim_gap(rng)` days (None = never).

    freeze_at: resolution stops for good on that wall day (game over).
    """
    rng = random.Random(seed)
    p = SplitPlayer(layout_cls)
    next_claim = claim_gap(rng)
    out, reverted = {}, None
    for wall in range(1, days + 1):
        p.env.wall = wall
        if freeze_at is None or wall < freeze_at:
            p.env.fcd = wall
        try:
            p.credit(100)
        except L.LiveCollision:
            reverted = wall
            break
        if check and wall % 37 == 0:
            p.tomorrow()
        if next_claim is not None and wall >= next_claim:
            p.claim(check=check)
            gap = claim_gap(rng)
            next_claim = None if gap is None else wall + gap
        if wall in snaps:
            out[wall] = (dict(p.proto), dict(p.player))
    return p, out, reverted


GAPS = {
    "claims every 1-14 days": lambda r: r.randint(1, 14),
    "claims every 1-14 days, 1 in 10 gaps 21-60 days":
        lambda r: r.randint(21, 60) if r.random() < 0.1 else r.randint(1, 14),
    "claims every 7 days": lambda r: 7,
    "never claims": lambda r: None,
}


def post_gameover(layout_cls):
    """Resolution stops on day 400 for good; credits continue for 2,700 more days."""
    rows = {}
    for label, gap in (("claims every 14 days", lambda r: 14), ("never claims", lambda r: None)):
        p, _, reverted = drive(layout_cls, 3100, gap, freeze_at=400)
        rows[label] = {
            "credit_revert_on_day": reverted,
            "worst_single_credit_gas": p.proto["peak_tx"],
            "creations": p.proto["creations"],
        }
    return rows


def stress_differential(layout_cls, seeds=16):
    """Random credits/claims with stalls, then a permanent freeze; ledger-checked."""
    ops = 0
    for seed in range(seeds):
        rng = random.Random(10_007 * seed + 3)
        p = SplitPlayer(layout_cls)
        freeze = rng.randrange(300, 1500)
        stall = rng.randrange(100, freeze - 40)
        cadence = [1, 3, 9, 14, 40, 200, 900, None][seed % 8]
        for wall in range(1, 4200):
            p.env.wall = wall
            if wall < freeze and not (stall <= wall < stall + 30):
                p.env.fcd = wall if rng.random() < 0.85 else wall - 1
            for _ in range(rng.choice([0, 1, 1, 2])):
                try:
                    p.credit(rng.choice([1, 100, CAP]))
                except L.LiveCollision:
                    return f"REVERT seed {seed} day {wall}"
                ops += 1
            if rng.random() < 0.05:
                p.tomorrow()
            if cadence and wall % cadence == 0:
                p.claim()
                ops += 1
        p.claim()
    return ops


def main():
    out = {"scope": "storage-only Glamsterdam model; not EVM traces, not a security proof"}
    out["lifetime_differential_ops"] = {D4.name: L.differential(D4), D16.name: L.differential(D16)}
    out["stress_differential_with_permanent_freeze"] = {c.name: stress_differential(c) for c in LAYOUTS}
    out["post_gameover_credits"] = {c.name: post_gameover(c) for c in LAYOUTS}
    out["min_resolution_lag_forcing_credit_revert"] = {
        c.name: L.min_colliding_stall(c) for c in LAYOUTS}
    years = (365, 3650, 10950)
    table = {}
    for gname, gap in GAPS.items():
        rows = {}
        for c in LAYOUTS:
            p, snaps, reverted = drive(c, 10950, gap, seed=7, check=False, snaps=set(years))
            pr1, pl1 = snaps[365]
            pr10, pl10 = snaps[3650]
            pr30, pl30 = snaps[10950]
            rows[c.name] = {
                "protocol_credit_gas_year1": pr1["net"],
                "protocol_credit_gas_per_year_after_10y": (pr30["net"] - pr10["net"]) // 20,
                "protocol_credit_gas_30y": pr30["net"],
                "player_claim_gas_per_year_after_10y": (pl30["net"] - pl10["net"]) // 20,
                "worst_single_credit_gas": pr30["peak_tx"],
                "creations_30y": pr30["creations"],
                "reverted": reverted,
            }
        table[gname] = rows
    out["daily_credit_100_flip"] = table
    print(json.dumps(out, indent=1))


if __name__ == "__main__" and not __import__("sys").argv[1:]:
    main()


# ---------------------------------------------------------------------------
# Claim-window study: W = 730 (current), 180 (historical), 90 (active plan).
# ---------------------------------------------------------------------------


class RingOverflow(L.Layout):
    """Page q lives in ring[q % P], else overflow[q] (absolute). No near tier.

    With P * 7 >= W + 1 + lag + 6, the ring occupant is provably expired by the
    resolution clock alone, so a credit never reads player state. Outside that
    normal-lag bound, overflow preserves live stakes with bounded per-credit work.
    """

    name = "RingOvf"
    P = 32

    def key(self, q):
        return ("R", q % self.P)

    def ovf(self, q):
        return ("O", q)

    def credit(self, tx, env, day, amount):
        if amount == 0:
            return
        q, i = divmod(day, LANES)
        k, ko = self.key(q), self.ovf(q)
        w = tx.sload(k)
        if tag(w) == q + 1:
            tx.sstore(k, set_lane(w, i, min(CAP, lane(w, i) + amount)))
            return
        marker = 0x80 | (q & 0x7F)
        wo = None
        if w and (w >> 248) == marker:
            wo = tx.sload(ko)
            if wo:
                assert tag(wo) == q + 1
                tx.sstore(ko, set_lane(wo, i, min(CAP, lane(wo, i) + amount)))
                return
        fresh = set_lane(page_word(q), i, min(CAP, amount))
        if not w or dead(tx, env, w, fcd_first=True):
            tx.sstore(k, fresh)
            return
        if wo is None:
            wo = tx.sload(ko)
        assert wo == 0, "a placed page always leaves its marker in the ring word"
        tx.sstore(ko, fresh)
        tx.sstore(k, (w & ~(0xFF << 248)) | (marker << 248))

    def walk(self, tx, env, start, end):
        out, cache = {}, {}
        for d in range(start + 1, end + 1):
            q, i = divmod(d, LANES)
            if q not in cache:
                w = tx.sload(self.key(q))
                if tag(w) != q + 1:
                    w = tx.sload(self.ovf(q))
                    assert w == 0 or tag(w) == q + 1
                cache[q] = w
            v = lane(cache[q], i)
            if v:
                out[d] = v
        return out


def sized(base, label, **kw):
    return type(label, (base,), dict(kw, name=label))


class BatchPlayer(SplitPlayer):
    """Credit inside a batch: another recipient already warmed the resolution clock."""

    def credit(self, amount, tx=None):
        if tx is None:
            tx = L.Tx(self.lay.store, self.proto)
            tx.warm.add(("G",))
            tx.orig[("G",)] = self.lay.store.get(("G",), 0)
            L.Player.credit(self, amount, tx)
            tx.close()
        else:
            L.Player.credit(self, amount, tx)


def drive2(player_cls, layout_cls, days, claim_gap, active_days=None, seed=7):
    rng = random.Random(seed)
    p = player_cls(layout_cls)
    next_claim = claim_gap(rng)
    worst_claim = 0
    for wall in range(1, days + 1):
        p.env.wall = p.env.fcd = wall
        if active_days is None or wall <= active_days:
            p.credit(100)
        if next_claim is not None and wall >= next_claim:
            before = p.player["peak_tx"]
            p.claim(check=False)
            worst_claim = max(worst_claim, p.player["peak_tx"], before)
            gap = claim_gap(rng)
            next_claim = None if gap is None else wall + gap
    return p


WINDOW_STUDY = {
    730: [sized(NearFarOverflow, "Dprime4_F128", M=4, F=128),
          sized(NearFarOverflow, "Dprime16_F128", M=16, F=128),
          sized(RingOverflow, "RingOvf128", P=128)],
    180: [sized(NearFarOverflow, "Dprime4_F32", M=4, F=32),
          sized(NearFarOverflow, "Dprime16_F32", M=16, F=32),
          sized(RingOverflow, "RingOvf32", P=32)],
    90: [sized(NearFarOverflow, "Dprime4_F15", M=4, F=15),
         sized(RingOverflow, "RingOvf15", P=15)],
}
STUDY_GAPS = {
    "1-14d claims, 30y": (lambda r: r.randint(1, 14), 10950, None),
    "1-14d + 1/10 gaps 21-60d, 30y": (
        lambda r: r.randint(21, 60) if r.random() < 0.1 else r.randint(1, 14), 10950, None),
    "never claims, 30y": (lambda r: None, 10950, None),
    "active 90 days then gone": (lambda r: r.randint(1, 14), 400, 90),
    "active 1 year then gone": (lambda r: r.randint(1, 14), 800, 365),
}


def window_study():
    out = {}
    saved = L.WINDOW
    try:
        for window, layouts in WINDOW_STUDY.items():
            L.WINDOW = window
            res = {}
            for c in layouts:
                checks = {"differential_ops": L.differential(c),
                          "stress_with_freeze": stress_differential(c),
                          "post_gameover": post_gameover(c),
                          "min_revert_lag": L.min_colliding_stall(c)}
                rows = {}
                for g, (gap, days, active) in STUDY_GAPS.items():
                    single = drive2(SplitPlayer, c, days, gap, active)
                    batch = drive2(BatchPlayer, c, days, gap, active)
                    rows[g] = {
                        "protocol_single_M": round(single.proto["net"] / 1e6, 2),
                        "protocol_batch_M": round(batch.proto["net"] / 1e6, 2),
                        "player_claims_M": round(single.player["net"] / 1e6, 2),
                        "worst_credit": single.proto["peak_tx"],
                        "worst_claim": single.player["peak_tx"],
                        "creations": single.proto["creations"],
                    }
                res[c.name] = {"checks": checks, "rows": rows}
            out[f"W={window}"] = res
    finally:
        L.WINDOW = saved
    return out


if __name__ == "__main__" and __import__("sys").argv[1:] == ["--window-study"]:
    print(json.dumps(window_study(), indent=1))


# Window sweep: ring sized to the window plus normal resolution lag (overflow covers stalls).
def ring_pages(window, lag=3):
    return -(-(window + 1 + lag + LANES - 1) // LANES)


def window_sweep():
    out = {}
    saved = L.WINDOW
    try:
        for window in (730, 180, 90, 60, 30, 14):
            L.WINDOW = window
            pages = ring_pages(window)
            layouts = [sized(RingOverflow, f"RingOvf{pages}", P=pages)]
            if window in (730, 180, 90):
                layouts.append(sized(NearFarOverflow, f"Dprime4_F{pages}", M=4, F=pages))
            for c in layouts:
                checks = {"differential_ops": L.differential(c),
                          "stress_with_freeze": stress_differential(c),
                          "post_gameover_reverts": [v["credit_revert_on_day"]
                                                    for v in post_gameover(c).values()],
                          "worst_credit_any_state": max(v["worst_single_credit_gas"]
                                                        for v in post_gameover(c).values()),
                          "min_revert_lag": L.min_colliding_stall(c)}
                rows = {}
                for g, (gap, days, active) in STUDY_GAPS.items():
                    batch = drive2(BatchPlayer, c, days, gap, active)
                    single = drive2(SplitPlayer, c, days, gap, active)
                    rows[g] = [round(batch.proto["net"] / 1e6, 2), round(single.proto["net"] / 1e6, 2),
                               round(single.player["net"] / 1e6, 2), single.proto["creations"],
                               single.player["peak_tx"]]
                out[f"W={window} {c.name}"] = {"checks": checks, "rows": rows}
    finally:
        L.WINDOW = saved
    return out


if __name__ == "__main__" and __import__("sys").argv[1:] == ["--window-sweep"]:
    print(json.dumps(window_sweep(), indent=1))


def readiness_regressions():
    """Check the review's zero-credit case and the selected layout's boundaries.

    Inputs are already whole-FLIP amounts, as in the other models. Decimal
    conversion, public entry authorization and payout accounting need Solidity tests.
    """
    r90 = sized(RingOverflow, "R90_P15", P=15)
    d90 = sized(NearFarOverflow, "D90_M4_F15", M=4, F=15)
    cases = []

    def no_op(p, label):
        before = dict(p.lay.store)
        meter = new_meter()
        tx = L.Tx(p.lay.store, meter)
        p.lay.credit(tx, p.env, p.env.wall + 1, 0)
        tx.close()
        assert p.lay.store == before, (p.lay.name, label, "zero changed storage")
        assert meter == new_meter(), (p.lay.name, label, "zero accessed storage")
        cases.append(f"{p.lay.name}:{label}")

    for cls, collision_pages in ((r90, 15), (d90, 4)):
        p = SplitPlayer(cls)
        p.env.wall = p.env.fcd = 1
        no_op(p, "empty_account")
        p.credit(100)
        no_op(p, "matching_page")
        p.credit(CAP)
        no_op(p, "saturated_lane")
        # Advance by enough pages to reuse the same ring/near home, after expiry.
        p.env.wall = p.env.fcd = collision_pages * 7 * 30 + 1
        no_op(p, "expired_occupant")

    # Construct a genuine R collision during a freeze. A zero must neither spill
    # nor change a hint; a positive credit must preserve both old and future stakes.
    p = SplitPlayer(r90)
    p.env.wall = 1
    p.credit(100)  # day 2, page 0
    p.env.wall = 105  # tomorrow day 106, page 15, same ring home
    no_op(p, "live_collision_before_spill")
    p.credit(100)
    assert ("O", 15) in p.lay.store
    no_op(p, "existing_overflow")
    p.tomorrow()

    # Recovery makes the ring occupant dead while tomorrow's spilled page is
    # still current. A later credit must merge in overflow, never duplicate it.
    p.env.fcd = p.env.wall
    p.claim()
    p.credit(50)
    p.tomorrow()
    assert lane(p.lay.store[("O", 15)], 106 % 7) == 150
    assert tag(p.lay.store[("R", 0)]) != 16

    # Repeat the 7-bit hint while the absolute page differs: a hint collision
    # must not relabel or overwrite the old overflow page.
    p = SplitPlayer(r90)
    p.env.wall = 1
    p.credit(100)
    p.env.wall = 15 * 7
    p.credit(100)
    old_overflow = p.lay.store[("O", 15)]
    q = 15 * 129  # same q % 15 and q % 128 as page 15
    p.env.wall = q * 7
    no_op(p, "stale_matching_hint")
    p.credit(50)
    p.tomorrow()
    assert p.lay.store[("O", 15)] == old_overflow
    assert tag(p.lay.store[("O", q)]) == q + 1

    # Force D's third tier as well, so its zero guard is tested beyond near/far.
    p = SplitPlayer(d90)
    for q in (0, 60, 120):
        p.env.wall = q * 7 + 1
        p.credit(100)
    assert ("O", 120) in p.lay.store
    no_op(p, "existing_third_tier")

    # First expired day, oldest live day and tomorrow, for all seven alignments.
    for offset in range(LANES):
        latest = 200 + offset
        p = SplitPlayer(r90)
        for day in (latest - 90, latest - 89, latest + 1):
            p.env.wall = day - 1
            p.env.fcd = min(day - 1, latest)
            p.credit(100)
        p.env.wall = p.env.fcd = latest
        cutoff = latest - 90
        got = p.lay.walk(L.Tx(p.lay.store, new_meter()), p.env, cutoff, latest)
        assert got == {latest - 89: 100}
        p.claim()
        p.tomorrow()
    return {"zero_credit_cases": cases, "zero_credit_cases_passed": len(cases),
            "recovery_preserves_overflow_home": "pass", "hint_wrap_preserves_old_page": "pass",
            "ninety_day_boundary_alignments_passed": LANES}


def readiness():
    """Reproducible preparation gate for the selected 90-day design."""
    saved = L.WINDOW
    try:
        L.WINDOW = 90
        r90 = sized(RingOverflow, "R90_P15", P=15)
        d90 = sized(NearFarOverflow, "D90_M4_F15", M=4, F=15)
        out = {"scope": "storage model only; native full-call gas and protocol integration remain required",
               "window_days": 90, "ring_pages": 15,
               "model_sha256": hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(),
               "lifetime_model_sha256": hashlib.sha256(_path.read_bytes()).hexdigest(),
               "regressions": readiness_regressions(), "layouts": {}}
        for cls in (r90, d90):
            differential_ops = L.differential(cls)
            freeze_ops = stress_differential(cls)
            postgame = post_gameover(cls)
            assert isinstance(differential_ops, int) and differential_ops > 0, (cls.name, differential_ops)
            assert isinstance(freeze_ops, int) and freeze_ops > 0, (cls.name, freeze_ops)
            assert all(row["credit_revert_on_day"] is None for row in postgame.values()), (cls.name, postgame)
            out["layouts"][cls.name] = {"differential_operations": differential_ops,
                                        "freeze_stress_operations": freeze_ops,
                                        "post_gameover": postgame}
        out["ninety_day_workloads"] = {}
        for label, gap in GAPS.items():
            rows = {}
            for cls in (L.Current, r90, d90):
                p = drive2(BatchPlayer, cls, 10950, gap)
                rows[cls.name] = {"protocol_credit_storage_gas_30y": p.proto["net"],
                                  "player_claim_storage_gas_30y": p.player["net"],
                                  "credit_creations_30y": p.proto["creations"]}
            out["ninety_day_workloads"][label] = rows
        return out
    finally:
        L.WINDOW = saved


if __name__ == "__main__" and __import__("sys").argv[1:] == ["--readiness"]:
    print(json.dumps(readiness(), indent=2))
