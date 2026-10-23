import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('rng_shape', ROOT / 'scripts/check-rng-shape.py')
SHAPE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SHAPE)


class RngShapeGateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.contracts = Path(self.temp.name) / 'contracts'
        shutil.copytree(ROOT / 'contracts', self.contracts)
        self.manifest = json.loads((ROOT / 'scripts/rng-shape-manifest.json').read_text())

    def change(self, file, before, after):
        p = self.contracts / file
        text = p.read_text()
        self.assertIn(before, text)
        p.write_text(text.replace(before, after, 1))

    def errors(self):
        return SHAPE.validate(self.contracts, self.manifest)[0]

    def test_reviewed_tree_passes(self):
        self.assertEqual(self.errors(), [])

    def test_duplicate_tag_fails(self):
        self.change('libraries/RngTags.sol', 'BAF_HEAD = 3;', 'BAF_HEAD = 1;')
        self.assertTrue(any('protocol-unique' in e for e in self.errors()))

    def test_runtime_tag_fails_even_if_registry_is_changed(self):
        self.change('modules/DegenerusGameAdvanceModule.sol', 'EntropyLib.hash2(RngTags.BAF_GATE, rngWord)', 'EntropyLib.hash2(epoch, rngWord)')
        self.manifest['sites'] = SHAPE.scan(self.contracts)
        self.assertTrue(any('Nonconstant' in e for e in self.errors()))

    def test_contract_address_fails_even_if_registry_is_changed(self):
        self.change('modules/DegenerusGameAdvanceModule.sol', 'EntropyLib.hash2(RngTags.BAF_GATE, rngWord)',
                    'EntropyLib.hash3(RngTags.BAF_GATE, rngWord, uint160(address(this)))')
        self.manifest['sites'] = SHAPE.scan(self.contracts)
        self.assertTrue(any('Forbidden' in e for e in self.errors()))

    def test_removed_discriminator_fails(self):
        self.change('libraries/PackedTicketSampleLib.sol',
                    'EntropyLib.hash3(RngTags.SAMPLE_PADDING, c.entropy, used)',
                    'EntropyLib.hash2(RngTags.SAMPLE_PADDING, c.entropy)')
        self.assertTrue(any('Unreviewed' in e for e in self.errors()))

    def test_lens_conversion_does_not_exempt_other_arguments(self):
        self.change('DegenerusGameLens.sol',
                    'RngTags.PROTOCOL_BOON_WINNER, word,',
                    'RngTags.PROTOCOL_BOON_WINNER, block.timestamp,')
        self.manifest['sites'] = SHAPE.scan(self.contracts)
        self.assertTrue(any('Forbidden' in e for e in self.errors()))

    def test_new_raw_hash_fails(self):
        self.change('modules/DegenerusGameAdvanceModule.sol', 'EntropyLib.hash2(RngTags.BAF_GATE, rngWord)',
                    'uint256(keccak256(abi.encode(rngWord)))')
        self.assertTrue(any('Unreviewed' in e for e in self.errors()))

    def test_raw_coin_bit_exception_is_pinned(self):
        self.change('Coinflip.sol', '(rngWord & 1) == 1', '((rngWord >> 1) & 1) == 1')
        self.assertTrue(any('raw coin-bit expression' in e for e in self.errors()))

    def test_gap_offset_is_pinned(self):
        self.change('Coinflip.sol', 'root >> (1 + uint256(start) - originalStart)',
                    'root >> (uint256(start) - originalStart)')
        self.assertTrue(any('raw coin-bit expression' in e for e in self.errors()))

    def test_other_consumer_cannot_use_raw_coin_bit(self):
        self.change('modules/DegenerusGameAdvanceModule.sol',
                    'EntropyLib.hash2(RngTags.BAF_GATE, rngWord)', 'rngWord')
        self.assertTrue(any('Stale reviewed hash' in e for e in self.errors()))


if __name__ == '__main__':
    unittest.main()
