"""Derive the EIP-170 audit inventory from deployment roots and Solidity imports."""
import json
import posixpath
import re

OPTIONAL_ROOTS = (
    "contracts/DegenerusGameLens.sol", "contracts/CrapsLens.sol",
    "contracts/DeityBoonViewer.sol", "contracts/DeityPassCustomizationRenderer.sol",
    "contracts/profiles/Selected.sol",
)
DISPLAY = {"contracts/Icons32Data.sol", "contracts/DeityPassCustomizationRenderer.sol"}


def inventory(root):
    sources = {p.relative_to(root).as_posix(): p.read_text()
               for p in (root / "contracts").rglob("*.sol")
               if p.relative_to(root).parts[1] not in {"mocks", "test"}}
    graph = {}
    contracts = {}
    for path, content in sources.items():
        content = re.sub(r"/\*.*?\*/|//[^\n]*", "", content, flags=re.S)
        graph[path] = [posixpath.normpath(posixpath.join(posixpath.dirname(path), imported))
                       for imported in re.findall(r'import\s+(?:[^;]*?from\s+)?["\']([^"\']+)["\']\s*;', content)
                       if imported.startswith(".")]
        for name in re.findall(r"\b(?:contract|library|interface)\s+(\w+)", content):
            contracts[name] = path
    manifest = root / "deployments/eip170.json"
    if not manifest.exists():
        return set(sources), set()
    rows = json.loads(manifest.read_text())["deployments"]
    todo = [contracts[row["contract"]] for row in rows] + list(OPTIONAL_ROOTS)
    reached = set()
    while todo:
        path = todo.pop()
        if path in reached:
            continue
        if path not in sources:
            raise ValueError(f"Missing production import/root: {path}")
        reached.add(path)
        todo.extend(graph[path])
    return reached, set(sources) - reached
