#!/usr/bin/env python3
"""The CI partition must cover every test exactly once, including fallback cases."""

import importlib.util
from pathlib import Path
import re
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("deep_matrix", Path(__file__).with_name("deep-invariant-matrix.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class DeepMatrixTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.directory = self.root / "test/fuzz/invariant"
        self.directory.mkdir(parents=True)

    def write(self, name, text):
        (self.directory / name).write_text(text)

    def test_empty_inventory_fails(self):
        with self.assertRaisesRegex(ValueError, "No invariant sources"):
            module.matrix(self.root)

    def test_ordinary_and_new_roots_keep_all_tests(self):
        self.write("NewSuite.inv.t.sol", "contract NewSuite {}")
        rows = module.matrix(self.root)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["label"], "all")
        self.assertTrue(re.search(rows[0]["match"], "inheritedInvariant()"))

    def test_heavy_suite_without_properties_fails(self):
        self.write("CrapsRngSeal.inv.t.sol", "// function invariant_fake() public {}")
        with self.assertRaisesRegex(ValueError, "No named invariant"):
            module.matrix(self.root)

    def test_comments_and_multiline_declarations(self):
        self.write("CrapsRngSeal.inv.t.sol", """
            /* function invariant_fake() public {} */
            // function invariant_fake2() public {}
            function
                invariant_real()
                public view {}
        """)
        rows = module.matrix(self.root)
        self.assertEqual([x["label"] for x in rows], ["invariant_real", "other-tests"])

    def test_named_and_fallback_jobs_form_exact_partition(self):
        self.write("CrapsRngSeal.inv.t.sol", """
            function invariant_arm() public view {}
            function invariant_armExtra() public view {}
            function invariant_$lane() public view {}
        """)
        rows = module.matrix(self.root)
        for name in ["invariant_arm", "invariant_armExtra", "invariant_$lane",
                     "invariant_armExtraSuffix", "invariant_inherited", "test_focused", "test_helper"]:
            for signature in [name, name + "()"]:
                matches = [row for row in rows if re.search(row["match"], signature)
                           and not re.search(row["exclude"], signature)]
                self.assertEqual(len(matches), 1, signature)

    def test_all_roots_remain_represented(self):
        self.write("CrapsRngSeal.inv.t.sol", "function invariant_a() public view {}")
        self.write("Other.inv.t.sol", "contract Other {}")
        self.assertEqual({row["file"] for row in module.matrix(self.root)},
                         {"test/fuzz/invariant/CrapsRngSeal.inv.t.sol", "test/fuzz/invariant/Other.inv.t.sol"})


if __name__ == "__main__":
    unittest.main()
