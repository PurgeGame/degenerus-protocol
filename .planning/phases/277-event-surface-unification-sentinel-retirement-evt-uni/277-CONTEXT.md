# Phase 277: Event Surface Unification + Sentinel Retirement (EVT-UNI) - Context

**Gathered:** 2026-05-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Consolidate the v39.0-additive `LootboxTicketRoll` event into the existing per-action events and retire the `_resolveLootboxCommon` `index != type(uint48).max` behavior-gating sentinel.

- DROP `LootboxTicketRoll` entirely from `contracts/interfaces/IDegenerusGameModules.sol` (the `IDegenerusGameLootboxModule` interface block) AND the contract-level event block of `contracts/modules/DegenerusGameLootboxModule.sol` — zero remaining emission sites (EVT-UNI-01).
- Restructure `LootBoxOpened` per EVT-UNI-02: add a real `lootboxIndex` indexed topic + split out `day`, and add `(uint32 preRollTickets, bool roundedUp)`. Currently `LootBoxOpened`'s 2nd field is named `index` but emits `day`.
- Add `(uint32 preRollTickets, bool roundedUp)` to `BurnieLootOpen` (EVT-UNI-03); add `bool roundedUp` to `JackpotTicketWin` (EVT-UNI-04).
- Retire the `index != type(uint48).max` sentinel branch in `_resolveLootboxCommon` (EVT-UNI-05); `uint48 index` keeps only its event-identifier role. Auto-resolve callers (`resolveLootboxDirect` + `resolveRedemptionLootbox`) stop passing `type(uint48).max` (EVT-UNI-05, EVT-UNI-06).
- Breaking event topic-hashes accepted per D-40N-EVT-BREAK-01 (EVT-UNI-08).

**Out of scope** (other phases): `_queueLootboxTickets` wrapper / `xTICKET_SCALE` cleanup / ENT-05 xorshift refactor (Phase 278); whole-BURNIE floor (Phase 279); terminal delta audit (Phase 280).

Wave shape: 1 USER-APPROVED batched contract commit `feat(277): event surface unification + sentinel retirement [EVT-UNI-01..08]` + 1 USER-APPROVED batched test commit `test(277): event topic-hash changes + LootboxTicketRoll removal + sentinel retirement + field consistency [TST-EVT-UNI-01..06]` (`feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` + `feedback_manual_review_before_push.md`).

</domain>

<decisions>
## Implementation Decisions

### Consolation Gate After Sentinel Retirement

- **D-277-CONSOLATION-GATE-01:** After the `index != type(uint48).max` sentinel retires, the manual-path WWXRP cold-bust consolation (`whole == 0` → `wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION)` + `LootBoxWwxrpReward` emit) is gated on the existing `bool emitLootboxEvent` parameter of `_resolveLootboxCommon`.
  - **Why:** The sentinel currently gates TWO things — (a) the `LootboxTicketRoll` emit and (b) the manual-vs-auto-resolve consolation asymmetry. EVT-UNI-01 removes (a). D-40N-SILENT-01 explicitly PRESERVES (b): manual keeps the `LOOTBOX_WWXRP_CONSOLATION = 1 ether` consolation, auto-resolve stays silent on cold-bust. So the sentinel cannot fully retire without a replacement gate. `emitLootboxEvent` is already passed `true` by both manual callers (`openLootBox` L616, `openBurnieLootBox` L671) and `false` by both auto-resolve callers (`resolveLootboxDirect` L714, `resolveRedemptionLootbox` L750) — exactly 1:1 with the consolation asymmetry. No new parameter added to the already-14-arg signature.
  - **Accepted coupling:** `emitLootboxEvent` now means "this is a manual, player-initiated open" — it gates both the `LootBoxOpened` emit AND the cold-bust consolation. The two always travel together (a manual open emits `LootBoxOpened` and is eligible for consolation; an auto-resolve does neither). Planner documents this dual role in the parameter's NatSpec.
  - **Interaction with D-277-AR-EMIT-01:** D-277-AR-EMIT-01 flips auto-resolve callers to emit `LootBoxOpened`. The planner must NOT achieve that by flipping their `emitLootboxEvent` arg to `true` — that would also (wrongly) enable auto-resolve cold-bust consolation, violating D-40N-SILENT-01. Auto-resolve `LootBoxOpened` emission must be wired independently of the `emitLootboxEvent` consolation gate (e.g. emit at the caller, or a separate code path). This is a hard constraint for plan-phase.

### LootBoxOpened Field Types — Whole-Token BURNIE Semantics

- **D-277-EVT-WHOLE-BURNIE-01:** `LootBoxOpened` keeps the narrow `uint32 burnie` field from EVT-UNI-02, but the emitted VALUE changes to a whole-BURNIE token count — `burnieAmount / 1 ether` — not the raw wei value.
  - **Why:** EVT-UNI-02's literal signature (`uint32 burnie`, `uint16 bonus`) would catastrophically truncate the current wei-scale values. Traced: `burnieAmount = burnieNoMultiplier + burniePresale + bonusBurnie`, where `burnieOut = (burnieBudget * PRICE_COIN_UNIT) / targetPrice`, `PRICE_COIN_UNIT = 1000 ether`. BURNIE is 18-decimal — `burnieAmount` lands on the `1e18`+ wei scale; `uint32` max is ~`4.29e9`. Emitting whole-token counts (`/ 1 ether`) brings the magnitude into `uint32` range and aligns with Phase 279's whole-BURNIE floor (post-Phase-279 these amounts are whole multiples of 1 ether anyway).
  - **Semantic change — indexers read token counts, not wei.** This is a deliberate consequence of D-40N-EVT-BREAK-01 (breaking topic-hashes already accepted; indexer rebuild expected). Applies to `LootBoxOpened` only.
  - **`uint128 amount` stays wei** — ETH amounts fit in `uint128` with comfortable headroom; no semantic change for the `amount` field. `uint32 preRollTickets` is fine (already `uint32 futureTickets` today).

- **D-277-BONUS-WIDTH-01:** `LootBoxOpened.bonus` is typed `uint32` — OVERRIDES EVT-UNI-02's `uint16 bonus`.
  - **Why:** `bonus` = the `bonusBurnie` local (`bonusBurnie = (burniePresale * LOOTBOX_PRESALE_BURNIE_BONUS_BPS) / 10_000`, 6200 bps = 62% of the presale BURNIE portion). Even as a whole-token count, `uint16` (max 65,535) is far too small — `bonus` is a large fraction of `burnie`, which itself needs `uint32` precisely because the reward magnitude can reach billions of whole tokens on a large EV-multiplied lootbox. A whale lootbox blows past 65,535 whole BURNIE of bonus easily. `uint32` for `bonus` matches the sibling `burnie` field's magnitude class.
  - **Planner still derives the worst-case bound** per `feedback_gas_worst_case.md` discipline — confirm `uint32` (~4.29B whole tokens) has headroom for the theoretical-max `bonus`; escalate if not.

### Auto-Resolve LootBoxOpened Emission (EVT-UNI-06 / D-40N-AR-EMIT-01)

- **D-277-AR-EMIT-01:** EVT-UNI-06 is LOCKED to option (a) — ADD `LootBoxOpened` emission to BOTH `resolveLootboxDirect` and `resolveRedemptionLootbox`. Auto-resolve no longer stays silent on `LootBoxOpened`.
  - **Why:** Unified event-emission model; auto-resolve `LootBoxOpened` is field-consistent with the manual paths so off-chain consumers read one event shape across all four ticket-award entry points. Roadmap's stated default.
  - **Gas cost acknowledged:** option (a) adds a `LootBoxOpened` `LOGn` to the high-volume decimator-claim path. Planner reports the per-op gas delta on that path in the contract commit message (`feedback_gas_worst_case.md`).
  - **Wiring constraint:** see D-277-CONSOLATION-GATE-01 — do NOT enable this by flipping `emitLootboxEvent` to `true` on the auto-resolve callers (that would also enable cold-bust consolation, violating D-40N-SILENT-01). Plan-phase decides the concrete wiring (caller-side emit vs. a dedicated emit-without-consolation path).

- **D-277-AR-INDEX-01:** `resolveLootboxDirect` + `resolveRedemptionLootbox` pass `lootboxIndex = 0` (NOT `type(uint48).max`) to `_resolveLootboxCommon`.
  - **Why:** These callers resolve ETH directly and never open a queued per-player lootbox, so there is no meaningful storage index. With the sentinel retired, `lootboxIndex` carries no behavior — it is purely an event-emission identifier. `0` is a clean sentinel-free default; any collision with a manual `index == 0` is cosmetic only (the value gates nothing). EVT-UNI-05's "pass real `index`" is satisfied in spirit — auto-resolve has no real index to pass, so `0` is the canonical "no index" value.

### Claude's Discretion

- **Final `LootBoxOpened` field order** — EVT-UNI-02 says "TBD by plan-phase for optimal slot packing." Planner finalizes; note event args don't pack like storage, but indexed-topic vs data-field placement and reader ergonomics still matter.
- **`BurnieLootOpen` field handling** — EVT-UNI-03 adds only `(uint32 preRollTickets, bool roundedUp)` with "same semantics"; it does NOT restructure `BurnieLootOpen`'s existing fields. So `BurnieLootOpen.burnieAmount` / `burnieReward` stay wei `uint256` while `LootBoxOpened.burnie` becomes a whole-token `uint32` — a deliberate asymmetry scoped by the requirements. Planner: implement as scoped; if it believes `BurnieLootOpen` should also adopt whole-token semantics for consistency, FLAG to the user rather than silently widening scope.
- **`JackpotTicketWin.roundedUp` capture** — `_jackpotTicketRoll` currently does `if (frac != 0 && ...) { whole += 1; }` with no `roundedUp` bool (Phase 276 left the event surface untouched per D-276-EVT-STATUSQUO-01). EVT-UNI-04 needs the bool captured and threaded to the emit at `DegenerusGameJackpotModule.sol:2246`. The two trait-matched emit sites (`:705`, `:1008`) pass `roundedUp = false` (trait-matched paths have zero fractional part). Planner finalizes.
- **NatSpec / comment updates** — bit-allocation NatSpec at `DegenerusGameLootboxModule.sol:880-892` (bits[152..167] still consumed on both paths — D-275-NATSPEC-01 already covers this; no change needed unless the sentinel-retirement wording references it); event-doc NatSpec blocks for `LootBoxOpened` / `BurnieLootOpen` / `JackpotTicketWin`; the inline `LootboxTicketRoll`-referencing comments at `DegenerusGameLootboxModule.sol:1052`, `:873-875`. All per `feedback_no_history_in_comments.md` — describe what IS, not what changed.
- **Test filenames + placement** — follow Phase 275 / 276 precedent (`test/stat/`, `test/edge/`, `test/unit/`, `test/regression/`). REQUIREMENTS.md §TST-EVT-UNI header suggests `test/lootbox/` + `test/jackpot/` + `test/regression/`; planner reconciles.
- **Gas-delta worst-case derivation** — per `feedback_gas_worst_case.md`: derive the theoretical worst case FIRST (likely the manual `openLootBox` path comparing `LootboxTicketRoll` LOG3 removal vs. the larger `LootBoxOpened` payload, plus the decimator-claim path's new `LootBoxOpened` LOGn), then benchmark. Report bytecode + gas delta in the contract commit message.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project + Milestone Anchors
- `.planning/PROJECT.md` — v40.0 milestone definition; D-40N-* decision anchors (D-40N-EVT-BREAK-01 breaking topic-hashes, D-40N-SENTINEL-RETIRE-01 sentinel retirement, D-40N-AR-EMIT-01 auto-resolve emission deferral, D-40N-SILENT-01 silent-on-cold-bust); v39.0 closure baseline `MILESTONE_V39_AT_HEAD_6a7455d1`.
- `.planning/ROADMAP.md` §"Phase 277: Event Surface Unification + Sentinel Retirement (EVT-UNI)" — goal, dependencies (Phase 275 + 276), requirements list, success criteria 1–6.
- `.planning/REQUIREMENTS.md` §EVT-UNI (EVT-UNI-01..08) + §TST-EVT-UNI (TST-EVT-UNI-01..06) — requirement-level specs. NOTE: EVT-UNI-02's literal `LootBoxOpened` signature (`uint32 burnie`, `uint16 bonus`) is OVERRIDDEN by D-277-EVT-WHOLE-BURNIE-01 (whole-token semantics) + D-277-BONUS-WIDTH-01 (`uint32 bonus`). EVT-UNI-06 is LOCKED to option (a) by D-277-AR-EMIT-01. Decision anchors D-40N-EVT-BREAK-01, D-40N-SILENT-01, D-40N-AR-EMIT-01 in §Decisions.
- `.planning/MILESTONES.md` §v39.0 — Phase 274 origin of `LootboxTicketRoll` + the `index != type(uint48).max` sentinel; v39.0 closure record.

### Prior Phase Context (carries)
- `.planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-CONTEXT.md` — D-275-HOIST-01 (Bernoulli math already hoisted OUTSIDE the sentinel gate — pre-stages this phase's retirement), D-275-STATUSQUO-01 (auto-resolve callers still pass `type(uint48).max` + `emitLootboxEvent=false` — THIS phase changes both), D-275-NATSPEC-01 (bits[152..167] NatSpec already updated for both paths).
- `.planning/phases/276-jackpotmodule-2216-baf-bernoulli-jpt-br/276-CONTEXT.md` — D-276-EVT-STATUSQUO-01 (`JackpotTicketWin` event surface left untouched in Phase 276; `ticketCount` stays pre-Bernoulli scaled — THIS phase adds `roundedUp`). `_jackpotTicketRoll` Bernoulli math landed at `DegenerusGameJackpotModule.sol:2235` with no `roundedUp` bool.

### v39 Carry Anchors
- `audit/FINDINGS-v39.0.md` §4 — v39 manual-path Bernoulli + `LootboxTicketRoll` + index-sentinel introduction; the surface this phase consolidates.

### Contract Files (audit subject)
- `contracts/modules/DegenerusGameLootboxModule.sol:66-74` — `LootBoxOpened` event def (2nd field named `index` but emits `day`; restructure target per EVT-UNI-02).
- `contracts/modules/DegenerusGameLootboxModule.sol:83-91` — `BurnieLootOpen` event def (add 2 fields per EVT-UNI-03; existing fields unchanged).
- `contracts/modules/DegenerusGameLootboxModule.sol:138-159` — `LootboxTicketRoll` event def + NatSpec block (DELETE entirely per EVT-UNI-01).
- `contracts/modules/DegenerusGameLootboxModule.sol:559` — `openLootBox` (manual caller; `emitLootboxEvent=true`).
- `contracts/modules/DegenerusGameLootboxModule.sol:671-696` — `openBurnieLootBox` `_resolveLootboxCommon` call + `BurnieLootOpen` emit at `:688` (manual; `emitLootboxEvent=true`).
- `contracts/modules/DegenerusGameLootboxModule.sol:704-729` — `resolveLootboxDirect` (auto-resolve; passes `type(uint48).max` + `emitLootboxEvent=false`; D-277-AR-INDEX-01 → `0`, D-277-AR-EMIT-01 → add `LootBoxOpened` emit).
- `contracts/modules/DegenerusGameLootboxModule.sol:739-766` — `resolveRedemptionLootbox` (auto-resolve; same changes).
- `contracts/modules/DegenerusGameLootboxModule.sol:865-934` — `_resolveLootboxCommon` NatSpec + signature (`uint48 index` sentinel param; `bool emitLootboxEvent` — the new consolation gate per D-277-CONSOLATION-GATE-01).
- `contracts/modules/DegenerusGameLootboxModule.sol:1019-1068` — the `if (futureTickets != 0)` block: shared Bernoulli locals (`scaledPre`/`whole`/`frac`/`roundedUp` at `:1037-1043`), the `if (index != type(uint48).max)` sentinel branch at `:1044` (manual consolation + `LootboxTicketRoll` emit at `:1060`; auto-resolve `_queueTickets` at `:1067`). RETIRE the sentinel per EVT-UNI-05.
- `contracts/modules/DegenerusGameLootboxModule.sol:1077-1091` — `coinflip.creditFlip` + the `if (emitLootboxEvent)` `LootBoxOpened` emit at `:1081`.
- `contracts/modules/DegenerusGameLootboxModule.sol:1069-1074` — `burnieAmount` / `bonusBurnie` compute (the values feeding `LootBoxOpened.burnie` / `.bonus`; D-277-EVT-WHOLE-BURNIE-01 `/ 1 ether` applied at the emit).
- `contracts/modules/DegenerusGameLootboxModule.sol:1693-1694` — `burnieOut` magnitude trace (`PRICE_COIN_UNIT = 1000 ether`; evidence for D-277-EVT-WHOLE-BURNIE-01 / D-277-BONUS-WIDTH-01).
- `contracts/interfaces/IDegenerusGameModules.sol:264-280` — `IDegenerusGameLootboxModule` interface block containing the `LootboxTicketRoll` event def (DELETE per EVT-UNI-01). NOTE: roadmap/requirements call this file `IDegenerusGameLootboxModule.sol`; the interface actually lives in `IDegenerusGameModules.sol`.
- `contracts/modules/DegenerusGameJackpotModule.sol:80-95` — `JackpotTicketWin` event def + NatSpec (add `bool roundedUp` per EVT-UNI-04).
- `contracts/modules/DegenerusGameJackpotModule.sol:705` — `JackpotTicketWin` emit, trait-matched path (`roundedUp = false`).
- `contracts/modules/DegenerusGameJackpotModule.sol:1008` — `JackpotTicketWin` emit, near/far-future coin path (`roundedUp = false`).
- `contracts/modules/DegenerusGameJackpotModule.sol:2235-2250` — `_jackpotTicketRoll` Bernoulli predicate (`whole += 1` with NO `roundedUp` bool yet) + `JackpotTicketWin` emit at `:2246` (capture `roundedUp` and thread it per EVT-UNI-04).

### Feedback / Discipline
- `feedback_no_contract_commits.md` — never commit contracts/ or test/ without explicit user approval.
- `feedback_batch_contract_approval.md` — batch all contract edits, present one diff, one approval at the end.
- `feedback_never_preapprove_contracts.md` — orchestrator must NEVER tell agents contract changes are pre-approved.
- `feedback_manual_review_before_push.md` — final user-review gate on the diff before push.
- `feedback_no_dead_guards.md` — the sentinel-retirement is a dead-guard removal; no leftover unreachable branches.
- `feedback_no_history_in_comments.md` — updated NatSpec/comments describe what IS, never what changed.
- `feedback_gas_worst_case.md` — derive theoretical worst case FIRST, then benchmark (drives the gas-delta + uint32-bound discretion items).
- `feedback_design_intent_before_deletion.md` — sentinel retirement: trace why the gate existed (v39 manual-vs-auto-resolve behavior split) before deleting; D-277-CONSOLATION-GATE-01 already captures the surviving behavior the gate protected.
- `feedback_skip_research_test_phases.md` — this is a largely mechanical event-surface refactor; plan-phase may skip the research agent.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`bool emitLootboxEvent` parameter of `_resolveLootboxCommon`** — already 1:1 with the manual-vs-auto-resolve split (manual=`true`, auto-resolve=`false`). Becomes the consolation gate per D-277-CONSOLATION-GATE-01; no new param needed.
- **Hoisted Bernoulli locals** (`scaledPre`, `whole`, `frac`, `roundedUp`) at `DegenerusGameLootboxModule.sol:1037-1043` — Phase 275 D-275-HOIST-01 already computes these OUTSIDE the sentinel gate. After EVT-UNI-05 retires the gate, both branches collapse trivially around these already-shared locals; `roundedUp` is already a live local ready to feed the new `LootBoxOpened.roundedUp` / `BurnieLootOpen.roundedUp` fields. `scaledPre` feeds `preRollTickets`.
- **`_queueTickets(buyer, targetLevel, quantity, rngBypass)` at `DegenerusGameStorage.sol:562`** — early-returns on `quantity == 0`; the unified post-retirement path calls it unconditionally with `whole`.

### Established Patterns
- **Sentinel-gated branching at `:1044`** (`if (index != type(uint48).max)`) — the retirement target. Post-Phase-275 both branches already Bernoulli-roll; the ONLY surviving behavioral difference is the manual-path cold-bust consolation, which moves to the `emitLootboxEvent` gate (D-277-CONSOLATION-GATE-01).
- **`if (emitLootboxEvent)` gate at `:1080`** — currently gates only the `LootBoxOpened` emit. After D-277-CONSOLATION-GATE-01 it also gates the cold-bust consolation; after D-277-AR-EMIT-01 the auto-resolve `LootBoxOpened` emit must be wired SEPARATELY (not via this flag).
- **`LootBoxOpened` 2nd field mislabel** — event field is `uint32 indexed index` but the emit at `:1081` passes `day`. EVT-UNI-02's restructure fixes this: separate `uint48 indexed lootboxIndex` + `uint48 day`.
- **`JackpotTicketWin` has 3 emit sites** — `:705` + `:1008` are trait-matched (`roundedUp=false`); `:2246` is the BAF `_jackpotTicketRoll` path (real `roundedUp`). Adding a field to the event forces all 3 emit sites to supply it.
- **`_jackpotTicketRoll` has no `roundedUp` bool** — `:2235` does `if (...) { whole += 1; }`; EVT-UNI-04 introduces the bool capture.

### Integration Points
- **Mutations confined to:** `DegenerusGameLootboxModule.sol` (event defs + `_resolveLootboxCommon` body + 4 callers), `DegenerusGameJackpotModule.sol` (`JackpotTicketWin` def + 3 emit sites + `_jackpotTicketRoll` `roundedUp` capture), `IDegenerusGameModules.sol` (`LootboxTicketRoll` interface deletion).
- **No new state variables, no new modifiers, no new admin/external entry points** — storage layout byte-identical at v40 phase-close HEAD vs v39 baseline `6a7455d1`. Event signature changes do not affect storage layout.
- **Cross-module byte-identity expected** for MintModule, EntropyLib, JackpotBucketLib, TraitUtils, DegenerusGameStorage helpers (no shared-helper edits).

</code_context>

<specifics>
## Specific Ideas

- **EVT-UNI-02 literal signature is a sketch, not law** — user explicitly accepted that EVT-UNI-02's `uint32 burnie` / `uint16 bonus` would truncate wei-scale values. Resolution: `LootBoxOpened.burnie` / `.bonus` emit whole-BURNIE token counts (`/ 1 ether`), `bonus` widened to `uint32`. The roadmap text + REQUIREMENTS.md EVT-UNI-02 should be corrected to match (flagged to user at context-close; not edited mid-discuss).
- **`burnieAmount` magnitude evidence** — `burnieOut = (burnieBudget * 1000 ether) / targetPrice`; BURNIE is 18-decimal; `burnieAmount` reaches `1e18`+ wei, billions of whole tokens on large EV-multiplied lootboxes. This is why `burnie` needs `uint32` (whole-token) and `bonus` cannot be `uint16`.
- **Consolation/emission wiring is the subtle part** — `emitLootboxEvent` now does double duty (gate `LootBoxOpened` emit + gate cold-bust consolation). Auto-resolve must emit `LootBoxOpened` (option a) WITHOUT triggering consolation. Plan-phase must keep these decoupled — see D-277-CONSOLATION-GATE-01 / D-277-AR-EMIT-01.

</specifics>

<deferred>
## Deferred Ideas

- **`_queueLootboxTickets` wrapper retirement + `xTICKET_SCALE` cleanup + ENT-05 BAF xorshift refactor + cross-surface regression (TST-CROSS-01)** — Phase 278 JPT-CLEAN.
- **Whole-BURNIE floor at lootbox spin + near/far-future coin jackpot** — Phase 279 BUR. Note: Phase 279's whole-BURNIE floor makes `burnieAmount` a whole multiple of 1 ether at the source, which post-hoc validates D-277-EVT-WHOLE-BURNIE-01's whole-token event semantics for `LootBoxOpened` (the `/ 1 ether` becomes lossless).
- **`BurnieLootOpen` whole-token semantics** — considered: should `BurnieLootOpen.burnieAmount` / `burnieReward` also switch to whole-token counts for consistency with `LootBoxOpened`? EVT-UNI-03 scopes `BurnieLootOpen` to only the 2 new fields, so it stays wei `uint256` this phase. If the planner thinks the asymmetry is wrong, FLAG to user — do not silently widen scope.
- **ROADMAP/REQUIREMENTS text correction** — EVT-UNI-02's `uint32 burnie` / `uint16 bonus` and "TBD" EVT-UNI-06 should be updated to reflect D-277-EVT-WHOLE-BURNIE-01 + D-277-BONUS-WIDTH-01 + D-277-AR-EMIT-01. Flagged to user at context-close; a docs-only follow-up, not part of the contract/test waves.

### Reviewed Todos (not folded)
None — `todo.match-phase` returned zero matches for Phase 277.

</deferred>

---

*Phase: 277-Event Surface Unification + Sentinel Retirement (EVT-UNI)*
*Context gathered: 2026-05-14*
