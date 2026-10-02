#!/usr/bin/env python3
"""Rebuild and reproduce the paired old/new 77-board calibration without rewriting history."""
import concurrent.futures
import csv
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'docs/hot-shooter-reproduction'
OUT.mkdir(exist_ok=True)
metadata = json.loads((ROOT / 'docs/CRAPS-HOT-SHOOTER-CALIBRATION-METADATA.json').read_text())
jobs = [j for j in metadata['jobs'] if j['name'] in ('production', 'candidate')]
historical = {}
for row in csv.DictReader((ROOT / 'docs/CRAPS-HOT-SHOOTER-CALIBRATION.tsv').open(), delimiter='\t'):
    experiment = row.pop('experiment')
    historical[(experiment, row['id'])] = row

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

with tempfile.TemporaryDirectory(prefix='craps-hot-calibration-') as tmp:
    binary = str(Path(tmp) / 'craps-hot')
    subprocess.run(['g++', '-O3', '-std=c++20', 'scripts/craps-hot-shooter-sim.cpp', '-o', binary], cwd=ROOT, check=True)
    validation = subprocess.check_output([binary, 'validate', '10000', '20261025'], text=True)
    def run(job):
        name = f"{job['name']}-{job['seed']}"
        output = OUT / f'{name}.tsv'
        with output.open('w') as stream:
            subprocess.run([binary] + job['args'], stdout=stream, check=True)
        rows = list(csv.DictReader(output.open(), delimiter='\t'))
        if len(rows) != 77:
            raise RuntimeError(f'{name}: expected 77 boards')
        for row in rows:
            if row != historical[(name, row['id'])]:
                raise RuntimeError(f"{name}: calibration differs for board {row['id']}")
        return {'job': job, 'file': str(output.relative_to(ROOT)), 'sha256': sha(output), 'exact_match_historical_rows': len(rows)}
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(run, jobs))
(OUT / 'metadata.json').write_text(json.dumps({
    'jobs': results, 'validation': validation.strip(),
    'source_sha256': {p: sha(ROOT / p) for p in [
        'scripts/craps-hot-shooter-sim.cpp', 'scripts/craps-high-water-system-sim.cpp', 'scripts/craps-system-sim.cpp',
    ]},
}, indent=2) + '\n')
print('All 308 paired calibration rows reproduce exactly.')
