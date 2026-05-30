# Phase 348: SPEC — Design-Lock + Freeze Proof + Discharged-Invariant Carry + §4 Placement Decision + Code-Size/GAS Inventories + Call-Graph Attestation - Context

**Gathered:** 2026-05-30
**Status:** Ready for planning

<domain>
## Phase Boundary

Paper-only SPEC design-lock for the v55 AfKing-in-Game redesign. **ZERO `contracts/*.sol` mutation.**
Owns 5 requirements — **FREEZE-01, FREEZE-02, FREEZE-03, PLACE-01, ARCH-04** — and produces the artifacts that
let 349 IMPL author ONE fully-reconciled, code-size-safe diff with **zero "by construction" assumptions**:

1. **PROVE the FREEZE spine** on paper — freeze-completeness (FREEZE-01), pre-RNG index-binding (FREEZE-02),
   stamped-day determinism (FREEZE-03).
2. **DECIDE the §4 placement** (PLACE-01) — required-path vs separate-legs, on non-revert grounds. **DECIDED:
   required-path** (see D-348-01).
3. **CARRY the discharged REVERT-FREE-CHAIN + EV-cap invariants** as locked SPEC invariants (the proof's §5
   4 obligations — **as amended by D-348-04, the try/catch drop** — + the §7 3 follow-ups).
4. **PRODUCE the code-size reclaim plan** (ARCH-04), measured + sequenced so the Game stays < 24,576 bytes at
   EVERY intermediate step.
5. **PRODUCE the GAS-opportunity inventory** (folds into the SPEC's attestation set; the wins LAND at 350).
6. **CONFIRM the OPEN-E / AFSUB / set-mutation carry-over.**
7. **GREP-ATTEST every cited `file:line` vs the v54 HEAD `20ca1f79`**, correcting drift.
8. **RECONCILE** the GameAfkingModule + storage-append + two-path-open shapes producer-before-consumer into the
   IMPL edit-order map for 349.

The design itself is DESIGN-LOCKED in `PLAN-V55-AFKING-IN-GAME-REDESIGN.md` §10 + the discharged
`PLAN-V55-REVERT-FREE-CHAIN-PROOF.md`; this phase re-attests + proves + inventories + decides placement — it does
NOT re-open the mechanism. The GAS application (gas-skeptic) is 350; the IMPL diff is 349; the in-milestone
adversarial sweep + FINDINGS is 352.

> **No SPEC.md was authored before this discussion** (`spec_loaded = false`). The locked requirements live in
> `.planning/REQUIREMENTS.md`; this phase's SPEC document SET (see D-348-07) becomes the authoring source for 349.

</domain>

<decisions>
## Implementation Decisions

These split into (A) **new decisions from this discussion** and (B) **carried-forward LOCKED design** (restated
because load-bearing — the v55 PLAN docs remain the source of truth for full rationale).

### A. §4 Placement (PLACE-01) — DECIDED

- **⚠ D-348-01 (HEADLINE — diverges from the doc recommendation): REQUIRED-PATH placement.** The process-pass is
  a new **chunked STAGE inserted in `advanceGame` immediately before `rngGate`** (new-day path only), guarded by a
  `subsFullyProcessed` flag + a `_subCursor` draining a per-call gas budget. **This OVERRIDES the doc's §4/§9
  recommendation (separate permissionless legs).** Chosen on **guaranteed-every-day** grounds — NOT forced by
  revert-safety (the REVERT-FREE-CHAIN proof made required-path VIABLE: a funded well-formed sub can't revert →
  can't freeze the day). The SPEC's PLACEMENT-DECISION doc MUST record this as a deliberate USER decision, note
  that PLAN-V55 §4/§9 are **superseded on the placement point**, and capture the resulting proof obligations
  (D-348-02, D-348-04). The **open** stays a normal post-RNG leg (see D-348-05); the buy/process **bounty folds
  into the advance bounty** (`2×·mult`) rather than a flat-per-tx leg — watch farm-by-splitting (`OPEN_KNEE`
  pro-rate is the in-codebase answer). Bounty mechanics are **PLACE-02 / 349-owned** — the SPEC only notes the fold.

- **D-348-02 (FREEZE-02 under required-path): UNIFORM index epoch per day.** Every sub in a day's process STAGE is
  stamped to the **SAME current `LR_INDEX`**, and `requestLootboxRng` (`AdvanceModule:1016`→ index advance `:1629`)
  **CANNOT interleave while `subsFullyProcessed == false`** — the STAGE owns the index until `rngGate` requests its
  word. Matches the original "uniform timing for locking" goal; airtight. **PROOF OBLIGATION (load-bearing, new):**
  the FREEZE-PROOF doc must verify against source whether `requestLootboxRng` is reachable mid-STAGE and SPECIFY the
  guard (block it while `!subsFullyProcessed`, or order the STAGE strictly before any index advance), AND that a
  single sub's processing reads `LR_INDEX` once (doesn't straddle within one sub).

- **D-348-03 (mint-gate standing): INHERIT the gate — no new logic.** The required-path STAGE rides
  `advanceGame`'s existing `_enforceDailyMintGate` (called `AdvanceModule:191`, body `:973`): mint standing OR the
  15–30min time-laddered bypass (which opens to anyone daily). Since the day advances daily regardless, afking
  processing is guaranteed-every-day in practice with ZERO new gate code. The SPEC documents the standing
  dependency as accepted. (Decoupling was rejected — it would re-introduce a separate-leg surface inside advance.)

- **⚠ D-348-04 (CORRECTION to REVERT-02 + proof §5 obligation 4): DROP the try/catch valve.** Prompted by USER
  ("didnt we get rid of try/catch?"). The healthy path is **revert-free BY CONSTRUCTION via obligation 1**
  (preserve the slice-builder validation invariants verbatim) — there is nothing to catch. The two residual revert
  classes are handled WITHOUT a valve: **class B (solvency-violation) FAILS LOUD** (catching it would *mask* a
  catastrophic solvency bug — `claimablePool -= uint128(ev)` underflow means SOLVENCY-01 is already violated);
  **class C (liveness-timeout) is terminal** (game already ≥120-day-dead / heading to game-over) — the SPEC instead
  **verifies the afking STAGE cannot block the game-over routing** (a separate advance path).
  - **This is a REWRITE of a carried invariant.** `REVERT-02` (REQUIREMENTS.md, **349-owned**) and proof §5
    obligation 4 BOTH currently say *"thin per-sub try/catch skip valve."* The SPEC MUST record this correction
    (parallel to how Phase 343 corrected `AUTOBUY-02`→`b.funder` via its D-01). The new form: *"NO valve:
    revert-free-by-construction (obl 1) for the healthy path; fail-loud-on-solvency (class B); terminal-routing-
    unblocked (class C)."*
  - **Consequence — the proof burden CONCENTRATES on obligation 1** (slice-builder fidelity), now the SOLE
    day-can't-brick guarantor under required-path. This is exactly where the rigor (the light `/contract-auditor`
    pass, D-348-06) should sit.
  - **Consequences to reconcile in the SPEC:** (a) §10 process-pass rule (2) *"mint slice fails → SKIP"* becomes a
    **pre-emptive** skip (the slice builder declines to build an unbuildable slice; under obligation 1 there are
    none in a healthy game — PROVE rule (2) is effectively unreachable). (b) §10's *"optional per-cycle eviction
    cap"* loses its revert-driven-mass-eviction rationale — **re-evaluate whether it stays** (note: rule-(1) normal
    eviction of an *unfunded* sub is unaffected).

### A. FREEZE-proof red-team (FREEZE-01)

- **D-348-05 (the live-read window = ACCEPTED-BY-DESIGN known issue).** USER established there is **no credible
  attack vector** on the §10 decision to read score/baseLevel/EV-cap LIVE at open: afking subs are committed
  pass-holders (`validThroughLevel`), there is no on-demand score lever in the ~5-min process→open window (the
  80→135% multiplier is streak-built over many levels), and a legit full-price deity-pass purchase on a good
  pending box is fine/−EV — not an exploit. Aligns with the USER-LOCKED weighting ([[threat-model-reentrancy-mev-nonissues]]:
  RNG-freeze dominant, player can't manipulate VRF input after request). **Disposition:** file the live-read window
  as a **written accepted-by-design known issue** (precedent: 339-01 D-03, the whale-frontrunning-on-VRF-resolution
  non-finding) in the FREEZE-PROOF doc, with the −EV/no-credible-actor rationale, **carried into
  `audit/FINDINGS-v55.0.md` + the v52 cumulative sweep as dispositioned/known.** **NO `/economic-analyst`
  red-team.**
  - **FREEZE-01 splits:** the **stamped fields `(index, amount, day)`** are genuinely frozen + proven (FREEZE-02
    index-binding + FREEZE-03 stamped-day determinism — the real proof work); the **live-read fields
    (score/baseLevel/EV-cap)** are the documented accepted-tradeoff, NOT proven-airtight.
  - **Early-slot DROPPED as a defense.** The "slot the afking open early in the post-RNG chain" idea (USER, then
    set aside) was a window-*tightener*; since the window is now ACCEPTED (not closed), it is **not needed** → the
    afking open stays a normal post-RNG leg, which **resolves the PLACE-02 'protocol-early-sequenced' drift**, and
    the VRF-timing must-verify is dropped.

- **D-348-06 (the ONE adversarial subagent at SPEC): LIGHT `/contract-auditor` pass on obligation-1.** Run
  `/contract-auditor` scoped to obligation-1 (slice-builder fidelity = the no-brick guarantor under no-try/catch) —
  verify the invariants are stated correctly for the fold (`ev = cost − claimableUse` + enum payKind, the 1-wei
  claimable sentinel, the `LOOTBOX_MIN` transient skip, `quantity ≥ 1`). This is a contract-correctness check,
  distinct from the freeze tradeoff (which is self-attested/known-issue). All OTHER adversarial probing is deferred
  to the **352 TERMINAL** in-milestone 3-skill sweep on the real folded code (NOT a paper re-audit of v54).

### A. Code-size + GAS rigor (ARCH-04)

- **D-348-08 (code-size = MEASURE + edit-order arithmetic).** Do NOT trust the doc's figures (218B headroom, the
  per-symbol bytes, ~2.8KB reclaim) — they may be stale vs `20ca1f79`, and 218B is too thin to take on faith.
  `forge build --sizes` the CURRENT Game runtime size + the real headroom vs 24,576 on the live tree; measure each
  EXISTING reclaim target (`claimAffiliateDgnrs`, `playerActivityScore`, `previewSellFarFutureTickets`); ESTIMATE
  the new stub + GameAfkingModule additions (code not written yet); produce an edit-order map with **running-total
  arithmetic proving < 24,576 at EVERY intermediate step** (reclaim FIRST → add stubs → lens/drop-`view` as needed).
  The 349 build is final verification. **CLI `forge build --sizes` / `forge inspect` need no ffi** — the
  `foundry.toml` ffi-off only blocks in-test `vm.ffi` (per the 319-04 note).

- **D-348-09 (GAS inventory = RUN `/gas-scavenger` at SPEC + enumerate).** Mirror Phase 343's D-02: front-load
  `/gas-scavenger` NOW as an **advisory candidate list** (no validation here; 350 runs `/gas-skeptic`) so 349 IMPL
  can build the wins in from the start (more candidates = fewer post-hoc gas diffs). ALSO enumerate the §6 scorecard
  levers (box-ledger→warm-stamp ~120k; `afkingSnapshot`/`afkingFundingOf` staticcall→SLOAD ~3-5k; same-slot
  aggregate flushes) + the **GAS-03 SAFE-WITH-CONDITIONS** list (bucket affiliate by roll-winner; **do NOT batch
  `quests.handleAffiliate`** — non-linear completion logic). GAS-01/02 flagged as **structural to the IMPL
  relocation** (confirmed-measured at 350/351). USER chose front-load DESPITE the dedicated 350 phase.

### B. Carried-forward LOCKED design (PLAN-V55 §10 + proof — DO NOT re-open)

- **§10 canonical design** (supersedes §0–§3): **boons OFF** for afking boxes → box `amount` = spend (deletes the
  boosted-amount freeze field); **score/baseLevel/EV-cap read LIVE at open** (D-348-05 accepted-tradeoff); the stamp
  collapses to **`(index, amount, day)`**; the **free-box guard = the `lastAutoBoughtDay == today` success-marker**
  set atomically AFTER a successful debit (failed buy / mid-cycle subscribe → no marker → no free box); the 3-rule
  process-pass per-sub logic (unfunded → evict-normal / skip-exempt; mint-fail → pre-emptive skip not evict [per
  D-348-04]; success → debit + marker + record cost).
- **Proof §5 obligations (the v55 invariant set), as amended:** (1) preserve `_resolveBuy`'s validation invariants
  VERBATIM (migration fidelity — the load-bearing obligation, now the sole no-brick guarantor); (2) EV-cap at open
  via `_applyEvMultiplierWithCap(player, level+1, amount, mult)` keyed `[player][level+1]`, exactly once per open,
  hard-clamped ≤10 ETH (no revert), with the **buy-time EV write BYPASSED** for afking boxes (no double-draw);
  (3) stamp `(index, amount, day)` + **seed the open with the STAMPED buy-day** (mirror today's frozen
  `lootboxDay`, NEVER open-time `_simulatedDayIndex()`); (4) **~~thin per-sub try/catch skip valve~~ → DROPPED
  (D-348-04)**.
- **REVERT-FREE-CHAIN is DISCHARGED** — v54 is already revert-free on the funded path; v55's job is migration
  fidelity (obligation 1), not re-proving. `mintForGame`/`transferFromPool` are NOT reachable on the buy path.
- **The §7 proof follow-ups (verify at SPEC, low risk):** reconcile AfKing's `mp·effectiveQty` cost units vs the
  Game's `priceForLevel·ticketQuantity/(4·TICKET_SCALE)` (equivalence, so the folded process-pass computes `cost`
  identically); confirm the stamp field widths hold `amount` (full wei) + `index` + `day` (the §8 Sub-record-width
  item — likely 2 slots); confirm the process-pass never routes through `_callTicketPurchase`'s lootbox EV tally
  (the obligation-2 double-draw guard).
- **The §3 freeze/security spine + the OPEN-E/AFSUB/set-mutation carry-over (CONSENT inputs, 349-owned):** the
  subscribe-time `isOperatorApproved` (OPEN-E) gate, the pass-gating (`validThroughLevel`), the VAULT/SDGNRS
  exemption-on-`player`, the funder=src accounting, and the set-mutation invariant ("no cursor advance after
  swap-pop" — the H-CANCEL-SWAP-MISS / [[afking-cancel-tombstone-streak-finding]] class) all carry over verbatim;
  the SPEC re-attests the OPEN-E 4-protection structure.

### Claude's Discretion
- **SPEC deliverable shape — 343's D-08 multi-doc pattern** (this gray area was NOT selected for discussion, so
  carried as the default): a SPEC document SET, not a monolithic `348-SPEC.md` — e.g. `348-FREEZE-PROOF.md` (incl.
  the accepted-by-design known issue), `348-PLACEMENT-DECISION.md` (the required-path divergence + proof
  obligations), `348-GREP-ATTESTATION.md`, `348-CODE-SIZE-PLAN.md`, `348-GAS-INVENTORY.md`,
  `348-IMPL-EDIT-ORDER-MAP.md`, indexed by `348-SPEC-INDEX.md`. Planner may split/merge filenames, but keep the
  concerns discrete + hand-off-able (precedent: 343 + v50/334).
- Whether the light `/contract-auditor` obligation-1 pass (D-348-06) records its result inline in a SPEC doc or a
  scratch attestation — planner's call.
- The downstream plan posture: **skip research, plan directly** off the v55 PLAN docs + this CONTEXT
  ([[feedback_skip_research_test_phases]] — this is a fully-specced internal refactor with a discharged proof;
  precedent 344's D-344-04). The planner may confirm.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### v55 design source-of-truth (read FIRST)
- `.planning/PLAN-V55-AFKING-IN-GAME-REDESIGN.md` — the DESIGN-LOCKED source. **§10 is canonical** (supersedes the
  §0–§3 stamp framing). **NOTE: §4/§9 placement recommendation (separate-legs) is SUPERSEDED by D-348-01
  (required-path); §10's try/catch / process-rule-(2) is amended by D-348-04 (no valve).**
- `.planning/PLAN-V55-REVERT-FREE-CHAIN-PROOF.md` — the discharged proof. **§5 = the 4 LOCKED obligations** (obl 4
  try/catch is DROPPED by D-348-04); **§7 = the 3 SPEC follow-ups** (cost-units / stamp widths / double-draw guard);
  §3 = the slice-builder discharge (obligation 1 substrate); §4 = the EV-cap-at-open + open-determinism derivation.
- `.planning/REQUIREMENTS.md` — the 29 v55.0 REQ-IDs (348 owns FREEZE-01/02/03, PLACE-01, ARCH-04). **NOTE:
  `REVERT-02` (349-owned) is corrected by D-348-04 — drop the try/catch valve.**
- `.planning/ROADMAP.md` §"Phase 348" — goal + 5 success criteria + the cross-cutting re-attest-vs-`20ca1f79` rule.

### SPEC-phase precedent (deliverable shape, red-team, gas-scavenger-at-SPEC, attestation discipline)
- `.planning/phases/343-spec-design-lock-solvency-proof-dead-code-gas-inventories-ca/` — the directly-analogous SPEC
  phase: `343-SPEC-INDEX.md` + the multi-doc set (D-08), the front-loaded proof red-team (D-07), gas-scavenger at
  SPEC (D-02), the GREP-ATTESTATION drift-correction discipline, and the D-01 requirement-correction precedent that
  D-348-01/D-348-04 mirror.
- `.planning/milestones/v50.0-phases/334-.../` — `334-*-FREEZE-PROOF.md` + `334-GREP-ATTESTATION.md` +
  `334-IMPL-EDIT-ORDER-MAP.md` (the freeze-proof + multi-doc precedent).

### Contract anchors (grep-verify ALL vs `20ca1f79`; the live tree is byte-identical to it — 4 docs-only commits since)
- `contracts/modules/DegenerusGameLootboxModule.sol` — `_applyEvMultiplierWithCap` **`:459`** (doc :459-495, MATCH);
  the frozen buy-day read `lootboxDay[index][player]` **`:514`**; the open-time `_simulatedDayIndex()` **`:513/:766/
  :799/:836/:868`** (the day the afking open must NOT copy — FREEZE-03); **⚠ the box seed the doc cites as `:534`
  did NOT grep as `keccak256(abi.encodePacked` — RE-PIN the actual seed-construction site (concrete drift instance).**
- `contracts/storage/DegenerusGameStorage.sol` — `lootboxEvBenefitUsedByLevel` **`:1469`** (doc :1468-1469);
  `LOOTBOX_EV_BENEFIT_CAP = 10 ether` **`:1326`** (MATCH).
- `contracts/AfKing.sol` — `_resolveBuy` **`:727`** (MATCH, body to `:795`); the named-revert comment **`:781-782`**
  (the 1-wei sentinel / claimable-shortfall avoidance); the `LOOTBOX_MIN` transient skip **`:772`**; `LOOTBOX_MIN`
  decl `:269`; OPEN-E `isOperatorApproved` interface `:43`; `validThroughLevel` `:103`; `fundingSource` `:106` (re-pin
  the subscribe-time OPEN-E gate the docs cite `:400-409` + `src` resolution `:682`).
- `contracts/modules/DegenerusGameAdvanceModule.sol` — `_enforceDailyMintGate` **`:973`** (MATCH), called `:191`;
  `requestLootboxRng` **`:1016`** (MATCH); the RNG-request index advance `_lrRead(...)+1` **`:1089` + `:1629`** (doc
  :1086-1090 / :1626-1630, MATCH); `rngGate` `:1152`; the STAGE insertion point (~`:273`, before `rngGate` `:274`).
- The reclaim targets for ARCH-04 measurement: `claimAffiliateDgnrs` (→ `BingoModule`), `playerActivityScore`,
  `previewSellFarFutureTickets` (sizes re-measured per D-348-08).

### Related memory (audit posture / dispositions)
- [[threat-model-reentrancy-mev-nonissues]] — the USER-LOCKED weighting (RNG-freeze dominant; player can't
  manipulate VRF input after request) — the basis for D-348-05 (no real freeze vector).
- [[v55-afking-revert-free-proof]] — the v55 active-state record (proof discharged; EV-cap-at-open; stamp shape).
- [[afking-cancel-tombstone-streak-finding]] + [[open-e-operator-approval-trust-boundary]] — the set-mutation +
  OPEN-E carry-over (CONSENT, 349).
- [[v45-vrf-freeze-invariant]] — the freeze north-star (every VRF-interacting variable frozen request→unlock).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`_applyEvMultiplierWithCap` (`LootboxModule:459`)** — the read+write-at-open EV-cap shape
  `resolveLootboxDirect`/`resolveRedemptionLootbox` already use; the afking open routes through it (obligation 2),
  keyed on the SAME `lootboxEvBenefitUsedByLevel[player][level+1]` map MintModule writes at buy.
- **The frozen `lootboxDay[index][player]` seed (`LootboxModule:514`)** — the template for the stamped-day open
  (FREEZE-03); the afking open mirrors it, NOT the open-time `_simulatedDayIndex()`.
- **`_resolveBuy` (`AfKing:727-795`)** — the slice builder whose validation invariants fold into the process-pass
  VERBATIM (obligation 1); its `:781-782` comment names the exact Game reverts it avoids — the substrate the light
  `/contract-auditor` pass (D-348-06) verifies survives the fold.
- **The `advanceGame` STAGE machinery** (`AdvanceModule`, `_enforceDailyMintGate:973`, `rngGate:1152`,
  `requestLootboxRng:1016`) — the host for the required-path process STAGE (D-348-01/02/03).
- **343's multi-doc SPEC set** — the directly-reusable deliverable template (D-08 → Claude's Discretion).

### Established Patterns
- **Accepted-by-design known-issue disposition** (339-01 D-03) — the exact shape for the live-read freeze tradeoff
  (D-348-05): a written non-finding so the deferred/in-milestone sweep treats it as dispositioned.
- **gas-scavenger-at-SPEC → gas-skeptic-at-GAS** (343 D-02 → 345; here 348 D-348-09 → 350) — advisory candidate list
  at SPEC, validation at the dedicated GAS phase.
- **Requirement-correction-recorded-in-SPEC** (343 D-01: `AUTOBUY-02`→`b.funder`) — the precedent for D-348-04
  rewriting `REVERT-02` + proof §5 obl 4.
- **The audit-discipline maxim** — "no 'by construction' / 'single fn reaches all paths' survives un-checked"
  ([[feedback_verify_call_graph_against_source]]); the GREP-ATTESTATION re-pins every anchor (the box-seed `:534`
  drift is the first concrete instance).

### Integration Points
- **Producer-before-consumer edit-order (the IMPL-EDIT-ORDER-MAP deliverable, for 349):** code-size reclaim FIRST
  (`claimAffiliateDgnrs`→`BingoModule` + read-aggregators) → `DegenerusGameStorage` append (subscriber set +
  process/open cursors + per-sub `(index,amount,day)` stamp + `lastAutoBoughtDay`/`lastOpenedIndex` + the v54
  `afkingFunding` ledger) → `GameAfkingModule` (subscribe/setters + the required-path process STAGE + the open-pass
  + the router) → `AdvanceModule` STAGE insertion (before `rngGate`, the `subsFullyProcessed`/`_subCursor` guard +
  the `requestLootboxRng` no-interleave guard) → interfaces → `AfKing.sol` thin dispatch stubs.
- **Verified:** `git diff --numstat 20ca1f79 HEAD -- contracts/` → EMPTY (4 docs-only commits since). The live tree
  IS the v55 baseline → the GREP-ATTESTATION greps it directly; no SHA checkout needed.

</code_context>

<specifics>
## Specific Ideas

- **The required-path divergence is the headline.** PLAN-V55 §4/§9 *recommend* separate-legs; the USER chose
  required-path on guaranteed-every-day grounds. The SPEC must record this as a deliberate override (not a
  contradiction to silently reconcile), document the superseded recommendation, and carry the two proof obligations
  it creates (the uniform-epoch no-interleave guard D-348-02; obligation-1-as-sole-no-brick-guarantor D-348-04).
- **No try/catch — fail loud on solvency.** The single sharpest IMPL-discipline point: the funded STAGE is
  revert-free by construction (obligation 1); a class-B (solvency) revert must propagate, never be swallowed
  (swallowing masks a SOLVENCY-01 violation). Class C is terminal — verify the game-over routing isn't STAGE-blocked.
- **The freeze story is stronger than the doc's −EV hand-wave.** The live-read window is an accepted-by-design known
  issue with a no-credible-actor rationale (committed pass-holders, no on-demand score lever, legit-purchase-fine) —
  documented, not defended or red-teamed.

</specifics>

<deferred>
## Deferred Ideas

- **Early-slot post-RNG window-closure** — proposed by USER, then dropped (the window is ACCEPTED as a known issue,
  not closed; D-348-05). Recorded so it isn't re-raised.
- All of the following are **downstream v55 phases, NOT scope creep into 348:** the `/gas-skeptic` validation +
  application of the gas-scavenger candidates → **350**; the IMPL diff (the fold + box redesign) → **349**; the
  empirical proofs (TST-01..06) → **351**; the in-milestone 3-skill adversarial sweep + `audit/FINDINGS-v55.0.md` +
  the closure flip → **352**.
- Generalized operator-spend of `claimableWinnings` + a bingo/afking progress view helper → out of v55 (REQUIREMENTS
  "Future Requirements").

None of the above are scope creep into 348 — the discussion stayed within the SPEC's paper-only boundary.

</deferred>

---

*Phase: 348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p*
*Context gathered: 2026-05-30*
