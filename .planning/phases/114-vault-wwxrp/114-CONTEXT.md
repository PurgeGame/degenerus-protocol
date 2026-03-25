# Phase 114: Vault + WWXRP - Context

**Gathered:** 2026-03-25 (auto mode)
**Status:** Ready for execution

<domain>
## Phase Boundary

Adversarial audit of DegenerusVault.sol (including DegenerusVaultShare), and WrappedWrappedXRP.sol -- the protocol's multi-asset vault and wrapped joke token. This phase examines every state-changing function across all three contracts using the three-agent system (Taskmaster -> Mad Genius -> Skeptic). The contracts handle:

**DegenerusVaultShare (DGVB/DGVE):**
- Minimal ERC20 share tokens for two independent share classes
- Vault-controlled mint/burn (only vault can mint/burn shares)
- Standard transfer/approve for users

**DegenerusVault:**
- Multi-asset vault with two independent share classes (DGVE for ETH+stETH, DGVB for BURNIE)
- Game-only deposits (ETH via msg.value, stETH via transferFrom, BURNIE via virtual escrow)
- Share redemption via burnCoin (DGVB -> BURNIE) and burnEth (DGVE -> ETH+stETH)
- Vault owner gameplay proxy (>50.1% DGVE supply required)
- WWXRP vault minting from uncirculating reserve
- Refill mechanism when all shares burned (1T new shares minted)

**WrappedWrappedXRP (WWXRP):**
- ERC20 joke token that MAY be backed by actual wXRP (intentionally undercollateralized)
- Unwrap: first-come-first-served against wXRP reserves
- Donate: increase wXRP backing without minting
- Privileged minting: game/coin/coinflip can mintPrize (unbacked), vault can vaultMintTo (from fixed reserve)
- burnForGame: game-only burn for bets

This phase does NOT re-audit the internal logic of game modules called via vault proxy functions (those are in Phases 103-111). Cross-module calls are traced far enough to verify state coherence in the calling context.

</domain>

<decisions>
## Implementation Decisions

### Function Categorization
- **D-01:** Use Categories B/C/D only -- no Category A. These are standalone contracts, not delegatecall modules. External/public state-changing functions -> Category B. Internal/private state-changing helpers -> Category C. View/pure functions -> Category D.
- **D-02:** Category B functions get full Mad Genius treatment: recursive call tree with line numbers, storage-write map, cached-local-vs-storage check, 10-angle attack analysis.
- **D-03:** Category C functions are traced as part of their parent's call tree. They do NOT get standalone attack sections unless they are called from multiple parents with different cached-local states (e.g., _burnCoinFor is called by burnCoin, so trace through burnCoin).

### Multi-Contract Scope (MULTI-PARENT Standalone)
- **D-04:** All three contracts (DegenerusVault, DegenerusVaultShare, WrappedWrappedXRP) are audited as a single unit. Cross-contract interactions between them are first-class audit targets.
- **D-05:** DegenerusVaultShare is embedded in the same file as DegenerusVault. Both the share token and vault are in scope.
- **D-06:** WrappedWrappedXRP interacts with the vault via vaultMintTo (vault calls WWXRP to mint from uncirculating reserve). This interface must be fully traced.

### Fresh Analysis
- **D-07:** Fresh adversarial analysis on ALL functions -- do not reference or trust prior findings from v1.0-v4.4. The entire point of v5.0 is catching bugs that survived 24 prior milestones.
- **D-08:** Prior audit results are not input to this phase. Every function is guilty until proven innocent.

### Key Attack Surfaces
- **D-09:** Share calculation correctness: deposit/withdraw share math must prevent disproportionate extraction. First-deposit inflation attack, rounding direction, zero-supply edge cases.
- **D-10:** WWXRP undercollateralized unwrap race: first-come-first-served means reserves can be drained. Verify CEI pattern, verify no reentrancy via wXRP transfer.
- **D-11:** Vault owner threshold (>50.1% DGVE) must be checked for manipulation via share transfer timing.
- **D-12:** BURNIE virtual deposit (vaultEscrow) and claim accounting -- coinTracked must stay synchronized with actual mint allowance.
- **D-13:** Refill mechanism when burning ALL shares -- verify no inflation attack where attacker drains vault then gets fresh shares.

### Cross-Module Call Boundary
- **D-14:** When vault proxy functions (gamePurchase, gameAdvance, etc.) call into the game contract, trace the subordinate calls far enough to verify the vault's state coherence. Full internals of game modules are audited in their own unit phases (103-111).
- **D-15:** If a subordinate call writes to storage that the vault has cached locally, that IS a finding for this phase.

### Report Format
- **D-16:** Follow ULTIMATE-AUDIT-DESIGN.md format: per-function sections with Call Tree, Storage Writes (Full Tree), Cached-Local-vs-Storage Check, Attack Analysis with verdicts.

### Claude's Discretion
- Ordering of function analysis within the report (suggest risk-tier ordering)
- Level of detail in cross-module subordinate call traces (enough to verify state coherence, no more)
- Whether to split the attack report into multiple files if it exceeds reasonable length

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Audit Design
- `.planning/ULTIMATE-AUDIT-DESIGN.md` -- Three-agent system design (Mad Genius / Skeptic / Taskmaster), attack angles, anti-shortcuts doctrine, output format

### Target Contracts
- `contracts/DegenerusVault.sol` -- Main audit target (1050 lines, includes DegenerusVaultShare + DegenerusVault)
- `contracts/WrappedWrappedXRP.sol` -- Second audit target (389 lines, WWXRP token)

### Interfaces
- `contracts/interfaces/IVaultCoin.sol` -- BURNIE vault interface (vaultEscrow, vaultMintTo, vaultMintAllowance)
- `contracts/interfaces/IStETH.sol` -- stETH interface
- `contracts/interfaces/IDegenerusGame.sol` -- Game interface for operator approval

### Wiring
- `contracts/ContractAddresses.sol` -- Compile-time constant addresses for all contracts

### Prior Phase Outputs (methodology reference only -- do NOT trust findings)
- `.planning/phases/103-game-router-storage-layout/103-CONTEXT.md` -- Phase 103 context (Category B/C/D pattern, report format)
- `audit/unit-01/COVERAGE-CHECKLIST.md` -- Phase 103 Taskmaster output (format reference)
- `audit/unit-01/ATTACK-REPORT.md` -- Phase 103 Mad Genius output (format reference)

### Prior Audit Context (known issues -- do not re-report)
- `audit/KNOWN-ISSUES.md` -- Known issues from v1.0-v4.4

</canonical_refs>

<code_context>
## Existing Code Insights

### DegenerusVaultShare Key Functions
- `constructor(name_, symbol_)` (L198) -- Deploy share token, mint INITIAL_SUPPLY (1T) to CREATOR
- `approve(spender, amount)` (L213) -- Standard ERC20 approve
- `transfer(to, amount)` (L225) -- Standard ERC20 transfer
- `transferFrom(from, to, amount)` (L237) -- Standard ERC20 transferFrom
- `vaultMint(to, amount)` (L258) -- Vault-only mint (unchecked overflow)
- `vaultBurn(from, amount)` (L273) -- Vault-only burn (unchecked underflow)
- `_transfer(from, to, amount)` (L290) -- Private transfer helper

### DegenerusVault Key Functions
- `constructor()` (L433) -- Deploy share tokens, sync coinTracked
- `deposit(coinAmount, stEthAmount)` (L454) -- Game-only deposit (ETH+stETH+BURNIE escrow)
- `receive()` (L465) -- Accept ETH donations
- `gameAdvance()` (L476) -- Proxy advanceGame (vaultOwner only)
- `gamePurchase(...)` (L489) -- Proxy purchase with ETH (vaultOwner only)
- `gamePurchaseTicketsBurnie(...)` (L510) -- Proxy BURNIE ticket purchase
- `gamePurchaseBurnieLootbox(...)` (L519) -- Proxy BURNIE lootbox
- `gameOpenLootBox(...)` (L527) -- Proxy lootbox open
- `gamePurchaseDeityPassFromBoon(...)` (L536) -- Proxy deity pass (complex ETH flow)
- `gameClaimWinnings()` (L550) -- Proxy claim winnings
- `gameClaimWhalePass()` (L556) -- Proxy whale pass claim
- `gameDegeneretteBetEth(...)` (L569) -- Proxy ETH bet
- `gameDegeneretteBetBurnie(...)` (L595) -- Proxy BURNIE bet
- `gameDegeneretteBetWwxrp(...)` (L617) -- Proxy WWXRP bet
- `gameResolveDegeneretteBets(...)` (L636) -- Proxy bet resolution
- `gameSetAutoRebuy(...)` (L643) -- Proxy auto-rebuy toggle
- `gameSetAutoRebuyTakeProfit(...)` (L650) -- Proxy take profit
- `gameSetDecimatorAutoRebuy(...)` (L657) -- Proxy decimator auto-rebuy
- `gameSetAfKingMode(...)` (L666) -- Proxy AFK king mode
- `gameSetOperatorApproval(...)` (L678) -- Proxy operator approval
- `coinDepositCoinflip(...)` (L685) -- Proxy coinflip deposit
- `coinClaimCoinflips(...)` (L693) -- Proxy coinflip claim
- `coinDecimatorBurn(...)` (L700) -- Proxy decimator burn
- `coinSetAutoRebuy(...)` (L708) -- Proxy coinflip auto-rebuy
- `coinSetAutoRebuyTakeProfit(...)` (L715) -- Proxy coinflip take profit
- `wwxrpMint(to, amount)` (L723) -- Mint WWXRP from reserve (vaultOwner only)
- `jackpotsClaimDecimator(lvl)` (L731) -- Proxy decimator jackpot claim
- `burnCoin(player, amount)` (L749) -- Burn DGVB for BURNIE (CRITICAL)
- `burnEth(player, amount)` (L816) -- Burn DGVE for ETH+stETH (CRITICAL)
- `_burnCoinFor(player, amount)` (L762) -- Internal DGVB claim logic
- `_burnEthFor(player, amount)` (L833) -- Internal DGVE claim logic
- `_combinedValue(extraValue)` (L959) -- Combine msg.value + vault ETH
- `_syncEthReserves()` (L971) -- Read ETH+stETH balances
- `_syncCoinReserves()` (L980) -- Sync coinTracked with actual allowance
- `_coinReservesView()` (L987) -- View helper for BURNIE reserves
- `_ethReservesView()` (L1002) -- View helper for ETH+stETH reserves
- `_stethBalance()` (L1024) -- Read stETH balance
- `_payEth(to, amount)` (L1031) -- Send ETH via low-level call
- `_paySteth(to, amount)` (L1039) -- Transfer stETH
- `_pullSteth(from, amount)` (L1046) -- Pull stETH via transferFrom

### WrappedWrappedXRP Key Functions
- `approve(spender, amount)` (L196) -- Standard ERC20 approve
- `transfer(to, amount)` (L208) -- Standard ERC20 transfer
- `transferFrom(from, to, amount)` (L222) -- Standard ERC20 transferFrom
- `unwrap(amount)` (L290) -- Burn WWXRP, receive wXRP (first-come-first-served)
- `donate(amount)` (L314) -- Donate wXRP to reserves
- `mintPrize(to, amount)` (L342) -- Authorized minter mint (unbacked)
- `vaultMintTo(to, amount)` (L363) -- Vault mint from uncirculating reserve
- `burnForGame(from, amount)` (L384) -- Game-only burn
- `_transfer(from, to, amount)` (L241) -- Internal transfer
- `_mint(to, amount)` (L254) -- Internal mint
- `_burn(from, amount)` (L266) -- Internal burn

### Established Pattern (from prior phases)
- 4-plan structure: Taskmaster checklist -> Mad Genius attack -> Skeptic review -> Final report
- Category B/C/D classification with risk tiers for Category B
- Taskmaster must achieve 100% coverage before unit advances to Skeptic
- Output goes to `audit/unit-12/` directory

### Key Integration Points
- Vault calls game contract for all gameplay proxying (address(this) as player)
- Vault calls coinflipPlayer for coinflip operations
- Vault calls coinToken for BURNIE operations (vaultEscrow, vaultMintTo, transfer)
- Vault calls wwxrpToken.vaultMintTo for WWXRP minting
- Vault calls steth for stETH transfers
- WWXRP calls wXRP (external token) for unwrap/donate
- Game/Coin/Coinflip call WWXRP.mintPrize for prize distribution
- Game calls WWXRP.burnForGame for bet burns

</code_context>

<specifics>
## Specific Ideas

No specific requirements beyond the ULTIMATE-AUDIT-DESIGN.md methodology. The three-agent system (Taskmaster checklist -> Mad Genius attack -> Skeptic review) drives the workflow, same as all v5.0 units.

Key areas of focus for this unit:
1. Share calculation math in burnCoin/burnEth -- can rounding be exploited for profit?
2. Refill mechanism (1T shares minted when supply hits 0) -- can this be weaponized?
3. WWXRP undercollateralized unwrap -- race condition between multiple unwrappers
4. Virtual BURNIE deposit (vaultEscrow) -- can coinTracked desync from reality?
5. Vault owner threshold manipulation via DGVE transfer/trade
6. ETH flow through gamePurchaseDeityPassFromBoon -- complex balance checks

</specifics>

<deferred>
## Deferred Ideas

- **Phase 118 coordination**: Full cross-module state coherence verification including vault proxy calls is deferred to the integration sweep.
- **Phase 112 coordination**: BurnieCoin's vaultEscrow and vaultMintTo implementations are audited in Phase 112 (BURNIE Token + Coinflip). This phase trusts the interface but traces the vault-side accounting.

</deferred>

---

*Phase: 114-vault-wwxrp*
*Context gathered: 2026-03-25*
