# Phase 107: Mint + Purchase Flow - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-03-25
**Phase:** 107-mint-purchase-flow
**Mode:** auto (--auto flag)
**Areas discussed:** Function Categorization, Ticket Queue Write Path Scope, Cross-Module Call Boundary, Assembly Audit Depth

---

## Function Categorization

| Option | Description | Selected |
|--------|-------------|----------|
| B/C/D only -- no Category A | Module has no delegatecall dispatchers. External->B, Internal->C, View/Pure->D | Y |
| Include pseudo-Category A for processFutureTicketBatch routing | processFutureTicketBatch routes through multiple queue key spaces | |

**User's choice:** [auto] B/C/D only -- no Category A (recommended default)
**Notes:** MintModule is a delegatecall target, not a dispatcher. processFutureTicketBatch has routing logic but it's standard conditional branching, not delegatecall dispatch.

---

## Ticket Queue Write Path Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Full write-side analysis + Phase 104 coordination | Trace all ticket queue write paths, reference Phase 104 PROVEN SAFE for drain side, independently verify batch processing | Y |
| Minimal write-side, trust Phase 104 fully | Only trace _queueTicketsScaled, skip processFutureTicketBatch | |
| Full end-to-end re-audit | Re-audit both write and drain sides from scratch | |

**User's choice:** [auto] Full write-side analysis + Phase 104 coordination (recommended default)
**Notes:** Phase 104 declared ticket queue drain PROVEN SAFE (F-06: test setup issue). This phase focuses on the write side but independently verifies processFutureTicketBatch's batch processing logic (trait generation, remainder rolling, budget management).

---

## Cross-Module Call Boundary

| Option | Description | Selected |
|--------|-------------|----------|
| Trace for state coherence only | Follow calls to affiliate, BurnieCoin, sDGNRS to verify cached-local-vs-storage, defer full audit | Y |
| Full trace into all subordinate contracts | Audit everything purchase functions touch | |
| Stop at module boundary entirely | Only audit code in MintModule.sol and MintStreakUtils.sol | |

**User's choice:** [auto] Trace for state coherence only (recommended default)
**Notes:** Purchase functions make external calls to affiliate.payAffiliate, coin.creditFlip, coin.burnCoin, etc. These must be traced for state coherence (does the call write to any storage the caller cached locally?) but full internal audits are in their respective unit phases.

---

## Assembly Audit Depth

| Option | Description | Selected |
|--------|-------------|----------|
| Full Yul verification with storage slot derivation | Verify _raritySymbolBatch assembly: slot calculation, array length, data slot, LCG period | Y |
| Surface-level assembly review | Check for obvious issues only | |

**User's choice:** [auto] Full Yul verification with storage slot derivation (recommended default)
**Notes:** _raritySymbolBatch uses inline assembly to write trait tickets to storage. Storage slot calculation must be verified against Solidity's standard layout rules. LCG-based PRNG period and bias must be checked.

---

## Claude's Discretion

- Function analysis ordering (risk-tier recommended, as in Phase 103-105)
- Cross-module trace depth (enough for cached-local-vs-storage, no more)
- Report file splitting (if needed for length)

## Deferred Ideas

- Phase 111 lootbox resolution internals
- Phase 116 affiliate internal logic
- Phase 118 full cross-module integration sweep

## Auto-Resolved

- Function Categorization: auto-selected B/C/D only
- Ticket Queue Write Path Scope: auto-selected full write-side + Phase 104 coordination
- Cross-Module Call Boundary: auto-selected trace for state coherence only
- Assembly Audit Depth: auto-selected full Yul verification
