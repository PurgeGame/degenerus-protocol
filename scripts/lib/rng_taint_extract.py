#!/usr/bin/env python3
"""Enumerate every function that RECEIVES a VRF word by parameter, and every call that PASSES one.

The RNG-window gate (check-rng-window.sh) tracks the VRF-word STORAGE identifiers and the two
cross-contract accessors by name. A word that leaves storage and travels onward as an argument —
`coinflip.processCoinflipPayouts(bonus, currentWord, day)`, the jackpot module's `word`
parameters, the degenerette resolve, the craps engine's `seed` — is invisible to identifier
matching: those consumers contribute no rows while the gate still reports full coverage. This
extractor is the taint-propagation half of the same drift discipline: it re-derives, from
source, (a) every function whose parameter list names a word-shaped value and (b) every call
expression whose arguments name one, so check-rng-taint.sh can diff that set against a
classified manifest and fail when a new parameter-fed consumer appears.

Output: one record per finding, TSV:
    <relpath>\t<function>\t<kind>\t<subject>\t<lineno>\t<code>
where
    kind    PARAM  — `function` declares a word-shaped parameter; subject = the parameter name
            ARG    — `function` passes a word-shaped identifier (or a tracked storage identifier)
                     as an argument to a CROSS-CONTRACT callee (dotted expression, e.g.
                     `coinflip.processCoinflipPayouts`); same-file internal passes are covered by
                     the callee's own PARAM row and are not repeated
Deterministic ordering (path, line).

Scope: production contracts only (interfaces/, mocks/, test/ excluded). Comment and string
content is masked before matching. Text-level analysis: it over-approximates (a `seed` that is
a FLIP amount is reported and classified NOT-RNG in the manifest) so that no genuinely
word-carrying parameter can go unclassified.
"""

import os
import re
import sys

CONTRACTS_DIR = os.environ.get("CONTRACTS_DIR", "contracts")
EXCLUDE_DIRS = {"interfaces", "mocks", "test"}
if os.environ.get("EXCLUDE_DIRS"):
    EXCLUDE_DIRS = {s.strip() for s in os.environ["EXCLUDE_DIRS"].split(",") if s.strip()}

# Word-shaped identifiers: anything containing "word" (rngWord, currentWord, fallbackWord,
# derivedWord, randomWords, wordSeed ...), the bare entropy/seed names the engine uses, and the
# tracked storage identifiers themselves. WORD_NAME_RE env overrides.
WORD_NAME_RE = re.compile(
    os.environ.get(
        "WORD_NAME_RE",
        r"\b(?:[A-Za-z_]*[Ww]ord[A-Za-z0-9_]*|entropy|seed|rngSeed|randomWords?|rngWordCurrent|rngWordByDay|lootboxRngWordByIndex)\b",
    )
)

# Words that match the pattern but are never a VRF value — kept small and explicit so the
# over-approximation stays honest; anything not listed is reported.
NEVER_WORD = set(
    s.strip() for s in os.environ.get("NEVER_WORD", "wordCount,keyword,password,sword").split(",") if s.strip()
)


def strip_comments_and_strings(src: str) -> str:
    out = []
    i, n = 0, len(src)
    state = "code"
    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ""
        if state == "code":
            if c == "/" and nxt == "/":
                out.append("  "); i += 2; state = "line"; continue
            if c == "/" and nxt == "*":
                out.append("  "); i += 2; state = "block"; continue
            if c == '"':
                out.append('"'); i += 1; state = "dq"; continue
            if c == "'":
                out.append("'"); i += 1; state = "sq"; continue
            out.append(c); i += 1
        elif state == "line":
            if c == "\n":
                out.append("\n"); state = "code"
            else:
                out.append(" ")
            i += 1
        elif state == "block":
            if c == "*" and nxt == "/":
                out.append("  "); i += 2; state = "code"
            else:
                out.append("\n" if c == "\n" else " "); i += 1
        else:
            q = '"' if state == "dq" else "'"
            if c == "\\":
                out.append("  "); i += 2
            elif c == q:
                out.append(q); i += 1; state = "code"
            else:
                out.append("\n" if c == "\n" else " "); i += 1
    return "".join(out)


FUNC_HEAD_RE = re.compile(r"\bfunction\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", re.M)
CALL_RE = re.compile(r"((?:[A-Za-z_][A-Za-z0-9_]*\s*\.\s*)*[A-Za-z_][A-Za-z0-9_]*)\s*(?:\{[^}]*\}\s*)?\(")
KEYWORDS = {
    "if", "for", "while", "return", "require", "assert", "revert", "emit", "abi", "keccak256",
    "sha256", "uint256", "uint24", "uint32", "uint48", "uint64", "uint128", "uint8", "uint16",
    "bytes32", "bytes4", "address", "bool", "payable", "new", "type", "unchecked", "assembly",
    "function", "modifier", "catch", "try", "else", "do", "delete", "mstore", "mload", "sload",
    "sstore", "and", "or", "xor", "shl", "shr", "add", "sub", "mul", "div", "mod", "not", "iszero",
    "lt", "gt", "eq", "byte", "keccak", "calldataload", "calldatacopy", "returndatacopy",
    "return", "revert", "log0", "log1", "log2", "log3", "log4", "extsload", "encode",
    "encodePacked", "encodeWithSelector", "encodeWithSignature", "decode", "uint160", "uint96",
    "uint40", "uint72", "uint88", "uint104", "uint112", "uint136", "uint152", "uint168", "uint176",
    "uint184", "uint192", "uint200", "uint208", "uint216", "uint224", "uint232", "uint240",
    "uint248", "int256", "bytes", "string", "wrap", "unwrap",
}


def enclosing_functions(masked: str):
    result = ["<file-scope>"] * (masked.count("\n") + 1)
    sig_positions = [(m.start(), m.group(1)) for m in FUNC_HEAD_RE.finditer(masked)]
    for m in re.finditer(r"\b(constructor|receive|fallback)\b", masked):
        sig_positions.append((m.start(), m.group(1)))
    for m in re.finditer(r"\bmodifier\s+(\w+)", masked):
        sig_positions.append((m.start(), m.group(1)))
    sig_positions.sort()
    depth = 0
    pending = None
    stack = []
    idx = 0
    line = 0
    for i, ch in enumerate(masked):
        while idx < len(sig_positions) and sig_positions[idx][0] <= i:
            pending = sig_positions[idx][1]
            idx += 1
        active = "<file-scope>"
        for d, name in reversed(stack):
            if name is not None:
                active = name
                break
        if line < len(result):
            result[line] = active
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
        if ch == "\n":
            line += 1
    return result


def param_list(masked: str, open_paren: int) -> str:
    """The text between the matching parentheses starting at open_paren."""
    depth = 0
    for j in range(open_paren, len(masked)):
        if masked[j] == "(":
            depth += 1
        elif masked[j] == ")":
            depth -= 1
            if depth == 0:
                return masked[open_paren + 1 : j]
    return ""


def word_names(text: str):
    return [w for w in WORD_NAME_RE.findall(text) if w not in NEVER_WORD]


def scan_file(rel: str, records):
    path = os.path.join(CONTRACTS_DIR, rel)
    with open(path, "r", encoding="utf-8") as f:
        raw = f.read()
    masked = strip_comments_and_strings(raw)
    fn_at = enclosing_functions(masked)
    raw_lines = raw.split("\n")
    line_starts = [0]
    for i, ch in enumerate(masked):
        if ch == "\n":
            line_starts.append(i + 1)

    def line_of(off):
        lo, hi = 0, len(line_starts) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if line_starts[mid] <= off:
                lo = mid
            else:
                hi = mid - 1
        return lo

    # (a) PARAM rows: a word-shaped name in the declared parameter list. Bodiless declarations
    # (interface / abstract heads, which end in `;` before any `{`) are not consumers.
    for m in FUNC_HEAD_RE.finditer(masked):
        name = m.group(1)
        params = param_list(masked, m.end() - 1)
        tail = masked[m.end() + len(params) :]
        brace = tail.find("{")
        semi = tail.find(";")
        if brace == -1 or (semi != -1 and semi < brace):
            continue
        for pname in word_names(params):
            ln = line_of(m.start())
            records.append((rel, name, "PARAM", pname, ln + 1, raw_lines[ln].strip()))

    # (b) ARG rows: a call whose argument text names a word-shaped identifier.
    for m in CALL_RE.finditer(masked):
        callee = re.sub(r"\s+", "", m.group(1))
        last = callee.split(".")[-1]
        if last in KEYWORDS or callee in KEYWORDS:
            continue
        # Skip the function's own declaration head.
        head = masked[max(0, m.start() - 9) : m.start()]
        if head.endswith("function ") or head.strip().endswith("function"):
            continue
        # Only CROSS-CONTRACT passes are ARG rows: an internal callee in the same file declares
        # its own PARAM row, which is the classification that matters. A dotted callee is an
        # instance/cast call (`coinflip.processCoinflipPayouts`, `IX(addr).fn`); type casts and
        # library-style prefixes are filtered by the keyword set.
        if "." not in callee:
            continue
        prefix = callee.split(".")[0]
        if prefix in KEYWORDS or prefix.startswith(("uint", "int", "bytes")):
            continue
        args = param_list(masked, m.end() - 1)
        if not args.strip():
            continue
        names = word_names(args)
        if not names:
            continue
        ln = line_of(m.start())
        fn = fn_at[ln] if ln < len(fn_at) else "<file-scope>"
        if fn == "<file-scope>":
            continue
        records.append((rel, fn, "ARG", callee, ln + 1, raw_lines[ln].strip()))


def main():
    records = []
    for root, dirs, files in os.walk(CONTRACTS_DIR):
        rel_root = os.path.relpath(root, CONTRACTS_DIR)
        top = rel_root.split(os.sep)[0] if rel_root != "." else ""
        if top in EXCLUDE_DIRS:
            dirs[:] = []
            continue
        for fn in files:
            if not fn.endswith(".sol"):
                continue
            rel = os.path.normpath(os.path.join(rel_root, fn)) if rel_root != "." else fn
            scan_file(rel, records)
    seen = set()
    out = []
    for r in sorted(records, key=lambda r: (r[0], r[4], r[2], r[3])):
        key = (r[0], r[1], r[2], r[3])
        if key in seen:
            continue
        seen.add(key)
        out.append(r)
    for r in out:
        print("\t".join(str(x) for x in r))


if __name__ == "__main__":
    main()
