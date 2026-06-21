# Milestone v72.0 — As-Built Audit: Foil Pack + Degenerette WWXRP/Rescore (+ Gas) — Requirements

> **Posture:** This is an AUDIT milestone, not a build. The subject is the full `ffbd7796 (v70 freeze) → HEAD` contract diff — **18 `.sol` files, +2,186/−355** — already committed across `f255d56c` (foil pack), `1dd07c4d` (WWXRP rig + payout fork), `16225de6` (Variant-2 foil match rescore). v71.0's BUILD is done; its deferred audit phases are **folded into v72.0**.
> The FOIL / RARE / MATCH / SEC requirements below are carried forward from v71.0 verbatim as **the design contract being audited** (`.planning/milestones/v71.0-REQUIREMENTS.md`, `.planning/V71-FOILPACK-FINAL-SPEC.md`). The RIG / PILLAR / GAS / TST blocks are **new v72 audit scope** — the WWXRP Degenerette rig + payout fork + the foil match rescore that v71 explicitly marked out-of-scope, plus the user-requested gas pass and the 3-pillars hard floor.
> Cross-model (Codex/ChatGPT + Gemini) is used on every load-bearing correctness/security claim in VERIFY (447) and REAUDIT (450); Claude-isolated-subagent nets where a CLI is unavailable.

## v72.0 Requirements

### FOIL — Purchase & economics  *(as-built design contract — verify/test/reaudit)*
- [ ] **FOIL-01**: A player can buy at most one foil pack per account per raw game-level (level-stamped cap, auto-resets per level).
- [ ] **FOIL-02**: A foil pack costs `10 × priceForLevel(level)` and delivers 4 whole tickets (16 quadrant entries).
- [ ] **FOIL-03**: A foil pack is payable with fresh ETH or claimable balance (the afking leg is rejected).
- [ ] **FOIL-04**: Foil spend routes 75% next-pool / 25% future-pool.
- [ ] **FOIL-05**: Foil tickets enter the regular jackpot as normal tickets; their boosted-rarity traits write real color tiers (incl. `color==7` gold).

### RARE — Activity-scaled rarity boost  *(as-built design contract)*
- [ ] **RARE-01**: Foil tickets roll traits via the NEW sibling producer (`traitFromWordFoil`/`packedTraitsFoil`); the v70-frozen shared producers are unmodified.
- [ ] **RARE-02**: The rarity multiplier scales with activity score ×2 @ 0 → ~×5 @ 350 → ×6 @ max, via the new `foilBoostBps` curve in `ActivityCurveLib`.
- [ ] **RARE-03**: The rarity multiplier is frozen at buy from the buyer's activity score and applied at resolve (never live-read).
- [ ] **RARE-04**: All rarer color tiers are lifted by the factor (mix-to-rare-tail); ×6 ⇒ gold ≈ 4.7%/quadrant.

### MATCH — Multi-currency match lottery  *(as-built design contract)*
- [ ] **MATCH-01**: Each pack's 4 ticket signatures (4 quadrants each) are frozen at buy and stored per `(player, level)`.
- [ ] **MATCH-02**: Each ticket is eligible the whole level against both daily winning sets (main + bonus, 2/day).
- [ ] **MATCH-03**: `claimFoilMatch(day, ticketIndex)` re-derives the day's winning traits from `rngWordByDay[day]`, counts exact positional quadrant matches, pays the 2/3/4 tier.
- [ ] **MATCH-04**: The match payout uses its OWN isolated table; it never routes through the EV-flat Degenerette per-N pick tables.
- [ ] **MATCH-05**: Settlement is pull/claim only; each `(day, drawKind, ticketIndex)` is claimable at most once; records persist per-level so a fast level advance cannot grief an unclaimed match.
- [ ] **MATCH-06**: The 2-of-4 / 3-of-4 tiers each pay one spin split 40% FLIP / 40% ETH / 20% WWXRP — FLIP `mintForGame`, ETH via the existing 10%-of-`futurePrizePool`-capped spin, WWXRP `mintPrize`.
- [ ] **MATCH-07**: The 4-of-4 tier grants half a whale pass (`whalePassClaims += 1`) plus a 40/40/20 bonus spin.
- [ ] **MATCH-08**: Spin magnitude and currency are both derived deterministically from `rngWordByDay[day]` at claim (disjoint entropy lanes); magnitude-first/currency-second reveal is UI-only.
- [ ] **MATCH-09**: The 2/3 tiers match against the live (hero-overridden) winning traits (bounded by-design hero edge retained); the 4-of-4 moonshot is gated on the hero-free pure-VRF winning traits (steer-proof).
- [ ] **MATCH-10**: The currency-payout ladder is calibrated to ≈2 ticket-faces of expected payout per pack over 30 days.

### RIG — Degenerette WWXRP rig + payout fork + Variant-2 rescore  *(NEW v72 scope — was v71 out-of-scope)*
- [ ] **RIG-01**: WWXRP reel rig (variant B) — on a WWXRP spin with `M ≤ 6` matched cells, a 60% chance flips exactly one unmatched **ordinary** (non-hero) cell into a match; a hero cell is never flipped; the apex `P(S9)` outcome probability is preserved (the rig shapes EV, it does not inflate the apex).
- [ ] **RIG-02**: WWXRP payout fork — WWXRP spins resolve on their OWN rigged per-N tables (`EV = 100` per table, flat 70% floor, RTP `{70, 115, 118, 120}%` by tier, surplus routed to 6+ outcomes); the ETH and FLIP payout paths are **byte-identical** to the pre-rig Degenerette.
- [ ] **RIG-03**: The foil MATCH is scored Degenerette-style (Variant-2: color-gated-by-symbol, score `T ∈ 0..8`), pays only `T ≥ 4` with EV-neutral faces `{4→2, 5→6, 6→35, 7→400, 8→10000 + ½ whale pass}`; holds ≈2.6333 ticket-faces of EV per pack over 30 days; match ticket-EV ≈2.16, ~flat in activity score.
- [ ] **RIG-04**: The rig + rescore do not regress the existing ETH/FLIP Degenerette game (byte-identical where intended), force a real reel match (no free wins), and preserve freeze-at-commitment (no live RNG read).

### PILLAR — the 3 protocol pillars  *(hard floor, cross-cutting — the explicit user ask)*
- [ ] **PILLAR-SOLV** (Solvency): no solvency hole on ANY new payout leg — foil ETH ≤10% `futurePrizePool`, FLIP/WWXRP are mints, the whale pass is a pool-neutral deferred grant, sDGNRS redemption backing stays intact, the WWXRP-rig surplus is fully accounted; no path pays unbacked value.
- [ ] **PILLAR-RNG** (RNG integrity): every new VRF consumer (foil rarity, match traits, WWXRP rig, hero edge, 4-of-4 moonshot) is frozen-at-commitment; no outcome is steerable / predictable / collusion-stackable; the 4-of-4 moonshot is gated on hero-free pure-VRF traits; the 2/3 hero edge is the only edge and is bounded by-design.
- [ ] **PILLAR-LIVE** (Liveness / no-brick): `advanceGame` + the mint/jackpot spine cannot be gas-bricked or state-corrupted by the foil ticket queue / `foilCursor` drain / leftover-budget drain / the rig; settlement is pull/claim only (advanceGame stays flat); EIP-170 fits.

### GAS — efficiency pass  *(NEW first-class axis — the explicit user ask)*
- [ ] **GAS-01**: A gas-efficiency pass over the entire new surface (FoilPackModule, Degenerette rig, Mint refactor + MintStreakUtils, TraitUtils, Storage append, ActivityCurveLib, Jackpot/Advance/Afking/Vault deltas) removes dead code / redundant SLOADs / packing waste with no behavior change and no regression to existing hot paths (`advanceGame`, `mint`/`mintFlip`, claim paths). Each accepted change is Scavenger→Skeptic validated.
- [ ] **GAS-02**: The Game contract + all modules stay under EIP-170 with the `GAME_FOILPACK_MODULE` wiring; the module split preserves headroom (re-measure vs the v70 baseline).

### SEC — security & integration floor  *(carried from v71)*
- [ ] **SEC-01**: No exploit beyond the bounded hero edge; the 4-of-4 moonshot cannot be steered or collusion-stacked. *(rolled up by PILLAR-RNG)*
- [ ] **SEC-02**: No solvency hole — ETH leg ≤10% of `futurePrizePool`, FLIP/WWXRP mints, whale pass pool-neutral. *(rolled up by PILLAR-SOLV)*
- [ ] **SEC-03**: New code fits EIP-170 (body in `GAME_FOILPACK_MODULE`, thin facade, storage appended in `DegenerusGameStorage`).
- [ ] **SEC-04**: The full forge suite is green and the storage-layout goldens / RNG-freeze proofs re-pass on the new (v72) subject.

### TST — test infrastructure & EV proofs
- [ ] **TST-INFRA-01**: Repair the `npm test` `GAME_FOILPACK_MODULE` / `ContractAddresses` resolution gap so the full Hardhat/JS suite runs against the new module (currently blocked at HEAD; 0 assertion fails, harness can't resolve the module address).
- [ ] **TST-EV-01**: Empirically prove the MATCH-10 / RIG-03 EV calibration (≈2.63 faces/pack/30d; ticket-EV ≈2.16) and the RIG-01/02 invariants (`P(S9)` invariance, variant-B flip-one bound, own-table `EV=100`, RTP ladder) via stat oracles.

## Future Requirements (deferred)
- Indexer-parity events for the foil buy + the match claim + the rig (additive; can land after).
- (carried from v70) mutation + Halmos formal on the new foil module; `roi`/`wwxrp` direct-body coverage.
- The v68 LOW defense-in-depth gated fixes (`:1843`/`:1850` `==0` re-roll guard + 423 rotation-timer hardening) — out of scope unless surfaced as load-bearing here.

## Out of Scope
- Any change to the v70-frozen shared trait producers or the existing lootbox/jackpot magnitude tables.
- New features beyond the as-built `ffbd7796 → HEAD` surface — v72 audits what exists; it does not add scope.
- Frontend/UI implementation of the reveal (on-chain provides the deterministic result; UI lives in a separate repo).
- Pushing to origin (USER pushes after review).

## Traceability

| Phase | Requirements (primary delivery) |
|---|---|
| **447 VERIFY + GAS** | verifies FOIL-01..05 / RARE-01..04 / MATCH-01..10 / RIG-01..04 / SEC-03 as-built vs locked design; delivers **GAS-01, GAS-02**; cross-model on load-bearing claims. Edits applied to working tree, **uncommitted**. |
| **448 FREEZE** | the single USER-approved contract commit → byte-frozen v72 subject (gates SEC-03 / GAS-02 into the committed tree). **Sole approval gate.** |
| **449 TST** | **TST-INFRA-01, TST-EV-01**, MATCH-10, RIG-03 EV; SEC-04 (suite green + layout goldens + RNG-freeze re-attest). |
| **450 REAUDIT** | **PILLAR-SOLV, PILLAR-RNG, PILLAR-LIVE**, SEC-01, SEC-02, RIG-04; cross-model council (Codex + Gemini) + Claude net; no-slot-move; invariant suites. |
| **451 TERMINAL** | SEC-04 final attest; `FINDINGS-v72.0.md` (chmod 444) + `AUDIT-V72-REPORT.html` + closure `MILESTONE_V72_AT_HEAD_<sha>`. |

All 33 requirements covered. (FOIL/RARE/MATCH are the as-built contract verified at 447 / proven at 449 / re-audited at 450; RIG/GAS delivered at 447; the 3 PILLARs + SEC attested at 450–451.)

---
*Requirements defined: 2026-06-21 (milestone v72.0 init, by hand — SDK state mutators avoided per repo process)*
