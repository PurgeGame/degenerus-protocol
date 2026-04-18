# Degenerus Protocol -- Delta Findings Report (v29.0 Post-v27 Contract Delta Audit)

**Audit Date:** 2026-04-18
**Methodology:** Seven-phase post-v27 delta audit. Phase 230 delta extraction and scope map; Phases 231-234 adversarial audits per module-group (earlybird, decimator including URGENT-inserted 232.1 RNG-index drain-ordering enforcement, jackpot/BAF/entropy, quests/boons/misc); Phase 235 conservation + RNG commitment re-proof + phase-transition RNG lock removal audit; Phase 236 regression sweep + consolidation. Executed read-only at HEAD `1646d5af`.
**Scope:** Post-v27.0-baseline contract-side delta -- the 10 contract-touching commits between commit `14cb45e1` (v27.0 phase 223 shipped 2026-04-13) and HEAD `1646d5af`, plus 2 post-Phase-230 RNG-hardening addendum commits (`314443af` keccak-seed fix; `c2e5e0a9` 17-site XOR-to-keccak entropy-mixing replacement) captured by `230-02-DELTA-ADDENDUM.md`. 12 in-scope files: `DegenerusGameJackpotModule.sol`, `DegenerusGameStorage.sol`, `DegenerusQuests.sol`, `IDegenerusQuests.sol`, `DegenerusGameMintModule.sol`, `DegenerusGame.sol`, `IDegenerusGame.sol`, `DegenerusGameDecimatorModule.sol`, `BurnieCoin.sol`, `DegenerusGameAdvanceModule.sol`, `DegenerusGameWhaleModule.sol`, `IDegenerusGameModules.sol`.
**Contracts in scope:** `DegenerusGame`, `DegenerusGameAdvanceModule`, `DegenerusGameJackpotModule`, `DegenerusGameDecimatorModule`, `DegenerusGameGameOverModule`, `DegenerusGameMintModule`, `DegenerusGameWhaleModule`, `DegenerusGameDegeneretteModule`, `DegenerusGameLootboxModule`, `DegenerusGameBoonModule`, `DegenerusGameStorage`, `DegenerusQuests`, `BurnieCoin`, and the module-interface group (`IDegenerusGame`, `IDegenerusQuests`, `IDegenerusGameModules`). v29.0 is a contracts-only audit — the sibling `database/` repository (API handlers, DB schema + migrations, indexer) was covered by v28.0 and is out of scope here.

---

## Executive Summary

| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 0 |
| LOW | 0 |
| INFO | 4 |
| **Total** | **4** |

**Overall Assessment:** Zero exploitable vulnerabilities found across the v29.0 delta. Five audit phases produced 13 plans total (231=3, 232=3, 232.1=3, 233=3, 234=1, 235=5) with 251 aggregate verdict rows all SAFE or SAFE-INFO and zero VULNERABLE / zero DEFERRED row-level verdicts. Four Finding Candidate: Y rows surfaced as INFO observations (2 from Phase 233-01 BAF event-widening indexer-compat; 1 from Phase 234-01 QST-01 companion-test-coverage; 1 retroactively surfaced during Phase 236 consolidation review from Phase 235-05 TRNX-01's Gameover-path buffer-swap analysis). All four are design decisions or off-chain-only observations, not on-chain vulnerabilities. This report is a delta supplement to the v5.0 Master Findings Report (`audit/FINDINGS.md`, 29 INFO), the v25.0 Master Delta Findings Report (`audit/FINDINGS-v25.0.md`, 13 INFO), and the v27.0 Call-Site Integrity Audit (`audit/FINDINGS-v27.0.md`, 16 INFO). The v26.0 milestone was design-only (bonus jackpot split) with no formal findings document. External auditors should read all four documents together. Regression verification of all prior v25.0 + v27.0 findings + v27.0 KNOWN-ISSUES entries is provided in the Regression Appendix (see Plan 236-02).

---

## Findings

### Phase 231: Earlybird Jackpot Audit (0 findings)

Three adversarial audits (EBD-01 `f20a2b5e` earlybird purchase-phase finalize refactor; EBD-02 `20a951df` trait-alignment rewrite; EBD-03 combined state machine). 40 PASS verdicts across 3 plans; zero FAIL; zero DEFER; zero Finding Candidate: Y rows. See `.planning/phases/231-earlybird-jackpot-audit/231-0N-AUDIT.md` for per-function verdict tables.

---

### Phase 232: Decimator Audit (0 findings)

Three adversarial audits (DCM-01 `3ad0f8d3` decimator burn-key refactor + consolidated jackpot block; DCM-02 `67031e7d` event emission; DCM-03 `858d83e4` terminal-claim passthrough). 44 verdict rows across 3 plans (36 SAFE + 8 SAFE-INFO); zero VULNERABLE / zero DEFERRED row-level verdicts; zero Finding Candidate: Y rows after Phase 236 consolidation review. (Note: DCM-01's two SAFE-INFO Finding Candidate: Y rows — `DECIMATOR_MIN_BUCKET_100` dead-code revival and "prev"-prefixed naming vestige — were reviewed during Phase 236 and classified as internal documentation/naming observations that do not rise to an INFO finding from the reader's perspective; they remain in the `232-01-AUDIT.md` record. DCM-02's Finding Candidate: Y row for v28.0 Phase 227 indexer-compat OBSERVATION is superseded here by the F-29-01 / F-29-02 event-widening INFO blocks which cover the same concern.)

---

### Phase 232.1: RNG-Index Ticket Drain Ordering Enforcement (0 findings)

URGENT-inserted phase — three plans (lazy pre-finalize gate contract fix; forge invariant + game-over path-isolation suite; sim-replay regression + `processFutureTicketBatch` reachable-caller audit). Zero Finding Candidate: Y rows. Net effect: enforces the RNG-index ticket drain-ordering invariant structurally so `_raritySymbolBatch` can never be invoked with `entropyWord == 0` under any reachable `advanceGame` stage sequence. The hardening is a gate-insertion strictly narrowing pre-existing surface; not promoted to `KNOWN-ISSUES.md` per `236-CONTEXT.md` D-09 (hardening makes an implicit invariant explicit; no new architectural design decision). See `.planning/phases/232.1-rng-index-ticket-drain-ordering-enforcement/232.1-0N-SUMMARY.md` for fix-series revision chronology.

---

### Phase 233: Jackpot/BAF + Entropy Audit (2 findings)

#### F-29-01: `JackpotEthWin` event signature widened uint8->uint16 traitId for `BAF_TRAIT_SENTINEL=420` carry

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 233 (`.planning/phases/233-jackpot-baf-entropy-audit/233-01-AUDIT.md` Findings-Candidate Block Candidate 1 + Per-Function Verdict Table row "JackpotEthWin event declaration widening") |
| **Contract** | `contracts/modules/DegenerusGameJackpotModule.sol` |
| **Function** | `event JackpotEthWin(address,uint24,uint16,uint256,uint256,uint24,uint32)` at `:69-77` (widened field at `:72`); related: `uint16 private constant BAF_TRAIT_SENTINEL = 420` at `:136`; emit sites at `:2002`, `:2034` |
| **Resolution** | OFF-CHAIN-INDEXER-REGEN |

Commit `104b5d42` (`feat(jackpot): tag BAF wins with traitId=420 sentinel`) widens the `JackpotEthWin` event's `traitId` field from `uint8` to `uint16` so it can carry the new `BAF_TRAIT_SENTINEL=420` compile-time constant. 420 is out-of-domain for real trait IDs (max `uint8 = 255`) and is injected at four emit sites inside `runBafJackpot` (`DegenerusGameJackpotModule.sol:2002` large-winner ETH half, `:2014` large-winner lootbox immediate half, `:2034` small-winner even-idx 100% ETH, `:2038` small-winner odd-idx 100% lootbox). EVM topic encoding is 32-byte left-padded regardless of the declared width, so on-chain log emission is byte-identical to what the pre-fix decl would have produced for the same argument value. The canonical event signature string changes from `JackpotEthWin(address,uint24,uint8,uint256,uint256,uint24,uint32)` to `JackpotEthWin(address,uint24,uint16,uint256,uint256,uint24,uint32)`, which changes the keccak-derived `topic0` hash. Off-chain ABI consumers (indexers, UI subgraphs, The Graph) must regenerate their ABI to decode post-fix events. Phase 233-01 domain-collision sweep (14 rows all SAFE) confirmed 420 cannot appear in `winningTraitsPacked` / `bonusTraitsPacked` (both populated from `uint8[4]` arrays via `JackpotBucketLib.packWinningTraits`) and cannot reach any `uint8` narrowing consumer of event `traitId` (all narrowing consumers at `MintModule:581/617` for rarity histograms; `JackpotBucketLib.unpackWinningTraits` output `uint8[4]` at `:278/444/893/1082/1722`). The 420 sentinel is observationally invisible to every on-chain branch — Solidity does not expose emitted event fields for on-chain re-read.

**Severity justification:** INFO because (a) on-chain behavior is unchanged (EVM indexed-topic encoding pads to 32 bytes regardless of declared width); (b) domain separation is structurally guaranteed (`uint16` wider than `uint8`; 420 > `type(uint8).max = 255`; `private` visibility keeps the symbol module-local); (c) no on-chain branch reads event fields for execution logic; (d) Degenerus is pre-launch per the `104b5d42` commit message — no live indexers affected. Downstream off-chain consumers regenerate ABIs as part of their normal deploy pipeline. Not a runtime / security / correctness risk on production contracts. See the new `KNOWN-ISSUES.md` "BAF event-widening + `BAF_TRAIT_SENTINEL=420` pattern" entry (Plan 236-01 Task 2) for the design-decision disclosure.

---

#### F-29-02: `JackpotTicketWin` event signature widened uint8->uint16 traitId for `BAF_TRAIT_SENTINEL=420` carry

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 233 (`.planning/phases/233-jackpot-baf-entropy-audit/233-01-AUDIT.md` Findings-Candidate Block Candidate 2 + Per-Function Verdict Table row "JackpotTicketWin event declaration widening") |
| **Contract** | `contracts/modules/DegenerusGameJackpotModule.sol` |
| **Function** | `event JackpotTicketWin(address,uint24,uint16,uint32,uint24,uint256)` at `:80-87` (widened field at `:83`); emit sites at `:2014`, `:2038` |
| **Resolution** | OFF-CHAIN-INDEXER-REGEN |

Same event-widening pattern as F-29-01 applied to `JackpotTicketWin`'s `traitId` field. Commit `104b5d42` widens `:83`'s `traitId` from `uint8` to `uint16` so the ticket-grant side of `runBafJackpot` can emit `BAF_TRAIT_SENTINEL=420`. Emit sites at `DegenerusGameJackpotModule.sol:2014` (large-winner lootbox immediate half, inside the `lootboxPortion <= LOOTBOX_CLAIM_THRESHOLD` branch) and `:2038` (small-winner odd-idx 100% lootbox). Canonical signature changes from `JackpotTicketWin(address,uint24,uint8,uint32,uint24,uint256)` to `JackpotTicketWin(address,uint24,uint16,uint32,uint24,uint256)`; `topic0` keccak hash changes; off-chain ABIs must regenerate. Note: `JackpotBurnieWin` at `DegenerusGameJackpotModule.sol:90-96` retains its pre-existing `uint8 traitId` field at `:93` (non-BAF emit sites continue to pass real `uint8` values); no indexer-compat drift for `JackpotBurnieWin`.

**Severity justification:** Same rationale as F-29-01 — INFO because on-chain behavior is unchanged, domain separation is structurally guaranteed, no on-chain branch reads event fields for execution logic, and Degenerus is pre-launch. This block and F-29-01 together constitute a single design pattern (the BAF sentinel approach) expressed across two event declarations. The paired `KNOWN-ISSUES.md` entry added by Plan 236-01 Task 2 consolidates the disclosure into ONE KI entry per `236-CONTEXT.md` D-05.

---

### Phase 234: Quests / Boons / Misc Audit (1 finding)

#### F-29-03: QST-01 `d5284be5` companion test-file update contains no positive coverage for the new wei-direct `mint_ETH` quest-credit path

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 234 (`.planning/phases/234-quests-boons-misc-audit/234-01-AUDIT.md` §QST-01 Per-Target Verdict Table row "Companion test-file (D-04)"; tracked internally as FC-234-A) |
| **Contract** | `test/fuzz/CoverageGap222.t.sol` |
| **Function** | `:1453-1455` (raw-selector ABI signature + argument-type update inside an `onlyCoin`-caller negative test at `:1441-1461`) |
| **Resolution** | INFO-ACCEPTED |

Commit `d5284be5` (`fix(quests): credit fresh ETH wei 1:1 to mint_ETH quest`) migrates the `mint_ETH` quest handler from a lossy `uint32`-rounded unit-scaling pipeline (pre-fix: `uint32 ethMintQty = uint32(quantity / (4 * TICKET_SCALE));` `questUnits * freshEth / costWei;` `uint32` cast; `ethMintQty * mintPrice`) to a wei-direct 1:1 credit pipeline (post-fix: `uint256 ethFreshWei = ticketFreshEth + lootboxFreshEth` flows unmodified from `DegenerusGameMintModule._purchaseFor` at `:1092` into `DegenerusQuests.handlePurchase` at `:762` and becomes the MINT_ETH delta at `:804-805` / `:819`). `git show d5284be5 -- test/` reports one touched file (`test/fuzz/CoverageGap222.t.sol`) with a 4-insertion / 2-deletion hunk at `:1453-1455` that updates a raw-selector ABI signature from `"handlePurchase(address,uint32,uint32,uint256,uint256,uint256)"` to `"handlePurchase(address,uint256,uint32,uint256,uint256,uint256)"` and the first-argument type annotation from `uint32(1)` to `uint256(1)`. The surrounding test (`assertFalse(o6, "quests.handlePurchase rejected non-coin caller")` at `:1459`) is an `onlyCoin`-caller negative test — it verifies the quest handler rejects non-coin callers, not that fresh-ETH wei is credited 1:1 to the MINT_ETH quest. The commit therefore introduces the necessary selector-alignment but no POSITIVE coverage for the new wei-direct credit semantics. Phase 234 QST-01 per-function audit (9 SAFE + 2 SAFE-INFO rows) proved the wei-direct pipeline correct against attack vectors (a) wei-credit 1:1 correctness, (b) fresh-ETH summation as sole feed point, (c) no double-credit with companion quests, (d) CEI / ordering, (e) interface lockstep. The finding here is strictly about test-suite coverage, not contract correctness.

**Severity justification:** INFO because the contract-side wei-direct pipeline is independently proven correct by Phase 234 QST-01's 11-row verdict table (9 SAFE + 2 SAFE-INFO) and by Phase 235 CONS-01 ETH conservation re-proof at HEAD `1646d5af` which covers the post-fix quest-credit path. The absence of a positive wei-direct test is a test-quality observation, not a runtime correctness defect. Consistent with prior-milestone patterns (see `feedback_test_rnglock.md` test-coverage reminders). NOT promoted to `KNOWN-ISSUES.md` per `236-CONTEXT.md` D-10 — `KNOWN-ISSUES` is reserved for intentional architecture + accepted automated-tool findings; test-tooling observations are not design decisions. Recommended follow-up: a dedicated positive-coverage test phase may close this gap if desired, but it is not gating for v29.0 shipping.

---

### Phase 235: Conservation + RNG Commitment Re-Proof + Phase Transition (1 finding)

#### F-29-04: Gameover RNG substitution for mid-cycle write-buffer tickets (RNG-consumer-determinism invariant violation at terminal state)

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 235 (`.planning/phases/235-conservation-rng-commitment-re-proof-phase-transition/235-05-AUDIT.md` TRNX-01 4-Path Walk Table Gameover row + Buffer-Swap Site Citation section + rngLocked End-State Check §Gameover Path; retroactively surfaced during Phase 236 consolidation review per `236-CONTEXT.md` D-06) |
| **Contract** | `contracts/modules/DegenerusGameAdvanceModule.sol` |
| **Function** | `_swapAndFreeze(purchaseLevel)` at `:292` (daily RNG buffer-swap site); `_swapTicketSlot(purchaseLevel_)` at `:1082` (mid-day lootbox RNG buffer-swap site); `_gameOverEntropy` at `:1222-1246` (entropy substitution); `_handleGameOverPath` at `:519-627` (terminal drain path); `_unlockRng(day)` at `:625` (terminal unlock) |
| **Resolution** | DESIGN-ACCEPTED |

Degenerus enforces an "RNG-consumer determinism" invariant: every RNG consumer's entropy should be fully committed at input time (the VRF word that an RNG consumer will read must be unknown-but-bound at the moment the consumer's input parameters are committed to storage). Phase 235 RNG-01 and RNG-02 prove this invariant holds for every new RNG consumer in the v29.0 delta under normal and skip-split paths. During Phase 236 consolidation review the user surfaced a terminal-state case where the invariant is technically violated: if a mid-cycle ticket-buffer swap has occurred (daily RNG request at `AdvanceModule:292` via `_swapAndFreeze(purchaseLevel)`, OR mid-day lootbox RNG request at `AdvanceModule:1082` via `_swapTicketSlot(purchaseLevel_)`) and the new write buffer is populated with tickets queued at the current level awaiting the expected-next VRF fulfillment, a game-over event intervening before that fulfillment causes those tickets to drain under `_gameOverEntropy` at `AdvanceModule:1222-1246` rather than the originally-anticipated VRF word. `_gameOverEntropy` derives substitute entropy from (a) committed VRF words still resident in storage, and (b) `block.prevrandao` admixture after a 3-day VRF stall at gameover (see `KNOWN-ISSUES.md` "Gameover prevrandao fallback" and F-25-08 in `audit/FINDINGS-v25.0.md`). The `_handleGameOverPath` at `AdvanceModule:519-627` then runs the best-effort drain rounds with an interposed `_swapTicketSlot(lvl + 1)` at `:595` and finalizes the terminal unlock at `AdvanceModule:625`. The substitute entropy is VRF-derived or VRF-plus-prevrandao — NEVER attacker-timed. Acceptance rationale: (a) only reachable at gameover (terminal state — no further gameplay after the `handleFinalSweep` 30-day window); (b) no player-reachable exploit — gameover is triggered by 120-day liveness stall or pool deficit, neither of which an attacker can time against a specific mid-cycle write-buffer state; (c) at gameover the protocol must drain within bounded transactions and cannot wait for a deferred fulfillment that may never arrive if the VRF coordinator is the reason for the liveness stall. Phase 235 TRNX-01's 4-Path Walk Table Gameover row is SAFE on rngLocked invariant preservation (exactly one `_unlockRng` fires at `AdvanceModule:625`; no double unlock, no missed unlock, no read-side-buffer write, no far-future queue write blocked by the `_livenessTriggered()` revert at `DegenerusGameStorage.sol:568/599/652`). This entry is a disclosure supplement, not a re-classification of the TRNX-01 Gameover-row verdict, which remains SAFE / Finding Candidate: N as recorded.

**Severity justification:** INFO / DESIGN-ACCEPTED per `236-CONTEXT.md` D-07 — matches the severity of the already-disclosed F-25-08 (Gameover prevrandao fallback) which is a same-domain acceptance. The violation is bounded to terminal state; no player-reachable exploit exists because gameover triggers are structural (120-day liveness stall or pool deficit), not player-timeable; and the substitute entropy is always VRF-derived or VRF-plus-prevrandao. The "RNG-consumer determinism" invariant is codified here as a canonical protocol property for future audits to reference by name when analyzing RNG-consuming code paths. See the new `KNOWN-ISSUES.md` "Gameover RNG substitution for mid-cycle write-buffer tickets" entry (Plan 236-01 Task 2) for the full design-decision disclosure with player-reachability and terminal-state rationale.

---

## Summary Statistics

### By Severity

| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 0 |
| LOW | 0 |
| INFO | 4 |

### By Source Phase

| Phase | Description | Findings |
|-------|-------------|----------|
| 231 | Earlybird Jackpot Audit | 0 |
| 232 | Decimator Audit | 0 |
| 232.1 | RNG-Index Ticket Drain Ordering Enforcement | 0 |
| 233 | Jackpot/BAF + Entropy Audit | 2 (F-29-01, F-29-02) |
| 234 | Quests / Boons / Misc Audit | 1 (F-29-03) |
| 235 | Conservation + RNG Commitment Re-Proof + Phase Transition | 1 (F-29-04) |

### By Contract / File

| Contract / File | Findings |
|-----------------|----------|
| `contracts/modules/DegenerusGameJackpotModule.sol` | 2 (F-29-01, F-29-02) |
| `test/fuzz/CoverageGap222.t.sol` | 1 (F-29-03) |
| `contracts/modules/DegenerusGameAdvanceModule.sol` | 1 (F-29-04 -- Gameover terminal-state buffer-swap surface at `:292`, `:1082`, `:625`) |

---

## Audit Trail

Verdicts: **SAFE** = no exploitable vulnerabilities found; **SAFE-INFO** = safe on-chain with an informational observation (off-chain or design-decision); **SCOPE MAP** = catalog-only output, not a findings pass.

| Phase | Scope | Plans | Findings | Verdict |
|-------|-------|-------|----------|---------|
| 230 | Delta Extraction & Scope Map (function-level changelog, cross-module interaction map, interface-drift catalog, consumer index) | 1 | 0 (catalog, not findings pass) | SCOPE MAP |
| 231 | Earlybird Jackpot Audit (EBD-01 purchase-phase finalize refactor; EBD-02 trait-alignment rewrite; EBD-03 combined state machine) | 3 | 40 PASS / 0 FAIL / 0 DEFER | SAFE |
| 232 | Decimator Audit (DCM-01 burn-key refactor; DCM-02 event emission; DCM-03 terminal-claim passthrough) | 3 | 36 SAFE + 8 SAFE-INFO / 0 VULN / 0 DEFER | SAFE |
| 232.1 | RNG-Index Ticket Drain Ordering Enforcement (URGENT-inserted: lazy pre-finalize gate contract fix; forge invariant suite; sim-replay + pftb reachable-caller audit) | 3 | 8/8 forge invariants PASS; zero L5 zero-hit trait IDs post-fix | SAFE (hardening) |
| 233 | Jackpot/BAF + Entropy Audit (JKP-01 traitId=420 sentinel; JKP-02 explicit entropy passthrough; JKP-03 cross-path bonus-trait consistency) | 3 | 75 SAFE + 2 SAFE-INFO / 0 VULN / 0 DEFER; 2 F-29-NN blocks contributed (F-29-01, F-29-02) | SAFE |
| 234 | Quests / Boons / Misc Audit (QST-01 `mint_ETH` wei-credit fix; QST-02 `boonPacked` mapping exposure; QST-03 BurnieCoin isolation) | 1 | 19 SAFE + 4 SAFE-INFO / 0 VULN / 0 DEFER; 1 F-29-NN block contributed (F-29-03) | SAFE |
| 235 | Conservation + RNG Commitment Re-Proof + Phase Transition (CONS-01 ETH; CONS-02 BURNIE; RNG-01 backward trace; RNG-02 commitment window; TRNX-01 phase transition) | 5 | 41 SSTORE rows + 10 path proofs + 10 mint + 6 burn + 28 backward-trace + 19 commitment-window + 4-path walk; all SAFE; 0 VULN / 0 DEFER / 0 Finding Candidate: Y at audit time; 1 F-29-NN block contributed retroactively (F-29-04) via Phase 236 consolidation review | SAFE |
| 236 | Regression Sweep + Findings Consolidation | 2 | (Regression Appendix in Plan 236-02; this document is Plan 236-01 output) | SAFE |
| **Total** | **7-phase post-v27 contract delta audit** | **19** | **4 INFO** | **SAFE** |

---

Regression verification of all 16 v27.0 INFO findings (F-27-01..16) + 3 v27.0 KNOWN-ISSUES entries + 13 v25.0 INFO findings (F-25-01..13) + v26.0 design-only milestone conclusions is provided in the Regression Appendix below (to be authored by Plan 236-02).
