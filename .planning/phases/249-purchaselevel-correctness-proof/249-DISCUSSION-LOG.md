# Phase 249: purchaseLevel Correctness Proof - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-01
**Phase:** 249-purchaselevel-correctness-proof
**Areas discussed:** PLV-01 enumeration scope, PLV-02 sweep encoding, PLV-04 grouping, PLV-06 daily-jackpot proof shape (with PLV-05 shape covered as adjacent question)

---

## PLV-01 enumeration scope

### Q1: How wide should PLV-01 enumeration scope be?

| Option | Description | Selected |
|--------|-------------|----------|
| AdvanceModule + helpers only | Catalog ONLY the AdvanceModule:185 binding + every read site of that local variable inside advanceGame's call tree (~30+ rows). Cross-module re-derivations flagged in a single OUT-OF-SCOPE-BY-CONSTRUCTION sub-table and routed to Phase 250 SIB-03. | |
| AdvanceModule + cross-module re-derivations | Wider scope: AdvanceModule:185 chain + MintModule:923 + WhaleModule:841 + LootboxModule:532 + BurnieCoinflip:578/1035 + AdvanceModule helpers L734/L1097/L1504. ~70+ rows. MintModule:923 has the same shape without the new guard; pre-flagging gives Phase 250 SIB a live finding-candidate seed. | ✓ |
| Bind sites only + parameter-chain cite | Enumerate every site that BINDS purchaseLevel as primary rows; sites that merely RECEIVE purchaseLevel as a parameter get a single-row boundary cite. ~15-20 primary rows + 6-8 boundary rows. | |

**User's choice:** AdvanceModule + cross-module re-derivations
**Notes:** Recorded as D-249-01.

### Q2: How deep should cross-module re-derivation rows go?

| Option | Description | Selected |
|--------|-------------|----------|
| Full per-row proof | Each cross-module re-derivation row carries a self-contained proof that the local purchaseLevel binding cannot be 0. Heavier rows but PLV-01 stands alone without forwarding to PLV-02 / Phase 250. | ✓ |
| Shape-class flag + PLV-02 deferral | Cross-module rows carry: site cite, shape-class tag, local invariant, verdict pointer. Lighter rows. | |
| Tag + bare cite only | Cross-module rows carry only site cite + shape-class tag with no verdict pointer. Lightest. | |

**User's choice:** Full per-row proof
**Notes:** Recorded as D-249-02. MintModule:923 needs `(jackpotPhaseFlag, cachedLevel = 0)` reachability; LootboxModule:532 needs packed-slot extraction invariant traced to WhaleModule:876 packer; parameter-passthrough sites trace upstream binders.

### Q3: PLV-01 row column structure — what columns?

| Option | Description | Selected |
|--------|-------------|----------|
| Standard 7-col + invariant tag | `Row ID | Site (file:line) | Function | Read kind | Invariant required | Verdict | Evidence cite`. Mirrors D-247-10 + D-248-12 with invariant tag added. | ✓ |
| 8-col + shape-class | Add a separate Shape class column for trivial Phase 250 SIB cross-cite. 8 columns. | |
| Standard 7-col, shape-class in note | Keep 7 columns; fold shape-class into Evidence cite or one-line note. | |

**User's choice:** Standard 7-col + invariant tag
**Notes:** Recorded as D-249-03.

---

## PLV-02 sweep encoding

### Q1: How should PLV-02's 4-D state-space sweep be encoded?

| Option | Description | Selected |
|--------|-------------|----------|
| 8 octants × 3 level bins | 8 octant tables (one per (lastPurchase, rngLocked, jackpot) triple) × level bins {lvl=0, 1≤lvl<levelMax, lvl=levelMax}. 24 cells total. | ✓ |
| Flat 16-cell table (level=0 vs level≥1) | Single flat 16-row table. Smaller; less hierarchical. | |
| Bin to {0, 1, 2, levelMax-1, levelMax} × 8 octants | ROADMAP-literal sweep: 8 octants × 5 level bins = 40 cells. More verbose. | |
| One row per octant + bin | 8 octants flat in a single table, level treated symbolically per row. 24 rows. Equivalent content; no octant sub-table headers. | |

**User's choice:** 8 octants × 3 level bins
**Notes:** Recorded as D-249-04. The (T,T,*,lvl=0) cells are the load-bearing UNREACHABLE rows whose disproof cites the L173 turbo guard.

### Q2: Where should reachability disproofs cite their evidence?

| Option | Description | Selected |
|--------|-------------|----------|
| Inline path:line cite + invariant name | Each UNREACHABLE cell carries a path:line cite + named invariant. Self-contained per row; matches Phase 248 BFL-04 grep-cited pattern. | ✓ |
| Forward-cite to PLV-03 row | UNREACHABLE cells cite forward to PLV-03's dedicated unreachable-state proof. Lighter rows; requires reader to flip. | |
| Both inline + forward-cite | One-line inline summary + forward-cite to PLV-03 row. Heaviest format. | |

**User's choice:** Inline path:line cite + invariant name
**Notes:** Recorded as D-249-05. Named-invariant ID scheme: INV-PLV-{A,B,C}-NN per axis.

### Q3: What about the level=levelMax overflow edge case at L185?

| Option | Description | Selected |
|--------|-------------|----------|
| Attest unreachable via game-mechanic bound | Prove level cannot reach uint24.max via game mechanics. Single attestation row + grep cite. | |
| Treat as INFO finding-candidate | Tag the overflow edge as INFO-severity finding-candidate. | |
| Out-of-scope-by-construction | Mark overflow edge as OOS-by-construction (level cap is v25/v26-era invariant not part of the v32 delta). One-line cite + skip. | ✓ |

**User's choice:** Out-of-scope-by-construction
**Notes:** Recorded as D-249-06. Same structural pattern as Phase 248 D-248-10 BurnieCoinflip boundary cite.

---

## PLV-04 grouping

### Q1: How should PLV-04 group arithmetic call sites?

| Option | Description | Selected |
|--------|-------------|----------|
| Per-call-site rows in operator-bucketed sub-tables | 5 sub-tables: -1 underflow / +1 +4 overflow / %10 modular / array-index oob / _tqReadKey + function-arg pass-through. | |
| Single flat per-call-site table | One flat table, all sites mixed, sorted by file:line. Each row has Operator column. Easier grep for `\| -1 \|` etc. | ✓ |
| Per-operator-category rows | One row per operator-category grouping ALL call sites. ~6 rows total. Most compact; loses per-site granularity. | |

**User's choice:** Single flat per-call-site table
**Notes:** Recorded as D-249-07.

### Q2: For the `purchaseLevel - 1` underflow rows, what extra evidence should they carry?

| Option | Description | Selected |
|--------|-------------|----------|
| Cross-cite PLV-02 + PLV-03 + PLV-05 | Each `-1` site row's verdict cites PLV-02 sweep, PLV-03 ternary unreachable proof, AND PLV-05 testnet panic 0x11 reproduction. Establishes per-site safety chain explicitly. | ✓ |
| Cross-cite PLV-02 only | Each `-1` row cites PLV-02 sweep as the load-bearing fact. Lighter rows. | |
| Inline algebra + PLV-02 cite | Each `-1` row carries inline algebra plus PLV-02 cite. Heaviest format. | |

**User's choice:** Cross-cite PLV-02 + PLV-03 + PLV-05
**Notes:** Recorded as D-249-08. Mirrors Phase 248 BFL-06's cross-cite to BFL-04 invariant.

### Q3: Array-index out-of-bounds: should PLV-04 rows for `levelPrizePool[purchaseLevel]` and `levelPrizePool[purchaseLevel - 1]` prove upper-bound separately?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — boundary cite + storage-array bound | Each `levelPrizePool[*]` site carries a verdict row for upper-bound (purchaseLevel ≤ levelMax) AND lower-bound. Symmetric coverage. | ✓ |
| Lower-bound only — upper-bound OOS-by-construction | Treat upper-bound as OOS-by-construction (same v25/v26-era invariant as PLV-02). Single per-section attestation. | |

**User's choice:** Yes — boundary cite + storage-array bound
**Notes:** Recorded as D-249-09. Maintains symmetric oob coverage.

---

## PLV-06 daily-jackpot proof shape

### Q1: What proof shape for PLV-06's daily-jackpot region?

| Option | Description | Selected |
|--------|-------------|----------|
| Per-branch invariant table + strand-disproof attestation | Single table walking each branch of L370-407 + one-paragraph strand-disproof. Matches Phase 248 BFL-04 invariant-table pattern. | ✓ |
| State-transition walk table | Mirror BFL-03 worked-example shape. Heavier; better fits sequential bug reproductions. | |
| Algebraic strand-disproof block + cite-only rows | Inline algebraic block + 1-liner verdicts. Most compact; least table-friendly. | |

**User's choice:** Per-branch invariant table + strand-disproof attestation
**Notes:** Recorded as D-249-12. PLV-06 is a single-call resolution proof, not a sequential trigger.

### Q2: Should PLV-06 cross-cite Phase 252 POST31-02?

| Option | Description | Selected |
|--------|-------------|----------|
| Cross-cite + provide composition hand-off | One-row hand-off attestation for Phase 252 POST31-02 productive-pause composition target. | ✓ |
| Mention without dedicated row | Reference Phase 252 in section preamble; no dedicated row. | |
| Skip cross-cite | PLV-06 stays scoped to strand-disproof; Phase 252 derives composition independently. | |

**User's choice:** Cross-cite + provide composition hand-off
**Notes:** Recorded as D-249-13. Mirrors Phase 248 BFL-04's cross-cite of the productive-pause path.

### Q3 (adjacent): PLV-05 testnet panic 0x11 reproduction shape

| Option | Description | Selected |
|--------|-------------|----------|
| BFL-03-style state-transition walk | Mirror Phase 248 BFL-03 worked-numeric-example. Pre-fix walk + post-fix walk. | ✓ |
| Symbolic call-trace + state-snapshot tables | Two tables: pre-fix + post-fix call traces with state snapshots at L173, L185, L204. Less granular than BFL-03. | |
| Inline narrative + state-table | Prose narrative + single end-state table. v25/v29 narrative-style finding-block format. | |

**User's choice:** BFL-03-style state-transition walk
**Notes:** Recorded as D-249-10. Same testnet block seed (10759449 + 10761786) per D-249-CF-10.

---

## Claude's Discretion

- Final section ordering within `audit/v32-249-PLV.md` (planner picks readable shape).
- Whether PLV-02 octant tables are inlined as 8 separate sub-tables or rendered as one flat 24-row table with octant column.
- Whether named-invariant ID scheme uses `INV-PLV-A-NN / INV-PLV-B-NN / INV-PLV-C-NN` (per-axis) or flat `INV-PLV-NN`.
- Whether finding-candidate severity is suggested in Phase 249's `Finding Candidates` subsection (recommended INFO baseline) or left blank for Phase 253.
- Per-REQ section header naming.
- Whether MintModule:924 `priceForLevel(purchaseLevel)` traces into PriceLookupLib internal arithmetic for PLV-04 coverage or treats PriceLookupLib as a boundary cite.
- Whether the Phase 251 hand-off appendix sketches an `it()` block or just lists symbolic-spec / suggested-file / Phase 247 row anchors.
- Octant ordering convention (FFF / FFT / FTF / FTT / TFF / TFT / TTF / TTT).
- Plan task split: 4-task suggested (PLV-01+02 / PLV-03+04 / PLV-05+06 / Final assembly + Phase 251 hand-off) vs 5-task split inheriting Phase 248 cadence — planner final call.

## Deferred Ideas

- Forge invariant fuzz test for `purchaseLevel ≥ 1` at every `levelPrizePool[purchaseLevel - 1]` site.
- MintModule:923 fix candidate (if reachable) — adding `!rngLockedFlag` analog conjunctive guard. Routes to Phase 250/253.
- Cross-milestone delta chain audit for `purchaseLevel` semantics back to v3.6 (Phases 59-62).
- PriceLookupLib internal arithmetic deep-walk (Claude's discretion).
- Phase 250 SIB-01 sibling-pattern sweep — additional same-shape ternaries Phase 249 may surface.
- Storage-layout add-row for any future purchaseLevel-related hardening.
- Octant ordering convention + named-invariant prefix flattening — left to planner.
