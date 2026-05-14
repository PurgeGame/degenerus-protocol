# Degenerus Protocol — Audit Repository

## What This Is

Smart contract audit repository for the Degenerus Protocol — an on-chain ETH game with repeating levels, prize pools, BURNIE token economy, DGNRS/sDGNRS governance tokens, and a comprehensive deity pass system. Contains all protocol contracts, deploy scripts, tests (Hardhat + Foundry fuzz), and audit documentation.

## Core Value

Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## Current State

**Active milestone:** v40.0 — Unified Whole-Ticket Award Protocol + Whole-BURNIE Floor (started 2026-05-13)
**Last shipped:** v39.0 — Lootbox Whole-Ticket Rounding + WWXRP Consolation (2026-05-13; closure signal `MILESTONE_V39_AT_HEAD_6a7455d1`)
**Prior shipped:** v38.0 — Always-Hero Simplification + Maximal Dead-Code Cleanup (2026-05-11; closure signal `MILESTONE_V38_AT_HEAD_06623edb`)
**Prior shipped:** v37.0 — Degenerette Recalibration + Maintenance Bundle (2026-05-11; closure signal `MILESTONE_V37_AT_HEAD_2654fcc2`)
**Prior shipped:** v36.0 — Lootbox-Path Entropy Refactor (2026-05-10; closure signal `MILESTONE_V36_AT_HEAD_1c0f09132d7439af9881c56fe197f81757f8164a`)
**Contract HEAD anchor (v39.0 closure):** `6a7455d1` (closure signal `MILESTONE_V39_AT_HEAD_6a7455d1`; intervening Phase 273 BAF-credit-routing-fix commits `ff929948` + `e9807891` + `e04d3333` + `1eb1ecb5` folded into v39.0 delta audit as included-since-baseline per D-274-BAF273-INCLUDE-01; surface-coverage attestation only)

## Current Milestone: v40.0 Unified Whole-Ticket Award Protocol + Whole-BURNIE Floor

**Goal:** Retire fractional-residue ticket queuing across all RNG-driven ticket-award surfaces (auto-resolve lootbox paths + jackpot ticket-roll path); land Bernoulli whole-ticket collapse at TICKET granularity (1 ticket = 4 entries — status quo formally settled per D-40N-GRANULARITY-01); unify the event surface by folding remainder visibility into existing per-action events (`LootBoxOpened` / `BurnieLootOpen` / `JackpotTicketWin`) and retiring the v39.0-additive `LootboxTicketRoll` event; retire the v39.0 `index != type(uint48).max` behavior-gating sentinel on `_resolveLootboxCommon` as manual + auto-resolve converge to the same `_queueTickets(whole)` model; bundle cosmetic xTICKET_SCALE cleanup + ENT-05 BAF xorshift refactor + `_queueLootboxTickets` wrapper retirement. **Plus whole-BURNIE-coin floor at 3 RNG-influenced BURNIE-award sites** — lootbox spin BURNIE (`LootboxModule:1080`) + near-future coin jackpot baseAmount (`JackpotModule:1842`) + far-future coin jackpot perWinner (`JackpotModule:1922`) — applying A1 floor-per-winner mechanic per D-40N-BUR-FLOOR-01 (sub-1-BURNIE residues evaporate; budget evaporation on low-pool jackpot days accepted per D-40N-BUR-DUST-01). Mint-boost ticket queuing (`MintModule:1142`) + mint-boost flip-credit (`MintModule:1199`) + daily-coinflip claim (`BurnieCoinflip:409/770/789`) + advance bounty + quest rewards + affiliate DGNRS deity bonus all explicitly EXCLUDED per D-40N-MINTBOOST-OUT-01 + D-40N-BUR-MINTBOOST-OUT-01 — deterministic dust accumulators on user-altered or system-deterministic inputs; not RNG-driven. Multi-phase shape (5 surface-split phases + 1 terminal audit phase = 6 phases per D-40N-CLOSURE-01) per v33/v34/v35/v37 precedent — NOT the v36/v38/v39 single-phase pattern.

**Audit baseline:** v39.0 closure HEAD `MILESTONE_V39_AT_HEAD_6a7455d1`.

**Target features:**

- **Auto-resolve LootboxModule Bernoulli extension** (`contracts/modules/DegenerusGameLootboxModule.sol` `_resolveLootboxCommon` auto-resolve branch + callers `resolveLootboxDirect` + `resolveRedemptionLootbox`): apply Bernoulli round-up at `_queueTicketsScaled` site (L1068) using `bits[152..167]` of per-resolution seed (16-bit slice for <0.10% relative bias — same bit-width as v39.0 manual-path per D-274-BIT-SLICE-01 v39 supersession). Replace `_queueTicketsScaled` call with `_queueTickets(whole)`. SILENT — no WWXRP consolation, no separate roll event. Net gas-NEUTRAL when factoring eliminated `_rollRemainder` consumption at trait-assignment time. Seed-uniqueness verified safe on all 4 upstream callers per v39 close trace (DecimatorModule:594 single-shot per `claimDecimatorJackpot(lvl)`, rngWord from per-level storage; DegeneretteModule:786 single-shot per payout call; StakedDegenerusStonk:672 single-shot per redemption, entropy = keccak(rngWord, player); DegenerusGame:1721 redemption-loop wrapper looping in 5-ETH chunks but EVOLVING rngWord per iteration via `rngWord = keccak256(abi.encode(rngWord))` at L1769). Supersedes D-274-AUTORESOLVE-OUT-01 + D-274-MANUAL-ONLY-01.

- **JackpotModule:2216 BAF small-lootbox Bernoulli** (`contracts/modules/JackpotModule.sol` `_jackpotTicketRoll` at L2186): apply Bernoulli round-up using `bits[200..215]` of the existing `entropy` chain (180+ bits separated from current bits[0..12] consumers; 16-bit slice for <0.10% relative bias). Replace `_queueLootboxTickets` wrapper call at L2216 with direct `_queueTickets(whole)`. Net gas-NEGATIVE. Per-roll uniqueness already guaranteed by `EntropyLib.entropyStep` between the 2-roll pattern at `_awardJackpotTickets` L2157/L2166. SILENT cold-bust (no consolation); roll outcome surfaces via `JackpotTicketWin` event field addition (target feature 3). Supersedes the L2216 portion of D-274-JACKPOT-OUT-01.

- **Event surface unification — breaking topic-hashes** (`contracts/modules/DegenerusGameLootboxModule.sol` + `contracts/modules/JackpotModule.sol` + `contracts/interfaces/IDegenerusGameLootboxModule.sol` + jackpot interface): drop the v39.0-additive `LootboxTicketRoll` event entirely (4 fields `player`, `lootboxIndex`, `preRollTickets`, `roundedUp` retire); fold `(uint32 preRollTickets, bool roundedUp)` directly into `LootBoxOpened` + `BurnieLootOpen` (manual-path emission semantics gain new fields; auto-resolve emission shape TBD by plan-phase — `LootBoxOpened` per-resolution emission likely added since auto-resolve currently lacks a per-resolution event); add `bool roundedUp` to `JackpotTicketWin`. Retire the `index != type(uint48).max` sentinel parameter on `_resolveLootboxCommon` — manual + auto-resolve converge on `_queueTickets(whole)` so the behavior gate no longer serves a purpose; the `uint48 index` parameter retains its event-emission identifier role but the sentinel-skip branch deletes. Saves ~1,350 gas per manual lootbox open (no separate LOG3). Pre-launch supersession of D-274-EVT-ROLL-01 + D-274-EVT-INDEX-SENTINEL-01 + D-274-NO-EVT-BREAK-01 non-breaking stance — no live indexer impact; v40.0 will require indexer rebuild against new topic-hashes regardless. Breaking topic-hashes accepted per D-40N-EVT-BREAK-01.

- **JackpotModule cosmetic xTICKET_SCALE cleanup + ENT-05 BAF xorshift refactor + `_queueLootboxTickets` retirement** (`contracts/modules/JackpotModule.sol`): cosmetic `xTICKET_SCALE` cleanups at L702 + L835 + L1005 (already deferred per D-274-JACKPOT-OUT-01); ENT-05 BAF xorshift refactor (deferred since v36.0); retire `_queueLootboxTickets` wrapper (now unused after the auto-resolve + jackpot Bernoulli surfaces land — the wrapper's whole purpose was to gate-keep scaled-vs-whole queuing in the legacy fractional model).

- **Whole-BURNIE-coin floor at 3 RNG-influenced BURNIE-award sites** (`contracts/modules/DegenerusGameLootboxModule.sol` + `contracts/modules/DegenerusGameJackpotModule.sol`): apply A1 floor-per-winner mechanic per D-40N-BUR-FLOOR-01 — `burnieAmount` at `LootboxModule.sol:1080` upstream of `coinflip.creditFlip(...)` (lootbox spin BURNIE variance roll), `baseAmount = coinBudget / cap` at `JackpotModule.sol:1785` (near-future coin jackpot per-winner amount), `perWinner = farBudget / found` at `JackpotModule.sol:1900` (far-future coin jackpot per-winner amount). Each floored to whole-BURNIE multiples (1 BURNIE = 1 ether) via integer-division floor before `coinflip.creditFlip(...)` / `coinflip.creditFlipBatch(...)` invocation. Sub-1-BURNIE residues evaporate per D-40N-BUR-DUST-01 ("sub 1 burnie amounts are economically negligible" per user disposition 2026-05-13). Per-spin per-player dust loss bounded < 1 BURNIE at LootboxModule:1080; daily-budget evaporation accepted at both JackpotModule sites when per-winner amount < 1 BURNIE (the existing `if (perWinner == 0) return` early-bail + `if (winner != address(0) && amount != 0)` emit-guard handle zero-amount cases). NO consolation, NO replacement event, NO cursor-rotation residue redistribution per D-40N-BUR-SILENT-01 (extends D-40N-SILENT-01 silent-on-cold-bust pattern to BURNIE-floor surface). Mint-boost flip-credit at `DegenerusGameMintModule.sol:1199` + daily-coinflip claim/mint at `BurnieCoinflip.sol:409/770/789` + advance bounty at `DegenerusGameAdvanceModule.sol` + quest rewards at `DegenerusQuests.sol` + affiliate DGNRS deity bonus all explicitly EXCLUDED per D-40N-BUR-MINTBOOST-OUT-01 (deterministic on user-altered or system-deterministic inputs; not RNG-amount; out of v40.0 "RNG-driven BURNIE awards" framing).

- **Test coverage** (per phase): (a) Bernoulli EV-neutrality property tests across many seeds on auto-resolve + jackpot ticket-roll paths; (b) silent-cold-bust regression tests on auto-resolve + jackpot — confirm zero WWXRP consolation mint, zero extra event emission; (c) bit-slice independence chi-square (bits[152..167] reuse on auto-resolve + bits[200..215] on jackpot vs existing bits[0..12]); (d) event topic-hash change tests on `LootBoxOpened` + `BurnieLootOpen` + `JackpotTicketWin`; (e) `LootboxTicketRoll` removal regression — zero remaining emission sites; (f) cross-mixing test — same player path mixing manual + auto-resolve + jackpot ticket-award; confirm all three paths Bernoulli-roll independently; (g) ENT-05 BAF byte-equivalence pre/post-refactor + post-refactor entropy chi-square + seed-uniqueness; (h) `_queueLootboxTickets` wrapper removal regression.

- **Delta audit + findings consolidation (terminal phase)**: single `audit/FINDINGS-v40.0.md` 9-section deliverable; v38.0 5-Bucket Severity Rubric carry; `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` PARALLEL adversarial pass on the finished §4 draft per D-271-ADVERSARIAL-01 carry (`/degen-skeptic` OUT OF SCOPE per D-271-ADVERSARIAL-02 carry); LEAN regression REG-01 (v39.0 closure non-widening for v39-touched surfaces NOT in v40 scope) + REG-02 (v34.0 closure non-widening) + REG-04 prior-finding spot-checks across `audit/FINDINGS-v25..v39.0.md`; KI walkthrough EXC-01..04 RE_VERIFIED; closure signal `MILESTONE_V40_AT_HEAD_<sha>` + ROADMAP/STATE/MILESTONES flips.

**Key context / constraints:**
- Pre-launch posture preserved — no live volume, no migration concerns; breaking event topic-hashes accepted per D-40N-EVT-BREAK-01
- Cross-repo READ-only pattern: `contracts/` + `test/` writes via per-commit user approval per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` (carry from v34..v39)
- Single-file terminal audit deliverable per D-NN-FILES-01 carry; forward-cite zero-emission per D-NN-FCITE-01 carry (terminal phase)
- Adversarial-pass timing: SEQUENTIAL after full §4 draft; 3-skill PARALLEL spawn red-teams the FINISHED draft per D-271-ADVERSARIAL-01 + D-271-ADVERSARIAL-03 carry
- Inline-execution mode at execute-phase open per D-271-EXEC-01 default carry
- **Multi-phase shape** (NOT v36/v38/v39 single-phase). Roadmapper will derive final phase split; expected surfaces: auto-resolve lootbox Bernoulli / JackpotModule BAF Bernoulli / event surface unification + sentinel retirement / JackpotModule cosmetic cleanup + ENT-05 BAF xorshift refactor / terminal audit deliverable
- **Granularity decision locked at TICKET granularity** per D-40N-GRANULARITY-01 — 1 ticket = 4 entries; Bernoulli rounds at ticket granularity; 4× variance vs entry-granularity accepted in exchange for simpler storage / no downstream re-scaling; entry-granularity refactor permanently dropped from roadmap consideration
- **Silent on auto-resolve + jackpot cold-bust** per D-40N-SILENT-01 — no WWXRP consolation, no separate roll event; auto-resolve + jackpot ticket-roll resolution happens without explicit player intent at the moment of resolution, so the v39.0 manual-path "cold bust UX" framing does NOT apply
- **No consolation parity with v39.0 manual-path** — manual-path keeps `LOOTBOX_WWXRP_CONSOLATION = 1 ether` mint on cold-bust; auto-resolve + jackpot get nothing; asymmetry intentional + documented
- **Mint-boost retention** per D-40N-MINTBOOST-OUT-01 — `_queueTicketsScaled` + `_rollRemainder` + `rem` byte STAY for `DegenerusGameMintModule.sol:1142`; deterministic dust accumulator, not RNG-driven; carries D-274-MINTBOOST-OUT-01 status quo
- **BURNIE-floor mechanic locked at A1 floor-per-winner** per D-40N-BUR-FLOOR-01 — applied at all 3 RNG-influenced BURNIE-award sites (LootboxModule:1080 + JackpotModule:1842 + JackpotModule:1922). NOT A2 budget-floor-redistribute; NOT A3 winner-count-adjust. User disposition 2026-05-13: "floor-only"
- **BURNIE-dust evaporation** per D-40N-BUR-DUST-01 — sub-1-BURNIE residues evaporate; daily-budget evaporation accepted on low-pool jackpot days when per-winner amount < 1 BURNIE. User disposition 2026-05-13: "sub 1 burnie amounts are economically negligible so just don't worry about it"
- **BURNIE-floor silent posture** per D-40N-BUR-SILENT-01 — no WWXRP consolation, no replacement event, no cursor-rotation residue redistribution at any of the 3 BUR sites; extends D-40N-SILENT-01 silent-on-cold-bust pattern to BURNIE-floor surface
- **Deterministic + player-alterable BURNIE-award sites OUT OF SCOPE** per D-40N-BUR-MINTBOOST-OUT-01 — mint-boost flip-credit (`MintModule:1199`) + daily-coinflip claim/mint (`BurnieCoinflip:409/770/789`) + advance bounty (`AdvanceModule:191/227/477/886`) + quest rewards (`DegenerusQuests:514/629/739/887/890/954/1885`) + affiliate DGNRS deity bonus (`DegenerusGame:1463` + `DegenerusAffiliate:777`) all retain status-quo fractional emission. User disposition 2026-05-13: "anywhere that we award BURNIE in random amounts" — scope narrows to RNG-amount-only sites
- **Sentinel retirement** per D-40N-SENTINEL-RETIRE-01 — `_resolveLootboxCommon` `index != type(uint48).max` behavior gate removes; manual + auto-resolve callers all pass real index for event emission; auto-resolve callers no longer pass `type(uint48).max`

## Completed Milestone: v39.0 Lootbox Whole-Ticket Rounding + WWXRP Consolation

**Goal:** On MANUAL lootbox opens (`openLootBox` + `openBurnieLootBox` only), replace fractional-residue accumulation with a single Bernoulli round-up at open time, queue whole tickets, and pay a WWXRP consolation when the ticket-path produces sub-1 ticket and the round-up Bernoulli fails. Surface remainder visibility through a new additive `LootboxTicketRoll` event. Auto-resolve paths (`resolveLootboxDirect` decimator-claim + `resolveRedemptionLootbox` sDGNRS-redemption) explicitly UNCHANGED — they keep scaled queuing + activation-time fractional resolution. NO breaking change to existing events. Single-phase patch shape (mirrors v36.0 Phase 266 + v38.0 Phase 272 precedent).

**Audit baseline:** v38.0 closure HEAD `MILESTONE_V38_AT_HEAD_06623edb`. Intervening commits (`ff929948` Phase 273 BAF credit routing contract patch + `e9807891` BAF-ROUTE-06/07/08 test expansion + `e04d3333` Phase 273 SUMMARY + `1eb1ecb5` `_livenessTriggered` NatSpec clarification) sit between baseline and v39.0 audit-subject HEAD; they are pre-shipped Phase 273 maintenance and fold into the v39.0 delta-audit baseline naturally (no requirements line items reopen — surface-coverage attestation only).

**Target features:**

- **Manual-path whole-ticket Bernoulli collapse** (`contracts/modules/DegenerusGameLootboxModule.sol` `_resolveLootboxCommon`): retain scaled-space accumulation across `amountFirst`/`amountSecond` branches and through the distress-mode bonus on BOTH paths (preserves precision; small bonuses don't truncate to 0). Then branch on `index != type(uint48).max`: MANUAL — Bernoulli collapse to whole tickets via floor + round-up on the fractional remainder using `bits[152..159]` of the per-resolution seed (previously unallocated; primary chunk consumed 152/256 bits), then queue via `_queueTickets` (whole-ticket queue helper) which emits `TicketsQueued(buyer, level, qty)`. AUTO-RESOLVE — call `_queueTicketsScaled` as today (status quo; emits `TicketsQueuedScaled`). Bit-allocation NatSpec adds `bits[152..159] fracRoundUp % 100 (manual-path ticket whole-collapse)` entry; total primary-chunk consumption 160/256 (slice consumed on manual paths only).
- **New `LootboxTicketRoll` event** (`contracts/modules/DegenerusGameLootboxModule.sol` + `contracts/interfaces/IDegenerusGameLootboxModule.sol`): `event LootboxTicketRoll(address indexed player, uint48 indexed lootboxIndex, uint32 preRollTickets, bool roundedUp);` — fires once per MANUAL lootbox open that lands on the ticket-path with non-zero pre-Bernoulli scaled value. Provides remainder-outcome visibility so UI can show "you rolled 2.47, won the round-up, got 3" or "you rolled 2.47, lost the round-up, got 2 + WWXRP consolation". Threads through `_resolveLootboxCommon` via new `uint48 index` parameter (dual-purpose: identifies the lootbox in the event AND gates the behavioral split between manual and auto-resolve flows); `openLootBox` / `openBurnieLootBox` pass their real index; `resolveLootboxDirect` / `resolveRedemptionLootbox` pass `type(uint48).max` as sentinel AND skip emission. Consumers derive `whole = (preRollTickets/100) + (roundedUp ? 1 : 0)` and infer consolation from `whole == 0` + same-tx `LootBoxWwxrpReward`. Minimal 4-field schema per user disposition 2026-05-13.
- **WWXRP consolation for manual-path cold-bust outcomes** (same module, same function, MANUAL branch only): when `futureTickets` (scaled) was non-zero pre-Bernoulli but `whole == 0` post-Bernoulli — ticket-path was selected, produced sub-1 scaled count, AND the round-up Bernoulli failed — mint `LOOTBOX_WWXRP_CONSOLATION = 1 ether` (matches existing 10%-path `LOOTBOX_WWXRP_PRIZE`) via `wwxrp.mintPrize(player, amount)` and emit `LootBoxWwxrpReward(player, day, amount, LOOTBOX_WWXRP_CONSOLATION)` (reuse existing event signature). Auto-resolve paths NEVER pay consolation regardless of pre-Bernoulli state. Manual-path zero-from-the-start cases (ticket-path not selected; OR `_lootboxTicketCount` truncated to 0 from a degenerate-tiny budget) also excluded.
- **NO breaking event changes**: `LootBoxOpened.futureTickets` continues emitting the post-distress scaled value (×100) on BOTH paths; `BurnieLootOpen.tickets` continues emitting scaled; `TicketsQueuedScaled` continues emitting from auto-resolve lootbox paths AND mint-boost. Whole-ticket information is exposed purely via the new additive `LootboxTicketRoll` event. UI / indexer / test consumers opt in to remainder visibility without rebasing existing event reads.
- **Test coverage**: (a) Bernoulli EV-neutrality property tests across many seeds (manual paths); (b) consolation trigger + non-trigger predicate tests (manual paths only); (c) regression — `_rollRemainder` no longer entered from manual-only player+level queues, BUT auto-resolve paths still produce `rem` byte residues + resolve at activation (status-quo preservation); (d) `LootboxTicketRoll` emission + field-consistency tests (manual paths only); (e) auto-resolve byte-equivalence tests (no behavior drift at `resolveLootboxDirect` / `resolveRedemptionLootbox`); (f) bit-slice independence chi-square; (g) cross-mixing test — same player opens manual + auto-resolve at same future level; confirm only manual contributions are Bernoulli-rolled, auto-resolve still pools via `rem` byte.
- **Delta audit + findings consolidation (terminal)**: single `audit/FINDINGS-v39.0.md` 9-section deliverable; v38.0 5-Bucket Severity Rubric carry; `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` PARALLEL adversarial pass on the finished §4 draft per D-271-ADVERSARIAL-01 carry (`/degen-skeptic` OUT OF SCOPE per D-271-ADVERSARIAL-02 carry); LEAN regression REG-01 (v38.0 closure non-widening) + REG-02 (v34.0 closure non-widening) + REG-04 prior-finding spot-checks across `audit/FINDINGS-v25..v38.0.md`; KI walkthrough EXC-01..04 RE_VERIFIED; closure signal `MILESTONE_V39_AT_HEAD_<sha>` + ROADMAP/STATE/MILESTONES flips. Phase 273 BAF-credit-routing pre-shipped commits get explicit included-since-baseline §3.A row coverage (no F-39-NN finding eligible; surface-coverage attestation).

**Key context / constraints:**
- Pre-launch posture preserved — no live volume, no migration concerns
- Cross-repo READ-only pattern: `contracts/` + `test/` writes via per-commit user approval per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` (carry from v34..v38)
- Single-file audit deliverable per D-NN-FILES-01 carry
- Forward-cite zero-emission per D-NN-FCITE-01 carry (terminal phase)
- Adversarial-pass timing: SEQUENTIAL after full §4 draft; 3-skill PARALLEL spawn red-teams the FINISHED draft per D-271-ADVERSARIAL-01 + D-271-ADVERSARIAL-03 carry
- Inline-execution mode at execute-phase open per D-271-EXEC-01 default carry
- Single-phase patch shape (Phase 274 only) per v36.0 Phase 266 + v38.0 Phase 272 precedent — multi-wave structure: Wave 1 contract commit (`_resolveLootboxCommon` manual-branch addition + `LOOTBOX_WWXRP_CONSOLATION` constant + `LootboxTicketRoll` event + index threading + bit-allocation NatSpec), Wave 2 test commit (manual-path unit + consolation + auto-resolve byte-equivalence regression + cross-mixing), Wave 3+ audit deliverable + closure flips
- `_queueTicketsScaled` + `_rollRemainder` + `rem` byte in `ticketsOwedPacked` STAY — mint-boost fractionals (`DegenerusGameMintModule.sol` line 1142) AND auto-resolve lootbox paths (`resolveLootboxDirect` + `resolveRedemptionLootbox`) continue using them. This milestone narrowly retires the MANUAL lootbox-path producer of fractional residues; mint-boost + auto-resolve retirement is a future-milestone consideration.
- NO breaking event changes per D-274-NO-EVT-BREAK-01: `LootBoxOpened.futureTickets` / `BurnieLootOpen.tickets` / `TicketsQueuedScaled` semantics unchanged. Whole-ticket information exposed via additive `LootboxTicketRoll` event.
- Behavior gating via `index != type(uint48).max` sentinel: manual callers pass real index → new behavior; auto-resolve callers pass `type(uint48).max` → status-quo behavior.
- Jackpot ticket-award sites OUT OF SCOPE per D-274-JACKPOT-OUT-01 — deferred to v40.0+ alongside the already-deferred v36.0 ENT-05 BAF xorshift refactor.

**Closure summary (v39.0 SHIPPED 2026-05-13):** Single-phase patch (Phase 274) mirroring v36.0 Phase 266 + v38.0 Phase 272 precedent. Wave 1 USER-APPROVED batched contract commit `c21f833a` ships LBX-WT-01..05 manual-branch Bernoulli + LBX-WX-01..04 WWXRP consolation + LBX-EVT-01..06 new `LootboxTicketRoll` event + index threading (4 callers updated; manual 2 pass real index + auto-resolve 2 pass `type(uint48).max` sentinel). Storage layout byte-identical at v39 HEAD vs `06623edb` (new constant compile-time inlined; new event log calldata-equivalent; new parameter on internal function not a storage slot). Cross-module byte-identity preserved for `JackpotModule + MintModule + Degenerette + TraitUtils + JackpotBucketLib + EntropyLib`. D-274-BIT-SLICE-01 superseded intra-Wave-1 from 8-bit to 16-bit slice on bias quantification (8-bit form had ~17% relative bias for `frac <= 56`; 16-bit form has <=0.10% relative bias, consistent with existing `bits[0..15]` rangeRoll precedent). Wave 2 USER-APPROVED batched test commit `f8e55cfe` ships TST-WT-01..07 + TST-WX-01..03 + TST-REG-01..04 (74 tests across 4 new files in `test/unit/`, `test/edge/`, `test/stat/`; all passing). Wave 3 audit deliverable `audit/FINDINGS-v39.0.md` (9 sections, FINAL READ-only at v39 closure HEAD `6a7455d1` post-Task-3.11) + 3-skill PARALLEL adversarial-pass at `274-01-ADVERSARIAL-LOG.md` (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` spawn intent per D-274-ADVERSARIAL-01 carry; `/degen-skeptic` OUT OF SCOPE per D-271-ADVERSARIAL-02 carry; 12 novel-vector hypotheses (i)..(t) investigated; 10 NEGATIVE_RESULT_ONLY + 2 ACCEPTED_DESIGN dispositions). Phase 273 BAF-credit-routing pre-shipped commits (`ff929948` + `e9807891` + `e04d3333` + `1eb1ecb5`) folded into v39.0 audit baseline as included-since-baseline per D-274-BAF273-INCLUDE-01 (surface-coverage attestation only). Wave 3 closure-flip commits land REQUIREMENTS + ROADMAP + STATE + MILESTONES + PROJECT updates atomically. **Result:** 8 of 8 §4 adversarial surfaces SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / SAFE_BY_DESIGN_PHASE_273; zero F-39-NN finding blocks; 1 PASS REG-01 (v38.0 closure NON-WIDENING for v38-touched surfaces NOT in v39 manual-lootbox scope; Phase 273 BurnieCoinflip carve-out folded as included-since-baseline) + 1 PASS REG-02 (v34.0 closure NON-WIDENING) + REG-03 KI envelope re-verifications + REG-04 prior-finding spot-check sweep PASS; KNOWN-ISSUES.md UNMODIFIED. Resolution: 39/39 Complete. **Decision-anchor IDs:** D-274-CLOSURE-01 + D-274-CLOSURE-02 + D-274-MANUAL-ONLY-01 + D-274-NO-EVT-BREAK-01 + D-274-EVT-ROLL-01 + D-274-EVT-INDEX-SENTINEL-01 + D-274-WX-AMOUNT-01 + D-274-BIT-SLICE-01 + D-274-APPROVAL-01 + D-274-ADVERSARIAL-01 + D-274-SEV-01 + D-274-FILES-01 + D-274-FCITE-01 + D-274-KI-01 + D-274-MINTBOOST-OUT-01 + D-274-AUTORESOLVE-OUT-01 + D-274-JACKPOT-OUT-01 + D-274-LBX02-OUT-01 + D-274-BAF273-INCLUDE-01 (19 v39-anchors); inherited carry-chains: D-272-* + D-271-* + D-266-* + D-265-* + D-262-* + D-257-* + D-253-15. Closure signal: `MILESTONE_V39_AT_HEAD_6a7455d1`.

## Completed Milestone: v38.0 Always-Hero Simplification + Maximal Dead-Code Cleanup

**Goal:** Drop the Degenerette hero opt-out semantics so hero always fires with quadrant 0 as default — adds random competition for any player's winning symbol, simplifies bet API + resolve path. Bundle with a maximal cleanup sweep across `contracts/` for accumulated dead code + unused constants + unreachable branches + stale comments + redundant guards, and land the 4 v37+ carry-forward items (LBX-02 + GASPIN-02/03 + SURF-03 re-baseline + STAT-03 v35.0 carry). Single-phase patch shape (mirrors v36.0 Phase 266 precedent; NOT the multi-phase v34/v35/v37 milestone shape).

**Audit baseline:** v37.0 closure HEAD `MILESTONE_V37_AT_HEAD_2654fcc2`.

**Target features:**

- **Always-on hero** (Degenerette; `contracts/modules/DegenerusGameDegeneretteModule.sol`): `_packFullTicketBet` normalizes `heroQuadrant ≥ 4` → `0` (was: opted out of hero); `_resolveFullTicketBet` extracts quadrant unconditionally (no `heroEnabled` bit read); `_fullTicketPayout` drops `heroEnabled` parameter, always applies hero for `M ∈ {2..7}`. Public API `placeDegeneretteBet(..., uint8 heroQuadrant)` signature UNCHANGED — `0xFF` and any `≥4` value still accepted (normalize to 0 internally). NatSpec rewrites describe what IS at v38 close (per `feedback_no_history_in_comments.md`). Net diff ~5 LOC delete + ~2 LOC add + ~10 LOC NatSpec. Bytecode shrink ~30 bytes + 1 fewer branch (~30 gas saved per spin). EV-neutrality preserved per Fraction-exact analytical audit run post-v37 close.
- **Maximal dead-code cleanup sweep** (`contracts/`): inventory-driven removal of (a) unused private/internal constants per grep recipe; (b) unreachable branches per `feedback_no_dead_guards.md` (caller-clamp / pre-validated paths in MintModule, JackpotModule, AdvanceModule, LootboxModule); (c) stale comments referencing pre-v37 design per `feedback_no_history_in_comments.md`; (d) redundant safety guards. `/gas-audit` orchestrator (`/gas-scavenger` + `/gas-skeptic`) runs systematic candidate-discovery. Per `feedback_design_intent_before_deletion.md`: each removal candidate traces original design intent + actor game-theory across timing/state combos BEFORE deletion shape is decided. Each accepted removal lands USER-APPROVED.
- **v37+ Carry-Forward Bundle Pickup**:
  - **LBX-02**: empirical 55%-tickets-path gas-savings test pin — `test/gas/LootboxOpenGas.test.js` extension once fixture provides reliable openable lootbox path coverage (Phase 266 GAS-01 precedent)
  - **GASPIN-02 + GASPIN-03**: SURF-05 gas-pin stabilization under combined `npm run test:stat` ordering — D-269-STAB-01 retry with refined `hardhat_reset` sequencing OR option (d) test-isolation via dedicated mocha config OR widened tolerance ceiling (last resort)
  - **SURF-03 re-baseline**: one-line `test/stat/SurfaceRegression.test.js` edit — `V36_BASELINE` → `PHASE_269_CLOSE_BASELINE = "8fd5c2e1..."` for the SURF-03 it block only; SURF-01/02/04 stay anchored at v36.0
  - **STAT-03 v35.0 carry**: `test/stat/PerPullEmptyBucketSkip.test.js` fixture density retune per Phase 264 D-IMPL-07 mid/late-game holder-density spec, OR document actual production-floor rate
- **Delta audit + findings consolidation (terminal)**: single `audit/FINDINGS-v38.0.md` 9-section deliverable; D-08 5-Bucket Severity Rubric carry; `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` PARALLEL adversarial pass per D-271-ADVERSARIAL-01 carry on finished §4 draft (`/degen-skeptic` OUT OF SCOPE per D-271-ADVERSARIAL-02 carry); LEAN regression REG-01 (v37.0 closure non-widening) + REG-02 (v34.0 closure non-widening) + REG-04 prior-finding spot-checks across audit/FINDINGS-v25..v37.0; KI walkthrough EXC-01..04 RE_VERIFIED; closure signal `MILESTONE_V38_AT_HEAD_06623edb` + ROADMAP/STATE/MILESTONES flips.

**Key context / constraints:**
- Pre-launch posture preserved — no live volume, no migration concerns
- Cross-repo READ-only pattern: `contracts/` + `test/` writes via per-commit user approval per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` (carry from v34..v37)
- Single-file audit deliverable per D-NN-FILES-01 carry
- Forward-cite zero-emission per D-NN-FCITE-01 carry (terminal phase)
- Adversarial-pass timing: SEQUENTIAL after full §4 draft; 3-skill PARALLEL spawn red-teams the FINISHED draft per D-271-ADVERSARIAL-01 + D-271-ADVERSARIAL-03 carry
- Inline-execution mode at execute-phase open per D-271-EXEC-01 default (mirrors v36.0 Phase 266 + v37.0 Phase 270/271 inline-execution carry; subagent `.md`-write guard pattern-matching FINDINGS/SUMMARY/ADVERSARIAL-LOG filenames blocks subagent writes)
- Single-phase patch shape (Phase 272 only) per v36.0 Phase 266 precedent — multi-wave structure: Wave 1 contract commits (always-hero diff + cleanup), Wave 2 test commits (re-validation + carry-bundle), Wave 3+ audit deliverable + ROADMAP/STATE/MILESTONES flips
**Audit deliverables (cumulative):** `audit/FINDINGS-v25.0.md` + `FINDINGS-v27.0.md` + `FINDINGS-v28.0.md` + `FINDINGS-v29.0.md` + `FINDINGS-v30.0.md` + `FINDINGS-v31.0.md` + `FINDINGS-v32.0.md` + `FINDINGS-v33.0.md` + `FINDINGS-v34.0.md` + `FINDINGS-v35.0.md` + `FINDINGS-v36.0.md` (FINAL READ-only at HEAD `1c0f0913`, 9 sections, ~700 lines, 6-surface adversarial table all SAFE_*, zero F-36-NN finding blocks); `KNOWN-ISSUES.md` modified by 1 entry rephrase at v36.0 close (EntropyLib XOR-shift entry NARROWS to BAF-jackpot-only scope per AUDIT-05; REPHRASE under D-09 Design Decisions, not new promotion); EXC-01..04 RE_VERIFIED at HEAD (EXC-01..03 NEGATIVE-scope at v36; EXC-04 NARROWS to BAF-jackpot-only)
**Awaiting user commit:** `test/edge/LastPurchaseDayRace.test.js` + `test/edge/BackfillIdempotency.test.js` (TST-FILE-01 + TST-FILE-02 from v32.0 Phase 251; remain untracked permanently per D-253-FIND04-04)

**Closure summary (v38.0 SHIPPED 2026-05-11):** Single-phase patch (Phase 272) mirroring v36.0 Phase 266 precedent. Wave 1 USER-APPROVED batched contract commit `527e3adc` ships HERO-01..05 always-on hero (silent-normalize variant) + CLEAN-01..05 dead-code sweep narrowed to `DegenerusGameDegeneretteModule.sol` per D-272-CLEAN-SCOPE-01 (bytecode delta −57 bytes 8955 → 8898; storage byte-identical; public ABI byte-identical). **Wave 1.5 USER-APPROVED contract revision commit `4760459f` adds defensive boundary validation at `placeDegeneretteBet` entry per D-272-INPUT-VALIDATION-01 — `heroQuadrant >= 4` reverts with `InvalidBet` instead of being silently normalized. This Wave-1.5 revision is the v38 remediation for Hypothesis (i) docs-vs-behavior drift surfaced at the Wave 3 3-skill PARALLEL adversarial pass; status pivoted from KEEP_AS_NEGATIVE_FINDING (Wave 3) to RESOLVED_AT_V38 (post Wave 1.5).** Wave 2 USER-APPROVED batched test commit `e3fcb95c` ships STAT-01..02 EV-neutrality re-validation + SURF-01..03 (SURF-03 re-baselined to `PHASE_269_CLOSE_BASELINE`) + LBX-02 path-of-investigation documentation + GASPIN-02 (a-alt) script-split + GASPIN-03 clean-run verification + STAT-03-v35-carry ACCEPTED-DESIGN documentation. Wave 3 audit deliverable `audit/FINDINGS-v38.0.md` (9 sections, ~850 lines, FINAL READ-only at v38 closure HEAD `06623edb`) + 3-skill PARALLEL adversarial-pass at `272-01-ADVERSARIAL-LOG.md` (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` per D-271-ADVERSARIAL-01 carry). Wave 1.5 audit-amendment commits `c63a75a1` + `08706ebd` + `1249a6fd` + `06623edb` propagate Hypothesis (i) RESOLVED_AT_V38 across all scoped audit artifacts. Wave 4 closure-flip commits land REQUIREMENTS + ROADMAP + STATE + MILESTONES + PROJECT updates atomically. **Result:** 7 of 7 §4 adversarial surfaces SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE; zero F-38-NN finding blocks; 1 PASS REG-01 + 1 PASS REG-02 + REG-03 KI envelope re-verifications + REG-04 prior-finding spot-check sweep PASS; KNOWN-ISSUES.md UNMODIFIED. Resolution: 29/30 Complete + 1/30 RE-DEFERRED-V39+ (LBX-02 — fixture-coverage gap persists; path-of-investigation prose at `audit/FINDINGS-v38.0.md` §9.NN.iv). **Decision-anchor IDs:** D-272-CLOSURE-01 + D-272-CLOSURE-02 + D-272-INPUT-VALIDATION-01 + D-272-CLEAN-SCOPE-01 + D-272-FCITE-01 + D-272-KI-01 + D-272-APPROVAL-01 + D-272-ADVERSARIAL-01 + D-272-SEV-01 + D-272-FILES-01 (10 v38-anchors); inherited carry-chains: D-271-ADVERSARIAL-01 (3-skill PARALLEL) + D-271-ADVERSARIAL-02 (`/degen-skeptic` OUT OF SCOPE) + D-271-ADVERSARIAL-03 (`/economic-analyst` added) + D-271-FCITE-01 + D-266-FCITE + D-265-FCITE-01 + D-262-FCITE-01 + D-257-FCITE-01 + D-253-15. Closure signal: `MILESTONE_V38_AT_HEAD_06623edb`.

## Deferred to Future Milestones

_Absorbed into v40.0 active milestone (no longer deferred — see "Current Milestone: v40.0" above):_
- Auto-resolve LootboxModule Bernoulli extension (was D-274-AUTORESOLVE-OUT-01) — now v40.0 target feature 1
- JackpotModule:2216 BAF small-lootbox Bernoulli (was D-274-JACKPOT-OUT-01 L2216 portion) — now v40.0 target feature 2
- Event surface unification (was D-274-EVT-ROLL-01 + D-274-EVT-INDEX-SENTINEL-01 + D-274-NO-EVT-BREAK-01 non-breaking stance) — now v40.0 target feature 3
- JackpotModule cosmetic xTICKET_SCALE cleanup (L702/L835/L1005) + ENT-05 BAF xorshift refactor + `_queueLootboxTickets` wrapper retirement — now v40.0 target feature 4
- Ticket-vs-entry granularity investigation + decision — SETTLED at TICKET granularity per D-40N-GRANULARITY-01 (1 ticket = 4 entries; 4× variance vs entry-granularity accepted; entry-granularity refactor permanently off the roadmap)

_Carried forward into v41.0+ (next-next-milestone candidates):_
- Lootbox empirical 55%-tickets-path gas-savings test pin (LBX-02 RE-DEFERRED-V41+ at v40.0 open; D-274-LBX02-OUT-01) — fixture-coverage gap persists; analytical worst-case load-bearing per Phase 266 GAS-01 + `feedback_gas_worst_case.md`; path-of-investigation prose at `audit/FINDINGS-v38.0.md` §9.NN.iv (carried unchanged from v38 + v39 close)
- Mint-boost fractional retirement (D-274-MINTBOOST-OUT-01 → D-40N-MINTBOOST-OUT-01 v40-anchor; future-milestone consideration) — `_queueTicketsScaled` + `_rollRemainder` + `rem` byte stay at `DegenerusGameMintModule.sol:1142` (deterministic dust accumulator, not RNG-driven; out of v40.0 scope per user disposition 2026-05-13)
- `runrewardjackpots` module-misplacement note — stale 2026-04-02 backlog note; not v40.0-tagged; carries forward
- Game-over thorough hardening — deferred to dedicated game-over hardening milestone



_Resolved at v39.0 close (no longer outstanding):_
- Lootbox manual-path whole-ticket Bernoulli + WWXRP cold-bust consolation + additive `LootboxTicketRoll` event — RESOLVED v39.0 Phase 274 (Wave 1 commit `c21f833a` ships LBX-WT-01..05 + LBX-WX-01..04 + LBX-EVT-01..06; Wave 2 commit `f8e55cfe` ships TST-WT-01..07 + TST-WX-01..03 + TST-REG-01..04; closure signal `MILESTONE_V39_AT_HEAD_6a7455d1`)

_Resolved at v38.0 close (no longer outstanding):_
- Always-on hero default-0 simplification — RESOLVED v38.0 Phase 272 (Wave 1 commit `527e3adc`; HERO-01..05 silent-normalize variant) + Wave 1.5 commit `4760459f` (D-272-INPUT-VALIDATION-01 defensive boundary validation revision)
- Maximal dead-code cleanup sweep — RESOLVED v38.0 Phase 272 Wave 1 commit `527e3adc` (CLEAN-01..05; narrowed to `DegenerusGameDegeneretteModule.sol` per D-272-CLEAN-SCOPE-01 — `/gas-audit` candidate-discovery surfaced no high-confidence cross-module removals matching `feedback_design_intent_before_deletion.md` standard)
- SURF-03 re-baseline post-LBX-01 — RESOLVED v38.0 Phase 272 Wave 2 commit `e3fcb95c` (re-baselined to `PHASE_269_CLOSE_BASELINE = "8fd5c2e1..."` for SURF-03 it block; SURF-01/02/04 retained at v36.0 baseline)
- SURF-05 gas-pin stabilization (GASPIN-02 + GASPIN-03 carry from v37.0 Phase 269) — RESOLVED v38.0 Phase 272 Wave 2 commit `e3fcb95c` (GASPIN-02 (a-alt) script-split per planner pick: `test:gas` script splits Phase261GasRegression + Phase264GasRegression off `test:stat` via package.json wiring; GASPIN-03 clean-run verification)
- `PerPullEmptyBucketSkip.test.js` fixture density retune (STAT-03 v35.0 carry) — RESOLVED v38.0 Phase 272 Wave 2 commit `e3fcb95c` via ACCEPTED-DESIGN ledger entry per planner pick option (b): test header documents 88.24% empty-bucket skip rate on sparse-fixture as v35.0 Phase 265 D-265-STAT03-01 fixture-calibration-error reframe; deity-backed dense fixture proves helper correctness empirically
- Hypothesis (i) docs-vs-behavior drift on `0xFF` input semantics (surfaced at Wave 3 3-skill PARALLEL adversarial pass; KEEP_AS_NEGATIVE_FINDING at Wave 3 2026-05-11) — RESOLVED_AT_V38 via Wave 1.5 commit `4760459f` (D-272-INPUT-VALIDATION-01 input validation; revert with `InvalidBet` on `>= 4` instead of silent normalize) + Wave 1.5 audit-amendment commits `c63a75a1` + `08706ebd` + `1249a6fd` + `06623edb`

_Resolved at v37.0 close (no longer outstanding):_
- Auditing post-v32.0 commits (`002bde55` presale auto-deactivate, `2713ce61` setDecimatorAutoRebuy removal) — RESOLVED v37.0 Phase 270 (DELTA-01..04 PASS; verdicts SAFE_BY_STRUCTURAL_CLOSURE + SAFE_BY_DESIGN per 270-01-DELTA-SURFACE.md; feeds Phase 271 §3.A Row Group 3 + §6b 4-row KI envelope)
- Lootbox `_resolveLootboxRoll` dead BURNIE-conversion branch cleanup — RESOLVED v37.0 Phase 269 (LBX-01 commit `8fd5c2e1`; bytecode shrink 177 bytes 18,330 → 18,153; caller-clamp triple-defense proves byte-equivalence)
- Degenerette payout recalibration (5-table per-N design) — RESOLVED v37.0 Phase 267 (commit `e1136071` `feat(267): degenerette producer + 5-table payout rewrite + 3-tier ETH split [DGN-01..15, PAY-SPLIT-01..03]`) + Phase 268 statistical validation (commit `4b277aaf` `test(268): degenerette stat suite + cross-surface preservation v37.0 + worst-case gas regression [STAT-01..07, SURF-01..06]`)
- SURF-05 gas-pin re-pinning fix (~120K combined-suite drift) — PARTIAL-RESOLVED v37.0 Phase 269 (GASPIN-01 root-cause inline at commit `009cbde3`; stabilization options (a)/(b)/(c) deferred to v38+ per D-269-STAB-01 attempt-failed analysis; v36.0 acceptance "128k is fine approved" carries forward)

_Resolved or carried at v36.0 / v35.0 close (no longer outstanding):_
- v35.0 burnie-near-future-per-pull-level resample seed — RESOLVED v35.0 (Phase 263)
- Phase 261 INFO-tier reconciliation drifts — addressed by v36.0 §3c handling
- Phase 257 Task 7 adversarial red-team gap — RESOLVED v34.0 Phase 262 Task 6

## Completed Milestone: v37.0 Degenerette Recalibration + Maintenance Bundle

**Goal:** Reconcile Degenerette payout calibration with the v34.0 heavy-tail trait producer (pre-launch fix), execute deferred maintenance (lootbox dead-branch cleanup + SURF-05 gas-pin re-pinning), and clear the long-deferred adversarial audit of post-v32.0 commits — all closed under a single `audit/FINDINGS-v37.0.md` deliverable.

**Audit baseline:** v36.0 closure HEAD `MILESTONE_V36_AT_HEAD_1c0f09132d7439af9881c56fe197f81757f8164a`.

**Target features:**
- **Degenerette 5-table payout recalibration** (primary, contracts): new `packedTraitsDegenerette` helper in `contracts/DegenerusTraitUtils.sol` with producer `[16,16,16,16,16,16,16,8]/120` (commons 13.33%, gold 6.67%; symbol uniform 1/8); replace `_evNormalizationRatio` in `contracts/modules/DegenerusGameDegeneretteModule.sol` with 5 per-N payout tables (N = gold-quadrant count ∈ {0..4}) each calibrated to basePayoutEV = 100 centi-x; symbol-only hero match with per-N hero boost dispatch; per-N WWXRP factors (5 tables); DELETE normalizer + 4 stale comments. Net ~50 LOC delete / ~50 LOC add. Constants 11 → 24. Mint + Jackpot + v34 gold-solo paths byte-identical (existing `packedTraitsFromSeed` + `JackpotBucketLib` UNCHANGED).
- **Degenerette statistical validation + cross-surface preservation**: 3 new `test/stat/*.js` (per-N EV exactness + producer chi² + bonus EV); extend `SurfaceRegression.test.js` per v34/v35/v36 pattern.
- **Lootbox dead BURNIE-conversion branch cleanup** in `contracts/modules/DegenerusGameLootboxModule.sol`: remove unreachable `if (targetLevel < currentLevel)` branch in `_resolveLootboxRoll` (~L1568-1581) — caller `_resolveLootboxCommon` already clamps `targetLevel >= currentLevel` at L882-884. ~50g/open savings + bytecode shrink + satisfies `feedback_no_dead_guards.md`.
- **SURF-05 gas-pin re-pinning fix**: investigate root cause of ~120K gas-pin drift in Phase 261/264 SURF-05 tests under `npm run test:stat` ordering (standalone runs at pinned values pass) and re-pin or fix ordering dependency so combined-suite runs stable.
- **Post-v32.0 deferred-commit adversarial audit pickup**: adversarial coverage of `002bde55` (presale auto-deactivate) and `2713ce61` (setDecimatorAutoRebuy removal) — long-deferred carry-forward from v34.0 close. Surface as §3.A delta rows in FINDINGS-v37.0.md.
- **Delta audit + findings consolidation (terminal)**: single `audit/FINDINGS-v37.0.md` deliverable with 5-bucket severity rubric (D-08 carry); adversarial pass `/contract-auditor` + `/zero-day-hunter` SEQUENTIAL after full §4 draft (D-NN-ADVERSARIAL-02 carry); LEAN regression REG-01 (v36.0 closure non-widening) + REG-02 (v34.0 closure non-widening, JackpotBucketLib byte-identity) + REG-04 prior-finding spot-checks across v25..v36; KI walkthrough EXC-01..04 RE_VERIFIED; closure signal `MILESTONE_V37_AT_HEAD_2654fcc2` + ROADMAP/STATE/MILESTONES flips.

**Key context / constraints:**
- Pre-launch posture preserved — no live volume, no migration concerns
- Cross-repo READ-only pattern: zero `contracts/` writes by agent; zero `test/` writes by agent. All contract + test commits USER-COMMITTED per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md`. Audit deliverable + planning docs AGENT-COMMITTED.
- Single-file audit deliverable per D-NN-FILES-01 carry
- Forward-cite zero-emission per D-NN-FCITE-01 carry (Phase 271 is terminal)
- Adversarial-pass timing: SEQUENTIAL after full §4 draft, parallel-spawn skills red-team the FINISHED draft per D-NN-ADVERSARIAL-02 carry
- `/economic-analyst` + `/degen-skeptic` adversarial inclusion deferred to phase-discuss (in scope only if phase-discuss confirms)
- 5-phase shape preview (roadmapper finalizes): 267 Degenerette contracts (batched) → 268 Degenerette stat + cross-surface tests → 269 lootbox dead-branch cleanup + SURF-05 re-pin → 270 post-v32.0 deferred-commit adversarial sub-audit → 271 delta audit + FINDINGS-v37.0.md (terminal)
- Derivation script for Degenerette constants: `.planning/notes/degenerette-recalibration/derive_5_tables.py` (reproducible `Fraction`-exact derivation of all 25 constants)
- Out of scope: ETH daily jackpot (already drawn at `lvl`); far-future BURNIE portion (already per-pull random level); purchase-phase ticket distributions; any change to trait-roll logic outside the Degenerette path; runrewardjackpots module-misplacement note (stale, not v37.0-tagged); gameover-thorough-test backlog note (out of v37.0 scope)

## Completed Milestone: v34.0 Trait Rarity Rework + Gold Solo Priority

**Status:** Complete — SHIPPED 2026-05-09. Closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555`.

**Result:** 4 phases (259-262), 10 plans, 36/36 requirements satisfied (TRAIT-01..06 + SOLO-01..09 + STAT-01..07 + SURF-01..05 + AUDIT-01..05 + REG-01..04). Audit baseline v33.0 contract-tree HEAD `4ce3703d740d3707c88a1af595618120a8168399` → v34.0 source-tree HEAD `6b63f6d4daf346a53a1d463790f637308ea8d555`. Phase 259 rewrote `contracts/DegenerusTraitUtils.sol` to a heavy-tail color distribution (`weightedColorBucket(uint32) → uint8` 8-tier 256-resolution: 25/25/25/12.5/6.25/3.125/2.344/0.781%; `traitFromWord(uint64)` rewritten as `(weightedColorBucket(low32) << 3) | (high32 & 7)` bit-slice composition; legacy `weightedBucket` fully removed; `[QQ][CCC][SSS]` byte layout preserved). Phase 260 added `_pickSoloQuadrant(uint8[4], uint256) internal pure → uint8` to `DegenerusGameJackpotModule.sol` and substituted `effectiveEntropy = (entropy & ~uint256(3)) | uint256((3 - soloQuadrant) & 3)` at all 4 ETH-distribution sites (line 282 `runTerminalJackpot`, line 349 `payDailyJackpot` jackpot-phase, line 524 `payDailyJackpot` purchase-phase, line 1147 `_resumeDailyEth` SPLIT_CALL2) atomically; line-349 ↔ line-1147 split-call coherence preserved by construction; 8 documented non-injection sites byte-identical; `JackpotBucketLib` byte-identical. Phase 261 published 1M-sample empirical color-frequency + chi-squared independence + symbol uniformity (STAT-01..03), 100K gold-solo coverage (100% on ≥1-gold draws) + tie-break uniformity (chi² p > 0.05) (STAT-04..05), per-surface EV uplift Monte Carlo (~3.4× headline) (STAT-06), pack-feel Wilson 99% CIs (STAT-07), and cross-surface preservation tests for hero override / Degenerette / 8 non-injection sites + gas regression (SURF-01..05). Phase 261-03 perf refactor of `_pickSoloQuadrant` to pure-stack uint256 packing reduced paired-empty-wrapper delta from 1477 gas to 1260 gas (200-gas headroom under 1500 gas amended ceiling); REQUIREMENTS.md SURF-05 amended to body-bound reality + `_resumeDailyEth` descope per `73d533d8`. Phase 262 published `audit/FINDINGS-v34.0.md` (665 lines, 9 sections, FINAL READ-only at HEAD `6b63f6d4`): 6 of 6 §4 adversarial surfaces SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE (a entropy-bit collision, b L349↔L1147 split-call coherence, c gold-trait population manipulation, d gas-griefing 4-iter loop, e overflow / signed-vs-unsigned XOR mask, f hero × gold composition added per Task 7 user disposition as intended skill-expression channel for high-engagement Degenerette wagerers); zero F-34-NN finding blocks; AUDIT-01 §3d delta-surface (5 TraitUtils + 14 JackpotModule + 5 downstream caller rows); AUDIT-04 zero-new-state scan (zero new storage slots + zero new public/external mutation entry points); AUDIT-03 §3e conservation re-proof (5 SAFE invariant rows: bucket-share-sum × pool invariance + JackpotBucketLib byte-identity + solvency invariant + hero override byte-layout + split-mode coherence). LEAN regression: 1 PASS REG-01 (v33.0 closure signal `MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399` re-verified non-widening; charity governance / GNRUS.sol byte-identical) + 1 PASS REG-02 (v32.0 closure signal `MILESTONE_V32_AT_HEAD_acd88512` re-verified non-widening; L173 turbo guard + L1174 backfill sentinel + GameStorage `_livenessTriggered` body byte-identical) + 4 PASS REG-04 (v25/v27/v29/v30 prior-finding spot-check rows). KI envelopes EXC-01..03 RE_VERIFIED NEGATIVE-scope at v34 (trait/solo path has zero affiliate-roll / AdvanceModule / gameover-RNG-substitution interaction); EXC-04 RE_VERIFIED with STAT-05 chi² empirical cross-cite (`test/stat/GoldSoloCoverage.test.js`, 100K samples per goldCount ∈ {2,3,4} chi² < {3.841, 5.991, 7.815} at α=0.05). KNOWN-ISSUES.md UNMODIFIED per D-262-KI-01 default zero-promotion path. Cross-repo READ-only pattern carried forward — zero `contracts/` writes by agent; zero `test/` writes by agent across all 4 v34.0 phases; all 5 v34 contract commits + 8 v34 test commits USER-COMMITTED per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` (Phase 260 multi-site SOLO injection batched per `feedback_batch_contract_approval.md`). Adversarial validation in Phase 262 Task 6 successfully spawned `/contract-auditor` + `/zero-day-hunter` skills with real captured output (resolves Phase 257 SPAWN_FAILED carry-forward); surfaced surface (a) bits 24-25 doc gap + surface (c) two-channel tightening + NEW surface (f) hero × gold composition, all folded into §4 prose via Task 7b atomic-commit per user disposition Option B. Zero forward-cites emitted (terminal-phase rule). Pre-close artifact audit run; 2 carry-forward stale quick-tasks acknowledged.

**Original Goal:** Convert the trait system from its legacy flat distribution (designed for the original PurgeGame's strategic-trait gameplay) into a heavy-tail rarity system suited to a pure-chance jackpot product, and add a gold-trait priority rule so legendary winning traits always claim the 60% solo bucket at every ETH-distribution site.

**Target features:**
- **Color/Symbol distribution split** in `contracts/DegenerusTraitUtils.sol`: replace `weightedBucket` with `weightedColorBucket` (256-resolution thresholds, 3 commons at 25% each + geometric tail down to 0.78%, 32× rarity ratio between rarest and most common color) and a flat 12.5% symbol distribution (3-bit slice). Update `traitFromWord` to compose the two. Keep `packedTraitsFromSeed` and the `[QQ][CCC][SSS]` byte layout unchanged.
- **Gold-solo priority** in `contracts/modules/DegenerusGameJackpotModule.sol`: add `_pickSoloQuadrant(uint8[4] traits, uint256 entropy)` helper that, when any winning trait has color 7 (gold), routes the solo bucket to a uniformly-chosen gold quadrant (option B tie-break — random among golds, preserves quadrant symmetry); falls through to existing rotation when no gold present. Inject at exactly the **4 ETH-distribution `_rollWinningTraits` consumer sites** with a meaningful solo bucket: line 282 (`runTerminalJackpot`), line 349 (`payDailyJackpot` jackpot-phase main), line 524 (`payDailyJackpot` purchase-phase main), and line 1147 (`_resumeDailyEth` call 2 — must produce identical effective entropy as line 349). The other 8 `_rollWinningTraits` sites (events 513/527/1713/1715, equal-split tickets/coin 598/599/1687, flat-bucket lootbox 683) intentionally NOT modified — verified to have no solo bucket structure.
- **Statistical validation suite**: 1M-sample empirical frequency test for `weightedColorBucket` (within 3-sigma binomial bounds), color/symbol independence chi-squared, gold-solo coverage simulation (100% of draws with any gold land solo on a gold quadrant), uniform tie-break test (chi-squared p > 0.05 over 100K multi-gold draws), pack-feel CIs (≥1 legendary in 27% of 10-packs), ~3.3× solo-EV uplift sim for gold-trait holders.
- **Cross-surface verification**: hero override (`_applyHeroOverride`) writes color from RNG bits / symbol from `dailyHeroWagers` — color logic preserved, symbol now uniform 12.5%; deity-pass virtual entries (floor(2% of bucket tickets) per symbol) operate cleanly on uniform symbol distribution; Degenerette match payouts unchanged byte layout; bonus-jackpot path (`_rollWinningTraits(_, true)`) unaffected (no solo bucket downstream).

**Key context / constraints:**
- Audit baseline: v33.0 contract HEAD `4ce3703d740d3707c88a1af595618120a8168399`
- Trait byte layout `[QQ][CCC][SSS]` UNCHANGED — quadrant 2 bits, color 3 bits, symbol 3 bits
- `JackpotBucketLib` UNCHANGED — gold-priority works by stuffing the chosen offset into the low 2 bits of `entropy` before passing downstream; existing rotation logic does the work
- Bucket share BPS UNCHANGED: `[6000, 1333, 1333, 1334]` (final-day) and `[2000, 2000, 2000, 2000]` (daily/purchase) — no constants change
- Bucket counts UNCHANGED: `[25, 15, 8, 1]` (daily) and `[20, 12, 6, 1]` (purchase) rotated by entropy
- Tie-break decision: random-among-gold (option B) — preserves quadrant symmetry, no permanent bias toward q0
- Hero override extension to color: OUT OF SCOPE (color stays RNG-only this milestone)
- Solo-bucket caps/floors: explicitly OUT OF SCOPE — variance is the product
- UI/UX rarity treatments, tier names (Common/Notable/Rare/Epic/Legendary), whitepaper updates: deferred to follow-on milestones once on-chain math ships
- Solvency invariant (`claimablePool ≤ ETH balance + stETH balance`) preserved
- Zero new external state, zero new admin functions, zero new upgrade hooks introduced

## Completed Milestone: v33.0 Charity Allowlist Governance (post-closure patch)

**Status:** Complete — SHIPPED 2026-05-06; RE-SHIPPED 2026-05-07 via Phase 258 post-closure patch.

**Result:** 5 phases (254-258), 16 plans, 28/28 requirements satisfied (ALW + VOTE + RES + CLEAN + TST + AUDIT-01..05 + FIX-01 + FIX-02). Audit baseline v32.0 HEAD `acd88512` → v33.0 contract-tree HEAD `4ce3703d740d3707c88a1af595618120a8168399`. Replaced the open `propose(address)` / approve-reject vote flow in `GNRUS.sol` with a vault-owner-curated 20-slot charity allowlist (3 locked foundational slots) — eliminating the collusion path where any sDGNRS coalition could route the per-level GNRUS distribution to an address they control. Phase 254 demolished v32-shape governance + laid v33.0 storage skeleton (`currentSlate[20]` + pending-edit mapping + bitmap helpers + 5 view helpers + `setCharity(uint8, address)` admin entry point + hot-pack slot 2). Phase 255 implemented `vote(uint8 slot)` (approve-only, full sDGNRS weight, locked 4-path revert order) and `pickCharity(uint24 level)` (idempotence-first → atomic flush → strict-`>` winner loop 0..19 → 3 LevelSkipped paths → 2%-of-pool distribution) and rewrote events / errors for the slot-based design. Phase 256 added 49 governance it-blocks + 30 pruned unit it-blocks + 6 integration it-blocks (real-game-flow conservation evidence via `charityResolve.pickCharity(lvl - 1)` from `DegenerusGameAdvanceModule:1634`) + `pickCharity` full-slate < 700_000 gas guardrail. Phase 257 published `audit/FINDINGS-v33.0.md` as the milestone-closure deliverable (~720 lines, 9 sections, FINAL READ-only at HEAD `dcb70941` initially): 8 of 8 §4 adversarial surfaces SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / SAFE_BY_TRUST_ASYMMETRY (a admin front-run, b edit-queue ordering, c tie-break gaming, d DGVE float gaming, e instant-apply abuse, f active-count drift, g locked-slot poisoning, h locked-slot lock-bypass); zero F-33-NN finding blocks. Phase 257 independent adversarial re-run by fresh-context `/contract-auditor` + `/zero-day-hunter` agents (loaded with skill specs after Task 7 SPAWN_FAILED forced executor-manual fallback) surfaced a queue-branch vote-redirect mechanism — `pickCharity` flushed queued edits BEFORE the winner pick. Phase 258 closed it structurally: FIX-01 reordered the flush block to execute AFTER the distribution payout (skip-paths A/B/C fall through to flush instead of returning early); FIX-02 added `address public lastWinningRecipient` storage + `error PreviousWinnerNotVotable()` declaration + a 5th vote() guard preventing consecutive recipient capture. Phase 258-02 re-audited at the patched HEAD adding §3a delta-surface entries (4 new: `lastWinningRecipient` NEW state + `PreviousWinnerNotVotable` NEW error + `pickCharity` MODIFIED_LOGIC follow-up + `vote` MODIFIED_LOGIC follow-up), re-tagged surface (a) with post-258 reinforcement, extended §4b sub-row prose with the queue-branch closure paragraph, added new row (i) consecutive-recipient capture closure, carried REG-01 forward at the new HEAD, and re-emitted closure signal `MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399` with explicit supersedence note for `MILESTONE_V33_AT_HEAD_dcb70941`. LEAN regression: 1 PASS REG-01 (v32.0 closure signal `MILESTONE_V32_AT_HEAD_acd88512` re-verified non-widening — L173 turbo guard + L1174 backfill sentinel + GameStorage `_livenessTriggered` body byte-identical between baseline and HEAD) + zero-row REG-02. KI envelopes EXC-01..04 all RE_VERIFIED NEGATIVE-scope (charity governance has zero RNG interaction). KNOWN-ISSUES.md UNMODIFIED per D-257-KI-01 default zero-promotion path (carries forward through Phase 258). All 6 contract+test commits USER-COMMITTED per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` (Phase 258 used the batched approval pattern with 3-file batch). Pre-close audit `.planning/v33.0-MILESTONE-AUDIT.md` returned `gaps_found` for bookkeeping defects only (Phases 254/255/256 missing VERIFICATION.md; Phase 255 SUMMARY frontmatter schema drift; TST-03 + TST-04 use `provides:` instead of `requirements-completed:`; ROADMAP Phase 257 plan checkbox unchecked) — no functional issues; user chose `[A]cknowledge` and option B `tag and ship now`.

## Completed Milestone: v32.0 Backfill Idempotency + purchaseLevel Underflow Audit

**Status:** Complete (2026-05-02)

**Result:** 7 phases (247-253), 7 plans, 32/32 requirements satisfied. v32.0 HEAD anchor `acd88512` containing both WIP guards committed in single SHA (turbo at L173 + backfill sentinel at L1174). Two HIGH SUPERSEDED-at-HEAD F-32-NN disclosure blocks: F-32-01 (productive-pause / turbo race → `purchaseLevel` underflow panic 0x11; closed by L173 conjunction `!inJackpot && !lastPurchaseDay && !rngLockedFlag`); F-32-02 (`_backfillGapDays` double-execution underflow; closed by L1174 sentinel `rngWordByDay[idx + 1] == 0`). Both SUPERSEDED-at-HEAD via PLV-03 ternary unreachable proof + PLV-05 testnet panic 0x11 walk + PLV-06 strand-disproof + Phase 252 §3.A composition for F-32-01; BFL-01..06 conservation + sentinel-correctness 4-step proof + Phase 252 §3.B composition for F-32-02. 134 V-rows across 25 REQs (Phase 247-252) all SAFE / NON-WIDENING / NON-INTERFERING with 0 FINDING_CANDIDATE rows surfaced. LEAN regression: 13 PASS REG-01 (12 prior-finding rows from v29 + v30 + v3.7/v3.8 baseline + 1 explicitly NAMED F-29-04 row) + 15-entry Exclusion Log + zero-row REG-02. KI envelopes EXC-01..04 all RE_VERIFIED non-widening (EXC-02 + EXC-03 dual-carrier via Phase 248 BFL-05; EXC-01 + EXC-04 NEGATIVE-scope via Phase 250 SIB-03). KNOWN-ISSUES.md UNMODIFIED per D-253-FIND03-01 default zero-promotion path (F-32-01 + F-32-02 both fail D-09 sticky predicate — SUPERSEDED at HEAD, not ongoing protocol behavior). Cross-repo READ-only pattern carried forward — zero `contracts/` writes by agent; zero `test/` writes by agent across all 7 v32.0 phases. Phase 251 awaiting-approval test files persist untracked permanently per D-253-FIND04-04. Zero forward-cites emitted (terminal-phase rule). Deliverable: `audit/FINDINGS-v32.0.md` (548 lines, 9 sections, FINAL READ-only at HEAD `acd88512`) emitting closure signal `MILESTONE_V32_AT_HEAD_acd88512`. Phase 253 used Phase 246 single-plan multi-task pattern (1 plan / 6 atomic per-task commits + 1 SUMMARY follow-up + 1 VERIFICATION commit). Note: gsd-executor + gsd-verifier subagents encountered the same Claude Code built-in restriction blocking subagents writing `audit/FINDINGS-*.md` ("Subagents should return findings as text, not write report files"); orchestrator executed all 6 tasks + verification inline in parent session. All phases verified PASSED 12/12 must_haves + 5/5 ROADMAP success criteria.

## Completed Milestone: v31.0 Post-v30 Delta Audit + Gameover Edge-Case Re-Audit

**Status:** Complete (2026-04-24)

**Result:** 4 phases (243-246), 11 plans (3 + 4 + 2 + 1 + 1 addendum), 33/33 requirements satisfied. Adversarial audit of 5 contract commits above v30.0 baseline `7ab515fe` → HEAD `cc68bfc7` (14 files, +187/-67 lines). **Zero on-chain vulnerabilities. Zero F-31-NN findings.** 142 verdict rows across 33 REQs all SAFE floor severity (Phase 244: 87 V-rows / 19 REQs, Phase 245: 55 V-rows / 14 REQs). LEAN regression: 6 PASS REG-01 (5 F-30-NNN delta-touched + F-29-04 explicitly NAMED) + 12-row exclusion log + 1 SUPERSEDED REG-02 (sDGNRS orphan-redemption window structurally closed by `771893d1`). KI EXC-02 + EXC-03 envelopes RE_VERIFIED non-widening via dual-carrier attestations (SDR-08-V01 + GOE-01-V01 + GOE-04-V02). `KNOWN-ISSUES.md` UNMODIFIED per D-07 default path (zero candidates pool → zero gating walks). 17/17 Phase 244 §Phase-245-Pre-Flag bullets CLOSED in Phase 245 (10 SDR-grouped + 7 GOE-grouped). Zero forward-cites emitted per CONTEXT.md D-25 terminal-phase rule. Cross-repo READ-only pattern carried forward — zero `contracts/` or `test/` writes. Deliverable: `audit/FINDINGS-v31.0.md` (403 lines, 9 sections, FINAL READ-only) emitting closure signal `MILESTONE_V31_CLOSED_AT_HEAD_cc68bfc7`. Phase 246 used the v30 Phase 242 single-plan multi-task pattern (1 plan / 6 atomic per-task commits / direct write to deliverable / READ-only flip on Task 6). Note: gsd-executor subagent encountered runtime guard blocking Write of FINDINGS-v31.0.md ("subagents shouldn't write report files"); orchestrator persisted the agent's prepared content via cp + 6 atomic commits matching plan task boundaries. All 4 phases verified PASSED 8/8 dimensions.

## Completed Milestone: v30.0 Full Fresh-Eyes VRF Consumer Determinism Audit

**Status:** Complete (2026-04-20)

**Result:** 6 phases (237-242), 14 plans, 26/26 requirements satisfied. Full fresh-eyes per-consumer VRF determinism audit at HEAD `7ab515fe` (contract tree byte-identical to v29.0 `1646d5af`; all post-v29 commits docs-only). **Zero on-chain vulnerabilities.** 17 INFO findings (F-30-001..F-30-017) consolidated into `audit/FINDINGS-v30.0.md` (729 lines, 10 sections). 31 prior RNG-adjacent findings re-verified (v29.0 F-29-03/04 + v25.0 + v3.7 + v3.8 rngLocked items): 31 PASS / 0 REGRESSED / 0 SUPERSEDED. 17-row FIND-03 KI Non-Promotion Ledger emitted (0 of 17 candidates qualified under D-09 3-predicate gating — accepted-design + non-exploitable + sticky; `KNOWN-ISSUES.md` UNMODIFIED per D-16 default path). Phase 238 per-consumer freeze proofs closed 146 rows (124 SAFE + 22 EXCEPTION matching EXC-01..04 distribution); Phase 239 proved `rngLockedFlag` AIRTIGHT + 62-row permissionless sweep (24 respects-rngLocked + 38 proven-orthogonal) + re-justified both documented asymmetries (lootbox index-advance + `phaseTransitionActive`) from first principles; Phase 240 proved VRF-available gameover-jackpot branch fully deterministic (19-row inventory / determinism proof / 28 GOVAR / 2 GOTRIG DISPROVEN_PLAYER_REACHABLE_VECTOR / BOTH_DISJOINT vs F-29-04); Phase 241 confirmed ONLY_NESS_HOLDS_AT_HEAD with Gate A set-equality + Gate B grep backstop, discharging 29/29 Phase 240 forward-cite tokens (`DISCHARGED_RE_VERIFIED_AT_HEAD`); Phase 242 emitted zero forward-cites (D-25 terminal-phase rule). Cross-repo READ-only pattern from v28.0/v29.0 carried forward — zero `contracts/` or `test/` writes throughout the milestone. Deliverable: `audit/FINDINGS-v30.0.md`.

## Completed Milestone: v29.0 Post-v27 Contract Delta Audit

**Status:** Complete (2026-04-18)

**Result:** 8 phases (230, 231, 232, 232.1, 233, 234, 235, 236), 21 plans, 25/25 requirements satisfied. Full adversarial audit of every `contracts/` change since the v27.0 (2026-04-13) baseline — 10 contract-touching commits across 12 files plus 2 post-Phase-230 RNG-hardening commits captured via `230-02-DELTA-ADDENDUM.md`. Phase 232.1 inserted mid-milestone for RNG-index ticket-drain ordering enforcement. **Zero on-chain vulnerabilities.** 4 INFO findings consolidated into `audit/FINDINGS-v29.0.md` (F-29-01/02 BAF event-widening; F-29-03 QST-01 companion-test-coverage observation; F-29-04 Gameover RNG substitution for mid-cycle write-buffer tickets — user-surfaced retroactively, codifies the new "RNG-consumer determinism" invariant). 32 prior findings re-verified at HEAD `1646d5af`: 31 PASS + 1 SUPERSEDED (F-25-09 EndgameModule deletion) + 0 REGRESSED. ETH + BURNIE conservation re-proven (41 SSTORE rows + 10 named-path proofs; 10 mint + 6 burn sites); RNG commitment integrity re-proven for every new consumer (28+ backward-trace rows + 19 commitment-window rows + 25-variable global state-space enumeration); TRNX-01 4-path walk verified rngLocked invariant preserved across the packed phase-transition. KNOWN-ISSUES.md updated with 1 new design-decision entry (Gameover RNG substitution), then refined for warden-facing scope (4 out-of-scope test/script entries removed, all internal audit-artifact cross-references stripped). Cross-repo READ-only pattern from v28.0 carried forward — zero `contracts/` or `test/` writes. Deliverable: `audit/FINDINGS-v29.0.md`.

## Completed Milestone: v28.0 Database & API Intent Alignment Audit

**Status:** Complete (2026-04-15)

**Result:** 6 phases (224–229), 13 plans. 69 findings consolidated into `audit/FINDINGS-v28.0.md` (0 CRITICAL, 0 HIGH, 0 MEDIUM, 27 LOW, 42 INFO). Phase 224 paired all 27 openapi endpoints with 27 implemented routes and 27 `API.md` headings (PAIRED-BOTH). Phase 225 swept handler JSDoc, response shapes, and request schemas across three plans (22 findings). Phase 226 diffed Drizzle schema vs applied SQL migrations (10 findings). Phase 227 audited indexer event-processor coverage + arg-mapping + comment drift (31 findings, including F-28-56 inverse-orphan — handler registered for an event no contract emits). Phase 228 verified cursor/reorg/view-refresh state machines and absorbed 4 Phase 227 deferrals via the D-227-10 scope-guard handoff pattern (5 findings). Phase 229 consolidated all findings under canonical flat `F-28-01..F-28-69` numbering with zero HIGH promotions (D-229-05), marked 48 DEFERRED to a future v29+ remediation backlog and 21 INFO-ACCEPTED retained in-document per D-229-10 (KNOWN-ISSUES.md untouched this milestone per user directive — v28 audits the sim/database/indexer layer, not contracts). All 17/17 requirements satisfied (API-01..05, SCHEMA-01..04, IDX-01..05, FIND-01..03). Cross-repo READ-only audit pattern formalized: writes confined to `audit/` + `.planning/`; no `contracts/`, `database/`, or `test/` changes. Deliverable: `audit/FINDINGS-v28.0.md`.

## Completed Milestone: v27.0 Call-Site Integrity Audit

**Status:** Complete (2026-04-13)

**Goal / Target scope / Incident context:**

**Goal:** Systematically surface runtime call-site-to-implementation mismatches that static compilation does not catch — the same class of bug as the `mintPackedFor` regression, where a call passes compile, may pass superficial tests, but reverts at runtime because selector/target/path alignment is wrong.

**Target scope:**
- Delegatecall target alignment across all `<ADDR>.delegatecall(abi.encodeWithSelector(IFACE.fn.selector, ...))` sites
- Raw selector and calldata literals (`bytes4(0x...)`, `bytes4(keccak256(...))`, manual abi encoders)
- External/public function test coverage gaps (unexercised surface = potential undetected mintPackedFor-class bugs)
- Findings consolidation into audit/FINDINGS-v27.0.md

**Prior incident context:** `mintPackedFor(address)` was declared in `IDegenerusGame` and called via staticcall from `DegenerusQuests._isLevelQuestEligible`, but had no implementation on `DegenerusGame`. Level-quest completion during purchase silently reverted under the narrow condition where accumulated progress crossed threshold on that single call, surfacing as generic `E()`. Fixed in commit `a0bf328b`. Makefile gate `check-interfaces` added in commit `23bbd671`. v27.0 extends this coverage.

**Result:** 4 phases (220-223), 9 plans. Phase 220 wired `scripts/check-delegatecall-alignment.sh` with 1:1 interface↔address mapping preflight (43 delegatecall sites verified ALIGNED). Phase 221 wired `scripts/check-raw-selectors.sh` with 5-pattern coverage and produced the 221-01-AUDIT.md catalog (5 JUSTIFIED INFO sites). Phase 222 classified all 308 external/public functions (19 COVERED / 177+1 CRITICAL_GAP / 112 EXEMPT after matrix refresh), shipped `scripts/coverage-check.sh` with three failure modes, and closed every CRITICAL_GAP via `test/fuzz/CoverageGap222.t.sol` (76 integration tests); Plan 222-03 strengthened test assertions and scoped drift detection to contract sections (commits ef83c5cd + e0a1aa3e). Phase 223 consolidated 16 INFO findings into `audit/FINDINGS-v27.0.md` with a full v25.0 regression appendix (all 13 prior findings verified). Zero exploitable vulnerabilities. All 14/14 requirements satisfied.

## Completed Milestone: v26.0 Bonus Jackpot Split

**Status:** Complete (2026-04-12)

**Result:** 2 phases (218-219), 4 plans. Phase 218 parameterized `_rollWinningTraits` with keccak256 domain separation for independent bonus traits, rewired all 6 jackpot caller sites, removed DJT storage infrastructure, added `DailyWinningTraits` event, and introduced level-1 double coin jackpot branch. Phase 219 delta audit: 10 code path sections, 13 verdicts, 0 findings. Main ETH path proven EQUIVALENT at all 5 sub-paths. Event correctness verified at all 3 emission sites. Entropy independence proven (E1 != E2 via keccak256 preimage resistance). Gas: +1,523 gas/drawing (0.022%), 1.993x headroom PRESERVED. All 11/11 requirements satisfied.

## Completed Milestone: v25.0 Full Audit (Post-v5.0 Delta + Fresh RNG)

**Status:** Complete (2026-04-11)

**Result:** 5 phases (213-217), 18 plans. Delta extraction (99 cross-module chains mapped). Adversarial audit (700+ verdicts, 0 VULNERABLE). RNG fresh-eyes (VRF/RNG proven SOUND from first principles). ETH conservation proof (20 flow chains, 75 SSTORE sites). Findings consolidation (13 INFO, 31-item regression with zero regressions). 3 design decisions promoted to KNOWN-ISSUES.md. All 18/18 requirements satisfied. Deliverable: `audit/FINDINGS-v25.0.md`.

## Completed Milestone: v24.0 Gameover Flow Audit & Fix

**Status:** Complete (2026-04-09)

**Result:** 4 phases (203-206), 5 plans. handleGameOverDrain restructured so RNG check gates ALL side effects; reverts with E() when funds > 0 but rngWord unavailable. All 7 trigger+drain requirements verified PASS. Sweep audit: 30-day delay, 33/33/34 split, stETH-first hard-revert, VRF shutdown all verified. Cross-module interaction audit: 5 IXNR requirements PASS. Delta audit: Phase 203 commit proven behaviorally equivalent.

## Completed Milestone: v23.0 Redemption Coinflip Fix

**Status:** Complete (2026-04-09)

**Result:** 2 phases (201-202), 2 plans. Phase 201 removed phantom `creditFlip(SDGNRS, burnieToCredit)` from all 3 redemption resolution paths in AdvanceModule — eliminated BURNIE coinflip pool inflation during resolution. `resolveRedemptionPeriod` changed to void (return value unused). Phase 202 delta audit: EQUIVALENT verdict, supply conservation proven (mint only at claim time via mintForGame), pool consistency verified (1 legitimate SDGNRS creditFlip remains at line 781), reservation/release symmetric, zero test regressions (Hardhat 1296, Foundry 150). All 4/4 requirements satisfied (RCA-01 through RCA-04).

## Completed Milestone: v22.0 Delta Audit & Payout Reference Rewrite

**Status:** Complete (2026-04-08)

## Completed Milestone: v21.0 Jackpot Two-Call Split & Skip-Split Optimization

**Status:** Complete (2026-04-08)

## Completed Milestone: v20.0 Pool Consolidation & Write Batching

**Status:** Complete (2026-04-05)

**Result:** 2 phases (186-187), 6 plans. Phase 186 inlined consolidatePrizePools + runRewardJackpots + _drawDownFuturePrizePool into AdvanceModule as single `_consolidatePoolsAndRewardJackpots` flow with batched SSTOREs. JackpotModule exposes `runBafJackpot` as external entry point with self-call guard. Dead code removed (5 functions + 2 helpers). Quest entropy fixed. All modules under 24KB (JackpotModule 22,858B, AdvanceModule 18,196B). Phase 187 delta audit: full variable sweep across normal/x10/x100 paths, 9/9 correctness checks pass, pool ETH conservation proven algebraically, all peripheral changes verified (self-call guard, passthrough, entropy, dead code, interfaces). Foundry 149/29, Hardhat 1304/5 — zero new regressions. 1 INFO finding (F-187-01: x100 yield dump/keep roll trigger shifted — design improvement). All 13/13 requirements satisfied.

## Completed Milestone: v19.0 Pool Accounting Fix & Sweep

**Status:** Complete (2026-04-04)

**Result:** 3 phases (183-185), 6 plans. Phase 183 fixed the jackpot payout path to defer the futurePool SSTORE and capture paidEth, refunding unspent ETH from empty trait buckets. Phase 184 swept all 81 pool mutation sites across 9 contracts — 0 accounting gaps. Phase 185 delta audit found F-185-01 HIGH (deferred SSTORE overwrote whale pass + auto-rebuy futurePool additions) — fixed by re-reading storage after _executeJackpot (+100 gas warm SLOAD). Foundry + Hardhat: zero unexpected regressions. All 9/9 requirements satisfied.

## Completed Milestone: v18.0 Delta Audit (v16.0-v17.1)

**Status:** Complete (2026-04-04)

## Completed Milestone: v17.1 Comment Correctness Sweep

**Status:** Complete (2026-04-03)

## Completed Milestone: v17.0 Affiliate Bonus Cache

**Status:** Complete (2026-04-03)

**Result:** 2 phases (173-174), 3 plans. Affiliate bonus cached in mintPacked_ bits [185-214] — eliminates 5 cold SLOADs (~10,500 gas) from every activity score computation. Cache write piggybacks on existing SSTORE in recordMintData. Bonus rate doubled to 1 point per 0.5 ETH (cap remains 50). 105 mintPacked_ operations audited across 8 contracts (0 collisions). Storage layout identical across 10 contracts. Foundry 176/27 and Hardhat 1267/42 — zero regressions vs v16.0. All 9/9 requirements satisfied.

## Completed Milestone: v16.0 Module Consolidation & Storage Repack

**Status:** Complete (2026-04-03)

**Result:** 5 phases (168-172), 6 plans. Storage repack: slot 0 filled to 32/32 bytes, currentPrizePool downsized to uint128 in slot 1, old slot 2 eliminated. EndgameModule fully deleted — rewardTopAffiliate inlined into AdvanceModule, runRewardJackpots migrated to JackpotModule, claimWhalePass moved to WhaleModule. All 15 Foundry test files updated for new layout. forge inspect confirms identical layout across 11 contracts. 3 fuzz test invariants repaired (TicketLifecycle double-buffer, RedemptionHandler supply tracking, VRFPathHandler gap backfill). All 14/14 requirements satisfied.

## Completed Milestone: v15.0 Delta Audit (v11.0-v14.0)

**Status:** Complete (2026-04-02)

**Result:** 6 phases (162-167), 11 plans. Function-level changelog (134 items across 21 contracts), level system reference (462 lines), jackpot carryover audit (11 functions SAFE), per-function adversarial audit (76 functions, 76 SAFE, 0 VULNERABLE, 3 INFO), RNG commitment window verification (5 paths, 4 SAFE, 1 KNOWN TRADEOFF), gas ceiling analysis (advanceGame 7,023,530 gas, 1.99x margin), call graph audit (36/36 CLEAN), test baseline (1455 passing, 124 expected failures, 0 unexpected). All 11/11 requirements satisfied.

## Requirements

### Validated

- ✓ v1.0 RNG security audit — VRF integration, manipulation windows, ticket selection
- ✓ v1.1 Economic flow audit — 13 reference docs covering all subsystems
- ✓ v1.2 RNG storage/function/data-flow deep dive
- ✓ v1.2 Delta attack reverification after code changes
- ✓ State-changing function audit — all external/public functions across all contracts
- ✓ Parameter reference — every named constant consolidated
- ✓ sDGNRS/DGNRS split implementation — soulbound + liquid wrapper architecture
- ✓ Audit doc sync — all 10 docs updated for sDGNRS/DGNRS split
- ✓ v2.1 Governance security audit — 26 verdicts covering all attack vectors — v2.1
- ✓ v2.1 M-02 closure — emergencyRecover eliminated, governance replaces single-admin authority — v2.1
- ✓ v2.1 War-game scenarios — 6 adversarial scenarios assessed with severity ratings — v2.1
- ✓ v2.1 Audit doc sync — all docs updated for governance, zero stale references — v2.1
- ✓ v2.1 Post-audit hardening — CEI fix, removed death clock pause + activeProposalCount — v2.1

### Validated

- ✓ v3.0 Full contract audit + payout specification — 5 phases, 58 requirements — v3.0
- ✓ v3.1 Comment correctness + intent verification — 84 findings (80 CMT + 4 DRIFT) across all 29 contracts — v3.1
- ✓ v3.2 RNG delta + comment re-scan — 30 deduplicated findings (6 LOW, 24 INFO), governance fresh eyes (14 surfaces, 0 new), v3.1 fix verification (76/3/4/1) — v3.2
- ✓ v3.3 Gambling burn delta audit — 3 HIGH + 1 MEDIUM confirmed and fixed (CP-08 double-spend, CP-06 stuck claims, Seam-1 fund trap, CP-07 split-claim) — v3.3
- ✓ v3.3 Redemption correctness — full lifecycle trace, segregation solvency proven, CEI verified, period state machine proven — v3.3
- ✓ v3.3 Invariant test suite — 7 Foundry invariants passing (solvency, double-claim, supply, cap, roll bounds, aggregate tracking) — v3.3
- ✓ v3.3 Adversarial sweep — 29/29 contracts swept, 0 new HIGH/MEDIUM, 13 composability sequences SAFE — v3.3
- ✓ v3.3 Economic analysis — ETH EV=100% (fair), BURNIE EV=0.98425x, bank-run solvency proven, 4 rational actor strategies unprofitable — v3.3
- ✓ v3.3 Gas optimization — 7 variables ALIVE, 3 packing opportunities documented, gas baseline captured — v3.3
- ✓ v3.3 Documentation sync — NatSpec verified, error renames, bit allocation map, 12 audit docs updated, PAY-16 payout path — v3.3
- ✓ v3.5 Gas optimization — 204 variables analyzed (201 ALIVE, 3 DEAD), 5 dead code items, 8 packing opportunities, 13 findings (3 LOW, 10 INFO) — v3.5 Phase 55
- ✓ v3.5 Comment correctness — 46 files (~26,300 lines) swept, 26 findings (7 LOW, 19 INFO), 34 prior findings verified FIXED, 3 regressions documented — v3.5 Phase 54
- ✓ v3.5 Gas ceiling analysis — 18 paths profiled (12 advanceGame + 6 purchase), 15 SAFE, 1 TIGHT, 2 AT_RISK, 4 INFO findings — v3.5 Phase 57
- ✓ v3.5 Final Polish — 43 findings consolidated (10 LOW, 33 INFO) from comment correctness (26), gas optimization (13), and gas ceiling analysis (4) — v3.5 Phase 58

### Validated

- ✓ v3.6 VRF Stall Resilience — gap day RNG backfill, orphaned lootbox recovery, midDayTicketRngPending clearing, stall→swap→resume test coverage, delta audit (8 surfaces SAFE), 2 INFO findings — v3.6 Phases 59-62

### Validated

- ✓ v3.7 VRF Request/Fulfillment Core — rawFulfillRandomWords revert-safety proven, 300k gas budget 6-10x sufficient, vrfRequestId lifecycle verified, rngLockedFlag mutual exclusion airtight, 12h timeout retry correct, Slot 0 assembly SAFE, 22 Foundry fuzz tests, 0 HIGH/MEDIUM/LOW, 2 INFO — v3.7 Phase 63
- ✓ v3.7 Lootbox RNG Lifecycle — all 5 LBOX requirements VERIFIED, index-to-word 1:1 mapping proven across daily/mid-day/retry/backfill/gameover paths, zero-state guards verified (4/5 guarded, 1 INFO-level 2^-256), per-player entropy uniqueness proven, full purchase-to-open lifecycle traced, 21 Foundry fuzz tests, 0 HIGH/MEDIUM/LOW, 2 INFO (V37-003, V37-004) — v3.7 Phase 64
- ✓ v3.7 VRF Stall Edge Cases — all 7 STALL requirements VERIFIED, gap backfill entropy unique via keccak256 preimage, gas ceiling 18.9M (< 30M block limit), coordinator swap resets all 8 VRF state vars, zero-seed unreachable after swap, gameover fallback prevrandao 1-bit bias INFO, dailyIdx timing consistent, 17 Foundry fuzz tests, 0 HIGH/MEDIUM/LOW, 3 INFO (V37-005, V37-006, V37-007) — v3.7 Phase 65
- ✓ v3.7 VRF Path Test Coverage — 7 invariant assertions (256 runs/depth 128), 6 parametric fuzz tests (1000 runs each), 4 Halmos symbolic proofs (0 counterexamples), redemption roll [25,175] bounds verified for all 2^256 inputs — v3.7 Phase 66
- ✓ v3.7 Verification + Doc Sync — 66-VERIFICATION.md (10/10 must-haves), V37-001 RESOLVED, Phase 66 cross-references in all findings docs, KNOWN-ISSUES.md updated — v3.7 Phase 67

### Validated

- ✓ v3.8 VRF commitment window audit — 55 variables, 87 permissionless paths, 51/51 SAFE general proof, coinflip + daily RNG path-specific proofs, 1 MEDIUM vulnerability (TQ-01 _tqWriteKey bug) with fix recommendation — v3.8 Phases 68-72
- ✓ v3.8 Boon storage packing — 29 per-player boon mappings packed into 2-slot struct, all 12 boon functions rewritten, lootbox boost simplified to single tier — v3.8 Phase 73

### Validated

- ✓ v3.9 Far-future ticket fix — third key space (bit 22), central routing for all 6 callers, dual-queue drain, combined pool jackpot selection, rngLocked guard, 35 Foundry tests, RNG commitment window proof — v3.9 Phases 74-80

### Validated

- ✓ v4.0 Ticket Lifecycle & RNG-Dependent Variable Re-Audit — 10 phases (81-91), 51 INFO findings (0 HIGH/MEDIUM/LOW), DEC-01/DGN-01 withdrawn as false positives, 134 cumulative total. Ticket creation (16 entry points), processing (RNG/cursor), consumption (9 jackpot types), prize pool flow (storage layout), daily ETH/coin/ticket jackpots, other jackpots (earlybird/BAF/decimator/degenerette/finalday), RNG re-verification (55 vars, 27 slot shifts), consolidated findings, cross-phase consistency verified — v4.0 Phases 81-91
- ✓ v4.1 Ticket Lifecycle Integration Tests — 3 phases (92-94), 24 Foundry integration tests deploying full 23-contract protocol, all 6 ticket sources verified (direct purchase x3, lootbox near/far, whale bundle), boundary routing (L+5 write vs L+6 FF), FF drain timing proven, zero-stranding sweeps across all key spaces, RNG commitment window formal proof (9/9 paths SAFE), rngLocked guard verified, 1 bug fix (requestLootboxRng mid-day gating) — v4.1 Phases 92-94

### Validated

- ✓ v4.2 Daily Jackpot Chunk Removal + Gas Optimization — 4 phases (95-98), chunk removal delta verified (behavioral equivalence + zero stale refs), gas ceiling profiled (all 3 stages SAFE with 34.9-42.3% headroom), 24 SLOADs audited + 7 loops analyzed, comment cleanup (8 issues fixed, function rename), documentation gap closure (13/13 requirements verified), 0 new findings — v4.2 Phases 95-98
- ✓ v4.3 prizePoolsPacked Batching Optimization — closed early after Phase 99 callsite audit revealed H14 gas savings was 25x overestimate (~63.8K actual vs ~1.6M estimated). Optimization abandoned as not cost-effective. — v4.3 Phase 99
- ✓ v4.4 BAF Cache-Overwrite Bug Fix + Pattern Scan — 3 phases (100-102), protocol-wide cache-overwrite scan (1 VULNERABLE / 11 SAFE across 29 contracts), delta reconciliation fix applied to `runRewardJackpots`, Foundry fix-proof test, zero regressions — v4.4 Phases 100-102

### Validated

- ✓ v7.0 Delta Adversarial Audit (v6.0 Changes) — 4 phases (126-129), 65 changed functions across 12 contracts, 3 FIXED (GOV-01 onlyGame guard, GH-01/GH-02 burnAtGameOver reorder), 4 INFO, 0 open actionable findings, all 11 changed contract storage layouts verified via forge inspect — v7.0 Phases 126-129
- ✓ v8.0 Pre-Audit Hardening — 5 phases (130-134), 13 plans. Bot race (Slither + 4naly3er, 113 categories triaged), ERC-20 compliance (4 tokens, 5 deviations documented), event correctness (30 findings, all DOCUMENT), comment re-scan (72 fixes applied), consolidation (KNOWN-ISSUES.md 5→30+ entries, C4A README drafted, 1 dead code fix, BurnieCoinflip immutable→constant refactor). 14/14 requirements satisfied. — v8.0 Phases 130-134
- ✓ v8.1 Final Audit Prep — 3 phases (135-137), 5 plans. Delta adversarial audit (29 functions, 0 VULNERABLE, 6 INFO), test hygiene (5 files committed, suites green), documentation finalized (KNOWN-ISSUES.md +4 entries, C4A README finalized). 10/10 requirements satisfied. — v8.1 Phases 135-137

### Validated

- ✓ v9.0 Contest Dry Run — 3 phases (138-140), 8 plans. 5 fresh-eyes wardens, 152 attack surfaces, 0 Medium+ findings, $0 projected payout — v9.0 Phases 138-140
- ✓ v10.0 Audit Submission Ready — 3 phases (141-143). Delta audit of dailyIdx/backfill/turbo changes, documentation finalized, vault sDGNRS burn/claim verified — v10.0 Phases 141-143
- ✓ v10.1 ABI Cleanup — 3 phases (144-146). 9 forwarding wrappers removed, 16 unused views removed, 3 bonus removals, BurnieCoinflip creditors expanded, vault-owner access control on Game, ~238 lines removed — v10.1 Phases 144-146
- ✓ v11.0 BURNIE Endgame Gate — gameOverPossible flag, drip projection, MintModule/LootboxModule enforcement — v11.0 Phases 151-152
- ✓ v12.0 Level Quests — core design, integration mapping, economic + gas analysis — v12.0 Phases 153-155
- ✓ v13.0 Level Quests Implementation — interfaces, storage, quest logic, handler integration, carryover redesign — v13.0 Phases 156-158.1
- ✓ v14.0 Activity Score & Quest Gas Optimization — compute-once score, handler consolidation, price removal, SLOAD dedup — v14.0 Phases 159-161
- ✓ v15.0 Delta Audit — 76 functions audited (all SAFE), RNG commitment windows verified, gas ceiling 1.99x margin, call graph clean, 1455 tests passing — v15.0 Phases 162-167
- ✓ v16.0 Module Consolidation & Storage Repack — EndgameModule eliminated (3 functions redistributed), storage slots 0-2 repacked (slot 0 32/32, currentPrizePool uint128 in slot 1, slot 2 killed), 14/14 requirements satisfied — v16.0 Phases 168-172
- ✓ v17.0 Affiliate Bonus Cache — cached affiliate bonus in mintPacked_ bits [185-214] eliminating 5 cold SLOADs from activity score, rate doubled to 1 point per 0.5 ETH, 105 mintPacked_ operations audited (0 collisions), both test suites zero regressions, 9/9 requirements satisfied — v17.0 Phases 173-174
- ✓ v17.1 Comment Correctness Sweep — 40 contracts swept, 72 findings (30 LOW, 42 INFO), 56 fixed, 0 regressions from v3.1/v3.5, WWXRP decimal scaling added — v17.1 Phases 175-178
- ✓ v18.0 Delta Audit (v16.0-v17.1) — 4 phases (179-182), full delta audit of v16.0-v17.1 changes — v18.0 Phases 179-182
- ✓ v19.0 Pool Accounting Fix & Sweep — jackpot payout ETH fix, 81-site pool sweep, HIGH finding fixed — v19.0 Phases 183-185
- ✓ v20.0 Pool Consolidation & Write Batching — consolidatePrizePools + runRewardJackpots inlined, batched SSTOREs, 13/13 requirements — v20.0 Phases 186-187
- ✓ v21.0 Jackpot Two-Call Split & Skip-Split Optimization — v21.0 Phases 195-198
- ✓ v22.0 Delta Audit & Payout Reference Rewrite — purchase phase jackpot redesign, event catalog — v22.0 Phases 199-200
- ✓ v23.0 Redemption Coinflip Fix — phantom creditFlip removed from 3 resolution paths, EQUIVALENT delta audit, 4/4 requirements — v23.0 Phases 201-202
- ✓ v25.0 Full Audit (Post-v5.0 Delta + Fresh RNG) — 5 phases, 18 plans, 18/18 requirements. Delta extraction (99 chains), adversarial (700+ verdicts, 0 VULNERABLE), RNG fresh-eyes (SOUND), ETH conservation (algebraic proof), findings consolidation (13 INFO, 31 regressions checked, 0 regressed) — v25.0 Phases 213-217
- ✓ v27.0 Call-Site Integrity Audit — 4 phases, 9 plans, 14/14 requirements. Delegatecall target alignment (43 sites ALIGNED), raw-selector audit (5 INFO), external function coverage (308 functions classified, 76 integration tests close all 177 CRITICAL_GAPs), 16 INFO consolidated into audit/FINDINGS-v27.0.md, all 13 v25.0 findings re-verified — v27.0 Phases 220-223
- ✓ v28.0 Database & API Intent Alignment Audit — 6 phases, 13 plans, 17/17 requirements. Cross-repo READ-only audit pattern formalized; 27/27/27 API alignment, Drizzle ↔ SQL migration audit, indexer event-processor coverage, cursor/reorg/view-refresh state machines; 69 findings (0 CRITICAL/HIGH/MEDIUM, 27 LOW, 42 INFO) — v28.0 Phases 224-229
- ✓ v29.0 Post-v27 Contract Delta Audit — 8 phases, 21 plans, 25/25 requirements. Adversarial audit of 10 contract-touching commits since v27.0 baseline; ETH + BURNIE conservation re-proven; RNG commitment integrity re-proven for every new consumer; TRNX-01 4-path rngLocked invariant verified. **0 on-chain vulnerabilities.** 4 INFO findings (F-29-01..04) including the user-surfaced "RNG-consumer determinism" invariant disclosure. 32 prior findings re-verified (31 PASS + 1 SUPERSEDED + 0 REGRESSED). KNOWN-ISSUES.md cleaned for warden-facing scope. Deliverable: audit/FINDINGS-v29.0.md — v29.0 Phases 230-236

## Completed Milestone: v8.1 Final Audit Prep

**Status:** Complete (2026-03-28)

**Result:** 3 phases (135-137), 5 plans. Delta adversarial audit of 5 changed contracts (29 functions, 0 VULNERABLE, 6 INFO). Price feed governance (~400 new lines) verified safe. Boon multi-category coexistence verified. Recycling bonus house edge maintained. Storage layouts 5/5 PASS via forge inspect. 5 test files committed (Hardhat 1351 passing, Foundry 6/6 new tests passing). KNOWN-ISSUES.md updated with 4 new entries. C4A contest README finalized (DRAFT removed). All 10/10 requirements satisfied (DELTA-01-04, TEST-01-03, DOC-01-03).

## Completed Milestone: v8.0 Pre-Audit Hardening

**Status:** Complete (2026-03-27)

**Result:** 5 phases (130-134), 13 plans. Slither 1,959 findings + 4naly3er 4,453 instances triaged (0 FIX, 27 DOCUMENT, 84 FP by category). ERC-20 compliance verified across 4 tokens. Event correctness audit across 29 contracts (30 INFO findings). NatSpec delta sweep (72 fixes). KNOWN-ISSUES.md expanded from 5 to 30+ entries with detector IDs. C4A contest README drafted. Dead code removed (_lootboxBpsToTier). BurnieCoinflip 4 immutables converted to constants via ContractAddresses.

## Completed Milestone: v7.0 Delta Adversarial Audit (v6.0 Changes)

**Status:** Complete (2026-03-26)

**Result:** 4 phases (126-129), 11 plans. Delta extraction (17 files, 65 functions, 23/29 MATCH, 5 DRIFT). DegenerusCharity full adversarial audit (17 functions, 0 VULNERABLE). Changed contract audit (48 functions across 11 contracts, 0 VULNERABLE). Consolidated: 3 FIXED (GOV-01, GH-01, GH-02), 4 INFO, 0 open actionable findings. All storage layouts verified via forge inspect.

## Completed Milestone: v6.0 Test Suite Cleanup + Storage/Gas Fixes + DegenerusCharity

**Status:** Complete (2026-03-26)

**Result:** 6 phases (120-125). Test suite cleanup (green baseline), storage/gas fixes (lastLootboxRngWord deletion, double-SLOAD elimination, NatSpec fixes, deity boon downgrade prevention, advanceBounty rewrite), degenerette freeze fix (frozen-context ETH routed through pending pools), DegenerusCharity contract (soulbound GNRUS token with burn redemption and sDGNRS governance), game integration (resolveLevel + handleGameOver hooks), test suite pruning (13 redundant tests deleted, zero unique coverage lost).

## Completed Milestone: v5.0 Ultimate Adversarial Audit

**Status:** Complete (2026-03-25)

**Result:** 17 phases (103-119), 29 contracts, 693 functions, ~15,000+ lines Solidity. Three-agent adversarial system (Taskmaster/Mad Genius/Skeptic) with mandatory call-tree expansion, storage-write mapping, and BAF cache-overwrite checks on every state-changing function. 100% Taskmaster coverage in all 16 units. Zero actionable findings (0 CRITICAL/HIGH/MEDIUM/LOW, 29 INFO). BAF-class bugs comprehensively eliminated. ETH conservation PROVEN. All 4 master deliverables produced (FINDINGS.md, ACCESS-CONTROL-MATRIX.md, STORAGE-WRITE-MAP.md, ETH-FLOW-MAP.md).

## Completed Milestone: v4.4 BAF Cache-Overwrite Bug Fix + Pattern Scan

**Status:** Complete (2026-03-25)

**Result:** 3 phases (100-102). Protocol-wide scan for cache-then-overwrite pattern found 1 VULNERABLE instance (`runRewardJackpots` in EndgameModule) and 11 SAFE across 29 contracts. Delta reconciliation fix: `rebuyDelta = _getFuturePrizePool() - baseFuturePool` added before write-back, preserving auto-rebuy contributions. Foundry integration test (`BafRebuyReconciliation.t.sol`) proves the fix. Foundry 355/14, Hardhat 1208/34 — zero regressions.

## Completed Milestone: v4.3 prizePoolsPacked Batching Optimization

**Status:** Closed early (2026-03-25)

**Result:** Phase 99 callsite audit completed. Key finding: H14's ~1.6M gas savings estimate used cold SSTORE pricing (5,000/write) but subsequent writes to the same dirty slot cost only 100 gas (EIP-2200). Actual savings: ~63,800 gas (0.46% of 14M ceiling). Phases 100-102 abandoned — architectural complexity not justified for ~$0.13/execution savings at 1 gwei.

## Completed Milestone: v4.2 Daily Jackpot Chunk Removal + Gas Optimization

**Status:** Complete (2026-03-25)

**Result:** 4 phases (95-98). Chunk removal delta verified (behavioral equivalence proof, zero stale refs across all Solidity files). Gas ceiling profiled — all 3 daily jackpot stages reclassified from AT_RISK/TIGHT to SAFE with 34.9-42.3% headroom. 24 SLOADs audited, 7 loops analyzed, 1 actionable optimization identified (deferred as architectural). Comment cleanup: 8 issues fixed, `_processDailyEthChunk` renamed to `_processDailyEth`, full NatSpec added. Gap closure: all 13 requirements verified and tracked, EVM SLOT 1 banner corrected.

## Completed Milestone: v4.1 Ticket Lifecycle Integration Tests

**Status:** Complete (2026-03-24)

**Result:** 24 Foundry integration tests across 3 phases (92-94). All 22 requirements satisfied. Full-protocol deployment via DeployProtocol exercising all 6 ticket sources, edge cases, zero-stranding sweeps, and RNG commitment window proofs. 1 contract bug fix discovered (requestLootboxRng blocked during mid-day ticket processing).

## Completed Milestone: v4.0 Ticket Lifecycle & RNG-Dependent Variable Re-Audit

**Status:** Complete (2026-03-23)

**Result:** 51 INFO findings across 8 audit phases (81-88), consolidated in v4.0-findings-consolidated.md. No HIGH, MEDIUM, or LOW findings. DEC-01 and DGN-01 withdrawn as false positives. Grand total across all milestones: 134 (51 v4.0 + 83 prior).

### Deferred (v3.3+)

- [ ] Foundry fuzz invariant tests for governance (vote weight conservation, threshold monotonicity)
- [ ] Formal verification of vote counting arithmetic via Halmos
- [ ] Monte Carlo simulation of governance outcomes under various voter distributions
- [ ] Storage packing implementation — 3 opportunities documented in v3.3 gas analysis (up to 66,300 gas savings)

### Out of Scope

- Frontend code — not in audit scope
- Off-chain infrastructure — VRF coordinator is external
- Gas optimization beyond correctness — C4A QA findings are low-cost
- Governance UI/frontend — not in audit scope
- Off-chain vote aggregation — on-chain only governance
- Governance upgrade mechanisms — contract is immutable per spec

## Context

- Solidity 0.8.34, Hardhat + Foundry dual test stack
- 23 protocol contracts deployed in deterministic order via CREATE nonce prediction
- All contracts use immutable `ContractAddresses` library (addresses baked at compile time)
- VRF via Chainlink VRF v2 for randomness
- DegenerusStonk split into StakedDegenerusStonk (soulbound, holds reserves) + DegenerusStonk (transferable ERC20 wrapper)
- VRF governance: emergencyRecover replaced with sDGNRS-holder propose/vote/execute (M-02 mitigation). Touches DegenerusAdmin, AdvanceModule, GameStorage, Game, DegenerusStonk.
- Post-v2.1: death clock pause removed (unnecessary complexity), activeProposalCount removed (no on-chain consumer), _executeSwap CEI fixed
- New: Gambling burn / redemption system on sDGNRS — during-game burns enter a pending queue resolved by RNG roll (25-175) during advanceGame. Post-gameOver burns remain deterministic. Touches StakedDegenerusStonk, DegenerusStonk, BurnieCoinflip, AdvanceModule, and their interfaces.
- New: Creator DGNRS vesting — 50B (25%) at deploy to CREATOR, 5B per game level claimable by vault owner via claimVested(). Fully vested at level 30. unwrapTo guard changed from 5h lastVrfProcessed timestamp to rngLocked() boolean.

## Constraints

- **Audit target:** Code4rena competitive audit — findings cost real money
- **Compiler:** Solidity 0.8.34 (overflow protection built-in)
- **EVM target:** Paris (no PUSH0)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Split DGNRS into sDGNRS + DGNRS wrapper | Enable secondary market for creator allocation while keeping game rewards soulbound | ✓ Good |
| Pool BPS rebalance (Whale 10%, Affiliate 35%, Lootbox 20%, Reward 5%, Earlybird 10%) | Better distribution alignment with game mechanics | ✓ Audited v2.0 |
| Coinflip bounty DGNRS gating (min 50k bet, 20k pool) | Prevent dust-amount bounty claims draining reward pool | ✓ Audited v2.0 |
| burnRemainingPools replacing burnForGame | Cleaner game-over cleanup, removes per-address burn authority | ✓ Audited v2.0 |
| Replace emergencyRecover with sDGNRS governance | M-02 mitigation: compromised admin key can no longer unilaterally control RNG | ✓ Audited v2.1, M-02 downgraded to Low |
| VRF retry timeout 18h → 12h | Faster recovery from stale VRF requests | ✓ Audited v2.1 |
| unwrapTo blocked while rngLocked | Prevents vote-stacking via DGNRS→sDGNRS conversion during VRF request/fulfillment window (replaced 5h timestamp check with rngLocked boolean) | ✓ v9.0 |
| Creator DGNRS vesting (50B + 5B/level) | Creator gets 25% at deploy, vault owner claims 5B per level up to 200B total at level 30. Prevents governance domination at launch. | ✓ v9.0 |
| Remove death clock pause for governance | Chainlink death + game death + 256 proposals is unrealistic; reduces complexity | ✓ Post-v2.1 |
| Remove activeProposalCount tracking | No on-chain consumer after death clock pause removal; eliminates uint8 overflow surface | ✓ Post-v2.1 |
| Move _voidAllActive before external calls | CEI compliance in _executeSwap; prevents theoretical sibling-proposal reentrancy | ✓ Post-v2.1 |
| Flag-only comment audit (no auto-fix) | Findings list is the deliverable — protocol team decides which to fix before C4A | ✓ Good — 84 findings produced, 5 cross-cutting patterns identified |
| CP-08 fix: subtract pending reservations in _deterministicBurnFrom | Post-gameOver burns must not consume ETH reserved for gambling claimants | ✓ Fixed v3.3, invariant tested |
| CP-06 fix: resolveRedemptionPeriod in _gameOverEntropy | Pending gambling claims must resolve even at game-over boundary | ✓ Fixed v3.3, invariant tested |
| Seam-1 fix: gameOver() guard on DGNRS.burn() | Prevent gambling claims under unreachable contract address | ✓ Fixed v3.3, verified by warden simulation |
| CP-07 fix: split-claim design for coinflip dependency | ETH pays immediately; BURNIE deferred until coinflip resolves | ✓ Fixed v3.3, invariant tested |
| Remove BurnieCoin forwarding wrappers (creditFlip, creditFlipBatch, etc.) | Callers pay extra gas for hop; all contracts are same-owner so access control between them is redundant routing | ✓ v10.1 — 7 wrappers removed, 18 call sites rewired |
| Vault-owner access control on Game (replacing Admin middleman) | Admin.stakeGameEthToStEth and Admin.setLootboxRngThreshold were pure forwards; Game checks vault owner directly | ✓ v10.1 |
| Merge mintForCoinflip into mintForGame | Two identical mint functions with different caller checks; merged to single function accepting COINFLIP + GAME | ✓ v10.1 |
| Replace 30-day BURNIE ban with gameOverPossible flag | Static elapsed-time ban replaced by dynamic drip-projection check; flag set at L10+ purchase-phase entry when futurePool drip cannot cover nextPool deficit | ✓ v11.0 Phase 151 |
| WAD-scale geometric drip projection (0.9925 decay) | Conservative 0.75% daily decay rate via closed-form series futurePool*(1-0.9925^n); ~700 gas for _wadPow | ✓ v11.0 Phase 151 |
| BURNIE lootbox far-future redirect (bit 22) when flag active | Current-level tickets redirect to far-future key space; near-future rolls (currentLevel+1..+6) land normally | ✓ v11.0 Phase 151 |
| Repack slot 0 to 32/32 bytes (add ticketsFullyProcessed + gameOverPossible) | Fill 2-byte padding in slot 0 to eliminate wasted space | ✓ v16.0 Phase 168 |
| Downsize currentPrizePool from uint256 to uint128 | 340B ETH exceeds total supply; uint128 saves a full slot | ✓ v16.0 Phase 168 |
| Eliminate EndgameModule entirely | 3 functions redistributed to existing modules; reduces delegatecall overhead and deploy complexity | ✓ v16.0 Phases 169-171 |
| claimWhalePass to WhaleModule (not JackpotModule) | WhaleModule already has whale-related logic; better semantic fit | ✓ v16.0 Phase 171 |
| NonceBurner placeholder in fuzz test deploy | Empty contract preserves nonce ordering after EndgameModule deletion | ✓ v16.0 Phase 171 |
| Cache affiliate bonus in mintPacked_ bits [185-214] | Eliminate 5 cold SLOADs (~10,500 gas) from every activity score read; write piggybacks on existing SSTORE | ✓ v17.0 Phase 173 |
| Affiliate bonus rate 1 point per 0.5 ETH (was 1 per 1 ETH) | Easier to reach cap; doubles reward for moderate affiliates | ✓ v17.0 Phase 173 |
| Remove phantom creditFlip from redemption resolution | creditFlip(SDGNRS, burnieToCredit) inflated coinflip pool without backing; removed from all 3 resolution paths | ✓ v23.0 Phase 201 |
| resolveRedemptionPeriod changed to void return | No caller uses the return value; prevents future accidental credit | ✓ v23.0 Phase 201 |

## Known Issues (Documented, Not Blocking)

| ID | Severity | Description |
|----|----------|-------------|
| WAR-01 | Medium | Compromised admin + 7-day community inattention enables coordinator swap |
| WAR-02 | Medium | Colluding voter cartel at day 6 (5% threshold) |
| WAR-06 | Low | Admin spam-propose gas griefing (no per-proposer cooldown) |
| ~~TQ-01~~ | ~~Medium~~ | ~~RESOLVED v3.9 Phase 77: combined pool replaces _tqWriteKey with _tqReadKey + _tqFarFutureKey~~ |

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Bit 22 reserved for far-future key space | Collision-free third key space for tickets > level+6, reduces max level to 2^22-1 (still millennia) | Good |
| Combined pool approach over simple TQ-01 one-line fix | Reads both _tqReadKey + _tqFarFutureKey, eliminates _tqWriteKey from jackpot entirely | Good — TQ-01 resolved |
| rngLocked guard with phaseTransitionActive exemption | Prevents permissionless FF writes during VRF window while allowing advanceGame-origin writes | Good — proven safe by RNG commitment window proof |
| Fix sampleFarFutureTickets to use _tqFarFutureKey | Was reading wrong key space (_tqWriteKey), BAF FF slices were always empty | Good — DSC-02 resolved |
| BAF scatter: per-round fixed payout, empty rounds return | Prevents few winners from splitting full 70% scatter pool; unfilled rounds recycle to future pool | Good |
| BAF scatter: 20% from current level, 80% random near-future | Better distribution — current level holders get guaranteed share, near-future spread evenly across +1..+6 | Good |

## Current State

v32.0 Backfill Idempotency + purchaseLevel Underflow Audit started 2026-04-30. Awaiting requirements + roadmap. Contract baseline: v31.0 HEAD `cc68bfc7` → HEAD `48554f8f` + WIP guards in `DegenerusGameAdvanceModule.sol`. READ-only posture LIFTED for this milestone — WIP fixes commit per explicit approval rule. Deliverable target: `audit/FINDINGS-v32.0.md`.

## Completed Milestone: v17.1 Comment Correctness Sweep

**Status:** Complete (2026-04-03)

**Result:** 4 phases (175-178), 14 plans. Full comment sweep of all 40 production contracts (modules, core game, tokens, infrastructure, libraries, interfaces, misc). 72 findings identified (30 LOW, 42 INFO), 56 fixed in commit 9c3e31bd. 0 regressions from v3.1/v3.5 prior sweeps. Key fixes: DGNRS→sDGNRS recipient corrections, stale module lists (EndgameModule removed), mintPacked_ bit layout updated for v17.0 cache fields, affiliate bonus tiered rate docs, WWXRP decimal scaling for real 6-decimal wXRP. All 8/8 requirements satisfied.

## Completed Milestone: v12.0 Level Quests

**Status:** Complete (2026-04-01)

**Result:** 3 phases (153-155), 3 plans. Planning-only milestone — produced design specification for per-level quest system. 536-line spec (eligibility, mechanics, 10x targets, storage, completion flow). 852-line integration map (10 contracts, 6 handler sites). Economic analysis: BURNIE inflation bounded at 12M/month worst-case (<16% ticket volume). Gas analysis: +22.4K quest roll (0.32%), eligibility 150-280 hot. 1.99x safety margin preserved. gameOverPossible interaction disproven (disjoint state domains). All 14 requirements satisfied.

## Completed Milestone: v11.0 BURNIE Endgame Gate

**Status:** Complete (2026-03-31)

**Result:** 2 phases (151-152), 4 plans. 30-day BURNIE ban replaced with gameOverPossible flag — dynamic drip-projection-based endgame detection at L10+ purchase-phase. WAD-scale geometric series (_wadPow + _projectedDrip) in AdvanceModule. MintModule reverts with GameOverPossible when flag active; LootboxModule redirects current-level BURNIE tickets to far-future key space (bit 22). Delta audit: 10 functions, 10 SAFE, 0 VULNERABLE, 1 INFO (V11-001 stale comment). RNG commitment window: 3 paths SAFE. Gas ceiling: +21K gas worst-case (0.3% increase), 2.0x margin preserved. All 13 requirements satisfied.

**Grand total across all milestones:** 148+ findings (16 LOW, 129+ INFO), 0 MEDIUM/HIGH outstanding. KNOWN-ISSUES.md comprehensive with 35+ entries.

## Completed Milestone: v10.3 Delta Adversarial Audit (v10.1 Changes)

**Status:** Complete (2026-03-30)

**Result:** 2 phases (149-150). 38 functions audited across 12 contracts: 30 SAFE, 8 INFO, 0 VULNERABLE. BurnieCoinflip creditor expansion, vault-owner access control, mintForGame merger all verified safe. Storage layouts clean (12 contracts via forge inspect). No KNOWN-ISSUES updates needed.

## Completed Milestone: v10.2 Ticket Mint Gas Optimization

**Status:** Complete (2026-03-30)

**Result:** 1 phase (147). Static gas analysis of advanceGame ticket-processing loop confirmed WRITES_BUDGET_SAFE=550 is optimal. 2.0x safety margin under worst-case adversarial conditions (7M vs 14M ceiling). Cap could safely go to 800 (1.39x margin) but per-ticket gas is nearly identical — more calls just spreads bounty wider. No code changes needed. Phase 148 (implementation) skipped.

## Completed Milestone: v10.1 ABI Cleanup

**Status:** Complete (2026-03-30)

**Result:** 3 phases (144-146), 5 plans. Scanned 25 production contracts (~225 functions). Removed 9 forwarding wrappers (7 BurnieCoin + 2 Admin), 16 unused views from DegenerusGame, plus 3 bonus removals (creditCoin, onlyFlipCreditors, mintForCoinflip merge). BurnieCoinflip creditors expanded to GAME+COIN+AFFILIATE+ADMIN. Admin middleman replaced with vault-owner access control on Game. ~238 lines removed, 1319 Hardhat tests passing.

## Completed Milestone: v10.0 Audit Submission Ready

**Status:** Complete (2026-03-29)

**Result:** 3 phases (141-143), 3 plans. Delta adversarial audit of dailyIdx init, backfill cap, turbo-at-L0 removal (all SAFE, 2 INFO). Documentation + submission readiness finalized. Vault sDGNRS burn/claim + self-win burn delta audit verified safe. votingSupply on sDGNRS, vault excluded from governance.

v9.0 Contest Dry Run shipped (2026-03-28). 5 wardens, 152 attack surfaces, 0 Medium+ findings, $0 projected payout. dailyIdx init + backfill cap committed post-milestone.

**Grand total across all milestones:** 147+ findings (16 LOW, 128+ INFO), 0 MEDIUM/HIGH outstanding. KNOWN-ISSUES.md comprehensive with 35+ entries. C4A contest README finalized.

Prior milestones: v1.0-v1.2 (RNG), v1.3 (sDGNRS split), v2.0 (C4A prep), v2.1 (governance), v3.0 (full audit), v3.1 (comments), v3.2 (delta + re-scan), v3.3 (gambling burn audit), v3.4 (skim + lootbox audit), v3.5 (final polish), v3.6 (VRF stall resilience), v3.7 (VRF path audit), v3.8 (VRF commitment window), v3.9 (far-future ticket fix), v4.0 (ticket lifecycle + RNG re-audit), v4.1 (ticket lifecycle integration tests), v4.2 (daily jackpot chunk removal), v4.3 (prizePoolsPacked — closed early), v4.4 (BAF cache-overwrite fix), v5.0 (ultimate adversarial audit), v6.0 (test cleanup + fixes + charity), v7.0 (delta adversarial audit), v8.0 (pre-audit hardening), v8.1 (final audit prep), v9.0 (contest dry run), v10.0 (audit submission ready), v10.1 (ABI cleanup), v10.2 (writes cap analysis — no change needed), v10.3 (v10.1 delta audit), v11.0 (BURNIE endgame gate), v12.0 (level quests design), v13.0 (level quests implementation), v14.0 (activity score + gas optimization), v15.0 (delta audit), v16.0 (module consolidation + storage repack).

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-05-14 — v40.0 milestone OPEN (Unified Whole-Ticket Award Protocol + Whole-BURNIE Floor). Audit baseline: v39.0 closure HEAD `MILESTONE_V39_AT_HEAD_6a7455d1`. Multi-phase shape (5 surface-split + 1 terminal audit = 6 phases 275-280) per v33/v34/v35/v37 precedent. Phase progress: 275 (auto-resolve LootboxModule Bernoulli) + 276 (JackpotModule:2216 BAF Bernoulli — contract commit `c473867e` + test commit `1568fd5c`, VERIFICATION passed 10/10) COMPLETE; 277 (event surface unification + sentinel retirement) COMPLETE — contract wave (USER-APPROVED commit `02fb7085`; `LootboxTicketRoll` deleted, `LootBoxOpened`/`BurnieLootOpen`/`JackpotTicketWin` gain `roundedUp`, `index != type(uint48).max` sentinel retired) + test wave (commit `6fbee850`) + CR-01 gap-closure (commit `f7a6fccd`: cold-bust WWXRP consolation re-gated on a dedicated `payColdBustConsolation` param so manual paths pay and auto-resolve stays silent; `bonusBurnie` field + `LootBoxWwxrpReward` event trimmed; `allowWhalePass`/`allowLazyPass` collapsed to `allowPasses`), VERIFICATION passed 14/14. 278 (JackpotModule cleanup + ENT-05 keccak refactor + wrapper retirement) COMPLETE — contract wave (USER-APPROVED commit `8a81a87c`; `_jackpotTicketRoll` entropy evolution swapped from `EntropyLib.entropyStep` xorshift to `EntropyLib.hash2` keccak self-mix, all 3 `JackpotTicketWin` emits unified onto whole-ticket counts, `EntropyLib.entropyStep` + the zero-caller `_queueLootboxTickets` wrapper deleted, `MintModule:649` comment touched; storage layout byte-identical vs `6a7455d1`, deployed bytecode −689 bytes) + test wave (commit `c3baf694`; TST-CLEAN-01 keccak invariant + TST-CROSS-01 cross-surface mixing + TST-CLEAN-02/03 regression + a v40.0 SURF re-baseline block superseding the stale v36/v37/v38 byte-identity gates) + regression gap-fix (commit `a91dac85`: superseded the stale `[02a]` MintModule byte-identity gate in `LootboxAutoResolveRegression.test.js`), VERIFICATION passed 10/10. Target features: auto-resolve LootboxModule Bernoulli + JackpotModule:2216 BAF Bernoulli + event surface unification (drop `LootboxTicketRoll`, fold into existing events, retire `index != type(uint48).max` sentinel) + JackpotModule cosmetic cleanup + ENT-05 BAF xorshift refactor + whole-BURNIE-coin floor at 3 RNG-influenced BURNIE-award sites (LootboxModule:1080 + JackpotModule:1842 + JackpotModule:1922) + terminal audit deliverable. Decision-anchor IDs: D-40N-GRANULARITY-01 (TICKET granularity settled) + D-40N-SILENT-01 (auto-resolve + jackpot silent on cold-bust) + D-40N-EVT-BREAK-01 (breaking topic-hashes accepted) + D-40N-MINTBOOST-OUT-01 (mint-boost retention) + D-40N-SENTINEL-RETIRE-01 (index sentinel retirement) + D-40N-BUR-FLOOR-01 (A1 floor-per-winner mechanic) + D-40N-BUR-DUST-01 (sub-1-BURNIE residues evaporate) + D-40N-BUR-SILENT-01 (no consolation / no replacement event on BUR) + D-40N-BUR-MINTBOOST-OUT-01 (deterministic BURNIE-award sites out of scope). Detailed v37.0 + v38.0 + v39.0 milestone records in `.planning/MILESTONES.md` + `.planning/STATE.md` "Last Shipped Milestone" block.*
