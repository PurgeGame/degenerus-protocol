# Phase 278 / Plan 01 — Storage-Layout Byte-Identity Proof

**Requirement:** JPT-CLEAN-06 (storage layout byte-identical to v39 baseline `6a7455d1`).
**Decisions:** D-278-ENT05-01 (xorshift→keccak swap inside `_jackpotTicketRoll` — function-body-only), D-278-EVT-UNIFY-01 (`JackpotTicketWin` emit *values* change; signature/topic-hash unchanged), D-278-ENTROPYSTEP-DELETE-01 (`EntropyLib.entropyStep` deleted), JPT-CLEAN-05 (`_queueLootboxTickets` zero-caller wrapper deleted).

## Baseline vs HEAD

| Side | Commit | File state |
|------|--------|------------|
| v39 baseline | `6a7455d1` (`audit(274): §9 closure attestation block + 274-01-SUMMARY.md`) | `contracts/modules/DegenerusGameJackpotModule.sol` at v39.0 close |
| Phase 278 pre-commit | working tree + Plan 01 Tasks 1–2 edits (uncommitted) | Same file with the `:2210` `entropyStep`→`hash2(entropy,entropy)` swap, the 3 `JackpotTicketWin` emit-value unifications, and the bit-allocation / event-doc / module NatSpec rewrites |

The JackpotModule storage-layout baseline is `6a7455d1`. Phases 275/276/277 between the v39 baseline and Phase 278 did not move any `DegenerusGameJackpotModule.sol` state variable — Phase 278 touches only function bodies + event *values* + NatSpec, so `6a7455d1` is the correct and valid storage-layout baseline for this file.

## Extraction Recipe

Standard `forge inspect ... storage-layout` mechanic, mirroring the Phase 275/276 artifact convention. The v39 baseline was materialized via a detached-HEAD git worktree at `6a7455d1` (read-only inspection target — no commit, no checkout of the working tree; the worktree was removed after extraction):

1. `forge inspect contracts/modules/DegenerusGameJackpotModule.sol:DegenerusGameJackpotModule storage-layout` at the current working tree (Tasks 1–2 applied) → `/tmp/p278-head-layout.txt` (171 lines).
2. `git worktree add /tmp/p278-baseline 6a7455d1` → `forge inspect ... storage-layout` inside the baseline worktree → `/tmp/p278-baseline-layout.txt` (171 lines).
3. `diff /tmp/p278-baseline-layout.txt /tmp/p278-head-layout.txt` + `sha256sum` cross-check.
4. `git worktree remove /tmp/p278-baseline`.

`forge inspect ... storage-layout` emits the resolved `{slot, offset, label, type, contract}` table directly — no `astId` normalization needed (the `forge` table view, unlike the raw Hardhat `storageLayout` JSON, does not embed compiler-internal AST node IDs).

## Verdict

**PASS — storage byte-identical to v39 baseline `6a7455d1`.**

- Layout line count: **baseline = 171**, **HEAD = 171**.
- `diff` of the two `forge inspect storage-layout` outputs: **empty (exit 0)**.

```
$ diff /tmp/p278-baseline-layout.txt /tmp/p278-head-layout.txt
$ echo $?
0
```

- `sha256sum` cross-check — identical hashes:

```
fc0e173c4d7e8f59575b6ffb2981439563f2f961b5aac5fb5ea3ee5ac35d2ce8  /tmp/p278-baseline-layout.txt
fc0e173c4d7e8f59575b6ffb2981439563f2f961b5aac5fb5ea3ee5ac35d2ce8  /tmp/p278-head-layout.txt
```

## JPT-CLEAN-06 Satisfaction Note

Phase 278's four-file contract surface change introduces **zero** storage-layout effect:

- **`_jackpotTicketRoll` `:2210` `entropyStep`→`hash2(entropy, entropy)` swap** — a function-call replacement inside the function body. `entropy` is already a function-scope local; no contract-level state added or moved. The downstream low-bit consumers (`entropy / 100`, `% 4`, `% 46`) and the bits[200..215] Bernoulli slice are unchanged — they now read a keccak word instead of an xorshift word, which has no storage implication.
- **3× `JackpotTicketWin` emit-value unification** — the `JackpotTicketWin` event *definition* (field types, `indexed` markers, field order) is unchanged; only the emitted 4th-argument *value* changes (scaled `×TICKET_SCALE` → whole). Event definitions are not storage; emit-value changes are codegen-only.
- **`EntropyLib.entropyStep` deletion** — `entropyStep` is a library `internal pure` function; libraries with only `internal` functions have no storage. Deleting it removes inlined code from callers, not storage slots.
- **`_queueLootboxTickets` deletion** — an `internal` storage-helper wrapper in `DegenerusGameStorage.sol` with zero callers. It declares no state variables; its body only forwards to `_queueTicketsScaled`. Deleting it removes dead code, not storage slots. `DegenerusGameStorage.sol`'s state-variable declarations are untouched.
- **`MintModule:649` comment touch** — comment-only; no codegen, no storage effect.

No contract-level state variables, mappings, or structs were added, removed, or reordered in any of the four files. JPT-CLEAN-06's storage byte-identity requirement is satisfied for `DegenerusGameJackpotModule.sol`.
