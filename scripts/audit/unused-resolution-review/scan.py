#!/usr/bin/env python3
"""Conservative production Solidity declaration inventory; not a public-API pruner.

Run from the repository root. Public/external functions, constructors, state
initializers, assembly references, and virtual overrides are retained. ABI-only
errors/events are candidates for manual inspection, not deletion instructions.
"""
import argparse
import hashlib
import json
import subprocess
from collections import defaultdict
from pathlib import Path


def walk(value):
    if isinstance(value, dict):
        yield value
        for item in value.values():
            yield from walk(item)
    elif isinstance(value, list):
        for item in value:
            yield from walk(item)


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--solc", default=str(Path.home() / ".svm/0.8.34/solc-0.8.34"))
parser.add_argument("--ast-cache", type=Path)
parser.add_argument("--revision", help="Read production source from this Git revision instead of the working tree")
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
out = Path(__file__).resolve().parent
if args.revision:
    files = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", args.revision,
                                     "--", "contracts"], cwd=root, text=True).splitlines()
    files = [f for f in files if f.endswith(".sol") and not {"mocks", "test"}.intersection(Path(f).parts)]
    sources = {f: {"content": subprocess.check_output(["git", "show", args.revision + ":" + f],
                                                    cwd=root, text=True)} for f in files}
else:
    paths = sorted(p for p in (root / "contracts").rglob("*.sol")
                   if not {"mocks", "test"}.intersection(p.relative_to(root).parts))
    sources = {str(p.relative_to(root)): {"content": p.read_text()} for p in paths}
if args.ast_cache and args.ast_cache.exists():
    compiled = json.loads(args.ast_cache.read_text())
else:
    request = {"language": "Solidity", "sources": sources, "settings": {
        "evmVersion": "osaka", "outputSelection": {"*": {
            "": ["ast"], "*": ["abi", "evm.methodIdentifiers"]}}}}
    result = subprocess.run([args.solc, "--standard-json", "--base-path", str(root),
                             "--include-path", str(root / "node_modules")],
                            input=json.dumps(request), text=True, capture_output=True, check=True)
    compiled = json.loads(result.stdout)
    if args.ast_cache:
        args.ast_cache.write_text(json.dumps(compiled))
errors = compiled.get("errors", [])
assert not any(e["severity"] == "error" for e in errors), errors
(out / "compiler-warnings.json").write_text(json.dumps(errors, indent=2) + "\n")

declarations, metadata = {}, {}
declaration_types = {"FunctionDefinition", "ModifierDefinition", "VariableDeclaration",
                     "ErrorDefinition", "EventDefinition"}
for file, source in compiled["sources"].items():
    source_path = root / file
    if not source_path.exists():
        source_path = root / "node_modules" / file
    raw = sources[file]["content"].encode() if file in sources else source_path.read_bytes()
    for contract in source["ast"].get("nodes", []):
        # Include file-level functions/constants as well as contract declarations.
        items = contract.get("nodes", []) if contract["nodeType"] == "ContractDefinition" else [contract]
        for node in items:
            if node["nodeType"] not in declaration_types:
                continue
            ident = node["id"]
            declarations[ident] = node
            metadata[ident] = {"file": file, "line": raw[:int(node["src"].split(":")[0])].count(b"\n") + 1,
                               "name": node.get("name", ""), "kind": node["nodeType"],
                               "visibility": node.get("visibility", ""),
                               "contract": contract.get("name", "") if items != [contract] else "",
                               "id": ident}

edges, incoming = defaultdict(set), defaultdict(set)
roots = set()
for ident, declaration in declarations.items():
    if (declaration["nodeType"] == "VariableDeclaration"
            or declaration.get("visibility") in {"public", "external"}
            or declaration.get("kind") in {"constructor", "fallback", "receive"}):
        roots.add(ident)
    for node in walk(declaration):
        refs = [node.get("referencedDeclaration")]
        refs += [r.get("declaration") for r in node.get("externalReferences", []) if isinstance(r, dict)]
        for target in refs:
            if isinstance(target, int) and target in declarations:
                edges[ident].add(target)
                incoming[target].add(ident)
    for base in declaration.get("baseFunctions", []):
        edges[base].add(ident)

reachable = set()
stack = list(roots)
while stack:
    ident = stack.pop()
    if ident in reachable:
        continue
    reachable.add(ident)
    stack.extend(edges[ident] - reachable)

inventory = {"method": __doc__.strip(), "production_source_count": len(sources),
             "unreachable_internal_functions": [], "unreferenced_nonpublic_constants": [],
             "unreferenced_nonpublic_storage": [], "unreferenced_errors_events": []}
for ident, node in declarations.items():
    if metadata[ident]["file"] not in sources:
        continue
    category = None
    if node["nodeType"] == "FunctionDefinition" and node.get("body") and ident not in reachable:
        category = "unreachable_internal_functions"
    elif node["nodeType"] == "VariableDeclaration" and node.get("visibility") != "public" and not incoming[ident]:
        if node.get("constant"):
            category = "unreferenced_nonpublic_constants"
        elif node.get("stateVariable"):
            category = "unreferenced_nonpublic_storage"
    elif node["nodeType"] in {"ErrorDefinition", "EventDefinition"} and not incoming[ident]:
        category = "unreferenced_errors_events"
    if category:
        inventory[category].append({**metadata[ident], "incoming": sorted(incoming[ident])})
(out / "inventory.json").write_text(json.dumps(inventory, indent=2) + "\n")
(out / "source-hashes.json").write_text(json.dumps({
    "commit": subprocess.check_output(["git", "rev-parse", args.revision or "HEAD"], cwd=root, text=True).strip(),
    "source_mode": "git_revision" if args.revision else "working_tree",
    "sha256": {f: hashlib.sha256(s["content"].encode()).hexdigest() for f, s in sources.items()}
}, indent=2) + "\n")
print(json.dumps({k: len(v) for k, v in inventory.items() if isinstance(v, list)}, indent=2))
