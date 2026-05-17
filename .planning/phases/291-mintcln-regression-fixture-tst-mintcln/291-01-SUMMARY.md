---
phase: 291-mintcln-regression-fixture-tst-mintcln
plan: 01
status: complete
requirements: [TST-MINTCLN-01]
key-files:
  modified:
    - test/helpers/raritySymbolBatchRef.mjs
---

# Plan 291-01 SUMMARY — v42 3-input reference + owed decoder

## What was built

Two additive exports added to `test/helpers/raritySymbolBatchRef.mjs`:

1. **`raritySymbolBatchRefV42({ baseKey, entropyWord, startIndex, count })`** —
   verbatim JS port of the post-MINTCLN `_raritySymbolBatch` body at
   `contracts/modules/DegenerusGameMintModule.sol:537-588`. Uses the 3-input
   keccak shape `abi.encode(['uint256','uint256','uint32'], [baseKey,
   entropyWord, groupIdx])`. Same uint64 LCG machinery + `traitFromWord` +
   quadrant addition as the v41 export.

2. **`decodeOwedFromBaseKey(baseKey)`** — recovers `owed` from the post-MINTCLN
   `baseKey` low 32 bits via `Number(BigInt(baseKey) & 0xFFFFFFFFn)`.

The v41 export `raritySymbolBatchRef` is byte-identical (line 126 unchanged) so
no consumer of the v41 4-input form sees any behavior change. `computeBaseKey`
and `TICKET_LCG_MULT` are also unchanged.

## Self-Check: PASSED

Verify gates from PLAN.md:
- All four exports resolve as functions / bigint: `helpers OK`.
- v42 ref smoke test against `(baseKey | 8000n, pinned entropy, 0, 4)` returns
  `[10, 79, 131, 200]` (count=4 Uint8Array, decoder round-trip `8000 === 8000`).
- `grep "export function raritySymbolBatchRef\b" | grep -v "V42"` matches
  line 126 (v41 export still distinct from V42).
- `abi.encode` / `abiCoder.encode` grep shows 3-arg call in v42 at line 238
  alongside 4-arg call in v41 at line 154 (distinct keccak input shapes).

## Phase 282 fixture status (pre-existing finding — NOT a Plan 01 regression)

`npx hardhat test test/edge/MintBatchDeterminism.test.js` reports
`0 passing, 6 failing` with `TypeError: Cannot convert undefined to a BigInt`.
Verified the same failure profile exists with my helper changes stashed — i.e.
**Phase 282's fixture was already broken at audit HEAD `e5665117` by Phase
290's `TraitsGenerated` event signature change** (5 fields → 3 fields; Phase
282 parses `parsed.args.ownedSalt` / `parsed.args.startIndex` which no longer
exist on-chain).

Plan 01's must_have "v41 export byte-identical" is satisfied (verified via
file inspection — line 126 export untouched). The parenthetical "Phase 282
fixture must keep passing" is structurally invalid post-MINTCLN — Phase 282 is
a v41-closure artifact whose contract-binding assumptions changed in Phase
290. **Surface to user at the Plan 02 USER-APPROVED checkpoint** so the user
can decide whether Phase 282 needs a follow-up update or stays as a frozen
v41-closure artifact with a known-broken-since-v42 disposition.

## No git commit per plan

Per `feedback_batch_contract_approval.md` + the plan `<output>` block: the
helper change stays staged-but-uncommitted. The Plan 02 USER-APPROVED batched
commit at phase close carries both deliverables in one diff.

## D-291-GAS-01 honored

Zero gas helper, gas constant, gas log, or gas comment added.
