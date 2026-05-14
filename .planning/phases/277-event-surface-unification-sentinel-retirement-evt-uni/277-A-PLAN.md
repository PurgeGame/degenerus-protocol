---
phase: 277-event-surface-unification-sentinel-retirement-evt-uni
plan: A
type: execute
wave: 1
depends_on: []
files_modified:
  - contracts/modules/DegenerusGameLootboxModule.sol
  - contracts/modules/DegenerusGameJackpotModule.sol
  - contracts/interfaces/IDegenerusGameModules.sol
autonomous: false
requirements:
  - EVT-UNI-01
  - EVT-UNI-02
  - EVT-UNI-03
  - EVT-UNI-04
  - EVT-UNI-05
  - EVT-UNI-06
  - EVT-UNI-07
  - EVT-UNI-08
user_setup: []

must_haves:
  truths:
    - "The `LootboxTicketRoll` event is DELETED from BOTH `contracts/modules/DegenerusGameLootboxModule.sol` (def + NatSpec block at `:134-159`) AND `contracts/interfaces/IDegenerusGameModules.sol` (def + NatSpec at `:267-281` inside the `IDegenerusGameLootboxModule` block) — `grep -rn 'LootboxTicketRoll' contracts/` returns zero hits (EVT-UNI-01)."
    - "`LootBoxOpened` is restructured to `event LootBoxOpened(address indexed player, uint48 indexed lootboxIndex, uint48 day, uint128 amount, uint24 futureLevel, uint32 preRollTickets, bool roundedUp, uint32 burnie, uint32 bonus)` — the old fused `uint32 indexed index` (which emitted `day`) splits into a real indexed `uint48 lootboxIndex` + a non-indexed `uint48 day`; `(uint32 preRollTickets, bool roundedUp)` added with v39 `LootboxTicketRoll` semantics; `amount` narrowed to `uint128` wei; `burnie`/`bonus` are `uint32` WHOLE-token counts (EVT-UNI-02, D-277-EVT-WHOLE-BURNIE-01, D-277-BONUS-WIDTH-01)."
    - "`LootBoxOpened.burnie` emits `burnieAmount / 1 ether` and `LootBoxOpened.bonus` emits `bonusBurnie / 1 ether` — WHOLE-token counts, not raw wei (D-277-EVT-WHOLE-BURNIE-01). `coinflip.creditFlip(player, burnieAmount)` is UNTOUCHED — still receives the full-precision wei `burnieAmount` (payout path unchanged; only the log field is floored)."
    - "`LootBoxOpened.bonus` typed `uint32` (NOT `uint16` from the literal EVT-UNI-02 text) — D-277-BONUS-WIDTH-01. The worst-case `bonus` whole-token bound is derived per `feedback_gas_worst_case.md` and `uint32` (~4.29e9) headroom is confirmed in the contract commit message; escalate to the user if the theoretical max exceeds `uint32`."
    - "`BurnieLootOpen` gains `(uint32 preRollTickets, bool roundedUp)` appended; its existing fields (`burnieAmount`, `burnieReward`) stay wei `uint256` UNCHANGED — deliberate asymmetry with `LootBoxOpened` scoped by EVT-UNI-03 (EVT-UNI-03)."
    - "`JackpotTicketWin` (`contracts/modules/DegenerusGameJackpotModule.sol:80-95`) gains a `bool roundedUp` field; all 3 emit sites supply it — `:705` and `:1008` (trait-matched paths) pass `roundedUp = false`; `_jackpotTicketRoll` (emit at `:2246`) captures the real Bernoulli outcome by declaring `bool roundedUp = false` above the `:2235` predicate and setting `roundedUp = true` inside the `unchecked` block alongside `whole += 1` (EVT-UNI-04)."
    - "The `index != type(uint48).max` sentinel branch in `_resolveLootboxCommon` (`:1044`) is RETIRED — both arms collapse to a single unified path: `if (whole != 0) { _queueTickets(...); }` queues whole tickets on every caller; the manual-path WWXRP cold-bust consolation is re-gated on the EXISTING `bool emitLootboxEvent` parameter (`else if (emitLootboxEvent) { wwxrp.mintPrize(...); emit LootBoxWwxrpReward(...); }`) — NO new parameter added (EVT-UNI-05, D-277-CONSOLATION-GATE-01). `grep -n 'type(uint48).max' contracts/modules/DegenerusGameLootboxModule.sol` returns zero hits."
    - "`scaledPre` and `roundedUp` are hoisted from the `if (futureTickets != 0)` block to `_resolveLootboxCommon` function scope (default `0` / `false`) so the post-block `LootBoxOpened` emit and the return tuple can read them — this is a new hoist beyond Phase 275's."
    - "Auto-resolve callers `resolveLootboxDirect` (`:704`) and `resolveRedemptionLootbox` (`:739`) pass `lootboxIndex = 0` (NOT `type(uint48).max`) as arg 3 to `_resolveLootboxCommon`, and KEEP arg 11 `emitLootboxEvent = false` (D-277-AR-INDEX-01, D-277-CONSOLATION-GATE-01)."
    - "Auto-resolve callers EMIT `LootBoxOpened` — wired INDEPENDENTLY of the `emitLootboxEvent` consolation gate (NOT by flipping arg 11 to `true`). Implemented by extending the `_resolveLootboxCommon` return tuple to `(uint32 futureTickets, uint256 burnieAmount, uint256 bonusBurnie, uint32 preRollTickets, bool roundedUp)` and emitting `LootBoxOpened` caller-side in `resolveLootboxDirect` + `resolveRedemptionLootbox` from that tuple. Auto-resolve cold-bust still mints NO WWXRP consolation and emits NO `LootBoxWwxrpReward` (D-277-AR-EMIT-01, D-40N-SILENT-01)."
    - "Storage layout byte-identical at phase-close HEAD vs v39 baseline `6a7455d1` for `DegenerusGameLootboxModule.sol` AND `DegenerusGameJackpotModule.sol` — event signature changes and the return-tuple extension do not touch storage layout; zero new state variables, zero new modifiers, zero new external/admin entry points (EVT-UNI / storage invariant)."
    - "NatSpec on `LootBoxOpened` / `BurnieLootOpen` / `JackpotTicketWin` / `_resolveLootboxCommon` rewritten to describe what IS (whole-token vs wei units; `index` parameter is now event-identifier-only with the dual-purpose-sentinel language removed; `emitLootboxEvent` dual role as 'manual, player-initiated open' gating both `LootBoxOpened` emit AND cold-bust consolation) per `feedback_no_history_in_comments.md`. No leftover unreachable branch per `feedback_no_dead_guards.md`."
    - "Worst-case gas + bytecode delta derived theoretically FIRST then benchmarked per `feedback_gas_worst_case.md` — manual `openLootBox` path (`LootboxTicketRoll` LOG3 removal vs larger `LootBoxOpened` payload) + the new `LootBoxOpened` LOGn on the high-volume decimator-claim auto-resolve path; reported in the contract commit message; expected NET-NEGATIVE overall (EVT-UNI-07)."
  artifacts:
    - path: "contracts/modules/DegenerusGameLootboxModule.sol"
      provides: "LootboxTicketRoll deletion + LootBoxOpened restructure + BurnieLootOpen 2-field add + sentinel retirement in _resolveLootboxCommon + return-tuple extension + 4-caller updates + NatSpec rewrites"
      contains: "uint48 indexed lootboxIndex"
    - path: "contracts/modules/DegenerusGameJackpotModule.sol"
      provides: "JackpotTicketWin roundedUp field add + 3 emit-site updates + _jackpotTicketRoll roundedUp capture + NatSpec rewrite"
      contains: "bool roundedUp"
    - path: "contracts/interfaces/IDegenerusGameModules.sol"
      provides: "LootboxTicketRoll event deletion from the IDegenerusGameLootboxModule interface block"
      contains: "interface IDegenerusGameLootboxModule"
    - path: ".planning/phases/277-event-surface-unification-sentinel-retirement-evt-uni/277-A-GAS-WORSTCASE.md"
      provides: "Theoretical worst-case derivation + empirical bench + bytecode delta + uint32 bonus-bound headroom proof + commit-message-ready summary per feedback_gas_worst_case.md"
    - path: ".planning/phases/277-event-surface-unification-sentinel-retirement-evt-uni/277-A-STORAGE-LAYOUT-DIFF.md"
      provides: "Storage-slot byte-identity proof vs 6a7455d1 baseline for DegenerusGameLootboxModule.sol + DegenerusGameJackpotModule.sol"
  key_links:
    - from: "contracts/modules/DegenerusGameLootboxModule.sol _resolveLootboxCommon (post-retirement unified path)"
      to: "_queueTickets(player, targetLevel, whole, false)"
      via: "single unconditional whole-ticket queue call replacing both sentinel arms"
      pattern: "_queueTickets\\(player, targetLevel, whole, false\\)"
    - from: "resolveLootboxDirect + resolveRedemptionLootbox"
      to: "emit LootBoxOpened(...) caller-side"
      via: "_resolveLootboxCommon extended return tuple (futureTickets, burnieAmount, bonusBurnie, preRollTickets, roundedUp); arg 11 emitLootboxEvent stays false so no consolation"
      pattern: "emit LootBoxOpened\\("
    - from: "_resolveLootboxCommon cold-bust arm"
      to: "wwxrp.mintPrize + emit LootBoxWwxrpReward"
      via: "else if (emitLootboxEvent) gate — D-277-CONSOLATION-GATE-01; manual callers pass true, auto-resolve callers pass false"
      pattern: "else if \\(emitLootboxEvent\\)"
    - from: "_jackpotTicketRoll Bernoulli predicate at DegenerusGameJackpotModule.sol:2235"
      to: "JackpotTicketWin emit at :2246"
      via: "bool roundedUp declared above the predicate, set true inside the unchecked block, threaded to the emit"
      pattern: "emit JackpotTicketWin\\("
---

<objective>
Unify the v40.0 ticket-award event surface and retire the `_resolveLootboxCommon` `index != type(uint48).max` behavior-gating sentinel. All source mutations for Phase 277 (EVT-UNI-01..08) land here in a single USER-APPROVED batched contract commit.

Concretely, across `contracts/modules/DegenerusGameLootboxModule.sol`, `contracts/modules/DegenerusGameJackpotModule.sol`, and `contracts/interfaces/IDegenerusGameModules.sol`:
1. DELETE the v39.0-additive `LootboxTicketRoll` event from the LootboxModule contract event block AND the `IDegenerusGameLootboxModule` interface block (EVT-UNI-01).
2. Restructure `LootBoxOpened` — split the fused `index`/`day` field into a real indexed `uint48 lootboxIndex` + non-indexed `uint48 day`, add `(uint32 preRollTickets, bool roundedUp)`, narrow `amount` to `uint128` wei, and emit `burnie`/`bonus` as `uint32` WHOLE-token counts (`/ 1 ether`) per D-277-EVT-WHOLE-BURNIE-01 + D-277-BONUS-WIDTH-01 (EVT-UNI-02).
3. Append `(uint32 preRollTickets, bool roundedUp)` to `BurnieLootOpen`; leave its existing wei `uint256` fields untouched (EVT-UNI-03).
4. Add `bool roundedUp` to `JackpotTicketWin`; capture the real Bernoulli outcome in `_jackpotTicketRoll` and thread `false` through the 2 trait-matched emit sites (EVT-UNI-04).
5. Retire the sentinel branch in `_resolveLootboxCommon` — collapse both arms to a unified `_queueTickets(whole)` path and re-gate the manual-path WWXRP cold-bust consolation on the EXISTING `bool emitLootboxEvent` parameter (no new parameter) per D-277-CONSOLATION-GATE-01 (EVT-UNI-05).
6. Add `LootBoxOpened` emission to both auto-resolve callers, wired INDEPENDENTLY of `emitLootboxEvent` (via an extended `_resolveLootboxCommon` return tuple + caller-side emit) so auto-resolve cold-bust stays silent per D-40N-SILENT-01; auto-resolve callers pass `lootboxIndex = 0` per D-277-AR-INDEX-01 (EVT-UNI-06, D-277-AR-EMIT-01).

Breaking event topic-hashes are accepted per D-40N-EVT-BREAK-01 (EVT-UNI-08). NatSpec/comments are rewritten to describe current behavior per `feedback_no_history_in_comments.md`; no unreachable branch is left behind per `feedback_no_dead_guards.md`.

Purpose: Consolidate the surfaces Phases 274/275/276 built — one event shape across all four ticket-award entry points, and a single unified resolution path now that manual + auto-resolve both Bernoulli-roll and queue whole tickets.

Output: Single USER-APPROVED batched contract commit `feat(277): event surface unification + sentinel retirement [EVT-UNI-01..08]` covering ALL contract edits in this phase. Bytecode delta + per-op gas delta reported in the commit message body. The executor presents the full batched diff and WAITS for explicit user approval before committing — contract changes are NEVER pre-approved.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/REQUIREMENTS.md
@.planning/phases/277-event-surface-unification-sentinel-retirement-evt-uni/277-CONTEXT.md
@.planning/phases/277-event-surface-unification-sentinel-retirement-evt-uni/277-PATTERNS.md
@.planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-CONTEXT.md
@.planning/phases/276-jackpotmodule-2216-baf-bernoulli-jpt-br/276-CONTEXT.md

# User-memory feedback files (project discipline)
@/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_no_contract_commits.md
@/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_batch_contract_approval.md
@/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_never_preapprove_contracts.md
@/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_manual_review_before_push.md
@/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_no_dead_guards.md
@/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_no_history_in_comments.md
@/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_gas_worst_case.md
@/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_design_intent_before_deletion.md

# Contract source (audit subject)
@contracts/modules/DegenerusGameLootboxModule.sol
@contracts/modules/DegenerusGameJackpotModule.sol
@contracts/interfaces/IDegenerusGameModules.sol

<interfaces>
<!-- Exact identifiers the executor needs. Current state of the mutation sites. -->

LootBoxOpened — CURRENT def (DegenerusGameLootboxModule.sol:66-74), 2nd field NAMED `index` but the emit at :1081 passes `day`:
  event LootBoxOpened(address indexed player, uint32 indexed index, uint256 amount, uint24 futureLevel, uint32 futureTickets, uint256 burnie, uint256 bonusBurnie)

LootBoxOpened — TARGET def (field order is planner discretion; this is the canonical shape; indexed topics first):
  event LootBoxOpened(address indexed player, uint48 indexed lootboxIndex, uint48 day, uint128 amount, uint24 futureLevel, uint32 preRollTickets, bool roundedUp, uint32 burnie, uint32 bonus)

BurnieLootOpen — CURRENT def (DegenerusGameLootboxModule.sol:83-90); TARGET appends `(uint32 preRollTickets, bool roundedUp)`, existing fields UNCHANGED:
  event BurnieLootOpen(address indexed player, uint32 indexed index, uint256 burnieAmount, uint24 ticketLevel, uint32 tickets, uint256 burnieReward)

LootboxTicketRoll — DELETION TARGET, two mirror copies:
  - DegenerusGameLootboxModule.sol:134-159 (NatSpec block + event def)
  - IDegenerusGameModules.sol:267-281 (NatSpec + event def, inside `interface IDegenerusGameLootboxModule` at :264)

_resolveLootboxCommon — CURRENT signature (DegenerusGameLootboxModule.sol:908-934); 14 args, returns 3:
  function _resolveLootboxCommon(address player, uint32 day, uint48 index, uint256 amount, uint24 targetLevel, uint24 currentLevel, uint256 seed, bool presale, bool allowWhalePass, bool allowLazyPass, bool emitLootboxEvent, bool allowBoons, uint256 distressEth, uint256 totalPackedEth) private returns (uint32 futureTickets, uint256 burnieAmount, uint256 bonusBurnie)
  TARGET return tuple extends to: (uint32 futureTickets, uint256 burnieAmount, uint256 bonusBurnie, uint32 preRollTickets, bool roundedUp)

_resolveLootboxCommon — CURRENT sentinel block (DegenerusGameLootboxModule.sol:1020-1067): the `if (futureTickets != 0)` block computes hoisted Bernoulli locals `scaledPre`/`whole`/`frac`/`roundedUp` at :1037-1043 (Phase 275 D-275-HOIST-01), then branches `if (index != type(uint48).max)` at :1044 — manual arm: `_queueTickets(whole)` else `wwxrp.mintPrize` + `emit LootBoxWwxrpReward`, then `emit LootboxTicketRoll`; auto-resolve else-arm: `_queueTickets(whole)`.

_resolveLootboxCommon — CURRENT LootBoxOpened emit (DegenerusGameLootboxModule.sol:1080-1090), gated by `if (emitLootboxEvent)`, currently passes `day` as the 2nd arg.

coinflip.creditFlip(player, burnieAmount) at DegenerusGameLootboxModule.sol:1081 — UNTOUCHED; receives full-precision wei. Only the LootBoxOpened.burnie/.bonus LOG fields are floored to whole tokens.

Auto-resolve callers — resolveLootboxDirect (:704-729) and resolveRedemptionLootbox (:739-766): both pass `type(uint48).max` as arg 3 (`index`) and `false` as arg 11 (`emitLootboxEvent`). Manual callers openLootBox (call ~:616) and openBurnieLootBox (call ~:671) pass a real `index` and `true` as arg 11. openBurnieLootBox emits `BurnieLootOpen` caller-side (~:688) from the `_resolveLootboxCommon` return tuple.

JackpotTicketWin — CURRENT def (DegenerusGameJackpotModule.sol:80-95): 6 fields `(address indexed winner, uint24 indexed ticketLevel, uint16 indexed traitId, uint32 ticketCount, uint24 sourceLevel, uint256 ticketIndex)`. TARGET appends `bool roundedUp`. 3 emit sites: :705 + :1008 (trait-matched, pass `false`), :2246 (BAF `_jackpotTicketRoll`, pass real `roundedUp`).

_jackpotTicketRoll Bernoulli (DegenerusGameJackpotModule.sol:2235): `if (frac != 0 && (uint16(entropy >> 200) % uint16(TICKET_SCALE)) < uint16(frac)) { unchecked { whole += 1; } }` — currently NO `roundedUp` bool. Phase 276 left the event surface untouched per D-276-EVT-STATUSQUO-01.
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: LootboxModule event surface — delete LootboxTicketRoll, restructure LootBoxOpened, extend BurnieLootOpen (EVT-UNI-01, EVT-UNI-02, EVT-UNI-03)</name>
  <files>contracts/modules/DegenerusGameLootboxModule.sol, contracts/interfaces/IDegenerusGameModules.sol</files>
  <read_first>
    - contracts/modules/DegenerusGameLootboxModule.sol (the file being modified — focus the event block `:55-160`: `LootBoxOpened` def `:58-74`, `BurnieLootOpen` def `:76-90`, `LootboxTicketRoll` def + NatSpec `:130-159`; and the `BurnieLootOpen` caller-side emit in `openBurnieLootBox` near `:688`)
    - contracts/interfaces/IDegenerusGameModules.sol (the file being modified — `interface IDegenerusGameLootboxModule` block at `:264-289`, the mirrored `LootboxTicketRoll` def + NatSpec at `:267-281`)
    - .planning/phases/277-event-surface-unification-sentinel-retirement-evt-uni/277-CONTEXT.md (D-277-EVT-WHOLE-BURNIE-01 whole-token burnie/bonus; D-277-BONUS-WIDTH-01 uint32 bonus; the §Claude's Discretion item on final field order + the BurnieLootOpen asymmetry FLAG-to-user rule)
    - .planning/phases/277-event-surface-unification-sentinel-retirement-evt-uni/277-PATTERNS.md (the event-definition style template from `BurnieLootOpen` `:76-90`; the EVT-UNI-02 restructured `LootBoxOpened` canonical shape; the EVT-UNI-01 deletion-target excerpt; the note that the 26-line `LootboxTicketRoll` NatSpec has good `preRollTickets`/`roundedUp` derivation wording to FOLD INTO the new `LootBoxOpened` NatSpec)
    - /home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_no_history_in_comments.md (NatSpec describes what IS, never what changed)
  </read_first>
  <action>
Edit `contracts/modules/DegenerusGameLootboxModule.sol` and `contracts/interfaces/IDegenerusGameModules.sol`. Make these changes:

(1) DELETE the entire `LootboxTicketRoll` block at `DegenerusGameLootboxModule.sol:134-159` — the 26-line NatSpec block AND the `event LootboxTicketRoll(...)` def. Before deleting, SALVAGE the `preRollTickets` / `roundedUp` derivation wording (`(preRollTickets / 100) + (roundedUp ? 1 : 0)`; consolation case `whole == 0 && preRollTickets > 0`) — fold it into the restructured `LootBoxOpened` NatSpec in step (2).

(2) DELETE the mirror `LootboxTicketRoll` block at `IDegenerusGameModules.sol:267-281` (NatSpec + def) from inside the `interface IDegenerusGameLootboxModule` block. The interface does NOT declare `LootBoxOpened` / `BurnieLootOpen` — no other interface edit is needed.

(3) RESTRUCTURE `LootBoxOpened` at `DegenerusGameLootboxModule.sol:58-74` to the canonical target shape: `event LootBoxOpened(address indexed player, uint48 indexed lootboxIndex, uint48 day, uint128 amount, uint24 futureLevel, uint32 preRollTickets, bool roundedUp, uint32 burnie, uint32 bonus)`. Field order is planner discretion but indexed topics MUST come first; this canonical shape is acceptable. Key changes from the current def: the fused `uint32 indexed index` (which actually emitted `day`) splits into a real indexed `uint48 lootboxIndex` AND a non-indexed `uint48 day`; `amount` narrows `uint256 -> uint128` (wei, retains headroom); `futureTickets` is renamed `preRollTickets` (already `uint32`); `(bool roundedUp)` is added; `burnie` narrows `uint256 -> uint32` and `bonusBurnie` is renamed `bonus` and narrows `uint256 -> uint32` — both `burnie` and `bonus` now carry WHOLE-token counts per D-277-EVT-WHOLE-BURNIE-01 + D-277-BONUS-WIDTH-01. Rewrite the `@notice` + per-field `@param` NatSpec to describe what IS: explicitly state `lootboxIndex` is the per-player storage index (auto-resolve passes `0`), `day` is the day index, `amount` is wei, `preRollTickets` is the post-distress pre-Bernoulli scaled count, `roundedUp` is the Bernoulli outcome, `burnie`/`bonus` are WHOLE-token counts (`wei / 1 ether`). NO "changed from" / "previously" history phrasing.

(4) EXTEND `BurnieLootOpen` at `DegenerusGameLootboxModule.sol:83-90` — APPEND `uint32 preRollTickets, bool roundedUp` to the field list. Leave ALL existing fields UNCHANGED: `burnieAmount` and `burnieReward` STAY wei `uint256`, `index` stays `uint32 indexed`. This wei-vs-whole-token asymmetry with `LootBoxOpened` is deliberate and scoped by EVT-UNI-03. Add `@param` NatSpec lines for the 2 new fields with the same `preRollTickets`/`roundedUp` semantics as `LootBoxOpened`. (Note: the `BurnieLootOpen` caller-side emit in `openBurnieLootBox` is updated in Task 2, which threads the new return-tuple values.)

(5) Do NOT touch `JackpotTicketWin` or `_resolveLootboxCommon` in this task — those are Tasks 2 and 3.

(6) Run `npx hardhat compile --force`. This task alone will produce compile errors at the emit sites (the emit args no longer match the new event arity) — that is EXPECTED and is resolved by Tasks 2/3. Do NOT attempt to make this task compile in isolation; the phase compiles cleanly only after all 3 tasks land. Confirm the ONLY compile errors are arity/type mismatches at the known emit sites (`LootBoxOpened` emit in `_resolveLootboxCommon`, `BurnieLootOpen` emit in `openBurnieLootBox`) and the deleted-`LootboxTicketRoll` emit site — no unexpected errors elsewhere.
  </action>
  <verify>
    <automated>
# LootboxTicketRoll fully deleted from both files
grep -rn "LootboxTicketRoll" contracts/ ; test $(grep -rc "LootboxTicketRoll" contracts/ | grep -v ':0$' | wc -l) -eq 0 || (echo "FAIL: LootboxTicketRoll still present in contracts/"; exit 1)
# LootBoxOpened restructured — new indexed lootboxIndex topic present
grep -qE "uint48 indexed lootboxIndex" contracts/modules/DegenerusGameLootboxModule.sol || (echo "FAIL: LootBoxOpened missing uint48 indexed lootboxIndex"; exit 1)
# bonus is uint32 not uint16 (D-277-BONUS-WIDTH-01)
grep -vE "^\s*//|^\s*///" contracts/modules/DegenerusGameLootboxModule.sol | grep -qE "uint16 bonus" && (echo "FAIL: bonus typed uint16 — D-277-BONUS-WIDTH-01 requires uint32"; exit 1) ; echo "bonus-width OK"
# BurnieLootOpen gained the 2 fields but kept wei uint256 burnieAmount
grep -qE "uint256 burnieAmount" contracts/modules/DegenerusGameLootboxModule.sol || (echo "FAIL: BurnieLootOpen.burnieAmount must stay uint256 wei"; exit 1)
    </automated>
  </verify>
  <done>`LootboxTicketRoll` is deleted from `DegenerusGameLootboxModule.sol` and `IDegenerusGameModules.sol` (zero `grep` hits across `contracts/`). `LootBoxOpened` is restructured to the 9-field target shape with a real indexed `uint48 lootboxIndex`, split `uint48 day`, `uint128 amount`, `(uint32 preRollTickets, bool roundedUp)`, and `uint32 burnie`/`uint32 bonus` whole-token fields. `BurnieLootOpen` has `(uint32 preRollTickets, bool roundedUp)` appended with its existing wei `uint256` fields untouched. NatSpec on both events describes current behavior with no history phrasing. The only remaining compile errors are the expected emit-site arity mismatches resolved by Tasks 2/3.</done>
</task>

<task type="auto">
  <name>Task 2: Retire the _resolveLootboxCommon sentinel, re-gate consolation on emitLootboxEvent, extend return tuple, wire all 4 callers + auto-resolve LootBoxOpened emit (EVT-UNI-05, EVT-UNI-06, EVT-UNI-07, EVT-UNI-08)</name>
  <files>contracts/modules/DegenerusGameLootboxModule.sol</files>
  <read_first>
    - contracts/modules/DegenerusGameLootboxModule.sol (the file being modified — `openLootBox` `:553-632` incl. its `_resolveLootboxCommon` call ~:616; `openBurnieLootBox` `:634-696` incl. its `_resolveLootboxCommon` call ~:671 and `BurnieLootOpen` emit ~:688; `resolveLootboxDirect` `:704-729`; `resolveRedemptionLootbox` `:739-766`; `_resolveLootboxCommon` NatSpec + signature `:865-934`; the `if (futureTickets != 0)` block + sentinel branch `:1020-1067`; the `LootBoxOpened` emit + `emitLootboxEvent` gate `:1077-1091`)
    - .planning/phases/277-event-surface-unification-sentinel-retirement-evt-uni/277-CONTEXT.md (D-277-CONSOLATION-GATE-01 — consolation moves to existing `emitLootboxEvent`, NO new param, dual-role NatSpec; D-277-AR-EMIT-01 — auto-resolve emits `LootBoxOpened` but NOT via flipping `emitLootboxEvent`; D-277-AR-INDEX-01 — auto-resolve passes `lootboxIndex = 0`; the HARD WIRING CONSTRAINT)
    - .planning/phases/277-event-surface-unification-sentinel-retirement-evt-uni/277-PATTERNS.md (the EVT-UNI-05 deletion-target + post-retirement collapsed shape sketch; the function-scope hoist note for `scaledPre`/`roundedUp`; the EVT-UNI-06 / D-277-AR-EMIT-01 wiring-discretion section; the `emitLootboxEvent` discriminator pattern — arg 11 is `true` for both manual callers, `false` for both auto-resolve callers)
    - .planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-CONTEXT.md (D-275-HOIST-01 — the Bernoulli locals are already hoisted OUTSIDE the sentinel gate, pre-staging this retirement)
    - /home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_no_dead_guards.md (no leftover unreachable branch after the sentinel deletes)
    - /home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_design_intent_before_deletion.md (trace WHY the sentinel existed — v39 manual-vs-auto-resolve behavior split — before deleting; D-277-CONSOLATION-GATE-01 captures the surviving behavior)
    - /home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_no_history_in_comments.md
  </read_first>
  <action>
Edit `contracts/modules/DegenerusGameLootboxModule.sol` ONLY. Make these changes:

(1) HOIST `scaledPre` and `roundedUp` from inside the `if (futureTickets != 0)` block to `_resolveLootboxCommon` function scope. Declare `uint32 scaledPre = 0;` and `bool roundedUp = false;` near the top of the function body (alongside the existing `returns` named locals). Inside the `if (futureTickets != 0)` block, ASSIGN (do not re-declare) `scaledPre = futureTickets;` and set `roundedUp = true;` inside the `unchecked` block where `whole += 1` happens. `whole` and `frac` may stay block-scoped — only `scaledPre` and `roundedUp` need function scope (the post-block `LootBoxOpened` emit and the extended return tuple read them).

(2) RETIRE the sentinel branch. Replace the `if (index != type(uint48).max) { ... } else { ... }` structure at `:1044-1066` with a single unified path:
  - `if (whole != 0) { _queueTickets(player, targetLevel, whole, false); }`
  - `else if (emitLootboxEvent) { wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION); emit LootBoxWwxrpReward(player, day, amount, LOOTBOX_WWXRP_CONSOLATION); }`
  - The `(whole == 0 && !emitLootboxEvent)` case falls through silently — auto-resolve cold-bust is silent per D-40N-SILENT-01. Do NOT add an explicit empty `else` branch (`feedback_no_dead_guards.md`).
  - DELETE the `emit LootboxTicketRoll(...)` line entirely (EVT-UNI-01 — the event no longer exists).
  - The `index` parameter is no longer read for behavior — it is now ONLY an event-emission identifier. Do NOT remove the parameter (the signature stays; manual callers still pass a real index, auto-resolve passes `0`).

(3) EXTEND the `_resolveLootboxCommon` return tuple from `(uint32 futureTickets, uint256 burnieAmount, uint256 bonusBurnie)` to `(uint32 futureTickets, uint256 burnieAmount, uint256 bonusBurnie, uint32 preRollTickets, bool roundedUp)`. Update the `returns(...)` clause, the trailing `return (...)` statement, and the `@return` NatSpec. `preRollTickets` returns `scaledPre`; `roundedUp` returns the hoisted `roundedUp`.

(4) UPDATE the in-function `LootBoxOpened` emit at `:1080-1090` (still gated by `if (emitLootboxEvent)` for the MANUAL paths). Supply the new field set: `lootboxIndex = index` (the param), `day`, `amount`, `futureLevel = targetLevel`, `preRollTickets = scaledPre`, `roundedUp`, `burnie = burnieAmount / 1 ether`, `bonus = bonusBurnie / 1 ether`. Match the final `LootBoxOpened` field order chosen in Task 1.

(5) UPDATE the manual callers. `openLootBox` (`_resolveLootboxCommon` call ~:616) and `openBurnieLootBox` (call ~:671) KEEP arg 3 = real `index` and KEEP arg 11 `emitLootboxEvent = true`. Update their call sites to destructure the extended 5-tuple return (add the 2 new return vars or `,` -placeholders as needed). `openBurnieLootBox`'s `BurnieLootOpen` emit (~:688) must now ALSO supply `preRollTickets` + `roundedUp` from the extended return tuple (EVT-UNI-03 field wiring).

(6) UPDATE the auto-resolve callers `resolveLootboxDirect` (`:704-729`) and `resolveRedemptionLootbox` (`:739-766`):
  - Change arg 3 from `type(uint48).max` to `0` (D-277-AR-INDEX-01). After this, `grep 'type(uint48).max'` in this file returns ZERO hits.
  - KEEP arg 11 `emitLootboxEvent = false` — do NOT flip to `true` (the HARD WIRING CONSTRAINT — flipping it would enable auto-resolve cold-bust consolation, violating D-40N-SILENT-01).
  - Destructure the extended 5-tuple return: `(uint32 futureTickets, uint256 burnieAmount, uint256 bonusBurnie, uint32 preRollTickets, bool roundedUp)`.
  - ADD a caller-side `emit LootBoxOpened(...)` in BOTH functions, AFTER the `_resolveLootboxCommon` call, supplying: `lootboxIndex = 0`, `day`, `amount` (the resolved ETH amount — match what the manual emit uses), `futureLevel = targetLevel`, `preRollTickets`, `roundedUp`, `burnie = burnieAmount / 1 ether`, `bonus = bonusBurnie / 1 ether`. This emit is UNCONDITIONAL in the auto-resolve callers (D-277-AR-EMIT-01) and is wired completely independently of the `emitLootboxEvent` flag.

(7) REWRITE NatSpec. `_resolveLootboxCommon` `@param index`: drop the "dual-purpose value (a) gates the behavioral split ... and (b) flows through to LootboxTicketRoll" language — describe what IS: `index` is the per-player storage index used purely as the `LootBoxOpened.lootboxIndex` event identifier; auto-resolve callers pass `0`. `@param emitLootboxEvent`: document the dual role per D-277-CONSOLATION-GATE-01 — it means "this is a manual, player-initiated open"; it gates BOTH the in-function `LootBoxOpened` emit AND the cold-bust WWXRP consolation; manual callers pass `true`, auto-resolve callers pass `false` (auto-resolve emits `LootBoxOpened` caller-side instead and is never eligible for consolation). Rewrite the inline comment block at `:1029-1043` (the one referencing the sentinel and "Manual callers pass a real `index`; auto-resolve callers pass `type(uint48).max`") to describe the unified post-retirement path. All per `feedback_no_history_in_comments.md` — present tense, no "changed from".

(8) Run `npx hardhat compile --force`. AFTER Tasks 1 + 2 land, `DegenerusGameLootboxModule.sol` + `IDegenerusGameModules.sol` should compile clean (Task 3 covers the JackpotModule). Confirm zero errors in `DegenerusGameLootboxModule.sol` and zero new warnings relative to the v39 baseline warning set.

(9) NO edits to any file other than `contracts/modules/DegenerusGameLootboxModule.sol`. NO new state variables, NO new modifiers, NO new external/admin entry points, NO new parameter on `_resolveLootboxCommon` (the consolation gate reuses the existing `emitLootboxEvent` — D-277-CONSOLATION-GATE-01).
  </action>
  <verify>
    <automated>
# Sentinel fully retired — zero type(uint48).max occurrences in the module
grep -c "type(uint48).max" contracts/modules/DegenerusGameLootboxModule.sol | grep -qE "^0$" || (echo "FAIL: type(uint48).max still present — sentinel not fully retired / auto-resolve callers not updated to 0"; exit 1)
# Consolation re-gated on emitLootboxEvent
grep -qE "else if \(emitLootboxEvent\)" contracts/modules/DegenerusGameLootboxModule.sol || (echo "FAIL: cold-bust consolation not re-gated on emitLootboxEvent (D-277-CONSOLATION-GATE-01)"; exit 1)
# Unified whole-ticket queue path present
grep -qE "_queueTickets\(player, targetLevel, whole, false\)" contracts/modules/DegenerusGameLootboxModule.sol || (echo "FAIL: unified _queueTickets(whole) path missing"; exit 1)
# Auto-resolve callers emit LootBoxOpened — at least 2 emit sites beyond the in-function one (>= 3 total)
test $(grep -vE "^\s*//|^\s*///" contracts/modules/DegenerusGameLootboxModule.sol | grep -cE "emit LootBoxOpened\(") -ge 3 || (echo "FAIL: expected >=3 emit LootBoxOpened sites (1 in-function + 2 auto-resolve callers)"; exit 1)
# LootboxModule + interface compile clean (JackpotModule may still error until Task 3)
npx hardhat compile --force 2>&1 | tee /tmp/277-A-t2-compile.log ; grep -E "DegenerusGameLootboxModule\.sol|IDegenerusGameModules\.sol" /tmp/277-A-t2-compile.log | grep -iE "error" && (echo "FAIL: compile errors in LootboxModule/interface after Task 2"; exit 1) ; echo "lootbox+interface compile OK"
    </automated>
  </verify>
  <done>The `index != type(uint48).max` sentinel branch is deleted from `_resolveLootboxCommon`; both arms collapse to a unified `if (whole != 0) { _queueTickets(...) } else if (emitLootboxEvent) { consolation }` path. `scaledPre`/`roundedUp` are hoisted to function scope; the return tuple is extended to 5 values. The in-function `LootBoxOpened` emit supplies the new field set with whole-token `burnie`/`bonus`. Manual callers keep real `index` + `emitLootboxEvent = true`; auto-resolve callers pass `lootboxIndex = 0` + `emitLootboxEvent = false` and emit `LootBoxOpened` caller-side from the extended return tuple. `openBurnieLootBox` threads `preRollTickets`/`roundedUp` into its `BurnieLootOpen` emit. NatSpec describes the unified path with no history phrasing. `grep 'type(uint48).max'` returns zero hits; `DegenerusGameLootboxModule.sol` + `IDegenerusGameModules.sol` compile clean.</done>
</task>

<task type="auto">
  <name>Task 3: JackpotModule — add JackpotTicketWin.roundedUp, capture it in _jackpotTicketRoll, thread false through the 2 trait-matched emit sites; full-phase compile + gas + storage proofs (EVT-UNI-04, EVT-UNI-07)</name>
  <files>contracts/modules/DegenerusGameJackpotModule.sol</files>
  <read_first>
    - contracts/modules/DegenerusGameJackpotModule.sol (the file being modified — `JackpotTicketWin` event def + NatSpec `:79-95`; trait-matched emit site 1 `:705-712`; trait-matched emit site 2 `:1008-1015`; `_jackpotTicketRoll` body incl. the Bernoulli predicate at `:2235` and the `JackpotTicketWin` emit at `:2246`)
    - .planning/phases/277-event-surface-unification-sentinel-retirement-evt-uni/277-CONTEXT.md (§Claude's Discretion — `JackpotTicketWin.roundedUp` capture: declare the bool above the predicate, set it inside the `unchecked` block; trait-matched sites pass `false`)
    - .planning/phases/277-event-surface-unification-sentinel-retirement-evt-uni/277-PATTERNS.md (the EVT-UNI-04 section — exact `roundedUp` capture pattern mirroring the Phase 275 lootbox shape `DegenerusGameLootboxModule.sol:1041-1045`; the 3-emit-site discipline; the note that the `:2186-2191` bit-allocation NatSpec is UNCHANGED — no new slice consumed)
    - .planning/phases/276-jackpotmodule-2216-baf-bernoulli-jpt-br/276-CONTEXT.md (D-276-EVT-STATUSQUO-01 — Phase 276 deliberately left `JackpotTicketWin` untouched; THIS phase adds `roundedUp`)
    - /home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_no_history_in_comments.md
    - /home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_gas_worst_case.md (derive theoretical worst case FIRST, then benchmark; report bytecode + gas delta)
  </read_first>
  <action>
Edit `contracts/modules/DegenerusGameJackpotModule.sol` (steps 1-4), then run the full-phase compile + proof artifacts (steps 5-7).

(1) ADD `bool roundedUp` to the `JackpotTicketWin` event def at `:80-95`. Field order is planner discretion but keep the 3 `indexed` topics first per the in-file convention — append `bool roundedUp` after the existing non-indexed fields (`ticketCount`, `sourceLevel`, `ticketIndex`). Update the `@dev` NatSpec to document `roundedUp` per `feedback_no_history_in_comments.md` — describe what IS: trait-matched paths emit `roundedUp = false` (zero fractional part by construction); the BAF `_jackpotTicketRoll` path emits the real Bernoulli round-up outcome.

(2) CAPTURE `roundedUp` in `_jackpotTicketRoll`. At the Bernoulli predicate (`:2235`, currently `if (frac != 0 && (uint16(entropy >> 200) % uint16(TICKET_SCALE)) < uint16(frac)) { unchecked { whole += 1; } }`): declare `bool roundedUp = false;` immediately ABOVE the `if`, and set `roundedUp = true;` INSIDE the `unchecked` block alongside `whole += 1;`. This mirrors the Phase 275 lootbox-surface shape exactly. The `bits[200..215]` slice is unchanged — no new entropy slice is consumed, so the `:2186-2191` bit-allocation NatSpec needs NO change.

(3) THREAD `roundedUp` into the `_jackpotTicketRoll` `JackpotTicketWin` emit at `:2246` — add it as the new last arg, matching the field order chosen in step (1).

(4) UPDATE the 2 trait-matched emit sites — `:705-712` and `:1008-1015` — to pass `roundedUp = false` as the new last arg (trait-matched paths have a zero fractional part, so `false` is correct). Leave the existing `// ticketCount emitted scaled ×TICKET_SCALE` comments in place.

(5) Run `npx hardhat compile --force` for the FULL phase (all 3 files from Tasks 1+2+3 now landed). Confirm: zero compile errors across `DegenerusGameLootboxModule.sol`, `DegenerusGameJackpotModule.sol`, `IDegenerusGameModules.sol`, and the whole project; zero new warnings relative to the v39 baseline warning set.

(6) STORAGE-LAYOUT PROOF. Capture the storage layout for `DegenerusGameLootboxModule` and `DegenerusGameJackpotModule` at current HEAD and diff against v39 baseline `6a7455d1` (e.g. `git show 6a7455d1:contracts/modules/DegenerusGameLootboxModule.sol` compiled vs current, or the hardhat storage-layout artifact). The diff MUST be empty — event signature changes and the return-tuple extension do not touch storage layout. Write the proof to `.planning/phases/277-event-surface-unification-sentinel-retirement-evt-uni/277-A-STORAGE-LAYOUT-DIFF.md`.

(7) GAS + BYTECODE WORST-CASE. Per `feedback_gas_worst_case.md`: FIRST derive the theoretical worst case analytically — (a) manual `openLootBox` path: removed `LootboxTicketRoll` LOG3 vs the now-larger `LootBoxOpened` payload (more data words, same/changed topic count); (b) the high-volume decimator-claim auto-resolve path: the NEW `LootBoxOpened` LOGn that did not exist before. Also derive the theoretical worst-case whole-token `bonus` value (`bonusBurnie / 1 ether` where `bonusBurnie = (burniePresale * LOOTBOX_PRESALE_BURNIE_BONUS_BPS) / 10_000`, 6200 bps; trace `burnieOut = (burnieBudget * PRICE_COIN_UNIT) / targetPrice`, `PRICE_COIN_UNIT = 1000 ether`) and CONFIRM it fits in `uint32` (~4.29e9) — if the theoretical max exceeds `uint32`, STOP and escalate to the user. THEN benchmark empirically (or note the fixture-coverage gap explicitly if no fixture exists, per the LBX-02 precedent). Write the theoretical derivation + empirical/fixture-gap result + bytecode delta + a commit-message-ready summary to `.planning/phases/277-event-surface-unification-sentinel-retirement-evt-uni/277-A-GAS-WORSTCASE.md`. Expected NET-NEGATIVE overall (EVT-UNI-07).

(8) NO edits to any file other than `contracts/modules/DegenerusGameJackpotModule.sol` in steps 1-4. NO new state variables, NO new modifiers, NO new external/admin entry points, NO new events on the JackpotModule.
  </action>
  <verify>
    <automated>
# JackpotTicketWin gained roundedUp
grep -qE "bool roundedUp" contracts/modules/DegenerusGameJackpotModule.sol || (echo "FAIL: JackpotTicketWin missing bool roundedUp field / capture"; exit 1)
# roundedUp captured in _jackpotTicketRoll (declared false, set true) — expect both tokens present
grep -qE "roundedUp = true" contracts/modules/DegenerusGameJackpotModule.sol || (echo "FAIL: _jackpotTicketRoll does not set roundedUp = true inside the unchecked block"; exit 1)
# All 3 JackpotTicketWin emit sites still present
test $(grep -vE "^\s*//|^\s*///" contracts/modules/DegenerusGameJackpotModule.sol | grep -cE "emit JackpotTicketWin\(") -eq 3 || (echo "FAIL: expected exactly 3 emit JackpotTicketWin sites"; exit 1)
# Full-phase clean compile
npx hardhat compile --force 2>&1 | tee /tmp/277-A-full-compile.log ; test "${PIPESTATUS[0]}" -eq 0 || (echo "FAIL: full-phase compile failed"; exit 1)
grep -iE "^\s*Error|: Error" /tmp/277-A-full-compile.log && (echo "FAIL: compile errors present"; exit 1) ; echo "full compile OK"
# Proof artifacts written
test -f .planning/phases/277-event-surface-unification-sentinel-retirement-evt-uni/277-A-STORAGE-LAYOUT-DIFF.md || (echo "FAIL: storage-layout proof missing"; exit 1)
test -f .planning/phases/277-event-surface-unification-sentinel-retirement-evt-uni/277-A-GAS-WORSTCASE.md || (echo "FAIL: gas worst-case report missing"; exit 1)
    </automated>
  </verify>
  <done>`JackpotTicketWin` has a `bool roundedUp` field; `_jackpotTicketRoll` declares `bool roundedUp = false` above the `:2235` predicate and sets it `true` inside the `unchecked` block; the `:2246` emit threads it; the 2 trait-matched emit sites (`:705`, `:1008`) pass `false`. The full phase (all 3 files) compiles clean with zero new warnings. The storage-layout diff vs `6a7455d1` is empty and recorded in `277-A-STORAGE-LAYOUT-DIFF.md`. The gas/bytecode worst-case derivation (theoretical-first, then benchmarked), the `uint32 bonus` headroom proof, and the bytecode delta are recorded in `277-A-GAS-WORSTCASE.md` with a commit-message-ready summary.</done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 4: USER-APPROVED batched contract commit</name>
  <what-built>All Phase 277 source mutations (EVT-UNI-01..08) across `contracts/modules/DegenerusGameLootboxModule.sol`, `contracts/modules/DegenerusGameJackpotModule.sol`, and `contracts/interfaces/IDegenerusGameModules.sol`: `LootboxTicketRoll` deleted; `LootBoxOpened` restructured with whole-token `burnie`/`bonus`; `BurnieLootOpen` + `JackpotTicketWin` extended; the `_resolveLootboxCommon` sentinel retired with consolation re-gated on `emitLootboxEvent`; auto-resolve callers emitting `LootBoxOpened` independently. Full phase compiles clean; storage layout byte-identical to `6a7455d1`; gas/bytecode worst-case derived and benchmarked.</what-built>
  <how-to-verify>
    1. Review the full batched diff for all 3 contract files: `git diff contracts/modules/DegenerusGameLootboxModule.sol contracts/modules/DegenerusGameJackpotModule.sol contracts/interfaces/IDegenerusGameModules.sol`.
    2. Confirm `grep -rn "LootboxTicketRoll" contracts/` returns zero hits and `grep -n "type(uint48).max" contracts/modules/DegenerusGameLootboxModule.sol` returns zero hits.
    3. Confirm the auto-resolve callers were NOT wired by flipping `emitLootboxEvent` to `true` — the consolation must still be gated by `emitLootboxEvent` and auto-resolve must pass `false` (verify the diff shows caller-side `emit LootBoxOpened` + extended return tuple, NOT an arg-11 flip).
    4. Review `.planning/phases/277-event-surface-unification-sentinel-retirement-evt-uni/277-A-STORAGE-LAYOUT-DIFF.md` (empty diff) and `277-A-GAS-WORSTCASE.md` (NET-NEGATIVE; `uint32 bonus` headroom confirmed).
    5. If approved, the executor commits with: `feat(277): event surface unification + sentinel retirement [EVT-UNI-01..08]` — body includes the bytecode delta + per-op gas delta from `277-A-GAS-WORSTCASE.md`. Contract changes are NEVER pre-approved; the executor waits for explicit approval and does NOT push.
  </how-to-verify>
  <resume-signal>Type "approved" to commit the batched contract diff, or describe required changes.</resume-signal>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Off-chain indexer ← event log surface (`LootBoxOpened` / `BurnieLootOpen` / `JackpotTicketWin` topic hashes) | The event ABI is the contract's read interface to off-chain consumers. Changing field count/types changes the topic hash — a breaking change for any consumer keyed on the old signature. |
| Manual caller (`openLootBox` / `openBurnieLootBox`, `emitLootboxEvent = true`) vs auto-resolve caller (`resolveLootboxDirect` / `resolveRedemptionLootbox`, `emitLootboxEvent = false`) → `_resolveLootboxCommon` | The `emitLootboxEvent` flag is the trust discriminator for "player-initiated open". Post-retirement it gates both the in-function `LootBoxOpened` emit AND the cold-bust WWXRP consolation (`wwxrp.mintPrize`). A mis-wired flag crosses consolation behavior between the two caller classes. |
| `_resolveLootboxCommon` → `wwxrp.mintPrize` (WWXRP token mint) | Cold-bust consolation mints WWXRP. This is the only value-bearing side-effect gated by the retired sentinel; mis-gating it is a real economic threat (auto-resolve minting WWXRP it should not). |
| `_jackpotTicketRoll` `entropy` chain → `bits[200..215]` Bernoulli slice | Already-VRF-derived entropy; the `roundedUp` capture reads the SAME slice the Phase 276 `whole += 1` predicate already reads — no new entropy consumption. |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-277-01 | Tampering / Repudiation | Breaking event topic-hashes on `LootBoxOpened` / `BurnieLootOpen` / `JackpotTicketWin` — an on-chain consumer keyed on the old signature would silently stop matching | accept | Accepted per D-40N-EVT-BREAK-01 — pre-launch supersession of the v39 non-breaking stance; indexer rebuild is expected and there is no live indexer. Mitigation discipline: Task 1's verify + Plan B TST-EVT-UNI-01/02 assert (a) the NEW signatures are well-formed and their topic hashes are computed/asserted, and (b) zero remaining emit sites for the old `LootboxTicketRoll` signature. The threat surface is confined to off-chain consumers — confirm via grep that NO on-chain contract in `contracts/` subscribes to or hard-codes these topic hashes (event consumption is off-chain only; Solidity contracts emit but do not read their own logs). No on-chain consumer depends on the old signatures. |
| T-277-02 | Elevation of Privilege / Tampering | The sentinel retirement crossing manual-path WWXRP cold-bust consolation into the auto-resolve paths (D-40N-SILENT-01 violation) — the LOAD-BEARING correctness threat | mitigate | The consolation is re-gated on the EXISTING `bool emitLootboxEvent` parameter (D-277-CONSOLATION-GATE-01), which is already exactly 1:1 with the manual-vs-auto-resolve split: `openLootBox` / `openBurnieLootBox` pass `true`, `resolveLootboxDirect` / `resolveRedemptionLootbox` pass `false`. The HARD WIRING CONSTRAINT (CONTEXT.md): auto-resolve `LootBoxOpened` emission (D-277-AR-EMIT-01) is wired via a caller-side emit + extended return tuple, NOT by flipping `emitLootboxEvent` to `true` — so auto-resolve callers keep `emitLootboxEvent = false` and the `else if (emitLootboxEvent)` consolation arm is structurally unreachable for them. Task 2 verify greps `else if (emitLootboxEvent)` and confirms `type(uint48).max` is fully gone. Task 4 human-verify explicitly checks the diff did NOT flip arg 11. Plan B TST-EVT-UNI-05 asserts auto-resolve cold-bust mints zero WWXRP / emits zero `LootBoxWwxrpReward`. |
| T-277-03 | Tampering | `LootBoxOpened.burnie` / `.bonus` whole-token truncation (`/ 1 ether`) corrupting a payout path | mitigate | The `/ 1 ether` floor is applied ONLY at the `LootBoxOpened` emit — a LOG field. `coinflip.creditFlip(player, burnieAmount)` at `:1081` is UNTOUCHED and continues to receive the full-precision wei `burnieAmount`. The threat model explicitly states: payout paths are untouched; only the log field is floored. Task 1 + Task 2 verify steps confirm `creditFlip` is not modified. Plan B TST-EVT-UNI-04 asserts manual-path field consistency (derived whole-ticket count from `preRollTickets`/`roundedUp` matches the queued count) — the BURNIE-credit amount is out of `LootBoxOpened`'s influence by construction. |
| T-277-04 | Tampering | `uint32 bonus` / `uint32 burnie` overflow — a whale lootbox producing a whole-token `bonus` exceeding `uint32` max (~4.29e9) would silently truncate the log | mitigate | Task 3 step (7) derives the theoretical worst-case whole-token `bonus` bound per `feedback_gas_worst_case.md` (tracing `bonusBurnie = (burniePresale * 6200) / 10_000`, `burnieOut = (burnieBudget * 1000 ether) / targetPrice`) and CONFIRMS `uint32` headroom; if the theoretical max exceeds `uint32`, the executor STOPS and escalates to the user rather than shipping a truncating field. Recorded in `277-A-GAS-WORSTCASE.md`. |
| T-277-05 | Tampering | Storage-layout drift — the return-tuple extension or hoisted function-scope locals accidentally moving a storage slot | mitigate | The return-tuple extension and `scaledPre`/`roundedUp` hoist add only function-local variables and return values — no contract-level state variables added or moved, no new mappings/structs. Task 3 step (6) captures the storage layout for both modules at HEAD and diffs against v39 baseline `6a7455d1`; the diff MUST be empty. Recorded in `277-A-STORAGE-LAYOUT-DIFF.md`. |
| T-277-06 | Tampering | Dead-guard residue — an unreachable branch left behind after the sentinel deletes | mitigate | Per `feedback_no_dead_guards.md` + `feedback_design_intent_before_deletion.md`: Task 2 traces WHY the sentinel existed (the v39 manual-vs-auto-resolve behavior split) before deleting, collapses both arms to a single unified path, and adds NO explicit empty `else` for the silent `(whole == 0 && !emitLootboxEvent)` case. Task 2 verify confirms `type(uint48).max` is fully gone (zero hits) — no residual sentinel comparison. |
| T-277-07 | Tampering | Cross-module byte-identity — accidental edits to shared helpers (`DegenerusGameStorage`, `EntropyLib`, `MintModule`, other interfaces) widening the surface beyond the 3 declared files | mitigate | The plan's `files_modified` is exactly 3 files. Each task's action ends with an explicit "NO edits to any other file" constraint. Task 3 step (5) full-project compile + the storage-layout proof confirm no shared-helper drift. Plan B's structural tests additionally grep that the surface is confined. |

No high-severity residual threat. T-277-02 (the load-bearing consolation-crossover threat) is fully mitigated by reusing the already-1:1 `emitLootboxEvent` discriminator plus the explicit HARD WIRING CONSTRAINT enforced in Task 2's action, Task 2's verify grep, and Task 4's human-verify diff check. T-277-01 (breaking topic-hashes) is an accepted, documented consequence of D-40N-EVT-BREAK-01 with no on-chain consumer dependency.
</threat_model>

<verification>
- `npx hardhat compile --force` succeeds with zero errors and zero new warnings vs the v39 baseline warning set, with all 3 contract files landed.
- `grep -rn "LootboxTicketRoll" contracts/` returns zero hits (event fully deleted from contract + interface).
- `grep -n "type(uint48).max" contracts/modules/DegenerusGameLootboxModule.sol` returns zero hits (sentinel fully retired; auto-resolve callers pass `0`).
- `_resolveLootboxCommon` contains a single unified `if (whole != 0) { _queueTickets(...) } else if (emitLootboxEvent) { wwxrp.mintPrize(...); emit LootBoxWwxrpReward(...); }` path — no sentinel branch, no dead `else`.
- `LootBoxOpened` has 9 fields with a real indexed `uint48 lootboxIndex`, split `uint48 day`, `uint128 amount`, `(uint32 preRollTickets, bool roundedUp)`, `uint32 burnie`, `uint32 bonus`; `BurnieLootOpen` has `(uint32 preRollTickets, bool roundedUp)` appended with its wei `uint256` fields intact; `JackpotTicketWin` has `bool roundedUp` appended.
- `coinflip.creditFlip(player, burnieAmount)` is unmodified — payout path untouched.
- `277-A-STORAGE-LAYOUT-DIFF.md` shows an empty diff vs `6a7455d1` for both modules.
- `277-A-GAS-WORSTCASE.md` records the theoretical-first worst-case derivation, the `uint32 bonus` headroom proof, the empirical/fixture-gap result, and the bytecode delta.
- Exactly 3 `emit LootBoxOpened` sites (1 in-function manual + 2 auto-resolve caller-side) and exactly 3 `emit JackpotTicketWin` sites, all supplying the new field set.
</verification>

<success_criteria>
- All 8 EVT-UNI requirements (EVT-UNI-01..08) implemented across the 3 declared contract files.
- The `LootboxTicketRoll` event is gone from both the contract and the interface; its `(preRollTickets, roundedUp)` semantics are folded into `LootBoxOpened` + `BurnieLootOpen`, and the Bernoulli outcome is surfaced on `JackpotTicketWin.roundedUp`.
- The `index != type(uint48).max` behavior-gating sentinel is retired; manual + auto-resolve converge on one unified `_queueTickets(whole)` path; the manual-path WWXRP cold-bust consolation is re-gated on the existing `emitLootboxEvent` parameter with no new parameter added.
- Auto-resolve callers emit `LootBoxOpened` (with `lootboxIndex = 0`) wired independently of `emitLootboxEvent`; auto-resolve cold-bust remains silent (no WWXRP consolation, no `LootBoxWwxrpReward`).
- Storage layout byte-identical to v39 baseline `6a7455d1` for both modules; zero new state/modifiers/entry points/events beyond the event field additions.
- Gas + bytecode delta derived theoretically then benchmarked; expected NET-NEGATIVE; reported in the commit message.
- Single USER-APPROVED batched contract commit `feat(277): event surface unification + sentinel retirement [EVT-UNI-01..08]`; executor waited for explicit approval and did not push.
</success_criteria>

<output>
After completion, create `.planning/phases/277-event-surface-unification-sentinel-retirement-evt-uni/277-A-SUMMARY.md`
</output>
