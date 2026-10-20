#!/usr/bin/env python3
"""Check the Phase 2 nested layouts that the root-slot golden cannot describe."""
import json
from pathlib import Path
import sys

out = Path(sys.argv[1] if len(sys.argv) > 1 else "forge-out-production")

def layout(name):
    return json.loads((out / f"{name}.sol" / f"{name}.json").read_text())["storageLayout"]

expected = [
    ("drawWord", 0, 0, "uint256"),
    ("added", 1, 0, "uint128"), ("totalPool", 1, 16, "uint128"),
    ("potRemainder", 2, 0, "uint128"), ("paidUnits", 2, 16, "uint64"),
    ("bankroll", 2, 24, "uint32"), ("bountyUnits", 2, 28, "uint32"),
    ("drawCursor", 3, 0, "uint208"), ("level", 3, 26, "uint24"),
    ("requestDay", 3, 29, "uint24"),
    ("multiplierBps", 4, 0, "uint32"), ("paidCount", 4, 4, "uint32"),
    ("drawnCount", 4, 8, "uint32"), ("drawnUnits", 4, 12, "uint32"),
    ("awardTarget", 4, 16, "uint32"), ("entryPrice", 4, 20, "uint32"),
    ("subsidyMultiplierBps", 4, 24, "uint32"), ("started", 4, 28, "bool"),
]
for name in ("CrapsBattle", "JackpotBattle"):
    data = layout(name)
    types = data["types"]
    root = next(x for x in data["storage"] if x["label"] == "_jackpotRounds")
    record = types[types[root["type"]]["value"]]
    actual = [(m["label"], int(m["slot"]), m["offset"], types[m["type"]]["label"])
              for m in record["members"]]
    assert actual == expected, (name, actual)
    assert int(record["numberOfBytes"]) == 160, name
    assert int(root["slot"]) == 17, (name, root)

sd = layout("sDGNRS")
fields = {x["label"]: (int(x["slot"]), x["offset"], sd["types"][x["type"]]["label"])
          for x in sd["storage"]}
assert fields["_batchPlayerCounts"] == (7, 24, "uint64")
assert fields["_batchPlayers"] == (9, 0, "mapping(uint256 => uint256)[2]")
assert fields["_redemptionBatches"][0] == 6
assert "_parkedRedemptions" not in fields
root = next(x for x in sd["storage"] if x["label"] == "_redemptionBatches")
record = sd["types"][sd["types"][root["type"]]["value"]]
assert int(record["numberOfBytes"]) == 64
assert [(m["label"], int(m["slot"]), m["offset"]) for m in record["members"]][-1] == ("id", 1, 28)
print("Phase 2 layout: five-word jackpot records, packed queue counts, unchanged mapping roots")
