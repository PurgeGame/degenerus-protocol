# Phase 302 Adversarial-Pass Charge — v43.0 rngLock Freeze Invariant Sweep

**For:** `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` (3-skill SWEEP per D-271-ADVERSARIAL-01 + D-271-ADVERSARIAL-03 carry).

**Out of scope:** `/degen-skeptic` per D-271-ADVERSARIAL-02 carry.

**Invocation pattern:** HYBRID per D-302-INVOKE-01. Task 2 dispatches `/contract-auditor` SEQUENTIAL_MAIN_CONTEXT in the orchestrator's main context. Tasks 3 + 4 dispatch `/zero-day-hunter` + `/economic-analyst` as PARALLEL_SUBAGENT via a single-message multi-Task block. Each of the 3 skills receives THIS document verbatim as its prompt — do not pre-summarize.

**Pre-authorized invocation:** Per `D-43N-SWEEP-PREAUTH-01` (user-authorization 2026-05-18), Phase 302 fires the 3-skill HYBRID without re-pinging the user. Tier-1 any-single-skill `FINDING_CANDIDATE` STILL triggers a user-review checkpoint at Task 5 integration per `D-302-CONSENSUS-01` (carry of v42 D-296-CONSENSUS-01).

---

## Context

You are reviewing the v43.0 milestone audit subject for the Degenerus Protocol. The audit subject is the **rngLock freeze invariant** AND the v43.0 audit artifacts produced in Phases 298–301:

- **Phase 298 RNGLOCK-CATALOG** (`.planning/RNGLOCK-CATALOG.md`) — 13-consumer VRF read-graph + 67-row §14 unique-slot index + §15 per-slot writer enumeration + §16 verdict matrix.
- **Phase 299 RNGLOCK-FIXREC** (`.planning/RNGLOCK-FIXREC.md`) — 111 per-VIOLATION §N entries + §0 executive summary post-EV-tier-discipline-lens + 119 `D-43N-V44-HANDOFF-NN` anchors aggregated into §M consolidated handoff register.
- **Phase 300 ADMIN-AUDIT** (`.planning/ADMIN-AUDIT.md`) — 22 admin-function `D-43N-V44-ADMA-NN` recommendations (R-01..R-22; A-34 setCharity catalog-gap candidate as R-06) + §1 enumeration + §2 participating-slot cross-reference + §3 per-admin-function recommendation table.
- **Phase 301 FUZZ harness** (`test/fuzz/RngLockDeterminism.t.sol`) — 13 `testFuzz_RngLockDeterminism_*` consumer functions + 5 `testFuzz_EdgeCase_*` functions + 17 `vm.skip` blocks cross-referencing FIXREC sec_N + HANDOFF-NN anchors per `D-301-VMSKIP-MECHANISM-01` Option C.

**v43.0 freeze invariant (precise statement, per `.planning/REQUIREMENTS.md`):**

> At `rngLockedFlag = true`, every storage slot that participates in deriving any VRF-influenced output is **frozen** until `rngLockedFlag = false`. The only values that may be unknown at lock time are the incoming VRF word and its deterministic derivations from that word. No external/public function call (including admin/owner) may mutate any participating slot during the rngLock window, with three explicit exempt entry points:
>
> 1. `advanceGame()` and every function reachable from it — the resolution orchestrator itself.
> 2. The VRF coordinator callback that delivers `randomness` — the VRF-word arrival path.
> 3. `retryLootboxRng()` failsafe — ≥6h cooldown gate + ≤1 VRF-replacement per stall event + does not manipulate any pre-lock state (`D-42N-RETRY-RNG-DOMAIN-SEP-01` Option A accepted).

**AUDIT-ONLY posture** (`D-43N-AUDIT-ONLY-01`, user-authorization 2026-05-18): Zero `contracts/` mutations and zero `test/` mutations in this phase. **`FINDING_CANDIDATE` elevation routes to a FIXREC-augment append, NOT a Phase 303a/etc FIX wave** per `D-302-AUDIT-ONLY-ROUTING-01`. Actual contract remediations are deferred to v44.0 FIX-MILESTONE consuming the §M handoff register.

**Milestone goal explicitly precludes `SAFE_BY_DESIGN` for participating slots.** Per `REQUIREMENTS.md` v43.0 goal: *"No SAFE_BY_DESIGN escape hatch for participating slots. 'Could possibly affect' = theoretical reachability; eliminate even if economic likelihood is LOW. Game-theoretic analysis is not a substitute for structural elimination."* If your evidence chain concludes `SAFE_BY_DESIGN` on a writer that mutates a §14 participating slot, re-classify as `SAFE_BY_STRUCTURAL_CLOSURE` (if the closure is structural — e.g., state-machine gate, atomic write/consume pair, type-system invariant) or `FINDING_CANDIDATE` (if the closure is design-only without structural guarantee). `SAFE_BY_DESIGN` remains valid for NON-participating-slot vectors or for hypotheses whose evidence chain demonstrates the proposed vector does not touch a §14 row.

**EV-tier discipline lens** (load-bearing per `feedback_skeptic_pass_before_catastrophe.md` carry). Phase 299 cluster authors over-classified findings as `CATASTROPHE` / `HIGH` based on methodology pattern labels rather than actual economic impact. The 3-condition catastrophe predicate: **a finding is catastrophic only when ALL three are true**:

1. The slot's value **feeds a VRF-derived output computation** (not incidental accounting like `claimablePool` or `claimableWinnings`).
2. The slot is **mutable mid-rngLock by a non-EXEMPT actor**.
3. The mutation **changes a VRF-derived output the mutator profits from after opportunity cost** (forfeited stake, Sybil bypass cost, etc.).

Apply this lens BEFORE elevating any finding past tactic-(a) revert depth. If any of the three conditions deflates the magnitude, default to `INFO`, `LOW`, or `ACCEPTED_DESIGN`.

---

## Charge — red-team the audit subject

Walk the **9 hypothesis surfaces** below (5 SWP-NN verbatim + 4 carry-forward augments per `D-302-CHARGE-01`). Per hypothesis, return one of these dispositions:

- **SAFE** — verified safe via the cited evidence; no adversarial vector.
- **SAFE_BY_DESIGN** — intentional/documented design that closes the surface (NON-participating-slot vectors only; rejected for §14 rows per the milestone goal).
- **SAFE_BY_STRUCTURAL_CLOSURE** — surface closed by structural property (state-machine gate, atomic state, type-system invariant).
- **NEGATIVE_RESULT_ONLY** — searched the vector, found nothing exploitable; document the negative result.
- **ACCEPTED_DESIGN** — design tradeoff identified; not a finding (e.g., intentional EV reduction as documented; user-accepted bytecode delta).
- **FINDING_CANDIDATE** — vector exists; describe the finding + suggested remediation (DO NOT propose contract changes; describe descriptively for user review).

**Required output format per hypothesis:**

```markdown
## Hypothesis (X) — [short title]

**Disposition:** SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / NEGATIVE_RESULT_ONLY / ACCEPTED_DESIGN / FINDING_CANDIDATE

**Evidence:**
- [line citations, control-flow trace, storage-write inventory, lens-condition check, etc.]

**Notes:**
- [reasoning, edge cases considered, alternative attack vectors explored]
```

If `FINDING_CANDIDATE` → include a **Description** block (the vector at v43 close), a **Severity estimate** (per D-08 5-Bucket Severity Rubric: CRITICAL / HIGH / MEDIUM / LOW / INFO; apply the 3-condition lens), and a **Suggested remediation** block (one of: rngLockedFlag-gated revert / snapshot-anchor / re-order to pre-lock / immutable — descriptive only, no contract code).

**Hard requirement: NO contract code in your output.** Suggested remediations are descriptive only per `feedback_never_preapprove_contracts.md` + `feedback_no_contract_commits.md` — only the user can approve contract changes, and the user reviews remediation descriptions before any patch is drafted.

**Hard requirement: NO post-v43 milestone forward-cite tokens.** Phase 303 (v43.0 TERMINAL) owns the forward-cite envelope per the v43 closure invariant. Do not name any post-v43 milestone, version, or release identifier. Use locked-decision IDs `D-43N-V44-HANDOFF-NN` + `D-43N-V44-ADMA-NN` + descriptive labels only.

**Beyond-charge entries.** You are free to surface beyond-charge hypotheses where you identify a novel attack surface; document each beyond-charge hypothesis with the same disposition rubric and the same output format. Beyond-charge entries are aggregated into the integrated LOG with the same two-tier consensus rule (Tier 2 only fires if all 3 skills independently address the same surface and all 3 emit FINDING_CANDIDATE).

**RNG-audit methodology** (load-bearing for every hypothesis):
- `feedback_rng_backward_trace.md` — every RNG audit must trace BACKWARD from each consumer to verify the word was unknown at input commitment time.
- `feedback_rng_commitment_window.md` — every RNG audit must check what player-controllable state can change between VRF request and fulfillment.
- `feedback_rng_window_storage_read_freshness.md` — enumerate ALL SLOADs inside rng-window, not just VRF-derived seeds; non-VRF reads consumed alongside RNG are a distinct bug class (F-41-02/03 precedent).
- `feedback_verify_call_graph_against_source.md` — any "by construction" / "single fn covers all paths" claim must be grep-verified against source pre-attestation.

---

## Hypothesis Surfaces

### Group I — SWP-01..05 verbatim charge surfaces

#### Hypothesis (i) — SWP-01: Freeze-invariant storage paths (`/contract-auditor` primary surface)

**Charge:** Walk every storage path that mutates a §14 participating slot during the rngLock window. For each, attest whether the path is one of the 3 exempt entry points (advanceGame() and reachable; VRF callback; retryLootboxRng failsafe) or whether it constitutes a VIOLATION per CAT-04. Cross-reference RNGLOCK-CATALOG §15 + §16 verdict matrix; surface any participating slot whose freeze gate is missing, incorrectly scoped, or bypassed via composition.

Specifically check:

- **(a) Coverage gates** — for each §14 row whose §16 verdict is VIOLATION, is the RNGLOCK-FIXREC.md §N.C recommended tactic textually present in-source at v43 close, or absent? Verification-only rows (V-009, V-010, V-011, V-055, V-064, V-066, V-072, V-074, V-142, V-170, V-179.C per FIXREC §0.7) should show their gate in-source — if any of the cited gate file:line citations DO NOT contain the documented gate, that is a CATALOG-FIXREC discrepancy and a FINDING_CANDIDATE.
- **(b) STALE-CATALOG-ROW re-verification** — FIXREC §0.7 marks V-016 / V-017 / V-018 as STALE (writer functions absent from current `contracts/`; line numbers point to view functions). Grep `contracts/` for `adminSeedTraitBucket` / `adminClearTraitBucket` and the helper at `DegenerusGame.sol:2510` — confirm absence or surface the writer.
- **(c) PENDING-VERIFICATION re-derivation** — FIXREC §0.7 marks V-047 / V-048 / V-050 (poolBalances[Lootbox] mega-tier) as PENDING-VERIFICATION. The "drain-pool-before-resolution" exploit described doesn't compute as written: the only EOA path to deflate Lootbox pool is the player's OWN lootbox resolution, which reduces their own payout. **Phase 302 SWEEP is the venue for resolving these markers.** Walk the cross-EOA pool-deflation surface independently; produce a concrete-tier disposition (CONFIRMED-EXPLOIT / NO-REAL-EV / RECLASSIFY-NON-PARTICIPATING).
- **(d) Missing-writer detection** — independent grep sweep for any `external` / `public` function in `contracts/` that writes a §14 slot but is absent from §15 (catalog completeness gate per CAT-06 re-verification).

**Evidence anchors:**
- RNGLOCK-CATALOG.md §14 (67 unique participating slots, S-01..S-67); §15 (per-slot writer enumeration with file:line); §16 (verdict matrix).
- RNGLOCK-FIXREC.md §0 Executive Summary (EV-tier breakdown post-lens); §0.6 subsumption map; §0.7 catalog hygiene markers; §1..§111 per-VIOLATION entries.
- ADMIN-AUDIT.md §1 (22 admin functions A-02..A-34); §2 cross-reference table; §3 R-01..R-22 per-admin recommendations.
- Existing in-source `rngLockedFlag` reverts: `MintModule.sol:877`, `:906`, `:1215`; `BurnieCoinflip.sol:730`; `sStonk.sol:492`; `WhaleModule.sol:543`; `DegenerusGame.sol:1513`, `:1528`, `:1575`; `Storage.sol:572` (`_queueTickets` / `_queueTicketRange` downstream revert).
- `prizePoolFrozen` routing (`Storage.sol:744`/`:771` `_swapAndFreeze` / `_unfreezePool`) — orthogonal to `rngLockedFlag` but related coverage gate.

**Expected disposition class:** Mixed. Verification-only rows expected `SAFE_BY_STRUCTURAL_CLOSURE` (gate in-source); STALE rows expected `NEGATIVE_RESULT_ONLY` post-grep-confirm; PENDING-VERIFICATION rows expected to re-derive to either `FINDING_CANDIDATE` or RECLASSIFY-NON-PARTICIPATING. Missing-writer paths emit `FINDING_CANDIDATE` if surfaced.

**Cross-cite:** `feedback_verify_call_graph_against_source.md` (grep-verify against source); `feedback_rng_window_storage_read_freshness.md` (enumerate ALL SLOADs inside the rngLock window).

---

#### Hypothesis (ii) — SWP-02: Novel attack surfaces (`/zero-day-hunter` primary surface)

**Charge:** Walk composition attacks, cross-module read/write races, ERC-callback-induced state mutations, multi-block window exploits. Specifically check:

- **(a) ERC777/ERC-callback-induced writes.** Are there ERC777-style `tokensReceived` / `tokensToSend` hooks during `transferFromPool` flows (`sDGNRS.sol:412` writes at `:422`) that could re-enter `contracts/` and mutate a §14 slot? The Reward / Lootbox pools (S-14 / S-15) are `transferFromPool`-mutated; any hook-induced re-entry that touches a §14 slot during a rngLock window is a VIOLATION class.
- **(b) Re-entrancy across module boundaries.** Walk the cross-module call graph for windows where Module A's external function reaches Module B's participating-slot writer during rngLock. Specifically high-composition-density consumers: §6 LootboxModule.resolveRedemptionLootbox; §7 _resolveLootboxCommon; §11 BurnieCoinflip; §12 sStonk; §13 DecimatorModule._awardDecimatorLootbox.
- **(c) Multi-block window exploits.** Can an attacker span the rngLock window across N blocks (VRF request at block B, callback at block B+k) where intermediate-block state mutations land between VRF request and fulfillment? Walk the player-callable functions accessible during the window — for each, identify §14 slots it writes.
- **(d) Cross-module composition.** Are there call graphs where Module A's external function reaches Module B's participating-slot writer via an indirect path that the per-module audit missed? Apply `feedback_verify_call_graph_against_source.md` (Phase 294 BURNIE gap precedent).
- **(e) ERC721 callback (deity-pass).** Does `DegenerusDeityPass.sol` `_mint` / `_safeMint` trigger `onERC721Received` callbacks that could re-enter `contracts/` and mutate `deityBySymbol` (S-07) or `deityPassOwners` (S-18) or `deityPassPurchasedCount` (S-19) during a rngLock window?
- **(f) Reverse-callback paths** — `BurnieCoin` / `BurnieCoinflip` / `sDGNRS` callbacks into `DegenerusGame` (e.g., `deactivateAfKingFromCoin` at `:1641` and `syncAfKingLazyPassFromCoin` at `:1654`) — do these reach §14 writers from cross-contract entry?

**Evidence anchors:**
- RNGLOCK-CATALOG.md §6 (LootboxModule.resolveRedemptionLootbox high-composition-density consumer); §7 (_resolveLootboxCommon); §11 (BurnieCoinflip._resolveFlip); §12 (sStonk.resolveRedemptionPeriod); §13 (DecimatorModule._awardDecimatorLootbox cluster).
- RNGLOCK-FIXREC.md §1 V-003 (cross-day hero-override race); §0 headline-2 (Cluster G manual-path lootbox open deep cluster); §0.6 subsumption map.
- `contracts/StakedDegenerusStonk.sol:412` (`transferFromPool`); `:453, :455` (`transferBetweenPools`); `:469` (`burnAtGameOver`).
- `contracts/BurnieCoinflip.sol:807, :837` (`_resolveFlip` + win-decode).
- `contracts/DegenerusDeityPass.sol` (deity-pass NFT — verify mint hook surface).
- `contracts/modules/DegenerusGameMintModule.sol:949` (`_resolveMintShortfall` `claimablePool -=`); `:877, :906, :1215` (in-source gates).
- `contracts/modules/DegenerusGameAdvanceModule.sol:1132` (`retryLootboxRng` failsafe); `:1729` (`_unlockRng` `dailyIdx` writer).

**Expected disposition class:** Most paths expected `SAFE_BY_STRUCTURAL_CLOSURE` (existing gates close most surfaces). Re-entrancy via OZ ERC20 `_transfer` / `_burn` is the `V-046` OZ-carveout class — already enumerated in FIXREC §22; do not re-emit unless your trace reveals a path the catalog missed. ERC721 deity-mint callback path expected `SAFE_BY_DESIGN` pending verification (deity-pass mints route through `WhaleModule:598` which writes `deityBySymbol` BEFORE any potential ERC721 receiver callback).

**Cross-cite:** `feedback_verify_call_graph_against_source.md`; FIXREC §0 headline-2 Cluster G; FIXREC §22 V-046 OZ-inherited writer carveout.

---

#### Hypothesis (iii) — SWP-03: Game-theoretic write-induced effects (`/economic-analyst` primary surface)

**Charge:** Walk incentive-compatible adversarial actions during the rngLock window. For each player class (degenerette bettor, lootbox holder, mint queuer, sStonk staker, decimator claimant, deity pass holder, charity admin, governance admin), identify any action available during the window that (a) is profitable in expectation conditional on VRF outcome AND (b) writes a §14 participating slot.

Apply the 3-condition catastrophe lens per `feedback_skeptic_pass_before_catastrophe.md`:
1. Slot feeds VRF-derived output computation (not incidental accounting).
2. Slot is mutable mid-rngLock by non-EXEMPT actor.
3. Mutation changes a VRF-derived output the mutator profits from after opportunity cost.

Specifically attest:

- **(a) V-184 sStonk cross-day re-roll** — FIXREC §0.4 headline-1 + §103 mark V-184 as the only true CATASTROPHE-tier finding. `redemptionPeriodIndex` (S-56) is not advanced inside `resolveRedemptionPeriod`; an attacker post-resolution can call `burn(1 wei)` on a future wall-clock day, re-arm `pendingRedemptionEthBase` for the already-resolved period, and force the next `advanceGame()` to overwrite `redemptionPeriods[period].roll` with a fresh independent roll. **Independently re-derive the 19% per-iteration EV claim**; confirm/deny CATASTROPHE-tier under the 3-condition lens.
- **(b) V-031 placeDegeneretteBet → _collectBetFunds → prizePoolsPacked future-pool inflation** — FIXREC §0.4 headline-3 + §18 mark V-031 as MEDIUM-HIGH (cheapest per-tx surface that directly inflates `futurePool` which the jackpot consumer reads). Independently re-derive the bound; confirm/deny HIGH-tier.
- **(c) Cluster G manual-path lootbox open (§43..§62, 20 entries)** — FIXREC §0.4 headline-2 splits Cluster G into HIGH (cross-EOA `mintPacked_` / activity-score writes ~5 entries), MEDIUM-LOW (writer-side gate adds ~12 entries), NO REAL EV after lens (self-zero rows V-088/V-094/V-097/V-100/V-103). Independently re-derive: does the "self-zero is intended state machine" disposition hold structurally? Or is there a cross-index leak (Index A's open mutating Index B's commitment via shared parent slot)?
- **(d) Cluster E game-over `claimablePool` writers (§27..§33, 7 entries — V-054/V-055/V-057/V-058/V-063/V-064/V-065)** — FIXREC §0.4 headline-4 splits: HIGH (V-063 `_claimWinningsInternal`), MEDIUM (V-054/V-057/V-058/V-065 bounded), ZERO (V-055/V-064 already-gated). Note FIXREC §0.7 also marks V-063 as RECLASSIFY-TO-NON-PARTICIPATING (claimablePool is pull-pattern accumulator, NOT a VRF input). **The two dispositions conflict.** Resolve: is `claimablePool` consumed by §5 GameOverModule in a way that makes it a VRF-derived output input, or is it pull-pattern only?
- **(e) Cluster A hero-override (V-003..V-005, §1..§3)** — FIXREC §0.4 headline-5 marks MEDIUM at most (only flips one byte of one trait quadrant; dominant payout determinants don't depend on this slot). Independently re-derive the 0.5%–5% EV redirect claim.
- **(f) Admin classes** — for each ADMA R-01..R-22 admin function, is there a player-class actor who benefits from coordinating with admin-key-compromise? Skeptic-filter: admin-key-compromise threat model is OUT OF SCOPE for non-Governance findings (per FIXREC §0.5 Governance tier disposition: HIGH under owner-honest-but-curious; MEDIUM under owner-honest; not a non-admin exploit surface). Surface only paths where a NON-admin attacker plus the admin's normal-trust action produces a profit.

**Evidence anchors:**
- RNGLOCK-FIXREC.md §0 Executive Summary (full EV-tier breakdown post-lens); §1..§37 (Cluster A-E entries); §43..§62 (Cluster G); §103 (V-184 CATASTROPHE).
- RNGLOCK-FIXREC.md §103 V-184 with HANDOFF anchor `D-43N-V44-HANDOFF-111`; subsumption fan-out to V-186/V-188/V-190/V-191/V-192/V-193.
- ADMIN-AUDIT.md §3.01..§3.22 R-01..R-22 (per-admin actor walk).
- `feedback_skeptic_pass_before_catastrophe.md` 3-condition catastrophe lens.

**Expected disposition class:** V-184 expected `FINDING_CANDIDATE` (CATASTROPHE, but already documented in FIXREC §103; rather than re-emit, attest the documented disposition holds under independent re-derivation OR surface a tighter bound). Cluster E V-063 expected to resolve to one disposition (NON-PARTICIPATING vs FINDING_CANDIDATE). Other clusters expected `ACCEPTED_DESIGN` (documented in FIXREC at MEDIUM-LOW) or `SAFE_BY_STRUCTURAL_CLOSURE` (gate already in-source).

**Cross-cite:** `feedback_skeptic_pass_before_catastrophe.md` (3-condition lens); FIXREC §0.3 EV-tier discipline lens; FIXREC §0.5 EV-tier breakdown post-lens.

---

#### Hypothesis (iv) — SWP-04: FINDING_CANDIDATE elevation routing (procedural)

**Charge:** If you surface a `FINDING_CANDIDATE`, do NOT propose contract changes. Describe the vector + suggested remediation tactic (one of the FIX-01 menu: rngLockedFlag-gated revert / snapshot-anchor / re-order to pre-lock / immutable). Elevation routes to **FIXREC-augment append** per `D-302-AUDIT-ONLY-ROUTING-01`, NOT a contract change.

Note that:
- Any `SAFE_BY_DESIGN` candidate for a §14 PARTICIPATING SLOT is REJECTED per the milestone goal — if your evidence chain concludes `SAFE_BY_DESIGN` on a participating-slot writer, re-classify as `SAFE_BY_STRUCTURAL_CLOSURE` (closure is structural) or `FINDING_CANDIDATE` (closure is design-only, not structural).
- Non-participating-slot `SAFE_BY_DESIGN` dispositions remain valid (e.g., GNRUS charity-allowlist storage if the slot is not in §14).
- `RECLASSIFY-NON-PARTICIPATING` is a permissible disposition for slots that FIXREC §0.7 flags as PENDING-VERIFICATION or FALSE-POSITIVE-RECLASSIFY where your trace confirms the slot doesn't actually feed a VRF-derived output (lens condition #1 fails).

This hypothesis is procedural — your output for hypothesis (iv) is a single attestation line confirming: "I will route FINDING_CANDIDATE elevations through the FIXREC-augment append channel per D-302-AUDIT-ONLY-ROUTING-01, with severity per the 3-condition lens and suggested remediation drawn from the FIX-01 menu (a/b/c/d), with NO contract code in my output."

**Evidence anchors:** `D-302-AUDIT-ONLY-ROUTING-01` routing decision (`.planning/phases/302-cross-surface-adversarial-sweep-sweep/302-CONTEXT.md`); FIXREC §M consolidated handoff register (HANDOFF-01..HANDOFF-119).

**Expected disposition class:** This hypothesis exists for procedural attestation only. Return `SAFE` (procedural attestation) or `NEGATIVE_RESULT_ONLY` (no elevations) with the attestation line in Evidence.

---

#### Hypothesis (v) — SWP-05: Skill set + pre-authorization attestation (procedural)

**Charge:** Document the skill-set discipline + invocation pre-authorization.

- `/degen-skeptic` is OUT OF SCOPE per `D-271-ADVERSARIAL-02` carry.
- `/economic-analyst` is IN SCOPE per `D-271-ADVERSARIAL-03` carry.
- Invocation is pre-authorized per `D-43N-SWEEP-PREAUTH-01` (user-authorization 2026-05-18) — no user-ping for invocation; Tier-1 user-review checkpoint discipline at integration is preserved per `D-302-CONSENSUS-01` (carry of v42 D-296-CONSENSUS-01).
- Two-tier consensus rule:
  - **Tier 1:** any single skill flagging `FINDING_CANDIDATE` = user-review checkpoint at Task 5 integration via `AskUserQuestion` PAUSE.
  - **Tier 2:** 3-of-3 consensus `FINDING_CANDIDATE` = definitive elevation to FIXREC-augment + automatic RE-PASS per `D-302-REPASS-SCOPE-01`.
- Skeptic-reviewer filter (`feedback_skeptic_pass_before_catastrophe.md`) applied BEFORE user-presentation: structural-protection sanity checks + 3-condition catastrophe lens.

This hypothesis is procedural. Your output for hypothesis (v) is a single attestation line confirming the skill-set scope + pre-authorization disposition.

**Evidence anchors:** `D-271-ADVERSARIAL-02` (`/degen-skeptic` OUT); `D-271-ADVERSARIAL-03` (`/economic-analyst` IN); `D-43N-SWEEP-PREAUTH-01`; `D-302-CONSENSUS-01`; `D-302-REPASS-SCOPE-01`.

**Expected disposition class:** `SAFE` (procedural attestation).

---

### Group II — Carry-forward augments (v43-specific; per D-302-CHARGE-01)

#### Hypothesis (vi) — Augment (i): FIXREC-recommended tactic adequacy

**Charge:** For a representative subset of Phase 299 FIXREC entries — **top-3 by EV magnitude** — does the recommended tactic (rngLockedFlag-gated revert / snapshot-anchor / re-order / immutable) actually close the VIOLATION class **structurally**, or are there secondary attack paths the recommendation misses?

The three FIXREC entries to attest (selected by EV magnitude per FIXREC §0.4 + §0.5):

1. **V-184 — `redemptionPeriodIndex` (S-56) cross-day re-roll** at FIXREC §103, anchor `D-43N-V44-HANDOFF-111`. The recommended tactic-(a) revert in `_submitGamblingClaimFrom` when `redemptionPeriods[redemptionPeriodIndex].roll != 0`. Walk the post-fix state:
   - Does the revert close every cross-day re-arm path? Specifically, does the attacker have any OTHER path to mutate `redemptionPeriods[period].roll` for an already-resolved period? (e.g., direct admin write; alternative resolution paths; cross-contract callback)
   - Does the revert correctly handle the legitimate first-resolution case (`roll == 0` initially; legitimate `_submitGamblingClaimFrom` must succeed pre-resolution)?
   - Does the alternative tactic-(c) "advance the index inside `resolveRedemptionPeriod` itself" present a DIFFERENT residual attack surface? (e.g., gap in the index sequence; race during the advance write)
   - V-184 subsumes V-186/V-188/V-190/V-191/V-192/V-193 per FIXREC §0.6 — does the recommended fix at V-184 structurally close all 7 catalog rows, or are there subsumption-collapsed rows where the residual surface persists?

2. **V-031 — `prizePoolsPacked` via `placeDegeneretteBet → _collectBetFunds`** at FIXREC §18, anchor `D-43N-V44-HANDOFF-18` (or as listed). The recommended tactic. Walk the post-fix state for the cheapest-per-tx prize-pool inflation surface; identify secondary writers of `prizePoolsPacked.future` that the fix doesn't gate (the catalog enumerates many — V-024/V-025/V-026/V-027/V-030/V-032; does ANY single-entry gate close all of them, or is per-entry-gate the only structural close?).

3. **V-063 — `claimablePool -= ` via `_claimWinningsInternal`** at FIXREC §31, anchor `D-43N-V44-HANDOFF-31`. The recommended tactic-(a) `_livenessTriggered() && !gameOver` gate. FIXREC §0.7 notes V-063 is also a FALSE-POSITIVE-RECLASSIFY-TO-NON-PARTICIPATING candidate. Resolve the conflict: does the gate close the EV, or is the slot non-participating (lens condition #1 fails)? V-063 subsumes V-073 per FIXREC §0.6 — same question for the subsumed row.

For each of the 3 entries, walk the actor game-theory against the post-FIX state and surface any residual EV or secondary attack path.

**Evidence anchors:**
- RNGLOCK-FIXREC.md §103 (V-184 + subsumption to §104..§109); §0.6 subsumption map row HANDOFF-111.
- RNGLOCK-FIXREC.md §18 (V-031); §13..§19 (Cluster C top-level ungated EOA entry points).
- RNGLOCK-FIXREC.md §31 (V-063); §0.7 FALSE-POSITIVE-RECLASSIFY-TO-NON-PARTICIPATING marker.
- `contracts/StakedDegenerusStonk.sol` `_submitGamblingClaimFrom` + `resolveRedemptionPeriod`; `redemptionPeriods` + `redemptionPeriodIndex` slots.
- `contracts/modules/DegenerusGameDegeneretteModule.sol` `placeDegeneretteBet` + `_collectBetFunds` + `prizePoolsPacked` writers.
- `contracts/modules/DegenerusGameJackpotModule.sol` `_claimWinningsInternal` callsite at `:1399`; `_livenessTriggered` + `gameOver` reads.

**Expected disposition class:** Mixed. Expected outcomes: V-184 fix closes 7 rows structurally pending re-derivation; V-031 likely requires per-entry-gate (single-entry gate insufficient); V-063 RECLASSIFY-NON-PARTICIPATING preferred over gate-add. Any residual EV path surfaced → `FINDING_CANDIDATE` (FIXREC-augment §N+1 entry).

**Cross-cite:** `feedback_design_intent_before_deletion.md` (verify the original phase that introduced the slot/writer); `feedback_skeptic_pass_before_catastrophe.md` (3-condition lens to re-derive tier on the post-fix residual).

---

#### Hypothesis (vii) — Augment (ii): Admin-class cross-interaction

**Charge:** For Phase 300 ADMA recommendations R-01..R-22, are there admin-class combinations (e.g., governance + parameter-update + charity-allowlist + vault-routed sub-call invoked in sequence within rngLock window) that bypass any individual admin gate? Walk the admin call graph cross-product; identify any composition where two admin entry points called in sequence reach a participating slot via a path that neither alone touches.

Specifically check:

- **(a) Governance + parameter-update composition.** R-02 `updateVrfCoordinatorAndSub` (HANDOFF-78 fan-out closes V-137/V-155/V-157/V-159/V-161) is the highest-fanout admin writer. R-01 `wireVrf` (immutable post-init per HANDOFF-86) is one-shot. Is there a window between R-02 firing (rotation queue) and the underlying coordinator-change-applied state where a non-EXEMPT mutation could land?
- **(b) Charity-allowlist + vault-routed sub-call.** R-06 `setCharity` (GNRUS catalog-gap candidate; mid-rngLock changes the charity address that `pickCharity` reads from advanceGame's jackpot stack) — does a `setCharity` write between `_finalizeEarlybird` (`AdvanceModule:1718`) callsites (multi-call advanceGame flow) redirect sDGNRS Reward pool grants across charity addresses within a single resolution?
- **(c) Vault-routed admin sub-call cross-contract callback chains.** R-07..R-15 are vault-routed wrappers around game entries (purchase, purchaseCoin, purchaseBurnieLootbox, openLootBox, deity-pass purchase, placeDegeneretteBet, setAutoRebuy, setAutoRebuyTakeProfit, setAfKingMode). The vault-routed entries have a broader trust boundary (`vault.isVaultOwner`) than the game entries (`ContractAddresses.ADMIN`). Are there sequences where a vault-routed entry + a coin-routed callback (R-16 `coinDepositCoinflip`, R-17 `coinDecimatorBurn`) compose to reach a §14 slot during rngLock that the per-entry analysis missed?
- **(d) Cross-call admin sub-call into post-resolution claimWinnings.** R-18 `gameClaimWinnings` (vault-routed `claimWinnings`) reaches the same `_claimWinningsInternal` callsite as V-063. Is there an admin-vault composition where `gameClaimWinnings` fires mid-rngLock (vault-owner during resolution) that produces a different residual than EOA `claimWinnings`?
- **(e) GNRUS `setCharity` catalog-gap re-attestation.** ADMA R-06 explicitly flags `setCharity` as a catalog-gap candidate (GNRUS `currentSlate` not enumerated in CATALOG §14). Re-derive: should `currentSlate` be a §14 row? If yes, all R-06 implications must be re-evaluated as participating-slot writers.

**Evidence anchors:**
- ADMIN-AUDIT.md §0 Executive Summary (R-02 highest-fanout note; R-01 wireVrf one-shot note; R-03/R-04/R-05 stake-ETH residual EV notes).
- ADMIN-AUDIT.md §1 admin function enumeration (A-02..A-34).
- ADMIN-AUDIT.md §2 participating-slot cross-reference (per-admin slot writes).
- ADMIN-AUDIT.md §3.01..§3.22 per-admin recommendation walks.
- ADMIN-AUDIT.md §4 v44.0 consolidated handoff register.
- `contracts/GNRUS.sol:378` (`setCharity`); `:623` (`pickCharity`); `AdvanceModule.sol:1718` (`_finalizeEarlybird` `pickCharity` callsite).
- `contracts/DegenerusVault.sol:607` (vault-routed `placeDegeneretteBet`); `DegenerusVault.sol` (vault-routed entry surface for R-07..R-20).

**Expected disposition class:** Most compositions expected `SAFE_BY_STRUCTURAL_CLOSURE` (per-entry gates close composition). R-06 setCharity catalog-gap re-attestation expected `FINDING_CANDIDATE` if `currentSlate` is confirmed as a §14 participating slot read by jackpot-resolution stack. Vault-routed cross-trust-boundary residual expected `ACCEPTED_DESIGN` or `FINDING_CANDIDATE` per residual EV after lens.

**Cross-cite:** ADMIN-AUDIT.md §0 R-02 dual-role note (legitimate stall recovery vs mid-flight word swap); FIXREC §0.5 Governance tier disposition.

---

#### Hypothesis (viii) — Augment (iii): Phase 301 FUZZ harness `vm.skip` coverage gaps

**Charge:** The Phase 301 FUZZ harness contains **17 `vm.skip` blocks** per `D-301-VMSKIP-MECHANISM-01` Option C, each cross-referencing a RNGLOCK-FIXREC section + HANDOFF-NN anchor. Does the harness exercise enough perturbation classes per CAT-01 consumer to surface all VIOLATION instances, or are there perturbation classes the harness misses?

The 17 `vm.skip` blocks at v43 close (per `grep -n "vm.skip\|SKIP: RNGLOCK-FIXREC" test/fuzz/RngLockDeterminism.t.sol`):

| Line | Test function | SKIP reason (FIXREC sec + HANDOFF) |
|------|---------------|-------------------------------------|
| 401-402 | `testFuzz_RngLockDeterminism_PayDailyJackpot` | sec1 V-003 dailyHeroWagers hero-override writer race; HANDOFF-01 |
| 472-473 | `testFuzz_RngLockDeterminism_RunTerminalJackpot` | sec13 V-024/V-025/V-027/V-031 prizePoolsPacked terminal-jackpot inflation cluster; HANDOFF-13 |
| 544-545 | `testFuzz_RngLockDeterminism_PayDailyJackpotCoinAndTickets` | sec1 V-003..V-005 dailyHeroWagers + V-024 coin-and-tickets writer cluster; HANDOFF-02 |
| 628-629 | `testFuzz_RngLockDeterminism_RunTerminalDecimatorJackpot` | sec13..sec17 terminal-decimator prizePoolsPacked + decBucketOffsetPacked cluster; HANDOFF-13 |
| 732-733 | `testFuzz_RngLockDeterminism_ResolveRedemptionLootbox` | sec43..sec62 Cluster G commitment-window slot writers; HANDOFF-43 |
| 821-822 | `testFuzz_RngLockDeterminism_ResolveLootboxCommon` | sec43..sec62 Cluster G per-index lootbox-commitment slot writers; HANDOFF-43 |
| 948-949 | `testFuzz_RngLockDeterminism_DegeneretteLootboxDirect` | sec43..sec62 Cluster G per-index lootbox-commitment writers (degenerette-routed); HANDOFF-43 |
| 1034-1035 | `testFuzz_RngLockDeterminism_DecimatorAwardLootbox` | sec98/sec110/sec111 V-175/V-201/V-202 decimator-claim cross-call writers; HANDOFF-99 |
| 1150-1151 | `testFuzz_RngLockDeterminism_MintTraitGeneration` | sec0.7 V-127 lastPurchaseDay (RESOLVED-AS-PHANTOM) + Cluster H mintPacked writers; HANDOFF-77 (phantom-marker holds) — runtime-verify |
| 1209-1210 | `testFuzz_RngLockDeterminism_BurnieCoinflipResolve` | sec102 V-182 bountyOwedTo + Phase 296 (xiv) entropy-correlation Tier-1 ACCEPT_AS_DOCUMENTED; HANDOFF-110 |
| 1275-1276 | `testFuzz_RngLockDeterminism_StakedStonkRedemption` | sec103 V-184 sStonk cross-day re-roll CATASTROPHE; HANDOFF-111 |
| 1348-1349 | `testFuzz_RngLockDeterminism_GameOverRngSubstitution` | sec27..sec33 V-054/V-057/V-063/V-065 claimablePool gameover writer cluster; HANDOFF-31 |
| 1559-1560 | `testFuzz_EdgeCase_AdminDuringLock` | sec1 (inherited) admin-during-lock writer surface; HANDOFF-01 (inherited) |
| 1595-1596 | `testFuzz_EdgeCase_NearEndOfWindow` | sec1 (inherited) near-end-of-window perturbation; HANDOFF-01 (inherited) |
| 1639-1640 | `testFuzz_EdgeCase_MultiTxBatch` | sec1 (inherited) multi-tx-batch perturbation stack; HANDOFF-01 (inherited) |
| 1683-1684 | `testFuzz_EdgeCase_MultiBlock` | sec1 (inherited) multi-block perturbation spread; HANDOFF-01 (inherited) |
| 1734-1735 | `testFuzz_EdgeCase_RetryLootboxRngDuringLock` | sec43..sec62 (inherited Cluster G) retry-during-lock perturbation; HANDOFF-43 (inherited) |

Specifically check:

- **(a) Action coverage per consumer.** Are there participating slots in CAT-01 (13-consumer surface §1..§13) whose writer set is not exercised by any `_perturb(seed)` or `_perturbAdminOnly(seed)` action in the harness?
- **(b) Skip-mask-vs-genuine-gap.** Does any `vm.skip` mask a VIOLATION class that the harness's action coverage genuinely fails to reach (the harness can't reach the writer) vs the documented skip-for-future-fix-flip pattern (the harness reaches the writer; the test would FAIL pre-fix; skip is intentional)? The 17 skips by intent are documented as fix-flip; verify no genuine-coverage-gap is hiding behind a skip-comment.
- **(c) Edge-case coverage.** Are there edge cases that should be added but aren't? Specifically:
  - Multi-tx batched perturbations spanning the window (covered by `testFuzz_EdgeCase_MultiTxBatch` — but does it cover ALL writer paths or just sec1?)
  - Near-end-of-window perturbations (covered by `testFuzz_EdgeCase_NearEndOfWindow` — coverage breadth?)
  - `retryLootboxRng`-during-lock perturbations (covered by `testFuzz_EdgeCase_RetryLootboxRngDuringLock` — does it cover the §9 retryLootboxRng exemption envelope correctly?)
  - Cross-EOA Sybil during single rngLock window (NOT explicitly covered)
  - ERC777 / ERC721 receiver callback-induced perturbations (NOT explicitly covered)
  - Cross-day boundary at JACKPOT_RESET_TIME (the V-184 cross-day vector — is the harness's `testFuzz_RngLockDeterminism_StakedStonkRedemption` skip the right shape for cross-day, or does it only cover same-day?)
- **(d) `_perturb` / `_perturbAdminOnly` action set completeness.** `_perturb(seed)` covers 9 actions (0-8); `_perturbAdminOnly(seed)` covers ADMA R-01..R-22. Independent grep: does the action set in `_perturb` reach every §14 row's non-EXEMPT writer? For any §14 row not reachable from the action set, that is a coverage gap.

**Evidence anchors:**
- `test/fuzz/RngLockDeterminism.t.sol` lines 22-23 (vm.skip comment header); lines 401, 472, 544, 628, 732, 821, 948, 1034, 1150, 1209, 1275, 1348, 1559, 1595, 1639, 1683, 1734 (17 vm.skip blocks).
- `test/fuzz/RngLockDeterminism.t.sol` `_perturb(seed)` definition; `_perturbAdminOnly(seed)` definition; `_assertVrfOutputByteIdentity` shared assertion site.
- RNGLOCK-CATALOG.md §1..§13 (13-consumer surface — each must be covered by at least one fuzz function per FUZZ-04).
- ADMIN-AUDIT.md §1 (R-01..R-22 — `_perturbAdminOnly` coverage target).

**Expected disposition class:** Most skips expected `SAFE_BY_STRUCTURAL_CLOSURE` (skip-for-future-fix-flip pattern is intentional). Edge-case coverage gaps expected to surface as `FINDING_CANDIDATE` (FIXREC-augment §N+1 entry recommending a new fuzz function). ERC777/ERC721 callback coverage expected to surface as `FINDING_CANDIDATE` if the harness doesn't reach the callback surface.

**Cross-cite:** `D-301-VMSKIP-MECHANISM-01` Option C; `feedback_verify_call_graph_against_source.md` (grep-verify the `_perturb` action coverage against §14 writer set).

---

#### Hypothesis (ix) — Augment (iv): Cross-consumer entropy bleed

**Charge:** For shared participating slots SLOAD'd by multiple consumers (per RNGLOCK-CATALOG §14 unique-slot index), do cross-consumer perturbations create entropy correlation that breaks one consumer's determinism via another consumer's resolution path?

Apply `feedback_rng_window_storage_read_freshness.md` discipline: enumerate ALL SLOADs inside the rngLock window, not just VRF-derived seeds; non-VRF reads consumed alongside RNG are a distinct bug class (F-41-02/03 precedent).

The shared-slot inventory from §14 (slots SLOAD'd by ≥2 consumer sections):

| Slot | Module | Consumer §N list (multi-reader) | Cross-consumer potential |
|------|--------|---------------------------------|--------------------------|
| S-01 `dailyIdx` | Storage | §1, §2, §3, §8 | day-key shared across daily-jackpot + degenerette resolution |
| S-02 `dailyHeroWagers[day][q]` | Storage | §1, §2, §3 | jackpot-trait-symbol input across 3 jackpot paths |
| S-03 `level` | Storage | §1, §2, §5, §6, §7, §8, §10, §13 | level-keyed everywhere; high cross-consumer fanout |
| S-04 `gameOver` | Storage | §1, §3, §5, §12 | game-over flag across jackpot + sStonk resolution |
| S-06 `traitBurnTicket[lvl][trait]` | Storage | §1, §2, §3 | bucket population shared across daily/terminal jackpot |
| S-07 `deityBySymbol[fullSymId]` | Storage | §1, §2, §3 | deity-pass cross-jackpot |
| S-09 `prizePoolsPacked` | Storage | §1, §8 | future-pool shared across daily-jackpot + degenerette |
| S-13 `dailyTicketBudgetsPacked` | Storage | §1, §2 | ticket budget shared |
| S-14 `sDGNRS poolBalances[Reward]` | sDGNRS | §1, §8, §11 | Reward-pool cross-jackpot + coinflip resolution |
| S-15 `sDGNRS poolBalances[Lootbox]` | sDGNRS | §6, §7, §8 | Lootbox-pool cross-lootbox-flow |
| S-17 `pendingRedemptionEthValue` | sDGNRS | §5, §12 | game-over + sStonk redemption cross-read |
| S-18 `deityPassOwners` | Storage | §5, §7 | deity-pass owner-set cross-read |
| S-22 `lootboxEvBenefitUsedByLevel` | Storage | §6, §7, §8, §13 | EV-cap accumulator shared across 4 lootbox paths (the FIXREC §43..§45 V-081/V-082/V-084 cluster) |
| S-23 `lootboxRngWordByIndex[index]` | Storage | §7, §8, §10 | per-index VRF word shared across lootbox flows |
| S-30 `presaleStatePacked` | Storage | §7, §8, §11 | presale-state cross-flow |
| S-32 `mintPacked_[player]` | Storage | §7, §8, §10, §13 | mint-state cross-read (the FIXREC Cluster H pattern) |
| S-35..S-37 `lastPurchaseDay` / `jackpotPhaseFlag` / `purchaseStartDay` | Storage | §6, §7, §8 | purchase-cycle cross-state |
| S-38 `rngRequestTime` | Storage | §6, §7, §8, §9 | VRF-request-time cross-read (RETRY exemption cross-cut) |
| S-39 `rngLockedFlag` | Storage | §6, §7, §8 | lock-flag self-reference |
| S-40 `ticketWriteSlot` | Storage | §1, §2, §6, §7, §8, §10 | very-high-fanout ticket-write flag |
| S-41/S-42 affiliate/quest cross-contract | external | §7, §8 | cross-contract cached fields |
| S-46 `lootboxRngPacked` (LR_INDEX + LR_MID_DAY) | Storage | §9, §10 | retry + mint cross-read |
| S-63 `rngWordByDay[day]` | Storage | §5, §12 | game-over + sStonk cross-read |

For each shared slot, identify:

- **(a) Writer-set span.** Consumer A's path during its rngLock window can write the slot; Consumer B reads it at its resolution path. Even though the writer is not in B's exempt-entry-point set, the write might land between B's VRF request and fulfillment. Specifically check the highest-fanout slots: S-03 `level` (8 consumers); S-40 `ticketWriteSlot` (6 consumers); S-22 `lootboxEvBenefitUsedByLevel` (4 consumers — the FIXREC Cluster G/anti-farming EV-cap cluster).
- **(b) The FIXREC Cluster G EV-cap precedent.** S-22 `lootboxEvBenefitUsedByLevel` is a cross-resolution accumulator (FIXREC §43..§45 V-081/V-082/V-084) — per FIXREC §0.4 headline-2 and `feedback_rng_window_storage_read_freshness.md`, this is a "cross-resolution accumulator bypasses per-index snapshot — fundamental design break per Phase 298 §0 headline #2". Independently re-derive: is the recommended tactic-(b) snapshot-anchor adequate, OR does the cross-consumer fanout (4 consumers §6/§7/§8/§13) require a per-consumer snapshot mechanism?
- **(c) S-38 `rngRequestTime`** is read by §6/§7/§8/§9 (the latter being the retryLootboxRng path). The retry path uses `rngRequestTime != 0` as guard. If a daily-flow VRF request lands between a lootbox VRF request and its callback, does `rngRequestTime` overwrite cause cross-consumer confusion?
- **(d) Cross-contract reads.** S-14 / S-15 / S-17 / S-41 / S-42 / S-56..S-62 are cross-contract slots. The OZ-carveout pattern (V-046) addresses S-14 OZ-inherited writers; is there a parallel cross-contract entropy bleed in the sDGNRS redemption pair (S-17 + S-57..S-60 + S-61)?
- **(e) Cross-contract callback path** — `BurnieCoinflip` writes `bountyOwedTo` (S-55) which is read by §11 BurnieCoinflip and potentially observed across §12 sStonk resolution paths. FIXREC §102 (V-182 Phase 296 (xiv) carry) addresses one slice; is there a cross-consumer slice across §11 + §12?

**Evidence anchors:**
- RNGLOCK-CATALOG.md §14 unique-slot index (67 rows; cross-consumer count per slot).
- RNGLOCK-CATALOG.md §15 per-slot writer enumeration; §16 verdict matrix.
- RNGLOCK-CATALOG.md §6 LootboxModule.resolveRedemptionLootbox; §7 _resolveLootboxCommon; §8 DegeneretteModule._resolveLootboxDirect; §13 DecimatorModule._awardDecimatorLootbox (the 4 consumers of S-22 — the FIXREC Cluster G cross-consumer accumulator).
- RNGLOCK-FIXREC.md §43..§45 (V-081/V-082/V-084 lootboxEvBenefitUsedByLevel cluster); §0.4 headline-2 Cluster G HIGH-tier disposition.
- `feedback_rng_window_storage_read_freshness.md` (the F-41-02/03 precedent — non-VRF reads consumed alongside RNG are a distinct bug class).
- `feedback_rng_backward_trace.md` (every word must be unknown at input commitment time — same applies to ALL reads inside the window, not just VRF-derived seeds).

**Expected disposition class:** S-22 cross-consumer accumulator expected `FINDING_CANDIDATE` if tactic-(b) snapshot is single-consumer-scoped (cluster-G recommendation needs per-consumer snapshot per the §0.4 headline-2 HIGH-tier disposition). Most other shared slots expected `SAFE_BY_STRUCTURAL_CLOSURE` (existing gates close cross-consumer fanout). S-38 cross-consumer read expected `SAFE_BY_STRUCTURAL_CLOSURE` (`retryLootboxRng` cooldown + `LR_MID_DAY=1` gate). Any novel cross-consumer entropy bleed → `FINDING_CANDIDATE` (FIXREC-augment §N+1 entry).

**Cross-cite:** `feedback_rng_window_storage_read_freshness.md` (F-41-02/03 precedent); `feedback_rng_commitment_window.md` (state between VRF request and fulfillment); FIXREC §0.4 headline-2.

---

## Disposition Rubric (verbatim)

Each skill returns one of these dispositions per hypothesis:

- **SAFE** — verified safe via the cited evidence; no adversarial vector.
- **SAFE_BY_DESIGN** — intentional/documented design that closes the surface (NON-participating-slot vectors only).
- **SAFE_BY_STRUCTURAL_CLOSURE** — surface closed by structural property (state-machine gate, atomic write/consume pair, type-system invariant).
- **NEGATIVE_RESULT_ONLY** — searched the vector, found nothing exploitable; document the negative result.
- **ACCEPTED_DESIGN** — design tradeoff identified; not a finding (intentional EV reduction; user-accepted bytecode delta; documented ACCEPTED_DESIGN entries in FIXREC §0.5 LOW/ACCEPTABLE-DESIGN row).
- **FINDING_CANDIDATE** — vector exists; describe the finding + suggested remediation. DO NOT propose contract changes; descriptive only.

**Hard requirement: NO contract code in your output.** Suggested remediations are descriptive only per `feedback_never_preapprove_contracts.md` + `feedback_no_contract_commits.md`.

**Hard requirement: NO post-v43 milestone forward-cite tokens.** Use locked-decision IDs `D-43N-V44-HANDOFF-NN` + `D-43N-V44-ADMA-NN` + descriptive labels only.

**Beyond-charge entries.** Skills are free to surface beyond-charge hypotheses where they identify a novel attack surface; document each beyond-charge hypothesis with the same disposition rubric (SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / NEGATIVE_RESULT_ONLY / ACCEPTED_DESIGN / FINDING_CANDIDATE).

---

## Reference files

Read these for context (all paths absolute):

**Audit subjects (v43.0 audit-only deliverables — read-only inputs):**
- `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/RNGLOCK-CATALOG.md` (Phase 298; 13-consumer surface + 67-row §14 + §15 writers + §16 verdict matrix)
- `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/RNGLOCK-FIXREC.md` (Phase 299; 111 §N entries + §0 executive summary post-EV-tier-lens + 119 HANDOFF anchors)
- `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/ADMIN-AUDIT.md` (Phase 300; R-01..R-22 + R-06 catalog-gap candidate)
- `/home/zak/Dev/PurgeGame/degenerus-audit/test/fuzz/RngLockDeterminism.t.sol` (Phase 301 FUZZ harness; 13 consumer fuzz + 5 edge-case fuzz + 17 vm.skip)

**Contract source surface (mainnet `contracts/`):**
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/modules/DegenerusGameMintModule.sol`
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/modules/DegenerusGameJackpotModule.sol`
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/modules/DegenerusGameAdvanceModule.sol`
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/modules/DegenerusGameDegeneretteModule.sol`
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/modules/DegenerusGameWhaleModule.sol`
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/modules/DegenerusGameLootboxModule.sol`
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/modules/DegenerusGameDecimatorModule.sol`
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/modules/DegenerusGameGameOverModule.sol`
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/storage/DegenerusGameStorage.sol`
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusGame.sol`
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusVault.sol`
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusAdmin.sol`
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/StakedDegenerusStonk.sol`
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/BurnieCoinflip.sol`
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/BurnieCoin.sol`
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/GNRUS.sol`
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusDeityPass.sol`
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusAffiliate.sol`
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusQuests.sol`

**Methodology feedback (load-bearing for every hypothesis):**
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_skeptic_pass_before_catastrophe.md` (3-condition catastrophe lens)
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_rng_backward_trace.md` (RNG audit backward-trace)
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_rng_commitment_window.md` (commitment-window check)
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_rng_window_storage_read_freshness.md` (non-VRF reads inside the window)
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_verify_call_graph_against_source.md` (grep-verify "by construction" claims)
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_design_intent_before_deletion.md` (cite original phase that introduced the slot/writer)
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_never_preapprove_contracts.md` (no contract code in output)
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_no_contract_commits.md` (no contract commits)

**v42 P296 precedent (verbatim shape inheritance):**
- `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/milestones/v42.0-phases/296-cross-surface-adversarial-sweep-sweep/296-ADVERSARIAL-CHARGE.md` (charge document format reference)
- `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/milestones/v42.0-phases/296-cross-surface-adversarial-sweep-sweep/296-01-ADVERSARIAL-LOG.md` (integrated LOG format reference)

---

## Required output per skill

Single message containing **9 H2 sections** (`## Hypothesis (i)` through `## Hypothesis (ix)`), each with Disposition + Evidence + Notes blocks per the format above. If `FINDING_CANDIDATE` → include Description + Severity (per D-08 5-Bucket: CRITICAL / HIGH / MEDIUM / LOW / INFO; apply 3-condition lens) + Suggested remediation (FIX-01 menu: a/b/c/d).

Plus any **beyond-charge entries** under separate H2 sections with the same disposition rubric.

Output file: `.planning/phases/302-cross-surface-adversarial-sweep-sweep/302-ADVERSARIAL-<SKILL>.md` with YAML frontmatter `skill: <name>; phase: 302-cross-surface-adversarial-sweep-sweep; plan: 01; generated_at: <date>; charge_hypothesis_count: 9 charged + N beyond-charge`.

---

*Phase: 302-cross-surface-adversarial-sweep-sweep*
*Adversarial-charge: 9 hypothesis surfaces (5 SWP-NN verbatim + 4 carry-forward augments per D-302-CHARGE-01)*
*3-skill HYBRID dispatch per D-302-INVOKE-01 (Task 2 SEQUENTIAL_MAIN_CONTEXT for `/contract-auditor`; Tasks 3+4 PARALLEL_SUBAGENT for `/zero-day-hunter` + `/economic-analyst`)*
*D-271-ADVERSARIAL-01 + D-271-ADVERSARIAL-03 carry; `/degen-skeptic` OUT OF SCOPE per D-271-ADVERSARIAL-02*
*Two-tier consensus rule applies at integration per D-302-CONSENSUS-01; RE-PASS scope candidate-fix-only per D-302-REPASS-SCOPE-01*
*Elevation routes to FIXREC-augment per D-302-AUDIT-ONLY-ROUTING-01 (no contract change at v43 per audit-only posture; v44.0 FIX-MILESTONE consumes the FIXREC-augment §M handoff register)*
*Beyond-charge entries permitted; each MUST use the same 6-disposition rubric*
*Skeptic-reviewer filter per feedback_skeptic_pass_before_catastrophe.md applied at Task 5 integration (structural-protection check + 3-condition catastrophe lens) BEFORE any FINDING_CANDIDATE is presented to the user as actionable*
*Invocation pre-authorized per D-43N-SWEEP-PREAUTH-01 (user-authorization 2026-05-18)*
