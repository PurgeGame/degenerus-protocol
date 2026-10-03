"""Snapshot identity includes verification inputs without expanding audit scope."""
import importlib.util
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("audit_snapshot", ROOT / "scripts/audit-snapshot.py")
AUDITOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDITOR)


class VerificationInputTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for folder in ("contracts/mocks", "contracts/test", "docs/audit", "scripts", "test"):
            (self.root / folder).mkdir(parents=True)
        contents = {
            "contracts/Logic.sol": "contract Logic {}\n",
            "contracts/ContractAddresses.sol": "library ContractAddresses {}\n",
            "contracts/Icons32Data.sol": "contract Icons32Data {}\n",
            "contracts/mocks/Harness.sol": "contract Harness {}\n",
            "contracts/test/Probe.sol": "contract Probe {}\n",
            "contracts/mocks/Reference.hex": "0x6000\n",
            "scripts/audit-snapshot.py": "# fixture tooling\n",
            "scope.txt": "contracts/Logic.sol\n",
            "out_of_scope.txt": "contracts/mocks/\ncontracts/test/\n",
        }
        for name in AUDITOR.SUPPORTING_SOLIDITY:
            contents.setdefault(name, "contract Supporting {}\n")
        self.scoped = sorted(["contracts/Logic.sol", *AUDITOR.SUPPORTING_SOLIDITY])
        contents["scope.txt"] = "\n".join(self.scoped) + "\n"
        for name, content in contents.items():
            (self.root / name).write_text(content)
        manifest = {"source_files": [], "source_file_count": 0,
                    "build_and_deployment_inputs": sorted(AUDITOR.SUPPORTING_SOLIDITY)}
        (self.root / "docs/audit/snapshot.json").write_text(json.dumps(manifest))
        for attribute, value in (("ROOT", self.root), ("AUDIT", self.root / "docs/audit")):
            replacement = patch.object(AUDITOR, attribute, value)
            replacement.start()
            self.addCleanup(replacement.stop)
        git = patch.object(AUDITOR.subprocess, "check_output", side_effect=lambda command, **kwargs:
                           b"scripts/audit-snapshot.py\0" if "ls-files" in command else b"a" * 40 + b"\n")
        git.start()
        self.addCleanup(git.stop)
        self.assertEqual(self.check(write=True), 0)

    def check(self, write=False):
        args = ["audit-snapshot.py", "--write"] if write else ["audit-snapshot.py"]
        with patch("sys.argv", args), contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return AUDITOR.main()

    def test_reference_bytecode_mutation_invalidates_verification_without_expanding_scope(self):
        self.assertEqual(self.check(), 0)
        self.assertEqual(AUDITOR.scope_files(), self.scoped)
        manifest = (self.root / "docs/audit/verification-sha256.txt").read_text()
        for path in ("contracts/mocks/Harness.sol", "contracts/test/Probe.sol", "contracts/mocks/Reference.hex"):
            self.assertIn(path, manifest)
        production_before = (self.root / "docs/audit/source-sha256.txt").read_bytes()
        (self.root / "contracts/mocks/Reference.hex").write_text("0x6001\n")
        self.assertEqual(self.check(), 1)
        self.assertEqual(AUDITOR.scope_files(), self.scoped)
        self.assertEqual((self.root / "docs/audit/source-sha256.txt").read_bytes(), production_before)

    def test_mock_removal_and_new_test_dependency_invalidate_verification(self):
        path = self.root / "contracts/mocks/Harness.sol"
        original = path.read_bytes()
        path.unlink()
        self.assertEqual(self.check(), 1)
        path.write_bytes(original)
        self.assertEqual(self.check(), 0)
        (self.root / "contracts/test/NewProbe.sol").write_text("contract NewProbe {}\n")
        self.assertEqual(self.check(), 1)
        self.assertEqual(AUDITOR.scope_files(), self.scoped)

    def test_new_production_module_cannot_be_omitted_from_scope(self):
        (self.root / "contracts/NewRngModule.sol").write_text("contract NewRngModule {}\n")
        with self.assertRaisesRegex(ValueError, "scope drift"):
            AUDITOR.scope_files()

    def test_reviewed_untracked_tool_is_authenticated(self):
        path = self.root / "scripts/layout/check_recursive_layout.py"
        path.parent.mkdir()
        path.write_text("# reviewed checker\n")
        self.assertEqual(self.check(), 1)
        self.assertEqual(self.check(write=True), 0)
        path.write_text("# changed checker\n")
        self.assertEqual(self.check(), 1)


if __name__ == "__main__":
    unittest.main()
