# Phase 353: SPEC — Design-Lock + Unmanipulable/Solvency Re-Attestation + XMODEL Design-Input + Call-Graph Attestation - Context

**Gathered:** 2026-06-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 353 is the **v56.0 SPEC design-lock** — **paper-only, ZERO `contracts/*.sol` mutation.** It settles the v56.0 mechanism in writing so the IMPL phase (354) authors a fully reconciled diff with no "by construction" assumptions, and designs the load-bearing non-exploitability + non-perturbation BEFORE any code is written.

Phase 353 OWNS three requirements — **AFF-01, AFF-02, XMODEL-01** — but its success criteria also fold in the **design feeds** for the requirements built/proven later (AGG/TKT/QST/OPEN at IMPL 354; GAS at 355; SEC at 356). This discussion captured the genuinely-open product/risk/process decisions; the rest of the v56 mechanism is already locked in the design-lock input doc + ROADMAP + REQUIREMENTS and is carried forward unchanged.

**Scope (USER-locked):** the AFKING SYSTEM — BOTH ENDS (the BUYING per-day STAGE/accrual/settle AND the OPENING box-pass/materialize). Maximally gas-efficient while COMPLETELY unmanipulable (esp. via strategic sub/unsub). NOT behavior-identical — slight semantic simplifications acceptable if cheaper + unmanipulable. Pre-launch redeploy-fresh (storage-layout break fine, no migration).

</domain>

<decisions>
## Implementation Decisions

### Quest Double-Credit (O1 / QST-05) — ADJUDICATED: genuine bug, fix
- **D-01:** O1 is a **genuine, isolated double-credit** — confirmed by full call-graph trace. A single LOOTBOX-quest completion's reward is `creditFlip`'d **twice**: internally at `DegenerusQuests.sol:890` AND lumped into the return `totalReturned = ethMintReward + lootboxReward` (`:893`) which the caller re-credits (`DegenerusGameMintModule.sol:1232` `lootboxFlipCredit += questReward` → `:1367` `creditFlip`). The eth-mint leg (return-only) and burnie-mint leg (internal-only) each credit exactly once; only the lootbox leg goes through both channels. BURNIE-only → OFF the ETH/`claimablePool` solvency path, but an unintended 2× emission.
- **D-02:** **NOT** the "two different quests both pay" case (completing the daily MINT_ETH quest AND a LOOTBOX quest from one buy, each paying its own reward) — that is by-design and correct. O1 is the *same single reward* paid twice.
- **D-03 (FIX MECHANIC, USER-chosen):** **Drop the internal `creditFlip` at `DegenerusQuests.sol:890`**; keep `lootboxReward` in the return so the caller's single batched `creditFlip` (`MintModule:1367`) pays it exactly once. Gas-optimal — removes one extra `creditFlip` CALL, aligns with the v56 gas theme. SPEC locks the fix + the non-perturbation proof for both callers.
- **D-04 (audit result — the pattern is ISOLATED):** Checked all 7 quest handlers + every caller. NONE repeat the bug: `handleMint` guards `if (paidWithEth) return reward` (BURNIE internal-only, ETH return-only); `handleFlip` has no internal credit (caller credits once via `_questApplyReward`); `handleDecimator` credits internally and the return is used as a **decimator burn-weight boost** (`BurnieCoin:613`, intended dual-use, NOT a re-credit); `handleAffiliate` no internal credit (routed once); `handleDegenerette` credits internally and the caller **ignores** the return (`DegeneretteModule:467`). Only `handlePurchase`'s lootbox leg is the bug.

### Dead Code (bonus find) — REMOVE
- **D-05:** `handleLootBox` (`DegenerusQuests.sol:698-742`) has **no production caller** — superseded by `handlePurchase` (which combines handleMint + handleLootBox). Only the interface entry (`IDegenerusQuests.sol:107`) + access-control tests reference it; its internal `creditFlip` (`:739`) is unreachable. **Remove it** in the v56 diff (function + interface entry + the access-control tests). Pre-launch redeploy-fresh makes the interface break fine. Removes bytecode + a latent double-credit footgun while we're already in the shared core.

### Affiliate Batching & Leaderboard (AFF-02) — leaderboard KEPT, option A
- **D-06:** The affiliate leaderboard is **NOT deletable** — it pays out real DGNRS at every level transition: (a) **1% of the DGNRS Affiliate pool → the top affiliate** for the frozen level (`_rewardTopAffiliate` → `affiliate.affiliateTop`, `DegenerusGameAdvanceModule.sol:700`); (b) **5% snapshotted → a score-proportional per-affiliate claim** `allocation × affiliateScore / totalAffiliateScore`, min-score-gated, one claim/level (`claimAffiliateDgnrs`, `DegenerusGameBingoModule.sol:217`). USER confirmed: "I need it for the affiliate claim so we can't get rid of it."
- **D-07 (USER-chosen):** The afking affiliate slice **DOES feed the leaderboard**, via **option A** — at settle, ONE batched leaderboard write lumped into the **settle-level**; accept the minor cross-level ranking lag for the afking slice; **NO force-flush** before the level-transition snapshot. (v56's aggregator already collapses the current per-buy ×2 `payAffiliate` leaderboard writes into this one-per-window write regardless.)
- **D-08 (gas note, USER insight, confirmed):** `_updateTopAffiliate` (`DegenerusAffiliate.sol:776-783`) is **read-once-compare** — one SLOAD of `affiliateTopByLevel[lvl]` + a conditional SSTORE only when the new total beats the top. So the settle-time leaderboard cost is cheap (`affiliateCoinEarned` warm SSTORE + `_totalAffiliateScore` warm SSTORE + the read-once-compare); keeping the leaderboard does NOT fight the gas goal.
- **D-09 (carried forward, locked):** AFF-01 — scheduled ~10-day flush KEEPS the winner-takes-all daily-seeded roll (seeded by the fixed window-boundary day, NOT player-chosen); the deterministic **75/20/5 split** is used ONLY on the player-triggered-alteration path → settle-timing can never select a favorable roll seed. The roll is EV-neutral + intra-upline-chain-only-redistributive + **buyer-never-wins** (`winner != sender`, `DegenerusAffiliate.sol:558`/`:579`). AFF-02 taper applied **per-buy at accrue** (immutable; clustering can't dodge it; `_applyLootboxTaper` `:787`, taper-only-reduces).

### Ticket-Mode Primitive (TKT-02) — DROP century parity
- **D-10 (USER-chosen):** When the new ticket-mode minimal-write primitive replaces the per-day `purchaseWith` heavyweight, **DROP the afking-ticket century/x00 quantity-bonus parity** (the `targetLevel % 100 == 0` bonus at `DegenerusGameMintModule.sol:1243`) for simplicity — an intentional semantic simplification under the v56 scope latitude. Afking-ticket buyers won't get the century bonus; manual buyers keep it. SPEC records the intentional non-parity.

### XMODEL-01 Cross-Model Design-Input Pass — focused bespoke prompts
- **D-11 (USER-chosen):** Run the cross-model design-input pass with **focused per-concern bespoke prompts** fed to BOTH `codex` + `gemini` (both CLIs confirmed installed at `/home/zak/.local/bin/`). Concerns: the strategic sub/unsub edge, settle-timing/roll-seed non-exploitability, the ticket-mode primitive parity, the open-end unmanipulability, and long-run gas suggestions. Fold each model's findings into the design-lock via a **disposition table** BEFORE IMPL. **Do NOT reuse the v52 `coordinator.sh` harness** — it's shaped for the v52 cumulative audit, not a v56 design-input pass. (XMODEL-01's TERMINAL close-augmentation half is owned by Phase 357 / AUDIT-01.)

### Claude's Discretion (deferred to researcher/planner — technical, not product calls)
- The **per-sub accumulator storage layout** (GAS-02 design feed): pack into the `Sub` slot's spare bits (the 4-field stamp uses 176/256) vs a new cold slot; exact field widths for the affiliate base + `windowStartDay` + quest progress + `lastSettledDay`. Lean = spare-bits (PLAN doc); pre-launch redeploy-fresh makes this low-stakes. Researcher confirms feasibility against `DegenerusGameStorage.sol`.
- The precise **±10-streak / confirmed-vs-provisional derivation**: the immutable debit-gated delivered-day markers, the `lastCompletedDay`/`afkCoveredThroughDay` double-credit guard, the active-pass anti-reset. Locked in shape (carried forward); the exact marker mechanism is a planning detail.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.** Baseline = v55.0 closure HEAD **`453f8073`** (`MILESTONE_V55_AT_HEAD_ca3bbd3220de763298ef2e742111f6e6ef90d583`). Every cited `file:line` MUST be grep-re-attested against `453f8073` at SPEC (no "by construction" survives un-checked). NOTE: the ROADMAP cites several anchors with bare module names (e.g. `MintModule:1243`, `GameAfkingModule.sol:760-831`) — the actual paths are under `contracts/modules/` (verified below); reconcile the bare names during attestation.

### Planning inputs (READ FIRST)
- `.planning/PLAN-V56-AFKING-BATCHING-GAS.md` — the design-lock input (mode-agnostic ~10-day aggregator, the 6 "Open SPEC decisions", the unexploitability rationale).
- `.planning/REQUIREMENTS.md` — the 24 v56.0 REQ-IDs; Phase 353 owns AFF-01/AFF-02/XMODEL-01.
- `.planning/ROADMAP.md` — Phase 353 Goal + Success Criteria (SC1-5) + the Coverage / center-of-gravity rationale.

### Quest core (the O1 fix + the dead-code removal + the shared-core non-perturbation)
- `contracts/DegenerusQuests.sol` — `handlePurchase` (`:763-898`); **O1 bug** at `:884` (comment), `:887` (burnie credit, keep), `:890` (lootbox credit — **DROP this**), `:893` (`totalReturned`, keep lootbox in it). `handleLootBox` (`:698-742`, **DEAD — remove**). Audited-clean handlers: `handleMint` (`:417-519`, guard `:513`), `handleFlip` (`:533`), `handleDecimator` (`:589-643`, internal credit `:629`), `handleAffiliate` (`:644`), `handleDegenerette` (`:913-956`, internal credit `:954`). `awardQuestStreakBonus` (`:365`) + the manual/bingo/degenerette/boon callers = the non-perturbation surface (QST-04).
- `contracts/interfaces/IDegenerusQuests.sol:107` — the `handleLootBox` interface entry to remove (D-05).

### Quest-handler callers (the double-credit verification)
- `contracts/modules/DegenerusGameMintModule.sol` — the O1 re-credit: `:1222-1232` (`handlePurchase` call + `lootboxFlipCredit += questReward`), `:1366-1367` (the batched `creditFlip`). Also `:1243` the century/x00 bonus (**dropped for afking**, D-10), `:1730` the `handleMint` caller (audited clean).
- `contracts/modules/GameAfkingModule.sol:760` — the **afking** `handlePurchase` caller. ⚠ RESEARCH ITEM: under the v56 aggregator the afking per-buy quest handling moves to the deferred settle, so confirm whether `handlePurchase` is still called per-buy on the afking path or replaced — the O1 fix must cover both callers OR the afking path stops calling it per-buy.
- `contracts/BurnieCoin.sol:613` (`handleDecimator` caller, clean — weight boost), `contracts/BurnieCoinflip.sol:275` (`handleFlip` caller, clean), `contracts/modules/DegenerusGameDegeneretteModule.sol:467` (`handleDegenerette` caller, clean — return ignored).

### Affiliate (the accrue/settle split + the leaderboard kept under option A)
- `contracts/DegenerusAffiliate.sol` — `payAffiliate` (`:455-588`): the leaderboard writes `:510` (`affiliateCoinEarned`), `:511` (`_totalAffiliateScore`), `:521` (`_updateTopAffiliate`); the taper `:504`/`:787`; the daily-seeded roll `:558`; buyer-never-wins `:579`. Views: `affiliateTop` (`:602`), `affiliateScore` (`:614`), `totalAffiliateScore` (`:625`), `_updateTopAffiliate` (`:776-783`, read-once-compare, D-08).
- **Leaderboard consumers (why it can't be deleted, D-06):** `contracts/modules/DegenerusGameAdvanceModule.sol:700` (`_rewardTopAffiliate`, 1% top-affiliate DGNRS prize); `contracts/modules/DegenerusGameBingoModule.sol:217-245` (`claimAffiliateDgnrs`, 5% proportional DGNRS claim).

### Aggregator / STAGE / storage / open-end (design feeds for IMPL)
- `contracts/storage/DegenerusGameStorage.sol` — the `Sub` 4-field stamp `(scorePlus1, amount, lastAutoBoughtDay)` + `lastOpenedDay`; the per-sub accumulator target (GAS-02).
- `contracts/modules/GameAfkingModule.sol` — the STAGE + accrual + the open path (`_openAfkingBox`→`resolveAfkingBox`); the lootbox stamp branch + the ticket-mode `purchaseWith` route (the ~262k binding case to replace with the minimal-write primitive).
- `contracts/modules/DegenerusGameAdvanceModule.sol` — the STAGE placement / the `mintBurnie` "settlement-due" cadence wiring + `SUB_STAGE_BATCH`.

### XMODEL-01 tooling
- `codex` + `gemini` CLIs at `/home/zak/.local/bin/` (both confirmed installed) — **bespoke focused prompts** (D-11).
- `.planning/audit-v52/bin/coordinator.sh` + `.planning/PLAN-V52-ULTIMATE-AUDIT.md` — the existing cross-model harness; reference only, **NOT reused** for the v56 design-input pass.

### Memory seeds
- `[[v56-batch-afking-affiliate-quest-seed]]` — the milestone seed (batch afking affiliate + quest; the streak-BURNIE-payout history).
- `[[o1-quest-lootbox-double-credit-advisory]]` — the O1 advisory (now ADJUDICATED a genuine bug → fix, D-01/D-03).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- The lootbox **box-stamp** primitive (`GameAfkingModule`) is the template the new ticket-mode minimal-write primitive must mirror (cheap write + cheap accrual, NOTHING cross-contract).
- The `lastAutoBoughtDay` / `lastOpenedDay` idempotency-marker shape is the template for the `windowStartDay` / `lastSettledDay` double-settle markers (AGG-05).
- The caller's existing **batched `creditFlip`** (`MintModule:1367`, accumulating quest + affiliate + presale credit into one call) is the channel the O1 fix routes the lootbox reward through (D-03).

### Established Patterns
- Quest handlers follow a "return value is for crediting ONLY when not internally credited" contract — `handleMint` honors it (guard `:513`), `handlePurchase` violates it for the lootbox leg (the bug). The fix restores the invariant.
- Affiliate credit is BURNIE flip-credit OFF the ETH/`claimablePool` path (the 349.2 invariant) → SOLVENCY-01 stays untouched; v56 is a BURNIE-emission-timing + gas change only.
- Affiliate scores route to `level + 1` during gameplay and freeze at index `lvl` on the L→L+1 transition (`_rewardTopAffiliate` comment) — the reason option-A's deferred settle introduces a cross-level lag (accepted, D-07).

### Integration Points
- The new `DegenerusQuests` batched-settle entrypoint must be proven non-perturbing to the manual / bingo / degenerette / boon callers (QST-04) — the same shared core the O1 fix + dead-code removal touch.
- The aggregator settle leg consumes AFF-01 (the distribution rule) and writes the leaderboard once per window (option A) — connects `GameAfkingModule` settle → `DegenerusAffiliate` leaderboard → the DGNRS-claim consumers.

</code_context>

<specifics>
## Specific Ideas

- USER framing on O1: "if it is paying the lootbox quest completion in quest module AND also adding it to the aggregated payout in the mint module then we need to fix that" — exactly the traced shape; fix confirmed.
- USER on the leaderboard: "what do we even use affiliate leaderboard for? can we just delete it?" → answered (1% top + 5% proportional DGNRS claim) → "ok I need it for the affiliate claim so we can't get rid of it. we can read the top once and compare to that so not much gas" → KEEP + option A + the read-once-compare gas note.
- USER posture throughout: minimize everyday writes/gas wherever it stays unmanipulable; favor simplification (drop century parity; drop dead code) over behavior-identity.

</specifics>

<deferred>
## Deferred Ideas

- **Whether the afking path still calls `handlePurchase` per-buy** under the v56 aggregator (vs deferring all quest work to the settle) — a research item that determines whether the O1 fix needs to cover the `GameAfkingModule:760` caller or whether that call disappears. Flagged for the researcher, not a separate phase.
- The accumulator field-width packing + the exact ±10-streak marker derivation — Claude's-discretion technical details (above), resolved by the researcher/planner, not new scope.
- No scope creep surfaced — discussion stayed within the v56.0 design-lock boundary.

</deferred>

---

*Phase: 353-spec-design-lock-unmanipulable-solvency-re-attestation-xmode*
*Context gathered: 2026-06-01*
