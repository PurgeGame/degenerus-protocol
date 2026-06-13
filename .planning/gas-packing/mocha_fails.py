#!/usr/bin/env python3
# Extract a stable name-set of failing mocha tests from an npm-test log.
# Each failure block: "  N) Describe...\n  ...\n  <title>:\n  <error>".
# Signature = describe-chain + title (everything up to & including the first
# line ending with ':'), joined by ' > '. Printed one per line, sorted.
import sys, re

lines = open(sys.argv[1], encoding="utf-8", errors="replace").read().splitlines()
sigs = []
i = 0
n = len(lines)
hdr = re.compile(r'^  (\d+)\) (.*)$')
while i < n:
    m = hdr.match(lines[i])
    if not m:
        i += 1
        continue
    parts = [m.group(2).strip()]
    i += 1
    # collect describe-chain lines until the title line (ends with ':')
    while i < n:
        ln = lines[i]
        t = ln.strip()
        if parts[-1].endswith(':'):
            break
        # stop runaway if we hit an obvious error/stack line before a title
        if t.startswith('at ') or t.startswith('Error') or t.startswith('AssertionError'):
            break
        if t:
            parts.append(t)
        i += 1
    sig = ' > '.join(p.rstrip(':').strip() for p in parts)
    sigs.append(sig)

for s in sorted(set(sigs)):
    print(s)
