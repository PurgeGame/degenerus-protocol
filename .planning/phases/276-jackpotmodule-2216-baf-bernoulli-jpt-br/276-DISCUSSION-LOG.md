# Phase 276: JackpotModule:2216 BAF Bernoulli (JPT-BR) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-14
**Phase:** 276-JackpotModule:2216 BAF Bernoulli (JPT-BR)
**Areas discussed:** rngBypass arg on new _queueTickets call, Bernoulli code shape inside _jackpotTicketRoll

---

## Gray Areas Presented (multiSelect)

| Option | Description | Selected |
|--------|-------------|----------|
| rngBypass arg on new _queueTickets call | Roadmap JPT-BR-02 says `false`; current wrapper passes `true`; far-future levels would revert with `false` | ✓ |
| JackpotTicketWin.ticketCount field semantics post-Bernoulli | Keep pre-Bernoulli scaled vs switch to whole-derived | |
| Test layout — Phase 275 precedent vs REQUIREMENTS.md header | test/stat + test/unit vs test/jackpot/ | |
| Bernoulli code shape inside _jackpotTicketRoll | Inline vs extract _bernoulliWhole helper | ✓ |

Two non-selected areas were resolved without discussion: JackpotTicketWin field semantics (locked status-quo by EVT-UNI-04's own wording — captured as D-276-EVT-STATUSQUO-01) and test layout (folded into Claude's Discretion, planner reconciles Phase 275 precedent vs REQUIREMENTS.md header).

---

## rngBypass Arg on the New `_queueTickets` Call

| Option | Description | Selected |
|--------|-------------|----------|
| Pin to true (correct semantics) | `_queueTickets(... true)` — preserves current bypass; CONTEXT.md decision-anchor overrides roadmap `false` | ✓ |
| Keep false per roadmap | Follow JPT-BR-02 literally — would revert advanceGame on far-future jackpot ticket rolls | |
| Edit ROADMAP.md + REQUIREMENTS.md first | Fix the source docs to `true` before continuing | |

**User's choice:** Pin to `true`.
**Notes:** User supplied the governing design principle verbatim: "far future tickets awarded as part of the advancegame chain need to bypass the rng lock because they are a part of the deterministic sequence of jackpot awards that must happen for the game to move forward. far future tickets that are claimable on demand like lootboxes or whale passes need to revert during RNGlock or else they could influence jackpot outcomes." This is the asymmetry that makes Phase 275 LBX-AR's `false` correct for its surface and `true` correct here. Investigation evidence: `_jackpotTicketRoll` runs inside the `advanceGame` window before `_unlockRng` (`DegenerusGameAdvanceModule.sol:452-473`, `:1696-1703`); `_queueTickets` guard at `DegenerusGameStorage.sol:575` would revert with `false` on far-future target levels. Captured as D-276-RNGBYPASS-01. Roadmap/REQUIREMENTS text correction flagged as a follow-up (not edited mid-discuss).

---

## Bernoulli Code Shape Inside `_jackpotTicketRoll`

| Option | Description | Selected |
|--------|-------------|----------|
| Inline | ~4 lines of Bernoulli math inlined before the `_queueTickets` call | ✓ |
| Extract _bernoulliWhole helper | Private helper with slice as param — one call site only | |

**User's choice:** Inline.
**Notes:** `_jackpotTicketRoll` is a single-path function (no sentinel-gated branch like Phase 275's `_resolveLootboxCommon`). A helper would have exactly one call site, slice offsets differ across surfaces (`[152..167]` vs `[200..215]`), and a cross-module helper would require re-touching Phase 275's committed code. Phase 275 deferred the helper for the same reason. Captured as D-276-INLINE-01.

---

## Claude's Discretion

- Exact bit-allocation NatSpec wording (JPT-BR-06).
- Exact `JackpotTicketWin` event-doc NatSpec + inline-comment wording updates.
- Storage-layout byte-identity proof recipe.
- Test filenames, function names, and folder placement (Phase 275 precedent vs REQUIREMENTS.md §TST-JPT-BR header — planner reconciles).
- Theoretical worst-case gas path derivation (`feedback_gas_worst_case.md`) — likely the 5%-branch far-future cold-queue path.

## Deferred Ideas

- `_queueLootboxTickets` wrapper retirement — Phase 278 JPT-CLEAN-05.
- `xTICKET_SCALE` cosmetic cleanup — Phase 278 JPT-CLEAN-01..03.
- ENT-05 BAF xorshift refactor — Phase 278 JPT-CLEAN-04.
- `JackpotTicketWin.roundedUp` field — Phase 277 EVT-UNI-04.
- `_bernoulliWhole` shared helper — rejected per D-276-INLINE-01 (same disposition as Phase 275 option A3).
- Cross-surface mixing regression TST-CROSS-01 — Phase 278.
- Full-stack 4-caller seed-uniqueness exercise — deferred option if Phase 279 adversarial pass surfaces a concern.
