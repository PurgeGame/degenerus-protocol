# Documentation

Start at [AUDIT.md](AUDIT.md) for the audit scope, severity criteria and reading order.

## Required reading

In the order given by [AUDIT.md](AUDIT.md#read-in-this-order):

- [Audit handoff](AUDIT.md), [scope.txt](../scope.txt), [out_of_scope.txt](../out_of_scope.txt)
  and the [readiness review](AUDIT-READINESS.md)
- [FLIP and WWXRP amount units](TOKEN-UNITS.md)
- [Security](../SECURITY.md) and [Known issues](../KNOWN-ISSUES.md)
- [Architecture](ARCHITECTURE.md)
- [Accounting](ACCOUNTING.md)
- [Properties](PROPERTIES.md)
- [DGVE owner approval](OWNER_GOVERNANCE.md)
- [Randomness inputs and domain separation](audit/RNG-DOMAINS.md)
- [Build and verification](VERIFICATION.md)
- [Economic disclosures](../ECONOMIC_DISCLOSURES.md)

## Audit inputs and evidence

- [Snapshot manifest](audit/snapshot.json), [source hashes](audit/source-sha256.txt) and
  [verification-input hashes](audit/verification-sha256.txt)
- [Readiness record](audit/freeze.json)
- [Analyzer triage](audit/ANALYZER-TRIAGE.md) and [test review](TEST_REVIEW.md)

## Mechanism references

- [Architecture details](ARCHITECTURE-DETAILS.md): profile composition, lootbox queue,
  Degenesis, purchase timing, AFKing, comps, bounty, VRF funding, tickets, BAF, wallet registry,
  events, jackpot legs, foil packs, century transitions
- [Account loans, seizure, recurring collection and redemptions](ACCOUNT-LOANS.md)
- [Craps preferences and jackpot battle](CRAPS-PREFERENCES.md)
- [Decimator battle rules, settlement and ABI](DECIMATOR-BATTLE.md) ([ABI](abi/Decimator.json))
- [Degenerette bet queue](DEGENERETTE-BET-QUEUE.md)
- [Degenerette payout math](DEGENERETTE-SINGLE-SYMBOL-MATH.md)
- [Deity tickets and boon draws](DEITY-BOONS.md)
- [Deity pass customization, frontend ABI and activation](DEITY-PASS-CUSTOMIZATION.md)
  ([ABI](abi/DeityPassCustomizationRenderer.json))
- [WWXRP boons](WWXRP-BOONS.md)
- [Vault player actions, funding and access rules](VAULT_PLAYER_ACTIONS.md)
- [Retained Coinflip, BAF and affiliate storage](STORAGE-REUSE.md)
- [Profile comparison and native replay tooling](../scripts/consolidation/README.md)
- [Participant terms](../TERMS.md)

## Historical evidence

These record earlier revisions or archived artifacts and are not descriptions of the current
source; each states its scope at the top.

- [Predecessor freeze record](audit/freeze-audit-2026-10-16.json)
- [Storage-reuse implementation review](../scripts/audit/storage-reuse/REVIEW.md),
  [credit callers](../scripts/audit/storage-reuse/CALLERS.md) and
  [native gas calibration](../scripts/audit/storage-reuse/GAS-CALIBRATION.md)
- [Storage-reuse phase 2 review](../scripts/audit/storage-reuse-phase2/REVIEW.md)
- [Obsolete queue-word fixture note](../test/fixtures/QueueWordCacheReference.md)
