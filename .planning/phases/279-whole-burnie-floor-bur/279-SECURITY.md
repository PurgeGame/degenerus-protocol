---
phase: 279
slug: whole-burnie-floor-bur
status: verified
threats_open: 0
asvs_level: 1
created: 2026-05-14
---

# Phase 279 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| VRF/RNG word → BURNIE-amount compute | Pre-floor `burnieAmount` / `coinBudget` / `farBudget` values derive from RNG-influenced variance rolls and daily budgets; the floor is a deterministic integer-division transform at the amount-compute point. | `uint256` BURNIE-wei amounts |
| amount-compute → `coinflip` credit sink | The floored amount crosses into the unchanged `coinflip.creditFlip(...)` / `creditFlipBatch(...)` interface; only value shape changes (always a 1-ether multiple). | `uint256` floored BURNIE-wei amounts |
| contract storage layout → v39 baseline `6a7455d1` | Phase 279 must not perturb storage slots — every off-chain consumer and the audit baseline depend on byte-identical layout. | Storage slot layout |
| contract source on disk → test source-structural assertions | The TST-BUR tests read post-Wave-1 contract source and assert structural properties; a stale/wrong-version read would silently pass against the wrong contract. | Solidity source text |
| v39 baseline `6a7455d1` → `SURF_01_PROTECTED_RANGES_V40` re-cut | The surface-regression gate diffs current source against the baseline; an over/under-broad re-cut masks real drift or fails on the intended Phase 279 delta. | Protected line-range arrays |
| mint-boost path `MintModule:1199` → negative cross-site assertion | The negative assertion must be pinned to the exact `lootboxFlipCredit` call site so it asserts against the right function. | Solidity function body |
| new `test/stat/` file → `test:stat` runner file list | `test:stat` is a hand-maintained explicit file list, not a glob; a new file silently never runs until its path is appended. | `package.json` script file list |

---

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation | Status |
|-----------|----------|-----------|-------------|------------|--------|
| T-279-01 | Tampering | Integer-division floor correctness `(x / 1 ether) * 1 ether` at the 3 BUR sites | mitigate | All 3 inline floors present & correctly ordered: `DegenerusGameLootboxModule.sol:1023` (after the post-bonus `burnieAmount` accumulation, before the `if (burnieAmount != 0)` guard); `DegenerusGameJackpotModule.sol:1789` (`baseAmount`); `DegenerusGameJackpotModule.sol:1896` (`perWinner`, immediately before the unchanged `if (perWinner == 0) return;` per D-279-BUR03-ORDER-01). All `uint256` operands, floor-direction-only, existing zero-guards absorb the post-floor-zero case. | closed |
| T-279-02 | Elevation of Privilege | Storage layout / new mutation paths | accept | BUR-04 byte-identity proof (`279-01-STORAGE-LAYOUT-DIFF.md`): empty `forge inspect storage-layout` diff + matching sha256 for both modules vs `6a7455d1`. Commit `8ef4a010` is `+18/-21` lines, all function-body/NatSpec; `extra`/`cursor` removals delete only stack locals. Zero new state/events/modifiers/entry points. | closed |
| T-279-03 | Denial of Service | Attacker amplification of dust evaporation / daily-budget griefing | accept | Dust evaporation bounded < 1 BURNIE/spin at BUR-01 (independent per-spin floor, no cross-spin accumulation); BUR-02/BUR-03 evaporation gated on `coinBudget < cap` / `farBudget < found` — `cap = DAILY_COIN_MAX_WINNERS` capped at `coinBudget`, `found` = sampled queue count, neither attacker-controllable at the amount-compute point. No attacker-amplification path. Accepted per D-40N-BUR-DUST-01. | closed |
| T-279-04 | Information Disclosure | Event-field value semantics shift (`LootBoxOpened.burnie`, `JackpotBurnieWin.amount`, `FarFutureCoinJackpotWinner.perWinner` now carry floored values) | accept | The 3 event signatures and topic-hashes are unchanged — only the emitted value is now always a 1-ether multiple. No new field, no schema change; the emit is now self-consistent with the credit. Floored value is strictly less information than the pre-floor fractional amount. Consistent with D-40N-BUR-SILENT-01. | closed |
| T-279-05 | Tampering | Accidental modification of the OUT-OF-SCOPE ticket-award cursor-rotation near `:1003` in `DegenerusGameJackpotModule.sol` | mitigate | `git show 8ef4a010` hunks for the module are all at lines ≥1752; the `:996-:1021` region still contains the `extra`/`cursor` ticket-award rotation intact. Whole-file `\b(extra\|cursor)\b` count = 5 (all in the surviving out-of-scope region); `_awardDailyCoinToTraitWinners` span count = 0. D-279-DISAMBIG-01 satisfied. | closed |
| T-279T-01 | Tampering | Source-structural test reads a stale/wrong contract file | mitigate | All `extractBody` calls resolve `MODULE_SOURCE_PATH` to `contracts/modules/...` explicitly in all 4 test files. Negative assertions are positive-pinned (e.g. `WholeBurnieFloorInvariant.test.js` asserts `creditFlip(buyer, lootboxFlipCredit)` IS present before asserting the floor is NOT). Tests run against post-Wave-1 source; all pass. | closed |
| T-279T-02 | Repudiation | `SURF_01_PROTECTED_RANGES_V40` re-cut over-broad or under-broad | mitigate | The v40.0 SURF-01 block passes green against post-Wave-1 source; all 5 v40.0 SURF blocks pass. Code review independently confirmed the re-cut ranges are an accurate complement of the OLD-side modified-line set vs `git diff 6a7455d1 HEAD`. `walkAndAssertV40` + `it` bodies byte-identical. | closed |
| T-279T-03 | Information Disclosure | Mint-boost negative assertion gives false confidence (asserts against wrong function) | mitigate | `WholeBurnieFloorInvariant.test.js` `[03a]` pins `_purchaseFor`/mint-boost site via positive assertion `creditFlip(buyer, lootboxFlipCredit)` present; `[03b]` then asserts no `/ 1 ether) * 1 ether` floor on `lootboxFlipCredit`. A mis-located `extractBody` fails the positive pin loudly. Both tests pass. | closed |
| T-279T-04 | Denial of Service | Invariant sweep is non-deterministic / flaky | accept | `WholeBurnieFloorInvariant.test.js` uses the deterministic `makeRng` seeded keccak-counter PRNG (fixed hex seeds) and asserts the deterministic `amount % 1 ether == 0` floor invariant — no probabilistic component, no statistical tolerance, no chi-square. Fully reproducible; a failure is a real failure, not flake. | closed |
| T-279T-05 | Elevation of Privilege | Test wave commits contract or `.planning/` files | mitigate | `git show --stat 37207743` staged exactly the 6 intended files (`package.json`, `test/stat/SurfaceRegression.test.js`, `test/stat/WholeBurnieFloorInvariant.test.js`, 3 `test/unit/` BUR files). Zero contract files, zero `.planning/` artifacts. Nothing pushed. Commit made only after explicit user approval at the Task 3 checkpoint. | closed |
| T-279T-06 | Repudiation | TST-BUR-04 passes in isolation but never runs in the `test:stat` CI tier | mitigate | `package.json` `test:stat` script's explicit file list includes `test/stat/WholeBurnieFloorInvariant.test.js` — confirmed present and confirmed executed under the `test:stat` tier. Not orphaned. | closed |

*Status: open · closed*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-279-01 | T-279-02 | Storage layout proven byte-identical to v39 baseline `6a7455d1` for both modules; Phase 279 touches only function bodies — no new state, events, modifiers, or entry points. No mitigation was silently expected; the BUR-04 byte-identity proof IS the disposition evidence. | Purge (user) | 2026-05-14 |
| AR-279-02 | T-279-03 | Sub-1-BURNIE dust evaporation is bounded and not attacker-amplifiable; daily-budget evaporation on low-pool days is driven by daily budget + winner count, neither attacker-controllable at the amount-compute point. Accepted per D-40N-BUR-DUST-01 ("sub 1 burnie amounts are economically negligible", user disposition 2026-05-13). | Purge (user) | 2026-05-14 |
| AR-279-03 | T-279-04 | Event signatures/topic-hashes unchanged; only the emitted value is now a 1-ether multiple, making the emit self-consistent with the `creditFlip` credit. No schema change, no new field, strictly less information disclosed. Consistent with D-40N-BUR-SILENT-01. | Purge (user) | 2026-05-14 |
| AR-279-04 | T-279T-04 | The invariant sweep is deterministic by construction (seeded `makeRng` PRNG, deterministic floor invariant, no statistical tolerance) — there is no flake surface to mitigate. | Purge (user) | 2026-05-14 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-05-14 | 11 | 11 | 0 | gsd-security-auditor (opus) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-05-14
