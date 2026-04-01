# Phase 104: Day Advancement + VRF - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-25
**Phase:** 104-day-advancement-vrf
**Mode:** auto (--auto flag)
**Areas discussed:** Function Categorization, Ticket Queue Drain Scope, VRF Audit Overlap, Cross-Module Call Boundary

---

## Function Categorization

| Option | Description | Selected |
|--------|-------------|----------|
| B/C/D only — no Category A | Module has no delegatecall dispatchers. External→B, Internal→C, View/Pure→D | ✓ |
| Include pseudo-Category A for rngGate routing | rngGate routes VRF callbacks similarly to dispatch | |

**User's choice:** [auto] B/C/D only — no Category A (recommended default)
**Notes:** Phase 103 had Category A because DegenerusGame.sol dispatches to modules via delegatecall. Phase 104 is a module itself — it receives delegatecalls, it doesn't dispatch them. rngGate() is a VRF callback router, not a delegatecall dispatcher.

---

## Ticket Queue Drain Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Dedicated section with standalone verdict | Priority investigation gets its own section in attack report, CONFIRMED BUG / PROVEN SAFE verdict | ✓ |
| Fold into normal _prepareFutureTickets analysis | Treat as part of standard function analysis | |
| Separate investigation report | Standalone document outside the main attack report | |

**User's choice:** [auto] Dedicated section with standalone verdict (recommended default)
**Notes:** ROADMAP.md explicitly flags this as PRIORITY INVESTIGATION. It deserves visibility but belongs in the attack report where all findings live.

---

## VRF Audit Overlap

| Option | Description | Selected |
|--------|-------------|----------|
| Fresh adversarial analysis — ignore prior findings | Don't trust v3.7/v3.8 results. Audit everything from scratch. | ✓ |
| Reference prior findings, focus on deltas | Reduced effort on previously-audited paths | |
| Skip previously-audited VRF functions entirely | Trust prior audit, only audit new code | |

**User's choice:** [auto] Fresh adversarial analysis — ignore prior findings (recommended default)
**Notes:** The entire premise of v5.0 is that bugs survive prior audits (BAF bug survived 12 rounds). Prior findings are NOT input to this phase.

---

## Cross-Module Call Boundary

| Option | Description | Selected |
|--------|-------------|----------|
| Trace for state coherence only | Follow subordinate calls to verify cached-local-vs-storage, defer full module audit | ✓ |
| Full trace into all subordinate modules | Audit everything advanceGame touches, regardless of module ownership | |
| Stop at module boundary entirely | Only audit code that lives in AdvanceModule.sol | |

**User's choice:** [auto] Trace for state coherence only (recommended default)
**Notes:** The BAF pattern requires checking if any descendant writes to storage an ancestor has cached. Must trace deep enough for that check. Full module internals are in their own unit phases (105-117).

---

## Claude's Discretion

- Function analysis ordering (risk-tier recommended, as in Phase 103)
- Cross-module trace depth (enough for cached-local-vs-storage, no more)
- Report file splitting (if needed for length)

## Deferred Ideas

- Phase 107 coordination on ticket queue write paths
- Phase 118 full cross-module integration sweep

## Auto-Resolved

- Function Categorization: auto-selected B/C/D only
- Ticket Queue Drain Scope: auto-selected dedicated section with standalone verdict
- VRF Audit Overlap: auto-selected fresh adversarial analysis
- Cross-Module Call Boundary: auto-selected trace for state coherence only
