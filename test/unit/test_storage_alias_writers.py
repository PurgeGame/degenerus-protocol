import importlib.util
import pathlib
import tempfile
import unittest
from unittest.mock import patch


ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("rng_window_extract", ROOT / "scripts/lib/rng_window_extract.py")
EXTRACT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EXTRACT)


class StorageAliasWriterTests(unittest.TestCase):
    def writes(self, source):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "Module.sol"
            path.write_text(source)
            with patch.object(EXTRACT, "VRF_WORD_IDENTIFIERS", ["heapRoot", "nested", "rounds"]):
                return {(row[1], row[2]) for row in EXTRACT.scan_file(str(path), "Module.sol")
                        if row[3] == "WRITE"}

    def test_heap_mapping_alias_writes_are_attributed(self):
        writes = self.writes("""
contract Module {
    function insert(uint256 i, uint256 node) external {
        mapping(uint256 => uint256) storage heap = heapRoot;
        heap[i] = node;
    }
    function rank() external {
        mapping(uint256 => uint256) storage heap = heapRoot;
        heap[0] = heap[9];
    }
}
""")
        self.assertEqual(writes, {("insert", "heapRoot"), ("rank", "heapRoot")})

    def test_nested_mapping_alias_delete_is_attributed(self):
        writes = self.writes("""
contract Module {
    function clear(uint256 i, address owner) external {
        mapping(uint256 => mapping(address => uint256)) storage book = nested;
        delete book[i][owner];
    }
}
""")
        self.assertEqual(writes, {("clear", "nested")})

    def test_assembly_store_through_struct_alias_is_attributed(self):
        writes = self.writes("""
contract Module {
    function write(uint256 id, uint256 value) external {
        Round storage target = rounds[id];
        assembly ("memory-safe") { sstore(target.slot, value) }
    }
    function read(uint256 id) external view returns (uint256 value) {
        Round storage target = rounds[id];
        assembly ("memory-safe") { value := sload(target.slot) }
    }
}
""")
        self.assertEqual(writes, {("write", "rounds")})

    def test_read_only_and_other_function_aliases_are_not_writers(self):
        writes = self.writes("""
contract Module {
    function read() external view returns (uint256) {
        mapping(uint256 => uint256) storage heap = heapRoot;
        return heap[0];
    }
    function different() external {
        mapping(uint256 => uint256) storage heap = unrelated;
        heap[0] = 7;
    }
    function progress(uint256 id) external {
        Round storage round = rounds[id];
        ++round.cursor;
    }
}
""")
        self.assertEqual(writes, {("progress", "rounds")})


if __name__ == "__main__":
    unittest.main()
