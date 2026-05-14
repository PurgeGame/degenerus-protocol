# Requirements: v40.0 Unified Whole-Ticket Award Protocol

**Milestone:** v40.0
**Audit baseline:** `MILESTONE_V39_AT_HEAD_6a7455d1`
**Phase shape:** Multi-phase (6 phases — 5 surface-split + 1 terminal audit) per v33/v34/v35/v37 precedent — NOT the v36/v38/v39 single-phase pattern
**Single terminal deliverable:** `audit/FINDINGS-v40.0.md` (per D-NN-FILES-01 carry → D-40N-FILES-01)
**Scope:** All RNG-driven ticket-award surfaces — auto-resolve LootboxModule paths (`resolveLootboxDirect` decimator-claim + `resolveRedemptionLootbox` sDGNRS-redemption) AND JackpotModule:2216 BAF small-lootbox ticket-roll path. Plus event surface unification + sentinel retirement + JackpotModule cosmetic cleanup + ENT-05 BAF xorshift refactor. Plus whole-BURNIE-coin floor at 3 RNG-influenced BURNIE-award sites — lootbox spin BURNIE (`LootboxModule:1080`) + near-future coin jackpot (`JackpotModule:1842`) + far-future coin jackpot (`JackpotModule:1922`). Mint-boost (`DegenerusGameMintModule.sol:1142` `_queueTicketsScaled` + `_rollRemainder`) AND mint-boost flip-credit (`DegenerusGameMintModule.sol:1199`) explicitly EXCLUDED per D-40N-MINTBOOST-OUT-01 + D-40N-BUR-MINTBOOST-OUT-01 — deterministic dust accumulators on user-altered input, not RNG-driven.

## Out of Scope

- **Mint-boost fractional retirement** per D-40N-MINTBOOST-OUT-01 (carries D-274-MINTBOOST-OUT-01) — `_queueTicketsScaled` callsite at `DegenerusGameMintModule.sol:1142` + `_rollRemainder` + `rem` byte in `ticketsOwedPacked` STAY. Mint-boost is a deterministic dust accumulator driven by `priceWei / (4 * TICKET_SCALE)` arithmetic on user-controllable mint amounts — NOT RNG-driven — so the user-controllable input forbids Bernoulli rounding (which needs commit-time-unknown RNG). User disposition 2026-05-13: "make all ticket awards full 4 entry tickets that use randomness that can't be altered (so not counting ticket mints)".
- **Deterministic + player-alterable BURNIE-award sites** per D-40N-BUR-MINTBOOST-OUT-01 — mint-boost flip-credit at `DegenerusGameMintModule.sol:1199` `coinflip.creditFlip(buyer, lootboxFlipCredit)`; daily-coinflip claim/mint at `BurnieCoinflip.sol:409/770/789`; advance bounty at `DegenerusGameAdvanceModule.sol:191/227/477/886`; quest rewards at `DegenerusQuests.sol:514/629/739/887/890/954/1885`; affiliate DGNRS deity bonus at `DegenerusGame.sol:1463` + `DegenerusAffiliate.sol:777`. All produce fractional BURNIE but the amounts are deterministic on user-altered or system-deterministic inputs (not RNG-amount) — out of v40.0 "RNG-driven BURNIE awards" framing. User disposition 2026-05-13: "anywhere that we award BURNIE in random amounts that might have fractional amounts" (scope narrows to the 3 BUR-targeted sites only).
- **Entry-vs-ticket granularity refactor** per D-40N-GRANULARITY-01 — granularity decision SETTLED at TICKET granularity (1 ticket = 4 entries; Bernoulli rounds at ticket granularity; 4× variance vs entry-granularity accepted in exchange for simpler storage / no downstream re-scaling). Entry-granularity refactor permanently dropped from roadmap consideration. The v39.0 manual-path Bernoulli already established this precedent at `bits[152..167]`; v40.0 extends the same convention to auto-resolve + jackpot surfaces.
- **WWXRP consolation on auto-resolve + jackpot cold-bust** per D-40N-SILENT-01 — auto-resolve + jackpot ticket-roll paths are SILENT on cold-bust (whole=0 from non-zero pre-Bernoulli scaled). No consolation mint, no separate roll event. The v39.0 manual-path's `LOOTBOX_WWXRP_CONSOLATION = 1 ether` consolation pattern does NOT extend to these paths because they resolve without explicit player intent at the moment of resolution (decimator-claim + sDGNRS-redemption + jackpot-ticket-award all happen as side-effects of other player actions or system actions, not as direct user-initiated lootbox opens). Asymmetry intentional + documented.
- **`LootboxTicketRoll` event preservation** — v39.0-additive `LootboxTicketRoll(player, lootboxIndex, preRollTickets, roundedUp)` event is RETIRED in v40.0 per D-40N-EVT-BREAK-01 (supersedes D-274-EVT-ROLL-01 + D-274-EVT-INDEX-SENTINEL-01 + D-274-NO-EVT-BREAK-01 non-breaking stance). Folded into existing per-action events (`LootBoxOpened`, `BurnieLootOpen`, `JackpotTicketWin`) via new field additions. Breaking topic-hashes accepted because v40.0 will require indexer rebuild against the auto-resolve + jackpot Bernoulli surfaces regardless.
- **Index-sentinel behavior gate** — `_resolveLootboxCommon` `index != type(uint48).max` behavior-gating sentinel (introduced v39.0 P274 Wave 1) is RETIRED in v40.0 per D-40N-SENTINEL-RETIRE-01. Manual + auto-resolve converge on the same `_queueTickets(whole)` model, so the behavior gate no longer serves a purpose. The `uint48 index` parameter MAY retain its event-identifier role (TBD per EVT-UNI-06 plan-phase decision) but the sentinel-skip branch deletes.
- **New storage layout / new admin / new upgrade hooks**
- **New public/external mutation entry points** (existing entry-point signatures may gain/lose `LootboxTicketRoll`-related parameters, but no new entry points)
- **KNOWN-ISSUES.md modifications** (default zero-promotion path per D-272-KI-01 → D-40N-KI-01 carry)
- **Game-over thorough hardening** — deferred to dedicated game-over hardening milestone
- **LBX-02 fixture-coverage gap** (RE-DEFERRED-V40+ at v39.0 close; D-274-LBX02-OUT-01) — RE-DEFERRED-V41+ at v40.0 open; fixture-coverage gap persists; analytical worst-case continues to be load-bearing per Phase 266 GAS-01 + `feedback_gas_worst_case.md`
- **`runrewardjackpots` module-misplacement note** — stale 2026-04-02 backlog note; not v40.0-tagged; carries forward to v41.0+

## v40.0 Requirements

### LBX-AR — Auto-Resolve LootboxModule Bernoulli (contracts/modules/DegenerusGameLootboxModule.sol)

- [ ] **LBX-AR-01**: Auto-resolve branch of `_resolveLootboxCommon` (the branch reached when called from `resolveLootboxDirect` or `resolveRedemptionLootbox`) applies Bernoulli round-up using `bits[152..167]` of the per-resolution seed — the SAME 16-bit slice the v39.0 manual-path uses per D-274-BIT-SLICE-01 (v39 supersession to 16-bit form for <0.10% relative bias). Predicate: `frac != 0 && (uint16(seed >> 152) % uint16(TICKET_SCALE)) < uint16(frac)` → `roundedUp = true`. Assign `futureTickets = whole + (roundedUp ? 1 : 0)`. EV-neutrality: `E[whole_post] == scaledPre / TICKET_SCALE` exactly. Net gas-NEUTRAL when factoring eliminated `_rollRemainder` consumption at trait-assignment time.
- [ ] **LBX-AR-02**: Replace `_queueTicketsScaled(player, targetLevel, futureTickets, false)` call at `DegenerusGameLootboxModule.sol:1068` (auto-resolve branch) with `_queueTickets(player, targetLevel, whole, false)` (whole-ticket helper at L562). The auto-resolve branch emits `TicketsQueued(buyer, level, qty)` (qty = whole) — NOT `TicketsQueuedScaled`. After v40.0 lands, NO call site emits `TicketsQueuedScaled` from the LootboxModule.
- [ ] **LBX-AR-03**: NO WWXRP consolation emission on auto-resolve cold-bust per D-40N-SILENT-01. When `whole == 0` post-Bernoulli on the auto-resolve branch, the function returns without invoking `wwxrp.mintPrize(...)` and without emitting `LootBoxWwxrpReward`. Auto-resolve cold-bust is a silent zero-award outcome.
- [ ] **LBX-AR-04**: Seed-uniqueness preservation across all 4 upstream auto-resolve callers — verified safe per PROJECT.md v40.0 trace (carried from v39 close): (a) DecimatorModule:594 `claimDecimatorJackpot(lvl)` — single-shot per call; rngWord from per-level storage; unique; (b) DegeneretteModule:786 — single-shot per payout call; (c) StakedDegenerusStonk:672 — single-shot per redemption; entropy = `keccak(rngWord, player)`; (d) DegenerusGame:1721 redemption-loop wrapper — loops in 5-ETH chunks but EVOLVES rngWord per iteration via `rngWord = keccak256(abi.encode(rngWord))` at L1769, so each chunk's seed is unique. v40.0 introduces no new seed-collision risk.
- [ ] **LBX-AR-05**: Storage layout byte-identical at v40 phase-close HEAD vs v39 baseline `6a7455d1` for `DegenerusGameLootboxModule.sol` (storage-slot grep proof). Zero new admin entry points; zero new external mutation entry points; zero new modifiers. The `_queueTicketsScaled` helper itself may be deleted from the module if no caller remains after LBX-AR-02 lands AND mint-boost call paths don't share the helper (verify via call-site grep — `_queueTicketsScaled` is module-private to LootboxModule; the mint-boost caller is `DegenerusGameMintModule.sol:1142` and uses ITS OWN `_queueTicketsScaled` if they're separate copies, OR the LootboxModule helper if shared cross-module; final disposition by plan-phase).
- [ ] **LBX-AR-06**: `_rollRemainder` invocation count from auto-resolve lootbox paths drops to zero post-v40.0 (verified via TST-LBX-AR-04). The mint-boost path at `DegenerusGameMintModule.sol:1142` continues to invoke `_rollRemainder` per D-40N-MINTBOOST-OUT-01 — `_rollRemainder` + `rem` byte STAY for mint-boost.

### JPT-BR — JackpotModule:2216 BAF Bernoulli (contracts/modules/JackpotModule.sol)

- [x] **JPT-BR-01**: `_jackpotTicketRoll` (at `JackpotModule.sol:2186`) applies Bernoulli round-up using `bits[200..215]` of the existing `entropy` chain — 16-bit slice for <0.10% relative bias; 180+ bits separated from current bits[0..12] consumers (path/bucket selection). Predicate: `frac != 0 && (uint16(entropy >> 200) % uint16(TICKET_SCALE)) < uint16(frac)` → `roundedUp = true`. Assign `whole = (scaledTickets / TICKET_SCALE) + (roundedUp ? 1 : 0)`.
- [x] **JPT-BR-02**: Replace `_queueLootboxTickets(player, level, scaledTickets)` wrapper call at `JackpotModule.sol:2216` with direct `_queueTickets(player, level, whole, false)`. The `_queueLootboxTickets` wrapper retires (JPT-CLEAN-05).
- [x] **JPT-BR-03**: Per-roll uniqueness verified — `EntropyLib.entropyStep` evolves the entropy chain between the 2-roll pattern at `_awardJackpotTickets` L2157/L2166, so each ticket-roll's entropy seed is distinct. v40.0 introduces no new entropy-collision risk.
- [x] **JPT-BR-04**: NO WWXRP consolation emission on jackpot cold-bust per D-40N-SILENT-01. When `whole == 0` post-Bernoulli, the function returns without invoking `wwxrp.mintPrize(...)`. Roll outcome surfaces via `JackpotTicketWin.roundedUp` field (EVT-UNI-04).
- [x] **JPT-BR-05**: Net gas-NEGATIVE (saves gas) — `_queueLootboxTickets` wrapper retirement removes one internal call frame; `_queueTickets(whole)` writes a smaller value to storage than `_queueTicketsScaled(scaled)`; eliminated `_rollRemainder` consumption at trait-assignment time. Gas delta reported in commit message.
- [x] **JPT-BR-06**: Bit-allocation NatSpec on `_awardJackpotTickets` / `_jackpotTicketRoll` updated to document the new sub-roll: `bits[200..215] jackpotTicketRoundUp % 100`. Total entropy consumption documented relative to the existing bits[0..12] consumers — clear 180+ bit separation.

### EVT-UNI — Event Surface Unification + Index-Sentinel Retirement (contracts/modules/DegenerusGameLootboxModule.sol + contracts/modules/JackpotModule.sol + interfaces)

- [x] **EVT-UNI-01**: DROP the v39.0-additive `LootboxTicketRoll` event entirely from `IDegenerusGameLootboxModule.sol` AND the contract-level event block of `DegenerusGameLootboxModule.sol`. Zero remaining emission sites in the codebase (verified via TST-EVT-UNI-02).
- [x] **EVT-UNI-02**: Add `(uint32 preRollTickets, bool roundedUp)` fields to `LootBoxOpened` event. New signature: `event LootBoxOpened(address indexed player, uint48 indexed lootboxIndex, uint48 day, uint128 amount, uint32 level, uint32 preRollTickets, uint32 burnie, uint16 bonus, bool roundedUp)` (final field order TBD by plan-phase for optimal slot packing). `preRollTickets` = pre-Bernoulli scaled value (matches `LootboxTicketRoll.preRollTickets` semantics from v39); `roundedUp` = Bernoulli outcome (matches `LootboxTicketRoll.roundedUp` semantics). Emitted on BOTH manual + auto-resolve paths (auto-resolve emission TBD per EVT-UNI-06 — if auto-resolve currently lacks per-resolution event, add emission OR rely on a separate signal).
- [x] **EVT-UNI-03**: Add `(uint32 preRollTickets, bool roundedUp)` fields to `BurnieLootOpen` event. Same semantics as EVT-UNI-02; emitted from `openBurnieLootBox` paths (manual only — auto-resolve doesn't open BURNIE lootboxes).
- [x] **EVT-UNI-04**: Add `bool roundedUp` field to `JackpotTicketWin` event. Single-field addition (JackpotModule already emits scaled values in its existing event surface; the existing `preRollTickets`-equivalent semantics live in current event fields per plan-phase grep). Emitted from `_awardJackpotTickets` L2157/L2166 ticket-roll outcomes.
- [x] **EVT-UNI-05**: RETIRE the `index != type(uint48).max` sentinel behavior-gating branch on `_resolveLootboxCommon`. Manual + auto-resolve callers ALL pass real `index` arg for event identification. The behavior split (Bernoulli + queue-whole vs. fall-through scaled-queue) deletes — both branches now Bernoulli-roll and call `_queueTickets(whole)`. The `uint48 index` parameter retains its event-emission identifier role per EVT-UNI-02. Auto-resolve callers (`resolveLootboxDirect` + `resolveRedemptionLootbox`) update to pass real `index` instead of `type(uint48).max`.
- [x] **EVT-UNI-06**: Auto-resolve emission shape decision — currently `resolveLootboxDirect` and `resolveRedemptionLootbox` do NOT emit `LootBoxOpened` (per-resolution event for auto-resolve was not added in v39.0). Plan-phase decides: (a) ADD `LootBoxOpened` emission to both auto-resolve callers (matches the unified event-emission model; field-consistent with manual paths); OR (b) keep auto-resolve silent on `LootBoxOpened` and surface `(preRollTickets, roundedUp)` via a different signal (e.g., extend `TicketsQueued` with these fields). Option (a) is the simpler / more uniform default; option (b) reduces gas on the high-volume decimator-claim path. Decision deferred to plan-phase per D-40N-AR-EMIT-01.
- [x] **EVT-UNI-07**: Bytecode delta — saves ~1,350 gas per manual lootbox open (no separate LOG3 emit for `LootboxTicketRoll`). Final per-op gas delta reported in commit message; expected NET-NEGATIVE across all ticket-award paths after factoring the `LogN` topic count + payload-size deltas.
- [x] **EVT-UNI-08**: Breaking topic-hashes accepted per D-40N-EVT-BREAK-01 — pre-launch supersession of D-274-NO-EVT-BREAK-01 non-breaking stance. Indexer rebuild expected; no live indexer impact.

### JPT-CLEAN — JackpotModule Cosmetic Cleanup + ENT-05 BAF Xorshift Refactor + `_queueLootboxTickets` Retirement (contracts/modules/JackpotModule.sol)

- [ ] **JPT-CLEAN-01**: Cosmetic `xTICKET_SCALE` cleanup at `JackpotModule.sol:702` (already deferred per D-274-JACKPOT-OUT-01) — simplify `× TICKET_SCALE` expressions where the scaled-vs-whole distinction is moot post-JPT-BR-02. Final shape TBD by plan-phase grep + intent-trace per `feedback_design_intent_before_deletion.md`.
- [ ] **JPT-CLEAN-02**: Cosmetic `xTICKET_SCALE` cleanup at `JackpotModule.sol:835`. Same disposition as JPT-CLEAN-01.
- [ ] **JPT-CLEAN-03**: Cosmetic `xTICKET_SCALE` cleanup at `JackpotModule.sol:1005`. Same disposition as JPT-CLEAN-01.
- [ ] **JPT-CLEAN-04**: ENT-05 BAF xorshift refactor (deferred since v36.0 P266; carry per D-274-JACKPOT-OUT-01 + EXC-04 NARROWS-retained scope) — refactor the BAF jackpot xorshift entropy path to align with `EntropyLib.entropyStep` keccak primary-chunk convention OR explicit derivation discipline. Specific refactor shape TBD by plan-phase (e.g., replace xorshift with keccak-derived sub-roll; OR document xorshift as locally-required for legacy reasons). EXC-04 KI envelope narrowing scope reduces post-refactor — if refactor lands, EXC-04 RE_VERIFIED at v40 close may demote from `NARROWS` to `NEGATIVE`.
- [ ] **JPT-CLEAN-05**: RETIRE `_queueLootboxTickets` wrapper function (unused after JPT-BR-02 lands — `JackpotModule.sol:2216` is its only caller; replacing with direct `_queueTickets(whole)` makes the wrapper dead code). Delete the wrapper + its private helper invocation chain per `feedback_no_dead_guards.md`.
- [ ] **JPT-CLEAN-06**: Storage layout byte-identical at v40 phase-close HEAD vs v39 baseline `6a7455d1` for `JackpotModule.sol` (storage-slot grep proof). Bytecode delta reported in commit message — expected NET-NEGATIVE (cleanup + refactor + wrapper retirement all shrink bytecode).

### TST-LBX-AR — Auto-Resolve LootboxModule Bernoulli Tests (test/lootbox/ or test/edge/)

- [ ] **TST-LBX-AR-01**: Bernoulli-collapse EV-neutrality property test on auto-resolve paths. ≥10,000 seeded `claimDecimatorJackpot` + `resolveRedemptionLootbox` invocations across a representative span of pre-Bernoulli scaled values (47, 99, 100, 147, 250, 1000, 9999). Property: `mean(whole_post) × TICKET_SCALE` within `±0.5%` of pre-Bernoulli scaled value at sample size N.
- [ ] **TST-LBX-AR-02**: Boundary tests on auto-resolve paths — pre-Bernoulli scaled values of 0, 1, 99, 100, 101, 199, 200. Confirm 0 → 0 deterministic; 100 → 100/100 = 1 whole deterministic; 199 → 1 whole + 99/100 Bernoulli → expected ~1.99 mean.
- [ ] **TST-LBX-AR-03**: Auto-resolve silent-cold-bust regression — force a seed where `futureTickets` pre-Bernoulli is `> 0` and `< TICKET_SCALE`, and the Bernoulli loses (`bits[152..167] % 100 >= frac`). Assert: zero `TicketsQueued` event emit (whole=0); zero `LootBoxWwxrpReward` event emit (NO consolation); zero `wwxrp.mintPrize` invocation; `wwxrp.balanceOf(player)` unchanged.
- [ ] **TST-LBX-AR-04**: Seed-uniqueness regression on all 4 upstream callers — DecimatorModule:594 + DegeneretteModule:786 + StakedDegenerusStonk:672 + DegenerusGame:1721 (5-ETH chunk redemption loop). For each caller, exercise N invocations with synthetically-distinct rngWord inputs; assert per-call Bernoulli outcomes are statistically independent (chi-square).
- [ ] **TST-LBX-AR-05**: `_rollRemainder` invocation regression on auto-resolve — open N auto-resolve lootboxes (via decimator-claim + sDGNRS-redemption); advance to target level; assert `_rollRemainder` is NOT invoked for the resulting player+level queue (since auto-resolve now Bernoulli-rolls at queue time). The mint-boost path is exercised separately (TST-LBX-AR-06) to confirm `_rollRemainder` still fires for mint-boost queues.
- [ ] **TST-LBX-AR-06**: Mint-boost regression — open a mint with `boostBps != 0` that produces a fractional `adjustedQty`; advance to target level; assert `_rollRemainder` STILL fires correctly on the boost-derived remainder per D-40N-MINTBOOST-OUT-01. Confirms v40.0 narrowly retires the auto-resolve lootbox producer without breaking mint-boost.

### TST-JPT-BR — JackpotModule:2216 BAF Bernoulli Tests (test/jackpot/ or test/edge/)

- [x] **TST-JPT-BR-01**: Bernoulli-collapse EV-neutrality property test on JackpotModule ticket-roll path. ≥10,000 seeded `_awardJackpotTickets` invocations across representative pre-Bernoulli scaled values. Property: `mean(whole_post) × TICKET_SCALE` within `±0.5%` of pre-Bernoulli scaled value.
- [x] **TST-JPT-BR-02**: Jackpot silent-cold-bust regression — force a seed where `_jackpotTicketRoll` produces `scaled > 0` and `< TICKET_SCALE`, and Bernoulli loses. Assert: zero `TicketsQueued` event emit; zero `LootBoxWwxrpReward` emit; `wwxrp.balanceOf(player)` unchanged. `JackpotTicketWin` event still emits with `roundedUp=false` per EVT-UNI-04.
- [x] **TST-JPT-BR-03**: Bit-slice `bits[200..215]` independence chi-square — verify the new Bernoulli slice is statistically uncorrelated with the existing bits[0..12] consumers (path/bucket selection). ≥10K seeds; chi-square test.
- [x] **TST-JPT-BR-04**: 2-roll pattern uniqueness — verify the 2 ticket-roll Bernoulli outcomes within a single `_awardJackpotTickets` invocation (L2157 + L2166) are independent. The `EntropyLib.entropyStep` step between L2157 and L2166 evolves entropy, so the two rolls' bits[200..215] slices are uncorrelated.

### TST-EVT-UNI — Event Surface Unification + Sentinel Retirement Tests (test/lootbox/ + test/jackpot/ + test/regression/)

- [ ] **TST-EVT-UNI-01**: Event topic-hash change tests on `LootBoxOpened` + `BurnieLootOpen` + `JackpotTicketWin`. Compute new topic hashes; assert event emissions match the new signatures; assert old topic hashes have zero remaining emit sites.
- [ ] **TST-EVT-UNI-02**: `LootboxTicketRoll` removal regression — assert zero remaining `LootboxTicketRoll` emission sites in the codebase (verified via static-analysis grep + dynamic test sweep across all lootbox paths). Interface signature deleted from `IDegenerusGameLootboxModule.sol`.
- [ ] **TST-EVT-UNI-03**: Sentinel-retirement regression — `_resolveLootboxCommon` no longer branches on `index != type(uint48).max`. Static-analysis or coverage trace confirms the conditional disassembles to a single unified code path. Auto-resolve callers (`resolveLootboxDirect` + `resolveRedemptionLootbox`) pass real `index` (NOT `type(uint48).max`).
- [ ] **TST-EVT-UNI-04**: Manual-path event field-consistency on `LootBoxOpened` — derived `whole = (preRollTickets / 100) + (roundedUp ? 1 : 0)` equals queued ticket count at the level; `preRollTickets` matches scaled-pre value; `lootboxIndex` matches the `index` arg passed to `openLootBox` / `openBurnieLootBox`; consolation correlation (whole=0 + same-tx `LootBoxWwxrpReward`) preserved per v39.0 invariants.
- [ ] **TST-EVT-UNI-05**: Auto-resolve event field-consistency — per plan-phase decision on EVT-UNI-06: if (a) chosen, assert `LootBoxOpened` emit on auto-resolve with correct `preRollTickets` + `roundedUp` fields; if (b) chosen, assert the alternative signal channel emits correctly.
- [ ] **TST-EVT-UNI-06**: Jackpot event field-consistency — `JackpotTicketWin.roundedUp` field present and correctly mirrors the Bernoulli outcome from `_jackpotTicketRoll`.

### TST-CLEAN — JackpotModule Cosmetic + ENT-05 BAF Xorshift Refactor + Wrapper Retirement Tests (test/jackpot/)

- [ ] **TST-CLEAN-01**: ENT-05 BAF xorshift refactor byte-equivalence — pre/post-refactor BAF jackpot outputs match across N seeded `_awardJackpotTickets` invocations. If the refactor changes entropy semantics intentionally, then test asserts the NEW invariant (post-refactor entropy chi-square + seed-uniqueness).
- [ ] **TST-CLEAN-02**: `_queueLootboxTickets` wrapper removal regression — assert zero remaining `_queueLootboxTickets` invocation sites in the codebase post-v40.0 (static-analysis grep). Wrapper function deleted from `JackpotModule.sol`.
- [ ] **TST-CLEAN-03**: Cosmetic `xTICKET_SCALE` cleanup byte-equivalence — pre/post-cleanup function bytecode at L702 + L835 + L1005 matches semantically (no behavior change). Storage layout byte-identical.

### TST-CROSS — Cross-Surface Mixing Test (test/regression/)

- [ ] **TST-CROSS-01**: Same-player cross-surface ticket-award mixing — exercise same player through all RNG-driven ticket-award paths at same target future level: 5 manual lootbox opens (`openLootBox` + `openBurnieLootBox`) + 3 auto-resolve lootbox opens (`resolveLootboxDirect` + `resolveRedemptionLootbox`) + 2 jackpot ticket-roll awards. Assert: all 3 surface families Bernoulli-roll independently (no shared `rem` byte residue accumulation across surfaces; per-resolution whole-ticket commits); mint-boost path mixed in once at the same future level continues to accumulate via `rem` byte per D-40N-MINTBOOST-OUT-01 (only mint-boost contributions go through `_rollRemainder` at activation time).

### BUR — Whole-BURNIE Floor (contracts/modules/DegenerusGameLootboxModule.sol + contracts/modules/DegenerusGameJackpotModule.sol)

- [ ] **BUR-01**: Floor `burnieAmount` at `DegenerusGameLootboxModule.sol:1080` (upstream of `coinflip.creditFlip(player, burnieAmount)`) to whole-BURNIE multiples — `burnieAmount = (burnieAmount / 1 ether) * 1 ether` (or equivalent integer-division floor). The variance-roll-derived BURNIE amount (computed via `_resolveLootboxRoll` at the upstream call sites at lines ~955-1000; flows through `burnieNoMultiplier + burniePresale + bonusBurnie` accumulator) becomes whole-BURNIE only. Sub-1-BURNIE residues evaporate per D-40N-BUR-DUST-01 (user disposition 2026-05-13: "sub 1 burnie amounts are economically negligible so just don't worry about it"). Per-spin per-player dust loss bounded at < 1 BURNIE. NO consolation. NO replacement event. NO cursor-rotation residue redistribution. Existing `LootBoxOpened.burnie` field emits the floored amount (no separate scaled-pre snapshot needed).
- [ ] **BUR-02**: Floor `baseAmount = coinBudget / cap` at `DegenerusGameJackpotModule.sol:1785` to whole-BURNIE multiples — `baseAmount = ((coinBudget / cap) / 1 ether) * 1 ether`. The existing `extra = coinBudget % cap` cursor-rotation `if (extra != 0 && cursor < extra) amount += 1` distribution (line ~1832) retires per D-40N-BUR-FLOOR-01 (the user picked A1 floor-per-winner mechanic, NOT A2 budget-floor-redistribute). When `baseAmount < 1 ether`, all near-future-coin-jackpot winners that day receive 0 BURNIE; the full daily near-future BURNIE jackpot budget evaporates that day. Daily-budget evaporation accepted per D-40N-BUR-DUST-01.
- [ ] **BUR-03**: Floor `perWinner = farBudget / found` at `DegenerusGameJackpotModule.sol:1900` (in `_awardFarFutureCoinJackpot`) to whole-BURNIE multiples — `perWinner = ((farBudget / found) / 1 ether) * 1 ether`. The existing `if (perWinner == 0) return` early-bail at `:1901` extends naturally to the floored case (returns when post-floor perWinner is 0). When `perWinner < 1 ether`, all 1-10 far-future-coin-jackpot winners receive 0 BURNIE; the 25% daily BURNIE budget allocated to far-future evaporates that day. Budget evaporation accepted per D-40N-BUR-DUST-01.
- [ ] **BUR-04**: Storage layout byte-identical at v40 phase-close HEAD vs v39 baseline `6a7455d1` for `DegenerusGameLootboxModule.sol` AND `DegenerusGameJackpotModule.sol` (storage-slot grep proof). Zero new state variables; zero new admin entry points; zero new external mutation entry points; zero new modifiers; zero new events; zero new emit sites. Whole-BURNIE floor is a pure-amount transformation upstream of existing `coinflip.creditFlip(...)` + `coinflip.creditFlipBatch(...)` emit sites + their existing `JackpotBurnieWin` / `LootBoxOpened` / `FarFutureCoinJackpotWinner` event emissions (event-field values reflect the post-floor amount).
- [ ] **BUR-05**: Bytecode delta NET-NEGATIVE at the 3 sites — single integer-division floor adds ~5-15 gas per site at the BURNIE-amount compute point, but eliminates fractional-wei storage in `coinflip.creditFlip` (mint amount stored at integer-1-ether boundaries; smaller calldata size on `creditFlipBatch`). Gas delta reported in commit message.

### TST-BUR — Whole-BURNIE Floor Tests (test/lootbox/ + test/jackpot/)

- [ ] **TST-BUR-01**: LootboxModule:1080 floor regression — exercise N lootbox spins that produce fractional `burnieAmount` (e.g., variance-BPS multiplier producing 1.47 BURNIE on a 1 ETH spin); assert `coinflip.creditFlip(player, ...)` invoked with floored whole-BURNIE value (1 BURNIE); assert player coinflip balance changes by exactly the floored value. Boundary cases: (a) 0.99 BURNIE → 0 (dust evaporates); (b) 1.99 BURNIE → 1 (floor); (c) 2.00 BURNIE → 2 (exact boundary, no change); (d) 0 BURNIE → 0 (existing `if (burnieAmount != 0)` guard preserves no-op). Plus negative assertion: `LootBoxOpened.burnie` event field equals the floored amount (NOT pre-floor amount).
- [ ] **TST-BUR-02**: JackpotModule near-future coin jackpot (`:1842`) floor regression — force a coin budget that produces `baseAmount < 1 ether` (e.g., setup with `coinBudget = 50 BURNIE` and `cap = 100 winners` → `baseAmount = 0.5 BURNIE`); assert all 100 winner emissions either invoke `coinflip.creditFlip(...)` with 0 OR get skipped via `if (winner != address(0) && amount != 0)` guard at L1834; assert daily-budget evaporation observable in accounting (the `coinBudget` allocated for that day is NOT credited to any winner). Plus positive case: budget producing `baseAmount = 1.5 BURNIE` → all 100 winners receive 1 BURNIE; 0.5 BURNIE per winner * 100 winners = 50 BURNIE evaporates that day.
- [ ] **TST-BUR-03**: JackpotModule far-future coin jackpot (`:1900`) floor regression — force a `farBudget` that produces `perWinner < 1 ether` (e.g., `farBudget = 5 BURNIE` / `found = 10 winners` → `perWinner = 0.5 BURNIE`); assert `_awardFarFutureCoinJackpot` early-bails via `if (perWinner == 0) return` (no `creditFlipBatch` invocation OR batch entries are floored to 0). Plus positive case: `farBudget = 25 BURNIE` / `found = 10 winners` → all 10 winners receive 2 BURNIE; 5 BURNIE residue evaporates.
- [ ] **TST-BUR-04**: Whole-BURNIE invariant sweep — exercise all 3 sites with N representative budgets/spins; assert every observable BURNIE-mint amount via `coinflip.creditFlip(...)` + `coinflip.creditFlipBatch(...)` from these 3 sites is a multiple of 1 ether. Static assertion: across the test sweep, `mod(any creditFlip amount, 1 ether) == 0`. Negative cross-site assertion: mint-boost path at `DegenerusGameMintModule.sol:1199` continues emitting fractional-wei `coinflip.creditFlip(buyer, lootboxFlipCredit)` per D-40N-BUR-MINTBOOST-OUT-01 (mint-boost flip-credit not RNG-driven; user-altered input; out of v40.0 BUR scope).

### AUDIT — Delta Audit Terminal (terminal-phase; audit/FINDINGS-v40.0.md)

- [ ] **AUDIT-01**: `audit/FINDINGS-v40.0.md` 9-section deliverable per D-40N-FILES-01 carry. Single FINAL READ-only file at v40.0 closure HEAD (`chmod 444` post-closure-flip). 5-Bucket Severity Rubric carry from v38.0 / D-08.
- [ ] **AUDIT-02**: §3.A row coverage for the 5+ v40.0 phase commits — auto-resolve LootboxModule Bernoulli contract + test commits (Phase 275); JackpotModule:2216 BAF Bernoulli contract + test commits (Phase 276); Event surface unification contract + test commits (Phase 277); JackpotModule cleanup + xorshift refactor contract + test commits (Phase 278); Whole-BURNIE floor contract + test commits (Phase 279). Each commit gets §3.A coverage proportional to surface change.
- [ ] **AUDIT-03**: §4 adversarial surfaces enumerated for v40.0 changes: (a) EV-neutrality of Bernoulli collapse on auto-resolve paths vs cross-lootbox accumulation (v39 manual-path precedent extended); (b) EV-neutrality of Bernoulli collapse on jackpot ticket-roll path; (c) Bit-slice `[152..167]` reuse on auto-resolve (independent of manual-path bits[152..167] consumption due to per-resolution-distinct seed); (d) Bit-slice `[200..215]` independence on jackpot (vs existing bits[0..12] consumers); (e) Silent cold-bust gating predicate on auto-resolve + jackpot (no consolation crossover from v39 manual-path); (f) Event topic-hash change correctness (LootBoxOpened + BurnieLootOpen + JackpotTicketWin signatures + emission sites); (g) Index-sentinel retirement byte-equivalence (no behavior crossover between manual + auto-resolve post-retirement); (h) `_queueLootboxTickets` wrapper retirement + ENT-05 BAF xorshift refactor structural integrity; (i) Mint-boost path byte-equivalent at v40 HEAD (status-quo preservation per D-40N-MINTBOOST-OUT-01); (j) Lootbox spin BURNIE floor at `LootboxModule.sol:1080` — RNG-amount-rounding invariant (per-spin floor preserves variance-roll EV-floor; no consolation; LootBoxOpened.burnie field consistency); (k) JackpotModule near-future coin jackpot (`:1842`) + far-future coin jackpot (`:1900`) BURNIE floor — daily-budget-evaporation ledger when per-winner amount < 1 BURNIE; cursor-rotation residue retirement at near-future; perWinner==0 early-bail at far-future; mint-boost flip-credit non-floor (`MintModule:1199`) status-quo preservation per D-40N-BUR-MINTBOOST-OUT-01.
- [ ] **AUDIT-04**: 3-skill PARALLEL adversarial pass on finished §4 draft per D-271-ADVERSARIAL-01 carry: `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` spawn. `/degen-skeptic` OUT OF SCOPE per D-271-ADVERSARIAL-02 carry. Adversarial-log at `phases/[terminal-phase-id]-01-ADVERSARIAL-LOG.md`; dispositions: zero residual FINDING_CANDIDATE OR explicit RESOLVED_AT_V40 with amendment commit reference.
- [ ] **AUDIT-05**: KI walkthrough EXC-01..04 RE_VERIFIED at v40 HEAD. EXC-04 may demote from `NARROWS` to `NEGATIVE` if JPT-CLEAN-04 ENT-05 BAF xorshift refactor lands and removes the narrows scope. Default zero-promotion path per D-40N-KI-01 carry. Closure verdict in §6b: `N of N KI_ELIGIBLE_PROMOTED; KNOWN_ISSUES_<UNMODIFIED|MODIFIED>`.
- [ ] **AUDIT-06**: Closure signal `MILESTONE_V40_AT_HEAD_<sha>` emitted in §9c. ROADMAP + STATE + MILESTONES + PROJECT closure-flips land atomically post-§9c attestation per D-40N-CLOSURE-01 carry. Forward-cite zero-emission at terminal phase per D-40N-FCITE-01 (carries D-NN-FCITE-01).

### REG — LEAN Regression (terminal-phase; audit/FINDINGS-v40.0.md §5)

- [ ] **REG-01**: v39.0 closure signal `MILESTONE_V39_AT_HEAD_6a7455d1` re-verified non-widening at v40 HEAD. Surface set: manual lootbox path (Bernoulli + consolation + LootboxTicketRoll-replaced-by-LootBoxOpened-fields); bits[152..167] manual-path slice (now shared with auto-resolve in v40 — verify per-resolution seed-uniqueness prevents observable manual-path drift). Lootbox spin BURNIE site at `LootboxModule.sol:1080` newly v40-scoped per BUR-01 — explicitly EXCLUDED from non-widening proof (in-scope mutation). Byte-identical for surfaces NOT in v40 scope (Degenerette + BURNIE coinflip + mint-boost ticket queue + mint-boost flip-credit `MintModule:1199` + WWXRP consolation predicate on manual-path + advance bounty + affiliate DGNRS deity bonus + quest rewards).
- [ ] **REG-02**: v34.0 closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555` re-verified non-widening at v40 HEAD. TraitUtils + `_pickSoloQuadrant` + JackpotBucketLib byte-identical.
- [ ] **REG-03**: KI envelope re-verifications at v40 HEAD — EXC-01..03 NEGATIVE-scope; EXC-04 disposition per JPT-CLEAN-04 ENT-05 BAF xorshift refactor outcome (NARROWS retained OR demoted to NEGATIVE).
- [ ] **REG-04**: Prior-finding spot-check sweep across `audit/FINDINGS-v25.0..v39.0.md` for v40-touched function/surface set. Focus: `_resolveLootboxCommon` (auto-resolve branch additions; manual-path index-sentinel retirement); `_queueTickets` (new auto-resolve + jackpot callsites); `_jackpotTicketRoll` (Bernoulli addition); `LootBoxOpened` / `BurnieLootOpen` / `JackpotTicketWin` event signature additions; `_queueLootboxTickets` retirement; `xTICKET_SCALE` cleanup sites; ENT-05 BAF xorshift refactor; `LootboxModule.sol:1080` BURNIE-credit site (BUR-01 floor); `JackpotModule.sol:1785/:1842` near-future coin jackpot (BUR-02 floor); `JackpotModule.sol:1900/:1922` far-future coin jackpot (BUR-03 floor).

## Acceptance Criteria

A requirement is **Complete** when:
- Code change landed in v40.0 audit-subject HEAD
- Test coverage exists (where applicable) and passes
- Audit §3.A row written; §4 surface attested SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE
- Adversarial-pass disposition: zero residual FINDING_CANDIDATE (or RESOLVED_AT_V40 with amendment commit reference)

A requirement is **RE-DEFERRED-V41+** when:
- Explicit user disposition + path-of-investigation prose in `audit/FINDINGS-v40.0.md` §9
- Specific carry conditions documented

## Decision Anchors (v40.0)

- **D-40N-CLOSURE-01**: Multi-phase shape (surface-split + terminal audit); v33/v34/v35/v37 precedent — NOT v36/v38/v39 single-phase
- **D-40N-CLOSURE-02**: Closure signal `MILESTONE_V40_AT_HEAD_<sha>` emitted in §9c; atomic cross-document flip per v39 P274 Task 3.10 precedent
- **D-40N-GRANULARITY-01**: TICKET-granularity SETTLED — 1 ticket = 4 entries; Bernoulli rounds at ticket granularity; 4× variance vs entry-granularity accepted in exchange for simpler storage / no downstream re-scaling; entry-granularity refactor permanently dropped from roadmap consideration
- **D-40N-SILENT-01**: Auto-resolve + jackpot ticket-roll paths SILENT on cold-bust — no WWXRP consolation, no separate roll event; manual-path keeps `LOOTBOX_WWXRP_CONSOLATION = 1 ether` consolation pattern (carries D-274-WX-AMOUNT-01); asymmetry intentional + documented
- **D-40N-EVT-BREAK-01**: Breaking event topic-hashes ACCEPTED — supersedes v39.0 D-274-NO-EVT-BREAK-01 non-breaking stance + D-274-EVT-ROLL-01 + D-274-EVT-INDEX-SENTINEL-01; `LootboxTicketRoll` retires; fields fold into `LootBoxOpened` / `BurnieLootOpen` / `JackpotTicketWin`; indexer rebuild expected
- **D-40N-SENTINEL-RETIRE-01**: `_resolveLootboxCommon` `index != type(uint48).max` behavior-gate retires — manual + auto-resolve converge on `_queueTickets(whole)` so the gate no longer serves a purpose; `uint48 index` parameter retains event-identifier role; auto-resolve callers pass real index (NOT sentinel); supersedes D-274-MANUAL-ONLY-01
- **D-40N-MINTBOOST-OUT-01**: Mint-boost fractional retirement OUT OF SCOPE for v40.0 (carries D-274-MINTBOOST-OUT-01) — `DegenerusGameMintModule.sol:1142` `_queueTicketsScaled` + `_rollRemainder` + `rem` byte STAY; deterministic dust accumulator, not RNG-driven; user disposition 2026-05-13 "not counting ticket mints"
- **D-40N-AR-EMIT-01**: Auto-resolve `LootBoxOpened` emission shape DEFERRED to plan-phase — options (a) add emission to `resolveLootboxDirect` + `resolveRedemptionLootbox`, OR (b) keep auto-resolve silent on `LootBoxOpened` and surface `(preRollTickets, roundedUp)` via alternative signal (e.g., `TicketsQueued` extension); plan-phase picks based on gas / event-surface uniformity tradeoff
- **D-40N-FILES-01**: Single terminal audit deliverable `audit/FINDINGS-v40.0.md`; D-NN-FILES-01 carry
- **D-40N-FCITE-01**: Forward-cite zero-emission at terminal phase; D-271-FCITE-01 → D-272-FCITE-01 → D-274-FCITE-01 carry chain
- **D-40N-KI-01**: Default zero-promotion path for `KNOWN-ISSUES.md`; D-272-KI-01 → D-274-KI-01 carry; EXC-04 disposition per JPT-CLEAN-04 outcome
- **D-40N-APPROVAL-01**: Per-commit user approval for `contracts/` + `test/` writes; `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` + `feedback_manual_review_before_push.md` carry
- **D-40N-ADVERSARIAL-01**: 3-skill PARALLEL adversarial spawn on finished §4 draft; D-271-ADVERSARIAL-01 → D-272-ADVERSARIAL-01 → D-274-ADVERSARIAL-01 carry; `/degen-skeptic` OUT OF SCOPE per D-271-ADVERSARIAL-02 carry
- **D-40N-SEV-01**: 5-Bucket Severity Rubric carry from v38.0 / D-08
- **D-40N-LBX02-OUT-01**: LBX-02 fixture-coverage gap RE-DEFERRED-V41+ at v40.0 open; carries D-274-LBX02-OUT-01
- **D-40N-BUR-FLOOR-01**: A1 floor-per-winner mechanic at all 3 RNG-influenced BURNIE-award sites — `LootboxModule:1080` (lootbox spin BURNIE) + `JackpotModule:1842` (near-future coin jackpot baseAmount) + `JackpotModule:1922` (far-future coin jackpot perWinner). NOT A2 budget-floor-redistribute; NOT A3 winner-count-adjust. Per-spin / per-winner integer-1-ether floor applied at the amount-compute point upstream of `coinflip.creditFlip(...)` / `coinflip.creditFlipBatch(...)`. User disposition 2026-05-13: "round all BURNIE down to nearest coin (1eth)" + "floor-only".
- **D-40N-BUR-DUST-01**: Sub-1-BURNIE residues evaporate per user disposition 2026-05-13: "sub 1 burnie amounts are economically negligible so just don't worry about it". Per-spin per-player loss bounded < 1 BURNIE at LootboxModule:1080. Daily-budget evaporation accepted at both JackpotModule sites when `baseAmount < 1 ether` (near-future) OR `perWinner < 1 ether` (far-future) — full daily near-future BURNIE jackpot budget OR full 25% far-future BURNIE allocation lost on low-pool days. The existing `if (perWinner == 0) return` early-bail at `JackpotModule:1901` and the `if (winner != address(0) && amount != 0)` emit-guard at `:1834` handle the zero-amount case without explicit budget-residue accounting.
- **D-40N-BUR-SILENT-01**: No WWXRP consolation, no replacement event, no cursor-rotation residue redistribution at any of the 3 BUR sites. Extends D-40N-SILENT-01 (auto-resolve + jackpot ticket-roll silent on cold-bust) to the whole-BURNIE-floor surface. The existing `LootBoxOpened.burnie` + `JackpotBurnieWin.amount` + `FarFutureCoinJackpotWinner.perWinner` event fields emit post-floor amounts (no separate scaled-pre snapshot needed).
- **D-40N-BUR-MINTBOOST-OUT-01**: Mint-boost flip-credit at `DegenerusGameMintModule.sol:1199` `coinflip.creditFlip(buyer, lootboxFlipCredit)` explicitly EXCLUDED from BUR scope — `lootboxFlipCredit` derives from deterministic mint-amount arithmetic (user-altered input), NOT RNG; out of v40.0 "RNG-driven BURNIE awards" framing. Carries the same out-of-scope discipline as D-40N-MINTBOOST-OUT-01 (mint-boost ticket queue). Also explicitly EXCLUDED: `BurnieCoinflip.sol:409/770/789` `burnie.mintForGame(...)` daily-coinflip claim/mint (deterministic per daily result); `DegenerusGameAdvanceModule.sol:191/227/477/886` advance bounty (player-altered timing); `DegenerusQuests.sol:514/629/739/887/890/954/1885` quest rewards (deterministic quest-completion criteria); `DegenerusGame.sol:1463` + `DegenerusAffiliate.sol:777` affiliate DGNRS deity bonus (deterministic on activity score).


## Traceability

Every v40.0 requirement maps to exactly one phase. Total coverage: 65/65.

| Requirement | Phase | Surface |
|-------------|-------|---------|
| LBX-AR-01 | Phase 275 | Auto-resolve LootboxModule Bernoulli (contract) |
| LBX-AR-02 | Phase 275 | Auto-resolve LootboxModule Bernoulli (contract) |
| LBX-AR-03 | Phase 275 | Auto-resolve LootboxModule Bernoulli (contract) |
| LBX-AR-04 | Phase 275 | Auto-resolve LootboxModule Bernoulli (contract) |
| LBX-AR-05 | Phase 275 | Auto-resolve LootboxModule Bernoulli (contract) |
| LBX-AR-06 | Phase 275 | Auto-resolve LootboxModule Bernoulli (contract) |
| TST-LBX-AR-01 | Phase 275 | Auto-resolve LootboxModule Bernoulli (test) |
| TST-LBX-AR-02 | Phase 275 | Auto-resolve LootboxModule Bernoulli (test) |
| TST-LBX-AR-03 | Phase 275 | Auto-resolve LootboxModule Bernoulli (test) |
| TST-LBX-AR-04 | Phase 275 | Auto-resolve LootboxModule Bernoulli (test) |
| TST-LBX-AR-05 | Phase 275 | Auto-resolve LootboxModule Bernoulli (test) |
| TST-LBX-AR-06 | Phase 275 | Auto-resolve LootboxModule Bernoulli (test) |
| JPT-BR-01 | Phase 276 | JackpotModule:2216 BAF Bernoulli (contract) |
| JPT-BR-02 | Phase 276 | JackpotModule:2216 BAF Bernoulli (contract) |
| JPT-BR-03 | Phase 276 | JackpotModule:2216 BAF Bernoulli (contract) |
| JPT-BR-04 | Phase 276 | JackpotModule:2216 BAF Bernoulli (contract) |
| JPT-BR-05 | Phase 276 | JackpotModule:2216 BAF Bernoulli (contract) |
| JPT-BR-06 | Phase 276 | JackpotModule:2216 BAF Bernoulli (contract) |
| TST-JPT-BR-01 | Phase 276 | JackpotModule:2216 BAF Bernoulli (test) |
| TST-JPT-BR-02 | Phase 276 | JackpotModule:2216 BAF Bernoulli (test) |
| TST-JPT-BR-03 | Phase 276 | JackpotModule:2216 BAF Bernoulli (test) |
| TST-JPT-BR-04 | Phase 276 | JackpotModule:2216 BAF Bernoulli (test) |
| EVT-UNI-01 | Phase 277 | Event surface unification + sentinel retirement (contract) |
| EVT-UNI-02 | Phase 277 | Event surface unification + sentinel retirement (contract) |
| EVT-UNI-03 | Phase 277 | Event surface unification + sentinel retirement (contract) |
| EVT-UNI-04 | Phase 277 | Event surface unification + sentinel retirement (contract) |
| EVT-UNI-05 | Phase 277 | Event surface unification + sentinel retirement (contract) |
| EVT-UNI-06 | Phase 277 | Event surface unification + sentinel retirement (contract) |
| EVT-UNI-07 | Phase 277 | Event surface unification + sentinel retirement (contract) |
| EVT-UNI-08 | Phase 277 | Event surface unification + sentinel retirement (contract) |
| TST-EVT-UNI-01 | Phase 277 | Event surface unification + sentinel retirement (test) |
| TST-EVT-UNI-02 | Phase 277 | Event surface unification + sentinel retirement (test) |
| TST-EVT-UNI-03 | Phase 277 | Event surface unification + sentinel retirement (test) |
| TST-EVT-UNI-04 | Phase 277 | Event surface unification + sentinel retirement (test) |
| TST-EVT-UNI-05 | Phase 277 | Event surface unification + sentinel retirement (test) |
| TST-EVT-UNI-06 | Phase 277 | Event surface unification + sentinel retirement (test) |
| JPT-CLEAN-01 | Phase 278 | JackpotModule cleanup + ENT-05 refactor + wrapper retirement (contract) |
| JPT-CLEAN-02 | Phase 278 | JackpotModule cleanup + ENT-05 refactor + wrapper retirement (contract) |
| JPT-CLEAN-03 | Phase 278 | JackpotModule cleanup + ENT-05 refactor + wrapper retirement (contract) |
| JPT-CLEAN-04 | Phase 278 | JackpotModule cleanup + ENT-05 refactor + wrapper retirement (contract) |
| JPT-CLEAN-05 | Phase 278 | JackpotModule cleanup + ENT-05 refactor + wrapper retirement (contract) |
| JPT-CLEAN-06 | Phase 278 | JackpotModule cleanup + ENT-05 refactor + wrapper retirement (contract) |
| TST-CLEAN-01 | Phase 278 | JackpotModule cleanup + ENT-05 refactor + wrapper retirement (test) |
| TST-CLEAN-02 | Phase 278 | JackpotModule cleanup + ENT-05 refactor + wrapper retirement (test) |
| TST-CLEAN-03 | Phase 278 | JackpotModule cleanup + ENT-05 refactor + wrapper retirement (test) |
| TST-CROSS-01 | Phase 278 | Cross-surface ticket-award mixing regression (test; sequenced after the 3 RNG-driven ticket surfaces land) |
| BUR-01 | Phase 279 | Lootbox spin BURNIE floor at LootboxModule:1080 (contract) |
| BUR-02 | Phase 279 | JackpotModule near-future coin jackpot baseAmount floor at :1842 (contract) |
| BUR-03 | Phase 279 | JackpotModule far-future coin jackpot perWinner floor at :1922 (contract) |
| BUR-04 | Phase 279 | BUR storage byte-identical + zero-new-event invariant (contract) |
| BUR-05 | Phase 279 | BUR bytecode delta NET-NEGATIVE (contract) |
| TST-BUR-01 | Phase 279 | Lootbox BURNIE floor regression (test) |
| TST-BUR-02 | Phase 279 | Near-future coin jackpot floor + budget-evaporation regression (test) |
| TST-BUR-03 | Phase 279 | Far-future coin jackpot floor + early-bail regression (test) |
| TST-BUR-04 | Phase 279 | Whole-BURNIE invariant sweep across all 3 BUR sites (test) |
| AUDIT-01 | Phase 280 | Terminal delta audit + findings consolidation |
| AUDIT-02 | Phase 280 | Terminal delta audit + findings consolidation |
| AUDIT-03 | Phase 280 | Terminal delta audit + findings consolidation |
| AUDIT-04 | Phase 280 | Terminal delta audit + findings consolidation |
| AUDIT-05 | Phase 280 | Terminal delta audit + findings consolidation |
| AUDIT-06 | Phase 280 | Terminal delta audit + findings consolidation |
| REG-01 | Phase 280 | LEAN regression appendix §5 |
| REG-02 | Phase 280 | LEAN regression appendix §5 |
| REG-03 | Phase 280 | LEAN regression appendix §5 |
| REG-04 | Phase 280 | LEAN regression appendix §5 |

### Per-phase requirement counts

| Phase | Contract Reqs | Test Reqs | Audit/Regression Reqs | Total |
|-------|---------------|-----------|----------------------|-------|
| 275 — LBX-AR | 6 (LBX-AR-01..06) | 6 (TST-LBX-AR-01..06) | — | 12 |
| 276 — JPT-BR | 6 (JPT-BR-01..06) | 4 (TST-JPT-BR-01..04) | — | 10 |
| 277 — EVT-UNI | 8 (EVT-UNI-01..08) | 6 (TST-EVT-UNI-01..06) | — | 14 |
| 278 — JPT-CLEAN | 6 (JPT-CLEAN-01..06) | 4 (TST-CLEAN-01..03 + TST-CROSS-01) | — | 10 |
| 279 — BUR | 5 (BUR-01..05) | 4 (TST-BUR-01..04) | — | 9 |
| 280 — Terminal | — | — | 10 (AUDIT-01..06 + REG-01..04) | 10 |
| **Total** | **31** | **24** | **10** | **65** |

### Phase dependency graph

```
275 (LBX-AR) ──┐
               ├──> 277 (EVT-UNI) ──┐
276 (JPT-BR) ──┤                    │
               │                    ├──> 280 (Terminal)
               └──> 278 (JPT-CLEAN) ┤
                                    │
279 (BUR) ──────────────────────────┘
```

- Phase 275 and Phase 276 are independent surfaces and can be planned/executed in parallel from a content-dependency perspective (per-commit USER-APPROVAL gates per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` discipline sequence wall-clock execution).
- Phase 277 (EVT-UNI) requires both Phase 275 + Phase 276: sentinel retirement (EVT-UNI-05) needs manual + auto-resolve converged on `_queueTickets(whole)` (LBX-AR-02 lands the auto-resolve convergence); `JackpotTicketWin.roundedUp` field addition (EVT-UNI-04) needs Phase 276 JPT-BR-01 Bernoulli outcome to surface.
- Phase 278 (JPT-CLEAN) requires Phase 276 for `_queueLootboxTickets` wrapper retirement (JPT-CLEAN-05) since `JackpotModule.sol:2216` is the wrapper's only caller — replacing it with direct `_queueTickets(whole)` is what makes the wrapper dead code. The cross-surface regression TST-CROSS-01 additionally requires Phase 275 + Phase 277 in final state.
- Phase 279 (BUR) is content-independent of Phases 275-278 — touches different sites inside LootboxModule (`:1080` vs `_resolveLootboxCommon` auto-resolve branch) and JackpotModule (`:1842/:1922` near/far-future coin jackpot vs `:2186/:2216` BAF ticket-roll). Sequences after Phase 278 for clean linear contract-mutation history; could in principle run in parallel.
- Phase 280 (Terminal) requires all 5 surface phases landed (audit baseline is the post-Phase-279 HEAD).

### Coverage verification

- ✓ All 65 v40.0 requirements mapped to exactly one phase
- ✓ Zero orphaned requirements (no requirement unmapped)
- ✓ Zero duplicate mappings (no requirement appears in multiple phases)
- ✓ Phase 280 success criteria reference exact REQ-IDs from Phases 275-279 phase commits in §3.A row coverage

### Acceptance status convention

Per `## Acceptance Criteria` above, each requirement is **Complete** when code+test+audit all attest the surface, OR **RE-DEFERRED-V41+** with user disposition + path-of-investigation prose in `audit/FINDINGS-v40.0.md` §9. Statuses populate at v40.0 closure via terminal-phase commit-readiness register §9.NN.
