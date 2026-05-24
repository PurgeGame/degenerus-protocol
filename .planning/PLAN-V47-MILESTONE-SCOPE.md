# v47.0 — Milestone Scope Manifest

**Status:** SCOPE-LOCKED, QUEUED. Single source of truth for what v47.0 contains. Created 2026-05-24.
**Hard prerequisite:** v46.0 must CLOSE first (Phase 320 TERMINAL — adversarial sweep + delta audit + closure). NO `contracts/` edits before v46.0 closure (would break its frozen-source delta-audit baseline). Every plan below repeats this.
**Posture:** pre-launch redeploy-fresh; storage-layout breaks fine, no migration scaffolding (`feedback_frozen_contracts_no_future_proofing`). Security floor over gas (`feedback_security_over_gas`).
**Approval model:** ONE batched USER-APPROVED contract diff for the whole milestone's contract surface (`feedback_batch_contract_approval` + `feedback_never_preapprove_contracts` + `feedback_manual_review_before_push`). Tests + planning AGENT-committable; `contracts/*.sol` USER-only.

---

## 1. The seven work items (all v47.0)

| # | Plan doc | Type | One-line |
|---|---|---|---|
| 1 | `PLAN-PRESALE-COIN-BOXES-RAKE-FREE.md` | FEATURE/ECON | Kill the 20% presale vault skim + 62% BURNIE bonus; add credit-gated coin-presale boxes (ETH→80% vault / 20% sDGNRS); `presaleOver` latch |
| 2 | `PLAN-LOOTBOX-BOON-UNIFICATION.md` | BEHAVIOR/SECURITY | **REMOVE BURNIE lootboxes** (terminal-paradox: unguardable BURNIE→future-ticket path) + unify the 3 remaining ETH callers to full boons+passes; fix 10% haircut; drop dead flags + all BURNIE-box carve-outs. Keep BURNIE→tickets |
| 3 | `PLAN-DEGENERETTE-RESOLUTION-GAS.md` | GAS (same-results) | Batch Degenerette `resolveBets` writes (cross-bet flush once; lootbox sum per-betId); RNG/freeze untouched |
| 4 | `PLAN-UNIVERSAL-CLAIMABLE-PAY.md` | UX/consistency | Every ETH-in path accepts `claimableWinnings` shortfall (whale bundle / lazy / deity passes + presale box) |
| 5 | `PLAN-SDGNRS-REDEMPTION-ACCOUNTING.md` | SECURITY/ACCOUNTING | sDGNRS redemption: ETH hard-segregation (fix `claimableWinnings[SDGNRS]` underflow) + BURNIE flip-credit-at-submit (fix BURNIE-blocks-ETH) |
| 6 | `PLAN-DEGENERETTE-SPINS-PER-CURRENCY.md` | BEHAVIOR | Degenerette max spins/bet → per-currency: ETH 25 / BURNIE 15 / WWXRP 5 (from global 10); min bet/spin unchanged |
| 7 | `PLAN-V47-AFKING-CANCEL-TOMBSTONE.md` | SECURITY/CORRECTNESS | Restore locked SUB-07: `setDailyQuantity(0)` → in-place tombstone (move nothing) + add the in-sweep tombstone-reclaim branch. Fixes **H-CANCEL-SWAP-MISS** (v46.0 audit) — cancel-behind-cursor relocates a pending tail → that sub misses a day → **mint streak resets** (up to −50% activity score). ISOLATED surface (`AfKing.sol` only). |

## 2. Why this is ONE batched contract diff (coordination map)

Plans 1–6 overlap heavily on the same files/functions — they cannot be independent diffs. The single approved diff must reconcile the surfaces below. (**Item 7 — `AfKing.sol` cancel-tombstone — is ISOLATED**: it shares no file/function with 1–6, so it adds to the batched diff without any cross-plan signature reconciliation.)

| Shared surface | Plans touching it | Coordination |
|---|---|---|
| `DegenerusGameLootboxModule.sol` — `_resolveLootboxCommon` + callers | 2 (REMOVE `openBurnieLootBox` → 3 ETH callers, flags), 5 (`resolveRedemptionLootbox`), 1 (presale box is its own boon-less resolution) | Settle the final `resolveRedemptionLootbox` signature once: **boon flag (2) + payable + no claimable debit (5)** together; plan 2 drops to 3 callers |
| `DegenerusGame.sol` / `MintModule` / `DegenerusVault` — BURNIE-lootbox removal | 2 (delete `purchaseBurnieLootbox`/`openBurnieLootBox`/`_purchaseBurnieLootboxFor`, `purchaseCoin` lootbox branch, vault wrapper) | Keep BURNIE→tickets (`purchaseCoin` ticketQuantity, vault `gamePurchaseTicketsBurnie`) |
| `DegenerusGame.sol` claimable accounting (`claimableWinnings` / `claimablePool`) | 1 (presale 80/20 ledger move), 4 (shortfall pattern), 5 (new `SDGNRS`-gated checked pull; remove unchecked debit) | Keep `claimablePool == Σ claimableWinnings` invariant balanced across all three |
| BURNIE flows | 1 (drop presale bonus, presale box mints BURNIE), 2 (REMOVE BURNIE lootbox — no more BURNIE→box conversion), 5 (`creditFlip` + burn/consume; `onlyFlipCreditors`+SDGNRS) | One pass over BURNIE mint/credit authority + sinks |
| `external payable` entry sweep (`DegenerusGame.sol`) | 4 (apply claimable-pay uniformly), 5 (lootbox becomes payable) | Audit all payable entries once |
| `DegenerusGameDegeneretteModule.sol` | 3 (batch resolveBets writes), 6 (per-currency spin caps) | Same file — one edit; 6 raises the loop bound (≤25 ETH) the gas-batching in 3 must absorb |
| Earlybird subsystem removal (plan 1 replaces it) | 1 — touches `MintModule:1210`, `WhaleModule:263/476/587`, `AdvanceModule:1672-1673/1744`, `DegenerusGameStorage:966-1013` + state/consts | Plan 1 grew from "presale boxes" to ALSO "remove earlybird emission"; rename `Pool.Earlybird`→`PresaleBox` |

**Most critical single point:** `resolveRedemptionLootbox` is edited by BOTH plan 2 and plan 5 — apply on the final signature in one diff (cross-refs already in both docs).

## 3. Execution path (the sequence that gets all 5 done)

1. **Close v46.0** — run Phase 320 TERMINAL (adversarial sweep on `fundingSource` + delta audit + closure; OPENE-01..04 attest here). Establishes the v47 audit baseline HEAD. *(Prereq for any v47 contract work.)*
2. **Create v47.0 milestone** — `/gsd-new-milestone`, ingesting this manifest as scope → `v47.0-REQUIREMENTS.md` + `v47.0-ROADMAP.md` + phases.
3. **Plan + execute v47 phases** (suggested shape, roadmapper finalizes):
   - **Phase A — contracts (ONE batched diff):** all 5 plans' contract edits, reconciled per §2, presented as a single USER-approved diff. HARD STOP at the contract boundary.
   - **Phase B — tests:** repro-first for plan 5 (two-claimant ETH underflow; BURNIE-can't-block-ETH; conservation), same-results gas proof for plan 3, behavior/EV tests for plans 1–2, claimable-pay coverage for plan 4.
   - **Phase C — terminal:** delta audit vs the v46.0 baseline + findings + closure (mirrors v45/v46 terminal pattern).
4. **Calibration gate:** plan 1 carries TO-CALIBRATE numbers; lock those at plan-time before Phase A.

## 4. Decision status (prep pass 2026-05-24)

**LOCKED (defaults applied to plan docs; override at plan-time):**
- Plan 5 (sDGNRS): MAX-pull shortfall → **revert**; BURNIE settle → single `redeemBurnieShare`; gameOver deterministic → **no change**.
- Plan 1 (presale): split → **collapse 90/10**; final-box → **soft overshoot**; credit overflow → **revert**; presale-box RNG → reuse committed index/day word + domain salt (freeze-safe in principle, re-verify at secure-phase).
- Ship as **ONE milestone / one batched diff** (entangled surface per §2; splitting re-audits the same files twice).

**RESOLVED — USER decisions (2026-05-24):**
- **D1 — DECIDED: ALL boxes uniform — every lootbox caller (incl. Degenerette + Decimator wins) rolls boons + passes, per-`betId` granularity.** ("make all the boxes the same, they can all roll boons and passes, it's fine.") No special-casing; plan 2's param removal stands. Low-risk: both win paths are PLAYER-CLAIM, off the advanceGame chain (Degenerette `resolveBets`; Decimator `claimDecimatorJackpot` `DecimatorModule:321`, freeze-blocked), and the boon draw uses the committed `rngWord` (freeze invariant intact). Boon gas is on the claimer's own tx.

- **D2 — Plan 1 economic numbers: RESOLVED (USER 2026-05-24).** DGNRS curve LOCKED (5×10-ETH tiers, rates 3.0/2.5/2.0/1.5/1.0 → drains at 50 ETH, 3× early/late). BURNIE mean LOCKED (400% branch), spread = mirror lootbox roll. **`Pool.PresaleBox` size = 10% of INITIAL_SUPPLY = the FULL former Earlybird allocation — presale boxes REPLACE the earlybird subsystem** (remove `_awardEarlybirdDgnrs` + 4 call sites + `_finalizeEarlybird` + curve state; rename the enum slot). Scope expansion captured in presale plan §3.

- **D4 — Undrained presale-pool backstop: RESOLVED (USER 2026-05-24) = none needed.** Sole close = exactly-50-ETH box; undrained pool burns at game-over (`burnAtGameOver`). Optional admin/level terminal not required. Close is also now a CLAMP to exactly 50 ETH (supersedes earlier soft-overshoot): the crossing box is sized down to land at 50, gets a normal roll + sweeps the remainder + latches `presaleOver`. **Lock-prevention: the MIN_BOX floor is checked on the REQUESTED amount (pre-clamp), so a sub-`MIN_BOX` gap (e.g. 1 wei short of 50) can't lock the close — any normal-sized request closes it.** See presale plan §3.3/§3.5/§7.
- **D5 — Credit accrual: RESOLVED (USER 2026-05-24) = ALL ETH buys EXCEPT Degenerette, during presale, `+= 0.25·eth`.** This is exactly the former `_awardEarlybirdDgnrs` sites (mint `MintModule:1210` + whale/lazy/deity `WhaleModule:263/476/587`) — a clean 1:1 swap. BURNIE buys + Degenerette excluded.

**OPEN — remaining: NONE.** All six v47 plans fully calibrated (pending v46.0 closure).
- **D3 — Plan 2 economic confirms: CONFIRMED as-is (USER 2026-05-24).** Winnings boxes mint passes (EV-budgeted) intended; 75%+no-activity dampener accepted. Closed.

**DEFERRED to phase-time (not now-lockable):** Phase A internal edit ordering (resolveRedemptionLootbox last-writer; claimable-invariant joint check); per-plan secure-phase adversarial passes.
