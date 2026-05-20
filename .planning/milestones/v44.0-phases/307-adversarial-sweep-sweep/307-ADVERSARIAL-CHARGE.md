# Phase 307 Adversarial-Pass Charge — v44.0 sStonk Per-Day Redemption Refactor

**Phase:** 307-adversarial-sweep-sweep
**Plan:** 01
**Authored:** 2026-05-19
**Audit baseline:** v43.0 closure HEAD `MILESTONE_V43_AT_HEAD_8111cfc5189f628b64b500c881f9995c3edf0ed2`
**Subject under probe:** v44.0 IMPL HEAD (post-Phase 305) + post-Phase 306 TST coverage
**Pre-authorization:** D-44N-SWEEP-PREAUTH-01 (locked at Phase 304 SPEC signoff). 3-skill HYBRID fires without kickoff re-ping.
**Composition:** `/contract-auditor` SEQUENTIAL_MAIN_CONTEXT + `/zero-day-hunter` PARALLEL_SUBAGENT + `/economic-analyst` PARALLEL_SUBAGENT per D-307-DISPATCH-01 (carry of D-302-INVOKE-01).
**Out-of-scope skills:** `/degen-skeptic` (D-271-ADVERSARIAL-02 carry).

---

## §0 Charge-Frame

### Composition and sequencing (D-307-DISPATCH-01)

- **Task 2 `/contract-auditor`** — SEQUENTIAL_MAIN_CONTEXT in the orchestrator's main context (NOT via Task subagent). Runs to completion FIRST so its disposition MD is available as anchoring context for the parallel hunter + economist pair.
- **Tasks 3 + 4 `/zero-day-hunter` + `/economic-analyst`** — PARALLEL_SUBAGENT spawned via a single-message multi-Task block (two `Task` tool calls in one block). Both receive the auditor MD as anchoring context (avoids redundant rediscovery; forces cross-skill coverage divergence).
- **HYBRID-fallback allowance** — If parallel-subagent dispatch fails (subagent crash, malformed output, timeout, persona drift) for any one of the parallel skills, fall back to SEQUENTIAL_MAIN_CONTEXT for that skill and document the fallback reason in the per-skill MD's `[invocation]` frontmatter.

### Two-tier consensus rule (D-302-CONSENSUS-01 carry)

- **Tier-1** — Any single skill's `FINDING_CANDIDATE` that survives the dual-gate skeptic filter → AskUserQuestion user-pause at Task 5 integration time. User adjudicates (elevate / SAFE_BY_DESIGN / NEGATIVE-VERIFIED-on-reconsideration).
- **Tier-2** — 3-of-3 cross-skill consensus `FINDING_CANDIDATE` on the same hypothesis → automatic elevation + RE-PASS per D-284-ADVERSARIAL-RE-PASS-01 (no user-pause required for the elevation itself; user diff review still required for any `contracts/*.sol` change per feedback_manual_review_before_push.md).
- **unanimous-NEGATIVE** — No surviving `FINDING_CANDIDATE` from any skill → no elevation, no user-pause. Task 6 precondition gate fails; phase proceeds directly to Task 7.

### 6-classification disposition rubric

Per-hypothesis verdict ∈ {`NEGATIVE-VERIFIED`, `FINDING_CANDIDATE`, `SAFE_BY_DESIGN`} crossed with per-skill source ∈ {`/contract-auditor`, `/zero-day-hunter`, `/economic-analyst`} = 9 disposition combinations, each row recorded in §1 of the per-skill MD and aggregated at Task 5 integration into `307-01-ADVERSARIAL-LOG.md`.

- **NEGATIVE-VERIFIED** — Hypothesis was probed concretely (with file:line trace through current source) and found unreachable / non-exploitable / structurally closed. Cite the structural protection.
- **FINDING_CANDIDATE** — Hypothesis surfaces a reachable-by-attacker exposure with a concrete attack narrative + (b)/(c) EV-lens signal. Must carry a severity tag from {CATASTROPHE, HIGH, MEDIUM, LOW, N-A}.
- **SAFE_BY_DESIGN** — Hypothesis points at a design choice the protocol intentionally made (e.g., dust truncation per SPEC-04 (b), per-day cap reset semantics per EDGE-16). Cite the SPEC/INV/EDGE ID that documents the intentional design.

---

## §1 SWP-01..05 verbatim charges (quoted from `.planning/REQUIREMENTS.md`)

## SWP-01 (charged to `/contract-auditor`, SEQUENTIAL_MAIN_CONTEXT)

> `/contract-auditor` SEQUENTIAL_MAIN_CONTEXT pass. Charge: find any state transition that violates INV-01..12; any (burn, advance, claim, gameOver) interleaving that produces an exploitable outcome; any storage-collision or packing bug in the new layout.

**Note:** Phase 305 IMPL introduced INV-13 (single-pool invariant, per D-305-SENTINEL-01) — auditor extends INV-01..12 scope to INV-01..13 verbatim. INV-13 emergent surface treated as first-class invariant under SWP-01.

## SWP-02 (charged to `/zero-day-hunter`, PARALLEL_SUBAGENT)

> `/zero-day-hunter` PARALLEL_SUBAGENT pass. Charge: novel attack surfaces on the per-day refactor — composition with lootbox/coinflip flows; ERC20 callback-induced re-entry on transfer paths; cross-module read/write races between sStonk and DegenerusGame storage.

## SWP-03 (charged to `/economic-analyst`, PARALLEL_SUBAGENT)

> `/economic-analyst` PARALLEL_SUBAGENT pass. Charge: game-theoretic write-induced effects under the per-day model; coordinated-burn scenarios; timing arbitrage between gap burns vs post-advance burns; MEV surfaces on the new state machine.

## SWP-04 (Two-tier consensus; orchestrator at Task 5)

> Two-tier consensus per D-302-CONSENSUS-01. Tier 1 any-skill FINDING_CANDIDATE → AskUserQuestion PAUSE. Tier 2 3-of-3 consensus → automatic elevation + RE-PASS per D-284-ADVERSARIAL-RE-PASS-01 against the FIXREC-augment diff.

## SWP-05 (Per-skill disposition table)

> Disposition table per skill — every charged hypothesis + beyond-charge entries get NEGATIVE-VERIFIED / FINDING_CANDIDATE / SAFE_BY_DESIGN classification. Skeptic-reviewer filter per feedback_skeptic_pass_before_catastrophe.md (structural-protection check + 3-condition EV lens) applied BEFORE any user-pause.

---

## §2 v44-specific carry-forward augments (i)..(v) (per D-307-CHARGE-01)

Each augment is charged to ALL 3 skills; per-skill MDs each carry one row per augment. Augments target Phase 305 IMPL emergent surfaces (D-305-* decision lineage) that did not exist at v43 audit baseline.

### Augment (i) — 1-slot DayPending packing edges

**Target:** `D-305-STRUCT-TIGHTEN-01` 1-slot 4×uint64 packing with mixed denominations.

**Probe:**
- uint64 overflow boundaries under maximally-pessimal whale-day burn aggregation. Worst-case theoretical pool size: 10k wallets × 160 ETH cap = 1.6e15 gwei vs uint64.max = 1.844e19 (~11500× headroom — confirm headroom holds under accumulated dust + edge interactions).
- Denomination-conversion edge cases at small/large/zero values (gwei for `ethBase`/`burnieBase`; whole-tokens for `supplySnapshot`/`burned`).
- gwei↔wei conversion ordering inside `_payEth`/`_payBurnie` (multiplication-before-division vs division-before-multiplication; ordering must reconstruct exact sum-of-claims at resolve).
- Sub-gwei dust loss bounded vs cumulative drift across multi-day claims (does `pendingRedemptionEthValue` ever diverge from `pool.ethBase × 1e9` summed across all unresolved days by more than INV-02's dust tolerance?).
- Misaligned bit-shift corruption on a packed-load (does writing to `pool.burned` ever spill into `pool.supplySnapshot`? Does writing `pool.ethBase` ever spill into `pool.burnieBase`?).

**Evidence anchors:**
- `contracts/StakedDegenerusStonk.sol:247` (`struct DayPending { uint64 ethBase; uint64 burnieBase; uint64 supplySnapshot; uint64 burned; }`)
  - **grep:** `grep -nE 'struct DayPending' contracts/StakedDegenerusStonk.sol` → `247:    struct DayPending {`
- `contracts/StakedDegenerusStonk.sol:259` (`mapping(uint32 => DayPending) internal pendingByDay;`)
  - **grep:** `grep -nE 'pendingByDay' contracts/StakedDegenerusStonk.sol` → `259:    mapping(uint32 => DayPending) internal pendingByDay;`
- `contracts/StakedDegenerusStonk.sol:828-836` (snapshot lazy-init + ceiling-divide cap enforcement)
- `contracts/StakedDegenerusStonk.sol:858-861` (gwei snap with `unchecked` block)
- `contracts/StakedDegenerusStonk.sol:874-877` (cumulative + per-day-pool gwei segregation)
- `contracts/StakedDegenerusStonk.sol:639-640` (resolve-side wei reconstruction via `× 1e9`)
- D-305-STRUCT-TIGHTEN-01 decision lineage (Phase 305 IMPL summary)
- INV-04 (per-day base correctness), INV-05 (cumulative correctness), INV-10 (per-day supply cap)

### Augment (ii) — `pendingResolveDay` sentinel race/collision

**Target:** `D-305-SENTINEL-01` 32-bit slot enforcing single-pool invariant (INV-13) via `PriorDayUnresolved` revert.

**Probe:**
- Sentinel-vs-pool desync attacks: can the sentinel ever name a day whose `pendingByDay[D]` was already cleared, or vice versa (a `pendingByDay[D]` with non-zero base whose sentinel is 0)?
- Multi-day stall recovery semantics: AdvanceModule reads the sentinel at three call sites (`:1228`, `:1294`, `:1327`) and writes a resolve at the matching call sites (`:1234`, `:1300`, `:1333`). Does any RNG-stall path (12h retry, 3-day fallback, gameOver entropy with stall) ever fire a `resolveRedemptionPeriod` against a `dayToResolve` ≠ sentinel?
- Sentinel staleness under `gameOver` mid-stall: if `gameOver` latches while sentinel is set, does the gameOver entropy path correctly resolve the stamped day, or does it skip + leave the sentinel pointing at a deleted-pool day forever?
- Cross-actor sentinel races: one player's burn sets the sentinel; another player's claim or burn or transfer reads it. Is the sentinel ever read by a different actor between set and clear in a way that produces an incorrect verdict?
- Sentinel clear-on-resolve ordering (`:665` — `if (pendingResolveDay == dayToResolve) pendingResolveDay = 0;`). If `resolveRedemptionPeriod` reverts after the `delete pendingByDay[dayToResolve]` at `:662` but before `:665` clears the sentinel, can sentinel + pool ever land in an unrecoverable desync? (No reverts in `:662-665` post-`delete`, but probe whether OOG or external trigger can interpose.)
- Single-pool invariant integrity: per INV-13, at most one day's pool may be unresolved at any time. Is there any code path that creates a second unresolved pool without setting the sentinel first?

**Evidence anchors:**
- `contracts/StakedDegenerusStonk.sol:119` (`error PriorDayUnresolved();`)
  - **grep:** `grep -nE 'PriorDayUnresolved' contracts/StakedDegenerusStonk.sol` → `119:    error PriorDayUnresolved();`
- `contracts/StakedDegenerusStonk.sol:269` (`uint32 public pendingResolveDay;`)
  - **grep:** `grep -nE 'pendingResolveDay' contracts/StakedDegenerusStonk.sol` → `269:    uint32 public pendingResolveDay;` + 4 read/write sites.
- `contracts/StakedDegenerusStonk.sol:665` (`if (pendingResolveDay == dayToResolve) pendingResolveDay = 0;`)
- `contracts/StakedDegenerusStonk.sol:819-821` (sentinel-read + PriorDayUnresolved revert + sentinel-write inside `_submitGamblingClaimFrom`)
- `contracts/modules/DegenerusGameAdvanceModule.sol:1228, 1294, 1327` (three reader call sites)
  - **grep:** `grep -nE 'pendingResolveDay\(\)' contracts/modules/DegenerusGameAdvanceModule.sol` → `1228, 1294, 1327`
- `contracts/modules/DegenerusGameAdvanceModule.sol:1234, 1300, 1333` (three writer call sites)
- D-305-SENTINEL-01 decision lineage; INV-13 single-pool invariant.

### Augment (iii) — gwei-snap precision interaction with cap arithmetic

**Target:** `D-305-GWEI-SNAP-01` snaps `ethValueOwed`/`burnieOwed` to gwei at source for exact `× roll / 100` arithmetic (`gcd(1e9, 100) = 100`).

**Probe:**
- Precision edge cases where snap-truncation interacts with the 160 ETH `MAX_DAILY_REDEMPTION_EV` cap (INV-11). Can a player snap-truncate just below the cap, then accumulate one more burn that — pre-snap — would have exceeded the cap?
- Per-(player, day) accumulation across multiple sub-claims: `claim.ethValueOwed += uint96(ethValueOwed)` at `:885`. Does the snap interact with the cap check at `:883` (`claim.ethValueOwed + ethValueOwed > MAX_DAILY_REDEMPTION_EV`) in a way that lets a player extract more than 160 ETH of EV per day via snap-rounding-down per-burn?
- Rounding semantics at the boundary where `ethValueOwed % 1e9 != 0`. Does the snap create a manipulable surplus or deficit between `pool.ethBase × 1e9` and the actual sum of `pendingRedemptions[player][day].ethValueOwed` values across players for the same day?
- gwei snap × 100-roll arithmetic at resolve: `rolledEth = (ethBase * roll) / 100` at `:644`. Worst-case dust: roll ∈ [25,175], 99-wei dust per period (pre-snap). Post-snap, does the dust bound widen, narrow, or shift in a way that breaks INV-02?
- BURNIE side mirror: `burnieToCredit = (burnieBase * roll) / 100` at `:648`. Same probe with BURNIE units (also gwei-snapped per D-305-GWEI-SNAP-01).

**Evidence anchors:**
- `contracts/StakedDegenerusStonk.sol:292` (`uint256 private constant MAX_DAILY_REDEMPTION_EV = 160 ether;`)
- `contracts/StakedDegenerusStonk.sol:858-861` (gwei snap with `unchecked` block — `ethValueOwed = (ethValueOwed / 1e9) * 1e9; burnieOwed = (burnieOwed / 1e9) * 1e9;`)
- `contracts/StakedDegenerusStonk.sol:874-877` (cumulative + per-day-pool gwei segregation post-snap)
- `contracts/StakedDegenerusStonk.sol:883` (EV cap check post-snap)
- `contracts/StakedDegenerusStonk.sol:644` (resolve-side `× roll / 100`)
- `contracts/StakedDegenerusStonk.sol:648` (BURNIE resolve-side `× roll / 100`)
- `contracts/StakedDegenerusStonk.sol:688` (claim-side `× roll / 100`)
- D-305-GWEI-SNAP-01 decision lineage; INV-11 EV cap.

### Augment (iv) — Phase 306 INV harness perturbation-class gaps

**Target:** Phase 306 TST proved 13 INV + 20 EDGE + 8 per-function fuzz + V-184 strict-byte-identity + 2 gas regression assertions at deep × 256 × 128. The 5-action `RedemptionHandler` exercises {`action_burn`, `action_advance`, `action_claim`, `action_gameOver`, `action_burnOnPreviousDay`}.

**Probe (the harness PROVED what it tested; this augment hunts for what it did NOT test):**
1. **Transfer mid-pending** — sDGNRS ERC20 `transfer` / `transferFrom` mid-pending-pool (between burn and advance, between advance and claim). Does totalSupply mutation while a `pendingByDay[D].supplySnapshot` is locked break INV-10 cap accounting on a later same-day burn?
2. **Approve mid-stall** — ERC20 `approve` while sentinel-stamped: does `approve` interact with the redemption flow in any way that affects pool accounting?
3. **Multi-actor sentinel race** — Two distinct players' burns landing in the same day-D window, one before and one after the sentinel write at `:821`. The harness probably tests sequential burns; can two interleaved burns produce inconsistent state?
4. **ERC20-callback-induced state mutation during burn/claim** — Although sDGNRS itself has no callbacks on transfer (basic ERC20), the burn flow invokes `coin.transfer`, `coinflip.claimCoinflipsForRedemption`, `game.claimWinnings`, `game.resolveRedemptionLootbox` — each external call is a re-entry surface. Can a malicious external contract (e.g., a player's malicious recipient) re-enter `claimRedemption` or `burn` and corrupt state?
5. **Coinflip pool drain mid-multi-day-claim** — Player burns on day D, day D+1; coinflip pool drains between D and D+1 claims. Does `_payBurnie` fallback to `coinflip.claimCoinflipsForRedemption(address(this), remaining)` revert if the coinflip pool is dry, leaving partial-claim state stuck?
6. **Partial-claim BURNIE branch under sentinel-stall** — `claimRedemption` has a partial-claim branch (`:715-721`) for unresolved coinflip days where ETH is paid but BURNIE remains. Does a sentinel-stall affecting the coinflip resolution interact with this branch in a way that drops a player's BURNIE or double-pays it?
7. **Admin-class actions during rngLock mid-pending** — Governance actions (e.g., setting allowed-charity addresses, admin transfers from pools) during rngLock window mid-pending. Do any admin paths SLOAD from `pendingByDay` or `pendingResolveDay` and inject state that breaks INV-04 / INV-05?
8. **rngLock + sentinel double-window** — Phase 306's `RedemptionHandler` does NOT exercise burns/claims during the rngLock window (those revert per EDGE-11). Probe: are there other entry points (e.g., vault `sdgnrsClaimRedemption(day)`) that could end-run the rngLock guard?

**Evidence anchors:**
- `test/invariant/RedemptionAccounting.t.sol` — 13 invariant_INV_NN_* functions (Phase 306 VERIFICATION); coverage gap target.
- `test/fuzz/handlers/RedemptionHandler.sol` — 5-action handler; only {burn, advance, claim, gameOver, burnOnPreviousDay}; perturbation classes 1-8 above NOT in the action set.
- `contracts/StakedDegenerusStonk.sol:809-895` (`_submitGamblingClaimFrom` — re-entry surfaces at `coin.transfer`, `game.claimWinnings`, etc.).
- `contracts/StakedDegenerusStonk.sol:675-740` (`claimRedemption` — partial-claim branch + external calls).
- 306-VERIFICATION.md (proven coverage shape).

### Augment (v) — Vault scope-expansion ACL surface

**Target:** `DegenerusVault.sdgnrsClaimRedemption(uint32 day) external onlyVaultOwner` added during Phase 305 IMPL as scope-expansion.

**Probe:**
- Vault-managed claim flow ACL coverage. `onlyVaultOwner` at `:431` modifier requires caller to hold >50.1% of DGVE. Probe: what happens if vault-ownership flips (one player accumulates >50.1% DGVE, claims, then DGVE rebalances) mid-pending?
- Interaction with `DegenerusVault`'s own pending-state machine. Does the vault track any per-day or per-pending state of its own that could desync with sStonk's `pendingRedemptions[vault][day]`?
- Reentrancy on the vault claim path: `sdgnrsClaimRedemption` → `sdgnrsToken.claimRedemption(day)` → re-enters back into the vault via `_payEth` (vault's receive() / fallback) and `_payBurnie` (vault's coin balance). Is the vault's `receive()` / fallback safe under reentry from sStonk during a claim?
- Cross-actor vault-claim manipulation: vault owner vs ultimate beneficiary. Can a vault owner direct a `claimRedemption` whose ETH/BURNIE the vault then absorbs, without distributing pro-rata to DGVE/DGVB holders?
- Composability with other vault entry points: does `sdgnrsClaimRedemption` interact with `gameAdvance`, `gameClaimWinnings`, `gameClaimWhalePass`, `burnSdgnrs`, etc., in a way that creates a profitable ordering for the vault owner at the expense of the vault's other share holders?

**Evidence anchors:**
- `contracts/DegenerusVault.sol:729` (`function sdgnrsClaimRedemption(uint32 day) external onlyVaultOwner`)
  - **grep:** `grep -nE 'sdgnrsClaimRedemption' contracts/DegenerusVault.sol` → `729:    function sdgnrsClaimRedemption(uint32 day) external onlyVaultOwner {`
- `contracts/DegenerusVault.sol:431` (`modifier onlyVaultOwner()`)
  - **grep:** `grep -nE 'onlyVaultOwner' contracts/DegenerusVault.sol` → `431:    modifier onlyVaultOwner() {` (+ N usage sites)
- `contracts/DegenerusVault.sol:730` (delegate to `sdgnrsToken.claimRedemption(day)`)
- `contracts/StakedDegenerusStonk.sol:675-740` (`claimRedemption` reentry surface)
- Phase 305 SUMMARY scope-expansion note.

---

## §3 Dual-gate skeptic-reviewer filter protocol (D-307-SKEPTIC-FILTER-01)

### Filter location: dual gate

1. **Per-skill self-filter** — Each skill applies the filter to its own `FINDING_CANDIDATE` set BEFORE writing its per-skill MD. Discards documented in a "Skeptic-Filter Self-Discarded" subsection within the MD AND in the `[skeptic-filter]` frontmatter `discarded: []` array.
2. **Orchestrator integration-time re-application** — At Plan Task 5 (integration), the orchestrator re-applies the filter against the aggregated `FINDING_CANDIDATE` set across all 3 skill MDs. Discards at integration time are documented inline in `307-01-ADVERSARIAL-LOG.md` Disposition section per D-307-AUDIT-TRAIL-01.

### Structural-protection arm: STRICT

A finding is discarded under the structural-protection arm **only** if the code path makes the attack **literally physically unreachable** — e.g.:
- `delete pendingByDay[D]` after resolve makes the V-184 overwrite primitive unreachable.
- The `PriorDayUnresolved` revert at `contracts/StakedDegenerusStonk.sol:820` makes cross-day pool accumulation literally impossible (the second burn reverts).
- The type system forbids the input (e.g., `uint32` cap prevents day > 2^32-1).

**Defense-in-depth alone (ACL gate + downstream secondary check) does NOT pass the filter** — those findings surface to user-pause.

### 3-condition EV lens

- **(a)** attacker controls the necessary state;
- **(b)** the manipulation produces a measurable economic gain;
- **(c)** the gain exceeds gas cost + opportunity cost + risk cost.

**(a) is the ONLY hard discard condition.** If the attacker does NOT control the necessary state, the filter discards the finding (no exploitable scenario can be constructed). **(b) measurability + (c) gain-vs-cost** are **severity-downgrade** signals — they DOWNGRADE the severity tag (CATASTROPHE → HIGH → MEDIUM → LOW) and document the downgrade rationale. They do NOT discard.

### `[skeptic-filter]` frontmatter shape (per-skill MD MUST include)

```yaml
[skeptic-filter]
discarded:
  - hypothesis-id: "<augment-letter or SWP-NN-sub-id>"
    structural-protection-citation: "<contracts/Foo.sol:LINE>"
    ev-lens-failed-condition: "a"   # always "a" for discards
    note: "<one-line explanation>"
```

Empty array (`discarded: []`) is valid if the skill found no discards.

---

## §4 Disposition-table column schema (D-307-AUDIT-TRAIL-01)

### Skeptic-Filter Discarded inline table (Task 5 LOG)

| Hypothesis-ID | Source skill | Structural-protection citation (file:line) | EV-lens failed condition | Note |
| ------------- | ------------ | ------------------------------------------ | ------------------------ | ---- |

Populated from (a) the union of all 3 per-skill `[skeptic-filter]` frontmatter `discarded` arrays AND (b) any additional orchestrator integration-time discards.

### Integrated Disposition table (Task 5 LOG; survivors only)

| Hypothesis-ID | Source skill | Verdict (NEGATIVE-VERIFIED / FINDING_CANDIDATE / SAFE_BY_DESIGN) | Severity tag (CATASTROPHE / HIGH / MEDIUM / LOW / N-A) | (b)+(c) downgrade rationale | Cross-skill consensus state (Tier-1 / Tier-2 / unanimous-NEGATIVE) |
| ------------- | ------------ | --------------------------------------------------------------- | ------------------------------------------------------ | --------------------------- | ------------------------------------------------------------------ |

### Severity-Downgrade Rationale table (Task 5 LOG)

For every surviving FINDING_CANDIDATE whose severity was downgraded under (b) or (c) arms, document the original-vs-downgraded severity + the (b)/(c) signal that drove the downgrade.

### Per-skill MD §1 disposition table (Tasks 2/3/4)

Columns: Hypothesis-ID, Verdict, Severity tag, Evidence anchors (file:line + INV/EDGE/SPEC IDs), Reasoning summary.

---

## §5 Elevation-routing protocol (D-307-ELEVATION-ROUTING-01)

Any Tier-1 user-approved or Tier-2 auto-elevated `FINDING_CANDIDATE` routes to:

1. **Author `307-FIXREC-AUGMENT.md`** (AGENT-COMMITTED) capturing:
   - VIOLATION class.
   - Recommended structural close (preferred — eliminates the attack primitive entirely) OR defense-in-depth mitigation (fallback when structural close infeasible).
   - Per-hypothesis evidence anchors (file:line + INV/EDGE/SPEC IDs + cross-reference to the surviving Disposition row).
   - v44 handoff anchor `D-44N-V44-AUGMENT-NN` (assign next free NN per `.planning/REQUIREMENTS.md` convention).

2. **If the close requires a `contracts/*.sol` diff:**
   - Batch the diff per feedback_batch_contract_approval.md (ONE consolidated diff covering ALL elevated remediations).
   - Present the diff to the USER for review per feedback_manual_review_before_push.md + feedback_never_preapprove_contracts.md (the orchestrator MUST NOT pre-approve the diff for sub-agents).
   - Land the contract diff as a **SEPARATE USER-APPROVED commit** (NOT bundled into the Task 7 agent commit).

3. **If the close requires `test/*.sol` augmentation:**
   - Bundle the test edit with the FIXREC-augment commit per feedback_no_contract_commits.md clarified policy (`test/` autonomy applies within the FIXREC-augment envelope).

4. **Trigger RE-PASS per D-302-REPASS-SCOPE-01:**
   - Dispatch the 3 skills against (augment diff + affected hypothesis subset ONLY — other hypotheses keep their original-pass disposition).
   - Produce `307-ADVERSARIAL-RE-PASS-{CONTRACT-AUDITOR,ZERO-DAY-HUNTER,ECONOMIC-ANALYST}.md` mirroring v42 P296 / v41 P284 convention.
   - Integrate into a `## Second-Pass (RE-PASS) Disposition` section appended to `307-01-ADVERSARIAL-LOG.md`.

5. **Cross-cite from Phase 308 §4 (AUDIT-06):**
   - Forward-cite placeholder in `307-01-ADVERSARIAL-LOG.md` §8 — Phase 308 resolves at TERMINAL.

**Memory anchors applied:** feedback_wait_for_approval.md + feedback_manual_review_before_push.md + feedback_batch_contract_approval.md + feedback_never_preapprove_contracts.md + feedback_no_contract_commits.md + feedback_design_intent_before_deletion.md (if augment proposes deletion) + feedback_frozen_contracts_no_future_proofing.md (no future-extensibility scaffolding).

---

## §6 Boilerplate

### Pre-authorization

- **D-44N-SWEEP-PREAUTH-01** — Locked at Phase 304 SPEC signoff. Phase 307 fires the 3-skill HYBRID without re-pinging at plan kickoff. Tier-1 single-skill `FINDING_CANDIDATE` still triggers AskUserQuestion user-pause per D-302-CONSENSUS-01 carry; Tier-2 3-of-3 auto-elevates without user checkpoint.

### Out-of-scope skills

- **D-271-ADVERSARIAL-02 (carry):** `/degen-skeptic` OUT OF SCOPE for Phase 307.
- **D-271-ADVERSARIAL-03 (carry):** `/economic-analyst` IN SCOPE for Phase 307.

### Consensus rule

- **D-302-CONSENSUS-01 (carry):** Two-tier consensus — Tier-1 user-pause + Tier-2 auto-elevate + RE-PASS.

### HYBRID-fallback allowance

- Per ROADMAP allowance: if parallel-subagent dispatch fails for `/zero-day-hunter` or `/economic-analyst`, fall back to SEQUENTIAL_MAIN_CONTEXT for the failing skill. Document the fallback in the per-skill MD's `[invocation]` frontmatter:

```yaml
[invocation]
mode: HYBRID_FALLBACK_SEQUENTIAL
reason: "<subagent crash / malformed output / timeout / persona drift detail>"
```

Persona fidelity preserved via the dedicated per-skill MD with verbatim CHARGE re-anchored.

### Mutations policy

- **Zero `contracts/*.sol`** and **zero `test/*.sol`** mutations during the pass EXCEPT via the D-307-ELEVATION-ROUTING-01 Task 6 envelope.
- Any `contracts/*.sol` diff at Task 6 lands as a SEPARATE USER-APPROVED commit per feedback_batch_contract_approval.md + feedback_never_preapprove_contracts.md + feedback_manual_review_before_push.md.
- Any `test/*.sol` augmentation at Task 6 bundles with the FIXREC-augment commit per feedback_no_contract_commits.md clarified policy.
- KNOWN-ISSUES.md **UNMODIFIED** per D-44N-KI-01. Phase 308 §6 re-verifies EXC-01..04 RE_VERIFIED-NEGATIVE-scope without mutation.

### Memory anchors (load-bearing for this phase)

- `feedback_skeptic_pass_before_catastrophe.md` — Operationalized via D-307-SKEPTIC-FILTER-01.
- `feedback_verify_call_graph_against_source.md` — Every file:line anchor in §2 grep-verified pre-write.
- `feedback_rng_backward_trace.md` — Applied to augments (ii) + (iv) RNG-touching hypotheses.
- `feedback_rng_commitment_window.md` — Applied to augment (ii) sentinel state-machine probes.
- `feedback_rng_window_storage_read_freshness.md` — Applied to augment (iv) Phase 306 INV harness perturbation-class gap probe.
- `feedback_security_over_gas.md` — Reject any gas optimization that weakens an invariant; security is hard floor.
- `feedback_no_history_in_comments.md` — Artifacts describe what IS; no "changed from" / "used to be" framing.

---

## §7 Required output per skill

Each per-skill MD (`307-ADVERSARIAL-CONTRACT-AUDITOR.md`, `307-ADVERSARIAL-ZERO-DAY-HUNTER.md`, `307-ADVERSARIAL-ECONOMIC-ANALYST.md`) MUST include:

1. **`[invocation]` frontmatter** — `mode: <SEQUENTIAL_MAIN_CONTEXT | PARALLEL_SUBAGENT | HYBRID_FALLBACK_SEQUENTIAL>` + dispatch timestamp + (if fallback) reason.
2. **`[skeptic-filter]` frontmatter** — `discarded: []` array per D-307-SKEPTIC-FILTER-01 per-skill self-filter arm.
3. **§0 Charge-frame re-anchor** — Verbatim quote of this CHARGE's §1 SWP-0N for the skill + §2 augment (i)..(v) headers.
4. **§1 Per-hypothesis disposition table** — One row per SWP-0N-derived hypothesis + one row per augment (i)..(v); `/economic-analyst` adds beyond-charge rows.
5. **§2 Skeptic-Filter Self-Discarded subsection** — Table or "no self-discards" attestation; cross-link to `[skeptic-filter]` frontmatter.
6. **§3 Cross-skill hand-off notes** — Observations that anchor the other skills' hypotheses; keeps coverage divergent.

---

## §8 Reference files (load-bearing)

### Phase 307 anchors
- `.planning/REQUIREMENTS.md` §"Adversarial Sweep (SWP)" — SWP-01..05 verbatim (lines 95-99).
- `.planning/phases/307-adversarial-sweep-sweep/307-CONTEXT.md` — D-307-* decision lineage.
- `.planning/ROADMAP.md` §"Phase 307: Adversarial Sweep (SWEEP)" — Goal + 5 success criteria.

### Locked SPEC + v44 IMPL surfaces
- `.planning/phases/304-spec-invariant-model-spec/304-SPEC.md` — Phase 304 SPEC (INV-01..12 + SPEC-01..05 + EDGE-01..18).
- `.planning/phases/305-implementation-impl/305-01-SUMMARY.md` — Phase 305 IMPL summary; v44 emergent surfaces.
- `.planning/phases/305-implementation-impl/305-CONTEXT.md` — Phase 305 IMPL CONTEXT.
- `.planning/phases/306-test-tst/306-VERIFICATION.md` — Phase 306 TST verification; 13 INV + 20 EDGE coverage.

### Contracts under adversarial probe
- `contracts/StakedDegenerusStonk.sol` — Primary target.
- `contracts/modules/DegenerusGameAdvanceModule.sol` — 3 sentinel call sites at `:1228, :1294, :1327` (reader) + `:1234, :1300, :1333` (writer).
- `contracts/DegenerusVault.sol` — `:729` `sdgnrsClaimRedemption(uint32 day) external onlyVaultOwner` scope-expansion.
- `contracts/interfaces/IStakedDegenerusStonk.sol` — `:87, :92, :104` interface surface.

### Test coverage proven at Phase 306
- `test/invariant/RedemptionAccounting.t.sol` — 13 invariant_INV_NN_* functions.
- `test/fuzz/handlers/RedemptionHandler.sol` — 5-action handler (perturbation-class gap probe target for augment (iv)).
- `test/fuzz/RedemptionEdgeCases.t.sol` — 20 EDGE-NN fuzz functions.
- `test/fuzz/StakedStonkRedemption.t.sol` — 8 per-function fuzz tests.
- `test/fuzz/RngLockDeterminism.t.sol` — V-184 strict-byte-identity at line 1278.
- `test/fuzz/RedemptionGas.t.sol` — 2 gas regression assertions (burn -29.8%; claim -57.5% vs v43).

### Skill source definitions
- `~/.claude/skills/contract-auditor/SKILL.md`
- `~/.claude/skills/zero-day-hunter/SKILL.md`
- `~/.claude/skills/economic-analyst/SKILL.md`

### Methodology precedents
- `.planning/milestones/v43.0-phases/302-cross-surface-adversarial-sweep-sweep/302-ADVERSARIAL-CHARGE.md` — Format template.
- `.planning/milestones/v43.0-phases/302-cross-surface-adversarial-sweep-sweep/302-01-ADVERSARIAL-LOG.md` — Integrated log format template.
- `.planning/milestones/v42.0-phases/296-cross-surface-adversarial-sweep-sweep/296-CONTEXT.md` — v42 original of inherited decision set.
- `.planning/milestones/v41.0-phases/284-delta-audit-findings-consolidation-terminal/284-ADVERSARIAL-RE-PASS-CONTRACT-AUDITOR.md` — RE-PASS report shape template.

### Audit findings cross-cited
- `audit/FINDINGS-v43.0.md` §9d — HANDOFF-111..117 register (closed by v44.0).
- `.planning/RNGLOCK-FIXREC.md` §103 — V-184 mechanic + game-theory walk (original CATASTROPHE that v44 structurally closes).

---

*Phase: 307-adversarial-sweep-sweep / Plan: 01 / Charge document authored 2026-05-19 per D-307-CHARGE-01.*
