# Degenerus Protocol

Ethereum gambling contracts for ticket jackpots, lootboxes, passes, coinflip, craps, Degenerette and
prize-pool growth bets. ETH/stETH obligations and token credits are separate ledgers. The audit
target is the **EIP-170 deployment profile**.

## ETH and stETH custody

| Contract | Assets and obligations |
| --- | --- |
| `DegenerusGame` | Holds ETH/stETH backing prize pools, claimable balances, prepaid AFKing, redemption reserves and Degenesis liabilities. |
| `DegenerusVault` | Holds its own ETH/stETH and tokens; also owns Game balances and Coinflip credits. DGVE and DGVF represent its separate backing pools. |
| `sDGNRS` | Holds ETH/stETH reserves, FLIP and Game claims; processes native and wrapped holder redemptions. |
| `GNRUS` | Holds its own ETH/stETH for charity allocation and token exits. |
| `DegenerusAdmin` | Receives subscription refunds and forwards native funding to the VRF coordinator. The external coordinator holds the subscription ETH. |
| `DGNRS` | Holds locked sDGNRS backing its transferable wrapper; forwards redemption proceeds. |
| Game modules | Execute against Game storage and custody through `delegatecall`; they are not separate prize-pool custodians. |
| Coinflip, CrapsBattle, Parimutuel, Quests, Affiliate, Jackpots, RecordBounty and token/NFT contracts | Track token balances, credits, eligibility or positions. Their internal credits are not separately held ETH/stETH. |

[Accounting](docs/ACCOUNTING.md) defines the backing equations and terminal allocations.

## Daily lifecycle

The public engine entry is `DegenerusGame.mineRun(uint32)`. It dispatches to `GameMiner._mineFlip`;
`mineFlip` names the internal mining chain, not another public entry. `nextMinerAction()` exposes
the next category selected from storage.

1. Daily preparation and advance select `requestDailyRng_g8190` on the RNG module.
2. Chainlink calls `rawFulfillRandomWords` on the Game; the callback stores an accepted raw word.
3. Mining calls `publishRng_g4514`, applies the daily word, and drains ticket, loan, box, bet,
   redemption and other work in resumable chunks. The callback does not run this work.
4. `runDailyPhase_g2582` advances the daily stages and, when their conditions hold, the level.
5. Timeout conditions select `runTerminalPhase`. The ending uses either a terminal jackpot or
   deterministic dead-VRF ticket claims.
6. The terminal path invokes `_handleFinalSweep` after the 30-day window measured from terminal payout
   completion. It distributes the remaining Game custody and expires other unclaimed balances.

[Architecture](docs/ARCHITECTURE.md) describes action priority, commitment boundaries and ending
rules.

## EIP-170 architecture

`DegenerusGame` inherits `Eip170Game`, which combines the `GameFacade` router and local boon
entries. Facade functions either execute locally or delegate to fixed module addresses.
`Game*Internals` contain forwarding helpers; `Game*Entries` expose worker entry points; `Eip170*`
shells compose the deployed implementations. Nested delegatecalls retain the Game's storage and
current `msg.sender`. Craps has its own storage context, a lifecycle delegate module, and a stateless
engine called externally.

The `_g<digits>` suffix is part of a Solidity function name and therefore its four-byte ABI
selector. The suffix encodes no authorization: check each implementation's guards. Interfaces and
callers must use the full name. [Module map](docs/MODULE-MAP.md) maps entry points to their
implementations; [storage packing](docs/STORAGE-PACKING.md) maps slots and bit ranges.

Profile selection happens at build time. The Glamsterdam shells and compatibility types remain
available to fixtures but are outside this audit's scope. No source directories need renaming to
follow the routing layers.

## Audit reading

| Reference | Purpose |
| --- | --- |
| [Scope](scope.txt) / [out of scope](out_of_scope.txt) | EIP-170 sources and review boundaries |
| [Audit handoff](docs/AUDIT.md) | Target, assumptions, severity and verification |
| [Security](SECURITY.md) | Authorities and external trust boundaries |
| [Known issues](KNOWN-ISSUES.md) | Owner-accepted implementation limitations |
| [Economic disclosures](ECONOMIC_DISCLOSURES.md) | Game rules and economic rights |
| [Token units](docs/TOKEN-UNITS.md) | Token scales and rounding |
| [Accounting](docs/ACCOUNTING.md) | Custody, obligations and reserves |
| [Architecture](docs/ARCHITECTURE.md) | Contract boundaries and lifecycle |
| [Documentation index](docs/README.md) | Mechanism references |

## Build and test quickstart

CI uses Node.js 20, Python 3.12 and Foundry with Solidity 0.8.38. Run from the repository root;
install dependencies in your own checkout. The compiler settings are via IR, 1,000 optimizer runs
and Osaka.

```sh
npm ci
git submodule update --init --recursive
export AUDIT_SCRATCH="${TMPDIR:-/tmp}/degenerus-audit-build"
mkdir -p "$AUDIT_SCRATCH"
export FOUNDRY_CACHE_PATH="$AUDIT_SCRATCH/cache"
export FOUNDRY_OUT="$AUDIT_SCRATCH/out"
sha256sum -c docs/audit/source-sha256.txt
PROFILE=eip170 node scripts/select-profile.js --no-pins
node scripts/select-profile.js --check
python3 scripts/test-foundry-groups.py --file test/unit/EthLedgerProductionReplay.t.sol \
  --log-dir "$AUDIT_SCRATCH/logs/smoke" --threads 1
python3 scripts/check-docs.py
```

The sliced runner restores address pins and profile sources.
[Testing](docs/TESTING.md) covers production builds, all test groups and structural gates.

License: [AGPL-3.0-only](LICENSE). [Terms](TERMS.md). Security contact: **burnie@degener.us**.
