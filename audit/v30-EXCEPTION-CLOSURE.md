---
phase: 241-exception-closure
plan: 01
milestone: v30.0
head_anchor: 7ab515fe
audit_baseline: 7ab515fe
deliverable: audit/v30-EXCEPTION-CLOSURE.md
requirements: [EXC-01, EXC-02, EXC-03, EXC-04]
write_policy: READ-only on contracts/ and test/; writes confined to .planning/ and audit/
supersedes: none
generated_at: 2026-04-19
---

# v30.0 Exception Closure — Phase 241 Final Consolidated Deliverable

**Audit baseline:** HEAD `7ab515fe` (contract tree identical to v29.0 `1646d5af`; post-v29 commits are docs-only per PROJECT.md — this plan's commits modify `audit/` and `.planning/` only).
**Requirements satisfied:** EXC-01, EXC-02, EXC-03, EXC-04 (Phase 241 scope = 4/4).
**Status post-commit:** READ-only per D-27. Downstream Phase 242 cites Row IDs; it does NOT edit this file.

## 2. Executive Summary

**Closure verdicts** (per D-09 closed-verdict vocabulary; derived at HEAD `7ab515fe`):

| Requirement | Closure Verdict | Predicates / Gates |
| ----------- | --------------- | ------------------ |
| EXC-01 | `CONFIRMED_SOLE_EXCEPTION_GROUPS` | § 3 22-row ONLY-ness table + § 4 Gate B grep backstop; Gate A (set-equality with Phase 238 22-EXCEPTION / 124-SAFE distribution) `GATE_A_PASSES`; Gate B (grep over D-07 surface universe) `GATE_B_PASSES` |
| EXC-02 | `RE_VERIFIED_AT_HEAD` | § 5 two-predicate table: EXC-02-P1 (single-call-site: sole caller `_gameOverEntropy` at `AdvanceModule:1252`) + EXC-02-P2 (14-day gate: `GAMEOVER_RNG_FALLBACK_DELAY = 14 days` at `:109` + check at `:1250`); both hold |
| EXC-03 | `RE_VERIFIED_AT_HEAD` | § 6 tri-gate table: EXC-03-P1 (terminal-state only via `_gameOverEntropy:1222-1246`) + EXC-03-P2 (no-player-reachable-timing, cross-cite Phase 240 GO-04 2 `DISPROVEN_PLAYER_REACHABLE_VECTOR` rows) + EXC-03-P3 (buffer-scope only at `:292, :1082`, cross-cite Phase 240 GO-05 `BOTH_DISJOINT`); all three hold |
| EXC-04 | `RE_VERIFIED_AT_HEAD` | § 7 two-part predicate: EXC-04-P1a (EntropyLib.entropyStep XOR-shift body at `EntropyLib.sol:16-23` intact, zero keccak inside body) + EXC-04-P1b (all 8 caller-site `keccak256(abi.encode(rngWord, ...))` constructions VRF-sourced via `rawFulfillRandomWords:1690` / `_applyDailyRng:1786` / `_backfillGapDays:1738`; 8 `EntropyLib.entropyStep` call sites set-equal with Phase 237's 8 EXC-04 rows); both hold |
| **Combined ONLY-ness Claim** | **`ONLY_NESS_HOLDS_AT_HEAD`** | Gate A ∧ Gate B ∧ EXC-02 RE_VERIFIED_AT_HEAD ∧ EXC-03 RE_VERIFIED_AT_HEAD ∧ EXC-04 RE_VERIFIED_AT_HEAD — all pass at HEAD `7ab515fe` |

**Forward-Cite Discharge Count:** 29/29 (17 EXC-02 + 12 EXC-03) — every Phase 240 forward-cite token line-item discharged in § 8 Forward-Cite Discharge Ledger with verdict `DISCHARGED_RE_VERIFIED_AT_HEAD`. See § 8a (EXC-241-023..039) + § 8b (EXC-241-040..051).

**Finding Candidates Count:** 0 — no row in § 3 / § 4 / § 5 / § 6 / § 7 / § 8 carries verdict `CANDIDATE_FINDING`. No Phase 242 FIND-01 intake from Phase 241. (Per D-20: no v30.0-series finding identifiers emitted — file-wide finding-ID pattern count = 0; finding-ID promotion is Phase 242 FIND-01 territory.)

**Scope-Guard Deferrals:** 0 — no delta from Phase 237's 146-row inventory or 22-EXCEPTION set surfaced; the fresh grep of `EntropyLib\.entropyStep` at HEAD yielded exactly 8 call sites set-equal with Phase 237's 8 EXC-04 rows (INV-237-124, -131, -132, -134..138).

## 3. EXC-01 Consolidated ONLY-ness Table

Per D-06 — universal ONLY-ness claim at HEAD `7ab515fe`: the 4 KI RNG entries are the SOLE violations of the RNG-consumer determinism invariant. Table lists the 22 EXCEPTION rows enumerated from Phase 237 `audit/v30-CONSUMER-INVENTORY.md` (the remaining 124 `VRF_DERIVED` rows are implicitly certified by Gate A's set-equality check against Phase 238's 124-SAFE count — NOT enumerated here per plan action).

Row-ID prefix `EXC-241-NNN` (D-23). Distribution: 2 EXC-01 (INV-237-005, -006) + 8 EXC-02 (INV-237-055..062) + 4 EXC-03 (INV-237-024, -045, -053, -054) + 8 EXC-04 (INV-237-124, -131, -132, -134..138) = 22 rows. Set-equal with Phase 238 `audit/v30-FREEZE-PROOF.md` 22-EXCEPTION / 124-SAFE distribution (`re-verified at HEAD 7ab515fe` — Phase 238's 22-row EXCEPTION set matches row-for-row the set enumerated below).

D-05 exploitability frame: `Player-Reachable Exploitability` column describes the player-reachable manipulation surface per KI envelope — NOT distribution quality.

| EXC-241-NNN | INV-237-NNN | File:Line | KI Group | Seed-Source Verdict | Player-Reachable Exploitability | Closed Verdict |
| ----------- | ----------- | --------- | -------- | ------------------- | ------------------------------- | -------------- |
| EXC-241-001 | INV-237-005 | `contracts/DegenerusAffiliate.sol:568` | EXC-01 (affiliate winner roll) | NON_VRF_PER_KI_EXC_01 | Player can time purchase across `currentDayIndex()` rollover to redirect affiliate credit between VAULT/DGNRS (50/50 flip); no protocol value extraction — payout total unchanged | CONFIRMED_SOLE_EXCEPTION_GROUP_EXC_01 |
| EXC-241-002 | INV-237-006 | `contracts/DegenerusAffiliate.sol:585` | EXC-01 (affiliate winner roll) | NON_VRF_PER_KI_EXC_01 | Player can time purchase across `currentDayIndex()` rollover to redirect 75/20/5 weighted winner (affiliate/upline1/upline2); redistributive between candidates, EV-neutral for protocol | CONFIRMED_SOLE_EXCEPTION_GROUP_EXC_01 |
| EXC-241-003 | INV-237-055 | `contracts/modules/DegenerusGameAdvanceModule.sol:1252` | EXC-02 (gameover prevrandao fallback) | NON_VRF_PER_KI_EXC_02 | VALIDATOR_ONLY_AFTER_14_DAYS — only reachable inside `_gameOverEntropy` after `GAMEOVER_RNG_FALLBACK_DELAY = 14 days` elapsed; player cannot induce VRF 14-day outage | CONFIRMED_SOLE_EXCEPTION_GROUP_EXC_02 |
| EXC-241-004 | INV-237-056 | `contracts/modules/DegenerusGameAdvanceModule.sol:1253` | EXC-02 (gameover prevrandao fallback) | NON_VRF_PER_KI_EXC_02 | VALIDATOR_ONLY_AFTER_14_DAYS — `_applyDailyRng(day, fallbackWord)` runs only on fallback path (post-14-day-gate); not player-reachable | CONFIRMED_SOLE_EXCEPTION_GROUP_EXC_02 |
| EXC-241-005 | INV-237-057 | `contracts/modules/DegenerusGameAdvanceModule.sol:1257` | EXC-02 (gameover prevrandao fallback) | NON_VRF_PER_KI_EXC_02 | VALIDATOR_ONLY_AFTER_14_DAYS — coinflip payouts consume fallback word only on post-14-day-gate path | CONFIRMED_SOLE_EXCEPTION_GROUP_EXC_02 |
| EXC-241-006 | INV-237-058 | `contracts/modules/DegenerusGameAdvanceModule.sol:1268` | EXC-02 (gameover prevrandao fallback) | NON_VRF_PER_KI_EXC_02 | VALIDATOR_ONLY_AFTER_14_DAYS — redemption roll `((fallbackWord >> 8) % 151) + 25` reachable only on post-14-day-gate path | CONFIRMED_SOLE_EXCEPTION_GROUP_EXC_02 |
| EXC-241-007 | INV-237-059 | `contracts/modules/DegenerusGameAdvanceModule.sol:1274` | EXC-02 (gameover prevrandao fallback) | NON_VRF_PER_KI_EXC_02 | VALIDATOR_ONLY_AFTER_14_DAYS — `_finalizeLootboxRng(fallbackWord)` reachable only on post-14-day-gate path | CONFIRMED_SOLE_EXCEPTION_GROUP_EXC_02 |
| EXC-241-008 | INV-237-060 | `contracts/modules/DegenerusGameAdvanceModule.sol:1308` | EXC-02 (gameover prevrandao fallback) | NON_VRF_PER_KI_EXC_02 | VALIDATOR_ONLY_AFTER_14_DAYS — historical-word SLOAD inside `_getHistoricalRngFallback`; caller gated by :1250 14-day check | CONFIRMED_SOLE_EXCEPTION_GROUP_EXC_02 |
| EXC-241-009 | INV-237-061 | `contracts/modules/DegenerusGameAdvanceModule.sol:1310` | EXC-02 (gameover prevrandao fallback) | NON_VRF_PER_KI_EXC_02 | VALIDATOR_ONLY_AFTER_14_DAYS — cumulative keccak of 5 historical VRF words inside `_getHistoricalRngFallback`; post-14-day-gate only | CONFIRMED_SOLE_EXCEPTION_GROUP_EXC_02 |
| EXC-241-010 | INV-237-062 | `contracts/modules/DegenerusGameAdvanceModule.sol:1322` | EXC-02 (gameover prevrandao fallback) | NON_VRF_PER_KI_EXC_02 | VALIDATOR_ONLY_AFTER_14_DAYS — final `keccak256(abi.encodePacked(combined, currentDay, block.prevrandao))` mix; 1-bit validator proposer bias per EIP-4399, KI-accepted | CONFIRMED_SOLE_EXCEPTION_GROUP_EXC_02 |
| EXC-241-011 | INV-237-024 | `contracts/modules/DegenerusGameAdvanceModule.sol:292` | EXC-03 (F-29-04 mid-cycle substitution) | NON_VRF_PER_KI_EXC_03 | NO_PLAYER_REACHABLE_TIMING — cross-cite Phase 240 GO-04 `DISPROVEN_PLAYER_REACHABLE_VECTOR` for both gameover triggers (120-day liveness + pool deficit) | CONFIRMED_SOLE_EXCEPTION_GROUP_EXC_03 |
| EXC-241-012 | INV-237-045 | `contracts/modules/DegenerusGameAdvanceModule.sol:1082` | EXC-03 (F-29-04 mid-cycle substitution) | NON_VRF_PER_KI_EXC_03 | NO_PLAYER_REACHABLE_TIMING — mid-day `_swapTicketSlot(purchaseLevel_)` pre-VRF swap; gameover-trigger-timing disproven per Phase 240 GO-04 | CONFIRMED_SOLE_EXCEPTION_GROUP_EXC_03 |
| EXC-241-013 | INV-237-053 | `contracts/modules/DegenerusGameAdvanceModule.sol:1221-1223` | EXC-03 (F-29-04 mid-cycle substitution) | NON_VRF_PER_KI_EXC_03 | NO_PLAYER_REACHABLE_TIMING — `_gameOverEntropy` substitution block; terminal-state-only + Phase 240 GO-05 `BOTH_DISJOINT` | CONFIRMED_SOLE_EXCEPTION_GROUP_EXC_03 |
| EXC-241-014 | INV-237-054 | `contracts/modules/DegenerusGameAdvanceModule.sol:1222-1246` | EXC-03 (F-29-04 mid-cycle substitution) | NON_VRF_PER_KI_EXC_03 | NO_PLAYER_REACHABLE_TIMING — `_gameOverEntropy` consumer cluster (coinflip/redemption/lootbox-finalize); same gameover-terminal-state envelope | CONFIRMED_SOLE_EXCEPTION_GROUP_EXC_03 |
| EXC-241-015 | INV-237-124 | `contracts/modules/DegenerusGameJackpotModule.sol:2119` | EXC-04 (EntropyLib XOR-shift seed) | NON_VRF_PER_KI_EXC_04 | VRF_SEED_FROZEN_BY_CALLER_SITE_KECCAK — `_jackpotTicketRoll` entropy derived through chain from `runBafJackpot(poolWei, lvl, rngWord)` caller; rngWord VRF-sourced; cross-cite Phase 238-03 `lootbox-index-advance` Named Gate | CONFIRMED_SOLE_EXCEPTION_GROUP_EXC_04 |
| EXC-241-016 | INV-237-131 | `contracts/modules/DegenerusGameLootboxModule.sol:813` | EXC-04 (EntropyLib XOR-shift seed) | NON_VRF_PER_KI_EXC_04 | VRF_SEED_FROZEN_BY_CALLER_SITE_KECCAK — `_rollTargetLevel` seeded from `keccak256(abi.encode(rngWord, player, day, amount))` constructions at `:554, :628, :673, :708`; rngWord VRF-sourced | CONFIRMED_SOLE_EXCEPTION_GROUP_EXC_04 |
| EXC-241-017 | INV-237-132 | `contracts/modules/DegenerusGameLootboxModule.sol:817` | EXC-04 (EntropyLib XOR-shift seed) | NON_VRF_PER_KI_EXC_04 | VRF_SEED_FROZEN_BY_CALLER_SITE_KECCAK — far-future entropyStep chained from `levelEntropy` (which chained from VRF-seeded entropy per previous row) | CONFIRMED_SOLE_EXCEPTION_GROUP_EXC_04 |
| EXC-241-018 | INV-237-134 | `contracts/modules/DegenerusGameLootboxModule.sol:1548` | EXC-04 (EntropyLib XOR-shift seed) | NON_VRF_PER_KI_EXC_04 | VRF_SEED_FROZEN_BY_CALLER_SITE_KECCAK — `_resolveLootboxRoll` chained from VRF-seeded `entropy` via caller chain to keccak seed construction; rngWord VRF-sourced | CONFIRMED_SOLE_EXCEPTION_GROUP_EXC_04 |
| EXC-241-019 | INV-237-135 | `contracts/modules/DegenerusGameLootboxModule.sol:1569` | EXC-04 (EntropyLib XOR-shift seed) | NON_VRF_PER_KI_EXC_04 | VRF_SEED_FROZEN_BY_CALLER_SITE_KECCAK — DGNRS-tier sub-roll chained from previous XOR-shift step (VRF-sourced) | CONFIRMED_SOLE_EXCEPTION_GROUP_EXC_04 |
| EXC-241-020 | INV-237-136 | `contracts/modules/DegenerusGameLootboxModule.sol:1585` | EXC-04 (EntropyLib XOR-shift seed) | NON_VRF_PER_KI_EXC_04 | VRF_SEED_FROZEN_BY_CALLER_SITE_KECCAK — WWXRP-tier sub-roll chained from previous XOR-shift step (VRF-sourced) | CONFIRMED_SOLE_EXCEPTION_GROUP_EXC_04 |
| EXC-241-021 | INV-237-137 | `contracts/modules/DegenerusGameLootboxModule.sol:1599-1600` | EXC-04 (EntropyLib XOR-shift seed) | NON_VRF_PER_KI_EXC_04 | VRF_SEED_FROZEN_BY_CALLER_SITE_KECCAK — large-BURNIE variance roll chained from previous XOR-shift step (VRF-sourced) | CONFIRMED_SOLE_EXCEPTION_GROUP_EXC_04 |
| EXC-241-022 | INV-237-138 | `contracts/modules/DegenerusGameLootboxModule.sol:1635-1636` | EXC-04 (EntropyLib XOR-shift seed) | NON_VRF_PER_KI_EXC_04 | VRF_SEED_FROZEN_BY_CALLER_SITE_KECCAK — `_lootboxTicketCount` chained from VRF-seeded `entropy` (caller passes nextEntropy from prior XOR-shift chain); rngWord VRF-sourced | CONFIRMED_SOLE_EXCEPTION_GROUP_EXC_04 |

### Gate A — Set-Equality Check (D-08)

The 22 EXC-241-NNN rows listed above form the set:

`{INV-237-005, INV-237-006} ∪ {INV-237-055, -056, -057, -058, -059, -060, -061, -062} ∪ {INV-237-024, INV-237-045, INV-237-053, INV-237-054} ∪ {INV-237-124, INV-237-131, INV-237-132, INV-237-134, INV-237-135, INV-237-136, INV-237-137, INV-237-138}`

Count = 2 + 8 + 4 + 8 = 22.

Cross-check against Phase 238 `audit/v30-FREEZE-PROOF.md` Consolidated Freeze-Proof Table `re-verified at HEAD 7ab515fe` — Phase 238's 22-EXCEPTION distribution (EXC-01=2 / EXC-02=8 / EXC-03=4 / EXC-04=8) matches this set row-for-row; structural equivalence holds (same INV-237-NNN set + same KI-group mapping at HEAD `7ab515fe`, contract tree identical to v29.0 `1646d5af`).

Verdict: **GATE_A_PASSES** — 22 EXC-241-NNN rows set-equal with Phase 238 EXCEPTION distribution; no Phase 237 inventory row with verdict ≠ `VRF_DERIVED` lies outside this set; no row in this set is missing at HEAD.

## 4. EXC-01 Grep Backstop Classification

Per D-07 — grep sweep over `contracts/` tree (excluding `contracts/mocks/` per mock-exclusion convention) for the closed player-reachable non-VRF entropy surface universe. Each hit classified per closed D-07 vocabulary.

### Grep Commands (reproducibility)

```
grep -rn 'block\.timestamp' contracts/ --include='*.sol'  | grep -v mocks/
grep -rn 'block\.number' contracts/ --include='*.sol'     | grep -v mocks/
grep -rn 'block\.prevrandao' contracts/ --include='*.sol' | grep -v mocks/
grep -rn 'blockhash' contracts/ --include='*.sol'         | grep -v mocks/
grep -rn 'block\.coinbase' contracts/ --include='*.sol'   | grep -v mocks/
grep -rn 'block\.difficulty' contracts/ --include='*.sol' | grep -v mocks/
grep -rn 'tx\.origin' contracts/ --include='*.sol'        | grep -v mocks/
grep -rn 'currentDayIndex' contracts/ --include='*.sol'   | grep -v mocks/
grep -rn 'storedCode' contracts/ --include='*.sol'        | grep -v mocks/
grep -rnE 'keccak256\(abi\.encode(Packed)?\(' contracts/ --include='*.sol' | grep -v mocks/
```

Comment-line hits (lines beginning with `*`, `//`, or inside `///` NatSpec) excluded unless they indicate a reachable code path; the verdict is derived from executable hits only.

### Gate B — Grep Backstop Classification Table

| Surface | Grep Pattern | Hits (non-comment) | file:line sample | Classification | Notes |
| ------- | ------------ | ------------------ | ---------------- | -------------- | ----- |
| `block.timestamp` | `block\.timestamp` | 33 | `DegenerusAdmin.sol:501` (proposal lifetime); `DegenerusAdmin.sol:667, :706, :762` (stall threshold); `DegenerusGameGameOverModule.sol:137, :190` (gameover-time + sweep-delay); `DegenerusStonk.sol:307` (365-day sweep gate); `DegenerusGameAdvanceModule.sol:158, :506, :554, :1007, :1036, :1109, :1578, :1787` (rngRequestTime / dailyIdx / lastVrfProcessedTimestamp / currentDayIndex plumbing); `GameTimeLib.sol:22` (`currentDayIndex()` implementation) | ORTHOGONAL_NOT_RNG_CONSUMED | Every hit consumed by (a) governance proposal lifetime gates (Admin), (b) stall detection, (c) daily-index calculation, (d) VRF-request-timestamp tracking (`rngRequestTime` — used ONLY for the 14-day fallback gate at `:1250`, NOT as entropy fed to an RNG consumer), (e) sweep-delay timers, or (f) `currentDayIndex()` feeding the EXC-01 affiliate keccak seed at `DegenerusAffiliate.sol:572, :589` (BELONGS_TO_KI_EXC_01 — already enumerated in § 3 EXC-241-001/002). No hit outside these categories feeds an RNG consumer. |
| `block.number` | `block\.number` | 0 | (none) | ORTHOGONAL_NOT_RNG_CONSUMED | Zero executable hits in `contracts/`. |
| `block.prevrandao` | `block\.prevrandao` | 1 | `DegenerusGameAdvanceModule.sol:1322` (`_getHistoricalRngFallback`) | BELONGS_TO_KI_EXC_02 | Sole executable hit is the final `keccak256(abi.encodePacked(combined, currentDay, block.prevrandao))` mix at `:1322` — already enumerated as EXC-241-010 (INV-237-062) in § 3. |
| `blockhash(...)` | `blockhash` | 0 | (none) | ORTHOGONAL_NOT_RNG_CONSUMED | Zero executable hits in `contracts/`. |
| `block.coinbase` | `block\.coinbase` | 0 | (none) | ORTHOGONAL_NOT_RNG_CONSUMED | Zero executable hits. |
| `block.difficulty` | `block\.difficulty` | 0 | (none) | ORTHOGONAL_NOT_RNG_CONSUMED | Zero executable hits (replaced post-merge by `prevrandao`; no legacy usage). |
| `tx.origin` | `tx\.origin` | 0 | (none) | ORTHOGONAL_NOT_RNG_CONSUMED | Zero executable hits in `contracts/`. |
| `currentDayIndex()` (packed day counter used as entropy) | `currentDayIndex` | multiple | `DegenerusAffiliate.sol:572, :589` (affiliate EXC-01 seed); `DegenerusGame.sol:217` + `DegenerusGameStorage.sol:1213, :1234` + `GameTimeLib.sol:21, :31` (pure time-index reads feeding `day` parameters, NOT RNG seeds) | BELONGS_TO_KI_EXC_01 (at `DegenerusAffiliate.sol:572, :589`) + ORTHOGONAL_NOT_RNG_CONSUMED (elsewhere) | Only 2 executable uses as entropy — both in EXC-01 scope (already enumerated EXC-241-001/002). All other uses are bare time-index SLOAD for `day` arithmetic, not entropy seeds. |
| `storedCode` (affiliate referral packed counter used as entropy) | `storedCode` | multiple | `DegenerusAffiliate.sol:574, :591` (affiliate EXC-01 seed); other hits in `DegenerusAffiliate.sol:408..507` are read/write lifecycle for storage slot, not entropy | BELONGS_TO_KI_EXC_01 (at `DegenerusAffiliate.sol:574, :591`) + ORTHOGONAL_NOT_RNG_CONSUMED (elsewhere) | Entropy-as-seed uses are the 2 EXC-01 rows; other uses are referral-slot lifecycle (reads/writes to storage, not entropy feeds). |
| `keccak256(...)` non-VRF-committed state feeding an RNG consumer | `keccak256\(abi\.encode(Packed)?\(` | 0 non-VRF-committed RNG-feeding hits outside known KI set | (see § 3) | ORTHOGONAL_NOT_RNG_CONSUMED or BELONGS_TO_KI_EXC_NN | Every `keccak256(abi.encode(rngWord, ...))` construction is VRF-seeded (see § 7 EXC-04-P1b enumeration). Non-VRF `keccak256(...)` constructions on packed state (e.g., slot keys, referral codes, event topic construction, `FUTURE_KEEP_TAG` packed-encode) either (a) serve as storage slot keys / event topic construction (not RNG seeds), or (b) are the 2 EXC-01 affiliate rows (already enumerated). Grep of `keccak256\(abi\.encodePacked\(.*AFFILIATE_ROLL_TAG` confirms the only non-VRF keccak seed path feeding an RNG consumer is the affiliate roll at `DegenerusAffiliate.sol:569-577, :586-594`. |
| `msg.sender` used as seed input | `msg\.sender` | multiple | `DegenerusAffiliate.sol:573, :590` (as `sender` parameter threaded into EXC-01 keccak seed); other hits are access-control / authentication (not entropy) | BELONGS_TO_KI_EXC_01 (at seed-feeding sites) + ORTHOGONAL_NOT_RNG_CONSUMED (elsewhere) | `sender` argument to `processAffiliatePayment` derives from a prior `msg.sender` read at caller chain — threaded into EXC-01 seed; already enumerated. |

**Verdict:** **GATE_B_PASSES** — every grep hit over the D-07 surface universe classifies as either `ORTHOGONAL_NOT_RNG_CONSUMED` or `BELONGS_TO_KI_EXC_NN`. Zero `CANDIDATE_FINDING` hits. No latent non-VRF entropy surface leaks into any RNG-derived payout or winner-selection path outside the 4 KI groups.

### Combined Closure Verdict

Per D-08: **`ONLY_NESS_HOLDS_AT_HEAD`** — Gate A PASSES (set-equality with Phase 238's 22-EXCEPTION distribution at HEAD `7ab515fe`) AND Gate B PASSES (grep backstop zero CANDIDATE_FINDING). The 4 KNOWN-ISSUES RNG entries (EXC-01/02/03/04) are confirmed as the ONLY violations of the RNG-consumer determinism invariant at HEAD `7ab515fe`. The universal ONLY-ness claim holds.

## 5. EXC-02 Predicate Re-Verification

Per D-10 — EXC-02 predicate re-derivation fresh at HEAD `7ab515fe`. Two predicates; BOTH must hold for `EXC-02 RE_VERIFIED_AT_HEAD`.

### Grep Commands (reproducibility)

```
grep -rn '_getHistoricalRngFallback' contracts/ --include='*.sol'
grep -rn 'GAMEOVER_RNG_FALLBACK_DELAY' contracts/ --include='*.sol'
```

### Predicate Table

| Predicate ID | Predicate Name | Target file:line | Grep Command | Hits | Gate Expression | HEAD Verdict |
| ------------ | -------------- | ---------------- | ------------ | ---- | --------------- | ------------ |
| EXC-02-P1 | Single-call-site predicate | `contracts/modules/DegenerusGameAdvanceModule.sol:1252` (sole CALL_SITE) + `:1301` (DEFINITION_SITE) | `grep -rn '_getHistoricalRngFallback' contracts/ --include='*.sol'` | 2 total: 1 DEFINITION (`:1301`) + 1 CALL_SITE (`:1252`, inside `_gameOverEntropy`). Zero additional callers. Zero COMMENT_OR_DOC hits outside DEFINITION/CALL scope. | Sole reachable invocation: `uint256 fallbackWord = _getHistoricalRngFallback(day);` at `:1252`, inside the enclosing `if (rngRequestTime != 0) { ... if (elapsed >= GAMEOVER_RNG_FALLBACK_DELAY) { ... }` body — NO other call site in any contract or module at HEAD `7ab515fe`. | RE_VERIFIED_AT_HEAD |
| EXC-02-P2 | 14-day gate predicate | `contracts/modules/DegenerusGameAdvanceModule.sol:109` (constant decl) + `:1250` (gate check) | `grep -rn 'GAMEOVER_RNG_FALLBACK_DELAY' contracts/ --include='*.sol'` | 2 total: 1 declaration (`:109` — `uint48 private constant GAMEOVER_RNG_FALLBACK_DELAY = 14 days;`) + 1 gate check (`:1250` — `if (elapsed >= GAMEOVER_RNG_FALLBACK_DELAY) { ... }`). Zero additional usages. | `_gameOverEntropy` branch at `:1248-1277` wraps the fallback call inside `if (rngRequestTime != 0)` outer guard + `uint48 elapsed = ts - rngRequestTime; if (elapsed >= GAMEOVER_RNG_FALLBACK_DELAY)` inner guard. Every reachable path into `_getHistoricalRngFallback` at `:1252` is preceded by the 14-day delay comparison. The `else` branch (elapsed < 14 days) reverts with `RngNotReady()` at `:1277`. | RE_VERIFIED_AT_HEAD |

### Section-Level Verdict

**`EXC-02 RE_VERIFIED_AT_HEAD`** — both predicates hold at HEAD `7ab515fe`.

### Cross-Cites (per D-12, corroborating only)

- **CITE Phase 239 `audit/v30-RNGLOCK-STATE-MACHINE.md` RNG-01 `AIRTIGHT`** — `re-verified at HEAD 7ab515fe`. Structural equivalence statement: the `rngLockedFlag` state machine at HEAD (1 Set-Site `AdvanceModule:1579` + 3 Clear-Sites + 9 Path Enumeration rows) is unchanged from Phase 239-01's proof (commit `5764c8a4`); no set-without-clear or clear-without-matching-set at HEAD; gameover-entry paths into `_gameOverEntropy` remain gated by the `rngLockedFlag` state machine, corroborating reachability closure for the `_getHistoricalRngFallback` caller.
- **CITE Phase 240 `audit/v30-GAMEOVER-JACKPOT-SAFETY.md` GO-02 VRF-available-branch determinism** — `re-verified at HEAD 7ab515fe`. Structural equivalence statement: 8-row prevrandao-fallback inventory (GO-240-008..015) at Phase 240 identifies consumer-level EXC-02 presence for the 8 INV-237-055..062 rows; each row decorated with `See Phase 241 EXC-02` forward-cite token; Phase 241's 2-predicate re-verification here discharges consumer-level presence to per-predicate closure for those 8 consumer rows.

## 6. EXC-03 Tri-Gate Predicate Re-Verification

Per D-10 — EXC-03 predicate re-derivation fresh at HEAD `7ab515fe`. Three predicates (tri-gate); ALL THREE must hold for `EXC-03 RE_VERIFIED_AT_HEAD`.

### Predicate Table

| Predicate ID | Predicate Name | Target file:line(s) | HEAD Evidence | Cross-Cite | HEAD Verdict |
| ------------ | -------------- | ------------------- | ------------- | ---------- | ------------ |
| EXC-03-P1 | Terminal-state predicate | `contracts/modules/DegenerusGameAdvanceModule.sol:1222-1246` (substitution site inside `_gameOverEntropy`) | Grep reachability: `_gameOverEntropy` is private at `:~1209` and called from a single invocation site in `advanceGame` at `:553` (gameover branch entry). The substitution block `:1222-1246` lives inside the `if (currentWord != 0 && rngRequestTime != 0)` branch of `_gameOverEntropy` which is NOT reachable from any other caller. No non-gameover caller path reaches the substitution region at HEAD. | Phase 240 GO-05 `BOTH_DISJOINT` — the 4-row F-29-04 INV-237 subset + 6-slot primitive-storage subset is structurally disjoint from the 7-row VRF-available gameover-entropy inventory + 25-slot jackpot-input state-variable universe (`re-verified at HEAD 7ab515fe`) | RE_VERIFIED_AT_HEAD |
| EXC-03-P2 | No-player-reachable-timing predicate | Gameover trigger surfaces (120-day liveness stall + pool deficit) as the only entries into `_gameOverEntropy` | Phase 240 GO-04 enumerates exactly 2 `GOTRIG-240-NNN` trigger surfaces, BOTH classified `DISPROVEN_PLAYER_REACHABLE_VECTOR`: (1) 120-day liveness stall — `block.timestamp` drift + `_livenessTriggered()` pure view over committed state; no player can advance `block.timestamp` by 120 days; (2) pool deficit — safety-escape trigger evaluated on deterministic `futurePool` / `nextPool` math; player purchase contribution to deficit is bounded and cannot time a specific mid-cycle write-buffer state alignment. | Phase 240 `audit/v30-GAMEOVER-JACKPOT-SAFETY.md` GO-04 2 `GOTRIG-240-NNN DISPROVEN_PLAYER_REACHABLE_VECTOR` rows (`re-verified at HEAD 7ab515fe` — gameover triggers unchanged; contract tree identical to v29.0 `1646d5af`). v29.0 Phase 235 Plan 04 F-29-04 commitment-window trace artifact corroborates the terminal-state + no-player-timing classification as contemporaneous evidence (prior-milestone, not relied upon per D-12). | RE_VERIFIED_AT_HEAD |
| EXC-03-P3 | Buffer-scope predicate | Buffer primitives `_swapAndFreeze(purchaseLevel)` at `contracts/modules/DegenerusGameAdvanceModule.sol:292` + `_swapTicketSlot(purchaseLevel_)` at `:1082`; substitution applies only to tickets in the post-swap write buffer | Both buffer-swap primitives unchanged at HEAD: `:292` invokes `_swapAndFreeze(purchaseLevel)` right before the daily VRF request branch (STAGE_RNG_REQUESTED); `:1082` invokes `_swapTicketSlot(purchaseLevel_)` inside `requestLootboxRng` right before the mid-day VRF `requestRandomWords` call at `:1088`. The 6 F-29-04 write-buffer-swap primitive storage slots per Phase 240 GO-05 — `ticketWriteSlot`, `ticketsFullyProcessed`, `ticketQueue[]`, `ticketsOwedPacked[][]`, `ticketCursor`, `ticketLevel` — are the exclusive substitution scope; no non-buffer slot is affected. | Phase 240 GO-05 `BOTH_DISJOINT` verdict (inventory-level + state-variable-level disjointness: `{4 F-29-04 rows} ∩ {7 VRF-available gameover-entropy rows} = ∅`, `{6 F-29-04 buffer slots} ∩ {25 GOVAR jackpot-input slots} = ∅`; `re-verified at HEAD 7ab515fe` — buffer primitive line numbers unchanged). | RE_VERIFIED_AT_HEAD |

### Section-Level Verdict

**`EXC-03 RE_VERIFIED_AT_HEAD`** — all three predicates hold at HEAD `7ab515fe`. F-29-04 mid-cycle RNG substitution remains (a) terminal-state only, (b) no player-reachable timing, (c) buffer-scope only. Phase 241 ADDS tri-gate closure on top of Phase 240's existing GO-05 `BOTH_DISJOINT` (per D-17 discipline — Phase 241 does NOT re-derive Phase 240's disjointness proof).

## 7. EXC-04 EntropyLib Seed-Construction Re-Verification

**CRITICAL ARCHITECTURAL NOTE (READ-verified from `contracts/libraries/EntropyLib.sol:16-23` at HEAD `7ab515fe`):** `EntropyLib.entropyStep(uint256 state)` is a pure XOR-shift function with ZERO keccak calls inside it. The keccak seed construction lives at **caller sites**, NOT inside `entropyStep`. Per plan D-10 two-part predicate, EXC-04 re-verification addresses:
- **P1a:** the `entropyStep` XOR-shift body at `contracts/libraries/EntropyLib.sol:16-23`
- **P1b:** the caller-site `keccak256(abi.encode(rngWord, ...))` constructions at Lootbox/Jackpot/Staked/DegenerusGame modules that feed entropy into `entropyStep`

Per D-10 — EXC-04 predicate re-derivation fresh at HEAD `7ab515fe`. Two predicates; BOTH parts must hold for `EXC-04 RE_VERIFIED_AT_HEAD`.

### Grep Commands (reproducibility)

```
grep -rn 'function entropyStep(uint256 state) internal pure' contracts/libraries/EntropyLib.sol
grep -rn 'EntropyLib\.entropyStep' contracts/ --include='*.sol'
grep -rnE 'keccak256\(abi\.encode\(rngWord' contracts/ --include='*.sol'
```

### Predicate Table

| Predicate ID | Predicate Name | Target file:line | Grep Command | Hits | rngWord / state Source | HEAD Verdict |
| ------------ | -------------- | ---------------- | ------------ | ---- | ---------------------- | ------------ |
| EXC-04-P1a | EntropyLib.entropyStep body intact | `contracts/libraries/EntropyLib.sol:16-23` | `grep -n 'function entropyStep(uint256 state) internal pure' contracts/libraries/EntropyLib.sol` | 1 definition at `:16`. Body at `:17-21` is an `unchecked { ... }` block containing exactly `state ^= state << 7;` (`:18`), `state ^= state >> 9;` (`:19`), `state ^= state << 8;` (`:20`). Return at `:22` (`return state;`). Closing brace `:23`. Zero keccak / zero library calls inside body; no additional statements; no new overload of `entropyStep`. | N/A (pure function, no VRF source — `state` comes from caller) | RE_VERIFIED_AT_HEAD |
| EXC-04-P1b | Caller-site keccak seed construction intact and VRF-sourced | Caller sites across Lootbox/Jackpot/Staked/DegenerusGame modules — 8 `entropyStep` consumers + 8 caller-site `keccak256(abi.encode(rngWord, ...))` constructions | `grep -rnE 'keccak256\(abi\.encode\(rngWord' contracts/ --include='*.sol'` + `grep -rn 'EntropyLib\.entropyStep' contracts/ --include='*.sol'` | Keccak-seed hits (8 caller-site constructions, all NON-zero): `DegenerusGame.sol:1769` (`keccak256(abi.encode(rngWord))` single-arg chain), `StakedDegenerusStonk.sol:660` (`keccak256(abi.encode(rngWord, player))`), `DegenerusGameJackpotModule.sol:1799` (`keccak256(abi.encode(rngWord, lvl, FAR_FUTURE_COIN_TAG))`), `DegenerusGameLootboxModule.sol:554, :628, :673, :708` (all `keccak256(abi.encode(rngWord, player, day, amount/amountEth))`), `DegenerusGameLootboxModule.sol:1753` (`keccak256(abi.encode(rngWordByDay[day], deity, day, slot))`). `entropyStep` call-site hits (8 executable — comment at `JackpotModule:43` excluded): `LootboxModule:813, :817, :1548, :1569, :1585, :1599, :1635`; `JackpotModule:2119`. | Every `rngWord` / `rngWordByDay[day]` argument traces to a VRF-callback write site: `AdvanceModule.rawFulfillRandomWords:1690` writes `rngWordCurrent = word` at `:1702` and `lootboxRngWordByIndex[index] = word` at `:1706`; `AdvanceModule._applyDailyRng:1773` writes `rngWordByDay[day] = finalWord` at `:1786`; `_backfillGapDays:1724` writes `rngWordByDay[gapDay] = derivedWord` at `:1738` where `derivedWord = keccak256(vrfWord, gapDay)` (vrfWord is VRF-sourced). All 8 `entropyStep` call sites receive `state`/`entropy`/`nextEntropy` pre-derived from one of these VRF-seeded keccak constructions (directly OR transitively via prior `entropyStep` chain). | RE_VERIFIED_AT_HEAD |

### Call-Site Inventory

Per-row trace of the 8 Phase 237 EXC-04 rows: for each `entropyStep` call site, cite the upstream caller-site keccak construction that produced the `state`/`entropy`/`nextEntropy` argument, then cite the VRF-callback source of `rngWord`.

| INV-237-NNN | entropyStep Call Site (file:line) | Upstream Caller-Site Keccak (file:line) | rngWord VRF Source (file:line) | EXC-04 Verdict |
| ----------- | --------------------------------- | --------------------------------------- | ------------------------------ | -------------- |
| INV-237-124 | `contracts/modules/DegenerusGameJackpotModule.sol:2119` (`entropy = EntropyLib.entropyStep(entropy);` inside `_jackpotTicketRoll`) | `entropy` param passed from `_awardJackpotTickets` (`:2068`) which receives `rngWord` threaded from `runBafJackpot(poolWei, lvl, rngWord)` caller chain at `JackpotModule:1966, :1974, :2008, :2037` — ultimately derived from `rngWord` argument to `_rewardJackpots` (which in turn is set from `rngGate`→`rngWordCurrent` or `_gameOverEntropy`). No intermediate keccak is required here because the VRF-sourced `rngWord` itself serves as the initial `entropy`; subsequent XOR-shift steps diverge per roll. | `rngWordCurrent` written at `AdvanceModule:1702` inside `rawFulfillRandomWords:1690` (VRF callback) | RE_VERIFIED_AT_HEAD |
| INV-237-131 | `contracts/modules/DegenerusGameLootboxModule.sol:813` (`uint256 levelEntropy = EntropyLib.entropyStep(entropy);` inside `_rollTargetLevel`) | `entropy` argument to `_rollTargetLevel` sourced from caller's `keccak256(abi.encode(rngWord, player, day, amount))` constructions at `LootboxModule:554` (`_resolveLootboxStandard`), `:628` (post-grace path), `:673` (`resolveLootboxDirect`), `:708` (`resolveRedemptionLootbox`) | `rngWord` argument to those caller functions derives from: `lootboxRngWordByIndex[index]` (written at `AdvanceModule:1204, :1706`) for lootbox open paths; `rngWordByDay[day]` (written at `:1786`) for redemption path; both VRF-sourced | RE_VERIFIED_AT_HEAD |
| INV-237-132 | `contracts/modules/DegenerusGameLootboxModule.sol:817` (`uint256 farEntropy = EntropyLib.entropyStep(levelEntropy);` inside `_rollTargetLevel` far-future branch) | `levelEntropy` is the return value of the preceding XOR-shift at `:813` (INV-237-131); same VRF-seeded chain | Same VRF sources as INV-237-131 | RE_VERIFIED_AT_HEAD |
| INV-237-134 | `contracts/modules/DegenerusGameLootboxModule.sol:1548` (`nextEntropy = EntropyLib.entropyStep(entropy);` inside `_resolveLootboxRoll`) | `entropy` argument to `_resolveLootboxRoll` is the `nextEntropy` threaded from `_rollTargetLevel` via `_resolveLootboxCommon`; caller chain ultimately seeded by `keccak256(abi.encode(rngWord, player, day, amount))` at `:554, :628, :673, :708` + `keccak256(abi.encode(rngWordByDay[day], deity, day, slot))` at `:1753` | Same VRF sources as INV-237-131 (+ daily VRF slot for the `:1753` deity/box resolution chain) | RE_VERIFIED_AT_HEAD |
| INV-237-135 | `contracts/modules/DegenerusGameLootboxModule.sol:1569` (`nextEntropy = EntropyLib.entropyStep(nextEntropy);` DGNRS-tier sub-roll) | `nextEntropy` is the return value of the preceding XOR-shift at `:1548` (INV-237-134); same VRF-seeded chain | Same VRF sources as INV-237-134 | RE_VERIFIED_AT_HEAD |
| INV-237-136 | `contracts/modules/DegenerusGameLootboxModule.sol:1585` (`nextEntropy = EntropyLib.entropyStep(nextEntropy);` WWXRP-tier sub-roll) | `nextEntropy` is the return value of the preceding XOR-shift at `:1548` / `:1569` (VRF-seeded chain) | Same VRF sources as INV-237-134 | RE_VERIFIED_AT_HEAD |
| INV-237-137 | `contracts/modules/DegenerusGameLootboxModule.sol:1599-1600` (`nextEntropy = EntropyLib.entropyStep(nextEntropy);` large-BURNIE variance roll) | `nextEntropy` is the return value of preceding XOR-shift at `:1548/:1569/:1585` (VRF-seeded chain) | Same VRF sources as INV-237-134 | RE_VERIFIED_AT_HEAD |
| INV-237-138 | `contracts/modules/DegenerusGameLootboxModule.sol:1635-1636` (`nextEntropy = EntropyLib.entropyStep(entropy);` inside `_lootboxTicketCount`) | `entropy` argument to `_lootboxTicketCount` is the `nextEntropy` threaded from `_resolveLootboxRoll:1548` (INV-237-134); VRF-seeded chain | Same VRF sources as INV-237-134 | RE_VERIFIED_AT_HEAD |

### Phase 237 Inventory Reconciliation

Phase 237 Consumer Index records 8 rows tagged `exception-xor-shift-seed`-adjacent (INV-237-124, -131, -132, -134, -135, -136, -137, -138). A fresh grep of `contracts/` for `EntropyLib\.entropyStep` at HEAD `7ab515fe` (excluding the single doc-comment line at `DegenerusGameJackpotModule.sol:43` which is a `*` NatSpec line, not a call site) yields EXACTLY 8 actual call sites: `LootboxModule:813, :817, :1548, :1569, :1585, :1599, :1635` + `JackpotModule:2119`. Set-equal match with Phase 237 inventory's 8-row EXC-04 subset at HEAD `7ab515fe`. NO delta.

### Section-Level Verdict

**`EXC-04 RE_VERIFIED_AT_HEAD`** — both EXC-04-P1a (EntropyLib.entropyStep XOR-shift body intact at `contracts/libraries/EntropyLib.sol:16-23` — signature `function entropyStep(uint256 state) internal pure returns (uint256)` + body `state ^= state << 7; state ^= state >> 9; state ^= state << 8;` inside `unchecked` block; ZERO keccak inside body) AND EXC-04-P1b (all 8 `EntropyLib.entropyStep` call sites receive state pre-derived from caller-site `keccak256(abi.encode(rngWord, ...))` constructions whose `rngWord` is VRF-sourced via `rawFulfillRandomWords:1690` / `_applyDailyRng:1786` / `_backfillGapDays:1738`; no new non-VRF entry point) hold. No EXC-04 forward-cite discharge rows added to § 8 — Phase 240 emitted none (Phase 240 scope = gameover-VRF-available branch).

### Cross-Cites (per D-12, corroborating only)

- **CITE Phase 238-03 `audit/v30-FREEZE-PROOF.md` `lootbox-index-advance` Named Gate** — `re-verified at HEAD 7ab515fe`. Structural equivalence statement: Phase 238-03's Named Gate distribution assigns all 8 EXC-04 rows (INV-237-124, -131, -132, -134..138) to the `lootbox-index-advance` gate, corroborating the per-call-site VRF source freezing inside the mid-day lootbox index-advance window; contract tree + Named Gate assignment unchanged at HEAD.
- **CITE Phase 239-03 `audit/v30-ASYMMETRY-RE-JUSTIFICATION.md § Asymmetry A`** — `re-verified at HEAD 7ab515fe`. Structural equivalence statement: the 6-step equivalence proof (single-writer to `lootboxRngWordByIndex` mapping + VRF-coordinator gate + private caller-chains + per-key atomicity + monotonic index advance + equivalence-to-rngLockedFlag) corroborates that `rngWord` provenance at the caller-site keccak constructions remains VRF-sourced and un-mutable between request and consumption; Asymmetry A's structural primitives unchanged at HEAD.

## 8. Forward-Cite Discharge Ledger

Per D-11 — explicit line-item discharge of the 29 cross-phase forward-cite tokens Phase 240 emitted expecting Phase 241 closure (17 `See Phase 241 EXC-02` + 12 `See Phase 241 EXC-03`). Ledger columns: `EXC-241-NNN | Forward-Cite Source (Phase 240 file:line token) | Phase 240 Source Row ID | Phase 241 Discharging Row/Predicate | Discharge Verdict | Predicate Used`.

Grep confirms 17 EXC-02 tokens + 12 EXC-03 tokens at HEAD `7ab515fe` in `audit/v30-GAMEOVER-JACKPOT-SAFETY.md` (commands preserved in § 4 reproducibility block — re-runnable as `grep -c 'See Phase 241 EXC-02' audit/v30-GAMEOVER-JACKPOT-SAFETY.md` = 17 and `grep -c 'See Phase 241 EXC-03' audit/v30-GAMEOVER-JACKPOT-SAFETY.md` = 12).

### 8a. EXC-02 Forward-Cite Discharges (17 rows)

Each discharge row closes a single `See Phase 241 EXC-02` token via the two-predicate combination **EXC-02-P1 (single-call-site) + EXC-02-P2 (14-day gate)** both re-verified at HEAD `7ab515fe` in § 5 above.

| EXC-241-NNN | Forward-Cite Source (Phase 240 file:line token) | Phase 240 Source Row ID | Phase 241 Discharging Row/Predicate | Discharge Verdict | Predicate Used |
| ----------- | ----------------------------------------------- | ---------------------- | ----------------------------------- | ----------------- | -------------- |
| EXC-241-023 | `audit/v30-GAMEOVER-JACKPOT-SAFETY.md:163` (GO-02 table-header meta-token) | GO-02 section-summary (covers GO-240-008..015) | EXC-02-P1 + EXC-02-P2 | DISCHARGED_RE_VERIFIED_AT_HEAD | Fallback reachable only inside `_gameOverEntropy:1252` + 14-day delay enforced at `:109/:1250` — both predicates hold at HEAD 7ab515fe |
| EXC-241-024 | `audit/v30-GAMEOVER-JACKPOT-SAFETY.md:180` (GO-240-008 row forward-cite) | GO-240-008 (`_gameOverEntropy` historical fallback call) — consumer at `AdvanceModule:1252` (INV-237-055) | EXC-02-P1 + EXC-02-P2 | DISCHARGED_RE_VERIFIED_AT_HEAD | Single call-site at `:1252` confirmed sole caller; 14-day gate at `:1250` guards this exact path — both predicates hold at HEAD 7ab515fe |
| EXC-241-025 | `audit/v30-GAMEOVER-JACKPOT-SAFETY.md:181` (GO-240-009 row forward-cite) | GO-240-009 (`_gameOverEntropy` fallback apply) — consumer at `AdvanceModule:1253` (INV-237-056) | EXC-02-P1 + EXC-02-P2 | DISCHARGED_RE_VERIFIED_AT_HEAD | `_applyDailyRng(day, fallbackWord)` consumes post-gate fallback word only; path reachable only via `:1252` call — both predicates hold at HEAD 7ab515fe |
| EXC-241-026 | `audit/v30-GAMEOVER-JACKPOT-SAFETY.md:182` (GO-240-010 row forward-cite) | GO-240-010 (`_gameOverEntropy` fallback coinflip) — consumer at `AdvanceModule:1257` (INV-237-057) | EXC-02-P1 + EXC-02-P2 | DISCHARGED_RE_VERIFIED_AT_HEAD | `processCoinflipPayouts(fallbackWord)` reachable only through `:1252` → post-14-day-gate branch — both predicates hold at HEAD 7ab515fe |
| EXC-241-027 | `audit/v30-GAMEOVER-JACKPOT-SAFETY.md:183` (GO-240-011 row forward-cite) | GO-240-011 (`_gameOverEntropy` fallback redemption roll) — consumer at `AdvanceModule:1268` (INV-237-058) | EXC-02-P1 + EXC-02-P2 | DISCHARGED_RE_VERIFIED_AT_HEAD | Redemption roll `((fallbackWord >> 8) % 151) + 25` reachable only through `:1252` → post-14-day-gate branch — both predicates hold at HEAD 7ab515fe |
| EXC-241-028 | `audit/v30-GAMEOVER-JACKPOT-SAFETY.md:184` (GO-240-012 row forward-cite) | GO-240-012 (`_gameOverEntropy` fallback lootbox finalize) — consumer at `AdvanceModule:1274` (INV-237-059) | EXC-02-P1 + EXC-02-P2 | DISCHARGED_RE_VERIFIED_AT_HEAD | `_finalizeLootboxRng(fallbackWord)` reachable only through `:1252` → post-14-day-gate branch — both predicates hold at HEAD 7ab515fe |
| EXC-241-029 | `audit/v30-GAMEOVER-JACKPOT-SAFETY.md:185` (GO-240-013 row forward-cite) | GO-240-013 (`_getHistoricalRngFallback` historical SLOAD) — consumer at `AdvanceModule:1308` (INV-237-060) | EXC-02-P1 + EXC-02-P2 | DISCHARGED_RE_VERIFIED_AT_HEAD | Historical-word SLOAD inside `_getHistoricalRngFallback` body; function reachable only via sole caller `:1252` gated by `:1250` 14-day check — both predicates hold at HEAD 7ab515fe |
| EXC-241-030 | `audit/v30-GAMEOVER-JACKPOT-SAFETY.md:186` (GO-240-014 row forward-cite) | GO-240-014 (`_getHistoricalRngFallback` combined keccak) — consumer at `AdvanceModule:1310` (INV-237-061) | EXC-02-P1 + EXC-02-P2 | DISCHARGED_RE_VERIFIED_AT_HEAD | Cumulative keccak `combined = keccak(combined, w)` inside fallback body; same caller + gate constraints — both predicates hold at HEAD 7ab515fe |
| EXC-241-031 | `audit/v30-GAMEOVER-JACKPOT-SAFETY.md:187` (GO-240-015 row forward-cite) | GO-240-015 (`_getHistoricalRngFallback` prevrandao mix) — consumer at `AdvanceModule:1322` (INV-237-062) | EXC-02-P1 + EXC-02-P2 | DISCHARGED_RE_VERIFIED_AT_HEAD | Final `keccak256(abi.encodePacked(combined, currentDay, block.prevrandao))` prevrandao mix inside fallback body; same caller + gate constraints + 1-bit validator proposer bias KI-accepted — both predicates hold at HEAD 7ab515fe |
| EXC-241-032 | `audit/v30-GAMEOVER-JACKPOT-SAFETY.md:195` (forward-cite-count attestation meta-token) | GO-02 attestation line (covers GO-240-008..015) | EXC-02-P1 + EXC-02-P2 | DISCHARGED_RE_VERIFIED_AT_HEAD | Attestation-level meta-token; closure flows from per-row discharge of GO-240-008..015 above — both predicates hold at HEAD 7ab515fe |
| EXC-241-033 | `audit/v30-GAMEOVER-JACKPOT-SAFETY.md:211` (GO-02 validator-column narrative) | GO-02 section narrative — validator closure on VRF-available branch routing to EXC-02 fallback | EXC-02-P1 + EXC-02-P2 | DISCHARGED_RE_VERIFIED_AT_HEAD | Validator withholding ≥14 days routes to EXC-02 prevrandao fallback; 14-day gate at `:109/:1250` + single caller at `:1252` — both predicates hold at HEAD 7ab515fe |
| EXC-241-034 | `audit/v30-GAMEOVER-JACKPOT-SAFETY.md:308` (GO-04 Non-Player Narrative meta-token) | GO-04 Non-Player Narrative (validator + VRF-oracle) section-summary | EXC-02-P1 + EXC-02-P2 | DISCHARGED_RE_VERIFIED_AT_HEAD | Non-player actor narrative closure; both validator and VRF-oracle closed verdicts route to EXC-02 fallback via same 14-day gate — both predicates hold at HEAD 7ab515fe |
| EXC-241-035 | `audit/v30-GAMEOVER-JACKPOT-SAFETY.md:354` (GO-04 Validator closed verdict `BOUNDED_BY_14DAY_EXC02_FALLBACK`) | GO-04 Validator narrative row (`GOTRIG-240-NNN` validator-column cross-cite) | EXC-02-P1 + EXC-02-P2 | DISCHARGED_RE_VERIFIED_AT_HEAD | `BOUNDED_BY_14DAY_EXC02_FALLBACK` bounded by the 14-day `GAMEOVER_RNG_FALLBACK_DELAY` constant at `:109` — both predicates hold at HEAD 7ab515fe |
| EXC-241-036 | `audit/v30-GAMEOVER-JACKPOT-SAFETY.md:364` (GO-04 VRF-oracle closed verdict `EXC-02_FALLBACK_ACCEPTED`) | GO-04 VRF-oracle narrative row | EXC-02-P1 + EXC-02-P2 | DISCHARGED_RE_VERIFIED_AT_HEAD | `EXC-02_FALLBACK_ACCEPTED` — VRF-oracle withholding ≥14 days routes to `_getHistoricalRngFallback:1301-1325` via sole caller `:1252` — both predicates hold at HEAD 7ab515fe |
| EXC-241-037 | `audit/v30-GAMEOVER-JACKPOT-SAFETY.md:567` (meta-token in per-D-22 consolidation summary) | Consolidation-file D-22 meta-line (covers GO-02 prevrandao 8 rows + GO-04 non-player narrative 2 additional cites) | EXC-02-P1 + EXC-02-P2 | DISCHARGED_RE_VERIFIED_AT_HEAD | Summary-level meta-token; closure flows from per-row discharges EXC-241-024..031 + narrative discharges EXC-241-033..036 — both predicates hold at HEAD 7ab515fe |
| EXC-241-038 | `audit/v30-GAMEOVER-JACKPOT-SAFETY.md:702` (GO-03 GOVAR `Role` forward-cite — validator + VRF-oracle narrative attribution) | GO-03 `Role` metadata line (attributes 2 forward-cite tokens for `GOVAR-240-004`/`-028` surface) | EXC-02-P1 + EXC-02-P2 | DISCHARGED_RE_VERIFIED_AT_HEAD | GO-03 per-variable attribution of validator + VRF-oracle narratives to `rngRequestTime` / `GAMEOVER_RNG_FALLBACK_DELAY`; closure flows from 14-day gate at `:109/:1250` — both predicates hold at HEAD 7ab515fe |
| EXC-241-039 | `audit/v30-GAMEOVER-JACKPOT-SAFETY.md:822` (attestation-counter meta-token for `See Phase 241 EXC-02`) | Consolidation-file attestation-counter line (enumerates 8 + 6 = 14+ EXC-02 tokens across consolidated file) | EXC-02-P1 + EXC-02-P2 | DISCHARGED_RE_VERIFIED_AT_HEAD | Attestation-counter meta-token; closure flows from aggregate per-row and narrative discharges above — both predicates hold at HEAD 7ab515fe |

### 8b. EXC-03 Forward-Cite Discharges (12 rows)

Each discharge row closes a single `See Phase 241 EXC-03` token via the tri-gate combination **EXC-03-P1 (terminal-state) + EXC-03-P2 (no-player-reachable-timing) + EXC-03-P3 (buffer-scope)** all re-verified at HEAD `7ab515fe` in § 6 above.

| EXC-241-NNN | Forward-Cite Source (Phase 240 file:line token) | Phase 240 Source Row ID | Phase 241 Discharging Row/Predicate | Discharge Verdict | Predicate Used |
| ----------- | ----------------------------------------------- | ---------------------- | ----------------------------------- | ----------------- | -------------- |
| EXC-241-040 | `audit/v30-GAMEOVER-JACKPOT-SAFETY.md:163` (GO-02 table-header meta-token) | GO-02 section-summary (covers GO-240-016..019) | EXC-03-P1 + EXC-03-P2 + EXC-03-P3 | DISCHARGED_RE_VERIFIED_AT_HEAD | Terminal-state only via `_gameOverEntropy:1222-1246`; no player-reachable trigger timing (Phase 240 GO-04 DISPROVEN_PLAYER_REACHABLE_VECTOR); buffer scope bounded to post-swap primitives at `:292, :1082` (Phase 240 GO-05 BOTH_DISJOINT) — all three predicates hold at HEAD 7ab515fe |
| EXC-241-041 | `audit/v30-GAMEOVER-JACKPOT-SAFETY.md:188` (GO-240-016 row forward-cite) | GO-240-016 (`advanceGame` ticket-buffer swap pre-daily VRF) — consumer at `AdvanceModule:292` (INV-237-024) | EXC-03-P1 + EXC-03-P2 + EXC-03-P3 | DISCHARGED_RE_VERIFIED_AT_HEAD | `_swapAndFreeze(purchaseLevel)` buffer primitive at `:292` unchanged; terminal-state-only + no-player-reachable-timing + buffer-scope — all three predicates hold at HEAD 7ab515fe |
| EXC-241-042 | `audit/v30-GAMEOVER-JACKPOT-SAFETY.md:189` (GO-240-017 row forward-cite) | GO-240-017 (`requestLootboxRng` ticket-buffer swap pre-midday VRF) — consumer at `AdvanceModule:1082` (INV-237-045) | EXC-03-P1 + EXC-03-P2 + EXC-03-P3 | DISCHARGED_RE_VERIFIED_AT_HEAD | `_swapTicketSlot(purchaseLevel_)` buffer primitive at `:1082` unchanged (preceding the VRF request at `:1088`); terminal-state-only + no-player-reachable-timing + buffer-scope — all three predicates hold at HEAD 7ab515fe |
| EXC-241-043 | `audit/v30-GAMEOVER-JACKPOT-SAFETY.md:190` (GO-240-018 row forward-cite) | GO-240-018 (`_gameOverEntropy` fresh VRF word) — consumer at `AdvanceModule:1221-1223` (INV-237-053) | EXC-03-P1 + EXC-03-P2 + EXC-03-P3 | DISCHARGED_RE_VERIFIED_AT_HEAD | `_gameOverEntropy` substitution block at `:1222-1246` reachable only via `advanceGame:553` single caller; terminal-state + no-player-timing + buffer-scope — all three predicates hold at HEAD 7ab515fe |
| EXC-241-044 | `audit/v30-GAMEOVER-JACKPOT-SAFETY.md:191` (GO-240-019 row forward-cite) | GO-240-019 (`_gameOverEntropy` consumer cluster) — consumer at `AdvanceModule:1222-1246` (INV-237-054) | EXC-03-P1 + EXC-03-P2 + EXC-03-P3 | DISCHARGED_RE_VERIFIED_AT_HEAD | `_gameOverEntropy` block covering coinflip `:1225` + redemption-roll `:1237-1239` + `_finalizeLootboxRng` `:1244` — same gameover-terminal-state envelope; all three predicates hold at HEAD 7ab515fe |
| EXC-241-045 | `audit/v30-GAMEOVER-JACKPOT-SAFETY.md:195` (forward-cite-count attestation meta-token) | GO-02 attestation line (covers GO-240-016..019) | EXC-03-P1 + EXC-03-P2 + EXC-03-P3 | DISCHARGED_RE_VERIFIED_AT_HEAD | Attestation-level meta-token; closure flows from per-row discharge of GO-240-016..019 above — all three predicates hold at HEAD 7ab515fe |
| EXC-241-046 | `audit/v30-GAMEOVER-JACKPOT-SAFETY.md:217` (GO-02 validator-closure narrative — F-29-04 acceptance attribution) | GO-02 section narrative — validator column closure on F-29-04 substitution surface | EXC-03-P1 + EXC-03-P2 + EXC-03-P3 | DISCHARGED_RE_VERIFIED_AT_HEAD | Validator block-reordering cannot split a tx; terminal-state + write-buffer-swap atomicity; Phase 239-03 § Asymmetry B single-threaded-EVM argument (cross-cite) — all three predicates hold at HEAD 7ab515fe |
| EXC-241-047 | `audit/v30-GAMEOVER-JACKPOT-SAFETY.md:378` (GO-05 D-19 forward-cite: F-29-04 acceptance + containment-only) | GO-05 forward-cite-per-D-19 section token | EXC-03-P1 + EXC-03-P2 + EXC-03-P3 | DISCHARGED_RE_VERIFIED_AT_HEAD | GO-05 BOTH_DISJOINT proves scope-containment only; Phase 241 EXC-03 owns F-29-04 acceptance re-verification via tri-gate — all three predicates hold at HEAD 7ab515fe |
| EXC-241-048 | `audit/v30-GAMEOVER-JACKPOT-SAFETY.md:534` (GO-05 containment-only forward-cite) | GO-05 containment-only forward-cite (F-29-04 acceptance handoff) | EXC-03-P1 + EXC-03-P2 + EXC-03-P3 | DISCHARGED_RE_VERIFIED_AT_HEAD | Containment-only handoff discharged by EXC-03 tri-gate — all three predicates hold at HEAD 7ab515fe |
| EXC-241-049 | `audit/v30-GAMEOVER-JACKPOT-SAFETY.md:551` (GO-05 D-19 strict-boundary forward-cite) | GO-05 D-19 strict-boundary line | EXC-03-P1 + EXC-03-P2 + EXC-03-P3 | DISCHARGED_RE_VERIFIED_AT_HEAD | D-19 strict boundary: Phase 240 proves containment; Phase 241 EXC-03 owns acceptance via tri-gate — all three predicates hold at HEAD 7ab515fe |
| EXC-241-050 | `audit/v30-GAMEOVER-JACKPOT-SAFETY.md:567` (meta-token in per-D-22 consolidation summary for EXC-03) | Consolidation-file D-22 meta-line (covers 4 GO-02 F-29-04 rows + GO-05 containment forward-cite) | EXC-03-P1 + EXC-03-P2 + EXC-03-P3 | DISCHARGED_RE_VERIFIED_AT_HEAD | Summary-level meta-token; closure flows from per-row discharges EXC-241-041..044 + containment discharges EXC-241-047..049 — all three predicates hold at HEAD 7ab515fe |
| EXC-241-051 | `audit/v30-GAMEOVER-JACKPOT-SAFETY.md:823` (attestation-counter meta-token for `See Phase 241 EXC-03`) | Consolidation-file attestation-counter line (enumerates 4 + 1 = 5+ EXC-03 tokens across consolidated file) | EXC-03-P1 + EXC-03-P2 + EXC-03-P3 | DISCHARGED_RE_VERIFIED_AT_HEAD | Attestation-counter meta-token; closure flows from aggregate per-row and narrative discharges above — all three predicates hold at HEAD 7ab515fe |

## 9. Prior-Artifact Cross-Cites

Per D-12/D-13 — every cross-cite carries a `re-verified at HEAD 7ab515fe` backtick-quoted note with a one-line structural-equivalence statement. Cross-cites are CORROBORATING CONTEMPORANEOUS EVIDENCE, not sole warrants — Phase 241 verdicts are all re-derived fresh at HEAD.

| Artifact | Role | Structural Equivalence at HEAD |
| -------- | ---- | ------------------------------ |
| `audit/v30-CONSUMER-INVENTORY.md` (Phase 237) | Source of 146-row Consumer Index + 22-EXCEPTION distribution used as Gate A target | `re-verified at HEAD 7ab515fe` — 22 EXCEPTION rows (INV-237-005, -006, -024, -045, -053..062, -124, -131, -132, -134..138) distribute across 4 KI groups (2/8/4/8) unchanged at HEAD; contract tree identical to v29.0 `1646d5af`. |
| `audit/v30-FREEZE-PROOF.md` (Phase 238) | Gate A set-equality cross-check — 22 EXCEPTION / 124 SAFE distribution | `re-verified at HEAD 7ab515fe` — the 22-EXCEPTION set in Phase 238's Consolidated Freeze-Proof Table matches row-for-row the 22-row set in § 3 above; Named Gate distribution (rngLocked=106 / lootbox-index-advance=20 / semantic-path-gate=18 / NO_GATE_NEEDED_ORTHOGONAL=2) unchanged. |
| `audit/v30-RNGLOCK-STATE-MACHINE.md` (Phase 239 RNG-01 AIRTIGHT) | Corroborates EXC-02 reachability closure for gameover-entry paths | `re-verified at HEAD 7ab515fe` — 1 Set-Site `AdvanceModule:1579` + 3 Clear-Sites + 9 Path Enumeration rows unchanged; `rngLockedFlag` state machine airtight; gameover-entry paths into `_gameOverEntropy` gated. |
| `audit/v30-PERMISSIONLESS-SWEEP.md` (Phase 239 RNG-02) | Corroborates no-permissionless-path-touches-RNG-state baseline | `re-verified at HEAD 7ab515fe` — 62-row Permissionless Sweep Table distribution (respects-rngLocked=24 / respects-equivalent-isolation=0 / proven-orthogonal=38 / CANDIDATE_FINDING=0) unchanged; no permissionless function touches RNG-consumer state outside the 3-class taxonomy. |
| `audit/v30-ASYMMETRY-RE-JUSTIFICATION.md § Asymmetry A` (Phase 239 RNG-03) | Corroborates EXC-04 `rngWord` source freezing inside lootbox index-advance window | `re-verified at HEAD 7ab515fe` — 6-step equivalence proof (single-writer to `lootboxRngWordByIndex` mapping + VRF-coordinator gate + private caller-chains + per-key atomicity + monotonic index advance + equivalence-to-rngLockedFlag) unchanged; storage primitives at `GameStorage.sol:1290, :1296-1297, :1315-1322, :1345` unchanged. |
| `audit/v30-GAMEOVER-JACKPOT-SAFETY.md` (Phase 240) | Source of 29 forward-cite tokens + GO-04 + GO-05 corroborating EXC-02/EXC-03 | `re-verified at HEAD 7ab515fe` — 838-line consolidated deliverable contains exactly 17 `See Phase 241 EXC-02` + 12 `See Phase 241 EXC-03` tokens (grep-counted), each discharged line-item in § 8; GO-04 2 `DISPROVEN_PLAYER_REACHABLE_VECTOR` rows + GO-05 `BOTH_DISJOINT` verdict unchanged. |
| `audit/FINAL-FINDINGS-REPORT.md` (v29.0 F-29-04 prior-milestone) | v29.0 F-29-04 entry as contemporaneous corroborating artifact for EXC-03 subject | `re-verified at HEAD 7ab515fe` — v29.0 `1646d5af` F-29-04 "Gameover RNG substitution for mid-cycle write-buffer tickets" entry's scope (terminal-state + no-player-timing + buffer-scope) matches Phase 241 § 6 tri-gate; contract tree unchanged since v29.0. |
| `KNOWN-ISSUES.md` (4 KI RNG entries) | SUBJECTS of Phase 241 re-verification, NOT warrants per D-12 | `re-verified at HEAD 7ab515fe` — the 4 KI entries (Affiliate / Prevrandao fallback / F-29-04 / EntropyLib XOR-shift) remain the acceptance envelopes whose scope boundaries are the re-verification target; content of `KNOWN-ISSUES.md` unmodified by Phase 241 per D-26. |

**Per D-19:** prior-milestone cross-cites above are CORROBORATING CONTEMPORANEOUS EVIDENCE, not regression verdicts. Regression verdicts (PASS/REGRESSED/SUPERSEDED) against prior-milestone findings are Phase 242 REG-01/REG-02 territory — not this phase.

## 10. Finding Candidates + Scope-Guard Deferrals + Attestation

### 10a. Finding Candidates (Phase 242 FIND-01 intake)

**None surfaced.** No row in § 3 / § 4 / § 5 / § 6 / § 7 / § 8a / § 8b carries verdict `CANDIDATE_FINDING`. The universal ONLY-ness claim holds (`ONLY_NESS_HOLDS_AT_HEAD`), all three predicate re-verifications pass (`EXC-02`/`EXC-03`/`EXC-04 RE_VERIFIED_AT_HEAD`), and all 29 Phase 240 forward-cite tokens are discharged (`DISCHARGED_RE_VERIFIED_AT_HEAD`). Per D-20 no v30.0-series finding identifiers emitted; Phase 242 FIND-01 intake from this plan is empty.

### 10b. Scope-Guard Deferrals

**None surfaced.** No consumer outside Phase 237's 146-row inventory was surfaced. No non-VRF seed surface absent from Phase 237's 22-EXCEPTION set was surfaced. The fresh grep of `EntropyLib\.entropyStep` at HEAD `7ab515fe` (excluding the single NatSpec doc-comment at `DegenerusGameJackpotModule.sol:43`) yielded exactly 8 actual call sites — set-equal with Phase 237's 8 EXC-04 rows (INV-237-124, -131, -132, -134..138). Zero delta; zero scope-guard deferral.

Per D-28: Phase 241 does NOT discharge any Phase 239 RNG-01/RNG-03 audit assumption beyond the Forward-Cite Discharge Ledger. No such additional discharge claim exists in this plan.

### 10c. Attestation

This deliverable attests that:

1. **Every verdict was derived fresh at HEAD `7ab515fe`** per D-12 fresh-re-prove discipline — Phase 237/238/239/240 cross-cites are corroborating only, never sole warrant; the contract tree at HEAD is identical to v29.0 `1646d5af` per PROJECT.md, and all re-verification predicates were re-derived directly from storage primitives, function signatures, and gate expressions inspected at HEAD.
2. **Zero writes to `contracts/` or `test/`** — `git status --porcelain contracts/ test/` empty at every task boundary; `git diff 7ab515fe -- contracts/` empty (D-25 HEAD-anchor freeze honoured).
3. **Phase 237/238/239/240 outputs unmodified** — `git status --porcelain` on `audit/v30-CONSUMER-INVENTORY.md`, `audit/v30-FREEZE-PROOF.md`, `audit/v30-RNGLOCK-STATE-MACHINE.md`, `audit/v30-PERMISSIONLESS-SWEEP.md`, `audit/v30-ASYMMETRY-RE-JUSTIFICATION.md`, `audit/v30-GAMEOVER-JACKPOT-SAFETY.md`, `audit/v30-240-01-INV-DET.md`, `audit/v30-240-02-STATE-TIMING.md`, `audit/v30-240-03-SCOPE.md` all empty (D-27 READ-only-after-commit).
4. **`KNOWN-ISSUES.md` untouched** per D-26 — KI promotions are Phase 242 FIND-03 territory, not Phase 241.
5. **Zero v30.0-series finding IDs emitted** per D-20 — file-wide grep for the `[prefix-char] dash 30 dash` finding-ID pattern yields 0 hits in `audit/v30-EXCEPTION-CLOSURE.md`; finding-ID promotion is Phase 242 FIND-01/FIND-02/FIND-03 territory.
6. **All 29 Phase 240 forward-cite tokens addressed** in § 8 Forward-Cite Discharge Ledger per D-11 — 17 EXC-02 + 12 EXC-03 line-item discharges with literal verdict string `DISCHARGED_RE_VERIFIED_AT_HEAD` on every row; zero residual undischarged tokens.

**ROADMAP Phase 241 Success Criteria closure:** SC-1 (EXC-01 ONLY-ness) closed by § 3 + § 4 + Gate A ∧ Gate B → `ONLY_NESS_HOLDS_AT_HEAD`; SC-2 (EXC-02 trigger-gating) closed by § 5 two-predicate + § 8a 17-row discharge → `EXC-02 RE_VERIFIED_AT_HEAD`; SC-3 (EXC-03 F-29-04 scope) closed by § 6 tri-gate + § 8b 12-row discharge → `EXC-03 RE_VERIFIED_AT_HEAD`; SC-4 (EXC-04 EntropyLib keccak seed) closed by § 7 two-part predicate + 8-row Call-Site Inventory → `EXC-04 RE_VERIFIED_AT_HEAD`.

Ready for Phase 242 FIND-01 intake (pool: 0 Phase 241 candidates + prior-phase candidates accumulated from 237/238/239/240).

