# Requirements — v56.0 AfKing Everyday-Gas Minimization

> **Baseline:** v55.0 HEAD — frozen contract subject `453f8073`, closure `MILESTONE_V55_AT_HEAD_ca3bbd3220de763298ef2e742111f6e6ef90d583`.
> **Design-lock input:** `.planning/PLAN-V56-AFKING-BATCHING-GAS.md` + the `[[v56-batch-afking-affiliate-quest-seed]]` memory.
> **Scope (USER-locked):** the AFKING SYSTEM specifically — **BOTH ENDS: the BUYING (the per-day process STAGE / accrual / settle) AND the OPENING (the box open-pass / materialize)**. Make the whole afking path maximally gas-efficient while remaining COMPLETELY secure and UNMANIPULABLE (no economic edge from any "fuckery" — with particular focus on gaining an edge by subscribing/unsubscribing strategically). NOT a whole-ecosystem sweep — afking buy + open only (shared-code touches handled with care).
> **Posture:** **NOT a behavior-identical pass** — slight semantic simplifications are acceptable if they cut gas and stay unmanipulable; the hard floor is unmanipulable + secure, enforced by a mandatory 3-skill adversarial economic review PLUS a baked-in **cross-model (Codex + Gemini) review** (XMODEL below — crafted prompts, in-milestone). Carefully-sequenced batched USER-APPROVED contract diff (HARD STOP at the contract-commit boundary); sequential-on-main (worktrees unsafe: submodule + node_modules); pre-launch redeploy-fresh (storage break fine). FULL close (sweep IN-MILESTONE at TERMINAL, like v54/v55). Affiliate/quest rewards stay BURNIE flip-credit off the ETH/`claimablePool` path → SOLVENCY-01 not in scope (a BURNIE-emission-timing change).

---

## v56.0 Requirements

### AGG — Mode-agnostic ~10-day aggregator settlement
- [ ] **AGG-01**: Per buy, the STAGE accrues the affiliate base + quest progress into a per-sub accumulator with NO cross-contract calls (the cheap hot path — replaces the per-buy `handlePurchase`/`payAffiliate`/`creditFlip` storm).
- [ ] **AGG-02**: A scheduled ~10-day flush (a `mintBurnie` "settlement-due" router leg, seeded by the fixed window boundary) settles the accrued affiliate + quest exactly once per window.
- [ ] **AGG-03**: Any player-triggered sub mutation (`setDailyQuantity` / funding change / unsub) flushes the accrued amounts at locked params (deterministic 75/20/5 affiliate split, NO roll) BEFORE applying the change (the mutator pays the settle gas → churn self-limits).
- [ ] **AGG-04**: The aggregator settles affiliate + quest uniformly for BOTH ticket and lootbox subs (mode-agnostic — the single settlement path for all sub types).
- [ ] **AGG-05**: Double-settle is impossible — `windowStartDay` + `lastSettledDay` markers gate the scheduled flush and reset on any player-triggered flush (the `lastAutoBoughtDay`/`lastOpenedDay` idempotency shape).

### TKT — Ticket-mode parity (minimal write primitive)
- [ ] **TKT-01**: Afking ticket subs use a custom minimal function that ONLY writes the ticket entries to the queue (mirrors the lootbox box-stamp); the per-day `MintModule.purchaseWith` heavyweight and its inline affiliate/quest are removed from the per-buy path (deferred to the AGG aggregator).
- [ ] **TKT-02**: The custom ticket-write produces the same queued ticket entries as `purchaseWith`'s ticket leg (resolution-equivalent placement/trait/quantity); the afking-ticket century / x00 quantity-bonus parity (`MintModule:1243`) is explicitly decided — keep, or drop-for-simplicity under the scope latitude.

### AFF — Affiliate batching (non-exploitable distribution)
- [ ] **AFF-01**: The scheduled flush keeps the winner-takes-all daily-seeded roll (seeded by the fixed window-boundary day — not player-chosen); the deterministic 75/20/5 split is used ONLY on the player-triggered-alteration path (so settle-timing can never select a favorable roll seed).
- [ ] **AFF-02**: The activity taper is applied per-buy at accrue (immutable); the affiliate leaderboard credit lumps into the settle-level (option A), with a force-flush-before-jackpot-snapshot path if the affiliate-selection ranking needs exactness.

### QST — Quest batching (shared `DegenerusQuests` core, non-perturbing)
- [ ] **QST-01**: The afking quest streak uses the ±10 model (+10 at subscribe / +10 per 10-day window / −10 on unsub); the slot-0 reward accrues + pays in the settle; slot-1 remains the player's own manual quest.
- [ ] **QST-02**: Streak bonuses + the activity-score read the confirmed-delivered streak (never the +10 pre-credit) — derived from immutable debit-gated delivered-day markers (no injectable add/subtract lever, so no pre-credit-EV inflation).
- [ ] **QST-03**: An afk+manual double-credit guard (`lastCompletedDay` / `afkCoveredThroughDay`) prevents double streak credit on afk-covered days; the gap-reset is suppressed via an active-pass check (anti-reset without daily writes). Slot rewards are NEVER suppressed (only the duplicate streak credit).
- [ ] **QST-04**: The batched-settle entrypoint added to the shared `DegenerusQuests` core is proven non-perturbing to the manual / bingo / degenerette / boon callers (`awardQuestStreakBonus` etc.).
- [ ] **QST-05**: The pre-existing lootbox-quest BURNIE double-credit (O1 — `handlePurchase` internal `creditFlip` + the returned-and-re-credited value) is confirmed intended or fixed.

### OPEN — The afking opening end (max-efficient + unmanipulable)
- [ ] **OPEN-01**: The afking open path — `_openAfkingBox` → `resolveAfkingBox` + the `mintBurnie` open leg / the `autoOpen` cursor + `OPEN_BATCH` — is reviewed and optimized for maximum gas efficiency (the per-open marginal ~74–78k + the batch cost), reading no cold ledger and sharing the cheapest viable materialization with the human path.
- [ ] **OPEN-02**: The afking open stays COMPLETELY unmanipulable under the v56 changes: the live-level open = parity with human `openLootBox` (open is permissionless + bounty-driven, never player-timed → no tier-timing edge); no double-open (`lastOpenedDay` monotone); no EV-cap double-draw (the shared per-`(player,level)` budget); no shared-mutable-state hazard with the human route — all RE-VERIFIED after the accrual/settle refactor.

### GAS — Everyday-cost reduction (measured)
- [ ] **GAS-01**: The per-buy marginal is measurably reduced (target: lootbox ~206k → ~130–140k; ticket off the ~262k `purchaseWith` heavyweight), measured per-buy + per-settle marginal under the 16.7M HARD per-tx ceiling (a TST-06-style harness).
- [ ] **GAS-02**: The per-sub accumulator packs into the `Sub` slot's spare bits where feasible (no new cold per-buy SSTORE).
- [ ] **GAS-03**: `SUB_STAGE_BATCH` is re-tuned for the lower per-sub cost (throughput / headroom); the per-day STAGE stays under the 16.7M ceiling at the `SUBSCRIBER_CAP`.
- [ ] **GAS-04**: Redundant payment-mode branches / repeated SLOADs in the STAGE are collapsed where a slight simplification is cheaper (allowed under the scope latitude).

### SEC — Security floor (the hard gate)
- [ ] **SEC-01**: The afking system (buy + open) is unmanipulable — no positive-EV vector from roll-timing, **strategic sub/unsub churn (the USER-flagged PRIMARY concern — churn to re-rate / re-roll the affiliate / dodge a streak penalty / harvest or duplicate a settlement / reset a window)**, re-rate-on-alteration, pre-credit-EV inflation, double-credit, open-timing, or settle-griefing. The 3-skill adversarial economic review + the XMODEL cross-model review are the gate.
- [ ] **SEC-02**: SOLVENCY-01 is untouched — affiliate/quest rewards remain BURNIE flip-credit off the ETH/`claimablePool` path; the ETH/pool debit is byte-unchanged; RNG-freeze intact under the new accrual/settle.

### XMODEL — Cross-model review (Codex + Gemini, baked in)
- [ ] **XMODEL-01**: A cross-model review (Codex + Gemini, fed crafted prompts in-milestone) covers the FULL afking system — both the BUYING (STAGE / accrual / settle) and the OPENING (open-pass / materialize) — for (a) long-run gas-optimization suggestions and (b) adversarial verification that the design is completely unmanipulable, with PARTICULAR focus on gaining an edge by strategic sub/unsub. Runs at SPEC (design input — suggestions folded into the design-lock before IMPL) and the cross-model models AUGMENT the TERMINAL adversarial close (Claude 3-skill + Codex + Gemini).

### AUDIT — Terminal close
- [ ] **AUDIT-01**: The in-milestone TERMINAL close — delta-audit (every changed surface NON-WIDENING vs the v55 baseline `453f8073`) + the mandatory 3-skill genuine-parallel adversarial economic review (`/contract-auditor` + `/economic-analyst` + `/zero-day-hunter`; `/degen-skeptic` dual-gate filter) + `audit/FINDINGS-v56.0.md` + the atomic closure flip.

## Future Requirements (deferred)
- Generalized operator-spend of `claimableWinnings` (carried from v54/v55) — larger blast radius, separate optional feature.
- The WWXRP 8-match jackpot whale-halfpass ([[wwxrp-jackpot-whalepass-seed]]) — small, foldable into a later bundle, NOT v56.
- The terminal-decimator final-day streak-boost ([[terminal-decimator-final-day-streak-boost-seed]]) — separate feature, NOT v56.

## Out of Scope
- The v52 consolidated cross-model audit (separate track; v56's surface folds into it as an additional track, not a substitute for v56's own in-milestone close).
- Restoring the old escalating/milestone streak BURNIE payout (USER-declined 2026-05-31 — the 1%/activity-score model stays).
- Any ETH/`claimablePool`/solvency-path change (this is a BURNIE-emission-timing + gas change only).
- Off-chain indexer / webpage (separate frontend track).

## Traceability

_(empty — filled by the roadmapper: each REQ-ID maps to exactly one phase; phases continue from 352 → 353.)_
