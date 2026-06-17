# 389-FINDINGS — PACKING-IDENTITY adjudication (STORAGE-01..07 + GASID-01..05 + FC-389-01..09)

**Subject (byte-frozen):** `a8b702a7` (contracts tree `2934d3d8987a09c5f073549a0cb499f6c5f28620`;
`git diff a8b702a7 -- contracts/` EMPTY before and after every task in this plan).
**Baseline (the audit oracle):** `test/REGRESSION-BASELINE-v63.md` — forge **854 / 0 / 110**, the
expected forge-failure NAME-set is strictly EMPTY (a regression is any failing name at this subject).
**Method:** COUNCIL + CLAUDE both (AUDIT-V63-PLAN §2 — a no-finding verdict for any slice requires
BOTH nets on record). NET 1 = the cross-model council (gemini + codex via council.sh), captured in
`389-01-COUNCIL-NET.md` + `council/*.txt`. NET 2 = the deep Claude adversarial net, captured in
`389-02-CLAUDE-NET.md` (run independently, leads folded after).
**Posture:** AUDIT-ONLY. A CONFIRMED finding is DOCUMENTED and ROUTED to a SEPARATE gated USER-hand-
review boundary — never fixed, never auto-committed in this phase. The subject stays byte-frozen and
re-freezes only after a gated fix boundary.
**Threat weighting (AUDIT-V63-PLAN §4, USER-locked):** DOMINANT = RNG/freeze · HIGH = gas-DoS only in
the advanceGame chain · SPINE = solvency · LOW/confirmatory = access-control + reentrancy + MEV.
**Design-intent anchor (§5):** verify identity/safety, do NOT re-litigate documented intended
mechanics (EV-multiplier lift, recycle relaxation, EV-neutral redistributions, the by-design rulings).

---

## 1. Both-nets-on-record attestation (per slice)

A no-finding (REFUTED / BY-DESIGN) verdict for any item below cites BOTH nets.

| Slice | NET 1 (council) | NET 2 (Claude) | both on record? |
|-------|-----------------|----------------|-----------------|
| STORAGE (STORAGE-01..07 + FC-389-01..04) | `389-01-COUNCIL-NET.md` + `council/storage.{gemini,codex}.txt` — both CLIs available, 0 skipped; aggregate = no production packing defect, 2 STORAGE-06 stale-harness leads + the FC-389-03 framing divergence routed forward | `389-02-CLAUDE-NET.md` STORAGE section — independent attack pass + STORAGE-04 cursor-lag proof + fresh `forge inspect` slot verification of all 3 STORAGE-06 candidates | ✓ both |
| GASID (GASID-01..05 + FC-389-05..09) | `389-01-COUNCIL-NET.md` + `council/gasid.{gemini,codex}.txt` — both CLIs available, 0 skipped; aggregate = no findings, full 30-row selector table + PriceLookup 0-mismatch recompute | `389-02-CLAUDE-NET.md` GASID section — independent attack pass + operand-width / preimage / nibble-table / trait-roll equivalence | ✓ both |

T-389-05 (a no-finding verdict issued with only one net) does not apply: both nets are on record for
both slices. T-389-04 (subject tampering) mitigation: `git diff a8b702a7 -- contracts/` EMPTY
throughout (the council ran read-only `--approval-mode plan`; NET 2 ran `forge clean/build/inspect`
without touching contract source — hardhat never invoked, landmine guarded).

---

## 2. Per-item adjudication table

Verdicts: **REFUTED** (claim attacked, holds) · **BY-DESIGN** (intended, sound) · **MONITOR** (no
defect, carried-forward observation) · **CONFIRMED** (a real defect — routed in §4). All 12 reqs + 9
leads carry one row.

### 2a. STORAGE requirements (STORAGE-01..07)

| ITEM | What it claims | NET 1 | NET 2 | VERDICT | Settling bound / cite (`a8b702a7`) |
|------|----------------|-------|-------|---------|-------------------------------------|
| **STORAGE-01** | every narrowing width ≥ real-world max (no silent truncation) | SOUND | REFUTED | **REFUTED** | EV used clamped 1e19 ≪ 2^64 (DegenerusGameStorage.sol:1686); DGNRS halves ≤ sDGNRS supply ~1e30 ≪ uint128 (:1132); poolWei real-ETH ≪ uint96 (:1760); sDGNRS `_totalSupply` 1e30 monotone ≪ uint128 (StakedDegenerusStonk.sol:213). Each cast enumerated with its bound in 389-02 §STORAGE-01. |
| **STORAGE-02** | masked RMW helpers preserve co-residents (round-trip) | SOUND | REFUTED | **REFUTED** | `_setLootboxEvUsedFor` `_EV_WINDOW_{A,B}_MASK` clears exactly its 88 bits (:1709-1738); `_setLevelDgnrsAllocation`/`_addLevelDgnrsClaimed` preserve the sibling 128-half (:1148/:1158); `_debitClaimableAndAfking` per-half guards (:956). Round-trip property argued by mask construction + green `RngLockDeterminism`/`RedemptionAccounting` pokes. |
| **STORAGE-03** | cross-module shift/mask conventions agree | SOUND | REFUTED | **REFUTED** | All 13 modules + Game inherit one `DegenerusGameStorage` (slots agree by construction); the 2 cross-module-read packs use identical decode — `deityBoonPacked` Game:884 + Lootbox:1146; `levelDgnrsPacked` single-sourced helpers. |
| **STORAGE-04** | two-window EV-cap never evicts a live key under cursor lag (10 ETH cap not re-earnable) | SOUND | REFUTED (cursor-lag proof) | **REFUTED** | Live key set ⊆ {currentLevel, currentLevel+1} PROVEN: (a) deferred human `openBoxes` writes NO cap — "the cap was drawn at deposit" (DegenerusGameLootboxModule.sol:567-579); (b) every cap write keys live `level+1` (deposits Mint:1685/1706, Whale:852, Afking:970; resolves :877/:966/:1089 read live `level`); (c) `level` is +1-monotone, sole writer advanceGame (DegenerusGameAdvanceModule.sol:1701-1709). Eviction discards only the smaller/dead key (:1727). No third live key reachable. |
| **STORAGE-05** | ABI getters preserved for privatized/packed fields | SOUND | REFUTED | **REFUTED** | sDGNRS `totalSupply()` uint256 (StakedDegenerusStonk.sol:513), `pendingRedemptionEthValue()` :518, `pendingResolveDay()` :524, `poolBalance()` :509; Admin votes/voteWeight/feedVotes/feedVoteWeight re-exposed. No interface break. |
| **STORAGE-06** | no harness hardcodes a moved slot | gemini SOUND (active harnesses clean aside from known RedemptionInvariants); codex 3 leads | 2 of 3 candidates CONFIRMED stale, 1 REFUTED | **CONFIRMED (oracle-integrity, LOW)** | vs fresh `forge inspect`: (1) Composition `MINT_PACKED_SLOT=10` reads `keccak(player,10)` but `mintPacked_` is slot **9** (10 = `rngWordByDay`) → vacuous canary (CompositionHandler.sol:37/:210); (3) HeroOverride JS `LOOTBOX_RNG_PACKED_SLOT=35` seeds slot 35 but `lootboxRngPacked` is slot **34** (35 = `lootboxRngWordByIndex` root) → seeding no-ops (HeroOverrideDayIndex.test.js:62; HeroOverrideWeightedRoll.test.js:202). Candidate (2) box-cursor 58/59 REFUTED — `boxCursor`@58 off7, `boxCursorIndex`@58 off13, `boxPlayers`@59 ⇒ harnesses CORRECT. Routed §4 (R-389-01). |
| **STORAGE-07** | capBucketCounts ≤ maxTotal+4 imprecision defended/tightened | DEFENDED (250-clamp + remainder share) | REFUTED as overflow (≤ maxTotal by trim/remainder) | **REFUTED** | Trim loop (JackpotBucketLib.sol:166-183) clears the ≤3 min-1 bumps; remainder loop (:186-202) never overshoots `nonSoloCap` ⇒ Σ capped ≤ maxTotal. Double-defended: `_processBucket` 250-clamp (DegenerusGameJackpotModule.sol:1141-1152) + `bucketShares` remainder = `pool-distributed` (:214-240). The "+4" is a TEST-slack constant (`204a91bb`), NOT a contract property (`capBucketCounts` byte-identical to baseline). |

### 2b. GASID requirements (GASID-01..05)

| ITEM | What it claims | NET 1 | NET 2 | VERDICT | Settling bound / cite (`a8b702a7`) |
|------|----------------|-------|-------|---------|-------------------------------------|
| **GASID-01** | `delegatecall(msg.data)` resolves the same selector + ABI-decodes identically | IDENTICAL (full 30-row selector table) | REFUTED | **REFUTED** | 30 wrapper selectors == module selectors (recomputed both nets, e.g. advanceGame 0x75b5e924, rawFulfillRandomWords 0x1fe543e3); typed wrappers keep the Solidity ABI decoder (short/dirty/malformed reverts identically on entry); wrapper-resident gates preserved before delegate. |
| **GASID-02** | hash1/hash2 keccak preimages byte-identical (RNG image preserved) | IDENTICAL | REFUTED | **REFUTED** | Operand-width rule applied to every migrated site — all operands are full 32-byte types (EntropyLib.sol:23/:38); `hash2(rngWord, uint256(uint160(player)))` == `abi.encode(rngWord, player)` (address zero-pads high 12 == uint160 cast); 3-arg COIN_JACKPOT_TAG correctly NOT migrated. |
| **GASID-03** | PriceLookup nibble-table output-identical over full domain | IDENTICAL (recomputed level∈[0,99999] = 0 mismatches) | REFUTED (differential 0 mismatches) | **REFUTED** | Nibble `0x4333222111 >> ((cycleOffset/10)*4) & 0xF` reproduces decade multipliers 1/2/3/4; intro tiers + milestone preserved; `unchecked` safe (PriceLookupLib.sol:21-41). Both nets recompute 0 mismatches over the domain. |
| **GASID-04** | trait-roll consolidation + `_farFutureSeed` extraction equivalent across inputs/boundaries/reverts | IDENTICAL | REFUTED | **REFUTED** | `_rollWinningTraitsPair` rolls hero ONCE (same hero main+bonus, matching baseline `_applyHeroOverride(…,w)` 3rd arg); `rBonus = hash2(randWord, BONUS_TRAITS_TAG)` == baseline bonus r; `_rollHeroSymbol` byte-identical; `_soloAdjustedEntropy` reproduces inline; `_farFutureSeed` literal extraction (MintStreakUtils:232). |
| **GASID-05** | no externally-observable behavior change (output/revert/event) | IDENTICAL | REFUTED | **REFUTED** | Anchored on GASID-01..04 + value-identical Stage-B packs + empty expected-red name-set (REGRESSION-BASELINE-v63 854/0/110). No observable delta. |

### 2c. STORAGE leads (FC-389-01..04)

| ITEM | What it claims | NET 1 | NET 2 | VERDICT | Settling bound / cite |
|------|----------------|-------|-------|---------|-----------------------|
| **FC-389-01** | EV-cap two-window eviction under resolve-cursor lag >1 level → 10 ETH cap re-earnable | SOUND (live set {level,+1}) | REFUTED (cursor-lag proof) | **REFUTED** | Same proof as STORAGE-04: deferred opens write no cap + live `level+1` keying + `level` +1-monotone ⇒ no third live key. DegenerusGameLootboxModule.sol:567-579/:877/:966/:1089 + AdvanceModule:1701-1709. |
| **FC-389-02** | sDGNRS uint96/uint128 narrowing casts truncate silently | SOUND | REFUTED (narrowing half) | **REFUTED (cross-ref 390)** | `_pendingRedemptionEthValue` increments only post-`pullRedemptionReserve` (StakedDegenerusStonk.sol:1061-1066), capped per wallet/day; `poolBalances` conserved (:548-592). Narrowing unreachable-overflow. Solvency-conservation lens → FC-390-01/-02/-03, FC-393-03. |
| **FC-389-03** | `DecClaimRound.totalBurn` comment "effective" vs accumulator "raw" mismatch | BOTH models: accumulator stores EFFECTIVE; imprecision on `DecEntry.burn` | accumulator stores EFFECTIVE; map raw-framing is the error; `DecClaimRound.totalBurn` comment CORRECT | **BY-DESIGN bound + INFO/MONITOR** | `_recordDecimatorBurn`: `e.burn = prevBurn + effectiveAmount`, `delta = effectiveAmount` → subbucket (Decimator:178-200); round sums effective (:262-276). `DecClaimRound.totalBurn` comment is CORRECT; the imprecise comment is `DecEntry.burn` "Total BURNIE burned" (DegenerusGameStorage.sol:1748) = effective, not raw. uint128 bound holds either way. Carried as INFO (no contract change). |
| **FC-389-04** | test-harness slot recalibration (regression-oracle integrity) | covered via STORAGE-06 leads | covered via STORAGE-06 | **CONFIRMED → folds to STORAGE-06 (R-389-01)** | Same 2 stale-harness items as STORAGE-06 (Composition slot-10, HeroOverride JS slot-35) + the known legacy RedemptionInvariants hole (routed 390). LOW oracle-integrity; forge primary baseline unaffected. |

### 2d. GASID leads (FC-389-05..09)

| ITEM | What it claims | NET 1 | NET 2 | VERDICT | Settling bound / cite |
|------|----------------|-------|-------|---------|-----------------------|
| **FC-389-05** | `DecClaimRound.rngWord` uint32 narrowing (gas-half: seed-only equivalence) | SOUND (winner uses full word) | REFUTED (narrowing half) | **REFUTED (cross-ref 391)** | Winner selection on FULL VRF word (Decimator:242/:269 → decBucketOffsetPacked); narrowed rngWord = claim-time lootbox seed only, sole consumer :410 → resolveLootboxDirect (keccak-mixed with frozen inputs). Distribution-bias half → RNG-02 / FC-391-04 in 391. |
| **FC-389-06** | EV-cap level-0 stamp collision reachable if `level==0` passed | SOUND (callers pass level+1) | REFUTED | **REFUTED** | All callers key `level+1`/`cachedLevel+1`/`currentLevel+1` ≥ 1; 0.8 checked arithmetic prevents uint24 wrap to 0 (DegenerusGameLootboxModule.sol:877, MintModule:1685, WhaleModule:852, GameAfkingModule:970). Level 0 never a cap key. |
| **FC-389-07** | `_addLevelDgnrsClaimed` unclamped high-half relies on caller invariant | SOUND (pro-rata bounded) | REFUTED | **REFUTED** | `Σ claimed ≤ allocation ≤ uint128` enforced upstream: Bingo `paid ≤ reward`, pro-rata `allocation*score/totalScore`, one claim/player (BingoModule:235/:247/:263; Affiliate:692/:703); Whale/deity reserve `allocation-claimed` (WhaleModule:735/:804). `newClaimed<<128` never overflows the allocation half. |
| **FC-389-08** | StakedStonk uint96/uint128 narrowing (solvency-sweep confirm) | SOUND | REFUTED (narrowing half) | **REFUTED (cross-ref 390)** | Same surface as FC-389-02; `_totalSupply` monotone ≪ uint128, `_pendingRedemptionEthValue` capped per wallet/day × 175% ≪ uint96 (StakedDegenerusStonk.sol:213/:315/:1081). Solvency-conservation → 390. |
| **FC-389-09** | dynamic-array `msg.data` wrappers decoder-divergence corner | SOUND (module shares decoder) | REFUTED | **REFUTED** | `previewSellFarFutureTickets`/`claimAfkingBurnie`/`rawFulfillRandomWords` — wrapper + module share the typed signature, so the same ABI schema decodes the same payload; wrapper entry-decode validates bounds; no alternate non-canonical-offset interpretation. |

---

## 3. Skeptic gate (run before any CATASTROPHE/HIGH)

**Outcome: 0 items reach CATASTROPHE/HIGH. No skeptic-gate elevation triggered.** Both surface-maps
found 0 HIGH on inspection; both nets converge on no contract defect across all 21 items. The gate is
recorded for the items that carried MED-attention or a CONFIRMED tag:

| Elevated-attention item | structural-protection check | 3-condition EV lens | gate result |
|---|---|---|---|
| **FC-389-01 / STORAGE-04** (the §6 MED-attention lead) | Structurally protected: (i) deferred opens write no cap, (ii) every cap write keys live `level+1`, (iii) `level` +1-monotone — three independent structural facts each block the third-live-key precondition. | EV lens — (1) reachable? NO (no write keys a non-live level); (2) profitable if reachable? would re-earn ≤10 ETH/level cap, but precondition unreachable; (3) repeatable? n/a. | **NOT a finding** — fails condition (1). Stays REFUTED, not elevated. |
| **STORAGE-06 / FC-389-04** (CONFIRMED stale harnesses) | The defect is in TEST harnesses, not the byte-frozen contract; the forge PRIMARY baseline (854/0/110) does not depend on the two stale pokes (Composition handler is an invariant-canary that goes vacuous, not red; HeroOverride are JS edge tests in the documented Hardhat corroborating-drift family). | EV lens — n/a (no on-chain value path; oracle-integrity only). Weighting per §4: this is LOW/confirmatory (not RNG/freeze, not advanceGame gas, not solvency). | **CONFIRMED LOW (oracle-integrity), NOT HIGH.** Routed §4 R-389-01 as a test-hardening item, not a contract change. |

No item is tagged CATASTROPHE/HIGH; the skeptic gate confirms the one CONFIRMED finding is a LOW
oracle-integrity test-hardening item, and the prime MED-attention lead (FC-389-01) is structurally
unreachable (fails EV condition 1).

---

## 4. Routing — CONFIRMED findings + carried INFO/MONITOR

### 4a. CONFIRMED — ROUTED (NOT fixed here)

**R-389-01 — STORAGE-06 / FC-389-04: two stale-slot test harnesses (LOW / oracle-integrity).**

- **Finding:** Two slot-hardcoded test harnesses poke a MOVED field (outside the 388-01 §6 reconciled
  poke set), confirmed against fresh `forge inspect` at `a8b702a7`:
  1. `test/fuzz/handlers/CompositionHandler.sol` `MINT_PACKED_SLOT = 10` reads `keccak256(player, 10)`
     for the `mintPacked_` gap-bit canary, but `mintPacked_` is slot **9** (slot 10 = `rngWordByDay`)
     → the gap-bit invariant goes VACUOUS (reads the wrong mapping space; cannot catch a real
     `mintPacked_` gap-bit regression).
  2. `test/edge/HeroOverrideDayIndex.test.js` + `test/edge/HeroOverrideWeightedRoll.test.js`
     `LOOTBOX_RNG_PACKED_SLOT = 35` seed the `lootboxRngIndex` via `setStorageAt(game, 35)`, but
     `lootboxRngPacked` is slot **34** (slot 35 = `lootboxRngWordByIndex` mapping root) → the
     `seedLootboxRngIndex` write silently NO-OPs; the bet-gate-open the tests rely on
     (`DegenerusGameDegeneretteModule:451 if index==0 revert`) is not actually satisfied. The in-test
     comment ("slot index 35 … resolved via the hardhat storage-layout artifact") is also stale.
- **Weight (§4):** LOW / confirmatory (oracle-integrity). NOT RNG/freeze, NOT advanceGame gas, NOT
  solvency. The forge PRIMARY baseline (854/0/110) is unaffected (the Composition canary goes vacuous,
  not red; the HeroOverride edge tests are JS corroborating, in the documented carried-drift family).
- **Proposed fix shape (NOT applied):** TEST-ONLY recalibration — `MINT_PACKED_SLOT = 9` in
  CompositionHandler; `LOOTBOX_RNG_PACKED_SLOT = 34` in the two HeroOverride JS files (+ stale comment
  fix). NO contract source change. This is a regression-oracle hardening, not a contract defect.
- **Routing:** goes to a SEPARATE gated boundary (batched test-hardening, USER hand-review — though
  test-only edits are hands-off per the contract-commit-only-approval rule, this remains DOCUMENTED
  here and is NOT applied in this audit-only phase). The subject re-freezes unchanged (these are test
  files, not `contracts/*.sol`). Cross-ref: the legacy `RedemptionInvariants.inv.t.sol` stale-slot
  hole (388-02 ORACLE-HOLES #2, slots 10/13/15) is the third known stale harness, routed to 390.

> Note: candidate (2) (box-cursor slots 58/59 in `SweepWorstCaseDrain` + `RngLockDeterminism`) raised
> by the council was REFUTED by fresh `forge inspect` — `boxCursor`@58 off7, `boxCursorIndex`@58 off13,
> `boxPlayers`@59 ⇒ those harnesses are CORRECT and are NOT routed.

### 4b. Carried INFO / MONITOR (no contract change; recorded so a future reader doesn't re-derive)

- **FC-389-03 (INFO):** `DecEntry.burn` comment "Total BURNIE burned this level" is imprecise — it
  stores the EFFECTIVE burn (raw × multBps), not the raw token burn. The `DecClaimRound.totalBurn`
  comment ("sum of effective amounts") is CORRECT. The storage-map FA-3 raw-vs-effective framing is
  itself the error and should not be re-derived as an overflow risk. uint128 bound sound. No change.
- **FC-389-05 distribution-bias half → 391:** the uint32 narrowing's per-bucket distribution-bias
  question (whether 32 bits biases reward distribution across many winners) is RNG-02 / FC-391-04 in
  the RNG sweep. The narrowing-EQUIVALENCE half is REFUTED here.
- **FC-389-02 / FC-389-08 solvency-conservation half → 390:** the narrowing-equivalence half is
  REFUTED here; whether an adversarial multi-tx sequence strands ETH / under-pulls stETH is
  FC-390-01/-02/-03 + FC-393-03 in the SOLVENCY/ACCESS sweeps.

### 4c. CONFIRMED contract findings

**0 CONFIRMED contract-source findings.** STORAGE-01..05, STORAGE-07, GASID-01..05 and FC-389-01/-02/
-03/-05/-06/-07/-08/-09 are all REFUTED / BY-DESIGN against `a8b702a7` with both nets on record. The
single CONFIRMED item (STORAGE-06 / FC-389-04) is a LOW oracle-integrity TEST-harness finding (R-389-01),
not a contract change. The byte-frozen subject is attested document-only at `a8b702a7`.

---

## 5. Re-attestation line (each req attested-or-finding)

| Req | Status at `a8b702a7` |
|-----|----------------------|
| STORAGE-01 | ATTESTED (no truncating cast; each narrowing bounded) |
| STORAGE-02 | ATTESTED (masked RMW preserves co-residents) |
| STORAGE-03 | ATTESTED (conventions agree by construction) |
| STORAGE-04 | ATTESTED (cursor-lag proof; 10 ETH cap not re-earnable) |
| STORAGE-05 | ATTESTED (ABI getters preserved) |
| STORAGE-06 | FINDING R-389-01 (2 stale test harnesses, LOW oracle-integrity, test-only fix; contract unaffected) |
| STORAGE-07 | ATTESTED (capBucketCounts ≤ maxTotal by construction + double-defended; "+4" is test-slack, not contract) |
| GASID-01 | ATTESTED (selector + ABI identity, 30/30) |
| GASID-02 | ATTESTED (keccak preimages byte-identical) |
| GASID-03 | ATTESTED (nibble-table output-identical, 0 mismatches) |
| GASID-04 | ATTESTED (trait-roll + `_farFutureSeed` equivalent) |
| GASID-05 | ATTESTED (no externally-observable behavior change) |

**Verdict:** the phase-389 packing/gas behavior-identity surface is adjudicated with BOTH nets on
record, the skeptic gate applied (0 HIGH), every req + lead carrying an explicit verdict. 0 CONFIRMED
contract findings; 1 CONFIRMED LOW oracle-integrity test-harness finding (R-389-01) DOCUMENTED + ROUTED
(test-only, not fixed here). Subject byte-frozen at `a8b702a7` throughout
(`git diff a8b702a7 -- contracts/` EMPTY).
