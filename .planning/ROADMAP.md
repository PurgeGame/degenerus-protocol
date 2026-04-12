# Roadmap: Degenerus Protocol Audit

## Milestones

- ✅ **v1.0 Initial RNG Security Audit** — Phases 1-5 (shipped 2026-03-14)
- ✅ **v2.0 Adversarial Audit** — Phases 6-18 (shipped 2026-03-17)
- ✅ **v3.0-v24.1** — Phases 19-212 (shipped 2026-04-10)
- ✅ **v25.0 Full Audit (Post-v5.0 Delta + Fresh RNG)** — Phases 213-217 (shipped 2026-04-11)
- ✅ **v26.0 Bonus Jackpot Split** — Phases 218-219 (shipped 2026-04-12)
- 🚧 **v27.0 Call-Site Integrity Audit** — Phases 220-223 (in progress)

## Phases

<details>
<summary>✅ v25.0 Full Audit (Phases 213-217) — SHIPPED 2026-04-11</summary>

- [x] Phase 213: Delta Extraction (3/3 plans) — completed 2026-04-10
- [x] Phase 214: Adversarial Audit (5/5 plans) — completed 2026-04-10
- [x] Phase 215: RNG Fresh Eyes (5/5 plans) — completed 2026-04-11
- [x] Phase 216: Pool & ETH Accounting (3/3 plans) — completed 2026-04-11
- [x] Phase 217: Findings Consolidation (2/2 plans) — completed 2026-04-11

</details>

<details>
<summary>✅ v26.0 Bonus Jackpot Split (Phases 218-219) — SHIPPED 2026-04-12</summary>

- [x] Phase 218: Bonus Split Implementation (2/2 plans) — completed 2026-04-12
- [x] Phase 219: Delta Audit & Gas Verification (2/2 plans) — completed 2026-04-12

</details>

### v27.0 Call-Site Integrity Audit (In Progress)

**Milestone Goal:** Systematically surface runtime call-site-to-implementation mismatches that static compilation does not catch — the same class of bug as the `mintPackedFor` regression (commit `a0bf328b`), where a call passed compile, passed superficial tests, and reverted at runtime because selector/target/path alignment was wrong.

- [x] **Phase 220: Delegatecall Target Alignment** - Verify every delegatecall target constant maps 1:1 to its interface and wire a static-analysis gate into the Makefile (completed 2026-04-12)
- [ ] **Phase 221: Raw Selector & Calldata Audit** - Catalog every `bytes4` literal, `keccak256` selector, and manual `abi.encode*` site with severity verdicts
- [ ] **Phase 222: External Function Coverage Gap** - Fix fuzz compile error, run `forge coverage`, classify every external/public function, and add tests for CRITICAL_GAPs
- [ ] **Phase 223: Findings Consolidation** - Roll up phase 220-222 findings into `audit/FINDINGS-v27.0.md`, update `KNOWN-ISSUES.md`, and ship v27.0

## Phase Details

### Phase 220: Delegatecall Target Alignment
**Goal**: Every `<ADDR>.delegatecall(abi.encodeWithSelector(IXxxModule.fn.selector, ...))` site is proven to target the address constant that matches its interface, with a Makefile gate preventing future drift
**Depends on**: Nothing (first phase of v27.0)
**Requirements**: CSI-01, CSI-02, CSI-03
**Success Criteria** (what must be TRUE):
  1. Every delegatecall site in `contracts/` is catalogued with `(target address constant, selector interface)` and a PASS/FAIL verdict on whether the two align
  2. Every `GAME_*_MODULE` constant in `ContractAddresses.sol` used as a delegatecall target has a documented 1:1 mapping to exactly one module interface, consistent across every caller
  3. A static-analysis script (e.g., `scripts/check-delegatecall-alignment.sh`) is added and wired into the Makefile such that any future address/interface mismatch fails `make test`
  4. Zero cross-wired delegatecalls remain, or every cross-wired site is documented as JUSTIFIED with rationale
**Plans**: 2 plans
- [x] 220-01-PLAN.md — Audit all 41 interface-bound encoding sites, write `scripts/check-delegatecall-alignment.sh`, wire `check-delegatecall` Makefile gate into `test-foundry`/`test-hardhat` (CSI-01, CSI-03)
- [x] 220-02-PLAN.md — Produce 220-02-MAPPING.md proving 1:1 interface↔address correspondence for all 9 LIVE module pairs, document dead `GAME_ENDGAME_MODULE`, add `validate_mapping` preflight to the script (CSI-02)

### Phase 221: Raw Selector & Calldata Audit
**Goal**: Every raw selector literal and hand-rolled calldata encoder in `contracts/` is either replaced with interface-bound form or justified in place, producing a findings document with severity verdicts
**Depends on**: Nothing (parallel with 220)
**Requirements**: CSI-04, CSI-05, CSI-06, CSI-07
**Success Criteria** (what must be TRUE):
  1. Every `bytes4(0x...)` hex literal in `contracts/` has a verdict (JUSTIFIED with code comment naming the target function, REPLACED with `IXxx.fn.selector`, or FLAGGED as a finding)
  2. Every `bytes4(keccak256("..."))` string-derived selector in `contracts/` has a verdict (JUSTIFIED, REPLACED, or FLAGGED)
  3. Every manual `abi.encode` / `abi.encodeCall` / `abi.encodeWithSignature` site that bypasses an interface-bound selector has a verdict with rationale
  4. A catalogue document lists every raw-selector site with its verdict so Phase 223 can roll it into the findings document
**Plans**: TBD

### Phase 222: External Function Coverage Gap
**Goal**: Every external/public function on a deployed contract is classified as COVERED, CRITICAL_GAP, or EXEMPT — and every CRITICAL_GAP has at least one new test exercising it on a realistic path, so a future `mintPackedFor`-class bug cannot hide in unexercised surface
**Depends on**: Phase 220, Phase 221 (findings fold into coverage priorities — unexercised functions flagged by 220/221 are prioritized as CRITICAL_GAP in 222's classification)
**Requirements**: CSI-08, CSI-09, CSI-10, CSI-11
**Success Criteria** (what must be TRUE):
  1. The `test/fuzz/FuturepoolSkim.t.sol` compile error (`_applyTimeBasedFutureTake` undeclared identifier) is fixed so `forge coverage` runs to completion
  2. `forge coverage --report summary` produces per-function line and branch coverage data for every deployed contract (`DegenerusGame`, modules, `BurnieCoin`, `BurnieCoinflip`, `DegenerusAffiliate`, `DegenerusJackpots`, `DegenerusQuests`, `StakedDegenerusStonk`, `DegenerusVault`, `DegenerusStonk`)
  3. Every external/public function on a deployed contract has a recorded classification (COVERED / CRITICAL_GAP / EXEMPT) with documented rationale for EXEMPTions
  4. Every CRITICAL_GAP function has at least one new test exercising it on a realistic path (conditional entry points where the real bug would manifest, not just direct invocation with happy-path args)
**Plans**: TBD

### Phase 223: Findings Consolidation
**Goal**: All v27.0 audit findings are severity-classified and rolled up into `audit/FINDINGS-v27.0.md`; design-decision items are promoted to `KNOWN-ISSUES.md`; v27.0 is marked SHIPPED
**Depends on**: Phase 220, Phase 221, Phase 222
**Requirements**: CSI-12, CSI-13, CSI-14
**Success Criteria** (what must be TRUE):
  1. `audit/FINDINGS-v27.0.md` exists with every finding from phases 220-222 severity-classified (HIGH / MEDIUM / LOW / INFO) and follows the `audit/FINDINGS-v25.0.md` structure
  2. `KNOWN-ISSUES.md` is updated with any accepted INFO/LOW items that are design decisions rather than bugs
  3. `MILESTONES.md` has a v27.0 retrospective entry matching the v25.0 / v26.0 format
  4. `PROJECT.md` moves v27.0 from "Current Milestone" to "Completed Milestone" and v27.0 is marked SHIPPED in this file's Milestones list
**Plans**: TBD

## Progress

**Execution Order:**
Phase 220 first (or in parallel with 221). Phase 221 in parallel with 220. Phase 222 after 220 + 221 (so their findings can inform coverage priorities). Phase 223 after all three.

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 213. Delta Extraction | v25.0 | 3/3 | Complete | 2026-04-10 |
| 214. Adversarial Audit | v25.0 | 5/5 | Complete | 2026-04-10 |
| 215. RNG Fresh Eyes | v25.0 | 5/5 | Complete | 2026-04-11 |
| 216. Pool & ETH Accounting | v25.0 | 3/3 | Complete | 2026-04-11 |
| 217. Findings Consolidation | v25.0 | 2/2 | Complete | 2026-04-11 |
| 218. Bonus Split Implementation | v26.0 | 2/2 | Complete | 2026-04-12 |
| 219. Delta Audit & Gas Verification | v26.0 | 2/2 | Complete | 2026-04-12 |
| 220. Delegatecall Target Alignment | v27.0 | 2/2 | Complete   | 2026-04-12 |
| 221. Raw Selector & Calldata Audit | v27.0 | 0/? | Not started | - |
| 222. External Function Coverage Gap | v27.0 | 0/? | Not started | - |
| 223. Findings Consolidation | v27.0 | 0/? | Not started | - |
