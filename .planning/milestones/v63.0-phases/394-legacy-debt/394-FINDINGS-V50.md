# 394-FINDINGS-V50 — LEGACY-DEBT / the v50 surface adjudication (LEGACY-01 + LEGACY-02)

**Subject (byte-frozen):** `a8b702a7` (contracts tree pin `2934d3d8987a09c5f073549a0cb499f6c5f28620`).
**Baseline (green oracle):** `test/REGRESSION-BASELINE-v63.md` = forge **854 / 0 / 110**.
**Date:** 2026-06-15.
**Method — CROSS-MODEL-LED, dual-net (AUDIT-V63-PLAN §2):** NET 1 = the external council
(`gemini` + `codex`, 394-01); NET 2 = the independent Claude adversarial net (394-03-CLAUDE-NET.md). A
no-finding verdict for any v50 sub-item requires BOTH nets on record.
**Posture:** AUDIT-ONLY. A CONFIRMED finding is DOCUMENTED and ROUTED to a SEPARATE gated USER-hand-review
boundary (batched, never auto-committed; the subject re-freezes after) — it is NOT fixed in this phase.
**Threat weighting (§4):** RNG-freeze = DOMINANT; value-non-equivalence / solvency / MINTDIV-drift = SPINE;
access / reentrancy / timing = confirmatory.
**Design-intent anchor (§5 — VERIFY, do not re-litigate):** the AFSUB inclusive eviction boundary
([[afking-pass-eviction-inclusive-boundary-intended]]), the OPEN-E operator-approval trust boundary
([[open-e-operator-approval-trust-boundary]]), the lootbox/claim-timing-is-not-a-player-edge ruling
([[lootbox-resolution-timing-by-design]]), and the whale-pass / WWXRP economics
([[degenerette-wwxrp-rtp-by-design]]) are BY-DESIGN.

---

## 1. Both-nets-on-record attestation

| Slice | NET 1 (council) | NET 2 (Claude) | Both? |
|---|---|---|---|
| v50 LEGACY-DEBT (LEGACY-01 whale-pass O(1) + box record; LEGACY-02 AFSUB + OPEN-E + MINTDIV) | `394-01-COUNCIL-NET.md` + `council/v50.gemini.txt` (22 lines) + `council/v50.codex.txt` (38 lines) — **BOTH models on record** (`v50.council.json` `skipped: []`; the codex usage-limit RESET this run, a change from 392/393). The two FINDINGS are DIVERGENT + cross-contradicting (the ideal adjudication input): gemini SOUND on LEGACY-01 / FINDING on MINTDIV; codex FINDING on LEGACY-01 / SOUND on MINTDIV; convergent SOUND on LEGACY-02a. | `394-03-CLAUDE-NET.md` — independent per-item attack: whale-pass O(1) value-equivalence + delta-stat-cap (§LEGACY-01a), the claim-time horizon skeptic dual-gate (§LEGACY-01), the deferred-claim freeze backward-trace re-verified in code (§LEGACY-01b), the AFSUB boundary/consent as-coded (§LEGACY-02a), the MINTDIV count-lockstep + quadrant-distribution proof (§LEGACY-02b) | ✓ both |

**Both-nets requirement satisfied for every v50 sub-item.** No item is treated as on-record from a single
net. **No post-reset codex re-run is owed for THIS slice** (codex was available + on record). The EXISTING
392/393 codex second-source carry-forward to 396 is unaffected; the codex reset is an OPPORTUNITY to pick up
those carried re-runs while the limit holds (flagged to 396).

**Threat-register cross-check:** T-394-08 (a no-finding verdict without both nets, or the whale-pass
value-equivalence attested without the arithmetic, or the MINTDIV lockstep waved without a proof) does NOT
apply — both nets are on record; the value-equivalence carries the delta-stat-cap arithmetic
(`Storage:1338`); the MINTDIV lockstep carries the `processed += take` proof + the `address[][256]`
bucket-semantics reason. T-394-09 (a CONFIRMED break under-weighted, or a HIGH tagged without the skeptic
filter) does NOT apply — the two divergent SPINE candidates were each run through the skeptic dual-gate
(§3). T-394-10 (a CONFIRMED finding silently fixed in-phase) does NOT apply — 0 CONFIRMED; the subject stays
byte-frozen.

---

## 2. Per-item adjudication table (LEGACY-01 + LEGACY-02)

| ITEM | What it claims | NET 1 | NET 2 | **VERDICT** | Settling value-equivalence / freeze / consent / lockstep cite (`a8b702a7`) |
|---|---|---|---|---|---|
| **LEGACY-01a** — whale-pass O(1) value-equivalence | the deferred `claimWhalePass` materializes the SAME value as the retired inline mint; single-shot, no double-claim | gemini SOUND / codex SOUND-on-count | REFUTED (value-equivalent) | **REFUTED** | COUNT timing-independent: `_queueTicketRange(player, startLevel, 100, halfPasses, false)` always queues `100 × halfPasses` (`WhaleModule:1007`, def `Storage:679`). SINGLE-SHOT: `whalePassClaims[player] = 0` (`WhaleModule:997`) BEFORE the award (`:1005-1007`); re-call reads 0 → `return`. STAT delta-capped: `levelsToAdd = min(100, deltaFreeze)`, no-double-dip (`Storage:1338`). Box enqueue single-shot: `boxPlayers[index].push` only on `existingAmount==0` (`WhaleModule:888`). |
| **LEGACY-01 (horizon)** — claim-time horizon shift | codex: a DELAYED claim queues from claim-time `level+1` → "100 FUTURE levels" = value non-equivalence (SPINE) | **codex FINDING (SPINE)** vs gemini SOUND | BY-DESIGN (D-04/D-20; no extraction) — skeptic gate run | **BY-DESIGN** | DOCUMENTED INTENT: `_activateWhalePass` doc "D-04 — timing shifts from open-time to claim-time" (`LootboxModule:1483-1485`) + the type-28 caller comment "tickets start at the level when the player calls claimWhalePass" (`:1903-1907`). `whalePassClaims` stores a COUNT only (`Storage:1107`); `startLevel = level + 1` reads the LIVE `level` (`WhaleModule:1003`, `level` = `Storage:237`). No extraction: count identical at any level; the shift moves coverage FORWARD (neutral-or-self-harming, never over-delivery); claim is RNG-independent; the pass is near-worthless ([[degenerette-wwxrp-rtp-by-design]]); inert claim-timing is covered by [[lootbox-resolution-timing-by-design]]. codex MECHANISM correct, SPINE label fails the skeptic gate; gemini OUTCOME (no value harm) correct. |
| **LEGACY-01b** — deferred-claim FREEZE-safety | the box index is committed at deposit before the word lands; the claim cannot steer the draw (DOMINANT) | convergent SOUND | REFUTED (RNG-independent claim) | **REFUTED** | COMMITMENT POINT: `index` snapshotted ONCE at deposit `lr = lootboxRngPacked; index = (lr >> LR_INDEX_SHIFT) & LR_INDEX_MASK` (`WhaleModule:850-851`), strictly before the word for that index is revealed. `claimWhalePass` reads NO RNG (`WhaleModule:991-1008` — zero `lootboxRng`/`entropy`/`word`); only `level`. Queued tickets are far-future-keyed + rng-locked while a word is in flight (`Storage:699`). Re-verified IN CODE (not the SPEC-334 paper proof). Green anchor: `RngWindowFreeze.inv.t.sol` (exercised, non-vacuous). |
| **LEGACY-02a** — AFSUB boundary + OPEN-E consent | inclusive keep-while-`<=`/evict-at-`+1` as documented; subscribe-time consent gate, no bypass | **convergent SOUND** (gemini + codex) | REFUTED / as-coded-by-design | **BY-DESIGN (as-coded)** | INCLUSIVE boundary `if (currentLevel > sub.validThroughLevel)` (`AfkingModule:1246`) → refresh if `currentLevel <= h` (`:1248-1250`) else finalize/delete/swap-pop (`:1252-1264`); `_passHorizonOf` canonical (deity sentinel / `frozenUntilLevel`) at BOTH write (`:419`) + crossing (`:596-606`); no-pass guard rejects `validThroughLevel == 0 || < level` (`:414-428`). CONSENT subscribe-only: SUB-02 `operatorApprovals[subscriber][msg.sender]` (`:314-320`) + OPENE-04 `operatorApprovals[fundingSource][subscriber]` (`:322-330`); `exemptSub` = VAULT/SDGNRS only (`:414-416`). The leniency is INTENDED, not flagged. |
| **LEGACY-02b** — MINTDIV index alignment | gemini: `processed` resets per-call → quadrant `(i & 3) << 6` mis-assigned across a budget split = quadrant bias (SPINE) | **gemini FINDING (SPINE)** vs codex SOUND | REFUTED (count lockstep exact; quadrant = distribution not ordering) — skeptic gate run | **REFUTED** | COUNT LOCKSTEP: `take = min(owed, maxT)` (`MintModule:634`); persisted debt drops by EXACTLY `take` (`:660-666` / `:1018-1020`); index advances `processed += take` (`:667` / `:902`, MINTDIV-02 replaced `writesUsed>>1`); reset only on `remainingOwed == 0` (`:672-676` / `:896`). No double-write / no skip across a split (the `owedMap` remainder is the resume anchor). QUADRANT is DISTRIBUTION not ordering: trait id = `(color<<3)|symbol` (0-63) + `(i&3)<<6` top bits → full 8-bit id; `traitBurnTicket[level]` = `address[][256]` jackpot buckets (`Storage:425-441`, `TraitUtils:143-175`); no contract treats the quadrant as ticket position; the per-call restart changes WHICH bucket a tail ticket lands in, not the count or the EV. gemini MECHANISM correct, SPINE label fails the skeptic gate; codex count-lockstep correct. Green anchor: `MintBatchDeterminism.test.js` (multiset-equality with a per-call `processed=0` reference replay, GREEN 854/0). |

---

## 3. Skeptic gate (run before any CATASTROPHE/HIGH)

Two SPINE candidates from NET 1 reached the gate — the LEGACY-01 horizon (codex) and the LEGACY-02b
quadrant (gemini). Each is the divergent half of a cross-contradicting pair; each was run through the
dual-gate (structural-protection check + the 3-condition EV lens) against the FROZEN source.

### 3a. LEGACY-01 horizon shift (codex SPINE candidate) — the PRIORITY dual-gate
- **Structural-protection / documented-intent:** the `LootboxModule:1483-1485` D-04 doc + the
  `:1903-1907` caller comment EXPLICITLY document the open-time→claim-time horizon shift as v50 design
  (D-04 / D-20). This is intent, not accidental drift.
- **3-condition EV lens:** (1) value gained/lost — NONE (count timing-independent: same `100 × halfPasses`
  at any claim level); (2) direction — a late claim moves coverage FORWARD into not-yet-reached levels =
  neutral-or-SELF-HARMING (the player forgoes the levels between open and claim), never an over-delivery;
  (3) player-steerable EV edge — NONE (the award is illiquid tickets on a near-worthless pass; the claim is
  permissionless + RNG-independent; the timing-not-an-edge ruling covers it). **Gate FAILS for HIGH** →
  BY-DESIGN. (NET 2 §LEGACY-01.)

### 3b. LEGACY-02b quadrant (gemini SPINE candidate) — dual-gate
- **Structural-protection:** the quadrant `(i & 3) << 6` is the top 2 bits of an 8-bit trait id whose
  `address[][256]` bucket array is a JACKPOT DISTRIBUTION structure (`Storage:425-441`), not a per-player
  ordering. No contract reads the quadrant as ticket-N's position. The count accounting (`processed += take`,
  exact `owedMap` debit) is INDEPENDENT of the quadrant and is lockstep across budget splits.
- **3-condition EV lens:** (1) value gained/lost — NONE (count exact, no double-write/skip); (2) the
  residual variance is over WHICH bucket a tail ticket lands in — the jackpot draws over the level-wide
  256-bucket multiset, so a different quadrant placement does not change the player's win probability; (3)
  player-steerable — to "force a split at a specific offset" needs control of the global queue position +
  `WRITES_BUDGET` + cold/warm scaling + co-queued players, AND the result would have to map to a
  selection advantage that does not exist. **Gate FAILS for HIGH** → REFUTED. Green-oracle corroboration:
  `MintBatchDeterminism.test.js` asserts the credited 256-bucket multiset matches a per-call-reset reference
  replay (854/0). (NET 2 §LEGACY-02b.)

**Result: NOTHING reaches HIGH/CATASTROPHE.** Both divergent SPINE candidates are documented-intent or
distribution-not-ordering; neither survives the skeptic dual-gate at the frozen source. The convergent-SOUND
items (LEGACY-01b box record, LEGACY-02a) and the value-equivalence (LEGACY-01a) are attested with both
nets on record.

---

## 4. Routing — CONFIRMED findings + carried INFO/MONITOR

### 4a. CONFIRMED contract findings
**0 CONFIRMED — document-only.** No CONTRACT-CHANGE-NEEDED block is emitted. LEGACY-01 + LEGACY-02 are
attested at `a8b702a7` with both nets on record. The subject stays byte-frozen
(`git diff a8b702a7 -- contracts/` empty).

### 4b. Carried INFO / MONITOR (no contract change; recorded so a future reader doesn't re-derive)
- **INFO — `MintBatchDeterminism.test.js` header staleness (test-only, ROUTED, not a contract finding).**
  The test header comment (lines 36-37) still describes Path B's accumulator as `processed += writesUsed >>
  1`; the live frozen caller is `processed += take` (`MintModule:902`, MINTDIV-02). The reference replay
  uses the EMITTED values so the assertion is correct against the live behavior — a comment-only staleness.
  Route a comment trim to a future test-hardening batch; NOT a contract change.
- **MONITOR (non-finding, favors the protocol) — late-claim stat UNDER-delivery.** The
  `_applyWhalePassStats` no-double-dip (`Storage:1338`) means a player who buys an independent pass that
  raises `frozenUntilLevel` BEFORE claiming a deferred whale-pass gets `deltaFreeze` reduced — a late claim
  can UNDER-deliver stats vs an early claim. This is the no-double-dip cap working as designed; it bounds
  the award DOWNWARD only. Recorded as a non-finding.
- **codex second-source carry (392/393, ROUTED to 396 — unchanged by this slice).** The codex reset is an
  OPPORTUNITY to pick up the carried 392 (BURNIE-04/-05) + 393 (ACCESS-02/-04) codex second-source re-runs
  while the limit holds; the post-responsive gemini second-source of the 394-02 v51 codex SOUND verdicts is
  likewise carried to 396. No debt added by THIS slice (codex on record here).

Any test-only (oracle-integrity / comment-staleness) gap is ROUTED, not a contract finding.

---

## 5. Re-attestation line (each req attested-or-finding)
- **LEGACY-01** (whale-pass O(1) deferred-claim path + box-open record) — **ATTESTED at `a8b702a7`**, both
  nets on record. Value-equivalence + single-shot REFUTED-as-finding (sound); the claim-time horizon
  BY-DESIGN (D-04/D-20, skeptic-gated); the box-record freeze REFUTED-as-finding (RNG-independent).
  **0 CONFIRMED.**
- **LEGACY-02** (AFSUB `validThroughLevel` evict/refresh + OPEN-E re-attest + MINTDIV index alignment) —
  **ATTESTED at `a8b702a7`**, both nets on record. AFSUB boundary/consent BY-DESIGN-as-coded; MINTDIV
  count-lockstep exact + the quadrant REFUTED-as-finding (distribution, not ordering, skeptic-gated).
  **0 CONFIRMED.**
- **LEGACY-05** — `audit/FINDINGS-v50.0.md` authored from this dual-net adjudication (Task 2 deliverable).

**Slice verdict:** the v50 legacy-debt surface (LEGACY-01 + LEGACY-02) is adjudicated against the
byte-frozen subject `a8b702a7` with BOTH nets on record, the skeptic dual-gate applied to the two divergent
SPINE candidates, and every sub-item carrying an explicit verdict. **0 CONFIRMED contract findings.** The
subject stays byte-frozen.
