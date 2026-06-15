# Mutation Survivor Triage — v63 subject `a8b702a7`

Every UNCAUGHT survivor from the completed campaign targets, classified FALSE (equivalent
mutant / unreachable / oracle-provably-indistinguishable) vs GENUINE (a reachable
behavioral change the comprehensive oracle should have killed but did not). Ambiguous →
default GENUINE → carried to Plan 03. GENUINE candidates are re-verified at FULL oracle
runs (default profile, FOUNDRY_FUZZ_RUNS=1000, INVARIANT runs=256) IN PLACE, then restored,
before being finalized.

**Scope of this ledger:** the only target fully scored so far is `BitPackingLib`
(PACKING IDENTITY). Its 55 survivors are triaged below. The remaining five targets are
IN-PROGRESS / NOT RUN (see CAMPAIGN-REPORT-v63.md status table); their survivors will be
appended here as each target's `.DONE` lands on resume.

**Subject (byte-frozen):** `a8b702a7` — contracts tree-hash
`2934d3d8987a09c5f073549a0cb499f6c5f28620`. Every re-verification mutation below was applied
TRANSIENTLY in place with the campaign runner stopped (no two processes mutate `contracts/`
at once) and restored before proceeding; `git diff a8b702a7 -- contracts/` is EMPTY at the
end (see byte-freeze attestation).

**Source:** `audit/mutation/BitPackingLib-v63.log` (the per-line `… --> UNCAUGHT` entries,
mutator + diff) + `audit/mutation/BitPackingLib-mut-v63/`.

---

## Survivor-class summary (`BitPackingLib`, 55 survivors)

| # | Class | Lines | Count | Mutators | Verdict |
|---|---|---|---|---|---|
| C1 | `MASK_*` constant value change | 33/36/39/42/45 | 36 | AOR (20), BOR (16) | **FALSE** (oracle-coverage gap on a caller-pre-clamped width-bounding mask; equivalent under the subject's invariant) |
| C2 | `MASK_*` constant type narrow | 33/36/39/42/45 | 5 | SBR `uint256→uint128` | **FALSE** (equivalent mutant — identical value, never stored) |
| C3 | `*_SHIFT` constant type narrow | 52–88 | 13 | SBR `uint256→uint128` | **FALSE** (equivalent mutant — identical value, never stored) |
| C4 | `setPacked` body removed | 110 | 1 | CR (return → comment) | **GENUINE** (reachable 46-call-site primitive, oracle never asserts a `setPacked` round-trip) |

**GENUINE set = { C4: `BitPackingLib.setPacked` body-coverage gap }** (1 survivor) — see
§GENUINE below. It is a TEST-coverage hole, NOT a contract defect (the subject's `setPacked`
is correct). Class = PACKING IDENTITY (not SPINE solvency/RNG). Routed to Plan 03.

---

## FALSE survivors

### C2 + C3 — SBR `uint256 → uint128` on the `MASK_*` and `*_SHIFT` constants (18 survivors)

**Mutated lines:** 33/36/39/42/45 (the five masks) and 52/55/58/61/64/67/70/73/76/79/82/85/88
(the thirteen shift positions). **Mutator:** SBR — e.g.
`uint256 internal constant MASK_16 = (uint256(1) << 16) - 1` →
`uint128 internal constant MASK_16 = (uint128(1) << 16) - 1`, and
`uint256 internal constant LAST_LEVEL_SHIFT = 0` →
`uint128 internal constant LAST_LEVEL_SHIFT = 0`.

**Verdict: FALSE — EQUIVALENT MUTANT.** The mutation changes only the declared Solidity TYPE
of a compile-time `constant`. The numeric VALUE is identical in both forms
(`(uint128(1) << 16) - 1 == 0xFFFF == (uint256(1) << 16) - 1`; the shift literals `0…228`
are unchanged and `< 2^128`). A `constant` is inlined at the use site, never written to
storage, and every consumer immediately participates in a `uint256` expression
(`value & mask`, `mask << shift`, `value << shift`) where the operand widens back to
`uint256` with no truncation (the masks ≤ 32 bits, the shifts ≤ 228 — all fit uint128). So
the produced bytecode and every observable result are byte-identical. No oracle can
distinguish these (the documented equivalent-mutant case); not a net hole.

### C1 — AOR / BOR value change on the `MASK_*` constants (36 survivors)

**Mutated lines:** 33 (`MASK_16`), 36 (`MASK_24`), 39 (`MASK_32`), 42 (`MASK_6`),
45 (`MASK_8`). **Mutators:** AOR (`(1<<N) - 1` → `+1` / `/1` / `*1` / `%1`) and BOR
(`(1<<N)` → `1 & N` / `1 | N` / `1 >> N` / `1 ^ N`), i.e. the mask CONSTANT takes a
different numeric value (e.g. `MASK_16: 0xFFFF → 0x10001` for `+1`; `→ 0` for `% 1`;
`→ (1|16)-1 = 0x10` for `| 16`).

**Verdict: FALSE — oracle-coverage gap on a caller-pre-clamped width-bounding mask
(equivalent under the subject's invariant).** Reasoning, against the storage-packing
surface map (`.planning/v63-surface-map/storage-packing.md`) and the on-chain consumers:

- The `MASK_*` constants are used in exactly two reachable shapes: (i) a width CLAMP at the
  call site BEFORE packing — e.g. `DegenerusGameMintModule.sol:378`
  `if (levelUnitsAfter > BitPackingLib.MASK_16) { levelUnitsAfter = BitPackingLib.MASK_16; }`
  then `setPacked(..., MASK_16, levelUnitsAfter)`; and (ii) the `value & mask` /
  `(mask << shift)` operands inside `setPacked` and the read-side accessors.
- Under the subject's invariant the packed VALUE is always already within the field width
  when it reaches the mask (the callers clamp, and the read-side masks a field that was
  written with a clamped value). For a value `v` already `< 2^N`, `v & MASK_N == v` for the
  correct mask; the over-/under-wide mutant masks differ ONLY on bits the subject never
  sets, so the observable packed/unpacked result is unchanged across the oracle's domain.
  The mutation is therefore behaviorally INDISTINGUISHABLE under the subject's
  caller-clamped invariant — an equivalent mutant relative to the reachable input set, not
  a live defect on a reachable path.
- This is the exact documented BitPackingLib false-survivor pattern (the prior all-files
  run logged the same `MASK_16/24` `[CR]`/`[AOR]` survivor swarm): the comprehensive oracle
  exercises the masked-RMW path but does not feed a `value` whose out-of-field bits would
  expose a wrong mask, because the protocol never produces such a value.
- NOTE (defensive-engineering): the masks are a DEFENSE-IN-DEPTH width bound on top of the
  caller clamps. A test that fed `setPacked` an oversized `value` and asserted the field
  bound would KILL these mutants and is the same coverage improvement as the C4 gap below;
  it is recorded as a Plan-03 oracle-hardening OPTION, but the survivors are FALSE (no net
  hole on the subject's reachable behavior, mask redundancy is by-design).

---

## GENUINE survivors

### C4 — `setPacked` masked-RMW return body commented out (1 survivor) [the noted 395-01 candidate]

**Mutated line:** 110. **Mutator:** CR.
`return (data & ~(mask << shift)) | ((value & mask) << shift)` →
`//return (data & ~(mask << shift)) | ((value & mask) << shift)` — `setPacked` now returns
0 (the default `uint256`).

**Companion data point (the oracle DOES reach the function):** on the SAME line, the RR
mutant `return … ==> revert()` was **CAUGHT** — so an oracle test does call `setPacked` and
notices when it reverts. But the CR mutant (return 0 instead of the packed word) **SURVIVED**
— the oracle calls `setPacked` but never asserts its RETURN VALUE round-trips.

**Full-run re-verification (this plan):** the CR mutation was applied IN PLACE and the
COMPREHENSIVE oracle re-run at the DEFAULT profile (no bounded env: FOUNDRY_FUZZ_RUNS=1000,
INVARIANT runs=256, via_ir):

```
Ran 12 test suites in 19.75s (70.63s CPU time): 113 tests passed, 0 failed, 0 skipped
oracle exit 0  ⇒ mutant STILL SURVIVES at full runs (not a bounded-run artifact)
```

The mutation was then restored (`git checkout -- contracts/`); byte-freeze re-asserted
(tree-hash `2934d3d8…`, diff EMPTY).

**Reachability (NOT dead code):** `BitPackingLib.setPacked` has **46 on-chain call sites**
across `DegenerusGameMintStreakUtils`, `DegenerusGameBoonModule`, `DegenerusGameWhaleModule`,
`DegenerusGameMintModule`, `GameAfkingModule`, `DegenerusGameBingoModule`,
`DegenerusGameDegeneretteModule`, `DegenerusGameLootboxModule`. It is the masked-RMW
primitive that writes the `mintPacked_[player]` word (last/count/streak/day/units,
frozen-until-level, whale-bundle-type, deity-pass, affiliate bonus, curse counter). Commenting
out its body zeroes EVERY one of those writes (the function returns 0, so the assigned packed
word becomes 0), yet all 12 oracle suites stay green.

**Verdict: GENUINE — a real oracle net hole (TEST coverage, not a contract defect).** The
subject's `setPacked` is correct; the GENUINE finding is that the comprehensive oracle does
not pin the `BitPackingLib.setPacked` mint-data round-trip. The oracle's packing coverage
is on the SEPARATE storage-helper family (`DegenerusGameStorage._creditAfking` etc. via
`V61Pack`, demonstrated KILLED in HARNESS-VALIDATION-v63.md §A) and the `StorageFoundation`
tail-pack canary — but NOT the `BitPackingLib.setPacked` mint-data path. Class = PACKING
IDENTITY (the storage-packing-breaks-slot landmine class), **not** a SPINE solvency/RNG hole.

**This is NOT a contract defect.** It exposes no required contract fix — it is an oracle gap.
It routes to Plan 03 as an oracle-hardening item: add a `setPacked` round-trip assertion
(write a field via `setPacked`, read it back, assert equality + sibling-field preservation;
ideally fuzz `data`/`shift`/`mask`/`value`). Such a test also kills the C1 mask-value
survivors above (it would feed an oversized `value` and assert the field bound), closing both
the C4 body gap and the C1 mask coverage in one assertion.

---

## SPINE-survivor flag

**No GENUINE survivor on a SPINE (solvency / RNG) target so far.** The one GENUINE survivor
(C4) is on the PACKING-IDENTITY class and is a test-coverage gap, not a behavioral defect.
The SPINE targets (`StakedDegenerusStonk` solvency, `DegenerusGameLootboxModule` /
`DegenerusGameDecimatorModule` RNG, the solvency helpers in `DegenerusGameStorage`) are
IN-PROGRESS / NOT RUN; any GENUINE survivor they produce on resume will be flagged SPINE
here prominently and re-verified at full runs.

---

## GENUINE set (the Plan-03 input)

| ID | Target | Line | Class | Nature | Plan-03 action |
|---|---|---|---|---|---|
| G-BPL-01 | `BitPackingLib.setPacked` | 110 | PACKING IDENTITY | oracle gap (no `setPacked` round-trip assertion); reachable 46-call-site primitive; survives full runs | add a `setPacked` round-trip / sibling-preservation assertion (also kills the C1 mask survivors) — TEST hardening, no contract change |

**No GENUINE survivor reveals a contract defect.** G-BPL-01 is a regression-net coverage
hole on a correct primitive; it does NOT require a `contracts/*.sol` change.

---

## Byte-freeze attestation

- `git rev-parse HEAD:contracts` == `2934d3d8987a09c5f073549a0cb499f6c5f28620`.
- `git diff a8b702a7 -- contracts/` — EMPTY.
- The C4 full-run re-verification mutation was the only in-place edit during triage; it was
  restored before this ledger was written. No commit was made while a mutant was in place.

**contracts/ byte-identical to `a8b702a7` after triage.**
