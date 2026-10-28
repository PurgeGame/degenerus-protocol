# Native Glamsterdam storage-reuse measurements

> **Historical evidence.** This file records the storage-reuse implementation committed in `c4c1effe5` (2026-10-20; source baseline `fb2540c55`, Solidity 0.8.34; the current build uses 0.8.38). It is not a description of the current
> source. Current layouts and behavior: [Storage reuse](../../../docs/STORAGE-REUSE.md) and
> `scripts/layout/golden/`.

Read-only `eth_simulateV1`, Sepolia PublicNode, no sent transactions. The primitive
probe confirms a **97,920 gas difference between creating and overwriting a slot**.
Solc 0.8.34, via IR, 1,000 optimizer runs, Osaka-targeted bytecode executed by the
Glamsterdam client. Exact request bodies, runtime hashes, address pins, block and
client are retained in `native-results.json`, `native-requests/` and the baseline
compiler-input archive. These synthetic states are not a replay of run 75.

All **54 calls (27 matched cases)** succeeded with matching returns and the declared
log comparison. Current90 uses the old Coinflip/BAF/affiliate codecs from the pinned
baseline, a 90-day claim window and the same new Game-side Vault schedule. Relevant
storage is independently translated; old code never interprets ring/history words.
This isolates codec costs. It does not measure shipped Current730's full backlog.

| Complete call | R90 charged | Current90 charged | R90 / Current90 peak (`maxUsedGas`) |
| --- | ---: | ---: | ---: |
| `credit_fresh` | 130,747 | 129,848 | 130,747 / 129,848 |
| `credit_same_page` | 32,462 | 31,928 | 32,462 / 31,928 |
| `credit_expired_reuse` | 35,643 | 129,848 | 35,643 / 129,848 |
| `credit_new_overflow` | 148,025 | 129,848 | 148,025 / 129,848 |
| `batch_overflow_32` | 4,174,955 | 3,655,291 | 4,174,955 / 3,655,291 |
| `claim_1_full_ring` | 167,627 | 166,027 | 167,627 / 177,643 |
| `claim_14` | 762,128 | 768,643 | 762,128 / 791,875 |
| `claim_90` | 875,272 | 851,465 | 875,272 / 1,002,473 |
| `claim_and_deposit_14` | 682,910 | 678,891 | 682,910 / 702,123 |
| `exit_90_rebuy` | 915,881 | 903,690 | 915,881 / 1,043,082 |
| `vault_90` | 447,516 | 459,341 | 447,516 / 574,176 |
| `vault_miner_checkpoint_76` | 470,850 | 462,076 | 470,850 / 577,594 |
| `baf_fresh` | 350,669 | 350,388 | 350,669 / 350,388 |
| `baf_reuse` | 252,749 | 350,388 | 252,749 / 350,388 |
| `affiliate_fresh` | 477,884 | 477,425 | 477,884 / 477,425 |
| `affiliate_next_level` | 161,180 | 258,523 | 161,180 / 258,523 |

The main savings recur when retained homes replace new storage creations. Initial
allocation and same-page credits are slightly dearer. Clearing refunds can make an
old-code claim cheaper in charged gas; this does not make clearing/recreating the
stake pages cheaper over a repeated credit/claim lifecycle. The 90-day walk remains
far below the 10M ceiling in these witnesses. They are measurements, not universal
maxima over all state and caller compositions.

`affiliate_capped` is an approved economic difference, not a pure gas comparison:
score events differ while payout events and returns match. For the full miner call,
execution-gas/reward fields are normalized; other fields/events match and all raw
logs remain available. That checkpoint is below the unpaid-million threshold, so
its raw logs contain no miner bounty or bounty stake credit.

## Batch allowance

`native-marginal.json` replays the same cold overflowing batch with 1, 2, 31 and 32
recipients. It leaves trailing calldata unchanged to hold intrinsic gas constant.
The 32-minus-31 marginal is **129,571 gas**. Both `CRAPS_CREDIT_GAS_MAX` and
`DEGENESIS_FLUSH_PER_CREDIT` are **160,000**, giving 23.48% headroom over this
marginal. Growth settlement shares the former allowance. The full 32-recipient
spill batch costs 4,174,955, below 32 × 160,000 even before its separate tail reserve.
`ENGINE_RETURN` remains 200,000; a complete standalone spill credit is 148,025.
`BAF_VAULT_SETTLE` remains 3.5M; it has not been reduced from a favorable witness.

## Measurement limits and remaining calibration

Calls use 16M gas, below the 16,777,216 threshold: no state-gas reservoir is used.
Charged gas and `maxUsedGas` are reported separately. The latter is peak required
gas, including call-forwarding constraints, **not a gross execution counter**.
The response's block resource gas is a resource maximum, not execution plus state.
These public endpoints do not expose `debug_traceCall`; actual execution/state
counters and uncapped/capped refunds therefore cannot be inferred by relabeling
`maxUsedGas`. Local recorded-access repricing is separate, conservative evidence.

Separate production-context witnesses in `native-context-results.json` and
`native-atomic-results.json` also pass with exact returns/logs:

| Complete phase | Native charged / peak | Reserved operation allowance |
| --- | ---: | ---: |
| Daily application, six maximum-depth boon draws | 3,457,590 | 7,200,000 |
| Century daily application, full 90-day Vault history | 3,788,553 | 7,200,000 |
| Live 29-day gap application | 709,253 | 850,000 |
| Terminal application with the same gap | 853,132 | 8,050,000 (`DAILY_APPLY + DAILY_GAP`) |
| Level-one daily draw, all 50 trait shares plus seal | 6,376,789 | 7,500,000 |

The gap fixtures establish the preceding Coinflip frontier through the real
resolver, including sDGNRS's cursor/rebuy latch. Their assertions prove that the
gap/terminal word actually applied and that neither path claimed the Vault or
wrote its backstop stamp. The six-boon fixture checks six awards and one fresh
daily application. The century fixture uses the existing full-production setup.

The level-one witness is in `native-purchase-results.json`; its fixture asserts
all 50 awards and the final unlock. It leaves 1,123,211 gas (17.61% of measured
cost) under `LEVEL_ONE_DRAW`. This includes the real Game delegate dispatch,
Coinflip credits and the daily seal, not just the credit batch.

These states are individual witnesses, not universal maxima. Broad caller tests
and conservative single-credit composition checks remain required; a standalone
credit result cannot certify every admission bound.
