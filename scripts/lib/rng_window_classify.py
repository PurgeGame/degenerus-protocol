#!/usr/bin/env python3
"""Generate the initial RNG-window manifest from the live access set.

Reads rng_window_extract.py output on stdin and emits a classified manifest to
stdout. Classification is by enclosing function (the semantic role of the site)
plus access mode. This is a ONE-TIME bootstrap: the emitted manifest is then
checked in and hand-reviewed; check-rng-window.sh diffs live source against the
checked-in file thereafter. Re-running this generator is only for re-bootstrap
after a large refactor (a reviewer must re-confirm every row).

Class meanings (see scripts/rng-window-manifest.tsv header):
  DECL            storage declaration of the word/cursor variable
  PRODUCER        writes a word/cursor (runs in the exempt advance/callback path)
  EXEMPT-ADVANCE  read inside advanceGame / the VRF request-response / seal /
                  gap-backfill flow — v45-exempt heartbeat (no player interleave)
  CONSUMER-SEALED player-reachable read that consumes a SEALED, write-once word
                  for a value decision (safe by write-once + post-unlock read)
  GATE            player-reachable readiness/existence check (!= 0), no value use
  CURSOR          player-reachable read of the lootboxRngPacked cursor (the
                  non-VRF read-alongside-the-word class the freeze net enumerates)
  ACCESSOR        pure view getter / packed-field helper
"""
import sys

EXEMPT_ADVANCE = {
    "advanceGame", "rngGate", "_applyDailyRng", "_finalizeRngRequest",
    "_finalizeLootboxRng", "_backfillGapDays", "_backfillOrphanedLootboxIndices",
    "_gameOverEntropy", "_handleGameOverPath", "_getHistoricalRngFallback",
    "requestLootboxRng", "updateVrfCoordinatorAndSub", "rawFulfillRandomWords",
    "_lrAdvanceIndexClearPending", "handleGameOverDrain",
}
CONSUMER_SEALED = {
    "_tryClaimFoilMatch", "_payFoilTier", "_processFoilDrain", "_resolveBet",
    "_openBoxBoth", "openHumanBoxes", "_openLootBoxLeg", "issueDeityBoon",
    "processTicketBatch", "_farFutureSeed", "_autoOpen", "deityBoonData",
}
GATE = {"_placeDegeneretteBetCore", "_buyPresaleBoxFor", "boxesPending", "_foilDrainPending"}
CURSOR = {"_recordLootboxEntry", "_recordAfkingCoverBox", "_purchaseForWithCached"}
ACCESSOR = {"rngWordForDay", "isRngFulfilled", "_lrRead", "_lrAdd", "_lrWrite"}


def classify(fn, ident, mode):
    if mode == "DECL":
        return "DECL"
    if fn in ACCESSOR:
        return "ACCESSOR"
    if mode == "WRITE":
        return "PRODUCER"
    if fn in EXEMPT_ADVANCE:
        return "EXEMPT-ADVANCE"
    if fn in CONSUMER_SEALED:
        return "CONSUMER-SEALED"
    if fn in GATE:
        return "GATE"
    if fn in CURSOR:
        return "CURSOR"
    return "UNCLASSIFIED"


seen = set()
rows = []
for line in sys.stdin:
    parts = line.rstrip("\n").split("\t")
    if len(parts) < 6:
        continue
    relpath, fn, ident, mode, lineno, code = parts[:6]
    cls = classify(fn, ident, mode)
    key = (relpath, fn, ident, mode)
    if key in seen:
        continue
    seen.add(key)
    rows.append((cls, ident, fn, relpath, mode))

# Order: class, identifier, file, function for a readable, stable manifest.
CLASS_ORDER = {
    "DECL": 0, "PRODUCER": 1, "EXEMPT-ADVANCE": 2, "CONSUMER-SEALED": 3,
    "GATE": 4, "CURSOR": 5, "ACCESSOR": 6, "UNCLASSIFIED": 9,
}
rows.sort(key=lambda r: (CLASS_ORDER.get(r[0], 9), r[1], r[3], r[2]))
for cls, ident, fn, relpath, mode in rows:
    sys.stdout.write("\t".join([cls, ident, fn, relpath, mode]) + "\n")
