# Phase 299-02 — FIXREC Cluster B (traitBurnTicket admin + deityBySymbol whale)

**Cluster scope:** `traitBurnTicket[lvl][trait]` (S-06) non-MintModule writer rows + `deityBySymbol[fullSymId]` (S-07) whale writer.
**VIOLATIONs in scope:** V-016, V-017, V-018, V-019 (RNGLOCK-CATALOG.md §16 rows 351-354).
**Handoff anchors:** D-43N-V44-HANDOFF-09 (V-016) · D-43N-V44-HANDOFF-10 (V-017) · D-43N-V44-HANDOFF-11 (V-018) · D-43N-V44-HANDOFF-12 (V-019).
**Layout authority:** `D-299-FIXREC-LAYOUT-01` (CONTEXT.md §decisions).
**Posture:** AUDIT-ONLY per `D-43N-AUDIT-ONLY-01`. Zero `contracts/` + `test/` mutations.

---

## Cluster preamble — grep-verification against current source

Per `feedback_verify_call_graph_against_source.md` ("Inline-duplicated business logic is recurring in DegenerusGameJackpotModule (Phase 294 BURNIE gap precedent)") and `feedback_frozen_contracts_no_future_proofing.md`, the FIXREC author re-grepped the CATALOG §15 writer rows for S-06 against `contracts/` at phase-execution time and surfaces the following source-vs-catalog discrepancies BEFORE issuing per-VIOLATION FIXREC. The discrepancies do **not** invalidate the catalog's VIOLATION classification (the catalog correctly applied its static stack-strict rule to the writer rows it enumerated) but they **do** materially change the §N.C remediation tactic and the v44.0 handoff payload.

**Grep performed (FIXREC author, phase-299-02 execution time):**

```
$ grep -n "adminSeedTraitBucket\|adminClearTraitBucket\|traitBurnTicket\[" contracts/DegenerusGame.sol
2398:        address[] storage arr = traitBurnTicket[lvlSel][traitSel];
2427:        address[] storage arr = traitBurnTicket[targetLvl][traitSel];
2510:        address[] storage a   = traitBurnTicket[lvl][trait];

$ grep -rn "adminSeedTraitBucket\|adminClearTraitBucket" contracts/ --include="*.sol"
(no hits)

$ grep -rn "traitBurnTicket" contracts/ --include="*.sol" | grep -v "// "
contracts/modules/DegenerusGameMintModule.sol:594:     [comment]
contracts/modules/DegenerusGameMintModule.sol:602:     mstore(0x20, traitBurnTicket.slot)
contracts/DegenerusGame.sol:2398:        address[] storage arr = traitBurnTicket[lvlSel][traitSel];
contracts/DegenerusGame.sol:2427:        address[] storage arr = traitBurnTicket[targetLvl][traitSel];
contracts/DegenerusGame.sol:2510:        address[] storage a   = traitBurnTicket[lvl][trait];
contracts/modules/DegenerusGameJackpotModule.sol:691,989,1039,1297,1400,1708,1718,1860 (reads only)
contracts/storage/DegenerusGameStorage.sol:415:    mapping(uint24 => address[][256]) internal traitBurnTicket;
```

**Source-of-truth findings:**

| Catalog writer claim | Current source disposition |
|---|---|
| `adminSeedTraitBucket` direct push @ DegenerusGame.sol:2398 (V-016, CATALOG §15 row 154, §16 row 351) | **PHANTOM** — function name absent from `contracts/`; line 2398 is the `sampleTraitTickets` external **view** function (read-only storage reference for far-future BAF scatter sampling, returns `address[] memory`). |
| `adminClearTraitBucket` direct push @ DegenerusGame.sol:2427 (V-017, CATALOG §15 row 155, §16 row 352) | **PHANTOM** — function name absent from `contracts/`; line 2427 is the `sampleTraitTicketsAtLevel` external **view** function (read-only sampling helper). |
| Helper writer @ DegenerusGame.sol:2510 (V-018, CATALOG §15 row 156, §16 row 353) | **PHANTOM-AS-WRITER** — line 2510 is the `getTickets` external **view** function (paginated count of player tickets); no `.push` / no `sstore`; storage reference is bound `storage` for read-only iteration. |
| `_purchaseDeityPass` @ WhaleModule.sol:598 (V-019, CATALOG §15 row 157, §16 row 354) | **CONFIRMED writer** — `deityBySymbol[symbolId] = buyer` SSTORE at WhaleModule.sol:598; reached from external `purchaseDeityPass(address,uint8)` at WhaleModule.sol:538; existing `if (rngLockedFlag) revert RngLocked();` gate at WhaleModule.sol:543. |

**Cluster-wide consequence:** V-016, V-017, V-018 are **source-absent VIOLATIONs** — the only actual SSTORE writer of `traitBurnTicket[lvl][trait]` in current `contracts/` is `_raritySymbolBatch` (MintModule.sol:616 length-write + :627 element-push), which the catalog itself classifies as **EXEMPT-ADVANCEGAME** in V-014 / V-015. There is no non-EXEMPT writer of S-06 in the deployed-bytecode call graph. V-019 is a real, source-grounded VIOLATION as classified; the catalog's stack-strict rule fires despite the runtime `rngLockedFlag` gate at :543 because the gate misses the `gameOver` window arm.

**FIXREC author posture:** Per `feedback_no_history_in_comments.md` ("comments describe what IS, never what changed") and `feedback_verify_call_graph_against_source.md` ("planning 'by construction' claims must be grep-verified against source pre-patch"), V-016 / V-017 / V-018 below carry a **NO-OP fix recommendation** with v44.0 handoff anchor instructing the FIX milestone plan-phase to (a) re-grep-verify against source state at v44.0-execution time, (b) only synthesize the gated-revert if the writer becomes present (e.g. a future admin-bootstrap feature is added), and (c) otherwise resolve the CATALOG row by amending the catalog to mark V-016 / V-017 / V-018 as **STALE-PHANTOM** at the v44.0 milestone's CATALOG-refresh sub-phase. V-019 below carries a **real one-line revert-extension** recommendation.

---

## §1 — VIOLATION V-016: traitBurnTicket admin-seed writer (PHANTOM)

**CATALOG row:** RNGLOCK-CATALOG.md §16 row 351 → `V-016 | S-06 traitBurnTicket[lvl][trait] | adminSeedTraitBucket direct push | DegenerusGame.sol:2398 (admin) | NO — admin EOA | VIOLATION | (a) | Gate adminSeed on !rngLockedFlag && !gameOver | D-43N-V44-HANDOFF-09`.
**Slot:** `traitBurnTicket[lvl][trait]` (S-06; DegenerusGameStorage.sol:415).
**Claimed writer:** `adminSeedTraitBucket` direct push @ DegenerusGame.sol:2398.

### §1.A — Design-intent backward-trace (FIXREC-02)

**Original-phase reference:** `[design-intent: pre-v25 baseline admin bootstrap; no dedicated trace artifact]`. Per `feedback_design_intent_before_deletion.md` no-fabrication rule, the FIXREC author searched `.planning/milestones/` for `adminSeedTraitBucket` — zero hits across v2.1 through v42.0 milestone phases. The phrase appears only in post-Phase-298 catalog-author working notes inside `.planning/RNGLOCK-CATALOG.md` and `.planning/phases/298-*/` (3 files total).

**What S-06 is for (slot-level intent, source-grounded):** `traitBurnTicket[lvl][trait]` is the per-level / per-trait-id bucket of ticket-holder addresses that participates in trait-matched jackpot winner selection. Reader side: `_randTraitTicket` (JackpotModule.sol:1707) — `address[] storage holders = traitBurnTicket_[trait]; uint256 len = holders.length;` (line 1718-1719) — selects `holders[idx]` as the literal jackpot ETH winner when `idx < len`, else falls through to the virtual deity entry (`deityBySymbol[fullSymId]`). The same bucket length feeds `_computeBucketCounts` (JackpotModule.sol:1030/1039) for bucket-budget allocation and is read again per-trait by `_awardDailyCoinToTraitWinners` (JackpotModule.sol:1860). Writer side: per grep, the only SSTORE site in `contracts/` is `_raritySymbolBatch`'s inline-assembly `sstore` to `keccak256(lvl, traitBurnTicket.slot)`-derived length + element slots (MintModule.sol:616 / :627), reached exclusively via the advanceGame ticket-batch delegate stack — which the catalog classifies as EXEMPT-ADVANCEGAME in V-014 / V-015.

**Why no admin direct-push writer exists in current source:** The Phase 298 CATALOG §15 rows 154-156 enumerate three additional S-06 writers anchored on `DegenerusGame.sol:2398 / :2427 / :2510`. Re-reading those lines in current source:

- DegenerusGame.sol:2398 — inside `sampleTraitTickets(uint256 entropy) external view returns (uint24 lvlSel, uint8 traitSel, address[] memory tickets)` (signature at :2376-:2381). Line 2398 reads `address[] storage arr = traitBurnTicket[lvlSel][traitSel];` then `arr.length` (:2399), then iterates `arr[(start + i) % len]` into a memory return array (:2408). **No `.push`, no `sstore`, no in-place mutation.** Function modifier is `external view`, so SSTORE is statically prohibited.
- DegenerusGame.sol:2427 — inside `sampleTraitTicketsAtLevel(uint24 targetLvl, uint256 entropy) external view returns (uint8 traitSel, address[] memory tickets)` (signature at :2422-:2425). Same shape: read-only sample helper.
- DegenerusGame.sol:2510 — inside `getTickets(uint8 trait, uint24 lvl, uint32 offset, uint32 limit, address player) external view returns (uint24 count, uint32 nextOffset, uint32 total)` (signature at :2503-:2509). Paginated read-only counter.

**What behavior would break if a blanket `if (rngLockedFlag) revert` were added:** N/A — the recommended gate site does not exist as a writer; gating a `view` function on `rngLockedFlag` would convert read-only sampling helpers into reverters during rngLock, breaking BAF scatter sampling that legitimately reads bucket state during resolution. The catalog tactic implicitly assumes a writer is present.

### §1.B — Actor game-theory walk (FIXREC-03)

**Exploit-actor class:** N/A — no writer exists in current source for an actor to invoke. If the catalog row were source-grounded (i.e. if an `adminSeedTraitBucket(uint24 lvl, uint8 trait, address[] calldata holders)` admin entry were added in a future feature), the exploit-actor class would be **admin (privileged)**:
- **Adversarial-admin model:** Admin observes a pending VRF callback inside the rngLock window for daily jackpot resolution, calls `adminSeedTraitBucket(lvl, trait, [colluder_address])` to splice a controlled address into the bucket. `_randTraitTicket` at JackpotModule.sol:1718 reads `holders[idx]` post-splice, awarding the controlled address the jackpot payout.
- **Action sequence (counterfactual):** (1) VRF request emits → `rngLockedFlag = true`. (2) Admin reads `_randTraitTicket` math (line 1749-1751) and pre-computes which `idx` will hit for the next VRF word (admin cannot pre-compute the VRF word itself, but **can** pre-compute the modular reduction across all possible bucket sizes). (3) Admin picks a target trait, calls `adminSeedTraitBucket` to resize the bucket so the colluder address lands at the favorable `idx` post-modulo. (4) VRF callback fires → colluder wins.
- **EV magnitude (counterfactual):** **CATASTROPHE-tier** at terminal jackpot drain — `_processDailyEth` (JackpotModule.sol:1232) and `_runEarlyBirdLootboxJackpot` (:676) and `_distributeTicketJackpot` (:896) all consume trait-bucket holders for payout-recipient selection. A 4-bucket reseed during the game-over drain could redirect the full terminal pool to attacker addresses.
- **Economic-likelihood disposition (counterfactual):** **LOW** under trust-minimization (admin assumed honest); **HIGH** under audit-strict (admin treated as adversarial-capable, per `feedback_design_intent_before_deletion.md` actor-walk discipline). The audit posture requires modeling adversarial admin even when the trust model is benign, because the gate is a defense-in-depth invariant that holds across all actor models.

**Real (source-grounded) actor model:** Zero — no actor can reach a non-EXEMPT writer of S-06. The only writer is MintModule.sol:616/:627 inside `_raritySymbolBatch`, only reachable via `advanceGame` (EXEMPT-ADVANCEGAME per V-014 / V-015).

### §1.C — Recommended tactic + rationale + impact (FIXREC-01 + FIXREC-04)

**Recommended tactic:** **NO-OP** at v43.0 audit milestone. Catalog tactic (a) `Gate adminSeed on !rngLockedFlag && !gameOver` is **not applicable** because the function does not exist in current `contracts/`.

**Rationale:** Per `feedback_verify_call_graph_against_source.md`, fix recommendations must be grep-verified against source pre-patch. Authoring a v44.0 fix for a non-existent function would either (a) require adding the function (out-of-scope expansion of contract surface during a defensive hardening milestone — violates `feedback_frozen_contracts_no_future_proofing.md`), or (b) decay into a phantom `// TODO when admin writer is added` comment which violates `feedback_no_history_in_comments.md`.

**Bytecode impact:** **+0 bytes.** No code emitted.
**Storage-layout impact:** **byte-identical.** No new slots, no slot reordering.
**Public-ABI impact:** **NON-BREAKING.** No selector added, no event topic-hash changed.

**v44.0 FIX-MILESTONE plan-phase guidance:** At v44.0 CATALOG-refresh sub-phase, re-grep `contracts/` for `adminSeedTraitBucket`. If the function is absent, amend RNGLOCK-CATALOG.md §15 row 154 + §16 row 351 to **STALE-PHANTOM** disposition with a one-line note citing this FIXREC §1. If the function has been added between v43.0 audit close and v44.0 fix execution (out-of-scope but possible), apply tactic (a) **per the then-current source signature** — the gate site is `function adminSeedTraitBucket(...) external onlyAdmin { if (rngLockedFlag) revert RngLocked(); if (gameOver) revert GameOver(); ... }` using the `RngLocked` custom error already declared at DegenerusGameStorage.sol:213 and revert-pattern precedents at MintModule.sol:1221, BurnieCoinflip.sol:730, WhaleModule.sol:543. The bytecode delta for the live-writer case is ~+25-35 bytes per gate: one `SLOAD rngLockedFlag` (~2100 gas cold / 100 warm) + `JUMPI` + `REVERT` for the custom error 4-byte selector, plus identical pattern for `gameOver` (declared at DegenerusGameStorage.sol:290 as `bool public gameOver`).

### §1.D — v44.0 FIX-MILESTONE handoff anchor (FIXREC-05)

**Anchor:** D-43N-V44-HANDOFF-09 — `traitBurnTicket` admin-seed writer NO-OP at v43.0; CATALOG row marked STALE-PHANTOM pending v44.0 CATALOG refresh. **Catalog row:** RNGLOCK-CATALOG.md:351 (§16 verdict-matrix). **Writer (claimed):** DegenerusGame.sol:2398 (actually `sampleTraitTickets` view function in current source; phantom-as-writer).

---

## §2 — VIOLATION V-017: traitBurnTicket admin-clear writer (PHANTOM)

**CATALOG row:** RNGLOCK-CATALOG.md §16 row 352 → `V-017 | S-06 traitBurnTicket[lvl][trait] | adminClearTraitBucket direct push | DegenerusGame.sol:2427 (admin) | NO — admin EOA | VIOLATION | (a) | Gate adminClear on !rngLockedFlag && !gameOver | D-43N-V44-HANDOFF-10`.
**Slot:** `traitBurnTicket[lvl][trait]` (S-06; DegenerusGameStorage.sol:415).
**Claimed writer:** `adminClearTraitBucket` direct push @ DegenerusGame.sol:2427.

### §2.A — Design-intent backward-trace (FIXREC-02)

**Original-phase reference:** `[design-intent: pre-v25 baseline admin replay/teardown helper; no dedicated trace artifact]`. Per `feedback_design_intent_before_deletion.md` no-fabrication rule, `.planning/milestones/` grep for `adminClearTraitBucket` returns zero hits across v2.1-v42.0.

**What clearing S-06 would have meant (counterfactual slot-level intent):** Resetting `traitBurnTicket[lvl][trait]` to empty would be a teardown action used either (a) pre-launch to wipe seeded test buckets before mainnet activation, or (b) post-drain at terminal game-over to free storage refund gas via `sstore(slot, 0)`. The reader-side consequence of clearing during live resolution: `_randTraitTicket`'s `holders.length` (JackpotModule.sol:1719) becomes zero, which forces the deity virtual-entry path (`idx >= len` at :1755) for every winner slot — collapsing all trait-trait jackpot winners onto `deityBySymbol[fullSymId]` (a single attacker-controlled address if the attacker bought that deity pass).

**Current-source disposition:** DegenerusGame.sol:2427 is `sampleTraitTicketsAtLevel(uint24 targetLvl, uint256 entropy) external view returns (uint8 traitSel, address[] memory tickets)` (signature at :2422-:2425). Body: `traitSel = uint8(entropy >> 24); address[] storage arr = traitBurnTicket[targetLvl][traitSel]; uint256 len = arr.length; if (len == 0) return (traitSel, new address[](0)); ...` followed by a read-only memory-array fill loop (:2436-:2441). **No `.push`, no `sstore`, no `delete` of any storage slot.** Function modifier is `external view`.

**What behavior would break if a blanket `if (rngLockedFlag) revert` were added to line :2427:** The view function would revert during rngLock, blocking off-chain BAF / front-end queries of bucket samples during the resolution window — a tangible UX regression with zero defensive benefit (view functions cannot mutate state, so the gate would be guarding nothing).

### §2.B — Actor game-theory walk (FIXREC-03)

**Exploit-actor class (counterfactual):** Admin (privileged). The counterfactual exploit is the dual of §1.B: instead of *adding* a controlled address to the bucket, admin *clears* the bucket mid-resolution to force the deity-virtual-entry payout path (JackpotModule.sol:1755-1758 `winners[i] = deity`).
- **Action sequence (counterfactual):** (1) Attacker purchases a deity pass for a target symbol (e.g. trait `t`); `deityBySymbol[symbolId] = attacker` via WhaleModule.sol:598. (2) VRF request emits → `rngLockedFlag = true`. (3) Adversarial admin calls `adminClearTraitBucket(lvl, trait)` zeroing `traitBurnTicket[lvl][trait].length`. (4) VRF callback fires → `_randTraitTicket` sees `len = 0`, `virtualCount ≥ 1` (because deity is set), `effectiveLen = 1`, every winner slot resolves to attacker via `idx % 1 = 0 >= 0 = len`. (5) Attacker captures all jackpot winners' payouts for the affected trait.
- **EV magnitude (counterfactual):** **HIGH-to-CATASTROPHE-tier** — multi-winner traits at gold tier (color==7, `virtualCount = 1`) and common tier (`virtualCount = max(2, len/50)`) both collapse onto the deity address when length=0.
- **Economic-likelihood disposition (counterfactual):** **LOW** under trust-minimization, **HIGH** under audit-strict.

**Real (source-grounded) actor model:** Zero — function does not exist.

### §2.C — Recommended tactic + rationale + impact (FIXREC-01 + FIXREC-04)

**Recommended tactic:** **NO-OP** at v43.0. Same rationale as §1.C — function is a phantom.

**Bytecode impact:** **+0 bytes.**
**Storage-layout impact:** **byte-identical.**
**Public-ABI impact:** **NON-BREAKING.**

**v44.0 plan-phase guidance:** Identical handling pattern to §1.C v44.0 guidance. If `adminClearTraitBucket` is absent at v44.0 source-state, mark CATALOG §15 row 155 + §16 row 352 as **STALE-PHANTOM**. If a `clear`/`delete`-shaped admin writer is added between milestones, apply tactic (a) with the same two-arm `if (rngLockedFlag) revert RngLocked(); if (gameOver) revert GameOver();` gate at function entry.

### §2.D — v44.0 FIX-MILESTONE handoff anchor (FIXREC-05)

**Anchor:** D-43N-V44-HANDOFF-10 — `traitBurnTicket` admin-clear writer NO-OP at v43.0; CATALOG row marked STALE-PHANTOM pending v44.0 CATALOG refresh. **Catalog row:** RNGLOCK-CATALOG.md:352 (§16 verdict-matrix). **Writer (claimed):** DegenerusGame.sol:2427 (actually `sampleTraitTicketsAtLevel` view function in current source; phantom-as-writer).

---

## §3 — VIOLATION V-018: traitBurnTicket helper writer @ :2510 (PHANTOM)

**CATALOG row:** RNGLOCK-CATALOG.md §16 row 353 → `V-018 | S-06 traitBurnTicket[lvl][trait] | helper writer at :2510 | DegenerusGame.sol:2510 (admin/helper) | NO — admin/helper | VIOLATION | (a) | Gate writer on !gameOver — terminal jackpot bucket must be frozen at drain | D-43N-V44-HANDOFF-11`.
**Slot:** `traitBurnTicket[lvl][trait]` (S-06; DegenerusGameStorage.sol:415).
**Claimed writer:** helper writer @ DegenerusGame.sol:2510.

### §3.A — Design-intent backward-trace (FIXREC-02)

**Original-phase reference:** `[design-intent: catalog §C.3.4 row flagged for source-line review; no original phase identified]`. CATALOG §C.3.4 (RNGLOCK-CATALOG.md:1390) explicitly notes "Source-code review of the surrounding function context is required; flagged here for completeness so the §D verdict matrix evaluates it" — the catalog author already surfaced uncertainty about the row at enumeration time. `.planning/milestones/` grep for `traitBurnTicket\[lvl\]\[trait\]` returns hits only in v25.0+ adversarial-audit phases and v41.0+ trait-ticket plans, none of which introduce a non-MintModule writer.

**Current-source disposition of line :2510:** Inside `getTickets(uint8 trait, uint24 lvl, uint32 offset, uint32 limit, address player) external view returns (uint24 count, uint32 nextOffset, uint32 total)` (signature at :2503-:2509). Body:

```solidity
address[] storage a = traitBurnTicket[lvl][trait];  // :2510 — read-only storage reference binding
total = uint32(a.length);                            // :2511 — SLOAD of length
if (offset >= total) return (0, total, total);       // :2512
uint256 end = offset + limit;                        // :2514
if (end > total) end = total;
for (uint256 i = offset; i < end; ) {                // :2517 — read-only iteration
    if (a[i] == player) count++;                     // :2518 — SLOAD comparison, no write
    unchecked { ++i; }
}
nextOffset = uint32(end);                            // :2523
```

**No `.push`, no `sstore`, no `delete`, no `a[i] = ...` write.** The function is a paginated read-only ticket counter used by front-ends to display a player's bucket holdings without OOG-risk on large buckets. Function modifier is `external view`.

**What behavior would break if a writer-gate were added to line :2510:** N/A — line :2510 is not a writer. The catalog tactic (a) `Gate writer on !gameOver — terminal jackpot bucket must be frozen at drain` is unactionable because there is no writer at this line.

### §3.B — Actor game-theory walk (FIXREC-03)

**Exploit-actor class (counterfactual):** Admin/helper (privileged). Without a source-grounded writer signature, the counterfactual is even less concrete than §1.B / §2.B — the catalog row is a placeholder for "source review required" rather than a specific writer claim.

**Real (source-grounded) actor model:** Zero — line :2510 is a view function read.

### §3.C — Recommended tactic + rationale + impact (FIXREC-01 + FIXREC-04)

**Recommended tactic:** **NO-OP** at v43.0. The catalog row was explicitly flagged at enumeration time as "source-code review required" (RNGLOCK-CATALOG.md:1390); current grep resolves the review as **no writer at this line**.

**Bytecode impact:** **+0 bytes.**
**Storage-layout impact:** **byte-identical.**
**Public-ABI impact:** **NON-BREAKING.**

**v44.0 plan-phase guidance:** Mark CATALOG §15 row 156 + §16 row 353 as **STALE-PHANTOM** at v44.0 CATALOG-refresh sub-phase, citing this FIXREC §3 (Phase 299-02) as the resolution of the "source review required" placeholder.

### §3.D — v44.0 FIX-MILESTONE handoff anchor (FIXREC-05)

**Anchor:** D-43N-V44-HANDOFF-11 — `traitBurnTicket` helper-writer-at-:2510 NO-OP at v43.0; CATALOG row marked STALE-PHANTOM (resolves the §C.3.4 "source review required" placeholder). **Catalog row:** RNGLOCK-CATALOG.md:353 (§16 verdict-matrix); placeholder at RNGLOCK-CATALOG.md:1390 (§C.3.4). **Writer (claimed):** DegenerusGame.sol:2510 (actually `getTickets` view function in current source; phantom-as-writer).

---

## §4 — VIOLATION V-019: deityBySymbol via `_purchaseDeityPass` (REAL)

**CATALOG row:** RNGLOCK-CATALOG.md §16 row 354 → `V-019 | S-07 deityBySymbol[fullSymId] | _purchaseDeityPass | WhaleModule.sol:538 (EOA purchaseDeityPass) | NO — EOA; runtime rngLockedFlag gate at :543 | VIOLATION | (a) | Gate _purchaseDeityPass on !gameOver — already gates rngLockedFlag at :543 | D-43N-V44-HANDOFF-12`.
**Slot:** `deityBySymbol[fullSymId]` (S-07; DegenerusGameStorage.sol — `mapping(uint16 => address) internal`).
**Writer:** `_purchaseDeityPass` SSTORE at `DegenerusGameWhaleModule.sol:598` (`deityBySymbol[symbolId] = buyer;`).
**External entry:** `purchaseDeityPass(address buyer, uint8 symbolId) external payable` at WhaleModule.sol:538 → calls `_purchaseDeityPass(buyer, symbolId)` private at :542.
**Existing runtime gate:** `if (rngLockedFlag) revert RngLocked();` at WhaleModule.sol:543 (first statement of `_purchaseDeityPass`); followed by `if (_livenessTriggered()) revert E();` at :544.

### §4.A — Design-intent backward-trace (FIXREC-02)

**Original-phase reference:** Phase 294 DPNERF (`.planning/milestones/v42.0-phases/294-deity-pass-gold-nerf-dpnerf/294-01-DESIGN-INTENT-TRACE.md`) is the most recent design-intent anchor touching the deity-pass subsystem (caller-uniform discipline + gold-tier virtual-entry nerf). The deity-pass purchase / `deityBySymbol` mapping pre-dates Phase 294 — grep on `.planning/milestones/v25.0-phases/214-adversarial-audit/214-04-STORAGE-LAYOUT.md` and `.planning/milestones/v25.0-phases/214-adversarial-audit/214-03-STATE-COMPOSITION.md` confirms `deityBySymbol` was already enumerated as a participating slot at v25.0 adversarial-audit time. Pre-v25 introduction phase not isolated to a single artifact (deity-pass economic mechanic is part of the baseline whale-module design from project inception).

**What S-07 is for (slot-level intent, source-grounded):** `deityBySymbol[symbolId]` (uint16 key, address value) maps a 0-31 symbol identifier (4 quadrants × 8 symbols) to the EOA that has purchased the corresponding deity pass. The mapping is the **virtual-entry injection vector** for trait-matched jackpot resolution: at JackpotModule.sol:1730 `_randTraitTicket` computes `uint8 fullSymId = (trait >> 6) * 8 + (trait & 0x07);` and reads `deity = deityBySymbol[fullSymId];`. When `deity != address(0)`, the function inflates `effectiveLen` by `virtualCount` (1 for gold-tier color==7, `max(2, len/50)` for common tiers — JackpotModule.sol:1732-1737), and when the modular winner-index `idx >= len`, the winner becomes the deity address (:1755-1757). The same pattern repeats at `_computeBucketCounts` (JackpotModule.sol:1044) and `_awardDailyCoinToTraitWinners` (JackpotModule.sol:1844).

**Why the existing `rngLockedFlag` gate at :543 is partial coverage:** `rngLockedFlag` is set/cleared by the VRF request/callback lifecycle (set in AdvanceModule's request path; cleared in AdvanceModule's `_unlockRng` per AdvanceModule.sol:631). The flag is **active** during the per-day jackpot resolution window. But at terminal game-over, the resolution path is `_handleGameOverPath` (AdvanceModule.sol:539) which short-circuits the rngLockedFlag set/clear cycle for the final drain — and even if `rngLockedFlag` were cleared post-drain by the standard lifecycle, the persistent `gameOver` flag (DegenerusGameStorage.sol:290 `bool public gameOver`) remains true for the rest of contract lifetime. Without a `gameOver` arm on the gate, **a whale could call `purchaseDeityPass` after `gameOver = true` but before terminal-drain settlement completes**, binding `deityBySymbol[symbolId]` to a freshly chosen address moments before the terminal jackpot consumes `deityBySymbol` at JackpotModule.sol:1730. The catalog correctly flags this as the missing arm.

**Important nuance — `_livenessTriggered()` at :544 is NOT a substitute for `gameOver`:** `_livenessTriggered()` (DegenerusGameStorage.sol:1243-1252) checks idle-day timeout (`lvl == 0 && currentDay - psd > _DEPLOY_IDLE_TIMEOUT_DAYS`), late-game idle timeout (`lvl != 0 && currentDay - psd > 120`), and VRF grace-period exceeded (`rngStart != 0 && block.timestamp - rngStart >= _VRF_GRACE_PERIOD`). It does **not** read the persistent `gameOver` flag — and crucially, `_livenessTriggered()` returns `false` when `lastPurchaseDay || jackpotPhaseFlag` (early-return at :1244). During terminal game-over **settlement** (post-trigger, pre-final-payout-completion), `gameOver == true` but `_livenessTriggered()` may return `false` if the trigger path set `lastPurchaseDay`. This confirms the catalog's surgical recommendation: the gate needs an explicit `if (gameOver) revert ...;` arm in addition to the existing `rngLockedFlag` and `_livenessTriggered` checks.

**What behavior would break if `!gameOver` were added to `_purchaseDeityPass`:** After terminal game-over trigger, deity-pass purchase is permanently blocked. This is the **intended** terminal-window invariant per the catalog (`terminal jackpot bucket must be frozen at drain`) — the deity-pass economic mechanic is meaningful only when level progression and jackpot resolution are live; post-`gameOver` purchases would have no downstream payout path and would constitute griefing surface only. Non-breaking semantics for the legitimate use case (purchase during normal game play before `gameOver` trigger).

### §4.B — Actor game-theory walk (FIXREC-03)

**Exploit-actor class:** Whale player (EOA-callable external entry; payable). Not admin-privileged — the only gating is the `rngLockedFlag` + `_livenessTriggered` revert pair plus the `deityBySymbol[symbolId] != address(0)` collision check at :546 (which means *the symbol must still be available* — caps the exploit window to symbols not yet bought).

**Action sequence (real, source-grounded):**

1. Attacker monitors mempool/chain state for the `gameOver` trigger (set on the terminal level-cap or liveness-trigger paths inside AdvanceModule's `_finalize` / `_handleGameOverPath`). The flag is `bool public gameOver` (DegenerusGameStorage.sol:290), so trigger is observable on-chain via storage SLOAD or via any state-changing tx that touched the flag.
2. Between `gameOver = true` write and terminal-jackpot completion, attacker observes which symbols `0..31` are still un-purchased (i.e. `deityBySymbol[symbolId] == address(0)`).
3. Attacker chooses a target trait (8 colors × 4 quadrants × 8 symbols = 256 traits, but the `fullSymId` derivation at JackpotModule.sol:1726 collapses to 32 fullSymIds) where they predict the terminal jackpot will pay (or simply maximize the deity-virtual-entry probability inflation for that fullSymId across all eight color-variants of that quadrant-symbol pairing).
4. Attacker calls `purchaseDeityPass(attacker_addr, target_symbolId)` paying `DEITY_PASS_BASE + (k * (k+1) * 1e18) / 2` ETH (price scales with `k = deityPassOwners.length` — up to 520 ETH for the 32nd pass per :527 docstring) with optional `boonTier` discount.
5. The `rngLockedFlag` check at :543 currently passes if the VRF lifecycle has cleared the flag (which it has by the time terminal drain is settling per AdvanceModule:631 sequencing). `_livenessTriggered()` at :544 may also pass (returns false when `lastPurchaseDay` or `jackpotPhaseFlag` is set, per :1244).
6. SSTORE at :598 binds `deityBySymbol[target_symbolId] = attacker`.
7. Terminal-jackpot consumer (the final pass through `_distributeTicketJackpot` / `_processDailyEth` / `_awardDailyCoinToTraitWinners` for `gameOver`-mode payouts) reads `deityBySymbol[fullSymId]` at JackpotModule.sol:1044 / :1730 / :1844, sees attacker, and routes virtual-entry winnings to attacker.

**EV magnitude:** **MEDIUM-HIGH** — terminal jackpot pool is the cumulative `currentPrizePool` plus `prizePoolsPacked` accumulations, historically the largest single payout event in the game lifecycle. The attacker pays up to 520 ETH for the deity pass but captures `virtualCount / (len + virtualCount)` share of trait payouts for the bound `fullSymId` across **all 8 color variants** (because `fullSymId = (trait >> 6) * 8 + (trait & 0x07)` does not include the color bits at `(trait >> 3) & 7`). For gold-tier (color==7) `virtualCount = 1`; for common tiers `virtualCount = max(2, len/50)`. Across 8 colors × multi-trait payouts at terminal drain, the deity-virtual-entry capture is structurally non-trivial.

**Economic-likelihood disposition:** **MEDIUM-HIGH**. The exploit window is narrow (between `gameOver = true` and terminal-jackpot completion — likely a few blocks), but the trigger is public-observable and the EV is large. The attack is **strictly more attractive than legitimate deity-pass purchase** during normal play because the buyer captures terminal-jackpot virtual entries without participating in earlier levels' wager / trait-bucket commitment surface. Audit-strict disposition: **the existing :543 gate is insufficient and the catalog's `!gameOver` arm is a load-bearing one-line invariant**.

**Note on alternative trust assumptions:** Under a benign-actor model the EV-weighted probability is lower (deity-pass purchasers are typically long-horizon whales, not griefing capital), but the audit posture per `feedback_design_intent_before_deletion.md` ("trace original design intent + actor game-theory across timing/state combos") requires modeling the adversarial actor explicitly. The `gameOver`-arm gate is the structural invariant; the actor-model probability does not change the recommendation.

### §4.C — Recommended tactic + rationale + impact (FIXREC-01 + FIXREC-04)

**Recommended tactic:** **(a) gated revert — extend existing :543 gate with `gameOver` arm.** Catalog tactic (a) verbatim: `Gate _purchaseDeityPass on !gameOver — already gates rngLockedFlag at :543`.

**Concrete patch shape (for v44.0 plan-phase consumption, not for application here):**

```solidity
// At DegenerusGameWhaleModule.sol:543 — current source has line 543 only.
// v44.0 fix synthesizes a single-line addition after :543:
function _purchaseDeityPass(address buyer, uint8 symbolId) private {
    if (rngLockedFlag) revert RngLocked();      // :543 — exists
    if (gameOver) revert E();                   // NEW — one line; pre-existing E() error matches surrounding style at :544/:545/:546/:549
    if (_livenessTriggered()) revert E();       // :544 — exists
    ...
}
```

**Rationale:**

1. **Minimal-surface fix** — one line, one storage-read, one branch. The `gameOver` flag is already declared at DegenerusGameStorage.sol:290 (`bool public gameOver`); no new state, no new error type (uses the pre-existing `error E()` shared across the module's revert path at :544/:545/:546/:549/:581 — consistent with `feedback_no_history_in_comments.md` "describes what IS" by reusing the established error shape).
2. **Defense-in-depth on the trait-bucket consumer freeze invariant** — the catalog's freeze-at-drain invariant for terminal jackpot resolution requires that **all participating-slot writers** be inert during the `gameOver` window. `_purchaseDeityPass` is the sole non-MintModule writer of S-07. With this gate, the `deityBySymbol` mapping becomes append-only across the live-game window and frozen at `gameOver` — the same shape that `_raritySymbolBatch` already enforces for S-06 via the EXEMPT-ADVANCEGAME stack (no advanceGame ticks fire post-`gameOver` except the terminal drain itself, which does not invoke MintModule's `_storeTraits`).
3. **Consistent with the project-wide `RngLocked`+`E()` revert convention** — the existing :543 line uses the `RngLocked` custom error (declared at DegenerusGameStorage.sol:213 and used at MintModule.sol:1221, BurnieCoinflip.sol:730, sStonk → StakedDegenerusStonk pattern). The new `gameOver` arm uses the module-internal `error E()` matching the surrounding revert style at :544-:581 — this maximizes ABI-stability for downstream consumers (no new selector hash to register).
4. **Behavior-preserving for the legitimate use case** — `purchaseDeityPass` during normal game play (pre-`gameOver`) is unaffected. The :522 docstring already states "Available before gameOver" — the gate **codifies the docstring's already-stated semantic invariant** that the current implementation does not enforce. This aligns with `feedback_design_intent_before_deletion.md` ("trace original design intent" — the docstring is the design-intent record).

**Bytecode impact estimate:** **+12 to +25 bytes** depending on optimizer settings. Pattern: `PUSH1 0x{slot} SLOAD ISZERO PUSH2 {label} JUMPI PUSH4 {E_selector} PUSH1 0x00 MSTORE PUSH1 0x04 PUSH1 0x00 REVERT` (the `error E()` 4-byte selector revert). Comparable to the existing `if (_livenessTriggered()) revert E();` gate at :544 which compiles to ~30 bytes (CALL + ISZERO + JUMPI + revert-pattern). For a direct storage-bool SLOAD the bytecode is shorter than the function-call variant — estimate ~12-18 bytes net.

**Storage-layout impact:** **byte-identical.** `gameOver` is already declared at DegenerusGameStorage.sol:290; no new slot allocated.

**Public-ABI impact:** **NON-BREAKING** per `D-40N-EVT-BREAK-01`. The selector for `purchaseDeityPass(address,uint8)` is unchanged. The added `revert E()` path uses an error selector already in the contract's ABI (used pervasively across :544/:545/:546/:549/:581 etc.). No event topic-hash change, no new public function, no return-type change. Downstream callers that previously could call `purchaseDeityPass` during the post-`gameOver` settlement window now revert — but the docstring at :522 already states "Available before gameOver", so the runtime behavior aligns with the documented contract, not the other way around. **The semantic change for callers is "this revert path was always documented; now it is enforced."**

**Verification handoff to v44.0:** The fix is testable via a property-based assertion: `assert(!gameOver || ! purchaseDeityPass succeeds for any (buyer, symbolId))`. Deferred to v44.0 plan-phase per `D-299-WAVE-SHAPE-01` (audit-only posture — no test/ mutations at v43.0).

### §4.D — v44.0 FIX-MILESTONE handoff anchor (FIXREC-05)

**Anchor:** D-43N-V44-HANDOFF-12 — `_purchaseDeityPass` `!gameOver` arm extension; one-line revert addition after existing :543 `rngLockedFlag` gate; uses pre-declared `gameOver` (DegenerusGameStorage.sol:290) and pre-declared `error E()`. **Catalog row:** RNGLOCK-CATALOG.md:354 (§16 verdict-matrix); §15 row 157 writer enumeration; §C.5.1 disposition (RNGLOCK-CATALOG.md:1398). **Writer:** DegenerusGameWhaleModule.sol:598 (SSTORE `deityBySymbol[symbolId] = buyer`); external entry at :538; private body at :542; existing partial gate at :543.

---

## Cluster summary

| V-NNN | Slot | Writer (claimed → actual) | Disposition | Tactic | Anchor | Bytecode Δ | EV-tier |
|-------|------|---------------------------|-------------|--------|--------|------------|---------|
| V-016 | S-06 | `adminSeedTraitBucket` @ :2398 → `sampleTraitTickets` view (PHANTOM) | NO-OP; mark CATALOG STALE-PHANTOM at v44.0 | (a) deferred / inapplicable | D-43N-V44-HANDOFF-09 | +0 bytes | LOW (counterfactual; CATASTROPHE if live) |
| V-017 | S-06 | `adminClearTraitBucket` @ :2427 → `sampleTraitTicketsAtLevel` view (PHANTOM) | NO-OP; mark CATALOG STALE-PHANTOM at v44.0 | (a) deferred / inapplicable | D-43N-V44-HANDOFF-10 | +0 bytes | LOW (counterfactual; HIGH-CATASTROPHE if live) |
| V-018 | S-06 | helper writer @ :2510 → `getTickets` view (PHANTOM) | NO-OP; resolves §C.3.4 source-review placeholder | (a) deferred / inapplicable | D-43N-V44-HANDOFF-11 | +0 bytes | UNKNOWN (placeholder row) |
| V-019 | S-07 | `_purchaseDeityPass` @ :598 (CONFIRMED) | One-line `if (gameOver) revert E();` after :543 | (a) gated revert | D-43N-V44-HANDOFF-12 | +12-25 bytes | MEDIUM-HIGH |

**Tactic-mix outcome:** Catalog assigned tactic (a) to all 4 rows. After source-grounded verification, only V-019 is a real-writer (a)-gated-revert; V-016/V-017/V-018 collapse to NO-OP with a v44.0 CATALOG-refresh handoff (resolving stale-phantom rows that were enumerated against pre-pivot or out-of-tree source state).

**Audit-only posture confirmed:** Zero `contracts/` mutations. Zero `test/` mutations. Zero by-design-exempt-from-fix tokens. All anchors emitted in `D-43N-V44-HANDOFF-NN` format per `D-299-FIXREC-LAYOUT-01` §M-handoff convention.
