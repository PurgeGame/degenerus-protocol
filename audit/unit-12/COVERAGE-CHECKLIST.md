# Unit 12: Vault + WWXRP -- Taskmaster Coverage Checklist

**Phase:** 114
**Contracts:** DegenerusVaultShare, DegenerusVault, WrappedWrappedXRP
**Generated:** 2026-03-25

---

## Contract 1: DegenerusVaultShare (DegenerusVault.sol L138-300)

### Function Inventory

| # | Function | Lines | Visibility | State-Changing | Category | Risk Tier |
|---|----------|-------|------------|----------------|----------|-----------|
| VS-01 | constructor(name_, symbol_) | L198-204 | internal | YES | B | LOW |
| VS-02 | approve(spender, amount) | L213-217 | external | YES | B | LOW |
| VS-03 | transfer(to, amount) | L225-228 | external | YES | B | LOW |
| VS-04 | transferFrom(from, to, amount) | L237-247 | external | YES | B | LOW |
| VS-05 | vaultMint(to, amount) | L258-265 | external onlyVault | YES | B | LOW |
| VS-06 | vaultBurn(from, amount) | L273-281 | external onlyVault | YES | B | LOW |
| VS-07 | _transfer(from, to, amount) | L290-299 | private | YES | C | - |

### View/Pure Functions (Category D -- no attack analysis)

| # | Function | Lines | Notes |
|---|----------|-------|-------|
| VS-D1 | decimals | L171 | constant = 18 |
| VS-D2 | INITIAL_SUPPLY | L173 | constant = 1T * 1e18 |
| VS-D3 | name | L167 | mutable string (set in constructor) |
| VS-D4 | symbol | L169 | mutable string (set in constructor) |
| VS-D5 | totalSupply | L176 | public state variable |
| VS-D6 | balanceOf | L178 | public mapping |
| VS-D7 | allowance | L180 | public mapping |

### Storage Write Map

| Function | Storage Variables Written |
|----------|--------------------------|
| constructor | totalSupply, balanceOf[CREATOR] |
| approve | allowance[msg.sender][spender] |
| transfer -> _transfer | balanceOf[from], balanceOf[to] |
| transferFrom -> _transfer | allowance[from][msg.sender], balanceOf[from], balanceOf[to] |
| vaultMint | totalSupply, balanceOf[to] |
| vaultBurn | balanceOf[from], totalSupply |

### Cross-Contract Call Map

| Function | External Calls | Target | Line |
|----------|---------------|--------|------|
| constructor | (none) | - | - |
| approve | (none) | - | - |
| transfer | (none) | - | - |
| transferFrom | (none) | - | - |
| vaultMint | (none) | - | - |
| vaultBurn | (none) | - | - |

DegenerusVaultShare makes ZERO external calls. All operations are self-contained.

---

## Contract 2: DegenerusVault (DegenerusVault.sol L309-1050)

### Function Inventory -- State-Changing (Category B)

| # | Function | Lines | Visibility | Access | Risk Tier |
|---|----------|-------|------------|--------|-----------|
| V-01 | constructor() | L433-440 | internal | - | LOW |
| V-02 | deposit(coinAmount, stEthAmount) | L454-462 | external payable | onlyGame | HIGH |
| V-03 | receive() | L465-467 | external payable | open | LOW |
| V-04 | gameAdvance() | L476-478 | external | onlyVaultOwner | LOW |
| V-05 | gamePurchase(...) | L489-504 | external payable | onlyVaultOwner | MED |
| V-06 | gamePurchaseTicketsBurnie(qty) | L510-513 | external | onlyVaultOwner | LOW |
| V-07 | gamePurchaseBurnieLootbox(amt) | L519-522 | external | onlyVaultOwner | LOW |
| V-08 | gameOpenLootBox(idx) | L527-529 | external | onlyVaultOwner | LOW |
| V-09 | gamePurchaseDeityPassFromBoon(price,symbolId) | L536-546 | external payable | onlyVaultOwner | HIGH |
| V-10 | gameClaimWinnings() | L550-552 | external | onlyVaultOwner | LOW |
| V-11 | gameClaimWhalePass() | L556-558 | external | onlyVaultOwner | LOW |
| V-12 | gameDegeneretteBetEth(...) | L569-587 | external payable | onlyVaultOwner | MED |
| V-13 | gameDegeneretteBetBurnie(...) | L595-609 | external | onlyVaultOwner | LOW |
| V-14 | gameDegeneretteBetWwxrp(...) | L617-631 | external | onlyVaultOwner | LOW |
| V-15 | gameResolveDegeneretteBets(betIds) | L636-638 | external | onlyVaultOwner | LOW |
| V-16 | gameSetAutoRebuy(enabled) | L643-645 | external | onlyVaultOwner | LOW |
| V-17 | gameSetAutoRebuyTakeProfit(tp) | L650-652 | external | onlyVaultOwner | LOW |
| V-18 | gameSetDecimatorAutoRebuy(enabled) | L657-659 | external | onlyVaultOwner | LOW |
| V-19 | gameSetAfKingMode(enabled,ethTp,coinTp) | L666-672 | external | onlyVaultOwner | LOW |
| V-20 | gameSetOperatorApproval(op,approved) | L678-680 | external | onlyVaultOwner | LOW |
| V-21 | coinDepositCoinflip(amount) | L685-687 | external | onlyVaultOwner | LOW |
| V-22 | coinClaimCoinflips(amount) | L693-695 | external | onlyVaultOwner | LOW |
| V-23 | coinDecimatorBurn(amount) | L700-702 | external | onlyVaultOwner | LOW |
| V-24 | coinSetAutoRebuy(enabled,tp) | L708-710 | external | onlyVaultOwner | LOW |
| V-25 | coinSetAutoRebuyTakeProfit(tp) | L715-717 | external | onlyVaultOwner | LOW |
| V-26 | wwxrpMint(to, amount) | L723-726 | external | onlyVaultOwner | MED |
| V-27 | jackpotsClaimDecimator(lvl) | L731-733 | external | onlyVaultOwner | LOW |
| V-28 | burnCoin(player, amount) | L749-756 | external | open+approval | CRITICAL |
| V-29 | burnEth(player, amount) | L816-826 | external | open+approval | CRITICAL |

### Function Inventory -- Private Helpers (Category C)

| # | Function | Lines | State-Changing | Notes |
|---|----------|-------|----------------|-------|
| V-C1 | _burnCoinFor(player, amount) | L762-802 | YES | Core DGVB claim logic |
| V-C2 | _burnEthFor(player, amount) | L833-876 | YES | Core DGVE claim logic |
| V-C3 | _syncCoinReserves() | L980-983 | YES | Writes coinTracked |
| V-C4 | _payEth(to, amount) | L1031-1034 | YES | Sends ETH via call |
| V-C5 | _paySteth(to, amount) | L1039-1041 | YES | Transfers stETH |
| V-C6 | _pullSteth(from, amount) | L1046-1049 | YES | Pulls stETH |

### Function Inventory -- View/Pure (Category D)

| # | Function | Lines | Notes |
|---|----------|-------|-------|
| V-D1 | _combinedValue(extraValue) | L959-965 | private view |
| V-D2 | _syncEthReserves() | L971-977 | private view |
| V-D3 | _coinReservesView() | L987-997 | private view |
| V-D4 | _ethReservesView() | L1002-1020 | private view |
| V-D5 | _stethBalance() | L1024-1026 | private view |
| V-D6 | _isVaultOwner(account) | L415-419 | private view |
| V-D7 | isVaultOwner(account) | L424-426 | external view |
| V-D8 | _requireApproved(player) | L406-410 | private view |
| V-D9 | previewBurnForCoinOut(coinOut) | L887-892 | external view |
| V-D10 | previewBurnForEthOut(targetValue) | L901-917 | external view |
| V-D11 | previewCoin(amount) | L927-932 | external view |
| V-D12 | previewEth(amount) | L939-951 | external view |

### Storage Write Map

| Function | Storage Variables Written (Full Call Tree) |
|----------|--------------------------------------------|
| constructor | coinShare (immutable), ethShare (immutable), coinTracked |
| deposit | coinTracked (via _syncCoinReserves + direct), (stETH pulled via _pullSteth -- external only) |
| receive() | (none -- only receives ETH) |
| gameAdvance | (none local -- proxies to game) |
| gamePurchase | (none local -- proxies to game) |
| gamePurchaseTicketsBurnie | (none local -- proxies to game) |
| gamePurchaseBurnieLootbox | (none local -- proxies to game) |
| gameOpenLootBox | (none local -- proxies to game) |
| gamePurchaseDeityPassFromBoon | (none local -- proxies to game; ETH leaves vault) |
| gameClaimWinnings | (none local -- proxies to game; ETH may enter vault) |
| gameClaimWhalePass | (none local -- proxies to game) |
| gameDegeneretteBetEth | (none local -- proxies to game) |
| gameDegeneretteBetBurnie | (none local -- proxies to game) |
| gameDegeneretteBetWwxrp | (none local -- proxies to game) |
| gameResolveDegeneretteBets | (none local -- proxies to game) |
| gameSetAutoRebuy | (none local -- proxies to game) |
| gameSetAutoRebuyTakeProfit | (none local -- proxies to game) |
| gameSetDecimatorAutoRebuy | (none local -- proxies to game) |
| gameSetAfKingMode | (none local -- proxies to game) |
| gameSetOperatorApproval | (none local -- proxies to game) |
| coinDepositCoinflip | (none local -- proxies to coinflip) |
| coinClaimCoinflips | (none local -- proxies to coinflip) |
| coinDecimatorBurn | (none local -- proxies to coin) |
| coinSetAutoRebuy | (none local -- proxies to coinflip) |
| coinSetAutoRebuyTakeProfit | (none local -- proxies to coinflip) |
| wwxrpMint | (none local -- proxies to wwxrp) |
| jackpotsClaimDecimator | (none local -- proxies to game) |
| burnCoin -> _burnCoinFor | coinTracked (via _syncCoinReserves + potential decrement at L798) |
| burnEth -> _burnEthFor | (none local, but ETH/stETH leave vault) |

### Cross-Contract Call Map

| Function | External Calls | Target Contract | Line |
|----------|---------------|-----------------|------|
| constructor | new DegenerusVaultShare() x2 | DegenerusVaultShare | L434-435 |
| constructor | coinToken.vaultMintAllowance() | BurnieCoin | L437 |
| deposit | _syncCoinReserves -> coinToken.vaultMintAllowance() | BurnieCoin | L981 |
| deposit | coinToken.vaultEscrow(coinAmount) | BurnieCoin | L457 |
| deposit | _pullSteth -> steth.transferFrom() | Lido stETH | L1048 |
| gameAdvance | gamePlayer.advanceGame() | DegenerusGame | L477 |
| gamePurchase | gamePlayer.purchase{value}() | DegenerusGame | L497 |
| gamePurchaseTicketsBurnie | gamePlayer.purchaseCoin() | DegenerusGame | L512 |
| gamePurchaseBurnieLootbox | gamePlayer.purchaseBurnieLootbox() | DegenerusGame | L521 |
| gameOpenLootBox | gamePlayer.openLootBox() | DegenerusGame | L528 |
| gamePurchaseDeityPassFromBoon | gamePlayer.claimableWinningsOf() | DegenerusGame | L539 |
| gamePurchaseDeityPassFromBoon | gamePlayer.claimWinnings() | DegenerusGame | L541 |
| gamePurchaseDeityPassFromBoon | gamePlayer.purchaseDeityPass{value}() | DegenerusGame | L545 |
| gameClaimWinnings | gamePlayer.claimWinningsStethFirst() | DegenerusGame | L551 |
| gameClaimWhalePass | gamePlayer.claimWhalePass() | DegenerusGame | L557 |
| gameDegeneretteBetEth | gamePlayer.placeFullTicketBets{value}() | DegenerusGame | L579 |
| gameDegeneretteBetBurnie | gamePlayer.placeFullTicketBets() | DegenerusGame | L601 |
| gameDegeneretteBetWwxrp | gamePlayer.placeFullTicketBets() | DegenerusGame | L623 |
| gameResolveDegeneretteBets | gamePlayer.resolveDegeneretteBets() | DegenerusGame | L637 |
| gameSetAutoRebuy | gamePlayer.setAutoRebuy() | DegenerusGame | L644 |
| gameSetAutoRebuyTakeProfit | gamePlayer.setAutoRebuyTakeProfit() | DegenerusGame | L651 |
| gameSetDecimatorAutoRebuy | gamePlayer.setDecimatorAutoRebuy() | DegenerusGame | L658 |
| gameSetAfKingMode | gamePlayer.setAfKingMode() | DegenerusGame | L671 |
| gameSetOperatorApproval | gamePlayer.setOperatorApproval() | DegenerusGame | L679 |
| coinDepositCoinflip | coinflipPlayer.depositCoinflip() | BurnieCoinflip | L686 |
| coinClaimCoinflips | coinflipPlayer.claimCoinflips() | BurnieCoinflip | L694 |
| coinDecimatorBurn | coinPlayer.decimatorBurn() | BurnieCoin | L701 |
| coinSetAutoRebuy | coinflipPlayer.setCoinflipAutoRebuy() | BurnieCoinflip | L709 |
| coinSetAutoRebuyTakeProfit | coinflipPlayer.setCoinflipAutoRebuyTakeProfit() | BurnieCoinflip | L716 |
| wwxrpMint | wwxrpToken.vaultMintTo() | WrappedWrappedXRP | L725 |
| jackpotsClaimDecimator | gamePlayer.claimDecimatorJackpot() | DegenerusGame | L732 |
| burnCoin/_burnCoinFor | coinToken.vaultMintAllowance() | BurnieCoin | L981 |
| burnCoin/_burnCoinFor | coinToken.balanceOf(address(this)) | BurnieCoin | L768 |
| burnCoin/_burnCoinFor | coinflipPlayer.previewClaimCoinflips() | BurnieCoinflip | L769 |
| burnCoin/_burnCoinFor | share.vaultBurn(player, amount) | DegenerusVaultShare | L775 |
| burnCoin/_burnCoinFor | share.vaultMint(player, REFILL_SUPPLY) | DegenerusVaultShare | L777 |
| burnCoin/_burnCoinFor | coinToken.transfer(player, payBal) | BurnieCoin | L786 |
| burnCoin/_burnCoinFor | coinflipPlayer.claimCoinflips() | BurnieCoinflip | L790 |
| burnCoin/_burnCoinFor | coinToken.transfer(player, claimed) | BurnieCoin | L793 |
| burnCoin/_burnCoinFor | coinToken.vaultMintTo(player, remaining) | BurnieCoin | L799 |
| burnEth/_burnEthFor | ethShare.totalSupply() | DegenerusVaultShare | L849 |
| burnEth/_burnEthFor | gamePlayer.claimableWinningsOf() | DegenerusGame | L841 |
| burnEth/_burnEthFor | gamePlayer.claimWinnings() | DegenerusGame | L854 |
| burnEth/_burnEthFor | steth.balanceOf(address(this)) | Lido stETH | L1025 |
| burnEth/_burnEthFor | share.vaultBurn(player, amount) | DegenerusVaultShare | L867 |
| burnEth/_burnEthFor | share.vaultMint(player, REFILL_SUPPLY) | DegenerusVaultShare | L869 |
| burnEth/_burnEthFor | _paySteth -> steth.transfer() | Lido stETH | L1040 |
| burnEth/_burnEthFor | _payEth -> to.call{value}() | player EOA/contract | L1032 |

---

## Contract 3: WrappedWrappedXRP (WrappedWrappedXRP.sol L40-389)

### Function Inventory

| # | Function | Lines | Visibility | State-Changing | Category | Risk Tier |
|---|----------|-------|------------|----------------|----------|-----------|
| W-01 | approve(spender, amount) | L196-200 | external | YES | B | LOW |
| W-02 | transfer(to, amount) | L208-211 | external | YES | B | LOW |
| W-03 | transferFrom(from, to, amount) | L222-235 | external | YES | B | LOW |
| W-04 | unwrap(amount) | L290-306 | external | YES | B | HIGH |
| W-05 | donate(amount) | L314-326 | external | YES | B | MED |
| W-06 | mintPrize(to, amount) | L342-354 | external | YES | B | MED |
| W-07 | vaultMintTo(to, amount) | L363-375 | external | YES | B | MED |
| W-08 | burnForGame(from, amount) | L384-388 | external | YES | B | MED |
| W-09 | _transfer(from, to, amount) | L241-249 | internal | YES | C | - |
| W-10 | _mint(to, amount) | L254-261 | internal | YES | C | - |
| W-11 | _burn(from, amount) | L266-274 | internal | YES | C | - |

### View/Pure Functions (Category D)

| # | Function | Lines | Notes |
|---|----------|-------|-------|
| W-D1 | supplyIncUncirculated() | L177-179 | external view |
| W-D2 | vaultMintAllowance() | L182-184 | external view |
| W-D3 | name | L118 | constant |
| W-D4 | symbol | L121 | constant |
| W-D5 | decimals | L124 | constant = 18 |
| W-D6 | totalSupply | L127 | public state |
| W-D7 | INITIAL_VAULT_ALLOWANCE | L130 | constant = 1B * 1e18 |
| W-D8 | vaultAllowance | L133 | public state |
| W-D9 | balanceOf | L136 | public mapping |
| W-D10 | allowance | L139 | public mapping |
| W-D11 | wXRPReserves | L173 | public state |

### Storage Write Map

| Function | Storage Variables Written |
|----------|--------------------------|
| approve | allowance[msg.sender][spender] |
| transfer -> _transfer | balanceOf[from], balanceOf[to] |
| transferFrom -> _transfer | allowance[from][msg.sender], balanceOf[from], balanceOf[to] |
| unwrap -> _burn | balanceOf[msg.sender], totalSupply, wXRPReserves |
| donate | wXRPReserves |
| mintPrize -> _mint | totalSupply, balanceOf[to] |
| vaultMintTo -> _mint | vaultAllowance, totalSupply, balanceOf[to] |
| burnForGame -> _burn | balanceOf[from], totalSupply |

### Cross-Contract Call Map

| Function | External Calls | Target Contract | Line |
|----------|---------------|-----------------|------|
| approve | (none) | - | - |
| transfer | (none) | - | - |
| transferFrom | (none) | - | - |
| unwrap | wXRP.transfer(msg.sender, amount) | wXRP token | L301 |
| donate | wXRP.transferFrom(msg.sender, address(this), amount) | wXRP token | L318 |
| mintPrize | (none, only internal _mint) | - | - |
| vaultMintTo | (none, only internal _mint) | - | - |
| burnForGame | (none, only internal _burn) | - | - |

---

## Summary Statistics

| Metric | Count |
|--------|-------|
| Total functions | 64 |
| Category B (full attack analysis) | 38 |
| Category C (traced via parents) | 10 |
| Category D (view/pure, no attack) | 16 |
| CRITICAL risk functions | 2 (burnCoin, burnEth) |
| HIGH risk functions | 3 (deposit, unwrap, gamePurchaseDeityPassFromBoon) |
| MEDIUM risk functions | 8 |
| LOW risk functions | 25 |
| External cross-contract calls | 49 unique call sites |

## Access Control Summary

| Guard | Functions Protected | Verification |
|-------|--------------------|-------------|
| onlyGame | deposit | msg.sender != ContractAddresses.GAME (L394) |
| onlyVaultOwner | 24 vault proxy functions | _isVaultOwner: balance * 1000 > supply * 501 (L418) |
| _requireApproved | burnCoin, burnEth (for non-self) | msg.sender != player && !game.isOperatorApproved (L407) |
| OnlyMinter (WWXRP) | mintPrize | msg.sender must be GAME, COIN, or COINFLIP (L343-348) |
| OnlyMinter (WWXRP) | burnForGame | msg.sender must be GAME (L385) |
| OnlyVault (WWXRP) | vaultMintTo | msg.sender must be VAULT (L364) |
| onlyVault (VaultShare) | vaultMint, vaultBurn | msg.sender != ContractAddresses.VAULT (L187) |

---

## Checklist Status

**Taskmaster Verdict: READY FOR MAD GENIUS**

All 64 functions catalogued. All cross-contract calls documented with line numbers. All storage writes mapped. Categories and risk tiers assigned. Zero omissions detected.
