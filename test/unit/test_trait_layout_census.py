"""Fixed-array trait headers and overflow words must retain their census root."""
import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[2] / "scripts/audit/storage-census/aggregate.py"
spec = importlib.util.spec_from_file_location("storage_census_aggregate", path)
census = importlib.util.module_from_spec(spec)
spec.loader.exec_module(census)

class TraitLayoutCensusTests(unittest.TestCase):
    def setUp(self):
        self.layout = census.Layout(
            [{"label": "lvlTraitEntry", "slot": "84", "offset": 0, "type": "buffers"}],
            {"buffers": {"encoding": "inplace", "base": "traits", "numberOfBytes": "16384"},
             "traits": {"encoding": "inplace", "base": "word", "numberOfBytes": "8192"},
             "word": {"encoding": "inplace", "numberOfBytes": "32"}})

    def test_all_header_boundaries_resolve_to_fixed_array(self):
        for parity, trait in [(0, 0), (0, 255), (1, 0), (1, 255)]:
            self.assertEqual(self.layout.resolve(84 + parity * 256 + trait, []),
                             ("lvlTraitEntry", f"lvlTraitEntry[{parity}][{trait}]", True))

    def test_overflow_at_last_header_preserves_root(self):
        self.assertEqual(self.layout.resolve(595, ["A123"]),
                         ("lvlTraitEntry", "lvlTraitEntry[1][255]{tail}", True))

    def test_following_slot_is_not_attributed_to_trait_array(self):
        self.assertEqual(self.layout.resolve(596, []), ("slot596", "slot596", False))
