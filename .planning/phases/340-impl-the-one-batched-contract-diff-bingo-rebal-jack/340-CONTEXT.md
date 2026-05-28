# Phase 340: IMPL — The ONE Batched Contract Diff (BINGO + REBAL + JACK) - Context

**Gathered:** 2026-05-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Land the **single reconciled `contracts/*.sol` diff** for the v51.0 claimBingo bundle, authored **producer-before-consumer** per the 339 SPEC edit-order map, applied + locally compiled, then **HELD at the contract-commit boundary for explicit user hand-review** (BATCH-02 HARD STOP, `autonomous:false`).

The diff is exactly four coherent parts (all in ONE batched diff):

1. **BINGO** — the new `contracts/modules/DegenerusGameBingoModule.sol` 3-tier color-completion entrypoint (regular / additive symbol-first / replacement quadrant-first; quadrant-first-before-symbol-first precedence + both-bits suppression; per-player `(level,quadrant)` dedup; `transferFromPool(Pool.Reward,…)` clamped-return + `coinflip.creditFlip(…)` draws; empty-pool graceful no-op; `gameOver` hard cutoff; event-only leaderboard) + the 3 shared-storage mappings (`bingoClaimed`/`firstQuadrant`/`firstSymbol`, `uint24` level key) + the `GAME_BINGO_MODULE` address constant + the `DegenerusGame.claimBingo` delegatecall entrypoint + the interface signatures. (BINGO-01..05)
2. **REBAL** — the `StakedDegenerusStonk` constructor pool-BPS swap. (REBAL-01)
3. **JACK** — the `DegenerusGameJackpotModule` final-day `Pool.Reward` deletion. (JACK-01/02)
4. **BATCH-02** — the single batched diff + the contract-commit HARD STOP.

**Hard boundary:** this is the ONLY contract phase in v51.0. The diff is applied to `contracts/` and locally compiling, but **NOT committed without explicit user hand-review** (`feedback_pause_at_contract_phase_boundaries` + `feedback_batch_contract_approval` + `feedback_never_preapprove_contracts` + `feedback_no_contract_commits` + `feedback_manual_review_before_push`). `ContractAddresses.sol` is freely modifiable (`feedback_contractaddresses_policy`). Pre-launch redeploy-fresh → appending storage at the tail is safe, no migration (`feedback_frozen_contracts_no_future_proofing`).

**Audit posture:** v51.0 MINIMAL CLOSE — the internal 3-skill adversarial sweep + delta-audit + `audit/FINDINGS-v51.0.md` are DEFERRED → the v52 consolidated audit (cumulative v50 + v51 surface). The 339 SPEC's freeze proof + tier-precedence lock + soundness attestation ARE the v51 security floor for this surface; the NON-WIDENING regression is owned by TST-06 at Phase 341.

</domain>

<decisions>
## Implementation Decisions

### Open IMPL decisions resolved in THIS discussion

These are the only implementation choices the 339 SPEC deliberately left open. Everything else is carried forward (locked) below.

- **D-340-01 (Event indexing topology):** The event-only leaderboard (D-08) indexes **`address indexed player` ONLY** on all three events. `level` / `symbol` / `burnieReward` / `dgnrsPaid` stay **non-indexed data fields**. Matches the codebase convention exactly (`JackpotDgnrsWin(address indexed winner, uint256 amount)` — `DegenerusGameJackpotModule.sol:112`); the off-chain indexer filters per-level/per-symbol off the non-indexed payload. Final shapes:
  - `FirstQuadrantBingo(address indexed player, uint256 level, uint8 symbol)`
  - `FirstSymbolBingo(address indexed player, uint256 level, uint8 symbol)`
  - `BingoClaimed(address indexed player, uint256 level, uint8 symbol, uint256 burnieReward, uint256 dgnrsPaid)` (the universal record, emitted on EVERY successful claim — carries the actually-paid amounts).
  - (Exact param ordering / whether the tier events carry the amounts too is Claude's discretion — `BingoClaimed` is the canonical amount-carrier per the acceptance contract.)
- **D-340-02 (Invalid-slot revert behavior):** **Explicit bounds/length guard + a named custom error** so BOTH a wrong-owner slot AND an out-of-bounds `slots[c]` index return ONE clean, fail-closed error (no bare native array-OOB `Panic(0x32)` surfacing for a bad index). Matches the dominant codebase idiom (452 custom-error reverts vs 5 require-strings). Use a descriptive new custom error (e.g. `NotSlotOwner`) or the inherited generic `E()` per the module's local convention — Claude's call on the exact identifier, but it MUST be a custom error, MUST guard the index length before the array read, and MUST require `traitBurnTicket[level][traitId][slots[c]] == msg.sender` for each of the 8 colors.
- **D-340-03 (IMPL verification bar before the hand-review HARD STOP):** **`forge build` clean ONLY.** All suite runs — both the existing regression AND the new bingo tests — are deferred to Phase 341 (where **TST-06 already owns** the NON-WIDENING full-suite regression vs the v50.0 baseline `812abeee`, and TST-01..05 own the per-tier / precedence / revert-dedup / empty-pool / jackpot-regression proofs). No double-work: 340's gate is "applied + compiles"; 341 proves behavior. (Note: this is lighter than the prior-milestone "applied + locally compiled/tested" phrasing — the user explicitly scoped 340 to compile-only since TST-06 is the regression home.)

### Carried forward from the 339 SPEC — LOCKED, do NOT re-derive

The full design is settled across the six Phase-339 artifacts (see canonical refs). IMPL **transcribes**, it does not re-litigate any number or shape. Summary of the binding locks (authoritative text lives in the cited artifacts):

- **D-01 (signature):** `claimBingo(uint256 level, uint8 symbol, uint32[8] calldata slots)`. `symbol < 32` validated; `quadrant = symbol >> 3`, `symInQ = symbol & 7`. `level` widened to `uint256` externally, keyed `uint24` internally; validate `level <= currentLevel` and `!gameOver`. `uint32` slot cap (~4.29B) is structurally unreachable — written disposition (339-DESIGN-LOCK §1a).
- **D-05/D-09 (constants + traitId):** the six reward constants verbatim (`REGULAR_DGNRS_BPS=5`, `FIRST_SYMBOL_BONUS_DGNRS_BPS=5`, `FIRST_QUADRANT_DGNRS_BPS=50`, `REGULAR_BURNIE=1_000e18`, `FIRST_SYMBOL_BONUS_BURNIE=1_000e18`, `FIRST_QUADRANT_BURNIE=5_000e18`). `traitId = (quadrant<<6)|(c<<3)|symInQ` for each color `c ∈ [0,7]`; trait byte `[QQ][CCC][SSS]` (`DegenerusTraitUtils.sol:17-39`).
- **D-07/D-10 (storage + placement):** 3 mappings appended to the SHARED `DegenerusGameStorage.sol` (tail, after `:416`): `bingoClaimed mapping(uint24=>mapping(address=>uint8))` (per-player 4-bit quadrant mask → max 4 claims/player/level), `firstQuadrant mapping(uint24=>uint8)` (systemwide 4-bit), `firstSymbol mapping(uint24=>uint32)` (systemwide 32-bit). New module in `contracts/modules/`; new `GAME_BINGO_MODULE` in `ContractAddresses.sol`; `DegenerusGame.claimBingo` external entrypoint delegatecalls it (mirror `DegenerusGame.sol:278-288` advanceGame dispatch); add the interface signatures.
- **D-06 (tier-precedence cascade) — the binding acceptance contract:** per-player dedup check → compute BOTH first-flags → `if (isQuadrantFirst)` mark **BOTH** `firstQuadrant |= qMask` AND `firstSymbol |= sMask`, pay REPLACEMENT (50 bps + 5_000e18), suppress symbol bonus, emit `FirstQuadrantBingo` → `else if (isSymbolFirst)` mark `firstSymbol |= sMask`, pay ADDITIVE (10 bps + 2_000e18), emit `FirstSymbolBingo` → `else` baseline (5 bps + 1_000e18). The both-bits-on-quadrant-first marking is the **double-pay-trap guard** — any IMPL that pays the symbol bonus on a quadrant-first OR fails to set `firstSymbol` on a quadrant-first VIOLATES the contract.
- **D-08 (reward paths / no-op / cutoff):** sDGNRS via `sdgnrs.transferFromPool(IStakedDegenerusStonk.Pool.Reward, msg.sender, (poolBal*bps)/10_000)` using the **clamped return** as `dgnrsPaid` (no manual clamp); BURNIE via `coinflip.creditFlip(msg.sender, amount)`. Empty/0 pool = graceful no-op (bits set, BURNIE still paid, `dgnrsPaid==0`). `gameOver` = hard revert.
- **D-11 (REBAL):** `StakedDegenerusStonk.sol` `AFFILIATE_POOL_BPS` 3500→3000 (`:295`) + `REWARD_POOL_BPS` 500→1000 (`:297`). Net-zero; complete pool-BPS set `{CREATOR 2000@:291, WHALE 1000, AFFILIATE 3000, LOOTBOX 2000, REWARD 1000, PRESALE_BOX 1000}` sums to 10000; total sDGNRS supply unchanged; `Pool.Reward` 50B→100B.
- **D-12 (JACK):** delete the `isFinalDay` `Pool.Reward` branch in `_handleSoloBucketWinner` (`DegenerusGameJackpotModule.sol:1339-1352`, NOT `_paySoloBucket` — name corrected at SPEC) + the `FINAL_DAY_DGNRS_BPS=100` constant (`:191`, sole use `:1343`) + the `JackpotDgnrsWin` event decl (`:112`, sole emit `:1350`). Cleanly orphaned. PRESERVE the rest of the `isFinalDay` plumbing — the `lvl + 1` ticket-index gate (`:617`) and the callers `:1085/1095/1135/1161/1190/1312` are UNTOUCHED.
- **D-13 (edit-order, BINDING):** (1) append storage → (2) author the module → (3) add `GAME_BINGO_MODULE` → (4) add the `DegenerusGame.claimBingo` entrypoint + interface → (5) REBAL → (6) JACK. Any other order risks a compile-time dangling reference. REBAL + JACK are isolated (different files, no shared symbol with BINGO) → order-independent relative to BINGO, listed last.
- **Freeze-safety (BINGO-06) + soundness (D-02):** PROVEN at SPEC. `claimBingo` is a strict READ-ONLY consumer of the post-RNG-resolution `traitBurnTicket` (the sole writer is `DegenerusGameMintModule.sol:603-643` — NOT the read-side anchors `:2701/2730/2813` or `JackpotModule:654`); it writes ONLY its own three bitfields; touches no current-VRF-window output during `rngLock`. IMPL MUST NOT add any write to `traitBurnTicket`.

### Contract-boundary HARD STOP (BATCH-02)

Phase 340 is `autonomous:false` at the contract-commit boundary. The single batched diff is applied + compiled but **HELD** — the planner must place the contract diff + the explicit user hand-review gate as a non-autonomous wave (the established v44–v50 IMPL precedent: one batched USER-APPROVED `contracts/*.sol` diff). Test/planning/docs commits are agent-committed; the `contracts/` diff is NOT committed without user approval.

### Claude's Discretion

- **Interface surface:** whether `claimBingo` is added to the existing `IDegenerusGame` (or equivalent) interface + a new `IDegenerusGameBingoModule` for the module-side selector — author's call, follow the established per-module interface pattern.
- **Naming:** exact constant/event/error identifiers (must match the locked semantics; the custom error per D-340-02 is author's choice of identifier).
- **`currentLevel` / `gameOver` read source** inside the module (shared storage read) — follow the codebase idiom.
- **CEI ordering is NOT discretionary:** set the claim/first bits (effects) BEFORE the external `transferFromPool` / `creditFlip` calls (interactions), per the acceptance-contract cascade ordering. Reentrancy is LOW/confirmatory in the locked threat model precisely because withdrawals are CEI'd — preserve that.
- Exact `slots`-validation loop structure (single 8-iteration loop computing `traitId` per color + the ownership require) — author's call, must honor D-340-02.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### The LOCKED design — read these FIRST (the 339 SPEC artifacts; this IS the spec for 340)
- `.planning/phases/339-spec-design-lock-rng-freeze-safety-proof-tier-precedence-loc/339-SPEC-INDEX.md` — the navigation/closure index mapping all six artifacts to the 5 SC + 2 reqs; the "Open before SPEC" resolution table; the two Wave-1 source corrections.
- `.planning/phases/339-spec-design-lock-rng-freeze-safety-proof-tier-precedence-loc/339-DESIGN-LOCK-BINGO.md` — **the binding IMPL acceptance contract**: signature (§1), storage shape (§2), traitId derivation (§3), module placement + delegatecall wiring (§4), the six constants verbatim (§5), reward paths / dedup / no-op / cutoff (§6), the producer-before-consumer edit-order (§8).
- `.planning/phases/339-spec-design-lock-rng-freeze-safety-proof-tier-precedence-loc/339-TIER-PRECEDENCE-ACCEPTANCE-CONTRACT.md` — **the BINGO-03 cascade**: the ordered `if (isQuadrantFirst) … else if (isSymbolFirst) … else …` decision, the three-branch acceptance table, the both-bits / suppression / double-pay-trap invariant.
- `.planning/phases/339-spec-design-lock-rng-freeze-safety-proof-tier-precedence-loc/339-GREP-ATTESTATION-EDIT-ORDER.md` — **the binding BATCH-02 edit-order map** + the 22-anchor grep table (every `file:line` confirmed vs `812abeee`, read-vs-write + REF-vs-MOD classified, drift corrections consolidated).
- `.planning/phases/339-spec-design-lock-rng-freeze-safety-proof-tier-precedence-loc/339-REBAL-JACK-ATTESTATION.md` — the REBAL complete-pool-BPS-sums-to-10000 invariant (incl. `CREATOR_BPS=2000@:291`) + the JACK clean-orphan / preserved-plumbing attestation (containing fn `_handleSoloBucketWinner@:1305`).
- `.planning/phases/339-spec-design-lock-rng-freeze-safety-proof-tier-precedence-loc/339-BINGO06-FREEZE-PROOF.md` — the BINGO-06 RNG-freeze proof (per-slot enumeration, verdict FREEZE-SAFE).
- `.planning/phases/339-spec-design-lock-rng-freeze-safety-proof-tier-precedence-loc/339-TRAITBURNTICKET-SOUNDNESS-ATTESTATION.md` — the `traitBurnTicket` write-site IFF soundness theorem (verdict SOUND; sole writer = `MintModule:603-643`) + the D-03 whale-race ACCEPTED-BY-DESIGN non-finding.
- `.planning/phases/339-spec-design-lock-rng-freeze-safety-proof-tier-precedence-loc/339-CONTEXT.md` — the D-01..D-13 decision log feeding the above artifacts.

### Scope + requirements
- `.planning/PLAN-V51-CLAIMBINGO-COLOR-COMPLETION.md` — the authoritative locked design (reward economics, validation sketch, game-theory/Monte-Carlo, "What this replaces" JACK section). The RESEARCH substitute load-bearing source.
- `.planning/REQUIREMENTS.md` — the 18 v51.0 REQ-IDs; **Phase 340 owns BINGO-01/02/03/04/05 · REBAL-01 · JACK-01/02 · BATCH-02** (9 reqs).
- `.planning/ROADMAP.md` §"Phase 340" — the 5 Success Criteria + the cross-cutting re-attestation rule.

### Source anchors (all grep-attested live at HEAD ≡ baseline `812abeee`; `git diff 812abeee HEAD -- contracts/` is EMPTY)
- `contracts/storage/DegenerusGameStorage.sol:404-416` — `traitBurnTicket` decl (`:416`); append the 3 new `uint24`-keyed mappings at the tail.
- `contracts/DegenerusTraitUtils.sol:17-39` — trait byte `[QQ][CCC][SSS]` layout (confirms `traitId` derivation).
- `contracts/DegenerusGame.sol:278-288` — the `GAME_*_MODULE.delegatecall` dispatch shape to mirror for `claimBingo`; `:2701/2730/2813` are READ-side `traitBurnTicket` consumers (NOT writers).
- `contracts/ContractAddresses.sol:13-31` — the module-constant block; add `GAME_BINGO_MODULE` (freely modifiable).
- `contracts/modules/DegenerusGameMintModule.sol:603-643` — the SOLE `traitBurnTicket` writer (the freeze-proof producer; do NOT touch); `:1322` — the `coinflip.creditFlip(…)` reference pattern.
- `contracts/modules/DegenerusGameDegeneretteModule.sol:1135-1159` — the `_awardDegeneretteDgnrs` `transferFromPool(Pool.Reward,…)` clamped-return reference (call `:1154-1155`, empty-pool guard `:1148`).
- `contracts/StakedDegenerusStonk.sol` — REBAL targets `:295` (AFFILIATE) / `:297` (REWARD); `CREATOR_BPS=2000@:291`; `poolBalance@:464` + `transferFromPool@:485` (clamps + returns clamped).
- `contracts/modules/DegenerusGameJackpotModule.sol` — JACK deletion: branch `:1339-1352` (in `_handleSoloBucketWinner@:1305`), constant `:191`, event decl `:112` + sole emit `:1350`; PRESERVE `:617` + callers `:1085/1095/1135/1161/1190/1312`; `:654` is a READ-side consumer.

### Audit-weighting / freeze invariants (memory-locked constraints)
- `v45-vrf-freeze-invariant` — every var interacting with a VRF word must be frozen [request→unlock]; the read must consume post-resolution, not buffered-for-next.
- `threat-model-reentrancy-mev-nonissues` — RNG/freeze DOMINANT; reentrancy + MEV LOW/confirmatory (justifies CEI ordering + the D-03 whale-race non-finding).
- `feedback_security_over_gas`, `feedback_verify_call_graph_against_source`, `feedback_frozen_contracts_no_future_proofing`, `feedback_contractaddresses_policy`, `feedback_pause_at_contract_phase_boundaries`, `feedback_batch_contract_approval`, `feedback_never_preapprove_contracts`, `feedback_no_contract_commits`, `feedback_manual_review_before_push` — governing constraints (the contract-boundary HARD STOP + the single batched USER-APPROVED diff).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`transferFromPool` draw pattern** — `_awardDegeneretteDgnrs` (`DegeneretteModule.sol:1135-1159`) is the exact sDGNRS-from-`Pool.Reward` model to copy (incl. the clamped-return-as-paid idiom → no manual clamp).
- **`coinflip.creditFlip` pattern** — `MintModule.sol:1322` is the BURNIE-flip-credit model (uncapped emission, same path as autoBuy bounty / affiliate kickback → no new inflation surface).
- **Module-delegatecall scaffold** — the existing `GAME_*_MODULE` entrypoints in `DegenerusGame.sol` (`:278-288` advanceGame) give the copy-paste wiring shape for `claimBingo` → `GAME_BINGO_MODULE`.
- **`traitBurnTicket` map** — already fully populated for jackpot winner selection; `claimBingo` is a pure READ consumer (adds NO writes).
- **Custom-error idiom** — the codebase uses custom errors almost exclusively (452 custom-error reverts vs 5 require-strings); modules declare local errors (`RngNotReady`, `NotApproved`, `NoWork`, …) plus an inherited generic `E()`. D-340-02's bad-slot error follows this.
- **Event-indexing idiom** — `address indexed player/winner` is indexed; uint amounts non-indexed (`JackpotDgnrsWin(address indexed winner, uint256 amount)@:112`, `PlayerCredited(address indexed player, address indexed recipient, uint256 amount)`). D-340-01 matches (player-only indexed).

### Established Patterns
- **Delegatecall module architecture** — modules share `DegenerusGameStorage.sol`'s layout; new storage MUST be appended there, not declared in the module. Pre-launch redeploy-fresh → appending is safe, no migration.
- **CEI on reward withdrawals** — effects (bit sets) before interactions (`transferFromPool` / `creditFlip`); this is why reentrancy is LOW-confirmatory in the threat model.
- **Graceful no-op on empty pool** — Degenerette + coinflip-bounty both no-op on a drained `Pool.Reward`; `claimBingo` matches.
- **Trait byte `[QQ][CCC][SSS]`** — `(quadrant<<6)|(c<<3)|symInQ` is the consistent index.

### Integration Points
- `DegenerusGame.claimBingo` external entrypoint → `ContractAddresses.GAME_BINGO_MODULE.delegatecall`.
- New shared storage in `DegenerusGameStorage.sol`: `bingoClaimed` / `firstQuadrant` / `firstSymbol` (`uint24`-keyed).
- New `GAME_BINGO_MODULE` constant in `ContractAddresses.sol`.
- The interface (`IDegenerusGame` or equivalent) gains the `claimBingo` signature; a new `IDegenerusGameBingoModule` declares the module-side selector.
- JACK deletion is in `DegenerusGameJackpotModule.sol` (the same file holding the read-side `:654`) → the read-only BINGO consumer + the final-day deletion land coherently in one diff.

</code_context>

<specifics>
## Specific Ideas

- The user again chose the **light/consistent** options on the three open gray areas (player-only event indexing, custom-error+bounds-guard, compile-only IMPL bar) — continuing the v51 pattern of "trust the locked design + minimal-surface defaults." IMPL should be a faithful transcription of the 339 SPEC, NOT a re-derivation.
- "PROVEN not assumed" / `feedback_verify_call_graph_against_source` is the recurring directive: even though the 339 grep table attested all 22 anchors against `812abeee` (and the contracts diff vs HEAD is empty), the planner/executor should still author each edit against live source line numbers, not trust the cited lines blind — the `DegenerusGame` mint/jackpot inline-duplication precedent.
- The IMPL bar being compile-only (D-340-03) intentionally moves ALL test execution to Phase 341; the planner must NOT widen 340 into a test phase.

</specifics>

<deferred>
## Deferred Ideas

- **Bingo progress view helper** (frontend read-only "which first-prizes are still up for grabs / claimable for me") — explicitly out of v51 scope; deferred follow-up read-only module.
- **The internal 3-skill adversarial sweep + delta-audit + `audit/FINDINGS-v51.0.md`** — DEFERRED → the v52 consolidated audit (cumulative v50 + v51 surface). Enumerated for the v52 charge at the Phase 342 TERMINAL minimal close.
- **Cross-level / multi-level bingo, 2nd/3rd-place ladders within a tier, commit-reveal anti-MEV, `Pool.Reward` refill automation, Q3 (Dice) special-case naming** — all explicit non-goals locked in the plan doc / REQUIREMENTS Out of Scope.
- **NON-WIDENING full-suite regression + per-tier / dedup / empty-pool / jackpot-regression tests** — these are Phase 341 (TST-01..06), not 340 (per D-340-03 compile-only).

None of the above arose as scope creep in this discussion — they were pre-recorded non-goals / downstream phases. Discussion stayed within phase scope.

</deferred>

---

*Phase: 340-impl-the-one-batched-contract-diff-bingo-rebal-jack*
*Context gathered: 2026-05-28*
