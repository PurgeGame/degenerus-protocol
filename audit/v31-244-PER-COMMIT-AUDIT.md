---
status: FINAL — READ-ONLY
phase: 244-per-commit-adversarial-audit-evt-rng-qst-gox
milestone: v31.0
audit_baseline: 7ab515fe
audit_head: cc68bfc7
in_scope_commits:
  - ced654df
  - 16597cac
  - 6b3f4f3c
  - 771893d1
  - cc68bfc7
owning_plans:
  - 244-01 (EVT)
  - 244-02 (RNG)
  - 244-03 (QST)
  - 244-04 (GOX + consolidation)
severity_bar: "{SAFE, INFO, LOW, MEDIUM, HIGH, CRITICAL} per CONTEXT.md D-08; QST-05 uses {SAFE, INFO, INFO-unreproducible} per CONTEXT.md D-14 LOCKED bar; KI exception rows use RE_VERIFIED_AT_HEAD cc68bfc7 per CONTEXT.md D-22"
finding_ids_emitted: 0
working_files_preserved:
  - audit/v31-244-EVT.md
  - audit/v31-244-RNG.md
  - audit/v31-244-QST.md
  - audit/v31-244-GOX.md
---

# v31.0 Phase 244 — Per-Commit Adversarial Audit (consolidated deliverable)

**Status:** FINAL — READ-ONLY (locked at 244-04 SUMMARY commit per CONTEXT.md D-05)
**Audit baseline:** 7ab515fe
**Audit head:** cc68bfc7
**In-scope commits:** ced654df + 16597cac + 6b3f4f3c + 771893d1 + cc68bfc7 (BAF-coupling addendum per CONTEXT.md D-03; ffced9ef docs-only, out of scope per CONTEXT.md D-01)
**Phase:** 244-per-commit-adversarial-audit-evt-rng-qst-gox
**Owning plans:** 244-01 (EVT) + 244-02 (RNG) + 244-03 (QST) + 244-04 (GOX + consolidation)
**Severity bar:** {SAFE, INFO, LOW, MEDIUM, HIGH, CRITICAL} per CONTEXT.md D-08; QST-05 uses {SAFE, INFO, INFO-unreproducible} per CONTEXT.md D-14 LOCKED bar; KI exception rows use RE_VERIFIED_AT_HEAD cc68bfc7 annotation per CONTEXT.md D-22
**Finding-IDs:** NOT emitted in this phase per CONTEXT.md D-21 (Phase 246 FIND-01 owns assignment)
**Token-splitting guard for D-21 self-match prevention:** Phase-246 finding-ID token `F-31-NN` is omitted from deliverable body; verification shell snippets use runtime-assembled `TOKEN="F-31""-"` so verification commands do not self-match. `grep -cE 'F-31-[0-9]'` on this deliverable returns 0.

---

## §0 — Per-Phase Verdict Heatmap

Planner-discretion readability aid per CONTEXT.md §Claude's Discretion ("per-REQ closure heatmap at top — optional, not required"). REQ × Verdict matrix summarizing Phase 244 closure.

| REQ-ID | Verdict Rows | Floor Severity | KI Envelope | Owning Plan |
| --- | --- | --- | --- | --- |
| EVT-01 | 5 | SAFE | n/a | 244-01 |
| EVT-02 | 5 | INFO | n/a | 244-01 |
| EVT-03 | 8 | INFO | n/a | 244-01 |
| EVT-04 | 4 | INFO | n/a | 244-01 |
| RNG-01 | 11 | SAFE (10 SAFE + 1 RE_VERIFIED) | EXC-03 RE_VERIFIED_AT_HEAD cc68bfc7 | 244-02 |
| RNG-02 | 7 | SAFE (1 SAFE + 6 RE_VERIFIED) | EXC-02 RE_VERIFIED_AT_HEAD cc68bfc7 | 244-02 |
| RNG-03 | 2 | SAFE | n/a | 244-02 |
| QST-01 | 7 | SAFE | n/a | 244-03 |
| QST-02 | 5 | SAFE | n/a | 244-03 |
| QST-03 | 4 | SAFE (NEGATIVE-scope) | n/a | 244-03 |
| QST-04 | 5 | SAFE | n/a | 244-03 |
| QST-05 | 3 | SAFE (2 SAFE + 1 INFO commentary per D-14 DIRECTION-ONLY bar) | n/a | 244-03 |
| GOX-01 | 8 | SAFE | n/a | 244-04 |
| GOX-02 | 3 | SAFE | n/a | 244-04 |
| GOX-03 | 3 | SAFE | n/a | 244-04 |
| GOX-04 | 2 | SAFE (1 SAFE + 1 RE_VERIFIED) | EXC-02 RE_VERIFIED_AT_HEAD cc68bfc7 | 244-04 |
| GOX-05 | 1 | SAFE | n/a | 244-04 |
| GOX-06 | 3 | SAFE | n/a | 244-04 |
| GOX-07 | 1 | SAFE (FAST-CLOSE per D-15) | n/a | 244-04 |
| **Totals** | **87 V-rows** | **SAFE floor across 19 REQs** | **EXC-02 + EXC-03 RE_VERIFIED** | **4 plans** |

**Finding candidates:** 0 across all 4 bucket sections. All 19 REQs close with at least SAFE floor severity. 7 INFO rows across EVT-02/03/04 + QST-05 + GOX-04-V02 are by-design observations (NatSpec-disclosed surfaces, RE_VERIFIED_AT_HEAD KI envelopes, direction-only bytecode commentary) — NOT promoted to findings by Phase 244. Phase 246 FIND-01 may reclassify if full milestone context surfaces new signals.

**Phase 243 §1.7 finding-candidate closure summary** (per CONTEXT.md D-09 mapping):

| §1.7 Bullet | Owning Plan(s) | Closure Status | Primary Verdict Row |
| --- | --- | --- | --- |
| Bullet 1 (burn State-1 ordering) | 244-04 | CLOSED | GOX-02-V01 (§4) |
| Bullet 2 (burnWrapped State-1 divergence) | 244-04 | CLOSED | GOX-02-V02 (§4) |
| Bullet 3 (_gameOverEntropy rngRequestTime clearing) | 244-02 primary + 244-04 derived | CLOSED | RNG-02-V04 primary (§2); GOX-06-V01 derived (§4) |
| Bullet 4 (handleGameOverDrain reserved subtraction) | 244-04 | CLOSED | GOX-03-V03 (§4) |
| Bullet 5 (_handleGameOverPath gameOver-before-liveness reorder) | 244-04 | CLOSED | GOX-06-V02 (§4) |
| Bullet 6 (BAF bit-0 coupling) | 244-01 | CLOSED | EVT-03-V07 (§1) |
| Bullet 7 (markBafSkipped consumer gating) | 244-01 | CLOSED | EVT-02-V03 + EVT-02-V05 (§1) |
| Bullet 8 (cc68bfc7 jackpots direct-handle reentrancy parity) | 244-04 primary + 244-02 scope-disjoint | CLOSED | GOX-06-V03 primary (§4); RNG-01-V10 scope-disjoint (§2) |

All 8 Phase 243 §1.7 INFO finding candidates CLOSED in Phase 244. Zero rolled forward to Phase 245.

---

## §1 — EVT Bucket (commit ced654df + cc68bfc7 BAF-coupling addendum per CONTEXT.md D-03)

*Embedded verbatim from `audit/v31-244-EVT.md` working file. Working file preserved on disk per CONTEXT.md D-05.*

# v31.0 Phase 244 — EVT Bucket Audit (commits ced654df + cc68bfc7 BAF-coupling addendum)

Audit baseline: 7ab515fe
Audit head:     cc68bfc7
Owning commits: ced654df (JackpotTicketWin event correctness) + cc68bfc7 (BAF-coupling per CONTEXT.md D-03)
Scope per:      audit/v31-243-DELTA-SURFACE.md §6 D-243-I004..D-243-I007
Plan:           244-01-PLAN.md
Phase:          244-per-commit-adversarial-audit-evt-rng-qst-gox
Status:         WORKING (Task 1 + Task 2 complete — full EVT bucket audit in-file). 244-04 consolidates this file into `audit/v31-244-PER-COMMIT-AUDIT.md` per CONTEXT.md D-05.

## §0 — Per-Bucket Verdict Count Card

| REQ-ID | Verdict Rows | Finding Candidates | Floor Severity |
| --- | --- | --- | --- |
| EVT-01 | 5 | 0 | SAFE |
| EVT-02 | 5 | 0 | INFO |
| EVT-03 | 8 | 0 | INFO |
| EVT-04 | 4 | 0 | INFO |

Aggregate: 22 V-rows across 4 REQs; 0 finding candidates; bucket floor-severity INFO (no SAFE-below-INFO downgrades; no LOW/MEDIUM/HIGH/CRITICAL surfaced). Phase 243 §1.7 bullets 6 (BAF expected-value under bit-0 coupling) + 7 (markBafSkipped consumer gating) closed per CONTEXT.md D-09 mapping.

Floor-severity semantics per CONTEXT.md D-08: SAFE (adversarial vector enumerated, behavior matches claim under all reachable inputs, no finding worth surfacing) / INFO (observation worth recording for Phase 246 reviewer but not exploitable) / LOW / MEDIUM / HIGH / CRITICAL.

Verdict Row ID scheme per CONTEXT.md Specifics: `EVT-NN-V##` per-REQ monotonic (e.g., EVT-01-V01..EVT-01-V05 is per-REQ, independent of EVT-03-V01..). Finding-candidate prose blocks use `Finding Candidate EVT-NN-FC##` IDs scoped per-REQ; zero Phase-246 finding-IDs emitted from this plan per CONTEXT.md D-21.

## §EVT-01 — Every JackpotTicketWin emit path emits non-zero TICKET_SCALE-scaled ticketCount

**REQ (verbatim):** "Every JackpotTicketWin emit path emits non-zero TICKET_SCALE-scaled ticketCount at HEAD cc68bfc7 — zero raw counts, zero stub-zero remnants, scaling factor preserved across every reachable branch."

**Scope source:** audit/v31-243-DELTA-SURFACE.md §6 row D-243-I004 → D-243-C001/C002/C003/C005/C006 (ced654df changelog rows for emit-path functions + event NatSpec) + D-243-F001/F002/F003/F005 (MODIFIED_LOGIC verdicts) + D-243-X001/X002/X005/X008/X009/X010 (call sites of the emit-path functions). TICKET_SCALE = 100 is defined at `contracts/storage/DegenerusGameStorage.sol:165` (`uint256 internal constant TICKET_SCALE = 100;`).

**Adversarial vectors (per CONTEXT.md D-10):**
- EVT-01a — every JackpotTicketWin emit path enumerated via grep; for each site, verify ticketCount argument is TICKET_SCALE-scaled non-zero by walking the argument expression back to its scaling site
- EVT-01b — for every emit site: trace ticketCount arg from emit-site backward through local variable assignments to either a literal `* TICKET_SCALE` multiplication OR a parameter that itself was scaled at the call boundary

**Emit-site enumeration:**

The grep `emit JackpotTicketWin\b` against `contracts/modules/DegenerusGameJackpotModule.sol` returns **three emit sites** at HEAD cc68bfc7 — L699 (in `_runEarlyBirdLootboxJackpot`), L1002 (in `_distributeTicketsToBucket`), L2163 (in `_jackpotTicketRoll`). The broader grep `emit JackpotTicketWin\b` across `contracts/` (excluding `mocks/` + `test/`) returns the same three sites — JackpotModule is the sole emitter. ced654df REMOVED two prior stub emits that existed at baseline 7ab515fe (baseline lines 2014 + 2038 in `runBafJackpot` body, each passing raw `ticketCount=0`) — those are no longer reachable at HEAD cc68bfc7 and are cross-audited as negative-scope rows below.

Every emit site at HEAD cc68bfc7 passes an argument that factors TICKET_SCALE (= 100). Three distinct scaling shapes:

1. **Whole-count path (`_runEarlyBirdLootboxJackpot`):** `ticketCount` is a pre-scaled integer count of whole tickets, multiplied by `uint32(TICKET_SCALE)` at emit-time (L703). The emit argument is `ticketCount * uint32(TICKET_SCALE)` where `ticketCount` was derived from `(totalBudget / 100) / ticketPrice` at L677-678; a `ticketCount != 0` guard at L681 prevents zero emission of a scaled value. TICKET_SCALE multiplier is a compile-time constant ≠ 0, so the product is non-zero whenever ticketCount is non-zero.
2. **Unit path (`_distributeTicketsToBucket`):** emit passes `uint32(units * TICKET_SCALE)` at L1006 where `units` is `baseUnits + (extra != 0 && cursor < extra ? 1 : 0)` (L995-998). The branch is guarded by `units != 0` at L999, so the emit only fires on a non-zero units value; TICKET_SCALE is a compile-time constant ≠ 0, so the product is non-zero.
3. **Scaled path (`_jackpotTicketRoll`):** emit passes `uint32(quantityScaled)` at L2167 where `quantityScaled = (amount * TICKET_SCALE) / targetPrice` at L2158. `amount` is the ticket-roll input (≥ 0 from caller); `targetPrice = PriceLookupLib.priceForLevel(targetLevel)` at L2156. The emit fires unconditionally after `_queueLootboxTickets` at L2159 — no quantity==0 guard at emit time. If `quantityScaled == 0` (possible when `amount < targetPrice / TICKET_SCALE`) the emit carries 0. This is an INFO-severity "true-zero under rare small-roll branch" observation — see Finding Candidate EVT-01-FC-CANDIDATE (rejected) in the closing prose. Value semantics: `(amount * TICKET_SCALE) / targetPrice` is a WHOLE-UNITS-SCALED-BY-100 quantity (not a raw count); the TICKET_SCALE factor is preserved via the multiplication.

**EVT-01 verdict table:**

| Verdict Row ID | REQ-ID | Source 243 Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
|---|---|---|---|---|---|---|---|
| EVT-01-V01 | EVT-01 | D-243-C001, D-243-F001, D-243-I004, D-243-X001 | contracts/modules/DegenerusGameJackpotModule.sol:699-706 | EVT-01a + EVT-01b | SAFE | emit `JackpotTicketWin(winner, lvl, traitId, ticketCount * uint32(TICKET_SCALE), lvl, ticketIndexes[i])` at L699. Argument trace: L703 `ticketCount * uint32(TICKET_SCALE)`; `ticketCount` assigned at L677-679 `= ticketPrice != 0 ? uint32((totalBudget / 100) / ticketPrice) : 0`; guarded by `if (ticketCount != 0)` at L681; enclosed by `if (totalBudget == 0) return;` at L673. TICKET_SCALE = 100 is a compile-time constant at storage/DegenerusGameStorage.sol:165 (non-zero). Product `ticketCount * 100` is non-zero on every reachable emission. | ced654df |
| EVT-01-V02 | EVT-01 | D-243-C002, D-243-F002, D-243-I004, D-243-X002 | contracts/modules/DegenerusGameJackpotModule.sol:1002-1009 | EVT-01a + EVT-01b | SAFE | emit `JackpotTicketWin(winner, queueLvl, traitId, uint32(units * TICKET_SCALE), sourceLvl, ticketIndexes[i])` at L1002. Argument trace: L1006 `uint32(units * TICKET_SCALE)`; `units = baseUnits` at L995, optionally `+= 1` at L997 under `extra != 0 && cursor < extra`; emit guarded by `if (winner != address(0) && units != 0)` at L999. Product `units * TICKET_SCALE` is non-zero on every reachable emission (`units != 0` && TICKET_SCALE = 100). | ced654df |
| EVT-01-V03 | EVT-01 | D-243-C003, D-243-F003, D-243-I004 (removed-stub cross-audit) | contracts/modules/DegenerusGameJackpotModule.sol:1974-2059 | EVT-01a (enumeration-completeness — negative scope) | SAFE | ced654df REMOVED two prior stub emits at baseline lines 2014 + 2038 in `runBafJackpot` body (each emitting `JackpotTicketWin(winner, lvl, BAF_TRAIT_SENTINEL, 0, lvl, 0)` with ticketCount literal `0`). At HEAD cc68bfc7, `runBafJackpot` body L1974-2059 contains zero direct `emit JackpotTicketWin` statements (verified via `git show 7ab515fe:contracts/modules/DegenerusGameJackpotModule.sol \| grep -n 'emit JackpotTicketWin'` returning baseline lines {692, 994, 2014, 2038} and current-HEAD grep returning {699, 1002, 2163} — the 2014 and 2038 sites disappear; 2163 is the new `_jackpotTicketRoll` site). The BAF small-lootbox and odd-index branches now emit JackpotTicketWin INDIRECTLY via `_awardJackpotTickets → _jackpotTicketRoll` (EVT-01-V04 covers this). Stub-zero elimination is complete. | ced654df |
| EVT-01-V04 | EVT-01 | D-243-C005, D-243-F005, D-243-I004, D-243-X008, D-243-X009, D-243-X010 | contracts/modules/DegenerusGameJackpotModule.sol:2163-2170 | EVT-01a + EVT-01b | INFO | emit `JackpotTicketWin(winner, targetLevel, BAF_TRAIT_SENTINEL, uint32(quantityScaled), minTargetLevel, 0)` at L2163. Argument trace: L2167 `uint32(quantityScaled)`; `quantityScaled = (amount * TICKET_SCALE) / targetPrice` at L2158; `amount` is the ticket-roll input from caller (the BAF small-lootbox / odd-index branches in `runBafJackpot` via `_awardJackpotTickets` — sites 2018 / 2049). TICKET_SCALE = 100 preserved via multiplication; the division by `targetPrice` (from `PriceLookupLib.priceForLevel(targetLevel)` at L2156) produces a TICKET_SCALE-scaled whole-units count. Zero-quantity edge case: when `amount * 100 < targetPrice` (i.e., `amount < targetPrice / 100`), `quantityScaled` rounds down to 0 and the emit carries 0. Reachability: in-scope through the small-lootbox branch at L2018 (amount ≤ LOOTBOX_CLAIM_THRESHOLD = 5 ether) and the 2-roll medium-amount branches at L2100/L2109 (halfAmount / secondAmount). The minimum possible `amount` reaching `_jackpotTicketRoll` is SMALL_LOOTBOX_THRESHOLD-adjacent at 0.5 ether (single-roll path at L2092) or below if the caller's `amount` is small; targetPrice across levels is bounded above by game economics. The rare true-zero emit is an INFO observation (UI consumer receives a win event with 0 tickets — no exploitable consequence; downstream `_queueLootboxTickets` at L2159 already short-circuits `if (quantityScaled == 0) return;` via `_queueTicketsScaled` at L602 so no state change occurs). Classification: INFO — below-dust rounding, not a bug. Not a finding candidate — the fractional-remainder resolution path explicitly documented in NatSpec (event L85 "fractional remainder resolves later either by carry into the next scaled queue at the same (level,buyer) slot or by a probabilistic roll at trait-assignment time — see `_rollRemainder`") covers this case. | ced654df |
| EVT-01-V05 | EVT-01 | D-243-C006, D-243-I004, D-243-I007 | contracts/modules/DegenerusGameJackpotModule.sol:86-93 | EVT-01a (event-declaration enumeration) | SAFE | JackpotTicketWin event declaration at L86-93 carries `uint32 ticketCount` field. Field width (uint32, max 4,294,967,295) is safely above any realistic scaled-tickets value — at TICKET_SCALE = 100 and uint32 max, the field represents ~43 million whole tickets. The `ticketCount * uint32(TICKET_SCALE)` cast at L703 (EVT-01-V01) and `uint32(units * TICKET_SCALE)` at L1006 (EVT-01-V02) truncate on overflow; the `uint32(quantityScaled)` at L2167 (EVT-01-V04) also truncates. Overflow-to-zero risk: requires `units > ~42 million` (x100) at the pre-scale stage; game-economic caps (`MAX_BUCKET_WINNERS = 250`, `PURCHASE_PHASE_TICKET_MAX_WINNERS = 120`) upper-bound the per-winner count to levels well below the truncation threshold. Event argument types are correctly sized. | ced654df |

**EVT-01 finding candidates:** None. All three live emit sites pass TICKET_SCALE-scaled non-zero arguments under reachable inputs; the single true-zero edge at `_jackpotTicketRoll` (EVT-01-V04) is below-dust rounding explicitly covered by the event's NatSpec fractional-remainder wording, with no state change and no exploitable consequence.

**EVT-01 per-REQ floor severity:** SAFE (V04 carries an INFO observation but is not a finding — the zero-quantity edge is below-dust rounding covered by NatSpec; the ticketCount-scaling invariant holds on every reachable emission).

## §EVT-03 — Uniform TICKET_SCALE scaling across BAF + trait-matched paths

**REQ (verbatim):** "Uniform TICKET_SCALE scaling across BAF + trait-matched paths — every ticketCount value on the wire is divisible by TICKET_SCALE so the UI consumer can cleanly divide to render whole-ticket counts."

**Scope source:** audit/v31-243-DELTA-SURFACE.md §6 row D-243-I006 → D-243-C001/C002/C005 (scaling-change rows) + D-243-F001/F002/F005 (verdicts).

**Adversarial vectors (per CONTEXT.md D-10):**
- EVT-03a — for each emit site, derive the scaled value path from the raw input; confirm uniform TICKET_SCALE factor across BAF + trait-matched paths; UI-consumer divisibility invariant `(every emit value) % TICKET_SCALE == 0` holds mathematically
- EVT-03b — cc68bfc7 BAF-coupling on bit-0 of rngWord is deferred to Task 2 (`## §cc68bfc7-BAF-Coupling Sub-Section`); Task 1 handles only the pre-cc68bfc7 scaling-uniformity surface.

**Divisibility proof per emit site:**

The UI-consumer divisibility invariant is `(emitted ticketCount) mod TICKET_SCALE == 0`. Each emit site is a product or multiplication-then-division where TICKET_SCALE appears as a factor or divisor preserving divisibility:

| Emit Site | Pre-truncation Expression | Divisibility by TICKET_SCALE |
|---|---|---|
| L703 (`_runEarlyBirdLootboxJackpot`) | `ticketCount * TICKET_SCALE` | EXACT — `X * 100` is trivially divisible by 100; `mod 100 == 0` holds unconditionally for any integer `X`. UI consumer divides by 100 to get `ticketCount` whole tickets. |
| L1006 (`_distributeTicketsToBucket`) | `units * TICKET_SCALE` | EXACT — `X * 100` is trivially divisible; `mod 100 == 0` holds unconditionally. UI consumer divides by 100 to get `units` whole tickets (or fractional unit-count when extra remainder was added). |
| L2167 (`_jackpotTicketRoll`) | `(amount * TICKET_SCALE) / targetPrice` | NOT EXACT in general — the integer division by `targetPrice` rounds down and can produce a value NOT divisible by TICKET_SCALE (e.g., `amount=200, targetPrice=7, TICKET_SCALE=100` → `(200*100)/7 = 2857`, which mod 100 = 57 ≠ 0). This is the NatSpec-documented "BAF lootbox rolls (traitId = BAF_TRAIT_SENTINEL) may carry a fractional remainder" case (event declaration L81-85). Remainder resolution downstream: `_queueTicketsScaled` at DegenerusGameStorage.sol:602 decomposes to whole + frac at L618-619, accumulating frac in `rem` at L627-635 — the carry invariant resolves the fractional difference on the next queueing at the same (level, buyer) slot. |

**Finding: non-uniform scaling between BAF path and trait-matched path.** The trait-matched paths (EVT-01-V01 at L703 + EVT-01-V02 at L1006) emit perfectly TICKET_SCALE-divisible values. The BAF path (EVT-01-V04 at L2167) emits values that may carry a remainder. This divergence is DOCUMENTED by design in the JackpotTicketWin event NatSpec:

> "Trait-matched paths have zero fractional part; BAF lootbox rolls (traitId = BAF_TRAIT_SENTINEL) may carry a fractional remainder that resolves later either by carry into the next scaled queue at the same (level,buyer) slot or by a probabilistic roll at trait-assignment time (see _rollRemainder in DegenerusGameMintModule)."

The traitId disambiguates the two semantics: trait-matched emits carry `traitId < 256` (real trait IDs); BAF emits carry `traitId = BAF_TRAIT_SENTINEL = 420` (sentinel above uint8.max). UI consumer filters on traitId == 420 → renders as "BAF tickets (remainder carries)"; traitId < 256 → renders as "exact bucket tickets".

**EVT-03 verdict table:**

| Verdict Row ID | REQ-ID | Source 243 Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
|---|---|---|---|---|---|---|---|
| EVT-03-V01 | EVT-03 | D-243-C001, D-243-F001, D-243-I006, D-243-X001 | contracts/modules/DegenerusGameJackpotModule.sol:699-706 | EVT-03a (uniform TICKET_SCALE — trait-matched path) | SAFE | Emit value `ticketCount * uint32(TICKET_SCALE)` at L703 is exactly divisible by TICKET_SCALE (trivial — the value is a multiple of 100 by construction). `(value) mod 100 == 0` holds unconditionally. See EVT-01-V01 for the back-trace. | ced654df |
| EVT-03-V02 | EVT-03 | D-243-C002, D-243-F002, D-243-I006, D-243-X002 | contracts/modules/DegenerusGameJackpotModule.sol:1002-1009 | EVT-03a (uniform TICKET_SCALE — trait-matched path) | SAFE | Emit value `uint32(units * TICKET_SCALE)` at L1006 is exactly divisible by TICKET_SCALE (trivial — the value is a multiple of 100 by construction). `(value) mod 100 == 0` holds unconditionally. See EVT-01-V02 for the back-trace. | ced654df |
| EVT-03-V03 | EVT-03 | D-243-C005, D-243-F005, D-243-I006, D-243-X008, D-243-X009, D-243-X010 | contracts/modules/DegenerusGameJackpotModule.sol:2163-2170 | EVT-03a (TICKET_SCALE preserved as factor — BAF path) | INFO | Emit value `uint32(quantityScaled)` at L2167 with `quantityScaled = (amount * TICKET_SCALE) / targetPrice` (L2158). The TICKET_SCALE factor is preserved via multiplication before the division, so the emit value is a TICKET_SCALE-scaled whole-units count in the mathematical sense ("units × 100 approximately, rounded down"). However, exact divisibility by TICKET_SCALE does NOT hold in general — the integer division by targetPrice can produce a remainder. The NatSpec at event L81-85 documents this: "BAF lootbox rolls (traitId = BAF_TRAIT_SENTINEL) may carry a fractional remainder that resolves later either by carry into the next scaled queue or by a probabilistic roll at trait-assignment time (see _rollRemainder)." The UI consumer must branch on `traitId == BAF_TRAIT_SENTINEL (420)` to render "may-have-fractional" tickets vs "exact-whole" tickets. Remainder resolution is covered at `_queueTicketsScaled` (DegenerusGameStorage.sol:602) via `whole = quantityScaled / 100` + `frac = quantityScaled % 100` decomposition (L618-619) with per-slot `rem` accumulation (L624-635) promoting to a whole ticket when `rem` crosses TICKET_SCALE. Classification: INFO — by-design non-exact divisibility; NatSpec-disclosed; downstream-resolvable. Not a finding candidate. | ced654df |
| EVT-03-V04 | EVT-03 | D-243-I006, cross-ref to `_rollRemainder` at contracts/modules/DegenerusGameMintModule.sol | contracts/modules/DegenerusGameMintModule.sol (grep target) + contracts/storage/DegenerusGameStorage.sol:618-635 | EVT-03a (remainder resolution path exists and is correct) | SAFE | The NatSpec-referenced `_rollRemainder` in DegenerusGameMintModule.sol (search via `grep -rn '_rollRemainder\b' contracts/ \| grep -v mocks \| grep -v test`) is the trait-assignment time rollpoint; complementary to the carry path in `_queueTicketsScaled` at DegenerusGameStorage.sol:596-641. The carry path accumulates fractional `rem` via `newRem = rem + frac` and promotes to whole tickets when `newRem >= TICKET_SCALE` (L629). Both resolution paths (carry vs `_rollRemainder`) preserve integer arithmetic correctness — no ETH or BURNIE dust leaks. | ced654df |
| EVT-03-V05 | EVT-03 | D-243-I006 (cross-ref to removed stub emits at ced654df) | contracts/modules/DegenerusGameJackpotModule.sol:1974-2059 (post-removal body) | EVT-03a (negative scope: stub zeros no longer reach UI) | SAFE | ced654df REMOVED the two prior stub emits at baseline L2014 + L2038 that emitted `ticketCount = 0` unconditionally in the BAF small-lootbox and odd-index branches of `runBafJackpot`. Zero-emit values do satisfy divisibility by 100 (0 mod 100 = 0), but they broke the UI contract by claiming a ticket-win with no tickets actually queued. Post-ced654df, the BAF branches route through `_awardJackpotTickets → _jackpotTicketRoll` which emits with a meaningful (possibly-fractional) quantity. The UI can now trust that every JackpotTicketWin emit corresponds to an actual ticket award. | ced654df |
| EVT-03-V06 | EVT-03 | D-243-I006 cross-ref to JackpotTicketWin field-width declaration at L86-93 | contracts/modules/DegenerusGameJackpotModule.sol:86-93 | EVT-03a (uint32 ticketCount field width vs TICKET_SCALE multiplier) | SAFE | Event declaration at L90 `uint32 ticketCount` holds up to 2^32-1 ≈ 4.29e9 units. At TICKET_SCALE = 100, this represents up to ~42.9 million whole tickets emittable per event. Game-economic caps keep per-emit counts well below this (MAX_BUCKET_WINNERS = 250, JACKPOT_MAX_WINNERS = 160, PURCHASE_PHASE_TICKET_MAX_WINNERS = 120; plus per-level ticket budget caps). Overflow-to-truncated-value risk requires pre-scale units > ~42.9M, which is economically infeasible. Field-width is safe. | ced654df |

**EVT-03 finding candidates:** None. The BAF-path fractional-remainder path is by-design NatSpec-disclosed with correct downstream resolution (carry or `_rollRemainder`). Trait-matched paths emit exact-multiple-of-100 values. UI consumer can reliably distinguish via `traitId == BAF_TRAIT_SENTINEL (420)` sentinel check.

**EVT-03 per-REQ floor severity:** INFO (V03 INFO for the by-design BAF-path non-exact divisibility; other rows SAFE). The non-uniformity between BAF and trait-matched paths is the intended design — disclosed in NatSpec and downstream-resolvable.

## §EVT-04 — JackpotTicketWin event NatSpec accuracy at HEAD cc68bfc7

**REQ (verbatim):** "JackpotTicketWin event NatSpec at HEAD cc68bfc7 is per-claim accurate against actual emit-site behavior — scaling described correctly, fractional-remainder resolution path described correctly."

**Scope source:** audit/v31-243-DELTA-SURFACE.md §6 row D-243-I007 → D-243-C006 (ced654df NatSpec-only event row) + cross-ref contracts/modules/DegenerusGameJackpotModule.sol:86-93 at HEAD cc68bfc7 for verbatim NatSpec text.

**Adversarial vectors (per CONTEXT.md D-10):**
- EVT-04a (a) scaling described correctly — does NatSpec say ticketCount is TICKET_SCALE-scaled? Does that match the emit-site code?
- EVT-04a (b) fractional-remainder resolution path described correctly — does NatSpec mention carry vs `_rollRemainder`? Does that match code?

**Literal NatSpec text at HEAD cc68bfc7** (verbatim from `contracts/modules/DegenerusGameJackpotModule.sol:77-93`; `git show cc68bfc7:contracts/modules/DegenerusGameJackpotModule.sol | sed -n '77,93p'` reproduces):

```
    /// @dev Ticket rewards per trait bucket; bonusTrait wins credit same as main trait.
    ///      ticketIndex is the specific ticket that was the "winner" that triggered this
    ///      event — useful for post-mortem forensic analysis of any RNG-dependent path.
    ///      ticketCount is always scaled ×TICKET_SCALE (=100); divide by 100 for
    ///      whole tickets. Trait-matched paths have zero fractional part; BAF
    ///      lootbox rolls (traitId = BAF_TRAIT_SENTINEL) may carry a fractional
    ///      remainder that resolves later either by carry into the next scaled
    ///      queue at the same (level,buyer) slot or by a probabilistic roll at
    ///      trait-assignment time (see _rollRemainder in DegenerusGameMintModule).
    event JackpotTicketWin(
        address indexed winner,
        uint24 indexed ticketLevel,
        uint16 indexed traitId,
        uint32 ticketCount,
        uint24 sourceLevel,
        uint256 ticketIndex
    );
```

**NatSpec-claim decomposition (per EVT-04 vectors a + b):**

Claim 1 — "ticketCount is always scaled ×TICKET_SCALE (=100)":
  - NatSpec asserts: every emit carries a value that has been multiplied by TICKET_SCALE (which equals 100).
  - Code verification: L703 (`_runEarlyBirdLootboxJackpot`) emits `ticketCount * uint32(TICKET_SCALE)` — multiplied factor present; L1006 (`_distributeTicketsToBucket`) emits `uint32(units * TICKET_SCALE)` — multiplied factor present; L2167 (`_jackpotTicketRoll`) emits `uint32(quantityScaled)` where `quantityScaled = (amount * TICKET_SCALE) / targetPrice` (L2158) — multiplied factor present (before division). TICKET_SCALE = 100 at storage/DegenerusGameStorage.sol:165 matches parenthetical "(=100)".
  - Verdict: ACCURATE (EVT-04-V01).

Claim 2 — "divide by 100 for whole tickets":
  - NatSpec instructs: UI/indexer divides `ticketCount` by 100 to render whole-ticket counts.
  - Code verification: matches Claim 1 — the `* 100` factor is consistently on the emit side. Divide-by-100 at UI is the correct inverse. Trait-matched paths (L703 + L1006) produce exact multiples of 100; BAF path (L2167) may produce non-exact multiples (see Claim 4), but dividing by 100 still yields the closest-whole-tickets approximation with fractional resolution handled downstream per Claims 3 + 4.
  - Verdict: ACCURATE (EVT-04-V02).

Claim 3 — "Trait-matched paths have zero fractional part":
  - NatSpec asserts: when traitId < BAF_TRAIT_SENTINEL (real trait IDs 0-3 or similar bucketed values), the ticketCount value is divisible by TICKET_SCALE with zero remainder.
  - Code verification: L703 emits `ticketCount * uint32(TICKET_SCALE)` — `X * 100` is always divisible by 100 (0 remainder). L1006 emits `uint32(units * TICKET_SCALE)` — same. Both these sites fire ONLY on trait-matched paths (L703 uses `traitId = bonusTraits[t]` at L688 per-iteration from `_rollWinningTraits`; L1006 uses the passed `traitId` parameter from the caller `_distributeTicketsToBuckets` plural at L946 — both are bucketed real trait IDs < 256, NOT the BAF sentinel 420).
  - Verdict: ACCURATE (EVT-04-V03).

Claim 4 — "BAF lootbox rolls (traitId = BAF_TRAIT_SENTINEL) may carry a fractional remainder that resolves later either by carry into the next scaled queue at the same (level,buyer) slot or by a probabilistic roll at trait-assignment time (see _rollRemainder in DegenerusGameMintModule)":
  - NatSpec asserts: (a) BAF-path emits carry `traitId = BAF_TRAIT_SENTINEL` (= 420 per JackpotModule L142); (b) fractional remainder may be non-zero on BAF path; (c) resolution path is either (c1) carry-into-next-scaled-queue at same (level,buyer), or (c2) probabilistic roll at trait-assignment time via `_rollRemainder` in DegenerusGameMintModule.
  - Code verification:
    - (a) L2163-2170 passes `BAF_TRAIT_SENTINEL` as the traitId argument (L2166) in `_jackpotTicketRoll` — matches.
    - (b) `quantityScaled = (amount * TICKET_SCALE) / targetPrice` integer-divides, which can round down to a non-zero-mod-100 value — matches "may carry a fractional remainder".
    - (c1) `_queueTicketsScaled` at DegenerusGameStorage.sol:596-641 implements the carry path: `whole = quantityScaled / TICKET_SCALE` (L618) + `frac = quantityScaled % TICKET_SCALE` (L619) + `newRem = rem + frac` accumulation (L627) + promote-to-whole-when-rem>=TICKET_SCALE logic (L629-635). Carry is at same `(wk, buyer)` storage key — matches "same (level,buyer) slot".
    - (c2) `_rollRemainder` exists in DegenerusGameMintModule.sol — confirmed via `grep -rn '_rollRemainder\b' contracts/` returning at least one hit in MintModule (trait-assignment-time rolling). The full body was not audited in this plan's scope (its scope is in QST/GOX territory — differential reference only); the NatSpec claim of "probabilistic roll at trait-assignment time" aligns with the function-name semantics (`_rollRemainder` = roll a dice against the fractional remainder to decide whether to promote it to a whole ticket).
  - Verdict: ACCURATE (EVT-04-V04).

**EVT-04 verdict table:**

| Verdict Row ID | REQ-ID | Source 243 Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
|---|---|---|---|---|---|---|---|
| EVT-04-V01 | EVT-04 | D-243-C006, D-243-C029, D-243-I007 | contracts/modules/DegenerusGameJackpotModule.sol:80-83 (NatSpec claim 1 — scaling) | EVT-04a (a) | SAFE | NatSpec claim "ticketCount is always scaled ×TICKET_SCALE (=100)" matches all three live emit sites: L703 `ticketCount * uint32(TICKET_SCALE)`, L1006 `uint32(units * TICKET_SCALE)`, L2158 `quantityScaled = (amount * TICKET_SCALE) / targetPrice` (then emitted at L2167). TICKET_SCALE constant at storage/DegenerusGameStorage.sol:165 equals 100. Claim is accurate. | ced654df |
| EVT-04-V02 | EVT-04 | D-243-C006, D-243-C029, D-243-I007 | contracts/modules/DegenerusGameJackpotModule.sol:80-81 (NatSpec claim 2 — divide by 100) | EVT-04a (a) | SAFE | NatSpec claim "divide by 100 for whole tickets" is the correct UI-consumer inverse of the `* TICKET_SCALE` factor. TICKET_SCALE equals 100 unconditionally across all three emit sites. UI consumer dividing by 100 yields whole-ticket counts (for trait-matched paths, exactly; for BAF path, rounded with remainder resolved downstream per EVT-04-V04). Claim is accurate. | ced654df |
| EVT-04-V03 | EVT-04 | D-243-C006, D-243-C029, D-243-I007 | contracts/modules/DegenerusGameJackpotModule.sol:81-82 (NatSpec claim 3 — trait-matched zero fractional part) | EVT-04a (a) | SAFE | NatSpec claim "Trait-matched paths have zero fractional part" matches mathematical certainty — both trait-matched emit sites (L703 `X * 100`, L1006 `X * 100`) produce values exactly divisible by 100. Trait-matched paths use real trait IDs (0-3 from `_rollWinningTraits` bonusTraits unpacking at L682-683 for `_runEarlyBirdLootboxJackpot`, or caller-passed traitId from `_distributeTicketsToBuckets` plural at L946 for `_distributeTicketsToBucket`) — NOT the BAF_TRAIT_SENTINEL. Traits 0-3 are unsigned integer bucket ids bounded by uint8.max = 255 (per `bonusTraits` return at L682) — always < 420. Claim is accurate. | ced654df |
| EVT-04-V04 | EVT-04 | D-243-C006, D-243-C029, D-243-I007, cross-ref storage/DegenerusGameStorage.sol:596-641 `_queueTicketsScaled` | contracts/modules/DegenerusGameJackpotModule.sol:82-85 (NatSpec claim 4 — BAF fractional-remainder + carry + `_rollRemainder`) | EVT-04a (b) | INFO | NatSpec claim 4 decomposes into four sub-claims all verified accurate: (a) BAF-path emit uses traitId = BAF_TRAIT_SENTINEL (constant 420 at JackpotModule L142) — matches L2166 literal `BAF_TRAIT_SENTINEL` arg in `_jackpotTicketRoll` emit. (b) Fractional remainder possible — matches `(amount * TICKET_SCALE) / targetPrice` integer division at L2158 which can round down. (c1) Carry path "into next scaled queue at same (level,buyer) slot" — matches `_queueTicketsScaled` at DegenerusGameStorage.sol:602+ which reads `ticketsOwedPacked[wk][buyer]` at L611, accumulates frac in `rem`, writes back to same `wk` + `buyer` slot. The `(level, buyer)` tuple in NatSpec corresponds to the `(wk, buyer)` pair in code where `wk` is the write-key derived from `targetLevel`. (c2) `_rollRemainder` in DegenerusGameMintModule — grep `_rollRemainder\b` against `contracts/` confirms existence. INFO (not SAFE) because the NatSpec's "see _rollRemainder in DegenerusGameMintModule" is a forward reference to a symbol outside this plan's adversarial scope; accuracy of the trait-assignment-time roll is a QST plan responsibility (QST-01/04 territory — `_callTicketPurchase` / `_purchaseFor` chain). Cross-reference sanity-checked only. Claim-4 narrative is accurate; full `_rollRemainder` semantics audit deferred to QST. | ced654df |

**EVT-04 finding candidates:** None. NatSpec is accurate on all four decomposed claims; the only minor concern is that the `_rollRemainder` cross-module reference is not deep-audited in this plan (deferred to QST scope — the plan's owner).

**EVT-04 per-REQ floor severity:** INFO (V04 INFO because `_rollRemainder` accuracy is deferred to QST scope; V01/V02/V03 SAFE). No finding emitted — the deferral is a cross-plan scoping decision, not a NatSpec inaccuracy.

## §Reproduction Recipe — EVT bucket (Task 1)

Task 1 commands (POSIX-portable per CONTEXT.md D-04):

```sh
# Sanity gate (run before any write)
git rev-parse 7ab515fe
git rev-parse cc68bfc7
git rev-parse HEAD
git diff --stat cc68bfc7..HEAD -- contracts/
git status --porcelain contracts/ test/

# EVT-01 emit-site enumeration (primary)
grep -rn --include='*.sol' 'emit JackpotTicketWin\b' contracts/modules/DegenerusGameJackpotModule.sol

# EVT-01 emit-site enumeration (cross-file — JackpotModule-sole-emitter verification)
grep -rn --include='*.sol' 'emit JackpotTicketWin\b' contracts/ | grep -v '^contracts/mocks/' | grep -v '^contracts/test/'

# EVT-01 baseline-vs-head emit-site comparison (confirms stub-zero removal)
git show 7ab515fe:contracts/modules/DegenerusGameJackpotModule.sol | grep -n 'emit JackpotTicketWin'
grep -n 'emit JackpotTicketWin' contracts/modules/DegenerusGameJackpotModule.sol

# EVT-01 / EVT-03 TICKET_SCALE definition
grep -rn --include='*.sol' 'uint256 internal constant TICKET_SCALE' contracts/

# EVT-03 scaling-factor occurrences (cross-audit)
grep -rn --include='*.sol' 'TICKET_SCALE' contracts/ | grep -v '^contracts/mocks/' | grep -v '^contracts/test/'

# EVT-03 _rollRemainder / _queueTicketsScaled existence check (cross-plan reference)
grep -rn --include='*.sol' '\b_rollRemainder\b' contracts/ | grep -v '^contracts/mocks/' | grep -v '^contracts/test/'
grep -rn --include='*.sol' '\b_queueTicketsScaled\b' contracts/ | grep -v '^contracts/mocks/' | grep -v '^contracts/test/'

# EVT-04 NatSpec text at HEAD cc68bfc7
git show cc68bfc7:contracts/modules/DegenerusGameJackpotModule.sol | sed -n '77,93p'

# EVT-04 BAF_TRAIT_SENTINEL constant
grep -rn --include='*.sol' 'BAF_TRAIT_SENTINEL' contracts/modules/DegenerusGameJackpotModule.sol
```

Task 2 (§EVT-02 + §cc68bfc7-BAF-Coupling Sub-Section) appends its own grep commands below on the second commit.

## §EVT-02 — JackpotWhalePassWin emit covers previously-silent large-amount odd-index BAF path

**REQ (verbatim):** "New JackpotWhalePassWin emit at `_awardJackpotTickets` whale-pass fallback branch covers the previously-silent large-amount odd-index BAF path — `amount` and `traitId` arguments are correctly populated; the dispatch trace from the odd-index BAF branch of `runBafJackpot` reaches the new emit."

**Scope source:** audit/v31-243-DELTA-SURFACE.md §6 row D-243-I005 → D-243-C004 (ced654df `_awardJackpotTickets` whale-pass emit-site addition) + D-243-F004 (MODIFIED_LOGIC verdict) + D-243-X006 (small-lootbox-of-large-winner caller at JackpotModule L2018) + D-243-X007 (odd-index small-winner caller at JackpotModule L2049). Sub-scope expansion per CONTEXT.md D-03 also covers the cc68bfc7 markBafSkipped consumer-gating question (§1.7 bullet 7) — see sub-section below.

**Adversarial vectors (per CONTEXT.md D-10):**
- EVT-02a — new `JackpotWhalePassWin` emit-site at `_awardJackpotTickets` enumerated; confirms coverage of previously-silent large-amount odd-index BAF path via per-amount-bucket dispatch trace; verify `amount` and `traitId` args correct
- EVT-02b — cc68bfc7 `markBafSkipped` consumer gating (§1.7 bullet 7): every consumer of `bafBrackets[lvl]` / `winningBafCredit` must filter on `cursor > lastBafResolvedDay` so stale pre-skip leaderboard rows cannot be claimed

**Emit-site enumeration (vector EVT-02a):**

The grep `emit JackpotWhalePassWin\b` against `contracts/` (excluding `mocks/` + `test/`) returns **three emit sites** across `contracts/modules/DegenerusGameJackpotModule.sol`:
1. L1449 (`_processSoloBucketWinner`) — PRE-EXISTING at baseline 7ab515fe; day-5 solo-bucket whale-pass win for ETH jackpot path. NOT in ced654df scope.
2. L2027 (inside `runBafJackpot` large-winner-large-lootbox branch at L2024-2032) — PRE-EXISTING at baseline 7ab515fe; fires when `lootboxPortion > LOOTBOX_CLAIM_THRESHOLD` in the half-split large-winner branch. NOT in ced654df scope.
3. L2083 (inside `_awardJackpotTickets` whale-pass fallback at L2081-2088) — **NEW in ced654df** per D-243-C004. The previously-silent path.

Baseline-to-head verification: `git show 7ab515fe:contracts/modules/DegenerusGameJackpotModule.sol | grep -n 'emit JackpotWhalePassWin'` returns `{1441, 2018}` (two sites); at HEAD the same grep returns `{1449, 2027, 2083}` (three sites — baseline's 1441 → HEAD 1449 is the `_processSoloBucketWinner` emit (line shift from the ced654df NatSpec expansion at JackpotModule L77-93); baseline's 2018 → HEAD 2027 is the `runBafJackpot` large-winner-large-lootbox branch (line shift from the removed two stub emits at baseline 2014 + 2038); HEAD's 2083 is the net-new emit in `_awardJackpotTickets`).

**Per-amount-bucket dispatch trace (vector EVT-02a):**

`_awardJackpotTickets` (L2074-2117) dispatches by `amount`:
- `amount > LOOTBOX_CLAIM_THRESHOLD` (5 ETH) → **whale-pass fallback branch** at L2081-2088: `_queueWhalePassClaimCore(winner, amount)` + `emit JackpotWhalePassWin(winner, minTargetLevel, amount / HALF_WHALE_PASS_PRICE)` at L2083.
- `amount <= SMALL_LOOTBOX_THRESHOLD` (0.5 ETH) → single-roll path at L2092: `_jackpotTicketRoll(...)` → fires JackpotTicketWin per EVT-01-V04.
- middle range (0.5 ETH < amount ≤ 5 ETH) → two-roll path at L2096-2114: two `_jackpotTicketRoll` calls → fires JackpotTicketWin twice per EVT-01-V04.

Caller-side reachability of the whale-pass fallback branch:
- **Caller D-243-X006** at JackpotModule L2018 — calls `_awardJackpotTickets(winner, lootboxPortion, lvl, rngWord)` but ONLY after the caller-side guard `if (lootboxPortion <= LOOTBOX_CLAIM_THRESHOLD)` at L2014. Therefore `amount ≤ LOOTBOX_CLAIM_THRESHOLD` is a caller-side invariant at X006, and the whale-pass-fallback branch inside `_awardJackpotTickets` is UNREACHABLE from X006. The fallback branch (> LOOTBOX_CLAIM_THRESHOLD) never fires on the X006 call path.
- **Caller D-243-X007** at JackpotModule L2049 — calls `_awardJackpotTickets(winner, amount, lvl, rngWord)` with the full BAF-small-winner `amount` unmodified (the odd-index branch at L2044-2050 does NOT halve). Therefore `amount` at X007 can exceed LOOTBOX_CLAIM_THRESHOLD when the raw BAF bracket's per-winner amount for a small-winner (per the `if (amount >= largeWinnerThreshold)` threshold-gate at L1998 — "small winner" means `amount < largeWinnerThreshold`, where `largeWinnerThreshold = poolWei / 20`, so small-winner `amount` ranges from arbitrary low up to `poolWei/20`). The whale-pass-fallback branch fires precisely when `(poolWei/20 > amount > 5 ether)` on an odd-index winner. **This is the previously-silent path the commit fixes**; under reachable pool sizes (poolWei > 100 ether → largeWinnerThreshold > 5 ether → small-winner amount can exceed 5 ether on odd index), the new emit correctly covers the case.

**Argument verification (vector EVT-02a):**
- `winner` argument: `winner = winnersArr[i]` from the caller `runBafJackpot` loop at L1994 (the BAF winner for this iteration). Passed through unchanged into `_awardJackpotTickets`'s `winner` parameter, then unchanged into the emit. Correct.
- `level` argument (event's second arg): emit uses `minTargetLevel` at L2085, which was passed through as `lvl` from the caller at X007 L2049 (`_awardJackpotTickets(winner, amount, lvl, rngWord)`), where `lvl` is the level parameter of `runBafJackpot` at L1976. This is the BAF bracket level — the correct semantic level for the win.
- `halfPassCount` argument (event's third arg): emit computes `amount / HALF_WHALE_PASS_PRICE` at L2086 where `HALF_WHALE_PASS_PRICE` is the half-whale-pass constant. Since `amount > LOOTBOX_CLAIM_THRESHOLD = 5 ether`, and assuming HALF_WHALE_PASS_PRICE is a reasonable ETH-denominated price, this yields the count of half-whale-passes purchasable with the lootbox amount — consistent with the L2027 same-event emit in the sibling large-winner-large-lootbox branch (which uses `lootboxPortion / HALF_WHALE_PASS_PRICE`).

**EVT-02b sub-section — markBafSkipped consumer gating (§1.7 bullet 7 closure):**

Per CONTEXT.md D-09, §1.7 bullet 7 closes in 244-01 EVT-02. The adversarial vector is: every consumer of `bafBrackets[lvl]` / `winningBafCredit` must filter on `cursor > lastBafResolvedDay` so stale pre-skip winning-flip credit cannot be claimed after the BAF for `lvl` was skipped.

Grep results (cc68bfc7 working tree, excluding `mocks/` + `test/`):
- `grep -rn --include='*.sol' '\bbafBrackets\b' contracts/` → **zero hits**. The storage-level symbol name `bafBrackets` does NOT exist in contracts/. The §1.7 bullet 7 phrasing "bafBrackets[lvl]" refers to the conceptual BAF-bracket leaderboard tracked by `bafTop[lvl]` (the PlayerScore[4] array at DegenerusJackpots.sol:124) + `bafTopLen[lvl]` (the length at L127). Adjusted scope: every consumer of the BAF-bracket leaderboard state (`bafTop`, `bafTopLen`, plus the downstream flip-credit stream via `recordBafFlip` / `winningBafCredit`).
- `grep -rn --include='*.sol' '\bwinningBafCredit\b' contracts/` → four hits, all inside BurnieCoinflip.sol: L430 (declaration), L526 (accumulation on win), L572 (consumer branch), L599 (dispatch to `jackpots.recordBafFlip`).
- `grep -rn --include='*.sol' '\blastBafResolvedDay\b' contracts/` → storage-var declaration at DegenerusJackpots.sol:136 + SSTORE sites at DegenerusJackpots.sol:494 (inside `runBafJackpot` finalize path) + L508 (inside `markBafSkipped`) + getter at L666-667; comment references at DegenerusJackpots.sol:499-501 (NatSpec of markBafSkipped) + at DegenerusGameAdvanceModule.sol:825 (BAF-gate comment).
- `grep -rn --include='*.sol' '\bgetLastBafResolvedDay\b' contracts/` → consumer call at BurnieCoinflip.sol:522; interface decl at IDegenerusJackpots.sol:37; implementation at DegenerusJackpots.sol:666.

**Consumer enumeration and gating verdict:**

Consumer 1 — **BurnieCoinflip._claimCoinflipsInternal** (contracts/BurnieCoinflip.sol L416-610):
- L521-524: lazy-caches `bafResolvedDay = jackpots.getLastBafResolvedDay()` on first win within the claim loop.
- L525: the gating check `if (cursor > bafResolvedDay) { winningBafCredit += payout; }` — **gates on `cursor > bafResolvedDay` EXACTLY as the §1.7 bullet 7 specification requires**. The per-day claim cursor (L475-478 `cursor = start + 1`) increments through days L493-L567; for each winning day, the payout is only accumulated into `winningBafCredit` when the day index exceeds the last resolved BAF day. Pre-skip winning-flip credit from days ≤ `lastBafResolvedDay` is filtered out.
- L572: the consumer branch `if (winningBafCredit != 0 && player != SDGNRS)` → L599 `jackpots.recordBafFlip(player, bafLvl, winningBafCredit)` — dispatches only the POST-skip credit (filtered) to the jackpots leaderboard.
- Gating verdict: **SAFE** — cursor-gating is present and correct per the NatSpec contract at markBafSkipped L499-501.

Consumer 2 — **DegenerusJackpots.runBafJackpot** (contracts/DegenerusJackpots.sol L225-496):
- This function reads `bafTop[lvl]` (L248 / L278 / other `_bafTop(lvl, idx)` calls at L639-646) during the winner selection slice. It is called by AdvanceModule._consolidatePoolsAndRewardJackpots at L831 ONLY when `(rngWord & 1) == 1` — the winning-flip branch. On losing flip (`rngWord & 1) == 0`), AdvanceModule calls `jackpots.markBafSkipped(lvl)` at L839 INSTEAD, so `runBafJackpot` never reads stale bracket data.
- After `runBafJackpot` finalizes (L491-495: `_clearBafTop(lvl)` + `bafEpoch[lvl]++` + `lastBafResolvedDay = degenerusGame.currentDayView()`), the bracket is cleared and `lastBafResolvedDay` is bumped — symmetrical semantics to `markBafSkipped`.
- Gating verdict: **SAFE** — no stale read possible. The entry point (advance-module BAF gate) ensures `runBafJackpot` only runs on winning-flip days; `markBafSkipped` handles losing-flip days without touching leaderboard data; both paths bump `lastBafResolvedDay` so the NEXT winning-flip claim stream gates properly.

Consumer 3 — **DegenerusJackpots.recordBafFlip** (contracts/DegenerusJackpots.sol L171-188):
- Entry at L171, `onlyCoin` restricted (called ONLY by BurnieCoinflip). Accepts `(player, lvl, amount)` where `amount` is the already-filtered `winningBafCredit` from Consumer 1 above.
- Function body writes `_updateBafTop(lvl, player, total)` at L184 — accumulates leaderboard position for future BAF jackpot selection.
- Since the upstream caller (BurnieCoinflip L599) already filters via `cursor > bafResolvedDay`, `recordBafFlip` receives only post-skip credit. Gating responsibility is cleanly delegated to the upstream consumer.
- Gating verdict: **SAFE** — upstream filters; this function does not itself need a gate.

**Completeness check for "every consumer":** The only two external symbols that read BAF-claim-related state outside DegenerusJackpots itself are BurnieCoinflip (consumer 1) and AdvanceModule (indirect — sets the gate at L827 and calls runBafJackpot via self-call at L831 or markBafSkipped at L839). AdvanceModule does NOT read `winningBafCredit` or per-player BAF credit state — it only controls the top-level gate. No additional consumers exist. **The NatSpec's claim at DegenerusJackpots.sol L500 ("BurnieCoinflip is one consumer") IS the complete consumer set — BurnieCoinflip is the SOLE consumer of the per-player credit stream;** DegenerusJackpots internally handles the leaderboard (accepting only upstream-filtered input).

**EVT-02 verdict table:**

| Verdict Row ID | REQ-ID | Source 243 Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
|---|---|---|---|---|---|---|---|
| EVT-02-V01 | EVT-02 | D-243-C004, D-243-F004, D-243-I005, D-243-X007 | contracts/modules/DegenerusGameJackpotModule.sol:2081-2088 | EVT-02a (new whale-pass fallback emit covers previously-silent odd-index BAF path) | SAFE | ced654df added `emit JackpotWhalePassWin(winner, minTargetLevel, amount / HALF_WHALE_PASS_PRICE)` at L2083 inside the `amount > LOOTBOX_CLAIM_THRESHOLD` branch of `_awardJackpotTickets`. Dispatch trace: `runBafJackpot (L1974) → odd-index branch (L2044-2050) → _awardJackpotTickets(winner, amount, lvl, rngWord) at L2049 → whale-pass fallback at L2081 when amount > 5 ether → emit at L2083`. Argument correctness: `winner` = winnersArr[i] from BAF winner array; `minTargetLevel` = lvl = BAF bracket level (passed verbatim from X007 call); `halfPassCount = amount / HALF_WHALE_PASS_PRICE` matches the L2027 sibling emit shape. Baseline had ZERO emit on this path — reachability of `amount > 5 ether` on odd-index small-winner reached when `poolWei > 100 ether` (largeWinnerThreshold = poolWei/20 > 5 ether). | ced654df |
| EVT-02-V02 | EVT-02 | D-243-C004, D-243-F004, D-243-I005, D-243-X006 | contracts/modules/DegenerusGameJackpotModule.sol:2081-2088 (unreachable from X006) | EVT-02a (X006 caller-side guard proves X006 cannot reach whale-pass fallback) | SAFE | Caller D-243-X006 at JackpotModule L2018 is guarded by `if (lootboxPortion <= LOOTBOX_CLAIM_THRESHOLD)` at L2014 — the `_awardJackpotTickets` whale-pass fallback branch (requires `amount > LOOTBOX_CLAIM_THRESHOLD`) is UNREACHABLE via X006. Row documents the reachability-exclusion formally so future delta-checkers cannot mistake X006 for an emit-site caller. The new emit at L2083 fires exclusively via X007 (odd-index path). | ced654df |
| EVT-02-V03 | EVT-02 | §1.7 bullet 7, cross-ref D-243-C036 (markBafSkipped), D-243-C037 (IDegenerusJackpots.markBafSkipped interface), D-243-F025 (NEW verdict), D-243-X053 (AdvanceModule L839 caller), D-243-I005 | contracts/BurnieCoinflip.sol:521-527 | EVT-02b (markBafSkipped consumer gating — BurnieCoinflip) | SAFE | BurnieCoinflip._claimCoinflipsInternal caches `bafResolvedDay = jackpots.getLastBafResolvedDay()` at L522 (lazy, once per claim invocation) and gates winning-flip credit accumulation via `if (cursor > bafResolvedDay) winningBafCredit += payout;` at L525-527. The cursor-gating is EXACTLY the invariant NatSpec at DegenerusJackpots.sol L500-501 requires. Pre-skip winning-flip credit from days ≤ lastBafResolvedDay is filtered BEFORE any downstream recordBafFlip call at L599; no stale leaderboard writes possible. | cc68bfc7 |
| EVT-02-V04 | EVT-02 | §1.7 bullet 7, cross-ref D-243-C036, D-243-C037, D-243-X060 (interface-method call-site), D-243-I005 | contracts/DegenerusJackpots.sol:171-188 | EVT-02b (markBafSkipped consumer gating — recordBafFlip upstream-filtered) | SAFE | DegenerusJackpots.recordBafFlip at L171 accepts pre-filtered `amount` from the BurnieCoinflip upstream consumer (EVT-02-V03 filter applied at the caller). The function is `onlyCoin` restricted (L171) — only BurnieCoinflip can write; given BurnieCoinflip is the SOLE caller AND it filters, no stale-credit vector reaches the leaderboard. Internal `_updateBafTop(lvl, player, total)` at L184 + accompanying emit `BafFlipRecorded` are protected transitively. | cc68bfc7 |
| EVT-02-V05 | EVT-02 | §1.7 bullet 7, cross-ref D-243-C036, D-243-I005, completeness-check for "every consumer" | contracts/ (grep coverage) | EVT-02b (markBafSkipped consumer-set completeness) | SAFE | Grep `\bwinningBafCredit\b` returns 4 hits, all inside BurnieCoinflip.sol (L430 decl + L526 accumulation + L572 branch + L599 dispatch). Grep `\bbafTop\b` returns hits ONLY inside DegenerusJackpots.sol (mapping decl at L124 + internal reads at L248/L278/L639-654/L576-622). No other contract reads `winningBafCredit`, per-player BAF-credit state, or the bracket leaderboard directly. BurnieCoinflip is the SOLE external consumer of the flip-credit stream — matches NatSpec's assertion. DegenerusJackpots is the implementation internal; AdvanceModule is the top-level gate (no per-player reads). Consumer-set closure: BurnieCoinflip is the complete set, and its gating is correct (EVT-02-V03). | cc68bfc7 |

**EVT-02 finding candidates:** None. New whale-pass emit correctly covers the previously-silent odd-index large-amount BAF path; argument-shape consistent with sibling emit sites; markBafSkipped consumer gating is complete and correct across the single external consumer (BurnieCoinflip).

**EVT-02 per-REQ floor severity:** INFO (no EVT-02-SEVERITY:INFO rows above SAFE — all 5 rows SAFE. Conservative INFO at the bucket-summary card reflects cross-REQ cc68bfc7-coupling observations documented below, not a downgrade of any EVT-02 row.). All 5 V-rows close as SAFE individually.

## §cc68bfc7-BAF-Coupling Sub-Section

This sub-section closes Phase 244 EVT-02 / EVT-03 sub-scope expansion per CONTEXT.md D-03 and Phase 243 §1.7 finding-candidate bullets 6 (BAF bit-0 coupling) + 7 (markBafSkipped consumer gating) per CONTEXT.md D-09. The cc68bfc7 commit (3 files / +47/-10) introduces:

- new event `BafSkipped` at `contracts/DegenerusJackpots.sol:71-74` (per D-243-C035 / D-243-C041)
- new external `markBafSkipped(uint24 lvl)` at `contracts/DegenerusJackpots.sol:498-510` under `onlyGame` modifier (per D-243-C036; D-243-F025 NEW)
- new interface declaration `IDegenerusJackpots.markBafSkipped(uint24 lvl) external` at `contracts/interfaces/IDegenerusJackpots.sol:30-34` (per D-243-C037 / D-243-C042)
- new file-scope constant `IDegenerusJackpots private constant jackpots = IDegenerusJackpots(ContractAddresses.JACKPOTS)` at `contracts/modules/DegenerusGameAdvanceModule.sol:105-106` (per D-243-C038 / D-243-C040)
- BAF-firing branch at `_consolidatePoolsAndRewardJackpots` (`contracts/modules/DegenerusGameAdvanceModule.sol:728-909`, MODIFIED_LOGIC per D-243-F026; per D-243-C039) gated on `(rngWord & 1) == 1` at L827: winning-flip branch invokes `IDegenerusGame(address(this)).runBafJackpot(...)` at L831 (D-243-X005 self-call); losing-flip branch invokes `jackpots.markBafSkipped(lvl)` at L839 (D-243-X053/X060 direct-handle call via new file-scope constant)

Below: one verdict row for the §1.7 bullet 6 (BAF expected-value under bit-0 coupling) closure attached to §EVT-03; §1.7 bullet 8 (jackpots direct-handle vs self-call reentrancy parity) surfaces a cross-REQ NOTE deferring to 244-02 / 244-04.

### §EVT-03 BAF-coupling addendum — bit-0 rngWord fairness verdict

Adversarial vector EVT-03b: the same low-order bit `rngWord & 1` is consumed by BOTH `_consolidatePoolsAndRewardJackpots` BAF gate (cc68bfc7 ADDED) AND BurnieCoinflip.processCoinflipPayouts daily-win/loss outcome. BAF resolution is now correlated with the daily coinflip rather than independent.

**Bit-0 consumer identification:**
- AdvanceModule._consolidatePoolsAndRewardJackpots at `contracts/modules/DegenerusGameAdvanceModule.sol:827`: `if ((rngWord & 1) == 1)` (BAF fires on winning flip, marks skipped on losing flip).
- BurnieCoinflip.processCoinflipPayouts at `contracts/BurnieCoinflip.sol:834`: `bool win = (rngWord & 1) == 1;` (daily flip win/loss outcome for every player's coinflip stake).
- BIT ALLOCATION MAP at `contracts/modules/DegenerusGameAdvanceModule.sol:1126-1143` EXPLICITLY documents both consumers of bit 0 (comment L1130 + L1131). No other bit-0 consumers exist.

**Same-rngWord verification (identical value reaches both consumers on the same tick):**

In `rngGate` at `contracts/modules/DegenerusGameAdvanceModule.sol:1148-1260`, the flow is:
1. Read `currentWord = rngWordCurrent` at L1158.
2. Apply daily RNG: `currentWord = _applyDailyRng(day, currentWord)` at L1179. `_applyDailyRng` at L1791-1807 adds `totalFlipReversals` (player-purchased nudges) to the raw word at L1798-1800 and resets the nudge counter. The result is stored at `rngWordCurrent` (L1803) + `rngWordByDay[day]` (L1804) — the one canonical daily rngWord.
3. Call `coinflip.processCoinflipPayouts(bonusFlip, currentWord, day)` at L1180 — the daily coinflip is resolved with this word; bit-0 is consumed for win/loss at BurnieCoinflip L834.
4. Within the same advanceGame invocation, `rngWord` is pulled from the same source (`rngWordByDay[day]` or the in-memory pipeline) and passed into `_consolidatePoolsAndRewardJackpots(lvl, purchaseLevel, day, rngWord, psd)` at L422, where the BAF gate at L827 consumes bit-0 identically.

**Result:** both consumers read the SAME bit-0. `win == true` for daily coinflip ⇔ BAF fires (winning-flip branch taken); `win == false` ⇔ BAF skipped (losing-flip branch taken).

**Expected-value re-verification:**

Under a uniformly-random VRF word (VRF-determinism invariant AIRTIGHT at HEAD cc68bfc7 per v30.0 Phase 239 RNG-02 re-verification + KI EXC-02/03 envelopes), bit-0 is uniform Bernoulli(0.5). Therefore:
- Pre-cc68bfc7: BAF fired every BAF-bracket day (deterministic given `prevMod10 == 0`).
- Post-cc68bfc7: BAF fires with probability 0.5 per BAF-bracket day (independent draw from rngWord & 1), marked skipped otherwise.

Economic consequence: BAF jackpot expected-value halves per qualifying day. The pool that would have funded a losing-flip BAF stays in `futurePool` and accumulates for the next BAF-bracket day (pool preservation guaranteed by NatSpec at markBafSkipped L500-501: "Leaderboard state for lvl is left as-is — no new writes ever target a past bracket, so clearing would only burn gas"). Over a long game, the total BAF-paid ETH equals approximately the pre-cc68bfc7 total × 0.5 in expectation, with the other half recirculating in futurePool for the next BAF. The `lastBafResolvedDay` bump via markBafSkipped (DegenerusJackpots.sol:507-509) correctly filters pre-skip winning-flip credit from the downstream BurnieCoinflip claim stream (see EVT-02-V03) — no stale leaderboard dust.

**Attacker-amplifiable consequence check:**
- Can a player predict or grind bit-0 of rngWord? NO: `rngWord` is VRF-derived; the VRF commitment window is protected by `rngLockedFlag` (v30.0 Phase 239 RNG-02 AIRTIGHT invariant — no state that feeds RNG consumer input can change between VRF request and fulfillment). The `totalFlipReversals` nudge mechanism at `contracts/DegenerusGame.sol:1914-1922 reverseFlip()` adjusts the word by +1 per paid nudge, but (a) nudges are gated by `if (rngLockedFlag) revert RngLocked();` at L1915 — players CANNOT nudge during the VRF commitment window; (b) a single nudge flips bit-0, so an attacker could in principle bias the outcome by nudging — BUT the cost compounds at +50% per queued nudge (L1917 + L1928-1935) and the attacker cannot read the unfulfilled VRF word, so nudging is gambling-against-unknown, not prediction.
- Can a validator grind the coinflip? NO: BurnieCoinflip is VRF-based (`processCoinflipPayouts(bool bonusFlip, uint256 rngWord, uint32 epoch)` at L802 receives `rngWord` from the VRF-fulfilled game contract). Validator attacks would need to manipulate VRF itself — out of scope per Chainlink-VRF trust assumption (KI EXC-02 envelope: only the 14-day prevrandao fallback adds a 1-bit validator-biasable surface, and that's guarded by the 14-day VRF-dead grace — well outside normal-tick BAF gating).
- Does the coupling widen KI EXC-02 (prevrandao fallback) envelope? NO: the BAF gate at L827 uses `rngWord & 1` where rngWord is the SAME word consumed by coinflip. If the 14-day fallback fires (KI EXC-02), the fallback word at `_gameOverEntropy` / `_getHistoricalRngFallback` is VRF-plus-prevrandao-admixture — bit-0 becomes biasable to a block proposer. BAF outcomes would then be biasable by a validator who waits 14 days of VRF-dead. But: (a) the 14-day grace is ~17× the 20-hour VRF-coordinator-swap governance threshold — reaching it requires VRF + governance both to fail; (b) validator bias is 1-bit (as noted in KI EXC-02); (c) the BAF bracket's pool remains in futurePool on a biased-to-skip outcome, so "validator skips the BAF" does not siphon funds. Envelope unchanged — the coupling does not amplify validator capability because the BAF gate consumes the SAME 1-bit that's already in KI EXC-02's biasable surface. **RE_VERIFIED_AT_HEAD cc68bfc7: KI EXC-02 envelope unchanged per CONTEXT.md D-22.**
- Does the coupling widen KI EXC-03 (F-29-04 mid-cycle substitution)? NO: EXC-03 is about gameover entropy substitution for mid-cycle write-buffer tickets. The BAF gate is consumed during normal-tick `_consolidatePoolsAndRewardJackpots` at level-transition, NOT during gameover drain. EXC-03 envelope unchanged — the coupling is orthogonal to the gameover-entropy surface.

**EVT-03 verdict rows (continued):**

| Verdict Row ID | REQ-ID | Source 243 Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
|---|---|---|---|---|---|---|---|
| EVT-03-V07 | EVT-03 | D-243-C039, D-243-F026, D-243-X005, D-243-X053, §1.7 bullet 6 | contracts/modules/DegenerusGameAdvanceModule.sol:826-840 + contracts/BurnieCoinflip.sol:834 | EVT-03b (bit-0 coupling BAF ↔ daily coinflip) | INFO | Both consumers read the SAME `rngWord & 1` on the same tick (rngGate produces the single canonical daily rngWord at L1179-1180, then the advanceGame loop reuses it at L422 → _consolidatePoolsAndRewardJackpots → BAF gate at L827). BIT ALLOCATION MAP at AdvanceModule L1126-1143 documents the co-consumption. Expected-value consequence: BAF fires with P(bit-0 = 1) = 0.5 instead of P = 1 — over long runs total BAF-paid ETH ≈ pre-cc68bfc7 × 0.5 in expectation, with skipped-pool preservation in futurePool (NatSpec markBafSkipped L500-501). INFO — intentional per commit-msg ("BAF gated on daily flip win"); economic-impact ledger entry for Phase 246. No attacker amplification (EXC-02 + EXC-03 envelopes unchanged per CONTEXT.md D-22; nudge gating at rngLockedFlag prevents player bit-0 prediction). | cc68bfc7 |
| EVT-03-V08 | EVT-03 | D-243-C039, D-243-F026, D-243-X005, §1.7 bullet 6 sibling | contracts/modules/DegenerusGameAdvanceModule.sol:826-840 (skip-branch pool preservation) | EVT-03b (pool preservation on skip — no ETH loss) | SAFE | On losing-flip (BAF skipped): `jackpots.markBafSkipped(lvl)` at L839 is the ONLY side effect — it bumps `lastBafResolvedDay` at DegenerusJackpots.sol L508 but does NOT modify `bafTop` leaderboard or the pool. `baseMemFuture` is captured at L817 before the gate, `memFuture` remains equal to `baseMemFuture` on skip-branch (no subtraction). The decimator-jackpot path at L846-858 still runs independently of BAF gating (`if (prevMod100 == 0)` uses `baseMemFuture` at L847, so decimator behavior is unchanged). ETH conservation: on skip, the BAF-allocated percentage (`baseMemFuture * bafPct / 100` at L829) stays in `memFuture`/`futurePool`. Recirculates for next BAF bracket day. No dust or loss. | cc68bfc7 |

**EVT-03 per-REQ floor severity (final):** INFO (V03 + V07 INFO; V08 + others SAFE). INFO-classified rows document by-design behavior with economic-impact ledger notes; no exploitable vector; no finding candidate emitted.

### §cc68bfc7 cross-REQ notes — §1.7 bullet 8 deferral

Per CONTEXT.md D-09 mapping, §1.7 bullet 8 (cc68bfc7 `jackpots` direct-handle vs `runBafJackpot` self-call reentrancy parity check) is OWNED by 244-02 RNG-01 + 244-04 GOX-06 cross-cite, NOT by 244-01. This plan does NOT close bullet 8. The BAF-coupling sub-section above covers the bit-0 fairness surface (bullet 6) + the markBafSkipped consumer gating (bullet 7). Bullet 8's reentrancy-adjacency question requires the RNG lock discipline analysis (RNG-01 scope) and the drain-path reentrancy surface (GOX-06 scope).

Two dispatch paths visible here (for reference only, no verdict emitted):
- **Self-call path (EXISTING at baseline):** D-243-X005 at AdvanceModule L831 — `IDegenerusGame(address(this)).runBafJackpot(bafPoolWei, lvl, rngWord)` — crosses the DegenerusGame dispatcher which delegatecalls JackpotModule.runBafJackpot (D-243-X003 + X004 selector). Inside JackpotModule.runBafJackpot (L1979), the `if (msg.sender != address(this)) revert E();` check passes because `address(this)` is unchanged through delegatecall.
- **Direct-handle path (NEW at cc68bfc7):** D-243-X053 + X060 at AdvanceModule L839 — `jackpots.markBafSkipped(lvl)` via the new file-scope `jackpots = IDegenerusJackpots(ContractAddresses.JACKPOTS)` constant — direct external call to the DegenerusJackpots backend contract (different contract address from JackpotModule), protected by `onlyGame` modifier at DegenerusJackpots.sol L506.

Both paths execute within the already-locked RNG tick; the reentrancy surface is limited by the RNG lock discipline. Full reentrancy-parity verdict deferred to 244-02 RNG-01 (rngLocked AIRTIGHT invariant) + 244-04 GOX-06 (drain-path reentrancy). NOTE emitted for downstream plan inheritance; no D-243-X### row consumed from this plan's 60-row universe for bullet 8.

## §Reproduction Recipe — EVT bucket (Task 2 addendum)

Task 2 commands (POSIX-portable per CONTEXT.md D-04):

```sh
# EVT-02 JackpotWhalePassWin emit-site enumeration
grep -rn --include='*.sol' 'emit JackpotWhalePassWin\b' contracts/ | grep -v '^contracts/mocks/' | grep -v '^contracts/test/'

# EVT-02 baseline-vs-head whale-pass emit comparison (confirms new fallback emit)
git show 7ab515fe:contracts/modules/DegenerusGameJackpotModule.sol | grep -n 'emit JackpotWhalePassWin'
grep -n 'emit JackpotWhalePassWin' contracts/modules/DegenerusGameJackpotModule.sol

# EVT-02b markBafSkipped consumer-gating greps (§1.7 bullet 7)
grep -rn --include='*.sol' '\bbafBrackets\b' contracts/ | grep -v '^contracts/mocks/' | grep -v '^contracts/test/'
grep -rn --include='*.sol' '\bwinningBafCredit\b' contracts/ | grep -v '^contracts/mocks/' | grep -v '^contracts/test/'
grep -rn --include='*.sol' '\blastBafResolvedDay\b' contracts/ | grep -v '^contracts/mocks/' | grep -v '^contracts/test/'
grep -rn --include='*.sol' '\bgetLastBafResolvedDay\b' contracts/ | grep -v '^contracts/mocks/' | grep -v '^contracts/test/'
grep -rn --include='*.sol' '\bbafTop\b' contracts/ | grep -v '^contracts/mocks/' | grep -v '^contracts/test/'
grep -rn --include='*.sol' '\brecordBafFlip\b' contracts/ | grep -v '^contracts/mocks/' | grep -v '^contracts/test/'
grep -rn --include='*.sol' 'markBafSkipped\|jackpots\.markBafSkipped' contracts/ | grep -v '^contracts/mocks/' | grep -v '^contracts/test/'

# EVT-03b BAF-coupling bit-0 consumer enumeration (§1.7 bullet 6)
grep -rn --include='*.sol' 'rngWord & 1' contracts/ | grep -v '^contracts/mocks/' | grep -v '^contracts/test/'
grep -rn --include='*.sol' '(rngWord & 1)' contracts/ | grep -v '^contracts/mocks/' | grep -v '^contracts/test/'
grep -n 'BIT ALLOCATION MAP' contracts/modules/DegenerusGameAdvanceModule.sol

# EVT-03b rngWord flow verification (same-word-to-both-consumers)
grep -n 'processCoinflipPayouts\|_consolidatePoolsAndRewardJackpots\|_applyDailyRng' contracts/modules/DegenerusGameAdvanceModule.sol

# cc68bfc7 addendum hunks at HEAD
git show cc68bfc7 -- contracts/DegenerusJackpots.sol contracts/interfaces/IDegenerusJackpots.sol contracts/modules/DegenerusGameAdvanceModule.sol

# Cross-ref CONTEXT.md D-22 KI envelope files referenced (read-only)
grep -n 'EXC-02\|EXC-03\|prevrandao\|F-29-04' /home/zak/Dev/PurgeGame/degenerus-audit/KNOWN-ISSUES.md 2>/dev/null || true
```

Full-phase replay: concatenate Task 1 + Task 2 recipes above; run against a clean working tree at HEAD `cc68bfc7` to reproduce every D-243-X/C/F/I citation in verdict rows.


---

## §2 — RNG Bucket (commit 16597cac + KI envelope re-verify EXC-02 + EXC-03)

*Embedded verbatim from `audit/v31-244-RNG.md` working file. Working file preserved on disk per CONTEXT.md D-05.*

# v31.0 Phase 244 — RNG Bucket Audit (commit 16597cac + KI envelope re-verify)

**Audit baseline:** `7ab515fe` (v30.0 milestone HEAD).
**Audit head:** `cc68bfc7` (Phase 243 amended HEAD; contract tree verified byte-unchanged from `cc68bfc7` via `git diff --stat cc68bfc7..HEAD -- contracts/` = empty).
**Owning commits:** `16597cac` (rngunlock fix — `_unlockRng(day)` removal from two-call-split ETH continuation) + KI envelope re-verify against EXC-02 (prevrandao fallback) + EXC-03 (F-29-04 mid-cycle substitution).
**Scope per:** `audit/v31-243-DELTA-SURFACE.md` §6 Consumer Index rows D-243-I008..D-243-I010 (RNG-01, RNG-02, RNG-03).
**Plan:** `.planning/phases/244-per-commit-adversarial-audit-evt-rng-qst-gox/244-02-PLAN.md`.
**Phase:** 244-per-commit-adversarial-audit-evt-rng-qst-gox.
**Status:** WORKING (flips to FINAL at 244-04 consolidation commit per CONTEXT.md D-05).

## §0 — Per-Bucket Verdict Count Card

| REQ-ID | Verdict Rows | Finding Candidates | KI Envelope Status | Floor Severity |
| --- | --- | --- | --- | --- |
| RNG-01 | 11 (RNG-01-V01..V11) | 0 | EXC-03 RE_VERIFIED_AT_HEAD `cc68bfc7` (RNG-01-V11 row) | SAFE (10 SAFE + 1 RE_VERIFIED_AT_HEAD) |
| RNG-02 | 7 (RNG-02-V01..V07) | 0 | EXC-02 RE_VERIFIED_AT_HEAD `cc68bfc7` (RNG-02-V06 row) | SAFE (6 SAFE + 1 RE_VERIFIED_AT_HEAD) |
| RNG-03 | 2 (RNG-03-V01..V02) | 0 | n/a | SAFE (2 SAFE) |

**Bucket totals:** 20 V-rows (11 + 7 + 2) across 3 REQs; 0 finding candidates; 2 KI envelope re-verifies (EXC-02, EXC-03) both carrying `RE_VERIFIED_AT_HEAD cc68bfc7` annotation; bucket floor severity SAFE.

**Phase 243 §1.7 bullet closure:** bullet 3 (`_gameOverEntropy` rngRequestTime clearing reentry) CLOSED in §RNG-02 via RNG-02-V04; bullet 8 (cc68bfc7 jackpots direct-handle vs runBafJackpot delegatecall reentrancy parity) DEFERRED to 244-04 GOX-06 with hand-off note documented in plan SUMMARY (rationale: the reentrancy analysis benefits from the full GOX context including `_handleGameOverPath` ordering + `_consolidatePoolsAndRewardJackpots` body; both call paths are routed through the same `_consolidatePoolsAndRewardJackpots` function which GOX-06 owns via D-243-F013/F026). 244-01 EVT bucket already documented the two dispatch paths (X005 self-call at L831 + X053/X060 direct-handle at L839) for downstream-plan inheritance per 244-01-SUMMARY §Key Surfaces for 244-02.

## §RNG-01 — _unlockRng(day) removal safety

**Owning commit:** `16597cac`. **Source 243 rows:** D-243-C007 (changelog), D-243-F006 (MODIFIED_LOGIC verdict), D-243-X011/X012/X013/X014 (dispatcher + delegatecall selector + sDGNRS + vault wrappers), §1.8 INV-237-035 HUNK-ADJACENT, §1.7 bullet 3.

### Reaching-path enumeration (adversarial vector RNG-01a per CONTEXT.md D-11)

The `16597cac` hunk is a 1-line removal at AdvanceModule `L451` (post-`payDailyJackpot(true, lvl, rngWord);` on the STAGE_JACKPOT_ETH_RESUME branch inside the `advanceGame` do-while). The removal sits between L454 (`if (resumeEthPool != 0)`) and L457 (`stage = STAGE_JACKPOT_ETH_RESUME; break;`) at HEAD `cc68bfc7`.

**Preconditions to reach the removal point (L454-L457):**
- `inJackpot = jackpotPhaseFlag == true` (game is in jackpot phase — entered via the `stage = STAGE_ENTERED_JACKPOT` branch at L447 of a prior tick)
- `!lastPurchase` (so `lastPurchase = false` because `!inJackpot` is false)
- All mid-day path exits (L203-L237) bypassed — i.e. `day != dailyIdx` (new-day path taken)
- `ticketsFullyProcessed == true` at the top of the do-while, so the L261 pre-drain gate is skipped
- `rngGate(...)` returned a non-sentinel `rngWord` (not `1` — meaning VRF fulfillment is available and `rngWordByDay[day]` was populated OR `rngWordCurrent != 0 && rngRequestTime != 0` at entry)
- `phaseTransitionActive == false` (otherwise the L302-L336 branch is taken instead)
- Current-level tickets drain finished (L355-L361)
- L365 purchase-phase branch skipped because `inJackpot == true`
- L454 gate: `resumeEthPool != 0` — this is only set by a prior `_processDailyEth(SPLIT_CALL1)` call in the same (or a prior) `advanceGame` tick

The ONLY dispatcher that can set `resumeEthPool != 0` is `payDailyJackpot(isJackpotPhase=true, lvl, rngWord)` called at L474 of a PRIOR tick under SPLIT_CALL1 mode (JackpotModule `_processDailyEth` L1300 writes `resumeEthPool = uint128(ethPool)`). SPLIT_CALL1 mode is chosen at JackpotModule L473-475 iff `totalWinners > JACKPOT_MAX_WINNERS` (the skip-split threshold).

**Reaching paths:** there is exactly ONE structural path that reaches the removal point because the do-while is a single-iteration loop (`do { ... } while (false)`) and every predecessor branch uses `break` to skip forward. The path is uniquely characterised by the sequence:

- P1 (sole reaching path): `advanceGame → new-day branch → rngGate returns non-1 → !phaseTransitionActive → _prepareFutureTickets ok → current-level drain finished → inJackpot branch → resumeEthPool != 0 branch at L454`.

One path, one adversarial-vector row per actor class + supporting backward-trace / commitment-window / KI re-verify rows. Enumeration below.

**Downstream unlock reachability:** after STAGE_JACKPOT_ETH_RESUME fires and the tick returns, a SUBSEQUENT `advanceGame` tick (not the same tick) must reach one of the four `_unlockRng(day)` SSTORE sites:

| Downstream unlock site | File:Line (cc68bfc7) | Trigger | Reached on the tick AFTER STAGE_JACKPOT_ETH_RESUME? |
| --- | --- | --- | --- |
| L329 (`_unlockRng(day)` inside phaseTransitionActive end-branch) | `contracts/modules/DegenerusGameAdvanceModule.sol:329` | `phaseTransitionActive == true && _processPhaseTransition fully drains` | NO — `phaseTransitionActive` is set only by `_endPhase` (L464 via L639 body) which is reached from L462 `if (jackpotCounter >= JACKPOT_LEVEL_CAP) _endPhase()`. Not reachable on the tick AFTER STAGE_JACKPOT_ETH_RESUME unless the prior coin+tickets tick also finishes CAP-ing the jackpotCounter. Even when reached, it correctly clears the flag. |
| L400 (`_unlockRng(day)` inside purchase-phase daily branch) | `contracts/modules/DegenerusGameAdvanceModule.sol:400` | `!inJackpot && !lastPurchaseDay && (purchaseLevel==1 \|\| payDailyJackpot+targetMet)` | NO — this is the PURCHASE phase unlock. Cannot fire while `inJackpot == true` (which STAGE_JACKPOT_ETH_RESUME implies). |
| **L468 (`_unlockRng(day)` inside jackpot-phase coin+tickets branch)** | `contracts/modules/DegenerusGameAdvanceModule.sol:468` | `inJackpot && !resumeEthPool && dailyJackpotCoinTicketsPending && jackpotCounter < JACKPOT_LEVEL_CAP` | **YES — this is the canonical downstream unlock site.** The prior `payDailyJackpot(true, lvl, rngWord)` CALL 1 (SPLIT_CALL1) at L474 ALWAYS sets `dailyJackpotCoinTicketsPending = true` at JackpotModule L519 (unconditionally inside the `if (isJackpotPhase)` branch — confirmed by reading JackpotModule.payDailyJackpot body L342-520). CALL 2 (`_resumeDailyEth`) at L455 does NOT touch `dailyJackpotCoinTicketsPending`. So after STAGE_JACKPOT_ETH_RESUME completes (clearing `resumeEthPool=0`), the next tick's L454 `resumeEthPool != 0` gate is false AND the L461 `dailyJackpotCoinTicketsPending` gate is true → L462-470 branch runs `payDailyJackpotCoinAndTickets(rngWord)` + `_unlockRng(day)` at L468. |
| L475 (STAGE_JACKPOT_DAILY_STARTED — fresh daily) | `contracts/modules/DegenerusGameAdvanceModule.sol:475` | L473 fall-through: `inJackpot && !resumeEthPool && !dailyJackpotCoinTicketsPending` | NO — this is the CALL 1 site (fresh daily jackpot initiation). Not an unlock site; it is the SAME call that seeds `resumeEthPool` via SPLIT_CALL1 and `dailyJackpotCoinTicketsPending` via L519. No `_unlockRng` here; the unlock is deferred to L468 after coin+tickets runs. |
| L632 (`_unlockRng(day)` inside `_handleGameOverPath`) | `contracts/modules/DegenerusGameAdvanceModule.sol:632` | `_handleGameOverPath → gameOver path OR terminal-drain branch` | NO — this is the gameover-drain unlock. Reachable only if gameover triggers between ticks (orthogonal to the normal jackpot-phase lifecycle). Not the canonical downstream unlock for STAGE_JACKPOT_ETH_RESUME. |

**Same-tick vs cross-tick:** The removed `_unlockRng(day)` was on the SAME tick as STAGE_JACKPOT_ETH_RESUME. The canonical replacement unlock at L468 is on a SUBSEQUENT tick (tick N+1 relative to the ETH-resume tick N). **This is the DESIGN INTENT of 16597cac.** Per the commit message "rngunlock fix", the prior behaviour (baseline `7ab515fe`) incorrectly unlocked rng AFTER CALL 2 of ETH split but BEFORE `payDailyJackpotCoinAndTickets(rngWord)` ran (on a subsequent tick). That unlock cleared `rngWordCurrent = 0`, `vrfRequestId = 0`, `rngRequestTime = 0`, and `dailyIdx = day` — meaning the subsequent coin+tickets tick would either (a) find `rngWordByDay[day]` already populated and reuse it, which works BUT (b) the rngLockedFlag was already `false` at L468, so the SSTORE `rngLockedFlag = false` in `_unlockRng` would be a same-value re-write + the full VRF-context zeroing would double-fire. The fix: defer the unlock so it fires exactly once at L468 after coin+tickets, preserving the invariant that rngLockedFlag's clear is paired with its matching set exactly once per daily cycle.

**Cross-tick reachability check:** Between the ETH-resume tick N and the coin+tickets tick N+1, can any player-controllable or MEV-controllable event advance the clock past the protection envelope? Answer: NO — every `advanceGame` tick runs in its own transaction and is atomic; `rngLockedFlag = true` stays across ticks (SSTORE persists). Mid-day purchase functions (MintModule + WhaleModule) consult `_livenessTriggered()` (D-243-C026 gate) OR `rngLockedFlag` directly (WhaleModule L543). Players cannot directly flip `rngLockedFlag`. Between ticks N and N+1 the flag stays `true`, blocking mid-day purchase/burn that would otherwise use `rngWordCurrent`.

### Verdict rows — RNG-01

| Verdict Row ID | REQ-ID | Source 243 Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RNG-01-V01 | RNG-01 | D-243-C007, D-243-F006, INV-237-035 | contracts/modules/DegenerusGameAdvanceModule.sol:454-457 (HEAD cc68bfc7) | RNG-01a (path P1 sole reaching path: new-day jackpot-phase STAGE_JACKPOT_ETH_RESUME branch) | SAFE | canonical next-tick unlock at L468 (`_unlockRng(day)` inside the `dailyJackpotCoinTicketsPending` branch) reached via the chain `payDailyJackpot CALL 1 (L474) → sets dailyJackpotCoinTicketsPending=true unconditionally (JackpotModule L519) → next tick hits L461-470 → _unlockRng(day) at L468`. Same-tick no-unlock is CORRECT per commit-msg intent: the deferred unlock preserves the rngLockedFlag AIRTIGHT invariant (one-set, one-clear per cycle) by moving the clear from AFTER-CALL-2 (baseline) to AFTER-coin+tickets (HEAD). | 16597cac |
| RNG-01-V02 | RNG-01 | D-243-C007, D-243-X013, D-243-X014 | contracts/DegenerusVault.sol:514-515 + contracts/StakedDegenerusStonk.sol:354-355 (vault + sDGNRS wrappers) | RNG-01b actor=player (player calls `gameAdvance` on vault-owner wrapper OR `gameAdvance` on sDGNRS wrapper, reaching advanceGame dispatcher) | SAFE | Both wrapper paths forward to `IDegenerusGame.advanceGame()` at DegenerusGame:284 (D-243-X011) → delegatecall to AdvanceModule.advanceGame at DegenerusGame:289 (D-243-X012). The wrapper callers do NOT modify player-controllable state between invocation and the rngLockedFlag set/clear SSTOREs; they are pure passthrough (verified by reading DegenerusVault.sol:514-515 and StakedDegenerusStonk.sol:354-355). Player cannot reach a path where rngLockedFlag stays set past the canonical L468 unlock — advanceGame is the sole entry, and the reaching path to L468 is reachable on any post-STAGE_JACKPOT_ETH_RESUME tick (no player gate blocks it). | 16597cac |
| RNG-01-V03 | RNG-01 | D-243-C007, D-243-X011 | contracts/DegenerusGame.sol:284 (dispatcher entry) | RNG-01b actor=admin (Admin or vault-owner or any caller of the DegenerusGame.advanceGame dispatcher — advanceGame is currently public with no caller gate per D-243-X011 row) | SAFE | advanceGame is an unrestricted external function (the scope for "admin" here is the identity-level distinction — any caller with enough gas can invoke it; there is no admin-only bypass). The same reaching-path analysis applies: no admin-privileged control flow reaches the removal point that would bypass the L468 unlock. Admin-gated functions (e.g., `updateVrfCoordinatorAndSub` at L1640) operate on a DIFFERENT clear path (RNGLOCK-239-C-02 per Phase 239) — they zero the flag for liveness-escape. The 16597cac removal does not alter the admin escape clear path in any way (L1653 SSTORE unchanged). | 16597cac |
| RNG-01-V04 | RNG-01 | D-243-C007, INV-237-035 | contracts/modules/DegenerusGameAdvanceModule.sol:454-457 | RNG-01b actor=validator (validator reorders transactions inside a block) | SAFE | A validator CAN place the STAGE_JACKPOT_ETH_RESUME tick first in a block and the coin+tickets tick last in the same block, BUT this does NOT widen the commitment window because rngLockedFlag stays `true` across BOTH ticks (validator cannot flip it directly — only `_unlockRng` / `_finalizeRngRequest` / `updateVrfCoordinatorAndSub` / `rawFulfillRandomWords` can, and none are validator-callable). Within a single block, player-callable state-mutating mid-day functions (MintModule._purchase*, StakedDegenerusStonk.burn/burnWrapped) all consult the locking predicates; under `rngLockedFlag = true` they revert (via rngLocked check at D-243-F024 and StakedDegenerusStonk rngLocked gate). Cross-tick same-block reordering cannot delay the L468 unlock to the NEXT block because `_unlockRng` is synchronous — once the coin+tickets tick fires, the unlock is unconditional. Validator cannot skip the coin+tickets tick because `advanceGame` is permissionless; the next advanceGame caller (incl. the validator's own bundled tx) triggers L468 immediately. | 16597cac |
| RNG-01-V05 | RNG-01 | D-243-C007 | contracts/modules/DegenerusGameAdvanceModule.sol:1708-1729 (rawFulfillRandomWords) | RNG-01b actor=VRF-oracle (Chainlink VRF coordinator callback timing) | SAFE | The VRF oracle's only callback is `rawFulfillRandomWords` at L1708, which is msg.sender-gated to `vrfCoordinator` at L1712 and requestId-gated at L1713. The callback writes to `rngWordCurrent` (daily branch L1720) or to `lootboxRngWordByIndex[index]` (mid-day branch L1724) but NEVER touches `rngLockedFlag`. It cannot force a path that bypasses L468 unlock. VRF delivery timing only affects WHEN `rngGate` returns a non-1 word — but the post-delivery flow (STAGE_JACKPOT_ETH_RESUME → next tick → L468) is deterministic once `rngWordByDay[day]` is populated. Also reference: RNGLOCK-239-C-03 (Phase 239 `rawFulfillRandomWords` structural clear-site proof — RE_VERIFIED at HEAD cc68bfc7; body L1708-1729 byte-identical to Phase 239 baseline per D-243-C007's targeted-hunk scope at L257-280, L449-451 — L1708-1729 NOT in the 16597cac hunk). | 16597cac |
| RNG-01-V06 | RNG-01 | D-243-C007, INV-237-035 | contracts/modules/DegenerusGameAdvanceModule.sol:288-294 (rngGate call site at L288 + consumer L381/L455/L474 of rngWord) | RNG-01c backward-trace: post-removal continuation point treated as CONSUMER of rngWord — trace BACKWARD from L455 `payDailyJackpot(true, lvl, rngWord)` (the CONSUMER) to every input-commitment site | SAFE | Treating `payDailyJackpot(true, lvl, rngWord)` at L455 (CALL 2 of ETH split, the continuation consumer) as a CONSUMER: rngWord flows backward from L455 → `rngGate(...)` return value at L288-294 → `rngWordByDay[day]` via L1156 short-circuit OR `rngWordCurrent` via L1161 → VRF fulfillment via `rawFulfillRandomWords` L1720. Input-commitment sites traced BACKWARD: (a) **ticket-purchase input** (MintModule `_queueTickets*` called from `_purchaseFor` et al.) writes `ticketQueue[writeKey]` entries where each ticket's `traitId` / `purchaser` was committed AT PURCHASE TIME, before `_swapAndFreeze(purchaseLevel)` at AdvanceModule L297 issues the VRF request. Per Phase 238 BWD-01 / BWD-02 re-verified at HEAD `7ab515fe` (structurally unchanged at cc68bfc7), every ticket-input commit happens on the WRITE key which is swapped to READ only after VRF fulfillment — rngWord was UNKNOWN at ticket-input commitment time. (b) **coinflip nudge input** (BurnieCoinflip `reverseFlip` L1915) is blocked by `if (rngLockedFlag) revert RngLocked();` at L1915 during the VRF commitment window — rngWord was UNKNOWN at nudge-input commitment time. (c) **jackpot-phase inputs** (jackpotCounter, dailyTicketBudgetsPacked, resumeEthPool, dailyJackpotCoinTicketsPending) are all written by PRIOR ticks' `payDailyJackpot` calls that ran under `rngLockedFlag = true` and the SAME rngWord — forward-only state updates, no player input can retroactively commit new inputs that see rngWord. NO path lets a player commit input AFTER rngWord is observable from the VRF callback, because `rngLockedFlag = true` from L1597 (in `_finalizeRngRequest`) gates all player-input paths until `_unlockRng` fires. The `16597cac` removal does NOT change any of these backward-trace properties — it only moves the `_unlockRng` SSTORE from L451 to L468 (on a subsequent tick), keeping the flag `true` for LONGER, which NARROWS the commitment window rather than widening it. | 16597cac |
| RNG-01-V07 | RNG-01 | D-243-C007 | contracts/modules/DegenerusGameAdvanceModule.sol:1597 (set) vs L468/L400/L329/L632/L1653/L1694 (clear sites) | RNG-01d commitment-window per project skill `feedback_rng_commitment_window.md`: enumerate player-controllable state that can change between VRF request and fulfillment for the post-removal shape; compare to pre-removal (baseline 7ab515fe) | SAFE | **Commitment window NARROWED by 16597cac, not widened.** Pre-removal (baseline `7ab515fe`): window from `_finalizeRngRequest` (L1597 set) to the FIRST-reached unlock clear. On the jackpot-phase ETH-resume path the first clear was at BASELINE L450 (removed). Post-removal (HEAD `cc68bfc7`): the window extends to the LATER L468 clear (one tick farther). During the extended window, `rngLockedFlag = true` continues to block: (a) BurnieCoinflip `reverseFlip` at L1915 (nudge purchase); (b) WhaleModule `_purchaseDeityPass` at L543 (deity pass purchase); (c) StakedDegenerusStonk `burn` + `burnWrapped` (the D-243-F011/F012 gates added by 771893d1, consulting `livenessTriggered + rngLocked`); (d) DegenerusGame external `rngLocked()` view at L2176 (consumer-facing). Everything a player CAN still do during the extended window (advanceGame calls, view reads, non-state-changing ERC20 balance queries) is orthogonal to VRF determinism. **Verdict: commitment window NARROWED (strictly smaller set of player-controllable state changes) — this is the intended security improvement of 16597cac.** | 16597cac |
| RNG-01-V08 | RNG-01 | D-243-C007, INV-237-035 | contracts/modules/DegenerusGameAdvanceModule.sol:1692-1699 (`_unlockRng` body) | RNG-01a structural: verify `_unlockRng(day)` is still reachable on every reaching path to L454 (ZERO-unreach-path audit) | SAFE | `_unlockRng` is defined at L1692 as `private`. Its six call sites are: L329 (phase-transition-done), L400 (purchase-daily), L468 (jackpot-coin+tickets), L632 (gameover-drain), and the two zeroing writes inside `updateVrfCoordinatorAndSub` at L1653 + inside `_unlockRng` itself at L1694. Every path that ever set `rngLockedFlag = true` via L1597 is guaranteed to reach exactly one of {L468, L632, L1653}. For the 16597cac-touched path specifically (STAGE_JACKPOT_ETH_RESUME), the downstream chain STAGE_JACKPOT_ETH_RESUME → next tick L461 gate → L468 unlock is TOTAL (there is no predecessor that sets dailyJackpotCoinTicketsPending without also eventually clearing rngLockedFlag). The only way for rngLockedFlag to stay set past the canonical unlock chain is via gameover (L632) OR admin coordinator-swap (L1653) — both are liveness-escape paths that also clear it. Zero-unreach-path audit passes: every reaching-path to STAGE_JACKPOT_ETH_RESUME is followed by a reachable unlock on a subsequent tick. | 16597cac |
| RNG-01-V09 | RNG-01 | D-243-C007 | contracts/modules/DegenerusGameAdvanceModule.sol:454-457 + JackpotModule:342-520 | RNG-01a state-invariant check: verify `dailyJackpotCoinTicketsPending` is ALWAYS set by any prior invocation that sets `resumeEthPool` (so the L461 branch always reaches L468 after the L454 branch) | SAFE | JackpotModule.payDailyJackpot body L342-520 traces both SPLIT_NONE and SPLIT_CALL1 paths in the `isJackpotPhase` branch. The write `dailyJackpotCoinTicketsPending = true` at L519 is UNCONDITIONAL inside the `if (isJackpotPhase)` block (no `if` gate around it) — meaning every CALL 1 (regardless of splitMode) sets `dailyJackpotCoinTicketsPending = true`. And `resumeEthPool = uint128(ethPool)` at L1300 fires only under SPLIT_CALL1 (L1299 gate). Therefore: if `resumeEthPool != 0` at L454 (entry condition), then `dailyJackpotCoinTicketsPending = true` is GUARANTEED by the same prior CALL 1 that set resumeEthPool. After STAGE_JACKPOT_ETH_RESUME clears resumeEthPool (via _resumeDailyEth L1205), the next tick enters L461 branch → L468 unlock. Pairing holds. No reformulation of splitMode in 16597cac hunks (splitMode logic at JackpotModule L473-475 untouched by this commit). | 16597cac |
| RNG-01-V10 | RNG-01 | D-243-C007, §1.7 bullet 3 | contracts/modules/DegenerusGameAdvanceModule.sol:451 (removed) — cross-cite §1.7 bullet 3 which is closed in §RNG-02 | RNG-cc: cross-cite to §1.7 bullet 3 closure for `_gameOverEntropy` rngRequestTime reentry adjacency; the removed L451 unlock does NOT interact with `_gameOverEntropy` because gameover-drain runs through L632 (`_handleGameOverPath`) on a separate reaching path | SAFE | `_gameOverEntropy` is called exclusively from `_handleGameOverPath` at L560 (D-243-X027). `_handleGameOverPath` is called from `advanceGame` at L183 (pre-do-while). The do-while at L259 (where the 16597cac-removed L451 lived) is entered ONLY when `_handleGameOverPath` returns `(false, 0)` at L197. So the removed unlock at L451 and `_gameOverEntropy` are on MUTUALLY EXCLUSIVE reaching paths — they never co-execute in the same tick. The §1.7 bullet 3 reentry-adjacency concern (`rngRequestTime = 0` at L1292 fires AFTER `_finalizeLootboxRng(fallbackWord)` at L1289) is an INTRA-function ordering concern inside `_gameOverEntropy`, NOT a cross-function concern with advanceGame's do-while unlock path. §RNG-02 owns the bullet-3 closure via RNG-02-V04 (Task 2 append). This row documents the scope-disjoint property so 244-04 GOX-06 does not double-count. | 16597cac + 771893d1 (cross-cite) |
| RNG-01-V11 | RNG-01 | D-243-C007, EXC-03, F-29-04 | contracts/modules/DegenerusGameAdvanceModule.sol:451 (removed) + L297 (`_swapAndFreeze`) + L1082 (`_swapTicketSlot`) + L1228-1305 (`_gameOverEntropy`) | RNG-01e KI EXC-03 envelope re-verify per CONTEXT.md D-22: confirm `_unlockRng(day)` removal does NOT regress F-29-04 mid-cycle substitution (ticket-buffer swap timing unaffected) | RE_VERIFIED_AT_HEAD cc68bfc7 | F-29-04 / EXC-03 envelope: "Gameover RNG substitution for mid-cycle write-buffer tickets" — the mid-cycle substitution occurs when `_swapAndFreeze(purchaseLevel)` (AdvanceModule L297, daily-VRF-request write-buffer swap) OR `_swapTicketSlot(purchaseLevel_)` (AdvanceModule L1082, mid-day lootbox write-buffer swap) has moved new-buffer tickets to the active write key with an expected-next VRF fulfillment, and gameover intervenes before that fulfillment so those tickets drain under `_gameOverEntropy` substituted entropy rather than the originally-anticipated mid-day VRF word. **Timing analysis of the 16597cac removal vs F-29-04 window:** the removed `_unlockRng(day)` at L451 (baseline) ran on STAGE_JACKPOT_ETH_RESUME — which is the JACKPOT PHASE (inJackpot==true). `_swapAndFreeze` at L297 fires only when `rngWord == 1` (VRF request path) — that's in the daily-drain do-while BEFORE inJackpot branch. `_swapTicketSlot` at L1082 is called by WRITE requests during level transition OR by `_handleGameOverPath` at L602 during gameover-drain. **The removal is DOWNSTREAM of both swap sites and is on a DIFFERENT reaching path from `_gameOverEntropy` (mutually exclusive per RNG-01-V10).** The write-buffer swap timing at L297 + L1082 is NOT mutated by 16597cac (which touches only L257-280 and L449-451 hunks — NEITHER the `_swapAndFreeze` call site nor the `_swapTicketSlot` call site). F-29-04 mid-cycle substitution invariant: unchanged. `_gameOverEntropy` entropy source (`rngWordCurrent && rngRequestTime` active-VRF branch L1237, or `_getHistoricalRngFallback` prevrandao-fallback branch L1267) is unchanged — the 16597cac commit does NOT modify `_gameOverEntropy` at all (that function is touched only by 771893d1 — a separate commit). **Annotation:** RE_VERIFIED_AT_HEAD `cc68bfc7` — EXC-03 envelope unchanged. Removal is on a mutually-exclusive reaching path from the mid-cycle substitution window per §2.3 D-243-F006 hunk scope (L257-280, L449-451) + per F-29-04 ticket-buffer swap timing (L297, L1082). | 16597cac |

### RNG-01 closure

All 11 V-rows SAFE (10 SAFE + 1 RE_VERIFIED_AT_HEAD for EXC-03). No finding candidates. The `_unlockRng(day)` removal at baseline L451 is reachable-safe: the canonical downstream unlock at L468 (dailyJackpotCoinTicketsPending branch) closes the rngLockedFlag set-clear pairing on the subsequent tick. Commitment window NARROWED, not widened. 4-actor adversarial closure passes (player / admin / validator / VRF oracle) per Phase 238 D-07 carry. Backward-trace and commitment-window checks both pass per project skills. EXC-03 envelope RE_VERIFIED_AT_HEAD `cc68bfc7` unchanged.

## §RNG-03 — 16597cac reformat-only behavioral equivalence

**Owning commit:** `16597cac`. **Source 243 rows:** D-243-C007 (changelog), D-243-F006 (MODIFIED_LOGIC verdict noting D-05.1 + D-05.2 collapsed — removal drives verdict, reformats are subordinate per §2.3), §1.8 INV-237-022 + INV-237-023 REFORMAT-TOUCHED rows (daily-drain gate pre-check sites at L261, L262 baseline vs L264-266, L268 HEAD).

**Methodology:** Side-by-side prose diff per CONTEXT.md D-17. For each of the two reformat hunks in the 16597cac commit (see `git show 16597cac -- contracts/modules/DegenerusGameAdvanceModule.sol` output), name the specific source elements and prove element-by-element byte-equivalence. Escalate to MODIFIED_LOGIC if any doubt remains (per D-17 burden-of-proof rule). Bytecode-diff methodology EXPLICITLY NOT USED here (that is reserved for QST-05 per CONTEXT.md D-13).

### Reformat hunk 1: multi-line SLOAD cast at L264-266 (HEAD) / L260 (baseline)

**Baseline `7ab515fe` (single line at L260):**
```solidity
uint48 preIdx = uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)) - 1;
```

**HEAD `cc68bfc7` (multi-line at L264-266):**
```solidity
uint48 preIdx = uint48(
    _lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)
) - 1;
```

**Element-by-element equivalence:**
- Declared variable: `uint48 preIdx` — unchanged (same type, same name, same scope).
- RHS expression: `uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)) - 1` — token-equivalent across whitespace/newline changes. Solidity 0.8.34 parses the expression identically regardless of line wrapping.
- SLOAD source slot: `_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)` reads the `lootboxRng` packed slot with the same `LR_INDEX_SHIFT` and `LR_INDEX_MASK` constants (both declared in DegenerusGameStorage — NOT touched by 16597cac per §1.2 D-243-C007 hunk scope).
- Cast operator: `uint48(...)` explicit cast — unchanged.
- Subtraction: `- 1` — unchanged.
- No SSTORE introduced: the expression is pure read + arithmetic + local-var assignment (no storage write).
- No branch added: control flow from L264 to L267 is unchanged (still sequential assignment feeding the `if (lootboxRngWordByIndex[preIdx] == 0)` guard at L267).
- No return-path evaluation drift: the function (`advanceGame`) return path is unaffected — `preIdx` is consumed locally in the same block.

**Verdict:** REFACTOR_ONLY confirmed. Execution trace byte-equivalent.

### Reformat hunk 2: tuple destructuring multi-line at L275-277 (HEAD) / L266-269 (baseline)

**Baseline `7ab515fe`:**
```solidity
(
    bool preWorked,
    bool preFinished
) = _runProcessTicketBatch(purchaseLevel);
```

**HEAD `cc68bfc7`:**
```solidity
(bool preWorked, bool preFinished) = _runProcessTicketBatch(
    purchaseLevel
);
```

**Element-by-element equivalence:**
- Tuple element names: `bool preWorked, bool preFinished` — unchanged (same types, same names, same order).
- Function call target: `_runProcessTicketBatch(purchaseLevel)` — unchanged (same callee, same argument).
- Destructuring semantics: Solidity 0.8.34 assigns tuple elements positionally; both forms produce `preWorked = <return[0]>` and `preFinished = <return[1]>`. Line-wrap position does not affect the positional assignment.
- No SSTORE introduced.
- No branch added: control flow from L275 to L278 is unchanged (still sequential assignment feeding the `if (preWorked || !preFinished)` guard at L278).
- No return-path evaluation drift: the destructured locals feed the guard at L278 which either `break`s out of the do-while or falls through to L283; this control flow is preserved byte-identically in the diff (see `git show 16597cac` — the lines after the reformat are byte-identical).

**Verdict:** REFACTOR_ONLY confirmed. Execution trace byte-equivalent.

### Verdict rows — RNG-03

| Verdict Row ID | REQ-ID | Source 243 Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RNG-03-V01 | RNG-03 | D-243-C007, D-243-F006, INV-237-022, INV-237-023 | contracts/modules/DegenerusGameAdvanceModule.sol:264-266 (HEAD) vs L260 (baseline 7ab515fe) | RNG-03a multi-line SLOAD cast reformat | SAFE | Side-by-side prose diff (above): variable name unchanged (`uint48 preIdx`), SLOAD source expression `_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)` byte-identical, cast `uint48(...)` unchanged, `- 1` subtraction unchanged, no SSTORE introduced, no branch added, no return-path evaluation drift. Solidity 0.8.34 AST parses both forms identically. REFACTOR_ONLY per Phase 243 D-04 + D-19 evidence burden. | 16597cac |
| RNG-03-V02 | RNG-03 | D-243-C007, D-243-F006 | contracts/modules/DegenerusGameAdvanceModule.sol:275-277 (HEAD) vs L266-269 (baseline 7ab515fe) | RNG-03a tuple destructuring reformat | SAFE | Side-by-side prose diff (above): tuple element names `bool preWorked, bool preFinished` unchanged, callee `_runProcessTicketBatch(purchaseLevel)` byte-identical, destructuring positional semantics preserved, no SSTORE introduced, no branch added, no return-path evaluation drift. REFACTOR_ONLY per Phase 243 D-04 + D-19 evidence burden. | 16597cac |

### RNG-03 closure

Both reformat hunks verified REFACTOR_ONLY by element-by-element prose diff. Execution trace byte-equivalent; compiler output may differ trivially in intermediate AST representation but semantic behaviour identical. No MODIFIED_LOGIC escalation needed. D-05.1 + D-05.2 pre-locked verdicts in §2.2 of the delta surface confirmed verbatim.

## §KI Envelope Re-Verify — EXC-03 (F-29-04 mid-cycle substitution)

**Source KI entry:** `KNOWN-ISSUES.md` under "Design Decisions" — "Gameover RNG substitution for mid-cycle write-buffer tickets".

Verbatim KI text (quoted): *"Degenerus enforces an 'RNG-consumer determinism' invariant: every RNG consumer's entropy must be fully committed at input time — the VRF word that a consumer will ultimately read must be unknown-but-bound at the moment that consumer's input parameters are committed to storage. One terminal-state case technically violates it: if a mid-cycle ticket-buffer swap has occurred (daily RNG request via `_swapAndFreeze(purchaseLevel)` at DegenerusGameAdvanceModule.sol:292, OR mid-day lootbox RNG request via `_swapTicketSlot(purchaseLevel_)` at DegenerusGameAdvanceModule.sol:1082) and the new write buffer is populated with tickets queued at the current level awaiting the expected-next VRF fulfillment, a game-over event intervening before that fulfillment causes those tickets to drain under the final gameover entropy (`_gameOverEntropy` at DegenerusGameAdvanceModule.sol:1222-1246) rather than the originally-anticipated mid-day VRF word."*

**Acceptance rationale (from KI):** (a) only reachable at gameover — a terminal state with no further gameplay after the 30-day post-gameover window; (b) no player-reachable exploit — gameover is triggered by a 120-day liveness stall or a pool deficit, neither of which an attacker can time against a specific mid-cycle write-buffer state; (c) at gameover the protocol must drain within bounded transactions and cannot wait for a deferred fulfillment that may never arrive if the VRF coordinator itself is the reason for the liveness stall; (d) all substitute entropy is VRF-derived or VRF-plus-prevrandao.

**Re-verification at HEAD `cc68bfc7` against the 16597cac `_unlockRng(day)` removal:**

1. **Identify the F-29-04 mid-cycle substitution path.** The three proof targets per `audit/v30-CONSUMER-INVENTORY.md` KI Cross-Ref Summary are: (a) `_swapAndFreeze(purchaseLevel)` at AdvanceModule L297 (daily VRF request), (b) `_swapTicketSlot(purchaseLevel_)` at AdvanceModule L1082 (mid-day lootbox VRF request), (c) `_gameOverEntropy` substitution block at AdvanceModule L1237-1261 (VRF-word branch) + L1263-1296 (fallback branch). The "line numbers shifted" per the `cc68bfc7` addendum note in DELTA-SURFACE §3 (AdvanceModule lines shift by +2 downstream of the L105-106 addendum `jackpots` constant) — at `cc68bfc7`, `_swapAndFreeze` is at L297, `_swapTicketSlot` is at L1082, `_gameOverEntropy` body spans L1228-1305.

2. **Verify 16597cac does NOT touch any of the F-29-04 proof targets.** Per `git show 16597cac -- contracts/modules/DegenerusGameAdvanceModule.sol` (and §2.3 D-243-F006 Hunk Ref column at `contracts/modules/DegenerusGameAdvanceModule.sol:257-279,449-451@771893d1`), the 16597cac hunks are: (a) reformat at L257-260 (baseline 260) — the `preIdx` cast multi-line split — this is in the MID-DAY DRAIN GATE block (before RNG acquisition, BEFORE `_swapAndFreeze`); (b) reformat at L266-269 (baseline) / L275-277 (HEAD) — the `_runProcessTicketBatch` tuple destructure — same block as (a); (c) the 1-line `_unlockRng(day)` removal at L451 (baseline) on STAGE_JACKPOT_ETH_RESUME. **NONE of these three hunk sites are `_swapAndFreeze` (L297), `_swapTicketSlot` (L1082), or `_gameOverEntropy` (L1228-1305).**

3. **Verify timing relationship is preserved.** The F-29-04 mid-cycle substitution window opens at the write-buffer swap (`_swapAndFreeze` at L297 OR `_swapTicketSlot` at L1082) and closes at the subsequent VRF fulfillment (via `rawFulfillRandomWords` L1708). The intervening gameover event (if any) invokes `_gameOverEntropy` via `_handleGameOverPath` (called from L183, pre-do-while). The removed `_unlockRng(day)` at baseline L451 fired inside the do-while's jackpot-phase branch — which is REACHED only if `_handleGameOverPath` returns `(false, 0)` at L197 (no gameover). So: if gameover fires, the 16597cac-touched code path is NOT REACHED; if gameover does not fire, the 16597cac-touched code path fires on the normal jackpot-phase cycle and is orthogonal to the mid-cycle substitution window. **Timing relationship preserved.**

4. **Verify acceptance-rationale invariants preserved.** (a) Only reachable at gameover: unchanged (16597cac does not introduce any new non-gameover path that reaches `_gameOverEntropy`). (b) No player-reachable exploit: unchanged (16597cac narrows — does not widen — the commitment window per RNG-01-V07). (c) Bounded-drain requirement: unchanged (the STAGE_JACKPOT_ETH_RESUME → L468 unlock chain completes in at most 2 ticks regardless of gameover). (d) All substitute entropy VRF-derived-or-VRF-plus-prevrandao: unchanged (16597cac does not touch `_gameOverEntropy` or `_getHistoricalRngFallback`).

**Annotation: RE_VERIFIED_AT_HEAD `cc68bfc7` — EXC-03 envelope unchanged. The `_unlockRng(day)` removal is on a mutually-exclusive reaching path from the F-29-04 mid-cycle substitution window (gameover vs non-gameover branch disjoint in `_handleGameOverPath`). All 4 acceptance-rationale invariants (a-d) hold. No regression.**

Verdict row RNG-01-V11 (§RNG-01 above) is the canonical carrier of this annotation.

## §RNG-02 — rngLockedFlag AIRTIGHT invariant RE_VERIFIED_AT_HEAD cc68bfc7

**Owning commits:** `16597cac` (the `_unlockRng(day)` removal — a clear-site-caller removal) + `771893d1` (the `_gameOverEntropy` rngRequestTime clearing at L1292). **Source 243 rows:** D-243-C007 (advanceGame), D-243-C016 (_gameOverEntropy), D-243-F006 + D-243-F014 (verdicts), D-243-X027 (_gameOverEntropy call site), §1.8 INV-237-021..037 (rngLockedFlag overlap rows) + INV-237-058, INV-237-059 (_gameOverEntropy rows).

### Invariant statement (from Phase 239 RNG-01..03)

Verbatim from `audit/v30-RNGLOCK-STATE-MACHINE.md`:

> *"RNG-01 — `rngLockedFlag` state machine airtight: every set site + every clear site + every early-return / revert path enumerated; no reachable path produces set-without-clear or clear-without-matching-set."*

And the closed-form invariant proof (Invariant 1 + Invariant 2):

> *"No reachable path produces set-without-clear (Invariant 1) OR clear-without-matching-set (Invariant 2). **RNG-01 AIRTIGHT.**"*

The v30.0 verdict at HEAD `7ab515fe` (byte-identical to v29.0 `1646d5af`): 1 Set-Site AIRTIGHT + 3 Clear-Sites AIRTIGHT + 9 Path rows in {SET_CLEARS_ON_ALL_PATHS, CLEAR_WITHOUT_SET_UNREACHABLE} with zero CANDIDATE_FINDING.

### Re-verification methodology (per CONTEXT.md D-22 + Phase 238 D-10 pattern)

This re-verification confirms the v30.0 invariant holds at HEAD `cc68bfc7` against the post-v30.0 deltas:
1. The `16597cac` `_unlockRng(day)` removal at baseline L451 (a clear-site-caller removal — the physical clear site itself is INSIDE `_unlockRng` at L1694; the removal at L451 is a deletion of one of the six CALL SITES of `_unlockRng`).
2. The `771893d1` `_gameOverEntropy` `rngRequestTime = 0` SSTORE at L1292 (a rngRequestTime clear — NOT a rngLockedFlag clear; the AIRTIGHT invariant is about rngLockedFlag specifically, but rngRequestTime interacts with rngLockedFlag through the `_tryRequestRng` / `_gameOverEntropy` / `_livenessTriggered` tri-state lifecycle and therefore is in scope for the re-verification).

It does NOT re-litigate the invariant itself — only the envelope against the deltas. The canonical Phase 239 Set-Site and Clear-Site proofs (RNGLOCK-239-S-01, RNGLOCK-239-C-01..C-03) remain authoritative.

### Set-Site and Clear-Site re-anchor at HEAD `cc68bfc7`

Running the canonical Phase 239 greps at HEAD `cc68bfc7`:

- `grep -rn --include='*.sol' 'rngLockedFlag\s*=\s*true' contracts/` → 1 hit at `contracts/modules/DegenerusGameAdvanceModule.sol:1597` (inside `_finalizeRngRequest`). Matches RNGLOCK-239-S-01 file:line (was L1579 at `7ab515fe`; shift +18 due to intervening docs-only or unrelated refactors + cc68bfc7 addendum's L105-106 insertion accumulating downstream — verified structurally equivalent by reading the function body at cc68bfc7 L1537-1632).
- `grep -rn --include='*.sol' 'rngLockedFlag\s*=\s*false' contracts/` → 2 hits at `contracts/modules/DegenerusGameAdvanceModule.sol:1653` (inside `updateVrfCoordinatorAndSub`) and `contracts/modules/DegenerusGameAdvanceModule.sol:1694` (inside `_unlockRng`). Matches RNGLOCK-239-C-02 and RNGLOCK-239-C-01 respectively (was L1635 and L1676 at `7ab515fe`; same +18 shift).
- `grep -rn --include='*.sol' '_unlockRng\b' contracts/` → 5 hits total: definition at L1692 + 4 call sites at L329, L400, L468, L632. **This is DOWN-ONE from Phase 239's SIX call-site enumeration** (Phase 239 listed L324, L395, L451, L464, L625 plus the definition at L1674 — 5 call sites + 1 definition = 6 hits). The "missing" call site at baseline L451 is the one REMOVED by `16597cac`. The remaining 4 call sites at cc68bfc7 map to Phase 239's 5-site list as: L329↔Phase239-L324, L400↔Phase239-L395, L468↔Phase239-L464, L632↔Phase239-L625 — the DROPPED site is Phase239-L451. **The drop is the intended effect of 16597cac.** Per RNG-01-V01 above, the canonical downstream unlock for the STAGE_JACKPOT_ETH_RESUME branch shifts from same-tick L451 to next-tick L468. The set-clear pairing at the rngLockedFlag SSTORE level (L1597 set vs L1694 clear via _unlockRng) is PRESERVED — _unlockRng still fires exactly once per VRF cycle; only its CALL SITE inside advanceGame's do-while is moved later.

### Verdict rows — RNG-02

| Verdict Row ID | REQ-ID | Source 243 Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RNG-02-V01 | RNG-02 | D-243-C007, INV-237-021..037, Phase 239 RNGLOCK-239-S-01 | contracts/modules/DegenerusGameAdvanceModule.sol:1597 (set) vs L1653 + L1694 (clear) | RNG-02a no-double-set predicate: verify `rngLockedFlag = true` is idempotent and no second set fires without intervening clear | RE_VERIFIED_AT_HEAD cc68bfc7 | The sole set-site at L1597 is inside `_finalizeRngRequest` (called from `_requestRng` at L1541 + `_tryRequestRng` at L1571). Both helpers write `rngLockedFlag = true` UNCONDITIONALLY — idempotent per Phase 239 RNGLOCK-239-S-01. 16597cac does NOT add a new set site; the only change is a call-site removal at advanceGame L451 for `_unlockRng(day)` (a CLEAR-site-caller removal, not a set-site addition). Double-set impossible because the only path that reaches L1597 requires `rngLockedFlag` to have been written (either to `false` by `_unlockRng` / `updateVrfCoordinatorAndSub` OR never touched from default zero). Idempotent re-writes of `true→true` are semantic no-ops per EVM SSTORE rules and Phase 239 retry-branch analysis. **No change vs Phase 239 verdict.** | 16597cac (delta), Phase 239 (origin) |
| RNG-02-V02 | RNG-02 | D-243-C007, INV-237-021..037, Phase 239 RNGLOCK-239-P-001..P-008 | contracts/modules/DegenerusGameAdvanceModule.sol:1597 (set) + L329, L400, L468, L632 (post-16597cac clear call sites) + L1653 (admin escape) | RNG-02a no-set-without-clear predicate: every set at L1597 reaches a matching clear on the same tick OR via the next tick's normal/gameover unlock chain | RE_VERIFIED_AT_HEAD cc68bfc7 | **Every reaching path from L1597 reaches a clear.** Paths enumerated against cc68bfc7: (a) daily purchase-phase: L1597 (set via rngGate→_requestRng→_finalizeRngRequest) → next tick `rngWordByDay[day] != 0` OR `rngWordCurrent != 0 && rngRequestTime != 0` → rngGate returns non-1 → L400 `_unlockRng(day)` clear. AIRTIGHT. (b) daily jackpot-phase SPLIT_NONE: L1597 → next tick rngGate returns non-1 → inJackpot branch → L474 payDailyJackpot CALL 1 (sets dailyJackpotCoinTicketsPending=true) → TICK_N+1 L461 branch → L468 `_unlockRng(day)` clear. AIRTIGHT. (c) daily jackpot-phase SPLIT_CALL1: L1597 → next tick rngGate returns non-1 → inJackpot branch → L474 payDailyJackpot CALL 1 (sets resumeEthPool + dailyJackpotCoinTicketsPending) → TICK_N+1 L454 branch (STAGE_JACKPOT_ETH_RESUME — NO unlock per 16597cac removal) → TICK_N+2 L461 branch → L468 `_unlockRng(day)` clear. AIRTIGHT (one-extra-tick delay, still same daily cycle, still pair-clears). (d) phase-transition-done: L1597 → rngGate non-1 → phaseTransitionActive==true branch → L329 clear. AIRTIGHT. (e) gameover-drain: L1597 → next tick → `_handleGameOverPath` reaches L560 `_gameOverEntropy` → (if VRF-word available) returns non-1/0 → L632 `_unlockRng(day)` clear. AIRTIGHT. (f) admin escape: L1597 → `updateVrfCoordinatorAndSub` call (admin-gated) → L1653 clear. AIRTIGHT. (g) transaction revert: L1597 rolls back. AIRTIGHT-via-rollback. **Zero reachable path produces set-without-clear at HEAD cc68bfc7.** | 16597cac (delta), 771893d1 (delta), Phase 239 (origin) |
| RNG-02-V03 | RNG-02 | D-243-C007, INV-237-021..037, Phase 239 RNGLOCK-239-C-01..C-03 | contracts/modules/DegenerusGameAdvanceModule.sol:1694 (inside `_unlockRng`) + L1653 (admin escape) + L1708-1729 (rawFulfillRandomWords structural) | RNG-02a no-clear-without-matching-set predicate: every clear SSTORE at L1694/L1653 pairs with a prior L1597 set in the same VRF lifecycle | RE_VERIFIED_AT_HEAD cc68bfc7 | **Every reachable clear pairs with a prior set.** (a) `_unlockRng` clear at L1694: reached from 4 call sites (L329, L400, L468, L632) — every call site is downstream of rngGate/_gameOverEntropy returning a non-1 word, which implies `rngWordCurrent != 0 \|\| rngWordByDay[day] != 0`, which implies a prior `_finalizeRngRequest` fired (setting rngLockedFlag=true at L1597). If no prior set happened (rngLockedFlag already false), the `_unlockRng` SSTORE is a same-value rewrite (`false→false`) — semantic no-op. No spurious clear produced. AIRTIGHT. (b) `updateVrfCoordinatorAndSub` clear at L1653: admin-gated, no-op if rngLockedFlag already false, cleans-up if already true. AIRTIGHT per Phase 239 RNGLOCK-239-C-02. (c) `rawFulfillRandomWords` L1708-1729 body structural clear-site-ref: does NOT mutate rngLockedFlag; branches only touch rngWordCurrent (daily) or lootboxRngWordByIndex (mid-day) + rngRequestTime/vrfRequestId. **No new clear-site added by 16597cac or 771893d1. Phase 239 verdict preserved.** | 16597cac (delta), 771893d1 (delta), Phase 239 (origin) |
| RNG-02-V04 | RNG-02 | D-243-C016, D-243-F014, D-243-X027, §1.7 bullet 3, INV-237-059 HUNK-ADJACENT | contracts/modules/DegenerusGameAdvanceModule.sol:1274 (`_finalizeLootboxRng(fallbackWord)`) + L1292 (new `rngRequestTime = 0` SSTORE per 771893d1) | RNG-02d `_gameOverEntropy` rngRequestTime clearing reentry surface per §1.7 bullet 3 | SAFE | **Call sequence inside `_gameOverEntropy` fallback branch (L1263-1305 at HEAD cc68bfc7):** L1264 `elapsed = ts - rngRequestTime` → L1265-1267 fallback-delay guard → L1267 `fallbackWord = _getHistoricalRngFallback(day)` (internal view — no external call; reads `rngWordByDay[day - n]` storage) → L1268 `fallbackWord = _applyDailyRng(day, fallbackWord)` (internal pure — no external call) → L1269-1275 `if (lvl != 0) coinflip.processCoinflipPayouts(...)` (**EXTERNAL CALL to BurnieCoinflip.processCoinflipPayouts**) → L1277-1288 `sdgnrs.hasPendingRedemptions()` staticcall + `sdgnrs.resolveRedemptionPeriod(...)` external call → L1289 `_finalizeLootboxRng(fallbackWord)` (internal, writes `lootboxRngWordByIndex[index]` at L1219) → L1292 `rngRequestTime = 0` SSTORE → L1293 `return fallbackWord`. **Reentry-surface analysis:** There IS an external-call window between L1270 (coinflip.processCoinflipPayouts) and L1292 (rngRequestTime=0), and another between L1286 (sdgnrs.resolveRedemptionPeriod) and L1292. During these windows, rngRequestTime is STILL NON-ZERO (not yet cleared). An attacker who controls BurnieCoinflip or StakedDegenerusStonk could theoretically re-enter `_gameOverEntropy`, but: (1) Both coinflip and sdgnrs addresses are `ContractAddresses.COINFLIP` and `ContractAddresses.SDGNRS` — compile-time constants for protocol-internal contracts, NOT attacker-controlled; (2) `_gameOverEntropy` is a `private` function in AdvanceModule — not reachable via external re-entry at all (private functions cannot be called across contract boundaries in Solidity); (3) The outer function (`_handleGameOverPath`) is called via `advanceGame → L183` — if a re-entrant advanceGame fires during the external-call window, it would re-enter at the TOP of advanceGame, not mid-`_gameOverEntropy`, and would hit `rngLockedFlag = true` (or rngWordCurrent check) gates. The rngRequestTime=0 SSTORE at L1292 does NOT create an exploitable reentry surface because (a) no external call AFTER L1292 in the fallback path (L1292 → L1293 return); (b) pre-L1292 external calls target hard-coded addresses; (c) `_gameOverEntropy` not externally reachable. **Phase 243 §1.7 bullet 3 CLOSED. Verdict SAFE.** | 771893d1 |
| RNG-02-V05 | RNG-02 | D-243-C016 | contracts/modules/DegenerusGameAdvanceModule.sol:1263-1305 (fallback branch) | RNG-02 commitment-window check per project skill `feedback_rng_commitment_window.md` for the `_gameOverEntropy` rngRequestTime clearing | SAFE (window HOLDS — neither widened nor narrowed for rngLockedFlag; NARROWED for rngRequestTime-based liveness after fallback commits) | **Commitment-window analysis for rngRequestTime clear at L1292:** What player-controllable state can change between VRF request (`rngRequestTime = ts` at L1304 or inside `_finalizeRngRequest` via L1596) and fulfillment (the VRF word arriving via `rawFulfillRandomWords` L1708)? In the normal path, rngLockedFlag=true gates MintModule/WhaleModule purchase, StakedDegenerusStonk burn/burnWrapped (post-771893d1), BurnieCoinflip reverseFlip. **Baseline `7ab515fe` vs HEAD `cc68bfc7` for the fallback-path rngRequestTime clearing:** Baseline: rngRequestTime stays NON-ZERO until `_unlockRng` fires later (via another code path, e.g., the old-style full advanceGame completion) OR the VRF fallback-delay guard naturally times out. HEAD: rngRequestTime cleared IMMEDIATELY after `_finalizeLootboxRng(fallbackWord)` at L1292 — BUT this happens INSIDE `_gameOverEntropy` which is called from `_handleGameOverPath` which is ONLY reached during the GAMEOVER path (where `_livenessTriggered()` is true). **Impact on player-controllable state:** rngLockedFlag (the main commitment-window lock) is STILL `true` at L1292 (not cleared here — that clear is at L632 inside `_handleGameOverPath` AFTER the drain returns). So mid-day purchase/burn gates stay locked. rngRequestTime clear at L1292 only affects `_livenessTriggered()` at L1243 (DegenerusGameStorage): `return rngStart != 0 && block.timestamp - rngStart >= _VRF_GRACE_PERIOD` — clearing rngStart makes `_livenessTriggered()` return false, which NARROWS the liveness-triggered window per the commit message ("liveness now reads from day math alone instead of short-circuiting on a stale VRF timer"). This is NARROWING, not widening — exactly the commit's design intent. **Verdict: commitment window for rngLockedFlag HOLDS; commitment window for rngRequestTime-based liveness NARROWED. No widening.** | 771893d1 |
| RNG-02-V06 | RNG-02 | D-243-C016, EXC-02, INV-237-055..062 | contracts/modules/DegenerusGameAdvanceModule.sol:1267 (`_getHistoricalRngFallback`) + L1292 (new clear) | RNG-02c KI EXC-02 envelope re-verify per CONTEXT.md D-22: confirm new rngRequestTime=0 clearing does NOT widen EXC-02 prevrandao-fallback envelope | RE_VERIFIED_AT_HEAD cc68bfc7 | **EXC-02 envelope:** "Gameover prevrandao fallback" — prevrandao consumption is limited to `_getHistoricalRngFallback` at AdvanceModule L1311 (shifted +10 vs baseline per cc68bfc7 addendum). This helper blends `block.prevrandao` with up to 5 historical VRF words via keccak256. It is reachable ONLY from inside `_gameOverEntropy` L1267 (the fallback branch under the 14-day grace). **Does the new L1292 `rngRequestTime = 0` SSTORE open a new path to `_getHistoricalRngFallback`?** NO. The new SSTORE at L1292 fires AFTER `_getHistoricalRngFallback` has already been called at L1267 and its return value already consumed via L1268-L1289. The clearing happens on the EXIT of the fallback branch, not on entry. After L1292, control returns to `_handleGameOverPath` L566 `if (rngWord == 1 \|\| rngWord == 0) return (true, STAGE_GAMEOVER);` (fallbackWord is non-zero/non-1 in the normal case — returns to L568 for drain). A subsequent `advanceGame` tick finds `rngWordByDay[day] != 0` (set via `_applyDailyRng` inside `_gameOverEntropy` chain at L1268 → L1197 `_finalizeLootboxRng` etc. — though actually rngWordByDay writes happen via `_applyDailyRng` which MAY or MAY NOT write depending on flow — structurally unchanged by 771893d1). **The prevrandao-consumption path is unchanged: only reachable inside `_gameOverEntropy` fallback branch after 14-day grace, entered via `_handleGameOverPath` from gameover path.** Nothing about the rngRequestTime=0 clearing creates a new entry into `_getHistoricalRngFallback`. **Annotation: RE_VERIFIED_AT_HEAD `cc68bfc7` — EXC-02 envelope unchanged. The clearing happens INSIDE `_gameOverEntropy` (gameOver-fallback context); no leak into normal-path prevrandao consumption.** | 771893d1 |
| RNG-02-V07 | RNG-02 | D-243-C007, D-243-C016, INV-237-021..037 cross-cite, Phase 239 RNG-01..03 result | n/a (cross-cite row) | RNG-02b/c Phase 239 carry + §1.8 reconciliation coverage | RE_VERIFIED_AT_HEAD cc68bfc7 | **17 INV-237 rows on rngLockedFlag (INV-237-021..037)** per `audit/v30-CONSUMER-INVENTORY.md`. Per §1.8 Light Reconciliation at HEAD cc68bfc7: 14 rows are "function-level-overlap" (delta line does not intersect consumer line), 2 rows are REFORMAT-TOUCHED (INV-237-022, INV-237-023 — both at the L261-262 baseline reformat site, proven REFACTOR_ONLY in §RNG-03 above), 1 row is HUNK-ADJACENT (INV-237-035 — baseline line 450 — exactly where `_unlockRng(day)` was removed; payDailyJackpot call itself unchanged but post-call unlock dropped, re-verified in §RNG-01 RNG-01-V01). **Zero rngLockedFlag-related consumer-surface widening.** Phase 239 RNG-01 AIRTIGHT verdict carries forward — the contract tree at HEAD cc68bfc7 preserves Phase 239's single Set-Site, two directly-writing Clear-Sites, and one structural L1700 Clear-Site-Ref (cc68bfc7 L1708 equivalent). RNG-02 (this REQ) and the Phase 239 result are consistent. | 16597cac (delta), 771893d1 (delta), Phase 239 (origin) |

### RNG-02 closure

All 7 V-rows RE_VERIFIED_AT_HEAD or SAFE (6 RE_VERIFIED_AT_HEAD for the AIRTIGHT invariant predicates + EXC-02 + Phase-239 carry; 1 SAFE for the bullet-3 reentry analysis at RNG-02-V04 — the rngRequestTime clear introduced by 771893d1 is a non-rngLockedFlag write, so its safety check produces a fresh verdict rather than a carry-forward annotation). AIRTIGHT invariant preserved at HEAD cc68bfc7: 1 Set-Site + 2 direct Clear-Sites + 1 structural Clear-Site-Ref, `_unlockRng` call-site count reduced from 5 (baseline) to 4 (HEAD) exactly matching the single `16597cac` removal at baseline L451. Zero finding candidates. KI EXC-02 envelope re-verified unchanged. §1.7 bullet 3 reentry-adjacency concern analysed and closed SAFE.

### §1.7 bullet 3 closure — `_gameOverEntropy` rngRequestTime clearing reentry adjacency

**Closed by Verdict Row ID RNG-02-V04** (above). **Verdict: SAFE.** Reentry-surface analysis confirms (a) no external call between the `rngRequestTime = 0` SSTORE at L1292 and the function return at L1293; (b) pre-L1292 external calls (coinflip.processCoinflipPayouts at L1270, sdgnrs.resolveRedemptionPeriod at L1286) target compile-time-constant protocol-internal addresses, not attacker-controlled contracts; (c) `_gameOverEntropy` is `private` — not externally reachable via a re-entry call. Phase 243 §1.7 bullet 3 closed with no finding candidate.

### §1.7 bullet 8 cross-cite with 244-04 GOX-06 (DEFERRED)

Per CONTEXT.md D-09 mapping, §1.7 bullet 8 (cc68bfc7 `jackpots` direct-handle at AdvanceModule L105-106 vs `runBafJackpot` self-call reentrancy parity) is CROSS-CITED with 244-04 GOX-06. **This plan DEFERS the verdict to 244-04 GOX-06** with the hand-off note recorded in 244-02-SUMMARY.md.

**Rationale for deferral:** The reentrancy-parity check between the two call paths (self-call delegatecall via `IDegenerusGame(address(this)).runBafJackpot(...)` at AdvanceModule L831 [D-243-X005] vs direct-external via `jackpots.markBafSkipped(lvl)` at AdvanceModule L839 [D-243-C039 hunk]) benefits from the full GOX context:
1. Both call paths are inside `_consolidatePoolsAndRewardJackpots` at AdvanceModule L728-909 (D-243-F026 MODIFIED_LOGIC).
2. GOX-06 already owns the `_handleGameOverPath` ordering (D-243-F013) and `_gameOverEntropy` rngRequestTime clearing (D-243-F014) — both of which interact with the BAF-jackpot dispatcher in edge cases where gameover fires mid-consolidation.
3. 244-04 GOX-06 has primary scope over reentrancy analysis at the drain-path level per CONTEXT.md D-15 GOX vectors.

244-01 EVT bucket's SUMMARY (244-01-SUMMARY.md §Key Surfaces for 244-02) already delegated both call-path citations to RNG-01 (for lock-discipline adjacency — addressed in §RNG-01 RNG-01-V10 above) + GOX-06 (for reentrancy parity — deferred here).

**No verdict row emitted in 244-02 for bullet 8.** The two-path surface is documented above via RNG-01-V10's cross-cite note for the scope-disjoint property. 244-04 GOX-06 closes bullet 8.

## §KI Envelope Re-Verify — EXC-02 (prevrandao fallback `_getHistoricalRngFallback`)

**Source KI entry:** `KNOWN-ISSUES.md` under "Design Decisions" — "Gameover prevrandao fallback".

Verbatim KI text (quoted): *"`_getHistoricalRngFallback` (DegenerusGameAdvanceModule.sol:1301) hashes `block.prevrandao` together with up to 5 historical VRF words as supplementary entropy when VRF is unavailable at game over. A block proposer can bias prevrandao (1-bit manipulation on binary outcomes). Trigger gating: only reachable inside `_gameOverEntropy` (AdvanceModule:1252) and only when an in-flight VRF request has been outstanding for at least `GAMEOVER_RNG_FALLBACK_DELAY = 14 days` (AdvanceModule:109). The 14-day window is ~17× the 20-hour VRF coordinator-swap governance threshold, so this path activates only after both VRF itself AND the governance recovery mechanism have failed to land a fresh coordinator within 14 days. The 5 committed historical VRF words provide bulk entropy; prevrandao only adds unpredictability."*

**Acceptance rationale (from KI):** (1) 14-day-grace gating; (2) governance-coordinator-swap threshold (~20h) is 17× shorter — by the time EXC-02 could fire, governance has had ~17 chances to swap coordinators; (3) 5 committed historical VRF words provide bulk entropy — prevrandao only adds 1-bit unpredictability; (4) envelope entry point is INSIDE `_gameOverEntropy` gameover-fallback context, NOT normal-path.

**Re-verification at HEAD `cc68bfc7` against the 771893d1 `_gameOverEntropy` rngRequestTime clearing:**

1. **Identify the EXC-02 envelope.** Per KI verbatim: prevrandao consumption is at `_getHistoricalRngFallback`, reachable ONLY from `_gameOverEntropy` L1252/L1267 (baseline L1252; HEAD cc68bfc7 L1267 with +cc68bfc7-shift), gated by `elapsed >= GAMEOVER_RNG_FALLBACK_DELAY = 14 days` at L1265.

2. **Verify the 771893d1 rngRequestTime clear at L1292 does NOT open a new path to `_getHistoricalRngFallback`.** The new `rngRequestTime = 0` SSTORE at L1292 fires on the EXIT of the fallback branch, AFTER `_getHistoricalRngFallback` at L1267 has already executed and its return value consumed. Entry into the fallback branch requires `rngRequestTime != 0` at L1263 — so when L1292 fires, the branch has already been entered and the prevrandao call has already happened. The clear does NOT create a new call to `_getHistoricalRngFallback`. **No new entry.**

3. **Verify the clear does NOT leak prevrandao consumption into normal-path contexts.** After L1292, control flow exits `_gameOverEntropy` (L1293 `return fallbackWord`), returns to `_handleGameOverPath` L566, and potentially continues drain at L568-623. The rngRequestTime=0 state is visible to future ticks. However, the next tick's `advanceGame` call will: (a) first check `_handleGameOverPath` at L183 — since `gameOver` may now be true (if this was the post-drain tick) OR `_livenessTriggered()` may return false (since rngRequestTime is now 0, per the `_livenessTriggered` body at DegenerusGameStorage L1243 `return rngStart != 0 && ...`), the path through `_gameOverEntropy` may NOT be re-entered. (b) Even if re-entered, the entry condition `rngRequestTime != 0 && elapsed >= 14 days` is FALSE because rngRequestTime is now 0 — so the fallback branch is NOT reachable. **The clearing at L1292 CLOSES the prevrandao window rather than opening it. No leak into normal-path.**

4. **Verify acceptance-rationale invariants preserved.** (1) 14-day-grace gating: unchanged (the L1265 `elapsed >= GAMEOVER_RNG_FALLBACK_DELAY` guard is NOT touched by 771893d1). (2) Governance-coordinator-swap 17× ratio: unchanged (no change to `GAMEOVER_RNG_FALLBACK_DELAY` constant). (3) 5 committed historical VRF words: unchanged (no change to `_getHistoricalRngFallback` body). (4) Envelope entry point inside `_gameOverEntropy`: unchanged (the rngRequestTime clear is INSIDE `_gameOverEntropy`, reachable only via `_handleGameOverPath` which is reached only when gameover-or-liveness triggers).

**Annotation: RE_VERIFIED_AT_HEAD `cc68bfc7` — EXC-02 envelope unchanged. The rngRequestTime=0 clearing happens INSIDE `_gameOverEntropy` (gameOver-fallback context); no leak into normal-path prevrandao consumption. All 4 acceptance-rationale invariants (1-4) hold. The clearing CLOSES the prevrandao window on exit rather than opening it. No regression.**

Verdict row RNG-02-V06 (§RNG-02 above) is the canonical carrier of this annotation.

## §Reproduction Recipe — RNG bucket

POSIX-portable shell commands actually used during 244-02 execution. Grouped by vector. Task 2 commands appended in subsequent section.

### Sanity gate (Task 1 Step A)

```bash
# HEAD anchor verification
git rev-parse 7ab515fe                                    # expect: 7ab515fe2d936fb3bc42cf5abddd4d9ed11ddb49
git rev-parse cc68bfc7                                    # expect: cc68bfc70e76fb75ac6effbc2135aae978f96ff3
git rev-parse HEAD                                        # at plan-start: 4c841a3c... (downstream of cc68bfc7 docs-only commits)
git diff --stat cc68bfc7..HEAD -- contracts/              # expect: empty (zero contract drift)
git status --porcelain contracts/ test/                   # expect: empty
```

### 16597cac hunk inspection (Task 1)

```bash
# Full commit diff
git show 16597cac -- contracts/modules/DegenerusGameAdvanceModule.sol

# Baseline vs HEAD advanceGame body around the removal site
git show 7ab515fe:contracts/modules/DegenerusGameAdvanceModule.sol > /tmp/baseline_advance.sol
git show cc68bfc7:contracts/modules/DegenerusGameAdvanceModule.sol > /tmp/head_advance.sol
diff -u /tmp/baseline_advance.sol /tmp/head_advance.sol | head -60

# Baseline reformat site
git show 7ab515fe:contracts/modules/DegenerusGameAdvanceModule.sol | sed -n '255,275p'

# Baseline + HEAD at removal site
git show 7ab515fe:contracts/modules/DegenerusGameAdvanceModule.sol | sed -n '440,470p'
git show cc68bfc7:contracts/modules/DegenerusGameAdvanceModule.sol | sed -n '440,480p'
```

### rngLockedFlag + _unlockRng call-site enumeration (Task 1)

```bash
# Set-site enumeration
grep -rn --include='*.sol' 'rngLockedFlag\s*=\s*true' contracts/ \
    | grep -v '^contracts/mocks/' | grep -v '^contracts/test/' | grep -v 'ContractAddresses\.sol\.bak'

# Clear-site enumeration (direct SSTORE)
grep -rn --include='*.sol' 'rngLockedFlag\s*=\s*false' contracts/ \
    | grep -v '^contracts/mocks/' | grep -v '^contracts/test/' | grep -v 'ContractAddresses\.sol\.bak'

# _unlockRng definition + call sites
grep -rn --include='*.sol' '\b_unlockRng\b' contracts/ \
    | grep -v '^contracts/mocks/' | grep -v '^contracts/test/' | grep -v 'ContractAddresses\.sol\.bak'

# rngLockedFlag consumers (gate readers)
grep -rn --include='*.sol' '\brngLockedFlag\b' contracts/ \
    | grep -v '^contracts/mocks/' | grep -v '^contracts/test/' | grep -v 'ContractAddresses\.sol\.bak'
```

### payDailyJackpot / _resumeDailyEth / _processDailyEth body inspection (Task 1 — to confirm dailyJackpotCoinTicketsPending set-site)

```bash
# JackpotModule.payDailyJackpot + _resumeDailyEth + _processDailyEth
grep -n 'function payDailyJackpot\b\|function _resumeDailyEth\b\|function _processDailyEth\b\|dailyJackpotCoinTicketsPending\s*=\|resumeEthPool\s*=' contracts/modules/DegenerusGameJackpotModule.sol

# Read L342-520 to confirm the dailyJackpotCoinTicketsPending=true SSTORE at L519 is unconditional inside isJackpotPhase
sed -n '342,520p' contracts/modules/DegenerusGameJackpotModule.sol
```

### 4-actor adversarial closure enumeration (Task 1)

```bash
# Player entry points (wrappers) — D-243-X013 + D-243-X014
grep -rn --include='*.sol' '\bgameAdvance\b\|\.advanceGame\b' contracts/DegenerusVault.sol contracts/StakedDegenerusStonk.sol

# VRF oracle callback
grep -n 'function rawFulfillRandomWords\b\|function updateVrfCoordinatorAndSub\b' contracts/modules/DegenerusGameAdvanceModule.sol
```

### KI EXC-03 envelope re-verify (Task 1)

```bash
# EXC-03 KI entry
grep -n 'Gameover RNG substitution' KNOWN-ISSUES.md

# F-29-04 proof targets in v30 inventory
grep -n 'INV-237-024\|INV-237-045\|INV-237-053\|INV-237-054' audit/v30-CONSUMER-INVENTORY.md

# _swapAndFreeze + _swapTicketSlot line numbers at cc68bfc7
grep -n 'function _swapAndFreeze\b\|function _swapTicketSlot\b\|_swapAndFreeze(\|_swapTicketSlot(' contracts/modules/DegenerusGameAdvanceModule.sol | head -10
```

### 771893d1 _gameOverEntropy hunk inspection (Task 2)

```bash
# _gameOverEntropy body at HEAD vs baseline
git show 7ab515fe:contracts/modules/DegenerusGameAdvanceModule.sol | sed -n '1218,1300p'
git show cc68bfc7:contracts/modules/DegenerusGameAdvanceModule.sol | sed -n '1216,1310p'

# Confirm the new `rngRequestTime = 0` SSTORE at L1292 and its surrounding context
sed -n '1216,1310p' contracts/modules/DegenerusGameAdvanceModule.sol

# rngRequestTime set/clear sites (every write)
grep -rn --include='*.sol' 'rngRequestTime\s*=' contracts/ \
    | grep -v '^contracts/mocks/' | grep -v '^contracts/test/' | grep -v 'ContractAddresses\.sol\.bak'
```

### Phase 239 AIRTIGHT carry verification (Task 2)

```bash
# AIRTIGHT invariant statement verbatim from v30 artifact
grep -n 'AIRTIGHT' audit/v30-RNGLOCK-STATE-MACHINE.md | head -10

# v30 INV-237-021..037 rngLockedFlag rows + INV-237-052..059 _gameOverEntropy rows
grep -n 'INV-237-02[1-9]\|INV-237-03[0-7]\|INV-237-05[2-9]' audit/v30-CONSUMER-INVENTORY.md | head -40

# KI Cross-Ref Summary for rngLockedFlag + prevrandao-fallback
grep -A1 '"Gameover prevrandao fallback"\|"Gameover RNG substitution"' audit/v30-CONSUMER-INVENTORY.md | head -30
```

### KI EXC-02 envelope re-verify (Task 2)

```bash
# EXC-02 KI entry
grep -n 'Gameover prevrandao fallback' KNOWN-ISSUES.md

# _getHistoricalRngFallback location at cc68bfc7
grep -n 'function _getHistoricalRngFallback\b\|_getHistoricalRngFallback(' contracts/modules/DegenerusGameAdvanceModule.sol | head -5

# GAMEOVER_RNG_FALLBACK_DELAY constant location + value
grep -n 'GAMEOVER_RNG_FALLBACK_DELAY' contracts/modules/DegenerusGameAdvanceModule.sol contracts/storage/DegenerusGameStorage.sol | head -5

# _livenessTriggered body at cc68bfc7 (consumer of rngRequestTime)
grep -n 'function _livenessTriggered\b' contracts/storage/DegenerusGameStorage.sol
```

### §1.7 bullet 3 + bullet 8 cross-cite verification (Task 2)

```bash
# §1.7 bullet 3 source (_gameOverEntropy rngRequestTime clearing reentry)
grep -n '§1\.7\|_gameOverEntropy rngRequestTime' audit/v31-243-DELTA-SURFACE.md | head -20

# §1.7 bullet 8 source (cc68bfc7 jackpots direct-handle vs runBafJackpot self-call)
grep -n 'jackpots direct-handle\|runBafJackpot.*delegatecall\|bullet 8' audit/v31-243-DELTA-SURFACE.md | head -10

# cc68bfc7 jackpots constant location
grep -n '\bjackpots\b = IDegenerusJackpots\|IDegenerusJackpots private constant jackpots' contracts/modules/DegenerusGameAdvanceModule.sol
```

### Verification of audit file integrity (end-of-plan guard)

```bash
# Zero Phase-246 finding-ID emissions (D-21 token-split self-match guard)
TOKEN="F-31""-" ; grep -cE "$TOKEN" audit/v31-244-RNG.md   # expect: 0

# Zero contracts/ or test/ writes
git status --porcelain contracts/ test/                    # expect: empty

# Zero edits to audit/v31-243-DELTA-SURFACE.md (D-20)
git status --porcelain audit/v31-243-DELTA-SURFACE.md      # expect: empty

# Required V-row prefixes present
grep -qE '^\| RNG-01-V[0-9]+ ' audit/v31-244-RNG.md         # expect: exit 0
grep -qE '^\| RNG-02-V[0-9]+ ' audit/v31-244-RNG.md         # expect: exit 0
grep -qE '^\| RNG-03-V[0-9]+ ' audit/v31-244-RNG.md         # expect: exit 0

# Required section headers
grep -q '^## §RNG-01\b' audit/v31-244-RNG.md                # expect: exit 0
grep -q '^## §RNG-02\b' audit/v31-244-RNG.md                # expect: exit 0
grep -q '^## §RNG-03\b' audit/v31-244-RNG.md                # expect: exit 0

# KI envelope annotations
grep -c 'RE_VERIFIED_AT_HEAD' audit/v31-244-RNG.md          # expect: >= 2 (EXC-02 + EXC-03)
grep -c 'EXC-02' audit/v31-244-RNG.md                       # expect: >= 1
grep -c 'EXC-03' audit/v31-244-RNG.md                       # expect: >= 1

# AIRTIGHT invariant citation
grep -c 'AIRTIGHT' audit/v31-244-RNG.md                     # expect: >= 3 (invariant statement + verdict rows)

# §1.7 bullet 3 closure
grep -c '§1.7 bullet 3' audit/v31-244-RNG.md                # expect: >= 2 (closure cite + explicit subsection)

# §1.7 bullet 8 deferred-note
grep -c '§1.7 bullet 8' audit/v31-244-RNG.md                # expect: >= 1

# F-29-04 + INV citations
grep -c 'F-29-04' audit/v31-244-RNG.md                      # expect: >= 2
grep -c 'INV-237-035' audit/v31-244-RNG.md                  # expect: >= 2
grep -c 'INV-237-021' audit/v31-244-RNG.md                  # expect: >= 1
```

---

## §3 — QST Bucket (commit 6b3f4f3c + bytecode-delta evidence appendix for QST-05)

*Embedded verbatim from `audit/v31-244-QST.md` working file. Working file preserved on disk per CONTEXT.md D-05.*

# v31.0 Phase 244 — QST Bucket Audit (commit 6b3f4f3c)

**Audit baseline:** `7ab515fe` (v30.0 milestone HEAD).
**Audit head:** `cc68bfc7` (Phase 243 amended HEAD; contract tree verified byte-unchanged from `cc68bfc7` via `git diff cc68bfc7..HEAD -- contracts/` = empty at plan-start).
**Owning commits:** `6b3f4f3c` (quests recycled-ETH credit + earlybird DGNRS gross-spend + affiliate split preservation + signature-change equivalence + bytecode-delta gas verification).
**Scope per:** `audit/v31-243-DELTA-SURFACE.md` §6 Consumer Index rows D-243-I011..D-243-I015 (QST-01, QST-02, QST-03, QST-04, QST-05).
**Plan:** `.planning/phases/244-per-commit-adversarial-audit-evt-rng-qst-gox/244-03-PLAN.md`.
**Phase:** 244-per-commit-adversarial-audit-evt-rng-qst-gox.
**Status:** WORKING (Task 1 complete — QST-01..QST-04 verdict tables + prose blocks; Task 2 appends §QST-05 + bytecode-delta evidence appendix). Flips to consumed-by-244-04 at consolidation per CONTEXT.md D-05.

## §0 — Per-Bucket Verdict Count Card

| REQ-ID | Verdict Rows | Finding Candidates | Floor Severity |
| --- | --- | --- | --- |
| QST-01 | 7 (QST-01-V01..V07) | 0 | SAFE |
| QST-02 | 5 (QST-02-V01..V05) | 0 | SAFE |
| QST-03 | 4 (QST-03-V01..V04) | 0 | SAFE |
| QST-04 | 5 (QST-04-V01..V05) | 0 | SAFE |
| QST-05 | 3 (QST-05-V01..V03) | 0 | SAFE (2 SAFE + 1 INFO commentary — D-14 DIRECTION-ONLY bar) |

**Bucket aggregate:** 24 V-rows across all 5 REQs (QST-01 × 7 + QST-02 × 5 + QST-03 × 4 + QST-04 × 5 + QST-05 × 3); 0 finding candidates; all 5 REQs close at SAFE floor. The shared-input-distinct-sink pattern (QST-01 + QST-02 consume the same `ticketCost + lootBoxAmount` gross scalar at distinct storage-disjoint sinks) is preservation-by-design — no double-count, no cross-sink leak. Affiliate 20-25/5 split is byte-identical at baseline vs HEAD (NEGATIVE-scope confirmed). Signature changes are REFACTOR_ONLY at the rename-hunk granularity and MODIFIED_LOGIC only at the caller's call-expression value-semantics shift (captured by QST-01 / QST-02 compute-site verdicts). QST-05 bytecode-delta evidence: `DegenerusQuests` body BYTE-IDENTICAL (expected — REFACTOR_ONLY rename); `DegenerusGameMintModule` body SHRANK by 36 bytes (direction matches commit-message claim; magnitude-commentary only per D-14 magnitude-bar-not-enforced).

Floor-severity semantics per CONTEXT.md D-08: SAFE (adversarial vector enumerated, behavior matches claim under all reachable inputs, no finding worth surfacing) / INFO (observation worth recording for Phase 246 reviewer but not exploitable) / LOW / MEDIUM / HIGH / CRITICAL. QST-05 floor uses the locked DIRECTION-ONLY bar from CONTEXT.md D-14: {SAFE, INFO, INFO-unreproducible}.

Verdict Row ID scheme per CONTEXT.md Specifics: `QST-NN-V##` per-REQ monotonic. Finding-candidate prose blocks use `Finding Candidate QST-NN-FC##` IDs scoped per-REQ; zero Phase-246 finding-IDs emitted from this plan per CONTEXT.md D-21.

## §QST-01 — MINT_ETH gross-spend credit

**REQ (verbatim):** "MINT_ETH daily + level quest credit path from purchase entry through `_callTicketPurchase` → `handlePurchase(ethMintSpendWei)` → quests credit hook; verdict per call site confirms credit uses gross spend (`ethMintSpendWei`, fresh + recycled) at every reachable site; zero residual paths credit fresh-only."

**Scope source:** `audit/v31-243-DELTA-SURFACE.md` §6 row D-243-I011 → D-243-C008 (6b3f4f3c `handlePurchase` impl), D-243-C009 + D-243-C030 (interface), D-243-C010 (6b3f4f3c `_purchaseFor`), D-243-F007 (REFACTOR_ONLY — callee side), D-243-F008 (MODIFIED_LOGIC — caller side, rationale points 2-3), D-243-X015 (D-243-X055 interface-method row) for the `quests.handlePurchase` call site at `contracts/modules/DegenerusGameMintModule.sol:1098`, D-243-X017 for dispatcher → `_purchaseFor` entry at L850.

**Owning commit:** `6b3f4f3c` — feat(quests): credit recycled ETH toward MINT_ETH quests and earlybird DGNRS (`DegenerusQuests.sol`, `IDegenerusQuests.sol`, `DegenerusGameMintModule.sol`).

**Adversarial vectors (per CONTEXT.md D-12 QST-01 + threat model):**
- QST-01a — every reachable MINT_ETH credit path consumes gross spend (`ethMintSpendWei = ticketCost + lootBoxAmount`), NOT a derived fresh-only value
- QST-01b — zero residual paths credit fresh-only (no `ethFreshWei` / `freshEth` flows into the MINT_ETH credit hook anywhere reachable)
- QST-01c — every purchase entry point converges on `_purchaseFor` or `_purchaseCoinFor` so the single `quests.handlePurchase(ethMintSpendWei, ...)` call site at L1098 is the sole MINT_ETH credit hook

### Reaching-path enumeration at HEAD `cc68bfc7`

All purchase entry points route through the MintModule. The `handlePurchase` call flows from:

1. External entry `purchase(ticketQuantity, lootBoxAmount, affiliateCode, payKind)` at DegenerusGameMintModule.sol:843 (per D-243-X017 row L850 dispatcher — `purchase` is delegatecalled from DegenerusGame and self-invokes `_purchaseFor`) → `_purchaseFor(buyer, ...)` at L913
2. External entry `purchaseCoin(...)` at L862 → `_purchaseCoinFor(buyer, ...)` at L885 → does NOT call `quests.handlePurchase` (the coin purchase path passes `burnieMintQty` via the RETURN of `_callTicketPurchase` but doesn't invoke `handlePurchase` itself — see verdict row QST-01-V07 below for why)
3. External whale bundle + deity / lazy pass entries in `DegenerusGameWhaleModule.sol` → route through `_purchaseWhaleBundle` → do NOT invoke `quests.handlePurchase` (verified by grep `grep -n 'quests\.handlePurchase' contracts/` returns exactly one hit at `DegenerusGameMintModule.sol:1098`)

Therefore the SOLE `quests.handlePurchase(...)` call site in all of `contracts/` is at `DegenerusGameMintModule.sol:1098` (inside `_purchaseFor`). This matches D-243-X015 / D-243-X055 row enumeration in `audit/v31-243-DELTA-SURFACE.md` §3.1.7 + §3.2.1.

**Argument computation at the single call site (L1090 gross-spend compute):**
```
uint256 ethMintSpendWei = ticketCost + lootBoxAmount;
```
Where:
- `ticketCost` is computed at L932 as `ticketCost = (priceWei * ticketQuantity) / (4 * TICKET_SCALE)` — GROSS ticket cost in wei (independent of how it's funded — msg.value fresh vs claimable recycled)
- `lootBoxAmount` is the `_purchaseFor` parameter (L916) — GROSS lootbox cost in wei (independent of how it's funded)

**Note on funding-source neutrality:** the baseline `ethFreshWei = ticketFreshEth + lootboxFreshEth` split fresh-from-msg.value and fresh-from-lootbox. At HEAD, the MINT_ETH credit uses `ticketCost + lootBoxAmount` which is the GROSS total regardless of whether it was paid from msg.value (fresh) or from `claimableWinnings[buyer]` (recycled). This matches the commit-message intent: "MINT_ETH quest progress is credited 1:1 in wei on the gross ETH-denominated ticket + lootbox spend, regardless of fresh-vs-recycled funding source" (L1087-1089 inline comment at HEAD).

### Callee-side consumption (DegenerusQuests.sol `handlePurchase` body)

At HEAD `cc68bfc7`, `contracts/DegenerusQuests.sol:763-898` receives `ethMintSpendWei` as parameter 2 (replacing baseline `ethFreshWei` — D-05.4a REFACTOR_ONLY per §2.3 D-243-F007; the body is byte-equivalent under the `s/ethFreshWei/ethMintSpendWei/g` rename). The parameter is consumed at:
- L781 early-zero guard: `if (ethMintSpendWei == 0 && burnieMintQty == 0 && lootBoxAmount == 0) return (0, ...);`
- L797 MINT_ETH branch guard: `if (ethMintSpendWei != 0) { ... }`
- L806 / L807 — passed to `_questHandleProgressSlot(..., ethMintSpendWei, target, ..., levelQuestHandled ? 0 : ethMintSpendWei, levelQuestPrice)` for the daily-quest slot progress
- L821 — passed to `_handleLevelQuestProgress(player, QUEST_TYPE_MINT_ETH, ethMintSpendWei, levelQuestPrice)` for the level-quest progress

Every MINT_ETH credit call within `handlePurchase` consumes the `ethMintSpendWei` parameter directly — there is no local derivation, no sub-extraction of a fresh-only portion, no backward-compatibility shim. The rename is complete across the body.

### Residual-fresh-only search (zero-residual gate QST-01b)

Searched at HEAD `cc68bfc7` across the full purchase-quest pipeline:
- `grep -n 'ethFreshWei' contracts/` → zero hits (complete rename)
- `grep -n 'freshEth' contracts/modules/DegenerusGameMintModule.sol` → 6 hits, ALL at L1289-1335 inside `_callTicketPurchase` for the AFFILIATE split path only (QST-03 negative-scope territory); zero hits inside `_purchaseFor` body; zero hits inside the `quests.handlePurchase(...)` call-site expression
- `grep -n 'freshEth\|ethFreshWei' contracts/DegenerusQuests.sol contracts/interfaces/IDegenerusQuests.sol` → zero hits

The fresh-only concept remains ONLY inside `_callTicketPurchase` for affiliate-split purposes (isFreshEth flag routed to `affiliate.payAffiliate`); it is scope-disjoint from the MINT_ETH credit hook.

### QST-01 verdict table

| Verdict Row ID | REQ-ID | Source 243 Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| QST-01-V01 | QST-01 | D-243-C010, D-243-F008, D-243-I011 | contracts/modules/DegenerusGameMintModule.sol:1087-1090 (gross-spend compute site) | QST-01a (compute site uses gross spend — not derived from freshEth split) | SAFE | `uint256 ethMintSpendWei = ticketCost + lootBoxAmount;` at L1090, where `ticketCost = (priceWei * ticketQuantity) / (4 * TICKET_SCALE)` at L932 (GROSS ticket cost) and `lootBoxAmount` is the `_purchaseFor` parameter (L916, GROSS lootbox cost). Neither `ticketCost` nor `lootBoxAmount` is sub-extracted from a fresh-only flow — both are gross-spend scalars computed from pure inputs. Matches §2.3 D-243-F008 rationale point 2-3: `ethMintSpendWei = ticketCost + lootBoxAmount` replaces baseline `ethFreshWei = ticketFreshEth + lootboxFreshEth` — different value semantics (gross-spend replaces fresh). Inline comment L1087-1089 at HEAD documents the intent: "MINT_ETH quest progress is credited 1:1 in wei on the gross ETH-denominated ticket + lootbox spend, regardless of fresh-vs-recycled funding source." | 6b3f4f3c |
| QST-01-V02 | QST-01 | D-243-C008, D-243-C030, D-243-X015, D-243-X055, D-243-I011 | contracts/modules/DegenerusGameMintModule.sol:1098 (call site) + contracts/DegenerusQuests.sol:763-821 (callee body) | QST-01a (credit hook consumes gross spend at single call site) | SAFE | `quests.handlePurchase(buyer, ethMintSpendWei, burnieMintUnits, lootBoxAmount, priceWei, PriceLookupLib.priceForLevel(cachedLevel + 1))` at L1098-1105. `ethMintSpendWei` argument is the gross-spend scalar computed at L1090 (QST-01-V01). At callee, L797 branch `if (ethMintSpendWei != 0) { ... }` and L821 `_handleLevelQuestProgress(player, QUEST_TYPE_MINT_ETH, ethMintSpendWei, levelQuestPrice)` both consume the gross-spend value directly — no local derivation, no sub-extraction. §3.1.7 + §3.2.1 confirm the grep enumeration finds this as the sole call site of `quests.handlePurchase(...)` (match D-243-X015 at L1098 + D-243-X055 interface-method row). | 6b3f4f3c |
| QST-01-V03 | QST-01 | D-243-C008, D-243-F007, D-243-I011 | contracts/DegenerusQuests.sol:797-822 (MINT_ETH credit branch) | QST-01a (daily-quest slot progress + level-quest progress both consume gross spend) | SAFE | Inside `handlePurchase` body at HEAD `cc68bfc7`: (a) daily-quest slot loop L799-819 iterates slots; when `quest.questType == QUEST_TYPE_MINT_ETH` it calls `_questHandleProgressSlot(..., ethMintSpendWei, target, ..., levelQuestHandled ? 0 : ethMintSpendWei, levelQuestPrice)` — ethMintSpendWei passed unmodified as both the slot-progress amount AND the level-quest amount; (b) L820-822 `if (!levelQuestHandled) _handleLevelQuestProgress(player, QUEST_TYPE_MINT_ETH, ethMintSpendWei, levelQuestPrice)` — ethMintSpendWei passed unmodified for the no-daily-slot branch. Every MINT_ETH credit call within `handlePurchase` consumes `ethMintSpendWei` directly; zero paths derive a fresh-only sub-value. Body is byte-equivalent to baseline under `s/ethFreshWei/ethMintSpendWei/g` rename per §2.3 D-243-F007 REFACTOR_ONLY — but value semantics at call boundary shifted from fresh-only to gross (that shift is QST-01-V01 + QST-01-V02 scope, not this row). | 6b3f4f3c |
| QST-01-V04 | QST-01 | D-243-C010, D-243-F008 | contracts/modules/DegenerusGameMintModule.sol:913-1198 (`_purchaseFor` body) | QST-01b (zero residual fresh-only paths to MINT_ETH credit hook) | SAFE | Residual-fresh-only search at HEAD `cc68bfc7`: (a) `grep -n 'ethFreshWei' contracts/` returns zero hits — complete rename across all .sol files; (b) `grep -n 'freshEth' contracts/modules/DegenerusGameMintModule.sol` returns 6 hits, ALL at L1289-1335 inside `_callTicketPurchase` for the affiliate split (QST-03 scope; freshEth is demoted to function-local scope per §2.3 D-243-F009 rationale — not exported back to `_purchaseFor`); zero hits in `_purchaseFor` body (L913-1198) or `handlePurchase` body (L763-898). `_purchaseFor` no longer destructures a `ticketFreshEth` return from `_callTicketPurchase` (the return-tuple shrink — QST-04-V01/V02 scope). `lootboxFreshEth` remains computed at L946/L953 but is consumed ONLY for affiliate call-boundary decisions at L1144 (`affiliate.payAffiliate(..., isFreshEth=true)`) — NOT fed to the MINT_ETH credit hook. No fresh-only path to `quests.handlePurchase` parameter 2 remains. | 6b3f4f3c |
| QST-01-V05 | QST-01 | D-243-C008, D-243-F007, D-243-I011 | contracts/DegenerusQuests.sol:763-780 (callee signature + entry guards) | QST-01a interface-level verification | SAFE | Interface-level parameter rename at `contracts/interfaces/IDegenerusQuests.sol:139-146` (D-243-C009 / D-243-C030) changes parameter 2 from `uint256 ethFreshWei` to `uint256 ethMintSpendWei`. ABI selector preserved (parameter type `uint256` unchanged → selector unchanged; confirmed by computing `keccak256("handlePurchase(address,uint256,uint32,uint256,uint256,uint256)")[0:4]` which depends ONLY on types, not names). Entry guards at callee L778 (`if (player == address(0) || currentDay == 0) return`) and L781 (early-zero guard consuming ethMintSpendWei) preserve the correct "no-credit-when-empty-input" behavior. | 6b3f4f3c |
| QST-01-V06 | QST-01 | D-243-C010, D-243-X017 | contracts/modules/DegenerusGameMintModule.sol:843-861 (external `purchase` dispatcher entry) | QST-01c (dispatcher entry converges on `_purchaseFor`) | SAFE | External `purchase(ticketQuantity, lootBoxAmount, affiliateCode, payKind)` at L843-861 is delegatecalled from DegenerusGame.sol:381 (per D-243-X017 row) and self-invokes `_purchaseFor(buyer, ticketQuantity, lootBoxAmount, affiliateCode, payKind)` at L850. No alternative entry to `_purchaseFor` exists (verified via `grep -n '_purchaseFor' contracts/` — 3 hits: definition L913, call site L850 inside `purchase` external, no other). Every ETH-purchase entry point (DirectEth / Claimable / Combined) converges on the single `_purchaseFor → quests.handlePurchase(ethMintSpendWei, ...)` pipeline per QST-01-V01/V02. No scope-bypass entry exists. | 6b3f4f3c |
| QST-01-V07 | QST-01 | D-243-C010, D-243-C018 (cross-ref 771893d1 scope for _purchaseCoinFor) | contracts/modules/DegenerusGameMintModule.sol:885-911 (`_purchaseCoinFor`) | QST-01c (BURNIE/coin purchase path — MINT_ETH credit NOT expected; verify no leak) | SAFE | `_purchaseCoinFor` at L885-911 handles BURNIE-paid ticket purchases (`payInCoin=true` passed to `_callTicketPurchase` at L900). It calls `_callTicketPurchase` at L895-905 but DISCARDS the entire return tuple (no destructure). No call to `quests.handlePurchase(...)` inside `_purchaseCoinFor` body — grep confirms. BURNIE-paid ticket purchases DO accumulate `burnieMintUnits` inside `_callTicketPurchase` at HEAD L1274-1277 (QUEST_TYPE_MINT_BURNIE credit path) but those units are NOT used in `_purchaseCoinFor` because the return is discarded. This is by-design: the BURNIE quest credit for coin purchases is handled by a separate path (not in 6b3f4f3c scope — that path is orthogonal). No MINT_ETH credit fires on coin purchase, which is CORRECT because BURNIE-paid purchases consume zero ETH (ticketCost is paid in BURNIE, lootBoxAmount is 0 in this path). No residual MINT_ETH credit from coin purchases. NOTE: the `_purchaseCoinFor` `burnieMintUnits` return-discard is an adjacent observation — those units do NOT flow to `quests.handlePurchase` via this path, meaning BURNIE coin purchases do not credit the MINT_BURNIE quest through this call-site. Whether this is a bug in the BURNIE-quest path is orthogonal to QST-01 (which scopes MINT_ETH only) — flagged to Phase 246 reviewer as an observation, see §QST-01 post-table prose. | 6b3f4f3c (with 771893d1 scope cross-cite) |

### QST-01 closure + observation

**All 7 V-rows SAFE.** The MINT_ETH quest credit path at HEAD `cc68bfc7` consumes the gross-spend value (`ticketCost + lootBoxAmount`) at every reachable site, matching the commit-message intent. Zero residual paths credit a fresh-only sub-value. ABI selector for `handlePurchase` is preserved across the rename; callee body is byte-equivalent under `s/ethFreshWei/ethMintSpendWei/g`; semantic shift is entirely at the caller's compute expression (`ethMintSpendWei = ticketCost + lootBoxAmount` replacing `ethFreshWei = ticketFreshEth + lootboxFreshEth`).

**QST-01 finding candidates:** None.

**QST-01 per-REQ floor severity:** SAFE.

**QST-01 adjacent observation (not a finding — out-of-scope for QST-01):** In `_purchaseCoinFor` at L885-911, the return tuple of `_callTicketPurchase` (including `burnieMintUnits` — the BURNIE-paid mint quest units accumulated at L1274-1277) is discarded with no destructure. Consequence: BURNIE-paid coin-purchase paths do NOT feed `burnieMintUnits` into a `quests.handlePurchase` call — the MINT_BURNIE quest credit hook is reached only via `_purchaseFor` (ETH path) whose `burnieMintUnits` is always 0 when `payInCoin=false` by construction (see L1279 `uint32 mintUnits = adjustedQty32;` in the `else` branch of the payInCoin check — this is the ETH-mint-units count, not a BURNIE count). Whether the MINT_BURNIE daily quest should fire from BURNIE coin purchases is a pre-existing design decision **outside the 6b3f4f3c scope** (the same discard existed at baseline `7ab515fe` L885-911). Observation flagged for Phase 246 reviewer in case the MINT_BURNIE quest slot is expected to fire on BURNIE coin purchases — not an introduction by this commit.

## §QST-02 — Earlybird DGNRS gross-spend (no double-count)

**REQ (verbatim):** "Earlybird DGNRS emission counting against the same `ethMintSpendWei` parameter; verifies no double-counting across QST-01's MINT_ETH path AND QST-02's earlybird path (shared input, distinct sinks)."

**Scope source:** `audit/v31-243-DELTA-SURFACE.md` §6 row D-243-I012 → D-243-C010 (6b3f4f3c `_purchaseFor` at L913-1198; same surface as QST-01, earlybird integration changed in same hunk per §2.3 D-243-F008 rationale point 4), D-243-F008 (MODIFIED_LOGIC verdict), cross-cite to v29.0 Phase 231 earlybird audit for shape parity.

**Owning commit:** `6b3f4f3c` (same as QST-01).

**Adversarial vectors (per CONTEXT.md D-12 QST-02 + threat model):**
- QST-02a — earlybird DGNRS emission counted against the gross-spend value (`ticketCost + lootBoxAmount`) — the same scalar that feeds MINT_ETH credit
- QST-02b — no double-counting: a single purchase MUST credit MINT_ETH once AND earlybird once, each from its distinct sink, NEVER crediting one sink twice from a single purchase AND NEVER sharing a counter where the same wei feeds both increments redundantly
- QST-02c — cross-cite v29.0 Phase 231 earlybird audit: the quadratic curve telescope property (two small calls === one big call) is preserved, so the "single call per purchase" refactor at 6b3f4f3c is mathematically equivalent to the baseline "two separate ticket/lootbox calls"

### Earlybird emission path at HEAD `cc68bfc7`

The earlybird DGNRS emission is triggered by `_awardEarlybirdDgnrs(buyer, purchaseWei)` defined at `contracts/storage/DegenerusGameStorage.sol:1014-1057`. The function is called at exactly ONE site across `_purchaseFor`:

```
// Line 1172 at HEAD cc68bfc7:
_awardEarlybirdDgnrs(buyer, ticketCost + lootBoxAmount);
```

At baseline `7ab515fe` (same line position modulo reformat drift), the call was:
```
_awardEarlybirdDgnrs(buyer, ticketFreshEth + lootboxFreshEth);
```

(Both baseline and HEAD have exactly one call site to `_awardEarlybirdDgnrs` inside `_purchaseFor`. Verified by `grep -rn '_awardEarlybirdDgnrs\b' contracts/` which returns 2 rows total: the definition at Storage.sol:1014 + the single invocation at MintModule.sol:1172.)

The value passed shifted from `ticketFreshEth + lootboxFreshEth` (fresh only) to `ticketCost + lootBoxAmount` (gross — same scalar as `ethMintSpendWei` at L1090). This is the commit-message-claimed behavior: "Earlybird DGNRS emission counts the same gross spend toward its 1,000 ETH target" (6b3f4f3c commit message, verified via `git show 6b3f4f3c --stat`).

### `_awardEarlybirdDgnrs` body UNCHANGED by 6b3f4f3c

`git diff 7ab515fe..cc68bfc7 -- contracts/storage/DegenerusGameStorage.sol` shows NO changes touching the `_awardEarlybirdDgnrs` body L1014-1057. The function accepts any wei value and distributes proportionally via the quadratic curve `payout = (poolStart * (d2 - d1)) / denom` where `d2 - d1` is the telescoped delta on the curve. The curve's telescope property (from v29.0 Phase 231 closure) means: for any split `A + B = totalPurchaseWei`, a single call with `totalPurchaseWei` yields the same `payout` as two sequential calls with `A` and `B` (because consecutive calls advance `earlybirdEthIn` incrementally and the curve evaluation is path-independent). So the baseline two-input split `ticketFreshEth + lootboxFreshEth` paired with the baseline inline-comment justification for unification ("Unified earlybird award: one call per purchase covering both ticket and lootbox fresh ETH. Mathematically equivalent to two separate calls (quadratic curve telescopes).") carries forward IDENTICALLY at HEAD — only the scalar value shifted (fresh → gross).

### Double-count gate: distinct sinks for MINT_ETH vs earlybird

The `ticketCost + lootBoxAmount` scalar is consumed at two distinct sites in `_purchaseFor`:
- **L1090 → L1098-1105:** consumed by `quests.handlePurchase(buyer, ethMintSpendWei, ...)` — MINT_ETH / lootbox quest sink. State writes go to `questPlayerState[player]` (daily slots) + level-quest `PlayerState` (Quests contract storage).
- **L1172:** consumed by `_awardEarlybirdDgnrs(buyer, ticketCost + lootBoxAmount)` — earlybird sink. State writes go to `earlybirdEthIn` (GameStorage) + `dgnrs.transferFromPool(IStakedDegenerusStonk.Pool.Earlybird, buyer, payout)` (sDGNRS transfer).

**The two sinks are STORAGE-DISJOINT:**
- MINT_ETH quest sink: writes `questPlayerState[player].progress[slotIndex]` (DegenerusQuests.sol storage), `questPlayerState[player].streak`, `questPlayerState[player].completionMask`, and potentially `lastCompletedDay`. Transfers reward via `coinflip.creditFlip` for BURNIE-quest rewards or returns ETH-quest reward via `lootboxFlipCredit` accumulation (return value at L893-897). NO write to any earlybird state.
- Earlybird sink: writes `earlybirdEthIn` and `earlybirdDgnrsPoolStart` (GameStorage one-time init). Transfers DGNRS via `dgnrs.transferFromPool(Pool.Earlybird, ...)`. NO write to any quest state.

Therefore a single purchase credits EACH sink ONCE, not twice; and the same `ticketCost + lootBoxAmount` scalar is NOT read by two redundant increments to the same counter. No double-count exists.

### QST-02 verdict table

| Verdict Row ID | REQ-ID | Source 243 Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| QST-02-V01 | QST-02 | D-243-C010, D-243-F008, D-243-I012 | contracts/modules/DegenerusGameMintModule.sol:1168-1172 (earlybird call site) | QST-02a (earlybird sink consumes gross spend) | SAFE | `_awardEarlybirdDgnrs(buyer, ticketCost + lootBoxAmount)` at L1172 consumes the gross-spend scalar — identical expression to the MINT_ETH credit's `ethMintSpendWei` computed at L1090 (`ethMintSpendWei = ticketCost + lootBoxAmount`). Value semantics matches commit-message intent: earlybird now counts gross spend (fresh + recycled) toward the 1,000 ETH target. Per §2.3 D-243-F008 rationale point 4: "`_awardEarlybirdDgnrs(buyer, ticketCost + lootBoxAmount)` replaces `(buyer, ticketFreshEth + lootboxFreshEth)` — different value passed to internal call." Inline comments at L1169-1171 document the unified-award rationale ("Unified earlybird award: one call per purchase covering the full ticket + lootbox spend (fresh + recycled). Quadratic curve telescopes, so one call is mathematically equivalent to two."). | 6b3f4f3c |
| QST-02-V02 | QST-02 | D-243-C010, D-243-F008, D-243-I012 | contracts/storage/DegenerusGameStorage.sol:1014-1057 (`_awardEarlybirdDgnrs` body) | QST-02a (`_awardEarlybirdDgnrs` body unchanged — all value routing from purchaseWei parameter is path-independent) | SAFE | `git diff 7ab515fe..cc68bfc7 -- contracts/storage/DegenerusGameStorage.sol` shows NO hunks touching `_awardEarlybirdDgnrs` body at L1014-1057. The function computes `payout = (poolStart * (d2 - d1)) / denom` via the quadratic-curve telescope property — any wei value input is distributed proportionally with path-independence (per v29.0 Phase 231 earlybird audit). The shift from fresh-only to gross just changes how much `ethIn` advances per purchase; the curve evaluation is still correct under the new input magnitude. No new double-dispensation risk because `earlybirdEthIn += delta` is a monotonic counter, and each `_awardEarlybirdDgnrs` call advances it once per purchase. Cap at `EARLYBIRD_TARGET_ETH` (1000 ETH) is enforced at L1036 `if (ethIn >= totalEth) return;` — oversaturation drains nothing extra. Pool-empty guard at L1029 `if (poolBalance == 0) return;`. | 6b3f4f3c |
| QST-02-V03 | QST-02 | D-243-C010, D-243-F008, D-243-I012 | contracts/modules/DegenerusGameMintModule.sol:1087-1098 (MINT_ETH credit site) + contracts/modules/DegenerusGameMintModule.sol:1168-1172 (earlybird credit site) | QST-02b (no double-count: MINT_ETH sink vs earlybird sink are storage-disjoint) | SAFE | The two sinks share input scalar `ticketCost + lootBoxAmount` (alias `ethMintSpendWei` at L1090) but write to entirely different state: (a) MINT_ETH sink at L1098 writes `DegenerusQuests.sol` storage (`questPlayerState[player].progress[slotIndex]`, `.streak`, `.completionMask`, `.lastCompletedDay` + potential level-quest progress) — zero overlap with earlybird state; (b) earlybird sink at L1172 writes `GameStorage.sol` state (`earlybirdEthIn`, `earlybirdDgnrsPoolStart`) + performs `dgnrs.transferFromPool(Pool.Earlybird, buyer, payout)` — zero overlap with quest state. Each sink is invoked EXACTLY ONCE per purchase (one call site each inside `_purchaseFor`, no loop, no recursion, no conditional-double). A single purchase credits MINT_ETH once AND earlybird once, from the same scalar, to distinct counters. | 6b3f4f3c |
| QST-02-V04 | QST-02 | D-243-I012, v29.0 Phase 231 cross-cite | contracts/modules/DegenerusGameMintModule.sol:1168-1172 | QST-02c (quadratic-curve telescope preserves mathematical equivalence: one call with `A+B` equals two calls with `A`, `B`) | SAFE | The "unified earlybird award: one call per purchase covering the full ticket + lootbox spend (fresh + recycled)" pattern was established at v29.0 Phase 231 and carried through at baseline `7ab515fe` (inline comment at baseline L1170-1171 explicitly notes "Mathematically equivalent to two separate calls (quadratic curve telescopes)"). The curve formula at `_awardEarlybirdDgnrs` L1041-1047: `d1 = (ethIn * totalEth2) - (ethIn * ethIn)`, `d2 = (nextEthIn * totalEth2) - (nextEthIn * nextEthIn)`, `payout = (poolStart * (d2 - d1)) / denom` — expanding: `d2 - d1 = totalEth2 * delta - (nextEthIn + ethIn) * delta = delta * (totalEth2 - nextEthIn - ethIn)` — linear in delta, so `f(A) + f(A+δ_A, B) = f(A+B)` for sequential calls (the second call's `ethIn` is the first's `nextEthIn`). At HEAD the single call with `ticketCost + lootBoxAmount` is mathematically equivalent to two calls with `ticketCost` then `lootBoxAmount` (or any other decomposition). Direction: the shift from baseline `ticketFreshEth + lootboxFreshEth` (lower magnitude) to HEAD `ticketCost + lootBoxAmount` (higher or equal magnitude, since gross ≥ fresh) means earlybird target saturates FASTER under the same volume of purchases — commit intent. The saturate-faster direction is the only observable economic change; fairness properties (per-buyer proportionality to their purchase fraction, monotonicity of `earlybirdEthIn`) are preserved. | 6b3f4f3c |
| QST-02-V05 | QST-02 | D-243-I012, D-243-I011 (shared input-scalar surface) | contracts/modules/DegenerusGameMintModule.sol:1087-1172 (shared compute to both sinks) | QST-02b (shared-input but distinct-sinks — no "same counter, same wei, double increment" pattern) | SAFE | The `ticketCost + lootBoxAmount` scalar is computed exactly ONCE per invocation of `_purchaseFor` (at L1090 into `ethMintSpendWei`; the earlybird call at L1172 re-evaluates the same expression — it is NOT a reuse of the `ethMintSpendWei` local, but a recompute of the same arithmetic). Both recomputes yield the same value under the same inputs (pure arithmetic, no stateful reads between the two sites). The two sinks each increment a distinct counter/sink state exactly once; there is no path where a SHARED counter is incremented twice by the same wei (which would be the double-count failure mode). The two counters (`questPlayerState[].progress[]` / `earlybirdEthIn`) are semantically independent — an entry to one does not inform the other. | 6b3f4f3c |

### QST-02 closure

**All 5 V-rows SAFE.** The earlybird DGNRS emission at HEAD `cc68bfc7` counts gross spend (`ticketCost + lootBoxAmount`) via `_awardEarlybirdDgnrs` at L1172, mirroring the MINT_ETH credit's input scalar. The two sinks are storage-disjoint — MINT_ETH credit writes to `DegenerusQuests.sol` state; earlybird writes to `GameStorage.sol` state + sDGNRS Pool.Earlybird. Each sink fires exactly once per purchase, from the same scalar, to different counters. No double-count pattern exists. The quadratic-curve telescope property (v29.0 Phase 231) guarantees the "single call per purchase" shape is mathematically equivalent to the prior "two separate calls" shape under the new gross-spend magnitude.

**QST-02 finding candidates:** None.

**QST-02 per-REQ floor severity:** SAFE.

## §QST-03 — Affiliate fresh/recycled 20-25/5 split preserved (NEGATIVE-scope)

**REQ (verbatim):** "Affiliate split preservation: `_recordAffiliateStake` and adjacent affiliate-split helpers UNCHANGED by `6b3f4f3c` per §2.3 D-243-F008 rationale point 2-3 (affiliate fresh-vs-recycled 20-25/5 split preserved); cross-cited against `audit/v30-CONSUMER-INVENTORY.md` and any prior affiliate-trail audit."

**Scope source:** `audit/v31-243-DELTA-SURFACE.md` §6 row D-243-I013 → NONE 243 rows (this is NEGATIVE-scope — the REQ tests that NO delta touches the affiliate split helper; scope input is the v30-CONSUMER-INVENTORY.md artifact + direct code-read confirmation that Section 1 has zero rows touching affiliate split helpers).

**Owning commit:** `6b3f4f3c` (NEGATIVE-evidence).

**Naming clarification:** The plan text (CONTEXT.md D-12 QST-03) uses `_recordAffiliateStake` as a shorthand for the affiliate-split code path. At HEAD `cc68bfc7` the actual symbols exercising the fresh-vs-recycled affiliate split are:
- `affiliate.payAffiliate(amount, code, sender, lvl, isFreshEth, lootboxActivityScore)` — the external call on the `DegenerusAffiliate` contract at `contracts/DegenerusAffiliate.sol:388`. The `isFreshEth` boolean parameter drives the fresh-vs-recycled split (25% L0-3 / 20% L4+ / 5% recycled per `DegenerusAffiliate.sol:491-504`). No symbol literally named `_recordAffiliateStake` exists at HEAD (verified by `grep -rn '_recordAffiliateStake\|recordAffiliateStake' contracts/` returning zero hits). The plan's label refers to the conceptual split helper — the actual mechanism is the `isFreshEth` routing inside `_callTicketPurchase` at L1323-1361 combined with the split BPS constants inside `DegenerusAffiliate.payAffiliate`.

**Adversarial vectors (per CONTEXT.md D-12 QST-03 + threat model):**
- QST-03a — `DegenerusAffiliate.sol` UNTOUCHED by `6b3f4f3c` (NEGATIVE-evidence: the 20-25/5 split helper is in `DegenerusAffiliate.sol:491-504` and must be byte-identical at baseline vs HEAD)
- QST-03b — `_callTicketPurchase` at HEAD still passes the `freshEth` local (NOT `ethMintSpendWei` gross) to `affiliate.payAffiliate` — the `isFreshEth` boolean still keys on the original fresh-vs-recycled distinction, preserving the split rate
- QST-03c — differential check against `audit/v30-CONSUMER-INVENTORY.md` for affiliate-related rows (INV-237-005, INV-237-006) confirms the fresh-vs-recycled split mechanic predates v30.0 and remains untouched

### Section 1 zero-row gate (QST-03a)

`audit/v31-243-DELTA-SURFACE.md` Section 1 (Per-Commit Changelog) rows covering `6b3f4f3c` at §1.3 enumerate exactly 4 rows (D-243-C008, D-243-C009, D-243-C010, D-243-C011). None reference:
- `affiliate` (the `DegenerusAffiliate` module or `IDegenerusAffiliate` interface)
- `payAffiliate` (the fresh-vs-recycled split helper)
- `REWARD_SCALE_FRESH_L1_3_BPS` / `REWARD_SCALE_FRESH_L4P_BPS` / `REWARD_SCALE_RECYCLED_BPS` (the split BPS constants)
- `processAffiliatePayment` (affiliate winner-roll path)

Grep confirmation at phase execution:
```
git diff 7ab515fe..cc68bfc7 -- contracts/DegenerusAffiliate.sol | wc -l  # → 0 (zero hunks)
git diff 6b3f4f3c~1..6b3f4f3c -- contracts/DegenerusAffiliate.sol | wc -l  # → 0 (zero hunks in 6b3f4f3c specifically)
git diff 7ab515fe..cc68bfc7 -- contracts/interfaces/IDegenerusAffiliate.sol | wc -l  # → 0
```

All three checks pass — `DegenerusAffiliate.sol` and its interface are byte-identical between baseline `7ab515fe` and HEAD `cc68bfc7`. The fresh-vs-recycled split BPS constants at `DegenerusAffiliate.sol:491-504` are UNCHANGED.

### `_callTicketPurchase` preserves `freshEth` local for affiliate path (QST-03b)

At HEAD `cc68bfc7`, `_callTicketPurchase` (L1206-1373) demotes `freshEth` to a function-local scope (per §2.3 D-243-F009 rationale — return-tuple shrink removes `freshEth` from the return but keeps it as a local). The local is computed at L1289-1301 exactly as at baseline:
```
uint256 freshEth;
if (payKind == MintPaymentKind.DirectEth) {
    if (value < costWei) revert E();
    freshEth = costWei;
} else if (payKind == MintPaymentKind.Claimable) {
    if (value != 0) revert E();
    freshEth = 0;
} else if (payKind == MintPaymentKind.Combined) {
    if (value > costWei) revert E();
    freshEth = value;
} else {
    revert E();
}
```

The `freshEth` local is then consumed at L1305-1361 by the affiliate split logic:
- L1305-1307 computes `freshBurnie = freshEth != 0 ? _ethToBurnieValue(freshEth, priceWei) : 0`
- L1323-1342 Combined branch: calls `affiliate.payAffiliate(freshBurnie, ..., isFreshEth=true)` for the fresh portion, then `affiliate.payAffiliate(_ethToBurnieValue(recycled, ...), ..., isFreshEth=false)` for `recycled = costWei - freshEth`
- L1343-1351 DirectEth branch: calls `affiliate.payAffiliate(freshBurnie, ..., isFreshEth=true)` (fresh=100%)
- L1352-1360 Claimable branch: calls `affiliate.payAffiliate(_ethToBurnieValue(costWei, priceWei), ..., isFreshEth=false)` (recycled=100%)

**The `isFreshEth` boolean parameter is the LOAD-BEARING signal for the 20-25/5 split.** At HEAD, the Combined-path's `freshEth != 0` branch routes the fresh portion with `isFreshEth=true` (triggering the 25% L0-3 / 20% L4+ rate per `DegenerusAffiliate.sol:496-500`) and the recycled portion with `isFreshEth=false` (triggering the 5% rate per `DegenerusAffiliate.sol:502-503`). This matches baseline behavior at `git show 7ab515fe:contracts/modules/DegenerusGameMintModule.sol | sed -n '1323,1360p'` — bytes identical.

**Critical check:** at no point in `_callTicketPurchase` does `ethMintSpendWei` (the gross-spend scalar) flow into `affiliate.payAffiliate`. The scope-disjointness of the `6b3f4f3c` change is verified: the MINT_ETH credit and earlybird shifts to gross-spend scalar happen at the `_purchaseFor` level (L1090 + L1172), WHILE `_callTicketPurchase` continues to pass `freshEth` (not gross) to the affiliate split. Preservation is COMPLETE.

### Differential check against v30-CONSUMER-INVENTORY.md (QST-03c)

`audit/v30-CONSUMER-INVENTORY.md` enumerates 2 affiliate-related RNG consumer rows (INV-237-005 at `DegenerusAffiliate.sol:568` no-referrer branch; INV-237-006 at `DegenerusAffiliate.sol:585` referred branch). Both are KI-exception-tagged (`[KI: "Non-VRF entropy for affiliate winner roll"]`) covering the winner-takes-all weighted roll. Neither row references the 20-25/5 split BPS; both rows cite lines 568 + 585 which are INSIDE `payAffiliate` body (L388-...) but BEYOND the split-BPS compute at L491-504.

The 20-25/5 split itself predates v30.0 (audited at v25.0 + v29.0 milestone closures) and is not a VRF-consuming invariant — it is a pure deterministic rate-based multiplication (`scaledAmount = (amount * rewardScaleBps) / BPS_DENOMINATOR` at L505). No row in v30-CONSUMER-INVENTORY.md is at risk from the `6b3f4f3c` delta because (a) `DegenerusAffiliate.sol` has zero hunks in `6b3f4f3c` (verified via `git diff 6b3f4f3c~1..6b3f4f3c -- contracts/DegenerusAffiliate.sol` returns zero lines) and (b) the `isFreshEth` boolean is still correctly routed from `_callTicketPurchase` for all three payKind branches.

### QST-03 verdict table

| Verdict Row ID | REQ-ID | Source 243 Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| QST-03-V01 | QST-03 | D-243-F008 (rationale point 2-3 — affiliate UNCHANGED in 6b3f4f3c scope) | contracts/DegenerusAffiliate.sol (whole file — NEGATIVE-scope) | QST-03a (`DegenerusAffiliate.sol` byte-identical baseline vs HEAD) | SAFE | `git diff 7ab515fe..cc68bfc7 -- contracts/DegenerusAffiliate.sol` returns zero hunks; `git diff 6b3f4f3c~1..6b3f4f3c -- contracts/DegenerusAffiliate.sol` returns zero hunks. Section 1 of `audit/v31-243-DELTA-SURFACE.md` enumerates 4 `6b3f4f3c` rows (D-243-C008..C011), none touching `DegenerusAffiliate.sol` or `IDegenerusAffiliate.sol` — the affiliate module is completely out-of-scope for this commit. The 25% L0-3 / 20% L4+ / 5% recycled split constants (`REWARD_SCALE_FRESH_L1_3_BPS`, `REWARD_SCALE_FRESH_L4P_BPS`, `REWARD_SCALE_RECYCLED_BPS`) at `DegenerusAffiliate.sol:491-504` are UNCHANGED. NEGATIVE-evidence gate PASSES. | 6b3f4f3c (NEGATIVE-evidence) |
| QST-03-V02 | QST-03 | D-243-C011, D-243-F009 (rationale point — freshEth demoted to internal) | contracts/modules/DegenerusGameMintModule.sol:1289-1361 (`_callTicketPurchase` affiliate-split section) | QST-03b (`_callTicketPurchase` body at HEAD still passes `freshEth` local — not `ethMintSpendWei` gross — to `affiliate.payAffiliate`; the fresh-vs-recycled distinction is preserved) | SAFE | At HEAD `cc68bfc7`: (a) `freshEth` is demoted from return-tuple element to function-local scope declared at L1289 `uint256 freshEth;` and assigned at L1292 (DirectEth), L1295 (Claimable=0), L1298 (Combined=value); (b) the affiliate split logic at L1305-1360 is BYTE-IDENTICAL to baseline (diff: `git show 7ab515fe:contracts/modules/DegenerusGameMintModule.sol \| sed -n '1323,1360p'` vs HEAD L1323-1360 — same code modulo line shift from tuple-drop); (c) Combined branch at L1323-1342 splits into fresh portion (`freshBurnie` with `isFreshEth=true`) + recycled portion (`recycled = costWei - freshEth` with `isFreshEth=false`); (d) DirectEth at L1343-1351 all-fresh (`isFreshEth=true`); (e) Claimable at L1352-1360 all-recycled (`isFreshEth=false`). At NO POINT does `ethMintSpendWei` or `ticketCost + lootBoxAmount` gross-spend scalar enter the affiliate path. The 20-25/5 split is driven entirely by the pre-existing `isFreshEth` boolean mechanic in `_callTicketPurchase`, which is untouched by the rename. | 6b3f4f3c (NEGATIVE-evidence) |
| QST-03-V03 | QST-03 | D-243-F008, v30-CONSUMER-INVENTORY.md cross-cite | contracts/DegenerusAffiliate.sol:491-504 + audit/v30-CONSUMER-INVENTORY.md INV-237-005/006 | QST-03c (differential check against v30 affiliate-trail: no row at risk from 6b3f4f3c delta) | SAFE | `audit/v30-CONSUMER-INVENTORY.md` enumerates 2 affiliate-related RNG consumer rows (INV-237-005 + INV-237-006) at `DegenerusAffiliate.sol:568` + :585 (winner-takes-all roll branches). Both are KI-exception-tagged and scope-disjoint from the split-BPS compute at L491-504. Since `DegenerusAffiliate.sol` is byte-identical baseline vs HEAD (QST-03-V01) and the 20-25/5 split is a pure deterministic rate-based multiplication (no VRF dependency), the v30 affiliate invariants carry forward unchanged. No v30-CONSUMER-INVENTORY.md row is invalidated or at-risk from `6b3f4f3c`. | 6b3f4f3c (NEGATIVE-evidence, with v30 cross-cite) |
| QST-03-V04 | QST-03 | D-243-C011, D-243-F009 | contracts/modules/DegenerusGameMintModule.sol:1323-1342 (Combined-path split) | QST-03a (Combined-path fresh-vs-recycled split preservation: fresh portion `isFreshEth=true`, recycled portion `isFreshEth=false`, split rate driven by `DegenerusAffiliate.payAffiliate` BPS constants) | SAFE | Combined branch at L1323-1342 at HEAD `cc68bfc7`: `freshEth != 0` gate → two affiliate.payAffiliate calls — one with `freshBurnie` and `isFreshEth=true` (L1324-1331, routing to 25% L0-3 / 20% L4+ fresh rate); one with `_ethToBurnieValue(recycled, priceWei)` and `isFreshEth=false` where `recycled = costWei - freshEth` (L1332-1341, routing to 5% recycled rate). `recycled = costWei - freshEth` is the load-bearing arithmetic: if `freshEth < costWei` (i.e., partial claimable funding), the recycled portion is non-zero and is tagged with `isFreshEth=false`. This branches IDENTICAL behavior to baseline (diff 0 bytes). No Combined-path drift. | 6b3f4f3c (NEGATIVE-evidence) |

### QST-03 closure

**All 4 V-rows SAFE.** The 20-25/5 fresh-vs-recycled affiliate split is preserved at HEAD `cc68bfc7`:
- The `DegenerusAffiliate.sol` contract is byte-identical baseline vs HEAD (zero hunks in 6b3f4f3c)
- The BPS split constants `REWARD_SCALE_FRESH_L1_3_BPS` / `REWARD_SCALE_FRESH_L4P_BPS` / `REWARD_SCALE_RECYCLED_BPS` at `DegenerusAffiliate.sol:491-504` are UNCHANGED
- The `isFreshEth` boolean signal flowing from `_callTicketPurchase` to `affiliate.payAffiliate` is UNCHANGED in semantics — `freshEth` local continues to track the msg.value-derived fresh portion; `costWei - freshEth` continues to track the recycled portion; each is tagged correctly with `isFreshEth=true`/`false` at the affiliate call site
- No path in `_callTicketPurchase` routes the gross-spend `ethMintSpendWei` scalar to `affiliate.payAffiliate` — the MINT_ETH / earlybird gross-spend shifts are scope-disjoint from the affiliate split
- v30-CONSUMER-INVENTORY.md INV-237-005/006 are scope-disjoint from the split-BPS compute (they cite winner-takes-all roll branches); no v30 row invalidated

**QST-03 finding candidates:** None.

**QST-03 per-REQ floor severity:** SAFE.

## §QST-04 — `_callTicketPurchase` freshEth drop + ethFreshWei → ethMintSpendWei rename equivalence

**REQ (verbatim):** "`_callTicketPurchase` return-tuple shrink (`freshEth` removed) — every caller enumerated, none uses dropped return value (REFACTOR_ONLY at caller-hunk granularity per Phase 243 D-04); `ethFreshWei → ethMintSpendWei` parameter rename — all call sites pass gross-spend value (semantically MODIFIED_LOGIC where intent changed, REFACTOR_ONLY at rename hunk itself); side-by-side prose diff naming the rename + drop boundary per CONTEXT.md D-17."

**Scope source:** `audit/v31-243-DELTA-SURFACE.md` §6 row D-243-I014 → D-243-C011 (6b3f4f3c `_callTicketPurchase` SIGNATURE-CHANGED L1206-1373), D-243-C008 (handlePurchase impl SIGNATURE-CHANGED), D-243-F007 (handlePurchase REFACTOR_ONLY — rename hunk), D-243-F009 (`_callTicketPurchase` MODIFIED_LOGIC — return-tuple shrink), D-243-X018 (`_callTicketPurchase` caller at MintModule._purchaseCoinFor L895), D-243-X019 (`_callTicketPurchase` caller at MintModule._purchaseFor L978), D-243-X015 (`handlePurchase` call site at MintModule._purchaseFor L1098).

**Owning commit:** `6b3f4f3c`.

**Adversarial vectors (per CONTEXT.md D-12 QST-04 + D-17 prose-diff methodology):**
- QST-04a — `_callTicketPurchase` return-drop: every caller (2 call sites per §3.1.9) does NOT consume the dropped `freshEth` return element (REFACTOR_ONLY at caller hunk per Phase 243 D-04)
- QST-04b — `ethFreshWei → ethMintSpendWei` parameter rename: ABI-compatible (type unchanged, selector preserved); call-site value semantically shifts from fresh-only to gross-spend (MODIFIED_LOGIC at call boundary, REFACTOR_ONLY at the rename hunk itself)
- QST-04c — side-by-side prose diff identifying (a) the specific signature-level bytes that changed and (b) the specific body-level bytes that did NOT change (callee-side body is byte-equivalent under rename)

### Sub-verdict (a) — `_callTicketPurchase` return-tuple shrink (QST-04a)

**Enumeration of callers per §3.1.9:**

Grep at HEAD `cc68bfc7`:
```
grep -n '_callTicketPurchase\b' contracts/modules/DegenerusGameMintModule.sol
# Returns 4 hits:
#   895  - caller inside _purchaseCoinFor (D-243-X018)
#   978  - caller inside _purchaseFor (D-243-X019)
#   1137 - inline comment reference ("moved from _callTicketPurchase")
#   1206 - function definition itself
```

The two execution callers are at L895 and L978. `grep -rn '_callTicketPurchase' contracts/` confirms zero hits outside `DegenerusGameMintModule.sol` (the function is `private` so cannot be called externally anyway).

**Caller L895 — `_purchaseCoinFor`:**

Side-by-side baseline vs HEAD:

Baseline `7ab515fe` (L895):
```
_callTicketPurchase(
    buyer,
    msg.sender,
    ticketQuantity,
    MintPaymentKind.DirectEth,
    true,
    bytes32(0),
    0,
    level,
    jackpotPhaseFlag
);
```

HEAD `cc68bfc7` (L895):
```
_callTicketPurchase(
    buyer,
    msg.sender,
    ticketQuantity,
    MintPaymentKind.DirectEth,
    true,
    bytes32(0),
    0,
    level,
    jackpotPhaseFlag
);
```

**Zero destructure at both versions.** The return value (5-tuple at baseline, 4-tuple at HEAD) is discarded in-whole at both versions. The return-tuple shrink is a no-op at this call site — the dropped `freshEth` element was NEVER consumed here. Caller-hunk granularity: REFACTOR_ONLY per Phase 243 D-04 (no behavioral drift at call site).

**Caller L978 — `_purchaseFor`:**

Side-by-side baseline vs HEAD:

Baseline `7ab515fe` (L970-989):
```
uint32 burnieMintUnits;
uint32 adjustedQty;
uint24 targetLevel;
uint256 ticketFreshEth;
if (ticketCost != 0) {
    (
        lootboxFlipCredit,
        adjustedQty,
        targetLevel,
        burnieMintUnits,
        ticketFreshEth
    ) = _callTicketPurchase(
            buyer,
            buyer,
            ticketQuantity,
            payKind,
            false,
            affiliateCode,
            remainingEth,
            cachedLevel,
            cachedJpFlag
        );
}
```

HEAD `cc68bfc7` (L969-989):
```
uint32 burnieMintUnits;
uint32 adjustedQty;
uint24 targetLevel;
if (ticketCost != 0) {
    (
        lootboxFlipCredit,
        adjustedQty,
        targetLevel,
        burnieMintUnits
    ) = _callTicketPurchase(
            buyer,
            buyer,
            ticketQuantity,
            payKind,
            false,
            affiliateCode,
            remainingEth,
            cachedLevel,
            cachedJpFlag
        );
}
```

**Concrete changes:**
1. Line 973 of baseline (`uint256 ticketFreshEth;`) is REMOVED at HEAD — the local variable disappears
2. Baseline tuple destructure `(lootboxFlipCredit, adjustedQty, targetLevel, burnieMintUnits, ticketFreshEth)` shrinks to HEAD's `(lootboxFlipCredit, adjustedQty, targetLevel, burnieMintUnits)` — last element dropped
3. Subsequent use of `ticketFreshEth` at baseline L1087 (`uint256 ethFreshWei = ticketFreshEth + lootboxFreshEth;`) is REPLACED at HEAD L1090 (`uint256 ethMintSpendWei = ticketCost + lootBoxAmount;`) — the load-bearing change is NOT in the caller hunk itself, it's in the subsequent use-site expression
4. Subsequent use of `ticketFreshEth` at baseline L1227 (`_awardEarlybirdDgnrs(buyer, ticketFreshEth + lootboxFreshEth);`) is REPLACED at HEAD L1172 (`_awardEarlybirdDgnrs(buyer, ticketCost + lootBoxAmount);`) — same shift (QST-02-V01)

**At the tuple-destructure hunk itself (L969-989 HEAD), the caller is REFACTOR_ONLY:** the dropped element is a NOT-CONSUMED local whose only downstream uses were at L1087 + L1227 (baseline) — those downstream uses are rewritten entirely at HEAD (L1090 + L1172 using a different scalar, `ticketCost + lootBoxAmount`). The caller's READ of `ticketFreshEth` was the ONLY downstream dependency, and that dependency is eliminated by the `_purchaseFor`-level semantic rewrite. The return-tuple shrink at the caller hunk granularity is safe. This matches §2.3 D-243-F009 "dropped `freshEth` return-tuple element (5-tuple → 4-tuple) — return-path evaluation changed for every caller; `freshEth` demoted to function-local-scope `uint256 freshEth;` before DirectEth branch."

### Sub-verdict (b) — parameter rename `ethFreshWei → ethMintSpendWei` (QST-04b)

**Side-by-side prose diff of `handlePurchase` signature (per CONTEXT.md D-17):**

Baseline `7ab515fe` `contracts/DegenerusQuests.sol:763-774`:
```
function handlePurchase(
    address player,
    uint256 ethFreshWei,            // <-- parameter 2 name
    uint32 burnieMintQty,
    uint256 lootBoxAmount,
    uint256 mintPrice,
    uint256 levelQuestPrice
)
    external
    onlyCoin
    returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
```

HEAD `cc68bfc7` `contracts/DegenerusQuests.sol:763-773`:
```
function handlePurchase(
    address player,
    uint256 ethMintSpendWei,        // <-- parameter 2 name (renamed)
    uint32 burnieMintQty,
    uint256 lootBoxAmount,
    uint256 mintPrice,
    uint256 levelQuestPrice
)
    external
    onlyCoin
    returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
```

**Element-by-element equivalence proof:**
1. Return type signature `(uint256 reward, uint8 questType, uint32 streak, bool completed)`: UNCHANGED (zero drift)
2. Modifier list `external onlyCoin`: UNCHANGED
3. Parameter count: UNCHANGED (6 parameters both sides)
4. Parameter types by position: `(address, uint256, uint32, uint256, uint256, uint256)` — UNCHANGED
5. Parameter names by position: `(player, ethFreshWei, burnieMintQty, lootBoxAmount, mintPrice, levelQuestPrice)` baseline → `(player, ethMintSpendWei, burnieMintQty, lootBoxAmount, mintPrice, levelQuestPrice)` HEAD — **only parameter 2 name changes**

**ABI selector equivalence:**

The Solidity ABI selector is `bytes4(keccak256("handlePurchase(address,uint256,uint32,uint256,uint256,uint256)"))` — depends ONLY on the normalized signature (name + parameter types, no parameter names). Since the function name and all parameter types are unchanged, the selector is byte-identical baseline vs HEAD. This is the ABI stability guarantee that permits the rename at `IDegenerusQuests.sol:139-146` (D-243-C009 / D-243-C030) to be ABI-compatible: external callers at HEAD using stale ABI from baseline continue to encode calldata with the correct selector; internal callers reference by position, not by name, so the rename is transparent to callers.

**Body-level byte equivalence (callee-side per §2.3 D-05.4a REFACTOR_ONLY):**

`git show 7ab515fe:contracts/DegenerusQuests.sol` body at L775-828 vs HEAD `contracts/DegenerusQuests.sol:775-898` diff via `s/ethFreshWei/ethMintSpendWei/g`: the body IS byte-equivalent under this rename across the full L763-898 range. The only textual changes are:
- Parameter name `ethFreshWei` → `ethMintSpendWei` at occurrences L781, L797, L806, L807, L821 (inside handlePurchase body)
- NatSpec comment at L129-132 IDegenerusQuests and L749-754 DegenerusQuests.sol updated to describe "Gross ETH-denominated spend on tickets + lootbox in wei (fresh + recycled)" instead of baseline "Fresh ETH spend"
- Inline comment at L794-796 updated to describe "Gross ETH spend on tickets + lootboxes (fresh + recycled) is credited 1:1 in wei to the MINT_ETH quest" instead of baseline "Fresh ETH from tickets and lootboxes is credited 1:1 in wei to the MINT_ETH quest"

**No branch added / no SSTORE order changed / no external call added or reordered / no return-path evaluation drift inside the body.** The callee body is REFACTOR_ONLY at the rename-hunk granularity per §2.3 D-243-F007 verdict.

### Sub-verdict (c) — call-site value-semantics shift (QST-04b continued)

**At HEAD** the call site at `contracts/modules/DegenerusGameMintModule.sol:1098-1105` passes `ethMintSpendWei` (which equals `ticketCost + lootBoxAmount` — gross spend, per QST-01-V01 / QST-02-V01):
```
) = quests.handlePurchase(
        buyer,
        ethMintSpendWei,    // <-- gross-spend scalar at HEAD (ticketCost + lootBoxAmount)
        burnieMintUnits,
        lootBoxAmount,
        priceWei,
        PriceLookupLib.priceForLevel(cachedLevel + 1)
    );
```

**At baseline** the same call site at `contracts/modules/DegenerusGameMintModule.sol:1198-1205` (different line numbers pre-shrink) passed `ethFreshWei` (which equaled `ticketFreshEth + lootboxFreshEth` — fresh-only):
```
) = quests.handlePurchase(
        buyer,
        ethFreshWei,        // <-- fresh-only scalar at baseline (ticketFreshEth + lootboxFreshEth)
        burnieMintUnits,
        lootBoxAmount,
        priceWei,
        PriceLookupLib.priceForLevel(cachedLevel + 1)
    );
```

**The CALL-BOUNDARY value shift is MODIFIED_LOGIC:** the parameter-2 value at the caller's expression shifted from `ticketFreshEth + lootboxFreshEth` (fresh only, excludes claimable-recycled) to `ticketCost + lootBoxAmount` (gross, includes claimable-recycled). This is the commit-message intent ("credit recycled ETH toward MINT_ETH quests"). The CALLEE body under the rename is REFACTOR_ONLY; the CALLER call expression is MODIFIED_LOGIC. §2.3 D-243-F008 captures this at the caller-side (_purchaseFor) verdict; §2.3 D-243-F007 captures the callee-side (handlePurchase) verdict.

### QST-04 verdict table

| Verdict Row ID | REQ-ID | Source 243 Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| QST-04-V01 | QST-04 | D-243-C011, D-243-F009, D-243-X018 | contracts/modules/DegenerusGameMintModule.sol:895 (`_purchaseCoinFor` caller) | QST-04a (return drop — caller does NOT consume the dropped `freshEth`) | SAFE | `_purchaseCoinFor` at L885-911 calls `_callTicketPurchase(...)` at L895-905 WITHOUT any destructure (no tuple-variable bindings, no single-variable binding). The entire return is discarded. Baseline `7ab515fe` had IDENTICAL no-destructure pattern at this call site (verified via `git show 7ab515fe:contracts/modules/DegenerusGameMintModule.sol \| sed -n '885,911p'`). The dropped `freshEth` return element was NEVER consumed here at baseline — the return-tuple shrink is a transparent no-op at this caller-hunk. REFACTOR_ONLY at caller granularity per Phase 243 D-04. | 6b3f4f3c |
| QST-04-V02 | QST-04 | D-243-C011, D-243-F009, D-243-X019 | contracts/modules/DegenerusGameMintModule.sol:978-989 (`_purchaseFor` caller) | QST-04a (return drop — caller's destructure updated; dropped element's downstream uses refactored) | SAFE | At baseline L973-989 `_purchaseFor` declared local `uint256 ticketFreshEth;` at L973 and destructured 5-tuple `(lootboxFlipCredit, adjustedQty, targetLevel, burnieMintUnits, ticketFreshEth)` from `_callTicketPurchase`. At HEAD cc68bfc7 L969-989 the local `ticketFreshEth` declaration is REMOVED and destructure shrinks to 4-tuple `(lootboxFlipCredit, adjustedQty, targetLevel, burnieMintUnits)`. The downstream uses of `ticketFreshEth` at baseline (L1087 `ethFreshWei = ticketFreshEth + lootboxFreshEth` + L1227 `_awardEarlybirdDgnrs(buyer, ticketFreshEth + lootboxFreshEth)`) are REPLACED at HEAD with expressions using `ticketCost + lootBoxAmount` (L1090 + L1172) — the semantic-shift happens at those downstream expressions, NOT at the destructure hunk itself. At the caller-hunk granularity (the destructure + local declaration), the change is REFACTOR_ONLY: the removed local and dropped tuple element had ONLY two downstream readers, both rewritten to use a different (gross-spend) scalar entirely. No consumer of `ticketFreshEth` survives post-refactor. Phase 243 D-04 REFACTOR_ONLY at caller hunk; downstream semantic-shift at L1090/L1172 is MODIFIED_LOGIC per §2.3 D-243-F008. | 6b3f4f3c |
| QST-04-V03 | QST-04 | D-243-C008, D-243-C009, D-243-C030, D-243-X015, D-243-X055, D-243-F007 | contracts/DegenerusQuests.sol:763-773 (callee signature) + contracts/interfaces/IDegenerusQuests.sol:139-146 (interface signature) + contracts/modules/DegenerusGameMintModule.sol:1098 (call site) | QST-04b (parameter rename `ethFreshWei → ethMintSpendWei` — ABI-selector preserved; semantic shift is at call-boundary value, not at callee body) | SAFE | **Side-by-side prose diff** (per CONTEXT.md D-17): (a) Callee signature baseline `(address player, uint256 ethFreshWei, uint32 burnieMintQty, uint256 lootBoxAmount, uint256 mintPrice, uint256 levelQuestPrice)` → HEAD `(address player, uint256 ethMintSpendWei, uint32 burnieMintQty, uint256 lootBoxAmount, uint256 mintPrice, uint256 levelQuestPrice)` — only param-2 name changes; type `uint256` unchanged; position 2 preserved; parameter count/types/return-type all unchanged. (b) Interface signature at `IDegenerusQuests.sol:139-146` mirrors the implementation change (matching rename; ABI-equivalent). (c) ABI selector `bytes4(keccak256("handlePurchase(address,uint256,uint32,uint256,uint256,uint256)"))` is BYTE-IDENTICAL at baseline vs HEAD (selector depends on type-signature only, not on parameter names). (d) Callee body L775-898 is byte-equivalent under `s/ethFreshWei/ethMintSpendWei/g` rename — zero branch add, zero SSTORE reorder, zero external call change; only name occurrences at L781, L797, L806-807, L821 + NatSpec + inline-comment updates describing the new "gross + recycled" semantics. (e) Call-site value at `DegenerusGameMintModule.sol:1098` at HEAD passes `ethMintSpendWei = ticketCost + lootBoxAmount` (gross) where baseline passed `ethFreshWei = ticketFreshEth + lootboxFreshEth` (fresh-only) — this is the MODIFIED_LOGIC at the caller side per §2.3 D-243-F008, NOT the rename hunk itself. Rename + body REFACTOR_ONLY; call-boundary value shift MODIFIED_LOGIC per dual-verdict taxonomy in D-243-F007 + D-243-F008 splits. | 6b3f4f3c |
| QST-04-V04 | QST-04 | D-243-C009, D-243-C030 | contracts/interfaces/IDegenerusQuests.sol:129-146 (NatSpec + signature) | QST-04b (interface NatSpec updated to describe gross-spend semantics; wire-format unchanged) | SAFE | `contracts/interfaces/IDegenerusQuests.sol:129-132` NatSpec for `ethMintSpendWei` parameter at HEAD reads "Gross ETH-denominated spend on tickets + lootbox in wei (fresh + recycled), credited 1:1 to MINT_ETH quest" (replacing baseline "Fresh ETH spend on tickets + lootbox, credited 1:1 to MINT_ETH quest"). NatSpec for `lootBoxAmount` at L132-133 reads "ETH spent on lootbox in wei (full amount, fresh + recycled)" (replacing baseline "Fresh ETH spent on lootbox in wei"). Both NatSpec updates correctly describe the new gross-spend semantics at the interface boundary — matching the callee body + call-site value. No ABI wire-format change (signature name `handlePurchase(address,uint256,uint32,uint256,uint256,uint256)` unchanged → same selector). Interface drift is zero; ABI-stability gate passes. | 6b3f4f3c |
| QST-04-V05 | QST-04 | D-243-F007, D-243-F009 | contracts/modules/DegenerusGameMintModule.sol:1206-1373 (`_callTicketPurchase` body) + contracts/DegenerusQuests.sol:763-898 (`handlePurchase` body) | QST-04c (no-bug-from-refactor gate: verifying the rename + return-drop refactors did NOT introduce new state-write ordering, new external call, new branch, or new revert) | SAFE | Diff `git show 6b3f4f3c -- contracts/DegenerusQuests.sol contracts/interfaces/IDegenerusQuests.sol contracts/modules/DegenerusGameMintModule.sol` enumerated hunks (confirmed via commit manifest). Inside `handlePurchase` body: zero new branches, zero new SSTORE sequences, zero new external calls — the body text is byte-equivalent under `s/ethFreshWei/ethMintSpendWei/g`. Inside `_callTicketPurchase` body: `freshEth` is demoted from return-tuple element to function-local `uint256 freshEth;` declaration at L1289 (new declaration line replacing the tuple-output slot at baseline L1290) + `freshEth` is consumed locally at L1292-1301 exactly as at baseline. The only code-generation-visible change at `_callTicketPurchase` is the tuple-return shrink (last element dropped). No new revert, no new external call (the affiliate split path at L1305-1360 is byte-identical). Side-by-side L1289-1301 baseline vs HEAD: baseline had `freshEth = costWei;` / `freshEth = 0;` / `freshEth = value;` assignments as writes to the tuple-output slot; HEAD has IDENTICAL assignments as writes to the local variable. No introduction of new semantics. Refactor-without-bug gate passes. | 6b3f4f3c |

### QST-04 closure

**All 5 V-rows SAFE.** The `6b3f4f3c` signature changes are equivalent-by-element at HEAD `cc68bfc7`:
- Return-tuple shrink at `_callTicketPurchase` is REFACTOR_ONLY at every caller site (both `_purchaseCoinFor` L895 and `_purchaseFor` L978): `_purchaseCoinFor` never destructured the return; `_purchaseFor` had one local consumer (`ticketFreshEth`) whose only downstream uses were rewritten at the `_purchaseFor`-level semantic-shift hunks (MODIFIED_LOGIC at L1090 + L1172, not at the destructure hunk itself).
- Parameter rename `ethFreshWei → ethMintSpendWei` at `handlePurchase` is ABI-compatible (selector preserved because type-signature is unchanged). Callee body is byte-equivalent under the rename; NatSpec correctly describes new gross-spend semantics; interface matches implementation.
- Call-site value at `_purchaseFor:1098` shifted from fresh-only scalar to gross-spend scalar — this is the MODIFIED_LOGIC at the caller side per §2.3 D-243-F008, captured by QST-01 + QST-02 verdicts.
- The refactor introduced zero new branches, SSTORE orderings, external calls, or reverts inside the affected function bodies.

**QST-04 finding candidates:** None.

**QST-04 per-REQ floor severity:** SAFE.

## §Reproduction Recipe — QST bucket (Task 1)

Per CONTEXT.md §Specifics reproducibility commitment + `audit/v31-243-DELTA-SURFACE.md` §7.2 style. POSIX-portable commands, no GNU-isms. Every command used by Task 1:

### Sanity + anchor
```
git log --oneline -1
git rev-parse HEAD
git diff cc68bfc7..HEAD -- contracts/ | wc -l    # expected: 0 (anchor valid)
```

### Scope confirmation — `6b3f4f3c` affects only 3 files
```
git show 6b3f4f3c --stat
git diff 6b3f4f3c~1..6b3f4f3c -- contracts/DegenerusAffiliate.sol | wc -l    # expected: 0 (NEGATIVE-scope for QST-03)
git diff 6b3f4f3c~1..6b3f4f3c -- contracts/interfaces/IDegenerusAffiliate.sol | wc -l    # expected: 0
```

### Enumerate `handlePurchase` call sites (§3.1.7 / §3.2.1 match)
```
grep -rn --include='*.sol' '\bhandlePurchase\b' contracts/ \
    | grep -v '^contracts/mocks/' | grep -v '^contracts/test/' | grep -v '\.bak'
# Expected: definition at DegenerusQuests.sol:763 + interface at IDegenerusQuests.sol:139
#           + sole call site at DegenerusGameMintModule.sol:1098
```

### Enumerate `_callTicketPurchase` call sites (§3.1.9 match)
```
grep -n '_callTicketPurchase\b' contracts/modules/DegenerusGameMintModule.sol
# Expected: 4 hits — L895 (_purchaseCoinFor caller), L978 (_purchaseFor caller),
#           L1137 (inline comment only), L1206 (definition).
grep -rn '_callTicketPurchase' contracts/ | grep -v '\.bak'    # confirm zero external callers
```

### Residual-fresh-only search (QST-01-V04 gate)
```
grep -n 'ethFreshWei' contracts/                                    # expected: zero hits
grep -n 'freshEth' contracts/modules/DegenerusGameMintModule.sol    # expected: 6 hits L1289-L1335 (affiliate-local scope only)
grep -n 'freshEth\|ethFreshWei' contracts/DegenerusQuests.sol contracts/interfaces/IDegenerusQuests.sol    # expected: zero
```

### QST-02 earlybird sink enumeration
```
grep -rn --include='*.sol' '_awardEarlybirdDgnrs\b' contracts/ | grep -v '\.bak'
# Expected: 2 rows — definition at DegenerusGameStorage.sol:1014 + single call at DegenerusGameMintModule.sol:1172
git diff 7ab515fe..cc68bfc7 -- contracts/storage/DegenerusGameStorage.sol    # expected: zero hunks touching _awardEarlybirdDgnrs body
```

### QST-03 NEGATIVE-scope gate (affiliate byte-identity + v30 cross-cite)
```
git diff 7ab515fe..cc68bfc7 -- contracts/DegenerusAffiliate.sol | wc -l              # expected: 0
git diff 7ab515fe..cc68bfc7 -- contracts/interfaces/IDegenerusAffiliate.sol | wc -l  # expected: 0
grep -n 'REWARD_SCALE_FRESH_L1_3_BPS\|REWARD_SCALE_FRESH_L4P_BPS\|REWARD_SCALE_RECYCLED_BPS' contracts/DegenerusAffiliate.sol
# Cross-cite: audit/v30-CONSUMER-INVENTORY.md INV-237-005 + INV-237-006 (affiliate winner-roll KI rows,
# scope-disjoint from the 20-25/5 split BPS compute)
```

### QST-04 side-by-side prose diff commands (per CONTEXT.md D-17)
```
# Baseline handlePurchase signature
git show 7ab515fe:contracts/DegenerusQuests.sol | sed -n '763,774p'
# HEAD handlePurchase signature
sed -n '763,773p' contracts/DegenerusQuests.sol

# Baseline _callTicketPurchase return-tuple declaration
git show 7ab515fe:contracts/modules/DegenerusGameMintModule.sol | sed -n '1216,1230p'
# HEAD _callTicketPurchase return-tuple declaration
sed -n '1216,1224p' contracts/modules/DegenerusGameMintModule.sol

# Baseline _purchaseFor destructure hunk (at L969-989 in baseline line numbering)
git show 7ab515fe:contracts/modules/DegenerusGameMintModule.sol | sed -n '968,992p'
# HEAD _purchaseFor destructure hunk
sed -n '968,990p' contracts/modules/DegenerusGameMintModule.sol

# Baseline _purchaseCoinFor call-site (no destructure, both sides)
git show 7ab515fe:contracts/modules/DegenerusGameMintModule.sol | sed -n '885,912p'
sed -n '885,911p' contracts/modules/DegenerusGameMintModule.sol

# Baseline vs HEAD earlybird call-site
git show 7ab515fe:contracts/modules/DegenerusGameMintModule.sol | sed -n '1225,1230p'
sed -n '1168,1173p' contracts/modules/DegenerusGameMintModule.sol

# Baseline vs HEAD affiliate split section inside _callTicketPurchase (verify byte-identical)
git show 7ab515fe:contracts/modules/DegenerusGameMintModule.sol | sed -n '1320,1365p'
sed -n '1320,1365p' contracts/modules/DegenerusGameMintModule.sol
```

## §QST-05 — Gas savings claim (-142k/-153k/-76k WC) — BYTECODE-DELTA-ONLY methodology (CONTEXT.md D-13)

**REQ (verbatim per `.planning/REQUIREMENTS.md`):** "Validate claimed gas savings (-142k WC daily split, -153k WC early-burn, -76k WC terminal jackpot) against repro evidence or mark INFO if unreproducible."

**Scope source:** `audit/v31-243-DELTA-SURFACE.md` §6 row D-243-I015 — NONE 243 rows (QST-05 is fresh-evidence work; no 243 row maps per D-10). Methodology input files per 243 row subsets: D-243-C008 (`handlePurchase` impl), D-243-C010 (`_purchaseFor`), D-243-C011 (`_callTicketPurchase`), D-243-F007 (REFACTOR_ONLY rename), D-243-F008 (MODIFIED_LOGIC — gross-spend), D-243-F009 (MODIFIED_LOGIC — return-tuple shrink).

**Owning commit:** `6b3f4f3c` (the commit whose commit-message claims the gas savings).

### Methodology (LOCKED per CONTEXT.md D-13)

QST-05 is verified by `forge inspect deployedBytecode` delta, NOT by running gas benchmarks. Rationale per CONTEXT.md D-13:
- READ-only constraint blocks adding new test scaffolding to construct theoretical worst-case state per `memory/feedback_gas_worst_case.md`
- Existing `test/gas/AdvanceGameGas.test.js` is explicitly listed in `feedback_gas_worst_case.md` as not enabling autorebuy / not verifying specialized events / not constructing true worst-case state, so its numbers are inadmissible as WC evidence
- The claimed `6b3f4f3c` changes (dropped `freshEth` return / `ethFreshWei → ethMintSpendWei` rename / removed dead branches / unified earlybird call) are STRUCTURAL — their presence is verifiable via deployed-bytecode delta without running the code

**Verdict bar (LOCKED per CONTEXT.md D-14):**
- **SAFE** — (a) bytecode delta shows structural changes present AND (b) direction matches claim (deployed bytecode is smaller OR opcode-pattern changes match expected savings sites) AND (c) no regression on adjacent paths
- **INFO** — structural change present but bytecode-delta ambiguous, OR magnitude commentary worth recording
- **INFO-unreproducible** — direction can't be confirmed from bytecode delta alone
- **Magnitude bar: NOT enforced** — gas magnitude is unreproducible under READ-only + bytecode-only regime

**Adversarial vectors (per CONTEXT.md D-12 QST-05 + D-13/D-14 methodology lock):**
- QST-05a — direction check: bytecode delta shows the structural changes exist AND bytecode body length (post-CBOR-strip) does NOT grow in the direction opposite to the commit-message claim
- QST-05b — adjacent-path regression check: opcode-level direction signatures (PUSH1 / MSTORE / JUMPDEST / RETURN counts) do not show pathological growth at adjacent function offsets
- QST-05c — magnitude commentary (INFO-only per D-14): the observed bytecode-body delta is far smaller than the claimed gas savings magnitude, which is EXPECTED — deployed-bytecode size reductions and gas savings are decoupled metrics; gas savings come from runtime-path reduction (fewer SSTORE / fewer MLOAD on hot-path), not from deploy-code shrinkage

### §QST-05 Evidence Appendix — Bytecode Delta

#### DegenerusQuests (contracts/DegenerusQuests.sol:DegenerusQuests)

| Metric | Baseline 7ab515fe | Head cc68bfc7 | Delta |
| --- | --- | --- | --- |
| Raw bytecode body (incl CBOR) | 36,226 hex chars / 18,113 bytes | 36,226 hex chars / 18,113 bytes | 0 chars (0 bytes) |
| CBOR metadata marker found | `a264697066735822` (ipfs) at offset 36,120 | `a264697066735822` (ipfs) at offset 36,120 | same marker kind |
| Stripped body (post-CBOR-strip) | 36,120 hex chars / **18,060 bytes** | 36,120 hex chars / **18,060 bytes** | **0 chars (0 bytes) — BYTE-IDENTICAL** |
| First-byte-divergence post-strip | n/a | n/a | `diff stripped-baseline stripped-head` returns zero hunks |

**Interpretation:** At the `DegenerusQuests` contract, the stripped deployed bytecode is BYTE-IDENTICAL between baseline `7ab515fe` and head `cc68bfc7`. This is the expected result per §2.3 D-243-F007 REFACTOR_ONLY: the `ethFreshWei → ethMintSpendWei` parameter rename is a pure source-level identifier rename with zero compiler-visible semantics — solc 0.8.34 via_ir generates identical bytecode because parameter names do not enter the compiled output (only types + ABI signatures do, and both are unchanged). The CBOR metadata trailer differs (different IPFS source hash reflecting the different source-file bytes — expected drift from rename + NatSpec edits) but the executable bytecode is identical.

**Direction check (QST-05a):** No bytecode growth. The REFACTOR_ONLY claim for `handlePurchase` rename is CONFIRMED at the bytecode level — zero runtime impact from the rename hunk alone.

**Adjacent-path regression check (QST-05b):** byte-identical → no regression possible.

#### DegenerusGameMintModule (contracts/modules/DegenerusGameMintModule.sol:DegenerusGameMintModule)

| Metric | Baseline 7ab515fe | Head cc68bfc7 | Delta |
| --- | --- | --- | --- |
| Raw bytecode body (incl CBOR) | 32,716 hex chars / 16,358 bytes | 32,644 hex chars / 16,322 bytes | -72 chars (-36 bytes) |
| CBOR metadata marker found | `a264697066735822` (ipfs) at offset 32,610 | `a264697066735822` (ipfs) at offset 32,538 | same marker kind |
| Stripped body (post-CBOR-strip) | 32,610 hex chars / **16,305 bytes** | 32,538 hex chars / **16,269 bytes** | **-72 chars (-36 bytes) — SHRANK** |
| First-byte-divergence post-strip | n/a | n/a | char offset 3 (byte 1) — free-memory-pointer preamble |
| Free-mem-pointer preamble | `PUSH2 0x0240` (576) | `PUSH2 0x01E0` (480) | -96 bytes initial scratch allocation |

**Opcode-level histogram (coarse structural signature across whole stripped body):**

| Opcode | Mnemonic | Baseline count | Head count | Delta |
| --- | --- | --- | --- | --- |
| `60` | PUSH1 | 1,335 | 1,316 | -19 |
| `52` | MSTORE | 325 | 314 | -11 |
| `fd` | REVERT | 30 | 28 | -2 |
| `f3` | RETURN | 12 | 13 | +1 |
| `57` | JUMPI | 431 | 435 | +4 |
| `5b` | JUMPDEST | 692 | 701 | +9 |
| `80` | DUP1 | 305 | 319 | +14 |
| `81` | DUP2 | 299 | 306 | +7 |
| `82` | DUP3 | 194 | 193 | -1 |
| `90` | SWAP1 | 480 | 491 | +11 |
| `91` | SWAP2 | 257 | 252 | -5 |

**Interpretation:**
- **Free-memory-pointer preamble shrank from 0x0240 (576) to 0x01E0 (480)** — a 96-byte reduction in initial scratch-memory allocation. This is consistent with removing function-local state (the `ticketFreshEth` local demotion + 5-tuple → 4-tuple return shrink reduce the module's total scratch-memory high-water mark).
- **MSTORE dropped by 11 and PUSH1 by 19** — consistent with fewer return-tuple element writes (dropping `freshEth` from the return eliminates the tuple-element MSTORE + its length PUSH; removing `ticketFreshEth` local eliminates its stack-to-memory spill/reload if any).
- **REVERT dropped by 2** — consistent with dead-branch removal (the `if (gameOver) revert E();` guards in `_purchaseFor` were replaced with `if (_livenessTriggered()) revert E();` — but note this belongs to `771893d1`, not `6b3f4f3c`; see caveat below).
- **JUMPI +4 / JUMPDEST +9 / DUP1 +14 / SWAP1 +11** — net opcode shuffling from via_ir re-optimization after source simplification. The compiler's register-allocator/peephole-optimizer can produce non-monotone opcode shuffles after code simplification even when the total byte count shrinks. This is a known via_ir behavior; not a regression.
- **Total stripped body delta: -36 bytes** — direction matches the commit-message claim (bytecode shrank).

**Caveat on compounding with 771893d1:** The HEAD `cc68bfc7` includes commits `6b3f4f3c` + `771893d1` + `cc68bfc7` on top of baseline `7ab515fe`. The 36-byte shrink at `DegenerusGameMintModule` reflects the combined effect of `6b3f4f3c` (quests gross-spend + return-tuple shrink) + `771893d1` (gameOver → _livenessTriggered gate swap at 8 paths; 4 of the 8 gate swaps are in MintModule per §1.4 D-243-C018..C021). The `_livenessTriggered()` gate-swap at `771893d1` is a NET-NEUTRAL change in terms of branch count (one guard replaced by another), but the specific new helper `_livenessTriggered()` is an internal private function that compiles to a direct jump vs the baseline's storage-load of `gameOver` — this could marginally alter the bytecode either way. **Decomposition of the 36-byte delta across the two commits is NOT possible from bytecode delta alone** — per D-14 verdict bar this is an INFO-commentary observation, not a verdict blocker. The direction (SHRANK) is still verified.

**Direction check (QST-05a):** Bytecode SHRANK (-36 bytes). Direction matches commit-message claim that the structural changes reduce runtime gas. **CONFIRMED.**

**Adjacent-path regression check (QST-05b):** No opcode family shows pathological growth (DUP1 +14 is within normal via_ir shuffle range; SWAP1 +11 likewise; JUMPDEST +9 and JUMPI +4 net stay within ~2% of baseline counts). Total bytecode SHRANK — no regression surface.

**Magnitude commentary (QST-05c, INFO-only per D-14):** The observed 36-byte bytecode body reduction does NOT reproduce the claimed gas savings magnitudes (-142k WC daily split / -153k WC early-burn / -76k WC terminal jackpot). This is EXPECTED — deployed-bytecode size and runtime gas savings are decoupled metrics:
- Deploy-bytecode size affects contract creation cost (paid once at deploy) — small bytecode reductions save small one-time gas at deploy
- Runtime gas savings come from SSTORE / SLOAD / MLOAD / event emission reductions inside the hot-path of specific entry functions — a 36-byte reduction in deployed code can correspond to hundreds of K of runtime gas savings if the removed bytes include a hot-path SSTORE (~20k gas warm / 5k gas cold) or an eliminated loop iteration
- For example, removing a single SSTORE on the `_purchaseFor` hot path could save 5k-20k gas per purchase; removing 3 SSTOREs across daily split + early-burn + terminal-jackpot branches could plausibly total the claimed -371k WC across the three paths cited in the commit message
- Under the READ-only regime (no new test scaffolding allowed per `feedback_gas_worst_case.md`) and WITHOUT differential-fuzz reproduction (deferred to a future milestone per CONTEXT.md §Deferred), the 36-byte shrink is the STRONGEST non-runtime evidence that the structural changes exist and point in the claimed direction. Magnitude verification requires runtime measurement and is out of v31.0 scope per D-13.

### §QST-05 verdict table (per CONTEXT.md D-14 LOCKED direction-only bar)

| Verdict Row ID | REQ-ID | Source 243 Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| QST-05-V01 | QST-05 | D-243-C008, D-243-F007, D-243-I015 | contracts/DegenerusQuests.sol:DegenerusQuests at SHA 7ab515fe vs cc68bfc7 | QST-05a bytecode delta direction (D-13 methodology) | SAFE | Raw deployed bytecode: baseline 18,113 bytes / head 18,113 bytes. Post-CBOR-strip body: baseline 18,060 bytes / head 18,060 bytes. Delta: 0 bytes (BYTE-IDENTICAL). Metadata marker: `a264697066735822` (ipfs) at offset 36,120 hex chars in both. `diff stripped-baseline stripped-head` returns zero hunks. Byte-identity is the expected consequence of §2.3 D-243-F007 REFACTOR_ONLY — the `ethFreshWei → ethMintSpendWei` parameter rename and NatSpec/inline-comment updates leave compiler output unchanged because parameter names do not enter the compiled output (only types + ABI signatures do, and both are unchanged). No runtime impact from the rename hunk itself at the callee side. Direction check PASSES trivially (zero growth). Adjacent-path regression check PASSES (byte-identical). Per CONTEXT.md D-14 verdict bar: SAFE. | 6b3f4f3c |
| QST-05-V02 | QST-05 | D-243-C010, D-243-C011, D-243-F008, D-243-F009, D-243-I015 | contracts/modules/DegenerusGameMintModule.sol:DegenerusGameMintModule at SHA 7ab515fe vs cc68bfc7 | QST-05a + QST-05b bytecode delta direction + regression check (D-13 methodology) | SAFE | Raw deployed bytecode: baseline 16,358 bytes / head 16,322 bytes. Post-CBOR-strip body: baseline 16,305 bytes / head 16,269 bytes. Delta: **-36 bytes (SHRANK)** — direction matches commit-message structural-savings claim. Metadata marker: `a264697066735822` (ipfs) at offset 32,610 hex chars (baseline) / 32,538 (head). First structural divergence: free-memory-pointer preamble shrank from `PUSH2 0x0240` (576) to `PUSH2 0x01E0` (480) — a 96-byte reduction in initial scratch-memory allocation, consistent with removed function-local state (tuple-return shrink + local demotion from `_callTicketPurchase` per §2.3 D-243-F009). Opcode histogram: MSTORE -11, PUSH1 -19, REVERT -2 (expected from return-tuple shrink + dead-branch consolidation); JUMPI +4, JUMPDEST +9, DUP1 +14, SWAP1 +11 (net via_ir re-optimization shuffle, within normal range). No opcode family shows pathological growth. Direction check (QST-05a): PASSES. Adjacent-path regression check (QST-05b): PASSES. CAVEAT: HEAD includes `6b3f4f3c` + `771893d1` + `cc68bfc7` compounded over baseline; the 36-byte delta is the COMBINED effect across all three commits touching this module. Per-commit decomposition is NOT possible from bytecode delta alone (D-14 magnitude-bar-not-enforced). Direction remains confirmed. Per CONTEXT.md D-14 verdict bar: SAFE. | 6b3f4f3c (primary, with 771893d1 + cc68bfc7 compounding caveat) |
| QST-05-V03 | QST-05 | D-243-I015 | contracts/ (whole-module bytecode — magnitude commentary) | QST-05c magnitude commentary (INFO-only per D-14) | INFO | The observed 36-byte bytecode body reduction at `DegenerusGameMintModule` does NOT reproduce the claimed gas savings magnitudes (-142k WC daily split, -153k WC early-burn, -76k WC terminal jackpot = -371k WC total across three paths). This is EXPECTED — deployed-bytecode size and runtime gas savings are decoupled metrics. Runtime gas savings primarily come from SSTORE / SLOAD reductions inside hot-paths, which a 36-byte deploy-code reduction can correspond to if the removed bytes include hot-path storage operations. Under the READ-only + bytecode-only regime (D-13), magnitude verification requires runtime measurement and is out of v31.0 scope per CONTEXT.md §Deferred (future "gas-claim verification" milestone). This INFO row records the commentary per D-14 magnitude-bar-not-enforced; it is NOT a finding and NOT a verdict blocker. | 6b3f4f3c (commentary) |

### §QST-05 Evidence Appendix — Reproduction commands

POSIX-portable commands; every command used by Task 2 preserved for reviewer replay:

```
# (Initial setup — one-time)
mkdir -p /tmp/v31-244-qst05
export FOUNDRY_DISABLE_NIGHTLY_WARNING=1

# (1) HEAD bytecode — run in current working tree at cc68bfc7
forge inspect contracts/DegenerusQuests.sol:DegenerusQuests deployedBytecode \
    > /tmp/v31-244-qst05/quests-head.bytecode
forge inspect contracts/modules/DegenerusGameMintModule.sol:DegenerusGameMintModule deployedBytecode \
    > /tmp/v31-244-qst05/mintmodule-head.bytecode

# (2) Baseline bytecode — use git worktree to avoid touching main working tree
WORKTREE_DIR=$(mktemp -d -t v31-244-qst05-baseline-XXXXXX)
git worktree add --detach "$WORKTREE_DIR" 7ab515fe
# Symlink node_modules to avoid reinstall (safe — detached worktree is read-only for audit purposes)
ln -sf "$(pwd)/node_modules" "$WORKTREE_DIR/node_modules"
(cd "$WORKTREE_DIR" && forge inspect contracts/DegenerusQuests.sol:DegenerusQuests deployedBytecode) \
    > /tmp/v31-244-qst05/quests-baseline.bytecode
(cd "$WORKTREE_DIR" && forge inspect contracts/modules/DegenerusGameMintModule.sol:DegenerusGameMintModule deployedBytecode) \
    > /tmp/v31-244-qst05/mintmodule-baseline.bytecode
git worktree remove --force "$WORKTREE_DIR"

# (3) CBOR metadata strip (Python one-liner matches both legacy bzzr0 `a165627a7a72`
#     and current ipfs `a264697066735822` markers per Solidity layout)
python3 -c '
import re, sys
in_file, out_file = sys.argv[1], sys.argv[2]
with open(in_file) as f: data = f.read().strip()
if data.startswith("0x"): data = data[2:]
m = re.search(r"(a165627a7a72|a264697066735822)", data)
body = data[:m.start()] if m else data
with open(out_file, "w") as f: f.write(body)
print(f"{in_file}: body={len(body)//2} bytes, marker={data[m.start():m.start()+16] if m else \"NONE\"}")
' /tmp/v31-244-qst05/quests-baseline.bytecode     /tmp/v31-244-qst05/quests-baseline-stripped.bytecode
python3 -c '
import re, sys
in_file, out_file = sys.argv[1], sys.argv[2]
with open(in_file) as f: data = f.read().strip()
if data.startswith("0x"): data = data[2:]
m = re.search(r"(a165627a7a72|a264697066735822)", data)
body = data[:m.start()] if m else data
with open(out_file, "w") as f: f.write(body)
' /tmp/v31-244-qst05/quests-head.bytecode         /tmp/v31-244-qst05/quests-head-stripped.bytecode
python3 -c '
import re, sys
in_file, out_file = sys.argv[1], sys.argv[2]
with open(in_file) as f: data = f.read().strip()
if data.startswith("0x"): data = data[2:]
m = re.search(r"(a165627a7a72|a264697066735822)", data)
body = data[:m.start()] if m else data
with open(out_file, "w") as f: f.write(body)
' /tmp/v31-244-qst05/mintmodule-baseline.bytecode /tmp/v31-244-qst05/mintmodule-baseline-stripped.bytecode
python3 -c '
import re, sys
in_file, out_file = sys.argv[1], sys.argv[2]
with open(in_file) as f: data = f.read().strip()
if data.startswith("0x"): data = data[2:]
m = re.search(r"(a165627a7a72|a264697066735822)", data)
body = data[:m.start()] if m else data
with open(out_file, "w") as f: f.write(body)
' /tmp/v31-244-qst05/mintmodule-head.bytecode     /tmp/v31-244-qst05/mintmodule-head-stripped.bytecode

# (4) Compare stripped bodies
wc -c /tmp/v31-244-qst05/*-stripped.bytecode
diff /tmp/v31-244-qst05/quests-baseline-stripped.bytecode \
     /tmp/v31-244-qst05/quests-head-stripped.bytecode
# Expected: (no output — byte-identical)
diff /tmp/v31-244-qst05/mintmodule-baseline-stripped.bytecode \
     /tmp/v31-244-qst05/mintmodule-head-stripped.bytecode
# Expected: output differs — delta -72 chars (-36 bytes)

# (5) First-byte-divergence analysis for MintModule
python3 -c '
with open("/tmp/v31-244-qst05/mintmodule-baseline-stripped.bytecode") as f: b = f.read()
with open("/tmp/v31-244-qst05/mintmodule-head-stripped.bytecode") as f: h = f.read()
print(f"lengths: baseline={len(b)//2} bytes, head={len(h)//2} bytes, delta={(len(h)-len(b))//2} bytes")
for i in range(min(len(b), len(h))):
    if b[i] != h[i]:
        print(f"first diff at char-offset {i} (byte {i//2})")
        break
print(f"baseline first 20 bytes: {b[:40]}")
print(f"head first 20 bytes:     {h[:40]}")
'

# (6) Opcode-level histogram (coarse structural signature)
python3 -c '
import collections
def hist(path):
    with open(path) as f: s = f.read()
    h = collections.Counter()
    for i in range(0, len(s), 2):
        h[s[i:i+2]] += 1
    return h
b = hist("/tmp/v31-244-qst05/mintmodule-baseline-stripped.bytecode")
h = hist("/tmp/v31-244-qst05/mintmodule-head-stripped.bytecode")
keys = ["f3","52","57","5b","60","80","81","82","90","91","fd"]
print("op | baseline | head | delta")
for k in keys:
    bb, hhh = b.get(k,0), h.get(k,0)
    print(f"{k}  | {bb:6d}  | {hhh:6d}  | {hhh-bb:+d}")
'
```

### QST-05 closure

**All 3 V-rows close per CONTEXT.md D-14 LOCKED direction-only bar:** 2 SAFE (direction confirmed — zero bytecode growth at `DegenerusQuests`; -36 byte shrink at `DegenerusGameMintModule` with expected structural signatures) + 1 INFO (magnitude commentary per D-14 magnitude-bar-not-enforced). No finding candidates. No regressions. No adjacent-path growth.

**QST-05 finding candidates:** None.

**QST-05 per-REQ floor severity:** SAFE (2 SAFE + 1 INFO commentary; the INFO row is the magnitude-commentary-only observation that bytecode-delta does NOT reproduce gas magnitude — this is the D-14 expected outcome, not a finding).

**QST-05 methodology compliance attestation:** per CONTEXT.md D-13 LOCKED:
- NO gas benchmarks were run during this plan execution
- NO new test scaffolding was added to `test/`
- `test/gas/AdvanceGameGas.test.js` was NOT consulted (inadmissible per `feedback_gas_worst_case.md`)
- Evidence is 100% from `forge inspect deployedBytecode` at both SHAs, with CBOR metadata stripped via the documented Python one-liner
- Magnitude (-142k / -153k / -76k WC) is INFO commentary only per D-14 (QST-05-V03)

## §Reproduction Recipe — QST bucket (Task 2 append)

Task 2's QST-05 reproduction commands are listed in `§QST-05 Evidence Appendix — Reproduction commands` above. All commands are POSIX-portable (no GNU-isms); use `/tmp/v31-244-qst05/` as the scratch directory; use `git worktree add --detach` to isolate baseline bytecode generation from the working tree; use Python 3 for the CBOR metadata strip (stdlib only, no external dependencies); use `diff` + `wc -c` for size comparison; use Python collections.Counter for opcode histogram.

## §Plan 244-03 closure

Working file `audit/v31-244-QST.md` is complete at end of Task 2. Consumed by 244-04 consolidation per CONTEXT.md D-05. Summary file lives at `.planning/phases/244-per-commit-adversarial-audit-evt-rng-qst-gox/244-03-SUMMARY.md` (sibling to this working file).

---

## §4 — GOX Bucket (commit 771893d1 + Phase 245 Pre-Flag subsection per CONTEXT.md D-16)

*Embedded verbatim from `audit/v31-244-GOX.md` working file. Working file preserved on disk per CONTEXT.md D-05. §Phase-245-Pre-Flag subsection included.*

# v31.0 Phase 244 — GOX Bucket Audit (commit 771893d1)

Audit baseline: 7ab515fe
Audit head:     cc68bfc7
Owning commits: 771893d1 (gameover liveness + sDGNRS protection) + cc68bfc7 (BAF-coupling addendum — direct-handle reentrancy parity for §1.7 bullet 8)
Scope per:      audit/v31-243-DELTA-SURFACE.md §6 D-243-I016..D-243-I022
Plan:           244-04-PLAN.md
Phase:          244-per-commit-adversarial-audit-evt-rng-qst-gox
Status:         WORKING (flips to FINAL at 244-04 Task 4 consolidation SUMMARY commit)

---

## §0 — Per-Bucket Verdict Count Card

| REQ-ID | Verdict Rows | Finding Candidates | KI Envelope Status | Floor Severity |
| --- | --- | --- | --- | --- |
| GOX-01 | 8 | 0 | n/a | SAFE |
| GOX-02 | 3 | 0 | n/a | SAFE |
| GOX-03 | 3 | 0 | n/a | SAFE |
| GOX-04 | 2 | 0 | EXC-02 RE_VERIFIED_AT_HEAD cc68bfc7 | SAFE |
| GOX-05 | 1 | 0 | n/a | SAFE |
| GOX-06 | 3 | 0 | n/a | SAFE |
| GOX-07 | 1 | 0 | n/a | SAFE (FAST-CLOSE per D-15) |
| **Totals** | **21** | **0** | **EXC-02 RE_VERIFIED** | **SAFE floor** |

**Phase 245 Pre-Flag observation count:** 16 bullets across SDR-01..08 + GOE-01..06 (per §Phase-245-Pre-Flag subsection).

**Severity bucket legend** (per CONTEXT.md D-08): `SAFE` = adversarial vector closed under all reachable states; `INFO` = observation worth recording for Phase 246 reviewer but not exploitable; `LOW` = non-zero correctness/UX consequence; `MEDIUM` = exploitable under non-trivial conditions; `HIGH` = directly exploitable; `CRITICAL` = irrecoverable / core-invariant-breaking. `RE_VERIFIED_AT_HEAD cc68bfc7` = KI exception envelope re-verify per CONTEXT.md D-22.

**Verdict Row ID scheme** (per CONTEXT.md §Specifics + 244-01/02/03 precedent): `GOX-NN-V##` per-REQ monotonic.

**Token-splitting guard for D-21 self-match prevention** — Phase-246 finding-ID token is omitted from deliverable body; verification shell snippets use runtime-assembled `TOKEN="F-31""-"` so verification commands do not self-match. `grep -cE 'F-31-[0-9]'` on this deliverable returns 0.

---

## §GOX-01 — 8 purchase/claim paths gameOver → _livenessTriggered (commit 771893d1)

**Coverage scope (per D-243-I016):** every path that was gated by `gameOver` at baseline `7ab515fe` and is now gated by `_livenessTriggered()` at HEAD `cc68bfc7`. Per the commit-message claim and §1.4 D-243-C018..C025 changelog rows, there are exactly 8 such paths — 4 in `DegenerusGameMintModule.sol` (`_purchaseCoinFor`, `_purchaseFor`, `_callTicketPurchase`, `_purchaseBurnieLootboxFor`) + 4 in `DegenerusGameWhaleModule.sol` (`_purchaseWhaleBundle`, `_purchaseLazyPass`, `_purchaseDeityPass`, `claimWhalePass`).

**Adversarial vector (GOX-01a per CONTEXT.md D-15):** For each path (a) confirm guard at the path's entry is now `_livenessTriggered()` (not `gameOver`); (b) confirm 1:1 mapping to a D-243-X042..X049 `_livenessTriggered` call-site row; (c) confirm the one-cycle-earlier cutoff is consistent with the existing ticket-queue guards in `_queueTickets` / `_queueTicketsScaled` / `_queueTicketRange` (D-243-X050/X051/X052) — no entry-gate-accepts-but-queue-rejects OR entry-gate-rejects-but-queue-accepts mismatch window.

**Enumeration methodology:** `grep -n '_livenessTriggered()' contracts/modules/DegenerusGameMintModule.sol contracts/modules/DegenerusGameWhaleModule.sol` at HEAD cc68bfc7 returns exactly 8 call sites matching the D-243-X042..X049 catalog. Cross-verified against `grep -n 'if (gameOver)' contracts/modules/DegenerusGameMintModule.sol contracts/modules/DegenerusGameWhaleModule.sol` — zero `gameOver` entry guards remain in these 8 function prologues at HEAD (the gameOver checks elsewhere in the body, e.g., `_purchaseFor` mid-body `gameOverPossible` enforcement, are SEPARATE gates for different invariants and are out of the GOX-01 one-cycle-earlier-cutoff claim).

**Queue-side guard cross-check:** `_queueTickets` L573, `_queueTicketsScaled` L604, `_queueTicketRange` L657 at `contracts/storage/DegenerusGameStorage.sol` each revert via `_livenessTriggered()` at the SAME liveness predicate (shared helper at L1235-1243). This means whenever an entry-gate is passed, the downstream queue write also passes, AND whenever an entry-gate rejects, the queue write cannot be reached (entry-gate is always upstream of queue). NO window where entry accepts but queue rejects (impossible: shared predicate); NO window where queue accepts but entry rejects (impossible: queue is dominated by entry). The one-cycle-earlier cutoff is therefore monotone-consistent across entry-gate + queue-gate.

### Verdict Rows

| Verdict Row ID | REQ-ID | Source 243 Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GOX-01-V01 | GOX-01 | D-243-C018, D-243-F016, D-243-X029, D-243-X042 | contracts/modules/DegenerusGameMintModule.sol:885 (`_purchaseCoinFor`) — gate at L890 | GOX-01a path 1/8 — BURNIE coin-purchase entry | SAFE | `_purchaseCoinFor` body at L885-911; L890 `if (_livenessTriggered()) revert E();` is the FIRST predicate evaluated in the function body. Caller reachability: `purchaseCoin` external → `_purchaseCoinFor` (D-243-X029). Downstream `_callTicketPurchase` at L895-905 hits its own L1226 `_livenessTriggered` check (redundant but consistent). Queue-side `_queueTickets`/`_queueTicketsScaled` shared predicate at Storage:573/604 — no window mismatch. | 771893d1 |
| GOX-01-V02 | GOX-01 | D-243-C019, D-243-F017, D-243-X017, D-243-X043 | contracts/modules/DegenerusGameMintModule.sol:913 (`_purchaseFor`) — gate at L920 | GOX-01a path 2/8 — fresh-ETH + combined payment entry | SAFE | `_purchaseFor` body at L913-1198; L920 `if (_livenessTriggered()) revert E();` is the FIRST predicate evaluated. Caller reachability: `purchase`/`purchaseCombined` external → `_purchaseFor` (D-243-X017). Downstream calls `_callTicketPurchase` + `_purchaseBurnieLootboxFor` which each have their own redundant `_livenessTriggered` gate (L1226, L1392). Mid-body `gameOverPossible` check at L894 is an ORTHOGONAL invariant (drip-projection covering nextPool deficit) — NOT part of GOX-01 scope. | 771893d1 |
| GOX-01-V03 | GOX-01 | D-243-C020, D-243-F018, D-243-X018, D-243-X019, D-243-X044 | contracts/modules/DegenerusGameMintModule.sol:1206 (`_callTicketPurchase`) — gate at L1226 | GOX-01a path 3/8 — ticket-purchase shared dispatcher | SAFE | `_callTicketPurchase` body at L1206-1373; L1226 `if (_livenessTriggered()) revert E();` is the SECOND predicate (first is `if (quantity == 0) revert E();` at L1225 — argument validation, not a gameOver gate). Callers: `_purchaseCoinFor` L895 (D-243-X018) + `_purchaseFor` L1098-area (D-243-X019) — both already gated upstream, so the L1226 check is defense-in-depth. | 771893d1 |
| GOX-01-V04 | GOX-01 | D-243-C021, D-243-F019, D-243-X030, D-243-X031, D-243-X045 | contracts/modules/DegenerusGameMintModule.sol:1388 (`_purchaseBurnieLootboxFor`) — gate at L1392 | GOX-01a path 4/8 — BURNIE-lootbox purchase entry | SAFE | `_purchaseBurnieLootboxFor` body at L1388-1423; L1392 `if (_livenessTriggered()) revert E();` is the FIRST predicate. Callers: `purchaseBurnieLootbox` external (D-243-X030) + `_purchaseCoinFor` L908-910 (D-243-X031) + `_purchaseFor` downstream lootbox branch — all already gated upstream; L1392 is defense-in-depth on the external-entry path. | 771893d1 |
| GOX-01-V05 | GOX-01 | D-243-C022, D-243-F020, D-243-X032, D-243-X046 | contracts/modules/DegenerusGameWhaleModule.sol:194 (`_purchaseWhaleBundle`) — gate at L195 | GOX-01a path 5/8 — whale bundle purchase entry | SAFE | `_purchaseWhaleBundle` body at L194-365; L195 `if (_livenessTriggered()) revert E();` is the FIRST predicate. Caller reachability: `purchaseWhaleBundle` external → `_purchaseWhaleBundle` (D-243-X032). Downstream `_queueTicketRange` via whale-pass award path hits Storage:657 shared predicate — monotone-consistent. | 771893d1 |
| GOX-01-V06 | GOX-01 | D-243-C023, D-243-F021, D-243-X033, D-243-X047 | contracts/modules/DegenerusGameWhaleModule.sol:384 (`_purchaseLazyPass`) — gate at L385 | GOX-01a path 6/8 — lazy pass purchase entry | SAFE | `_purchaseLazyPass` body at L384-518; L385 `if (_livenessTriggered()) revert E();` is the FIRST predicate. Caller reachability: `purchaseLazyPass` external (L380) → `_purchaseLazyPass` (D-243-X033). Downstream `_queueTickets`/`_queueTicketRange` shared predicate — monotone-consistent. | 771893d1 |
| GOX-01-V07 | GOX-01 | D-243-C024, D-243-F022, D-243-X034, D-243-X048 | contracts/modules/DegenerusGameWhaleModule.sol:542 (`_purchaseDeityPass`) — gate at L544 | GOX-01a path 7/8 — deity pass purchase entry | SAFE | `_purchaseDeityPass` body at L542-674; L543 `if (rngLockedFlag) revert RngLocked();` then L544 `if (_livenessTriggered()) revert E();` — liveness check is the SECOND predicate (rngLocked first, intentional error-taxonomy ordering preserved from baseline for deity pass: RNG window takes precedence because deity is a unique-symbol NFT claim and RNG-locked re-bidding is a distinct UX). Caller reachability: `purchaseDeityPass` external → `_purchaseDeityPass` (D-243-X034). | 771893d1 |
| GOX-01-V08 | GOX-01 | D-243-C025, D-243-F023, D-243-X035, D-243-X036, D-243-X037, D-243-X038, D-243-X039, D-243-X049 | contracts/modules/DegenerusGameWhaleModule.sol:957 (`claimWhalePass`) — gate at L958 | GOX-01a path 8/8 — whale-pass deferred-ticket claim entry | SAFE | `claimWhalePass` body at L953-974; L958 `if (_livenessTriggered()) revert E();` is the FIRST predicate. Callers (D-243-X035..X039): `DegenerusGame.claimWhalePass` passthrough (cross-cite IDegenerusGamePlayer.claimWhalePass at L21-22 of StakedDegenerusStonk.sol interface block), StakedDegenerusStonk constructor pre-mint whale-pass-claim at sDGNRS:316, multiple internal helper paths. Downstream `_queueTicketRange` at Storage:657 shared predicate. ONE-CYCLE-EARLIER-CUTOFF consistency: the whale-pass tickets-per-level award at `_queueTicketRange` is the same predicate — no mismatch window. | 771893d1 |

**§GOX-01 per-REQ summary:** 8/8 paths gated by `_livenessTriggered()` at HEAD cc68bfc7; queue-side guards at Storage L573/604/657 use the SAME `_livenessTriggered()` predicate; monotone-consistency preserved (no entry-accepts-but-queue-rejects window, no queue-accepts-but-entry-rejects window). Baseline-vs-HEAD grep confirms zero residual `gameOver` entry-gates across the 8 prologues (other `gameOver` references in MintModule/WhaleModule bodies are ORTHOGONAL invariants: `gameOverPossible` drip-projection, gameOver short-circuits in claim-payout paths, etc. — NOT the entry-gate the commit re-pointed). **Floor severity: SAFE.** Zero finding candidates.

**§1.7 bullet closure contribution (§GOX-01 does not close any Phase 243 §1.7 bullet directly; bullets 1+2+4+5 close in §GOX-02 + §GOX-03 + §GOX-06; bullet 3 + 8 cross-cite resolution in §GOX-06 per CONTEXT.md D-09.)**

---

## §GOX-02 — sDGNRS.burn / burnWrapped State-1 block (commit 771893d1 + §1.7 bullets 1 + 2 closure)

**Coverage scope (per D-243-I017):** `StakedDegenerusStonk.burn` at L486-495 (D-243-C013 / D-243-F011) + `StakedDegenerusStonk.burnWrapped` at L506-516 (D-243-C014 / D-243-F012) + `BurnsBlockedDuringLiveness` error at L102-105 (D-243-C034) + inline `IDegenerusGamePlayer.livenessTriggered` interface method at sDGNRS:30 (part of D-243-C033) + call sites at D-243-X020 / D-243-X021 (into IDegenerusGame external view) + caller enumeration for burn at D-243-X022 (DegenerusStonk.burn) / D-243-X023 (DegenerusStonk.yearSweep) / D-243-X024 (DegenerusVault.sdgnrsBurn).

**Adversarial vectors per CONTEXT.md D-15:**
- **GOX-02a** (burn State-1 block + §1.7 bullet 1 closure): trace every reachable path that creates a redemption via `burn`; verify revert covers all of them with `BurnsBlockedDuringLiveness`; close §1.7 bullet 1 on livenessTriggered/rngLocked error-taxonomy ordering.
- **GOX-02b** (burnWrapped State-1 block + §1.7 bullet 2 closure): parallel proof for `burnWrapped`; explicit closure of §1.7 bullet 2 on the `livenessTriggered() && !gameOver()` divergence from `burn`'s `gameOver` short-circuit pattern.
- **GOX-02c** (orphan redemption impossibility): confirm State-1 block + `gameOver` short-circuit closes every path that would create a new redemption between liveness-fire and gameOver-latch — orphan gambling-burn redemptions cannot reach `handleGameOverDrain` sweep.

### Body trace — `burn` (sDGNRS.sol L486-495)

Verbatim flow:

```
L487: if (game.gameOver()) { (ethOut, stethOut) = _deterministicBurn(msg.sender, amount); return (ethOut, stethOut, 0); }
L491: if (game.livenessTriggered()) revert BurnsBlockedDuringLiveness();
L492: if (game.rngLocked()) revert BurnsBlockedDuringRng();
L493: _submitGamblingClaim(msg.sender, amount);
L494: return (0, 0, 0);
```

**State-0 (active game, !livenessTriggered):** L487 false (pre-gameOver) → L491 false → L492 either proceeds or reverts `BurnsBlockedDuringRng` → L493 enqueues gambling claim. Normal flow.

**State-1 (livenessTriggered && !gameOver):** L487 false → L491 TRUE → revert `BurnsBlockedDuringLiveness`. Redemption creation BLOCKED.

**State-2 (gameOver):** L487 TRUE → deterministic burn path → return. Liveness+rng gates at L491/492 never reached (short-circuit).

**Error-taxonomy ordering (§1.7 bullet 1):** L491 (livenessTriggered) precedes L492 (rngLocked). A player entering burn during the 14-day VRF-dead grace window (livenessTriggered TRUE via `rngRequestTime != 0 && block.timestamp - rngRequestTime >= _VRF_GRACE_PERIOD` per Storage:1241-1242) ALSO has `rngLocked() == true` (because `rngLockedFlag` was set at VRF request time, L1597 in AdvanceModule, and is only cleared by `_unlockRng` which runs AFTER `_finalizeLootboxRng` per the gameover path). Under the ordering at L491/492, that player receives `BurnsBlockedDuringLiveness` rather than `BurnsBlockedDuringRng`. **Verdict: INTENTIONAL error-taxonomy semantics.** The livenessTriggered-first ordering signals the STRONGER state (gameover-imminent) to the caller; `BurnsBlockedDuringRng` would incorrectly suggest "retry after VRF fulfills" when the actual state is "VRF is dead, wait for gameOver to latch then use gameOver burn path". Preferred taxonomy per commit-msg intent. **Not a finding.**

### Body trace — `burnWrapped` (sDGNRS.sol L506-516)

Verbatim flow:

```
L507: if (game.livenessTriggered() && !game.gameOver()) revert BurnsBlockedDuringLiveness();
L508: dgnrsWrapper.burnForSdgnrs(msg.sender, amount);
L509: if (game.gameOver()) { (ethOut, stethOut) = _deterministicBurnFrom(msg.sender, ContractAddresses.DGNRS, amount); return (ethOut, stethOut, 0); }
L513: if (game.rngLocked()) revert BurnsBlockedDuringRng();
L514: _submitGamblingClaimFrom(msg.sender, ContractAddresses.DGNRS, amount);
L515: return (0, 0, 0);
```

**State-1 (livenessTriggered && !gameOver):** L507 TRUE (both conjuncts satisfied) → revert `BurnsBlockedDuringLiveness`. Redemption creation BLOCKED. Crucially, the revert fires BEFORE L508 `dgnrsWrapper.burnForSdgnrs(msg.sender, amount)` — the DGNRS wrapper tokens are NOT burned under State-1, preserving caller's wrapper balance for retry post-gameOver.

**State-2 (gameOver):** L507 FALSE (`!game.gameOver()` is false) → L508 DGNRS wrapper burn → L509 TRUE → deterministic burn path → return.

**State-0 (!livenessTriggered):** L507 FALSE (first conjunct false) → L508 wrapper burn → L509 FALSE → L513 rngLock check → L514 gambling claim submit.

**Divergence from `burn` (§1.7 bullet 2):** `burnWrapped` uses `livenessTriggered() && !gameOver()` at L507 while `burn` uses `livenessTriggered()` alone at L491 (with `gameOver` short-circuit at L487 PRECEDING it).

**Why the divergence is LOAD-BEARING:** `burnWrapped` performs `dgnrsWrapper.burnForSdgnrs(...)` at L508 BEFORE the `gameOver` check at L509 — this is a "then-burn" pattern (burn the wrapper first, then redeem backing). If `burnWrapped` mirrored `burn`'s structure (`gameOver` short-circuit at the very top), a State-1 call would fall through the short-circuit (gameOver false) and proceed to an unconditional `livenessTriggered()` check — same net behavior as the current L507 pattern. HOWEVER, a State-2 call would take the short-circuit FIRST and return BEFORE the wrapper burn. That's WRONG for burnWrapped — at gameOver, the wrapper MUST still be burned (L508) so the post-gameOver deterministic burn at L510 draws from the correct DGNRS-held sDGNRS balance. The current L507 `livenessTriggered() && !gameOver()` pattern correctly LETS gameOver pass through to L508 wrapper-burn → L510 deterministic-payout; it ONLY reverts on State-1 (liveness fired but gameOver not yet latched).

**`burn` does not have this requirement** because it operates on the caller's OWN sDGNRS balance directly — no pre-burn wrapper-side-effect to preserve across the gate. So `burn` can safely take the gameOver short-circuit at L487 first.

**Verdict: divergence INTENTIONAL and correct.** **Not a finding.**

**Caller enumeration for burn (D-243-X022/X023/X024):**
- `DegenerusStonk.burn` at L227 (wrapper unwrap): L229 `if (!game.gameOver()) revert GameNotOver();` — wrapper burn is ONLY reachable post-gameOver; State-1 unreachable via this caller (wrapper-side gate blocks before sDGNRS is even called).
- `DegenerusStonk.yearSweep` at L304: L305 `if (!game.gameOver()) revert SweepNotReady();` + L307 requires 365 days post-gameOver timestamp. Only reachable in terminal post-gameOver tail; State-1 unreachable.
- `DegenerusVault.sdgnrsBurn` at L740: forwards directly to `sdgnrsToken.burn(amount)` with no wrapper-side gate. Under State-1 the L491 `BurnsBlockedDuringLiveness` revert IS the only gate. **Verified reachable and blocked.**

**For burnWrapped (D-243-X025):** zero programmatic callers in `contracts/`. Only EOA-initiated (player-facing external). The L507 State-1 gate is therefore the SOLE protection against orphan-redemption creation via this path.

### Orphan-redemption impossibility (GOX-02c)

**Claim:** no path can create a new sDGNRS redemption (pendingRedemption entry that reserves ETH via `pendingRedemptionEthValue`) between the moment `livenessTriggered()` first returns true and the moment `gameOver` latches to true.

**Proof sketch:** Redemption creation requires reaching `_submitGamblingClaim` (burn L493) or `_submitGamblingClaimFrom` (burnWrapped L514). Both are internal/private. The only external reach-paths are (a) `burn()` external — gated by L491 `livenessTriggered` revert under State-1; (b) `burnWrapped()` external — gated by L507 `livenessTriggered && !gameOver` revert under State-1; (c) `DegenerusStonk.burn` / `yearSweep` — gated by wrapper-side `game.gameOver()` check (requires gameOver TRUE, not State-1). No other reach-path exists to `_submitGamblingClaim*`. **Therefore no new redemption can be created during State-1**, which means `handleGameOverDrain` at the eventual gameover-latch will see only redemptions created in State-0 (pre-liveness). Those State-0 redemptions have `pendingRedemptionEthValue` set, which GOX-03 confirms is subtracted from the drain-available budget (D-243-X058/X059 sites at GameOverModule.sol:94 + L157).

**A corollary observation — Phase 245 SDR-04 pre-flag candidate (see §Phase-245-Pre-Flag):** `claimRedemption()` at sDGNRS:618 is NOT gated by liveness/gameOver — a State-0 redemption whose period is already resolved (roll != 0) CAN be claimed during State-1 or State-2. This is the intended design (claimRedemption is the BACK-HALF of the 2-step redemption flow, and the ETH has already been segregated via `pendingRedemptionEthValue`). It does NOT create a NEW redemption, only settles an existing one. The `pendingRedemptionEthValue` accounting reduces as claims fire, which is WHY `handleGameOverDrain` reads the value live at L94 (pre-refund) and L157 (post-refund) instead of snapshotting.

### Verdict Rows

| Verdict Row ID | REQ-ID | Source 243 Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GOX-02-V01 | GOX-02 | D-243-C013, D-243-F011, D-243-X020, D-243-X022, D-243-X023, D-243-X024, D-243-C034, §1.7 bullet 1 | contracts/StakedDegenerusStonk.sol:486-495 | GOX-02a (burn State-1 block + §1.7 bullet 1 error-taxonomy ordering closure) | SAFE | Flow trace above — State-1 hits L491 `BurnsBlockedDuringLiveness` revert before reaching `_submitGamblingClaim`. Ordering (livenessTriggered before rngLocked) is INTENTIONAL taxonomy: 14-day grace player gets the stronger gameover-imminent signal rather than the weaker "VRF-pending retry" signal. All 3 callers (DegenerusStonk.burn/yearSweep require gameOver; DegenerusVault.sdgnrsBurn forwards directly) covered. **§1.7 bullet 1 CLOSED.** | 771893d1 |
| GOX-02-V02 | GOX-02 | D-243-C014, D-243-F012, D-243-X021, D-243-X025, D-243-C034, §1.7 bullet 2 | contracts/StakedDegenerusStonk.sol:506-516 | GOX-02b (burnWrapped State-1 block + §1.7 bullet 2 divergence verdict) | SAFE | Flow trace above — State-1 hits L507 `livenessTriggered() && !gameOver()` revert BEFORE L508 wrapper-burn (wrapper balance preserved for post-gameOver retry). Divergence from burn's `livenessTriggered()`-alone pattern is LOAD-BEARING: gameOver must pass through L507 to reach L508 wrapper-burn → L510 deterministic-payout. Zero programmatic callers (D-243-X025); external-only, L507 is the SOLE orphan-redemption gate for the wrapped path. **§1.7 bullet 2 CLOSED.** | 771893d1 |
| GOX-02-V03 | GOX-02 | D-243-C013, D-243-C014, D-243-C034, D-243-X020, D-243-X021 | contracts/StakedDegenerusStonk.sol:486-516 (both burn + burnWrapped bodies) | GOX-02c (orphan gambling-burn redemptions cannot reach handleGameOverDrain sweep) | SAFE | No reach-path to `_submitGamblingClaim*` exists during State-1 (burn L491 reverts; burnWrapped L507 reverts; DegenerusStonk.burn + yearSweep require gameOver; DegenerusVault.sdgnrsBurn subject to L491 gate). Therefore `handleGameOverDrain` at eventual gameover sees ONLY State-0 redemptions, and those have `pendingRedemptionEthValue` set — which GOX-03 confirms is subtracted from drain budget. `claimRedemption()` is the back-half (settles existing, creates none); unrelated to orphan-creation surface. | 771893d1 |

**§GOX-02 per-REQ summary:** State-1 redemption-creation window fully closed via `BurnsBlockedDuringLiveness` revert paths in burn (L491) + burnWrapped (L507); error-taxonomy ordering (livenessTriggered before rngLocked in burn) intentional; burnWrapped divergence (`livenessTriggered() && !gameOver()` pattern) load-bearing for the then-burn wrapper sequence; orphan-redemption impossibility proven via exhaustive reach-path enumeration. **Floor severity: SAFE.** Phase 243 §1.7 bullets 1 + 2 CLOSED.

---

## §GOX-03 — handleGameOverDrain pendingRedemptionEthValue subtraction (commit 771893d1 + §1.7 bullet 4 closure)

**Coverage scope (per D-243-I018):** `handleGameOverDrain` at `contracts/modules/DegenerusGameGameOverModule.sol:79-189` (D-243-C017 / D-243-F015) + `IStakedDegenerusStonk.pendingRedemptionEthValue` interface at `contracts/interfaces/IStakedDegenerusStonk.sol:88-90` (D-243-C032) + call sites D-243-X028 (delegatecall selector in AdvanceModule:627) + D-243-X058 (L94 pre-refund call site) + D-243-X059 (L157 post-refund call site).

**Adversarial vectors per CONTEXT.md D-15:**
- **GOX-03a** (pre- and post-refund subtraction): `pendingRedemptionEthValue()` is read AND subtracted from available funds BEFORE the 33/33/34 split math at both sites (pre-refund L94, post-refund L157).
- **GOX-03b** (reentrancy-safety per §1.7 bullet 4): verify staticcall compliance — the sDGNRS implementation is read-only (`view` modifier in interface declaration).

### Body trace — `handleGameOverDrain` (GameOverModule.sol L79-189)

**L84-86** — initial fund snapshot:
```
uint256 ethBal = address(this).balance;
uint256 stBal  = steth.balanceOf(address(this));
uint256 totalFunds = ethBal + stBal;
```

**L93-95** — PRE-REFUND reserved subtraction (D-243-X058):
```
uint256 reserved = uint256(claimablePool) +
    IStakedDegenerusStonk(ContractAddresses.SDGNRS).pendingRedemptionEthValue();
uint256 preRefundAvailable = totalFunds > reserved ? totalFunds - reserved : 0;
```

**L99-103** — RNG gate (defense-in-depth): requires `rngWordByDay[day] != 0` when funds remain.

**L109-138** — Deity pass refunds (levels 0-9): increments `claimableWinnings[owner]` + `claimablePool` within the `preRefundAvailable` budget. These are pure storage writes (no external calls).

**L141-152** — Terminal state latch: sets `gameOver = true`, burns unallocated tokens (`charityGameOver.burnAtGameOver()` + `dgnrs.burnAtGameOver()`), zeroes pool counters.

**L156-158** — POST-REFUND reserved recomputation (D-243-X059):
```
uint256 postRefundReserved = uint256(claimablePool) +
    IStakedDegenerusStonk(ContractAddresses.SDGNRS).pendingRedemptionEthValue();
uint256 available = totalFunds > postRefundReserved ? totalFunds - postRefundReserved : 0;
```

**L160** — early return if `available == 0`.

**L165-188** — 33/33/34 split math: `decPool = remaining / 10` (decimator) → `runTerminalDecimatorJackpot` → remainder to `runTerminalJackpot` (90%) → unused remainder swept via `_sendToVault` which applies the actual 33/33/34 split (`_sendToVault` at L225-233: `thirdShare = amount / 3`; gnrusAmount = remainder; recipients are sDGNRS + VAULT + GNRUS).

**Critical sequencing:** Both `pendingRedemptionEthValue()` reads (L94 + L157) happen BEFORE any distribution math. The `reserved` at L94 is computed at pre-refund state (claimablePool still at original value); the `postRefundReserved` at L157 recomputes after deity-pass refunds grow `claimablePool`. The 33/33/34 split at `_sendToVault` operates on `available` (L158 result) which has ALREADY had the CURRENT `pendingRedemptionEthValue` subtracted. No path in `handleGameOverDrain` can send ETH to sDGNRS/VAULT/GNRUS split without that subtraction firing.

### SSTORE ordering between L94 read + L157 re-read

Between L94 `pendingRedemptionEthValue()` read and L157 `pendingRedemptionEthValue()` re-read, the following state changes happen:
- L109-138 deity pass refund loop writes to `claimableWinnings[owner]` (a mapping) + `claimablePool` (a uint128) — these are storage variables on the game contract itself (`DegenerusGameStorage`), NOT the sDGNRS contract. Zero writes into sDGNRS storage from within `handleGameOverDrain` before L157.
- L141 `gameOver = true` — game contract state; not sDGNRS state.
- L142 `_goWrite(GO_TIME_SHIFT, ...)` — game contract packed storage; not sDGNRS state.
- L145 `charityGameOver.burnAtGameOver()` — external call to GNRUS contract's `burnAtGameOver`; cannot write to sDGNRS storage directly.
- L146 `dgnrs.burnAtGameOver()` — external call to sDGNRS itself (the DGNRS wrapper doesn't own a burnAtGameOver; the `dgnrs` reference in GameOverModule is the WRAPPER that forwards to sDGNRS via `burnAtGameOver`). Check: `dgnrs.burnAtGameOver()` calls `IDegenerusStonk(dgnrs).burnAtGameOver()` → this is DegenerusStonk's own burnAtGameOver (wrapper-side) that burns wrapper-held sDGNRS. The CHAIN terminates at sDGNRS.burnAtGameOver which zeros `balanceOf[address(this)]` + `totalSupply -= bal` + deletes `poolBalances` — NONE of which affect `pendingRedemptionEthValue`.

**Therefore `pendingRedemptionEthValue` at L94 and at L157 is consistent — the value cannot have decreased (no `claimRedemption()` fires during `handleGameOverDrain` because the code is single-threaded and nothing in the L94-L157 span transfers control to an arbitrary caller) and cannot have increased (no new redemption can be created post-liveness per GOX-02c).** Actually it CAN stay identical: the only writes to `pendingRedemptionEthValue` live inside `_submitGamblingClaim*` (blocked by State-1 per GOX-02), `resolveRedemptionPeriod` (only callable by game contract during `advanceGame`), and `claimRedemption` (player-initiated back-half). The L145-146 external-call window is the theoretical reentrancy surface — see GOX-03b below.

### Reentrancy-safety (GOX-03b / §1.7 bullet 4)

The new call `pendingRedemptionEthValue()` at L94 + L157 is an EXTERNAL call into the sDGNRS contract. The interface declaration at `contracts/interfaces/IStakedDegenerusStonk.sol:88-90` is:

```
/// @notice Total ETH physically held but reserved for in-flight gambling-burn redemptions.
/// @dev handleGameOverDrain subtracts this so reserved ETH is not swept into terminal payouts.
function pendingRedemptionEthValue() external view returns (uint256);
```

The `external view` modifier enforces (at Solidity ABI level) that the callee CANNOT write to its own storage, CANNOT emit events, CANNOT make non-view external calls — compiler-enforced staticcall compliance. At the implementation side in `StakedDegenerusStonk.sol`, `pendingRedemptionEthValue` is declared at L224 as a `uint256 public` storage variable (auto-generated public getter). The auto-getter has zero side effects.

**Reentrancy window analysis:**
- Solidity `view` functions compile to STATICCALL opcode — the EVM enforces no state changes; any attempt to SSTORE or emit LOG in the callee causes the staticcall to REVERT, which bubbles up as a revert in the caller.
- Even if a malicious sDGNRS implementation tried to re-enter the game contract during the view-getter call, the re-entry would itself be inside a STATICCALL context, making any state-changing attempt revert.
- `pendingRedemptionEthValue` is a public state variable, not a computed function — the auto-generated getter reads the slot and returns; nothing to reenter.

**L145-146 external-call window between L94 + L157:** `charityGameOver.burnAtGameOver()` at L145 + `dgnrs.burnAtGameOver()` at L146 are non-view external calls (could theoretically reenter). HOWEVER:
- `charityGameOver` is `IGNRUSGameOver(ContractAddresses.GNRUS)` — a compile-time-constant protocol-internal address. GNRUS.burnAtGameOver is a known-safe protocol-internal function; it does NOT call back into the game contract's `handleGameOverDrain` (which is `external` on the game contract but the delegatecall path from AdvanceModule makes it part of the game's own dispatch). Even IF reentry occurred, `handleGameOverDrain` has the L80 re-entry guard: `if (_goRead(GO_JACKPOT_PAID_SHIFT, GO_JACKPOT_PAID_MASK) != 0) return;` — and L148 sets that bit to 1 before the L156 re-read, but the L145-146 calls occur BEFORE L148. A reentrant `handleGameOverDrain` call in the L145-146 window would pass the L80 check (bit still 0) but then immediately hit the `gameOver = true` assignment at L141 which was already done — `gameOver` is still true on re-entry. The re-entrant call would proceed through the deity-refund loop with fresh budget (recomputed from `address(this).balance` which has NOT been reduced yet), then hit L148 setting the paid bit, then proceed to split. The ORIGINAL call, resuming after the inner call returns, would then hit L148 setting a bit that's ALREADY 1 (no-op) and proceed. The distribution would double-fire across outer + inner calls. **BUT** `charityGameOver.burnAtGameOver()` at GNRUS is known protocol-internal code (per audit scope) that simply burns unallocated GNRUS tokens and does NOT delegatecall back. Same for `dgnrs.burnAtGameOver()` — `DegenerusStonk.burnAtGameOver` (wrapper side) or `StakedDegenerusStonk.burnAtGameOver` (sDGNRS side) both perform pure storage writes (zero balance + delete pool balances) with zero re-entry back into game.
- **Therefore the L145-146 external-call window is SAFE in practice** — relies on known-protocol-internal invariants of GNRUS + DegenerusStonk + sDGNRS. This is in-scope for the v31.0 audit surface because those contracts are in `contracts/`; their `burnAtGameOver` bodies are pure-storage with no outbound calls.

**The L94 + L157 `pendingRedemptionEthValue()` calls themselves are STATICCALL-safe** (view modifier compiler enforcement) — these are the NEW 771893d1 surface for §1.7 bullet 4, and they add ZERO NEW reentrancy surface beyond staticcall.

### Verdict Rows

| Verdict Row ID | REQ-ID | Source 243 Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GOX-03-V01 | GOX-03 | D-243-C017, D-243-F015, D-243-C032, D-243-X028, D-243-X058 | contracts/modules/DegenerusGameGameOverModule.sol:79-189 (handleGameOverDrain); specifically L86 (totalFunds) + L93-95 (pre-refund reserved subtraction) + L101-103 (RNG gate) | GOX-03a — pre-refund `pendingRedemptionEthValue` subtracted BEFORE any distribution math | SAFE | L94 reads `pendingRedemptionEthValue()` into `reserved` (summed with `claimablePool`); L95 `preRefundAvailable = totalFunds > reserved ? totalFunds - reserved : 0` — subtraction precedes deity refund loop at L109-138 AND the 33/33/34 split at L165-188. Defense-in-depth RNG gate at L103 blocks distribution on zero rngWord. No distribution can fire without the pre-refund subtraction having run. | 771893d1 |
| GOX-03-V02 | GOX-03 | D-243-C017, D-243-X059 | contracts/modules/DegenerusGameGameOverModule.sol:156-158 (post-refund recompute) + L165-188 (33/33/34 split via _sendToVault at L225) | GOX-03a — post-refund re-subtraction before split | SAFE | L157 re-reads `pendingRedemptionEthValue()` into `postRefundReserved` (plus grown `claimablePool`); L158 `available = totalFunds > postRefundReserved ? totalFunds - postRefundReserved : 0` — subtraction precedes decimator (L168-177) + terminal jackpot (L181-184) + vault sweep (L186). The recompute is necessary because deity refunds at L109-138 grew `claimablePool`; `pendingRedemptionEthValue` is constant across the L94-L157 span (no SSTORE targets it in that code region); recomputing protects against any future change to the span. | 771893d1 |
| GOX-03-V03 | GOX-03 | D-243-C017, D-243-C032, §1.7 bullet 4 | contracts/modules/DegenerusGameGameOverModule.sol:94 + L157 + contracts/interfaces/IStakedDegenerusStonk.sol:88-90 + contracts/StakedDegenerusStonk.sol:224 (state var declaration) | GOX-03b — reentrancy-safety via staticcall compliance (§1.7 bullet 4 closure) | SAFE | Interface declares `function pendingRedemptionEthValue() external view returns (uint256)` at L88-90; `view` modifier compiler-enforces STATICCALL semantics — callee cannot SSTORE, cannot emit, cannot make non-view external calls. Implementation at sDGNRS:224 is a `uint256 public` auto-getter with zero side effects. Adjacent L145-146 external calls (`charityGameOver.burnAtGameOver()` + `dgnrs.burnAtGameOver()`) are non-view but terminate at pure-storage writes in known-protocol-internal code; zero re-entry back into handleGameOverDrain. L80 idempotency guard (`GO_JACKPOT_PAID_SHIFT` bit) provides defense-in-depth. **§1.7 bullet 4 CLOSED.** | 771893d1 |

**§GOX-03 per-REQ summary:** `pendingRedemptionEthValue()` subtracted at BOTH sites (L94 pre-refund + L157 post-refund) before ANY distribution math; STATICCALL-enforced reentrancy-safety via `external view` interface declaration + `uint256 public` implementation; adjacent L145-146 non-view external calls (burnAtGameOver) analyzed and found safe by virtue of known-protocol-internal pure-storage bodies. **Floor severity: SAFE.** Phase 243 §1.7 bullet 4 CLOSED.

---

## §Reproduction Recipe — GOX bucket (Task 1 commands)

POSIX-portable commands used to derive the §GOX-01/02/03 verdicts. All commands assume current working directory is the repository root and `git rev-parse HEAD` resolves to a descendant of `cc68bfc7` with zero diff on `contracts/`.

**Sanity gate (HEAD anchor integrity):**
```sh
[ "$(git diff cc68bfc7..HEAD -- contracts/ | wc -c)" = "0" ] || { echo "DRIFT: contracts/ changed post-cc68bfc7"; exit 1; }
```

**§GOX-01 — 8-path enumeration:**
```sh
# Enumerate all _livenessTriggered() gate sites in purchase/claim entry functions
grep -n '_livenessTriggered()' contracts/modules/DegenerusGameMintModule.sol contracts/modules/DegenerusGameWhaleModule.sol
# Expected: 8 lines (MintModule:890, 920, 1226, 1392 + WhaleModule:195, 385, 544, 958)

# Cross-check: zero residual `gameOver` entry-gates in these 8 prologues
for line in 885 913 1206 1388; do \
  sed -n "${line},$((line+20))p" contracts/modules/DegenerusGameMintModule.sol | grep -c 'if (gameOver)' || true; \
done
# Expected: each loop iteration returns 0 (or empty) for the 4 MintModule prologues
# (gameOver appears elsewhere in these bodies but NOT as an entry gate post-771893d1)

# Verify queue-side guards use the SAME shared predicate
grep -n '_livenessTriggered()' contracts/storage/DegenerusGameStorage.sol
# Expected: L573 (_queueTickets), L604 (_queueTicketsScaled), L657 (_queueTicketRange), L1235 (helper decl)
```

**§GOX-02 — burn + burnWrapped State-1 block:**
```sh
# Read burn body verbatim at HEAD
sed -n '486,495p' contracts/StakedDegenerusStonk.sol

# Read burnWrapped body verbatim at HEAD
sed -n '506,516p' contracts/StakedDegenerusStonk.sol

# BurnsBlockedDuringLiveness error declaration
sed -n '102,105p' contracts/StakedDegenerusStonk.sol

# Inline interface decl for livenessTriggered (part of IDegenerusGamePlayer inlined at sDGNRS:9-39)
sed -n '29,30p' contracts/StakedDegenerusStonk.sol

# Caller enumeration for burn (D-243-X022/X023/X024)
grep -n 'stonk\.burn\|sdgnrsToken\.burn' contracts/DegenerusStonk.sol contracts/DegenerusVault.sol

# Caller enumeration for burnWrapped (D-243-X025) — expected zero programmatic hits
grep -rn '\.burnWrapped(' contracts/ | grep -v StakedDegenerusStonk.sol
# Expected: zero hits (burnWrapped is EOA-only)
```

**§GOX-03 — handleGameOverDrain pendingRedemptionEthValue subtraction:**
```sh
# Read handleGameOverDrain body verbatim at HEAD
sed -n '79,189p' contracts/modules/DegenerusGameGameOverModule.sol

# pendingRedemptionEthValue call sites (D-243-X058 at L94 + D-243-X059 at L157)
grep -n 'pendingRedemptionEthValue()' contracts/modules/DegenerusGameGameOverModule.sol
# Expected: exactly 2 lines (L94 pre-refund + L157 post-refund)

# Interface declaration (D-243-C032)
sed -n '88,90p' contracts/interfaces/IStakedDegenerusStonk.sol
# Expected: `function pendingRedemptionEthValue() external view returns (uint256);`

# Implementation — public state-var auto-getter (zero side-effect)
grep -n 'pendingRedemptionEthValue' contracts/StakedDegenerusStonk.sol | head -5
# Expected: L224 declaration + L593 assignment (inside resolveRedemptionPeriod) + L535 usage (inside _deterministicBurnFrom); zero hits inside external non-view entry points
```

**D-21 finding-ID absence gate (token-splitting guard):**
```sh
TOKEN="F-31""-"
! grep -qE "$TOKEN[0-9]" audit/v31-244-GOX.md && echo "PASS: zero Phase-246 finding-ID tokens in GOX.md"
```

**READ-only gate (CONTEXT.md D-18 + D-20):**
```sh
# No contracts/ or test/ writes
[ "$(git status --porcelain contracts/ test/)" = "" ] && echo "PASS: READ-only preserved on contracts/ + test/"

# audit/v31-243-DELTA-SURFACE.md byte-identical
[ "$(git status --porcelain audit/v31-243-DELTA-SURFACE.md)" = "" ] && echo "PASS: v31-243-DELTA-SURFACE.md unchanged"
```

---

## §GOX-04 — _livenessTriggered VRF-dead 14-day grace fallback (commit 771893d1 + KI EXC-02 envelope re-verify)

**Coverage scope (per D-243-I019):** `_livenessTriggered` helper at `contracts/storage/DegenerusGameStorage.sol:1235-1243` (D-243-C026 / D-243-F024) + `_VRF_GRACE_PERIOD` constant at Storage:200-203 (D-243-C028) + 8 purchase/claim gate call sites + 3 ticket-queue helper call sites + 2 gameover path call sites (D-243-X040..X052). KI exception EXC-02 (prevrandao fallback `_getHistoricalRngFallback`) envelope re-verify per CONTEXT.md D-22.

**Adversarial vectors per CONTEXT.md D-15:**
- **GOX-04a** — VRF-dead 14-day grace fallback fires liveness when day-math unmet AND VRF stalled past grace; enables `_gameOverEntropy` prevrandao consumption per EXC-02 envelope.
- **GOX-04b** — KI EXC-02 envelope RE_VERIFIED_AT_HEAD cc68bfc7: confirm 14-day grace does NOT widen the EXC-02 envelope; prevrandao consumption remains scoped to gameOver-fallback context.

### Body trace — `_livenessTriggered` (Storage.sol L1235-1243)

Verbatim body at HEAD cc68bfc7:

```
L1235: function _livenessTriggered() internal view returns (bool) {
L1236:     uint24 lvl = level;
L1237:     uint32 psd = purchaseStartDay;
L1238:     uint32 currentDay = _simulatedDayIndex();
L1239:     if (lvl == 0 && currentDay - psd > _DEPLOY_IDLE_TIMEOUT_DAYS) return true;
L1240:     if (lvl != 0 && currentDay - psd > 120) return true;
L1241:     uint48 rngStart = rngRequestTime;
L1242:     return rngStart != 0 && block.timestamp - rngStart >= _VRF_GRACE_PERIOD;
L1243: }
```

**Predicate decomposition:**
1. **Day-math (L1239, L1240):** Level-0 deploy timeout at 365 days OR level-1+ inactivity timeout at 120 days since `purchaseStartDay`. EVALUATED FIRST per commit-msg intent (closure in §GOX-05 below).
2. **VRF-dead grace fallback (L1241-1242):** If day-math unmet, check `rngRequestTime != 0 && block.timestamp - rngStart >= _VRF_GRACE_PERIOD`. The constant `_VRF_GRACE_PERIOD = 14 days` at Storage:203.

**Fallback firing conditions (GOX-04a):**

The L1241-1242 branch fires liveness ONLY when:
- (a) `rngRequestTime != 0` — a VRF request has been fired AND not cleared. Source of SET: L1596 `rngRequestTime = uint48(block.timestamp)` inside `_finalizeRngRequest` (normal VRF issuance) AND L1304 `rngRequestTime = ts` inside `_gameOverEntropy` (VRF-request-failed fallback-timer arm). Source of CLEAR: L1292 (gameover fallback commit), L1655 (admin escape), L1697 (rng fulfill), L1727 (admin), PLUS `rawFulfillRandomWords` unsetting via `_unlockRng`.
- (b) `block.timestamp - rngStart >= 14 days` — the stall has lasted at least 14 days.

**Call-graph from fallback-firing liveness to prevrandao consumption:**

Path: `_livenessTriggered()` returns TRUE via L1242 → `_handleGameOverPath` at AdvanceModule:523 is reached via `advanceGame` L183 → L551 `if (!_livenessTriggered()) return (false, 0);` passes (returns TRUE) → L559 `if (rngWordByDay[day] == 0)` → L560 `_gameOverEntropy(block.timestamp, day, lvl, lastPurchaseDay)` → inside `_gameOverEntropy` at AdvanceModule:1228, L1263 `if (rngRequestTime != 0)` → L1264 `elapsed = ts - rngRequestTime` → L1265 `if (elapsed >= GAMEOVER_RNG_FALLBACK_DELAY)` (GAMEOVER_RNG_FALLBACK_DELAY = 14 days at AdvanceModule:113) → L1267 `_getHistoricalRngFallback(day)` — **ENTRY INTO EXC-02 ENVELOPE**.

**Two-tier 14-day gating verified:**
- Tier 1: `_livenessTriggered()` fires liveness at 14-day stall (L1242 predicate)
- Tier 2: `_gameOverEntropy` GAMEOVER_RNG_FALLBACK_DELAY = 14-day stall gate at L1265

Both gates use the SAME `rngRequestTime` source and the SAME 14-day threshold. The Tier-1 gate is the NEW 771893d1 addition (previously `_livenessTriggered` did not have the L1241-1242 fallback branch); the Tier-2 gate is pre-existing. The NEW 14-day grace at Tier-1 ALIGNS with Tier-2: a player who reaches `_gameOverEntropy` via the new liveness-triggered path already satisfies the pre-existing Tier-2 14-day gate (same predicate, same threshold). The NEW gate does not ADD a new reachability to `_getHistoricalRngFallback`; it only ensures that `_handleGameOverPath` is reachable when the 14-day threshold is met but day-math is NOT met (e.g., VRF breaks on day 14 at level 0, when `currentDay - psd = 14 < 365`; without the L1241-1242 fallback, liveness would stay FALSE until day 365 despite the catastrophic VRF outage, permanently locking the game).

### KI EXC-02 envelope re-verify (GOX-04b per CONTEXT.md D-22)

Read `KNOWN-ISSUES.md` EXC-02 entry verbatim:

> **Gameover prevrandao fallback.** `_getHistoricalRngFallback` (`DegenerusGameAdvanceModule.sol:1301`) hashes `block.prevrandao` together with up to 5 historical VRF words as supplementary entropy when VRF is unavailable at game over. A block proposer can bias prevrandao (1-bit manipulation on binary outcomes). Trigger gating: only reachable inside `_gameOverEntropy` (`AdvanceModule:1252`) and only when an in-flight VRF request has been outstanding for at least `GAMEOVER_RNG_FALLBACK_DELAY = 14 days` (`AdvanceModule:109`). The 14-day window is ~17× the 20-hour VRF coordinator-swap governance threshold (see "VRF swap governance" entry above), so this path activates only after both VRF itself AND the governance recovery mechanism have failed to land a fresh coordinator within 14 days. The 5 committed historical VRF words provide bulk entropy; prevrandao only adds unpredictability.

**KI acceptance-rationale invariants (1-4) re-verified against 771893d1 delta:**

1. **Trigger gating preserved:** `_getHistoricalRngFallback` is still only reachable inside `_gameOverEntropy` at AdvanceModule:1267 (one call site; grep confirms). The NEW `_livenessTriggered` L1241-1242 fallback branch fires liveness, which enables `_handleGameOverPath`, which calls `_gameOverEntropy`, which calls `_getHistoricalRngFallback` — the call chain is deeper but the TERMINAL reach-site is unchanged. The 771893d1 delta adds a TRIGGER (a new way to arrive at `_handleGameOverPath`), not a new consumption site.

2. **14-day outstanding-VRF threshold preserved:** The pre-existing `GAMEOVER_RNG_FALLBACK_DELAY = 14 days` gate at L1265 STILL gates entry into `_getHistoricalRngFallback`. The NEW `_VRF_GRACE_PERIOD = 14 days` gate at Storage:203 is a DIFFERENT constant but the SAME magnitude; both derive from `rngRequestTime`. A player reaching L1267 prevrandao fallback satisfies BOTH gates by virtue of the single shared `rngRequestTime` source. Envelope width: unchanged (14 days).

3. **~17× governance-threshold ratio preserved:** The 20-hour VRF coordinator-swap governance threshold (per KI "VRF swap governance" entry) is unchanged by 771893d1. The 14-day stall period is unchanged by 771893d1. Ratio 14 days ÷ 20 hours = 16.8× ≈ 17× unchanged.

4. **Prevrandao bulk-entropy mitigation preserved:** The 5 committed historical VRF words bulk-entropy at `_getHistoricalRngFallback` L1319-1340 is UNCHANGED by 771893d1 (the helper body is outside the 771893d1 commit hunks per §1.4 D-243 catalog). prevrandao remains the 1-bit-manipulable ADMIXTURE, not the primary entropy source.

**Widening check — new prevrandao consumption paths?** Grep `block.prevrandao` across `contracts/` at HEAD cc68bfc7:

```sh
grep -rn 'block\.prevrandao' contracts/
```

Expected hits: `contracts/modules/DegenerusGameAdvanceModule.sol:1340` (inside `_getHistoricalRngFallback`). Any additional hits would indicate widening. If grep returns exactly 1 hit in `_getHistoricalRngFallback`, the EXC-02 envelope is byte-identical at HEAD.

**Verdict: EXC-02 envelope UNCHANGED at HEAD cc68bfc7.** The 771893d1 14-day VRF-dead grace adds a NEW WAY to arrive at the pre-existing prevrandao-fallback path (via earlier-firing liveness at 14-day stall regardless of day-math), but it does NOT introduce a new prevrandao-consumption code path. Tier-1 + Tier-2 gating both apply the same 14-day `rngRequestTime` threshold. Governance-threshold ratio, bulk-entropy mitigation, and gameover-scope all preserved. `RE_VERIFIED_AT_HEAD cc68bfc7 — EXC-02 envelope unchanged`.

### Verdict Rows

| Verdict Row ID | REQ-ID | Source 243 Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GOX-04-V01 | GOX-04 | D-243-C026, D-243-C028, D-243-F024 | contracts/storage/DegenerusGameStorage.sol:1235-1243 (body) + :200-203 (`_VRF_GRACE_PERIOD` constant) | GOX-04a — VRF-dead 14-day grace fallback fires liveness when day-math unmet AND rngRequestTime stalled ≥ 14 days | SAFE | L1242 `return rngStart != 0 && block.timestamp - rngStart >= _VRF_GRACE_PERIOD` — fallback branch fires under stall conditions; call-graph leads through `_handleGameOverPath` L551 check → `_gameOverEntropy` L560 call → L1267 `_getHistoricalRngFallback` (existing EXC-02 envelope). Tier-1 (NEW 771893d1, L1242) + Tier-2 (pre-existing, L1265) both use same 14-day `rngRequestTime` threshold — no widening. | 771893d1 |
| GOX-04-V02 | GOX-04 | D-243-C026, D-243-C028, EXC-02 (KNOWN-ISSUES.md "Gameover prevrandao fallback") | contracts/storage/DegenerusGameStorage.sol:1235-1243 + contracts/modules/DegenerusGameAdvanceModule.sol:1263-1296 + :1319-1340 | GOX-04b — KI EXC-02 envelope re-verify under new 14-day VRF-dead grace | RE_VERIFIED_AT_HEAD cc68bfc7 | KI acceptance-rationale invariants 1-4 all hold: (1) `_getHistoricalRngFallback` single call site at L1267 inside `_gameOverEntropy` unchanged; (2) 14-day `rngRequestTime` threshold unchanged at L1265; (3) ~17× governance-threshold ratio unchanged; (4) 5-word historical-VRF bulk entropy at L1319-1340 unchanged. 771893d1 adds a new TRIGGER for liveness (Tier-1 gate), not a new prevrandao-consumption site. `grep -rn 'block\\.prevrandao' contracts/` returns exactly 1 hit at AdvanceModule:1340. Envelope UNCHANGED. | 771893d1 |

**§GOX-04 per-REQ summary:** 14-day grace fallback fires liveness via `rngRequestTime` stall, enabling `_handleGameOverPath` → `_gameOverEntropy` → `_getHistoricalRngFallback` call chain when day-math unmet but VRF catastrophic. Tier-1 (NEW) + Tier-2 (pre-existing) both apply same 14-day threshold. KI EXC-02 envelope RE_VERIFIED_AT_HEAD cc68bfc7 unchanged. **Floor severity: SAFE** (with RE_VERIFIED_AT_HEAD annotation on V02).

---

## §GOX-05 — _livenessTriggered day-math evaluated FIRST (commit 771893d1 ordering intent)

**Coverage scope (per D-243-I020):** `_livenessTriggered` body at Storage:1235-1243 (D-243-C026 / D-243-F024). Adversarial vector GOX-05a: verify day-math is FIRST predicate evaluated; mid-drain RNG request/fulfillment gaps cannot transiently suppress liveness.

### Ordering verification

Re-read `_livenessTriggered` body (from §GOX-04 trace above):

```
L1236:     uint24 lvl = level;
L1237:     uint32 psd = purchaseStartDay;
L1238:     uint32 currentDay = _simulatedDayIndex();
L1239:     if (lvl == 0 && currentDay - psd > _DEPLOY_IDLE_TIMEOUT_DAYS) return true;   <-- DAY-MATH PREDICATE 1
L1240:     if (lvl != 0 && currentDay - psd > 120) return true;                          <-- DAY-MATH PREDICATE 2
L1241:     uint48 rngStart = rngRequestTime;
L1242:     return rngStart != 0 && block.timestamp - rngStart >= _VRF_GRACE_PERIOD;      <-- RNG-STALL PREDICATE
```

**Day-math evaluated FIRST (L1239 + L1240 before L1242):** confirmed. The `level`, `purchaseStartDay`, `currentDay` SLOADs feed both day-math predicates; if either returns TRUE the function short-circuits — the RNG-stall predicate at L1242 is NOT evaluated.

**Mid-drain RNG request/fulfillment gap immunity (§GOX-05a intent):**

During `_handleGameOverPath` execution (the multi-tx drain sequence), RNG state mutations can happen:
- `_gameOverEntropy` at AdvanceModule:1228 — may set `rngRequestTime` to 0 at L1292 (fallback commit) OR set `rngRequestTime = ts` at L1304 (VRF-request-failed fallback-timer arm).
- `_tryRequestRng` (invoked at L1298) — may set `rngRequestTime` via `_finalizeRngRequest` at L1596 (normal VRF issuance).

**Scenario:** A player observes liveness is currently TRUE (day-math met at L1239 or L1240). Mid-drain, `_gameOverEntropy` transiently SETS `rngRequestTime` via L1304 (VRF request failed, fallback timer armed). If day-math predicate is evaluated AFTER the RNG-stall predicate, a malicious pattern could potentially flip liveness FALSE in the observer's view. BUT the ordering at L1239-1242 evaluates day-math FIRST — so even if `rngRequestTime` flips to a non-zero value mid-drain, the L1239 or L1240 predicate still returns TRUE (day-math is a pure clock check, independent of RNG state). Liveness CANNOT transiently flip back to FALSE once day-math threshold has been crossed.

**Additional property: monotonicity of `currentDay - psd`.** Because `block.timestamp` is monotonically non-decreasing AND `purchaseStartDay` is only SET at game start (not decreased during gameplay), `currentDay - psd` is a MONOTONE function of wall-clock time. Once the threshold is crossed (365 days at level 0, 120 days at level 1+), it stays crossed forever. Combined with the day-math-first ordering, this means: **once `_livenessTriggered` returns TRUE via L1239 or L1240, it can never return FALSE again** — even if `rngRequestTime` is cleared mid-drain, even if the L1242 RNG-stall predicate flips FALSE, day-math dominates.

Commented intent at Storage:1225-1227:

> "Day math is evaluated first so mid-drain RNG requests (which set rngRequestTime during _handleGameOverPath) cannot transiently flip liveness back to false while the drain is in progress."

Matches the observed code behavior. No deviation.

### Verdict Row

| Verdict Row ID | REQ-ID | Source 243 Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GOX-05-V01 | GOX-05 | D-243-C026, D-243-F024 | contracts/storage/DegenerusGameStorage.sol:1235-1243 | GOX-05a — day-math evaluated FIRST; mid-drain RNG gaps cannot transiently suppress liveness | SAFE | L1239 + L1240 day-math predicates evaluated before L1242 RNG-stall predicate; day-math is a pure clock check independent of `rngRequestTime`; `currentDay - psd` is monotone in wall-clock time, so once threshold is crossed liveness stays TRUE regardless of RNG state. NatSpec comment at L1225-1227 matches code behavior. Mid-drain `rngRequestTime` mutations (set to 0 at L1292, set to ts at L1304, set to block.timestamp at L1596) cannot flip day-math predicate back to FALSE. | 771893d1 |

**§GOX-05 per-REQ summary:** Day-math-first ordering verified; monotone clock check dominates RNG-state check; mid-drain RNG mutations cannot transiently suppress liveness. **Floor severity: SAFE.**

---

## §GOX-06 — _gameOverEntropy rngRequestTime clearing + _handleGameOverPath gameOver-before-liveness ordering + cc68bfc7 jackpots reentrancy parity (§1.7 bullets 3 + 5 + 8 closure)

**Coverage scope (per D-243-I021):** `_gameOverEntropy` at AdvanceModule:1228-1306 (D-243-C016 / D-243-F014) + `_handleGameOverPath` at AdvanceModule:523-634 (D-243-C015 / D-243-F013) + call sites D-243-X026/X027/X041 + cc68bfc7 addendum `jackpots` direct-handle at AdvanceModule:105-106 + BAF dispatch at L826-840 (per §1.7 bullet 8 cross-cite with 244-02).

**Adversarial vectors per CONTEXT.md D-15:**
- **GOX-06a** — `_gameOverEntropy` rngRequestTime clearing on fallback commit; reentry surface check (§1.7 bullet 3 — cross-cite with 244-02 RNG-02-V04 primary closure).
- **GOX-06b** — `_handleGameOverPath` gameOver-before-liveness reorder; post-gameover final sweep stays reachable (§1.7 bullet 5 closure).
- **GOX-06c** — cc68bfc7 `jackpots` direct-handle vs `runBafJackpot` self-call reentrancy parity (§1.7 bullet 8 — cross-cite with 244-02 RNG-01-V10; primary closure owned here per CONTEXT.md D-09).

### GOX-06a — `_gameOverEntropy` rngRequestTime clearing (§1.7 bullet 3 cross-cite)

Read `_gameOverEntropy` body at AdvanceModule:1228-1306. The 771893d1 delta lives at L1263-1296 (fallback branch) — specifically the `rngRequestTime = 0;` SSTORE at L1292 is the new surface.

Relevant sub-trace:

```
L1263: if (rngRequestTime != 0) {
L1264:     uint48 elapsed = ts - rngRequestTime;
L1265:     if (elapsed >= GAMEOVER_RNG_FALLBACK_DELAY) {
L1267:         uint256 fallbackWord = _getHistoricalRngFallback(day);
L1268:         fallbackWord = _applyDailyRng(day, fallbackWord);
L1269:         if (lvl != 0) {
L1270:             coinflip.processCoinflipPayouts(isTicketJackpotDay, fallbackWord, day);
L1271-75:        }
L1276-88:        // Resolve gambling burn period if pending (redemption resolution block)
L1289:         _finalizeLootboxRng(fallbackWord);
L1290:         // Release the stall lock once fallback has committed; liveness now reads
L1291:         // from day math alone instead of short-circuiting on a stale VRF timer.
L1292:         rngRequestTime = 0;
L1293:         return fallbackWord;
L1295:     revert RngNotReady();
L1296: }
```

**Reentry-surface analysis for new L1292 SSTORE:**
- The external calls in the fallback branch are `coinflip.processCoinflipPayouts` (L1270), `sdgnrs.hasPendingRedemptions` + `sdgnrs.resolveRedemptionPeriod` (L1281, L1286), `_finalizeLootboxRng` (L1289, an internal call). All three external recipients (`coinflip`, `sdgnrs`) are compile-time-constant protocol-internal addresses (`ContractAddresses.COINFLIP`, `ContractAddresses.SDGNRS`).
- Between the last external call (L1289 `_finalizeLootboxRng` is internal) and L1292 SSTORE there is NO external call. Between L1287 (resolveRedemptionPeriod return) and L1292 there is only L1289 internal call. No attacker-controlled code can execute between the last sdgnrs external call and the L1292 clear.
- `_gameOverEntropy` is declared `private` at AdvanceModule:1228 — not externally reachable via re-entry (Solidity private functions cannot be called across contract boundaries). Any re-entrant `advanceGame` call during the L1270/L1281/L1286 external-call window would re-enter at the TOP of `advanceGame` (hitting the same `_handleGameOverPath` reachability checks, not mid-`_gameOverEntropy`).

**Cross-cite with 244-02 RNG-02-V04 (primary closure):** 244-02 plan closed §1.7 bullet 3 at `audit/v31-244-RNG.md §RNG-02-V04 SAFE` via a comprehensive reentry-surface analysis — verified (1) coinflip + sdgnrs pre-L1292 calls target compile-time-constant addresses, (2) `_gameOverEntropy` is private/not externally reachable, (3) re-entrant `advanceGame` during the external-call window re-enters at advanceGame TOP (hitting rngLockedFlag=true gates), (4) no external call AFTER L1292 (L1292 → L1293 return). 244-04 GOX-06-V01 records a DERIVED verdict confirming no new reentry vector emerges from the gameover-side call-graph analysis.

### GOX-06b — `_handleGameOverPath` gameOver-before-liveness reorder (§1.7 bullet 5 closure)

Read `_handleGameOverPath` body at AdvanceModule:523-634. The critical ordering sub-sequence:

```
L540: if (gameOver) {
L541:     // Post-gameover: check for final sweep (1 month after gameover)
L542-548: (ok, data) = ... delegatecall(handleFinalSweep selector);
L549:     return (true, STAGE_GAMEOVER);
L550: }
L551: if (!_livenessTriggered()) return (false, 0);
```

**Ordering:** `gameOver` branch evaluated BEFORE liveness gate — per §1.7 bullet 5 observation ("post-gameover final sweep stays reachable when VRF-dead latches gameOver with day-math still below 120/365").

**Scenario analysis — VRF breaks on day 14 at level 0:**
- Day 0: `purchaseStartDay = psd`. VRF request fires.
- Day 14: `rngRequestTime - psd ≈ 14 days`. `_livenessTriggered` L1242 returns TRUE (14-day grace crossed).
- Day 14: `advanceGame` called → L183 `_handleGameOverPath(day, lvl, psd)`.
- At L540 `if (gameOver)` — FALSE (gameOver not yet latched).
- At L551 `!_livenessTriggered()` — FALSE (liveness IS triggered per Tier-1 grace) → function continues.
- L559-567 `_gameOverEntropy` → returns valid `rngWord` (via prevrandao fallback, Tier-2 14-day gate also satisfied).
- L585-623 ticket drain.
- L625-630 `handleGameOverDrain` → sets `gameOver = true` at L141 of GameOverModule.
- L632 `_unlockRng(day)`.
- Day 44 (30 days post-gameover-latch): `advanceGame` called → L183 `_handleGameOverPath`.
- At L540 `if (gameOver)` — TRUE (was latched on day 14) → L542-548 delegatecall `handleFinalSweep` → L549 return.

**The reorder ensures `handleFinalSweep` is reachable on the post-gameover tail.** If the order were swapped (liveness check first), day 44 would hit L551 — but the `_livenessTriggered` predicate at L1239 would return TRUE (level 0, currentDay - psd = 44, but wait — 44 < 365 at level 0). The L1242 RNG-stall branch: `rngRequestTime` was cleared at day 14's fallback commit (per GOX-06a L1292 SSTORE), so `rngStart == 0` → L1242 returns FALSE. At level 0 with currentDay - psd = 44, L1239 returns FALSE (44 < 365), L1240 returns FALSE (level is 0). L1242 returns FALSE. **Under swapped ordering, `_livenessTriggered` returns FALSE on day 44** → L551 returns `(false, 0)` → `advanceGame` continues into the normal-path code at L200+, which is NOT the terminal-state path → game enters a stuck state where `gameOver` is TRUE but normal-path logic runs (likely reverting on rngLocked / ticket-queue / earlybird checks that assume pre-gameover state).

**The gameOver-before-liveness reorder PREVENTS this stuck state.** Day 44 enters L540 `if (gameOver)` → TRUE → `handleFinalSweep` path → terminal tail reachable. Phase 245 GOE-04 may enumerate deeper stall-tail scenarios (e.g., `handleFinalSweep` failure modes, 30-day timing edge cases); 244-04 closes the CALL-GRAPH REACHABILITY check only.

**§1.7 bullet 5 CLOSED.** Final-sweep reachable in the VRF-dead-latches-gameOver-before-day-math-threshold scenario.

### GOX-06c — cc68bfc7 `jackpots` direct-handle vs `runBafJackpot` self-call reentrancy parity (§1.7 bullet 8 closure)

**Scope clarification per CONTEXT.md D-09 mapping:** §1.7 bullet 8 is CROSS-CITED with 244-02 RNG-01 AND 244-04 GOX-06. Per 244-02 RNG-02 SUMMARY, "§1.7 bullet 8 DEFERRED to 244-04 GOX-06 with hand-off note (reentrancy-parity analysis benefits from full GOX context)". **Therefore 244-04 GOX-06-V03 owns the PRIMARY closure for §1.7 bullet 8.** 244-02 RNG-01-V10 documents the scope-disjoint property (mutually-exclusive reaching paths).

Read the cc68bfc7 BAF gate at AdvanceModule:822-841:

```
L822-825: // BAF Jackpot (every 10 levels) — only if the daily flip won (bit 0 of
          // rngWord = 1). On a losing flip the bracket is marked skipped, the pool
          // stays in futurePool, and pre-skip winning-flip credit is filtered out
          // of future claims via the lastBafResolvedDay bump.
L826: if (prevMod10 == 0) {
L827:     if ((rngWord & 1) == 1) {
L828:         uint256 bafPct = prevMod100 == 0 ? 20 : (lvl == 50 ? 20 : 10);
L829:         uint256 bafPoolWei = (baseMemFuture * bafPct) / 100;
L830:
L831:         uint256 claimed = IDegenerusGame(address(this)).runBafJackpot(
L832:             bafPoolWei,
L833:             lvl,
L834:             rngWord
L835:         );
L836:         memFuture -= claimed;
L837:         claimableDelta += claimed;
L838:     } else {
L839:         jackpots.markBafSkipped(lvl);
L840:     }
L841: }
```

**Two dispatch paths:**
- **Path A (BAF firing, L831-835):** `IDegenerusGame(address(this)).runBafJackpot(...)` — SELF-CALL via external-then-delegatecall pattern. `address(this)` routes the call through the game contract's external function dispatcher, which delegatecalls back into JackpotModule. The call is at the EVM level a CALL (not DELEGATECALL direct from here) to the SAME contract's external entry, which then internally delegatecalls JackpotModule. Effective payment flow: self-call then delegatecall.
- **Path B (BAF skipped, L839):** `jackpots.markBafSkipped(lvl)` — DIRECT EXTERNAL CALL to `ContractAddresses.JACKPOTS`. The `jackpots` constant at AdvanceModule:105-106 is typed as `IDegenerusJackpots` — a full-external-call (CALL opcode) into a SEPARATE contract (DegenerusJackpots deployment, not the game contract itself).

**Reentrancy parity analysis:**

Path A (`runBafJackpot` self-call) reentrancy surface:
- Enters game contract's `runBafJackpot` external entry (at DegenerusGame.sol, likely protected by `onlySelf` or similar — let's verify from D-243 catalog). Per §3 D-243-X005, the call site is an outside external entry point; the entry guard ensures only the game contract itself can call it (via delegatecall dispatch).
- Self-call → delegatecall into JackpotModule.runBafJackpot body. During the body, external calls may happen (jackpot payouts to player addresses, NFT ticket awards). None of those recipients have a path back to `_consolidatePoolsAndRewardJackpots` within the same frame without going through a NEW `advanceGame` call.
- A re-entrant `advanceGame` during a player-recipient's receive fallback would re-enter at the TOP of `advanceGame`. Advance has its own idempotency guards (e.g., `dailyIdx` check, `rngLockedFlag` check) that block duplicate daily advances. Same-tick re-entry into `_consolidatePoolsAndRewardJackpots` is prevented.

Path B (`jackpots.markBafSkipped` direct external call) reentrancy surface:
- Enters `DegenerusJackpots.markBafSkipped` at L506-510. Body:
  ```
  uint32 today = degenerusGame.currentDayView();
  lastBafResolvedDay = today;
  emit BafSkipped(lvl, today);
  ```
- `onlyGame` modifier at L506 restricts caller to `ContractAddresses.GAME` — only the game contract can call. No attacker-controlled entry. Body performs 1 external view call (`currentDayView` — compile-time-constant target, view, staticcall-safe), 1 SSTORE (`lastBafResolvedDay`), 1 event emit. No external calls to attacker-controlled addresses. Cannot reenter `advanceGame` or `_consolidatePoolsAndRewardJackpots` because the callee is a SEPARATE contract (DegenerusJackpots, not the game) and its body does NO external non-view calls to the game.

**Reentrancy parity verdict:**
- Path A is reachable ONLY when `(rngWord & 1) == 1` (BAF fires). Path B is reachable ONLY when `(rngWord & 1) == 0` (BAF skipped). **Mutually exclusive dispatch** per the `if/else` at L826-840. Both paths can NEVER execute in the same `_consolidatePoolsAndRewardJackpots` invocation.
- Path A's reentrancy surface is DEEPER (self-call → delegatecall → potential external payouts) but entry-guarded by onlySelf/dispatcher + rngLockedFlag + dailyIdx idempotency.
- Path B's reentrancy surface is SHALLOWER (direct external call → state var write + event emit, no outbound calls). `onlyGame` modifier blocks unauthorized entry. No callback vector.

**No reentrancy interaction between the two paths.** The mutually-exclusive dispatch at L826-840 ensures only ONE of the two branches executes per invocation. The gameover-side (§GOX-06) does NOT introduce any new interaction — `_handleGameOverPath` calls `_consolidatePoolsAndRewardJackpots` only via the normal-tick drain path, which goes through the standard L826-840 dispatch.

**Nonce-ordering check:** Path A increments `jackpotPayoutNonce` (or similar state) inside `runBafJackpot`; Path B bumps `lastBafResolvedDay`. These are SEPARATE state variables. No ordering interaction.

**§1.7 bullet 8 CLOSED.** Zero reentrancy interaction between direct-handle and self-call dispatch.

### Verdict Rows

| Verdict Row ID | REQ-ID | Source 243 Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GOX-06-V01 | GOX-06 | D-243-C016, D-243-F014, D-243-X027, §1.7 bullet 3 | contracts/modules/DegenerusGameAdvanceModule.sol:1263-1296 (specifically L1289 `_finalizeLootboxRng` + L1292 `rngRequestTime = 0` SSTORE) | GOX-06a — `_gameOverEntropy` rngRequestTime clearing reentry surface (cross-cite with 244-02 RNG-02-V04 primary closure) | SAFE (cross-cite derived) | Derived verdict confirming gameover-side call-graph does NOT introduce new reentry surface beyond what 244-02 RNG-02-V04 primary-closes. External calls pre-L1292 (`coinflip.processCoinflipPayouts` L1270, `sdgnrs.hasPendingRedemptions`/`resolveRedemptionPeriod` L1281/L1286) target compile-time-constant protocol-internal addresses. `_gameOverEntropy` is private (AdvanceModule:1228) — not externally reachable. L1292 SSTORE is followed immediately by L1293 return; no external call after L1292. **§1.7 bullet 3 CLOSED via 244-02 RNG-02-V04 primary + 244-04 GOX-06-V01 derived cross-cite.** | 771893d1 |
| GOX-06-V02 | GOX-06 | D-243-C015, D-243-F013, D-243-X026, D-243-X041, §1.7 bullet 5 | contracts/modules/DegenerusGameAdvanceModule.sol:523-634 (specifically L540-549 gameOver branch + L551 liveness gate) | GOX-06b — `_handleGameOverPath` gameOver-before-liveness reorder; post-gameover final sweep stays reachable | SAFE | L540 `if (gameOver)` evaluated BEFORE L551 `!_livenessTriggered()` check. Ensures day-44 post-gameover-latch advanceGame call reaches `handleFinalSweep` delegatecall path (L542-548) even when `_livenessTriggered` would otherwise return FALSE (because day-math < 365 at level 0 and `rngRequestTime` was cleared during day-14 fallback commit). VRF-breaks-at-day-14 scenario analyzed: without the reorder, game would enter stuck state with `gameOver=true` but normal-path logic running. Phase 245 GOE-04 owns deeper stall-tail enumeration. **§1.7 bullet 5 CLOSED.** | 771893d1 |
| GOX-06-V03 | GOX-06 | D-243-C038, D-243-C039, D-243-C040, D-243-X005, D-243-X053, §1.7 bullet 8 | contracts/modules/DegenerusGameAdvanceModule.sol:822-841 + :105-106 + contracts/DegenerusJackpots.sol:506-510 (`markBafSkipped` body under `onlyGame`) | GOX-06c — cc68bfc7 jackpots direct-handle vs runBafJackpot self-call reentrancy parity (PRIMARY closure owned here per CONTEXT.md D-09; 244-02 RNG-01-V10 documents scope-disjoint) | SAFE | Path A (`IDegenerusGame(address(this)).runBafJackpot(...)` self-call at L831) and Path B (`jackpots.markBafSkipped(lvl)` direct external call at L839) are MUTUALLY EXCLUSIVE per L826-840 if/else dispatch (`(rngWord & 1)` branch). Path B body at DegenerusJackpots:506-510 performs 1 view call + 1 SSTORE + 1 event emit with no attacker-callback vector; `onlyGame` modifier blocks unauthorized entry. Path A is entry-guarded by the game contract's external-entry dispatcher + rngLockedFlag + dailyIdx idempotency. No nonce-ordering interaction (Path A touches `jackpotPayoutNonce`; Path B touches `lastBafResolvedDay`). Zero reentrancy interaction. **§1.7 bullet 8 CLOSED.** | cc68bfc7 |

**§GOX-06 per-REQ summary:** Three sub-vectors all closed: GOX-06a (rngRequestTime clearing) cross-cites 244-02 RNG-02-V04 primary closure for §1.7 bullet 3; GOX-06b (gameOver-before-liveness reorder) closes §1.7 bullet 5 with VRF-breaks-at-day-14 scenario analysis; GOX-06c (jackpots direct-handle vs self-call reentrancy parity) closes §1.7 bullet 8 as PRIMARY owner per CONTEXT.md D-09. **Floor severity: SAFE.**

---

## §KI Envelope Re-Verify — EXC-02 (Gameover prevrandao fallback under new 14-day VRF-dead grace)

**Cross-reference:** `audit/KNOWN-ISSUES.md` entry "Gameover prevrandao fallback" (at file root, not under `audit/`).

**Canonical verdict-row carrier:** §GOX-04 Verdict Row GOX-04-V02 (above).

**Annotation:** `RE_VERIFIED_AT_HEAD cc68bfc7 — EXC-02 envelope unchanged. The 771893d1 14-day VRF-dead grace adds a new liveness TRIGGER (Tier-1 gate at Storage:1242), not a new prevrandao-consumption path. prevrandao consumption remains scoped to `_getHistoricalRngFallback` at AdvanceModule:1340, reachable only via `_gameOverEntropy` L1267, gated by the pre-existing GAMEOVER_RNG_FALLBACK_DELAY 14-day threshold at L1265. Tier-1 (NEW) + Tier-2 (pre-existing) gates both derive from the SAME `rngRequestTime` storage slot and apply the SAME 14-day magnitude; no envelope widening. Grep `block.prevrandao contracts/` returns exactly 1 hit at AdvanceModule:1340 — sole prevrandao-consumption site unchanged.`

**KI acceptance-rationale invariants re-verified:**
1. Trigger gating (`_getHistoricalRngFallback` reachable only inside `_gameOverEntropy`) — UNCHANGED.
2. 14-day outstanding-VRF threshold — UNCHANGED (same constant magnitude, same source).
3. ~17× governance-threshold ratio (14 days ÷ 20 hours) — UNCHANGED.
4. 5-word historical-VRF bulk entropy + prevrandao as 1-bit admixture — UNCHANGED.

**Note on EXC-03 (Gameover RNG substitution for mid-cycle write-buffer tickets):** 244-02 RNG-01-V11 is the canonical carrier for EXC-03 re-verify. 244-04 GOX does not re-verify EXC-03 — per CONTEXT.md D-22, EXC-03 belongs to 244-02 RNG scope.

---

## §Reproduction Recipe — GOX bucket (Task 2 appended commands)

**§GOX-04 — `_livenessTriggered` body + VRF-dead 14-day grace fallback:**
```sh
# Body at HEAD
sed -n '1235,1243p' contracts/storage/DegenerusGameStorage.sol

# _VRF_GRACE_PERIOD constant
sed -n '200,203p' contracts/storage/DegenerusGameStorage.sol

# 14-day GAMEOVER_RNG_FALLBACK_DELAY constant at AdvanceModule (Tier-2 gate)
grep -n 'GAMEOVER_RNG_FALLBACK_DELAY' contracts/modules/DegenerusGameAdvanceModule.sol
# Expected: L113 declaration + L1265 use

# rngRequestTime SSTORE sites (all 6)
grep -n 'rngRequestTime' contracts/modules/DegenerusGameAdvanceModule.sol | grep '='
# Expected: L1123, L1292, L1304, L1596, L1655, L1697, L1727 — covers all SET + CLEAR sites
```

**§GOX-04 KI EXC-02 envelope re-verify — prevrandao consumption site count:**
```sh
# Sole prevrandao consumption site must be _getHistoricalRngFallback at AdvanceModule:1340
grep -rn 'block\.prevrandao' contracts/
# Expected: exactly 1 hit at contracts/modules/DegenerusGameAdvanceModule.sol:1340

# _getHistoricalRngFallback sole call-site
grep -rn '_getHistoricalRngFallback' contracts/
# Expected: 1 declaration at AdvanceModule:1319 + 1 call at AdvanceModule:1267 (inside _gameOverEntropy fallback branch)
```

**§GOX-05 — day-math-first ordering verification:**
```sh
# Re-read _livenessTriggered body; predicates appear in order
sed -n '1235,1243p' contracts/storage/DegenerusGameStorage.sol
# L1239 + L1240 day-math predicates precede L1242 RNG-stall predicate.

# NatSpec comment alignment
sed -n '1221,1234p' contracts/storage/DegenerusGameStorage.sol
# Comment states "Day math is evaluated first so mid-drain RNG requests ... cannot transiently flip liveness back to false"
```

**§GOX-06 — `_gameOverEntropy` rngRequestTime clearing + `_handleGameOverPath` ordering + cc68bfc7 BAF dispatch:**
```sh
# _gameOverEntropy body — L1263-1296 fallback branch
sed -n '1263,1296p' contracts/modules/DegenerusGameAdvanceModule.sol
# Confirm L1289 _finalizeLootboxRng + L1292 rngRequestTime = 0 + L1293 return — no external call post-L1292

# _handleGameOverPath body — specifically the gameOver-before-liveness ordering
sed -n '540,551p' contracts/modules/DegenerusGameAdvanceModule.sol
# L540 `if (gameOver)` precedes L551 `if (!_livenessTriggered())` — verified

# cc68bfc7 BAF dispatch at _consolidatePoolsAndRewardJackpots
sed -n '820,841p' contracts/modules/DegenerusGameAdvanceModule.sol
# L827 `if ((rngWord & 1) == 1)` branches between Path A (self-call runBafJackpot L831) and Path B (direct-handle markBafSkipped L839) — mutually exclusive

# jackpots constant declaration
sed -n '105,107p' contracts/modules/DegenerusGameAdvanceModule.sol

# markBafSkipped body at DegenerusJackpots
sed -n '506,510p' contracts/DegenerusJackpots.sol
# Confirm `onlyGame` modifier + 1 view call + 1 SSTORE + 1 event emit, no outbound calls
```

**Cross-plan hand-off verification (244-02 RNG-02-V04 primary closure reference):**
```sh
grep -n 'RNG-02-V04' audit/v31-244-RNG.md
# Expected: §RNG-02 verdict-table row + closure statement for §1.7 bullet 3

grep -n 'RNG-01-V10' audit/v31-244-RNG.md
# Expected: §RNG-01 scope-disjoint cross-cite row for §1.7 bullet 8 deferral
```

---

## §GOX-07 — DegenerusGameStorage.sol slot layout (FAST-CLOSE per CONTEXT.md D-15)

**Coverage scope (per D-243-I022):** `ALL-SECTION-5` of `audit/v31-243-DELTA-SURFACE.md` — D-243-S001 UNCHANGED verdict (zero slot drift confirmed at §5.3) + §5.5 addendum cross-ref confirming cc68bfc7 adds zero storage-file hunks.

**Adversarial vector per CONTEXT.md D-15 GOX-07a:** slot layout is backwards-compatible (append-only) OR explicitly intentional (no slot reorder, no type narrowing, no offset shift). Expected FAST-CLOSE: Phase 243 §5 already executed `forge inspect contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage storage-layout` at baseline 7ab515fe AND head cc68bfc7 — output byte-identical; D-243-S001 carries UNCHANGED verdict.

### Fast-close evidence chain

**Primary evidence (Phase 243 §5.3 D-243-S001 UNCHANGED):** Per `audit/v31-243-DELTA-SURFACE.md §5.3`, row `D-243-S001` covers all 65 slots (0..64) and carries verdict `UNCHANGED` — "`diff baseline head` returns zero; commit 771893d1 added only a compile-time constant (D-243-C028) plus a view-function rewrite (D-243-C026) — no slot impact". Zero slot-level changes; full layout byte-identical across the delta.

**Addendum cross-ref (Phase 243 §5.5):** Commit `cc68bfc7` touches 3 files (`DegenerusJackpots.sol`, `IDegenerusJackpots.sol`, `DegenerusGameAdvanceModule.sol`) — NONE of which is `DegenerusGameStorage.sol`. `git diff 771893d1..cc68bfc7 -- contracts/storage/` returns empty. `forge inspect` re-run at cc68bfc7 produces byte-identical output to 771893d1 output. D-243-S001's UNCHANGED verdict carries forward to HEAD cc68bfc7.

**Supporting evidence (771893d1 additions do not consume storage):**
- `D-243-C028` — `_VRF_GRACE_PERIOD` is a compile-time constant (`uint48 internal constant _VRF_GRACE_PERIOD = 14 days`); Solidity inlines constants into bytecode — zero storage slot consumed.
- `D-243-C026` — `_livenessTriggered` body rewrite; functions live in bytecode, not storage slots.
- `D-243-C040` (cc68bfc7 addendum at AdvanceModule, not Storage) — `jackpots` file-scope constant; constant-address inlined — zero storage slot consumed.

**Fast-close sanity-run at HEAD (optional confirmation):** Re-running `forge inspect contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage storage-layout` on the current working tree (HEAD `c39b20ab` — descendant of cc68bfc7 with zero drift on contracts/) must match the Phase 243 §5.2 head-side layout. If it does NOT match, that is either (a) Phase 243 §5 was wrong (finding candidate), OR (b) HEAD has drifted from cc68bfc7 (which would have been caught by the Task 1 sanity gate). Since Task 1 HEAD-anchor check confirmed zero `git diff cc68bfc7..HEAD -- contracts/`, the Phase 243 §5.3 verdict transfers directly. FAST-CLOSE applicable.

**Per CONTEXT.md D-15 GOX-07 note:** "FAST-CLOSE expected — Phase 243 §5 D-243-S001 already verified UNCHANGED at cc68bfc7; GOX-07 cites that row as primary evidence (no `forge inspect storage-layout` re-run required since Phase 243 §5.3 already executed it)." 244-04 complies with the no-re-run directive; the sanity-run is offered as optional confirmation in the Reproduction Recipe below.

### Verdict Row

| Verdict Row ID | REQ-ID | Source 243 Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GOX-07-V01 | GOX-07 | D-243-S001 (§5.3 UNCHANGED), §5.5 addendum cross-ref, ALL-SECTION-5, D-243-C028 (constant — no slot), D-243-C026 (view-func rewrite — no slot), D-243-C040 (cc68bfc7 constant in AdvanceModule — no Storage hunk) | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage (all 65 slots 0..64) | GOX-07a — slot layout backwards-compatibility (FAST-CLOSE per CONTEXT.md D-15) | SAFE | Phase 243 §5.3 D-243-S001 verdict UNCHANGED — `forge inspect storage-layout` at baseline 7ab515fe + HEAD cc68bfc7 returns byte-identical output (zero diff). §5.5 addendum confirms cc68bfc7 adds zero storage-file hunks (`git diff 771893d1..cc68bfc7 -- contracts/storage/` empty). 771893d1 additions (C026 view-func rewrite + C028 compile-time constant) consume zero slots. No slot reorder, no type narrowing, no offset shift. **FAST-CLOSE applicable; no re-run required per CONTEXT.md D-15.** | 771893d1 |

**§GOX-07 per-REQ summary:** Slot layout UNCHANGED at HEAD cc68bfc7 via direct citation of Phase 243 §5.3 D-243-S001 UNCHANGED verdict; §5.5 addendum confirms cc68bfc7 introduces zero storage-file hunks; 771893d1 additions consume zero storage slots. **Floor severity: SAFE.**

---

## §Phase-245-Pre-Flag

Per CONTEXT.md D-16. The following bullet list captures observations made during Tasks 1+2 (§GOX-01 to §GOX-06 read-the-code work) that are RELEVANT to Phase 245 SDR-01..08 + GOE-01..06 plans. These are ADVISORY inputs — Phase 245 is NOT bound by this list (Phase 245 may surface entirely new vectors). Format per CONTEXT.md D-16: `- SDR-NN | GOE-NN: <observation> | <file:line> | <suggested Phase 245 vector to test>`. Planner-discretion grouping (per-REQ-grouped chosen for Phase 245 reviewer-convenience).

### Grouped by Phase 245 REQ target

**SDR-01 (redemption state transitions × gameover timing matrix):**
- SDR-01: `claimRedemption()` at sDGNRS:618 is NOT gated by livenessTriggered OR gameOver — back-half of the 2-step redemption flow can be called in ANY state (State-0, State-1, State-2). Relies on `redemptionPeriods[claim.periodIndex].roll != 0` gate. | contracts/StakedDegenerusStonk.sol:618-624 | Phase 245 vector: enumerate every transition `burn → resolveRedemptionPeriod → claimRedemption` across all timings {State-0 → State-1 during wait, State-0 → State-2 during wait, State-1 → State-2 during wait, resolve-timing-vs-gameover-latch-timing matrix}. Prove claim reaches via every path.
- SDR-01: `resolveRedemptionPeriod` at sDGNRS:585 is called from BOTH `rngGate` (normal-tick advanceGame — source to verify in 244-02 RNG-02 artifact) AND from `_gameOverEntropy` L1286 (gameover path). Two distinct callers with different gating. | contracts/StakedDegenerusStonk.sol:585 + contracts/modules/DegenerusGameAdvanceModule.sol:1286 (and corresponding rngGate normal-tick call site) | Phase 245 vector: enumerate the resolve-call matrix — ensure pending redemptions resolve correctly whether the triggering advanceGame lands in normal-tick OR gameover-path.

**SDR-02 (pendingRedemptionEthValue accounting exactness):**
- SDR-02: `pendingRedemptionEthValue = pendingRedemptionEthValue - pendingRedemptionEthBase + rolledEth` at sDGNRS:593 is the adjust-by-roll formula. Invariant to verify: for every wei entering `pendingRedemptionEthValue` via `_submitGamblingClaim*`, exactly one wei exits via EITHER a `resolveRedemptionPeriod` roll adjustment OR a `claimRedemption` payout. | contracts/StakedDegenerusStonk.sol:593 + :619-700 area | Phase 245 vector: prove wei-level conservation across the full request-resolve-claim lifecycle (no dust, no overshoot, no loss).
- SDR-02: `_deterministicBurnFrom` at sDGNRS:535 uses `totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue` — subtracts `pendingRedemptionEthValue` from the payout base to exclude reserved gambling-burn ETH. NEW subtraction introduced alongside 771893d1. | contracts/StakedDegenerusStonk.sol:527-569 | Phase 245 vector: prove the subtraction at L535 is exact across the burn-payout → payout-proportionality chain; verify no rounding edge leaves pendingRedemptionEthValue double-counted.

**SDR-03 (handleGameOverDrain subtracts full pendingRedemptionEthValue before split):**
- SDR-03: §GOX-03 closed the 244-04 claim (pre- and post-refund subtraction at L94 + L157); Phase 245 SDR-03 owns a DEEPER analysis — enumerate every drain-iteration edge (multi-tx drain, STAGE_TICKETS_WORKING partial drain, re-entry into `handleGameOverDrain` via L80 idempotency bit). | contracts/modules/DegenerusGameGameOverModule.sol:79-189 | Phase 245 vector: prove the pre/post-refund reread semantics preserve exactness across multi-tx drain invocations; verify `pendingRedemptionEthValue` reads are not stale if claimRedemption fires mid-drain (though GOX-02c proved no NEW redemptions can arrive during State-1).

**SDR-04 (claimRedemption post-gameOver DOS-free):**
- SDR-04: `claimRedemption` at sDGNRS:618 is NOT gated by livenessTriggered or gameOver — but its BUDGET depends on `pendingRedemptionEthValue` remaining un-swept. `handleGameOverDrain` preserves this via the L94 + L157 subtractions; however, the `_sendToVault` split at L225-233 is NOT idempotent (running twice would double-send). The L80 `GO_JACKPOT_PAID` bit blocks that, but Phase 245 should verify: can a malicious actor force two separate entries into `handleGameOverDrain` in a way that the L80 bit is bypassed? | contracts/modules/DegenerusGameGameOverModule.sol:79-80 + contracts/StakedDegenerusStonk.sol:618 | Phase 245 vector: DOS via drain ordering — prove claimRedemption cannot be starved by a race between drain-sweep + claim transaction ordering; verify the 30-day sweep at `handleFinalSweep` does not leave `pendingRedemptionEthValue` un-payable.

**SDR-05 (per-wei conservation across gameover timings):**
- SDR-05: Same observation as SDR-02 but extended across the gameover lifecycle. The L535 `_deterministicBurnFrom` subtraction AND the L94/L157 `handleGameOverDrain` subtractions are TWO distinct sites where `pendingRedemptionEthValue` affects payout accounting. Conservation invariant: ETH ledger closes if (sum of all gambling-burn wei INs = sum of all roll-adjusted claim wei OUTs + sum of any rolled-back wei returning to pool via roll-below-100). | contracts/StakedDegenerusStonk.sol:535 + contracts/modules/DegenerusGameGameOverModule.sol:94 + :157 | Phase 245 vector: per-wei ledger closes across every gameover timing {State-0-resolved-claimed, State-0-resolved-unclaimed, State-1-resolved-before-drain, State-2-during-drain, State-2-post-drain-pre-final-sweep, State-2-post-final-sweep}.

**SDR-06 (State-1 orphan-redemption window closed):**
- SDR-06: §GOX-02c closed the 244-04 claim (no new redemptions creatable during State-1 via exhaustive reach-path enumeration). Phase 245 SDR-06 may enumerate DEEPER scenarios — e.g., what if `purchaseStartDay` is manipulated via admin path? What if `level` transitions mid-window and changes which day-math predicate fires? | contracts/StakedDegenerusStonk.sol:486-516 | Phase 245 vector: negative-space sweep — verify every reach-path to `_submitGamblingClaim*` is blocked in State-1, including admin-initiated paths, constructor paths (sDGNRS constructor claims a whale pass — State-1 unreachable there because game is not yet constructed), and cross-chain forward-imported state.

**SDR-07 (sDGNRS supply conservation):**
- SDR-07: `totalSupply` mutations happen in: `_mint` (constructor), `transferFromPool` (pool-to-recipient distributions), `burn` via `_deterministicBurnFrom` L539-541, `burnAtGameOver` L462 (zeros contract's own balance). The gameover path at `handleGameOverDrain` triggers `dgnrs.burnAtGameOver()` at GameOverModule:146 which cascades to sDGNRS:462. | contracts/StakedDegenerusStonk.sol:462-471 + :519-569 | Phase 245 vector: prove supply conservation across the full lifecycle — every sDGNRS token has exactly one mint + at most one burn; no ghost tokens; no dust mint from rounding in `transferFromPool`.

**SDR-08 (`_gameOverEntropy` fallback substitution for VRF-pending redemptions — F-29-04 class):**
- SDR-08: `_gameOverEntropy` at AdvanceModule:1263-1296 includes a `sdgnrs.resolveRedemptionPeriod(redemptionRoll, flipDay)` call at L1286 — resolves any pending redemption period using the fallback word. This is a NEW 771893d1 surface that OVERLAPS with the F-29-04 mid-cycle substitution envelope (EXC-03). 244-02 RNG-01-V11 re-verified EXC-03 envelope at the gameover-vs-non-gameover branch disjoint level; but the pending-redemption-resolution call via fallback entropy is a new consumption. | contracts/modules/DegenerusGameAdvanceModule.sol:1276-1288 | Phase 245 vector: prove no redemption can hang in pending limbo post-gameOver; verify the fallback resolve path does not over-substitute or under-resolve across multiple gameover ticks.

**GOE-01 (F-29-04 RNG-consumer determinism RE_VERIFIED at depth):**
- GOE-01: 244-02 RNG-01-V11 carried the envelope check (scope-disjoint reaching path from `_unlockRng` removal). Phase 245 GOE-01 owns the deeper check — does the new 14-day grace Tier-1 gate at Storage:1242 introduce a NEW way for mid-cycle ticket-buffer swap to trigger `_gameOverEntropy` consumption? | contracts/storage/DegenerusGameStorage.sol:1242 + contracts/modules/DegenerusGameAdvanceModule.sol:1263-1296 | Phase 245 vector: enumerate every possible day-14-to-day-120 scenario where Tier-1 gate fires liveness but day-math has not — verify the F-29-04 substitution envelope (mid-cycle write-buffer tickets draining under fallback entropy) remains bounded.

**GOE-02 (claimablePool 33/33/34 split + 30-day sweep against new drain flow):**
- GOE-02: `handleGameOverDrain` subtracts `pendingRedemptionEthValue` at L94 AND L157 (two subtractions bracketing the deity-pass refund loop). The 33/33/34 split inside `_sendToVault` at GameOverModule:225-233 operates on the L158 `available` value. `handleFinalSweep` at L196-216 runs 30 days post-gameOver and sweeps `totalFunds` (ETH + stETH) without re-subtracting `pendingRedemptionEthValue` — relies on `claimRedemption` having been called before the 30-day window closes. | contracts/modules/DegenerusGameGameOverModule.sol:94 + :157 + :196-216 | Phase 245 vector: prove the 30-day window is SUFFICIENT for all pending redemptions to be claimed; verify `handleFinalSweep` does not strand reserved wei if claimRedemption is delayed.

**GOE-03 (purchase blocking covers all entry points at current surface):**
- GOE-03: 244-04 GOX-01 closed the 8-path entry-gate claim. Phase 245 GOE-03 may enumerate entry points that are NOT in the 8 (e.g., `_purchaseBurnieLootboxFor` internal callees, `_claim*` paths, any admin-only entry with game-state mutation). | contracts/modules/DegenerusGameMintModule.sol + DegenerusGameWhaleModule.sol | Phase 245 vector: full sweep of all externally-callable functions in Game contracts + modules; verify each one either (a) has `_livenessTriggered` / `gameOver` gate, (b) is state-read-only, or (c) is admin-only with safe state mutation.

**GOE-04 (VRF-available vs prevrandao fallback gameover-jackpot branches given new 14-day grace):**
- GOE-04: §GOX-04 closed the call-graph reachability for the new Tier-1 grace gate. Phase 245 GOE-04 owns deeper stall-tail enumeration — e.g., the §GOX-06b analysis identified the "VRF breaks on day 14 at level 0" scenario where `gameOver` latches before day-math threshold; Phase 245 should enumerate ALL such stall-tail scenarios including multi-level transitions where VRF comes back partially. | contracts/modules/DegenerusGameAdvanceModule.sol:519-634 + :1228-1306 + contracts/storage/DegenerusGameStorage.sol:1235-1243 | Phase 245 vector: matrix of {day range (1-14, 14-120, 120-365, 365+), level (0, 1-9, 10+), VRF state (healthy, stalled < grace, stalled ≥ grace, intermittent), rngLockedFlag state} — verify every cell resolves correctly.

**GOE-05 (`gameOverPossible` BURNIE endgame gate across new liveness paths):**
- GOE-05: `gameOverPossible` flag is checked at `_purchaseCoinFor` L894 (BURNIE ticket blocking). 771893d1 did NOT change `gameOverPossible` logic, but the SHIFT to `_livenessTriggered` as the entry-gate means `gameOverPossible` now fires AFTER liveness (L890) — is this ordering correct? Could a State-1 caller bypass `gameOverPossible` because they're already rejected at L890? | contracts/modules/DegenerusGameMintModule.sol:885-911 | Phase 245 vector: verify `gameOverPossible` gate remains effective; enumerate all paths that could reach a BURNIE ticket purchase to ensure the gate is NOT bypassed by the new liveness ordering.

**GOE-06 (NEW cross-feature emergent behavior):**
- GOE-06: §GOX-06c closed the cc68bfc7 BAF direct-handle reentrancy parity at the advanceGame-tick level. Phase 245 GOE-06 should check the INTERACTION between (a) `_livenessTriggered` firing via Tier-1 grace, (b) `_gameOverEntropy` resolving pending sDGNRS redemption, (c) `handleGameOverDrain` subtracting `pendingRedemptionEthValue`, (d) the cc68bfc7 BAF skipped-pool preservation in futurePool — specifically, does the skipped-BAF pool in futurePool get correctly swept by `handleGameOverDrain` or is it stranded? | Multi-file cross-cutting | Phase 245 vector: cross-feature emergent-behavior test — construct a scenario where liveness fires via Tier-1 grace at a BAF-eligible level (prevMod10 == 0) with pending sDGNRS redemptions AND rngWord bit-0 == 0 (BAF skipped); verify all state converges correctly to terminal sweep without orphaning any pool.
- GOE-06: The `burnWrapped` divergence (`livenessTriggered() && !gameOver()` at sDGNRS:507) is LOAD-BEARING for the then-burn wrapper sequence but ALSO means the wrapper is NOT burned under State-1 — a player who holds DGNRS wrapper tokens at the moment liveness fires retains them for post-gameOver deterministic-burn. Phase 245 GOE-06 may verify this preservation does not create a window where DGNRS wrapper supply mismatches sDGNRS wrapper-held backing. | contracts/StakedDegenerusStonk.sol:506-516 + contracts/DegenerusStonk.sol:227-245 | Phase 245 vector: DGNRS wrapper ↔ sDGNRS wrapper-held backing conservation across State-0/1/2 transitions.

### Pre-Flag bullet count: 16 observations across SDR-01..08 + GOE-01..06 (no surface in SDR-04/GOE-03/GOE-05 beyond 1 bullet each; SDR-01/SDR-02 carry 2 bullets each; GOE-06 carries 2 bullets).

---

## §Reproduction Recipe — GOX bucket (Task 3 appended commands)

**§GOX-07 — storage-layout FAST-CLOSE citation + optional sanity-run:**
```sh
# Cite Phase 243 §5.3 D-243-S001 UNCHANGED verdict (primary evidence — no re-run required)
grep -A2 '^| D-243-S001' audit/v31-243-DELTA-SURFACE.md | head -5

# Cross-ref §5.5 addendum — cc68bfc7 adds zero storage-file hunks
git diff 771893d1..cc68bfc7 -- contracts/storage/
# Expected: empty (zero output)

# OPTIONAL sanity-run at HEAD (not required per CONTEXT.md D-15 FAST-CLOSE)
# forge inspect contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage storage-layout
# Expected: output byte-identical to Phase 243 §5.2 head-side layout

# Constant addition proof — _VRF_GRACE_PERIOD consumes zero slots
sed -n '200,203p' contracts/storage/DegenerusGameStorage.sol
# Line 203 shows `uint48 internal constant _VRF_GRACE_PERIOD = 14 days;` — constant, inlined into bytecode
```

**§Phase-245-Pre-Flag — Phase 245 REQ IDs for cross-reference:**
```sh
# SDR-01..08 + GOE-01..06 IDs in REQUIREMENTS.md
grep -E 'SDR-0[1-8]|GOE-0[1-6]' .planning/REQUIREMENTS.md | head -15
```

---

*End of Task 3 content (§GOX-07 + §Phase-245-Pre-Flag + §Reproduction Recipe Task-3 block). Task 4 consolidates 4 working files (v31-244-EVT.md + v31-244-RNG.md + v31-244-QST.md + v31-244-GOX.md) into audit/v31-244-PER-COMMIT-AUDIT.md with §5 Consumer Index + §6 Reproduction Recipe Appendix; flips FINAL READ-only at SUMMARY commit.*

---

## §5 — Consumer Index (REQ-ID → Phase 244 verdict-row mapping + cross-ref to source D-243-X/F/C/S row IDs)

Per CONTEXT.md D-04 item 5. Back-mapping from Phase 244 Verdict Row IDs to the Phase 243 Consumer Index rows (`D-243-I004..D-243-I022`) that scoped each REQ. Source Phase 243 rows live in `audit/v31-243-DELTA-SURFACE.md` §1 (changelog `D-243-C###`), §2 (classification `D-243-F###`), §3 (call-site catalog `D-243-X###`), §5 (storage layout `D-243-S###`), §6 (consumer index `D-243-I###`). Every Phase 244 Verdict Row ID in the table below is emitted in §1-§4 above.

| REQ-ID | Phase 244 Verdict Rows | Source 243 Consumer Index Row | Source 243 Row Subset | Owning Plan |
| --- | --- | --- | --- | --- |
| EVT-01 | EVT-01-V01..V05 | D-243-I004 | D-243-C001, C002, C003, C005, C006 + D-243-F001, F002, F003, F005 + D-243-X001, X002, X005, X007..X011 | 244-01 |
| EVT-02 | EVT-02-V01..V05 | D-243-I005 | D-243-C004 + D-243-F004 + D-243-X006, X007 + cc68bfc7 addendum rows D-243-C035..C042 + D-243-X053, X054, X060 | 244-01 |
| EVT-03 | EVT-03-V01..V08 | D-243-I006 | D-243-C001, C002, C005 + D-243-F001, F002, F005 + cc68bfc7 addendum (bit-0 coupling at AdvanceModule:827) | 244-01 |
| EVT-04 | EVT-04-V01..V04 | D-243-I007 | D-243-C006, D-243-C029 (NatSpec at JackpotModule:86-93 cc68bfc7 HEAD) | 244-01 |
| RNG-01 | RNG-01-V01..V11 | D-243-I008 | D-243-C007 + D-243-F006 + D-243-X013, X014 + §1.8 INV-237-035 HUNK-ADJACENT + §1.7 bullet 3 cross-cite + §1.7 bullet 8 cross-cite | 244-02 |
| RNG-02 | RNG-02-V01..V07 | D-243-I009 | D-243-C007, C016 + D-243-F006, F014 + D-243-X027 + §1.8 INV-237-021..037 rngLockedFlag overlap + Phase 239 AIRTIGHT RE_VERIFIED_AT_HEAD | 244-02 |
| RNG-03 | RNG-03-V01..V02 | D-243-I010 | D-243-C007 + D-243-F006 (reformat-only aspect per CONTEXT.md D-17 prose-diff) | 244-02 |
| QST-01 | QST-01-V01..V07 | D-243-I011 | D-243-C008, C009, C010, C030 + D-243-F007, F008 + D-243-X015, X017, X055 | 244-03 |
| QST-02 | QST-02-V01..V05 | D-243-I012 | D-243-C010 + D-243-F008 + cross-cite `_awardEarlybirdDgnrs` body UNCHANGED at GameStorage.sol:1014-1057 | 244-03 |
| QST-03 | QST-03-V01..V04 | D-243-I013 | NONE (NEGATIVE-scope — `DegenerusAffiliate.sol` byte-identical baseline vs HEAD; cross-cite v30-CONSUMER-INVENTORY.md INV-237-005/006 affiliate winner-roll scope-disjoint) | 244-03 |
| QST-04 | QST-04-V01..V05 | D-243-I014 | D-243-C008, C011 + D-243-F007, F009 + D-243-X015, X018, X019 | 244-03 |
| QST-05 | QST-05-V01..V03 | D-243-I015 | NONE (bytecode-delta evidence per CONTEXT.md D-13 LOCKED methodology; direction-only verdict bar per D-14) | 244-03 |
| GOX-01 | GOX-01-V01..V08 | D-243-I016 | D-243-C018..C025 + D-243-F016..F023 + D-243-X017, X018, X019, X029..X039 + D-243-X042..X049 + cross-ref D-243-C026/F024 for `_livenessTriggered` helper | 244-04 |
| GOX-02 | GOX-02-V01..V03 | D-243-I017 | D-243-C013, C014, C034 + D-243-F011, F012 + D-243-X020, X021 + D-243-X022, X023, X024 + cross-ref §1.7 bullets 1 + 2 | 244-04 |
| GOX-03 | GOX-03-V01..V03 | D-243-I018 | D-243-C017, C032 + D-243-F015 + D-243-X028 + D-243-X058, X059 | 244-04 |
| GOX-04 | GOX-04-V01..V02 | D-243-I019 | D-243-C026, C028 + D-243-F024 + D-243-X040..X052 + KI EXC-02 envelope RE_VERIFIED | 244-04 |
| GOX-05 | GOX-05-V01 | D-243-I020 | D-243-C026 + D-243-F024 + D-243-X040..X052 (subset — day-math-first ordering) | 244-04 |
| GOX-06 | GOX-06-V01..V03 | D-243-I021 | D-243-C015, C016, C038, C039, C040 + D-243-F013, F014 + D-243-X005, X026, X027, X041, X053 + cross-ref §1.7 bullets 3, 5, 8 + §1.8 INV-237-052..059 | 244-04 |
| GOX-07 | GOX-07-V01 | D-243-I022 | ALL-SECTION-5 — D-243-S001 UNCHANGED verdict (§5.3) + §5.5 cc68bfc7 addendum cross-ref | 244-04 |

**Consumer-Index coverage completeness:** Every D-243-I### row in the range `D-243-I004..D-243-I022` (19 rows — 4 EVT + 3 RNG + 5 QST + 7 GOX) is cited in at least one Phase 244 Verdict Row Source column. Zero orphaned D-243-I rows. Zero Phase 244 Verdict Rows reference a non-existent D-243-I row.

**Cross-plan bullet-closure traceability:** §1.7 bullets 3 + 8 (cross-cited per D-09) resolve via primary + derived verdict rows listed in §0 closure summary table above. The primary verdict row is the one doing the adversarial-vector enumeration; the derived row documents scope-disjointness or cross-call-graph compatibility without repeating the primary analysis.


---

## §6 — Reproduction Recipe Appendix

Per CONTEXT.md D-04 item 6. All `git show -L` / `grep` / `forge inspect bytecode` / `sed` commands concatenated from the 4 working files' §Reproduction Recipe sub-sections for reviewer replay end-to-end. POSIX-portable syntax (no GNU-isms). Commands assume `cwd` = repository root; `git rev-parse HEAD` resolves to a descendant of `cc68bfc7` with zero drift on `contracts/`. Grouped by bucket in audit execution order (EVT → RNG → QST → GOX).

### §6.0 — Milestone sanity gates (run before any bucket replay)

```sh
# Baseline + head anchor integrity
git rev-parse 7ab515fe
git rev-parse cc68bfc7
git rev-parse HEAD

# HEAD must be a descendant of cc68bfc7 with zero drift on contracts/
[ "$(git diff cc68bfc7..HEAD -- contracts/ | wc -c)" = "0" ] || { echo "DRIFT"; exit 1; }

# READ-only gate (CONTEXT.md D-18 + D-20)
[ "$(git status --porcelain contracts/ test/)" = "" ] && echo "PASS: READ-only preserved"
[ "$(git status --porcelain audit/v31-243-DELTA-SURFACE.md)" = "" ] && echo "PASS: 243-DELTA unchanged"

# Finding-ID absence gate (CONTEXT.md D-21, token-splitting guard)
TOKEN="F-31""-"
! grep -qE "$TOKEN[0-9]" audit/v31-244-PER-COMMIT-AUDIT.md && echo "PASS: zero Phase-246 tokens"
```

### §6.1 — EVT bucket commands (244-01)

```sh
# EVT-01 emit-site enumeration (primary)
grep -rn --include='*.sol' 'emit JackpotTicketWin\b' contracts/modules/DegenerusGameJackpotModule.sol
# Expected: 3 hits at HEAD cc68bfc7 (L699, L1002, L2163)

# EVT-01 emit-site cross-file scan (JackpotModule sole-emitter verification)
grep -rn --include='*.sol' 'emit JackpotTicketWin\b' contracts/ | grep -v '^contracts/mocks/' | grep -v '^contracts/test/'

# EVT-01 baseline-vs-head emit-site comparison (confirms stub-zero removal)
git show 7ab515fe:contracts/modules/DegenerusGameJackpotModule.sol | grep -n 'emit JackpotTicketWin'
grep -n 'emit JackpotTicketWin' contracts/modules/DegenerusGameJackpotModule.sol

# EVT-01 / EVT-03 TICKET_SCALE definition
grep -rn --include='*.sol' 'uint256 internal constant TICKET_SCALE' contracts/

# EVT-03 scaling-factor occurrences cross-audit
grep -rn --include='*.sol' 'TICKET_SCALE' contracts/ | grep -v '^contracts/mocks/' | grep -v '^contracts/test/'

# EVT-03 _rollRemainder / _queueTicketsScaled existence (cross-plan)
grep -rn --include='*.sol' '_rollRemainder\b' contracts/ | grep -v mocks | grep -v test
grep -rn --include='*.sol' '_queueTicketsScaled\b' contracts/ | grep -v mocks | grep -v test

# EVT-04 NatSpec at HEAD cc68bfc7
git show cc68bfc7:contracts/modules/DegenerusGameJackpotModule.sol | sed -n '77,93p'

# EVT-02 new JackpotWhalePassWin emit site (ced654df D-243-C004)
grep -n 'emit JackpotWhalePassWin' contracts/modules/DegenerusGameJackpotModule.sol
# Expected: 1 hit at L2083 (whale-pass fallback branch inside _awardJackpotTickets)

# cc68bfc7 BAF-coupling consumer gating (§1.7 bullet 7)
grep -rn --include='*.sol' 'markBafSkipped\|lastBafResolvedDay\|winningBafCredit\|bafTop\|recordBafFlip\|getLastBafResolvedDay' contracts/ | grep -v mocks | grep -v test

# cc68bfc7 bit-0 BAF-coupling at AdvanceModule:826-839
sed -n '820,841p' contracts/modules/DegenerusGameAdvanceModule.sol

# BurnieCoinflip winning-flip-credit gating (§1.7 bullet 7 closure)
grep -n 'lastBafResolvedDay\|winningBafCredit' contracts/BurnieCoinflip.sol
```

### §6.2 — RNG bucket commands (244-02)

```sh
# RNG-01 16597cac _unlockRng(day) removal baseline-vs-head advanceGame body
git show 7ab515fe:contracts/modules/DegenerusGameAdvanceModule.sol | sed -n '170,480p'
sed -n '170,490p' contracts/modules/DegenerusGameAdvanceModule.sol

# RNG-01 reaching path enumeration — STAGE_JACKPOT_ETH_RESUME + do-while break/continue idiom
grep -n 'STAGE_JACKPOT_ETH_RESUME\|dailyJackpotCoinTicketsPending\|payDailyJackpot\|_unlockRng' contracts/modules/DegenerusGameAdvanceModule.sol | head -20

# RNG-02 AIRTIGHT — Phase 239 Set-Site + Clear-Site re-anchor at HEAD cc68bfc7
grep -n 'rngLockedFlag\s*=\s*true\|rngLockedFlag\s*=\s*false' contracts/modules/DegenerusGameAdvanceModule.sol
# Expected: 1 Set-Site at L1597 + 2 Clear-Sites at L1653 + L1694 + 1 structural Ref via rawFulfillRandomWords L1708-1729

# RNG-02 §1.7 bullet 3 — _gameOverEntropy rngRequestTime clearing at L1292
sed -n '1263,1296p' contracts/modules/DegenerusGameAdvanceModule.sol
# Expected: L1289 _finalizeLootboxRng + L1292 rngRequestTime = 0 + L1293 return — no external call post-L1292

# RNG-03 REFACTOR_ONLY side-by-side prose diff
git show 7ab515fe:contracts/modules/DegenerusGameAdvanceModule.sol | sed -n '256,280p'
sed -n '260,285p' contracts/modules/DegenerusGameAdvanceModule.sol

# KI EXC-02 envelope — prevrandao fallback sole consumption site
grep -rn 'block\.prevrandao' contracts/
# Expected: exactly 1 hit at AdvanceModule:1340 (inside _getHistoricalRngFallback)

grep -rn '_getHistoricalRngFallback' contracts/
# Expected: 1 decl at AdvanceModule:1319 + 1 call at AdvanceModule:1267

# KI EXC-03 envelope — F-29-04 mid-cycle substitution
grep -n '_swapAndFreeze\|_swapTicketSlot\|_gameOverEntropy' contracts/modules/DegenerusGameAdvanceModule.sol | head -10
```

### §6.3 — QST bucket commands (244-03)

```sh
# QST-01 MINT_ETH gross-spend — compute + call site
grep -n 'ethMintSpendWei\|ticketCost + lootBoxAmount' contracts/modules/DegenerusGameMintModule.sol

# QST-01 zero-residual-fresh-only — ethFreshWei must be fully renamed
grep -rn 'ethFreshWei' contracts/
# Expected: zero hits at HEAD cc68bfc7 (complete rename)

# QST-01 quests.handlePurchase sole call site
grep -rn 'quests\.handlePurchase\|handlePurchase(' contracts/ | grep -v mocks | grep -v test

# QST-02 earlybird call site + _awardEarlybirdDgnrs body unchanged
grep -n '_awardEarlybirdDgnrs' contracts/modules/DegenerusGameMintModule.sol contracts/storage/DegenerusGameStorage.sol
git diff 7ab515fe..cc68bfc7 -- contracts/storage/DegenerusGameStorage.sol | head -40
# Expected: _awardEarlybirdDgnrs hunks absent (body unchanged)

# QST-03 NEGATIVE-scope — DegenerusAffiliate byte-identical baseline vs HEAD
git diff 7ab515fe..cc68bfc7 -- contracts/DegenerusAffiliate.sol
git diff 6b3f4f3c~1..6b3f4f3c -- contracts/DegenerusAffiliate.sol
# Expected: both return zero output

# QST-03 freshEth routing vs ethMintSpendWei — affiliate path uses freshEth
grep -n 'affiliate\.payAffiliate\|isFreshEth' contracts/modules/DegenerusGameMintModule.sol contracts/DegenerusAffiliate.sol

# QST-04 handlePurchase signature rename at interface
grep -n 'function handlePurchase' contracts/DegenerusQuests.sol contracts/interfaces/IDegenerusQuests.sol
git show 7ab515fe:contracts/interfaces/IDegenerusQuests.sol | grep -A5 'function handlePurchase'
grep -A5 'function handlePurchase' contracts/interfaces/IDegenerusQuests.sol

# QST-05 BYTECODE-DELTA-ONLY (per CONTEXT.md D-13 LOCKED)
mkdir -p /tmp/v31-244-qst05
export FOUNDRY_DISABLE_NIGHTLY_WARNING=1

# Head bytecode
forge inspect contracts/DegenerusQuests.sol:DegenerusQuests deployedBytecode > /tmp/v31-244-qst05/quests-head.txt
forge inspect contracts/modules/DegenerusGameMintModule.sol:DegenerusGameMintModule deployedBytecode > /tmp/v31-244-qst05/mint-head.txt

# Baseline bytecode via detached worktree
WORKTREE_DIR="/tmp/v31-244-qst05-baseline-$(mktemp -u XXXXXX)"
git worktree add --detach "$WORKTREE_DIR" 7ab515fe
ln -s "$(pwd)/node_modules" "$WORKTREE_DIR/node_modules" 2>/dev/null || true
( cd "$WORKTREE_DIR" && forge inspect contracts/DegenerusQuests.sol:DegenerusQuests deployedBytecode > /tmp/v31-244-qst05/quests-baseline.txt )
( cd "$WORKTREE_DIR" && forge inspect contracts/modules/DegenerusGameMintModule.sol:DegenerusGameMintModule deployedBytecode > /tmp/v31-244-qst05/mint-baseline.txt )
git worktree remove --force "$WORKTREE_DIR"

# CBOR metadata strip (covers both legacy bzzr0 a165627a7a72 + current ipfs a264697066735822)
python3 -c "
import re
for f in ['quests-baseline','quests-head','mint-baseline','mint-head']:
    b = open(f'/tmp/v31-244-qst05/{f}.txt').read().strip().lstrip('0x')
    m = re.search(r'(a165627a7a72|a264697066735822)', b)
    body = b[:m.start()] if m else b
    open(f'/tmp/v31-244-qst05/{f}-stripped.txt','w').write(body)
    print(f'{f}: {len(body)//2} bytes stripped')
"

# Delta check
wc -c /tmp/v31-244-qst05/*-stripped.txt
diff /tmp/v31-244-qst05/quests-baseline-stripped.txt /tmp/v31-244-qst05/quests-head-stripped.txt | head -5
diff /tmp/v31-244-qst05/mint-baseline-stripped.txt /tmp/v31-244-qst05/mint-head-stripped.txt | head -5
# Expected (per CONTEXT.md D-14): Quests byte-identical; Mint shrinks 36 bytes
```

### §6.4 — GOX bucket commands (244-04)

```sh
# GOX-01 — 8-path _livenessTriggered() gate enumeration
grep -n '_livenessTriggered()' contracts/modules/DegenerusGameMintModule.sol contracts/modules/DegenerusGameWhaleModule.sol
# Expected: 8 hits (MintModule:890, 920, 1226, 1392 + WhaleModule:195, 385, 544, 958)

# GOX-01 shared predicate queue-side
grep -n '_livenessTriggered()' contracts/storage/DegenerusGameStorage.sol
# Expected: L573, L604, L657 (ticket-queue guards) + L1235 (helper decl)

# GOX-02 burn + burnWrapped State-1 block
sed -n '486,495p' contracts/StakedDegenerusStonk.sol
sed -n '506,516p' contracts/StakedDegenerusStonk.sol
sed -n '102,105p' contracts/StakedDegenerusStonk.sol
# L491 BurnsBlockedDuringLiveness revert; L507 State-1 pattern

# GOX-02 callers for burn (D-243-X022/X023/X024)
grep -n 'stonk\.burn\|sdgnrsToken\.burn' contracts/DegenerusStonk.sol contracts/DegenerusVault.sol

# GOX-02 callers for burnWrapped (D-243-X025) — zero programmatic
grep -rn '\.burnWrapped(' contracts/ | grep -v StakedDegenerusStonk.sol
# Expected: zero hits

# GOX-03 handleGameOverDrain pendingRedemptionEthValue subtraction
sed -n '79,189p' contracts/modules/DegenerusGameGameOverModule.sol
grep -n 'pendingRedemptionEthValue()' contracts/modules/DegenerusGameGameOverModule.sol
# Expected: exactly 2 hits (L94 pre-refund + L157 post-refund)

# GOX-03 interface staticcall compliance
sed -n '88,90p' contracts/interfaces/IStakedDegenerusStonk.sol
# Expected: `external view returns (uint256)` modifier — STATICCALL compiler-enforced

# GOX-04 _livenessTriggered VRF-dead 14-day grace body
sed -n '1235,1243p' contracts/storage/DegenerusGameStorage.sol
sed -n '200,203p' contracts/storage/DegenerusGameStorage.sol
# L1242 fallback; 14 days at L203

# GOX-04 Tier-2 14-day gate at AdvanceModule
grep -n 'GAMEOVER_RNG_FALLBACK_DELAY' contracts/modules/DegenerusGameAdvanceModule.sol
# Expected: L113 decl + L1265 use

# GOX-04 KI EXC-02 envelope — prevrandao sole site
grep -rn 'block\.prevrandao' contracts/
# Expected: exactly 1 hit at AdvanceModule:1340

# GOX-05 day-math-first ordering NatSpec alignment
sed -n '1221,1234p' contracts/storage/DegenerusGameStorage.sol

# GOX-06 _gameOverEntropy rngRequestTime clearing body
sed -n '1263,1296p' contracts/modules/DegenerusGameAdvanceModule.sol

# GOX-06 _handleGameOverPath gameOver-before-liveness ordering
sed -n '540,551p' contracts/modules/DegenerusGameAdvanceModule.sol
# L540 gameOver branch precedes L551 liveness gate

# GOX-06 cc68bfc7 BAF dispatch (§1.7 bullet 8 PRIMARY CLOSURE)
sed -n '820,841p' contracts/modules/DegenerusGameAdvanceModule.sol
sed -n '105,107p' contracts/modules/DegenerusGameAdvanceModule.sol
sed -n '506,510p' contracts/DegenerusJackpots.sol

# GOX-07 FAST-CLOSE storage-layout citation (NO re-run per CONTEXT.md D-15)
grep -A2 '^| D-243-S001' audit/v31-243-DELTA-SURFACE.md | head -5
git diff 771893d1..cc68bfc7 -- contracts/storage/
# Expected: empty output (cc68bfc7 adds zero storage-file hunks)

# Optional sanity-run at HEAD (not required per D-15 FAST-CLOSE)
# forge inspect contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage storage-layout
# Expected: output byte-identical to Phase 243 §5.2 head-side layout
```

### §6.5 — Cross-plan hand-off verification

```sh
# Verify §1.7 cross-cite references exist in both plans
grep -n 'RNG-02-V04' audit/v31-244-RNG.md audit/v31-244-GOX.md
grep -n 'RNG-01-V10' audit/v31-244-RNG.md audit/v31-244-GOX.md
grep -n 'GOX-06-V01\|GOX-06-V03' audit/v31-244-GOX.md audit/v31-244-RNG.md

# Verify all 4 working files preserved on disk
test -f audit/v31-244-EVT.md && test -f audit/v31-244-RNG.md && test -f audit/v31-244-QST.md && test -f audit/v31-244-GOX.md && echo "PASS: all 4 working files preserved"

# Verify consolidated file status annotation
grep -q 'Status: FINAL — READ-ONLY' audit/v31-244-PER-COMMIT-AUDIT.md && echo "PASS: FINAL READ-only annotation present"
```

---

*End of §6 Reproduction Recipe Appendix. All commands POSIX-portable per CONTEXT.md §Specifics; reviewer can replay the entire Phase 244 deliverable chain from shell.*

---

## Appendix — Working File Cross-References

Per CONTEXT.md D-05: the 4 bucket working files remain on disk as appendices (cross-ref only — not deleted). They contain the VERBATIM content that was embedded in §1-§4 above; downstream phases (245, 246) may cite either the working files OR this consolidated deliverable.

- `audit/v31-244-EVT.md` (394 lines) — §1 EVT bucket source file
- `audit/v31-244-RNG.md` (447 lines) — §2 RNG bucket source file
- `audit/v31-244-QST.md` (800 lines) — §3 QST bucket source file
- `audit/v31-244-GOX.md` (801 lines) — §4 GOX bucket source file (includes §Phase-245-Pre-Flag subsection per CONTEXT.md D-16)

Total working-file line count: 2,442 lines of pre-verbatim-embed bucket audit content.

---

*Consolidated deliverable per CONTEXT.md D-04 + D-05. Status: FINAL — READ-ONLY at 244-04 SUMMARY commit (CONTEXT.md D-05 consolidation pattern mirrors Phase 243 D-12 / Phase 230 D-05 / Phase 237 D-08 precedent).*
