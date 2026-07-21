# Security Policy

Frozen subject: `contracts/` tree `622b9a51` @ tag `degenerus-c4a` (post-v75.0 hardening freeze).

## Reporting a vulnerability

This code is **not yet deployed** — there are no live funds at risk and no disclosure embargo.
Report vulnerabilities however is easiest: open a public issue or send them to **burnie@degener.us**.
Include: affected contract + line, the invariant broken, a concrete exploit path (actor,
preconditions, sequence), and the value impact.

Before reporting, check `KNOWN-ISSUES.md` — every pre-triaged finding, by-design ruling, and
cross-model disposition is documented there and is not eligible.

## What we care about (severity floor)

The threat weighting is locked (real-money adversarial actors, hostile-admin-key assumption):

1. **RNG / freeze manipulability (DOMINANT).** Chainlink VRF V2.5 is the sole randomness source.
   Every input to an RNG-dependent calculation must be committed before the VRF request; any path
   where a player mutates outcome-relevant state between request and fulfillment, or a
   proposer/validator biases a *live* outcome, is high+.
2. **Gas-DoS in the advanceGame chain (HIGH).** `advanceGame` and its same-tx composition must
   complete under the block gas limit for any achievable on-chain state. Target worst-case < 10M,
   provably never > 16.7M. Any path an attacker forces past the ceiling (= game-over) is high.
3. **Solvency / backing conservation (SPINE).** ETH and token accounting must be exact. Wei-scale
   rounding is not a finding (all rounding favors solvency). Any unauthorized value extraction —
   by a player, an external attacker, or a compromised admin — is high.
4. **Access control / reentrancy / MEV (LOWER).** In scope, but weighted below the above.

## Trust model — trusted and restricted roles

The protocol has **no upgradeability, no proxy, and no configurable privileged addresses.** Every
cross-contract authority is a compile-time constant in `ContractAddresses.sol` (nonce-predicted at
deploy). The roles below are the *only* trusted actors; each is bounded as stated.

### 1. sDGNRS majority governance (emergency VRF-coordinator + price-feed swap)

**Who:** any holder of voting sDGNRS, acting through `DegenerusAdmin.propose` / `vote`. sDGNRS is
soulbound; voting weight = `votingSupply()`.

**Powers:**
- Rotate the Chainlink VRF coordinator (`propose(newCoordinator, newKeyHash)` → `vote` → `_executeSwap`).
- Rotate the LINK/ETH price feed (`proposeFeedSwap` → `voteFeedSwap`).

**Bounds:**
- **Death-clock prerequisite.** A VRF-swap proposal cannot even be *created* until the VRF has
  stalled. `ADMIN_STALL_THRESHOLD = 44 hours` (raised from 20h this batch) for the vault-owner path;
  `COMMUNITY_STALL_THRESHOLD = 7 days` for the 0.5%-sDGNRS community path. 44h clears a full healthy ~24h
  RNG cycle plus margin so the sawtooth `block.timestamp − lastVrfProcessed` cannot trip governance
  on a healthy game. Feed swaps require the feed unhealthy 2d (admin) / 7d (community).
- **Decaying-threshold vote.** Approval threshold decays 50% → 5% over the 168h (7-day) proposal
  lifetime; execution requires approve-weight > reject-weight *and* meeting the live threshold.
  Reject voters holding more sDGNRS than approvers block the swap. Expired proposals (≥168h) die.
- **Kill-on-recovery (475 fix, `93d17288`).** A proposal exists only to replace a *dead* coordinator.
  Both `vote()` and `canExecute()` now invalidate (`ProposalState.Killed`) a proposal whenever VRF
  is healthy *now* (`stall < 44h`) **or** any VRF word was fulfilled after the proposal was created
  (`lastVrfProcessed > createdAt`). The `lastVrfProcessed > createdAt` clause makes the kill
  recovery-proof even if no one "poked" the proposal during the recovery window — it closes the
  pre-fix gap where a stall-1 proposal could survive an un-poked recovery and later execute on a
  re-stall against an age-decayed (down to 5%) threshold with stale votes.
- **Payable `receive()`.** `DegenerusAdmin` accepts native ETH and best-effort forwards it to the
  VAULT via an assembly `pop(call(...))` whose success flag is discarded, so the hook can *never*
  revert. This exists because `VRFCoordinatorV2_5.cancelSubscription` issues an unconditional
  `to.call{value: nativeBalance}("")` (even when `nativeBalance == 0`) during a coordinator swap; a
  non-payable owner would revert the cancel and roll back the LINK refund. The zero path is a no-op;
  any stray native is forwarded, never stranded.
- **Cannot:** modify game logic, move game funds, change any access-control address, mint tokens, or
  touch RNG outside the death-clock-gated coordinator swap. A hostile coordinator that *did* land
  cannot retroactively bias already-committed words; while VRF is dead, sDGNRS supply is frozen.

### 2. Vault owner — holder of > 50.1% of DGVE supply

**Who:** `DegenerusVault._isVaultOwner(account)` ≡ `balance * 1000 > supply * 501` of the **DGVE**
ETH/stETH share-class token (DGVE and DGVF are the two ERC-20 share classes the vault deploys from
its own constructor). CREATOR holds the initial 1T supply of each; the role transfers with the token.

**Powers (`onlyVaultOwner`, unilateral):** swap/stake ETH↔stETH (the vault's own custodied position),
set the lootbox mid-day-RNG threshold (the pending-lootbox ETH-equivalent value that must accumulate
before an extra *intra-day* lootbox VRF request may be triggered — a LINK-cost-limiting operational
knob, not a security parameter), the owner-gated salvage-buy fallback, **AFKing seat grants**
(`afkingGrant` — grant seat claim rights from the vault's 998-seat allowance on
`AFKingSubscriptionToken`; the token itself enforces the sale lock — grants revert until all 1,000
free-tranche seats are claimed — and the 998 lifetime cap, so the owner cannot dilute the free
tranche or mint past supply), and a family of `game*` /
`coin*` / `wwxrp*` / `sdgnrs*` proxy actions the vault performs *as itself* (it custodies perpetual
tickets and reserves). **Post-gameOver GNRUS charity recovery** (`VAULT.isVaultOwner`-gated, on the
GNRUS contract): once the game's final sweep has run, `GNRUS.vaultRedeemFor(holder)` redeems a
holder's entire GNRUS on its behalf, paying the holder its full proportional ETH+stETH share; 3 years
after that sweep, `GNRUS.sweepResidualToVault()` reclaims any ETH/stETH GNRUS still holds to the vault.

**Governance-gated (NOT unilateral vault-owner powers):** the LINK price-feed swap and the VRF-
coordinator swap. The vault owner may only *propose* one (the vault-owner proposal path — feed
unhealthy 2d / VRF stalled 44h); neither executes without sDGNRS-majority governance behind the
death-clock (decaying vote threshold + kill-on-recovery — see role 1). `proposeFeedSwap` /
`voteFeedSwap`; the 0.5%-sDGNRS community path (7d) is the other proposal entry.

**Bounds:** every vault-owner action operates only on the vault's *own* custodied position
(its shares, its tickets, its escrow). It cannot reach into player balances or the game's
claimablePool. The vault's reserve is a virtual-allowance model (`balanceOf[VAULT] == 0`). The
price-feed swap only affects LINK→FLIP donation valuation and is itself death-clock-gated in Admin.
The two GNRUS recovery actions are the sole vault-owner powers that reach beyond the vault's own
position, and only narrowly: they act on *charity residual* on a contract already post-gameOver and
past its final sweep — never live player balances or the game claimablePool. `vaultRedeemFor` is
value-preserving (the holder receives exactly what `burn()` would pay it; the owner cannot extract
holder value), and `sweepResidualToVault` is time-locked to 3 years past the final sweep — a grace
window in which any holder can redeem (itself, or via `vaultRedeemFor`) before the residual is
reclaimed.

### 3. DegenerusGasFaucet — relocated, out of scope

The donation-funded gas-dust faucet has been **moved to the separate `degenerus-utilities` repo** and
is **not part of this audit**. It was a standalone, dormant utility — not deployed by `deploy.js`, no
protocol-state writes, no access to protocol backing or solvency; its only privileged surface was the
vault owner managing its `approvedDistributor` set over externally-donated ETH. Findings against it
are not eligible here.

### 4. Chainlink VRF coordinator — trusted external black box

**Who:** the `VRF_COORDINATOR` constant (and any coordinator installed by a governance swap).

**Powers:** delivers VRF words via `rawFulfillRandomWords`; the protocol trusts these words are
unbiased and unpredictable at request time.

**Bounds:** a request-id check (`requestId == vrfRequestId`) and a `rngWordCurrent == 0` guard mean a
stale/duplicate fulfillment is dropped. VRF unavailability stalls the game but loses no funds; gap
days backfill (`keccak256(vrfWord, gapDay)`) on recovery, capped at 120 days. After a catastrophic
> 120-day VRF death the deadman (role-independent) commits a non-steerable historical+prevrandao
fallback so the protocol can drain rather than brick (see KNOWN-ISSUES.md "VRF-death deadman").

### Roles that do NOT exist

No pausing role, no fee-setter, no treasury withdrawer, no mint/blacklist admin, no proxy admin, no
address re-pointer. `onlyOwner` surfaces (deity-pass renderer, vault operations) are operational, not
fund-bearing, and the fund-bearing ones funnel through the bounded roles above.

## Permissionless-settlement trust boundary (locked ruling)

Many actions are intentionally **permissionless** — callable for another player by anyone. This is
safe under one rule, applied uniformly:

> **A permissionless action is allowed iff (a) value can only settle *to* the rightful owner, and
> (b) any spend is sourced only from a consenting party (`msg.sender`, the owner, or an
> operator-approved delegate). Cashout and spend are gated; settlement and caller-funded gifts are not.**

- **Harvest-inward-only settlement (ungated).** `openBox`/`openBoxes`, `claimBingo(player,…)`
  (sender-or-approved, player-keyed dedup), `claimWhalePass`, `claimAffiliateDgnrs` (single + batch
  with per-item try/catch), `resolveDegeneretteBets`, `resolveRedemptionLootbox` (sDGNRS-only),
  ticket settlement, and the advance crank all credit the *resolved owner/contract* — the caller can
  never redirect the value to itself.
- **Caller-funded gifts (ungated, but spend = funder).** `Coinflip.depositCoinflip(player, amount)`
  and the Degenerette gift placement source the FLIP principal from `msg.sender` on the gift branch
  (`funder = msg.sender` when caller ≠ player and not operator-approved); the stake/position belongs
  to `player`. No branch burns a non-consenting party's FLIP. WWXRP is gift-excluded.
  `directDeposit=false` on gift/operator deposits suppresses biggestFlip/bounty credit so a funder
  cannot farm a streak; quest progress credits the spender (the funder), which is the consenting
  payer.
- **Cashout / spend (gated).** Moving value *out* to a chosen address, or spending a non-consenting
  party's balance, requires self, owner, or operator approval. Operator approval
  (`setOperatorApproval`) is the trust boundary — granting it is the player's consent.

A finding under this boundary must show a permissionless path that either (a) settles value to a
party other than the rightful owner, or (b) spends from a party that did not consent.
