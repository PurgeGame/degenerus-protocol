#!/usr/bin/env python3
"""Enumerate every external call site in the advance-chain contract set.

The liveness pillar requires that no transaction the game needs in order to progress can
revert or exceed the per-transaction gas cap. `advanceGame` is that transaction: it
delegatecalls the game's own modules and calls a ring of satellites (Coinflip, the craps
table, quests, sDGNRS, the charity resolver, the VRF coordinator ...). Every one of those
calls is either wrapped in try/catch, or made bare on the argument that the callee cannot
revert. That argument has lived in prose (per-site comments and a hand-kept map). This
extractor is the source-of-truth half of a drift gate: it re-derives, from source, every
external call expression in the crank's file set, tagged with its enclosing function and
its wrapping, so check-advance-calls.sh can diff the live set against the classified
manifest and fail when a new (unclassified) call appears on the crank.

Output: one record per call site, TSV:
    <relpath>\t<function>\t<callee>\t<mode>\t<lineno>\t<code>
where
    callee  is `Iface.fn` for an interface-cast or interface-typed-instance call,
            `delegatecall:Iface.fn` for a selector-bound delegatecall,
            `lowlevel:<kind>` for `.call/.staticcall/.delegatecall` without a selector,
            `yul:<kind>` for a `call/staticcall/delegatecall` opcode inside assembly,
            `new:<Contract>` for a creation.
    mode    is BARE (unwrapped) or TRY (the expression sits directly under `try`).
Deterministic ordering (path, line).

Scope: the files named in SCOPE_FILES (env override, comma-separated, relative to
CONTRACTS_DIR). Default = the crank set: the advance module, the game facade and its
storage base, and every module the advance module reaches by delegatecall.

Text-level analysis, not a compiler pass. Comment and string content is masked before
matching so prose mentions never count; brace depth gives the enclosing function; the
`try` detection looks at the statement head. It is deliberately over-inclusive: every
syntactic call is reported and the manifest records the reviewed reachability judgement.
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
]

SCOPE_FILES = DEFAULT_SCOPE
if os.environ.get("SCOPE_FILES"):
    SCOPE_FILES = [s.strip() for s in os.environ["SCOPE_FILES"].split(",") if s.strip()]

# Extra files scanned ONLY for interface-typed instance declarations (so `coinflip.x()` in a
# module resolves to `ICoinflip.x` even though the declaration lives in the storage base).
DECL_FILES = SCOPE_FILES


def strip_comments_and_strings(src: str) -> str:
    out = []
    i, n = 0, len(src)
    state = "code"
    while i < n:
        c = src[i]
        if state == "code":
            if src.startswith("//", i):
                state = "line"
                out.append("  ")
                i += 2
                continue
            if src.startswith("/*", i):
                state = "block"
                out.append("  ")
                i += 2
                continue
            if c == '"':
                state = "dq"
                out.append('"')
                i += 1
                continue
            if c == "'":
                state = "sq"
                out.append("'")
                i += 1
                continue
            out.append(c)
            i += 1
        elif state == "line":
            if c == "\n":
                state = "code"
                out.append(c)
            else:
                out.append(" ")
            i += 1
        elif state == "block":
            if src.startswith("*/", i):
                state = "code"
                out.append("  ")
                i += 2
                continue
            out.append("\n" if c == "\n" else " ")
            i += 1
        elif state in ("dq", "sq"):
            q = '"' if state == "dq" else "'"
            if c == "\\":
                out.append("  ")
                i += 2
                continue
            if c == q:
                state = "code"
                out.append(q)
            else:
                out.append(" ")
            i += 1
    return "".join(out)


FN_RE = re.compile(
    r"\b(function\s+([A-Za-z_][A-Za-z0-9_]*)|constructor|receive|fallback|modifier\s+([A-Za-z_][A-Za-z0-9_]*))\b"
)
IFACE_DECL_RE = re.compile(
    r"\b(I[A-Za-z][A-Za-z0-9_]*)\s+(?:internal|private|public)?\s*(?:constant|immutable)?\s*([a-zA-Z_][A-Za-z0-9_]*)\s*(?:=|;)"
)
CAST_CALL_RE = re.compile(
    r"\b(I[A-Za-z][A-Za-z0-9_]*)\s*\(([^()]*(?:\([^()]*\))?[^()]*)\)\s*\.\s*([a-zA-Z_][A-Za-z0-9_]*)\s*(?:\{[^}]*\}\s*)?\("
)
LOWLEVEL_RE = re.compile(r"\.(call|delegatecall|staticcall)\s*(?:\{[^}]*\}\s*)?\(")
SELECTOR_RE = re.compile(r"\b(I[A-Za-z][A-Za-z0-9_]*)\s*\.\s*([a-zA-Z_][A-Za-z0-9_]*)\s*\.\s*selector\b")
YUL_RE = re.compile(r"\b(call|staticcall|delegatecall)\s*\(")
NEW_RE = re.compile(r"\bnew\s+([A-Z][A-Za-z0-9_]*)\s*(?:\{[^}]*\}\s*)?\(")


def enclosing_functions(masked: str):
    """Map each line to its enclosing function name via brace-depth tracking."""
    fn_at_line = {}
    depth = 0
    stack = []  # (depth_when_opened, name)
    pending = None
    lines = masked.split("\n")
    for ln, line in enumerate(lines, 1):
        m = FN_RE.search(line)
        if m and depth <= 1 + len(stack) * 0 and pending is None:
            name = m.group(2) or m.group(3) or m.group(1)
            pending = name
        current = stack[-1][1] if stack else ""
        fn_at_line[ln] = current if current else (pending or "")
        for ch in line:
            if ch == "{":
                if pending is not None:
                    stack.append((depth, pending))
                    pending = None
                depth += 1
            elif ch == "}":
                depth -= 1
                if stack and stack[-1][0] == depth:
                    stack.pop()
        if pending is not None and ";" in line and "{" not in line:
            pending = None  # abstract declaration without a body
    return fn_at_line


def assembly_lines(masked: str):
    """Set of line numbers inside `assembly { ... }` blocks."""
    inside = set()
    depth = 0
    in_asm = False
    asm_depth = 0
    for ln, line in enumerate(masked.split("\n"), 1):
        i = 0
        while i < len(line):
            if not in_asm and line.startswith("assembly", i) and re.match(r"assembly\b", line[i:]):
                j = line.find("{", i)
                if j != -1:
                    in_asm = True
                    asm_depth = depth
                    depth += 1
                    inside.add(ln)
                    i = j + 1
                    continue
            ch = line[i]
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if in_asm and depth == asm_depth:
                    in_asm = False
            i += 1
        if in_asm:
            inside.add(ln)
    return inside


def load(relpath: str):
    path = os.path.join(CONTRACTS_DIR, relpath)
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def main():
    instances = {}  # name -> Iface
    for rel in DECL_FILES:
        p = os.path.join(CONTRACTS_DIR, rel)
        if not os.path.exists(p):
            continue
        masked = strip_comments_and_strings(load(rel))
        for m in IFACE_DECL_RE.finditer(masked):
            instances[m.group(2)] = m.group(1)
    inst_re = None
    if instances:
        names = "|".join(sorted(map(re.escape, instances), key=len, reverse=True))
        inst_re = re.compile(r"(?<![A-Za-z0-9_.])(" + names + r")\s*\.\s*([a-zA-Z_][A-Za-z0-9_]*)\s*(?:\{[^}]*\}\s*)?\(")

    records = []
    for rel in SCOPE_FILES:
        p = os.path.join(CONTRACTS_DIR, rel)
        if not os.path.exists(p):
            sys.stderr.write(f"WARN: scope file missing: {rel}\n")
            continue
        raw = load(rel)
        masked = strip_comments_and_strings(raw)
        fn_at = enclosing_functions(masked)
        asm = assembly_lines(masked)
        lines = masked.split("\n")
        raw_lines = raw.split("\n")
        for ln, line in enumerate(lines, 1):
            fn = fn_at.get(ln, "")
            found = []
            if ln in asm:
                for m in YUL_RE.finditer(line):
                    found.append((m.start(), f"yul:{m.group(1)}"))
            else:
                for m in CAST_CALL_RE.finditer(line):
                    found.append((m.start(), f"{m.group(1)}.{m.group(3)}"))
                if inst_re:
                    for m in inst_re.finditer(line):
                        found.append((m.start(), f"{instances[m.group(1)]}.{m.group(2)}"))
                for m in LOWLEVEL_RE.finditer(line):
                    kind = m.group(1)
                    # Selector-bound delegatecall: look ahead within the statement for I*.fn.selector.
                    window = "\n".join(lines[ln - 1 : min(len(lines), ln + 3)])
                    sm = SELECTOR_RE.search(window[m.start() :]) if kind == "delegatecall" else None
                    if sm:
                        found.append((m.start(), f"delegatecall:{sm.group(1)}.{sm.group(2)}"))
                    else:
                        found.append((m.start(), f"lowlevel:{kind}"))
                for m in NEW_RE.finditer(line):
                    found.append((m.start(), f"new:{m.group(1)}"))
            if not found:
                continue
            # Wrapping: the statement head (previous lines up to ';' or '{' + this line prefix).
            head = ""
            k = ln - 2
            while k >= 0 and not re.search(r"[;{}]\s*$", lines[k]):
                head = lines[k] + "\n" + head
                k -= 1
            for col, callee in sorted(found):
                prefix = head + line[:col]
                mode = "TRY" if re.search(r"\btry\s+[^;{}]*$", prefix) else "BARE"
                code = raw_lines[ln - 1].strip()
                records.append((rel, fn, callee, mode, ln, code))
    records.sort(key=lambda r: (r[0], r[4], r[2]))
    for r in records:
        print("\t".join(str(x) for x in r))


if __name__ == "__main__":
    main()
