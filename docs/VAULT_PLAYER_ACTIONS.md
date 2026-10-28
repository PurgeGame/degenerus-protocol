# Vault player controls

The [DGVE owner executor](OWNER_GOVERNANCE.md) calls
`vault.playerAction(target, data, ethValue)` to perform player actions as the Vault. It does so
for a proposal approved by **more than 50.1% of live DGVE supply**, or for a holder or delegate
who controls that majority through `directAction`
([Direct Vault gameplay](OWNER_GOVERNANCE.md#direct-vault-gameplay)). No other caller can reach it.
`data` is the destination's normal ABI-encoded function call. `ethValue` is ETH
drawn from the Vault in addition to the transaction's `msg.value`. Return values
are returned as ABI-encoded `bytes`; destination reverts propagate unchanged. A target or
selector outside the allowlist reverts `UnsupportedPlayerAction`. Each call emits
`PlayerAction(operator, target, selector, value)`.

Before game over, the Vault can hold native ETH, stETH, Game-side claimable
winnings and prepaid AFKing funding. These are different locations: `ethValue`
spends only native ETH already held by the Vault. Purchases can instead use the
Game's claimable/combined payment modes; claims and prepaid-funding withdrawals
can bring ETH back to the Vault while the game is live. Calling Game
`claimWinningsStethFirst()` prefers stETH, so it does not guarantee a native ETH
balance. The restricted Degenesis budget uses `vault.spendDegenesis` exclusively.

For calls that support a self-account shorthand, **ID 0 means the Vault**, not
the DGVE holder. Funding deposits require an explicit beneficiary ID (Vault = 1).
Explicit IDs still require the destination's normal authorization, so the Vault can also
act for accounts it owns or is approved for. Claim proceeds follow the underlying
account's payee rules. The transaction caller gains no power over unrelated IDs.

Vault-owned smurfs use that same route: encode the smurf's explicit ID for
purchases, account settings, bets and claims supported by the destination.
`sweepAccounts` also collects proceeds from acquired account families. Ownership
is checked at execution, including children that have been seized separately.
Wallet-wide functions without an account-ID argument still act on the Vault wallet.

## Available actions

| Target | Player actions reachable through `playerAction` |
| --- | --- |
| Game | Tickets, boxes, foil packs, FLIP tickets, Degenesis boxes, whale/lazy/deity pass purchases, Degenerette, mining, reverseFlip, decurse, smite, deity boons, smurf creation, operator approvals, acquired-account sweeps |
| Game subscriptions and claims | AFKing pause/resume/quantity and funding; full/partial ETH claims or stETH-first claims; AFKing FLIP, Bingo, dead-VRF, foil matches, golden tickets, whale passes, affiliate DGNRS |
| Coinflip / FLIP | Deposits, banked winnings, partial carry withdrawal, auto-rebuy and take-profit settings, decimator burns |
| Craps | Boards, custom battle creation/entry/closing, slip amendments, bonus window/day entries, pass reservations, future days, normal-to-high conversion, reserved-day/window upgrades |
| Parimutuel | Growth bets |
| WWXRP | Reward withdrawals, acquired-account collection, burn-game entries and claims |
| sDGNRS / DGNRS | Native/wrapped burns, redemption claims, vesting and year sweep |
| Affiliate / Jackpots | Create a Vault-owned referral code, referral registration, affiliate claims, BAF consolation claims |
| AFKing seat token | Restyle, approve operators (seats move with `sweepNft`) |
| GNRUS | Charity votes and GNRUS burns |
| Admin | `donateVrf` (native ETH VRF subscription funding) |

For example, the approved transaction below buys a foil pack with 0.1 ETH from Vault reserves. The executor makes this Vault call, from a proposal or `directAction`; a holder cannot call the Vault directly:

```solidity
vault.playerAction(
    GAME,
    abi.encodeCall(
        IDegenerusGame.purchaseOrderFor,
        (0, 0, 0, bytes32(0), MintPaymentKind.DirectEth, true)
    ),
    0.1 ether // A foil pack costs 10 tickets at the active level's price (0.1 ETH at 0.01 ETH per ticket); normal payment rules apply.
);
```

Ordinary gameplay uses `playerAction`; the Vault has no per-action gameplay wrappers.
Callers encode the destination ABI and decode returned `bytes` where
needed. Dedicated Vault controls cover restricted Degenesis spending, capped
DGNRS unwrapping, WWXRP and AFKing seat minting, Craps comp batches/donations and
delegate budgets, foreign-token/NFT sweeps, liquidation fallback settings, and
share redemption. Their privileged destination selectors are excluded from
`playerAction`, so each budgeted operation has one route. Approved Game operators can
use explicit account ID 1; that approval does not grant access to
`playerAction` or ETH held directly by the Vault. Such approvals persist across a
change of DGVE ownership; a later owner approval (proposal or `directAction`) revokes any
of them through `playerAction`.

## Rules

The fixed allowlist in `contracts/libraries/VaultPlayerActions.sol` checks both
the destination and selector. Calls use ordinary `CALL`, never `delegatecall`.
There is no configurable target or selector list. Arbitrary calls, stETH transfers
or approvals, direct FLIP allowance minting, and internal settlement hooks are
outside this entry point. DGVF and DGVE redemption paths retain their accounting.
Player actions can spend or risk Vault backing.

Destination restrictions that apply:

- Vault AFKing is box-only, quantity 0 pauses its permanent seat, and quantity 1–8
  resumes/changes it. The normal AFKing timing gates still apply.
- The Vault never borrows: `borrow` and `clearDebtNow` are not on the allowlist. Its protocol
  deity cannot manually issue boons.
  The Vault already owns a deity pass, so purchasing a second remains prohibited.
- The Vault's referral is already assigned permanently; it cannot replace it.
- VRF coordinator-swap proposals and votes are excluded: `sDGNRS.votingSupply()` excludes
  the Vault's treasury allocation. Counting that balance as votes would violate
  the governance denominator. The DGVE executor retains the Admin owner proposal path. Holders retain
  community voting rights from their personal eligible sDGNRS holdings.
- Craps custom battle creation requires creator authorization. An owner proposal
  can grant that to the Vault with `CrapsBattle.setBattleCreator(VAULT, true)`.
- Normal RNG/day locks, game-over restrictions, prices, quotas, balances,
  claim existence and voting eligibility are enforced at the destination.

Controls that check `isVaultOwner(msg.sender)` are called **by the governance
executor** at their own target address: Game thresholds/Thanos/smurf allowances/ETH-to-stETH staking,
Craps creator permissions, WWXRP mint scale/trusted minters, GNRUS charity/recovery
controls, and Admin owner operations. Permissionless maintenance and cache/identity
helpers can likewise be called externally without impersonating the Vault.

## Verification

`test/fuzz/VaultPlayerActions.t.sol` exercises real payment/identity routes,
authorization, timing restrictions, rejection of system hooks and protected-token
calls, return values and revert propagation. The other `test/fuzz/Vault*.t.sol` suites
cover the dedicated controls and share accounting.

After compiling the focused Foundry suites, run:

```sh
node scripts/check-vault-player-actions.js
```

This checks every allowed signature against compiled ABIs, requires every other
mutable method on those targets to have an explicit classification, confirms the
Vault ABI has no per-action gameplay wrappers, detects
excluded-method selector collisions, and checks the Vault's deployment size.
