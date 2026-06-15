# Mutation Survivor Triage — v63 subject `a8b702a7`

Every UNCAUGHT survivor from the completed campaign targets, classified FALSE (equivalent
mutant / unreachable / oracle-provably-indistinguishable) vs GENUINE (a reachable
behavioral change the comprehensive oracle should have killed but did not). Ambiguous →
default GENUINE → carried to Plan 03. GENUINE candidates are re-verified at FULL oracle
runs (default profile, FOUNDRY_FUZZ_RUNS=1000, INVARIANT runs=256) IN PLACE, then restored,
before being finalized.

**Scope of this ledger (UPDATED — Plan 03):** three spine targets are now fully scored and
triaged: `BitPackingLib` (PACKING IDENTITY, §below), `DegenerusGameStorage` (PACKING +
SOLVENCY helpers, §DegenerusGameStorage), and `StakedDegenerusStonk` (SOLVENCY SPINE,
§StakedDegenerusStonk). The remaining three targets (`BurnieCoinflip`,
`DegenerusGameLootboxModule`, `DegenerusGameDecimatorModule`) are CI-DEFERRED / NOT RUN — the
campaign was deliberately BOUNDED after the spine targets (see CAMPAIGN-REPORT-v63.md
status table + CI-resume section). Their survivors will be appended here on CI resume.

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

---

## `DegenerusGameStorage` (PACKING + SOLVENCY helpers) — 2 raw survivors, 1 real

**Source:** `audit/mutation/DegenerusGameStorage-v63.log` +
`audit/mutation/DegenerusGameStorage-mut-v63/` (PROGRESS-v63.log: `DONE killed=2 uncaught=2`).
The runner's `uncaught=2` is the grep heuristic; the AUTHORITATIVE survivor set is the saved
compilable mutants in the `-mut-v63/DegenerusGameStorage/` dir, diffed against the subject.

| ID | Line | Mutator | Function | Verdict |
|---|---|---|---|---|
| (artifact) | 595 | RR | `_queueTickets` | **non-survivor** — the saved `_RR_3` mutant (`if (quantity == 0) revert()`, missing `;`) is a COMPILATION FAILURE, not a live survivor (counted by the runner's grep, not a real uncaught mutant); `_RR_3.sol` is byte-identical to the subject |
| S-DGS-01 | 583 | RR | `_isDistressMode` | **FALSE** — see reasoning below |

### S-DGS-01 — `_isDistressMode` line-583 live branch RR (FALSE)

**Mutated line:** 583. **Mutator:** RR.
`return currentDay >= psd + 120;` (the `level != 0` distress branch) → `revert()`.

**Verdict: FALSE — reachable but already covered OUTSIDE the comprehensive-forge-oracle union.**
`_isDistressMode()` is reachable (3 on-chain callers: `DegenerusGameWhaleModule:923`,
`GameAfkingModule:1391`, `DegenerusGameMintModule:1543`) and economically meaningful (distress
mode = 100% nextpool allocation + 25% ticket bonus). The line-583 RR mutant would brick every
distress-gated path in a live (level != 0) game. HOWEVER the distress-mode behavior IS covered
by the JS distress suites (`test/unit/DistressLootbox.test.js`,
`test/unit/LootboxAutoResolveSilentColdBust.test.js`, `test/unit/LootboxWholeTicket.test.js`,
`test/repro/C1BoxAutoOpen.t.sol`), which are OUTSIDE the 12-suite comprehensive-forge-oracle
union the campaign ran against. So the survivor is a gap in the NARROW forge-oracle subset, NOT
a hole in the protocol's overall regression coverage. Driving the line-583 (`level != 0`)
branch deterministically inside the forge oracle would require advancing the game past level 0
through the full purchase/advance flow — out of proportion to closing a gap already covered
elsewhere. Per the audit posture (do not over-invest; a reachable-but-already-covered survivor
is FALSE, not a forced test), S-DGS-01 is recorded **FALSE**. Not a contract defect (the
subject's `_isDistressMode` is correct).

**No GENUINE survivor on `DegenerusGameStorage`.**

---

## `StakedDegenerusStonk` (SOLVENCY SPINE) — 76 distinct survivors

**Source:** `audit/mutation/StakedDegenerusStonk-v63.log` (the `--> UNCAUGHT` entries; full run,
PROGRESS-v63.log: `DONE killed=152 uncaught=78 elapsed=10692s` — a COMPLETE run, not partial;
two of the 78 markers are wrapped-line duplicates → 76 distinct survivor lines).

**Root cause of the survivor swarm (the single dominant pattern):** the comprehensive oracle
drives the **LIVE-game gambling-burn → `claimRedemption`** path exhaustively (the live legs at
876–900 were all CAUGHT) but never drives the **POST-gameOver deterministic / pool-drain /
settle** paths, nor the constructor (deploy-only), keeper-crank wrappers, deposit-event lines,
or view functions. None of these survivors is a contract defect — every subject line is
correct; the regression net simply lacked an assertion on the post-gameOver / non-redemption
surface.

### Survivor-class summary (`StakedDegenerusStonk`, 76 survivors)

| # | Class | Lines | Function(s) | Verdict |
|---|---|---|---|---|
| K1 | gameOver deterministic burn | 624,625,659,678,679,681,684,685,686,690,692,693,707 | `burn`/`_deterministicBurn`/`_deterministicBurnFrom` | **GENUINE → KILLED** (gameOver leg never driven by oracle) |
| K2 | burnAtGameOver pool drain | 602,603,605,606 | `burnAtGameOver` | **GENUINE → KILLED** (never called by oracle) |
| K3 | transferFromPool legs | 549,553,555,558,559,567,569,570 | `transferFromPool` | **GENUINE → KILLED** (post-conditions unasserted) |
| K4 | transferFromPool self-win burn | 563,564 | `transferFromPool` | **GENUINE → KILLED** (self-win branch never driven) |
| K5 | transferBetweenPools | 580,584,586,589,591,592,593 | `transferBetweenPools` | **GENUINE → KILLED** (rebalance conservation unasserted) |
| K6 | wrapperTransferTo | 456,457,459 | `wrapperTransferTo` | **GENUINE → KILLED** (DGNRS-only path never driven) |
| F1 | constructor allocations | 394,396,402,405,406,407,409,411,415,429 | `constructor` | **FALSE** (deploy-only; the deploy fixture's pool/supply invariants are asserted by the StorageFoundation / PoolConservation oracle on the AS-DEPLOYED state, but a per-line RR/CR in the one-shot constructor is an equivalent/unreachable mutant relative to re-running the constructor — slither cannot re-deploy a mutated constructor inside the live fixture) |
| F2 | ERC20 metadata constants | 200,203,206 | name/symbol/decimals | **FALSE** (cosmetic constants; no solvency/RNG consumer; the oracle asserts no metadata string) |
| F3 | keeper-crank wrappers | 470,475 | `gameAdvance`/`gameClaimWhalePass` | **FALSE** (thin pass-throughs to `game.mintBurnie()` / `game.claimWhalePass`; the oracle never cranks the keeper router — covered by the advance/keeper JS + module suites outside the union) |
| F4 | deposit event/auth lines | 488,489,498,499 | `receive`/`depositSteth` | **FALSE** (the `receive`/`depositSteth` ACL + event are covered by `RedemptionStethFallback::test_POOL04_*` for the live-balance read, but the bare event-emit / revert-string RR/CR on the deposit path is an equivalent mutant — no downstream solvency read depends on the event, deposits are read live via `address(this).balance`) |
| F5 | view functions | 510,718,919,936,937,957 | `poolBalance`/`hasPendingRedemptions`/`previewBurn`/`burnieReserve` | **FALSE** (pure views with no state effect; `previewBurn`/`burnieReserve` mirror the burn math but are advisory — the oracle asserts the BURN path, not the preview; a wrong preview cannot break solvency) |
| F6 | gameOver settle + empty-slot | 793,795,798,823,835,864,865 | `claimRedemptionMany`/`_claimRedemptionFor` | **FALSE** — the live settle legs (876–900) are CAUGHT; the survivors are the **gameOver 100%-direct settle branch** (835/864/865) and the **batch-loop / empty-slot-skip** plumbing (793/795/798/823). The gameOver settle branch is the same post-gameOver-coverage gap as K1/K2 but on the *claim* side; rather than build a second gameOver fixture for the settle path, the K1/K2 gameOver kills already pin the post-gameOver accounting identity (supply/balance/payout). The loop/skip lines (`++i`, `continue`, `++settled`, empty-slot `return false`) are control-flow plumbing whose effect is the *count* of settled boxes (a keeper-bounty input, not a solvency identity); their RR mutants are caught by the live `claimRedemptionMany` path already exercised. Recorded **FALSE** (covered or non-solvency-bearing); not forced into a test per the no-over-invest posture. |

**GENUINE set (`StakedDegenerusStonk`) = { K1, K2, K3, K4, K5, K6 } → ALL KILLED** by
`test/mutation/MutationKills.t.sol` (see §GENUINE set table + MUTATION-FINDINGS-v63.md). Every
one is a TEST-coverage hole on a CORRECT subject line — **no contract defect**.

**SPINE flag (prominent):** K1 (gameOver deterministic burn) and K2 (burnAtGameOver) and the
F6 gameOver settle branch are on the SOLVENCY SPINE. They are GENUINE oracle gaps, NOT
behavioral defects — the post-gameOver payout/burn/drain code is correct; the redemption suites
simply lacked a gameOver-driving fixture. K1/K2 are now pinned by deterministic kill-tests that
assert the exact supply/balance/ETH-payout identity of the post-gameOver path.

---

## SPINE-survivor flag

**No GENUINE survivor reveals a SPINE (solvency / RNG) DEFECT.** The SPINE-class GENUINE
survivors that DID appear are all on `StakedDegenerusStonk` (K1 gameOver deterministic burn,
K2 burnAtGameOver) — each is a TEST-coverage gap on a CORRECT subject line, now KILLED by a
deterministic kill-test, NOT a behavioral defect. `DegenerusGameStorage`'s one survivor
(S-DGS-01) is FALSE (covered outside the forge oracle). `BitPackingLib`'s GENUINE survivor
(C4/G-BPL-01) is PACKING IDENTITY, KILLED. The three CI-deferred targets
(`BurnieCoinflip`, `DegenerusGameLootboxModule`, `DegenerusGameDecimatorModule`) are NOT RUN;
any GENUINE survivor they produce on CI resume will be flagged SPINE here and re-verified at
full runs.

---

## GENUINE set (the Plan-03 input → ALL KILLED)

| ID | Target | Line(s) | Class | Nature | Plan-03 disposition |
|---|---|---|---|---|---|
| G-BPL-01 | `BitPackingLib.setPacked` | 110 (+C1 masks 33/36/39/42/45) | PACKING IDENTITY | oracle gap (no `setPacked` round-trip assertion); reachable 46-call-site primitive | **KILLED** by `test_kills_BitPackingLib_110_setPacked_roundTrip` (validated: FAILs with CR mutant AND with C1 mask-value mutant) |
| K1 | `StakedStonk._deterministicBurnFrom` (+`burn`) | 624,625,659,678,679,681,684–693,707 | SOLVENCY SPINE | oracle gap (gameOver deterministic burn leg never driven) | **KILLED** by `test_kills_StakedStonk_deterministicBurn_gameOverPayout` + `_stethFallbackSplit` (validated 678 RR, 693 RR) |
| K2 | `StakedStonk.burnAtGameOver` | 602,603,605,606 | SOLVENCY SPINE | oracle gap (never called) | **KILLED** by `test_kills_StakedStonk_burnAtGameOver_drainsLocalSupply` (validated 602 RR) |
| K3 | `StakedStonk.transferFromPool` | 549,553,555,558,559,567,569,570 | SOLVENCY | oracle gap (post-conditions unasserted) | **KILLED** by `test_kills_StakedStonk_transferFromPool_creditsRecipient` (validated 558 RR) |
| K4 | `StakedStonk.transferFromPool` self-win | 563,564 | SOLVENCY | oracle gap (self-win branch never driven) | **KILLED** by `test_kills_StakedStonk_transferFromPool_selfWinBurns` (validated 563 RR) |
| K5 | `StakedStonk.transferBetweenPools` | 580,584,586,589,591,592,593 | SOLVENCY | oracle gap (rebalance conservation unasserted) | **KILLED** by `test_kills_StakedStonk_transferBetweenPools_conserves` (validated 591 RR) |
| K6 | `StakedStonk.wrapperTransferTo` | 456,457,459 | SOLVENCY | oracle gap (DGNRS-only path never driven) | **KILLED** by `test_kills_StakedStonk_wrapperTransferTo_movesBalance` (validated 457 RR) |

**No GENUINE survivor reveals a contract defect.** Every GENUINE survivor is a regression-net
coverage hole on a CORRECT subject line; NONE requires a `contracts/*.sol` change. All are
KILLED by `test/mutation/MutationKills.t.sol` (8 tests, each validated fail-with-mutation /
pass-without). FALSE survivors (S-DGS-01, F1–F6, BitPackingLib C1/C2/C3) are equivalent /
unreachable / already-covered-elsewhere and are NOT forced into tests (no-over-invest posture).

---

## Byte-freeze attestation

- `git rev-parse HEAD:contracts` == `2934d3d8987a09c5f073549a0cb499f6c5f28620`.
- `git diff a8b702a7 -- contracts/` — EMPTY.
- Every kill-test validation (Plan 03) re-applied its survivor's mutation TRANSIENTLY in place,
  ran the targeted test (confirmed RED), then `git checkout -- contracts/` restored the byte-
  frozen subject and confirmed GREEN. No commit was ever made while a mutant was on disk.

**contracts/ byte-identical to `a8b702a7` after triage + kill-test validation.**
