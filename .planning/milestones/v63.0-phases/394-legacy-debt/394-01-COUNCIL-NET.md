# 394-01 — NET 1 (Cross-Model Council) Capture Record — LEGACY-DEBT / the v50 surface slice (LEGACY-01, LEGACY-02)

**Subject (byte-frozen):** `a8b702a7` (contracts tree pin `2934d3d8987a09c5f073549a0cb499f6c5f28620`).
**Net:** NET 1 = the cross-model council (external `gemini` + `codex` CLIs via `council.sh`).
**Purpose:** per AUDIT-V63-PLAN §2, a no-finding verdict for any sweep slice requires BOTH nets on
record. This v50 surface is FOLDED AUDIT DEBT — v50.0 closed 2026-05-28 via a USER-approved MINIMAL CLOSE
WITHOUT Phase 338's internal 3-skill adversarial sweep + delta-audit + `audit/FINDINGS-v50.0.md` (all
deferred). The cross-model council — the PRIMARY finder ([[cross-model-led-audits-over-claude-only]]) — goes
on record FIRST so the Wave-2 Claude-net + adjudication plan (394-03) can fold the council leads in BEFORE
any per-item verdict and author the deferred `audit/FINDINGS-v50.0.md`. RAW capture only — NOT adjudicated,
refuted, or fixed here (adjudication is 394-03).

---

## NET 1 ON RECORD for the v50 LEGACY-DEBT slice

The v50 slice (LEGACY-01 whale-pass O(1) deferred-claim path + the box-open record; LEGACY-02 AFSUB
pass-gating + OPEN-E re-attest + MINTDIV index alignment) was fanned to the council via
`council.sh --label v50`. **BOTH models are on record with substantive traced per-item audits** —
`gemini` AND `codex` each returned a non-empty answer that addresses all three break-targets (LEGACY-01,
LEGACY-02a, LEGACY-02b) with `file:line` cites at `a8b702a7`. `skipped[]` is EMPTY this run.

**This is a change from the prior sweep phases (392-01..04, 393-01) where `codex` was in `skipped[]` under a
hard usage-limit cap.** The codex usage limit has RESET — codex returned a full traced audit (38 lines)
this run, with `v50.codex.err` = 0 bytes (clean exit). **The dual-NET is therefore satisfied by the council
ALONE on this slice** (gemini + codex both on record); the Wave-2 Claude net (394-03) is the independent
second-discipline net the both-nets-on-record rule requires. **No post-reset codex re-run is owed for
394-01.** (The 392/393 carry-forward of a codex re-run → 396 still stands for THOSE slices — see the 394-01
NOTE at the end; this slice does NOT add to that debt.)

## Council manifest (available / skipped)

| Slice | Label | council.json | Available models | Skipped models |
|-------|-------|--------------|------------------|----------------|
| LEGACY-DEBT (v50 surface) | `v50` | `council/v50.council.json` | `gemini` (real audit) + `codex` (real audit) | (none) |

Council runner: `.planning/audit-v52/cross-model/bin/council.sh` (read-only wrappers — `ask-gemini.sh`
`--approval-mode plan`; `ask-codex.sh` `--sandbox read-only`). No `--schema` was passed → free-text `.txt`
output. ONE slice = ONE fan-out (gemini + codex run in parallel internally), so the single-invocation pacing
rule ([[pace-runs-to-survive-5h-cap]]) is satisfied. `council.sh` exited 0.

**Fan-out narrative (recorded for audit-trail integrity):**
- An earlier session had authored + committed the prompt (`691315c5`) and started a fan-out that was
  INTERRUPTED before producing output — it left two 0-byte `.err` files (`v50.gemini.err`,
  `v50.codex.err`, timestamped 00:27) and NO `.txt` outputs and NO `council.json`. The stale empty `.err`
  files were removed before re-running (a single specific pair, not a blanket clean).
- The re-run of `council.sh --label v50` fanned gemini + codex in parallel. BOTH returned OK
  (`council: gemini OK -> v50.gemini.txt`; `council: codex OK -> v50.codex.txt`). Both fresh `.err` files
  are 0 bytes (clean exits). `v50.council.json` reflects the real state:
  `models: ["gemini","codex"]`, `skipped: []`.

**Write-capable-agent verification ([[feedback_verify_writecapable_agents]]):** the council wrote ONLY to its
out-dir (`council/v50.gemini.txt`, `council/v50.codex.txt`, `v50.council.json`, the two 0-byte `.err`
files). NO stray file was written anywhere in the tree — full `git status --porcelain` shows only the
pre-existing untracked `PLAYER-PURCHASE-REWARDS.html` and a prior-session `.planning/STATE.md` edit (the
Phase 394 "execution started" position marker — NOT produced by this fan-out). The byte-frozen `contracts/`
was NOT touched.

## Raw output file paths

| Slice | gemini | codex |
|-------|--------|-------|
| LEGACY-DEBT (v50) | `council/v50.gemini.txt` (22 lines, substantive — per-item trace) | `council/v50.codex.txt` (38 lines, substantive — per-item trace) |

(Both models read source directly during exploration rather than strictly via the instructed
`git show a8b702a7:...` — fine for RAW capture; 394-03 re-reads the frozen source for every cite. Several
cite-drifts to reconcile at 394-03 are flagged in the leads below.)

---

## One-line characterization per model (RAW — not adjudicated)

- **v50.gemini:** **LEGACY-01 VERIFIED SOUND · LEGACY-02a VERIFIED SOUND · LEGACY-02b FINDING (SPINE).**
  gemini cleared the whale-pass O(1) path (value-equivalence of the materialized award + the
  `_applyWhalePassStats` `levelsToAdd`/`deltaFreeze≤100` no-double-dip; freeze-safety of the deposit-time
  `lootboxRngPacked` index snapshot; the clear-before-award single-shot + first-deposit-only enqueue) and
  the AFSUB pass-gating (the `currentLevel > validThroughLevel` inclusive boundary, the `_passHorizonOf`
  canonical horizon, the subscribe-time SUB-02 + OPENE-04 consent gates, the VAULT/SDGNRS-only `exemptSub`
  carve-out). It RAISED a FINDING on LEGACY-02b (MINTDIV): it claims the `processed` cursor is NOT persisted
  across a write-budget mid-queue stop (`processed` re-declared 0 each call @582/880 while `ticketCursor`
  persists only the player `idx` @703), so a player split across `advanceGame` chunks (e.g. chunk 1 takes
  `take=199`, a non-multiple of 4) resumes chunk 2 at `processed=0` — and since the quadrant offset
  `(uint8(i & 3) << 6)` @761 depends on the `processed` index `i`, the trait quadrant assignment becomes
  gas-/budget-split-dependent (a quadrant bias). gemini's verdict is RAW — its FINDING is a RAW lead, not a
  finalized adjudication.

- **v50.codex:** **LEGACY-01 FINDING (SPINE) · LEGACY-02a VERIFIED SOUND · LEGACY-02b VERIFIED SOUND.**
  codex cleared the AFSUB pass-gating (same convergent SOUND trace as gemini — the `currentLevel >
  validThroughLevel` inclusive boundary @1246, the crossing re-read/refresh/evict @1247-1264, the
  subscribe-time SUB-02 + OPENE-04 gates, the `operatorApprovals` storage backing) and — directly
  CONTRADICTING gemini — cleared LEGACY-02b MINTDIV as SOUND, explicitly noting `processed = 0` resets ONLY
  when `remainingOwed == 0` @672-676 (skip/cleanup paths reset before moving to the next player @597-618;
  `_processOneTicketEntry` writes exactly `take` traits + decrements owed by exactly `take`, returns
  `advance = remainingOwed == 0`) — so the write count equals the consumed ticket count across budget
  splits, no path advances by `writesUsed`, the next-player boundary is off-by-one clean. It RAISED a
  FINDING on LEGACY-01 (whale-pass): a DELAYED-MATERIALIZATION horizon drift — `whalePassClaims[player]`
  stores only a COUNT, not the open-time level, so an inline award would apply from OPEN-time `level+1` while
  the deferred `claimWhalePass` applies from CLAIM-time `level+1` @1003; if nobody claims before `level`
  moves, the player receives 100 FUTURE levels instead of the originally-opened 100-level window. codex
  itself notes the box enqueue half is freeze-safe + single-enqueue (the SOUND subpart). codex's verdict is
  RAW — its FINDING is a RAW lead, not a finalized adjudication.

**The two FINDINGS are DIVERGENT and CROSS-CONTRADICTING — this is the highest-value outcome of the
fan-out:**
- On **LEGACY-01** the models SPLIT: gemini SOUND vs codex FINDING (delayed-materialization horizon drift).
- On **LEGACY-02b** the models SPLIT the OTHER way: gemini FINDING (quadrant bias via `processed` reset) vs
  codex SOUND (reset only at `remainingOwed == 0`).
- On **LEGACY-02a** the models CONVERGE: both VERIFIED SOUND.

The two splits are exactly the prime targets this slice charged HARD, and they require the skeptic dual-gate
([[feedback_skeptic_pass_before_catastrophe]]) at 394-03 against the FROZEN source — a SPINE elevation must
survive the structural-protection + value lens. The cross-contradiction (each model SOUND on the item the
OTHER flagged) is the ideal adjudication input: 394-03 can pit each model's specific trace against the
other's and against the code.

---

## Raw council leads routed to 394-03 Wave-2 adjudication (NOT adjudicated here)

The council net is on record. The following are the RAW leads/divergences for 394-03 to fold in against the
Claude net before any per-item verdict and the deferred `audit/FINDINGS-v50.0.md`.

1. **PRIORITY — DIVERGENT on LEGACY-01: codex FINDING (delayed-materialization horizon drift) vs gemini
   SOUND (value-equivalent).** codex asserts `whalePassClaims[player]` stores only a COUNT (written at
   `_activateWhalePass` `whalePassClaims[player] += 1`, `DegenerusGameLootboxModule.sol:1486-1489`, called
   from the boon-type-28 path @1899-1901), and `claimWhalePass` recomputes `startLevel = level + 1` @1003
   from the LIVE `level` at CLAIM time — so a player who opens at level L but does not claim until level L'>L
   receives a window starting at L'+1 (100 future levels) instead of the open-time L+1 window an inline award
   would have given. **CRITICAL ANCHOR for 394-03:** there is a directly-relevant code comment at
   `DegenerusGameLootboxModule.sol:1483` — "D-04 — timing shifts from open-time [...]" on the
   `_activateWhalePass` doc — which suggests the claim-time horizon may be DOCUMENTED INTENT (a v50 design
   decision D-04), NOT an accidental drift. gemini, by contrast, cleared the SAME path as value-equivalent,
   reasoning the ticket-count arithmetic + `_applyWhalePassStats` (`levelsToAdd`/`deltaFreeze≤100`)
   replicate the inline award's economic weight. **394-03 MUST: (a) read the `_activateWhalePass` D-04 doc
   @1483-1489 + the `claimWhalePass` `startLevel = level+1` @1003 at the frozen source and settle whether the
   claim-time horizon is DOCUMENTED INTENT (D-04 by-design — the deferred design KNOWINGLY shifts the
   horizon to claim time) or an accidental value-non-equivalence; (b) if intent, confirm there is no
   value-EXTRACTION edge (a later claim is generally NEUTRAL/beneficial-to-the-player — future levels are
   the SAME 100-level span, and the pass is rated near-worthless [[degenerette-wwxrp-rtp-by-design]], so the
   bound governs severity); (c) apply the skeptic 3-condition-EV lens — is a player-chosen claim-timing a
   material EV edge given the lootbox/claim TIMING-is-not-a-player-edge by-design ruling
   [[lootbox-resolution-timing-by-design]], or is it the inert claim-timing the ruling already covers?**
   The two models directly contradict; the D-04 comment is the load-bearing tie-breaker.

2. **PRIORITY — DIVERGENT on LEGACY-02b (MINTDIV): gemini FINDING (quadrant bias via `processed` reset) vs
   codex SOUND (reset only at `remainingOwed == 0`).** gemini claims `processed` is re-declared 0 each call
   (`MintModule:582`/`:880`) and NOT persisted across a write-budget split, so a player's traits after a
   mid-queue stop resume at `processed=0`, and because the quadrant offset `(uint8(i & 3) << 6)` @761
   depends on `i = processed`, the 200th ticket (intended quadrant 3) is written as quadrant 0 → a
   gas-/budget-split-dependent quadrant bias. codex DIRECTLY REFUTES this: `processed = 0` resets ONLY when
   `remainingOwed == 0` @672-676 (the player is FULLY finished, `++idx` to the next player), the skip/cleanup
   resets @597-618 also fire only before moving to the next player, and `_processOneTicketEntry` advances
   `processed += take` / resets only on `advance = remainingOwed == 0` @893-904 — so a PARTIAL player
   (write-budget exhausted mid-player) does NOT reset `processed`, and the persisted `owedMap[player]`
   remainder + the re-entered loop resume at the correct trait offset. **394-03 MUST trace the `processed`
   cursor across a REAL budget-split boundary at the frozen source and settle the contradiction:** does a
   PARTIAL player (`take < owed`, `remainingOwed > 0`) persist `remainingOwed` to `owedMap[player]`
   @663-666 and END the call with `processed = take_1` (gemini's worry), and does the NEXT call for the SAME
   player re-enter with `processed = 0` BUT `owed = remainder` so the write resumes at the right offset
   (codex's defense) — i.e. is the quadrant index `i` keyed on the WITHIN-CALL `processed` (which resets)
   or on a persistent absolute trait offset? **The crux: does `_raritySymbolBatch`'s quadrant `i` track the
   ABSOLUTE ticket position (so a reset corrupts it — gemini) or does the `baseKey`/`owed`-derived offset
   already make the resumed batch write the correct quadrants (codex's "baseKey correctly includes owed,
   ensuring the PRNG seed remains distinct" — but gemini's point is the QUADRANT SHIFT, distinct from the
   PRNG seed)?** Reconstruct or extend the MINTDIV cross-path-equality oracle (Phase 336 green coverage,
   carried in `test/REGRESSION-BASELINE-v63.md`) to FORCE a budget split mid-player at a non-multiple-of-4
   `take` and assert the trait quadrant assignment is split-invariant. This is the single most material
   contract-change-candidate lead from the council (a SPINE value-non-equivalence if gemini is right; a
   non-finding if codex is right).

3. **CONVERGENT SOUND on LEGACY-02a (AFSUB pass-gating + OPEN-E consent) — re-attest against the Claude
   net.** BOTH gemini and codex VERIFIED SOUND with convergent traces: the `currentLevel >
   sub.validThroughLevel` inclusive boundary @1246 (keep while `<=`, evict at +1 — the documented intended
   leniency, NOT flagged); the crossing re-read `_passHorizonOf(player)` @1247 → refresh if `currentLevel
   <= h` @1248-1250 else finalize/delete/swap-pop @1252-1264; the `_passHorizonOf` canonical horizon
   (deity sentinel `type(uint24).max` / else `frozenUntilLevel`) @596-605; the subscribe-time SUB-02
   self-consent / `operatorApprovals[subscriber][msg.sender]` @314-320 + OPENE-04 non-self `fundingSource`
   `operatorApprovals[fundingSource][subscriber]` @322-330 (checked at subscribe ONLY); the `exemptSub`
   carve-out strictly VAULT/SDGNRS @415-416. **394-03 should re-attest against the Claude net; convergent
   council SOUND (×2 models) + Claude SOUND = both-nets-on-record for a no-finding verdict on LEGACY-02a.**

4. **CONVERGENT SOUND on the LEGACY-01 box-open record half (the enqueue/freeze subpart) — re-attest.**
   Even though the models DIVERGE on the whale-pass CLAIM half, BOTH agree the box-open RECORD half is
   freeze-safe + single-enqueue: `_recordLootboxEntry` snapshots `lootboxRngPacked` once @850 and derives
   `index` @851; first-deposit-only `boxPlayers[index].push` (`existingAmount == 0`); subsequent deposits
   reuse the FROZEN packed record; the `LootBoxBuy` event @931 carries the same index; the consumer gates on
   `lootboxRngWordByIndex[index] != 0` (codex cited `LootboxModule:681-682` + the `_openLootBoxLegWith`
   zero-word revert @545). **394-03 re-attest this enqueue/freeze subpart against the Claude net** — the
   DIVERGENCE is isolated to the CLAIM-time horizon (lead 1), not the box record.

5. **Cite-drifts to reconcile at 394-03 (NOT findings — bookkeeping; 394-03 re-reads the frozen source for
   every cite regardless).**
   - gemini cited the MINTDIV index advance at `MintModule:930` (the cross-path `_processOneTicketEntry`
     caller path) AND @668 (the future-ticket loop) — the authoritative loop cite is @668, the cross-path
     `processed += take` is @903; pin both at the frozen source.
   - gemini cited `_applyWhalePassStats` at `Storage:1338` (`levelsToAdd`/`deltaFreeze` logic) — confirm the
     stat-apply line at the frozen source (the prompt cited `_applyWhalePassStats` @1005 as the WhaleModule
     call site; the implementation may live in storage/a helper).
   - codex cited `whalePassClaims` storage at `DegenerusGameStorage.sol:1107`, live `level` at
     `Storage:237`, `operatorApprovals` at `Storage:1119`, `Sub.validThroughLevel` at `Storage:2162-2166`,
     `ticketsOwedPacked` at `Storage:489-491`, and the `_processOneTicketEntry` helper trait-write at
     `MintModule:993-1023` — pin each at the frozen source (the prompt cited `_processOneTicketEntry`
     definition @951; codex's @993-1023 is the body).
   - codex cited the boon-type-28 whale-pass activation at `LootboxModule:1899-1901` and `_activateWhalePass`
     @1486-1489 with the D-04 timing comment @1483 — these resolve at the frozen source (verified: the
     `_activateWhalePass` doc @1483 + `whalePassClaims[player] += 1` @1489 + the type-28 caller @1901), the
     load-bearing anchor for lead 1.

---

## Byte-freeze attestation (after the council fan-out)

Immediately after the fan-out, verified the subject was not mutated:

- `git diff a8b702a7 -- contracts/` → **EMPTY** (0 diff lines; subject byte-frozen; the council writes only
  its model output under `council/`).
- `git status --porcelain contracts/` → **EMPTY** (no working-tree contract change).
- Full-tree `git status --porcelain` shows only the pre-existing untracked `PLAYER-PURCHASE-REWARDS.html`
  and the prior-session `.planning/STATE.md` position-marker edit — **neither produced by this fan-out**;
  the council wrote no stray file anywhere ([[feedback_verify_writecapable_agents]] — verified clean).

The council ran in read-only wrappers (`ask-gemini.sh --approval-mode plan`; `ask-codex.sh --sandbox
read-only`) and produced output only under `.planning/phases/394-legacy-debt/council/`. **T-394-01**
(tampering of the byte-frozen subject) mitigation satisfied. **T-394-02** (a slice silently treated as
on-record with BOTH CLIs unavailable) does NOT apply — BOTH gemini AND codex are available with real audits;
`skipped[]` is empty; **no post-reset codex re-run is owed for THIS slice** (the codex usage limit has reset
this run). **T-394-03** (scope-drift / re-litigating documented intent) mitigation satisfied — the prompt
carried the KNOWN-BY-DESIGN list, and both models' FINDINGS are genuine PROPERTY-break claims (a
delayed-materialization horizon drift + a budget-split quadrant bias) on the charged prime targets, not
desirability complaints — they are routed to 394-03 for the skeptic dual-gate against the frozen source.
**T-394-SC** (`hardhat compile --force` regenerating ContractAddresses source) avoided — only `git show` /
read tools touched the subject.

---

## NOTE — carry-forward status (the 396 codex re-run debt)

This slice did NOT add to the post-reset codex re-run debt — codex was AVAILABLE and on record here. The
EXISTING carry-forward to 396 (the post-reset codex second-source of the 392 BURNIE-04/-05 + 393
ACCESS-02/-04 gemini SOUND verdicts, recorded when codex was capped at those slices) STILL stands and is
unaffected by this slice. **OPPORTUNITY:** because the codex usage limit has reset (confirmed by this slice's
successful codex run), the 392/393 codex second-source re-runs MAY now be runnable opportunistically — flag
this observation to 396 / the milestone close so the carried codex re-runs can be picked up while the limit
holds.
