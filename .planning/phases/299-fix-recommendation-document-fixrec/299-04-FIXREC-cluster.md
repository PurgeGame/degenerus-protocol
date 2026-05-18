# Phase 299 — FIXREC Cluster D: sDGNRS poolBalances Reward + Lootbox (cross-contract)

**Cluster:** D — Slots S-14 (`sDGNRS poolBalances[Pool.Reward]`) + S-15 (`sDGNRS poolBalances[Pool.Lootbox]`) cross-contract pool-balance race exposure.
**VIOLATIONs covered:** V-043, V-045, V-046, V-047, V-048, V-050, V-051 (7 logical entries — `D-43N-V44-HANDOFF-20`..`D-43N-V44-HANDOFF-26`).
**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §14 rows S-14/S-15; §15 writer enumeration rows 170-177; §16 verdict-matrix rows 376-387; consumers §1 (`JackpotModule._handleSoloBucketWinner` final-day Reward read), §6 (`LootboxModule.resolveRedemptionLootbox` Lootbox-pool read), §7 (`LootboxModule._resolveLootboxCommon` manual-path Lootbox-pool read), §11 (`BurnieCoinflip` → `payCoinflipBountyDgnrs` Reward-pool bounty read).
**Posture:** AUDIT-ONLY per `D-43N-AUDIT-ONLY-01`. Zero `contracts/` + zero `test/` mutations. Authorial output only.
**Drafted:** 2026-05-18

---

## Cluster preamble — cross-contract slot architecture (load-bearing for every §N.A below)

The two participating slots in this cluster live in a separately deployed sister contract (`contracts/StakedDegenerusStonk.sol`), not in `DegenerusGame` storage. Per `D-298-EXEMPT-CROSSCONTRACT-01`, cross-contract slots inherit per-callsite classification by walking the reach-stack of each invocation; the same writer function can carry distinct verdicts at distinct callsites. Per `D-298-TRACE-DEPTH-01`, the sDGNRS slot is in-source-scope (the file lives under `contracts/`) and its writers are enumerated alongside `contracts/`-internal writers in §15.

The slot itself is declared as `uint256[5] internal poolBalances` (one slot per `Pool` enum value: `Whale`, `Affiliate`, `Lootbox`, `Reward`, `Earlybird`). Writers in the source-of-truth grep (`grep -n "poolBalances\[" contracts/StakedDegenerusStonk.sol`):

| File:line | Writer | Function |
|-----------|--------|----------|
| `:310-:314` | constructor batch init | `constructor` |
| `:422` | `poolBalances[idx] = available - amount;` (unchecked debit) | `transferFromPool(Pool, address, uint256)` — `onlyGame` |
| `:453` | `poolBalances[fromIdx] = available - amount;` (unchecked debit) | `transferBetweenPools(Pool, Pool, uint256)` — `onlyGame` |
| `:455` | `poolBalances[toIdx] += amount;` (credit) | same function — paired with `:453` |
| `:469` | `delete poolBalances;` (zero-out array) | `burnAtGameOver()` — `onlyGame` |

Reach-graph: every post-deploy writer is gated by the `onlyGame` modifier (`msg.sender == ContractAddresses.GAME`). The `transferFromPool` and `transferBetweenPools` functions are the ONLY mutators that can fire during the rngLock window — `burnAtGameOver` is reached only via `_handleGameOverPath` from `advanceGame` (EXEMPT-VRFCALLBACK / EXEMPT-ADVANCEGAME, see catalog row 386 V-052) and the constructor runs once pre-deploy. Consequently, every VIOLATION in this cluster traces to one of the two debit/credit functions reached from an EOA-callable entry point in `DegenerusGame.sol` or one of its delegated modules.

**Two consumers depend on live SLOADs of these slots during a rngLock window:**

1. `JackpotModule._handleSoloBucketWinner` reads `dgnrs.poolBalance(Pool.Reward)` at `DegenerusGameJackpotModule.sol:1493`, scales by `FINAL_DAY_DGNRS_BPS / 10_000` at `:1496`, and calls `dgnrs.transferFromPool(Pool.Reward, w, reward)` at `:1498` — on the final physical day's solo-bucket winner only. This consumer is in the advanceGame stack itself, BUT the slot value can be mutated cross-call between `_swapAndFreeze` (when VRF is requested) and the final-day resolution by any non-advanceGame writer.
2. `LootboxModule._lootboxDgnrsReward` reads `dgnrs.poolBalance(Pool.Lootbox)` at `DegenerusGameLootboxModule.sol:1770`, scales by `(ppm * amount) / (1_000_000 * 1 ether)`, caps at the pool balance, and credits via `dgnrs.transferFromPool(Pool.Lootbox, player, amount)` at `:1786` inside `_creditDgnrsReward`. This is reached from 4 dispatcher shells: `openLootBox` (EOA), `openBurnieLootBox` (EOA), `resolveLootboxDirect` (auto-resolve, advance-stack), `resolveRedemptionLootbox` (auto-resolve from sStonk claimRedemption — EOA-triggered indirectly).

Additionally, `payCoinflipBountyDgnrs` at `DegenerusGame.sol:402` reads `dgnrs.poolBalance(Pool.Reward)` at `:414`, scales by `COINFLIP_BOUNTY_DGNRS_BPS / 10_000` at `:418`, and writes via `transferFromPool` at `:420`. The catalog classifies this as EXEMPT-VRFCALLBACK (V-042) when reached from `BurnieCoinflip.processCoinflipPayouts` — but the function's caller-allowlist also includes `msg.sender == ContractAddresses.COIN` (DegenerusCoin) which is not in the same VRF stack. Per §B-6 of §11, the catalog accepts the EXEMPT-VRFCALLBACK classification for this consumer's reach; V-043 picks up the residual non-advanceGame Reward-pool writers from other GAME callsites.

**Phase 281 precedent (load-bearing for tactic (b) selection in every §N.C below):** `D-281-FIX-SHAPE-01` (`.planning/milestones/v41.0-phases/281-mint-batch-determinism-fix-fix/281-01-DESIGN-INTENT-TRACE.md`) introduced the **owed-salt 4th-keccak-input snapshot** pattern as the canonical resolution shape for "live-SLOAD-between-commitment-and-resolution" race classes. Selected because it produced zero storage delta, zero new SSTORE/SLOAD on the hot path, minimal grep footprint, neutral actor game-theory, and preservation of the indexer-replay invariant. Phase 288's `dailyIdx` structural-anchor snapshot extended the precedent to multi-call resolution stacks. Cluster D maps directly: the resolution-consumer reads the cross-contract pool balance AFTER the entropy commitment moment; snapshotting the pool balance at the commitment moment (`_swapAndFreeze` for the daily-VRF consumer §1, lootbox-purchase / `lootboxRngWordByIndex[index]` write for manual-path lootbox §7, burn submission for sStonk claimRedemption §6) eliminates the cross-contract write race at the cost of one extra `uint256` snapshot field per commitment record.

Per `feedback_design_intent_before_deletion.md`: the natural decomposition of "what would break if pools were frozen" is documented per §N.A below. Per `feedback_rng_backward_trace.md`: every entry below traces backward from the consumer SLOAD site to verify the pool-balance value was unknown at the entropy-commitment moment but subject to mutation in the rng-window. Per `feedback_rng_window_storage_read_freshness.md`: the slot is a non-VRF SLOAD consumed alongside the VRF word, a distinct bug class per the F-41-02 / F-41-03 precedent.

---

## §1 — V-043: sDGNRS poolBalances[Reward] × `transferFromPool` from non-advanceGame GAME entries (claim/settlement paths)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 378 (V-043). §1 row 41 (D-43N catalog row 41 verdict-matrix). Writer enumeration §15 row 170. §1 §C "Slot: sDGNRS `poolBalances[Pool.Reward]` (cross-contract)" and §1 §D row 41.

### §1.A — Design-intent backward-trace

**Slot introduction phase:** The sDGNRS `poolBalances` array was introduced as part of the sDGNRS sister-contract architecture — a separately deployed soulbound token backed by ETH / stETH / BURNIE reserves with pre-minted supply split across five reward pools (`Whale`, `Affiliate`, `Lootbox`, `Reward`, `Earlybird`). The Reward pool specifically is the "general payout" tier: the final-day solo-bucket DGNRS reward (`JackpotModule.sol:1496` `(dgnrsPool * FINAL_DAY_DGNRS_BPS) / 10_000`), the BurnieCoin / Coinflip bounty payouts (`DegenerusGame.payCoinflipBountyDgnrs:418`), and Decimator/Lootbox `Reward`-keyed drains all source from this slot.

The economic function: the Reward pool is the "tail" of the v40-era prize-distribution architecture. Every distribution from the Reward pool reduces the pool balance, and the pool is never refilled post-deploy (constructor sets it once at `:313` `poolBalances[uint8(Pool.Reward)] = rewardAmount`, and the only post-deploy writers are the debit-side `transferFromPool` plus the dual-write `transferBetweenPools`). This is the monotone-drain invariant: the Reward pool can only shrink during the game's active lifetime (and is then zeroed at `burnAtGameOver:469`).

**Cite for "what would break if frozen":** Freezing `poolBalances[Reward]` during rngLock would block legitimate non-advanceGame Reward-pool drains — specifically, the catalog row 41 enumerates "any non-advanceGame-stack write to `poolBalances[Pool.Reward]`" as the violation class. The set of legitimate writers includes (a) `payCoinflipBountyDgnrs` reached from `BurnieCoin.burnCoin` (the `msg.sender == COIN` arm at `DegenerusGame.sol:408`), (b) admin-style quest reward distribution paths, and (c) any other `DegenerusGame` callsite that distributes Reward-pool DGNRS as a side-effect of player action (e.g., a quest streak reward, an affiliate bonus payout, or a settlement claim). Each of these flows expects to debit the Reward pool during rngLock for legitimate gameplay reasons; gating them on `rngLockedFlag` (tactic (a)) would interrupt valid game flow and force user-visible failures on quest reward / settlement paths that share no causal dependency on the daily VRF resolution.

The catalog tactic (b) snapshot-at-`_swapAndFreeze` avoids the freeze entirely: the consumer (`_handleSoloBucketWinner`) gets a snapshot value taken at the VRF-request moment instead of a live SLOAD at the final-day resolution moment. Legitimate cross-contract drains continue unimpaired; the consumer simply reads a pinned value that cannot race the consumer's own VRF-derived selection.

**Precedent for snapshot pattern:** Phase 281 owed-salt 4th-keccak-input introduced the snapshot-at-commitment pattern for the mint-batch determinism class (`D-281-FIX-SHAPE-01` selected over (a) gated-revert because of zero storage delta and zero MEV surface). Phase 288 extended to `dailyIdx` structural anchor at lock-time. The Cluster-D Reward-pool snapshot is the direct application of this precedent to the cross-contract sDGNRS pool-balance class.

### §1.B — Actor game-theory walk

**Exploit-actor class:** Player triggering a non-advanceGame Reward-pool drain mid-rngLock window. Concrete vectors:

- Player calls `BurnieCoin.burnCoin(...)` (BurnieCoin EOA-callable surface), which transitively reaches `DegenerusGame.payCoinflipBountyDgnrs` via the `msg.sender == COIN` arm at `DegenerusGame.sol:408`. The bounty `payout = (poolBalance * COINFLIP_BOUNTY_DGNRS_BPS) / 10_000` at `:418` debits the Reward pool by 1% (or configured BPS) of the pool size. A determined attacker can chain multiple `burnCoin` calls during the rngLock window to drain the Reward pool by `n × COINFLIP_BOUNTY_DGNRS_BPS / 10_000` before the final-day solo-bucket consumer reads `dgnrsPool` at `:1493`.
- A player or operator triggering a quest reward / affiliate bonus / settlement flow that reaches `dgnrs.transferFromPool(Pool.Reward, ...)` from any `DegenerusGame.sol`-internal callsite outside the advanceGame stack. The catalog's wording — "claim/settlement paths, quest reward etc." — covers this class without enumerating every individual callsite, because the verdict-matrix classification is on the writer (`transferFromPool` from non-advanceGame stack) rather than per-callsite at row 41.

**Action sequence during rngLock window (sequential):**

- T0: `advanceGame` enters daily-phase, requests VRF, sets `rngLockedFlag = true` at `AdvanceModule:1634` (D-12 / §11 cross-reference).
- T1 (attacker move): Attacker observes the impending final-day solo-bucket distribution magnitude. Attacker calls `BurnieCoin.burnCoin(...)` or a quest-reward / settlement path that reaches `transferFromPool(Pool.Reward, ...)`. Pool balance shrinks by `Δ`.
- T2 (VRF callback): `rawFulfillRandomWords` fires, `_applyDailyRng` writes `rngWordCurrent`, advanceGame proceeds to `_handleSoloBucketWinner` final-day branch.
- T3 (consumer SLOAD): `_handleSoloBucketWinner` reads `dgnrsPool = dgnrs.poolBalance(Pool.Reward)` at `:1493`. This is `originalPool - Δ`.
- T4 (resolution): `reward = (originalPool - Δ) * FINAL_DAY_DGNRS_BPS / 10_000`. Consumer transfers `reward` to the VRF-selected winner. The attacker has reduced the winner's payout by `Δ * FINAL_DAY_DGNRS_BPS / 10_000`.

**EV magnitude estimate:** **MEDIUM-HIGH on the per-tx margin; CATASTROPHE-tier in absolute USD on the final physical day.** The final-day solo-bucket distribution is a terminal one-shot payout; the catalog §1 §B "B-6" attestation confirms this slot drives the entire terminal-day DGNRS payout amount. The attacker's per-tx Δ is bounded by `COINFLIP_BOUNTY_DGNRS_BPS / 10_000` (typically ~1% per drain call), but multiple drains within the rngLock window are additive. The attacker need not be the winner; even an indifferent third party can frontrun the winner's expected payout, and a SDGNRS holder with conflicting incentives (e.g., short bias on the terminal-day distribution) realizes EV from the deflation. Economic-likelihood disposition: **likely-exploited** on the final physical day, because the terminal payout magnitude is observable from public state in advance and the rngLock window provides a deterministic write opportunity.

**Note on the V-042 EXEMPT-VRFCALLBACK boundary:** When reached from `BurnieCoinflip.processCoinflipPayouts` (catalog row 377 V-042), the same writer function is EXEMPT-VRFCALLBACK because that resolution path runs inside `processCoinflipPayouts` which is itself gated by the `onlyDegenerusGameContract` modifier and reached only from advanceGame-stack callsites (catalog §11 §A entry 1 attestation). V-043 captures the residual non-advanceGame, non-Coinflip-resolution callsites — i.e., the `msg.sender == COIN` arm reached from `BurnieCoin.burnCoin` directly (EOA), and any other GAME-internal callsite outside the advance-stack.

### §1.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) snapshot/anchor pattern.** Catalog §1 §E row 41 rationale: "snapshot `dgnrsPool` at `_swapAndFreeze` time; read snapshot inside `_handleSoloBucketWinner`."

**Concrete shape:**

- Introduce a packed snapshot field `dgnrsRewardPoolSnapshot` (uint128 sufficient since `INITIAL_SUPPLY` fits well under `2^128 − 1`).
- Populate the field inside `_swapAndFreeze` (the same advance-stack callsite where `prizePoolsPacked` is already snapshotted per catalog rows 19-20). Call `dgnrs.poolBalance(Pool.Reward)` once, store in the snapshot field.
- Modify `_handleSoloBucketWinner` final-day branch (`DegenerusGameJackpotModule.sol:1493`) to read the snapshot field instead of the live SLOAD.
- The `transferFromPool` write at `:1498` continues to fire against the live pool balance — only the magnitude calculation uses the snapshot. (The actual transfer will still bound to live balance via `transferFromPool`'s internal `amount > available` clamp at `StakedDegenerusStonk.sol:418-420`, so the snapshot value is the "intended" magnitude and the live pool clamp is the safety floor.)

**Rationale for rejecting alternative tactics:**

- **(a) `rngLockedFlag`-gated revert** rejected: gating `payCoinflipBountyDgnrs` (or every quest-reward / settlement path) on `rngLockedFlag` would interrupt legitimate gameplay flows that share no causal dependency on the daily VRF resolution. The class includes flows like `BurnieCoin.burnCoin` → coinflip bounty payout which are themselves part of normal in-game economy.
- **(c) pre-lock reorder** rejected: the consumer's read is structurally tied to the final-day solo-bucket branch which fires inside the advance-stack resolution. Reordering writers to land before `_swapAndFreeze` is impossible because the writers are EOA-triggered at attacker discretion.
- **(d) immutable** rejected: the slot is fundamentally mutable (pool drains over the game's lifetime).

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** new packed snapshot field `dgnrsRewardPoolSnapshot` (uint128). 16 bytes. Fits inside the existing `prizePoolsPacked`-adjacent layout in `DegenerusGameStorage` (packing options determined by Phase 299→v44 plan-phase). **NOT byte-identical** — one new slot or one slot-extension. Storage-delta = +16 bytes (or +32 if standalone slot for layout simplicity).
- **Bytecode delta:** ~100-150 bytes. One additional `dgnrs.poolBalance(Pool.Reward)` external call inside `_swapAndFreeze` (single SLOAD on sDGNRS side + STATICCALL overhead ≈ 2500 gas worst-case cold), one SSTORE on the snapshot field (~20000 gas warm), one SLOAD on the snapshot field replacing the live external call at `:1493` (eliminates the existing STATICCALL).
- **Net runtime gas:** approximately neutral on the hot path. `_swapAndFreeze` pays +1 STATICCALL +1 SSTORE; `_handleSoloBucketWinner` saves 1 STATICCALL and gains 1 SLOAD. Final-day path runs once per game so the snapshot SSTORE cost amortizes to zero per game.
- **Public ABI:** **NON-BREAKING.** No event topic-hash change; the new field is internal storage. External views can expose the snapshot via a new view function if desired (v44 plan-phase discretion).
- **Reference precedent:** Phase 281 owed-salt snapshot is exactly this shape, zero ABI delta and +~30 gas per `_raritySymbolBatch` invocation (Phase 281 §iii cost analysis). Phase 288 `dailyIdx` structural snapshot is the multi-call analog.

### §1.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-20`** — Snapshot sDGNRS `poolBalances[Pool.Reward]` at `_swapAndFreeze` time; `_handleSoloBucketWinner` final-day branch reads the snapshot instead of the live external `dgnrs.poolBalance(Pool.Reward)` SLOAD. Concrete file:line targets:

- Snapshot WRITE site: inside `_swapAndFreeze` (callsites at `AdvanceModule.sol:299, :631, :1095` per catalog row 20).
- Snapshot READ site: replace the live external call at `DegenerusGameJackpotModule.sol:1493` (`dgnrs.poolBalance(IStakedDegenerusStonk.Pool.Reward)`) with a SLOAD on the new snapshot field.
- Storage field: new `dgnrsRewardPoolSnapshot` field in `DegenerusGameStorage.sol` (packing layout per v44 plan-phase discretion).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 378 (V-043) and §1 §E row 41.

---

## §2 — V-045: sDGNRS poolBalances[Reward] × sDGNRS-internal admin / initial-distribution writers

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 380 (V-045). §1 verdict-matrix row 43. Writer enumeration §15 row 172 (constructor / initial distribution). §1 §C "Slot: sDGNRS `poolBalances[Pool.Reward]` (cross-contract)".

### §2.A — Design-intent backward-trace

**Slot introduction phase:** Same architecture phase as §1.A — the sDGNRS sister-contract pool partitioning was introduced as the pre-deploy supply distribution mechanism. The constructor at `StakedDegenerusStonk.sol:307-:314` mints `poolTotal` to `address(this)` and assigns the five pool subtotals (`whaleAmount`, `affiliateAmount`, `lootboxAmount`, `rewardAmount`, `earlybirdAmount`). The Reward pool's initial value is `rewardAmount`, computed pre-deploy from the sDGNRS deploy parameters.

**The V-045 row in the catalog (§16 row 380) describes "sDGNRS-internal writers (admin / initial distribution / ERC20 mint into pool)" as the writer class.** Per grep verification (`grep -n "poolBalances\[" contracts/StakedDegenerusStonk.sol`), the actual writer set is exactly:

| Site | Writer |
|------|--------|
| `:310-:314` | constructor batch initialization (pre-deploy, runs once) |
| `:422` | `transferFromPool` (debit) — `onlyGame` |
| `:453, :455` | `transferBetweenPools` (debit + credit pair) — `onlyGame` |
| `:469` | `burnAtGameOver` (`delete poolBalances`) — `onlyGame` |

There is no sDGNRS-side admin function that writes `poolBalances[Reward]` outside the constructor (verified by exhaustive grep). The V-045 row's characterization ("admin / initial distribution / ERC20 mint into pool") therefore describes the CLASS of writers reaching from non-GAME entry points — which in the current source is JUST the constructor (a one-shot, pre-deploy event).

**Note on per-design-intent finality:** Per `feedback_frozen_contracts_no_future_proofing.md`, contracts are frozen at deploy and design-intent is fixed at deployment time. V-045 therefore captures the residual VIOLATION class for any sDGNRS-internal writer that is NOT covered by the per-callsite verdict in §16 rows for `transferFromPool` / `transferBetweenPools` — which in practice is only the constructor (catalog row 43 explicitly says "initial pool funding, admin distribution, ERC20 mint into pool"). Since the constructor cannot fire during a live game's rngLock window (Solidity constructors run exactly once at deploy), V-045 is structurally a NULL-set violation in the deployed system — but the catalog row carries the VIOLATION token under `D-43N-AUDIT-ONLY-01` strict discipline (no "safe-by-design" attestation class permitted; the only available token is VIOLATION).

**Cite for "what would break if frozen":** Freezing the Reward pool against the (already non-existent) admin / initial-distribution writers during rngLock is a no-op behavioral change in the current frozen contracts. The catalog row 43 row exists to preserve the verdict-matrix completeness invariant: every (slot × writer × callsite) tuple carries one of `EXEMPT-ADVANCEGAME` / `EXEMPT-VRFCALLBACK` / `EXEMPT-RETRYLOOTBOXRNG` / `VIOLATION`. The class "sDGNRS-internal admin / initial distribution writers" must receive a token, and under audit-only strict-discipline that token is VIOLATION.

### §2.B — Actor game-theory walk

**Exploit-actor class:** Pre-deploy admin (deployer / DAO / multisig). Action sequence: at deploy time, admin sets `rewardAmount` in the constructor input parameters. No post-deploy admin writer of `poolBalances[Reward]` exists in the source. The "exploit" would require either (a) a malicious deployer pre-deploy, OR (b) a hypothetical future admin distribution writer added in a contract upgrade (which is prohibited by contract-frozen-at-deploy posture per `feedback_frozen_contracts_no_future_proofing.md`).

**Action sequence during rngLock window:** Not applicable — the constructor cannot fire during a live game's rngLock window. The slot's post-deploy mutation is exclusively through `transferFromPool` / `transferBetweenPools` / `burnAtGameOver` (covered by V-043 / V-051 / V-052).

**EV magnitude estimate:** **LOW (governance-trust class) in practical terms; MEDIUM (catalog-discipline class).** The catalog row 43 carries the VIOLATION token because of strict-classification discipline, not because of a live exploit surface. The economic-likelihood disposition: **non-exploitable in the deployed contract** (the writer class is empty post-deploy). The catalog row exists to preserve the strict-discipline invariant and to forward the verdict for v44.0 FIX-MILESTONE consideration if any future contract change introduces an admin writer of this slot.

### §2.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) snapshot/anchor pattern.** Catalog §1 §E row 43 rationale: "same snapshot-at-freeze pattern — eliminates cross-contract write race."

**Concrete shape:** The same snapshot at `_swapAndFreeze` introduced for V-043 covers V-045 automatically. The snapshot field `dgnrsRewardPoolSnapshot` is read in lieu of the live SLOAD; any hypothetical cross-contract writer (admin / initial distribution / OZ-inherited ERC20) cannot race the consumer because the consumer no longer performs a live SLOAD inside the rng-window.

**Rationale for rejecting alternative tactics:**

- **(a) `rngLockedFlag`-gated revert** rejected: the only writer of this class is the constructor (which runs pre-deploy, not during rngLock). Gating it serves no purpose. For hypothetical future admin writers, the gate would land on the admin function in sDGNRS — but sDGNRS does not query `game.rngLocked()` for any writer other than `burn()` at `:492`. Adding a new gate-query is more invasive than the snapshot tactic and yields no consumer-side guarantee.
- **(c) pre-lock reorder** rejected: no current writer of this class fires during rngLock to reorder.
- **(d) immutable** rejected: the slot must remain mutable (the Reward pool drains over the game's lifetime via `transferFromPool`).

**Bytecode / storage-layout / public-ABI impact:** **Zero marginal cost beyond V-043.** V-045 is fully covered by the same snapshot field and snapshot SSTORE introduced for V-043. The two violations share `D-43N-V44-HANDOFF-21` and `D-43N-V44-HANDOFF-20` as a unified fix surface in the v44.0 plan-phase. Storage delta = 0 marginal bytes; bytecode delta = 0 marginal bytes; runtime gas delta = 0 marginal gas.

**Reference precedent:** Phase 281 owed-salt snapshot — single-field snapshot at commitment moment cures both VRF-derived-writer and non-VRF-writer race classes against the consumer.

### §2.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-21`** — Same snapshot mechanism as `D-43N-V44-HANDOFF-20` covers the sDGNRS-internal admin / initial-distribution writer race-class. The v44.0 plan-phase implementation lands a single snapshot field that resolves both V-043 and V-045 atomically.

- Implementation cite: same as `D-43N-V44-HANDOFF-20` — `_swapAndFreeze` snapshot WRITE, `_handleSoloBucketWinner:1493` snapshot READ.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 380 (V-045) and §1 §E row 43.

---

## §3 — V-046: sDGNRS poolBalances[Reward] × OZ-inherited ERC20 writers (the lone non-`contracts/` VIOLATION)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 381 (V-046). §15 writer enumeration row 173 ("ERC20 `transfer` / `transferFrom` / `_mint` / `_burn` (OZ-inherited)"). §17 OZ-carveout table rows for `_mint` / `_burn`. `D-298-OZ-CARVEOUT-01` is the governing locked-decision.

### §3.A — Design-intent backward-trace

**Slot introduction phase:** Same cluster preamble — sDGNRS sister-contract pool partitioning. The OZ-inherited writer class is the catalog's accommodation of the structural fact that ERC20 standard methods (`_mint`, `_burn`, `transfer`, `transferFrom`, `approve`, `permit`) live in the OpenZeppelin library tree outside `contracts/`. Per `D-298-OZ-CARVEOUT-01`, these writers are listed in §15 with a `(OZ-inherited)` annotation and a `node_modules/@openzeppelin/...` path stub for §17 cross-coverage; they do not appear in the §17 Pattern 1/2 `contracts/` grep hits and are NOT discrepancies.

**Source-of-truth refinement:** A grep of `contracts/StakedDegenerusStonk.sol` shows **no `import` directive for `@openzeppelin/contracts/token/ERC20`** — sDGNRS implements its ERC20 surface internally (custom `balanceOf` mapping, custom `transfer`, custom `_mint`, custom `_burn`). The §15 row 173 enumeration ("OZ-inherited") is the catalog's classification of the ERC20 surface CLASS, not a claim that this specific contract inherits OZ ERC20 source. Sister contracts in the project DO inherit OZ ERC20 (BurnieCoin, WrappedWrappedXRP, DegenerusStonk wrapper); the catalog `D-298-OZ-CARVEOUT-01` rule applies generically across the contract suite.

**Key catalog claim (§16 row 381):** "OZ-inherited writers (`_mint`, `_burn`, ERC20 standard methods) — `node_modules/@openzeppelin/.../ERC20.sol` `(OZ-inherited)` — NO — non-EXEMPT EOA ERC20 surface — VIOLATION — (b) — OZ-inherited writer; snapshot-at-freeze covers ERC20 transfer race."

**Important structural disambiguation:** OZ ERC20 `_mint` / `_burn` / `transfer` / `transferFrom` write `balanceOf` mappings, NOT `poolBalances[idx]`. The `poolBalances[Reward]` slot is mutated ONLY by `transferFromPool` / `transferBetweenPools` / `burnAtGameOver` (the four grep-verified writers in the cluster preamble). The OZ-inherited writer class therefore enters this VIOLATION row INDIRECTLY: ERC20 transfers/mints into / out of `address(this)` change `balanceOf[address(this)]` and `totalSupply`, but they DO NOT directly write the `poolBalances` array. The catalog row 381 conflates two slots (the ERC20 `balanceOf` family and the `poolBalances` array) under the same "sDGNRS Reward-pool race" umbrella. Per `feedback_verify_call_graph_against_source.md`, this FIXREC entry refines the catalog by noting the indirection: ERC20-surface writes on `balanceOf[address(this)]` and `totalSupply` are part of the same accounting envelope as `poolBalances[Reward]` and a desync between them (e.g., a `_burn` from `address(this)` that does NOT zero out a `poolBalances[Reward]` slot) could in principle change the effective Reward-pool magnitude observable through `poolBalance(Pool.Reward)` view. In the deployed source, this view returns `poolBalances[_poolIndex(pool)]` directly (`StakedDegenerusStonk.sol:392`) — it does NOT consult `balanceOf[address(this)]`. Therefore the ERC20-surface writes are NOT directly observable through the consumer's read at `JackpotModule.sol:1493`.

**The lone non-`contracts/` VIOLATION attestation (per the verifier's framing in the plan):** V-046 is the only VIOLATION in the verdict matrix whose writer source-of-record lives OUTSIDE `contracts/` (in `node_modules/@openzeppelin/`). Every other VIOLATION in Cluster D, and indeed every other VIOLATION in the entire catalog, traces to a writer function declared inside `contracts/`. V-046's structural distinctness drives the recommendation in §3.C: the fix CANNOT land on the OZ source file itself (it is a third-party dependency outside the project's modification scope and would create an indefensible maintenance burden); the fix MUST land in `contracts/` via the snapshot-at-freeze tactic, which gates the CONSUMER's read rather than the WRITER's mutate.

**Cite for "what would break if frozen":** Freezing OZ ERC20 standard methods during rngLock would block legitimate ERC20 surface flows (sDGNRS holder transfers, burns, mints during normal play). For sDGNRS specifically, the contract is soulbound (no `transfer` to non-zero addresses) — but `_mint`, `_burn`, and `wrapperTransferTo` (`:337`, restricted to `msg.sender == DGNRS`) still fire during normal play. Gating these on `rngLockedFlag` would break the DGNRS wrapper's unwrap flow during the rng-window — an unacceptable user-visible regression. The snapshot tactic preserves all standard-ERC20 behaviors while removing the consumer-side race.

### §3.B — Actor game-theory walk

**Exploit-actor class:** Any sDGNRS-holding EOA executing the ERC20 surface during the rngLock window. Concrete vectors:

- DGNRS wrapper holder calls `DegenerusStonk.burn(amount)` (or similar wrapper-side burn entry) which transitively reaches `_burn(address(this), amount)` inside sDGNRS, reducing `balanceOf[address(this)]` and `totalSupply`. Per the disambiguation in §3.A, this does NOT directly write `poolBalances[Reward]` but DOES change the effective sDGNRS accounting envelope.
- sDGNRS holder triggers a `wrapperTransferTo` (restricted to `msg.sender == DGNRS`) — an indirect EOA reach via the DGNRS wrapper's unwrap flow.

**Action sequence during rngLock window:** Same temporal shape as §1.B but the mutation target is `balanceOf[address(this)]` / `totalSupply` rather than `poolBalances[Reward]` directly. The consumer-side read at `JackpotModule.sol:1493` reads `poolBalance(Pool.Reward)` which returns `poolBalances[_poolIndex(pool)]` directly — so the ERC20-surface mutation does NOT race the consumer's `dgnrsPool` value. The catalog row 381 lists this writer class as VIOLATION under the conservative D-43N-AUDIT-ONLY-01 strict discipline (every writer class gets a token), but the structural reality is that the OZ-surface mutations do not flow into the consumer's SLOAD path.

**EV magnitude estimate:** **LOW per-write; effectively zero in practice for the Reward-pool consumer's read.** The catalog row carries VIOLATION as a conservative classification; the structural disambiguation in §3.A shows the indirection does not reach the consumer. The economic-likelihood disposition: **non-exploitable through the documented consumer reach path**, but the row is preserved for catalog-discipline completeness and to forward the OZ-carveout pattern to v44.0 FIX-MILESTONE for explicit attestation.

### §3.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) snapshot/anchor pattern.** Catalog §1 §E (row 43-equivalent for OZ surface) rationale: "OZ-inherited writer; snapshot-at-freeze covers ERC20 transfer race."

**Concrete shape:** Same as V-043 — the snapshot field `dgnrsRewardPoolSnapshot` covers the OZ-inherited writer race-class automatically. The consumer no longer reads `poolBalances[Reward]` (or any other sDGNRS-side accounting field) live during the rngLock window; it reads the snapshot captured at `_swapAndFreeze` instead.

**The "fix-in-`contracts/`" pattern (load-bearing per `D-298-OZ-CARVEOUT-01` and the plan's V-046-specific requirement):** Because OZ-inherited writers live OUTSIDE `contracts/` (in `node_modules/@openzeppelin/contracts/token/ERC20/ERC20.sol`), the FIX cannot land on the writer source. Two structural options exist:

1. **Gate the calling function in `contracts/`** that invokes the OZ-inherited writer. For sister contracts that DO inherit OZ ERC20 (e.g., BurnieCoin's `_mint` / `_burn` reached from `mintForGame` / `burnForCoinflip`), the FIX would add `if (game.rngLocked()) revert RngLocked();` to the `contracts/`-side wrapper function — landing the gate on the calling surface rather than the OZ method itself.
2. **Snapshot the consumer's read at the commitment moment**, which is the catalog's selected tactic (b). This avoids touching the writer entirely; it gates the consumer instead.

The catalog selects option (2) for V-046 because the consumer-side snapshot is structurally simpler and more comprehensive: a single snapshot covers all writer classes simultaneously (V-043, V-045, V-046), and the snapshot landing site is in `contracts/` (`_swapAndFreeze`) where the v44.0 FIX-MILESTONE has authority to land changes.

**Documentation requirement per `D-298-OZ-CARVEOUT-01`:** The v44.0 plan-phase MUST attest that the chosen tactic-(b) snapshot pattern places the fix INSIDE `contracts/` (specifically inside `_swapAndFreeze` in `contracts/modules/DegenerusGameAdvanceModule.sol` and inside `_handleSoloBucketWinner` in `contracts/modules/DegenerusGameJackpotModule.sol`), with the OZ source files untouched. This attestation satisfies the carveout rule's requirement that no `node_modules/` files be modified.

**Rationale for rejecting alternative tactics:**

- **(a) `rngLockedFlag`-gated revert in OZ source** rejected: the writer source-of-record is in `node_modules/`. Modifying OZ source is structurally prohibited (third-party dependency, maintenance-burden indefensible). The plan's V-046-specific requirement explicitly directs the fix INTO `contracts/`.
- **(a) `rngLockedFlag`-gated revert in `contracts/` wrapper** is a viable alternative for sister contracts (BurnieCoin's wrappers, etc.), but for sDGNRS specifically, the contract has no `contracts/`-side wrapper around the OZ ERC20 surface (the ERC20 implementation is built-in, custom). The snapshot tactic is therefore simpler and works uniformly.
- **(c) pre-lock reorder** rejected: ERC20 mutations are EOA-discretionary; reordering is structurally impossible.
- **(d) immutable** rejected: `balanceOf[address(this)]` and `totalSupply` are inherently mutable.

**Bytecode / storage-layout / public-ABI impact:** **Zero marginal cost beyond V-043.** Same snapshot field, same SSTORE site, same SLOAD site. Storage delta = 0 marginal bytes; bytecode delta = 0 marginal bytes; runtime gas delta = 0 marginal gas.

**Reference precedent:** `D-298-OZ-CARVEOUT-01` explicitly permits the snapshot-in-`contracts/` pattern as the canonical resolution for the OZ-inherited writer class. Phase 281 owed-salt snapshot demonstrates the same "snapshot the consumer's read at commitment, leave the writer surface untouched" shape for the mint-batch class.

### §3.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-22`** — OZ-inherited writer class for sDGNRS poolBalances[Reward] resolved by the same snapshot-at-freeze tactic as V-043 / V-045. The OZ-carveout attestation requires the v44.0 plan-phase to confirm the FIX lands in `contracts/` only (no `node_modules/` modifications). Implementation cite: same as `D-43N-V44-HANDOFF-20`.

- OZ-carveout attestation cite: `D-298-OZ-CARVEOUT-01` in `.planning/phases/298-vrf-read-graph-catalog-catalog/298-CONTEXT.md` (and §15 / §17 of `.planning/RNGLOCK-CATALOG.md`).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 381 (V-046).

---

## §4 — V-047: sDGNRS poolBalances[Lootbox] × `transferFromPool` from `openLootBox` (manual EOA path)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 382 (V-047). §15 writer enumeration row 174 (`transferFromPool` reached from `openLootBox`). §6 verdict-matrix row D-6 ("`dgnrs.poolBalances[Pool.Lootbox]` × `transferFromPool` (debit via `_creditDgnrsReward` from `openLootBox` etc.)" — NO — VIOLATION).

### §4.A — Design-intent backward-trace

**Slot introduction phase:** Same cluster preamble. The Lootbox pool specifically funds the DGNRS-tier lootbox payouts: `LootboxModule._lootboxDgnrsReward` (`DegenerusGameLootboxModule.sol:1770`) scales `dgnrsAmount = (poolBalance * ppm * amount) / (1_000_000 * 1 ether)` where `ppm` is one of `LOOTBOX_DGNRS_POOL_SMALL_PPM` / `_MEDIUM_PPM` / `_LARGE_PPM` / `_MEGA_PPM` (catalog §6 §B B-9). The DGNRS-tier path is taken when `pathRoll < 13 && pathRoll >= 11` (10% of paths per §0 headline finding D-6/D-7 EV reach analysis).

The economic function: the Lootbox pool is the EV reward stream for the lootbox payout system — every lootbox-open call (manual `openLootBox` / `openBurnieLootBox` from EOA, OR auto-resolve from `resolveLootboxDirect` / `resolveRedemptionLootbox` from the advance/redemption stack) that rolls into the DGNRS-tier arm draws down `poolBalances[Lootbox]` via `_creditDgnrsReward:1786`. Pool refilling: the constructor sets `poolBalances[Lootbox] = lootboxAmount` at `:312`; post-deploy refills occur via `transferBetweenPools(otherPool, Pool.Lootbox, ...)` from advance-stack rebalances.

**Manual-path commitment-window (per `feedback_rng_commitment_window.md`, mirroring catalog §7 commitment-window discipline):**

- T0: Player buys a ticket lot in the MintModule lootbox-allocation path, reserving a lootbox-RNG `index` (`AdvanceModule._lrRead(LR_INDEX_SHIFT)`). The reserved `index` is the entropy-commitment moment for the manual lootbox payout.
- T1: Daily advance OR mid-day VRF fulfillment writes `lootboxRngWordByIndex[index] = word` at `_finalizeLootboxRng:1253`. From this point the per-index RNG word is final and public.
- T2: Player calls `DegenerusGame.openLootBox(player, index)` at `:665` (EOA) → delegatecalls `LootboxModule.openLootBox:526` → reads `lootboxRngWordByIndex[index]`, derives `seed = keccak256(rngWord, player, day, amount)`, calls `_resolveLootboxCommon:960` → `_resolveLootboxRoll:1623` → `_lootboxDgnrsReward:1770` (when DGNRS-tier branch is taken).

**Critical commitment-window structural fact:** The player opens TX C at their discretion AFTER TX B publishes `rngWord`. The catalog §7 trace explicitly notes: "every OTHER SLOAD reached during resolution (player's activity score, EV-cap usage, level, dgnrs pool balance, decimator window, boon storage, …) is sampled at TX C time, NOT at TX A (purchase) time. That is the structural source of every VIOLATION row." V-047 is the dgnrs-pool-balance instance of this class.

**Cite for "what would break if frozen":** Freezing `poolBalances[Lootbox]` during rngLock would block legitimate Lootbox-pool drains from concurrent lootbox-open flows (other players' `openLootBox` calls happening concurrently with the rngLock window). The pool is shared across all lootbox-resolution paths; gating each `_creditDgnrsReward` call on `rngLockedFlag` would force all DGNRS-tier lootbox payouts to fail-and-retry during every daily VRF cycle — an unacceptable user-visible degradation. The catalog's tactic (b) snapshot-at-burn-submission avoids this by snapshotting the pool balance at the entropy-commitment moment (the moment when `lootboxRngWordByIndex[index]` is written) and using the snapshot inside `_lootboxDgnrsReward` instead of the live SLOAD.

**Precedent for snapshot pattern:** Phase 281 owed-salt 4th-keccak-input snapshot at the commitment moment is the load-bearing precedent. Phase 288 `dailyIdx` structural anchor is the multi-call analog. The cluster-D Lootbox-pool snapshot mirrors the manual-lootbox commitment-window discipline already encoded in the catalog §6 / §7 trace.

### §4.B — Actor game-theory walk

**Exploit-actor class:** Player observing their own pending lootbox VRF word AND `poolBalances[Lootbox]`, deciding when to call `openLootBox` to maximize the DGNRS-tier payout magnitude.

**Action sequence during rngLock window (sequential, per catalog §6 D-9 analysis adapted to V-047's openLootBox reach):**

- T0 (player commits): Player buys ticket lot reserving lootbox-RNG `index`. `lootboxRngWordByIndex[index]` is not yet written.
- T1 (VRF callback): `_finalizeLootboxRng` writes `lootboxRngWordByIndex[index] = word`. Player now knows `rngWord` and can compute `seed = keccak256(rngWord, player, day, amount)`, the resolution path roll, and whether the DGNRS-tier branch will be taken — all BEFORE calling `openLootBox`.
- T2 (attacker move — pool manipulation): If the DGNRS-tier branch will be taken AND the tier roll lands in the mega-tier (`tierRoll >= 995`, 0.5% per the `LOOTBOX_DGNRS_POOL_MEGA_PPM` arm), the player can:
  - (a) Trigger OTHER players' `openLootBox` / `openBurnieLootBox` calls to drain the pool BEFORE their own claim (if the attacker controls or coordinates with other accounts).
  - (b) Trigger advance-stack rebalances via daily-advance cooperative yields (Phase 281 ticket-batch cooperative-yield primitive) that may relocate Lootbox-pool balance.
  - (c) Time their own `openLootBox` to land BEFORE / AFTER a concurrent advance-stack rebalance that moves Lootbox-pool balance.
- T3 (consumer SLOAD): Player calls `openLootBox`. `_lootboxDgnrsReward:1770` reads `dgnrs.poolBalance(Pool.Lootbox)`. Value is the cumulative pool balance at T3, which may differ substantially from the balance at T0 / T1.
- T4 (payout): `dgnrsAmount = (poolBalance * ppm * amount) / (1_000_000 * 1 ether)`. Capped at the pool balance. Player receives the payout.

**EV magnitude estimate:** **HIGH per-tx; CATASTROPHE-tier in the mega-tier 0.5% arm.** The mega-tier payout is `(poolBalance * LOOTBOX_DGNRS_POOL_MEGA_PPM * amount) / (1_000_000 * 1 ether)` — a single lootbox-open in the mega-tier arm can claim a substantial fraction of the entire Lootbox pool. The catalog §6 §B B-9 analysis and §0 headline finding (D-6/D-7) explicitly flag this as a deep VIOLATION cluster ("manual-path lootbox open is a deep VIOLATION cluster per §0 headline #2; Lootbox pool size is direct dgnrs-reward magnitude input"). The economic-likelihood disposition: **likely-exploited** by any whale-bias player who patches their lootbox-RNG window with cross-flow drains, particularly in late-game where the Lootbox pool size has been deflated and the mega-tier 0.5% arm represents a large fraction of remaining DGNRS supply.

### §4.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) snapshot/anchor pattern.** Catalog §16 row 382 rationale: "Snapshot pool balance at burn submission; pass as param into resolveRedemptionLootbox" — generalizes to: snapshot `poolBalances[Lootbox]` at the entropy-commitment moment (the `_finalizeLootboxRng` write of `lootboxRngWordByIndex[index]`) and pass into the resolution path.

**Concrete shape (for openLootBox manual-path specifically):**

- Introduce a per-index snapshot field `lootboxPoolSnapshotByIndex[index]` (uint128) in `DegenerusGameStorage`, keyed by the same `index` that keys `lootboxRngWordByIndex`.
- At the `_finalizeLootboxRng:1253` write of `lootboxRngWordByIndex[index] = word`, ALSO write `lootboxPoolSnapshotByIndex[index] = uint128(dgnrs.poolBalance(Pool.Lootbox))`.
- Modify `_lootboxDgnrsReward` (`DegenerusGameLootboxModule.sol:1770`) to read `lootboxPoolSnapshotByIndex[index]` instead of `dgnrs.poolBalance(Pool.Lootbox)` when called via the manual-path entry (the `_resolveLootboxCommon` reach from `openLootBox`).
- The auto-resolve paths (`resolveLootboxDirect`, `resolveRedemptionLootbox`) use different commitment-moment snapshots (covered by V-050 below).
- The `transferFromPool` debit at `:1786` continues to fire against the live pool balance; only the magnitude calculation uses the snapshot.

**Rationale for rejecting alternative tactics:**

- **(a) `rngLockedFlag`-gated revert** rejected: `openLootBox` is a manual EOA path that legitimately fires during the rngLock window (the lootbox-RNG flow is domain-separated from the daily-VRF flow per `D-42N-RETRY-RNG-DOMAIN-SEP-01`). Gating `openLootBox` on the daily `rngLockedFlag` would block legitimate lootbox-open calls and create a denial-of-service window during every daily VRF cycle.
- **(c) pre-lock reorder** rejected: the natural reorder point is at burn / index-commitment, which IS tactic (b).
- **(d) immutable** rejected: the slot is fundamentally mutable.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** new `lootboxPoolSnapshotByIndex[index]` mapping. ~32 bytes per active lootbox `index`. **NOT byte-identical** — new mapping. Storage delta = ~32 bytes per active lootbox slot.
- **Bytecode delta:** ~150-200 bytes. One additional `dgnrs.poolBalance(Pool.Lootbox)` STATICCALL inside `_finalizeLootboxRng` (~2500 gas cold / ~100 gas warm), one SSTORE on the snapshot mapping (~22100 gas cold / ~2900 gas warm), one SLOAD inside `_lootboxDgnrsReward` replacing the external STATICCALL.
- **Net runtime gas:** approximately neutral on the hot path. `_finalizeLootboxRng` pays +1 STATICCALL +1 SSTORE per lootbox-index; `_lootboxDgnrsReward` saves 1 STATICCALL per resolve. Manual-path resolve is EOA-discretionary so the snapshot SSTORE cost is paid up-front at VRF-fulfillment time (when the daily-advance budget already pays for the SSTOREs).
- **Public ABI:** **NON-BREAKING.** No event topic-hash change; new mapping. Could be exposed via a view function (v44 plan-phase discretion).
- **Reference precedent:** Phase 281 owed-salt snapshot + Phase 288 `dailyIdx` structural snapshot. The per-index keying mirrors the existing `lootboxRngWordByIndex[index]` shape — consistent with the catalog §7 commitment-window discipline ("lootbox-RNG flow is domain-separated; the per-index RNG word is the entropy-commitment").

### §4.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-23`** — Snapshot sDGNRS `poolBalances[Pool.Lootbox]` at `_finalizeLootboxRng` time (paired with `lootboxRngWordByIndex[index]` write); `_lootboxDgnrsReward` reads the snapshot when called from the manual-path resolution. Concrete cites:

- Snapshot WRITE site: extend `_finalizeLootboxRng` at `AdvanceModule.sol:1253` (lootbox-RNG fulfillment) to write `lootboxPoolSnapshotByIndex[index] = uint128(dgnrs.poolBalance(Pool.Lootbox))` alongside the existing `lootboxRngWordByIndex[index] = word` write.
- Snapshot READ site: replace `dgnrs.poolBalance(Pool.Lootbox)` at `LootboxModule.sol:1770` with `lootboxPoolSnapshotByIndex[index]` when entered via the manual-path dispatcher (`openLootBox` / `openBurnieLootBox`).
- Storage field: new `mapping(uint256 => uint128) lootboxPoolSnapshotByIndex` in `DegenerusGameStorage.sol`.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 382 (V-047), §6 D-6, §7 manual-path commitment-window discipline.

---

## §5 — V-048: sDGNRS poolBalances[Lootbox] × `transferFromPool` from `openBurnieLootBox` (manual EOA path, sibling to V-047)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 383 (V-048). §15 writer enumeration row 174 (`transferFromPool` reached from `openBurnieLootBox`). §6 verdict-matrix row D-7 ("`dgnrs.poolBalances[Pool.Lootbox]` × `transferFromPool` (debit) reaching entry `openBurnieLootBox` (EOA, sibling)" — NO — VIOLATION).

### §5.A — Design-intent backward-trace

**Slot introduction phase:** Same as §4.A. The `openBurnieLootBox` external entry (`LootboxModule.sol:607`) is the sibling of `openLootBox` (`:526`) — same Lootbox-pool consumer, same resolution path through `_resolveLootboxCommon:960` → `_resolveLootboxRoll:1623` → `_lootboxDgnrsReward:1770`, differing only in the payment surface (BURNIE token rather than ETH for the ticket purchase) and the lootbox-RNG `index` commitment shape.

The BurnieLootbox path was introduced as the BURNIE-coin-paid lootbox tier — same resolution mechanics, different funding source. The MintModule's lootbox-allocation path (`DegenerusGameMintModule.sol:1399`) writes `lootboxBurnie[index][buyer]` instead of `lootboxEth[index][buyer]`. The `index` semantics, the `_finalizeLootboxRng` write of `lootboxRngWordByIndex[index]`, and the `_lootboxDgnrsReward:1770` consumer-side SLOAD are all shared with V-047.

**Cite for "what would break if frozen":** Identical to §4.A — the Lootbox pool serves both ETH-paid and BURNIE-paid lootbox resolution paths; freezing the pool during rngLock would block both manual-path entries from drawing DGNRS-tier payouts.

### §5.B — Actor game-theory walk

**Exploit-actor class:** Identical to §4.B — player observing their own pending BURNIE-lootbox VRF word AND `poolBalances[Lootbox]`, deciding when to call `openBurnieLootBox` to maximize DGNRS-tier payout magnitude.

**Action sequence during rngLock window:** Identical sequence as §4.B with `openLootBox` → `openBurnieLootBox` substitution. The catalog §6 D-7 row confirms the same VIOLATION classification with the same reasoning: "reaching entry `openBurnieLootBox` (EOA, sibling). NO. **VIOLATION**."

**EV magnitude estimate:** **HIGH per-tx; CATASTROPHE-tier in the mega-tier arm.** Same magnitude class as V-047. The economic-likelihood disposition: **likely-exploited** in the same conditions as V-047, with a SLIGHT discount because BURNIE-paid lootboxes have a different funnel-cost profile (BURNIE token availability is rate-limited by the daily mint cycle), which marginally reduces the attacker's optionality compared to ETH-paid lootboxes. Net economic-likelihood disposition: **likely-exploited** alongside V-047.

### §5.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) snapshot/anchor pattern.** Catalog §16 row 383 rationale: "Same snapshot tactic as V-047."

**Concrete shape:** Identical to §4.C. The same `lootboxPoolSnapshotByIndex[index]` snapshot field covers both `openLootBox` and `openBurnieLootBox` manual-path entries because they share the same `index` keying and the same `_finalizeLootboxRng:1253` snapshot WRITE site. The READ-site modification in `_lootboxDgnrsReward:1770` applies uniformly to both dispatchers.

**Rationale for rejecting alternative tactics:** Identical to §4.C. Tactic (a) gated-revert breaks legitimate BURNIE-lootbox manual-path opens during rngLock; tactic (c) reorder is structurally impossible; tactic (d) immutable rejected on mutability grounds.

**Bytecode / storage-layout / public-ABI impact:** **Zero marginal cost beyond V-047.** Same snapshot field, same WRITE site, same READ site. The two violations share `D-43N-V44-HANDOFF-23` and `D-43N-V44-HANDOFF-24` as a unified fix surface in the v44.0 plan-phase. Storage delta = 0 marginal bytes; bytecode delta = 0 marginal bytes; runtime gas delta = 0 marginal gas.

**Reference precedent:** Same as V-047.

### §5.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-24`** — Same snapshot mechanism as `D-43N-V44-HANDOFF-23` covers the `openBurnieLootBox` manual-path race-class.

- Implementation cite: same as `D-43N-V44-HANDOFF-23` — `_finalizeLootboxRng:1253` snapshot WRITE, `LootboxModule.sol:1770` snapshot READ when entered from `openBurnieLootBox:607`.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 383 (V-048), §6 D-7.

---

## §6 — V-050: sDGNRS poolBalances[Lootbox] × `transferFromPool` from `resolveRedemptionLootbox` (sStonk claimRedemption reach)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 385 (V-050). §6 verdict-matrix row D-9 ("`dgnrs.poolBalances[Pool.Lootbox]` × `transferFromPool` (debit) reaching entry `claimRedemption` → this consumer. NO. **VIOLATION**.") §6 §E E-2 ("Snapshot pool balance at burn submission; pass as param into resolveRedemptionLootbox").

### §6.A — Design-intent backward-trace

**Slot introduction phase:** Same cluster preamble. The `resolveRedemptionLootbox` path is the sDGNRS-side claim-redemption flow: a player burns sDGNRS via `burn` (`:486`) or `burnWrapped`, which calls `_submitGamblingClaim` (`:493`) writing `pendingRedemptions[player]` with the activity score snapshotted at submission. After the period resolves (via `resolveRedemptionPeriod` invoked from advanceGame, catalog §12), the player calls `claimRedemption` (`:618`) which reads the resolved period's roll, splits the ETH 50/50 into direct + lootbox portions, then calls `game.resolveRedemptionLootbox(player, lootboxEth, entropy, actScore)` (`:672`). The Game-side `resolveRedemptionLootbox` (`DegenerusGame.sol:1721`) delegatecalls into the lootbox-module's redemption path, which reaches `_resolveLootboxCommon:960` → `_lootboxDgnrsReward:1770`.

**Commitment-window per catalog §6 trace:** The RNG commitment point for this consumer is "the moment the player initiates `claimRedemption` (because `rngWord` here is `rngWordByDay[claimPeriodIndex]` — a historical, publicly-readable VRF word the player has already observed)" (catalog §6 audit metadata). Every SLOAD reached during resolution that influences VRF-derived output is consumed AFTER the attacker knows the entropy, and is therefore a freshness-window participant unless structurally invariant against player-influenceable mutation. The catalog §6 §B B-9 attestation explicitly classifies `dgnrs.poolBalance(Lootbox)` SLOAD at `:1770` as a participating slot, and §6 §D D-9 classifies the writer reach via `claimRedemption` as VIOLATION.

**The activityScore snapshot precedent (load-bearing for the V-050 tactic shape):** The catalog §6 §E E-1 rationale explicitly notes that "The consumer ALREADY snapshots `activityScore` at burn submission (`StakedDegenerusStonk.sol:claim.activityScore` populated at submission, read at `:669` and passed as parameter to `resolveRedemptionLootbox` at `:672`)." This is the in-source precedent for the snapshot-at-burn-submission pattern; V-050 extends the same pattern to `poolBalances[Lootbox]`.

Concrete in-source confirmation: `StakedDegenerusStonk.sol:628` reads `claim.activityScore` (snapshotted at burn submission), `:669` adjusts for off-by-one (`uint16 actScore = claimActivityScore > 0 ? claimActivityScore - 1 : 0`), `:672` passes `actScore` as the 4th parameter to `game.resolveRedemptionLootbox`. The activityScore snapshot demonstrates the structural mechanism: `PendingRedemption` struct already has the snapshot field; adding `poolBalanceSnapshot` extends the struct by one `uint128`.

**Cite for "what would break if frozen":** Freezing `poolBalances[Lootbox]` during rngLock would block legitimate Lootbox-pool drains from advance-stack rebalances and concurrent lootbox-open flows. Gating `claimRedemption` on `rngLockedFlag` (tactic (a)) would also block legitimate player-recovery claims during the daily VRF cycle — an unacceptable user-visible regression for a recovery path. The catalog §6 §E explicitly rejects tactic (a) for this consumer: "tactic (a) `rngLockedFlag`-gated revert is rejected because `claimRedemption` is a player-recovery path that must succeed once the period roll is published; gating on `rngLockedFlag` would block legitimate claims while a day's RNG cycle is mid-flight."

### §6.B — Actor game-theory walk

**Exploit-actor class:** Player who has burned sDGNRS via `burn` / `burnWrapped` and is awaiting claim. Knowing `rngWord = rngWordByDay[claimPeriodIndex]` ahead of `claimRedemption`, the player computes whether the DGNRS-tier path will be taken (bits `[40..55] % 20 in [11, 13)`) AND whether the DGNRS-tier is mega (`tierRoll >= 995`, 0.5%) AND can manipulate `poolBalances[Lootbox]` via cross-call drains BEFORE calling `claimRedemption`.

**Action sequence during rngLock window (per catalog §6 D-9 analysis, verbatim load-bearing):**

- T0 (burn submission): Player calls `burn(amount)` or `burnWrapped(amount)`. `_submitGamblingClaim` writes `pendingRedemptions[player]` with `activityScore` snapshotted at submission. `pendingRedemptionEthValue` and `pendingRedemptionBurnie` are aggregated for the period.
- T1 (period resolve via advanceGame): `resolveRedemptionPeriod` (catalog §12) runs inside the advance-stack and writes `redemptionPeriods[period] = {roll, flipDay}`. From this point, the period's `roll` and `flipDay` are final and public.
- T2 (attacker observation): Player observes `rngWord = rngWordByDay[period]` (historical, publicly readable). Player computes the DGNRS-tier branch outcome ahead of T3.
- T3 (attacker move — pool manipulation): If the DGNRS-tier mega branch will be taken, attacker triggers sibling Lootbox-pool drains (other players' `openLootBox` calls or admin/operator flows that touch the pool) to either deflate or inflate the pool depending on attacker's payout-bias. Per catalog §6 §B B-9: "the attacker can pre-grind the pool (e.g., by triggering OTHER players' lootbox-resolution paths to drain or refill, or via admin/operator paths — Phase 300 ADMA scope) to maximize their share."
- T4 (consumer SLOAD): Player calls `claimRedemption`. Game-side `resolveRedemptionLootbox` reaches `_lootboxDgnrsReward:1770` which reads `dgnrs.poolBalance(Pool.Lootbox)`. Value reflects all pool-mutations between T1 and T4.
- T5 (payout): `dgnrsAmount = (poolBalance * ppm * amount) / (1_000_000 * 1 ether)`. Player receives the payout.

**EV magnitude estimate:** **MEDIUM-HIGH per-tx; CATASTROPHE-tier in the mega-tier arm.** Same magnitude class as V-047 but with one mitigating factor: the burn submission already snapshots `activityScore`, demonstrating that the surrounding code path is amenable to additional snapshots (lower implementation friction). The economic-likelihood disposition: **likely-exploited** in late-game where the Lootbox pool size has been deflated and the mega-tier arm represents a large fraction of remaining DGNRS supply. Catalog §0 headline reach analysis flags this as a top-tier concern alongside V-047 / V-048.

### §6.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) snapshot/anchor pattern.** Catalog §16 row 385 rationale: "Snapshot pool balance at burn submission; mirror activityScore snapshot" — direct application of the activityScore-snapshot precedent in the same `PendingRedemption` struct.

**Concrete shape:**

- Extend the `PendingRedemption` struct in `StakedDegenerusStonk.sol` to add `uint128 lootboxPoolSnapshot` (paired with the existing `activityScore` snapshot).
- At burn submission inside `_submitGamblingClaim`, populate `claim.lootboxPoolSnapshot = uint128(poolBalances[uint8(Pool.Lootbox)])` (or equivalent — the snapshot is taken at the entropy-commitment moment).
- At `claimRedemption:672`, pass the snapshot value as an ADDITIONAL parameter to `game.resolveRedemptionLootbox`. The signature becomes `resolveRedemptionLootbox(address player, uint256 amount, uint256 rngWord, uint16 activityScore, uint128 lootboxPoolSnapshot)`.
- Game-side `resolveRedemptionLootbox` (`DegenerusGame.sol:1721`) forwards the snapshot to the lootbox-module delegatecall payload, which reaches `_lootboxDgnrsReward:1770`. `_lootboxDgnrsReward` reads the snapshot parameter instead of the live `dgnrs.poolBalance(Pool.Lootbox)`.
- The `transferFromPool` debit at `:1786` continues to fire against the live pool balance; only the magnitude calculation uses the snapshot.

**Rationale for rejecting alternative tactics:**

- **(a) `rngLockedFlag`-gated revert** rejected per catalog §6 §E E-2: "claimRedemption is a player-recovery path that must succeed once the period roll is published; gating on rngLockedFlag would block legitimate claims while a day's RNG cycle is mid-flight."
- **(c) pre-lock reorder** rejected: the natural reorder point IS burn submission, which IS tactic (b).
- **(d) immutable** rejected on mutability grounds.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** `PendingRedemption` struct extended by `uint128 lootboxPoolSnapshot` — 16 bytes. Sibling fields are `ethValueOwed (uint128)`, `burnieOwed (uint128)`, `periodIndex (uint32)`, `activityScore (uint16)`. Adding a `uint128` may need a new storage slot depending on existing packing — v44 plan-phase determines exact layout. Storage delta = +16 bytes per active pending redemption.
- **Bytecode delta:** ~200-250 bytes. One additional SLOAD on `poolBalances[Lootbox]` at burn submission, one SSTORE on the new snapshot field, one calldata parameter added to `IDegenerusGame.resolveRedemptionLootbox` (interface change in `StakedDegenerusStonk.sol:38`), one SLOAD replaced by parameter read inside `_lootboxDgnrsReward`.
- **Net runtime gas:** approximately neutral or slightly positive (+1 SSTORE at burn time, -1 STATICCALL at resolve time).
- **Public ABI:** **CALLER-INTERFACE BREAKING for `IDegenerusGame.resolveRedemptionLootbox`** — the signature changes by adding a `uint128 lootboxPoolSnapshot` parameter. Since the caller is exclusively `StakedDegenerusStonk.claimRedemption` (verified by grep: `grep -rn "resolveRedemptionLootbox" contracts/`), the interface change is locally contained. **NON-BREAKING for downstream EOA consumers** since the function is `external` callable only by `ContractAddresses.SDGNRS` per the gate at `DegenerusGame.sol:1727`.
- **Reference precedent:** the in-struct `activityScore` snapshot in `PendingRedemption` is the direct in-source precedent. Phase 281 owed-salt snapshot is the load-bearing methodology precedent. Catalog §6 §E E-1 explicitly states "Mirrors Phase 288 dailyIdx structural-snapshot precedent and Phase 281 owed-salt 4th-keccak-input precedent."

### §6.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-25`** — Snapshot sDGNRS `poolBalances[Pool.Lootbox]` at burn submission inside `_submitGamblingClaim`; pass as parameter into `resolveRedemptionLootbox` alongside the existing `activityScore` snapshot. Concrete cites:

- Snapshot WRITE site: extend `_submitGamblingClaim` in `StakedDegenerusStonk.sol` (`:493` and surrounding) to write `claim.lootboxPoolSnapshot = uint128(poolBalances[uint8(Pool.Lootbox)])` alongside the existing activityScore write.
- Parameter passthrough: extend signature of `IDegenerusGame.resolveRedemptionLootbox` (interface in `StakedDegenerusStonk.sol:38`) and of `DegenerusGame.resolveRedemptionLootbox` (`:1721`) to include `uint128 lootboxPoolSnapshot`. Modify `claimRedemption:672` to pass the snapshot.
- Snapshot READ site: `_lootboxDgnrsReward` in `LootboxModule.sol:1770` reads the snapshot parameter instead of `dgnrs.poolBalance(Pool.Lootbox)` when entered from `resolveRedemptionLootbox`.
- Storage field: extend `PendingRedemption` struct in `StakedDegenerusStonk.sol`.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 385 (V-050), §6 §D D-9, §6 §E E-2.

---

## §7 — V-051: sDGNRS poolBalances[Lootbox] × `transferBetweenPools` (Lootbox-touching, mixed-callsite per-callsite split)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 386 (V-051). §15 writer enumeration row 175 (`transferBetweenPools` Lootbox-touching reached from JackpotModule / MintModule / GameOverModule). §6 verdict-matrix row D-10 ("`dgnrs.poolBalances[Pool.Lootbox]` × `StakedDegenerusStonk.transferBetweenPools` (any Lootbox-touching callsite) — Mixed — split per callsite in Phase 299 FIX sub-phase").

### §7.A — Design-intent backward-trace

**Slot introduction phase:** Same cluster preamble. `transferBetweenPools` (`StakedDegenerusStonk.sol:443-:458`) is the pool-rebalance primitive: it debits `poolBalances[fromIdx]` and credits `poolBalances[toIdx]` in a single call, gated by `onlyGame`. Per catalog §15 row 175, the Lootbox-touching callsites span multiple modules — JackpotModule / MintModule / GameOverModule rebalances reach into Lootbox-pool from various directions:

- **JackpotModule rebalances:** post-daily-payout consolidation moving residual ETH-derived sDGNRS from one pool tier to another (advance-stack — EXEMPT-ADVANCEGAME).
- **MintModule rebalances:** purchase-path side-effects that reallocate Lootbox-pool from / to other pools (potential EOA reach via `purchase` / `purchaseCoin` / `purchaseBurnieLootbox` entries).
- **GameOverModule rebalances:** game-over teardown phase rebalances (advance-stack — EXEMPT-VRFCALLBACK).

Per the catalog row 175 enumeration ("Lootbox-keyed rebalances"), the comprehensive callsite set is NOT enumerated at the catalog level — it is explicitly deferred to Phase 299 per row 386's "(b) Per-callsite Phase 299 split: admin paths tactic (a); advance-stack EXEMPT" rationale and per row 2072 D-10 "Mixed — split per callsite in Phase 299 FIX sub-phase".

**Per-callsite Phase 299 split (executor-authored disposition per the catalog directive):**

Following the directive in catalog row 386, V-051 is decomposed into THREE per-callsite classes:

| Class | Source-module callsites | Reach-stack | Per-callsite disposition |
|-------|-------------------------|-------------|--------------------------|
| V-051-AdvanceStack | JackpotModule `_consolidatePools` / GameOverModule `handleGameOverDrain` Lootbox-touching rebalances | advanceGame self-stack OR VRF-callback OR retryLootboxRng | **EXEMPT-ADVANCEGAME** / **EXEMPT-VRFCALLBACK** (per the EXEMPT-stack derivation in catalog rows 17-21, 27, 32, 42) — no fix required for this sub-class |
| V-051-MintPath | MintModule purchase-side rebalances (if any reach `transferBetweenPools(*, Pool.Lootbox)` from non-advanceGame `purchase` / `purchaseCoin` / `purchaseBurnieLootbox` entries) | EOA `purchase` (catalog row 22 confirms `purchase` has NO blanket `rngLockedFlag` revert) | **VIOLATION**; recommended tactic (a) gated-revert OR consolidated with catalog row 22 fix |
| V-051-AdminPath | hypothetical admin / operator Lootbox-pool rebalance (no current implementation exists per grep) | admin EOA | **VIOLATION** in the catalog's strict-discipline; recommended tactic (a) gated-revert at the admin caller IF such a writer is ever added |

**Grep verification for V-051-AdminPath:** `grep -n "transferBetweenPools" contracts/ -r --include="*.sol"` enumerates all callsites of the rebalance function. Per `feedback_verify_call_graph_against_source.md`, the per-callsite Phase 299 split MUST be derived from grep of the source, not assumed. The catalog row 386 directive ("admin paths tactic (a); advance-stack EXEMPT") implies admin paths exist, but the source-of-truth enumeration in §15 row 175 cites "JackpotModule / MintModule / GameOverModule Lootbox-keyed rebalances" only — no admin path in the current source. v44.0 plan-phase MUST grep-verify the callsite set BEFORE landing the fix.

**Cite for "what would break if frozen":** Freezing the Lootbox pool against `transferBetweenPools` during rngLock would block legitimate cross-pool rebalances from the advance-stack (which are themselves EXEMPT and do not need gating) AND from any non-advanceGame caller in the MintModule purchase-path (which is the V-051-MintPath sub-class and should be covered by the existing catalog row 22 gate on `MintModule.purchase` if it lands as part of the v44 plan-phase fix).

### §7.B — Actor game-theory walk

**Exploit-actor class (per sub-class):**

- **V-051-AdvanceStack:** No exploit surface — advance-stack callsites run inside `advanceGame()` / VRF-callback flows and inherit EXEMPT classification by `D-298-EXEMPT-REACH-01` strict-stack-rooted discipline.
- **V-051-MintPath:** Player triggering an EOA-callable purchase entry (`purchase` / `purchaseCoin` / `purchaseBurnieLootbox`) during the rngLock window, where the purchase has a Lootbox-pool rebalance side-effect. The attacker's lever is identical to V-047 / V-048 / V-050 but expressed through the rebalance writer rather than the direct debit writer. EV magnitude is bounded by the per-tx rebalance magnitude (typically a small fraction of the pool).
- **V-051-AdminPath:** Admin / operator (governance-trust class). Action sequence requires an admin / operator function that calls `transferBetweenPools(*, Pool.Lootbox, ...)` — no such function exists in the current source per grep, so this sub-class is structurally inactive in the deployed contract.

**Action sequence during rngLock window (sub-class V-051-MintPath):**

- T0: `advanceGame` enters daily-phase, requests VRF, sets `rngLockedFlag = true`.
- T1 (attacker move): Attacker calls `MintModule.purchase` (or sibling) which has a Lootbox-pool rebalance side-effect. Pool balance shifts by `±Δ`.
- T2 (consumer SLOAD): A pending Lootbox-pool consumer reads `dgnrs.poolBalance(Pool.Lootbox)` — depending on which consumer (V-047 manual-path, V-048 BurnieLootbox-path, V-050 sStonk-claim-path), the shift propagates into the payout magnitude.

**EV magnitude estimate (per sub-class):**

- **V-051-AdvanceStack: N/A** (EXEMPT, no exploit).
- **V-051-MintPath: LOW-MEDIUM per-tx** — bounded by the rebalance side-effect magnitude, which is typically a small fraction of the pool per purchase. Compounds with V-047 / V-048 / V-050 magnitudes when chained.
- **V-051-AdminPath: not applicable** (no admin writer exists in the current source).

Economic-likelihood disposition: **V-051-MintPath: possibly-exploited** when combined with V-047 / V-048 / V-050 in a multi-step pool-grinding sequence; the per-tx margin is small but the writer surface adds optionality. **V-051-AdvanceStack / V-051-AdminPath: non-exploitable** in the deployed contract.

### §7.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) Per-callsite Phase 299 split** — different tactic per sub-class:

- **V-051-AdvanceStack: NO FIX REQUIRED.** The callsites are EXEMPT-ADVANCEGAME / EXEMPT-VRFCALLBACK per the existing strict-discipline. The V-047 / V-048 / V-050 snapshot tactics already cure the consumer-side reads against these legitimate rebalances; the rebalances themselves do not need additional gating.
- **V-051-MintPath: covered by the catalog row 22 fix (tactic (a) gated-revert on `MintModule.purchase` / `purchaseCoin` / `purchaseBurnieLootbox`).** Catalog §1 §E row 22 already recommends "add top-level `if (rngLockedFlag) revert` to MintModule.purchase + purchaseCoin + purchaseBurnieLootbox" for the `prizePoolsPacked` (next/future) writes. The same gate atomically covers the V-051-MintPath sub-class — gating the purchase entries blocks BOTH the prizePoolsPacked writes AND any Lootbox-pool rebalance side-effects in those entries. No marginal fix is needed beyond the catalog row 22 implementation.
- **V-051-AdminPath: deferred** — no current writer exists. If a future v44.0 plan-phase introduces an admin writer of `transferBetweenPools(*, Pool.Lootbox, ...)`, the writer MUST be gated on `rngLockedFlag` at the admin caller. (Contracts are frozen at deploy per `feedback_frozen_contracts_no_future_proofing.md`, so this is a forward-looking attestation rather than an active fix requirement.)

**Rationale for rejecting alternative tactics:**

- **Uniform (b) snapshot/anchor** rejected: the rebalance writer mutates two slots simultaneously and is reached from multiple stacks; a per-callsite split is structurally cleaner than a single snapshot that would have to track both sides of the rebalance.
- **Uniform (a) gated-revert** rejected: advance-stack callsites are legitimately EXEMPT; gating them on `rngLockedFlag` would create a recursive lock (the advance-stack itself sets `rngLockedFlag`, so gating its own internal rebalance writers on `rngLockedFlag` would deadlock).
- **(c) pre-lock reorder** rejected: not applicable to a per-callsite class.
- **(d) immutable** rejected: pools must rebalance during normal operation.

**Bytecode / storage-layout / public-ABI impact:**

- **V-051-AdvanceStack:** 0 bytes, 0 gas — no fix.
- **V-051-MintPath:** 0 marginal bytes — fix is covered by catalog row 22 implementation (the gate on `purchase` / `purchaseCoin` / `purchaseBurnieLootbox`). Storage delta = 0; bytecode delta = ~30 bytes per entry for the `if (rngLockedFlag) revert RngLocked()` check (already counted in catalog row 22's impact).
- **V-051-AdminPath:** 0 bytes (no fix; deferred forward-attestation only).
- **Public ABI:** **NON-BREAKING** — no signature changes.
- **Reference precedent:** Catalog row 22 fix (`MintModule.purchase` rngLockedFlag gate) is the in-catalog precedent. `MintModule.sol:1221` existing partial gate `cachedJpFlag && rngLockedFlag` is the in-source pattern.

### §7.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-26`** — Per-callsite Phase 299 split for sDGNRS `poolBalances[Pool.Lootbox]` × `transferBetweenPools` (Lootbox-touching) writer class:

- **V-051-AdvanceStack:** NO FIX (EXEMPT). Attestation that v47 plan-phase grep-verifies the callsite set under `JackpotModule` / `GameOverModule` is exclusively advance-stack rooted.
- **V-051-MintPath:** subsumed by catalog row 22 `D-43N-V44-HANDOFF-NN` (see Cluster B / `prizePoolsPacked` Phase 299 cluster output for the row-22 handoff anchor identity).
- **V-051-AdminPath:** forward-attestation only — no fix in the v44.0 plan-phase, with an explicit grep-attestation that no admin / operator writer of `transferBetweenPools(*, Pool.Lootbox, ...)` exists in the v43.0 baseline source. Any future contract change introducing such a writer MUST land an `rngLockedFlag` gate per tactic (a).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 386 (V-051), §6 D-10, §15 row 175.

---

## Cluster D — summary attestations

| V-NNN | Slot | Writer-class | Tactic | EV-tier | Anchor |
|-------|------|--------------|--------|---------|--------|
| V-043 | poolBalances[Reward] | non-advanceGame GAME entries (claim/settlement/quest-reward/payCoinflipBountyDgnrs-from-COIN) | (b) snapshot-at-`_swapAndFreeze` | MEDIUM-HIGH (CATASTROPHE on final day) | `D-43N-V44-HANDOFF-20` |
| V-045 | poolBalances[Reward] | sDGNRS-internal admin / initial distribution | (b) same snapshot | LOW (governance) / catalog-discipline | `D-43N-V44-HANDOFF-21` |
| V-046 | poolBalances[Reward] | OZ-inherited ERC20 (the lone non-`contracts/` VIOLATION; fix lands IN `contracts/`) | (b) same snapshot | LOW (consumer-disambiguated) / catalog-discipline | `D-43N-V44-HANDOFF-22` |
| V-047 | poolBalances[Lootbox] | `transferFromPool` from `openLootBox` (manual EOA) | (b) snapshot-at-`_finalizeLootboxRng` (per-index) | HIGH (CATASTROPHE in mega-tier) | `D-43N-V44-HANDOFF-23` |
| V-048 | poolBalances[Lootbox] | `transferFromPool` from `openBurnieLootBox` (manual EOA, sibling) | (b) same snapshot | HIGH (CATASTROPHE in mega-tier) | `D-43N-V44-HANDOFF-24` |
| V-050 | poolBalances[Lootbox] | `transferFromPool` from `resolveRedemptionLootbox` (sStonk claimRedemption reach) | (b) snapshot-at-burn-submission (mirror activityScore) | MEDIUM-HIGH (CATASTROPHE in mega-tier) | `D-43N-V44-HANDOFF-25` |
| V-051 | poolBalances[Lootbox] | `transferBetweenPools` (mixed-callsite, per-callsite split) | (b) per-callsite split: AdvanceStack=EXEMPT, MintPath=subsumed-by-row-22 (a), AdminPath=forward-only | LOW-MEDIUM in MintPath; N/A elsewhere | `D-43N-V44-HANDOFF-26` |

**Tactic mix:** 7 / 7 select tactic (b) snapshot/anchor (with V-051 carrying a per-callsite mix that includes one tactic-(a) cross-reference to catalog row 22 for the MintPath sub-class). Zero tactic (a) standalone, zero tactic (c) pre-lock reorder, zero tactic (d) immutable.

**EV-tier distribution:** HIGH/CATASTROPHE-tier in 4 entries (V-043 final-day, V-047, V-048, V-050 mega-tier). MEDIUM-HIGH-tier in 1 entry (V-043 non-final-day baseline). LOW / catalog-discipline-tier in 3 entries (V-045, V-046 consumer-disambiguated, V-051 per-callsite splits).

**v44.0 handoff anchor count:** 7 — `D-43N-V44-HANDOFF-20` through `D-43N-V44-HANDOFF-26`. Three of the seven (V-043 / V-045 / V-046) share a single Reward-pool snapshot field (`dgnrsRewardPoolSnapshot` at `_swapAndFreeze`). Two of the seven (V-047 / V-048) share a single per-index Lootbox-pool snapshot mapping (`lootboxPoolSnapshotByIndex[index]` at `_finalizeLootboxRng`). V-050 carries its own per-redemption snapshot (extends the `PendingRedemption` struct alongside the existing `activityScore` snapshot). V-051 is per-callsite split with one MintPath sub-class subsumed by the catalog row 22 fix.

**V-046 OZ disposition:** V-046 is the lone Cluster-D VIOLATION whose writer source-of-record lives outside `contracts/` (in `node_modules/@openzeppelin/`). The fix MUST land in `contracts/` per `D-298-OZ-CARVEOUT-01`; the tactic (b) snapshot-at-`_swapAndFreeze` lands the fix on the CONSUMER's read inside `contracts/modules/DegenerusGameJackpotModule.sol` and `contracts/modules/DegenerusGameAdvanceModule.sol`, never on the OZ source. Source-of-truth refinement: sDGNRS itself does not actually inherit OZ ERC20 (custom in-contract ERC20 implementation), but the V-046 row captures the OZ-inherited writer class generically for the contract suite per `D-298-OZ-CARVEOUT-01` carve-out rule.

**Source-tree mutation count:** 0 (`contracts/`) + 0 (`test/`). Audit-only posture per `D-43N-AUDIT-ONLY-01`.

**SAFE_BY_DESIGN tokens:** zero — strict-discipline per `D-43N-AUDIT-ONLY-01`.

**Cross-references to other Phase 299 FIXREC cluster outputs:** V-051-MintPath sub-class is subsumed by catalog row 22's handoff anchor (Cluster B / `prizePoolsPacked` family — see sibling Phase 299 FIXREC cluster output for the row-22 anchor identity). All other Cluster D entries are self-contained within this file.

---

*Phase: 299-Fix-Recommendation-Document-FIXREC, Plan 04 — Cluster D (sDGNRS cross-contract pool balances)*
*Drafted: 2026-05-18*
