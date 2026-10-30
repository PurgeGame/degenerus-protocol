"""Scope follows deployment imports, including indirect profile dependencies."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts/lib"))
import audit_scope


class AuditScopeTests(unittest.TestCase):
    def inventory(self, sources):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "deployments").mkdir()
            (root / "deployments/eip170.json").write_text(json.dumps({
                "deployments": [{"contract": "Host"}]
            }))
            for name, source in sources.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(source)
            with patch.object(audit_scope, "OPTIONAL_ROOTS", ()):
                return audit_scope.inventory(root)

    def test_transitive_imports_determine_scope_not_names(self):
        included, excluded = self.inventory({
            "contracts/Host.sol": 'import {Shared} from "./modules/Shared.sol"; contract Host {}',
            "contracts/modules/Shared.sol": 'import "../profiles/glamsterdam/Named.sol"; contract Shared {}',
            "contracts/profiles/glamsterdam/Named.sol": "contract Named {}",
            "contracts/modules/Unused.sol": "contract Unused {}",
            "contracts/mocks/Fake.sol": "contract Fake {}",
        })
        self.assertEqual(included, {"contracts/Host.sol", "contracts/modules/Shared.sol",
                                    "contracts/profiles/glamsterdam/Named.sol"})
        self.assertEqual(excluded, {"contracts/modules/Unused.sol"})

    def test_comments_do_not_expand_scope(self):
        included, excluded = self.inventory({
            "contracts/Host.sol": '// import "./Unused.sol";\n/* import "./Missing.sol"; */ contract Host {}',
            "contracts/Unused.sol": "contract Unused {}",
        })
        self.assertEqual(included, {"contracts/Host.sol"})
        self.assertEqual(excluded, {"contracts/Unused.sol"})

    def test_missing_import_fails_closed(self):
        with self.assertRaisesRegex(ValueError, "Missing production import/root"):
            self.inventory({"contracts/Host.sol": 'import "./Missing.sol"; contract Host {}'})


if __name__ == "__main__":
    unittest.main()
