# Phase 244: Per-Commit Adversarial Audit (EVT + RNG + QST + GOX) — Context

**Gathered:** 2026-04-24
**Status:** Ready for planning
**Mode:** Auto-decided via Phase 230 / 237 / 238 / 243 precedents (user selected 1 gray area: QST-05; all others auto-locked from precedent)

<domain>
## Phase Boundary

Adversarially audit every contract code change in the 5 post-v30 commits (4 code-touching + 1 docs-only) against its commit-message behavior claim — surface every finding candidate {SAFE / INFO / LOW / MEDIUM / HIGH / CRITICAL} into the v31.0 candidate pool before Phase 245 (sDGNRS + gameover safety) and Phase 246 (findings consolidation).

Scope source is `audit/v31-243-DELTA-SURFACE.md` (FINAL READ-only at HEAD `cc68bfc7`). The Section 6 Consumer Index already maps every Phase 244 REQ to its specific D-243-X / D-243-F / D-243-C / D-243-S row IDs — Phase 244 plans inherit scope without re-discovery.

19 requirements across 4 commit-buckets:

- **EVT-01..EVT-04** (4 REQs) — `ced654df` JackpotTicketWin event correctness — every emit path scaled non-zero / new whale-pass emit covers odd-index BAF / TICKET_SCALE uniform / NatSpec accuracy
- **RNG-01..RNG-03** (3 REQs) — `16597cac` rngunlock fix — `_unlockRng(day)` removal safety / v30 `rngLockedFlag` AIRTIGHT invariant RE_VERIFIED_AT_HEAD `cc68bfc7` / reformat-only sub-changes byte-equivalent
- **QST-01..QST-05** (5 REQs) — `6b3f4f3c` quest recycled-ETH credits — `MINT_ETH` gross-spend credit / earlybird DGNRS gross-spend / affiliate 20-25/5 fresh-recycled split preserved / `_callTicketPurchase` return drop + rename equivalence / claimed gas savings (-142k/-153k/-76k WC) reproduction
- **GOX-01..GOX-07** (7 REQs) — `771893d1` gameover liveness + sDGNRS protection — 8 purchase/claim paths gameOver→`_livenessTriggered` / `sDGNRS.burn`+`burnWrapped` State-1 block / `handleGameOverDrain` `pendingRedemptionEthValue` subtraction / `_livenessTriggered` 14-day VRF-dead grace + day-math-first / `_gameOverEntropy` `rngRequestTime` clearing + `_handleGameOverPath` ordering / `DegenerusGameStorage.sol` slot-layout

Scope is strictly READ-only: no `contracts/` or `test/` writes (v28/v29/v30 carry-forward + project `feedback_no_contract_commits.md`). Finding-ID emission is deferred to Phase 246 (FIND-01/02/03); Phase 244 produces per-REQ verdicts + finding-candidate blocks that become the Phase 246 candidate pool.

**Not in Phase 244:** sDGNRS redemption × gameover-timing matrix (SDR-01..08 → Phase 245); pre-existing gameover invariant re-verification at depth (GOE-01..06 → Phase 245); F-31-NN finding ID assignment + severity classification + KNOWN-ISSUES.md promotion + lean regression appendix (FIND-01..03, REG-01..02 → Phase 246).

</domain>

<decisions>
## Implementation Decisions

### Plan Split & Wave Topology
- **D-01 (4 plans, one per commit-bucket — EVT/RNG/QST/GOX):** Mirrors v29.0 Phase 231-234 per-feature precedent (231 earlybird, 232 decimator, 233 jackpot/BAF, 234 quests/boons/misc) and Phase 243's 3-plans-mirrors-3-DELTA-REQs shape:
  - `244-01-PLAN.md` EVT — `ced654df` audit (EVT-01..EVT-04, 4 REQs covering 5 emit-site rows + 1 new event row + 1 NatSpec row) → contributes to consolidated deliverable
  - `244-02-PLAN.md` RNG — `16597cac` audit (RNG-01..RNG-03, 3 REQs covering 1 advanceGame row + reformat sub-changes + KI envelope re-verification)
  - `244-03-PLAN.md` QST — `6b3f4f3c` audit (QST-01..QST-05, 5 REQs covering 4 function rows + 1 interface signature + bytecode-delta methodology for QST-05)
  - `244-04-PLAN.md` GOX — `771893d1` audit (GOX-01..GOX-07, 7 REQs covering 8 purchase/claim path rows + sDGNRS revert paths + drain subtraction + livenessTriggered body + storage layout) — also pre-flags Phase 245 SDR/GOE candidates per D-08
- **D-02 (single-wave parallel — all 4 plans concurrent):** All 4 commit-buckets are scope-disjoint at function-row granularity (EVT touches `DegenerusGameJackpotModule.sol` only; RNG touches `DegenerusGameAdvanceModule.sol` only; QST touches `DegenerusQuests.sol` + `DegenerusGameMintModule.sol` + interface; GOX touches the 9-file `771893d1` surface). Zero cross-plan dependency on row data. All 4 plans fire single-wave parallel after CONTEXT lock. Honors prior user directive ("run all the parallel shit you can" — Phase 238).
- **D-03 (cc68bfc7 BAF-coupling addendum coverage routes through EVT plan):** The `cc68bfc7` addendum commit landed mid-Phase-243 and is enumerated in `audit/v31-243-DELTA-SURFACE.md` §1.6 (8 INFO Finding Candidates) — its semantic surface (BAF gated on daily-flip win + new `markBafSkipped` + `BafSkipped` event + new direct-handle `jackpots` constant) is BAF/event-flow territory and therefore folds into the EVT plan (244-01) as an EVT-02/EVT-03 sub-scope expansion, NOT a 5th plan. Per §1.7 bullet 6 (BAF expected-value re-verification under coupling) and bullet 7 (`markBafSkipped` consumer gating) and bullet 8 (`jackpots` direct-handle vs delegatecall reentrancy parity).

### Deliverable Shape
- **D-04 (single consolidated `audit/v31-244-PER-COMMIT-AUDIT.md`):** Matches Phase 230 D-05 / Phase 237 D-08 / Phase 243 D-07 single-file precedent. 4 sections, one per commit-bucket, plus a Consumer Index back-mapping. Sections (planner's discretion on internal ordering, but all required):
  1. EVT — `ced654df` per-REQ verdicts + finding-candidate blocks for EVT-01..EVT-04 + cc68bfc7 BAF-coupling sub-section
  2. RNG — `16597cac` per-REQ verdicts + finding-candidate blocks for RNG-01..RNG-03 + KI envelope re-verification subsection
  3. QST — `6b3f4f3c` per-REQ verdicts + finding-candidate blocks for QST-01..QST-05 + bytecode-delta evidence appendix for QST-05
  4. GOX — `771893d1` per-REQ verdicts + finding-candidate blocks for GOX-01..GOX-07 + Phase 245 SDR/GOE pre-flag subsection
  5. Consumer Index — v31.0 REQ-ID (EVT-01..GOX-07) → Phase 244 verdict-row mapping + cross-ref to source D-243-X/F/C/S row IDs from `audit/v31-243-DELTA-SURFACE.md` Section 6
  6. Reproduction recipe appendix — all `git show -L` / `grep` / `forge inspect bytecode` commands concatenated for reviewer replay
- **D-05 (per-plan working file pattern with consolidation in 244-04):** Each plan writes its bucket section to a working file (`audit/v31-244-EVT.md`, `v31-244-RNG.md`, `v31-244-QST.md`, `v31-244-GOX.md`) during execution. The terminal plan in the wave (244-04 GOX, since it's largest) consolidates all four bucket files into the final `audit/v31-244-PER-COMMIT-AUDIT.md`, appends Consumer Index + reproduction recipe, and flips it FINAL READ-only at SUMMARY commit. Working files remain as appendices (cross-ref only). Matches Phase 243 D-12 consolidation pattern.
- **D-06 (tabular, grep-friendly, no mermaid — Phase 243 D-08 carry):** Per-REQ verdict columns: `Verdict Row ID | REQ-ID | Source 243 Row(s) | File:Line | Adversarial Vector | Verdict (SAFE/INFO/LOW/MED/HIGH/CRITICAL) | Evidence | Owning Commit SHA`. One row per REQ × adversarial vector (multiple vectors per REQ produce multiple rows; per-REQ closure aggregation in a separate REQ-summary table). Finding-candidate prose blocks follow the table per bucket section. Grep commands appendix uses portable POSIX syntax (no GNU-isms).

### Verdict Taxonomy & Cross-REQ Overlap
- **D-07 (per-REQ closure with explicit shared-row cross-cite):** Many REQs share Phase 243 rows (e.g., GOX-01..06 all touch `_livenessTriggered` body via D-243-X040..X052; QST-01/02 share `_purchaseFor` via D-243-C010 + D-243-F008). Each REQ gets its own verdict block — re-read same code through each REQ's adversarial lens, even if duplicative. Cleaner audit trail (a Phase 246 reviewer can grep for "GOX-01" and see every verdict that closes it without untangling multi-REQ verdict cells). Where two REQs share an adversarial vector exactly (e.g., GOX-04 + GOX-05 both about `_livenessTriggered` body), the second REQ's verdict cell may cross-cite the first row's evidence with an explicit `(see Verdict Row ID GOX-04-V01 — same vector)` reference instead of full re-derivation. Matches v29.0 Phase 231 D-08 attack-vector enumeration pattern.
- **D-08 (per-REQ verdict from the 6-bucket taxonomy, locked by ROADMAP SC-5):** Every audited REQ receives a closed verdict {SAFE / INFO / LOW / MEDIUM / HIGH / CRITICAL}. Discrimination bar:
  - **SAFE** — adversarial vector enumerated; behavior matches commit-message claim under all reachable inputs/states; no finding worth surfacing
  - **INFO** — observation worth recording for Phase 246 reviewer (e.g., NatSpec discrepancy, reentrancy-adjacent ordering note, downstream-coupling consequence) but not exploitable
  - **LOW** — low-impact deviation from claim or pre-existing pattern (e.g., minor code-shape inconsistency, dead branch, unreachable revert) with non-zero correctness/UX consequence
  - **MEDIUM** — exploitable under non-trivial conditions OR breaks a documented invariant on a reachable path
  - **HIGH** — directly exploitable to siphon funds / lock state / break supply or pool conservation under realistic actor model
  - **CRITICAL** — same as HIGH but irrecoverable / unbounded loss / breaks core game invariant (gameover trigger, RNG determinism, ETH conservation)
  Severity bar follows v29.0 Phase 236 D-04 / v30.0 Phase 242 D-05 calibration. Phase 244 emits `SEVERITY: <bucket>` per finding candidate; Phase 246 FIND-02 may re-classify with full milestone context (Phase 244 verdict is the floor; Phase 246 may upgrade or downgrade with rationale).
- **D-09 (8 Section 1.7 INFO candidates from Phase 243 are pre-loaded into Phase 244 verdict pool):** Each of the 8 INFO Finding Candidates from `audit/v31-243-DELTA-SURFACE.md` §1.7 (5 from original 771893d1 sweep + 3 from cc68bfc7 addendum) is consumed by the Phase 244 plan owning the relevant REQ:
  - §1.7 bullets 1, 2 (burn/burnWrapped State-1 ordering) → 244-04 GOX-02
  - §1.7 bullet 3 (`_gameOverEntropy` rngRequestTime clearing reentry) → 244-02 RNG-02 + 244-04 GOX-06
  - §1.7 bullet 4 (`handleGameOverDrain` reserved subtraction reentrancy) → 244-04 GOX-03
  - §1.7 bullet 5 (`_handleGameOverPath` gameOver-before-liveness reorder) → 244-04 GOX-06 (Phase 244 closes the call-graph reachability check; Phase 245 GOE-04 does the deeper stall-tail enumeration)
  - §1.7 bullet 6 (cc68bfc7 BAF-coupling on bit-0 of rngWord) → 244-01 EVT-02 + EVT-03 (per D-03 expanded sub-scope)
  - §1.7 bullet 7 (`markBafSkipped` consumer gating on `cursor > lastBafResolvedDay`) → 244-01 EVT-02
  - §1.7 bullet 8 (cc68bfc7 `jackpots` direct-handle vs `runBafJackpot` delegatecall reentrancy parity) → 244-02 RNG-01 + 244-04 GOX-06 (cross-cite both)
  Each candidate either (a) closes with a Phase 244 verdict {SAFE / INFO / LOW / MED / HIGH / CRITICAL}, OR (b) is rolled forward to Phase 245 with explicit hand-off note (per D-12). Zero candidate is left unaddressed.

### Methodology Per Commit-Bucket

#### EVT (244-01)
- **D-10 (EVT adversarial vectors — fixed, planner MUST cover at minimum):**
  - **EVT-01:** (a) every JackpotTicketWin emit path enumerated via grep (cite D-243-X001/X002/X005/X007..X011 from §3 of delta surface); (b) `ticketCount` argument trace from emit-site back to scaling site to confirm non-zero `TICKET_SCALE`-scaled value; (c) verify NO emit path passes raw unscaled count or zero stub
  - **EVT-02:** (a) new `JackpotWhalePassWin` emit-site at `_awardJackpotTickets` enumerated; (b) confirm covers previously-silent large-amount odd-index BAF path via per-amount-bucket dispatch trace; (c) verify `amount` and `traitId` args correct; (d) cc68bfc7 BAF-coupling sub-vector — `markBafSkipped` consumer gating verification per §1.7 bullet 7
  - **EVT-03:** (a) for each emit site, derive scaled value path from raw input; (b) confirm uniform `TICKET_SCALE` factor across BAF + trait-matched paths; (c) UI-consumer divisibility invariant (every emit value % TICKET_SCALE == 0) holds
  - **EVT-04:** (a) read NatSpec at HEAD `cc68bfc7` for `JackpotTicketWin` event declaration; (b) per-claim accuracy check against actual emit-site behavior (scaling described correctly, fractional remainder resolution path described correctly)

#### RNG (244-02)
- **D-11 (RNG adversarial vectors — fixed, planner MUST cover at minimum):**
  - **RNG-01:** (a) trace every reaching path that lands at the post-`payDailyJackpot(true, lvl, rngWord)` continuation in `advanceGame` after `_unlockRng(day)` removal; (b) for each path, identify the next `rngLocked = false` SSTORE and verify it is reached on the SAME tick (no cross-tick reachability); (c) HUNK-ADJACENT cross-cite to `audit/v31-243-DELTA-SURFACE.md` §1.8 INV-237-035 row; (d) actor-class adversarial closure (player / admin / validator / VRF oracle — Phase 238 D-07 four-actor taxonomy carry) — does any actor reach a path where rngLocked stays set past the tick?
  - **RNG-02:** (a) re-verify v30.0 `rngLockedFlag` AIRTIGHT invariant (no double-set, no set-without-clear, no clear-without-matching-set) at HEAD `cc68bfc7`; (b) cross-cite Phase 239 RNG-01..03 result; (c) cite §1.8 reconciliation rows (INV-237-021..037 on rngLockedFlag); (d) confirm `_gameOverEntropy` rngRequestTime clearing per §1.7 bullet 3 does not break the AIRTIGHT invariant; (e) explicit RE_VERIFIED_AT_HEAD `cc68bfc7` annotation per Phase 238 D-10 pattern
  - **RNG-03:** (a) for the `16597cac` multi-line SLOAD + tuple destructuring reformat hunks, side-by-side prose diff naming the specific elements proven byte-equivalent (no SSTORE order change, no branch added, no return-path evaluation drift); (b) classification follows Phase 243 D-04 REFACTOR_ONLY definition + D-19 evidence burden — name the concrete source element the verdict keys on

#### QST (244-03)
- **D-12 (QST adversarial vectors — fixed, planner MUST cover at minimum):**
  - **QST-01:** (a) trace MINT_ETH daily + level quest credit path from purchase entry through `_callTicketPurchase` → `handlePurchase(ethMintSpendWei)` → quests credit hook; (b) confirm credit uses gross spend (`ethMintSpendWei`, fresh + recycled) at every reachable site; (c) confirm zero residual paths credit fresh-only
  - **QST-02:** (a) trace earlybird DGNRS emission counting against the same `ethMintSpendWei` parameter; (b) verify no double-counting across QST-01's MINT_ETH path AND QST-02's earlybird path (shared input, distinct sinks)
  - **QST-03:** (a) negative-scope verification — `_recordAffiliateStake` and adjacent affiliate-split helpers UNCHANGED by `6b3f4f3c` per §2.3; (b) differential check against `audit/v30-CONSUMER-INVENTORY.md` (or v29 affiliate-trail artifact if more relevant) confirming the fresh-vs-recycled 20-25/5 split is preserved untouched
  - **QST-04:** (a) for `_callTicketPurchase` return drop (`freshEth` removed): enumerate all callers, confirm none use the dropped return value (REFACTOR_ONLY at the caller-hunk granularity per Phase 243 D-04); (b) for `ethFreshWei → ethMintSpendWei` parameter rename: confirm all call sites pass the gross-spend value (semantically MODIFIED_LOGIC where intent changed, REFACTOR_ONLY at the rename hunk itself); (c) side-by-side prose diff naming the rename + drop boundary
  - **QST-05:** Per D-13 (QST-05 methodology lock — bytecode-delta-only)

- **D-13 (QST-05 methodology — BYTECODE-DELTA-ONLY, no gas measurement):** Per user discussion (the only explicitly-discussed gray area). QST-05 is verified by `forge inspect bytecode` deployed-bytecode delta, NOT by running gas benchmarks. Rationale: (a) READ-only constraint blocks adding new test scaffolding to construct theoretical worst-case state per `feedback_gas_worst_case.md`; (b) existing `test/gas/AdvanceGameGas.test.js` is explicitly listed in `feedback_gas_worst_case.md` as not enabling autorebuy / not verifying specialized events / not constructing true worst-case state, so its numbers are inadmissible as WC evidence; (c) the claimed `6b3f4f3c` changes (dropped `freshEth` return / `ethFreshWei→ethMintSpendWei` rename / removed dead branches) are STRUCTURAL — their presence is verifiable via deployed-bytecode delta without running the code. Methodology:
  1. For each contract touched by `6b3f4f3c` (`DegenerusQuests.sol`, `DegenerusGameMintModule.sol`), run `forge inspect <Contract> bytecode` against baseline `7ab515fe` AND head `cc68bfc7`
  2. Strip trailing CBOR metadata (compiler version + IPFS hash) — bytes after the metadata-length suffix per Solidity layout — before comparing to avoid noise from metadata drift
  3. Compare runtime-bytecode body length AND structural opcode patterns at the affected function offsets
  4. Map any size reduction to specific sources cited in the commit diff (dropped return path → fewer SSTORE/MSTORE/RETURN ops; rename → no body change; dead-branch removal → fewer JUMPI ops)
  5. Magnitude (-142k WC daily split / -153k WC early-burn / -76k WC terminal jackpot) is INFO commentary only — bytecode delta does NOT reproduce gas magnitude, only confirms direction (smaller / structurally cleaner)

- **D-14 (QST-05 verdict bar — DIRECTION-ONLY):** Per user discussion. SAFE = (a) bytecode delta shows the structural changes present (dropped return, rename, removed branches verifiable in opcode delta) AND (b) direction matches the claim (deployed bytecode is smaller OR opcode-pattern changes match expected savings sites) AND (c) no regression on adjacent paths (nothing got bigger that wasn't expected to). INFO = (a) structural change present but bytecode-delta ambiguous (compiler optimization may have masked or amplified the change), OR (b) magnitude commentary worth recording even with direction confirmed. INFO-unreproducible = direction can't be confirmed from bytecode delta alone (e.g., compiler optimizer reordered surrounding code so the QST-05 hunk's contribution is not isolatable). Magnitude bar (e.g., ±5% / ±20% of -142k claim) is NOT enforced — gas magnitude is unreproducible under READ-only-+-bytecode-only regime per D-13.

#### GOX (244-04)
- **D-15 (GOX adversarial vectors — fixed, planner MUST cover at minimum):**
  - **GOX-01:** (a) enumerate all 8 purchase/claim paths moved from `gameOver` → `_livenessTriggered` (cite D-243-X029 / X017 / X018 / X019 / X030 / X031 / X032 / X033 / X034 / X035 / X036 / X037 / X038 / X039 from §3); (b) confirm one-cycle-earlier cutoff is consistent with existing `_queueTickets` / scaled / range variant ticket-queue guards (cross-cite Phase 232.1 if relevant)
  - **GOX-02:** (a) `sDGNRS.burn` State-1 block (livenessTriggered fired, !gameOver) — trace every reachable path that creates a redemption; verify revert covers all of them with `BurnsBlockedDuringLiveness`; (b) `sDGNRS.burnWrapped` parallel proof; (c) close §1.7 bullet 1 + 2 (error-taxonomy ordering between livenessTriggered + rngLocked checks); (d) confirm orphan gambling-burn redemptions cannot reach `handleGameOverDrain` sweep
  - **GOX-03:** (a) `handleGameOverDrain` arithmetic — confirm `pendingRedemptionEthValue()` is read AND subtracted from available funds BEFORE the 33/33/34 split math; (b) verify SSTORE ordering and reentrancy-safety per §1.7 bullet 4; (c) cross-cite IStakedDegenerusStonk.pendingRedemptionEthValue interface row (D-243-C032) as scope hand-off
  - **GOX-04:** (a) trace `_livenessTriggered` body — verify VRF-dead 14-day grace fallback (`_VRF_GRACE_PERIOD` constant) fires liveness when day-math unmet AND VRF stalled past grace; (b) confirm fallback enables `_gameOverEntropy` prevrandao consumption per KI exception envelope (no widening)
  - **GOX-05:** (a) verify day-math evaluated FIRST in `_livenessTriggered` body — mid-drain RNG request/fulfillment gaps cannot transiently suppress liveness (b) confirm ordering matches commit-message intent
  - **GOX-06:** (a) `_gameOverEntropy` clears `rngRequestTime` on fallback commit; verify reentry surface per §1.7 bullet 3; (b) `_handleGameOverPath` checks gameOver BEFORE liveness — verify post-gameover final sweep stays reachable per §1.7 bullet 5; (c) cross-cite §1.7 bullet 8 (cc68bfc7 `jackpots` direct-handle reentrancy parity check vs delegatecall path)
  - **GOX-07:** (a) `forge inspect contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage storage-layout` at baseline + head; (b) confirm slot layout is backwards-compatible (append-only) OR explicitly intentional (no slot reorder, no type narrowing, no offset shift); (c) FAST-CLOSE expected — Phase 243 §5 D-243-S001 already verified UNCHANGED at `cc68bfc7`; GOX-07 cites that row as primary evidence

### Phase 245 Hand-Off (244-04 GOX plan)
- **D-16 (244-04 pre-flags Phase 245 SDR/GOE candidates as a dedicated plan section):** When Phase 244 GOX work reads `_livenessTriggered` / `handleGameOverDrain` / `burn` / `burnWrapped` / `_gameOverEntropy` / `_handleGameOverPath` (which it must for GOX-01..GOX-06), it captures observations relevant to Phase 245 SDR-01..08 + GOE-01..06 in a "Phase 245 Pre-Flag" subsection at the END of the GOX bucket section. Format: bullet list — `- SDR-NN | GOE-NN: <observation> | <file:line> | <suggested Phase 245 vector to test>`. Matches `audit/v31-243-DELTA-SURFACE.md` §1.7 finding-candidate format. Phase 245 plans consume this subsection as bonus pre-derived input — they are NOT bound by it (Phase 245 may surface entirely new vectors), but Phase 244 has already done the read-the-code work, so the observations carry forward.
- **D-17 (REFACTOR_ONLY behavioral-equivalence proof — side-by-side prose with named-element reasoning):** For RNG-03 (16597cac multi-line SLOAD + tuple destructuring reformat) and the QST-04 rename hunks (`ethFreshWei → ethMintSpendWei` parameter rename at the rename-hunk granularity), the verification methodology is side-by-side prose diff naming the specific source elements proven byte-equivalent (per Phase 243 D-19 evidence burden). NOT bytecode-diff — that would be expensive and may show innocuous metadata drift. Where REFACTOR_ONLY claim has any doubt (e.g., variable-ordering changed in a tuple destructuring), the doubt MUST escalate to MODIFIED_LOGIC + a separate verdict (Phase 243 D-04 burden-of-proof rule). The QST-05 bytecode-delta methodology (D-13) is NOT applied to RNG-03 / QST-04 reformat verification — those are read-the-source confirmations, not gas claims.

### Scope Boundaries
- **D-18 (READ-only scope, no `contracts/` or `test/` writes):** Carries v28/v29/v30/Phase 243 D-22 carry-forward + project-level `feedback_no_contract_commits.md` + `feedback_never_preapprove_contracts.md`. Writes confined to `.planning/phases/244-*/` + `audit/v31-244-*.md` files. `KNOWN-ISSUES.md` is NOT touched in Phase 244 — KI promotions / Non-Promotion Ledger are Phase 246 FIND-03 only.
- **D-19 (HEAD anchor `cc68bfc7` locked in every plan frontmatter):** Carries Phase 243 D-03 amended HEAD. Every `244-0N-PLAN.md` frontmatter freezes `baseline=7ab515fe`, `head=cc68bfc7`. If any FURTHER new contract commit lands before Phase 244 begins OR mid-execution, baseline resets and Phase 244 may re-open for an addendum (Phase 230 D-06 / Phase 237 D-17 / Phase 243 D-03 pattern). Phase 244 plan-start verifies HEAD has not moved past `cc68bfc7` before locking frontmatter.
- **D-20 (`audit/v31-243-DELTA-SURFACE.md` is READ-only — scope-guard deferral rule):** Per Phase 243 D-21. If any Phase 244 plan finds a changed function / state-var / event / interface method / call site NOT in the catalog, it records a scope-guard deferral in its own plan SUMMARY (file:line + path-family proposal + KI cross-ref if applicable). Phase 243 output is NOT re-edited in place. Gaps become Phase 246 finding candidates.
- **D-21 (no F-31-NN finding-ID emission — Phase 246 owns it):** Carries Phase 230 D-06 / Phase 237 D-15 / Phase 243 D-20 pattern. Phase 244 produces per-REQ verdicts + finding-candidate blocks with `SEVERITY: <bucket>` annotations; Phase 246 FIND-01 assigns F-31-NN IDs and FIND-02 may re-classify severity with full milestone context.
- **D-22 (KI exception RE_VERIFIED_AT_HEAD only — no re-litigation):** The 4 accepted RNG exceptions per `KNOWN-ISSUES.md` (affiliate non-VRF roll / prevrandao fallback / F-29-04 mid-cycle substitution / EntropyLib XOR-shift) are RE_VERIFIED at HEAD `cc68bfc7` for envelope-non-widening only. RNG-02 verifies the AIRTIGHT invariant covers the new `_gameOverEntropy rngRequestTime` clearing without widening EXC-02 / EXC-03. GOX-04 verifies the new 14-day VRF-dead grace does not widen EXC-02. RNG-01 verifies the `_unlockRng(day)` removal does not regress EXC-03 mid-cycle substitution. Acceptance is NOT re-litigated; only the envelope is re-verified per Phase 238 D-11 / Phase 241 EXC-01..04 pattern.

### Claude's Discretion
- Exact within-section ordering of per-REQ verdict tables vs prose blocks (e.g., table-first vs preamble-first per bucket section)
- Whether to inline 244-04 GOX consolidation into 244-04 SUMMARY commit OR a separate `244-04-CONSOLIDATION.md` follow-up artifact (planner may pick either; Phase 243 used a single SUMMARY commit for the consolidation)
- Whether to include a "per-REQ closure heatmap" at the top of `audit/v31-244-PER-COMMIT-AUDIT.md` (REQ × verdict matrix as a readability aid) — optional, not required
- Whether QST-05 `forge inspect bytecode` evidence is inlined in the QST section OR linked to a companion file `audit/v31-244-QST-05-BYTECODE.md` if the bytecode dump exceeds ~200 lines per contract
- Severity pre-classification for finding-candidate blocks — Phase 244 may pre-classify {SAFE / INFO / LOW / MED / HIGH / CRITICAL} or leave SEVERITY:`TBD-246` for Phase 246; recommended pre-classify per D-08 unless ambiguous
- Whether to add a one-line "change count card" at the top of each bucket section (mirroring Phase 243's D-07 §1.1..1.6 cards) for Phase 246 FIND-01 convenience — planner-discretion, not mandated
- How to format the Phase 245 Pre-Flag subsection in 244-04 (per-REQ-grouped vs per-file-grouped vs per-vector-grouped) — planner-discretion as long as every bullet has the SDR-NN/GOE-NN target + observation + file:line + suggested vector

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 243 scope anchor (MANDATORY — READ-only per D-20)
- `audit/v31-243-DELTA-SURFACE.md` — FINAL READ-only at HEAD `cc68bfc7`; the SOLE scope input
  - §1.1..§1.6 — per-commit changelog (42 D-243-C### rows) — provides commit-grouped function/state/event/interface/error inventory
  - §1.7 — 8 INFO Finding Candidates (5 from original 771893d1 sweep + 3 from cc68bfc7 addendum) — D-09 maps each candidate to its consuming Phase 244 plan
  - §1.8 — Light Reconciliation against `audit/v30-CONSUMER-INVENTORY.md` (30 INV-237 overlap rows; INV-237-035 HUNK-ADJACENT for RNG-01)
  - §2 — Aggregate function classification (26 D-243-F### rows; 2 NEW / 23 MODIFIED_LOGIC / 1 REFACTOR_ONLY / 0 DELETED / 0 RENAMED) — every Phase 244 verdict cites the relevant F-row
  - §3 — Downstream call-site catalog (60 D-243-X### rows) — caller enumeration for every changed function/interface method
  - §4 — State variable / event / error / interface inventory (continuation of D-243-C###; covers BurnsBlockedDuringLiveness error decl + JackpotWhalePassWin event + BafSkipped event + markBafSkipped interface method + jackpots constant + _VRF_GRACE_PERIOD constant + IStakedDegenerusStonk.pendingRedemptionEthValue interface)
  - §5 — Storage slot layout diff (D-243-S001 UNCHANGED at `cc68bfc7`) — primary evidence for GOX-07
  - §6 — Consumer Index (41 D-243-I### rows) — REQ-ID → 243 row subset mapping; Phase 244 plans cite their D-243-I row to inherit scope
  - §7 — Reproduction recipe appendix (all `git diff` / `git show -L` / `grep` / `forge inspect` commands)

### Milestone scope (MUST read)
- `.planning/REQUIREMENTS.md` §EVT (4 REQs) + §RNG (3 REQs) + §QST (5 REQs) + §GOX (7 REQs) — exact REQ wording + accepted RNG exceptions list (out-of-scope re-litigation)
- `.planning/ROADMAP.md` Phase 244 block — 5 Success Criteria + Depends on Phase 243 + scope-guard handoff to Phase 245/246
- `.planning/PROJECT.md` Current Milestone v31.0 — write-policy statement (READ-only) + 5 in-scope commits + accepted RNG exceptions

### In-scope commits (chronological per REQUIREMENTS.md)
- `ced654df` — fix(jackpot): emit accurate scaled ticketCount on all JackpotTicketWin paths (`DegenerusGameJackpotModule.sol` +33/-6) — EVT-01..EVT-04 anchor
- `16597cac` — rngunlock fix (`DegenerusGameAdvanceModule.sol` +6/-6) — RNG-01..RNG-03 anchor
- `6b3f4f3c` — feat(quests): credit recycled ETH toward MINT_ETH quests + earlybird DGNRS (`DegenerusQuests.sol`, `IDegenerusQuests.sol`, `DegenerusGameMintModule.sol`) — QST-01..QST-05 anchor
- `771893d1` — feat(gameover): shift purchase/claim gates to liveness + protect sDGNRS redemptions (9 files) — GOX-01..GOX-07 anchor
- `cc68bfc7` — feat(baf): gate BAF jackpot on daily flip win (`DegenerusJackpots.sol` +19, `IDegenerusJackpots.sol` +6, `DegenerusGameAdvanceModule.sol` +22/-10) — addendum scope; routes through 244-01 EVT plan per D-03

### Accepted RNG exceptions (MUST read — drive D-22 RE_VERIFIED_AT_HEAD verdicts)
- `audit/KNOWN-ISSUES.md` — 4 accepted entries:
  - "Non-VRF entropy for affiliate winner roll" (EXC-01)
  - "Gameover prevrandao fallback" `_getHistoricalRngFallback`, `DegenerusGameAdvanceModule.sol:109` + `:1252` (EXC-02) — re-verified for 14-day grace envelope by GOX-04
  - "Gameover RNG substitution for mid-cycle write-buffer tickets" F-29-04 / `_swapAndFreeze` / `_swapTicketSlot` / `_gameOverEntropy` (EXC-03) — re-verified by RNG-01 + RNG-02
  - "EntropyLib XOR-shift PRNG" (EXC-04)

### Methodology precedents (carried forward, not re-litigated)
- `.planning/milestones/v29.0-phases/231-earlybird-jackpot-audit/231-CONTEXT.md` — direct precedent for per-commit attack-vector enumeration (D-08), per-function verdict tables (D-02), no F-NN emission (D-09), scope-guard deferral (D-06); D-01/02/05/06/08/09 mirrored into D-01/06/07/08/20/21
- `.planning/milestones/v29.0-phases/232-decimator-audit/232-CONTEXT.md` — direct precedent for per-commit-bucket plan split + single consolidated AUDIT.md per phase
- `.planning/milestones/v29.0-phases/233-jackpot-baf-entropy-audit/233-CONTEXT.md` — BAF/jackpot adversarial-audit precedent (relevant for EVT plan)
- `.planning/milestones/v29.0-phases/234-quests-boons-misc-audit/234-CONTEXT.md` — quest adversarial-audit precedent (relevant for QST plan)
- `.planning/milestones/v30.0-phases/238-backward-forward-freeze-proofs/238-CONTEXT.md` — fresh re-prove + cross-cite pattern (D-09); KI-exception in-scope with EXCEPTION verdict (D-11); 4-actor adversarial closure taxonomy (D-07); D-09/11 mirrored into D-22, D-07 carry to RNG-01 actor closure
- `.planning/milestones/v30.0-phases/240-gameover-jackpot-safety/240-CONTEXT.md` — gameover-jackpot adversarial-audit precedent (relevant for GOX plan)
- `.planning/phases/243-delta-extraction-per-commit-classification/243-CONTEXT.md` — direct upstream Phase 243 CONTEXT.md (D-09 row-ID prefix scheme, D-21 scope-guard deferral, D-22 READ-only carry, D-04 5-bucket classification, D-19 evidence burden, §1.7 finding-candidate format)
- `.planning/phases/243-delta-extraction-per-commit-classification/243-03-SUMMARY.md` — Phase 243 plan-close summary; documents the §6 Consumer Index hand-off pattern Phase 244 consumes

### Prior audit outputs (light cross-reference per RE_VERIFIED_AT_HEAD pattern)
- `audit/v30-CONSUMER-INVENTORY.md` — v30.0 RNG consumer inventory; RNG-02 cites INV-237-021..037 (rngLockedFlag); SDR-08/GOE-01 (Phase 245 hand-off) cites INV-237-052..059 (F-29-04 envelope)
- `audit/FINDINGS-v30.0.md` — v30.0 17 INFO findings; REG-01 (Phase 246) regression spot-check intake
- `audit/FINDINGS-v29.0.md` — v29.0 4 INFO findings (F-29-01..04); F-29-04 cited by RNG-01 + Phase 245 SDR-08 hand-off
- `audit/STORAGE-WRITE-MAP.md` — prior storage-write catalog; GOX-07 cites for slot-layout context
- `audit/ACCESS-CONTROL-MATRIX.md` — prior access-control matrix; GOX-01 8-path enumeration cross-cites for liveness-gate consistency

### Project feedback rules (apply across all 4 plans)
- `memory/feedback_no_contract_commits.md` — READ-only scope enforcement; no `contracts/` or `test/` writes
- `memory/feedback_never_preapprove_contracts.md` — orchestrator MUST NOT pre-approve contract changes for agents
- `memory/feedback_contract_locations.md` — `contracts/` is the only authoritative source; stale copies (`contracts/ContractAddresses.sol.bak`, `degenerus-protocol/contracts/`, etc.) are NEVER read
- `memory/feedback_no_history_in_comments.md` — deliverable docs describe what IS, not what CHANGED (except where change-tracking is the entire point)
- `memory/feedback_gas_worst_case.md` — gas analysis must derive theoretical worst case FIRST, then test it; existing `test/gas/AdvanceGameGas.test.js` is INADMISSIBLE as worst-case evidence; **drives QST-05 D-13 + D-14 lock**
- `memory/feedback_rng_backward_trace.md` — every RNG audit must trace BACKWARD from each consumer to verify word was unknown at input commitment time; **drives RNG-01 backward-trace methodology**
- `memory/feedback_rng_commitment_window.md` — every RNG audit must check what player-controllable state can change between VRF request and fulfillment; **drives RNG-01 + RNG-02 commitment-window check**

### Source files at HEAD `cc68bfc7` (read directly from `contracts/` per `feedback_contract_locations.md`)
- **EVT scope:** `contracts/modules/DegenerusGameJackpotModule.sol` (ced654df) + `contracts/DegenerusJackpots.sol` (cc68bfc7) + `contracts/interfaces/IDegenerusJackpots.sol` (cc68bfc7) + `contracts/modules/DegenerusGameAdvanceModule.sol` (cc68bfc7 BAF-coupling hunks)
- **RNG scope:** `contracts/modules/DegenerusGameAdvanceModule.sol` (16597cac)
- **QST scope:** `contracts/DegenerusQuests.sol` (6b3f4f3c) + `contracts/interfaces/IDegenerusQuests.sol` (6b3f4f3c) + `contracts/modules/DegenerusGameMintModule.sol` (6b3f4f3c)
- **GOX scope:** `contracts/DegenerusGame.sol` + `contracts/StakedDegenerusStonk.sol` + `contracts/interfaces/IDegenerusGame.sol` + `contracts/interfaces/IStakedDegenerusStonk.sol` + `contracts/modules/DegenerusGameAdvanceModule.sol` + `contracts/modules/DegenerusGameGameOverModule.sol` + `contracts/modules/DegenerusGameMintModule.sol` + `contracts/modules/DegenerusGameWhaleModule.sol` + `contracts/storage/DegenerusGameStorage.sol` (all 771893d1)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **Phase 243 §6 Consumer Index** — pre-derived REQ-ID → row-subset mapping; Phase 244 plans cite their D-243-I row instead of re-discovering scope (e.g., GOX-01 plan cites D-243-I016 to inherit the 8-path call-site enumeration from §3 X029..X039 + X042..X049)
- **Phase 243 §1.7 Finding Candidates** — 8 INFO bullets pre-flagged at phase-context time; D-09 maps each candidate to its consuming Phase 244 plan, saving re-discovery work
- **Phase 243 §1.8 Light Reconciliation table** — 30 INV-237 overlap rows pre-classified as `function-level-overlap` / `REFORMAT-TOUCHED` / `HUNK-ADJACENT`; RNG-02 inherits the rngLockedFlag overlap analysis directly
- **v29.0 Phase 231 `231-01-EARLYBIRD-AUDIT.md`** — direct format precedent for per-commit AUDIT.md (per-function verdict table + finding-candidate prose blocks); Phase 244 follows the same shape
- **v30.0 Phase 240 `240-01-GO-INVENTORY.md`** — direct format precedent for gameover-jackpot adversarial audit; GOX plan inherits the path-family enumeration shape
- **`audit/` directory** — established v29-v31 namespace conventions; `v31-244-*` namespace is fresh (zero collisions)
- **Existing Makefile gates** — `check-interfaces`, `check-delegatecall`, `check-raw-selectors` already enforce interface↔implementation alignment; Phase 244 does NOT duplicate these gates (verification artifacts), only audits the new code surface

### Established Patterns
- **HEAD anchor in plan frontmatter** — Phase 230 D-06 / Phase 237 D-17 / Phase 243 D-03; applied as D-19
- **READ-only scope on audit milestones** — v28/v29/v30/Phase 243 D-22 carry; applied as D-18
- **No finding-ID emission in audit phases** — Phase 230 D-06 / Phase 237 D-15 / Phase 243 D-20; applied as D-21
- **Scope-guard deferral rule** — downstream phases record deferrals instead of editing prior-phase output; applied as D-20
- **Single-file consolidated deliverable** — Phase 230 D-05 / Phase 237 D-08 / Phase 243 D-07; applied as D-04 + D-05
- **Tabular grep-friendly, no mermaid** — Phase 230 D-08 / Phase 237 D-09 / Phase 243 D-08; applied as D-06
- **Per-REQ closure with attack-vector enumeration** — v29.0 Phase 231 D-08; applied as D-07 + D-10/11/12/15
- **KI exception RE_VERIFIED only** — Phase 238 D-11 / Phase 241 EXC-01..04; applied as D-22
- **Pre-flag downstream-phase candidates** — Phase 243 §1.7 carry; applied as D-09 (consume) + D-16 (emit forward)

### Git Infrastructure (verified 2026-04-24 via Phase 243 §7)
- `git show -L <start>,<end>:<file> 7ab515fe` and `cc68bfc7` for per-commit hunk inspection (cited per Phase 243 §7.2 reproduction recipe)
- `grep -rn` portable POSIX syntax for call-site enumeration (Phase 243 §7.3 reproduction recipe)
- `forge inspect <Contract> bytecode` for QST-05 deployed-bytecode delta + GOX-07 storage-layout verification
- `git diff --stat 7ab515fe..cc68bfc7 -- contracts/` → 14 files / +187 / -67 (verified at Phase 243 close)

### Module Map (for adversarial vector enumeration per D-10/11/12/15)
- **DegenerusGameJackpotModule** (EVT) — emits JackpotTicketWin in `_runEarlyBirdLootboxJackpot`, `_distributeTicketsToBucket`, `runBafJackpot`, `_jackpotTicketRoll`; new JackpotWhalePassWin in `_awardJackpotTickets`
- **DegenerusGameAdvanceModule** (RNG + cc68bfc7 BAF) — hosts `advanceGame`, `_unlockRng`, `_handleGameOverPath`, `_gameOverEntropy`, `_livenessTriggered`, `_consolidatePoolsAndRewardJackpots`; new `jackpots` constant + `markBafSkipped` invocation
- **DegenerusQuests + DegenerusGameMintModule + IDegenerusQuests** (QST) — `handlePurchase` (sig change), `_callTicketPurchase` (return drop), `_purchaseFor` (gross-spend semantics), `recordMint` (recycled-ETH credit)
- **DegenerusGame + StakedDegenerusStonk + IDegenerusGame + IStakedDegenerusStonk + AdvanceModule + GameOverModule + MintModule + WhaleModule + DegenerusGameStorage** (GOX) — 9-file `771893d1` surface; `livenessTriggered` external view; `burn` + `burnWrapped` State-1 block; `handleGameOverDrain` arithmetic; `_livenessTriggered` body; `pendingRedemptionEthValue` interface

### Integration Points
- `audit/v31-244-PER-COMMIT-AUDIT.md` is the scope anchor for:
  - **Phase 245** (sDGNRS + gameover safety) — consumes 244-04's "Phase 245 Pre-Flag" subsection per D-16; SDR/GOE plans use Phase 244 GOX verdicts as pre-derived input
  - **Phase 246** (findings consolidation) — Phase 244 verdicts + finding-candidate blocks become FIND-01 intake; SEVERITY pre-classifications become FIND-02 floor; KI re-verification verdicts become REG-01 spot-check inputs
- Verdict Row IDs (e.g., GOX-04-V01) flow as stable citations into Phase 245/246 plan files

</code_context>

<specifics>
## Specific Ideas

- **Verdict Row ID scheme suggestion:** `<REQ-ID>-V###` zero-padded — e.g., `GOX-04-V01`, `EVT-02-V03`, `QST-05-V01`. Per-REQ monotonic. Multi-vector REQs produce multiple V rows; cross-cite REQs (per D-07) reference the source row's V-ID. Planner may flatten to milestone-wide `V-244-NNN` if cleaner; must be consistent and documented in Section 0 legend of the consolidated deliverable.
- **Reproduction recipe appendix is part of the deliverable** — not a separate file. Carries v25/v29/v30/Phase 243 reproducibility commitment forward; reviewer can replay Phase 244 from shell.
- **QST-05 bytecode comparison snippet** — recommend including the exact `forge inspect` command + the bytewise diff command (`diff <(forge inspect ... | sed 's/a165627a7a72/...METADATA-BREAK/' | head -c -90) ...`) in the QST section's evidence appendix so a reviewer can replay without hunting for the metadata-strip incantation.
- **Per-bucket "verdict count card"** — one-line summary per bucket (e.g., "EVT: 4 REQs / 7 V-rows / 0 finding-candidates") at the top of each bucket section is planner-discretion but recommended for Phase 246 FIND-01 intake convenience.

</specifics>

<deferred>
## Deferred Ideas

- **Differential-fuzz QST-05 reproduction** — the gold-standard methodology (running both baseline + head test suites under controlled state to measure actual gas delta) is blocked by READ-only constraint. Out of v31.0 scope; flag as future-milestone candidate (e.g., a separate v32.0 "gas-claim verification" milestone where READ-only is lifted for `test/` only).
- **Cross-milestone severity calibration sweep** — Phase 244's SEVERITY discrimination bar (D-08) is calibrated against v29.0 Phase 236 + v30.0 Phase 242. A formal cross-milestone severity-rubric standardization (e.g., a Codex of Severity rules) is out of v31.0 scope; could be a future audit-tooling milestone.
- **Bytecode-delta automated CI gate** — wiring the QST-05 bytecode-diff methodology into a CI check (e.g., a script that re-runs `forge inspect bytecode` per PR) is out of READ-only v31.0 scope. Future-milestone candidate.
- **Phase 245 Pre-Flag → SDR/GOE plan inheritance protocol** — D-16 leaves the consumption pattern to Phase 245's CONTEXT (whether Phase 245 plans copy the pre-flag bullets verbatim or derive their own from scratch with pre-flag as advisory). Defer to Phase 245 CONTEXT discussion.

</deferred>

---

*Phase: 244-per-commit-adversarial-audit-evt-rng-qst-gox*
*Context gathered: 2026-04-24*
