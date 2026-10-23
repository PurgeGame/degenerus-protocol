#!/usr/bin/env python3
"""Pinned production build plus ABI/layout/IR evidence for optimization comparisons."""
import argparse
import io
import json
import os
from pathlib import Path
import posixpath
import re
import subprocess
import tarfile

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--revision')
p.add_argument('--pins', type=Path)
p.add_argument('--out', type=Path, required=True)
a = p.parse_args()
a.out.mkdir(parents=True, exist_ok=True)
if a.revision:
    with tarfile.open(fileobj=io.BytesIO(subprocess.check_output(['git', 'archive', a.revision, 'contracts']))) as archive:
        sources = {m.name: {'content': archive.extractfile(m).read().decode()}
                   for m in archive.getmembers() if m.isfile() and m.name.endswith('.sol')}
else:
    sources = {str(f): {'content': f.read_text()} for f in Path('contracts').rglob('*.sol')}
if a.pins:
    sources['contracts/ContractAddresses.sol'] = {'content': a.pins.read_text()}
pending = ['test/craps/CrapsViews.sol']
while pending:
    filename = pending.pop()
    if filename in sources:
        continue
    content = (subprocess.check_output(['git', 'show', f'{a.revision}:{filename}'], text=True)
               if a.revision else Path(filename).read_text())
    sources[filename] = {'content': content}
    # The runtime used by the replay must have the revision's readers as well as
    # its production contracts; otherwise a new RNG helper contaminates the base.
    for imported in re.findall(r'import\b[^;]*?["\']([^"\']+)["\']\s*;', content):
        if imported.startswith('.'):
            dependency = posixpath.normpath(posixpath.join(posixpath.dirname(filename), imported))
            if dependency.startswith('test/') and dependency not in sources:
                pending.append(dependency)
sources['contracts/XaLayout.sol'] = {'content': '''pragma solidity 0.8.38;
import {DegenerusQuests} from "./DegenerusQuests.sol";
import {DegenerusAffiliate} from "./DegenerusAffiliate.sol";
contract XaQuestsLayout is DegenerusQuests { DegenerusQuestsStorage private probe; }
contract XaAffiliateLayout is DegenerusAffiliate {
 constructor() DegenerusAffiliate(new address[](0),new bytes32[](0),new uint8[](0),new address[](0),new bytes32[](0)) {}
 DegenerusAffiliateStorage private probe;
}
'''}
rows = json.loads(subprocess.check_output(['node', '--input-type=module', '-e',
    'import {DEPLOYMENTS} from "./scripts/lib/deploymentManifest.js"; console.log(JSON.stringify(DEPLOYMENTS))'], text=True))
names = {r['contract'] for r in rows} | {'DegenerusGameLens', 'CrapsLens', 'DegenerusVaultShare', 'CrapsViews'}
selection = {'*': {'': ['ast'], '*': ['abi', 'storageLayout', 'evm.methodIdentifiers']}}
for filename, source in sources.items():
    for name in names:
        if re.search(r'\bcontract\s+' + name + r'\b', source['content']):
            selection.setdefault(filename, {})[name] = ['abi', 'storageLayout', 'evm.methodIdentifiers',
                'evm.bytecode.object', 'evm.deployedBytecode.object',
                'evm.deployedBytecode.immutableReferences', 'irOptimized', 'metadata']
request = {'language': 'Solidity', 'sources': sources, 'settings': {
    'optimizer': {'enabled': True, 'runs': 1000}, 'viaIR': True, 'evmVersion': 'osaka',
    'remappings': ['@openzeppelin/=node_modules/@openzeppelin/', 'forge-std/=lib/forge-std/src/'],
    'outputSelection': selection}}
(a.out / 'input.json').write_text(json.dumps(request))
solc = os.environ.get('SOLC', str(Path.home() / '.svm/0.8.38/solc-0.8.38'))
version = subprocess.check_output([solc, '--version'], text=True)
assert '0.8.38+' in version, version
with (a.out / 'output.json').open('w') as output:
    subprocess.run([solc, '--base-path', '.', '--include-path', 'node_modules', '--standard-json'],
        input=json.dumps(request), text=True, stdout=output, check=True)
result = json.loads((a.out / 'output.json').read_text())
errors = [e['formattedMessage'] for e in result.get('errors', []) if e['severity'] == 'error']
if errors:
    raise SystemExit('\n'.join(errors))
contracts = {}
for filename, entries in result['contracts'].items():
    for name, artifact in entries.items():
        contracts[name] = artifact
        directory = a.out / 'artifacts' / Path(filename).name
        directory.mkdir(parents=True, exist_ok=True)
        emitted = dict(artifact)
        emitted['methodIdentifiers'] = artifact.get('evm', {}).get('methodIdentifiers', {})
        for key in ['bytecode', 'deployedBytecode']:
            if key in artifact.get('evm', {}):
                emitted[key] = dict(artifact['evm'][key], object='0x' + artifact['evm'][key]['object'])
        (directory / (name + '.json')).write_text(json.dumps(emitted))
(a.out / 'abis.json').write_text(json.dumps(contracts))
summary = {name: len(contracts[name]['evm']['deployedBytecode']['object']) // 2 for name in sorted(names)}
(a.out / 'sizes.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps({'revision': a.revision or 'working tree', 'compiler': version.strip(), 'sizes': summary}), flush=True)
