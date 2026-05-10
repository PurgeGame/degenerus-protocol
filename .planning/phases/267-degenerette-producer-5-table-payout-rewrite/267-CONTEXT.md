# Phase 267: Degenerette Producer + 5-Table Payout Rewrite - Context

**Gathered:** 2026-05-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Replace the broken `_evNormalizationRatio` runtime corrector in `contracts/modules/DegenerusGameDegeneretteModule.sol` with **5 per-N (gold-quadrant-count) precomputed payout/hero/WWXRP tables**, indexed by `_countGoldQuadrants(playerTicket) ∈ {0..4}`. Add a new `packedTraitsDegenerette(uint256) → uint32` producer to `contracts/DegenerusTraitUtils.sol` using per-quadrant near-uniform color distribution `[16,16,16,16,16,16,16,8]/120` (commons 13.33%, gold 6.67%) and uniform 1/8 symbol. Existing `weightedColorBucket` / `traitFromWord` / `packedTraitsFromSeed` bodies stay byte-identical (Mint + Jackpot + v34.0 gold-solo paths UNTOUCHED). Rewrite `_distributePayout` ETH-currency branch with a **3-tier split rule** (PAY-SPLIT-01..03): payouts ≤ 3× bet pay 100% ETH; 3-10× bet payouts pay 2.5× bet ETH floor + remainder lootbox; >10× bet payouts retain the existing 25% ETH / 75% lootbox split; pool-cap takes precedence on top of all three tiers.

**Audit baseline:** v36.0 audit-subject HEAD `1c0f09132d7439af9881c56fe197f81757f8164a` (closure signal `MILESTONE_V36_AT_HEAD_1c0f09132d7439af9881c56fe197f81757f8164a` carried into v37.0 baseline).

**Phase 267 boundary state at close:**

- 1 batched USER-APPROVED contract commit landing both `contracts/DegenerusTraitUtils.sol` (new `packedTraitsDegenerette` + `_degTrait` helper, additive only — `internal pure` library helpers, inlined into the consumer) and `contracts/modules/DegenerusGameDegeneretteModule.sol` (5-table dispatch rewrite + 25 packed constants + symbol-only hero + producer-callsite swap + 4 stale comment surfaces rewritten + `_evNormalizationRatio` deletion + `_distributePayout` ETH-branch 3-tier split rewrite + `betAmount` threading from L656).
- Net constant count: 11 → 24 (+5 payout packed +5 jackpot M=8 +5 hero packed +5 WWXRP packed −4 single-table −2 normalizer); two threshold/floor multipliers added inline to `_distributePayout` (3× and 2.5× — kept as inline literals per `feedback_no_dead_guards.md`-adjacent simplicity preference; planner may promote to named constants if NatSpec readability demands).
- Zero new storage slots; zero new public/external mutation entry points; zero new external pure entry points (`packedTraitsDegenerette` is `internal pure` per D-267-VISIBILITY-01, inlined into consumer — does NOT widen the public ABI); zero new admin functions; zero new modifiers.
- Working file `267-01-CONSTANTS-VERIFY.md` (AGENT-COMMITTED) capturing reproducible re-derivation evidence: `derive_5_tables.py` stdout grep-matched byte-for-byte against the .sol pasted hex.
- Phase 267 plan also chore-fixes upstream doc wording + new requirement adds to match locked signatures + new payout-split rule: REQUIREMENTS.md DGN-03 (signature) + DGN-01 (visibility) + new PAY-SPLIT-01..03 section + STAT-07 (Phase 268 mapping) + AUDIT-02 surface (h) (Phase 271 mapping) + Coverage line 47→51 + Traceability rows; ROADMAP.md Phase 267 inline goal + success criterion 6 + Phase 268 STAT-07 + Phase 271 AUDIT-02 surface (h); Phase 271 AUDIT-04 attestation language (drop ALLOWED-NEW-STATELESS-ENTRY — no longer applicable since `packedTraitsDegenerette` is `internal pure`, not a new external entry). All upstream-doc edits land in the same plan task 1 chore commit (single agent-commit per `feedback_batch_contract_approval.md`-adjacent batched-doc-edit discipline).
- 18 requirements (DGN-01..DGN-15 + PAY-SPLIT-01..03) flipped to PASS at phase close; PROGRESS table flipped 0/0 → 1/1 (single multi-task plan).
- Tests + audit deliverable + closure flips OUT of scope → Phase 268 (stat + cross-surface) + Phase 269 (lootbox cleanup) + Phase 270 (post-v32 sub-audit) + Phase 271 (audit + closure).

</domain>

<decisions>
## Implementation Decisions

### Carry-forward (locked from prior milestones — not re-asked)

- **D-267-FILES-01 (single canonical audit deliverable, Phase 271):** Mirror v33 D-257-FILES-01 / v34 D-262-FILES-01 / v35 D-265-FILES-01 / v36 D-266-FILES-01. NOT a Phase 267 concern (audit deliverable lives in Phase 271).
- **D-267-CLOSURE-01 (signal SHA = HEAD at audit-pass-close commit):** Mirror v36 D-266-CLOSURE-01. Closure signal `MILESTONE_V37_AT_HEAD_<sha>` emitted at Phase 271 §9c. NOT a Phase 267 concern.
- **D-267-CLOSURE-02 (commit-readiness register §9.NN — three subsections):** Mirror v36 D-266-CLOSURE-02. §9.NN.i USER-APPROVED contracts + §9.NN.ii USER-APPROVED tests + §9.NN.iii AGENT-COMMITTED audit + planning artifacts. NO §9.NN.iv awaiting-approval subsection. NOT a Phase 267 concern.
- **D-267-FCITE-01 (forward-cite zero-emission, terminal phase):** Mirror v36 D-266-FCITE-01. NOT a Phase 267 concern (Phase 271 is terminal).
- **D-267-SEV-01 (D-08 5-bucket severity rubric):** Inherited from v25-onward D-08 chain. NOT a Phase 267 concern.
- **D-267-APPROVAL-01 (audit/.planning writes agent-author):** Mirror v36 D-266-APPROVAL-01. NOT a Phase 267 concern.
- **D-267-APPROVAL-02 (contract + test commits USER-APPROVED batched):** Per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md`. Phase 267 has 1 batched contract commit (TraitUtils + DegeneretteModule combined); agent presents diff and waits for explicit user "approved" before committing.

### Carry-forward (locked from `.planning/notes/2026-05-10-degenerette-payout-recalibration.md`)

- **D-267-SCOPE-01 (Degenerette only):** New `packedTraitsDegenerette` helper added to TraitUtils. Existing `weightedColorBucket` / `traitFromWord` / `packedTraitsFromSeed` byte-identical. Mint + Jackpot + v34 gold-solo mechanic UNTOUCHED.
- **D-267-DIST-01 (color widths `[16,16,16,16,16,16,16,8]/120`):** 7 commons at 13.333%, gold at 6.667%. Producer: base-15 scaling `scaled = uint32((uint64(uint32(rnd)) * 15) >> 32)` (max bias ~2.3e-10), then `scaled == 14 ? 7 : scaled >> 1`. Symbol uniform 1/8 from high 32 bits of each 64-bit lane.
- **D-267-NORM-01 (NO runtime normalizer):** `_evNormalizationRatio` (L808-851) DELETED with its single call site (L965-969). EV-equality enforced by 5-table calibration, not by runtime correction.
- **D-267-EV-TARGET-01 (basePayoutEV = 100 centi-x per N, exact):** Each of 5 payout tables satisfies `Σ P_N(M) × payout(M) = exactly 100 centi-x`. Drift 0.00 bps per N (verified in `derive_5_tables.py`).
- **D-267-EV-PRECISION-01 (M=4/M=5/M=6 cascade absorbs residual; M=8 monotonic in N):** M=4 coarse (~1 bps per centi-x), M=5 fine (~0.05 bps), M=6 ultra-fine (~0.005 bps). Final per-N drift ±0.0003 bps. M=8 jackpots stay at uniform-scale values: 107,564 / 125,830 / 147,929 / 175,123 / 209,164 — strictly monotonic in N.
- **D-267-HERO-01 (symbol-only hero match):** Hero boost fires on `symbolMatch` only; `colorMatch` ignored. P(hero match) = 1/8 uniform per quadrant. HERO_PENALTY (9500) and HERO_SCALE (10000) UNCHANGED.
- **D-267-HERO-02 (per-N hero boost tables):** 5 separate `HERO_BOOST_N{0..4}_PACKED` tables (M=2..7 packed into 96 bits each, 16 bits per multiplier).
- **D-267-WWXRP-SPLIT-01 (10/30/30/30 across buckets 5/6/7/8, per-N factors):** Existing split preserved. 5 separate `WWXRP_FACTORS_N{0..4}_PACKED` tables (4 × 64-bit factors per uint256). Total ETH bonus EV = exactly 5.000% per N.
- **D-267-PRODUCER-API-01 (no breaking changes to existing TraitUtils functions):** `weightedColorBucket(uint32) → uint8`, `traitFromWord(uint64) → uint8`, `packedTraitsFromSeed(uint256) → uint32` all byte-identical. New `packedTraitsDegenerette(uint256) → uint32` added alongside. Phase 268 SURF-01 verifies byte-identity.
- **D-267-CONSTPASTE-01 (25 packed constants paste-ready from script):** All 25 constant byte-values paste-ready in `.planning/notes/2026-05-10-degenerette-payout-recalibration.md` §"Concrete file changes", regenerable from `.planning/notes/degenerette-recalibration/derive_5_tables.py` (Python `Fraction`-exact, no FP drift).

### Locked this discussion

- **D-267-COUNTGOLD-01 (`_countGoldQuadrants` signature):** `function _countGoldQuadrants(uint32 ticket) private pure returns (uint8 count)` — operates directly on the packed `uint32` ticket via `uint8((ticket >> (q*8 + 3)) & 7) == 7` across `q ∈ {0,1,2,3}`. Matches ROADMAP success criterion 2 + planning note implementation. Avoids unpack-then-repack overhead at the `_fullTicketPayout` call site (which already has `playerTicket` as uint32). REQUIREMENTS.md DGN-03 wording (`(uint8[4]) internal pure`) is the outlier; Phase 267 plan includes a chore task to correct DGN-03 to `(uint32 ticket) private pure returns (uint8)` matching this lock.

- **D-267-VISIBILITY-01 (`packedTraitsDegenerette` visibility = `internal pure`):** Mirrors `packedTraitsFromSeed` (also `internal pure` in `contracts/DegenerusTraitUtils.sol:169`). On a `library` declaration, `internal pure` functions are inlined into the consumer — zero DELEGATECALL overhead, zero new function selector in the public ABI. Phase 267 plan includes chore tasks to correct upstream doc wording: REQUIREMENTS.md DGN-01 (`external pure` → `internal pure`), ROADMAP success criterion 1 + 5 wording, and Phase 271 AUDIT-04 attestation language (DROP "ALLOWED-NEW-STATELESS-ENTRY" entirely — the new helper is no longer a NEW external entry; AUDIT-04 attests zero new external mutation entry points + zero new external pure entry points). The new helper additive-only-on-the-library posture is preserved (Phase 268 SURF-01 byte-identity for existing functions).

- **D-267-PAYSPLIT-01 (3-tier ETH split rule, `payout ≤ 3 × bet` inclusive → 100% ETH):** ETH-currency Degenerette quickPlay payouts at or below 3× the per-ticket bet skip the lootbox conversion path entirely; full payout credited as claimable ETH via `_addClaimableEth(player, payout)`. Threshold inclusive at exactly `payout == 3 * betAmount` (matches user wording "<= 3x"). Implementation: early-return branch at top of `_distributePayout` `CURRENCY_ETH` block. Boundary discontinuity at exactly 3.0× bet (3.0× pays 100% ETH = 3.0× bet ETH; 3.01× pays 2.5× bet ETH per PAY-SPLIT-02 floor) accepted as documented design — the 3.0× → 2.5× ETH drop at 3.01× is much smaller than the alternative 3.0× → 0.7525× drop under naive 25% split.

- **D-267-PAYSPLIT-02 (3-10× band 2.5× ETH floor; >10× existing 25% split):** For payouts above the 3× threshold, ETH share computed as `ethShare = max(2.5 * betAmount, payout / 4)`, capped at `payout`. Lootbox share is `payout - ethShare`. The `max()` resolves cleanly into two bands: (a) `3 * bet < payout ≤ 10 * bet` → ethShare = 2.5 × bet (flat floor), lootbox = payout - 2.5 × bet; (b) `payout > 10 * bet` → ethShare = payout / 4 (existing 25% split), lootbox = 3 × payout / 4. The two bands meet exactly at `payout = 10 * bet` where 0.25 × payout = 2.5 × bet. Single-line Solidity expression: `uint256 ethShare = (2 * betAmount + (betAmount >> 1)); if (payout / 4 > ethShare) { ethShare = payout / 4; }` (or equivalent). Planner picks exact form; integer-division semantics + max-with-cap should be expressed with no overflow (uint256 headroom is ample for `2.5 * bet` since betAmount ≤ MIN_BET_ETH × extreme_count and bet always fits in uint128).

- **D-267-PAYSPLIT-03 (pool-cap precedence on top of split rule):** Existing `ETH_WIN_CAP_BPS = 1_000` (10% of futurePool) cap remains in force AFTER the split rule above. Compute `ethShare` and `lootboxShare` per D-267-PAYSPLIT-01..02; then if `ethShare > pool * ETH_WIN_CAP_BPS / 10_000`, flip excess: `lootboxShare += ethShare - maxEth; ethShare = maxEth; emit PayoutCapped(player, ethShare, lootboxShare);`. Pool cap takes precedence over the all-ETH small-payout passthrough AND the 2.5× floor — i.e., a thin pool can convert a sub-3× bet payout into a partial-ETH-partial-lootbox split if the all-ETH amount would exceed 10% of pool. Documented in `_distributePayout` NatSpec as "pool cap takes precedence over small-payout passthrough and 2.5× floor". Frozen-pool branch (L695-711) keeps its existing solvency-check posture (full ethShare debited from pending future pool with revert-on-insufficient).

- **D-267-PAYSPLIT-04 (scope = ETH-currency Degenerette quickPlay only):** PAY-SPLIT-01..03 apply ONLY to `_distributePayout`'s `CURRENCY_ETH` branch (L690+). `CURRENCY_BURNIE` branch (L735-736: `coin.mintForGame(player, payout)`) UNCHANGED — BURNIE pays directly, no lootbox conversion exists. `CURRENCY_WWXRP` branch (L737-739: `wwxrp.mintPrize(player, payout)`) UNCHANGED. JackpotModule ETH-distribution injection sites (v34.0 SURF-02 surface) UNCHANGED — Phase 268 SURF-02 byte-identity claim preserved. Mint module + lootbox module + entropy lib UNCHANGED.

- **D-267-PAYSPLIT-05 (`betAmount` threading via `_distributePayout` 5th argument):** Current `_distributePayout` signature `(player, currency, payout, rngWord)` extended to `(player, currency, betAmount, payout, rngWord)`. The new `betAmount` is the per-ticket bet (uint128). At the L656 call site within the spin loop, `amountPerTicket` is already in scope (verified via grep at `_awardDegeneretteDgnrs(player, amountPerTicket, matches)` at L661). Argument-ordering insertion of `betAmount` between `currency` and `payout` keeps related parameters adjacent (currency-bet-payout group) and minimizes cognitive load. Planner picks exact arg ordering; ordering decision documented inline in NatSpec.

- **D-267-PLAN-01 (single multi-task plan):** Mirror v33 P257 / v34 P262 / v35 P265 / v36 P266 single-multi-task-atomic-commit-per-task precedent. `267-01-PLAN.md` ordering (planner refines exact decomposition):
  1. **Chore:** upstream doc wording fixes + new requirement adds — (a) REQUIREMENTS.md DGN-03 signature (`(uint8[4]) internal pure` → `(uint32 ticket) private pure returns (uint8)` per D-267-COUNTGOLD-01); (b) REQUIREMENTS.md DGN-01 visibility (`external pure` → `internal pure` per D-267-VISIBILITY-01); (c) ROADMAP success criterion 1 + 5 visibility wording + criterion 2 signature wording + Phase 271 AUDIT-04 attestation drop "ALLOWED-NEW-STATELESS-ENTRY" (replace with attestation that ZERO new external pure entries are added); (d) NEW: REQUIREMENTS.md add PAY-SPLIT-01..03 section (per D-267-PAYSPLIT-01..05) + STAT-07 + AUDIT-02 surface (h) + Coverage line 47→51 + Traceability rows for all 4 new reqs; (e) NEW: ROADMAP.md Phase 267 inline goal + success criterion 6 covering `_distributePayout` rewrite + Phase 268 STAT-07 wording + Phase 271 AUDIT-02 surface (h) wording. All edits in a single agent-commit (this CONTEXT.md update commit batches all upstream-doc edits per D-267-APPROVAL-01 carry).
  2. **Chore:** re-run `python3 .planning/notes/degenerette-recalibration/derive_5_tables.py`, capture stdout into `267-01-CONSTANTS-VERIFY.md`, grep-assert every emitted hex byte-string matches the planning-note's pasted .sol hex byte-for-byte (per D-267-CONSTVERIFY-01).
  3. **Contract impl + USER-APPROVED batched commit:** TraitUtils additive (`packedTraitsDegenerette` + `_degTrait` private helper) AND DegeneretteModule rewrite — (a) delete `_evNormalizationRatio` + its call site; (b) add `_countGoldQuadrants` + `_wwxrpFactor`; (c) rewrite `_getBasePayoutBps` + `_applyHeroMultiplier` + `_fullTicketPayout` for per-N dispatch; (d) rewrite `_distributePayout` ETH branch with 3-tier split rule per D-267-PAYSPLIT-01..03 + thread `betAmount` (uint128) into the signature per D-267-PAYSPLIT-05 + update L656 call site to pass `amountPerTicket`; (e) swap producer at L607; (f) rewrite stale comments per D-267-COMMENTS-01 + add NatSpec to `_distributePayout` documenting the 3-tier rule + pool-cap precedence; (g) replace 4 single-table + 2 normalizer constants with 25 per-N packed constants. One diff, one approval, one commit.
  4. **Phase-close:** `267-01-SUMMARY.md` + commit-readiness register (i USER-APPROVED contracts: 1 commit; ii USER-APPROVED tests: 0 commits — Phase 268 owns tests; iii AGENT-COMMITTED planning artifacts: PLAN + SUMMARY + CONSTANTS-VERIFY + REQUIREMENTS.md DGN-03 wording fix).
  ~4 atomic commits total. Single-plan-multi-task discipline.

- **D-267-CONSTVERIFY-01 (constant-verification policy):** Three-part:
  1. Plan task re-runs `derive_5_tables.py`, captures stdout into `.planning/phases/267-degenerette-producer-5-table-payout-rewrite/267-01-CONSTANTS-VERIFY.md`.
  2. Same task grep-asserts every constant byte-string in the script output matches the .sol pasted hex byte-for-byte (`QUICK_PLAY_PAYOUTS_N{0..4}_PACKED` + 5 × `QUICK_PLAY_PAYOUT_N{0..4}_M8` + 5 × `HERO_BOOST_N{0..4}_PACKED` + 5 × `WWXRP_FACTORS_N{0..4}_PACKED`). Any mismatch BLOCKS the contract commit.
  3. Phase 268 STAT-05 empirically verifies per-N basePayoutEV = 100.00 ± 0.50 centi-x against actual on-chain dispatch (catches bit-rot or mis-paste drift that the script-grep missed).
  Closes the verification gap that bit Phase 259 (heavy-tail producer landed without payout-consumer reconciliation; v34 §3d carved Degenerette UNAFFECTED on a bit-layout-only check).

- **D-267-COMMENTS-01 (NatSpec-first + surgical inline rewrite):** Comment rewrite scope:
  - **NatSpec on every new/rewritten function:** `packedTraitsDegenerette` + `_degTrait` (TraitUtils); `_countGoldQuadrants` + `_getBasePayoutBps` + `_wwxrpFactor` + `_applyHeroMultiplier` + `_fullTicketPayout` (DegeneretteModule). NatSpec describes the per-N table dispatch + bit layout + EV invariant in the language of CURRENT design only (per `feedback_no_history_in_comments.md` — never references "this used to be a normalizer" or "previous design").
  - **DELETE entirely §"EXACT EV NORMALIZATION" prose at L287-298** (it describes the deleted normalizer; nothing in the new code references it). Replace with a single-line top-of-section `///` comment naming the per-N invariant: `"EV-equality across picks: each pick maps to exactly one of 5 per-N tables; basePayoutEV is calibrated to 100 centi-x per table; runtime payout = bet × basePayout_N(M) × roiBps / 1_000_000."`
  - **Surgically rewrite L239 (RTP claim → "basePayoutEV = 100 centi-x exact per N; player RTP = roiBps/10000")**, **L262 (`weights=10` → "per-N factors derived from each N's basePayout schedule + binomial-convolution P_N(M) + 10/30/30/30 split; ETH bonus EV = 5.000% per N")**, and **L316 (`HERO_BOOST_PACKED` reference → per-N `HERO_BOOST_N{0..4}_PACKED` reference)**.
  - **Block headers L235-251 / L253-268 / L314-322 get fresh §-headers** describing the per-N tables that occupy those storage slots in the new design.
  - **Audit-trail framing:** all comments in the language of "what IS" — zero "what changed" prose anywhere in the contract source. Phase 271 §3.A delta-surface row count higher than DGN-13 minimum but each row carries clear DOC-CLEANUP classification.

### Claude's Discretion (planner refines)

- **Per-N dispatch style:** chained `if/else if` on `N` (planning note pattern) vs `assembly switch` vs jumptable. Planning note locks chained-if; planner may swap if gas regression in Phase 268 SURF-06 demands. Default: chained-if.
- **`_wwxrpFactor` placement:** new private helper vs inlined into `_fullTicketPayout`. Planner picks; planning note shows separate helper for clarity.
- **NatSpec line-budget:** how verbose the per-N tables' bit-layout commentary gets. Planner picks; minimum: which bits each `% small` slice consumes (for `packedTraitsDegenerette`'s `_degTrait`) + the per-N table layout `[M=0..7 packed in 8×32 bits | M=8 separate uint256]` (for payouts) and `[M=2..7 packed in 6×16 bits = 96 bits]` (for hero) and `[B=5..8 packed in 4×64 bits]` (for WWXRP).
- **Naming convention for the new private helper in TraitUtils:** `_degTrait` (planning note) vs `_packDegenQuadrant` vs other. Planner picks.
- **Plan-task ordering:** the 4-step order in D-267-PLAN-01 is the sketch; planner may interleave (e.g., REQUIREMENTS.md fix can land in the same agent commit as PLAN.md authoring). Per-task atomic-commit discipline preserved.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 267 Anchors

- `.planning/ROADMAP.md` §"Phase 267: Degenerette Producer + 5-Table Payout Rewrite" — 5 success criteria; depends-on = nothing (first impl phase); audit baseline v36.0 closure HEAD `1c0f0913`.
- `.planning/REQUIREMENTS.md` DGN-01..DGN-15 — 15 v37.0 requirements all mapped to Phase 267 (Note: DGN-03 wording is corrected to `(uint32 ticket) private pure returns (uint8)` as a Phase 267 plan chore task per D-267-COUNTGOLD-01).
- `.planning/STATE.md` — milestone v37.0 status; Phase 267 active; v36.0 closure signal `MILESTONE_V36_AT_HEAD_1c0f0913` carry-forward context.
- `.planning/PROJECT.md` — current focus banner, READ-only-LIFTED disposition.

### Source-of-Truth Planning Note (paste-ready code + locked decisions)

- `.planning/notes/2026-05-10-degenerette-payout-recalibration.md` — exhaustive ~540-line planning note. Contains:
  - §"Locked decisions" — D-267-SCOPE-01 / D-267-DIST-01 / D-267-NORM-01 / D-267-EV-TARGET-01 / D-267-EV-PRECISION-01 / D-267-HERO-01..02 / D-267-WWXRP-SPLIT-01 / D-267-PRODUCER-API-01 / D-267-FILES-01 / D-267-PHASE-SHAPE-01 / D-267-CLOSURE-01..02 / D-267-ADVERSARIAL-01.
  - §"Concrete file changes" — paste-ready Solidity for `packedTraitsDegenerette`, `_degTrait`, `_countGoldQuadrants`, `_getBasePayoutBps`, `_wwxrpFactor`, `_applyHeroMultiplier`, `_fullTicketPayout`. **MUST be the source of truth for the contract diff.**
  - §"Constants paste reference" — 25 packed constants byte-values; derived via `Fraction`-exact Python script.
  - §"Audit deliverable shape (Phase 269)" — mis-numbered (it's Phase 271 not 269 in the current 5-phase ROADMAP); ignore the phase-number labeling, content is correct.
- `.planning/notes/degenerette-recalibration/derive_5_tables.py` — reproducible `Fraction`-exact derivation of all 25 constants. Re-run as a Phase 267 plan chore task per D-267-CONSTVERIFY-01; output captured into `267-01-CONSTANTS-VERIFY.md`.
- `.planning/notes/degenerette-recalibration/derive_constants.py` — REJECTED single-normalizer alternative; kept for reference only. Do NOT use for Phase 267.

### Live Contract State (mutation subject — HEAD `1c0f0913`)

- `contracts/DegenerusTraitUtils.sol` — additive change site (new `packedTraitsDegenerette` + `_degTrait` private helper). Existing `weightedColorBucket` / `traitFromWord` / `packedTraitsFromSeed` bodies stay byte-identical (DGN-14, Phase 268 SURF-01).
- `contracts/modules/DegenerusGameDegeneretteModule.sol` — primary mutation site. Affected line ranges at v36.0 HEAD:
  - L235-251: `QUICK_PLAY_BASE_PAYOUTS_PACKED` block — DELETED, replaced by 5 × `QUICK_PLAY_PAYOUTS_N{0..4}_PACKED` + 5 × `QUICK_PLAY_PAYOUT_N{0..4}_M8`.
  - L253-268: WWXRP bonus EV redistribution `WWXRP_BONUS_FACTOR_BUCKET5..8` block — DELETED, replaced by 5 × `WWXRP_FACTORS_N{0..4}_PACKED`.
  - L287-298: §"EXACT EV NORMALIZATION" prose — DELETED entirely (per D-267-COMMENTS-01).
  - L314-322: hero quadrant multiplier `HERO_BOOST_PACKED` block — DELETED, replaced by 5 × `HERO_BOOST_N{0..4}_PACKED`.
  - L607: producer call `packedTraitsFromSeed(resultSeed)` — SWAPPED to `packedTraitsDegenerette(resultSeed)` (DGN-12).
  - L808-851: `_evNormalizationRatio` function body — DELETED (DGN-02).
  - L933+: `_fullTicketPayout` body — REWRITTEN for N-threading + per-N table dispatch + symbol-only hero.
  - L965-969: single call site of `_evNormalizationRatio` — DELETED.
  - L239 + L262 + L316: stale comment surfaces — surgically rewritten per D-267-COMMENTS-01.
  - L656: `_distributePayout(player, currency, payout, lootboxWord)` callsite — ARG INSERT to pass `amountPerTicket` per D-267-PAYSPLIT-05 (new signature `_distributePayout(player, currency, betAmount, payout, lootboxWord)`).
  - L678-740: `_distributePayout` body + NatSpec — REWRITTEN per D-267-PAYSPLIT-01..04 (3-tier ETH split rule + 2.5× floor + pool-cap precedence). `CURRENCY_BURNIE` (L735-736) + `CURRENCY_WWXRP` (L737-739) branches UNCHANGED.
- `contracts/modules/DegenerusGameMintModule.sol` — UNTOUCHED; existing `packedTraitsFromSeed` consumer body byte-identical (Phase 268 SURF-04 carry; v34 gold-solo Mint mechanic preserved).
- `contracts/modules/DegenerusGameJackpotModule.sol` — UNTOUCHED; v34 gold-solo `_pickSoloQuadrant` + 4 ETH-distribution injection sites + `JackpotBucketLib` byte-identical (Phase 268 SURF-02).
- `contracts/modules/DegenerusGameLootboxModule.sol` — UNTOUCHED at Phase 267 (v36 entropy-refactor surfaces stay byte-identical at Phase 267 close; Phase 269 will delete the dead BURNIE-conversion branch separately).
- `contracts/libraries/EntropyLib.sol` — UNTOUCHED (Phase 268 SURF-04 / v36 ENT-04 carry).

### v33.0 / v34.0 / v35.0 / v36.0 Precedent (deliverable shape + commit discipline)

- `.planning/milestones/v36.0-phases/266-lootbox-entropy-refactor/266-CONTEXT.md` — primary template for Phase 267 decision-shape and carry-forward chain (D-266-FILES-01 / D-266-CLOSURE-01..02 / D-266-FCITE-01 / D-266-SEV-01 / D-266-APPROVAL-01..02 / D-266-ADVERSARIAL-01..03).
- `.planning/milestones/v36.0-phases/266-lootbox-entropy-refactor/266-01-PLAN.md` — single-multi-task atomic-commit-per-task precedent (~12-task v36 plan; Phase 267 expected ~4-task because narrower scope).
- `.planning/milestones/v36.0-phases/266-lootbox-entropy-refactor/266-01-SUMMARY.md` — phase-closure SUMMARY format precedent.
- `audit/FINDINGS-v36.0.md` — v36.0 9-section deliverable; closure signal `MILESTONE_V36_AT_HEAD_1c0f0913`. Phase 271 will mirror this shape for v37.0.

### Memory / Feedback Governing This Phase

- `feedback_no_contract_commits.md` — explicit per-commit user approval for `contracts/` + `test/` changes. Phase 267 has 1 batched contract commit (TraitUtils additive + DegeneretteModule rewrite combined), USER-APPROVED.
- `feedback_batch_contract_approval.md` — batch all phase contract edits, present one diff at end. Phase 267 follows this discipline by combining TraitUtils helper addition with DegeneretteModule rewrite into a single diff/commit.
- `feedback_never_preapprove_contracts.md` — orchestrator/agent must NOT pre-approve any contract change. Vacuous unless the agent attempts to claim pre-approval; just don't.
- `feedback_no_history_in_comments.md` — D-267-COMMENTS-01 NatSpec describes per-N tables as the CURRENT design. NEVER reference "this was a normalizer before" or "previous color distribution" anywhere in contract source.
- `feedback_wait_for_approval.md` — D-267-APPROVAL-02 contract-diff approval gate. Agent presents the batched diff, waits for explicit "approved" before committing.
- `feedback_manual_review_before_push.md` — final user-review gate before any push. NO `git push` by agent.
- `feedback_rng_backward_trace.md` — backward-trace methodology applies if any RNG-relevant adversarial surface lands in Phase 271 §4 (e.g., AUDIT-02 surface (b) symbol-only hero match). Producer changes are RNG-relevant; per-N table dispatch is not.
- `feedback_gas_worst_case.md` — Phase 268 SURF-06 derives theoretical worst-case gas envelope FIRST (gold-counter 4-iter loop + 5-case dispatch + 5 packed-constant SLOAD-equivalents), then tests. Net expected ≈ wash (normalizer math removed; per-N dispatch added).
- `feedback_skip_research_test_phases.md` — Phase 267 has locked decisions in this CONTEXT.md + paste-ready code in the planning note. Skip research-agent dispatch; jump straight to plan-phase.
- `feedback_contractaddresses_policy.md` — N/A; Phase 267 doesn't touch `ContractAddresses.sol`.
- `feedback_no_dead_guards.md` — N/A for Phase 267 (lootbox dead-branch cleanup is Phase 269).

### Active KI Envelope

- `KNOWN-ISSUES.md` — current state at v36.0 close. EXC-04 NARROWED to BAF-jackpot-only scope at v36. Phase 267 makes no KI changes (KI walkthrough lives in Phase 271 AUDIT-05).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **Paste-ready Solidity in the planning note** — `.planning/notes/2026-05-10-degenerette-payout-recalibration.md` §"Concrete file changes" contains paste-ready bodies for `packedTraitsDegenerette`, `_degTrait`, `_countGoldQuadrants`, `_getBasePayoutBps`, `_wwxrpFactor`, `_applyHeroMultiplier`, `_fullTicketPayout`. Source-of-truth for the contract diff.
- **25 packed constants byte-strings** — same note §"Concrete file changes" / §"Constants paste reference"; each constant's hex body is reproducible via `derive_5_tables.py`.
- **`packedTraitsFromSeed` body** — preserved verbatim; new `packedTraitsDegenerette` is a sibling helper using a different `_degTrait` private helper internally. Same `[QQ][CCC][SSS]` byte layout for downstream consumer compatibility.
- **`_fullTicketPayout` skeleton** — call-site changes localized: thread `N` through `_getBasePayoutBps` + `_wwxrpFactor` + `_applyHeroMultiplier`. Bonus-bucket dispatch (`_wwxrpBonusBucket`) UNCHANGED.

### Established Patterns

- **Single batched contract commit per phase** — v33 P256 / v34 P262 / v35 P265 / v36 P266. Phase 267 inherits.
- **Atomic-commit per task** — v33/v34/v35/v36 single-plan multi-task pattern.
- **Constants centralized at top of file** — DegeneretteModule already groups packed constants near top (L235-322 region). New 25 constants stay in this region.
- **Bit-packed constants** — convention: packed schedules read via `(packed >> (idx * width)) & mask`. New per-N tables follow the same convention (32-bit/64-bit/16-bit slices depending on table type).
- **Producer/consumer separation** — `DegenerusTraitUtils.sol` produces packed traits; module consumers read with `>> shift & mask` patterns. `packedTraitsDegenerette` joins this convention.

### Integration Points

- **`contracts/DegenerusTraitUtils.sol`** — additive change; new `packedTraitsDegenerette` + `_degTrait` private helper. Existing 3 functions byte-identical (DGN-14, Phase 268 SURF-01).
- **`contracts/modules/DegenerusGameDegeneretteModule.sol`** — primary mutation site (see `<canonical_refs>` Live Contract State for line ranges).
- **`.planning/phases/267-degenerette-producer-5-table-payout-rewrite/`** — phase artifacts: `267-CONTEXT.md` (this file), `267-01-PLAN.md` (planner output), `267-01-CONSTANTS-VERIFY.md` (executor output per D-267-CONSTVERIFY-01), `267-01-SUMMARY.md` (executor output), `267-DISCUSSION-LOG.md` (sibling to this file).
- **`.planning/REQUIREMENTS.md`** — DGN-03 wording fix (Phase 267 plan chore task per D-267-COUNTGOLD-01).
- **`audit/FINDINGS-v37.0.md`** — does NOT exist yet at Phase 267 close; authored in Phase 271. Phase 267 contributes the §3.A delta-surface row content (TraitUtils additive + DegeneretteModule rewrite enumerated declarations).

</code_context>

<specifics>
## Specific Ideas

### `_countGoldQuadrants` body (paste-ready, locked per D-267-COUNTGOLD-01)

```solidity
/// @dev Counts gold (color == 7) quadrants in a packed ticket.
///      Returns N ∈ {0, 1, 2, 3, 4} — the index for per-N payout/hero/WWXRP tables.
function _countGoldQuadrants(uint32 ticket) private pure returns (uint8 count) {
    unchecked {
        for (uint8 q = 0; q < 4; ++q) {
            uint8 color = uint8((ticket >> (q * 8 + 3)) & 7);
            if (color == 7) ++count;
        }
    }
}
```

### `packedTraitsDegenerette` body (paste-ready, locked per D-267-DIST-01 + D-267-VISIBILITY-01)

Mirrors `packedTraitsFromSeed` convention at `contracts/DegenerusTraitUtils.sol:169-178` exactly: each per-quadrant byte is `[QQ][CCC][SSS]` with QQ tag in bits 7-6 of the byte (Q=0 → 0x00, Q=1 → 0x40, Q=2 → 0x80, Q=3 → 0xC0); 4 bytes packed into uint32 via `<< 0/8/16/24`.

```solidity
/// @notice Packs 4 quadrant traits using the Degenerette near-uniform color
///         distribution: 7 commons at 2/15 each, gold at 1/15.
/// @dev Per-quadrant: color via base-15 scaling (gold = scaled==14, common =
///      scaled >> 1), symbol uniform 1/8 from the high 32 bits of each 64-bit lane.
///      Existing packedTraitsFromSeed (heavy-tail color) preserved for
///      MintModule + JackpotModule consumers (DGN-14, Phase 268 SURF-01).
function packedTraitsDegenerette(uint256 rand) internal pure returns (uint32) {
    uint8 traitA = _degTrait(uint64(rand));                  // Q=0: bits 7-6 = 00
    uint8 traitB = _degTrait(uint64(rand >> 64))  | 64;      // Q=1: bits 7-6 = 01
    uint8 traitC = _degTrait(uint64(rand >> 128)) | 128;     // Q=2: bits 7-6 = 10
    uint8 traitD = _degTrait(uint64(rand >> 192)) | 192;     // Q=3: bits 7-6 = 11
    return uint32(traitA)
         | (uint32(traitB) << 8)
         | (uint32(traitC) << 16)
         | (uint32(traitD) << 24);
}

function _degTrait(uint64 rnd) private pure returns (uint8) {
    uint32 scaled = uint32((uint64(uint32(rnd)) * 15) >> 32);
    uint8 color = scaled == 14 ? 7 : uint8(scaled >> 1);
    uint8 symbol = uint8(rnd >> 32) & 7;
    return (color << 3) | symbol;
}
```

**Verified against `packedTraitsFromSeed`:** the OR-masks (`| 64`, `| 128`, `| 192`) are the canonical [QQ][CCC][SSS] byte-layout convention — `_degTrait` returns `(color << 3) | symbol` which occupies bits 0..5; the QQ tag occupies bits 6..7. Convention is identical to `packedTraitsFromSeed` line 171-174.

### `_getBasePayoutBps` body (paste-ready, locked per D-267-EV-TARGET-01)

```solidity
/// @dev Dispatches to the per-N base payout table.
function _getBasePayoutBps(uint8 N, uint8 matches) private pure returns (uint256) {
    if (matches >= 8) {
        if (N == 0) return QUICK_PLAY_PAYOUT_N0_M8;
        if (N == 1) return QUICK_PLAY_PAYOUT_N1_M8;
        if (N == 2) return QUICK_PLAY_PAYOUT_N2_M8;
        if (N == 3) return QUICK_PLAY_PAYOUT_N3_M8;
        return QUICK_PLAY_PAYOUT_N4_M8;
    }
    uint256 packed;
    if (N == 0) packed = QUICK_PLAY_PAYOUTS_N0_PACKED;
    else if (N == 1) packed = QUICK_PLAY_PAYOUTS_N1_PACKED;
    else if (N == 2) packed = QUICK_PLAY_PAYOUTS_N2_PACKED;
    else if (N == 3) packed = QUICK_PLAY_PAYOUTS_N3_PACKED;
    else packed = QUICK_PLAY_PAYOUTS_N4_PACKED;
    return (packed >> (uint256(matches) * 32)) & 0xFFFFFFFF;
}
```

### `_applyHeroMultiplier` body (paste-ready, locked per D-267-HERO-01..02)

```solidity
function _applyHeroMultiplier(
    uint256 payout,
    uint32 playerTicket,
    uint32 resultTicket,
    uint8 matches,
    uint8 heroQuadrant,
    uint8 N
) private pure returns (uint256) {
    uint256 shift = uint256(heroQuadrant) * 8;
    bool symbolMatch = ((playerTicket >> shift) & 7) == ((resultTicket >> shift) & 7);

    uint256 multiplier;
    if (symbolMatch) {
        uint256 packed;
        if (N == 0) packed = HERO_BOOST_N0_PACKED;
        else if (N == 1) packed = HERO_BOOST_N1_PACKED;
        else if (N == 2) packed = HERO_BOOST_N2_PACKED;
        else if (N == 3) packed = HERO_BOOST_N3_PACKED;
        else packed = HERO_BOOST_N4_PACKED;
        multiplier = (packed >> (uint256(matches - 2) * 16)) & 0xFFFF;
    } else {
        multiplier = HERO_PENALTY;
    }
    return (payout * multiplier) / HERO_SCALE;
}
```

### 25 packed constant byte-values (paste-ready, locked per D-267-CONSTPASTE-01)

See `.planning/notes/2026-05-10-degenerette-payout-recalibration.md` §"Concrete file changes" → "CONSTANT REWRITE" block. All 25 constants pre-rendered. Re-derive via `python3 .planning/notes/degenerette-recalibration/derive_5_tables.py` per D-267-CONSTVERIFY-01 to produce the .sol-ready hex strings, then grep-assert byte-identical match.

### `_distributePayout` ETH-branch rewrite shape (locked per D-267-PAYSPLIT-01..05)

Sketch (planner refines exact form). Surrounding non-ETH branches and frozen-pool branch UNCHANGED:

```solidity
/// @dev Distributes payout to player. ETH-currency 3-tier split rule:
///        - payout <= 3 * betAmount → 100% ETH (no lootbox conversion)
///        - 3 * betAmount < payout <= 10 * betAmount → 2.5 * betAmount ETH + remainder lootbox
///        - payout > 10 * betAmount → 25% ETH + 75% lootbox
///      Pool-cap (ETH_WIN_CAP_BPS = 10% of futurePool) takes precedence over all three tiers:
///      if computed ethShare exceeds 10% of pool, excess flips to lootbox.
function _distributePayout(
    address player,
    uint8 currency,
    uint128 betAmount,
    uint256 payout,
    uint256 rngWord
) private {
    if (currency == CURRENCY_ETH) {
        // 3-tier split rule (PAY-SPLIT-01..02)
        uint256 ethShare;
        uint256 lootboxShare;
        uint256 threeBet = uint256(betAmount) * 3;
        if (payout <= threeBet) {
            ethShare = payout;             // tier 1: all ETH
            lootboxShare = 0;
        } else {
            uint256 minEth = (uint256(betAmount) * 5) / 2;       // 2.5 * bet
            uint256 stdEth = payout / 4;                          // 25%
            ethShare = stdEth > minEth ? stdEth : minEth;         // tier 2 floor or tier 3 standard
            lootboxShare = payout - ethShare;
        }

        if (prizePoolFrozen) {
            // Frozen-pool branch: pending future debit + claimable ETH credit
            (uint128 pNext, uint128 pFuture) = _getPendingPools();
            if (uint256(pFuture) < ethShare) revert E();
            _setPendingPools(pNext, pFuture - uint128(ethShare));
            _addClaimableEth(player, ethShare);
        } else {
            // Unfrozen path: pool cap precedence (PAY-SPLIT-03)
            uint256 pool = _getFuturePrizePool();
            uint256 maxEth = (pool * ETH_WIN_CAP_BPS) / 10_000;
            if (ethShare > maxEth) {
                lootboxShare += ethShare - maxEth;
                ethShare = maxEth;
                emit PayoutCapped(player, ethShare, lootboxShare);
            }
            unchecked { pool -= ethShare; }
            _setFuturePrizePool(pool);
            _addClaimableEth(player, ethShare);
        }

        if (lootboxShare > 0) {
            _resolveLootboxDirect(player, lootboxShare, rngWord);
        }
    } else if (currency == CURRENCY_BURNIE) {
        coin.mintForGame(player, payout);
    } else if (currency == CURRENCY_WWXRP) {
        wwxrp.mintPrize(player, payout);
    }
}
```

Call site at L656 updated:

```solidity
// Was:  _distributePayout(player, currency, payout, lootboxWord);
// Now:  _distributePayout(player, currency, amountPerTicket, payout, lootboxWord);
```

Worked examples (bet = 1.0, no pool-cap interference):

| payout (× bet) | ethShare | lootboxShare | tier |
|---|---|---|---|
| 2.0 | 2.0 | 0 | 1 (≤3×) |
| 3.0 | 3.0 | 0 | 1 (≤3×) |
| 3.01 | 2.5 | 0.51 | 2 (floor) |
| 5.0 | 2.5 | 2.5 | 2 (floor) |
| 10.0 | 2.5 | 7.5 | 2 = 3 boundary |
| 100.0 | 25.0 | 75.0 | 3 (25% standard) |
| 209,164 (M=8 N=4) | 52,291 | 156,873 | 3 (25% standard) |

</specifics>

<deferred>
## Deferred Ideas

### `_jackpotTicketRoll` BAF jackpot xorshift refactor (v36 ENT-05 carry)

`DegenerusGameJackpotModule.sol:2186-2229`. Same xorshift pattern as the v36-completed lootbox refactor; explicit deferral per v36 D-266-SCOPE-OUT-01. NOT a Phase 267 (or v37.0) deliverable. Tracked in `.planning/STATE.md` Next-Milestone Backlog.

### Phase 269 lootbox dead BURNIE-conversion branch deletion (LBX-01..03)

`DegenerusGameLootboxModule.sol _resolveLootboxRoll` ~L1568-1581 dead `if (targetLevel < currentLevel)` branch. Routed to Phase 269 in this milestone, NOT Phase 267. Phase 267 leaves LootboxModule byte-identical.

### Phase 269 SURF-05 gas-pin re-pinning (GASPIN-01..03)

Phase 261/264 SURF-05 ~120K gas-pin drift under `npm run test:stat` ordering. Routed to Phase 269. Phase 267 doesn't touch gas pins.

### Phase 270 post-v32.0 deferred-commit adversarial sub-audit (`002bde55` + `2713ce61`)

Carry-forward deferral from v33→v34→v35→v36→v37 close per repeated user disposition. Phase 270 audit-only. NOT a Phase 267 concern.

### `/economic-analyst` + `/degen-skeptic` adversarial-skill expansion for Phase 271

Planning note locks `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` + `/degen-skeptic` for Phase 271. ROADMAP notes "/economic-analyst + /degen-skeptic inclusion deferred to Phase 271 discuss-phase decision per CONTEXT.md". Resolve at Phase 271 discuss-phase, not Phase 267.

### `runrewardjackpots` module-misplacement (2026-04-02 stale backlog note)

Out of v37.0 scope per `.planning/REQUIREMENTS.md` Out of Scope table. Not v37.0-tagged.

### Game-over thorough hardening (`gameover-thorough-test.md`)

Out of v37.0 scope; defer to dedicated game-over hardening milestone.

### Single-normalizer alternative design (`derive_constants.py`)

Rejected per user disposition. The 5-table design (`derive_5_tables.py`) supersedes it. Kept in `.planning/notes/degenerette-recalibration/derive_constants.py` for reference only.

</deferred>

---

*Phase: 267-degenerette-producer-5-table-payout-rewrite*
*Context gathered: 2026-05-10*
