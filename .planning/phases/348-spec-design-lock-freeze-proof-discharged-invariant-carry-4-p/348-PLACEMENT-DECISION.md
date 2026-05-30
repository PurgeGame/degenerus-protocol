# 348-PLACEMENT-DECISION — The §4 Process/Open Placement DECISION (PLACE-01)

**Phase:** 348 — SPEC (Design-Lock + Freeze Proof + Discharged-Invariant Carry + §4 Placement + Code-Size/GAS Inventories + Attestation)
**Plan:** 348-04 · **Authored:** 2026-05-30
**Requirement:** PLACE-01
**Decision owner:** USER (D-348-01 — the HEADLINE divergence of the v55.0 milestone)
**Subject HEAD:** `f353a50b` (working tree) — `contracts/` byte-identical to the v54 de-custody HEAD **`20ca1f79`** (per `348-GREP-ATTESTATION.md` §0; 9 docs-only commits since → grep against the live tree IS an attestation against `20ca1f79`).

> **All `file:line` anchors below are the RE-PINNED live lines from `348-GREP-ATTESTATION.md` (the load-bearing
> UPSTREAM PRODUCER for the phase), NOT the drifted doc-cited lines.** 349 IMPL cites the actual lines here.

---

## 0. THE DECISION (read first)

> **The §4 process/open placement is DECIDED = REQUIRED-PATH.** The afking process-pass is a new **chunked STAGE
> inserted in `advanceGame` immediately before `rngGate`** (new-day path only), guarded by a `subsFullyProcessed`
> flag + a `_subCursor` draining a per-call gas budget, inheriting `advanceGame`'s existing `_enforceDailyMintGate`
> standing. The **open** stays a NORMAL post-RNG cursor-chunked leg (`OPEN_BATCH`-style) — it is **NOT** folded into
> advance. This is **D-348-01**, a **DELIBERATE USER OVERRIDE** of the design doc's separate-legs recommendation.

This document records the placement as a DELIBERATE decision — **not a contradiction to be silently reconciled**. It
(1) marks the superseded recommendation, (2) records the decision basis precisely, (3) specifies the chunked-STAGE
mechanism against the re-pinned anchors, (4) carries the two proof obligations the override creates and binds each to
its proof in `348-FREEZE-PROOF.md` / `348-INVARIANT-CARRY.md` (348-03), (5) records the inherited mint-gate standing
dependency as ACCEPTED with ZERO new gate code, and (6) NOTES (does not decide) the bounty fold (PLACE-02, 349-owned).

**This is the analog of the placement-decision content that Phase 343 folded into its edit-order map — here promoted
to its own doc because it is the headline USER override of the milestone.**

---

## 1. ⚠ SUPERSEDED RECOMMENDATION — PLAN-V55 §4 + §9 (separate-legs) are NO LONGER LIVE on the placement point

**`PLAN-V55-AFKING-IN-GAME-REDESIGN.md` §4 RECOMMENDS separate permissionless legs; §9 leans the same way. Both are
hereby marked SUPERSEDED on the placement point.** A future reader (or the 349 author) MUST NOT treat the doc's
separate-legs recommendation as the live decision.

| Source (now SUPERSEDED on placement) | What it says (verbatim sense) | Status after D-348-01 |
|---|---|---|
| `PLAN-V55-AFKING-IN-GAME-REDESIGN.md` **§4 "RECOMMENDED — separate permissionless legs (autoBuy-shaped)"** | "the process-leg runs in the pre-RNG window, cursor-chunked (`BUY_BATCH`-style)… The open-leg runs post-`_unlockRng`… No coupling to advance liveness. This is the minimal-risk shape." | **SUPERSEDED** — the process-leg is now a required `advanceGame` STAGE (the §4 ALTERNATIVE is the chosen path), NOT a separate permissionless leg. |
| `PLAN-V55-AFKING-IN-GAME-REDESIGN.md` **§0-Correction-2 "→ Recommended: keep the process-pass and the open-pass as separate permissionless legs"** | recommends separate-legs on liveness-coupling grounds; "Required-path placement is documented as the alternative (§4)… at the cost of per-sub isolation." | **SUPERSEDED on the recommendation** — the liveness fear is discharged for the healthy path (see §3); the per-sub-isolation cost it cites is itself superseded by D-348-04 (no try/catch — see §4 + `348-INVARIANT-CARRY.md`). |
| `PLAN-V55-AFKING-IN-GAME-REDESIGN.md` **§9 "Next step — §4 placement"** | "Recommendation still leans separate-legs for minimal surface; required-path is on the table." | **SUPERSEDED** — the lean is overturned; required-path is DECIDED, not merely "on the table." |
| `PLAN-V55-REVERT-FREE-CHAIN-PROOF.md` **§8 "§4 placement decision (resolved by this proof)"** | "Required-path placement is VIABLE and clean… Recommendation still leans separate-legs for minimal surface, but required-path is now on the table per the user's instinct." | **The VIABILITY finding STANDS** (it is the enabling rationale — see §3); the residual "lean separate-legs" is **SUPERSEDED** by the decision. **Note also:** §8's "per-sub skip valve (obl. 4)" is itself superseded by D-348-04 (no try/catch). |

**Why this is recorded as an override, not a reconciliation:** the design docs are the source-of-truth for the
mechanism, but their *placement recommendation* was a judgement call (minimal-surface) that the USER overruled on a
different axis (guaranteed-every-day — §2). Silently "reconciling" by following the doc's recommendation would invert
the USER's decision; silently following the decision without marking the doc would leave a live-looking stale
recommendation for the next reader. Both failure modes are the documentation-integrity threat this doc closes
(`T-348-08`, Repudiation). The audit trail is therefore explicit: **doc recommends separate-legs → USER chose
required-path → §4/§9 SUPERSEDED.** (Precedent: Phase 343's D-01 recorded the `AUTOBUY-02`→`b.funder` correction the
same way — a recorded override of a carried artifact, not a silent edit.)

---

## 2. DECISION BASIS — guaranteed-every-day, NOT revert-safety

**The decision was made on GUARANTEED-EVERY-DAY grounds.** It was **NOT forced by revert-safety.** This distinction is
load-bearing and is recorded precisely so it is not later misattributed:

- **Required-path was VIABLE because the REVERT-FREE-CHAIN proof made it so — not because revert-safety required it.**
  The `PLAN-V55-REVERT-FREE-CHAIN-PROOF.md` (DISCHARGED 2026-05-30) proves that **a funded, well-formed afking sub
  cannot revert in a healthy game** → it cannot block the day from reaching `rngGate` → it cannot freeze the day. This
  **discharges the §0-Correction-2 liveness fear for the healthy path** (Correction-2 feared "a single reverting sub
  would block the day from reaching `rngGate` → game freeze = gg"; the proof shows there is no such reverting sub on
  the funded path). Required-path went from "only safe with per-sub try/catch isolation" (the doc's framing) to
  "clean by construction."
- **Given viability, the choice rested on OTHER merits** (per proof §8 + CONTEXT D-348-01): **guaranteed-every-day vs
  minimal-surface**, the **`_enforceDailyMintGate` standing interaction** (§5), and **bounty farm-by-splitting** (§6).
  The USER chose **guaranteed-every-day**: because the day advances daily regardless, riding `advanceGame` makes
  afking processing happen **every day in practice** (every sub processed every day), rather than depending on a
  separate permissionless keeper leg actually being called.
- **The recommendation it overrides leaned the OTHER way** (minimal-surface → separate-legs). The USER weighed
  guaranteed-every-day higher than minimal-surface, which is a legitimate decision the proof's viability finding
  unlocked. **Revert-safety is neutral between the two** post-proof — it no longer dictates separate-legs, so it is NOT
  the basis for choosing required-path either.

**Net:** *"required-path is chosen on guaranteed-every-day grounds; the REVERT-FREE-CHAIN proof made it VIABLE (a
funded well-formed sub can't revert → can't freeze the day → the §0-Correction-2 liveness fear is discharged for the
healthy path), so the decision rests on guaranteed-every-day vs minimal-surface, NOT on revert-safety."*

---

## 3. THE MECHANISM — a chunked STAGE before `rngGate`

The process-pass is a **new chunked STAGE inserted in `advanceGame` immediately before the `rngGate` call**, on the
**new-day path only**, guarded by a `subsFullyProcessed` flag + a `_subCursor` draining a per-call gas budget. (349
IMPL builds it; this SPEC pins the placement + the guards.)

### 3a. Insertion point (re-pinned)

| Anchor | Re-pinned line | Matched source / role |
|---|---|---|
| **STAGE insertion point** | **`AdvanceModule:272-273`** | `// RNG: use existing word or request new one` (`:272`) / `bool bonusFlip = (inJackpot && jackpotCounter == 0) \|\| lvl == 0;` (`:273`) — the new STAGE inserts **here**, immediately before the `rngGate(` call. |
| **`rngGate(...)` call site** | **`AdvanceModule:274`** | `(uint256 rngWord, uint32 gapDays) = rngGate(` — the STAGE runs strictly BEFORE this. |
| **`rngGate` def** | **`AdvanceModule:1152`** | `function rngGate(` — the point at which the day requests its VRF word (the index advances inside the RNG request). |

The STAGE sits inside the `do { … } while` block (`AdvanceModule:245…`), **after** the daily ticket-drain gate
(`:247-270`, which already guarantees `ticketsFullyProcessed` before RNG) and **before** `rngGate(:274)`. It is
new-day-path only: the mid-day same-day path (`:194-224`) returns before reaching this block, so the STAGE never runs
mid-day.

### 3b. The two guards

1. **`subsFullyProcessed` flag** — a chunk gate mirroring the existing `ticketsFullyProcessed` discipline
   (`AdvanceModule:196/247/269`): the STAGE drains the subscriber set across multiple `advanceGame` calls, advancing
   `_subCursor`; while `!subsFullyProcessed` the function `break`s and returns (a partial-drain `STAGE_*` working
   status, no RNG request yet, mult-discipline per the existing `STAGE_TICKETS_WORKING` partial-drain pattern at
   `:216-218/:264-266`); only once the cursor reaches the end does it set `subsFullyProcessed = true` and fall through
   to `rngGate(:274)`. **This is the exact "drain a slot fully before RNG" shape the ticket gate already uses.**
2. **`_subCursor` per-call gas budget** — drains a bounded number of subs per `advanceGame` call (a `BUY_BATCH`-style
   chunk size), so a large subscriber set spreads across several advance calls without exceeding the 16.7M advance-
   chain gas ceiling (`[[threat-model-reentrancy-mev-nonissues]]`: gas-DoS in the advanceGame chain is the HIGH
   surface).

**Process-leg chunking = pre-RNG, cursor-chunked, `BUY_BATCH`-style** (inside the STAGE). **Open-leg = a NORMAL
post-RNG cursor-chunked leg, `OPEN_BATCH`-style** — the open is NOT folded into advance; it stays a separate router
category (consistent with §5 "Open stays a separate post-RNG router category"). This split is intentional: the freeze
guarantee comes from the pre-RNG index-binding of the *stamp* (FREEZE-02), so only the *process/stamp* leg needs to be
pre-RNG; the open materializes from the already-frozen stamp + the committed word and can run as an ordinary post-RNG
leg.

> **This also resolves the PLACE-02 "protocol-early-sequenced" drift.** The earlier idea of sequencing the afking open
> *early* in the post-RNG chain (a window-tightener) is DROPPED — the live-read window is ACCEPTED as a known issue,
> not closed (D-348-05; see `348-FREEZE-PROOF.md` FREEZE-01), so the open needs no special early slot and stays a
> normal post-RNG leg. The VRF-timing must-verify for the open is dropped.

---

## 4. CARRIED PROOF OBLIGATIONS — the two obligations the override CREATES

Choosing required-path creates exactly two proof obligations that separate-legs would not. **Both are CARRIED here and
BOUND to their proofs in 348-03 — they do not survive loose or un-bound into 349 IMPL.**

### 4a. D-348-02 — the uniform-index-epoch no-interleave guard (FREEZE-02 obligation)

**Obligation:** every sub in a day's process STAGE is stamped to the **SAME current `LR_INDEX`** (a uniform index
epoch per day), and `requestLootboxRng` **cannot interleave** an index advance while the STAGE is mid-drain
(`subsFullyProcessed == false`). Without this, a stamp could bind to an index whose VRF word already exists → freeze
broken.

**Why required-path creates it:** running the process-pass as an `advanceGame` STAGE means it shares the call surface
with the index-advance machinery; the proof must verify `requestLootboxRng` (`AdvanceModule:1016`, advancing
`LR_INDEX` at the two `_lrWrite(… _lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK) + 1)` sites **`:1089`** and **`:1629`**)
cannot fire mid-STAGE, and that a single sub's processing reads `LR_INDEX` once (does not straddle an advance within
one sub). Separate-legs would get the uniform epoch "for free" from the index-binding alone; required-path must
SPECIFY the guard (block `requestLootboxRng` while `!subsFullyProcessed`, OR order the STAGE strictly before any index
advance — which the §3a insertion point already does, since the STAGE precedes `rngGate(:274)` and the index only
advances at the RNG request).

> **→ PROVEN in `348-FREEZE-PROOF.md` (FREEZE-02).** That doc owns walking the AdvanceModule source, proving the
> `LR_INDEX`-read-once claim, stating whether `requestLootboxRng` is reachable mid-STAGE, and SPECIFYING the
> no-interleave guard against the re-pinned `:1016` / `:1089` / `:1629`. This decision doc CARRIES the obligation;
> `348-FREEZE-PROOF.md` DISCHARGES it. **D-348-02** is the binding key between the two.

### 4b. D-348-04 — obligation-1 (slice-builder fidelity) as the SOLE no-brick guarantor (no try/catch)

**Obligation:** under required-path with **NO try/catch valve** (D-348-04 — the valve was DROPPED), the funded buy must
be **revert-free BY CONSTRUCTION**, which rests SOLELY on preserving `_resolveBuy`'s slice-builder validation
invariants VERBATIM when it folds into the process STAGE (proof §5 obligation 1). If those invariants are mis-stated
for the fold, a single sub bricks the day — there is no valve to catch it.

**Why required-path creates it (and why the valve was dropped):** the design doc's §4 ALTERNATIVE and the proof's §8
both originally said required-path needs "a thin per-sub try/catch skip valve" (proof §5 obligation 4) to absorb the
residual revert classes. **D-348-04 DROPPED that valve** (prompted by USER: "didn't we get rid of try/catch?"):

- **The healthy path is revert-free by construction** via obligation 1 — there is nothing to catch.
- **Class B (solvency-violation) FAILS LOUD** — catching it would *mask* a catastrophic SOLVENCY-01 violation (the
  `claimablePool -= uint128(ev)` underflow). It must propagate.
- **Class C (liveness-timeout) is terminal** — the game is already ≥120-day-dead / heading to game-over; the SPEC
  instead verifies the afking STAGE cannot block the game-over routing (a separate advance path — `_handleGameOverPath`
  at `AdvanceModule:182`, which runs and returns BEFORE the STAGE block is reached).

**Consequence:** the proof burden CONCENTRATES on obligation 1, now the **SOLE day-can't-brick guarantor** under
required-path. This is exactly where the rigor sits — the light `/contract-auditor` pass on obligation-1 (D-348-06).

> **→ CARRIED + corrected in `348-INVARIANT-CARRY.md`.** That doc records the D-348-04 correction to `REVERT-02`
> (REQUIREMENTS.md, 349-owned) + proof §5 obligation 4 (both currently say "thin per-sub try/catch skip valve"),
> rewrites them to the no-valve form (revert-free-by-construction + fail-loud-on-solvency + terminal-routing-unblocked),
> and runs the light `/contract-auditor` obligation-1 pass. This decision doc CARRIES the obligation as the consequence
> of the placement; `348-INVARIANT-CARRY.md` DISCHARGES/records it. **D-348-04** is the binding key between the two.

---

## 5. MINT-GATE STANDING DEPENDENCY (D-348-03) — ACCEPTED, ZERO new gate code

**The required-path STAGE rides `advanceGame`'s EXISTING `_enforceDailyMintGate` — with ZERO new gate code. This
standing dependency is recorded as ACCEPTED.**

| Anchor | Re-pinned line | Role |
|---|---|---|
| `_enforceDailyMintGate(...)` call site | **`AdvanceModule:191`** | `_enforceDailyMintGate(caller, purchaseLevel, dailyIdx);` — runs at the top of the new-day path, BEFORE the STAGE block. |
| `_enforceDailyMintGate` def | **`AdvanceModule:973`** | `function _enforceDailyMintGate(` — the gate body: mint standing OR the 15–30min time-laddered bypass. |

- Because the STAGE is inserted **after** `_enforceDailyMintGate(:191)` and inside the same new-day `advanceGame` flow,
  it **inherits** the existing gate at zero cost: whoever drives the advance needs **mint standing OR the 15–30min
  time-laddered bypass** (which opens to anyone daily).
- Since the day advances **daily regardless** (the time-laddered bypass guarantees *someone* can always advance), the
  afking processing is **guaranteed-every-day in practice** — which is precisely the property that motivated the
  required-path choice (§2). **No new gate code is authored** — the STAGE uses the gate that is already there.
- **Decoupling was REJECTED.** Adding a separate, gate-free entry to the STAGE would re-introduce a separate-leg
  surface *inside* advance — defeating the point of the required-path placement and re-creating the surface the
  decision sought to avoid. The standing dependency is the accepted price of the inherited gate.

> **Recorded disposition:** the mint-gate standing dependency is ACCEPTED (not silently assumed) — the STAGE is
> guaranteed-every-day *conditional on the daily advance happening*, which the time-laddered bypass already
> guarantees; ZERO new gate code; decoupling rejected.

---

## 6. BOUNTY FOLD (PLACE-02) — NOTED only, NOT decided (349-owned)

The bounty mechanics are **PLACE-02 / 349-owned** — this SPEC only **NOTES** the fold; it does not decide the
mechanics. Recorded so 349 has the steer without re-litigating placement:

- The buy/process bounty **folds into the advance bounty** (`2×·mult`) rather than a flat-per-tx leg. The advance
  bounty's day-epoch stall multiplier is already in `advanceGame` (the `mult` 2×/4×/6× block at `AdvanceModule:226-242`,
  written straight into the `mult` return the router scales) — the process STAGE rides it.
- **Farm-by-splitting** (many minimal chunks each earning the flat advance bounty) is the watch-item; the **`OPEN_KNEE`
  pro-rate** is the in-codebase answer (pay for work done, not per call — the "middle-chunk-unpaid" liveness gap, per
  §5, is the reason to prefer work-scaled over once-per-advance).
- The **open** leg keeps its own separate post-RNG router category (`OPEN_BATCH`-style, `OPEN_KNEE` pro-rate
  unchanged), consistent with §5.

**349 decides the bounty mechanics (PLACE-02); this doc only records the fold direction + the farm-by-splitting watch.**

---

## 7. Anchor coverage vs the plan's must-haves (self-audit)

| Must-have | Where satisfied |
|---|---|
| Placement DECIDED = REQUIRED-PATH, framed as a deliberate USER override | §0 + §1 (the string "required-path") |
| PLAN-V55 §4 + §9 explicitly marked SUPERSEDED on the placement point | §1 (the SUPERSEDED table, §4/§9 referenced) |
| Decision basis = guaranteed-every-day, NOT revert-safety, with proof-made-it-viable rationale | §2 |
| Chunked-STAGE mechanism specified (`subsFullyProcessed` + `_subCursor`, before `rngGate`) citing the re-pinned insertion point + `rngGate :1152` | §3 (insertion `:272-273`, `rngGate :1152`) |
| D-348-02 → `348-FREEZE-PROOF.md` (FREEZE-02) | §4a |
| D-348-04 → `348-INVARIANT-CARRY.md` | §4b |
| Mint-gate standing accepted, ZERO new gate code, citing `_enforceDailyMintGate :973` | §5 |
| Leg chunking specified (process pre-RNG `BUY_BATCH`-style; open post-RNG `OPEN_BATCH`-style, NOT folded) | §3b |
| Bounty fold NOTED (not decided — PLACE-02 is 349-owned) | §6 |
| Zero `contracts/*.sol` edits | §8 |

---

## 8. Attestation

Zero `contracts/*.sol` edits — `git diff --name-only -- contracts/` is empty. Paper-only SPEC decision; the only CLI
used was `git diff` + `grep`/read (read-only). All `file:line` anchors are the RE-PINNED live lines from
`348-GREP-ATTESTATION.md` (the phase's UPSTREAM PRODUCER), not the drifted doc-cited lines. The two carried proof
obligations are bound to their proofs in `348-FREEZE-PROOF.md` (FREEZE-02 / D-348-02) + `348-INVARIANT-CARRY.md`
(D-348-04), which 349 IMPL reads alongside this decision.

**Valid until:** the subject HEAD's `contracts/` moves off `20ca1f79` (re-run `348-GREP-ATTESTATION.md` first if any
`contracts/*.sol` commit lands before 349). As of `f353a50b` the tree is byte-identical to `20ca1f79`.

*Phase: 348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p · Plan: 348-04 · Requirement: PLACE-01.*
