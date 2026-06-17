---
phase: 391-rng-spine
verified: 2026-06-15T00:00:00Z
status: passed
score: 8/8
overrides_applied: 0
---

# Phase 391: RNG-SPINE Verification Report

**Phase Goal:** Every new/changed RNG consumer is freeze-safe (word unknown at commitment; in-window reads frozen; narrowing entropy adequate); BOTH finding nets on record. (RNG/freeze is the dominant threat class.)
**Verified:** 2026-06-15
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | BOTH NETS ON RECORD: NET 1 council (rng.gemini.txt + rng.codex.txt, captured in 391-01-COUNCIL-NET.md) + NET 2 independent Claude net (391-02-CLAUDE-NET.md); 391-FINDINGS.md attests both | VERIFIED | `council/rng.council.json` — models: [gemini, codex], skipped: []. Both CLIs exited 0. `391-01-COUNCIL-NET.md` explicit "NET 1 ON RECORD for RNG-FREEZE" line. `391-02-CLAUDE-NET.md` 335 lines, NET 2 run independently (council folded at §H). `391-FINDINGS.md` §1 both-nets-on-record attestation table. |
| 2 | ADJUDICATION COMPLETENESS: 391-FINDINGS.md carries an explicit verdict (CONFIRMED/REFUTED/BY-DESIGN/MONITOR) for EVERY RNG-01..06 req AND every FC-391-01..05 lead AND cross-refs FC-389-05, FC-392-11, each with a settling cite | VERIFIED | All 13 items carry a row in `391-FINDINGS.md` §2 with REFUTED verdict + file:line settling cite at `a8b702a7`. RNG-01..06 §2a; FC-391-01..05 §2b; FC-389-05 + FC-392-11 §2c. REQUIREMENTS.md RNG section shows all 6 marked `[x]` with ✅ ATTESTED 391-02 attribution. |
| 3 | PRIORITY ITEMS: (a) RNG-04 cross-round uint32 seed-collision divergence (codex INFO/LOW vs gemini SOUND) resolved with a real trace + skeptic-gate verdict; (b) RNG-02/FC-391-04 decimator uint32 distribution-bias settled with a real distribution argument (keccak random-oracle reasoning) | VERIFIED | (a) `391-FINDINGS.md` §3a: skeptic dual-gate applied at source — pinned DecimatorModule:277 + LootboxModule:883; structural-protection check + 3-condition EV lens (reachable: ~10^-5..10^-4; profitable: NO — off the ETH spine, magnitude independent; grindable: NO — words VRF-fixed after burn). REFUTED-as-break; INFO/LOW benign carried §4b. (b) `391-FINDINGS.md` §3b + `391-02-CLAUDE-NET.md` §B: full random-oracle argument — `keccak256(W || addr_i)` for distinct `addr_i` produces independent uniform 256-bit outputs (keccak avalanche destroys the 32-bit shared prefix in the tier-modulo low bits); joint tier distribution = product of N independent uniform draws; multi-account actor gets N independent uniform draws with no shared-W edge; non-grindable (W is VRF-fixed after address commitment). Real distribution reasoning, not a hand-wave. |
| 4 | BACKWARD-TRACE doctrine applied (word unknown at commitment); in-window SLOAD enumeration (RNG-06) present | VERIFIED | `391-02-CLAUDE-NET.md` §A: per-consumer table with commitment point, word source, and attack result for every consumer (manual open, resolveLootboxDirect, box-spins, survival flip, redemption lootbox, decimator claim, coinflip/carry, EntropyLib migration sites, reverseFlip, salvage quote). §F: in-window SLOAD enumeration over freeze-spine slots 10/34/35+dailyIdx; daily-resolution and lootbox-resolution windows enumerated; two load-bearing claims (EntropyLib byte-identity + activityScore frozen snapshot) attacked and confirmed. `391-FINDINGS.md` §2a RNG-06 row cites the slot enumeration. |
| 5 | AUDIT-ONLY: NO contract source modified (`git diff a8b702a7 -- contracts/` empty; phase changed only .planning/ docs) | VERIFIED | `git diff a8b702a7 -- contracts/` exit 0, 0 bytes output. `git status --porcelain contracts/` empty. `git diff a8b702a7 HEAD -- contracts/` also 0 bytes. Council ran in read-only wrappers (`ask-gemini.sh --approval-mode plan`; `ask-codex.sh --sandbox read-only`); NET 2 read all source via `git show a8b702a7:`. Both SUMMARY files confirm "0 contract source" touched. |
| 6 | Council prompt is substantive and neutrally charged against `a8b702a7`, encoding backward-trace doctrine, in-window SLOAD enumeration, distribution-bias prime target charged hard, KNOWN-BY-DESIGN list, per-finding output format | VERIFIED | `391-01-COUNCIL-PROMPT-RNG.md` 296 lines (well above min_lines:45). Contains `a8b702a7` reference; all of RNG-01..06, FC-391-01..05, FC-389-05, FC-392-11 present; backward-trace doctrine, SLOAD enumeration, uint32/distribution prime target as dedicated numbered break-target; KNOWN-BY-DESIGN exclusion list; per-finding FINDING/VERIFIED-SOUND format. No verdict pre-stated. |
| 7 | RNG-01..06 all attested in REQUIREMENTS.md with 391-02 citation | VERIFIED | REQUIREMENTS.md RNG section: all six `[x] **RNG-0N**: ... ✅ ATTESTED 391-02 (both nets; ...)` entries present and cross-referencing 391-FINDINGS section cites. |
| 8 | Council raw outputs are substantive (non-stub), with source-level analysis from both models | VERIFIED | `rng.gemini.txt` 54 lines, 9 matches for source-level identifiers (DegenerusGame*, Module refs, rngWord, betId, etc.). `rng.codex.txt` 27 lines, 11 matches for source cites incl. `:269`, `:277`, `:399`, `:883`, file paths. Council JSON `skipped:[]`. Both err files 0 bytes (clean exits). |

**Score:** 8/8 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.planning/phases/391-rng-spine/391-01-COUNCIL-PROMPT-RNG.md` | Neutral council prompt for RNG-01..06 + FC-391-01..05 + FC-389-05/FC-392-11; min 45 lines | VERIFIED | 296 lines. Contains all required IDs, backward-trace doctrine, SLOAD enumeration, distribution-bias hard-charge, KNOWN-BY-DESIGN list. |
| `.planning/phases/391-rng-spine/391-01-COUNCIL-NET.md` | Council-net capture: raw output paths, available/skipped, byte-freeze attestation, NET 1 ON RECORD; min 20 lines | VERIFIED | 161 lines. Explicit "NET 1 ON RECORD for RNG-FREEZE" header. Manifest table shows gemini+codex available, 0 skipped. Raw output paths listed. Byte-freeze attestation: `git diff a8b702a7 -- contracts/` EMPTY + `git status --porcelain contracts/` EMPTY. |
| `.planning/phases/391-rng-spine/council/rng.gemini.txt` | Non-empty gemini raw output | VERIFIED | 54 lines, substantive source-traced response: all 6 RNG thesis points VERIFIED SOUND with backward-traced commitment points, keccak diffusion argument, one-shot record-clear, day+1 gate reasoning. |
| `.planning/phases/391-rng-spine/council/rng.codex.txt` | Non-empty codex raw output | VERIFIED | 27 lines, substantive source-traced response: 1 INFO/LOW FINDING on RNG-04 (cross-round uint32 collision) + VERIFIED SOUND on all other items with source file:line cites at `a8b702a7`. |
| `.planning/phases/391-rng-spine/council/rng.council.json` | Manifest with available/skipped and output paths | VERIFIED | 7 lines. `"models":["gemini","codex"]`, `"skipped":[]`, `"outputs":{"gemini":".../rng.gemini.txt","codex":".../rng.codex.txt"}`. |
| `.planning/phases/391-rng-spine/391-02-CLAUDE-NET.md` | NET 2 adversarial analysis; min 90 lines | VERIFIED | 335 lines. Independent per-consumer backward-trace (§A table with 10 consumers), dedicated distribution argument (§B with 3-part reasoning), one-shot/survival-flip trace (§C), RNG-04 cross-round skeptic dual-gate (§D), day-boundary divergence bound (§E), in-window SLOAD enumeration (§F), inherited cross-refs (§G), council fold-in (§H), verdict summary (§I). |
| `.planning/phases/391-rng-spine/391-FINDINGS.md` | Both-nets-on-record + per-item verdict table for all 13 items + skeptic gate + routing; min 90 lines | VERIFIED | 191 lines. §1 both-nets table. §2a RNG-01..06 (6 rows), §2b FC-391-01..05 (5 rows), §2c FC-389-05+FC-392-11 (2 rows) = 13 rows total. §3 skeptic gate with dual-gate table for RNG-04 (§3a) and RNG-02/FC-391-04 (§3b) — both with structural-protection check + 3-condition EV lens. §4 routing: 0 CONFIRMED contract findings; INFO/LOW + test-hardening items documented. §5 re-attestation line for all 6 reqs. |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `391-01-COUNCIL-PROMPT-RNG.md` | `council.sh --label rng` fan-out | council.sh execution | VERIFIED | Confirmed via council/rng.council.json existence + both model outputs non-empty + err files 0 bytes. SUMMARY commit `61b55436` records the fan-out. |
| `391-01-COUNCIL-NET.md` | `council/rng.council.json` | manifest capture | VERIFIED | `grep -q "rng\.council\.json" 391-01-COUNCIL-NET.md` PASS. Council JSON path referenced in the net capture record. |
| `391-FINDINGS.md` | `391-01 council/*.txt` | both-nets-on-record fold | VERIFIED | §1 attestation table references `council/rng.{gemini,codex}.txt` and `391-01-COUNCIL-NET.md`. `391-02-CLAUDE-NET.md` §H fold-in table cross-references council. |
| `391-FINDINGS.md` | RNG-01..06 + FC-391-01..05 + FC-389-05, FC-392-11 | per-item verdict rows | VERIFIED | All 13 items found in FINDINGS.md via grep. Each row contains a REFUTED verdict + settling cite. `grep -c "REFUTED\|CONFIRMED\|BY-DESIGN\|MONITOR"` = 31 lines. |

---

### Data-Flow Trace (Level 4)

This is an audit documentation phase — no rendered dynamic data, no user-facing UI. Artifacts are structured analysis documents. Level 4 data-flow trace is not applicable for audit deliverables (the "data" is analytical reasoning, not a database-backed render path).

---

### Behavioral Spot-Checks

This phase is audit-documentation only. The only runnable check applicable is the byte-freeze attestation (whether contracts were mutated):

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Contracts byte-frozen at `a8b702a7` throughout | `git diff a8b702a7 -- contracts/` | empty (0 bytes) | PASS |
| Contracts working tree clean | `git status --porcelain contracts/` | empty (0 bytes) | PASS |
| No contracts changed vs HEAD either | `git diff a8b702a7 HEAD -- contracts/` | empty (0 bytes) | PASS |

---

### Probe Execution

No conventional `scripts/*/tests/probe-*.sh` exist for this phase. The PLAN does not declare probes. The byte-freeze git check above satisfies the T-391-01 tamper-detection requirement. SKIPPED (no probe files).

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|---------|
| RNG-01 | 391-01 + 391-02 | Every new/changed consumer backward-traced — VRF word unknown at commitment | SATISFIED | `391-02-CLAUDE-NET.md` §A: full per-consumer backward-trace table. `391-FINDINGS.md` §2a RNG-01 row: REFUTED verdict with per-consumer commitment-point cites. REQUIREMENTS.md `[x]` ✅ ATTESTED 391-02. |
| RNG-02 | 391-01 + 391-02 | Decimator uint32 claim-seed: entropy floor + non-grindable + UNBIASED per-bucket distribution | SATISFIED | `391-02-CLAUDE-NET.md` §B: 3-part distribution argument (joint distribution, multi-account, 32-bit floor adequacy). `391-FINDINGS.md` §2a RNG-02 + §3b: random-oracle distribution argument + 3-condition EV lens. Distribution oracle ROUTED as test-hardening. REQUIREMENTS.md `[x]` ✅ ATTESTED. |
| RNG-03 | 391-01 + 391-02 | Box-spin resolvers (WWXRP/BURNIE/ETH) one-shot + replay-safe | SATISFIED | `391-02-CLAUDE-NET.md` §C: record-clear-before-resolution confirmed at LootboxModule:579, DegeneretteModule:655, DecimatorModule:399; `address(this)!=GAME` guard at DegeneretteModule:1298/1353/1408. `391-FINDINGS.md` §2a RNG-03: REFUTED. REQUIREMENTS.md `[x]`. |
| RNG-04 | 391-01 + 391-02 | `resolveLootboxDirect` + spin seeds domain-separated (no cross-consumer seed collision) | SATISFIED | `391-FINDINGS.md` §2a RNG-04: per-caller domain-separation enumerated; codex INFO/LOW cross-round divergence resolved via skeptic dual-gate §3a. REFUTED as break; INFO/LOW benign carried §4b. REQUIREMENTS.md `[x]` ✅ ATTESTED. |
| RNG-05 | 391-01 + 391-02 | Redemption day+1 pre-draw gate holds on burn side; no zero-seed grind | SATISFIED | `391-02-CLAUDE-NET.md` §E: day-boundary divergence bound (3 interleavings traced). `391-FINDINGS.md` §2a RNG-05: gate pins `currentPeriod <= dailyIdx` by construction; day+1 UNDRAWN at burn time; second wall = `rngLocked` in burn()/burnWrapped(). REQUIREMENTS.md `[x]`. |
| RNG-06 | 391-01 + 391-02 | Every SLOAD inside rng-window over repacked slots is freeze-invariant | SATISFIED | `391-02-CLAUDE-NET.md` §F: enumeration over slots 10/34/35+dailyIdx; daily and lootbox resolution windows; EntropyLib byte-identity + activityScore frozen snapshot confirmed. `391-FINDINGS.md` §2a RNG-06: REFUTED. REQUIREMENTS.md `[x]`. |

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none) | - | - | - | - |

No TBD, FIXME, XXX, or TODO/PLACEHOLDER markers found in any of the 391-rng-spine deliverables. No stub patterns. The INFO/LOW cross-round correlation (RNG-04) and the distribution-oracle test-hardening note are formal audit observations, not debt markers — both are properly documented in §4b of 391-FINDINGS.md.

---

### Human Verification Required

No human verification items identified. This is an audit documentation phase verified against observable artifacts (files, line counts, grep patterns, git byte-freeze). All truths are verifiable programmatically.

---

## Gaps Summary

None. All 8 must-have truths are VERIFIED. All required artifacts exist and are substantive (well above min_lines thresholds). All key links are connected. Both council outputs are substantive (not stubs). The byte-freeze invariant holds. No contracts were modified. All 6 REQUIREMENTS.md RNG requirements are satisfied with both-nets-on-record backing.

**The phase 391 goal is achieved:** every new/changed RNG consumer is attested freeze-safe with both finding nets on record, the priority items (RNG-04 cross-round collision and RNG-02 distribution-bias prime) resolved with real source-pinned reasoning, the backward-trace doctrine applied per-consumer, the in-window SLOADs enumerated, and 0 CONFIRMED contract findings — the DOMINANT threat class is clean across the change set.

---

_Verified: 2026-06-15T00:00:00Z_
_Verifier: Claude (gsd-verifier)_
