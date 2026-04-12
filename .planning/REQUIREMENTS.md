# Requirements: Degenerus Protocol Audit — v27.0 Call-Site Integrity Audit

**Defined:** 2026-04-12
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## Milestone Goal

Systematically surface runtime call-site-to-implementation mismatches that static compilation does not catch — the same class of bug as the `mintPackedFor` regression (commit `a0bf328b`), where a call passed compile, passed superficial tests, and reverted at runtime under a narrow path because selector/target/path alignment was wrong.

The scope is deliberately bounded to **call-site integrity**. Out of scope for this milestone: storage layout regression (already verified v25.0), deployed bytecode vs source (requires RPC infra), generic `E()` revert specificity (debuggability, not correctness).

## v27.0 Requirements

### Delegatecall Target Alignment (Phase 220)

- [x] **CSI-01**: Every `<ADDR>.delegatecall(abi.encodeWithSelector(IXxxModule.fn.selector, ...))` site uses a target address constant that corresponds to `IXxxModule` (no cross-wired addresses — e.g., no `GAME_BOON_MODULE.delegatecall(abi.encodeWithSelector(IDegenerusGameJackpotModule.fn.selector, ...))`)
- [x] **CSI-02**: Every `GAME_*_MODULE` address constant in `ContractAddresses.sol` that is used as a delegatecall target has a 1:1 mapping to exactly one module interface, verified across every caller
- [x] **CSI-03**: A static-analysis script (`scripts/check-delegatecall-alignment.sh` or similar) is added and wired into the Makefile gate so any future delegatecall/interface misalignment fails `make test`

### Raw Selector & Calldata Audit (Phase 221)

- [x] **CSI-04**: Every `bytes4(0x...)` hex literal in `contracts/` is cataloged; each one is either (a) justified in-place with a code comment naming the function it represents, or (b) replaced with an interface-bound `IXxx.fn.selector` reference
- [x] **CSI-05**: Every `bytes4(keccak256("..."))` string-derived selector in `contracts/` is cataloged and each one is justified or replaced with interface-bound form
- [x] **CSI-06**: Every manual `abi.encode` / `abi.encodeCall` / `abi.encodeWithSignature` that bypasses interface-bound selectors (i.e., does not reference an `IXxx.fn.selector`) is cataloged with rationale
- [x] **CSI-07**: Catalog output is a findings document listing every raw selector site with severity verdict (JUSTIFIED / REPLACED / FLAGGED)

### External Function Coverage Gap (Phase 222)

- [ ] **CSI-08**: The test suite compile error in `test/fuzz/FuturepoolSkim.t.sol` (`_applyTimeBasedFutureTake` undeclared identifier) is fixed so `forge coverage` can run
- [ ] **CSI-09**: `forge coverage --report summary` runs to completion and produces per-function line/branch coverage data for all deployed contracts (`DegenerusGame`, modules, `BurnieCoin`, `BurnieCoinflip`, `DegenerusAffiliate`, `DegenerusJackpots`, `DegenerusQuests`, `StakedDegenerusStonk`, `DegenerusVault`, `DegenerusStonk`)
- [ ] **CSI-10**: Every external/public function on a deployed contract is classified as COVERED (≥1 test invokes it), CRITICAL_GAP (needs new test — on a path that could revert at runtime like `mintPackedFor` did), or EXEMPT (admin/governance/emergency path, documented rationale)
- [ ] **CSI-11**: All CRITICAL_GAP functions identified in CSI-10 have at least one new test added that exercises them on a realistic path (not just direct invocation with happy-path args — must cover the conditional entry points where the real bug manifested)

### Findings Consolidation (Phase 223)

- [ ] **CSI-12**: `audit/FINDINGS-v27.0.md` is produced with severity-classified findings rolled up from phases 220-222 (HIGH / MEDIUM / LOW / INFO), following the `audit/FINDINGS-v25.0.md` structure
- [ ] **CSI-13**: `KNOWN-ISSUES.md` is updated with any accepted INFO/LOW items that are design decisions rather than bugs
- [ ] **CSI-14**: `MILESTONES.md` retrospective entry is written (mirroring v25.0 / v26.0 format); `PROJECT.md` moves v27.0 to "Completed Milestone"; v27.0 marked SHIPPED

## Future Requirements

Deferred to later milestones. Tracked but not in this roadmap.

### Storage & Deploy Integrity (future)

- Storage layout regression script (automate what v25.0 verified manually across 13 DegenerusGameStorage inheritors)
- Deployed bytecode vs compiled source verification (requires RPC infrastructure)

### Revert Specificity (future)

- Replace generic `revert E()` sites with specific custom errors where the call site warrants — improves debuggability; currently every `E()` is indistinguishable in traces

## Out of Scope (v27.0)

Explicit exclusions with reasoning:

- **Storage layout consistency check** — already verified in v25.0 ("forge inspect confirms identical 84-variable storage layout across all 13 DegenerusGameStorage inheritors"). Re-running under v27.0 adds no signal; automation is a future concern, not a same-class-bug hunt.
- **Deployed bytecode match** — requires RPC access and a verification pipeline; different architectural concern (deploy integrity, not source integrity).
- **Reentrancy sweep** — already verified in v25.0 ("zero VULNERABLE findings, all external calls follow CEI"). Not the mintPackedFor class.
- **Adversarial economic paths** — covered by v25.0 adversarial audit; different risk class.
- **`is IDegenerusGame` compile-time inheritance enforcement** — the strongest possible guarantee (forces the compiler to enforce every interface function), but would require adding `override` to ~57 functions on `DegenerusGame` and similar churn on other contracts. High mechanical cost against the current `check-interfaces` gate which catches the same class at `make test` time. Reconsider if the gate ever produces false negatives.

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CSI-01 | Phase 220 | Complete |
| CSI-02 | Phase 220 | Complete |
| CSI-03 | Phase 220 | Complete |
| CSI-04 | Phase 221 | Complete |
| CSI-05 | Phase 221 | Complete |
| CSI-06 | Phase 221 | Complete |
| CSI-07 | Phase 221 | Complete |
| CSI-08 | Phase 222 | Pending |
| CSI-09 | Phase 222 | Pending |
| CSI-10 | Phase 222 | Pending |
| CSI-11 | Phase 222 | Pending |
| CSI-12 | Phase 223 | Pending |
| CSI-13 | Phase 223 | Pending |
| CSI-14 | Phase 223 | Pending |

**Coverage:** 14/14 requirements mapped to exactly one phase. No orphans. No duplicates.
