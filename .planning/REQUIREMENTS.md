# Requirements: Degenerus Protocol — v66.0 RNG-Surface & Cross-Contract-Call Manipulability Re-Audit

**Defined:** 2026-06-16
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Milestone goal:** Re-verify the VRF-freeze invariant across every RNG consumer and exhaustively sweep all cross-contract calls for any player-manipulable state between VRF request and consumption — confirm nothing is missing before C4A.
**Method:** Cross-model council (Gemini + Codex) is the PRIMARY finder; Claude builds the foundation, adjudicates, and synthesizes. Every candidate finding is adversarially verified before it is recorded.
**Subject:** post-rename HEAD `42c8e9c6` (= origin/main `bb0912a6` + the additive CurseChanged indexer-parity emit, UNPUSHED), byte-frozen at FOUNDATION.
**Seed hypotheses:** `.planning/v66-BLIND-SPOT-PANEL.md` (six-lens blind-spot panel — the convergent meta-finding is that the trusted RNG corpus is stale vs current code, so the consumer net must be re-derived FROM HEAD).
**Posture:** Audit-only on a byte-frozen subject. No contract changes expected; any that surface go through the standard contract-commit approval gate. Test-only additions (RNGNET-MECH) commit autonomously.

## v1 Requirements

Requirements for this milestone. Each maps to exactly one roadmap phase.

### FOUND — Foundation: Subject Freeze & Green Baseline

- [ ] **FOUND-01**: The audit subject is byte-frozen at current post-rename HEAD, with the commit hash and contracts-tree hash recorded as the v66 freeze anchor.
- [ ] **FOUND-02**: A green baseline oracle is captured and documented (forge full-suite pass/skip counts + hardhat parity) as the v66 regression baseline; any pre-existing reds are catalogued as carried, not new.

### RNGNET — Re-Derive the VRF-Consumer Net From HEAD

- [ ] **RNGNET-01**: The complete set of VRF-derived-value consumers is re-derived from current HEAD source by mechanical enumeration (every read of a VRF word / `rngWordByDay` / `rngWordForDay` / `rngWordCurrent` / `lootboxRngWordByIndex` / every `EntropyLib` derivation), independently of the existing catalog.
- [ ] **RNGNET-02**: The re-derived consumer set is diffed against `RNGLOCK-CATALOG.md`; every consumer absent or mis-classified in the catalog (at minimum: BAF winner-select, far-future salvage seed, `coinflipTopByDay` leaderboard, Degenerette survival flip, redemption FLIP-escrow leg) is enrolled and freeze-classified.
- [ ] **RNGNET-03**: The stale trusted RNG docs (`RNGLOCK-CATALOG`, `v30-RNGLOCK-STATE-MACHINE`, `v30-FREEZE-PROOF`, §11/§12) are reconciled to current code or superseded by a current-HEAD consumer-net document; every stale anchor (deleted `BurnieCoinflip`/`StakedDegenerusStonk` names, the removed rotation clear-site, the removed stored `flipDay`, the removed `currentDayView()` cross-call) is corrected or explicitly marked superseded.

### RNGSEAM — Cross-Contract Freeze Seams

- [ ] **RNGSEAM-01**: `claimRedemption(player, day)` argument-selection is proven safe — a non-empty `pendingRedemptions[player][d]` can exist only for `d == currentDayIndex()` with `d+1` undrawn; no path lets a caller select a `day` whose `day+1` VRF word or coinflip result is already on-chain at call time.
- [ ] **RNGSEAM-02**: The redemption FLIP-escrow leg `getCoinflipDayResult(day+1)` is backward-traced for freshness — `day+1`'s coinflip result is provably unwritten at submit and committed atomically by the resolving advance, and the packed-lane read cannot alias another resolved day's byte.
- [ ] **RNGSEAM-03**: The BAF winner-selection path (`runBafJackpot` → `sampleFarFutureTickets` / `sampleTraitTicketsAtLevel`) and the `coinflipTopByDay` leaderboard slice are proven frozen across the Game↔Jackpots↔Coinflip boundary — no sampled `ticketQueue`/`traitBurnTicket`/leaderboard write is reachable after the daily word is observable but before the BAF resolves.
- [ ] **RNGSEAM-04**: The VRF-stall gap-backfill path is analyzed for entropy-collapse — where the redemption roll, coinflip win, and lootbox seed all derive from a single post-gap word; any economic invariant assuming those draws are independent is identified and the EV deviation quantified.
- [ ] **RNGSEAM-05**: The reworked `updateVrfCoordinatorAndSub` (keep-lock + re-request/preserve across a coordinator swap) is proven to hold every freeze-relevant variable consistent — no rotation branch strands the lock, accepts an untrusted coordinator's word, or de-syncs `vrfRequestId` and `rngWordCurrent`.

### RNGSEL — Input-Selection Grinding

- [ ] **RNGSEL-01**: The far-future salvage seed `keccak(player, settled prior-day word)` is verified against address-selection grinding — the realized `jitterMult`/`ticketShareBps`/ETH-FLIP-split swing an actor can obtain by choosing which controlled address sells is quantified, and whether it erodes the by-design salvage discount is determined.
- [ ] **RNGSEL-02**: The Degenerette score-seed `keccak(rngWord, index, spinIdx)` (no betId, no player) is proven safe by exhaustively showing no `lootboxRngWordByIndex[index]` write coincides with an accepting placement at the same active index (incl. gap-backfill and mid-day-retry interleavings).
- [ ] **RNGSEL-03**: The redemption/lootbox claim path is examined for elective-resolution / first-mover capture — whether a player can precompute a favorable self-claim outcome (e.g. whale-pass-jackpot order dependence) for value a passive holder would not receive, given no claim deadline during a live game.

### RNGFALL — Gameover Prevrandao Fallback

- [ ] **RNGFALL-01**: The gameover prevrandao fallback path (which never sets `rngLockedFlag`) is re-derived under the current reworked consumers — every player-controllable input to `processCoinflipPayouts` / `resolveRedemptionPeriod` / `_finalizeLootboxRng` during the fallback window is verified frozen or its mutability is dispositioned, accounting for block-proposer influence on `block.prevrandao`.

### RNGNET-MECH — Close the Mechanical-Net Gaps (test-only)

- [ ] **MECH-01**: The redemption claim-side seed gets a real (un-mocked) submit→resolve→claim regression test; the `rngWordForDay(day+1) → rngWordForDay(day)` mutant (v62 REDEMPTION-ZERO-SEED class) must fail it, and the existing suite is shown blind to that mutant.
- [ ] **MECH-02**: The mid-day cross-day lootbox binding test (`RngIndexDrainBinding.t.sol`, currently `vm.skip(true)` + vacuous early-return) is rewritten to read `lootboxRngWordByIndex` from storage and assert post-request boxes/tickets bind to the live index, not the in-flight word.
- [ ] **MECH-03**: A focused mutation pass on the Coinflip RNG spine (`processCoinflipPayouts` / `_storeDayResult` / `_dayResult`) augments or replaces the source-string "byte-unmodified" net with behavioral coverage; surviving mutants are dispositioned.
- [ ] **MECH-04**: The coinflip win-classification floor is asserted by reading current constants (`COINFLIP_EXTRA_MIN_PERCENT >= 50`, no win stores `b ∈ [2,49]`, no `+bonus` byte overflow) plus a boundary test.

### COUNCIL — Cross-Model Adjudication + Synthesis

- [ ] **COUNCIL-01**: The cross-model council (Gemini + Codex) runs as the primary finder over every RNGNET / RNGSEAM / RNGSEL / RNGFALL surface, seeded with the blind-spot panel hypotheses.
- [ ] **COUNCIL-02**: Every candidate finding is adversarially verified (independent refutation; majority-refute kills it) before it is recorded as confirmed.
- [ ] **COUNCIL-03**: A canonical `audit/FINDINGS-v66.0.md` (+ report) records confirmed findings, refutations, and by-design dispositions; any contract fix routes through the contract-commit approval gate; the milestone closure signal is recorded.

## v2 Requirements

Deferred — not in this milestone's roadmap.

### Features (post-audit)

- **SEED-001**: Century quest-streak shield grant (`.planning/seeds/SEED-001-century-quest-streak-shield.md`) — a contract feature; its own approval + re-audit. Explicitly out of this audit-only milestone.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Contract feature changes (incl. SEED-001) | Audit-only milestone on a byte-frozen subject; features are a separate cycle |
| Gas optimization | Security/RNG-freeze is the hard floor; no optimization that weakens an invariant; gas passes are their own track |
| Full non-RNG solvency re-audit | Covered by v62/v63/v64; only RNG-adjacent solvency seams (RNGSEAM-04) are in scope here |
| Pushing any contract fix without review | Standing rule — manual diff review + approval before any `contracts/*.sol` commit/push |

## Traceability

Each requirement maps to exactly one phase. v66.0 phases continue 410-415.

| Requirement | Phase | Status |
|-------------|-------|--------|
| FOUND-01 | Phase 410 | Pending |
| FOUND-02 | Phase 410 | Pending |
| RNGNET-01 | Phase 411 | Pending |
| RNGNET-02 | Phase 411 | Pending |
| RNGNET-03 | Phase 411 | Pending |
| RNGSEAM-01 | Phase 412 | Pending |
| RNGSEAM-02 | Phase 412 | Pending |
| RNGSEAM-03 | Phase 412 | Pending |
| RNGSEAM-04 | Phase 412 | Pending |
| RNGSEAM-05 | Phase 412 | Pending |
| RNGSEL-01 | Phase 413 | Pending |
| RNGSEL-02 | Phase 413 | Pending |
| RNGSEL-03 | Phase 413 | Pending |
| RNGFALL-01 | Phase 413 | Pending |
| MECH-01 | Phase 414 | Pending |
| MECH-02 | Phase 414 | Pending |
| MECH-03 | Phase 414 | Pending |
| MECH-04 | Phase 414 | Pending |
| COUNCIL-01 | Phase 415 | Pending |
| COUNCIL-02 | Phase 415 | Pending |
| COUNCIL-03 | Phase 415 | Pending |

**Coverage:**
- v1 requirements: 21 total
- Mapped to phases: 21 ✓
- Unmapped: 0 ✓

---
*Requirements defined: 2026-06-16 — grounded in the v66 blind-spot panel.*
*Last updated: 2026-06-16 — traceability filled by roadmapper; 21/21 mapped across phases 410-415.*
