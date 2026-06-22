# Roadmap — Milestone v74.0 — C4A Readiness: Live Adversarial Agent + Final Finding-Squash + Scope/Known-Issues Package

> **Subject:** the v73.0 byte-frozen contract subject — `contracts/` tree `d6615306` @ IMPL `64ec993e`, closure `MILESTONE_V73_AT_HEAD_15650b6a…` (0 CAT/0 HIGH/0 MED/0 LOW). HEAD is 1 commit ahead = `DegenerusGasFaucet.sol` (owner-deprioritized → documented out-of-scope).
> **Posture (default):** **no contract LOGIC change** → subject stays byte-frozen. Two workstreams, one engine: a live adversarial agent whose runtime invariant oracle == the C4A package's Main-Invariants section (single shared manifest, MAN-01).
> **The ONLY possible approval gate is the conditional 464 SQUASH-GATE** — it fires only if the agent campaign surfaces a real defect, or the owner overrides a carried item to FIX. Under the current disposition (both carried items = DOCUMENT/defended) **464 is expected to be a no-op and v74 ships gate-free.** Everything else (docs, tests, the agent, findings) commits autonomously.
> **Numbering continues 456 → 457.** No research (readiness + adversarial testing of existing frozen source).
> **Owner constraints (`.planning/v74-grounding/CONSTRAINTS.md`):** accelerated 15-min game-days + honest actors 24/7 → live multi-actor soak practical; oracle = per-actor net-P&L-vs-EV robust to honest flow, solvency global across all actors. Local-fork = the fast bug-finder.
> **Carried-item dispositions (owner-adjudicated 2026-06-21, both downgraded from LOW):** (A) mid-day VRF "re-roll" = single-writer-guarded by `requestId == vrfRequestId`, no reachable double-write → INFO note; (B) VRF rotation-timer notes = governance-malice out-of-scope per trust model + bounded by the non-resettable 120/365-day backstop → trust-model entry. Neither warrants a contract change.
> **Grounding:** `.planning/v74-grounding/SYNTHESIS.md` (5-report fan-out) + `CONSTRAINTS.md`.

---

## Phase 457 — SCOPE (docs only)

**Goal:** Regenerate the contest scope from the frozen tree so it names only contracts that exist, and produce the in-scope-only SLOC table.

**Requirements:** SCOPE-01, SCOPE-02, SCOPE-03

**Success criteria:**
1. `scope.txt` lists every in-scope contract present at tree `d6615306` (deleted BurnieCoin/Stonk/EndgameModule removed; FoilPackModule/ActivityCurveLib added); `out_of_scope.txt` lists tests/mocks/interfaces/scripts + the gas faucet.
2. An in-scope-only file + nSLOC table is produced (from `report.md` minus mocks/tests/scripts) and is internally consistent with `scope.txt`.
3. `report.md` + `ADERYN-TRIAGE.md` reflect current static-analysis triage at HEAD (no stale pre-gas-faucet rows).

## Phase 458 — RENAME + SECURITY (docs only)

**Goal:** Purge stale names from all contest docs and author the security/trust-model + prior-audits material.

**Requirements:** PKG-01, PKG-02, PKG-03, PKG-04

**Success criteria:**
1. No contest-facing doc names a renamed-away or deleted symbol (BURNIE/BurnieCoin/BurnieCoinflip/Stonk/DGVB grep-clean across the package docs).
2. `SECURITY.md` exists describing the security model, trust assumptions, and disclosure posture.
3. A trusted/restricted-roles table documents every privileged role (owner/keeper/VRF-coordinator-governance/etc.), exactly what each is trusted to do, and what is assumed-honest — including the governance-malice-out-of-scope line that carries carried-item B.
4. A Prior-Audits summary lists the v62–v73 audits (method · verdict · frozen-subject hash · the v73 forge 943/0/108 floor).

## Phase 459 — KNOWN-ISSUES (docs only)

**Goal:** Build the precise known-issues perimeter and assemble the contest README in C4 section order.

**Requirements:** KI-01, KI-02, KI-03, KI-04

**Success criteria:**
1. Every by-design quirk has a known-issue entry naming (a) the specific function/mechanism, (b) the precise conceded behavior, (c) the accepted worst-case impact — covering FoilPack, Degenerette Variant-2, the WWXRP rig (m≥7-cap / +2-color-unlock / never-S=9), Bingo, Afking. No vague blanket disclaimers.
2. The two carried items are documented per their adjudicated disposition (KI-02): A as an INFO single-writer-guard note, B via the trust-model + bounded-liveness line — framed as defended/out-of-scope, not accepted vulnerabilities.
3. `DegenerusGasFaucet.sol` is explicitly listed out-of-scope with its reason.
4. A single contest README is assembled in current C4 section order (audit-details · warden notes · automated-findings-out-of-scope · publicly-known-issues · overview · scope table · out-of-scope · areas-of-concern · main-invariants · trusted-roles · prior-audits · build/test/PoC).

## Phase 460 — MANIFEST (docs + test-config only)

**Goal:** Emit the single canonical invariant manifest shared by the README and the agent, and fix advertised-but-broken scripts.

**Requirements:** MAN-01, MAN-02

**Success criteria:**
1. A machine-readable invariant manifest exists — each entry: id, identity statement, on-chain read/view, comparator/tolerance, source `file:line` — and is the verbatim source for the README Main-Invariants section.
2. The manifest covers the runtime oracle set: SOLVENCY conservation, BACKING bound (incl. auto-rebuy carry + redemption legs), redemption segregation, per-(N,heroIsGold) EV ceiling, the held-fixed P(S=9)/RTP/ROI pins, the rig never-S=9 cap, and LIVENESS/no-brick + no-permanent-dead-state.
3. The stale `package.json` scripts (`test:adversarial`, `test:adversarial:sepolia-actors`, `test:sim` → non-existent dirs) are fixed or removed; no advertised npm script fails.

## Phase 461 — HARNESS-FIX (test-only, autonomous)

**Goal:** De-flake the suite and clear the carried stale stat anchors on the frozen tree.

**Requirements:** HARN-01, HARN-02

**Success criteria:**
1. `block_timestamp` is pinned in `foundry.toml`; the `_deployProtocol` real-clock setUp flake no longer reproduces across repeated runs.
2. The 6 stale `test:stat` surface/regression anchors (Jackpot/TraitUtils/EntropyLib/lootbox) are re-anchored to tree `d6615306`; the stat suite carries no known-red anchors.
3. Full `forge` suite green at the v73 floor (943/0/108 or better) after the fixes.

## Phase 462 — AGENT-FORK (new files, autonomous)

**Goal:** Build the adversarial agent and run it hard against a local fork as the fast bug-finder.

**Requirements:** AGT-01, AGT-02, AGT-03, AGT-04, AGT-05, AGT-06, AGT-07

**Success criteria:**
1. The agent boots from `deploy:local` — loads the exported manifest + per-contract ABIs and connects funded wallets (no hand-rolled typing).
2. The agent drives the full external action surface with correct purchase→advance-day→VRF→multi-level sequencing (mirrors `test/fuzz/handlers/`).
3. An off-chain per-actor ledger normalizes every value leg (ETH/sDGNRS/DGNRS/claimable/afking/vault) to one numeraire and tracks each wallet's realized net P&L vs its modeled EV.
4. After every external-call action the agent asserts the MAN-01 oracle; a violation is captured as a structured, replayable tx sequence (snapshot id + pre/post ledger).
5. The by-design allowlist + statistical gate are in place: the "win more than you should" alarm fires only on profit beyond the EV bound by k·σ over a counted sample; allowlisted by-design behaviors do not alarm.
6. Against a local fork the agent compresses 15-min-day game-time, funds instantly, and snapshot/reverts around each hypothesized exploit; a documented multi-day campaign runs and any repros are captured.
7. The existing Foundry `deep` invariant campaign runs in parallel as a free breadth-adversary; its results are recorded alongside the daemon's.

## Phase 463 — AGENT-SOAK (new files + ops, autonomous)

**Goal:** Point the same agent at the live 15-min-day testnet for the realistic 24/7 multi-actor soak and triage what it finds.

**Requirements:** SOAK-01, SOAK-02, SOAK-03

**Success criteria:**
1. The same agent runs against the live testnet via an RPC-mode switch — observes real Chainlink VRF fulfilment, serializes sends through a NonceManager with replace-by-fee, and drip-refills wallets below a low-water mark.
2. Multi-actor / interaction probes run that only exist with honest 24/7 traffic — front-run / sandwich honest txs, race shared windows (redemption / advanceGame / jackpot), attempt to block or capture honest rewards.
3. A continuous soak runs with checkpoint/resume (persisted ledger + last block, reconciled on boot); findings are triaged FIX vs DOCUMENT; any brick is logged + reproduced rather than silently wedging the chain.

## Phase 464 — SQUASH-GATE (conditional — SOLE contract approval gate)

> **Expected NO-OP under current dispositions.** Fires only if 462/463 surface a real defect, or the owner overrides a carried item to FIX.

**Goal:** If and only if a contract change is warranted, batch ALL edits into one owner-approved diff; otherwise confirm the subject stays byte-frozen.

**Requirements:** SQ-01

**Success criteria:**
1. If no real defect surfaced and no carried-item override is taken → this phase records a no-op and confirms `git diff d6615306 -- contracts/` is empty (subject byte-frozen).
2. If a contract change IS warranted → ALL edits land in ONE batched commit only after explicit owner hand-review (commit-guard `CONTRACTS_COMMIT_APPROVED=1` + hook move-aside); the changed subject is re-verified (forge suite + RNG-freeze/invariant re-attest) before 465.

## Phase 465 — TERMINAL (docs only)

**Goal:** Produce the closure evidence and the assembled C4A package bundle.

**Requirements:** TERM-01, TERM-02, TERM-03

**Success criteria:**
1. `audit/FINDINGS-v74.0.md` (chmod 444) records the agent-campaign results, the fix/document dispositions (incl. the two carried items), and the final verdict.
2. The full `forge` suite is re-verified green at the frozen (or, if 464 fired, updated) floor; the C4A bundle (README + scope/out_of_scope + KNOWN-ISSUES + SECURITY + manifest) is assembled and internally consistent (scope ↔ SLOC ↔ manifest ↔ known-issues cross-checked).
3. The closure signal `MILESTONE_V74_AT_HEAD_<sha>` is stamped against the final subject.

---

## Coverage

| Phase | Requirements | Gate |
|-------|--------------|------|
| 457 SCOPE | SCOPE-01/02/03 | none (docs) |
| 458 RENAME+SECURITY | PKG-01/02/03/04 | none (docs) |
| 459 KNOWN-ISSUES | KI-01/02/03/04 | none (docs) |
| 460 MANIFEST | MAN-01/02 | none (docs/test-config) |
| 461 HARNESS-FIX | HARN-01/02 | none (test-only) |
| 462 AGENT-FORK | AGT-01..07 | none (new files) |
| 463 AGENT-SOAK | SOAK-01/02/03 | none (new files + ops) |
| 464 SQUASH-GATE | SQ-01 | **sole contract gate (conditional, expected no-op)** |
| 465 TERMINAL | TERM-01/02/03 | none (docs) |

**28 requirements** mapped across **9 phases**; 0 unmapped ✓. The default path is gate-free; the single possible approval gate (464) is conditional and expected unused.

---
*Roadmap created: 2026-06-21*
*Phase numbering continues from v73.0 (456) → 457.*
