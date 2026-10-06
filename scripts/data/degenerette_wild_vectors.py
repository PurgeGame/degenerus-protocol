"""Generate test/fixtures/degenerette-wild-vectors.json: canonical Degenerette reels.

An independent scalar reference of the wild-color rules (it reads no contract source).
`test/stat/DegeneretteWildVectors.test.js` checks every vector against the compiled
production harness; the database, website and simulator replay the same file.

Run: python3 -B scripts/data/degenerette_wild_vectors.py [--check]
"""

from pathlib import Path
import hashlib
import json
import sys

import sha3

OUT = Path(__file__).resolve().parents[2] / "test/fixtures/degenerette-wild-vectors.json"

PLAYER_TICKET_TAG = 0x446567656E506C61796572  # DegenPlayer
RESULT_TICKET_TAG = 0x446567656E526573756C74  # DegenResult
HERO_PICK_TAG = 0x446567656E4865726F  # DegenHero
WWXRP_DRAW_TAG = 0x575758525044726177  # WWXRPDraw
WWXRP_RIG_SALT = 0x52494721  # RIG!
BET_SURVIVAL_TAG = 0x446567656E537572766976616C  # DegenSurvival
BOX_SURVIVAL_TAG = 0x537572766976616C  # Survival
QUICK_PLAY_SALT = 0x51
RANDOM_HERO = 32

BASE_CENTIX = [0, 0, 0, 50, 300, 1000, 10000, 62500, 1817328, 23000000]
ETH_ADD_CENTIX = [0, 0, 0, 0, 0, 0, 240, 4600, 105000, 22408400]
WWXRP_S8, WWXRP_S9 = 480677, 100000000
WWXRP_FLOOR_SCALED = 5762468903
WWXRP_FACTORS = {6: 356636, 7: 1825147, 8: 5245201, 9: 2242955}
KNEES = [0, 305, 500, 30000]
FLIP_CURVE = [9000, 9891, 9970, 9990]
WWXRP_CURVE = [7000, 12400, 12760, 13000]
CURRENCY_ETH, CURRENCY_FLIP, CURRENCY_WWXRP = 0, 1, 3


def keccak(data: bytes) -> int:
    h = sha3.keccak_256()
    h.update(data)
    return int.from_bytes(h.digest(), "big")


def word32(x):
    return x.to_bytes(32, "big")


def hash2(a, b):
    return keccak(word32(a) + word32(b))


def hash4(a, b, c, d):
    return keccak(word32(a) + word32(b) + word32(c) + word32(d))


def ordinary_lanes(rand):
    t = 0
    for q in range(4):
        lane = rand >> (64 * q)
        t |= (((lane & 7) << 3) | ((lane >> 32) & 7)) << (8 * q)
    return t


def house_lanes(rand):
    t = 0
    for q in range(4):
        lane = rand >> (64 * q)
        sym = (lane >> 32) & 7
        t |= (0x40 | sym if (lane >> 3) & 15 == 0 else ((lane & 7) << 3) | sym) << (8 * q)
    return t


def spin_symbol(seed, symbol):
    return hash2(seed, HERO_PICK_TAG) % 24 if symbol == RANDOM_HERO else symbol


def player_ticket(seed, symbol):
    t = ordinary_lanes(hash2(seed, PLAYER_TICKET_TAG))
    shift = (symbol >> 3) * 8
    return (t & ~(0xFF << shift) & 0xFFFFFFFF) | ((0x40 | (symbol & 7)) << shift)


def score(p, r):
    s = w = 0
    for q in range(4):
        a, b = (p >> 8 * q) & 0xFF, (r >> 8 * q) & 0xFF
        aw, bw = bool(a & 0x40), bool(b & 0x40)
        s += (a & 7) == (b & 7)
        s += 2 if aw and bw else 1 if aw or bw else int((a >> 3) & 7 == (b >> 3) & 7)
        w += bw
    return s, w


def rig(p, r, hero_quadrant, rig_seed):
    """WWXRP help: (rigged house ticket, help applied)."""
    if rig_seed % 20:
        return r, False
    s, _ = score(p, r)
    matches = s - ((r >> (8 * hero_quadrant + 6)) & 1)
    if s < 3 or matches > 6:
        return r, False
    eligible = []
    for q in range(4):
        a, b = (p >> 8 * q) & 0xFF, (r >> 8 * q) & 0xFF
        if not (a | b) & 0x40 and (a >> 3) & 7 != (b >> 3) & 7:
            eligible.append(0x38 << (8 * q))
        if q != hero_quadrant and a & 7 != b & 7:
            eligible.append(7 << (8 * q))
    mask = eligible[hash2(rig_seed, 1) % len(eligible)]
    return (r & ~mask & 0xFFFFFFFF) | (p & mask), True


def curve(points, activity):
    for i in range(1, 4):
        if activity <= KNEES[i]:
            return points[i - 1] + (activity - KNEES[i - 1]) * (points[i] - points[i - 1]) // (KNEES[i] - KNEES[i - 1])
    return points[-1]


def payout(s, w, currency, stake, activity):
    if s < 3:
        return 0
    if currency == CURRENCY_WWXRP:
        base = WWXRP_S8 if s == 8 else WWXRP_S9 if s == 9 else BASE_CENTIX[s]
        scaled = WWXRP_FLOOR_SCALED
        if s >= 6:
            scaled += (curve(WWXRP_CURVE, activity) - 7000) * WWXRP_FACTORS[s]
        return stake * base * (4 + w) * scaled // 4_000_000_000_000
    rate = BASE_CENTIX[s] * curve(FLIP_CURVE, activity)
    if currency == CURRENCY_ETH:
        rate += ETH_ADD_CENTIX[s] * 10_000
    return stake * rate * (4 + w) // 4_000_000


def bet_house_seed(word, index, spin):
    pre = word32(word) + index.to_bytes(4, "big") + (bytes([spin]) if spin else b"")
    return keccak(pre + bytes([QUICK_PLAY_SALT]))


def roll(seed, house_seed, symbol, currency):
    sym = spin_symbol(seed, symbol)
    p = player_ticket(seed, sym)
    natural = house_lanes(house_seed)
    r, helped = natural, False
    if currency == CURRENCY_WWXRP:
        r, helped = rig(p, natural, sym >> 3, hash2(seed, WWXRP_RIG_SALT))
    s, w = score(p, r)
    return {"hero": sym, "player": p, "natural_house": natural, "house": r, "help_applied": helped,
            "score": s, "wilds": w}


def h(x, n=8):
    return "0x%0*x" % (n, x)


def bet_vector(word, index, symbol, spin, stake_eth, stake_flip, activity):
    seed = hash4(word, index, symbol, spin)
    v = roll(seed, bet_house_seed(word, index, spin), symbol, CURRENCY_ETH)
    return {
        "word": h(word, 64), "index": index, "symbol": symbol, "spin": spin,
        "player": h(v["player"]), "house": h(v["house"]), "score": v["score"], "wilds": v["wilds"],
        "tail_byte": v["score"] | (v["wilds"] << 4),
        "activity": activity,
        "eth_stake_wei": str(stake_eth), "eth_payout_wei": str(payout(v["score"], v["wilds"], 0, stake_eth, activity)),
        "flip_stake": str(stake_flip), "flip_payout_pre_survival": str(payout(v["score"], v["wilds"], 1, stake_flip, activity)),
    }


def find_bet(index, symbol, spin, want):
    for word in range(1, 10**8):
        seed = hash4(word, index, symbol, spin)
        p = player_ticket(seed, symbol)
        s, w = score(p, house_lanes(bet_house_seed(word, index, spin)))
        if want(s, w):
            return word
    raise RuntimeError("no word")


def main():
    bets = []
    # Every hero quadrant, ordinary and wild hero-lane house colors, scores 1..8, later spins.
    cases = [
        (0, 0, lambda s, w: s == 1), (1, 0, lambda s, w: s == 2), (9, 0, lambda s, w: s == 3 and w == 0),
        (17, 0, lambda s, w: s == 4 and w >= 1), (5, 3, lambda s, w: s == 5),
        (12, 7, lambda s, w: s == 6), (20, 24, lambda s, w: s == 7), (2, 0, lambda s, w: s >= 3 and w == 2),
    ]
    for symbol, spin, want in cases:
        word = find_bet(1, symbol, spin, want)
        bets.append(bet_vector(word, 1, symbol, spin, 10**16, 1000, [0, 305, 500, 30000][len(bets) % 4]))
    # A paid S8, then FLIP survival in both outcomes for one owner/bet.
    word = find_bet(1, 11, 0, lambda s, w: s == 8)
    bets.append(bet_vector(word, 1, 11, 0, 10**16, 1000, 30000))
    owner = 0x00000000000000000000000000000000000000AA
    survival = []
    for want in (1, 0):
        for word in range(1, 1000):
            if hash4(word, owner, 1, BET_SURVIVAL_TAG) & 1 == want:
                survival.append({"word": h(word, 64), "owner": h(owner, 40), "bet_id": 1, "survives": bool(want)})
                break

    boxes = []
    # Natural S9 with two house wilds through the WWXRP and ETH box paths (pinned contract tests).
    jackpot_seed = 359696
    draw = hash2(jackpot_seed, WWXRP_DRAW_TAG)
    for currency, seed in ((CURRENCY_WWXRP, draw), (CURRENCY_ETH, draw)):
        v = roll(seed, hash2(seed, RESULT_TICKET_TAG), 15, currency)
        boxes.append({"currency": currency, "award_seed": h(jackpot_seed, 64) if currency == CURRENCY_WWXRP else None,
                      "spin_seed": h(seed, 64), "symbol": 15, **{k: h(v[k]) if k in ("player", "natural_house", "house") else v[k] for k in v},
                      "activity": 0 if currency == CURRENCY_WWXRP else 30000,
                      "stake": str(10**18 if currency == CURRENCY_WWXRP else 10**16),
                      "raw_payout": str(payout(v["score"], v["wilds"], currency, 10**18 if currency == CURRENCY_WWXRP else 10**16,
                                               0 if currency == CURRENCY_WWXRP else 30000))})
    # WWXRP help applied and not applied, including a random hero.
    found = {True: 0, False: 0}
    for k in range(1, 100000):
        draw = hash2(k, WWXRP_DRAW_TAG)
        symbol = RANDOM_HERO if k % 2 else k % 24
        v = roll(draw, hash2(draw, RESULT_TICKET_TAG), symbol, CURRENCY_WWXRP)
        if v["score"] < 3 or found[v["help_applied"]] >= 2:
            continue
        found[v["help_applied"]] += 1
        boxes.append({"currency": CURRENCY_WWXRP, "award_seed": h(k, 64), "spin_seed": h(draw, 64), "symbol": symbol,
                      **{kk: h(v[kk]) if kk in ("player", "natural_house", "house") else v[kk] for kk in v},
                      "activity": 305, "stake": str(10**18),
                      "raw_payout": str(payout(v["score"], v["wilds"], CURRENCY_WWXRP, 10**18, 305))})
        if all(n >= 2 for n in found.values()):
            break
    # Three-spin FLIP box chain: spin i reel seed = hash2(seed, i); one survival flip for the chain.
    for k in range(1000):
        chain_seed = hash2(0xF11F, k)
        chain = []
        for i in range(3):
            ss = hash2(chain_seed, i)
            v = roll(ss, hash2(ss, RESULT_TICKET_TAG), RANDOM_HERO, CURRENCY_FLIP)
            chain.append({"spin_seed": h(ss, 64), **{k: h(v[k]) if k in ("player", "natural_house", "house") else v[k] for k in v}})
        if any(c["score"] >= 3 for c in chain):
            break
    packed = 0
    for i, v in enumerate(chain):
        packed |= (int(v["player"], 16) | (int(v["house"], 16) << 32) | (v["score"] << 64)) << (72 * i)
    survived = hash2(chain_seed, BOX_SURVIVAL_TAG) & 1 == 1
    packed |= (3 << 216) | ((1 << 224) if survived else 0)
    flip_chain = {"box_seed": h(chain_seed, 64), "spins": chain, "survived": survived, "packed_spins": h(packed, 64)}

    producers = []
    for k in range(6):
        rand = keccak(b"producer" + bytes([k]))
        if k == 0:
            rand &= ~(0xF << 3)  # lane 0 wild
        producers.append({"rand": h(rand, 64), "ordinary": h(ordinary_lanes(rand)), "house": h(house_lanes(rand))})

    data = {
        "description": "Canonical Degenerette wild-color reels. Lane byte: bit7 0 | bit6 wild | bits5-3 color | bits2-0 symbol; quadrant = byte position. DegeneretteResolved tail byte = score | houseWilds << 4. BoxSpin spin = player:32 | house:32 | score:8 per 72 bits, count at 216, survived at 224.",
        "generator": "scripts/data/degenerette_wild_vectors.py",
        "tables": {"base_centix": BASE_CENTIX, "eth_add_centix": ETH_ADD_CENTIX, "wwxrp_s8_centix": WWXRP_S8,
                   "wwxrp_s9_centix": WWXRP_S9, "wwxrp_floor_scaled": WWXRP_FLOOR_SCALED,
                   "wwxrp_bonus_factors": WWXRP_FACTORS, "activity_knees": KNEES,
                   "flip_curve_bps": FLIP_CURVE, "wwxrp_curve_bps": WWXRP_CURVE},
        "producers": producers,
        "bet_spins": bets,
        "flip_survival": survival,
        "box_spins": boxes,
        "flip_box_chain": flip_chain,
    }
    text = json.dumps(data, indent=2) + "\n"
    if "--check" in sys.argv:
        assert OUT.read_text() == text, "fixture is stale; regenerate"
    else:
        OUT.parent.mkdir(parents=True, exist_ok=True)
        OUT.write_text(text)
    print(OUT, hashlib.sha256(text.encode()).hexdigest())


if __name__ == "__main__":
    main()
