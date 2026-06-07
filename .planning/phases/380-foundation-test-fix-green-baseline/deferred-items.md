# Phase 380 — Deferred Items (out-of-scope discoveries)

Items discovered during execution that are NOT directly caused by the executing plan's
changes. Logged, not fixed, per the executor SCOPE BOUNDARY rule. For the Plan 380-04
full-suite gate / council-sweep oracle.

## From Plan 380-02 (event-schema + deity storage-collapse test refresh)

### DEF-380-02-01 — Hardhat gameover-VRF drive harness does not reach `gameOver()==true` at c4d48008

**Discovered during:** Task 2 (FOUND-03 deity-refund test refresh).

**Suites affected (Hardhat JS, NOT in the forge REGRESSION-BASELINE ledger):**
- `test/edge/GameOver.test.js` — 9 passing / 7 failing
- `test/unit/SecurityEconHardening.test.js` — 23 passing / 16 failing

**Symptom:** The multi-step `triggerGameOverAtLevel0(game, caller, mockVRF)` helper
(`advanceGame` -> VRF request -> `fulfillRandomWords` -> `advanceGame`) does not drive
`gameOver()` to `true` against the frozen subject `c4d48008`. The failures present as
`expected false to equal true` (the `gameOver()` assertion) and the downstream
`expected 0 to be at least 20000000000000000000` (no deity refund credited because
gameover never latched). The failures span the WHOLE suite — including tests this plan
never touched (FIX-01..FIX-04 whale/lazy/deity/receive blocked-after-gameover, FIX-06
"refund only via drain", FIX-07 FIFO, and the pre/post-game timeout + advanceGame-path
tests in GameOver.test.js).

**Proof it is PRE-EXISTING (not caused by the FOUND-03 schema edits):** the pass/fail
counts are byte-identical with vs without this plan's edits —
- GameOver.test.js: baseline (HEAD) 9/7 == with-edits 9/7
- SecurityEconHardening.test.js: baseline (HEAD) 23/16 == with-edits 23/16
The Plan 380-02 edits to these two files are comment / describe-title / field-name only
(the static `deityPassPricePaid` realignment); they change no executable assertion's
outcome.

**Root cause (DIAGNOSED via a throwaway probe, NOT fixed here):** the shared
`triggerGameOverAtLevel0` helper drives a FIXED two-step sequence (advanceGame -> fulfill
-> advanceGame), but at `c4d48008` the gameover latch needs MORE advance+fulfill cycles.
Probe trace at level 0 after a 912d+ warp:
- advance#1 -> reqId=1, `gameOver=false`, `rngLocked=true`
- fulfillRandomWords(reqId,42) -> ok
- advance#2 -> `gameOver=false`, `rngLocked=STILL true`   <-- the helper stops here
- (extra) advance#3 + fulfill -> `gameOver=false`
- (extra) advance#4 + fulfill -> `gameOver=true`           <-- latches only here
So each advance re-issues a fresh VRF request that must be fulfilled before the next
advance progresses; the fixed 2-step never reaches the latch. The frozen
`AdvanceModule`/`GameOverModule` code paths are byte-identical baseline->subject — this is
a harness-drive shape drift, not a contract defect (the same "byte-identical code path"
carried-red class Plan 380-01 documented for the forge suites).

**Fix recipe for Plan 380-04 (test-only):** replace the fixed 2-step helper with a bounded
loop that keeps advancing AND fulfilling the latest request id until `gameOver()` (or a
safety cap), mirroring the `driveFullVRFCycle` loop idiom but re-fulfilling inside the
loop, e.g.:
```js
async function triggerGameOverAtLevel0(game, caller, mockVRF) {
  for (let i = 0; i < 40; i++) {
    await game.connect(caller).advanceGame();
    if (await game.gameOver()) return;
    const rid = await getLastVRFRequestId(mockVRF);
    if (rid > 0n) { try { await mockVRF.fulfillRandomWords(rid, 42n); } catch {} }
    if (await game.gameOver()) return;
  }
}
```
This helper is duplicated in BOTH `test/edge/GameOver.test.js` and
`test/unit/SecurityEconHardening.test.js` (and a similar fixed-step pattern likely recurs
in other gameover-driving JS suites) — the 380-04 gate should fix all copies together.

**Why deferred (NOT fixed in 380-02):** out of FOUND-03's named scope. FOUND-03 is the
`deityPassPurchasedCount` / `deityPassPaidTotal` -> `deityPassPricePaid` + `min(pricePaid,
20e18)` field-name/semantics realignment, which IS complete (AC grep clean; the static
deity-refund framing now matches the frozen source). Repairing the gameover-VRF drive
harness is a distinct workstream (the JS full-suite green gate) that belongs to Plan
380-04, not the schema-delta plan. Per the SCOPE BOUNDARY rule, pre-existing failures in
an unrelated harness path are not auto-fixed here.

**No contract change implicated.** The frozen subject is correct by construction; the gap
is in the test harness's gameover drive, to be re-derived against the frozen source at the
380-04 gate.
