# Requirements: Milestone v64.0 — Recent-Changes Re-Audit + Level-Semantics Correctness Sweep

**Defined:** 2026-06-15
**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

**Milestone goal:** Run the established cross-model-led dual-net audit over the **full post-v62 contract delta** (`77580320..HEAD`, 41 files / +4902/−3697 / 33 commits — gas rounds, storage packing, the reward overhaul, the BURNIE emission rework, the permissionless decimator/redemption entrypoints, the payable-chain CEI fixes, and the 5 genuinely-new post-v63 commits) PLUS a dedicated **whole-codebase `lvl` vs `lvl+1` correctness examination**, then ship `audit/FINDINGS-v64.0.md` + closure. Much of `77580320..a8b702a7` was swept in v63 — its dispositions carry as PRIORS (BURNIE-04 fixed, BURNIE-05 by-design, the 4 refuted HIGHs not re-litigated) — but the surface is re-swept comprehensively per USER (broadest scope chosen over post-v63-diff-only).

**Baseline:** v62.0 closure subject `77580320` (last formally audited frozen point).
**Subject:** HEAD `78eb3dd2` — to byte-freeze at FOUNDATION (Phase 397).
**Method:** **Council + Claude dual-net per slice** — the Gemini+Codex cross-model council (`gemini`/`codex` CLIs) NET-1 + an independent Claude-led adversarial NET-2 in every sweep phase; Claude builds the foundation, orchestrates, adjudicates against the frozen subject, runs the skeptic gate, and synthesizes. A no-finding verdict for any slice requires BOTH nets on record.
**Posture:** AUDIT-ONLY — no NEW contract change planned; a council/Workflow-surfaced, adjudicated, skeptic-passed finding routes to a gated fix (USER hand-review, batched, never pre-approved); otherwise document-only.
**Level-semantics emphasis (USER's explicit ask):** the `lvl` vs `lvl+1` examination is a dedicated phase (398), not folded into the slices — every `level` / `level+1` / `_activeTicketLevel` / `streakBaseLevel` / `afkingDrain.level()+1` / jackpot-phase site is enumerated and verified against intended phase semantics. Census: 119 `+1` arithmetic sites / 165 level-mentions over the contracts tree.

---

## v64.0 Requirements

### FND — Foundation (subject freeze + green baseline + delta surface)
- [ ] **FND-01**: The audit subject is byte-frozen at HEAD `78eb3dd2`; the baseline diff vs `77580320` is recorded as the `77580320..HEAD` audit-delta surface (per-file/per-family characterization routed to the sweep phases); `git diff` against the frozen SHA stays empty through the sweeps.
- [ ] **FND-02**: The authoritative storage layout is re-derived via `forge inspect storageLayout` at the subject; all slot-hardcoded harnesses are reconciled against the post-packing slots (Game 6-slot merge, StakedStonk, BurnieCoinflip, Admin), runtime-correct (not compile-only-green).
- [ ] **FND-03**: A GREEN forge regression baseline is established and recorded at the subject (0 deterministic failures); the JS suite's known pre-existing reds are characterized by name so new reds are distinguishable.
- [ ] **FND-04**: The v63 dispositions are intaken as explicit PRIORS (BURNIE-04 fixed `98c4f049`, BURNIE-05 by-design, the 4 refuted HIGHs, R-389-01 LOW) so the sweeps do not re-litigate settled rulings; the genuinely-new post-v63 delta (`a8b702a7..HEAD`) is flagged as priority surface.
- [ ] **FND-05**: The verifier oracle is confirmed to exercise its target code on every changed surface (no oracle hole); finding-candidates from any read-only surface pass are routed to their sweep phases.

### LVL — Level-semantics correctness sweep (whole-codebase; USER's explicit ask)
- [ ] **LVL-01**: A COMPLETE census of every `level` / `level+1` / `lvl` / `lvl+1` / `currentLevel(+1)` / `cachedLevel(+1)` site across all contracts is produced (not a sample) — each site classified by role (purchase target · jackpot resolve · leaderboard key · streak basis · EV-cap key · price lookup · boundary guard).
- [ ] **LVL-02**: Every direct/afking/whale ticket-purchase path's target level is verified to match phase semantics — purchase phase → `level+1`, jackpot phase → `level` — and `_activeTicketLevel()` and its open-coded `jackpotPhaseFlag ? level : level+1` equivalents are confirmed consistent at every call site.
- [ ] **LVL-03**: The mint-streak / `streakBaseLevel` level basis is verified consistent between the recording path (`_recordMintStreakForLevel`) and every activity-score reader (`_playerActivityScore*`, afking secondary), with no off-by-one between mint level and the streak-advance level.
- [ ] **LVL-04**: The affiliate leaderboard level basis is verified — `payAffiliate(lvl)` vs `claim()`'s `afkingDrain.level()+1` — and the long-noted affiliate-score level asymmetry is dispositioned (correct-by-design or finding).
- [ ] **LVL-05**: The jackpot / decimator / lootbox resolution level keys are verified to agree across the resolver open level, the EV-cap key, the price lookup, and the far-future distance math (e.g. `currentLevel + 1` == resolver open level == EV-cap key).
- [ ] **LVL-06**: Boundary correctness is verified at level 0 (no vacuous `< level` comparison letting a passless/streak case through), century `x00` levels, and the gameover/terminal level — no underflow, overflow, or off-by-one at the edges.
- [ ] **LVL-07**: Every level-basis divergence surfaced is dispositioned with both nets on record (correct-by-design with the reason, or a routed finding); the sweep result is recorded as a level-semantics map.

### RWD — Reward-mechanics audit (lootbox overhaul · spins · recycle · emission · quest-streak)
- [ ] **RWD-01**: The lootbox EV-multiplier change (floor 90% / ceiling 145% / ceiling-score 40,000) and reward-component split (40/15/15/15/10/5) are verified EV-consistent with the documented design (`.planning/PAPER-REWARD-CHANGES-BRIEF.md`); only the stated EV changes (multiplier lift + recycle relaxation) actually change EV.
- [ ] **RWD-02**: The three Degenerette-spin lootbox outcomes (WWXRP spin, BURNIE spins ×3 with survival flip, ETH spin with 3-tier split + recirc) are verified EV-neutral per category, one-shot, and freeze-safe (the spin seeds are not player-knowable at commitment).
- [ ] **RWD-03**: The ticket-roll budget preservation (per-hit budget ×11/9) and far-future distribution change (20% far / 1.5× budget weighting) are verified value-conserving (no aggregate ticket-ETH leak or inflation).
- [ ] **RWD-04**: The mint recycle-bonus relaxation (≥3-whole-ticket claimable threshold, drain-detection removed) is verified to not open a positive-EV money-pump (flip-credit illiquidity + sub-unity direct-box EV + claimable-won-first + the 10-ETH/(player,level) cap).
- [ ] **RWD-05**: The BURNIE zero-start emission rework (coinflip-seeded stake replacing the 2M+2M lumps, day-20 rebuy latch, survival flip) is verified emission-conserving and survive-before-mint; no unbacked BURNIE is emitted.
- [ ] **RWD-06**: The quest-streak unification (halved/uncapped quest streak, afking-secondary parity, unified activity score) is verified to not create an afking↔manual same-day double-channel and to respect the activity-score hard cap.

### SOLV — Solvency · carry · redemption audit
- [ ] **SOLV-01**: The `claimablePool == Σ claimable + Σ afking` identity holds across every changed credit/debit path (incl. the salvage-swap legs, the dust-forfeit self-credit, and the payable-chain redemption).
- [ ] **SOLV-02**: The BURNIE-04 carry-escrow fix (`98c4f049`: submit-time carry escrow, flip-contingent D+1 payout, `CoinflipClaimState` event) is re-verified — carry value is no longer stranded from redemption backing, and the fix introduces no over-credit or double-count.
- [ ] **SOLV-03**: The salvage carry-symmetric BURNIE sourcing + vault-owner buyer fallback (`a8fa3afa`) is verified value-conserving and solvency-safe (ETH from vault claimable+afking, stage reserves via `depositAfkingFunding`; the toggle + ETH floor bound the vault leg).
- [ ] **SOLV-04**: The permissionless / live-game redemption + dust-drop forfeit + the payable-delegatecall-chain ETH leg (`403afc62`, `4547b387`, `78b858ed`) are verified — every live claim is funded, the stETH-before-ETH CEI ordering holds (the V62-03/yield-surplus class), and no path strands or double-credits across the gameover drain snapshot.
- [ ] **SOLV-05**: The coinflip claim-window changes (first-claim 30→180 days, calibrated keeper bounty) are verified to not strand seed value or open a keeper faucet against real prevailing gas.

### PACK — Storage-packing & gas-refactor behavior-identity
- [ ] **PACK-01**: Every narrowed packed field's width is ≥ its real-world maximum (no silent truncating cast); each narrowing is enumerated with the bound that makes it safe (Game 6-slot merge, StakedStonk solvency scalars + poolBalances, BurnieCoinflip, Admin vote-record).
- [ ] **PACK-02**: Masked read-modify-write helpers preserve every co-resident field; cross-module readers/writers of a delegatecall-shared packed slot use identical shift/mask conventions (slot agreement by construction).
- [ ] **PACK-03**: The raw `delegatecall(msg.data)` dispatch and the gas-round hot-path refactors resolve the same selector / ABI-decode identically and change no externally-observable behavior (output / revert / event).
- [ ] **PACK-04**: External ABI getters are preserved for every privatized/packed field (no interface break for off-chain consumers, including the indexer).

### PERM — Permissionless-composition & keeper / indexer-event surface
- [ ] **PERM-01**: The permissionless decimator + redemption batch-claim entrypoints (`4547b387`, `a6b3e2fd`) are access-correct (no privilege escalation), composition-safe (no cross-call reentrancy / ordering break), and the decimator offset-key isolation (`d8778c3e`) prevents a lagged-gameover live-round overwrite.
- [ ] **PERM-02**: The keeper box-bounties (decimator + redemption batch) are net-negative-or-neutral against real prevailing gas (5–50+ gwei) + flip-credit illiquidity — not a farmable faucet.
- [ ] **PERM-03**: The redemption pre-draw RNG gate (`d8778c3e`) and the mid-day RNG threshold gate hold the freeze invariant against a grindable zero-word read.
- [ ] **PERM-04**: The 3 new indexer-parity events (`AffiliateEarningsRecorded` reused in `claim`, `MintStreakRecorded`, `AfkingDelivered`) emit at the correct site with correct args, fire once per logical event, and are emission-only (no state/behavior change) — confirming the contract↔indexer reconstruction contract.

### RNG — Freeze spine re-attest (changed RNG-window state)
- [ ] **RNG-01**: Every new/changed RNG consumer in the delta is traced backward to confirm the VRF word was unknown when the player committed their input (the spin seeds, the decimator claim-seed, the redemption lootbox seed).
- [ ] **RNG-02**: All SLOADs consumed inside the rng-window across the changed surface are enumerated; no player-controllable non-VRF state can shift between VRF request and fulfillment to bias an output.
- [ ] **RNG-03**: The box-spin / decimator / redemption resolvers are one-shot and replay-safe (record-clear-before-resolution + the delegatecall `address(this) != GAME` guard); no double-resolve.

### MUT — Mutation (folded; resume the v63 CI-resumable tail)
- [ ] **MUT-01**: The v63 CI-resumable mutation campaign is resumed over the changed spine targets; surviving mutants are triaged FALSE (oracle gap) vs GENUINE (test gap), and every GENUINE survivor is killed by a regression test (no contract defect expected).

### TERM — Terminal (synthesis + findings + closure)
- [ ] **TERM-01**: All sweep findings are consolidated into a deduped ledger; each is adjudicated against the frozen subject, skeptic-gated, and assigned a severity + disposition (fixed-route / by-design / refuted / test-hardening).
- [ ] **TERM-02**: `audit/FINDINGS-v64.0.md` (chmod 444) + the HTML report are authored as the canonical deliverables; both nets are on record for every no-finding verdict.
- [ ] **TERM-03**: The milestone is closed at the frozen subject with the closure signal `MILESTONE_V64_AT_HEAD_<sha>`; every v64.0 requirement is re-attested; any routed fix is recorded as a gated post-audit USER-hand-review item (not applied in-milestone).

## v2 Requirements

(none — this is a bounded audit milestone; any deferred deep-dive is recorded as a routed finding at TERMINAL.)

## Out of Scope

| Item | Reason |
|------|--------|
| New contract features / mechanics | Audit-only milestone; the contract is frozen at the subject. |
| Re-litigating v63 settled dispositions | BURNIE-04 (fixed), BURNIE-05 (by-design), the 4 refuted HIGHs carry as priors — re-examined only where the new delta interacts with them. |
| Pre-v62 surface (≤ `77580320`) | Already covered by v62 and earlier audit milestones; v64's baseline is the v62 close. |
| Off-chain indexer implementation | v64 verifies the on-chain emit contract (PERM-04); the indexer's own reconstruction code is a separate consumer. |
| Applying any surfaced fix in-milestone | Posture is audit-only; a confirmed finding routes to a gated USER-hand-review fix after the milestone. |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| FND-01 | 397 | Pending |
| FND-02 | 397 | Pending |
| FND-03 | 397 | Pending |
| FND-04 | 397 | Pending |
| FND-05 | 397 | Pending |
| LVL-01 | 398 | Pending |
| LVL-02 | 398 | Pending |
| LVL-03 | 398 | Pending |
| LVL-04 | 398 | Pending |
| LVL-05 | 398 | Pending |
| LVL-06 | 398 | Pending |
| LVL-07 | 398 | Pending |
| RWD-01 | 399 | Pending |
| RWD-02 | 399 | Pending |
| RWD-03 | 399 | Pending |
| RWD-04 | 399 | Pending |
| RWD-05 | 399 | Pending |
| RWD-06 | 399 | Pending |
| SOLV-01 | 400 | Pending |
| SOLV-02 | 400 | Pending |
| SOLV-03 | 400 | Pending |
| SOLV-04 | 400 | Pending |
| SOLV-05 | 400 | Pending |
| PACK-01 | 401 | Pending |
| PACK-02 | 401 | Pending |
| PACK-03 | 401 | Pending |
| PACK-04 | 401 | Pending |
| PERM-01 | 402 | Pending |
| PERM-02 | 402 | Pending |
| PERM-03 | 402 | Pending |
| PERM-04 | 402 | Pending |
| RNG-01 | 403 | Pending |
| RNG-02 | 403 | Pending |
| RNG-03 | 403 | Pending |
| MUT-01 | 404 | Pending |
| TERM-01 | 405 | Pending |
| TERM-02 | 405 | Pending |
| TERM-03 | 405 | Pending |

**Coverage:**
- v64.0 requirements: 38 total
- Mapped to phases: 38
- Unmapped: 0 ✓

---
*Requirements defined: 2026-06-15*
*Last updated: 2026-06-15 after initial definition (v64.0 milestone init)*
