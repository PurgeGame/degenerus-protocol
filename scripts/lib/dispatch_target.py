#!/usr/bin/env python3
"""Resolve the lexically visible target assignment at a shared miner dispatch site.

Branch-local assignments disappear when their block ends. A nested selector can
inherit its parent branch's target; a sibling branch cannot. Unknown assignments
fail closed. This supplements the direct-delegatecall checks without allowlisting
the miner's selector sites.
"""
from pathlib import Path
import re
import sys

from external_call_extract import strip_comments_and_strings


def target_at(source, line):
    source = strip_comments_and_strings(source)
    if not re.search(r"\btarget\s*\.\s*delegatecall\s*(?:\{[^}]*\}\s*)?\(", source):
        return ""
    lines = source.splitlines()
    prefix = "\n".join(lines[:line - 1] + [lines[line - 1].split(".selector", 1)[0]])
    targets = [""]
    for match in re.finditer(r"\btarget\s*=\s*([^;]+);|[{}]", prefix):
        token = match[0]
        if token == "{":
            targets.append(targets[-1])
        elif token == "}":
            if len(targets) > 1:
                targets.pop()
        else:
            constant = re.fullmatch(r"ContractAddresses\.(\w+)\s*", match[1])
            targets[-1] = constant[1] if constant else ""
    return targets[-1]


if __name__ == "__main__":
    print(target_at(Path(sys.argv[1]).read_text(), int(sys.argv[2])))
