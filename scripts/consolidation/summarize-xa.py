#!/usr/bin/env python3
"""Summarize completed Lane A evidence; fail if a required gate is not green."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--out', type=Path, default=Path('.planning/consolidation/xa/final'))
a = p.parse_args()

def read(name):
    return json.loads((a.out / name).read_text())

def sha(path):
    return hashlib.file_digest(path.open('rb'), 'sha256').hexdigest()

tests = {}
for name in ['focused', 'candidate-acceptance', 'replay-baseline-initialized',
             'native-miner-fixture', 'hardhat', 'deploy-tests']:
    rows = [json.loads(line) for line in (a.out / (name + '.log')).read_text().splitlines()
            if line.startswith('{')]
    assert rows and all(r['exit_code'] == 0 and r['failed'] == 0 for r in rows), name
    tests[name] = [{k: r[k] for k in ['run_id', 'passed', 'failed', 'skipped', 'pending'] if k in r}
                   for r in rows]
supplementary = next(json.loads(line) for line in (a.out / 'supplementary.log').read_text().splitlines()
                     if line.startswith('{'))
assert supplementary['passed'] == 325 and supplementary['failed'] == 2 and supplementary['skipped'] == 1
tests['supplementary'] = {
    'run_id': supplementary['run_id'], 'passed': 325, 'failedOnFirstRun': 2, 'skipped': 1,
    'correctedAndPassedIn': tests['candidate-acceptance'][0]['run_id'],
    'corrections': ['Terminal Affiliate fixture now enters the deadman state before claim.',
                    'BAF storage-footprint accounting deduplicates the aliased host account.'],
    'skip': 'testFuzz_FoilMatchesArchivedRuntime: optional archived runtime is absent.'}

comparison = read('replay-comparison.json')
assert comparison['differences'] == []
assert all(v in ['PASS', 'DETECTED'] for v in comparison['proofs'].values())
long = next(r for r in comparison['runs'] if r['identity'].endswith('/testLongRunCensus'))
gas = {}
for payer in ['protocol', 'player']:
    before = sum(x['gas'] for x in long['baselineGas'].values() if x['payer'] == payer)
    after = sum(x['gas'] for x in long['candidateGas'].values() if x['payer'] == payer)
    gas[payer] = {'baseline': before, 'candidate': after, 'delta': after-before}

sizes = read('sizes.json')
assert not sizes['memory_guard']['errors']
assert all(r['runtime_remaining'] >= 0 and r['initcode_remaining'] >= 0 for r in sizes['rows'])
host = next(r for r in sizes['rows'] if r['key'] == 'COINFLIP')
guard = next(r for r in sizes['memory_guard']['rows'] if r['key'] == 'COINFLIP')
assert guard['entry_pointer'] <= 0x160
no_spill = read('no-spill-output.json')
no_spill_errors = [e['formattedMessage'] for e in no_spill.get('errors', []) if e['severity'] == 'error']
assert no_spill_errors and all('YulException' in e for e in no_spill_errors)

layout = read('layout-proof.json')
assert all(v['recursiveMemberParity'] for v in layout['namespaces'].values())
assert len(layout['unchangedLayouts']) == 67 and len(layout['rewardPaths']) == 12
native = read('native-gas.json')
assert len(native['cases']) == 28 and all(r['returnAndOrderedLogs'] == 'PASS' for r in native['cases'])
assert sum(r['targetKind'] == 'production entry' for r in native['cases']) == 27
miners = [r for r in native['cases'] if 'miner' in r]
assert len(miners) == 2 and all(r['miner']['rewardFormula'] == 'PASS' for r in miners)
assert any(r['miner']['rewardFlip'] > 0 for r in miners)
deployment = read('native/deployment/complete.json')
assert deployment['stage'] == 'complete' and deployment['deployed'] == 25 and deployment['purchases'] == 4
address = read('address-proof.json')
assert address['changedAliases'] == ['COINFLIP', 'QUESTS'] and address['reservedNonces'] == [6, 10]
for source in Path('contracts').rglob('*.sol'):
    if source.name != 'ContractAddresses.sol':
        assert source.read_bytes() == (a.out / 'native/deployment' / source).read_bytes(), str(source)

# Compiler metadata is checked separately by check-deployment-sizes.js. Preserve
# hashes for every production source and all changed implementation/test tooling.
changed = subprocess.check_output(['git', 'diff', '--name-only', address['base']], text=True).splitlines()
untracked = subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard'], text=True).splitlines()
files = sorted(set(str(f) for f in Path('contracts').rglob('*.sol')) | set(changed + untracked))
sources = {f: sha(Path(f)) for f in files if Path(f).is_file() and not f.startswith('.planning/')}
(a.out / 'source-provenance.json').write_text(json.dumps(sources, indent=2) + '\n')
verification = {
    'status': 'PASS', 'base': address['base'], 'compiler': '0.8.38; viaIR; optimizer runs 1000; Osaka bytecode',
    'host': host, 'hostMemoryGuard': guard['entry_pointer_hex'], 'lowerSpillAttempt': no_spill_errors,
    'namespaceProof': layout['namespaces'], 'unchangedLayouts': len(layout['unchangedLayouts']),
    'rewardEntryPoints': list(layout['rewardPaths']), 'tests': tests,
    'differential': {'differences': 0, 'runs': len(comparison['runs']),
                     'transactions': sum(r['transactions'] for r in comparison['runs']),
                     'checkpoints': sum(r['checkpoints'] for r in comparison['runs']),
                     'mutationChecks': comparison['proofs']},
    'longRunOsakaExecutionGas': gas, 'deploymentCostModel': read('deployment-cost-model.json')['deploymentModelDelta'],
    'native': {'client': native['client'], 'cases': len(native['cases']), 'miners': miners, 'deployment': deployment},
    'addresses': address, 'sourceProvenance': 'source-provenance.json',
    'deferred': ['Whole repository unit/invariant/statistical/fork suites',
                 'Combined Lane A + Lane B integration acceptance',
                 'External simulator/indexer end-to-end receipts',
                 'Native Glamsterdam full-lifecycle gas census',
                 'Optional absent archived foil runtime comparison']}
(a.out / 'verification.json').write_text(json.dumps(verification, indent=2) + '\n')
manifest = []
for path in sorted(a.out.rglob('*')):
    if not path.is_file() or 'attempts' in path.parts or path.name == 'MANIFEST.sha256':
        continue
    manifest.append(f'{sha(path)}  {path.relative_to(a.out)}')
(a.out / 'MANIFEST.sha256').write_text('\n'.join(manifest) + '\n')
print(json.dumps({'status': 'PASS', 'hostBytes': host['runtime_bytes'], 'differential': verification['differential'],
                  'nativeCases': len(native['cases']), 'longRunOsakaExecutionGas': gas}, indent=2))
