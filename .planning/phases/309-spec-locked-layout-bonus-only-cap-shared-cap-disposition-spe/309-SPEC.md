# Phase 309 SPEC — Locked Layout + Bonus-Only Cap + Shared-Cap Disposition

**Milestone:** v45.0 — Close the Lootbox EV-Cap Open-Ordering Hole (V-081)
**Baseline HEAD:** `MILESTONE_V44_AT_HEAD_6f0ba2963a10654ba554a8c333c5ee80c54a8349`
**Requirements covered here (Plan 309-01):** SPEC-01, SPEC-02, SPEC-03
**Requirement covered by Plan 309-02:** SPEC-04 (shared-cap disposition — §4, added separately)
**Authoritative content source:** `309-CONTEXT.md` decisions D-01..D-09 (D-10/D-11 → §4 Plan 02)

This SPEC LOCKS the v45.0 design BEFORE any contract change. It does not redesign; it
transcribes the locked decisions and grounds every cited `file:line` in a grep run against
the `contracts/` tree at the baseline HEAD. Per `feedback_no_history_in_comments`, all
statements describe what IS at HEAD (the SPEC) or what the IMPL phase MUST produce — never
what changed.

> **Scope invariant:** This is a SPEC-only phase. ZERO `contracts/` mutations, ZERO `test/`
> mutations. The grep evidence below is read-only verification; the only file written is this
> SPEC document.

---

## §0 Call-Graph Evidence (grep-verified against HEAD)

Every row was produced by a name-anchored `grep -n` against the `contracts/` tree at baseline
HEAD `6f0ba2963a10654ba554a8c333c5ee80c54a8349`. The recorded line is the line `grep -n`
returned; the matched substring is the literal source text at that line. SLOAD/SSTORE/call
sites are enumerated individually — no path is asserted "by construction".

### §0.A Storage declarations — `contracts/storage/DegenerusGameStorage.sol`

| Symbol | Line(s) | Matched substring | Key shape | Disposition |
|--------|---------|-------------------|-----------|-------------|
| `lootboxDay` | 1370 | `mapping(uint48 => mapping(address => uint32)) internal lootboxDay;` | `(uint48 index, address player) → uint32` | **Co-pack REJECTED (D-03)** — seed input |
| `lootboxBaseLevelPacked` | 1374-1375 | `mapping(uint48 => mapping(address => uint24))` / `internal lootboxBaseLevelPacked;` | `(uint48 index, address player) → uint24` | **REMOVED / merged into word (D-02)** |
| `lootboxEvScorePacked` | 1379 | `mapping(uint48 => mapping(address => uint16)) internal lootboxEvScorePacked;` | `(uint48 index, address player) → uint16` | **Widened uint256 + renamed `lootboxPurchasePacked` (D-05)** |
| `lootboxEvBenefitUsedByLevel` | 1427-1428 | `mapping(address => mapping(uint24 => uint256))` / `internal lootboxEvBenefitUsedByLevel;` | `(address player, uint24 level) → uint256` | **Shared cap accumulator — wrong key shape to co-pack (D-04)** |

Key-shape note: `lootboxBaseLevelPacked` (1374-1375) shares the EXACT `(uint48 index → address)`
outer/inner key of `lootboxEvScorePacked` (1379) and `lootboxDay` (1370) — that key-shape
identity is what makes the D-02 merge legal. `lootboxEvBenefitUsedByLevel` (1427-1428) is
keyed `(address player → uint24 level)` — a different shape that cannot co-pack into an
`(index, player)` slot (D-04).

### §0.B EV constants + multiplier helper — `contracts/modules/DegenerusGameLootboxModule.sol`

| Symbol | Line(s) | Matched substring |
|--------|---------|-------------------|
| `LOOTBOX_EV_MIN_BPS` | 308 | `uint16 private constant LOOTBOX_EV_MIN_BPS = 8_000;` |
| `LOOTBOX_EV_NEUTRAL_BPS` | 310 | `uint16 private constant LOOTBOX_EV_NEUTRAL_BPS = 10_000;` |
| `LOOTBOX_EV_MAX_BPS` | 312 | `uint16 private constant LOOTBOX_EV_MAX_BPS = 13_500;` |
| `LOOTBOX_EV_BENEFIT_CAP` | 314-315 | `uint256 private constant LOOTBOX_EV_BENEFIT_CAP =` / `10 ether;` |
| `_lootboxEvMultiplierFromScore` (def) | 444 | `function _lootboxEvMultiplierFromScore(` |

The cap is exactly `10 ether = 1e19 wei` (line 315). NEUTRAL = `10_000` bps = 100% (line 310).

### §0.C `_applyEvMultiplierWithCap` — definition + ALL THREE call sites (SPEC-02 anchor)

| Role | Line | Matched substring |
|------|------|-------------------|
| Definition | 475 | `function _applyEvMultiplierWithCap(` |
| Existing early-return (SPEC-02 Change-1 target) | 482 | `if (evMultiplierBps == LOOTBOX_EV_NEUTRAL_BPS) {` |
| **CALL #1 — open path** (`openLootBox`) | 559 | `uint256 scaledAmount = _applyEvMultiplierWithCap(` |
| **CALL #2 — `resolveLootboxDirect`** | 675 | `uint256 scaledAmount = _applyEvMultiplierWithCap(player, currentLevel, amount, evMultiplierBps);` |
| **CALL #3 — `resolveRedemptionLootbox`** | 711 | `uint256 scaledAmount = _applyEvMultiplierWithCap(player, currentLevel, amount, evMultiplierBps);` |

`grep -n "_applyEvMultiplierWithCap"` returns exactly four lines: 475 (def), 559, 675, 711.
Three distinct call sites — enumerated above, not asserted. The SPEC-02 `<=` rewrite at the
single definition (475/482) reaches all three callers because they share one helper.

### §0.D Cap-fn body SLOADs/SSTORE — `_applyEvMultiplierWithCap` (475-509)

| Op | Line | Matched substring |
|----|------|-------------------|
| Early return (neutral) | 482-484 | `if (evMultiplierBps == LOOTBOX_EV_NEUTRAL_BPS) { return amount; }` |
| SLOAD used cap | 487 | `uint256 usedBenefit = lootboxEvBenefitUsedByLevel[player][lvl];` |
| Compute remaining | 488-490 | `uint256 remainingCap = usedBenefit >= LOOTBOX_EV_BENEFIT_CAP ? 0 : LOOTBOX_EV_BENEFIT_CAP - usedBenefit;` |
| Cap-exhausted return | 492-495 | `if (remainingCap == 0) { ... return amount; }` |
| Adjusted/neutral split | 498-499 | `uint256 adjustedPortion = amount > remainingCap ? remainingCap : amount; uint256 neutralPortion = amount - adjustedPortion;` |
| SSTORE advance used cap | 502 | `lootboxEvBenefitUsedByLevel[player][lvl] = usedBenefit + adjustedPortion;` |
| Scale | 507-508 | `uint256 adjustedValue = (adjustedPortion * evMultiplierBps) / 10_000; scaledAmount = adjustedValue + neutralPortion;` |

The only shared mutable state read+written here is `lootboxEvBenefitUsedByLevel[player][lvl]`
(SLOAD 487, SSTORE 502). This is the cap-draw HEAD has at resolution today (the V-081 surface).

### §0.E Three roll entry points + frozen-score multiplier sources

| Function | Def line | Multiplier source | Matched substring |
|----------|----------|-------------------|-------------------|
| `openLootBox` | 517 | 558 (from packed score) | `function openLootBox(address player, uint48 index) external {` |
| open score read | — | 557 | `uint16 evScorePacked = lootboxEvScorePacked[index][player];` |
| open score→mult | — | 558 | `uint256 evMultiplierBps = _lootboxEvMultiplierFromScore(uint256(evScorePacked - 1));` |
| `resolveLootboxDirect` | 666 | 674 | `function resolveLootboxDirect(address player, uint256 amount, uint256 rngWord, uint16 activityScore) external {` |
| direct score→mult (frozen `activityScore` param) | — | 674 | `uint256 evMultiplierBps = _lootboxEvMultiplierFromScore(uint256(activityScore));` |
| `resolveRedemptionLootbox` | 702 | 710 | `function resolveRedemptionLootbox(address player, uint256 amount, uint256 rngWord, uint16 activityScore) external {` |
| redemption score→mult (frozen `activityScore` param) | — | 710 | `uint256 evMultiplierBps = _lootboxEvMultiplierFromScore(uint256(activityScore));` |

`resolveLootboxDirect` (674) and `resolveRedemptionLootbox` (710) derive the multiplier from
the FROZEN `activityScore` function parameter, NOT from `rngWord` — the word-independence
anchor carried into §4 (SPEC-04, Plan 02).

### §0.F Seed-build sites — RAW amount feeds `keccak256` (INV-04 / IMPL-05 anchor)

| Site | Line | Matched substring | Amount arg |
|------|------|-------------------|-----------|
| `openLootBox` | 545 | `uint256 seed = uint256(keccak256(abi.encode(rngWord, player, day, amount)));` | raw `amount` (uint256 from `lootboxEth`) |
| BURNIE open path | 621 | `uint256 seed = uint256(keccak256(abi.encode(rngWord, player, day, amountEth)));` | **`amountEth`** — see discrepancy note below |
| `resolveLootboxDirect` | 671 | `uint256 seed = uint256(keccak256(abi.encode(rngWord, player, day, amount)));` | raw `amount` |
| `resolveRedemptionLootbox` | 707 | `uint256 seed = uint256(keccak256(abi.encode(rngWord, player, day, amount)));` | raw `amount` |

All four roll seeds bind `(rngWord, player, day, <amount>)`. The reward-scaling change (SPEC-02/03)
introduces a derived `adjustedPortion` used ONLY for reward computation — the seed's amount arg
is never replaced. IMPL-05 / INV-04 require these four expressions stay byte-identical.

> **DISCREPANCY (recorded, not normalized):** The plan `<verified_head_facts>` listed `:621`
> as `keccak256(abi.encode(rngWord, player, day, amount))`. The ACTUAL HEAD source at line 621
> uses `amountEth` (a BURNIE→ETH-equivalent conversion computed at line 612:
> `uint256 amountEth = (burnieAmount * priceWei * 80) / (PRICE_COIN_UNIT * 100);`). This is the
> BURNIE-lootbox open path (`openBurnieLootBox`-style), distinct from the ETH `openLootBox` at
> 517/545. The seed-amount semantics are equivalent (each path seeds with its own settled
> amount), but the variable name differs. IMPL-05 must preserve the `amountEth` arg at 621
> exactly — the V-081 scaling change does not touch the BURNIE open path's seed.

### §0.G `lootboxBaseLevelPacked` + `lootboxEvScorePacked` read/write/clear sites (all 4 files)

| Field | Op | File:Line | Matched substring |
|-------|----|-----------|-------------------|
| baseLevel | read | Lootbox:541 | `uint24 baseLevelPacked = lootboxBaseLevelPacked[index][player];` |
| baseLevel | clear (zero-at-open) | Lootbox:570 | `lootboxBaseLevelPacked[index][player] = 0;` |
| baseLevel | write (Mint first-deposit) | Mint:992-994 | `lootboxBaseLevelPacked[lbIndex][buyer] = uint24( cachedLevel + 1 );` |
| baseLevel | write (Whale first-deposit) | Whale:855 | `lootboxBaseLevelPacked[index][buyer] = uint24(level + 2);` |
| score | read | Lootbox:557 | `uint16 evScorePacked = lootboxEvScorePacked[index][player];` |
| score | clear (zero-at-open) | Lootbox:571 | `lootboxEvScorePacked[index][player] = 0;` |
| score | write (Mint, gated) | Mint:1154-1155 | `if (lbFirstDeposit) { lootboxEvScorePacked[lbIndex][buyer] = uint16(cachedScore + 1); }` |
| score | write (Whale, inline) | Whale:856-858 | `lootboxEvScorePacked[index][buyer] = uint16( IDegenerusGame(address(this)).playerActivityScore(buyer) + 1 );` |

All baseLevel + score read/write/clear sites live inside the 4 in-scope files
(LootboxModule, MintModule, WhaleModule) plus the Storage declaration — no scope escape. The
two zero-at-open clears (Lootbox:570 + 571) become a single whole-word SSTORE under D-07.

### §0.H `lootboxDay` writers — EXHAUSTIVE enumeration across all files (D-03 support)

| # | File:Line | Branch / context | Matched substring |
|---|-----------|------------------|-------------------|
| W1 | Mint:991 | ETH first-deposit | `lootboxDay[lbIndex][buyer] = lbDay;` |
| W2 | Mint:1396-1397 | **BURNIE-lootbox path** (separate from ETH first-deposit) | `if (lootboxDay[index][buyer] == 0) { lootboxDay[index][buyer] = _simulatedDayIndex(); }` |
| W3 | Whale:854 | Whale first-deposit | `lootboxDay[index][buyer] = dayIndex;` |

`grep -n "lootboxDay" contracts/modules/DegenerusGameMintModule.sol` returns BOTH Mint writers
(991 and 1396-1397). W2 is the BURNIE deposit path — it writes `lootboxDay` then `lootboxBurnie`
(Mint:1399), an entirely separate slot from the ETH packed word. ENUMERATING every writer
confirms D-03: `lootboxDay` stays its own `uint32` slot for ALL THREE writers (W1/W2/W3); none
of them is folded into the packed word, because the day is consumed as a seed input at the
read sites (Lootbox:528, 545; 616, 621). Reads: Lootbox:528 (`uint32 day = lootboxDay[index][player];`),
Lootbox:616 (`uint32 day = lootboxDay[index][player];`).

### §0.I FLAGGED DIVERGENCES (inline-duplicated business logic — Phase 294 BURNIE precedent)

| # | Divergence | Site A | Site B | IMPL implication |
|---|-----------|--------|--------|------------------|
| DIV-1 | **baseLevel sentinel offset differs** | Mint:992-994 writes `uint24(cachedLevel + 1)` | Whale:855 writes `uint24(level + 2)` | The packed-word `baseLevel+1` field MUST carry whatever each call site already encodes — Mint contributes `cachedLevel + 1`, Whale contributes `level + 2`. The IMPL pack helper takes an already-encoded `baseLevelPlus1`; it MUST NOT silently normalize the two offsets. Each call site preserves its existing semantics. |
| DIV-2 | **score-write structure differs** | Mint:1154-1155 gates behind `if (lbFirstDeposit) { ... }` | Whale:856-858 writes inline inside the first-deposit branch (`if (existingAmount == 0)`) | The §3 tally rule MUST cover BOTH write shapes. Mint computes `cachedScore` later (1106) then writes the score gated; Whale snapshots `playerActivityScore(buyer)` inline at first deposit. The tally rule is structure-agnostic: "first deposit writes `score+1`" holds for both; the IMPL must wire each module's existing structure to the packed word without re-ordering its score read. |

These divergences are DOCUMENTED, not fixed. Phase 310 IMPL must patch each site preserving
its current semantics (per `feedback_verify_call_graph_against_source` — inline-duplicated logic
is recurring in this codebase; the Phase 294 BURNIE gap is the precedent).

### §0.J Line-number reconciliation vs plan `<verified_head_facts>`

All cited lines matched the plan's pre-verified facts EXCEPT:
- **621 seed amount arg:** plan said `amount`; HEAD has `amountEth` (recorded in §0.F discrepancy box).

Storage spans confirmed: `lootboxBaseLevelPacked` decl spans 1374-1375 (type on 1374, name on 1375);
`lootboxEvBenefitUsedByLevel` spans 1427-1428 (type on 1427, name on 1428). Mint baseLevel write
spans 992-994 (statement split across three lines). All other lines (1370, 1379, 308-314, 444,
475, 482, 517, 528, 541, 545, 557-559, 570-571, 616, 666, 671, 674-675, 702, 707, 710-711;
Mint 987, 991, 1013, 1155, 1396-1397; Whale 851, 854-856, 876) matched exactly.

### §0.K Attestation

**Zero "by construction" / "single fn reaches all paths" claims** — every cited site in §0.A
through §0.J is grep-verified above with its matched substring and the line `grep -n` returned.
SLOADs/SSTOREs and the three `_applyEvMultiplierWithCap` call sites are enumerated individually;
all three `lootboxDay` writers are enumerated exhaustively; both inline-duplication divergences
are flagged for IMPL preservation. This SPEC describes what IS at HEAD
`6f0ba2963a10654ba554a8c333c5ee80c54a8349` (`feedback_no_history_in_comments`).

---

## §1 SPEC-01 — Packed-Slot Layout (LOCKED)

Transcribes the LOCKED decisions D-01..D-07 from `309-CONTEXT.md`. No redesign, no
alternatives. Storage decls cited by their §0.A grep-verified lines.

### §1.1 Final packed `uint256` word layout (D-02)

A single `uint256` value (per `(uint48 index, address player)` mapping entry) holds three
fields plus free space:

| Bit range | Field | Width | Encoding |
|-----------|-------|-------|----------|
| `[0:16]` | `score + 1` | `uint16` | `0` = unset; raw activity score + 1 |
| `[16:80]` | `adjustedPortion` | `uint64` | cap-eligible ETH that received the bonus; `<= 10 ETH` |
| `[80:104]` | `baseLevel + 1` | `uint24` | `0` = unset; per-module sentinel offset (see DIV-1) |
| `[104:256]` | free | 152 bits | reserved, written as zero |

This single word REPLACES BOTH the old `lootboxEvScorePacked` (`Storage.sol:1379`, §0.A) and
`lootboxBaseLevelPacked` (`Storage.sol:1374-1375`, §0.A).

### §1.2 `adjustedPortion` width = `uint64` (D-01) — fix-plan `uint96` SUPERSEDED

`adjustedPortion` is **`uint64`**, NOT `uint96`. The v45 fix-plan
(`.planning/v45-lootbox-evcap-fix-plan.md`) specified `uint96`; that width is **SUPERSEDED** by
this SPEC. `REQUIREMENTS.md` SPEC-01 specifies `uint64`, and this SPEC locks `uint64`.

Width proof:
- `adjustedPortion <= LOOTBOX_EV_BENEFIT_CAP = 10 ether = 1e19 wei` (constant at `LootboxModule.sol:314-315`, §0.B).
- `ceil(log2(1e19)) = 64` → 64 bits is the minimum standard width that holds the cap.
- `uint64` max `= 2^64 - 1 ≈ 1.8447e19 wei ≈ 18.44 ETH` → ~84% headroom above the 10 ETH cap.
- A single box's accumulated `adjustedPortion` can NEVER exceed the cap: each per-deposit
  `add = min(deposit, remaining)` advances `lootboxEvBenefitUsedByLevel[player][lvl]` (§0.D
  SSTORE 502 semantics carried to allocation time), so the running total is bounded by the cap.

Tightest standard width per `feedback_maximal_variable_packing` + the REQUIREMENTS.md "tightest
field widths" gas directive.

### §1.3 baseLevel co-pack (D-02) — removes a slot, net −1

The packed word folds in the base level, REMOVING the separate `lootboxBaseLevelPacked` mapping
(`Storage.sol:1374-1375`, §0.A) entirely → **net −1 storage slot per `(index, player)` box**.

Justification (all grep-grounded in §0):
- Same `(uint48 index => address)` outer/inner key as the score word (§0.A key-shape note).
- Identical write-once / read+clear lifecycle: written at first deposit (Mint:992-994, Whale:855
  — §0.G), read at open (Lootbox:541 — §0.G), cleared at open (Lootbox:570 — §0.G).
- All sites live inside the 4 in-scope files — no scope escape (§0.G).
- `baseLevel` is NOT a seed input (the seed binds `day`+`amount`, §0.F — not `baseLevel`).
- The deposit-time `adjustedPortion` accumulation already read-modify-writes the word, so
  folding `baseLevel` in adds ZERO additional deposit-path SLOAD.

### §1.4 `lootboxDay` co-pack REJECTED (D-03) — freeze hard line

`lootboxDay` (`uint32`, `Storage.sol:1370`, §0.A) shares the `(index, player)` key but is
**EXCLUDED** from the packed word — evaluated and rejected. Reason: it is read at
`LootboxModule.sol:528` and `:616` (§0.H reads) and feeds the frozen roll seed
`keccak256(abi.encode(rngWord, player, day, amount))` at `:545` (§0.F). Co-packing `lootboxDay`
would perturb a seed-input read path, forbidden by **INV-04 / IMPL-05** (seed/roll
byte-identical). This is the freeze-invariant hard line per `v45-vrf-freeze-invariant` +
`feedback_security_over_gas`: packing never trades a freeze invariant. All three `lootboxDay`
writers (§0.H W1/W2/W3) keep their own `uint32` slot.

### §1.5 No-other-co-pack negative finding (D-04)

Per SPEC-01's literal scope (cap-bounded per-box fields), the only other cap-bounded field is
`lootboxEvBenefitUsedByLevel` (`Storage.sol:1427-1428`, §0.A), keyed `(address player, uint24
level)`. That is the WRONG key shape for an `(index, player)` slot — it cannot co-pack. Recorded
as an explicit negative finding. (`baseLevel` in §1.3 is an opportunistic, non-cap-bounded
co-pack the user opted into beyond SPEC-01's literal ask.)

### §1.6 Rename (D-05): `lootboxEvScorePacked → lootboxPurchasePacked`

Rename `lootboxEvScorePacked` → **`lootboxPurchasePacked`**, type
`mapping(uint48 => mapping(address => uint256))`. This single mapping REPLACES BOTH
`lootboxEvScorePacked` (`Storage.sol:1379`) and `lootboxBaseLevelPacked` (`Storage.sol:1374-1375`).
Rationale: the word is no longer EV-only (it now also carries `baseLevel`), so a neutral
"purchase-time packed state" name describes what IS, per `feedback_no_history_in_comments`.

### §1.7 Helper signatures (D-06)

```solidity
function _packLootboxPurchase(uint16 scorePlus1, uint64 adj, uint24 baseLevelPlus1)
    returns (uint256);
function _unpackLootboxPurchase(uint256)
    returns (uint16 scorePlus1, uint64 adj, uint24 baseLevelPlus1);
```

The helpers live in `DegenerusGameLootboxModule.sol` alongside the EV constants (§0.B) and
`_applyEvMultiplierWithCap` (§0.C). The pack helper takes an **already-encoded** `baseLevelPlus1`
— it does NOT reconcile the DIV-1 sentinel-offset divergence. Phase 310 IMPL MUST preserve each
call site's existing encoding: Mint passes `cachedLevel + 1` (Mint:992-994, §0.G/§0.I DIV-1),
Whale passes `level + 2` (Whale:855, §0.G/§0.I DIV-1). The helper never normalizes them.

### §1.8 No-new-slot attestation (D-07)

No NEW storage slot is introduced. Mapping values never cross-pack, and the old `uint16`
`lootboxEvScorePacked` already occupied a full slot (mappings allocate a full slot per value
regardless of declared width). Widening that mapping value to `uint256` adds zero slots; the
`baseLevel` merge (§1.3) REMOVES one slot. **Net change: −1 storage slot per `(index, player)`.**
Zero-at-open clears all three fields (`score+1`, `adjustedPortion`, `baseLevel+1`) in a single
SSTORE of the whole word — replacing the two separate clears at `LootboxModule.sol:570` and
`:571` (§0.G).

---

## §2 SPEC-02 — Bonus-Only Cap (LOCKED)

Transcribes D-08 verbatim from `REQUIREMENTS.md` SPEC-02 + the fix-plan Change 1.

### §2.1 Rule

In `_applyEvMultiplierWithCap` (`LootboxModule.sol:475`, §0.C definition), REPLACE the existing
early return:

```solidity
// HEAD (LootboxModule.sol:482, §0.D):
if (evMultiplierBps == LOOTBOX_EV_NEUTRAL_BPS) {
    return amount;
}
```

with a `<=` condition that applies the multiplier in full and never consumes the cap:

```solidity
// LOCKED v45.0 rule:
if (evMultiplierBps <= LOOTBOX_EV_NEUTRAL_BPS) {
    return (amount * evMultiplierBps) / 10_000;
}
```

- A **penalty** box (`evMultiplierBps < NEUTRAL`, i.e. sub-100%) applies its penalty on the FULL
  `amount` and draws ZERO from the cap.
- A **neutral** box (`evMultiplierBps == NEUTRAL`) returns `amount` (since `amount * 10_000 / 10_000
  = amount`) and draws ZERO from the cap.
- ONLY a **bonus** box (`evMultiplierBps > NEUTRAL`) falls through to the cap-draw logic
  (`LootboxModule.sol:487-508`, §0.D) and consumes `lootboxEvBenefitUsedByLevel[player][lvl]`.

This eliminates the V-081 penalty-dodge: a sub-100% box can no longer consume cap headroom that
should be reserved for bonus boxes.

### §2.2 Applies to ALL THREE callers

`_applyEvMultiplierWithCap` is a single private helper; the `<=` rewrite at its definition
(475/482) reaches all three grep-verified call sites enumerated in §0.C:

| Caller | Call line (§0.C) | Path |
|--------|------------------|------|
| `openLootBox` | **559** | purchased-box open |
| `resolveLootboxDirect` | **675** | decimator / degenerette on-the-fly |
| `resolveRedemptionLootbox` | **711** | redemption on-the-fly |

EV constants are at `LootboxModule.sol:308-314` (§0.B): `LOOTBOX_EV_NEUTRAL_BPS = 10_000`
(line 310). The `/ 10_000` literal divisor matches the existing scaling at `LootboxModule.sol:507`
(§0.D).

---

## §3 SPEC-03 — Allocation Tally + Open-Apply (LOCKED)

Transcribes D-09 verbatim from `REQUIREMENTS.md` SPEC-03; `adjustedPortion` width now `uint64`
per D-01 (§1.2). The cap draw MOVES from resolution time (§0.D, the V-081 surface) to
allocation/deposit time for purchased boxes, so open order can no longer steer cap allocation.

### §3.1 Per-deposit tally rule (frozen multiplier from first-deposit score)

The box's multiplier is frozen from the FIRST-deposit score snapshot. At each deposit:

- **`mult <= NEUTRAL`** (penalty or neutral): store `score + 1` only on first deposit; NO cap
  draw. `adjustedPortion` stays `0` in the packed word.
- **`mult > NEUTRAL`** (bonus): draw the cap at allocation time:
  - `remaining = CAP - lootboxEvBenefitUsedByLevel[player][lvl]` (clamp to `0` if `used >= CAP`).
  - `add = min(depositAmount, remaining)`.
  - advance the shared used accumulator: `lootboxEvBenefitUsedByLevel[player][lvl] += add`.
  - accumulate into the packed word: `adjustedPortion += add` via read-modify-write of
    `lootboxPurchasePacked[index][player]`.

`CAP = LOOTBOX_EV_BENEFIT_CAP = 10 ether` (§0.B line 314-315). The accumulator is the same
`lootboxEvBenefitUsedByLevel[player][lvl]` that HEAD draws at resolution (§0.D SLOAD 487 / SSTORE
502) — keyed `(player, uint24 level)` (§0.A line 1427-1428).

### §3.2 First deposit vs subsequent deposits

- **First deposit:** writes `score + 1` AND `baseLevel + 1` into the packed word (per D-02 §1.1),
  preserving the per-module sentinel offset (DIV-1, §0.I): Mint contributes `cachedLevel + 1`
  (Mint:992-994, §0.G), Whale contributes `level + 2` (Whale:855, §0.G).
- **Subsequent deposits:** accumulate `adjustedPortion` ONLY (score + multiplier already frozen
  from the first-deposit snapshot); `score+1` and `baseLevel+1` are not rewritten.

### §3.3 Deposit-site citations + structural divergences

Cited deposit sites from §0:

| Module | First-deposit sites | Subsequent | Score write |
|--------|--------------------|-----------|-------------|
| Mint | day 991, baseLevel 992-994 | lootboxEth 1013-1015 | 1154-1155 **gated** behind `if (lbFirstDeposit)` (§0.I DIV-2) |
| Whale | day 854, baseLevel 855, score 856-858 | lootboxEth 876 | 856-858 **inline** in first-deposit branch (§0.I DIV-2) |

The §3.1 tally rule covers BOTH structural shapes (DIV-2, §0.I): Mint computes `cachedScore`
later (Mint:1106) and writes the score gated; Whale snapshots `playerActivityScore(buyer)` inline
at first deposit. The rule "first deposit writes `score+1`; bonus boxes accumulate `adjustedPortion`"
holds for both — the IMPL wires each module's existing structure to the packed word without
re-ordering its score read. The DIV-1 baseLevel sentinel divergence (Mint `+1` vs Whale `+2`) is
likewise preserved at each site per §1.7.

### §3.4 openLootBox frozen application — no cap SLOAD/SSTORE

`openLootBox` (`LootboxModule.sol:517`, §0.E) applies the FROZEN allocation read from the packed
word, with NO cap SLOAD/SSTORE (the cap was already drawn at deposit time per §3.1):

```
scaled = mult <= NEUTRAL
       ? amount * mult / 1e4
       : adj * mult / 1e4 + (amount - adj)
```

where `mult = _lootboxEvMultiplierFromScore(score)` (frozen from the unpacked `score+1`,
§0.E read 557 / mult 558) and `adj = adjustedPortion` (unpacked from the word). The bonus branch
scales only the `adj` portion by `mult` and pays the remainder `(amount - adj)` at 100% — exactly
the adjusted/neutral split HEAD computes at `LootboxModule.sol:498-508` (§0.D), but with the
cap-eligible portion pre-frozen instead of drawn live.

The cap-draw SLOAD/SSTORE that HEAD performs inside `_applyEvMultiplierWithCap` at open
(§0.D lines 487, 502) is REMOVED from the open path — `openLootBox` no longer calls the
cap-drawing branch; it reads the frozen `adj` from the word. The zero-at-open write clears the
WHOLE packed slot in a single SSTORE (§1.8), replacing the two separate clears at
`LootboxModule.sol:570` and `:571` (§0.G).

### §3.5 Seed / roll preservation (IMPL-05 / INV-04)

The raw `amount` STILL feeds the roll seed `keccak256(abi.encode(rngWord, player, day, amount))`
at `LootboxModule.sol:545` (open path, §0.F) — only reward SCALING uses `adjustedPortion`; the
seed's amount arg is never replaced by `adj`. The `lootboxEth` packed layout
(`(level << 232) | amount`) is UNTOUCHED (Mint:1013-1015, Whale:876 — §0.G). The roll target the
box hits and the index/word it rolls against are byte-unchanged. (The BURNIE open path seeds with
`amountEth` at `:621`, §0.F discrepancy box — also preserved unchanged.) This is the INV-04 /
IMPL-05 seed-byte-identical hard line carried from §0.F.
