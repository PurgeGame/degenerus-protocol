# QST — Afking Quest BURNIE + Streak (v56 amendment DRAFT)

**Status:** FOLDED into 353-SPEC.md + REQUIREMENTS + ROADMAP 2026-06-01.
**USER decisions (2026-06-01):** quests stay AUTOMATIC (push, NOT pull); the streak head-start is a simple first-sub-only `+daysToNextSettle` (no provisional/vesting); quest BURNIE rides the `mintBurnie` "settlement-due" router chain when due; ADD a permissionless claim button as a keeper-liveness fallback.
**Anchors:** `QUEST_SLOT0_REWARD` / `QUEST_RANDOM_REWARD` (flat 100 / 200 BURNIE); streak machinery in `DegenerusQuests` (`lastCompletedDay` `:1596`); activity-score `MintStreakUtils:198` (1%/streak). BURNIE = `creditFlip`, OFF the ETH/`claimablePool` solvency path.

## What is paid
- **Slot-0 completion reward** = the ONLY direct quest BURNIE: the existing flat **100 BURNIE per delivered day** (an afking buy completes slot-0 = MINT_ETH each delivered day).
- **Slot-1** (~200 random) stays the player's **MANUAL** quest — afking does NOT auto-collect it.
- **The ±10 streak is NOT direct BURNIE** — it is the activity-score multiplier (1%/streak → lootbox EV / century at resolution). The old escalating direct streak-BURNIE bonus stays retired (USER 2026-05-31).

## Streak model (SIMPLIFIED — drops the provisional/vesting machinery)
- **First-sub-only head-start** (`hasEverSubscribed` 1-bit/account): on the FIRST-EVER subscribe, grant `streak += daysToNextSettleDay` (the days remaining in the current global ~10-day settle epoch). Re-subs after a cancel get NO fresh head-start.
- **Bounded +0..+9 over the manual baseline:** because the head-start is "days until the next global settle" (always < a full 10-day window), an afking sub is at most **+9** ahead of someone manually buying from the same point; the gap closes to **+0** by settle day as the manual baseline catches up. Never a full extra window.
- **NO provisional / NO decay / NO forfeit** — the grant is real immediately and kept. This SUPERSEDES the prior "confirmed-vs-provisional" guard for the afking grant: there is no +10 pre-credit to escrow; the bounded +0..+9 head-start IS the accepted exposure.
- **Otherwise** the streak tracks the normal ±10-per-window activity model, with reset/−10 on unsub (same as a manual buyer's gap-reset).
- **Accepted edge:** `sub → grab ≤+9 → bail` nets ≤+9 once per account (first-sub-only). A sybil could mint a fresh ≤+9 per NEW wallet, but each costs an afking pass → a **pass-cost-gated** farm, not a free one. USER-ACCEPTED as a non-issue.

## Quest BURNIE handling (AUTOMATIC push + claim fallback)
1. **Accrue (daily STAGE, cheap):** each delivered day, bump a delivered-day **counter** `questProgress` in the sub's slot (a COUNT, not a BURNIE amount → stays tiny). No cross-contract, no mint per day.
2. **Settle — automatic:** the **`mintBurnie` "settlement-due" router chain**, when a sub's settle is due (~10-day cadence), runs `_settleQuest(sub)` → mints `questProgress × QUEST_SLOT0_REWARD`, `creditFlip`s it to the sub (OFF the ETH/solvency path), advances the streak, zeroes the counter. **One cross-contract call per sub per ~10 days** — the v56 batching win (vs a per-day `creditFlip`).
3. **Settle — manual fallback (the claim button):** a **permissionless `claimQuest(address[] subs)`** runs the SAME `_settleQuest(sub)` (always credits the sub, never the caller) — a keeper-liveness safety so a player's earned quest BURNIE is never stranded if the router lags. Keeper path + claim button share one internal settle fn.
4. **Unsub:** `_settleQuest` the accrued counter first (mint what's owed) before removing the sub.
- **No day marker:** the counter is a self-marking running balance zeroed at settle (a double-fire finds `questProgress == 0`).

## Retained guards (UNCHANGED)
- **QST-03** `lastCompletedDay` / `afkCoveredThroughDay` double-credit guard (afk + manual on the same day) + active-pass anti-reset; slot rewards NEVER suppressed.
- **QST-04** the `DegenerusQuests` batched-settle entrypoint proven non-perturbing to manual / bingo / degenerette / boon callers.
- **QST-05** the O1 lootbox-quest BURNIE double-credit (confirmed-intended or fixed).

## What this changes in `353-SPEC.md` / REQUIREMENTS / ROADMAP
- **QST-01** — streak = first-sub-only `+daysToNextSettle` head-start (bounded +0..+9) + ±10/window; slot-0 = counter-accrue → settle-mint; slot-1 manual. NO provisional.
- **QST-02** — REFRAME: the afking head-start is a **bounded (+0..+9, first-sub-only) DIRECT** streak grant, USER-ACCEPTED; the "read confirmed-delivered, no pre-credit inflation" guard is SIMPLIFIED away for the afking grant (the bound replaces the escrow). The activity-score still reads the actual streak.
- **AGG-02 (quest leg)** — the `mintBurnie` settlement-due router chain mints the slot-0 quest BURNIE + advances the streak when due; **ADD `claimQuest(subs[])`** permissionless fallback.
- **QST-03/04/05** — UNCHANGED.
- **Storage** — `questProgress` = a delivered-day counter in the slot; + a `hasEverSubscribed` 1-bit/account.
