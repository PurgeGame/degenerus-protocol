# 325 — Call-Graph Attestation: BTOMB (item 5) + HERO (item 6)

## Scope

READ-ONLY grep-attestation of every `file:line` anchor cited in the v48.0 plan docs for
**item 5 (BTOMB — gameover BURNIE tombstone, flood VAULT mint allowance)** and **item 6 (HERO —
Degenerette hero 2-pt rescale to 9-point max)** against the v47.0-closure baseline HEAD
`da5c9d50989707c8964a9411e68c51ca1b1a25f2`.

Plan docs attested:
- `.planning/PLAN-V48-GAMEOVER-BURNIE-TOMBSTONE.md` (item 5)
- `.planning/PLAN-V48-DEGENERETTE-HERO-2PT-RESCALE.md` (item 6)

## Sources of truth (this attestation)

- `contracts/BurnieCoin.sol` (744 lines) — Supply struct / vaultAllowance / views / GAME-gated
  allowance-increase path / `_toUint128` cap
- `contracts/modules/DegenerusGameGameOverModule.sol` — `burnAtGameOver` invocation + `handleFinalSweep`
- `contracts/modules/DegenerusGameDegeneretteModule.sol` (1221 lines) — scoring / payout / award /
  WWXRP / hero anchors
- `contracts/modules/DegenerusGameJackpotModule.sol` + `contracts/DegenerusGame.sol` — HERO-06
  `dailyHeroWagers` / `_rollHeroSymbol` no-leak

**Attestation-method note (baseline-anchored):** The working tree's `contracts/` is byte-identical
to baseline HEAD `da5c9d50989707c8964a9411e68c51ca1b1a25f2` — `git diff --name-only da5c9d50 HEAD
-- contracts/` returns ZERO files. Every grep is against the live tree and is implicitly resolved at
the baseline. Read from `contracts/` ONLY.

## Verdict legend

- `MATCH` — anchor lands on the claimed line.
- `SHIFTED(±N)` — content present, N lines off the claimed line/range.
- `ABSENT` — content not found / materially diverged (surfaced as an IMPL blocker).

---

## A. BTOMB (item 5) — `BurnieCoin.sol` + `GameOverModule` anchor reconciliation

| # | Anchor (claimed) | ACTUAL | Verdict |
|---|---|---|---|
| B1 | `:172-180` `struct Supply { ... uint128 vaultAllowance; }` packed with `totalSupply`; ctor seeds vaultAllowance 2_000_000 ether | `BurnieCoin.sol`: `struct Supply { uint128 totalSupply; uint128 vaultAllowance; }` :172-175 (two `uint128` co-packed in one 32-byte slot, NatSpec :171); `_supply` ctor seed `Supply({totalSupply: 0, vaultAllowance: uint128(2_000_000 ether)});` :179-180 | **MATCH** (struct :172-175; the 2_000_000-ether seed at :179-180 — the claimed :172-180 envelope is exact) |
| B2 | `:256` `totalSupply()` EXCLUDES vaultAllowance | `function totalSupply() external view returns (uint256) { return _supply.totalSupply; }` :256-258 (NatSpec :255 "excludes ... VAULT allowance") | **MATCH** (returns `totalSupply` only — vaultAllowance excluded from circulating) |
| B3 | `:263-264` `supplyIncUncirculated()` INCLUDES vaultAllowance | `function supplyIncUncirculated() external view returns (uint256) { return uint256(_supply.totalSupply) + uint256(_supply.vaultAllowance); }` :263-265 | **MATCH** (includes vaultAllowance — the overhang signal lands here) |
| B4 | `:270-271` `vaultMintAllowance()` returns vaultAllowance | `function vaultMintAllowance() external view returns (uint256) { return _supply.vaultAllowance; }` :270-272 | **MATCH** |
| B5 | `:370` `_supply.vaultAllowance += amount128;` (the GAME-gated allowance-increase path BTOMB reuses) | `_supply.vaultAllowance += amount128;` at **:370** — but note: :370 is inside a mint-side RECLASSIFICATION path (paired with `_supply.totalSupply -= amount128;` :369, moving circulating→allowance, NOT a clean increase). The CLEAN GAME-gated allowance-increase BTOMB should reuse is **`vaultEscrow(uint256 amount)` :557-567**: gated `sender != GAME && sender != VAULT) revert OnlyVault()` :559-562, `uint128 amount128 = _toUint128(amount);` :563, `_supply.vaultAllowance += amount128;` :565 (unchecked) | **MATCH** + **PATH CLARIFICATION** (the `+= amount128` increase pattern lands at :370 AND :565; the GAME-gated entrypoint BTOMB should reuse for a one-shot flood is `vaultEscrow` :557-567 — GAME-callable, increases `vaultAllowance` only, does NOT touch circulating `totalSupply`. The :370 site is a reclassification, not the right reuse target) |
| B6 | GameOverModule: `burnAtGameOver` invoked at `:142`; `handleFinalSweep` `:192` (+30d) | `DegenerusGameGameOverModule.sol`: `dgnrs.burnAtGameOver();` at **:142** (preceded by `charityGameOver.burnAtGameOver();` :141); `function handleFinalSweep() external` :192 with `if (block.timestamp < _goRead(GO_TIME_SHIFT, GO_TIME_MASK) + 30 days) return;` :194 | **MATCH** (the gameover-drain one-shot site for the BTOMB call; gated on `gameOver()` via the GameOverModule, one-shot) |
| B7 | feasibility — 1Q BURNIE = 1e36 wei « uint128 max (~3.4e38), ~340× headroom; checked add / cap | `uint128` max = 3.402…e38; 1e36 wei = ~0.3% of the field (~340× headroom). `_toUint128(uint256 value)` :350-353 reverts `SupplyOverflow` if `value > type(uint128).max` :351. **Note:** `vaultEscrow`'s add is `unchecked` (:564-565) — `_toUint128` caps the per-call ARGUMENT at uint128 max but does NOT guard `existing + amount` against wrapping. At gameover the existing vaultAllowance is bounded (seeded 2e24 + escrows), so `existing + 1e36` is far below 1e38; but the BTOMB SPEC must add an explicit checked-add / cap so the flood constant + existing can't overflow (the plan's own "Verify at SPEC" minor) | **CONFIRMED FEASIBLE** (1e36 « uint128 max; field-width + the existing increase path both exist. The unchecked add in `vaultEscrow` means the one-shot guard is Plan 03's open packing item — flagged, not a blocker; the flood value is structurally tiny vs the field) |

### BTOMB exact structures

**`BurnieCoin.sol:172-180` (the packed supply slot + 2_000_000-ether seed):**
```solidity
    struct Supply {
        uint128 totalSupply;
        uint128 vaultAllowance;
    }
    Supply private _supply =
        Supply({totalSupply: 0, vaultAllowance: uint128(2_000_000 ether)});
```

**`BurnieCoin.sol:557-567` (the GAME-gated clean allowance-increase path BTOMB reuses):**
```solidity
    function vaultEscrow(uint256 amount) external {
        address sender = msg.sender;
        if (
            sender != ContractAddresses.GAME &&
            sender != ContractAddresses.VAULT
        ) revert OnlyVault();
        uint128 amount128 = _toUint128(amount);
        unchecked {
            _supply.vaultAllowance += amount128;
        }
        emit VaultEscrowRecorded(sender, amount);
    }
```

**Key BTOMB finding:** the flood mechanic is sound — `vaultEscrow` (GAME-callable) bumps
`vaultAllowance` only, leaving circulating `totalSupply()` untouched (B2), so nothing keyed off
circulating supply is distorted; the signal lands in `supplyIncUncirculated()` / `vaultMintAllowance()`
/ `balanceOf(VAULT)`. 1e36 wei is ~0.3% of the `uint128` field. The one open item for Plan 03 is the
explicit checked-add/cap on the one-shot flood (the increase site is `unchecked`); the gameover-drain
one-shot call site (`burnAtGameOver` :142 / GameOverModule) is the right hook.

---

## B. HERO (item 6) — `DegeneretteModule.sol` anchor reconciliation

### Deleted constructs (item 6 net-deletes these)

| # | Anchor (claimed) | ACTUAL | Verdict |
|---|---|---|---|
| H1 | `_applyHeroMultiplier` (the standalone EV-neutral hero multiplier — DELETE) | `function _applyHeroMultiplier(... uint8 matches, uint8 heroQuadrant, ...)` :1070-1095; symbol-match lookup `multiplier = (packed >> (uint256(matches - 2) * 16)) & MASK_16;` :1090, else `multiplier = HERO_PENALTY;` :1092, `return (payout * multiplier) / HERO_SCALE;` :1094 | **MATCH** (the multiplier function to net-delete) |
| H2 | `HERO_BOOST_N0..N4_PACKED` (`:339-342`) | `HERO_BOOST_N0_PACKED` :339, `N1` :340, `N2` :341, `N3` :342, `N4_PACKED` :343 | **SHIFTED(+1 on the N4 line)** (claimed :339-342 covers N0..N3; N4 is at :343 — the 5-table block is :339-343; content present, all 5 tables there to delete) |
| H3 | `HERO_PENALTY` | `uint16 private constant HERO_PENALTY = 9500;` :344 | **MATCH** |
| H4 | `HERO_SCALE` (`:331` per the interfaces block) | `uint16 private constant HERO_SCALE = 10_000;` at **:345** (the `:331` anchor is a NatSpec line describing the HERO_SCALE identity, not the declaration) | **SHIFTED(+14)** (the declaration is at :345; :331 is the NatSpec derivation comment `... = HERO_SCALE for each (M, N)`. Content present; the constant to delete is :345) |
| H5 | M<2 / M=8 hero-multiplier carve-out in `_fullTicketPayout` (DELETE the branch) | `if (matches >= 2 && matches < 8) { payout = _applyHeroMultiplier(...); }` :1047-1059 (the carve-out: hero adjustment only applied for M∈[2,8), NatSpec :1043-1046) | **MATCH** (the `matches >= 2 && matches < 8` gate is the carve-out the rescale removes when dispatching on `S` instead) |

### Kept / edited constructs

| # | Anchor (claimed) | ACTUAL | Verdict |
|---|---|---|---|
| H6 | `FT_HERO_SHIFT` decode (KEPT — still need heroQuadrant for scoring) | `uint256 private constant FT_HERO_SHIFT = 237;` :323; decode `uint8 heroQuadrant = uint8((packed >> (FT_HERO_SHIFT + 1)) & MASK_2);` :637 (in `_resolveFullTicketBet`); encode :903-906 | **MATCH** (KEPT — heroQuadrant decode at resolve time is reused by the new `_score`; no bet-layout change) |
| H7 | `heroQuadrant >= 4` revert (KEPT — hero mandatory) | `if (heroQuadrant >= 4) revert InvalidBet();` :503 (entry-point validation; NatSpec :368 "inputs >= 4 (including 0xFF) revert with InvalidBet") | **MATCH** (KEPT — hero quadrant stays mandatory) |
| H8 | `_countMatches` → hero-aware `_score(...) ∈ {0..9}` (EDIT) | `function _countMatches(uint32 playerTicket, uint32 resultTicket) private pure returns (uint8 matches)` :932-962; counts 8 axes (4 color :943 + 4 symbol :952) → {0..8}; called at :682 | **MATCH** (the function the rescale converts to `_score(playerTicket, resultTicket, heroQuadrant)` = 7 ordinary axes + 2·hero-symbol-match → {0..9}) |
| H9 | `_resolveFullTicketBet` (the resolve path; decodes heroQuadrant) | `function _resolveFullTicketBet(...)` :622; decodes `heroQuadrant` :637; `matches = _countMatches(...)` :682; `payout = _fullTicketPayout(... matches, ... heroQuadrant)` :685-695; `emit FullTicketResult(... matches ...)` :696-... :701; `if (currency == CURRENCY_ETH && matches >= 6) _awardDegeneretteDgnrs(player, amountPerTicket, matches);` :723-724 | **MATCH** (the resolve path that wires score→payout→award→event; all the rescale's call edges land here) |
| H10 | `_fullTicketPayout` — drop hero-multiplier branch, dispatch on S (EDIT) | `function _fullTicketPayout(... uint8 matches, ... uint8 heroQuadrant)` :1008-1059; `uint8 N = _countGoldQuadrants(playerTicket);` :1018; `basePayoutBps = _getBasePayoutBps(N, matches);` :1019; WWXRP bucket :1023-... ; hero-multiplier branch :1047-1059 (to drop) | **MATCH** |
| H11 | `QUICK_PLAY_PAYOUTS_N0..N4_PACKED` (`:256-260`) + the separate M=8 slot (9-bucket layout → widen to 10) | packed M=0..7 tables `QUICK_PLAY_PAYOUTS_N0_PACKED` :256 … `N4_PACKED` :260; separate M=8 jackpot constants `QUICK_PLAY_PAYOUT_N0_M8` :264 … `N4_M8` :268; dispatch `_getBasePayoutBps` :1104-1118 (`if (matches >= 8) return QUICK_PLAY_PAYOUT_N{N}_M8;` :1105-1110, else `(packed >> (matches * 32)) & 0xFFFFFFFF` :1118) | **MATCH** (current 9-bucket layout confirmed: M=0..7 packed @ :256-260 + separate M=8 @ :264-268; the rescale widens to S=0..9 with both S=8 AND S=9 likely separate `uint256` per N — the re-pack is Plan 03's open packing item) |
| H12 | `_getBasePayoutBps(N, S)` | `function _getBasePayoutBps(uint8 N, uint8 matches) private pure returns (uint256)` :1104-1119 | **MATCH** |
| H13 | `_awardDegeneretteDgnrs` + `DEGEN_DGNRS_6/7/8_BPS` (re-map thresholds, D-03 → S≥7) | `DEGEN_DGNRS_6_BPS = 400` :203, `DEGEN_DGNRS_7_BPS = 800` :204, `DEGEN_DGNRS_8_BPS = 1500` :205; `_awardDegeneretteDgnrs(...)` :1196: `if (matchCount == 6) bps = DEGEN_DGNRS_6_BPS;` :1202, `== 7 → 7_BPS` :1203, else `8_BPS` :1204; gated `matches >= 6` at the call :723 | **MATCH** (current thresholds key on `matches >= 6`; D-03 re-maps to the new scale at `S≥7` — shift-by-one) |
| H14 | `_wwxrpBonusBucket` / `_wwxrpFactor` / `WWXRP_FACTORS_N*_PACKED` (re-map buckets to 10-pt scale) | `_wwxrpBonusBucket(uint8 matches)` :966-970 (`if (matches < 5) return 0; return matches; // 5,6,7,8` — buckets 5..8); `_wwxrpFactor(uint8 N, uint8 bucket)` :980-... (`WWXRP_FACTORS_N0..N4_PACKED` :283-287); used in `_fullTicketPayout` :1023-1032 | **MATCH** (current WWXRP buckets 5..8 on the M-scale; the rescale re-maps to the S-scale + recomputes factors to hold ETH +5% / WWXRP high-roi EV exact per N) |
| H15 | `FullTicketResult.matches` (0-8) doc/range → (0-9) | `event FullTicketResult(... uint8 matches, ...)` :97-... :102 (NatSpec `@param matches Number of attribute matches (0-8).` :95); also `_countMatches` NatSpec `(0-8)` :931, `_getBasePayoutBps` `(0..8)` :1102, `_fullTicketPayout` `(0-8)` :1001 | **MATCH** (the `matches` field + its `(0-8)` doc range; widens to `(0-9)` — flag the off-chain indexer/event-range concern, out of scope per PROJECT.md) |
| H16 | v47 `resolveBets` write-batch shape (DGAS — byte-identical constraint) | `function resolveBets(address player, uint64[] calldata betIds) external` :415; cross-bet payout accumulator threaded `resolveBets → _resolveBet → _resolveFullTicketBet → _distributePayout`, flushed ONCE (NatSpec :387-396; lootbox-share summed per-betId :620-622; "byte-identical to per-spin. Flushed once by resolveBets" :806) | **MATCH** (the v47 write-batch shape is present; HERO recalibration is payout-SHAPE only and must stay write-batch byte-identical to the per-spin baseline — the DGAS constraint) |
| H17 | `_roiBpsFromScore` activity-score curve (UNTOUCHED per D-02) | `function _roiBpsFromScore(...)` :1130-... ; called `uint256 roiBps = _roiBpsFromScore(activityScore);` :644 | **MATCH** (the activity-score ROI curve is untouched by the rescale — neutral-EV + activity scaling preserved) |
| H18 | `_countGoldQuadrants` → N table selector (UNTOUCHED) | `function _countGoldQuadrants(uint32 ticket) private pure returns (uint8 count)` :919; `N = _countGoldQuadrants(playerTicket)` :1018 | **MATCH** (N selector unchanged; the new `A`-distribution still depends only on N → EV-equality per-N holds) |

### HERO-06 no-leak row

| # | Anchor (claimed) | ACTUAL | Verdict |
|---|---|---|---|
| H19 | `dailyHeroWagers` / `_rollHeroSymbol` (DegenerusGame:2693 + JackpotModule) reads WAGERED hero symbols, NOT per-bet scores — the `matches`-range change cannot leak in | **WRITE side** (DegeneretteModule :538-553): on `CURRENCY_ETH`, `uint8 heroSymbol = uint8(customTicket >> (heroQuadrant * 8)) & 7;` :541 (the player's WAGERED symbol, decoded from the bet ticket — NOT `matches`/`_countMatches`); accumulates `wagerUnit` into `dailyHeroWagers[day][heroQuadrant]` keyed by symbol :544-552. **READ side**: `DegenerusGame.sol:2693` getter `uint256 packed = dailyHeroWagers[day][quadrant];`; `_rollHeroSymbol(uint8 day, ...)` (JackpotModule :1475) reads `dailyHeroWagers[day][q]` :1489 ("most wagered across all quadrants", NatSpec :1421-1426). The jackpot consumes the WAGER POOL, never `matches`/`S` | **CONFIRMED NO-LEAK** (the daily-hero-symbol jackpot reads wagered symbols from `dailyHeroWagers`, written from the bet's chosen `heroSymbol` — entirely disjoint from the per-bet `matches`/`_countMatches` score. Widening `matches` 0-8→0-9 (`S`) cannot leak into the daily-hero jackpot: different state, different code path) |

### HERO exact current `_fullTicketPayout` hero-multiplier carve-out (the branch the rescale drops)

```solidity
        // _DegeneretteModule.sol:1047-1059
        if (matches >= 2 && matches < 8) {
            payout = _applyHeroMultiplier(
                payout,
                N,
                matches,
                heroQuadrant,
                ...
            );
        }
```

The rescale net-deletes `_applyHeroMultiplier` (:1070-1095), the 5 `HERO_BOOST_N*_PACKED` tables
(:339-343), `HERO_PENALTY` (:344), `HERO_SCALE` (:345), and this `matches >= 2 && matches < 8`
carve-out (:1047-1059) — replacing the hero meaning with the `+2` in the new `_score`. `FT_HERO_SHIFT`
decode (:323/:637) and the `heroQuadrant >= 4` revert (:503) are KEPT (hero stays mandatory + stored,
no bet-layout change). The jackpot relabel `S=9 ≡ M=8` reuses the same `QUICK_PLAY_PAYOUT_N{N}_M8`
constants' physical event (identical odds).

---

## C. Roll-up

- **BTOMB (item 5) anchors:** 7 attested — **6 MATCH / 0 SHIFTED / 0 ABSENT**, with one **PATH
  CLARIFICATION** (B5): the clean GAME-gated allowance-increase entrypoint BTOMB should reuse is
  `vaultEscrow` (`:557-567`), not the `:370` reclassification site (which pairs the `+= amount128`
  with a `totalSupply -= amount128`). B7 is **CONFIRMED FEASIBLE** (1e36 wei « uint128 max ~3.4e38).
- **HERO (item 6) anchors:** 19 attested — **17 MATCH / 2 SHIFTED / 0 ABSENT.** The two SHIFTED are
  immaterial: H2 `HERO_BOOST_N4_PACKED` at :343 (claimed :339-342 covers N0..N3; the full 5-table
  block is :339-343) and H4 `HERO_SCALE` declaration at :345 (the `:331` anchor is its NatSpec
  derivation comment, not the decl). Every deleted construct, every kept/edited construct, and the
  `FullTicketResult.matches` (0-8) range all verify; **HERO-06 is CONFIRMED NO-LEAK** (H19).

**IMPL-blocker count for items 5+6: 0.**

**Discretion / feasibility verdicts (explicit):**
- **BTOMB field/path-exists:** CONFIRMED — `uint128 vaultAllowance` field (:174), `totalSupply()`
  excludes (:256) / `supplyIncUncirculated()` + `vaultMintAllowance()` include (:263-272), the
  GAME-gated `vaultEscrow` allowance-increase path (:557-567), and the gameover-drain one-shot hook
  (`burnAtGameOver` :142 / GameOverModule) all exist. The one-shot checked-add/cap is Plan 03's open
  packing item (the increase site is `unchecked`); 1e36 « uint128 max so structurally safe.
- **HERO-06 no-leak:** CONFIRMED — `dailyHeroWagers`/`_rollHeroSymbol` read the WAGERED hero symbol
  pool (DegeneretteModule write :541, DegenerusGame read :2693, JackpotModule `_rollHeroSymbol`
  :1475/:1489), NOT per-bet `matches`/`S` scores. The 0-8→0-9 range change cannot leak in.

*Anchors will shift once the Phase 326 batched diff lands — re-grep at IMPL time. BTOMB (BurnieCoin +
GameOverModule) and HERO (DegeneretteModule) are ISOLATED from the items 2/3/4/7 shared-file surface,
so Plan 03's shared-signature reconciliation does not depend on these — but BTOMB co-hooks the
gameover-drain (`burnAtGameOver` :142) that item 4 (POOL) also folds into, so the GameOverModule
edit-order is a Plan 03 coordination point. The HERO constants are byte-reproduced by
`derive_5_tables.py` at TST (Phase 327), never hand-typed.*
