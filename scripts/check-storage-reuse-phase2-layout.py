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
    ("day", 4, 29, "uint24"),
]
for name in ("CrapsBattle", "JackpotBattle"):
    data = layout(name)
    types = data["types"]
    root = next(x for x in data["storage"] if x["label"] == "_jackpotRounds")
    record = types[types[root["type"]].get("base", types[root["type"]].get("value"))]
    actual = [(m["label"], int(m["slot"]), m["offset"], types[m["type"]]["label"])
              for m in record["members"]]
    assert actual == expected, (name, actual)
    assert int(record["numberOfBytes"]) == 160, name
    assert int(root["slot"]) == 271, (name, root)
    roots = {x["label"]: (int(x["slot"]), x["offset"]) for x in data["storage"]}
    expected_roots = {'_bets': (0, 0), '_customBattleCount': (1, 0), '_battles': (2, 0), '_bonusSeated': (3, 0), '_bonus': (4, 0), '_slotState': (5, 0), '_battleCreator': (6, 0), '_highField': (7, 0), '_customBattle': (8, 0), '_passCreditsById': (9, 0), '_progressive': (10, 0), '_minerSlot': (11, 0), '_activeJackpotSlot': (11, 8), '_firstWindowDay': (11, 16), '_highRollerReserve': (12, 0), '_rngSlotCursor': (13, 0), '_fundedCustomSlots': (14, 0), '_dayTickets': (15, 0), '_dayStaked': (79, 0), '_boostBudget': (143, 0), '_battleDays': (207, 0), '_jackpotRounds': (271, 0), '_rngSlots': (2831, 0), '_daySeated': (2833, 0)}
    assert roots == expected_roots, (name, roots)

sd = layout("sDGNRS")
fields = {x["label"]: (int(x["slot"]), x["offset"], sd["types"][x["type"]]["label"])
          for x in sd["storage"]}
assert fields["_batchPlayerCounts"] == (6, 24, 'uint64')
assert fields["_batchPlayers"] == (8, 0, 'mapping(uint256 => uint256)[2]')
assert fields["_redemptionBatches"][0] == 10
assert "_parkedRedemptions" not in fields
root = next(x for x in sd["storage"] if x["label"] == "_redemptionBatches")
record = sd["types"][sd["types"][root["type"]].get("base", sd["types"][root["type"]].get("value"))]
assert int(record["numberOfBytes"]) == 64
assert [(m["label"], int(m["slot"]), m["offset"]) for m in record["members"]][-1] == ("id", 1, 28)
print("Phase 2 layout: tagged five-word jackpot records, packed queue counts, pinned Craps roots, pinned sDGNRS roots")

# Private peripheral fields and the full direct-array extent used by raw fixtures.
import re
pin_source = Path("test/helpers/PeripheralSlots.sol").read_text()
pins = {k: int(v) for k,v in re.findall(r"constant (\w+) = (\d+);", pin_source)}
if "constant AFF_LEVEL_SCORE = QaSlots.SCORE;" in pin_source:
    pins["AFF_LEVEL_SCORE"] = int(json.loads(Path("scripts/consolidation/xa-namespaces.json").read_text())["affiliate"]["root"],16) + 3
expected_pins = {'SD_BATCHES': {'contract': 'sDGNRS', 'label': '_redemptionBatches', 'field': 'slot', 'expected': 10}, 'SD_BATCH_PLAYERS': {'contract': 'sDGNRS', 'label': '_batchPlayers', 'field': 'slot', 'expected': 8}, 'SD_BATCH_COUNTS': {'contract': 'sDGNRS', 'label': '_batchPlayerCounts', 'field': 'slot', 'expected': 6}, 'AFF_LEVEL_SCORE': {'contract': 'DegenerusAffiliate', 'label': '_levelScore', 'field': 'slot', 'expected': 3}, 'CR_DAY_TICKETS': {'contract': 'CrapsBattle', 'label': '_dayTickets', 'field': 'slot', 'expected': 15}, 'CR_DAY_STAKED': {'contract': 'CrapsBattle', 'label': '_dayStaked', 'field': 'slot', 'expected': 79}, 'CR_BOOST_BUDGET': {'contract': 'CrapsBattle', 'label': '_boostBudget', 'field': 'slot', 'expected': 143}, 'CR_DAY_SEATED': {'contract': 'CrapsBattle', 'label': '_daySeated', 'field': 'slot', 'expected': 2833}, 'GNR_APPROVE_WEIGHT': {'contract': 'GNRUS', 'label': '_slotApproveWeight', 'field': 'slot', 'expected': 45}, 'WW_DRAW_HEADER': {'contract': 'WWXRP', 'label': '_drawHeader', 'field': 'slot', 'expected': 9}, 'WW_DRAW_ENTRY': {'contract': 'WWXRP', 'label': '_drawEntry', 'field': 'slot', 'expected': 3}, 'WW_INCIN_HEADER': {'contract': 'WWXRP', 'label': '_incinHeader', 'field': 'slot', 'expected': 39}, 'WW_INCIN_ENTRY': {'contract': 'WWXRP', 'label': '_incinEntry', 'field': 'slot', 'expected': 5}, 'WW_DAY_CLAIMED': {'contract': 'WWXRP', 'label': '_dayClaimed', 'field': 'slot', 'expected': 4}, 'WW_CLAIMABLE': {'contract': 'WWXRP', 'label': '_claimable', 'field': 'slot', 'expected': 8}, 'JP_BAF_TOP': {'contract': 'DegenerusJackpots', 'label': 'bafTop', 'field': 'slot', 'expected': 3}, 'JP_BAF_LEVEL': {'contract': 'DegenerusJackpots', 'label': 'bafLevel', 'field': 'slot', 'expected': 1}, 'JP_BAF_BANK_LEVELS': {'contract': 'DegenerusJackpots', 'label': 'bafTopLevels', 'field': 'slot', 'expected': 2}, 'CENSUS_DIRECT_END': {'contracts': ['DegenerusGame', 'CrapsBattle', 'JackpotBattle', 'sDGNRS', 'DegenerusAffiliate', 'DegenerusJackpots', 'GNRUS', 'WWXRP'], 'field': 'max_storage_end', 'expected': 2849}}
assert set(pins) == set(expected_pins), (set(pins), set(expected_pins))
for constant, specification in expected_pins.items():
    if specification["field"] == "max_storage_end":
        value = 0
        for name in specification["contracts"]:
            data = layout(name)
            for row in data["storage"]:
                value = max(value, int(row["slot"]) + (int(data["types"][row["type"]]["numberOfBytes"]) + 31) // 32)
    else:
        data = layout(specification["contract"])
        if specification["contract"] == "DegenerusAffiliate" and not data["storage"]:
            probe = json.loads((out / "XaLayout.sol" / "XaAffiliateLayout.json").read_text())["storageLayout"]
            record = probe["types"][probe["storage"][0]["type"]]
            row = next(r for r in record["members"] if r["label"] == specification["label"])
            root = int(json.loads(Path("scripts/consolidation/xa-namespaces.json").read_text())["affiliate"]["root"], 16)
            value = root + int(row["slot"])
            specification = dict(specification, expected=root + specification["expected"])
        else:
            row = next(r for r in data["storage"] if r["label"] == specification["label"])
            value = int(row[specification["field"]])
    assert pins[constant] == value == specification["expected"], (constant, pins[constant], value, specification)
    print("Compiler pin:", constant, value)
