# Phase 311 SPEC — VRF-Rotation Liveness Fix

**Gathered:** 2026-05-22
**Baseline HEAD (milestone audit baseline):** `MILESTONE_V44_AT_HEAD_6f0ba2963a10654ba554a8c333c5ee80c54a8349`
**Verified-against HEAD (this SPEC's grep evidence):** `3153149a75d0dfced1d9496d9cec348f47f6e630`
**Requirements covered here (Plan 311-01):** VRF-01..05 (evidence base only — the design narrative that *closes* them is authored in Plan 311-02)
**Authoritative decision source:** `311-CONTEXT.md` decisions D-01..D-05 + `<canonical_refs>`

This SPEC LOCKS the v45.0 VRF-rotation fix DESIGN before any contract change. Plan 311-01 (this
commit) authors the section skeleton and the load-bearing **§0 Call-Graph Manifest** — every
`file:line` cited in `311-CONTEXT.md` `<canonical_refs>` is re-grepped against contract HEAD and
recorded VERIFIED or DRIFTED. Plan 311-02 fills §1–§6 with the design narrative; **no design
assertion in §1–§6 may state a call path that does not have a row in §0.** Per
`feedback_verify_call_graph_against_source`, this discharges the grep-verification obligation as a
discrete, checkable pass — **zero "by construction" claims.**

> **Scope invariant:** This is a SPEC-only phase. ZERO `contracts/` mutations, ZERO `test/`
> mutations. The grep evidence below is read-only verification; the only file written is this SPEC
> document. (`git diff --quiet -- contracts/ test/` MUST stay clean.)

Per `feedback_contract_locations`, every contract read is from the `contracts/` directory only
(stale copies elsewhere are never consulted). Per `feedback_no_history_in_comments`, every row
describes what IS at HEAD `3153149a` — never what changed.

---

## §0 Call-Graph Manifest (grep-verified against HEAD)

**Method.** Each row was produced by a name-anchored `grep -n` against the `contracts/` tree at
HEAD `3153149a75d0dfced1d9496d9cec348f47f6e630`, then the cited region was read to confirm the
literal source text. SLOAD/SSTORE/call sites are enumerated individually. The `CONTEXT-claimed
line` column is the anchor as transcribed in `311-CONTEXT.md` `<canonical_refs>` /
`<manifest_targets>`; the `VERIFIED line (HEAD)` column is the line `grep -n` returned at HEAD.
`Status` is **VERIFIED** when the claimed line equals (or is inside the claimed span of) the
verified line, **DRIFTED ±N** otherwise (drift recorded, never silently rewritten).

**No "by construction" claims appear anywhere in §0.** Every downstream §1–§6 design assertion
MUST cite a row in this manifest.

### §0.A `contracts/modules/DegenerusGameAdvanceModule.sol` — primary VRF-rotation surface

Canonical verified references (colon-joined, for grep): `DegenerusGameAdvanceModule.sol:498`,
`DegenerusGameAdvanceModule.sol:1044`, `DegenerusGameAdvanceModule.sol:1048`,
`DegenerusGameAdvanceModule.sol:1097`, `DegenerusGameAdvanceModule.sol:1133`,
`DegenerusGameAdvanceModule.sol:1134`, `DegenerusGameAdvanceModule.sol:1688`,
`DegenerusGameAdvanceModule.sol:1701`-`1704`, `DegenerusGameAdvanceModule.sol:1709`,
`DegenerusGameAdvanceModule.sol:1711`-`1714`, `DegenerusGameAdvanceModule.sol:1756`,
`DegenerusGameAdvanceModule.sol:1761`, `DegenerusGameAdvanceModule.sol:1768`,
`DegenerusGameAdvanceModule.sol:1772`, `DegenerusGameAdvanceModule.sol:1208`,
`DegenerusGameAdvanceModule.sol:1817`, `DegenerusGameAdvanceModule.sol:213`,
`DegenerusGameAdvanceModule.sol:238`, `DegenerusGameAdvanceModule.sol:271`,
`DegenerusGameAdvanceModule.sol:1102`, `DegenerusGameAdvanceModule.sol:1143`,
`DegenerusGameAdvanceModule.sol:1587`, `DegenerusGameAdvanceModule.sol:1605`.

| Symbol / Site | CONTEXT-claimed line | VERIFIED line (HEAD) | Status | Confirmation at that line |
|---------------|----------------------|----------------------|--------|---------------------------|
| `wireVrf` definition | :498 | `DegenerusGameAdvanceModule.sol:498` | **VERIFIED** | `function wireVrf(` — admin-only (`:503` `if (msg.sender != ContractAddresses.ADMIN) revert E();`); writes the 3 VRF config slots at `:506-508`. No init-only lock present (D-03 target). |
| `requestLootboxRng` definition | :1044 | `DegenerusGameAdvanceModule.sol:1044` | **VERIFIED** | `function requestLootboxRng() external {` |
| `LR_MID_DAY` single-in-flight gate | :1048 | `DegenerusGameAdvanceModule.sol:1048` | **VERIFIED** | `if (_lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK) != 0) revert E();` — at-most-one in-flight mid-day request (bounds orphans to 1/rotation; grounds D-05 narrow scope). |
| sets `LR_MID_DAY = 1` (buffer swap) | :1097 | `DegenerusGameAdvanceModule.sol:1097` | **VERIFIED** | `_lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 1);` — inside the freeze-buffer swap block `:1092-1099`. |
| `retryLootboxRng` definition | :1133 | `DegenerusGameAdvanceModule.sol:1133` | **VERIFIED** | `function retryLootboxRng() external {` — the standing failsafe (re-fires VRF, same params; stalled `requestId` auto-rejected; buffer + pre-advanced index preserved per its `:1126-1132` docstring). This IS the re-issue precedent for D-01/D-02. |
| `retryLootboxRng` reverts if `LR_MID_DAY==0` | :1134 | `DegenerusGameAdvanceModule.sol:1134` | **VERIFIED** | `if (_lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK) == 0) revert E();` — only reachable when a mid-day swap is in flight. |
| `updateVrfCoordinatorAndSub` definition | :1688 | `DegenerusGameAdvanceModule.sol:1688` | **VERIFIED** | `function updateVrfCoordinatorAndSub(` — admin-only (`:1693`); the emergency-rotation entry (D-01/D-02 rework target). |
| force-unlock + zero resets | :1701-1704 | `DegenerusGameAdvanceModule.sol:1701`-`1704` | **VERIFIED** | `:1701` `rngLockedFlag = false;` · `:1702` `vrfRequestId = 0;` · `:1703` `rngRequestTime = 0;` · `:1704` `rngWordCurrent = 0;` — the unconditional blanket reset D-02 replaces with preserve+re-issue. |
| clears `LR_MID_DAY = 0` | :1709 | `DegenerusGameAdvanceModule.sol:1709` | **VERIFIED** | `_lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0);` — drops the in-flight mid-day flag without re-issuing → orphans `lootboxRngWordByIndex[N]` (root cause). |
| `totalFlipReversals` carry-over comment | :1711-1714 | `DegenerusGameAdvanceModule.sol:1711`-`1714` | **VERIFIED** | `:1711` `// Intentional: totalFlipReversals is NOT reset here.` (comment spans 1711-1714) — the carry-over D-02 re-issue MUST preserve. (`totalFlipReversals` is itself read at `:1843` and consumed into the daily word at `:273`/`:1847`.) |
| `rawFulfillRandomWords` definition | :1756 | `DegenerusGameAdvanceModule.sol:1756` | **VERIFIED** | `function rawFulfillRandomWords(` — the VRF callback; reused unchanged by re-issue (a fresh `vrfRequestId` is what the callback matches). |
| `requestId` / word guard (abandons old word) | :1761 | `DegenerusGameAdvanceModule.sol:1761` | **VERIFIED** | `if (requestId != vrfRequestId || rngWordCurrent != 0) return;` — a stale coordinator's callback (old `requestId`) is rejected; this is the freeze-safety mechanism for re-issue (old word abandoned). |
| daily branch → `rngWordCurrent` | :1766-1768 | `DegenerusGameAdvanceModule.sol:1768` (branch `if` at `:1766`) | **VERIFIED** | `:1766` `if (rngLockedFlag) {` · `:1768` `rngWordCurrent = word;` — the daily-fulfillment write target (D-02 daily re-issue lands here). |
| mid-day branch → `lootboxRngWordByIndex[index]` | mid-day branch (the `else` after :1769) | `DegenerusGameAdvanceModule.sol:1772` (`else` at `:1769`) | **VERIFIED** | `:1769` `} else {` · `:1771` `uint48 index = uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)) - 1;` · `:1772` `lootboxRngWordByIndex[index] = word;` — the mid-day-fulfillment write target (D-02 mid-day re-issue lands here). |
| existing `_backfillOrphanedLootboxIndices` CALL | :1208 | `DegenerusGameAdvanceModule.sol:1208` | **VERIFIED** | `_backfillOrphanedLootboxIndices(currentWord);` — gated behind the gap-day branch `:1202` (`day > idx + 1 && rngWordByDay[idx + 1] == 0`), itself reached only when a fresh word exists (`:1193` `currentWord != 0 && rngRequestTime != 0`). D-05 reachability anchor. |
| `_backfillOrphanedLootboxIndices` DEFINITION | :1817 | `DegenerusGameAdvanceModule.sol:1817` | **VERIFIED** | `function _backfillOrphanedLootboxIndices(uint256 vrfWord) private {` — backward scan `:1822` (`for (uint48 i = idx - 1; i >= 1; )`), VRF-derived `keccak256(abi.encodePacked(vrfWord, i))` at `:1826` (not front-runnable — `vrfWord` is the fresh post-gap word). |
| advance-flow drain gate (Scenario B revert site) | :209-238, :269 | `DegenerusGameAdvanceModule.sol:213` + `:238` (same-day); `:269`-`271` (new-day) | **VERIFIED (revert lines refined)** | Same-day branch (`:205` `if (day == dailyIdx)`): `:209` `if (_lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK) != 0) {` → `:210-212` reads `lootboxRngWordByIndex[index]` → **`:213` `if (word == 0) revert RngNotReady();`**; tail **`:238` `revert NotTimeYet();`**. New-day path: `:269` `if (lootboxRngWordByIndex[preIdx] == 0) {` → **`:271` `if (cw == 0) revert RngNotReady();`**. CONTEXT cited `:238`/`:269` as the revert anchors; the precise reverts are `:213` + `:238` (same-day) and `:271` (new-day). D-05 must confirm re-issue un-blocks `:213`/`:271`. |
| `requestRandomWords` call sites (re-issue mechanic ref for D-01/D-02) | "the call sites" (no lines given) | `DegenerusGameAdvanceModule.sol:1102`, `:1143`, `:1587`, `:1605` | **VERIFIED (enumerated)** | `:1102` inside `requestLootboxRng` (mid-day request) · `:1143` inside `retryLootboxRng` (the failsafe re-issue — the canonical "re-fire on same params" pattern D-01 reuses) · `:1587` + `:1605` inside `_finalizeRngRequest`/daily-request path (`:1587` `uint256 id = vrfCoordinator.requestRandomWords(`, `:1605` retry-branch). All four are `vrfCoordinator.requestRandomWords(VRFRandomWordsRequest({...}))`. |
| `rawFulfillRandomWords` daily vs mid-day write lines (explicit) | daily `rngWordCurrent =`; mid-day `lootboxRngWordByIndex[index] =` | daily 1768; mid-day 1772 | **VERIFIED** | Daily-branch write: `:1768` `rngWordCurrent = word;`. Mid-day-branch write: `:1772` `lootboxRngWordByIndex[index] = word;` (+ `:1773` `emit LootboxRngApplied(index, word, requestId);`, `:1774` `vrfRequestId = 0;`, `:1775` `rngRequestTime = 0;`). |

### §0.B `contracts/modules/DegenerusGameMintModule.sol` — Scenario A consumer

Canonical verified reference (colon-joined, for grep): `DegenerusGameMintModule.sol:686`.

| Symbol / Site | CONTEXT-claimed line | VERIFIED line (HEAD) | Status | Confirmation at that line |
|---------------|----------------------|----------------------|--------|---------------------------|
| `entropy = lootboxRngWordByIndex[…-1]` with NO zero-guard | :686 | `DegenerusGameMintModule.sol:686` | **VERIFIED** | `uint256 entropy = lootboxRngWordByIndex[uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)) - 1];` — read directly into `entropy`, NO `== 0` guard before it flows into `_processOneTicketEntry(…, entropy, …)` at `:690-696`. This is the Scenario A entropy-0 path (orphaned index → `entropy == 0` → deterministic traits). VRF-01 consumer anchor. |

### §0.C `contracts/storage/DegenerusGameStorage.sol` — VRF-participating slots

Canonical verified references (colon-joined, for grep): `DegenerusGameStorage.sol:244`,
`DegenerusGameStorage.sol:373`, `DegenerusGameStorage.sol:1287`, `DegenerusGameStorage.sol:1291`,
`DegenerusGameStorage.sol:1295`, `DegenerusGameStorage.sol:1328`-`1329`,
`DegenerusGameStorage.sol:1431`.

| Symbol / Site | CONTEXT-claimed line | VERIFIED line (HEAD) | Status | Confirmation at that line |
|---------------|----------------------|----------------------|--------|---------------------------|
| `rngRequestTime` | :244 | `DegenerusGameStorage.sol:244` | **VERIFIED** | `uint48 internal rngRequestTime;` — VRF-request timestamp / timeout lock (`rngRequestTime != 0` = a request is outstanding). Re-issue sets this fresh (D-01). |
| `rngWordCurrent` | :373 | `DegenerusGameStorage.sol:373` | **VERIFIED** | `uint256 internal rngWordCurrent;` — the current daily VRF word slot (daily-branch fulfillment target). |
| `vrfCoordinator` | :1287 | `DegenerusGameStorage.sol:1287` | **VERIFIED** | `IVRFCoordinator internal vrfCoordinator;` — config slot written by both `wireVrf` (`DegenerusGameAdvanceModule.sol:506`) and `updateVrfCoordinatorAndSub` (`DegenerusGameAdvanceModule.sol:1696`). |
| `vrfKeyHash` | :1291 | `DegenerusGameStorage.sol:1291` | **VERIFIED** | `bytes32 internal vrfKeyHash;` — config slot written by both VRF admin fns (`DegenerusGameAdvanceModule.sol:508` / `:1698`). |
| `vrfSubscriptionId` | :1295 | `DegenerusGameStorage.sol:1295` | **VERIFIED** | `uint256 internal vrfSubscriptionId;` — config slot written by both VRF admin fns (`DegenerusGameAdvanceModule.sol:507` / `:1697`). |
| `LR_MID_DAY` shift/mask | :1328-1329 | `DegenerusGameStorage.sol:1328`-`1329` | **VERIFIED** | `:1328` `uint256 internal constant LR_MID_DAY_SHIFT = 224;` · `:1329` `uint256 internal constant LR_MID_DAY_MASK = 0xFF; // 8 bits` — the single-in-flight mid-day gate field. |
| `lootboxRngWordByIndex` | :1431 | `DegenerusGameStorage.sol:1431` | **VERIFIED** | `mapping(uint48 => uint256) internal lootboxRngWordByIndex;` — the per-index lootbox VRF word (the slot orphaned by rotation; Scenario A consumer reads `[N-1]`). |

### §0.D `_setVrfConfig` (D-04) — TO-BE-CREATED, not an existing symbol

| Symbol | CONTEXT framing | Grep result at HEAD | Status |
|--------|-----------------|---------------------|--------|
| `_setVrfConfig(coord, sub, key)` internal helper | D-04 dedup target | `grep -rn "_setVrfConfig" contracts/` → **zero matches** | **TO-BE-CREATED** (does NOT exist at HEAD). D-04 introduces it at Phase 312 to collapse the near-duplicate 3-slot config write that currently lives inline in BOTH `wireVrf` (`:506-508`) and `updateVrfCoordinatorAndSub` (`:1696-1698`). Recorded here as to-be-created so no §1–§6 assertion treats it as an existing call-graph node. |

### §0.E `requestRandomWords` re-issue-mechanic sub-block (D-01/D-02 reference)

All four `vrfCoordinator.requestRandomWords(...)` call sites in `DegenerusGameAdvanceModule.sol`,
enumerated (the re-issue mechanic D-01/D-02 reuses — re-firing the request just produces a fresh
`vrfRequestId` the existing `rawFulfillRandomWords` matches against; no new fulfillment path):

| # | Line (HEAD) | Enclosing function | Role |
|---|-------------|--------------------|------|
| 1 | 1102 | `requestLootboxRng` (`:1044`) | Initial mid-day lootbox request; sets `vrfRequestId`/`rngRequestTime`/`rngWordCurrent=0` at `:1121-1123`. |
| 2 | 1143 | `retryLootboxRng` (`:1133`) | **Failsafe re-issue** — re-fires VRF with the same `VRFRandomWordsRequest` params; sets fresh `vrfRequestId`/`rngRequestTime` at `:1154-1155`; preserves `LR_MID_DAY` + pre-advanced index. The canonical re-issue pattern D-01/D-02 generalize to the rotation path. |
| 3 | 1587 | daily-request path (`_finalizeRngRequest`) | Daily VRF request. |
| 4 | 1605 | daily-request path (retry branch) | Daily VRF retry re-fire. |

### §0.F `rawFulfillRandomWords` daily-vs-mid-day branch boundary (explicit write lines)

The callback (`:1756`) splits on `rngLockedFlag`. Re-issue (D-01/D-02) reuses BOTH branches
unchanged:

| Branch | Boundary line | Write site (HEAD) | Target slot |
|--------|---------------|-------------------|-------------|
| Guard (abandons old word) | 1761 | `if (requestId != vrfRequestId || rngWordCurrent != 0) return;` | — (rejects stale `requestId`) |
| Daily (`rngLockedFlag == true`) | `if` at 1766 | **:1768** `rngWordCurrent = word;` | `rngWordCurrent` (`Storage:373`) |
| Mid-day (`else`) | `else` at 1769 | **:1772** `lootboxRngWordByIndex[index] = word;` | `lootboxRngWordByIndex` (`Storage:1431`), `index = LR_INDEX - 1` (`:1771`) |

### §0.G Requirement-context coverage (VRF-01 / VRF-02)

- **VRF-01** (orphan-index resolves to a real word). Anchors: the Scenario A consumer
  `MintModule.sol:686` (§0.B, no zero-guard); the `lootboxRngWordByIndex` slot (`Storage:1431`,
  §0.C); the mid-day fulfillment write `AdvanceModule.sol:1772` (§0.A/§0.F — where a re-issued
  word lands). The fix must guarantee `[N]` holds a real VRF word before any same-day advance
  reads it at `:686`.
- **VRF-02** (post-rotation liveness). Anchors: `requestLootboxRng` `:1044` + its gate `:1048`
  (§0.A); `retryLootboxRng` `:1133` + its gate `:1134` (§0.A); the advance-flow drain gate
  `:209-238` (same-day) + `:269-271` (new-day) (§0.A) — the Scenario B revert sites that re-issue
  must un-block so `requestLootboxRng`/`retryLootboxRng`/daily-drain stay reachable.

### §0.H §0 Attestation

**Zero "by construction" / "single fn reaches all paths" claims** appear above. Every cited site
in §0.A–§0.G is grep-verified against HEAD `3153149a75d0dfced1d9496d9cec348f47f6e630` with its
matched source text and the line `grep -n` returned; the four `requestRandomWords` call sites and
the daily/mid-day fulfillment writes are enumerated individually; the drain-gate revert lines are
refined to the precise `revert` statements (`:213`/`:238`/`:271`). One CONTEXT symbol — D-04's
`_setVrfConfig` — is recorded as **TO-BE-CREATED** (§0.D), not as an existing node. The
vault/admin-routed dispatch naming drift (CONTEXT "DegenerusVault" vs the verified
`DegenerusAdmin.sol` + `DegenerusGame.sol` sites) is reconciled in **§0.Y** below. Every
downstream §1–§6 design assertion must cite a row here. (`feedback_no_history_in_comments`,
`feedback_verify_call_graph_against_source`.)

### §0.X §9d-Anchor → Closing-Change Mapping

Source rows: `audit/FINDINGS-v44.0.md` §9d.2 (FIXREC handoff anchors, the HANDOFF-NN rows) +
§9d.4 (ADMA handoff anchors). Each row below cross-references the FINDINGS §9d line it comes from
and maps the anchor to the v45.0 closing change (decision ID D-01..D-05) + the requirement it
closes (VRF-01..05 from `REQUIREMENTS.md` / ROADMAP §Phase 311 Success Criteria 1-5). The decision
shapes are the LOCKED inputs from `311-CONTEXT.md` `<decisions>`; the requirement→change mapping is
the ROADMAP §Phase 311 goal statement (re-issue-in-flight closes VRF-01/02/03; `wireVrf` one-shot
lock closes VRF-04; vault reach closes VRF-05).

> **Maximalist-catalog note (`project_rnglock_audit_disposition`):** the §9d HANDOFF/ADMA rows are
> a **maximalist enumeration catalog**, NOT a list of live player-exploitable vectors. Admin VRF
> rotation is an EXEMPT-class operation, not a player-discretionary write (`v45-vrf-freeze-invariant`
> — `advanceGame`/admin exempt). The closing changes target the **real liveness defect** (the
> orphan-index CATASTROPHE: Scenario A entropy-0 traits + Scenario B ~120-day freeze) and the
> one-shot-lock hardening — they do NOT over-fix the governance rows beyond that. VRF-03 "freeze
> disposition" is satisfied by re-issue being freeze-safe (old word abandoned via the `:1761`
> `requestId` guard, new word unpredictable), not by adding player-facing gates.

| §9d Anchor | V-NN | What it flags (§9d source) | Closing change (decision ID) | Requirement closed | §9d source line |
|------------|------|----------------------------|------------------------------|--------------------|-----------------|
| HANDOFF-78 | V-137 | S-38 `rngRequestTime` (governance); the **rejected** `pendingVrfRotationPacked` queue+apply tactic; named closer of 5 governance rows (78/85/87/89/91) | **D-01 + D-02** re-issue-in-flight (rejects queue+apply; preserve+re-issue both daily & mid-day paths) | **VRF-03** (freeze cluster) + VRF-01/VRF-02 (orphan + liveness) | §9d.2 :686 |
| HANDOFF-85 | V-155 | S-46 `lootboxRngPacked.LR_MID_DAY` (governance); "Subsumed by HANDOFF-78" | **D-01 + D-02** (mid-day branch: keep `LR_MID_DAY=1`, re-request the reserved index) | **VRF-03** | §9d.2 :693 |
| HANDOFF-86 | V-156 | S-47 `vrfCoordinator` (wireVrf); (d) one-shot lock; named closer of 3 wireVrf rows (86/88/90) | **D-03** `wireVrf` init-only lock (+ **D-04** `_setVrfConfig` dedup) | **VRF-04** (wireVrf one-shot lock) | §9d.2 :694 |
| HANDOFF-87 | V-157 | S-47 `vrfCoordinator` (governance); "Subsumed by HANDOFF-78" | **D-01 + D-02** (config repoint stays; rotation now safe via re-issue) | **VRF-03** | §9d.2 :695 |
| HANDOFF-88 | V-158 | S-48 `vrfSubscriptionId` (wireVrf); "Subsumed by HANDOFF-86" | **D-03** (+ **D-04**) | **VRF-04** | §9d.2 :696 |
| HANDOFF-89 | V-159 | S-48 `vrfSubscriptionId` (governance); "Subsumed by HANDOFF-78" | **D-01 + D-02** | **VRF-03** | §9d.2 :697 |
| HANDOFF-90 | V-160 | S-49 `vrfKeyHash` (wireVrf); "Subsumed by HANDOFF-86" | **D-03** (+ **D-04**) | **VRF-04** | §9d.2 :698 |
| HANDOFF-91 | V-161 | S-49 `vrfKeyHash` (governance); "Subsumed by HANDOFF-78" | **D-01 + D-02** | **VRF-03** | §9d.2 :699 |
| ADMA-01 | V-156 / V-158 / V-160 (cross-ref) | `DegenerusGameAdvanceModule.wireVrf @ AdvanceModule.sol:498`; (d) immutable / seal `wireVrf` post-init via one-shot flag | **D-03** `wireVrf` init-only lock (+ **D-04** dedup) | **VRF-04** (HANDOFF-86/88/90 + ADMA-01) | §9d.4 :746 |
| ADMA-02 | S-47/48/49/38/46 (cross-ref; ties HANDOFF-78) | `DegenerusGameAdvanceModule.updateVrfCoordinatorAndSub @ AdvanceModule.sol:1677` (§9d-cited line **DRIFTED** — see note); (c) pre-lock reorder / queue mid-stall rotations; **vault-routed** reach | **D-03 + D-01/D-02** (the D-03 lock + D-01/D-02 safe-rotation cover the vault-routed path) | **VRF-05** (vault-routed reach) | §9d.4 :747 |

> **ADMA-02 line drift (recorded, not silently propagated):** §9d.4 :747 cites
> `updateVrfCoordinatorAndSub @ AdvanceModule.sol:1677`. At HEAD `3153149a` the function definition
> is at **`DegenerusGameAdvanceModule.sol:1688`** (§0.A row, VERIFIED). Drift **+11 lines** vs the
> v44 §9d citation (the v44 §9d register was written against the v44 closure HEAD
> `6f0ba296…`; the +11 drift reflects edits between that baseline and current HEAD). The verified
> HEAD line `:1688` governs all §1–§6 assertions; `:1677` is the stale §9d-register citation.
>
> **Cluster-completeness note:** all 10 cluster anchors named in the plan
> (`HANDOFF-78/85/86/87/88/89/90/91` + `ADMA-01/02`) have a row above. The CONTEXT/PROJECT prose
> also references the cluster as "HANDOFF-78/85/87/89/91 (freeze) + 86/88/90 + ADMA-01 (wireVrf
> lock) + ADMA-02 (vault reach)"; the freeze sub-cluster is `{78,85,87,89,91}` (→ D-01/D-02,
> VRF-03), the wireVrf sub-cluster is `{86,88,90,ADMA-01}` (→ D-03/D-04, VRF-04), and ADMA-02 is the
> vault-routed reach (→ VRF-05). The split matches ROADMAP §Phase 311 Success Criteria 3-4.

### §0.Y Vault/Admin-Routed Reach Trace (ADMA-02 / VRF-05)

`311-CONTEXT.md` `<code_context>` names a **`DegenerusVault`** dispatch to the admin VRF functions
(ADMA-02). This sub-section records the **ACTUAL** dispatch sites grep-verified across `contracts/`
at HEAD `3153149a`, and reconciles the naming drift. This trace is the evidence base for the §4
VRF-05 design assertion that the D-03 lock + D-01/D-02 safe-rotation cover the routed path.

**Naming-drift reconciliation (CONTEXT "DegenerusVault" vs verified source).** `contracts/DegenerusVault.sol`
**exists** as a file, but `grep -n "wireVrf\|updateVrfCoordinatorAndSub\|gameAdmin" contracts/DegenerusVault.sol`
returns **zero matches** — `DegenerusVault.sol` does **NOT** itself dispatch either VRF admin
function. `DegenerusVault` is the **vault-ownership** contract: it is referenced as the ownership
oracle (`IDegenerusVaultOwner vault = IDegenerusVaultOwner(ContractAddresses.VAULT)` at
`DegenerusAdmin.sol:434-435`) whose `vault.isVaultOwner(msg.sender)` gate guards the admin
entry points (the `onlyOwner` modifier, `DegenerusAdmin.sol:437`). The CONTEXT "DegenerusVault
dispatch" is therefore a **naming drift**: the real dispatch lives in `DegenerusAdmin.sol`
(vault-owner-gated wrappers) + `DegenerusGame.sol` (the `delegatecall` selector-routed entry
points). Recorded, not silently rewritten.

**Verified dispatch — `wireVrf` (one-shot init path, D-03/D-04/VRF-04):**

| Hop | Site (HEAD) | Role |
|-----|-------------|------|
| 1 | `DegenerusAdmin.sol:445` `constructor()` → `DegenerusAdmin.sol:458` `gameAdmin.wireVrf(ContractAddresses.VRF_COORDINATOR, subId, ContractAddresses.VRF_KEY_HASH)` | The **one-time** deployment wiring (called from the Admin constructor, after `vrfCoordinator.createSubscription()` at `:446`). Structurally init-only; this is exactly why D-03's one-shot lock is safe — legitimate use is a single constructor call. |
| 2 | `DegenerusGame.sol:308` `function wireVrf(...)` → `DegenerusGame.sol:312-321` `GAME_ADVANCE_MODULE.delegatecall(abi.encodeWithSelector(IDegenerusGameAdvanceModule.wireVrf.selector, ...))` | The selector-routed `delegatecall` entry into the AdvanceModule implementation. |
| 3 | `DegenerusGameAdvanceModule.sol:498` `function wireVrf(...)` (§0.A) — admin-gated at `:503` (`msg.sender != ContractAddresses.ADMIN`); writes `vrfCoordinator`/`vrfSubscriptionId`/`vrfKeyHash` at `:506-508` | The implementation. **No one-shot lock at HEAD** (D-03 target). |

**Verified dispatch — `updateVrfCoordinatorAndSub` (emergency rotation path, D-01/D-02/VRF-05):**

| Hop | Site (HEAD) | Role |
|-----|-------------|------|
| 1 | `DegenerusAdmin.sol:859` `_executeSwap(uint256 proposalId)` (internal) → `DegenerusAdmin.sol:901` `gameAdmin.updateVrfCoordinatorAndSub(newCoordinator, newSubId, newKeyHash)` | The governance proposal-execution path. Reached through the stall-gated rotation-proposal flow (`ADMIN_STALL_THRESHOLD = 20 hours`, `DegenerusAdmin.sol:406`; proposal create/execute gated on `gameAdmin.lastVrfProcessed()` staleness at `:666`/`:705`). Adds the new coordinator as consumer (`:894`) + transfers LINK (`:907-912`) around the push. |
| 2 | `DegenerusGame.sol:1874` `function updateVrfCoordinatorAndSub(...)` → `DegenerusGame.sol:1878-1891` `GAME_ADVANCE_MODULE.delegatecall(abi.encodeWithSelector(IDegenerusGameAdvanceModule.updateVrfCoordinatorAndSub.selector, ...))` | The selector-routed `delegatecall` entry into the AdvanceModule implementation. |
| 3 | `DegenerusGameAdvanceModule.sol:1688` `function updateVrfCoordinatorAndSub(...)` (§0.A) — admin-gated at `:1693`; the orphan-causing blanket reset at `:1701-1704`/`:1709` | The implementation (D-01/D-02 rework target). |

**Interface anchor.** Both functions are declared on the `IDegenerusGameAdmin` interface consumed
by `DegenerusAdmin.sol` (`updateVrfCoordinatorAndSub` decl `DegenerusAdmin.sol:99`; `wireVrf` decl
`DegenerusAdmin.sol:109`) and on `IDegenerusGameModules.sol` (`wireVrf` `:22`,
`updateVrfCoordinatorAndSub` `:32`) — these are interface declarations, distinct from the call
sites (`:458` / `:901`) and the AdvanceModule implementations (`:498` / `:1688`).

**VRF-05 evidence summary.** There is **no `DegenerusVault`-routed path** to either VRF admin
function — the only routed reach is (a) `DegenerusAdmin` (vault-owner-gated) and (b)
`DegenerusGame` (selector `delegatecall`), both terminating at the same two AdvanceModule
implementations (`:498` / `:1688`). Therefore the D-03 one-shot lock (applied at the
`wireVrf` implementation `:498`) and the D-01/D-02 safe-rotation (applied at the
`updateVrfCoordinatorAndSub` implementation `:1688`) cover **every** routed entry — the lock/safety
sits at the delegatecall target, downstream of all wrappers, so no wrapper can bypass it. (§4
VRF-05 in Plan 02 builds its assertion on this trace.)

---

## §1 Design-Intent Backward-Trace (Scenario A + Scenario B)

[authored in Plan 02]

## §2 LOCKED Fix Shape — Re-Issue In-Flight (D-01/D-02)

[authored in Plan 02]

## §3 Freeze-Invariant Disposition (VRF-03)

[authored in Plan 02]

## §4 wireVrf One-Shot Lock + _setVrfConfig Dedup + Vault Reach (D-03/D-04/VRF-04/VRF-05)

[authored in Plan 02]

## §5 Orphan-Recovery Breadth (D-05)

[authored in Plan 02]

## §6 Rejected Options

[authored in Plan 02]
