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
