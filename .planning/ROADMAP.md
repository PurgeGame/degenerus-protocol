# Roadmap — Milestone v75.0 — Ticket/Entry Correctness + Disambiguation

> **Subject (RESETS the audit subject — contract LOGIC change):** baseline = local HEAD `cdd32fe9` (clean `contracts/` tree; not pushed). Resets off v74.0 closure `MILESTONE_V74_AT_HEAD_93d17288…` (`contracts/` tree `f06b1ef6`). **Numbering continues 478 → 479.**
> **The defect (FIXED in 479):** `ticketsOwedPacked.owed` is in ENTRIES (4 per whole ticket, each worth price/4). Two prize legs queued a whole-ticket count (`amount/price`, no `<<2`) into the entries sink → ¼ delivery: `JackpotModule._jackpotTicketRoll` (~2143) + `LootboxModule._lootboxTicketCount` (~2188)→queue (~1383, also reached via `DecimatorModule:673`). USER-confirmed (matched live RTP sim). Conservation-safe; winners under-paid. Fixed `b2ab3e9f` (canonical `wholeTicketsToEntries(w)=w<<2`).
> **Posture:** FOUR remaining contract-touching phases (480/481/482/483) each ship as ONE batched `.sol` diff behind the contract-commit approval gate (the sole gates). All test/golden/ABI/docs/verify/re-audit work commits autonomously.
> **ABI decision (LOCKED):** rename misleading event names/fields + normalize emitted units to entries (481); RENAME the 3 entries-returning view selectors; KEEP mechanism selectors. No live indexer decodes these events.
> **Threat weighting (locked):** DOMINANT RNG/freeze · HIGH gas-DoS in advanceGame (>16.7M = game-over) · SPINE solvency/backing · LOWER access/reentrancy/MEV.
> **Binding scope:** `.planning/v75-grounding/v75.0-ticket-entry-disambiguation-ledger.md` **§10** (owner decisions applied; governing principle §10.1: rename only entry-COUNT/VALUE holders; KEEP mechanism/subsystem names). Finding memory `prize-ticket-legs-whole-vs-entries-2026-06-29`.

---

## Prior Milestones (index)

> **Canonical milestone record = `.planning/milestones/` + git tags + `.planning/MILESTONES.md`.** This file holds the ACTIVE milestone's full roadmap above; on close it collapses to this index and the full roadmap moves to `milestones/v<X.Y>-ROADMAP.md`. Next milestone authors a fresh roadmap BY HAND (repo convention — gsd-sdk state mutators avoided).

- ✅ **v75.0 Ticket/Entry Correctness + Disambiguation** — Phases 479-484 (shipped 2026-06-30, tag `v75.0`) — 0 open findings
- ✅ **v74.0 As-Built Milestone Audit + C4A Package** — Phases 466-478 (shipped 2026-06-27, tag `v74.0`) — 0 open findings
- ✅ **v73.0 Degenerette "Variant-2" Color-Gated Rescore** — Phases 452-456 (shipped 2026-06-21, tag `v73.0`)
- ✅ **v72.0 As-Built Audit — Foil Pack + Degenerette WWXRP-Rig** — (shipped 2026-06-21, tag `v72.0`)
- 📋 Earlier milestones — see `.planning/MILESTONES.md` + `.planning/milestones/`

<details>
<summary>✅ v75.0 Ticket/Entry Correctness + Disambiguation (Phases 479-484) — SHIPPED 2026-06-30</summary>

Fixed ¼ ticket under-delivery in both prize legs via `wholeTicketsToEntries(w)=w<<2` + full ticket/entry disambiguation sweep. 3-model re-audit CLEAN (0 crit/high/med). 39 commits · 136 files · +6,254/−1,790.

- [x] Phase 479: CONV + VALUE-FIX (gated diff #1 — behavior) — `b2ab3e9f` / `7844ee7f`
- [x] Phase 480: RENAME-SWEEP (gated diff #2 — no behavior) — `bcc47ccc` / `848a56fe`
- [x] Phase 481: EVENT/ABI SURFACE + VIEW SELECTORS (gated diff #3 — ABI) — `94322027` / `046dd24b`
- [x] Phase 482: DEGENERETTE DEAD-MODE REPACK (gated diff #4 — behavior) — `310bccfc` / `27c113c4`
- [x] Phase 483: FF-SALVAGE ENTRY-GRANULARITY (gated diff #5 — behavior) — `61e40429` / `7d2c3a43`
- [x] Phase 484: VERIFY + CLOSE — `87a6dd76` + `795fa7ed`

Full roadmap + success criteria: `milestones/v75.0-ROADMAP.md`. Requirements: `milestones/v75.0-REQUIREMENTS.md`. Audit: `milestones/v75.0-v75.0-MILESTONE-AUDIT.md`. Findings: `audit/FINDINGS-v75.0.md`.

</details>

<details>
<summary>✅ v74.0 As-Built Milestone Audit + C4A Package (Phases 466-478) — SHIPPED 2026-06-27</summary>

Full milestone audit of the `v73.0 → HEAD` contract batch (29 .sol, +1873/−1032) + complete C4A package. **0 open findings**; the sole conditional contract gate (475) fired once → 1 MEDIUM (DegenerusAdmin recovery-spanning VRF-swap proposal) owner-approved-fixed `93d17288`. Subject byte-frozen `contracts/` tree `f06b1ef6` @ `93d17288`; closure `MILESTONE_V74_AT_HEAD_93d17288…`.

- [x] Phase 466: SUBJECT-FREEZE-CONFIRM
- [x] Phase 467: HARNESS-GREEN-GATE (test-only)
- [x] Phase 468: AUDIT-SOLV-FOLD
- [x] Phase 469: AUDIT-RNG-LIVENESS
- [x] Phase 470: AUDIT-ACCESS-PERMISSIONLESS
- [x] Phase 471: AUDIT-EV-RTP
- [x] Phase 472: AUDIT-RENAME-WIRING-STORAGE
- [x] Phase 473: AUDIT-GAS-FAUCET
- [x] Phase 474: MANIFEST-REPOINT
- [x] Phase 475: CROSS-MODEL-REAUDIT (sole conditional contract gate — fired once, resolved)
- [x] Phase 476: AGENT-SOAK-REATTEST
- [x] Phase 477: C4A-PACKAGE
- [x] Phase 478: TERMINAL

Full roadmap + success criteria: `milestones/v74.0-ROADMAP.md`. Requirements: `milestones/v74.0-REQUIREMENTS.md`. Findings: `audit/FINDINGS-v74.0.md`. Phase execution record: `milestones/v74.0-phases/`.

</details>

