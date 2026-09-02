#!/usr/bin/env python3
"""Enumerate every `unchecked { ... }` block in the main contract set, with a stable key.

An unchecked subtraction whose bound assumption is wrong is the canonical critical. The bounds
live in comments and in reviewers' heads; this extractor re-derives, from source, every
unchecked block in the game facade, its storage base and the modules, tagged with its enclosing
function and the block's first statement, so check-unchecked.sh can diff the live set against a
manifest that records the invariant keeping each block in range — and fail when a block is added,
moved or rewritten without that record.

Output: one record per block, TSV:
    <relpath>\t<function>\t<ordinal>\t<head>\t<lineno>\t<ops>
where ordinal is the block's 1-based position within its function, head is the block's first
non-empty statement (whitespace-collapsed, comments stripped, at most 90 chars), and ops lists
which of - / -= / * / *= / + / += / ++ / -- / << appear inside the block.

Scope: SCOPE_FILES (env, comma-separated) or the default main-contract set. Comments and strings
are masked before matching.
"""
import os
import re
import sys

CONTRACTS_DIR = os.environ.get("CONTRACTS_DIR", "contracts")
DEFAULT_SCOPE = [
    "DegenerusGame.sol",
    "storage/DegenerusGameStorage.sol",
    "modules/DegenerusGameAdvanceModule.sol",
    "modules/DegenerusGameJackpotModule.sol",
    "modules/DegenerusGameMintModule.sol",
    "modules/DegenerusGameGameOverModule.sol",
    "modules/GameAfkingModule.sol",
    "modules/DegenerusGameLootboxModule.sol",
    "modules/DegenerusGameBoonModule.sol",
    "modules/DegenerusGameWhaleModule.sol",
    "modules/DegenerusGameFoilPackModule.sol",
    "modules/DegenerusGameDecimatorModule.sol",
    "modules/DegenerusGameDegeneretteModule.sol",
    "modules/DegenerusGameBingoModule.sol",
]
SCOPE = [s.strip() for s in os.environ.get("SCOPE_FILES", "").split(",") if s.strip()] or DEFAULT_SCOPE

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from external_call_extract import strip_comments_and_strings  # noqa: E402

FN_RE = re.compile(r"\b(?:function\s+([A-Za-z_][A-Za-z0-9_]*)|(constructor)|(receive)\s*\(|(fallback)\s*\(|modifier\s+([A-Za-z_]\w*))")
UNCHECKED_RE = re.compile(r"\bunchecked\s*\{")
OPS = [("-=", "-="), ("+=", "+="), ("*=", "*="), ("++", "++"), ("--", "--"), ("<<", "<<"), ("-", "-"), ("+", "+"), ("*", "*")]


def enclosing(masked, pos):
    """Name of the function whose body contains offset `pos` (brace-depth scan)."""
    best = ""
    depth = 0
    pending = None
    stack = []
    i = 0
    sigs = [(m.start(), m.group(1) or m.group(2) or m.group(3) or m.group(4) or m.group(5)) for m in FN_RE.finditer(masked)]
    si = 0
    for i, ch in enumerate(masked):
        while si < len(sigs) and sigs[si][0] <= i:
            pending = sigs[si][1]
            si += 1
        if i == pos:
            for d, n in reversed(stack):
                if n:
                    return n
            return ""
        if ch == "{":
            depth += 1
            stack.append((depth, pending))
            pending = None
        elif ch == "}":
            if stack and stack[-1][0] == depth:
                stack.pop()
            depth -= 1
        elif ch == ";":
            pending = None
    return best


def block_body(masked, open_pos):
    depth = 0
    for j in range(open_pos, len(masked)):
        if masked[j] == "{":
            depth += 1
        elif masked[j] == "}":
            depth -= 1
            if depth == 0:
                return masked[open_pos + 1 : j]
    return masked[open_pos + 1 :]


def main():
    rows = []
    for rel in SCOPE:
        path = os.path.join(CONTRACTS_DIR, rel)
        if not os.path.exists(path):
            sys.stderr.write(f"WARN: missing {rel}\n")
            continue
        raw = open(path, encoding="utf-8").read()
        masked = strip_comments_and_strings(raw)
        per_fn = {}
        for m in UNCHECKED_RE.finditer(masked):
            open_pos = m.end() - 1
            fn = enclosing(masked, open_pos)
            per_fn[fn] = per_fn.get(fn, 0) + 1
            body = block_body(masked, open_pos)
            head = re.sub(r"\s+", " ", body.strip().split(";")[0]).strip()[:90]
            ops = []
            probe = body
            for tok, name in OPS:
                if tok in probe:
                    ops.append(name)
                    probe = probe.replace(tok, " ")
            ln = masked.count("\n", 0, m.start()) + 1
            rows.append((rel, fn, per_fn[fn], head, ln, "/".join(ops)))
    rows.sort(key=lambda r: (r[0], r[4]))
    for r in rows:
        print("\t".join(str(x) for x in r))


if __name__ == "__main__":
    main()
