# Phase 314 Adversarial-Pass Charge — v45.0 VRF-Rotation Liveness Fix + Consolidate-Forward Delta

**Phase:** 314-sweep-3-skill-adversarial-degenerette-audit-sweep
**Plan:** 01
**Authored:** 2026-05-23
**Audit baseline:** v44.0 closure HEAD `MILESTONE_V44_AT_HEAD_6f0ba2963a10654ba554a8c333c5ee80c54a8349`
**Subject under probe:** v45.0 audit-subject HEAD — post-Phase 312 IMPL (`a303ae18` VRF-rotation fix) + post-Phase 313 TST (VTST-01..04 coverage)
**Composition:** `/contract-auditor` SEQUENTIAL_MAIN_CONTEXT FIRST + `/zero-day-hunter` + `/economic-analyst` PARALLEL_SUBAGENT (HYBRID-fallback to SEQUENTIAL_MAIN_CONTEXT allowed) per D-302-INVOKE-01 / D-10.
**Out-of-scope skills:** `/degen-skeptic` (D-271-ADVERSARIAL-02 carry).
**In-scope skills:** `/economic-analyst` (D-271-ADVERSARIAL-03 carry).

---

## §0 Charge-Frame

### Composition and sequencing (D-302-INVOKE-01 carry / CONTEXT D-10)

- **Task 2 `/contract-auditor`** — SEQUENTIAL_MAIN_CONTEXT in the orchestrator's main context (NOT via Task subagent). Runs to completion FIRST so its disposition MD anchors the parallel hunter + economist pair. DGAUD-01..04 is **folded into this skill's scope** per D-05 (a section of the auditor MD + a section of the integrated LOG — NOT a separate `degenerette-audit-note` file).
- **Tasks 3 + 4 `/zero-day-hunter` + `/economic-analyst`** — PARALLEL_SUBAGENT spawned via a single-message multi-Task block (two `Task` tool calls in one message). Both receive the auditor MD as anchoring context (avoids redundant rediscovery; forces cross-skill coverage divergence). **D-10 mechanics:** parallel dispatch is attempted ONLY if the executor genuinely has the Task tool; the standard fallback per v42 P296 / v43 P302 / v44 P307 is HYBRID_FALLBACK_SEQUENTIAL. The Phase 314 executor runs in the main orchestrator context, which DOES hold the Task tool, so PARALLEL_SUBAGENT is the planned mode. The chosen mode is recorded in each per-skill MD `[invocation]` frontmatter.
- **HYBRID-fallback allowance** — If parallel-subagent dispatch fails (subagent crash, malformed output, timeout, persona drift) for either parallel skill, fall back to SEQUENTIAL_MAIN_CONTEXT for that skill and document `mode: HYBRID_FALLBACK_SEQUENTIAL` + reason in the per-skill MD `[invocation]` frontmatter. Persona fidelity preserved via the dedicated per-skill MD carrying the verbatim CHARGE either way.

### Two-tier consensus rule (D-302-CONSENSUS-01 carry)

- **Tier-1** — Any single skill's `FINDING_CANDIDATE` that survives the dual-gate skeptic filter → AskUserQuestion user-pause at Task 5 integration time. User adjudicates (elevate / SAFE_BY_DESIGN / NEGATIVE-VERIFIED-on-reconsideration). This is the sensitive-contract boundary per `feedback_pause_at_contract_phase_boundaries.md`.
- **Tier-2** — 3-of-3 cross-skill consensus `FINDING_CANDIDATE` on the same hypothesis → automatic elevation + RE-PASS per `D-284-ADVERSARIAL-RE-PASS-01` (no user-pause for the elevation itself; user diff review still required for any `contracts/*.sol` change per `feedback_manual_review_before_push.md`).
- **unanimous-NEGATIVE** — No surviving `FINDING_CANDIDATE` from any skill → no elevation, no user-pause. Task 6 precondition gate fails; phase proceeds directly to Task 7. **This is the EXPECTED outcome** per the lean-verification-formality posture (cf. v42 P296 / v43 P302 / v44 P307 — 72/72 rows unanimous-NEGATIVE).

### 3-classification disposition rubric

Per-hypothesis verdict ∈ {`NEGATIVE-VERIFIED`, `FINDING_CANDIDATE`, `SAFE_BY_DESIGN`} crossed with per-skill source ∈ {`/contract-auditor`, `/zero-day-hunter`, `/economic-analyst`}. Each row is recorded in §1 of the per-skill MD and aggregated at Task 5 into `314-01-ADVERSARIAL-LOG.md`.

- **NEGATIVE-VERIFIED** — Hypothesis was probed concretely (file:line trace through current source) and found unreachable / non-exploitable / structurally closed. Cite the structural protection.
- **FINDING_CANDIDATE** — Hypothesis surfaces a reachable-by-attacker exposure with a concrete attack narrative + (b)/(c) EV-lens signal. Must carry a severity tag from {CATASTROPHE, HIGH, MEDIUM, LOW, N-A}.
- **SAFE_BY_DESIGN** — Hypothesis points at a design choice the protocol intentionally made (e.g., admin-gated freeze-exempt rotation per D-03, accepted off-chain-indexer convention per D-06). Cite the decision / design rationale.

> **Posture:** lean **verification-formality** with FULL disposition enumeration, expecting unanimous-NEGATIVE. The genuinely-new contract surface is the VRF re-issue code (`a303ae18`); everything else (V-081, jackpot pending-pool, degenerette removal) is re-attestation of already-landed deltas. The bar is rigorous full enumeration, NOT adversarial over-reach.

---

## SWP-01 — VRF-rotation fix red-team (§1; charged to `/contract-auditor` SEQUENTIAL_MAIN_CONTEXT)

### SWP-01 verbatim charge (quoted from `.planning/REQUIREMENTS.md:84`)

> **SWP-01**: Red-team the VRF-rotation fix — rotation-spam / stuck-pending / double-request griefing, a new liveness-DoS, a new freeze violation, or a `wireVrf`-lock that breaks a legitimate ops path. RE-PASS per `D-284-ADVERSARIAL-RE-PASS-01` if a candidate materialises.

### Charge framing per CONTEXT D-01..D-04

The genuinely-new contract surface is the `updateVrfCoordinatorAndSub` detect-preserve-re-issue rework + the `_setVrfConfig` (internal) / `_requestVrfWord` (private) helpers, landed at `a303ae18`. The auditor red-teams the post-fix state machine for rotation-spam, stuck-pending, double-request, liveness-DoS, and freeze-violation vectors. The four phase-specific disposition rows below are MANDATED.

#### SWP-01.A — wireVrf constructor-only-reachable RE-PROOF (D-04 — DROP stale charge, KEEP re-proof)

The ROADMAP SWP-01 charge line *"a `wireVrf`-lock that breaks a legitimate ops path"* is **STALE and is DROPPED per D-04** — the landed fix `a303ae18` intentionally OMITTED the `wireVrf` init-only lock (SPEC D-03 / VRF-04, user-approved), on the claim that `wireVrf` is reachable only from the `DegenerusAdmin` constructor. **There is no lock to break.** The red-team instead RE-PROVES the "wireVrf is constructor-only-reachable" call-graph claim — MANDATORY per `feedback_verify_call_graph_against_source.md` ("by construction" claims are exactly what gets attacked). Required disposition: a SWP-01.A SAFE_BY_DESIGN/NEGATIVE-VERIFIED row that grep-traces ALL callers of `wireVrf` across the contract tree and confirms only the `DegenerusAdmin` constructor reaches it (the `:503` ADMIN guard is the runtime backstop).

**Evidence anchors:**
- `contracts/modules/DegenerusGameAdvanceModule.sol:488-493` — NatSpec: *"Deploy-only VRF setup called from the ContractAddresses.ADMIN constructor … No post-deploy caller exists on ADMIN"* (the D-04 claim under re-proof).
  - **grep:** `grep -nE 'Deploy-only|No post-deploy' contracts/modules/DegenerusGameAdvanceModule.sol` → `488:      |  Deploy-only VRF setup called from the ContractAddresses.ADMIN constructor.` + `493:    /// @dev Access: ContractAddresses.ADMIN only. No post-deploy caller exists on ADMIN;`
- `contracts/modules/DegenerusGameAdvanceModule.sol:498` — `function wireVrf(`
  - **grep:** `grep -nE 'function wireVrf' contracts/modules/DegenerusGameAdvanceModule.sol` → `498:    function wireVrf(`
- `contracts/modules/DegenerusGameAdvanceModule.sol:503` — `if (msg.sender != ContractAddresses.ADMIN) revert E();`
  - **grep:** `grep -nE 'msg\.sender != ContractAddresses\.ADMIN' contracts/modules/DegenerusGameAdvanceModule.sol` → `503` + `1717`
- `contracts/modules/DegenerusGameAdvanceModule.sol:506` — `_setVrfConfig(coordinator_, subId, keyHash_);` (wireVrf's only body action; no state beyond config).
- §9d.4 ADMA-01 (`wireVrf` seal) — the maximalist-catalog anchor this re-proof retires for v45.

#### SWP-01.B — rotation-spam (D-03 — SAFE_BY_DESIGN row, KEEP, do NOT drop)

`updateVrfCoordinatorAndSub` is ADMIN-only (`:1717`) and admin rotation is freeze-EXEMPT per `v45-vrf-freeze-invariant`, so player-driven rotation-spam is structurally impossible. **Keep the ROADMAP "rotation-spam griefing" line as an explicit SWP-01.B SAFE_BY_DESIGN disposition row** (admin-gated + freeze-exempt) — enumerate-everything precedent (v44 P307's 72-row table). Do NOT drop it.

**Evidence anchors:**
- `contracts/modules/DegenerusGameAdvanceModule.sol:1712` — `function updateVrfCoordinatorAndSub(`
  - **grep:** `grep -nE 'function updateVrfCoordinatorAndSub' contracts/modules/DegenerusGameAdvanceModule.sol` → `1712`
- `contracts/modules/DegenerusGameAdvanceModule.sol:1717` — `if (msg.sender != ContractAddresses.ADMIN) revert E();` (the rotation ADMIN guard).
- `v45-vrf-freeze-invariant` — admin rotation is freeze-EXEMPT; rotation is not player-reachable.

#### SWP-01.C — LINK-funding-order SPOT-CHECK (D-01 — SAFE_BY_DESIGN row, NOT a deep trace)

The re-issue fires `requestRandomWords` on the NEW coordinator BEFORE LINK lands; the diff comment (`:1722-1725`) asserts `DegenerusAdmin` funds it atomically in the same `_executeSwap` tx via `transferAndCall`, and VER-01 was resolved at IMPL. The red-team **confirms `DegenerusAdmin` funds same-tx at `:911` and records SAFE_BY_DESIGN** — it does NOT perform a deep cross-contract `_executeSwap` trace. The documented rationale carries it; `retryLootboxRng` (`:1131`) is the standing failsafe if the new coordinator stalls.

**Evidence anchors:**
- `contracts/DegenerusAdmin.sol:859` — `function _executeSwap(uint256 proposalId) internal {`
  - **grep:** `grep -nE 'function _executeSwap' contracts/DegenerusAdmin.sol` → `859`
- `contracts/DegenerusAdmin.sol:894` — `IVRFCoordinatorV2_5Owner(newCoordinator).addConsumer(` (add consumer on the new coordinator).
- `contracts/DegenerusAdmin.sol:901` — `gameAdmin.updateVrfCoordinatorAndSub(` (dispatch — fires the re-issue on the new coordinator).
- `contracts/DegenerusAdmin.sol:911` — `linkToken.transferAndCall(` (same-tx LINK funding — D-01 SAFE_BY_DESIGN, NOT a deep trace).
  - **grep:** `grep -nE 'addConsumer\(|updateVrfCoordinatorAndSub\(|transferAndCall\(' contracts/DegenerusAdmin.sol` → `894` / `901` / `911` (+ `997` second transferAndCall in a non-rotation path).
- `contracts/modules/DegenerusGameAdvanceModule.sol:1131` — `function retryLootboxRng()` (standing failsafe).

#### SWP-01.D — daily/mid-day exclusivity (D-02 — red-team DISCRETION: standalone-row-if-warranted)

The re-issue branch precedence is `if (LR_MID_DAY) {re-issue mid-day} else if (rngLockedFlag) {re-issue daily if rngWordCurrent==0} else {nothing in flight → config repoint only}` — mid-day wins, so a daily re-issue is skipped when `LR_MID_DAY` is set (VER-03 exclusivity is the load-bearing assumption). The red-team gives this a **standalone hypothesis row** *("can both LR_MID_DAY and rngLockedFlag be set so a daily word is silently dropped → permanent post-rotation freeze?")* ONLY IF tracing the `LR_MID_DAY` / `rngLockedFlag` set-clear sites shows it warrants one; otherwise it folds into the general freeze-invariant disposition. Treat the invariant as attackable, not assumed (`feedback_verify_call_graph_against_source.md`). Red-team discretion is explicit per D-02.

**Evidence anchors:**
- `contracts/modules/DegenerusGameAdvanceModule.sol:1720` — `_setVrfConfig(newCoordinator, newSubId, newKeyHash);` (re-point first).
- `contracts/modules/DegenerusGameAdvanceModule.sol:1726` — `if (_lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK) != 0) {` (mid-day branch; KEEP LR_MID_DAY=1; `:1729 vrfRequestId = _requestVrfWord(VRF_MIDDAY_CONFIRMATIONS)`).
- `contracts/modules/DegenerusGameAdvanceModule.sol:1731` — `} else if (rngLockedFlag) {` (daily branch; `:1733 if (rngWordCurrent == 0)` → `:1735 _requestVrfWord(VRF_REQUEST_CONFIRMATIONS)`; else preserve delivered word).
- `contracts/modules/DegenerusGameAdvanceModule.sol:1741` — `// else: nothing in flight -> config repoint only; no re-issue, no flag change.`
  - **grep:** `grep -nE 'LR_MID_DAY_SHIFT|rngLockedFlag|rngWordCurrent == 0' contracts/modules/DegenerusGameAdvanceModule.sol` → set/clear sites at `209/225` (advance), `1046/1095/1132` (mid-day request guards), `1669/1774` (daily lock set/clear), `1726/1731/1733` (rotation re-issue branch).
- LR_MID_DAY / rngLockedFlag set-clear trace targets: `:1669` (`rngLockedFlag = true`), `:1774` (`_unlockRng` clears), `:1095` (`_lrWrite(LR_MID_DAY_SHIFT,…,1)`), `:225` (`_lrWrite(LR_MID_DAY_SHIFT,…,0)`).

#### SWP-01.E — stuck-pending / double-request / freeze re-break (the :1793 abandoned-word guard)

The freeze-safe boundary: `rawFulfillRandomWords` rejects a stale (pre-rotation) callback via the `:1793` guard. RE-PROVE the consumed-this-cycle word is the FRESH re-issued one; no in-flight VRF-participating slot mutation mid-window changes an output (cf. `v45-vrf-freeze-invariant`).

**Evidence anchors:**
- `contracts/modules/DegenerusGameAdvanceModule.sol:1788` — `function rawFulfillRandomWords(`
  - **grep:** `grep -nE 'function rawFulfillRandomWords' contracts/modules/DegenerusGameAdvanceModule.sol` → `1788`
- `contracts/modules/DegenerusGameAdvanceModule.sol:1792` — `if (msg.sender != address(vrfCoordinator)) revert E();` (coordinator-only).
- `contracts/modules/DegenerusGameAdvanceModule.sol:1793` — `if (requestId != vrfRequestId || rngWordCurrent != 0) return;` (the freeze-safe stale-word-abandoned guard — grounds the D-03 + freeze re-break disposition).
  - **grep:** `grep -nE 'requestId != vrfRequestId' contracts/modules/DegenerusGameAdvanceModule.sol` → `1793`
  - **note:** internal comments at `:1728`/`:1739` reference stale line-refs `:1761`/`:1772` for this guard / the mid-day branch; the live guard is `:1793` and the mid-day fulfillment branch is `:1801` — cosmetic comment doc-drift in already-landed code, ZERO behavioral impact (informational observation, not a finding; contracts are frozen).
- `contracts/modules/DegenerusGameAdvanceModule.sol:1849` — `function _backfillOrphanedLootboxIndices(uint256 vrfWord) private` (orphan-index backfill — the SWP-01 headline surface the v45 fix closes).
- `contracts/modules/DegenerusGameAdvanceModule.sol:1622` — `_requestVrfWord(uint16 confirmations) private` ; `:1639` — `_setVrfConfig(address coord, uint256 sub, bytes32 key) internal` (the two new helpers).
- §9d.2 VRF-cluster anchors HANDOFF-78/85/87/89/91 (freeze) + 86/88/90 (wireVrf lock) + §9d.4 ADMA-02 (rotation vault-routed reach) — maximalist-catalog context, NOT live player vectors per `project_rnglock_audit_disposition`.

---

## SWP-02 — Consolidated-delta composition pass (§2; charged to ALL 3 skills)

### SWP-02 verbatim charge (quoted from `.planning/REQUIREMENTS.md:85`)

> **SWP-02**: Composition pass across the consolidated delta surfaces — V-081 allocation/packing, jackpot pending-pool obligations, degenerette removal — any cross-surface composition attack or differential behaviour an attacker can game.

### Charge framing per CONTEXT D-09 (standard enumerate-and-dispose, no special framing)

Cross-surface composition across the three landed deltas. Each skill probes its lens; the economist adds beyond-charge MEV / coordination rows.

#### SWP-02.V081 — V-081 EV-cap allocation/packing (`9bcd582d`)

Bonus-only cap + frozen-at-deposit apply. Probe packing-collision (does writing one packed field corrupt an adjacent one?), cap-accounting differential behaviour, and EV-positive deposit/open ordering (economist lens).

**Evidence anchors:**
- `contracts/storage/DegenerusGameStorage.sol:1387` — `function _packLootboxPurchase(uint16 scorePlus1, uint64 adj, uint24 baseLevelPlus1)`
  - **grep:** `grep -nE 'function _packLootboxPurchase|function _unpackLootboxPurchase' contracts/storage/DegenerusGameStorage.sol` → `1387` / `1396`
- `contracts/storage/DegenerusGameStorage.sol:1396` — `function _unpackLootboxPurchase(uint256 word)`
- `contracts/storage/DegenerusGameStorage.sol:1442` — `mapping(uint48 => mapping(address => uint256)) internal lootboxPurchasePacked;`
- `contracts/storage/DegenerusGameStorage.sol:1491` — `internal lootboxEvBenefitUsedByLevel;` (per-(player, level) cap accumulator).
- `contracts/modules/DegenerusGameLootboxModule.sol:433` — `function _applyEvMultiplierWithCap(` ; `:442` `if (evMultiplierBps <= LOOTBOX_EV_NEUTRAL_BPS) {` (bonus-only early-return); `:458` `adjustedPortion = amount > remainingCap ? remainingCap : amount;` ; `:462` `lootboxEvBenefitUsedByLevel[player][lvl] = usedBenefit + adjustedPortion;` (cap advance).
  - **grep:** `grep -nE 'function _applyEvMultiplierWithCap|function openLootBox' contracts/modules/DegenerusGameLootboxModule.sol` → `433` / `477`
- `contracts/modules/DegenerusGameLootboxModule.sol:477` — `function openLootBox(address player, uint48 index) external {` ; `:504` reads `lootboxPurchasePacked[index][player]`; `:533` `lootboxPurchasePacked[index][player] = 0;` (whole-word zero-at-open).

#### SWP-02.JACKPOT — jackpot pending-pool yield-surplus obligations (`6e5acd7e` + regression `f3e21064`)

Confirm `prizePoolPendingPacked` is now in the `distributeYieldSurplus` obligations so pending ETH cannot be misread as yield surplus / over-distributed. Probe over/under-distribution game-theory (economist lens) + solvency surface.

**Evidence anchors:**
- `contracts/modules/DegenerusGameJackpotModule.sol:732` — `function distributeYieldSurplus(uint256 rngWord) external {`
  - **grep:** `grep -nE 'function distributeYieldSurplus' contracts/modules/DegenerusGameJackpotModule.sol` → `732`
- `contracts/modules/DegenerusGameJackpotModule.sol:735` — `uint256 obligations = _getCurrentPrizePool() +` (obligations base).
- `contracts/modules/DegenerusGameJackpotModule.sol:742-747` — `// freeze-window revenue lands in balance but routes to prizePoolPendingPacked` … `obligations += uint256(pNext) + uint256(pFuture);` (the fix — pending pool now in obligations).
- `contracts/modules/DegenerusGameJackpotModule.sol:749` — `if (totalBal <= obligations) return;` ; `:751` `uint256 yieldPool = totalBal - obligations;` (no over-distribution).

#### SWP-02.DEGEN — degenerette removal composition (`92b110bf`)

Any cross-surface composition or differential-behaviour attack arising from the degenerette refactor (the on-chain leaderboard tracking removal). Anchors below (folded into the DGAUD section per D-05).

---

## DGAUD-01..04 — Degenerette refactor audit (§3; FOLDED into `/contract-auditor` per D-05)

> **Placement (D-05):** DGAUD-01..04 are charged INTO the `/contract-auditor` scope alongside SWP-02 with a single integrated disposition table. The degenerette coverage becomes a **section of the auditor MD + a section of `314-01-ADVERSARIAL-LOG.md`, NOT a separate `degenerette-audit-note` file** — a deliberate deviation from the ROADMAP wave-shape phrase "+ degenerette-audit-note bundle".

### DGAUD-01..04 verbatim charges (quoted from `.planning/REQUIREMENTS.md:61-64`)

> **DGAUD-01**: The `92b110bf` storage-slot shift (removal of `playerDegeneretteEthWagered` + `topDegeneretteByLevel`) is confirmed safe pre-deploy — full-suite recompile clean; no storage collision with any retained slot.
> **DGAUD-02**: `dailyHeroWagers` (the Jackpot RNG hero-override input) write-path is byte-identical after the refactor — removing the per-player/per-level tracking did not alter hero-wager accounting.
> **DGAUD-03**: No dangling references to the removed mappings/views remain in `contracts/` or interfaces; off-chain leaderboard reconstruction from `BetPlaced` events is viable (events still emitted with the required fields).
> **DGAUD-04**: Backlog rows touching the degenerette surface are re-verified against the refactored module — HANDOFF-01..03 (S-02 `dailyHeroWagers`), HANDOFF-18 (V-031 prizePool degenerette-bet), HANDOFF-81 (V-142 `degeneretteBets`), HANDOFF-82 (V-147 `prizePoolPendingPacked` frozen-branch) — disposition updated.

### Locked disposition BARS

- **DGAUD-01 — DETERMINISTIC (D-08):** `forge build` recompile-clean + storage-slot-shift safe + dangling-ref grep ZERO. The audit RUNS `forge build` (records recompile-clean) and the dangling-ref grep (records ZERO). Pre-confirmed clean at HEAD; the audit RE-ATTESTS.
- **DGAUD-02 — BEHAVIORAL identity, NOT literal bytes (D-07):** The ROADMAP says `dailyHeroWagers` "byte-identical", but `92b110bf` de-indented the block and dropped an enclosing `{}` scope when it removed the sibling per-player/per-level block. Attest **semantic/behavioral identity** — the day / heroSymbol(heroQuadrant) / wagerUnit / pack-unpack SSTORE computation at `:489-497` is unchanged (whitespace + scope-brace removal only). Literal byte-identity would spuriously "fail". Use `git show 92b110bf -- contracts/modules/DegenerusGameDegeneretteModule.sol` as the diff substrate.
- **DGAUD-03 — VIABLE-IN-PRINCIPLE, index→level convention ACCEPTED, NOT escalated (D-06):** Confirm `BetPlaced` (`:480`) still fires on every ETH bet path carrying **player + 128-bit amount** (`packed` holds the amount; `player` is indexed). The removed `topDegeneretteByLevel` was keyed by **game level**, and only the lootbox `index` (not `level`) is in the event — the **index→level derivation is an ACCEPTED off-chain-indexer convention, NOT a finding**. Do NOT escalate the level-recoverability gap to a FINDING_CANDIDATE; it is the user's own off-chain-leaderboard design.
- **DGAUD-04 — re-verify, expected carry-forward (D-08):** Re-verify HANDOFF-01/02/03 (S-02 `dailyHeroWagers`) + HANDOFF-18 (V-031 prizePool degenerette-bet) + HANDOFF-81 (V-142 `degeneretteBets`) + HANDOFF-82 (V-147 `prizePoolPendingPacked` frozen-branch) against the refactored module. Expected disposition: the refactor surface does not intersect these anchors (`dailyHeroWagers` / prizePool / pending all untouched), so dispositions carry forward.

**Evidence anchors:**
- `contracts/modules/DegenerusGameDegeneretteModule.sol:69` — `event BetPlaced(` (DGAUD-03 off-chain reconstruction fields — player indexed + packed 128-bit amount).
  - **grep:** `grep -nE 'event BetPlaced|emit BetPlaced|function _placeDegeneretteBet|dailyHeroWagers' contracts/modules/DegenerusGameDegeneretteModule.sol` → `69` (event) / `405` (`_placeDegeneretteBet`) / `437` (`_placeDegeneretteBetCore`) / `480` (emit) / `489` (read) / `497` (write) / `810` (ledger comment)
- `contracts/modules/DegenerusGameDegeneretteModule.sol:405` — `function _placeDegeneretteBet(`
- `contracts/modules/DegenerusGameDegeneretteModule.sol:480` — `emit BetPlaced(player, uint32(index), nonce, packed);` (fires on every ETH bet path).
- `contracts/modules/DegenerusGameDegeneretteModule.sol:489` — `uint256 wPacked = dailyHeroWagers[day][heroQuadrant];` (DGAUD-02 read).
- `contracts/modules/DegenerusGameDegeneretteModule.sol:497` — `dailyHeroWagers[day][heroQuadrant] = wPacked;` (DGAUD-02 write — BEHAVIORAL identity attested per D-07).
- **DGAUD-01/03 dangling-ref grep (PRE-CONFIRMED ZERO at HEAD):**
  - **grep:** `grep -rnE "playerDegeneretteEthWagered|topDegeneretteByLevel|getPlayerDegeneretteWager|getTopDegenerette" contracts/` → **ZERO matches** (verified 2026-05-23).
- §9d DGAUD-04 re-verify set: HANDOFF-01/02/03 (S-02 `dailyHeroWagers`), HANDOFF-18 (V-031), HANDOFF-81 (V-142 `degeneretteBets`), HANDOFF-82 (V-147 `prizePoolPendingPacked` frozen-branch) — `audit/FINDINGS-v44.0.md` §9d.

---

## §4 Dual-gate skeptic-reviewer filter protocol (D-314-SKEPTIC-FILTER-01, operationalizing `feedback_skeptic_pass_before_catastrophe.md`)

### Filter location: dual gate

1. **Per-skill self-filter** — Each skill applies the filter to its own `FINDING_CANDIDATE` set BEFORE writing its per-skill MD. Discards documented in a "Skeptic-Filter Self-Discarded" subsection within the MD AND in the `[skeptic-filter]` frontmatter `discarded: []` array.
2. **Orchestrator integration-time re-application** — At Task 5 (integration), the orchestrator re-applies the filter against the aggregated `FINDING_CANDIDATE` set across all 3 skill MDs (the UNION). Integration-time discards are documented inline in `314-01-ADVERSARIAL-LOG.md` Skeptic-Filter Discarded table. **This re-application happens BEFORE any AskUserQuestion user-pause.**

### Structural-protection arm: STRICT

A finding is discarded under the structural-protection arm **only** if the code path makes the attack **literally physically unreachable** — e.g.:
- The `:503` / `:1717` `ContractAddresses.ADMIN` guards make `wireVrf` / `updateVrfCoordinatorAndSub` unreachable by any player (admin-gated).
- The `:1793` `requestId != vrfRequestId || rngWordCurrent != 0` guard makes a stale (pre-rotation) callback literally inert (`return`).
- The type system forbids the input.

**Defense-in-depth alone (ACL gate + downstream secondary check) does NOT pass the strict structural arm** — those findings surface to user-pause.

### 3-condition EV lens

- **(a)** attacker controls the necessary state;
- **(b)** the manipulation produces a measurable economic gain;
- **(c)** the gain exceeds gas cost + opportunity cost + risk cost.

**(a) is the ONLY hard discard condition.** If the attacker does NOT control the necessary state, the filter discards the finding (no exploitable scenario can be constructed). **(b) measurability + (c) gain-vs-cost** are **severity-downgrade** signals — they DOWNGRADE the severity tag (CATASTROPHE → HIGH → MEDIUM → LOW) and document the downgrade rationale. They do NOT discard.

### `[skeptic-filter]` frontmatter shape (per-skill MD MUST include)

```yaml
[skeptic-filter]
discarded:
  - hypothesis-id: "<SWP-NN-sub-id or DGAUD-NN>"
    structural-protection-citation: "<contracts/Foo.sol:LINE>"
    ev-lens-failed-condition: "a"   # always "a" for discards
    note: "<one-line explanation>"
```

Empty array (`discarded: []`) is valid if the skill found no discards (the expected case).

---

## §5 Disposition-table column schema + consensus routing + elevation routing

### Skeptic-Filter Discarded inline table (Task 5 LOG)

| Hypothesis-ID | Source skill | Structural-protection citation (file:line) | EV-lens failed condition | Note |
| ------------- | ------------ | ------------------------------------------ | ------------------------ | ---- |

Populated from (a) the union of all 3 per-skill `[skeptic-filter]` `discarded` arrays AND (b) any additional orchestrator integration-time discards.

### Integrated Disposition table (Task 5 LOG; survivors only)

| Hypothesis-ID | Source skill | Verdict (NEGATIVE-VERIFIED / FINDING_CANDIDATE / SAFE_BY_DESIGN) | Severity tag (CATASTROPHE / HIGH / MEDIUM / LOW / N-A) | (b)+(c) downgrade rationale | Cross-skill consensus state (Tier-1 / Tier-2 / unanimous-NEGATIVE) |
| ------------- | ------------ | --------------------------------------------------------------- | ------------------------------------------------------ | --------------------------- | ------------------------------------------------------------------ |

### Severity-Downgrade Rationale table (Task 5 LOG)

For every surviving FINDING_CANDIDATE whose severity was downgraded under (b) or (c) arms, document original-vs-downgraded severity + the driving (b)/(c) signal (may be a "no downgrades" attestation).

### Per-skill MD §1 disposition table (Tasks 2/3/4)

Columns: Hypothesis-ID, Verdict, Severity tag, Evidence anchors (file:line + SWP/DGAUD/HANDOFF/ADMA/VRF IDs), Reasoning summary.

### Two-tier consensus routing (D-302-CONSENSUS-01)

- **Tier-2 (3-of-3 consensus FINDING_CANDIDATE on same hypothesis)** → automatic elevation + RE-PASS per D-284-ADVERSARIAL-RE-PASS-01 (no user-pause for elevation).
- **Tier-1 (any-skill FINDING_CANDIDATE surviving dual-gate filter)** → AskUserQuestion user-pause at Task 5.
- **unanimous-NEGATIVE** → no elevation; Task 6 gate fails; proceed to Task 7.

### Elevation-routing protocol (Task 6, conditional)

Any Tier-1 user-approved or Tier-2 auto-elevated `FINDING_CANDIDATE` routes to:

1. **Author `314-FIXREC-AUGMENT.md`** (AGENT-COMMITTED): VIOLATION class; recommended structural close (preferred — eliminates the attack primitive) OR defense-in-depth mitigation (fallback); per-hypothesis evidence anchors (file:line + SWP/DGAUD/HANDOFF/ADMA/VRF IDs + cross-ref to the surviving Disposition row); v45 handoff anchor `D-NN-V45-AUGMENT-NN`.
2. **If the close requires a `contracts/*.sol` diff:** batch per `feedback_batch_contract_approval.md` (ONE consolidated diff); present the actual `git diff -- contracts/` to the USER for explicit review per `feedback_manual_review_before_push.md` + `feedback_never_preapprove_contracts.md` (orchestrator MUST NOT pre-approve for sub-agents); land the diff as a SEPARATE USER-APPROVED commit (NOT bundled into the Task 7 agent commit). This is the sensitive-contract boundary per `feedback_pause_at_contract_phase_boundaries.md`.
3. **If the close requires `test/*.sol` augmentation:** bundle with the FIXREC-augment commit (test/ autonomy within the envelope per `feedback_no_contract_commits.md`).
4. **Trigger RE-PASS per D-284-ADVERSARIAL-RE-PASS-01:** dispatch the 3 skills against (augment diff + affected hypothesis subset ONLY); produce `314-ADVERSARIAL-RE-PASS-{CONTRACT-AUDITOR,ZERO-DAY-HUNTER,ECONOMIC-ANALYST}.md`; integrate into a `## Second-Pass (RE-PASS) Disposition` section appended to `314-01-ADVERSARIAL-LOG.md`.
5. **Update the Phase 315 §4 forward-cite placeholder** in the LOG.

Deletion proposals MUST trace original design intent + actor game-theory first (`feedback_design_intent_before_deletion.md`); MUST NOT propose future-extensibility scaffolding (`feedback_frozen_contracts_no_future_proofing.md`).

---

## §6 Boilerplate

### Out-of-scope / in-scope skills

- **D-271-ADVERSARIAL-02 (carry):** `/degen-skeptic` OUT OF SCOPE for Phase 314.
- **D-271-ADVERSARIAL-03 (carry):** `/economic-analyst` IN SCOPE for Phase 314.

### Consensus rule

- **D-302-CONSENSUS-01 (carry):** Two-tier consensus — Tier-1 user-pause + Tier-2 auto-elevate + RE-PASS.

### Invocation / HYBRID-fallback allowance (D-10)

- `/contract-auditor` SEQUENTIAL_MAIN_CONTEXT FIRST. `/zero-day-hunter` + `/economic-analyst` PARALLEL_SUBAGENT if the executor has the Task tool, else HYBRID_FALLBACK_SEQUENTIAL. The Phase 314 executor runs in the main orchestrator context (Task tool present) → PARALLEL_SUBAGENT is the planned mode. Document the chosen mode in each per-skill MD `[invocation]` frontmatter:

```yaml
[invocation]
skill: /<skill>
mode: <SEQUENTIAL_MAIN_CONTEXT | PARALLEL_SUBAGENT | HYBRID_FALLBACK_SEQUENTIAL>
dispatch_timestamp: "<ISO>"
runner: <orchestrator-main-context | task-subagent>
fallback_reason: <null | "...">
charge_anchor: ".planning/phases/314-sweep-3-skill-adversarial-degenerette-audit-sweep/314-ADVERSARIAL-CHARGE.md"
```

### Mutations policy

- **Zero `contracts/*.sol`** and **zero `test/*.sol`** mutations during the pass EXCEPT via the §5 Task 6 elevation envelope.
- Any `contracts/*.sol` diff at Task 6 lands as a SEPARATE USER-APPROVED commit per `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` + `feedback_manual_review_before_push.md`.
- Any `test/*.sol` augmentation at Task 6 bundles with the FIXREC-augment commit per `feedback_no_contract_commits.md`.
- This is an AUDIT-ONLY phase: it READS `contracts/` + git history and WRITES only `.planning/phases/314-*/`.

### Lean verification-formality posture

The bar is rigorous FULL disposition enumeration expecting unanimous-NEGATIVE like v42 P296 / v43 P302 / v44 P307 (72/72 rows). Accept documented rationales (D-01 LINK-order spot-check), document structural protections as SAFE_BY_DESIGN rather than hunt them exhaustively (D-03 rotation-spam), and accept the off-chain-leaderboard design as a convention rather than escalate the level-recoverability gap (D-06). NOT adversarial over-reach.

### Memory anchors (load-bearing)

- `feedback_skeptic_pass_before_catastrophe.md` — operationalized via §4 D-314-SKEPTIC-FILTER-01.
- `feedback_verify_call_graph_against_source.md` — every file:line anchor grep-verified pre-write (this CHARGE); the wireVrf "by construction" claim (D-04) adversarially re-proven, not asserted.
- `feedback_rng_backward_trace.md` / `feedback_rng_commitment_window.md` / `feedback_rng_window_storage_read_freshness.md` — applied to the SWP-01 VRF re-issue window (rotation-between-request-and-fulfilment).
- `v45-vrf-freeze-invariant.md` — admin rotation EXEMPT; consumed-this-cycle word is the fresh re-issued one; old word abandoned via `:1793` guard.
- `project_rnglock_audit_disposition.md` — §9d anchors are a maximalist catalog, NOT live player vectors.
- `feedback_security_over_gas.md` — security/RNG-non-manipulability is the hard floor.
- `feedback_no_history_in_comments.md` — artifacts describe what IS.

---

## §7 Required output per skill

Each per-skill MD (`314-ADVERSARIAL-CONTRACT-AUDITOR.md`, `314-ADVERSARIAL-ZERO-DAY-HUNTER.md`, `314-ADVERSARIAL-ECONOMIC-ANALYST.md`) MUST include:

1. **`[invocation]` frontmatter** — mode + dispatch timestamp + (if fallback) reason.
2. **`[skeptic-filter]` frontmatter** — `discarded: []` array per the per-skill self-filter arm.
3. **§0 Charge-frame re-anchor** — verbatim quote of the skill's charged SWP-0N (+ DGAUD section for the auditor).
4. **§1 Per-hypothesis disposition table** — one row per charged hypothesis; auditor adds the DGAUD-01..04 section; economist adds beyond-charge rows.
5. **§2 Skeptic-Filter Self-Discarded subsection** — table or "no self-discards" attestation.
6. **§3 Cross-skill hand-off notes** — observations anchoring the other skills' hypotheses; keeps coverage divergent.

---

## §8 Reference files (load-bearing)

### Phase 314 anchors
- `.planning/REQUIREMENTS.md` — SWP-01..02 (`:84-85`), DGAUD-01..04 (`:61-64`), DELTA-04 (`:71`), Traceability rows (`:127-140`).
- `.planning/phases/314-sweep-3-skill-adversarial-degenerette-audit-sweep/314-CONTEXT.md` — D-01..D-10 verbatim.
- `.planning/ROADMAP.md` §"Phase 314" — Goal + 5 success criteria (NOTE the SWP-01 "wireVrf-lock" clause is STALE per D-04; the "+ degenerette-audit-note bundle" wave phrase is SUPERSEDED by D-05).

### Locked design + prior-phase context
- `.planning/phases/311-spec-vrf-rotation-liveness-fix-spec/311-SPEC.md` — §0 grep-verified call-graph manifest + §3 freeze disposition.
- `.planning/phases/312-impl-vrf-rotation-fix-single-batched-user-approved-diff-impl/312-CONTEXT.md` — D-06/D-07/D-08 + VER-01..04 + wireVrf reachability reasoning behind D-04.

### Contracts under adversarial probe (v45.0 audit-subject HEAD)
- `contracts/modules/DegenerusGameAdvanceModule.sol` — SWP-01 primary (`a303ae18`).
- `contracts/DegenerusAdmin.sol` — D-01 LINK spot-check.
- `contracts/modules/DegenerusGameDegeneretteModule.sol` — DGAUD (`92b110bf`).
- `contracts/storage/DegenerusGameStorage.sol` + `contracts/modules/DegenerusGameLootboxModule.sol` — V-081 (`9bcd582d`).
- `contracts/modules/DegenerusGameJackpotModule.sol` — jackpot pending-pool (`6e5acd7e` + `f3e21064`).

### Audit cross-cites
- `audit/FINDINGS-v44.0.md` §9d.2 (HANDOFF-78/85/86/87/88/89/90/91), §9d.4 (ADMA-01/02), §9d (HANDOFF-01/02/03/18/81/82 DGAUD-04 set).

### Skill source definitions
- `~/.claude/skills/contract-auditor/SKILL.md` / `~/.claude/skills/zero-day-hunter/SKILL.md` / `~/.claude/skills/economic-analyst/SKILL.md`.

### Methodology precedents
- `.planning/milestones/v44.0-phases/307-adversarial-sweep-sweep/307-ADVERSARIAL-CHARGE.md` + `307-01-ADVERSARIAL-LOG.md` + `307-ADVERSARIAL-CONTRACT-AUDITOR.md` (artifact bundle shape).
- `.planning/milestones/v41.0-phases/284-delta-audit-findings-consolidation-terminal/284-ADVERSARIAL-RE-PASS-CONTRACT-AUDITOR.md` (RE-PASS shape — used only if Task 6 fires).

---

*Phase: 314-sweep-3-skill-adversarial-degenerette-audit-sweep / Plan: 01 / Charge document authored 2026-05-23. All cited file:line anchors grep-verified against source HEAD per feedback_verify_call_graph_against_source.md.*
