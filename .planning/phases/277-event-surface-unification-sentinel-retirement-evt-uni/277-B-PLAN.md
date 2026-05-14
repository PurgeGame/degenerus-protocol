---
phase: 277-event-surface-unification-sentinel-retirement-evt-uni
plan: B
type: execute
wave: 2
depends_on:
  - A
files_modified:
  - test/unit/LootboxWholeTicket.test.js
  - test/unit/EventSurfaceUnification.test.js
  - test/unit/SentinelRetirement.test.js
  - test/edge/EventFieldConsistency.test.js
  - package.json
autonomous: false
requirements:
  - TST-EVT-UNI-01
  - TST-EVT-UNI-02
  - TST-EVT-UNI-03
  - TST-EVT-UNI-04
  - TST-EVT-UNI-05
  - TST-EVT-UNI-06

must_haves:
  truths:
    - "`test/unit/LootboxWholeTicket.test.js` is UPDATED — the TST-WT-03/06/07 blocks that assert `LootboxTicketRoll` exists, that `if (index != type(uint48).max)` appears, and that auto-resolve passes `type(uint48).max` are REWRITTEN to assert the post-EVT-UNI surface (sentinel gone, `LootBoxOpened` carries `preRollTickets`/`roundedUp`, auto-resolve passes `0`). The file still passes in full (Phase 275 updated it in `bb1b1abd` — same update discipline)."
    - "TST-EVT-UNI-01: topic-hash change tests — for `LootBoxOpened`, `BurnieLootOpen`, `JackpotTicketWin` the test computes the NEW canonical-signature topic hash via `hre.ethers.id(...)`, asserts the deployed contract's interface (`iface.getEvent(name).topicHash` + `.inputs` type list) matches the new shape, and asserts the OLD topic hashes have zero remaining emit sites in `contracts/`."
    - "TST-EVT-UNI-02: `LootboxTicketRoll` removal regression — source-grep asserts `LootboxTicketRoll` appears ZERO times in BOTH `contracts/modules/DegenerusGameLootboxModule.sol` AND `contracts/interfaces/IDegenerusGameModules.sol` (def + emit sites); a dynamic sweep across the lootbox open paths confirms no `LootboxTicketRoll` log is ever produced."
    - "TST-EVT-UNI-03: sentinel-retirement regression — source-grep asserts `type(uint48).max` appears ZERO times in `DegenerusGameLootboxModule.sol` (the inverse of the Phase 274 `[06f]` test which asserted `>= 2`); asserts `resolveLootboxDirect` + `resolveRedemptionLootbox` pass `0` as the `_resolveLootboxCommon` index arg; a coverage/structural trace confirms `_resolveLootboxCommon` no longer branches on `index`."
    - "TST-EVT-UNI-04: manual-path `LootBoxOpened` field-consistency — for `openLootBox` opens, derived `whole = (preRollTickets / 100) + (roundedUp ? 1 : 0)` equals the queued ticket count at the level; `preRollTickets` matches the pre-Bernoulli scaled value; `lootboxIndex` matches the `index` arg passed to `openLootBox`; the v39 consolation correlation (`whole == 0` ⇒ same-tx `LootBoxWwxrpReward`) is preserved on the manual path."
    - "TST-EVT-UNI-05: auto-resolve `LootBoxOpened` field-consistency — `resolveLootboxDirect` + `resolveRedemptionLootbox` DO emit `LootBoxOpened` with `lootboxIndex = 0` and correct `preRollTickets` + `roundedUp`; AND auto-resolve cold-bust (`whole == 0`) mints ZERO WWXRP / emits ZERO `LootBoxWwxrpReward` (D-40N-SILENT-01 — the load-bearing assertion that the sentinel retirement did NOT cross consolation into auto-resolve)."
    - "TST-EVT-UNI-06: jackpot `JackpotTicketWin.roundedUp` field-consistency — the field is present on the deployed event ABI; the BAF `_jackpotTicketRoll` path emits `roundedUp` mirroring the actual Bernoulli outcome (true when the round-up incremented `whole`, false otherwise); the 2 trait-matched emit sites emit `roundedUp = false`."
    - "Test placement follows the Phase 275/276 scheme: structural + field-consistency + silent-cold-bust regression in `test/unit/`; boundary/field-consistency in `test/edge/`. NO new top-level test dirs (`test/lootbox/`, `test/jackpot/`, `test/regression/` do NOT exist and are NOT created) — this reconciles the REQUIREMENTS.md §TST-EVT-UNI header suggestion against the on-disk reality per 277-PATTERNS.md."
    - "All test files + the `package.json` script wiring land in a single USER-APPROVED batched test commit `test(277): ...`. The test commit lands AFTER Plan A's contract commit. `test/` files require explicit USER APPROVAL per `feedback_no_contract_commits.md`."
    - "Full test run is green — the updated `LootboxWholeTicket.test.js` and the 3 new test files all pass against the Plan-A contract HEAD; no pre-existing test regresses."
  artifacts:
    - path: "test/unit/LootboxWholeTicket.test.js"
      provides: "UPDATED — TST-WT-03/06/07 blocks rewritten to the post-EVT-UNI surface (sentinel gone, LootboxTicketRoll gone, LootBoxOpened carries the new fields, auto-resolve passes 0)"
    - path: "test/unit/EventSurfaceUnification.test.js"
      provides: "TST-EVT-UNI-01 topic-hash change tests + TST-EVT-UNI-02 LootboxTicketRoll removal regression"
    - path: "test/unit/SentinelRetirement.test.js"
      provides: "TST-EVT-UNI-03 sentinel-retirement regression (type(uint48).max zero-occurrence + auto-resolve passes 0 + unified-path structural trace)"
    - path: "test/edge/EventFieldConsistency.test.js"
      provides: "TST-EVT-UNI-04 manual-path LootBoxOpened field-consistency + TST-EVT-UNI-05 auto-resolve field-consistency incl. silent-cold-bust + TST-EVT-UNI-06 JackpotTicketWin.roundedUp consistency"
    - path: "package.json"
      provides: "Test-script wiring — new test files added to the appropriate test scripts following the Phase 275/276 wiring pattern"
  key_links:
    - from: "test/unit/EventSurfaceUnification.test.js"
      to: "contracts/modules/DegenerusGameLootboxModule.sol + contracts/interfaces/IDegenerusGameModules.sol"
      via: "source-grep (LootboxTicketRoll zero-occurrence) + ethers iface.getEvent topic-hash assertion"
      pattern: "iface\\.getEvent\\(|hre\\.ethers\\.id\\("
    - from: "test/unit/SentinelRetirement.test.js"
      to: "contracts/modules/DegenerusGameLootboxModule.sol"
      via: "source-grep — type(uint48).max zero-occurrence; resolveLootboxDirect/resolveRedemptionLootbox pass 0"
      pattern: "type\\\\\\(uint48\\\\\\)\\\\.max"
    - from: "test/edge/EventFieldConsistency.test.js"
      to: "contracts/modules/DegenerusGameLootboxModule.sol (_resolveLootboxCommon) + DegenerusGameJackpotModule.sol (_jackpotTicketRoll)"
      via: "dynamic open/resolve invocations — assert LootBoxOpened / JackpotTicketWin log fields + assert auto-resolve cold-bust emits no LootBoxWwxrpReward"
      pattern: "emit LootBoxOpened|LootBoxWwxrpReward"
    - from: "test/unit/LootboxWholeTicket.test.js (updated TST-WT-06/07/03)"
      to: "contracts/modules/DegenerusGameLootboxModule.sol post-Plan-A"
      via: "rewritten structural assertions targeting the post-EVT-UNI surface"
      pattern: "LootBoxOpened|preRollTickets|roundedUp"
---

<objective>
Add test coverage for Phase 277's event-surface unification + sentinel retirement (TST-EVT-UNI-01..06) and UPDATE the existing `test/unit/LootboxWholeTicket.test.js` whose TST-WT-03/06/07 blocks break when EVT-UNI-01 deletes `LootboxTicketRoll` and EVT-UNI-05 retires the sentinel.

Concretely:
1. UPDATE `test/unit/LootboxWholeTicket.test.js` — rewrite the TST-WT-03 (sentinel structural assertion), TST-WT-06, and TST-WT-07 (`LootboxTicketRoll` existence + field-consistency) blocks to assert the post-EVT-UNI surface. Same update discipline Phase 275 applied in `bb1b1abd`.
2. NEW `test/unit/EventSurfaceUnification.test.js` — TST-EVT-UNI-01 (topic-hash change tests for `LootBoxOpened` / `BurnieLootOpen` / `JackpotTicketWin`) + TST-EVT-UNI-02 (`LootboxTicketRoll` removal regression).
3. NEW `test/unit/SentinelRetirement.test.js` — TST-EVT-UNI-03 (`type(uint48).max` zero-occurrence + auto-resolve passes `0` + unified-path structural trace).
4. NEW `test/edge/EventFieldConsistency.test.js` — TST-EVT-UNI-04 (manual-path `LootBoxOpened` field-consistency) + TST-EVT-UNI-05 (auto-resolve `LootBoxOpened` field-consistency including the load-bearing silent-cold-bust assertion) + TST-EVT-UNI-06 (`JackpotTicketWin.roundedUp` consistency).
5. Wire the new test files into `package.json` test scripts following the Phase 275/276 pattern.

This is a mechanical event-surface test wave — every pattern has a Phase 274/275 analog (`LootboxWholeTicket.test.js` structural-grep idiom, `LootboxAutoResolveSilentColdBust.test.js` emit-absence posture, `LootboxAutoResolveRemByte.test.js` `fs`/`path`/`execSync` source-grep). No new top-level test dirs are created — `test/unit/` + `test/edge/` per the Phase 275/276 placement scheme.

Purpose: Empirical + structural confirmation that Plan A deleted `LootboxTicketRoll` cleanly, retired the sentinel without crossing consolation behavior into auto-resolve (D-40N-SILENT-01), and that the new event field set is internally consistent across all four ticket-award entry points.

Output: Single USER-APPROVED batched test commit `test(277): event topic-hash changes + LootboxTicketRoll removal + sentinel retirement + field consistency [TST-EVT-UNI-01..06]`. 1 updated test file + 3 new test files + a minor `package.json` edit. The executor presents the full batched diff and WAITS for explicit user approval before committing; does NOT push.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/REQUIREMENTS.md
@.planning/phases/277-event-surface-unification-sentinel-retirement-evt-uni/277-CONTEXT.md
@.planning/phases/277-event-surface-unification-sentinel-retirement-evt-uni/277-PATTERNS.md
@.planning/phases/277-event-surface-unification-sentinel-retirement-evt-uni/277-A-PLAN.md
@.planning/phases/277-event-surface-unification-sentinel-retirement-evt-uni/277-A-SUMMARY.md

# User-memory feedback files (project discipline)
@/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_no_contract_commits.md
@/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_batch_contract_approval.md
@/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_never_preapprove_contracts.md
@/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_manual_review_before_push.md

# Contract source (post-Plan-A — the test subject)
@contracts/modules/DegenerusGameLootboxModule.sol
@contracts/modules/DegenerusGameJackpotModule.sol
@contracts/interfaces/IDegenerusGameModules.sol

# Test analogs to MIRROR — structural-grep idiom, emit-absence posture, fs/path/execSync source-grep
@test/unit/LootboxWholeTicket.test.js
@test/unit/LootboxAutoResolveSilentColdBust.test.js
@test/unit/LootboxAutoResolveRemByte.test.js
</context>

<tasks>

<task type="auto">
  <name>Task 1: Update LootboxWholeTicket.test.js + add EventSurfaceUnification.test.js + SentinelRetirement.test.js (TST-EVT-UNI-01, TST-EVT-UNI-02, TST-EVT-UNI-03)</name>
  <files>test/unit/LootboxWholeTicket.test.js, test/unit/EventSurfaceUnification.test.js, test/unit/SentinelRetirement.test.js</files>
  <read_first>
    - test/unit/LootboxWholeTicket.test.js (the file being updated — full 740 lines; focus the TST-WT-03 block `:367-407` `[03-static]` which asserts `if (index != type(uint48).max)` appears after the Bernoulli slice, the TST-WT-06 block `:590-680` `[06a]`/`[06b]`/`[06d]`/`[06e]`/`[06f]` asserting `LootboxTicketRoll` exists on contract + interface and auto-resolve passes `type(uint48).max`, and the TST-WT-07 block `:682-739` `[07a]`/`[07b]`/`[07c]` `LootboxTicketRoll` field-consistency + emit ordering; also the structural-grep idiom at `:45-54` + `:125-175`)
    - test/unit/LootboxAutoResolveRemByte.test.js (the `fs`/`path`/`execSync` import block + `git show <baseline>:<path> | grep -c` baseline-diff source-grep idiom — mirror for the zero-occurrence assertions)
    - contracts/modules/DegenerusGameLootboxModule.sol (post-Plan-A — the restructured `LootBoxOpened` def, the deleted `LootboxTicketRoll`, the retired sentinel in `_resolveLootboxCommon`, the auto-resolve callers passing `0`)
    - contracts/interfaces/IDegenerusGameModules.sol (post-Plan-A — `IDegenerusGameLootboxModule` block with `LootboxTicketRoll` deleted)
    - contracts/modules/DegenerusGameJackpotModule.sol (post-Plan-A — `JackpotTicketWin` def with `bool roundedUp`)
    - .planning/phases/277-event-surface-unification-sentinel-retirement-evt-uni/277-PATTERNS.md (the §"New TST-EVT-UNI-01..06 tests" section — topic-hash assertion pattern via `hre.ethers.id(...)` + `iface.getEvent(...).topicHash`; emit-absence pattern; sentinel-retirement structural-proof pattern `type(uint48).max` zero-occurrence; the §"test placement" callout — no new top-level dirs)
    - .planning/phases/277-event-surface-unification-sentinel-retirement-evt-uni/277-A-SUMMARY.md (the final `LootBoxOpened` field order chosen by Plan A — the topic-hash assertion MUST use the actual shipped signature)
  </read_first>
  <action>
Create/update 3 test files. Use the Phase 274/275 structural-grep + topic-hash idioms.

(1) UPDATE `test/unit/LootboxWholeTicket.test.js`:
  - TST-WT-03 `[03-static]` (`:367-407`): the assertion that `if (index != type(uint48).max)` appears AFTER the Bernoulli slice is now FALSE — the sentinel is retired. Rewrite it to assert the post-retirement structural shape: `type(uint48).max` does NOT appear in `_resolveLootboxCommon`; the unified `if (whole != 0) { _queueTickets(...) } else if (emitLootboxEvent) { ... }` path is present.
  - TST-WT-06 `[06a]`/`[06b]`/`[06d]`/`[06e]` (`:590-680`): these assert `emit LootboxTicketRoll(...)` exists on the contract AND the interface. Rewrite to assert `LootboxTicketRoll` is GONE (zero occurrences in both files) and that `LootBoxOpened` now carries `preRollTickets` + `roundedUp` fields.
  - TST-WT-06 `[06f]`: asserts auto-resolve passes `type(uint48).max`. Rewrite to assert auto-resolve callers pass `0` (the `_resolveLootboxCommon` index arg in `resolveLootboxDirect` + `resolveRedemptionLootbox`).
  - TST-WT-07 `[07a]`/`[07b]`/`[07c]` (`:682-739`): `LootboxTicketRoll` field-consistency + emit-ordering vs the sentinel. Rewrite to assert the equivalent invariants on the new surface — `LootBoxOpened.preRollTickets` / `.roundedUp` field-consistency, and that the consolation emit is gated by `emitLootboxEvent` (not the retired sentinel).
  - Leave TST-WT-01/02/04/05 (and any other passing blocks) UNTOUCHED unless they reference the deleted/retired surface. Run the file and confirm it passes in full.

(2) CREATE `test/unit/EventSurfaceUnification.test.js`:
  - TST-EVT-UNI-01 — topic-hash change tests. For each of `LootBoxOpened`, `BurnieLootOpen`, `JackpotTicketWin`: load the deployed contract's interface via `hre.ethers.getContractFactory(...)`/`.interface`; assert `iface.getEvent(name).inputs.map(i => i.type)` deep-equals the new field type list (use the ACTUAL shipped signature from `277-A-SUMMARY.md`); assert `iface.getEvent(name).topicHash` equals `hre.ethers.id("<new canonical signature>")`; assert the OLD topic hash (the v39 signature) has zero remaining emit sites by source-grep over `contracts/`.
  - TST-EVT-UNI-02 — `LootboxTicketRoll` removal regression. Source-grep (`fs.readFileSync` + regex) asserts `LootboxTicketRoll` appears ZERO times in BOTH `contracts/modules/DegenerusGameLootboxModule.sol` AND `contracts/interfaces/IDegenerusGameModules.sol`. Add a dynamic sweep: open lootboxes via the available manual + auto-resolve paths and assert no `LootboxTicketRoll` log topic appears in any receipt (the event no longer exists on any ABI, so a topic-presence check suffices).

(3) CREATE `test/unit/SentinelRetirement.test.js`:
  - TST-EVT-UNI-03 — sentinel-retirement regression. Source-grep asserts `type(uint48).max` appears ZERO times in `contracts/modules/DegenerusGameLootboxModule.sol` (inverse of the Phase 274 `[06f]` test which asserted `>= 2`). Source-grep asserts `resolveLootboxDirect` + `resolveRedemptionLootbox` pass `0` as the `_resolveLootboxCommon` index arg (3rd positional arg). Add a structural assertion that `_resolveLootboxCommon`'s `if (futureTickets != 0)` block contains the unified `if (whole != 0)` / `else if (emitLootboxEvent)` shape and NO `if (index` comparison.

(4) Test placement: all 3 files in `test/unit/` per the Phase 275/276 scheme. Do NOT create `test/lootbox/`, `test/jackpot/`, or `test/regression/` (they do not exist on disk; REQUIREMENTS.md §TST-EVT-UNI's header suggestion is reconciled to the on-disk reality per 277-PATTERNS.md).

(5) Run `npx hardhat test test/unit/LootboxWholeTicket.test.js test/unit/EventSurfaceUnification.test.js test/unit/SentinelRetirement.test.js` — all pass.
  </action>
  <verify>
    <automated>
# The 3 unit test files run green
npx hardhat test test/unit/LootboxWholeTicket.test.js test/unit/EventSurfaceUnification.test.js test/unit/SentinelRetirement.test.js 2>&1 | tee /tmp/277-B-t1.log
test "${PIPESTATUS[0]}" -eq 0 || (echo "FAIL: unit tests did not pass"; exit 1)
grep -qE "passing" /tmp/277-B-t1.log || (echo "FAIL: no passing tests reported"; exit 1)
grep -qE "[1-9][0-9]* failing" /tmp/277-B-t1.log && (echo "FAIL: failing tests present"; exit 1) ; echo "no failures"
# New files exist
test -f test/unit/EventSurfaceUnification.test.js || (echo "FAIL: EventSurfaceUnification.test.js missing"; exit 1)
test -f test/unit/SentinelRetirement.test.js || (echo "FAIL: SentinelRetirement.test.js missing"; exit 1)
# The tests actually grep the retired/deleted surfaces
grep -q "LootboxTicketRoll" test/unit/EventSurfaceUnification.test.js || (echo "FAIL: EventSurfaceUnification.test.js does not reference LootboxTicketRoll removal"; exit 1)
grep -qE "uint48.*max|topicHash|getEvent" test/unit/EventSurfaceUnification.test.js || (echo "FAIL: EventSurfaceUnification.test.js missing topic-hash assertions"; exit 1)
    </automated>
  </verify>
  <done>`test/unit/LootboxWholeTicket.test.js` is updated — TST-WT-03/06/07 rewritten to the post-EVT-UNI surface — and passes in full. `test/unit/EventSurfaceUnification.test.js` covers TST-EVT-UNI-01 (topic-hash change for all 3 events) + TST-EVT-UNI-02 (`LootboxTicketRoll` zero-occurrence in contract + interface). `test/unit/SentinelRetirement.test.js` covers TST-EVT-UNI-03 (`type(uint48).max` zero-occurrence + auto-resolve passes `0` + unified-path structural trace). All 3 files run green; no new top-level test dirs created.</done>
</task>

<task type="auto">
  <name>Task 2: Add EventFieldConsistency.test.js (manual + auto-resolve + jackpot field consistency, incl. silent-cold-bust) + package.json wiring (TST-EVT-UNI-04, TST-EVT-UNI-05, TST-EVT-UNI-06)</name>
  <files>test/edge/EventFieldConsistency.test.js, package.json</files>
  <read_first>
    - test/unit/LootboxAutoResolveSilentColdBust.test.js (the emit-absence / silent-cold-bust posture — mirror for the TST-EVT-UNI-05 auto-resolve cold-bust assertion: zero `LootBoxWwxrpReward`, zero `wwxrp.mintPrize`, `wwxrp.balanceOf` unchanged)
    - test/unit/LootboxWholeTicket.test.js (the dynamic open-lootbox + receipt-log-parsing idiom + the manual-path consolation-correlation invariant from the Phase 274 TST-WT blocks)
    - contracts/modules/DegenerusGameLootboxModule.sol (post-Plan-A — `openLootBox`, `openBurnieLootBox`, `resolveLootboxDirect`, `resolveRedemptionLootbox`, the restructured `LootBoxOpened` emit, the `emitLootboxEvent`-gated consolation)
    - contracts/modules/DegenerusGameJackpotModule.sol (post-Plan-A — `JackpotTicketWin` with `bool roundedUp`; the BAF `_jackpotTicketRoll` emit at `:2246` and the 2 trait-matched emit sites `:705` / `:1008`)
    - .planning/phases/277-event-surface-unification-sentinel-retirement-evt-uni/277-CONTEXT.md (D-277-AR-EMIT-01 — auto-resolve DOES emit `LootBoxOpened`; D-277-AR-INDEX-01 — with `lootboxIndex = 0`; D-40N-SILENT-01 — auto-resolve cold-bust is silent; D-277-CONSOLATION-GATE-01 — manual consolation gated on `emitLootboxEvent`)
    - .planning/phases/277-event-surface-unification-sentinel-retirement-evt-uni/277-A-SUMMARY.md (the shipped `LootBoxOpened` / `JackpotTicketWin` field order — the log-decode assertions MUST use the actual shipped field positions)
    - package.json (the existing test-script structure — mirror the Phase 275/276 wiring for where new `test/unit/` + `test/edge/` files are registered)
  </read_first>
  <action>
Create `test/edge/EventFieldConsistency.test.js` and wire `package.json`.

(1) CREATE `test/edge/EventFieldConsistency.test.js` with 3 describe blocks:

  TST-EVT-UNI-04 — manual-path `LootBoxOpened` field-consistency:
  - Open a lootbox via `openLootBox` with a known `index`; parse the `LootBoxOpened` log from the receipt.
  - Assert `lootboxIndex` in the log equals the `index` arg passed to `openLootBox`.
  - Assert `preRollTickets` equals the pre-Bernoulli scaled value (the post-distress scaled ticket count).
  - Assert the derived `whole = (preRollTickets / 100) + (roundedUp ? 1 : 0)` equals the queued ticket count at `futureLevel` for the player.
  - Assert the v39 consolation correlation holds on the manual path: when the derived `whole == 0`, a same-tx `LootBoxWwxrpReward` IS emitted (consolation preserved on the manual path per D-277-CONSOLATION-GATE-01).

  TST-EVT-UNI-05 — auto-resolve `LootBoxOpened` field-consistency + silent cold-bust:
  - Drive `resolveLootboxDirect` (and `resolveRedemptionLootbox`) and parse the `LootBoxOpened` log.
  - Assert `LootBoxOpened` IS emitted by the auto-resolve path (D-277-AR-EMIT-01) with `lootboxIndex == 0` (D-277-AR-INDEX-01) and correct `preRollTickets` + `roundedUp`.
  - LOAD-BEARING: force an auto-resolve cold-bust (`whole == 0` from a non-zero pre-Bernoulli scaled value where the Bernoulli loses) and assert ZERO `LootBoxWwxrpReward` log, ZERO `wwxrp.mintPrize` invocation, `wwxrp.balanceOf(player)` unchanged — proving the sentinel retirement did NOT cross manual-path consolation into auto-resolve (D-40N-SILENT-01). Mirror the posture of `test/unit/LootboxAutoResolveSilentColdBust.test.js`.

  TST-EVT-UNI-06 — jackpot `JackpotTicketWin.roundedUp` field-consistency:
  - Assert `bool roundedUp` is present on the deployed `JackpotTicketWin` event ABI (`iface.getEvent("JackpotTicketWin")`).
  - Drive the BAF `_jackpotTicketRoll` path and assert the emitted `roundedUp` mirrors the actual Bernoulli outcome — `true` exactly when the round-up incremented `whole` (derive the expected outcome from the seed/`entropy` slice `bits[200..215]`), `false` otherwise.
  - Drive a trait-matched jackpot ticket-win path and assert `roundedUp == false` at the `:705` / `:1008`-style emit sites.

(2) Test placement: `test/edge/` for this file per the Phase 275/276 boundary/field-consistency scheme. Do NOT create new top-level test dirs.

(3) WIRE `package.json` — register the 4 test files (the 3 from Task 1 + this one) into the appropriate test scripts following the existing Phase 275/276 wiring pattern (e.g. the default `test` script and/or whichever script the edge/unit tests already belong to). Keep the edit minimal and consistent with the existing structure.

(4) Run the full new + updated test set: `npx hardhat test test/unit/LootboxWholeTicket.test.js test/unit/EventSurfaceUnification.test.js test/unit/SentinelRetirement.test.js test/edge/EventFieldConsistency.test.js` — all pass. Then run the full project test suite (`npm test` or the project's full-suite script) and confirm no pre-existing test regresses.
  </action>
  <verify>
    <automated>
# The 4 Phase-277 test files run green together
npx hardhat test test/unit/LootboxWholeTicket.test.js test/unit/EventSurfaceUnification.test.js test/unit/SentinelRetirement.test.js test/edge/EventFieldConsistency.test.js 2>&1 | tee /tmp/277-B-t2.log
test "${PIPESTATUS[0]}" -eq 0 || (echo "FAIL: Phase 277 test set did not pass"; exit 1)
grep -qE "[1-9][0-9]* failing" /tmp/277-B-t2.log && (echo "FAIL: failing tests present"; exit 1) ; echo "no failures"
# New edge file exists and covers the silent-cold-bust load-bearing assertion
test -f test/edge/EventFieldConsistency.test.js || (echo "FAIL: EventFieldConsistency.test.js missing"; exit 1)
grep -qE "LootBoxWwxrpReward" test/edge/EventFieldConsistency.test.js || (echo "FAIL: EventFieldConsistency.test.js missing auto-resolve silent-cold-bust assertion"; exit 1)
grep -qE "roundedUp" test/edge/EventFieldConsistency.test.js || (echo "FAIL: EventFieldConsistency.test.js missing JackpotTicketWin.roundedUp consistency check"; exit 1)
# Full suite — no regression
npm test 2>&1 | tee /tmp/277-B-fullsuite.log ; grep -qE "[1-9][0-9]* failing" /tmp/277-B-fullsuite.log && (echo "FAIL: full-suite regression"; exit 1) ; echo "full suite green"
    </automated>
  </verify>
  <done>`test/edge/EventFieldConsistency.test.js` covers TST-EVT-UNI-04 (manual-path `LootBoxOpened` field-consistency + consolation correlation), TST-EVT-UNI-05 (auto-resolve `LootBoxOpened` field-consistency + the load-bearing silent-cold-bust assertion that auto-resolve mints zero WWXRP on cold-bust), and TST-EVT-UNI-06 (`JackpotTicketWin.roundedUp` consistency across the BAF + trait-matched emit sites). `package.json` registers all 4 Phase 277 test files. The full project test suite is green with no regression.</done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 3: USER-APPROVED batched test commit</name>
  <what-built>All Phase 277 test coverage (TST-EVT-UNI-01..06): `test/unit/LootboxWholeTicket.test.js` updated (TST-WT-03/06/07 rewritten to the post-EVT-UNI surface); 3 new test files — `test/unit/EventSurfaceUnification.test.js` (topic-hash changes + `LootboxTicketRoll` removal), `test/unit/SentinelRetirement.test.js` (sentinel retirement + auto-resolve passes `0`), `test/edge/EventFieldConsistency.test.js` (manual + auto-resolve + jackpot field consistency, incl. the load-bearing auto-resolve silent-cold-bust assertion); `package.json` test-script wiring. Full project suite green.</what-built>
  <how-to-verify>
    1. Review the full batched diff: `git diff test/unit/LootboxWholeTicket.test.js test/unit/EventSurfaceUnification.test.js test/unit/SentinelRetirement.test.js test/edge/EventFieldConsistency.test.js package.json` (plus the new untracked files).
    2. Confirm `test/unit/LootboxWholeTicket.test.js` was UPDATED in place (not deleted/recreated) — the TST-WT-03/06/07 rewrites assert the post-EVT-UNI surface, the other TST-WT blocks are intact.
    3. Confirm TST-EVT-UNI-05 includes the load-bearing assertion: auto-resolve cold-bust mints ZERO WWXRP / emits ZERO `LootBoxWwxrpReward`.
    4. Confirm no new top-level test dirs were created (`test/lootbox/`, `test/jackpot/`, `test/regression/` absent).
    5. Confirm the full project test suite is green (no pre-existing test regressed).
    6. If approved, the executor commits with: `test(277): event topic-hash changes + LootboxTicketRoll removal + sentinel retirement + field consistency [TST-EVT-UNI-01..06]`. Test changes are NEVER pre-approved; the executor waits for explicit approval and does NOT push.
  </how-to-verify>
  <resume-signal>Type "approved" to commit the batched test diff, or describe required changes.</resume-signal>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Test suite ← contract source (post-Plan-A) | The test wave is the verification boundary that confirms Plan A's source mutations match the EVT-UNI requirements + D-277-* decisions. A weak/missing assertion lets a Plan-A defect ship undetected. |
| Static source-grep assertions ← `contracts/` files on disk | TST-EVT-UNI-02/03 assert via `fs.readFileSync` + regex. If the grep target path or pattern is wrong, the assertion passes vacuously. |
| Dynamic log-decode assertions ← deployed contract ABI | TST-EVT-UNI-01/04/05/06 decode event logs. If the test decodes against a stale ABI or the wrong field positions, field-consistency checks pass against the wrong shape. |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-277B-01 | Repudiation / Information Disclosure | A vacuous source-grep assertion (wrong path, wrong regex) in TST-EVT-UNI-02/03 passes without actually proving `LootboxTicketRoll` / `type(uint48).max` is gone | mitigate | The grep idiom is copied verbatim from the proven Phase 274/275 `LootboxAutoResolveRemByte.test.js` + `LootboxWholeTicket.test.js` structural-grep blocks (which already assert occurrence COUNTS, not just presence). The assertions check explicit counts (`=== 0`) against named absolute paths (`contracts/modules/DegenerusGameLootboxModule.sol`, `contracts/interfaces/IDegenerusGameModules.sol`). Task 1 verify additionally greps that the test files themselves reference the retired surfaces, catching a no-op test. The inverse Phase 274 `[06f]` test (asserted `>= 2`) is being flipped to `=== 0` — a deliberate, traceable polarity change. |
| T-277B-02 | Tampering | Field-consistency tests (TST-EVT-UNI-01/04/05/06) decode logs against the wrong field order — Plan A's `LootBoxOpened` field order is planner discretion, so a hard-coded position list could drift | mitigate | The tests read the ACTUAL shipped signature from `277-A-SUMMARY.md` (listed in `read_first`) and assert against `iface.getEvent(name).inputs` — the deployed ABI is the source of truth, not a hard-coded guess. TST-EVT-UNI-01 asserts the type list AND the topic hash, so a field-order or type mismatch fails loudly. |
| T-277B-03 | Elevation of Privilege | The load-bearing TST-EVT-UNI-05 silent-cold-bust assertion is the test-side guarantee that the sentinel retirement did not cross consolation into auto-resolve — a weak version would let a D-40N-SILENT-01 violation ship | mitigate | TST-EVT-UNI-05 mirrors the proven `test/unit/LootboxAutoResolveSilentColdBust.test.js` posture: it asserts THREE independent signals on an auto-resolve cold-bust — zero `LootBoxWwxrpReward` log, zero `wwxrp.mintPrize` invocation, and `wwxrp.balanceOf(player)` unchanged. Task 2 verify greps that `LootBoxWwxrpReward` is referenced in the edge file. The assertion is forced (a seed where pre-Bernoulli scaled is non-zero and the Bernoulli loses), not incidental. |
| T-277B-04 | Tampering | A new Phase 277 test passes but a pre-existing test silently regresses (the event-shape change has wide blast radius across the test suite) | mitigate | Task 2 runs the FULL project test suite (`npm test`) and the verify step greps for `failing` — any pre-existing test broken by the event-surface change fails the task. `test/unit/LootboxWholeTicket.test.js` is explicitly updated in-place (the known-broken file); any OTHER file that breaks surfaces as a full-suite failure and must be triaged before the commit. |
| T-277B-05 | Repudiation | Test files committed without explicit user approval (project discipline violation) | mitigate | Task 3 is a `checkpoint:human-verify` blocking gate; the plan is `autonomous: false`. Per `feedback_no_contract_commits.md` + `feedback_never_preapprove_contracts.md`, `test/` files require explicit USER APPROVAL — the executor presents the batched diff and waits; does not push. |

No high-severity residual threat. The test wave has no on-chain attack surface — its threats are verification-quality threats (vacuous assertions, stale-ABI decoding, regression blind spots), each mitigated by reusing proven Phase 274/275 idioms, asserting against the deployed ABI rather than hard-coded shapes, and running the full suite.
</threat_model>

<verification>
- `npx hardhat test test/unit/LootboxWholeTicket.test.js test/unit/EventSurfaceUnification.test.js test/unit/SentinelRetirement.test.js test/edge/EventFieldConsistency.test.js` — all pass, zero failing.
- `npm test` (full project suite) — green, no pre-existing test regressed.
- `test/unit/LootboxWholeTicket.test.js` updated in place — TST-WT-03/06/07 rewritten to the post-EVT-UNI surface; other TST-WT blocks intact.
- TST-EVT-UNI-01 asserts new topic hashes + field type lists for `LootBoxOpened` / `BurnieLootOpen` / `JackpotTicketWin` against the deployed ABI.
- TST-EVT-UNI-02 asserts `LootboxTicketRoll` zero-occurrence in `DegenerusGameLootboxModule.sol` + `IDegenerusGameModules.sol`.
- TST-EVT-UNI-03 asserts `type(uint48).max` zero-occurrence in `DegenerusGameLootboxModule.sol` + auto-resolve callers pass `0`.
- TST-EVT-UNI-04 asserts manual-path `LootBoxOpened` field-consistency + consolation correlation.
- TST-EVT-UNI-05 asserts auto-resolve `LootBoxOpened` emission with `lootboxIndex = 0` AND the load-bearing silent-cold-bust (zero WWXRP, zero `LootBoxWwxrpReward`, balance unchanged).
- TST-EVT-UNI-06 asserts `JackpotTicketWin.roundedUp` is present and mirrors the Bernoulli outcome across BAF + trait-matched emit sites.
- No new top-level test dirs created.
</verification>

<success_criteria>
- All 6 TST-EVT-UNI requirements (TST-EVT-UNI-01..06) covered across the 1 updated + 3 new test files.
- `test/unit/LootboxWholeTicket.test.js` updated so its `LootboxTicketRoll` / sentinel-referencing blocks assert the post-EVT-UNI surface; the file passes in full.
- The load-bearing D-40N-SILENT-01 guarantee is test-enforced: auto-resolve cold-bust mints zero WWXRP and emits zero `LootBoxWwxrpReward`.
- The full project test suite is green with no regression from the event-surface change.
- Test placement follows the Phase 275/276 scheme (`test/unit/` + `test/edge/`); no new top-level dirs.
- Single USER-APPROVED batched test commit `test(277): event topic-hash changes + LootboxTicketRoll removal + sentinel retirement + field consistency [TST-EVT-UNI-01..06]`; executor waited for explicit approval and did not push.
</success_criteria>

<output>
After completion, create `.planning/phases/277-event-surface-unification-sentinel-retirement-evt-uni/277-B-SUMMARY.md`
</output>
