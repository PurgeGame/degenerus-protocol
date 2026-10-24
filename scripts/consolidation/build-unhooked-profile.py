#!/usr/bin/env python3
"""Build a hand-specialized EIP-170 control with ordinary fixed call boundaries.

Local calls bypass the profile hooks. Remote calls are ordinary non-virtual split
helpers. Only the deployed EIP-170 dependency closure is compiled. The generated
input is retained so the independent control can be reviewed source by source.
"""
import argparse
import json
from pathlib import Path
import posixpath
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def remove_function(source, name):
    matches = list(re.finditer(r'\bfunction\s+' + re.escape(name) + r'\s*\(', source))
    assert len(matches) == 1, (name, len(matches))
    start = matches[0].start()
    brace = source.index('{', start)
    depth, end = 1, brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[:start] + source[end:]


def executable(code):
    data = bytes.fromhex(code.removeprefix('0x'))
    tail = int.from_bytes(data[-2:], 'big') + 2
    assert tail < len(data)
    return data[:-tail]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out', type=Path, required=True)
    a = p.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    sources = {str(f): f.read_text() for f in Path('contracts').rglob('*.sol')}
    assert './eip170/Eip170Game.sol' in sources['contracts/profiles/Selected.sol']
    rows = json.loads(subprocess.check_output(['node', '--input-type=module', '-e',
        'import {PROFILES} from "./scripts/lib/deploymentProfiles.js"; console.log(JSON.stringify(PROFILES.eip170))'], text=True))
    roots = []
    for row in rows:
        matches = [file for file in sources if Path(file).stem == row['contract']]
        assert len(matches) == 1
        roots.extend(matches)
    control = dict(sources)
    replacements = []

    # These five deployed groups contain the implementation their hook selected.
    # Give the calling component that implementation and call it directly.
    file = 'contracts/modules/GameFacade.sol'
    control[file] = control[file].replace('abstract contract GameFacade is ',
        'import {GameBoonActions} from "./GameBoonActions.sol";\n\nabstract contract GameFacade is GameBoonActions, ')
    control[file] = control[file].replace('_gameConsumeActionBoon(', '_consumeActionBoon(')
    file = 'contracts/modules/GameEntryInternals.sol'
    control[file] = remove_function(control[file], '_gameConsumeActionBoon')
    file = 'contracts/profiles/eip170/Eip170Game.sol'
    control[file] = remove_function(control[file], '_gameConsumeActionBoon').replace('GameFacade, GameBoonActions', 'GameFacade')

    file = 'contracts/modules/DegenerusGameTicketModule.sol'
    control[file] = remove_function(control[file], '_ticketFoilWork')
    control[file] = control[file].replace('contract DegenerusGameTicketModule is ',
        'import {DegenerusGameFoilWorkerModule} from "./DegenerusGameFoilWorkerModule.sol";\n\ncontract DegenerusGameTicketModule is DegenerusGameFoilWorkerModule, ')
    control[file] = control[file].replace('_ticketFoilWork(', '_runFoilWork(')
    file = 'contracts/profiles/eip170/Eip170TicketFoil.sol'
    control[file] = remove_function(control[file], '_ticketFoilWork').replace(
        'DegenerusGameTicketModule, DegenerusGameFoilWorkerModule', 'DegenerusGameTicketModule')
    replacements += ['_gameConsumeActionBoon -> _consumeActionBoon', '_ticketFoilWork -> _runFoilWork']

    local = {
        'Lootbox': ('DegenerusGameLootboxModule', ['_boxResolveHumanBoxOrder', '_boxResolveAfkingBox', '_boxResolveLootboxDirect']),
        'Boon': ('DegenerusGameBoonModule', ['_boxRollBoxBoons']),
        'Degenerette': ('DegenerusGameDegeneretteModule', ['_boxResolveWwxrpSpinFromBox', '_boxResolveFlipSpinsFromBox', '_boxResolveEthSpinFromBox']),
    }
    for shell, (component, functions) in local.items():
        for function in functions:
            file = f'contracts/modules/{component}.sol'
            direct = function.replace('_box', '_localbox', 1)
            control[file] = control[file].replace(function + '(', direct + '(')
            file = f'contracts/profiles/eip170/Eip170{shell}.sol'
            control[file] = remove_function(control[file], function)
            replacements.append(function + ' -> ' + direct)

    boundary_files = ['GameEntryInternals', 'GameActionInternals', 'GameDailyInternals', 'GameBoxInternals']
    remote = set()
    for name in boundary_files:
        file = f'contracts/modules/{name}.sol'
        remote.update(re.findall(r'function\s+(\w+)\s*\(', control[file]))
        control[file] = re.sub(r'\bvirtual\b', '', control[file])
    remote.update(['_coinflipQuest', '_crapsSettleBattle', '_endgameSplitDegenesis',
                   '_degenesisPurchaseWith', '_foilPurchaseWith', '_delegateLifecycle'])
    # The lifecycle creation hook's default is the external table call in EIP-170.
    remote.update(re.findall(r'function\s+(\w+)\([^{}]*?\bvirtual\b', control['contracts/JackpotBattle.sol']))
    for file in control:
        for name in sorted(remote):
            control[file] = re.sub(r'\b' + re.escape(name) + r'\b', '_split' + name[1:], control[file])
        # Remove virtual only on the fixed split helpers, preserving unrelated
        # ERC721/adaptor extension points.
        control[file] = re.sub(r'(function\s+_split\w+\s*\([^{}]*?)\bvirtual\b', r'\1', control[file])
    replacements += sorted(name + ' -> fixed non-virtual _split' + name[1:] for name in remote)

    def closure(tree):
        selected, pending = {}, list(roots)
        while pending:
            file = pending.pop()
            if file in selected:
                continue
            source = tree[file]
            selected[file] = {'content': source}
            for dependency in re.findall(r'import\b[^;]*?["\']([^"\']+)["\']\s*;', source):
                if dependency.startswith('.'):
                    child = posixpath.normpath(posixpath.join(posixpath.dirname(file), dependency))
                    pending.append(child)
        return selected

    artifacts = {}
    for label, tree in [('profile', sources), ('unhooked', control)]:
        selected = closure(tree)
        selection = {file: {row['contract']: ['abi', 'evm.methodIdentifiers', 'evm.deployedBytecode.object',
            'evm.deployedBytecode.immutableReferences']} for file in roots for row in rows if Path(file).stem == row['contract']}
        request = dict(language='Solidity', sources=selected, settings=dict(viaIR=True,
            optimizer=dict(enabled=True, runs=1000), evmVersion='osaka',
            remappings=['@openzeppelin/=node_modules/@openzeppelin/'], outputSelection=selection))
        (a.out / f'{label}-input.json').write_text(json.dumps(request))
        with (a.out / f'{label}-output.json').open('w') as output:
            subprocess.run([str(Path.home()/'.svm/0.8.38/solc-0.8.38'), '--base-path', '.',
                '--include-path', 'node_modules', '--standard-json'], input=json.dumps(request),
                text=True, stdout=output, check=True)
        result = json.loads((a.out / f'{label}-output.json').read_text())
        errors = [e['formattedMessage'] for e in result.get('errors', []) if e['severity']=='error']
        assert not errors, '\n'.join(errors)
        artifacts[label] = {name: artifact for entries in result['contracts'].values() for name, artifact in entries.items()}
    pins = dict(re.findall(r'address internal constant (\w+)\s*=\s*address\((0x[0-9a-fA-F]+)\)', sources['contracts/ContractAddresses.sol']))
    overrides, table = {}, []
    for row in rows:
        name = row['contract']
        before = artifacts['profile'][name]['evm']['deployedBytecode']
        after = artifacts['unhooked'][name]['evm']['deployedBytecode']
        same = executable(before['object']) == executable(after['object'])
        assert artifacts['profile'][name]['abi'] == artifacts['unhooked'][name]['abi'], ('ABI changed', name)
        if after.get('immutableReferences'):
            assert same, ('Changed immutable template needs binding', name)
        else:
            overrides[pins[row['key']].lower()] = '0x' + after['object']
        table.append(dict(contract=name, byteIdenticalExecutable=same,
                          beforeBytes=len(before['object'])//2, afterBytes=len(after['object'])//2))
    (a.out / 'runtime-overrides.json').write_text(json.dumps(overrides))
    (a.out / 'comparison.json').write_text(json.dumps(dict(replacements=replacements, contracts=table), indent=2))
    print(json.dumps(dict(contracts=len(table), identical=sum(r['byteIdenticalExecutable'] for r in table))), flush=True)


if __name__ == '__main__':
    main()
