# Requirements — Milestone v74.0 — C4A Readiness: Live Adversarial Agent + Final Finding-Squash + Scope/Known-Issues Package

**Defined:** 2026-06-21
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

> **Subject:** the v73.0 byte-frozen contract subject — `contracts/` tree `d6615306` @ IMPL `64ec993e`, closed under `MILESTONE_V73_AT_HEAD_15650b6a…` (verdict 0 CAT/0 HIGH/0 MED/0 LOW). HEAD is 1 commit ahead = the standalone `DegenerusGasFaucet.sol` (owner-deprioritized as third-party → documented out-of-scope, not audited this milestone).
> **Posture (default):** **no contract LOGIC change** → the subject stays byte-frozen and v73's audit story stays narrow. v74 runs essentially gate-free; the SOLE possible contract-commit gate is the conditional 464 SQUASH-GATE (only fires if the agent campaign surfaces something real, or the owner overrides a carried-LOW to FIX). All docs/test/agent work commits autonomously.
> **Two workstreams, one engine:** (A) a live adversarial agent whose runtime invariant oracle == (B) the C4A package's Main-Invariants section. A single machine-readable invariant manifest (MAN-01) is the shared source.
> **Owner constraints (`.planning/v74-grounding/CONSTRAINTS.md`):** testnet runs **accelerated 15-min game-days** with **honest actors playing 24/7** → live multi-actor soak is practical; the "win more than you should" oracle is **per-actor net-P&L-vs-EV**, robust to honest background flow, with solvency/backing invariants holding globally across all actors. The agent is a real EXTERNAL attacker on the live, independently-run testnet — it never deploys or drives the environment (no fork; no time/VRF/stETH/honest-actor control); the existing Foundry invariant suite stays a separate in-repo white-box net.
> **Grounding:** `.planning/v74-grounding/SYNTHESIS.md` (5-report fan-out) + `CONSTRAINTS.md`.

---

## v1 Requirements

Requirements for v74.0. Each maps to exactly one roadmap phase (457–465).

### SCOPE — contest scope & SLOC package (Phase 457)

- [ ] **SCOPE-01**: `scope.txt` regenerated from the frozen tree `d6615306` — lists every in-scope contract that actually exists (drop deleted BurnieCoin/Stonk/EndgameModule; add FoilPackModule/ActivityCurveLib), with a paired `out_of_scope.txt` (tests, mocks, interfaces, scripts, the gas faucet).
- [ ] **SCOPE-02**: An in-scope-only file + nSLOC table is produced (built from `report.md` minus mocks/tests/scripts), suitable for embedding in the contest README.
- [ ] **SCOPE-03**: `report.md` + `ADERYN-TRIAGE.md` are refreshed against HEAD (current static-analysis triage status; stale pre-gas-faucet state corrected).

### PKG — README, security model & prior-audits (Phase 458)

- [ ] **PKG-01**: A rename pass is applied across all contest-facing docs (BURNIE→FLIP, BurnieCoin→FLIP, BurnieCoinflip→Coinflip, Stonk→DGNRS/sDGNRS, DGVB→DGVF) so no doc names a renamed-away or deleted symbol.
- [ ] **PKG-02**: `SECURITY.md` exists — describes the protocol's security model, trust assumptions, and responsible-disclosure posture.
- [ ] **PKG-03**: A trusted/restricted-roles table documents every privileged role (owner/keeper/VRF/etc.), exactly what it is trusted to do, and what is assumed-honest — the security/trust model a warden must respect.
- [ ] **PKG-04**: A Prior-Audits summary lists the v62–v73 milestone audits (method + verdict + frozen-subject hash + the v73 forge 943/0/108 floor) so their FINDINGS are pre-classified as known.

### KI — known-issues perimeter & contest README assembly (Phase 459)

- [ ] **KI-01**: A known-issues entry exists for every by-design quirk a warden could surface — FoilPack EV/claim, Degenerette Variant-2 scoring, the WWXRP rig (m≥7-cap / +2-color-unlock / never-S=9), Bingo, Afking — each naming (a) the specific function/mechanism, (b) the precise conceded behavior, (c) the accepted worst-case impact (specific-and-honest, never a vague blanket disclaimer).
- [ ] **KI-02**: The two carried items are documented as **defended/out-of-scope**, NOT as accepted vulnerabilities (owner-adjudicated 2026-06-21, both downgraded from LOW): (a) the mid-day lootbox VRF write "re-roll" — stated as single-writer-guarded by `requestId == vrfRequestId` (Chainlink fulfils each id once; stale/duplicate ids are auto-rejected; no reachable double-write), so the `==0` guard would be redundant defense-in-depth → **INFO note**; (b) the VRF coordinator-rotation timing notes — fold into the trust-model table (governance malice out-of-scope; honest rotation recovers, majority-malice = the out-of-scope governance-malice branch) + a bounded-liveness line (non-resettable 120/365-day backstop guarantees recovery). Default disposition = DOCUMENT; the conditional FIX option at 464 is now expected to stay unused (464 a no-op).
- [ ] **KI-03**: `DegenerusGasFaucet.sol` is explicitly documented as out-of-scope (unwired/third-party, owner-deprioritized) with the reason stated.
- [ ] **KI-04**: A single contest README is assembled in current C4 section order (audit-details · warden notes · automated-findings-out-of-scope · publicly-known-issues · overview · scope table · out-of-scope · areas-of-concern · main-invariants · trusted-roles · prior-audits · build/test/PoC instructions).

### MAN — shared invariant manifest & test-config hygiene (Phase 460)

- [ ] **MAN-01**: A single machine-readable invariant manifest is emitted (each entry: id, identity statement, on-chain read/view, comparator/tolerance, source `file:line`) — the canonical oracle shared verbatim by the README Main-Invariants section and the agent.
- [ ] **MAN-02**: The stale `package.json` scripts referencing non-existent dirs (`test:adversarial`, `test:adversarial:sepolia-actors`, `test:sim` → `test/adversarial/`, `test/simulation/`) are fixed or removed so no advertised script fails.

### HARN — frozen-subject harness fixes (Phase 461, test-only)

- [ ] **HARN-01**: `block_timestamp` is pinned in `foundry.toml` so the `_deployProtocol` real-clock setUp flake is eliminated (de-flakes the whole suite and the agent's reuse of `DeployProtocol.sol`).
- [ ] **HARN-02**: The 6 stale `test:stat` surface/regression baseline anchors (Jackpot/TraitUtils/EntropyLib/lootbox SurfaceRegression / PerPullEmptyBucketSkip) are re-anchored to the frozen tree so the stat suite carries no known-red anchors.

### AGT — adversarial agent: live external attacker (Phase 462)

- [ ] **AGT-01**: The agent CONNECTS to the already-running, independently-operated testnet as an external actor — RPC endpoint + deployed addresses/ABIs supplied via config (from the sim-repo deployment output), holding its own funded wallet(s). It does NOT deploy the protocol or drive the environment (the clock / VRF / stETH / honest actors are run by others; the agent has nothing to do with running the game).
- [ ] **AGT-02**: The agent drives the full external action surface (purchase, advanceGame, redeemFlip, claimFoilMatch[Many], whale/lazy/deity pass, degeneretteResolve, claimBingo, claimAfkingFlip, claimDecimatorJackpot, claimWinnings, affiliate/whale claims), sequencing purchase→advance-day→VRF→multi-level correctly (mirrors `test/fuzz/handlers/`).
- [ ] **AGT-03**: The agent maintains an off-chain per-actor ledger normalizing every value leg (ETH, sDGNRS, DGNRS, claimable, afking, vault) to one numeraire, accumulating each wallet's realized net P&L vs its modeled EV bound.
- [ ] **AGT-04**: After every external-call action the agent asserts the runtime invariant oracle (MAN-01): SOLVENCY conservation, BACKING bound (incl. auto-rebuy carry + redemption legs), redemption segregation, per-(N,heroIsGold) EV ceiling, the held-fixed P(S=9)/RTP/ROI pins, the rig never-S=9 cap, and LIVENESS/no-brick (+ no-permanent-dead-state).
- [ ] **AGT-05**: A by-design allowlist + statistical gate suppresses false positives — the "win more than you should" alarm fires only when realized profit exceeds the modeled EV bound by k·σ over a counted sample (never per-spin), and allowlisted by-design behaviors (deity-boon, salvage windows, owner knobs, known WONTFIX) do not alarm.
- [ ] **AGT-06**: The agent runs as a real external attacker at live testnet pace (NO fork, NO time-control, NO snapshots) — it watches the mempool/events to spot honest actors' transactions (front-run / sandwich / shared-window-race targets) and to detect violations, and logs every action as a structured replayable record so a flagged violation is already a reproducible tx sequence.
- [ ] **AGT-07**: The existing Foundry invariant suite continues as a SEPARATE in-repo white-box net (`FOUNDRY_PROFILE=deep`, 1000×256, auto-shrunk sequences) — complementary breadth coverage, NOT part of the external live agent.

### SOAK — live testnet soak & multi-actor probes (Phase 463)

- [ ] **SOAK-01**: The same agent runs against the live 15-min-day testnet via an RPC-mode switch — observes (does not mock) real Chainlink VRF fulfilment, serializes sends through a NonceManager with replace-by-fee, and drip-refills actor wallets below a low-water mark.
- [ ] **SOAK-02**: The agent runs multi-actor / interaction probes that only exist with honest 24/7 traffic — front-run / sandwich honest txs, race shared windows (redemption / advanceGame / jackpot resolution), and attempt to block or capture honest rewards.
- [ ] **SOAK-03**: A continuous 24/7 soak is run with checkpoint/resume (persisted ledger + last block, reconciled on boot); findings are triaged into FIX vs DOCUMENT; any brick is logged + reproduced rather than silently wedging the shared chain.

### SQ — squash gate (Phase 464, conditional — SOLE contract approval gate)

- [ ] **SQ-01**: IF (and only if) the agent campaign surfaces a real defect, or the owner overrides a carried-LOW to FIX, ALL contract edits are batched into ONE diff presented for explicit owner hand-review and committed only on approval (commit-guard `CONTRACTS_COMMIT_APPROVED=1` + hook move-aside); otherwise this phase is a no-op and v74 ships gate-free with the subject byte-frozen.

### TERM — closure & C4A bundle (Phase 465)

- [ ] **TERM-01**: `audit/FINDINGS-v74.0.md` (chmod 444) records the agent-campaign results, the fix/document dispositions, and the final verdict.
- [ ] **TERM-02**: The full forge suite is re-verified green at the frozen (or, if 464 fired, updated) floor; the final C4A package bundle (README + scope/out_of_scope + KNOWN-ISSUES + SECURITY + manifest) is assembled and internally consistent.
- [ ] **TERM-03**: The v74 closure signal `MILESTONE_V74_AT_HEAD_<sha>` is stamped against the final subject.

---

## Out of Scope

| Item | Reason |
|------|--------|
| Auditing `DegenerusGasFaucet.sol` | Owner-deprioritized ("essentially third party, not a big deal"); unwired into ContractAddresses/deploy. Documented out-of-scope (KI-03), not audited. |
| Any new protocol feature | v74 is readiness + adversarial testing, not feature work. The contract subject stays byte-frozen by default. |
| Re-running the full v62–v73 manual/cross-model audit | Those milestones closed 0 CAT/0 HIGH; v74 adds the *machine/live* detection net (the agent) + the contest package, not another manual pass. |
| Mainnet deployment / launch ops | Out of audit-repo scope; the soak targets the testnet only. |
| Indexer/ABI re-vendor, website/papers repo | Separate repos / follow-ups, unchanged by v74. |
| Fixing the carried LOWs by default | Default disposition is DOCUMENT (keep subject frozen); FIX is an owner override decided at 464 (would convert 464 into a real gate). |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| SCOPE-01 | 457 | Pending |
| SCOPE-02 | 457 | Pending |
| SCOPE-03 | 457 | Pending |
| PKG-01 | 458 | Pending |
| PKG-02 | 458 | Pending |
| PKG-03 | 458 | Pending |
| PKG-04 | 458 | Pending |
| KI-01 | 459 | Pending |
| KI-02 | 459 | Pending |
| KI-03 | 459 | Pending |
| KI-04 | 459 | Pending |
| MAN-01 | 460 | Pending |
| MAN-02 | 460 | Pending |
| HARN-01 | 461 | Pending |
| HARN-02 | 461 | Pending |
| AGT-01 | 462 | Pending |
| AGT-02 | 462 | Pending |
| AGT-03 | 462 | Pending |
| AGT-04 | 462 | Pending |
| AGT-05 | 462 | Pending |
| AGT-06 | 462 | Pending |
| AGT-07 | 462 | Pending |
| SOAK-01 | 463 | Pending |
| SOAK-02 | 463 | Pending |
| SOAK-03 | 463 | Pending |
| SQ-01 | 464 | Pending (conditional) |
| TERM-01 | 465 | Pending |
| TERM-02 | 465 | Pending |
| TERM-03 | 465 | Pending |

**Coverage:**
- v1 requirements: 28 total
- Mapped to phases: 28
- Unmapped: 0 ✓

---
*Requirements defined: 2026-06-21*
*Last updated: 2026-06-21 after milestone v74.0 initialization*
