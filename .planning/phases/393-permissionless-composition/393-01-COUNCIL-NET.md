# 393-01 — NET 1 (Cross-Model Council) Capture Record — PERMISSIONLESS-COMPOSITION (ACCESS-01..05)

**Subject (byte-frozen):** `a8b702a7` (contracts tree pin `2934d3d8987a09c5f073549a0cb499f6c5f28620`).
**Net:** NET 1 = the cross-model council (external `gemini` + `codex` CLIs via `council.sh`).
**Purpose:** per AUDIT-V63-PLAN §2, a no-finding verdict for any sweep slice requires BOTH nets on
record. Access-control / reentrancy / MEV is the LOW/confirmatory threat class (§4) — but the SUBSTANTIVE
items in this slice are ACCESS-02 (keeper-bounty economics vs real gas) and ACCESS-04 (partial-balance
burst solvency), where a real grief/faucet/steer or a burst-solvency strand weighs higher. The council —
the PRIMARY finder ([[cross-model-led-audits-over-claude-only]]) — goes on record FIRST so the Wave-2
Claude-net + adjudication plan (393-02) can fold the council leads in BEFORE any per-item verdict. RAW
capture only — NOT adjudicated, refuted, or fixed here (adjudication is 393-02).

---

## NET 1 ON RECORD for PERMISSIONLESS-COMPOSITION

The PERMISSIONLESS-COMPOSITION slice was fanned to the council via `council.sh --label access`. **One model
(`gemini`) is on record with a substantive traced audit; `codex` is in `skipped[]`** — `codex` hit a HARD
usage-limit cap ("You've hit your usage limit ... try again at 11:56 PM" — `/tmp/ask-codex.err`), not a
transient/timeout error, so a re-run is not possible until the limit resets (this matches the codex cap that
skipped it at 392-01..04). Per the plan's both-unavailable rule, a SINGLE available model with real content
satisfies "council on record" with the skip documented (T-393-02: a slice silently treated as on-record with
BOTH CLIs unavailable would be surfaced for re-run — that condition does NOT apply here, because gemini IS on
record with a real answer). The codex skip is recorded faithfully in `access.council.json` `skipped[]` and is
carried forward as a coverage note: **flag a post-reset codex re-run → 396** (re-run codex opportunistically
once the limit resets to second-source the gemini SOUND verdicts on this slice).

## Council manifest (available / skipped)

| Slice | Label | council.json | Available models | Skipped models |
|-------|-------|--------------|------------------|----------------|
| PERMISSIONLESS-COMPOSITION | `access` | `council/access.council.json` | `gemini` (real audit) | `codex` (usage-limit cap — hard, not transient) |

Council runner: `.planning/audit-v52/cross-model/bin/council.sh` (read-only wrappers — `ask-gemini.sh`
`--approval-mode plan`; `ask-codex.sh` `--sandbox read-only`). No `--schema` was passed → free-text `.txt`
output. ONE slice = ONE fan-out (gemini + codex run in parallel internally), so the single-invocation pacing
rule ([[pace-runs-to-survive-5h-cap]]) is satisfied. `council.sh` exited 0.

**Fan-out narrative (recorded for audit-trail integrity):**
- `council.sh` ran gemini + codex in parallel. `codex` SKIPPED (`council: codex SKIPPED (rc=0)`;
  `access.codex.err` = the wrapper skip notice "ask-codex: codex exec failed"; `/tmp/ask-codex.err` =
  the OpenAI Codex banner [v0.135.0, model `gpt-5.5`, sandbox read-only] followed by the
  "You've hit your usage limit … try again at 11:56 PM" cap). `gemini` returned OK with a substantive
  traced audit (`council: gemini OK`; `access.gemini.err` = 0 bytes — gemini exited 0 cleanly).
- `access.council.json` reflects the real post-fan-out state: `models: ["gemini"]`, `skipped: ["codex"]`,
  `outputs.gemini = council/access.gemini.txt`.

**Write-capable-agent verification ([[feedback_verify_writecapable_agents]]):** the council wrote ONLY to its
out-dir (`council/access.gemini.txt`, `access.council.json`, the two `.err` files). No stray file was written
anywhere in the tree (full `git status --porcelain` shows only the pre-existing
`PLAYER-PURCHASE-REWARDS.html` untracked file and the prior-session `.planning/STATE.md` edit — neither
produced by this fan-out; the byte-frozen `contracts/` was NOT touched).

## Raw output file paths

| Slice | gemini | codex |
|-------|--------|-------|
| PERMISSIONLESS-COMPOSITION | `council/access.gemini.txt` (43 lines, substantive — full per-item trace) | (skipped — no output; `council/access.codex.err` = wrapper skip notice; `/tmp/ask-codex.err` = the usage-limit banner) |

(`council/access.gemini.err` = 0 bytes — gemini exited 0. gemini's cites are working-tree-derived where it
read source directly rather than strictly via the instructed `git show a8b702a7:...`; fine for RAW capture —
393-02 re-reads the frozen source for every cite. NOTE one gemini cite drift to reconcile at 393-02: it
cited `claimCoinflipCarry` mint at `BurnieCoinflip.sol:787` — the authoritative cite is the entry @366; and
it cited a redemption bounty `BOX_BOUNTY_ETH_TARGET = 24e12` / `~48k gas` whereas the prompt/cite pins both
bounties at `15e12` wei — 393-02 must re-read the redemption bounty constant + the carry mint line at the
frozen source.)

---

## One-line characterization per model (RAW — not adjudicated)

- **access.gemini:** **VERIFIED SOUND across ALL of ACCESS-01..05 + FC-393-04 — 0 findings**, with concrete
  per-item traces. ACCESS-01 (beneficiary-only): all of `claimDecimatorJackpot`/`Many`, `claimRedemption`/
  `Many`, `claimCoinflipCarry` credit `player` (or sDGNRS's own claimable for dust forfeits), never
  `msg.sender`. ACCESS-02 (keeper-bounty): gave the REAL-gas accounting the prompt demanded — at 20 gwei the
  ~30k-gas decimator settle costs ~0.0006 ETH = **40x** the 0.000015-ETH reward; at 5 gwei = **10x**; the
  reward is illiquid BURNIE flip-credit (50% flip risk + peg discount) so realized liquid value ≈30% of the
  ETH-target; un-manufacturable (each entry requires a real BURNIE / sDGNRS burn, ≥1 whole-token floor for
  redemptions); BURNIE dilution bounded by real burn activity + the 50%/day supply cap. ACCESS-03
  (forced-timing magnitude): adjacent-level ticket-price jumps exist at milestone levels (e.g. ~0.16→0.24
  ETH at L99→L100) but come with corresponding jackpot-reward jumps, and a forced earlier resolution is
  generally beneficial/neutral for the winner (closer-level tickets); the frozen seed immunizes the
  win/loss outcome — ruled INERT. ACCESS-04 (partial-balance burst solvency): `_pendingRedemptionEthValue`
  lowered by the exact `totalRolledEth` per claim; each leg uses `min(balance, amount)` ETH + pulls the
  remainder as stETH; the MAX_ROLL (175%) reservation covers any 25-175% roll, so an ETH drain by earlier
  same-block claims merely shifts the deficit to the stETH leg of the same reservation — no ETH stranded,
  no stETH under-pulled. ACCESS-05 (gates + reentrancy): `prizePoolFrozen` blocks decimator/redemption
  during the RNG window, `rngLocked` blocks `claimCoinflipCarry`, post-gameOver redemption is self-claim
  only; CEI holds (slot delete + ledger debit before the untrusted `.call`); stETH transferred before the
  ETH `.call` (closing the V62-03 in-flight-stETH double-count); the callee `msg.sender == SDGNRS` gates on
  `resolveRedemptionLootbox` / `creditRedemptionDirect` hold. FC-393-04 (claim-loop gas): packed storage
  keeps the 365/1460 walks cheap, the sDGNRS auto-settle is kept current each `advanceGame` (≈O(1) steady
  state), cold-SLOAD walks are caller-paid + isolated from the `advanceGame` liveness chain. gemini's verdict
  is RAW — its SOUND verdicts and its real-gas numbers are leads for 393-02 to re-attest against the Claude
  net + the frozen source, NOT a finalized adjudication.

- **access.codex:** **NO OUTPUT (skipped — usage-limit cap).** Not a refusal or a classifier trip; a hard
  account cap (`gpt-5.5`, "You've hit your usage limit … try again at 11:56 PM"). Carried to 396 (and
  opportunistically 393-02 if the limit resets) for a second-source re-run of the gemini SOUND verdicts on
  this slice.

---

## Raw council leads routed to 393-02 Wave-2 adjudication (NOT adjudicated here)

The council net is on record. The following are the RAW leads/anchors for 393-02 to fold in against the
Claude net before any per-item verdict. gemini returned **0 findings** (all VERIFIED SOUND) — so the leads
are convergent-SOUND anchors to re-attest, plus the two prime targets that demand the skeptic dual-gate
([[feedback_skeptic_pass_before_catastrophe]]) at source, plus two cite-drifts to reconcile.

1. **PRIME re-attest — ACCESS-02 keeper-bounty economics (gemini VERIFIED SOUND with REAL-gas numbers).**
   gemini supplied the real-gas accounting the prompt charged for: 40x under-water at 20 gwei, 10x at 5 gwei,
   ~30% liquid value after flip-risk + peg discount, un-manufacturable (real burn per box, ≥1 whole-token
   redemption floor), BURNIE dilution bounded by real burn + the 50%/day cap. **393-02 MUST re-verify the
   redemption bounty constant** — gemini cited the redemption bounty as `BOX_BOUNTY_ETH_TARGET = 24e12` wei
   (~48k gas) whereas the prompt + permissionless-access.md §2 pin BOTH bounties at the identical `15e12`
   wei. Re-read `StakedDegenerusStonk:803-814` at `a8b702a7` to settle the actual redemption bounty constant
   before confirming the faucet verdict; the conclusion (net-negative vs real gas + un-manufacturable) holds
   either way (at `24e12`/`48k gas` the 20-gwei cost ~0.00096 ETH is still ~40x), but the constant must be
   pinned. Couple to FC-390-06 (issuance bound REFUTED at 390) for the BURNIE-dilution half. Apply the
   3-condition-EV lens — gemini itself rated this SOUND with the numbers; the convergent SOUND + Claude SOUND
   + the real-gas accounting = both-nets-on-record for a no-finding verdict on ACCESS-02.

2. **PRIME re-attest — ACCESS-04 / FC-393-03 partial-balance burst solvency (gemini VERIFIED SOUND).** gemini
   confirmed the segregation accounting: `_pendingRedemptionEthValue` lowered by the exact `totalRolledEth`
   per claim; `min(balance, amount)` ETH legs + stETH-remainder pull; the MAX_ROLL (175%) reservation covers
   any 25-175% roll so an ETH drain by earlier same-block claims merely shifts the deficit to the stETH leg
   of the same reservation — no strand, no under-pull. **393-02 should re-read the redemption legs at
   `a8b702a7`** (`StakedDegenerusStonk` @880/:888/:898 + the `_pendingRedemptionEthValue` release @849, the
   line gemini cited) and re-attest Σ legs == Σ rolled == Σ released across an adversarial same-block burst
   against the Claude net + (if reconstructable) a burst oracle. Couple to the 390 FC-392-08 / FC-393-03
   solvency-half REFUTAL (each leg recomputes a fresh `bal`, GAME pulls the remainder fail-closed). Convergent
   council SOUND + Claude SOUND + the leg accounting = both-nets-on-record on the solvency-adjacent prime.

3. **Re-attest — ACCESS-01 / ACCESS-03 / ACCESS-05 + FC-393-01/-02/-04 + the inherited cross-refs FC-390-03,
   FC-390-06, FC-392-08, FC-392-20 (gemini VERIFIED SOUND).** 393-02 should re-attest these against the
   Claude net; convergent council SOUND + Claude SOUND = both-nets-on-record for a no-finding verdict on each.
   Key convergent SOUND anchors: ACCESS-01 beneficiary-only (value to `player`, never `msg.sender`);
   ACCESS-03 forced-timing magnitude INERT (adjacent-level jumps are milestone reward jumps; forced earlier
   resolution is beneficial/neutral; frozen seed immunizes win/loss — FC-393-01); the forfeit-to-self
   deterministic split with no per-victim extraction (FC-393-02); ACCESS-05 gates intact (`prizePoolFrozen`,
   `rngLocked`, self-claim-only post-gameOver) + CEI + stETH-first/ETH-last + the SDGNRS-gated callees +
   `distributeYieldSurplus` internal-only (FC-390-03 ACCESS half — no batch splits across the boundary);
   FC-393-04 / FC-392-20 claim-loop gas caller-paid + off the advanceGame chain.

4. **Cite-drift to reconcile at 393-02 (NOT a finding — bookkeeping).** gemini cited the `claimCoinflipCarry`
   mint at `BurnieCoinflip.sol:787`; the authoritative entry cite is @366. And the redemption bounty constant
   (lead 1). 393-02 re-reads the frozen source for every cite regardless; flagged so the adjudicator pins the
   correct lines and the no-finding verdict rests on the right code.

5. **Codex second-source still owed.** codex skipped (usage cap). The slice has gemini on record (satisfies
   "council on record" with the skip documented). **Flag a post-reset codex re-run → 396** to second-source
   the gemini SOUND verdicts (especially the two primes ACCESS-02 / ACCESS-04); 393-02 may opportunistically
   re-run codex if the limit has reset by then.

---

## Byte-freeze attestation (after the council fan-out)

Immediately after the fan-out, verified the subject was not mutated:

- `git diff a8b702a7 -- contracts/` → **EMPTY** (0 diff lines; subject byte-frozen; the council writes only
  its model output under `council/`).
- `git status --porcelain contracts/` → **EMPTY** (no working-tree contract change).
- Full-tree `git status --porcelain` shows only the pre-existing untracked `PLAYER-PURCHASE-REWARDS.html`
  and the prior-session `.planning/STATE.md` edit — **neither produced by this fan-out**; the council wrote
  no stray file anywhere ([[feedback_verify_writecapable_agents]] — verified clean).

The council ran in read-only wrappers (`ask-gemini.sh --approval-mode plan`; `ask-codex.sh --sandbox
read-only`) and produced output only under `.planning/phases/393-permissionless-composition/council/`.
**T-393-01** (tampering of the byte-frozen subject) mitigation satisfied. **T-393-02** (a slice silently
treated as on-record with BOTH CLIs unavailable) does NOT apply — gemini is available with a real audit; the
codex skip is documented in `skipped[]` and surfaced (not silently passed) with a recommended post-reset
re-run to 396. **T-393-03** (`hardhat compile --force` regenerating ContractAddresses source) avoided —
only `git show` / read tools touched the subject.
