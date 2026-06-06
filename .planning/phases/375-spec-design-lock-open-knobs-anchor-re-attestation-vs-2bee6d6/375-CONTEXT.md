# Phase 375: SPEC — Design-Lock (open knobs) + Anchor Re-Attestation vs `2bee6d6f` + Edit-Order Map - Context

**Gathered:** 2026-06-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Paper-only design-lock SPEC phase — **ZERO `contracts/*.sol` edits**. It produces the SPEC design-lock document that lets Phase 376 IMPL author the ONE batched contract diff with zero "by construction" assumptions. Three deliverables (SPEC-01):

1. **Lock the open knobs** in writing (the 4 decisions below + the discretion/verification items).
2. **Re-attest every cited `file:line` anchor** against the frozen baseline `2bee6d6f` (the plan docs were grep-verified vs the 2026-06-06 HEAD; correct any drift).
3. **Map the producer-before-consumer edit order** for the single 376 diff.

Out of bounds: any `contracts/*.sol` change (that is 376); re-litigating the LOCKED scope (the 3 work items + the packing sub-concept are all in scope per `PLAN-V61-MILESTONE-SCOPE.md`).

</domain>

<decisions>
## Implementation Decisions

### AFPAY / PACK sequencing
- **D-01 — Accessor-first (USER, overrides the docs' "feature-first" lean).** The single 376 diff lands the **PACK accessor layer** (`_claimableOf/_afkingOf` reads + `_creditClaimable/_debitClaimable/_creditAfking/_debitAfking`, each paired with the `claimablePool` update) **and the slot repack** (`[afking:high128 | claimable:low128]`) **first**, then writes the AFPAY waterfall against those accessors **once**. This supersedes the "feature-first" wording in `PLAN-V61-MILESTONE-SCOPE.md` §2 and `REQUIREMENTS.md` PACK-02 — both explicitly deferred the exact *feature-first vs accessor-first* choice to SPEC-01, so this is the intended lock, not a conflict. **Rationale:** the `claimablePool == Σ(claimableWinnings + afkingFunding)` solvency invariant is centralized in the accessor layer *before* the new spend path exists, and the waterfall is authored once with no raw-mapping churn. **Edit order: PACK-01 → PACK-02 → AFPAY-01…07.**

### AFPAY transparency
- **D-02 — `AfkingSpent` at every afking debit (USER).** Emit `AfkingSpent(address indexed player, uint256 amount)` at **each** afking draw — `_processMintPayment` (ticket mint) **and** the shared `_settleShortfall` helper (whale / presale / lootbox). Not the narrower `_processMintPayment`-only option. **Rationale:** it is the new transparency event for the milestone's headline feature; full observability of where afking gets spent. The extra LOG on a shortfall-funded buy is off the `advanceGame` hot path → marginal gas. **Deliberate departure** from how claimable spends stay silent outside `_processMintPayment` — call this out in the SPEC so it reads as intentional.

### CURSE economics
- **D-03 — `CURSE_COUNT_CAP = 20` points (USER, = plan recommendation).** The `uint8` curse counter saturates at 20 pts (10 stacks / 10 ghost-cashouts; −2000 bps max penalty). Doubles as the mandatory uint8-wrap guard (`+= 2` must never wrap 254→0). Clean headroom above the 5-stack (10-pt) smite ceiling.

### SMITE / curse targeting
- **D-04 — Keep the protocol-addr skip (USER, = plan recommendation).** Both `smite()` and the cashout-curse SET skip `VAULT` / `SDGNRS` / `GNRUS` (constant compares, no SLOAD). **Rationale:** protects the sDGNRS redemption-snapshot activity-score read (`StakedDegenerusStonk.sol:942`) from corruption; keeps the two curse sources consistent; prevents a deity wasting 200 BURNIE on a non-player address.

### Claude's Discretion
- **D-05 — Staleness day-basis = `_currentMintDay()`.** The `_maybeCurse` staleness compare (`lastEthDay + 5 > _currentMintDay()`) uses `_currentMintDay()` — the basis already in the `PLAN-CASHOUT-CURSE.md` §3 sketch and the ticket cure-stamp — not `_simulatedDayIndex()`. The ≤1-day skew between the two is immaterial against a 5-day window (`PLAN-CASHOUT-CURSE.md` §Accepted edges). Low-stakes builder call; user did not object.

### SPEC-execution items (no decision — the SPEC's own work; listed so the planner sequences them)
- **Anchor re-attestation vs `2bee6d6f`.** Re-grep every cited `file:line` against the frozen baseline (confirmed an ancestor of HEAD — re-attest via git). **Path note for the planner:** the plan docs use shorthand module names; full paths live under `contracts/modules/` and `contracts/storage/` (e.g. "MintModule" → `contracts/modules/DegenerusGameMintModule.sol`, "DegenerusGameStorage" → `contracts/storage/DegenerusGameStorage.sol`). Cite full paths in the SPEC.
- **`purchaseWith` dead-confirm.** Verify `DegenerusGameMintModule.sol` `purchaseWith` is dead (only def + `IDegenerusGameModules` interface + stale comments; no call site / selector) → leave untouched. If live, wire the afking interaction.
- **Self-smite sanity.** Confirm paying to curse yourself has no score-floor / bounty exploit via the shared counter (harmless by design).
- **Edit-order map (producer-before-consumer) — two independent tracks:**
  - **Track A (balances mapping):** PACK-01 accessor layer → PACK-02 repack → AFPAY-01 `_settleShortfall` → AFPAY-02…06 spend paths → AFPAY-07 event.
  - **Track B (`mintPacked_` curse counter — different storage slot from the balances mapping, so independent of Track A):** CURSE-01 `BitPackingLib` shift → CURSE-02 APPLY → CURSE-03 SET → CURSE-04 CURE → CURSE-05 lootbox bounty stamp → CURSE-06 `decurse` → CURSE-07 view → SMITE-01 (shares the counter / cap / APPLY).
  - **Cross-check:** CURSE-04 cure fires in `_purchaseWithFor` (a buy path AFPAY also touches) but mutates `mintPacked_` curse bits, **not** the balances mapping → no write-after-write conflict with the PACK repack.
- **SOLVENCY accessor-invariant location.** The `claimablePool == Σ(claimable + afking)` identity lives in the PACK accessor layer (ONE place) — re-attested empirically at SEC-02 (378).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Design-lock inputs (the source of truth — read all)
- `.planning/PLAN-V61-MILESTONE-SCOPE.md` — milestone scope manifest; the 3 work items + packing; §2 per-plan open items (note: §2 "feature-first" lean is superseded by D-01).
- `.planning/PLAN-V61-AFKING-AS-PAYMENT-SOURCE.md` — AFPAY waterfall (§2 funding table, §3 scope, §4 6-edit map) + PACK sub-concept (§6); §7 sequencing (resolved by D-01) + §8 open checks (`purchaseWith`, affiliate split, AfkingSpent breadth — resolved by D-02).
- `.planning/PLAN-CASHOUT-CURSE.md` — CURSE counter / APPLY / SET / CURE / `decurse` (§1–5); §Open decision = cap (D-03); §Accepted edges = day-basis (D-05); §Constants.
- `.planning/PLAN-V61-DEITY-SMITE.md` — SMITE design (§1 confirmed decisions, §3 sketch); §4 open: protocol skip (D-04) + self-smite (verify).
- `.planning/PLAN-UNIVERSAL-CLAIMABLE-PAY.md` — shipped ancestor (whale/presale already pull claimable; AFPAY adds the 3rd tier).
- `.planning/REQUIREMENTS.md` — the 27 v61.0 reqs; SPEC-01 enumerates the knobs; AFPAY-01..07 / PACK-01/02 / CURSE-01..07 / SMITE-01 / SEC-01/02 / TST-01..06 / AUDIT-01; Out-of-scope list.
- `.planning/ROADMAP.md` (v61.0 section) — phase 375–379 details + the contract-boundary HARD STOP at 376.

### Contract anchors (re-attest vs `2bee6d6f` at SPEC — full paths)
- `contracts/storage/DegenerusGameStorage.sol` — `_settleShortfall` generalization target (~:851), `AfkingSpent` decl, `claimablePool` `uint128` (~:838-839), `PRICE_COIN_UNIT` (~:162).
- `contracts/DegenerusGame.sol` — `_processMintPayment` (~:1054), `_resolvePlayer` (~:573), `claimWinnings` (~:1556), public `playerActivityScore` (~:2701), post-gameOver claim-merge (~:1575-1585), `decurse`/`smite` new entries.
- `contracts/modules/DegenerusGameMintModule.sol` — lootbox shortfall (~:1126-1146), presale box (~:1489), ticket affiliate split (~:1620-1692), cure site `_purchaseWithFor` (~:1285), plain lootbox leg (~:1170-1254), `purchaseWith` dead-confirm (~:858).
- `contracts/modules/DegenerusGameWhaleModule.sol` — whale bundle / lazy pass / deity pass shortfalls (~:263/490/596), `_recordLootboxMintDay` (~:983, relocate → MintStreakUtils base).
- `contracts/modules/DegenerusGameDegeneretteModule.sol` — `_collectBetFunds` (~:579-588).
- `contracts/modules/DegenerusGameMintStreakUtils.sol` — `_playerActivityScore` (~:241), CURSE APPLY site (~:320), `packed` already loaded (~:248 → zero-new-SLOAD), `_bountyEligible` (~:30-63), `CURSE_COUNT_CAP`.
- `contracts/modules/DegenerusGamePayoutUtils.sol` — the 2 centralized claimable credits.
- `contracts/modules/GameAfkingModule.sol` — afking auto-buy own spend (~:791-799, OUT of scope — no double-draw).
- `contracts/libraries/BitPackingLib.sol` — add `CURSE_COUNT_SHIFT = 215` in the `[215-222]` free gap (`AFFILIATE_BONUS_POINTS` ends 214, `LEVEL_UNITS_SHIFT = 228`) + `MASK_8`; grep no full-slot `mintPacked_` writer clobbers 215-222.
- `contracts/DegenerusDeityPass.sol` — `ownerOf(deityId)` smite gate (soulbound, `tokenId = symbolId` 0-31).
- `contracts/BurnieCoin.sol` — `burnCoin` (~:572, `onlyGame`) — `decurse` 100 / `smite` 200 BURNIE sinks (`PRICE_COIN_UNIT/10`, `/5`).
- `contracts/StakedDegenerusStonk.sol` — redemption snapshot reads the activity score (~:942) → the reason D-04 keeps the protocol-addr skip.
- `contracts/test/SettleClaimableShortfallTester.sol` — update to the new `_settleShortfall` signature (test-side, free).

### Baseline
- Frozen subject = `2bee6d6f` (v60.0 closure HEAD; `git merge-base --is-ancestor` confirmed ancestor of HEAD). 10 commits ahead of origin/main, NOT pushed.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `_settleClaimableShortfall` (`DegenerusGameStorage.sol`) → generalize to `_settleShortfall(buyer, shortfall, allowClaimable) → (claimableUsed, afkingUsed)`; covers lootbox + presale + 3 whale sites at once.
- `PLAN-PLAYERQUESTSTATE-1SLOT-PACKING.md` accessor pattern — the precedent for the PACK accessor layer (D-01 lands this first).
- `_recordLootboxMintDay` (`DegenerusGameWhaleModule.sol:983`, private) — relocate to the shared `MintStreakUtils` base so the plain lootbox leg + pass flows share one copy (CURSE-05).

### Established Patterns
- `uint128`-cast / `unchecked` claimablePool math (e.g. `depositAfkingFunding`'s `claimablePool += uint128(msg.value)`) — PACK-02 does half-math in `uint128` and recombines via `(uint256(afking) << 128) | claimable` (NO naive full-word `+=`).
- Cheapest-first bail ordering in hot paths (the `_maybeCurse` SET sketch); constant-compare protocol-addr skips (D-04); `mintPacked_` bit-field RMW with no write-after-write clobber.

### Integration Points
- Claimable/afking balances mapping → PACK accessor + repack (Track A).
- `mintPacked_` bits 215-222 → CURSE counter (Track B).
- `_playerActivityScore` (`:320`) → CURSE APPLY chokepoint (propagates to every consumer + public view + frozen snapshots).
- `_purchaseWithFor` (`:1285`) → CURE; `claimWinnings` → SET; `smite`/`decurse` → new Game entries.

</code_context>

<specifics>
## Specific Ideas

- **The accessor-first choice (D-01) is the headline divergence.** Downstream MUST treat any "feature-first" phrasing in `PLAN-V61-MILESTONE-SCOPE.md` / `REQUIREMENTS.md` PACK-02 as superseded — the requirement text itself deferred the exact choice to SPEC-01, so the SPEC document should restate the order as PACK accessor + repack → AFPAY waterfall and (optionally) note the wording reconciliation.
- Hard floor carried into every IMPL edit: RNG-freeze intact (all 3 items read no `rngWord`) + SOLVENCY-01 (`claimablePool == Σ`) — proven at SEC-01/02 (378), centralized in the PACK accessor (D-01 makes this cleaner).

</specifics>

<deferred>
## Deferred Ideas

None new — discussion stayed within the SPEC phase scope. (Already tracked as future milestones in `REQUIREMENTS.md` "Future Requirements": the v52 consolidated cross-model audit + the v62 blind-spot audit `.planning/AUDIT-V62-PLAN.md`.)

</deferred>

---

*Phase: 375-spec-design-lock-open-knobs-anchor-re-attestation-vs-2bee6d6*
*Context gathered: 2026-06-06*
