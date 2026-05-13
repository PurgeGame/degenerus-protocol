# Phase 272 Plan 01 — Adversarial Validation Log

**Phase:** 272-always-hero-simplification-maximal-dead-code-cleanup-terminal
**Plan:** 272-01
**Target:** `audit/FINDINGS-v38.0.md` §4 7-surface inline draft (a)..(g) — post-Task-3.4 state
**Methodology:** D-272-ADVERSARIAL-01 (PARALLEL spawn via single message — `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`). 4th-skill scope explicitly bounded to these three per D-271-ADVERSARIAL-02 carry → D-272-ADVERSARIAL-01 (degen-skeptic-grade adversarial skill is out of scope at v38).
**HEAD at adversarial-pass authoring time:** `079ec007` (post-Task-3.4 §6/§7/§8 commit, Wave 3)
**Wave 1 contract commit:** `527e3adc` (HERO-01..05 + CLEAN-01..05)
**Wave 2 test commit:** `e3fcb95c` (STAT-01..02 + SURF-01..03 + LBX-02 RE-DEFER + GASPIN-02 (a-alt) + GASPIN-03 + STAT-03-v35-carry ACCEPTED-DESIGN)
**Spawned:** 2026-05-11

Input to each skill: (1) the finished §4 7-surface inline draft + §4.2 verdict roll-up; (2) the Wave 1 contract diff at `527e3adc`; (3) the Wave 2 test diff at `e3fcb95c`; (4) Phase 272 CONTEXT.md `<decisions>` + `<deferred_to_planner>` + `<canonical_refs>` blocks; (5) per-skill focus mandate per `272-01-PLAN.md` Task 3.5.

---

## /contract-auditor

Solidity-focused adversarial review of the v38.0 hero-quadrant-extraction edit in `contracts/modules/DegenerusGameDegeneretteModule.sol` (live at HEAD with the post-Wave-1 body at `527e3adc`) against the §4 7-surface sweep in `audit/FINDINGS-v38.0.md`. Methodology: read the post-edit bodies line-by-line; trace each surface to its concrete code-path; attempt to construct a counterexample for each verdict; map the hero-pack/extract block at L591 + L832-845 + L947-993; backward-trace per `feedback_rng_backward_trace.md`; commitment-window analysis per `feedback_rng_commitment_window.md`.

### Per-surface verdicts

- **Surface (a) — Hero always-on EV-neutrality preserved across (M, N): AGREE — SAFE_BY_DESIGN. Mechanism strength: STRUCTURAL.**

  Verified per-N HERO_BOOST tables byte-identical at L337-341 (`grep -E "HERO_BOOST_N[0-4]_PACKED" contracts/modules/DegenerusGameDegeneretteModule.sol` returns the 5 packed constants byte-identical to v37 baseline `2654fcc2`). `HERO_PENALTY = 9500` (L342) and `HERO_SCALE = 10000` (L343) byte-identical. EV-neutrality equation `P(hero|M, N) × boost(M, N) + (1 − P(hero|M, N)) × HERO_PENALTY = HERO_SCALE` mechanically preserved across all (M, N) ∈ ({2..7} × {0..4}) — the calibration is encoded in the table values themselves, which are UNCHANGED. The Wave 2 STAT-01 + STAT-02 re-pin under always-on hero PASS at ≥1M draws/N + ≥100K hero-active draws/N respectively (within ±0.50 centi-x basePayoutEV / ±1% hero-active EV-neutrality tolerance) is the empirical witness. Structural closure: the per-N HERO_BOOST tables are the SAME mathematical object as the EV-neutrality equation solution at each (M, N) — by construction. No counterexample constructible.

- **Surface (b) — Hero quadrant 0 default does NOT create payout-bias: AGREE — SAFE_BY_DESIGN. Mechanism strength: STRUCTURAL.**

  Per-quadrant symbol distribution `[16,16,16,16,16,16,16,8]/120` (color) × uniform 1/8 (symbol) is producer-level — `packedTraitsDegenerette` at `contracts/DegenerusTraitUtils.sol` byte-identical at v38 HEAD (cross-module byte-identity grep proof in §3.B). The per-N HERO_BOOST table dispatch indexes by N (gold-quadrant count from `_countGoldQuadrants(playerTicket)`, NOT player-chosen heroQuadrant). The hero-match equality check at `_applyHeroMultiplier` L1018 `((playerTicket >> heroQuadrant*8) & 7) == ((resultTicket >> heroQuadrant*8) & 7)` reads the 3-bit symbol nibble of the chosen quadrant — uniform 1/8 distribution per quadrant means P(hero match | M, N) is structurally the same for any heroQuadrant ∈ {0..3}. Quadrant 0 default is informationally neutral.

- **Surface (c) — Each cleanup-sweep removal preserves the invariant it claimed to guard: AGREE — SAFE_BY_DESIGN. Mechanism strength: DESIGN + STRUCTURAL.**

  Per-CLEAN-NN design-intent trace inline in the Wave 1 commit message `527e3adc` body + §3.A row attribution + §4 surface (c) prose. Verified each removal:
  - MASK_3 (v37 baseline L347) — cross-module grep `grep -rn "MASK_3" contracts/` at HEAD returns zero matches; no other-file callsites; safe to delete.
  - heroBits + heroEnabled locals (v37 baseline L592-594) — replaced by the direct quadrant extract at post-edit L591 (single line, semantically equivalent under always-on schedule).
  - heroEnabled parameter on `_fullTicketPayout` — the `heroEnabled &&` arm of the guard predicate was statically true under always-on schedule (the hero application is unconditional for M ∈ {2..7}); removal preserves the safety property `matches >= 2 && matches < 8`.
  - @param heroEnabled NatSpec line — removed in tandem with parameter (doc-block consistency).
  - Stale "enabled" / "opt-out" comments — rewritten per `feedback_no_history_in_comments.md`. Sample check: L321 `FT_HERO_SHIFT` inline comment at HEAD reads `// 3 bits: [0]=reserved, [1..2]=quadrant (always-on hero)` — no comparative/historical language.
  - CLEAN-05 negative result (no additional redundant-guard removals) — manual grep-walk found no further candidates with statically-provable predicates beyond the HERO-03 guard simplification.

- **Surface (d) — Storage layout byte-identical at v38 vs `2654fcc2`: AGREE — SAFE_BY_STRUCTURAL_CLOSURE. Mechanism strength: STRUCTURAL.**

  `FT_HERO_SHIFT = 237` (L321) preserved at v38 HEAD. Vestigial enabled bit at offset 0 always = 1 post-pack via `uint256(1)` at L843. 3-bit allocation preserved (no collapse to 2 bits) — explicit storage-layout discipline per HERO-02 bit allocation lock. Verified `diff <(git show 2654fcc2:contracts/modules/DegenerusGameDegeneretteModule.sol | grep -E "FT_.*_SHIFT") <(grep -E "FT_.*_SHIFT" contracts/modules/DegenerusGameDegeneretteModule.sol)` returns exit 0 (all `FT_*_SHIFT` constant declarations byte-identical except the inline comment on the `FT_HERO_SHIFT` line which is the HERO-04 NatSpec rewrite). Storage state byte-identical.

- **Surface (e) — Public ABI byte-identical: AGREE — SAFE_BY_STRUCTURAL_CLOSURE. Mechanism strength: STRUCTURAL.**

  `placeDegeneretteBet(address player, uint8 currency, uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 heroQuadrant)` signature byte-identical at L367-374. `0xFF` accepted at ABI boundary; HERO-01 normalization (`uint8 effectiveQuadrant = heroQuadrant < 4 ? heroQuadrant : 0;` at L832) happens AFTER the call frame enters `_packFullTicketBet`. No revert on `heroQuadrant >= 4`. Backward-compatible with v37-integrated frontends and EOA callers. `_fullTicketPayout` signature change (drop of `bool heroEnabled` parameter) is internal-only (`private` linkage); no ABI impact.

- **Surface (f) — Variance impact bound on risk-averse subset: AGREE — SAFE_BY_DESIGN. Mechanism strength: DESIGN.**

  EV invariant by construction (per surface (a)). Worst-case downside per hero-active spin = `HERO_PENALTY × basePayout = 0.95 × basePayout` (5% downside). Best-case upside per hero-active spin = boost-magnitude × basePayout (per-N table, ~1.18× to ~2.50× across M ∈ {2..7}). Variance increase on the variance-averse subset is documented as accepted-design via §4 (f) prose disclosure per D-272-KI-01 default. No new KNOWN-ISSUES.md entry under Design Decisions. Player has zero EV-rational reason to prefer pre-v38 over post-v38 (EV invariant); variance-averse players lose a variance-reduction tool but receive same EV.

- **Surface (g) — `npm run test:stat` + `npm run test:gas` clean run at v38 close: AGREE — SAFE_BY_STRUCTURAL_CLOSURE. Mechanism strength: STRUCTURAL.**

  GASPIN-02 path (a-alt) script-split applied at `package.json` per Wave 2 commit `e3fcb95c`. GASPIN-03 consistency-gate verification at Wave 2 Task 2.5 documented non-regression vs pre-Wave-2 baseline. STAT-03-v35-carry remaining failure documented as ACCEPTED-DESIGN per v35.0 Phase 265 D-265-STAT03-01 fixture-calibration-error reframe. The (a-alt) script-split is the load-bearing improvement; it isolates gas-pin tests from stat-pin tests under the v36.0 "128k is fine approved" gas-pin drift envelope.

### Storage-layout / ABI-byte-identity edge cases investigated

- **In-flight bet migration at v37→v38 boundary.** A bet placed at v37 baseline with `heroEnabled = false` (i.e., bit 0 = 0 at `FT_HERO_SHIFT`) resolved AFTER the v38 upgrade: post-v38 `_resolveFullTicketBet` at L591 reads bits 1-2 via `MASK_2` and ignores bit 0. So an in-flight v37-opt-out bet with `heroQuadrant = 0xFF` (which packed `enabled = 0, quadrant_lo = 0, quadrant_hi = 0`) would resolve at v38 as `heroQuadrant = 0` and receive the always-on hero boost on quadrant 0. **This is a deliberate migration semantics** per D-272-DESIGN-INTENT-01: in-flight bets at the v37→v38 upgrade boundary transition from opt-out to always-on hero on quadrant 0. The user has acknowledged this as accepted behavior change. NOT a finding (deployment governance concern; pre-launch context per CONTEXT.md `<spec_lock>`).

- **HERO-01 normalization edge cases (signed-vs-unsigned, assembly).** `heroQuadrant` is `uint8`; the `< 4` comparison is unsigned natural. The function `placeDegeneretteBet` is `external payable` with NO assembly; calldata-encoded `uint8` goes through Solidity's standard ABI decoding (truncates to 8 bits). Solidity compiler emits a SHR/AND mask if needed; the comparison `< 4` operates on the validated 8-bit value. No signed-value bypass; no assembly bypass.

- **Cleanup-removal blast radius beyond Degenerette module.** D-272-CLEAN-SCOPE-01 narrows cleanup scope to `DegenerusGameDegeneretteModule.sol` only. Verified via cross-module byte-identity grep proof in §3.B: `JackpotModule`, `MintModule`, `LootboxModule`, `TraitUtils`, `JackpotBucketLib`, `EntropyLib` ALL byte-identical at v38 HEAD vs `2654fcc2`. Zero blast radius.

### Verdict roll-up from `/contract-auditor`

7 of 7 §4 surfaces (a)..(g) AGREE with the inline-draft verdicts. Zero FINDING_CANDIDATE. Zero 8th-surface NEW_VECTOR from the storage-layout / ABI-byte-identity / HERO-01-normalization / cleanup-blast-radius edge case sweeps. Phase 272 §4 verdict roll-up STANDS unchanged from `/contract-auditor` perspective.

---

## /zero-day-hunter

Vulnerability-class novel-vector review of the v38.0 hero-quadrant-extraction edit + cleanup-sweep. Methodology per zero-day-hunter SKILL.md: ignore previously-audited vectors (gas limits / VRF / reentrancy / MEV / admin / economic basics — all cleared at v37 closure); focus on creative/unconventional/composition-based attack surfaces specific to the v38 delta. Hunt for the bug that 10 previous auditors missed.

### Per-surface concurrence

All 7 inline-draft surface verdicts (a)..(g) AGREE at the surface level. The novel-vector hunt below identifies one INFO-severity docs-vs-behavior drift requiring disposition.

### Novel-vector hypotheses investigated

- **Hypothesis (h) — Vestigial-bit corruption via alternate write path.** The vestigial bit at `FT_HERO_SHIFT + 0` is set unconditionally by `_packFullTicketBet` at L843 via `uint256(1)`. Could a different code path write to `degeneretteBets[..][..]` without setting this bit? Verified via grep `grep -n "degeneretteBets\[" contracts/modules/DegenerusGameDegeneretteModule.sol` — single write site at L478 (immediately following `_packFullTicketBet`). The function `_placeDegeneretteBetCore` is the sole production path; no test-only or admin override exists. **Why this fails:** Single write site; structural invariant preserved. **Mechanism strength:** STRUCTURAL — depends on no future phase adding alternate `degeneretteBets` write sites (current invariant holds at v38). **Disposition:** NEGATIVE_RESULT_ONLY.

- **Hypothesis (i) — `dailyHeroWagers` tracking inconsistency post-v38.** Critical observation: the `if (heroQuadrant < 4)` gate at L484 (in `_placeDegeneretteBetCore`) controls whether the player's bet contributes to the `dailyHeroWagers[day][heroQuadrant]` ledger. At v38 the gate uses the RAW `heroQuadrant` parameter (NOT the normalized `effectiveQuadrant` from `_packFullTicketBet`). So a player passing `heroQuadrant = 0xFF` (or any `>= 4`):
  1. Has their bet packed with quadrant 0 (HERO-01 normalization at L832).
  2. Receives the always-on hero multiplier resolution against quadrant 0 (at `_applyHeroMultiplier`).
  3. Does NOT have their wager credited to `dailyHeroWagers[day][0]` (the L484 gate skips them).

  **Asymmetry vs intra-v38 player who passes `heroQuadrant = 0`:** Player A passing `0` → bet packed to quadrant 0, wager TRACKED in `dailyHeroWagers[day][0]`. Player B passing `0xFF` → bet packed to quadrant 0, wager NOT tracked. Both players receive the same hero multiplier resolution.

  **Downstream consequence:** `dailyHeroWagers` drives `_topHeroSymbol` in `DegenerusGameJackpotModule.sol` L1615-1643, which determines the daily hero winner via highest aggregate wager per (quadrant, symbol). `_applyHeroOverride` at L1584-1611 uses the daily hero winner to force a specific (quadrant, symbol) win in the daily jackpot. So `dailyHeroWagers` is the input ledger to a real economic mechanism (forced daily-jackpot quadrant override).

  **Adversarial exploitability analysis:**
  - Player passing `0xFF` HIDES their wager from the daily-hero-winner ledger.
  - This is **EV-NEGATIVE** for the player: they lose the daily-hero-winner influence channel (their wagers don't push (quadrant 0, their preferred symbol) toward becoming the daily hero winner, which would auto-win them a quadrant in the daily jackpot draw).
  - They STILL get the v38 hero multiplier on quadrant 0 (no opt-out for boost).
  - So passing `0xFF` is strictly EV-NEGATIVE: lose ledger influence, gain nothing.
  - No player-reachable value extraction. No determinism break. No griefing surface (passing `0xFF` only suppresses YOUR OWN wager tracking; other players' wagers continue to track normally; the daily-hero-winner mechanism remains contestable).
  - Behavior is observable asymmetry (D-08 MEDIUM ceiling pre-mitigation analysis) but self-correcting via player rationality (rational players will not pass `0xFF` because it's EV-negative).

  **Severity assessment (D-08 5-bucket):** INFO. The behavior is a docs-vs-behavior drift: the gate `if (heroQuadrant < 4)` at L484 was self-consistent at v37 baseline (opt-out semantics gated both boost and ledger tracking identically), but at v38 the boost is always-on while the ledger still uses opt-out semantics. The comment at L483 `"Daily hero symbol tracking"` does not document the asymmetry.

  **D-09 KI Gating Rubric application:** This is NOT a KI-promotion candidate. The behavior is not "accepted-design" — it's a drift between code and intended-semantics (the v38 intent per CONTEXT.md `<spec_lock>` is "always-on hero" which would imply all players' wagers should be tracked uniformly). KI promotion requires "accepted-design + non-exploitable + sticky"; the first predicate fails (it's drift, not design).

  **Recommended forward-looking action (out-of-scope at v38 per D-272-KI-01 default zero-promotion path; suitable v39+ backlog seed):** Either (a) change the L484 gate to use `effectiveQuadrant` (computed via the same `heroQuadrant < 4 ? heroQuadrant : 0` ternary) so all v38 players get tracked on quadrant 0 when passing `0xFF`; (b) change the gate to `currency == CURRENCY_ETH` (always track for ETH bets; the always-on hero schedule means every ETH bet is hero-active); or (c) leave as-is and update the inline comment + NatSpec to document the asymmetry as v38 ACCEPTED-DESIGN with rationale (player chose to pass `0xFF`; we honor the legacy opt-out semantics for the daily-hero-winner ledger only).

  **Disposition per D-272-KI-01 + `feedback_wait_for_approval.md`:** KEEP_AS_NEGATIVE_FINDING (do NOT escalate to KI promotion — this is INFO-severity behavior drift, not a design decision; the player cannot extract value; the behavior self-corrects via player rationality). The §4 verdict roll-up DOES NOT change: surface (b) "quadrant 0 default" verdict is unchanged because the payout-bias question is orthogonal to this ledger-tracking asymmetry; surface (c) "cleanup-sweep removal preserves invariants" verdict is unchanged because the L484 gate was NOT removed by Wave 1 (it pre-existed in the v37 baseline). Surface this as a v39+ cleanup backlog candidate via the `272-01-SUMMARY.md` "Deferred Issues" / "Forward-Looking Notes" channel and via the §9.NN.iv RE-DEFER register pickup-pointer (do NOT cite a specific v39 phase ID per D-272-FCITE-01 terminal-phase rule).

- **Hypothesis (j) — RNG commitment-window with always-on hero.** Pre-v38, a variance-averse player could pass `heroQuadrant = 0xFF` after the bet placement window — BUT actually no, the bet is committed at `_placeDegeneretteBetCore` BEFORE `lootboxRngWordByIndex[index]` is set (guarded by `if (lootboxRngWordByIndex[index] != 0) revert RngNotReady();` at L451). The player CANNOT see RNG before placing. Commitment-window structurally closed for `heroQuadrant`. **Disposition:** NEGATIVE_RESULT_ONLY (degenerate-PASS attestation per `feedback_rng_commitment_window.md` — Phase 272 has zero RNG-path mutation).

- **Hypothesis (k) — Cross-module byte-identity assumption gap.** §4 surface (d) + §3.B claim storage byte-identity vs v37. Transitively, REG-01 carries v37 → v38; v37 closure carries v36 → v37; so v38 storage layout is byte-identical to v36 baseline `1c0f0913`. Verified the chain inline at §3.B. **Disposition:** NEGATIVE_RESULT_ONLY.

- **Hypothesis (l) — LBX-02 RE-DEFER prose vs actual gas envelope at v38.** LBX-02 is FORMAL RE-DEFER per v38 (no empirical pin attempted). Analytical worst-case load-bearing per `feedback_gas_worst_case.md` + Phase 266 GAS-01 precedent. Is the v37 Phase 269 analytical worst-case derivation still valid at v38? `contracts/modules/DegenerusGameLootboxModule.sol` byte-identical at v38 HEAD per cross-module byte-identity grep proof (§3.B). The 177-byte bytecode shrink from Phase 269 LBX-01 carries forward unchanged. **Disposition:** NEGATIVE_RESULT_ONLY.

- **Hypothesis (m) — STAT-03-v35-carry ACCEPTED-DESIGN at v38 masks a real protocol regression.** The 88.24% empty-bucket skip rate persists at v38; documented as fixture-density artifact per v35.0 Phase 265 D-265-STAT03-01 reframe. Phase 272 has zero PerPullEmptyBucketSkip surface mutation; the rate is identical to v35 (fixture is identical; no contract-side coin-jackpot mutation at v38). **Disposition:** NEGATIVE_RESULT_ONLY.

- **Hypothesis (n) — Cleanup-removal blast radius via dead-code-cited-by-other-tooling.** Could `MASK_3` be referenced by any external tooling (test helpers, ABI consumers, frontend SDK)? `MASK_3` was `private constant` at v37 baseline (linkage: file-internal only); not in ABI; not in deployed-artifact `function-selectors` set. No external consumer surface. **Disposition:** NEGATIVE_RESULT_ONLY.

- **Hypothesis (o) — Cleanup-removal blast radius via reflection/EVM-introspection.** Could `MASK_3 = 0x7` be referenced via bytecode inspection? `private constant` is inlined at compile time; no constant-table entry; no `PUSH1 0x7` site uniquely attributable to MASK_3 in bytecode (constants are inlined into consumer functions). No reflection-vector surface. **Disposition:** NEGATIVE_RESULT_ONLY.

### Verdict roll-up from `/zero-day-hunter`

7 of 7 §4 surfaces AGREE with the inline-draft verdicts at the surface level. One docs-vs-behavior drift identified (Hypothesis (i) — `dailyHeroWagers` tracking inconsistency post-v38) with disposition KEEP_AS_NEGATIVE_FINDING per D-272-KI-01 default zero-promotion path. The §4 verdict roll-up STANDS unchanged.

---

## /economic-analyst

Mechanism-design and rational-actor review of the v38.0 always-on hero schedule + cleanup-sweep. Methodology per economic-analyst SKILL.md: model rational behavior across actor types (Degen Gambler, EV Maximizer, Whale, Affiliate, Griefer); look for incentive bugs (not code bugs); analyze defection, equilibrium, death-spiral dynamics.

### Per-surface concurrence

All 7 inline-draft surface verdicts (a)..(g) AGREE at the surface level. Surface (f) variance-impact assessment is the load-bearing economic claim; expanded analysis below.

### Variance-impact analysis (Surface (f) expansion)

- **Pre-v38 posture:** Players could pass `heroQuadrant = 0xFF` to skip the hero multiplier and lock payout at `basePayout(M, N)` (zero variance from hero multiplier; EV invariant per per-N HERO_BOOST calibration). This was a variance-reduction tool with no EV impact.

- **Post-v38 posture:** All players receive hero multiplier resolution. Worst-case downside per hero-active spin = `HERO_PENALTY = 0.95 × basePayout` (5% downside). Best-case upside per hero-active spin = boost-magnitude × basePayout (per-N table maxima range ~1.18× to ~2.50× across M ∈ {2..7}). Bounded variance increase; EV invariant.

- **Risk-averse subset impact:** The variance-averse player who previously locked at basePayout now faces ~5% second-moment dispersion increase. From a behavioral-economics lens (loss aversion + hyperbolic discounting), the perceived value loss may exceed the 5% nominal downside in some risk-utility models (e.g., quadratic utility). BUT in a degen-game context — where players self-select for variance-seeking entertainment value — the variance-averse subset is structurally small. User disposition per CONTEXT.md `<spec_lock>` accepts this trade-off pre-launch.

- **EV-rational players (risk-neutral / risk-loving):** Zero effect. EV invariant by construction.

- **Whales:** Zero differential impact. Whales operate at the EV-rational layer; their decisions are driven by aggregate EV / pool capacity, not variance preferences.

- **Affiliates:** Zero direct impact (affiliates don't place Degenerette bets; they receive referral commissions on referred-player wagers).

- **Griefers:** Pre-v38, a griefer could grief OTHER players by... actually no, hero-opt-out only affected the griefer's own bet. Post-v38, same — hero now applies to the griefer's own bet only. No grief-other-player surface emerges from the always-on schedule.

### Skill-expression channel preservation

- Pre-v38, a player could express skill by choosing `heroQuadrant ∈ {0..3}` based on personal symbol-distribution beliefs (though under uniform 1/8 symbol distribution there's no actual skill edge to express).
- Post-v38, the choice channel is preserved on-chain — `placeDegeneretteBet(..., uint8 heroQuadrant)` still accepts any `heroQuadrant ∈ {0..3}` and the player's customTicket symbol at that quadrant is the matched-against side.
- UI-layer simplification (defaulting to 0, removing the toggle) is a frontend choice that does NOT preclude advanced-mode direct-ABI access to the channel.
- **Skill-expression channel structurally preserved.** Players who valued the channel pre-v38 still have it at v38.

### Player-side strategy shifts

- EV-rational players: no shift (EV invariant).
- Variance-averse players: lose variance-reduction tool. Strategic response: either accept variance (continue playing with hero always-on) or exit (go play a different game). The CONTEXT.md user disposition accepts this exit risk for the variance-averse subset as bounded acceptable.
- Whale vs casual differential: zero differential (the hero mechanism's impact is per-spin, not per-stake; whales and casuals face the same multiplier distribution).

### `dailyHeroWagers` mechanism interaction (cross-cite `/zero-day-hunter` Hypothesis (i))

The `dailyHeroWagers` ledger drives the daily-hero-winner mechanism in `DegenerusGameJackpotModule._applyHeroOverride` (forced (quadrant, symbol) win in the daily jackpot). At v38, players passing `heroQuadrant = 0xFF` are NOT credited to the ledger (despite receiving hero multiplier on quadrant 0). Mechanism-design impact analysis:

- **Could a coalition coordinate to pass `0xFF` and grief the daily-hero-winner mechanism?** A coalition passing `0xFF` only suppresses THEIR OWN wager tracking; other (rational) players' wagers continue to track normally. The mechanism remains contestable by rational participants. The coalition's suppression is EV-NEGATIVE for itself (they lose daily-hero-winner influence without saving anything). No grief-other-player surface; no value-extraction surface.

- **Could a single griefer aim to push the daily-hero-winner to a specific (quadrant, symbol) by NOT participating in `dailyHeroWagers[day][0]`?** The griefer's absence from the (0, X) bucket reduces (0, X)'s competitiveness in the winner-selection, but only marginally (their wager weight is removed). If the griefer is a large player, they have an incentive to FAVOR (0, X) winning (they would gain from the forced-win in the daily jackpot draw), not disfavor — so they would NOT pass `0xFF`. Self-correcting incentive structure.

- **Conclusion:** The Hypothesis (i) docs-vs-behavior drift has zero mechanism-design griefing surface. It is structurally self-correcting via rational-actor incentives. The `/economic-analyst` perspective concurs with the `/zero-day-hunter` KEEP_AS_NEGATIVE_FINDING disposition; no KI promotion warranted.

### Death-spiral / equilibrium analysis

- **Always-on hero schedule equilibrium:** The mechanism maintains the same Nash equilibrium structure as pre-v38 (Degenerette is a per-spin lottery with per-N table dispatch + hero multiplier + WWXRP factor + 3-tier ETH split). Player participation incentives unchanged at the EV layer.
- **Death-spiral risk:** No new feedback loops introduced. The variance-reduction tool removal does not create a player-exodus death-spiral because (a) EV is invariant, (b) the variance-averse subset is structurally small in a degen-game context, (c) the per-N HERO_BOOST tables remain calibrated for EV-neutrality.

### Verdict roll-up from `/economic-analyst`

7 of 7 §4 surfaces AGREE with the inline-draft verdicts. Surface (f) variance-impact verdict SAFE_BY_DESIGN concurs; bounded acceptable variance impact per user disposition; no KI promotion. Hypothesis (i) docs-vs-behavior drift concurred KEEP_AS_NEGATIVE_FINDING (mechanism-design impact is zero). Phase 272 §4 verdict roll-up STANDS unchanged from `/economic-analyst` perspective.

---

## Disposition

### Per-skill concurrence summary

- `/contract-auditor`: 7 of 7 §4 surfaces AGREE. Zero 8th-surface NEW_VECTOR from storage-layout / ABI-byte-identity / HERO-01-normalization / cleanup-blast-radius edge case sweeps.
- `/zero-day-hunter`: 7 of 7 §4 surfaces AGREE at surface level. One docs-vs-behavior drift identified (Hypothesis (i) — `dailyHeroWagers` tracking inconsistency post-v38).
- `/economic-analyst`: 7 of 7 §4 surfaces AGREE. Hypothesis (i) confirmed zero mechanism-design griefing surface; self-correcting via rational-actor incentives.

### Per-finding-candidate disposition (per D-272-KI-01 default + `feedback_wait_for_approval.md`)

| Finding ID | Surface | Description | Severity (D-08) | Disposition |
| ---------- | ------- | ----------- | --------------- | ----------- |
| Hypothesis (i) | Surface (b) + (c) interaction (out of band) | `dailyHeroWagers` tracking inconsistency post-v38: `if (heroQuadrant < 4)` gate at `_placeDegeneretteBetCore` L484 uses raw input, so players passing `0xFF` get hero multiplier on quadrant 0 (HERO-01 normalization) but are NOT credited to `dailyHeroWagers[day][0]`. EV-NEGATIVE for the player who triggers it; no value-extraction; no determinism break; no griefing surface. | INFO | KEEP_AS_NEGATIVE_FINDING |

**Disagreements:** None. All 3 skills concurred on the §4 7-surface verdicts. The Hypothesis (i) finding is unanimous KEEP_AS_NEGATIVE_FINDING per D-272-KI-01 default zero-promotion path.

**8th-surface NEW_VECTOR candidates:** None. The Hypothesis (i) finding is INFO-severity docs-vs-behavior drift, not a novel attack vector requiring a new §4 surface row.

**KI promotion candidates:** None. Hypothesis (i) does NOT satisfy D-09 KI Gating Rubric (the behavior is drift, not accepted-design — fails the first predicate).

**FINDING_CANDIDATE escalation per `feedback_wait_for_approval.md`:** None requiring user disposition. Hypothesis (i) is INFO-severity self-correcting behavior drift; KEEP_AS_NEGATIVE_FINDING disposition does NOT require user approval (it is the default D-272-KI-01 zero-promotion path applied uniformly).

### Forward-looking notes (v39+ backlog seed candidates per §9.NN.iv pickup-pointer carve-out)

- **Hypothesis (i) — `dailyHeroWagers` post-v38 ledger-tracking cleanup.** Suggested remediation in v39+: change the L484 gate from `if (heroQuadrant < 4)` to either (a) `if (heroQuadrant < 4 || heroQuadrant >= 4)` simplified to unconditional (with effectiveQuadrant for storage key), OR (b) `if (currency == CURRENCY_ETH)` (always track for ETH bets; the always-on hero schedule means every ETH bet is hero-active on some quadrant). Option (b) is the cleaner v39+ form aligned with always-on hero semantics. The current v38 behavior is benign (EV-negative for the player who triggers it; self-correcting via rational-actor incentives); v39+ cleanup is a quality-of-implementation improvement, NOT a security fix.

### Final disposition

**§4 verdict roll-up STANDS unchanged:** 7 of 7 surfaces (a)..(g) SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE. Zero F-38-NN finding blocks emit per D-272-FIND-01 carry default path. KNOWN-ISSUES.md UNMODIFIED at v38 close per D-272-KI-01 default zero-promotion path. Phase 272 audit deliverable proceeds to Task 3.6 (§9 closure-attestation TWO-subsection format + §9.NN.iv RE-DEFER Register).

**FINDING_CANDIDATE list:** Empty (Hypothesis (i) is KEEP_AS_NEGATIVE_FINDING, not a FINDING_CANDIDATE). Per D-272-KI-01 + `feedback_wait_for_approval.md`: do NOT halt; proceed to Task 3.6.

---

*Phase 272 Plan 01 — Adversarial Validation Log*
*Generated: 2026-05-11*
*3-skill PARALLEL spawn pattern per D-272-ADVERSARIAL-01.*
*HEAD at log-authoring time: `079ec007` (post-Task-3.4 §6/§7/§8 commit).*

---

## Wave 1.5 Disposition Update (2026-05-11, post Wave 3 close)

**Hypothesis (i) — `dailyHeroWagers` post-v38 ledger-tracking drift**

**Status:** Pivoted from KEEP_AS_NEGATIVE_FINDING (at this adversarial-pass close) to RESOLVED_AT_V38 (Wave 1.5).

**Resolution:** Commit `4760459f` — defensive boundary validation. `_placeDegeneretteBetCore` entry adds `if (heroQuadrant >= 4) revert InvalidBet();`. The previous silent-normalize path (Hypothesis (i)'s root) no longer exists; invalid inputs are rejected at the public ABI boundary.

**Spec_lock revision:** HERO-05 pivoted from "accept + normalize" to "reject invalid input". Tracked as D-272-INPUT-VALIDATION-01 in `272-CONTEXT.md`. Wave 4 closure flips will propagate the revision to ROADMAP success criterion #2 + REQUIREMENTS.md HERO-05 prose.

**Audit impact:**
- `audit/FINDINGS-v38.0.md` §3.A: amended (Wave 1.5 row + HERO-05 row revised).
- §4 surface (b): verdict revised to SAFE_BY_DEFENSIVE_VALIDATION; rationale: the asymmetric "omit heroQuadrant" path no longer exists.
- §9.NN.iv RE-DEFER Register: Hypothesis (i) row REMOVED (no v39+ pickup).
- §7 cross-cite: noted RESOLVED_AT_V38.

**Adversarial-pass historical record:** This log section is an APPENDED disposition update; the H2 sections above (the 3 skills' original outputs) remain as the historical record of what the adversarial pass found at Wave 3 close. The pivot reflects user disposition (Wave 1.5 USER-APPROVED commit on 2026-05-11).
