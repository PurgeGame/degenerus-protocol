# 391-01 — NET 1 (Cross-Model Council) Capture Record — RNG-FREEZE SPINE (RNG-01..06)

**Subject (byte-frozen):** `a8b702a7` (contracts tree `2934d3d8987a09c5f073549a0cb499f6c5f28620`).
**Net:** NET 1 = the cross-model council (external `gemini` + `codex` CLIs via `council.sh`).
**Purpose:** per AUDIT-V63-PLAN §2, a no-finding verdict for any sweep slice requires BOTH nets on
record. RNG/freeze is the DOMINANT threat class (§4 threat weighting) — a confirmed RNG-manipulability or
freeze break is the highest-severity class — and the council is the PRIMARY finder
([[cross-model-led-audits-over-claude-only]] — the council caught the V62-01 / RNGRETRY / RNGREUSE classes
a Claude-only pass missed). This record puts NET 1 on record for the RNG-FREEZE spine so the Wave-2
Claude-net + adjudication plan (391-02) can fold the council leads in BEFORE any per-item verdict. RAW
capture only — NOT adjudicated, refuted, or fixed here (adjudication is 391-02).

---

## NET 1 ON RECORD for RNG-FREEZE

The RNG-FREEZE slice was fanned to BOTH council models; **0 CLIs skipped**. Every RNG-01..06 thesis point,
every FC-391-01..05 owned lead, and the inherited cross-refs (FC-389-05 decimator-uint32 RNG-consumption
half, FC-392-11 coinflip-carry RNG-lock half) received a traced response from BOTH models. The slice has
both council models on record (`skipped[]` empty) — the both-unavailable re-run condition does NOT apply.

## Council manifest (available / skipped)

| Slice | Label | council.json | Available models | Skipped models |
|-------|-------|--------------|------------------|----------------|
| RNG-FREEZE | `rng` | `council/rng.council.json` | `gemini`, `codex` | (none) |

Council runner: `.planning/audit-v52/cross-model/bin/council.sh` (read-only wrappers — `ask-gemini.sh`
`--approval-mode plan`; `ask-codex.sh` `--sandbox read-only`; the models may
`git show a8b702a7:contracts/<File>.sol` but cannot mutate). No `--schema` was passed → free-text `.txt`
outputs. ONE slice = ONE fan-out (gemini + codex run in parallel internally), so the single-invocation
pacing rule ([[pace-runs-to-survive-5h-cap]]) is satisfied. Both wrappers exited 0
(`council.sh` exit 0; `rng.gemini.err` + `rng.codex.err` both 0 bytes).

## Raw output file paths

| Slice | gemini | codex |
|-------|--------|-------|
| RNG-FREEZE | `council/rng.gemini.txt` (54 lines) | `council/rng.codex.txt` (27 lines) |

(`council/rng.gemini.err` + `council/rng.codex.err` hold the per-model stderr; both 0 bytes — both models
exited 0.)

---

## One-line characterization per model (RAW — not adjudicated)

- **rng.gemini:** **VERIFIED SOUND across ALL of RNG-01..06** with backward-traced commitment points —
  RNG-01 freshness (bets bound to `lootboxRngIndex` + `betId` at placement, placement reverts if the
  index word is already on-chain; decimator winners from the full word at resolution; redemption burn
  gated on `rngWordForDay(currentPeriod) != 0` with `day+1` undrawn); RNG-02 decimator 32-bit SOUND (the
  per-player `hash2(word, address)` keccak diffusion makes shared-32-bit outcomes independent + uniform
  across the winning population, non-grindable because the word is drawn after address commitment);
  RNG-03 one-shot (record zeroed `LootboxModule:579`, bet deleted `DegeneretteModule:646`, decimator
  `e.claimed=1` @398 before the lootbox award); RNG-04 domain-separation airtight via the per-caller
  terms; RNG-05 day+1 gate SOUND; RNG-06 SLOAD freeze-invariant (activityScore frozen-snapshot,
  EntropyLib byte-identical). gemini noted some boon-interpretation live reads (`level`, `decWindowOpen`)
  but classified them as the documented by-design timing edge, NOT a freshness break. gemini stopped at
  the research stage and asked for confirmation before drafting a formal report — its SOUND verdicts are
  RAW, NOT a finalized adjudication. **0 findings.**

- **rng.codex:** **One INFO/LOW FINDING + VERIFIED SOUND on everything else.** The finding is on
  **RNG-04 / FC-391-01** — a CROSS-ROUND `uint32` claim-seed collision for decimator claims: because
  `resolveLootboxDirect` dropped `amount` (seed = `hash2(round.rngWord, uint160(player))`,
  `LootboxModule:883`) AND `round.rngWord` is narrowed to `uint32` (`DecimatorModule:277`), if the same
  player `P` wins at two decimator levels `L` and `L2` where `uint32(VRF_L2) == uint32(VRF_L)`, the two
  direct-lootbox claim seeds are IDENTICAL (same outcome). The old `amount` term would have separated
  claims with different lootbox portions; the current seed carries no level/round/amount domain. codex
  explicitly classifies this as **INFO/LOW, NOT a freeze/manipulability break** — the later low-32 VRF
  word is unknown at burn time so the player cannot steer it, and `e.claimed=1` (@399) prevents same-round
  replay (it does NOT prevent the cross-round 32-bit equality). codex VERIFIED SOUND on RNG-01 (commitment
  binds to the index before the word is written), RNG-02 (full-word winner selection + per-address
  random-oracle separation under the shared 32-bit salt, non-grindable), RNG-03 (record-clear / bet-delete
  / box-spin delegatecall guards), the BURNIE survival-flip accumulator (the spin payout is added to
  `acc.burnieMint` BEFORE the survival branch can subtract the same bet's `totalPayout` — no cross-bet
  transient underflow), RNG-05 (burn reverts under daily RNG lock + requires the current wall-day word;
  backfill writes up to the current wall day, not `currentPeriod + 1`, so the burn cannot stamp a day
  whose next word is already on-chain), the coinflip carry RNG-lock (FC-392-11 half — the daily request
  sets `rngLockedFlag=true`, the callback stores the word while keeping the lock, unlock after processing;
  `claimCoinflipCarry` checks `rngLocked()` before reading `autoRebuyCarry`), and RNG-06 (the enumerated
  slots confirmed against `RngWindowFreezeHandler:66-71`; `hash2`/`hash1` byte-identical preimages; box-spin
  `activityScore` threaded from packed/frozen records, not a live read).

---

## Raw council leads routed to 391-02 Wave-2 adjudication (NOT adjudicated here)

The council net is on record. The following are the RAW leads/divergences for 391-02 to fold in against
the Claude net before any verdict:

1. **CONVERGENT-DIVERGENCE on RNG-04 / FC-391-01 — cross-round `uint32` decimator claim-seed collision
   (codex INFO/LOW finding vs gemini SOUND).** This is the single material cross-model divergence on the
   slice and the PRIORITY item for 391-02. codex asserts that the COMBINATION of the dropped `amount` term
   (`LootboxModule:883`) AND the `uint32` narrowing (`DecimatorModule:277`) means a single player winning
   at two decimator levels `L`/`L2` with `uint32(VRF_L2) == uint32(VRF_L)` gets IDENTICAL direct-lootbox
   claim seeds — `e.claimed=1` (@399) only blocks same-round replay, not the cross-round 32-bit equality.
   gemini, examining the SAME surface, ruled RNG-04 domain-separation "airtight" (it reasoned within ONE
   level / one claim, where the per-caller term + the player address separate concurrent claims, and did
   NOT consider the cross-LEVEL `uint32`-collision case). **391-02 MUST re-read the decimator claim path at
   `a8b702a7`** (`_claimDecimatorJackpotFor:385-411`, the `round.rngWord = uint32(rngWord)` write @277, and
   `resolveLootboxDirect:883`) and settle: (a) is the cross-round identical-seed outcome actually a
   freshness/manipulability concern, or purely a benign correlation (the player cannot CHOOSE either
   `uint32` word, both fixed by VRF after their burn commitment, and the claim cannot redirect value)? (b)
   what is the realized probability and impact — a `~1/2^32` per-level-pair collision for one player, on a
   per-claim LOOTBOX tier outcome (BURNIE-credit-adjacent, off the ETH/`claimablePool` spine), with NO
   player control over either word? Apply the skeptic dual-gate (structural-protection + 3-condition EV
   lens [[feedback_skeptic_pass_before_catastrophe]]) BEFORE elevating: codex itself rated this INFO/LOW
   and explicitly "not a freeze/manipulability break". Both the §6-prime RNG-02 distribution concern AND
   this RNG-04 cross-round item touch the SAME two narrowings (dropped `amount` + `uint32`) — 391-02 should
   adjudicate them together. If CONFIRMED material at source after the skeptic gate it routes to a gated
   USER-hand-review (a doc-only KNOWN-ISSUES entry is the likely disposition for an INFO/LOW
   no-player-control correlation); if refuted, both-nets-on-record for RNG-04.

2. **The §6-PRIME RNG-02 / FC-391-04 decimator 32-bit distribution-bias target — BOTH models VERIFIED
   SOUND with a real distribution argument (not a hand-wave).** This was the dedicated prime target the
   ORACLE-HOLES audit flagged as the MISSING distribution property. gemini: the per-player address mixing
   `hash2(word, address)` with keccak full diffusion makes outcomes independent + uniform across the
   winning population — sharing a 32-bit component does not correlate distinct addresses' results; the word
   is drawn AFTER address commitment so non-grindable. codex: winner selection uses the FULL word before
   the storage narrowing (`DecimatorModule:241-269`); claim outcomes are `keccak256(32-byte word, 32-byte
   address)` so distinct winner addresses are distinct random-oracle inputs under the same 32-bit salt;
   claim order is non-grindable (credits `player`, marks `e.claimed`, cannot redirect value). **391-02
   should re-attest this against the Claude net + the planned distribution/grinding oracle (RNG-02);
   convergent council SOUND + Claude SOUND + an exercising oracle = both-nets-on-record for a no-finding
   verdict on the prime target.** NOTE the interaction with item 1 — the SAME `uint32` floor that both
   models call distribution-SOUND within a level is what codex flags as a cross-LEVEL seed-collision; the
   adjudication must reconcile "uniform/independent across a level's population" (both SOUND) with
   "identical across two levels for one player at `uint32` equality" (codex's INFO/LOW).

3. **All remaining RNG-01 / RNG-03 / RNG-05 / RNG-06 thesis points + FC-391-02/-03/-05 + the inherited
   cross-refs FC-389-05 and FC-392-11 — VERIFIED SOUND by BOTH models** with source traces at `a8b702a7`.
   391-02 should confirm these against the Claude net; convergent council SOUND + Claude SOUND =
   both-nets-on-record for a no-finding verdict on those items. Key convergent SOUND anchors for 391-02 to
   re-attest: RNG-01 commitment-before-word (placement binds the index + reverts on an already-worded
   index; redemption burn gated on the current-day word with `day+1` undrawn); RNG-03 one-shot
   (record-zero `LootboxModule:578-580`, bet `delete` `DegeneretteModule:655`, decimator `e.claimed=1`
   before the award; box-spin `address(this) == GAME` guards @1298/@1353/@1408); FC-391-03 survival-flip
   accumulator (spin payout added to `acc.burnieMint` BEFORE any survival subtraction — no cross-bet
   transient underflow); RNG-05 day+1 gate (burn under daily-RNG-lock + current-wall-day word required;
   backfill never writes `currentPeriod + 1`); FC-392-11 coinflip-carry RNG-lock (request sets the lock,
   callback stores the word while locked, `claimCoinflipCarry` checks `rngLocked()` before reading the
   carry); RNG-06 SLOAD enumeration + EntropyLib byte-identity + frozen `activityScore`. One gemini
   observation to confirm-not-elevate: some boon-interpretation reads (`level`, `decWindowOpen`) are live
   but afford only the documented by-design timing edge (a player choosing WHEN to resolve an
   already-fixed outcome — [[lootbox-resolution-timing-by-design]]), not a freshness break — 391-02 should
   confirm this matches the by-design ruling and is not a new live-input-into-seed path.

---

## Byte-freeze attestation (after the council fan-out)

Immediately after the fan-out, verified the subject was not mutated:

- `git diff a8b702a7 -- contracts/` → **EMPTY** (subject byte-frozen; council writes only to its out-dir).
- `git status --porcelain contracts/` → **EMPTY** (no working-tree contract change).

The council ran in read-only wrappers (`ask-gemini.sh --approval-mode plan`; `ask-codex.sh --sandbox
read-only`) and produced output only under `.planning/phases/391-rng-spine/council/`. T-391-01 (tampering
of the byte-frozen subject) mitigation satisfied. T-391-02 (a slice silently treated as on-record with
both CLIs unavailable) does not apply — both CLIs were available (`skipped[]` empty); the
both-unavailable re-run-and-surface condition is not triggered.
