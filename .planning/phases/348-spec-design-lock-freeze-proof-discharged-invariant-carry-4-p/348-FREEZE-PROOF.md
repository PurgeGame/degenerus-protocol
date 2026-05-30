# 348-FREEZE-PROOF — The v55 AfKing-in-Game Freeze Spine, Proven on Paper

**Phase:** 348 — SPEC (paper-only; **zero `contracts/*.sol` edits**) · **Plan:** 348-03 · **Authored:** 2026-05-30
**Requirements:** FREEZE-01 / FREEZE-02 / FREEZE-03
**Subject HEAD:** `f353a50b` (working tree) — `contracts/` **byte-identical** to the v54 de-custody HEAD `20ca1f79`
(`git diff --numstat 20ca1f79 HEAD -- contracts/` is EMPTY; the 9 commits since are docs-only). Every `file:line` below
was grep/read-verified on the live tree, so a live grep IS a valid attestation against `20ca1f79`.
**Anchor source:** the re-pinned live lines in `348-GREP-ATTESTATION.md` (348-01). This doc cites the ACTUAL re-grepped
lines, **never** the drifted doc-cited lines. In particular the box seed is **`abi.encode`** at `LB:534` (NOT
`abi.encodePacked` — that is the PRESALE box at `LB:644`, a distinct path; §1a of the attestation).

**Verdict (bottom line):**
- **FREEZE-02 — PROVEN** (index-binding; the load-bearing D-348-02 obligation). The required-path process STAGE reads
  `LR_INDEX` once and binds the stamp to the **pre-RNG** index; the no-interleave guard is SPECIFIED against source.
- **FREEZE-03 — PROVEN** (stamped-day determinism). The afking open seeds `keccak256(abi.encode(rngWord, player, day,
  amount))` from the **STAMPED** buy-day, never open-time `_simulatedDayIndex()`; zero `block.*` entropy in the draw.
- **FREEZE-01 — SPLIT.** The stamped fields `(index, amount, day)` are **genuinely frozen + proven** (by FREEZE-02 +
  FREEZE-03). The live-read fields (score / baseLevel / EV-cap, read LIVE at open per §10) are filed as a **WRITTEN
  ACCEPTED-BY-DESIGN KNOWN ISSUE** (D-348-05) — NOT proven-airtight, NOT red-teamed, carried into
  `audit/FINDINGS-v55.0.md` + the v52 cumulative sweep as dispositioned/known.

This is the SECURITY SPINE of Phase 348. The freeze story rests on obligation-1 (slice-builder fidelity, proven in
`348-INVARIANT-CARRY.md`), which is BOTH the no-brick guarantor under the no-try/catch required-path AND the substrate
this freeze proof reasons over.

---

## 0. The freeze target — what "frozen" must mean for an afking box (§10 canonical design)

Under PLAN-V55 §10 (canonical, supersedes the §0–§3 stamp framing), an afking box is processed in **two legs** split by
the day's VRF reveal:

1. **Process leg (PRE-RNG)** — a chunked STAGE inserted in `advanceGame` immediately before `rngGate` (D-348-01,
   required-path). For each funded sub it: stamps `(index = current LR_INDEX, amount, day)` into the Sub record,
   debits `afkingFunding`, and sets the `lastAutoBoughtDay == today` success-marker (set atomically AFTER a successful
   debit — a failed/mid-cycle subscribe leaves no marker → no free box). **boons OFF** → box `amount` = spend exactly
   (the boosted-amount freeze field is deleted; this is what collapses the stamp to three fields).
2. **Open leg (POST-RNG)** — a normal post-RNG leg that materializes the box from the stamp + the committed
   `lootboxRngWordByIndex[index]`, with identical draw math to `openLootBox` (`LB:503`).

**Outcome-determining inputs to the box draw** (what the seed + target-level roll consume):

| Input | v55 afking source | Frozen? |
|-------|-------------------|---------|
| `rngWord` | `lootboxRngWordByIndex[index]` — the word committed to the **stamped** `index` | ✅ via FREEZE-02 (index binding) |
| `day` | the **stamped** buy-day in the Sub record (mirrors today's frozen `lootboxDay[index][player]`, `LB:514`) | ✅ via FREEZE-03 |
| `amount` | the stamped spend (boons OFF → `amount` = spend, no boost lever) | ✅ stamped at process |
| `index` | the **pre-RNG** `LR_INDEX` stamped at process | ✅ via FREEZE-02 |
| `score` (→ EV multiplier `_lootboxEvMultiplierFromScore`) | **read LIVE at open** (§10) | ⚠ live-read window — D-348-05 known issue |
| `baseLevel` (→ target-level roll floor) | **read LIVE at open** (§10) | ⚠ live-read window — D-348-05 known issue |
| EV-cap consumption (`lootboxEvBenefitUsedByLevel[player][level+1]`) | **RMW LIVE at open** via `_applyEvMultiplierWithCap` (`LB:459`) | ⚠ live-read window — D-348-05 known issue |

The seed `keccak256(abi.encode(rngWord, player, day, amount))` (`LB:534`) consumes ONLY the four stamped/frozen inputs
(`rngWord, player, day, amount`). The live-read fields enter **after** the seed — they scale the payout (`score` →
`evMultiplierBps`) and floor the target level (`baseLevel`), they do **not** feed the seed. FREEZE-01's split falls out
of exactly this line: the seed-side is provably frozen; the multiplier/floor-side is the accepted live-read window.

> **Note on the human `openLootBox` path (`LB:529-532`):** today the human path FREEZES `scorePlus1` / `adj` /
> `baseLevelPlus1` into `lootboxPurchasePacked[index][player]` at deposit and reads that snapshot at open. The v55
> afking design **deliberately diverges** — it reads score/baseLevel/EV-cap LIVE at open (§10) rather than stamping
> them, accepting the live-read window (D-348-05) in exchange for not carrying the snapshot word in the Sub stamp.
> Humans keep the existing frozen-snapshot path; afking boxes take the live-read path → **two open routes** (§10).

---

## FREEZE-02 — Pre-RNG index-binding (the load-bearing D-348-02 proof obligation)

**Claim:** A funded afking box can NEVER attach to a lootbox index whose VRF word **already exists** at process time.
The stamp binds to the **pre-RNG** `LR_INDEX`, and that index does not receive its word until `rngGate` requests it
strictly **after** the STAGE has run. Equivalently: the player cannot inspect a revealed word and then steer a box onto
it.

### (a) The index is advanced at exactly two sites, both AFTER / OUTSIDE the STAGE

`LR_INDEX` is read via `_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)` and **advanced only** at the two RNG-request
`_lrWrite(... + 1)` sites (re-pinned `348-GREP-ATTESTATION.md` §2.4):

- **Site B — daily request, `:1629`** inside `_finalizeRngRequest` (private). This is reached from `rngGate`
  (`:1152`) via `_requestRng` on the "need fresh RNG" / "12h timeout retry" branches (`:1218` / `:1225`). `rngGate`
  is called at **`:274`** — i.e. **immediately after** the STAGE insertion point (`~:272-273`, attestation §2.4).
  So on the new-day path, the daily index advance fires **downstream of `rngGate`, strictly after** the STAGE has
  finished stamping every sub. The STAGE owns `LR_INDEX` for the whole pass; the advance happens only once the STAGE
  yields to `rngGate`.
- **Site A — mid-day request, `:1089`** inside `requestLootboxRng` (`:1016`, external, standalone). This is the
  only site that could in principle interleave with the STAGE, because it is a separate permissionless entrypoint.
  It is handled by the guard in (c).

There is **no third** index-advance site (grep of `LR_INDEX_SHIFT, LR_INDEX_MASK) + 1` returns exactly `:1089` and
`:1629`). The retry path `retryLootboxRng` (`:1105`) explicitly does **not** advance the index (comment `:1102-1104`:
"the pre-advanced lootboxRngIndex are preserved"), and `_finalizeRngRequest`'s retry branch is `if (!isRetry)`-gated
(`:1624`) so a retry never double-advances.

### (b) `LR_INDEX` is read ONCE at pass start — a single sub does not straddle

**SPECIFICATION (D-348-02, 349-owned):** the STAGE reads the current `LR_INDEX` **once at pass start** into a local
(the uniform index epoch) and stamps every sub in the day's STAGE to that **same** value — NOT a per-sub re-read. This
makes the per-day index a uniform epoch (matches the original "uniform timing for locking" goal). Two properties the
349 IMPL must preserve, both within reach because the STAGE is a single `advanceGame` sub-call:

1. **No within-sub straddle.** A single sub's processing is a straight-line stamp (`stamp ← (epochIndex, amount,
   day)`); it performs no operation that re-reads or advances `LR_INDEX` mid-sub. (The slice-builder math — obligation
   1 — computes `cost`/`ev`/`payKind` from the Sub fields + the snapshot; it does not touch `LR_INDEX`.)
2. **No cross-sub drift within the pass.** Because (c) blocks any index advance for the duration of the pass, the
   epoch local read at pass start remains the live `LR_INDEX` for every sub in the pass — re-reading would yield the
   same value, so reading once is both sufficient and the canonical form.

### (c) The no-interleave guard — SPECIFIED against source

The STAGE introduces a **new** `subsFullyProcessed` flag (it does NOT exist in source today — confirmed: grep of
`subsFullyProcessed` in `DegenerusGameAdvanceModule.sol` returns ZERO matches, so this guard must be AUTHORED at 349,
it cannot be assumed). The guard requirement, stated two equivalent ways (349 may implement EITHER; the first is the
direct analog of the existing `LR_MID_DAY` reroll-block):

> **GUARD (REQUIRED):** While `subsFullyProcessed == false`, `requestLootboxRng` (`:1016`, the mid-day index-advance
> at `:1089`) MUST be blocked — add an early `revert` when the afking STAGE has not drained, exactly mirroring the
> existing reroll-block at `:1020` (`if (_lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK) != 0) revert E();`). **OR
> EQUIVALENTLY:** order the STAGE strictly **before any index advance** within a single `advanceGame` execution AND
> hold `subsFullyProcessed == false` across calls so a separate-tx `requestLootboxRng` cannot land between the STAGE
> chunks and the day's `rngGate`.

Why this is necessary and sufficient:

- **Necessary.** `requestLootboxRng` is a standalone external function. Absent the guard, a player could (i) let the
  STAGE stamp their box to `index = N`, then (ii) call `requestLootboxRng` to advance the index AND, after the VRF
  callback, learn `lootboxRngWordByIndex[N]` — but `N` is now a *closed* index whose word is fixed. The actual freeze
  risk is the inverse: a mid-STAGE advance would let a sub stamped *after* the advance attach to an index `N+1` whose
  word is requested in the same flow the attacker triggers — collapsing the pre-RNG separation. Blocking the advance
  for the pass duration removes the lever entirely.
- **Sufficient.** With the advance blocked while `!subsFullyProcessed`, the only index advances are Site B (after
  `rngGate`, after the STAGE) and a post-pass `requestLootboxRng` (after `subsFullyProcessed == true`). In both cases
  the stamped index's word is committed by `_finalizeLootboxRng` (`:1229`), which reads `LR_INDEX - 1` (`:1230`) and
  writes `lootboxRngWordByIndex[index]` only `if (lootboxRngWordByIndex[index] != 0) return;` (`:1231` — write-once).
  The stamp bound to the pre-RNG index; the word for that index is produced by a request the player does not control
  the timing of relative to the reveal; the box draw reads `lootboxRngWordByIndex[stampedIndex]` at open (mirroring
  `LB:510`). **The player cannot observe the word and then choose the index** — the index was fixed at process, before
  any word for it existed.

Additionally, `requestLootboxRng` already self-gates against operating before the daily word is recorded:
`if (rngWordByDay[currentDay] == 0) revert E();` (`:1028`) and the 15-min pre-reset block (`:1026`). These are
pre-existing protections the guard composes with, not replaces.

### (d) FREEZE-02 disposition

**PROVEN, conditional on the 349 IMPL authoring the `subsFullyProcessed` guard exactly as specified in (c) and the
read-once epoch in (b).** The guard does NOT survive un-specified into IMPL — it is written here against the
re-pinned `:1016` / `:1089` / `:1629` / `:274` lines. This is the single load-bearing freeze obligation, and it is a
SPECIFICATION (the flag does not exist yet), not an attestation of existing code. 351 TST owns the empirical
freeze-fuzz (TST-01) that exercises a `requestLootboxRng` attempt mid-STAGE and asserts the revert.

---

## FREEZE-03 — Stamped-day determinism (the box draw is a pure function of frozen inputs)

**Claim:** The afking box draw is a pure function of `(frozen rngWord, player, stamped day, stamped amount)` with NO
block-level entropy and NO open-time day lever.

### (a) The seed carries no `block.*` entropy

The box seed at the re-pinned **`LB:534`** is:

```solidity
uint256 seed = uint256(keccak256(abi.encode(rngWord, player, day, amount)));
```

It is **`abi.encode`** (32-byte left-padded fields), NOT `abi.encodePacked` — the afking open MUST mirror this exact
construction (the PRESALE box at `LB:644` is the only `abi.encodePacked` seed and is a different path; attestation §1a).
The encoding is load-bearing: `abi.encode` vs `abi.encodePacked` produce different hash preimages, so copying the
packed form would compute a different seed and break box-outcome equivalence with `openLootBox`.

Entropy-side guard (re-verified for this proof):
`grep -nE "block\.(timestamp|number|prevrandao|coinbase|difficulty|chainid|basefee|gaslimit)|blockhash"
contracts/modules/DegenerusGameLootboxModule.sol` → **ZERO matches.** There is no `block.timestamp` / `block.number`
/ `block.prevrandao` / `block.coinbase` / `blockhash` anywhere in the module, including the `:534` draw. The only
non-stamped term in the seed is `player` (the box owner, fixed), and the only `day`-dependence is the `day` term — which
(b) pins to the stamped buy-day. **Determinism holds on the entropy side.**

### (b) The afking open seeds from the STAMPED day, never open-time `_simulatedDayIndex()`

Today's `openLootBox` (`LB:503`) seeds with the **frozen** `lootboxDay[index][player]` (read `LB:514`), falling back
to `currentDay = _simulatedDayIndex()` (`LB:513`) only when the stored day is `0` (`LB:515-517`). The
`resolveLootboxDirect` / `resolveRedemptionLootbox` template instead seeds with **open-time** `_simulatedDayIndex()`
(the sites the afking open must NOT copy: `LB:513/:766/:799/:836/:868`, attestation §2.1).

**SPECIFICATION (obligation 3, 349-owned):** the afking open seeds from the **stamped** buy-day held in the Sub
record (the third stamp field `(index, amount, day)`), mirroring today's `lootboxDay[index][player]` (`LB:514`) — it
does **not** read open-time `_simulatedDayIndex()` for the seed `day` term.

### (c) Monotonicity is necessary-but-NOT-sufficient — the boundary-pinned stamp is the structural closure

The USER's operational reality is that the process STAGE is clocked right after the day boundary and the day index is
monotonic ("no going backwards"). That makes the day **naturally fixed** at process time — but monotonicity ALONE does
not close the determinism lever:

> A keeper who is also the box player could still **choose** to open same-day vs a later day. If the open seeded from
> open-time `_simulatedDayIndex()`, those are two different `day` terms → two different seeds → two different
> deterministic box outcomes the player could select between. Monotonicity bounds the day forward but does not pin a
> single value to the box.

**Structural closure:** stamp the boundary-pinned process day into the Sub record and seed the open from that
**stamped** value (b). Then the `day` term is fixed at process time for every later open of that box, regardless of
when the open is called. This makes the draw airtight at ~zero cost precisely because the day is already determined the
moment the box is processed. → This is exactly why the v55 stamp is `(index, amount, day)`, not just `(index, amount)`.

### (d) FREEZE-03 disposition

**PROVEN, conditional on the 349 IMPL seeding the open from the stamped day (b) and mirroring the `abi.encode` form
(a).** No `block.*` entropy exists in the draw (verified ZERO). The determinism lever (open-time day choice) is closed
by the boundary-pinned stamp. 351 TST owns the empirical same-seed determinism proof.

---

## FREEZE-01 — Freeze-completeness (SPLIT: stamped fields proven; live-read window an accepted-by-design known issue)

Per D-348-05, FREEZE-01 **splits** into a proven half and a documented-tradeoff half.

### (a) The stamped fields `(index, amount, day)` are genuinely frozen + proven

- `index` — frozen at the pre-RNG `LR_INDEX` (FREEZE-02). The box reads `lootboxRngWordByIndex[stampedIndex]` at open;
  the word for that index does not exist at process and is committed write-once by `_finalizeLootboxRng` (`:1231`).
- `day` — frozen at the boundary-pinned stamp; seeds the draw (FREEZE-03), not open-time `_simulatedDayIndex()`.
- `amount` — frozen at the stamped spend. **boons OFF** for afking boxes (§10) ⇒ `amount` = spend exactly, with no
  boosted-amount field and no open-time amount lever. The seed consumes this stamped `amount` directly (`LB:534`).

Together with the no-`block.*` entropy guard (FREEZE-03a), the **seed-determining set is fully frozen**: an afking box's
seed `keccak256(abi.encode(rngWord, player, day, amount))` is fixed the instant the box is processed.

### (b) ⚠ ACCEPTED-BY-DESIGN KNOWN ISSUE — the live-read window (score / baseLevel / EV-cap read LIVE at open)

> **This is a written accepted-by-design known issue, NOT a proven-airtight guarantee and NOT a red-teamed surface.**
> Precedent: the 339-01 D-03 whale-frontrunning-on-VRF-resolution non-finding (enshrined in
> `339-TRAITBURNTICKET-SOUNDNESS-ATTESTATION.md`).

Under §10, the afking open reads three fields LIVE at open rather than stamping them: the activity **score** (→
`_lootboxEvMultiplierFromScore`, the 80→135% EV multiplier), the **baseLevel** (→ the target-level roll floor,
`_rollTargetLevel`), and the **EV-cap** consumption (`lootboxEvBenefitUsedByLevel[player][level+1]`, RMW at open via
`_applyEvMultiplierWithCap`, `LB:459`). These enter the payout **after** the seed (they scale/floor the result; they
do not feed `keccak256`), so the box's *seed* is frozen even though its *scaling* is live.

**Why there is no credible attack vector (USER-established; the −EV / no-credible-actor rationale):**

1. **Committed pass-holders.** Afking subs are pass-gated via `validThroughLevel` (`AfKing.sol:103`, written at
   subscribe `:371`). The subscriber population in any given process→open window is a committed set; there is no
   open-the-floodgates anonymous actor who can materialize a favorable live-read on demand.
2. **No on-demand score lever in the ~5-min process→open window.** The activity score that drives the 80→135%
   multiplier is **streak-built over many levels** — it cannot be spiked inside the short window between the post-
   boundary process STAGE and the post-RNG open. There is no single transaction that moves a player's score enough to
   matter within that window.
3. **A legit full-price action is fine / −EV.** The only "lever" a player has is to legitimately improve their
   standing (e.g. buy a deity pass at full price) before opening a pending box. That is a real economic action priced
   at fair value, not an exploit — and on expectation it is −EV (you pay full price for a marginal multiplier shift on
   one box). This aligns with the USER-LOCKED audit weighting ([[threat-model-reentrancy-mev-nonissues]]: RNG-freeze
   is the dominant concern, and a player **cannot manipulate the VRF input after the request** — which the stamped
   `(index, amount, day)` + committed word fully covers; the live multiplier is not VRF input).
4. **The seed — the only VRF-determined output — is already frozen** (FREEZE-02 + FREEZE-03). The live-read affects
   only the deterministic scaling/floor applied to an already-fixed draw, not which trait/level the box rolls.

**Disposition:** filed as a written accepted-by-design known issue. **NO `/economic-analyst` red-team** (the USER
established there is no credible vector; this is documented, not defended). **CARRIED into `audit/FINDINGS-v55.0.md`**
(the in-milestone 352 sweep) **+ the v52 cumulative cross-model sweep** as dispositioned/known — so neither sweep
re-litigates it; it is treated as a known accepted tradeoff.

### (c) FREEZE-01 disposition

**SPLIT-PROVEN.** The stamped fields `(index, amount, day)` — the seed-determining set — are genuinely frozen + proven
(a). The live-read fields (score/baseLevel/EV-cap) are the documented accepted tradeoff (b), NOT proven-airtight.

---

## Dropped defenses (recorded so they are not re-raised)

- **Early-slot post-RNG window-closure — DROPPED.** The idea of slotting the afking open early in the post-RNG chain
  (USER, then set aside) was a window-*tightener* for the live-read window. Since the window is now **ACCEPTED as a
  known issue (not closed)** (D-348-05), the tightener is **not needed** → the afking open stays a **normal post-RNG
  leg**. This also resolves the PLACE-02 "protocol-early-sequenced" drift (the open is not specially sequenced), and
  **the VRF-timing must-verify is DROPPED** (there is no early-slot ordering to verify against the VRF reveal). The
  open's only freeze obligations are FREEZE-03 (stamped-day seed) + reading `lootboxRngWordByIndex[stampedIndex]`.

---

## Cross-references

- **Obligation-1 (slice-builder fidelity)** — the substrate this freeze proof rests on (the process leg's stamp is
  built from the `_resolveBuy` slice math) — is carried + auditor-checked in `348-INVARIANT-CARRY.md`.
- **EV-cap at open** (`_applyEvMultiplierWithCap` keyed `[player][level+1]`, the live RMW that is part of the live-read
  window) — the equivalence + double-draw guard are in `348-INVARIANT-CARRY.md` (obligation 2 + §7-iii).
- **The no-interleave guard SPEC** (FREEZE-02c) is the load-bearing input the 349 IMPL must author; 351 TST-01 proves
  it empirically.

---

*Zero `contracts/*.sol` edits — `git diff --name-only -- contracts/` is empty (only the pre-existing unrelated
`scope.txt` change is in the working tree, untouched by this plan). Paper-only SPEC proof; the only CLI used was
`git diff` + `grep`/read (read-only source inspection). Phase: 348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p · Plan: 348-03.*
