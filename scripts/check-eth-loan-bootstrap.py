#!/usr/bin/env python3
"""Finite model of immediate borrowing against a newly bought whale-pass award.

This is NOT a model of the pass's bundled rewards or lifetime economic return.
It grants the strongest discount for free and ignores lender/eligibility limits,
so the modeled principal is an upper bound for this isolated ticket strategy.
Production helper parity is tested separately in EthLoanBootstrap.t.sol.
"""
import argparse
from fractions import Fraction
import hashlib
import json
from pathlib import Path

ETHER = 10**18
SOURCES = (
    "contracts/storage/DegenerusGameStorage.sol",
    "contracts/modules/DegenerusGameMintStreakUtils.sol",
    "contracts/modules/DegenerusGameWhaleModule.sol",
    "contracts/libraries/PriceLookupLib.sol",
)
# Current model inputs. The archived proof manifest retains its historical identity.
# Reviewed 2026-10-29: loan credit retains custody and LOAN_LATE_WINDOW only restricts
# eligibility; collateral rates, ticket awards and this principal upper bound are unchanged.
SOURCE_SHA256 = {
    "contracts/storage/DegenerusGameStorage.sol": "57315ff0defd830bea48dacc399ad0b4be339e3ffc687dcc20f8dac85cc54f5e",
    "contracts/modules/DegenerusGameMintStreakUtils.sol": "d6abac94f9dada75f272d6eeb16788f221cca61925ca90bceb334e1754ac9dd7",
    "contracts/modules/DegenerusGameWhaleModule.sol": "ed9180948aad0982a8991f88ed6ad5d854862ed96b4204a68c895b44a020f125",
    "contracts/libraries/PriceLookupLib.sol": "cbec28472ed02519f3bce1e3ffc809eb9a4cab87311c37a016dc7390c92d9a46",
}


def price(level):
    if level < 5:
        return ETHER // 100
    if level < 10:
        return ETHER // 50
    r = level % 100
    cents = 24 if r == 0 else 4 if r < 30 else 8 if r < 60 else 12 if r < 90 else 16
    return ETHER * cents // 100


def rate(distance):
    assert 2 <= distance <= 100
    if distance <= 20:
        return 1000 - (distance - 2) * 500 // 18
    return 500 - (distance - 20) * 300 // 80


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--pins", type=Path)
    parser.add_argument("--json-output", type=Path)
    args = parser.parse_args()
    pins = json.loads(args.pins.read_text()) if args.pins else SOURCE_SHA256
    for name in SOURCES:
        actual = hashlib.sha256((args.root / name).read_bytes()).hexdigest()
        if pins.get(name) != actual:
            raise SystemExit(f"Source changed; review model before updating pins: {name}")

    best = Fraction(0)
    witness = None
    cases = 0
    # Starts 1..9 cover the intro. Starts 10..109 cover each repeating price
    # position once. A later due level only removes nonnegative collateral.
    # At the uint24 boundary an ordinary 100-level purchase reverts; excluding
    # truncated collateral could only reduce this upper bound.
    for start in range(1, 110):
        bonus = max(0, 10 - start)
        for active in (start, start - 1):
            early = base = odd = 0
            for target in range(start + 2, start + 100):
                value = price(target) * rate(target - active)
                # Makes the aggregate quantity decomposition exact despite floors.
                assert value % 10_000 == 0
                unit = value // 10_000
                if target < 10:
                    early += 5 * unit
                else:
                    base += unit
                    if (target - start - bonus) % 2 == 0:
                        odd += unit
            for quantity in range(1, 1001):
                award = quantity + quantity // 5
                principal = award * early + (award // 2) * base + (award % 2) * odd
                unit_cost = 24 * ETHER // 10 if start <= 4 else 4 * ETHER
                cost = unit_cost * (100 * quantity - 35) // 100
                ratio = Fraction(principal, cost)
                cases += 1
                assert principal < cost
                if ratio > best:
                    best = ratio
                    witness = dict(pass_level=start, active_level=active, quantity=quantity,
                                   awarded_quantity=award, principal_wei=principal, cost_wei=cost)
    assert cases == 218_000
    assert best == Fraction(8207, 62400)
    result = dict(status="PASS", cases=cases, max_ratio=str(best),
                  max_percent=float(best * 100), witness=witness,
                  scope="new whale-pass ticket award; immediate borrow; excludes bundled rewards and later outcomes",
                  source_hashes={name: pins[name] for name in SOURCES})
    output = json.dumps(result, indent=2) + "\n"
    if args.json_output:
        args.json_output.write_text(output)
    print(output, end="")


if __name__ == "__main__":
    main()
