# 392-02 — NET 1 (Cross-Model Council) Capture Record — ENTROPY-AND-ECON / BURNIE-coinflip-rework slice (BURNIE-01..06)

**Subject (byte-frozen):** `a8b702a7` (contracts tree pin `2934d3d8987a09c5f073549a0cb499f6c5f28620`).
**Net:** NET 1 = the cross-model council (external `gemini` + `codex` CLIs via `council.sh`).
**Purpose:** per AUDIT-V63-PLAN §2, a no-finding verdict for any sweep slice requires BOTH nets on
record. The BURNIE/coinflip-rework slice is the solvency-ADJACENT backing spine of this phase — BURNIE is
OFF the ETH/`claimablePool` path by design (BURNIE-06), so the concern is the sDGNRS REDEMPTION-BACKING
completeness/conservation: a carry/seed accounting gap that progressively under-credits redeemers
(FC-392-16) or silently forfeits ~half the seeded initial emission (FC-392-17). The council — the PRIMARY
finder ([[cross-model-led-audits-over-claude-only]]) — goes on record FIRST so the Wave-2 Claude-net +
adjudication plan (392-04) can fold the council leads in BEFORE any per-item verdict. RAW capture only —
NOT adjudicated, refuted, or fixed here (adjudication is 392-04).

---

## NET 1 ON RECORD for BURNIE

The BURNIE slice was fanned to the council via `council.sh --label burnie`. **One model (`gemini`) is on
record with a substantive traced audit; `codex` is in `skipped[]`** — `codex` hit the SAME HARD usage-limit
cap as in 392-01 ("ERROR: You've hit your usage limit … try again at 11:56 PM"), not a transient/timeout
error, so a re-run is not possible until the limit resets (~late evening, consistent with the 392-01
banner). Per the plan's both-unavailable rule, a SINGLE available model with real content satisfies
"council on record" with the skip documented (T-392-05: a slice silently treated as on-record with BOTH
CLIs unavailable would be surfaced for re-run — that condition does NOT apply here, because gemini IS on
record with a real, substantive answer). The codex skip is recorded faithfully in `burnie.council.json`
`skipped[]` and is carried to 392-04 as a coverage note (re-run codex opportunistically at 392-04 / 396
once the limit resets to second-source the gemini leads — especially the two prime backing findings).

## Council manifest (available / skipped)

| Slice | Label | council.json | Available models | Skipped models |
|-------|-------|--------------|------------------|----------------|
| ENTROPY-AND-ECON (BURNIE) | `burnie` | `council/burnie.council.json` | `gemini` (real traced audit) | `codex` (usage-limit cap — hard, not transient) |

Council runner: `.planning/audit-v52/cross-model/bin/council.sh` (read-only wrappers — `ask-gemini.sh`
`--approval-mode plan`; `ask-codex.sh` `--sandbox read-only`; the models may `git show a8b702a7:...` but
cannot mutate). No `--schema` was passed → free-text `.txt` output. ONE slice = ONE fan-out (gemini + codex
run in parallel internally), so the single-invocation pacing rule ([[pace-runs-to-survive-5h-cap]]) is
satisfied. `council.sh` exited 0; `burnie.gemini.err` is 0 bytes (gemini exited clean — unlike the 392-01
ECON run, gemini did NOT timeout on a trailing tool step this time; the full audit landed on stdout and the
wrapper exited 0). `burnie.codex.err` = the wrapper skip notice (`ask-codex: codex exec failed`);
`/tmp/ask-codex.err` holds the usage-limit banner.

## Raw output file paths

| Slice | gemini | codex |
|-------|--------|-------|
| ENTROPY-AND-ECON (BURNIE) | `council/burnie.gemini.txt` (41 lines, substantive) | (skipped — no output; `council/burnie.codex.err` = wrapper skip notice; `/tmp/ask-codex.err` = the usage-limit banner) |

**Write-capable-agent verification ([[feedback_verify_writecapable_agents]]):** gemini's narrative CLAIMS
it "saved the detailed audit report to `BURNIE-AUDIT-REPORT.md`" — but `--approval-mode plan` (read-only)
BLOCKED the write: `find . -name BURNIE-AUDIT-REPORT.md` returns nothing, and no file outside `council/`
was modified in the run window. This is the SAME claimed-but-not-written pattern observed at 392-01 (gemini
narrates a report draft its read-only mode prevents). The byte-frozen subject `contracts/` was NOT touched;
NO stray file was created anywhere. The only untracked working-tree file is the pre-existing
`PLAYER-PURCHASE-REWARDS.html` (unrelated to this slice; left untouched).

---

## One-line characterization per model (RAW — not adjudicated)

- **burnie.gemini:** **Two FINDINGS landing EXACTLY on the two prime backing targets + VERIFIED SOUND on
  BURNIE-01/02/03/06.** gemini raised (PRIME-01 / BURNIE-04 / FC-392-16) the **sDGNRS auto-rebuy carry
  stranded from redemption backing** — `autoRebuyCarry` accumulated post-day-20 is invisible to
  `previewClaimCoinflips` (which only counts settled `claimableStored` + unresolved winning days, never the
  carry), so `burnieOwed` in `StakedDegenerusStonk` progressively UNDER-CREDITS redeemers as sDGNRS's
  rolling coinflip position grows, with no liquidation path (it called the carry a "black hole for value");
  and (PRIME-02 / BURNIE-05 / FC-392-17) the **VAULT seed window-aging forfeiture** — the VAULT's day-1-20
  seed (~half the seeded emission, gemini characterized it as ~2M expected) is silently and unrecoverably
  forfeited if the VAULT owner does not call `coinClaimCoinflips` within the first 30 days (the
  `_claimCoinflipsInternal` `COIN_CLAIM_FIRST_DAYS = 30` window with the `minClaimableDay` skip), because —
  unlike sDGNRS — the VAULT has NO auto-claim safety net. It VERIFIED SOUND on BURNIE-01 (every BURNIE
  source — seeds, Degenerette, afking, lootbox, redemptions — gates on a survived coinflip before minting),
  BURNIE-02 (the 8M total stake ~4M EV accurately replaces the removed 2M+2M fixed lumps), BURNIE-03 (the
  `sdgnrsAutoRebuyArmed` latch is monotone and correctly transitions from wallet-mints to carry-rolling),
  and BURNIE-06 (the 128-bit wei stake lanes + 8-bit day-result lanes are lossless and correctly isolate
  BURNIE from the ETH solvency path). gemini's verdict is RAW — it stopped to "present the findings for
  formal approval" before a finalized adjudication, so its two FINDINGS are RAW leads, NOT a finalized
  verdict. gemini did NOT separately characterize the cross-ref backing-dynamics leads (FC-392-11
  loss-sequence backing / FC-392-13 carry settle-ordering double-count) nor the LOW/INFO leads (FC-392-18
  permissive fromGame branch / FC-392-19 survival-flip seed reuse / FC-392-12 seed leaderboard exclusion /
  FC-392-20 claim-loop gas) — those received no explicit council verdict and are carried Claude-net-primary
  to 392-04.

- **burnie.codex:** **NO OUTPUT (skipped — usage-limit cap).** Not a refusal or a classifier trip; a hard
  account cap (identical banner to 392-01, reset ~11:56 PM). Carried to 392-04 / 396 for an opportunistic
  second-source re-run once the limit resets — particularly to second-source the two prime backing findings
  and to cover the non-prime leads gemini did not explicitly characterize.

---

## Raw council leads routed to 392-04 Wave-2 adjudication (NOT adjudicated here)

The council net is on record. The following are the RAW leads for 392-04 to fold in against the Claude net
before any verdict. **Both gemini FINDINGS land on the EXACT prime targets this slice charged HARD (the
carry-excluded-from-backing strand + the VAULT seed window-aging) — they require the skeptic dual-gate
([[feedback_skeptic_pass_before_catastrophe]]) at 392-04: a MED elevation must survive the
structural-protection + 3-condition-EV lens against the FROZEN source, bounded by the design-intent anchor
(the intended variance trade + BURNIE rated "worthless except the whale pass" → severity is bounded to an
under-credit/strand or lost-emission class, NOT an ETH insolvency — but a confirmed under-credit or
lost-emission window is still a value-bearing finding).**

1. **PRIORITY — gemini FINDING: sDGNRS auto-rebuy carry stranded from redemption backing (BURNIE-04 /
   FC-392-16 / break-target 1, the §6 prime lead #1).** gemini CONFIRMS the carry is invisible to
   `previewClaimCoinflips` + the `redeemBurnieShare` consume waterfall, so redeemers are progressively
   under-credited post-day-20 with no liquidation path. **392-04 MUST re-read the frozen source and apply
   the three-part trace the prompt demanded:** (i) confirm at `a8b702a7` that `previewClaimCoinflips`
   (`BurnieCoinflip:971`) = `_viewClaimableCoin` + `claimableStored` and that NEITHER it nor the consume
   waterfall (`:940-967`, incl. the bounded `_claimCoinflipsAmount(SDGNRS, remainder, false)` @956) reads
   `autoRebuyCarry`; (ii) settle whether this is a CONSERVATIVE under-credit/strand (`base <= burnieBal +
   claimableBurnie` → waterfall never reverts → no over-credit, no insolvency) — gemini characterized it as
   under-credit, consistent with conservative; (iii) confirm the steady-state observation the prompt
   raised — `_viewClaimableCoin(SDGNRS)` returns 0 between resolutions (cursor `lastClaim` == latest after
   each daily auto-claim), so `burnieOwed` reflects only the HELD balance and the ongoing BURNIE share to
   redeemers post-seed is essentially zero. **Then DECIDE design-intent vs defect:** is this the intended
   loss of the BURNIE-share economics the old fixed 2M reserve provided (BURNIE "worthless except the whale
   pass" → likely a doc-only KNOWN-ISSUES entry / by-design ruling), or an accidental backing gap that
   warrants a gated fix? gemini gave the property-break (carry excluded) but did NOT settle the
   design-intent question or quantify the realized under-credit — that adjudication is 392-04's, with the
   skeptic gate and the FC-392-16 disposition.

2. **PRIORITY — gemini FINDING: VAULT seed window-aging forfeiture (BURNIE-05 / FC-392-17 / break-target 2,
   the §6 prime lead #2, "most likely to need a contract change").** gemini CONFIRMS the VAULT's day-1-20
   seed is unrecoverably forfeited if not claimed within the 30-day `COIN_CLAIM_FIRST_DAYS` window, because
   the VAULT — unlike sDGNRS — has no auto-claim safety net. **392-04 MUST re-read the window math at
   `a8b702a7`** (`_claimCoinflipsInternal:423-436` — `windowDays = start == 0 ? COIN_CLAIM_FIRST_DAYS :
   COIN_CLAIM_DAYS`; `if (start < minClaimableDay) start = minClaimableDay` silently skips below-window
   days; the read-path twin `_viewClaimableCoin:1022-1030`; `DegenerusVault.coinClaimCoinflips:630-631`) and
   the deploy/operations model, then settle the three determinations the prompt demanded: (i) is the VAULT
   expected/guaranteed to claim within 30 days, or on auto-rebuy at deploy? (ii) is there ANY auto-claim /
   auto-rebuy / keeper safety net for the VAULT seed (the prompt notes there is for sDGNRS via the armed
   branch but apparently none for the VAULT)? (iii) under the realistic timeline, is the seed at risk of
   silent forfeiture? **DECIDE: INTENDED forfeiture (BY-DESIGN — operationally claimed within 30 days / a
   deliberate use-it-or-lose-it incentive) or a real DEFECT → routed gated fix.** This is the surface map's
   flag as the most likely real contract change — give it the rigorous dedicated treatment + the skeptic
   gate. gemini gave the property-break (silent forfeiture path) but did NOT settle the design-intent
   (whether the VAULT is operationally claimed) — that is 392-04's adjudication with the FC-392-17
   disposition.

3. **gemini VERIFIED SOUND — BURNIE-01 (survive-before-mint), BURNIE-02 (emission conservation), BURNIE-03
   (latch monotonicity), BURNIE-06 (packed-lane round-trip + off-spine) — re-attest against the Claude
   net.** gemini confirmed every BURNIE source gates on a survived coinflip (seeds, Degenerette per-bet +
   box spins, afking, lootbox, redemptions), the 8M-stake/~4M-EV seed conserves the removed 2M+2M, the
   `sdgnrsAutoRebuyArmed` latch is monotone with a correct wallet-mint→carry-roll transition, and the
   128-bit wei stake lanes + 8-bit 3-state day-result lanes round-trip losslessly with BURNIE off the ETH
   path. **392-04 should re-attest these against the Claude net; convergent council SOUND + Claude SOUND =
   both-nets-on-record for a no-finding verdict on these four items.** Re-attest at source the specific
   reasons: the survive-before-mint enumeration (every mint source gated), the conservation identity
   (`supplyIncludingUncirculated`; nothing mints up front), the latch set-once @884-885 + the
   armed-branch-mints-nothing @877-878, and the lane bounds (the day-result win∈[50,156]⊂[0,255] with no win
   in [2,49]; the stake-lane masked sibling-day preservation bounded by uint128 supply).

4. **CROSS-REF + LOW/INFO leads with NO explicit council verdict → carried Claude-net-primary to 392-04.**
   gemini did NOT explicitly characterize: FC-392-11 (the loss-sequence sDGNRS backing dynamics — does a
   loss sequence drop backing below outstanding obligations; the RNG-lock half was attested at 391, the
   backing-dynamics half is owned here), FC-392-13 (the `claimCoinflipCarry` settle-ordering double-count
   check across the `claimableStored` take-profit channel and the `autoRebuyCarry` withdrawal channel),
   FC-392-18 (the `setCoinflipAutoRebuy` fromGame permissive branch @662-668 — confirm it stays unreachable,
   matches baseline), FC-392-19 (the survival-flip seed reusing the box seed hash `hash2(rngWord, betId)` —
   for BURNIE bets `betLootboxShare == 0` so no box opens), FC-392-12 (the seed leaderboard/bounty
   exclusion), FC-392-20 (the claim-loop gas ceiling at 365/1460 under the new packed reads, cross-ref
   FC-393-04). **These are CARRIED to 392-04 as Claude-net-primary items — the council coverage is
   gemini-only and selective on the non-prime targets.** A codex re-run at 392-04 / 396 (post-limit-reset)
   is the recommended second-source for these (and to second-source the two prime FINDINGS).

---

## Byte-freeze attestation (after the council fan-out)

Immediately after the fan-out, verified the subject was not mutated:

- `git diff a8b702a7 -- contracts/` → **EMPTY** (subject byte-frozen; the council writes only its model
  output under `council/`; gemini's claimed `BURNIE-AUDIT-REPORT.md` was BLOCKED by read-only mode and was
  never written anywhere — confirmed via `find`).
- `git status --porcelain contracts/` → **EMPTY** (no working-tree contract change).
- No stray files created anywhere outside `council/`; the only untracked working-tree file is the
  pre-existing `PLAYER-PURCHASE-REWARDS.html` (unrelated to this slice; left untouched).

The council ran in read-only wrappers (`ask-gemini.sh --approval-mode plan`; `ask-codex.sh --sandbox
read-only`) and produced output under `.planning/phases/392-entropy-and-econ/council/`. **T-392-04**
(tampering of the byte-frozen subject) mitigation satisfied. **T-392-05** (a slice silently treated as
on-record with BOTH CLIs unavailable) does NOT apply — gemini is available with a real audit; the codex
skip is documented in `skipped[]` and surfaced (not silently passed) with a recommended post-reset re-run.
**T-392-06** (the two prime backing leads waved as "BURNIE is worthless so it doesn't matter" without
tracing the backing accounting) mitigation satisfied — the prompt charged both prime leads HARD as
dedicated targets demanding a CONFIRM/REFUTE/BY-DESIGN with the backing accounting traced, and gemini
returned property-break FINDINGS on BOTH (not hand-waves) that 392-04 will adjudicate with the skeptic gate
+ the design-intent disposition. **T-392-SC2** (`hardhat compile --force` regenerating ContractAddresses
source) avoided — only `git show` / read tools touched the subject.
