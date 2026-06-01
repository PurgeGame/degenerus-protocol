# Requirements — v56.0 AfKing Everyday-Gas Minimization

> **Baseline:** v55.0 HEAD — frozen contract subject `453f8073`, closure `MILESTONE_V55_AT_HEAD_ca3bbd3220de763298ef2e742111f6e6ef90d583`.
> **Design-lock input:** `.planning/PLAN-V56-AFKING-BATCHING-GAS.md` + the `[[v56-batch-afking-affiliate-quest-seed]]` memory.
> **Scope (USER-locked):** the AFKING SYSTEM specifically — **BOTH ENDS: the BUYING (the per-day process STAGE / accrual / settle) AND the OPENING (the box open-pass / materialize)**. Make the whole afking path maximally gas-efficient while remaining COMPLETELY secure and UNMANIPULABLE (no economic edge from any "fuckery" — with particular focus on gaining an edge by subscribing/unsubscribing strategically). NOT a whole-ecosystem sweep — afking buy + open only (shared-code touches handled with care).
> **Posture:** **NOT a behavior-identical pass** — slight semantic simplifications are acceptable if they cut gas and stay unmanipulable; the hard floor is unmanipulable + secure, enforced by a mandatory 3-skill adversarial economic review PLUS a baked-in **cross-model (Codex + Gemini) review** (XMODEL below — crafted prompts, in-milestone). Carefully-sequenced batched USER-APPROVED contract diff (HARD STOP at the contract-commit boundary); sequential-on-main (worktrees unsafe: submodule + node_modules); pre-launch redeploy-fresh (storage break fine). FULL close (sweep IN-MILESTONE at TERMINAL, like v54/v55). Affiliate/quest rewards stay BURNIE flip-credit off the ETH/`claimablePool` path → SOLVENCY-01 not in scope (a BURNIE-emission-timing change).

---

## v56.0 Requirements

### AGG — Mode-agnostic ~10-day aggregator settlement
- [x] **AGG-01**: Per buy, the STAGE accrues the affiliate base + quest progress into a per-sub accumulator with NO cross-contract calls (the cheap hot path — replaces the per-buy `handlePurchase`/`payAffiliate`/`creditFlip` storm). **(accrue producer built 354-03; the affiliate PULL consumer `claim`/`withdraw` completing the no-cross-contract-on-the-hot-path design built 354-04.)**
- [ ] **AGG-02**: The QUEST leg settles AUTOMATICALLY by RIDING THE DAILY BUY STAGE on the global settle day (`currentDay % settlePeriod == 0`, ~10-day cadence) — the internal `_settleQuest(sub)` runs INLINE in the STAGE (riding the warm Sub-slot write the buy already does), minting the sub's accrued slot-0 `questProgress × QUEST_SLOT0_REWARD` BURNIE **+ the accrued `buyerOwedBurnie` ticket buyer-bonus** in ONE `creditFlip` to the sub + applies the streak, draining both counters once per epoch — PLUS a permissionless `claimQuest(address[] subs)` keeper-liveness fallback running the SAME `_settleQuest(sub)` (always credits the sub, never the caller); quests stay AUTOMATIC (the sub's own reward; no sub action). The separate `mintBurnie` "settlement-due" router leg is REJECTED as a redundant cold-SLOAD pass; `SUB_STAGE_BATCH` is SHRUNK so the heavier settle-day chunk fits the 16.7M ceiling (number deferred to 355). **(amended 2026-06-01 — quest settle RIDES THE BUY STAGE [separate settlement-due leg rejected]; the slot-0 quest BURNIE + the 10%/20% ticket buyer-bonus mint TOGETHER in one creditFlip; the AFFILIATE leg is PULL with NO scheduled flush; claimQuest fallback stays; first-sub-only +daysToNextSettle streak, no provisional. See `353-SPEC.md` AGG/QST/TKT.)**
- [ ] **AGG-03**: A player-triggered unsub triggers a lightweight QUEST-settle that drains the sub's accrued `questProgress` → one `creditFlip` to the sub before applying the change; the AFFILIATE base is NOT flushed on mutation — it persists in the slot for the uplines to PULL (an unsub does not forfeit the uplines' accrued affiliate). **(amended 2026-06-01 — flat-7% deterministic-split pull; quests stay automatic: the prior "player-flush replays the fixed-seed roll" mechanism is REMOVED — there is no affiliate roll/flush at all. See `353-SPEC.md` AFF-01/AGG.)**
- [x] **AGG-04**: The QUEST-settle path settles uniformly for BOTH ticket and lootbox subs (mode-agnostic — `questProgress` is mode-independent); the affiliate base is likewise mode-agnostic and pulled uniformly via `claim`. **(amended 2026-06-01 — flat-7% deterministic-split pull; quests stay automatic.) (the mode-agnostic affiliate PULL `claim` — uniform for ticket + lootbox subs — built 354-04; the mode-agnostic quest settle built 354-03.)**
- [x] **AGG-05**: Double-settle is impossible via self-marking running balances — the affiliate `claim` zeroes `affiliateBase[sub]` (a re-claim sees `B == 0` → no-op) and the quest flush drains `questProgress` (a double-fire finds `0` → no-op); the per-sub `windowStartDay`/`lastSettledDay` double-settle markers are DROPPED (the zeroed running balance is self-marking). **(amended 2026-06-01 — flat-7% deterministic-split pull; quests stay automatic: markers DROPPED. See `353-SPEC.md` AGG.)**

### TKT — Ticket-mode parity (minimal write primitive)
- [x] **TKT-01**: Afking ticket subs use a custom minimal function that ONLY writes the ticket entries to the queue (mirrors the lootbox box-stamp); the per-day `MintModule.purchaseWith` heavyweight and its inline affiliate/quest are removed from the per-buy path (deferred to the AGG aggregator). The primitive ADDITIONALLY ACCRUES the 10%/20% ticket buyer-bonus per buy (`DegenerusGameMintModule.sol:1655-1659` — flat 10% of the BURNIE-equivalent ticket spend, doubling to 20% for ≥10-ticket buys) into the per-sub `buyerOwedBurnie` field — closing the v55-style regression where the bypass-`_callTicketPurchase` primitive silently DROPPED the buyer-bonus. **(amended 2026-06-01 — the minimal-write primitive accrues the 10%/20% ticket buyer-bonus into the per-sub buyer-owed-BURNIE field, matching live `:1655` minus the affiliate-kickback leg; the dropped-bonus regression risk is CLOSED. See `353-SPEC.md` TKT/Accumulator.)**
- [x] **TKT-02**: The custom ticket-write produces the same queued ticket entries as `purchaseWith`'s ticket leg (resolution-equivalent placement/trait/quantity); the afking-ticket century / x00 quantity-bonus parity (`MintModule:1243`) is explicitly decided — keep, or drop-for-simplicity under the scope latitude. The 10%/20% ticket buyer-bonus is at PARITY with live (`:1655-1659`), accrued per buy into `buyerOwedBurnie` and minted to the sub TOGETHER WITH the slot-0 quest reward at the quest STAGE settle (one `creditFlip`); it is ticket-mode-specific (lootbox subs use the boon) and pays the BUYER so it rides the quest PUSH, not the affiliate PULL. **(amended 2026-06-01 — the afking ticket primitive accrues the 10%/20% buyer-bonus at live parity [minus kickback]; settled with the quest. See `353-SPEC.md` TKT/QST.)**

### AFF — Affiliate batching (non-exploitable distribution)
- [x] **AFF-01**: The afking affiliate distribution is a flat-7% deterministic-split PULL — per buy accrue `_ethToBurnie(ethSpent) × 7/100` (flat, no taper, no kickback) into the sub's running `affiliateBase`; settle by PULL via `claim(address[] subs)` (same-affiliate batch, ONE `sumB`, the fixed 75/20/5 split computed once → `pendingClaim[A/U1/U2]`, buyer-never-wins via `A ≠ sub` guaranteed + the rare U1/U2==sub cycle skip, `DegenerusAffiliate.sol:579`); `withdraw()` = the only cross-contract `creditFlip` (CEI). There is NO roll, NO seed, NO scheduled/mutation affiliate flush — so settle-timing cannot select a favorable seed AND no two-distribution free option can exist (exactly ONE deterministic path). **(amended 2026-06-01 — flat-7% deterministic-split pull; quests stay automatic: SUPERSEDES the XMODEL roll-unification — the roll itself is REMOVED, so the C1/C2 free-option finding is MOOT. Adversarially re-cleared, economic-analyst + zero-day-hunter, no Medium+. See `353-SPEC.md` AFF-01.)**
- [x] **AFF-02**: The activity taper is afking-N/A (flat 7%; the `_applyLootboxTaper` anti-concentration reduction applies to MANUAL buys only); the affiliate leaderboard credits at `claim` time to the direct affiliate `A` (USER-accepted claim-time distortion). **(amended 2026-06-01 — flat-7% deterministic-split pull; quests stay automatic: replaces the option-A-lump-at-settle wording — there is no scheduled affiliate settle under the pull. See `353-SPEC.md` AFF-02.)**

### QST — Quest batching (shared `DegenerusQuests` core, non-perturbing)
- [ ] **QST-01**: The afking quest streak uses a SIMPLIFIED first-sub-only `+daysToNextSettle` head-start (`hasEverSubscribed` 1-bit; bounded +0..+9 over the manual baseline, no provisional/vesting) on top of the ±10-per-window activity model (−10 on unsub); the slot-0 reward accrues as a delivered-day `questProgress` COUNTER → settled = mint `× QUEST_SLOT0_REWARD` (the ONLY direct quest BURNIE); slot-1 remains the player's own manual quest; the ±10 streak is the activity-score multiplier, NOT direct BURNIE. **(amended 2026-06-01 — automatic slot-0 BURNIE via mintBurnie chain + claimQuest fallback; first-sub-only +daysToNextSettle streak, no provisional. See `353-SPEC.md` QST.)**
- [ ] **QST-02**: The first-sub-only `+daysToNextSettle` head-start is a bounded (+0..+9, once/account) DIRECT streak grant that is USER-ACCEPTED-BY-DESIGN — the prior "read confirmed-delivered, never the +10 pre-credit / no pre-credit-EV inflation" escrow guard is SIMPLIFIED AWAY for the afking grant (the bound REPLACES the escrow; a deliberate accepted tradeoff, NOT a missed control — 356/357 treat it as accepted-by-design); the activity-score still reads the actual `state.streak`, and the per-window streak still advances only on debit-DELIVERED days (the C3-a streak-dodge fix stays in force). **(amended 2026-06-01 — automatic slot-0 BURNIE via mintBurnie chain + claimQuest fallback; first-sub-only +daysToNextSettle streak, no provisional. See `353-SPEC.md` QST-02 reframe.)**
- [ ] **QST-03**: An afk+manual double-credit guard (`lastCompletedDay` / `afkCoveredThroughDay`) prevents double streak credit on afk-covered days; the gap-reset is suppressed via an active-pass check (anti-reset without daily writes). Slot rewards are NEVER suppressed (only the duplicate streak credit).
- [ ] **QST-04**: The batched-settle entrypoint added to the shared `DegenerusQuests` core is proven non-perturbing to the manual / bingo / degenerette / boon callers (`awardQuestStreakBonus` etc.).
- [ ] **QST-05**: The pre-existing lootbox-quest BURNIE double-credit (O1 — `handlePurchase` internal `creditFlip` + the returned-and-re-credited value) is confirmed intended or fixed.

### OPEN — The afking opening end (max-efficient + unmanipulable)
- [x] **OPEN-01**: The afking open path — `_openAfkingBox` → `resolveAfkingBox` + the `mintBurnie` open leg / the `autoOpen` cursor + `OPEN_BATCH` — is reviewed and optimized for maximum gas efficiency (the per-open marginal ~74–78k + the batch cost), reading no cold ledger and sharing the cheapest viable materialization with the human path.
- [x] **OPEN-02**: The afking open stays COMPLETELY unmanipulable under the v56 changes: the live-level open = parity with human `openLootBox` (open is permissionless + bounty-driven, never player-timed → no tier-timing edge); no double-open (`lastOpenedDay` monotone); no EV-cap double-draw (the shared per-`(player,level)` budget); no shared-mutable-state hazard with the human route — all RE-VERIFIED after the accrual/settle refactor.

### GAS — Everyday-cost reduction (measured)
- [ ] **GAS-01**: The per-buy marginal is measurably reduced (target: lootbox ~206k → ~130–140k; ticket off the ~262k `purchaseWith` heavyweight), measured per-buy + per-settle marginal under the 16.7M HARD per-tx ceiling (a TST-06-style harness).
- [ ] **GAS-02**: The per-sub accumulator packs into the `Sub` slot's spare bits where feasible (no new cold per-buy SSTORE). **(amended 2026-06-01 — flat-7% deterministic-split pull; quests stay automatic: the accumulator SHRINKS to `affiliateBase uint32` (whole-BURNIE, 100M clamp) + `questProgress`, both self-marking running balances [`windowStartDay`/`lastSettledDay` DROPPED]; the off-slot `pendingClaim` mapping (affiliate recipients) is touched at `claim`/`withdraw`, never per-buy.)**
- [ ] **GAS-03**: `SUB_STAGE_BATCH` is re-tuned for the lower per-sub cost (throughput / headroom); the per-day STAGE stays under the 16.7M ceiling at the `SUBSCRIBER_CAP`.
- [ ] **GAS-04**: Redundant payment-mode branches / repeated SLOADs in the STAGE are collapsed where a slight simplification is cheaper (allowed under the scope latitude).

### SEC — Security floor (the hard gate)
- [ ] **SEC-01**: The afking system (buy + open) is unmanipulable — no positive-EV vector from settle-timing (no seed — _amended 2026-06-01 — flat-7% deterministic-split pull; quests stay automatic: the roll/seed is REMOVED_), **strategic sub/unsub churn (the USER-flagged PRIMARY concern — churn to re-claim the affiliate [the accrued `affiliateBase` persists for the uplines → forfeit-nothing-gain-nothing] / dodge a streak penalty / harvest or duplicate a settlement)**, re-rate-on-alteration, pre-credit-EV inflation, double-credit, open-timing, or settle-griefing. The 3-skill adversarial economic review + the XMODEL cross-model review are the gate.
- [ ] **SEC-02**: SOLVENCY-01 is untouched — affiliate/quest rewards remain BURNIE flip-credit off the ETH/`claimablePool` path; the ETH/pool debit is byte-unchanged; RNG-freeze intact under the new accrual/settle.

### XMODEL — Cross-model review (Codex + Gemini, baked in)
- [x] **XMODEL-01**: A cross-model review (Codex + Gemini, fed crafted prompts in-milestone) covers the FULL afking system — both the BUYING (STAGE / accrual / settle) and the OPENING (open-pass / materialize) — for (a) long-run gas-optimization suggestions and (b) adversarial verification that the design is completely unmanipulable, with PARTICULAR focus on gaining an edge by strategic sub/unsub. Runs at SPEC (design input — suggestions folded into the design-lock before IMPL) and the cross-model models AUGMENT the TERMINAL adversarial close (Claude 3-skill + Codex + Gemini).

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

Each REQ-ID maps to exactly ONE phase (the phase that OWNS/delivers it). Phases continue from 352 → 353. **24/24 mapped, 0 orphaned, 0 duplicated.** Shape: 353 SPEC → 354 IMPL → 355 GAS → 356 TST → 357 TERMINAL (the established v54.0/v55.0 audit pattern). Full phase detail + per-requirement center-of-gravity rationale: `.planning/ROADMAP.md` (Phase Details + Coverage).

| Requirement | Phase | Phase Type | Status |
|-------------|-------|------------|--------|
| AGG-01 | Phase 354 | IMPL | Complete |
| AGG-02 | Phase 354 | IMPL | Pending |
| AGG-03 | Phase 354 | IMPL | Pending |
| AGG-04 | Phase 354 | IMPL | Complete |
| AGG-05 | Phase 354 | IMPL | Complete |
| TKT-01 | Phase 354 | IMPL | Pending |
| TKT-02 | Phase 354 | IMPL | Pending |
| AFF-01 | Phase 353 | SPEC | Complete |
| AFF-02 | Phase 353 | SPEC | Complete |
| QST-01 | Phase 354 | IMPL | Pending |
| QST-02 | Phase 354 | IMPL | Pending |
| QST-03 | Phase 354 | IMPL | Pending |
| QST-04 | Phase 354 | IMPL | Pending |
| QST-05 | Phase 354 | IMPL | Pending |
| OPEN-01 | Phase 354 | IMPL | Pending |
| OPEN-02 | Phase 354 | IMPL | Pending |
| GAS-01 | Phase 355 | GAS | Pending |
| GAS-02 | Phase 355 | GAS | Pending |
| GAS-03 | Phase 355 | GAS | Pending |
| GAS-04 | Phase 355 | GAS | Pending |
| SEC-01 | Phase 356 | TST | Pending |
| SEC-02 | Phase 356 | TST | Pending |
| XMODEL-01 | Phase 353 | SPEC (home — design-input; TERMINAL 357 close-augmentation reflected in AUDIT-01 SC) | Complete |
| AUDIT-01 | Phase 357 | TERMINAL | Pending |

**Per-phase rollup:**

| Phase | Type | Requirements | Count |
|-------|------|--------------|-------|
| 353 | SPEC | AFF-01, AFF-02, XMODEL-01 | 3 |
| 354 | IMPL | AGG-01, AGG-02, AGG-03, AGG-04, AGG-05, TKT-01, TKT-02, QST-01, QST-02, QST-03, QST-04, QST-05, OPEN-01, OPEN-02 | 14 |
| 355 | GAS | GAS-01, GAS-02, GAS-03, GAS-04 | 4 |
| 356 | TST | SEC-01, SEC-02 | 2 |
| 357 | TERMINAL | AUDIT-01 | 1 |
| **Total** | | | **24** |

**Per-category rollup:**

| Category | Total | Phase(s) |
|----------|-------|----------|
| AGG | 5 | 354 IMPL |
| TKT | 2 | 354 IMPL |
| AFF | 2 | 353 SPEC |
| QST | 5 | 354 IMPL |
| OPEN | 2 | 354 IMPL |
| GAS | 4 | 355 GAS |
| SEC | 2 | 356 TST |
| XMODEL | 1 | 353 SPEC (home) + 357 TERMINAL (close touchpoint) |
| AUDIT | 1 | 357 TERMINAL |
| **Total** | **24** | |

**Center-of-gravity notes (where a requirement's work spans phases):**

- **AFF-01 / AFF-02 → SPEC (353):** the affiliate distribution mechanism (the flat-7% deterministic-split PULL — accrue flat 7% per buy into the running `affiliateBase`, settle by PULL via `claim`/`withdraw` with the fixed 75/20/5 split; taper afking-N/A + leaderboard-at-claim — _amended 2026-06-01 — flat-7% deterministic-split pull; quests stay automatic: SUPERSEDES the XMODEL roll-unification, the roll is removed_) is a DESIGN DECISION that gates non-gameability — it is locked at SPEC and BUILT at IMPL (the affiliate PULL `claim`/`withdraw` + the QUEST-only AGG-02/03 settle plumbing consume the AFF rule). No double-count: AGG = the quest accrue/settle plumbing + the affiliate accrue; AFF = the distribution rule the `claim` PULL applies.
- **XMODEL-01 → SPEC (353) home + TERMINAL (357) touchpoint:** its PRIMARY deliverable is the design-input cross-model pass folded into the design-lock BEFORE IMPL (the gating half → home = SPEC); its TERMINAL close-augmentation (Codex + Gemini augmenting the Claude 3-skill sweep) is reflected in AUDIT-01's success criteria (Phase 357), not separately counted.
- **SEC-01 / SEC-02 → TST (356):** the hard security floor (unmanipulable esp. strategic sub/unsub; SOLVENCY-01 untouched + RNG-freeze intact) is PROVEN empirically + adversarially at TST as the gate (mirrors v55, where FREEZE design lived at SPEC but the empirical proofs were a distinct phase). The SPEC "SEC design" (the unmanipulable/solvency/freeze re-attestation on paper) is the design gate folded into 353's SC5, and the TERMINAL adversarial review (AUDIT-01) is the final re-confirmation — SEC-01/02's center-of-gravity (first PROVEN) is TST.
- **AGG / TKT / QST / OPEN → IMPL (354):** the built behaviors. The SPEC concerns they feed (accumulator layout, ticket-primitive shape, the DegenerusQuests batched-settle entrypoint + non-perturbation approach, the ±10-streak derivation, the open-end review) are folded into 353's SC2/SC3/SC4 — counted only at their IMPL home.
- **GAS → GAS (355):** measured everyday-cost reduction; much of GAS-01/02 is structural to the IMPL refactor (the GAS phase MEASURES + lands the residual `SUB_STAGE_BATCH` re-tune + mode/SLOAD collapse, or records Outcome-A no-diff per the v55 350 precedent).
- **AUDIT-01 → TERMINAL (357):** the FULL in-milestone close re-attests all 24 requirements.
