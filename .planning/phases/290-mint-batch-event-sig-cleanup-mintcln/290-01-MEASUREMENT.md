# Phase 290 MINTCLN — Measurement Attestations (MINTCLN-08 + MINTCLN-09)

> Scaffold for the 6 load-bearing attestations Plan 02 fills in after the contract patch lands.
> `<FILL-IN-Plan-02>` placeholders mark fields Plan 02 populates post-patch.
> This doc is the verbatim copy-forward source for Plan 02's batched commit message body, per `feedback_no_history_in_comments.md` (numerical attestations go in the commit body, NOT into NatSpec).
> Plan 02 MUST re-validate every populated value against the post-patch tree before the user approves the commit.

## Audit Baseline

Anchor: `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` (v41.0 closure HEAD). Source of truth for every "byte-identical to v41 close" assertion in this scaffold and for every "delta vs v41 close" measurement Plan 02 records below. All comparisons resolve against this SHA via `git worktree add` or `git show <sha>:<path>` techniques.

## (1) Bytecode Delta

`contracts/modules/DegenerusGameMintModule.sol` deployed-runtime bytecode delta vs v41 close = **`<SIGNED-INT>` bytes** (positive = grew; negative = shrank). `<FILL-IN-Plan-02>`

**Method:** Compile twice via `forge build` (or `hardhat compile` if the toolchain in use) — once at the v42 HEAD post-patch, once at `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` baseline via `git worktree add ../v41-baseline 315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4`. Size-compare the deployed runtime bytecode strings emitted by the compiler.

**Expected sign:** **negative** (cleanup drops one `_raritySymbolBatch` parameter + drops one keccak input + drops 3 fields from `TraitsGenerated` event encoding at both emit sites = smaller bytecode at all touched callsites). Magnitude bounded by Plan 02's worst-case estimate before measurement is taken. If measured magnitude exceeds Plan 02's pre-derivation estimate by > 50%, escalate to user before commit.

`<FILL-IN-Plan-02>`

## (2) Storage-Slot Grep Proof (MINTCLN-08)

`forge inspect contracts/modules/DegenerusGameMintModule.sol storageLayout` diff vs v41 close = **`<EMPTY | recorded-non-empty-value>`**. `<FILL-IN-Plan-02>`

`forge inspect contracts/storage/DegenerusGameStorage.sol storageLayout` diff vs v41 close = **`<EMPTY | recorded-non-empty-value>`**. `<FILL-IN-Plan-02>`

**Locks under MINTCLN-08:**
- `ticketsOwedPacked[rk][player]` 40-bit packed form (rem low 8 + owed next 24 + processed-via-owed-salt high 8) MUST remain at the same slot offset / type / label as v41 close.
- Zero new storage slots in MINTCLN scope.
- Zero new mappings in MINTCLN scope.
- Zero new SSTORE callsites in MINTCLN scope (all SSTOREs in the touched range write to pre-existing slots).
- Zero new SLOAD callsites in MINTCLN scope.

**Escalation rule:** If either `forge inspect storageLayout` diff is NON-EMPTY, STOP and escalate to user before commit — MINTCLN-08 is a hard byte-identity lock; any non-empty diff is an out-of-scope storage layout change that requires user disposition.

`<FILL-IN-Plan-02>`

## (3) Worst-Case Gas (theoretical FIRST per feedback_gas_worst_case.md)

Theoretical derivation framework (Plan 02 fills in the numerical bounds and the empirical confirmation; the FRAMEWORK is locked here):

**(a) Anchor case.** ~5840 `owed`-per-player multi-call drain at max `WRITES_BUDGET_SAFE` — the deity-pass + far-future worst-case scenario where a single `(rk, player)` slot accumulates the upper-bound `owed` and consumes successive `processFutureTicketBatch` / `processTicketBatch` calls until drained. `<FILL-IN-Plan-02>`

**(b) Per-`_raritySymbolBatch`-invocation gas delta.** Removing `ownedSalt` (uint32) from `abi.encode(baseKey, entropyWord, groupIdx, ownedSalt)` to `abi.encode(baseKey, entropyWord, groupIdx)` saves +1 ABI-encoded 32-byte word at the keccak input → estimated `~-3 gas` per keccak word (keccak cost difference) + `~-30 gas` from the dropped memory load + function-parameter slot. Estimated `≥-30 gas` savings per invocation. `<FILL-IN-Plan-02>`

**(c) Per-`TraitsGenerated` emit gas delta.** Dropping 3 fields from the event payload (the `uint24 level` indexed field + the `uint32 startIndex` non-indexed field + the `uint256 entropy` non-indexed field) saves event-data + topic encoding. Specifically: `level` was indexed at the v41 declaration (`uint24 indexed level` at `DegenerusGameStorage.sol:486`) — its removal drops a `LOG3` to a `LOG2` topic cost (`-375 gas`) plus removes one indexed-topic SHA3 hash if present in the encoding path. The `startIndex` + `entropy` removals drop two non-indexed words from LOGDATA (`~-16 gas` for the two memory-stored 32-byte words encoded into the event data). Estimated `~-375 gas` per emit (dominant contributor: `LOG3 → LOG2`). Plan 02 verifies the `LOG3 → LOG2` transition by reading the post-patch declaration's `indexed` modifier count (the post-MINTCLN-04 shape `(address indexed player, uint256 baseKey, uint32 take)` has exactly 1 indexed field → `LOG2`). `<FILL-IN-Plan-02>`

**(d) Cross-call drain total.** At 5840-owed-per-player worst-case: `_raritySymbolBatch` is invoked once per outer-loop entry (`(5840 / writesBudget-per-iteration)` invocations, roughly `5840 / 292 ≈ 20` invocations end-to-end at typical writes budgets); `TraitsGenerated` is emitted once per outer-loop entry. Estimated `~-30 × 20 ≈ -600 gas` from invocation savings + `~-375 × 20 ≈ -7500 gas` from emit savings = `~-8100 gas` across a full drain (rough order). `<FILL-IN-Plan-02>`

**Empirical confirmation.** `<FILL-IN-Plan-02 — run existing benchmark fixture if test/gas/ contains one targeting `processFutureTicketBatch` or `processTicketBatch` drain scenarios; if no fixture exists, record theoretical-only and defer empirical to Phase 291 TST-MINTCLN per `feedback_gas_worst_case.md` theoretical-first prioritization rule>`

## (4) Selector Attestations (MINTCLN-09)

- `processFutureTicketBatch(uint24,uint256)` selector = **`<0x........>`** (UNCHANGED vs v41 close). `<FILL-IN-Plan-02>`
- `processTicketBatch(uint24)` selector = **`<0x........>`** (UNCHANGED vs v41 close). `<FILL-IN-Plan-02>`
- `_processOneTicketEntry(address,uint24,uint24,uint32,uint32,uint256,uint256)` — private function; not part of public ABI; canonical signature recorded for completeness. Selector hash = **`<0x........>`** (recorded value; not exposed as a 4-byte external selector). `<FILL-IN-Plan-02>`

**Method:** `cast sig "<canonical-signature>"` OR `python3 -c 'from eth_utils import keccak; print(keccak(b"<sig>")[:4].hex())'`.

**Lock under MINTCLN-09:** All three signatures byte-identical to v41 close. If any selector hash differs from v41 close, STOP and escalate to user — MINTCLN-09 is a hard public-ABI byte-identity lock for the two external functions, and the private `_processOneTicketEntry` canonical signature is recorded as a structural attestation of "no internal-call-graph break ahead of the MINTCLN refactor."

`<FILL-IN-Plan-02>`

## (5) Event Topic Hash Attestations (MINTCLN-04 + MINTCLN-09)

- `TraitsGenerated` v41 topic hash (6-field shape) = **`<0x................................................................>`** = `cast keccak "TraitsGenerated(address,uint24,uint32,uint32,uint32,uint256)"`. `<FILL-IN-Plan-02>`
- `TraitsGenerated` v42 topic hash (3-field shape post-MINTCLN-04) = **`<0x................................................................>`** = `cast keccak "TraitsGenerated(address,uint256,uint32)"`. `<FILL-IN-Plan-02>`

**The two topic hashes MUST differ.** That difference IS the BREAKING-TOPIC-HASH structural attestation per D-42N-EVT-BREAK-01 — recorded explicitly here so the audit deliverable at Phase 297 §3.A can cite both values verbatim.

- `TicketsCredited` topic hash = **`<0x........>`** (UNCHANGED vs v41 close — `grep` `contracts/` for the canonical `TicketsCredited` signature, then `cast keccak` the canonical-form string; record the value). `<FILL-IN-Plan-02>`
- `TicketsQueued(address,uint24,uint32)` topic hash = **`<0x........>`** (UNCHANGED vs v41 close). `<FILL-IN-Plan-02>`

**Lock under MINTCLN-04 + MINTCLN-09:** Only `TraitsGenerated` topic hash changes. `TicketsCredited` + `TicketsQueued` byte-identical to v41 close. If either non-`TraitsGenerated` event topic hash differs, STOP and escalate to user.

`<FILL-IN-Plan-02>`

## (6) B2-Symmetric-Callsite Diff Check (per v41 Phase 281 precedent)

Post-patch `baseKey` construction at `processFutureTicketBatch` (mint:423-425) MUST be byte-identical to the `baseKey` construction at `_processOneTicketEntry` (mint:800-802) — modulo the local variable name difference (`idx` vs `queueIdx`, which is a non-substantive local rename).

Post-patch `_raritySymbolBatch` callsite at mint:469 MUST be byte-identical to the callsite at mint:803 — modulo the same local name.

Post-patch `TraitsGenerated` emit at mint:470-477 MUST be byte-identical to the emit at mint:804-811 — modulo the same local name.

**Method:** Structural diff via `diff <(sed -n '423,425p' contracts/modules/DegenerusGameMintModule.sol) <(sed -n '800,802p' contracts/modules/DegenerusGameMintModule.sol)` (and analogous on the callsite + emit pairs); expect identical text modulo the local-name swap. Plan 02 may also use the same structural-diff technique via post-MINTCLN line offsets (the line numbers cited here are pre-patch; post-patch line offsets may shift by a few lines due to the deletions). Plan 02 records the post-patch line offsets in the populated value below.

**Lock under v41 Phase 281 B2-symmetric precedent:** Any deviation from byte-identity (beyond the local-name swap) is an out-of-scope drift that requires user disposition before commit.

`<FILL-IN-Plan-02>`

## Source-Doc Cross-Cite

- **Back-reference:** `290-01-DESIGN-INTENT-TRACE.md` (this scaffold's sister artifact; Plan 01 design-intent gate per MINTCLN-10 + `feedback_design_intent_before_deletion.md`).
- **Forward-reference:** `290-02-PLAN.md` (the contract-patch plan; Plan 02 reads this scaffold's `<FILL-IN-Plan-02>` placeholders and populates them post-patch).
- **Plan 02 Task 5 (checkpoint:human-verify):** uses the populated values from this scaffold verbatim in the batched commit message body. The doc MUST be re-validated against the post-patch tree before the user approves the commit.

Plan 02 fills the `<FILL-IN-Plan-02>` placeholders post-patch. The populated values are the verbatim copy-forward source for the batched commit message body (per `feedback_no_history_in_comments.md` — numerical attestations live in the commit body, NOT in NatSpec). The doc MUST be re-validated against the post-patch tree before the user approves the commit.
