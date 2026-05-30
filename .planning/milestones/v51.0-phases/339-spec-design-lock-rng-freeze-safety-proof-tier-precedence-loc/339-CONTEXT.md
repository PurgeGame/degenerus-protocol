# Phase 339: SPEC — Design-Lock + RNG-Freeze-Safety Proof + Tier-Precedence Lock + Call-Graph Attestation - Context

**Gathered:** 2026-05-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Paper-only **design-lock** for the v51.0 claimBingo bundle (BINGO + REBAL + JACK). Phase 339 produces the SPEC deliverable that lets Phase 340 author **one fully-reconciled `contracts/*.sol` diff with zero "by construction" assumptions**. It must:

1. Settle the `claimBingo(uint256 level, uint8 symbol, uint32[8] slots)` signature + storage shape (`bingoClaimed` u8 / `firstQuadrant` u8 / `firstSymbol` u32, keyed by `uint24` level) + reward constants + module placement (new `contracts/modules/DegenerusGameBingoModule.sol`, delegatecalled from `DegenerusGame.claimBingo`). **(BATCH-01)**
2. **PROVE** (not assume) the BINGO-06 RNG-freeze safety of the `traitBurnTicket` read. **(BINGO-06)**
3. Design-lock the tier-precedence rule (quadrant-first checked BEFORE symbol-first; quadrant-first marks BOTH bits + suppresses the symbol-first bonus). **(BATCH-01, "Open before SPEC" item 7)**
4. Attest the REBAL BPS-sum invariant + the JACK final-day deletion side-effects.
5. Grep-attest every cited `file:line` vs the v50.0-closure HEAD `812abeee` and correct any drift in the SPEC.

**Hard boundary: ZERO `contracts/*.sol` edits in this phase.** This is the design-lock; the diff lands at 340. No research sub-phase (the design + game-theory/Monte-Carlo is already done in the plan doc).

**Audit posture:** v51.0 minimal close — the internal 3-skill adversarial sweep + delta-audit + `audit/FINDINGS-v51.0.md` are DEFERRED → the v52 consolidated audit. Phase 339's freeze proof + tier-precedence lock + soundness attestation ARE the v51 security floor for this surface.

</domain>

<decisions>
## Implementation Decisions

### Slot-Arg Width (discussed — "Open before SPEC" #2)
- **D-01:** Lock the signature as `claimBingo(uint256 level, uint8 symbol, uint32[8] calldata slots)`. **`slots` is `uint32[8]`, not `uint256[8]`.** `slots[c]` indexes the dynamic `address[]` inside `traitBurnTicket[level][traitId]`. The `uint32` cap (~4.29B entries per `(level, traitId)`) is unreachable — it would require 4 billion RNG-resolved ticket entries of ONE trait byte on ONE level. Rationale: cheap calldata, and the cap is a non-issue. The SPEC must state the cap explicitly so the audit has a written disposition (not silence).

### Bingo Soundness Attestation (discussed — "Open before SPEC" #4, BINGO-01 foundation)
- **D-02:** The SPEC must do a **full write-site attestation** of `traitBurnTicket`, NOT a precedent-based hand-wave. It must read the actual population sites (`DegenerusGameJackpotModule.sol:654` storage-bucket writer + `DegenerusGame.sol:2701 / 2730 / 2813`) and PROVE: an address appears at `traitBurnTicket[level][traitId][slot]` **iff** it owned a post-RNG-resolved entry carrying that exact trait byte `[QQ][CCC][SSS]`. Specifically attest: (a) the append is keyed by the resolved trait byte (no cross-trait contamination); (b) duplicate-append behavior (a player who resolved N entries of the same trait appears N times — fine, the player just names a slot they occupy); (c) any transfer/burn re-population semantics that could let a NON-owner land at a slot. This is the heart of whether `claimBingo` can be spoofed → it gets the most rigorous treatment in the SPEC.

### Whale-Race / MEV Disposition (discussed)
- **D-03:** The SPEC **enshrines the whale-frontrunning disposition as a written ACCEPTED-BY-DESIGN non-finding.** Text: "whale frontrunning on the per-VRF trait-resolution batch is accepted by design — the race window is the per-VRF reveal, not per-block; two simultaneous first-claimants for the same `(level, quadrant)` or `(level, symbol)` require both to land their last needed color in the same VRF resolution, which is rare." Purpose: the deferred v52 adversarial sweep treats this as already-dispositioned/known, not a fresh finding. Race-start semantics also locked: claimable the moment level-N entry traits are RNG-resolved (`currentLevel` advances).

### Freeze-Safety Proof Depth (BINGO-06) — Claude's discretion default
- **D-04:** (User skipped this gray area → defaulting per the USER-LOCKED audit weighting where RNG/freeze is the DOMINANT axis.) The SPEC proves BINGO-06 with a **structured per-slot enumeration**, not prose alone: enumerate every storage slot `claimBingo` touches and classify each as either (i) its own NEW bitfield write (`bingoClaimed` / `firstQuadrant` / `firstSymbol`), (ii) a post-resolution READ (`traitBurnTicket`, `currentLevel`, `gameOver`, `poolBalance`), or (iii) an external reward call (`transferFromPool` / `creditFlip`) — and show NONE is a current-VRF-window output slot during `rngLock`. Re-attest `v45-vrf-freeze-invariant` for the read on paper. If the user later prefers lighter prose, that's a downgrade they can request — but the rigorous form is the safe default for the dominant axis.

### Carried-Forward Locked Design (from the plan doc — DO NOT re-derive; SPEC transcribes into the acceptance contract)
- **D-05:** Reward tiers (all LOCKED): regular = 0.05% `Pool.Reward` + 1 000 BURNIE; symbol-first = ADDITIVE 0.1% + 2 000 (regular + bonus); quadrant-first = REPLACEMENT 0.5% + 5 000. Constants: `REGULAR_DGNRS_BPS=5`, `FIRST_SYMBOL_BONUS_DGNRS_BPS=5`, `FIRST_QUADRANT_DGNRS_BPS=50`; `REGULAR_BURNIE=1_000e18`, `FIRST_SYMBOL_BONUS_BURNIE=1_000e18`, `FIRST_QUADRANT_BURNIE=5_000e18`.
- **D-06:** Tier-precedence rule (LOCKED, must be written as the IMPL acceptance contract): check `isQuadrantFirst` BEFORE `isSymbolFirst`; quadrant-first → mark BOTH `firstQuadrant` AND `firstSymbol` bits, pay REPLACEMENT, SUPPRESS the symbol-first bonus; symbol-first (not quadrant-first) → mark `firstSymbol`, pay ADDITIVE; regular (both set) → baseline.
- **D-07:** Per-player dedup = once per `(level, quadrant)` via `bingoClaimed[level][msg.sender]` quadrant-mask bit → max 4 claims/player/level. Systemwide first keys: `(level, quadrant)` for 4 quadrant-firsts; `(level, symbol)` for 32 symbol-firsts.
- **D-08:** Reward paths: sDGNRS via `sdgnrs.transferFromPool(IStakedDegenerusStonk.Pool.Reward, msg.sender, (poolBal*bps)/10_000)` using the clamped return as `dgnrsPaid`; BURNIE via `coinflip.creditFlip(msg.sender, amount)`. Empty/0-amount pool = graceful no-op (claim+first bits set, BURNIE still paid, `dgnrsPaid==0`). `gameOver` = hard cutoff (revert). Leaderboard event-only: `FirstQuadrantBingo` / `FirstSymbolBingo` / `BingoClaimed`.
- **D-09:** `traitId = (quadrant<<6) | (c<<3) | symInQ`, `quadrant = symbol>>3`, `symInQ = symbol & 7`, where the trait byte layout is `[QQ][CCC][SSS]` (Q bits 7-6, C bits 5-3, S bits 2-0). Scout-confirmed this matches `DegenerusTraitUtils.sol:17-39`. Duplicate-slot griefing impossible — each trait byte encodes exactly one `(quadrant, color, symbol)`.
- **D-10:** Module placement LOCKED: new `contracts/modules/DegenerusGameBingoModule.sol` (scout-confirmed all `GAME_*_MODULE`s live in `contracts/modules/`). Wiring: a new `claimBingo` external entrypoint in `DegenerusGame.sol` that `ContractAddresses.GAME_BINGO_MODULE.delegatecall(...)`s — the established dispatch pattern; needs a new `GAME_BINGO_MODULE` address in `ContractAddresses.sol` (freely modifiable per `feedback_contractaddresses_policy`). Storage mappings live in the shared `DegenerusGameStorage.sol` (delegatecall architecture → storage must be in the shared layout; pre-launch redeploy-fresh, so appending is fine, no migration).

### REBAL + JACK Attestation Scope (SPEC verification charge)
- **D-11:** REBAL: `StakedDegenerusStonk.sol` constructor swap `AFFILIATE_POOL_BPS` 3500→3000 (:295) and `REWARD_POOL_BPS` 500→1000 (:297). The swap is net-zero (+500/−500) so the BPS-sum is invariant trivially — BUT REBAL-01 demands the SPEC **enumerate the COMPLETE pool-BPS set** and confirm it sums to 10 000. ⚠ The 5 constants near :294-298 (WHALE 1000 / AFFILIATE 3500 / LOOTBOX 2000 / REWARD 500 / PRESALE_BOX 1000) sum to only **8000** — the remaining ~2000 bps live in other pool constants the SPEC MUST locate and include in the attestation. Also attest no other pool/constant is perturbed and total sDGNRS supply is unchanged (only the affiliate↔reward split shifts; `Pool.Reward` 50B→100B; affiliate per-share ~14% haircut).
- **D-12:** JACK: delete the `isFinalDay` `Pool.Reward` branch in `_paySoloBucket` (`DegenerusGameJackpotModule.sol:1339-1352`) + the `FINAL_DAY_DGNRS_BPS=100` constant (:191) + the `JackpotDgnrsWin` event (decl :112). Scout-confirmed BOTH are cleanly orphaned by the deletion (`FINAL_DAY_DGNRS_BPS` sole use :1343 inside the branch; `JackpotDgnrsWin` sole emit :1350 inside the branch). SPEC must attest the rest of the `isFinalDay` plumbing is PRESERVED — the `lvl+1` ticket-index gate (:617) and the `_paySoloBucket` callers (:1085/1095/1135/1161/1190/1312) untouched.

### Grep-Attestation / Edit-Order (BATCH-01 close-out)
- **D-13:** Grep-attest EVERY cited `file:line` vs the v50.0-closure HEAD `812abeee`; correct any drift in the SPEC. ✅ Scout already confirmed `git diff 812abeee HEAD -- contracts/` is **EMPTY** (the only commits since `812abeee` are v51 planning docs) → **grepping at current HEAD == grepping at `812abeee`** for `contracts/`; no contract drift to reconcile. The SPEC's output includes the producer-before-consumer edit-order map for the 340 diff: storage + new module + `ContractAddresses` → `DegenerusGame.claimBingo` delegatecall + interface → `StakedDegenerusStonk` rebalance → `JackpotModule` deletion.

### Claude's Discretion
- Exact SPEC.md section structure / formatting (mirror the v50.0 Phase 334 SPEC layout precedent).
- The freeze-proof depth (D-04) defaulted to rigorous structured enumeration — user may downgrade on request.
- Whether the slot-width cap note (D-01) is a one-liner or a short paragraph — author's call, must be present either way.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Locked design + scope (read first)
- `.planning/PLAN-V51-CLAIMBINGO-COLOR-COMPLETION.md` — the authoritative locked design: full reward economics, validation sketch, storage/constants, game-theory/Monte-Carlo, the 7 "Open before SPEC" items, and the "What this replaces" (JACK) section. **The single most important ref.**
- `.planning/REQUIREMENTS.md` — the 18 v51.0 REQ-IDs (BINGO-01..06 · REBAL-01 · JACK-01/02 · TST-01..06 · BATCH-01/02/03). Phase 339 owns **BATCH-01 + BINGO-06**.
- `.planning/ROADMAP.md` §"Phase 339" — the 5 Success Criteria (the SPEC's acceptance contract) + the cross-cutting re-attestation rule.

### Source anchors to grep-attest vs `812abeee` (all scout-confirmed live at HEAD == baseline)
- `contracts/storage/DegenerusGameStorage.sol:416` — `mapping(uint24 => address[][256]) internal traitBurnTicket;` (traitId fits `uint8`/256 fixed slots; inner `address[]` dynamic). Storage shape (:404-416 region) for the 3 new mappings.
- `contracts/DegenerusTraitUtils.sol:17-39` — trait byte layout `[QQ][CCC][SSS]` (Q 7-6, C 5-3, S 2-0); confirms `traitId` derivation.
- `contracts/modules/DegenerusGameJackpotModule.sol` — JACK deletion: branch `:1339-1352`, constant `:191`, event decl `:112` + sole emit `:1350`; preserved plumbing `:617` + callers `:1085/1095/1135/1161/1190/1312`; `traitBurnTicket` population site `:654`.
- `contracts/DegenerusGame.sol` — `traitBurnTicket` population sites `:2701 / 2730 / 2813` (the BINGO-01 soundness write-sites, D-02); the `GAME_*_MODULE.delegatecall` dispatch pattern for wiring `claimBingo`.
- `contracts/StakedDegenerusStonk.sol:294-298` — REBAL pool-BPS constants (`AFFILIATE` :295, `REWARD` :297); SPEC must enumerate the FULL pool-BPS set for the 10 000-sum invariant (the 5 visible sum to 8000 — find the rest).
- `contracts/modules/DegenerusGameDegeneretteModule.sol:1135-1159` — the `transferFromPool(Pool.Reward,…)` reference pattern (`_awardDegeneretteDgnrs`).
- `contracts/modules/DegenerusGameMintModule.sol:1319` — the `coinflip.creditFlip(…)` BURNIE reference pattern.
- `contracts/ContractAddresses.sol` — add `GAME_BINGO_MODULE` here (freely modifiable).

### Audit-weighting / freeze invariants (memory-locked constraints)
- `v45-vrf-freeze-invariant` — every var interacting with a VRF word must be frozen [request→unlock] vs players; the read must consume post-resolution, not buffered-for-next.
- `threat-model-reentrancy-mev-nonissues` — USER-LOCKED audit weighting: RNG/freeze DOMINANT; MEV LOW/confirmatory (justifies D-03 + D-04 defaults).
- `feedback_security_over_gas`, `feedback_verify_call_graph_against_source`, `feedback_frozen_contracts_no_future_proofing`, `feedback_contractaddresses_policy` — governing constraints.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`transferFromPool` draw pattern** — `_awardDegeneretteDgnrs` (`DegeneretteModule.sol:1135-1159`) is the exact sDGNRS-from-`Pool.Reward` model `claimBingo` copies (incl. the clamped-return-as-paid-amount idiom → no manual clamp needed).
- **`coinflip.creditFlip` pattern** — `MintModule.sol:1319` is the BURNIE-flip-credit model (uncapped emission, same path as autoBuy bounty / affiliate kickback → no new inflation surface).
- **`traitBurnTicket` map** — already fully populated for jackpot winner selection (read-only consumer; we add NO writes to it).
- **Module-delegatecall scaffold** — 8 existing `GAME_*_MODULE` entrypoints in `DegenerusGame.sol` give the copy-paste wiring shape for `claimBingo` → `GAME_BINGO_MODULE`.

### Established Patterns
- **Delegatecall module architecture** — modules share `DegenerusGameStorage.sol`'s layout; new storage MUST be appended there (not declared in the module). Pre-launch redeploy-fresh → appending is safe, no migration (`feedback_frozen_contracts_no_future_proofing`).
- **Graceful no-op on empty pool** — Degenerette + coinflip-bounty both already no-op on a drained `Pool.Reward`; `claimBingo` matches.
- **Trait byte `[QQ][CCC][SSS]`** — the canonical packing; `(quadrant<<6)|(c<<3)|symInQ` is the consistent index.

### Integration Points
- `DegenerusGame.claimBingo` external entrypoint → `ContractAddresses.GAME_BINGO_MODULE.delegatecall`.
- New shared storage in `DegenerusGameStorage.sol`: `bingoClaimed` / `firstQuadrant` / `firstSymbol` (keyed by `uint24`).
- New `GAME_BINGO_MODULE` address constant in `ContractAddresses.sol`.
- The interface (`IDegenerusGame` or equivalent) gains the `claimBingo` signature.
- JACK deletion is in the SAME module file (`DegenerusGameJackpotModule.sol`) the BINGO module reads `traitBurnTicket` from → the SPEC reconciles the shared storage so the read-only consumer + the final-day deletion land coherently in one diff.

</code_context>

<specifics>
## Specific Ideas

- The user picked the **recommended option on every discussed gray area** (uint32[8] · full write-site attestation · whale-race-as-locked-non-finding) and skipped the freeze-proof-depth question — signaling "keep it light, trust the locked design + the safe defaults." The SPEC should be a faithful design-lock + the rigorous freeze/soundness proofs, NOT a re-litigation of settled economics.
- "PROVEN not assumed" is the recurring directive (BINGO-06, the call-graph rule). The precedent that justifies it: the `DegenerusGame` mint/jackpot inline-duplication caught in prior milestones — no "single fn reaches all paths" claim survives un-checked.

</specifics>

<deferred>
## Deferred Ideas

- **Bingo progress view helper** (frontend read-only "which first-prizes are still up for grabs / claimable for me") — explicitly out of v51 scope; deferred follow-up module.
- **The internal 3-skill adversarial sweep + delta-audit + `audit/FINDINGS-v51.0.md`** — DEFERRED → the v52 consolidated audit (cumulative v50 + v51 surface). NOT a Phase 339 concern beyond enumerating the v51 surface for the v52 charge at TERMINAL.
- **Cross-level / multi-level bingo, 2nd/3rd-place ladders, commit-reveal anti-MEV, `Pool.Reward` refill automation** — all explicit non-goals (locked in the plan doc / REQUIREMENTS Out of Scope).
- **Q3 (Dice) special-case naming** — UI string only; validation identical, no contract effect.

None of the above arose as scope creep in this discussion — they were pre-recorded non-goals. Discussion stayed within phase scope.

</deferred>

---

*Phase: 339-spec-design-lock-rng-freeze-safety-proof-tier-precedence-loc*
*Context gathered: 2026-05-28*
