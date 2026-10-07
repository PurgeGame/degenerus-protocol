# Unused and obsolete resolution machinery

Reviewed commit: `c0fdf0e85` (`perf(storage): pack ID entries and batch ticket awards`).

Scope: production Solidity, concentrating on machinery inherited from individually addressed or out-of-order resolution. This review makes no production or checked-in test changes. It is pinned to the packing commit above; separate account-liquidation edits appeared in the working tree during the review and are outside this audit. Gas savings have not been benchmarked for these candidates.

## 1. Craps still supports out-of-order FIFO completion

**Locations:** `contracts/JackpotBattle.sol:125`, `:174`, `:190`; `contracts/storage/CrapsBattleStorage.sol:1124`.

Three pieces overlap:

- `_rngSlotCursor[index]` identifies the next field.
- `_rngPending[index]` separately counts unfinished fields.
- The read loop skips already-completed boards, and `_completeRngSlot` advances the cursor only if the completed slot happens to match the head.

That last behavior is specifically useful when a later field can finish before the head. The current production paths cannot do that:

1. Nonempty fields are registered once when armed. Empty fields never enter this FIFO.
2. `runCrapsReadWork` is Game-only and selects `slots[pos]`.
3. `CrapsBattle.resolveRngSlot` is self-only. Its only production callers are the read worker and the dedicated daily jackpot worker.
4. The daily worker resolves jackpot slots, which `finalizeBattle` explicitly excludes from ordinary cohort completion.
5. Ordinary completion occurs in the final seat's atomic self-call to `finalizeBattle`, or in the FIFO worker's expiry branch. Both operate on the head. Partial settlement leaves it pending; failed payouts revert the whole transition.
6. New fields bind to the other, write-side buffer. They do not change the sealed FIFO being drained.

At worker boundaries, the resulting invariant is:

```
pending[index] == slots[index].length - cursor[index]
```

**Recommendation:** make the cursor authoritative, derive emptiness from length, remove the already-completed-head skip, and simplify head completion. Preserve custom-capacity release and the Game's pending-bit transitions. Publish the advanced cursor before the completion callback, as today. Remove the redundant counter only as a coordinated change to registration, expiry, completion, and maintenance's genesis check. Respect shared delegatecall storage alignment when changing the storage declaration.

**Gas relevance:** this can eliminate counter reads/writes on registration and completion, plus repeated head comparisons and the board read/key calculation used only by the obsolete skip. It is not necessarily a fixed gas amount per field: both buffers share packed counter words, storage warmness varies, and cursor/length reads replace some counter reads. Benchmark real `mineFlip` transactions and repeated register/drain/reuse cycles.

**Evidence:** the isolated assertions in `fifo-assertions.patch` check pending-versus-length, unfinished FIFO heads, and head identity at completion. Against the original three selected suites, 24 tests passed and one failed: `test_ExpirationSkipsAlreadyCompletedLaterQueueSlot` at `test/craps/CrapsStorageReuse.t.sol:177`. That test uses `vm.prank(address(table))` to resolve `slot + 1` directly while the head remains pending. This is an artificial self-call unavailable to a player.

In the isolated probe, that scenario was replaced with an ordinary caller being rejected, followed by the worker settling the head and expiring the remaining field. All **25 tests passed**, including one fuzz property with **1,000 runs**. Suites cover global ordering, gas admission, partial settlement, payout rollback, physical buffer reuse, expiry, and terminal shutdown. These are targeted checks with the existing mocked Game fixture, not a full protocol integration proof or gas benchmark.

## 2. Degenerette's erased-bet skip is obsolete

**Locations:** `contracts/modules/DegenerusGameDegeneretteModule.sol:321`, `:433`; `contracts/libraries/MineFlipGasBounds.sol:96`.

The resolver still checks `bet == 0`, chooses a cheaper skip allowance, and advances without resolving the bet. The queue now has no production operation that creates holes:

- Placement writes a nonzero compact bet at the current write count and advances that count atomically.
- Buffer sealing captures exactly that dense prefix as `degeneretteReadCount`.
- Resolution advances the cursor without modifying the stored bet.
- Buffer reuse overwrites new entries and limits reads to the new count; stale tail lanes are outside the queue.

**Recommendation:** remove the zero-bet branch, `BET_SKIP_GAS`, and `DEGENERETTE_SKIP_GAS`; admit every live entry using `_betGasMaximum(bet)`.

The remaining test for this branch, `test/fuzz/DegeneretteSweep.t.sol:545`, creates ten holes by directly zeroing five storage words with `vm.store`. Replace it with reachable dense-queue/reuse coverage rather than preserving a production branch solely to satisfy forged storage.

**Gas relevance:** a recurring per-bet branch and its gas-selection logic disappear. No storage write is removed by this particular change. Optimized bytecode and whole-transaction gas must be compared before quoting savings.

## 3. Record-bounty deletion is no longer needed to prevent replay

**Location:** `contracts/modules/DegenerusGameDegeneretteModule.sol:946`.

The main bet is retained, but resolution still executes `delete degeneretteRecordBounty[key]`.

The side slot is read only for a flagged live bet. Every placement that sets the record flag first stores its bounty at that key; an unflagged replacement ignores any retained value. The ordered persistent cursor and active transient cursor prevent resolving the old bet again. Consequently, correctness does not require clearing this side slot after reading it.

**Recommendation:** remove the unnecessary deletion and retain/overwrite the bounty like the bet itself. Preserve the flag gate and both cursor protections. Update the storage comment and `test/fuzz/BigRecordArming.t.sol:184`, which currently asserts a physical zero, and add explicit flagged → unflagged → flagged buffer-reuse coverage before shipping.

**Gas relevance:** removes an unnecessary resolution write and retains the value for cheaper future overwrite. Refunds do not restore execution gas. Per the user's direction, refund accounting is not a prerequisite for this cleanup recommendation; measure execution savings alongside the implementation.

## 4. Worker readiness is checked more than once

**Locations:** `contracts/modules/DegenerusGameMinerModule.sol:55`, `:77`, `:155`; `contracts/modules/GameAfkingModule.sol:1593`, `:1655`; `contracts/modules/DegenerusGameDegeneretteModule.sol:425`; `contracts/modules/DegenerusGameDecimatorModule.sol:338`.

The miner selects the consumer through `_nextMinerAction`, which already calls `_rngConsumerStage`. Its trusted worker then calculates the full stage again. The dispatch path explicitly has only reads between selection and the first call, and reselects after each worker.

A smaller independently supported cleanup is the subsequent zero-word check in AFKing (`:1599`), human boxes (`:1658`), and Degenerette (`:427`). A successful matching stage already proves the current word nonzero and published; each immediately reads that same word through `_lootboxWord(_rngReadBuffer())`. There is no intervening state-changing call. Decimator already relies on this implication.

**Recommendation:** remove the redundant zero-word checks first, subject to optimized-code comparison. Separately consider trusted worker entrypoints that consume the miner's selection instead of redoing it. Keep caller/context restrictions and reentrancy protections. Direct module calls and test-only worker exposure must be handled explicitly; do not indiscriminately remove the shared stage function, which remains necessary for selection and views.

**Gas relevance:** repeated state reads and, for full stage recomputation, the redemption-pending external view. Some repetition may already be optimized away within a single contract. Calls across dispatch boundaries warrant measurement.

## 5. Source-only leftovers

The typed compiler inventory found these production-unreachable helpers/constants:

| Declaration | Location | Other use |
| --- | --- | --- |
| `_lrAdd` | `contracts/storage/DegenerusGameStorage.sol:3342` | No Solidity callers; stale classification entry in `scripts/lib/rng_window_classify.py` |
| `_walletKey` | same file, `:1618` | Still used by test harnesses; move/localize those uses if removing it |
| `LB_ID_MASK` | same file, `:2449` | No production use |
| `LB_LEVEL_MASK` | same file, `:2451` | Used by `test/fuzz/LootboxTierSizes.t.sol` |
| `RECORD_KINDS` | `contracts/interfaces/ICoinflip.sol:44` | File-level constant with no production references |

The compiler also reports the unused `address s` local in `contracts/Coinflip.sol:1707` after the ID migration. These have no reachable production runtime work to eliminate; do not count their source removal as a transaction gas saving.

Unused error declarations include the Degenerette and Lootbox modules' `RngNotReady` and Jackpot module's `JackpotWorkMismatch`. Inspect ABI compatibility when removing declarations. The raw inventory also contains deliberate facade/interface aliases: Game's bubbled worker errors and Craps' `BadBattleTerms` alias are examples to retain. Public constants with generated getters are excluded from the unused-constant results.

Stale comments should be fixed alongside cleanup:

- Degenerette `:66` describes a manual-resolution error that is never thrown there.
- Degenerette `:773` says the caller already zeroed the bet, which is now false.
- Degenerette/Lootbox comments still name the removed `sweepDegeneretteBets` entrypoint.
- Game `:1792` and storage `:4658` still describe manual read consumers.

## Machinery that remains live

- **Transient Degenerette cursor:** serializes callbacks and hides the in-flight prefix while persistent cursor writes are batched. FIFO ordering alone does not prevent callback reentry.
- **Read counts and buffer boundaries:** bound the live prefix and prevent stale packed lanes from becoming entries when a shorter queue reuses a buffer.
- **Craps expiry/day tags:** a stalled read can outlive the storage retention window; the expiry tests exercise this. Keep the expiry path even when removing completed-head skipping.
- **Craps seat cursor:** supports partial settlement and lapsed-day refunds. A field queue cursor does not replace progress within a field.
- **Decimator phases/sampling/payout cursors:** checkpoint bounded work across transactions.
- **AFKing stamps and pending state:** the subscriber array is a persistent ring with inactive/tombstoned entries and cross-day state, unlike the dense Degenerette queue.
- **VRF active-request and publication state:** ordered consumers do not make request retries, callback authority, or terminal state disappear.
- **Award identity/seed separation:** multiple jackpot tickets still require distinct award identity; this is unrelated to removing resolution bookkeeping.

## Reproduction and limitations

`python3 scripts/audit/unused-resolution-review/scan.py --revision c0fdf0e85` compiles a typed AST using local Solidity 0.8.34 and writes `inventory.json`, `compiler-warnings.json`, and `source-hashes.json`. It scans 83 production source files plus imported dependencies. Public/external functions are conservative roots, so an absent in-repository caller is never enough to label a public API dead. Assembly declaration references and overrides are included. Raw error/event candidates require manual ABI and delegatecall review. The inventory is not a reachability proof for every external selector or branch. Omit `--revision` to scan current working-tree sources.

The probe workspace is recorded in `probe-workspace.json`. It copies the prior isolated, address-pinned validation workspace, applies `fifo-assertions.patch`, and imports only the three listed Craps suites. `fifo-probe.log` preserves the original artificial out-of-order failure. `production-caller-probe.patch` records the replacement test; `fifo-production-caller-probe.log` records the 25-test passing run. Instrumentation changes gas, so those test gas figures are not optimization measurements.

Recommended implementation order: remove obsolete Degenerette hole handling, the bounty clear, and stale source declarations/comments; simplify Craps FIFO bookkeeping with the production-call coverage above; then simplify centralized worker admission as a separate change. Measure execution gas with the implementation without blocking removal of unnecessary work on refund accounting.
