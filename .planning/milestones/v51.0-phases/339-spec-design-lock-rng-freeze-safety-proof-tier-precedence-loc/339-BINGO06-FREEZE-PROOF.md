# 339 — BINGO-06 RNG-Freeze-Safety Proof (claimBingo)

**Phase:** 339 — SPEC design-lock (claimBingo / v51.0)
**Requirement:** BINGO-06 (PROVE, do not assume, the RNG-freeze safety of the `claimBingo` `traitBurnTicket` read).
**Method:** Structured per-slot enumeration (per **D-04**) — every storage slot `claimBingo` touches is classified into exactly one of three classes and each is shown NOT to be a current-VRF-window output slot during `rngLock`.
**Tree:** All `file:line` anchors grep-attested against the live tree at HEAD `743c20ae`. `git diff 812abeee HEAD -- contracts/` is **EMPTY** (the only commits since the v50.0-closure HEAD `812abeee` are v51 planning docs) → **grepping at HEAD == grepping at `812abeee`** for `contracts/` (D-13).
**Companion:** `339-TRAITBURNTICKET-SOUNDNESS-ATTESTATION.md` carries the write-site proof of the IFF invariant that this freeze proof depends on (the "populated-only-after-level-L-resolution" claim).

---

## VERDICT: **FREEZE-SAFE**

`claimBingo` touches **no current-VRF-window output slot during `rngLock`**. It adds **NO** write to `traitBurnTicket` (it is a strict read-only consumer of the post-RNG-resolution map), it writes only three freshly-appended bitfields that no VRF-influenced path reads or writes, and its reads consume only post-resolution / non-VRF-derived state. The `v45-vrf-freeze-invariant` is re-attested **by name** below for the `traitBurnTicket` read.

---

## The RNG-freeze window (what "during `rngLock`" means)

The freeze window is bounded by `rngLockedFlag` (`contracts/storage/DegenerusGameStorage.sol:279`, `bool internal rngLockedFlag`):

- **SET** `rngLockedFlag = true` at `contracts/modules/DegenerusGameAdvanceModule.sol:1640` (request → daily RNG lock open).
- **HELD** `true` while a daily is in flight (`AdvanceModule.sol:1697`).
- **CLEAR** `rngLockedFlag = false` at `contracts/modules/DegenerusGameAdvanceModule.sol:1721` (post-resolution unlock).

The structural freeze guard that the codebase already enforces for player-reachable writes is at `contracts/storage/DegenerusGameStorage.sol:573`:

```
if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked();   // isFarFuture := lvl > currentLevel + 5
```

The `v45-vrf-freeze-invariant` (memory): *every variable interacting with a VRF word must be frozen for the duration [request → unlock] with respect to players; a read must consume post-resolution state, not state buffered-for-next.* The proof below shows `claimBingo` interacts with **no** such variable inside the locked window.

---

## Per-slot classification TABLE (D-04 — every slot `claimBingo` touches)

| # | Slot / call | Class | Anchor (live tree) | VRF-window output during `rngLock`? | Why |
|---|---|---|---|---|---|
| 1 | `bingoClaimed[level][msg.sender]` (per-player `uint8`) | **(i) NEW write** | `DegenerusGameStorage.sol` append (D-05; new mapping) | **NO** | Brand-new slot appended to the shared delegatecall layout; read/written by `claimBingo` ONLY; no VRF path touches it. |
| 2 | `firstQuadrant[level]` (systemwide `uint8`) | **(i) NEW write** | `DegenerusGameStorage.sol` append (D-05; new mapping) | **NO** | Brand-new slot; written by `claimBingo` ONLY; no VRF path touches it. |
| 3 | `firstSymbol[level]` (systemwide `uint32`) | **(i) NEW write** | `DegenerusGameStorage.sol` append (D-05; new mapping) | **NO** | Brand-new slot; written by `claimBingo` ONLY; no VRF path touches it. |
| 4 | `traitBurnTicket[level][traitId][slots[c]]` for `c ∈ [0,7]` (resolved `address[]`) | **(ii) post-resolution READ** | `DegenerusGameStorage.sol:416` (decl) | **NO** | Populated **only after** level-`level` traits are RNG-resolved (see §"Populated-only-after-level-L-resolution"). `claimBingo` reads it; it does **NOT** write it. The read consumes post-resolution data, not buffered-for-next. |
| 5 | `level` (the "current level"; `uint24 public level`) | **(ii) post-resolution READ** | `DegenerusGameStorage.sol:245` (decl `uint24 public level = 0;`) | **NO** | A monotone game counter advanced by `advanceGame`; read in the `require(level <= currentLevel)` gate. Not a VRF-derived current-window output; it is the freeze-window **boundary input**, not an output. |
| 6 | `gameOver` (`bool public gameOver`) | **(ii) post-resolution READ** | `DegenerusGameStorage.sol:285` | **NO** | Terminal-state flag, read by the `require(!gameOver)` hard-cutoff gate. Not VRF-derived. |
| 7 | `poolBalance(Pool.Reward)` (sDGNRS reward pool balance) | **(ii) post-resolution READ** (external `view`) | `StakedDegenerusStonk.sol:464` (`function poolBalance(Pool) external view returns (uint256)`) | **NO** | A staking-contract pool balance in `StakedDegenerusStonk`, not in the game's VRF window at all; read to size the sDGNRS draw. |
| 8 | `sdgnrs.transferFromPool(Pool.Reward, msg.sender, amt)` | **(iii) external reward CALL** | `StakedDegenerusStonk.sol:485` (`external onlyGame returns (uint256 transferred)`, clamped) | **NO** | Moves sDGNRS out of the staking-contract reward pool; clamped-return idiom (`if (amount > available) amount = available;` at `:491-493`, `if (available == 0) return 0;` at `:490`). Touches no VRF-derived current-window output. |
| 9 | `coinflip.creditFlip(msg.sender, burnieReward)` | **(iii) external reward CALL** | (BURNIE flip-credit path; same as `DegenerusGameMintModule.sol:1319` / autoBuy bounty) | **NO** | Credits uncapped-emission BURNIE flip credit in the coinflip contract; no VRF-derived current-window output. |

**Conclusion of the table:** every touched slot falls into class (i), (ii), or (iii); **none** is a current-VRF-window output slot during `rngLock`.

---

## Class (i) — the three NEW bitfield WRITES (`bingoClaimed`, `firstQuadrant`, `firstSymbol`)

These are the only writes `claimBingo` performs. All three are **brand-new mappings appended to `DegenerusGameStorage.sol`** (D-05 / D-10 — shared delegatecall layout; pre-launch redeploy-fresh, so appending needs no migration):

- `mapping(uint24 => mapping(address => uint8)) bingoClaimed;` — per-player, 4 quadrant bits used.
- `mapping(uint24 => uint8) firstQuadrant;` — systemwide, 4 quadrant bits used.
- `mapping(uint24 => uint32) firstSymbol;` — systemwide, 32 symbol bits used.

**Freeze argument:** because these slots are newly introduced by this very milestone, **no pre-existing VRF-consuming or VRF-producing path reads or writes them** — there is nothing in the daily RNG pipeline (`AdvanceModule` request/fulfil, trait resolution in `MintModule`, jackpot winner selection in `JackpotModule`) that touches `bingoClaimed`/`firstQuadrant`/`firstSymbol`. A VRF word never flows into nor out of these slots. They are pure `claimBingo` bookkeeping (the dedup bit + the two systemwide-first bits). They therefore cannot be a "current-VRF-window output slot" by construction-of-novelty, and — unlike a "by construction" hand-wave on EXISTING storage — this is verifiable by grep: the new identifiers appear nowhere else in `contracts/` (they do not yet exist at HEAD; at IMPL 340 the verifier must confirm the only readers/writers are `claimBingo`).

---

## Class (ii) — the post-resolution READS

### 1. `traitBurnTicket[level][traitId][slots[c]]` — the load-bearing read

This is the one read that interacts with RNG-derived data, so it gets the rigorous treatment.

- **Declaration:** `contracts/storage/DegenerusGameStorage.sol:416` — `mapping(uint24 => address[][256]) internal traitBurnTicket;` (the `uint24` level key; the inner `address[][256]` is `traitId → address[]`, `traitId` fitting the 256 fixed slots, inner array dynamic).
- **What `claimBingo` does with it:** for each color `c ∈ [0,7]` of the requested symbol, it computes `traitId = (quadrant << 6) | (c << 3) | symInQ` and asserts `traitBurnTicket[level][traitId][slots[c]] == msg.sender` (Validation sketch, plan doc :101-105). This is a **read** — an `address` SLOAD plus an equality check.
- **`claimBingo` adds NO write to `traitBurnTicket`.** It is a strict **read-only consumer**. The append/population of `traitBurnTicket` happens elsewhere, entirely outside `claimBingo` (the sole write-site is proven in the companion doc; see §"Populated-only-after-level-L-resolution").

#### Populated-only-after-level-L-resolution invariant (attested)

The entry `traitBurnTicket[L][traitId][i]` for a level `L` is populated **only after** level-`L` traits are RNG-resolved. The mechanism (proven in full in `339-TRAITBURNTICKET-SOUNDNESS-ATTESTATION.md`):

- The **sole** population site is the inline-assembly batch-append in `contracts/modules/DegenerusGameMintModule.sol:603-643`. It runs inside ticket processing, which derives each `traitId` from the resolved VRF entropy word (`DegenerusTraitUtils.traitFromWord(s)` at `MintModule.sol:586`, where `s` is seeded from the per-batch `entropyWord`, `MintModule.sol:572-575`). The trait byte does not exist until that resolution has occurred — so the address cannot be appended under a `traitId` until that level's RNG has been consumed.
- Trait-byte layout `[QQ][CCC][SSS]` (Q bits 7-6, C bits 5-3, S bits 2-0) is confirmed at `contracts/DegenerusTraitUtils.sol:17-39` → the read target IS the resolved trait byte.
- The existing jackpot path **reads** `traitBurnTicket` only post-resolution (the jackpot winner-selection reads at `DegenerusGameJackpotModule.sol:654/886/936/1173/1257/1554/1696` are all on already-resolved buckets) — corroborating that the map is a settled, post-resolution artifact by the time anything consumes it.

Because `claimBingo` requires `level <= currentLevel` (the `level` gate, slot #5), the only buckets it can read are at or below the current level — i.e. levels whose traits are already RNG-resolved. It cannot index a future-level bucket whose RNG is still in flight.

#### `v45-vrf-freeze-invariant` — re-attested BY NAME for the read

Per **`v45-vrf-freeze-invariant`**: *every variable interacting with a VRF word must be frozen [request → unlock] with respect to players; the read must consume post-resolution data, not buffered-for-next.*

- `claimBingo`'s `traitBurnTicket` read **consumes post-resolution data**: the bucket is fully written at trait-resolution time (`MintModule.sol:603-643`), which has completed for any `level <= currentLevel`. It is NOT reading a slot that the *current* VRF word is about to write — that slot does not yet hold the data, and `claimBingo` cannot reach a future-level bucket (the `level <= currentLevel` gate).
- `claimBingo` **mutates no variable that interacts with a current VRF word** inside the locked window: its only writes are the three NEW class-(i) bitfields, which no VRF path reads. It does not write `traitBurnTicket`, `level`, `gameOver`, the prize pools, or any entropy/seed slot.
- Therefore the invariant holds: no VRF-interacting variable is read-while-being-written or mutated-while-frozen by `claimBingo`. The race-start semantics below pin exactly when the read first becomes safe.

### 2. `level` (the "current level")
Read in `require(level <= currentLevel)` (plan doc :91). `uint24 public level` declared at `DegenerusGameStorage.sol:245`; advanced by `advanceGame`. It is the freeze-window **boundary input** (the thing that gates which buckets are even addressable), not a VRF-window output that `claimBingo` could corrupt. Read-only here.

### 3. `gameOver`
Read in `require(!gameOver)` (plan doc :90) — the hard cutoff. `bool public gameOver` at `DegenerusGameStorage.sol:285`. Terminal flag, not VRF-derived. Read-only here.

### 4. `poolBalance(Pool.Reward)`
Read to size the sDGNRS draw (`uint256 poolBal = sdgnrs.poolBalance(Pool.Reward)`, plan doc :135). `function poolBalance(Pool pool) external view returns (uint256)` at `StakedDegenerusStonk.sol:464` (returns `poolBalances[_poolIndex(pool)]`). This lives in the **staking contract**, not the game's RNG window; it is not a VRF-derived current-window output. Read-only here.

---

## Class (iii) — the external reward CALLS

### 1. `transferFromPool` (sDGNRS draw)
`function transferFromPool(Pool pool, address to, uint256 amount) external onlyGame returns (uint256 transferred)` at `StakedDegenerusStonk.sol:485`. Confirmed: `onlyGame` modifier (game-only authorization) + the clamped-return idiom — `if (amount == 0) return 0;` (`:486`), `if (available == 0) return 0;` (`:490`), `if (amount > available) amount = available;` (`:491-493`). `claimBingo` uses the clamped return as `dgnrsPaid`, so an empty/short pool is a graceful no-op (claim+first bits still set, BURNIE still paid) — D-08. This call moves sDGNRS in the staking contract; it touches **no** VRF-derived current-window output.

### 2. `coinflip.creditFlip` (BURNIE flip credit)
`coinflip.creditFlip(msg.sender, burnieReward)` — the uncapped-emission BURNIE flip-credit path, identical to the model at `DegenerusGameMintModule.sol:1319` (and the autoBuy bounty / affiliate-kickback path). Always paid (even on empty Reward pool). Credits BURNIE in the coinflip contract; touches **no** VRF-derived current-window output and introduces no new inflation surface beyond the already-audited flip-credit emission.

---

## Race-start semantics (LOCKED, per D-03)

A `(level, symbol)` becomes claimable the **moment level-`level` entry traits are RNG-resolved** — i.e. when the game's level counter advances such that those traits are settled in `traitBurnTicket`. This is the exact instant the post-resolution-read invariant first holds for that level; before it, the bucket is empty/unpopulated and the `traitBurnTicket[level][traitId][slots[c]] == msg.sender` check cannot pass (and `level <= currentLevel` would gate a too-early call). The whale-frontrunning race on that per-VRF-reveal resolution batch is enshrined as an ACCEPTED-BY-DESIGN non-finding in `339-TRAITBURNTICKET-SOUNDNESS-ATTESTATION.md` (D-03).

---

## Anchor-attestation note (D-13 — grep-attested drift correction)

While grep-attesting the cited anchors against HEAD (`743c20ae` ≡ `812abeee` for `contracts/`), the population/write-site of `traitBurnTicket` was traced to its **true** location for the purposes of this proof. The plan and CONTEXT D-02 cite `DegenerusGame.sol:2701/2730/2813` and `DegenerusGameJackpotModule.sol:654` as "write-sites"; on source inspection **those four anchors are READ-side** (`:2701` `sampleTraitTickets` / `:2730` `sampleTraitTicketsAtLevel` / `:2813` `getTickets` are all `view`; `:654` is a jackpot bucket reader). The **sole population/append (write) site is `DegenerusGameMintModule.sol:603-643`** (inline-assembly batch append, keyed by the RNG-resolved `traitId`). This freeze proof relies on the corrected write-site for the post-resolution invariant; the full corrected enumeration and its consequence for soundness are recorded in the companion attestation. The correction does NOT weaken the freeze verdict — it strengthens it: the populate-only-after-resolution claim is anchored to the actual writer, not assumed from a read-side citation.

---

## Summary

| Class | Slots | Freeze disposition |
|---|---|---|
| (i) NEW write | `bingoClaimed`, `firstQuadrant`, `firstSymbol` | Brand-new; no VRF path reads/writes them. |
| (ii) post-resolution READ | `traitBurnTicket[level][traitId][slots[c]]`, `level`, `gameOver`, `poolBalance(Pool.Reward)` | Consume only settled/non-VRF state; `traitBurnTicket` read is post-resolution and `claimBingo` adds NO write to it. |
| (iii) external reward CALL | `transferFromPool` (`:485`, clamped/`onlyGame`), `coinflip.creditFlip` | Touch sDGNRS pool + BURNIE flip credit; neither a VRF-derived current-window output. |

**`claimBingo` is FREEZE-SAFE.** `v45-vrf-freeze-invariant` is preserved and re-attested by name for the `traitBurnTicket` read. No touched slot is a current-VRF-window output slot during `rngLock`.
