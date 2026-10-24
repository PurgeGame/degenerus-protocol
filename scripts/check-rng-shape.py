#!/usr/bin/env python3
"""Fail closed on hash-site drift, malformed RNG preimages and duplicate action tags.

Every production hash is registered, including explicitly non-RNG storage/commitment
hashes. The companion taint/window gates cover transported words and publication.
This is a reviewed source registry, not a claim of whole-program semantic taint proof.
"""
import argparse
import json
from pathlib import Path
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent / 'lib'))
from rng_taint_extract import strip_comments_and_strings, enclosing_functions, param_list

def compact(s):
    return re.sub(r'\s+', '', s)

def scan(root):
    rows = []
    for path in sorted(root.rglob('*.sol')):
        if {'interfaces', 'mocks', 'test'} & set(path.relative_to(root).parts):
            continue
        source = path.read_text()
        masked = strip_comments_and_strings(source)
        functions = enclosing_functions(masked)
        for match in re.finditer(r'\b(keccak256|EntropyLib\.hash[1-4])\s*\(', masked):
            line = masked.count('\n', 0, match.start())
            args = param_list(masked, match.end() - 1)
            expression = source[match.start():match.end() + len(args) + 1]
            rows.append({'file': str(path.relative_to(root)), 'function': functions[line],
                         'expression': compact(expression)})
    return rows

# The one raw coinflip bit is pinned independently of the editable hash registry.
RAW_COIN_BITS = {
    'processCoinflipPayouts': 'boolwin=(rngWord&1)==1;',
}

def validate_raw_coin_bits(root, manifest):
    errors = []
    registered = {(r['file'], r['function'], r['expression']) for r in manifest.get('rawBitExceptions', [])}
    required = {('Coinflip.sol', fn, expression) for fn, expression in RAW_COIN_BITS.items()}
    if registered != required or len(manifest.get('rawBitExceptions', [])) != len(required):
        errors.append('Raw coin-bit exception registry must contain exactly the reviewed ordinary-result entry')
    source = (root / 'Coinflip.sol').read_text()
    masked = strip_comments_and_strings(source)
    for name, statement in RAW_COIN_BITS.items():
        match = re.search(r'\bfunction\s+' + name + r'\s*\(', masked)
        if not match:
            errors.append('Missing raw coin-bit consumer: ' + name)
            continue
        start = masked.index('{', match.end())
        end = start + 1
        depth = 1
        while depth and end < len(masked):
            depth += (masked[end] == '{') - (masked[end] == '}')
            end += 1
        if compact(source[start:end]).count(statement) != 1:
            errors.append('Reviewed raw coin-bit expression changed: ' + name)
    return errors

def validate(root, manifest):
    errors = validate_raw_coin_bits(root, manifest)
    source = (root / 'libraries/RngTags.sol').read_text()
    tags = dict(re.findall(r'uint256\s+internal\s+constant\s+(\w+)\s*=\s*(\d+)\s*;', source))
    declarations = re.findall(r'\bconstant\s+(\w+)\s*=', strip_comments_and_strings(source))
    if set(declarations) != set(tags) or len(declarations) != len(tags):
        errors.append('Tags must each be a named uint256 constant with an explicit numeric value')
    if not tags or len(set(map(int, tags.values()))) != len(tags) or 0 in map(int, tags.values()):
        errors.append('Tag values must be nonzero and protocol-unique')
    live = scan(root)
    registered = manifest['sites']
    key = lambda r: (r['file'], r['function'], r['expression'])
    from collections import Counter
    before, after = Counter(map(key, registered)), Counter(map(key, live))
    for item, count in (after - before).items(): errors.append(f'Unreviewed hash ({count}): {item}')
    for item, count in (before - after).items(): errors.append(f'Stale reviewed hash ({count}): {item}')
    used = set()
    for row in live:
        expression = row['expression']
        if not expression.startswith('EntropyLib.'):
            continue
        args = expression[expression.index('(') + 1:-1]
        depth = 0
        parts = []
        start = 0
        for i, char in enumerate(args):
            depth += (char == '(') - (char == ')')
            if char == ',' and depth == 0:
                parts.append(args[start:i]); start = i + 1
        parts.append(args[start:])
        tag = parts[0]
        refs = re.findall(r'RngTags\.(\w+)', tag)
        valid = bool(re.fullmatch(r'RngTags\.\w+', tag)) or bool(re.fullmatch(r'ticketLeg\?RngTags\.\w+:RngTags\.\w+', tag))
        if not valid or any(t not in tags for t in refs):
            errors.append(f'Nonconstant or unknown tag: {row}')
        used.update(refs)
        if len(parts) != int(expression[len('EntropyLib.hash')]) or not 2 <= len(parts) <= 4:
            errors.append(f'Unsupported fixed-width shape: {row}')
        # This exact Lens expression converts its issuer to a fixed wallet ID. Exempt
        # only that expression, never the other arguments of the same call.
        expected = 'issuer==ContractAddresses.VAULT?VAULT_WALLET_ID:SDGNRS_WALLET_ID'
        inspected = ','.join(p for p in parts if not (
            row['file'] == 'DegenerusGameLens.sol' and p == expected))
        if re.search(r'address\(|ContractAddresses\.|block\.|tx\.|chainid\(|blockhash\(|gasleft\(', inspected):
            errors.append(f'Forbidden deployment/block input: {row}')
    if set(tags) != used:
        errors.append(f'Unused tags: {sorted(set(tags) - used)}')
    return errors, {'tags': len(tags), 'reviewed_hash_sites': len(live), 'reviewed_raw_bit_exceptions': len(RAW_COIN_BITS)}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--contracts', type=Path, default=Path('contracts'))
    p.add_argument('--manifest', type=Path, default=Path('scripts/rng-shape-manifest.json'))
    a=p.parse_args()
    errors, summary=validate(a.contracts, json.loads(a.manifest.read_text()))
    for error in errors: print(error)
    print(json.dumps(dict(summary, status='FAIL' if errors else 'PASS')))
    return bool(errors)

if __name__ == '__main__': sys.exit(main())
