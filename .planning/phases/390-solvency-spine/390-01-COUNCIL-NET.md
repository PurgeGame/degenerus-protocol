# 390-01 — NET 1 (Cross-Model Council) Capture Record — SOLVENCY-SPINE (SOLV-01..07)

**Subject (byte-frozen):** `a8b702a7` (contracts tree `2934d3d8987a09c5f073549a0cb499f6c5f28620`).
**Net:** NET 1 = the cross-model council (external `gemini` + `codex` CLIs via `council.sh`).
**Purpose:** per AUDIT-V63-PLAN §2, a no-finding verdict for any sweep slice requires BOTH nets on
record. Solvency is the SPINE (§4 threat weighting) and the council is the PRIMARY finder
([[cross-model-led-audits-over-claude-only]] — the council caught the V62-03 CEI class a Claude-only
pass missed). This record puts NET 1 on record for the SOLVENCY-SPINE surface so the Wave-2 Claude-net +
adjudication plan (390-02) can fold the council leads in BEFORE any per-item verdict. RAW capture only —
NOT adjudicated, refuted, or fixed here (adjudication is 390-02).

---

## NET 1 ON RECORD for SOLVENCY-SPINE

The SOLVENCY slice was fanned to BOTH council models; **0 CLIs skipped**. Every SOLV-01..07 thesis point,
every FC-390-01..07 lead, and every inherited cross-ref (FC-389-02/-08, FC-392-08, FC-393-02/-03)
received a traced response from BOTH models. The slice has both council models on record (skipped[] empty)
— the both-unavailable re-run condition does NOT apply.

## Council manifest (available / skipped)

| Slice | Label | council.json | Available models | Skipped models |
|-------|-------|--------------|------------------|----------------|
| SOLVENCY | `solv` | `council/solv.council.json` | `gemini`, `codex` | (none) |

Council runner: `.planning/audit-v52/cross-model/bin/council.sh` (read-only wrappers — `ask-gemini.sh`
`--approval-mode plan`; `ask-codex.sh` `--sandbox read-only`; the models may `git show
a8b702a7:contracts/<File>.sol` but cannot mutate). No `--schema` was passed → free-text `.txt` outputs.
ONE slice = ONE fan-out (gemini + codex run in parallel internally), so the single-invocation pacing rule
([[pace-runs-to-survive-5h-cap]]) is satisfied. Wall clock: start `01:20:22Z` → done `01:27:34Z` (~7m12s);
both wrappers exited 0.

## Raw output file paths

| Slice | gemini | codex |
|-------|--------|-------|
| SOLVENCY | `council/solv.gemini.txt` (23 lines) | `council/solv.codex.txt` (27 lines) |

(`council/solv.gemini.err` + `council/solv.codex.err` hold the per-model stderr; both 0 bytes — both
models exited 0.)

---

## One-line characterization per model (RAW — not adjudicated)

- **solv.gemini:** VERIFIED SOUND on the SOLV-01..06 thesis (redemption submit↔claim reconciliation, the
  MAX(175%)→rolled release, dust-forfeit backing by the ETH+stETH pull, the gameOver-drain snapshot
  ordering being tx-atomic, and the V62-03 CEI class closed via stETH-before-ETH in BOTH
  `_payoutWithStethFallback` AND sDGNRS `_payEth`). **BUT it surfaces ONE HIGH-severity SOLV-07 lead** —
  a `whalePassCost` double-credit in the JackpotModule solo-bucket/whale-pass distribution: it claims
  `_processSoloBucketWinner` adds `whalePassCost → futurePrizePool` (cite ~line 1284) AND the caller
  `payDailyJackpot`'s final-day `unpaidDailyEth = dailyEthBudget − paidDailyEth` (cite ~447/452) re-adds
  the same `whalePassCost` to `futurePrizePool` because `paidDailyEth` counts only the ETH portion; on
  non-final days `currentPrizePool` is decremented only by `paidDailyEth`, leaving the `whalePassCost`
  share in `currentPrizePool` while it is also added to `futurePrizePool` → phantom-ETH pool inflation.
  (gemini stopped at the research stage and proposed a follow-up plan rather than finalizing — its
  SOLV-07 claim is a RAW lead, NOT a confirmed finding.)

- **solv.codex:** **No reachable solvency-spine finding.** VERIFIED SOUND across ALL of SOLV-01..07 + ALL
  FC-390-01..07 + every inherited cross-ref, each with `file:line` anchors at `a8b702a7`. On the exact
  SOLV-07 point gemini flagged, codex traces the solo whale-pass split as **single-counted** — "solo
  whale-pass cost routes to `futurePrizePool` while only ETH goes to `claimableDelta`" (cite 1265-1275) —
  i.e. it directly CONTRADICTS gemini's double-credit claim. Codex additionally records ONE caveat: the
  literal `claimablePool == Σ balancesPacked` equality has a DOCUMENTED conservative exception for
  decimator rounds (`claimablePool` may pre-reserve an unclaimed decimator pool before winners are
  credited; cite DegenerusGameStorage.sol:356-366) — an OVER-reservation of backing, not an underbacked
  path. Codex also pinned: SOLV-05 strand/double-credit-free because EVM txs are atomic (a claim cannot
  execute "after line 78 but before line 206" of another tx); FC-390-06 keeper bounty bounded AND below
  real 5-50 gwei gas cost (illiquid flip credit); the redemption ETH-spin path flushes claimable/pool
  writes before recirc and recirc disables the ETH-spin cascade (FC-392-08); forfeit-to-self timing is
  non-extractive (FC-393-02).

---

## Raw council leads routed to 390-02 Wave-2 adjudication (NOT adjudicated here)

The council net is on record. The following are the RAW leads/divergences for 390-02 to fold in against
the Claude net before any verdict:

1. **CONVERGENT-DIVERGENCE on SOLV-07 — `whalePassCost` double-credit (gemini HIGH lead vs codex SOUND).**
   This is the single material cross-model divergence on the slice and the PRIORITY item for 390-02. Gemini
   asserts a final-day-budget double-count of `whalePassCost` (added to `futurePrizePool` once in
   `_processSoloBucketWinner` and again via `payDailyJackpot`'s `unpaidDailyEth = dailyEthBudget −
   paidDailyEth`, with a non-final-day under-debit of `currentPrizePool`); codex asserts the solo whale-pass
   split is single-counted (only the ETH portion enters `claimableDelta`, the pass cost routes to
   `futurePrizePool` once). **390-02 MUST re-read `_processSoloBucketWinner` + `payDailyJackpot`'s final-day
   `unpaidDailyEth`/`paidDailyEth`/`currentPrizePool` arithmetic at `a8b702a7`** (NOTE: gemini's ~1284 vs
   the prompt's @1247 / codex's @1265-1275 line-cites for `_processSoloBucketWinner` differ — pin the exact
   frozen lines first), trace whether `paidDailyEth` includes or excludes the whale-pass-cost share of the
   budget, and settle whether the final-day fold re-adds it. Apply the skeptic dual-gate (structural-protection
   + 3-condition EV lens [[feedback_skeptic_pass_before_catastrophe]]) BEFORE elevating: gemini self-flagged
   this as a research-stage lead, not a finalized finding, and the prize-pool routing is NOT inside the
   `claimablePool` solvency identity (whale-pass value is a pool obligation, F2/F3 in solvency.md) — so the
   "insolvency" framing needs source confirmation that pool obligations actually exceed balance, not just
   that one term is folded twice into a pool that is separately reconciled. If CONFIRMED at source after the
   skeptic gate it routes to a gated USER-hand-review fix; if refuted, both-nets-SOUND on SOLV-07.

2. **Documented decimator pre-reservation exception to the literal claimablePool equality (codex caveat,
   INFO).** Codex notes `claimablePool` can pre-reserve an unclaimed decimator pool before individual
   winners are credited (DegenerusGameStorage.sol:356-366) — the `claimablePool == Σ balancesPacked`
   equality has a documented conservative slack here. This is an OVER-reservation (more backing held than
   strictly owed), not an underbacked payout. **390-02 should confirm the Claude net agrees this slack is
   conservative-only** (matches the solvency.md E3 decimator "full pool → claimablePool at resolution; ETH
   half stays, lootbox half migrates to futurePrizePool at claim" model) and that it does not interact with
   the SOLV-07 lead (item 1) — i.e. the decimator pre-reservation is distinct from the daily-jackpot fold.

3. **All other SOLV-01..06 thesis points + ALL FC-390-01..07 + the inherited cross-refs
   (FC-389-02/-08, FC-392-08, FC-393-02/-03)** were returned **VERIFIED SOUND by both models** with source
   traces (codex explicitly SOUND on every item; gemini SOUND on SOLV-01..06 + the prime targets SOLV-04/05/06).
   390-02 should confirm these against the Claude net; convergent council SOUND + Claude SOUND =
   both-nets-on-record for a no-finding verdict on those items. Key convergent SOUND anchors for 390-02 to
   re-attest: SOLV-04 dust-forfeit value-in-before-credit (both); SOLV-05 gameOver-drain tx-atomicity (both);
   SOLV-06 stETH-before-ETH on `_payoutWithStethFallback` + sDGNRS `_payEth` + `pullRedemptionReserve`
   debit-before-call (both); FC-390-04 `claimValue > combined ⟹ claimable != 0` last-share-burn equality-not-`>`
   (codex); FC-390-06 keeper bounty bounded + sub-real-gas (codex); FC-392-08 ETH-spin flush-before-recirc
   (codex).

---

## Byte-freeze attestation (after the council fan-out)

Immediately after the fan-out, verified the subject was not mutated:

- `git diff a8b702a7 -- contracts/` → **EMPTY** (subject byte-frozen; council writes only to its out-dir).
- `git status --porcelain contracts/` → **EMPTY** (no working-tree contract change).

The council ran in read-only wrappers (`ask-gemini.sh --approval-mode plan`; `ask-codex.sh --sandbox
read-only`) and produced output only under `.planning/phases/390-solvency-spine/council/`. T-390-01
(tampering of the byte-frozen subject) mitigation satisfied. T-390-02 (a slice silently treated as
on-record with both CLIs unavailable) does not apply — both CLIs were available (skipped[] empty).
