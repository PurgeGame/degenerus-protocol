# Documentation

Start at [AUDIT.md](AUDIT.md) for the audit scope, severity criteria and reading list.

Audit inputs and verification:

- [Audit handoff](AUDIT.md) and [readiness review](AUDIT-READINESS.md)
- [Snapshot manifest](audit/snapshot.json), [source hashes](audit/source-sha256.txt) and
  [verification-input hashes](audit/verification-sha256.txt)
- [Readiness record](audit/freeze.json) and the
  [predecessor freeze record](audit/freeze-audit-2026-10-16.json)
- [Build and verification](VERIFICATION.md), [analyzer triage](audit/ANALYZER-TRIAGE.md)
  and [test review](TEST_REVIEW.md)
- [Randomness inputs and domain separation](audit/RNG-DOMAINS.md)

Design and trust (repository root):
[Security](../SECURITY.md), [Economic disclosures](../ECONOMIC_DISCLOSURES.md),
[Known issues](../KNOWN-ISSUES.md), [scope.txt](../scope.txt) and
[out_of_scope.txt](../out_of_scope.txt).

Technical references:

- [Architecture and accounting](ARCHITECTURE.md)
- [FLIP and WWXRP amount units](TOKEN-UNITS.md)
- [DGVE owner approval](OWNER_GOVERNANCE.md)
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
