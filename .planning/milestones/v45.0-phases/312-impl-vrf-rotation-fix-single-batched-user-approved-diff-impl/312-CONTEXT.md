# Phase 312: IMPL — VRF-Rotation Fix (Single Batched USER-APPROVED Diff) (IMPL) - Context

**Gathered:** 2026-05-23
**Status:** Ready for planning

<domain>
## Phase Boundary

Apply the LOCKED Phase 311 SPEC (`.planning/phases/311-*/311-SPEC.md`, D-01..D-05 closing VRF-01..05)
as a **single batched USER-APPROVED contract diff** — present ONE diff at the end of the phase, get
ONE approval, no partial commits, no pre-approval (per `feedback_batch_contract_approval` +
`feedback_never_preapprove_contracts` + `feedback_no_contract_commits` +
`feedback_manual_review_before_push`).

**This is an execution phase — the design is LOCKED in the 311 SPEC + REQUIREMENTS.md. Do NOT
redesign.** The discussion did not reopen any locked decision; it resolved three code-organization
choices the SPEC left open (re-issue helper, `_setVrfConfig` visibility, and the MintModule guard
question — D-06/D-07/D-08 below).

**Net touch set: `contracts/modules/DegenerusGameAdvanceModule.sol` ONLY.**
- No new storage slot (queue+apply `pendingVrfRotationPacked` REJECTED by SPEC §6.1 — re-issue needs none).
- No `MintModule.sol` edit (zero-guard DECLINED, D-08 — honor SPEC §3.4).
- Storage-layout break would be acceptable (pre-launch redeploy-fresh per
  `feedback_frozen_contracts_no_future_proofing`) — but the locked shape introduces no layout change.

All cited `file:line` re-grep-verified against source pre-patch per
`feedback_verify_call_graph_against_source` (SPEC verified @ `3153149a`; HEAD now `cc1448da` —
`wireVrf`@498 / `updateVrfCoordinatorAndSub`@1688 / `retryLootboxRng`@1133 / the 4
`requestRandomWords` sites @1102/1143/1587/1605 confirmed stable at discussion time; full re-grep is
a planning obligation).

</domain>

<decisions>
## Implementation Decisions

> **The 311 SPEC is load-bearing and fully locks D-01..D-05.** It lives in phase 311's directory
> (`check_spec` looked only in 312's dir, so `spec_loaded` was false here) — downstream agents MUST
> read it (see Canonical References). Unlike Phase 309→310, the SPEC ALSO resolved its own
> SPEC-discretion items (the `wireVrf` wired-detection mechanism, the `_setVrfConfig` signature, the
> re-issue mechanics, the three-case branch behavior, D-05 reachability). The decisions below are
> ONLY the three code-organization choices resolved in this discussion (D-06/D-07/D-08) + the four
> researcher verification items; everything else is the SPEC verbatim.

### New decisions from this discussion

- **D-06 (re-issue helper — NEW code only):** The re-issue (D-01/D-02) re-fires
  `vrfCoordinator.requestRandomWords(VRFRandomWordsRequest{...})` on the new coordinator. Today there
  are **4 byte-identical-modulo-confirmations inline copies** of that struct in `AdvanceModule.sol`:
  mid-day @`:1102`/`:1143` (`requestConfirmations: VRF_MIDDAY_CONFIRMATIONS`) and daily @`:1587`/`:1605`
  (`requestConfirmations: VRF_REQUEST_CONFIRMATIONS`); the re-issue needs BOTH variants. **Extract an
  `AdvanceModule`-internal helper** `_requestVrfWord(<confirmations>) returns (uint256 id)` that builds
  the struct + calls `requestRandomWords`, and route ONLY the new re-issue branches through it
  (daily branch → `VRF_REQUEST_CONFIRMATIONS`; mid-day branch → `VRF_MIDDAY_CONFIRMATIONS`). This
  single-sources the NEW code (the user's standing single-source-of-truth ethos — Phase 310 D-01/D-02
  + the 311 D-04 dedup; the inline-duplication drift bug class per `feedback_verify_call_graph_against_source`)
  WITHOUT churning the 4 working sites inside a security-critical diff. **The existing 4 inline sites
  are NOT retrofitted** (full retrofit considered + deferred — see Deferred Ideas).

- **D-07 (`_setVrfConfig` visibility = `internal`):** Keep SPEC §4.2 verbatim — `internal`
  `_setVrfConfig(address coord, uint256 sub, bytes32 key)` (3-field config write only;
  `lastVrfProcessedTimestamp` stays inline in `wireVrf`). The user chose SPEC-literal `internal` over
  the marginally-tighter `private` (both callers are same-contract, so `private` would suffice; the
  SPEC's stated 310 cross-module justification doesn't transfer — but the functional equivalence +
  SPEC fidelity for this execution phase win). No override of the SPEC here.

- **D-08 (NO zero-guard at `MintModule:686`):** Honor SPEC §3.4 — do NOT add an `entropy == 0` guard at
  the Scenario-A consumer (`MintModule.sol:686`). The mid-day re-issue fills `lootboxRngWordByIndex[N]`
  **structurally** (so `entropy == 0` is unreachable post-fix), §5 confirmed no residual orphan path,
  and Phase 313 VTST-01/03 will PROVE the structural fill. Adding the guard would defend a state the
  fix eliminates, expand the diff beyond the ROADMAP touch set (into `MintModule.sol`), and revisit a
  locked SPEC decision. **`MintModule.sol` is therefore untouched this phase.**

### Open Verification Items (researcher MUST resolve before the planner locks the patch shape)

These are NOT redesigns of the locked SPEC — they are correctness questions about realizing the locked
re-issue against the surrounding code. Each gates the IMPL.

- **VER-01 — LINK-funding order around the re-issue.** The Admin wrapper does `addConsumer`
  (`DegenerusAdmin.sol:894`) → `updateVrfCoordinatorAndSub` (`:901`) → transfer LINK (`:907-912`). The
  re-issue now fires `requestRandomWords` inside `:901` — **before** LINK lands at `:907-912`. Confirm
  the new subscription accepts the request and fulfills once funded (Chainlink charges at fulfillment),
  OR whether the Admin wrapper must fund-before-call. If a reorder is required, that touches
  `DegenerusAdmin.sol` — a potential scope expansion beyond `AdvanceModule.sol` to surface for approval.
  Note `retryLootboxRng` (`:1138-1141`) gates on `getSubscription` linkBal ≥ `MIN_LINK_FOR_LOOTBOX_RNG`
  before re-firing — evaluate whether the rotation re-issue needs the same precheck.
- **VER-02 — `rngWordCurrent != 0` interaction (daily case).** The daily re-issue's fresh callback is
  gated by `rawFulfillRandomWords:1761` `if (requestId != vrfRequestId || rngWordCurrent != 0) return;`.
  If a daily word was already delivered-but-unprocessed (`rngWordCurrent != 0`), the new callback is
  rejected. Confirm the daily branch handles an already-delivered word correctly (e.g., short-circuit
  the re-issue when `rngWordCurrent != 0`, since the existing word is valid entropy) per SPEC §2.2's
  "eliminates the just-delivered-but-unprocessed edge case" note.
- **VER-03 — daily vs mid-day flag exclusivity.** SPEC §2.2 treats daily (`rngLockedFlag == true`) and
  mid-day (`LR_MID_DAY == 1`) as distinct cases. Confirm they cannot both be set simultaneously, or
  define the branch precedence inside `updateVrfCoordinatorAndSub` if they can.
- **VER-04 — full pre-patch re-grep.** Re-grep every SPEC §0 anchor against HEAD before patching (SPEC
  verified @ `3153149a`; current HEAD `cc1448da`) per `feedback_verify_call_graph_against_source`.

### Locked by the 311 SPEC — carried forward verbatim, NOT reopened

- **D-01 (re-issue on new coordinator):** Replace the unconditional blanket reset
  (`AdvanceModule:1701-1704` + `:1709`) with detect-preserve-re-issue. After repointing config, if a
  request is in flight, re-fire `requestRandomWords` on the now-current coordinator and set fresh
  `vrfRequestId = id` + `rngRequestTime = block.timestamp`. Freeze-safe: the dead old coordinator's
  callback carries the OLD `requestId` and is rejected by the `:1761` guard (old word abandoned, new
  word unpredictable). `retryLootboxRng` (`:1133`, ≥`MIDDAY_RNG_RETRY_TIMEOUT`) stays the standing
  failsafe.
- **D-02 (preserve+re-issue both paths; drop the force-unlock):** Three cases —
  - **Daily** (`rngLockedFlag == true`): KEEP `rngLockedFlag = true`, re-request → `rawFulfillRandomWords`
    daily branch (`:1768` `rngWordCurrent = word`).
  - **Mid-day** (`LR_MID_DAY == 1`): KEEP `LR_MID_DAY = 1`, re-request → mid-day branch (`:1772`
    `lootboxRngWordByIndex[index] = word`); `LR_INDEX` preserved so `index` resolves to the SAME orphaned
    slot `[N]`. **This is the precise close of VRF-01.**
  - **Nothing in flight:** config repoint only — no re-issue, no flag change.
- **D-03 (`wireVrf` init-only lock):** `wireVrf` reverts once VRF is wired; detection LOCKED to
  `if (address(vrfCoordinator) != address(0)) revert E();` (no new slot). `updateVrfCoordinatorAndSub`
  becomes the SOLE post-init VRF-config mutator. Closes VRF-04 (HANDOFF-86/88/90 + ADMA-01).
- **D-04 (`_setVrfConfig` dedup):** Both `wireVrf` and `updateVrfCoordinatorAndSub` route their 3-field
  config write through one helper (visibility = `internal` per D-07). `lastVrfProcessedTimestamp`
  (`wireVrf:509`) stays inline, outside the helper.
- **D-05 (narrow orphan-recovery):** No new backfill wiring. Re-issue fills the single in-flight index
  directly (`:1772`) AND un-blocks the new-day drain gate (`:269`/`:271`), restoring reachability of the
  EXISTING `_backfillOrphanedLootboxIndices` (`:1208` call / `:1817` def, VRF-derived `keccak(word,i)`).
  `LR_MID_DAY` single-in-flight gate (`:1048`) bounds orphans to ≤1/rotation. SPEC §5 CONFIRMED-COVERED;
  escalation NOT triggered.
- **`totalFlipReversals` carry-over PRESERVED** (`:1711-1714`) — re-issue leaves that block untouched
  (nudges from burned BURNIE apply to the first post-rotation daily word). VRF-05 (vault reach): guards
  sit at the `delegatecall` targets (`:498`/`:1688`), downstream of every wrapper — no wrapper bypass.

### Claude's Discretion

- Exact `_requestVrfWord` signature/visibility (D-06). The confirmations param type matches the
  `VRFRandomWordsRequest.requestConfirmations` field / the `VRF_*_CONFIRMATIONS` constant types. **Lean
  `private`** to match the existing AdvanceModule re-fire helpers (`_requestRng`/`_tryRequestRng` at
  `:1585`/`:1600` are `private`); aligning it with `_setVrfConfig`'s `internal` (D-07) is also
  acceptable — minor, same-contract-only either way.
- The exact if/else branch structure inside `updateVrfCoordinatorAndSub` and the bit/flag read mechanics
  (`_lrRead(LR_MID_DAY_*)`, `rngLockedFlag`), subject to VER-02/VER-03.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents (researcher, planner, executor) MUST read these before planning or implementing.**

### v45.0 LOCKED design (load-bearing — read first)
- `.planning/phases/311-spec-vrf-rotation-liveness-fix-spec/311-SPEC.md` — **THE locked design.** §0
  grep-verified call-graph manifest (every `file:line` IMPL touches, incl. §0.Y vault/admin dispatch
  reconciliation), §1 design-intent backward-trace (Scenario A/B), §2 re-issue fix shape (D-01/D-02),
  §3 freeze-invariant disposition (VRF-03; validator-entropy REJECTED), §4 `wireVrf` lock + `_setVrfConfig`
  dedup + vault reach (D-03/D-04/VRF-04/VRF-05), §5 orphan-recovery breadth (D-05 CONFIRMED-COVERED), §6
  rejected/deferred options. MUST read before any patch.
- `.planning/REQUIREMENTS.md` — VRF-01..05 (the 5 requirements this phase delivers; proven by VTST-01..04
  at Phase 313), the fix-shape directive (re-issue locked; queue+apply the rejected alternative), the
  posture (single batched USER-APPROVED diff), and Out of Scope.
- `.planning/phases/311-*/311-CONTEXT.md` — the D-01..D-05 source decisions the SPEC transcribes, plus the
  Claude's-Discretion + carried-behavior notes (`totalFlipReversals`, re-issue mechanics).
- `.planning/phases/310-implementation-single-batched-user-approved-contract-diff-im/310-CONTEXT.md` — the
  single-source-of-truth precedent (D-01/D-02 consolidate-shared-logic) that grounds D-06 here, AND the
  template for this phase's batched-diff posture (execution phase, SPEC in the SIBLING dir, do-not-redesign).
- `.planning/ROADMAP.md` §Phase 312 — the VRF-01..05 scope statement + 5 success criteria + wave shape (1
  batched USER-APPROVED contract commit; final wave `autonomous: false`).
- `.planning/STATE.md` — baseline `MILESTONE_V44_AT_HEAD_6f0ba2963a10654ba554a8c333c5ee80c54a8349`.

### §9d VRF-cluster source (the anchors this fix closes)
- `audit/FINDINGS-v44.0.md` §9d.2 — HANDOFF-78/85/87/89/91 (freeze → D-01/D-02, VRF-03), HANDOFF-86/88/90
  (wireVrf lock → D-03/D-04, VRF-04).
- `audit/FINDINGS-v44.0.md` §9d.4 — ADMA-01 (`wireVrf` seal → D-03) + ADMA-02 (`updateVrfCoordinatorAndSub`
  vault-routed reach → VRF-05; the §9d-cited `:1677` DRIFTED to `:1688` at HEAD — see SPEC §0.X note).

### Contract HEAD sites IMPL touches (re-grep-verify pre-patch per VER-04)
- `contracts/modules/DegenerusGameAdvanceModule.sol:498` — `wireVrf` (D-03 init-only lock + D-04 shared write).
- `contracts/modules/DegenerusGameAdvanceModule.sol:1688` — `updateVrfCoordinatorAndSub` (D-01/D-02 rework
  target; `:1696-1698` config write → `_setVrfConfig`; `:1701-1704` resets + `:1709` `LR_MID_DAY=0` REPLACED
  by preserve+re-issue; `:1711-1714` `totalFlipReversals` carry-over PRESERVED).
- `contracts/modules/DegenerusGameAdvanceModule.sol:1102` / `:1143` / `:1587` / `:1605` — the 4 inline
  `requestRandomWords` structs (mid-day `VRF_MIDDAY_CONFIRMATIONS` / daily `VRF_REQUEST_CONFIRMATIONS`); the
  `_requestVrfWord` extraction base (D-06; new re-issue routes through it, these 4 stay inline).
- `contracts/modules/DegenerusGameAdvanceModule.sol:1756` — `rawFulfillRandomWords` (`:1761` requestId/word
  guard that abandons the old word; `:1768` daily write → `rngWordCurrent`; `:1772` mid-day write →
  `lootboxRngWordByIndex[index]`). Reused UNCHANGED by re-issue.
- `contracts/modules/DegenerusGameAdvanceModule.sol:1044`/`:1048`/`:1097` — `requestLootboxRng` + the
  `LR_MID_DAY` single-in-flight gate + the `LR_MID_DAY=1` set (orphan bound = ≤1/rotation).
- `contracts/modules/DegenerusGameAdvanceModule.sol:1133`/`:1134`/`:1138-1141` — `retryLootboxRng` (failsafe;
  the canonical re-fire pattern + the LINK-balance precheck referenced by VER-01).
- `contracts/modules/DegenerusGameAdvanceModule.sol:1208`/`:1817` — existing `_backfillOrphanedLootboxIndices`
  call + definition (D-05 reachability; NOT modified).
- `contracts/modules/DegenerusGameAdvanceModule.sol:~205-238`/`~263-275` — the advance-flow drain gate
  (Scenario B revert sites `:213`/`:238`/`:271`; re-issue un-blocks these).
- `contracts/modules/DegenerusGameMintModule.sol:686` — `entropy = lootboxRngWordByIndex[...-1]`, no zero-guard
  (Scenario A consumer). **NOT modified** (D-08); cited for context only.
- `contracts/storage/DegenerusGameStorage.sol:244`/`:373`/`:1287`/`:1291`/`:1295`/`:1328-1329`/`:1431` — the
  VRF-participating slots (`rngRequestTime`/`rngWordCurrent`/`vrfCoordinator`/`vrfKeyHash`/`vrfSubscriptionId`/
  `LR_MID_DAY` shift+mask/`lootboxRngWordByIndex`). Read-only reference (no layout change).
- `contracts/DegenerusAdmin.sol:894`/`:901`/`:907-912` — the rotation dispatch + LINK funding sequence (VER-01).
- `contracts/DegenerusAdmin.sol:458` + `contracts/DegenerusGame.sol:308`/`:1874` — the wireVrf/rotation routed
  reach (`delegatecall` targets; VRF-05 guards sit at the AdvanceModule implementations downstream).

### Memory / methodology (must apply)
- `feedback_batch_contract_approval`, `feedback_never_preapprove_contracts`, `feedback_no_contract_commits`,
  `feedback_manual_review_before_push` — single batched USER-APPROVED diff; ONE approval at end; never
  pre-approve; user reviews the diff before any push.
- `feedback_verify_call_graph_against_source` — re-grep every cited line pre-patch (VER-04); no "by
  construction"; inline-duplicated logic is the recurring drift bug class (drove D-06).
- `project_vrf_rotation_midday_orphan_index` — the CONFIRMED finding + the re-issue shape (now D-01).
- `v45-vrf-freeze-invariant` — every variable interacting with a VRF word frozen [rng request→unlock] vs
  PLAYERS; advanceGame/admin EXEMPT; verify consumed-this-cycle (re-issue: old word abandoned, new word fresh).
- `project_rnglock_audit_disposition` — §9d anchors are a maximalist catalog, NOT live player vectors; fix the
  real liveness defect, don't over-fix governance rows.
- `feedback_security_over_gas` (validator-influenceable entropy backfill REJECTED),
  `feedback_design_intent_before_deletion`, `feedback_frozen_contracts_no_future_proofing`,
  `feedback_maximal_variable_packing`, `feedback_no_history_in_comments`,
  `feedback_pause_at_contract_phase_boundaries` (confirm direction at this sensitive contract-phase boundary).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `rawFulfillRandomWords` (`:1756`) already has BOTH a daily branch (→ `rngWordCurrent`, `:1768`) and a
  mid-day branch (→ `lootboxRngWordByIndex[index]`, `:1772`). Re-issue (D-01/D-02) reuses both UNCHANGED —
  re-firing just makes a fresh `vrfRequestId` the callback matches against. No new fulfillment path.
- `retryLootboxRng` (`:1143`) is the canonical "re-fire on same params, set fresh `vrfRequestId`/
  `rngRequestTime`, preserve `LR_MID_DAY`+`LR_INDEX`" pattern that D-01 generalizes to the rotation path; it
  also remains the standing failsafe if the NEW coordinator stalls. Its LINK precheck (`:1138-1141`) informs VER-01.
- `_backfillOrphanedLootboxIndices` (`:1817`) already exists (VRF-derived `keccak(vrfWord, i)`, backward scan).
  D-05 keeps it; re-issue restores its reachability, no new wiring.
- The 4 inline `requestRandomWords` structs (`:1102`/`:1143`/`:1587`/`:1605`) are the `_requestVrfWord`
  extraction base (D-06): byte-identical except `requestConfirmations` (mid-day vs daily constant).

### Established Patterns
- VRF-config writes are admin-gated (`ContractAddresses.ADMIN`). `wireVrf` (`:498`) + `updateVrfCoordinatorAndSub`
  (`:1688`) both write the same 3 slots — the near-duplication D-04's `_setVrfConfig` collapses.
- AdvanceModule-internal re-fire helpers (`_requestRng`/`_tryRequestRng`, `:1585`/`:1600`) are `private` — the
  convention `_requestVrfWord` (D-06) most naturally matches.
- `LR_MID_DAY` gates a single in-flight mid-day request (`:1048`) → ≤1 orphaned index per rotation (grounds D-05).
- Re-issue is freeze-safe via the `:1761` `requestId` guard (`v45-vrf-freeze-invariant`: admin rotation EXEMPT,
  consumed-this-cycle word is the fresh one, old word abandoned).

### Integration Points
- **All edits land in `DegenerusGameAdvanceModule.sol`** — `_setVrfConfig` + `_requestVrfWord` helpers, the
  `wireVrf` lock guard, and the `updateVrfCoordinatorAndSub` rework. No `MintModule`/`Storage` mutation; no new
  storage slot.
- The rotation is reached via `DegenerusAdmin._executeSwap:859/901` → `DegenerusGame:1874` `delegatecall` →
  AdvanceModule `:1688`; the LINK-funding sequence around the push is the VER-01 surface (the only place a scope
  expansion to `DegenerusAdmin.sol` could arise — surface for approval if VER-01 demands a reorder).

</code_context>

<specifics>
## Specific Ideas

- The user's standing **single-source-of-truth over duplication** preference (Phase 310 D-01/D-02, reaffirmed
  in 311-CONTEXT, embodied in the SPEC's own D-04) drove D-06 — but scoped to the NEW re-issue code only, NOT a
  retrofit of the 4 working inline sites, to keep a security-critical diff minimal and reviewable.
- On the two SPEC-adjacent calls the user chose **SPEC fidelity for this execution phase**: `_setVrfConfig`
  stays `internal` (D-07, SPEC §4.2 verbatim) and no zero-guard is added at `MintModule:686` (D-08, honor SPEC
  §3.4). This phase honors the locked design rather than reopening it.
- Decision-anchor convention (D-NN) continued: the SPEC's D-01..D-05 carry forward; this discussion's new
  decisions are D-06/D-07/D-08; verification obligations are VER-01..04.

</specifics>

<deferred>
## Deferred Ideas

- **Full retrofit of the 4 existing inline `requestRandomWords` sites through `_requestVrfWord`** — considered
  (the maximal single-source-of-truth play) and DEFERRED in favor of D-06's new-code-only scope; the existing
  sites are not broken and churning them broadens a security-critical diff. Revisit only if a future phase does
  a deliberate AdvanceModule consolidation pass.
- **Defense-in-depth `entropy == 0` guard at `MintModule:686`** — considered and DECLINED (D-08) in favor of
  honoring SPEC §3.4's structural fill (proven by 313 VTST-01/03). Revisit only via the SPEC §5 escalation
  clause, which §5 confirmed is NOT triggered.
- **Queue+apply rotation (`pendingVrfRotationPacked`)** — the §9d HANDOFF-78 tactic; REJECTED as the fix shape
  by SPEC §6.1 (old coordinator dead → in-flight word never resolves → adds recovery latency). Recorded as the
  documented alternative only.
- **Belt-and-suspenders gate-independent orphan backfill / dedicated recovery entry point** — SPEC §6.2
  DEFERRED; the standing fallback the §5 escalation clause would have invoked (it did not).
- Non-VRF v44 backlog (~115 anchors), V-081 dedicated regression, jackpot pending-pool new work, VRF fallback /
  `retryLootboxRng` re-audit, game-over hardening — out of scope for v45.0 per `.planning/REQUIREMENTS.md`.

</deferred>

---

*Phase: 312-impl-vrf-rotation-fix-single-batched-user-approved-diff-impl*
*Context gathered: 2026-05-23*
