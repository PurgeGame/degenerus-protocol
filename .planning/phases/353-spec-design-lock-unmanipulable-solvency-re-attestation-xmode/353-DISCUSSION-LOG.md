# Phase 353: SPEC — Design-Lock + Unmanipulable/Solvency Re-Attestation + XMODEL Design-Input + Call-Graph Attestation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-01
**Phase:** 353-spec-design-lock-unmanipulable-solvency-re-attestation-xmode
**Areas discussed:** O1 double-credit (QST-05), Ticket century parity (TKT-02), Jackpot/affiliate leaderboard (AFF-02), XMODEL-01 scope; + bonus: quest-payout-system audit & dead-code (handleLootBox)

---

## Gray-area selection

| Option | Description | Selected |
|--------|-------------|----------|
| O1 double-credit | Adjudicate the lootbox-quest BURNIE double-credit | ✓ |
| Ticket century parity | Keep or drop the x00 quantity bonus in the new ticket primitive | ✓ |
| Jackpot force-flush | Does the jackpot affiliate snapshot need exactness? | ✓ |
| XMODEL-01 scope | How to run the codex + gemini design-input pass | ✓ |

**User's choice:** All four selected.

---

## O1 Double-Credit (QST-05)

First pass — disposition:

| Option | Description | Selected |
|--------|-------------|----------|
| Fix in v56 diff (drop from return) | Credit once via internal :890 | |
| Fix by dropping internal :890 | Credit once via caller batch | |
| Document only | Treat as pre-existing/immaterial | |

**User's response (clarify):** "what is the issue exactly? someone buys a lootbox and completes the 'buy something' quest and the 'buy a lootbox' secondary quest at the same time? that is by design" — then: "can we look at the quest payout system and see if this is bugged anywhere else too? if it is paying the lootbox quest completion in quest module AND also adding it to the aggregated payout in the mint module then we need to fix that."

**Resolution (after the requested system-wide audit):**
- Clarified O1 is NOT "two quests both pay" (by design) — it's ONE lootbox-quest reward `creditFlip`'d twice (internal `DegenerusQuests:890` + caller re-credit `MintModule:1232/1367`).
- Audited all 7 handlers + every caller: the pattern is **isolated** (handleMint guards, handleFlip/handleAffiliate credit once, handleDecimator uses the return as a weight boost, handleDegenerette ignores the return). Only `handlePurchase`'s lootbox leg is the bug.

Second pass — fix mechanic:

| Option | Description | Selected |
|--------|-------------|----------|
| Drop internal :890, credit via caller batch | Gas-optimal, one fewer creditFlip call | ✓ |
| Drop lootboxReward from the return, keep :890 | Smaller change to the return contract | |

**User's choice:** Drop internal `:890`, credit via the caller's batch.

---

## Dead Code (bonus find during the audit) — handleLootBox

| Option | Description | Selected |
|--------|-------------|----------|
| Remove it in the v56 diff | Delete fn + interface entry + access-control tests | ✓ |
| Leave it | Keep diff minimal, document instead | |

**User's choice:** Remove it in the v56 diff.
**Notes:** No production caller (superseded by handlePurchase); interface + access-control tests only; pre-launch redeploy makes the interface break fine.

---

## Ticket Century Parity (TKT-02)

| Option | Description | Selected |
|--------|-------------|----------|
| Drop for simplicity | Drop the century/x00 bonus for afking-ticket subs | ✓ |
| Keep at parity | Replicate the bonus in the new primitive | |
| Investigate first | Researcher measures EV/gas before deciding | |

**User's choice:** Drop for simplicity (intentional semantic simplification under the v56 scope latitude).

---

## Jackpot / Affiliate Leaderboard (AFF-02)

First framing (force-flush) — user redirected: "can we look to simplify this whole system to do fewer writes" and later "what do we even use affiliate leaderboard for? can we just delete it and save the gas?"

After investigating the consumers (1% top-affiliate DGNRS prize via `AdvanceModule:700`; 5% proportional DGNRS claim via `BingoModule:217`):

| Option | Description | Selected |
|--------|-------------|----------|
| Exclude afking from the leaderboard | Fewest writes, no force-flush; afking refs don't count toward DGNRS rank | |
| Keep at settle, accept level lag (no force-flush) | One batched write at settle, lumped into the settle-level | ✓ |
| Keep + force-flush before level transition | Exact attribution, most writes | |

**User's choice:** Keep at settle, accept level lag (no force-flush) — option A.
**Notes:** "ok I need it for the affiliate claim so we can't get rid of it. we can read the top once and compare to that so not much gas." Confirmed: the leaderboard is needed for the affiliate claim (can't delete); `_updateTopAffiliate` is read-once-compare, so keeping it is cheap. v56's aggregator already collapses the per-buy ×2 leaderboard writes into one-per-window at settle.

---

## XMODEL-01 Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Focused per-concern prompts, bespoke | Separate prompts per concern to codex + gemini, disposition table | ✓ |
| Single full-design-dump per model | One comprehensive prompt per model | |
| Reuse v52 coordinator.sh | Drive through the existing harness | |

**User's choice:** Focused per-concern bespoke prompts to both codex + gemini.
**Notes:** Both CLIs confirmed installed at `/home/zak/.local/bin/`. Do NOT reuse the v52 harness (shaped for the cumulative audit). Fold findings via a disposition table BEFORE IMPL.

---

## Claude's Discretion

- The per-sub accumulator storage layout (Sub spare-bits vs new slot + field widths — GAS-02 design feed) — researcher/planner resolves; lean = spare-bits per the PLAN doc.
- The precise ±10-streak / confirmed-vs-provisional marker derivation — locked in shape (carried forward), exact mechanism is a planning detail.

## Deferred Ideas

- Whether the afking path still calls `handlePurchase` per-buy under the v56 aggregator (vs deferring all quest work to the settle) — research item that scopes whether the O1 fix must cover the `GameAfkingModule:760` caller.
- No scope creep surfaced — discussion stayed within the v56.0 design-lock boundary.
