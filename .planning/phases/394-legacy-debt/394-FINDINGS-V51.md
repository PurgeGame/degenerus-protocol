# 394-FINDINGS-V51 — LEGACY-DEBT / the v51 surface adjudication (LEGACY-03 + LEGACY-04)

**Subject (byte-frozen):** `a8b702a7` (contracts tree pin `2934d3d8987a09c5f073549a0cb499f6c5f28620`).
**Baseline (green oracle):** `test/REGRESSION-BASELINE-v63.md` = forge **854 / 0 / 110** (expected
forge-failure NAME-set strictly EMPTY). The ETH prize-pool conservation anchor is
`PoolConservation.inv.t.sol` (FUZZ-05); the sDGNRS Reward-pool backing anchor is the BPS-sum + clamp proof
(§2, NET 2 §3). The v51 contract behaviors carry the Phase-341 coverage (per-tier rewards / dedup / empty-pool
/ jackpot-final-day regression) folded into this green subject.
**Date:** 2026-06-15.
**Method — CROSS-MODEL-LED, dual-net (AUDIT-V63-PLAN §2):** NET 1 = the external council
(`394-02-COUNCIL-NET.md` — `codex` on record, `gemini` skipped/non-responsive → 396); NET 2 = the independent
Claude adversarial net (`394-04-CLAUDE-NET.md`). A no-finding verdict for any v51 sub-item requires BOTH nets
on record.
**Posture:** AUDIT-ONLY. A CONFIRMED finding is DOCUMENTED and ROUTED to a SEPARATE gated USER-hand-review
boundary (batched, never auto-committed; the subject re-freezes only after a gated fix) — it is NOT fixed in
this phase.
**Threat weighting (§4):** the bingo `traitBurnTicket` freeze read = DOMINANT (RNG/freeze); the sDGNRS
`Pool.Reward` rebalance + the jackpot final-day deletion = SPINE (solvency); access / reentrancy / timing =
confirmatory.
**Design-intent anchor (§5 — VERIFY, do not re-litigate):** the claimBingo no-level-guard
([[claimbingo-no-level-guard]]) and the Degenerette RTP / whale-pass economics
([[degenerete-wwxrp-rtp-by-design]] / [[degenerette-wwxrp-rtp-by-design]]) are BY-DESIGN — the sweep verifies
freeze / tier-precedence / dedup-integrity / pool-conservation; it does NOT re-flag the no-level-guard or the
RTP.

---

## 1. Both-nets-on-record attestation

| Slice | NET 1 (council) | NET 2 (Claude) | Both? |
|---|---|---|---|
| v51 LEGACY-DEBT (LEGACY-03 claimBingo / BingoModule; LEGACY-04 sDGNRS `Pool.Reward` rebalance + jackpot final-day deletion) | `394-02-COUNCIL-NET.md` + `council/v51.codex.txt` (19 lines, full traced audit) — **`codex` on record = 0 findings, all 3 break-targets VERIFIED SOUND** (with the LEGACY-04b "no final-day Reward path" refinement + the stale `JackpotModule:1047` comment note). **`gemini` SKIPPED** (`v51.council.json` `skipped: ["gemini"]`) — non-responsive (no output within an 8-min hard cap ×2; rc=124), NOT a refusal/classifier trip. The single-available-model-with-real-content rule satisfies "council on record" with the skip documented; the `gemini` second-source is carried to **396**. | `394-04-CLAUDE-NET.md` — independent per-item attack: the claimBingo freeze backward-trace (the sole `traitBurnTicket` writer enumerated + shown in the swapped/frozen read buffer), the tier-precedence/dedup/CEI/empty-pool/gameOver analysis, the `Pool.Reward` 8-BPS-sum + clamp split-conservation proof, the jackpot final-day deletion grep-enumeration (the premise shown VACUOUS) + the ETH-path FUZZ-05 backing-conservation | ✓ both (codex + Claude); gemini skip documented → 396 |

**Both-nets requirement satisfied for every v51 sub-item.** No item is treated as on-record from a single
net — `codex` (NET 1) + Claude (NET 2) are both on record, CONVERGENT SOUND on all four sub-items. The
`gemini` skip is surfaced, not silently passed (T-394-12): a post-responsive `gemini` second-source re-run of
the codex SOUND verdicts (esp. the LEGACY-03a freeze + the LEGACY-04b "no final-day Reward path" refinement)
is carried to 396. NOTE the inversion vs the 392/393 slices (there codex was capped, gemini available; here
codex is available, gemini non-responsive) — the 396 second-source carry now spans BOTH directions.

**Threat-register cross-check.** T-394-12 (a no-finding verdict without both nets, or the Pool.Reward
conservation attested without the BPS sum, or the claimBingo freeze/dedup waved without a CEI proof) does NOT
apply — both nets on record; the conservation carries the 8-BPS sum (= 10000 = `BPS_DENOM`); the dedup carries
the CEI bit-ordering cite (`BingoModule:151`/`:166-169`/`:174` before `:188-196`). T-394-13 (a CONFIRMED break
under-weighted, or a HIGH tagged without the skeptic filter) does NOT apply — the skeptic dual-gate ran on the
three value-bearing items (§3); none reaches HIGH. T-394-14 (a CONFIRMED finding silently fixed in-phase) does
NOT apply — 0 CONFIRMED; the subject stays byte-frozen.

---

## 2. Per-item adjudication table (LEGACY-03 + LEGACY-04)

| ITEM | What it claims | NET 1 (codex) | NET 2 (Claude) | **VERDICT** | Settling freeze / tier / dedup / CEI / BPS-sum / clamp / conservation cite (`a8b702a7`) |
|---|---|---|---|---|---|
| **LEGACY-03a** — claimBingo FREEZE-safety (DOMINANT) | the post-resolution `traitBurnTicket[level]` read is over a frozen, pre-resolved population; no player can steer it after the level's word is public | VERIFIED SOUND | REFUTED (RNG-freeze-safe) | **REFUTED** | Backward-trace: the SOLE writer of `traitBurnTicket[level]` is `_raritySymbolBatch` (`MintModule:789-812`, the assembly batch-`sstore`); all other touches are READ-ONLY (`BingoModule:135-141` read; `JackpotModule` `_randTraitTicket` `view`). The writer drains the read buffer which is swap+frozen BEFORE the word: `_swapTicketSlot` reverts if the read slot isn't drained (`Storage:780-784`), `_swapAndFreeze` sets `prizePoolFrozen` (`:793-805`) on the daily-RNG path (`AdvanceModule:389`); far-future sale rng-locked (`MintModule:1214`). `claimBingo` is strictly `msg.sender`-only (no operator path). |
| **LEGACY-03b** — tier-precedence + (level,quadrant) dedup + CEI + empty-pool + gameOver | quadrant-first marks BOTH bits and suppresses the symbol bonus; the dedup bit is set before the external calls (reentrancy-safe); empty pool is a graceful no-op; gameOver blocks post-game | VERIFIED SOUND | REFUTED (CEI-tight, tier-correct) | **REFUTED** | Dedup EFFECT `bingoClaimed[level][msg.sender] \|= qMask` (`BingoModule:151`) + tier bits (`:166-169` quadrant-first marks BOTH; `:174` symbol-first preserves the co-resident quadrant mask via `& ~uint64(0xFFFFFFFF)`) ALL set BEFORE the interactions `transferFromPool`/`creditFlip` (`:188-196`) → a reentrant or repeat claim hits the set `qMask` and reverts `AlreadyClaimed` (`:150`). Empty-pool: `transferFromPool` clamps to 0 (`StakedStonk:553-556`), bit consumed, BURNIE still paid (`:196`). gameOver `:122`. No-level-guard self-gated by the 8-color ownership check (`:137-145`, [[claimbingo-no-level-guard]]). |
| **LEGACY-04a** — sDGNRS `Pool.Reward` rebalance (SPINE) | the AFFILIATE 3500→3000 / REWARD 500→1000 rebalance conserves the genesis split (sum = BPS_DENOM) and no draw over-draws / reads a stale BPS | VERIFIED SOUND | REFUTED (split conserved, no over-draw) | **REFUTED** | 8-BPS sum at source: CREATOR 2000 + WHALE 1000 + AFFILIATE 3000 + LOOTBOX 2000 + REWARD 1000 + PRESALE_BOX 1000 = **10000 == `BPS_DENOM`** (`StakedStonk:302-312`). Genesis seeding exact (`INITIAL_SUPPLY = 1e30` ÷ `10_000` = `1e26`, integer → the dust branch `:391-397` is a no-op; pools seeded `:404-408`, `uint128` narrowing safe ≤1e30≪2^128). `transferFromPool` clamps (`:548-570`: `available==0→0`; `amount>available→available`); `transferBetweenPools` clamps (`:579-593`). Every consumer reads the LIVE balance — Bingo `:188-193`, Degenerette `:1220-1232`, coinflip bounty `Game:465-475` — NO hard-coded old split. |
| **LEGACY-04b** — jackpot final-day `Pool.Reward` deletion (SPINE) | the final-day reward consolidation deletes/draws `Pool.Reward`, risking stranded backing or a double-spend vs a concurrent Bingo/Degenerette draw | VERIFIED SOUND — **codex found NO final-day Reward path** | REFUTED, **premise VACUOUS** | **REFUTED (premise vacuous) + INFO doc-hygiene** | **Grep-enumeration:** `Pool.Reward` appears at EXACTLY 6 sites — genesis (`StakedStonk:408`/`:311`/`:389`), the 3 live draws (Bingo `:188/190`, Degenerette `:1221/1230`, coinflip `Game:466/472`), and doc comments — and NOWHERE in `AdvanceModule` or `JackpotModule`. The AdvanceModule final-day pool draw (`_rewardTopAffiliate :753-763`) targets **`Pool.Affiliate`**, not `Pool.Reward`; `JackpotModule` has ZERO sDGNRS pool touch (grep empty). The real final-day surface is the ETH prize-pool (`currentPrizePool`/`claimablePool`/`futurePrizePool`, `Storage:354-379`), backing-conserved by FUZZ-05 (`PoolConservation.inv.t.sol`, green) + the 390 SOLVENCY spine. **INFO:** the two STALE "DGNRS on final day" comments (`JackpotModule:1047`/`:1160`) describe a transfer the code does not implement (solo bucket pays ETH+whale-passes only). |

---

## 3. Skeptic dual-gate (run before any CATASTROPHE/HIGH)

Nothing in the v51 slice reaches a CONFIRMED break, so nothing reaches the HIGH bar — but per the standing
posture ([[feedback_skeptic_pass_before_catastrophe]]) the dual-gate (structural-protection check + the
3-condition EV lens) was applied to the three value-bearing items (the DOMINANT freeze read + the two SPINE
conservation surfaces) to confirm none is an under-weighted HIGH (NET 2 §5):

### 3a. The bingo `traitBurnTicket` freeze read (DOMINANT)
- **Structural protection:** the sole writer (`_raritySymbolBatch`, `MintModule:789-812`) runs in the
  swapped/frozen read buffer (`Storage:780-805`, `AdvanceModule:389`) before the level's word; the read
  (`BingoModule:135-141`) is over a frozen population; far-future sale is rng-locked (`MintModule:1214`).
- **3-condition EV lens:** (1) value gained/lost from steering the read — NONE (no post-word append exists);
  (2) direction — n/a (no steering surface); (3) player-steerable edge — NONE. **Gate FAILS for HIGH →
  REFUTED** (RNG-freeze holds).

### 3b. The sDGNRS Pool.Reward rebalance (SPINE)
- **Structural protection:** the 8 BPS sum to `BPS_DENOM` (10000, `StakedStonk:302-312`); the clamp
  (`:548-570`) bounds every draw to the available balance.
- **3-condition EV lens:** (1) value — NONE (no over-draw; the split is conserved); (2) direction — n/a; (3)
  edge — NONE. **Gate FAILS for HIGH → REFUTED.**

### 3c. The jackpot final-day deletion (SPINE)
- **Structural protection:** the premise is VACUOUS (no sDGNRS Reward final-day path; grep-enumerated); the
  real ETH final-day path is FUZZ-05-conserved + green (`PoolConservation.inv.t.sol`).
- **3-condition EV lens:** (1) value — NONE (no stranded/double-spent sDGNRS backing; the ETH reshape is
  backed); (2) direction — n/a; (3) edge — NONE. **Gate FAILS for HIGH → REFUTED** (premise vacuous).

**Result: NOTHING reaches HIGH/CATASTROPHE.** All three value-bearing items are structurally protected with no
EV edge; the convergent-SOUND verdicts (both nets) are attested with both nets on record. The only
non-REFUTED output is document-only (the two stale comments).

---

## 4. Routing — CONFIRMED findings + carried INFO/MONITOR

### 4a. CONFIRMED contract findings
**0 CONFIRMED — document-only.** No CONTRACT-CHANGE-NEEDED block is emitted. LEGACY-03 + LEGACY-04 are
attested at `a8b702a7` with both nets on record. The subject stays byte-frozen
(`git diff a8b702a7 -- contracts/` empty).

### 4b. Carried INFO / MONITOR (no contract change; recorded so a future reader doesn't re-derive)
- **INFO — stale "DGNRS on final day" comments (doc-only, ROUTED, NOT a contract finding).** Two comments —
  `JackpotModule:1047` ("Solo bucket gets whale pass + DGNRS on final day") and `:1160` ("Solo bucket (jackpot
  phase): whale pass + DGNRS on final day") — describe a `Pool.Reward`/DGNRS transfer the frozen solo-bucket
  path (`_handleSoloBucketWinner` → `_processSoloBucketWinner`) does NOT implement (it pays 75% ETH + 25%
  whale passes only). The code is the authority; no value moves. Per [[feedback_no_history_in_comments]] /
  [[lean-code-comments-no-procedural-meta]] this is a doc-hygiene item — route a comment trim to a post-audit
  hygiene pass (a non-contract edit, deferred while the subject is byte-frozen). codex independently flagged
  `:1047`; NET 2 found the second site `:1160`.
- **MONITOR (non-finding, favors the protocol) — the bingo dedup is permanent.** The `(level, quadrant)`
  dedup bit (`bingoClaimed`, `BingoModule:151`) is one-shot per the design — bingo is a first-completion
  reward, the dedup is permanent by intent. An empty Reward pool at claim-time consumes the bit and pays only
  BURNIE (the ETH/stETH draw is a graceful no-op, not re-attemptable). This is the intended one-shot economics
  ([[intended-game-mechanics-not-findings]]), recorded as a non-finding.
- **`gemini` second-source carry (ROUTED to 396).** `gemini` skipped (non-responsive) on this slice; a
  post-responsive re-run to second-source the codex SOUND verdicts (the LEGACY-03a freeze + the LEGACY-04b
  "no final-day Reward path" refinement) is carried to 396. The existing 392/393 codex second-source carry to
  396 is unaffected.

Any doc-only (comment-staleness) gap is ROUTED, not a contract finding.

---

## 5. Re-attestation line (each req attested-or-finding)
- **LEGACY-03** (claimBingo color-completion / BingoModule — 3-tier reward selection, per-player
  `(level,quadrant)` dedup, freeze-safety of the post-resolution `traitBurnTicket` read) — **ATTESTED at
  `a8b702a7`**, both nets on record. The freeze REFUTED-as-finding (RNG-freeze-safe, the read over a frozen
  population, sole writer in the swapped/frozen buffer); tier-precedence + dedup + CEI + empty-pool + gameOver
  REFUTED-as-finding (CEI-tight). **0 CONFIRMED.**
- **LEGACY-04** (the sDGNRS `Pool.Reward` rebalance + the jackpot final-day `Pool.Reward` deletion
  side-effects) — **ATTESTED at `a8b702a7`**, both nets on record. The rebalance REFUTED-as-finding (split
  conserved sum=BPS_DENOM, every draw clamps, no stale-split consumer); the final-day deletion
  REFUTED-as-finding — **premise VACUOUS** (no sDGNRS Reward final-day path; the real ETH surface is
  FUZZ-05-conserved). **0 CONFIRMED** + 1 INFO doc-hygiene (the two stale comments).
- **LEGACY-06** — `audit/FINDINGS-v51.0.md` authored from this dual-net adjudication (Task 2 deliverable).

**Slice verdict:** the v51 legacy-debt surface (LEGACY-03 + LEGACY-04) is adjudicated against the byte-frozen
subject `a8b702a7` with BOTH nets on record (codex + Claude, CONVERGENT SOUND; gemini skip documented → 396),
the skeptic dual-gate applied to the three value-bearing items, and every sub-item carrying an explicit
verdict. **0 CONFIRMED contract findings**; 1 INFO doc-hygiene item (the stale `JackpotModule:1047`/`:1160`
comments). The subject stays byte-frozen.
