# Degenerus Protocol

Ethereum gambling contracts: ticket jackpots, lootboxes and passes, coinflip, craps,
Degenerette and a prize-pool growth parimutuel. ETH/stETH obligations and token credits
are accounted for separately. Contracts use fixed deployment addresses; game modules
execute by delegatecall, while craps uses a separate stateless dice engine.

**External audit: start with [the audit handoff](docs/AUDIT.md).**

| Document | Purpose |
| --- | --- |
| [Audit handoff](docs/AUDIT.md) | Exact source snapshot, scope and reading order |
| [Architecture](docs/ARCHITECTURE.md) | Contract boundaries, value flow and invariants |
| [Security and roles](SECURITY.md) | Authorities, external dependencies and reporting |
| [Known issues](KNOWN-ISSUES.md) | Accepted assumptions and disclosed limitations |
| [Economic disclosures](ECONOMIC_DISCLOSURES.md) | Creator allocations and economic rights |
| [Verification](docs/VERIFICATION.md) | Build, tests and evidence limits |

Solidity **0.8.34**, via IR, optimizer **1,000 runs**, EVM **Osaka**. Dependencies are
recorded in `package-lock.json` and `foundry.lock`; see verification instructions before
running tests that patch deployment constants.

Deployment order and contract names are authoritative in
[scripts/lib/predictAddresses.js](scripts/lib/predictAddresses.js). The pipeline predicts
addresses, patches `ContractAddresses.sol`, recompiles and deploys. Checked-in test pins
are not a production deployment manifest.

[Terms](TERMS.md) are separate from the technical audit specification.

License: [AGPL-3.0-only](LICENSE). Security contact: **burnie@degener.us**.
