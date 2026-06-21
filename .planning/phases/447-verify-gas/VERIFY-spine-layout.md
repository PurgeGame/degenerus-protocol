# VERIFY — Spine Layout / Mint-Refactor Equivalence / Foil-Drain Liveness

> Subject: the spine refactor + storage append + advance wiring added since the v70 freeze
> `ffbd7796` (subject `contracts/` tree `99f2e53f`) → HEAD `9df2a37d` / working tree.
> Method: `forge inspect` authoritative storage-layout diff (forge 1.6.0), full source-diff
> trace, three isolated read-only review passes. Neutral defensive-engineering framing.
> READ-ONLY: no `.sol` or test file was modified.

## Verdict (one-line per concern)

| Concern | Result |
|---|---|
| Storage layout = all-appended, no existing slot moved | **YES — PROVEN (forge inspect)** |
| Mint/streak refactor = behavior-equivalent extraction | **YES** |
| Frozen trait producers untouched (only new `traitFromWordFoil` sibling) | **YES** |
| Quests +148 = additive, fund-safe, revert-safe, bounded | **YES** |
| advanceGame brickable / deadlockable by foil queue | **NO** |

**Top issues:** 1 LOW (defense-in-depth), 3 INFO. **0 CAT / 0 HIGH / 0 MED.**

---

## SECTION 1 — LAYOUT (highest priority)

### Method
Authoritative comparison via `forge inspect DegenerusGame storage-layout --json` on both the
v70 freeze (built in a throwaway worktree at `ffbd7796`) and HEAD. Diffed every `(slot, offset,
underlying-type)` tuple by variable label. Underlying type compared by resolving solc's type-ID
to `{label, numberOfBytes, encoding}` (the type-ID integer itself is a per-compilation artifact
and is expected to renumber).

### Result: ALL-APPENDED — no existing variable moved, resized, retyped, or repacked. **SAFE.**

- v70 layout: 87 storage vars, max slot used = **59** (`boxPlayers`).
- HEAD layout: 94 storage vars; the 7 new foil vars all land at **slot ≥ 60**, strictly after 59.
- Every v70 variable retained **identical slot + identical offset + identical underlying type**
  (label/bytes/encoding). The only diffs the raw JSON showed were 7 type-ID renumberings
  (`vrfCoordinator`, `decBurn`, `decClaimRounds`, `terminalDecEntries`,
  `lastTerminalDecClaimRound`, `boonPacked`, `_subOf`) — each resolved to the SAME human type,
  SAME `numberOfBytes`, SAME encoding, SAME slot, SAME offset. Pure compilation-artifact noise,
  **not** a layout change.

### New-slot list (the appended foil layout)

| Var | Slot | Offset | Type | Bytes | Status |
|---|---|---|---|---|---|
| `foilRecord` | 60 | 0 | `mapping(uint24 => mapping(address => uint256))` | 32 | OK-APPENDED |
| `foilMatchClaimed` | 61 | 0 | `mapping(bytes32 => bool)` | 32 | OK-APPENDED |
| `dailyFoilDraw` | 62 | 0 | `mapping(uint24 => uint256)` | 32 | OK-APPENDED |
| `foilBuyers` | 63 | 0 | `mapping(uint24 => uint256[])` | 32 | OK-APPENDED |
| `foilCursor` | 64 | 0 | `uint32` | 4 | OK-APPENDED |
| `foilDrainDay` | 64 | 4 | `uint24` | 3 | OK-APPENDED (packed) |
| `foilLastResolveDay` | 64 | 7 | `uint24` | 3 | OK-APPENDED (packed) |

`foilCursor`/`foilDrainDay`/`foilLastResolveDay` co-pack into a single fresh slot 64 (4+3+3 = 10
bytes of 32) — a new slot, repurposing nothing. All `constant`/`mask` additions
(`FOIL_TO_FUTURE_BPS`, `FOIL_PACK_ENTRIES`, `FOIL_PACK_TICKETS`, `_FOIL_*_MASK/_SHIFT`,
`FOIL_SEED_TAG`, `FOIL_CCY_TAG`, `FOIL_SPIN_TAG`) and the new view/pure accessors
(`_foilRecordFor`, `_foilMultFor`, `_foilDrainPending`, `_foilBoughtThisLevel`, `_packFoilDraw`,
`_foilDrawFor`) consume NO storage slots.

The storage source diff is a single additive hunk at `DegenerusGameStorage.sol:2391-2575`
(after the last v70 member `boxPlayers`), confirming the textual append matches the compiled
layout.

**LAYOUT FINDING: none. 0 CAT.** The single fear-class (a moved/repurposed slot) is refuted by
the compiler's own layout output.

---

## SECTION 2 — REFACTOR-EQUIVALENCE

### 2a. Mint/streak extraction — `_recordMintData` moved verbatim. **MATCH.**
- `DegenerusGameMintStreakUtils.sol` (+218, new base class) is the extraction target. The
  ~216-line activity-score / mint-streak recorder `_recordMintData` was relocated **byte-for-byte**
  from `DegenerusGameMintModule.sol` (v70 `:337-552`) into `MintStreakUtils.sol:466-666`. Function-body
  `diff` is empty: same `MASK_16` level-units clamp, same `<4`-unit early exit, same mint-day
  stamp, same whale-frozen clear, same lifetime `total` increment (capped `uint24.max`), same
  affiliate-bonus cache, same dirty-write guard, same ordering of effects, same `internal`
  visibility.
- Call site unchanged: `_recordMintData(buyer, targetLevel, mintUnits)` — identical args/order;
  `MintModule is MintStreakUtils` so the now-base `internal` fn is reachable; exactly one
  definition repo-wide (no stray copy left behind). The MintModule line-loss is this extraction
  plus the additive foil-drain wiring — **no streak/activity math was edited.**

### 2b. Frozen shared trait producers — **UNMODIFIED. MATCH.**
- `git diff ffbd7796 HEAD -- contracts/DegenerusTraitUtils.sol` is **purely additive** (first 222
  lines byte-identical). Full-function diffs of `traitFromWord`, `packedTraitsFromSeed`,
  `weightedColorBucket`, `packedTraitsDegenerette` each exit-0 (identical).
- Only NEW siblings appended: `foilCuts`, `foilTrait`, `traitFromWordFoil`, `packedTraitsFoil` —
  exactly the sanctioned "new sibling only" allowance (SPEC §2 / §6.4).

### 2c. DegenerusQuests.sol +148 — additive foil-quest, **SAFE.**
- The retired `QUEST_TYPE_RESERVED = 4` is repurposed to `QUEST_TYPE_FOIL = 4`; `rollDailyQuest`
  gains a 4th `forceFoil` param; two GAME-only entry points `handleFoilPack` / `foilStreakBoost`
  are added. **No existing quest's probability, reward, ordering, or completion path changed.**
- `rollDailyQuest`: new branch order `if (forceFoil) FOIL; else if (forceMintFlip) MINT_FLIP; else
  <weighted random>`. Pre-existing forceMintFlip + random-roll + slot-0-always-`MINT_ETH` logic is
  byte-identical to v70. The two forces are mutually exclusive by construction (opposite cycle
  ends; advance passes `phaseTransitionActive && gapDays==0` for foil vs
  `lastPurchaseDay && compressedJackpotFlag!=2` for mintFlip).
- `_bonusQuestType` random-pool skip changed `== QUEST_TYPE_RESERVED` → `== QUEST_TYPE_FOIL`
  (both `== 4`): FOIL stays excluded from the random pool exactly as RESERVED was — no probability
  shift.
- `handleFoilPack` (GAME-only): mirrors the established `handleDecimatorBurn` secondary-quest
  template — guards (zero-addr / `currentDay==0` / FOIL-slot-absent sentinel / progress<target /
  secondary-locked) are all graceful early-returns, **no reachable `revert`**, fixed
  `QUEST_RANDOM_REWARD = 100 ether` via the standard `creditFlip` path, no double-pay
  (completion-mask slot bit set before return), no loops.
- `foilStreakBoost` (GAME-only): floor-only streak ≥ 12 (never lowers), O(1), moves no funds.
- Caller check: the single live caller `DegenerusGameAdvanceModule.sol:1264` passes **4 args**;
  `IDegenerusQuests.sol` declares 4; `forge build` is clean project-wide — no 3-arg caller remains.

**REFACTOR FINDING: none. 0 CAT/HIGH/MED.**

---

## SECTION 3 — LIVENESS (advanceGame + spine cannot brick/corrupt/deadlock)

The foil drain lives in the NEW `DegenerusGameFoilPackModule.sol` (`_processFoilDrain`,
delegatecall-only `processFoilDrain`). MintModule's `_drainFoil` (`:747-769`) is a thin
delegatecall wrapper that short-circuits on `!_foilDrainPending()` and bubbles any sub-revert.
AdvanceModule's two readiness gates (`:237-254` mid-day, `:281-320` new-day) widen the existing
ticket-queue gate with `|| _foilDrainPending()`.

### Concern 1 — BOUNDED PER CALL (no gas-brick): **PROVEN-SAFE.**
- Inner buyer loop charges a fixed `(FOIL_PACK_ENTRIES*2)+3 = 35` budget units/buyer
  (`FoilPackModule:722`) and defers a WHOLE buyer when `room < 35` (`:715-719`) — max buyers/call
  = `room/35` (warm 550→15, cold 358→10). Backlog spread across many buyers defers + resumes via
  `foilCursor`; never unbounded.
- Outer day loop `while (dd <= last)` breaks on the first zero word (`:703-704`); `rngWordByDay`
  is densely sealed `[1..dailyIdx]` (gap-backfill `AdvanceModule:1895-1908`), and the drain runs
  strictly BEFORE the day's RNG draw. So the walked range ≤ `(dailyIdx+1) − foilDrainDay`, which
  the buy guard `buyFoilPack:177` (reverts any buy while advance ≥2 days behind) + the
  `resolveDay ≤ dailyIdx+2` cap (`:297`) hold to the buy-window width (a small constant). Empty
  buckets cost only 2 SLOADs/day and no `delete` (`:728` runs only when `total != 0`). The
  unpriced empty-day walk is **bounded and trivial** — cannot approach the 16.7M ceiling.

### Concern 2 — NO DEADLOCK (progress guarantee): **PROVEN-SAFE.**
- (a) If `_foilDrainPending()` is true at a gate, `_runProcessTicketBatch` runs and either
  advances ≥1 pack or defers `finished=false`; advance only falls through to RNG when the gate's
  `if` does NOT break, requiring `finished==true && worked==false` — and `finished=true` implies
  the drain caught up (see c). Advance never draws while genuinely pending.
- (b) `worked = (ticketCursor != prevCursor) || (ticketLevel != prevLevel)`
  (`AdvanceModule:1581`) correctly reports foil-only progress: the queue-empty completion path
  sets `ticketLevel = 0` (`MintModule:660`) ⇒ `worked=true`; a budget-short defer returns
  `finished=false` ⇒ advance breaks on `!preFinished`. No invisible-progress path.
- (c) `finished=true` ⇒ `_foilDrainPending()==false`: `_processFoilDrain` returns `true` only
  after the outer loop exits (`dd>last` OR zero word), writing `foilDrainDay = dd`, so the
  re-evaluated `dd<=last && rngWordByDay[dd]!=0` is false. A defer (pending stays true) always
  returns `finished=false`. The "drain a pack, finished=true, still pending → draw early" state is
  unreachable.

### Concern 3 — NO REVERT in the advance path: **PROVEN-SAFE.**
- Unsealed bucket ⇒ `break`, never revert (`:703-704`).
- `unchecked room -= 35` cannot underflow: the `room < 35` guard runs first and the guard constant
  **equals** the charge constant — verified identical (`(FOIL_PACK_ENTRIES*2)+3 = 35` at both
  `FoilPackModule:715/:722` and the wrapper pre-guard `MintModule:753`).
- Assembly trait-batch writer is a fixed loop over ≤16 distinct traits / ≤16 writes per pack — no
  OOG within one bounded pack.
- `resolveDay >= 1` always (day index is 1-indexed, `GameTimeLib`), so no slot-0/underflow read in
  `_foilDrainPending`'s `rngWordByDay[dd]`. Tier-payout reverts live only in the permissionless
  CLAIM path (try/catch-wrapped), never in the advance drain (the drain files trait entries only,
  pays no tier).
- One-pack-per-cycle cap (`_foilBoughtThisLevel`, presence `!= 0`) blocks a second buy.

### Concern 4 — LOW-WATER-MARK INVARIANT: **PROVEN-SAFE.**
- Buy update `if (foilDrainDay == 0 || foilDrainDay > prevLast) foilDrainDay = resolveDay`
  (`:320-321`): drain-caught-up resets the cursor forward (skips empty range); drain-behind leaves
  it (older buckets drain first); first-ever sets it. `foilDrainDay` always points at the earliest
  un-drained sealed-or-future bucket, never skips a populated bucket, never sticks below a drained
  one.
- A buyer landing BELOW the live `foilDrainDay` is unreachable: `resolveDay >= dailyIdx` (buy
  guard) while `foilDrainDay <= dailyIdx+1` when active; the only overlap requires
  `day < dailyIdx`, impossible. No lost-boost value bug, no stuck cursor.

**ADVANCE-BRICKABLE-BY-FOIL: NO.**

---

## RANKED ISSUES

| # | Sev | Where | Issue | Suggested fix (NOT applied) |
|---|---|---|---|---|
| 1 | **LOW** | `FoilPackModule:702-733` (`_processFoilDrain` outer loop) | The outer day-walk decrements the write budget only per *buyer*, not per *day* iterated. Bound on the walk length rests on an EXTERNAL invariant (the `buyFoilPack:177` ≥2-days-behind buy guard + RNG dense-sealing) rather than a local budget charge. Not exploitable today (walk is provably bounded to the buy window). | Add a cheap per-empty-day budget decrement (or a max-days-per-call cap) so the outer loop is self-bounding independent of the buy guard — defense-in-depth against a future relaxation of that guard. |
| 2 | INFO | `FoilPackModule:715,722` + `MintModule:753` | The `(FOIL_PACK_ENTRIES*2)+3 = 35` guard/charge is hand-replicated in 3 sites with "MUST stay equal" comments; currently identical, but drift would reintroduce the unchecked-underflow the comment warns about. | Hoist to a single named `constant FOIL_PACK_DRAIN_COST` and reference it at all 3 sites. |
| 3 | INFO | `DegenerusQuests.sol` (`QUEST_TYPE_FOIL = 4`) | Reuses retired id `4` (`QUEST_TYPE_RESERVED`). Migration-safe (v70 never rolled or persisted `4`; quests re-stamp per day), but undocumented. | One-line comment noting id 4 was provably never persisted under v70, so the reuse is migration-safe. |
| 4 | INFO | `DegenerusGameStorage.sol` `_foilDrainPending` | When `last == 0` it short-circuits before any `rngWordByDay[dd]` read, so the `dd==0` slot is never read for the pending decision. Confirmed safe; noted for completeness. | None. |

---

## EVIDENCE / REPRODUCTION

- Layout: `forge inspect DegenerusGame storage-layout --json` on a worktree at `ffbd7796` vs HEAD;
  Python tuple-diff by label + type-ID resolution. v70 max slot 59, all 7 foil vars slot ≥ 60, 0
  existing-var movement.
- Refactor: `git diff ffbd7796 HEAD -- <MintModule> <MintStreakUtils> <TraitUtils> <Quests>`;
  function-body `diff` exit-0 for `_recordMintData` and the 4 frozen producers.
- Liveness: full-body trace of `_processFoilDrain`, `processTicketBatch`, the two advance gates,
  `_runProcessTicketBatch`, `_drainFoil`, `buyFoilPack` enqueue + low-water update; guard==charge
  constants verified identical; baseline `forge test` 944/0/108 (BASELINE.md).
