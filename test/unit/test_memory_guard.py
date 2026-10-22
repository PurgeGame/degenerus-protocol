import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    "memory_guard", Path(__file__).resolve().parents[2] / "scripts/check-memory-guard.py"
)
guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard)


class MemoryGuardTests(unittest.TestCase):
    def test_compiler_prologues(self):
        for code, expected in [("6080604052", 128), ("0x608080604052", 128),
                               ("6104e080604052", 1248), ("610120604052", 288),
                               ("604060809052", 128)]:
            self.assertEqual(guard.entry_pointer(code), expected)

    def test_does_not_search_later_code_or_push_data(self):
        for code in ["006080604052", "636080604052", "600080604052", "6080", "6180",
                     "608180604052", "6080602052", "", "__unlinked__"]:
            with self.subTest(code=code), self.assertRaises(ValueError):
                guard.entry_pointer(code)

    def test_allowlist_limits_and_removed_spills(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact = root / "Example.sol/Example.json"
            artifact.parent.mkdir()
            entries = [{"key": "EXAMPLE", "contract": "Example"}]
            def check(code, exceptions):
                artifact.write_text(json.dumps({"deployedBytecode": {"object": code}}))
                return guard.check(entries, root, exceptions)["errors"]
            allowed = {"Example": (256, "Measured loop cost exceeds the entry saving")}
            self.assertTrue(check("610100604052", {}))
            self.assertFalse(check("610100604052", allowed))
            self.assertTrue(check("610120604052", allowed))
            self.assertTrue(check("6080604052", allowed))
            self.assertFalse(check("6080604052", {}))
            self.assertTrue(check("6080604052", {"Typo": allowed["Example"]}))

    def test_missing_artifact_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            report = guard.check([{"key": "MISSING", "contract": "Missing"}], Path(directory), {})
            self.assertEqual(len(report["errors"]), 1)

    def test_allowlist_requires_reason_and_unique_bounded_pointer(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "allow.tsv"
            for text in ["Example\t0x100\t\n", "Example\t0x80\treason\n",
                         "Example\t0x101\treason\n", "Example\t0x100\treason\nExample\t0x100\treason\n"]:
                path.write_text(text)
                with self.subTest(text=text), self.assertRaises(ValueError):
                    guard.read_allowlist(path)


if __name__ == "__main__":
    unittest.main()
