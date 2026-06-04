# Phase 357: TERMINAL — Delta Audit + 3-Skill Genuine-PARALLEL Adversarial Sweep (AUGMENTED by XMODEL Codex + Gemini close) + FINDINGS-v56.0 + Closure Flip - Context

**Gathered:** 2026-06-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Close the v56.0 milestone (AfKing Everyday-Gas Minimization) via a FULL in-milestone close
(NOT deferred to v52 — like v54.0/v55.0, unlike v50.0/v51.0). One formal requirement,
**AUDIT-01**, but it spans five deliverables:

1. **Delta-audit** — every changed v56 surface NON-WIDENING vs the v55 baseline `453f8073` with
   zero orphan hunks; SOLVENCY-01 byte-unchanged (ETH/`claimablePool` debit untouched) + RNG-freeze
   intact + the affiliate flat-7% deterministic-split-PULL non-gameability (NO roll/seed/flush,
   buyer-never-wins) + the open-end two-path/no-double-open + the shared-`DegenerusQuests`-core
   non-perturbation re-attested.
2. **3-skill genuine-PARALLEL adversarial sweep** — `/contract-auditor` + `/economic-analyst` +
   `/zero-day-hunter` run as concurrent background Task spawns from the orchestrator;
   `/degen-skeptic` = the dual-gate filter (D-271-ADVERSARIAL-02), NOT a probing skill. Charge:
   the strategic sub/unsub edge (PRIMARY), settle-timing non-exploitability (trivial — no seed),
   pre-credit-EV inflation, the two-path open.
3. **XMODEL-01 cross-model close** — Codex + Gemini fed crafted prompts on the FULL afking system
   (buy STAGE/accrual/settle AND open-pass/materialize), AUGMENTING the Claude sweep.
4. **`audit/FINDINGS-v56.0.md`** — the 9-section report (chmod 444), folding the delta-audit + the
   adversarial disposition + the finding ledger.
5. **The atomic 5-doc closure flip** — ROADMAP + STATE + MILESTONES + PROJECT + REQUIREMENTS, the
   `MILESTONE_V56_AT_HEAD_<sha>` closure signal, re-attest the full v56.0 requirement set.

**Posture — this is NOT the standard DOC-ONLY frozen-subject TERMINAL.** v56 breaks the prior
"zero contract mutation + 0 findings" mold by USER decision: the leading **357-00 contract gate**
bundles THREE contract changes (the F-356-01 `drainAffiliateBase` stub + two USER-directed afking
sub-hardening gates — see D-11/D-12), so 357 has TWO `autonomous:false` gates (357-00 contract gate
+ the closure gate) — not one. The hardening also requires TEST reconciliation (the new subscribe
reverts will turn some passless/unfunded-subscribe fixtures red — legitimate behavior-supersession
drops handled like 356-07's expanded-mandate drops — plus new positive proofs). This is the 5th
repetition of the v44→v55 TERMINAL pattern; the sweep/delta/FINDINGS/flip mechanics are
precedent-locked (the v56-specific judgment is in `<decisions>`), but the leading hardening+fix gate
is new this milestone.

**Scope note — USER-directed mid-discuss (2026-06-02):** two afking sub-hardening gates were added
to v56 scope (the milestone's SEC-01 strategic-sub/unsub spine). Together they make *every active
afking sub a pass-holder grounded on a real purchase* → the `5cb707f2` advance-gate bypass becomes
provably sound and the passless/unfunded free-rider + cap-occupancy vectors close.

</domain>

<decisions>
## Implementation Decisions

> **USER answered all four open gray areas (2026-06-02).** The precedent-locked TERMINAL mechanics
> (genuine-PARALLEL topology, dual-gate, FINDINGS 9-section/chmod-444, atomic 5-doc flip,
> autonomous:false closure gate) are NOT re-decided — they mirror Phase 352 (v55) verbatim. The
> decisions below capture what is v56-specific.

### 357-00 contract gate — FIX-FIRST + hardening, audit the fixed subject (D-01)
- **D-01:** The 357-00 contract gate bundles THREE changes at ONE `autonomous:false` USER-approved
  boundary, applied + `forge build` clean + HELD for explicit USER hand-review (pre-commit hook moved
  aside + `CONTRACTS_COMMIT_APPROVED=1`), BEFORE the delta-audit/sweep run:
  1. **F-356-01 fix** — the ONE-line `drainAffiliateBase` dispatch stub in `DegenerusGame.sol`,
     mirroring the working `claimAfkingBurnie` stub at `DegenerusGame.sol:413`:
     `drainAffiliateBase(address sub) external returns (uint256)` →
     `delegatecall(IGameAfkingModule.drainAffiliateBase.selector, ...)`, `_revertDelegate` on failure,
     return the decoded `base`. Module impl (`GameAfkingModule.sol:1300`), interface
     (`IDegenerusGameModules.sol:503` / `DegenerusAffiliate.sol:58`), and `level()` are ALL already
     correct — the stub is the only gap.
  2. **Pass-required subscribe (D-11).**
  3. **Purchase-grounded subscribe (D-12).**
- **Sequence:** 357-00 (the bundled gate) → re-run + reconcile the NON-WIDENING gate at the post-fix
  HEAD' (D-14) → re-freeze the audit subject at HEAD' → 357-01 delta-audit ∥ 357-02 sweep @ HEAD'
  (the three changes are IN audit scope; the sweep probes the new stub's `claim` CEI + the hardened
  gates + the now-sound `5cb707f2` bypass) → 357-03 FINDINGS-v56.0 (§4 records F-356-01 as
  RESOLVED-AT-357 — the fix + the post-fix re-verification, NOT a carried finding) → 357-04 closure.
- **Net effect:** the closure HEAD = the actually-shippable, hardened subject (audited == shipped) —
  the cleanest reconciliation vs auditing the broken/unhardened subject and fixing after.

### Afking sub-hardening — USER-directed mid-357-discuss 2026-06-02 (D-11/D-12/D-13)
- **D-11 (pass-required subscribe):** `subscribe()` REVERTS (a new `NoPass`-style error) on the UPSERT
  branch (`dailyQuantity >= 1`) unless `_passHorizonOf(subscriber) >= currentLevel` (deity sentinel
  `type(uint24).max` always covers); the cancel/unsub branch (`dailyQuantity == 0`, returns at `:328`)
  is NOT gated. This replaces the soft create-then-evict behavior (a passless sub could be created with
  `validThroughLevel = 0` and was only evicted on the first process pass `:942`) with a hard
  subscribe-time gate → a passless/expired-pass sub can never be created (the cap-occupancy + free-rider
  vectors close). The per-iter crossing eviction (`:942`) is KEPT — a pass valid at subscribe can be
  outgrown as levels advance.
- **D-12 (purchase-grounded subscribe):** `subscribe()` (UPSERT branch) REVERTS (a new
  `MustPurchaseToBeginAfking`-style error) unless the subscriber is grounded on a real purchase —
  EITHER already purchased today OR the in-tx cover-buy is funded and executes. This kills the existing
  unfunded-forfeit path for players (`GameAfkingModule.sol:455-457` `_setStreakBase(s, 0)` on unfunded,
  which today silently starts an inert run instead of reverting). The grounding leverages the existing
  cover-buy block (`:362-460`): the NEW-run `done[0]` (manual slot-0 today) / funded `_deliverAfkingBuy`
  paths ARE grounded; the unfunded branch becomes the revert. **The exact "purchased today" predicate is
  an IMPL decision** — candidate signals: manual ETH mint today (`mintPacked_` DAY_SHIFT == today),
  manual slot-0 `done[0]`, afking `lastAutoBoughtDay == today`, or a pending-unopened-box
  (`lastOpenedDay < lastAutoBoughtDay`) — and it MUST NOT revert genuinely-grounded re-subscribes
  (already-bought-today / pending-box states). The `5cb707f2` advance-gate bypass (`AdvanceModule:1124`,
  active sub `dailyQuantity != 0`) is LEFT AS-IS — it is now provably backed by a real buy, so the
  bypass is sound (no free-rider can be an "active sub").
- **D-13 (protocol-sub exemption — load-bearing for bootstrap; USER-confirmed):** the TWO protocol
  self-subscribers — `DegenerusVault` (`:483`) + `StakedDegenerusStonk` (`:388`), which self-subscribe
  with no pass and unfunded at construction — are EXEMPT from BOTH new gates (D-11 + D-12). USER
  explicitly confirmed the must-buy-today exemption (2026-06-02); the pass exemption stands identically
  (they hold no pass → requiring one breaks their construction-time self-subscribe). Exempt set =
  `{ContractAddresses.VAULT, ContractAddresses.SDGNRS}` hardcoded — naive gating WITHOUT this exemption
  reverts the VAULT/sDGNRS self-subscriptions and breaks deploy/bootstrap (the existing `:413-414` /
  `:455-457` comments document exactly this no-revert constraint).

### Push posture at close — CLOSE-THEN-PROMPT-TO-PUSH (D-02)
- **D-02:** v56 DIVERGES from every prior milestone's "NOTHING pushed at close" rule because the v56
  contract subject is **ALREADY PUBLIC** on `origin/main` (354 `e18af451` + the 355 GAS diff are
  pushed) — so the *broken* affiliate-claim contract is currently live. Plus there is an **unpushed**
  8-line contract change going into close: `5cb707f2 feat(advance): active AfKing sub bypasses
  mustMintToday with no time delay` (DegenerusGameAdvanceModule). Posture:
  - Apply the closure flip **locally** — nothing is auto-pushed.
  - At the `autonomous:false` closure gate, **explicitly surface that the live public contract is
    broken until pushed**, and **offer to push** the bundle (the F-356-01 fix commit + `5cb707f2` +
    the closure flip) — but WAIT for the USER's explicit GO before any push.
  - Pushing is outward-facing/publishing → it stays a deliberate, explicitly-authorized step; it does
    NOT happen as a side effect of closing.

### XMODEL Codex + Gemini close — BEST-EFFORT AUGMENTATION (D-03)
- **D-03:** The Claude 3-skill genuine-PARALLEL sweep is the **PRIMARY gate**. The Codex + Gemini
  cross-model close (fed crafted prompts on the FULL afking buy+open system + the F-356-01 fix
  surface) **augments** it — its dispositions fold into the adversarial log — but a CLI being
  unavailable does NOT block closure (record it as attempted/partial). This matches XMODEL-01's
  "augment the TERMINAL adversarial close" wording; the cross-model close is additive assurance, not
  a hard dependency on external tooling.

### 5cb707f2 advance-gate change — IN-SCOPE v56 SURFACE, re-attest unmanipulable (D-04)
- **D-04:** The unpushed `5cb707f2` (the active-AfKing-sub `mustMintToday` bypass with no time
  predicate, `DegenerusGameAdvanceModule._enforceDailyMintGate:1124`) is treated as a v56 contract
  surface:
  - **Delta-audit** attributes the 8-line hunk as a v56 work item (already folded into the NON-WIDENING
    ledger via the 356-07 HEAD reconciliation, commit `d6badcb3`).
  - **The sweep is charged** to re-verify the advance-gate change is unmanipulable. **POST-HARDENING the
    sweep re-attests it is now SOUND:** the D-11/D-12 gates guarantee every active sub is a pass-holding,
    purchase-grounded participant, so the `:1124` bypass ("the daily auto-buy IS participation") is no
    longer claimable by an unfunded free-rider. The sweep confirms the bypass gives no advance-timing /
    daily-mint-gate edge given the hardened sub invariant (and that the protocol-sub exemption D-13
    doesn't reopen one for VAULT/sDGNRS, which can advance via their own existing paths).

### NON-WIDENING re-run + test reconciliation + new proofs (D-14)
- **D-14:** After 357-00, re-run `forge test` at HEAD' and reconcile `test/REGRESSION-BASELINE-v56.md`:
  - The F-356-01 stub can only turn a currently-reverting affiliate-`claim` assertion GREEN or be
    regression-neutral (NON-WIDENING HOLDS or NARROWS).
  - The D-11/D-12 reverts WILL turn some currently-green fixtures RED (tests that subscribe passless or
    unfunded EOAs) — these are LEGITIMATE behavior-supersession reds (the hardened v56 diff intentionally
    supersedes them), reconciled exactly like the 356-07 expanded-mandate drops: `vm.skip`-with-reason
    DROP + re-prove the new behavior GREEN via positive proofs. This means 357-00 is NOT a pure
    "contract gate + re-run" — it also authors NEW positive proofs (pass-required revert fires for a
    passless EOA; grounding revert fires for an unfunded EOA; VAULT/sDGNRS exempt still subscribe;
    deity bypasses; a pass covering currentLevel passes; the crossing eviction still evicts an outgrown
    pass) — folded into the V56Sec* suites or a new V56SubHardening suite. The post-reconcile ledger
    must still satisfy `live − union == ∅` (NON-WIDENING) before the subject re-freezes at HEAD'.

### Claude's Discretion
- **Plan shape (D-05):** mirror the Phase 352 (v55) structure with a LEADING contract gate —
  `357-00 CONTRACT GATE` (the bundled F-356-01 stub + D-11 pass-gate + D-12 grounding, `autonomous:false`;
  then the D-14 NON-WIDENING re-run + test reconciliation + new positive proofs; re-freeze HEAD') →
  `357-01 DELTA-AUDIT` ∥ `357-02 ADVERSARIAL-SWEEP` (parallel wave, both READ-ONLY @ HEAD', the sweep
  is genuine-PARALLEL 3-skill + best-effort XMODEL) → `357-03 FINDINGS-v56.0.md` (consumes 01+02;
  F-356-01 = RESOLVED) → `357-04 CLOSURE-FLIP` (`autonomous:false`, LAST, then the close-then-prompt-
  to-push offer). The planner finalizes wave grouping (357-00 may itself split into a contract sub-plan
  + a test-reconciliation sub-plan).
- **Sweep topology (D-06, precedent-locked, restated):** genuine **PARALLEL_SUBAGENT**, run INLINE in
  the orchestrator context (which holds the Task tool) so all 3 skills launch as concurrent background
  spawns — NOT nested inside a `gsd-executor` (which lacks Task → forces the SEQUENTIAL fallback). The
  hard-won 314/324/328/333/352 lesson. Each subagent probes the FROZEN subject via `git show <HEAD'>:
  contracts/...` (never from memory), READ-ONLY, every cited `file:line` re-grep-verified at HEAD'.
- **Verdict target (D-07):** working target is the v55-style clean closure (the ONLY new finding is
  F-356-01, which is RESOLVED in-phase, not deferred); the O1/QST-05 lootbox-quest double-credit was
  already adjudicated + fixed at IMPL (356-05 proved single-credit) → record as RESOLVED, not a finding.
  The `0 NEW (additional) FINDINGS` clause is amended only by a FINDING_CANDIDATE that survives the
  dual-gate; a survivor is surfaced to the USER closure gate (DEFER→v57 with fix design / FIX-as-new-
  phase / ACCEPT_AS_DOCUMENTED), the terminal never silently halt-and-fixes beyond the locked F-356-01.
- **Sweep charge for the hardening (D-08b):** the sweep additionally probes the D-11/D-12 gates — the
  pass-gate can't be forged/flash-bypassed (subscribe reads the live horizon; the crossing re-reads),
  the grounding can't be faked (the immediate buy must be real funded delivery), the D-13 protocol-sub
  exemption can't be abused (only the two hardcoded addresses), and the passless cap-occupancy +
  unfunded free-rider vectors are CONFIRMED CLOSED (subscribe now reverts both) — this materially
  strengthens the SEC-01 strategic-sub/unsub story the milestone is built on.
- **Requirement re-attestation (D-08):** re-attest the **actual current v56.0 requirement set**
  (`.planning/REQUIREMENTS.md` is authoritative — it has expanded beyond the original 24 to include
  GAS-05, LIVE-01, GAS-06; cite the table, do NOT hardcode "24"). All are Complete except AUDIT-01.
- **Worktrees / execution (D-09):** sequential-on-main, NO worktrees (submodule + node_modules
  constraint; `use_worktrees: false`). The only contract write is the 357-00 one-line stub; the rest
  writes `.planning/` + `audit/` docs. The closure flip must be atomic on main.
- **FINDINGS §-structure (D-10):** mirror `audit/FINDINGS-v55.0.md` (the 9-section layout + §9a verdict
  + §9b/§9c closure-signal propagation + chmod 444) as the structural template.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Scope + requirements + roadmap (the closure bar)
- `.planning/ROADMAP.md` — Phase 357 goal + the 3 Success Criteria (the sweep charge, the NON-WIDENING
  bar, the FINDINGS §-shape, the closure-flip gate) + the v56.0 Coverage tables + the FULL-CLOSE
  audit-posture note.
- `.planning/REQUIREMENTS.md` — AUDIT-01 exact wording (`:57`) + the AUTHORITATIVE requirement status
  table (the rows to flip at closure — the expanded set incl. GAS-05/LIVE-01/GAS-06, NOT a hardcoded 24).
- `.planning/PROJECT.md` — the v56.0 milestone section (work items, locked design decisions,
  out-of-scope list) — the closure flip moves "Current Milestone" → "Completed".

### The carried finding to fix (F-356-01 — the 357-00 contract gate)
- Memory topic `[[v56-affiliate-drain-missing-game-stub-bug]]` — the exact one-line fix spec (mirror
  `claimAfkingBurnie:413`), the source-confirmed reachability, the severity/disposition.
- `.planning/STATE.md` §"v56 CARRIED FINDING" — the must-fix record.
- `test/REGRESSION-BASELINE-v56.md` carried-findings — the ledger surfacing.

### The frozen subject — source (read from `contracts/` at HEAD'; FROZEN at the post-fix HEAD)
- `contracts/DegenerusGame.sol` — the `drainAffiliateBase` stub to ADD (mirror `claimAfkingBurnie:413`);
  `receive():2959`, no `fallback()`.
- `contracts/modules/GameAfkingModule.sol` — **the D-11/D-12 hardening sites:** `subscribe():255` (the
  UPSERT branch `:331+`, the cover-buy block `:362-460`, the existing unfunded-forfeit `:455-457`, the
  pass-horizon write `:350`), `_passHorizonOf():482` (the pass read — deity sentinel / `frozenUntilLevel`),
  the per-iter crossing eviction `:942`, `_addToSet():502` (the cap-occupancy path), the cancel branch
  `:311-328` (NOT gated). Plus the mode-agnostic accrue/settle STAGE, `_settleQuest` + `pendingBurnie`,
  `claimQuest`/`drainAffiliateBase:1300`, the open path, the ticket-mode minimal-write primitive.
- `contracts/DegenerusVault.sol:483` + `contracts/StakedDegenerusStonk.sol:388` — the TWO protocol
  self-subscribers (D-13 exempt set); `subscribe(address(this), true, false, 1, …)` with no pass,
  unfunded at construction.
- `contracts/DegenerusAffiliate.sol` — the flat-7% deterministic-split PULL: `claim(subs[])` 75/20/5
  (`:579` buyer-never-wins), the per-sub drain loop (`:654`), `withdraw()` CEI, `pendingClaim`.
- `contracts/modules/DegenerusGameAdvanceModule.sol` — `_enforceDailyMintGate():1084` + the `5cb707f2`
  active-sub bypass at `:1124` (D-04; now provably-backed post-hardening) + the gap/jackpot decouple
  (GAS-06) + the `openBoxes` valve (LIVE-01).
- `contracts/libraries/BitPackingLib.sol` — `HAS_DEITY_PASS_SHIFT`, `FROZEN_UNTIL_LEVEL_SHIFT`,
  `DAY_SHIFT`, `MASK_24/32` (the pass-horizon + last-mint-day fields the gates read).
- `contracts/DegenerusQuests.sol` — the shared batched-settle entrypoint (`settleAfkingQuest`),
  `handlePurchase:815`, the O1/QST-05 double-credit site (proven single-credit at 356-05).
- `contracts/storage/DegenerusGameStorage.sol` — the re-packed `Sub` slot accumulator
  (`affiliateBase`/`questProgress`/`pendingBurnie`/`hasEverSubscribed`/`validThroughLevel`).
- Reach the frozen subject via `git show <HEAD'>:contracts/...` — re-grep every cited `file:line`.

### The regression ledger (the NON-WIDENING gate — AUTHORITATIVE)
- `test/REGRESSION-BASELINE-v56.md` (449 lines) — live v56 624/134/30 == the empirical `453f8073`
  baseline union BY NAME (`live − union == ∅` AND `union − live == ∅`), the D-10 offset migration,
  the SOLVENCY-01 leg-1 byte-diff anchor (GameAfkingModule `709-710 ↔ 663-664`), the 14 migration-
  unmasked v56-behavior drops, the HEAD reconciliation incl. `5cb707f2`. **Re-run + update after the
  F-356-01 fix.**

### The TERMINAL pattern to mirror (the v55 template — the 5th repetition)
- `audit/FINDINGS-v55.0.md` — the 9-section layout + §9a verdict + §9b/§9c closure-signal propagation
  + chmod 444 (the structural template for FINDINGS-v56.0.md). (Also `audit/FINDINGS-v49.0.md` /
  `FINDINGS-v48.0.md` as additional references.)
- `.planning/milestones/v55.0-phases/352-terminal-delta-audit-3-skill-genuine-parallel-adversarial-sw/`
  — `352-01-DELTA-AUDIT.md` (the delta shape), `352-02-ADVERSARIAL-LOG.md` (§A charge / §B raw
  per-skill / §C disposition table / §D dual-gate attestation + the genuine-PARALLEL topology note),
  `352-04-PLAN.md` (the closure-flip plan: SHA orchestration, autonomous:false gate, threat model).
- `.planning/milestones/v49.0-phases/333-.../333-CONTEXT.md` — the precedent decision-set the v56
  judgment extends (the prior "USER delegated to Claude's judgment" TERMINAL baseline).
- `.planning/MILESTONES.md` — the archive target the closure flip appends to.

### The audit skills (reusable, persona-fidelity preserved)
- `~/.claude/skills/contract-auditor`, `~/.claude/skills/economic-analyst`,
  `~/.claude/skills/zero-day-hunter` — the 3 genuine-PARALLEL sweep skills.
- `~/.claude/skills/degen-skeptic` — the dual-gate FILTER (D-271-ADVERSARIAL-02), OUT as a probing skill.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- The Phase 352 (v55) TERMINAL plan/log/FINDINGS set — the directly-reusable structural templates for
  every 357 deliverable (5th repetition of the same shape).
- `git show <sha>:contracts/...` — the read-only frozen-subject access the sweep + delta use.
- The working `claimAfkingBurnie` stub (`DegenerusGame.sol:413`) — the EXACT template for the F-356-01
  `drainAffiliateBase` one-line fix (same dispatch shape, sibling selector).
- **The existing subscribe cover-buy block (`GameAfkingModule.sol:362-460`)** — the D-12 grounding
  reuses it: the funded `_deliverAfkingBuy` / manual-`done[0]` paths already define "grounded"; only the
  unfunded-forfeit leg (`:455-457`) flips to the revert. `_passHorizonOf:482` is the D-11 pass read.
- **The protocol-sub exemption pattern** — the two hardcoded self-subscribers (`ContractAddresses.VAULT`
  / `SDGNRS`) are the only addresses that bypass the D-11/D-12 gates (D-13).
- `test/REGRESSION-BASELINE-v56.md` — the authoritative NON-WIDENING ledger to re-run + reconcile post-
  357-00 (D-14: F-356-01 narrows; the D-11/D-12 supersession reds are `vm.skip`-dropped + re-proven).

### Established Patterns
- Adversarial-log structure: §A CHARGE + §B raw per-skill + §C per-probe disposition table + §D
  dual-gate Skeptic-Reviewer Filter Attestation (the 320/324/328/333/352 shape).
- Closure-flip pattern: single autonomous:false USER gate → resolve placeholder SHA → atomic 5-doc
  flip in one pass → chmod 444 → grep zero unresolved `MILESTONE_V56_AT_HEAD_<sha>` placeholders.
- NON-WIDENING = strict failing-NAME-set equality vs the `453f8073` union (not a count); file-path
  churn (renames/migrations) is attributable via the ledger, not a regression.

### Integration Points
- **357-00 is the ONLY contract write** — the one-line `DegenerusGame.sol` stub, at the autonomous:false
  gate; everything after re-freezes at HEAD' and is READ-ONLY against `contracts/`.
- The sweep + delta READ the frozen subject @ HEAD'; they WRITE only `.planning/` logs +
  `audit/FINDINGS-v56.0.md`.
- The closure flip WRITES the 5 docs (ROADMAP/STATE/MILESTONES/PROJECT/REQUIREMENTS) + chmod-444s the
  findings; `.planning/` is gitignored → force-add; the closure commit has NO `.sol` (the 357-00 fix
  commit is the sole `.sol` commit, gated separately). The pre-commit hook is moved aside for 357-00 only.

</code_context>

<specifics>
## Specific Ideas

- **This TERMINAL has TWO `autonomous:false` gates** (the 357-00 contract gate + the 357-04 closure
  gate), unlike every prior TERMINAL's single closure gate — because USER chose fix-first + the
  hardening folds into the same gate (D-01).
- **The 357-00 gate is THREE contract changes, not one** (F-356-01 stub + D-11 pass-gate + D-12
  grounding) + test reconciliation (D-14) — bigger than any prior TERMINAL's contract footprint (which
  was zero). The hardening was USER-directed mid-discuss and lands in v56 because it IS the SEC-01
  strategic-sub/unsub spine.
- **The live public contract is currently broken** (affiliate rewards unreachable) — the close-then-
  prompt-to-push posture (D-02) makes surfacing this + offering the push a mandatory closure-gate item.
- **F-356-01 is the ONE in-phase finding, RESOLVED** — not the v55-style "0 NEW_FINDINGS"; the sweep is
  still a genuine hunt ready to surface more (any survivor → USER closure gate, default DEFER→v57).
- **The hardening CLOSES two concrete vectors I surfaced from the source:** (1) passless subs occupying
  `SUBSCRIBER_CAP` slots between subscribe and the first-process-pass eviction (D-11 now reverts them at
  subscribe), and (2) unfunded "active subs" claiming the `5cb707f2` advance-gate bypass with no real
  buy (D-12 now requires grounding) — both are dispositioned CLOSED in the sweep (D-08b), strengthening
  SEC-01.
- **The protocol-sub exemption (D-13) is load-bearing for bootstrap** — VAULT/sDGNRS self-subscribe with
  no pass + no funds at construction; the gates MUST carve them out or deploy breaks. USER confirmed.
- The genuinely-new v56 attack surfaces the sweep spends deepest effort on: the strategic sub/unsub
  edge (PRIMARY), the D-11/D-12 hardened gates + the now-sound `5cb707f2` bypass (D-04/D-08b), and the
  new `drainAffiliateBase` stub reachability + the affiliate `claim` CEI.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within the TERMINAL phase scope. Any FINDING_CANDIDATE the sweep surfaces is,
by default, DEFER→v57 with its fix design locked — adjudicated at the USER closure gate (D-07), not in
this discussion. The v52 consolidated cross-model audit still folds the v56 surface into its cumulative
sweep as an additional track (recorded in the v52 charge), not a substitute for this in-milestone close.

</deferred>

---

*Phase: 357-terminal-delta-audit-3-skill-genuine-parallel-adversarial-sw*
*Context gathered: 2026-06-02*
