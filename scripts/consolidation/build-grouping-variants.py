#!/usr/bin/env python3
"""Compile reviewable grouping alternatives without changing production sources."""
import argparse, copy, importlib.util, json, re, subprocess
from pathlib import Path

spec = importlib.util.spec_from_file_location('census', Path(__file__).with_name('native-profile-census.py'))
c = importlib.util.module_from_spec(spec); spec.loader.exec_module(c)


def compile_input(request, directory, label):
    (directory / f'{label}-input.json').write_text(json.dumps(request))
    with (directory / f'{label}-output.json').open('w') as output:
        subprocess.run([str(Path.home()/'.svm/0.8.38/solc-0.8.38'), '--base-path', '.', '--include-path', 'node_modules', '--standard-json'],
                       input=json.dumps(request), text=True, stdout=output, check=True)
    result = json.loads((directory / f'{label}-output.json').read_text())
    errors = [e['formattedMessage'] for e in result.get('errors', []) if e['severity']=='error']
    assert not errors, '\n'.join(errors)
    return result


def immutable_names(output):
    names = {}
    def visit(node, scope):
        if isinstance(node, dict):
            if node.get('nodeType') == 'ContractDefinition': scope = node['name']
            if node.get('nodeType') == 'VariableDeclaration' and node.get('mutability') == 'immutable':
                names[str(node['id'])] = (scope, node['name'])
            for value in node.values(): visit(value, scope)
        elif isinstance(node, list):
            for value in node: visit(value, scope)
    for source in output['sources'].values(): visit(source.get('ast', {}), '')
    return names


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--baseline', type=Path, required=True)
    p.add_argument('--dataset', type=Path, required=True)
    p.add_argument('--artifacts', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    a=p.parse_args(); a.out.mkdir(parents=True, exist_ok=True)
    request=json.loads((a.baseline/'profile-input.json').read_text())
    old=json.loads((a.baseline/'profile-output.json').read_text())
    old_contracts={name:value for group in old['contracts'].values() for name,value in group.items()}
    ast_request=copy.deepcopy(request); ast_request['settings']['outputSelection']={'*':{'':['ast']}}
    old_names=immutable_names(compile_input(ast_request,a.out,'baseline-ast'))
    codes, names, inverse=c.load_dataset(a.dataset,a.artifacts)
    pins=dict(re.findall(r'address internal constant (\w+)\s*=\s*address\((0x[0-9a-fA-F]+)\)',request['sources']['contracts/ContractAddresses.sol']['content']))
    rows=json.loads(subprocess.check_output(['node','--input-type=module','-e',
        'import {PROFILES} from "./scripts/lib/deploymentProfiles.js"; console.log(JSON.stringify(PROFILES.eip170))'],text=True))
    for variant in ['qa-delegate']:
        tree=copy.deepcopy(request)
        addresses=tree['sources']['contracts/ContractAddresses.sol']['content']
        for key in ['QUESTS','AFFILIATE']:
            addresses=re.sub(r'(address internal constant '+key+r'\s*=\s*address\()[^)]+',r'\g<1>'+pins['COINFLIP'],addresses)
        tree['sources']['contracts/ContractAddresses.sol']['content']=addresses
        quest_selectors=old_contracts['Eip170Quests']['evm']['methodIdentifiers'].values()
        affiliate_selectors=old_contracts['Eip170Affiliate']['evm']['methodIdentifiers'].values()
        coin_selectors=old_contracts['Coinflip']['evm']['methodIdentifiers'].values()
        # Existing public constants may overlap; their values must remain equal.
        shared=set(quest_selectors)&set(affiliate_selectors)
        allowed={'supportsInterface(bytes4)'}
        print('overlapping QA selectors',sorted(shared),flush=True)
        conditions=' || '.join('msg.sig == 0x'+selector for selector in sorted(set(quest_selectors)-set(coin_selectors)))
        router='''
    fallback() external {
        address target = CONDITION ? QUEST : AFFILIATE;
        assembly ("memory-safe") {
            let data := mload(0x40)
            calldatacopy(data, 0, calldatasize())
            let ok := delegatecall(gas(), target, data, calldatasize(), 0, 0)
            returndatacopy(data, 0, returndatasize())
            if iszero(ok) { revert(data, returndatasize()) }
            return(data, returndatasize())
        }
    }
'''.replace('CONDITION',conditions).replace('QUEST',pins['QUESTS']).replace('AFFILIATE',pins['AFFILIATE'])
        file='contracts/profiles/eip170/Eip170Coinflip.sol'
        tree['sources'][file]['content']=tree['sources'][file]['content'].rsplit('}',1)[0]+router+'}\n'
        tree['settings']['outputSelection']['*']={'':['ast']}
        new=compile_input(tree,a.out,variant)
        new_names=immutable_names(new)
        new_contracts={name:value for group in new['contracts'].values() for name,value in group.items()}
        runtimes={}; sizes=[]
        for row in rows:
            name=row['contract']; address=pins[row['key']].lower()
            before=old_contracts[name]['evm']['deployedBytecode']; after=new_contracts[name]['evm']['deployedBytecode']
            old_data=bytearray.fromhex(before['object']); live=bytes.fromhex(codes[address].removeprefix('0x'))
            values={}
            for key, locations in before.get('immutableReferences',{}).items():
                pieces=[live[x['start']:x['start']+x['length']] for x in locations]
                assert all(value==pieces[0] for value in pieces)
                values[old_names[key]]=pieces[0]
                for loc in locations: old_data[loc['start']:loc['start']+loc['length']]=pieces[0]
            # Metadata may differ with fixture-only wrappers; executable code must match.
            def executable(raw): return raw[:-int.from_bytes(raw[-2:],'big')-2]
            assert executable(old_data)==executable(live), ('baseline runtime mismatch',name)
            bound=bytearray.fromhex(after['object'])
            for key, locations in after.get('immutableReferences',{}).items():
                value=values[new_names[key]]
                for loc in locations:
                    assert len(value)==loc['length']
                    bound[loc['start']:loc['start']+loc['length']]=value
            runtimes[address]='0x'+bound.hex()
            sizes.append(dict(contract=name,runtimeBytes=len(bound),fitsEip170=len(bound)<=24576))
        (a.out/f'{variant}-runtimes.json').write_text(json.dumps(runtimes))
        (a.out/f'{variant}-mapping.json').write_text(json.dumps({pins[key].lower():pins['COINFLIP'].lower() for key in ['QUESTS','AFFILIATE']}))
        (a.out/f'{variant}-sizes.json').write_text(json.dumps(sizes,indent=2))
        print(variant,[(x['contract'],x['runtimeBytes']) for x in sizes if not x['fitsEip170']],flush=True)

if __name__=='__main__': main()
