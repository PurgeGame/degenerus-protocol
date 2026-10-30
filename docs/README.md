# Documentation

[AUDIT.md](AUDIT.md) is the audit handoff: target, scope, assumptions, severity and source identity.
[TESTING.md](TESTING.md) gives reproducible build, test and gate commands.

## System references

| Document | Review use |
| --- | --- |
| [Architecture](ARCHITECTURE.md) | Contract boundaries, daily progression and ending |
| [Accounting](ACCOUNTING.md) | Custody, obligations and reserves |
| [Token units](TOKEN-UNITS.md) | Amount scales and rounding |
| [Module map](MODULE-MAP.md) | External entries, implementations and nested delegate routes |
| [Storage packing](STORAGE-PACKING.md) | Manual bit fields and compiler layouts |
| [Properties](PROPERTIES.md) | Critical properties and assertion locations |
| [RNG domains](audit/RNG-DOMAINS.md) | Requests, words, consumers and commitment boundaries |
| [ETH exit assurance](audit/ETH-EXIT-ASSURANCE.md) | Helper proofs, composition evidence and limits |
| [Owner governance](OWNER_GOVERNANCE.md) | DGVE escrow, delegation and execution |

## Mechanism references

| Document | Review use |
| --- | --- |
| [Architecture details](ARCHITECTURE-DETAILS.md) | Degenesis, pools, AFKing, tickets, bounty and VRF funding |
| [Account loans](ACCOUNT-LOANS.md) | Borrowing, repayment, seizure and redemptions |
| [Craps boards and jackpot battle](CRAPS-PREFERENCES.md) | Board encoding, locks and settlement |
| [Decimator battle](DECIMATOR-BATTLE.md) | Eligibility, draws and payouts |
| [Degenerette queue](DEGENERETTE-BET-QUEUE.md) | Bet packing, commitment and resolution |
| [Degenerette math](DEGENERETTE-SINGLE-SYMBOL-MATH.md) | Wild colors, scores and payout calculations |
| [Deity boons](DEITY-BOONS.md) | Perpetual entries and awards |
| [Deity display dependencies](DEITY-PASS-CUSTOMIZATION.md) | Renderer and icon authority boundaries |
| [WWXRP boons](WWXRP-BOONS.md) | Token consumption and supported applications |
| [Vault player actions](VAULT_PLAYER_ACTIONS.md) | Funding and delegated controls |
| [Retained storage](STORAGE-REUSE.md) | Ring tags, expiry and raw-reader semantics |

The owner-controlled boundaries are [Security](../SECURITY.md), [Known issues](../KNOWN-ISSUES.md),
[Economic disclosures](../ECONOMIC_DISCLOSURES.md) and [Terms](../TERMS.md).
