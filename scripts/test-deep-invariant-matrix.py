#!/usr/bin/env python3
"""CI covers every test; Advance's ten seeds retain its full aggregate run budget."""

import importlib.util
from pathlib import Path
import re
import tempfile
import tomllib
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

    def test_advance_partitions_preserve_budget_and_other_tests(self):
        self.write("AdvanceLiveness.inv.t.sol", "function invariant_advanceLiveness() public view {}")
        rows = module.matrix(self.root)
        partitions = [row for row in rows if row["seed_partition"] != ""]
        self.assertEqual(len(partitions), 10)
        self.assertEqual({row["seed_partition"] for row in partitions}, {str(i) for i in range(10)})
        self.assertEqual(sum(row["runs"] for row in partitions), 1000)
        self.assertTrue(all(row["runs"] == 100 and row["depth"] == 256 and
                            row["profile"] == "deep_advance_ci" for row in partitions))
        self.assertEqual(len({module.partition_seed("12345", "1", row["seed_partition"])
                              for row in partitions}), 10)
        for name in ["invariant_advanceLiveness", "invariant_advanceLivenessExtra",
                     "invariant_inherited", "test_focused", "test_importedHelper"]:
            for signature in [name, name + "()"]:
                matches = [row for row in rows if re.search(row["match"], signature)
                           and not re.search(row["exclude"], signature)]
                self.assertEqual(len(matches), 10 if name == "invariant_advanceLiveness" else 1)
                if name != "invariant_advanceLiveness":
                    self.assertEqual(matches[0]["profile"], "deep")

    def test_missing_advance_property_is_not_silently_dropped(self):
        self.write("AdvanceLiveness.inv.t.sol", "// function invariant_advanceLiveness() public {}")
        with self.assertRaisesRegex(ValueError, "Missing partitioned property"):
            module.matrix(self.root)

    def test_seed_identity_reproducible_and_attempt_specific(self):
        seed = module.partition_seed("12345", "1", "0")
        self.assertRegex(seed, r"^0x[0-9a-f]{64}$")
        self.assertEqual(seed, module.partition_seed("12345", "1", "0"))
        self.assertNotEqual(seed, module.partition_seed("12345", "2", "0"))
        self.assertNotEqual(seed, module.partition_seed("12346", "1", "0"))
        self.assertEqual(module.partition_seed("12345", "1", ""), "12345")
        for invalid in ["10", "-1", "00", "unknown"]:
            with self.assertRaisesRegex(ValueError, "Unknown AdvanceLiveness"):
                module.partition_seed("12345", "1", invalid)
        with self.assertRaisesRegex(ValueError, "identity"):
            module.partition_seed("", "1", "0")

    def test_profile_and_inline_budgets_preserve_local_deep(self):
        root = Path(__file__).resolve().parents[1]
        profiles = tomllib.loads((root / "foundry.toml").read_text())["profile"]
        self.assertEqual(profiles["deep"]["invariant"]["runs"], 1000)
        self.assertEqual(profiles["deep"]["invariant"]["depth"], 256)
        self.assertEqual(profiles["deep_advance_ci"]["invariant"],
                         dict(profiles["deep"]["invariant"], runs=100))
        self.assertEqual(profiles["deep_advance_ci"]["fuzz"], profiles["deep"]["fuzz"])
        text = (root / "test/fuzz/invariant/AdvanceLiveness.inv.t.sol").read_text()
        for profile, runs, depth in [("default", 64, 100), ("deep", 1000, 256),
                                     ("deep_advance_ci", 100, 256)]:
            for key, expected in [("runs", runs), ("depth", depth)]:
                matches = re.findall(r"forge-config: " + profile + r"\.invariant\." + key + r" = (\d+)", text)
                self.assertEqual(matches, [str(expected)])


if __name__ == "__main__":
    unittest.main()
