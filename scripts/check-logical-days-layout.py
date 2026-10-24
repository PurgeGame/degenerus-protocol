#!/usr/bin/env python3
"""Pin logical session clocks, Coinflip mirror, and the three-word quest namespace."""
import json
from pathlib import Path
import sys

out = Path(sys.argv[1])

def layout(source, name):
    return json.loads((out / f"{source}.sol" / f"{name}.json").read_text())["storageLayout"]

def check_fields(data, expected):
    fields = {row["label"]: (int(row["slot"]), row["offset"], data["types"][row["type"]]["label"])
              for row in data["storage"]}
    for name, position in expected.items():
        assert fields[name] == position, (name, fields[name], position)
    return fields

game = check_fields(layout("DegenerusGame", "DegenerusGame"), {
    "dailyIdx": (0, 3, "uint24"),
    "gameOver": (0, 21, "bool"),
    "rngFlagsAndNudges": (0, 30, "uint16"),
    "dailyComplete": (5, 3, "bool"),
    "lastDailyRequestWallDay": (5, 27, "uint24"),
    "lastDailyCompletedAt": (13, 16, "uint48"),
    "degenesisOpenedAt": (13, 22, "uint48"),
})
assert "rngGapApplied" not in game
assert "terminalCrapsWords" not in game
check_fields(layout("Coinflip", "Coinflip"), {
    "requestedDailyIdx": (4, 22, "uint24"),
})
quest = layout("XaLayout", "XaQuestsLayout")
record = quest["types"][quest["storage"][0]["type"]]
assert int(record["numberOfBytes"]) == 96
assert [(r["label"], int(r["slot"]), r["offset"]) for r in record["members"]] == [
    ("activeQuestsPacked", 0, 0), ("questPlayerState", 1, 0), ("levelQuestPlayerState", 2, 0)
]
print("PASS logical clocks packed in existing words; Coinflip mirror packed; quests use exactly three namespace roots")
