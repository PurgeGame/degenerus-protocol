"""Reject stale, incomplete and partially analyzed static-analysis evidence."""
import importlib.util
import json
import logging
from pathlib import Path
import tempfile
import types
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("slither_check", ROOT / "scripts/check-slither.py")
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)


class SlitherIntegrityTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        (self.root / "contracts").mkdir()
        (self.root / "contracts/Game.sol").write_text("contract Game {}\n")
        (self.root / "scope.txt").write_text("contracts/Game.sol\n")
        self.out = self.root / "out"
        (self.out / "build-info").mkdir(parents=True)
        self.path = self.out / "build-info/current.json"
        self.build = {"input": {"sources": {"contracts/Game.sol": {"content": "contract Game {}\n"}}},
                      "output": {"sources": {"contracts/Game.sol": {"ast": {"nodeType": "SourceUnit"}}}}}
        self.write()

    def write(self):
        self.path.write_text(json.dumps(self.build))

    def test_fresh_complete_inputs_pass(self):
        _, covered = CHECK.validate_inputs(self.out, self.root)
        self.assertEqual(covered, {"contracts/Game.sol"})

    def test_source_change_rejects_stale_evidence(self):
        (self.root / "contracts/Game.sol").write_text("contract Game { uint public value; }\n")
        with self.assertRaisesRegex(ValueError, "stale"):
            CHECK.validate_inputs(self.out, self.root)

    def test_missing_scope_and_ast_are_rejected(self):
        (self.root / "scope.txt").write_text("contracts/Game.sol\ncontracts/Other.sol\n")
        with self.assertRaisesRegex(ValueError, "Scoped sources missing"):
            CHECK.validate_inputs(self.out, self.root)
        self.build["output"]["sources"]["contracts/Game.sol"].pop("ast")
        self.write()
        with self.assertRaisesRegex(ValueError, "missing AST"):
            CHECK.validate_inputs(self.out, self.root)

    def test_old_incremental_unit_is_not_ignored(self):
        self.build["input"]["sources"]["contracts/Game.sol"]["content"] = "contract OldGame {}"
        (self.out / "build-info/old.json").write_text(json.dumps(self.build))
        with self.assertRaisesRegex(ValueError, "stale"):
            CHECK.validate_inputs(self.out, self.root)

    def test_missing_full_build_info_is_rejected(self):
        self.path.write_text('{"id":"minimal-forge-record"}')
        with self.assertRaisesRegex(ValueError, "full compiler input/output missing"):
            CHECK.validate_inputs(self.out, self.root)

    def test_logged_ir_failure_cannot_pass(self):
        test = self
        class FakeSlither:
            def __init__(self, *args, **kwargs):
                test.assertTrue(kwargs["disallow_partial"])
                logging.getLogger("SlitherSolc").error("Impossible to generate IR for top level function")
                self.contracts = [types.SimpleNamespace(
                    is_incorrectly_constructed=False, functions_declared=[object()])]
        module = types.ModuleType("slither.slither")
        module.Slither = FakeSlither
        with patch.dict("sys.modules", {"slither": types.ModuleType("slither"), "slither.slither": module}):
            with self.assertRaisesRegex(ValueError, "Incomplete Slither analysis"):
                CHECK.analyze(self.out)

    def test_gate_executes_ir_analysis_hook(self):
        test = self
        class FakeSlither:
            def __init__(self, *args, **kwargs):
                test.assertTrue(kwargs["disallow_partial"])
                self._init_parsing_and_analyses(False)

            def _init_parsing_and_analyses(self, skip_analyze):
                test.assertFalse(skip_analyze)
                test.assertTrue(self.skip_data_dependency)
                self.contracts = [types.SimpleNamespace(
                    is_incorrectly_constructed=False, functions_declared=[object()])]

        module = types.ModuleType("slither.slither")
        module.Slither = FakeSlither
        with patch.dict("sys.modules", {"slither": types.ModuleType("slither"), "slither.slither": module}):
            self.assertEqual(CHECK.analyze(self.out)["functions"], 1)


if __name__ == "__main__":
    unittest.main()
