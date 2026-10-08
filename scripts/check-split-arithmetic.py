#!/usr/bin/env python3
"""Exact integer split proofs with explicit EVM overflow bounds.

These are arithmetic models, not bytecode proofs. A source fingerprint fails closed
when the modeled bucket routine or Solidity carrier changes. Foundry also executes
the production bucket routine and the generic four-way model with bounded fuzzing.
Requires z3-solver (installed by the pinned Halmos environment).
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import z3

ROOT = Path(__file__).resolve().parents[1]
MAX_UINT256 = 2**256 - 1
BPS = 10_000
MAX_POOL = 10**30
# Any change requires reviewing both the integer model and Solidity carrier.
SOURCE_PINS = {
    "contracts/libraries/JackpotBucketLib.sol": "12e4725bec303028593b65962a601f310949bcf5bbf90e603fd44f848dd23834",
    "test/halmos/NewProperties.t.sol": "57186404679df87a4ec4b300fa05dd4d05beb06d50baf9b6c37187b12c66c7f0",
    "test/halmos/SolvencyArithmetic.t.sol": "735b5b3ff055ceca6f1266dbe597d44b6cda489d3e68e63ce68437301b4f3b61",
}


def check(name, constraints, violation=None, expected=z3.unsat):
    solver = z3.Solver()
    solver.set(timeout=30_000)
    solver.add(*constraints)
    if violation is not None:
        solver.add(violation)
    status = solver.check()
    row = {"name": name, "expected": str(expected), "result": str(status)}
    if status != expected:
        row["detail"] = (solver.reason_unknown() if status == z3.unknown
                         else str(solver.model()) if status == z3.sat
                         else "No witness: the sensitivity/non-vacuity check is unsatisfiable")
        raise AssertionError(json.dumps(row))
    return row


def proofs():
    rows = []
    pool = z3.Int("pool")
    bps = z3.Ints("b0 b1 b2 b3")
    products = [pool * b for b in bps]
    shares = [p / BPS for p in products]  # Z3 integer division; operands are nonnegative.
    domain = [pool >= 0, pool <= MAX_POOL, *[b >= 0 for b in bps], sum(bps) <= BPS]
    rows.append(check("domain-is-nonempty", domain, expected=z3.sat))
    # Pin non-vacuity at meaningful boundary states as well as zero.
    rows.append(check("full-pool-and-full-bps-admitted", domain + [pool == MAX_POOL, bps[0] == BPS], expected=z3.sat))
    rows.append(check("checked-products-fit-uint256", domain, z3.Or(*[p < 0 for p in products], *[p > MAX_UINT256 for p in products])))
    rows.append(check("floored-shares-fit-and-are-bounded", domain, z3.Or(*[q < 0 for q in shares], *[q > pool for q in shares])))
    rows.append(check("four-floors-never-overpay", domain, sum(shares) > pool))
    rows.append(check("checked-partial-sums-fit", domain, z3.Or(sum(shares) > MAX_UINT256, sum(products) > MAX_UINT256)))

    # Generic three floored legs plus an exact remainder. The fourth BPS variable
    # can be zero, so the projection is exactly the original three-BPS domain.
    reward = pool - sum(shares[:3])
    rows.append(check("four-way-remainder-cannot-underflow", domain, reward < 0))
    rows.append(check("four-way-exact-conservation", domain, sum(shares[:3]) + reward != pool))
    rows.append(check("four-way-remainder-bounded", domain, reward > pool))

    # Model the actual library's four iterations. Empty ordinary buckets still
    # contribute to distributed; their omitted payout stays available for refund.
    counts = z3.Ints("c0 c1 c2 c3")
    bucket_domain = domain + [c >= 0 for c in counts] + [c <= 65535 for c in counts]
    for remainder in range(4):
        ordinary = [i for i in range(4) if i != remainder]
        distributed = sum(shares[i] for i in ordinary)
        paid = [pool - distributed if i == remainder else z3.If(counts[i] != 0, shares[i], 0) for i in range(4)]
        omitted = sum(z3.If(counts[i] == 0, shares[i], 0) for i in ordinary)
        rows.append(check(f"bucket-{remainder}-checked-arithmetic-safe", bucket_domain,
                          z3.Or(distributed < 0, distributed > pool, sum(paid) > MAX_UINT256)))
        rows.append(check(f"bucket-{remainder}-never-overpays", bucket_domain, sum(paid) > pool))
        rows.append(check(f"bucket-{remainder}-refund-conserves-pool", bucket_domain, sum(paid) + omitted != pool))

    # Sensitivity controls: deliberately wrong formulas must have counterexamples.
    rows.append(check("detect-ceiling-instead-of-floor", domain,
                      sum((p + BPS - 1) / BPS for p in products) > pool, z3.sat))
    rows.append(check("detect-extra-remainder-wei", domain,
                      sum(shares[:3]) + reward + 1 > pool, z3.sat))
    rows.append(check("detect-missing-bps-cap", [pool >= 1, pool <= MAX_POOL, bps[0] > BPS, bps[0] <= 65535],
                      products[0] / BPS > pool, z3.sat))
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json-output", type=Path)
    args = parser.parse_args()
    pins = {}
    for file, expected in SOURCE_PINS.items():
        actual = hashlib.sha256((ROOT / file).read_bytes()).hexdigest()
        if actual != expected:
            raise AssertionError(f"Source drift in {file}: review the arithmetic model before updating its pin")
        pins[file] = actual
    rows = proofs()
    result = {"z3_version": z3.get_version_string(), "source_pins": pins, "checks": rows,
              "scope": "Exact nonnegative integer models over pool <= 1e30, total BPS <= 10000; checked uint256 bounds proven separately. Not bytecode equivalence."}
    if args.json_output:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(json.dumps(result, indent=2) + "\n")
    print(f"Split arithmetic: {len(rows)} checks passed (proofs, non-vacuity and sensitivity controls)")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (AssertionError, ValueError, OSError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
