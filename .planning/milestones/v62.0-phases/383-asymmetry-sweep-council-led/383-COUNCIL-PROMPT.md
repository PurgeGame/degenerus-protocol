# Council Sweep 383 — ASYMMETRY: parallel-path families

You are an external auditor on a cross-model council auditing the **Degenerus Protocol** before a Code4rena
audit. Read the EXACT frozen source at `c4d48008` via `git show c4d48008:contracts/<File>.sol` (ignore the
working tree). Be concrete and reachable: a finding needs a real ordered call sequence. No speculative gaps.

**Threat priority:** DOMINANT = RNG/freeze + solvency; HIGH = gas-DoS in `advanceGame` (16,777,216 = brick);
LOW = access-control / reentrancy / MEV.

**ALREADY FOUND (do NOT re-report):** V62-01 — permissionless lootbox auto-open reads active `LR_INDEX`
but words land at `LR_INDEX − 1` (human/presale boxes never auto-open). Look for OTHER box-path asymmetries.

**KNOWN BY-DESIGN (do NOT flag):** lootbox open timing (permissionless open, seed frozen); Degenerette
RTP>100% + worthless WWXRP; operator-approval IS the trust boundary; afking inclusive eviction; lootbox
delayed finalization; `claimBingo` no level guard; affiliate single-step direct-mint; PRESALE-01 reinvest
over-credit wontfix.

## Focus — find the one diverging sibling (ASYM-01..06)

The thesis to BREAK: "every box path enqueues; the pass types differ only where intended; the jackpot
distributions share the same math; every RNG read is frozen; every pool mutation is paired and conserved."

1. **Pass types (ASYM-03)** — whale / lazy / deity, all in `WhaleModule`. Diff: price calc, freeze delta
   (`frozenUntilLevel`/`levelCount` via `_applyWhalePassStats` / `_activate10LevelPass`), the lootbox 10%
   (`_recordLootboxEntry`), the presale-box credit, the DGNRS reward, the gate checks. Any unintended
   divergence?
2. **Jackpot distribution (ASYM-04)** — `JackpotModule`. Diff purchase-phase `payDailyJackpot(false)` vs
   jackpot-phase `payDailyJackpot(true)` vs game-over `runTerminalJackpot`: winner caps
   (`DAILY_ETH_MAX_WINNERS=305`, `DAILY_COIN_MAX_WINNERS=50`), the shared `_processDailyEth`/`_processBucket`
   math, the solo bucket + the whale-pass handler. Hunt an off-by-one or a missing cap.
3. **RNG-consume sites (ASYM-05)** — grep EVERY read of `rngWordByDay` / `rngWordCurrent` /
   `lootboxRngWordByIndex` / `_applyDailyRng`. For each, trace BACKWARD that the consumed value was unknown
   / frozen at input-commitment time. Enumerate ALL SLOADs in the request→unlock window, NOT just
   VRF-derived seeds (non-VRF reads consumed alongside RNG are a distinct bug class).
4. **Pool/credit updates (ASYM-06)** — every `claimableWinnings` / `claimablePool` / `futurePrizePool` /
   `nextPrizePool` mutation is paired and conserved (the solvency spine).
5. **Carried candidates:** (a) **affiliate-score magnitude** — a 1.01-ETH affiliate buy yields
   ~25,250-ether `affiliateScore` (mint-quantity-weighted, ~2500× the ETH spent) — intended scoring unit,
   or an over-allocation/asymmetry vs ETH spend? (`DegenerusAffiliate`). (b) **FC2** Degenerette award
   match-key vs frozen score-key. (c) **FC3** WWXRP `_wwxrpBonusBucket` +0.0004% uplift (note WWXRP is
   by-design worthless — is the uplift still consistent/bounded?).

## Output (per finding)
PROPERTY · reachable CALL SEQUENCE · STATE VAR + `file:line` at `c4d48008` · SEVERITY · why protections
don't stop it. State explicitly any family you verified SYMMETRIC and why.
