# 392-01 — NET 1 (Cross-Model Council) Capture Record — ENTROPY-AND-ECON / reward game-theory (ECON-01..06)

**Subject (byte-frozen):** `a8b702a7` (contracts tree pin `2934d3d8987a09c5f073549a0cb499f6c5f28620`).
**Net:** NET 1 = the cross-model council (external `gemini` + `codex` CLIs via `council.sh`).
**Purpose:** per AUDIT-V63-PLAN §2, a no-finding verdict for any sweep slice requires BOTH nets on
record. ECON is the reward game-theory dimension — a closed positive-EV money pump (ECON-04) is HIGH, and
the scarce-asset whale-pass channel (ECON-05) + bounded-accrual (ECON-01) touch value-bearing invariants.
The council — the PRIMARY finder ([[cross-model-led-audits-over-claude-only]]) — goes on record FIRST so
the Wave-2 Claude-net + adjudication plan (392-03) can fold the council leads in BEFORE any per-item
verdict. RAW capture only — NOT adjudicated, refuted, or fixed here (adjudication is 392-03).

---

## NET 1 ON RECORD for ECON

The ECON slice was fanned to the council via `council.sh --label econ`. **One model (`gemini`) is on record
with a substantive traced audit; `codex` is in `skipped[]`** — `codex` hit a HARD usage-limit cap
("You've hit your usage limit ... try again at 11:56 PM"), not a transient/timeout error, so a re-run is
not possible until the limit resets. Per the plan's both-unavailable rule, a SINGLE available model with
real content satisfies "council on record" with the skip documented (T-392-02: a slice silently treated as
on-record with BOTH CLIs unavailable would be surfaced for re-run — that condition does NOT apply here,
because gemini IS on record with a real answer). The codex skip is recorded faithfully in
`econ.council.json` `skipped[]` + `skip_reasons` and is carried to 392-03 as a coverage note (re-run codex
opportunistically at 392-03 / 396 once the limit resets to second-source the gemini leads).

## Council manifest (available / skipped)

| Slice | Label | council.json | Available models | Skipped models |
|-------|-------|--------------|------------------|----------------|
| ENTROPY-AND-ECON | `econ` | `council/econ.council.json` | `gemini` (real audit) | `codex` (usage-limit cap — hard, not transient) |

Council runner: `.planning/audit-v52/cross-model/bin/council.sh` (read-only wrappers — `ask-gemini.sh`
`--approval-mode plan`; `ask-codex.sh` `--sandbox read-only`). No `--schema` was passed → free-text `.txt`
output. ONE slice = ONE fan-out (gemini + codex run in parallel internally), so the single-invocation
pacing rule ([[pace-runs-to-survive-5h-cap]]) is satisfied.

**Fan-out narrative (recorded for audit-trail integrity):**
- `council.sh` first fan-out: `codex` SKIPPED (rc captured; `/tmp/ask-codex.err` = usage-limit cap);
  `gemini` returned an EMPTY answer (a single newline byte) on the first attempt — the wrapper swallows
  gemini stderr (`2>/dev/null`), so an aborted/empty `$RAW` was written as a 1-byte file that passes the
  `-s` non-empty test (a false-green the manifest would have recorded as "available").
- A liveness probe confirmed `gemini` is live (a tiny prompt returned `PONG`). A DIRECT gemini re-run of
  the SAME `392-01-COUNCIL-PROMPT-ECON.md` produced the SUBSTANTIVE audit captured in `econ.gemini.txt`.
  The re-run process exited `rc=124` (timeout) ONLY on gemini's trailing tool step (it tried to WRITE a
  report file, which `--approval-mode plan` read-only blocked) — the full audit answer had ALREADY been
  emitted to stdout BEFORE the timeout, so the captured `econ.gemini.txt` is the complete model verdict.
- `econ.council.json` was regenerated to reflect the real post-re-run state (gemini available with real
  content; codex skipped with reason).

**Write-capable-agent verification ([[feedback_verify_writecapable_agents]]):** the gemini re-run, despite
`--approval-mode plan`, wrote ONE stray file OUTSIDE the council out-dir — `test/repro/StreakPumpRepro.test.js`
(a hardhat repro for its streak-pump finding). The byte-frozen subject `contracts/` was NOT touched. The
stray repro was REMOVED (single specific path; not a blanket clean) — its content is captured as a RAW lead
below (lead 1) for 392-03 to adjudicate; the file itself is not a planned output. gemini did NOT create the
`plans/reward-economics-audit.md` it claimed to draft (read-only mode held for that path).

## Raw output file paths

| Slice | gemini | codex |
|-------|--------|-------|
| ENTROPY-AND-ECON | `council/econ.gemini.txt` (21 lines, substantive) | (skipped — no output; `council/econ.codex.err` = wrapper skip notice; `/tmp/ask-codex.err` = the usage-limit banner) |

(`council/econ.gemini.err` holds the gemini re-run stderr — the `Ripgrep not available → GrepTool` notice +
the `Error executing tool read_file: File not found` it hit while exploring before falling back. `gemini`
read source via `read_file`/`GrepTool` exploration rather than the instructed `git show a8b702a7:...`, so
its cites are working-tree-derived — fine for RAW capture; 392-03 re-reads the frozen source for every cite.)

---

## One-line characterization per model (RAW — not adjudicated)

- **econ.gemini:** **Two HIGH candidate findings + VERIFIED SOUND on ECON-02 / ECON-05 / ECON-01.** gemini
  raised (1) a streak-pump via afking↔manual toggling on the same day (a double-channel breaching the
  ≤3/day rate bound, ECON-06/ECON-01), and (2) a claimed repeatable positive-EV money pump from the 100%
  neutral-EV lootbox floor STACKED with the 10% recycle-bonus kicker (asserting the 10-ETH benefit cap only
  bounds the uplift ABOVE 100%, leaving floor + bonus uncapped, ECON-04). It VERIFIED SOUND on the
  redistribution arithmetic (ECON-02: the 40/15/15/15/10/5 split, the 19,678-bps ticket budget, the
  far/near weighting), the whale-pass supply cap (ECON-05: the `wwxrpJackpotWhalePassBracketAwarded` flag
  enforces one-per-bracket across all channels), and the accrual ceilings (ECON-01: ROI / decimator / EV
  consumers all hard-saturate, preventing unbounded accrual from high streaks). gemini's verdict is RAW —
  it stopped to ask "do you agree with this strategy?" before drafting a formal report, so its HIGH
  candidates are RAW leads, NOT a finalized adjudication.

- **econ.codex:** **NO OUTPUT (skipped — usage-limit cap).** Not a refusal or a classifier trip; a hard
  account cap. Carried to 392-03/396 for an opportunistic second-source re-run once the limit resets.

---

## Raw council leads routed to 392-03 Wave-2 adjudication (NOT adjudicated here)

The council net is on record. The following are the RAW leads/divergences for 392-03 to fold in against the
Claude net before any verdict. **Both gemini HIGH candidates land on the EXACT prime targets this slice
charged HARD (the money-pump search + the streak rate-bound) — they require the skeptic dual-gate
([[feedback_skeptic_pass_before_catastrophe]]) at 392-03 because the surface maps + the PAPER brief both
assess these specific surfaces as EV-neutral/bounded by-design; a HIGH elevation must survive the
structural-protection + 3-condition-EV lens against the FROZEN source.**

1. **PRIORITY — gemini HIGH candidate: positive-EV money pump = 100% neutral-EV lootbox floor + 10%
   recycle-bonus kicker (ECON-04 / break-target 1 + FC-392-06).** gemini asserts that a player at activity
   score ≥6,000 (where the EV multiplier = 100% neutral) recycles claimable into boxes at ~100% expected
   return AND collects the 10% recycle kicker as "pure profit", forming a repeatable ≥110%-RTP loop; it
   claims the 10-ETH benefit cap bounds ONLY the uplift ABOVE 100%, leaving the floor + bonus uncapped.
   **392-03 MUST re-read the frozen source and apply the per-leg value accounting the prompt demanded:**
   (a) is the recycle kicker's 10% paid as ILLIQUID BURNIE flip-credit that must SURVIVE a coinflip before
   it mints (valued below the 0.59:1 peg), so the realized output << the nominal 10% (the surface map's
   refutation — `reward-economics.md` §3, [[intended-game-mechanics-not-findings]])? (b) is the recycled
   spend's box EV genuinely 100% at score 6,000, or is the DIRECT-open lootbox EV sub-100% (the prompt's
   point (b) — boxes pay their own EV, not a guaranteed 100% return; the 100% multiplier scales a sub-unity
   base budget)? (c) does claimable have to be WON first (a positive-variance event) before it can be
   recycled, so the "loop" is seeded by a prior win, not a closed cycle? gemini did NOT show the per-leg
   wei accounting the prompt required (illiquidity + flip-survival + sub-100% direct EV) — its claim is a
   STRUCTURAL assertion that the cap doesn't cover the floor, NOT a traced repeatable cycle with value-out
   > value-in net of illiquidity. **This is the single most material lead; adjudicate it against the frozen
   `_applyEvMultiplierWithCap` (LootboxModule:474), the recycle kicker (MintModule:1740-1744), and the
   actual realized BURNIE-credit value BEFORE any HIGH elevation.** If the kicker output is illiquid/
   flip-gated and the box direct EV is sub-100%, the loop is value-LOSING (the map's verdict) → refuted; if
   gemini's "uncapped floor + bonus = pure profit" survives the per-leg accounting at source, it elevates
   to a gated USER-hand-review.

2. **gemini HIGH candidate: streak-pump via afking↔manual same-day toggling (ECON-06 / ECON-01 /
   break-target 4 / FC-392-01 + FC-392-02).** gemini asserts a player toggling between afking and manual
   modes on the same day harvests a streak increment from an afking delivery AND a second increment from a
   manual slot-0 mint, because afking deliveries don't update the manual `completionMask` — breaching the
   intended ≤3/day rate bound and reaching the activity-score ceiling (and high EV multiplier) faster than
   designed. **392-03 MUST re-read `_questCompleteWithPair` (~1700-1760, the `afking` branch that SKIPS the
   manual +1 for slot 0), `recordAfkingSecondary` (GameAfkingModule:1714), and the decay anchors
   (`lastActiveDay`/`lastCompletedDay`, updated only on slot 0) at the frozen source and settle:** (a) does
   the `afking` branch's slot-0 skip already PREVENT the double-count gemini describes (the surface map's
   FA-2 hypothesis is that it does — "the primary is supposed to be streak-neutral while afking")? (b) even
   if a transient +2 lands on one day, does the next-day DECAY zero it when the primary is then skipped
   (FA-1's question), making it a bounded/self-correcting bump rather than a persistent ceiling-breach? (c)
   what is the REALIZED magnitude — the ceiling is UNCHANGED (every consumer saturates below the 65,534 cap;
   the streak only shortens time-to-ceiling), so even a confirmed double-count is a ramp-SPEED gaming, not a
   ceiling-breach — apply the skeptic 3-condition-EV lens (is the faster ramp materially harmful given the
   ceilings are fixed?). Likely disposition spectrum: bounded/decay-corrected → INFO/LOW or doc-only;
   persistent un-decayed bypass of the daily-primary gate that materially accelerates max-EV access →
   gated USER-hand-review. NOTE gemini's repro (`StreakPumpRepro.test.js`, removed) asserted "+2 in one
   day" — 392-03 can reconstruct an equivalent oracle to empirically confirm/refute against the frozen
   contracts.

3. **gemini VERIFIED SOUND — ECON-02 (redistributions), ECON-05 (whale-pass supply), ECON-01 (accrual
   ceilings) — re-attest against the Claude net.** gemini confirmed the Class-A redistribution arithmetic
   (the 40/15/15/15/10/5 split, the 19,678-bps ×11/9 ticket budget, the far/near weighting), the
   whale-half-pass one-per-bracket supply (the `wwxrpJackpotWhalePassBracketAwarded` global flag enforces
   the cap across all acquisition channels — directly addressing break-target 2 / FC-392-07's supply half),
   and the downstream accrual ceilings (ROI / decimator / EV saturate, so high streaks cannot accrue
   unbounded — break-target 8 / the ECON-01 bounded-accrual sweep). **392-03 should re-attest these against
   the Claude net; convergent council SOUND + Claude SOUND = both-nets-on-record for a no-finding verdict
   on these items.** gemini did NOT separately characterize the remaining charged targets — the
   whale-pass ACQUISITION-COST quantification (P(S==9) × boxes-per-pass, the cost-curve half of
   break-target 2), the redemption ETH-spin value-extraction surface (break-target 3 / FC-392-08, the
   cap-re-earn-across-chunks + the EV-uplift-beyond-bound half; the solvency half is 390's), the EV-cap
   bound under composed paths (break-target 5 / FC-392-05/-06/-09), the decimator-ramp / stale-comment /
   BoxSpin-sentinel items (break-target 6 / FC-392-03/-04/-10), and the affiliate-composition leads
   (break-target 7 / FC-392-14/-15). **These charged targets received NO explicit council verdict (the
   codex skip + gemini's selective summary) and are therefore CARRIED to 392-03 as Claude-net-primary items
   — the council coverage is gemini-only and partial on the non-prime targets.** A codex re-run at 392-03/
   396 (post-limit-reset) is the recommended second-source for these.

---

## Byte-freeze attestation (after the council fan-out)

Immediately after the fan-out (and after removing the stray gemini repro artifact), verified the subject
was not mutated:

- `git diff a8b702a7 -- contracts/` → **EMPTY** (subject byte-frozen; the council writes only its model
  output; the one stray gemini artifact was OUTSIDE `contracts/` and was removed).
- `git status --porcelain contracts/` → **EMPTY** (no working-tree contract change).

The council ran in read-only wrappers (`ask-gemini.sh --approval-mode plan`; `ask-codex.sh --sandbox
read-only`) and produced output under `.planning/phases/392-entropy-and-econ/council/`. **T-392-01**
(tampering of the byte-frozen subject) mitigation satisfied. **T-392-02** (a slice silently treated as
on-record with BOTH CLIs unavailable) does NOT apply — gemini is available with a real audit; the codex
skip is documented in `skipped[]` + `skip_reasons` and surfaced (not silently passed) with a recommended
post-reset re-run. **T-392-03** (scope-drift / re-litigating documented intent) mitigation satisfied — the
prompt carried the design-intent anchor + KNOWN-BY-DESIGN list, and gemini's two HIGH candidates are
genuine PROPERTY-break claims (a money pump + a rate-bound breach), not desirability complaints — they are
routed to 392-03 for the skeptic dual-gate against the frozen source.
