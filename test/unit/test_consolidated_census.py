"""New module files and forwarding wrappers must enter the existing drift gates."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ConsolidatedCensusTests(unittest.TestCase):
    def extract(self, script, source):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "modules").mkdir()
            (root / "modules/NewComponent.sol").write_text(source)
            result = subprocess.run(
                ["python3", str(ROOT / "scripts/lib" / script)],
                env={**os.environ, "CONTRACTS_DIR": str(root), "SCOPE_FILES": ""},
                capture_output=True, text=True, check=True,
            )
            return result.stdout

    def test_new_component_and_all_forwarding_wrappers_are_enumerated(self):
        methods = ("callRemaining", "callValueRemaining", "callBoolRemaining",
                   "staticcallRemaining", "staticWordRemaining")
        source = "contract NewComponent {\nfunction run() external {\n"
        source += "\n".join(f"BoundedCall.{method}(meter, target, minimum, tail, data);" for method in methods)
        source += "\n// BoundedCall.callRemaining(comment);\n} }\n"
        rows = self.extract("external_call_extract.py", source).splitlines()
        self.assertEqual(len(rows), len(methods))
        self.assertEqual({row.split("\t")[2] for row in rows}, {"bounded:" + m for m in methods})
        self.assertTrue(all(row.startswith("modules/NewComponent.sol\trun\t") for row in rows))

    def test_new_component_unchecked_arithmetic_cannot_escape_the_registry(self):
        result = self.extract("unchecked_extract.py",
                              "contract NewComponent {\nfunction run() external {\nunchecked { value -= charge; }\n} }\n")
        self.assertIn("modules/NewComponent.sol\trun\t1\tvalue -= charge", result)


if __name__ == "__main__":
    unittest.main()
