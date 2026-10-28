import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import tomllib
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('storage_reuse_mutations', ROOT / 'scripts/audit/mutate-storage-reuse.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


def result(name='selected()', status='Success', reason=None):
    return json.dumps({'Selected.t.sol:Test': {'test_results': {
        name: {'status': status, 'reason': reason}}}})


class StorageReuseMutationTest(unittest.TestCase):
    def test_process_group_scan_skips_unreadable_unrelated_processes(self):
        denied = mock.MagicMock()
        denied.name = '100'
        (denied / 'stat').read_text.side_effect = PermissionError('unrelated process')
        readable = mock.MagicMock()
        readable.name = '101'
        (readable / 'stat').read_text.return_value = '101 (compiler) S 1 42 0'
        with mock.patch.object(runner, 'Path') as proc:
            proc.return_value.is_dir.return_value = True
            proc.return_value.iterdir.return_value = [denied, readable]
            self.assertTrue(runner.process_group_running(42))
            (readable / 'stat').read_text.return_value = '101 (compiler) Z 1 42 0'
            self.assertFalse(runner.process_group_running(42))

    def test_disposable_config_only_adds_read_access_to_its_artifacts(self):
        original = (ROOT / 'foundry.toml').read_text()
        expected = tomllib.loads(original)
        expected['profile']['default']['fs_permissions'].append(
            {'access': 'read', 'path': './forge-out-mutations'})
        self.assertEqual(tomllib.loads(runner.mutation_configuration(original)), expected)
        with self.assertRaises(ValueError):
            runner.mutation_configuration('unexpected configuration')

    def test_every_current_mutation_targets_a_unique_production_anchor(self):
        self.assertEqual(runner.SOURCE, 'contracts/modules/CoinflipCore.sol')
        runner.validate_anchors((ROOT / runner.SOURCE).read_text(), runner.mutations())
        self.assertEqual(len(runner.mutations()), 8)

    def test_missing_or_repeated_anchor_is_rejected_before_mutation(self):
        mutation = [('bad', 'test.sol', 'selected', 'anchor', 'changed')]
        for source in ('other', 'anchor anchor'):
            with self.assertRaises(ValueError):
                runner.validate_anchors(source, mutation)

    def test_noop_or_duplicate_mutation_name_is_rejected(self):
        for mutations in ([('bad', 'test.sol', 'selected', 'x', 'x')],
                          [('same', 'test.sol', 'selected', 'x', 'z'),
                           ('same', 'test.sol', 'selected', 'y', 'z')]):
            with self.assertRaises(ValueError):
                runner.validate_anchors('x y', mutations)

    def test_only_exact_named_success_is_a_baseline(self):
        self.assertTrue(runner.classify_result(result(), 'selected', 0)['passed'])
        self.assertFalse(runner.classify_result(result(name='other()'), 'selected', 0)['passed'])
        self.assertFalse(runner.classify_result(result(), 'selected', 1)['passed'])
        self.assertFalse(runner.classify_result(result(status='Skipped'), 'selected', 0)['passed'])

    def test_only_exact_named_assertion_failure_is_a_kill(self):
        text = result(status='Failure', reason='assertion failed: 1 != 2')
        self.assertTrue(runner.classify_result(text, 'selected', 1)['killed'])
        self.assertFalse(runner.classify_result(text, 'other', 1)['killed'])
        self.assertFalse(runner.classify_result(text, 'selected', 0)['killed'])
        self.assertFalse(runner.classify_result(text, 'selected', -9)['killed'])

    def test_custom_assertion_requires_exact_expected_prefix_and_numeric_difference(self):
        text = result(status='Failure', reason='spill marker survives merge: 0 != 144')
        self.assertFalse(runner.classify_result(text, 'selected', 1)['killed'])
        self.assertTrue(runner.classify_result(text, 'selected', 1, 'spill marker survives merge')['killed'])
        self.assertFalse(runner.classify_result(text, 'selected', 1, 'other label')['killed'])
        self.assertFalse(runner.classify_result(
            result(status='Failure', reason='arbitrary revert: 0 != 144'), 'selected', 1)['killed'])

    def test_compile_setup_empty_and_unrelated_failures_do_not_count(self):
        samples = [
            'Error: Compiler run failed\n[FAIL: assertion failed] selected()',
            '{}',
            result(name='setUp()', status='Failure', reason='assertion failed'),
            result(status='Failure', reason='EvmError: Revert'),
            result(status='Failure', reason='EvmError: OutOfGas'),
            result(status='Failure', reason='panic: arithmetic underflow or overflow (0x11)'),
            result(status='Failure', reason={'unexpected': 'value'}),
            '[]',
        ]
        for text in samples:
            with self.subTest(text=text):
                outcome = runner.classify_result(text, 'selected', 1)
                self.assertFalse(outcome['passed'])
                self.assertFalse(outcome['killed'])

    def test_extra_test_results_cannot_hide_a_fixture_failure(self):
        data = json.loads(result(status='Failure', reason='assertion failed'))
        data['Selected.t.sol:Other'] = {'test_results': {'setUp()': {
            'status': 'Failure', 'reason': 'assertion failed'}}}
        self.assertFalse(runner.classify_result(json.dumps(data), 'selected', 1)['killed'])

    def test_timeout_stops_compiler_process_group_before_returning(self):
        # A simulated forge process launches a simulated solc child. Both must
        # stop before the caller's finally block can restore a mutated source.
        code = ('import subprocess,sys,time; '
                'p=subprocess.Popen([sys.executable,"-c",'
                '"import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(60)"]); '
                'print(p.pid,flush=True); time.sleep(60)')
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'child.pid'
            with output.open('w') as out:
                with self.assertRaises(subprocess.TimeoutExpired):
                    runner.run_child([sys.executable, '-c', code], cwd=folder,
                                     env=os.environ.copy(), stdout=out,
                                     stderr=subprocess.DEVNULL, timeout=1)
            child = int(output.read_text())
            stat = Path(f'/proc/{child}/stat')
            if stat.exists():
                # An orphan zombie has terminated and cannot read restored sources.
                self.assertEqual(stat.read_text().split()[2], 'Z')

    def test_normal_wrapper_exit_stops_compiler_process_group_before_returning(self):
        code = ('import json,os,subprocess,sys; '
                'p=subprocess.Popen([sys.executable,"-c",'
                '"import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); '
                "print('ready',flush=True); time.sleep(60)" +
                '"],stdout=subprocess.PIPE,text=True); '
                'p.stdout.readline(); print(json.dumps({"wrapper":os.getpid(),"child":p.pid}),flush=True); '
                'sys.exit(int(sys.argv[1]))')
        for exit_code in (0, 7):
            with self.subTest(exit_code=exit_code), tempfile.TemporaryDirectory() as folder:
                output = Path(folder) / 'child.json'
                try:
                    with output.open('w') as out:
                        actual = runner.run_child([sys.executable, '-c', code, str(exit_code)],
                                                  cwd=folder, env=os.environ.copy(), stdout=out,
                                                  stderr=subprocess.DEVNULL, timeout=5)
                    self.assertEqual(actual, exit_code)
                    ids = json.loads(output.read_text())
                    self.assertFalse(runner.process_group_running(ids['wrapper']),
                                     'compiler still running when source restoration may begin')
                finally:
                    if output.exists() and output.read_text():
                        try:
                            os.killpg(json.loads(output.read_text())['wrapper'], signal.SIGKILL)
                        except ProcessLookupError:
                            pass


if __name__ == '__main__':
    unittest.main()
