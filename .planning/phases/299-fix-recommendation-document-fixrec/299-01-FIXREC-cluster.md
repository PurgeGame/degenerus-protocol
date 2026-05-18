# Phase 299 — Plan 01 — FIXREC Cluster A

**Cluster:** A — `dailyHeroWagers[day][q]` (S-02) + `autoRebuyState[beneficiary]` (S-05) slot family.

**Scope:** 8 logical VIOLATIONs from `.planning/RNGLOCK-CATALOG.md` §16:

| §N | V-NNN | Slot | Writer fn | Callsite | Tactic | H-NN |
|----|-------|------|-----------|----------|--------|------|
| §1 | V-003 | S-02 `dailyHeroWagers[day][q]` | `_placeDegeneretteBetCore` | `DegeneretteModule.sol:367` (EOA `placeDegeneretteBet`) | (b) | H-01 |
| §2 | V-004 | S-02 `dailyHeroWagers[day][q]` | `_placeDegeneretteBetCore` | `DegenerusGame.sol:714` (parent dispatch) | (b) | H-02 |
| §3 | V-005 | S-02 `dailyHeroWagers[day][q]` | `_placeDegeneretteBetCore` | `DegenerusVault.sol:607` (vault-routed) | (b) | H-03 |
| §4 | V-009 | S-05 `autoRebuyState[beneficiary]` | `_setAutoRebuy` | `DegenerusGame.sol:1495` (EOA `setAutoRebuy`) | (a) | H-04 |
| §5 | V-010 | S-05 `autoRebuyState[beneficiary]` | `_setAutoRebuyTakeProfit` | `DegenerusGame.sol:1504` (EOA `setAutoRebuyTakeProfit`) | (a) | H-05 |
| §6 | V-011 | S-05 `autoRebuyState[beneficiary]` | `_setAfKingMode` | `DegenerusGame.sol:1559` (EOA `setAfKingMode`) | (a) | H-06 |
| §7 | V-012 | S-05 `autoRebuyState[beneficiary]` | `_deactivateAfKing` | `DegenerusGame.sol:1641` (`deactivateAfKingFromCoin` BurnieCoin callback) | (a) | H-07 |
| §8 | V-013 | S-05 `autoRebuyState[beneficiary]` | `syncAfKingLazyPassFromCoin` | `DegenerusGame.sol:1654` (BurnieCoinflip callback) | (a) | H-08 |

Section numbering is local to this cluster file; the Wave-2 aggregator renumbers globally. Per `D-43N-AUDIT-ONLY-01` this artifact is read-only analysis — zero `contracts/` and zero `test/` mutations occur during plan execution.

Per `feedback_no_history_in_comments.md`, prose describes what IS (current VIOLATION state + recommended target state), not what changed.

---

## §1 — V-003 (`dailyHeroWagers[day][q]` via `_placeDegeneretteBetCore` at DegeneretteModule.sol:367)

### §1.A — Design-intent backward-trace

**Slot introduction.** `dailyHeroWagers` is declared at `contracts/storage/DegenerusGameStorage.sol:1485` as `mapping(uint32 => uint256[4]) internal dailyHeroWagers;` — four packed-uint32 slots per day, one per hero quadrant, each accumulating up to eight per-symbol weighted ETH wagers. The writer at `contracts/modules/DegenerusGameDegeneretteModule.sol:499` SSTORES `dailyHeroWagers[day][heroQuadrant] = wPacked` where `day = _simulatedDayIndex()` (wall-clock-derived). The reader at `contracts/modules/DegenerusGameJackpotModule.sol:1653` is `_rollHeroSymbol(dailyIdx, heroEntropy)` — a weighted random roll across the four packed quadrant slots, used by `_applyHeroOverride` to force the hero-symbol byte into the winning trait quadrant during every jackpot resolution call (CALL 1 + CALL 2 of the 2-call ETH-split, plus the coin-and-tickets phase).

**Phase 288 dailyIdx precedent.** Per `.planning/milestones/v41.0-phases/288-f-41-03-cross-day-call-1-call-2-determinism-fix-fix-jpsurf/288-01-DESIGN-INTENT-TRACE.md` §(iii), `dailyIdx` is written ONLY by `_unlockRng` (AdvanceModule:1730) AFTER all CALL 1 + CALL 2 + coin-and-tickets phases complete for a given day's cycle. Phase 288 swapped the consumer read from `_simulatedDayIndex()` to `dailyIdx` so both calls of the 2-call split read the IDENTICAL slot regardless of physical-day-boundary crossings during a stalled jackpot. Quote (Phase 288 trace §(iii) line 35): *"Reading `dailyHeroWagers[dailyIdx]` instead of `dailyHeroWagers[_simulatedDayIndex()]` makes BOTH calls of the 2-call split read the IDENTICAL slot regardless of cross-day timing."*

**Design intent for the slot's existence.** The hero-override is a community contest: players nominate `(quadrant, symbol)` pairs via ETH degenerette bets, the top-wagered symbol per quadrant becomes the forced override for the NEXT jackpot. Phase 288 §(i) line 11-13 establishes the canonical model: bets placed on day D contribute to day D+1's jackpot hero override; bets placed on day D MUST NOT influence day D's own jackpot (would create a within-cycle frontrun). The contest is on a stable historical population — the jackpot reads a SETTLED slot, not a live one.

**Why a naive gate would break behavior.** A blanket `if (rngLockedFlag) revert RngLocked()` on `placeDegeneretteBet` would unnecessarily block ETH betting throughout the rng-lock window — which spans the entire 2-call ETH split plus the coin-and-tickets phase. Bets that target day D+1's hero override are functionally unrelated to day D's resolution and need not be rejected; the canonical Phase 288 mental model (`slot[D] = bets placed on day D`) is preserved only if writes for day D+1 are permitted to land in `slot[D+1]` while the consumer reads `slot[dailyIdx]` (= `slot[D]`). The asymmetric solution is to gate the WRITE on `slot != dailyIdx` (or equivalently freeze the read-slot anchor at lock time), not gate the entire entry.

**Cross-day-passive gap.** Per Phase 288 §(ii), the writer's `_simulatedDayIndex()` is wall-clock-derived. During the rng-lock window the consumer reads `dailyHeroWagers[dailyIdx]` (frozen, slot of the prior day). If the wall clock has NOT yet rolled, `_simulatedDayIndex() == dailyIdx + 1` (current betting day) and writes land in `slot[dailyIdx + 1]` — DISJOINT from the consumer read — and the invariant is preserved by clock geometry alone. The Phase 299 VIOLATION arises in the opposite case: when `_simulatedDayIndex() == dailyIdx` (within the resolution window before `_unlockRng` advances dailyIdx, OR during cross-day stalls where dailyIdx has been bumped to the NEW day and writes target that new day's slot just as the consumer reads it). Phase 288 closed F-41-03 between CALL 1 / CALL 2 via the `dailyIdx` consumer-swap; Phase 299 closes the parallel writer-side window where an EOA bet co-mutates `dailyHeroWagers[dailyIdx][q]` between VRF request and fulfillment.

### §1.B — Actor game-theory walk

Per `feedback_rng_commitment_window.md` — every RNG audit must check what player-controllable state can change between VRF request and fulfillment. Per `feedback_rng_backward_trace.md` — trace BACKWARD from the consumer to verify the word was unknown at input commitment time. The consumer `_rollHeroSymbol(dailyIdx, heroEntropy)` at JackpotModule.sol:1639 keccak-hashes `(heroEntropy, day)` and consumes the result modulo `effectiveTotal` (= weighted sum across the eight per-symbol slots), THEN selects the winning slot via cumulative-cursor walk over weights derived from `dailyHeroWagers[dailyIdx][q]`. The weights are SLOAD'd inside the rng-lock window. An attacker who mutates a weight after VRF request but before fulfillment shifts the cumulative-cursor boundary, redistributing the win probability.

**Actor class:** ETH-funded player or MEV bot (single transaction; no special role required). Bet entry is unrestricted external `placeDegeneretteBet` at DegeneretteModule.sol:367.

**Action sequence during rngLock window:**

1. Player observes `_requestRng` has been triggered (publicly visible via Chainlink VRF request event OR `rngRequestTime != 0` SLOAD).
2. Player observes the pending VRF request seed and the current `dailyIdx == D-1` (frozen during the lock per Phase 288 §(iii)).
3. Player snapshots `dailyHeroWagers[D-1][0..3]` (4 SLOADs; cheap public read).
4. Player computes, for the publicly-known but not-yet-fulfilled `heroEntropy` value range (or speculatively for any plausible value), which `(quadrant, symbol)` slot a marginal-amount bet would push into the leader position, thereby flipping which symbol gets the `leaderBonus = maxAmount / 2` ×1.5 multiplier.
5. Player fires `placeDegeneretteBet{value: X}(player, CURRENCY_ETH, amountPerTicket, 1, customTicket, heroQuadrant)`. The write at DegeneretteModule.sol:499 mutates `dailyHeroWagers[_simulatedDayIndex()][heroQuadrant]`; in the worst case `_simulatedDayIndex() == dailyIdx`, the write lands on the slot the consumer will read.
6. VRF callback fires; `_applyHeroOverride` consumes the mutated weight vector; the player's preferred `(quadrant, symbol)` becomes the forced hero in the winning traits.

**EV magnitude.** MEDIUM-tier. The hero override only flips one byte of one trait quadrant; the dominant payout determinants are the bucket-mask roll (`_pickSoloQuadrant`), prizePool size, and ticket-queue level distribution — none of which depend on `dailyHeroWagers`. The hero-override's economic effect is per-day-jackpot SCOPED to whichever winners' trait matches the forced symbol — a partial EV redirect of typically 0.5%–5% of the daily ETH prize-pool to the attacker's preferred symbol. CATASTROPHE-tier is reserved for slots that directly feed roll selection (e.g. autoRebuyState afKingMode in §6/§7/§8 — finalist redirect at jackpot award time); dailyHeroWagers manipulates a side-channel byte in the hero-symbol roll, not the underlying jackpot bucket math.

**Economic likelihood: MEDIUM.** Per-bet cost is small (`amountPerTicket` minimum is enforced by `_validateMinBet` but is well below the marginal hero-flip EV at non-trivial prize-pool sizes). Bot infrastructure to observe `rngRequestTime` and chain a place-bet transaction in the lock window is well-precedented in the protocol (Phase 296 SWEEP demonstrated MEV reach across cross-contract surfaces).

### §1.C — Recommended tactic + rationale + impact estimate

**Tactic: (b) snapshot/anchor pattern.** Per catalog §16 row V-003 rationale: *"Phase 288 dailyIdx snapshot; freeze read-day at lock time."*

**Rationale.** A blanket `rngLockedFlag` gate (tactic (a)) on `placeDegeneretteBet` is wrong because betting must remain live during the lock window for the canonical-Phase-288 reason: bets placed during day D (which the rng-lock window may straddle if cross-day stalls occur) target day D+1's hero override and are functionally unrelated to day D's resolution. The asymmetric remediation is to freeze the consumer-read anchor at lock time so the consumer no longer reads the slot the writer is currently mutating. Two implementation options exist for (b):

1. **Snapshot the 4 packed quadrant SLOADs into a transient stack/memory anchor at `_requestRng` time** and pass the anchor through `_applyHeroOverride` invocations within a single jackpot resolution. This eliminates the cross-day-passive surface AND the active EOA-frontrun surface in one move. Bytecode delta: ~80–120 bytes (4 SLOADs + 4 memory writes at the lock-flag-set site; struct-encoded read of the anchor inside `_rollHeroSymbol`).

2. **Add a write-side check in `_placeDegeneretteBetCore` at DegeneretteModule.sol:486** that rejects writes targeting `_simulatedDayIndex() == dailyIdx`: writes for the prior-day slot are exactly the slot the rng-lock-window consumer reads, so during the lock the write is invalid for that day. Bytecode delta: ~30 bytes (1 SLOAD of `dailyIdx` + 1 SLOAD of `rngLockedFlag` + 1 conditional branch). Storage delta: 0. This option deviates from the "snapshot" terminology of catalog (b) but achieves the same invariant via write-time anchor rejection rather than read-time snapshot — semantically equivalent at the consumer's freshness boundary.

v44.0 plan-phase selects between (1) and (2) at sub-phase planning; both satisfy the Phase 298 catalog (b) classification.

**Storage-layout impact.** Zero. Both options re-use the existing slot ID `dailyHeroWagers[day][q]` and the existing `dailyIdx` + `rngLockedFlag` SLOADs.

**Public ABI impact.** Zero per `D-40N-EVT-BREAK-01` + `D-42N-EVT-BREAK-01`. Option 1 emits no new event topic; option 2 emits no new event topic. Option 2 introduces a new `RngLocked` revert path on `placeDegeneretteBet` for the within-day-lock case; per the catalog (`RngLocked` custom error pattern at MintModule:1221 / BurnieCoinflip:730 / sStonk:492 / DegenerusGameStorage.sol:213), this is a non-breaking surface-extension because `RngLocked` is already an inherited error type the surrounding modules emit.

**Bytecode impact estimate.** Option 1: +80–120 bytes. Option 2: +30–50 bytes. Both well below the 24KB EIP-170 module size ceiling.

### §1.D — v44.0 handoff anchor

**Anchor:** D-43N-V44-HANDOFF-01 — Apply Phase 288 `dailyIdx` snapshot-anchor pattern to `dailyHeroWagers[dailyIdx][q]` so within-day EOA `placeDegeneretteBet` writes during rng-lock cannot mutate the slot the consumer reads. **Catalog row:** RNGLOCK-CATALOG.md:338 (V-003). **Writer:** `contracts/modules/DegenerusGameDegeneretteModule.sol:499` reached from external entry at `:367`.

---

## §2 — V-004 (`dailyHeroWagers[day][q]` via `_placeDegeneretteBetCore` at DegenerusGame.sol:714)

### §2.A — Design-intent backward-trace

**Same slot, same writer, distinct callsite.** `DegenerusGame.placeDegeneretteBet` at `contracts/DegenerusGame.sol:714` is the parent-contract dispatcher: it `delegatecall`s to `ContractAddresses.GAME_DEGENERETTE_MODULE.placeDegeneretteBet` (DegenerusGame.sol:722–737). Because Solidity delegatecall preserves storage context, the SSTORE in `_placeDegeneretteBetCore` at DegeneretteModule.sol:499 lands in the SAME storage slot of the SAME `DegenerusGame` instance regardless of whether entry is the module's external function (§1) or the parent's dispatcher (§2). The verdict matrix splits these as separate rows per `D-298-EXEMPT-CROSSCONTRACT-01` strict per-callsite discipline: the same writer function reached from a different callsite gets its own verdict row even when the underlying SSTORE is identical.

**Why the parent dispatcher exists.** The parent `DegenerusGame` is the user-facing contract address; off-chain UIs target its ABI. The dispatcher pattern at DegenerusGame.sol:714–737 forwards calldata to the module via delegatecall so that callers see a uniform `DegenerusGame.placeDegeneretteBet(...)` entrypoint without needing to know about module-routing internals. The dispatcher itself performs no business logic — it is a thin selector-forwarding shim with `_resolvePlayer(player)` pre-resolution.

**Phase 288 precedent.** Same trace as §1.A. The Phase 288 `dailyIdx` snapshot/freeze invariant applies identically at this callsite because the underlying SSTORE is the same.

**Why a naive gate would break behavior.** Same as §1.A — the dispatcher path must remain open during the lock window for bets that target the NEXT day's hero-override slot.

### §2.B — Actor game-theory walk

Same actor class, action sequence, EV, and likelihood as §1.B. The parent-dispatcher path is in fact the path off-chain wallets actually hit (the module-direct path is uncommon since DegenerusGame.sol is the canonical address documented to the front-end). For Phase 299 audit purposes the parent-dispatcher VIOLATION row carries the realistic-exploit weight; the module-direct row (§1) is preserved for catalog completeness per strict per-callsite enumeration.

Per `feedback_rng_commitment_window.md`, the player-controllable surface from this callsite is identical: `dailyHeroWagers[dailyIdx][q]` SLOADed inside the rng-lock window can be mutated by a single EOA transaction targeting `DegenerusGame.placeDegeneretteBet`.

**EV magnitude.** MEDIUM-tier (same as §1.B). The parent-dispatcher entry is the realistic-attack path; the EV ceiling is identical because the writer body is identical.

**Economic likelihood: MEDIUM-to-HIGH** (higher than §1.B because the parent-dispatcher entry is the path with public ABI exposure; bots looking for arbitrary attack surface target the parent contract, not the module).

### §2.C — Recommended tactic + rationale + impact estimate

**Tactic: (b) snapshot/anchor pattern.** Per catalog §16 row V-004 rationale: *"Parent dispatch — same day-key freeze attestation."*

**Rationale.** The remediation tactic is identical to §1.C because both V-003 and V-004 mutate the same storage slot via the same writer body. A SINGLE remediation — applied at the SSTORE site DegeneretteModule.sol:499 or at the consumer SLOAD site JackpotModule.sol:1653 — covers both V-003 and V-004 callsites simultaneously. The verdict matrix splits the rows for catalog-completeness discipline; the v44.0 sub-phase implementing the fix touches one (writer-side) or zero+one (consumer-side) lines of source and resolves V-003 + V-004 with the same diff.

**Storage-layout impact.** Zero (same as §1.C).

**Public ABI impact.** Zero. The parent dispatcher's `placeDegeneretteBet` selector is preserved; option 2 adds a `RngLocked` revert path co-extensive with §1.C.

**Bytecode impact estimate.** Zero incremental delta beyond §1.C (single source-line fix covers both callsites).

### §2.D — v44.0 handoff anchor

**Anchor:** D-43N-V44-HANDOFF-02 — Same snapshot/freeze attestation as H-01 applied to the parent-dispatcher reach of `_placeDegeneretteBetCore`; v44.0 sub-phase consolidates H-01 + H-02 into one diff at the writer or consumer site. **Catalog row:** RNGLOCK-CATALOG.md:339 (V-004). **Writer:** `contracts/modules/DegenerusGameDegeneretteModule.sol:499` reached via delegatecall from `contracts/DegenerusGame.sol:714`.

---

## §3 — V-005 (`dailyHeroWagers[day][q]` via `_placeDegeneretteBetCore` at DegenerusVault.sol:607)

### §3.A — Design-intent backward-trace

**Vault-routed callsite.** `DegenerusVault.placeDegeneretteBet` at `contracts/DegenerusVault.sol:607` is a vault-multisig wrapper: a vault-owner role (51%+ DGVE holder per the `onlyVaultOwner` modifier at DegenerusVault.sol:601) invokes `gamePlayer.placeDegeneretteBet{value: value}(address(this), ...)` — a regular external call into `DegenerusGame.placeDegeneretteBet` (§2) with the vault as the bet-placer. Once execution enters `DegenerusGame`, the parent dispatcher path of §2 takes over, ultimately delegatecalling the module and SSTOREing at DegeneretteModule.sol:499 with `player == DegenerusVault` and `day == _simulatedDayIndex()`. The storage slot mutated is the same logical `dailyHeroWagers[day][heroQuadrant]` in the game instance.

**Why the vault exists.** The DGVE-token-gated vault allows pooled-capital bet placement: vault depositors (DGVE holders) collectively control the vault's bet treasury and elect a vault-owner to actuate bets. The vault entry exists to support pooled-strategy play without requiring each depositor to actuate bets individually.

**Phase 288 precedent.** Same trace as §1.A. The vault path is an additional EOA-reachable surface (the vault-owner is an EOA satisfying `onlyVaultOwner`) that targets the identical storage slot.

**Why a naive gate would break behavior.** Same as §1.A. Additionally, vault depositors expect the vault to remain capable of placing bets through the lock window when those bets target the next-day slot; a blanket revert at the vault-owner role would block legitimate vault strategy actuation.

### §3.B — Actor game-theory walk

**Actor class:** Vault-owner (EOA holding 51%+ of DGVE per `onlyVaultOwner`) acting as a privileged amplifier — the vault concentrates capital across multiple depositors into a single bet that lands at the same storage slot.

**Action sequence during rngLock window:**

1. Vault-owner observes pending VRF request (same observation channel as §1.B).
2. Vault-owner snapshots `dailyHeroWagers[D-1][0..3]` and computes the marginal-bet threshold to flip the leader position (same as §1.B).
3. Vault-owner calls `DegenerusVault.placeDegeneretteBet{value: X}(...)` — vault treasury funds the bet; per-DGVE-share dilution is borne by depositors. The vault's capital pool may significantly exceed any single EOA's, so the leader-flip threshold can be cleared in a single tx even at large `maxAmount` in the leader slot.
4. Execution flows DegenerusVault.sol:607 → DegenerusGame.sol:714 (§2) → delegatecall to module → SSTORE at DegeneretteModule.sol:499.
5. VRF callback consumes the mutated weight vector; vault-owner's preferred symbol becomes forced hero.

**EV magnitude.** HIGH-tier (one tier above §1.B). The vault's pooled capital allows clearing leader-flip thresholds that a single EOA cannot reach within rational-economics bounds. The vault-owner extracts hero-override redirect EV from the protocol's daily ETH prize-pool at depositors' (DGVE-share-dilution) expense — internal-extraction griefing — but the externally-observable hero-override flip is fully exploitable for downstream MEV (e.g. predicting the forced symbol allows the vault-owner to pre-arrange tickets whose traits intersect the forced quadrant's payout).

**Economic likelihood: MEDIUM-LOW.** The vault-owner role concentrates trust; depositors observe vault bets and can withdraw if the owner mis-acts. But (a) governance-token control of an EOA permission is a recurring DeFi-MEV pattern (compare DEX-vault frontrun cases), and (b) the vault-owner threshold is 51% — concentrated holdings can sustain mis-action across multiple depositor-withdrawal cycles before consequence accrues. Per `feedback_design_intent_before_deletion.md`, the actor walk must enumerate even low-likelihood high-EV paths: HIGH × MEDIUM-LOW = expected-value comparable to §1.B's MEDIUM × MEDIUM.

### §3.C — Recommended tactic + rationale + impact estimate

**Tactic: (b) snapshot/anchor pattern.** Per catalog §16 row V-005 rationale: *"Vault-routed bet — same day-key freeze attestation."*

**Rationale.** Identical to §1.C and §2.C — the underlying SSTORE at DegeneretteModule.sol:499 is the same. A single remediation diff covers V-003 + V-004 + V-005 simultaneously. The vault-routed entry is a leaf callsite that transparently inherits the writer-side or consumer-side anchor.

**Storage-layout impact.** Zero.

**Public ABI impact.** Zero. The vault's `placeDegeneretteBet` selector and the game's `placeDegeneretteBet` selector are both preserved; option-2 `RngLocked` revert path propagates through the vault entry as a normal Solidity bubble-up (the vault's `(bool ok, bytes memory data) = ...` pattern at DegenerusVault.sol:607 catches and re-throws — verify the existing surrounding pattern; if not, the revert bubbles via Solidity default behavior).

**Bytecode impact estimate.** Zero incremental delta beyond §1.C.

### §3.D — v44.0 handoff anchor

**Anchor:** D-43N-V44-HANDOFF-03 — Vault-routed reach of `_placeDegeneretteBetCore` resolved by the same writer-side or consumer-side snapshot/freeze applied to H-01 + H-02; v44.0 sub-phase verifies the vault entry inherits the gate transparently and emits a vault-side regression test asserting the `RngLocked` revert bubbles through `gamePlayer.placeDegeneretteBet`. **Catalog row:** RNGLOCK-CATALOG.md:340 (V-005). **Writer:** `contracts/modules/DegenerusGameDegeneretteModule.sol:499` reached via external call from `contracts/DegenerusVault.sol:607`.

---

## §4 — V-009 (`autoRebuyState[beneficiary]` via `_setAutoRebuy` at DegenerusGame.sol:1495)

### §4.A — Design-intent backward-trace

**Slot introduction.** `autoRebuyState` is declared as `mapping(address => AutoRebuyState) internal autoRebuyState` in `DegenerusGameStorage`. The struct packs `{ bool autoRebuyEnabled, uint128 takeProfit, bool afKingMode, uint24 afKingActivatedLevel }` and is consumed by §1 of the catalog (JackpotModule.payDailyJackpot at `:339`) during finalist-redirect — the auto-rebuy state determines whether a player's winning ETH gets converted back into next-level (or next+1) tickets vs paid out as claimable. The afKing-mode arm additionally affects the rebuy bonus rate (30% default → 45% with afKing) and clamps `takeProfit` to floors (5 ETH / 20k BURNIE).

**Writer chain.** `setAutoRebuy(address player, bool enabled)` at DegenerusGame.sol:1495 is an external EOA entry. It resolves `_resolvePlayer(player)` and invokes `_setAutoRebuy(player, enabled)` at `:1512`. The private writer at `:1512–:1522` performs `if (rngLockedFlag) revert RngLocked();` at `:1513` (runtime gate ALREADY PRESENT), then SSTOREs `state.autoRebuyEnabled = enabled` at `:1516`, emits `AutoRebuyToggled`, and (if disabling) cascades into `_deactivateAfKing(player)` at `:1520`.

**Why the slot exists.** Auto-rebuy is a player-side UX toggle: rather than manually re-buying tickets each level, the player opts into automatic conversion of their winnings into next-level tickets. The state must be player-settable on demand outside the rng-lock window so the player can react to evolving game state (level progression, prize-pool changes, jackpot outcomes) between resolutions.

**Why a naive blanket gate would break behavior.** The runtime gate at DegenerusGame.sol:1513 IS the correct design: it blocks writes during the rng-lock window so the jackpot consumer's SLOAD of `autoRebuyState[winner]` is not co-mutated by the winner themselves. The slot is unwriteable during finalist-redirect, exactly the desired invariant.

**Catalog coverage attestation.** Per catalog §16 V-009 rationale: *"Gate already at DegenerusGame:1513; FUZZ-301 verify branch coverage."* Phase 299 documents that V-009's gate is PRESENT and the Phase 299 deliverable for this row is a coverage-verification handoff (FUZZ test asserts the revert fires across the full rng-lock window for every reachable `setAutoRebuy(...)` invocation pattern), not a new gate-install.

### §4.B — Actor game-theory walk

Per `feedback_rng_window_storage_read_freshness.md` — non-VRF SLOADs inside the rng-window consumed alongside RNG are a distinct bug class. The jackpot consumer at JackpotModule.payDailyJackpot SLOADs `autoRebuyState[winner]` to determine the finalist-redirect rule (tickets vs claimable). If a winner mutates their own `autoRebuyEnabled` between VRF request and fulfillment, they can redirect their winnings between the two pools based on knowledge gained after VRF observation but before the jackpot SSTOREs the redirect.

**Actor class:** Player (any holder; no special role).

**Action sequence during rngLock window (PRE-GATE scenario, what the gate prevents):**

1. Player observes pending VRF request and the imminent jackpot resolution.
2. Player models their probability of finishing in the winner cohort under each possible VRF word value (publicly inferable from on-chain state).
3. Player models their downstream EV under (a) tickets redirect vs (b) claimable-pool payout, conditional on the predicted winning level and the next-level prize-pool size.
4. Player calls `setAutoRebuy(player, enabled')` to flip the redirect ELECTION ex-ante of VRF fulfillment but ex-post of VRF request — gaining a free option on which payout pool to receive.
5. The runtime gate at DegenerusGame.sol:1513 REJECTS the tx with `RngLocked` revert; the elective state cannot be mutated inside the rng-lock window.

**EV magnitude.** HIGH-tier IF the gate were absent. The finalist-redirect election affects 100% of the winner's payout, not a per-symbol byte side-channel. Without the gate, the player extracts a free option on which payout pool to receive — the option's value equals `|EV(tickets-path) − EV(claimable-path)|` per winner, which at large prize-pool sizes can exceed several ETH per cycle. Per Phase 299 cluster preamble, autoRebuyState is HIGH-tier because afKing mode is the per-jackpot-day finalist-redirect-rule input.

**Economic likelihood: covered.** The gate at `:1513` prevents the action sequence from completing; the EOA observes the revert and abandons the attempt. The Phase 299 deliverable for V-009 is FUZZ-301 coverage verification — that the gate fires at every callsite reachable under every state combination.

### §4.C — Recommended tactic + rationale + impact estimate

**Tactic: (a) rngLockedFlag-gated revert.** Per catalog §16 row V-009 rationale: *"Gate already at DegenerusGame:1513; FUZZ-301 verify branch coverage."*

**Rationale.** The gate is already installed at the private writer entry point `_setAutoRebuy` at DegenerusGame.sol:1513. Phase 299's deliverable for this VIOLATION row is the v44.0 sub-phase that authors a fuzz/property test confirming:

- Every callsite of `_setAutoRebuy(...)` (currently only `setAutoRebuy` at `:1495` and the cascade from `_setAutoRebuyTakeProfit` at `:1536` → `_deactivateAfKing`) is exercised under `rngLockedFlag == true`.
- The revert fires for every `(player, enabled)` input combination during the lock.
- The revert message decodes to `RngLocked()` (selector `0x...` — verify against `DegenerusGameStorage.sol:213`).

The catalog (a) classification is "gated revert"; the gate IS the revert. The completion criterion is coverage attestation, not gate-install.

**Storage-layout impact.** Zero. No slot added.

**Public ABI impact.** Zero. The `setAutoRebuy(address,bool)` selector is preserved; the `RngLocked` revert is already an inherited error per DegenerusGameStorage.sol:213.

**Bytecode impact estimate.** Zero (gate already compiled in at `:1513`).

**FUZZ test scope.** Phase 301 FUZZ harness should add a property: ∀ player p, ∀ enabled e, when `rngLockedFlag == true`, `DegenerusGame.setAutoRebuy(p, e)` reverts with `RngLocked()` selector. The harness MUST reach `_setAutoRebuy` from the parent dispatcher (DegenerusGame.sol:1495), not just the internal helper, so the dispatcher → private-writer call path is included in the coverage trace.

### §4.D — v44.0 handoff anchor

**Anchor:** D-43N-V44-HANDOFF-04 — Confirm by fuzz test (Phase 301 harness) that the `rngLockedFlag` gate at DegenerusGame.sol:1513 fires for every reachable invocation of `setAutoRebuy(address,bool)` across the rng-lock window. No source change expected; coverage-attestation only. **Catalog row:** RNGLOCK-CATALOG.md:344 (V-009). **Writer:** `contracts/DegenerusGame.sol:1512` (private `_setAutoRebuy`) reached from external entry at `:1495`.

---

## §5 — V-010 (`autoRebuyState[beneficiary]` via `_setAutoRebuyTakeProfit` at DegenerusGame.sol:1504)

### §5.A — Design-intent backward-trace

**Same slot, parallel writer.** `setAutoRebuyTakeProfit(address player, uint256 takeProfit)` at DegenerusGame.sol:1504 is the parallel EOA entry for setting the `takeProfit` field of `AutoRebuyState`. It resolves the player and invokes `_setAutoRebuyTakeProfit` at `:1524`. The private writer at `:1524–:1538` performs `if (rngLockedFlag) revert RngLocked();` at `:1528` (runtime gate PRESENT), SSTOREs `state.takeProfit = uint128(takeProfit)` at `:1532`, emits `AutoRebuyTakeProfitSet`, then (if takeProfit < AFKING_KEEP_MIN_ETH and non-zero) cascades into `_deactivateAfKing(player)` at `:1536`.

**Why the slot exists.** `takeProfit` is the amount of player winnings reserved for manual claim (not auto-rebuy'd). It is a player-side preference that determines the split between (a) "tickets-via-auto-rebuy" and (b) "claimable-via-takeProfit-reserve" pools. The user controls this per their off-chain strategy.

**Why a naive blanket gate would break behavior.** Same as §4.A — the runtime gate at `:1528` IS the correct design. Outside the lock window the player needs free read/write access to retune their takeProfit allocation; inside the lock window the gate blocks election-mid-resolution.

**Catalog coverage attestation.** Per catalog §16 V-010 rationale: *"Gate already at DegenerusGame:1528 — same coverage gap."* Phase 299 deliverable: FUZZ-301 coverage verification.

### §5.B — Actor game-theory walk

**Actor class:** Player (any holder).

**Action sequence during rngLock window (PRE-GATE scenario):**

1. Player observes pending VRF and models their winner-cohort probability (same as §4.B).
2. Player models their downstream EV under (a) `takeProfit = high` (more claimable reserved) vs (b) `takeProfit = low` (more auto-rebuy'd into tickets).
3. Player calls `setAutoRebuyTakeProfit(player, takeProfit')` to flip the allocation.
4. Runtime gate at DegenerusGame.sol:1528 REJECTS with `RngLocked` revert; the elective allocation cannot be mutated inside the lock window.

**Bonus surface (cascade-side).** Per the writer body at DegenerusGame.sol:1535–1537, setting `takeProfit < AFKING_KEEP_MIN_ETH` AND non-zero cascades into `_deactivateAfKing(player)`. If a player could land a `setAutoRebuyTakeProfit(player, 1 wei)` during the rng-lock window, they would deactivate afKing-mode mid-resolution — but the gate at `:1528` blocks this BEFORE the cascade is reached, so V-010 carries V-011's EV in the rng-lock-mutated case (since afKing mode is the higher-EV slot per the cluster preamble).

**EV magnitude.** HIGH-tier (same as §4.B; cascade-amplified if takeProfit drops below the AFKING floor while afKing is active — see §6.B for afKing-mode EV).

**Economic likelihood: covered by gate.**

### §5.C — Recommended tactic + rationale + impact estimate

**Tactic: (a) rngLockedFlag-gated revert.** Per catalog §16 row V-010 rationale: *"Gate already at DegenerusGame:1528 — same coverage gap."*

**Rationale.** Same as §4.C — the gate is installed at the private writer at `:1528`. Phase 299 deliverable is FUZZ-301 coverage attestation that the revert fires for every reachable `setAutoRebuyTakeProfit` invocation during the lock. Cascade-coverage requirement: the FUZZ harness MUST also assert that the `_deactivateAfKing` cascade at `:1536` is NEVER reached during the lock (because the parent revert at `:1528` fires first), so V-010's gate transitively covers the cascade path into the §7 writer body even when reached via `_setAutoRebuyTakeProfit`.

**Storage-layout impact.** Zero.

**Public ABI impact.** Zero. `setAutoRebuyTakeProfit(address,uint256)` selector preserved.

**Bytecode impact estimate.** Zero (gate already compiled in at `:1528`).

### §5.D — v44.0 handoff anchor

**Anchor:** D-43N-V44-HANDOFF-05 — Fuzz-verify the `rngLockedFlag` gate at DegenerusGame.sol:1528 fires for every reachable invocation of `setAutoRebuyTakeProfit(address,uint256)` AND that the `_deactivateAfKing` cascade at `:1536` is unreachable inside the lock window. No source change expected. **Catalog row:** RNGLOCK-CATALOG.md:345 (V-010). **Writer:** `contracts/DegenerusGame.sol:1524` (private `_setAutoRebuyTakeProfit`) reached from external entry at `:1504`.

---

## §6 — V-011 (`autoRebuyState[beneficiary]` via `_setAfKingMode` at DegenerusGame.sol:1559)

### §6.A — Design-intent backward-trace

**Same slot, afKing-mode writer.** `setAfKingMode(address player, bool enabled, uint256 ethTakeProfit, uint256 coinTakeProfit)` at DegenerusGame.sol:1559 is the EOA entry for toggling afKing mode — the higher-rebuy-rate variant of auto-rebuy that forces auto-rebuy ON for both ETH and BURNIE, clamps `takeProfit` to floors (5 ETH / 20k BURNIE), and requires a lazy-pass (deity pass OR whale-pass `frozenUntilLevel > level`). The private writer at `:1569–:1608` performs `if (rngLockedFlag) revert RngLocked();` at `:1575` (runtime gate PRESENT), then either deactivates (cascading to `_deactivateAfKing` at `:1577`) or activates with full state machine: SSTOREs `state.autoRebuyEnabled = true` at `:1593`, `state.takeProfit = uint128(adjustedEthKeep)` at `:1597`, `state.afKingMode = true` at `:1604`, `state.afKingActivatedLevel = level` at `:1605`. The call also dispatches a cross-contract `coinflip.setCoinflipAutoRebuy(player, true, adjustedCoinKeep)` at `:1600`.

**Why the slot exists.** afKing mode is a "max-grind" lazy-pass-gated rebuy mode that automatically converts winnings to next-level tickets at +50% bonus rate (45% vs 30% baseline). It is intended for lazy-pass holders who commit to the protocol's ticket-purchase grind across multiple levels and accept the AFKING_KEEP_MIN floor as the price of the bonus-rate access.

**Why a naive blanket gate would break behavior.** Same as §4.A — the runtime gate at `:1575` IS the correct design. afKing toggle election outside the lock window is essential for lazy-pass-holders to react to game-state evolution; inside the lock window the gate blocks mid-resolution election.

**Catalog coverage attestation.** Per catalog §16 V-011 rationale: *"Gate already at DegenerusGame:1575 — same coverage gap."* Phase 299 deliverable: FUZZ-301 coverage verification.

### §6.B — Actor game-theory walk

Per the Phase 299 cluster preamble, afKing mode is HIGH-tier because it is the per-jackpot-day finalist-redirect-rule input AND it forces both currencies (ETH + BURNIE) into auto-rebuy with elevated bonus. Combined-pool finalist-redirect manipulation has a strictly larger EV than single-pool manipulation.

**Actor class:** Lazy-pass-holding player (deity pass OR whale-pass `frozenUntilLevel > level` per `_hasAnyLazyPass` at DegenerusGame.sol:1610).

**Action sequence during rngLock window (PRE-GATE scenario):**

1. Player observes pending VRF and models their winner-cohort probability under each possible VRF word.
2. Player models EV under (a) afKing mode ON: 45% bonus on auto-rebuy'd tickets, both ETH+BURNIE pools forced into rebuy, takeProfit clamped to floors vs (b) afKing mode OFF: 30% bonus on ETH only (if `autoRebuyEnabled` separately), free takeProfit allocation.
3. Player calls `setAfKingMode(player, enabled', ethTakeProfit', coinTakeProfit')` to flip the finalist-redirect election between regimes.
4. Runtime gate at DegenerusGame.sol:1575 REJECTS with `RngLocked` revert; the elective regime cannot be mutated inside the lock window.

**EV magnitude.** HIGH-tier (potentially CATASTROPHE-tier at large prize-pool levels). The afKing 45% bonus is applied to the full auto-rebuy stream — at a large daily ETH prize-pool with afKing-flip-redirect, the bonus delta alone can be 15% of the auto-rebuy pool's value, plus the cross-currency BURNIE auto-rebuy redirect, plus the cross-contract `coinflip.setCoinflipAutoRebuy` side-effect at `:1600`.

**Economic likelihood: covered by gate.** The lazy-pass requirement narrows the attack-actor cohort to lazy-pass holders; this is a non-trivial subset of all addresses but is bounded by deity-pass + whale-pass supply.

### §6.C — Recommended tactic + rationale + impact estimate

**Tactic: (a) rngLockedFlag-gated revert.** Per catalog §16 row V-011 rationale: *"Gate already at DegenerusGame:1575 — same coverage gap."*

**Rationale.** Same as §4.C and §5.C — the gate is installed at the private writer at `:1575`. Phase 299 deliverable is FUZZ-301 coverage attestation. Cascade-coverage requirement: the FUZZ harness MUST cover both arms of the writer — (i) `enabled == false` branch at `:1576–:1579` cascading into `_deactivateAfKing` at `:1577`, and (ii) `enabled == true` arm at `:1580–:1607` — both ARE inside the gate's protection scope at `:1575`. The cross-contract dispatch at `:1600` (`coinflip.setCoinflipAutoRebuy`) is also unreachable inside the lock window per the gate.

**Storage-layout impact.** Zero.

**Public ABI impact.** Zero. `setAfKingMode(address,bool,uint256,uint256)` selector preserved.

**Bytecode impact estimate.** Zero (gate already compiled in at `:1575`).

**Cross-contract coupling note.** The `coinflip.setCoinflipAutoRebuy` dispatch at `:1600` writes to BurnieCoinflip state. The gate at `:1575` blocks reach into that dispatch during the lock window; v44.0 sub-phase verifies BurnieCoinflip's own rng-lock-window invariants do NOT also need a parallel gate (since the entry from GAME is closed at GAME).

### §6.D — v44.0 handoff anchor

**Anchor:** D-43N-V44-HANDOFF-06 — Fuzz-verify the `rngLockedFlag` gate at DegenerusGame.sol:1575 fires across both arms of `_setAfKingMode` (deactivate-cascade arm at `:1576–:1579` and full-activate arm at `:1580–:1607` including the cross-contract `coinflip.setCoinflipAutoRebuy` dispatch at `:1600`). No source change expected. **Catalog row:** RNGLOCK-CATALOG.md:346 (V-011). **Writer:** `contracts/DegenerusGame.sol:1569` (private `_setAfKingMode`) reached from external entry at `:1559`.

---

## §7 — V-012 (`autoRebuyState[beneficiary]` via `_deactivateAfKing` at DegenerusGame.sol:1641 / `deactivateAfKingFromCoin`)

### §7.A — Design-intent backward-trace

**MISSING-GATE writer.** `deactivateAfKingFromCoin(address player)` at DegenerusGame.sol:1641 is an external callback entry restricted to `msg.sender == ContractAddresses.COIN || msg.sender == ContractAddresses.COINFLIP` (revert at `:1642–:1645`). It directly invokes `_deactivateAfKing(player)` at `:1646`. The private writer at `:1670–:1682` SSTOREs `state.afKingMode = false` at `:1679`, `state.afKingActivatedLevel = 0` at `:1680`, and emits `AfKingModeToggled(player, false)` at `:1681`. The writer also dispatches `coinflip.settleFlipModeChange(player)` at `:1678` and reverts with `AfKingLockActive` if the deactivation occurs inside the AFKING_LOCK_LEVELS window per `:1675–:1676`.

**Critical gap: NO `rngLockedFlag` gate.** Unlike V-009 / V-010 / V-011, the entry `deactivateAfKingFromCoin` at `:1641` does NOT perform an `if (rngLockedFlag) revert RngLocked()` check. The private `_deactivateAfKing` body at `:1670` also lacks the gate. This is the catalog-flagged MISSING-GATE row.

**Why the slot exists.** afKing mode hooks into the BurnieCoin contract (and BurnieCoinflip) — when a player loses their lazy-pass status via a BurnieCoin transfer that drops their balance below the qualifying threshold, the COIN contract calls back into the game via this entry to deactivate afKing-mode. This is the "lazy-pass slipped, deactivate the dependent state" cross-contract synchronization hook.

**Why EOA-controllable via callback.** Per Phase 299 cluster preamble: *"coin and coinflip callbacks are EOA-triggerable via cheap BurnieCoin transfer / coinflip arming, so the callback path is effectively EOA-controllable."* A player triggers `deactivateAfKingFromCoin` by initiating a BurnieCoin token transfer (or coinflip arming/deposit) that causes COIN's internal hook to invoke `DegenerusGame.deactivateAfKingFromCoin(player)`. The player's cost is the BurnieCoin transfer fee; the effect is mid-rng-lock-window mutation of `autoRebuyState[player].afKingMode` and `afKingActivatedLevel`.

**Why a naive gate would break behavior.** Adding `if (rngLockedFlag) revert RngLocked()` at `:1641` blocks the callback during the lock window. But the cross-contract synchronization-hook semantic requires that lazy-pass-loss events be SOMEWHERE recorded; rejecting the callback during the lock means the COIN side's "I just lost my lazy pass" event is dropped. The remediation must either (i) queue the deactivation until after `_unlockRng`, or (ii) reject the upstream lazy-pass-loss-causing-transfer at COIN, or (iii) accept the gate's "drop" behavior and reconcile lazy-pass state on the next non-locked deactivation reach. v44.0 sub-phase selects between these options.

### §7.B — Actor game-theory walk

**Actor class:** Lazy-pass-holding player with co-incident jackpot stake. Higher-EV variant: a coordinated MEV-bot operating across BurnieCoin + DegenerusGame.

**Action sequence during rngLock window (CURRENT UNGATED state):**

1. Player has afKing mode ACTIVE (per `state.afKingMode == true`) and qualifies as a winner cohort with non-trivial probability under the pending VRF.
2. Player observes pending VRF request (same observation channel as §1.B).
3. Player models their downstream EV under (a) afKing ACTIVE during finalist-redirect (forced full auto-rebuy at 45% bonus) vs (b) afKing INACTIVE during finalist-redirect (no rebuy unless `autoRebuyEnabled` separately is true).
4. Player initiates a BurnieCoin transfer that triggers a lazy-pass-loss event in COIN's accounting, which invokes `DegenerusGame.deactivateAfKingFromCoin(player)`.
5. The callback executes WITHOUT a `rngLockedFlag` gate at `:1641`; reaches `_deactivateAfKing` at `:1670`; sets `state.afKingMode = false` at `:1679`.
6. VRF callback fires; jackpot consumer's SLOAD of `autoRebuyState[player].afKingMode` returns `false`; finalist-redirect rule selects the non-afKing path; player's winnings flow through the lower-friction path the player just elected by canceling afKing.

**Subtlety:** the AFKING_LOCK_LEVELS check at DegenerusGame.sol:1675–1676 (`if (uint256(level) < unlockLevel) revert AfKingLockActive();`) imposes a deactivation cooldown — afKing cannot be deactivated within AFKING_LOCK_LEVELS levels of activation. This partial constraint REDUCES but does not eliminate the rng-lock-window exploit surface: a player whose afKing activation is older than AFKING_LOCK_LEVELS levels can freely deactivate at any moment.

**EV magnitude.** HIGH-tier. The afKing deactivation flips the finalist-redirect rule mid-rng-lock — equivalent EV to §6.B's afKing toggle, with the advantage that the entry path requires only a BurnieCoin transfer (lower-friction than direct `setAfKingMode` call, which is gated). The MISSING-GATE status of this entry is what makes the EV REACHABLE.

**Economic likelihood: HIGH.** A BurnieCoin transfer is cheap. The callback is callable on any block. The actor's only constraint is being past AFKING_LOCK_LEVELS since activation. The MISSING-GATE row at `:1641` is exactly the kind of "non-VRF SLOAD inside the rng-window" bug class flagged by `feedback_rng_window_storage_read_freshness.md`.

### §7.C — Recommended tactic + rationale + impact estimate

**Tactic: (a) rngLockedFlag-gated revert.** Per catalog §16 row V-012 rationale: *"MISSING `if (rngLockedFlag) revert` at DegenerusGame:1641 — add."*

**Rationale.** The exact one-line addition at DegenerusGame.sol:1641 is:

```solidity
function deactivateAfKingFromCoin(address player) external {
    if (
        msg.sender != ContractAddresses.COIN &&
        msg.sender != ContractAddresses.COINFLIP
    ) revert E();
    if (rngLockedFlag) revert RngLocked();   // <-- ADD (mirrors :1513 / :1528 / :1575)
    _deactivateAfKing(player);
}
```

The gate placement is at the public-entry function body, BEFORE the call into the private writer, mirroring the pattern at `_setAutoRebuy:1513`, `_setAutoRebuyTakeProfit:1528`, and `_setAfKingMode:1575`. Phase 299 documents the placement convention; v44.0 sub-phase implements the diff and adds a coverage test.

**Cross-contract synchronization note.** Per §7.A's "naive gate breaks behavior" analysis: adding the gate causes the COIN-side lazy-pass-loss callback to revert during the lock window, leaving COIN's view of the player's lazy-pass-status out of sync with the game's. v44.0 sub-phase must verify that (i) COIN tolerates the revert (does not bubble it into a state-corrupting failure), and (ii) lazy-pass-loss events that fire during the lock window are reconciled on the next non-locked invocation (e.g. via a deferred-sync queue OR via the next legitimate lazy-pass-loss event that re-fires once the lock clears).

**Tactic alternative.** A more sophisticated remediation would queue the deactivation in a pending-deactivation buffer during the lock window and apply at `_unlockRng` time. This is closer to tactic (c) pre-lock reorder and would have ~+100 byte impact + 1 new storage slot. v44.0 sub-phase selects between the simple (a) gate (catalog-recommended) and the more invasive (c) queue at planning.

**Storage-layout impact.** Zero for catalog (a). +1 slot for tactic (c) queue alternative.

**Public ABI impact.** Zero. The `deactivateAfKingFromCoin(address)` selector is preserved; the `RngLocked` revert path is added as a new revert reason for COIN/COINFLIP callers — non-breaking because `RngLocked` is an inherited error from `DegenerusGameStorage.sol:213` that the COIN contract is already aware of (per its existing interactions with other gated entries).

**Bytecode impact estimate.** ~30 bytes (`SLOAD rngLockedFlag` + `JUMPI` + `revert(0,0)` with selector push). Well under module budget.

### §7.D — v44.0 handoff anchor

**Anchor:** D-43N-V44-HANDOFF-07 — Add `if (rngLockedFlag) revert RngLocked();` gate at `deactivateAfKingFromCoin(address)` entry body at DegenerusGame.sol:1641 (between the COIN/COINFLIP `msg.sender` check at `:1642–:1645` and the `_deactivateAfKing(player)` call at `:1646`); verify COIN-side reconciliation of lazy-pass-loss events that fire during the lock window. **Catalog row:** RNGLOCK-CATALOG.md:347 (V-012). **Writer:** `contracts/DegenerusGame.sol:1670` (private `_deactivateAfKing`) reached from external callback entry at `:1641`.

---

## §8 — V-013 (`autoRebuyState[beneficiary]` via `syncAfKingLazyPassFromCoin` at DegenerusGame.sol:1654)

### §8.A — Design-intent backward-trace

**MISSING-GATE writer.** `syncAfKingLazyPassFromCoin(address player) external returns (bool active)` at DegenerusGame.sol:1654 is the BurnieCoinflip-restricted callback entry (`msg.sender != ContractAddresses.COINFLIP` revert at `:1657`). The function reads `autoRebuyState[player]` at `:1658`; returns early if `!state.afKingMode` at `:1659`; returns early if `_hasAnyLazyPass(player)` at `:1660`; otherwise SSTOREs `state.afKingMode = false` at `:1664`, `state.afKingActivatedLevel = 0` at `:1665`, and emits `AfKingModeToggled(player, false)` at `:1666`.

**Critical gap: NO `rngLockedFlag` gate AND NO AFKING_LOCK_LEVELS check.** Unlike V-012 (`_deactivateAfKing` which enforces AFKING_LOCK_LEVELS at `:1675–1676`), the V-013 writer body at `:1654` bypasses the lock-level cooldown — it only checks lazy-pass status, not the activation-level cooldown. AND it lacks the `rngLockedFlag` gate entirely. This is a strictly worse-protected writer than V-012.

**Why the writer exists.** BurnieCoinflip-initiated coinflip operations (deposit, claim, arming) call back into the game via this entry to verify the player still holds the lazy-pass required for afKing mode. If the coinflip operation's side-effect on the player's BurnieCoin balance caused lazy-pass-loss, the writer auto-deactivates afKing without enforcing AFKING_LOCK_LEVELS (the design intent being: "the lazy-pass requirement was always primary; if it's gone, afKing must be revoked immediately even mid-lock-period to preserve the lazy-pass-gating invariant").

**Why a naive gate would break behavior.** Same as §7.A — adding `if (rngLockedFlag) revert RngLocked()` at `:1654` blocks the coinflip sync during the lock window. The COINFLIP-side semantic is: "I'm telling the game the player's lazy-pass status changed". Dropping the sync during the lock means the game's view of lazy-pass-status diverges from COINFLIP's until the next non-locked sync.

### §8.B — Actor game-theory walk

**Actor class:** Lazy-pass-holding player with co-incident jackpot stake AND co-incident BurnieCoinflip activity.

**Action sequence during rngLock window (CURRENT UNGATED state):**

1. Player has afKing mode ACTIVE and qualifies as a winner cohort.
2. Player observes pending VRF and models afKing-active vs afKing-inactive EV under the predicted finalist-redirect rule.
3. Player initiates a BurnieCoinflip operation (deposit / claim / arming) that causes a lazy-pass-loss event (e.g., a BurnieCoin balance reduction within COINFLIP's accounting hook).
4. COINFLIP invokes `DegenerusGame.syncAfKingLazyPassFromCoin(player)`.
5. The callback executes WITHOUT a `rngLockedFlag` gate at `:1654`; the `_hasAnyLazyPass(player)` check at `:1660` returns `false` (player just lost it); SSTOREs `state.afKingMode = false` at `:1664`.
6. VRF callback consumes the mutated `autoRebuyState[player].afKingMode`; finalist-redirect rule selects the non-afKing path.

**Worse than §7.B.** This writer LACKS the AFKING_LOCK_LEVELS check that V-012's `_deactivateAfKing` body imposes. A player who activated afKing mode less than AFKING_LOCK_LEVELS levels ago CAN reach mid-lock deactivation via this entry (cannot via V-012's entry). The MISSING-GATE row at `:1654` is the strictly-most-exploitable autoRebuyState writer in Cluster A.

**EV magnitude.** HIGH-tier (CATASTROPHE-tier under specific actor profiles — lazy-pass-just-lost players with recent activation can extract afKing-toggle EV ANYWHERE in their afKing lifecycle via this path). Equivalent or larger than §7.B.

**Economic likelihood: HIGH.** BurnieCoinflip operations are routine for lazy-pass holders (the same cohort uses coinflip for daily play). Triggering a lazy-pass-loss-causing BurnieCoinflip op is a normal-economic-incentive action, not a griefing-only path.

### §8.C — Recommended tactic + rationale + impact estimate

**Tactic: (a) rngLockedFlag-gated revert.** Per catalog §16 row V-013 rationale: *"MISSING gate at DegenerusGame:1654 — add."*

**Rationale.** The exact one-line addition at DegenerusGame.sol:1654 is:

```solidity
function syncAfKingLazyPassFromCoin(
    address player
) external returns (bool active) {
    if (msg.sender != ContractAddresses.COINFLIP) revert E();
    if (rngLockedFlag) revert RngLocked();   // <-- ADD (mirrors :1513 / :1528 / :1575)
    AutoRebuyState storage state = autoRebuyState[player];
    // ... (rest of body unchanged)
}
```

The gate placement is between the `msg.sender` check and the `autoRebuyState[player]` SLOAD, mirroring §7.C's placement convention. Per `feedback_rng_window_storage_read_freshness.md`, this is the "non-VRF storage read inside the rng-window" pattern: the SLOAD of `state.afKingMode` at `:1659` is consumed alongside RNG by the downstream jackpot consumer, so its write must be locked during the window.

**Cross-contract synchronization note.** Same as §7.C — the COINFLIP-side sync semantic is dropped during the lock window when the gate fires. v44.0 sub-phase verifies COINFLIP tolerates the revert and reconciles on the next non-locked sync. The COINFLIP-side is already aware of `RngLocked` per its own gated entries (`BurnieCoinflip:730`).

**Why this gate is STRICTLY required despite the (b) snapshot alternative.** Catalog (b) snapshot would require freezing the consumer's `autoRebuyState[winner].afKingMode` SLOAD at lock time. The afKing-mode SLOAD currently happens inside the jackpot's per-winner-iteration loop in `JackpotModule.payDailyJackpot`; a snapshot at lock time would require pre-computing the winner set, which is impossible because the winner set depends on VRF. Snapshot is therefore infeasible for `autoRebuyState[*].afKingMode`; gated-revert is the only structurally-feasible tactic. Catalog (a) is the correct selection.

**Storage-layout impact.** Zero.

**Public ABI impact.** Zero. `syncAfKingLazyPassFromCoin(address)` selector preserved; the `RngLocked` revert path is added — non-breaking per §7.C.

**Bytecode impact estimate.** ~30 bytes (same as §7.C).

**FUZZ test scope.** Phase 301 FUZZ harness should assert: ∀ player p with `state.afKingMode == true`, when `rngLockedFlag == true`, `DegenerusGame.syncAfKingLazyPassFromCoin(p)` reverts with `RngLocked()` selector. The harness MUST reach the function via a simulated COINFLIP `msg.sender` (mock COINFLIP or coverage-mode caller-spoofing).

### §8.D — v44.0 handoff anchor

**Anchor:** D-43N-V44-HANDOFF-08 — Add `if (rngLockedFlag) revert RngLocked();` gate at `syncAfKingLazyPassFromCoin(address)` entry body at DegenerusGame.sol:1654 (between the COINFLIP `msg.sender` check at `:1657` and the `autoRebuyState[player]` SLOAD at `:1658`); verify BurnieCoinflip-side reconciliation of lazy-pass-loss sync events that fire during the lock window. **Catalog row:** RNGLOCK-CATALOG.md:348 (V-013). **Writer:** `contracts/DegenerusGame.sol:1654` (`syncAfKingLazyPassFromCoin` external entry; writer body at `:1664–:1666`).

---

## Cluster-A summary roll-up

**VIOLATION count:** 8 (V-003, V-004, V-005, V-009, V-010, V-011, V-012, V-013).

**Tactic mix:** 3 × (b) snapshot/anchor (V-003, V-004, V-005); 5 × (a) rngLockedFlag-gated revert (V-009, V-010, V-011, V-012, V-013).

**EV-tier distribution:**

| EV tier | Count | V-NNN |
|---------|-------|-------|
| HIGH (CATASTROPHE-adjacent) | 5 | V-009, V-010, V-011, V-012, V-013 |
| HIGH | 1 | V-005 (vault-amplified) |
| MEDIUM | 2 | V-003, V-004 |

**Gate-status distribution (V-009 family):**

- V-009: gate PRESENT at DegenerusGame.sol:1513 → FUZZ coverage attestation
- V-010: gate PRESENT at DegenerusGame.sol:1528 → FUZZ coverage attestation
- V-011: gate PRESENT at DegenerusGame.sol:1575 → FUZZ coverage attestation
- V-012: gate MISSING at DegenerusGame.sol:1641 → ADD per H-07
- V-013: gate MISSING at DegenerusGame.sol:1654 → ADD per H-08

**Handoff-anchor range:** D-43N-V44-HANDOFF-01 through D-43N-V44-HANDOFF-08.

**Catalog-row cross-references:** §16 rows V-003 (line 338) through V-013 (line 348).

**v44.0 FIX-MILESTONE consumer notes.**

- v44.0 dailyHeroWagers sub-phase (H-01 + H-02 + H-03) is ONE source-code diff at either the writer site DegeneretteModule.sol:499 OR the consumer site JackpotModule.sol:1653 — the three handoff anchors are catalog-completeness rows for the same underlying fix.
- v44.0 autoRebuyState sub-phase (H-04 + H-05 + H-06) is ZERO source-code diff — pure FUZZ-301 coverage attestation; this should be planned as a Phase 301 FUZZ deliverable, not a Phase v44 contract change.
- v44.0 autoRebuyState sub-phase (H-07 + H-08) is TWO source-code diffs — one per missing gate — at DegenerusGame.sol:1641 and DegenerusGame.sol:1654. Both diffs are ~1 line plus accompanying cross-contract reconciliation verification (COIN/COINFLIP-side tolerates the new revert path).

Per `D-43N-AUDIT-ONLY-01`, no `contracts/` or `test/` changes are made by Phase 299. v44.0 FIX-MILESTONE is the source-tree-mutation venue.
