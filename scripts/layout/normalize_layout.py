#!/usr/bin/env python3
"""Canonicalize `forge inspect <C> storageLayout --json` into an astId-free,
diff-stable representation.

forge's raw output carries `astId`s (and astId-bearing struct/contract type ids)
that shift on unrelated source edits or recompiles. Comparing those produces false
"layout changed" noise. This emits only the layout-meaningful fields — a
slot/offset-sorted list of {slot, offset, label, typeLabel, bytes, encoding} — so a
diff signals a REAL storage move (slot/offset/type/size change), which under 155
delegatecall sites is a whole-protocol corruption risk.
"""
import sys, json

d = json.load(sys.stdin)
storage = d.get("storage", []) or []
types = d.get("types", {}) or {}

out = []
for e in storage:
    t = e.get("type")
    ti = types.get(t, {}) if isinstance(types, dict) else {}
    out.append({
        "slot": int(e.get("slot", 0)),
        "offset": int(e.get("offset", 0)),
        "label": e.get("label"),
        "typeLabel": ti.get("label"),      # astId-free human type, e.g. "uint24", "mapping(address => uint256)"
        "bytes": ti.get("numberOfBytes"),
        "encoding": ti.get("encoding"),
    })

out.sort(key=lambda x: (x["slot"], x["offset"], x["label"] or ""))
print(json.dumps(out, indent=2, sort_keys=True))
