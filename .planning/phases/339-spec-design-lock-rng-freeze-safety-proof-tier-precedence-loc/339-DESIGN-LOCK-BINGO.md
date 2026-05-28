# Phase 339 — claimBingo BINGO Design-Lock (SC1 / BATCH-01)

**Status:** LOCKED · **Gathered:** 2026-05-28 · **Audit subject HEAD:** `812abeee` (≡ current HEAD `832e9a72` for `contracts/` — `git diff 812abeee HEAD -- contracts/` is EMPTY)

This is the SETTLED design of the `claimBingo` color-completion entrypoint. The economics are LOCKED in `.planning/PLAN-V51-CLAIMBINGO-COLOR-COMPLETION.md` and `339-CONTEXT.md` (D-01/D-05/D-07/D-08/D-09/D-10) — this document **transcribes** them into the binding IMPL acceptance contract for Phase 340. It does **not** re-derive or re-litigate any settled number. The tier-selection logic lives in its companion: `339-TIER-PRECEDENCE-ACCEPTANCE-CONTRACT.md`.

All cited `file:line` anchors were grep-attested against the live tree (≡ `812abeee` for `contracts/`) at execution start.

---

## 1. Function Signature (D-01) — LOCKED

```
claimBingo(uint256 level, uint8 symbol, uint32[8] calldata slots)
```

- `slots` is **`uint32[8]`**, NOT `uint256[8]`. Each `slots[c]` (`c ∈ [0,7]`) names a position the caller occupies inside the dynamic inner `address[]` of `traitBurnTicket[level][traitId]` (see §3 for the `traitId` derivation per color `c`).
- `symbol` is `uint8`; the entrypoint validates `symbol < 32` (32 symbols = 4 quadrants × 8 symbols-in-quadrant). `quadrant = symbol >> 3` (∈ [0,3]); `symInQ = symbol & 7` (∈ [0,7]).
- `level` is widened to `uint256` in the external signature for ABI convenience but is **keyed internally as `uint24`** (see §2) — it matches the existing `traitBurnTicket` key width. The entrypoint validates `level <= currentLevel` and `!gameOver`.

### 1a. uint32 slot-width DISPOSITION (D-01 — written, not silent)

The `uint32` cap on each `slots[c]` admits up to **4,294,967,295 (~4.29B)** distinct array positions per `(level, traitId)`. This cap is **UNREACHABLE** and is therefore a **non-issue** — recorded here as a written audit disposition rather than left to silence:

- A `slots[c]` value can only validly index an `address[]` that the writer (`MintModule:603-643`, see §3) actually grew to that length. To make `slots[c]` overflow `uint32`, a single `(level, traitId)` bucket would need **more than 4 billion appended entries** — i.e. 4 billion RNG-resolved ticket entries carrying **one specific trait byte** `[QQ][CCC][SSS]` on **one specific level**. That is not reachable under any realistic (or even adversarial-but-bounded) ticket volume; the per-level entry supply is bounded far below `2^32` by the array-growth note at `DegenerusGameStorage.sol:415` ("Array growth bounded by total ticket supply per level").
- `uint32[8] calldata` is also the cheaper calldata choice (256 bytes of slot indices vs 256 bytes were it `uint256[8]`… `uint32[8]` packs to 32 bytes of meaningful data), and the IMPL reads `slots[c]` as an array index, so a narrower type is strictly safer and cheaper. The cap is stated so the deferred v52 audit has an explicit disposition: **slot-width overflow is structurally unreachable.**

---

## 2. Storage Shape (D-05 / D-07 / D-10) — LOCKED

The three new mappings are **appended to the SHARED `contracts/storage/DegenerusGameStorage.sol` layout**, NOT declared inside `DegenerusGameBingoModule.sol`. This is mandatory: the delegatecall module architecture (§4) means every module executes against `DegenerusGame`'s storage, so any state `claimBingo` reads/writes MUST live in the shared storage contract. Pre-launch redeploy-fresh (`feedback_frozen_contracts_no_future_proofing`) → **appending new slots at the tail is safe, no migration**.

| Mapping | Type | Scope | Bits used | Key |
|---------|------|-------|-----------|-----|
| `bingoClaimed` | `mapping(uint24 => mapping(address => uint8))` | per-player | 4 (quadrant mask) | `[level][msg.sender]` |
| `firstQuadrant` | `mapping(uint24 => uint8)` | systemwide | 4 (quadrant mask) | `[level]` |
| `firstSymbol` | `mapping(uint24 => uint32)` | systemwide | 32 (one bit per symbol 0–31) | `[level]` |

- **The `uint24` level key is the precedent set by `traitBurnTicket`.** `contracts/storage/DegenerusGameStorage.sol:416` declares `mapping(uint24 => address[][256]) internal traitBurnTicket;` (the `:404-416` comment block documents the `level → traitId(0-255) → address[]` shape and the "array growth bounded by total ticket supply per level" guarantee). The three new mappings adopt the **identical `uint24` level key** so the dedup/first bits index the same level domain the `traitBurnTicket` read uses — no key-width mismatch, no silent truncation.
- `bingoClaimed[level][msg.sender]` uses a **4-bit quadrant mask** (`qMask = 1 << quadrant`, quadrant ∈ [0,3]) → at most **4 claims per player per level** (one per quadrant). See D-07 / §6.
- `firstQuadrant[level]` is a **systemwide 4-bit mask** → at most **4 quadrant-firsts per level** (one per quadrant).
- `firstSymbol[level]` is a **systemwide 32-bit mask** (`sMask = 1 << symbol`, symbol ∈ [0,31]) → at most **32 symbol-firsts per level** (one per symbol).

These three mappings are **claimBingo-exclusive** — the only writer/reader of `bingoClaimed` / `firstQuadrant` / `firstSymbol` is `claimBingo` (the IMPL verifier should confirm no other code path touches them, per the 339-01 next-phase note).

---

## 3. traitId Derivation (D-09) — LOCKED

For each color `c ∈ [0,7]` of the requested `symbol`, the entrypoint computes the 8-bit trait byte and reads `traitBurnTicket[level][traitId][slots[c]]`, requiring it to equal `msg.sender`:

```
quadrant = symbol >> 3            // bits 7-6 of the trait byte (∈ [0,3])
symInQ   = symbol & 7             // bits 2-0 of the trait byte (∈ [0,7])
traitId  = (quadrant << 6) | (c << 3) | symInQ     // for each color c ∈ [0,7]
```

The trait byte layout is `[QQ][CCC][SSS]` — Q in bits 7-6, C (color) in bits 5-3, S (symbol-in-quadrant) in bits 2-0 — confirmed at **`contracts/DegenerusTraitUtils.sol:17-39`** (the "TRAIT ID STRUCTURE" block: "Bits 7-6: Quadrant", "Bits 5-3: Color tier", "Bits 2-0: Symbol", "Format: `[QQ][CCC][SSS]` = 8 bits").

**Duplicate-slot griefing is IMPOSSIBLE.** Each trait byte encodes exactly one `(quadrant, color, symbol)` triple. A valid bingo requires one owned entry in **each of the 8 distinct color buckets** `c = 0..7` of the same `(quadrant, symInQ)` — i.e. 8 distinct `traitId` values that differ only in their color bits. A caller cannot satisfy two colors with one slot: the 8 reads target 8 different `address[]` arrays. (The soundness of "address at `traitBurnTicket[level][traitId][slot]` ⟺ owned a post-RNG-resolved entry of that exact trait byte" is the IFF theorem proved in `339-TRAITBURNTICKET-SOUNDNESS-ATTESTATION.md`; the sole populating writer is `DegenerusGameMintModule.sol:603-643`, keyed by the RNG-resolved `traitId` at `:586-587` — NOT the read-side anchors `DegenerusGame.sol:2701/2730/2813` or `JackpotModule:654` per the D-13 correction in 339-01.)

---

## 4. Module Placement + Delegatecall Wiring (D-10) — LOCKED

- **New module file:** `contracts/modules/DegenerusGameBingoModule.sol` (all 8 existing `GAME_*_MODULE`s live in `contracts/modules/`; the bingo module joins them).
- **New entrypoint in `DegenerusGame.sol`:** a new external `claimBingo(uint256 level, uint8 symbol, uint32[8] calldata slots)` that delegatecalls `ContractAddresses.GAME_BINGO_MODULE`, following the established dispatch shape. The copy-paste reference is the `advanceGame()` entrypoint at **`DegenerusGame.sol:278-288`** (`ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(abi.encodeWithSelector(...)); if (!ok) _revertDelegate(data);`) and the `purchase`/`purchaseCoin` entrypoints at **`DegenerusGame.sol:520-532` / `:545-554`** (`ContractAddresses.GAME_MINT_MODULE.delegatecall(...)`). claimBingo mirrors this: encode `IDegenerusGame*.claimBingo.selector` with the three args, delegatecall `GAME_BINGO_MODULE`, `_revertDelegate(data)` on failure.
- **New address constant:** add `GAME_BINGO_MODULE` to `contracts/ContractAddresses.sol` alongside the existing `GAME_MINT_MODULE` (`:13`), `GAME_ADVANCE_MODULE` (`:15`), `GAME_WHALE_MODULE` (`:17`), `GAME_JACKPOT_MODULE` (`:19`), `GAME_DECIMATOR_MODULE` (`:21`), `GAME_ENDGAME_MODULE` (`:23`), `GAME_GAMEOVER_MODULE` (`:25`), `GAME_LOOTBOX_MODULE` (`:27`), `GAME_BOON_MODULE` (`:29`), `GAME_DEGENERETTE_MODULE` (`:31`). `ContractAddresses.sol` is **freely modifiable** per `feedback_contractaddresses_policy`.
- **Interface:** the relevant `DegenerusGame` interface (`IDegenerusGame` or equivalent) gains the `claimBingo(uint256, uint8, uint32[8])` signature, plus a new `IDegenerusGameBingoModule` interface declaring the module-side `claimBingo` selector the delegatecall encodes.

---

## 5. Reward Constants (D-05) — TRANSCRIBED VERBATIM

| Constant | Value | Percent of `Pool.Reward` | Semantics |
|----------|-------|--------------------------|-----------|
| `REGULAR_DGNRS_BPS` | `5` | 0.05% | baseline sDGNRS draw |
| `FIRST_SYMBOL_BONUS_DGNRS_BPS` | `5` | +0.05% | **ADDED** to regular (→ 0.1% total for symbol-first) |
| `FIRST_QUADRANT_DGNRS_BPS` | `50` | 0.5% | **REPLACEMENT** (supersedes regular + symbol bonus) |
| `REGULAR_BURNIE` | `1_000e18` | — | baseline BURNIE flip credit |
| `FIRST_SYMBOL_BONUS_BURNIE` | `1_000e18` | — | **ADDED** to regular (→ 2 000e18 total for symbol-first) |
| `FIRST_QUADRANT_BURNIE` | `5_000e18` | — | **REPLACES** regular + symbol bonus |

- **Regular tier:** 0.05% `Pool.Reward` + 1 000 BURNIE (`REGULAR_DGNRS_BPS=5` + `REGULAR_BURNIE=1_000e18`).
- **Symbol-first tier (ADDITIVE):** 0.05% + 0.05% = **0.1%** + 1 000 + 1 000 = **2 000 BURNIE** (regular + the symbol-first bonus).
- **Quadrant-first tier (REPLACEMENT):** **0.5%** `Pool.Reward` + **5 000 BURNIE** — non-additive; it does NOT stack on the regular/symbol amounts, it replaces them (and suppresses the symbol-first bonus per the tier-precedence rule). See `339-TIER-PRECEDENCE-ACCEPTANCE-CONTRACT.md`.

These are the SETTLED numbers — IMPL transcribes them as named constants in `DegenerusGameBingoModule.sol`; it does NOT recompute or re-tune them.

---

## 6. Reward Paths + Dedup + No-Op + Cutoff (D-07 / D-08) — LOCKED

### 6a. sDGNRS draw (D-08)

sDGNRS reward paid via:

```
sdgnrs.transferFromPool(IStakedDegenerusStonk.Pool.Reward, msg.sender, (poolBal * bps) / 10_000)
```

where `bps` is the selected tier's DGNRS bps (5 / 10 / 50) and `poolBal` is the current `Pool.Reward` balance. The function uses the **clamped return value** as `dgnrsPaid` — `transferFromPool` returns the amount actually transferred (clamped to the available pool), so **no manual clamp is needed**. Reference pattern: `_awardDegeneretteDgnrs` at `contracts/modules/DegenerusGameDegeneretteModule.sol:1135-1159`.

### 6b. BURNIE flip credit (D-08)

BURNIE reward paid via:

```
coinflip.creditFlip(msg.sender, amount)
```

where `amount` is the selected tier's BURNIE (1 000 / 2 000 / 5 000 e18). Reference pattern: `contracts/modules/DegenerusGameMintModule.sol:1319` (uncapped emission, same flip-credit path as the autoBuy bounty / affiliate kickback → no new inflation surface).

### 6c. Empty / 0-amount pool = GRACEFUL NO-OP (D-08)

If `Pool.Reward` is empty (or the computed draw is 0): the claim is NOT reverted. The claim bits + first bits are STILL set, the BURNIE flip credit is STILL paid, and `dgnrsPaid == 0`. This matches the Degenerette + coinflip-bounty pattern of no-op'ing on a drained `Pool.Reward` (`Pool.Reward` drains to zero by design — there is no refill automation; the BURNIE flip credit and the leaderboard event remain meaningful even at a dry pool).

### 6d. gameOver = HARD CUTOFF (D-08)

`gameOver == true` → `claimBingo` **reverts** (hard cutoff). Bingo claiming is a game-long-but-not-after-end surface.

### 6e. Per-player dedup + systemwide first keys (D-07)

- **Per-player dedup:** once per `(level, quadrant)` via `bingoClaimed[level][msg.sender] & qMask`. On a valid claim, if the bit is unset, set `bingoClaimed[level][msg.sender] |= qMask`; if already set, the claim is a **revert** (already claimed this quadrant on this level). → **max 4 claims per player per level** (one per quadrant).
- **Systemwide first keys:** `firstQuadrant[level]` keyed by `(level, quadrant)` → 4 quadrant-firsts per level; `firstSymbol[level]` keyed by `(level, symbol)` → 32 symbol-firsts per level. (The exact set/check ordering — quadrant-first checked before symbol-first, both-bits-marked on a quadrant-first, suppression — is the binding rule in `339-TIER-PRECEDENCE-ACCEPTANCE-CONTRACT.md`.)

### 6f. Event-only leaderboard (D-08)

No on-chain leaderboard storage. Tier outcomes are surfaced via events only:
- `FirstQuadrantBingo` — emitted on a quadrant-first claim.
- `FirstSymbolBingo` — emitted on a symbol-first (non-quadrant-first) claim.
- `BingoClaimed(msg.sender, level, symbol, burnieReward, dgnrsPaid)` — emitted on **every** successful claim regardless of tier (the universal record carrying the actually-paid amounts).

---

## 7. RNG-Freeze posture (cross-ref)

`claimBingo` is a **strict read-only consumer** of the post-RNG-resolution `traitBurnTicket` map (it adds NO writes to it) and writes only its own three bitfields (`bingoClaimed` / `firstQuadrant` / `firstSymbol`). It touches no current-VRF-window output slot during `rngLock`. This is PROVEN (not assumed) in the companion `339-BINGO06-FREEZE-PROOF.md` (verdict FREEZE-SAFE) and the soundness of the ownership read in `339-TRAITBURNTICKET-SOUNDNESS-ATTESTATION.md` (verdict SOUND). The freeze proof is anchored to the **real writer** `DegenerusGameMintModule.sol:603-643` per the D-13 correction.

---

## 8. Producer-before-consumer edit-order for the 340 diff (D-13)

The single batched IMPL diff (Phase 340) lands in this order so each consumer sees its producer:

1. **Storage** — append `bingoClaimed` / `firstQuadrant` / `firstSymbol` to `contracts/storage/DegenerusGameStorage.sol` (tail of the layout, after `:416` `traitBurnTicket`).
2. **New module** — author `contracts/modules/DegenerusGameBingoModule.sol` (constants §5, the read/validate/select/pay logic, the three events).
3. **ContractAddresses** — add `GAME_BINGO_MODULE` to `contracts/ContractAddresses.sol`.
4. **DegenerusGame entrypoint + interface** — add the `claimBingo` external entrypoint (delegatecall to `GAME_BINGO_MODULE`, mirroring `:278-288`) + the interface signatures.
5. **(co-requisite, separate docs)** `StakedDegenerusStonk` rebalance (REBAL, `339` REBAL attestation) → `JackpotModule` final-day deletion (JACK, `339` JACK attestation).

---

*Phase: 339-spec-design-lock-rng-freeze-safety-proof-tier-precedence-loc · Plan 02 · Task 1*
*Companion: 339-TIER-PRECEDENCE-ACCEPTANCE-CONTRACT.md (tier selection) · 339-BINGO06-FREEZE-PROOF.md + 339-TRAITBURNTICKET-SOUNDNESS-ATTESTATION.md (freeze + soundness)*
