# Phase 446: IMPL — Batched Contract Diff [contract-commit gate] - Context

**Gathered:** 2026-06-19
**Status:** Ready for planning
**Source:** Synthesized from the locked `445-SPEC.md` design-lock (no discuss-phase — the SPEC has zero open decisions; both USER pins resolved 2026-06-19)

<domain>
## Phase Boundary

Land the v71.0 Foil Pack feature as **ONE batched, USER-approved `contracts/*.sol` diff** — the sole approval gate of the milestone — byte-freezing the v71 subject. The diff authors three locked tracks straight from `445-SPEC.md`:

- **FOIL (purchase + economics)** — a new `buyFoilPack()` payable entrypoint: one-per-RAW-level cap, `10 × priceForLevel(level)` for 4 whole tickets, fresh-ETH/claimable payment with the afking leg REJECTED, 75/25 next/future routing (`FOIL_TO_FUTURE_BPS = 2500`), and the 4 foil tickets entering the REGULAR jackpot as normal entries — but resolving boosted-rarity traits that write real color tiers (incl. `color == 7` gold).
- **RARE (activity-scaled rarity boost)** — two NEW sibling producers (`traitFromWordFoil` / `packedTraitsFoil`) + a new `foilBoostBps(score)` curve in `ActivityCurveLib`, delivering ×2→~×5→×6 with the boost **frozen at buy** from the buyer's activity score and applied at resolve (never live-read). The v70-frozen shared producers are NOT touched.
- **MATCH (multi-currency match lottery)** — `claimFoilMatch(day, ticketIndex, drawKind)` pull/claim: per-`(player, level)` frozen signatures, whole-level eligibility against both daily winning sets, exact 6-bit positional quadrant predicate, the LIVE (2/3-of-4) vs HERO-FREE (4-of-4) re-derivation split, the isolated 40/40/20 spin (FLIP/WWXRP mints, ETH ≤10%-of-`futurePrizePool`), the half-whale-pass grant, and the CEI double-claim guard.

This is a **mechanical batched diff from `445-SPEC.md`** — every coefficient, the boost curve, the packed storage layout, the two entrypoint bodies, the winning-set re-derivation, the isolated payout, and the calibration are design-locked there with "no by-construction assumptions, no mid-diff re-grep, no unsettled decision." Phase 446 decides only the small IMPL-discretion residue (§decisions). Baseline = the v70.0 closure subject `contracts/` tree `99f2e53f` @ `ffbd7796` (closure `MILESTONE_V70_AT_HEAD_25ff6aaed0e9209e2003f467a3607056bfac9c03`; origin/main `0bc8cf72`); `contracts/*.sol` is CLEAN at milestone start. Empirical proof (447 TST, MATCH-10), re-audit (448 REAUDIT, SEC-01/02/04), and terminal attest (449) are separate phases.

</domain>

<decisions>
## Implementation Decisions

`445-SPEC.md` is the **load-bearing, build-ready spec** — all substantive decisions (the rarity PMF + `/15360` cutoff ladder, the `foilBoostBps` curve, the packed `foilRecord` layout + folded cap + `foilMatchClaimed` marker, the two entrypoint bodies, the LIVE/HERO-FREE re-derivation crux, the isolated payout lanes, the calibration verdict, the module placement) are **already locked there and are NOT re-litigated here**. Both layout pins are RESOLVED (D.6, §T): PIN 1 = `foilRecord` keyed `mapping(uint24 => mapping(address => uint256))` (level=>player surviving-record form; the single-slot self-overwrite loss edge is ELIMINATED); PIN 2 = packed bit-offset stamp `[144-167]` / payload `[0-143]` (ACCEPTED). The decisions below are the IMPL-discretion knobs the SPEC explicitly defers to 446.

### IMPL-discretion residue (the SPEC's open knobs — these are the ONLY 446 choices)
- **D-446-01 (foil-owed jackpot-trait resolution mechanism):** §E.1 step 7 fixes the producer = `packedTraitsFoil(seed, multBps)` and the multiplier = the frozen `multBps`, but **leaves the mechanism to 446**: whether the queue-resolution path that today calls `packedTraitsFromSeed` (heavy-tail) routes foil-owed entries through the sibling via a **parallel foil-owed queue** or a **per-entry boost tag**. Pick the cleaner option that does not edit the v70-frozen producers and keeps the foil path purely additive (RARE-01). The frozen `multBps` from `foilRecord` is the input either way.
- **D-446-02 (module file name + symbol placement):** The new module's file/contract name (e.g. `DegenerusGameFoilPackModule.sol`) and the exact placement of the new constants (`FOIL_TO_FUTURE_BPS`, `FOIL_SEED_TAG`, `FOIL_MAG_TAG`, `FOIL_CCY_TAG`, the bonus-traits / ETH-cap tags) and helpers — IMPL detail, matching the existing module/storage conventions.
- **D-446-03 (literal vs mask/`type()` constants where equivalent):** Where a `type(uintN).max` literal and a named mask are equivalent, pick the most self-documenting form (follows the house convention from prior phases).
- **D-446-04 (`GAME_FOILPACK_MODULE` address constant in `ContractAddresses.sol`):** Add the new `address internal constant GAME_FOILPACK_MODULE = …;` alongside the existing 12 `GAME_*_MODULE` at `ContractAddresses.sol:13-35`. `ContractAddresses.sol` is modifiable without the per-file approval gate (it still rides the one batched commit).

### Carry-verbatim corrected anchors (§1 of the SPEC — a stale value steers 446 to wrong code)
- Foil-ticket queue scale is **`400`** (`= 4 × TICKET_SCALE = 100`), NOT `4` — the third arg of `_queueTicketsScaled` is `quantityScaled` in `TICKET_SCALE` units.
- `whalePassClaims` **already exists** at `DegenerusGameStorage.sol:1122` (`mapping(address => uint256)`) — the 4-of-4 tier does `whalePassClaims[player] += 1`; do **NOT** re-declare it.
- The ETH cap-spin clone source is **`DegenerusGameDegeneretteModule.sol:877-915`** (`maxEth` `:889`, lootbox-resolve `:915`) — NOT the previously-cited `:402-446`.
- The double-claim marker is **`foilMatchClaimed`** (unified name; not `foilClaimed`).
- `claimFoilMatch(D)` reads the hero pool at **`dailyHeroWagers[D-1]`** (the prior-day slot; `dailyIdxFor(day) == day - 1`).

### Claude's Discretion
- **Pre-approval empirical gate (taken at discretion, before presenting the diff):** `forge build` clean + the **EIP-170 deployed-bytecode ceiling re-measure** (SEC-03 / §F.4 — confirm the new `GAME_FOILPACK_MODULE` body and the facade-after-stubs both fit 24,576 B, recording actual sizes vs the §F estimate of ~8–11 KB body / 13.5–16.5 KB headroom) + a **storage-layout sanity** (`foilRecord` + `foilMatchClaimed` tail-append after `boxPlayers` `:2393`, NO slot moves of existing fields — the new layout golden lands in 448) + a baseline-parity smoke. Full behavioural proof stays in 447 TST / 448 REAUDIT.
- **Diff presentation (taken at discretion):** present the batched diff grouped by track (FOIL economics+entrypoint / RARE producers+curve / MATCH claim+payout / storage+module-wiring) with a per-file change map, so the one hand-review is auditable. **ONE atomic contract commit** (the batch-approval rule) — the sole approval gate; `git push` left to the USER.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### The load-bearing design-lock (read FIRST — self-contained for a 446 author)
- `.planning/phases/445-spec-design-lock-the-implementation-contract/445-SPEC.md` — the build-ready spec: §0 decisions + the two RESOLVED pins, §1 corrected anchors, §A economics (rarity PMF + `/15360` ladder + `foilBoostBps` curve), §D storage layout (`foilRecord` + folded cap + `foilMatchClaimed`), §E entrypoints (E.1 `buyFoilPack` 8-step body, E.2 `claimFoilMatch` body, E.3 the LIVE-vs-HERO-FREE re-derivation crux, E.5 isolated payout lanes, E.7 calibration), §F module placement + EIP-170, §R REQ-coverage map, §S threat model, §T USER decisions. **This is the spec for the 446 diff.**
- The three section files (consolidated into §A/§D/§E of the SPEC, kept for cross-reference): `445-SPEC-A-economics.md`, `445-SPEC-D-storage.md`, `445-SPEC-E-entrypoints.md`.

### Milestone inputs
- `.planning/V71-FOILPACK-FINAL-SPEC.md` — the locked design ("this file wins").
- `.planning/V71-FOILPACK-DESIGN-CONTEXT.md` — grounding/history.
- `.planning/REQUIREMENTS.md` — the 446 REQ-IDs (FOIL-01..05, RARE-01..04, MATCH-01..09, SEC-03) + Out-of-Scope + Traceability.
- `.planning/ROADMAP.md` §"Phase 446" — goal + success criteria + the contract-commit-gate posture.
- `.planning/phases/445-.../445-RESEARCH.md` — the authoritative research (every coefficient adversarially V1/V2/V3-verified) the SPEC consolidates; read for the derivation behind any locked number.

### Source files in the 446 edit surface (anchored at `ffbd7796` / tree `99f2e53f`)
- **NEW** `contracts/modules/DegenerusGameFoilPackModule.sol` (name per D-446-02) — the foil body: `_buyFoilPack(buyer, ethSent)` (E.1) + `_claimFoilMatch(...)` (E.2) + the isolated 40/40/20 spin payout (E.5). ~8–11 KB.
- `contracts/DegenerusGame.sol` — two thin facade stubs `buyFoilPack() external payable` + `claimFoilMatch(uint256 day, uint256 ticketIndex, uint8 drawKind) external`, both `delegatecall(GAME_FOILPACK_MODULE)` + `_revertDelegate`. Template = `buyPresaleBox` (`:614-629`). `whalePassClaims` slot at `:1122` (reused, not re-declared).
- `contracts/storage/DegenerusGameStorage.sol` — tail-append `foilRecord` (`mapping(uint24 => mapping(address => uint256))`) + `foilMatchClaimed` (`mapping(bytes32 => bool)`) after `boxPlayers` (`:2393`); new constants `FOIL_TO_FUTURE_BPS = 2500` + the keccak-domain tags (`FOIL_SEED_TAG`, `FOIL_MAG_TAG`, `FOIL_CCY_TAG`, bonus-traits + ETH-cap `1000` bps as applicable). `level` = `uint24 public level` (`:236`). No slot moves.
- `contracts/DegenerusTraitUtils.sol` (root — NOT `contracts/libraries/`; the SPEC's `libraries/` prefix is a grounding typo, corrected by the planner) — NEW siblings `traitFromWordFoil(uint64,uint256)` + `packedTraitsFoil(uint256,uint256)`, cloned structurally from `packedTraitsDegenerette`/`_degTrait` (`:201-223`); ONLY the color stage changes (the `/15360` cutoff ladder). The frozen producers `weightedColorBucket`/`traitFromWord`/`packedTraitsFromSeed` (`:115/:143/:169`) are NOT edited/retyped/moved (RARE-01).
- `contracts/libraries/ActivityCurveLib.sol` — NEW `foilBoostBps(uint256 score)` curve (output `20000..60000` bps; reuses the two existing shared knees per §A.2).
- `contracts/ContractAddresses.sol` — new `GAME_FOILPACK_MODULE` constant (`:13-35` neighborhood).
- `contracts/interfaces/IDegenerusGame.sol` — add the two new external selectors if the delegatecall encoding / facade signature requires it.
- Clone reference (read-only, NOT edited): `contracts/modules/DegenerusGameDegeneretteModule.sol:877-915` (the ETH cap-spin path the E.5 ETH lane clones); `contracts/modules/DegenerusGameJackpotModule.sol` `_applyHeroResult` (`:1316-1341`), `_rollWinningTraits`/`_rollHeroSymbol` (the E.3 re-derivation mirror); `JackpotBucketLib.sol:281-286` (`getRandomTraits`/`packWinningTraits`); `contracts/modules/DegenerusGameMintModule.sol:201-217,:236-299,:1709` (the payment/routing accounting shapes reused, the `cachedScore` source).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets / patterns (copy the shape, fork the minimum)
- **Facade-stub pattern** `buyPresaleBox` (`DegenerusGame.sol:614-629`): resolve player → `MODULE.delegatecall(abi.encodeWithSelector(...))` → `_revertDelegate(data)`. The two foil stubs copy this verbatim; all logic lives in the module.
- **Sibling-producer pattern** `packedTraitsDegenerette` already coexists beside the frozen heavy-tail producer — the foil siblings follow the same additive shape; only the color stage differs.
- **Payment/routing shapes** reused but forked: `_processMintPayment` accounting (`:236-299`) with the afking leg REJECTED via the residual-vs-claimable guard; `_recordMintPayment` frozen/unfrozen branch (`:201-217`) reused unchanged with ONLY `FOIL_TO_FUTURE_BPS = 2500` forked from `PURCHASE_TO_FUTURE_BPS = 1000`.
- **ETH cap-spin** cloned from `DegenerusGameDegeneretteModule.sol:877-915` (10%-`futurePrizePool` clamp + lootbox spill).

### Established invariants the diff must preserve
- **RARE-01 — frozen producers untouched.** The foil path is purely additive (new siblings + new curve); the v70-frozen `weightedColorBucket`/`traitFromWord`/`packedTraitsFromSeed` are byte-identical after the diff.
- **The boost CANCELS in the match channel.** The daily winning set is a flat-uniform 6-bit model (`getRandomTraits`), so per-quadrant match `q = 1/64` is M-invariant — the boost changes jackpot-gold participation (§A) but NOT match-lottery odds (calibration is closed-form, M-flat).
- **CEI** — `foilMatchClaimed[mk] = true` is written BEFORE any payout effect in `claimFoilMatch`.
- **No slot moves** — `foilRecord` + `foilMatchClaimed` tail-append; the existing storage layout is unchanged (the new golden lands in 448).

### Integration / blast radius
- New external selectors cross the contract boundary (`buyFoilPack`, `claimFoilMatch`) + the foil tickets join `traitBurnTicket[level][traitId]` jackpot eligibility. Foil-owed entries resolve boosted traits (real `color == 7` gold) → feeds the same RNG-consumer surface the 448 REAUDIT re-freezes.
- The diff RESETS the v70 RNG-freeze proof + storage-layout golden on the new (foil) subject — all re-run on the post-IMPL subject at 448 (v70 methodology carries forward).
- Indexer parity events for the foil buy + match claim are **additive and deferred** (REQUIREMENTS Future) — not in this diff.

</code_context>

<specifics>
## Specific Ideas

- The whole milestone is engineered so 446 is **mechanical**: the SPEC author's stated goal is that the IMPL writes the diff with no re-derivation. Treat any ambiguity as a SPEC lookup, not a new decision — escalate to the USER only if the SPEC genuinely under-specifies (it should not).
- The **sole approval gate** is the one consolidated `contracts/*.sol` commit. Applying/editing `.sol` autonomously is fine; the commit needs the USER's hand-review of the single batched diff. Commit all planning docs BEFORE touching `.sol` (the commit-guard hook blocks commits while `contracts/*.sol` is dirty; bypass for the approved contract commit only).
- Calibration is **CONFIRM-and-REPORT**: realized 1.9376 faces/pack/30d lands 3.1% low on the ~2 target → no recalibration flag; the locked table stays LOCKED. The build-time comment cites the **87.9%/12.1%** tier split (not the illustrative ~85%).

</specifics>

<deferred>
## Deferred Ideas

- **MATCH-10** (empirical ≈2-faces/pack/30d calibration confirm) — proven at 447 TST, not 446. The SPEC's closed-form figures stand; 447 confirms empirically and only flags the USER if materially off (never silently retunes).
- **SEC-01 / SEC-02 / SEC-04** — design bases are locked in the SPEC (§E.3 / §E.5 / §D); they are **attested downstream** at 448 REAUDIT / 449 TERMINAL per the audit-milestone pattern. Not closed in 446.
- **Indexer parity events** for the foil buy + match claim — additive, can land after the feature (REQUIREMENTS Future).
- **Out of scope (REQUIREMENTS):** adding WWXRP / the 40/40/20 split to the *existing* Degenerette; any change to the v70-frozen shared trait producers or the existing lootbox/jackpot magnitude tables; the frontend/UI reveal (separate repo).

</deferred>

---

*Phase: 446-IMPL — Batched Contract Diff [contract-commit gate]*
*Context synthesized 2026-06-19 from the locked 445-SPEC.md (no open decisions)*
