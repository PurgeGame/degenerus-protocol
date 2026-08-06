# Security Policy

Frozen subject: `contracts/` tree `0e7b02fe` @ tag `degenerus-c4a` (post-v75.0 hardening freeze).

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
knob, not a security parameter), **thanos-level declaration** (`DegenerusGame.setThanosLevel` — see
the dedicated bounds below; the one vault-owner power that reaches every player's pricing),
the owner-gated salvage-buy fallback, **foreign-asset sweeps** (`DegenerusVault.sweepToken` / `sweepNft` — recover tokens or NFTs stranded in the vault by mistaken transfer; stETH is the one protected token, so the custodied backing is unreachable), **retired-VRF-subscription recovery** (`DegenerusAdmin.retrySubCancel` — cancel a *retired* coordinator's subscription and recover its LINK; the live coordinator/sub pair reverts `SubscriptionActive`, so the game's active RNG can never be stranded by it), **AFKing seat grants**
(`afkingSeatMint` — mint seats from the vault's 998-seat tranche on `AFKingSubscriptionToken`
straight to a recipient; the token itself enforces the sale lock — mints revert until all 1,000
free-tranche seats are out — and the 998 lifetime cap, so the owner cannot dilute the free
tranche or mint past supply), **AFKing seat restyling**
(`DegenerusVault.afkingSeatRestyle` — rewrite the cosmetic card art of a vault-held seat, and of
the SDGNRS-held construction seat, which the token authorizes the vault to restyle because SDGNRS
has no admin surface of its own; purely cosmetic — it moves no seat, touches no subscription or
tenure state, and confers no authority over the SDGNRS seat, which SDGNRS still owns and which has
no ERC721-out path), and a family of `game*` /
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

**Bounds — thanos-level declaration (the one power that is NOT vault-position-local).**
`setThanosLevel(targetLevel, shift)` declares that every ticket entry drained for `targetLevel`
onward divides by `2^shift`, i.e. it raises the effective entry price (and the foil-pack price) for
everyone from that level on. It is a purely *prospective* price change, bounded so it can neither
retro-price a materialized ticket nor be used to extract value. On the plain ticket it is
EV-neutral: the price is fixed, the delivered entries divide by `2^s`, and the uniform division
cancels in the pot-share fraction. On the **foil pack it is not** — the pack keeps its entry count
and pays `2^s` the price while **no** foil payout scales with the exponent, so a declaration makes
that SKU deliberately bad value for as long as it is in force. That is a design ruling rather than
an oversight: scaling a foil payout would mean reading the exponent at claim time, and a foil claim
can settle arbitrarily later than its buy, so a claim parked across a fresh declaration would pay
`2^(new - old)` times its face. Bounds:
- **6-level notice, pre-materialization.** `targetLevel >= level + 6`, which lands the declaration
  strictly before the target's first materialization (the far-future promotion at the transition to
  `target - 5`). One level's entries therefore always share one exponent regardless of when they
  were bought or drained, and the uniform division cancels in the pot-share fraction — a raw entry's
  replacement cost and expected pot share are both unchanged by any declaration.
- **Immutable once armed.** A pending declaration whose 6-level window has opened cannot be changed
  (`level + 6 > snapLevel` reverts `ThanosBounds`); it clears when its level commits.
- **Capped depth.** `shift <= 8` (256× maximum divisor).
- **Runaway-scale floor.** A non-zero shift requires the target level's projected entries — the
  previous level's *settled* pool target at the target level's price — to still exceed 40,000,000
  entries (10M whole tickets) after division, so snapping is undeclarable below runaway demand.
- **No value path.** It moves no ETH, credits nothing to the vault, and cannot touch
  `claimablePool`, player balances, or any already-drained entry.

**Bounds (all other powers):** every other vault-owner action operates only on the vault's *own*
custodied position (its shares, its tickets, its escrow). It cannot reach into player balances or the
game's claimablePool. The vault's reserve is a virtual-allowance model (`balanceOf[VAULT] == 0`). The
price-feed swap only affects LINK→FLIP donation valuation and is itself death-clock-gated in Admin.
Besides the thanos declaration above, the two GNRUS recovery actions and the retired-VRF-
subscription recovery are the only vault-owner powers
that reach beyond the vault's own position, and only narrowly: they act on *charity residual* on a
contract already post-gameOver and
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

### 5. ENS reverse registrar — optional, constructor-only, zero authority

**Who:** the `ENS_REVERSE_REGISTRAR` constant in `ContractAddresses.sol`. **It is `address(0)` in the
frozen subject**, so in the audited tree the call site is unreachable dead code; a mainnet/Base
deployment patches in the L1 `ReverseRegistrar` or Base's `L2ReverseRegistrar` (the `setName(string)`
selector is shared).

**Powers:** none over the protocol. Seventeen player-facing contracts — the fifteen standalone
deployments plus the vault's two share-class tokens (which take their name as a constructor
argument) — make **one** best-effort `setName("<label>.degenerus.eth")` low-level call from their
own constructor to register their ENS reverse name. The return value is deliberately discarded so a
missing/hostile/reverting registrar can never revert a deployment.

**Bounds:** constructor-only (unreachable after deploy), no state read from it, no value sent, no
storage written from its response. A hostile registrar can at most refuse to name the contracts or
publish a misleading reverse record off-protocol — it cannot affect game state, funds, or access
control. This is the only address in the system that is *not* protocol-controlled, and it is why the
raw-selector gate carries an explicit justification comment at each of the 16 call sites.

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
  `claimFoilMatchMany` (each settled win credits its own pack owner; a non-claimable tuple *at index
  0* reverts `StaleBatch` so a second sender handed an already-swept list fails in simulation instead
  of paying to walk it — later non-claimable tuples are still skipped), `sDGNRS.claimRedemption` /
  `claimRedemptionMany` during a live game (both halves of the rolled ETH route to the GAME — the
  direct half into the claimant's *gated* claimable, the lootbox half resolved to the claimant),
  ticket settlement, and the advance crank all credit the *resolved owner/contract* — the caller can
  never redirect the value to itself.
- **Post-gameOver push exception (gated).** Once the game is over, `sDGNRS.claimRedemption`
  direct-*pushes* ETH to `player`, so it narrows to `player` or an operator `player` approved on the
  GAME; `claimRedemptionMany` reverts `Unauthorized` post-gameOver (use the single self-claim). Same
  rule, applied to a push instead of a credit. `subscribe` and the idle `mineFlip` crank likewise
  close post-gameOver (`GameOver()` / `NoWork()`), except that `mineFlip` still runs a pending 30-day
  final sweep.
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
