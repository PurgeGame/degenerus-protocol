#!/usr/bin/env python3
"""Apply the call-traffic calibration to only P1's actual eliminated edges.

Input is the call-traffic report's raw edges.json. Keep protocol-paid and player-paid
rows separate; modeled call savings are not measured transaction receipts.
"""
import argparse, collections, hashlib, json, math, re
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('traffic', type=Path)
p.add_argument('calibration', type=Path)
p.add_argument('comparison', type=Path)
p.add_argument('output', type=Path)
p.add_argument('--run-index', type=int, default=0,
               help='index of the long-run scenario in the comparison report')
a = p.parse_args()
raw = a.traffic.read_bytes()
data = json.loads(raw)
fits = json.loads(a.calibration.read_text())['fits']
functions = {'purchase', 'borrow', 'repay', 'createSmurf', 'raiseSmurfBaseAllowance',
             'sweepAccounts', 'redeemFlip', 'withdrawAfkingFunding'}
hooks = {'registerWallet', 'registerWalletIdentity', 'recordAfkingSecondary', 'floorAfkingStreakBase'}

def internal(edge):
    caller, callee = edge.get('caller'), edge.get('callee')
    fn = edge.get('signature', '').split('(')[0]
    if edge.get('class') != 'ordinary': return False
    return ((caller == 'Game' and callee == 'Mint' and fn in functions)
        or (caller == 'Game' and callee in ('Ticket', 'Afking') and fn in hooks)
        or (caller == 'Mint' and callee == 'Boon' and fn == 'consumePurchaseBoost')
        or (caller == 'Mint' and callee == 'Lootbox' and fn in ('beginBoxOrder', 'applyBoxOrderScore'))
        or (caller == 'Mint' and callee == 'Mint' and fn == 'purchaseWith')
        or (caller == 'Mint' and callee == 'Game' and fn == 'livenessTriggered'))

def estimate(tx, candidate):
    warm = {tx['sender'], tx['target_name'], *('0x'+format(i,'040x') for i in range(1,18))}
    frames = {}; cold = removed = 0; frame_gas = 0
    for edge in tx['accesses']:
        if edge['kind'] == 'Resume': continue
        depth = edge['depth']
        for d in sorted([d for d in frames if d >= depth], reverse=True):
            saved, reverted = frames.pop(d)
            parent_reverted = frames.get(d-1, (None, not tx['ok']))[1]
            if reverted and not parent_reverted: warm = saved
        target = edge['callee']
        if candidate and edge.get('caller') == 'Degenesis' and target == 'Mint' and edge.get('signature','').startswith('purchase('):
            target = 'Game'  # This delegate frame is retained, with the six-argument adapter.
        eliminated = candidate and internal(edge)
        if not eliminated:
            cold += target not in warm; warm.add(target)
        if 'class' in edge:
            if eliminated:
                words = math.ceil(max(0,edge['input_bytes']-4)/32) + edge['output_words']
                family = 'dynamic' if '[]' in edge['signature'] or re.search(r'\b(bytes|string)(,|\))',edge['signature']) else 'static'
                fit = fits[family]
                frame_gas += max(100, fit['fixed'] + fit['per_word'] * words); removed += 1
            frames[depth] = (set(warm), edge['reverted'])
    return cold, removed, frame_gas

rows = collections.defaultdict(collections.Counter)
for tx in data['transactions']:
    if tx['scenario'] != 'longrun': continue
    b, _, _ = estimate(tx, False); c, removed, forwarding = estimate(tx, True)
    row = rows[(tx['payer'],tx['label'])]
    row['count'] += 1; row['removed_edges'] += removed; row['cold_touches_saved'] += b-c
    row['modeled_forwarding_saving'] += forwarding
    row['modeled_osaka_saving'] += (b-c)*2500 + forwarding
    row['modeled_glamsterdam_saving'] += (b-c)*2900 + forwarding
comparison = json.loads(a.comparison.read_text())['runs'][a.run_index]
for (payer,label),row in rows.items():
    b = comparison['baselineGas'][label]; c = comparison['candidateGas'][label]
    assert b['count'] == row['count'] == c['count'], label
    row['measured_baseline_execution'] = b['gas']; row['measured_candidate_execution'] = c['gas']
    row['measured_execution_saving'] = b['gas']-c['gas']
totals = {}
for payer in ['player','protocol']:
    total = collections.Counter()
    for (kind,label),row in rows.items():
        if kind == payer: total.update(row)
    totals[payer] = dict(total)
report = {'traffic_sha256':hashlib.sha256(raw).hexdigest(), 'calibration':fits,
          'method':'P1-only edge removal; retained Foil->Mint adapter and Degenesis->Game delegate frame; ordered account warmth with reverted-frame rollback; forwarding fit is a model, execution totals are instrumented Osaka measurements.',
          'totals':totals, 'rows':[dict(payer=k[0],label=k[1],**v) for k,v in sorted(rows.items())]}
a.output.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(totals,indent=2))
