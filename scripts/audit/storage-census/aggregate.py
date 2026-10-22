#!/usr/bin/env python3
"""Aggregate storage-census logs into ranked per-root creation tables.

Input: forge `-vv` logs written by scripts/audit/storage-census/run.py (the focused runner's log
directory). Every census transaction logs CENSUS lines (one per created or cleared slot), a
CENSUSTX summary, and every scenario a CENSUSMETA line (see test/census/StorageCensus.sol).

Labels come from the compiled `storageLayout` in forge-out/ artifacts (Foundry's extra_output),
falling back to scripts/layout/golden/*.json (root names only).

Counting rules (.planning/STORAGE-REUSE-PHASE2.md §1): the census already collapses each
transaction to its start and end value, so a clear and rewrite in one transaction never appears.
A "re-creation" is a CREATE of a slot that an earlier, different transaction of the same
scenario CLEARED.

Usage:
  python3 scripts/audit/storage-census/aggregate.py [LOG ...] [--log-dir DIR] [--out FILE.md]
          [--json FILE.json] [--forge-out forge-out]
With no LOG arguments, every *.log under the newest run of each census suite in --log-dir
(default .audit-test-logs/storage-census) is read; a scenario logged by several runs keeps the
newest run's lines.
"""

import argparse
from collections import defaultdict, OrderedDict
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[3]

ACCOUNT_ARTIFACT = {
    "Game": "DegenerusGame", "Coinflip": "Coinflip", "FLIP": "FLIP", "sDGNRS": "sDGNRS", "DGNRS": "DGNRS",
    "CRAPS": "CrapsBattle", "JackpotBattle": "JackpotBattle", "CrapsEngine": "CrapsEngine", "WWXRP": "WWXRP",
    "GNRUS": "GNRUS", "Affiliate": "DegenerusAffiliate", "Jackpots": "DegenerusJackpots",
    "Vault": "DegenerusVault", "Quests": "DegenerusQuests", "AFKingToken": "AFKingSubscriptionToken",
    "DeityPass": "DegenerusDeityPass", "Parimutuel": "DegenerusParimutuel", "RecordBounty": "DegenerusRecordBounty",
    "OwnerGovernance": "DegenerusOwnerGovernance", "Admin": "DegenerusAdmin", "Icons32": "Icons32Data",
    "MockStETH": "MockStETH", "MockVRF": "MockVRFCoordinator", "MockLINK": "MockLinkToken", "MockFeed": "MockLinkEthFeed",
}
GOLDEN_FALLBACK = {}
WORD = 32


# --------------------------------------------------------------------------------------------
# Storage layouts
# --------------------------------------------------------------------------------------------

class Layout:
    def __init__(self, storage, types):
        self.storage = storage
        self.types = types or {}
        self.by_slot = defaultdict(list)
        for var in storage:
            first = int(var["slot"])
            nbytes = int(self.types.get(var["type"], {}).get("numberOfBytes", var.get("bytes", 32)))
            span = max(1, (int(var.get("offset", 0)) + nbytes + WORD - 1) // WORD)
            for s in range(first, first + span):
                self.by_slot[s].append(var)

    def indirect_roots(self):
        """Physical mapping/array heads, including heads nested in fixed arrays."""
        roots = {"mapping": set(), "dynamic_array": set()}
        for slot, variables in self.by_slot.items():
            for var in variables:
                type_id, _ = self.descend_word(var["type"], slot - int(var["slot"]), var["label"])
                kind = self.types.get(type_id, {}).get("encoding")
                if kind in roots:
                    roots[kind].add(slot)
        return roots

    def type_of(self, var):
        return var.get("type")

    def slots_of(self, type_id):
        t = self.types.get(type_id, {})
        return max(1, (int(t.get("numberOfBytes", 32)) + WORD - 1) // WORD)

    def descend_word(self, type_id, word, label):
        """Descend `word` slots into an in-place type (struct / static array)."""
        t = self.types.get(type_id)
        if t is None:
            return type_id, label + (f"+{word}" if word else "")
        if t.get("members"):
            members = [m for m in t["members"] if int(m["slot"]) <= word]
            if not members:
                return type_id, label + f"+{word}"
            # Latest member starting at or before the word that still covers it.
            best = None
            for m in t["members"]:
                ms = int(m["slot"])
                if ms <= word < ms + self.slots_of(m["type"]):
                    best = m if best is None or int(m["offset"]) < int(best["offset"]) else best
            if best is None:
                return type_id, label + f"+{word}"
            names = [m["label"] for m in t["members"] if int(m["slot"]) == int(best["slot"])
                     and self.slots_of(m["type"]) == 1] if self.slots_of(best["type"]) == 1 else [best["label"]]
            lbl = label + "." + ("{" + ",".join(names) + "}" if len(names) > 1 else best["label"])
            return self.descend_word(best["type"], word - int(best["slot"]), lbl)
        if t.get("encoding") == "inplace" and t.get("base"):
            base = t["base"]
            per = self.slots_of(base)
            if int(self.types.get(base, {}).get("numberOfBytes", 32)) < WORD:
                return base, label + f"[w{word}]"
            return self.descend_word(base, word % per, label + f"[{word // per}]")
        return type_id, label + (f"+{word}" if word else "")

    def resolve(self, root_slot, hops):
        """Return (root label, full label, ok)."""
        vars_ = self.by_slot.get(root_slot)
        if not vars_:
            return f"slot{root_slot}", f"slot{root_slot}", False
        if len(vars_) > 1 and all(self.slots_of(v["type"]) == 1 for v in vars_):
            root_label = "{" + ",".join(v["label"] for v in vars_) + "}"
            type_id = vars_[0]["type"] if len(vars_) == 1 else None
        else:
            var = vars_[0]
            root_label = var["label"]
            type_id = var["type"]
            word = root_slot - int(var["slot"])
            t0 = self.types.get(type_id, {})
            if word or t0.get("members") or (t0.get("encoding") == "inplace" and t0.get("base")):
                type_id, label = self.descend_word(type_id, word, root_label)
            else:
                label = root_label
        if len(vars_) > 1 and all(self.slots_of(v["type"]) == 1 for v in vars_):
            label = root_label
        ok = True
        for hop in hops:
            kind, n = hop[0], int(hop[1:])
            t = self.types.get(type_id, {}) if type_id else {}
            if kind == "M" and t.get("encoding") == "mapping":
                type_id, label = self.descend_word(t["value"], n, label + "[]")
            elif kind == "A" and t.get("encoding") == "dynamic_array":
                base = t["base"]
                if int(self.types.get(base, {}).get("numberOfBytes", 32)) < WORD:
                    type_id, label = base, label + "[]"
                else:
                    per = self.slots_of(base)
                    type_id, label = self.descend_word(base, n % per, label + "[]")
            elif kind == "A" and t.get("encoding") == "inplace" and not t.get("members"):
                # A word used as a hand-rolled list header: entries at keccak(header slot) + i.
                type_id, label = None, label + "{tail}"
            else:
                label += f"<{hop}?>"
                ok = False
                type_id = None
        return root_label, label, ok


def _canonical(param):
    t = param["type"]
    if t.startswith("tuple"):
        return "(" + ",".join(_canonical(c) for c in param.get("components", [])) + ")" + t[5:]
    return t


def error_names(forge_out):
    """Selector -> custom error name from every artifact ABI (needs pycryptodome; else empty)."""
    try:
        from Crypto.Hash import keccak
    except ImportError:
        return {}
    names = {"0x4e487b71": "Panic(uint256)", "0x08c379a0": "Error(string)"}
    for path in Path(forge_out).glob("*.sol/*.json"):
        try:
            abi = json.loads(path.read_text()).get("abi", [])
        except (OSError, ValueError):
            continue
        for item in abi:
            if item.get("type") != "error":
                continue
            sig = f"{item['name']}({','.join(_canonical(i) for i in item.get('inputs', []))})"
            sel = "0x" + keccak.new(digest_bits=256, data=sig.encode()).hexdigest()[:8]
            names.setdefault(sel, sig)
    return names


def _keccak(data):
    from Crypto.Hash import keccak
    return int(keccak.new(digest_bits=256, data=data).hexdigest(), 16)


_ARRAY_IN_MAPPING_CACHE = {}
SECOND_CHANCE = {}  # (account, root slot) -> events the in-test walk left unattributed, resolved here


def resolve_unattributed(layout, slot, max_key=1024, span=1 << 20):
    """Second-chance attribution for a slot the census could not walk: a manually addressed
    list stored at keccak(keccak(key . root)) + i, i.e. `mapping(K => T[])` whose length word
    the transaction never touched (e.g. Game `foilQueue`). Brute-forces keys 0..max_key-1 of
    every physical mapping root, including fixed-array leaves. Direct dynamic-array
    heads are also searched. Returns (root slot, key, index, kind) or None. Needs pycryptodome."""
    try:
        import Crypto  # noqa: F401
    except ImportError:
        return None
    s = int(slot, 16)
    cache = _ARRAY_IN_MAPPING_CACHE.setdefault(layout, {"list": [], "elem": [], "built": False})
    if not cache["built"]:
        roots = layout.indirect_roots()
        for r in sorted(roots["dynamic_array"]):
            cache["list"].append((_keccak(r.to_bytes(32, "big")), r, 0, "D"))
        for r in sorted(roots["mapping"]):
            for k in range(max_key):
                inner = _keccak(k.to_bytes(32, "big") + r.to_bytes(32, "big"))
                cache["elem"].append((inner, r, k))
                cache["list"].append((_keccak(inner.to_bytes(32, "big")), r, k, "A"))
        cache["list"].sort()
        cache["elem"].sort()
        cache["built"] = True
    import bisect
    # A wide mapping value (e.g. uint256[256]) word far from any member the tx touched.
    i = bisect.bisect_right(cache["elem"], (s, 1 << 256, 0)) - 1
    if i >= 0 and s - cache["elem"][i][0] < 4096:
        return cache["elem"][i][1], cache["elem"][i][2], s - cache["elem"][i][0], "M"
    i = bisect.bisect_right(cache["list"], (s, 1 << 256, 0, "")) - 1
    if i >= 0 and s - cache["list"][i][0] < span:
        return cache["list"][i][1], cache["list"][i][2], s - cache["list"][i][0], cache["list"][i][3]
    return None


def load_layouts(forge_out):
    layouts = {}
    for account, artifact in ACCOUNT_ARTIFACT.items():
        found = None
        for path in sorted(Path(forge_out).glob(f"**/{artifact}.json")):
            try:
                data = json.loads(path.read_text())
            except (OSError, ValueError):
                continue
            sl = data.get("storageLayout")
            if sl and sl.get("storage") is not None:
                found = Layout(sl["storage"], sl.get("types"))
                break
        if found is None:
            golden = ROOT / "scripts/layout/golden" / f"{GOLDEN_FALLBACK.get(artifact, artifact)}.json"
            if golden.exists():
                rows = json.loads(golden.read_text())
                found = Layout([{**r, "type": r.get("typeLabel")} for r in rows], {})
        if found is not None:
            layouts[account] = found
    return layouts


# --------------------------------------------------------------------------------------------
# Logs
# --------------------------------------------------------------------------------------------

LINE = re.compile(r"(CENSUS(?:TX|META|REV|NOTE)?\|[^\s]*)")


def find_logs(log_dir):
    """Newest run first, so the first scenario occurrence kept is the newest."""
    runs = sorted((p for p in Path(log_dir).iterdir() if p.is_dir()), reverse=True)
    for run in runs:
        yield from sorted(run.glob("*.log"))


def parse(paths):
    scenarios = OrderedDict()  # name -> {"meta": [...], "events": [...], "txs": [...]}
    seen_in = {}
    for path in paths:
        local = defaultdict(lambda: {"meta": None, "events": [], "txs": [], "revs": [], "notes": []})
        for raw in Path(path).read_text(errors="replace").splitlines():
            m = LINE.search(raw)
            if not m:
                continue
            f = m.group(1).split("|")
            if f[0] == "CENSUS" and len(f) == 13:
                local[f[1]]["events"].append({
                    "label": f[2], "seq": int(f[3]), "payer": f[4], "account": f[5], "address": f[6],
                    "slot": f[7], "root": f[8], "path": f[9], "kind": f[10], "day": int(f[11]), "level": int(f[12]),
                })
            elif f[0] == "CENSUSTX" and len(f) == 12:
                local[f[1]]["txs"].append({
                    "label": f[2], "seq": int(f[3]), "payer": f[4], "ok": f[5] == "ok", "creates": int(f[6]),
                    "clears": int(f[7]), "overwrites": int(f[8]), "unattributed": int(f[9]),
                    "day": int(f[10]), "level": int(f[11]),
                })
            elif f[0] == "CENSUSREV" and len(f) == 6:
                local[f[1]]["revs"].append({"label": f[2], "seq": int(f[3]), "selector": f[4], "len": int(f[5])})
            elif f[0] == "CENSUSNOTE":
                local[f[1]]["notes"].append("|".join(f[2:]))
            elif f[0] == "CENSUSMETA" and len(f) == 10:
                local[f[1]]["meta"] = dict(zip(
                    ("startDay", "endDay", "startLevel", "endLevel", "txs", "creates", "clears", "overwrites"),
                    map(int, f[2:])))
        for name, data in local.items():
            if name in scenarios:
                continue  # an older run of the same scenario
            scenarios[name] = data
            seen_in[name] = str(path)
    return scenarios, seen_in


# --------------------------------------------------------------------------------------------
# Aggregation
# --------------------------------------------------------------------------------------------

def hops_of(path):
    if path in ("D", ""):
        return []
    return [h for h in path.split("/") if h and h not in ("U", "D")]


def aggregate(scenarios, layouts):
    rows = {}  # (account, root label) -> stats
    detail = defaultdict(lambda: defaultdict(int))  # (account, root label) -> full label -> creates
    unattributed = defaultdict(lambda: {"creates": 0, "clears": 0, "samples": set(), "scenarios": set()})
    per_scenario = {}
    for name, data in scenarios.items():
        meta = data["meta"] or {}
        days = max(1, meta.get("endDay", 0) - meta.get("startDay", 0)) if meta else 1
        levels = meta.get("endLevel", 0) - meta.get("startLevel", 0) if meta else 0
        per_scenario[name] = {"days": days, "levels": levels, "meta": meta,
                              "txs": len(data["txs"]), "failedTxs": sum(not t["ok"] for t in data["txs"])}
        labels = defaultdict(lambda: {"ok": 0, "reverted": 0, "creates": 0, "clears": 0, "payer": ""})
        for t in data["txs"]:
            lab = labels[t["label"]]
            lab["ok" if t["ok"] else "reverted"] += 1
            lab["creates"] += t["creates"]
            lab["clears"] += t["clears"]
            lab["payer"] = t["payer"]
        for r in data.get("revs", []):
            labels[r["label"]].setdefault("reasons", defaultdict(int))[r["selector"]] += 1
        per_scenario[name]["labels"] = dict(labels)
        per_scenario[name]["notes"] = data.get("notes", [])
        cleared = {}  # (address, slot) -> seq of last clear
        for e in sorted(data["events"], key=lambda e: e["seq"]):
            key = (e["address"], e["slot"])
            if "U" in e["path"].split("/") and e["account"] in layouts and e["path"] == "U":
                hit = resolve_unattributed(layouts[e["account"]], e["slot"])
                if hit:
                    SECOND_CHANCE[(e["account"], hit[0])] = SECOND_CHANCE.get((e["account"], hit[0]), 0) + 1
                    e["root"], e["path"] = str(hit[0]), (f"A{hit[2]}" if hit[3] == "D" else f"M0/A{hit[2]}" if hit[3] == "A" else f"M{hit[2]}")
            if "U" in e["path"].split("/"):
                u = unattributed[(e["account"], e["path"])]
                u["creates" if e["kind"] == "CREATE" else "clears"] += 1
                if len(u["samples"]) < 3:
                    u["samples"].add(e["slot"])
                u["scenarios"].add(name)
                root_label, full = f"unattributed({e['path']})", f"unattributed({e['path']})"
            elif e["account"] in layouts and e["root"].isdigit():
                root_label, full, _ = layouts[e["account"]].resolve(int(e["root"]), hops_of(e["path"]))
            else:
                root_label = full = f"slot{e['root']}"
            r = rows.setdefault((e["account"], root_label), {
                "creates": 0, "clears": 0, "recreates": 0, "protocol": 0, "player": 0,
                "byScenario": defaultdict(lambda: {"creates": 0, "clears": 0, "recreates": 0, "protocol": 0, "player": 0,
                                                  "byLevel": defaultdict(int), "byDay": defaultdict(int),
                                                  "labels": defaultdict(int), "txLabels": defaultdict(int)}),
                "labels": defaultdict(int), "txLabels": defaultdict(int)})
            s = r["byScenario"][name]
            if e["kind"] == "CREATE":
                r["creates"] += 1
                s["creates"] += 1
                r[e["payer"]] += 1
                s[e["payer"]] += 1
                s["byLevel"][e["level"]] += 1
                s["byDay"][e["day"]] += 1
                r["labels"][full] += 1
                r["txLabels"][e["label"]] += 1
                s["labels"][full] += 1
                s["txLabels"][e["label"]] += 1
                if key in cleared and cleared[key] < e["seq"]:
                    r["recreates"] += 1
                    s["recreates"] += 1
            else:
                r["clears"] += 1
                s["clears"] += 1
                cleared[key] = e["seq"]
    return rows, unattributed, per_scenario


def fmt_rate(n, d):
    return f"{n / d:.2f}" if d else "—"


def render(rows, unattributed, per_scenario, seen_in, errors=None):
    errors = errors or {}
    out = []
    out.append("## Scenarios\n")
    out.append("| Scenario | Days | Levels | Txs (failed) | Creates | Clears | Overwrites |")
    out.append("|---|---:|---:|---:|---:|---:|---:|")
    for name, s in per_scenario.items():
        m = s["meta"]
        out.append(f"| {name} | {s['days']} | {s['levels']} ({m.get('startLevel', '?')}→{m.get('endLevel', '?')}) | "
                   f"{s['txs']} ({s['failedTxs']}) | {m.get('creates', '?')} | {m.get('clears', '?')} | "
                   f"{m.get('overwrites', '?')} |")
    out.append("")
    out.append("## Transaction coverage (per scenario and label)\n")
    out.append("| Scenario | Tx label | Payer | OK | Reverted | Creates | Clears | Revert selectors |")
    out.append("|---|---|---|---:|---:|---:|---:|---|")
    for name, s in per_scenario.items():
        for label, v in sorted(s.get("labels", {}).items(), key=lambda kv: -(kv[1]["ok"] + kv[1]["reverted"])):
            reasons = ", ".join(f"{errors.get(k, k)}:{n}" for k, n in sorted(v.get("reasons", {}).items(), key=lambda kv: -kv[1])[:3])
            out.append(f"| {name} | {label} | {v['payer']} | {v['ok']} | {v['reverted']} | {v['creates']} | "
                       f"{v['clears']} | {reasons} |")
    out.append("")
    for name, s in per_scenario.items():
        ranked =sorted(((k, v) for k, v in rows.items() if v["byScenario"].get(name, {}).get("creates", 0)
                         or v["byScenario"].get(name, {}).get("clears", 0)),
                        key=lambda kv: -kv[1]["byScenario"][name]["creates"])
        if not ranked:
            continue
        out.append(f"## {name} — ranked by creations ({s['days']} days, {s['levels']} levels)\n")
        out.append("| # | Contract | Root | Creates | /day | /level | Clears | Re-creates | Protocol | Player | Top tx labels | Leaf labels |")
        out.append("|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---|---|")
        for i, ((account, root), v) in enumerate(ranked, 1):
            sc = v["byScenario"][name]
            tx = ", ".join(f"{k}:{n}" for k, n in sorted(sc["txLabels"].items(), key=lambda kv: -kv[1])[:3])
            leaves = ", ".join(f"`{k}`:{n}" for k, n in sorted(sc["labels"].items(), key=lambda kv: -kv[1])[:3])
            out.append(f"| {i} | {account} | `{root}` | {sc['creates']} | {fmt_rate(sc['creates'], s['days'])} | "
                       f"{fmt_rate(sc['creates'], s['levels'])} | {sc['clears']} | {sc['recreates']} | "
                       f"{sc['protocol']} | {sc['player']} | {tx} | {leaves} |")
        out.append("")
    for name, s in per_scenario.items():
        if s["levels"] < 3:
            continue
        ranked = sorted(((k, v) for k, v in rows.items() if v["byScenario"].get(name, {}).get("creates", 0)),
                        key=lambda kv: -kv[1]["byScenario"][name]["creates"])[:15]
        out.append(f"## {name} — creations per level (top roots; level at the time of the write)\n")
        lo, hi = s["meta"].get("startLevel", 0), s["meta"].get("endLevel", 0)
        out.append("| Contract | Root | " + " | ".join(f"L{l}" for l in range(lo, hi + 1)) + " |")
        out.append("|---|---|" + "---:|" * (hi - lo + 1))
        for (account, root), v in ranked:
            bl = v["byScenario"][name]["byLevel"]
            out.append(f"| {account} | `{root}` | " + " | ".join(str(bl.get(l, 0)) for l in range(lo, hi + 1)) + " |")
        out.append("")
    for name, s in per_scenario.items():
        if s["days"] < 40:
            continue
        lo, hi = s["meta"].get("startDay", 0), s["meta"].get("endDay", 0)
        buckets = list(range(lo, hi + 1, 20))
        ranked = sorted(((k, v) for k, v in rows.items() if v["byScenario"].get(name, {}).get("creates", 0)),
                        key=lambda kv: -kv[1]["byScenario"][name]["creates"])[:20]
        out.append(f"## {name} — creations per 20-day window (top roots; flat = steady churn, falling = one-time fill)\n")
        out.append("| Contract | Root | " + " | ".join(f"d{b}-{min(b + 19, hi)}" for b in buckets) + " |")
        out.append("|---|---|" + "---:|" * len(buckets))
        for (account, root), v in ranked:
            bd = v["byScenario"][name]["byDay"]
            cells = [sum(n for d, n in bd.items() if b <= d < b + 20) for b in buckets]
            out.append(f"| {account} | `{root}` | " + " | ".join(map(str, cells)) + " |")
        out.append("")
    out.append("## All scenarios combined\n")
    out.append("| # | Contract | Root | Creates | Clears | Re-creates | Protocol | Player | Scenarios |")
    out.append("|---:|---|---|---:|---:|---:|---:|---:|---|")
    for i, ((account, root), v) in enumerate(sorted(rows.items(), key=lambda kv: -kv[1]["creates"]), 1):
        scen = ", ".join(f"{n}:{d['creates']}" for n, d in v["byScenario"].items() if d["creates"] or d["clears"])
        out.append(f"| {i} | {account} | `{root}` | {v['creates']} | {v['clears']} | {v['recreates']} | "
                   f"{v['protocol']} | {v['player']} | {scen} |")
    out.append("")
    out.append("## Unattributed slots\n")
    if SECOND_CHANCE:
        out.append("The in-test walk left these events unattributed; the aggregator's brute-force pass "
                   "(keys 0..1023 of every mapping root) placed them: "
                   + ", ".join(f"{a} slot {r}: {n}" for (a, r), n in sorted(SECOND_CHANCE.items())) + ".\n")
    if not unattributed:
        out.append("None.\n")
    else:
        out.append("| Contract | Path | Creates | Clears | Scenarios | Sample slots |")
        out.append("|---|---|---:|---:|---|---|")
        for (account, path), u in sorted(unattributed.items(), key=lambda kv: -kv[1]["creates"]):
            out.append(f"| {account} | `{path}` | {u['creates']} | {u['clears']} | {', '.join(sorted(u['scenarios']))} | "
                       f"{', '.join(sorted(u['samples']))} |")
        out.append("")
    out.append("Sources: " + ", ".join(sorted(set(seen_in.values()))))
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("logs", nargs="*")
    ap.add_argument("--log-dir", default=str(ROOT / ".audit-test-logs/storage-census"))
    ap.add_argument("--forge-out", default=str(ROOT / "forge-out"))
    ap.add_argument("--out")
    ap.add_argument("--json")
    args = ap.parse_args()
    paths = args.logs or list(find_logs(args.log_dir))
    if not paths:
        sys.exit("no census logs found")
    scenarios, seen_in = parse(paths)
    if not scenarios:
        sys.exit("no CENSUS lines in the given logs")
    layouts = load_layouts(args.forge_out)
    rows, unattributed, per_scenario = aggregate(scenarios, layouts)
    text = render(rows, unattributed, per_scenario, seen_in, error_names(args.forge_out))
    if args.out:
        Path(args.out).write_text(text)
    else:
        sys.stdout.write(text)
    if args.json:
        Path(args.json).write_text(json.dumps({
            "scenarios": per_scenario,
            "roots": [{"contract": a, "root": r, **{k: (dict(v) if isinstance(v, defaultdict) else v)
                                                    for k, v in d.items() if k != "byScenario"},
                       "byScenario": {n: dict(s) for n, s in d["byScenario"].items()}}
                      for (a, r), d in sorted(rows.items(), key=lambda kv: -kv[1]["creates"])],
            "unattributed": [{"contract": a, "path": p, "creates": u["creates"], "clears": u["clears"],
                              "scenarios": sorted(u["scenarios"]), "samples": sorted(u["samples"])}
                             for (a, p), u in unattributed.items()],
        }, indent=1, default=str))


if __name__ == "__main__":
    main()
