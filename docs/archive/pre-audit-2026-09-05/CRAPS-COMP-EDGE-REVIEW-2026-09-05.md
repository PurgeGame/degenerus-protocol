> Historical document. Superseded by the [current audit handoff](../../AUDIT.md). Claims and test counts below apply only to their original revision.

# Comp edge review — 2026-09-05

This follow-up supersedes broad reassurance about the latest future-window additions.
The comp-budget design remains coherent, and no allowance bypass was demonstrated, but
there are two concrete behavioral defects to address. No production source was edited.
Source hashes and replay logs are in `audit/comp-edge-review-2026-09-05/` (local, ignored).
All production sources still matched the tested snapshot at the final comparison.

## New future-window lapse gap

`_reserveWindow` writes an ordinary window seat and debits the comp allowance up front.
If advance never opens that day, `keepScheduled` invokes `_sweepLapsedDay` and steps over
all seven windows. That sweep only visits `_dayTickets` and day-ticket bet IDs; the new
window-local reservations are not among them.

Witness: reserve a normal routine window for 1,227 FLIP-equivalent; advance time beyond
its unopened day; run the actual keeper until its cursor passes that day. The reserved
field retains one unresolved seat, the player gets zero pass credits, and the budget
remains lower by 1,227. The witness passes by asserting this undesirable behavior.
This is a stranded comp, not a demonstrated theft or budget overspend.

Fix direction: define restitution for unplayed single-window reservations and include
those reservations in a bounded, once-only lapse sweep. Do not substitute a full-day
pass for a cheaper window inadvertently. A refund of the charged comp allowance or an
equivalent replacement reservation needs an explicit policy; test repeated/partial
sweeps and both normal/high reservations.

## Pre-existing cross-day progressive qualification overwrite

`_noteRoutineVictory` stores one day per winner in `_routineGoalDay[winner]`. The event
progressive checks that same single day for its repeat-victory doubling. Recording a
routine win from another day therefore removes the earlier day's qualification, even
if its event has not yet been resolved. Permissionless out-of-order resolution makes
that ordering relevant. The same implementation exists in HEAD, before these comps.

The supplied `PostRequestOutcomeControls.t.sol` witness ran successfully: under identical
progressive pool, event result and standing, the payout helper returns 800,000 without
the intervening day update and 400,000 after it. This test uses production-helper taps
and injected outcomes, not a complete public-transaction payout scenario.

Fix direction: preserve qualification per player AND day; verify both chronological and
out-of-order completion and maintain the intended rule for an event finalized before
its own day's routine win. This is distinct from shared progressive-pool depletion by
other legitimate awards, which is inherently order-dependent under the current model.

## Checks

Latest selected suites: 95 tests passed across four suites, including inherited tests
and supplied witnesses. That count is NOT proof of no defect: the witness tests explicitly
assert current problematic behavior. The separate new lapse witness also passed, confirming
the gap. Current reservation duplicate/seat-number checks and delegate allowance/rollback
checks passed. Earlier full-repository and 95-test results do not certify these additions.
