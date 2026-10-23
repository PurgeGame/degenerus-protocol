#!/usr/bin/env python3
"""Pack OptNativePairs fixtures without inventing values for unobserved slots."""
import argparse
from collections import Counter
import gzip
import hashlib
import json
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('fixtures', type=Path)
p.add_argument('out', type=Path)
a = p.parse_args()
a.out.mkdir(parents=True, exist_ok=True)
codes, counts, hashes = {}, Counter(), {}
paths = sorted(a.fixtures.glob('*.call.json'), key=lambda p: int(p.name.split('.')[0]))
assert paths, 'No fixtures'
with gzip.open(a.out / 'calls.jsonl.gz', 'wt') as output:
    for path in paths:
        row = json.loads(path.read_text())
        state_path = path.with_name(path.name.replace('.call.json', '.state.json'))
        state = json.loads(state_path.read_text())
        converted = {}
        for address, account in state.items():
            address = address.lower()
            code = account.pop('code').lower()
            assert address not in codes or codes[address] == code, ('Code changed', address)
            codes[address] = code
            account['balance'] = hex(int(account['balance'], 16))
            account['nonce'] = hex(int(account['nonce'], 16))
            account['state'] = {k.lower(): v.lower() for k, v in account['state'].items()}
            converted[address] = account
        row['from_'] = row['from_'].lower()
        row['to'] = row['to'].lower()
        row['value'] = hex(int(row['value'], 16))
        row['state'] = converted
        row['success'] = None  # Native status is measured, never presumed from the fixture.
        counts[row['label']] += 1
        output.write(json.dumps(row, separators=(',', ':')) + '\n')
        hashes[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
        hashes[state_path.name] = hashlib.sha256(state_path.read_bytes()).hexdigest()
(a.out / 'codes.json').write_text(json.dumps(codes) + '\n')
(a.out / 'provenance.json').write_text(json.dumps({
    'method': 'Union of both runtime access sets at each sampled current-workload prestate; '
              'all values read again after snapshot restoration. Up to four samples per category. '
              'Native execution independently rejects any uncovered access.',
    'countsAreSampleCounts': True, 'samples': len(paths), 'labels': counts, 'sha256': hashes,
}, indent=2) + '\n')
print(json.dumps({'samples': len(paths), 'accounts': len(codes), 'labels': len(counts)}))
