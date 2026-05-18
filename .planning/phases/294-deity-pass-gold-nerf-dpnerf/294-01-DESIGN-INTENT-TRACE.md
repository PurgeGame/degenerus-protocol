# Phase 294 DPNERF — Design-Intent Trace (DPNERF-06)

> Per `feedback_design_intent_before_deletion.md`: this trace records the original design intent of the code-shape Plan 02 is about to restructure, BEFORE the contract patch lands. The artifact is the AGENT-COMMITTED pre-patch gate. Plan 02 cannot begin its contract-edit task until this file exists alongside `294-01-MEASUREMENT.md` at the paths in Plan 01 `files_modified`.
>
> History is allowed in THIS file because the trace IS a planning artifact whose purpose is to record historical rationale for v41 → v42 changes. The `feedback_no_history_in_comments.md` rule applies to NatSpec / contract source comments only — it does NOT apply to planning docs.

## Audit Baseline + Anchors

**Audit baseline:** `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` (v41.0 closure HEAD; v42.0 milestone open against v41 close per `D-42N-MILESTONE-OPEN-01`). All "v41 close" references in this trace, and all "byte-identical to v41 close" assertions in `294-01-MEASUREMENT.md`, resolve against this SHA.

**Intermediate anchor:** Phase 292 close — the most-recent v42 surface phase already attesting zero storage / ABI delta vs v41 (Phase 290 MINTCLN + Phase 292 HRROLL both shipped with byte-identical storage layout + public-ABI selectors vs v41 close per their respective MEASUREMENT.md attestations). Phase 294 DPNERF inherits and re-attests on top of that chain.

**Phase 294-scope decision anchors (5 anchors; user dispositions recorded 2026-05-17):**

- **D-42N-GOLD-FLOOR-01** — gold-tier (`color == 7`) `_randTraitTicket` deity virtual entries set to flat 1 (no `len / 50` scaling; no min-2 floor). Common-tier (`color ∈ [0..6]`) `virtualCount = max(len/50, 2)` UNCHANGED. (User-locked 2026-05-17 per `.planning/ROADMAP.md` line 41 + lines 197-210.)
- **D-42N-DEITY-EV-01** — intentional EV reduction with NO common-tier compensation. Deity-pass holders earn strictly less total EV across all 8 colors than at v41; commons stay at v41 weight. Not a constant-EV rebalance, not a commons-bump, not a rebias-toward-commons. (User-locked 2026-05-17.)
- **D-42N-PATH-COVERAGE-01** — both ETH and BURNIE near-future coin jackpot paths covered by the single function-body change in `_randTraitTicket`; no callsite flag, no path-discrimination parameter, no per-path duplication of the function body. (User-locked 2026-05-17.)
- **D-294-CALLER-UNIFORM-01** — extension of `D-42N-PATH-COVERAGE-01` recorded at planner-time per CONTEXT.md `<decisions>`: ALL 4 `_randTraitTicket` callsites are covered uniformly by the single function-body change. The roadmap text names only "ETH + BURNIE coin jackpot paths" but the literal scope of the body change reaches: (i) **L698 `_runEarlyBirdLootboxJackpot`** — early-bird lootbox jackpot trait winners (3% of `futurePrizePool` at `lvl+1`; 100 winners across 4 traits = 25/trait); (ii) **L988 `_distributeTicketsToBucket`** (helper invoked by `_distributeTicketJackpot` from L637 daily-tickets / L652 carryover-tickets / L883 early-bird-post-purchase-tickets); (iii) **L1296 `_processDailyEth`** — daily ETH jackpot trait winners (the roadmap-named `_runJackpotEthFlow` path resolves through here: `_runJackpotEthFlow` L1142 → `_processDailyEth` L1232 → `_randTraitTicket` L1296); (iv) **L1399 `_resolveTraitWinners`** — ETH trait-winner resolution sub-flow. The BURNIE near-future coin jackpot path resolves via `payDailyCoinJackpot` (L1767) → `_awardDailyCoinToTraitWinners` (L1816+) → trait-bucket sampling → `_randTraitTicket` (the same function-body change applies by construction). (Planner-locked 2026-05-17 per CONTEXT.md.)
- **D-294-NATSPEC-01** — locked exact 5-line two-tier `what IS` comment block shape at L1721-1723: line 1 "Virtual deity entries (if a deity exists for this symbol):"; line 2 "  Gold tier (color == 7): flat 1 virtual entry."; line 3 "  Common tier (color in [0..6]): floor(2% of bucket), minimum 2."; line 4 "traitId layout: (quadrant << 6) | (color << 3) | symIdx"; line 5 "fullSymId = quadrant * 8 + symIdx". ZERO history language ("previously", "v41 used to", "was max(len/50, 2)"). ZERO decision-anchor citations in source comments (no `// D-42N-GOLD-FLOOR-01` / `// DPNERF-01` / `// Phase 294` markers). (Planner-locked 2026-05-17 per CONTEXT.md + `feedback_no_history_in_comments.md`.)

**Carry-forward anchors (load-bearing context; do NOT re-derive):**

- **D-42N-MILESTONE-OPEN-01** (v42) — v42.0 milestone open at v41 close HEAD `315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4`.
- **D-281-FIX-SHAPE-01** (v41 Phase 281) — owed-salt cross-call seed-separation pattern. CITED FOR COMPLETENESS only — DPNERF does NOT touch the mint-batch determinism path; the `_randTraitTicket` consumer's `randomWord` source (raw VRF payload via `_rollWinningTraits`) is unaffected.
- **D-288-FIX-SHAPE-01** (v41 Phase 288) — `dailyIdx` structural anchor as single-writer day-key. CITED FOR COMPLETENESS only — DPNERF does NOT touch the hero-override day-index path; the gold-tier branch is purely a `virtualCount` allocation change inside `_randTraitTicket`.
- **D-271-ADVERSARIAL-01 + D-271-ADVERSARIAL-03** (v34 Phase 271) — Phase 296 SWEEP performs the combined 3-skill PARALLEL adversarial pass over MINTCLN + HRROLL + DPNERF together. DPNERF is NOT red-teamed in isolation at Phase 294. Per `D-294-CALLER-UNIFORM-01`, the SWEEP hypothesis surface MUST cover all 4 callsites, not just the 2 paths named in the roadmap.
- **D-271-ADVERSARIAL-02** (v34) — `/degen-skeptic` OUT OF SCOPE. Carry-forward to Phase 296.

## Section (i) — Original `virtualCount = len / 50; if (virtualCount < 2) virtualCount = 2` Rationale

Per DPNERF-06(i): trace WHY the v41 design used 2% of bucket with a min-2 floor for deity virtual entries.

The pre-patch shape at `contracts/modules/DegenerusGameJackpotModule.sol:1729-1731` (inside the `if (deity != address(0))` block of `_randTraitTicket`) is:

```
virtualCount = len / 50;
if (virtualCount < 2) virtualCount = 2;
```

with the inline NatSpec at L1721-1723 reading:

```
// Virtual deity entries: floor(2% of bucket tickets), minimum 2, if a deity exists for this symbol.
// traitId layout: (quadrant << 6) | (color << 3) | symIdx
// fullSymId = quadrant * 8 + symIdx
```

The v41 design intent was: deity-pass holders earn a structural "skim" on top of the trait-bucket ticket distribution. The skim size scales with the bucket — `len / 50` = 2% of the bucket's ticket population — so the deity's expected share of the bucket grows proportionally with the bucket's total bet activity. The 2% magnitude was selected as a meaningful but not-dominant deity share: large-bucket EV is still primarily distributed among the organic ticket holders.

The `if (virtualCount < 2) virtualCount = 2;` floor exists to guarantee a baseline payout to the deity on small buckets. Without the floor, small buckets would round `len / 50` to 0 (for `len < 50`) or 1 (for `len ∈ [50, 99]`), making deity ownership economically marginal on the lower-activity (quadrant × color × symbol) slots. Deity ownership represents a non-trivial capital commitment (the deity-pass purchase price at v41 close, gated by `DEITY_PASS_BASE`); under-rewarding the deity on small buckets would erode the holder's incentive to retain the pass across the daily-jackpot cycle, leading to secondary-market price collapse and an under-utilized deity surface.

Critically, the v41 design treated all 8 colors **uniformly** — no per-tier differentiation. The 2% + min-2 floor was applied identically across the (quadrant × color × symbol) trait space regardless of the bucket's natural size. The trait-byte layout `(quadrant << 6) | (color << 3) | symIdx` semantically distinguishes 8 colors, with color 7 (gold) being the rarest tier; but the v41 `_randTraitTicket` body did not differentiate the virtual-entry allocation by color. This uniformity is the design property the DPNERF nerf intentionally breaks.

The v41 `virtualCount = max(len/50, 2)` shape was **NOT a defect** — it was a constraint-satisfying design at v41 design time: deity-pass holders received a meaningful EV share scaled to bucket activity, with a structural floor protecting their downside on low-activity slots. The v42 DPNERF nerf is a **player-economy rebalance**, not a defect remediation — it intentionally reshapes the deity EV curve to address the gold-tier concentration issue documented in §(ii).

## Section (ii) — Gold-Tile Concentration Issue

Per DPNERF-06(ii): explain the disproportionate-reward issue the DPNERF nerf addresses.

The trait-byte layout `(quadrant << 6) | (color << 3) | symIdx` partitions the trait space into 4 quadrants × 8 colors × 8 symbols = 256 trait IDs. Color 7 is gold per the canonical mapping documented at `contracts/DegenerusTraitUtils.sol:50,97,112,214` (`scaled == 14 → gold (color 7)`) and reaffirmed in the gold-tier idiom at `contracts/modules/DegenerusGameJackpotModule.sol:1105` (`if (((traits[i] >> 3) & 7) == 7)` in `_pickSoloQuadrant`) + `contracts/modules/DegenerusGameDegeneretteModule.sol:854-859` (`Counts gold (color == 7) quadrants in a packed ticket. Color tier occupies bits 5-3 of each per-quadrant byte; gold is the highest...`).

Gold-tier traits sit in the **smallest bucket tier** across the trait-byte layout: organic player betting concentrates on the higher-frequency common-color slots, leaving gold-tier buckets structurally smaller (the gold rarity-weighting both in the visible UI and in the underlying entropy distribution naturally produces smaller bet pools on gold slots). The `dailyHeroWagers` and ticket-distribution pipelines that ultimately feed `traitBurnTicket_[trait]` (the `holders` array at `_randTraitTicket` L1719) reflect this organic concentration.

On a small gold bucket, the v41 formula behaves disproportionately:

- For a gold-bucket with `len = 30` tickets: `len / 50 = 0`; the min-2 floor kicks in; `virtualCount = 2`; deity-win probability = `2 / (30 + 2) ≈ 6.25%` per winner-slot.
- For a gold-bucket with `len = 50` tickets: `len / 50 = 1`; the min-2 floor kicks in; `virtualCount = 2`; deity-win probability = `2 / (50 + 2) ≈ 3.85%` per winner-slot.
- For a common-color bucket with `len = 500` tickets: `len / 50 = 10`; floor inactive; `virtualCount = 10`; deity-win probability = `10 / (500 + 10) ≈ 1.96%` per winner-slot.

The v41 design intended `~2%` deity share uniformly; on small gold buckets, the min-2 floor pushes the actual deity-win probability to 3-7% — a 1.5-3× over-extraction on the smallest tier. The over-extraction compounds across the 4 ETH + 4 BURNIE coin-jackpot trait-winner selections per day: deity owners systematically over-extract on gold-tier wins relative to their 2%-target share across the daily cycle.

The DPNERF fix shrinks the gold-tier deity allocation to a **flat 1 virtual entry** (eliminating the floor escalation on small gold buckets while preserving a meaningful deity participation). On the same gold-bucket examples above:

- `len = 30` gold: `virtualCount = 1`; deity-win probability = `1 / (30 + 1) ≈ 3.23%` (was 6.25% → ~−48%).
- `len = 50` gold: `virtualCount = 1`; deity-win probability = `1 / (50 + 1) ≈ 1.96%` (was 3.85% → ~−49%).

Common-color buckets remain UNCHANGED at v41 `max(len/50, 2)` per `D-42N-DEITY-EV-01`. The nerf is **surgical on gold** — it touches only the tier that exhibited the concentration, and does not perturb common-color economics.

## Section (iii) — Compensation Trade-Offs

Per DPNERF-06(iii): enumerate the 3 alternatives considered at user-disposition time on 2026-05-17 + the locked outcome.

**(a) Keep total EV constant via commons-bump — REJECTED.** Boost the common-tier `virtualCount` to compensate for the gold-tier reduction (e.g., commons floor changes from min-2 to min-3, or commons formula shifts from `len/50` to `len/40`). The intent: keep the total daily deity EV across the (quadrant × color × symbol) space approximately constant, just rebalanced away from gold-tier wins. Rejected because: (1) it complicates the post-patch comment block (would require enumerating the commons-bump magnitude as well as the gold-tier flat-1); (2) it increases the bytecode delta (two algebraic branches plus a tuning constant for the new commons formula); (3) it introduces a coupled-pair-of-tunings rather than a single targeted nerf — the audit story becomes "we nerfed gold AND we boosted commons" instead of the cleaner "we nerfed gold"; (4) it requires its own decision anchor for the commons-bump magnitude, which the user did not request and which would re-open the commons-tier balance the v41 design already settled.

**(b) Intentional reduction — LOCKED per `D-42N-DEITY-EV-01`.** Gold-tier `virtualCount = 1` (no scaling, no floor); commons `virtualCount = max(len/50, 2)` UNCHANGED. Net result: deity-pass holders earn strictly less total EV across all 8 colors than at v41 close; no rebalance toward commons; no compensating-bump anywhere. Selected because it is the minimum-surface change matching the user's stated intent — "deity earns less total EV across all 8 colors" per CONTEXT.md `<decisions>` — and produces the cleanest audit-story (single decision anchor, single bytecode branch, single comment-block rewrite). The total deity EV across the daily cycle is reduced by approximately the magnitude of the gold-tier over-extraction documented in §(ii); the secondary-market deity-pass price equilibrium adjusts to the reduced EV expectation rather than being artificially propped up by a commons-bump.

**(c) Intentional rebias-toward-commons — REJECTED.** Boost the commons floor AND nerf gold simultaneously, with a net shift of deity EV toward common-color wins (not just constant-EV like alternative (a), but deliberately shifted). Explicitly different from (a) because (c) aims to make deity-pass holders earn relatively MORE on commons than at v41, balanced against the gold-tier reduction. Rejected because: (1) it goes beyond the targeted gold nerf and would require its own decision anchor + economic-model surface that wasn't requested by the user; (2) it would change the v41 commons-tier economics the user did not flag as in-scope; (3) it would require Phase 295 TST-DPNERF + Phase 296 SWEEP to test a much larger surface than the locked targeted-nerf scope.

**Cross-reference (SWEEP-02(iii) pre-emptive answer):** the user explicitly accepts that secondary-strategy shifts may occur under alternative (b). Deity-pass holders may pivot to non-gold gameplay strategies once the gold-tier EV is reduced — this is treated as Phase 296 SWEEP discovery space, NOT a Phase 294 in-scope mitigation. The intentional EV reduction is the user's stated outcome per `D-42N-DEITY-EV-01`; downstream player game-theory adjustments are accepted as a feature of the nerf, not a bug.

## Section (iv) — Path-Coverage Trade-Offs

Per DPNERF-06(iv): enumerate the 3 alternatives considered at user-disposition time on 2026-05-17 + the locked outcome.

**(a) ETH-only — REJECTED.** Apply the gold nerf only at the ETH jackpot path (`_processDailyEth` L1296 + `_resolveTraitWinners` L1399); leave the BURNIE near-future coin jackpot path + the early-bird lootbox path + the carryover-ticket-distribution path on the v41 `max(len/50, 2)` formula. Rejected because: (1) it would require either a callsite flag on `_randTraitTicket` (additional parameter; ABI-deviating in spirit even if not in surface) or a path-discrimination predicate inside the function body (e.g., a thread-local "am I being called from the ETH path?" flag — structurally impossible in EVM without external state), or a duplicated `_randTraitTicket` body for the BURNIE path with its own gold branch (doubling the audit surface); (2) it would create a differential-behavior vector that Phase 296 SWEEP would have to attest as intentional rather than accidental; (3) it would mean deity-pass holders continue extracting un-nerfed gold EV through the non-ETH paths, partially defeating the `D-42N-DEITY-EV-01` "deity earns less total EV across all 8 colors" intent.

**(b) Both ETH + BURNIE paths symmetric — STRICT SUBSET of (c).** This is the literal roadmap framing — apply the nerf to both jackpot-class paths via the single function-body change. The function-body change does in fact reach both paths by construction (single `_randTraitTicket` body, no callsite flag). Selected as a literal interpretation of the roadmap text, but (c) is the more precise framing of the actual code-reach.

**(c) All-callsite-uniform across BOTH virtualCount surfaces — LOCKED per `D-294-CALLER-UNIFORM-01` + `D-294-BURNIE-INLINE-01`.** Plan 01 framed this as "single `_randTraitTicket` body change reaches all 4 callsites + the BURNIE path by construction." Plan 02 verification proved the BURNIE clause wrong: `_awardDailyCoinToTraitWinners` (L1822-1906) does NOT call `_randTraitTicket`. It inlines its own `virtualCount = len/50; if (virtualCount < 2) virtualCount = 2;` at L1864-1867. The DPNERF nerf therefore lands on **two virtualCount surfaces**, not one:

**Surface A — `_randTraitTicket` body (4 callsites, ETH paths):**
- Callsite 1 — `_runEarlyBirdLootboxJackpot` at L698: early-bird lootbox jackpot trait winners (3% of `futurePrizePool` at `lvl+1`; 100 winners across 4 traits = 25/trait).
- Callsite 2 — `_distributeTicketsToBucket` (helper) at L988: trait-bucket ticket winner selection invoked by `_distributeTicketJackpot` from L637 daily-tickets / L652 carryover-tickets / L883 early-bird-post-purchase-tickets.
- Callsite 3 — `_processDailyEth` at L1296: daily ETH jackpot trait winners. `_runJackpotEthFlow` L1142 → `_processDailyEth` L1232 → `_randTraitTicket` L1296.
- Callsite 4 — `_resolveTraitWinners` at L1399: ETH trait-winner resolution sub-flow.

**Surface B — `_awardDailyCoinToTraitWinners` inline block (1 callsite, BURNIE path):**
- BURNIE near-future coin jackpot: `payDailyCoinJackpot` (L1773, `external`) → `_awardDailyCoinToTraitWinners` (L1822, `private`) → inline `virtualCount` block at L1864-1867. The BURNIE flow is a multi-bucket / 1-winner-per-iteration sampler (each iteration picks a random `lvlPrime ∈ [minLevel, maxLevel]`, then samples 1 winner from `traitBurnTicket[lvlPrime][trait_i]`). This shape is architecturally incompatible with `_randTraitTicket`'s signature `(address[][256] storage traitBurnTicket_, uint8 trait, uint8 numWinners, ...)` (single-bucket / N-winner / aggregated-return). The inline duplication of the virtualCount business rule is therefore deliberate, not accidental.

DPNERF applies the **same** gold-tier branch shape at both surfaces:
```solidity
if (deity != address(0)) {
    if (((trait_* >> 3) & 7) == 7) {   // trait at L1732; trait_i at L1865
        virtualCount = 1;
    } else {
        virtualCount = len / 50;
        if (virtualCount < 2) virtualCount = 2;
    }
}
```

Selected because: (1) it matches REQUIREMENTS.md DPNERF-03 framing "deity earns less total EV across all 8 colors" — the "total EV" measure would not hold if the BURNIE surface (or any of the 4 ETH callsites) leaked un-nerfed gold EV; (2) it matches the roadmap's "no callsite flag or path-discrimination logic" wording — the branch lives at the virtualCount-computing surface, not at the call sites of those surfaces; (3) it preserves the minimum-surface principle within each surface (no callsite plumbing on either side); (4) it acknowledges the architectural reality that BURNIE is its own surface rather than forcing a fictional "by construction" cover-up.

Phase 296 SWEEP coverage extends from the roadmap's "ETH vs BURNIE differential-behavior" hypothesis to "all-5-surface uniformity attestation (4 `_randTraitTicket` callsites + 1 `_awardDailyCoinToTraitWinners` inline) + incentive-shift across early-bird lootbox + carryover-ticket-distribution paths". SWEEP must additionally grep the contract for any OTHER `virtualCount = len / 50` inline duplication that Plan 01 may have missed (verified at Plan 02 close: zero other instances exist in `DegenerusGameJackpotModule.sol`; the only two are the patched surfaces). Phase 297 §3.A delta-surface table cites all 5 surfaces by line number under the DPNERF row.

**Plan 01 vs Plan 02 reconciliation:** the `<canonical_refs>` block earlier in this doc and the `D-294-CALLER-UNIFORM-01` entry above contain the planner-time "by construction" framing. Both are superseded by this section's 5-surface enumeration. They are left as-written for historical traceability — the Plan 02 surface table in `294-01-MEASUREMENT.md` §3 + this §(iv) section are the authoritative shape.

## Decision Anchors (Full Restatement)

| Anchor | Disposition | Source |
|---|---|---|
| `D-42N-GOLD-FLOOR-01` | Gold-tier (`color == 7`) `virtualCount = 1` (flat); commons (`color ∈ [0..6]`) `virtualCount = max(len/50, 2)` UNCHANGED | User-locked 2026-05-17 per ROADMAP.md lines 197-210 |
| `D-42N-DEITY-EV-01` | Intentional total-EV reduction; no common-tier compensation; commons-bump + rebias-toward-commons alternatives REJECTED | User-locked 2026-05-17 per ROADMAP.md lines 197-210 |
| `D-42N-PATH-COVERAGE-01` | Single function-body change reaches BOTH ETH and BURNIE near-future coin jackpot paths; no callsite flag; no path-discrimination logic; ETH-only alternative REJECTED | User-locked 2026-05-17 per ROADMAP.md lines 197-210 |
| `D-294-CALLER-UNIFORM-01` | Extension of PATH-COVERAGE: ALL 4 `_randTraitTicket` callsites (L698 + L988 + L1296 + L1399) uniform by construction; Phase 296 SWEEP hypothesis surface extended from "ETH vs BURNIE" to "all-callsite uniformity + early-bird-lootbox / carryover-ticket-distribution incentive shifts" | Planner-locked 2026-05-17 per CONTEXT.md `<decisions>` |
| `D-294-NATSPEC-01` | Locked 5-line two-tier `what IS` comment shape at L1721-1723 (Gold flat 1; Common floor(2%) min 2); ZERO history language; ZERO decision-anchor citations in source comments. Same comment shape applied at `_awardDailyCoinToTraitWinners` L1864 ahead of the inline gold-tier branch (added per `D-294-BURNIE-INLINE-01`). | Planner-locked 2026-05-17 per CONTEXT.md `<decisions>` + `feedback_no_history_in_comments.md` |
| `D-294-BURNIE-INLINE-01` | Gap-closure anchor recorded after Plan 02 verification proved the Plan 01 call-graph claim wrong. `_awardDailyCoinToTraitWinners` (L1822-1906) does NOT call `_randTraitTicket`; it inlines its own `virtualCount = len/50; if (virtualCount < 2) virtualCount = 2;` at L1864-1867 because the BURNIE flow is a multi-bucket / 1-winner-per-iteration sampler architecturally incompatible with `_randTraitTicket`'s single-bucket / N-winner signature. The DPNERF gold-tier nerf is therefore applied as a parallel +4/-2 source delta at L1864-1867 mirroring the `_randTraitTicket:1732-1737` patch. Both surfaces carry the same locked branch shape. The Plan 01 "by construction" reach-claim is retracted; the 5-surface enumeration in §3 of MEASUREMENT supersedes. | Verifier-surfaced 2026-05-18; user-locked 2026-05-18 |

Source-of-truth note: all five anchors are recorded in CONTEXT.md `<decisions>` and re-stated in Plan 01 `must_haves.truths`. The three roadmap-locked anchors (GOLD-FLOOR-01, DEITY-EV-01, PATH-COVERAGE-01) trace back to `.planning/ROADMAP.md` line 41 (Phase 294 entry) and lines 197-210 (Phase 294 detail block). The two planner-locked sub-anchors (CALLER-UNIFORM-01, NATSPEC-01) are recorded at CONTEXT.md and inherited by Plan 02 without re-derivation.

## Out-of-Scope Register (NOT touched by Phase 294 per REQUIREMENTS.md lines 22-27 + CONTEXT.md `<code_context>` Out-of-Scope Source-Tree Surfaces)

| # | Item | Disposition |
|---|---|---|
| (a) | DPNERF common-tier compensation | OUT-OF-SCOPE per `D-42N-DEITY-EV-01` (REQUIREMENTS.md line 22); common-tier `virtualCount = max(len/50, 2)` UNCHANGED in the `else` branch of the post-patch shape; not addressed by Plan 02. |
| (b) | Storage-layout changes | OUT-OF-SCOPE per DPNERF-04 + REQUIREMENTS.md line 23; single-function `_randTraitTicket` body change; zero new storage slots; zero new mappings; zero new SSTORE callsites; zero new SLOAD callsites in DPNERF scope (the `deityBySymbol[fullSymId]` SLOAD at pre-patch L1728 is UNCHANGED in count, slot, type); not addressed by Plan 02. |
| (c) | Public ABI changes | OUT-OF-SCOPE per DPNERF-05 + REQUIREMENTS.md line 24; `_randTraitTicket` is `private`; all 4 caller signatures + parameter types + return shapes UNCHANGED; `payDailyCoinJackpot` (the only `external` entry within 2 hops at L1767) signature UNCHANGED; not addressed by Plan 02. |
| (d) | `_pickSoloQuadrant` (L1080-1130) | OUT-OF-SCOPE — adjacent gold-tier code path (picks among gold-quadrants when multiple winning traits are gold); orthogonal to `_randTraitTicket`'s deity-virtual-count behavior; byte-identical post-patch attestation required in `294-01-MEASUREMENT.md` §2; not addressed by Plan 02. |
| (e) | `DegenerusGameDegeneretteModule.sol` boon distribution `BP_DEITY_PASS_TIER_SHIFT` flow | OUT-OF-SCOPE per REQUIREMENTS.md line 25; boon-distribution-for-deity-pass-holders surface UNCHANGED; not addressed by Plan 02. |
| (f) | `DegenerusGameWhaleModule.sol` deity-pass purchase pricing `DEITY_PASS_BASE` | OUT-OF-SCOPE per REQUIREMENTS.md line 26; deity-pass purchase economics UNCHANGED; not addressed by Plan 02. |
| (g) | `DegenerusDeityPass.sol` soulbound NFT minting | OUT-OF-SCOPE per REQUIREMENTS.md line 27; soulbound NFT minting UNCHANGED; not addressed by Plan 02. |
| (h) | `DegenerusGameBoonModule.sol` boon distribution flow | OUT-OF-SCOPE per REQUIREMENTS.md line 25 (boon distribution carve-out includes the boon module proper); boon distribution flow UNCHANGED; not addressed by Plan 02. |
| (i) | `DegenerusGameStorage.sol` storage declarations | OUT-OF-SCOPE per DPNERF-04; zero storage layout changes; not addressed by Plan 02. |
| (j) | `IDegenerusGameModules.sol` interface declarations | OUT-OF-SCOPE per DPNERF-05; zero public ABI changes; not addressed by Plan 02. |
| (k) | `test/` tree | OUT-OF-SCOPE at Phase 294; zero `test/` mutations; TST-DPNERF-01..05 ships at Phase 295; not addressed by Plan 02. |
| (l) | `KNOWN-ISSUES.md` | OUT-OF-SCOPE per CONTEXT.md `<decisions>` Claude's-Discretion disposition (mirrors D-281-KI-01 + D-291-KI-01 + D-293-STALE-VIEW-01 pattern for surface-mutation phases); UNMODIFIED; not addressed by Plan 02. |
| (m) | `audit/FINDINGS-v42.0.md` | OUT-OF-SCOPE — does not yet exist; closure-flip happens at Phase 297 terminal phase; not addressed by Plan 02. |
| (n) | `GOLD_COLOR = 7` named constant | OUT-OF-SCOPE per `feedback_frozen_contracts_no_future_proofing.md`; magic-7 is well-established (10+ source citations across `DegenerusTraitUtils.sol:50,97,112,185,193,194,214` + `DegenerusGameDegeneretteModule.sol:854,855` + `DegenerusGameJackpotModule.sol:1089,1105`); not introduced; not addressed by Plan 02. |
| (o) | `uint8 color = (trait >> 3) & 7;` local-variable cache | OUT-OF-SCOPE per Claude's Discretion (CONTEXT.md `<decisions>`); gold-tier check fires once per `_randTraitTicket` invocation (not in a hot loop); inline expression has identical bytecode cost; precedent at L1105 uses inline; not introduced; not addressed by Plan 02. |
| (p) | Decision-anchor citation in source comments | OUT-OF-SCOPE per `D-294-NATSPEC-01` + `feedback_no_history_in_comments.md`; audit-decision IDs live in `.planning/` artifacts + `audit/FINDINGS-v42.0.md`, not in source; not addressed by Plan 02. |
| (q) | NatSpec change at `_randTraitTicket` function-level docstring (L1706) | OUT-OF-SCOPE per CONTEXT.md `<decisions>` Claude's-Discretion; function-level docstring (`/// @dev Selects random winners from a trait's ticket pool, returning both addresses and indices.`) UNCHANGED; only the inline virtual-entry comment block at L1721-1723 changes per `D-294-NATSPEC-01`; not addressed by Plan 02. |

## SWEEP-02(iii) DPNERF Adversarial-Hypothesis Pre-Emptive Answers

Per `D-294-CALLER-UNIFORM-01` SWEEP-scope expansion: pre-emptively address the Phase 296 SWEEP DPNERF hypotheses so Phase 296's 3-skill PARALLEL adversarial pass has a baseline disposition record to test against.

**Hypothesis 1: All-4-callsite uniformity — does the gold nerf produce any incentive shift in the early-bird lootbox path (callsite L698) where deity-pass holders might game the lootbox window differently than the daily-jackpot window?** Pre-emptive answer: the early-bird lootbox window operates at `lvl+1` distributing 3% of `futurePrizePool` to 100 winners across 4 traits (25/trait). A deity-pass holder could in principle delay deity-pass acquisition to align with high-`futurePrizePool` levels for non-gold trait wins (where the commons floor preserves their v41-EV expectation) while skipping levels where the projected winning traits skew gold-heavy (where the nerf reduces their gold-tier EV). This is a player-strategy shift expressing the intentional EV reduction in deity-pass-acquisition timing, not an exploit — the mechanic accepts intentional EV reduction on gold per `D-42N-DEITY-EV-01`. The lootbox window mechanic itself is UNCHANGED. Expected Phase 296 disposition: **SAFE_BY_DESIGN**.

**Hypothesis 2: Carryover-ticket-distribution path uniformity — does the gold contribution to deity's bucket-share move across levels through the carryover path (callsite L988 via L652)?** Pre-emptive answer: carryover tickets re-enter the bucket distribution at later levels with the SAME trait IDs they carried at the originating level. The gold nerf applies uniformly at the new level's `_randTraitTicket` invocation (same function body; no per-level differentiation). A gold-trait ticket carrying over from level N to level N+1 enters the level-N+1 `_randTraitTicket` call with the gold-tier nerf already applied — no level-crossing EV leak. Expected Phase 296 disposition: **SAFE_BY_STRUCTURAL_UNIFORMITY**.

**Hypothesis 3: Secondary-strategy destabilization — does the EV reduction destabilize deity-pass holder behavior in unintended ways (secondary-market deity-pass price collapse; deity owners pivot to non-gold gameplay strategies that destabilize commons-tier dynamics)?** Pre-emptive answer: deity-pass economics shift toward common-color EV emphasis once gold-tier deity EV is reduced. Commons floor `max(len/50, 2)` is UNCHANGED so the commons-tier player-economy primitives (organic bet distribution, win-frequency expectations on common-color slots) are not directly perturbed by Phase 294. Any secondary-market deity-pass price shift is an intended outcome of the nerf per `D-42N-DEITY-EV-01`, not an unintended destabilization. Pivot-to-commons by deity-pass holders is also accepted as a feature of the nerf — the mechanic re-equilibrates deity-pass holder behavior toward broader-color participation. Expected Phase 296 disposition: **SAFE_BY_INTENT**.

**Hypothesis 4: ETH vs BURNIE differential-behavior — does the gold nerf create any asymmetry between the ETH jackpot path and the BURNIE near-future coin jackpot path that an attacker could game?** Pre-emptive answer: NO by construction — single function-body change in `_randTraitTicket` reaches both paths via the same code path; no callsite flag; no path-discrimination logic; no per-path tuning constants. ETH and BURNIE deity-EV reductions are structurally identical (both produce `virtualCount = 1` on gold; both retain `max(len/50, 2)` on commons; both inherit the same color extraction idiom `((trait >> 3) & 7) == 7`). The mechanic accepts that ETH-payout-currency-denominated wins and BURNIE-payout-currency-denominated wins are economically distinguishable to the holder, but the deity-virtual-entry allocation is uniform. Expected Phase 296 disposition: **SAFE_BY_CONSTRUCTION**.

## RNG Audit Methodology Disposition

Per CONTEXT.md `<canonical_refs>` audit-methodology section: `feedback_rng_backward_trace.md` and `feedback_rng_commitment_window.md` are NOT applicable to Phase 294.

**Backward-trace not required:** DPNERF does not introduce a new RNG consumer. `_randTraitTicket`'s `randomWord` consumption pattern at L1743-1745 (`uint256 r = uint256(keccak256(abi.encode(randomWord, trait, salt, i))) % effectiveLen;`) is UNCHANGED — only the `virtualCount` allocation path changes, and `virtualCount` is computed from `trait` (already committed at VRF-request time by the upstream `_rollWinningTraits` consumer) plus `len` (deterministic function of the trait-bucket state at jackpot-resolution time). No new randomness source; no new RNG sink; no new bit-slice consumption.

**Commitment-window invariant unchanged:** the gold-tier branch is deterministic on `trait`, which is already committed at VRF-request time by `_rollWinningTraits`'s upstream caller chain. The DPNERF branch does not introduce any player-controllable state that could change between VRF request and fulfillment. The commitment-window invariant is preserved structurally — no new attack surface for RNG-timing exploits.

No RNG audit burden added by Phase 294. The trait-byte input to the gold-tier branch is committed at the same point as the existing `virtualCount` inputs; the same commitment-window invariant established by v41's `_rollWinningTraits` path applies unchanged.

## Plan-02 Pre-Patch Gate

Plan 02 (`294-02-PLAN.md`) cannot begin its contract-edit task until BOTH `294-01-DESIGN-INTENT-TRACE.md` AND `294-01-MEASUREMENT.md` exist at the paths in Plan 01 `files_modified`. This is the design-intent-before-deletion gate per `feedback_design_intent_before_deletion.md`.

Plan 02's first task reads both artifacts and copies forward the 5 phase-scope decision anchors + the measurement framework into the batched contract commit message body (per `feedback_no_history_in_comments.md` — numerical attestations live in the commit body, NOT in NatSpec). Plan 02 is the user-approval gate for the contract changes per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_manual_review_before_push.md`; Plan 01 is AGENT-COMMITTED (planning artifacts only; zero contract / test edits).

**The planner has NOT pre-approved the contract diff per `feedback_never_preapprove_contracts.md`.** Plan 02's executor MUST present the full diff to the user for explicit review BEFORE staging or committing any contract change. The trace above and the measurement scaffold are the rationale-record the user sees alongside the diff at review time; they are NOT a substitute for the user's review.

## Sister-Plan Coverage Map

| Requirement | Plan 01 coverage | Plan 02 coverage |
|---|---|---|
| DPNERF-01 (gold-tier branch shape: `if (((trait >> 3) & 7) == 7) { virtualCount = 1; } else { virtualCount = len / 50; if (virtualCount < 2) virtualCount = 2; }`) | — | Plan 02 contract patch implementing the locked branch shape verbatim per CONTEXT.md `<specifics>` |
| DPNERF-02 (path coverage all callsites) | §3 callsite enumeration in MEASUREMENT scaffold (FINAL at Plan 01 time) + §(iv) Path-Coverage Trade-Offs in this trace | Plan 02 by construction (single function-body change reaches all 4 callsites with no callsite flag) |
| DPNERF-03 (common-tier preserved; intentional EV reduction; "deity earns less total EV across all 8 colors") | §(iii) Compensation Trade-Offs in this trace locks `D-42N-DEITY-EV-01` | Plan 02 by construction (else branch byte-identical to v41 `virtualCount = len / 50; if (virtualCount < 2) virtualCount = 2;` logic) |
| DPNERF-04 (storage byte-identical) | §2 attestation scaffold in MEASUREMENT + Out-of-Scope Register row (b) + (i) in this trace | Plan 02 post-patch `forge inspect storageLayout` EMPTY diff vs `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` |
| DPNERF-05 (public ABI byte-identical) | §4 attestation scaffold in MEASUREMENT + Out-of-Scope Register row (c) + (j) in this trace | Plan 02 post-patch `forge inspect methodIdentifiers` EMPTY diff vs `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` |
| DPNERF-06 (decision anchors recorded BEFORE patch) | This trace doc (4-section trace + 5 anchors + out-of-scope register + SWEEP-02(iii) pre-emptive answers) | — (gates Plan 02 by depends_on; satisfied at Plan 01 close) |

## Source Citations

| File | Line range | Role at Plan 01 |
|---|---|---|
| `contracts/modules/DegenerusGameJackpotModule.sol` | L1706 | `_randTraitTicket` function-level docstring — UNCHANGED by Plan 02 per CONTEXT.md Claude's Discretion. |
| `contracts/modules/DegenerusGameJackpotModule.sol` | L1707-L1757 | `_randTraitTicket` body — patch target; gold-tier branch added BEFORE existing `virtualCount = len / 50` + `if (virtualCount < 2) virtualCount = 2` logic. |
| `contracts/modules/DegenerusGameJackpotModule.sol` | L1721-L1723 | Pre-patch 3-line inline NatSpec comment block — REWRITTEN by Plan 02 to the 5-line two-tier shape per `D-294-NATSPEC-01`. |
| `contracts/modules/DegenerusGameJackpotModule.sol` | L1729-L1731 | Pre-patch `virtualCount = len / 50; if (virtualCount < 2) virtualCount = 2;` shape inside the `if (deity != address(0))` block — REPLACED by Plan 02 with the branched form (gold flat-1 + else preserved). |
| `contracts/modules/DegenerusGameJackpotModule.sol` | L1105 | Existing gold-tier extraction idiom `((traits[i] >> 3) & 7) == 7` in `_pickSoloQuadrant`; reused verbatim for the DPNERF branch per CONTEXT.md Claude's Discretion. |
| `contracts/modules/DegenerusGameJackpotModule.sol` | L1080-L1130 | `_pickSoloQuadrant` — UNRELATED gold-tier code path; byte-identical post-patch per Out-of-Scope Register row (d). |
| `contracts/modules/DegenerusGameJackpotModule.sol` | L698 | Callsite 1 of 4 — `_runEarlyBirdLootboxJackpot`; uniform-by-construction per `D-294-CALLER-UNIFORM-01`. |
| `contracts/modules/DegenerusGameJackpotModule.sol` | L988 | Callsite 2 of 4 — `_distributeTicketsToBucket` helper; uniform-by-construction per `D-294-CALLER-UNIFORM-01`. |
| `contracts/modules/DegenerusGameJackpotModule.sol` | L1296 | Callsite 3 of 4 — `_processDailyEth`; uniform-by-construction per `D-294-CALLER-UNIFORM-01`. |
| `contracts/modules/DegenerusGameJackpotModule.sol` | L1399 | Callsite 4 of 4 — `_resolveTraitWinners`; uniform-by-construction per `D-294-CALLER-UNIFORM-01`. |
| `contracts/modules/DegenerusGameJackpotModule.sol` | L1767 / L1816+ | BURNIE near-future coin jackpot path: `payDailyCoinJackpot` → `_awardDailyCoinToTraitWinners` → `_randTraitTicket` (resolves through callsite 2 or 3). |
| `contracts/DegenerusTraitUtils.sol` | L50, L97, L112, L214 | Gold = color 7 semantic confirmation (`scaled == 14 → gold (color 7)` mapping). |
| `contracts/modules/DegenerusGameDegeneretteModule.sol` | L854-L859 | Additional gold-tier extraction idiom precedent (`Counts gold (color == 7) quadrants in a packed ticket. Color tier occupies bits 5-3 of each per-quadrant byte; gold is the highest...`). |
| `contracts/storage/DegenerusGameStorage.sol` | (whole file) | Storage layout target for byte-identity attestation per DPNERF-04; UNCHANGED by Plan 02 per Out-of-Scope Register row (i). |

---

*Phase 294 Plan 01 — Design-Intent Trace (DPNERF-06); AGENT-COMMITTED pre-patch gate; produced 2026-05-17 against audit baseline `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4`.*
