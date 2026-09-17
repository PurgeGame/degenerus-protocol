> Historical document. Superseded by the [current audit handoff](../../AUDIT.md). Claims and test counts below apply only to their original revision.

# Craps rotating shooter: Claude implementation plan

> **Status: IMPLEMENTED IN THE CURRENT WORKTREE; FOCUSED VERIFICATION PASSING.** Written
> 2026-09-03; verification updated 2026-09-04. Not committed or deployed.
>
> This document began as an implementation handoff and now also records the working-tree
> verification. It is not a description of deployed behavior; the live deployment remains
> authoritative until these changes are reviewed and shipped.

<agent_identity>

You are Contract Claude, the senior Solidity engineer responsible for implementing and verifying
the rotating-shooter feature in the Degenerus Craps Battle system. Work from the live repository,
not from this plan alone. Preserve deterministic settlement, preview/payment parity, shared dice,
storage compatibility, code-size limits, settlement gas bounds, and the current dirty working tree.

Inspect the live diff before editing. Do not reset, restore, discard, stage, or commit unrelated
changes. If the live code contradicts a premise that would change the approved economics, report
the contradiction before changing semantics. Resolve ordinary naming and packing details without
turning them into product questions.

</agent_identity>

## Verification update — 2026-09-04

The implementation and the production-default simulator now agree on the proposed eight-row Hot
Shooter table, the `RotatingShooter` domain, the +5% one-turn uplift, and the engine bounds. The
simulator also retains `legacy`, `rebalanced`, and `rotating` modes so all economic comparisons use
paired common randomness.

The principal policy cells below use the integer `standard_mixed` field, twelve independent seeds
(`20260903..20260914`), exact shared starts and sequential seat offsets. Each 10- and 80-seat mode
contains 168 million seat-runs; each 40-seat mode contains 336 million seat-runs. Positive player
value is a lower engine edge than the legacy schedule. Positive net-burn change is more retained
FLIP after the unchanged allocation.

| Seats | Legacy edge | Stacked edge | Player value change | First-turn reach | Net-burn change/day | 95% seed-block interval |
|---:|---:|---:|---:|---:|---:|---:|
| 10 | 18.2379% | 17.2498% | +0.9881 pp | 75.5238% | -1,543.8 FLIP | +0.8585 to +1.1176 pp |
| 40 | 22.0443% | 22.0648% | -0.0205 pp | 20.1287% | +128.2 FLIP | -0.0721 to +0.0311 pp |
| 80 | 22.5638% | 22.8270% | -0.2632 pp | 10.0622% | +3,293.4 FLIP | -0.2908 to -0.2356 pp |

At forty seats, the reduced natural table by itself moved edge from 22.0443% to 22.6031%
(+0.5588 pp to the engine). Adding the rotation returned 0.5383 pp to players, leaving the net
+0.0205 pp engine movement above. The whole 95% interval remains inside the plan's absolute
0.10-pp acceptance band. The roughly 128-FLIP daily change is about 0.10% of the approximately
124,988-FLIP scheduled daily allocation at this activity level. The 50,000-FLIP base and 1,200-bps
action rate were not changed.

Across the eight placed-chip rows at forty seats, observed first-turn reach was 19.45–20.18%, and
natural overlap reproduced each row's 5–15% eligibility rate. The deterministic first-order
change in expected uplift per active hand remains between -0.025 and +0.045 percentage points of
eligible profit across all rows. Raw row-level engine-edge means remain tail-sensitive, so they
must not be treated as more precise than the aggregate policy cells above.

High-lane checks used four seeds and 560,000 high-seat runs per forced lane. The stacked system's
10x high-seat credit was 483,753 FLIP at p99 and 1,783,752 FLIP at p99.9; the 100x figures were
4,785,025 and 17,522,530 FLIP. The largest sampled credits were 30.424 million and 2.926 billion
FLIP respectively, both slightly below the corresponding legacy maxima in the paired sample. The
tail remains intrinsically large because of the existing mandatory escalator, but rotation did
not add another draw or another high multiplier.

Verification completed:

- `CrapsShooterBoost.t.sol`: 25/25 passing, including the 1,000-case first-lap permutation fuzz,
  exact rows, overlap/floor order, high scaling, custom exclusion, and preview/payment parity.
- All `test/craps/*.t.sol` suites: passing.
- `CrapsRealWiringConservation.inv.t.sol`: passing.
- `CrapsGas.t.sol`: 6/6 passing. Scheduled 512-shooter worst case is 2,672,341 gas.
- Runtime size: 24,357 bytes, 219 bytes below EIP-170 and 43 bytes below the project's 24,400-byte
  guardrail.
- Storage-layout oracle: all goldens match; no storage change.
- Contract/model parity gate, warning-clean C++ build, and `git diff --check`: passing.

The all-repository `forge test -q` and standalone `forge build --sizes` commands repeatedly spent
more than six minutes rebuilding all 279 via-IR sources without reaching the test phase in this
environment and were interrupted. They are not recorded as passes. The deployed-runtime size is
still covered directly by the passing production-runtime gas test above.

## 1. Objective and approved product decisions

Give every seat in a protocol-scheduled Craps field one potential turn as the named shooter. Pick a
uniformly random starting seat only after entry has closed, then pass the shooter role through the
field's dense seat order. A seat that is still playing when its first turn arrives receives a small
profit-only boost for that hand.

The approved rules are:

1. The rotating-shooter uplift is **+5% of eligible hand profit**.
2. It applies on that seat's **first assigned shooter only**, once for the whole run in that slot.
3. It **stacks additively** with natural Hot Shooter. It does not compound.
4. If natural Hot Shooter is `u%`, the combined uplift is `u + 5`, applied to the same eligible
   profit base and floored once.
5. One random start is shared by the whole field. The role then advances in dense seat order and
   wraps from the last seat to seat one.
6. The rotation is fixed when the field closes. If a seat's personal run ends before its turn, its
   boost is forfeited. Do **not** remove dead seats and do not compact or recompute the order.
7. The displayed shooter role may continue cycling after the first lap, but the +5% benefit exists
   only on the seat's first turn.
8. The feature is for **protocol-scheduled windows only**. Custom battles continue to receive zero
   house-funded shooter boost.
9. Ordinary, high, day-ticket, house, Vault, and other protocol seats participate as the seats they
   already are. A high seat gets one boosted base run and the existing high multiple scales it once.
10. “Once per resolution” means once per player per scheduled **slot/window**, not once per
    `resolveSlot` transaction or settlement batch. Scheduled entry rules already enforce one seat
    per address in a field.
11. Add no persistent per-seat or per-field rotation storage. The result must be reproducible from
    inputs already frozen before settlement.

The feature is intended to create a visible low-population perk while leaving the overall shooter
subsidy approximately unchanged around forty seats, slightly higher below that level and slightly
lower above it.

## 2. Live-code grounding

Read these before editing:

- [`contracts/Craps.sol`](../../../contracts/Craps.sol): pure hand and multi-hand run engine.
- [`contracts/CrapsBattle.sol`](../../../contracts/CrapsBattle.sol): dense seat fields, scheduled/custom
  classification, settlement batching, scoring, previews, and the current Hot Shooter table.
- [`test/craps/CrapsOracle.sol`](../../../test/craps/CrapsOracle.sol): independent settlement oracle.
- [`test/craps/CrapsShooterBoost.t.sol`](../../../test/craps/CrapsShooterBoost.t.sol): current profit-only
  boost and entropy tests.
- [`test/craps/CrapsResolveBudget.t.sol`](../../../test/craps/CrapsResolveBudget.t.sol): batch-boundary and
  cursor invariants.
- [`test/craps/CrapsViews.sol`](../../../test/craps/CrapsViews.sol): internal views and day-ticket
  settlement harnesses that also call `_settlementOf`.
- [`scripts/craps-high-water-system-sim.cpp`](../../../scripts/craps-high-water-system-sim.cpp): current
  economic model.

Important existing architecture:

- A field is a dense, one-based range `1..entrants`.
- The field's own window-local seats come first; its day-ticket seats follow them. `_settleBatch`
  already passes the correct combined field ordinal as `seat` to `_resolve`.
- A day ticket's stored `betId` seat is local to the day field. It is **not** its combined ordinal
  inside a particular window. Never derive rotating-shooter position from `uint64(betId)` for a
  day ticket.
- The frozen field count is the low 32 bits of `_battles[w.key]`. Settlement batches and the
  `_bonusCursor` must not affect it.
- `_settlementOf` is shared by payment and previews. The new seat/count inputs must reach every
  call site identically.
- Natural Hot Shooter currently uses a player-and-hand-specific domain in `Craps._settleSlip` and
  boosts eligible profit before the mandatory hand escalator scales the base hand.
- Scheduled versus custom behavior is selected in `_settlementOf`; customs are deliberately
  passed zero boost terms.

## 3. Exact rotation definition

For a closed scheduled field, define:

```text
N       = frozen field entrant count
seat    = this slip's combined dense field ordinal, 1..N
start   = 1 + rotationDraw(fieldSeed, slot, ROTATING_SHOOTER_TAG) % N
offset  = (seat + N - start) % N
```

`offset` is the zero-based hand ordinal of this seat's first turn. Equivalently, the shooter shown
for shared hand `h` is:

```text
shooterAt(h) = 1 + ((start - 1 + h) % N)
```

The rotating uplift applies to this slip exactly when:

```text
handOrdinal == offset
```

It does not apply again at `offset + N`, even though the displayed role has cycled back to the
same seat. If the run stops before `offset`, it receives no rotating uplift. An offset beyond the
512-hand run ceiling is naturally unreachable and should encode as disabled rather than expanding
the engine's bound.

### Entropy requirements

Add a dedicated domain separator such as `ROTATING_SHOOTER_TAG`. Derive one start for the field
from future table entropy and the window slot or already slot-separated Craps seed. Requirements:

- the start is unknowable while entry or amendment is open;
- different slots do not accidentally share a start when they close onto the same table word;
- all seats in one field observe the same start;
- dice, scatter, survival, natural Hot Shooter, rounding, ladder, and tie-break streams do not
  move;
- replaying identical closed-field inputs gives the identical start;
- settlement order and batch boundaries do not enter the derivation.

Do not hash the player into the shared start. The seat offset supplies the per-seat permutation.
Modulo reduction is consistent with the contract's existing deterministic field draws.

### Fixed rotation is load-bearing

Do not “skip dead seats.” Each slip is currently settled as a complete independent run over shared
dice. Compacting a live rotation would require resolving the whole field hand-by-hand and would
make one seat's boost depend on other seats' intermediate state. That introduces cross-seat
simulation, batch-order hazards, much higher gas, and preview complexity. A dead seat simply misses
its first turn; the next shared hand names the next fixed seat.

## 4. Additive stacking and payout order

For one hand, let `profit` be the eligible-profit scalar already returned by the base hand engine.
Let `naturalPct` be either zero or the scheduled Hot Shooter uplift, and let `rotationPct` be either
zero or five:

```text
totalPct = naturalPct + rotationPct
bonus    = floor(profit * totalPct / 100)
handOut  = ordinaryBaseHandReturn + bonus
bankroll += mandatoryEscalator * handOut
```

This is additive stacking. Do not calculate `1.05 * 1.u`, and do not floor two independent bonuses
before adding them. Combining the percentages and flooring once preserves the current hand-level
accounting rule.

The existing eligible-profit boundary remains exact. The rotating boost includes Pass, Place,
hardway, and the profit portion of Don't Pass wins. It excludes principal, roll-cap refunds,
survival doubling, pre-existing bankroll, battle bounty, ladder/progressive awards, boons, and all
post-run credits.

It is intentional that the extra bankroll can cross Goal, afford another hand, change Goal/Bust,
change the high point, and change the battle winner. It must not change the shared dice or consume
another randomness draw inside the run.

## 5. Hot Shooter rebalance

Keep the current natural eligibility chances and reduce the ordinary uplifts as follows:

| Player-placed chips | Natural chance | Current uplift | Proposed uplift | Maximum when stacked |
|---:|---:|---:|---:|---:|
| 0 | 15% | 33% | 32% | 37% |
| 1 | 14% | 30% | 29% | 34% |
| 2 | 12% | 30% | 29% | 34% |
| 3 | 11% | 30% | 29% | 34% |
| 4 | 9% | 30% | 29% | 34% |
| 5 | 8% | 25% | 24% | 29% |
| 6 | 6% | 25% | 23% | 28% |
| 7 | 5% | 20% | 18% | 23% |

With additive stacking, the first-order expected boost on an active hand in the first lap is below,
where `naturalChance` is a fraction such as `0.15`, not the integer `15`:

```text
naturalChance * proposedUplift + 5 / N
```

The forty-seat neutral target is therefore approximately:

```text
proposedUplift = currentUplift - 5 / (40 * naturalChance)
```

The table uses whole percentages supported by the current byte packing and stays within 0.045
percentage points of eligible profit per active hand at `N = 40` for every row. The five-chip and
seven-chip rounding choices lean slightly toward the player instead of applying another full-point
cut.

The proposed low-16-bit schedule constant is:

```text
0x1205170618081D091D0B1D0C1D0E200F
```

Do not rely on the hex alone: retain a row-by-row test of chance and uplift.

Replacing natural Hot Shooter entirely was rejected. Calibration indicated that matching its
current value with only one reachable turn at forty seats would require roughly a 125–130% one-time
uplift, contrary to the intended small, bounded perk.

## 6. Suggested data plumbing

Prefer the smallest representation that preserves clarity, preview parity, and gas. One viable
approach is:

1. Obtain `N` once from the frozen scoreboard and use the combined `seat` already carried by the
   settlement walk.
2. Derive `start` and `offset` outside the hand loop.
3. Encode `offset + 1` above the current 16-bit Hot Shooter terms. Zero means disabled. Ten bits
   are enough for first-hand ordinals 0..511.
4. If `offset >= _MAX_SLIP_HANDS`, encode zero because that turn cannot be reached.
5. Pass this packed term into `_settleSlip`; compare its decoded value with the existing hand
   ordinal in the loop.

If this packing is used, fix the current natural-uplift read. `boost >> 8` would accidentally
include the new high bits; decode the natural percentage explicitly with `(boost >> 8) & 0xFF`.
Do not overlap the hand-return/log packing or any stored header field.

Claude may choose a separate argument if measured code size, stack pressure, or readability makes
that safer. Either way:

- compute no rotation hash per hand;
- add no storage write;
- do not let the resolver's current batch cursor stand in for `seat` or `N`;
- preserve a zero term for custom battles;
- preserve the exact existing natural Hot Shooter draw.

Audit every `_settlementOf` call site. In particular:

- `_resolve` already receives the combined seat;
- direct window previews can use their window-local seat because those seats occupy the first
  segment of the combined field;
- day-ticket test/view paths such as `CrapsViews.settlementOn` must add the window's own-seat count
  to the day-local seat;
- payment, preview, oracle, and test harnesses must all use the same frozen `N` and combined seat.

If adding `N` and `seat` to function signatures causes via-IR stack pressure, use a small packed
memory/input word or a transient field in the existing memory-only `Window` representation. Do not
solve stack pressure with persistent state.

## 7. UI and public derivation contract

The website should be able to show the named shooter beside the shared dice for every hand. This
repository does not contain that frontend, so deliver a canonical derivation/API for its consumer.

Preferred UI data after the table word exists:

```text
rotationOf(slot) -> (entrants, startSeat)
shooterAt(slot, handOrdinal) -> denseSeat
```

One compact view plus the published formula is sufficient; do not add an event or storage solely
for display if the values are already derivable. If contract code size makes a production view too
expensive, place the canonical helper in the appropriate lens/interface and add a parity test
against settlement.

The frontend behavior to hand off is:

- show the seat/player identity beside the dice for the current shared hand;
- advance sequentially and wrap at `N`;
- mark the first lap as eligible for the +5% rotating bonus;
- when natural Hot Shooter overlaps, show both labels or a combined `Hot Shooter +5%` treatment;
- do not imply that a dead seat's turn was reassigned;
- drive the animation from shared hand ordinal, never from `resolveSlot` batch position.

The existing placement logs/indexer may resolve dense seat to player. If that mapping is not
available for the combined own-seat/day-seat range, expose or document one canonical resolver
rather than duplicating the split in multiple clients.

## 8. Economic evidence and acceptance bands

The preliminary model retained the shipped five-round bankroll, 5x Goal, three-hand escalator,
current natural Hot Shooter draws, profit-only accounting, and the weighted `mixed_40_cohort`:

- 50% blank seats;
- 12.5% each sharp place, mixed, pass-heavy, and Don't-Pass-heavy seats.

The key cells used four independent seeds (`20260903` through `20260906`) with one million runs per
strategy per seed and paired common randomness. Positive player-value change means a lower engine
edge than the current rules.

| Seats | Reach first turn | Current edge | Proposed stacked edge | Player value change | Direct boost change | Approx. net-burn change/day |
|---:|---:|---:|---:|---:|---:|---:|
| 10 | 75.71% | 22.262% | 21.304% | +0.958 pp | +1.034 pp bankroll | -1,497 FLIP |
| 40 | 20.11% | 22.262% | 22.270% | -0.008 pp | +0.009 pp bankroll | +50 FLIP |
| 80 | 10.05% | 22.262% | 22.546% | -0.284 pp | -0.280 pp bankroll | +3,549 FLIP |

The FLIP column uses the simulator's expected 15,622.5 FLIP of bankroll action per ordinary daily
ticket. At steady activity, with the same ticket count and action profile across the trailing
window, the existing scheduled allocation remains unchanged:

```text
allocation(N) = 50,000 + 12% * 15,622.5 * N
```

At forty tickets that is 124,988 FLIP. A roughly 50-FLIP modeled burn difference is approximately
0.04% of the scheduled allocation and is economically neutral for this purpose. Ten seats receive
a modest low-population subsidy; eighty seats retain modestly more burn. The production budget's
existing trailing-window lag and realized ladder variance remain unchanged by this feature.

A paired two-million-run sanity cell at one seat showed 100% first-turn reach and about +0.18
percentage points of player value. The benefit is not monotonic below forty: it tends to peak near
five to ten seats because later random offsets receive the mandatory hand escalator while also
being less likely to survive. That variance is accepted because the start is uniformly random and
the product owner explicitly accepts unequal realized turns when they are fairly randomized.

These are calibration estimates, not invariants. Final verification must:

1. reproduce current and proposed results with the production-exact implementation;
2. run at least `N = 1, 2, 5, 10, 20, 40, 80, 160`;
3. report every placed-chip row, not only the mixed cohort;
4. use multiple seeds and paired common randomness because rare long runs create noisy tails;
5. model the exact shared starting seat/permutation at field level, not merely independent uniform
   offsets, so winner/ranking correlations are measured;
6. include ordinary, 10x, and 100x high-lane action;
7. report mean, upper-tail payout, Goal rate, mean hands, first-turn reach, overlap rate, engine
   edge, and resulting net burn after the unchanged allocation schedule.

Do not tune the 50,000-FLIP base or 1,200-bps action rate as part of this change. If production-exact
results miss the forty-seat target materially, adjust the proposed Hot Shooter uplift table, not
the global emission schedule. Treat an absolute forty-seat edge movement of 0.10 percentage points
or less as the initial acceptance band, subject to tail and high-lane checks.

## 9. Incentive and risk review

| Actor | Expected behavior or risk | Required guardrail |
|---|---|---|
| Variance-seeking player | Values the visible named turn beyond its small EV | Show the role and overlap clearly; do not imply a guaranteed profit |
| EV maximizer | May compare seat positions or wait to enter late | Future random start must make every frozen seat ex ante identical |
| Late entrant | Knows their seat number but not the start | Bind start to post-close entropy; arrival order must carry no expected edge |
| Whale/high seat | Receives a larger absolute amount because the whole run scales | Boost one base run and apply the existing high multiple once; test 100x tails |
| Sybil or griefer | Can buy funded seats to change `N` or gain more chances across wallets | Every extra seat bears full risk; monitor multi-wallet concentration and do not create free entries |
| House/Vault/protocol seat | Participates in the same dense rotation | Do not special-case identities or allow settlement order to choose their turn |
| Affiliate/competitor | No new direct control over settlement | Do not expose pre-close start information through quoting or indexing |

The stable strategy is ordinary paid participation: no actor can select a favorable offset before
the word exists, and an extra wallet must buy an entire risky seat. A griefer can increase `N`, but
cannot target who moves earlier because the start remains unknown; the paid seat also becomes part
of the same permutation. Monitor this empirically rather than adding identity heuristics to pure
settlement.

Primary risks:

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Using batch order/cursor as rotation order | Low if reviewed | Critical | Derive only from frozen combined seat, `N`, slot, and word |
| Treating a day-local seat as the combined field seat | Medium | High | Central helper plus direct/day parity tests |
| Packing offset above bit 16 without masking natural uplift | Medium | Critical | Explicit masks and boundary tests |
| Skipping dead seats | Medium product temptation | Critical | Fixed permutation; document forfeiture and reject compaction |
| Multiplicative or double-floor stacking | Medium | High | Add percentages, floor once, then scale once |
| UI and settlement deriving different starts | Medium | High | One canonical helper and parity vectors |
| High-multiple payout tail | Low/medium | High | 10x/100x simulation, gas pins, payout-tail reporting |
| Added resolver gas/code size | Medium | Medium/high | No storage, no per-hand hash, measure full-field and `advanceGame(0)` paths |

Post-launch monitoring should track field-size distribution, first-turn reach, natural/rotation
overlap, incremental rotating payout, engine edge by chip row, high-lane share, and net FLIP burn
after the existing scheduled allocation.

## 10. Required contract and oracle tests

Add focused tests covering at least:

1. The exact eight-row proposed Hot Shooter schedule.
2. `N = 1`: start is seat one and hand zero is the only boosted turn.
3. A wrap vector such as `N = 5, start = 3`, producing seats `3,4,5,1,2` on hands `0..4`.
4. Every seat appears exactly once in the first `N` hands for fuzzed `N` and start.
5. No rotating boost on the second lap.
6. A run that Busts before its offset receives no boost and does not move another seat's offset.
7. Natural-only, rotation-only, and overlapping hands. An overlap adds five percentage points,
   never multiplies, and floors eligible profit once.
8. Maximum stacked uplift is 37% on the proposed blank row.
9. Principal, refunds, survival doubling, bounty, boon, ladder, and progressive money remain
   ineligible.
10. The combined base-hand result is scaled by the mandatory escalator once.
11. Start changes across domain/slot/word vectors but is identical for all seats in one field.
12. The new domain does not move dice, scatter, survival, natural Hot Shooter, rounding, or ties.
13. Direct window seats and appended day-ticket seats receive the expected combined ordinals.
14. Whole-field settlement, one-seat batches, and mixed work-budget batches produce identical
    settlements, leader, winner, payments, and rotation.
15. Preview and paid settlement agree for ordinary, high, and day-ticket paths.
16. A high seat scales one boosted run and does not receive independent rotation draws per copy.
17. Custom battles remain byte-for-byte equivalent to the current zero-boost path.
18. Offsets at or above the 512-hand bound disable the benefit safely.
19. Field-count and arithmetic boundaries cannot divide by zero, wrap a one-based seat, or truncate
    a legitimate count.
20. The differential oracle independently reproduces rotation and additive stacking rather than
    calling the production helper for its expected answer.

Do not weaken current assertions merely because the new boost can legitimately change Goal/Bust,
hands played, bankroll, high point, or winner. Update expected semantics and retain independent
derivations.

## 11. Execution order

1. Inspect `git status`, relevant diffs, storage layout, bytecode headroom, all `_settlementOf`
   callers, and current Craps tests.
2. Add the shared rotation derivation and pure boundary vectors first.
3. Plumb frozen `N` and combined `seat` through payment, preview, and day-ticket harness paths.
4. Extend the run terms and implement the one-hand additive +5% in `Craps._settleSlip`.
5. Change the natural Hot Shooter table and pin all rows.
6. Update the independent oracle and focused unit/fuzz tests.
7. Add the canonical UI derivation/view and its parity vectors.
8. Update the simulator with the exact shared field permutation and rerun the economic matrix.
9. Update current-system documentation only after code and economic acceptance checks agree.
10. Run focused tests, gas/size checks, storage-layout checks, then the full suite.

At minimum run the current equivalents of:

```bash
forge test --match-path test/craps/CrapsShooterBoost.t.sol
forge test --match-path test/craps/CrapsSlip.t.sol
forge test --match-path test/craps/CrapsBattle.t.sol
forge test --match-path test/craps/CrapsResolveBudget.t.sol
forge test --match-path test/craps/CrapsHighRoller.t.sol
forge test --match-path test/craps/CrapsHighWater.t.sol
forge test --match-path test/craps/CrapsSystemEcon.t.sol
forge test --match-path test/craps/CrapsGas.t.sol
forge test --match-path test/craps/EngineGas.t.sol
forge test
forge build --sizes
git diff --check
```

Also run the repository's storage-layout comparison for `CrapsBattle`. The expected storage-layout
change is **none**.

## 12. Guardrails

- Do not use a settlement caller, batch boundary, gas budget, cursor, or current leader as entropy.
- Do not allow the start to be known before entry/amendment closes.
- Do not use player address in the shared start or `betId` as a day ticket's combined seat.
- Do not dynamically skip, replace, or compact dead seats.
- Do not grant the +5% more than once per slot run.
- Do not compound natural and rotating percentages or floor them independently.
- Do not boost principal or any value outside the existing eligible-profit scalar.
- Do not add a second high-seat draw or scale a high run twice.
- Do not extend the house-funded mechanic to custom battles.
- Do not alter shared dice, survival, ranking, Goal latch, escalator, payout rounding, bounties,
  boons, ladder/progressive rules, the 50,000 base, or the 1,200-bps action rate.
- Do not add persistent rotation state merely for settlement or display.
- Do not accept an economic mean while ignoring high-lane and long-run tails.
- Do not reset, restore, stage, commit, or overwrite unrelated working-tree changes.

## 13. Delivery

Return:

1. the exact start/offset formula and entropy preimage implemented;
2. the exact Hot Shooter table and packed representation;
3. the exact additive stacking and floor order;
4. files changed;
5. focused, fuzz, full-suite, storage-layout, gas, and bytecode-size results;
6. current-versus-proposed economic tables at `N = 1, 2, 5, 10, 20, 40, 80, 160`;
7. high-lane and payout-tail results;
8. the canonical frontend derivation/API for displaying the shooter beside the dice;
9. any remaining uncertainty or acceptance-band miss.

Do not commit or stage the implementation unless separately instructed.
