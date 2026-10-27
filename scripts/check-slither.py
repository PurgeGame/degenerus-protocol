#!/usr/bin/env python3
"""Require fresh compiler inputs and complete Slither parsing before trusting its reports."""

import argparse
import json
import logging
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


def validate_inputs(out, root=ROOT):
    """Old incremental build-info must not silently add stale compilation units."""
    files = sorted((out / "build-info").glob("*.json"))
    if not files:
        raise ValueError("No build-info; build production contracts with forge build --build-info first")
    covered = set()
    for path in files:
        build = json.loads(path.read_text())
        sources = build.get("input", {}).get("sources", {})
        asts = build.get("output", {}).get("sources", {})
        if not sources or not asts:
            raise ValueError(f"{path}: full compiler input/output missing; use a fresh --build-info output directory")
        for name, source in sources.items():
            target = root / name
            if not target.is_file() or source.get("content") != target.read_text():
                raise ValueError(f"{path}: stale or missing compiler source {name}")
            if not asts.get(name, {}).get("ast"):
                raise ValueError(f"{path}: missing AST for {name}")
            covered.add(name)
    scoped = {line.strip() for line in (root / "scope.txt").read_text().splitlines()
              if line.strip() and not line.lstrip().startswith("#")}
    if missing := scoped - covered:
        raise ValueError(f"Scoped sources missing from compiler inputs: {sorted(missing)}")
    return files, covered


class AnalysisErrors(logging.Handler):
    def __init__(self):
        super().__init__(logging.ERROR)
        self.errors = []

    def emit(self, record):
        self.errors.append(record.getMessage())


def analyze(out):
    from slither.slither import Slither

    class CompleteIR(Slither):
        def _init_parsing_and_analyses(self, skip_analyze):
            # Slither 0.11.5's analysis hook always generates SlithIR and storage
            # layouts. Its optional, expensive transitive dependency closure is
            # needed by detectors, not by this compiler-integrity gate.
            self.skip_data_dependency = True
            super()._init_parsing_and_analyses(skip_analyze)

    # disallow_partial rejects contract IR omissions. Capture error logs as well:
    # Slither 0.11.5 can log a top-level-function IR failure without raising it.
    errors = AnalysisErrors()
    logger = logging.getLogger()
    logger.addHandler(errors)
    try:
        slither = CompleteIR(str(ROOT), compile_force_framework="foundry", ignore_compile=True,
                             foundry_out_directory=str(out), disallow_partial=True)
    finally:
        logger.removeHandler(errors)
    if errors.errors:
        raise ValueError("Incomplete Slither analysis:\n" + "\n".join(errors.errors))
    contracts = slither.contracts
    if not contracts or any(c.is_incorrectly_constructed for c in contracts):
        raise ValueError("Slither returned empty or partially constructed contracts")
    return {"contracts": len(contracts),
            "functions": sum(len(c.functions_declared) for c in contracts),
            "analysis": "complete parsing and SlithIR; detector dependency closure is a separate run"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("out", type=Path, help="fresh Foundry production artifacts built with --build-info")
    args = parser.parse_args()
    out = args.out.resolve()
    files, sources = validate_inputs(out)
    result = analyze(out)
    # Parsing can take minutes; reject edits made while analysis was running too.
    validate_inputs(out)
    print(json.dumps({"result": "pass", "build_info_files": len(files),
                      "compiler_sources": len(sources), **result}, indent=2))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"Slither integrity check failed: {error}", file=sys.stderr)
        sys.exit(1)
