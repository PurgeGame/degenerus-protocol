#!/usr/bin/env python3
"""Run strict profile parity in isolated copies with common state-owner addresses.

Production deployments use contiguous CREATE nonces. This proof alone aligns each
Glamsterdam group's nonce with its EIP-170 alias, making address-keyed state and
entropy byte-comparable. It keeps the actual selected shells and call boundaries.
Namespaced Quests/Affiliate storage and emitters retain their logical identities.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--out', type=Path, required=True)
p.add_argument('--work-root', type=Path, required=True)
p.add_argument('--forge-runner', type=Path, required=True,
               help='Authorized forge-slot.sh wrapper: WORKTREE TEST_FILE...')
a = p.parse_args()
a.out = a.out.resolve()
a.work_root = a.work_root.resolve()
a.forge_runner = a.forge_runner.resolve()
a.out.mkdir(parents=True, exist_ok=True)
a.work_root.mkdir(parents=True, exist_ok=True)
# Freeze one source revision before either profile runs. A long first replay
# must not cause the second profile to pick up concurrent workspace edits.
snapshot_context = tempfile.TemporaryDirectory(prefix='source-', dir=a.work_root)
snapshot = Path(snapshot_context.name)
for directory in ('contracts', 'test', 'scripts'):
    shutil.copytree(ROOT / directory, snapshot / directory)
shutil.copyfile(ROOT / 'foundry.toml', snapshot / 'foundry.toml')
logs = []
abis = {}
for profile in ('eip170', 'glamsterdam'):
    work = a.work_root / profile
    marker = work / '.profile-differential-copy'
    if not work.exists():
        subprocess.run(['git', 'worktree', 'add', '--detach', str(work), 'HEAD'], cwd=ROOT, check=True)
        marker.write_text(str(ROOT))
    assert marker.is_file() and marker.read_text() == str(ROOT), f'Not an owned proof copy: {work}'
    for directory in ('contracts', 'test', 'scripts'):
        shutil.rmtree(work / directory)
        shutil.copytree(snapshot / directory, work / directory)
    shutil.copyfile(snapshot / 'foundry.toml', work / 'foundry.toml')
    if not (work / 'node_modules').exists():
        (work / 'node_modules').symlink_to(ROOT / 'node_modules', target_is_directory=True)
    subprocess.run(['git', 'submodule', 'update', '--init', 'lib/forge-std'], cwd=work, check=True)
    manifest = work / 'scripts/lib/deploymentManifest.js'
    source = manifest.read_text()
    old = 'export const DEPLOYMENTS = PROFILES[PROFILE];'
    assert source.count(old) == 1, 'Manifest proof adapter needs review'
    source = source.replace(old, '''export const DEPLOYMENTS = PROFILES[PROFILE].map(row => {
  const nonceOffset = PROFILES.eip170.findIndex(ref => ref.aliases.includes(row.key));
  if (nonceOffset < 0) throw new Error(`No common pin for ${row.key}`);
  return {...row, nonceOffset};
});''')
    manifest.write_text(source)
    generator = work / 'scripts/consolidation/generate-fixtures.js'
    source = generator.read_text()
    old = '  for (const row of DEPLOYMENTS) {'
    assert source.count(old) == 1, 'Fixture proof adapter needs review'
    generator.write_text(source.replace(old, old + '\n    lines.push(`        vm.setNonce(address(this), ${5 + row.nonceOffset});`);'))
    env = dict(os.environ, PROFILE=profile, FOUNDRY_PROFILE='consolidation', FOUNDRY_ISOLATE='false')
    with (a.out / f'{profile}-driver.log').open('w') as log:
        subprocess.run([str(a.forge_runner), str(work), 'test/differential/ConsolidationReplay.t.sol'],
                       cwd=work, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    summaries = sorted((work / '.pin-logs').glob('*/summary.json'))
    assert summaries, 'Wrapper must retain .pin-logs/summary.json evidence'
    summary = json.loads(summaries[-1].read_text())
    assert len(summary) == 1 and summary[0]['exit_code'] == 0, summary
    assert summary[0]['failed'] == 0, 'Profile replay or an imported helper suite failed'
    replay_log = work / '.pin-logs' / summary[0]['log']
    # Foundry also executes imported helper suites. Pin the actual replay suite,
    # rather than mistaking the aggregate helper count for the scenario count.
    active = False
    replay_passes = 0
    with replay_log.open() as stream:
        for line in stream:
            if line.startswith('Ran ') and ' tests for ' in line:
                active = line.strip() == ('Ran 11 tests for '
                    'test/differential/ConsolidationReplay.t.sol:ConsolidationReplayTest')
            elif active and line.startswith('[PASS]'):
                replay_passes += 1
    assert replay_passes == 11, f'Expected all 11 replay scenarios, saw {replay_passes}'
    logs.append(str(replay_log))
    if profile == 'eip170':
        for file in (work / 'forge-out').glob('*/*.json'):
            artifact = json.loads(file.read_text())
            if 'abi' in artifact:
                abis[file.stem] = {'abi': artifact['abi']}
assert abis, 'Missing replay ABIs'
abi_file = a.out / 'abis.json'
abi_file.write_text(json.dumps(abis))
cmd = ['node', '--max-old-space-size=10000', 'scripts/consolidation/compare-replay.js',
       *logs, str(abi_file), str(a.out / 'differential.json'), '--profiles']
(a.out / 'comparison-command.json').write_text(json.dumps(cmd, indent=2))
subprocess.run(cmd, cwd=ROOT, check=True)
