#!/usr/bin/env python3
"""Reject native element operations on the logical-lane ticket queue and its aliases."""
import pathlib
import re
import sys


def violations(source):
    source = re.sub(r"/\*.*?\*/|//[^\n]*", lambda m: "\n" * m[0].count("\n"), source, flags=re.S)
    aliases = set(re.findall(r"\b(\w+)\s*=\s*ticketQueue\s*\[", source))
    # Storage parameters pass the same logical array between drain helpers. Scan them
    # conservatively in queue-consuming files, including a newly introduced alias.
    if "ticketQueue" in source:
        aliases.update(re.findall(r"uint256\[\]\s+storage\s+(\w+)\s*[,)]", source))
    changed = True
    while changed:
        extra = {target for target, origin in re.findall(r"uint256\[\]\s+storage\s+(\w+)\s*=\s*(\w+)\s*;", source) if origin in aliases}
        changed = bool(extra - aliases)
        aliases.update(extra)
    patterns = [r"\bticketQueue\s*\[[^;\n]*?\]\s*(?:\[|\.(?:push|pop)\s*\()"]
    patterns.extend(r"\b" + re.escape(name) + r"\s*(?:\[|\.(?:push|pop)\s*\()" for name in aliases)
    return [source.count("\n", 0, m.start()) + 1 for pattern in patterns for m in re.finditer(pattern, source)]


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        for op in ("q[0]", "q.push(1)", "q.pop()", "ticketQueue[key][0]", "ticketQueue[key].push(1)"):
            assert violations("uint256[] storage q = ticketQueue[key]; " + op), op
        assert violations("uint256[] storage q = ticketQueue[key]; uint256[] storage alias = q; alias[0];")
        assert not violations("uint256[] storage q = ticketQueue[key]; uint256 n = q.length; _tqPositionAt(q, 0);")
        print("PASS ticket queue codec gate self-test")
        sys.exit(0)
    failures = []
    for path in pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "contracts").rglob("*.sol"):
        if "mocks" in path.parts or "interfaces" in path.parts:
            continue
        failures.extend(f"{path}:{line}: native operation on a packed ticket queue" for line in violations(path.read_text()))
    print("\n".join(failures) if failures else "PASS ticket queues use lane codec operations")
    sys.exit(bool(failures))
