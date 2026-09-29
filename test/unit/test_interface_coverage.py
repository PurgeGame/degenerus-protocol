"""Control tests for fail-closed interface inventory and delegated selector coverage."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class InterfaceCoverageTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / "scripts").mkdir()
        shutil.copy2(ROOT / "scripts/check-interface-coverage.sh", self.root / "scripts")
        shutil.copytree(ROOT / "contracts/interfaces", self.root / "contracts/interfaces")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        forge = self.bin / "forge"
        forge.write_text('''#!/usr/bin/env python3
import os
import sys
target = sys.argv[2].split(":")[-1]
mode = os.environ.get("INTERFACE_TEST_MODE", "")
methods = [("common()", "00000001")]
if target == "IJackpotBattle":
    methods = [("settle()", "00000002"), ("lock()", "00000003")]
elif target == "CrapsBattle":
    methods = [("settle()", "00000002")]
elif target == "JackpotBattle" and mode != "missing_delegate":
    methods = [("lock()", "00000003")]
elif target == "IDegenerusParimutuel" and mode == "unused_missing":
    methods.append(("externalOnly()", "00000004"))
if target == "JackpotBattle" and mode == "empty_delegate":
    methods = []
for signature, selector in methods:
    print(f"| {signature} | {selector} |")
''')
        forge.chmod(0o755)

    def run_gate(self, mode=""):
        env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}", INTERFACE_TEST_MODE=mode)
        return subprocess.run(
            ["bash", "scripts/check-interface-coverage.sh"], cwd=self.root,
            env=env, text=True, capture_output=True, timeout=30,
        )

    def test_all_interfaces_and_delegated_union_are_checked(self):
        result = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("IDegenerusParimutuel", result.stdout)
        self.assertIn("CrapsBattle+JackpotBattle", result.stdout)
        self.assertIn("(2 fns covered)", result.stdout)

    def test_new_interface_cannot_silently_escape_the_map(self):
        (self.root / "contracts/interfaces/IUnmapped.sol").write_text(
            "pragma solidity 0.8.34; interface IUnmapped { function newCall() external; }\n"
        )
        result = self.run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("IUnmapped", result.stderr)
        self.assertIn("unmapped=", result.stderr)

    def test_missing_delegated_selector_is_fatal(self):
        result = self.run_gate("missing_delegate")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("lock()", result.stdout)

    def test_unused_declaration_is_still_a_required_interface_function(self):
        result = self.run_gate("unused_missing")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("externalOnly()", result.stdout)

    def test_empty_inspection_cannot_pass_a_delegated_interface(self):
        result = self.run_gate("empty_delegate")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no methods extracted", result.stdout)


if __name__ == "__main__":
    unittest.main()
