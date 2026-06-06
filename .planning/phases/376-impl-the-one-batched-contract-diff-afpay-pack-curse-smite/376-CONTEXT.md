# Phase 376: IMPL — The ONE Batched Contract Diff (AFPAY + PACK + CURSE + SMITE) - Context

**Gathered:** 2026-06-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Land the single reconciled `contracts/*.sol` diff — **17 requirements** (AFPAY-01..07 · PACK-01/02 · CURSE-01..07 · SMITE-01) — **producer-before-consumer** per `SPEC-V61-DESIGN-LOCK.md` §4, applied to `contracts/` and **`forge build` clean**, then **HELD at the contract-commit boundary** for explicit USER hand-review. This is THE contract-boundary HARD STOP for v61.0 (`autonomous:false` at the commit gate).

**In scope:** the ONE batched diff under the SPEC's settled knobs + edit order, with RNG-freeze intact + SOLVENCY-01 held. `ContractAddresses.sol` freely modifiable; `contracts/test/` consumers updated for build-cleanliness (test-side, free to commit).

**Out of bounds:** re-litigating any SPEC-locked design (D-01..D-05, the verification verdicts, the anchors, the edit order — all settled at 375); the proving tests + empirical SEC floor (378 TST); gas-neutrality measurement (377 GAS); the adversarial sweep / closure (379 TERMINAL). NO contract COMMIT without USER hand-review.

</domain>

<spec_lock>
## Requirements (locked via SPEC — milestone-level)

**17 requirements are locked.** The locked-requirements SPEC for this phase is **`.planning/SPEC-V61-DESIGN-LOCK.md`** (the Phase-375 design-lock deliverable) — NOT a phase-dir `*-SPEC.md`. It is the single source of truth and downstream agents MUST read it before planning or implementing. Requirements, signatures, anchors, and the edit order are **not duplicated here**.

What the SPEC locks (do NOT re-open):
- **D-01..D-05** — accessor-first PACK/AFPAY sequencing · `AfkingSpent` at every afking debit · `CURSE_COUNT_CAP = 20` · protocol-addr skip (VAULT/SDGNRS/GNRUS) · staleness basis `_currentMintDay()`.
- **Verification verdicts** — `purchaseWith` is DEAD → leave untouched (waterfall lands in the live `_purchaseForWith` / `_processMintPayment`); self-smite HARMLESS-by-design → no guard required.
- **All 29 re-attested anchors vs `2bee6d6f`** (SPEC §3) including the **4 CORRECTED** ones (see Specific Ideas — these supersede the `375-CONTEXT.md` `~:NNN`).
- **Signatures / shapes** — `_settleShortfall(buyer, shortfall, allowClaimable) → (claimableUsed, afkingUsed)`; `CURSE_COUNT_SHIFT = 215` + `MASK_8`; recombine `(uint256(afking) << 128) | claimable`; `prizeContribution = msg.value + claimableUsed + afkingUsed`; `freshEth = costWei − claimableUsedTicket`.
- **The full producer-before-consumer edit order** — Track A (PACK-01 accessor → PACK-02 repack → AFPAY-01 `_settleShortfall` → AFPAY-02..06 → AFPAY-07) and Track B (CURSE-01 → ... → CURSE-07 → SMITE-01); the two tracks touch different storage slots (balances mapping vs `mintPacked_`) → independent, but producer-before-consumer is strict WITHIN each.

</spec_lock>

<decisions>
## Implementation Decisions

### Curse entrypoint placement (discussed 2026-06-06)

The codebase shape that grounds this: `DegenerusGameMintStreakUtils` is an **abstract base** (`is DegenerusGameStorage`) inherited by BOTH the Game (`DegenerusGame is DegenerusGameMintStreakUtils`) AND the delegatecall modules (e.g. `GameAfkingModule is DegenerusGameMintStreakUtils`). `claimWinnings` is a **direct Game function** (`:1556`), not a stub.

- **PLACE-01 — `decurse` / `smite` = thin Game dispatch stubs into an EXISTING delegatecall module (USER, LOCKED).** NOT inline in `DegenerusGame.sol`; NOT a new dedicated module. This matches the SPEC's literal "new Game dispatch stubs" wording and keeps the Game lean against the code-size ceiling. The curse **mutators** (`+= 2` saturating / clear-to-0 / `>= CURSE_COUNT_CAP` skip), the **APPLY** (CURSE-02), and `curseCountOf` (CURSE-07) are internal/public helpers in the **`MintStreakUtils` base** (visible to the Game + every module, zero duplication); the **SET hook** `_maybeCurse` stays inline in the Game's direct `claimWinnings` (`:1556`) as a base-internal call.

- **PLACE-02 — exact host module = planner's call (USER deferred), by code-size headroom + cohesion.** Preference order: **(1) `GameAfkingModule`** — afking-immunity cohesion (active afker = immunity is an afking concept), already inherits `MintStreakUtils`, already has the `claimAfkingBurnie` / `subscribe` / `mintBurnie` / `drainAffiliateBase` Game-stub precedent to mirror (`DegenerusGame.sol:413` neighborhood); **(2) `DegenerusGameMintModule`** — cure-adjacency (owns `_purchaseForWith`, the CURSE-04 cure host) + already calls `burnCoin`. Avoid a new module (overkill for ~2 small fns + a new address + interface + delegatecall hop).

- **PLACE-03 — code-size guardrail (intrinsic to PLACE-01).** `forge build` MUST confirm the Game contract stays under the **24,576-byte EIP-170 ceiling** after the new stubs land (v55 needed a code-size reclaim → this is a real risk, the whole reason the stub-vs-inline choice mattered). If the stubs push the Game over the ceiling, that is a BLOCKER to raise at the hand-review — do not silently work around it.

### Execution posture (defaulted to established precedent — user did not select these areas)

- **Done-definition at the hard stop = SC5 literal:** the diff applied + `forge build` clean + HELD at the contract-commit boundary. The proving tests + non-regression + the empirical SEC floor are **378 TST** (TST-01..06 + SEC-01/02); gas-neutrality is **377 GAS**. (The executor may sanity-spot-check obvious behavioral breaks, but the formal gate at 376 is build-cleanliness, not a green suite.)
- **Hand-review packaging = ONE batched diff for ONE approval** (`[[feedback_batch_contract_approval]]` / `[[feedback_no_implicit_approval]]`). A per-track / per-REQ-ID annotated walkthrough alongside the diff is welcome but not required.
- **Plan granularity = planner's call** — one monolithic plan vs Track A / Track B sub-plans; either way it is still ONE diff, ONE approval. **Sequential-on-main, no worktrees for contract-touching plans** (`[[worktrees-reenabled-contracts-gate]]`). Checkpoint per unit so a 5h cap-stop never lands mid-edit (`[[pace-runs-to-survive-5h-cap]]`).

### Claude's Discretion / planner-resolve items (resolve by reading code at plan time)

- The exact host module for `decurse`/`smite` (per PLACE-02 preference order).
- **Accessor-layer physical home** (PACK-01): `_claimableOf` / `_afkingOf` + `_creditClaimable` / `_debitClaimable` / `_creditAfking` / `_debitAfking` — natural home is the shared base/storage so the Game + all modules reach them; verify against the existing `claimablePool` accessor convention + the `PLAN-PLAYERQUESTSTATE-1SLOT-PACKING.md` precedent.
- How `_maybeCurse` SET hooks into the direct Game `claimWinnings` (an inline internal call to a `MintStreakUtils`-base helper after a successful `_claimWinningsInternal`).
- `_recordLootboxMintDay` relocation (CURSE-05): `DegenerusGameWhaleModule` private (def `:1000`) → `MintStreakUtils` base, so the plain standalone lootbox leg + the pass flows share one copy.
- `contracts/test/SettleClaimableShortfallTester.sol` (`:39`) → update to the new `_settleShortfall` signature (required for `forge build` clean; test-side, free to commit). Sweep for any other `contracts/test/` consumer that breaks the build under the new signatures / the repacked balances mapping.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Source of truth — READ FIRST
- `.planning/SPEC-V61-DESIGN-LOCK.md` — **the locked-requirements SPEC.** §1 knobs D-01..D-05 + verification verdicts · §2 the 4 CORRECTED anchors · §3 the full 29-anchor re-attested table (grounded on `2bee6d6f`) + the SOLVENCY accessor-invariant home · §4 the producer-before-consumer edit-order map (Track A / Track B + the CURE-vs-PACK-repack cross-check). Every `file:line` at IMPL comes from §3, NOT from the `~:NNN` in `375-CONTEXT.md`.
- `.planning/phases/375-spec-design-lock-open-knobs-anchor-re-attestation-vs-2bee6d6/375-CONTEXT.md` — the design-lock discussion context (D-01..D-05 rationale). ⚠ Its `<canonical_refs>` contract anchors are PRE-attestation `~:NNN` — superseded by SPEC §2/§3 (see Specific Ideas).
- `.planning/ROADMAP.md` (v61.0 §) — Phase 376 goal + Success Criteria 1–5 + the contract-boundary HARD STOP posture.
- `.planning/REQUIREMENTS.md` — the 17 contract REQ-IDs (AFPAY-01..07 · PACK-01/02 · CURSE-01..07 · SMITE-01) + Out-of-scope.

### Design-lock inputs (the SPEC folded these; read for sketch detail)
- `.planning/PLAN-V61-AFKING-AS-PAYMENT-SOURCE.md` — AFPAY waterfall (§2 funding table, §4 edit map) + PACK sub-concept (§6 accessor + uint128-half math). §7 sequencing resolved by D-01; §8 open checks resolved by the SPEC verdicts + D-02.
- `.planning/PLAN-CASHOUT-CURSE.md` — CURSE counter / APPLY / SET / CURE / `decurse` (§1–5); cap (D-03) + day-basis (D-05).
- `.planning/PLAN-V61-DEITY-SMITE.md` — SMITE design (§1 confirmed knobs, §3 sketch); protocol-skip (D-04) + self-smite (verified harmless).
- `.planning/PLAN-UNIVERSAL-CLAIMABLE-PAY.md` — shipped ancestor (whale/presale already pull claimable; AFPAY adds the 3rd tier).
- `.planning/PLAN-PLAYERQUESTSTATE-1SLOT-PACKING.md` — the accessor-layer precedent for PACK-01.

### Contract anchors (full paths; lines = SPEC §3 re-attested on `2bee6d6f`)
- `contracts/storage/DegenerusGameStorage.sol` — `_settleClaimableShortfall` (def `:851`, paired `claimablePool -=` `:857`) → generalize to `_settleShortfall`; `claimablePool` `uint128` decl **`:365`** (SOLVENCY comment `:358`); `AfkingSpent` decl (AFPAY-07/D-02); `PRICE_COIN_UNIT` `:162`.
- `contracts/DegenerusGame.sol` — `_processMintPayment` def `:1054` (sole call site `:474`); `_resolvePlayer` `:573`; `claimWinnings` `:1556` (CURSE-03 SET host); public `playerActivityScore` `:2701`; post-gameOver claim-merge `:1575-1595` (single `claimablePool -=` `:1589`); new `decurse`/`smite` dispatch stubs (mirror `claimAfkingBurnie:413`).
- `contracts/modules/DegenerusGameMintModule.sol` — cure host **`_purchaseForWith` def `:1093`** (body to `:1419`); lootbox shortfall call `:1143` (`:1135-1146`); presale box `:1489`; affiliate split `:1655/1665/1675/1684` + `coinCost` `:1600/1695` + bonus `:1697`; plain lootbox leg `:1135-1254`; `purchaseWith` def `:858` = DEAD (leave untouched).
- `contracts/modules/DegenerusGameWhaleModule.sol` — `_settleClaimableShortfall` `:263` / `:490` / `:596` (AFPAY-04, all 3 replaced by the generalized helper); `_recordLootboxMintDay` def **`:1000`** (call site `:858`) → relocate to MintStreakUtils base (CURSE-05).
- `contracts/modules/DegenerusGameDegeneretteModule.sol` — `_collectBetFunds` def `:573` (call `:468`; preserve `InvalidBet()` reverts `:498-500/:562-566`) — AFPAY-05.
- `contracts/modules/DegenerusGameMintStreakUtils.sol` — `_playerActivityScore` def `:241` (2-arg wrapper `:327`); CURSE APPLY `scoreBps = bonusBps` **`:320`** (zero-new-SLOAD: `packed` loaded `:248`); `_bountyEligible` `:30`; `CURSE_COUNT_CAP` (add) — base home for the curse helpers + the placement decision.
- `contracts/modules/DegenerusGamePayoutUtils.sol` — the 2 centralized claimable credits `:25/:39/:63` (PACK-01 routes through `_creditClaimable`).
- `contracts/modules/GameAfkingModule.sol` — afking auto-buy own spend `_deliverAfkingBuy` def `:777`, debit `:~791-792` (OUT of scope — no double-draw; `_processMintPayment` ref count here = 0). Candidate host for `decurse`/`smite` (PLACE-02).
- `contracts/libraries/BitPackingLib.sol` — `AFFILIATE_BONUS_POINTS_SHIFT = 209` (ends 214), `LEVEL_UNITS_SHIFT = 228`; `[215-222]` free gap → add `CURSE_COUNT_SHIFT = 215` + `MASK_8 = 0xFF` (CURSE-01).
- `contracts/DegenerusDeityPass.sol` — `ownerOf(uint256)` `:335` (soulbound, `tokenId = symbolId` 0-31) — smite gate.
- `contracts/BurnieCoin.sol` — `burnCoin` `:572` (`onlyGame` `:497`) — `decurse` 100 / `smite` 200 BURNIE sinks (`PRICE_COIN_UNIT/10`, `/5`).
- `contracts/StakedDegenerusStonk.sol` — redemption-snapshot activity-score read **`:932`** (`claim.activityScore = uint16(game.playerActivityScore(beneficiary)) + 1`) — the reason D-04 keeps the protocol-addr skip.
- `contracts/test/SettleClaimableShortfallTester.sol` — `_settleClaimableShortfall(...)` `:39` → update to the new `_settleShortfall` signature.

### Baseline
- Frozen subject = `2bee6d6f` (v60.0 closure HEAD; confirmed ancestor of working-tree HEAD). 10 commits ahead of origin/main, NOT pushed.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`MintStreakUtils` abstract base** (`is DegenerusGameStorage`, inherited by Game + all modules) — home for the curse mutators / APPLY / cap / `curseCountOf` internal+public helpers (PLACE-01). No duplication across modules.
- **`_settleClaimableShortfall`** (`DegenerusGameStorage.sol:851`) → generalize to `_settleShortfall(buyer, shortfall, allowClaimable) → (claimableUsed, afkingUsed)`; covers lootbox + presale + the 3 whale sites at once (AFPAY-01).
- **Game dispatch-stub pattern** (`DegenerusGame.sol:413` `claimAfkingBurnie` and the `:286-433` stub cluster) — the exact `delegatecall(abi.encodeWithSelector(IModule.fn.selector, ...))` shape to mirror for `decurse`/`smite` (PLACE-01).
- **`_recordLootboxMintDay`** (`DegenerusGameWhaleModule.sol:1000`, private) — relocate to `MintStreakUtils` base so the plain lootbox leg + pass flows share one copy (CURSE-05).
- **`PLAN-PLAYERQUESTSTATE-1SLOT-PACKING.md` accessor pattern** — the precedent for the PACK accessor layer (D-01).

### Established Patterns
- `uint128`-cast / `unchecked` `claimablePool` math (e.g. `depositAfkingFunding`'s `claimablePool += uint128(msg.value)`) — PACK-02 does half-math in `uint128` and recombines via `(uint256(afking) << 128) | claimable` (NO naive full-word `+=` — 0.8's 256-bit check misses a 127→128 carry).
- `mintPacked_` field-isolated bit-field RMW — all 12 writers (Boon/Bingo/Whale/MintStreakUtils/Mint/Lootbox/Afking + Storage/Game) are field-isolated → bits 215-222 are clobber-free for the CURSE counter.
- Cheapest-first bail ordering in hot paths (the `_maybeCurse` SET sketch); constant-compare protocol-addr skips (D-04, no SLOAD).

### Integration Points
- Claimable/afking balances mapping → PACK accessor + repack (Track A, one storage slot).
- `mintPacked_` bits 215-222 → CURSE counter (Track B, a DIFFERENT slot → independent of Track A; the CURSE-04 cure and the PACK repack both fire in `_purchaseForWith` but touch different slots → no write-after-write conflict, per SPEC §4 cross-check).
- `_playerActivityScore:320` → CURSE APPLY chokepoint (propagates to every consumer + the public view + frozen snapshots).
- `claimWinnings:1556` → SET; `_purchaseForWith:1093` → CURE + AFPAY waterfall host; `decurse`/`smite` → new Game stubs → existing module (PLACE-01/02).

</code_context>

<specifics>
## Specific Ideas

- **The 4 CORRECTED anchors (SPEC §2) OVERRIDE the `375-CONTEXT.md` `~:NNN`.** IMPL MUST use the baseline-true lines, NOT the pre-attestation shorthands:
  1. `claimablePool` `uint128` **decl = `:365`** (the `~:838-839` cited in 375-CONTEXT is the `_setCurrentPrizePool` width doc-comment, not the decl).
  2. cure + AFPAY host = **`_purchaseForWith` `:1093`** — there is NO `_purchaseWithFor` symbol at the baseline (name transposition; `:1285` is inside the body). Naming `_purchaseWithFor` would reference a non-existent symbol.
  3. `_recordLootboxMintDay` def = **`:1000`** (375-CONTEXT cited `~:983`, drift +17).
  4. sDGNRS redemption activity-score read = **`:932`** (375-CONTEXT cited `~:942`, drift −10).
- **Placement rationale (PLACE-01):** stub-into-module beats inline-in-Game because the Game's 24,576-byte ceiling is the binding constraint (v55 reclaim history); it beats a new module because `decurse`+`smite` are ~2 small fns and a new module adds an address + interface + delegatecall hop for no cohesion win.
- **Producer-before-consumer is load-bearing** — within Track A the PACK accessor precedes the repack precedes the AFPAY waterfall; within Track B the whole CURSE chain (esp. CURSE-01 layout + CURSE-02 APPLY) precedes SMITE-01 (shared counter + cap + APPLY). Authoring out of order risks naming a not-yet-existing helper.
- **Hard floor on every edit:** RNG-freeze intact — NO `rngWord` read added (AFPAY ledger-only; CURSE/SMITE touch only the activity-score path: view-only read + a score-LOWERING write on a successful access-controlled claim). SOLVENCY-01 — `claimablePool == Σ(claimable + afking)` centralized in the PACK accessor; every afking debit pairs a `claimablePool -=` (pool-neutral, contract balance unchanged). Proven empirically at SEC-01/02 (378).
- **AFPAY-06 byte-identity obligation:** the affiliate-split refactor MUST stay byte-for-byte behavior-identical on the existing no-afking DirectEth/Claimable/Combined cases (re-verify at IMPL; proven at TST-01, 378).
- **Comment discipline on the diff:** comments explain HOW the code works — no plan IDs, REQ tags, spec-line cites, or change-history (`[[lean-code-comments-no-procedural-meta]]` / `[[feedback_no_history_in_comments]]`). Contracts are frozen at deploy → no future-proofing redundancy (`[[feedback_frozen_contracts_no_future_proofing]]`).

</specifics>

<deferred>
## Deferred Ideas

None new — discussion stayed within the 376 IMPL scope. The non-discussed execution areas (done-definition, hand-review packaging, plan granularity) defaulted to established precedent (captured under Execution posture), not deferred. Downstream phases own their parts: 377 GAS (gas-neutrality measurement) · 378 TST (TST-01..06 + SEC-01/02) · 379 TERMINAL (delta-audit + 3-skill sweep + `audit/FINDINGS-v61.0.md` + closure flip).

</deferred>

---

*Phase: 376-impl-the-one-batched-contract-diff-afpay-pack-curse-smite*
*Context gathered: 2026-06-06*
