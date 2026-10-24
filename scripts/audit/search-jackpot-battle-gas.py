#!/usr/bin/env python3
"""Find real RNG witnesses for long distinct-level jackpot construction walks.

Uses the production keccak256/ABI encoding, 99 eligible levels and replacement
sampling. This ranks queue topologies, not EVM gas. Replay witnesses through the
production worker in JackpotBattleConstructionMaximumGas.t.sol for gas evidence.
Requires PyCryptodome (Crypto.Hash.keccak).
"""
import argparse
import json
from Crypto.Hash import keccak


def digest(data):
    return keccak.new(digest_bits=256, data=data).digest()


def word(value):
    return value.to_bytes(32, "big")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seeds", type=int, default=100_000)
    parser.add_argument("--start", type=int, default=1)
    parser.add_argument("--level", type=int, default=40)
    args = parser.parse_args()
    tag = word(66)  # RngTags.FUTURE_BATTLE
    mult_tag = word(33)  # RngTags.CRAPS_JACKPOT_MULT
    ordinals = [word(i) for i in range(100)]
    best = {}
    top = []
    for seed in range(args.start, args.start + args.seeds):
        battle = digest(tag + word(seed))
        seen = set()
        for ordinal in ordinals:
            offset = int.from_bytes(digest(word(67) + battle + ordinal), "big") % 99
            if offset in seen:
                break
            seen.add(offset)
        roll = int.from_bytes(digest(mult_tag + battle), "big") % 1000
        multiplier = 5000 if roll < 900 else 30000 if roll < 990 else 200000 if roll < 999 else 1000000
        row = {"seed": seed, "distinct_prefix": len(seen), "roll": roll,
               "multiplier_bps": multiplier}
        if multiplier not in best or len(seen) > best[multiplier]["distinct_prefix"]:
            best[multiplier] = row
        top.append(row)
        top.sort(key=lambda r: (-r["distinct_prefix"], r["seed"]))
        del top[12:]
    print(json.dumps({"start": args.start, "seeds": args.seeds, "level": args.level,
                      "top": top, "best_by_multiplier": best}, indent=2))


if __name__ == "__main__":
    main()
