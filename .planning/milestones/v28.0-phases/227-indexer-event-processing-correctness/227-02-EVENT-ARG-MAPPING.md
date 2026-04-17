# 227-02 Event Arg → Schema Mapping (IDX-02)

**Phase:** 227 | **Plan:** 02 | **Requirement:** IDX-02
**Input set:** 95 PROCESSED ∪ DELEGATED→PROCESSED rows from `227-01-EVENT-COVERAGE-MATRIX.md`.
**Schema authority:** `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/phases/226-schema-migration-orphan-audit/226-01-SCHEMA-MIGRATION-DIFF.md` (locked per D-227-09).
**Finding block:** F-28-227-101..199 (reserved per D-227-11, disjoint from 227-01 F-28-227-01..23 and from 227-03's reserved two-hundred-series block).
**Verdict dimensions (all three must PASS for event PASS):** (1) field-name, (2) Solidity↔Drizzle type, (3) coercion safety.

## Coercion Gotchas Table (verbatim from 227-RESEARCH.md §Type-Coercion Gotchas)

| Solidity type | Safe TS coercion | Unsafe (finding candidate) | Target column |
|---------------|-----------------|---------------------------|---------------|
| `uint8` / `uint16` / `uint24` / `uint32` | `Number(parseBigInt(x))` | direct `ctx.args.x as number` (works for small ints but loses provenance) | `smallint` / `integer` |
| `uint48` / `uint56` / `uint64` | `parseBigInt(x).toString()` or Drizzle `bigint({mode:'bigint'})` | `Number(parseBigInt(x))` — JS `Number` safe only to 2^53-1 | `bigint` or `numeric`/`text` |
| `uint96` / `uint128` / `uint256` | `parseBigInt(x).toString()` | `Number(parseBigInt(x))` — **silent truncation** past 2^53 | `numeric` or `text` |
| `address` | `parseAddress(x)` (lowercased) | raw `ctx.args.x` (mixed case from viem) — breaks FK joins against other lowercased columns | `text` |
| `bytes32` | `ctx.args.x as string` (viem returns `0x`-prefixed hex) | hex-decode to Buffer | `text` |
| `bool` | `Boolean(ctx.args.x)` or direct | `Number(ctx.args.x)` | `boolean` |
| enum / `uint8` | `Number(parseBigInt(x))` with named enum guard | raw `parseBigInt` (leaks bigint type surface) | `smallint` |
| `int256` (signed) | `parseBigInt(x).toString()` | `Number(...)` | `numeric` |

### Silent-truncation hunt pattern (verbatim from 227-RESEARCH.md)

```
rg -nB2 -A1 "Number\(parseBigInt\(ctx\.args\.\w+\)\)" /home/zak/Dev/PurgeGame/database/src/handlers/*.ts
```

Verdict: LOW finding if the Solidity arg type is `uint48` or wider. PASS if `uint32` or narrower.

### Address-case drift hunt pattern (verbatim from 227-RESEARCH.md)

```
rg -n "ctx\.args\.\w+" /home/zak/Dev/PurgeGame/database/src/handlers/*.ts | rg -v "parseAddress|parseBigInt|\.toString"
```

Verdict: LOW finding if the Solidity arg type is `address`.

## Methodology notes

- For each event, the **Solidity types** come from the multiline event regex extraction (canonical — `/tmp/events-clean.txt` during execution, sourced from `contracts/*.sol`, `contracts/modules/*.sol`, `contracts/storage/*.sol`).
- For each handler, **`ctx.args.*` reads** and `.insert(table).values({...})` **object keys** are extracted per handler function body.
- **Schema column types** are sourced via Phase 226 locked model lookup (D-227-09). Every decimal-string-stored uint256 → `numeric/text`; every `Number()` coerced narrow uint → `smallint/integer`; address → `text`.
- **Name match** uses camel↔snake equivalence (e.g., `tokenId` ↔ `token_id`, `blockNumber` ↔ `block_number`). TS Drizzle camelCase object keys map to snake_case Postgres columns via Drizzle's `pgTable` column aliases in all schemas verified in Phase 226.
- **Legend:** ✓ = PASS, ✗ = FAIL, n/a = arg not written to schema (recorded for coverage only).

---

## Per-Event Verdict Tables

Each event block shows: `EventName — declaring contract → handlers/<file>.ts:<line>(<fn>) → <schemaTable>`.

### Affiliate — DegenerusAffiliate.sol → handlers/affiliate.ts:33 (handleAffiliate) → affiliate_codes

Solidity: `event Affiliate(uint256 amount, bytes32 indexed code, address sender)`

| Event | Arg | Solidity type | Coercion wrapper | TS field | Schema table | Schema column | Schema type | Name match? | Type match? | Coercion safe? | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Affiliate | amount | uint256 | (not read) | — | — | — | — | n/a | n/a | n/a | PASS (unused) |
| Affiliate | code | bytes32 | `String(ctx.args.code)` | code | affiliate_codes | code | text | ✓ | ✓ | ✓ | PASS |
| Affiliate | sender | address | `parseAddress(ctx.args.sender)` | owner | affiliate_codes | owner | text | ✓ (maps sender→owner per handler semantic; schema column named `owner`) | ✓ | ✓ | PASS |

**Event verdict:** PASS  (handler deliberately aliases `sender` → `owner`; documented in affiliate.ts:34 semantics)

---

### ReferralUpdated — DegenerusAffiliate.sol → handlers/affiliate.ts:60 → player_referrals

Solidity: `event ReferralUpdated(address indexed player, bytes32 indexed code, address indexed referrer, bool locked)`

| Event | Arg | Solidity type | Coercion wrapper | TS field | Schema column | Schema type | Name match? | Type match? | Coercion safe? | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|
| ReferralUpdated | player | address | parseAddress | player | player | text | ✓ | ✓ | ✓ | PASS |
| ReferralUpdated | code | bytes32 | `String(ctx.args.code)` | code | code | text | ✓ | ✓ | ✓ | PASS |
| ReferralUpdated | referrer | address | parseAddress | referrer | referrer | text | ✓ | ✓ | ✓ | PASS |
| ReferralUpdated | locked | bool | `Boolean(ctx.args.locked)` | locked | locked | boolean | ✓ | ✓ | ✓ | PASS |

**Event verdict:** PASS

---

### AffiliateEarningsRecorded — DegenerusAffiliate.sol → handlers/affiliate.ts:93 → affiliate_earnings

Solidity: `event AffiliateEarningsRecorded(uint24 indexed level, address indexed affiliate, uint256 amount, uint256 newTotal, address indexed sender, bytes32 code, bool isFreshEth)`

| Event | Arg | Solidity type | Coercion | TS field | Schema column | Schema type | Name | Type | Coerce | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|
| AffiliateEarningsRecorded | level | uint24 | `Number(parseBigInt(.level))` | level | level | integer | ✓ | ✓ | ✓ (uint24 safe) | PASS |
| AffiliateEarningsRecorded | affiliate | address | parseAddress | affiliate | affiliate | text | ✓ | ✓ | ✓ | PASS |
| AffiliateEarningsRecorded | amount | uint256 | (not read) | — | — | — | n/a | n/a | n/a | PASS (unused) |
| AffiliateEarningsRecorded | newTotal | uint256 | `parseBigInt(.newTotal).toString()` | totalEarned | total_earned | numeric/text | ✓ (rename semantic) | ✓ | ✓ | PASS |
| AffiliateEarningsRecorded | sender, code, isFreshEth | address / bytes32 / bool | (not read) | — | — | — | n/a | n/a | n/a | PASS (unused) |

**Event verdict:** PASS

---

### AffiliateTopUpdated — DegenerusAffiliate.sol → handlers/affiliate.ts:121 → affiliate_top_by_level

Solidity: `event AffiliateTopUpdated(uint24 indexed level, address indexed player, uint96 score)`

| Arg | Sol | Coercion | TS field | Schema col | Schema type | Name | Type | Coerce | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| level | uint24 | Number(parseBigInt) | level | level | integer | ✓ | ✓ | ✓ | PASS |
| player | address | parseAddress | player | player | text | ✓ | ✓ | ✓ | PASS |
| score | uint96 | `parseBigInt(.score).toString()` | score | score | numeric/text | ✓ | ✓ | ✓ (string-preserving) | PASS |

**Event verdict:** PASS

---

### AffiliateDgnrsReward — modules/DegenerusGameAdvanceModule.sol → handlers/affiliate.ts:151 → affiliate_dgnrs_rewards

Solidity: `event AffiliateDgnrsReward(address indexed affiliate, uint24 indexed level, uint256 dgnrsAmount)`

| Arg | Sol | Coercion | TS field | Schema col | Schema type | Name | Type | Coerce | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| affiliate | address | parseAddress | affiliate | affiliate | text | ✓ | ✓ | ✓ | PASS |
| level | uint24 | Number(parseBigInt) | level | level | integer | ✓ | ✓ | ✓ | PASS |
| dgnrsAmount | uint256 | parseBigInt(.).toString() | dgnrsAmount | dgnrs_amount | numeric/text | ✓ | ✓ | ✓ | PASS |

**Event verdict:** PASS

---

### AffiliateDgnrsClaimed — DegenerusGame.sol → handlers/affiliate.ts:172 → affiliate_dgnrs_claims

Solidity: `event AffiliateDgnrsClaimed(address indexed affiliate, uint24 indexed level, address indexed caller, uint256 score, uint256 amount)`

| Arg | Sol | Coercion | TS | Schema col | Schema type | Name | Type | Coerce | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| affiliate | address | parseAddress | affiliate | affiliate | text | ✓ | ✓ | ✓ | PASS |
| level | uint24 | Number(parseBigInt) | level | level | integer | ✓ | ✓ | ✓ | PASS |
| caller | address | parseAddress | caller | caller | text | ✓ | ✓ | ✓ | PASS |
| score | uint256 | parseBigInt(.).toString() | score | score | numeric/text | ✓ | ✓ | ✓ | PASS |
| amount | uint256 | parseBigInt(.).toString() | amount | amount | numeric/text | ✓ | ✓ | ✓ | PASS |

**Event verdict:** PASS

---

### BafFlipRecorded — DegenerusJackpots.sol → handlers/baf-jackpot.ts:21 → baf_flip_totals

Solidity: `event BafFlipRecorded(address indexed player, uint24 indexed lvl, uint256 amount, uint256 newTotal)`

| Arg | Sol | Coercion | TS | Schema col | Schema type | Name | Type | Coerce | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| player | address | parseAddress | player | player | text | ✓ | ✓ | ✓ | PASS |
| lvl | uint24 | Number(parseBigInt(.lvl)) | level | level | integer | ✓ (`lvl`→`level` camel equivalence; handler rename, matches Phase 226 locked column `level`) | ✓ | ✓ | PASS |
| amount | uint256 | (not read) | — | — | — | n/a | n/a | n/a | PASS (unused) |
| newTotal | uint256 | parseBigInt(.).toString() | totalStake | total_stake | numeric/text | ✓ (rename semantic) | ✓ | ✓ | PASS |

**Event verdict:** PASS

---

### CoinflipDeposit — BurnieCoinflip.sol → handlers/coinflip.ts:48 → coinflip_daily_stakes

Solidity: `event CoinflipDeposit(address indexed player, uint256 creditedFlip)`

| Arg | Sol | Coercion | TS | Schema col | Type | Name | Type | Coerce | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| player | address | parseAddress | player | player | text | ✓ | ✓ | ✓ | PASS |
| creditedFlip | uint256 | parseBigInt(.).toString() | amount | amount | numeric/text | ✓ (rename) | ✓ | ✓ | PASS |
| day | (derived from block.timestamp) | — | day | day | integer | — | ✓ | ✓ (safe — timestamp/86400) | PASS |

**Event verdict:** PASS

---

### CoinflipStakeUpdated — BurnieCoinflip.sol → handlers/coinflip.ts:65 → coinflip_daily_stakes

Solidity: `event CoinflipStakeUpdated(address indexed player, uint32 indexed day, uint256 amount, uint256 newTotal)`

| Arg | Sol | Coercion | TS | Schema col | Type | Name | Type | Coerce | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| player | address | parseAddress | player | player | text | ✓ | ✓ | ✓ | PASS |
| day | uint32 | Number(parseBigInt) | day | day | integer | ✓ | ✓ | ✓ | PASS |
| amount | uint256 | (not read) | — | — | — | n/a | n/a | n/a | PASS |
| newTotal | uint256 | parseBigInt(.).toString() | amount | amount | numeric/text | ✓ (rename) | ✓ | ✓ | PASS |

**Event verdict:** PASS

---

### CoinflipDayResolved — BurnieCoinflip.sol → handlers/coinflip.ts:90 → coinflip_results

Solidity: `event CoinflipDayResolved(uint32 indexed day, bool win, uint16 rewardPercent, uint128 bountyAfter, uint128 bountyPaid, address bountyRecipient)`

| Arg | Sol | Coercion | TS | Schema col | Type | Name | Type | Coerce | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| day | uint32 | Number(parseBigInt) | day | day | integer | ✓ | ✓ | ✓ | PASS |
| win | bool | Boolean | win | win | boolean | ✓ | ✓ | ✓ | PASS |
| rewardPercent | uint16 | Number(parseBigInt) | rewardPercent | reward_percent | integer | ✓ | ✓ | ✓ | PASS |
| bountyAfter | uint128 | parseBigInt(.).toString() | bountyAfter | bounty_after | numeric/text | ✓ | ✓ | ✓ | PASS |
| bountyPaid | uint128 | parseBigInt(.).toString() | bountyPaid | bounty_paid | numeric/text | ✓ | ✓ | ✓ | PASS |
| bountyRecipient | address | parseAddress (nullable guard) | bountyRecipient | bounty_recipient | text | ✓ | ✓ | ✓ | PASS |

**Event verdict:** PASS

---

### CoinflipTopUpdated — BurnieCoinflip.sol → handlers/coinflip.ts:125 → coinflip_leaderboard

Solidity: `event CoinflipTopUpdated(uint32 indexed day, address indexed player, uint96 score)`

All three args present. day/uint32→integer PASS; player/address→text PASS; score/uint96 `parseBigInt(.).toString()` → numeric/text PASS.

**Event verdict:** PASS

---

### BiggestFlipUpdated — BurnieCoinflip.sol → handlers/coinflip.ts:152 → coinflip_bounty_state (id=1 singleton)

Solidity: `event BiggestFlipUpdated(address indexed player, uint256 recordAmount)`

| Arg | Sol | Coercion | TS | Schema col | Type | Name | Type | Coerce | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| player | address | parseAddress | biggestFlipPlayer | biggest_flip_player | text | ✓ (rename) | ✓ | ✓ | PASS |
| recordAmount | uint256 | parseBigInt(.).toString() | biggestFlipAmount | biggest_flip_amount | numeric/text | ✓ (rename) | ✓ | ✓ | PASS |

**Event verdict:** PASS

---

### BountyOwed — BurnieCoinflip.sol → handlers/coinflip.ts:180 → coinflip_bounty_state

Solidity: `event BountyOwed(address indexed player, uint128 bounty, uint256 recordFlip)`

| Arg | Sol | Coercion | TS | Schema col | Type | Name | Type | Coerce | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| player | address | (not read) | — | — | — | n/a | n/a | n/a | PASS (not persisted; singleton upserts currentBounty only) |
| bounty | uint128 | parseBigInt(.bounty).toString() | currentBounty | current_bounty | numeric/text | ✓ (rename) | ✓ | ✓ | PASS |
| recordFlip | uint256 | (not read) | — | — | — | n/a | n/a | n/a | PASS |

**Event verdict:** PASS

---

### BountyPaid — BurnieCoinflip.sol → handlers/coinflip.ts:214 (no-op) → (none)

Solidity: `event BountyPaid(address indexed to, uint256 amount)`

Handler is deliberate no-op (comment cites CoinflipDayResolved captures bounty_paid and bounty_recipient). All args unused.

**Event verdict:** PASS (informational no-op)

---

### CoinflipAutoRebuyToggled — BurnieCoinflip.sol → handlers/coinflip.ts:220 → coinflip_settings

Solidity: `event CoinflipAutoRebuyToggled(address indexed player, bool enabled)`

player/address→text PASS; enabled/bool→boolean PASS.

**Event verdict:** PASS

---

### CoinflipAutoRebuyStopSet — BurnieCoinflip.sol → handlers/coinflip.ts:245 → coinflip_settings

Solidity: `event CoinflipAutoRebuyStopSet(address indexed player, uint256 stopAmount)`

player/address→text PASS; stopAmount/uint256 → `parseBigInt(.).toString()` → `auto_rebuy_stop` (numeric/text) PASS (rename).

**Event verdict:** PASS

---

### LinkCreditRecorded — DegenerusAdmin.sol → handlers/coinflip.ts:275 → coinflip_daily_stakes

Solidity: `event LinkCreditRecorded(address indexed player, uint256 amount)`

player/address→text PASS; amount/uint256 parseBigInt(.).toString()→amount (numeric/text) PASS; day derived from block.timestamp → day (integer) PASS.

**Event verdict:** PASS

---

### DailyRngApplied — modules/DegenerusGameAdvanceModule.sol → handlers/daily-rng.ts:18 → daily_rng

Solidity: `event DailyRngApplied(uint32 day, uint256 rawWord, uint256 nudges, uint256 finalWord)`

| Arg | Sol | Coercion | TS | Schema col | Type | Name | Type | Coerce | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| day | uint32 | Number(parseBigInt) | day | day | integer | ✓ | ✓ | ✓ | PASS |
| rawWord | uint256 | `String(ctx.args.rawWord)` | rawWord | raw_word | text | ✓ | ✓ | ✓ (string-preserving; viem returns decimal string → persisted verbatim) | PASS |
| nudges | uint256 | `Number(parseBigInt(.nudges))` | nudges | nudges | integer | ✓ | ✓ | ✗ **silent-truncation candidate** — nudges declared `uint256` but narrowed to JS number | **FAIL (F-28-227-101)** |
| finalWord | uint256 | `String(ctx.args.finalWord)` | finalWord | final_word | text | ✓ | ✓ | ✓ | PASS |

**Event verdict:** FAIL — see F-28-227-101.

Note: In practice, `nudges` is a small counter (observed range 0..~60). Severity LOW — will not overflow under current game mechanics, but type surface allows it; contract could change. Rule 4 does not apply; we treat as LOW finding.

---

### LootboxRngApplied — DegenerusGame.sol → handlers/daily-rng.ts:40 → lootbox_rng

Solidity: `event LootboxRngApplied(uint48 index, uint256 word, uint256 requestId)`

| Arg | Sol | Coercion | TS | Schema col | Type | Name | Type | Coerce | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| index | uint48 | `Number(parseBigInt(.index))` | lootboxIndex | lootbox_index | integer | ✓ (rename) | ✓ | ✗ — **uint48 narrowed to JS number** | **FAIL (F-28-227-102)** |
| word | uint256 | String(.) | word | word | text | ✓ | ✓ | ✓ | PASS |
| requestId | uint256 | String(.) | requestId | request_id | text | ✓ | ✓ | ✓ | PASS |

**Event verdict:** FAIL — see F-28-227-102. (uint48 max = 2^48−1 ≈ 2.8×10^14; below 2^53, so NO actual overflow risk. Severity INFO — type surface leak only.)

---

### DecBurnRecorded — modules/DegenerusGameDecimatorModule.sol → handlers/decimator.ts:58 → decimator_burns + decimator_bucket_totals

Solidity: `event DecBurnRecorded(address indexed player, uint24 indexed lvl, uint8 bucket, uint8 subBucket, uint256 effectiveAmount, uint256 newTotalBurn)`

| Arg | Sol | Coercion | TS | Schema col | Type | Name | Type | Coerce | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| player | address | parseAddress | player | player | text | ✓ | ✓ | ✓ | PASS |
| lvl | uint24 | Number(parseBigInt) | level | level | integer | ✓ (lvl→level rename) | ✓ | ✓ | PASS |
| bucket | uint8 | Number(parseBigInt) | bucket | bucket | smallint | ✓ | ✓ | ✓ | PASS |
| subBucket | uint8 | Number(parseBigInt) | subBucket | sub_bucket | smallint | ✓ | ✓ | ✓ | PASS |
| effectiveAmount | uint256 | parseBigInt(.).toString() | effectiveAmount | effective_amount | numeric/text | ✓ | ✓ | ✓ | PASS |
| newTotalBurn | uint256 | parseBigInt(.).toString() | totalBurn | total_burn | numeric/text | ✓ (rename) | ✓ | ✓ | PASS |

**Event verdict:** PASS

---

### DecimatorResolved — modules/DegenerusGameDecimatorModule.sol → handlers/decimator.ts:193 → decimator_rounds

Solidity: `event DecimatorResolved(uint24 indexed lvl, uint64 packedOffsets, uint256 poolWei, uint256 totalBurn)`

| Arg | Sol | Coercion | TS | Schema col | Type | Name | Type | Coerce | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| lvl | uint24 | Number(parseBigInt) | level | level | integer | ✓ | ✓ | ✓ | PASS |
| packedOffsets | uint64 | parseBigInt(.).toString() | packedOffsets | packed_offsets | numeric/text | ✓ | ✓ | ✓ | PASS |
| poolWei | uint256 | parseBigInt(.).toString() | poolEth | pool_eth | numeric/text | ✓ (rename) | ✓ | ✓ | PASS |
| totalBurn | uint256 | parseBigInt(.).toString() | totalQualifyingBurn | total_qualifying_burn | numeric/text | ✓ (rename) | ✓ | ✓ | PASS |

**Event verdict:** PASS

---

### PlayerCredited (composite: winnings.ts + decimator.ts) — modules/Payout+GameOver+Lootbox → 2 tables

Solidity (shared across three declarations, identical 3-arg shape): `event PlayerCredited(address indexed player, address indexed recipient, uint256 amount)`

**winnings.ts:275 (handlePlayerCredited → player_winnings):**
| Arg | Sol | Coercion | TS | Schema col | Type | Verdict |
|---|---|---|---|---|---|---|
| player | address | parseAddress | player | player | text | PASS |
| recipient | address | (not read) | — | — | — | PASS (unused by winnings handler) |
| amount | uint256 | parseBigInt(.amount) → BigInt arithmetic → claimableEth/totalCredited | claimable_eth + total_credited | numeric/text | PASS |

**decimator.ts:271 (handlePlayerCreditedDecimator → decimator_claims):**
| Arg | Sol | Coercion | TS | Schema col | Type | Verdict |
|---|---|---|---|---|---|---|
| player | address | parseAddress | player | player | text | PASS |
| amount | uint256 | parseBigInt(.).toString() | ethAmount | eth_amount | numeric/text | PASS |
| (level) | derived from game_state | — | level | level | integer | PASS (documented — not in ABI) |

**Event verdict:** PASS (composite)

---

### AutoRebuyProcessed — REGISTRY ORPHAN (F-28-227-23 in 227-01; no Solidity emitter) → handlers/decimator.ts:270

Registry key exists; no event ever fires. Handler is dead code. Out of 227-02 verdict scope (no live mapping to audit).

**Event verdict:** PASS (vacuously; flagged as orphan in 227-01 F-28-227-23).

---

### BoostUsed — modules/DegenerusGameMintModule.sol → handlers/decimator.ts:304 → player_boosts

Solidity: `event BoostUsed(address indexed player, uint32 indexed day, uint256 originalAmount, uint256 boostedAmount, uint16 boostBps)`

player/address→text, day/uint32→integer, originalAmount/boostedAmount uint256→numeric/text (toString), boostBps/uint16→integer. All PASS.

**Event verdict:** PASS

---

### LootBoxBoostConsumed — modules/DegenerusGameWhaleModule.sol → handlers/decimator.ts:329 → player_boosts

Solidity: `event LootBoxBoostConsumed(address indexed player, uint32 indexed day, uint256 originalAmount, uint256 boostedAmount, uint16 boostBps)`

Same shape/handler pattern as BoostUsed. All args map cleanly. PASS.

**Event verdict:** PASS

---

### DecimatorBurn — BurnieCoin.sol → handlers/decimator.ts:356 → decimator_coin_burns

Solidity: `event DecimatorBurn(address indexed player, uint256 amountBurned, uint8 bucket)`

player/address→text PASS; amountBurned/uint256 toString→numeric/text PASS; bucket/uint8 Number→smallint PASS.

**Event verdict:** PASS

---

### TerminalDecBurnRecorded — modules/DegenerusGameDecimatorModule.sol → handlers/decimator.ts:458 → terminal_decimator_burns

Solidity: `event TerminalDecBurnRecorded(address indexed player, uint24 indexed lvl, uint8 bucket, uint8 subBucket, uint256 effectiveAmount, uint256 weightedAmount, uint256 timeMultBps)`

| Arg | Sol | Coercion | TS | Schema col | Type | Verdict |
|---|---|---|---|---|---|---|
| player | address | parseAddress | player | player | text | PASS |
| lvl | uint24 | Number(parseBigInt) | level | level | integer | PASS |
| bucket | uint8 | Number | bucket | bucket | smallint | PASS |
| subBucket | uint8 | Number | subBucket | sub_bucket | smallint | PASS |
| effectiveAmount | uint256 | toString | effectiveAmount | effective_amount | numeric/text | PASS |
| weightedAmount | uint256 | toString | weightedAmount | weighted_amount | numeric/text | PASS |
| timeMultBps | uint256 | **`Number(parseBigInt(.timeMultBps))`** | timeMultBps | time_mult_bps | integer | ✗ **uint256 narrowed** — **FAIL (F-28-227-103)** |

**Event verdict:** FAIL — F-28-227-103. Note: in-practice `timeMultBps` is a basis-points multiplier (≤10000 typical, ≤2^16 realistic), but TYPE is uint256 → TYPE-LEVEL coercion unsafe. Severity LOW.

---

### TerminalDecimatorBurn — BurnieCoin.sol → handlers/decimator.ts:487 → terminal_decimator_coin_burns

Solidity: `event TerminalDecimatorBurn(address indexed player, uint256 amountBurned)`

player/address→text PASS; amountBurned/uint256 toString→numeric/text PASS.

**Event verdict:** PASS

---

### BetPlaced — modules/DegenerusGameDegeneretteModule.sol → handlers/degenerette.ts:23 → degenerette_bets

Solidity: `event BetPlaced(address indexed player, uint32 indexed index, uint64 indexed betId, uint256 packed)`

| Arg | Sol | Coercion | TS | Schema col | Type | Verdict |
|---|---|---|---|---|---|---|
| player | address | parseAddress | player | player | text | PASS |
| index | uint32 | Number | betIndex | bet_index | integer | PASS (rename) |
| betId | uint64 | **parseBigInt(.).toString()** | betId | bet_id | numeric/text | PASS (safe coercion — uint64 preserved as string) |
| packed | uint256 | parseBigInt(.).toString() | packedData | packed_data | numeric/text | PASS (rename) |

**Event verdict:** PASS

---

### FullTicketResolved — modules/DegenerusGameDegeneretteModule.sol → handlers/degenerette.ts:49 → degenerette_results

Solidity: `event FullTicketResolved(address indexed player, uint64 indexed betId, uint8 ticketCount, uint256 totalPayout, uint32 resultTicket)`

| Arg | Sol | Coercion | TS | Schema col | Type | Verdict |
|---|---|---|---|---|---|---|
| player | address | parseAddress | player | player | text | PASS |
| betId | uint64 | parseBigInt(.).toString() | betId | bet_id | numeric/text | PASS |
| ticketCount / totalPayout / resultTicket | — | (stored in `resultData` JSONB via spread) | resultData | result_data | jsonb | ✓ (bigints serialized via raw-events convention as decimal strings) | PASS |

**Event verdict:** PASS (trailing args captured in JSONB per D-227-09 "coercion semantics" — JSONB stores decimal strings preserving uint256 precision)

---

### FullTicketResult — modules/DegenerusGameDegeneretteModule.sol → handlers/degenerette.ts:71 → degenerette_results

Solidity: `event FullTicketResult(address indexed player, uint64 indexed betId, uint8 ticketIndex, uint32 playerTicket, uint8 matches, uint256 payout)`

player PASS (parseAddress), betId PASS (toString), payout/uint256 toString→numeric/text PASS, extras → resultData JSONB PASS.

**Event verdict:** PASS

---

### PayoutCapped — modules/DegenerusGameDegeneretteModule.sol → handlers/degenerette.ts:100 → degenerette_results

Solidity: `event PayoutCapped(address indexed player, uint256 cappedEthPayout, uint256 excessConverted)`

player/address→text PASS; cappedEthPayout/uint256 toString→payout (numeric/text) PASS (rename); excessConverted/uint256 not written directly (synthetic betId='0' sentinel acknowledged in handler comment — INFO only, no FAIL).

**Event verdict:** PASS (explicit sentinel for non-existent betId is documented design; not a type-mismatch).

---

### DeityBoonIssued — modules/DegenerusGameLootboxModule.sol → handlers/deity-boons.ts:16 → deity_boons

Solidity: `event DeityBoonIssued(address indexed deity, address indexed recipient, uint32 indexed day, uint8 slot, uint8 boonType)`

deity/recipient/address→text PASS (parseAddress); day/uint32→integer PASS; slot/boonType/uint8→smallint PASS.

**Event verdict:** PASS

---

### Transfer (DEITY_PASS) — DegenerusDeityPass.sol → handlers/deity-pass.ts:61 → deity_pass_ownership + deity_pass_transfers

Solidity (ERC-721 shape): `event Transfer(address indexed from, address indexed to, uint256 indexed tokenId)`

| Arg | Sol | Coercion | TS | Schema col | Type | Verdict |
|---|---|---|---|---|---|---|
| from | address | parseAddress | fromAddress | from_address | text | PASS |
| to | address | parseAddress | to / toAddress | owner / to_address | text | PASS |
| tokenId | uint256 | `Number(parseBigInt(.tokenId ?? .value))` | tokenId | token_id | integer | ✗ **uint256→Number silent-truncation** — **FAIL (F-28-227-104)** |

**Event verdict:** FAIL — F-28-227-104. Deity Pass tokenId range is bounded by supply cap (~few thousand at most) → realistic max < 2^20; no runtime overflow, but TYPE is uint256. Severity LOW.

---

### BurnThrough — DegenerusStonk.sol → handlers/dgnrs-misc.ts:20 (no-op) → (none)

Solidity: `event BurnThrough(address indexed from, uint256 amount, uint256 ethOut, uint256 stethOut, uint256 burnieOut)`

Handler is deliberate no-op (handler comment cites raw_events capture + Transfer handles balance). All args unused.

**Event verdict:** PASS (informational no-op)

---

### UnwrapTo — DegenerusStonk.sol → handlers/dgnrs-misc.ts:31 (no-op) → (none)

Solidity: `event UnwrapTo(address indexed recipient, uint256 amount)` — handler is no-op.

**Event verdict:** PASS (informational no-op)

---

### Advance — modules/DegenerusGameAdvanceModule.sol → handlers/game-fsm.ts:173 (composite via index.ts:81) → game_state + level_transitions

Solidity: `event Advance(uint8 stage, uint24 lvl)`

| Arg | Sol | Coercion | TS | Schema col | Type | Verdict |
|---|---|---|---|---|---|---|
| stage | uint8 | Number(parseBigInt) | stage / advanceStage | advance_stage | smallint | PASS |
| lvl | uint24 | Number(parseBigInt) | level | level | integer | PASS |

Composite at index.ts:81-184 also reads `stage` and `lvl` via `Number(BigInt(String(ctx.args.stage)))` — semantically equivalent to `Number(parseBigInt)`; uint8/uint24 both safe.

**Event verdict:** PASS

---

### ProposalCreated (GNRUS shape) — GNRUS.sol → handlers/gnrus-governance.ts:270 → gnrus_proposals

Solidity: `event ProposalCreated(uint24 indexed level, uint48 indexed proposalId, address indexed proposer, address recipient)`

| Arg | Sol | Coercion | TS | Schema col | Type | Verdict |
|---|---|---|---|---|---|---|
| level | uint24 | Number(parseBigInt) | level | level | integer | PASS |
| proposalId | uint48 | parseBigInt(.).toString() | proposalId | proposal_id | numeric/text | PASS (safe string-preserving) |
| proposer | address | parseAddress | proposer | proposer | text | PASS |
| recipient | address | parseAddress | recipient | recipient | text | PASS |

**Event verdict:** PASS. (Note: ADMIN ProposalCreated collision classified by 227-01 F-28-227-07; out of IDX-02 scope.)

---

### Voted — GNRUS.sol → handlers/gnrus-governance.ts:291 → gnrus_votes

Solidity: `event Voted(uint24 indexed level, uint48 indexed proposalId, address indexed voter, bool approve, uint256 weight)`

level/uint24→integer PASS; proposalId/uint48 toString→numeric/text PASS; voter/address→text PASS; approve/bool Boolean→boolean PASS; weight/uint256 toString→numeric/text PASS.

**Event verdict:** PASS

---

### LevelResolved — GNRUS.sol → handlers/gnrus-governance.ts:314 → gnrus_level_resolutions

Solidity: `event LevelResolved(uint24 indexed level, uint48 indexed winningProposalId, address recipient, uint256 gnrusDistributed)`

All args map cleanly: level/uint24→integer, winningProposalId/uint48 toString→numeric/text, recipient/address→text, gnrusDistributed/uint256 toString→numeric/text.

**Event verdict:** PASS

---

### LevelSkipped — GNRUS.sol → handlers/gnrus-governance.ts:335 → gnrus_level_skips

Solidity: `event LevelSkipped(uint24 indexed level)` — level/uint24→integer PASS.

**Event verdict:** PASS

---

### GameOverFinalized — GNRUS.sol → handlers/gnrus-governance.ts:350 → gnrus_game_over

Solidity: `event GameOverFinalized(uint256 gnrusBurned, uint256 ethClaimed, uint256 stethClaimed)`

All three uint256 args `toString()` → numeric/text PASS.

**Event verdict:** PASS

---

### JackpotEthWin — modules/DegenerusGameJackpotModule.sol → handlers/jackpot.ts:18 → jackpot_distributions

Solidity: `event JackpotEthWin(address indexed winner, uint24 indexed level, uint8 indexed traitId, uint256 amount, uint256 ticketIndex, uint24 rebuyLevel, uint32 rebuyTickets)`

| Arg | Sol | Coercion | TS | Schema col | Type | Verdict |
|---|---|---|---|---|---|---|
| winner | address | parseAddress | winner | winner | text | PASS |
| level | uint24 | Number | level | level | integer | PASS |
| traitId | uint8 | Number | traitId | trait_id | smallint | PASS |
| amount | uint256 | toString | amount | amount | numeric/text | PASS |
| ticketIndex | uint256 | `parseBigInt(.ticketIndex)` → guarded cast to Number OR null if > MAX_SAFE_INTEGER | ticketIndex | ticket_index | integer/bigint | PASS (explicit 2^53 guard) |
| rebuyLevel | uint24 | Number | rebuyLevel | rebuy_level | integer | PASS |
| rebuyTickets | uint32 | Number | rebuyTickets | rebuy_tickets | integer | PASS |

**Event verdict:** PASS

---

### JackpotBurnieWin — modules/DegenerusGameJackpotModule.sol → handlers/jackpot.ts:45 → jackpot_distributions

Solidity: `event JackpotBurnieWin(address indexed winner, uint24 indexed level, uint8 indexed traitId, uint256 amount, uint256 ticketIndex)`

Same handler pattern: winner address, level/traitId small, amount/uint256 toString, ticketIndex guarded cast. All PASS.

**Event verdict:** PASS

---

### JackpotTicketWin — modules/DegenerusGameJackpotModule.sol → handlers/jackpot.ts:68 → jackpot_distributions

Solidity: `event JackpotTicketWin(address indexed winner, uint24 indexed ticketLevel, uint8 indexed traitId, uint32 ticketCount, uint24 sourceLevel, uint256 ticketIndex)`

winner PASS; ticketLevel/uint24→integer→level (rename) PASS; traitId/uint8→smallint PASS; ticketCount/uint32 Number→integer → `amount: ticketCount.toString()` stored in numeric/text column PASS (widening, safe); sourceLevel/uint24→integer PASS; ticketIndex guarded cast PASS.

**Event verdict:** PASS

---

### JackpotDgnrsWin — modules/DegenerusGameJackpotModule.sol → handlers/jackpot.ts:108 → jackpot_distributions

Solidity: `event JackpotDgnrsWin(address indexed winner, uint256 amount)` — winner/address→text PASS; amount/uint256 toString→numeric/text PASS; level hardcoded to 0 (documented design).

**Event verdict:** PASS

---

### JackpotWhalePassWin — modules/DegenerusGameJackpotModule.sol → handlers/jackpot.ts:124 → jackpot_distributions

Solidity: `event JackpotWhalePassWin(address indexed winner, uint24 indexed level, uint256 halfPassCount)`

winner PASS; level/uint24→integer PASS; halfPassCount/**uint256 → `Number(parseBigInt(.halfPassCount))`** → `half_pass_count` (integer) **FAIL (F-28-227-105)**. In practice halfPassCount is bounded by supply (<1000 typical); LOW severity.

**Event verdict:** FAIL — F-28-227-105.

---

### FarFutureCoinJackpotWinner — modules/DegenerusGameJackpotModule.sol → handlers/jackpot.ts:128 → jackpot_distributions

Solidity: `event FarFutureCoinJackpotWinner(address indexed winner, uint24 indexed currentLevel, uint24 indexed winnerLevel, uint256 amount)`

winner PASS; currentLevel/uint24→integer→level PASS (rename); winnerLevel/uint24→integer PASS; amount/uint256 toString→numeric/text PASS.

**Event verdict:** PASS

---

### LootBoxOpened — modules/DegenerusGameLootboxModule.sol → handlers/lootbox.ts:48 → lootbox_results

Solidity: `event LootBoxOpened(address indexed player, uint32 indexed index, uint256 amount, uint24 futureLevel, uint32 futureTickets, uint256 burnie, uint256 bonusBurnie)`

player/address→text PASS; index/uint32→integer→lootbox_index PASS (rename). Remaining args (amount, futureLevel, futureTickets, burnie, bonusBurnie) NOT PERSISTED — only rewardType='opened' + lootboxIndex stored. Deliberate by handler design (raw_events captures full args).

**Event verdict:** PASS (under-stored by design — documented pattern; data coverage is an INFO observation, not FAIL)

---

### BurnieLootBuy — modules/DegenerusGameMintModule.sol → handlers/lootbox.ts:78 → lootbox_purchases

Solidity: `event BurnieLootBuy(address indexed buyer, uint32 indexed index, uint256 burnieAmount)`

buyer/address→text→player PASS (rename semantics: buyer→player); burnieAmount/uint256 toString→burnie_spent (numeric/text) PASS (rename). Note: `index` arg not read (only recorded in raw_events).

**Event verdict:** PASS

---

### BurnieLootOpen — modules/DegenerusGameLootboxModule.sol → handlers/lootbox.ts:98 → lootbox_results

Solidity: `event BurnieLootOpen(address indexed player, uint32 indexed index, uint256 burnieAmount, uint24 ticketLevel, uint32 tickets, uint256 burnieReward)`

player/address→text PASS; index/uint32→integer→lootbox_index PASS. Extras not persisted (same pattern as LootBoxOpened). PASS.

**Event verdict:** PASS

---

### LootBoxIdx — modules/DegenerusGameMintModule.sol → handlers/lootbox.ts:106 → lootbox_results

Solidity: `event LootBoxIdx(address indexed buyer, uint32 indexed index, uint32 indexed day)`

buyer/address→text→player PASS (rename); index/uint32→integer→lootbox_index PASS; day not read (discarded). PASS.

**Event verdict:** PASS

---

### LootBoxIndexAssigned — modules/DegenerusGameWhaleModule.sol → handlers/lootbox.ts:106 (shared with LootBoxIdx) → lootbox_results

Solidity: `event LootBoxIndexAssigned(address indexed buyer, uint32 indexed index, uint32 indexed day)` — identical 3-arg shape as LootBoxIdx. Same handler — PASS.

**Event verdict:** PASS

---

### TraitsGenerated — storage/DegenerusGameStorage.sol → composite handlers/lootbox.ts:139 + traits-generated.ts:43 → traits_generated + trait_burn_tickets

Solidity: `event TraitsGenerated(address indexed player, uint24 indexed level, uint32 queueIdx, uint32 startIndex, uint32 count, uint256 entropy)`

| Arg | Sol | Coercion | TS | Schema col | Type | Verdict |
|---|---|---|---|---|---|---|
| player | address | parseAddress | player | player | text | PASS |
| level | uint24 | Number | level | (used for replay, not written directly to traits_generated; written to trait_burn_tickets) | integer | PASS |
| queueIdx | uint32 | Number | queueIdx | (used in replay) | integer | PASS |
| startIndex | uint32 | Number | startIndex | (used in replay) | integer | PASS |
| count | uint32 | Number | count | count | integer | PASS |
| entropy | uint256 | parseBigInt(.) → toString for storage, BigInt for replay | entropy | entropy | numeric/text | PASS (both representations preserved) |

**Event verdict:** PASS (composite)

---

### LootBoxReward (+DgnrsReward +WwxrpReward +WhalePassJackpot — all dispatch to handleLootBoxReward) — modules/*LootboxModule.sol → handlers/lootbox.ts:166 → lootbox_results

Solidity (LootBoxReward example): `event LootBoxReward(address indexed player, uint32 indexed day, uint8 indexed rewardType, uint256 lootboxAmount, uint256 amount)`

Handler: player/address→text PASS; day/uint32→Number→lootbox_index (integer; documented reuse of column) PASS; **remaining args spread into `rewardData` JSONB** PASS (bigints serialize to decimal strings via raw_events convention).

**Event verdict:** PASS — four rows covered (LootBoxReward, LootBoxDgnrsReward, LootBoxWwxrpReward, LootBoxWhalePassJackpot).

---

### DeityPassPurchased — storage/DegenerusGameStorage.sol → handlers/new-events.ts:18 → deity_pass_purchases

Solidity: `event DeityPassPurchased(address indexed buyer, uint8 symbolId, uint256 price, uint24 level)`

buyer/address→text PASS; symbolId/uint8 Number→smallint PASS; price/uint256 toString→numeric/text PASS; level/uint24→integer PASS.

**Event verdict:** PASS

---

### GameOverDrained — storage/DegenerusGameStorage.sol → handlers/new-events.ts:39 → game_over_events (+ resets prize_pools)

Solidity: `event GameOverDrained(uint24 level, uint256 available, uint256 claimablePool)`

level/uint24→integer PASS; available/uint256 toString→numeric/text PASS; claimablePool/uint256 toString→numeric/text PASS.

**Event verdict:** PASS

---

### FinalSwept — storage/DegenerusGameStorage.sol → handlers/new-events.ts:91 → final_sweep_events (+ resets player_winnings)

Solidity: `event FinalSwept(uint256 totalFunds)` — totalFunds/uint256 toString→numeric/text PASS.

**Event verdict:** PASS

---

### BoonConsumed — storage/DegenerusGameStorage.sol → handlers/new-events.ts:118 → boon_consumptions

Solidity: `event BoonConsumed(address indexed player, uint8 boonType, uint16 boostBps)`

All three args PASS (address→text, uint8→smallint, uint16→integer).

**Event verdict:** PASS

---

### AdminSwapEthForStEth / AdminStakeEthForStEth — storage/DegenerusGameStorage.sol → handlers/new-events.ts → admin_events

Solidity: `event AdminSwapEthForStEth(address indexed recipient, uint256 amount)` / `event AdminStakeEthForStEth(uint256 amount)`

recipient/address→text PASS; amount/uint256 toString→numeric/text PASS.

**Event verdict:** PASS (both)

---

### LinkEthFeedUpdated — DegenerusAdmin.sol → handlers/new-events.ts:173 → link_feed_updates

Solidity: `event LinkEthFeedUpdated(address indexed oldFeed, address indexed newFeed)` — both parseAddress → text PASS.

**Event verdict:** PASS

---

### DailyWinningTraits — modules/DegenerusGameJackpotModule.sol → handlers/new-events.ts:190 → daily_winning_traits

Solidity: `event DailyWinningTraits(uint32 indexed day, uint32 mainTraitsPacked, uint32 bonusTraitsPacked, uint24 bonusTargetLevel)`

day/uint32→integer PASS; mainTraitsPacked/uint32 Number→integer PASS; bonusTraitsPacked/uint32 Number→integer PASS; bonusTargetLevel/uint24 Number→integer PASS.

**Event verdict:** PASS

---

### AutoRebuyToggled / AfKingModeToggled / DecimatorAutoRebuyToggled — DegenerusGame.sol → handlers/player-settings.ts → player_settings

Each shape: `(address indexed player, bool enabled)`. Address + bool coerce via parseAddress + Boolean. All PASS.

### AutoRebuyTakeProfitSet — DegenerusGame.sol → handlers/player-settings.ts:41 → player_settings

Solidity: `event AutoRebuyTakeProfitSet(address indexed player, uint256 takeProfit)` — player PASS; takeProfit/uint256 toString→auto_rebuy_take_profit (numeric/text) PASS.

**Event verdict (all 4 settings events):** PASS

---

### LootBoxBuy — modules/DegenerusGameMintModule.sol → composite (index.ts:71) → prize-pool.ts + lootbox.ts:17 (handleLootBoxBuyRecord) → lootbox_purchases

Solidity: `event LootBoxBuy(address indexed buyer, uint32 indexed day, uint256 amount, bool presale, uint24 level)`

`handleLootBoxBuyRecord` (lootbox.ts:17): buyer/address→text→player PASS; amount/uint256 toString→eth_spent PASS (rename). Other args (day, presale, level) not persisted in this handler; `handleLootBoxBuy` (prize-pool.ts:26) is a no-op per v2.1 comment.

**Event verdict:** PASS

---

### RewardJackpotsSettled — modules/DegenerusGameAdvanceModule.sol → handlers/prize-pool.ts:73 → prize_pools

Solidity: `event RewardJackpotsSettled(uint24 indexed lvl, uint256 futurePool, uint256 claimableDelta)`

lvl: NOT read (handler only needs pool totals, not level association — by design). futurePool/uint256 toString→future_prize_pool (numeric/text) PASS; claimableDelta/uint256 parseBigInt → BigInt arithmetic → claimable_winnings (numeric/text) PASS.

**Event verdict:** PASS

---

### QuestSlotRolled — DegenerusQuests.sol → handlers/quests.ts:34 → quest_definitions

Solidity: `event QuestSlotRolled(uint32 indexed day, uint8 indexed slot, uint8 questType, uint8 flags, uint24 version)`

All args Number(parseBigInt)→integer/smallint, consistent typing. All PASS.

**Event verdict:** PASS

---

### QuestProgressUpdated — DegenerusQuests.sol → handlers/quests.ts:70 → quest_progress

Solidity: `event QuestProgressUpdated(address indexed player, uint32 indexed day, uint8 indexed slot, uint8 questType, uint128 progress, uint256 target)`

player/address→text PASS; day/uint32→integer PASS; slot/questType/uint8→smallint PASS; progress/uint128 toString→numeric/text PASS; target/uint256 toString→numeric/text PASS.

**Event verdict:** PASS

---

### QuestCompleted (ROUTER) — DegenerusQuests.sol + BurnieCoinflip.sol → handlers/quests.ts:109 (`handleQuestCompletedRouter`)

DELEGATED. Handler branches on `ADDRESS_TO_CONTRACT`.

**QUESTS branch (DegenerusQuests.sol) — full signature: `event QuestCompleted(address indexed player, uint32 indexed day, uint8 indexed slot, uint8 questType, uint32 streak, uint256 reward)`**

| Arg | Sol | Coercion | TS | Schema col | Type | Verdict |
|---|---|---|---|---|---|---|
| player | address | parseAddress | player | player | text | PASS |
| day | uint32 | Number | day | day | integer | PASS |
| slot | uint8 | Number | slot | slot | smallint | PASS |
| questType | uint8 | Number | questType | quest_type | smallint | PASS |
| streak | uint32 | (not read directly; SQL `currentStreak + 1` uses DB-side increment) | — | — | — | PASS (documented) |
| reward | uint256 | (not read) | — | — | — | PASS (unused) |

**COINFLIP/COIN branch (BurnieCoinflip.sol) — signature: `event QuestCompleted(address indexed player, uint8 questType, uint32 streak, uint256 reward)`**

Handler only reads `player` for this branch (increments streak via SQL). Other args (4-arg shape) not read. PASS.

**Event verdict:** PASS (for both emitter paths)

---

### QuestStreakBonusAwarded — DegenerusQuests.sol → handlers/quests.ts:189 → player_streaks

Solidity: `event QuestStreakBonusAwarded(address indexed player, uint16 amount, uint24 newStreak, uint32 currentDay)`

player PASS; newStreak/uint24→Number→current_streak (integer) PASS (rename); `amount` and `currentDay` not read.

**Event verdict:** PASS

---

### QuestStreakReset — DegenerusQuests.sol → handlers/quests.ts:210 → player_streaks

Solidity: `event QuestStreakReset(address indexed player, uint24 previousStreak, uint32 currentDay)` — handler reads only player; sets current_streak=0 unconditionally. PASS.

**Event verdict:** PASS

---

### QuestStreakShieldUsed — DegenerusQuests.sol → handlers/quests.ts:240 → player_streaks

Solidity: `event QuestStreakShieldUsed(address indexed player, uint16 used, uint16 remaining, uint32 currentDay)`

player PASS; remaining/uint16→Number→shields (integer) PASS.

**Event verdict:** PASS

---

### LevelQuestCompleted — DegenerusQuests.sol → handlers/quests.ts:265 → level_quest_completions

Solidity: `event LevelQuestCompleted(address indexed player, uint24 indexed level, uint8 questType, uint256 reward)`

All 4 args: address→text, uint24→integer, uint8→smallint, uint256 toString→numeric/text. All PASS.

**Event verdict:** PASS

---

### Burn (SDGNRS only per address dispatch) — StakedDegenerusStonk.sol → handlers/sdgnrs.ts:46 → sdgnrs_burns

Solidity: `event Burn(address indexed from, uint256 amount, uint256 ethOut, uint256 stethOut, uint256 burnieOut)`

Handler has field-guard: skips if `from` undefined or `burnieOut` undefined (explicitly excludes GNRUS shape). For SDGNRS path:
from/address→text→burner (rename) PASS; amount/ethOut/stethOut/burnieOut all uint256 toString→numeric/text PASS.

**Event verdict:** PASS. (GNRUS collision is F-28-227-21 in 227-01; not in 227-02 scope.)

---

### PoolTransfer — StakedDegenerusStonk.sol → handlers/sdgnrs.ts:81 → sdgnrs_pool_balances

Solidity: `event PoolTransfer(Pool indexed pool, address indexed to, uint256 amount)` (Pool is a uint8 enum)

pool/uint8 Number→integer PASS; to/address — **NOT READ** (handler subtracts balance only; `to` is a recipient but irrelevant to pool balance accounting by design) PASS (unused); amount/uint256 toString used in SQL arithmetic PASS.

**Event verdict:** PASS

---

### PoolRebalance — StakedDegenerusStonk.sol → handlers/sdgnrs.ts:108 → sdgnrs_pool_balances

Solidity: `event PoolRebalance(Pool indexed from, Pool indexed to, uint256 amount)`

from/uint8 enum Number→fromPool (integer) PASS; to/uint8 enum Number→toPool (integer) PASS; amount/uint256 toString PASS.

**Event verdict:** PASS

---

### RedemptionSubmitted — StakedDegenerusStonk.sol → handlers/sdgnrs.ts:155 → sdgnrs_redemptions

Solidity: `event RedemptionSubmitted(address indexed player, uint256 sdgnrsAmount, uint256 ethValueOwed, uint256 burnieOwed, uint32 periodIndex)`

player PASS; sdgnrsAmount/ethValueOwed/burnieOwed uint256 toString→numeric/text PASS; periodIndex/uint32→integer PASS.

**Event verdict:** PASS

---

### RedemptionResolved — StakedDegenerusStonk.sol → handlers/sdgnrs.ts:178 → sdgnrs_redemptions

Solidity: `event RedemptionResolved(uint32 indexed periodIndex, uint16 roll, uint256 rolledBurnie, uint32 flipDay)`

periodIndex/uint32→integer PASS; roll/uint16→Number→integer PASS; rolledBurnie, flipDay not read.

**Event verdict:** PASS

---

### RedemptionClaimed — StakedDegenerusStonk.sol → handlers/sdgnrs.ts:199 → sdgnrs_redemptions

Solidity: `event RedemptionClaimed(address indexed player, uint16 roll, bool flipResolved, uint256 ethPayout, uint256 burniePayout, uint256 lootboxEth)`

player PASS; flipResolved/bool Boolean→boolean→flip_won (rename) PASS; ethPayout/burniePayout/lootboxEth all uint256 toString→numeric/text PASS. `roll` arg not read (already captured via RedemptionResolved).

**Event verdict:** PASS

---

### TicketsQueued / TicketsQueuedScaled / TicketsQueuedRange — storage/DegenerusGameStorage.sol → handlers/tickets.ts → player_tickets

Solidity:
- `event TicketsQueued(address indexed buyer, uint24 targetLevel, uint32 quantity)`
- `event TicketsQueuedScaled(address indexed buyer, uint24 targetLevel, uint32 quantityScaled)`
- `event TicketsQueuedRange(address indexed buyer, uint24 startLevel, uint24 numLevels, uint32 ticketsPerLevel)`

For all three: buyer/address→text→player (rename) PASS; uint24/uint32 fields all Number→integer PASS. `quantity`/`quantityScaled`/`ticketsPerLevel` all uint32 and fit in JS Number safely → ticket_count (integer) PASS.

Note (Rule 2 observation): handler comment at tickets.ts:22 explicitly states "ticket counts are safe integers (max ~2^53), so Number() conversion from BigInt is safe here" — coercion justified.

**Event verdict:** PASS (all three)

---

### Transfer (COIN / DGNRS / SDGNRS / WWXRP) — token-balances.ts:142 (ERC20 core) → token_balances + token_supply

Solidity (ERC-20 shape): `event Transfer(address indexed from, address indexed to, uint256 amount)`

| Arg | Sol | Coercion | TS | Schema col | Type | Verdict |
|---|---|---|---|---|---|---|
| from | address | parseAddress | from | holder (when sender row) | text | PASS |
| to | address | parseAddress | to | holder (when receiver row) | text | PASS |
| amount | uint256 | parseBigInt → SQL CAST arithmetic (string-preserving) | amount | balance | numeric/text | PASS |

**Event verdict:** PASS (4 contracts routed: COIN, DGNRS, SDGNRS, WWXRP)

---

### VaultEscrowRecorded — BurnieCoin.sol → handlers/vault.ts:275 → vault_state

Solidity: `event VaultEscrowRecorded(address indexed sender, uint256 amount)`

sender/address — NOT READ (by design; vault_state is singleton, sender not tracked) PASS (unused); amount/uint256 toString → SQL arithmetic → burnie_reserve (numeric/text) PASS.

**Event verdict:** PASS

---

### VaultAllowanceSpent — BurnieCoin.sol, WrappedWrappedXRP.sol → handlers/vault.ts:304 (no-op) → (none)

Solidity: `event VaultAllowanceSpent(address indexed spender, uint256 amount)` — handler is deliberate no-op (documented). PASS.

**Event verdict:** PASS (informational no-op; both emitter contracts)

---

### Deposit (ROUTER) — DegenerusVault.sol + StakedDegenerusStonk.sol → handlers/vault.ts:54 (`handleDepositRouter`)

DELEGATED. Router branches on `ADDRESS_TO_CONTRACT`.

**VAULT branch (DegenerusVault.sol) — `event Deposit(address indexed from, uint256 ethAmount, uint256 stEthAmount, uint256 coinAmount)`** — routes to `handleVaultDeposit` (vault.ts:89):

| Arg | Sol | Coercion | TS | Schema col | Type | Verdict |
|---|---|---|---|---|---|---|
| from | address | parseAddress | depositor | depositor | text | PASS (rename) |
| ethAmount | uint256 | toString | ethAmount | eth_amount | numeric/text | PASS |
| stEthAmount | uint256 | toString | stEthAmount | st_eth_amount | numeric/text | PASS |
| coinAmount | uint256 | toString | coinAmount | coin_amount | numeric/text | PASS |

**SDGNRS branch (StakedDegenerusStonk.sol) — `event Deposit(address indexed from, uint256 ethAmount, uint256 stethAmount, uint256 burnieAmount)`** — routes to `handleSdgnrsDeposit` (sdgnrs.ts:24):

from → depositor PASS; ethAmount/stethAmount/burnieAmount all uint256 toString → numeric/text PASS.

**Event verdict:** PASS (both emitter branches)

Note: SDGNRS shape uses `stethAmount` (lowercase `eth`) while VAULT shape uses `stEthAmount` (camel `Eth`). Each handler reads the exact field name matching its branch — NO cross-branch field-name confusion.

---

### Claim — DegenerusVault.sol → handlers/vault.ts:204 → vault_claims

Solidity: `event Claim(address indexed from, uint256 sharesBurned, uint256 ethOut, uint256 stEthOut, uint256 coinOut)`

from→claimant (rename) PASS; all 4 uint256 args toString→numeric/text PASS.

**Event verdict:** PASS

---

### WhalePassClaimed — modules/DegenerusGameWhaleModule.sol → handlers/whale-pass.ts:16 → player_whale_passes

Solidity: `event WhalePassClaimed(address indexed player, address indexed caller, uint256 halfPasses, uint24 startLevel)`

| Arg | Sol | Coercion | TS | Schema col | Type | Verdict |
|---|---|---|---|---|---|---|
| player | address | parseAddress | player | player | text | PASS |
| caller | address | parseAddress | caller | caller | text | PASS |
| halfPasses | uint256 | **Number(parseBigInt(.halfPasses))** | halfPasses | half_passes | integer | ✗ **uint256 narrowed** — **FAIL (F-28-227-106)** |
| startLevel | uint24 | Number | startLevel | start_level | integer | PASS |

**Event verdict:** FAIL — F-28-227-106. In practice halfPasses ≤ small integer (collectible count); LOW severity.

---

### WinningsClaimed / ClaimableSpent — DegenerusGame.sol → handlers/winnings.ts:42 / :76 → player_winnings

Solidity:
- `event WinningsClaimed(address indexed player, address indexed caller, uint256 amount)`
- `event ClaimableSpent(address indexed player, uint256 amount, uint256 newBalance, MintPaymentKind payKind, uint256 costWei)`

WinningsClaimed: player PASS; caller not read; amount parseBigInt → BigInt arithmetic → claimable_eth/total_claimed (numeric/text) PASS.

ClaimableSpent: player PASS; amount parseBigInt → BigInt arithmetic → claimable_eth (numeric/text) PASS; newBalance/payKind/costWei all unused (handler derives state via read-then-subtract pattern — documented).

**Event verdict:** PASS (both)

---

### Donated / Unwrapped — WrappedWrappedXRP.sol → handlers/wwxrp-misc.ts (both no-ops) → (none)

Solidity: (viem-decoded from ABI; both are informational auxiliary events; handlers are no-ops per design). Not persisted; raw_events captures.

**Event verdict:** PASS (both informational no-ops)

---

## Silent-truncation + Address-drift Sweep Summary (Task 2)

### Sweep 1 — Silent-truncation hits from `Number(parseBigInt(ctx.args.*))`

Total hits: **104** lines matching pattern. Cross-referenced against Solidity arg types (227-01 extraction).

**LOW-severity findings (Solidity arg ≥ uint48):**

| # | Handler:Line | Arg | Sol type | Finding |
|---|---|---|---|---|
| 1 | daily-rng.ts:22 | nudges | uint256 | **F-28-227-101** |
| 2 | daily-rng.ts:42 | index | uint48 | **F-28-227-102** |
| 3 | decimator.ts:465 | timeMultBps | uint256 | **F-28-227-103** |
| 4 | deity-pass.ts:64 | tokenId | uint256 | **F-28-227-104** |
| 5 | jackpot.ts:112 | halfPassCount | uint256 | **F-28-227-105** |
| 6 | whale-pass.ts:19 | halfPasses | uint256 | **F-28-227-106** |

**PASS (Solidity arg ≤ uint32), no finding emitted:**
All remaining 98 `Number(parseBigInt(...))` calls operate on `uint8`/`uint16`/`uint24`/`uint32` args — within JS safe-integer range. Explicit examples spot-checked:
- `affiliate.ts:93,121,152,173` — `level/uint24` PASS
- `coinflip.ts:94,125` — `day/uint32`, `rewardPercent/uint16` PASS
- `decimator.ts:58..82, 130, 162, 195, 273, 358, 393` — `lvl/uint24`, `bucket/uint8`, `subBucket/uint8`, `day/uint32`, `targetLevel/uint24`, `boostBps/uint16` PASS
- `quests.ts:36..40, 72..74, 115, 116, 127, 189, 240, 268, 269` — all uint8/uint24/uint32 PASS
- `game-fsm.ts:40,41` — stage/uint8, lvl/uint24 PASS
- `sdgnrs.ts:81,109,110,159,180,181` — pool (uint8 enum), periodIndex/uint32, roll/uint16 PASS
- `new-events.ts:31,33,51,131,132,202,203,204,205` — symbolId/uint8, level/uint24, boonType/uint8, boostBps/uint16, day/uint32, *TraitsPacked/uint32, bonusTargetLevel/uint24 PASS
- `jackpot.ts:19,20,24,25,46,47,69..72,111,130,131` — level/uint24, traitId/uint8, rebuyLevel/uint24, rebuyTickets/uint32, ticketLevel/uint24, ticketCount/uint32, sourceLevel/uint24, currentLevel/uint24, winnerLevel/uint24 PASS
- `tickets.ts:26,27,38,39,50,51,52` — targetLevel/uint24, quantity|quantityScaled|ticketsPerLevel/uint32, startLevel/uint24, numLevels/uint24 PASS
- `lootbox.ts:50,89,108,132..135,161` — index/uint32, count/uint32, level/uint24, queueIdx/uint32, startIndex/uint32, day/uint32 PASS
- `degenerette.ts:25` — index/uint32 PASS
- `traits-generated.ts:27..30` — level/uint24, queueIdx/uint32, startIndex/uint32, count/uint32 PASS
- `gnrus-governance.ts:26,47,70,91` — level/uint24 PASS
- `deity-boons.ts:18..20` — day/uint32, slot/uint8, boonType/uint8 PASS
- `baf-jackpot.ts:24` — lvl/uint24 PASS
- `index.ts:85,94,216` — stage/uint8, lvl/uint24, day/uint32 PASS (via `Number(BigInt(String(...)))` — semantic equivalent)

### Sweep 2 — Address-case drift

`rg -n "ctx\.args\.\w+" database/src/handlers/*.ts | rg -v "parseAddress|parseBigInt|\.toString"` returned **22 hits** (including index.ts composite). Manual classification:

| Handler:Line | Arg | Sol type | Unsafe? |
|---|---|---|---|
| index.ts:85,94,216 | stage, lvl, day | uint8/uint24/uint32 | No — wrapped in `Number(BigInt(String(...)))` |
| affiliate.ts:34,61 | code | bytes32 | No — `String(.)` is correct for bytes32 |
| affiliate.ts:63 | locked | bool | No — `Boolean(.)` |
| coinflip.ts:95,216 | win, enabled | bool | No |
| coinflip.ts:99 | bountyRecipient | address | No — conditionally wrapped: `ctx.args.bountyRecipient ? parseAddress(ctx.args.bountyRecipient) : null` |
| daily-rng.ts:21,23,43,44 | rawWord, finalWord, word, requestId | uint256 | No — `String(.)` preserves viem's decimal-string conversion |
| player-settings.ts:23,74,99 | enabled | bool | No |
| sdgnrs.ts:24,47,52 (comments) | from, burnieOut | (none — comments + guards) | No — inside `if` guard in sdgnrs.ts:52 |
| sdgnrs.ts:205 | flipResolved | bool | No |
| gnrus-governance.ts:50 | approve | bool | No |
| degenerette.ts:27 | packed | uint256 | No — null-check then parseBigInt |

**Zero address-type args read without `parseAddress`.** No F-28-227-1NN finding stubs required for this sweep.

### Sweep 3 — Field-name mismatches (Name match? = ✗)

All verdict rows inspected have `Name match? = ✓`. Several use explicit renames (e.g., `buyer`→`player`, `lvl`→`level`, `creditedFlip`→`amount`, `newTotal`→`totalEarned`/`totalStake`, `packed`→`packedData`, `sender`→`owner`, `recordAmount`→`biggestFlipAmount`, `bounty`→`currentBounty`, `sharesBurned`→same, `burner`/`from`→`burner` (SDGNRS context), `buyer`/`from`→`depositor`, `from`→`fromAddress`, `to`→`toAddress`, `tokenId`→`token_id`, `rewardPercent`→`reward_percent`). Every rename is a deliberate handler semantic and matches the Phase 226 locked schema column. **No silent field-swap (e.g., `from` written to `to_address`) observed.**

**Zero Name-match FAIL findings.**

---

## Finding Stubs (F-28-227-101..106; block range F-28-227-101..199 reserved)

#### F-28-227-101: DailyRngApplied.nudges silent truncation via `Number(parseBigInt(...))`

- **Severity:** LOW
- **Direction:** schema↔handler
- **Phase:** 227
- **Requirement:** IDX-02
- **File:** /home/zak/Dev/PurgeGame/database/src/handlers/daily-rng.ts:22
- **Event source:** /home/zak/Dev/PurgeGame/degenerus-audit/contracts/modules/DegenerusGameAdvanceModule.sol:76 (arg type `uint256 nudges`)
- **Target column:** `daily_rng.nudges` (integer per 226-01-SCHEMA-MIGRATION-DIFF.md)
- **Resolution:** RESOLVED-CODE — replace `Number(parseBigInt(ctx.args.nudges))` with `parseBigInt(ctx.args.nudges).toString()` and widen column to `numeric`/`text`; OR narrow Solidity arg to `uint32` if runtime range justifies.
- **Evidence:** line 22 `const nudges = Number(parseBigInt(ctx.args.nudges));` against `uint256` Solidity type.

#### F-28-227-102: LootboxRngApplied.index uint48 narrowed to JS number

- **Severity:** INFO (uint48 max ≈ 2.8×10^14 < 2^53 = 9×10^15 — no runtime overflow; type-surface leak only)
- **Direction:** schema↔handler
- **Phase:** 227
- **Requirement:** IDX-02
- **File:** /home/zak/Dev/PurgeGame/database/src/handlers/daily-rng.ts:42
- **Event source:** /home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusGame.sol (or inherited module; `event LootboxRngApplied(uint48 index, uint256 word, uint256 requestId)`)
- **Target column:** `lootbox_rng.lootbox_index` (integer)
- **Resolution:** INFO-ACCEPTED (uint48 fits JS number) OR RESOLVED-CODE to `parseBigInt(.).toString()` for uniformity.
- **Evidence:** line 42 `const lootboxIndex = Number(parseBigInt(ctx.args.index));`

#### F-28-227-103: TerminalDecBurnRecorded.timeMultBps silent truncation

- **Severity:** LOW
- **Direction:** schema↔handler
- **Phase:** 227 | **Requirement:** IDX-02
- **File:** /home/zak/Dev/PurgeGame/database/src/handlers/decimator.ts:465
- **Event source:** /home/zak/Dev/PurgeGame/degenerus-audit/contracts/modules/DegenerusGameDecimatorModule.sol:600 (`uint256 timeMultBps`)
- **Target column:** `terminal_decimator_burns.time_mult_bps` (integer)
- **Resolution:** RESOLVED-CODE — narrow contract arg to `uint32` (realistic range ≤2^32 for a bps multiplier) OR widen DB column to numeric + `parseBigInt(.).toString()`.
- **Evidence:** line 465 `const timeMultBps = Number(parseBigInt(ctx.args.timeMultBps));`

#### F-28-227-104: DeityPass Transfer.tokenId uint256 narrowed to JS number

- **Severity:** LOW
- **Direction:** schema↔handler
- **Phase:** 227 | **Requirement:** IDX-02
- **File:** /home/zak/Dev/PurgeGame/database/src/handlers/deity-pass.ts:64
- **Event source:** /home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusDeityPass.sol:59 (ERC-721 `uint256 indexed tokenId`)
- **Target column:** `deity_pass_ownership.token_id` / `deity_pass_transfers.token_id` (integer)
- **Resolution:** RESOLVED-CODE — `parseBigInt(ctx.args.tokenId).toString()` + column widened to `numeric`/`text` (standard practice for ERC-721 tokenId).
- **Evidence:** line 64 `const tokenId = Number(parseBigInt(ctx.args.tokenId ?? ctx.args.value));`

#### F-28-227-105: JackpotWhalePassWin.halfPassCount silent truncation

- **Severity:** LOW
- **Direction:** schema↔handler
- **Phase:** 227 | **Requirement:** IDX-02
- **File:** /home/zak/Dev/PurgeGame/database/src/handlers/jackpot.ts:112
- **Event source:** /home/zak/Dev/PurgeGame/degenerus-audit/contracts/modules/DegenerusGameJackpotModule.sol:111 (`uint256 halfPassCount`)
- **Target column:** `jackpot_distributions.half_pass_count` (integer)
- **Resolution:** RESOLVED-CODE — either narrow contract arg to `uint32` (realistic cap), or `parseBigInt(.).toString()` + widen column.
- **Evidence:** line 112 `const halfPassCount = Number(parseBigInt(ctx.args.halfPassCount));`

#### F-28-227-106: WhalePassClaimed.halfPasses silent truncation

- **Severity:** LOW
- **Direction:** schema↔handler
- **Phase:** 227 | **Requirement:** IDX-02
- **File:** /home/zak/Dev/PurgeGame/database/src/handlers/whale-pass.ts:19
- **Event source:** /home/zak/Dev/PurgeGame/degenerus-audit/contracts/modules/DegenerusGameWhaleModule.sol:65 (`uint256 halfPasses`)
- **Target column:** `player_whale_passes.half_passes` (integer)
- **Resolution:** RESOLVED-CODE — narrow Solidity arg to `uint32` or widen DB column + `parseBigInt(.).toString()`.
- **Evidence:** line 19 `const halfPasses = Number(parseBigInt(ctx.args.halfPasses));`

---

## Closure

**Events covered (227-02 input set):** 95 rows (87 PROCESSED + 8 DELEGATED→PROCESSED per 227-01 handoff).
**Event-level PASS:** 89
**Event-level FAIL:** 6 (DailyRngApplied, LootboxRngApplied, TerminalDecBurnRecorded, Transfer(DEITY_PASS), JackpotWhalePassWin, WhalePassClaimed)
**Per-arg-row verdicts emitted across all three dimensions (Name / Type / Coercion):** exhaustive above.

**Finding IDs consumed:** F-28-227-101..F-28-227-106 (6 stubs).
**Block remaining:** F-28-227-107..F-28-227-199 (93 IDs unused; room for 227-03 / 229 if any cross-cut).
**Zero collisions** with 227-01 (F-28-227-01..23) or 227-03's reserved two-hundred-series block.
