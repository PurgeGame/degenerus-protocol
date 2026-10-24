#!/usr/bin/env python3
"""Check selector-preserving delegate routes against the selected deployed ABI."""
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
sources = {str(p): {'content': p.read_text()} for p in Path('contracts').rglob('*.sol')}
request = {'language': 'Solidity', 'sources': sources, 'settings': {
    'outputSelection': {'*': {'': ['ast'], '*': ['evm.methodIdentifiers']}}}}
compiler = Path.home() / '.svm/0.8.38/solc-0.8.38'
run = subprocess.run([str(compiler), '--base-path', '.', '--include-path', 'node_modules', '--standard-json'],
                     input=json.dumps(request), text=True, capture_output=True, check=True)
output = json.loads(run.stdout)
errors = [e['formattedMessage'] for e in output.get('errors', []) if e['severity'] == 'error']
assert not errors, '\n'.join(errors)
rows = json.loads(subprocess.check_output(['node', '--input-type=module', '-e',
    'import {DEPLOYMENTS} from "./scripts/lib/deploymentManifest.js"; console.log(JSON.stringify(DEPLOYMENTS))'], text=True))
hosts = {alias: row['contract'] for row in rows for alias in row['aliases']}
methods = {name: artifact['evm']['methodIdentifiers'] for entries in output['contracts'].values()
           for name, artifact in entries.items()}
checked = []


def walk(node, source, function=None):
    if not isinstance(node, dict):
        return
    if node.get('nodeType') == 'FunctionDefinition':
        function = node
    if node.get('nodeType') == 'FunctionCall':
        expr = node.get('expression', {})
        args = node.get('arguments', [])
        if expr.get('name') == '_delegateLifecycle':
            assert function and 'functionSelector' in function, (source, 'unresolved lifecycle selector')
            host = hosts['CRAPS_LIFECYCLE_MODULE']
            assert function['functionSelector'] in methods[host].values(), (source, function['name'], host)
            checked.append((function['name'], 'CRAPS_LIFECYCLE_MODULE', host))
        if (expr.get('memberName') == 'delegatecall' and len(args) == 1
                and args[0].get('memberName') == 'data'
                and args[0].get('expression', {}).get('name') == 'msg'):
            target = expr.get('expression', {})
            key = target.get('memberName')
            if target.get('expression', {}).get('name') == 'ContractAddresses':
                assert function and 'functionSelector' in function, (source, 'unresolved calldata selector', key)
                host = hosts[key]
                selector = function['functionSelector']
                assert selector in methods[host].values(), (source, function['name'], key, host, selector)
                checked.append((function['name'], key, host))
    for value in node.values():
        if isinstance(value, dict):
            walk(value, source, function)
        elif isinstance(value, list):
            for child in value:
                walk(child, source, function)


for source, unit in output['sources'].items():
    walk(unit['ast'], source)
assert checked, 'No selector-preserving routes checked'
print(json.dumps({'profile': os.environ.get('PROFILE', 'eip170'), 'forwardedRoutes': checked}, indent=2))
