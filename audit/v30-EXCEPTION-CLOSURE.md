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
