# Roadmap — Milestone v72.0 — As-Built Audit: Foil Pack + Degenerette WWXRP/Rescore (+ Gas)

> **Subject:** the `ffbd7796 (v70 freeze) → HEAD` diff — 18 `.sol`, +2,186/−355, already committed (`f255d56c` foil pack, `1dd07c4d` WWXRP rig + payout fork, `16225de6` Variant-2 rescore). v71.0 build done; its audit folds in here.
> **Posture:** verify → freeze → test → reaudit → terminal (no build). Continues numbering 446 → **447**. The 3 pillars (Solvency · RNG integrity · Liveness/no-brick) are the hard floor; gas-efficiency is a first-class axis; cross-model (Codex/ChatGPT + Gemini) on every load-bearing claim.
> **The ONLY approval gate is the FREEZE contract commit (448).** Everything else (verify analysis, applied-but-uncommitted `.sol` edits, tests, tooling, council, findings) runs autonomously.
> **Autonomous-run ordering note (USER "run full auto, going to bed"):** because the contract-commit gate cannot be crossed while the USER sleeps, VERIFY+GAS (447), TST (449), and REAUDIT (450) all run against the **working tree** (edits applied, uncommitted); any fix found during TST/REAUDIT is applied to the same tree. FREEZE (448) is therefore executed **last among the contract-touching phases** — it captures the fully-verified, gas-optimized, re-audited tree in one consolidated diff for USER review. TERMINAL (451) finalizes after the freeze commit. Until then the run **holds** at the FREEZE gate.

---

## Phase 447 — VERIFY + GAS
**Goal:** Prove the as-built foil + rig surface matches its locked design, and squeeze the gas — producing a single consolidated, still-uncommitted working tree ready to freeze.
**Requirements:** FOIL-01..05, RARE-01..04, MATCH-01..10, RIG-01..04, SEC-03 (verify); GAS-01, GAS-02 (deliver).
**Work:**
- Adversarial verify (isolated top-model subagents, neutral prompts) of HEAD vs `V71-FOILPACK-FINAL-SPEC.md` §U/§V, the foil-rescore design, and the WWXRP-rig design — every formula, freeze point, table, and spine-wiring branch. Cross-model (Codex/Gemini) confirms each load-bearing claim.
- Gas-efficiency pass (Scavenger → Skeptic) over all 18 changed files: dead code, redundant SLOADs, packing, hot-path (advanceGame/mint/claim) non-regression. Apply only Skeptic-approved edits to the working tree.
- `forge build` clean; EIP-170 re-measure (Game + GAME_FOILPACK_MODULE); byte-parity smoke on the unchanged surface.
**Success criteria:**
1. Each FOIL/RARE/MATCH/RIG behavior is traced to its implementing code and matches the locked design (or a delta is fixed in-tree).
2. Gas edits applied are all Skeptic-approved and behavior-inert (forge parity holds).
3. `forge build` green; every contract ≤ EIP-170; no hot-path gas regression.
4. A single consolidated `.sol` diff is staged-in-tree (uncommitted) and ready for the FREEZE gate.

## Phase 448 — FREEZE  *(the sole approval gate — autonomous:false)*
**Goal:** Capture the verified, gas-optimized, re-audited working tree as the byte-frozen v72 subject in ONE USER-approved contract commit.
**Requirements:** SEC-03, GAS-02 (into the committed subject).
**Work:** Present the consolidated `contracts/*.sol` diff (verify fixes + gas edits + any REAUDIT fixes) for USER hand-review → on approval, ONE atomic commit → record the v72 subject SHA + `contracts/` tree hash.
**Success criteria:**
1. USER has hand-reviewed and approved the full `.sol` diff.
2. One atomic contract commit; `contracts/` tree hash recorded as the v72 subject.
3. No mainnet `.sol` committed without that approval.

## Phase 449 — TST
**Goal:** Prove the new mechanics and re-green the suite on the v72 subject.
**Requirements:** TST-INFRA-01, TST-EV-01, MATCH-10, RIG-03; SEC-04 (suite + goldens).
**Work:**
- Fix the `npm test` `GAME_FOILPACK_MODULE`/`ContractAddresses` gap so the JS suite runs.
- Stat oracles: MATCH-10/RIG-03 EV (≈2.63 faces/pack/30d, ticket-EV ≈2.16); RIG-01/02 invariants (`P(S9)` invariance, variant-B flip-one bound, own-table `EV=100`, RTP {70,115,118,120}%); rarity-freeze-at-buy; per-tier match payouts.
- Recapture storage-layout goldens (no-slot-move expectation over the new appended slots); re-attest the RNG-freeze proof on the v72 subject.
**Success criteria:**
1. Full forge suite green; full `npm test` runs (harness gap fixed).
2. EV/RIG stat oracles reproduce the locked numbers within tolerance.
3. Layout goldens match (slots appended, none moved); RNG-freeze proof re-passes.

## Phase 450 — REAUDIT
**Goal:** Cross-model adversarial sweep of the new surface with the 3 pillars as the explicit target; nothing a C4A warden could submit survives undocumented.
**Requirements:** PILLAR-SOLV, PILLAR-RNG, PILLAR-LIVE, SEC-01, SEC-02, RIG-04.
**Work:**
- Council: Codex (ChatGPT) + Gemini + a Claude isolated net, each over foil economics/solvency, the hero-edge + 4-of-4 moonshot steer-resistance, the WWXRP-rig honesty + `P(S9)` invariance, RNG-window/composition/dead-state attacks, and advanceGame/spine brick + state-corruption under the foil queue.
- Dedicated 3-pillars adversarial pass; deep invariant suites (≥1000/256); no-slot-move re-confirm; full forge suite.
- Each candidate finding adversarially verified (refute-by-default) before it is recorded; load-bearing verdicts cross-model-confirmed.
**Success criteria:**
1. All three pillars have an explicit, cross-model-confirmed verdict (safe / finding+disposition).
2. 0 CAT / 0 HIGH (or every finding fixed in-tree and re-verified, then folded into the FREEZE diff).
3. Invariant suites green at depth; layout unchanged.

## Phase 451 — TERMINAL
**Goal:** Ship the evidence pack and the closure signal.
**Requirements:** SEC-04 (final attest).
**Work:** `audit/FINDINGS-v72.0.md` (chmod 444) + `audit/AUDIT-V72-REPORT.html`; closure signal `MILESTONE_V72_AT_HEAD_<sha>`; confirm the subject is byte-frozen at the FREEZE diff and the audit is clean.
**Success criteria:**
1. FINDINGS doc (444) + HTML report written; verdict + dispositions recorded.
2. Closure signal emitted at the frozen subject SHA.
3. SEC-04 attested: suite green, goldens + RNG-freeze re-pass on the closure subject.

---
**Coverage:** all 33 requirements mapped. 5 phases (447–451). Sole gate = 448 FREEZE.
*Roadmap authored 2026-06-21, by hand (milestone v72.0 init).*
