# Phase 299 Plan 03 — FIXREC Cluster C (prizePoolsPacked S-09 EOA writers)

**Generated:** 2026-05-18
**Cluster scope:** Slot S-09 `prizePoolsPacked` (uint256 packed; next-pool + future-pool fields) EOA-reachable writer rows from `RNGLOCK-CATALOG.md` §16.
**VIOLATIONs covered:** V-024, V-025, V-026, V-027, V-030, V-031, V-032 (7 logical rows).
**Handoff anchors emitted:** D-43N-V44-HANDOFF-13 … D-43N-V44-HANDOFF-19.
**Posture:** AUDIT-ONLY per `D-43N-AUDIT-ONLY-01`. Zero `contracts/` and zero `test/` mutations. Per-VIOLATION 4-sub-section depth per `D-299-FIXREC-LAYOUT-01`.

**Cluster theme.** `prizePoolsPacked` packs two uint128 accounting fields (`nextPrizePool`, `futurePrizePool`) into one storage slot. Two daily-jackpot consumers read the slot inside the rngLock window: §1 `JackpotModule.payDailyJackpot` (P1 reads `_getPrizePools()` at JackpotModule `:431, :511, :548, :570, :725, :840, :842, :1201`; drives `reserveSlice = futurePoolBal / 200` carryover at `:432`, `ethDaySlice = (_getFuturePrizePool() * poolBps) / 10_000` 1% drip at `:548`, and the BAF purchase-phase payout budget at `:570`) and §8 `DegeneretteModule._resolveLootboxDirect` (auto-resolve branch which reads the same packed slot in the resolution stack). Each of the 7 EOA writers below mutates the slot during the rngLock window without a top-level `rngLockedFlag` revert, so the value the consumer reads can be inflated/deflated by anything an attacker fires between `_requestRng` and `_unlockRng`. The structural intent — frozen pool inputs across the freeze — is documented in `D-42N-FREEZE-INVARIANT-01` (Phase 290 MINTCLN owed-in-baseKey collapse) and is the same envelope Phase 281 owed-salt + Phase 288 dailyIdx snapshot patterns enforce on neighbouring slots.

**Catalog cross-reference.** Each §N below cites the `RNGLOCK-CATALOG.md` §16 row tactic + rationale verbatim and extends it to the `D-299-FIXREC-LAYOUT-01` 4-sub-section depth.

---

## §1 — V-024: MintModule payment processing → prizePoolsPacked

**Slot:** S-09 `prizePoolsPacked` (next + future)
**Writer:** `_processMintPayment` / `_handleMintRevenue` callsites reached from `purchase`, `purchaseCoin`, `purchaseBurnieLootbox` (file:line `MintModule.sol:376` `_setPrizePools`, `:1062` `_setPrizePools` inside lootbox revenue split)
**EOA reach:** `MintModule.sol:830` (`purchase`), `:852` (`purchaseCoin`), `:864` (`purchaseBurnieLootbox`)
**Catalog row:** §16 V-024 — `VIOLATION | (a) | Add top-level rngLockedFlag revert to MintModule.purchase/purchaseCoin/purchaseBurnieLootbox | D-43N-V44-HANDOFF-13`

### §1.A — Design-intent backward-trace

The three MintModule purchase entries (`purchase`, `purchaseCoin`, `purchaseBurnieLootbox`) are the primary ETH + BURNIE on-ramp for tickets and loot boxes. Their write into `prizePoolsPacked` exists because every paid ticket or paid loot box routes a portion of revenue into the `next`/`future` pool accumulators that fund future daily jackpots; `_setPrizePools(...)` is invoked at `MintModule.sol:376` (ticket purchase split) and `:1062` (loot-box-buy revenue split). The accumulator-write is the structural intent — players paying into the game must increase the pool that will eventually pay out. The conservative reading of the freeze invariant (`D-42N-FREEZE-INVARIANT-01`, Phase 290 MINTCLN) requires those mutations to either (i) be barred during the freeze, or (ii) land in a parallel "pending" slot via `_setPendingPools` and merge after `_unfreezePool`. The pending-pool branch already exists at MintModule `:368-:380` and `:1054-:1066`: `if (prizePoolFrozen) _setPendingPools(...)` else `_setPrizePools(...)`. The bug is that `prizePoolFrozen` and `rngLockedFlag` cover DIFFERENT windows: `prizePoolFrozen` toggles at `_swapAndFreeze` / `_unfreezePool` inside the jackpot-phase transition; `rngLockedFlag` covers the broader VRF in-flight window which includes non-jackpot-day rngLocked sub-windows. The existing partial gate at `MintModule.sol:1221` (`if (cachedJpFlag && rngLockedFlag) { ... targetLevel = cachedLevel + 1; }`) only redirects target-level on the LAST jackpot day to prevent stranded tickets — it does not block the prize-pool write itself, and it is conditioned on `cachedJpFlag`, so it does nothing on a non-jackpot-phase rngLocked window. Per `feedback_design_intent_before_deletion.md`, the original design clearly meant the freeze + pending-pool branch to be the canonical protection — the freeze flag just isn't co-extensive with the full rngLock window, so the protection silently leaks. Per `feedback_no_history_in_comments.md` the fix is described as what IS required, not what was missing.

### §1.B — Actor game-theory walk

**Exploit-actor class:** any EOA player. **Action sequence:** after `_requestRng` fires (rngLockedFlag = true) but before `_unlockRng` clears it (i.e. inside the daily-jackpot resolution window where §1 `payDailyJackpot` is about to read `_getPrizePools()` at `:431` / `:511` / `:548` / `:570`), the attacker fires `MintModule.purchase(..., ticketQuantity=X, lootBoxAmount=Y, ...)` with msg.value covering both shares. The call lands in `_purchaseFor` (no top-level rngLockedFlag gate — only `_livenessTriggered()` at `:906`) and walks through `_processMintPayment`/`_handleMintRevenue` reaching `_setPrizePools(next + nextShare, future + futureShare)` at `:376`. The consumer's `reserveSlice` (`futurePoolBal / 200`), `ethDaySlice` (`futurePoolBal * poolBps / 10_000` at JackpotModule `:548`), and BAF purchase-phase payout budget (read at `:570`) all increase. Per `feedback_rng_commitment_window.md` the commitment-window invariant is that nothing player-controllable can change between the rng request and the consumer's read; this violation is a direct breach. **EV magnitude:** LOW per single mint transaction (attacker pays in ETH at a fixed price and receives tickets / boxes whose EV is bounded by the standard expected return); however, **aggregate EV across all parallel mint paths during a high-stakes jackpot window can be MEDIUM-tier**: an attacker who is already a winner under one entropy outcome can inflate `futurePool` to magnify their own win when the consumer reads it. The economic likelihood is BOUNDED because every dollar of inflation comes from the attacker's own wallet — the steal target is the SHARE of the inflated pool that ends up routed to the attacker via the bucket allocation, not the inflation itself. **Disposition:** MEDIUM-tier with caveat — exploitability is gated by whether the attacker has won the relevant solo / large bucket, which is itself VRF-determined.

### §1.C — Recommended tactic + rationale + impact

**Tactic:** (a) rngLockedFlag-gated revert. Reproducing catalog row V-024 verbatim: "Add top-level `if (rngLockedFlag) revert RngLocked();` to `MintModule.purchase` / `purchaseCoin` / `purchaseBurnieLootbox`". Three callsites: `MintModule.sol:830`, `:852`, `:864`. Each gate is the canonical 2-line `if (rngLockedFlag) revert RngLocked();` invoking the existing `RngLocked` custom error already imported in MintModule (precedent: `MintModule.sol:1221` references it inside the cachedJpFlag branch; `BurnieCoinflip.sol:730`, `StakedDegenerusStonk.sol:492`). **Rationale:** the existing `prizePoolFrozen` branch covers the jackpot-phase swap window but does not cover non-jackpot-phase rngLock; the freeze invariant per `D-42N-FREEZE-INVARIANT-01` and the commitment-window discipline per `feedback_rng_commitment_window.md` together require the broader gate. The tactic (b) snapshot alternative — record `prizePoolsPacked` value at lock time and serve consumers from the snapshot — is rejected here for cost: `prizePoolsPacked` is performance-critical (packed for single-SLOAD efficiency in the daily resolution stack), and snapshotting it would require a parallel packed slot whose layout drift must be audited at every `_setPrizePools`/`_setPendingPools` callsite. The simpler (a) revert is byte-cheap and preserves the existing storage layout. **Bytecode impact:** ~30 bytes per gate site (single SLOAD + JUMPI + REVERT-4-bytes), ≈90 bytes total across the 3 entry points. **Storage layout:** BYTE-IDENTICAL — no new slot. **Public ABI:** NON-BREAKING — purchase signatures unchanged; new revert path returns the documented `RngLocked()` error per the convention.

### §1.D — v44.0 handoff anchor

**Anchor:** `D-43N-V44-HANDOFF-13`
**Citation:** `MintModule.sol:830` (`purchase`), `:852` (`purchaseCoin`), `:864` (`purchaseBurnieLootbox`)
**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row V-024 (slot=S-09, writer=MintModule payment processing, callsite=MintModule.sol purchase family).

---

## §2 — V-025: WhaleModule purchase entries → prizePoolsPacked

**Slot:** S-09 `prizePoolsPacked`
**Writer:** `_setPrizePools` reached from `purchaseWhaleBundle` (`WhaleModule.sol:353`) + `purchaseLazyPass` (`WhaleModule.sol:499`)
**EOA reach:** `WhaleModule.sol:187` (`purchaseWhaleBundle`), `:380` (`purchaseLazyPass`)
**Catalog row:** §16 V-025 — `VIOLATION | (a) | Add top-level rngLockedFlag revert at WhaleModule:187 + :380 | D-43N-V44-HANDOFF-14`

### §2.A — Design-intent backward-trace

`purchaseWhaleBundle` and `purchaseLazyPass` are the two whale-tier ETH purchase entries that fund pass-based rewards. The whale-bundle entry routes 5%/95% of `totalPrice` to `nextPool`/`futurePool` post-game (or 100% future during presale) via `_setPrizePools(next + nextShare, future + (totalPrice - nextShare))` at `WhaleModule.sol:353`; the lazy-pass entry routes the discounted pass price into the pool via the same `_setPrizePools` writer at `:499`. Both calls predate the rngLock discipline introduced when the daily-jackpot VRF-resolution surface was carved out, and their accumulator-write is the structural intent: whale bundles pay into the pool that whales' own claims will later draw from. As with V-024, the `prizePoolFrozen` branch at `WhaleModule.sol:345-:357` handles the jackpot-phase swap window via `_setPendingPools`, but does not cover the broader rngLock window. Phase 290 MINTCLN's owed-in-baseKey collapse design rationale (`290-01-DESIGN-INTENT-TRACE.md`) is the controlling precedent: per-callsite gates at EOA entry points are the only complete protection for accumulator slots that participate in VRF-resolution reads. Per `feedback_design_intent_before_deletion.md`, the original frozen-pending pattern remains valid; the gate at the EOA entry is the supplement that closes the rngLock-window gap.

### §2.B — Actor game-theory walk

**Exploit-actor class:** any EOA player with enough ETH to purchase a whale bundle (current price floor ≈ `WHALE_BUNDLE_BASE` + level-dependent escalation) or a lazy pass. **Action sequence:** inside the rngLock window, attacker fires `purchaseWhaleBundle(buyer, quantity)` with msg.value covering `totalPrice = baseUnit × quantity`. Maximum single-call mutation: `quantity ∈ [1..100]` × per-bundle price → up to 100× per-bundle inflation of `futurePool`. The consumer at §1 reads `_getFuturePrizePool()` at JackpotModule `:548` and multiplies by `poolBps`; the inflated value propagates directly to `ethDaySlice`. **EV magnitude:** MEDIUM. Whale-bundle is the LARGEST single-call writer in the catalog for S-09 — one call can shift `futurePool` by tens of ETH. Per `feedback_rng_commitment_window.md` the attack window is the rngLock duration (seconds-to-minutes for VRF callback latency). **Disposition:** MEDIUM-tier; gated by attacker's win probability under the in-flight VRF outcome, but the leverage per call is much higher than V-024.

### §2.C — Recommended tactic + rationale + impact

**Tactic:** (a) rngLockedFlag-gated revert at `WhaleModule.sol:187` (`purchaseWhaleBundle`) and `:380` (`purchaseLazyPass`). Two callsites. The `_livenessTriggered()` revert at `:195` and `:385` is the existing top-level check; the gate is co-located right alongside that check: `if (rngLockedFlag) revert RngLocked();`. `RngLocked` is the canonical custom error already used by sibling `WhaleModule._purchaseDeityPass` at `:543`. **Rationale:** identical to §1.C — the existing `prizePoolFrozen`/`_setPendingPools` branch covers only the jackpot-phase swap window; the broader rngLock window requires the entry-level revert. Tactic (b) snapshot is rejected for the same byte-cost + layout-drift reason (the slot is performance-critical and packed). **Bytecode impact:** ~30 bytes × 2 sites = ~60 bytes. **Storage layout:** BYTE-IDENTICAL. **Public ABI:** NON-BREAKING.

### §2.D — v44.0 handoff anchor

**Anchor:** `D-43N-V44-HANDOFF-14`
**Citation:** `WhaleModule.sol:187` (`purchaseWhaleBundle`), `:380` (`purchaseLazyPass`)
**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row V-025.

---

## §3 — V-026: WhaleModule.purchaseDeityPass → prizePoolsPacked (runtime-gated)

**Slot:** S-09 `prizePoolsPacked`
**Writer:** `_setPrizePools` reached from `_purchaseDeityPass` at `WhaleModule.sol:653` (revenue split)
**EOA reach:** `WhaleModule.sol:538` (`purchaseDeityPass` external) → `:542` (`_purchaseDeityPass` private)
**Catalog row:** §16 V-026 — `VIOLATION | (a) | Gate already at WhaleModule:543 — coverage verification only | D-43N-V44-HANDOFF-15`

### §3.A — Design-intent backward-trace

`purchaseDeityPass` is the deity-pass purchase entry (one of 32 per-symbol passes); the price escalates with the count of already-sold passes and a per-buyer boon-discount may apply. The pass-price revenue routes into `prizePoolsPacked` via `_setPrizePools(next + nextShare, future + (totalPrice - nextShare))` at `WhaleModule.sol:653`. UNLIKE V-024 and V-025, this entry HAS a top-level `rngLockedFlag` revert: `WhaleModule.sol:543` reads `if (rngLockedFlag) revert RngLocked();` as the FIRST statement of `_purchaseDeityPass`. The runtime gate is design-intent-aligned with the freeze invariant (`D-42N-FREEZE-INVARIANT-01`) and the original deity-pass introduction phase. Catalog §16 still classifies V-026 as VIOLATION per `D-298-EXEMPT-REACH-01` (strict + per-callsite + stack-strict): the verdict matrix records the WRITER row regardless of any runtime mitigation, since runtime gates must be coverage-verified rather than assumed. The classification difference between V-019 (S-07 `deityBySymbol`) and V-026 (S-09 `prizePoolsPacked`) is that both gates derive from the same `:543` revert — they are co-located and either both fire or both don't.

### §3.B — Actor game-theory walk

**Exploit-actor class:** any EOA buyer attempting a deity-pass purchase during rngLock. **Action sequence:** the actor fires `purchaseDeityPass(buyer, symbolId)`. The first statement at `:543` reads `if (rngLockedFlag) revert RngLocked();` and reverts. The deity-pass price write to `prizePoolsPacked` at `:653` is therefore UNREACHABLE during rngLock IF the runtime gate fires reliably. Per `feedback_rng_window_storage_read_freshness.md`, every SLOAD inside the rng-window must be enumerated; the gate's correctness depends on `rngLockedFlag`'s value at the time of the SLOAD. Since `rngLockedFlag` itself only transitions inside `_requestRng` (true) / `_unlockRng` (false), both inside the advanceGame stack, no concurrent EOA writer can flip the gate between SLOAD and SSTORE within `_purchaseDeityPass`. **EV magnitude:** LOW — the gate effectively closes the window. The only residual risk is a coverage gap if `rngLockedFlag` is not set when the consumer reads `_getPrizePools()` at §1 (e.g. `_requestRng` runs after `_purchaseDeityPass` in the same block — impossible per the advanceGame stack ordering). **Disposition:** LOW-tier, structurally bounded. The verdict-matrix entry exists to FORCE the FUZZ-301 branch-coverage check.

### §3.C — Recommended tactic + rationale + impact

**Tactic:** (a) rngLockedFlag-gated revert — ALREADY PRESENT at `WhaleModule.sol:543`. **No source-tree change required.** Catalog row V-026 explicitly says "coverage verification only". Per `D-43N-FUZZ-VMSKIP-01` and Phase 301 FUZZ scope, V-026 hands off to FUZZ-301 as a branch-coverage attestation target: the FUZZ test asserts that `purchaseDeityPass` reverts with `RngLocked()` when called inside the rngLock window, exercising the `:543` revert path. **Rationale:** the gate is already correctly placed; any code change risks regressing the existing protection. Per `feedback_frozen_contracts_no_future_proofing.md` the contract is frozen at deploy; the FIXREC remediation is the FUZZ-301 attestation, not a source mutation. **Bytecode impact:** ZERO. **Storage layout:** UNCHANGED. **Public ABI:** UNCHANGED.

### §3.D — v44.0 handoff anchor

**Anchor:** `D-43N-V44-HANDOFF-15`
**Citation:** `WhaleModule.sol:538` (entry) → `:543` (gate) → `:653` (`_setPrizePools` revenue split)
**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row V-026; cross-links to V-019 (same gate, S-07 slot).

---

## §4 — V-027: recordDecBurn → prizePoolsPacked (BurnieCoin callback)

**Slot:** S-09 `prizePoolsPacked`
**Writer:** `recordDecBurn`'s downstream prize-pool routing reached via the BurnieCoin `decimatorBurn` callback path; the prize-pool credit lands on the GAME-side ETH-receive write at `DegenerusGame.sol:1747` (`_setPrizePools(next, future + uint128(amount))`) when decimator BURNIE-burn unlocks the corresponding ETH share, and the `recordDecBurn` entry point itself is at `DegenerusGame.sol:1029`.
**EOA reach:** `BurnieCoin.sol:559` (`decimatorBurn`) → `:610` (calls `degenerusGame.recordDecBurn(...)` → `DegenerusGame.sol:1029` → `DegenerusGameDecimatorModule.sol:133`)
**Catalog row:** §16 V-027 — `VIOLATION | (a) | Add rngLockedFlag gate at DegenerusGame:1029 OR upstream in DegenerusCoin.burnCoin | D-43N-V44-HANDOFF-16`

### §4.A — Design-intent backward-trace

`recordDecBurn` is the GAME-side callback that BurnieCoin invokes during `decimatorBurn` to record the burn into the per-level / per-bucket aggregate. The decimator subsystem rewards BURNIE burns with lottery-style payouts on level transitions; the burn itself is denominated in BURNIE but the corresponding ETH prize-pool routing happens on the GAME side as part of the burn-fund-credit pipeline. The catalog §15 enumeration places `recordDecBurn` under the S-09 writers because the decimator-resolution flow (`DegenerusGameJackpotModule._awardDecimatorLootbox` at JackpotModule `:573`) ultimately consults `prizePoolsPacked` reads through the dec-burn aggregate's ETH-share routing. The structural intent: BURNIE burns fund decimator lottery payouts; the dec-burn aggregate must be frozen across the rngLock window to keep payout consumers consistent. The current `recordDecBurn` body (`DegenerusGameDecimatorModule.sol:133-:192`) gates ONLY on `msg.sender != ContractAddresses.COIN` (`OnlyCoin` revert at `:140`); there is no rngLockedFlag check. The original decimator-design phase predates rngLock discipline. Per `feedback_design_intent_before_deletion.md`, the dec-burn aggregate's freeze across rngLock IS the design intent — it just was never wired through `recordDecBurn`'s entry.

### §4.B — Actor game-theory walk

**Exploit-actor class:** any EOA holding BURNIE tokens. **Action sequence:** inside the rngLock window, attacker fires `BurnieCoin.decimatorBurn(player, amount)` with `amount >= MIN_DECIMATOR_BURN`. The call burns BURNIE and reaches `degenerusGame.recordDecBurn(...)` at BurnieCoin `:610`. `recordDecBurn` mutates `decBurn[lvl][player]` and subbucket aggregates (`_decUpdateSubbucket`). The mutated aggregate is then read by the §1 jackpot consumer's dec-related branches when the jackpot resolution computes decimator-lottery EV inputs. **EV magnitude:** MEDIUM-HIGH. Per `feedback_rng_commitment_window.md` and `feedback_rng_window_storage_read_freshness.md` (F-41-02/03 precedent), decimator burns are FEE-CHEAP relative to their EV impact: the attacker spends BURNIE (which itself is purchased / earned) and shifts a multi-ETH payout's distribution. Burning small amounts repeatedly mid-window can accumulate subbucket entries that displace the deterministic subbucket order. **Disposition:** MEDIUM-HIGH; the per-burn cost is low, the per-window ROI scales with the player's bucket position.

### §4.C — Recommended tactic + rationale + impact

**Tactic:** (a) rngLockedFlag-gated revert. Per catalog row V-027: "Add `rngLockedFlag` gate at `DegenerusGame:1029` OR upstream in `DegenerusCoin.burnCoin`". Two candidate sites: `DegenerusGame.sol:1029` (the GAME-side proxy entry that delegatecalls to the Decimator module) or `BurnieCoin.sol:559` (`decimatorBurn`, the EOA entry point). The cleaner site is `DegenerusGame.sol:1029` since the rngLock state lives in GAME storage and the GAME-side entry is the architectural boundary; adding the gate to BurnieCoin would require BurnieCoin to read GAME state through a cross-contract call (which adds gas to every dec-burn and creates a cross-contract coupling). **Rationale:** the GAME-side gate is internally consistent with the rest of the FIXREC cluster (V-024/V-025/V-027 all gate at the GAME-side EOA entry). Per `feedback_design_intent_before_deletion.md`, the freeze invariant lives in GAME; BurnieCoin is the messenger. Tactic (b) snapshot is rejected: snapshotting the dec-burn aggregate would require freezing a much larger state surface (`decBurn[lvl][player]` is a mapping; snapshot scaling is impractical). **Bytecode impact:** ~30 bytes for the single gate at `DegenerusGame.sol:1029`. **Storage layout:** BYTE-IDENTICAL. **Public ABI:** NON-BREAKING — `recordDecBurn` keeps its signature, only gains a guarded revert path; BurnieCoin callers see `RngLocked()` revert propagating up through `decimatorBurn`'s call to `recordDecBurn`.

### §4.D — v44.0 handoff anchor

**Anchor:** `D-43N-V44-HANDOFF-16`
**Citation:** `DegenerusGame.sol:1029` (`recordDecBurn` GAME-side entry) and cross-link `BurnieCoin.sol:559` (`decimatorBurn` EOA entry)
**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row V-027.

---

## §5 — V-030: claimWhalePass → _queueTicketRange adjacent writes

**Slot:** S-09 `prizePoolsPacked` (adjacent writes alongside `_queueTicketRange`-mediated routing)
**Writer:** `_queueTicketRange`-co-located prize-pool writes reached via `claimWhalePass` (`DegenerusGame.sol:1692` parent dispatch → `WhaleModule.sol:957` body → `:973` `_queueTicketRange`)
**EOA reach:** `DegenerusGame.sol:1692` (`claimWhalePass`)
**Catalog row:** §16 V-030 — `VIOLATION | (a) | Effective gate via _queueTicketRange revert; add explicit top-level gate for clarity | D-43N-V44-HANDOFF-17`

### §5.A — Design-intent backward-trace

`claimWhalePass` is the deferred-claim entry for whale-pass ticket awards. Whale-pass winners accumulate `whalePassClaims[player]` half-pass counts during normal solo-bucket resolution (`JackpotModule.sol:1570` `whalePassClaims[winner] += whalePassCount`); the EOA-callable `claimWhalePass` later converts the half-pass count into actual ticket entries via `_queueTicketRange(player, startLevel, 100, halfPasses, false)` at `WhaleModule.sol:973`. The `_queueTicketRange` writer is the same family as `_queueTickets`, both of which carry rngLockedFlag gates inside the body (`DegenerusGameStorage.sol:572` reads `if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked();`). Per the catalog rationale, the "effective gate" exists DOWNSTREAM via that body revert when `_queueTicketRange` writes a far-future ticket key during rngLock. The design intent (from the original whale-pass introduction) is that ticket awards must respect the queue's far-future / write-slot discipline. The structural protection IS the downstream revert; the missing piece is the entry-level revert at the EOA boundary, which improves diagnostic clarity (callers see the revert at `claimWhalePass`, not deep in `_queueTicketRange`) and protects against future refactors that might rewire `_queueTicketRange`'s internal gate.

### §5.B — Actor game-theory walk

**Exploit-actor class:** any EOA with a non-zero `whalePassClaims` balance (i.e. a prior whale-pass solo-bucket winner). **Action sequence:** inside the rngLock window, attacker fires `claimWhalePass(player)`. `_livenessTriggered()` at `WhaleModule.sol:958` is the only entry-level check. The function proceeds to compute `startLevel = level + 1` and invokes `_queueTicketRange(...)` at `:973`. Inside `_queueTicketRange`, the `_queueTickets`-family gate at `DegenerusGameStorage.sol:572` reverts when the target is far-future and `rngLockedFlag = true && rngBypass = false`. The `claimWhalePass` call passes `false` as the `rngBypass` parameter at `:973`, so the gate fires for far-future writes. **EV magnitude:** LOW per single claim — `claimWhalePass` only converts pre-existing half-pass counts into tickets; it does not let the attacker inflate the underlying count. However, cumulative across many small half-pass batches, an attacker could land queue writes that influence the next-day consumer's `ticketQueue[wk]` read-slot ordering — though the double-buffer protection at `_swapAndFreeze` (toggling `ticketWriteSlot`) makes this concretely difficult. **Disposition:** LOW-tier (structurally protected via the downstream revert).

### §5.C — Recommended tactic + rationale + impact

**Tactic:** (a) rngLockedFlag-gated revert at the EOA entry. Per catalog row V-030: "Effective gate via `_queueTicketRange` revert; add explicit top-level gate for clarity". Two candidate sites: `DegenerusGame.sol:1692` (parent dispatch — adds the gate before delegatecall) and `WhaleModule.sol:957` (module body — adds the gate at the function's top). Recommendation: add at `WhaleModule.sol:957` (alongside `_livenessTriggered()` at `:958`) since that's the canonical body and the parent dispatch is a thin delegatecall shim. `if (rngLockedFlag) revert RngLocked();`. **Rationale:** explicit top-level gate produces deterministic revert behavior diagnosable from the EOA entry-call selector, avoiding the indirection through `_queueTicketRange`'s body. The cluster invariant (every EOA writer of S-09 carries an entry-level gate) becomes uniform across V-024..V-027 + V-030..V-032. Tactic (b) snapshot is N/A — `claimWhalePass` is not an accumulator-write into `prizePoolsPacked` directly; the catalog row classifies it under "adjacent writes" (the prize-pool reads happen during `_queueTicketRange`'s far-future gate evaluation). **Bytecode impact:** ~30 bytes. **Storage layout:** BYTE-IDENTICAL. **Public ABI:** NON-BREAKING.

### §5.D — v44.0 handoff anchor

**Anchor:** `D-43N-V44-HANDOFF-17`
**Citation:** `DegenerusGame.sol:1692` (parent dispatch) → `WhaleModule.sol:957` (body) → `:973` (`_queueTicketRange`)
**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row V-030.

---

## §6 — V-031: placeDegeneretteBet → _collectBetFunds → prizePoolsPacked

**Slot:** S-09 `prizePoolsPacked`
**Writer:** `_setPrizePools` reached from `_collectBetFunds` at `DegeneretteModule.sol:556` (and `_setPendingPools` at `:553` when frozen)
**EOA reach:** `DegenerusGame.sol:714` (`placeDegeneretteBet` parent dispatch) → `DegeneretteModule.sol:367` (module body) → `:405` (`_placeDegeneretteBet`) → `:422` (`_collectBetFunds`) → `:556` (`_setPrizePools(next, future + uint128(totalBet))`)
**Catalog row:** §16 V-031 — `VIOLATION | (a) | Add rngLockedFlag revert to _placeDegeneretteBetCore at DegeneretteModule:405 | D-43N-V44-HANDOFF-18`

### §6.A — Design-intent backward-trace

`placeDegeneretteBet` is the Full-Ticket Degenerette ETH/BURNIE/WWXRP bet entry. The ETH-currency branch in `_collectBetFunds` (`DegeneretteModule.sol:539-:560`) routes the bet's ETH into the `future` prize pool: at `:556` `_setPrizePools(next, future + uint128(totalBet))` when not frozen, or `:553` `_setPendingPools(...)` when frozen. The original Degenerette design (Phase 292 HRROLL / Phase 294 DPNERF era) intended for placed bets to fund pool growth between resolutions; the rngLock-window protection is intended via the frozen-pending branch. The body already reads `if (lootboxRngWordByIndex[index] != 0) revert RngNotReady();` at `:452` — this guards against placing a bet for an INDEX whose RNG has already published, but does NOT block a bet during the daily-jackpot rngLock window. The catalog row V-031 names `_placeDegeneretteBetCore` at `:405` as the gate site (note: the actual body line numbers are `_placeDegeneretteBet :405` and `_placeDegeneretteBetCore :437` — the catalog uses :405 as the wave-1 anchor; either site reaches the same writer chain). Per `feedback_design_intent_before_deletion.md`, the design intent was a frozen-window protection; the rngLock-window subset is uncovered.

### §6.B — Actor game-theory walk

**Exploit-actor class:** any EOA placing a Degenerette bet. **Action sequence:** inside the rngLock window, attacker fires `placeDegeneretteBet(player, currency=ETH, amountPerTicket, ticketCount, customTicket, heroQuadrant)` with msg.value covering `totalBet = amountPerTicket × ticketCount`. The bet body executes the lootbox-index check at `:452` (passes if the current lootbox index doesn't have a published word) and then runs `_collectBetFunds` which writes `prizePoolsPacked.future += totalBet` at `:556`. The consumer at §1 / §8 then reads the inflated `futurePool`. **EV magnitude:** HIGH per `feedback_rng_window_storage_read_freshness.md`'s F-41-02/03 precedent: Degenerette is the CHEAP-BET entry point — minimum bet is `MIN_BET_ETH` (typically ~0.001 ETH or similar), and `ticketCount ∈ [1..10]`, so per-call cost is low while the `futurePool` mutation directly drives the jackpot consumer's `ethDaySlice` budget. The hero-quadrant + customTicket parameters also write `dailyHeroWagers[day][q]` at `:499` (this is V-003 territory under S-02, handled in Cluster A). **Disposition:** HIGH-tier — best per-dollar attack across the cluster.

### §6.C — Recommended tactic + rationale + impact

**Tactic:** (a) rngLockedFlag-gated revert at `_placeDegeneretteBetCore` per catalog row V-031: "Add `rngLockedFlag` revert to `_placeDegeneretteBetCore` at DegeneretteModule:405". The line :405 anchor places the gate at the body of `_placeDegeneretteBet` (the private function called by the external entry `placeDegeneretteBet`), right after `_resolvePlayer` and before any state mutation. Alternatively the gate can live at `_placeDegeneretteBetCore` (`:437`) — both sites are reached from the same external entry. Recommendation: add at `:405` (the private wrapper that ALL bet-paths funnel through, including any future EOA-equivalent entries). `if (rngLockedFlag) revert RngLocked();`. **Rationale:** Degenerette bets ALSO mutate S-02 `dailyHeroWagers` (V-003 in Cluster A, tactic (b) snapshot per Phase 288 dailyIdx precedent). The S-02 violation is best handled by snapshotting the day-key at lock time; the S-09 violation here is best handled by reverting at the entry. Both protections are independent and BOTH should be applied — the gate at :405 closes S-09; the snapshot in Cluster A closes S-02. Tactic (b) snapshot for S-09 alone is rejected for the same packed-slot performance reason as §1.C / §2.C. **Bytecode impact:** ~30 bytes at the single gate site. **Storage layout:** BYTE-IDENTICAL. **Public ABI:** NON-BREAKING.

### §6.D — v44.0 handoff anchor

**Anchor:** `D-43N-V44-HANDOFF-18`
**Citation:** `DegenerusGame.sol:714` (parent dispatch) → `DegeneretteModule.sol:367` (external entry) → `:405` (private wrapper, gate site) → `:422` (`_collectBetFunds`) → `:556` (`_setPrizePools` write)
**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row V-031.

---

## §7 — V-032: openLootBox / openBurnieLootBox → prizePoolsPacked (lootbox payout consolidation)

**Slot:** S-09 `prizePoolsPacked`
**Writer:** lootbox payout consolidation reached via `openLootBox` / `openBurnieLootBox` resolution — the writes land on the GAME-side ETH-receive credit at `DegenerusGame.sol:1747` (`_setPrizePools(next, future + uint128(amount))`) and on lootbox-module internal pool-routing during the open-time resolution.
**EOA reach:** `DegenerusGame.sol:665` (`openLootBox`), `:673` (`openBurnieLootBox`) → delegatecall into LootboxModule
**Catalog row:** §16 V-032 — `VIOLATION | (b) | Domain-separated lootbox VRF; snapshot prizePool at lootbox-buy-time, not open-time | D-43N-V44-HANDOFF-19`

### §7.A — Design-intent backward-trace

`openLootBox` / `openBurnieLootBox` are the manual-resolve lootbox-open entry points. Per the Phase 296 RETRY_LOOTBOX_RNG / SWEEP discipline (`296-CONTEXT.md` + `296-ADVERSARIAL-LOG.md`), the lootbox VRF surface is DOMAIN-SEPARATED from the daily-jackpot VRF: lootbox RNG is per-index (`lootboxRngWordByIndex[index]`), populated via `_finalizeLootboxRng` (daily window) or `rawFulfillRandomWords` (mid-day), and consumed by `openLootBox` resolution. The headline metric in `RNGLOCK-CATALOG.md` §0 #2 ("Manual-path lootbox open is a deep VIOLATION cluster") records 35 VIOLATION rows on the open-resolution surface. The structural intent (`D-281-FREEZE-INVARIANT-01` owed-salt + Phase 288 dailyIdx + Phase 296 RETRY_LOOTBOX_RNG domain-separation): per-index purchase-time commitment slots (`lootboxEth`, `lootboxDay`, `lootboxBaseLevelPacked`, `lootboxEvScorePacked`) snapshot the player's state AT THE TIME OF LOOTBOX PURCHASE (Phase 281 owed-salt precedent), so that open-time resolution reads frozen inputs. For V-032 the missing snapshot is on the `prizePoolsPacked` cross-pool value — `openLootBox`'s resolution path reads `_getPrizePools()` LIVE during the open-time consolidation, which means an attacker can mutate `prizePoolsPacked` between buy-time and open-time. Per `feedback_design_intent_before_deletion.md`, the per-index snapshot pattern IS the design intent (already applied for `lootboxEth` via Phase 281 owed-salt) — the snapshot just didn't extend to the prize-pool cross-pool fields. Tactic (a) rngLockedFlag-gated revert at `openLootBox` would break the design intent: lootbox open is supposed to be a frozen-input deterministic resolution; gating it on rngLock would create a denial-of-service window where players cannot redeem their VRF'd lootboxes.

### §7.B — Actor game-theory walk

**Exploit-actor class:** any EOA holding an unopened lootbox with `lootboxRngWordByIndex[index] != 0` (RNG published). **Action sequence:** the attacker has a lootbox bought at time T0 (with `prizePool@T0 = P0`). Between T0 and open-time T1, OTHER players (or the attacker themselves) mutate `prizePoolsPacked` via the V-024/V-025/V-027/V-031 paths (all the EOA writers in this cluster). At open-time T1, the attacker fires `openLootBox(player, lootboxIndex)`. The open-resolution path reads `_getPrizePools()` LIVE (at `prizePool@T1 = P1`) and uses `P1` for any pool-relative payout caps or share computations. Since `P1 > P0` is achievable by the attacker's allies (or even the attacker themselves prior to opening), the open-time payout magnitude can be inflated relative to the original buy-time commitment. Per `feedback_rng_window_storage_read_freshness.md`, this is the F-41-02/03 class precisely: a SLOAD inside the resolution window reads a slot the attacker can mutate before the read. **EV magnitude:** HIGH per the F-41-02/03 precedent — `prizePool` directly affects payout caps; manipulation is fee-cheap and can be batched across many lootbox indices. **Disposition:** HIGH-tier.

### §7.C — Recommended tactic + rationale + impact

**Tactic:** (b) snapshot/anchor pattern. Per catalog row V-032: "Domain-separated lootbox VRF; snapshot prizePool at lootbox-buy-time, not open-time". This is the Phase 281 owed-salt + Phase 288 dailyIdx snapshot precedent applied to S-09. Implementation outline: at lootbox-buy time (the per-index commitment write, e.g. `MintModule._allocateLootbox` at `MintModule.sol:991` for the catalog row V-091 site, and the corresponding Whale / Burnie allocation sites), snapshot the buy-time `prizePoolsPacked` value (or the relevant payout-cap-driving subfield such as `nextPool` for the cap-multiplier flow) into a per-index packed slot — either a new field within an EXISTING per-index commitment struct (e.g. extending `lootboxBaseLevelPacked` or `lootboxEvScorePacked` with a packed `prizePoolSnapshot` field) or a new dedicated mapping. At open-time, the resolution path reads the per-index snapshot instead of the live `_getPrizePools()`. **Storage discipline (CRITICAL):** `prizePoolsPacked` is performance-critical and packed for SLOAD efficiency. The snapshot field MUST be packed alongside an existing per-index field to avoid a new dedicated 32-byte slot per index. The recommended layout: extend the existing `lootboxBaseLevelPacked[index][player]` (currently 256 bits with baseLevel + presale + auxiliary fields) to include the snapshot in a packed sub-field. `RNGLOCK-CATALOG.md` §0 #2 already calls out the lootbox-cluster snapshot family — the V-032 snapshot is part of the same pattern. **Rationale for rejecting tactic (a):** rngLockedFlag-gated revert at `openLootBox` breaks the design: lootbox open is per-index, frozen-input deterministic; gating it on the global rngLockedFlag would block redemption during every daily jackpot window, which is a UX denial. **Bytecode impact:** ~100-200 bytes (new snapshot write path at allocation sites + new snapshot read in open resolution + ~3 SSTOREs/SLOADs per lootbox lifecycle). **Storage layout:** REQUIRES per-index packed-field extension — the snapshot field must be added within an existing per-index struct to avoid adding a new dedicated 32-byte slot. This is a layout change but a CONTAINED one (existing fields keep their bit ranges; the snapshot lives in the unused bit range of `lootboxBaseLevelPacked` per the canonical layout audit). **Public ABI:** NON-BREAKING — `openLootBox`/`openBurnieLootBox` signatures unchanged.

### §7.D — v44.0 handoff anchor

**Anchor:** `D-43N-V44-HANDOFF-19`
**Citation:** `DegenerusGame.sol:665` (`openLootBox`), `:673` (`openBurnieLootBox`) — payout consolidation surface; allocation-side snapshot sites at `MintModule.sol:991` (per-index commitment for buy-side), `WhaleModule.sol:854`, `MintModule.sol:1397` (BURNIE allocation)
**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row V-032; cross-links to the 35-row lootbox open-resolution cluster headlined in §0 #2.

---

## Cluster Summary

| § | VIOLATION | Writer entry | Tactic | EV-tier | Handoff anchor |
|---|-----------|--------------|--------|---------|----------------|
| §1 | V-024 | MintModule.purchase / purchaseCoin / purchaseBurnieLootbox | (a) | MEDIUM | D-43N-V44-HANDOFF-13 |
| §2 | V-025 | WhaleModule.purchaseWhaleBundle / purchaseLazyPass | (a) | MEDIUM | D-43N-V44-HANDOFF-14 |
| §3 | V-026 | WhaleModule.purchaseDeityPass | (a) — already gated | LOW (coverage only) | D-43N-V44-HANDOFF-15 |
| §4 | V-027 | DegenerusGame.recordDecBurn (BurnieCoin callback) | (a) | MEDIUM-HIGH | D-43N-V44-HANDOFF-16 |
| §5 | V-030 | DegenerusGame.claimWhalePass → _queueTicketRange | (a) | LOW (downstream gate) | D-43N-V44-HANDOFF-17 |
| §6 | V-031 | placeDegeneretteBet → _collectBetFunds | (a) | HIGH | D-43N-V44-HANDOFF-18 |
| §7 | V-032 | openLootBox / openBurnieLootBox payout consolidation | (b) | HIGH | D-43N-V44-HANDOFF-19 |

**Tactic mix:** (a) rngLockedFlag-gated revert × 6 (V-024, V-025, V-026 [coverage-only], V-027, V-030, V-031); (b) snapshot/anchor × 1 (V-032).
**EV-tier distribution:** HIGH × 2 (V-031, V-032); MEDIUM-HIGH × 1 (V-027); MEDIUM × 2 (V-024, V-025); LOW × 2 (V-026 [structurally gated], V-030 [downstream gated]).
**Handoff anchors emitted:** D-43N-V44-HANDOFF-13, -14, -15, -16, -17, -18, -19 (7 anchors, sequential, matching the catalog §16 placeholder block for V-024..V-027 + V-030..V-032).

**v44.0 plan-phase consumption:** each §N.D anchor is the entry-budget unit for a v44.0 sub-phase (per `D-43N-AUDIT-ONLY-01` handoff register); the v44.0 plan-phase may group the 6 tactic-(a) anchors (H-13..H-18) into a single "S-09 rngLock entry-revert" sub-phase, with the tactic-(b) snapshot (H-19) routed to the lootbox-snapshot sub-phase per §0 #2 cluster grouping.
