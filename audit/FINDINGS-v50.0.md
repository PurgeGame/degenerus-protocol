# FINDINGS — v50.0 (Whale-Pass O(1) + AFSUB Pass-Gated Subs + MintModule Index Alignment — deferred deliverable, swept under v63.0 Phase 394 LEGACY-DEBT, CROSS-MODEL-LED)

- **Frozen audit subject (SHA):** `a8b702a7` (contracts tree pin `2934d3d8987a09c5f073549a0cb499f6c5f28620`). The v50 contract surface is audited AS IT STANDS in the byte-frozen v63 subject. **NOTE — the v50 surface was NOT separately re-frozen:** v50.0 closed 2026-05-28 via a USER-approved MINIMAL CLOSE (closure HEAD `812abeee`, no formal `MILESTONE_V50_AT_HEAD` signal), with Phase 338's internal 3-skill adversarial sweep + delta-audit + this `FINDINGS-v50.0.md` all DEFERRED. The deferred debt was folded into v63.0 Phase 394 (LEGACY-DEBT, reqs LEGACY-01/-02/-05) by the USER on 2026-06-14, so the v50 surface is swept as the form it carries at the cumulative byte-frozen v63 subject `a8b702a7` (the v50 items are byte-stable from the v50 close through this subject; `git diff a8b702a7 -- contracts/` is empty at every checkpoint — this is a document-only audit, zero `contracts/*.sol` mutation).
- **Baseline (frozen, green oracle):** `test/REGRESSION-BASELINE-v63.md` = forge **854 / 0 / 110** (carries the Phase-336 v50 coverage: whale-pass equivalence + uniform-O(1) + freeze fuzz; the AFSUB sweep/evict/refresh + no-pass-SLOAD oracle; the MINTDIV cross-path equality).
- **Date:** 2026-06-15.
- **Method — CROSS-MODEL-LED, dual-net (the defining v63 premise, AUDIT-V63-PLAN §2):** the external council (`gemini` + `codex`) is the PRIMARY finder; Claude orchestrates the dispatch, runs an INDEPENDENT second-discipline net, **adjudicates every candidate vs the frozen source** with the skeptic dual-gate, applies the locked threat model + by-design rulings, and anchors verdicts to the green oracle. A no-finding verdict for any sub-item requires BOTH nets on record (NET 1 = council `394-01`; NET 2 = Claude `394-03`).
- **Council pipeline:** `.planning/audit-v52/cross-model/bin/council.sh` -> `ask-gemini.sh` (read-only `--approval-mode plan`) + `ask-codex.sh` (`exec --sandbox read-only`). For the v50 slice (`--label v50`) **both models returned substantive traced audits; `v50.council.json` `skipped: []`** (the codex usage-limit reset for this run). Raw outputs: `.planning/phases/394-legacy-debt/council/v50.gemini.txt` (22 lines) + `v50.codex.txt` (38 lines).

---

## Executive summary

**The v50 surface (the whale-pass O(1) deferred-claim refactor, the AFSUB pass-gated subscriptions, and the MintModule index alignment) clears the dual-net sweep with 0 actionable findings.** The cross-model council produced the ideal adjudication input — two DIVERGENT, cross-contradicting SPINE candidates (codex flagged the whale-pass claim-time horizon; gemini flagged a MINTDIV quadrant bias; each model cleared the item the other flagged; both converged SOUND on AFSUB). Both candidates were run through the skeptic dual-gate against the byte-frozen source: the horizon shift is DOCUMENTED v50 intent (D-04 / D-20) with no value-extraction edge, and the MINTDIV quadrant is a random distribution mechanism (not a per-player ordering invariant) whose count accounting is exact and lockstep across budget splits. Neither survives to a HIGH. Every result is anchored to the green oracle (854/0/110) and re-verified in code, not trusted from the v50 paper proofs.

| Disposition | Count |
|---|---|
| **HIGH / CATASTROPHE (contract fix required)** | **0** |
| MEDIUM (contract fix required) | 0 |
| LOW (bounded; fix recommended) | 0 |
| BY-DESIGN (documented intent, recorded so not re-flagged) | 3 — the claim-time horizon (D-04/D-20), the AFSUB inclusive boundary, the OPEN-E operator-approval |
| REFUTED at the frozen source (the divergent SPINE candidates + the value/freeze claims) | 4 — LEGACY-01a value-equivalence, LEGACY-01b box-record freeze, LEGACY-02a AFSUB-as-coded, LEGACY-02b MINTDIV quadrant |
| INFO / test-only (ROUTED, not a contract change) | 1 — `MintBatchDeterminism.test.js` stale Path-B accumulator comment |

> **Milestone outcome:** this is the deferred v50 AUDIT deliverable, discharged in-milestone under v63.0 Phase 394. Its deliverable is THIS findings document. **0 actionable findings -> no remediation gate from the v50 surface.** The subject stays byte-frozen; no fix is applied or committed.

---

## The v50 surface coverage (each item with its adjudicated verdict + settling cite at `a8b702a7`)

### LEGACY-01 — Whale-pass O(1) deferred-claim path + box-open record

The v50 refactor replaced the retired inline ~100-loop pass mint with an O(1) deferred claim: a box-open
whale-pass boon (type 28) records `whalePassClaims[player] += 1` (a COUNT only, `LootboxModule:1489`,
`Storage:1107`), and materialization (stats + `100 levels x halfPasses` tickets) is deferred to the
player-paid `claimWhalePass` endpoint (`WhaleModule:991`).

- **LEGACY-01a — value-equivalence — VERIFIED SOUND (REFUTED as a finding).** The deferred claim is
  value-equivalent to the inline mint: the ticket COUNT is timing-independent
  (`_queueTicketRange(player, startLevel, 100, halfPasses, false)` always queues `100 x halfPasses`,
  `WhaleModule:1007`); the claim is strict single-shot (`whalePassClaims[player] = 0` at `:997` BEFORE the
  award at `:1005-1007`; a re-call reads 0 and returns); the stat application is delta-capped with no
  double-dip (`levelsToAdd = min(100, deltaFreeze)`, `_applyWhalePassStats`, `Storage:1338`); the box
  enqueue is single-shot (`boxPlayers[index].push` only on `existingAmount == 0`, `WhaleModule:888`).
- **LEGACY-01 (claim-time horizon) — BY-DESIGN (D-04 / D-20).** codex (NET 1) flagged a SPINE
  value-non-equivalence: a DELAYED claim recomputes `startLevel = level + 1` from the LIVE claim-time
  `level` (`WhaleModule:1003`, `level` = `Storage:237`), so a late claim queues the 100-level span from
  claim-time `level+1` instead of open-time `level+1`. The mechanism is ACCURATE, but the horizon shift is
  DOCUMENTED v50 design: the `_activateWhalePass` doc states "D-04 — timing shifts from open-time to
  claim-time" (`LootboxModule:1483-1485`) and the type-28 caller comment states "the queued tickets start
  at the level when the player calls claimWhalePass — not necessarily `level + 1` here"
  (`:1903-1907`). Skeptic dual-gate: the count is identical at any claim level; the shift moves coverage
  FORWARD (neutral-or-self-harming, never an over-delivery); the award is illiquid tickets on a
  near-worthless pass; the claim is permissionless + RNG-independent. No value-extraction edge — the
  inert claim-timing is covered by the lootbox/claim-timing-is-not-a-player-edge ruling. gemini's
  "value-equivalent" outcome and codex's "horizon shifts" mechanism reconcile under "documented intent, no
  extraction."
- **LEGACY-01b — box-open record FREEZE-safety — VERIFIED SOUND (REFUTED, re-verified in code).** The
  lootbox index is committed ONCE at deposit (`lr = lootboxRngPacked; index = (lr >> LR_INDEX_SHIFT) &
  LR_INDEX_MASK`, `WhaleModule:850-851`), strictly before the word for that index is revealed; the
  consumer gates on `lootboxRngWordByIndex[index] != 0`. The `claimWhalePass` path reads NO RNG word
  (`WhaleModule:991-1008` — zero entropy reads; the only live read is `level`, the horizon input), so the
  deferred claim cannot steer which word/index it reads. WHALE-04 freeze re-verified at the frozen source,
  not trusted from the SPEC-334 paper proof. Green anchor: `RngWindowFreeze.inv.t.sol` (exercised,
  non-vacuous).

### LEGACY-02 — AFSUB pass-gating (`validThroughLevel` evict/refresh + OPEN-E re-attest) + MINTDIV index alignment

- **LEGACY-02a — AFSUB boundary + OPEN-E consent — VERIFIED SOUND / BY-DESIGN-as-coded (convergent NET 1
  + NET 2).** The inclusive eviction boundary is coded as documented: `if (currentLevel >
  sub.validThroughLevel)` (`AfkingModule:1246`) keeps the sub while `currentLevel <= validThroughLevel`
  and evicts at `+1`; on crossing it re-reads the canonical `_passHorizonOf(player)` (deity sentinel
  `type(uint24).max` / else `frozenUntilLevel`, `:596-606`) and REFRESHES if still covered (`:1248-1250`)
  else FINALIZES -> delete -> swap-pop (`:1252-1264`); the no-pass guard rejects a non-exempt subscriber with
  `validThroughLevel == 0 || < level` (`:414-428`). The OPEN-E consent gate is subscribe-only: SUB-02
  `operatorApprovals[subscriber][msg.sender]` (`:314-320`) + OPENE-04
  `operatorApprovals[fundingSource][subscriber]` (`:322-330`); `exemptSub` = VAULT/SDGNRS only
  (`:414-416`). The inclusive leniency and the operator-approval-is-the-trust-boundary semantics are
  INTENDED and are NOT flagged.
- **LEGACY-02b — MINTDIV index alignment — VERIFIED SOUND (REFUTED).** gemini (NET 1) flagged a SPINE
  quadrant bias: the within-call `processed` cursor resets per `advanceGame` call
  (`MintModule:582`/`874`), so across a write-budget split the quadrant offset `(uint8(i & 3) << 6)`
  (`:761`, keyed on `i = processed...`) restarts from 0 rather than continuing. The mechanical observation
  is accurate, but the COUNT accounting is exact and lockstep: `take = min(owed, maxT)` (`:634`); the
  persisted debt drops by EXACTLY `take` (`:660-666` / `:1018-1020`); the index advances `processed +=
  take` (`:667` / `:902`, the MINTDIV-02 fix that replaced the `writesUsed >> 1` heuristic); the reset
  fires only on `remainingOwed == 0` (`:672-676` / `:896`); the persisted `owedMap` remainder is the
  resume anchor — no double-write, no skip across a budget boundary. The quadrant is a RANDOM DISTRIBUTION
  mechanism, NOT a per-player ordering invariant: a trait id is `(color << 3) | symbol` (0-63) plus the
  quadrant top 2 bits forming a full 8-bit id, indexing the `address[][256]` jackpot-bucket array
  (`Storage:425-441`, `TraitUtils:143-175`); no contract reads the quadrant as ticket-N's position, the
  jackpot draws over the level-wide 256-bucket multiset, and the per-call restart changes WHICH bucket a
  tail ticket lands in, not the count or the EV. Skeptic dual-gate: no value gained/lost, no
  player-steerable edge. codex's count-lockstep verdict is correct. Green anchor:
  `MintBatchDeterminism.test.js` — its W2 indexer-replay reconstructs the credited trait multiset
  (every trait id 0..255, including the quadrant bits) with a per-call `processed = 0` reference replay
  and asserts trait-by-trait equality with the on-chain credit (GREEN, 854/0).

---

## Lower-severity / INFO

- **INFO — `test/edge/MintBatchDeterminism.test.js` stale Path-B accumulator comment (test-only).** The
  test header (lines 36-37) still describes Path B's `processed` accumulator as `processed += writesUsed >>
  1`; the live frozen caller is `processed += take` (`MintModule:902`, MINTDIV-02). The reference replay
  uses the EMITTED values so the assertion is correct against the live behavior — a comment-only staleness.
  Route a comment trim to a future test-hardening batch; NOT a contract change.

## Refuted / by-design (recorded so they are not re-flagged)

- **Whale-pass claim-time horizon shift (codex, divergent SPINE candidate) — BY-DESIGN (D-04 / D-20).** A
  deferred claim queues from claim-time `level+1`; this is documented v50 intent
  (`LootboxModule:1483-1485` + `:1903-1907`), count-equivalent, neutral-or-self-harming in direction,
  non-extractable, and freeze-independent.
- **MINTDIV quadrant bias (gemini, divergent SPINE candidate) — REFUTED.** The quadrant is a random
  distribution mechanism over the `address[][256]` jackpot buckets, not a per-player ordering invariant;
  the count is exact and lockstep across budget splits; the residual placement variance carries no EV edge
  and is the tested behavior of the green oracle.
- **AFSUB inclusive eviction boundary — BY-DESIGN.** Keep while `currentLevel <= validThroughLevel`, evict
  at `+1` ([[afking-pass-eviction-inclusive-boundary-intended]]); the intended leniency, not a defect.
- **OPEN-E operator-approval trust boundary — BY-DESIGN.** Operator-approval IS the trust boundary; a later
  revoke does not stop an active sub; a re-point = re-subscribe re-checks
  ([[open-e-operator-approval-trust-boundary]]); not modelling a tricked-into-approving actor.
- **Whale-pass / WWXRP economics — BY-DESIGN.** The pass is near-worthless (the value is the near-unfarmable
  whale pass), the global per-bracket supply flag caps supply ([[degenerette-wwxrp-rtp-by-design]]); not a
  finding.

## Prior mitigations on record (v50 close)

- **WHALE-04 freeze-safety** proven at SPEC (Phase 334) and re-verified IN CODE here (LEGACY-01b).
- **TST-01 / TST-03** empirical coverage at Phase 336 (whale-pass equivalence + uniform-O(1) + freeze fuzz;
  the AFSUB sweep/evict/refresh + no-pass-SLOAD oracle; the MINTDIV cross-path equality) — carried green in
  `REGRESSION-BASELINE-v63` (854/0/110).
- **MINTDIV-01 reachability** proven at SPEC (Phase 334); the MINTDIV-02 `processed += take` alignment
  (replacing the `writesUsed >> 1` heuristic) is the live frozen code (`MintModule:902`).
- Pre-launch (no live funds); the v50 contract history is UNPUSHED.

## Both-nets attestation

Both nets are on record for every v50 sub-item (NET 1 = the council `394-01`, gemini + codex both
substantive, `skipped: []`; NET 2 = the independent Claude net `394-03-CLAUDE-NET.md`). The two DIVERGENT
SPINE candidates were each run through the skeptic dual-gate against the byte-frozen source. No sub-item is
attested from a single net. The full slice adjudication (the per-item table, the skeptic gate, the routing)
is recorded in `.planning/phases/394-legacy-debt/394-FINDINGS-V50.md`.

## Routing

**0 CONFIRMED contract findings -> no remediation gate from the v50 surface.** The single INFO item (the
stale test comment) is test-only and ROUTED to a future comment-trim batch. The subject stays byte-frozen
(`git diff a8b702a7 -- contracts/` empty); no fix is applied or committed in this audit milestone.
