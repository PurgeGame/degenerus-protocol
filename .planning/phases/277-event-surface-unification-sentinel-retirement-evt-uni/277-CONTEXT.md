# Phase 277: Event Surface Unification + Sentinel Retirement (EVT-UNI) - Context

**Gathered:** 2026-05-14 (revised 2026-05-14)
**Status:** Ready for planning

> **⚠ Plans 277-A / 277-B + 277-PATTERNS.md are STALE.** They were built on the
> superseded context (whole-token BURNIE semantics, `preRollTickets` additions,
> auto-resolve `LootBoxOpened` emission). This revision overrides those
> decisions — re-run `/gsd-plan-phase 277` before executing.

<domain>
## Phase Boundary

Consolidate the v39.0-additive `LootboxTicketRoll` event into the existing per-action events and retire the `_resolveLootboxCommon` `index != type(uint48).max` behavior-gating sentinel.

- DROP `LootboxTicketRoll` entirely from `contracts/interfaces/IDegenerusGameModules.sol` (the `IDegenerusGameLootboxModule` interface block) AND the contract-level event block of `contracts/modules/DegenerusGameLootboxModule.sol` — zero remaining emission sites (EVT-UNI-01).
- Restructure `LootBoxOpened` per EVT-UNI-02: fix the mislabel (2nd field is named `index` but emits `day`) — split into a proper `day` field + a real `lootboxIndex`; add `bool roundedUp`. **Field widths stay wide — see D-277-EVT-WIDE-01 (EVT-UNI-02's literal `uint32 burnie` / `uint16 bonus` narrowing is REJECTED).**
- Add `bool roundedUp` to `BurnieLootOpen` (EVT-UNI-03) and to `JackpotTicketWin` (EVT-UNI-04). **`preRollTickets` is NOT added — see D-277-NO-PREROLL-01 (redundant with the existing scaled `futureTickets` / `tickets` fields).**
- Retire the `index != type(uint48).max` sentinel branch in `_resolveLootboxCommon` (EVT-UNI-05); `uint48 index` keeps only its event-identifier role on the manual `LootBoxOpened` emit. Auto-resolve callers (`resolveLootboxDirect` + `resolveRedemptionLootbox`) stop passing `type(uint48).max` (EVT-UNI-05, EVT-UNI-06).
- **Auto-resolve emits NO `LootBoxOpened` — EVT-UNI-06 resolves to "stay silent" (D-277-AR-SILENT-01).**
- Breaking event topic-hashes accepted per D-40N-EVT-BREAK-01 (EVT-UNI-08).

**Out of scope** (other phases): `_queueLootboxTickets` wrapper / `xTICKET_SCALE` cleanup / ENT-05 xorshift refactor (Phase 278); whole-BURNIE floor (Phase 279); terminal delta audit (Phase 280).

Wave shape: 1 USER-APPROVED batched contract commit `feat(277): event surface unification + sentinel retirement [EVT-UNI-01..08]` + 1 USER-APPROVED batched test commit `test(277): event topic-hash changes + LootboxTicketRoll removal + sentinel retirement + field consistency [TST-EVT-UNI-01..06]` (`feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` + `feedback_manual_review_before_push.md`).

</domain>

<decisions>
## Implementation Decisions

### Key Premise — Event Fields Have No Storage Slots

The whole EVT-UNI-02 "narrow `uint32 burnie` / `uint16 bonus` for slot packing" rationale is **invalid**: event non-indexed data fields are ABI-encoded as full 32-byte words regardless of declared type. `uint32 burnie` and `uint256 burnie` produce *identical* `LOG` gas. The only real event gas levers are: **(1) number of `LOG` emissions, (2) number of indexed topics, (3) number of non-indexed params** — never their declared width. This premise drives D-277-EVT-WIDE-01, D-277-NO-PREROLL-01, and D-277-AR-SILENT-01.

### Event Field Widths — No Truncation, Keep Wide

- **D-277-EVT-WIDE-01:** `LootBoxOpened` keeps `amount`, `burnie`, `bonusBurnie` as `uint256` wei — exactly as today. EVT-UNI-02's literal `uint32 burnie` / `uint16 bonus` narrowing is **REJECTED**.
  - **Why:** narrowing a non-indexed event field saves zero gas (see Key Premise) and only introduces truncation risk. `burnieAmount` is 18-decimal and reaches billions of whole tokens on large EV-multiplied lootboxes — `uint32` (~4.29B) overflows; wei-scale values overflow `uint32` instantly. `uint256` wei = zero truncation, identical `LOG` gas, no `/ 1 ether` divisions in the hot path, no indexer-breaking semantic change.
  - **SUPERSEDES / KILLS:** D-277-EVT-WHOLE-BURNIE-01 and D-277-BONUS-WIDTH-01 (both removed — they solved a non-problem and created a real one).
  - `uint24 futureLevel`, `uint32 futureTickets` keep their current widths (already adequate; scaled ticket count fits `uint32`).

### preRollTickets Is Redundant — Add Only roundedUp

- **D-277-NO-PREROLL-01:** EVT-UNI-03's `preRollTickets` field is **NOT** added to `LootBoxOpened` or `BurnieLootOpen`.
  - **Why:** `LootBoxOpened.futureTickets` and `BurnieLootOpen.tickets` **already emit the scaled pre-Bernoulli count.** At `DegenerusGameLootboxModule.sol:1038` `scaledPre = futureTickets`; the emit at `:1086` passes the un-mutated `futureTickets` (the Bernoulli collapse mutates only the local `whole`, never `futureTickets`). `BurnieLootOpen.tickets` is the returned `futureTickets` — same value. So `LootBoxOpened.futureTickets == scaledPre == LootboxTicketRoll.preRollTickets` today. Adding `preRollTickets` duplicates an existing field.
  - **Off-chain derivation:** consumers compute `whole = (futureTickets / TICKET_SCALE) + (roundedUp ? 1 : 0)` and infer the WWXRP-consolation case as `whole == 0 && futureTickets > 0` (corroborated by a same-tx `LootBoxWwxrpReward`) — exactly the `LootboxTicketRoll` semantics, sourced from already-emitted fields.
  - **Gas:** saves one non-indexed data word per lootbox-open emit vs. the original EVT-UNI-03 shape.

### roundedUp Additions — The Only Genuinely New Field

- **D-277-ROUNDEDUP-01:** Add `bool roundedUp` (one non-indexed data word) to `LootBoxOpened`, `BurnieLootOpen`, and `JackpotTicketWin`. This is the **only** new field across all three events.
  - The `roundedUp` local already exists at `DegenerusGameLootboxModule.sol:1041` (Phase 275 hoisted it outside the sentinel gate) — live and ready to feed both `LootBoxOpened` and `BurnieLootOpen`.
  - `_jackpotTicketRoll` has NO `roundedUp` bool today (`DegenerusGameJackpotModule.sol:~2235` does `if (...) { whole += 1; }` bare). EVT-UNI-04 introduces the bool capture and threads it to the `JackpotTicketWin` emit at `:2246`. The two trait-matched emit sites (`:705`, `:1008`) pass `roundedUp = false` (trait-matched paths have zero fractional part).
  - **advanceGame-chain note:** `JackpotTicketWin` is emitted on the advanceGame chain (`_jackpotTicketRoll` runs in the advanceGame window per Phase 276). The +1 data word is unavoidable — `roundedUp` is genuinely new information — but it is the minimum addition.

### Auto-Resolve Stays Silent — advanceGame-Chain Gas

- **D-277-AR-SILENT-01:** `resolveLootboxDirect` and `resolveRedemptionLootbox` emit **NO** `LootBoxOpened`. EVT-UNI-06 resolves to "auto-resolve stays silent." **REVERTS the prior D-277-AR-EMIT-01.**
  - **Why — advanceGame-chain reachability:** `resolveLootboxDirect` is reachable on the advanceGame chain. `processCoinflipPayouts` runs during advanceGame (`DegenerusGameAdvanceModule.sol:1184/1244/1274/1761`) → `BurnieCoinflip` → `DegenerusGameDegeneretteModule._distributePayout` (`:730`) → `_resolveLootboxDirect` (`:797`) → `resolveLootboxDirect`. advanceGame is block-gas-limit-sensitive (the daily jackpot is deliberately split across multiple advanceGame calls to stay under the 15M block limit). Adding a full `LootBoxOpened` LOG3 on that path is a gas cost the project explicitly wants to avoid.
  - **Why — it's redundant anyway:** auto-resolve ticket awards are *already observable*. `_queueTickets` (`DegenerusGameStorage.sol:562`) unconditionally emits `TicketsQueued(buyer, targetLevel, quantity)` — player, level, and whole-ticket count are all there. The "event surface unification" goal (consolidate `LootboxTicketRoll`) does not require auto-resolve to emit a heavy event.
  - **Scope:** the decimator-claim path (`DegenerusGameDecimatorModule._awardDecimatorLootbox:570`) and the sDGNRS-redemption path (`StakedDegenerusStonk.sol:672`) likewise emit nothing extra.

### Consolation Gate — Simplified (sentinel retires with zero tension)

- **D-277-CONSOLATION-GATE-01:** After the `index != type(uint48).max` sentinel retires, the manual-path WWXRP cold-bust consolation (`whole == 0` → `wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION)` + `LootBoxWwxrpReward` emit) stays gated on the existing `bool emitLootboxEvent` parameter of `_resolveLootboxCommon`.
  - **Why it's clean now:** because auto-resolve emits nothing (D-277-AR-SILENT-01), `emitLootboxEvent` continues to gate **both** the `LootBoxOpened` emit **and** the cold-bust consolation, together — exactly as the sentinel did. `emitLootboxEvent` is already passed `true` by both manual callers (`openLootBox`, `openBurnieLootBox`) and `false` by both auto-resolve callers (`resolveLootboxDirect`, `resolveRedemptionLootbox`) — 1:1 with the consolation asymmetry. D-40N-SILENT-01 preserved (manual keeps the consolation; auto-resolve stays silent on cold-bust). No new parameter on the already-14-arg signature.
  - **No decoupling needed:** the earlier "hard constraint — do NOT flip `emitLootboxEvent`, wire auto-resolve emit separately" is **GONE**. It only existed because the prior D-277-AR-EMIT-01 wanted auto-resolve to emit `LootBoxOpened`. With D-277-AR-SILENT-01 that tension dissolves entirely — `emitLootboxEvent` keeps its single coherent meaning ("this is a manual, player-initiated open").
  - The sentinel `index != type(uint48).max` retires with zero residual tension: its two jobs — (a) gate the `LootboxTicketRoll` emit (deleted by EVT-UNI-01) and (b) gate the manual-vs-auto consolation split (moves to `emitLootboxEvent`) — both resolve cleanly.

### Sentinel Retirement Mechanics (EVT-UNI-05)

- The `if (index != type(uint48).max)` branch at `DegenerusGameLootboxModule.sol:1046` retires. Post-Phase-275 both branches already Bernoulli-roll on the shared hoisted locals (`scaledPre` / `whole` / `frac` / `roundedUp` at `:1038-1044`, D-275-HOIST-01). After retirement: the unified path calls `_queueTickets(player, targetLevel, whole, false)` unconditionally (it early-returns on `whole == 0` for the silent auto-resolve cold-bust); the manual cold-bust consolation moves under `if (emitLootboxEvent)`. No leftover unreachable branch (`feedback_no_dead_guards.md`).

- **D-277-AR-INDEX-01 → moot:** with auto-resolve emitting nothing, the `uint48 index` parameter is never read on the auto-resolve path after sentinel retirement. Auto-resolve callers pass `0` (clean default). Cosmetic only — the value gates nothing and is emitted nowhere.

### Claude's Discretion

- **`lootboxIndex` indexed-topic vs. data-field** — EVT-UNI-02 wants a "real `lootboxIndex` indexed topic." An indexed topic costs +375 gas/emit but is filterable off-chain. `LootBoxOpened` currently has 2 indexed params (`player` + the mislabeled `index`); replacing the mislabeled `index`-as-`day` with `lootboxIndex` indexed keeps the topic count flat (`day` becomes a data field). If `day` should also be filterable, that's a 3rd topic = +375 gas. Manual `openLootBox` is NOT on the advanceGame chain, so this is lower-stakes — planner finalizes.
- **Final `LootBoxOpened` field order** — event args don't pack like storage, but indexed-vs-data placement and reader ergonomics still matter. Planner finalizes.
- **`JackpotTicketWin.roundedUp` capture mechanics** — `_jackpotTicketRoll` needs the bool captured at the `whole += 1` site and threaded to the `:2246` emit; the two trait-matched sites (`:705`, `:1008`) pass `false`. Planner finalizes.
- **NatSpec / comment updates** — event-doc NatSpec for `LootBoxOpened` / `BurnieLootOpen` / `JackpotTicketWin`; delete the `LootboxTicketRoll`-referencing inline comments at `DegenerusGameLootboxModule.sol:1052`, `:873-875`; bit-allocation NatSpec at `:880-892` (bits[152..167] still consumed on both paths — D-275-NATSPEC-01 already covers this). All per `feedback_no_history_in_comments.md` — describe what IS, not what changed.
- **Test filenames + placement** — Phase 275/276 precedent (`test/stat/`, `test/edge/`, `test/unit/`, `test/regression/`) vs. REQUIREMENTS.md §TST-EVT-UNI suggestion (`test/lootbox/` + `test/jackpot/` + `test/regression/`); planner reconciles.
- **Gas-delta worst-case derivation** — per `feedback_gas_worst_case.md`: derive the theoretical worst case FIRST, then benchmark. Expected directions: the manual `openLootBox` path is net gas-NEGATIVE (deletes the `LootboxTicketRoll` LOG3, adds only `roundedUp` to `LootBoxOpened`); the advanceGame-chain coinflip-payout auto-resolve path is net-flat-or-negative for the lootbox portion (no new `LootBoxOpened` emit; sentinel branch collapses); `JackpotTicketWin` takes +1 data word on the advanceGame chain. Report bytecode + gas delta in the contract commit message.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project + Milestone Anchors
- `.planning/PROJECT.md` — v40.0 milestone definition; D-40N-* decision anchors (D-40N-EVT-BREAK-01 breaking topic-hashes, D-40N-SENTINEL-RETIRE-01 sentinel retirement, D-40N-AR-EMIT-01 auto-resolve emission deferral, D-40N-SILENT-01 silent-on-cold-bust); v39.0 closure baseline `MILESTONE_V39_AT_HEAD_6a7455d1`.
- `.planning/ROADMAP.md` §"Phase 277: Event Surface Unification + Sentinel Retirement (EVT-UNI)" — goal, dependencies (Phase 275 + 276), requirements list, success criteria 1–6.
- `.planning/REQUIREMENTS.md` §EVT-UNI (EVT-UNI-01..08) + §TST-EVT-UNI (TST-EVT-UNI-01..06) — requirement-level specs. **NOTE — three requirement texts are OVERRIDDEN by this revision:** (1) EVT-UNI-02's literal `LootBoxOpened` signature (`uint32 burnie`, `uint16 bonus`) is REJECTED by D-277-EVT-WIDE-01 — fields stay `uint256` wei; (2) EVT-UNI-03's `preRollTickets` addition is REJECTED by D-277-NO-PREROLL-01 — only `roundedUp` is added; (3) EVT-UNI-06 resolves to "auto-resolve stays silent" per D-277-AR-SILENT-01. Decision anchors D-40N-EVT-BREAK-01, D-40N-SILENT-01, D-40N-AR-EMIT-01 in §Decisions.
- `.planning/MILESTONES.md` §v39.0 — Phase 274 origin of `LootboxTicketRoll` + the `index != type(uint48).max` sentinel; v39.0 closure record.

### Prior Phase Context (carries)
- `.planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-CONTEXT.md` — D-275-HOIST-01 (Bernoulli math already hoisted OUTSIDE the sentinel gate — pre-stages this phase's retirement; `roundedUp` local already live), D-275-STATUSQUO-01 (auto-resolve callers still pass `type(uint48).max` + `emitLootboxEvent=false` — THIS phase changes the index arg), D-275-NATSPEC-01 (bits[152..167] NatSpec already updated for both paths).
- `.planning/phases/276-jackpotmodule-2216-baf-bernoulli-jpt-br/276-CONTEXT.md` — D-276-EVT-STATUSQUO-01 (`JackpotTicketWin` event surface left untouched in Phase 276; `ticketCount` stays pre-Bernoulli scaled — THIS phase adds `roundedUp`). `_jackpotTicketRoll` Bernoulli math landed at `DegenerusGameJackpotModule.sol:~2235` with no `roundedUp` bool.

### v39 Carry Anchors
- `audit/FINDINGS-v39.0.md` §4 — v39 manual-path Bernoulli + `LootboxTicketRoll` + index-sentinel introduction; the surface this phase consolidates.

### Contract Files (audit subject)
- `contracts/modules/DegenerusGameLootboxModule.sol:58-74` — `LootBoxOpened` event def (2nd field named `index` but emits `day`; restructure per EVT-UNI-02 — fix mislabel + add `roundedUp`; fields stay `uint256` wide).
- `contracts/modules/DegenerusGameLootboxModule.sol:76-90` — `BurnieLootOpen` event def (add only `bool roundedUp` per EVT-UNI-03 + D-277-NO-PREROLL-01; existing fields unchanged).
- `contracts/modules/DegenerusGameLootboxModule.sol:134-159` — `LootboxTicketRoll` event def + NatSpec block (DELETE entirely per EVT-UNI-01).
- `contracts/modules/DegenerusGameLootboxModule.sol:559-632` — `openLootBox` (manual caller; `emitLootboxEvent=true`).
- `contracts/modules/DegenerusGameLootboxModule.sol:640-696` — `openBurnieLootBox` `_resolveLootboxCommon` call + `BurnieLootOpen` emit at `:688` (manual; `emitLootboxEvent=true`).
- `contracts/modules/DegenerusGameLootboxModule.sol:703-730` — `resolveLootboxDirect` (auto-resolve; passes `type(uint48).max` + `emitLootboxEvent=false`; D-277-AR-INDEX-01 → `0`, D-277-AR-SILENT-01 → emits nothing).
- `contracts/modules/DegenerusGameLootboxModule.sol:739-766` — `resolveRedemptionLootbox` (auto-resolve; same changes).
- `contracts/modules/DegenerusGameLootboxModule.sol:865-934` — `_resolveLootboxCommon` NatSpec + signature (`uint48 index` sentinel param → event-identifier only; `bool emitLootboxEvent` — the consolation gate per D-277-CONSOLATION-GATE-01).
- `contracts/modules/DegenerusGameLootboxModule.sol:1019-1067` — the `if (futureTickets != 0)` block: shared Bernoulli locals (`scaledPre`/`whole`/`frac`/`roundedUp` at `:1038-1044`), the `if (index != type(uint48).max)` sentinel branch at `:1046` (manual consolation + `LootboxTicketRoll` emit at `:1060`; auto-resolve `_queueTickets` at `:1065`). RETIRE the sentinel per EVT-UNI-05.
- `contracts/modules/DegenerusGameLootboxModule.sol:1069-1091` — `burnieAmount` / `bonusBurnie` compute + `coinflip.creditFlip` + the `if (emitLootboxEvent)` `LootBoxOpened` emit at `:1080-1090` (values fed wide as `uint256` wei per D-277-EVT-WIDE-01 — NO `/ 1 ether`).
- `contracts/interfaces/IDegenerusGameModules.sol:264-280` — `IDegenerusGameLootboxModule` interface block containing the `LootboxTicketRoll` event def (DELETE per EVT-UNI-01). NOTE: roadmap/requirements call this file `IDegenerusGameLootboxModule.sol`; the interface actually lives in `IDegenerusGameModules.sol`.
- `contracts/modules/DegenerusGameJackpotModule.sol:80-95` — `JackpotTicketWin` event def + NatSpec (add only `bool roundedUp` per EVT-UNI-04; `traitId` is already a 3rd indexed topic — `roundedUp` must be non-indexed).
- `contracts/modules/DegenerusGameJackpotModule.sol:705` — `JackpotTicketWin` emit, trait-matched path (`roundedUp = false`).
- `contracts/modules/DegenerusGameJackpotModule.sol:1008` — `JackpotTicketWin` emit, near/far-future coin path (`roundedUp = false`).
- `contracts/modules/DegenerusGameJackpotModule.sol:~2235-2250` — `_jackpotTicketRoll` Bernoulli predicate (`whole += 1` with NO `roundedUp` bool yet) + `JackpotTicketWin` emit at `:2246` (capture `roundedUp` and thread it per EVT-UNI-04).

### advanceGame-Chain Reachability (gas evidence for D-277-AR-SILENT-01)
- `contracts/modules/DegenerusGameAdvanceModule.sol:1184, 1244, 1274, 1761` — `processCoinflipPayouts` invocations inside the advanceGame flow.
- `contracts/modules/DegenerusGameDegeneretteModule.sol:730-793` — `_distributePayout` (3-tier split); `:786` routes the lootbox share to `_resolveLootboxDirect`.
- `contracts/modules/DegenerusGameDegeneretteModule.sol:797-813` — `_resolveLootboxDirect` → delegatecall `resolveLootboxDirect` (the advanceGame-chain auto-resolve entry).
- `contracts/modules/DegenerusGameDecimatorModule.sol:570-601` — `_awardDecimatorLootbox` → `resolveLootboxDirect` (decimator-claim auto-resolve path; high-volume, player-initiated).
- `contracts/StakedDegenerusStonk.sol:672` — `game.resolveRedemptionLootbox` (sDGNRS-redemption auto-resolve path; player-initiated `claimRedemption`).
- `contracts/storage/DegenerusGameStorage.sol:562-590` — `_queueTickets` — unconditionally emits `TicketsQueued(buyer, targetLevel, quantity)`; this is what already makes auto-resolve ticket awards observable.

### Feedback / Discipline
- `feedback_no_contract_commits.md` — never commit contracts/ or test/ without explicit user approval.
- `feedback_batch_contract_approval.md` — batch all contract edits, present one diff, one approval at the end.
- `feedback_never_preapprove_contracts.md` — orchestrator must NEVER tell agents contract changes are pre-approved.
- `feedback_manual_review_before_push.md` — final user-review gate on the diff before push.
- `feedback_no_dead_guards.md` — the sentinel-retirement is a dead-guard removal; no leftover unreachable branches.
- `feedback_no_history_in_comments.md` — updated NatSpec/comments describe what IS, never what changed.
- `feedback_gas_worst_case.md` — derive theoretical worst case FIRST, then benchmark (drives the gas-delta discretion item).
- `feedback_design_intent_before_deletion.md` — sentinel retirement: trace why the gate existed (v39 manual-vs-auto-resolve behavior split) before deleting; D-277-CONSOLATION-GATE-01 captures the surviving behavior the gate protected.
- `feedback_skip_research_test_phases.md` — this is a largely mechanical event-surface refactor; plan-phase may skip the research agent.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`bool emitLootboxEvent` parameter of `_resolveLootboxCommon`** — already 1:1 with the manual-vs-auto-resolve split (manual=`true`, auto-resolve=`false`). Becomes the consolation gate per D-277-CONSOLATION-GATE-01 with NO decoupling needed; no new param.
- **Hoisted Bernoulli locals** (`scaledPre`, `whole`, `frac`, `roundedUp`) at `DegenerusGameLootboxModule.sol:1038-1044` — Phase 275 D-275-HOIST-01 already computes these OUTSIDE the sentinel gate. `roundedUp` is already a live local ready to feed `LootBoxOpened.roundedUp` / `BurnieLootOpen.roundedUp`. After EVT-UNI-05 retires the gate, both branches collapse trivially around these shared locals.
- **`futureTickets` already carries the scaled pre-Bernoulli count** — the `LootBoxOpened` emit at `:1086` and the `openBurnieLootBox` return both use the un-mutated scaled `futureTickets`. This is why `preRollTickets` is redundant (D-277-NO-PREROLL-01).
- **`_queueTickets(buyer, targetLevel, quantity, rngBypass)` at `DegenerusGameStorage.sol:562`** — early-returns on `quantity == 0`; emits `TicketsQueued` unconditionally. The unified post-retirement path calls it with `whole`; its `TicketsQueued` emit is what keeps auto-resolve ticket awards observable without a `LootBoxOpened` (D-277-AR-SILENT-01).

### Established Patterns
- **Event gas model** — non-indexed event params are ABI-encoded as full 32-byte words; `LOG` gas = `375 + 375·topics + 8·data_bytes`. Field width never affects gas. Levers: emission count, indexed-topic count, non-indexed-param count.
- **Sentinel-gated branching at `:1046`** (`if (index != type(uint48).max)`) — the retirement target. Post-Phase-275 both branches already Bernoulli-roll; the only surviving behavioral difference is the manual-path cold-bust consolation, which moves to the `emitLootboxEvent` gate (D-277-CONSOLATION-GATE-01).
- **`if (emitLootboxEvent)` gate at `:1080`** — currently gates only the `LootBoxOpened` emit. After D-277-CONSOLATION-GATE-01 it also gates the cold-bust consolation. Since auto-resolve emits nothing (D-277-AR-SILENT-01), this single gate cleanly covers both manual-only behaviors.
- **`LootBoxOpened` 2nd field mislabel** — event field is `uint32 indexed index` but the emit at `:1081` passes `day`. EVT-UNI-02's restructure fixes this: a real `lootboxIndex` + a separate `day` field.
- **`JackpotTicketWin` has 3 emit sites** — `:705` + `:1008` are trait-matched (`roundedUp=false`); `:2246` is the BAF `_jackpotTicketRoll` path (real `roundedUp`). Adding `roundedUp` forces all 3 sites to supply it. `traitId` is already the 3rd indexed topic — `roundedUp` must be a non-indexed data field.

### Integration Points
- **Mutations confined to:** `DegenerusGameLootboxModule.sol` (event defs + `_resolveLootboxCommon` body + 4 callers), `DegenerusGameJackpotModule.sol` (`JackpotTicketWin` def + 3 emit sites + `_jackpotTicketRoll` `roundedUp` capture), `IDegenerusGameModules.sol` (`LootboxTicketRoll` interface deletion).
- **No new state variables, no new modifiers, no new admin/external entry points** — storage layout byte-identical at v40 phase-close HEAD vs v39 baseline `6a7455d1`. Event signature changes do not affect storage layout.
- **Cross-module byte-identity expected** for MintModule, EntropyLib, JackpotBucketLib, TraitUtils, DegenerusGameStorage helpers (no shared-helper edits).

</code_context>

<specifics>
## Specific Ideas

- **User directive (revision driver):** "make sure we aren't truncating anything" + "make this as gas efficient as we can, especially for advancegame chain components" + "1 burnie minimum resolution is 100% fine." Resolution: keep event fields wide (`uint256` wei) — no truncation, and *zero* gas cost vs. narrowing because event data words are 32 bytes regardless. The whole-token-BURNIE machinery was unnecessary. The advanceGame-chain directive specifically kills the auto-resolve `LootBoxOpened` emission (D-277-AR-SILENT-01).
- **EVT-UNI-02 / -03 / -06 are OVERRIDDEN** — EVT-UNI-02's `uint32 burnie` / `uint16 bonus`, EVT-UNI-03's `preRollTickets`, and EVT-UNI-06's emit-decision are all corrected by this revision. ROADMAP.md + REQUIREMENTS.md text needs the corresponding correction (deferred docs-only follow-up — see Deferred Ideas).
- **advanceGame-chain trace** — `resolveLootboxDirect` is reachable from `processCoinflipPayouts` (runs in advanceGame) via the Degenerette coinflip-payout 3-tier split. This is the concrete reason auto-resolve must not emit a heavy `LootBoxOpened` LOG.

</specifics>

<deferred>
## Deferred Ideas

- **`_queueLootboxTickets` wrapper retirement + `xTICKET_SCALE` cleanup + ENT-05 BAF xorshift refactor + cross-surface regression (TST-CROSS-01)** — Phase 278 JPT-CLEAN.
- **Whole-BURNIE floor at lootbox spin + near/far-future coin jackpot** — Phase 279 BUR.
- **ROADMAP/REQUIREMENTS text correction (now larger than originally scoped)** — three EVT-UNI requirement texts are overridden by this revision and should be corrected: EVT-UNI-02 (`uint32 burnie` / `uint16 bonus` → stays `uint256` wide; no whole-token semantics), EVT-UNI-03 (`preRollTickets` → not added, redundant; only `roundedUp`), EVT-UNI-06 (auto-resolve → stays silent, no `LootBoxOpened`). Flagged to user at context-close; a docs-only follow-up, not part of the contract/test waves.
- **Whole-token event semantics for any BURNIE field** — explicitly considered and REJECTED this phase. It saves zero gas (event fields have no slots), introduces truncation/overflow risk, breaks indexer value semantics, and adds `/ 1 ether` divisions. Not revisited unless a future indexer-ergonomics requirement justifies the tradeoff.

### Reviewed Todos (not folded)
None — `todo.match-phase` returned zero matches for Phase 277.

</deferred>

---

*Phase: 277-Event Surface Unification + Sentinel Retirement (EVT-UNI)*
*Context gathered: 2026-05-14 — revised 2026-05-14*
