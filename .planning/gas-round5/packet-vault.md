# Gas round-5 packet — DegenerusVault.sol (+ DegenerusVaultShare)

6 findings: VAULT-01, VAULT-02, VAULT-04, VAULT-06, VAULT-13 (APPROVED) · VAULT-08 (PARTIAL, adjudicated below).
Locate by CONTENT — line numbers are audit-time.

## Adjudications (round-5 orchestrator)

- **VAULT-08 — APPLY burnCoin leg ONLY; burnEth leg REJECTED** (skeptic's own split, adopted):
  DegenerusVaultShare.vaultBurn → `returns (uint256 supplyBefore)` (pre-decrement totalSupply;
  selector unchanged); burnCoin burns first and uses the return; burnEth keeps its totalSupply()
  staticcall and ignores the new return. The burnEth reorder would move the share burn ahead of the
  deliberately-arranged claimWinnings/solvency sequence (cf. 53cd25cf CEI reorder) — fails the
  security-over-gas floor.
- VAULT-01 note: BurnieCoin.vaultEscrow becomes caller-less after deposit() deletion — that is a
  separate BurnieCoin-scope cleanup, OUT of this round's batch (don't touch BurnieCoin.sol). Trim
  only the vault-local interface surface. Update header/natspec deposit() references
  (comments-describe-what-IS).
- VAULT-02 note: after coinTracked removal re-check remaining vault storage; any vm.store/vm.load
  vault harness recalibrates per the storage playbook (forge inspect for authoritative slots).
  Revert-reason shift on the theoretical corner (Panic 0x11 → BurnieCoin Insufficient) is
  skeptic-cleared.
- VAULT-04/VAULT-13: revert-reason/site shifts on already-reverting paths only — update any test
  pinning those errors.

## Ledger bodies

#### VAULT-01 — contracts/DegenerusVault.sol (L500-L508 (plus L434-L437, L356, L1000-L1003))
**Category:** unused_function · **Frequency:** cold · **Confidence:** high · **Batch:** vault

deposit(uint256 coinAmount, uint256 stEthAmount) is gated onlyGame, but the deployed GAME never calls it. DegenerusGame's only vault interface is IDegenerusVaultOwnerGame { isVaultOwner } (DegenerusGame.sol:65-67, :143-144); grep of all of contracts/ (Game + every module + library) finds zero '.deposit(' call sites and no interface declaring it. Value actually reaches the vault via: ETH -> receive() / claimable-winnings credits (_addClaimableEth(ContractAddresses.VAULT,...) e.g. DegenerusGameJackpotModule.sol:711), stETH -> direct _sendStethFirst transfers (DegenerusGameGameOverModule.sol:228), BURNIE -> BurnieCoin-internal vaultAllowance credits (BurnieCoin.sol:370/391). Since all contracts are immutable at deploy, this entry point is unreachable forever. Its removal also strands _pullSteth (sole caller is deposit), the onlyGame modifier (sole user), and the vault-level Unauthorized error (sole user), all removable with it. BurnieCoin.vaultEscrow keeps its other authorized caller (GAME) so no peer change is needed.

**Change:** Delete deposit() (L500-508), _pullSteth (L1000-1003), the onlyGame modifier (L434-437), and the vault-scope 'error Unauthorized()' (L356). Keep the Deposit event (still emitted by receive()).

**Savings:** runtime 0 (never executed) · bytecode ~400-550 (body + dispatcher entry + _pullSteth + modifier/error) · skeptic-revised: 0 runtime; ~400-550 bytes of vault runtime bytecode (dispatcher entry + payable body with two external calls + modifier + error + _pullSteth). Vault is not EIP-170-constrained, so deployment-cost value only.

**Skeptic (APPROVED, risk low, invariant impact none):** Verified unreachable. Grep of all production contracts/ finds zero '.deposit(' call sites, zero raw-selector encodings targeting the vault, and every peer interface to the VAULT address declares only isVaultOwner (DegenerusGame.sol:65-67 + :143-144, DegenerusStonk.sol:34-36, GNRUS.sol:28-31, DegenerusDeityPass.sol:21-23, DegenerusAdmin.sol:179-181, modules/DegenerusGameMintStreakUtils.sol:10-12). onlyGame (DegenerusVault.sol:434-437) restricts the caller to the GAME contract, which never calls it — so even deploy scripts can never reach it. Value channels confirmed independent: receive() (L511-513), claimable-winnings credits (modules/DegenerusGamePayoutUtils.sol:23), direct stETH transfers (DegenerusStonk.sol:325), LINK sweep (DegenerusAdmin.sol:950-958), and BURNIE flows that BurnieCoin redirects to vaultAllowance internally (BurnieCoin.sol:365-375, 389-394). _pullSteth's sole caller is deposit (L506); onlyGame's sole user is deposit (L500); vault-scope error Unauthorized's sole user is onlyGame (L435 — the L229 use is the separate DegenerusVaultShare scope). Deposit event stays (receive() emits it). Nothing ever flowed through this function, so no solvency path is touched.

**Implementation notes:** Also update the header-diagram/natspec references to deposit() (DegenerusVault.sol:142, :146, :166) per the comments-describe-what-IS rule. One correction to the rec's risk note: BurnieCoin.vaultEscrow does NOT have another live caller — grep shows vault.deposit (L503) was its only production call site (GAME is authorized at BurnieCoin.sol:520-525 but never calls it), so vaultEscrow becomes caller-less in BurnieCoin; that is a separate BurnieCoin-scope cleanup decision, not a blocker here. The now-unused vaultEscrow declaration in the local IVaultCoin import surface can be trimmed at zero cost.

**Finder risk notes:** Skeptic must re-confirm no module reaches deposit via raw selector call (grep for abi.encodeWithSelector against VAULT found none) and that no future-deploy script depends on it (contracts are frozen at deploy, per project policy unreachable = removable). Removal does not touch solvency paths: nothing ever flowed through this function.


#### VAULT-02 — contracts/DegenerusVault.sol (L427, L470-L471, L504, L774, L934-L937)
**Category:** dead_code · **Frequency:** warm · **Confidence:** high · **Batch:** vault

uint256 private coinTracked is write-only state: its only appearances in all of contracts/ are assignments (constructor L471, deposit L504, burnCoin L774, _syncCoinReserves L936). It is private, the vault is a standalone contract (no delegatecall sharing), and no function returns or branches on it. Every consumer of the real number re-reads the authoritative source coinToken.vaultMintAllowance() anyway. The only behavioral side effect is the checked-subtraction underflow revert at L774 ('coinTracked -= remaining'), which duplicates BurnieCoin's own allowance enforcement: BurnieCoin.sol:556 'if (amount128 > allowanceVault) revert Insufficient();' inside vaultMintTo (the very next call at L775) — the dominating check; the tx reverts either way. Note coinTracked is synced at the top of burnCoin but the live allowance is re-checked at mint time by the coin, so the local copy is not even a reliable guard.

**Change:** Delete 'uint256 private coinTracked;' (L427) and constructor lines 470-471; change _syncCoinReserves to a view that just returns coinToken.vaultMintAllowance() (or inline the call at L742); delete 'coinTracked += coinAmount;' (L504, moot if VAULT-01 lands) and 'coinTracked -= remaining;' (L774).

**Savings:** runtime ~5,200 per burnCoin (cold slot access 2100 + SSTORE_RESET 2900 in _syncCoinReserves, + ~200 for the warm dirty write/read at L774); ~8,700 per coin-bearing deposit if deposit() were kept (extra staticcall + two SSTOREs); ~24k one-time at construction · bytecode ~80-120 · skeptic-revised: ~2,200-5,200 per burnCoin (cold SSTORE of coinTracked in _syncCoinReserves: 2100 cold access + 100-2900 depending on whether the allowance changed since last burn; plus ~200 warm read/write at L774 when reached); ~5,000-8,000 per deposit if deposit() survives; ~22k one-time constructor SSTORE. Real saving on the warm redemption path.

**Skeptic (APPROVED, risk low, invariant impact none):** Verified write-only: all five coinTracked sites in the entire codebase are writes (DegenerusVault.sol:427, 471, 504, 774, 936); the vault is standalone (no delegatecall storage sharing, no assembly), and the var is private. The only behavioral effect is the checked subtraction at L774. Dominating check confirmed: BurnieCoin.sol:552-556 vaultMintTo reverts Insufficient when amount exceeds the LIVE vaultAllowance, and L775 calls it immediately with the same `remaining` on every path through L774. Stronger still: on every reachable L774 path the subtraction cannot underflow anyway — balanceOf[VAULT] is structurally 0 (BurnieCoin redirects all VAULT-bound transfers/mints to vaultAllowance, BurnieCoin.sol:365-375/389-394), so the vault-balance leg never runs, and whenever the coinflip leg claims a nonzero amount the subsequent transfer at L769 reverts before L774 (see VAULT-03). Thus L774 is only reached with claimable==0, where remaining = allowance*amount/supply <= allowance (amount <= supplyBefore is enforced by the successful vaultBurn at L751) and the live allowance is untouched since the L742 sync. In the one theoretical corner where preview/claim diverge, both versions still revert (Panic 0x11 vs BurnieCoin Insufficient) — revert-reason change only.

**Implementation notes:** After removal the vault has ZERO storage variables — any vault-targeting test harness using vm.store/vm.load on slot 0 breaks at runtime (compile stays green); recalibrate per the storage-packing playbook. _syncCoinReserves becomes a view returning coinToken.vaultMintAllowance() (or inline at L742/L502); delete constructor L470-471 together (coinAllowance becomes unused).

**Finder risk notes:** The L774 checked subtraction is an implicit solvency-shaped guard; its exact dominator is BurnieCoin.sol:552-556 (vaultMintTo reverts Insufficient when amount exceeds live vaultAllowance), reachable on every path since L775 immediately calls vaultMintTo with the same amount. Revert reason/site changes (vault Panic 0x11 -> coin Insufficient) — behavior in success paths identical.


#### VAULT-04 — contracts/DegenerusVault.sol (L807)
**Category:** redundant_check · **Frequency:** warm · **Confidence:** medium · **Batch:** vault

In burnEth, the conjunct 'claimable != 0' in 'if (claimValue > combined && claimable != 0)' is arithmetically dominated for every execution that completes: reserve = combined + claimable (L804) and claimValue = (reserve * amount) / supplyBefore <= reserve whenever amount <= supplyBefore — which holds in every non-reverting run because share.vaultBurn(msg.sender, amount) (L821) reverts when amount exceeds the caller's balance (<= totalSupply). Hence claimValue > combined implies claimable >= 1. The conjunct only matters in runs already destined to revert at L821, where it merely skips a wasted claimWinnings call before the revert.

**Change:** Replace the condition with 'if (claimValue > combined)'.

**Savings:** runtime ~10-20 per burnEth taking the shortfall branch · bytecode ~10 · skeptic-revised: ~5-15 gas per burnEth taking the shortfall branch (claimable is already on stack; one ISZERO+JUMPI removed) + ~10 bytes. Marginal.

**Skeptic (APPROVED, risk low, invariant impact none):** Arithmetic domination verified. With claimable==0, claimValue = floor(combined*amount/supplyBefore) > combined requires amount > supplyBefore (and combined > 0). Every such run reverts regardless: share.vaultBurn at L821 reverts Insufficient since balanceOf[msg.sender] <= totalSupply = supplyBefore < amount (DegenerusVault.sol:315-317), and supply/balances cannot change between the L803 read and L821 (share mint/burn is onlyVault and the only intermediate external call, claimWinnings, can only trigger the vault's receive() which just emits). Even in the corner where the now-unguarded claimWinnings call adds <=1 wei and lets the L813/L818 branch pass, vaultBurn still reverts. So all non-reverting executions are byte-identical; only revert reason/site on invalid-amount runs changes.

**Implementation notes:** Savings are near-noise; apply only if already touching burnEth for other approved items. Behavior change is confined to runs with amount > total share supply, which revert in both versions.

**Finder risk notes:** Revert-path behavior change only: a caller passing amount > supply now triggers a claimWinnings external call before reverting at vaultBurn (tx still reverts; claimWinnings on the game with sentinel-level claimable is benign). The dominating relation is the L804 arithmetic plus the L821 vaultBurn balance check (DegenerusVault.sol:821 -> DegenerusVaultShare.vaultBurn L315-317).


#### VAULT-06 — contracts/DegenerusVault.sol (L794-L805 vs L956-L974 (and L925-L931))
**Category:** bytecode_dedup · **Frequency:** cold · **Confidence:** high · **Batch:** vault

The claimable-winnings 1-wei-sentinel normalization ('claimable <= 1 ? 0 : claimable - 1' around gamePlayer.claimableWinningsOf(address(this))) is implemented twice: inline in burnEth (L795-L802) and again in _ethReservesView (L963-L970). _ethReservesView also re-implements the ethBal/stBal/combined computation already provided by _syncEthReserves (L925-L931). One private helper '_netClaimableWinnings() returns (uint256)' used by both sites, plus composing _ethReservesView from _syncEthReserves, removes the duplicated sequences.

**Change:** Add 'function _netClaimableWinnings() private view returns (uint256 c) { c = gamePlayer.claimableWinningsOf(address(this)); c = c <= 1 ? 0 : c - 1; }'; use it at burnEth L795-802 and inside _ethReservesView; rewrite _ethReservesView as '(ethBal, , uint256 combined) = _syncEthReserves(); mainReserve = combined + _netClaimableWinnings();'.

**Savings:** runtime ~0 (via_ir may inline; runtime neutral) · bytecode ~80-150 · skeptic-revised: ~0 runtime; bytecode ~0-150 bytes — via_ir at runs=50 may already inline/dedup these short sequences, so treat as source-hygiene with possible small size win. Vault is not EIP-170-constrained.

**Skeptic (APPROVED, risk none, invariant impact none):** Duplication verified: the 1-wei-sentinel normalization appears at DegenerusVault.sol:795-802 (burnEth) and :963-970 (_ethReservesView) with identical semantics (<=1 -> 0, else -1), and _ethReservesView:956-962 re-implements _syncEthReserves:925-931 verbatim. The proposed _netClaimableWinnings helper + composition is a behavior-identical pure refactor: the c-1 branch only executes for c>=2 so checked vs unchecked is equivalent, and the final combined+claimable add cannot overflow with real ETH magnitudes. No logic, ordering, or external-call change.

**Implementation notes:** Minor: the sketched rewrite `(ethBal, , uint256 combined) = _syncEthReserves();` mixes a declared return var with a new declaration in one tuple — split into a plain call assigning to locals. Low priority; bundle with other approved burnEth-adjacent edits.

**Finder risk notes:** Deployment-size-only value; the vault is not near the EIP-170 ceiling, so this is housekeeping rather than a strategic lever. No logic change.


#### VAULT-13 — contracts/DegenerusVault.sol (L619-L622)
**Category:** redundant_check · **Frequency:** cold · **Confidence:** high · **Batch:** vault

gameDegeneretteBet's overpay guard 'if (value > uint256(amountPerTicket) * ticketCount) revert Insufficient();' is dominated by the game side on every reachable path: the vault forwards value as msg.value into gamePlayer.placeDegeneretteBet (currency 0 == CURRENCY_ETH, DegenerusGameDegeneretteModule.sol:215), where _collectBetFunds reverts InvalidBet when ethPaid > totalBet (DegenerusGameDegeneretteModule.sol:581) and totalBet is computed with the identical formula uint256(amountPerTicket) * uint256(ticketCount) (DegenerusGameDegeneretteModule.sol:509). Underpayment is also handled game-side (claimable/afking top-up), so the vault check adds no protection for vault funds.

**Change:** Delete the multiplication and comparison at L622; keep 'value = _combinedValue(ethValue);' (its own vault-balance check at L918 is independent and must stay).

**Savings:** runtime ~60-90 per vault-owner ETH bet (one uint128 widening mul + compare + revert plumbing) · bytecode ~30-50 · skeptic-revised: ~60-90 gas per vault-owner ETH bet + ~30-50 bytes — cold, owner-gated path, so long-run value is small but real

**Skeptic (APPROVED, risk low, invariant impact none):** Dominating check verified on every reachable path. Sole entry: DegenerusVault.gameDegeneretteBet (owner-gated) computes value=_combinedValue(ethValue) and forwards it as msg.value to gamePlayer.placeDegeneretteBet (L624-631). Game side: DegenerusGame.placeDegeneretteBet:862-877 delegatecalls the module (msg.value preserved under delegatecall) -> module placeDegeneretteBet:366 -> _placeDegeneretteBet:451 -> _collectBetFunds(player, currency, totalBet, msg.value):468, which for CURRENCY_ETH (constant 0, module L215, matching the vault's currency==0 branch) reverts InvalidBet when ethPaid > totalBet (module L581), with totalBet computed by the identical widening formula uint256(amountPerTicket) * uint256(ticketCount) (module L508, overflow-free: uint128*uint8 < 2^256). _collectBetFunds is reached unconditionally after _placeDegeneretteBetCore on every ETH path; any earlier module revert also kills the tx, so no overpaying execution can complete. Underpayment is game-handled (claimable/afking top-up, L582-600). The vault's independent balance protection (_combinedValue's L918 check) is explicitly retained.

**Implementation notes:** Delete only the L622 comparison; keep `value = _combinedValue(ethValue);`. Revert reason on the overpay path changes from vault Insufficient to game InvalidBet (revert site moves inside the delegatecall) — update any test pinning that error.

**Finder risk notes:** Dominating check: DegenerusGameDegeneretteModule.sol:581 via DegenerusGame.sol:862 delegatecall (msg.value preserved). Revert reason changes from vault Insufficient to game InvalidBet on the overpay path. Owner-gated cold path — low absolute value.


#### VAULT-08 — contracts/DegenerusVault.sol (L743 and L751 (burnCoin); L803 and L821 (burnEth))
**Category:** redundant_external_call · **Frequency:** warm · **Confidence:** low · **Batch:** vault

burnCoin and burnEth each make a dedicated staticcall share.totalSupply() that reads the same slot vaultBurn touches moments later in the same tx. If DegenerusVaultShare.vaultBurn returned the pre-burn totalSupply, the separate getter call disappears. burnCoin is a clean reorder (burn first, then compute coinOut = coinBal * amount / supplyBefore — identical math). burnEth is more invasive: supplyBefore feeds the claimValue computation that decides the pre-burn claimWinnings call and the Insufficient solvency check (L818), so the burn would move ahead of the game claim call.

**Change:** Change DegenerusVaultShare.vaultBurn to 'returns (uint256 supplyBefore)' (return totalSupply prior to decrement); in burnCoin, call vaultBurn before computing coinOut and use its return as supplyBefore. Apply to burnEth only if the Skeptic clears moving the share burn ahead of the claimWinnings/solvency sequence.

**Savings:** runtime ~600-1,000 per burnCoin/burnEth (eliminates one warm staticcall + dispatch + duplicate warm SLOAD of the supply slot) · bytecode ~20-40 · skeptic-revised: ~400-800 per burnCoin (one eliminated warm staticcall round-trip + duplicate warm SLOAD of the share supply slot). burnEth keeps its totalSupply() call.

**Skeptic (PARTIAL, risk low, invariant impact none):** burnCoin leg APPROVED: vaultBurn is defined in-file (DegenerusVault.sol:315-323), onlyVault-gated, hook-free, and called nowhere outside the vault (grep: only L751/L821); returning the pre-decrement totalSupply changes neither selector nor any peer. Reordering the burn ahead of the coinOut computation is equivalent — vaultBurn touches only share-token storage, never the BurnieCoin/coinflip state read for coinBal, and the refill condition (supplyBefore == amount) uses the returned value identically. burnEth leg REJECTED: there supplyBefore feeds the claimValue computation that gates the pre-burn gamePlayer.claimWinnings call and the L818 stETH-sufficiency check; moving the share burn ahead of that external-call-plus-check sequence reorders effects around a payout/solvency-adjacent sequence that was deliberately arranged (cf. the recent CEI reorder fix 53cd25cf in the ETH/stETH claim path) for ~600 gas on a redemption — fails the security-over-gas floor for an unproven reorder.

**Counterexample:** For the rejected burnEth leg: burnEth's sequence compute-claimValue -> claimWinnings -> refresh balances -> Insufficient check -> burn intentionally keeps the share burn after the solvency decision; burn-first changes the effect/interaction order around the game call. No concrete exploit was constructed, which is exactly why it stays unapproved rather than rejected-as-broken.

**Implementation notes:** Apply to burnCoin only: change DegenerusVaultShare.vaultBurn to `returns (uint256 supplyBefore)` (return totalSupply before decrement); burnEth may ignore the new return value unchanged. Selector is unaffected by return type. Test harnesses pinning the share ABI may need regeneration.

**Finder risk notes:** Reordering effects near a payout path: the share token is in-repo, onlyVault-controlled and hook-free, so burn-first does not open reentrancy, but burnEth's current sequence (compute -> claim -> check -> burn) is deliberate-looking; restrict to burnCoin unless validated. Failure-path revert sites shift.


