#!/usr/bin/env python3
"""Failure-mode tests for the exact split arithmetic gate (requires z3-solver)."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import z3

SPEC = importlib.util.spec_from_file_location("split_proofs", Path(__file__).with_name("check-split-arithmetic.py"))
proofs = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(proofs)


class SplitProofGateTest(unittest.TestCase):
    def test_false_theorem_is_rejected(self):
        amount = z3.Int("amount")
        with self.assertRaises(AssertionError):
            proofs.check("bad", [amount >= 0], amount + 1 > amount)

    def test_vacuous_sensitivity_control_is_rejected(self):
        with self.assertRaises(AssertionError):
            proofs.check("bad-control", [z3.BoolVal(False)], expected=z3.sat)

    def test_unknown_is_not_a_pass(self):
        with patch.object(proofs.z3, "Solver") as factory:
            factory.return_value.check.return_value = z3.unknown
            factory.return_value.reason_unknown.return_value = "timeout"
            with self.assertRaisesRegex(AssertionError, "timeout"):
                proofs.check("timed-out", [z3.BoolVal(True)])

    def test_semantic_source_drift_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for file in proofs.SOURCE_PINS:
                target = root / file
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text((proofs.ROOT / file).read_text())
            target = root / "contracts/libraries/JackpotBucketLib.sol"
            target.write_text(target.read_text().replace("pool - distributed", "pool - distributed + 1"))
            with patch.object(proofs, "ROOT", root), patch("sys.argv", ["check-split-arithmetic.py"]):
                with self.assertRaisesRegex(AssertionError, "Source drift"):
                    proofs.main()


if __name__ == "__main__":
    unittest.main()
