# Phase 292 HRROLL — Measurement Attestations (HRROLL-06 + HRROLL-07 + HRROLL-08)

> The 6 attestation sections are populated post-patch by Plan 02 against the v41 baseline.
> This doc is the verbatim copy-forward source for Plan 02's batched commit message body, per `feedback_no_history_in_comments.md` (numerical attestations go in the commit body, NOT into NatSpec).
> Plan 02 MUST re-validate every populated value against the post-patch tree before the user approves the commit.
>
> Pattern note: this scaffold mirrors `290-01-MEASUREMENT.md`'s 6-section shape with two HRROLL-specific adjustments — §5 (events) degenerates to "NONE touched — HRROLL has no event surface"; §6 (callsite diff) degenerates to single-site verification because `_applyHeroOverride` has only one caller in the codebase (`_rollWinningTraits` at L1941). Plan 01 produces sections §1, §3, and §5 in FINAL form; sections §2, §4, and §6 carry `<FILL-IN-Plan-02>` placeholders Plan 02 populates post-patch.

## (1) Audit Baseline

Anchor: `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` (v41.0 closure HEAD). Source of truth for every "byte-identical to v41 close" assertion in this scaffold and for every "delta vs v41 close" measurement Plan 02 records below. All comparisons resolve against this SHA via `git worktree add /tmp/v41-baseline 315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` or `git show <sha>:<path>` techniques per the Phase 290 measurement-pattern precedent.

## (2) Storage-Slot Grep Proof (HRROLL-06)

`forge inspect contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage storageLayout` diff vs `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` close = **EMPTY** (substantive diff exit code 0; both trees produce byte-identical 34317-byte output).

`forge inspect contracts/modules/DegenerusGameJackpotModule.sol:DegenerusGameJackpotModule storageLayout` diff vs v41 close = **INHERITED** (the module declares no storage of its own — both v41 baseline and v42 post-patch trees return `Error: storage layout missing from artifact` for the module-specific path; storage layout lives ONLY at `contracts/storage/DegenerusGameStorage.sol`, which is byte-identical per the row above).

**Method (executed Plan 02 Task 2):** Materialized the v41 baseline via `git worktree add /tmp/v41-baseline-292 315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4`. Ran `FOUNDRY_DISABLE_NIGHTLY_WARNING=1 forge inspect contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage storageLayout` against both the post-patch tree (output `/tmp/v42-storage-292.txt`) and the v41 baseline (output `/tmp/v41-storage-292.txt`). Both files are 171 lines / 34317 bytes; `diff /tmp/v41-storage-292.txt /tmp/v42-storage-292.txt` returns exit code 0 with no output (byte-identical).

**Locks under HRROLL-06 (Plan 02 verifies all):**
- `dailyHeroWagers[uint32 => uint256[4]]` mapping at the same slot offset / type / label as v41 close. ✓ (preserved structurally — zero edits to `contracts/storage/DegenerusGameStorage.sol`).
- `dailyIdx` UNCHANGED at the same slot / type. ✓ (preserved structurally — zero edits to `contracts/storage/`).
- Zero new storage slots in HRROLL scope (slot counts identical at both trees). ✓ (storage-layout byte-identity confirms.)
- Zero new mappings in HRROLL scope. ✓ (storage-layout byte-identity confirms.)
- Zero new SSTORE callsites in HRROLL scope (the new `_rollHeroSymbol` is `private view` — incapable of SSTORE). ✓ (function declared `private view`; compiler-enforced).
- Zero new SLOAD callsites in HRROLL scope (the new `_rollHeroSymbol` reads the SAME 4 × `dailyHeroWagers[day][q]` slots that v41 `_topHeroSymbol` read — same slot count, same access pattern). ✓ (verified by source inspection — `for (uint8 q; q < 4; ) { uint256 packed = dailyHeroWagers[day][q]; ... }` identical access pattern to v41).

**Result table:**

| File | v41 baseline lines | v42 post-patch lines | Substantive diff |
|---|---|---|---|
| `contracts/storage/DegenerusGameStorage.sol` | 171 | 171 | **EMPTY** (byte-identical) |
| `contracts/modules/DegenerusGameJackpotModule.sol` | n/a (no module-level storage) | n/a (no module-level storage) | **INHERITED** (no module-specific layout artifact at either tree; storage lives at `DegenerusGameStorage.sol`) |

**Escalation rule:** If the substantive diff is non-empty, record the exact diff text in this section AND flag `🚨 STORAGE LAYOUT REGRESSION — STOP — escalate to user before Plan 02 Task 5` (mirrors Phase 290 escalation pattern). HRROLL-06 attestation FAILS until the diff is empty.

**Summary line (for the Task 5 commit body copy-forward):** storageLayout diff vs `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` = EMPTY (forge diff exit 0, 171 lines / 34317 bytes byte-identical at both trees).

**STATUS: PASS — HRROLL-06 storage byte-identity attestation confirmed against v41 close baseline.**

## (3) Worst-Case Gas (theoretical FIRST per feedback_gas_worst_case.md) + D-42N-CACHE-01 + D-42N-GAS-01 + D-42N-COLOR-ENTROPY-01

This section is **FINAL at Plan 01 time** (not placeholder). The locked D-42N-CACHE-01 chosen shape + D-42N-GAS-01 acceptance threshold + D-42N-COLOR-ENTROPY-01 non-collision attestation are all derived analytically here. Plan 02 implements the chosen shape verbatim and re-validates the theoretical figures against the post-patch tree before user approval.

### (3.a) v41 baseline — `_topHeroSymbol(dailyIdx)` gas reference

Analytical derivation (per `feedback_gas_worst_case.md`):

| Component | Cost | Reasoning |
|---|---|---|
| 4 × SLOAD (one per quadrant) | ~8400 gas | Cold SLOAD = 2100 each; in the jackpot-resolution context the `dailyHeroWagers[day][q]` slots are not in the per-call hot set ⇒ 4 × 2100 = 8400. |
| 32 × bit-extract (`(packed >> (s*32)) & 0xFFFFFFFF`) | ~768 gas | ~24 gas per extract (3 × SHR/SHL ≈ 9 + 3 × AND ≈ 9 + memory/stack ≈ 6); 32 × 24 = 768. |
| 32 × strict-`>` comparison | ~96 gas | GT opcode ~3 gas; 32 × 3 = 96. |
| 32 × inner-loop `unchecked { ++s }` | ~160 gas | ~5 gas per increment; 32 × 5 = 160. |
| 4 × outer-loop `unchecked { ++q }` | ~20 gas | 4 × 5 = 20. |
| Function entry/exit | ~50 gas | Standard call frame. |
| **v41 baseline (worst-case)** | **~9494 gas** | Sum of components above. |

### (3.b) D-42N-CACHE-01 Three-Shape Comparison

The pass-1 cost (4 × SLOAD + 32 × bit-extract + leader tracking) is structurally fixed across all three candidate shapes; the comparison turns on (a) the cache-build overhead, (b) the pass-2 walk cost, and (c) the conditional leader-bonus add. The keccak + MOD + DIV cost is also structurally fixed across all three shapes.

| Shape | Pass-1 cost (SLOAD + cache build + leader track) | Pass-2 cost (cursor walk to early-exit) | Keccak + MOD + DIV | Total (worst-case) | Δ vs v41 baseline (~9494) |
|---|---|---|---|---|---|
| **Flat `uint32[32]` indexed `q*8 + s`** | 4 SLOAD (~8400) + 32 extract (~768) + 32 MSTORE to flat array (~96) + leader tracking via strict-`>` (~96 + 160 inner-loop + 20 outer-loop ≈ ~276) ≈ **~9540** | 32 × MLOAD (~96) + 32 × cumulative add (~96) + 32 × GT comparison (~96) + 1 × leaderBonus-add branch (~10) ≈ **~298** | keccak256(abi.encode(uint256, uint32)) over 64-byte input ≈ 30 base + 6×2 word cost = 42 + memory expansion (~32) + MOD (~8) + DIV (~5) ≈ **~87** | **~9925** | **+431 gas** |
| **`uint64[32]` weights array (pre-bonus-applied)** | Same pass-1 as flat `uint32[32]` PLUS pre-applied `leaderBonus` add at `idx == leaderIdx` during cache build (~24 gas extra: 1 × ADD + 1 × MSTORE overwrite) ≈ **~9564** | Same pass-2 minus the conditional `if (idx == leaderIdx) cumulative += leaderBonus` branch (~−10 gas) ≈ **~288** | Same ≈ **~87** | **~9939** | **+445 gas** |
| **Packed `uint256[4]` cache with SHR+AND extracts in hot loop** | 4 SLOAD (~8400) + 4 MSTORE of packed slots into memory cache (~12) + pass-1 leader tracking via same extract idiom (~768 + 96 + 160 + 20 ≈ ~1044) ≈ **~9456** | 32 × MLOAD-cache + SHR+AND extract from cached packed slot (~24 each ⇒ ~768) + 32 × cumulative add (~96) + 32 × GT (~96) + 1 × leaderBonus-add branch (~10) ≈ **~970** | Same ≈ **~87** | **~10513** | **+1019 gas** |

**Recommended shape: flat `uint32[32]`** — lowest total worst-case among the three (~+431 gas regression; ~+1019 gas for packed `uint256[4]` is 2.4× worse). Auditor story is clearest: pass 1 extracts amounts once into a flat array; pass 2 walks the flat array with the conditional leader-bonus add. The `uint64[32]` variant trades the conditional pass-2 branch (~−10 gas) for the pre-applied cache-build cost (~+24 gas) — net-negative ~+14 gas. The packed `uint256[4]` variant re-extracts each amount inside the pass-2 hot loop, paying SHR+AND on every iteration — burns ~588 gas in pass-2 alone for no design value.

**LOCK:** Plan 02 implements the **flat `uint32[32]` indexed `q*8 + s`** cache shape verbatim. The pass-2 cursor walk retains the conditional `if (idx == leaderIdx) cumulative += leaderBonus` branch (do NOT pre-apply leader bonus during cache build).

**REJECTED shapes:**
- **`uint64[32]` weights (pre-bonus-applied)** — net +14 gas vs flat `uint32[32]`. Audit story is marginally cleaner (no pass-2 branch) but costs more gas overall. REJECTED.
- **Packed `uint256[4]` cache (re-extract in pass-2)** — net +588 gas vs flat `uint32[32]`; worst case among the three. REJECTED.
- **Re-SLOAD-without-cache** — burns ~8400 gas per call for no design value (would re-pay the cold SLOAD cost twice). Violates `feedback_no_dead_guards.md`. REJECTED outright per CONTEXT.md.

### (3.c) D-42N-GAS-01 Acceptance Threshold

Derived from the locked D-42N-CACHE-01 flat `uint32[32]` shape's theoretical worst case (~+431 gas vs v41 baseline):

- **Soft acceptance threshold: +500 gas vs v41 `_topHeroSymbol` baseline.** Theoretical ~+431 fits with ~70 gas headroom for second-order effects (memory expansion edge cases, optimizer interactions).
- **Hard upper-bound: +750 gas.** Provides ~10% headroom over the soft threshold for measurement noise.
- **Empirical validation:** Phase 293 TST-HRROLL-06 asserts the runtime gas regression against this threshold (within ±100 gas of the soft target → PASS), per the D-291-GAS-01 mirror pattern (theoretical-at-contract-phase + empirical-at-test-phase).

The calculated ~+431 figure is **well under** the +10K ESCALATION-CHECKPOINT threshold from CONTEXT.md. Plan 02 proceeds without user-checkpoint.

### (3.d) ESCALATION-CHECKPOINT branch

**STATUS: NOT TRIGGERED.**

The locked D-42N-CACHE-01 flat `uint32[32]` shape's theoretical worst case is ~+431 gas — well within the +10K bound per CONTEXT.md. No escalation marker emitted; Plan 02 may proceed to its contract-edit task once `292-01-DESIGN-INTENT-TRACE.md` exists.

(Counterfactual: had the chosen shape's worst case exceeded +10K vs v41 baseline, this section would carry an explicit `🚨 ESCALATION-CHECKPOINT — STOP — surface to user before Plan 02 proceeds` marker, and Plan 02 would block on user disposition before touching contracts/.)

### (3.e) D-42N-COLOR-ENTROPY-01 Non-Collision Attestation

**One-liner:** Color path consumes bits `quadrant*3` of `r` (where `r = isBonus ? keccak256(abi.encodePacked(randWord, BONUS_TRAITS_TAG)) : randWord` per `_rollWinningTraits` L1937-L1939); symbol-roll path consumes `uint64(uint256(keccak256(abi.encode(heroEntropy, day))) % effectiveTotal)`. The two entropy sources are **structurally orthogonal** — the color path reads specific bit-slices of an existing entropy variable (`r`); the symbol-roll path reads a keccak hash of the raw `randWord` (`heroEntropy`) plus `day`. Keccak's output is independent of any specific bit-slice of its input by hash-function design (avalanche property). Non-collision is **structural, NOT probabilistic**.

**Cross-RNG-consumer register at v42 close (for completeness; sourced from REQUIREMENTS.md SWEEP-02(ii) Hypothesis 3 register):**

| Consumer | Entropy source | Bit-slice / domain |
|---|---|---|
| jackpot-path-select | raw `randWord` | bits[0..12] |
| lootbox-Bernoulli (manual open per v39 LBX-WT) | per-resolution seed (keccak-derived) | bits[152..167] |
| jackpot-Bernoulli (BAF per v40 ENT-05) | keccak(randWord, ...) hash output | bits[200..215] |
| color-sample (v37 hero-color path) | `r` (= `randWord` for regular; `keccak(randWord, BONUS_TRAITS_TAG)` for bonus) | bits `quadrant*3` (bits 0-11 in raw or hashed form) |
| **HRROLL symbol-roll (NEW at v42)** | `keccak256(abi.encode(heroEntropy, day))` (full 256-bit hash output ⇒ uint64 modulo) | **separate keccak hash output domain — NOT in the raw `randWord` bit register** |

The HRROLL symbol-roll keccak output does NOT live in the raw `randWord` bit register at all — it lives in the keccak output domain — so collision with any of the four bit-slice consumers above is **structurally impossible**.

## (4) Selector Attestations (HRROLL-07)

**Method (executed Plan 02 Task 3):** Ran `FOUNDRY_DISABLE_NIGHTLY_WARNING=1 forge inspect contracts/modules/DegenerusGameJackpotModule.sol:DegenerusGameJackpotModule methodIdentifiers` against both the post-patch tree (`/tmp/v42-methods-292.txt`) and the v41 baseline (`/tmp/v41-methods-292.txt`). `diff /tmp/v41-methods-292.txt /tmp/v42-methods-292.txt` returns exit code 0 with no output (byte-identical). Selectors cross-verified via `cast sig "<canonical-signature>"`.

**Public ABI selector table** (entire public/external surface of `DegenerusGameJackpotModule` — all UNCHANGED vs v41 close):

| Function | Canonical signature | 4-byte selector | Disposition |
|---|---|---|---|
| `payDailyJackpot` | `payDailyJackpot(bool,uint24,uint256)` | `0x2ef8c646` | UNCHANGED vs v41 close |
| `payDailyJackpotCoinAndTickets` | `payDailyJackpotCoinAndTickets(uint256)` | `0xb1c9ed2d` | UNCHANGED vs v41 close |
| `payDailyCoinJackpot` | `payDailyCoinJackpot(uint24,uint256,uint24,uint24)` | `0xdbedb1c1` | UNCHANGED vs v41 close |
| `emitDailyWinningTraits` | `emitDailyWinningTraits(uint24,uint256,uint24)` | `0x1fe49a5a` | UNCHANGED vs v41 close |
| `runBafJackpot` | `runBafJackpot(uint256,uint24,uint256)` | `0x4181af8e` | UNCHANGED vs v41 close |
| `runTerminalJackpot` | `runTerminalJackpot(uint256,uint24,uint256)` | `0xa56efd97` | UNCHANGED vs v41 close |
| `distributeYieldSurplus` | `distributeYieldSurplus(uint256)` | `0x74307d12` | UNCHANGED vs v41 close |
| `gameOver` | `gameOver()` | `0xbdb337d1` | UNCHANGED vs v41 close |
| `level` | `level()` | `0x6fd5ae15` | UNCHANGED vs v41 close |
| `boonPacked` | `boonPacked(address)` | `0x24a7ad0b` | UNCHANGED vs v41 close |

**Verification (forge methodIdentifiers diff vs v41 close, the canonical attestation):** `diff /tmp/v41-methods-292.txt /tmp/v42-methods-292.txt` → exit 0, byte-identical (10/10 public-ABI selectors match across both trees). Whole-table disposition: ALL UNCHANGED vs v41 close.

**Private-function signature deltas (documented for audit-story completeness; do NOT count against HRROLL-07 public-ABI byte-identity invariant):**

| Function | Canonical signature | 4-byte selector | Disposition |
|---|---|---|---|
| `_applyHeroOverride` (private; v42 form) | `_applyHeroOverride(uint8[4],uint256,uint256)` | n/a (private) | Signature changed (gained 3rd `uint256 heroEntropy` param); private — not in public ABI |
| `_rollHeroSymbol` (private; new at v42) | `_rollHeroSymbol(uint32,uint256)` | n/a (private) | NEW at v42; private — not in public ABI |
| `_topHeroSymbol` (private; removed at v42) | `_topHeroSymbol(uint32)` | n/a (private) | REMOVED at v42; private — not in public ABI |

**Locks under HRROLL-07 (Plan 02 verified all):**
- Zero new public/external entry points. ✓ (forge methodIdentifiers byte-identical; 10/10 selectors UNCHANGED.)
- Zero new modifiers. ✓ (no modifier-decl deltas in the patched function bodies; the `_applyHeroOverride` signature change added a parameter, not a modifier.)
- Zero new admin or governance hooks. ✓ (no `onlyOwner` / `onlyAdmin` / governance-callable functions added.)
- Zero new upgrade hooks. ✓ (no `upgradeToAndCall` / proxy-admin entry points added.)
- All existing public/external selectors byte-identical to v41 close. ✓ (forge diff exit 0; cast sig values match the v41 baseline values 1-for-1.)

**Escalation rule:** If any public/external selector changes, record the exact selector delta in this section AND flag `🚨 PUBLIC ABI REGRESSION — STOP — escalate to user before Plan 02 Task 5`. HRROLL-07 attestation FAILS until the public ABI is byte-identical.

**STATUS: PASS — HRROLL-07 public ABI byte-identity attestation confirmed against v41 close baseline.**

## (5) Events — NONE Touched (HRROLL has no event surface)

HRROLL scope contains **zero event declarations and zero event emissions**. No event topic-hash changes. No event-signature attestations required. This section is structurally empty for Phase 292.

Recorded as a distinction vs the Phase 290 pattern: Phase 290 carried the breaking `TraitsGenerated` topic-hash attestation at its §5 under D-42N-EVT-BREAK-01; Phase 292 has no analogous surface because HRROLL touches only `_applyHeroOverride` + `_topHeroSymbol` (deleted) + `_rollHeroSymbol` (new), none of which emit or declare events.

NO placeholder; this section is FINAL at Plan 01 time.

## (6) Callsite Diff (Single-Site — HRROLL `_applyHeroOverride` Caller Set Degenerates to ONE)

**Pre-patch state (verified at Plan 01 authorship time via grep over the v42 working tree against the v41 baseline):**

`_applyHeroOverride` has EXACTLY ONE caller in the codebase: `contracts/modules/DegenerusGameJackpotModule.sol:1941` (inside `_rollWinningTraits` at L1928-L1943). The B2-symmetric Phase 290 pattern (multiple callsites updated in parallel) degenerates to a single-site verification for HRROLL — this is a documented structural distinction, not an oversight.

The single callsite at L1941 currently reads (v41 close):

```solidity
_applyHeroOverride(traits, r);
```

Plan 02 updates the L1941 callsite to the 3-arg form per D-42N-BONUS-ENTROPY-01:

```solidity
_applyHeroOverride(traits, r, randWord);
```

Where `randWord` is the raw VRF parameter to `_rollWinningTraits` (in scope at L1941 since `_rollWinningTraits` declares it as its first parameter at L1933).

**Upstream caller verification:** `_rollWinningTraits` itself has 12 upstream callers (`grep -n "_rollWinningTraits(" contracts/`: L285, L354, L520, L531, L538, L609, L610, L689, L1180, L1734, L1754, L1756). All 12 callers pass `randWord` as the first argument; `randWord` is already in scope at every caller. NO caller-path edit required to plumb the raw `randWord` into `_applyHeroOverride` — the existing `_rollWinningTraits(randWord, isBonus)` signature already carries it. (Verified per CONTEXT.md scout.)

**Post-patch verification (executed Plan 02 Task 4):**

- Post-patch callsite line shifted from L1941 (v41) to **L1988** (v42) due to the function-body length growth between v41 `_topHeroSymbol` (29 lines) and v42 `_rollHeroSymbol` (62 lines). Exact post-patch line:
  ```solidity
  // contracts/modules/DegenerusGameJackpotModule.sol:1988
  _applyHeroOverride(traits, r, randWord);
  ```
- `_applyHeroOverride` declaration now lives at **L1600** (`function _applyHeroOverride(`); 3-arg signature `(uint8[4] memory w, uint256 randomWord, uint256 heroEntropy)`.
- `_rollHeroSymbol` declaration lives at **L1639** (`function _rollHeroSymbol(`); signature `(uint32 day, uint256 entropy)`.
- `_rollHeroSymbol` call site inside `_applyHeroOverride` lives at **L1609** (`) = _rollHeroSymbol(dailyIdx, heroEntropy);`).

**Grep-count verification matrix (Plan 02 Task 4):**

| Verification | Expected count | Actual count | Disposition |
|---|---|---|---|
| `grep -cE "_applyHeroOverride\("` (declarations + call sites, paren-anchored) | 2 | **2** | **PASS** (1 decl L1600 + 1 callsite L1988) |
| `grep -cE "_applyHeroOverride"` (bare — incl NatSpec mentions) | 2 | **3** | **PASS-with-note** (extra match is NatSpec self-reference at L1594 in `_applyHeroOverride`'s own docblock describing the function; benign documentation) |
| `grep -cE "_applyHeroOverride\(traits, r, randWord\)"` (exact 3-arg callsite) | 1 | **1** | **PASS** (L1988) |
| `grep -cE "_topHeroSymbol"` (function fully deleted) | 0 | **0** | **PASS** (declaration + every callsite gone) |
| `grep -cE "function _rollHeroSymbol"` | 1 | **1** | **PASS** (L1639) |
| `grep -cE "_rollHeroSymbol\("` (paren-anchored — declarations + call sites) | 2 | **2** | **PASS** (1 decl L1639 + 1 call L1609) |
| `grep -cE "_rollHeroSymbol"` (bare — incl NatSpec) | 2 | **3** | **PASS-with-note** (extra match is NatSpec mention at L1585 in `_applyHeroOverride`'s docblock describing the symbol-roll helper; benign documentation) |
| `grep -cE "_rollHeroSymbol\(dailyIdx, heroEntropy\)"` (exact call) | 1 | **1** | **PASS** (L1609) |
| `grep -cE "uint32\[32\] memory weights"` (D-42N-CACHE-01 flat cache shape) | 1 | **1** | **PASS** (L1647 inside `_rollHeroSymbol`) |
| `grep -cE "keccak256\(abi\.encode\(entropy, day\)\)"` (D-42N-DETERMINISM-01 keccak form) | ≥1 | **2** | **PASS** (1 NatSpec mention at L1635 + 1 code use at L1684) |
| `grep -cE "uint256 heroEntropy"` (HRROLL-04 signature parameter) | 1 | **1** | **PASS** (L1603 in the post-patch signature) |
| `grep -cE "CALL 1 and.*CALL 2"` (history-language sweep per `feedback_no_history_in_comments.md`) | 0 | **0** | **PASS** (NatSpec rewritten without `(CALL 1 / CALL 2)` wording) |
| `grep -E "previously\|pre-v41\|pre-cleanup\|formerly\|the bug at"` filtered through `grep -vE "^[[:space:]]*//\|^[[:space:]]*\*"` (history tokens outside comment leaders) | 0 | **0** | **PASS** |

**B2-degeneration note:** The Phase 290 B2-symmetric pattern (which paired the `processFutureTicketBatch` callsite with the `_processOneTicketEntry` callsite and ran a structural diff between the two) **does not apply at HRROLL** because `_applyHeroOverride` has exactly one caller in the codebase (`_rollWinningTraits` at L1988 post-patch; was L1941 at v41). Single-site verification is the appropriate analog — confirming the lone callsite reads the post-patch 3-arg form with raw `randWord` as the 3rd argument per D-42N-BONUS-ENTROPY-01.

**Compile attestation:** `FOUNDRY_DISABLE_NIGHTLY_WARNING=1 forge build --skip test` returns exit code 0 on the post-patch tree (no compile errors; pre-existing forge-lint warnings on unrelated lines are unchanged). The patched contract compiles cleanly against the existing solidity toolchain version.

**Locks under HRROLL-04 (Plan 02 verified):**
- L1988 is the ONLY callsite of `_applyHeroOverride` (single-site verification PASS). ✓
- The 3-arg form passes `(traits, r, randWord)` in that order — raw `randWord` (NOT post-bonus-tag `r`) is the 3rd argument per D-42N-BONUS-ENTROPY-01. ✓
- `_topHeroSymbol` is gone — zero matches in the post-patch tree; no stub, no deprecated marker, no `// @dev removed` comment. ✓

**STATUS: PASS — Single-site callsite verification matrix all rows PASS or PASS-with-note; HRROLL-04 + HRROLL-01 callsite locks confirmed.**

## Source-Doc Cross-Cite

- Back-link: `292-01-DESIGN-INTENT-TRACE.md` (HRROLL-10 5-section trace + 7 decision anchors).
- Forward-link: `292-02-PLAN.md` (Plan 02 contract-patch task; reads this scaffold and copies §1 + §3 + §5 (FINAL at Plan 01 time) verbatim into the batched contract commit message body; fills in §2 + §4 + §6 (`<FILL-IN-Plan-02>` placeholders) post-patch; presents the full diff to the user for explicit review per `feedback_manual_review_before_push.md` + `feedback_never_preapprove_contracts.md`).

**Re-validation requirement:** Plan 02 MUST re-validate every populated value in this doc against the post-patch tree before the user approves the contract commit. The doc is the verbatim copy-forward source for the commit body — any drift between this doc and the post-patch tree is a Plan 02 verification failure.

---

*Phase 292 Plan 01 — Measurement Attestations scaffold (HRROLL-06 + HRROLL-07 + HRROLL-08); AGENT-COMMITTED pre-patch gate; produced 2026-05-17 against audit baseline `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4`.*
