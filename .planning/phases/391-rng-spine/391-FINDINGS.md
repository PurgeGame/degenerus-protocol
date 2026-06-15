# 391-FINDINGS — RNG-SPINE adjudication (RNG-01..06 + FC-391-01..05 + 2 inherited cross-refs)

**Subject (byte-frozen):** `a8b702a7` (contracts tree `2934d3d8987a09c5f073549a0cb499f6c5f28620`;
`git diff a8b702a7 -- contracts/` EMPTY before and after every task in this plan).
**Baseline (the audit oracle):** `test/REGRESSION-BASELINE-v63.md` — forge **854 / 0 / 110**, the
expected forge-failure NAME-set is strictly EMPTY (a regression is any failing name at this subject). The
RNG-window freeze authority = `RngWindowFreeze.inv.t.sol` EXERCISED + non-vacuous (`afterInvariant` gates
`ghost_windowsOpened>0` AND `ghost_inWindowActions>0`) + FALSIFIABLE
(`test_invariantCatchesSeededInWindowMutation` PASS: a seeded in-window mutation of `rngWordByDay[snapDay]`
fires the detector); the 7/7 GREEN VRFPath suite; `DecimatorOffsetIsolation.t.sol` EXERCISED for terminal
[lvl+1] slot-isolation + claim-path-reached. **The decimator uint32 per-bucket DISTRIBUTION is a MISSING
oracle property** (388-02 ORACLE-HOLES) — proven here by a real distribution argument (§3b), NOT relied on
as already-netted; a statistical/property oracle is a ROUTED test-hardening item (§4b).
**Method:** COUNCIL + CLAUDE both (AUDIT-V63-PLAN §2 — a no-finding verdict for any slice requires BOTH
nets on record). NET 1 = the cross-model council (gemini + codex via council.sh), captured in
`391-01-COUNCIL-NET.md` + `council/rng.{gemini,codex}.txt`. NET 2 = the deep Claude adversarial net,
captured in `391-02-CLAUDE-NET.md` (run independently, council leads folded after).
**Posture:** AUDIT-ONLY. A CONFIRMED finding is DOCUMENTED and ROUTED to a SEPARATE gated USER-hand-
review boundary — never fixed, never auto-committed in this phase. The subject stays byte-frozen and
re-freezes only after a gated fix boundary.
**Threat weighting (AUDIT-V63-PLAN §4, USER-locked):** RNG/freeze = the **DOMINANT** class — the highest-
priority dimension. A real freshness/freeze break or a grindable distribution is HIGH-or-above; a benign
INFO timing/correlation item is not. DOMINANT = RNG/freeze · HIGH = gas-DoS only in the advanceGame
chain · SPINE = solvency · LOW/confirmatory = access-control + reentrancy + MEV.
**Design-intent anchor (§5):** verify the seed is FROZEN at request — do NOT flag the by-design lootbox
open/resolve TIMING as a freshness bug ([[lootbox-resolution-timing-by-design]]); verify freeze +
distribution, NOT desirability, for the Degenerette RTP / WWXRP worthlessness
([[degenerette-wwxrp-rtp-by-design]]); the documented EV-multiplier/recycle changes are 392's; the public
far-future salvage QUOTE (settled prior-day word) is by-design (not a payout RNG).

---

## 1. Both-nets-on-record attestation

A no-finding (REFUTED / BY-DESIGN / MONITOR) verdict for any item below cites BOTH nets.

| Slice | NET 1 (council) | NET 2 (Claude) | both on record? |
|-------|-----------------|----------------|-----------------|
| RNG-FREEZE (RNG-01..06 + FC-391-01..05 + FC-389-05, FC-392-11) | `391-01-COUNCIL-NET.md` + `council/rng.{gemini,codex}.txt` — both CLIs available, **0 skipped**. gemini: VERIFIED SOUND across ALL of RNG-01..06 (backward-traced commitment points; decimator 32-bit keccak-diffusion argument; one-shot record-clear; day+1 gate; SLOAD freeze-invariance), **0 findings**. codex: VERIFIED SOUND on RNG-01/02/03/05/06 + the survival accumulator + the coinflip-carry RNG-lock, **+1 INFO/LOW lead on RNG-04 / FC-391-01** (cross-round `uint32` decimator claim-seed collision, self-rated "not a freeze/manipulability break"). The single material cross-model divergence (codex INFO/LOW vs gemini SOUND), routed here. | `391-02-CLAUDE-NET.md` — independent per-consumer backward-trace (§A) + the dedicated decimator distribution argument (§B) + the RNG-03 one-shot + survival-accumulator trace (§C) + the RNG-04 cross-round skeptic dual-gate (§D) + the RNG-05 day-boundary divergence bound (§E) + the RNG-06 in-window SLOAD enumeration with the hash-preimage + activityScore-snapshot claims attacked (§F) | ✓ both |

T-391-05 (a no-finding verdict issued with only one net, or the decimator distribution waved as
"address-mixed so fine" without a real argument) does not apply: both nets are on record; RNG-02/FC-391-04
carries a concrete random-oracle distribution argument (§3b); the missing-distribution-oracle is recorded
as a ROUTED test-hardening item (§4b), not relied on as netted. T-391-04 (subject tampering) mitigation:
`git diff a8b702a7 -- contracts/` EMPTY throughout (the council ran read-only `--approval-mode plan` /
`--sandbox read-only`; NET 2 read all source via `git show a8b702a7:` — hardhat never invoked).
T-391-07 (a CONFIRMED finding silently fixed in-phase) does not apply: 0 CONFIRMED contract findings; the
one INFO/LOW correlation (RNG-04 cross-round) is DOCUMENTED + ROUTED (§4), never fixed.

---

## 2. Per-item adjudication table

Verdicts: **REFUTED** (claim attacked, holds) · **BY-DESIGN** (intended, sound) · **MONITOR** (no
defect, carried observation) · **CONFIRMED** (a real defect — routed in §4). All 6 reqs + 5 owned leads +
2 inherited cross-refs carry one row.

### 2a. RNG requirements (RNG-01..06)

| ITEM | What it claims | NET 1 | NET 2 | VERDICT | Settling commitment-point / bound / cite (`a8b702a7`) |
|------|----------------|-------|-------|---------|--------------------------------------------------------|
| **RNG-01** | every new/changed consumer backward-traces to a word UNKNOWN at the player's input-commitment | SOUND | REFUTED | **REFUTED** | PER-CONSUMER COMMITMENT POINTS: manual open binds `index` at the rng-request index-advance (LootboxModule:560; Advance:1690), word lands after; `resolveLootboxDirect` seed = caller-domain-separated word + player, no live read (LootboxModule:883/880-882); box-spins descend from the box's committed anchor seed (DegeneretteModule:1292/1347/1402); survival flip binds `betId` at placement before the word (DegeneretteModule:773); redemption keys `rngWordForDay(day+1)` undrawn at burn (StakedStonk:878); decimator claim word fixed at resolution, burn predates it (DecimatorModule:277, winners from the FULL word :241-269); coinflip stakes committed pre-word, resolved in the locked window (BurnieCoinflip:822, days 1-20 deploy-seeded); reverseFlip nudge gated by `rngLockedFlag` (Game:1817); far-future salvage = a settled-word QUOTE, not a payout (MintStreakUtils:232, by-design §5). No consumer admits a live, post-reveal, player-controllable seed input. (391-02-CLAUDE-NET §A.) |
| **RNG-02** | decimator uint32 claim-seed: entropy floor + non-grindable + UNBIASED per-bucket distribution | SOUND (keccak diffusion) | REFUTED (dedicated argument) | **REFUTED** | DEDICATED DISTRIBUTION ARGUMENT (§3b): winners selected from the FULL word before narrowing (DecimatorModule:241-269); claim seed = `hash2(uint32_word, uint160(player))` = `keccak256(W ‖ addr)` (LootboxModule:883). Random-oracle: distinct addresses ⇒ independent uniform 256-bit outputs even under the shared 32-bit `W` (keccak avalanche decorrelates the shared prefix from the tier-modulo low bits); the within-level joint tier distribution = product of N independent uniform draws (unbiased). Non-grindable: `W` is VRF-fixed at resolution AFTER address commitment; a multi-account actor gets N independent uniform draws with no shared-word edge. The 32-bit floor only bounds the cross-LEVEL word space (the §3a collision case, benign). ROUTED distribution-oracle note §4b. |
| **RNG-03** | box-spin resolvers (WWXRP/BURNIE/ETH) one-shot + replay-safe | SOUND | REFUTED | **REFUTED** | One-shot by construction: record-clear BEFORE resolution (`lootboxEth[index][player]=0` LootboxModule:579; `delete degeneretteBets[player][betId]` DegeneretteModule:655; `e.claimed=1` DecimatorModule:399) + delegatecall-only module guard `address(this)!=GAME` (DegeneretteModule:1298/1353/1408). A revert-to-observe unwinds the cleared record but the seed is fixed ⇒ any retry yields the IDENTICAL outcome (no re-roll). (391-02-CLAUDE-NET §C.) |
| **RNG-04** | resolveLootboxDirect + spin seeds domain-separated (no cross-consumer collision) | **codex INFO/LOW cross-round** vs **gemini SOUND** (DIVERGENT) | REFUTED (freeze/manip break); cross-round INFO/LOW benign | **REFUTED** (+ INFO/LOW carried §4b) | DIVERGENCE RESOLVED (§3a). Every caller domain-separates: decimator the per-level `round.rngWord` + winner address; Degenerette `hash2(rngWord, betId)`; recirc per-resolution rehash; redemption `hash2(rngWordForDay(day+1), player)` + per-chunk `hash1` (LootboxModule:560/883/1053, DecimatorModule:673, DegeneretteModule:786). Within-round: `e.claimed=1` / distinct `betId` block same-word/same-player collisions. Cross-round (codex): same player at two levels with `uint32(VRF_L2)==uint32(VRF_L)` ⇒ identical seed — skeptic dual-gate (§3a) = benign INFO/LOW (no player control, no value extraction, off the ETH spine). NET 2 reconciles both models. |
| **RNG-05** | redemption day+1 pre-draw gate (`BurnsBlockedBeforeDailyRng`) holds; no zero-seed grind | SOUND | REFUTED (day-boundary bound) | **REFUTED** | DAY-BOUNDARY DIVERGENCE BOUND: `currentPeriod = GameTimeLib.currentDayIndex()` is PURE in `block.timestamp` (GameTimeLib:31-33, does NOT read `dailyIdx`); gate `rngWordForDay(currentPeriod)!=0` (StakedStonk:991) forces `currentPeriod <= dailyIdx` because `rngWordByDay[d]` is written only by `_unlockRng(d)` / gap-backfill for days `<= dailyIdx` (Advance:1786/1841). A wall day past `dailyIdx` with no advance ⇒ word 0 ⇒ burn reverts; the highest admissible stamp is `dailyIdx`, so `day+1 = dailyIdx+1` is UNDRAWN at burn time. Lootbox leg reads `rngWordForDay(day+1)` (StakedStonk:878) — never on-chain at burn. Independent `rngLocked` guard in burn()/burnWrapped() = second wall. Closes the v62 REDEMPTION-ZERO-SEED gap. (391-02-CLAUDE-NET §E.) |
| **RNG-06** | every SLOAD inside an rng-window over the repacked slots is freeze-invariant | SOUND | REFUTED (enumeration) | **REFUTED** | IN-WINDOW SLOAD ENUMERATION over slots `rngWordByDay`@10 / `lootboxRngPacked`@34 / `lootboxRngWordByIndex`@35 / `dailyIdx`@(slot0,byte3): daily window (JackpotModule traits/coin on the day's `randWord`+frozen `lvl`; redemption roll `(currentWord>>8)%151+25` Advance:1259; coinflip `processCoinflipPayouts` day-word + frozen-snapshot stakes) + lootbox window (box draws read the slot-35 VRF anchor + the deposit-frozen packed `lootboxEth` word; spins' `activityScore` = the deposit/burn-time snapshot, never a live read — LootboxModule:541, DegeneretteModule:649, DecimatorModule:410). Two load-bearing claims attacked: (i) EntropyLib byte-identity — `hash2(a,b)==keccak256(abi.encode(a,b))`, `hash1(a)==keccak256(abi.encode(a))`, every migrated operand 32-byte incl. `uint256(uint160(player))` (EntropyLib:23-41); (ii) activityScore frozen-snapshot CONFIRMED. Anchored on the FALSIFIABLE `RngWindowFreeze.inv.t.sol` (slots 10/34/35 + dailyIdx); attacked beyond its action set (box-spin/decimator/redemption reads) — all VRF-derived or frozen. (391-02-CLAUDE-NET §F.) |

### 2b. RNG owned leads (FC-391-01..05)

| ITEM | What it claims | NET 1 | NET 2 | VERDICT | Settling bound / cite |
|------|----------------|-------|-------|---------|-----------------------|
| **FC-391-01** | resolveLootboxDirect dropped `amount`; caller-side domain separation load-bearing | codex INFO/LOW (cross-round) vs gemini SOUND | REFUTED | **REFUTED** (+ INFO/LOW §4b) | Same as RNG-04: every caller domain-separates; within-round collisions blocked; the cross-round `uint32` identical-seed is benign INFO/LOW (no control, no extraction). LootboxModule:883, DecimatorModule:277/673. (§3a skeptic gate.) |
| **FC-391-02** | box-spin replay/one-shot; the new permissionless consumer is single-shot | SOUND | REFUTED | **REFUTED** | Same as RNG-03: record-clear-before-resolution + `address(this)!=GAME` delegatecall guard ⇒ one-shot; revert-to-observe re-yields the identical fixed-seed outcome. DegeneretteModule:655/1298/1353/1408. |
| **FC-391-03** | survival-flip cross-bet accumulator can't transiently underflow the unsigned running total | SOUND | REFUTED | **REFUTED** | `acc.burnieMint += payout` PER SPIN in `_distributePayout` (DegeneretteModule:907) places this bet's `totalPayout` into `acc` BEFORE the flip; WIN `+= totalPayout` (:774), LOSS `-= totalPayout` (:777) subtracts exactly what this bet added — the per-bet `+=` always precedes its own `-=`, so no cross-bet ordering can drive it negative. Box-spin variant uses a LOCAL `total` (DegeneretteModule:1357/1393) — strictly underflow-free. |
| **FC-391-04** | decimator 32-bit narrowing can't BIAS the per-bucket reward distribution (the §6 prime / MISSING property) | SOUND (both, real argument) | REFUTED (dedicated §3b) | **REFUTED** | Same as RNG-02: random-oracle independence + non-grindability (§3b); the within-level tier histogram converges to uniform; the 32-bit floor bounds only the cross-level word space (benign §3a). The MISSING distribution oracle is ROUTED as a test-hardening item (§4b), NOT a contract change. DecimatorModule:241-277, LootboxModule:883. |
| **FC-391-05** | redemption day-boundary: `currentDayIndex()` can't diverge from `dailyIdx` to stamp a day whose day+1 word is on-chain | SOUND | REFUTED | **REFUTED** | Same as RNG-05: the gate pins `currentPeriod <= dailyIdx` (word written only for ≤ dailyIdx days), so `day+1` is undrawn at burn time; backfill never writes `currentPeriod+1`. GameTimeLib:31-33, StakedStonk:983/991, Advance:1786/1841. (§3a day-boundary bound.) |

### 2c. Inherited cross-refs (FC-389-05, FC-392-11)

| ITEM | What it claims | NET 1 | NET 2 | VERDICT | Settling bound / cite |
|------|----------------|-------|-------|---------|-----------------------|
| **FC-389-05** | decimator uint32 narrowing-equivalence (gas-identity half) + the RNG-consumption / grind-retry-timing half (owned here) | SOUND | REFUTED (RNG half) | **REFUTED (RNG half); STORAGE → 389** | `round.rngWord = uint32(rngWord)` (DecimatorModule:277) = predictability-WITHOUT-control (address committed at burn, word VRF-fixed at resolution, permissionless deterministic claim credits only the winner so claim timing can't grind). Packs into the `DecClaimRound` slot with `poolWei`(uint96)+`totalBurn`(uint128)=256 bits, no co-resident corruption (STORAGE-attestation half owned by 389). RNG-consumption + grind/retry-timing half: REFUTED (§B/§D). |
| **FC-392-11** | coinflip-carry RNG-lock coverage half (the backing/EV dynamics half is 392's) | SOUND | REFUTED (lock airtight) | **REFUTED (RNG-lock half); backing → 392** | `claimCoinflipCarry` reverts on `degenerusGame.rngLocked()` at the TOP (BurnieCoinflip:759) BEFORE settling or reading `autoRebuyCarry` (:770). Lock window: set at the daily request (Advance:1699), callback stores `rngWordCurrent` while KEEPING the lock (Advance:1808), `_unlockRng` clears only after processing (Advance:1779). `processCoinflipPayouts` is `onlyDegenerusGameContract` (:204) applying the roll inside the locked window. No window exists where a carry claim/settle reads the roll before the lock blocks it — airtight. Backing-solvency dynamics (loss zeroes pending; carry excluded from redemption backing) → 392. |

---

## 3. Skeptic gate (run before any CATASTROPHE/HIGH)

**Outcome: 0 items reach CATASTROPHE/HIGH.** Both surface-maps found 0 HIGH on inspection; both nets
converge on no freeze/manipulability break across all 13 items. The single material cross-model divergence
(RNG-04 codex INFO/LOW cross-round collision vs gemini SOUND) is run through the full dual-gate (§3a). The
§6 prime distribution target (RNG-02 / FC-391-04) gets the dedicated real argument (§3b). RNG/freeze is
the DOMINANT class — a confirmed break here would be highest-severity — so both prime/divergent targets
get the gate even at INFO/LOW.

### 3a. RNG-04 / FC-391-01 cross-round `uint32` collision — the load-bearing dual-gate

The council DIVERGED: codex raised an INFO/LOW cross-round `uint32` claim-seed collision (same player
winning at two decimator levels where `uint32(VRF_L2)==uint32(VRF_L)` gets identical direct-lootbox
seeds), self-rated "not a freeze/manipulability break"; gemini ruled RNG-04 SOUND (reasoning within ONE
level, where the per-caller term + the player address separate concurrent claims). NET 2 pinned the exact
frozen lines and ran the dual-gate.

| Gate dimension | Result |
|---|---|
| **Source pin** | `round.rngWord = uint32(rngWord)` (DecimatorModule:277); `_claimDecimatorJackpotFor` passes `round.rngWord` (:410) → `_awardDecimatorLootbox` (:645) → `resolveLootboxDirect(winner, amount, rngWord, ...)` seed = `hash2(uint32_word, uint160(player))` (LootboxModule:883). `e.claimed=1` (:399) is per (level, player). |
| **Structural-protection check** | (1) The seed sets only the tier/level OUTCOME TYPE; the reward MAGNITUDE scales independently by each claim's own `amount`. (2) The player cannot CHOOSE either `VRF_L` or `VRF_L2` (both VRF-fixed at each level's resolution, AFTER the player's burn commitments). (3) The lootbox tier is BURNIE-credit/ticket-adjacent, OFF the ETH/`claimablePool` solvency spine. (4) An identical uniform draw realized twice for the SAME player does not raise its expectation (conditioning two of P's draws to be equal does not bias them toward higher tiers). |
| **3-condition EV/reachability lens** | (1) reachable? Marginally — P ~ K^2/2^33 ≈ 10^-5..10^-4 for realistic K decimator levels, AND the same player must win at both colliding levels. (2) profitable? NO — no value extraction: same-distribution draw realized twice, magnitude set by independent `amount`, off the ETH spine (fails the profitability condition). (3) repeatable/grindable? NO — the words are VRF-fixed after address commitment and cannot be chosen or predicted at burn time (predictability-without-control). |
| **Gate result** | **NOT a freeze/manipulability break — fails the profitability + grindability conditions. RNG-04 REFUTED as a break; the cross-round collision is INFO/LOW benign (no player control, no value extraction, off the ETH spine).** NET 2 reconciles both models: gemini's within-level SOUND holds; codex's cross-round collision is real-but-benign INFO/LOW. Carried as a doc-only INFO observation (§4b), the likely USER disposition. |

### 3b. RNG-02 / FC-391-04 decimator distribution — the §6 PRIME dedicated argument

| Gate dimension | Result |
|---|---|
| **Source pin** | Winner select from the FULL word `decSeed = rngWord` (DecimatorModule:241-269); narrowing `round.rngWord = uint32(rngWord)` (:277) feeds ONLY the claim-time lootbox seed `hash2(uint32_word, uint160(player))` (LootboxModule:883), which drives `_rollTargetLevel` (bits 0-39) + `_resolveLootboxRoll` (bits 40+, the tier draw). |
| **Distribution argument (real, not a hand-wave)** | Across the WHOLE winning-bucket population of one level (N winners sharing one `W`, differing by 160-bit address): each `seed_i = keccak256(W ‖ addr_i)` is an independent uniform 256-bit random-oracle output (distinct `addr_i` ⇒ distinct inputs ⇒ decorrelated outputs; keccak avalanche destroys the shared 32-bit prefix in the tier-modulo low bits). The joint tier distribution = product of N independent uniform draws — unbiased, uncorrelated. Identical to the full-word case WITHIN a level (the per-winner draw was always conditioned on one level word). |
| **3-condition EV lens** | (1) reachable bias? NO — the population tier histogram converges to uniform (independent draws). (2) profitable multi-account exploit? NO — N controlled addresses get N independent uniform draws, no shared-`W` edge, no aggregate advantage over a single account. (3) grindable? NO — `W` is VRF-fixed after address commitment; the 32-bit floor only bounds the cross-LEVEL word space (the §3a benign collision), not within-level steerability. |
| **Gate result** | **NOT a finding — distribution unbiased + non-grindable. REFUTED.** The MISSING distribution oracle is ROUTED as a test-hardening item (§4b), NOT relied on as netted for this verdict (the property is proven by the random-oracle argument above). |

### 3c. Remaining items

No other item is tagged CATASTROPHE/HIGH. RNG-01/03/05/06 + FC-391-02/03/05 + FC-389-05/FC-392-11 are
REFUTED-sound by both nets with source traces (§2) — none reaches the elevated-attention threshold (each
is a freeze/one-shot/lock property proven by construction, not a borderline EV call). The gemini
boon-interpretation observation (`level`, `decWindowOpen` live reads) is confirmed as the by-design timing
edge (an OUTPUT gate choosing which already-fixed bracket lands, not a seed input —
[[lootbox-resolution-timing-by-design]]), NOT a new live-input-into-seed path.

---

## 4. Routing — CONFIRMED findings + carried INFO/MONITOR

### 4a. CONFIRMED contract findings

**0 CONFIRMED contract-source findings.** RNG-01..06, FC-391-01..05, and the 2 inherited cross-refs are
all REFUTED / BY-DESIGN against `a8b702a7` with BOTH nets on record. The byte-frozen subject is attested
document-only at `a8b702a7`. No freeze/manipulability break — the DOMINANT class is clean across the
change set. RNG-01..06 attested.

### 4b. Carried INFO / MONITOR (no contract change; recorded so a future reader doesn't re-derive)

- **RNG-04 / FC-391-01 cross-round `uint32` collision (codex INFO/LOW lead → REFUTED-as-break,
  carried INFO):** a single player winning at two decimator levels with `uint32(VRF_L2)==uint32(VRF_L)`
  gets identical direct-lootbox claim seeds. The skeptic dual-gate (§3a) confirms it is benign: no player
  control over either word, no value extraction (magnitude set by independent `amount`, off the ETH
  spine), ~10^-5..10^-4 reachability. A future reader should NOT re-derive it as a HIGH/manipulability
  finding. The likely USER disposition (if recorded at all) is a doc-only KNOWN-ISSUES entry for a
  no-player-control correlation — but note the standing rule that obviously-intended bounded mechanics
  do not belong in the public moat ([[intended-game-mechanics-not-findings]]); routed to USER judgment,
  NOT fixed here.
- **Decimator uint32 distribution-oracle test-hardening (ROUTED to a later test phase, NOT a contract
  change):** `DecimatorOffsetIsolation.t.sol` proves terminal slot-isolation + claim-path-reached but no
  oracle asserts the per-bucket tier DISTRIBUTION is unbiased across a winner population (the 388-02
  MISSING property). A later test phase COULD add a statistical/property test that draws many
  `hash2(W, addr)` over a synthetic winner population and asserts the tier histogram is within tolerance
  of uniform — an oracle-completeness item; the property is already proven above by the random-oracle
  argument (§3b). NOT a contract defect.
- **FC-389-05 narrowing-equivalence (INFO):** the uint32 claim-word is predictability-without-control;
  the RNG-consumption half is REFUTED here, the STORAGE slot-attestation half is owned by 389. No change.
- **FC-392-11 backing-solvency half (cross-ref → 392):** the RNG-lock coverage of the carry roll is
  airtight (§2c); the backing/EV dynamics (a loss sequence vs outstanding redemption obligations; the
  carry's exclusion from sDGNRS redemption backing) are owned by 392 — recorded so 392 owns that half.
- **Boon-interpretation live reads (MONITOR, by-design):** gemini's `level` / `decWindowOpen` observation
  is the documented timing edge (output gate, not seed input — [[lootbox-resolution-timing-by-design]]),
  confirmed not a freshness break. No change.

Any test-only (oracle-integrity / missing-property) gap is ROUTED, not a contract finding.

---

## 5. Re-attestation line (each req attested-or-finding)

| Req | Status at `a8b702a7` |
|-----|----------------------|
| RNG-01 | ATTESTED (every new/changed consumer backward-traces to a word unknown at the player's input-commitment) |
| RNG-02 | ATTESTED (decimator uint32 claim-seed: 32-bit floor, non-grindable, per-bucket distribution UNBIASED by the random-oracle argument) |
| RNG-03 | ATTESTED (box-spin resolvers one-shot + replay-safe; record-clear-before-resolution + delegatecall guard) |
| RNG-04 | ATTESTED (seeds domain-separated; the cross-round `uint32` collision is benign INFO/LOW, not a break) |
| RNG-05 | ATTESTED (redemption day+1 pre-draw gate holds; `currentPeriod <= dailyIdx` by construction; no zero-seed grind) |
| RNG-06 | ATTESTED (every in-window SLOAD is VRF-derived or a frozen snapshot; EntropyLib byte-identity; activityScore frozen) |

**Verdict:** the phase-391 RNG-freeze surface (RNG-01..06 + FC-391-01..05 + FC-389-05, FC-392-11) is
adjudicated with BOTH nets on record, the skeptic gate applied (0 HIGH — the single divergent INFO/LOW
lead REFUTED-as-break at source), and every item carrying an explicit verdict backed by a commitment-
point, bound, or source-cite. The two prime/divergent targets are settled by dedicated treatment: RNG-04
cross-round collision (§3a skeptic dual-gate = benign INFO/LOW), RNG-02/FC-391-04 distribution (§3b real
random-oracle argument = unbiased + non-grindable). The backward-trace is applied to every consumer
(§2a RNG-01); the in-window SLOADs are enumerated (§2a RNG-06); the day-boundary divergence is bounded
(§2a RNG-05). **0 CONFIRMED contract findings.** The byte-frozen subject is attested document-only at
`a8b702a7` throughout (`git diff a8b702a7 -- contracts/` EMPTY). The DOMINANT threat class is clean.
