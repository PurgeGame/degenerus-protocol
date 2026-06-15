# 394-FINDINGS — Phase 394 LEGACY-DEBT consolidated index (LEGACY-01..06; the v50 + v51 slices)

**Subject (byte-frozen):** `a8b702a7` (contracts tree `2934d3d8987a09c5f073549a0cb499f6c5f28620`;
`git diff a8b702a7 -- contracts/` EMPTY throughout the phase).
**Baseline (the audit oracle):** `test/REGRESSION-BASELINE-v63.md` — forge **854 / 0 / 110** (expected
forge-failure NAME-set strictly EMPTY). The ETH prize-pool conservation anchor is `PoolConservation.inv.t.sol`
(FUZZ-05); the RNG-freeze anchor is `RngWindowFreeze.inv.t.sol` (exercised, non-vacuous).
**Method:** CROSS-MODEL-LED, dual-net per slice (AUDIT-V63-PLAN §2 — a no-finding verdict for any slice
requires BOTH nets on record).
**Posture:** AUDIT-ONLY. Any CONFIRMED finding is DOCUMENTED + ROUTED to a SEPARATE gated USER-hand-review
boundary, BATCHED, never fixed/auto-committed in this phase; the subject re-freezes only after a gated fix.

This index ties the two phase-394 slice deliverables into one phase verdict, discharging the deferred v50 + v51
audit debt (folded into v63.0 by the USER on 2026-06-14):
- **v50 slice** — `394-FINDINGS-V50.md` (LEGACY-01 whale-pass O(1) deferred-claim + box-open record;
  LEGACY-02 AFSUB `validThroughLevel` evict/refresh + OPEN-E re-attest + the MINTDIV index alignment). NET 1 =
  `394-01-COUNCIL-NET.md` + `council/v50.{gemini,codex}.txt`; NET 2 = `394-03-CLAUDE-NET.md`. The deferred
  deliverable: `audit/FINDINGS-v50.0.md` (LEGACY-05).
- **v51 slice** — `394-FINDINGS-V51.md` (LEGACY-03 claimBingo color-completion / BingoModule — 3-tier +
  tier-precedence + dedup + freeze; LEGACY-04 the sDGNRS `Pool.Reward` rebalance + the jackpot final-day
  `Pool.Reward` deletion). NET 1 = `394-02-COUNCIL-NET.md` + `council/v51.codex.txt`; NET 2 =
  `394-04-CLAUDE-NET.md`. The deferred deliverable: `audit/FINDINGS-v51.0.md` (LEGACY-06).

---

## 1. Both-nets-on-record rollup (both slices)

A no-finding (REFUTED / BY-DESIGN / MONITOR) verdict for any item in either slice cites BOTH nets.

| Slice | NET 1 (council) | NET 2 (Claude) | both on record? | council notes |
|-------|-----------------|----------------|-----------------|---------------|
| v50 (394-01 / 394-03) | **both models on record** (`v50.council.json` `skipped: []`; codex usage-limit RESET this run) — DIVERGENT, cross-contradicting (the ideal adjudication input): gemini SOUND-LEGACY-01 / FINDING-MINTDIV; codex FINDING-LEGACY-01 / SOUND-MINTDIV; convergent SOUND on LEGACY-02a | `394-03-CLAUDE-NET.md` — whale-pass value-equivalence + horizon skeptic gate + freeze backward-trace + AFSUB as-coded + MINTDIV count-lockstep | ✓ both (gemini + codex + Claude) | — |
| v51 (394-02 / 394-04) | **`codex` on record** (19-line traced audit, 0 findings, all 3 break-targets VERIFIED SOUND + the LEGACY-04b "no final-day Reward path" refinement + the stale `JackpotModule:1047` comment); **`gemini` SKIPPED** (non-responsive, `skipped: ["gemini"]`) | `394-04-CLAUDE-NET.md` — claimBingo freeze backward-trace + tier/dedup/CEI + Pool.Reward 8-BPS-sum conservation + the final-day grep-enumeration (premise VACUOUS) | ✓ both (codex + Claude) | `gemini` second-source → 396 |

**Both nets are on record for BOTH slices.** For v50, both council models AND Claude are on record (no skip);
for v51, `codex` (council) + Claude are on record with the `gemini` skip documented (the single-available-model
rule). The codex second-source debt is INVERTED across the two slices — for v50 there is none (codex
available); for v51 the `gemini` second-source is owed → **396**. The pre-existing 392/393 codex second-source
carry to 396 is unaffected (the codex reset is an opportunity to pick those up while the limit holds).

---

## 2. Phase-394 verdict rollup — all 6 LEGACY reqs re-attested

| Req | Verdict | Slice deliverable (detail) | Authored FINDINGS |
|-----|---------|-----------------------------|--------------------|
| **LEGACY-01** (whale-pass O(1) deferred-claim + box-open record) | **ATTESTED** — both nets on record; 0 CONFIRMED; value-equivalence + single-shot REFUTED, claim-time horizon BY-DESIGN (D-04/D-20, skeptic-gated), box-record freeze REFUTED (RNG-independent) | `394-FINDINGS-V50.md` §2/§3/§5 | `audit/FINDINGS-v50.0.md` (LEGACY-05) |
| **LEGACY-02** (AFSUB evict/refresh + OPEN-E + MINTDIV index alignment) | **ATTESTED** — both nets on record; 0 CONFIRMED; AFSUB boundary/consent BY-DESIGN-as-coded, MINTDIV count-lockstep exact + quadrant REFUTED (distribution, not ordering, skeptic-gated) | `394-FINDINGS-V50.md` §2/§3/§5 | `audit/FINDINGS-v50.0.md` (LEGACY-05) |
| **LEGACY-03** (claimBingo color-completion / BingoModule — 3-tier + dedup + freeze) | **ATTESTED** — both nets on record; 0 CONFIRMED; freeze REFUTED (read over a frozen population, sole writer in the swapped/frozen buffer), tier-precedence + dedup + CEI + empty-pool + gameOver REFUTED (CEI-tight) | `394-FINDINGS-V51.md` §2/§3/§5 | `audit/FINDINGS-v51.0.md` (LEGACY-06) |
| **LEGACY-04** (sDGNRS Pool.Reward rebalance + jackpot final-day Pool.Reward deletion) | **ATTESTED** — both nets on record; 0 CONFIRMED; rebalance REFUTED (split conserved sum=BPS_DENOM, every draw clamps, no stale-split consumer); final-day deletion REFUTED — **premise VACUOUS** (no sDGNRS Reward final-day path; the old branch orphaned at v51 D-12; real surface = ETH pools, FUZZ-05-conserved) + 1 INFO doc-hygiene (the two stale comments) | `394-FINDINGS-V51.md` §2/§4/§5 | `audit/FINDINGS-v51.0.md` (LEGACY-06) |
| **LEGACY-05** (`audit/FINDINGS-v50.0.md` authored) | **DISCHARGED** — authored from the v50 dual-net adjudication, matching the FINDINGS-v62.0 format; both nets attested; 0 actionable | `394-03` (Task 2) | `audit/FINDINGS-v50.0.md` |
| **LEGACY-06** (`audit/FINDINGS-v51.0.md` authored) | **DISCHARGED** — authored from the v51 dual-net adjudication, matching the FINDINGS-v62.0 format; both nets attested; 0 actionable | `394-04` (Task 2, this plan) | `audit/FINDINGS-v51.0.md` |

**Phase rollup:** all 6 LEGACY reqs ATTESTED/DISCHARGED with both nets on record. **0 CONFIRMED contract
findings across BOTH slices.** The two deferred FINDINGS deliverables (LEGACY-05 + LEGACY-06) are discharged.
The only routed outputs are document-only (the v50 stale test-comment INFO; the v51 stale code-comment INFO) +
the carried second-source (gemini for v51 → 396).

---

## 3. Consolidated routed-list (both slices)

| # | Item | Slice | Weight | Routing | Second-source |
|---|------|-------|--------|---------|---------------|
| 1 | `MintBatchDeterminism.test.js` stale Path-B accumulator comment (test-only, the live caller is `processed += take`) | v50 | INFO | comment trim → future test-hardening batch; NOT a contract change | n/a (codex on record) |
| 2 | stale "DGNRS on final day" comments `JackpotModule:1047` + `:1160` (the v51 D-12 orphaning residue; the solo bucket pays ETH+whale-passes only) | v51 | INFO | comment trim → post-audit hygiene pass; NOT a contract change (subject byte-frozen during the sweep) | gemini second-source → 396 |

**No CATASTROPHE/HIGH/MED/LOW across either slice — 0 CONFIRMED contract findings.** The skeptic dual-gate was
applied to every value-bearing item (v50: the two divergent SPINE candidates — the whale-pass horizon + the
MINTDIV quadrant, both REFUTED/BY-DESIGN; v51: the DOMINANT bingo freeze read + the two SPINE conservation
surfaces — the Pool.Reward rebalance + the final-day deletion, all REFUTED). No money pump, no supply break, no
ETH insolvency, no RNG-freeze break, no attacker profit. Both INFO items are document-only and ROUTED, never
fixed in this phase; the subject stays byte-frozen.

Carried second-source to 396: the post-responsive **gemini** re-run of the v51 codex SOUND verdicts (esp. the
LEGACY-03a freeze + the LEGACY-04b "no final-day Reward path" refinement); plus the pre-existing 392/393 codex
second-source carry (unchanged by this phase).

---

## 4. Phase-394 byte-freeze attestation

`git diff a8b702a7 -- contracts/` is EMPTY before and after every task across BOTH slices
(394-01/394-02/394-03/394-04); `git status --porcelain contracts/` EMPTY; the contracts tree held at
`2934d3d8987a09c5f073549a0cb499f6c5f28620` throughout. The council ran read-only (`--approval-mode plan` /
`--sandbox read-only`); both Claude nets read all source via `git show a8b702a7:`; hardhat was never invoked
(the ContractAddresses-regeneration landmine avoided). No CONFIRMED finding was fixed in-phase (0 CONFIRMED
across both slices). The only untracked working-tree file is the pre-existing `PLAYER-PURCHASE-REWARDS.html`
(unrelated; left untouched).

**Phase-394 verdict:** the LEGACY-DEBT surface (all 6 reqs — LEGACY-01..06; the cumulative v50 + v51 contract
surface + the two deferred FINDINGS deliverables) is adjudicated with BOTH nets on record for BOTH slices, the
skeptic gate applied (0 CATASTROPHE/HIGH), and every item carrying an explicit verdict. **0 CONFIRMED contract
findings across both slices**; the two deferred deliverables (`audit/FINDINGS-v50.0.md` LEGACY-05 +
`audit/FINDINGS-v51.0.md` LEGACY-06) are DISCHARGED; 2 INFO doc-only items routed to a hygiene pass; the
gemini v51 second-source carried to 396. The byte-frozen subject `a8b702a7` is attested throughout.
