import importlib.util
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('native_sweep', ROOT / 'scripts/consolidation/native-multiplier-sweep.py')
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class NativeMultiplierSweepTest(unittest.TestCase):
    def args(self, **overrides):
        values = dict(rpc='http://127.0.0.1:19351', limit=16_777_216,
                      multiplier=0, max_groups=0, through_level=None)
        values.update(overrides)
        return SimpleNamespace(**values)

    def test_default_campaign_does_not_stop_at_a_level(self):
        args = gate.parser().parse_args(['--dataset', 'd', '--artifacts', 'a', '--out', 'o',
            '--rpc', 'http://127.0.0.1:1', '--schedule', 'osaka', '--profile', 'eip170', '--multiplier', '0'])
        self.assertIsNone(args.through_level)
        self.assertEqual(args.max_groups, 0)
        gate.validate_args(args)

    def test_only_real_transaction_caps_and_supported_calibrations(self):
        for multiplier in (0, 2500, 10_000, 2**32 - 1):
            gate.validate_args(self.args(multiplier=multiplier))
        for multiplier in (-1, 1, 2499, 2**32):
            with self.assertRaises(ValueError):
                gate.validate_args(self.args(multiplier=multiplier))
        for limit in (20_999, 500_000_000):
            with self.assertRaises(ValueError):
                gate.validate_args(self.args(limit=limit))

    def test_remote_nodes_and_invalid_partial_bounds_rejected(self):
        for override in ({'rpc': 'https://example.com'}, {'max_groups': -1}, {'through_level': 0}):
            with self.assertRaises(ValueError):
                gate.validate_args(self.args(**override))

    def test_empty_duplicate_or_missing_calls_are_not_complete_evidence(self):
        gate.validate_rows([{'seq': 1}, {'seq': 2}])
        for rows in ([], [{'seq': 2}], [{'seq': 1}, {'seq': 1}], [{'seq': 1}, {'seq': 3}]):
            with self.assertRaises(ValueError):
                gate.validate_rows(rows)

    def test_contiguous_truncated_prefix_is_not_a_complete_capture(self):
        rows = [{'seq': 1, 'label': 'purchase', 'success': True},
                {'seq': 2, 'label': 'mineFlip:3', 'success': True}]
        summary = dict(calls=2, counts={'purchase': 1, 'mineFlip:3': 1}, census={'successfulCalls': 2})
        gate.validate_rows(rows, summary)
        with self.assertRaisesRegex(ValueError, 'call count'):
            gate.validate_rows(rows[:1], summary)
        changed = [dict(rows[0]), dict(rows[1], label='purchase')]
        with self.assertRaisesRegex(ValueError, 'action counts'):
            gate.validate_rows(changed, summary)
        changed = [dict(rows[0]), dict(rows[1], success=False)]
        with self.assertRaisesRegex(ValueError, 'success counts'):
            gate.validate_rows(changed, summary)

    def test_grouping_preserves_timestamp_block_and_crank_boundaries(self):
        def row(seq, **kw):
            return dict(seq=seq, label=kw.get('label', 'mineFlip:3'), number=kw.get('number', 1),
                        timestamp=kw.get('timestamp', 10), crank=kw.get('crank'))
        rows = [row(1, crank={}), row(2, label='vrfFulfill'), row(3, number=2),
                row(4, number=2, timestamp=11), row(5, number=2, timestamp=11, crank={}),
                row(6, label='purchase', number=2, timestamp=11), row(7, label='purchase')]
        self.assertEqual([[r['seq'] for r in g] for g in gate.groups(rows)], [[1, 2], [3], [4], [5], [6], [7]])

    def test_world_oracle_rejects_one_wei_and_one_slot_mutations(self):
        baseline = {'player': {'balance': '0x5', 'nonce': '0x1', 'state': {'0x1': '0x2'}}}
        for mutation in ({'balance': '0x6', 'nonce': '0x1', 'state': {'0x1': '0x2'}},
                         {'balance': '0x5', 'nonce': '0x1', 'state': {'0x1': '0x3'}}):
            self.assertTrue(gate.differences({'player': mutation}, baseline, {'player'}, 'fixture'))
        # Only explicit sender transaction nonces are omitted, not contract nonces.
        changed = {'player': {'balance': '0x5', 'nonce': '0x2', 'state': {'0x1': '0x2'}}}
        self.assertFalse(gate.differences(changed, baseline, {'player'}, 'fixture'))
        self.assertTrue(gate.differences(changed, baseline, set(), 'fixture'))

    def test_fixture_eth_is_not_discarded_with_recorder_storage(self):
        before = {'fixture': {'balance': '0x5', 'nonce': '0x1', 'state': {'0x1': '0x2'}}}
        bookkeeping = {'fixture': {'balance': '0x5', 'nonce': '0x2', 'state': {'0x1': '0x3'}}}
        self.assertFalse(gate.differences(bookkeeping, before, set(), 'fixture'))
        bookkeeping['fixture']['balance'] = '0x4'
        self.assertTrue(gate.differences(bookkeeping, before, set(), 'fixture'))

    def test_redemption_cache_equivalence_is_inactive_only_and_keeps_adjacent_fields(self):
        spec = dict(address='sdgnrs', batchSlot='0x6', batchShift=128, cacheSlot='0x7', cacheShift=160)
        before = {'sdgnrs': {'balance': '0x5', 'nonce': '0x1', 'state': {'0x6': '0x1', '0x7': '0x123'}}}
        after = json.loads(json.dumps(before))
        after['sdgnrs']['state']['0x7'] = hex(0x123 | (123456 << 160))
        self.assertTrue(gate.differences(after, before, set(), 'fixture'))
        self.assertFalse(gate.differences(after, before, set(), 'fixture', spec))
        # The oracle must not mutate either supplied world.
        self.assertEqual(after['sdgnrs']['state']['0x7'], hex(0x123 | (123456 << 160)))
        for world in (after, before):
            world['sdgnrs']['state']['0x6'] = hex(1 | (7 << 128))
            self.assertTrue(gate.differences(after, before, set(), 'fixture', spec))
            world['sdgnrs']['state']['0x6'] = '0x1'
        after['sdgnrs']['state']['0x7'] = hex(0x124 | (123456 << 160))
        self.assertTrue(gate.differences(after, before, set(), 'fixture', spec))

    def test_redemption_cache_exception_requires_reviewed_source_and_exact_layout(self):
        source = {'contracts/sDGNRS.sol': '7bac41205f7871f84d3f2a3e26e12d98a7a469b830c0965274391b5afe159137'}
        fields = [dict(label='_settlingBatch', slot='6', offset=16, type='t_uint32'),
                  dict(label='_settlingReserveLeft', slot='7', offset=20, type='t_uint96')]
        with TemporaryDirectory() as temp:
            artifacts = Path(temp)
            target = artifacts / 'sDGNRS.sol/sDGNRS.json'
            target.parent.mkdir()
            def write(layout):
                target.write_text(json.dumps({'storageLayout': {'storage': layout}}))
            write(fields)
            self.assertEqual(gate.inactive_cache_spec(artifacts, {'sDGNRS': 'sdgnrs'}, source)['cacheShift'], 160)
            with self.assertRaisesRegex(ValueError, 'source review'):
                gate.inactive_cache_spec(artifacts, {'sDGNRS': 'sdgnrs'}, {})
            for index, key, value in ((0, 'slot', '7'), (0, 'offset', 12), (0, 'type', 't_uint96'),
                                      (1, 'slot', '6'), (1, 'offset', 0), (1, 'type', 't_uint32')):
                changed = [dict(field) for field in fields]
                changed[index][key] = value
                write(changed)
                with self.assertRaisesRegex(AssertionError, 'layout changed'):
                    gate.inactive_cache_spec(artifacts, {'sDGNRS': 'sdgnrs'}, source)

    def test_provenance_rejects_stale_captured_and_current_sources(self):
        import hashlib
        with TemporaryDirectory() as temp:
            root = Path(temp) / 'root'
            bundle = Path(temp) / 'bundle'
            capture = bundle / 'profiles/eip170/capture'
            artifacts = capture / 'forge-out'
            artifacts.mkdir(parents=True)
            dataset = capture.parent / 'dataset'
            dataset.mkdir()
            (dataset / 'initial.json').write_text('{}')
            (bundle / 'SHA256SUMS').write_text(hashlib.sha256(b'{}').hexdigest() + '  profiles/eip170/dataset/initial.json\n')
            inputs = capture.parent / 'capture-evidence'
            inputs.mkdir()
            sources = {'contracts/Foo.sol': 'contract Foo {}',
                       'contracts/profiles/Selected.sol': 'import "./eip170/Eip170Game.sol";'}
            for base in (root, capture):
                for name, body in sources.items():
                    (base / name).parent.mkdir(parents=True, exist_ok=True)
                    (base / name).write_text(body)
            (root / 'scope.txt').write_text('\n'.join(sources))
            manifest = {name: hashlib.sha256(body.encode()).hexdigest() for name, body in sources.items()}
            (inputs / 'focused-01-inputs.json').write_text(json.dumps(manifest))
            self.assertEqual(gate.source_identity(dataset, artifacts, 'eip170', root)['generatedSourceDifferences'], [])
            (root / 'contracts/Foo.sol').write_text('contract Foo { uint x; }')
            with self.assertRaisesRegex(ValueError, 'differs from checkout'):
                gate.source_identity(dataset, artifacts, 'eip170', root)
            (capture / 'contracts/Foo.sol').write_text('contract Foo { uint x; }')
            with self.assertRaisesRegex(ValueError, 'recorded compiler input'):
                gate.source_identity(dataset, artifacts, 'eip170', root)

    def test_packaged_checksum_rejects_rewritten_dataset(self):
        # The full handoff's manifest is exercised by real runs; this unit verifies
        # the same failure through a minimal, source-consistent capture.
        import hashlib
        with TemporaryDirectory() as temp:
            root = Path(temp) / 'root'
            bundle = Path(temp) / 'bundle'
            capture = bundle / 'profiles/eip170/capture'
            artifacts = capture / 'forge-out'
            artifacts.mkdir(parents=True)
            dataset = capture.parent / 'dataset'
            dataset.mkdir()
            (dataset / 'initial.json').write_text('{"changed":true}')
            (bundle / 'SHA256SUMS').write_text(hashlib.sha256(b'{}').hexdigest() + '  profiles/eip170/dataset/initial.json\n')
            body = 'import "./eip170/Eip170Game.sol";'
            name = 'contracts/profiles/Selected.sol'
            for base in (root, capture):
                (base / name).parent.mkdir(parents=True)
                (base / name).write_text(body)
            (root / 'scope.txt').write_text(name)
            inputs = capture.parent / 'capture-evidence'
            inputs.mkdir()
            (inputs / 'focused-01-inputs.json').write_text(json.dumps({name: hashlib.sha256(body.encode()).hexdigest()}))
            with self.assertRaisesRegex(ValueError, 'packaged member checksum'):
                gate.source_identity(dataset, artifacts, 'eip170', root)


if __name__ == '__main__':
    unittest.main()
