# Phase 259: Trait Distribution Split - Context

**Gathered:** 2026-05-08
**Status:** Ready for planning

<domain>
## Phase Boundary

`contracts/DegenerusTraitUtils.sol` implements the heavy-tail color distribution (25/25/25/12.5/6.25/3.125/2.344/0.781% over 256-resolution thresholds) via a single `weightedColorBucket(uint32) → uint8` while preserving the `[QQ][CCC][SSS]` byte layout and the symbol slice. Legacy `weightedBucket(uint32)` is fully removed; both in-`contracts/` consumers (`DegenerusGameMintModule`, `DegenerusGameDegeneretteModule`) reach the new distribution transparently because the `traitFromWord(uint64)` and `packedTraitsFromSeed(uint256)` external signatures are byte-stable.

In scope:
- Replace `weightedBucket` body with the new 256-resolution color thresholds; rename to `weightedColorBucket`.
- Rewrite `traitFromWord(uint64)`: `color = weightedColorBucket(uint32(rnd))`, `symbol = uint8(rnd >> 32) & 7`, return `(color << 3) | symbol`.
- Preserve `packedTraitsFromSeed(uint256)` quadrant flags (`| 64`, `| 128`, `| 192`).
- Add `contracts/test/TraitUtilsTester.sol` test harness (PriceLookupTester pattern).
- Add `test/unit/DegenerusTraitUtils.test.js` (Hardhat) covering boundary + composition + byte-layout.
- Rewrite the file-header ASCII block, natspec, and local variables to color/symbol terminology.
- Audit `contracts/` for residual `weightedBucket` references (word-boundary grep).

Out of scope (deferred to Phase 260+):
- `_pickSoloQuadrant` injection in `DegenerusGameJackpotModule.sol` — Phase 260.
- Statistical (1M-sample) validation — Phase 261.
- Cross-surface verification of Hero override / deity-pass / Degenerette — Phase 261.
- Gas regression tests vs v33.0 baseline — Phase 261.
- Findings consolidation — Phase 262.

</domain>

<decisions>
## Implementation Decisions

### Test Harness
- **D-01:** New `contracts/test/TraitUtilsTester.sol` exposes ALL three trait-utils functions as `external pure` passthroughs: `weightedColorBucket(uint32)`, `traitFromWord(uint64)`, `packedTraitsFromSeed(uint256)`. Mirrors the `contracts/test/PriceLookupTester.sol` pattern. Required because all three target functions are `internal pure` and Hardhat cannot invoke them from JS without a wrapper.

### Comment / Natspec Terminology
- **D-02:** Switch terminology in `contracts/DegenerusTraitUtils.sol` fully to **color/symbol** throughout: top-of-file ASCII block, every natspec doc-comment, and every local variable name (`category` → `color`, `sub` → `symbol`). Per `feedback_no_history_in_comments.md` comments describe what IS — the new distribution justifies the new terms.
- **D-03:** Rewrite the WEIGHTED DISTRIBUTION ASCII table in the header comment to the new heavy-tail percentages (25/25/25/12.5/6.25/3.125/2.344/0.781% over 256-resolution thresholds) with the corresponding `[0,64) [64,128) [128,192) [192,224) [224,240) [240,248) [248,254) [254,256)` ranges.
- **D-04:** Update the TRAIT ID STRUCTURE box (currently uses "Category bucket" / "Sub-bucket"): rename the bit-field labels to "Color tier" / "Symbol".
- **D-05:** No history comments. The legacy 13.3%-each / 75-bucket table is deleted — never commented out, never preserved as a "previous" block. Function `weightedBucket` is structurally removed (TRAIT-01).

### TRAIT-04 Verification (legacy removal proof)
- **D-06:** Locked verification command: `grep -rwn "weightedBucket" contracts/` (the `-w` flag enforces word boundaries so the new `weightedColorBucket` does not false-match). Must return zero hits at phase close. This is the canonical TRAIT-04 acceptance check.

### Test File Layout
- **D-07:** Single Hardhat unit-test file `test/unit/DegenerusTraitUtils.test.js` with three `describe` blocks:
  1. `weightedColorBucket(uint32)` — 16 boundary cases per success criterion #1 (`scaled = 0, 63, 64, 127, 128, 191, 192, 223, 224, 239, 240, 247, 248, 253, 254, 255`), each asserting the expected color tier 0-7. Boundary inputs are computed by reverse-mapping `scaled` to a `rnd` value such that `uint32((uint64(rnd) * 256) >> 32) == scaled`.
  2. `traitFromWord(uint64)` — isolated-bit tests proving low 32 bits drive color via `weightedColorBucket` and high 32 bits drive symbol via `& 7`; verify the bit-slice composition `(color << 3) | symbol` end-to-end.
  3. `packedTraitsFromSeed(uint256)` — byte-layout assertions confirming quadrant flags `0/64/128/192` on the four packed traits and that the result fits in 32 bits.
- **D-08:** Matches existing per-contract test convention (`test/unit/DegenerusGame.test.js`, `BurnieCoin.test.js`, `DegenerusJackpots.test.js`, etc.). No split per function.
- **D-09:** Existing Foundry fuzz `test/fuzz/DegeneretteFreezeResolution.t.sol:354` consumes `packedTraitsFromSeed` and is the implicit byte-layout regression test ("existing byte-layout tests pass without modification" in success criterion #3) — run unchanged at phase close to confirm.

### Approval & Commit Posture (carried forward)
- **D-10:** All `contracts/` and `test/` edits in this phase are batched and presented as one diff at the end of the phase per `feedback_batch_contract_approval.md`; user approval is explicit per commit (no orchestrator pre-approval) per `feedback_no_contract_commits.md` and `feedback_never_preapprove_contracts.md`.
- **D-11:** Skip research-agent dispatch per `feedback_skip_research_test_phases.md` — phase is fully specified in REQUIREMENTS.md (TRAIT-01..06) with exact signatures, thresholds, and boundary cases. Plan directly.

### Claude's Discretion
- Choice of how to construct boundary `rnd` values that map cleanly to the requested `scaled` values in the Hardhat tests (math is mechanical; planner picks the form).
- Exact wording of natspec doc-comments after the terminology switch — semantics locked, prose is incidental.
- Whether to keep the file-header ASCII border style (`+==...==+`) or simplify; planner default is "preserve existing style for visual consistency."

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & roadmap
- `.planning/REQUIREMENTS.md` — TRAIT-01..06 (exact function signatures, threshold table, boundary test enumeration, color tier frequency table) and the `[QQ][CCC][SSS]` bit-layout reference. Locked source of truth.
- `.planning/ROADMAP.md` §"Phase 259" — Goal statement, Success Criteria 1-4, Depends-on (none — first impl phase; baseline v33.0 HEAD `4ce3703d740d3707c88a1af595618120a8168399`).

### Contracts under change
- `contracts/DegenerusTraitUtils.sol` — Library being rewritten (only file with logic edits).
- `contracts/test/TraitUtilsTester.sol` — NEW file (test harness, PriceLookupTester pattern).
- `contracts/test/PriceLookupTester.sol` — Reference pattern for the new harness.

### Caller surfaces (no change required, behavior verification only)
- `contracts/modules/DegenerusGameMintModule.sol:581` — calls `DegenerusTraitUtils.traitFromWord(s)` to derive trait IDs during ticket trait sampling. Signature preserved → byte-stable.
- `contracts/modules/DegenerusGameDegeneretteModule.sol:607` — calls `DegenerusTraitUtils.packedTraitsFromSeed(resultSeed)` to derive Degenerette spin ticket. Byte layout preserved → signature stable.
- `test/fuzz/DegeneretteFreezeResolution.t.sol:354` — Foundry fuzz; consumes `packedTraitsFromSeed` (byte-layout regression).

### Memory / feedback governing this phase
- `feedback_no_contract_commits.md` — explicit per-commit user approval for all `contracts/` + `test/` changes.
- `feedback_batch_contract_approval.md` — batch all phase edits, present one diff at the end.
- `feedback_never_preapprove_contracts.md` — orchestrator must NOT tell agents anything is pre-approved.
- `feedback_no_history_in_comments.md` — comments describe what IS; no "previously was" or "changed from".
- `feedback_skip_research_test_phases.md` — skip research-agent dispatch for mechanical phases.
- `feedback_wait_for_approval.md` — present fix and wait for explicit approval before editing.
- `feedback_manual_review_before_push.md` — never push contract changes without diff review.

### Milestone & state
- `.planning/PROJECT.md` — v34.0 milestone goal and contract HEAD anchor.
- `.planning/STATE.md` — current focus (Planning Phase 259).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`contracts/test/PriceLookupTester.sol`** — Direct analog for the new `TraitUtilsTester.sol`. Pattern: import the internal-pure library, declare a contract, expose each library function via an `external pure` passthrough (or compute simple aggregates). Used in `test/validation/PaperParity.test.js` via `hre.ethers.getContractFactory("PriceLookupTester")` + `.deploy()` in a fixture. Replicate verbatim.
- **`test/unit/*.test.js`** convention — per-contract Hardhat test file with nested `describe` blocks per function. New file `test/unit/DegenerusTraitUtils.test.js` follows the same pattern.

### Established Patterns
- **Bit-packing convention** — quadrant flags applied via `| 64`, `| 128`, `| 192` on traits B/C/D (already in `packedTraitsFromSeed`); preserved unchanged. Tests assert these flags on the packed output.
- **Scaling intermediate** — current `weightedBucket` uses `uint32 scaled = uint32((uint64(rnd) * 75) >> 32)` to avoid overflow. The new `weightedColorBucket` uses the same shape with multiplier `256` instead of `75`: `uint32 scaled = uint32((uint64(rnd) * 256) >> 32)`. Same `unchecked` block envelope.
- **Internal-pure test exposure** — `contracts/test/` is the dedicated home for test-only wrappers; do NOT add public functions to the library itself.

### Integration Points
- `DegenerusGameMintModule.sol:581` consumes `traitFromWord(uint64)` — signature unchanged, return type unchanged, just the internal weighting changes. No edits in the consumer.
- `DegenerusGameDegeneretteModule.sol:607` consumes `packedTraitsFromSeed(uint256)` — signature/return unchanged, byte layout preserved (TRAIT-03). No edits in the consumer.
- `test/fuzz/DegeneretteFreezeResolution.t.sol:354` consumes `packedTraitsFromSeed(uint256)` — must continue to compile + pass without modification (success criterion #3 implicit regression).
- No off-chain JS/TS scripts in `script/` reference the legacy `weightedBucket` (verified by repo-wide grep — should be confirmed by planner during the TRAIT-04 audit).

</code_context>

<specifics>
## Specific Ideas

- Color tier frequency table (REQUIREMENTS.md): `[0,64)→0` 25%, `[64,128)→1` 25%, `[128,192)→2` 25%, `[192,224)→3` 12.5%, `[224,240)→4` 6.25%, `[240,248)→5` 3.125%, `[248,254)→6` 2.344%, `[254,256)→7` 0.781%. Rarity ratio 32× between rarest (color 7) and most common (colors 0/1/2). Symbol distribution stays flat 12.5% (3-bit slice of high uint32).
- Exact `weightedColorBucket` body shape (locked by TRAIT-01):
  ```solidity
  function weightedColorBucket(uint32 rnd) internal pure returns (uint8) {
      unchecked {
          uint32 scaled = uint32((uint64(rnd) * 256) >> 32);
          if (scaled < 64) return 0;
          if (scaled < 128) return 1;
          if (scaled < 192) return 2;
          if (scaled < 224) return 3;
          if (scaled < 240) return 4;
          if (scaled < 248) return 5;
          if (scaled < 254) return 6;
          return 7;
      }
  }
  ```
- Exact `traitFromWord` body shape (locked by TRAIT-02):
  ```solidity
  function traitFromWord(uint64 rnd) internal pure returns (uint8) {
      uint8 color = weightedColorBucket(uint32(rnd));
      uint8 symbol = uint8(rnd >> 32) & 7;
      return (color << 3) | symbol;
  }
  ```
- Boundary test cases (locked by TRAIT-05): `scaled ∈ {0, 63, 64, 127, 128, 191, 192, 223, 224, 239, 240, 247, 248, 253, 254, 255}` with expected colors `{0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7}`.

</specifics>

<deferred>
## Deferred Ideas

- `_pickSoloQuadrant` helper in `DegenerusGameJackpotModule.sol` and the four ETH-distribution call-site injections (lines 282 / 349 / 524 / 1147) — Phase 260 (depends on color tier 7 existing post-Phase 259).
- 1M-sample empirical color-frequency Monte Carlo + chi-squared independence + symbol uniformity tests (`test/stat/`) — Phase 261.
- Pack-feel CIs over 100K 10-ticket packs — Phase 261.
- Cross-surface verification of Hero override (`_applyHeroOverride`), deity-pass virtual entries, Degenerette match payouts, and the 8 documented non-injection bonus-jackpot sites — Phase 261.
- Gas regression vs v33.0 baseline (`weightedColorBucket` ±100 gas, `_pickSoloQuadrant` < 500 gas, top-level entry-point delta < 2000 gas) — Phase 261. Per `feedback_gas_worst_case.md`, derive theoretical worst case FIRST, then test.
- Delta audit / findings consolidation (`audit/FINDINGS-v34.0.md`) — Phase 262.

</deferred>

---

*Phase: 259-trait-distribution-split*
*Context gathered: 2026-05-08*
