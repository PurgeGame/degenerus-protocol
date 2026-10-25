# Degenerus Protocol

Ethereum gambling contracts: ticket jackpots, lootboxes and passes, coinflip, craps,
Degenerette and a prize-pool growth parimutuel. ETH/stETH obligations and token credits
are accounted for separately. Contracts use fixed deployment addresses; game modules
execute by delegatecall, while craps uses a separate stateless dice engine.

**External audit: use tag `audit-2026-10-25` and start with [the audit handoff](docs/AUDIT.md).**
The [freeze record](docs/audit/freeze.json) identifies the tested inputs, their hashes and verification limits.

| Document | Purpose |
| --- | --- |
| [Audit handoff](docs/AUDIT.md) | Exact source snapshot, scope and reading order |
| [Token units](docs/TOKEN-UNITS.md) | Whole-token FLIP/WWXRP APIs and rounding rules |
| [Architecture](docs/ARCHITECTURE.md) | Contract boundaries, value flow and invariants |
| [DGVE owner approval](docs/OWNER_GOVERNANCE.md) | Escrow, voting delegation, admin actions and icon bootstrap |
| [Security and roles](SECURITY.md) | Authorities, external dependencies and reporting |
| [Known issues](KNOWN-ISSUES.md) | Accepted assumptions and disclosed limitations |
| [Economic disclosures](ECONOMIC_DISCLOSURES.md) | Creator allocations and economic rights |
| [Verification](docs/VERIFICATION.md) | Build, tests and known verification limits |

Solidity **0.8.38**, via IR, optimizer **1,000 runs**, EVM **Osaka**. Dependencies are
recorded in `package-lock.json` and `foundry.lock`; see verification instructions before
running tests that patch deployment constants.

## Build profiles and deployment set

One source tree compiles to two deployment profiles. The profile is a compile-time choice
(`PROFILE`, default `eip170`); no profile flag exists on chain. `node scripts/select-profile.js`
regenerates the files that depend on it (`contracts/profiles/Selected.sol`, `contracts/Coinflip.sol`,
`deployments/<profile>.json` and the test helpers); `--check` verifies they are current.

| Profile | Role | Deployment entries | Runtime / initcode limit |
| --- | --- | --- | --- |
| `eip170` (`contracts/profiles/eip170`) | Deployment and primary audit target | 37 | 24,576 / 49,152 bytes |
| `glamsterdam` (`contracts/profiles/glamsterdam`) | Maintained alternate that folds the workers into larger deployments | 21 | 65,536 / 131,072 bytes (EIP-7954) |

Shared logic lives in `contracts/modules` (`GameFacade`, `GameActions`, `GamePurchase`,
`GameMiner`, `CoinflipCore`, `CrapsBattleCore` and the delegatecall workers) and
`contracts/storage`; the profile shells only choose which components share a deployment.
The order and aliases of each deployment sequence are authoritative in
[scripts/lib/deploymentProfiles.js](scripts/lib/deploymentProfiles.js) and
[deployments/eip170.json](deployments/eip170.json); an alias never consumes a CREATE nonce.

`eip170` deployment set, in creation order (37 entries):

| Entry | Contract | Hosts |
| --- | --- | --- |
| `ICONS_32` | `Icons32Data` | Icon path data |
| `GAME_ACTIONS_MODULE`, `GAME_BINGO_MODULE` | `Eip170Actions` | Account actions, bingo and allowance entries |
| `GAME_PURCHASE_MODULE` | `Eip170Purchase` | Ticket, lootbox and pass purchase entries |
| `GAME_MINT_MODULE` | `Eip170Mint` | Ticket mint |
| `GAME_FOILPACK_MODULE`, `GAME_DEGENESIS_MODULE` | `Eip170DegenesisFoil` | Degenesis sale and foil packs |
| `GAME_ADVANCE_MODULE` | `Eip170Advance` | Daily advance stages |
| `GAME_JACKPOT_MODULE` | `Eip170Jackpot` | Jackpot payouts |
| `GAME_JACKPOT_DRAW_MODULE` | `Eip170JackpotDraw` | Jackpot draws |
| `GAME_WHALE_MODULE` | `Eip170Whale` | Whale, lazy and deity passes |
| `GAME_TICKET_MODULE` | `Eip170TicketFoil` | Ticket materialization and foil workers |
| `GAME_LOOTBOX_MODULE` | `Eip170Lootbox` | Lootboxes |
| `GAME_BOON_MODULE` | `Eip170Boon` | Boons |
| `GAME_DEGENERETTE_MODULE` | `Eip170Degenerette` | Degenerette bets |
| `GAME_AFKING_MODULE` | `Eip170Afking` | AFKing subscriptions |
| `GAME_GAMEOVER_MODULE` | `Eip170Endgame` | Terminal settlement, dead-VRF ending, VRF initialization and coordinator swap |
| `GAME_DECIMATOR_MODULE` | `Eip170Decimator` | Decimator battle |
| `GAME_MINER_MODULE`, `GAME_RNG_MODULE` | `Eip170MinerRng` | `mineRun` and the request, publication and retry stages |
| `COIN` | `FLIP` | FLIP token |
| `GAME` | `DegenerusGame` (`Eip170Game`) | Player entry points, VRF callback and views; delegates to the workers above |
| `COINFLIP` | `Coinflip` | Daily flip stakes and credits |
| `QUESTS` | `Eip170Quests` | Quests |
| `AFFILIATE` | `Eip170Affiliate` | Referral rewards |
| `JACKPOTS` | `DegenerusJackpots` | Jackpot support and BAF scores |
| `DEITY_PASS` | `DegenerusDeityPass` | Deity pass NFT |
| `VAULT` | `DegenerusVault` | Vault; it also creates the DGVE and DGVF share tokens |
| `SDGNRS`, `DGNRS` | `sDGNRS`, `DGNRS` | Reserve token and its transferable wrapper |
| `ADMIN` | `DegenerusAdmin` | VRF subscription, coordinator-swap governance, `donateVrf` |
| `GNRUS` | `GNRUS` | Charity token and ballots |
| `AFKING_SUB_TOKEN` | `AFKingSubscriptionToken` | Subscription seats |
| `PARIMUTUEL` | `DegenerusParimutuel` | Growth bets |
| `RECORD_BOUNTY` | `DegenerusRecordBounty` | Record bounty |
| `CRAPS_ENGINE` | `Eip170CrapsEngine` | Stateless dice engine (`external pure`) |
| `CRAPS_LIFECYCLE_MODULE` | `Eip170JackpotBattle` | Jackpot battle, run by the table's delegatecall |
| `CRAPS`, `JACKPOT_BATTLE` | `CrapsBattle` (`Eip170Craps`) | Craps table, seats and payouts |
| `WWXRP` | `WWXRP` | WWXRP token and daily draw |
| `OWNER_GOVERNANCE` | `DegenerusOwnerGovernance` | DGVE owner approval |

`DegenerusGameLens`, `CrapsLens`, `DeityBoonViewer` and `DeityPassCustomizationRenderer`
are in scope but are not part of the sequence. The deployment pipeline predicts the addresses,
patches `ContractAddresses.sol`, recompiles and deploys; checked-in test pins are not a
production deployment manifest.

## Entry points

The Game answers every player-facing name below and delegates to its workers by selector.

| Contract | Entry |
| --- | --- |
| `DegenerusGame` | `purchaseOrderFor`, `mineRun(gasMultiplierBps)`, `currentLvl`, `betDegenerette`, `decimatorActive`, `giveBoon`, `getGrowth`, `claimClaimable`, `purchaseDegenesisBox`, `clearDebtNow`, `reverseFlip`, `claimDeadVrf` |
| `Coinflip` | `playCoinflip` |
| `GNRUS` | `castBallot` |
| `WWXRP` | `enterDraw`, `claim` |
| `CrapsBattle` | `throwCraps`, `playCraps` |
| `DegenerusAdmin` | `donateVrf` |
| `DegenerusVault` | `playerAction` |

`mineRun` is the single engine entry. It selects the next action from storage (daily
request, publication, read consumers, advance stages, settlement or terminal work) and runs it
by delegatecall. Hooks that only other protocol contracts call carry a numeric suffix
(`_g<number>`) in their names so the dispatcher reaches them first; players do not call them.

## Randomness and VRF funding

Chainlink VRF v2.5 supplies randomness. Every request is paid in native ETH from the
coordinator subscription; there is no LINK token or price feed.
`DegenerusAdmin.donateVrf()` forwards the whole ETH amount to the subscription and credits a
quarter of it, in wei, as the donor's mid-day request credit. The Game tops the subscription
up when yield is distributed at level entry (if the deficit is at least a tenth of the refill
band) and refills it at the top of a daily request, taking yield surplus first, then sDGNRS
claimable, then its AFKing balance; neither step gates a request. `rawFulfillRandomWords`
runs on the Game itself, accepts only the coordinator and the stored request ID (its low 64
bits), refuses raw words 0 and 1, and stores the raw word. Daily nudges move only the coinflip.

## Build and test

```sh
npm ci
sha256sum -c docs/audit/source-sha256.txt        # source and build-input identity
make check-audit-snapshot test-assurance-tools   # manifest and assurance-tool checks
forge build --skip test                          # production build (default profile eip170)
node scripts/check-deployment-sizes.js           # runtime and initcode ceilings of the selected profile
make test-foundry                                # structural gates, then the Foundry groups
make test-hardhat                                # structural gates, then Hardhat in bounded batches
make test-fork                                   # mainnet-fork suite (needs an archive RPC)
```

`make test-foundry` and `make test-hardhat` patch `ContractAddresses.sol` with predicted
addresses for the run and restore it afterwards. Run one compile at a time; the via-IR build
is memory-heavy. To work on the alternate profile, run `PROFILE=glamsterdam node scripts/select-profile.js`
first and check sizes with `--schedule glamsterdam`. Its runtimes exceed 24,576 bytes, so
Hardhat also needs `CONSOLIDATION_CANDIDATE=true`, which lifts Hardhat's contract-size limit;
the `eip170` profile fits the default limits. [Verification](docs/VERIFICATION.md) lists every
group, gate and known limit.

### Results for this revision

Counts come from the final battery and are recorded in [the freeze record](docs/audit/freeze.json).

| Check | Result |
| --- | --- |
| Foundry standard groups | `[final battery]` passed / failed / skipped |
| Hardhat | `[final battery]` passed / failed |
| Deep invariants (1000 runs x 256 depth) | `[final battery]` roots, passed / failed |
| Halmos properties | `[final battery]` |
| Mainnet fork suites | `[final battery]` |
| Slither / Aderyn | `[final battery]` results / instances |

### Contract sizes (eip170 profile, runtime bytes)

The ceiling is 24,576 runtime and 49,152 initcode bytes per entry. The five entries with
the least spare room:

| Entry | Runtime bytes | Spare bytes |
| --- | --- | --- |
| `[final build]` | `[final build]` | `[final build]` |
| `[final build]` | `[final build]` | `[final build]` |
| `[final build]` | `[final build]` | `[final build]` |
| `[final build]` | `[final build]` | `[final build]` |
| `[final build]` | `[final build]` | `[final build]` |

The full per-entry table is `local_verification.structural.sizes` in the freeze record.

[Terms](TERMS.md) are separate from the technical audit specification.

License: [AGPL-3.0-only](LICENSE). Security contact: **burnie@degener.us**.
