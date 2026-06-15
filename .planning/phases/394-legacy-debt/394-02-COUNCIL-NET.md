# 394-02 — NET 1 (Cross-Model Council) Capture Record — LEGACY-DEBT / the v51 surface slice (LEGACY-03, LEGACY-04)

**Subject (byte-frozen):** `a8b702a7` (contracts tree pin `2934d3d8987a09c5f073549a0cb499f6c5f28620`).
**Net:** NET 1 = the cross-model council (external `gemini` + `codex` CLIs via `council.sh`).
**Purpose:** per AUDIT-V63-PLAN §2, a no-finding verdict for any sweep slice requires BOTH nets on
record. This v51 surface is FOLDED AUDIT DEBT — v51.0 closed minimally (USER decision 2026-05-28) WITHOUT
the internal 3-skill adversarial sweep + delta-audit + `audit/FINDINGS-v51.0.md` (all deferred). The
cross-model council — the PRIMARY finder ([[cross-model-led-audits-over-claude-only]]) — goes on record FIRST
so the Wave-2 Claude-net + adjudication plan (394-04) can fold the council leads in BEFORE any per-item
verdict and author the deferred `audit/FINDINGS-v51.0.md`. RAW capture only — NOT adjudicated, refuted, or
fixed here (adjudication is 394-04).

---

## NET 1 ON RECORD for the v51 LEGACY-DEBT slice

The v51 slice (LEGACY-03 `claimBingo` color-completion / `DegenerusGameBingoModule.sol` 3-tier selection +
tier-precedence + per-player `(level, quadrant)` dedup + empty-pool/`gameOver` + freeze-safe `traitBurnTicket`
read; LEGACY-04 the sDGNRS `Pool.Reward` rebalance + the jackpot final-day `Pool.Reward` deletion
side-effects) was fanned to the council via `council.sh --label v51`. **`codex` is on record with a
substantive, fully-traced per-item audit** (VERIFIED SOUND on all three break-targets, with `file:line` cites
at `a8b702a7` and one refinement + one stale-comment note). **`gemini` is in `skipped[]`** — it ran but
produced NO output within a hard 8-minute cap on TWO successive attempts (non-responsive for this prompt, see
the fan-out narrative below); recorded faithfully in `v51.council.json` `skipped[]`.

Per the plan's both-unavailable rule, a SINGLE available model with real content satisfies "council on
record" with the skip documented (T-394-05: a slice silently treated as on-record with BOTH CLIs unavailable
would be surfaced for re-run — that condition does NOT apply here, because `codex` IS on record with a real
traced audit). The Wave-2 Claude net (394-04) is the independent second-discipline net the both-nets-on-record
rule requires. **Flag a post-reset/post-responsive `gemini` re-run → 396** to second-source the codex SOUND
verdicts on this slice (opportunistically once gemini responds; the codex-cap-reset window noted at 394-01
remains an opportunity to pick up the carried 392/393 codex re-runs too).

## Council manifest (available / skipped)

| Slice | Label | council.json | Available models | Skipped models |
|-------|-------|--------------|------------------|----------------|
| LEGACY-DEBT (v51 surface) | `v51` | `council/v51.council.json` | `codex` (real traced audit) | `gemini` (non-responsive — no output within an 8-min hard cap ×2 runs) |

Council runner: `.planning/audit-v52/cross-model/bin/council.sh` (read-only wrappers — `ask-gemini.sh`
`--approval-mode plan`; `ask-codex.sh` `--sandbox read-only`). No `--schema` was passed → free-text `.txt`
output. ONE slice = ONE fan-out (gemini + codex run in parallel internally), so the single-invocation pacing
rule ([[pace-runs-to-survive-5h-cap]]) is satisfied.

**Fan-out narrative (recorded for audit-trail integrity):**
- The initial `council.sh --label v51` fan-out ran gemini + codex in parallel. **codex returned OK** quickly
  (`council: codex OK -> v51.codex.txt`; `v51.codex.err` = 0 bytes, clean exit; 19 lines / 4931 bytes of
  substantive per-item trace). **gemini ran for ~57 minutes without producing output** (the `ask-gemini.sh`
  wrapper captures the full response into a variable and writes `.txt` only AFTER the response returns, so a
  long/hung run leaves NO `.txt`), and the background `council.sh` process tree was then killed by the
  orchestration harness before gemini's `wait` completed — so `council.sh` never reached its manifest-build
  step and `v51.council.json` was not written by the script.
- To complete the council without re-invoking the already-finished codex, `gemini` was re-run ALONE via
  `ask-gemini.sh` under a hard `timeout 480` cap. It again produced **NO output (rc=124, timeout-killed)** and
  left an empty `v51.gemini.txt` — the same non-responsive behavior. The single specific empty `v51.gemini.txt`
  was removed (NOT a blanket clean), the non-response reason recorded in `v51.gemini.err`, and
  `v51.council.json` was constructed to match `council.sh`'s exact manifest shape from the true on-disk state
  (`models: ["codex"]`, `skipped: ["gemini"]`, `outputs.codex = council/v51.codex.txt`) — `council.sh`
  re-derives availability from the non-empty `.txt` files, so this manifest is byte-shape-identical to what
  the script would have emitted given the same files.
- This is distinct from the 393-01 codex usage-cap skip (a hard account cap) and from the 394-01 both-models
  run (gemini + codex both returned). Here the roles are INVERTED: codex is the available model; gemini is the
  non-responsive skip. Net effect is the same — one substantive council model on record + the skip documented
  + a second-source re-run carried to 396.

**Write-capable-agent verification ([[feedback_verify_writecapable_agents]]):** the council wrote ONLY to its
out-dir (`council/v51.codex.txt`, `council/v51.codex.err`, `council/v51.gemini.err`, `v51.council.json`). NO
stray file was written anywhere in the tree — full `git status --porcelain` shows only the pre-existing
untracked `PLAYER-PURCHASE-REWARDS.html` (NOT produced by this fan-out). The byte-frozen `contracts/` was NOT
touched.

## Raw output file paths

| Slice | codex | gemini |
|-------|-------|--------|
| LEGACY-DEBT (v51) | `council/v51.codex.txt` (19 lines, substantive — full per-item trace) | (skipped — no output; `council/v51.gemini.err` = the non-response/timeout reason) |

(codex read source directly during exploration rather than strictly via the instructed `git show
a8b702a7:...` — fine for RAW capture; 394-04 re-reads the frozen source for every cite. codex's cites are
notably PRECISE — several drill into the `DegenerusGameStorage.sol` slot definitions and the `MintModule`
resolution path the prompt did not pre-cite; a few are richer than the prompt's anchors and are flagged below
for 394-04 to pin.)

---

## One-line characterization per model (RAW — not adjudicated)

- **v51.codex:** **LEGACY-03 VERIFIED SOUND · LEGACY-04a VERIFIED SOUND · LEGACY-04b VERIFIED SOUND — 0
  findings**, with concrete per-item traces. **LEGACY-03:** `claimBingo` is freeze-safe + CEI-tight — the
  consumed `traitBurnTicket` (`Storage:441`) is read-only at `BingoModule:135-140`; the only append path is
  ticket resolution `_raritySymbolBatch` (`MintModule:773-812`), and queue freezing prevents post-word
  steering (`_swapTicketSlot` flips the write/read buffer + resets drain `Storage:780-784`; `_swapAndFreeze`
  before RNG `:793-805`; daily/midday RNG advances the lootbox index BEFORE the word lands
  `AdvanceModule:1136-1151` / `:1689-1699`; far-future sale reverts during the RNG lock `MintModule:1214`).
  Tier precedence holds (`bingoFirsts` `Storage:1933-1936`; quadrant-first marks BOTH bits `:157-169`
  suppressing the symbol bonus; symbol-first preserves the high quadrant-mask bits `(bf & ~uint64(0xFFFFFFFF))
  | ...` `:173-176`). Dedup + empty-pool hold (`bingoClaimed` `Storage:1929-1931`; the `(level, quadrant)` bit
  checked+set `:148-151` BEFORE the sDGNRS+BURNIE calls `:188-196`; `transferFromPool` clamps to zero on an
  empty pool `StakedStonk:548-570`, so an empty Reward pool consumes the bingo bit and pays only BURNIE;
  `gameOver` gate `:122`). **LEGACY-04a:** the rebalance conserves supply + clamps — the `Pool` enum is only
  `Whale, Affiliate, Lootbox, Reward, PresaleBox` (`StakedStonk:241-247`), `CREATOR 2000 + WHALE 1000 +
  AFFILIATE 3000 + LOOTBOX 2000 + REWARD 1000 + PRESALE_BOX 1000 = 10000 = BPS_DENOM` (`:299-312`),
  `INITIAL_SUPPLY = 1e30` is divisible by 10_000 so the dust branch `:391-397` is a no-op; `transferFromPool`
  / `transferBetweenPools` clamp before decrementing (`:548-570` / `:579-593`); the `uint128` narrowing is safe
  (total ≤ 1e30 ≪ 2^128); no live consumer hard-codes the old split (Bingo `:188-193`, Degenerette `:1220-1230`,
  the coinflip bounty `Game:465-475`, the affiliate path reads the live pool + subtracts the actual `paid`
  return `AdvanceModule:753-775`). **LEGACY-04b:** **codex found NO final-day sDGNRS `Pool.Reward`
  deletion/draw path at all** — grepping the frozen contracts, `Pool.Reward` appears only in seeding + Bingo +
  Degenerette + the coinflip bounty; the jackpot final-day code mutates ETH prize-pool state
  (`currentPrizePool`, `claimablePool`, `prizePoolsPacked` `Storage:354-379`), NOT
  `StakedDegenerusStonk.poolBalances[Pool.Reward]`. The ETH final-day accounting conserves backing (final
  physical day computes a current-pool budget, calls `_processDailyEth`, decrements `currentPrizePool` by the
  full `dailyEthBudget`, returns unpaid ETH to future `JackpotModule:323-329` / `:433-449`; `_processDailyEth`
  credits claimable `:1058-1120`; the solo whale-pass path moves the pass-cost portion into future + includes
  it in `paidEth` `:1183-1215` / `:1241-1281`). No double-spend with concurrent Bingo/Degenerette draws (each
  reads the fresh Reward balance + relies on the clamp; same-block cases are EVM transaction-ordered, no stale
  overlap). **codex also flagged a STALE COMMENT** at `JackpotModule:1047` saying the solo bucket gets "DGNRS
  on final day," but the frozen code path does NOT implement a `Pool.Reward` transfer there. codex's verdict is
  RAW — its SOUND verdicts + the LEGACY-04b "no final-day Reward path" refinement + the stale-comment note are
  leads for 394-04 to re-attest against the Claude net + the frozen source, NOT a finalized adjudication.

- **v51.gemini:** **NO OUTPUT (skipped — non-responsive).** Not a refusal or a classifier trip; the
  `gemini-3-pro-preview` CLI ran for ~57 min on the first attempt then was harness-killed before returning,
  and produced nothing within a hard 8-min cap on a second isolated run (rc=124). Carried to 396 (and
  opportunistically 394-04 if it responds) for a second-source re-run of the codex SOUND verdicts on this
  slice.

---

## Raw council leads routed to 394-04 Wave-2 adjudication (NOT adjudicated here)

The council net is on record. The following are the RAW leads/anchors for 394-04 to fold in against the
Claude net before any per-item verdict and the deferred `audit/FINDINGS-v51.0.md`. codex returned **0
findings** (all three break-targets VERIFIED SOUND) — so the leads are convergent-with-design SOUND anchors to
re-attest at source, plus one structural refinement, plus one stale-comment bookkeeping item, plus the gemini
second-source debt.

1. **PRIORITY re-attest — LEGACY-04b: codex found NO sDGNRS `Pool.Reward` final-day deletion/draw path at
   all.** This is the most material refinement of the slice's premise. The prompt charged the jackpot
   final-day `Pool.Reward` deletion side-effects (break-target 3) on the assumption that the final-day
   consolidation TOUCHES sDGNRS `Pool.Reward`. codex traced that the jackpot final-day code mutates only the
   ETH prize-pool state (`currentPrizePool` / `claimablePool` / `prizePoolsPacked` at `Storage:354-379`) and
   does NOT call `StakedDegenerusStonk.transferFromPool(Pool.Reward, …)` on the final-day path — `Pool.Reward`
   appears only in seeding + Bingo + Degenerette + the coinflip bounty. **394-04 MUST: (a) independently
   grep-enumerate every `Pool.Reward` / `poolBalances[uint8(Pool.Reward)]` reference in the frozen contracts
   and confirm the jackpot/advance final-day path has NONE** (re-verify the `AdvanceModule:753-775` affiliate
   draw is against `Pool.Affiliate`, not `Pool.Reward` — codex's trace says the affiliate path reads the live
   Affiliate pool; pin which `Pool` enum member each `AdvanceModule` draw targets); **(b) if confirmed, the
   LEGACY-04b charge resolves as "the premise does not hold — there is no sDGNRS final-day Reward deletion;
   the final-day ETH accounting is the real surface,"** and the Claude net should instead re-attest the ETH
   final-day conservation codex traced (`JackpotModule:323-329`/`:433-449`/`:1058-1120`/`:1183-1281`) as the
   substantive LEGACY-04b verdict; **(c) reconcile against the AUDIT-V63-PLAN interface cites** which pointed
   the final-day `Pool.Reward` deletion at `AdvanceModule:_consolidatePoolsAndRewardJackpots @833` /
   `JackpotModule:1047/1160` — settle whether those cites refer to ETH-pool consolidation (mis-labeled as
   `Pool.Reward` in the planning note) or whether codex missed a path (the grep + the per-draw `Pool` enum pin
   is the tie-breaker). The 390 SOLVENCY phase + FUZZ-05 POOL-CONSERVATION already attest the ETH
   final-day/`claimablePool` identity — cross-ref so the LEGACY-04b ETH-accounting half does not double-audit.

2. **STALE COMMENT (bookkeeping → 394-04 / a doc-only fix candidate, NOT a contract finding).** codex flagged
   `JackpotModule:1047` — a comment saying the solo bucket gets "DGNRS on final day" — as STALE: the frozen
   code path does NOT implement a `Pool.Reward` transfer there. This is consistent with lead 1 (no final-day
   sDGNRS Reward draw). **394-04 should re-read `JackpotModule:1047` at the frozen source**, confirm the
   comment is stale-vs-code (a `[[feedback_no_history_in_comments]]` / lean-comment hygiene item, NOT a
   correctness defect — the code is the authority), and record it for the v51 FINDINGS as an INFO/doc note (a
   comment fix is a non-contract edit, agent-committable, off the contract-commit gate — but the subject is
   byte-frozen during the sweep, so any comment fix is deferred to a post-audit hygiene pass, not applied
   here).

3. **Re-attest — LEGACY-03 `claimBingo` freeze + tier-precedence + dedup + empty-pool + gameOver (codex
   VERIFIED SOUND).** codex's trace is the convergent-with-SPEC-339 SOUND anchor: the freeze-safety rests on
   the queue write/read-buffer swap + freeze before RNG (`_swapTicketSlot` `Storage:780-784`, `_swapAndFreeze`
   `:793-805`) and the lootbox-index advance BEFORE the word lands (`AdvanceModule:1136-1151`/`:1689-1699`), so
   the `traitBurnTicket[level]` population the read consumes (`BingoModule:135-140`) is frozen relative to the
   level's word; the only writer is `_raritySymbolBatch` (`MintModule:773-812`), which runs in the frozen
   window. **394-04 MUST re-verify IN CODE (do NOT trust the prior paper proof or codex's trace alone):
   enumerate EVERY writer of `traitBurnTicket[level]` and confirm NONE is reachable AFTER the level's word is
   public** (the backward-trace the prompt demanded), and re-attest the tier-precedence masking
   (`:157-169`/`:173-176`) + the dedup bit ordering (`:148-151` before `:188-196`) + the empty-pool no-op
   (clamp to 0, bit still consumed) + the `gameOver` gate `:122`. Convergent council SOUND (codex) + Claude
   SOUND = both-nets-on-record for a no-finding verdict on LEGACY-03.

4. **Re-attest — LEGACY-04a `Pool.Reward` rebalance conservation + no-over-draw (codex VERIFIED SOUND).**
   codex's per-constant sum (2000+1000+3000+2000+1000+1000 = 10000 = `BPS_DENOM`), the `Pool` enum
   enumeration (only 5 members `:241-247`, of which Reward is one), the `INITIAL_SUPPLY = 1e30` divisible by
   10_000 (dust branch a no-op), the clamp-before-decrement in both transfer fns (`:548-570`/`:579-593`), the
   safe `uint128` narrowing, and the no-stale-split-hardcode across all four consumers are the convergent
   SOUND anchors. **394-04 should re-attest at the frozen source** (re-sum the BPS, re-confirm no `Pool` enum
   member carries a stray non-zero BPS off the 6 named constants, re-confirm each consumer reads the live
   `poolBalance`) against the Claude net. Convergent council SOUND + Claude SOUND = both-nets-on-record on
   LEGACY-04a.

5. **gemini second-source still owed.** gemini skipped (non-responsive). The slice has codex on record
   (satisfies "council on record" with the skip documented). **Flag a post-responsive gemini re-run → 396** to
   second-source the codex SOUND verdicts (especially LEGACY-03 freeze-safety + the LEGACY-04b "no final-day
   Reward path" refinement); 394-04 may opportunistically re-run gemini if it responds by then. NOTE the
   inversion vs prior slices (392/393 = codex capped, gemini available; here = codex available, gemini
   non-responsive) — the 396 second-source carry now spans BOTH directions.

6. **Cite-precision to pin at 394-04 (NOT findings — bookkeeping; 394-04 re-reads the frozen source for every
   cite regardless).** codex's cites are richer than the prompt's anchors and should be pinned:
   `traitBurnTicket` def `Storage:441`; `bingoClaimed` `Storage:1929-1931`; `bingoFirsts` `Storage:1933-1936`;
   the queue-swap/freeze `Storage:780-805`; `_raritySymbolBatch` `MintModule:773-812`; the RNG index-advance
   `AdvanceModule:1136-1151`/`:1689-1699`; the `Pool` enum `StakedStonk:241-247`; `poolBalances` `:253`; the
   ETH final-day path `JackpotModule:323-329`/`:433-449`/`:1058-1120`/`:1183-1281`. Pin each at the frozen
   source (most are storage/def sites the prompt did not pre-cite; codex's `BingoModule` cites `:135-140` /
   `:148-151` / `:157-176` / `:188-196` align with the prompt's `@130-136` / `@148-151` / `@155-180` /
   `@188-196` within a couple lines — re-read to pin exact).

---

## Byte-freeze attestation (after the council fan-out)

Immediately after the fan-out, verified the subject was not mutated:

- `git diff a8b702a7 -- contracts/` → **EMPTY** (0 diff lines; subject byte-frozen; the council writes only
  its model output under `council/`).
- `git status --porcelain contracts/` → **EMPTY** (no working-tree contract change).
- Full-tree `git status --porcelain` shows only the pre-existing untracked `PLAYER-PURCHASE-REWARDS.html` —
  NOT produced by this fan-out (the council's `council/v51.*` outputs are under the gitignored `.planning/`
  tree); the council wrote no stray file anywhere ([[feedback_verify_writecapable_agents]] — verified clean).

The council ran in read-only wrappers (`ask-gemini.sh --approval-mode plan`; `ask-codex.sh --sandbox
read-only`) and produced output only under `.planning/phases/394-legacy-debt/council/`. **T-394-04**
(tampering of the byte-frozen subject) mitigation satisfied. **T-394-05** (a slice silently treated as
on-record with BOTH CLIs unavailable) does NOT apply — `codex` IS available with a real traced audit;
`skipped[]` records the gemini non-response and is surfaced (not silently passed) with a recommended
post-responsive re-run to 396. **T-394-06** (scope-drift / re-litigating documented intent) mitigation
satisfied — the prompt carried the KNOWN-BY-DESIGN list, and codex verified freeze-safety / tier-precedence /
dedup / pool-conservation without re-litigating the no-level-guard or the RTP. **T-394-SC** (`hardhat compile
--force` regenerating ContractAddresses source) avoided — only `git show` / read tools touched the subject.

---

## NOTE — carry-forward status (the 396 second-source debt)

This slice ADDS a `gemini` second-source re-run to the 396 carry (gemini non-responsive here). The EXISTING
carry-forward to 396 (the post-reset codex second-source of the 392 BURNIE-04/-05 + 393 ACCESS-02/-04 gemini
SOUND verdicts) STILL stands. **OPPORTUNITY (from 394-01):** the codex usage limit has reset — confirmed
again here by codex's successful run — so the 392/393 codex second-source re-runs remain runnable
opportunistically; and the gemini non-response on THIS slice should be retried once gemini responds (it
returned full audits on the 391/392/393 slices, so this is a transient non-response, not a hard cap). The 396
close should pick up BOTH directions of the carried second-source debt while each CLI is responsive.
