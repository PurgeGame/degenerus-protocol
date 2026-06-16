# v65.0 — BURNIE → FLIP Rename: Canonical Surface Map

> Built from an 8-agent read-only classification of all 34 burnie-touching contract files + the test/scripts surface (workflow `flip-rename-surface-map`). Raw per-file data: the run-`w1pb7zlpr` result. This doc is the execution spec.

## 0. Scope — DECIDED 2026-06-16: **BROAD (full rebrand)**

§2/§3/§5 + **§4 (the 11 `coin`-as-token identifiers)** all apply. Generic `coin` stays: `burnCoin`, `mintForGame`, `PRICE_COIN_UNIT`, `IDegenerusCoin`, `IVaultCoin`, all `coinflip*`. Micro-naming locked: `IBurnieCoin`→`IFLIP`, `IBurnieTombstone`→`IFlipTombstone`, `OnlyBurnieCoin`/`onlyBurnieCoin`→`OnlyFLIP`/`onlyFLIP`, `name`→`"Degenerus Gambling Token"`.

## 1. Invariants

- **Full FUNCTIONAL PARITY** — only names change. Zero logic change. The post-rename bytecode differs only by selectors / event topics / the two metadata strings.
- Rename changes selectors + event topics → the off-chain indexer/ABI must re-vendor (manifest §6).
- v64 byte-freeze is intentionally broken by this milestone → re-attest at close.

## 2. Contract / interface / file renames (load-bearing — do these in §7 order)

| Source | Target | File rename | Impact |
|---|---|---|---|
| `BurnieCoinflipPlayer` / `IBurnieCoinflipPlayer` | `ICoinflipPlayer` | — | abi/deploy |
| `IBurnieCoinflipLinkReward` | `ICoinflipLinkReward` | — | abi |
| `IBurnieCoinflipAffiliate` | `ICoinflipAffiliate` | — | abi |
| `IBurnieCoinflip` | `ICoinflip` | `interfaces/IBurnieCoinflip.sol` → `interfaces/ICoinflip.sol` | abi/deploy |
| `BurnieCoinflip` | `Coinflip` | `BurnieCoinflip.sol` → `Coinflip.sol` | abi/deploy |
| `IBurnieCoin` | `IFLIP` *(inline iface in Coinflip.sol; see §9)* | — | abi |
| `BurnieCoin` | `FLIP` | `BurnieCoin.sol` → `FLIP.sol` | abi/deploy |
| `IBurnieTombstone` | `IFlipTombstone` *(see §9)* | — | — |

**On-chain metadata strings (`FLIP.sol`):** `name "Burnies"` → `"Degenerus Gambling Token"`; `symbol "BURNIE"` → `"FLIP"`.

## 3. Token-identifier renames (NARROW + BROAD) — by category

**Functions (selector-impacting):** `mintBurnie`→`mintFlip` · `redeemBurnie`→`redeemFlip` · `claimAfkingBurnie`→`claimAfkingFlip` · `withdrawRedeemedBurnie`→`withdrawRedeemedFlip` · `burnieReserve`→`flipReserve` · `claimCoinflipsFromBurnie`→`claimCoinflipsFromFlip` · `consumeBurnieForSalvage`→`consumeFlipForSalvage` · `previewSalvageBurnieBacking`→`previewSalvageFlipBacking` · `resolveBurnieSpinsFromBox`→`resolveFlipSpinsFromBox`. **Params:** `forceMintBurnie`→`forceMintFlip` · `burnieMintQty`→`flipMintQty` · `burnieReward`→`flipReward`.

**Internal functions:** `_settlePendingBurnie`→`_settlePendingFlip` · `_ethToBurnieValue`→`_ethToFlipValue` · `_ethToBurnie`→`_ethToFlip` · `_redeemBurnieFor`→`_redeemFlipFor` · `_packBurnieToWhole`→`_packFlipToWhole` · `_unpackWholeBurnieToWei`→`_unpackWholeFlipToWei` · `_quoteFarFutureBurnieSplit`→`_quoteFarFutureFlipSplit`.

**Events / errors / modifiers (topic-impacting):** `JackpotBurnieWin`→`JackpotFlipWin` (event) · `OnlyBurnieCoin`→`OnlyFLIP` (error) · `onlyBurnieCoin`→`onlyFLIP` (modifier).

**Constants (ALLCAPS):** `BURNIE_TOMBSTONE_WEI`→`FLIP_TOMBSTONE_WEI` · `LOOTBOX_LARGE_BURNIE_{LOW,HIGH}_{BASE,STEP}_BPS`→`…_FLIP_…` · `PRESALE_BOX_BURNIE_{LOW,HIGH}_{BASE,STEP}_BPS`→`…_FLIP_…` · `BOX_SPIN_TYPE_BURNIE`/`BOX_BURNIE_SPINS`/`BOX_BURNIE_SPIN_TAG`→`…_FLIP…` · `QUEST_TYPE_MINT_BURNIE`→`QUEST_TYPE_MINT_FLIP` · `FIRST_SYMBOL_BONUS_BURNIE`→`FIRST_SYMBOL_BONUS_FLIP` · `FIRST_QUADRANT_BURNIE`→`FIRST_QUADRANT_FLIP` · `LR_PENDING_BURNIE_{SHIFT,MASK}`→`LR_PENDING_FLIP_…` · `LR_BURNIE_SCALE`→`LR_FLIP_SCALE` · `CURRENCY_BURNIE`→`CURRENCY_FLIP` · `MAX_SPINS_BURNIE`→`MAX_SPINS_FLIP` · `MIN_BET_BURNIE`→`MIN_BET_FLIP` · `REGULAR_BURNIE`→`REGULAR_FLIP` · `"MINT_BURNIE"`→`"MINT_FLIP"` (string literal).

**Variables / struct fields / camelCase (`burnie*`→`flip*`):** `burnieOut` · `burnieEscrow` · `burnieEscrowWhole` · `burnieEscrowWei` · `burnieEscrowed` · `burnieMint` · `burnieMintUnits` · `burnieHeld` · `burniePaid` · `burnieBal` · `burnieEth` · `burnieBps` · `burnieBudget` · `burnieReserve` · `burnieWindowOpen` · `burnieTokens` · `claimableBurnie`→`claimableFlip` · `pendingBurnie`→`pendingFlip` · `freshBurnie`→`freshFlip` · `ownedBurnie`→`ownedFlip` · `totalBurnie`→`totalFlip` · `targetBurnie`→`targetFlip` · lowercase var `burnie`→`flip`.

**PascalCase catch-all:** `Burnie`→`Flip` and any `Burnie<X>` naming the token (`BurnieValue`→`FlipValue`, `BurnieBacking`→`FlipBacking`, `BurnieSpins`→`FlipSpins`, `BurnieForSalvage`→`FlipForSalvage`, `BurnieSplit`→`FlipSplit`, `BurnieOut`→`FlipOut`, …) — exact-match per occurrence.

**Comments / docstrings:** ~200 `BURNIE` comment tokens → `FLIP` across 17 files; plus `BurnieCoin._adjustDecimatorBucket` (comment ref to the contract) → `FLIP._adjustDecimatorBucket`.

## 4. BROAD-scope-only: `coin`-as-the-token identifiers (apply ONLY if BROAD chosen)

`coinOut`→`flipOut` (11) · `coinShare`→`flipShare` (6) · `coinToken`→`flipToken` (5) · `coin`→`flip` (4, **risky — bare generic; per-occurrence only**) · `coinPlayer`→`flipPlayer` (3) · `FAR_FUTURE_COIN_{BPS,SAMPLES,TAG}`→`FAR_FUTURE_FLIP_…` (3) · `COIN_JACKPOT_TAG`/`COIN_LEVEL_TAG`→`FLIP_JACKPOT_TAG`/`FLIP_LEVEL_TAG` (2) · `FarFutureCoinJackpotWinner`→`FarFutureFlipJackpotWinner` (event, topic-impacting) · `_runCoinJackpot`→`_runFlipJackpot` · `payDailyCoinJackpot`→`payDailyFlipJackpot` · `redeemableCoinBacking`→`redeemableFlipBacking` (**selector; mappers split KEEP-vs-RENAME — BROAD renames it**).

Even under BROAD, **do NOT** touch: `burnCoin`, `mintForGame`, `PRICE_COIN_UNIT`, `IDegenerusCoin`, `IVaultCoin`, or any `coinflip*` (the action).

## 5. KEEP carve-outs (NEVER rename — exact-match preserve)

- **Creator persona:** `@author Burnie Degenerus` (18 occ / 17 files), `Burnie Degenerus` (2), the creator email `burnie@degener.us` (3 files).
- **The verb `burn`:** `burn`, `_burn`, `burnCoin`, `burnCoinForSalvage`, `burnForCoinflip`, `burnForGame`, `burnForSdgnrs`, `burnAtGameOver`, `tombstoneAtGameOver`, `traitBurnTicket`, `BurnThrough`, decimator burn-tracking (`decBurn`, `recordDecBurn`, `DecBurnRecorded`, `TerminalDecBurnRecorded`, `recordTerminalDecBurn`, `totalBurn`/`newBurn`/`prevBurn`/`entryBurn`/`weightedBurn`), `mint`/`mintForGame`/`vaultMintTo`, `decurse`, `smite`, `balanceOf`/`transfer`.
- **The action `coinflip`/`flip`:** all `coinflip*` and action-`flip*` (`coinflip` 101 occ, `creditFlip` 23, `consumeCoinflipsForBurn` ⚠ KEEP, `claimCoinflips`, `previewClaimCoinflips`, `_addDailyFlip`, `_flipStake`, `BiggestFlipUpdated`, `CoinflipDeposit`, `QUEST_TYPE_FLIP`, `SEED_FLIP_*`, `OnlyFlipCreditors`, `redeemableCoinBacking` under NARROW, etc.).

**Exact-match rule:** replace whole tokens with word boundaries; never substring-replace.

## 6. External-impact manifest (indexer / ABI re-vendor)

**Selector changes (functions):** `mintBurnie`→`mintFlip`, `redeemBurnie`→`redeemFlip`, `claimAfkingBurnie`→`claimAfkingFlip`, `withdrawRedeemedBurnie`→`withdrawRedeemedFlip`, `burnieReserve`→`flipReserve`, `claimCoinflipsFromBurnie`→`claimCoinflipsFromFlip`, `consumeBurnieForSalvage`→`consumeFlipForSalvage`, `previewSalvageBurnieBacking`→`previewSalvageFlipBacking`, `resolveBurnieSpinsFromBox`→`resolveFlipSpinsFromBox`, params `forceMintBurnie`/`burnieMintQty`/`burnieReward`. Error: `OnlyBurnieCoin`→`OnlyFLIP`. **BROAD also:** `redeemableCoinBacking`→`redeemableFlipBacking`.

**Event-topic changes:** `JackpotBurnieWin`→`JackpotFlipWin`; the `burnie`/`burnieEscrowWei`/`burnieEscrowed` event-params. **BROAD also:** `FarFutureCoinJackpotWinner`→`FarFutureFlipJackpotWinner`.

**Contract artifact renames** (break artifact-name loaders): `BurnieCoin`→`FLIP`, `BurnieCoinflip`→`Coinflip`, `IBurnieCoinflip`→`ICoinflip`.

## 7. Hazards + ordering (replace LONGER tokens first)

1. `IBurnieCoinflip{Player,LinkReward,Affiliate}` → before `IBurnieCoinflip` → before `BurnieCoinflip` → before `BurnieCoin` (each is a prefix of the prior). `IBurnieCoin` after `IBurnieCoinflip`.
2. `BURNIE_<X>` constants before bare `BURNIE`.
3. `burnie<X>`/`Burnie<X>` camel/Pascal before any bare token replace.
4. Post-rename collision check: confirm no renamed token identifier equals an existing action identifier (e.g. ensure `flipOut`/`flipShare` etc. don't pre-exist).

## 8. Test / scripts surface (45 files, ~900+ refs)

**File renames (8):** `test/unit/BurnieCoin.test.js`→`FLIP.test.js` · `test/unit/BurnieCoinflip.test.js`→`Coinflip.test.js` · `test/stat/WholeBurnieFloorInvariant.test.js`→`WholeFlipFloorInvariant.test.js` · `test/unit/LootboxWholeBurnieFloor.test.js`→`LootboxWholeFlipFloor.test.js` · `test/fuzz/BurnieCoinInvariants.t.sol`→`FLIPInvariants.t.sol` · `test/fuzz/BurnieEmissionSeeds.t.sol`→`FlipEmissionSeeds.t.sol` · `test/fuzz/BurnieRedeemWindow.t.sol`→`FlipRedeemWindow.t.sol` · `test/fuzz/BurnieTombstone.t.sol`→`FlipTombstone.t.sol`.

**Artifact-name dependencies (must update together):** `scripts/lib/predictAddresses.js` `KEY_TO_CONTRACT` (`'COIN'→'BurnieCoin'`, `'COINFLIP'→'BurnieCoinflip'` → `'FLIP'`/`'Coinflip'`); `test/helpers/deployFixture.js` (`deployFullProtocol` loads by contract name); any hardcoded `forge-out/BurnieCoin.sol/…` paths; `package.json` `test:stat` glob (renamed file).

**Change categories:** 36 files w/ contract-name refs · 2 selector-changing fn refs · 2 error-name refs · ERC20 name/symbol assertions (`BurnieCoin.test.js`) · 30 comment/description refs · 6 audit-doc/JSON files (`audit/site/data/*`, `audit/GAS-AUDIT-*.json`). ⚠ The test-inventory agent wrongly proposed `consumeCoinflipsForBurn`→`consumeFlipForBurn`; that's **KEEP** (contract mapper authoritative).

## 9. Open judgment calls

1. **SCOPE: NARROW vs BROAD** (§0/§4) — *the user decision.*
2. **`IBurnieCoin`** (inline token interface in Coinflip.sol) → `IFLIP` vs `IFlip`. Default `IFLIP` (matches contract `FLIP`).
3. **`IBurnieTombstone`** → `IFlipTombstone` (keep token prefix) vs `ITombstone` (drop). Default `IFlipTombstone`.
4. **`OnlyBurnieCoin`/`onlyBurnieCoin`** → `OnlyFLIP`/`onlyFLIP` (consistent w/ contract name). Confirm.
5. **`name`** display string → `"Degenerus Gambling Token"` (confirm long name).
6. `IDegenerusCoin` / `IVaultCoin` (other token interface views) → **KEEP** (no `burnie`; generic).
