#!/usr/bin/env python3
"""Enumerate every access to a VRF-word storage variable in the contract tree.

The VRF freeze invariant (v45 north-star) requires that every storage slot a
pending randomness consumption READS is frozen against player action for the
whole [request -> unlock] window. The runtime net (RngWindowFreeze.inv.t.sol)
asserts that freeze over a HAND-ENUMERATED set of slots. This extractor is the
source-of-truth half of a drift gate: it re-derives, from source, every read
and write of the VRF-word storage variables, tagged with its enclosing
function, so check-rng-window.sh can diff the live access set against the
classified manifest and fail when a new (unclassified) consumer appears.

Output: one record per access, TSV:
    <relpath>\t<function>\t<identifier>\t<mode>\t<lineno>\t<code>
where mode is READ or WRITE. Deterministic ordering (path, line).

Scope: production contracts only. interfaces/ (declarations, no bodies) and
mocks/ (external-format doubles) are excluded, mirroring the other gates.

This is text-level analysis, not a compiler dataflow pass. It is intentionally
conservative: it reports every syntactic access so the gate forces a human
classification of each one; it does not attempt to prove reachability. Comment
and string content is stripped before matching so prose mentions never count.
"""

import os
import re
import sys

# The VRF-word storage variables. These are the slots a pending consumption
# reads: the fulfilled-but-not-yet-sealed daily buffer, the two sealed
# VRF-derived words, plus the packed cursor read ALONGSIDE the lootbox word
# (a non-VRF read of the cursor in the window is its own bug class, so it is
# tracked here too). Keep this list in lockstep with the manifest header
# FROZEN_SET and with the enumerated slot set in RngWindowFreezeHandler.
#
# The IDENTIFIERS env var (comma-separated) overrides this default set so the
# same scope-tracking extractor serves every identifier-registry gate (RNGW
# uses the default; the SOLV pool-write gate passes the counted-term set).
VRF_WORD_IDENTIFIERS = [
    "rngWordCurrent",
    "rngWordByDay",
    "lootboxRngWordByIndex",
    "lootboxRngPacked",
]

if os.environ.get("IDENTIFIERS"):
    VRF_WORD_IDENTIFIERS = [
        s.strip() for s in os.environ["IDENTIFIERS"].split(",") if s.strip()
    ]

# Directories under contracts/ excluded from the scan (no executable consumer
# bodies live here). Matches check-raw-selectors.sh EXCLUDE_PATHS intent.
# EXCLUDE_DIRS env var (comma-separated) overrides — the SOLV gate also drops
# contracts/test (test-only harnesses, not production surface); the RNGW gate
# keeps the default so its reviewed manifest stays row-identical.
EXCLUDE_DIRS = {"interfaces", "mocks"}

if os.environ.get("EXCLUDE_DIRS"):
    EXCLUDE_DIRS = {
        s.strip() for s in os.environ["EXCLUDE_DIRS"].split(",") if s.strip()
    }


def strip_comments_and_strings(src: str) -> str:
    """Blank out // line comments, /* */ block comments, and string/hex
    literals, preserving newlines and column positions so line numbers and
    brace depth stay accurate. Returns the masked source."""
    out = []
    i, n = 0, len(src)
    state = "code"  # code | line | block | dq | sq
    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ""
        if state == "code":
            if c == "/" and nxt == "/":
                out.append("  ")
                i += 2
                state = "line"
                continue
            if c == "/" and nxt == "*":
                out.append("  ")
                i += 2
                state = "block"
                continue
            if c == '"':
                out.append('"')
                i += 1
                state = "dq"
                continue
            if c == "'":
                out.append("'")
                i += 1
                state = "sq"
                continue
            out.append(c)
            i += 1
        elif state == "line":
            if c == "\n":
                out.append("\n")
                i += 1
                state = "code"
            else:
                out.append(" ")
                i += 1
        elif state == "block":
            if c == "*" and nxt == "/":
                out.append("  ")
                i += 2
                state = "code"
            else:
                out.append("\n" if c == "\n" else " ")
                i += 1
        elif state == "dq":
            if c == "\\":
                out.append("  ")
                i += 2
            elif c == '"':
                out.append('"')
                i += 1
                state = "code"
            else:
                out.append("\n" if c == "\n" else " ")
                i += 1
        elif state == "sq":
            if c == "\\":
                out.append("  ")
                i += 2
            elif c == "'":
                out.append("'")
                i += 1
                state = "code"
            else:
                out.append("\n" if c == "\n" else " ")
                i += 1
    return "".join(out)


FUNC_RE = re.compile(
    r"\b(?:function\s+(\w+)|(constructor)|(receive)\s*\(|(fallback)\s*\()"
)
MODIFIER_RE = re.compile(r"\bmodifier\s+(\w+)")


def enclosing_functions(masked: str):
    """Return a list (len == number of lines) mapping each 0-based line to the
    name of the function/modifier/constructor whose body encloses it, or
    '<file-scope>' for declarations outside any function body.

    Scope tracking is brace-depth based on the masked (comment-free) source.
    The function name is latched at the '{' that opens the most recent
    signature seen at the depth the body opens on."""
    result = ["<file-scope>"] * (masked.count("\n") + 1)

    # Signatures can span multiple lines, so find every function/modifier/ctor
    # signature up front with its start offset, then interleave with braces as we
    # scan the masked (comment-free) source. A signature name is latched as
    # pending until the '{' that opens its body (or a ';' that ends a declaration).
    sig_positions = []  # (offset, name)
    for m in FUNC_RE.finditer(masked):
        name = m.group(1) or m.group(2) or m.group(3) or m.group(4)
        sig_positions.append((m.start(), name))
    for m in MODIFIER_RE.finditer(masked):
        sig_positions.append((m.start(), m.group(1)))
    sig_positions.sort()

    depth = 0
    pending_name = None  # last signature name seen since the last '{' or ';'
    scope_stack = []     # list of (open_depth, name)
    sig_idx = 0
    cur_line = 0
    for i, ch in enumerate(masked):
        while sig_idx < len(sig_positions) and sig_positions[sig_idx][0] <= i:
            pending_name = sig_positions[sig_idx][1]
            sig_idx += 1
        # Determine active function name (innermost named scope).
        active = "<file-scope>"
        for d, name in reversed(scope_stack):
            if name is not None:
                active = name
                break
        if cur_line < len(result):
            result[cur_line] = active
        if ch == "{":
            depth += 1
            if pending_name is not None:
                scope_stack.append((depth, pending_name))
                pending_name = None
            else:
                scope_stack.append((depth, None))
        elif ch == "}":
            if scope_stack and scope_stack[-1][0] == depth:
                scope_stack.pop()
            depth -= 1
        elif ch == ";":
            pending_name = None
        if ch == "\n":
            cur_line += 1
    return result


DECL_RE_TMPL = (
    r"\b(?:uint\d*|mapping\s*\([^)]*\))\s+(?:internal|public|private|constant)\s+"
)


def classify_mode(masked_line: str, ident: str) -> str:
    """DECL if this line is the state-variable declaration of the identifier;
    WRITE if the identifier is the target of an assignment (ident = ... or
    ident[..] = ...); else READ. Compound assignments (+=, -=, ...) count as
    WRITE (they also read, but a write site is the stricter classification the
    gate cares about — a producer). DECL is tested first so an initialized
    declaration (`uint256 internal x = ...;`) is a DECL, not a WRITE."""
    if re.search(DECL_RE_TMPL + re.escape(ident) + r"\b", masked_line):
        return "DECL"
    pat = re.compile(
        r"\b" + re.escape(ident) + r"\b\s*(\[[^\]]*\]\s*)?(?P<op>[-+*/|&^]?=)(?![=])"
    )
    if pat.search(masked_line):
        return "WRITE"
    return "READ"


def scan_file(path: str, relpath: str):
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        src = fh.read()
    masked = strip_comments_and_strings(src)
    masked_lines = masked.split("\n")
    raw_lines = src.split("\n")
    fn_by_line = enclosing_functions(masked)

    records = []
    for idx, mline in enumerate(masked_lines):
        for ident in VRF_WORD_IDENTIFIERS:
            # Whole-word match on the masked (comment-free) line.
            if re.search(r"\b" + re.escape(ident) + r"\b", mline):
                mode = classify_mode(mline, ident)
                fn = fn_by_line[idx] if idx < len(fn_by_line) else "<file-scope>"
                code = raw_lines[idx].strip() if idx < len(raw_lines) else ""
                records.append((relpath, fn, ident, mode, idx + 1, code))
    return records


def main():
    root = os.environ.get("CONTRACTS_DIR", "contracts")
    if not os.path.isdir(root):
        sys.stderr.write("ERROR: CONTRACTS_DIR does not exist: %s\n" % root)
        return 2
    all_records = []
    for dirpath, dirnames, filenames in os.walk(root):
        # prune excluded dirs
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS]
        for fn in sorted(filenames):
            if not fn.endswith(".sol"):
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, root)
            all_records.extend(scan_file(full, rel))
    # Deterministic order: path, line.
    all_records.sort(key=lambda r: (r[0], r[4]))
    for rel, fn, ident, mode, lineno, code in all_records:
        sys.stdout.write("\t".join([rel, fn, ident, mode, str(lineno), code]) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
