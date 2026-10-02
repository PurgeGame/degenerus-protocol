#!/usr/bin/env python3
"""Regression checks for security registry write/alias coverage."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("rng_extract", Path(__file__).parent / "lib/rng_window_extract.py")
extract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(extract)


class WriteCoverage(unittest.TestCase):
    def test_nested_and_struct_writes(self):
        for line in ("root[a][b] = 3;", "root.member += 2;", "delete root;", "++root;", "root[a].field--;", "delete root[a][b];"):
            with self.subTest(line=line):
                self.assertEqual(extract.classify_mode(line, "root"), "WRITE")
        for line in ("if (root == 2) return;", "uint256 x = root[a][b];", "if (root.member != 0) return;"):
            self.assertEqual(extract.classify_mode(line, "root"), "READ")

    def test_storage_alias_is_scoped_and_binding_is_not_write(self):
        source = '''contract Fixture {
    struct Work { uint256 cursor; }
    Work internal root;
    function inspect() external view {
        Work storage work = root;
        uint256 x = work.cursor;
    }
    function begin() external {
        Work storage work = root;
        work.cursor = 1;
        resume(work);
    }
    function resume(Work storage work) internal {
        ++work.cursor;
    }
    function unrelated() external pure {
        uint256 work = 2;
        ++work;
    }
}'''
        saved = extract.VRF_WORD_IDENTIFIERS
        try:
            extract.VRF_WORD_IDENTIFIERS = ["root"]
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "Fixture.sol"
                path.write_text(source)
                records = extract.scan_file(str(path), "Fixture.sol")
            writes = {(fn, ident) for _, fn, ident, mode, *_ in records if mode == "WRITE"}
            self.assertEqual(writes, {("begin", "root"), ("resume", "root")})
        finally:
            extract.VRF_WORD_IDENTIFIERS = saved


if __name__ == "__main__":
    unittest.main()
