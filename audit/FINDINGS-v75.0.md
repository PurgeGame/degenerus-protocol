# FINDINGS — Milestone v75.0 (Ticket/Entry Correctness + Disambiguation)

**Date:** 2026-06-30 · **Subject:** `git diff cdd32fe9..HEAD -- contracts/` (5 gated diffs, 19 files, +681/−674) · **Verdict: CLEAN — SAFE TO SHIP.**

## Scope audited
The 5 gated contract diffs: 479 (value fix — the ¼ under-delivery), 480 (identifier rename, no behavior), 481 (event/ABI + view selectors), 482 (degenerette dead-mode repack), 483 (FF-salvage entry-granularity).

## Cross-model re-audit (3 independent perspectives, adversarially verified)
- **Codex (GPT-5):** 0 findings; safe to ship.
- **GLM-5.2:** clean, 0 blocking; 3 low/nit (all non-defects, see below).
- **Claude-lens** (5-dimension workflow → adversarial refute → synthesize): 0 critical/high surviving; 1 nit.

All three converged: **no critical/high/medium defect.** The substantive verifications:
- **479:** `wholeTicketsToEntries(w)=w<<2` applied at exactly the 2 prize legs (Jackpot BAF roll `JackpotModule:2143`, Lootbox roll `LootboxModule:1383`) + Decimator **transitively** (delegates to the fixed Lootbox leg) — no missed ×4, no double ×4 across all 11 queue sites. emit==queue holds. Conservation **tightens** (pre-fix pool was ~4× over-backed; post-fix backing==delivery). Bernoulli round-up EV-neutral (`<<2` scales both branches by 4; `E[whole<<2]=4·E[whole]`). Overflow-safe (`whole<<2 ≤ ~171.8M < uint32 max`).
- **482:** dead `mode`/`isRandom`/`hasCustom` bits have **zero remaining readers**; `packed==0` no-bet sentinel preserved by `spinCount≥1` (validated before the only pack site); `DEGEN_*_SHIFT` fields tile `[0..219]` with no overlap/truncation; the one cross-fn currency decode moved `>>42`→`>>40` consistently; EV byte-identical.
- **483:** 5-site coupling exact (`×4` debit removal cancels `/4` face valuation — byte-identical at aligned `E=4W`, well-defined for sub-whole `n`); floor/too-small-revert relaxed to one entry; entries transferred seller→buyer (never minted, supply conserved); payout ≤ backing (solvency holds); no double-credit on duplicate levels.
- **480/481:** storage layout byte-stable (`--check` green); KEEP-set intact (`JackpotTicketWin` name, `FoilMatchClaimed.ticketIndex`, `futureTickets`, mechanism selectors, `AFKING_TICKET_SCALE`, the activation-queue cluster); the 2 inline-asm `.slot` reads bind the renamed var at the unchanged slot.
- **Cross-cutting:** no VRF-freeze violation, no `advanceGame` gas-DoS regression, no solvency-spine break, no bad cross-phase composition.

## Test floor (committed HEAD)
- `forge test` **1005/0/107** · `npm test` **1362/0** · layout `--check` **green** · 37 Bernoulli EV assertions green.
- **RTP re-sim:** `PrizeLegEntriesDelivery` 3/0 proves the prize-leg basis == purchase/daily `(B<<2)/price` (uniform entries-per-ETH); 479 ¼ under-delivery resolved (×4 corrected), EV-neutral.

## Surviving items — all cosmetic/known, NOT ship blockers (documented, not fixed in-milestone to avoid reopening a gated commit)
- **N1 (nit, 479/480):** `AdvanceModule:1615/1618` comment "16 generic tickets per level" reads as whole tickets; `VAULT_PERPETUAL_ENTRIES=16` feeds the entries sink → 16 **entries** (= 4 whole tickets). Comment-only; no behavior/value/layout impact. Reword to "16 entries (= 4 whole tickets)". → optional cleanup.
- **N2 (nit, 480, GLM):** stale "ticket units" doc comment in `_budgetToEntries`. → optional cleanup.
- **N3 (low, 479, GLM):** `_budgetToEntries` `priceForLevel==0` guard removed — a **known intentional** dead-guard trim (`priceForLevel` is never 0 in this path); not a defect.
- **N4 (nit, 480, GLM):** `dailyTicketBudgetsPacked` not renamed — **deliberate KEEP** (Jackpot "Ticket Jackpot" mechanism cluster).

## Disposition
**0 open findings. Milestone v75.0 cleared for closure.** The 4 nits above are optional cosmetic cleanup for a future touch (or a 484 doc pass alongside the `D-481-DOCS-01` jackpot-doc reconciliation), not blockers.
