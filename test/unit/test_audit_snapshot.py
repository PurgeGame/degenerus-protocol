"""Evidence checksum failures must survive a source-identity refresh."""
import hashlib
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


class EvidenceIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.audit = Path(self.temp.name)
        self.patch = patch.object(AUDITOR, "AUDIT", self.audit)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.contents = b"identifiable evidence, including failed attempts\n"
        (self.audit / "evidence.zip").write_bytes(self.contents)
        self.manifest = {
            "supplement_archive_10": "evidence.zip",
            "supplement_archive_10_sha256": hashlib.sha256(self.contents).hexdigest(),
        }

    def test_matching_numbered_and_original_archives(self):
        self.manifest.update(evidence_archive="evidence.zip", evidence_archive_sha256=hashlib.sha256(self.contents).hexdigest())
        AUDITOR.check_archives(self.manifest)

    def test_tampered_archive_fails_even_when_refreshing_sources(self):
        (self.audit / "evidence.zip").write_bytes(b"replaced by a passing-only log")
        (self.audit / "snapshot.json").write_text(json.dumps(self.manifest))
        with patch("sys.argv", ["audit-snapshot.py", "--write"]):
            with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                AUDITOR.main()
        self.assertEqual(json.loads((self.audit / "snapshot.json").read_text()), self.manifest)
        self.assertFalse((self.audit / "source-sha256.txt").exists())

    def test_missing_archive_fails(self):
        (self.audit / "evidence.zip").unlink()
        with self.assertRaises(FileNotFoundError):
            AUDITOR.check_archives(self.manifest)

    def test_parent_and_absolute_paths_fail(self):
        for name in ("../evidence.zip", "/tmp/evidence.zip"):
            with self.subTest(name=name):
                self.manifest["supplement_archive_10"] = name
                with self.assertRaisesRegex(ValueError, "invalid evidence archive path"):
                    AUDITOR.check_archives(self.manifest)

    def test_missing_checksum_fails(self):
        del self.manifest["supplement_archive_10_sha256"]
        with self.assertRaisesRegex(ValueError, "missing or invalid archive checksum"):
            AUDITOR.check_archives(self.manifest)


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
        self.assertEqual(AUDITOR.scope_files(), ["contracts/Logic.sol"])
        manifest = (self.root / "docs/audit/verification-sha256.txt").read_text()
        for path in ("contracts/mocks/Harness.sol", "contracts/test/Probe.sol", "contracts/mocks/Reference.hex"):
            self.assertIn(path, manifest)
        production_before = (self.root / "docs/audit/source-sha256.txt").read_bytes()
        (self.root / "contracts/mocks/Reference.hex").write_text("0x6001\n")
        self.assertEqual(self.check(), 1)
        self.assertEqual(AUDITOR.scope_files(), ["contracts/Logic.sol"])
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
        self.assertEqual(AUDITOR.scope_files(), ["contracts/Logic.sol"])


if __name__ == "__main__":
    unittest.main()
